import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/crypto/crypto_primitives.dart';

void main() {
  group('Argon2id 口令派生', () {
    test('同口令同 salt 派生结果确定', () {
      final salt = Uint8List.fromList(List.filled(16, 7));
      final a = CryptoPrimitives.deriveKek('口令Pass123', salt,
          memoryKib: 64, iterations: 1);
      final b = CryptoPrimitives.deriveKek('口令Pass123', salt,
          memoryKib: 64, iterations: 1);
      expect(a.length, 32);
      expect(a, equals(b));
    });

    test('不同口令或不同 salt 派生结果不同', () {
      final salt1 = Uint8List.fromList(List.filled(16, 1));
      final salt2 = Uint8List.fromList(List.filled(16, 2));
      final base = CryptoPrimitives.deriveKek('password', salt1,
          memoryKib: 64, iterations: 1);
      expect(
          CryptoPrimitives.deriveKek('password!', salt1, memoryKib: 64, iterations: 1),
          isNot(equals(base)));
      expect(
          CryptoPrimitives.deriveKek('password', salt2, memoryKib: 64, iterations: 1),
          isNot(equals(base)));
    });

    test('生产参数（64MB/t=3）冒烟：可跑通且结果确定', () {
      final salt = Uint8List.fromList(List.filled(16, 3));
      final a = CryptoPrimitives.deriveKek('生产档口令', salt);
      final b = CryptoPrimitives.deriveKek('生产档口令', salt);
      expect(a.length, CryptoPrimitives.kArgon2OutputLength);
      expect(a, equals(b));
    });
  });

  group('AES-256-GCM', () {
    final key = Uint8List.fromList(List.filled(32, 9));
    // 业务侧加密的是 UTF-8 字节（JSON 序列化），明文样例同样用 UTF-8 编码
    final plaintext = utf8.encode('早餐 47.62 元');

    test('加解密往返', () async {
      final box = await CryptoPrimitives.aeadEncrypt(key, plaintext);
      expect(box.nonce.length, 12);
      final clear = await CryptoPrimitives.aeadDecrypt(key, box);
      expect(clear, equals(plaintext));
    });

    test('同明文两次加密 nonce 不同（随机 nonce）', () async {
      final a = await CryptoPrimitives.aeadEncrypt(key, plaintext);
      final b = await CryptoPrimitives.aeadEncrypt(key, plaintext);
      expect(a.nonce, isNot(equals(b.nonce)));
      expect(a.cipherText, isNot(equals(b.cipherText)));
    });

    test('错误密钥解密必须失败', () async {
      final box = await CryptoPrimitives.aeadEncrypt(key, plaintext);
      final wrongKey = Uint8List.fromList(List.filled(32, 1));
      expect(
        () => CryptoPrimitives.aeadDecrypt(wrongKey, box),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('密文篡改解密必须失败', () async {
      final box = await CryptoPrimitives.aeadEncrypt(key, plaintext);
      final tampered = SecretBox(
        Uint8List.fromList([...box.cipherText.take(3), box.cipherText[3] ^ 0xFF, ...box.cipherText.skip(4)]),
        nonce: box.nonce,
        mac: box.mac,
      );
      expect(
        () => CryptoPrimitives.aeadDecrypt(key, tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('AAD 参与认证：加密与解密 AAD 不一致必须失败', () async {
      final box =
          await CryptoPrimitives.aeadEncrypt(key, plaintext, aad: [1, 2, 3]);
      expect(
        () => CryptoPrimitives.aeadDecrypt(key, box, aad: [1, 2, 4]),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      // AAD 一致时正常解出
      final clear = await CryptoPrimitives.aeadDecrypt(key, box, aad: [1, 2, 3]);
      expect(clear, equals(plaintext));
    });
  });

  group('X25519', () {
    test('双方协商得到相同共享秘密', () async {
      final alice = await CryptoPrimitives.generateX25519KeyPair();
      final bob = await CryptoPrimitives.generateX25519KeyPair();
      final alicePub = await alice.extractPublicKey();
      final bobPub = await bob.extractPublicKey();

      final s1 = await CryptoPrimitives.x25519SharedSecret(
          ourKeyPair: alice, theirPublicKey: bobPub);
      final s2 = await CryptoPrimitives.x25519SharedSecret(
          ourKeyPair: bob, theirPublicKey: alicePub);
      expect(s1, equals(s2));
      expect(s1.length, 32);
    });

    test('不同密钥对协商结果不同', () async {
      final alice = await CryptoPrimitives.generateX25519KeyPair();
      final bob = await CryptoPrimitives.generateX25519KeyPair();
      final bobPub = await bob.extractPublicKey();
      final s1 = await CryptoPrimitives.x25519SharedSecret(
          ourKeyPair: alice, theirPublicKey: bobPub);

      final eve = await CryptoPrimitives.generateX25519KeyPair();
      final s2 = await CryptoPrimitives.x25519SharedSecret(
          ourKeyPair: eve, theirPublicKey: bobPub);
      expect(s1, isNot(equals(s2)));
    });
  });
}
