import 'package:flutter/material.dart';

import 'theme_helper.dart';

/// 预算进度统一口径：进度比例与颜色分档的唯一计算入口。
///
/// 首页预算卡与预算页进度条共用，禁止在页面内重复写阈值。
/// 颜色按未取整的原始比例判定，达到即变色：
/// ≥100% 超支红、≥80% 接近橙、其余正常主色。
/// 预算为 0（未设置）不判超支，返回 0 进度与正常色。
class BudgetProgress {
  BudgetProgress._();

  /// 接近阈值（含）
  static const double warningRatio = 0.8;

  /// 超支阈值（含）
  static const double overRatio = 1.0;

  /// 进度条比例：0~1，预算为 0 时 0
  static double ratio(num? used, num? total) {
    final t = (total ?? 0).toDouble();
    if (t <= 0) return 0;
    return ((used ?? 0).toDouble() / t).clamp(0.0, 1.0);
  }

  /// 进度条颜色：用未取整的原始比例判定，避免四舍五入误判分档
  static Color color(BuildContext context, {num? used, num? total}) {
    final t = (total ?? 0).toDouble();
    if (t <= 0) return ThemeHelper.primary(context);
    final r = (used ?? 0).toDouble() / t;
    if (r >= overRatio) return ThemeHelper.expenseColor(context);
    if (r >= warningRatio) return Colors.orange;
    return ThemeHelper.primary(context);
  }
}
