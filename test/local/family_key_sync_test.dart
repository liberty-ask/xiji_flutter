import 'dart:convert';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/crypto_primitives.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/member_public_key_store.dart';
import 'package:xiji_flutter/models/family_member.dart';
import 'package:xiji_flutter/sync/family_key_service.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';
import 'package:xiji_flutter/sync/sync_puller.dart';
import 'package:xiji_flutter/sync/sync_scheduler.dart';
import 'package:xiji_flutter/sync/vault_sync_service.dart';

import 'fake_sync_server.dart';

/// 任务 8.4：家庭密钥包裹分发专项测试（design.md D13）。
///
/// 覆盖密封盒原语、admin 生成分发、幂等补发、ingest 消化
/// （他人 vaultDoc 公钥登记 / 本人 fkey 解 F）、双设备首拉
/// 中途拿 F 同页解业务密文、个人 key 回落、存量重密封、无 F 推送门控。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

  KeyVault newVault() =>
      KeyVault(InMemoryVaultStore(), profile: Argon2Profile.fast());

  Future<void> loginAs(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalUser.profileKey,
        jsonEncode({'id': id, 'nickname': 'u-$id', 'phone': '13800000000'}));
  }

  Future<String> pubBase64Of(KeyVault vault) async {
    final pub = await vault.unlockedKeyPair!.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // MemberPublicKeyStore 是进程内静态缓存：逐测试重置防串扰
    await MemberPublicKeyStore.setForTesting(<String, String>{});
  });

  group('8.4a：密封盒原语与密钥派生', () {
    test('包裹 → 解包出同一 F；错私钥解包抛认证错误', () async {
      final f = KeyVault.generateFamilyKey();
      final recipient = await CryptoPrimitives.generateX25519KeyPair();
      final other = await CryptoPrimitives.generateX25519KeyPair();

      final sealed = await KeyVault.sealFamilyKeyFor(
        familyKey: f,
        recipientPublicKey: await recipient.extractPublicKey(),
      );
      final opened = await CryptoPrimitives.openSealedFamilyKey(
        ephemeralPubKeyBase64: sealed.ephemeralPubKey,
        wrappedFBase64: sealed.wrappedF,
        ourKeyPair: recipient,
      );
      expect(opened, equals(f));

      await expectLater(
        CryptoPrimitives.openSealedFamilyKey(
          ephemeralPubKeyBase64: sealed.ephemeralPubKey,
          wrappedFBase64: sealed.wrappedF,
          ourKeyPair: other,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
        reason: '非目标私钥解密封盒必须认证失败（F 机密性所在）',
      );
    });

    test('家庭 dataKey 派生：确定性、与个人 dataKey 域分离、无 F 为空',
        () async {
      await loginAs('user-1');
      final vault = newVault();
      await vault.setup('pw123456');
      final f = KeyVault.generateFamilyKey();
      await vault.putFamilyKey('f1', f);

      expect(await vault.familyDataKey('f1'),
          equals(await vault.familyDataKey('f1')),
          reason: '同 F 派生结果确定');
      expect(await vault.familyDataKey('f1'),
          isNot(equals(await vault.personalDataKey())),
          reason: '家庭/个人密钥域分离');
      expect(await vault.getFamilyKey('f2'), isNull,
          reason: '未分发 F 的家庭返回 null');
      expect(await vault.familyDataKey('f2'), isNull);
    });
  });

  group('8.4c：FamilyKeyService 分发', () {
    test('admin 首次：生成 F 并为全员（含自己）密封盒分发', () async {
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        'user-2': await pubBase64Of(vaultB),
      });
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);

      await FamilyKeyService.ensureDistributed(
        members: const [
          (id: 'user-1', role: FamilyMemberRole.admin),
          (id: 'user-2', role: FamilyMemberRole.member),
        ],
        vault: vaultA,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );

      final f = await vaultA.getFamilyKey('f1');
      expect(f, isNotNull, reason: 'admin 本机生成并保存 F');

      final pushedIds = pushPort.calls
          .expand((c) => c.records.map((r) => r['id'] as String))
          .toSet();
      expect(pushedIds, {'fkey-f1-user-1', 'fkey-f1-user-2'},
          reason: '每人一条包裹记录，含 admin 自己（换设备可恢复）');

      // B 的包裹份：B 传输密钥可解 payload，B 私钥可解密封盒得同一 F
      final recB = server.record('fkey-f1-user-2')!;
      final payloadB = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey('user-2'), recB);
      expect(payloadB['recordType'], FamilyKeyService.kRecordType);
      expect(payloadB['forUserId'], 'user-2');
      final fB = await vaultB.openFamilyKeyWrap(
        ephemeralPubKeyBase64: payloadB['ephemeralPubKey'] as String,
        wrappedFBase64: payloadB['wrappedF'] as String,
      );
      expect(fB, equals(f), reason: 'B 解密封盒得到同一把 F');

      // A 自己的包裹份用 A 私钥可解（换设备恢复路径）
      final recA = server.record('fkey-f1-user-1')!;
      final payloadA = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey('user-1'), recA);
      final fA = await vaultA.openFamilyKeyWrap(
        ephemeralPubKeyBase64: payloadA['ephemeralPubKey'] as String,
        wrappedFBase64: payloadA['wrappedF'] as String,
      );
      expect(fA, equals(f));
    });

    test('普通成员无 F 不生成：静默等待 admin 分发', () async {
      await loginAs('user-2');
      final vault = newVault();
      await vault.setup('pw123456');
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);

      await FamilyKeyService.ensureDistributed(
        members: const [
          (id: 'user-1', role: FamilyMemberRole.admin),
          (id: 'user-2', role: FamilyMemberRole.member),
        ],
        vault: vault,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      expect(await vault.getFamilyKey('f1'), isNull,
          reason: '生成权唯一给 admin，防多把 F 并存互解不通');
      expect(pushPort.calls, isEmpty);
    });

    test('幂等：云端已有包裹份不重复推送', () async {
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        'user-2': await pubBase64Of(vaultB),
      });
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);
      final members = const [
        (id: 'user-1', role: FamilyMemberRole.admin),
        (id: 'user-2', role: FamilyMemberRole.member),
      ];
      final distribute = () => FamilyKeyService.ensureDistributed(
            members: members,
            vault: vaultA,
            pushPort: pushPort,
            pullPort: FakeServerPullPort(server),
            currentFamilyId: () async => 'f1',
          );

      await distribute();
      expect(pushPort.calls, isNotEmpty);
      pushPort.calls.clear();

      // 第二轮：recordId 精确探测均已存在，不重推
      await distribute();
      expect(pushPort.calls, isEmpty);
    });

    test('成员公钥未到达：本轮跳过，登记后下轮补包裹', () async {
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        // user-2 公钥未登记（vaultDoc 未同步到达）
      });
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);
      final members = const [
        (id: 'user-1', role: FamilyMemberRole.admin),
        (id: 'user-2', role: FamilyMemberRole.member),
      ];
      final distribute = () => FamilyKeyService.ensureDistributed(
            members: members,
            vault: vaultA,
            pushPort: pushPort,
            pullPort: FakeServerPullPort(server),
            currentFamilyId: () async => 'f1',
          );

      await distribute();
      final ids1 = pushPort.calls
          .expand((c) => c.records.map((r) => r['id'] as String))
          .toSet();
      expect(ids1, {'fkey-f1-user-1'}, reason: '缺公钥成员本轮跳过');
      pushPort.calls.clear();

      // 公钥到达（模拟其 vaultDoc 拉取登记）后下轮补包裹
      await MemberPublicKeyStore.register('user-2', await pubBase64Of(vaultB));
      await distribute();
      final ids2 = pushPort.calls
          .expand((c) => c.records.map((r) => r['id'] as String))
          .toSet();
      expect(ids2, {'fkey-f1-user-2'});
    });

    test('锁定期不分发：静默跳过', () async {
      await loginAs('user-1');
      final vault = newVault();
      await vault.setup('pw123456');
      vault.lock();
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);

      await FamilyKeyService.ensureDistributed(
        members: const [(id: 'user-1', role: FamilyMemberRole.admin)],
        vault: vault,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      expect(await vault.getFamilyKey('f1'), isNull);
      expect(pushPort.calls, isEmpty);
    });
  });

  group('8.4d：SyncIngest 消化 vaultDoc / fkey', () {
    test('他人 vaultDoc：公钥登记供包裹分发，文档本身拒收导入', () async {
      // 其他成员 user-2 的 vault（文档归属 user-2）
      await loginAs('user-2');
      final vaultOther = newVault();
      await vaultOther.setup('pw123456');
      final doc = await vaultOther.exportVaultDoc();

      // 拉取方 user-1
      await loginAs('user-1');
      final vaultMe = newVault();
      await vaultMe.setup('pw123456');
      final row = SyncPendingRow(
        recordType: VaultSyncService.kRecordType,
        id: VaultSyncService.vaultRecordId('user-2'),
        version: 99,
        updatedAt: DateTime(2026, 10, 24),
        deleted: false,
        familyId: 'f1',
        payload: <String, dynamic>{
          ...doc,
          'recordType': VaultSyncService.kRecordType,
          'syncVersion': (doc['syncVersion'] as int) + 1,
        },
      );
      // 其传输密钥（按文档归属者 user-2 派生）加密
      final record = await SyncOutbox.encryptRecord(
          KeyVault.vaultTransportKey('user-2'), row);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ingest =
          SyncIngest(db, vault: vaultMe, userId: () async => 'user-1');

      final result = await ingest.applyRecord(
          await vaultMe.personalDataKey(), record);
      expect(result, IngestResult.skipped, reason: '他人 vaultDoc 拒收导入');
      expect(await MemberPublicKeyStore.get('user-2'),
          await pubBase64Of(vaultOther),
          reason: '公钥已登记，是 F 包裹分发的必需输入');
    });

    test('fkey 记录：他人包裹份跳过不中断；本人包裹份解出 F 落库', () async {
      await loginAs('user-2');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      final f = KeyVault.generateFamilyKey();

      // 本人包裹份：admin 用 B 公钥密封
      final sealedForB = await KeyVault.sealFamilyKeyFor(
        familyKey: f,
        recipientPublicKey: await vaultB.unlockedKeyPair!.extractPublicKey(),
      );
      final myRow = SyncPendingRow(
        recordType: FamilyKeyService.kRecordType,
        id: FamilyKeyService.familyKeyRecordId('f1', 'user-2'),
        version: 1,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
        deleted: false,
        familyId: 'f1',
        payload: <String, dynamic>{
          'recordType': FamilyKeyService.kRecordType,
          'familyId': 'f1',
          'forUserId': 'user-2',
          'ephemeralPubKey': sealedForB.ephemeralPubKey,
          'wrappedF': sealedForB.wrappedF,
        },
      );
      final myRecord = await SyncOutbox.encryptRecord(
          KeyVault.vaultTransportKey('user-2'), myRow);

      // 他人包裹份（user-1 传输密钥加密，B 解不开是预期）
      final foreignRow = SyncPendingRow(
        recordType: FamilyKeyService.kRecordType,
        id: FamilyKeyService.familyKeyRecordId('f1', 'user-1'),
        version: 1,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
        deleted: false,
        familyId: 'f1',
        payload: <String, dynamic>{
          'recordType': FamilyKeyService.kRecordType,
          'familyId': 'f1',
          'forUserId': 'user-1',
          'ephemeralPubKey': 'AAAA',
          'wrappedF': 'BBBB',
        },
      );
      final foreignRecord = await SyncOutbox.encryptRecord(
          KeyVault.vaultTransportKey('user-1'), foreignRow);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ingest =
          SyncIngest(db, vault: vaultB, userId: () async => 'user-2');
      final personal = await vaultB.personalDataKey();

      // 他人包裹份在前也不中断：静默跳过（密封盒保证 F 机密性）
      expect(await ingest.applyRecord(personal, foreignRecord),
          IngestResult.skipped);
      expect(await vaultB.getFamilyKey('f1'), isNull);

      // 本人包裹份：解密封盒得 F 落库
      expect(
          await ingest.applyRecord(personal, myRecord), IngestResult.updated);
      expect(await vaultB.getFamilyKey('f1'), equals(f));

      // 幂等：重复消化同一包裹份仍是同一 F
      expect(
          await ingest.applyRecord(personal, myRecord), IngestResult.updated);
      expect(await vaultB.getFamilyKey('f1'), equals(f));
    });
  });

  group('8.4：双设备端到端闭环', () {
    test('A 分发并推家庭密文 → B 首次拉取同轮解出 F 并入库业务数据',
        () async {
      // ── 设备 A（user-1，admin）──
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        'user-2': await pubBase64Of(vaultB),
      });
      final server = FakeSyncServer(pageSize: 10);
      final pushPort = _RecordingPushPort(server);

      // A 生成 F 并全员分发
      await FamilyKeyService.ensureDistributed(
        members: const [
          (id: 'user-1', role: FamilyMemberRole.admin),
          (id: 'user-2', role: FamilyMemberRole.member),
        ],
        vault: vaultA,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      final f = await vaultA.getFamilyKey('f1');

      // A 写业务数据，家庭 key 加密上云
      final dbA = AppDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      await dbA.into(dbA.transactions).insertReturning(
          TransactionsCompanion.insert(
        id: const Value('tx-1'),
        type: 1,
        categoryId: diningId,
        amountCents: 3000,
        date: DateTime(2026, 10, 1),
        userId: 'user-1',
        familyId: const Value('f1'),
        description: const Value('午餐'),
      ));
      final familyKeyA = await vaultA.familyDataKey('f1');
      for (final row in await SyncOutbox.collectAll(dbA, 'f1')) {
        server.push('f1', [await SyncOutbox.encryptRecord(familyKeyA!, row)]);
      }

      // ── 设备 B（user-2，后加入成员）：本机无 F 首次拉取 ──
      await loginAs('user-2');
      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbB.close);
      final pullerB = SyncPuller(
          db: dbB,
          port: FakeServerPullPort(server),
          currentFamilyId: () async => 'f1',
          vault: vaultB);
      await pullerB.pullAll(await vaultB.personalDataKey(),
          familyDataKeyProvider: () => vaultB.familyDataKey('f1'));

      // fkey（epoch 时间戳排序恒最前）中途送达 F，同页后续业务密文
      // 立即可解——否则游标越过后该批家庭密文永久错过
      expect(await vaultB.getFamilyKey('f1'), equals(f));
      final txs = await dbB.select(dbB.transactions).get();
      expect(txs, hasLength(1), reason: '家庭密文首拉即入库，无跨轮丢失');
      expect(txs.first.amountCents, 3000);
      expect(txs.first.description, '午餐');
      expect(txs.first.syncPending, false, reason: '云端权威数据无需回推');
    });

    test('解密键序：家庭 key 解不开的存量个人密文回落个人 key 入库',
        () async {
      await loginAs('user-1');
      final vault = newVault();
      await vault.setup('pw123456');
      final personal = await vault.personalDataKey();
      final server = FakeSyncServer();

      // 存量个人密文（二期老数据，家庭 key 出现前推的）
      server.push('f1', [
        await SyncOutbox.encryptRecord(personal, _cloudTx('tx-old'))
      ]);
      // 本机已有一把与该密文无关的 F（如刚生成未重推完）
      await vault.putFamilyKey('f1', KeyVault.generateFamilyKey());

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final puller = SyncPuller(
          db: db,
          port: FakeServerPullPort(server),
          currentFamilyId: () async => 'f1',
          vault: vault);
      await puller.pullAll(personal,
          familyDataKeyProvider: () => vault.familyDataKey('f1'));

      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(1), reason: '家庭 key 失败后回落个人 key 解开');
      expect(txs.first.id, 'tx-old');
    });
  });

  group('8.4e：存量重密封与推送门控（调度器集成）', () {
    test('首次同步：存量已上云密文重标并以家庭 key 重推，幂等不重复',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'backup_enabled': true,
      });
      await loginAs('user-1');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final port = _FakePushPort();
      final vault = newVault();
      await vault.setup('pw123456');
      await vault.putFamilyKey('f1', KeyVault.generateFamilyKey());

      // 存量行：已推送状态（syncPending=false）、老 updated_at
      await db.into(db.transactions).insertReturning(
          TransactionsCompanion.insert(
        id: const Value('tx-old'),
        type: 1,
        categoryId: diningId,
        amountCents: 3000,
        date: DateTime(2026, 10, 1),
        userId: 'user-1',
        familyId: const Value('f1'),
        description: const Value('早餐'),
        version: const Value(1),
        updatedAt: Value(DateTime(2026, 10, 1)),
        syncPending: const Value(false),
      ));
      final scheduler = SyncScheduler(
        db: db,
        port: port,
        pullPort: _NoopPullPort(),
        vault: vault,
        isSignedIn: () async => true,
        currentFamilyId: () async => 'f1',
        membersProvider: () async => const [],
      );

      await scheduler.maybePush();

      // 存量行被重标并以家庭 key 重推（LWW 同 version 时间新者胜覆盖云端）
      expect(port.totalRecords, 1);
      final record = port.calls.first.records.single;
      expect(record['id'], 'tx-old');
      final familyKey = await vault.familyDataKey('f1');
      final payload =
          await SyncOutbox.decryptRecord(familyKey!, record);
      expect(payload['amountCents'], 3000, reason: '重推密文已换家庭 key');

      final row = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx-old')))
          .getSingle();
      expect(row.syncPending, false, reason: '推净后标记清理');
      expect(row.updatedAt.isAfter(DateTime(2026, 10, 2)), isTrue,
          reason: '重标刷新 updated_at 覆盖云端旧密文');

      // 重密封标记幂等：无新变更不再推送
      port.calls.clear();
      await scheduler.maybePush();
      expect(port.calls, isEmpty);
    });

    test('无 F：业务推送跳过标记保留，不产生任何请求', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'backup_enabled': true,
      });
      await loginAs('user-1');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final port = _FakePushPort();
      final vault = newVault();
      await vault.setup('pw123456');
      // 不预置 F：模拟成员尚未收到 admin 分发

      await db.into(db.transactions).insertReturning(
          TransactionsCompanion.insert(
        id: const Value('tx-1'),
        type: 1,
        categoryId: diningId,
        amountCents: 3000,
        date: DateTime(2026, 10, 1),
        userId: 'user-1',
        familyId: const Value('f1'),
      ));
      final scheduler = SyncScheduler(
        db: db,
        port: port,
        pullPort: _NoopPullPort(),
        vault: vault,
        isSignedIn: () async => true,
        currentFamilyId: () async => 'f1',
        membersProvider: () async => const [],
      );

      await scheduler.maybePush();

      expect(port.calls, isEmpty, reason: '无 F 跳过业务推送');
      final row = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx-1')))
          .getSingle();
      expect(row.syncPending, true, reason: '标记保留，F 到达后下轮重推');
    });
  });

  group('8.6：家庭互救重置流', () {
    test('忘者重置密钥：seed 后 vault 胜出 → 墓碑废弃旧包裹 → 老成员重包裹 → F 恢复',
        () async {
      // ── 初始态：admin(user-1) 已分发 F 给 user-2（旧公钥）──
      // 注意：vault 存储键按 userId 隔离（账号隔离约束）——各 vault
      // 必须在其归属用户登录态下 setup
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      await loginAs('user-2');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await loginAs('user-1');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        'user-2': await pubBase64Of(vaultB),
      });
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);
      final members = const [
        (id: 'user-1', role: FamilyMemberRole.admin),
        (id: 'user-2', role: FamilyMemberRole.member),
      ];
      await FamilyKeyService.ensureDistributed(
        members: members,
        vault: vaultA,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      // 双方旧 vaultDoc 上云（pushVault 按当前登录用户归属记录 ID）
      await VaultSyncService.pushVault(
          port: pushPort, vault: vaultA, currentFamilyId: () async => 'f1');
      await loginAs('user-2');
      await VaultSyncService.pushVault(
          port: pushPort, vault: vaultB, currentFamilyId: () async => 'f1');
      await loginAs('user-1');
      final oldCloudDoc =
          server.record(VaultSyncService.vaultRecordId('user-2'))!;
      final oldF = await vaultA.getFamilyKey('f1');

      // ── user-2 忘者：口令+恢复码双丢，重置密钥（新密钥对）──
      await loginAs('user-2');
      final vaultB2 = newVault(); // 全新 vault = 新 setup
      await vaultB2.setup('new-password');
      // 拉云端旧 vaultDoc 读 syncVersion → seed 抬高本地
      final oldDoc = await VaultSyncService.pullVaultDoc(
          port: FakeServerPullPort(server), userId: 'user-2', familyId: 'f1');
      expect(oldDoc, isNotNull, reason: '忘者旧 vaultDoc 必在云端');
      await vaultB2
          .seedSyncVersion((oldDoc!['syncVersion'] as int?) ?? 1);
      // 废弃云端旧包裹（旧公钥份新私钥解不开）
      await FamilyKeyService.requestRewrapAfterReset(
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      // 新公钥 vaultDoc 上云（seed 后 LWW 胜出）
      await VaultSyncService.pushVault(
          port: pushPort, vault: vaultB2, currentFamilyId: () async => 'f1');

      // 忘者自己的 fkey 已变墓碑
      final tombstone = server.record('fkey-f1-user-2')!;
      expect(tombstone['deleted'], 1, reason: '旧包裹已被墓碑废弃');
      expect(
          (server.record(VaultSyncService.vaultRecordId('user-2'))!
                  ['version'] as int) >
              (oldCloudDoc['version'] as int),
          isTrue,
          reason: 'seed 后新 vault 覆盖云端旧版');

      // ── 老成员 user-1：拉到新 vaultDoc（公钥更新）→ 探测墓碑重包裹 ──
      await loginAs('user-1');
      final newDoc = await VaultSyncService.pullVaultDoc(
          port: FakeServerPullPort(server), userId: 'user-2', familyId: 'f1');
      expect(newDoc, isNotNull);
      expect(newDoc!['publicKey'], await pubBase64Of(vaultB2),
          reason: 'seed 后新 vaultDoc 已在云端');
      await MemberPublicKeyStore.register(
          'user-2', newDoc['publicKey'] as String);
      pushPort.calls.clear();
      await FamilyKeyService.ensureDistributed(
        members: members,
        vault: vaultA,
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      final rewrapped = server.record('fkey-f1-user-2')!;
      expect(rewrapped['deleted'], 0, reason: '墓碑被重包裹覆盖');
      expect(rewrapped['version'] as int,
          greaterThanOrEqualTo((tombstone['version'] as int) + 1),
          reason: '重包裹 version 严格高于墓碑');

      // ── 忘者拉取：解出重包裹份恢复 F ──
      await loginAs('user-2');
      final rewrappedPayload = await SyncOutbox.decryptRecord(
          KeyVault.vaultTransportKey('user-2'), rewrapped);
      final recoveredF = await vaultB2.openFamilyKeyWrap(
        ephemeralPubKeyBase64: rewrappedPayload['ephemeralPubKey'] as String,
        wrappedFBase64: rewrappedPayload['wrappedF'] as String,
      );
      expect(recoveredF, equals(oldF), reason: '互救闭环：F 恢复如初');
    });

    test('重包裹幂等：老成员下轮探测正常记录不再重推', () async {
      await loginAs('user-1');
      final vaultA = newVault();
      await vaultA.setup('pw123456');
      final vaultB = newVault();
      await vaultB.setup('pw123456');
      await MemberPublicKeyStore.setForTesting(<String, String>{
        'user-1': await pubBase64Of(vaultA),
        'user-2': await pubBase64Of(vaultB),
      });
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);
      final members = const [
        (id: 'user-1', role: FamilyMemberRole.admin),
        (id: 'user-2', role: FamilyMemberRole.member),
      ];
      final distribute = () => FamilyKeyService.ensureDistributed(
            members: members,
            vault: vaultA,
            pushPort: pushPort,
            pullPort: FakeServerPullPort(server),
            currentFamilyId: () async => 'f1',
          );
      await distribute();
      pushPort.calls.clear();
      // 二轮：全员正常记录 → 零推送
      await distribute();
      expect(pushPort.calls, isEmpty);
    });

    test('requestRewrapAfterReset：云端无包裹记录时 no-op', () async {
      await loginAs('user-2');
      final server = FakeSyncServer();
      final pushPort = _RecordingPushPort(server);
      await FamilyKeyService.requestRewrapAfterReset(
        pushPort: pushPort,
        pullPort: FakeServerPullPort(server),
        currentFamilyId: () async => 'f1',
      );
      expect(pushPort.calls, isEmpty, reason: '从未分发 → 无需墓碑');
    });
  });
}

/// 构造云端交易记录（明文载荷 → 加密由调用方执行）
SyncPendingRow _cloudTx(String id, {DateTime? updatedAt}) {
  return SyncPendingRow(
    recordType: 'transaction',
    id: id,
    version: 1,
    updatedAt: updatedAt ?? DateTime(2026, 10, 1),
    deleted: false,
    familyId: 'f1',
    payload: <String, dynamic>{
      'recordType': 'transaction',
      'type': 1,
      'categoryId': '01a15d13-bded-710c-a3bd-aba94a5aeb36',
      'amountCents': 1000,
      'dateMs': DateTime(2026, 10, 1).millisecondsSinceEpoch,
      'userId': 'user-1',
      'familyId': 'f1',
      'description': 'x',
      'counterparty': null,
      'tradeNo': null,
      'merchantOrderNo': null,
      'payMethod': null,
      'platform': null,
    },
  );
}

/// 推送端口：记录调用并转发 FakeSyncServer
class _RecordingPushPort implements SyncPushPort {
  _RecordingPushPort(this._server);
  final FakeSyncServer _server;
  final List<({String familyId, List<Map<String, dynamic>> records})> calls =
      [];

  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    calls.add((familyId: familyId, records: records));
    return _server.push(familyId, records);
  }
}

/// 本地假推送端口（不接服务端，全量回执成功）
class _FakePushPort implements SyncPushPort {
  final List<({String familyId, List<Map<String, dynamic>> records})> calls =
      [];

  int get totalRecords =>
      calls.fold(0, (sum, c) => sum + c.records.length);

  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    calls.add((familyId: familyId, records: records));
    return records.map((r) => r['id'] as String).toSet();
  }
}

/// 空拉取端口：服务端无该家庭记录
class _NoopPullPort implements SyncPullPort {
  @override
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId, {
    String? recordId,
    int? limit,
  }) async =>
      <String, dynamic>{
        'records': <Map<String, dynamic>>[],
        'hasMore': false,
      };
}
