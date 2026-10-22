import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/budget_repository.dart';
import 'package:xiji_flutter/services/api/budget_service.dart';

void main() {
  late AppDatabase db;
  late BudgetService service;

  setUp(() {
    // 门面内部经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    service = BudgetService.withRepo(BudgetRepository(db));
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
            year: 2026,
            month: 10,
            amount: 1000,
            deleted: const Value(true),
          ));
      await service.setBudget(total: 6000, year: 2026, month: 10);

      final rows = await db.select(db.budgets).get();
      expect(rows.length, 1);
      expect(rows.first.deleted, false);
      expect(rows.first.amount, 6000);
      expect(rows.first.version, 2);

      final data = await service.getBudget(year: 2026, month: 10);
      expect(data['budget'], 6000);
    });
  });
}
