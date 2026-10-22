import 'package:intl/intl.dart';

/// 全局金额展示格式化（千分位 + 固定 2 位小数）。
///
/// 口径：本地库/门面返回原始 double（浮点累加误差真实存在，如
/// 8425.670000000001），展示层统一在本工具截断——门面保持数据语义，
/// 格式化收敛在展示层（与既有首页 NumberFormat('#,##0.00') 惯例对齐）。
/// 空间受限的简写场景（日历格子 +1.2w 等）不适用本工具。
class AmountFormat {
  AmountFormat._();

  static final NumberFormat _formatter = NumberFormat('#,##0.00');

  /// 千分位 + 2 位小数：8425.670000000001 -> 8,425.67
  static String format(num? value) => _formatter.format(value ?? 0);
}
