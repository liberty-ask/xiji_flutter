import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'crypto_primitives.dart';
import 'vault_store.dart';

/// Argon2id 派生参数。随包裹物持久化——解包按持久化值执行（参数升级后旧包裹
/// 仍可解），改口令时用当前默认档重包裹。
@immutable
class Argon2Profile {
  const Argon2Profile({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  /// 移动端安全档（与 CryptoPrimitives 生产常量一致）。
  factory Argon2Profile.production() => const Argon2Profile(
        memoryKib: CryptoPrimitives.kArgon2MemoryKib,
        iterations: CryptoPrimitives.kArgon2Iterations,
        parallelism: CryptoPrimitives.kArgon2Parallelism,
      );

  /// 单测提速档（不用于生产）。
  factory Argon2Profile.fast() => const Argon2Profile(
        memoryKib: 64,
        iterations: 1,
        parallelism: 1,
      );

  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'memoryKib': memoryKib,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  factory Argon2Profile.fromJson(Map<String, dynamic> json) => Argon2Profile(
        memoryKib: json['memoryKib'] as int,
        iterations: json['iterations'] as int,
        parallelism: json['parallelism'] as int,
      );
}

/// 解锁/解包失败（口令错误或包裹物损坏）。不区分两种情况，避免向攻击者
/// 暴露「口令对了但数据坏了」这类信息。
class KeyVaultUnlockException implements Exception {
  @override
  String toString() => 'KeyVaultUnlockException';
}

/// 信封加密的私钥层（见 openspec design.md D3）：
///
///   加密口令 --Argon2id--> KEK（仅内存，不落盘）
///     KEK 解开 secure storage 中被包裹的 X25519 数据私钥
///
/// KEK 每次口令操作即时派生、用完即弃；落库的只有口令包裹份
/// （salt + Argon2 参数 + nonce + 密文）。改口令仅重包裹私钥，
/// 公钥与家庭密钥包裹物（7.x/8.4）均不受影响。
class KeyVault {
  KeyVault(this._store, {Argon2Profile? profile})
      : _defaultProfile = profile ?? Argon2Profile.production();

  /// secure storage 中的 vault 文档 key。
  static const String storageKey = 'xiji_key_vault';

  /// vault 文档结构版本（向后兼容扩展预留）。
  static const int _kVaultVersion = 1;
  static const int _kSaltLength = 16;

  final VaultStore _store;
  final Argon2Profile _defaultProfile;

  /// 解锁后的私钥缓存（内存态，6.6 生物识别日常解锁的就是这份缓存）。
  SimpleKeyPair? _unlockedKeyPair;
  SimplePublicKey? _unlockedPublicKey;

  bool get isUnlocked => _unlockedKeyPair != null;
  SimpleKeyPair? get unlockedKeyPair => _unlockedKeyPair;
  SimplePublicKey? get unlockedPublicKey => _unlockedPublicKey;

  /// 是否已完成口令设置（vault 文档存在）。
  Future<bool> isConfigured() async => await _store.read(storageKey) != null;

  /// 首次设置口令：生成 X25519 密钥对，私钥用口令派生的 KEK 包裹落库。
  /// 已配置时抛 StateError（重设口令走 changePassword 或恢复码流，防止
  /// 误触覆盖既有密钥导致云端密文永久失解）。
  Future<SimplePublicKey> setup(String password) async {
    if (await isConfigured()) {
      throw StateError('KeyVault already configured');
    }
    final salt = _randomBytes(_kSaltLength);
    final kek = CryptoPrimitives.deriveKek(password, salt,
        memoryKib: _defaultProfile.memoryKib,
        iterations: _defaultProfile.iterations);
    final keyPair = await CryptoPrimitives.generateX25519KeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    // AAD 绑定公钥：公钥与私钥包裹物互换拼装无法通过认证
    final box = await CryptoPrimitives.aeadEncrypt(kek, privateKeyBytes,
        aad: publicKey.bytes);
    final vault = <String, dynamic>{
      'version': _kVaultVersion,
      'publicKey': base64Encode(publicKey.bytes),
      'passwordWrap': _wrapJson(salt, _defaultProfile, box),
    };
    await _store.write(storageKey, jsonEncode(vault));

    _unlockedKeyPair = keyPair;
    _unlockedPublicKey = publicKey;
    return publicKey;
  }

  /// 口令解锁：派生 KEK 解开私钥并缓存于内存。
  /// 口令错误 / 包裹物损坏抛 [KeyVaultUnlockException]。
  Future<SimpleKeyPair> unlock(String password) async {
    final vault = await _readVault();
    final privateKeyBytes =
        await _unwrap(vault, vault['passwordWrap'], password);
    final publicKey = SimplePublicKey(
        base64Decode(vault['publicKey'] as String),
        type: KeyPairType.x25519);
    final keyPair = SimpleKeyPairData(privateKeyBytes,
        publicKey: publicKey, type: KeyPairType.x25519);
    _unlockedKeyPair = keyPair;
    _unlockedPublicKey = publicKey;
    return keyPair;
  }

  /// 改口令：旧口令验证并解包私钥，新口令仅重新包裹私钥落库。
  /// KEK 不落盘，其余包裹物（将来的恢复码份、家庭密钥份）原样保留，
  /// 存量业务密文不动。
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final vault = await _readVault();
    final privateKeyBytes =
        await _unwrap(vault, vault['passwordWrap'], oldPassword);

    // 新 salt + 新 KEK，口令包裹份整块替换
    final salt = _randomBytes(_kSaltLength);
    final kek = CryptoPrimitives.deriveKek(newPassword, salt,
        memoryKib: _defaultProfile.memoryKib,
        iterations: _defaultProfile.iterations);
    final publicKeyBytes = base64Decode(vault['publicKey'] as String);
    final box = await CryptoPrimitives.aeadEncrypt(kek, privateKeyBytes,
        aad: publicKeyBytes);
    vault['passwordWrap'] = _wrapJson(salt, _defaultProfile, box);
    await _store.write(storageKey, jsonEncode(vault));
  }

  /// 清除内存中的解锁缓存（App 退后台超时/登出时调用；不动物理包裹物）。
  void lock() {
    _unlockedKeyPair = null;
    _unlockedPublicKey = null;
  }

  Future<Map<String, dynamic>> _readVault() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      throw StateError('KeyVault not configured');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('vault document corrupted');
    }
    return decoded;
  }

  Future<Uint8List> _unwrap(
      Map<String, dynamic> vault, dynamic wrap, String password) async {
    try {
      final w = wrap as Map<String, dynamic>;
      final profile = Argon2Profile.fromJson(w['argon2']);
      final salt = base64Decode(w['salt'] as String);
      final kek = CryptoPrimitives.deriveKek(password, salt,
          memoryKib: profile.memoryKib, iterations: profile.iterations);
      final box = SecretBox(
        base64Decode(w['ciphertext'] as String),
        nonce: base64Decode(w['nonce'] as String),
        mac: Mac(base64Decode(w['mac'] as String)),
      );
      return await CryptoPrimitives.aeadDecrypt(kek, box,
          aad: base64Decode(vault['publicKey'] as String));
    } on SecretBoxAuthenticationError {
      throw KeyVaultUnlockException();
    }
  }

  Map<String, dynamic> _wrapJson(
      Uint8List salt, Argon2Profile profile, SecretBox box) {
    return <String, dynamic>{
      'salt': base64Encode(salt),
      'argon2': profile.toJson(),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }
}
