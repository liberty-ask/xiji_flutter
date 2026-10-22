import 'dart:math';
import 'dart:typed_data';

/// RFC 9562 UUIDv7 生成器：48 位毫秒时间戳 + 4 位版本 + 74 位随机段。
///
/// 所有业务记录 ID 由客户端生成此格式，云端原样存储永不重新分配。
/// 注意：ID 中的时间戳仅为索引友好的赠品——业务时间取记录 date 字段，
/// 同步仲裁取 version 字段，任何业务逻辑不得依据 ID 排序或比较时间。
class UuidV7 {
  UuidV7._();

  static final Random _random = Random.secure();

  /// 生成 36 位标准 UUIDv7 字符串（8-4-4-4-4，小写十六进制）
  static String generate() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final bytes = Uint8List(16);

    // 字节 0-5：48 位 unix 毫秒时间戳
    bytes[0] = (ts >> 40) & 0xFF;
    bytes[1] = (ts >> 32) & 0xFF;
    bytes[2] = (ts >> 24) & 0xFF;
    bytes[3] = (ts >> 16) & 0xFF;
    bytes[4] = (ts >> 8) & 0xFF;
    bytes[5] = ts & 0xFF;

    // 字节 6：ver=0b0111 高 4 位 + rand_a 高 4 位
    bytes[6] = 0x70 | _random.nextInt(0x10);
    // 字节 7：rand_a 低 8 位
    bytes[7] = _random.nextInt(0x100);
    // 字节 8：var=0b10 高 2 位 + rand_b 高 6 位
    bytes[8] = 0x80 | _random.nextInt(0x40);
    // 字节 9-15：rand_b 其余 56 位
    for (var i = 9; i < 16; i++) {
      bytes[i] = _random.nextInt(0x100);
    }

    return _format(bytes);
  }

  static String _format(Uint8List b) {
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// 解析 UUIDv7 中嵌入的 48 位毫秒时间戳（仅用于测试与诊断，禁止业务使用）
  static int extractTimestamp(String uuid) {
    final hex = uuid.replaceAll('-', '').substring(0, 12);
    return int.parse(hex, radix: 16);
  }
}
