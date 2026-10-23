import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/crypto_primitives.dart';
import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/backup_flag_store.dart';
import '../data/local/db_provider.dart';
import '../services/api/api_client.dart';
import 'sync_outbox.dart';

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

/// 同步调度器（tasks.md 7.3）：联网批量推送发件箱。
///
/// 触发方式为写路径 fire-and-forget（不阻塞本地操作）：
/// - 单飞：运行中再触发仅记重跑标记，结束后补跑一轮（天然防抖合并）
/// - 门控：备份开关开 → 已登录 → 密钥已解锁（任一不满足静默跳过，
///   标记保留；解锁/登录后的下一次写操作触发自动补推）
/// - 失败重试不丢：任何推送异常终止本轮、标记保留，靠下次触发重推
/// - 分批：每家庭每批 ≤ [batchSize]（对齐服务端 500 上限）；
///   跨家庭记录不能同批（服务端按家庭校验归属）
class SyncScheduler {
  SyncScheduler({
    AppDatabase? db,
    SyncPushPort? port,
    KeyVault? vault,
    Future<bool> Function()? isSignedIn,
    this.batchSize = 500,
  })  : _db = db ?? Db.database,
        _port = port ?? ApiSyncPushPort(),
        _vault = vault ?? VaultProvider.vault,
        _isSignedIn = isSignedIn ?? _defaultSignedIn;

  static Future<bool> _defaultSignedIn() async =>
      await ApiClient().getToken() != null;

  static SyncScheduler? _instance;

  /// 应用级单例：门面写路径统一经此触发
  static SyncScheduler get instance => _instance ??= SyncScheduler();

  final AppDatabase _db;
  final SyncPushPort _port;
  final KeyVault _vault;
  final Future<bool> Function() _isSignedIn;
  final int batchSize;

  bool _running = false;
  bool _rerun = false;

  /// 尽力而为推送：调用方一律 fire-and-forget（unawaited），
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
        await _pushAll();
      } finally {
        _running = false;
      }
      if (_rerun) {
        _rerun = false;
        await maybePush();
      }
    } catch (e) {
      debugPrint('[SyncScheduler] 推送中断，发件箱标记保留待重试: $e');
    }
  }

  Future<void> _pushAll() async {
    if (!await BackupFlagStore.isEnabled()) return;
    if (!await _isSignedIn()) return;
    final keyPair = _vault.unlockedKeyPair;
    if (keyPair == null) return;

    final rows = await SyncOutbox.collectAll(_db);
    if (rows.isEmpty) return;

    final privateKey =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final dataKey = CryptoPrimitives.hkdfSha256(
      privateKey,
      info: CryptoPrimitives.kSyncDataKeyInfo,
    );

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
        final done = await _port.push(entry.key, records);
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
