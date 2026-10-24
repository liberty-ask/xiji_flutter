import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/backup_flag_store.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';
import 'package:xiji_flutter/sync/sync_scheduler.dart' show SyncPushPort;
import 'package:xiji_flutter/sync/vault_sync_service.dart';

import '../local/fake_sync_server.dart';

/// 任务 6.7：vault 云端托管专项测试。
///
/// 核心闭环：重装/换设备后凭口令从云端恢复密钥体系——
/// setup → pushVault → 新设备 pullVaultDoc → importVaultDoc → unlock。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  KeyVault newVault(InMemoryVaultStore store) =>
      KeyVault(store, profile: Argon2Profile.fast());

  Future<void> loginAs(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalUser.profileKey,
        jsonEncode({'id': id, 'nickname': 'u-$id', 'phone': '13800000000'}));
  }

  late FakeSyncServer server;
  setUp(() => server = FakeSyncServer());

  group('6.7：重装/换设备 vault 云端恢复闭环', () {
    test('setup → 推送 → 新设备拉取导入 → 原口令解锁出同一密钥对', () async {
      // 设备 A：开启备份（setup 生成密钥对并推送托管记录）
      await loginAs('user-1');
      final storeA = InMemoryVaultStore();
      final vaultA = newVault(storeA);
      final setupResult = await vaultA.setup('my-password-123');
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');
      expect(server.record(VaultSyncService.vaultRecordId('user-1')),
          isNotNull, reason: 'vault 托管记录已上云');

      // 设备 B（新设备）：本地全新（独立 store），云端拉取导入
      final storeB = InMemoryVaultStore();
      final vaultB = newVault(storeB);
      expect(await vaultB.isConfigured(), isFalse);
      final cloudDoc = await VaultSyncService.pullVaultDoc(
          port: FakeServerPullPort(server), userId: 'user-1', familyId: 'f1');
      expect(cloudDoc, isNotNull);
      expect(cloudDoc!['recordType'], VaultSyncService.kRecordType);
      expect(await vaultB.importVaultDoc(cloudDoc), isTrue);

      // 导入后已配置，原口令解锁成功，公钥与设备 A 一致
      expect(await vaultB.isConfigured(), isTrue);
      final keyPair = await vaultB.unlock('my-password-123');
      final pub = await keyPair.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));
    });

    test('改口令后推送：新设备拉到新版 vault，新口令解锁、旧口令失败',
        () async {
      await loginAs('user-1');
      final storeA = InMemoryVaultStore();
      final vaultA = newVault(storeA);
      await vaultA.setup('old-password');
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // 设备 A 改口令 → 再推（syncVersion 递增，云端覆盖）
      await vaultA.changePassword('old-password', 'new-password');
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // 新设备拉取导入：新口令解锁、旧口令失败
      final storeB = InMemoryVaultStore();
      final vaultB = newVault(storeB);
      final cloudDoc = await VaultSyncService.pullVaultDoc(
          port: FakeServerPullPort(server), userId: 'user-1', familyId: 'f1');
      expect(await vaultB.importVaultDoc(cloudDoc!), isTrue);
      await vaultB.unlock('new-password');
      vaultB.lock();
      expect(() => vaultB.unlock('old-password'),
          throwsA(isA<KeyVaultUnlockException>()));
    });

    test('pushVault 门控：未配置/无家庭上下文均静默跳过', () async {
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      // 未配置
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vault,
          currentFamilyId: () async => 'f1');
      expect(server.pull('f1', null, null)['records'], isEmpty);

      // 已配置但无家庭
      await loginAs('user-1');
      await vault.setup('my-password-123');
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vault,
          currentFamilyId: () async => null);
      expect(server.pull('f1', null, null)['records'], isEmpty);
    });
  });

  group('6.8：开关状态随 vault 云端漫游', () {
    test('开启 → 新设备登录探测 → 开关自动恢复开启（免口令）', () async {
      // 设备 A：setup → 开启开关 → 推送（vault 含 enabled=true）
      await loginAs('user-1');
      final vaultA = newVault(InMemoryVaultStore());
      await vaultA.setup('my-password-123');
      await vaultA.setBackupEnabled(true);
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // 设备 B（重装/换设备）：登录后自动探测恢复（restoreFromCloud）
      final vaultB = newVault(InMemoryVaultStore());
      final restored = await VaultSyncService.restoreFromCloud(
          port: FakeServerPullPort(server),
          vault: vaultB,
          userId: 'user-1',
          familyId: 'f1');
      expect(restored, isTrue);
      // 开关状态已恢复为开启——用户不再有「明明开了怎么又关了」的错觉
      expect(await vaultB.isBackupEnabled(), isTrue);
      // 密钥仍是锁定态：解锁需口令（安全门槛不变）
      expect(vaultB.isUnlocked, isFalse);
      await vaultB.unlock('my-password-123');
    });

    test('关闭动作推送 enabled=false → 新设备探测后开关为关', () async {
      await loginAs('user-1');
      final vaultA = newVault(InMemoryVaultStore());
      await vaultA.setup('my-password-123');
      await vaultA.setBackupEnabled(true);
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // 设备 A 关闭开关 → 推送 enabled=false 上云（不走业务门控）
      await vaultA.setBackupEnabled(false);
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // 新设备：探测 → 开关忠实为关
      final vaultB = newVault(InMemoryVaultStore());
      await VaultSyncService.restoreFromCloud(
          port: FakeServerPullPort(server),
          vault: vaultB,
          userId: 'user-1',
          familyId: 'f1');
      expect(await vaultB.isBackupEnabled(), isFalse);
    });

    test('老 vault 无 enabled 字段：迁移读旧 BackupFlagStore 并回填',
        () async {
      await loginAs('user-1');
      final vault = newVault(InMemoryVaultStore());
      await vault.setup('my-password-123');
      // 旧版语义：vault 无 enabled 字段，本地 FlagStore 曾开启
      await BackupFlagStore.setEnabled(true);

      expect(await vault.isBackupEnabled(), isTrue,
          reason: '迁移映射旧本地开关');
      // 回填后 vault 文档带上了 enabled 字段
      final doc = await vault.exportVaultDoc();
      expect(doc['enabled'], isTrue);

      // 关闭后 vault 字段优先（不再读旧 store）
      await BackupFlagStore.setEnabled(true);
      await vault.setBackupEnabled(false);
      expect(await vault.isBackupEnabled(), isFalse);
    });
  });

  group('6.7：importVaultDoc LWW 与归属校验', () {
    test('云端同版/低版拒收，高版接受', () async {
      await loginAs('user-1');
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('my-password-123');
      final raw = (await store.read(await vault.vaultKeyForTesting))!;
      final base = jsonDecode(raw) as Map<String, dynamic>;
      final localVer = base['syncVersion'] as int;

      // 高版接受
      final higher = Map<String, dynamic>.of(base)
        ..['syncVersion'] = localVer + 5;
      expect(await vault.importVaultDoc(higher), isTrue);

      // 同版拒收（幂等）
      expect(await vault.importVaultDoc(higher), isFalse);
      // 低版拒收
      final lower = Map<String, dynamic>.of(base)..['syncVersion'] = 1;
      expect(await vault.importVaultDoc(lower), isFalse);
    });

    test('跨账号 vault 与结构残缺拒收', () async {
      await loginAs('user-2');
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('my-password-123');
      expect(await vault.importVaultDoc(<String, dynamic>{
        'version': 1,
        'userId': 'user-1',
        'publicKey': 'AAAA',
        'passwordWrap': <String, dynamic>{},
        'syncVersion': 99,
      }), isFalse, reason: '他人 userId 拒收');

      expect(
          await vault.importVaultDoc(
              <String, dynamic>{'syncVersion': 100, 'userId': 'user-2'}),
          isFalse, reason: '缺公钥/口令包裹份拒收');
    });
  });

  group('6.7：SyncIngest vault 记录特判', () {
    test('dataKey 解不开的 vault 记录走传输密钥导入；普通记录失败仍抛',
        () async {
      await loginAs('user-1');
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      await vault.setup('my-password-123');
      final doc = await vault.exportVaultDoc();

      // 用 vault 传输密钥构造云端 vault 记录（与 pushVault 同构）
      final transportKey = KeyVault.vaultTransportKey('user-1');
      final row = SyncPendingRow(
        recordType: VaultSyncService.kRecordType,
        id: VaultSyncService.vaultRecordId('user-1'),
        // 云端版本高于本地（本地 setup 后未再变更）：模拟他处推送的更新
        version: (doc['syncVersion'] as int) + 1,
        updatedAt: DateTime(2026, 10, 24),
        deleted: false,
        familyId: 'f1',
        payload: <String, dynamic>{
          ...doc,
          'recordType': VaultSyncService.kRecordType,
          // vault 文档内部的 LWW 版本也要高于本地（importVaultDoc
          // 比较的是文档 syncVersion，非记录机制 version 字段）
          'syncVersion': (doc['syncVersion'] as int) + 1,
        },
      );
      final vaultRecord = await SyncOutbox.encryptRecord(transportKey, row);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ingest =
          SyncIngest(db, vault: vault, userId: () async => 'user-1');
      final dataKey =
          Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));

      // 业务密钥解不开 → vault 前缀特判 → 传输密钥导入成功
      expect(await ingest.applyRecord(dataKey, vaultRecord),
          IngestResult.updated);
      // 已同版 → 幂等 skipped
      expect(await ingest.applyRecord(dataKey, vaultRecord),
          IngestResult.skipped);
      // 非 vault/fkey 前缀记录解不开 → 8.4 语义：其他成员未重密封的
      // 旧密文按不可读跳过（游标照常推进，不再中断家庭通道拉取）
      final foreign = Map<String, dynamic>.of(vaultRecord)
        ..['id'] = 'tx-foreign';
      expect(await ingest.applyRecord(dataKey, foreign),
          IngestResult.skipped);
    });
  });

  group('6.9：自动解锁份与云端恢复链集成', () {
    test('不卸载重启：restoreFromCloud 已配置分支自动解锁，免口令', () async {
      await loginAs('user-1');
      final store = InMemoryVaultStore();
      final vault = newVault(store);
      final setupResult = await vault.setup('my-password-123');
      await vault.setBackupEnabled(true);
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vault,
          currentFamilyId: () async => 'f1');

      // 重启模拟：已配置（不卸载），restoreFromCloud 内部 autoUnlock
      final fresh = newVault(store);
      expect(fresh.isUnlocked, isFalse);
      final restored = await VaultSyncService.restoreFromCloud(
          port: FakeServerPullPort(server),
          vault: fresh,
          userId: 'user-1',
          familyId: 'f1');
      expect(restored, isFalse, reason: '已配置不走云端导入');
      expect(fresh.isUnlocked, isTrue, reason: '自动解锁份恢复解锁态，免口令');
      final pub = await fresh.unlockedKeyPair!.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));
    });

    test('重装首启：探测导入保持锁定（等口令），口令解锁后下次启动自动',
        () async {
      await loginAs('user-1');
      final storeA = InMemoryVaultStore();
      final vaultA = newVault(storeA);
      final setupResult = await vaultA.setup('my-password-123');
      await vaultA.setBackupEnabled(true);
      await VaultSyncService.pushVault(
          port: _ServerPushPort(server),
          vault: vaultA,
          currentFamilyId: () async => 'f1');

      // B 设备重装：全新 store（自动解锁份随卸载销毁），探测导入
      final storeB = InMemoryVaultStore();
      final vaultB = newVault(storeB);
      final restored = await VaultSyncService.restoreFromCloud(
          port: FakeServerPullPort(server),
          vault: vaultB,
          userId: 'user-1',
          familyId: 'f1');
      expect(restored, isTrue);
      expect(vaultB.isUnlocked, isFalse,
          reason: '重装无自动解锁份：保持锁定，由首页弹口令框完成恢复');

      // 首启口令解锁 → 自动解锁份重建 → 下次启动免口令
      await vaultB.unlock('my-password-123');
      final pub = await vaultB.unlockedKeyPair!.extractPublicKey();
      expect(pub.bytes, equals(setupResult.publicKey.bytes));

      final vaultB2 = newVault(storeB);
      await VaultSyncService.restoreFromCloud(
          port: FakeServerPullPort(server),
          vault: vaultB2,
          userId: 'user-1',
          familyId: 'f1');
      expect(vaultB2.isUnlocked, isTrue,
          reason: '口令解锁一次后，后续启动全程免口令');
    });
  });
}

/// FakeSyncServer 的推送端口适配（对齐 ApiSyncPushPort 语义）
class _ServerPushPort implements SyncPushPort {
  _ServerPushPort(this._server);
  final FakeSyncServer _server;

  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    await Future<void>.delayed(Duration.zero);
    return _server.push(familyId, records);
  }
}
