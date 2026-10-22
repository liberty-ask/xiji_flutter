import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';

void main() {
  KeyVault newVault(InMemoryVaultStore store) =>
      KeyVault(store, profile: Argon2Profile.fast());

  group('KeyVault 信封加密（私钥层）', () {
    test('setup 后已配置，未 setup 前未配置', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      expect(await vault.isConfigured(), isFalse);
      await vault.setup('my-password-123');
      expect(await vault.isConfigured(), isTrue);
    });

    test('重复 setup 必须被拒绝（防误覆盖密钥）', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('first-password');
      expect(() => vault.setup('second-password'), throwsStateError);
    });

    test('口令正确解锁：公钥与 setup 一致，私钥在内存缓存', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final publicKey = await vault.setup('my-password-123');
      expect(vault.isUnlocked, isTrue); // setup 后即解锁态

      final fresh = newVault(store); // 模拟重启后的新实例
      expect(fresh.isUnlocked, isFalse);
      final keyPair = await fresh.unlock('my-password-123');
      final unlockedPub = await keyPair.extractPublicKey();
      expect(unlockedPub.bytes, equals(publicKey.bytes));
      expect(fresh.isUnlocked, isTrue);
      expect(fresh.unlockedPublicKey!.bytes, equals(publicKey.bytes));
    });

    test('错误口令解锁必须失败，不留下半解锁态', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('correct-password');
      final fresh = newVault(store);
      expect(
        () => fresh.unlock('wrong-password'),
        throwsA(isA<KeyVaultUnlockException>()),
      );
      expect(fresh.isUnlocked, isFalse);
    });

    test('未配置时 unlock 抛 StateError', () async {
      final vault = newVault(InMemoryVaultStore());
      expect(() => vault.unlock('any'), throwsStateError);
    });

    test('存储中只有包裹物：无私钥明文、无 KEK 字段', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('my-password-123');

      final raw = (await store.read(KeyVault.storageKey))!;
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      // 结构白名单：密钥本体与 KEK 绝不落盘
      expect(doc.keys, unorderedEquals(['version', 'publicKey', 'passwordWrap']));
      expect(doc['passwordWrap'] is Map<String, dynamic>, isTrue);

      // 私钥明文（含 base64 形式）不得出现在存储中
      final privateKeyBytes =
          await vault.unlockedKeyPair!.extractPrivateKeyBytes();
      expect(raw.contains(base64Encode(privateKeyBytes)), isFalse);
      expect(raw.contains(base64Encode(privateKeyBytes).substring(0, 20)),
          isFalse);
    });

    test('改口令：新口令可解锁、旧口令失败、密钥对不变、仅口令包裹份变化',
        () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final originalPublicKey = await vault.setup('old-password');

      final rawBefore = (await store.read(KeyVault.storageKey))!;
      final docBefore = jsonDecode(rawBefore) as Map<String, dynamic>;
      final wrapBefore = docBefore['passwordWrap'] as Map<String, dynamic>;

      await vault.changePassword('old-password', 'new-password');

      final rawAfter = (await store.read(KeyVault.storageKey))!;
      final docAfter = jsonDecode(rawAfter) as Map<String, dynamic>;
      final wrapAfter = docAfter['passwordWrap'] as Map<String, dynamic>;

      // 改口令只动 passwordWrap：版本与公钥原样（私钥未换、密文体系不受影响）
      expect(docAfter['version'], equals(docBefore['version']));
      expect(docAfter['publicKey'], equals(docBefore['publicKey']));
      // 换了 salt 与密文（新 KEK 重包裹）
      expect(wrapAfter['salt'], isNot(equals(wrapBefore['salt'])));
      expect(wrapAfter['ciphertext'], isNot(equals(wrapBefore['ciphertext'])));

      // 旧口令失效、新口令解开的是同一把私钥
      final fresh = newVault(store);
      expect(
        () => fresh.unlock('old-password'),
        throwsA(isA<KeyVaultUnlockException>()),
      );
      final keyPair = await fresh.unlock('new-password');
      final pub = await keyPair.extractPublicKey();
      expect(pub.bytes, equals(originalPublicKey.bytes));
    });

    test('改口令旧口令错误时必须失败且不改动任何包裹物', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('real-password');
      final rawBefore = (await store.read(KeyVault.storageKey))!;

      expect(
        () => vault.changePassword('typo-password', 'new-password'),
        throwsA(isA<KeyVaultUnlockException>()),
      );
      expect(await store.read(KeyVault.storageKey), equals(rawBefore));
    });

    test('lock 清除内存解锁缓存，物理包裹物保留', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('my-password-123');
      vault.lock();
      expect(vault.isUnlocked, isFalse);
      expect(vault.unlockedKeyPair, isNull);
      expect(await vault.isConfigured(), isTrue);
      await vault.unlock('my-password-123');
      expect(vault.isUnlocked, isTrue);
    });
  });
}
