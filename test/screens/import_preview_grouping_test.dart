import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/bill_import_service.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/parser/bill_csv_parser.dart';
import 'package:xiji_flutter/screens/import/import_bills_screen.dart';

/// 导入预览分组（中性分类方案）：一个交易对方一张卡片，
/// 一个 chip 同时覆盖该商户的收入行与支出行。
void main() {
  BillImportPreviewItem item({
    String? counterparty,
    int? type,
    String? description,
    String categoryId = 'cat',
  }) {
    return BillImportPreviewItem(
      row: ParsedBillRow(
        platformCode: 'alipay',
        date: DateTime(2026, 11, 1),
        amount: 10,
        type: type,
        counterparty: counterparty,
        description: description,
      ),
      duplicate: false,
      categoryId: categoryId,
    );
  }

  test('同一商户收支混合仍是一张卡片，chip 取第一条可指认行', () {
    final expenseFirst = item(
        counterparty: '某商户', type: 1, description: '支出1', categoryId: 'e1');
    final incomeFirst = item(
        counterparty: '某商户', type: 0, description: '收入1', categoryId: 'i1');
    final groups = groupBillPreviewItems([
      expenseFirst,
      incomeFirst,
      item(counterparty: '某商户', type: 1, description: '支出2', categoryId: 'e2'),
    ]);

    expect(groups.length, 1);
    final group = groups.single;
    expect(group.length, 3);
    expect(group.assignable.length, 3,
        reason: '收入行与支出行都参与同一个 chip 的批量写入');
    expect(group.representative, expenseFirst);
  });

  test('type=2 不计收支行不参与批量指认，只能用行级覆盖', () {
    final expense = item(counterparty: '某商户', type: 1);
    final neutral = item(counterparty: '某商户', type: 2);
    final groups = groupBillPreviewItems([expense, neutral]);

    final group = groups.single;
    expect(group.items.length, 2);
    expect(group.assignable, [expense],
        reason: 'type=2 不进 batch write，避免把不计收支塞进分类批量口径');
    expect(group.representative, expense);
  });

  test('指认范围排除退款关联行，其余条目仍可批量指认', () {
    final normal = item(counterparty: '某商户', type: 1);
    final linked = item(counterparty: '某商户', type: 2)..refundLinked = true;
    final groups = groupBillPreviewItems([normal, linked]);

    final group = groups.single;
    expect(group.items.length, 2);
    expect(group.assignable, [normal],
        reason: '退款关联行继承原支出分类，不参与批量指认');
    expect(group.representative, normal);
  });

  test('全部为退款关联行时该卡片不可指认', () {
    final linked = item(counterparty: '某商户', type: 2)..refundLinked = true;
    final groups = groupBillPreviewItems([linked]);
    expect(groups.single.assignable, isEmpty);
  });

  test('无交易对方的行单独成组并排在最后', () {
    final groups = groupBillPreviewItems([
      item(counterparty: null, type: 1),
      item(counterparty: '甲', type: 1),
      item(counterparty: '  ', type: 1),
    ]);
    expect(groups.map((g) => g.counterparty), ['甲', '']);
  });

  test('未分类判定按整卡聚合（用于卡片边框）', () {
    final groups = groupBillPreviewItems([
      item(counterparty: '甲', type: 1, categoryId: 'x'),
      item(
        counterparty: '甲',
        type: 0,
        categoryId: BuiltinCategories.uncategorizedId,
      ),
    ]);
    expect(groups.single.hasUncategorized, true);
  });

  group('三个撤销入口', () {
    test('hasAssigned 只在存在已指认可指认行时为真', () {
      final assigned = groupBillPreviewItems([
        item(counterparty: '甲', type: 1, categoryId: 'x'),
      ]).single;
      expect(assigned.hasAssigned, true);

      final allUnknown = groupBillPreviewItems([
        item(
          counterparty: '甲',
          type: 1,
          categoryId: BuiltinCategories.uncategorizedId,
        ),
      ]).single;
      expect(allUnknown.hasAssigned, false);

      final neutralOnly = groupBillPreviewItems([
        item(counterparty: '甲', type: 2, categoryId: 'x'),
      ]).single;
      expect(neutralOnly.hasAssigned, false, reason: 'type=2 不可批量指认');
    });

    test('撤销本卡：可指认行置未分类，type=2 / 退款关联行保持', () {
      final normal = item(counterparty: '甲', type: 1, categoryId: 'x');
      final income = item(counterparty: '甲', type: 0, categoryId: 'y');
      final neutral = item(counterparty: '甲', type: 2, categoryId: 'z');
      final linked = item(counterparty: '甲', type: 2, categoryId: 'w')
        ..refundLinked = true;
      final group =
          groupBillPreviewItems([normal, income, neutral, linked]).single;

      resetGroupCategories(group);

      expect(normal.categoryId, BuiltinCategories.uncategorizedId);
      expect(income.categoryId, BuiltinCategories.uncategorizedId);
      expect(neutral.categoryId, 'z', reason: 'type=2 不在撤销范围');
      expect(linked.categoryId, 'w', reason: '退款关联行继承原支出分类');
    });

    test('全部置为未分类：所有可指认行置未分类', () {
      final a = item(counterparty: '甲', type: 1, categoryId: 'x');
      final b = item(counterparty: '乙', type: 0, categoryId: 'y');
      final neutral = item(counterparty: '乙', type: 2, categoryId: 'z');
      final linked = item(counterparty: '乙', type: 2, categoryId: 'w')
        ..refundLinked = true;

      resetAllCategories([a, b, neutral, linked]);

      expect(a.categoryId, BuiltinCategories.uncategorizedId);
      expect(b.categoryId, BuiltinCategories.uncategorizedId);
      expect(neutral.categoryId, 'z');
      expect(linked.categoryId, 'w');
    });
  });
}
