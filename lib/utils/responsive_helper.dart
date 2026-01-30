import 'package:flutter/material.dart';

/// 响应式布局辅助类
/// 提供跨端适配的工具方法
class ResponsiveHelper {
  // 屏幕尺寸阈值
  static const double smallScreenHeight = 700.0; // 小屏设备（如小屏手机）
  static const double largeScreenHeight = 900.0; // 大屏设备（如平板、PC）
  static const double smallScreenWidth = 360.0;  // 小屏宽度
  static const double largeScreenWidth = 768.0;  // 大屏宽度（平板及以上）

  /// 获取屏幕尺寸信息
  static MediaQueryData getMediaQuery(BuildContext context) {
    return MediaQuery.of(context);
  }

  /// 判断是否为小屏设备（高度）
  static bool isSmallScreen(BuildContext context) {
    return getMediaQuery(context).size.height < smallScreenHeight;
  }

  /// 判断是否为小屏设备（宽度）
  static bool isSmallScreenWidth(BuildContext context) {
    return getMediaQuery(context).size.width < smallScreenWidth;
  }

  /// 判断是否为大屏设备（高度）
  static bool isLargeScreen(BuildContext context) {
    return getMediaQuery(context).size.height > largeScreenHeight;
  }

  /// 判断是否为大屏设备（宽度）
  static bool isLargeScreenWidth(BuildContext context) {
    return getMediaQuery(context).size.width > largeScreenWidth;
  }

  /// 判断是否为平板或PC（宽度）
  static bool isTabletOrDesktop(BuildContext context) {
    return getMediaQuery(context).size.width >= largeScreenWidth;
  }

  /// 获取屏幕高度
  static double screenHeight(BuildContext context) {
    return getMediaQuery(context).size.height;
  }

  /// 获取屏幕宽度
  static double screenWidth(BuildContext context) {
    return getMediaQuery(context).size.width;
  }

  /// 响应式间距 - 水平方向
  static double horizontalPadding(BuildContext context) {
    if (isTabletOrDesktop(context)) {
      return 32.0; // 平板/PC使用更大的间距
    } else if (isSmallScreenWidth(context)) {
      return 16.0; // 小屏手机使用较小的间距
    }
    return 24.0; // 默认间距
  }

  /// 响应式间距 - 垂直方向
  static double verticalPadding(BuildContext context) {
    if (isSmallScreen(context)) {
      return 12.0; // 小屏设备使用较小的垂直间距
    }
    return 16.0; // 默认间距
  }

  /// 响应式字体大小 - 标题
  static double titleFontSize(BuildContext context) {
    if (isSmallScreen(context)) {
      return 16.0;
    } else if (isLargeScreen(context)) {
      return 20.0;
    }
    return 18.0;
  }

  /// 响应式字体大小 - 副标题
  static double subtitleFontSize(BuildContext context) {
    if (isSmallScreen(context)) {
      return 11.0;
    } else if (isLargeScreen(context)) {
      return 14.0;
    }
    return 12.0;
  }

  /// 响应式字体大小 - 正文
  static double bodyFontSize(BuildContext context) {
    if (isSmallScreen(context)) {
      return 13.0;
    } else if (isLargeScreen(context)) {
      return 16.0;
    }
    return 14.0;
  }

  /// 响应式按钮内边距
  static EdgeInsets buttonPadding(BuildContext context) {
    if (isSmallScreen(context)) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    } else if (isLargeScreen(context)) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 10);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  }

  /// 响应式图标大小
  static double iconSize(BuildContext context, {double defaultSize = 24.0}) {
    if (isSmallScreen(context)) {
      return defaultSize * 0.85;
    } else if (isLargeScreen(context)) {
      return defaultSize * 1.15;
    }
    return defaultSize;
  }

  /// 响应式卡片内边距
  static EdgeInsets cardPadding(BuildContext context) {
    if (isSmallScreen(context)) {
      return const EdgeInsets.all(12);
    } else if (isLargeScreen(context)) {
      return const EdgeInsets.all(24);
    }
    return const EdgeInsets.all(16);
  }

  /// 响应式间距 - 通用
  static double spacing(BuildContext context, {
    double small = 8.0,
    double normal = 16.0,
    double large = 24.0,
  }) {
    if (isSmallScreen(context)) {
      return small;
    } else if (isLargeScreen(context)) {
      return large;
    }
    return normal;
  }

  /// 响应式容器边距
  static EdgeInsets containerMargin(BuildContext context) {
    final horizontal = horizontalPadding(context);
    final vertical = verticalPadding(context);
    return EdgeInsets.symmetric(
      horizontal: horizontal,
      vertical: vertical,
    );
  }

  /// 根据屏幕尺寸返回不同值
  static T responsiveValue<T>(
    BuildContext context, {
    required T small,
    required T normal,
    T? large,
  }) {
    if (isSmallScreen(context)) {
      return small;
    } else if (isLargeScreen(context) && large != null) {
      return large;
    }
    return normal;
  }

  /// 响应式字体样式
  static TextStyle responsiveTextStyle(
    BuildContext context, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    final size = fontSize ?? bodyFontSize(context);
    return TextStyle(
      fontSize: size,
      fontWeight: fontWeight ?? FontWeight.normal,
      color: color,
    );
  }

  /// 响应式标题样式
  static TextStyle responsiveTitleStyle(
    BuildContext context, {
    FontWeight? fontWeight,
    Color? color,
  }) {
    return TextStyle(
      fontSize: titleFontSize(context),
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color,
    );
  }

  /// 响应式副标题样式
  static TextStyle responsiveSubtitleStyle(
    BuildContext context, {
    FontWeight? fontWeight,
    Color? color,
  }) {
    return TextStyle(
      fontSize: subtitleFontSize(context),
      fontWeight: fontWeight ?? FontWeight.normal,
      color: color,
    );
  }
}


