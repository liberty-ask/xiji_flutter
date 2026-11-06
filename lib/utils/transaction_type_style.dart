import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme_helper.dart';

/// 交易收支方向（收入 / 支出）的文案、图标与颜色映射。
/// 不计收支（type=2）的中性样式由调用方按需处理。
class TransactionTypeStyle {
  static String label(AppLocalizations l10n, bool isIncome) =>
      isIncome ? l10n.income : l10n.expense;

  static IconData icon(bool isIncome) =>
      isIncome ? Icons.arrow_upward : Icons.arrow_downward;

  static Color color(BuildContext context, bool isIncome) =>
      isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context);
}
