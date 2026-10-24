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
        updatedAt: DateTime.now(),
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

  /// 登录后自动探测恢复（6.8）：本机未配置时从云端拉取 vault 导入。
  /// 返回是否拉到并导入（false = 云端无 vault / 已配置 / 失败静默）。
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
      if (await vault_.isConfigured()) return false;
      final cloudDoc = await pullVaultDoc(
          port: port, userId: userId, familyId: familyId);
      if (cloudDoc == null) return false;
      return await vault_.importVaultDoc(cloudDoc);
    } catch (_) {
      // 网络失败等：下次登录/开 App 再探测，静默
      return false;
    }
  }

  /// 专项拉取云端 vault 文档（新设备恢复流）：逐页拉取、只处理 vault
  /// 记录（按 userId 派生传输密钥解密；业务记录密钥不同天然解不开，
  /// 静默跳过）、找到即返回明文 vault JSON。游标现算不落盘（不动
  /// SyncCursorStore——业务数据的增量游标由恢复完成后的全量同步管理）。
  ///
  /// 返回 null：云端无本账号 vault（从未开启过备份）。
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
    int? cursorTime;
    String? cursorId;
    while (true) {
      final page = await pullPort.pull(family, cursorTime, cursorId);
      final records =
          (page['records'] as List? ?? const []).cast<Map<String, dynamic>>();
      for (final record in records) {
        if (record['id'] != vaultRecordId(id)) continue;
        try {
          final payload =
              await SyncOutbox.decryptRecord(transportKey, record);
          if (payload['recordType'] == kRecordType) {
            return payload;
          }
        } catch (_) {
          // AAD/密钥不匹配（历史版本或异常数据）跳过
        }
      }
      if (page['hasMore'] != true) return null;
      cursorTime = page['nextCursorTime'] as int;
      cursorId = page['nextCursorId'] as String;
    }
  }
}
