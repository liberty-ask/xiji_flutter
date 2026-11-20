import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:drift/drift.dart';

import '../crypto/key_vault.dart';
import '../crypto/vault_provider.dart';
import '../data/local/app_database.dart';
import '../data/local/backup_switch_store.dart';
import '../data/local/member_public_key_store.dart';
import '../data/local/transaction_fts.dart';
import 'backup_switch_service.dart';
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
/// - 云端覆盖写入的行 syncPending=false（云端权威数据无需回推），
///   例外：个人 key 回落解密的行标 true——过渡密文仅本人可解，
///   需以家庭 key 重推覆盖云端旧密文，其他成员才能解（见
///   applyRecord 内注释）
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
    // 个人 key 回落且已有家庭 key：该密文是过渡态（仅本人可解），
    // 入库后标 pending 待以家庭 key 重推——否则重装方回落拉回的
    // 存量永远停留为个人密文，其他成员拿到 F 也解不开（真机踩坑）。
    // 注意仅限「有家庭 key 却解不开」的回落：无 F 时个人密文是常态
    // （同账号多设备/家庭尚未启用分发），标 pending 反而推不出去
    var usedFallbackKey = false;

    // 键序解密：家庭 key → 个人 key
    for (final key in [familyDataKey, personalDataKey]) {
      if (key == null) continue;
      try {
        payload = await SyncOutbox.decryptRecord(key, record);
        usedFallbackKey = identical(key, personalDataKey) &&
            familyDataKey != null;
        break;
      } on SecretBoxAuthenticationError {
        continue; // 试下一把键
      }
    }

    if (payload == null) {
      // 机制记录（传输密钥加密）：vault / fkey / bksw 特判
      if (id.startsWith('vault-')) {
        return _ingestVaultDoc(record);
      }
      if (id.startsWith('fk-')) {
        return _ingestFamilyKeyWrap(record);
      }
      if (id.startsWith('bksw-')) {
        return _ingestBackupSwitch(record);
      }
      // 其他成员未重密封的旧密文：本人无其个人 key，解不开是预期。
      // 跳过且游标照常推进（重密封方重推后版本更新可增量拉到可解版）。
      return IngestResult.skipped;
    }

    final recordType = payload['recordType'] as String;
    return switch (recordType) {
      SyncOutbox.kTypeTransaction =>
        _applyTransaction(record, payload, markPending: usedFallbackKey),
      SyncOutbox.kTypeCategory =>
        _applyCategory(record, payload, markPending: usedFallbackKey),
      SyncOutbox.kTypeBudget =>
        _applyBudget(record, payload, markPending: usedFallbackKey),
      SyncOutbox.kTypeCategoryRule =>
        _applyCategoryRule(record, payload, markPending: usedFallbackKey),
      VaultSyncService.kRecordType =>
        Future<IngestResult>.value(IngestResult.skipped),
      FamilyKeyService.kRecordType =>
        Future<IngestResult>.value(IngestResult.skipped),
      _ => throw ArgumentError('未知的同步记录类型: $recordType'),
    };
  }

  /// 页级批量仲裁（tasks.md 7.10）：一页（服务端上限 2000 条）内
  /// 每张表只做「1 次批量 SELECT + 1 批写入」，替代逐条的
  /// SELECT + INSERT/UPDATE（2000 条从约 4000 次 isolate 往返降到个位数）。
  ///
  /// 语义与 [applyRecord] 完全等价，三处顺序约束必须保留：
  /// 1. 解密按分段批量（[SyncOutbox.decryptBatch] 下放 isolate），分段
  ///    边界为 fkey 包裹记录——fkey 可能在本页中途才送达 F，同页后续
  ///    业务记录必须能立即用新 F 解密（否则游标越过后永久错过）；
  /// 2. vault/fkey 机制记录保持逐条即时处理（涉及网络与密钥库写入，
  ///    且数量为「每用户 1 条 vault + 每成员 1 条包裹」）；
  /// 3. 页内重复 id / 重复 matchText 的合并取 LWW 更优的一条，与逐条
  ///    「后到者与已写入的前者再仲裁」的最终状态一致。
  ///
  /// 返回本页 applied/skipped 计数（与逐条路径同口径，供拉取统计日志），
  /// [familyKeyGained] 表示本页内首次获得家庭密钥（调用方需刷新本地
  /// 缓存供下一页使用）。
  Future<({int applied, int skipped, bool familyKeyGained})> applyPage(
    Uint8List personalDataKey,
    List<Map<String, dynamic>> records, {
    Uint8List? familyDataKey,
    Future<Uint8List?> Function()? familyDataKeyProvider,
  }) async {
    var familyKey = familyDataKey;
    var familyKeyGained = false;
    var applied = 0;
    var skipped = 0;

    final items = <_IngestItem>[];

    // vault/fkey 类型记录按机制记录跳过（与逐条路径的 switch 一致）
    void enqueue(
      Map<String, dynamic> record,
      Map<String, dynamic> payload, {
      required bool markPending,
    }) {
      final type = payload['recordType'] as String;
      if (type == VaultSyncService.kRecordType ||
          type == FamilyKeyService.kRecordType) {
        skipped++;
      } else {
        items.add(_IngestItem(
          record: record,
          payload: payload,
          markPending: markPending,
        ));
      }
    }

    // 批量解密当前分段：第一轮家庭 key，第二轮个人 key 回落（存量个人
    // 密文）。markPending 仅在「有 F 却靠个人 key 解开」时为 true，
    // 与逐条路径的 usedFallbackKey 判定一致。
    Future<void> flushSegment(List<Map<String, dynamic>> segment) async {
      if (segment.isEmpty) return;
      final plain = List<Map<String, dynamic>?>.filled(segment.length, null);
      final usedPersonal = List<bool>.filled(segment.length, false);

      final key = familyKey;
      if (key != null) {
        final withFamily = await SyncOutbox.decryptBatch(key, segment);
        for (var i = 0; i < segment.length; i++) {
          plain[i] = withFamily[i];
        }
      }
      final needPersonal = <int>[
        for (var i = 0; i < segment.length; i++)
          if (plain[i] == null) i,
      ];
      if (needPersonal.isNotEmpty) {
        final subset = <Map<String, dynamic>>[
          for (final i in needPersonal) segment[i],
        ];
        final withPersonal =
            await SyncOutbox.decryptBatch(personalDataKey, subset);
        for (var j = 0; j < needPersonal.length; j++) {
          if (withPersonal[j] != null) {
            plain[needPersonal[j]] = withPersonal[j];
            usedPersonal[needPersonal[j]] = true;
          }
        }
      }

      final fallbackMarksPending = key != null;
      for (var i = 0; i < segment.length; i++) {
        final record = segment[i];
        final payload = plain[i];
        if (payload == null) {
          if ((record['id'] as String).startsWith('vault-')) {
            final result = await _ingestVaultDoc(record);
            result == IngestResult.skipped ? skipped++ : applied++;
            continue;
          }
          if ((record['id'] as String).startsWith('bksw-')) {
            final result = await _ingestBackupSwitch(record);
            result == IngestResult.skipped ? skipped++ : applied++;
            continue;
          }
          // 其他成员未重密封的旧密文：本人无其个人 key，解不开是预期。
          // 跳过且游标照常推进（重密封方重推后版本更新可增量拉到可解版）。
          skipped++;
          continue;
        }
        enqueue(record, payload,
            markPending: fallbackMarksPending && usedPersonal[i]);
      }
    }

    var segment = <Map<String, dynamic>>[];
    for (final record in records) {
      final id = record['id'] as String;
      if (!id.startsWith('fk-')) {
        segment.add(record);
        continue;
      }

      // fkey 包裹是分段边界：先结算前一分段（旧 F），再按逐条路径处理
      // 包裹本身——若本页中途送出 F，后续分段立即改用新 F 解密。
      await flushSegment(segment);
      segment = <Map<String, dynamic>>[];

      Map<String, dynamic>? payload;
      var usedFallbackKey = false;
      for (final key in [familyKey, personalDataKey]) {
        if (key == null) continue;
        try {
          payload = await SyncOutbox.decryptRecord(key, record);
          usedFallbackKey =
              identical(key, personalDataKey) && familyKey != null;
          break;
        } on SecretBoxAuthenticationError {
          continue;
        }
      }
      if (payload != null) {
        // 业务 key 意外解开机制记录：与原逐条路径同口径分流
        enqueue(record, payload, markPending: usedFallbackKey);
        continue;
      }
      final hadNoFamilyKey = familyKey == null;
      final result = await _ingestFamilyKeyWrap(record);
      result == IngestResult.skipped ? skipped++ : applied++;
      if (result == IngestResult.updated) {
        // F 落库后刷新页内密钥：无→有（后开成员首拉）与旧→新
        // （重开自愈轮换场景）均让后续分段立即改用新 F 解密；
        // familyKeyGained 仅在首获（无→有）时置位——旧→新的游标
        // 管理由开关重开的清游标动作负责，不在此触发
        final refreshed = await familyDataKeyProvider?.call();
        if (refreshed != null) {
          familyKey = refreshed;
          if (hadNoFamilyKey) familyKeyGained = true;
        }
      }
    }
    await flushSegment(segment);

    final txItems = <_IngestItem>[];
    final categoryItems = <_IngestItem>[];
    final budgetItems = <_IngestItem>[];
    final ruleItems = <_IngestItem>[];
    for (final item in items) {
      switch (item.payload['recordType'] as String) {
        case SyncOutbox.kTypeTransaction:
          txItems.add(item);
          break;
        case SyncOutbox.kTypeCategory:
          categoryItems.add(item);
          break;
        case SyncOutbox.kTypeBudget:
          budgetItems.add(item);
          break;
        case SyncOutbox.kTypeCategoryRule:
          ruleItems.add(item);
          break;
        default:
          throw ArgumentError('未知的同步记录类型: ${item.payload['recordType']}');
      }
    }

    final txStats = await _applyTransactionsBatch(txItems);
    final categoryStats = await _applyCategoriesBatch(categoryItems);
    final budgetStats = await _applyBudgetsBatch(budgetItems);
    final ruleStats = await _applyCategoryRulesBatch(ruleItems);
    applied += txStats.$1 + categoryStats.$1 + budgetStats.$1 + ruleStats.$1;
    skipped += txStats.$2 + categoryStats.$2 + budgetStats.$2 + ruleStats.$2;

    return (
      applied: applied,
      skipped: skipped,
      familyKeyGained: familyKeyGained,
    );
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

  /// bksw 家庭维度备份开关记录（family-scoped-backup-switch）：拉到
  /// 自己的开关记录时按 version LWW 仲裁写入本地开关存储（多设备
  /// 漫游：version 高者胜，平局/更低忽略幂等）。他人开关记录传输
  /// 密钥不匹配，解不开是预期，静默跳过。
  Future<IngestResult> _ingestBackupSwitch(
      Map<String, dynamic> record) async {
    final userId = await (_userId?.call());
    if (userId == null) return IngestResult.skipped;
    if ((record['deleted'] as num?)?.toInt() == 1 ||
        record['deleted'] == true) {
      return IngestResult.skipped; // 开关记录只 upsert 不删（防御）
    }
    Map<String, dynamic> payload;
    try {
      payload = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey(userId), record);
    } on SecretBoxAuthenticationError {
      return IngestResult.skipped; // 他人开关记录：解不开是预期
    }
    if (payload['recordType'] != BackupSwitchService.kRecordType) {
      return IngestResult.skipped;
    }
    if (payload['userId'] != userId) return IngestResult.skipped;
    final familyId = payload['familyId'] as String?;
    if (familyId == null || familyId.isEmpty) return IngestResult.skipped;
    final enabled = payload['enabled'];
    if (enabled is! bool) return IngestResult.skipped;
    // version 取服务端明文机制字段（与 fkey 探测同口径）
    final version = (record['version'] as num?)?.toInt() ?? 1;
    final applied =
        await BackupSwitchStore.applyRemote(familyId, enabled, version);
    return applied ? IngestResult.updated : IngestResult.skipped;
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

  /// 交易行 companion（单条与批量共用）。v7 退款冲抵字段：旧客户端推来的
  /// payload 无此字段，此时保留本地已有冲抵关联与已退额，避免旧版本编辑
  /// 原支出把净额冲抵清零。
  TransactionsCompanion _transactionRow(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    required bool markPending,
    Transaction? existing,
  }) {
    final (version, updatedAt, deleted) = _meta(record);
    final hasRefundFields = payload.containsKey('refundedCents');
    final refundOfIdValue = !hasRefundFields && existing != null
        ? Value(existing.refundOfId)
        : Value(payload['refundOfId'] as String?);
    final refundedCentsValue = !hasRefundFields && existing != null
        ? Value(existing.refundedCents)
        : Value((payload['refundedCents'] as num?)?.toInt() ?? 0);

    return TransactionsCompanion.insert(
      id: Value(record['id'] as String),
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
      refundOfId: refundOfIdValue,
      refundedCents: refundedCentsValue,
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(markPending),
    );
  }

  Future<IngestResult> _applyTransaction(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    bool markPending = false,
  }) async {
    final (version, updatedAt, _) = _meta(record);
    final id = record['id'] as String;

    // 仲裁读 + 主表写 + 索引写同一事务：与整页批量路径同口径，
    // 避免单条路径留下「主表已写、索引未写」的半截状态
    return _db.transaction(() async {
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

      final row = _transactionRow(record, payload,
          markPending: markPending, existing: existing);

      if (existing == null) {
        await _db.into(_db.transactions).insert(row);
      } else {
        await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
            .write(row);
      }
      await TransactionFts.sync(_db, [_ftsEntryOf(id, row)]);
      return existing == null ? IngestResult.inserted : IngestResult.updated;
    });
  }

  /// 从交易 companion 提取索引素材：与主表写入同源，避免再回查主表
  static TransactionFtsEntry _ftsEntryOf(
    String id,
    TransactionsCompanion row,
  ) =>
      TransactionFtsEntry(
        id: id,
        deleted: row.deleted.present ? row.deleted.value : false,
        description: row.description.present ? row.description.value : null,
        counterparty:
            row.counterparty.present ? row.counterparty.value : null,
      );

  /// 整页交易批量仲裁：1 次（分块）id 查询 + 1 批写入
  Future<(int, int)> _applyTransactionsBatch(List<_IngestItem> items) async {
    if (items.isEmpty) return (0, 0);
    final byId = _dedupeById(items);
    final existing = await _existingTransactions(byId.keys.toList());

    final inserts = <TransactionsCompanion>[];
    final updates = <({String id, TransactionsCompanion row})>[];
    // 索引素材随仲裁结果一起收集：主表写入与 FTS 写入同源（同一 companion），
    // 页级事务内先批量删后批量插，不额外回查主表、不增加 isolate 往返
    final ftsEntries = <TransactionFtsEntry>[];
    var applied = 0;
    var skipped = 0;

    for (final entry in byId.entries) {
      final item = entry.value;
      final (version, updatedAt, _) = _meta(item.record);
      final local = existing[entry.key];
      if (local != null && !_remoteWins(
          localVersion: local.version,
          localUpdatedAt: local.updatedAt,
          remoteVersion: version,
          remoteUpdatedAt: updatedAt)) {
        skipped++;
        continue;
      }
      final row = _transactionRow(item.record, item.payload,
          markPending: item.markPending, existing: local);
      if (local == null) {
        inserts.add(row);
      } else {
        updates.add((id: entry.key, row: row));
      }
      ftsEntries.add(_ftsEntryOf(entry.key, row));
      applied++;
    }
    skipped += items.length - byId.length;

    if (inserts.isNotEmpty || updates.isNotEmpty) {
      await _db.batch((b) {
        for (final row in inserts) {
          b.insert(_db.transactions, row);
        }
        for (final update in updates) {
          b.update(_db.transactions, update.row,
              where: (t) => t.id.equals(update.id));
        }
        // 索引与主表同一页级事务（由 puller 的 page transaction 包裹）
        TransactionFts.queueInBatch(b, ftsEntries);
      });
    }
    return (applied, skipped);
  }

  CategoriesCompanion _categoryRow(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    required bool markPending,
  }) {
    final (version, updatedAt, deleted) = _meta(record);
    return CategoriesCompanion.insert(
      id: Value(record['id'] as String),
      name: payload['name'] as String,
      icon: payload['icon'] as String,
      // 分类已中性化：旧协议里的 type 忽略；nameKey 不同步，
      // 远端记录一律按自建分类处理（显示原文）
      nameKey: const Value(null),
      familyId: Value(payload['familyId'] as String),
      isBuiltin: Value(payload['isBuiltin'] as bool? ?? false),
      sortOrder: Value(payload['sortOrder'] as int? ?? 0),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(markPending),
    );
  }

  Future<IngestResult> _applyCategory(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    bool markPending = false,
  }) async {
    final (version, updatedAt, _) = _meta(record);
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

    final row = _categoryRow(record, payload, markPending: markPending);

    if (existing == null) {
      await _db.into(_db.categories).insert(row);
      return IngestResult.inserted;
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(row);
    return IngestResult.updated;
  }

  Future<(int, int)> _applyCategoriesBatch(List<_IngestItem> items) async {
    if (items.isEmpty) return (0, 0);
    final byId = _dedupeById(items);
    final existing = await _existingCategories(byId.keys.toList());

    final inserts = <CategoriesCompanion>[];
    final updates = <({String id, CategoriesCompanion row})>[];
    var applied = 0;
    var skipped = 0;

    for (final entry in byId.entries) {
      final item = entry.value;
      final (version, updatedAt, _) = _meta(item.record);
      final local = existing[entry.key];
      if (local != null && !_remoteWins(
          localVersion: local.version,
          localUpdatedAt: local.updatedAt,
          remoteVersion: version,
          remoteUpdatedAt: updatedAt)) {
        skipped++;
        continue;
      }
      final row = _categoryRow(item.record, item.payload,
          markPending: item.markPending);
      if (local == null) {
        inserts.add(row);
      } else {
        updates.add((id: entry.key, row: row));
      }
      applied++;
    }
    skipped += items.length - byId.length;

    if (inserts.isNotEmpty || updates.isNotEmpty) {
      await _db.batch((b) {
        for (final row in inserts) {
          b.insert(_db.categories, row);
        }
        for (final update in updates) {
          b.update(_db.categories, update.row,
              where: (c) => c.id.equals(update.id));
        }
      });
    }
    return (applied, skipped);
  }

  BudgetsCompanion _budgetRow(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    required bool markPending,
  }) {
    final (version, updatedAt, deleted) = _meta(record);
    return BudgetsCompanion.insert(
      id: Value(record['id'] as String),
      familyId: Value(payload['familyId'] as String),
      userId: payload['userId'] as String,
      year: payload['year'] as int,
      month: payload['month'] as int,
      amountCents: payload['amountCents'] as int,
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(markPending),
    );
  }

  Future<IngestResult> _applyBudget(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    bool markPending = false,
  }) async {
    final (version, updatedAt, _) = _meta(record);
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

    final row = _budgetRow(record, payload, markPending: markPending);

    if (existing == null) {
      await _db.into(_db.budgets).insert(row);
      return IngestResult.inserted;
    }
    await (_db.update(_db.budgets)..where((b) => b.id.equals(id)))
        .write(row);
    return IngestResult.updated;
  }

  Future<(int, int)> _applyBudgetsBatch(List<_IngestItem> items) async {
    if (items.isEmpty) return (0, 0);
    final byId = _dedupeById(items);
    final existing = await _existingBudgets(byId.keys.toList());

    final inserts = <BudgetsCompanion>[];
    final updates = <({String id, BudgetsCompanion row})>[];
    var applied = 0;
    var skipped = 0;

    for (final entry in byId.entries) {
      final item = entry.value;
      final (version, updatedAt, _) = _meta(item.record);
      final local = existing[entry.key];
      if (local != null && !_remoteWins(
          localVersion: local.version,
          localUpdatedAt: local.updatedAt,
          remoteVersion: version,
          remoteUpdatedAt: updatedAt)) {
        skipped++;
        continue;
      }
      final row = _budgetRow(item.record, item.payload,
          markPending: item.markPending);
      if (local == null) {
        inserts.add(row);
      } else {
        updates.add((id: entry.key, row: row));
      }
      applied++;
    }
    skipped += items.length - byId.length;

    if (inserts.isNotEmpty || updates.isNotEmpty) {
      await _db.batch((b) {
        for (final row in inserts) {
          b.insert(_db.budgets, row);
        }
        for (final update in updates) {
          b.update(_db.budgets, update.row,
              where: (bd) => bd.id.equals(update.id));
        }
      });
    }
    return (applied, skipped);
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
    Map<String, dynamic> payload, {
    bool markPending = false,
  }) async {
    final (version, updatedAt, _) = _meta(record);
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

    if (existing == null) {
      await _db.into(_db.categoryRules).insert(
          _ruleInsertRow(record, payload, markPending: markPending));
      return IngestResult.inserted;
    }
    await (_db.update(_db.categoryRules)
          ..where((r) => r.id.equals(existing.id)))
        .write(_ruleContentRow(record, payload, markPending: markPending));
    return IngestResult.updated;
  }

  /// 学习表内容列（更新用：不含 id/matchText，归并时保留本地 id）
  CategoryRulesCompanion _ruleContentRow(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    required bool markPending,
  }) {
    final (version, updatedAt, deleted) = _meta(record);
    return CategoryRulesCompanion(
      categoryId: Value(payload['categoryId'] as String),
      source: Value(payload['source'] as int),
      hitCount: Value(payload['hitCount'] as int? ?? 0),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(markPending),
    );
  }

  CategoryRulesCompanion _ruleInsertRow(
    Map<String, dynamic> record,
    Map<String, dynamic> payload, {
    required bool markPending,
  }) {
    final (version, updatedAt, deleted) = _meta(record);
    return CategoryRulesCompanion.insert(
      id: Value(record['id'] as String),
      matchText: payload['matchText'] as String,
      categoryId: payload['categoryId'] as String,
      source: payload['source'] as int,
      hitCount: Value(payload['hitCount'] as int? ?? 0),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      syncPending: Value(markPending),
    );
  }

  /// 整页学习表批量仲裁。页内同 matchText 先去重（保留 LWW 更优的一条），
  /// 否则两条不同 id 的同文本记录会撞 UNIQUE(match_text) 导致整页回滚；
  /// 去重后的最终状态与逐条「先插入、再与前者仲裁」完全一致。
  Future<(int, int)> _applyCategoryRulesBatch(List<_IngestItem> items) async {
    if (items.isEmpty) return (0, 0);

    final byText = <String, _IngestItem>{};
    for (final item in items) {
      final text = item.payload['matchText'] as String;
      final prev = byText[text];
      if (prev == null || _recordWins(item.record, prev.record)) {
        byText[text] = item;
      }
    }
    final existing = await _existingCategoryRules(byText.keys.toList());

    final inserts = <CategoryRulesCompanion>[];
    final updates = <({String id, CategoryRulesCompanion row})>[];
    var applied = 0;
    var skipped = 0;

    for (final entry in byText.entries) {
      final item = entry.value;
      final (version, updatedAt, _) = _meta(item.record);
      final local = existing[entry.key];
      if (local != null && !_remoteWins(
          localVersion: local.version,
          localUpdatedAt: local.updatedAt,
          remoteVersion: version,
          remoteUpdatedAt: updatedAt)) {
        skipped++;
        continue;
      }
      if (local == null) {
        inserts.add(_ruleInsertRow(item.record, item.payload,
            markPending: item.markPending));
      } else {
        updates.add((
          id: local.id,
          row: _ruleContentRow(item.record, item.payload,
              markPending: item.markPending),
        ));
      }
      applied++;
    }
    skipped += items.length - byText.length;

    if (inserts.isNotEmpty || updates.isNotEmpty) {
      await _db.batch((b) {
        for (final row in inserts) {
          b.insert(_db.categoryRules, row);
        }
        for (final update in updates) {
          b.update(_db.categoryRules, update.row,
              where: (r) => r.id.equals(update.id));
        }
      });
    }
    return (applied, skipped);
  }

  /// 页内同 id 去重：保留 LWW 更优的一条。服务端主键唯一，正常不会出现，
  /// 属防御性处理（避免批量插入撞主键导致整页回滚）。
  static Map<String, _IngestItem> _dedupeById(List<_IngestItem> items) {
    final map = <String, _IngestItem>{};
    for (final item in items) {
      final id = item.record['id'] as String;
      final prev = map[id];
      if (prev == null || _recordWins(item.record, prev.record)) {
        map[id] = item;
      }
    }
    return map;
  }

  /// 两条云端记录按 LWW 比较（a 是否胜过 b）
  static bool _recordWins(Map<String, dynamic> a, Map<String, dynamic> b) {
    final (versionA, updatedAtA, _) = _meta(a);
    final (versionB, updatedAtB, _) = _meta(b);
    return _remoteWins(
      localVersion: versionB,
      localUpdatedAt: updatedAtB,
      remoteVersion: versionA,
      remoteUpdatedAt: updatedAtA,
    );
  }

  Future<Map<String, Transaction>> _existingTransactions(
      List<String> ids) async {
    final result = <String, Transaction>{};
    for (final chunk in _chunks(ids)) {
      final rows = await (_db.select(_db.transactions)
            ..where((t) => t.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        result[row.id] = row;
      }
    }
    return result;
  }

  Future<Map<String, Category>> _existingCategories(List<String> ids) async {
    final result = <String, Category>{};
    for (final chunk in _chunks(ids)) {
      final rows = await (_db.select(_db.categories)
            ..where((c) => c.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        result[row.id] = row;
      }
    }
    return result;
  }

  Future<Map<String, Budget>> _existingBudgets(List<String> ids) async {
    final result = <String, Budget>{};
    for (final chunk in _chunks(ids)) {
      final rows = await (_db.select(_db.budgets)
            ..where((b) => b.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        result[row.id] = row;
      }
    }
    return result;
  }

  Future<Map<String, CategoryRule>> _existingCategoryRules(
      List<String> texts) async {
    final result = <String, CategoryRule>{};
    for (final chunk in _chunks(texts)) {
      final rows = await (_db.select(_db.categoryRules)
            ..where((r) => r.matchText.isIn(chunk)))
          .get();
      for (final row in rows) {
        result[row.matchText] = row;
      }
    }
    return result;
  }

  /// 按批切分（保守 400 个/批，避开 SQLite 变量个数上限）
  static Iterable<List<T>> _chunks<T>(List<T> items) sync* {
    const size = 400;
    for (var start = 0; start < items.length; start += size) {
      final end = start + size > items.length ? items.length : start + size;
      yield items.sublist(start, end);
    }
  }
}

/// 页内待入库条目：解密后的明文载荷 + 是否需以家庭 key 重推
class _IngestItem {
  const _IngestItem({
    required this.record,
    required this.payload,
    required this.markPending,
  });

  final Map<String, dynamic> record;
  final Map<String, dynamic> payload;
  final bool markPending;
}
