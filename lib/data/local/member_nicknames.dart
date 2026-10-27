import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_user.dart';

/// 家庭成员昵称缓存（userId -> nickname）。
///
/// 用途：本地优先模式下首页近期动态需按交易归属 userId 显示
/// 成员昵称，离线时不得依赖网络可达。
/// 写入点：拉取家庭成员列表成功时整表覆盖（FamilyService.getMembers）；
/// 当前用户本人随 LocalUser 资料写入，保证本人昵称总是最新。
/// 键名带 @userId 后缀账号隔离（同一手机多账号不串扰）。
class MemberNicknames {
  static const _keyPrefix = 'member_nicknames@';

  static Future<String> _key() async {
    final user = await LocalUser.load();
    return '$_keyPrefix${user?.id ?? ''}';
  }

  /// 覆盖式写入全量映射（拉成员列表成功时调用）
  static Future<void> cacheAll(Map<String, String> nicknames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _key(), jsonEncode(nicknames));
  }

  /// 补充/更新单个成员昵称（当前用户本人资料刷新时调用）
  static Future<void> cacheOne(String userId, String nickname) async {
    if (userId.isEmpty || nickname.isEmpty) return;
    final map = await loadAll();
    map[userId] = nickname;
    await cacheAll(map);
  }

  /// 读取全量映射（无缓存返回空 Map）
  static Future<Map<String, String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key());
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// 登出时清除（由调用方携带当前 userId 执行）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _key());
  }
}
