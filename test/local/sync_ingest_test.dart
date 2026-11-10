import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';

void main() {
  late AppDatabase db;
  late SyncIngest ingest;
  final dataKey = Uint8List.fromList(List.generate(32, (i) => i * 3 % 256));

  final txBusiness = <String, dynamic>{
    'recordType': 'transaction',
    'type': 1,
    'categoryId': '01a15d13-bded-710c-a3bd-aba94a5aeb36',
    'amountCents': 3000,
    'dateMs': DateTime(2026, 10, 1).millisecondsSinceEpoch,
    'userId': 'user-1',
    'familyId': 'f1',
    'description': '瑞幸咖啡',
    'counterparty': null,
    'tradeNo': null,
    'merchantOrderNo': null,
    'payMethod': null,
    'platform': null,
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ingest = SyncIngest(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 构造云端拉取记录（走 outbox 加密，与生产密文格式一致）
  Future<Map<String, dynamic>> cloudTx({
    String id = 'tx-1',
    int version = 1,
    DateTime? updatedAt,
    bool deleted = false,
    Map<String, dynamic> business = const {},
  }) =>
      SyncOutbox.encryptRecord(
        dataKey,
        SyncPendingRow(
          recordType: 'transaction',
          id: id,
          version: version,
          updatedAt: updatedAt ?? DateTime(2026, 10, 1, 8),
          deleted: deleted,
          familyId: 'f1',
          payload: <String, dynamic>{...txBusiness, ...business},
        ),
      );

  Future<Transaction?> localTx(String id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  group('任务 7.4：入库仲裁（LWW 与服务端对齐）', () {
    test('本地无该 id：插入全字段且 syncPending=false', () async {
      final result =
          await ingest.applyRecord(dataKey, await cloudTx());
      expect(result, IngestResult.inserted);

      final row = (await localTx('tx-1'))!;
      expect(row.amountCents, 3000);
      expect(row.description, '瑞幸咖啡');
      expect(row.date, DateTime(2026, 10, 1));
      expect(row.version, 1);
      expect(row.deleted, false);
      expect(row.syncPending, false, reason: '云端权威数据无需回推');
    });

    test('云端 version 高：覆盖本地', () async {
      await ingest.applyRecord(dataKey, await cloudTx());
      // 本地编辑未推送（version 2）
      await (db.update(db.transactions)..where((t) => t.id.equals('tx-1')))
          .write(const TransactionsCompanion(
            amountCents: Value(9999),
            version: Value(2),
          ));

      final result = await ingest.applyRecord(
          dataKey, await cloudTx(version: 3, business: {'amountCents': 500}));
      expect(result, IngestResult.updated);

      final row = (await localTx('tx-1'))!;
      expect(row.amountCents, 500);
      expect(row.version, 3);
      expect(row.syncPending, false);
    });

    test('本地 version 高：跳过，本地未推送数据不被云端旧值冲掉', () async {
      await ingest.applyRecord(dataKey, await cloudTx());
      await (db.update(db.transactions)..where((t) => t.id.equals('tx-1')))
          .write(const TransactionsCompanion(
            amountCents: Value(9999),
            version: Value(5),
            syncPending: Value(true),
          ));

      final result = await ingest.applyRecord(
          dataKey, await cloudTx(version: 3, business: {'amountCents': 500}));
      expect(result, IngestResult.skipped);

      final row = (await localTx('tx-1'))!;
      expect(row.amountCents, 9999);
      expect(row.version, 5);
      expect(row.syncPending, true, reason: '标记保留待推送');
    });

    test('同 version 云端 updated_at 新：覆盖；完全相同：幂等跳过', () async {
      final at = DateTime(2026, 10, 1, 8);
      await ingest.applyRecord(
          dataKey, await cloudTx(updatedAt: at));

      // 同 version + 更晚 updated_at → 覆盖
      final result = await ingest.applyRecord(dataKey,
          await cloudTx(updatedAt: at.add(const Duration(minutes: 1))));
      expect(result, IngestResult.updated);

      // 同 version + 同 updated_at → 幂等跳过
      final again = await ingest.applyRecord(dataKey,
          await cloudTx(updatedAt: at.add(const Duration(minutes: 1))));
      expect(again, IngestResult.skipped);
    });

    test('墓碑同规则：胜出删除落库，正常记录不复活已删行', () async {
      await ingest.applyRecord(dataKey,
          await cloudTx(version: 2, deleted: true));
      var row = (await localTx('tx-1'))!;
      expect(row.deleted, true, reason: '墓碑胜出即删除落库');

      // 低 version 正常记录不能复活（version 相同时间更早也不行）
      final result = await ingest.applyRecord(
          dataKey,
          await cloudTx(
              version: 2,
              updatedAt: DateTime(2026, 10, 1, 7),
              deleted: false));
      expect(result, IngestResult.skipped);
      row = (await localTx('tx-1'))!;
      expect(row.deleted, true);

      // 更高 version 正常记录可翻案复活
      final revive = await ingest.applyRecord(
          dataKey,
          await cloudTx(
              version: 3,
              updatedAt: DateTime(2026, 10, 2),
              deleted: false));
      expect(revive, IngestResult.updated);
      row = (await localTx('tx-1'))!;
      expect(row.deleted, false);
    });
  });

  group('任务 7.4：三表路由', () {
    test('category 记录入库', () async {
      final record = await SyncOutbox.encryptRecord(
        dataKey,
        SyncPendingRow(
          recordType: 'category',
          id: 'cat-9',
          version: 1,
          updatedAt: DateTime(2026, 10, 1),
          deleted: false,
          familyId: 'f1',
          payload: const <String, dynamic>{
            'recordType': 'category',
            'name': '宠物开销',
            'icon': 'pets',
            'type': 1,
            'isBuiltin': false,
            'sortOrder': 12,
            'familyId': 'f1',
          },
        ),
      );
      final result = await ingest.applyRecord(dataKey, record);
      expect(result, IngestResult.inserted);

      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals('cat-9')))
          .getSingle();
      expect(row.name, '宠物开销');
      expect(row.sortOrder, 12);
      expect(row.syncPending, false);
    });

    test('budget 记录入库', () async {
      final record = await SyncOutbox.encryptRecord(
        dataKey,
        SyncPendingRow(
          recordType: 'budget',
          id: 'b-9',
          version: 1,
          updatedAt: DateTime(2026, 10, 1),
          deleted: false,
          familyId: 'f1',
          payload: const <String, dynamic>{
            'recordType': 'budget',
            'familyId': 'f1',
            'userId': 'user-1',
            'year': 2026,
            'month': 10,
            'amountCents': 150000,
          },
        ),
      );
      final result = await ingest.applyRecord(dataKey, record);
      expect(result, IngestResult.inserted);

      final row = await (db.select(db.budgets)
            ..where((b) => b.id.equals('b-9')))
          .getSingle();
      expect(row.year, 2026);
      expect(row.month, 10);
      expect(row.amountCents, 150000);
      expect(row.syncPending, false);
    });

    test('未知记录类型抛错', () async {
      final record = await SyncOutbox.encryptRecord(
        dataKey,
        SyncPendingRow(
          recordType: 'unknown',
          id: 'x',
          version: 1,
          updatedAt: DateTime(2026, 10, 1),
          deleted: false,
          familyId: 'f1',
          payload: const <String, dynamic>{'recordType': 'unknown'},
        ),
      );
      expect(() => ingest.applyRecord(dataKey, record),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('7.10：页级批量仲裁（applyPage）', () {
    Future<Map<String, dynamic>> cloudRecord({
      required String recordType,
      required String id,
      int version = 1,
      DateTime? updatedAt,
      bool deleted = false,
      required Map<String, dynamic> payload,
      Uint8List? key,
    }) =>
        SyncOutbox.encryptRecord(
          key ?? dataKey,
          SyncPendingRow(
            recordType: recordType,
            id: id,
            version: version,
            updatedAt: updatedAt ?? DateTime(2026, 10, 1, 8),
            deleted: deleted,
            familyId: 'f1',
            payload: payload,
          ),
        );

    Map<String, dynamic> rulePayload({
      required String matchText,
      required String categoryId,
      int hitCount = 1,
    }) =>
        <String, dynamic>{
          'recordType': SyncOutbox.kTypeCategoryRule,
          'matchText': matchText,
          'categoryId': categoryId,
          'source': 1,
          'hitCount': hitCount,
        };

    test('整页四类记录：一次调用批量入库，全部 syncPending=false', () async {
      final stats = await ingest.applyPage(dataKey, [
        await cloudTx(id: 'tx-a'),
        await cloudTx(id: 'tx-b'),
        await cloudTx(id: 'tx-c'),
        await cloudRecord(
          recordType: SyncOutbox.kTypeCategory,
          id: 'cat-9',
          payload: <String, dynamic>{
            'recordType': SyncOutbox.kTypeCategory,
            'name': '合成分类',
            'icon': 'pets',
            'type': 1,
            'isBuiltin': false,
            'sortOrder': 12,
            'familyId': 'f1',
          },
        ),
        await cloudRecord(
          recordType: SyncOutbox.kTypeBudget,
          id: 'b-9',
          payload: <String, dynamic>{
            'recordType': SyncOutbox.kTypeBudget,
            'familyId': 'f1',
            'userId': 'user-1',
            'year': 2026,
            'month': 10,
            'amountCents': 150000,
          },
        ),
        await cloudRecord(
          recordType: SyncOutbox.kTypeCategoryRule,
          id: 'r-9',
          payload: rulePayload(matchText: '合成商户A', categoryId: 'cat-A'),
        ),
      ]);

      expect(stats.applied, 6);
      expect(stats.skipped, 0);
      expect(stats.familyKeyGained, false);

      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(3));
      expect(txs.every((t) => t.syncPending == false), true);
      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals('cat-9')))
          .getSingle();
      expect(category.name, '合成分类');
      expect((await db.select(db.budgets).get()).single.amountCents, 150000);
      expect((await db.select(db.categoryRules).get()).single.matchText,
          '合成商户A');
    });

    test('页内 LWW 三态与墓碑规则与逐条路径一致', () async {
      await ingest.applyPage(dataKey, [await cloudTx(id: 'tx-1', version: 1)]);
      // 本地有未推送编辑（version 5）
      await (db.update(db.transactions)..where((t) => t.id.equals('tx-1')))
          .write(const TransactionsCompanion(
        amountCents: Value(9999),
        version: Value(5),
        syncPending: Value(true),
      ));

      final stats = await ingest.applyPage(dataKey, [
        // 云端旧版本：跳过
        await cloudTx(id: 'tx-1', version: 3, business: {'amountCents': 500}),
        // 新记录：插入
        await cloudTx(id: 'tx-2', version: 1),
        // 墓碑：按同规则落库
        await cloudTx(id: 'tx-3', version: 1, deleted: true),
      ]);

      expect(stats.applied, 2);
      expect(stats.skipped, 1);
      final local = (await localTx('tx-1'))!;
      expect(local.amountCents, 9999);
      expect(local.syncPending, true, reason: '本地未推送数据不被云端旧值冲掉');
      expect((await localTx('tx-2'))!.syncPending, false);
      expect((await localTx('tx-3'))!.deleted, true);
    });

    test('页内同 id 重复：取 LWW 更优的一条，不撞主键', () async {
      final stats = await ingest.applyPage(dataKey, [
        await cloudTx(id: 'tx-1', version: 1, business: {'amountCents': 100}),
        await cloudTx(id: 'tx-1', version: 3, business: {'amountCents': 300}),
      ]);

      expect(stats.applied, 1);
      expect(stats.skipped, 1);
      final row = (await localTx('tx-1'))!;
      expect(row.version, 3);
      expect(row.amountCents, 300);
    });

    test('学习表页内同 matchText 不同 id：归并为一行（LWW 胜者）', () async {
      final stats = await ingest.applyPage(dataKey, [
        await cloudRecord(
          recordType: SyncOutbox.kTypeCategoryRule,
          id: 'r-1',
          version: 1,
          payload: rulePayload(matchText: '合成商户A', categoryId: 'cat-A'),
        ),
        await cloudRecord(
          recordType: SyncOutbox.kTypeCategoryRule,
          id: 'r-2',
          version: 2,
          payload: rulePayload(matchText: '合成商户A', categoryId: 'cat-B'),
        ),
      ]);

      expect(stats.applied, 1);
      expect(stats.skipped, 1);
      final rows = await db.select(db.categoryRules).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'r-2');
      expect(rows.single.categoryId, 'cat-B');
    });

    test('学习表本地已有同文本不同 id：更新本地行并保留本地 id', () async {
      await db.into(db.categoryRules).insert(CategoryRulesCompanion.insert(
            id: const Value('local-1'),
            matchText: '合成商户B',
            categoryId: 'cat-A',
            source: 1,
            version: const Value(1),
            updatedAt: Value(DateTime(2026, 10, 1, 8)),
            syncPending: const Value(true),
          ));

      final stats = await ingest.applyPage(dataKey, [
        await cloudRecord(
          recordType: SyncOutbox.kTypeCategoryRule,
          id: 'remote-9',
          version: 2,
          updatedAt: DateTime(2026, 10, 1, 9),
          payload: rulePayload(matchText: '合成商户B', categoryId: 'cat-B'),
        ),
      ]);

      expect(stats.applied, 1);
      final rows = await db.select(db.categoryRules).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'local-1');
      expect(rows.single.categoryId, 'cat-B');
      expect(rows.single.syncPending, false);
    });

    test('个人 key 落回的记录入库并置待推（家庭 key 重密封）', () async {
      final otherFamilyKey = Uint8List.fromList(
          List.generate(32, (i) => (i * 7 + 11) % 256));

      final stats = await ingest.applyPage(
        dataKey,
        [await cloudTx(id: 'tx-1', version: 1)],
        familyDataKey: otherFamilyKey,
      );

      expect(stats.applied, 1);
      expect(stats.familyKeyGained, false);
      expect((await localTx('tx-1'))!.syncPending, true,
          reason: '个人 key 解出的记录需以家庭 key 重推');
    });
  });

  group('搜索索引：同步入库维护 transactions_fts', () {
    late TransactionRepository repo;

    setUp(() {
      repo = TransactionRepository(db);
    });

    test('单条 applyRecord 入库后可搜到描述与交易对方', () async {
      await ingest.applyRecord(
        dataKey,
        await cloudTx(business: {
          'description': '合成早餐',
          'counterparty': '合成小吃店',
        }),
      );

      expect(await repo.search('f1', '早餐'), hasLength(1));
      expect(await repo.search('f1', '小吃店'), hasLength(1));
    });

    test('整页 applyPage 批量入库后可搜到（批量路径同事务建索引）', () async {
      final stats = await ingest.applyPage(dataKey, [
        await cloudTx(id: 'tx-1', business: {'description': '合成地铁'}),
        await cloudTx(
          id: 'tx-2',
          business: {'description': '合成外卖', 'counterparty': '合成餐馆'},
        ),
      ]);

      expect(stats.applied, 2);
      expect(await repo.search('f1', '地铁'), hasLength(1));
      expect(await repo.search('f1', '合成餐馆').then((l) => l.single.id),
          'tx-2');
    });

    test('同步更新版本后旧关键词不再命中、新关键词命中', () async {
      await ingest.applyRecord(
        dataKey,
        await cloudTx(business: {'description': '合成旧描述'}),
      );
      expect(await repo.search('f1', '旧描述'), hasLength(1));

      await ingest.applyRecord(
        dataKey,
        await cloudTx(
          version: 2,
          updatedAt: DateTime(2026, 10, 2, 8),
          business: {'description': '合成新描述'},
        ),
      );

      expect(await repo.search('f1', '旧描述'), isEmpty,
          reason: '索引必须随主表更新，不能残留旧文本');
      expect(await repo.search('f1', '新描述'), hasLength(1));
    });

    test('墓碑同步到达后不可搜且索引行被摘除', () async {
      await ingest.applyRecord(
        dataKey,
        await cloudTx(business: {'description': '合成待删'}),
      );
      expect(await repo.search('f1', '待删'), hasLength(1));

      await ingest.applyRecord(
        dataKey,
        await cloudTx(
          version: 2,
          updatedAt: DateTime(2026, 10, 2, 8),
          deleted: true,
        ),
      );

      expect(await repo.search('f1', '待删'), isEmpty);
      final ftsRows = await db.customSelect(
        'SELECT COUNT(*) AS c FROM transactions_fts WHERE tx_id = ?',
        variables: [const Variable('tx-1')],
      ).getSingle();
      expect(ftsRows.read<int>('c'), 0, reason: '墓碑应摘除索引，不留脏行');
    });
  });
}
