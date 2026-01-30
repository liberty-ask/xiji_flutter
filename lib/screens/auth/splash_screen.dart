import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  void _checkAuthAndNavigate() {
    final authProvider = context.read<AuthProvider>();
    
    // 如果已经初始化，直接跳转
    if (authProvider.isInitialized) {
      _navigateBasedOnAuth(authProvider);
      return;
    }
    
    // 监听初始化状态变化
    authProvider.addListener(_onAuthChanged);
    
    // 设置超时保护（最多等待5秒）
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_hasNavigated) {
        _navigateBasedOnAuth(authProvider);
      }
    });
  }

  void _onAuthChanged() {
    if (_hasNavigated) return;
    
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isInitialized) {
      authProvider.removeListener(_onAuthChanged);
      if (mounted) {
        _navigateBasedOnAuth(authProvider);
      }
    }
  }

  void _navigateBasedOnAuth(AuthProvider authProvider) {
    if (_hasNavigated) return;
    _hasNavigated = true;
    
    if (authProvider.isAuthenticated) {
      // 已登录，跳转到首页
      context.go('/home');
    } else {
      // 未登录，跳转到欢迎页
      context.go('/welcome');
    }
  }

  @override
  void dispose() {
    // 移除监听器，防止内存泄漏
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } catch (e) {
      // 如果context已经不可用，忽略错误
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ThemeHelper.background(context),
              ThemeHelper.background(context).withValues(alpha: 0.9),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 应用Logo或图标
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 64,
                  color: ThemeHelper.primary(context),
                ),
              ),
              const SizedBox(height: 24),
              // 应用名称
              ScaledText(
                AppLocalizations.of(context)!.appTitle,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 48),
              // 加载指示器
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ThemeHelper.primary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

