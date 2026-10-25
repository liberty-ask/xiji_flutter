import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:drift/drift.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/member_public_key_store.dart';
import 'family_key_service.dart';
import 'sync_outbox.dart';
import 'vault_sync_service.dart';

/// 单条云端记录的入库仲裁结果
enum IngestResult { inserted, updated, skipped }

/// 云端拉取记录的本地入库仲裁器（tasks.md 7.4 / 8.4）。
///
/// LWW 规则与服务端完全对齐（见 7.2）：
/// - 本地无该 id → 插入
/// - version 高者胜（云端高 → 覆盖本地；本地高 → 跳过，
///   本地未推送的更新数据不被云端旧值冲掉，标记保留待推）
/// - 同 version → updated_at 新者胜；完全相同 → 幂等跳过
/// - 墓碑与正常记录同规则：墓碑胜出即删除落库，正常记录胜出
///   不复活（只有更高 version 才能翻案）
/// - 云端覆盖写入的行 syncPending=false（云端权威数据无需回推）
///
/// 解密键序（8.4 D13）：家庭 dataKey（业务记录主键）→ 失败按记录
/// 前缀分流：vault-/fkey- 机制记录走传输密钥；普通业务记录回落
/// 个人 dataKey（存量个人密文）→ 仍失败按「不可读跳过」（其他成员
/// 未重密封的旧密文，本人无其个人 key；重密封后其重推覆盖可解），
/// 不再按损坏中断——家庭通道拉取不能被他人旧密文堵死。
class SyncIngest {
  SyncIngest(this._db, {KeyVault? vault, Future<String?> Function()? userId})
      : _vault = vault,
        _userId = userId;

  final AppDatabase _db;
  final KeyVault? _vault;

  /// vault 记录归属用户 ID 的惰性来源（生产走 LocalUser）。
  /// 拉到 vault 记录时用于派生传输密钥；null 则跳过该记录。
  final Future<String?> Function()? _userId;

  /// 解密并仲裁入库单条拉取记录。
  /// [familyDataKey] 家庭数据密钥（8.4 起业务记录主加密键，本机未获
  /// F 时为 null）；[personalDataKey] 个人数据密钥（存量密文回落键）。
  Future<IngestResult> applyRecord(
    Uint8List personalDataKey,
    Map<String, dynamic> record, {
    Uint8List? familyDataKey,
  }) async {
    final id = record['id'] as String;
    Map<String, dynamic>? payload;

    // 键序解密：家庭 key → 个人 key
    for (final key in [familyDataKey, personalDataKey]) {
      if (key == null) continue;
      try {
        payload = await SyncOutbox.decryptRecord(key, record);
        break;
      } on SecretBoxAuthenticationError {
        continue; // 试下一把键
      }
    }

    if (payload == null) {
      // 机制记录（传输密钥加密）：vault / fkey 特判
      if (id.startsWith('vault-')) {
        return _ingestVaultDoc(record);
      }
      if (id.startsWith('fk-')) {
        return _ingestFamilyKeyWrap(record);
      }
      // 其他成员未重密封的旧密文：本人无其个人 key，解不开是预期。
      // 跳过且游标照常推进（重密封方重推后版本更新可增量拉到可解版）。
      return IngestResult.skipped;
    }

    final recordType = payload['recordType'] as String;
    return switch (recordType) {
      SyncOutbox.kTypeTransaction => _applyTransaction(record, payload),
      SyncOutbox.kTypeCategory => _applyCategory(record, payload),
      SyncOutbox.kTypeBudget => _applyBudget(record, payload),
      SyncOutbox.kTypeCategoryRule => _applyCategoryRule(record, payload),
      VaultSyncService.kRecordType =>
        Future<IngestResult>.value(IngestResult.skipped),
      FamilyKeyService.kRecordType =>
        Future<IngestResult>.value(IngestResult.skipped),
      _ => throw ArgumentError('未知的同步记录类型: $recordType'),
    };
  }

  /// vaultDoc 记录：按文档归属者的传输密钥解密（id 内嵌 userId——
  /// 机制字段全家庭成员可知，他人 vaultDoc 也可解出 payload）→
  /// 公钥登记（MemberPublicKeyStore：无论归属是否本账号——其他
  /// 成员的 vaultDoc 拒收导入，但其公钥是 F 包裹分发的必需输入）
  /// → importVaultDoc LWW/归属校验（他人文档拒收导入）。
  /// vault 保密性由 Argon2id 口令包裹保证，payload 可见不破坏安全
  /// （零信任兼容，见 key_vault.dart 传输密钥注释）。
  Future<IngestResult> _ingestVaultDoc(
      Map<String, dynamic> record) async {
    final docUserId = (record['id'] as String).replaceFirst('vault-', '');
    Map<String, dynamic> vaultPayload;
    try {
      vaultPayload = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey(docUserId), record);
    } on SecretBoxAuthenticationError {
      return IngestResult.skipped; // 异常/残缺数据：静默跳过
    }
    final owner = vaultPayload['userId'] as String?;
    final docPublicKey = vaultPayload['publicKey'] as String?;
    if (owner != null && docPublicKey != null) {
      await MemberPublicKeyStore.register(owner, docPublicKey);
    }
    final adopted =
        await (_vault ?? VaultProvider.vault).importVaultDoc(vaultPayload);
    return adopted ? IngestResult.updated : IngestResult.skipped;
  }

  /// fkey 记录：本人传输密钥解 payload → 私钥解密封盒得 F 落库。
  /// 他人的包裹份（其传输密钥加密）解不开是预期，静默跳过——F 的
  /// 机密性由密封盒保证，他人份跳过不影响家庭通道推进。锁定期不可
  /// 达（拉取门控要求已解锁），异常静默跳过下轮再试。
  Future<IngestResult> _ingestFamilyKeyWrap(
      Map<String, dynamic> record) async {
    final userId = await (_userId?.call());
    if (userId == null) return IngestResult.skipped;
    Map<String, dynamic> payload;
    try {
      payload = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey(userId), record);
    } on SecretBoxAuthenticationError {
      return IngestResult.skipped; // 他人包裹份：解不开是预期，跳过
    }
    if (payload['forUserId'] != userId) return IngestResult.skipped;
    // 墓碑态（互救重置废弃的旧包裹，等新包裹在路上）：无包裹字段，
    // 静默跳过——重包裹份到达时按 updated_at 增量推进拉到
    if (payload['ephemeralPubKey'] == null ||
        payload['wrappedF'] == null) {
      return IngestResult.skipped;
    }
    try {
      final familyKey = await (_vault ?? VaultProvider.vault)
          .openFamilyKeyWrap(
        ephemeralPubKeyBase64: payload['ephemeralPubKey'] as String,
        wrappedFBase64: payload['wrappedF'] as String,
      );
      await (_vault ?? VaultProvider.vault)
          .putFamilyKey(payload['familyId'] as String, familyKey);
      return IngestResult.updated;
    } on SecretBoxAuthenticationError {
      // 私钥对不上（老包裹份/异常数据）：静默跳过
      return IngestResult.skipped;
    }
  }

  /// 同步机制字段（三类表共用）
  static (int, DateTime, bool) _meta(Map<String, dynamic> record) => (
        record['version'] as int,
        DateTime.fromMillisecondsSinceEpoch(record['updatedAt'] as int),
        (record['deleted'] as int) == 1,
      );

  /// LWW 判定：云端记录是否胜过本地行
  static bool _remoteWins({
    required int localVersion,
    required DateTime localUpdatedAt,
    required int remoteVersion,
    required DateTime remoteUpdatedAt,
  }) {
    if (remoteVersion != localVersion) return remoteVersion > localVersion;
    return remoteUpdatedAt.isAfter(localUpdatedAt);
  }

  Future<IngestResult> _applyTransaction(
    Map<String, dynamic> record,
    Map<String, dynamic> payload,
  ) async {
    final (version, updatedAt, deleted) = _meta(record);
    final id = record['id'] as String;

    final existing = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();

    if (existing != null && !_remoteWins(
        localVersion: existing.version,
        localUpdatedAt: existing.updatedAt,
        remoteVersion: version,
        remoteUpdatedAt: updatedAt)) {
      return IngestResult.skipped;
    }

    final row = TransactionsCompanion.insert(
      id: Value(id),
      type: payload['type'] as int,
      categoryId: payload['categoryId'] as String,
      amountCents: payload['amountCents'] as int,
      date: DateTime.fromMillisecondsSinceEpoch(
          payload[SyncOutbox.kDateMsField] as int),
      userId: payload['userId'] as String,
      familyId: Value(payload['familyId'] as String),
      description: Value(payload['description'] as String?),
      counterparty: Value(payload['counterparty'] as String?),
      tradeNo: Value(payload['tradeNo'] as String?),
      merchantOrderNo: Value(payload['merchantOrderNo'] as String?),
      payMethod: Value(payload['payMethod'] as String?),
      platform: Value(payload['platform'] as String?),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: const Value(false),
    );

    if (existing == null) {
      await _db.into(_db.transactions).insert(row);
      return IngestResult.inserted;
    }
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
        .write(row);
    return IngestResult.updated;
  }

  Future<IngestResult> _applyCategory(
    Map<String, dynamic> record,
    Map<String, dynamic> payload,
  ) async {
    final (version, updatedAt, deleted) = _meta(record);
    final id = record['id'] as String;

    final existing = await (_db.select(_db.categories)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();

    if (existing != null && !_remoteWins(
        localVersion: existing.version,
        localUpdatedAt: existing.updatedAt,
        remoteVersion: version,
        remoteUpdatedAt: updatedAt)) {
      return IngestResult.skipped;
    }

    final row = CategoriesCompanion.insert(
      id: Value(id),
      name: payload['name'] as String,
      icon: payload['icon'] as String,
      type: payload['type'] as int,
      familyId: Value(payload['familyId'] as String),
      isBuiltin: Value(payload['isBuiltin'] as bool? ?? false),
      sortOrder: Value(payload['sortOrder'] as int? ?? 0),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: const Value(false),
    );

    if (existing == null) {
      await _db.into(_db.categories).insert(row);
      return IngestResult.inserted;
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(row);
    return IngestResult.updated;
  }

  Future<IngestResult> _applyBudget(
    Map<String, dynamic> record,
    Map<String, dynamic> payload,
  ) async {
    final (version, updatedAt, deleted) = _meta(record);
    final id = record['id'] as String;

    final existing = await (_db.select(_db.budgets)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();

    if (existing != null && !_remoteWins(
        localVersion: existing.version,
        localUpdatedAt: existing.updatedAt,
        remoteVersion: version,
        remoteUpdatedAt: updatedAt)) {
      return IngestResult.skipped;
    }

    final row = BudgetsCompanion.insert(
      id: Value(id),
      familyId: Value(payload['familyId'] as String),
      userId: payload['userId'] as String,
      year: payload['year'] as int,
      month: payload['month'] as int,
      amountCents: payload['amountCents'] as int,
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: const Value(false),
    );

    if (existing == null) {
      await _db.into(_db.budgets).insert(row);
      return IngestResult.inserted;
    }
    await (_db.update(_db.budgets)..where((b) => b.id.equals(id)))
        .write(row);
    return IngestResult.updated;
  }

  /// 学习表入库（7.6）。matchText 在密文内、服务端无法按它去重，
  /// 双端对同一文本并发指认会产生 id 不同、matchText 相同的服务端
  /// 条目——归并必须在拉取侧做：
  ///
  /// - 本地无该 matchText → 插入云端行
  /// - 本地有（同 id 常规路径 / 不同 id 并发归并路径）→ LWW；
  ///   云端胜则把本地行更新为云端内容（保留本地 id 占位，满足
  ///   UNIQUE(match_text)），服务端冗余条目由各设备归并吸收，
  ///   最终该文本收敛到最新 version 的指认
  Future<IngestResult> _applyCategoryRule(
    Map<String, dynamic> record,
    Map<String, dynamic> payload,
  ) async {
    final (version, updatedAt, deleted) = _meta(record);
    final id = record['id'] as String;
    final matchText = payload['matchText'] as String;

    final existing = await (_db.select(_db.categoryRules)
          ..where((r) => r.matchText.equals(matchText))
          ..limit(1))
        .getSingleOrNull();

    if (existing != null && !_remoteWins(
        localVersion: existing.version,
        localUpdatedAt: existing.updatedAt,
        remoteVersion: version,
        remoteUpdatedAt: updatedAt)) {
      return IngestResult.skipped;
    }

    final content = CategoryRulesCompanion(
      categoryId: Value(payload['categoryId'] as String),
      source: Value(payload['source'] as int),
      hitCount: Value(payload['hitCount'] as int? ?? 0),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: const Value(false),
    );

    if (existing == null) {
      await _db.into(_db.categoryRules).insert(CategoryRulesCompanion.insert(
            id: Value(id),
            matchText: matchText,
            categoryId: payload['categoryId'] as String,
            source: payload['source'] as int,
            hitCount: Value(payload['hitCount'] as int? ?? 0),
            version: Value(version),
            updatedAt: Value(updatedAt),
            deleted: Value(deleted),
            syncPending: const Value(false),
          ));
      return IngestResult.inserted;
    }
    await (_db.update(_db.categoryRules)
          ..where((r) => r.id.equals(existing.id)))
        .write(content);
    return IngestResult.updated;
  }
}
