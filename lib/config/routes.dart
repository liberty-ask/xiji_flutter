import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/welcome_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/add_transaction_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/transaction/detail_screen.dart';
import '../screens/statistics/statistics_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/family/members_screen.dart';
import '../screens/budget/budget_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/change_password_screen.dart';
import '../screens/family/audit_screen.dart';
import '../screens/family/invite_screen.dart';
import '../screens/family/exit_family_screen.dart';
import '../screens/family/scanner_screen.dart';
import '../screens/family/apply_family_screen.dart';
import '../screens/settings/theme_screen.dart';
import '../screens/settings/language_screen.dart';
import '../screens/settings/font_size_screen.dart';
import '../screens/voice/voice_transaction_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/import/import_bills_screen.dart';
import '../screens/category/category_manage_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/home_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/category_provider.dart';
import '../models/user.dart';

// 临时占位页面
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              '$title 页面\n正在开发中...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class AppRouter {
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: authProvider,
      redirect: (context, state) {
        final currentPath = state.uri.path;
        
        // 启动页面不需要重定向
        if (currentPath == '/splash') {
          return null;
        }
        
        // 需要认证的路由列表
        final protectedRoutes = [
          '/home',
          '/add-transaction',
          '/detail',
          '/statistics',
          '/calendar',
          '/profile',
          '/members',
          '/audit',
          '/budget',
          '/theme',
          '/language',
          '/font-size',
          '/edit-profile',
          '/change-password',
          '/invite',
          '/exit-family',
          '/import-bills',
          '/category-manage',
          '/scanner',
          '/apply-family',
          '/voice-transaction',
        ];

        // 检查是否是受保护的路由
        if (protectedRoutes.contains(currentPath)) {
          // 如果正在初始化，暂时不重定向（等待初始化完成）
          if (!authProvider.isInitialized) {
            return null;
          }
          // 如果初始化完成但未认证，重定向到登录页
          if (!authProvider.isAuthenticated) {
            return '/login?redirect=$currentPath';
          }

          // 检查管理员权限
          final requireAdminRoutes = ['/audit'];
          if (requireAdminRoutes.contains(currentPath)) {
            final user = authProvider.user;
            if (user?.role == null || !UserRole.isAdmin(user!.role)) {
              return '/home'; // 没有权限，重定向到首页
            }
          }
        }

        // 如果已登录，访问登录/注册页时重定向到首页
        if ((currentPath == '/login' || currentPath == '/register' || currentPath == '/welcome') &&
            authProvider.isAuthenticated) {
          return '/home';
        }

        return null; // 不需要重定向
      },
      routes: [
        // 启动页面
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        // 公开路由
        GoRoute(
          path: '/welcome',
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        
        // 需要认证的路由
        GoRoute(
          path: '/home',
          builder: (context, state) => ChangeNotifierProvider(
            create: (_) => HomeProvider(),
            child: const HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/add-transaction',
          builder: (context, state) => MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => TransactionProvider()),
              ChangeNotifierProvider(create: (_) => CategoryProvider()),
            ],
            child: const AddTransactionScreen(),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/statistics',
          builder: (context, state) => const StatisticsScreen(),
        ),
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => ChangeNotifierProvider(
            create: (_) => CategoryProvider(),
            child: const DetailScreen(),
          ),
        ),
        GoRoute(
          path: '/edit-profile',
          builder: (context, state) => const EditProfileScreen(),
        ),
        GoRoute(
          path: '/change-password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
        GoRoute(
          path: '/budget',
          builder: (context, state) => const BudgetScreen(),
        ),
        GoRoute(
          path: '/theme',
          builder: (context, state) => const ThemeScreen(),
        ),
        GoRoute(
          path: '/language',
          builder: (context, state) => const LanguageScreen(),
        ),
        GoRoute(
          path: '/font-size',
          builder: (context, state) => const FontSizeScreen(),
        ),
        GoRoute(
          path: '/members',
          builder: (context, state) => const MembersScreen(),
        ),
        GoRoute(
          path: '/audit',
          builder: (context, state) => const AuditScreen(),
        ),
        GoRoute(
          path: '/invite',
          builder: (context, state) => const InviteScreen(),
        ),
        GoRoute(
          path: '/exit-family',
          builder: (context, state) => const ExitFamilyScreen(),
        ),
        GoRoute(
          path: '/import-bills',
          builder: (context, state) => const ImportBillsScreen(),
        ),
        GoRoute(
          path: '/category-manage',
          builder: (context, state) => ChangeNotifierProvider(
            create: (_) => CategoryProvider(),
            child: const CategoryManageScreen(),
          ),
        ),
        GoRoute(
          path: '/scanner',
          builder: (context, state) => const ScannerScreen(),
        ),
        GoRoute(
          path: '/apply-family',
          builder: (context, state) {
            final familyId = state.uri.queryParameters['familyId'];
            return ApplyFamilyScreen(familyId: familyId);
          },
        ),
        GoRoute(
          path: '/voice-transaction',
          builder: (context, state) => const VoiceTransactionScreen(),
        ),
        
        // 默认重定向
        GoRoute(
          path: '/',
          redirect: (context, state) => '/splash',
        ),
      ],
    );
  }
}
