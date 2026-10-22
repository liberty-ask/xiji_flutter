import 'package:shared_preferences/shared_preferences.dart';

/// 云备份开关存取（tasks.md 6.3，design.md D7 二期「备份开关」）。
///
/// 开关状态与密钥保险库同为设备级（7.0 账号分库时一并账号化）；
/// 6.x 阶段开关打开即代表「已设置加密口令，同意端到端加密备份」，
/// 7.x 同步任务以本开关作为上传/下拉的门控。
class BackupFlagStore {
  static const _key = 'backup_enabled';

  /// 当前开关状态（默认关闭）
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
