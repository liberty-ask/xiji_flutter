import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 家庭成员 X25519 公钥缓存（三期 8.4，见 design.md D13）。
///
/// 公钥源真相是各成员的 vaultDoc（payload 内 publicKey 明文），
/// 经家庭通道同步自然到达；本缓存仅是分发 F 时的快速查询层，
/// 缺失的成员本轮跳过、其 vaultDoc 到达后下轮补包裹。
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

  /// 登记成员公钥（base64）。vaultDoc 拉取入库时调用。
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
