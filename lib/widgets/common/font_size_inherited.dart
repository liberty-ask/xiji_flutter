import 'package:flutter/material.dart';

class FontSizeInherited extends InheritedWidget {
  final double fontSizeScale;

  const FontSizeInherited({
    Key? key,
    required this.fontSizeScale,
    required Widget child,
  }) : super(key: key, child: child);

  static FontSizeInherited of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<FontSizeInherited>();
    assert(result != null, 'No FontSizeInherited found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(FontSizeInherited oldWidget) {
    return fontSizeScale != oldWidget.fontSizeScale;
  }
}
