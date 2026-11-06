import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/utils/amount_format.dart';

/// 金额展示口径：千分位 + 固定 2 位小数，不做万/亿缩写。
/// 统计图表 Y 轴标签、日历热力图格子、列表/详情金额均由本工具产出。
void main() {
  group('AmountFormat.format 统一 2 位小数', () {
    test('0 与空值展示 0.00', () {
      expect(AmountFormat.format(0), '0.00');
      expect(AmountFormat.format(null), '0.00');
    });

    test('小金额补足两位小数', () {
      expect(AmountFormat.format(0.05), '0.05');
      expect(AmountFormat.format(0.5), '0.50');
      expect(AmountFormat.format(-0.5), '-0.50');
    });

    test('千元以下不出现分组符', () {
      expect(AmountFormat.format(100), '100.00');
      expect(AmountFormat.format(999.99), '999.99');
    });

    test('千元以上带千分位（轴标签与日历格子最长形态）', () {
      expect(AmountFormat.format(1234.5), '1,234.50');
      expect(AmountFormat.format(2000), '2,000.00');
      expect(AmountFormat.format(10000), '10,000.00');
      expect(AmountFormat.format(12345.67), '12,345.67');
      expect(AmountFormat.format(-12345.67), '-12,345.67');
    });

    test('超过万元完整展示，不缩写为万/亿', () {
      expect(AmountFormat.format(123456.78), '123,456.78');
      expect(AmountFormat.format(1234567.89), '1,234,567.89');
    });
  });
}
