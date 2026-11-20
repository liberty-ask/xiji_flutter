import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiji_flutter/data/local/backup_switch_store.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/models/user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalUser.cache(User(
      id: 'user-1',
      nickname: '测试用户',
      phone: '13800000000',
    ));
  });

  group('BackupSwitchStore 键隔离', () {
    test('不同家庭开关互不影响', () async {
      await BackupSwitchStore.setEnabled('family-a', true);
      expect(await BackupSwitchStore.isEnabled('family-a'), isTrue);
      expect(await BackupSwitchStore.isEnabled('family-b'), isFalse);
    });

    test('不同账号开关互不影响', () async {
      await BackupSwitchStore.setEnabled('family-a', true);
      // 切换账号（B 账号读到的是自己的键，默认关闭）
      await LocalUser.cache(User(
        id: 'user-2',
        nickname: '用户B',
        phone: '13900000000',
      ));
      expect(await BackupSwitchStore.isEnabled('family-a'), isFalse);
    });

    test('未登录（anonymous）读写不抛错且与已登录态隔离', () async {
      // LocalUser.load 失败回退 anonymous 后缀，不与 user-1 的键串扰
      await BackupSwitchStore.setEnabled('family-a', true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(LocalUser.profileKey);
      expect(await BackupSwitchStore.isEnabled('family-a'), isFalse);
    });
  });

  group('BackupSwitchStore 版本与 LWW', () {
    test('本地切换递增版本', () async {
      expect(await BackupSwitchStore.getVersion('family-a'), 0);
      final v1 = await BackupSwitchStore.setEnabled('family-a', true);
      expect(v1, 1);
      final v2 = await BackupSwitchStore.setEnabled('family-a', false);
      expect(v2, 2);
      expect(await BackupSwitchStore.getVersion('family-a'), 2);
    });

    test('远端高版本采纳', () async {
      await BackupSwitchStore.setEnabled('family-a', true); // v1 开
      final applied =
          await BackupSwitchStore.applyRemote('family-a', false, 3);
      expect(applied, isTrue);
      expect(await BackupSwitchStore.isEnabled('family-a'), isFalse);
      expect(await BackupSwitchStore.getVersion('family-a'), 3);
    });

    test('远端平局与低版本忽略（幂等）', () async {
      await BackupSwitchStore.setEnabled('family-a', true); // v1
      expect(await BackupSwitchStore.applyRemote('family-a', false, 1),
          isFalse);
      expect(await BackupSwitchStore.applyRemote('family-a', false, 0),
          isFalse);
      expect(await BackupSwitchStore.isEnabled('family-a'), isTrue);
      expect(await BackupSwitchStore.getVersion('family-a'), 1);
    });

    test('远端应用后本地切换基于新版本递增', () async {
      await BackupSwitchStore.applyRemote('family-a', true, 5);
      final next = await BackupSwitchStore.setEnabled('family-a', false);
      expect(next, 6);
    });
  });
}
