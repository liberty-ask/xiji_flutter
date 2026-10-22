import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/family.dart';

/// 家庭列表本地缓存：网络拉取成功后写入，无网络时兜底显示。
///
/// 首页左上角家庭名/头像不依赖网络可达（离线优先语义），
/// 缓存随登录态写入，登出清除；真身数据仍以服务端为准。
class LocalFamilyCache {
  static const cacheKey = 'local_family_list';

  /// 缓存家庭列表（网络拉取成功时调用）
  static Future<void> cache(List<Family> families) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode(families.map((f) => f.toJson()).toList()),
    );
  }

  /// 读取缓存的家庭列表（可能为 null：从未成功拉取过）
  static Future<List<Family>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Family.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 清除缓存（登出时调用）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }
}
