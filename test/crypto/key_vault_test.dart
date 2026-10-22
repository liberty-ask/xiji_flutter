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
      final setupResult = await vault.setup('my-password-123');
      final publicKey = setupResult.publicKey;
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

    test('存储中只有包裹物：无私钥明文、无 KEK 字段、无恢复码明文', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final setupResult = await vault.setup('my-password-123');

      final raw = (await store.read(KeyVault.storageKey))!;
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      // 结构白名单：密钥本体与 KEK 绝不落盘
      expect(doc.keys, unorderedEquals(
          ['version', 'publicKey', 'passwordWrap', 'recoveryWrap']));
      expect(doc['passwordWrap'] is Map<String, dynamic>, isTrue);
      expect(doc['recoveryWrap'] is Map<String, dynamic>, isTrue);

      // 恢复码明文（含分段片段）不得出现在存储中
      final code = setupResult.recoveryCode;
      expect(raw.contains(code), isFalse);
      expect(raw.contains(KeyVault.formatRecoveryCode(code)), isFalse);
      expect(raw.contains(code.substring(0, 8)), isFalse);

      // 私钥明文（含 base64 形式）不得出现在存储中
      final privateKeyBytes =
          await vault.unlockedKeyPair!.extractPrivateKeyBytes();
      expect(raw.contains(base64Encode(privateKeyBytes)), isFalse);
      expect(raw.contains(base64Encode(privateKeyBytes).substring(0, 20)),
          isFalse);
    });

    test('改口令：新口令可解锁、旧口令失败、密钥对不变、仅口令包裹份变化，恢复码包裹份原样',
        () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final originalPublicKey = (await vault.setup('old-password')).publicKey;

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
      expect(docAfter['recoveryWrap'], equals(docBefore['recoveryWrap']));
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

    test('恢复码形态：24 位、字符表内、每次 setup 各不相同', () async {
      final vault1 = newVault(InMemoryVaultStore());
      final vault2 = newVault(InMemoryVaultStore());
      final code1 = (await vault1.setup('pass-a')).recoveryCode;
      final code2 = (await vault2.setup('pass-b')).recoveryCode;
      expect(code1.length, equals(24));
      expect(code2.length, equals(24));
      expect(code1, isNot(equals(code2)));
      for (final c in code1.split('')) {
        expect('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.contains(c), isTrue);
      }
    });

    test('恢复码输入归一与展示格式', () {
      // 分隔符/空格/小写均可归一，易混淆字符（I/O/0/1）剔除后长度不足必失败
      expect(
        KeyVault.normalizeRecoveryCode('abcd-efgh jklm npqr stuv wxy2'),
        equals('ABCDEFGHJKLMNPQRSTUVWXY2'),
      );
      expect(
        KeyVault.normalizeRecoveryCode('io10'),
        equals(''),
      );
      expect(
        KeyVault.formatRecoveryCode('ABCDEFGHJKLMNPQRSTUVWXY2'),
        equals('ABCD-EFGH-JKLM-NPQR-STUV-WXY2'),
      );
    });

    test('恢复码重置口令：新口令生效、旧口令失效、密钥对与恢复码包裹份不变',
        () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final setupResult = await vault.setup('old-password');
      final rawBefore = (await store.read(KeyVault.storageKey))!;
      final docBefore = jsonDecode(rawBefore) as Map<String, dynamic>;
      vault.lock();

      // 用户输入带分隔符与小写的恢复码，归一后应正常解包
      final formattedInput =
          KeyVault.formatRecoveryCode(setupResult.recoveryCode).toLowerCase();
      await vault.resetPasswordWithRecoveryCode(formattedInput, 'new-pass-9');

      final rawAfter = (await store.read(KeyVault.storageKey))!;
      final docAfter = jsonDecode(rawAfter) as Map<String, dynamic>;
      expect(docAfter['publicKey'], equals(docBefore['publicKey']));
      expect(docAfter['recoveryWrap'], equals(docBefore['recoveryWrap']));
      expect(docAfter['passwordWrap'],
          isNot(equals(docBefore['passwordWrap'])));
      // 重置后即解锁态，缓存的是同一把私钥
      expect(vault.isUnlocked, isTrue);

      final fresh = newVault(store);
      expect(
        () => fresh.unlock('old-password'),
        throwsA(isA<KeyVaultUnlockException>()),
      );
      final keyPair = await fresh.unlock('new-pass-9');
      final pub = await keyPair.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));

      // 恢复码可再次用于重置（包裹份未随重置失效）
      await fresh.resetPasswordWithRecoveryCode(
          setupResult.recoveryCode, 'another-pass-1');
      final third = newVault(store);
      final keyPair2 = await third.unlock('another-pass-1');
      final pub2 = await keyPair2.extractPublicKey();
      expect(pub2.bytes, equals(setupResult.publicKey.bytes));
    });

    test('恢复码重置口令：恢复码错误不改动任何包裹物', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('old-password');
      final rawBefore = (await store.read(KeyVault.storageKey))!;

      final wrongCode = List.generate(24, (_) => 'X').join();
      expect(
        () => vault.resetPasswordWithRecoveryCode(wrongCode, 'new-pass-9'),
        throwsA(isA<KeyVaultUnlockException>()),
      );

      expect(await store.read(KeyVault.storageKey), equals(rawBefore));
      final fresh = newVault(store);
      await fresh.unlock('old-password'); // 旧口令仍有效
    });

    test('恢复码重置口令：无恢复码包裹份抛 StateError（理论不可达防御）',
        () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('old-password');
      final doc =
          jsonDecode((await store.read(KeyVault.storageKey))!) as Map<String, dynamic>;
      doc.remove('recoveryWrap');
      await store.write(KeyVault.storageKey, jsonEncode(doc));

      expect(
        () => vault.resetPasswordWithRecoveryCode('ABCDEFGHJKLMNPQRSTUVWXY2', 'n1'),
        throwsA(isA<StateError>()),
      );
    });

    test('生物识别包裹：开启需先解锁，解锁后凭包裹份解出同一私钥', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final setupResult = await vault.setup('my-password-123');
      vault.lock();
      expect(vault.isUnlocked, isFalse);
      // 锁定态不可开启（需先凭口令解锁）
      expect(() => vault.enableBiometric(), throwsA(isA<StateError>()));
      expect(await vault.isBiometricEnabled(), isFalse);

      await vault.unlock('my-password-123');
      await vault.enableBiometric();
      expect(await vault.isBiometricEnabled(), isTrue);

      // 重启模拟：lock 后无需口令，凭生物识别包裹份解锁
      vault.lock();
      final keyPair = await vault.unlockWithBiometric();
      final pub = await keyPair.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));
      expect(vault.isUnlocked, isTrue);

      // KEK 独立存储：vault 文档与 KEK 都不含私钥明文
      final raw = (await store.read(KeyVault.storageKey))!;
      expect(raw.contains('my-password-123'), isFalse);
    });

    test('生物识别包裹：改口令/重置口令后仍有效，关闭后彻底移除', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final setupResult = await vault.setup('old-password');
      await vault.enableBiometric();

      // 改口令不动 biometricWrap（私钥未换）
      await vault.changePassword('old-password', 'new-password-1');
      expect(await vault.isBiometricEnabled(), isTrue);
      vault.lock();
      final keyPair = await vault.unlockWithBiometric();
      final pub = await keyPair.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));

      // 恢复码重置口令后同样有效
      await vault.resetPasswordWithRecoveryCode(
          setupResult.recoveryCode, 'third-pass-1');
      vault.lock();
      final keyPair2 = await vault.unlockWithBiometric();
      final pub2 = await keyPair2.extractPublicKey();
      expect(pub2.bytes, equals(setupResult.publicKey.bytes));

      // 关闭：包裹份与 KEK 一并移除，解锁仅剩口令路径
      await vault.disableBiometric();
      expect(await vault.isBiometricEnabled(), isFalse);
      vault.lock();
      expect(() => vault.unlockWithBiometric(), throwsA(isA<StateError>()));
      await vault.unlock('third-pass-1');
      expect(vault.isUnlocked, isTrue);
    });
  });
}
