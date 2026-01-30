import 'package:flutter/material.dart';

/// 扩展ThemeData以支持自定义颜色
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color surfaceLight;
  final Color surfaceHighlight;
  final Color backgroundDark;
  final Color backgroundLight;
  final Color surfaceDark;
  final Color expenseColor;
  final Color secondaryColor;

  const AppThemeColors({
    required this.surfaceLight,
    required this.surfaceHighlight,
    required this.backgroundDark,
    required this.backgroundLight,
    required this.surfaceDark,
    required this.expenseColor,
    required this.secondaryColor,
  });

  @override
  AppThemeColors copyWith({
    Color? surfaceLight,
    Color? surfaceHighlight,
    Color? backgroundDark,
    Color? backgroundLight,
    Color? surfaceDark,
    Color? expenseColor,
    Color? secondaryColor,
  }) {
    return AppThemeColors(
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      backgroundLight: backgroundLight ?? this.backgroundLight,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      expenseColor: expenseColor ?? this.expenseColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) {
      return this;
    }
    return AppThemeColors(
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceHighlight: Color.lerp(surfaceHighlight, other.surfaceHighlight, t)!,
      backgroundDark: Color.lerp(backgroundDark, other.backgroundDark, t)!,
      backgroundLight: Color.lerp(backgroundLight, other.backgroundLight, t)!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      expenseColor: Color.lerp(expenseColor, other.expenseColor, t)!,
      secondaryColor: Color.lerp(secondaryColor, other.secondaryColor, t)!,
    );
  }
}

/// 扩展方法：从ThemeData获取AppThemeColors
extension ThemeDataExtension on ThemeData {
  AppThemeColors get appColors {
    return extension<AppThemeColors>() ?? const AppThemeColors(
      surfaceLight: Color(0xFF142B1D),
      surfaceHighlight: Color(0xFF1D3D29),
      backgroundDark: Color(0xFF030805),
      backgroundLight: Color(0xFF0A160D),
      surfaceDark: Color(0xFF08120C),
      expenseColor: Color(0xFFFF4D4D),
      secondaryColor: Color(0xFFFBBF24),
    );
  }
}

