import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/budget_repository.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/statistics_repository.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/services/api/budget_service.dart';

void main() {
  late AppDatabase db;
  late BudgetService service;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 门面内部经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）；
    // 预算归属经 LocalUser 解析当前用户，预置登录用户 A。
    SharedPreferences.setMockInitialValues({
      LocalUser.profileKey: jsonEncode(User(
        id: 'user-A',
        nickname: 'A',
        phone: '1',
      ).toJson()),
    });
    db = AppDatabase(NativeDatabase.memory());
    service = BudgetService.withRepo(BudgetRepository(db), StatisticsRepository(db));
  });

  tearDown(() async {
    await db.close();
  });

  group('任务 5.6：预算门面本地化（页面零改动的本地读写）', () {
    test('未设置预算返回 budget=null', () async {
      final data = await service.getBudget(year: 2026, month: 10);
      expect(data['budget'], isNull);
    });

    test('设置后读取返回金额', () async {
      await service.setBudget(total: 5000, year: 2026, month: 10);
      final data = await service.getBudget(year: 2026, month: 10);
      expect(data['budget'], 5000);
    });

    test('同月重复设置覆盖且不撞唯一约束', () async {
      await service.setBudget(total: 5000, year: 2026, month: 10);
      await service.setBudget(total: 8000, year: 2026, month: 10);
      final data = await service.getBudget(year: 2026, month: 10);
      expect(data['budget'], 8000);

      // 行级核对：同月仅一行，version 递增
      final rows = await db.select(db.budgets).get();
      expect(rows.length, 1);
      expect(rows.first.version, 2);
    });

    test('跨月互不影响', () async {
      await service.setBudget(total: 5000, year: 2026, month: 10);
      final data = await service.getBudget(year: 2026, month: 11);
      expect(data['budget'], isNull);
    });

    test('默认参数取当前年月', () async {
      final now = DateTime.now();
      await service.setBudget(total: 3000, year: now.year, month: now.month);
      final data = await service.getBudget();
      expect(data['budget'], 3000);
    });

    test('墓碑行被 setBudget 复活而非撞唯一约束', () async {
      // 手工造墓碑行（模拟同步/迁移产生的删除态）
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: 2026,
            month: 10,
            amountCents: 100000,
            deleted: const Value(true),
          ));
      await service.setBudget(total: 6000, year: 2026, month: 10);

      final rows = await db.select(db.budgets).get();
      expect(rows.length, 1);
      expect(rows.first.deleted, false);
      expect(rows.first.amountCents, 600000);
      expect(rows.first.version, 2);

      final data = await service.getBudget(year: 2026, month: 10);
      expect(data['budget'], 6000);
    });
  });

  group('任务 7.1：预算个人化（D8 各成员每月各自一条）', () {
    test('不同成员同月预算互不可见、互不覆盖', () async {
      final repo = BudgetRepository(db);
      const family = '';
      const y = 2026, m = 10;

      // A、B 各设各的：两行并存
      await repo.upsertMonth(
          familyId: family, userId: 'user-A', year: y, month: m, amountCents: 500000);
      await repo.upsertMonth(
          familyId: family, userId: 'user-B', year: y, month: m, amountCents: 200000);
      final rows = await db.select(db.budgets).get();
      expect(rows.length, 2);
      expect(rows.map((r) => r.userId).toSet(), {'user-A', 'user-B'});

      // 各读各的，值不串
      expect((await repo.findByMonth(family, 'user-A', y, m))!.amountCents, 500000);
      expect((await repo.findByMonth(family, 'user-B', y, m))!.amountCents, 200000);
      expect(await repo.findByMonth(family, 'user-C', y, m), isNull);

      // A 改预算不动 B 的
      await repo.upsertMonth(
          familyId: family, userId: 'user-A', year: y, month: m, amountCents: 800000);
      expect((await repo.findByMonth(family, 'user-A', y, m))!.amountCents, 800000);
      expect((await repo.findByMonth(family, 'user-B', y, m))!.amountCents, 200000);
      expect((await db.select(db.budgets).get()).length, 2);
    });
  });

  group('任务 8.5：预算与支出同口径（家庭/个人视图）', () {
    Future<void> seedTx(String userId, int cents, DateTime date) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 1,
            categoryId: '01a15d13-bded-710c-a3bd-aba94a5aeb36',
            amountCents: cents,
            date: date,
            userId: userId,
          ));
    }

    test('个人口径：本人预算 vs 本人支出，进度/剩余/百分比正确', () async {
      const y = 2026, m = 10;
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: y,
            month: m,
            amountCents: 100000, // 1000 元
          ));
      await seedTx('user-A', 30000, DateTime(2026, 10, 5)); // 本人 300
      await seedTx('user-B', 50000, DateTime(2026, 10, 6)); // 他人不计

      final data = await service.getBudget(year: y, month: m);
      expect(data['budget'], 1000);
      expect(data['used'], 300, reason: '个人口径只算本人支出');
      expect(data['remaining'], 700);
      expect(data['percentage'], 30);
    });

    test('家庭口径：预算与支出同为已设预算成员，未设预算成员排除',
        () async {
      const family = '';
      const y = 2026, m = 10;
      final stats = StatisticsRepository(db);

      // A、B 设预算；C 未设
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: y,
            month: m,
            amountCents: 100000,
          ));
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-B',
            year: y,
            month: m,
            amountCents: 50000,
          ));
      // A 300、B 200、C 900（C 未设预算，支出不计入避免进度虚高）
      await seedTx('user-A', 30000, DateTime(2026, 10, 5));
      await seedTx('user-B', 20000, DateTime(2026, 10, 6));
      await seedTx('user-C', 90000, DateTime(2026, 10, 7));

      final p = await stats.familyBudgetProgress(family, y, m);
      expect(p.total, 1500, reason: '预算合计 = A 1000 + B 500');
      expect(p.used, 500, reason: '支出只算已设预算成员 A+B，C 排除');
      expect(p.memberCount, 2, reason: 'X = 已设预算成员数');
    });

    test('家庭口径边界：无人设预算全 0；墓碑预算行不计入', () async {
      const family = '';
      const y = 2026, m = 10;
      final stats = StatisticsRepository(db);

      await seedTx('user-A', 30000, DateTime(2026, 10, 5));
      var p = await stats.familyBudgetProgress(family, y, m);
      expect(p.total, 0);
      expect(p.used, 0, reason: '无人设预算 → 支出无口径可算');
      expect(p.memberCount, 0);

      // 墓碑预算行（远端删除）不参与口径
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: y,
            month: m,
            amountCents: 100000,
            deleted: const Value(true),
          ));
      p = await stats.familyBudgetProgress(family, y, m);
      expect(p.memberCount, 0);
    });

    test('月份窗口隔离：其他月支出与预算不串月', () async {
      const family = '';
      final stats = StatisticsRepository(db);
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: 2026,
            month: 11,
            amountCents: 100000,
          ));
      await seedTx('user-A', 30000, DateTime(2026, 10, 5)); // 10 月支出

      final p10 = await stats.familyBudgetProgress(family, 2026, 10);
      expect(p10.total, 0);
      expect(p10.used, 0);

      final p11 = await stats.familyBudgetProgress(family, 2026, 11);
      expect(p11.total, 1000);
      expect(p11.used, 0, reason: '10 月支出不计入 11 月口径');
    });
  });

  group('预算支出净额口径（退款冲抵，1666 vs 1600 回归）', () {
    const categoryId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

    test('1666 元支出已退 66 → 预算页与首页预算卡同为 1600', () async {
      const y = 2026, m = 11;
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: y,
            month: m,
            amountCents: 200000, // 2000 元
          ));
      // 原支出 1666 元，累计已退 66 元
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 1,
            categoryId: categoryId,
            amountCents: 166600,
            date: DateTime(2026, 11, 5),
            userId: 'user-A',
            refundedCents: const Value(6600),
          ));
      // 退款行自身 type=2（不计收支），不进入支出统计
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 2,
            categoryId: categoryId,
            amountCents: 6600,
            date: DateTime(2026, 11, 6),
            userId: 'user-A',
          ));

      final personal = await service.getBudget(year: y, month: m);
      expect(personal['used'], 1600, reason: '净额法：1666 - 66');
      expect(personal['percentage'], 80, reason: '1600 / 2000 正好 80%');

      final family =
          await StatisticsRepository(db).familyBudgetProgress('', y, m);
      expect(family.used, 1600, reason: '首页预算卡与预算页支出同数');
      expect(family.total, 2000);
    });

    test('统一入口：家庭全部成员与预算成员两种 scope 同源', () async {
      const y = 2026, m = 11;
      final stats = StatisticsRepository(db);
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'user-A',
            year: y,
            month: m,
            amountCents: 200000,
          ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 1,
            categoryId: categoryId,
            amountCents: 166600,
            date: DateTime(2026, 11, 5),
            userId: 'user-A',
            refundedCents: const Value(6600),
          ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 1,
            categoryId: categoryId,
            amountCents: 10000,
            date: DateTime(2026, 11, 7),
            userId: 'user-B', // 未设预算成员
          ));

      final monthStart = DateTime(y, m, 1);
      final monthEnd =
          DateTime(y, m + 1, 1).subtract(const Duration(microseconds: 1));
      final familyExpense = await stats.expenseCentsInRange(
        familyId: '',
        start: monthStart,
        end: monthEnd,
      );
      final budgetedExpense = await stats.expenseCentsInRange(
        familyId: '',
        start: monthStart,
        end: monthEnd,
        userIds: ['user-A'],
      );
      expect(familyExpense, 160000 + 10000, reason: '家庭口径含未设预算成员');
      expect(budgetedExpense, 160000, reason: '预算成员口径仅含 A 的净额');
    });
  });
}
