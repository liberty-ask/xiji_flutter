import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:drift/drift.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import 'sync_outbox.dart';
import 'vault_sync_service.dart';

/// 单条云端记录的入库仲裁结果
enum IngestResult { inserted, updated, skipped }

/// 云端拉取记录的本地入库仲裁器（tasks.md 7.4）。
///
/// LWW 规则与服务端完全对齐（见 7.2）：
/// - 本地无该 id → 插入
/// - version 高者胜（云端高 → 覆盖本地；本地高 → 跳过，
///   本地未推送的更新数据不被云端旧值冲掉，标记保留待推）
/// - 同 version → updated_at 新者胜；完全相同 → 幂等跳过
/// - 墓碑与正常记录同规则：墓碑胜出即删除落库，正常记录胜出
///   不复活（只有更高 version 才能翻案）
/// - 云端覆盖写入的行 syncPending=false（云端权威数据无需回推）
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
  /// 解密失败（密钥不对/密文损坏/AAD 不匹配）抛原异常，由拉取循环
  /// 终止本轮、游标不推进（重试无害；密钥错=全量失败不会推进任何游标）。
  ///
  /// vault 托管记录（6.7）特判：dataKey 解不开（传输密钥不同），
  /// 按 id 前缀识别后用 vault 传输密钥解，importVaultDoc LWW 落地；
  /// 解不开的 vault 记录静默跳过（跨账号 vault 无害：归属校验拒收）。
  Future<IngestResult> applyRecord(
    Uint8List dataKey,
    Map<String, dynamic> record,
  ) async {
    final id = record['id'] as String;
    Map<String, dynamic> payload;
    try {
      payload = await SyncOutbox.decryptRecord(dataKey, record);
    } on SecretBoxAuthenticationError {
      if (id.startsWith('vault-')) {
        final userId = await (_userId?.call());
        if (userId == null) return IngestResult.skipped;
        final vaultPayload = await SyncOutbox.decryptRecord(
            KeyVault.vaultTransportKey(userId), record);
        final adopted = await (_vault ?? VaultProvider.vault)
            .importVaultDoc(vaultPayload);
        return adopted ? IngestResult.updated : IngestResult.skipped;
      }
      rethrow;
    }
    final recordType = payload['recordType'] as String;
    return switch (recordType) {
      SyncOutbox.kTypeTransaction => _applyTransaction(record, payload),
      SyncOutbox.kTypeCategory => _applyCategory(record, payload),
      SyncOutbox.kTypeBudget => _applyBudget(record, payload),
      SyncOutbox.kTypeCategoryRule => _applyCategoryRule(record, payload),
      VaultSyncService.kRecordType => Future<IngestResult>.value(
          IngestResult.skipped),
      _ => throw ArgumentError('未知的同步记录类型: $recordType'),
    };
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
