import 'package:flutter/foundation.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/current_family_store.dart';
import '../data/local/local_user.dart';
import 'sync_outbox.dart';
import 'sync_scheduler.dart' show ApiSyncPushPort, SyncPushPort;
import 'sync_puller.dart' show ApiSyncPullPort, SyncPullPort;

/// vault 云端托管服务（tasks.md 6.7 补位）：vault 文档（口令包裹的
/// X25519 私钥 + 恢复码包裹份）作为一种特殊同步记录走现有 sync 通道，
/// 服务端零改动、只见密文。解决卸载重装/换设备后密钥体系断裂——
/// spec.md L57「新设备登录输口令后全量恢复」的完整闭环。
///
/// 通道选择：vault 是账号级数据，借「当前家庭」通道传输（同学习表
/// 先例）；每轮同步幂等推送当前家庭，切家庭后自动补位。
class VaultSyncService {
  VaultSyncService._();

  static const String kRecordType = 'vaultDoc';

  /// vault 记录的确定性 ID：同账号同家庭 upsert 单行覆盖。
  static String vaultRecordId(String userId) => 'vault-$userId';

  /// 推送当前 vault 文档到当前家庭通道（幂等 upsert，LWW）。
  /// 未配置 vault / 无家庭上下文 / 网络失败均静默跳过（下轮重试）。
  /// [port] 与 [familyId] 可注入测试。
  static Future<void> pushVault({
    SyncPushPort? port,
    KeyVault? vault,
    Future<String?> Function()? currentFamilyId,
  }) async {
    final vault_ = vault ?? VaultProvider.vault;
    try {
      if (!await vault_.isConfigured()) return;
      final userId = await LocalUser.load();
      if (userId == null) return;
      final familyId = await (currentFamilyId ?? CurrentFamilyStore.get)();
      // CurrentFamilyStore.get 无家庭时返回 ''（非空签名）
      if (familyId == null || familyId.isEmpty) return;

      final doc = await vault_.exportVaultDoc();
      final transportKey = KeyVault.vaultTransportKey(userId.id);
      final row = SyncPendingRow(
        recordType: kRecordType,
        id: vaultRecordId(userId.id),
        version: (doc['syncVersion'] as int? ?? 1),
        // vault 记录固定极老 updated_at（epoch=1ms）：游标分页中永远
        // 排最前，对业务数据全量拉取无干扰。注：探测已改走 recordId
        // 精确拉取（7.10），不再依赖排序位置；LWW 仲裁 version 不同时
        // 只比 version（syncVersion 严格递增），updated_at 不参与仲裁。
        // 注意同 version 的 epoch 推送会被服务端「updated_at 新者胜」
        // 拒绝覆盖存量记录——存量真实时间戳记录需等 syncVersion 递增
        // 的下一次推送才会收敛为 epoch 值。
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
        deleted: false,
        familyId: familyId,
        payload: <String, dynamic>{...doc, 'recordType': kRecordType},
      );
      final record = await SyncOutbox.encryptRecord(transportKey, row);
      await (port ?? ApiSyncPushPort()).push(familyId, [record]);
    } catch (e) {
      // 尽力而为：下轮同步重推（幂等），不打断调用方。
      // 含存储层异常（如单测环境无 secure storage 插件）——门控本身
      // 的探测失败不得中断业务数据推送
      debugPrint('[VaultSync] vault 推送跳过，下轮重试: $e');
    }
  }

  /// 登录后自动探测恢复（6.8 + 6.9）：本机未配置时从云端拉取 vault 导入；
  /// 随后尝试自动解锁（6.9 自动解锁份：不卸载免口令，重装/换设备无
  /// 自动解锁份保持锁定由 UI 弹口令框）。返回是否拉到并导入
  /// （false = 云端无 vault / 已配置 / 失败静默）。
  /// 免口令：传输密钥 = HKDF(userId)，登录即得——重装/换设备后
  /// 开关状态（enabled 字段随 vault 漫游）在登录瞬间即恢复。
  static Future<bool> restoreFromCloud({
    SyncPullPort? port,
    KeyVault? vault,
    String? userId,
    String? familyId,
  }) async {
    final vault_ = vault ?? VaultProvider.vault;
    try {
      if (await vault_.isConfigured()) {
        // 本机已配置（不卸载场景）：自动解锁恢复解锁态，同步全无感；
        // 无自动解锁份（老版本升级首启）保持锁定，走口令路径补写
        await vault_.autoUnlock();
        return false;
      }
      final cloudDoc = await pullVaultDoc(
          port: port, userId: userId, familyId: familyId);
      if (cloudDoc == null) return false;
      final imported = await vault_.importVaultDoc(cloudDoc);
      // 重装/换设备导入成功：自动解锁（重装后无自动解锁份，静默保持
      // 锁定，由首页弹口令框完成首次恢复，口令解锁后重建自动解锁份）
      if (imported) await vault_.autoUnlock();
      return imported;
    } catch (_) {
      // 网络失败等：下次登录/开 App 再探测，静默
      return false;
    }
  }

  /// 专项拉取云端 vault 文档（新设备恢复流）：recordId 精确拉取
  /// vault-<userId> 单条记录（服务端 7.10 扩展，1 次 RTT——旧方案按
  /// updated_at ASC 逐页扫全量业务数据，万条数据数十页、重装后开关
  /// 状态恢复慢的根因），按 userId 派生传输密钥解密返回明文 vault JSON。
  ///
  /// 返回 null：云端无本账号 vault（从未开启过备份）/ 解密失败。
  static Future<Map<String, dynamic>?> pullVaultDoc({
    SyncPullPort? port,
    String? userId,
    String? familyId,
  }) async {
    final id = userId ?? (await LocalUser.load())?.id;
    if (id == null) return null;
    final family = familyId ?? await CurrentFamilyStore.get();
    if (family.isEmpty) return null;

    final transportKey = KeyVault.vaultTransportKey(id);
    final pullPort = port ?? ApiSyncPullPort();
    final page = await pullPort.pull(family, null, null,
        recordId: vaultRecordId(id));
    final records =
        (page['records'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (final record in records) {
      if (record['id'] != vaultRecordId(id)) continue;
      try {
        final payload = await SyncOutbox.decryptRecord(transportKey, record);
        if (payload['recordType'] == kRecordType) {
          return payload;
        }
      } catch (_) {
        // AAD/密钥不匹配（历史版本或异常数据）视为无 vault
      }
    }
    return null;
  }
}
