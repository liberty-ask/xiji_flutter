import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/backup_import_service.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late BackupImportService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = BackupImportService(db);
    SharedPreferences.setMockInitialValues({'current_family_id': 'fam-1'});
  });

  tearDown(() async {
    await db.close();
  });

  final diningId = BuiltinCategories.byName('餐饮', 1)!.id;
  final salaryId = BuiltinCategories.byName('工资', 0)!.id;

  /// 最小备份样本：1 内置命中 + 1 自定义 + 2 交易 + 1 预算
  String backupJson({
    String? txId,
  }) =>
      '''
{
  "version": 1,
  "exportedAt": "2026-10-22T12:00:00",
  "categories": [
    {"id": "9001", "name": "餐饮", "icon": "restaurant", "type": 1, "sortOrder": 0, "builtin": false},
    {"id": "9002", "name": "工资", "icon": "payments", "type": 0, "sortOrder": 0, "builtin": false},
    {"id": "9003", "name": "宠物医疗", "icon": "pets", "type": 1, "sortOrder": 5, "builtin": false}
  ],
  "transactions": [
    {"id": "${txId ?? '7001'}", "familyId": "2009264986999275522", "type": 1, "amount": 47.62,
     "categoryId": "9001", "payMethod": "余额宝", "date": "2021-01-01",
     "description": "早餐", "platform": "支付宝", "counterparty": "包子铺",
     "merchantOrderNo": null, "tradeNo": "TN-1", "createdBy": "2009264986806337537",
     "updatedAt": "2026-01-09 21:28:32"},
    {"id": "7002", "familyId": "2009264986999275522", "type": 0, "amount": 2000.00,
     "categoryId": "9002", "payMethod": null, "date": "2026-01-05",
     "description": null, "platform": null, "counterparty": null,
     "merchantOrderNo": null, "tradeNo": null, "createdBy": "2009264986806337538",
     "updatedAt": "2026-01-05 09:00:00"}
  ],
  "budgets": [
    {"familyId": "2009264986999275522", "amount": 2000.00}
  ]
}
''';

  test('内置分类按名称+类型映射，自定义分类保原 ID 插入归属当前家庭', () async {
    final result = await service.importFromString(backupJson());

    expect(result.categoriesMappedBuiltin, 2); // 餐饮+工资
    expect(result.categoriesInserted, 1); // 宠物医疗
    final custom = await (db.select(db.categories)
          ..where((c) => c.id.equals('9003')))
        .getSingle();
    expect(custom.familyId, 'fam-1');
    expect(custom.isBuiltin, false);
    expect(custom.icon, 'pets');
    // 分类总数 = 内置 18 + 自定义 1
    final all = await db.select(db.categories).get();
    expect(all.length, BuiltinCategories.all.length + 1);
  });

  test('交易：ID/categoryId/createdAt 时间戳/归属用户与家庭映射正确', () async {
    await service.importFromString(backupJson());

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('7001')))
        .getSingle();
    expect(tx.type, 1);
    expect(tx.amount, 47.62);
    expect(tx.categoryId, diningId); // 9001 -> 内置餐饮 UUID
    expect(tx.familyId, 'fam-1'); // 归一化当前家庭
    expect(tx.userId, '2009264986806337537');
    expect(tx.platform, '支付宝');
    expect(tx.tradeNo, 'TN-1');
    expect(tx.updatedAt, DateTime(2026, 1, 9, 21, 28, 32)); // 保留导出时间戳
    expect(tx.deleted, false);

    final tx2 = await (db.select(db.transactions)
          ..where((t) => t.id.equals('7002')))
        .getSingle();
    expect(tx2.categoryId, salaryId);
    expect(tx2.userId, '2009264986806337538'); // 另一成员归属保留
  });

  test('预算灌入当前家庭当月', () async {
    await service.importFromString(backupJson());

    final now = DateTime.now();
    final budget = await (db.select(db.budgets)
          ..where((b) =>
              b.familyId.equals('fam-1') &
              b.year.equals(now.year) &
              b.month.equals(now.month)))
        .getSingle();
    expect(budget.amount, 2000.0);
  });

  test('幂等：重复导入零副作用（分类同名映射、交易按 ID 跳过、预算不覆盖）', () async {
    await service.importFromString(backupJson());
    // 幂等导入之间用户改了当月预算，导入不得覆盖
    await (db.update(db.budgets)
          ..where((b) => b.familyId.equals('fam-1')))
        .write(const BudgetsCompanion(amount: Value(5000)));

    final result = await service.importFromString(backupJson());

    expect(result.transactionsInserted, 0);
    expect(result.transactionsSkipped, 2);
    // 重复导入分类全部走映射/跳过，不再插入
    expect(result.categoriesInserted, 0);
    expect(result.categoriesMappedBuiltin, 2);
    expect(result.categoriesSkipped, 1);
    expect(result.budgetsImported, 0);
    final all = await db.select(db.transactions).get();
    expect(all.length, 2);
    final budget = await (db.select(db.budgets)
          ..where((b) => b.familyId.equals('fam-1')))
        .getSingle();
    expect(budget.amount, 5000.0);
  });

  test('坏 JSON 与版本不符抛 FormatException', () async {
    await expectLater(
        service.importFromString('not json'), throwsFormatException);
    await expectLater(
        service.importFromString('{"version": 99}'), throwsFormatException);
  });

  test('导入后 FTS 可搜索：描述与交易对方关键词命中导入交易（回填存量）',
      () async {
    final repo = TransactionRepository(db);
    // 导入器直写主表绕过 Repository 的 FTS 双写，导入末尾的 FTS
    // 全量重建负责回填——真机 5.8 验证踩过的坑（搜索索引为空）
    await service.importFromString(backupJson());

    final hits1 = await repo.search('fam-1', '包子');
    expect(hits1.length, 1); // 交易对方命中
    expect(hits1.first.id, '7001');
    final hits2 = await repo.search('fam-1', '早餐');
    expect(hits2.length, 1); // 描述命中
    final hits3 = await repo.search('fam-1', '工资');
    expect(hits3, isEmpty); // 描述/对方为空的记录不进索引，搜索不出
  });
}
