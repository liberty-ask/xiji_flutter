import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/family_member_cache.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/models/family_member.dart';
import 'package:xiji_flutter/models/user.dart';

FamilyMember member(String id, String name,
        {int role = 0, int syncEnabled = 1, String? publicKey}) =>
    FamilyMember(
      id: id,
      name: name,
      role: role,
      avatar: 'avatar-$id',
      label: 'label-$id',
      syncEnabled: syncEnabled,
      publicKey: publicKey,
    );

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

  group('FamilyMemberCache：成员列表本地缓存', () {
    test('保存后完整读回（含 syncEnabled/role/avatar/label/publicKey）', () async {
      final members = [
        member('m1', '我', role: 1, syncEnabled: 1, publicKey: 'pk1'),
        member('m2', '家人', role: 0, syncEnabled: 0),
      ];
      await FamilyMemberCache.save('f1', members);

      final loaded = (await FamilyMemberCache.load('f1'))!;
      expect(loaded, hasLength(2));
      expect(loaded.first.id, 'm1');
      expect(loaded.first.name, '我');
      expect(loaded.first.role, 1);
      expect(loaded.first.avatar, 'avatar-m1');
      expect(loaded.first.label, 'label-m1');
      expect(loaded.first.syncEnabled, 1);
      expect(loaded.first.isSyncing, true);
      expect(loaded.first.publicKey, 'pk1');
      expect(loaded.last.isSyncing, false);
    });

    test('按家庭隔离：切换家庭后各自读到自己的成员', () async {
      await FamilyMemberCache.save('f1', [member('m1', '家庭一成员')]);
      await FamilyMemberCache.save('f2', [
        member('m2', '家庭二成员'),
        member('m3', '家庭二成员2'),
      ]);

      final f1 = (await FamilyMemberCache.load('f1'))!;
      final f2 = (await FamilyMemberCache.load('f2'))!;
      expect(f1.map((m) => m.id), ['m1']);
      expect(f2.map((m) => m.id), ['m2', 'm3']);
    });

    test('无缓存/空家庭 ID 返回 null', () async {
      expect(await FamilyMemberCache.load('f-unknown'), isNull);
      expect(await FamilyMemberCache.load(''), isNull);
      await FamilyMemberCache.save('', [member('m1', 'x')]);
      expect(await FamilyMemberCache.load(''), isNull);
    });

    test('按账号隔离：换账号读不到上一账号缓存', () async {
      await FamilyMemberCache.save('f1', [member('m1', 'A 家庭')]);

      SharedPreferences.setMockInitialValues({
        LocalUser.profileKey: jsonEncode(User(
          id: 'u2',
          nickname: 'B',
          phone: '2',
        ).toJson()),
        'family_members@u1@f1': jsonEncode([
          member('m1', 'A 家庭').toJson(),
        ]),
      });
      expect(await FamilyMemberCache.load('f1'), isNull);
    });
  });

  group('fetchWithFallback：网络优先、断网回退', () {
    test('网络成功：返回网络结果并落盘', () async {
      final result = await FamilyMemberCache.fetchWithFallback(
        familyId: 'f1',
        fetch: () async => [member('m1', '网络成员')],
      );
      expect(result.single.name, '网络成员');
      expect((await FamilyMemberCache.load('f1'))!.single.name, '网络成员');
    });

    test('断网但有缓存：回退返回缓存成员', () async {
      await FamilyMemberCache.save('f1', [
        member('m1', '缓存成员', syncEnabled: 1),
      ]);

      final result = await FamilyMemberCache.fetchWithFallback(
        familyId: 'f1',
        fetch: () async => throw Exception('offline'),
      );
      expect(result.single.name, '缓存成员');
      expect(result.single.isSyncing, true,
          reason: 'N 的 syncEnabled 可从缓存还原');
    });

    test('断网且无缓存：原样抛错', () async {
      expect(
        () => FamilyMemberCache.fetchWithFallback(
          familyId: 'f1',
          fetch: () async => throw Exception('offline'),
        ),
        throwsException,
      );
    });
  });

  group('登出清理', () {
    test('clearAll 清空所有账号与家庭维度的成员缓存', () async {
      await FamilyMemberCache.save('f1', [member('m1', 'A 家庭')]);

      // 换账号 u2 再写一份，模拟多账号共用一台设备
      SharedPreferences.setMockInitialValues({
        LocalUser.profileKey: jsonEncode(User(
          id: 'u2',
          nickname: 'B',
          phone: '2',
        ).toJson()),
        'family_members@u1@f1': jsonEncode([
          member('m1', 'A 家庭').toJson(),
        ]),
      });
      await FamilyMemberCache.save('f2', [member('m2', 'B 家庭')]);

      await FamilyMemberCache.clearAll();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('family_members@')),
        isEmpty,
      );
      expect(await FamilyMemberCache.load('f2'), isNull);
    });
  });
}
