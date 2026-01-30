import 'package:flutter/material.dart';
import '../widgets/common/scaled_text.dart';

class TextHelper {
  /// 获取文本颜色
  static Color getTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// 获取次要文本颜色
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withAlpha(128);
  }

  /// 标题文本（大）
  static Widget titleLarge(
    BuildContext context,
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: getTextColor(context),
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 标题文本（中）
  static Widget titleMedium(
    BuildContext context,
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: getTextColor(context),
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 标题文本（小）
  static Widget titleSmall(
    BuildContext context,
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: getTextColor(context),
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 正文文本
  static Widget body(
    BuildContext context,
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
      int? maxLines,
      TextOverflow? overflow,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 14,
        color: getTextColor(context),
      ).merge(style),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// 辅助文本
  static Widget caption(
    BuildContext context,
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 12,
        color: getSecondaryTextColor(context),
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 按钮文本
  static Widget button(
    String text,
    {
      TextStyle? style,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ).merge(style),
    );
  }

  /// 错误文本
  static Widget error(
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 14,
        color: Colors.redAccent,
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 成功文本
  static Widget success(
    String text,
    {
      TextStyle? style,
      TextAlign? textAlign,
    }
  ) {
    return ScaledText(
      text,
      style: TextStyle(
        fontSize: 14,
        color: Colors.green,
      ).merge(style),
      textAlign: textAlign,
    );
  }

  /// 自定义文本
  static Widget custom(
    String text,
    {
      required TextStyle style,
      TextAlign? textAlign,
      int? maxLines,
      TextOverflow? overflow,
    }
  ) {
    return ScaledText(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
