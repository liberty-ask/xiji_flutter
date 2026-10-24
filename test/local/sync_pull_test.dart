import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/sync/sync_cursor_store.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';
import 'package:xiji_flutter/sync/sync_puller.dart';

import 'fake_sync_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dataKey =
      Uint8List.fromList(List.generate(32, (i) => i * 5 % 256));

  tearDown(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('任务 7.4：分页拉取循环', () {
    test('hasMore 翻页直到取完，全部入库，游标落位', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = FakeSyncServer(pageSize: 2);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 造 5 条交易记录进服务端（updatedAt 递增保证排序稳定）
      for (var i = 1; i <= 5; i++) {
        final row = _cloudTx('tx-$i',
            updatedAt: DateTime(2026, 10, 1, 0, 0, i));
        server.push('f1', [await SyncOutbox.encryptRecord(dataKey, row)]);
      }

      final puller = SyncPuller(
          db: db,
          port: FakeServerPullPort(server),
          currentFamilyId: () async => 'f1');
      await puller.pullAll(dataKey);

      expect(server.requests.length, 3, reason: '5 条页大小 2 → 3 页');
      final txCount = await db.select(db.transactions).get();
      expect(txCount, hasLength(5));
      // 游标保存到尾页末条位置
      final cursor = await SyncCursorStore.load('f1');
      expect(cursor, isNotNull);
      expect(cursor!.time, DateTime(2026, 10, 1, 0, 0, 5).millisecondsSinceEpoch);
      expect(cursor.id, 'tx-5');
    });

    test('游标增量：首次全量后云端新增，第二次只拉新记录', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = FakeSyncServer(pageSize: 500);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      server.push('f1',
          [await SyncOutbox.encryptRecord(dataKey, _cloudTx('tx-1'))]);
      final puller = SyncPuller(
          db: db,
          port: FakeServerPullPort(server),
          currentFamilyId: () async => 'f1');
      await puller.pullAll(dataKey);
      expect(server.requests.first.cursorTime, null,
          reason: '新设备无游标全量拉取');

      // 云端新增一条
      server.push('f1', [
        await SyncOutbox.encryptRecord(
            dataKey,
            _cloudTx('tx-2',
                updatedAt: DateTime(2026, 10, 2)))
      ]);
      await puller.pullAll(dataKey);

      expect(server.requests.last.cursorTime, isNotNull,
          reason: '第二次带游标增量拉取');
      final rows = await db.select(db.transactions).get();
      expect(rows.map((r) => r.id), containsAll(<String>['tx-1', 'tx-2']));
    });

    test('中途页解密异常：游标停在成功页末，下次从断点重拉', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = FakeSyncServer(pageSize: 2);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      for (var i = 1; i <= 3; i++) {
        final row = _cloudTx('tx-$i', updatedAt: DateTime(2026, 10, 1, 0, 0, i));
        server.push('f1', [await SyncOutbox.encryptRecord(dataKey, row)]);
      }
      // 第二页起损坏密文（篡改 ciphertext）→ 解密失败
      final port = _CorruptingServerPort(server);
      final puller = SyncPuller(
          db: db, port: port, currentFamilyId: () async => 'f1');

      await expectLater(puller.pullAll(dataKey), throwsA(anything));
      // 游标停在第一页末条（tx-2 成功入库已推进），损坏页下次重拉
      final cursor = await SyncCursorStore.load('f1');
      expect(cursor, isNotNull);
      expect(
          cursor!.time, DateTime(2026, 10, 1, 0, 0, 2).millisecondsSinceEpoch);
      expect(cursor.id, 'tx-2');
      expect(server.requests.length, 2, reason: '第一页成功、第二页拉取后失败');

      // 重拉从断点继续：只取 tx-3（服务端已恢复完好密文）
      final recovered = SyncPuller(
          db: db, port: FakeServerPullPort(server), currentFamilyId: () async => 'f1');
      await recovered.pullAll(dataKey);
      final rows = await db.select(db.transactions).get();
      expect(rows.map((r) => r.id), containsAll(<String>['tx-1', 'tx-2', 'tx-3']));
      expect(server.requests.last.cursorId, 'tx-2',
          reason: '断点续拉带 tx-2 游标');
    });
  });

  group('任务 7.4：新设备全量恢复（双设备模拟）', () {
    test('设备 A 推送 → 设备 B 空库全量拉取，本地统计一致', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = FakeSyncServer();

      // ── 设备 A：写本地数据 → 发件箱收集加密 → 推送 ──
      final deviceA = AppDatabase(NativeDatabase.memory());
      addTearDown(deviceA.close);

      const amounts = <int>[3000, 12550, 199]; // 分
      for (var i = 0; i < 3; i++) {
        await deviceA.into(deviceA.transactions).insertReturning(
            TransactionsCompanion.insert(
          id: Value('tx-${i + 1}'),
          type: 1,
          categoryId: '01a15d13-bded-710c-a3bd-aba94a5aeb36',
          amountCents: amounts[i],
          date: DateTime(2026, 10, i + 1),
          userId: 'user-1',
          familyId: const Value('f1'),
          description: Value('咖啡 $i'),
        ));
      }
      await deviceA.into(deviceA.categories).insertReturning(
          CategoriesCompanion.insert(
        id: const Value('cat-x'),
        name: '宠物开销',
        icon: 'pets',
        type: 1,
        familyId: const Value('f1'),
      ));
      await deviceA.into(deviceA.budgets).insertReturning(
          BudgetsCompanion.insert(
        id: const Value('b-1'),
        familyId: const Value('f1'),
        userId: 'user-1',
        year: 2026,
        month: 10,
        amountCents: 200000,
      ));

      final outboxRows = await SyncOutbox.collectAll(deviceA, 'f1');
      expect(outboxRows, hasLength(5), reason: '三表收集 3 交易+1 分类+1 预算');
      server.push(
          'f1',
          [
            for (final row in outboxRows)
              await SyncOutbox.encryptRecord(dataKey, row)
          ]);

      // ── 设备 B：全新空库 → 全量拉取恢复 ──
      final deviceB = AppDatabase(NativeDatabase.memory());
      addTearDown(deviceB.close);
      final puller = SyncPuller(
          db: deviceB,
          port: FakeServerPullPort(server),
          currentFamilyId: () async => 'f1');
      await puller.pullAll(dataKey);

      // 验证恢复后本地统计与设备 A 一致
      final aTxs = await deviceA.select(deviceA.transactions).get();
      final bTxs = await deviceB.select(deviceB.transactions).get();
      expect(bTxs, hasLength(aTxs.length));
      final aSum =
          aTxs.fold<int>(0, (sum, t) => sum + t.amountCents);
      final bSum =
          bTxs.fold<int>(0, (sum, t) => sum + t.amountCents);
      expect(bSum, aSum, reason: '交易金额总和一致');
      expect(
          bTxs.map((t) => t.id), containsAll(aTxs.map((t) => t.id)));

      final aCat = await (deviceA.select(deviceA.categories)
            ..where((c) => c.id.equals('cat-x')))
          .getSingle();
      final bCat = await (deviceB.select(deviceB.categories)
            ..where((c) => c.id.equals('cat-x')))
          .getSingle();
      expect(bCat.name, aCat.name);
      expect(bCat.syncPending, false);

      final aBudget = await deviceA.select(deviceA.budgets).getSingle();
      final bBudget = await deviceB.select(deviceB.budgets).getSingle();
      expect(bBudget.amountCents, aBudget.amountCents);
      expect(bBudget.year, 2026);

      // 设备 B 恢复后游标落位，下次增量
      expect(await SyncCursorStore.load('f1'), isNotNull);
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

/// 从第二页起破坏密文（模拟损坏记录）
class _CorruptingServerPort implements SyncPullPort {
  _CorruptingServerPort(this._server);
  final FakeSyncServer _server;
  int _pulled = 0;

  @override
  Future<Map<String, dynamic>> pull(
    String familyId,
    int? cursorTime,
    String? cursorId, {
    String? recordId,
    int? limit,
  }) async {
    final page = _server.pull(familyId, cursorTime, cursorId,
        recordId: recordId, limit: limit);
    _pulled++;
    if (_pulled == 2) {
      final records = (page['records'] as List).cast<Map<String, dynamic>>();
      for (final r in records) {
        r['ciphertext'] = 'AAAA${r['ciphertext']}'; // 篡改 base64
      }
    }
    return page;
  }
}
