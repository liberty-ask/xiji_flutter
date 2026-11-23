import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/local_family_cache.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/pending_family_switch_store.dart';
import 'package:xiji_flutter/models/family.dart';
import 'package:xiji_flutter/models/user.dart';

/// 离线优先的家庭切换：本地立即生效，服务端切换失败只记待补发。
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

  group('LocalFamilyCache.setCurrent：离线切换本地即刻生效', () {
    test('只改写 isCurrent，其余字段原样保留', () async {
      await LocalFamilyCache.cache([
        Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1, avatar: 'a'),
        Family(id: 'f2', name: '家庭二', isCurrent: false, role: 0),
      ]);

      await LocalFamilyCache.setCurrent('f2');

      final families = (await LocalFamilyCache.load())!;
      expect(families.map((f) => f.id), ['f1', 'f2']);
      expect(families.firstWhere((f) => f.id == 'f2').isCurrent, true);
      final f1 = families.firstWhere((f) => f.id == 'f1');
      expect(f1.isCurrent, false);
      expect(f1.name, '家庭一');
      expect(f1.role, 1);
      expect(f1.avatar, 'a');
    });

    test('无缓存时静默跳过，不抛错', () async {
      await LocalFamilyCache.setCurrent('f2');
      expect(await LocalFamilyCache.load(), isNull);
    });
  });

  group('PendingFamilySwitchStore：服务端切换待补发', () {
    test('保存/读取/清除', () async {
      expect(await PendingFamilySwitchStore.load(), isNull);

      await PendingFamilySwitchStore.save('f2');
      expect(await PendingFamilySwitchStore.load(), 'f2');

      await PendingFamilySwitchStore.clear();
      expect(await PendingFamilySwitchStore.load(), isNull);
    });

    test('按账号隔离，切换账号不串用待补发', () async {
      await PendingFamilySwitchStore.save('f2'); // u1

      // 切到 u2：读不到 u1 的待补发
      SharedPreferences.setMockInitialValues({
        LocalUser.profileKey: jsonEncode(User(
          id: 'u2',
          nickname: 'B',
          phone: '2',
        ).toJson()),
        'pending_family_switch@u1': 'f2',
      });
      expect(await PendingFamilySwitchStore.load(), isNull);
      await PendingFamilySwitchStore.save('f3');

      // 切回 u1：仍保留自己的待补发
      SharedPreferences.setMockInitialValues({
        LocalUser.profileKey: jsonEncode(User(
          id: 'u1',
          nickname: 'A',
          phone: '1',
        ).toJson()),
        'pending_family_switch@u1': 'f2',
        'pending_family_switch@u2': 'f3',
      });
      expect(await PendingFamilySwitchStore.load(), 'f2');
    });
  });
}
