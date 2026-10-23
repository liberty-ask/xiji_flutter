import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';

void main() {
  late AppDatabase db;
  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36'; // 餐饮（内置）

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Transaction> insertTx({String id = 'tx-1', String familyId = 'f1'}) =>
      db.into(db.transactions).insertReturning(TransactionsCompanion.insert(
        id: Value(id),
        type: 1,
        categoryId: diningId,
        amountCents: 3000,
        date: DateTime(2026, 10, 1),
        userId: 'user-1',
        familyId: Value(familyId),
        description: const Value('瑞幸咖啡'),
        tradeNo: const Value('T100'),
      ));

  Future<Category> insertCategory(
          {String id = 'cat-1', String familyId = 'f1'}) =>
      db.into(db.categories).insertReturning(CategoriesCompanion.insert(
        id: Value(id),
        name: '自定义分类',
        icon: 'star',
        type: 1,
        familyId: Value(familyId),
      ));

  Future<Budget> insertBudget({String id = 'b-1', String familyId = 'f1'}) =>
      db.into(db.budgets).insertReturning(BudgetsCompanion.insert(
        id: Value(id),
        familyId: Value(familyId),
        userId: 'user-1',
        year: 2026,
        month: 10,
        amountCents: 200000,
      ));

  Future<int> pendingCount(String table) => db
      .customSelect('SELECT COUNT(*) AS c FROM $table WHERE sync_pending = 1',
          readsFrom: {db.transactions, db.categories, db.budgets})
      .map((row) => row.read<int>('c'))
      .getSingle();

  group('任务 7.3：发件箱收集（collectAll）', () {
    test('三表混合收集：含表路由、同步字段与载荷', () async {
      await insertTx();
      await insertCategory();
      await insertBudget();

      final rows = await SyncOutbox.collectAll(db);
      expect(rows, hasLength(3));

      final tx = rows.singleWhere((r) => r.recordType == 'transaction');
      expect(tx.id, 'tx-1');
      expect(tx.version, 1);
      expect(tx.deleted, false);
      expect(tx.familyId, 'f1');
      expect(tx.payload['amountCents'], 3000);
      expect(tx.payload['categoryId'], diningId);
      expect(tx.payload['description'], '瑞幸咖啡');
      expect(tx.payload['tradeNo'], 'T100');
      expect(tx.payload['dateMs'],
          DateTime(2026, 10, 1).millisecondsSinceEpoch);

      final cat = rows.singleWhere((r) => r.recordType == 'category');
      expect(cat.payload['name'], '自定义分类');
      expect(cat.payload['isBuiltin'], false);

      final budget = rows.singleWhere((r) => r.recordType == 'budget');
      expect(budget.payload['year'], 2026);
      expect(budget.payload['amountCents'], 200000);
    });

    test('墓碑行参与收集（deleted 上传收敛删除）', () async {
      final row = await insertTx();
      await (db.update(db.transactions)..where((t) => t.id.equals(row.id)))
          .write(const TransactionsCompanion(
            deleted: Value(true),
            version: Value(2),
          ));

      final rows = await SyncOutbox.collectAll(db);
      expect(rows, hasLength(1));
      expect(rows.first.deleted, true);
      expect(rows.first.version, 2);
    });

    test('已推送标记与内置分类不重复收集', () async {
      await insertTx();
      await insertCategory();
      await SyncOutbox.clearPending(
          db, (await SyncOutbox.collectAll(db)).toList());
      await db.seedBuiltinCategories(); // syncPending=false

      expect(await SyncOutbox.collectAll(db), isEmpty);
      expect(await pendingCount('transactions'), 0);
      expect(await pendingCount('categories'), 0);
    });
  });

  group('任务 7.3：加密构造（encryptRecord/decryptRecord）', () {
    final dataKey =
        Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));

    test('加密可解密回原载荷；字段对齐服务端 SyncPushRecord', () async {
      await insertTx();
      final row = (await SyncOutbox.collectAll(db)).single;

      final record = await SyncOutbox.encryptRecord(dataKey, row);
      expect(record['id'], 'tx-1');
      expect(record['version'], 1);
      expect(record['deleted'], 0);
      expect(record['updatedAt'], row.updatedAt.millisecondsSinceEpoch);
      // base64 可解码，密文与 nonce 均为合法 base64
      base64Decode(record['nonce'] as String);
      final cipherBytes = base64Decode(record['ciphertext'] as String);
      // ciphertext = 密文‖16 字节 GCM 标签，必然长于 JSON 明文的一部分特征
      expect(cipherBytes.length, greaterThan(16));

      final payload = await SyncOutbox.decryptRecord(dataKey, record);
      expect(payload, row.payload);
    });

    test('nonce 不重复（同密钥同明文两次加密）', () async {
      await insertTx();
      final row = (await SyncOutbox.collectAll(db)).single;

      final a = await SyncOutbox.encryptRecord(dataKey, row);
      final b = await SyncOutbox.encryptRecord(dataKey, row);
      expect(a['nonce'], isNot(equals(b['nonce'])));
      expect(a['ciphertext'], isNot(equals(b['ciphertext'])));
    });

    test('AAD 绑定记录 ID：换 ID 解密必须失败', () async {
      await insertTx();
      final row = (await SyncOutbox.collectAll(db)).single;
      final record = await SyncOutbox.encryptRecord(dataKey, row);

      final forged = Map<String, dynamic>.from(record)..['id'] = 'tx-other';
      expect(
        () => SyncOutbox.decryptRecord(dataKey, forged),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('任务 7.3：清标记（clearPending）', () {
    test('只清传入行，批次内部分失败条目保留', () async {
      await insertTx(id: 'tx-1');
      await insertTx(id: 'tx-2');
      final rows = await SyncOutbox.collectAll(db);
      expect(rows, hasLength(2));

      // 只回执 tx-1（模拟服务端 results 缺失 tx-2）
      await SyncOutbox.clearPending(
          db, rows.where((r) => r.id == 'tx-1').toList());

      expect(await pendingCount('transactions'), 1);
      final rest = await SyncOutbox.collectAll(db);
      expect(rest.single.id, 'tx-2');
    });
  });
}
