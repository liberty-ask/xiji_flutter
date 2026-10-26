import 'package:shared_preferences/shared_preferences.dart';

/// 同步拉取游标存取（tasks.md 7.4 / 8.8 账号隔离）：按「家庭 + 用户」
/// 持久化 (updated_at, id) 二元组游标，标记「云端已拉取到该位置」。
///
/// - 8.8 账号隔离：键带 @userId 后缀。同一手机切换账号（本地库已按
///   userId 分库）时游标互不继承——仅 familyId 维度下，先登录者的
///   同步把家庭游标推进到末尾，后登录者增量拉取永远返回空，看不到
///   对方新记的数据（切账号死锁，真机实测）
/// - 崩溃/中断安全：每页入库全部成功后才推进游标，中途失败下次
///   从旧游标重拉，LWW 幂等保证重拉无害
/// - 新设备全量恢复：无游标（缺省）即从头全量拉取
/// - 切家庭后各自家庭游标独立推进
/// - 旧键（无 userId 后缀）不迁移：新键空值 → 下次登录全量拉一次，
///   LWW 幂等无副作用（升级自然自愈，见 8.8）
class SyncCursorStore {
  static const _timePrefix = 'sync_cursor_time_';
  static const _idPrefix = 'sync_cursor_id_';

  static String _timeKey(String familyId, String userId) =>
      '$_timePrefix$familyId@$userId';

  static String _idKey(String familyId, String userId) =>
      '$_idPrefix$familyId@$userId';

  /// 读取家庭游标；无游标返回 null（新设备全量恢复）
  static Future<({int time, String id})?> load(
      String familyId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final time = prefs.getInt(_timeKey(familyId, userId));
    final id = prefs.getString(_idKey(familyId, userId));
    if (time == null || id == null) return null;
    return (time: time, id: id);
  }

  /// 保存家庭游标（页入库成功后调用）
  static Future<void> save(
      String familyId, String userId, int time, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeKey(familyId, userId), time);
    await prefs.setString(_idKey(familyId, userId), id);
  }

  /// 清除家庭游标（首获 F 后全量重拉用）：游标已推进的历史密文
  /// 此前无 F 解不开被跳过，须回到无游标态从头拉取（LWW 幂等，
  /// 重拉无害）
  static Future<void> clear(String familyId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_timeKey(familyId, userId));
    await prefs.remove(_idKey(familyId, userId));
  }
}
