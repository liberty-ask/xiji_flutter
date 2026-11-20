import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/backup_switch_store.dart';
import '../data/local/local_family_cache.dart';
import '../data/local/local_user.dart';
import 'sync_cursor_store.dart';
import 'sync_outbox.dart';
import 'sync_scheduler.dart' show ApiSyncPushPort, SyncPushPort;

/// 家庭维度备份开关的云端漫游（family-scoped-backup-switch）。
///
/// 开关状态作为 bksw 记录走现有 sync 通道（服务端零改动、零明文）：
/// - 记录 ID `bksw-<sha256(familyId:userId) 前16hex>`（21 字符，满足
///   服务端 ≤36 上限，对齐 fkey 短前缀+哈希先例；确定性 ID 支撑
///   幂等 upsert）
/// - version 每次切换递增（单写者，LWW 无多写者冲突）
/// - updated_at 真实时间戳（游标增量自然可达，无需 recordId 精确
///   探测——与 vault/fkey 的 epoch 方案语义相反）
/// - 传输密钥 HKDF(userId)：登录即得，多设备漫游免口令
///
/// 推送不受家庭业务门控（L2）约束：关闭动作的 bksw(false) 必须上云，
/// 否则重装/换设备后开关状态回弹为开。可靠性由脏标记保证：本地切换
/// 置脏，推送成功清除；每轮同步对全部脏家庭补位推送（账号级保障）。
class BackupSwitchService {
  BackupSwitchService._();

  static const String kRecordType = 'bksw';

  /// bksw 记录确定性 ID：同家庭同账号 upsert 单行覆盖。
  /// `bksw-` + sha256(familyId:userId) 前 16 位十六进制（21 字符），
  /// 不直拼 ID——雪花拼接会超服务端 sync_records.id 36 字符上限
  static Future<String> backupSwitchRecordId(
      String familyId, String userId) async {
    final digest = await Sha256().hash(utf8.encode('$familyId:$userId'));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 16);
    return 'bksw-$hex';
  }

  /// 推送单个家庭的开关状态（幂等）。version 为 0（从未切换）时
  /// 无状态可漫游，跳过。推送成功清除脏标记。任何异常静默（下轮
  /// 脏标记补位重试），不打断调用方。
  static Future<void> pushBackupSwitch({
    required String familyId,
    SyncPushPort? port,
  }) async {
    try {
      if (familyId.isEmpty) return;
      final user = await LocalUser.load();
      if (user == null) return;
      final version = await BackupSwitchStore.getVersion(familyId);
      if (version <= 0) return; // 无切换历史：默认关闭无需漫游
      final enabled = await BackupSwitchStore.isEnabled(familyId);
      final row = SyncPendingRow(
        recordType: kRecordType,
        id: await backupSwitchRecordId(familyId, user.id),
        version: version,
        updatedAt: DateTime.now().toUtc(),
        deleted: false,
        familyId: familyId,
        payload: <String, dynamic>{
          'recordType': kRecordType,
          'familyId': familyId,
          'userId': user.id,
          'enabled': enabled,
        },
      );
      final record = await SyncOutbox.encryptRecord(
          KeyVault.vaultTransportKey(user.id), row);
      await (port ?? ApiSyncPushPort()).push(familyId, [record]);
      await BackupSwitchStore.clearDirty(familyId);
    } catch (e) {
      // 尽力而为：脏标记保留，下轮同步补位重推
      debugPrint('[BackupSwitch] bksw 推送跳过，下轮重试: $e');
    }
  }

  /// 每轮同步的账号级保障入口：对全部脏家庭逐个补位推送。
  /// 家庭间相互隔离，单家庭失败不影响其余家庭。
  static Future<void> pushAllDirty({SyncPushPort? port}) async {
    for (final familyId in await BackupSwitchStore.dirtyFamilyIds()) {
      await pushBackupSwitch(familyId: familyId, port: port);
    }
  }

  /// 重开自愈：家庭备份开关 off→on 跃迁时清除该家庭的拉取游标，
  /// 下轮同步走全量重拉。依据：fkey 记录固定 epoch 排最前，全量
  /// 重拉必达当前密钥包裹（含关闭期间轮换后的新 F，ingest 无条件
  /// 覆盖落库、puller 每页刷新密钥），关闭期间的数据随之补齐；
  /// 增量路径则永远够不到 epoch 记录。幂等：无游标时清空为 no-op
  /// （首次开启本就无游标，全量拉取天然覆盖）。
  static Future<void> clearCursorOnReenable(String familyId) async {
    final user = await LocalUser.load();
    await SyncCursorStore.clear(familyId, user?.id ?? '');
  }

  /// 存量迁移（family-scoped-backup-switch）：老账号级开关
  /// （vault.enabled，已退役为只读迁移源）一次性铺到该账号全部
  /// 已加入家庭的开关存储，原值为开启的家庭各推一条 bksw 上云。
  /// 幂等：标记 `backup_flag_migrated@<userId>` 落盘后不再执行；
  /// 推送失败由脏标记+下轮补位自愈；家庭缓存未就绪（null）时
  /// 不落标记下轮重试，避免漏铺后加入庭。
  static Future<void> migrateLegacySwitch(
      {KeyVault? vault, SyncPushPort? port}) async {
    try {
      final user = await LocalUser.load();
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final marker = 'backup_flag_migrated@${user.id}';
      if (prefs.getBool(marker) == true) return;

      final vault_ = vault ?? VaultProvider.vault;
      if (await vault_.isConfigured()) {
        final doc = await vault_.exportVaultDoc();
        if (doc['enabled'] == true) {
          final families = await LocalFamilyCache.load();
          if (families == null) return; // 缓存未就绪：下轮重试
          for (final family in families) {
            // 仅铺尚无切换历史的家庭（version 0），避免覆盖用户
            // 升级后已手动切换的新状态
            if (await BackupSwitchStore.getVersion(family.id) > 0) continue;
            await BackupSwitchStore.setEnabled(family.id, true);
            await pushBackupSwitch(familyId: family.id, port: port);
          }
        }
      }
      await prefs.setBool(marker, true);
    } catch (e) {
      debugPrint('[BackupSwitch] 存量迁移跳过，下轮重试: $e');
    }
  }
}
