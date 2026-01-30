import 'package:flutter/material.dart';
import '../models/theme_extensions.dart';

/// 主题颜色辅助类
/// 用于从BuildContext获取主题颜色
class ThemeHelper {
  static ColorScheme getColorScheme(BuildContext context) {
    return Theme.of(context).colorScheme;
  }

  static AppThemeColors getAppColors(BuildContext context) {
    return Theme.of(context).appColors;
  }

  // 便捷方法：获取主要颜色
  static Color primary(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  // 便捷方法：获取surface颜色
  static Color surface(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  // 便捷方法：获取background颜色
  static Color background(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  // 便捷方法：获取surfaceLight颜色
  static Color surfaceLight(BuildContext context) {
    return Theme.of(context).appColors.surfaceLight;
  }

  // 便捷方法：获取surfaceHighlight颜色
  static Color surfaceHighlight(BuildContext context) {
    return Theme.of(context).appColors.surfaceHighlight;
  }

  // 便捷方法：获取surfaceDark颜色
  static Color surfaceDark(BuildContext context) {
    return Theme.of(context).appColors.surfaceDark;
  }

  // 便捷方法：获取expenseColor颜色
  static Color expenseColor(BuildContext context) {
    return Theme.of(context).appColors.expenseColor;
  }
}

