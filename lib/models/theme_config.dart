import 'package:flutter/material.dart';
import 'theme_extensions.dart';

class ThemeConfig {
  final String id;
  final String name;
  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color expense;
  final Color background;
  final Color backgroundDark;
  final Color backgroundLight;
  final Color surface;
  final Color surfaceDark;
  final Color surfaceLight;
  final Color surfaceHighlight;

  ThemeConfig({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    required this.expense,
    required this.background,
    required this.backgroundDark,
    required this.backgroundLight,
    required this.surface,
    required this.surfaceDark,
    required this.surfaceLight,
    required this.surfaceHighlight,
  });

  // 预定义主题列表
  static final List<ThemeConfig> themes = [
    ThemeConfig(
      id: 'green',
      name: '清新绿',
      primary: const Color(0xFF13EC5B),
      primaryDark: const Color(0xFF0EA641),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF050D08),
      backgroundDark: const Color(0xFF030805),
      backgroundLight: const Color(0xFF0A160D),
      surface: const Color(0xFF0C1A12),
      surfaceDark: const Color(0xFF08120C),
      surfaceLight: const Color(0xFF142B1D),
      surfaceHighlight: const Color(0xFF1D3D29),
    ),
    ThemeConfig(
      id: 'blue',
      name: '天空蓝',
      primary: const Color(0xFF3B82F6),
      primaryDark: const Color(0xFF2563EB),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF050D1A),
      backgroundDark: const Color(0xFF030812),
      backgroundLight: const Color(0xFF0A1526),
      surface: const Color(0xFF0C1A2E),
      surfaceDark: const Color(0xFF081220),
      surfaceLight: const Color(0xFF142B44),
      surfaceHighlight: const Color(0xFF1D3D5C),
    ),
    ThemeConfig(
      id: 'purple',
      name: '优雅紫',
      primary: const Color(0xFFA855F7),
      primaryDark: const Color(0xFF9333EA),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF0F0519),
      backgroundDark: const Color(0xFF0A0312),
      backgroundLight: const Color(0xFF1A0D2E),
      surface: const Color(0xFF1D1430),
      surfaceDark: const Color(0xFF150D22),
      surfaceLight: const Color(0xFF2D1F44),
      surfaceHighlight: const Color(0xFF3D295C),
    ),
    ThemeConfig(
      id: 'orange',
      name: '温暖橙',
      primary: const Color(0xFFF97316),
      primaryDark: const Color(0xFFEA580C),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF1A0D05),
      backgroundDark: const Color(0xFF120903),
      backgroundLight: const Color(0xFF2E1A0D),
      surface: const Color(0xFF301D14),
      surfaceDark: const Color(0xFF22150D),
      surfaceLight: const Color(0xFF442D1F),
      surfaceHighlight: const Color(0xFF5C3D29),
    ),
    ThemeConfig(
      id: 'pink',
      name: '浪漫粉',
      primary: const Color(0xFFEC4899),
      primaryDark: const Color(0xFFDB2777),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF1A0512),
      backgroundDark: const Color(0xFF12030A),
      backgroundLight: const Color(0xFF2E0D1A),
      surface: const Color(0xFF30141D),
      surfaceDark: const Color(0xFF220D15),
      surfaceLight: const Color(0xFF441F2D),
      surfaceHighlight: const Color(0xFF5C293D),
    ),
    ThemeConfig(
      id: 'cyan',
      name: '海洋青',
      primary: const Color(0xFF06B6D4),
      primaryDark: const Color(0xFF0891B2),
      secondary: const Color(0xFFFBBF24),
      expense: const Color(0xFFFF4D4D),
      background: const Color(0xFF051A1D),
      backgroundDark: const Color(0xFF031215),
      backgroundLight: const Color(0xFF0D2E32),
      surface: const Color(0xFF14303D),
      surfaceDark: const Color(0xFF0D2228),
      surfaceLight: const Color(0xFF1F444D),
      surfaceHighlight: const Color(0xFF295C6B),
    ),
  ];

  // 默认主题
  static ThemeConfig get defaultTheme => themes[0];

  // 根据ID获取主题
  static ThemeConfig? getThemeById(String id) {
    try {
      return themes.firstWhere((theme) => theme.id == id);
    } catch (e) {
      return null;
    }
  }

  // 生成ThemeData
  ThemeData toThemeData({Brightness brightness = Brightness.dark}) {
    final isDark = brightness == Brightness.dark;
    
    // 定义浅色主题的颜色
    final lightBackgroundColor = Colors.grey[50]!;
    final lightCardColor = Colors.white;
    final lightTextColor = Colors.grey[900]!;
    final lightSubTextColor = Colors.grey[600]!;
    final lightBorderColor = Colors.grey[200]!;
    
    return ThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: isDark ? background : lightBackgroundColor,
      colorScheme: isDark ? ColorScheme.dark(
        primary: primary,
        secondary: primaryDark,
        surface: surface,
        error: expense,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onBackground: Colors.white,
        onError: Colors.white,
      ) : ColorScheme.light(
        primary: primary,
        secondary: primaryDark,
        surface: lightCardColor,
        error: expense,
        background: lightBackgroundColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextColor!,
        onBackground: lightTextColor,
        onError: Colors.white,
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppThemeColors(
          surfaceLight: surfaceLight,
          surfaceHighlight: surfaceHighlight,
          backgroundDark: backgroundDark,
          backgroundLight: backgroundLight,
          surfaceDark: surfaceDark,
          expenseColor: expense,
          secondaryColor: secondary,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? surface : primary,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.white),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? surface : lightCardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? Colors.white.withAlpha(25) : lightBorderColor),
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? background : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.3) : primary.withAlpha(150)),
          foregroundColor: isDark ? Colors.white : primary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceDark : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(25) : lightBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        labelStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey[700]),
        hintStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey[400]),
        prefixIconColor: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey[600],
        suffixIconColor: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey[600],
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: isDark ? Colors.white : lightTextColor),
        displayMedium: TextStyle(color: isDark ? Colors.white : lightTextColor),
        displaySmall: TextStyle(color: isDark ? Colors.white : lightTextColor),
        headlineLarge: TextStyle(color: isDark ? Colors.white : lightTextColor),
        headlineMedium: TextStyle(color: isDark ? Colors.white : lightTextColor),
        headlineSmall: TextStyle(color: isDark ? Colors.white : lightTextColor),
        titleLarge: TextStyle(color: isDark ? Colors.white : lightTextColor),
        titleMedium: TextStyle(color: isDark ? Colors.white : lightTextColor),
        titleSmall: TextStyle(color: isDark ? Colors.white : lightSubTextColor),
        bodyLarge: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.9) : lightTextColor),
        bodyMedium: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.8) : lightSubTextColor),
        bodySmall: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.grey[500]),
        labelLarge: TextStyle(color: isDark ? Colors.white : primary),
        labelMedium: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.8) : primary),
        labelSmall: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.6) : primary.withAlpha(180)),
      ),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.8) : lightSubTextColor,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : lightBorderColor,
        thickness: 1,
      ),
    );
  }
}

