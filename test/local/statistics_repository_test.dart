import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/statistics_repository.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository txRepo;
  late StatisticsRepository statsRepo;

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36'; // 餐饮（内置，支出）
  const shoppingId = '01a15d13-bdef-75ae-8342-df8b6acf41fa'; // 购物（内置，支出）
  const salaryId = '01a15d13-bdf0-7a5f-993a-8442815623e1'; // 工资（内置，收入）

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    txRepo = TransactionRepository(db);
    statsRepo = StatisticsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // 插入一笔交易的便捷方法
  Future<void> seed(
    int type,
    double amount,
    DateTime date, {
    String categoryId = diningId,
    String familyId = 'f1',
  }) =>
      txRepo.insert(TransactionsCompanion.insert(
        type: type,
        categoryId: categoryId,
        amount: amount,
        date: date,
        userId: 'user-1',
        familyId: Value(familyId),
      ));

  group('任务 1.6：客户端统计聚合（对齐服务端口径）', () {
    test('首页月度概览：本月收入、支出、结余、今日与昨日支出', () async {
      final now = DateTime(2026, 10, 15, 12, 0);
      await seed(0, 8000, DateTime(2026, 10, 1), categoryId: salaryId);
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 120, DateTime(2026, 10, 15)); // 今日
      await seed(1, 45, DateTime(2026, 10, 14)); // 昨日
      await seed(1, 60, DateTime(2026, 9, 30)); // 上月（不计入）

      final o = await statsRepo.monthlyOverview('f1', now);

      expect(o.income, 8000);
      expect(o.expense, 30 + 120 + 45);
      expect(o.balance, 8000 - (30 + 120 + 45));
      expect(o.todayExpense, 120);
      expect(o.yesterdayExpense, 45);
    });

    test('家庭隔离：月度概览仅统计当前家庭的交易', () async {
      final now = DateTime(2026, 10, 15);
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 999, DateTime(2026, 10, 3), familyId: 'f2');

      final o = await statsRepo.monthlyOverview('f1', now);
      expect(o.expense, 30, reason: '他家的支出不得计入本家统计');
    });

    test('type=2（不计收支）排除在收支统计之外', () async {
      final now = DateTime(2026, 10, 15);
      await seed(0, 5000, DateTime(2026, 10, 1), categoryId: salaryId);
      await seed(1, 100, DateTime(2026, 10, 2));
      // 不计收支的转账/理财流水（账单导入典型）
      await seed(2, 9999, DateTime(2026, 10, 3));
      await seed(2, 8888, DateTime(2026, 10, 15)); // 今日 type=2 也不进今日支出

      final o = await statsRepo.monthlyOverview('f1', now);
      expect(o.income, 5000, reason: 'type=2 不得污染收入');
      expect(o.expense, 100, reason: 'type=2 不得污染支出');
      expect(o.todayExpense, 0, reason: 'type=2 不得污染今日支出');

      // 分类统计同样排除：type=2 传参直接禁止
      expect(
        () => statsRepo.categoryStatistics(
            familyId: 'f1',
            type: 2,
            start: DateTime(2026, 10, 1),
            end: DateTime(2026, 10, 31)),
        throwsA(isA<AssertionError>()),
        reason: '收支统计禁止 type=2',
      );
    });

    test('墓碑记录排除在统计之外', () async {
      final now = DateTime(2026, 10, 15);
      final deleted = await txRepo.insert(TransactionsCompanion.insert(
        type: 1,
        categoryId: diningId,
        amount: 500,
        date: DateTime(2026, 10, 3),
        userId: 'user-1',
        familyId: const Value('f1'),
      ));
      await seed(1, 100, DateTime(2026, 10, 5));
      await txRepo.softDelete(deleted.id);

      final o = await statsRepo.monthlyOverview('f1', now);
      expect(o.expense, 100, reason: '墓碑不得计入统计');
    });

    test('分类统计：按分类聚合、降序、占比合计为 100%', () async {
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 70, DateTime(2026, 10, 3), categoryId: diningId);
      await seed(1, 100, DateTime(2026, 10, 4), categoryId: shoppingId);
      await seed(0, 8000, DateTime(2026, 10, 5), categoryId: salaryId);
      await seed(1, 999, DateTime(2026, 11, 1)); // 11月，区间外

      final items = await statsRepo.categoryStatistics(
        familyId: 'f1',
        type: 1,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );

      expect(items.length, 2, reason: '仅支出且区间内：购物100、餐饮30+70');
      expect(items.first.name, '购物', reason: '按金额降序');
      expect(items.first.amount, 100);
      expect(items.first.percentage, closeTo(50, 0.001));
      expect(items[1].name, '餐饮');
      expect(items[1].amount, 100);
      expect(items[1].percentage, closeTo(50, 0.001));

      final pctSum =
          items.fold<double>(0, (sum, i) => sum + i.percentage);
      expect(pctSum, closeTo(100, 0.001));
    });

    test('分类统计：分类已删除则条目不展示，金额仍计入分母', () async {
      await seed(1, 100, DateTime(2026, 10, 2));
      // 自定义分类 + 交易，随后软删除分类
      final cat = await db.into(db.categories).insertReturning(
          CategoriesCompanion.insert(
              name: '自定义', icon: 'category', type: 1));
      await seed(1, 50, DateTime(2026, 10, 3), categoryId: cat.id);
      await (db.update(db.categories)..where((c) => c.id.equals(cat.id)))
          .write(const CategoriesCompanion(
        deleted: Value(true),
      ));

      final items = await statsRepo.categoryStatistics(
        familyId: 'f1',
        type: 1,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );

      expect(items.length, 1, reason: '已删除分类的条目不展示');
      expect(items.first.name, '餐饮');
      // 分母含已删分类的 50：占比 = 100/150
      expect(items.first.percentage, closeTo(100 / 150 * 100, 0.001),
          reason: '对齐服务端：total 分母包含被过滤分类的金额');
    });
  });
}
