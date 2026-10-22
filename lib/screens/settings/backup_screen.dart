import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../crypto/key_vault.dart';
import '../../crypto/vault_store.dart';
import '../../data/local/backup_flag_store.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/scaled_text.dart';

/// 云备份设置页（tasks.md 6.3）：备份开关（默认关闭）+ 开启时口令设置流
/// （强度校验）+ 恢复码生成与仅展示一次。
///
/// 密钥层见 design.md D3：口令派生 KEK 解开私钥、私钥解数据密钥、数据密钥
/// 加密业务记录。本页只负责开关与口令/恢复码的交互流程，密钥全部落在
/// KeyVault。7.x 同步任务以 BackupFlagStore 作为上传/下拉门控。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final KeyVault _vault = KeyVault(SecureVaultStore.instance);

  bool _enabled = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await BackupFlagStore.isEnabled();
    final configured = await _vault.isConfigured();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _configured = configured;
      });
    }
  }

  void _onTabTapped(int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/calendar');
        break;
      case 2:
        context.push('/add-transaction');
        break;
      case 3:
        context.go('/statistics');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  /// 开关切换入口：开启走口令设置流（已配置过口令的直接恢复），
  /// 关闭需二次确认。
  Future<void> _onSwitchChanged(bool value) async {
    if (value) {
      if (await _vault.isConfigured()) {
        // 之前设置过口令：重开即恢复，无需再走设置流
        await BackupFlagStore.setEnabled(true);
        if (mounted) setState(() => _enabled = true);
        return;
      }
      final password = await _showPasswordDialog();
      if (password == null || !mounted) return; // 用户取消，开关回弹
      final result = await _runSetup(password);
      if (result == null || !mounted) return;
      final saved = await _showRecoveryCodeDialog(result.recoveryCode);
      if (!saved || !mounted) return;
      await BackupFlagStore.setEnabled(true);
      if (mounted) {
        setState(() {
          _enabled = true;
          _configured = true;
        });
      }
    } else {
      final confirmed = await _showDisableConfirm();
      if (confirmed != true || !mounted) return;
      await BackupFlagStore.setEnabled(false);
      if (mounted) setState(() => _enabled = false);
    }
  }

  /// 口令设置对话框：口令两次 + 强度校验（≥8 位且含字母与数字）。
  /// 返回 null 表示用户取消。
  Future<String?> _showPasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var obscure = true;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.backupSetPasswordTitle),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.backupSetPasswordDesc),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l10n.backupPasswordLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (value) => _validatePassword(l10n, value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l10n.backupPasswordConfirmLabel,
                  ),
                  validator: (value) {
                    if (value != passwordController.text) {
                      return l10n.backupPasswordMismatch;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(passwordController.text);
                }
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  /// 执行 KeyVault.setup（生产档 Argon2 需数秒，加载遮罩）。
  Future<KeyVaultSetupResult?> _runSetup(String password) async {
    final l10n = AppLocalizations.of(context)!;
    _showGeneratingDialog(l10n);
    try {
      return await _vault.setup(password);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupSetupFailed)),
        );
      }
      return null;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showGeneratingDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ScaledText(l10n.backupGeneratingKeys),
            ],
          ),
        ),
      ),
    );
  }

  /// 恢复码仅展示一次：不可点外部关闭、不可返回，用户点「我已妥善保存」
  /// 后明文即弃（KeyVault 仅存恢复码包裹份）。
  Future<bool> _showRecoveryCodeDialog(String code) async {
    final l10n = AppLocalizations.of(context)!;
    final formatted = KeyVault.formatRecoveryCode(code);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.backupRecoveryCodeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: ThemeHelper.expenseColor(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ScaledText(
                      l10n.backupRecoveryCodeOnceWarning,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: ThemeHelper.surface(context),
                  border: Border.all(
                    color: ThemeHelper.primary(context).withValues(alpha: 0.4),
                  ),
                ),
                child: SelectableText(
                  formatted,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: ThemeHelper.primary(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: formatted));
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(l10n.backupRecoveryCodeCopied)),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.backupRecoveryCodeCopy),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.backupRecoveryCodeSaved),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<bool?> _showDisableConfirm() async {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backupDisableTitle),
        content: Text(l10n.backupDisableMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  /// 恢复码重置口令流（6.5）：对话框输入恢复码 + 新口令两次，
  /// 校验通过后调 KeyVault 重置（生产档 Argon2 两次派生，加载遮罩）。
  Future<void> _resetPassword() async {
    final input = await _showResetPasswordDialog();
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    _showResettingDialog(l10n);
    try {
      await _vault.resetPasswordWithRecoveryCode(input.$1, input.$2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupResetDone)),
        );
      }
    } on KeyVaultUnlockException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupResetWrongCode)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupResetFailed)),
        );
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<(String, String)?> _showResetPasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var obscure = true;

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.backupResetPasswordTitle),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: l10n.backupResetRecoveryCodeLabel,
                  ),
                  validator: (value) {
                    if (KeyVault.normalizeRecoveryCode(value ?? '').length !=
                        24) {
                      return l10n.backupResetCodeInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l10n.backupResetNewPasswordLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (value) => _validatePassword(l10n, value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l10n.backupResetNewPasswordConfirmLabel,
                  ),
                  validator: (value) {
                    if (value != passwordController.text) {
                      return l10n.backupPasswordMismatch;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext)
                      .pop((codeController.text, passwordController.text));
                }
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );

    codeController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  void _showResettingDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ScaledText(l10n.backupResetting),
            ],
          ),
        ),
      ),
    );
  }

  /// 口令强度校验（设置与重置共用）：≥8 位且同时包含字母与数字。
  String? _validatePassword(AppLocalizations l10n, String? value) {
    if (value == null || value.length < 8) {
      return l10n.backupPasswordTooShort;
    }
    if (!RegExp(r'(?=.*[A-Za-z])(?=.*\d)').hasMatch(value)) {
      return l10n.backupPasswordWeak;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.grey[200]!;

    return Scaffold(
      appBar: AppBar(
        title: ScaledText(l10n.cloudBackup),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.horizontalPadding(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // 端到端加密说明卡
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: ThemeHelper.surface(context),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.enhanced_encryption,
                    color: ThemeHelper.primary(context),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScaledText(
                          l10n.cloudBackup,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ScaledText(
                          l10n.backupE2eDescription,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.4),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 备份开关
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: ThemeHelper.surface(context),
                border: Border.all(color: borderColor),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                  ),
                  child: Icon(
                    Icons.cloud_outlined,
                    color: ThemeHelper.primary(context),
                    size: 20,
                  ),
                ),
                title: ScaledText(
                  l10n.cloudBackup,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: ScaledText(
                  _enabled ? l10n.backupEnabled : l10n.backupDataLocalOnly,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                trailing: Switch(
                  value: _enabled,
                  onChanged: _onSwitchChanged,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 恢复码重置口令入口（已设置过口令才显示，见 6.5）
            if (_configured)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: ThemeHelper.surface(context),
                  border: Border.all(color: borderColor),
                ),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color:
                          ThemeHelper.primary(context).withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      Icons.key,
                      color: ThemeHelper.primary(context),
                      size: 20,
                    ),
                  ),
                  title: ScaledText(
                    l10n.backupResetPasswordTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: ScaledText(
                    l10n.backupResetPasswordSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  onTap: _resetPassword,
                ),
              ),
            if (_configured) const SizedBox(height: 16),
            // 当前状态提示
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: ThemeHelper.surface(context),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _enabled ? Icons.verified_user_outlined : Icons.info_outline,
                    color: _enabled
                        ? ThemeHelper.primary(context)
                        : ThemeHelper.expenseColor(context),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ScaledText(
                      _enabled
                          ? l10n.backupEncryptedInfo
                          : l10n.backupLocalOnlyWarning,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 4,
        onTap: _onTabTapped,
      ),
    );
  }
}
