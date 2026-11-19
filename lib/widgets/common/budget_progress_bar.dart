import 'package:flutter/material.dart';

import '../../utils/budget_progress.dart';

/// 预算进度条：首页预算卡与预算页共用的唯一渲染入口。
///
/// 进度比例与颜色阈值统一由 [BudgetProgress] 计算，页面只传金额，
/// 避免两处各写一套阈值导致分叉。
class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({
    super.key,
    required this.used,
    required this.total,
    this.height = 6,
    this.borderRadius = 6,
  });

  /// 已用金额（元）
  final num? used;

  /// 预算额度（元）；0 或 null 表示未设置预算
  final num? total;

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LinearProgressIndicator(
        value: BudgetProgress.ratio(used, total),
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        valueColor: AlwaysStoppedAnimation<Color>(
          BudgetProgress.color(context, used: used, total: total),
        ),
        minHeight: height,
      ),
    );
  }
}
