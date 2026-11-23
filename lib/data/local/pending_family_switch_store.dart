import 'package:shared_preferences/shared_preferences.dart';

import 'local_user.dart';

/// 待补发的「切换当前家庭」请求。
///
/// 离线切换时本地已立即生效，服务端调用失败后把目标家庭记录在此，
/// 下次联网（启动/手动刷新/下一轮同步）时补发；成功即清除。
/// 键按账号隔离，避免多账号共用同一待补发状态。
class PendingFamilySwitchStore {
  static const _keyPrefix = 'pending_family_switch@';

  static Future<String> _key() async {
    final user = await LocalUser.load();
    return '$_keyPrefix${user?.id ?? ''}';
  }

  static Future<void> save(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _key(), familyId);
  }

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(await _key());
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _key());
  }
}
