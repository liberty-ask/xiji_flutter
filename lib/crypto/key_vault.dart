import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'crypto_primitives.dart';
import '../data/local/backup_flag_store.dart';
import '../data/local/local_user.dart';
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

/// setup 结果：恢复码明文仅在此返回一次（不落盘），由 UI 展示后即弃。
@immutable
class KeyVaultSetupResult {
  const KeyVaultSetupResult({
    required this.publicKey,
    required this.recoveryCode,
  });

  final SimplePublicKey publicKey;

  /// 规范化恢复码（24 位无分隔符），展示时用 [KeyVault.formatRecoveryCode]。
  final String recoveryCode;
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

  /// 老版本全局键（无账号隔离）：账号化升级的认领迁移源。
  /// vault 文档与生物 KEK 均按当前登录用户账号化存储——同机多账号
  /// 各自独立密钥体系，B 开关/解锁不得读到 A 的 vault（否则 B 的
  /// 数据被 A 密钥加密推云后永久失解）。
  static const String _legacyStorageKey = 'xiji_key_vault';
  static const String _legacyBiometricKey = 'xiji_biometric_kek';

  /// 生物识别 KEK 在 secure storage 中的独立 key（与 vault 文档分开存，
  /// 日常解锁先过生物识别提示，通过后才读取本 key）。
  Future<String> _biometricKey() async =>
      '$_legacyBiometricKey${await _keySuffix()}';

  Future<String> _vaultKey() async =>
      '$_legacyStorageKey${await _keySuffix()}';

  /// 自动解锁份（6.9）在 secure storage 中的独立 key：口令路径每次
  /// 解锁成功后把私钥明文密封一份（Keystore/Keychain 硬件保护，
  /// 卸载即销毁、不可导出），下次启动免口令恢复解锁态。
  static const String _autoUnlockPrefix = 'xiji_vault_auto_unlock';

  Future<String> _autoUnlockKey() async =>
      '$_autoUnlockPrefix${await _keySuffix()}';

  Future<String> _keySuffix() async {
    final user = await LocalUser.load();
    return '@${user?.id ?? 'anonymous'}';
  }

  Future<String?> _currentUserId() async => (await LocalUser.load())?.id;

  /// 账号化读取：新键 miss 且老全局键存在时，将老 vault 认领给当前
  /// 登录用户（补 userId 字段写新键、删老键，生物 KEK 键同步迁移）。
  /// 认领规则：老 vault 归「升级后首个登录读到它的用户」——升级后请
  /// 先用原配置账号登录一次再切换其他账号。
  Future<String?> _readVaultRaw() async {
    final key = await _vaultKey();
    final raw = await _store.read(key);
    if (raw != null) return raw;
    final legacy = await _store.read(_legacyStorageKey);
    if (legacy == null) return null;
    final decoded = jsonDecode(legacy);
    if (decoded is Map<String, dynamic>) {
      decoded['userId'] = await _currentUserId();
      await _store.write(key, jsonEncode(decoded));
    }
    await _store.delete(_legacyStorageKey);
    final legacyBio = await _store.read(_legacyBiometricKey);
    if (legacyBio != null) {
      await _store.write(await _biometricKey(), legacyBio);
      await _store.delete(_legacyBiometricKey);
    }
    return await _store.read(key);
  }

  /// vault 归属校验：文档 userId 与当前登录用户不符视为非本账号
  /// 配置（isConfigured 返回 false，读写口令流抛 StateError 拦截）。
  Future<bool> _vaultBelongsToCurrentUser(
      Map<String, dynamic> vault) async {
    final vaultUserId = vault['userId'] as String?;
    if (vaultUserId == null) return true;
    return vaultUserId == await _currentUserId();
  }

  /// vault 文档结构版本（向后兼容扩展预留）。
  static const int _kVaultVersion = 1;
  static const int _kSaltLength = 16;
  static const int _kKekLength = 32;

  /// 恢复码字符表：排除易混淆的 I/O/0/1（120 bit 熵，足够恢复口令用）。
  static const String _kRecoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _kRecoveryCodeLength = 24;

  final VaultStore _store;
  final Argon2Profile _defaultProfile;

  /// 解锁后的私钥缓存（内存态，6.6 生物识别日常解锁的就是这份缓存）。
  SimpleKeyPair? _unlockedKeyPair;
  SimplePublicKey? _unlockedPublicKey;

  bool get isUnlocked => _unlockedKeyPair != null;
  SimpleKeyPair? get unlockedKeyPair => _unlockedKeyPair;
  SimplePublicKey? get unlockedPublicKey => _unlockedPublicKey;

  /// 是否已完成口令设置（vault 文档存在且归属当前登录用户）。
  Future<bool> isConfigured() async {
    final raw = await _readVaultRaw();
    if (raw == null) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return false;
    return _vaultBelongsToCurrentUser(decoded);
  }

  /// 测试用：当前账号的 vault 文档键（账号化后无静态常量）。
  @visibleForTesting
  Future<String> get vaultKeyForTesting => _vaultKey();

  /// 首次设置口令：生成 X25519 密钥对，私钥分别用口令与恢复码各自派生的
  /// KEK 包裹落库（两个包裹份同一把私钥；恢复码明文不落盘、仅本次返回，
  /// 忘记口令时凭它重设口令）。已配置时抛 StateError（重设口令走
  /// changePassword 或恢复码流，防止误触覆盖既有密钥导致云端密文永久失解）。
  Future<KeyVaultSetupResult> setup(String password) async {
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

    // 恢复码包裹份：恢复码作为等价口令各自 Argon2 派生 KEK
    final recoveryCode = _generateRecoveryCode();
    final recoverySalt = _randomBytes(_kSaltLength);
    final recoveryKek = CryptoPrimitives.deriveKek(recoveryCode, recoverySalt,
        memoryKib: _defaultProfile.memoryKib,
        iterations: _defaultProfile.iterations);
    final recoveryBox = await CryptoPrimitives.aeadEncrypt(
        recoveryKek, privateKeyBytes,
        aad: publicKey.bytes);

    final vault = <String, dynamic>{
      'version': _kVaultVersion,
      'userId': await _currentUserId(),
      'publicKey': base64Encode(publicKey.bytes),
      'passwordWrap': _wrapJson(salt, _defaultProfile, box),
      'recoveryWrap': _wrapJson(recoverySalt, _defaultProfile, recoveryBox),
    };
    await _writeVault(vault);

    _unlockedKeyPair = keyPair;
    _unlockedPublicKey = publicKey;
    await _writeAutoUnlock(
        Uint8List.fromList(privateKeyBytes));
    return KeyVaultSetupResult(
        publicKey: publicKey, recoveryCode: recoveryCode);
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
    // 解锁成功即补写自动解锁份：重装/换设备后首次口令解锁完成后，
    // 之后每次启动恢复无感
    await _writeAutoUnlock(privateKeyBytes);
    return keyPair;
  }

  /// 自动解锁份（6.9）：读 secure storage 中密封的私钥副本，恢复
  /// 解锁态。解决「每次打开 App 都要输备份口令」——本地库本为明文
  /// SQLite，备份口令并不保护本机数据（锁屏才是本机真正的门），自动
  /// 解锁份的安全增量损失≈0；口令退役为「卸载重装/换设备恢复 + 改
  /// 口令/恢复码重置」专用凭证。
  ///
  /// 返回 false 的场景（由 UI 层决定是否弹口令框）：
  /// - vault 未配置
  /// - 开启了生物识别保护（尊重「解锁要过指纹」的用户意愿，走 6.6）
  /// - 无自动解锁份（卸载重装/换设备/老版本升级后首次启动）
  /// - 副本损坏（按无自动解锁份处理，走口令）
  Future<bool> autoUnlock() async {
    if (isUnlocked) return true;
    if (await isBiometricEnabled()) return false;
    final raw = await _readVaultRaw();
    if (raw == null) return false;
    final b64 = await _store.read(await _autoUnlockKey());
    if (b64 == null) return false;
    try {
      final doc = jsonDecode(raw);
      if (doc is! Map<String, dynamic>) return false;
      if (!await _vaultBelongsToCurrentUser(doc)) return false;
      final publicKey = SimplePublicKey(
          base64Decode(doc['publicKey'] as String),
          type: KeyPairType.x25519);
      final keyPair = SimpleKeyPairData(base64Decode(b64),
          publicKey: publicKey, type: KeyPairType.x25519);
      _unlockedKeyPair = keyPair;
      _unlockedPublicKey = publicKey;
      return true;
    } catch (_) {
      return false; // 副本损坏：按无自动解锁份处理，走口令
    }
  }

  /// 写自动解锁份（密封私钥副本到 secure storage）。私钥不变（改口令
  /// 仅重包裹），自动解锁份天然免疫改口令。写失败静默不阻断解锁
  /// （下次口令路径再补写）。
  Future<void> _writeAutoUnlock(Uint8List privateKeyBytes) async {
    try {
      await _store.write(await _autoUnlockKey(), base64Encode(privateKeyBytes));
    } catch (_) {
      // 存储层异常不阻断解锁主流程
    }
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
    await _writeVault(vault);
  }

  /// 凭恢复码重置口令（6.5）：恢复码解开私钥，新口令仅重包裹
  /// passwordWrap；恢复码包裹份、公钥与存量密文体系不受影响。
  /// 重置成功后私钥缓存于内存（解锁态）。恢复码错误抛
  /// [KeyVaultUnlockException]；vault 无恢复码包裹份抛 StateError
  /// （理论不可达：setup 必生成恢复码包裹份）。
  Future<void> resetPasswordWithRecoveryCode(
      String recoveryCodeInput, String newPassword) async {
    final vault = await _readVault();
    final wrap = vault['recoveryWrap'];
    if (wrap == null) {
      throw StateError('KeyVault has no recovery wrap');
    }
    final privateKeyBytes =
        await _unwrap(vault, wrap, normalizeRecoveryCode(recoveryCodeInput));

    final salt = _randomBytes(_kSaltLength);
    final kek = CryptoPrimitives.deriveKek(newPassword, salt,
        memoryKib: _defaultProfile.memoryKib,
        iterations: _defaultProfile.iterations);
    final publicKeyBytes = base64Decode(vault['publicKey'] as String);
    final box = await CryptoPrimitives.aeadEncrypt(kek, privateKeyBytes,
        aad: publicKeyBytes);
    vault['passwordWrap'] = _wrapJson(salt, _defaultProfile, box);
    await _writeVault(vault);

    final publicKey =
        SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
    _unlockedKeyPair = SimpleKeyPairData(privateKeyBytes,
        publicKey: publicKey, type: KeyPairType.x25519);
    _unlockedPublicKey = publicKey;
    // 恢复码重置路径同样补写自动解锁份（私钥未变，幂等覆盖）
    await _writeAutoUnlock(privateKeyBytes);
  }

  /// 是否已开启生物识别解锁（biometricWrap 与 KEK 双存才视为开启）。
  Future<bool> isBiometricEnabled() async {
    final raw = await _readVaultRaw();
    if (raw == null) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['biometricWrap'] == null ||
        !await _vaultBelongsToCurrentUser(decoded)) {
      return false;
    }
    return await _store.read(await _biometricKey()) != null;
  }

  /// 开启生物识别解锁（6.6）：生成随机 KEK 包裹当前已解锁的私钥，
  /// KEK 存 secure storage 独立 key。日常解锁由 UI 层先过生物识别
  /// 提示，再调 [unlockWithBiometric] 取 KEK 解包。未解锁态不可开启
  /// （需先凭口令/恢复码解锁，口令仅开启/重置时输入）。
  /// 改口令/重置口令不动 biometricWrap（私钥未变）。
  Future<void> enableBiometric() async {
    final keyPair = _unlockedKeyPair;
    final publicKey = _unlockedPublicKey;
    if (keyPair == null || publicKey == null) {
      throw StateError('KeyVault is locked');
    }
    final vault = await _readVault();
    final kek = _randomBytes(_kKekLength);
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final box = await CryptoPrimitives.aeadEncrypt(kek, privateKeyBytes,
        aad: publicKey.bytes);
    vault['biometricWrap'] = _boxJson(box);
    await _writeVault(vault);
    await _store.write(await _biometricKey(), base64Encode(kek));
  }

  /// 生物识别提示通过后调用：用 KEK 解开私钥并缓存于内存。
  /// 未开启抛 StateError；KEK/包裹物损坏抛 [KeyVaultUnlockException]。
  Future<SimpleKeyPair> unlockWithBiometric() async {
    final vault = await _readVault();
    final wrap = vault['biometricWrap'];
    final kekRaw = await _store.read(await _biometricKey());
    if (wrap == null || kekRaw == null) {
      throw StateError('Biometric unlock not enabled');
    }
    try {
      final box = SecretBox(
        base64Decode(wrap['ciphertext'] as String),
        nonce: base64Decode(wrap['nonce'] as String),
        mac: Mac(base64Decode(wrap['mac'] as String)),
      );
      final privateKeyBytes = await CryptoPrimitives.aeadDecrypt(
          base64Decode(kekRaw), box,
          aad: base64Decode(vault['publicKey'] as String));
      final publicKey = SimplePublicKey(
          base64Decode(vault['publicKey'] as String),
          type: KeyPairType.x25519);
      final keyPair = SimpleKeyPairData(privateKeyBytes,
          publicKey: publicKey, type: KeyPairType.x25519);
      _unlockedKeyPair = keyPair;
      _unlockedPublicKey = publicKey;
      return keyPair;
    } on SecretBoxAuthenticationError {
      throw KeyVaultUnlockException();
    }
  }

  /// 关闭生物识别解锁：删除包裹份与 KEK（口令/恢复码包裹份不受影响）。
  Future<void> disableBiometric() async {
    final raw = await _readVaultRaw();
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> &&
        decoded['biometricWrap'] != null) {
      decoded.remove('biometricWrap');
      await _writeVault(decoded);
    }
    await _store.delete(await _biometricKey());
  }

  /// vault 文档统一写入口：每次变更递增 syncVersion（vault 云端
  /// 托管记录的 LWW 版本），由 VaultSyncService 随同步推上云。
  Future<void> _writeVault(Map<String, dynamic> vault) async {
    vault['syncVersion'] = (vault['syncVersion'] as int? ?? 0) + 1;
    await _store.write(await _vaultKey(), jsonEncode(vault));
  }

  /// 云备份开关（6.8 修订）：开关真值源在 vault 文档内（enabled 字段），
  /// 随 vault 云端托管漫游——重装/换设备登录后开关状态自动恢复，
  /// 不再出现「明明开了怎么又关了」。未配置 vault 时恒为 false。
  Future<bool> isBackupEnabled() async {
    final raw = await _readVaultRaw();
    if (raw == null) return false;
    final doc = jsonDecode(raw);
    if (doc is! Map<String, dynamic>) return false;
    final enabled = doc['enabled'];
    if (enabled is bool) return enabled;
    // 一次性迁移：老 vault 文档无 enabled 字段，映射旧 BackupFlagStore
    // 本地缓存（曾开启过备份的忠实迁移），回填落盘
    final migrated = await BackupFlagStore.isEnabled();
    doc['enabled'] = migrated;
    await _writeVault(doc);
    return migrated;
  }

  /// 写云备份开关并落盘（经 _writeVault 递增 syncVersion，随下轮
  /// vault 推送漫游到云端——关闭动作也必须推：否则重装后弹回开启）。
  Future<void> setBackupEnabled(bool value) async {
    final raw = await _readVaultRaw();
    if (raw == null) return; // vault 未配置：无开关可言（UI 层不应到达）
    final doc = jsonDecode(raw);
    if (doc is! Map<String, dynamic>) return;
    doc['enabled'] = value;
    await _writeVault(doc);
  }

  /// 导出 vault 文档（口令包裹的密文，无私钥明文），
  /// 供云端托管记录构造使用。未配置抛 StateError。
  Future<Map<String, dynamic>> exportVaultDoc() async => await _readVault();

  /// vault 托管记录的传输密钥 = HKDF(userId)。
  /// 这层加密仅为 sync_records 密文格式统一（GCM + AAD 绑记录 ID）
  /// 与「服务端零明文」一致性；vault 自身保密性由 Argon2id 口令包裹
  /// 保证——文档暴露给任何人，口令不泄露即安全（零信任兼容）。
  /// 用 userId 派生而非公钥：新设备无私钥也不知公钥（在密文内），
  /// userId 是登录即得的机制字段，跨设备一致。
  static Uint8List vaultTransportKey(String userId) =>
      CryptoPrimitives.hkdfSha256(utf8.encode(userId),
          info: _kVaultTransportInfo);

  static const String _kVaultTransportInfo = 'xiji-vault-transport';

  /// 导入云端托管 vault 文档（新设备恢复 / 多设备口令变更同步）。
  /// LWW：云端 syncVersion 不高于本地时忽略（幂等）；归属校验与
  /// 本地写入同键。导入后需口令解锁，不解锁不产生任何明文。
  /// 返回是否采纳（false = 本地已同版或更新）。
  Future<bool> importVaultDoc(Map<String, dynamic> cloudDoc) async {
    final cloudUserId = cloudDoc['userId'] as String?;
    final currentId = await _currentUserId();
    if (cloudUserId != null && currentId != null && cloudUserId != currentId) {
      return false; // 他人的 vault 记录，拒收
    }
    if (cloudDoc['publicKey'] == null ||
        cloudDoc['passwordWrap'] == null) {
      return false; // 结构不完整，拒收
    }
    final raw = await _readVaultRaw();
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final localVer = decoded['syncVersion'] as int? ?? 0;
        final cloudVer = cloudDoc['syncVersion'] as int? ?? 0;
        if (cloudVer <= localVer) return false; // 本地同版或更新
        final localUser = decoded['userId'] as String?;
        if (localUser != null && cloudUserId != null &&
            localUser != cloudUserId) {
          return false; // 公钥体系不同的 vault，拒收（防跨账号覆盖）
        }
      }
    }
    await _store.write(await _vaultKey(), jsonEncode(cloudDoc));
    return true;
  }

  /// 清除内存中的解锁缓存（App 退后台超时/登出时调用；不动物理包裹物）。
  void lock() {
    _unlockedKeyPair = null;
    _unlockedPublicKey = null;
  }

  Future<Map<String, dynamic>> _readVault() async {
    final raw = await _readVaultRaw();
    if (raw == null) {
      throw StateError('KeyVault not configured');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('vault document corrupted');
    }
    if (!await _vaultBelongsToCurrentUser(decoded)) {
      throw StateError('KeyVault belongs to another account');
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

  /// 随机 KEK 包裹份（生物识别用）：无需口令派生参数，仅存密文盒。
  Map<String, dynamic> _boxJson(SecretBox box) {
    return <String, dynamic>{
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

  /// 随机生成规范化恢复码（24 位无分隔符，派生 KEK 也用此形态）。
  String _generateRecoveryCode() {
    final rng = Random.secure();
    return List.generate(
      _kRecoveryCodeLength,
      (_) => _kRecoveryAlphabet[rng.nextInt(_kRecoveryAlphabet.length)],
    ).join();
  }

  /// 恢复码展示格式：每 4 位一组（XXXX-XXXX-XXXX-XXXX-XXXX-XXXX）。
  static String formatRecoveryCode(String normalized) {
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write('-');
      buffer.write(normalized[i]);
    }
    return buffer.toString();
  }

  /// 用户输入归一：大小写不敏感、剔除分隔符与不在字符表中的字符
  /// （含易混淆的 I/O/0/1，误输会在解包认证时失败而非静默变形）。
  static String normalizeRecoveryCode(String input) {
    final upper = input.toUpperCase();
    return upper.replaceAll(RegExp('[^$_kRecoveryAlphabet]'), '');
  }
}
