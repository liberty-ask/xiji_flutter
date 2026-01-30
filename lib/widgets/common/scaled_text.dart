import 'package:flutter/material.dart';
import 'font_size_inherited.dart';

class ScaledText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const ScaledText(
    this.data,
    {
      Key? key,
      this.style,
      this.strutStyle,
      this.textAlign,
      this.textDirection,
      this.locale,
      this.softWrap,
      this.overflow,
      this.textScaleFactor,
      this.maxLines,
      this.semanticsLabel,
      this.textWidthBasis,
      this.textHeightBehavior,
      this.selectionColor,
    }
  ) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final fontSizeScale = FontSizeInherited.of(context).fontSizeScale;
    
    // 计算最终的文本缩放因子
    final finalTextScaleFactor = textScaleFactor != null 
        ? textScaleFactor! * fontSizeScale 
        : fontSizeScale;

    // 获取主题的文本颜色
    final themeTextColor = Theme.of(context).colorScheme.onSurface;
    
    // 处理样式，确保文本颜色在浅色主题下正确显示
    TextStyle? finalStyle = style;
    if (style != null && style!.color != null) {
      // 检查文本颜色是否是基于白色的（包括带有透明度的版本）
      final color = style!.color!;
      final isWhiteBased = color.red == 255 && color.green == 255 && color.blue == 255;
      
      if (isWhiteBased) {
        // 如果调用者指定了基于白色的文本，在浅色主题下使用主题的文本颜色
        final brightness = Theme.of(context).brightness;
        if (brightness == Brightness.light) {
          // 保持相同的透明度
          final alpha = color.alpha;
          final adjustedColor = themeTextColor.withAlpha(alpha);
          finalStyle = style!.copyWith(color: adjustedColor);
        }
      }
    } else if (style == null) {
      // 如果调用者没有指定样式，使用主题的文本颜色
      finalStyle = TextStyle(color: themeTextColor);
    }
    
    // 确保Icon和其他Widget的颜色也能正确显示
    // 注意：这部分需要在具体使用Icon的地方处理

    return Text(
      data,
      style: finalStyle,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: finalTextScaleFactor,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
