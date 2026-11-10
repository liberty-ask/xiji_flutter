import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3; // ignore: depend_on_referenced_packages
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';

/// v9 -> v10：分类中性化迁移。
///
/// 覆盖点：
/// - categories 重建：删除 type、新增 name_key，旧内置行按 25 个中性常量重写；
/// - 两个「未分类」合并为支出侧唯一 ID，「理财」交易改挂「其他」；
/// - 用户自建分类保留（name_key 为 NULL，显示原文），不因重建丢失。
void main() {
  const customCategoryId = '01a15d13-ff00-7000-8000-000000000001';
  const oldExpenseUncategorizedId = '01a15d13-bdf0-7501-9f3a-5c6d90abc12e';
  const oldIncomeUncategorizedId = '01a15d13-bdf0-7502-8b7c-4d5e6f70890a';
  const oldInvestmentId = '01a15d13-bdf0-7842-87c1-81c76e61eb09';
  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

  Future<Directory> createV9Database() async {
    final dir = await Directory.systemTemp.createTemp('xiji_v10_migration');
    final dbPath = '${dir.path}/xiji.sqlite';
    final raw = sqlite3.sqlite3.open(dbPath);
    // v9 形态：categories 带 type、无 name_key
    raw.execute('CREATE TABLE categories('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'icon TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'is_builtin INTEGER NOT NULL DEFAULT 0, '
        'sort_order INTEGER NOT NULL DEFAULT 0, '
        "family_id TEXT NOT NULL DEFAULT '', "
        'version INTEGER NOT NULL DEFAULT 1, '
        'updated_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'sync_pending INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id))');
    raw.execute('CREATE TABLE transactions('
        'id TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'category_id TEXT NOT NULL, '
        'amount_cents INTEGER NOT NULL, '
        'date INTEGER NOT NULL, '
        'user_id TEXT NOT NULL, '
        "family_id TEXT NOT NULL DEFAULT '', "
        'description TEXT NULL, '
        'counterparty TEXT NULL, '
        'trade_no TEXT NULL, '
        'merchant_order_no TEXT NULL, '
        'pay_method TEXT NULL, '
        'platform TEXT NULL, '
        'refund_of_id TEXT NULL, '
        'refunded_cents INTEGER NOT NULL DEFAULT 0, '
        'version INTEGER NOT NULL DEFAULT 1, '
        'updated_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'sync_pending INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id))');

    // v9 历史内置行：只放迁移要判定的几个，足够验证重建口径
    raw.execute(
      'INSERT INTO categories(id, name, icon, type, is_builtin, sort_order, '
      'updated_at, sync_pending) VALUES (?, ?, ?, 1, 1, 0, 0, 0)',
      [diningId, '餐饮', 'restaurant'],
    );
    raw.execute(
      'INSERT INTO categories(id, name, icon, type, is_builtin, sort_order, '
      'updated_at, sync_pending) VALUES (?, ?, ?, 1, 1, 12, 0, 0)',
      [oldExpenseUncategorizedId, '未分类', 'help_outline'],
    );
    raw.execute(
      'INSERT INTO categories(id, name, icon, type, is_builtin, sort_order, '
      'updated_at, sync_pending) VALUES (?, ?, ?, 0, 1, 6, 0, 0)',
      [oldIncomeUncategorizedId, '未分类', 'help_outline'],
    );
    raw.execute(
      'INSERT INTO categories(id, name, icon, type, is_builtin, sort_order, '
      'updated_at, sync_pending) VALUES (?, ?, ?, 0, 1, 2, 0, 0)',
      [oldInvestmentId, '理财', 'trending_up'],
    );
    // 用户自建分类（旧备份里有 type，迁移后 name_key 为 NULL）
    raw.execute(
      'INSERT INTO categories(id, name, icon, type, is_builtin, sort_order, '
      'updated_at, sync_pending) VALUES (?, ?, ?, 1, 0, 13, 0, 1)',
      [customCategoryId, '自定义甲', 'help_outline'],
    );

    void insertTx(String id, int type, String categoryId, int cents) {
      raw.execute(
        'INSERT INTO transactions(id, type, category_id, amount_cents, date, '
        'user_id, updated_at) VALUES (?, ?, ?, ?, 0, ?, 0)',
        [id, type, categoryId, cents, 'user-1'],
      );
    }

    insertTx('tx-income-uncat', 0, oldIncomeUncategorizedId, 100);
    insertTx('tx-investment', 0, oldInvestmentId, 200);
    insertTx('tx-dining', 1, diningId, 300);
    raw.execute('PRAGMA user_version = 9');
    raw.dispose();
    return dir;
  }

  test('v9 -> v10：删 type 加 name_key、合并未分类、理财改挂其他、自建保留', () async {
    final dir = await createV9Database();
    addTearDown(() async {
      await dir.delete(recursive: true);
    });
    final dbPath = '${dir.path}/xiji.sqlite';

    final db = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(() => db.close());

    // 1) 表结构：type 列已删除、name_key 列存在
    final columns = await db.customSelect('PRAGMA table_info(categories)').get();
    final names = columns.map((r) => r.read<String>('name')).toList();
    expect(names.contains('type'), false, reason: '分类 type 列必须删除');
    expect(names.contains('name_key'), true, reason: '必须新增 name_key 列');

    // 2) 内置分类收敛为 25 个中性分类
    final builtins = await (db.select(db.categories)
          ..where((c) => c.isBuiltin.equals(true)))
        .get();
    expect(builtins.length, 25);
    expect(
      builtins.map((c) => c.nameKey),
      everyElement(isNotNull),
      reason: '内置分类必须落 name_key',
    );
    expect(
      builtins.where((c) => c.name == '理财'),
      isEmpty,
      reason: '「理财」必须删除',
    );
    expect(
      builtins.where((c) => c.name == '未分类').length,
      1,
      reason: '两个未分类合并为一个',
    );

    // 3) 自建分类保留、name_key 为 NULL（显示原文）
    final custom = await (db.select(db.categories)
          ..where((c) => c.id.equals(customCategoryId)))
        .getSingle();
    expect(custom.name, '自定义甲');
    expect(custom.isBuiltin, false);
    expect(custom.nameKey, isNull);
    expect(custom.sortOrder, 13, reason: '自建分类排序不被迁移重排');

    // 4) 交易改挂：收入未分类 → 唯一未分类；理财 → 其他
    final incomeUncat = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-income-uncat')))
        .getSingle();
    expect(incomeUncat.categoryId, BuiltinCategories.uncategorizedId);

    final investment = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-investment')))
        .getSingle();
    expect(investment.categoryId, BuiltinCategories.byName('其他')!.id);
    expect(investment.type, 0, reason: '迁移不改交易方向');

    // 5) 正常交易不变
    final dining = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-dining')))
        .getSingle();
    expect(dining.categoryId, diningId);

    // 6) 重复打开幂等：内置仍是 25 个、自建仍是一行
    await db.close();
    final reopened = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(() => reopened.close());
    final again = await reopened.select(reopened.categories).get();
    expect(again.length, 26, reason: '25 个内置 + 1 个自建，不重复补种');
  });
}
