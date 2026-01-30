import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontSizeProvider with ChangeNotifier {
  static const String _fontSizeKey = 'app_font_size';
  
  double _fontSizeScale = 1.0;
  
  double get fontSizeScale => _fontSizeScale;
  
  FontSizeProvider() {
    _loadFontSize();
  }
  
  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSizeScale = prefs.getDouble(_fontSizeKey) ?? 1.0;
    notifyListeners();
  }
  
  Future<void> setFontSize(double scale) async {
    // 限制字号范围：0.8 到 1.4
    _fontSizeScale = scale.clamp(0.8, 1.4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, _fontSizeScale);
    notifyListeners();
  }
  
  void updateFontSize(double delta) {
    // 每次调整 0.1 的步长
    final newScale = (_fontSizeScale + delta).clamp(0.8, 1.4);
    setFontSize(newScale);
  }
  
  // 获取当前字号对应的描述（根据提供的国际化对象）
  String getFontSizeDescription(dynamic localizations) {
    if (_fontSizeScale < 0.9) {
      return localizations.fontSizeTiny;
    } else if (_fontSizeScale < 1.0) {
      return localizations.fontSizeSmall;
    } else if (_fontSizeScale < 1.1) {
      return localizations.fontSizeStandard;
    } else if (_fontSizeScale < 1.2) {
      return localizations.fontSizeLarge;
    } else if (_fontSizeScale < 1.3) {
      return localizations.fontSizeExtraLarge;
    } else {
      return localizations.fontSizeHuge;
    }
  }
  
  // 获取字号对应的描述（静态方法，用于无上下文场景）
  static String getFontSizeDescriptionByScale(double scale, dynamic localizations) {
    if (scale < 0.9) {
      return localizations.fontSizeTiny;
    } else if (scale < 1.0) {
      return localizations.fontSizeSmall;
    } else if (scale < 1.1) {
      return localizations.fontSizeStandard;
    } else if (scale < 1.2) {
      return localizations.fontSizeLarge;
    } else if (scale < 1.3) {
      return localizations.fontSizeExtraLarge;
    } else {
      return localizations.fontSizeHuge;
    }
  }
}
