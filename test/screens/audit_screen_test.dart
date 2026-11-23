import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/models/application.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/providers/auth_provider.dart';
import 'package:xiji_flutter/screens/family/audit_screen.dart';
import 'package:xiji_flutter/services/api/api_client.dart';
import 'package:xiji_flutter/widgets/common/font_size_inherited.dart';

/// 待审批页：网络失败不展示原始异常；已有列表刷新失败时保留内容；
/// 非管理员即使被直接路由进入也不请求、不渲染审核内容。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  AuthProvider authWithRole(int role) {
    final auth = AuthProvider();
    auth.debugSetUser(User(
      id: 'u1',
      nickname: '测试用户',
      phone: '13800000000',
      role: role,
    ));
    return auth;
  }

  Future<void> pumpAudit(
    WidgetTester tester,
    Future<List<Application>> Function() loader, {
    bool isAdmin = true,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authWithRole(isAdmin ? UserRole.admin : UserRole.member),
        child: FontSizeInherited(
          fontSizeScale: 1.0,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: AuditScreen(applicationLoader: loader),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('网络失败且无数据：显示可读文案与重试，不暴露原始异常', (tester) async {
    await pumpAudit(
        tester, () async => throw const ApiException('Connection error'));

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.auditLoadNetworkError), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Connection error'), findsNothing);
  });

  testWidgets('已有列表时刷新失败：保留内容，不清空成错误页', (tester) async {
    var shouldFail = false;
    await pumpAudit(tester, () async {
      if (shouldFail) throw const ApiException('Connection error');
      return [Application(id: 'a1', name: '申请人甲', time: '2026-11-23')];
    });

    expect(find.text('申请人甲'), findsOneWidget);

    shouldFail = true;
    await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(find.text('申请人甲'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('非管理员直接进入：不请求数据、不渲染审核内容', (tester) async {
    var loaderCalled = false;
    await pumpAudit(
      tester,
      () async {
        loaderCalled = true;
        return [Application(id: 'a1', name: '申请人甲', time: '2026-11-23')];
      },
      isAdmin: false,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(loaderCalled, isFalse, reason: '越权进入不应发起审核数据请求');
    expect(find.text(l10n.permissionDenied), findsOneWidget);
    expect(find.text('申请人甲'), findsNothing);
    expect(find.text(l10n.approve), findsNothing);
  });
}
