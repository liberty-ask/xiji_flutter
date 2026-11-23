import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

class LanguageProvider with ChangeNotifier {
  static const String _languageKey = 'app_language';

  Locale? _currentLocale;

  /// 与App显示语言同源的HTTP Accept-Language标签（简中zh-CN/繁中zh-TW/英文en）。
  /// 由_loadLanguage与setLanguage同步更新，供ApiClient请求拦截器读取，
  /// 后端按该语言返回用户可见文案。偏好未加载完成时为null（跟随系统）。
  static String? resolvedLanguageTag;

  Locale? get currentLocale => _currentLocale;

  /// 把Locale归一化为后端支持的语言标签：zh_TW→zh-TW，zh/zh_CN→zh-CN，en*→en
  static String? _languageTagFor(Locale? locale) {
    if (locale == null) return null;
    if (locale.languageCode == 'zh') {
      return locale.countryCode == 'TW' ? 'zh-TW' : 'zh-CN';
    }
    return locale.languageCode;
  }

  /// 更新请求头同源标签：跟随系统时取平台locale（与MaterialApp的解析一致）
  static void _syncResolvedLanguageTag(Locale? locale) {
    resolvedLanguageTag = _languageTagFor(locale ?? PlatformDispatcher.instance.locale);
  }

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
    _syncResolvedLanguageTag(_currentLocale);
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
    _syncResolvedLanguageTag(_currentLocale);
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
