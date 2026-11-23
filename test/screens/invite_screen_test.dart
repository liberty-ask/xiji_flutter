import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/current_family_store.dart';
import 'package:xiji_flutter/data/local/local_family_cache.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/models/family.dart';
import 'package:xiji_flutter/screens/family/invite_screen.dart';
import 'package:xiji_flutter/widgets/common/font_size_inherited.dart';

/// 邀请页纯本地出码：有缓存直接展示，无缓存给可读提示而非通用错误。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpInviteScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      FontSizeInherited(
        fontSizeScale: 1.0,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const InviteScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有本地家庭缓存：直接出二维码并展示家庭名（无网络依赖）',
      (tester) async {
    await LocalFamilyCache.cache([
      Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
      Family(id: 'f2', name: '家庭二', isCurrent: false, role: 0),
    ]);
    await CurrentFamilyStore.set('f1');

    await pumpInviteScreen(tester);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('家庭一'), findsWidgets);
    expect(find.text('家庭二'), findsNothing);
  });

  testWidgets('切换家庭后按本地当前家庭出码', (tester) async {
    await LocalFamilyCache.cache([
      Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
      Family(id: 'f2', name: '家庭二', isCurrent: false, role: 0),
    ]);
    await LocalFamilyCache.setCurrent('f2');
    await CurrentFamilyStore.set('f2');

    await pumpInviteScreen(tester);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('家庭二'), findsWidgets);
    expect(find.text('家庭一'), findsNothing);
  });

  testWidgets('无本地家庭缓存：展示可读提示与重试/返回，不显示通用错误',
      (tester) async {
    await pumpInviteScreen(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text(l10n.inviteNoLocalFamily), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(find.text(l10n.back), findsOneWidget);
  });
}
