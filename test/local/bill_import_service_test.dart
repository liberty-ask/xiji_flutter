import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/bill_import_service.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_engine.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/models/category_keyword_rule.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/parser/bill_csv_parser.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CategoryRepository categories;
  late CategoryRuleRepository rules;
  late BillImportService service;

  final testRules = CategoryKeywordRule.parseList('''
  {
    "rules": [
      { "keywords": ["瑞幸"], "category": "餐饮", "type": 1 }
    ]
  }
  ''');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = TransactionRepository(db);
    categories = CategoryRepository(db);
    rules = CategoryRuleRepository(db);
    service = BillImportService.withRepos(
        transactions, rules, CategoryEngine(rules, categories, testRules));

    SharedPreferences.setMockInitialValues({});
    await LocalUser.cache(User(
      id: 'user-1',
      nickname: '测试用户',
      phone: '13800000000',
    ));
  });

  tearDown(() async {
    await db.close();
  });

  final diningId = BuiltinCategories.byName('餐饮', 1)!.id;
  final uncategorizedExpenseId = BuiltinCategories.uncategorizedExpenseId;
  final uncategorizedIncomeId = BuiltinCategories.uncategorizedIncomeId;

  ParsedBillRow row({
    String? tradeNo = 'TN001',
    String? counterparty = '某商户',
    String? description = '商品',
    double amount = 25,
    int? type = 1,
    String? status,
  }) {
    return ParsedBillRow(
      platformCode: 'alipay',
      tradeNo: tradeNo,
      date: DateTime(2026, 9, 1, 10, 0, 0),
      amount: amount,
      type: type,
      counterparty: counterparty,
      description: description,
      status: status,
    );
  }

  group('任务 3.4：本地 tradeNo 去重', () {
    test('同一 CSV 导入两次仅新增缺失单号', () async {
      final csv = [
        row(tradeNo: 'TN1'),
        row(tradeNo: 'TN2'),
      ];
      final first = await service.importRows(await service.prepare(csv));
      expect(first.successCount, 2);
      expect(first.skipCount, 0);
      expect(await transactions.listAll(), hasLength(2));

      // 第二次导入：全部已存在，仅提示新增条数
      final second = await service.importRows(await service.prepare(csv));
      expect(second.successCount, 0, reason: '重复单号不再入库');
      expect(second.skipCount, 2);
      expect(await transactions.listAll(), hasLength(2));
    });

    test('同一批次内重复单号只入库一条', () async {
      final outcome = await service.importRows(await service.prepare([
        row(tradeNo: 'TN1'),
        row(tradeNo: 'TN1'),
      ]));
      expect(outcome.successCount, 1);
      expect(outcome.skipCount, 1);
    });

    test('单号缺失的行不去重，各入一条', () async {
      final outcome = await service.importRows(await service.prepare([
        row(tradeNo: null),
        row(tradeNo: null),
      ]));
      expect(outcome.successCount, 2);
      expect(outcome.skipCount, 0);
    });

    test('与历史单号去重：prepare 阶段即标记重复', () async {
      await service.importRows(await service.prepare([row(tradeNo: 'OLD1')]));

      final preview = await service.prepare([
        row(tradeNo: 'OLD1'),
        row(tradeNo: 'NEW1'),
      ]);
      expect(preview[0].duplicate, true);
      expect(preview[1].duplicate, false);
    });
  });

  group('任务 3.6：未分类兜底入库不阻塞', () {
    test('未命中行以未分类入库（支出侧），入库不阻塞', () async {
      final preview = await service.prepare([row(counterparty: '陌生商户')]);
      expect(preview.first.categoryId, uncategorizedExpenseId);
      expect(preview.first.isUncategorized, true);

      final outcome = await service.importRows(preview);
      expect(outcome.successCount, 1, reason: '未分类不阻塞入库');

      final saved = await transactions.listAll();
      expect(saved.first.categoryId, uncategorizedExpenseId);
      expect(saved.first.counterparty, '陌生商户');
      expect(saved.first.tradeNo, 'TN001');
    });

    test('收入未命中挂收入侧未分类', () async {
      final preview =
          await service.prepare([row(type: 0, counterparty: '陌生来源')]);
      expect(preview.first.categoryId, uncategorizedIncomeId);
    });

    test('未分类记录入库后可修改分类', () async {
      await service.importRows(await service.prepare([
        row(tradeNo: 'UNC1', counterparty: '陌生商户')
      ]));
      final saved = await transactions.listAll();
      expect(saved.first.categoryId, uncategorizedExpenseId);

      // 入库后修改分类为餐饮
      final updated = await transactions.update(
        saved.first.id,
        TransactionsCompanion(categoryId: Value(diningId)),
      );
      expect(updated.categoryId, diningId);
      expect(updated.version, saved.first.version + 1, reason: '变更进入同步仲裁');
    });

    test('收/支类型未知的行判失败，不计入成功', () async {
      final outcome = await service
          .importRows(await service.prepare([row(type: null)]));
      expect(outcome.failCount, 1);
      expect(outcome.successCount, 0);
      expect(outcome.failures, isNotEmpty);
      expect(await transactions.listAll(), isEmpty);
    });
  });

  group('分类预填与指认回写', () {
    test('引擎预填命中：瑞幸 → 餐饮', () async {
      final preview = await service.prepare([
        row(counterparty: '瑞幸咖啡（杭州）有限公司')
      ]);
      expect(preview.first.categoryId, diningId);
    });

    test('批量指认回写学习表，下次同商户自动命中', () async {
      await service.assignCategory(
          counterparty: '陌生商户', categoryId: diningId);

      final preview = await service.prepare([row(counterparty: '陌生商户')]);
      expect(preview.first.categoryId, diningId,
          reason: '指认回写后自动命中，不再是未分类');

      final entry = await rules.findByMatchText('陌生商户');
      expect(entry!.categoryId, diningId);
      expect(entry.source, 0, reason: '0-账单导入');
      expect(entry.hitCount, 1, reason: 'prepare 命中即计数');
    });

    test('退款行强制转收入（对齐服务端导入语义）', () async {
      final preview = await service.prepare([
        row(
            counterparty: '瑞幸咖啡',
            description: '退款-拿铁',
            type: 1,
            status: '退款成功'),
      ]);
      expect(preview.first.row.type, 0, reason: '描述/状态含退款 → 收入');
      expect(preview.first.categoryId, uncategorizedIncomeId,
          reason: '收入类型不命中支出关键词规则');
    });
  });
}
