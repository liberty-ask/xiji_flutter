import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 家庭成员 X25519 公钥缓存（三期 8.4，见 design.md D13）。
///
/// 公钥主来源是「成员关系」：服务端 family_member.public_key，客户端每轮
/// 同步上报，持钥成员拉成员列表即登记（不再依赖 vaultDoc 的增量可达性
/// ——其 updated_at 固定 epoch，永远落在已推进游标之前）。
/// vaultDoc（payload 内 publicKey 明文）保留为按 recordId 精确探测的兜底。
/// 本缓存是分发 F 时的快速查询层，缺失的成员本轮跳过、下轮补包裹。
/// 公钥本身非机密（私钥才需要保护），SharedPreferences 明文即可。
class MemberPublicKeyStore {
  MemberPublicKeyStore._();

  static const String _storageKey = 'xiji_member_public_keys';

  /// 进程内缓存：disk -> memory 一次加载
  static Map<String, String>? _cache;

  static Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _cache = <String, String>{};
      return _cache!;
    }
    final decoded = jsonDecode(raw);
    _cache = decoded is Map<String, dynamic>
        ? decoded.map((k, v) => MapEntry(k, v as String))
        : <String, String>{};
    return _cache!;
  }

  /// 登记成员公钥（base64）。成员列表下发 / vaultDoc 探测入库时调用。
  static Future<void> register(String userId, String publicKeyBase64) async {
    final cache = await _load();
    if (userId.isEmpty || publicKeyBase64.isEmpty) return;
    if (cache[userId] == publicKeyBase64) return;
    cache[userId] = publicKeyBase64;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(cache));
  }

  /// 查询成员公钥（base64）。未到达（vaultDoc 未同步到）返回 null。
  static Future<String?> get(String userId) async {
    final cache = await _load();
    return cache[userId];
  }

  /// 测试注入预置缓存
  @visibleForTesting
  static Future<void> setForTesting(Map<String, String> entries) async {
    final cache = await _load();
    cache
      ..clear()
      ..addAll(entries);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(cache));
  }
}
