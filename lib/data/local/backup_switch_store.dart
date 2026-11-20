import 'package:shared_preferences/shared_preferences.dart';

import 'local_user.dart';

/// 家庭维度云备份开关存取（family-scoped-backup-switch）。
///
/// 真值源：SharedPreferences 按「家庭 × 账号」双维度隔离存储——
/// A 账号在家庭 X 开启备份不影响家庭 Y，也不影响 B 账号。
/// 开关版本号（version）随每次切换递增，作为 bksw 云端记录的
/// LWW 仲裁依据：多设备拉取对写时 version 高者胜。
///
/// 旧 BackupFlagStore（账号级 backup_enabled@userId）退役为
/// 一次性迁移源，不再承担真值职责。
class BackupSwitchStore {
  /// 开关键：backup_enabled@<familyId>@<userId>
  static Future<String> _switchKey(String familyId) async =>
      'backup_enabled@$familyId@${await _userId()}';

  /// 版本键：backup_switch_version@<familyId>@<userId>
  static Future<String> _versionKey(String familyId) async =>
      'backup_switch_version@$familyId@${await _userId()}';

  /// 脏标记键前缀：本地切换后待推送上云的家庭开关。推送成功清除，
  /// 失败保留由下轮同步补位（关闭动作必须上云的可靠性保证）
  static const _dirtyPrefix = 'backup_switch_dirty@';

  static Future<String> _dirtyKey(String familyId) async =>
      '$_dirtyPrefix$familyId@${await _userId()}';

  static Future<String> _userId() async =>
      (await LocalUser.load())?.id ?? 'anonymous';

  /// 当前家庭的开关状态（默认关闭）
  static Future<bool> isEnabled(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _switchKey(familyId)) ?? false;
  }

  /// 当前开关版本（从未切换过为 0）
  static Future<int> getVersion(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(await _versionKey(familyId)) ?? 0;
  }

  /// 本地切换开关：version 递增（供 bksw 推送携带，LWW 覆盖），
  /// 并置脏标记（待推送上云）。返回递增后的版本号。
  static Future<int> setEnabled(String familyId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final next = await getVersion(familyId) + 1;
    await prefs.setBool(await _switchKey(familyId), value);
    await prefs.setInt(await _versionKey(familyId), next);
    await prefs.setBool(await _dirtyKey(familyId), true);
    return next;
  }

  /// 当前账号下有待推送开关的家庭列表（脏标记扫描）
  static Future<List<String>> dirtyFamilyIds() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await _userId();
    final suffix = '@$userId';
    return prefs
        .getKeys()
        .where((k) => k.startsWith(_dirtyPrefix) && k.endsWith(suffix))
        .map((k) =>
            k.substring(_dirtyPrefix.length, k.length - suffix.length))
        .toList(growable: false);
  }

  /// 推送成功后清除脏标记
  static Future<void> clearDirty(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _dirtyKey(familyId));
  }

  /// 应用远端 bksw 记录（多设备漫游）：version 高者胜，平局或更低
  /// 忽略（幂等）。返回是否采纳。
  static Future<bool> applyRemote(
      String familyId, bool value, int version) async {
    final local = await getVersion(familyId);
    if (version <= local) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _switchKey(familyId), value);
    await prefs.setInt(await _versionKey(familyId), version);
    return true;
  }
}
