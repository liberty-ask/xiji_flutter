import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart';

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

}
