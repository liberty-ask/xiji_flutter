import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 密钥保险库存储抽象（注入式，单测用内存实现，不触平台通道）。
abstract class VaultStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 生产实现：Android 加密 SharedPreferences / iOS 首解锁本机 Keychain，
/// 平台选项与 ApiClient 的 token 存储保持同档安全级别。
class SecureVaultStore implements VaultStore {
  SecureVaultStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final SecureVaultStore instance = SecureVaultStore._();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 单测实现：内存 Map，模拟落库读写。
class InMemoryVaultStore implements VaultStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
