import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
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
}
