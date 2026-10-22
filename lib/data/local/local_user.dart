import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';

/// 本地用户资料缓存：登录后随资料拉取写入，登出清除。
///
/// 用途：本地优先模式下（离线）交易写入需要记录归属用户 ID，
/// 首页近期动态需要展示用户昵称，分类管理需要角色判断——
/// 这些均不得依赖网络可达。资料真身仍在服务端（鉴权缓存语义），
/// 二期同步启用后由账号体系接管。
class LocalUser {
  /// 缓存键（测试 mock SharedPreferences 时引用）
  static const profileKey = 'local_user_profile';

  /// 缓存用户资料（登录/资料刷新成功时调用）
  static Future<void> cache(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileKey, jsonEncode(user.toJson()));
  }

  /// 读取缓存的用户资料（可能为 null：从未登录成功过）
  static Future<User?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 清除缓存（登出时调用）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(profileKey);
  }
}
