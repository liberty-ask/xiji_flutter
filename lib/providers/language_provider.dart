import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

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
      LanguageOption(null, Icons.settings_system_daydream),
      LanguageOption(const Locale('zh', 'CN'), Icons.language),
      LanguageOption(const Locale('zh', 'TW'), Icons.language),
      LanguageOption(const Locale('en', 'US'), Icons.language),
    ];
  }
}

class LanguageOption {
  final Locale? locale;
  final IconData icon;
  
  LanguageOption(this.locale, this.icon);

  String displayName(AppLocalizations l10n) {
    if (locale == null) return l10n.followSystem;
    if (locale!.languageCode == 'en') return l10n.english;
    if (locale!.countryCode == 'TW') return l10n.traditionalChinese;
    return l10n.simplifiedChinese;
  }
}
