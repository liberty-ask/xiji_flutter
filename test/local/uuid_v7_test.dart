import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/uuid_v7.dart';

void main() {
  group('任务 1.2：UUIDv7 客户端生成器', () {
    final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

    test('格式：36 位标准 UUIDv7，版本位 7，变体位 10，小写十六进制', () {
      for (var i = 0; i < 100; i++) {
        final id = UuidV7.generate();
        expect(id, matches(uuidPattern), reason: '生成的 $id 不符合 UUIDv7 格式');
        expect(id.length, 36);
      }
    });

    test('时间戳正确嵌入 48 位毫秒段', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final id = UuidV7.generate();
      final after = DateTime.now().millisecondsSinceEpoch;

      final ts = UuidV7.extractTimestamp(id);
      expect(ts, greaterThanOrEqualTo(before));
      expect(ts, lessThanOrEqualTo(after));
    });

    test('唯一性：连续生成 10000 个无重复', () {
      final ids = List.generate(10000, (_) => UuidV7.generate());
      expect(ids.toSet().length, 10000);
    });

    test('74 位随机段：同毫秒生成的多个 UUID 随机段互异', () {
      final ids = List.generate(1000, (_) => UuidV7.generate());

      // 按 48 位时间戳分组，校验同毫秒组内随机段（rand_a 12 位 + rand_b 62 位）互异
      final byTimestamp = <int, Set<String>>{};
      for (final id in ids) {
        final ts = UuidV7.extractTimestamp(id);
        final hex = id.replaceAll('-', '');
        final randomBits = hex.substring(13, 16) + hex.substring(17, 32);
        byTimestamp.putIfAbsent(ts, () => {}).add(randomBits);
      }

      var sameMsGroups = 0;
      for (final entry in byTimestamp.entries) {
        if (entry.value.length > 1) sameMsGroups++;
      }
      // 1000 个连续生成必有大量同毫秒组，各组内随机段必须互异
      expect(sameMsGroups, greaterThan(0),
          reason: '生成过快导致全部异毫秒，测试假设失效');
      final allRandom = ids.map((id) {
        final hex = id.replaceAll('-', '');
        return hex.substring(13, 16) + hex.substring(17, 32);
      }).toSet();
      expect(allRandom.length, 1000, reason: '随机段存在重复');
    });
  });
}
