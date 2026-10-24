import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' hide Mac;

/// 端到端加密原语封装（第 6 组基座，见 openspec design.md D3）。
///
/// 三层信封的底层原语：
/// - Argon2id：加密口令 -> KEK（不落盘）
/// - X25519：设备身份密钥对与家庭密钥包裹
/// - AES-256-GCM：业务记录与包裹物的对称加密
///
/// 本层只做原语，不含任何存储与密钥管理（信封流程在 6.2 vault 层）。
class CryptoPrimitives {
  CryptoPrimitives._();

  /// Argon2id 生产参数（移动端安全档：64MB / t=3 / p=1，输出 32 字节 KEK）。
  /// 仅口令设置与重置时执行一次，日常解锁走生物识别缓存，不承受此开销。
  static const int kArgon2MemoryKib = 64 * 1024;
  static const int kArgon2Iterations = 3;
  static const int kArgon2Parallelism = 1;
  static const int kArgon2OutputLength = 32;

  /// 口令派生 KEK。同口令同 salt 必得同 KEK；[memoryKib]/[iterations] 可注入
  /// 小参数供单测提速，生产行为不受影响。
  static Uint8List deriveKek(
    String password,
    Uint8List salt, {
    int memoryKib = kArgon2MemoryKib,
    int iterations = kArgon2Iterations,
  }) {
    final generator = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: kArgon2OutputLength,
        iterations: iterations,
        memory: memoryKib,
        lanes: kArgon2Parallelism,
      ));
    final out = Uint8List(kArgon2OutputLength);
    generator.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, out, 0);
    return out;
  }

  /// AES-256-GCM 加密（12 字节随机 nonce）。key 必须 32 字节。
  /// [aad] 为附加认证数据（如记录 ID），参与认证但不入密文。
  static Future<SecretBox> aeadEncrypt(
    Uint8List key,
    List<int> plaintext, {
    List<int>? aad,
  }) async {
    final cipher = AesGcm.with256bits();
    return cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      aad: aad ?? const <int>[],
    );
  }

  /// AES-256-GCM 解密。密文被篡改 / key 或 aad 不匹配时抛 [SecretBoxAuthenticationError]。
  static Future<Uint8List> aeadDecrypt(
    Uint8List key,
    SecretBox box, {
    List<int>? aad,
  }) async {
    final cipher = AesGcm.with256bits();
    final clear = await cipher.decrypt(box,
        secretKey: SecretKey(key), aad: aad ?? const <int>[]);
    return Uint8List.fromList(clear);
  }

  /// 同步数据密钥的 HKDF info（固定域分离串：派生用途唯一，换用途必须换 info）
  static const String kSyncDataKeyInfo = 'xiji-sync-data-key';

  /// HKDF-SHA256（RFC 5869，salt 置空）：从高熵 ikm（X25519 私钥）派生
  /// 同步数据密钥 F。同私钥必得同 F——新设备凭口令解出同一私钥即得同 F，
  /// 存量密文全量可解（见 design.md 7.3）。
  /// extract：PRK = HMAC-SHA256(零 salt, ikm)；expand：T(i) 逐块串联截断。
  static Uint8List hkdfSha256(
    Uint8List ikm, {
    required String info,
    int length = 32,
  }) {
    Uint8List hmac(Uint8List key, Uint8List data) {
      final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
      return mac.process(data);
    }

    // extract（salt 置空 = 32 字节全零 key）
    final prk = hmac(Uint8List(32), ikm);

    // expand：T(i) = HMAC(PRK, T(i-1) ‖ info ‖ i)，逐块拼接截断
    final infoBytes = utf8.encode(info);
    final result = Uint8List(length);
    var filled = 0;
    Uint8List t = Uint8List(0);
    var counter = 1;
    while (filled < length) {
      t = hmac(prk, Uint8List.fromList([...t, ...infoBytes, counter]));
      final take = t.length <= (length - filled) ? t.length : length - filled;
      result.setRange(filled, filled + take, t);
      filled += take;
      counter++;
    }
    return result;
  }

  /// 生成 X25519 密钥对（SimpleKeyPairData/SimplePublicKey）。
  static Future<SimpleKeyPair> generateX25519KeyPair() async {
    final algorithm = X25519();
    return algorithm.newKeyPair();
  }

  /// X25519 共享密钥协商（对方公钥 + 己方私钥 -> 共享秘密）。
  static Future<Uint8List> x25519SharedSecret({
    required SimpleKeyPair ourKeyPair,
    required SimplePublicKey theirPublicKey,
  }) async {
    final algorithm = X25519();
    final secret = await algorithm.sharedSecretKey(
      keyPair: ourKeyPair,
      remotePublicKey: theirPublicKey,
    );
    final bytes = await secret.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// 家庭密钥包裹的 HKDF info（域分离：与 dataKey/传输密钥互不可替）
  static const String kFamilyKeyWrapInfo = 'xiji-family-key-wrap';

  /// 密封盒包裹结果：临时公钥 + 包裹密文（nonce‖cipherText‖tag 拼接）。
  /// 两者均以 base64 进 fkey 记录 payload（见 design.md D13）。
  static Future<({String ephemeralPubKey, String wrappedF})>
      sealFamilyKeyFor({
    required Uint8List familyKey,
    required SimplePublicKey recipientPublicKey,
  }) async {
    final ephemeral = await generateX25519KeyPair();
    final shared = await x25519SharedSecret(
        ourKeyPair: ephemeral, theirPublicKey: recipientPublicKey);
    final wrapKey = hkdfSha256(shared, info: kFamilyKeyWrapInfo);
    final box = await aeadEncrypt(wrapKey, familyKey);
    final ephemeralPub = await ephemeral.extractPublicKey();
    final ephemeralPubBytes = ephemeralPub.bytes;
    final combined = Uint8List.fromList(
        [...box.nonce, ...box.cipherText, ...box.mac.bytes]);
    return (
      ephemeralPubKey: base64Encode(ephemeralPubBytes),
      wrappedF: base64Encode(combined),
    );
  }

  /// 密封盒解包裹：己方私钥 + 密封盒携带的临时公钥 ECDH 派生包裹密钥
  /// 解出家庭密钥 F。私钥不匹配（非本成员的包裹份）抛
  /// [SecretBoxAuthenticationError]，由调用方按静默跳过处理。
  static Future<Uint8List> openSealedFamilyKey({
    required String ephemeralPubKeyBase64,
    required String wrappedFBase64,
    required SimpleKeyPair ourKeyPair,
  }) async {
    final ephemeralPub = SimplePublicKey(
        base64Decode(ephemeralPubKeyBase64), type: KeyPairType.x25519);
    final shared = await x25519SharedSecret(
        ourKeyPair: ourKeyPair, theirPublicKey: ephemeralPub);
    final wrapKey = hkdfSha256(shared, info: kFamilyKeyWrapInfo);

    final combined = base64Decode(wrappedFBase64);
    final nonce = combined.sublist(0, 12);
    final cipherText = combined.sublist(12, combined.length - 16);
    final mac = combined.sublist(combined.length - 16);
    final clear = await aeadDecrypt(
      wrapKey,
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
    );
    return clear;
  }
}
