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

  /// 从家庭列表中解析当前家庭：优先按本地当前家庭 ID 命中，
  /// 找不到时返回 null（调用方保留既有展示，避免服务端 isCurrent
  /// 尚未追平时误显示旧家庭）；[currentId] 为空时退回 isCurrent/首个。
  static Family? resolveCurrent(List<Family> families, String currentId) {
    if (families.isEmpty) return null;
    if (currentId.isNotEmpty) {
      for (final f in families) {
        if (f.id == currentId) return f;
      }
      return null;
    }
    return families.firstWhere((f) => f.isCurrent, orElse: () => families.first);
  }

  /// 本地切换当前家庭：只改写 isCurrent 标记并回写缓存，
  /// 不依赖服务端（离线切换立即生效，重启后仍停留在新家庭）。
  static Future<void> setCurrent(String familyId) async {
    final families = await load();
    if (families == null || families.isEmpty) return;
    await cache([
      for (final f in families)
        Family(
          id: f.id,
          name: f.name,
          isCurrent: f.id == familyId,
          role: f.role,
          avatar: f.avatar,
        ),
    ]);
  }

  /// 清除缓存（登出时调用）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }
}
