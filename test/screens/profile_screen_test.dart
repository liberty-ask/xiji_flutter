import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/providers/auth_provider.dart';
import 'package:xiji_flutter/screens/profile/profile_screen.dart';
import 'package:xiji_flutter/widgets/common/font_size_inherited.dart';

/// 「加入审核」入口可见性：只由当前家庭角色决定（非管理员不可见）
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpProfile(WidgetTester tester, {required int role}) async {
    final auth = AuthProvider();
    auth.debugSetUser(User(
      id: 'u1',
      nickname: '测试用户',
      phone: '13800000000',
      role: role,
    ));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: FontSizeInherited(
          fontSizeScale: 1.0,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: const ProfileScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('非管理员看不到「加入审核」入口', (tester) async {
    await pumpProfile(tester, role: UserRole.member);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.joinAudit), findsNothing);
  });

  testWidgets('管理员可见「加入审核」入口', (tester) async {
    await pumpProfile(tester, role: UserRole.admin);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.joinAudit), findsOneWidget);
  });
}
