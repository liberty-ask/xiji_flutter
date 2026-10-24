import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/local_user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  KeyVault newVault(InMemoryVaultStore store) =>
      KeyVault(store, profile: Argon2Profile.fast());

  /// 模拟登录指定账号（LocalUser 直接读 SharedPreferences mock）
  Future<void> loginAs(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalUser.profileKey,
        jsonEncode({'id': id, 'nickname': 'u-$id', 'phone': '13800000000'}));
  }

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

      final raw = (await store.read(await vault.vaultKeyForTesting))!;
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      // 结构白名单：密钥本体与 KEK 绝不落盘
      expect(doc.keys, unorderedEquals(
          ['version', 'userId', 'publicKey', 'passwordWrap', 'recoveryWrap']));
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

      final rawBefore = (await store.read(await vault.vaultKeyForTesting))!;
      final docBefore = jsonDecode(rawBefore) as Map<String, dynamic>;
      final wrapBefore = docBefore['passwordWrap'] as Map<String, dynamic>;

      await vault.changePassword('old-password', 'new-password');

      final rawAfter = (await store.read(await vault.vaultKeyForTesting))!;
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
      final rawBefore = (await store.read(await vault.vaultKeyForTesting))!;

      expect(
        () => vault.changePassword('typo-password', 'new-password'),
        throwsA(isA<KeyVaultUnlockException>()),
      );
      expect(await store.read(await vault.vaultKeyForTesting), equals(rawBefore));
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
      final rawBefore = (await store.read(await vault.vaultKeyForTesting))!;
      final docBefore = jsonDecode(rawBefore) as Map<String, dynamic>;
      vault.lock();

      // 用户输入带分隔符与小写的恢复码，归一后应正常解包
      final formattedInput =
          KeyVault.formatRecoveryCode(setupResult.recoveryCode).toLowerCase();
      await vault.resetPasswordWithRecoveryCode(formattedInput, 'new-pass-9');

      final rawAfter = (await store.read(await vault.vaultKeyForTesting))!;
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
      final rawBefore = (await store.read(await vault.vaultKeyForTesting))!;

      final wrongCode = List.generate(24, (_) => 'X').join();
      expect(
        () => vault.resetPasswordWithRecoveryCode(wrongCode, 'new-pass-9'),
        throwsA(isA<KeyVaultUnlockException>()),
      );

      expect(await store.read(await vault.vaultKeyForTesting), equals(rawBefore));
      final fresh = newVault(store);
      await fresh.unlock('old-password'); // 旧口令仍有效
    });

    test('恢复码重置口令：无恢复码包裹份抛 StateError（理论不可达防御）',
        () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('old-password');
      final doc =
          jsonDecode((await store.read(await vault.vaultKeyForTesting))!) as Map<String, dynamic>;
      doc.remove('recoveryWrap');
      await store.write(await vault.vaultKeyForTesting, jsonEncode(doc));

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
      final raw = (await store.read(await vault.vaultKeyForTesting))!;
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

  group('vault 账号隔离（同机多账号硬约束）', () {
    test('A 的开关/vault 不串到 B：B 全新配置，A 回登数据完好', () async {
      final store = InMemoryVaultStore();
      await loginAs('user-a');
      final vaultA = newVault(store);
      final setupA = await vaultA.setup('password-a-123');
      await vaultA.enableBiometric();

      // 切换账号 B（同手机另一账号登录）
      await loginAs('user-b');
      final vaultB = newVault(store);
      expect(await vaultB.isConfigured(), isFalse,
          reason: 'B 读不到 A 的 vault（键已账号化）');
      expect(await vaultB.isBiometricEnabled(), isFalse);
      expect(() => vaultB.unlock('password-a-123'), throwsStateError,
          reason: 'B 输 A 的口令不可能解锁——vault 都不存在');

      // B 独立 setup 自己的口令（不覆盖 A 的云端加密身份）
      final setupB = await vaultB.setup('password-b-456');
      expect(setupB.publicKey.bytes, isNot(equals(setupA.publicKey.bytes)),
          reason: 'B 有独立密钥对，不是复用 A 的');

      // A 回登：vault 完好，口令解锁如初（同 store 双键并存互不干扰）
      await loginAs('user-a');
      final vaultA2 = newVault(store);
      expect(await vaultA2.isConfigured(), isTrue);
      expect(await vaultA2.isBiometricEnabled(), isTrue);
      vaultA2.lock();
      final pair = await vaultA2.unlock('password-a-123');
      final pub = await pair.extractPublicKey();
      expect(pub.bytes, equals(setupA.publicKey.bytes),
          reason: 'A 的私钥与解锁路径未被 B 的 setup 破坏');
    });

    test('老全局键认领迁移：归升级后首个登录读到它的用户', () async {
      final store = InMemoryVaultStore();
      // 模拟升级前的老版 vault（全局键、无 userId 字段）
      await store.write('xiji_key_vault',
          jsonEncode({'version': 1, 'publicKey': 'aGk=', 'passwordWrap': {}}));
      await store.write('xiji_biometric_kek', 'b2xkS0VL');

      await loginAs('user-a');
      final vault = newVault(store);
      expect(await vault.isConfigured(), isTrue, reason: '老 vault 被当前用户认领');

      // 迁移落位：新账号键有文档且归属 A，老键清空
      final raw = (await store.read(await vault.vaultKeyForTesting))!;
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      expect(doc['userId'], 'user-a');
      expect(await store.read('xiji_key_vault'), isNull);
      expect(await store.read((await vault.vaultKeyForTesting)
          .replaceFirst(RegExp(r'@.*$'), '@user-b')), isNull,
          reason: '认领只写给当前用户，不复制给其他账号键');
      final bioKey =
          (await vault.vaultKeyForTesting).replaceFirst('xiji_key_vault', 'xiji_biometric_kek');
      expect(await store.read(bioKey), 'b2xkS0VL',
          reason: '生物 KEK 老键同步迁移到账号键');

      // 认领后切 B：B 不认领（老键已删），B 未配置
      await loginAs('user-b');
      final vaultB = newVault(store);
      expect(await vaultB.isConfigured(), isFalse);
    });

    test('防御纵深：A 的文档被挪到 B 的键下，归属校验拦截', () async {
      final store = InMemoryVaultStore();
      await loginAs('user-a');
      final vaultA = newVault(store);
      await vaultA.setup('password-a-123');
      final rawA = (await store.read(await vaultA.vaultKeyForTesting))!;

      // 异常场景：A 的文档被手工写到 B 的键下（存储串库/备份恢复错位）
      await loginAs('user-b');
      await store.write('xiji_key_vault@user-b', rawA);
      final vaultB = newVault(store);
      expect(await vaultB.isConfigured(), isFalse,
          reason: '文档 userId 与当前用户不符，视为非本账号配置');
      expect(() => vaultB.unlock('password-a-123'), throwsStateError,
          reason: '解锁路径同样被归属校验拦截');
    });
  });
}
