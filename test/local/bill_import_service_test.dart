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
import 'package:xiji_flutter/data/local/statistics_repository.dart';
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
    String? merchantOrderNo,
    String? counterparty = '某商户',
    String? description = '商品',
    double amount = 25,
    int? type = 1,
    String? status,
    DateTime? date,
  }) {
    return ParsedBillRow(
      platformCode: 'alipay',
      tradeNo: tradeNo,
      merchantOrderNo: merchantOrderNo,
      date: date ?? DateTime(2026, 9, 1, 10, 0, 0),
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
      expect(await transactions.listAll(''), hasLength(2));

      // 第二次导入：全部已存在，仅提示新增条数
      final second = await service.importRows(await service.prepare(csv));
      expect(second.successCount, 0, reason: '重复单号不再入库');
      expect(second.skipCount, 2);
      expect(await transactions.listAll(''), hasLength(2));
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

    test('同一订单号的付款行与退款行（商家单号不同）各入一条，复导幂等', () async {
      final csv = [
        // 京东价保/部分退款：两行共用交易订单号，商家单号不同
        row(
            tradeNo: 'JD1',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '价保退款-商品',
            amount: 3.23,
            type: 2),
        row(
            tradeNo: 'JD1',
            merchantOrderNo: 'M_ORDER',
            description: '商品',
            amount: 33.79,
            type: 1),
      ];
      final first = await service.importRows(await service.prepare(csv));
      expect(first.successCount, 2, reason: '商家单号不同 → 两笔独立交易');
      expect(first.skipCount, 0);

      final saved = await transactions.listAll('');
      expect(saved, hasLength(2));
      final refund =
          saved.firstWhere((t) => t.merchantOrderNo == 'M_REFUND');
      final pay = saved.firstWhere((t) => t.merchantOrderNo == 'M_ORDER');
      expect(refund.type, 2, reason: '净额法：退款冲抵原支出，本身不计收支');
      expect(refund.amountCents, 323);
      expect(refund.refundOfId, pay.id, reason: '退款显式关联原支出');
      expect(refund.categoryId, pay.categoryId, reason: '退款沿用原支出分类');
      expect(pay.type, 1);
      expect(pay.amountCents, 3379, reason: '支出按账单原额入账，净额由退款冲抵');
      expect(pay.refundedCents, 323, reason: '原支出累计已退额');

      // 统计净额：33.79 - 3.23 = 30.56，退款不进收入
      final stats = StatisticsRepository(db);
      final summary = await stats.rangeSummary(
        familyId: '',
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      );
      expect(summary.expense, 30.56);
      expect(summary.income, 0.0);

      final second = await service.importRows(await service.prepare(csv));
      expect(second.successCount, 0, reason: '同一份账单复导幂等');
      expect(second.skipCount, 2);
      expect(await transactions.listAll(''), hasLength(2));
    });

    test('预览即判定退款冲抵：可关联行标记不计收支，无原支出保持收入', () async {
      final items = await service.prepare([
        row(
            tradeNo: 'JD9',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '价保退款-商品',
            amount: 3.23,
            type: 2),
        row(
            tradeNo: 'JD9',
            merchantOrderNo: 'M_ORDER',
            description: '商品',
            amount: 33.79,
            type: 1),
      ]);
      final refundItem = items.firstWhere((i) => i.refund);
      final payItem =
          items.firstWhere((i) => i.row.tradeNo == 'JD9' && i.row.type == 1);
      expect(refundItem.refundLinked, true, reason: '预览应与入库一致按不计收支展示');
      expect(refundItem.categoryId, payItem.categoryId, reason: '沿用原支出分类');

      final orphan = await service.prepare([
        row(
            tradeNo: 'JD10',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 5,
            type: 2),
      ]);
      expect(orphan.single.refundLinked, false, reason: '无原支出时降级为收入展示');
    });

    test('跨月退款仍冲抵原支出所属月份，不在退款当月计负支出', () async {
      final csv = [
        row(
            tradeNo: 'JD2',
            merchantOrderNo: 'M_ORDER',
            amount: 100,
            type: 1,
            date: DateTime(2026, 9, 28, 10)),
        row(
            tradeNo: 'JD2',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 40,
            type: 2,
            date: DateTime(2026, 10, 3, 10)),
      ];
      final outcome = await service.importRows(await service.prepare(csv));
      expect(outcome.successCount, 2);

      final stats = StatisticsRepository(db);
      final sep = await stats.rangeSummary(
        familyId: '',
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      );
      final oct = await stats.rangeSummary(
        familyId: '',
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );
      expect(sep.expense, 60.0, reason: '9 月支出 100 - 40');
      expect(oct.expense, 0.0, reason: '10 月不计负支出');
      expect(oct.income, 0.0, reason: '退款不计收入');
    });

    test('多次部分退款累加到同一原支出（含先导原支出后再导退款）', () async {
      // 第一次：先导入原支出
      await service.importRows(await service.prepare([
        row(tradeNo: 'JD3', merchantOrderNo: 'M_ORDER', amount: 100, type: 1),
      ]));
      // 第二次：同一订单两次退款，各自商家单号不同，且原支出已在库中
      final outcome = await service.importRows(await service.prepare([
        row(
            tradeNo: 'JD3',
            merchantOrderNo: 'M_R1',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 30,
            type: 2),
        row(
            tradeNo: 'JD3',
            merchantOrderNo: 'M_R2',
            counterparty: '京东金融',
            description: '价保退款-商品',
            amount: 20,
            type: 2),
      ]));
      expect(outcome.successCount, 2);

      final saved = await transactions.listAll('');
      final pay = saved.firstWhere((t) => t.merchantOrderNo == 'M_ORDER');
      expect(pay.refundedCents, 5000, reason: '30 + 20 累加');
      expect(pay.version, greaterThan(1), reason: '原支出改动进发件箱');
      final refunds = saved.where((t) => t.refundOfId == pay.id).toList();
      expect(refunds, hasLength(2));
      expect(refunds.every((r) => r.type == 2), true);

      final stats = StatisticsRepository(db);
      expect(
          (await stats.rangeSummary(
            familyId: '',
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 30),
          ))
              .expense,
          50.0);
    });

    test('退款额超过剩余可退额时不关联，降级为独立收入行', () async {
      final outcome = await service.importRows(await service.prepare([
        row(tradeNo: 'JD4', merchantOrderNo: 'M_ORDER', amount: 10, type: 1),
        row(
            tradeNo: 'JD4',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 15,
            type: 2),
      ]));
      expect(outcome.successCount, 2);
      final saved = await transactions.listAll('');
      final refund = saved.firstWhere((t) => t.merchantOrderNo == 'M_REFUND');
      expect(refund.refundOfId, isNull, reason: '超额退款不猜关联');
      expect(refund.type, 0, reason: '降级为独立收入行');
      final pay = saved.firstWhere((t) => t.merchantOrderNo == 'M_ORDER');
      expect(pay.refundedCents, 0);
    });

    test('删除退款行恢复原支出金额', () async {
      await service.importRows(await service.prepare([
        row(tradeNo: 'JD5', merchantOrderNo: 'M_ORDER', amount: 100, type: 1),
        row(
            tradeNo: 'JD5',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 40,
            type: 2),
      ]));
      final saved = await transactions.listAll('');
      final refund = saved.firstWhere((t) => t.merchantOrderNo == 'M_REFUND');
      final pay = saved.firstWhere((t) => t.merchantOrderNo == 'M_ORDER');

      await transactions.softDelete(refund.id);
      final after = await transactions.listAll('');
      expect(after, hasLength(1));
      expect(after.first.refundedCents, 0, reason: '删除退款后支出恢复原额');
      expect(after.first.version, greaterThan(pay.version));
    });

    test('删除原支出级联删除其退款行，不留悬空关联', () async {
      await service.importRows(await service.prepare([
        row(tradeNo: 'JD6', merchantOrderNo: 'M_ORDER', amount: 100, type: 1),
        row(
            tradeNo: 'JD6',
            merchantOrderNo: 'M_REFUND',
            counterparty: '京东金融',
            description: '退款-商品',
            amount: 40,
            type: 2),
      ]));
      final saved = await transactions.listAll('');
      final pay = saved.firstWhere((t) => t.merchantOrderNo == 'M_ORDER');

      await transactions.softDelete(pay.id);
      expect(await transactions.listAll(''), isEmpty, reason: '退款随原支出级联删除');
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

    test('墓碑不占单号：删除后重导成功入库（新 id 独立同步）', () async {
      await service.importRows(await service.prepare([row(tradeNo: 'TN1')]));
      final saved = await transactions.listAll('');
      expect(saved, hasLength(1));

      // 软删除（墓碑）：行保留参与同步，但不再占用单号
      await transactions.softDelete(saved.first.id);
      expect(await transactions.listAll(''), isEmpty,
          reason: '墓碑行不出现在列表查询');

      // 重新导入同一单号：不再被「已导入将跳过」挡住
      final outcome = await service.importRows(await service.prepare([
        row(tradeNo: 'TN1', counterparty: '重导商户')
      ]));
      expect(outcome.successCount, 1, reason: '墓碑不占单号，重导放行');
      expect(outcome.skipCount, 0);

      final again = await transactions.listAll('');
      expect(again, hasLength(1));
      expect(again.first.counterparty, '重导商户');
      expect(again.first.id, isNot(saved.first.id), reason: '重导生成新 id');
    });
  });

  group('任务 3.6：未分类兜底入库不阻塞', () {
    test('未命中行以未分类入库（支出侧），入库不阻塞', () async {
      final preview = await service.prepare([row(counterparty: '陌生商户')]);
      expect(preview.first.categoryId, uncategorizedExpenseId);
      expect(preview.first.isUncategorized, true);

      final outcome = await service.importRows(preview);
      expect(outcome.successCount, 1, reason: '未分类不阻塞入库');

      final saved = await transactions.listAll('');
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
      final saved = await transactions.listAll('');
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
      expect(await transactions.listAll(''), isEmpty);
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

    test('退款守卫：明确标注支出的行不被退款文本改写', () async {
      final preview = await service.prepare([
        row(
            counterparty: '瑞幸咖啡',
            description: '退款-拿铁',
            type: 1,
            status: '退款成功'),
      ]);
      expect(preview.first.row.type, 1, reason: '账单明确标注支出 → 保持支出');
      expect(preview.first.categoryId, diningId, reason: '支出类型命中支出关键词规则');
    });

    test('退款守卫：明确标注收入的行保持收入', () async {
      final preview = await service.prepare([
        row(
            counterparty: '瑞幸咖啡',
            description: '退款-拿铁',
            type: 0,
            status: '退款成功'),
      ]);
      expect(preview.first.row.type, 0, reason: '账单明确标注收入 → 保持收入');
    });

    test('收/支未标注的退款行仍转收入（type=2 唯一合法服务对象）', () async {
      final preview = await service.prepare([
        row(
            counterparty: '瑞幸咖啡',
            description: '退款-拿铁',
            type: 2,
            status: '退款成功'),
      ]);
      expect(preview.first.row.type, 0, reason: '收/支未标注 + 退款佐证 → 收入');
      expect(preview.first.categoryId, uncategorizedIncomeId,
          reason: '收入类型不命中支出关键词规则');
    });
  });
}
