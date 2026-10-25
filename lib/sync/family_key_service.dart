import 'dart:convert';

import 'package:cryptography/cryptography.dart'
    show KeyPairType, SecretBoxAuthenticationError, Sha256, SimplePublicKey;
import 'package:flutter/foundation.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/current_family_store.dart';
import '../data/local/local_user.dart';
import '../data/local/member_public_key_store.dart';
import '../models/family_member.dart';
import 'sync_outbox.dart';
import 'sync_puller.dart' show ApiSyncPullPort, SyncPullPort;
import 'sync_scheduler.dart' show ApiSyncPushPort, SyncPushPort;

/// 家庭数据密钥 F 的生成与包裹分发（三期 8.4，design.md D13）。
///
/// - F 生成权：家庭创建者（role=admin）首次门控通过且本机无 F 时
///   生成一把 32 字节随机 F，per-成员密封盒包裹后逐条推送 fkey 记录。
///   多把 F 并存会导致部分成员密文互解不通，生成权唯一给 admin
///   （现实中创建者先开同步是压倒性主流；admin 不开同步的家庭成员
///   共享数据不可用是诚实语义，由 8.2 休眠标记给出明确预期）。
/// - 包裹记录：recordType=familyKeyWrap、id=fk-<sha256(familyId:
///   forUserId) 截 32hex>（35 字符，直拼雪花 ID 会超服务端 36 上限）、
///   payload 用 forUserId 的 vault 传输密钥加密（与 vaultDoc 同机制，
///   服务端零明文）；F 机密性由密封盒保证——其他成员拉到也解不出。
/// - 分发触发：每轮同步对比「成员列表 vs 云端 fkey 记录」（recordId
///   精确探测，每成员 1 RTT），缺失即包裹推送；不要求邀请人在线，
///   任何持有 F 且在线的成员可为新成员补包裹（幂等：记录已存在跳过）。
/// - 成员公钥：从 MemberPublicKeyStore 查（vaultDoc 同步到达时登记），
///   缺公钥的成员本轮跳过、下轮自动补。
class FamilyKeyService {
  FamilyKeyService._();

  static const String kRecordType = 'familyKeyWrap';

  /// fkey 记录确定性 ID：同家庭同成员 upsert 单行覆盖
  /// 包裹记录 ID：`fk-` + sha256(familyId:forUserId) 前 32 位十六进制
  /// （35 字符）。不直拼 familyId+forUserId——雪花 ID 拼接会超过
  /// 服务端 sync_records.id 的 36 字符上限（fkey-19+1+19=44 被拒），
  /// 哈希确定性保证两端算出同一 ID（探测/幂等依赖）
  static Future<String> familyKeyRecordId(
      String familyId, String userId) async {
    final digest = await Sha256().hash(utf8.encode('$familyId:$userId'));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 32);
    return 'fk-$hex';
  }

  /// 每轮同步的 F 保障入口（调度器门控通过后调用）：
  /// 1. 本机无 F：仅 admin 生成并全员分发；普通成员静默等待
  /// 2. 本机有 F：为云端缺 fkey 记录的成员补包裹（新入伙成员）
  /// 3. 云端记录为墓碑（成员互救重置后主动废弃旧包裹）：视为缺失，
  ///    用当前公钥重包裹推送（version 严格高于墓碑，LWW 覆盖）——
  ///    公钥变化检测重包裹的机制基础（8.6 互救）
  ///
  /// 全程尽力而为：任何异常静默下轮重试，不阻断业务同步。
  /// [members] 为当前家庭成员列表（含 role）；[membersPort]/[pushPort]
  /// 可注入测试。
  static Future<void> ensureDistributed({
    required List<({String id, int role})> members,
    KeyVault? vault,
    SyncPushPort? pushPort,
    SyncPullPort? pullPort,
    Future<String?> Function()? currentFamilyId,
  }) async {
    final vault_ = vault ?? VaultProvider.vault;
    try {
      final me = await LocalUser.load();
      if (me == null) return;
      final familyId =
          await (currentFamilyId ?? CurrentFamilyStore.get)();
      if (familyId == null || familyId.isEmpty) return;
      if (!vault_.isUnlocked) return;

      var familyKey = await vault_.getFamilyKey(familyId);

      // 本机无 F：仅 admin 有生成权
      if (familyKey == null) {
        final isAdmin = members.any((m) =>
            m.id == me.id && m.role == FamilyMemberRole.admin);
        if (!isAdmin) return;
        familyKey = KeyVault.generateFamilyKey();
        await vault_.putFamilyKey(familyId, familyKey);
        debugPrint('[FamilyKey] admin 生成家庭密钥 F');
      }

      // 为云端缺 fkey 记录（或墓碑态）的成员包裹（含我：换设备后
      // F 云端可恢复）
      for (final member in members) {
        final recordId = await familyKeyRecordId(familyId, member.id);
        final remote = await _remoteRecordState(
            pullPort, familyId, recordId);
        // 正常记录跳过；无记录 or 墓碑（互救重置废弃的旧包裹）补
        final needsWrap = remote == null || remote.deleted == true;
        if (!needsWrap) continue;
        // 重包裹必须严格高于云端墓碑版本（LWW 覆盖）
        final nextVersion = (remote?.version ?? 0) + 1;
        final ok = await _wrapAndPush(
          pushPort: pushPort,
          vault: vault_,
          familyId: familyId,
          familyKey: familyKey,
          forUserId: member.id,
          version: nextVersion,
        );
        if (ok) {
          debugPrint('[FamilyKey] 已为成员 ${member.id} 分发包裹 v$nextVersion');
        }
      }
    } catch (e) {
      debugPrint('[FamilyKey] 分发跳过，下轮重试: $e');
    }
  }

  /// 自身包裹探测送达（8.4 缺陷修复）：本机无 F 时用 recordId 精确
  /// 拉取自身 fkey（不走游标分页——包裹记录为 epoch 时间戳，在已
  /// 推进的游标之前，增量拉取永远够不到；「后开启成员首拉错过包裹、
  /// F 永久失联」的洞），拉到即本人传输密钥解密、私钥解密封盒、
  /// F 落库。
  ///
  /// 返回 true = 本轮首获 F（调用方据此做存量重密封 + 重置拉取游标
  /// 全量重拉——此前无 F 被跳过的历史密文以家庭 key 解开入库）。
  /// 覆盖场景：普通成员后开启云备份（admin 补包裹后送达）、admin
  /// 换设备（vault 云端恢复同一私钥，解开自包裹恢复同一把 F，避免
  /// 误生成新 F 裂脑）。墓碑态/解密失败等待重包裹，返回 false。
  /// 探测应在 ensureDistributed 之前调用：先恢复 F 再谈生成/分发。
  static Future<bool> ensureOwnFamilyKey({
    KeyVault? vault,
    SyncPullPort? pullPort,
    Future<String?> Function()? currentFamilyId,
  }) async {
    final vault_ = vault ?? VaultProvider.vault;
    try {
      final me = await LocalUser.load();
      if (me == null) return false;
      final familyId =
          await (currentFamilyId ?? CurrentFamilyStore.get)();
      if (familyId == null || familyId.isEmpty) return false;
      if (!vault_.isUnlocked) return false;
      if (await vault_.getFamilyKey(familyId) != null) return false;

      final page = await (pullPort ?? ApiSyncPullPort()).pull(familyId, null,
          null,
          recordId: await familyKeyRecordId(familyId, me.id));
      final records =
          (page['records'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (records.isEmpty) return false;
      final record = records.first;
      if ((record['deleted'] as num?)?.toInt() == 1 ||
          record['deleted'] == true) {
        return false; // 墓碑态：等待重包裹
      }

      Map<String, dynamic> payload;
      try {
        payload = await SyncOutbox.decryptRecord(
            KeyVault.vaultTransportKey(me.id), record);
      } on SecretBoxAuthenticationError {
        return false; // 解不开（数据异常）：等待重包裹
      }
      if (payload['forUserId'] != me.id) return false;
      // 墓碑 payload（无包裹字段）同样按等待处理
      if (payload['ephemeralPubKey'] == null ||
          payload['wrappedF'] == null) {
        return false;
      }
      final familyKey = await vault_.openFamilyKeyWrap(
        ephemeralPubKeyBase64: payload['ephemeralPubKey'] as String,
        wrappedFBase64: payload['wrappedF'] as String,
      );
      await vault_.putFamilyKey(familyId, familyKey);
      debugPrint('[FamilyKey] 自身包裹送达，F 已落库（首获，触发全量重拉）');
      return true;
    } catch (e) {
      debugPrint('[FamilyKey] 自身 fkey 探测跳过，下轮重试: $e');
      return false;
    }
  }

  /// 互救重置流（8.6）：忘者重置密钥后调用——废弃云端自己的旧包裹
  /// （旧公钥包裹份新私钥解不开），推墓碑标记，持有 F 的成员下轮
  /// 探测到墓碑即用新公钥重包裹。云端无记录（从未分发）时 no-op。
  static Future<void> requestRewrapAfterReset({
    SyncPushPort? pushPort,
    SyncPullPort? pullPort,
    Future<String?> Function()? currentFamilyId,
  }) async {
    try {
      final me = await LocalUser.load();
      if (me == null) return;
      final familyId =
          await (currentFamilyId ?? CurrentFamilyStore.get)();
      if (familyId == null || familyId.isEmpty) return;

      final recordId = await familyKeyRecordId(familyId, me.id);
      final remote =
          await _remoteRecordState(pullPort, familyId, recordId);
      if (remote == null || remote.deleted == true) return; // 无需墓碑

      // 墓碑：仅机制字段参与（id/version/updated_at/deleted），
      // payload 置空——传输密钥加密下服务端仍零明文
      final row = SyncPendingRow(
        recordType: kRecordType,
        id: recordId,
        version: remote.version + 1,
        // 用真实时间戳：确保 LWW 覆盖存量 + 优先于业务记录被
        // 老成员尽早拉到（分页排序在前）
        updatedAt: DateTime.now().toUtc(),
        deleted: true,
        familyId: familyId,
        payload: <String, dynamic>{
          'recordType': kRecordType,
          'familyId': familyId,
          'forUserId': me.id,
        },
      );
      final record = await SyncOutbox.encryptRecord(
          KeyVault.vaultTransportKey(me.id), row);
      await (pushPort ?? ApiSyncPushPort()).push(familyId, [record]);
      debugPrint('[FamilyKey] 互救：已废弃旧包裹（墓碑），等待重包裹');
    } catch (e) {
      debugPrint('[FamilyKey] 互救墓碑推送跳过，下轮重试: $e');
    }
  }

  /// recordId 精确探测云端 fkey 记录状态（7.10 服务端扩展，1 次 RTT）。
  /// 返回 null = 无记录；记录的 version/deleted 为服务端明文机制字段，
  /// 无需解密。网络失败返回「正常存在」占位（宁可少推、由幂等 upsert
  /// 收敛，不重复生成不同包裹内容）。
  static Future<({int version, bool deleted})?> _remoteRecordState(
    SyncPullPort? pullPort,
    String familyId,
    String recordId,
  ) async {
    try {
      final page = await (pullPort ?? ApiSyncPullPort())
          .pull(familyId, null, null, recordId: recordId);
      final records =
          (page['records'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (records.isEmpty) return null;
      final row = records.first;
      return (
        version: (row['version'] as num?)?.toInt() ?? 1,
        deleted: (row['deleted'] as num?)?.toInt() == 1 ||
            row['deleted'] == true,
      );
    } catch (_) {
      return (version: 1, deleted: false); // 探测失败按正常存在处理
    }
  }

  /// 为单个成员密封盒包裹 F 并推送 fkey 记录。
  /// [version] 记录 LWW 版本：首次包裹 1，互救重包裹严格高于墓碑版本。
  /// 公钥未到达（vaultDoc 未同步）返回 false，下轮重试。
  static Future<bool> _wrapAndPush({
    required SyncPushPort? pushPort,
    required KeyVault vault,
    required String familyId,
    required Uint8List familyKey,
    required String forUserId,
    required int version,
  }) async {
    final pubBase64 = await MemberPublicKeyStore.get(forUserId);
    if (pubBase64 == null) return false;
    final pubBytes = base64Decode(pubBase64);
    final recipientPublicKey =
        SimplePublicKey(pubBytes, type: KeyPairType.x25519);
    final sealed = await KeyVault.sealFamilyKeyFor(
        familyKey: familyKey, recipientPublicKey: recipientPublicKey);

    final row = SyncPendingRow(
      recordType: kRecordType,
      id: await familyKeyRecordId(familyId, forUserId),
      version: version,
      // 与 vaultDoc 同策略：机制记录固定极老值，不干扰业务游标分页
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      deleted: false,
      familyId: familyId,
      payload: <String, dynamic>{
        'recordType': kRecordType,
        'familyId': familyId,
        'forUserId': forUserId,
        'ephemeralPubKey': sealed.ephemeralPubKey,
        'wrappedF': sealed.wrappedF,
      },
    );
    // payload 用 forUserId 的传输密钥加密（仅本人可解，与 vaultDoc 同）
    final record = await SyncOutbox.encryptRecord(
        KeyVault.vaultTransportKey(forUserId), row);
    await (pushPort ?? ApiSyncPushPort()).push(familyId, [record]);
    return true;
  }
}
