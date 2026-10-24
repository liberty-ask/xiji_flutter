import 'package:shared_preferences/shared_preferences.dart';

import 'local_user.dart';

/// 云备份开关存取（tasks.md 6.3，design.md D7 二期「备份开关」）。
///
/// 键按当前登录用户账号化：A 开的备份不得串到 B（开关、密钥、游标
/// 同为账号/家庭隔离体系）。6.x 阶段开关打开即代表「已设置加密口令，
/// 同意端到端加密备份」，7.x 同步任务以本开关作为上传/下拉的门控。
class BackupFlagStore {
  /// 老版本全局键（无账号隔离）：账号化升级的认领迁移源。
  /// 与 KeyVault 老键同规则：归「升级后首个登录读到它的用户」。
  static const _legacyKey = 'backup_enabled';

  static Future<String> _key() async =>
      'backup_enabled@${(await LocalUser.load())?.id ?? 'anonymous'}';

  /// 当前开关状态（默认关闭）
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _key();
    var value = prefs.getBool(key);
    if (value == null) {
      // 老全局键认领迁移：开关跟随 vault 同规则归当前用户
      final legacy = prefs.getBool(_legacyKey);
      if (legacy != null) {
        await prefs.setBool(key, legacy);
        await prefs.remove(_legacyKey);
        value = legacy;
      }
    }
    return value ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _key(), value);
  }
}
