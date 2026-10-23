import 'package:flutter/foundation.dart';

import 'key_vault.dart';
import 'vault_store.dart';

/// KeyVault 应用级单例。
///
/// KeyVault 的解锁缓存（内存态私钥）是实例字段——各处各 new 一份实例
/// 时，备份页解锁后同步调度器读到的另一份仍是锁着的。收敛为全局唯一
/// 实例后，任一处解锁（口令/恢复码/生物识别）全应用立即可见。
class VaultProvider {
  VaultProvider._();

  static KeyVault? _override;

  /// 全局唯一实例（secure storage 无状态；唯解锁缓存是实例态，须单例）
  static KeyVault get vault =>
      _override ?? KeyVault(SecureVaultStore.instance);

  @visibleForTesting
  static void overrideForTesting(KeyVault vault) => _override = vault;

  @visibleForTesting
  static void resetForTesting() => _override = null;
}
