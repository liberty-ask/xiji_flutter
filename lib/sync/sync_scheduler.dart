import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/crypto_primitives.dart';
import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/current_family_store.dart';
import '../data/local/db_provider.dart';
import '../services/api/api_client.dart';
import 'sync_outbox.dart';
import 'sync_puller.dart';
import 'vault_sync_service.dart';

/// 推送端口：按家庭推送一批记录，返回「使命完成」的记录 ID 集合
/// （accepted 与 rejected 均含——rejected 即服务端 LWW 仲裁已有更高
/// version，本地旧值无需再推）。测试注入假实现。
abstract class SyncPushPort {
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  );
}

/// 生产端口：走 ApiClient 调用 POST /v1/sync/push。
/// 网络失败 / 业务 code!=200 / 401 刷新失败均以异常上抛，
/// 由调度器按「失败保留标记待重试」处理。
class ApiSyncPushPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    final data = await ApiClient().post<Map<String, dynamic>>(
      '/v1/sync/push',
      data: <String, dynamic>{
        'familyId': familyId,
        'records': records,
      },
    );
    final done = <String>{};
    for (final item in (data['results'] as List? ?? const [])) {
      done.add((item as Map<String, dynamic>)['id'] as String);
    }
    return done;
  }
}

/// 同步调度器（tasks.md 7.3/7.4）：推-拉-对账循环。
///
/// 流程：门控 → 推送发件箱 → 拉取云端增量入库 → 补推
/// （拉取仲裁跳过的本地高版本记录，一轮收敛双向一致）。
///
/// 触发方式为写路径 fire-and-forget（不阻塞本地操作）：
/// - 单飞：运行中再触发仅记重跑标记，结束后补跑一轮（天然防抖合并）
/// - 门控：备份开关开 → 已登录 → 密钥已解锁（任一不满足静默跳过，
///   标记与游标保留；解锁/登录后的下一次触发自动补推）
/// - 失败重试不丢：任何环节异常终止本轮、标记与游标保留，
///   靠下次触发重推/重拉（LWW 幂等，重拉无害）
/// - 分批：每家庭每批 ≤ [batchSize]（对齐服务端 500 上限）；
///   跨家庭记录不能同批（服务端按家庭校验归属）
class SyncScheduler {
  SyncScheduler({
    AppDatabase? db,
    SyncPushPort? port,
    SyncPullPort? pullPort,
    KeyVault? vault,
    Future<bool> Function()? isSignedIn,
    Future<String?> Function()? currentFamilyId,
    SyncPuller? puller,
    this.batchSize = 500,
  })  : _injectedDb = db,
        _injectedPuller = puller,
        _pullPort = pullPort,
        _port = port ?? ApiSyncPushPort(),
        _vault = vault ?? VaultProvider.vault,
        _isSignedIn = isSignedIn ?? _defaultSignedIn,
        _currentFamilyId = currentFamilyId ?? CurrentFamilyStore.get;

  static Future<bool> _defaultSignedIn() async =>
      await ApiClient().getToken() != null;

  static SyncScheduler? _instance;

  /// 应用级单例：门面写路径统一经此触发
  static SyncScheduler get instance => _instance ??= SyncScheduler();

  final AppDatabase? _injectedDb;
  final SyncPuller? _injectedPuller;
  final SyncPullPort? _pullPort;
  final SyncPushPort _port;
  final KeyVault _vault;
  final Future<bool> Function() _isSignedIn;
  final Future<String?> Function() _currentFamilyId;
  final int batchSize;

  /// 当前库：注入（测试）优先；默认随 Db 单例动态取——Db.close()
  /// 重开新库后（登出/账号切换）自动指向新库，防止持有已关闭
  /// 旧库的引用导致同步静默失效。
  AppDatabase get _db => _injectedDb ?? Db.database;

  /// 拉取器：注入（测试）优先；否则每轮基于当前库新建（薄对象，
  /// 天然跟随 _db 动态指向，不缓存旧库引用）。
  SyncPuller get _puller => _injectedPuller ??
      SyncPuller(
        db: _db,
        port: _pullPort,
        currentFamilyId: _currentFamilyId,
      );

  bool _running = false;
  bool _rerun = false;

  /// 尽力而为同步：调用方一律 fire-and-forget（unawaited），
  /// 任何异常不出函数边界（后台任务的既定语义，真机日志可查
  /// debugPrint 输出）。
  Future<void> maybePush() async {
    try {
      if (_running) {
        _rerun = true;
        return;
      }
      _running = true;
      try {
        await _syncOnce();
      } finally {
        _running = false;
      }
      if (_rerun) {
        _rerun = false;
        await maybePush();
      }
    } catch (e) {
      debugPrint('[SyncScheduler] 同步中断，标记与游标保留待重试: $e');
    }
  }

  Future<void> _syncOnce() async {
    final dataKey = await _gate();
    if (dataKey == null) {
      debugPrint('[SyncScheduler] 门控未通过，本轮跳过');
      return;
    }
    debugPrint('[SyncScheduler] 门控通过，开始同步');
    // vault 托管补位（6.7）：每轮幂等推送最新 vault 到当前家庭通道，
    // 云端 upsert 覆盖——改口令/重置后下轮同步自动更新云端副本；
    // 新开启用户首轮同步即补上云端 vault。内部自吞异常，失败下轮重试
    await VaultSyncService.pushVault();
    await _pushAll(dataKey);
    await _puller.pullAll(dataKey);
    // 对账补推：拉取仲裁跳过的本地高版本记录（或推送环节部分
    // 失败遗留）推上去，一轮收敛；已推净则空转返回
    await _pushAll(dataKey);
    debugPrint('[SyncScheduler] 一轮同步完成');
  }

  /// 门控：备份开关 → 登录态 → 密钥解锁 → 派生数据密钥。
  /// 任一不满足返回 null（静默跳过，标记与游标保留）。
  /// 备份开关真值源 = vault.enabled（6.8：账号级，随 vault 云端漫游）。
  Future<Uint8List?> _gate() async {
    if (!await _vault.isBackupEnabled()) {
      debugPrint('[SyncScheduler] 门控跳过：备份开关未开');
      return null;
    }
    if (!await _isSignedIn()) {
      debugPrint('[SyncScheduler] 门控跳过：未登录');
      return null;
    }
    final keyPair = _vault.unlockedKeyPair;
    if (keyPair == null) {
      debugPrint('[SyncScheduler] 门控跳过：密钥未解锁');
      return null;
    }
    final privateKey = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    return CryptoPrimitives.hkdfSha256(privateKey,
        info: CryptoPrimitives.kSyncDataKeyInfo);
  }

  Future<void> _pushAll(Uint8List dataKey) async {
    final rows = await SyncOutbox.collectAll(_db, await _currentFamilyId());
    if (rows.isEmpty) {
      debugPrint('[SyncScheduler] 发件箱为空，无需推送');
      return;
    }

    // 按家庭分组推送（服务端按家庭整批校验，跨家庭不能同批）
    final byFamily = <String, List<SyncPendingRow>>{};
    for (final row in rows) {
      byFamily.putIfAbsent(row.familyId, () => <SyncPendingRow>[]).add(row);
    }

    for (final entry in byFamily.entries) {
      var start = 0;
      while (start < entry.value.length) {
        final batch =
            entry.value.skip(start).take(batchSize).toList(growable: false);
        final records = <Map<String, dynamic>>[];
        for (final row in batch) {
          records.add(await SyncOutbox.encryptRecord(dataKey, row));
        }
        debugPrint('[SyncScheduler] 推送家庭 ${entry.key} '
            '批次 ${start ~/ batchSize + 1}：${records.length} 条');
        final done = await _port.push(entry.key, records);
        debugPrint('[SyncScheduler] 服务端回执：${done.length} 条完成');
        final cleared =
            batch.where((row) => done.contains(row.id)).toList();
        if (cleared.isNotEmpty) {
          await SyncOutbox.clearPending(_db, cleared);
        }
        start += batch.length;
      }
    }
  }
}
