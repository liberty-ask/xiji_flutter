import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('任务 1.2：本地库 schema', () {
    final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

    test('建库成功（四表 + FTS5 虚拟表）', () async {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names,
          containsAll(['transactions', 'categories', 'budgets', 'category_rules']));
      expect(names, contains('transactions_fts'),
          reason: 'FTS5 虚拟表必须随库创建');
    });

    test('显式 id 插入后原样保存（客户端 ID 不被改写）', () async {
      const builtinId = '0198f79a-1234-7000-8000-abcdefabcdef';
      await db.into(db.categories).insert(CategoriesCompanion.insert(
            id: const Value(builtinId),
            name: '餐饮',
            icon: 'restaurant',
            type: 1,
            isBuiltin: const Value(true),
          ));

      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals(builtinId)))
          .getSingle();
      expect(row.id, builtinId);
      expect(row.isBuiltin, true);
    });

    test('不传 id 时 clientDefault 生成 UUIDv7，同步字段默认值正确', () async {
      final category = await db.into(db.categories).insertReturning(
          CategoriesCompanion.insert(name: '餐饮', icon: 'restaurant', type: 1));
      expect(category.id, matches(uuidPattern));

      final now = DateTime(2026, 10, 21, 12, 0);
      final tx = await db.into(db.transactions).insertReturning(
          TransactionsCompanion.insert(
            type: 1,
            categoryId: category.id,
            amountCents: 3000,
            date: now,
            userId: 'user-1',
          ));
      expect(tx.id, matches(uuidPattern));
      expect(tx.version, 1, reason: 'LWW 仲裁序号初始为 1');
      expect(tx.deleted, false, reason: '新建记录不应为墓碑');
      expect(tx.syncPending, true, reason: '新建记录默认进入发件箱');
      expect(tx.date, now);
    });

    test('预算表 family+user+year+month 唯一约束', () async {
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
          userId: 'u1', year: 2026, month: 10, amountCents: 300000));

      // 同家庭同用户同月：撞唯一约束
      await expectLater(
        () => db.into(db.budgets).insert(BudgetsCompanion.insert(
            userId: 'u1', year: 2026, month: 10, amountCents: 500000)),
        throwsA(isA<Exception>()),
        reason: '同成员同月重复设置预算应冲突',
      );

      // 同家庭不同成员同月：并存（D8 个人预算制）
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
          userId: 'u2', year: 2026, month: 10, amountCents: 200000));
      final rows = await db.select(db.budgets).get();
      expect(rows.length, 2, reason: '不同成员同月各一条');
    });

    test('学习表 matchText 唯一约束', () async {
      final category = await db.into(db.categories).insertReturning(
          CategoriesCompanion.insert(name: '餐饮', icon: 'restaurant', type: 1));
      await db.into(db.categoryRules).insert(CategoryRulesCompanion.insert(
            matchText: '瑞幸咖啡',
            categoryId: category.id,
            source: 1,
          ));

      await expectLater(
        () => db.into(db.categoryRules).insert(CategoryRulesCompanion.insert(
              matchText: '瑞幸咖啡',
              categoryId: category.id,
              source: 0,
            )),
        throwsA(isA<Exception>()),
        reason: '同一匹配文本的学习条目应收敛为单条',
      );
    });
  });
}
