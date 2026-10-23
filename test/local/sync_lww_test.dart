import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';

import 'fake_sync_server.dart';

/// 任务 7.5：LWW 冲突与墓碑专项测试（双端并发模拟）。
///
/// 双设备抽象：两个独立 AppDatabase（内存）+ 共享 FakeSyncServer。
/// 设备动作用原始组件组装（不经 SyncPuller/SyncCursorStore——
/// SharedPreferences 全局 mock 下双设备游标互串，且 7.5 焦点是
/// 仲裁语义而非分页，分页已由 7.4 覆盖）。
void main() {
  final dataKey =
      Uint8List.fromList(List.generate(32, (i) => i * 11 % 256));

  late AppDatabase deviceA;
  late AppDatabase deviceB;
  late FakeSyncServer server;

  const txId = 'tx-conflict';
  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';

  setUp(() {
    deviceA = AppDatabase(NativeDatabase.memory());
    deviceB = AppDatabase(NativeDatabase.memory());
    server = FakeSyncServer();
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
  });

  /// 在设备上落一条 v1 初始态交易（模拟双端已同步的共同起点）
  Future<void> seedTx(AppDatabase db, {int amountCents = 1000}) async {
    await db.into(db.transactions).insertReturning(
        TransactionsCompanion.insert(
      id: const Value(txId),
      type: 1,
      categoryId: diningId,
      amountCents: amountCents,
      date: DateTime(2026, 10, 1),
      userId: 'user-1',
      familyId: const Value('f1'),
      description: const Value('初始'),
      // 种子行为已同步态：无待推送
      syncPending: const Value(false),
    ));
  }

  /// 设备推送动作：收集 → 加密 → 推 → 按回执清标记（与真实调度一致：
  /// accepted 与 rejected 均清——rejected 即服务端有更高 version）
  Future<void> devicePush(AppDatabase db) async {
    final rows = await SyncOutbox.collectAll(db, 'f1');
    if (rows.isEmpty) return;
    final records = <Map<String, dynamic>>[];
    for (final row in rows) {
      records.add(await SyncOutbox.encryptRecord(dataKey, row));
    }
    final accepted = server.push('f1', records);
    final done = rows.where((r) => accepted.contains(r.id)).toList();
    if (done.isNotEmpty) {
      await SyncOutbox.clearPending(db, done);
    }
  }

  /// 设备拉取动作：全量翻页 → 逐条 LWW 仲裁入库（游标现算不落盘）
  Future<void> devicePull(AppDatabase db) async {
    final ingest = SyncIngest(db);
    int? cursorTime;
    String? cursorId;
    while (true) {
      final page = server.pull('f1', cursorTime, cursorId);
      final records =
          (page['records'] as List).cast<Map<String, dynamic>>();
      for (final record in records) {
        await ingest.applyRecord(dataKey, record);
      }
      if (page['hasMore'] != true) break;
      cursorTime = page['nextCursorTime'] as int;
      cursorId = page['nextCursorId'] as String;
    }
  }

  Future<Transaction> readTx(AppDatabase db) =>
      (db.select(db.transactions)..where((t) => t.id.equals(txId)))
          .getSingle();

  group('7.5：双端并发编辑收敛', () {
    test('并发编辑收敛到 version 高者（A v2 vs B v5 → 双端 v5）', () async {
      await seedTx(deviceA);
      await seedTx(deviceB);

      // 双端离线并发编辑：A 改为 100（v2），B 改为 200（v5）
      await (deviceA.update(deviceA.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        amountCents: const Value(100),
        version: const Value(2),
        updatedAt: Value(DateTime(2026, 10, 2, 8)),
        syncPending: const Value(true),
      ));
      await (deviceB.update(deviceB.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        amountCents: const Value(200),
        version: const Value(5),
        updatedAt: Value(DateTime(2026, 10, 2, 9)),
        syncPending: const Value(true),
      ));

      // 双端先后推送（顺序无关性由服务端 LWW 保证）
      await devicePush(deviceA); // v2 accepted
      await devicePush(deviceB); // v5 accepted（覆盖 v2）
      expect(server.record(txId)!['version'], 5);

      // 双端拉取收敛
      await devicePull(deviceA);
      await devicePull(deviceB);

      final a = await readTx(deviceA);
      final b = await readTx(deviceB);
      expect(a.version, 5);
      expect(a.amountCents, 200);
      expect(b.version, 5);
      expect(b.amountCents, 200, reason: '双端收敛到 version 高者');
    });

    test('同 version 并发收敛到 updated_at 新者', () async {
      await seedTx(deviceA);
      await seedTx(deviceB);

      // A v3 早、B v3 晚
      await (deviceA.update(deviceA.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        amountCents: const Value(111),
        version: const Value(3),
        updatedAt: Value(DateTime(2026, 10, 2, 8)),
        syncPending: const Value(true),
      ));
      await (deviceB.update(deviceB.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        amountCents: const Value(222),
        version: const Value(3),
        updatedAt: Value(DateTime(2026, 10, 2, 12)),
        syncPending: const Value(true),
      ));

      // B（updated_at 新）先推，A（updated_at 旧）后推——推达顺序颠倒
      // 也不影响：服务端按 updated_at 仲裁拒绝 A，服务端仍保留 B 的位置
      await devicePush(deviceB);
      await devicePush(deviceA);
      expect(server.record(txId)!['updatedAt'],
          DateTime(2026, 10, 2, 12).millisecondsSinceEpoch,
          reason: 'A 推达更晚但 updated_at 更旧，服务端拒绝覆盖');
      await devicePull(deviceA);
      await devicePull(deviceB);

      final a = await readTx(deviceA);
      final b = await readTx(deviceB);
      expect(a.amountCents, 222);
      expect(b.amountCents, 222, reason: '双端收敛到 updated_at 新者');
      expect(a.updatedAt, DateTime(2026, 10, 2, 12));
    });
  });

  group('7.5：删除墓碑不复活', () {
    test('删除后迟到低版本编辑推送被拒，双端收敛墓碑', () async {
      await seedTx(deviceA);
      await seedTx(deviceB);

      // A 连续编辑到 v6 后删除（墓碑）
      await (deviceA.update(deviceA.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        deleted: const Value(true),
        version: const Value(6),
        updatedAt: Value(DateTime(2026, 10, 3, 8)),
        syncPending: const Value(true),
      ));
      await devicePush(deviceA);
      expect(server.record(txId)!['deleted'], 1);

      // B 手上有迟到的旧编辑（v4，未推送）
      await (deviceB.update(deviceB.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        amountCents: const Value(999),
        version: const Value(4),
        updatedAt: Value(DateTime(2026, 10, 3, 6)),
        syncPending: const Value(true),
      ));

      // B 推迟到编辑：服务端 v6 墓碑更高 → rejected，不覆盖
      await devicePush(deviceB);
      expect(server.record(txId)!['deleted'], 1,
          reason: '低 version 编辑不能复活墓碑');
      expect(server.record(txId)!['version'], 6);

      // B 拉取：本地 v4 被服务端 v6 墓碑覆盖 → B 落墓碑
      await devicePull(deviceB);
      // A 拉取：幂等
      await devicePull(deviceA);

      final a = await readTx(deviceA);
      final b = await readTx(deviceB);
      expect(a.deleted, true);
      expect(b.deleted, true, reason: '双端一致收敛到墓碑');
      expect(b.version, 6);
      expect(b.syncPending, false);
    });

    test('更高 version 的正常编辑可翻案复活（LWW 语义完整性）', () async {
      await seedTx(deviceA);
      await seedTx(deviceB);

      // A 删除 v2
      await (deviceA.update(deviceA.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        deleted: const Value(true),
        version: const Value(2),
        updatedAt: Value(DateTime(2026, 10, 3, 8)),
        syncPending: const Value(true),
      ));
      await devicePush(deviceA);
      await devicePull(deviceB);
      expect((await readTx(deviceB)).deleted, true);

      // B 在删除后重新记账（更高 version 正常记录）
      await (deviceB.update(deviceB.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
        deleted: const Value(false),
        amountCents: const Value(500),
        version: const Value(3),
        updatedAt: Value(DateTime(2026, 10, 3, 10)),
        syncPending: const Value(true),
      ));
      await devicePush(deviceB);
      await devicePull(deviceA);

      final a = await readTx(deviceA);
      final b = await readTx(deviceB);
      expect(a.deleted, false, reason: '更高 version 正常记录翻案复活');
      expect(b.deleted, false);
      expect(a.amountCents, 500);
      expect(b.amountCents, 500);
    });
  });
}
