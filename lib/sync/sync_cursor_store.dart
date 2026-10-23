import 'package:shared_preferences/shared_preferences.dart';

/// 同步拉取游标存取（tasks.md 7.4）：按家庭持久化 (updated_at, id)
/// 二元组游标，标记「云端已拉取到该位置」。
///
/// - 崩溃/中断安全：每页入库全部成功后才推进游标，中途失败下次
///   从旧游标重拉，LWW 幂等保证重拉无害
/// - 新设备全量恢复：无游标（缺省）即从头全量拉取
/// - 切家庭后各自家庭游标独立推进
class SyncCursorStore {
  static const _timePrefix = 'sync_cursor_time_';
  static const _idPrefix = 'sync_cursor_id_';

  /// 读取家庭游标；无游标返回 null（新设备全量恢复）
  static Future<({int time, String id})?> load(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    final time = prefs.getInt('$_timePrefix$familyId');
    final id = prefs.getString('$_idPrefix$familyId');
    if (time == null || id == null) return null;
    return (time: time, id: id);
  }

  /// 保存家庭游标（页入库成功后调用）
  static Future<void> save(
      String familyId, int time, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_timePrefix$familyId', time);
    await prefs.setString('$_idPrefix$familyId', id);
  }
}
