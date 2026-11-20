import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/backup_switch_store.dart';
import 'package:xiji_flutter/data/local/local_family_cache.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/models/family.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/sync/backup_switch_service.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';
import 'package:xiji_flutter/sync/sync_scheduler.dart' show SyncPushPort;

import 'fake_sync_server.dart';

/// family-scoped-backup-switch：bksw 云端漫游记录专项测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = FakeSyncServer();
    await LocalUser.cache(User(
      id: 'user-1',
      nickname: '测试用户',
      phone: '13800000000',
    ));
  });

  group('记录 ID 规格', () {
    test('bksw- 前缀 + 21 字符 + 确定性', () async {
      final id1 =
          await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      final id2 =
          await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      final id3 =
          await BackupSwitchService.backupSwitchRecordId('f2', 'user-1');
      expect(id1.length, lessThanOrEqualTo(36));
      expect(id1.startsWith('bksw-'), isTrue);
      expect(id1, id2, reason: '确定性：两端各自计算一致（幂等依赖）');
      expect(id1, isNot(id3), reason: '不同家庭不同记录');
    });
  });

  group('推送与脏标记', () {
    test('切换后推送：记录规格与 payload 正确，脏清除', () async {
      await BackupSwitchStore.setEnabled('f1', true); // v1
      await BackupSwitchService.pushBackupSwitch(
          familyId: 'f1', port: _ServerPushPort(server));

      final id = await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      final record = server.record(id);
      expect(record, isNotNull, reason: 'bksw 记录已上云');
      expect(record!['familyId'], 'f1');
      expect(record['version'], 1);
      expect((record['deleted'] as num?)?.toInt(), 0);
      // 真实时间戳（非 epoch）：游标增量自然可达
      final updatedAt = record['updatedAt'] as int;
      expect(updatedAt, greaterThan(DateTime(2026, 1, 1).millisecondsSinceEpoch));

      final payload = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey('user-1'), record);
      expect(payload['recordType'], 'bksw');
      expect(payload['familyId'], 'f1');
      expect(payload['userId'], 'user-1');
      expect(payload['enabled'], isTrue);

      expect(await BackupSwitchStore.dirtyFamilyIds(), isEmpty,
          reason: '推送成功清除脏标记');
    });

    test('未切换过（version 0）不推送', () async {
      await BackupSwitchService.pushBackupSwitch(
          familyId: 'f1', port: _ServerPushPort(server));
      expect(server.pull('f1', null, null)['records'], isEmpty);
    });

    test('推送失败脏保留，pushAllDirty 下轮补位重推', () async {
      await BackupSwitchStore.setEnabled('f1', true); // v1
      final failing = _FailingPushPort();
      await BackupSwitchService.pushBackupSwitch(familyId: 'f1', port: failing);
      expect(await BackupSwitchStore.dirtyFamilyIds(), ['f1'],
          reason: '失败后脏标记保留');

      // 补位重推成功：脏清除、云端有记录
      await BackupSwitchService.pushAllDirty(port: _ServerPushPort(server));
      expect(await BackupSwitchStore.dirtyFamilyIds(), isEmpty);
      final id = await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      expect(server.record(id), isNotNull);
    });

    test('多家庭补位互不影响（关闭动作必须上云）', () async {
      await BackupSwitchStore.setEnabled('f1', true); // v1
      await BackupSwitchStore.setEnabled('f2', false); // v1
      await BackupSwitchService.pushAllDirty(port: _ServerPushPort(server));

      final id1 = await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      final id2 = await BackupSwitchService.backupSwitchRecordId('f2', 'user-1');
      final r1 = server.record(id1)!;
      final r2 = server.record(id2)!;
      expect(r1['familyId'], 'f1');
      expect(r2['familyId'], 'f2', reason: '各走各的家庭通道');
      expect(
          (await SyncOutbox.decryptRecord(
              KeyVault.vaultTransportKey('user-1'), r1))['enabled'],
          isTrue);
      expect(
          (await SyncOutbox.decryptRecord(
              KeyVault.vaultTransportKey('user-1'), r2))['enabled'],
          isFalse,
          reason: '关闭状态同样漫游上云');
      expect(await BackupSwitchStore.dirtyFamilyIds(), isEmpty);
    });

    test('同 version 重推：updated_at 更新被 LWW 接受（幂等）', () async {
      await BackupSwitchStore.setEnabled('f1', true); // v1
      await BackupSwitchService.pushBackupSwitch(
          familyId: 'f1', port: _ServerPushPort(server));
      // 人为再置脏重推（同 version）
      await BackupSwitchStore.setEnabled('f1', true); // v2
      await BackupSwitchService.pushBackupSwitch(
          familyId: 'f1', port: _ServerPushPort(server));
      final id = await BackupSwitchService.backupSwitchRecordId('f1', 'user-1');
      expect(server.record(id)!['version'], 2);
    });
  });

  group('多设备漫游（ingest 仲裁）', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
    });

    /// 以 [userId] 身份推送「关闭」状态的开关记录（v2）并返回云端密文
    Future<Map<String, dynamic>> pushedSwitchRecord(
        String familyId, String userId) async {
      await LocalUser.cache(User(
          id: userId, nickname: 'u', phone: '13800000000'));
      await BackupSwitchStore.setEnabled(familyId, true); // v1
      await BackupSwitchStore.setEnabled(familyId, false); // v2 关
      await BackupSwitchService.pushBackupSwitch(
          familyId: familyId, port: _ServerPushPort(server));
      final id =
          await BackupSwitchService.backupSwitchRecordId(familyId, userId);
      return server.record(id)!;
    }

    test('设备甲关闭上云 → 设备乙拉取仲裁写入本地开关', () async {
      final record = await pushedSwitchRecord('f1', 'user-1');
      // 设备乙视角：重置本地，登录同账号，本地为旧态（v1 开启）
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalUser.cache(User(
          id: 'user-1', nickname: 'u', phone: '13800000000'));
      await BackupSwitchStore.setEnabled('f1', true); // v1 开

      final ingest = SyncIngest(db, userId: () async => 'user-1');
      final result = await ingest.applyRecord(_dummyKey(), record);
      expect(result, IngestResult.updated);
      expect(await BackupSwitchStore.isEnabled('f1'), isFalse,
          reason: '设备乙开关同步为关（关闭动作跨设备漫游）');
    });

    test('本地更高版本：云端旧记录忽略（LWW）', () async {
      final record = await pushedSwitchRecord('f1', 'user-1');
      // 设备乙：本地 v9 开启
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalUser.cache(User(
          id: 'user-1', nickname: 'u', phone: '13800000000'));
      for (var i = 0; i < 9; i++) {
        await BackupSwitchStore.setEnabled('f1', true);
      }

      final ingest = SyncIngest(db, userId: () async => 'user-1');
      final result = await ingest.applyRecord(_dummyKey(), record);
      expect(result, IngestResult.skipped);
      expect(await BackupSwitchStore.isEnabled('f1'), isTrue);
      expect(await BackupSwitchStore.getVersion('f1'), 9);
    });

    test('他人开关记录拒收（传输密钥不匹配）', () async {
      final record = await pushedSwitchRecord('f1', 'user-2');
      final ingest = SyncIngest(db, userId: () async => 'user-1');
      final result = await ingest.applyRecord(_dummyKey(), record);
      expect(result, IngestResult.skipped);
      expect(await BackupSwitchStore.isEnabled('f1'), isFalse);
    });

    test('applyPage 页级路径同样处理 bksw 记录', () async {
      final record = await pushedSwitchRecord('f1', 'user-1');
      // 设备乙：空本地（version 0）
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalUser.cache(User(
          id: 'user-1', nickname: 'u', phone: '13800000000'));

      final ingest = SyncIngest(db, userId: () async => 'user-1');
      final page = await ingest.applyPage(_dummyKey(), [record]);
      expect(page.applied, 1, reason: '页级路径写入开关');
      expect(await BackupSwitchStore.isEnabled('f1'), isFalse);
    });
  });

  group('存量迁移（vault.enabled → 家庭开关）', () {
    test('老开关开启：铺到全部家庭并各推 bksw', () async {
      final vault = KeyVault(InMemoryVaultStore(),
          profile: Argon2Profile.fast());
      await vault.setup('pw123456');
      await vault.injectLegacyBackupFlag(true);

      await LocalFamilyCache.cache([
        Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
        Family(id: 'f2', name: '家庭二', isCurrent: false, role: 2),
      ]);

      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));

      expect(await BackupSwitchStore.isEnabled('f1'), isTrue);
      expect(await BackupSwitchStore.isEnabled('f2'), isTrue);
      // 各推一条 bksw 上云
      expect(
          server.record(await BackupSwitchService.backupSwitchRecordId(
              'f1', 'user-1')),
          isNotNull);
      expect(
          server.record(await BackupSwitchService.backupSwitchRecordId(
              'f2', 'user-1')),
          isNotNull);
      // 迁移标记已落
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('backup_flag_migrated@user-1'), isTrue);
    });

    test('老开关关闭：不铺任何家庭，标记直接落', () async {
      final vault = KeyVault(InMemoryVaultStore(),
          profile: Argon2Profile.fast());
      await vault.setup('pw123456');
      await vault.injectLegacyBackupFlag(false);
      await LocalFamilyCache.cache([
        Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
      ]);

      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));

      expect(await BackupSwitchStore.isEnabled('f1'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('backup_flag_migrated@user-1'), isTrue);
    });

    test('重复执行幂等：不重复推记录、不覆盖手动新状态', () async {
      final vault = KeyVault(InMemoryVaultStore(),
          profile: Argon2Profile.fast());
      await vault.setup('pw123456');
      await vault.injectLegacyBackupFlag(true);
      await LocalFamilyCache.cache([
        Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
      ]);
      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));

      // 用户升级后手动关闭 f1（产生新 version）
      await BackupSwitchStore.setEnabled('f1', false);
      // 再次触发迁移（标记已落）——不执行
      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));
      expect(await BackupSwitchStore.isEnabled('f1'), isFalse,
          reason: '手动切换不被迁移覆盖');
    });

    test('家庭缓存未就绪：不落标记，下轮重试', () async {
      final vault = KeyVault(InMemoryVaultStore(),
          profile: Argon2Profile.fast());
      await vault.setup('pw123456');
      await vault.injectLegacyBackupFlag(true);
      // 不写家庭缓存（LocalFamilyCache.load 返回 null）

      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('backup_flag_migrated@user-1'), isNull,
          reason: '缓存未就绪不落标记，下轮重试');
      expect(await BackupSwitchStore.dirtyFamilyIds(), isEmpty);

      // 缓存就绪后重试成功
      await LocalFamilyCache.cache([
        Family(id: 'f1', name: '家庭一', isCurrent: true, role: 1),
      ]);
      await BackupSwitchService.migrateLegacySwitch(
          vault: vault, port: _ServerPushPort(server));
      expect(await BackupSwitchStore.isEnabled('f1'), isTrue);
      expect(prefs.getBool('backup_flag_migrated@user-1'), isTrue);
    });
  });
}

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

class _FailingPushPort implements SyncPushPort {
  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    throw Exception('Connection error');
  }
}

/// 占位个人密钥：业务键解不开 bksw 机制记录，触发传输密钥特判分支
Uint8List _dummyKey() =>
    Uint8List.fromList(List<int>.filled(32, 7));
