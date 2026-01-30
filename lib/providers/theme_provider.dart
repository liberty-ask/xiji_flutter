import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theme_config.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeIdKey = 'app_theme';
  
  ThemeConfig _currentTheme = ThemeConfig.defaultTheme;
  ThemeConfig? _previewTheme;
  
  ThemeConfig get currentTheme => _currentTheme;
  ThemeConfig? get previewTheme => _previewTheme;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeId = prefs.getString(_themeIdKey) ?? ThemeConfig.defaultTheme.id;
    
    final theme = ThemeConfig.getThemeById(themeId) ?? ThemeConfig.defaultTheme;
    _currentTheme = theme;
    
    notifyListeners();
  }

  Future<void> setTheme(String themeId) async {
    final theme = ThemeConfig.getThemeById(themeId);
    if (theme != null) {
      _currentTheme = theme;
      _previewTheme = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeIdKey, themeId);
      notifyListeners();
    }
  }

  void setPreviewTheme(String? themeId) {
    if (themeId == null) {
      _previewTheme = null;
    } else {
      _previewTheme = ThemeConfig.getThemeById(themeId);
    }
    notifyListeners();
  }

  void applyPreviewTheme(String themeId) {
    setPreviewTheme(themeId);
  }

  void clearPreview() {
    _previewTheme = null;
    notifyListeners();
  }

  // 获取当前应该使用的主题（如果有预览主题则使用预览主题，否则使用当前主题）
  ThemeConfig get activeTheme => _previewTheme ?? _currentTheme;
  
  // 获取ThemeData
  ThemeData get themeData {
    return activeTheme.toThemeData();
  }
}

