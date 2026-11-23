import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/current_family_store.dart';
import 'package:xiji_flutter/data/local/family_member_cache.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/l10n/app_localizations.dart';
import 'package:xiji_flutter/models/family_member.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/screens/family/members_screen.dart';
import 'package:xiji_flutter/widgets/common/font_size_inherited.dart';

/// 成员页断网行为：有缓存正常渲染；无缓存显示可读提示，不暴露原始异常。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      LocalUser.profileKey: jsonEncode(User(
        id: 'u1',
        nickname: 'A',
        phone: '1',
      ).toJson()),
    });
  });

  Future<void> pumpMembers(
    WidgetTester tester, {
    Future<List<FamilyMember>> Function()? loader,
  }) async {
    await tester.pumpWidget(
      FontSizeInherited(
        fontSizeScale: 1.0,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: MembersScreen(
            memberLoader: loader ??
                () async => throw Exception('Connection error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('断网但有缓存：正常渲染成员列表，不显示错误态', (tester) async {
    await FamilyMemberCache.save('f1', [
      FamilyMember(id: 'm1', name: '张三', role: 1, syncEnabled: 1),
      FamilyMember(id: 'm2', name: '李四', role: 0, syncEnabled: 0),
    ]);
    await CurrentFamilyStore.set('f1');

    await pumpMembers(tester);

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('断网且无缓存：显示可读提示与重试，不暴露原始异常文本',
      (tester) async {
    await CurrentFamilyStore.set('f1');

    await pumpMembers(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.membersLoadFailed), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Connection error'), findsNothing);
  });
}
