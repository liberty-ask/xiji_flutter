import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36'; // 餐饮（内置）

  TransactionsCompanion newTx({
    int type = 1,
    int amountCents = 3000,
    DateTime? date,
    String? description,
    String? counterparty,
    String familyId = 'f1',
  }) =>
      TransactionsCompanion.insert(
        type: type,
        categoryId: diningId,
        amountCents: amountCents,
        date: date ?? DateTime(2026, 10, 1),
        userId: 'user-1',
        familyId: Value(familyId),
        description:
            description == null ? const Value.absent() : Value(description),
        counterparty:
            counterparty == null ? const Value.absent() : Value(counterparty),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('任务 1.4：Repository 交易 CRUD 与软删除墓碑', () {
    test('新增：生成 UUIDv7、发件箱置位、FTS 已可搜到', () async {
      final row = await repo.insert(
          newTx(description: '瑞幸咖啡拿铁', counterparty: '瑞幸咖啡'));

      expect(row.id, isNotEmpty);
      expect(row.syncPending, true, reason: '新增必须进发件箱');
      expect(row.version, 1);
      expect(row.deleted, false);

      final hits = await repo.search('f1', '拿铁');
      expect(hits.map((t) => t.id), [row.id]);
    });

    test('编辑：version+1、updatedAt 刷新、FTS 重建', () async {
      final row = await repo.insert(newTx(
          description: '午餐', counterparty: '公司食堂', amountCents: 1500));
      final before = row.updatedAt;

      final updated = await repo.update(row.id,
          newTx(description: '晚餐', counterparty: '外婆家', amountCents: 4200));

      expect(updated.version, 2, reason: '编辑后 version 递增');
      // drift 存储秒级精度，同秒内编辑允许相等，但不得早于插入时间
      expect(updated.updatedAt.isBefore(before), false,
          reason: 'updatedAt 不得回退');
      expect(updated.syncPending, true);
      expect(updated.amountCents, 4200);

      expect(await repo.search('f1', '午餐'), isEmpty, reason: '旧关键词应从索引清除');
      expect(await repo.search('f1', '晚餐').then((l) => l.single.id), row.id);
      expect(await repo.search('f1', '外婆家').then((l) => l.single.id), row.id);
    });

    test('删除：软删除墓碑保留行、FTS 摘除、列表与搜索均不可见', () async {
      final a = await repo.insert(newTx(description: '瑞幸拿铁'));
      await repo.insert(newTx(description: '星巴克美式'));

      await repo.softDelete(a.id);

      // 墓碑保留在表中（参与同步）
      final tombstone = await (db.select(db.transactions)
            ..where((t) => t.id.equals(a.id)))
          .getSingle();
      expect(tombstone.deleted, true, reason: '删除应为软删除墓碑');
      expect(tombstone.syncPending, true);
      expect(tombstone.version, 2);

      // 列表与单查不可见
      final list = await repo.listAll('f1');
      expect(list.map((t) => t.id), isNot(contains(a.id)));
      expect(await repo.findById(a.id), isNull);
      // 搜索也不可见
      expect(await repo.search('f1', '拿铁'), isEmpty);
      expect(await repo.search('f1', '星巴克'), isNotEmpty);
    });

    test('列表：排除墓碑、按业务日期倒序', () async {
      await repo.insert(
          newTx(description: '早', date: DateTime(2026, 10, 1), amountCents: 1000));
      await repo.insert(
          newTx(description: '晚', date: DateTime(2026, 10, 3), amountCents: 2000));
      final deleted = await repo.insert(
          newTx(description: '中', date: DateTime(2026, 10, 2), amountCents: 3000));
      await repo.softDelete(deleted.id);

      final list = await repo.listAll('f1');
      expect(list.map((t) => t.description), ['晚', '早'],
          reason: '按 date 倒序且排除墓碑');
    });

    test('家庭隔离：列表与搜索仅当前家庭可见', () async {
      await repo.insert(newTx(description: '本家的拿铁'));
      await repo.insert(
          newTx(description: '他家的拿铁', familyId: 'f2'));

      final list = await repo.listAll('f1');
      expect(list.map((t) => t.description), ['本家的拿铁']);
      expect(await repo.search('f1', '拿铁').then((l) => l.single.description),
          '本家的拿铁',
          reason: 'FTS 命中后仍按家庭过滤（同库多家庭不串数据）');
    });

    test('编辑不存在的交易抛错', () async {
      await expectLater(
        () => repo.update('00000000-0000-7000-8000-000000000000',
            const TransactionsCompanion(amountCents: Value(100))),
        throwsStateError,
      );
    });

    test('无描述无交易对方的记录不写 FTS 空行', () async {
      final row = await repo.insert(newTx());
      final ftsRows = await db
          .customSelect('SELECT COUNT(*) AS c FROM transactions_fts')
          .getSingle();
      expect(ftsRows.read<int>('c'), 0, reason: '无正文的记录不应产生 FTS 行');
      expect(await repo.findById(row.id), isNotNull);
    });
  });
}
