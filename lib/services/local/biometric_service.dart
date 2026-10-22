import 'package:local_auth/local_auth.dart';

import '../../l10n/app_localizations.dart';

/// 生物识别提示封装（6.6）：只负责「本机生物识别是否可用」与「弹出系统
/// 提示」；密钥的包裹与解包在 KeyVault（unlockedWithBiometric 由 UI 在
/// 提示通过后调用）。日常解锁走这里，口令仅开启/重置时出现。
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// 本机是否已录入指纹/面容（未录入时不可开启生物识别解锁）。
  Future<bool> isAvailable() async {
    final types = await _auth.getAvailableBiometrics();
    return types.isNotEmpty;
  }

  /// 弹出系统生物识别提示。返回 false 表示用户取消或验证失败。
  Future<bool> authenticate(AppLocalizations l10n) {
    return _auth.authenticate(
      localizedReason: l10n.biometricUnlockReason,
      options: const AuthenticationOptions(
        biometricOnly: true, // 仅指纹/面容，不回落设备锁屏密码
        stickyAuth: true, // 验证过程中 App 被切后台，回来继续而非直接失败
      ),
    );
  }
}
