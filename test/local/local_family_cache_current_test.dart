import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/local_family_cache.dart';
import 'package:xiji_flutter/models/family.dart';

/// 邀请页等只读页面解析「当前家庭」的口径：
/// 以本地当前家庭 ID 优先，服务端 isCurrent 未追平时不误切旧家庭。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  final families = [
    Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
    Family(id: 'f2', name: '家庭二', isCurrent: false, role: 0),
  ];

  group('LocalFamilyCache.resolveCurrent', () {
    test('本地当前家庭 ID 命中时优先使用它（即使 isCurrent 仍是旧家庭）', () {
      final family = LocalFamilyCache.resolveCurrent(families, 'f2');
      expect(family?.id, 'f2');
    });

    test('列表中找不到本地当前家庭时返回 null（调用方保留缓存展示）', () {
      expect(LocalFamilyCache.resolveCurrent(families, 'f3'), isNull);
    });

    test('当前家庭 ID 为空时退回 isCurrent', () {
      expect(LocalFamilyCache.resolveCurrent(families, '')?.id, 'f1');
    });

    test('空列表返回 null', () {
      expect(LocalFamilyCache.resolveCurrent([], 'f2'), isNull);
    });

    test('离线切换后缓存已指向新家庭', () async {
      await LocalFamilyCache.cache(families);
      await LocalFamilyCache.setCurrent('f2');

      final cached = (await LocalFamilyCache.load())!;
      expect(LocalFamilyCache.resolveCurrent(cached, 'f2')?.id, 'f2');
    });
  });
}
