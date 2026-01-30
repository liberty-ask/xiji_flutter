import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  static const String _languageKey = 'app_language';
  
  Locale? _currentLocale;
  
  Locale? get currentLocale => _currentLocale;
  
  LanguageProvider() {
    _loadLanguage();
  }
  
  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageStr = prefs.getString(_languageKey);
    if (languageStr == null) {
      // 默认跟随系统
      _currentLocale = null;
    } else {
      final parts = languageStr.split('_');
      if (parts.length == 2) {
        _currentLocale = Locale(parts[0], parts[1]);
      } else {
        _currentLocale = Locale(languageStr);
      }
    }
    notifyListeners();
  }
  
  Future<void> setLanguage(Locale? locale) async {
    _currentLocale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      // 跟随系统
      await prefs.remove(_languageKey);
    } else {
      await prefs.setString(_languageKey, '${locale.languageCode}_${locale.countryCode}');
    }
    notifyListeners();
  }
  
  // 获取支持的语言列表
  List<LanguageOption> get supportedLanguages {
    return [
      LanguageOption(null, '跟随系统', Icons.settings_system_daydream),
      LanguageOption(const Locale('zh', 'CN'), '简体中文', Icons.language),
      LanguageOption(const Locale('zh', 'TW'), '繁体中文', Icons.language),
      LanguageOption(const Locale('en', 'US'), 'English', Icons.language),
    ];
  }
}

class LanguageOption {
  final Locale? locale;
  final String name;
  final IconData icon;
  
  LanguageOption(this.locale, this.name, this.icon);
}
