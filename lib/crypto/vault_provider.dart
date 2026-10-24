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
  static KeyVault? _instance;

  /// 全局唯一实例（secure storage 无状态；唯解锁缓存是实例态，须单例）。
  /// 真单例：首次访问惰性创建并缓存，任一处解锁（口令/恢复码/生物识别）
  /// 全应用立即可见——此前 getter 每次 new 新实例，备份页解锁后同步
  /// 调度器读到的另一份仍是锁着的，门控永远「密钥未解锁」。
  static KeyVault get vault =>
      _override ?? (_instance ??= KeyVault(SecureVaultStore.instance));

  @visibleForTesting
  static void overrideForTesting(KeyVault vault) => _override = vault;

  @visibleForTesting
  static void resetForTesting() => _override = null;
}
