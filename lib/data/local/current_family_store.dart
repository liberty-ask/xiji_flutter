import 'package:shared_preferences/shared_preferences.dart';

import 'local_family_cache.dart';

/// 当前家庭存取：本地库家庭维度的统一路由源（见 design.md D11）。
///
/// 写入时机：登录成功 / 家庭列表加载解析出当前家庭 / 切换家庭；
/// 清除时机：登出。门面层读取后传给 repository，页面零改动。
///
/// 读取兜底链：prefs 存值 -> 家庭缓存首个 -> 空串（未登录/未拉取过家庭，
/// 一期登录后必经首页解析，空串仅存在于极端启动时序）。
class CurrentFamilyStore {
  static const _key = 'current_family_id';

  /// 写入当前家庭 ID
  static Future<void> set(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, familyId);
  }

  /// 读取当前家庭 ID（含兜底链）
  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null && stored.isNotEmpty) return stored;
    final families = await LocalFamilyCache.load();
    if (families != null && families.isNotEmpty) return families.first.id;
    return '';
  }

  /// 清除（登出时调用）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
