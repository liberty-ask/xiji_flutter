import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';
import 'providers/font_size_provider.dart';
import 'widgets/common/font_size_inherited.dart';
import 'utils/global_error_handler.dart';
import 'services/widget/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';

void main() {
  // 初始化全局异常处理
  GlobalErrorHandler.initialize();
  
  // 使用 runZonedGuarded 捕获所有未处理的异步错误
  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stack) {
      // 捕获所有未处理的异步错误
      GlobalErrorHandler.handleUncaughtError(error, stack);
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final ThemeProvider _themeProvider;
  late final LanguageProvider _languageProvider;
  late final FontSizeProvider _fontSizeProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _themeProvider = ThemeProvider();
    _languageProvider = LanguageProvider();
    _fontSizeProvider = FontSizeProvider();
    _router = AppRouter.createRouter(_authProvider);
    
    // 初始化认证状态（从存储中恢复）
    _authProvider.initialize();
    
    // 设置 Widget 服务的路由
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomeWidgetService.setRouter(_router);
      HomeWidgetService.initialize();
      
      // 检查是否有从 Widget 启动的路由
      _checkWidgetRoute();
    });
  }
  
  /// 检查是否有从 Widget 启动的路由
  Future<void> _checkWidgetRoute() async {
    try {
      const platform = MethodChannel('com.xiji/widget');
      final route = await platform.invokeMethod<String>('getInitialRoute');
      if (route != null && route.isNotEmpty) {
        // 延迟一下，确保路由已初始化
        Future.delayed(const Duration(milliseconds: 500), () {
          _router.go(route);
        });
      }
    } catch (e) {
      // 忽略错误，可能不是从 Widget 启动
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
        ChangeNotifierProvider.value(value: _languageProvider),
        ChangeNotifierProvider.value(value: _fontSizeProvider),
      ],
      child: Consumer3<ThemeProvider, LanguageProvider, FontSizeProvider>(
        builder: (context, themeProvider, languageProvider, fontSizeProvider, _) {
          // 确保字号缩放因子始终为正数
          final scale = fontSizeProvider.fontSizeScale > 0 ? fontSizeProvider.fontSizeScale : 1.0;
          
          return FontSizeInherited(
            fontSizeScale: scale,
            child: MaterialApp.router(
              title: '玺记',
              debugShowCheckedModeBanner: false,
              theme: themeProvider.themeData,
              routerConfig: _router,
              locale: languageProvider.currentLocale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          );
        },
      ),
    );
  }
}

