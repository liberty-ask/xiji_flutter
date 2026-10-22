import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/backup_flag_store.dart';
import '../../l10n/app_localizations.dart';

/// 首次记账后的云备份引导（tasks.md 6.4，见 design.md Risks：
/// 纯本地模式卸载即丢数据 → 不做隐藏，首次记账后引导开启备份）。
///
/// 仅当「备份未开启 && 从未展示过」时弹一次；记账入口（手动表单、
/// 语音直接入库）都挂本引导，幂等由 SharedPreferences 标记保证。
class BackupGuidance {
  static const _shownKey = 'backup_guidance_shown';

  /// 记账保存成功后调用：满足条件则弹出一次性备份引导对话框。
  static Future<void> maybeShowAfterFirstSave(BuildContext context) async {
    if (await BackupFlagStore.isEnabled()) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_shownKey) ?? false) return;
    await prefs.setBool(_shownKey, true); // 展示一次即标记，不再自动打扰
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backupGuidanceTitle),
        content: Text(l10n.backupGuidanceMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.backupGuidanceLater),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.backupGuidanceGo),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) context.push('/backup');
  }
}
