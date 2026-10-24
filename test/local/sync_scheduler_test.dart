import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/crypto/crypto_primitives.dart';
import 'package:xiji_flutter/crypto/key_vault.dart';
import 'package:xiji_flutter/crypto/vault_store.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';
import 'package:xiji_flutter/sync/sync_puller.dart';
import 'package:xiji_flutter/sync/sync_scheduler.dart';

/// 假推送端口：记录每次调用，可注入响应/异常模拟服务端行为
class FakePort implements SyncPushPort {
  final List<({String familyId, List<Map<String, dynamic>> records})> calls =
      [];

  /// null = 默认全部回执成功；否则用注入逻辑决定回执/抛异常
  Future<Set<String>> Function(
      String familyId, List<Map<String, dynamic>> records)? handler;

  @override
  Future<Set<String>> push(
    String familyId,
    List<Map<String, dynamic>> records,
  ) async {
    calls.add((familyId: familyId, records: records));
    if (handler != null) return await handler!(familyId, records);
    return records.map((r) => r['id'] as String).toSet();
  }

  int get totalRecords =>
      calls.fold(0, (sum, c) => sum + c.records.length);
}

/// 空拉取端口（默认页）：服务端无该家庭记录
class NoopPullPort implements SyncPullPort {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakePort port;
  late KeyVault vault;
  late SyncScheduler scheduler;

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

  Future<void> insertTx(String id, {String familyId = 'f1'}) async {
    await db.into(db.transactions).insertReturning(
        TransactionsCompanion.insert(
      id: Value(id),
      type: 1,
      categoryId: diningId,
      amountCents: 3000,
      date: DateTime(2026, 10, 1),
      userId: 'user-1',
      familyId: Value(familyId),
    ));
  }

  Future<int> pendingCount(String table) => db
      .customSelect('SELECT COUNT(*) AS c FROM $table WHERE sync_pending = 1')
      .map((row) => row.read<int>('c'))
      .getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'backup_enabled': true,
    });
    db = AppDatabase(NativeDatabase.memory());
    port = FakePort();
    vault = KeyVault(InMemoryVaultStore(), profile: Argon2Profile.fast());
    await vault.setup('pw123456'); // setup 后即解锁态
    scheduler = SyncScheduler(
      db: db,
      port: port,
      pullPort: NoopPullPort(),
      vault: vault,
      isSignedIn: () async => true,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('任务 7.3：门控（任一不满足静默跳过，标记保留）', () {
    test('备份开关关闭：不推送', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await insertTx('tx-1');
      await scheduler.maybePush();

      expect(port.calls, isEmpty);
      expect(await pendingCount('transactions'), 1);
    });

    test('未登录：不推送', () async {
      final lockedScheduler = SyncScheduler(
        db: db,
        port: port,
        pullPort: NoopPullPort(),
        vault: vault,
        isSignedIn: () async => false,
      );
      await insertTx('tx-1');
      await lockedScheduler.maybePush();

      expect(port.calls, isEmpty);
    });

    test('密钥未解锁：不推送；解锁后触发即补推', () async {
      vault.lock();
      await insertTx('tx-1');
      await scheduler.maybePush();
      expect(port.calls, isEmpty);

      await vault.unlock('pw123456');
      await scheduler.maybePush();
      expect(port.totalRecords, 1);
      expect(await pendingCount('transactions'), 0);
    });
  });

  group('任务 7.10：同步轮完成事件（停留页刷新）', () {
    test('同步成功后触发一次完成事件', () async {
      var fired = 0;
      final sub = scheduler.onRoundCompleted.listen((_) => fired++);

      await insertTx('tx-1');
      await scheduler.maybePush();
      // broadcast 流事件分发为微任务：pumpEventQueue 排空后再断言
      await pumpEventQueue();

      expect(fired, 1);
      await sub.cancel();
    });

    test('门控跳过（密钥锁定）不触发完成事件', () async {
      vault.lock();
      var fired = 0;
      final sub = scheduler.onRoundCompleted.listen((_) => fired++);

      await insertTx('tx-1');
      await scheduler.maybePush();
      await pumpEventQueue();
      expect(port.calls, isEmpty);
      expect(fired, 0);

      await sub.cancel();
    });

    test('推送网络失败不触发完成事件（标记保留待重试）', () async {
      port.handler = (familyId, records) => throw Exception('网络不可达');
      var fired = 0;
      final sub = scheduler.onRoundCompleted.listen((_) => fired++);

      await insertTx('tx-1');
      // 推送失败由调度器内部消化（fire-and-forget：标记保留待重试）
      await scheduler.maybePush();
      await pumpEventQueue();

      expect(fired, 0);
      expect(await pendingCount('transactions'), 1);
      await sub.cancel();
    });
  });

  group('任务 7.3：推送与标记清理', () {
    test('三表混合收集推送成功全清；无变更不重复推', () async {
      await insertTx('tx-1');
      await insertTx('tx-2');
      await db.into(db.categories).insertReturning(CategoriesCompanion.insert(
        id: const Value('cat-1'),
        name: '自定义分类',
        icon: 'star',
        type: 1,
        familyId: const Value('f1'),
      ));
      await db.into(db.budgets).insertReturning(BudgetsCompanion.insert(
        id: const Value('b-1'),
        familyId: const Value('f1'),
        userId: 'user-1',
        year: 2026,
        month: 10,
        amountCents: 200000,
      ));

      await scheduler.maybePush();
      expect(port.calls, hasLength(1));
      expect(port.calls.first.familyId, 'f1');
      expect(port.calls.first.records, hasLength(4));
      // 推送记录字段对齐服务端 SyncPushRecord
      final record = port.calls.first.records.first;
      expect(record.keys,
          containsAll(<String>['id', 'version', 'updatedAt', 'deleted', 'nonce', 'ciphertext']));
      expect(await pendingCount('transactions'), 0);
      expect(await pendingCount('categories'), 0);
      expect(await pendingCount('budgets'), 0);

      // 无新变更再触发：不再发起请求
      await scheduler.maybePush();
      expect(port.calls, hasLength(1));
    });

    test('推送密文可被本机密钥解开（密钥派生一致性）', () async {
      await insertTx('tx-1');
      await scheduler.maybePush();

      final privateKey = Uint8List.fromList(
          await vault.unlockedKeyPair!.extractPrivateKeyBytes());
      final dataKey = CryptoPrimitives.hkdfSha256(privateKey,
          info: CryptoPrimitives.kSyncDataKeyInfo);
      final record = port.calls.first.records.single;
      final payload = await SyncOutbox.decryptRecord(dataKey, record);
      expect(payload['recordType'], 'transaction');
      expect(payload['amountCents'], 3000);
    });

    test('批次内部分失败只清成功条，重试推净剩余条目', () async {
      await insertTx('tx-1');
      await insertTx('tx-2');
      port.handler = (familyId, records) async => records
          .map((r) => r['id'] as String)
          .where((id) => id == 'tx-1')
          .toSet();

      await scheduler.maybePush();
      // 推-拉-对账循环：首轮推送只回执 tx-1，补推 tx-2 仍被拒（标记保留）
      expect(port.calls, hasLength(2));
      expect(port.calls.first.records, hasLength(2));
      expect(port.calls.last.records.single['id'], 'tx-2');
      expect(await pendingCount('transactions'), 1,
          reason: '服务端持续拒绝时标记保留待重试');

      // 服务端恢复全量回执，再触发推净 tx-2
      port.handler = null;
      await scheduler.maybePush();
      expect(port.calls, hasLength(3));
      expect(port.calls.last.records.single['id'], 'tx-2');
      expect(await pendingCount('transactions'), 0);

      // 无新变更再触发：不再发请求
      await scheduler.maybePush();
      expect(port.calls, hasLength(3));
    });

    test('网络失败全部保留，恢复后一次推净', () async {
      await insertTx('tx-1');
      await insertTx('tx-2');
      port.handler = (_, __) => throw Exception('网络不可达');

      // fire-and-forget 语义：异常不出函数边界
      await scheduler.maybePush();
      expect(port.calls, hasLength(1));
      expect(await pendingCount('transactions'), 2);

      port.handler = null;
      await scheduler.maybePush();
      expect(port.totalRecords, 4); // 第一次失败 2 条 + 重试成功 2 条
      expect(await pendingCount('transactions'), 0);
    });
  });

  group('任务 7.3：分批与多家庭', () {
    test('分批：batchSize=2 时 5 条分 3 批', () async {
      final chunked = SyncScheduler(
        db: db,
        port: port,
        pullPort: NoopPullPort(),
        vault: vault,
        isSignedIn: () async => true,
        batchSize: 2,
      );
      for (var i = 1; i <= 5; i++) {
        await insertTx('tx-$i');
      }

      await chunked.maybePush();
      expect(port.calls.map((c) => c.records.length), [2, 2, 1]);
      expect(await pendingCount('transactions'), 0);
    });

    test('多家庭分组：跨家庭记录分批各自推送', () async {
      await insertTx('tx-1', familyId: 'f1');
      await insertTx('tx-2', familyId: 'f1');
      await insertTx('tx-3', familyId: 'f2');

      await scheduler.maybePush();
      expect(port.calls, hasLength(2));
      final f1 = port.calls.singleWhere((c) => c.familyId == 'f1');
      final f2 = port.calls.singleWhere((c) => c.familyId == 'f2');
      expect(f1.records, hasLength(2));
      expect(f2.records, hasLength(1));
      expect(await pendingCount('transactions'), 0);
    });

    test('单飞：运行中重复触发合并为一轮，不重复推', () async {
      for (var i = 1; i <= 3; i++) {
        await insertTx('tx-$i');
      }
      // 慢端口放大并发窗口
      port.handler = (familyId, records) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return records.map((r) => r['id'] as String).toSet();
      };

      await Future.wait(
          List.generate(3, (_) => scheduler.maybePush()));
      expect(port.totalRecords, 3, reason: '并发触发不得重复推送');
      expect(await pendingCount('transactions'), 0);

      // rerun 补跑无新变更，不再发请求
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(port.calls, hasLength(1));
    });
  });
}
