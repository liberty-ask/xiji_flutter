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

      final rows = await SyncOutbox.collectAll(db, 'f1');
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

      final rows = await SyncOutbox.collectAll(db, 'f1');
      expect(rows, hasLength(1));
      expect(rows.first.deleted, true);
      expect(rows.first.version, 2);
    });

    test('已推送标记与内置分类不重复收集', () async {
      await insertTx();
      await insertCategory();
      await SyncOutbox.clearPending(
          db, (await SyncOutbox.collectAll(db, 'f1')).toList());
      await db.seedBuiltinCategories(); // syncPending=false

      expect(await SyncOutbox.collectAll(db, 'f1'), isEmpty);
      expect(await pendingCount('transactions'), 0);
      expect(await pendingCount('categories'), 0);
    });
  });

  group('任务 7.3：加密构造（encryptRecord/decryptRecord）', () {
    final dataKey =
        Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));

    test('加密可解密回原载荷；字段对齐服务端 SyncPushRecord', () async {
      await insertTx();
      final row = (await SyncOutbox.collectAll(db, 'f1')).single;

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
      final row = (await SyncOutbox.collectAll(db, 'f1')).single;

      final a = await SyncOutbox.encryptRecord(dataKey, row);
      final b = await SyncOutbox.encryptRecord(dataKey, row);
      expect(a['nonce'], isNot(equals(b['nonce'])));
      expect(a['ciphertext'], isNot(equals(b['ciphertext'])));
    });

    test('AAD 绑定记录 ID：换 ID 解密必须失败', () async {
      await insertTx();
      final row = (await SyncOutbox.collectAll(db, 'f1')).single;
      final record = await SyncOutbox.encryptRecord(dataKey, row);

      final forged = Map<String, dynamic>.from(record)..['id'] = 'tx-other';
      expect(
        () => SyncOutbox.decryptRecord(dataKey, forged),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('阶段 4：批量加解密（encryptBatch/decryptBatch）', () {
    // 全部为合成数据：合成 ID / 金额 / 描述，无真实账单特征
    final dataKey =
        Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) % 256));

    SyncPendingRow syntheticRow(int i) => SyncPendingRow(
          recordType: 'transaction',
          id: 'tx-batch-$i',
          version: 1,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i),
          deleted: false,
          familyId: 'f1',
          payload: <String, dynamic>{
            'recordType': 'transaction',
            'type': 1,
            'categoryId': 'cat-synthetic',
            'amountCents': 1000 + i,
            SyncOutbox.kDateMsField: 1700000000000 + i,
            'userId': 'user-synthetic',
            'familyId': 'f1',
            'description': '合成记录 $i',
            'refundedCents': 0,
          },
        );

    test('批量加密与单条结果一致（字段 + 明文往返）', () async {
      final rows = List.generate(20, syntheticRow);
      final singles = <Map<String, dynamic>>[
        for (final row in rows) await SyncOutbox.encryptRecord(dataKey, row),
      ];
      final batch = await SyncOutbox.encryptBatch(dataKey, rows);

      expect(batch, hasLength(singles.length));
      for (var i = 0; i < rows.length; i++) {
        expect(batch[i]['id'], singles[i]['id']);
        expect(batch[i]['version'], singles[i]['version']);
        expect(batch[i]['updatedAt'], singles[i]['updatedAt']);
        expect(batch[i]['deleted'], singles[i]['deleted']);
        expect(base64Decode(batch[i]['nonce'] as String), hasLength(12));
        expect(await SyncOutbox.decryptRecord(dataKey, batch[i]),
            rows[i].payload);
      }
    });

    test('批量解密跨 500 分块完整且顺序一致', () async {
      final rows = List.generate(1200, syntheticRow);
      final records = await SyncOutbox.encryptBatch(dataKey, rows);
      final plain = await SyncOutbox.decryptBatch(dataKey, records);

      expect(plain, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        expect(plain[i], isNotNull);
        expect(plain[i]!['amountCents'], rows[i].payload['amountCents']);
        expect(plain[i]!['description'], rows[i].payload['description']);
      }
    });

    test('批量解密单条认证失败返回 null 占位，不中断整批', () async {
      final rows = List.generate(5, syntheticRow);
      final records = await SyncOutbox.encryptBatch(dataKey, rows);
      // 换 ID 破坏 AAD（模拟密文换位/他人密文）
      records[2] = Map<String, dynamic>.from(records[2])
        ..['id'] = 'tx-forged';

      final plain = await SyncOutbox.decryptBatch(dataKey, records);
      expect(plain, hasLength(5));
      expect(plain[2], isNull);
      expect(plain.whereType<Map<String, dynamic>>(), hasLength(4));
    });

    test('空列表直接返回空（不发 isolate）', () async {
      expect(await SyncOutbox.encryptBatch(dataKey, const []), isEmpty);
      expect(await SyncOutbox.decryptBatch(dataKey, const []), isEmpty);
    });
  });

  group('任务 7.3：清标记（clearPending）', () {
    test('只清传入行，批次内部分失败条目保留', () async {
      await insertTx(id: 'tx-1');
      await insertTx(id: 'tx-2');
      final rows = await SyncOutbox.collectAll(db, 'f1');
      expect(rows, hasLength(2));

      // 只回执 tx-1（模拟服务端 results 缺失 tx-2）
      await SyncOutbox.clearPending(
          db, rows.where((r) => r.id == 'tx-1').toList());

      expect(await pendingCount('transactions'), 1);
      final rest = await SyncOutbox.collectAll(db, 'f1');
      expect(rest.single.id, 'tx-2');
    });

    test('推送在途时被本地编辑（version 已变）不清标记', () async {
      final tx = await insertTx(id: 'tx-1');
      final rows = await SyncOutbox.collectAll(db, 'f1');
      expect(rows, hasLength(1));

      // 模拟推送请求在途期间用户编辑了同一笔（仓储写路径：version+1、
      // updatedAt 前进、sync_pending 保持 true）
      await (db.update(db.transactions)..where((t) => t.id.equals('tx-1')))
          .write(TransactionsCompanion(
        version: const Value(2),
        updatedAt: Value(tx.updatedAt.add(const Duration(seconds: 5))),
        amountCents: const Value(5000),
      ));

      // 回执按出栈快照清理：版本已变，必须保留待推
      await SyncOutbox.clearPending(db, rows);

      expect(await pendingCount('transactions'), 1);
      final rest = await SyncOutbox.collectAll(db, 'f1');
      expect(rest.single.version, 2);
      expect(rest.single.payload['amountCents'], 5000);
    });
  });
}
