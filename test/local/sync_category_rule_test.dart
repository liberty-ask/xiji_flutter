import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/sync/sync_ingest.dart';
import 'package:xiji_flutter/sync/sync_outbox.dart';

import 'fake_sync_server.dart';

/// 任务 7.6：学习表加密漫游专项测试。
///
/// 设备动作用原始组件组装（与 sync_lww_test 同法：SharedPreferences
/// 全局 mock 下双设备游标互串，拉取游标现算不落盘）。
void main() {
  final dataKey =
      Uint8List.fromList(List.generate(32, (i) => i * 13 % 256));

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';
  const petId = '0f8f1d3e-2c4b-7a5e-9d6c-1b2a3c4d5e6f';

  late AppDatabase deviceA;
  late AppDatabase deviceB;
  late FakeSyncServer server;

  setUp(() {
    deviceA = AppDatabase(NativeDatabase.memory());
    deviceB = AppDatabase(NativeDatabase.memory());
    server = FakeSyncServer();
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
  });

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

  group('7.6：换设备学习表命中生效', () {
    test('A 指认 → 推送 → B 空库全量拉取 → 学习表命中生效', () async {
      // 设备 A：账单导入指认「美团外卖」→ 餐饮（学习表回写）
      final repoA = CategoryRuleRepository(deviceA);
      await repoA.assign(matchText: '美团外卖', categoryId: diningId, source: 0);
      await repoA.recordHit((await deviceA.select(deviceA.categoryRules)
              .getSingle())
          .id);

      // A 推送（含学习表条目）
      await devicePush(deviceA);
      final ruleId = (await deviceA.select(deviceA.categoryRules).getSingle()).id;
      expect(server.record(ruleId), isNotNull, reason: '学习表条目已上云');

      // 设备 B：全新空库全量拉取
      await devicePull(deviceB);

      // B 换设备后学习表命中生效：findByMatchText 命中餐饮指认
      // （CategoryEngine 学习表命中即走此数据源，3.2 已单测引擎行为）
      final repoB = CategoryRuleRepository(deviceB);
      final hit = await repoB.findByMatchText('美团外卖');
      expect(hit, isNotNull);
      expect(hit!.categoryId, diningId);
      expect(hit.hitCount, 1, reason: '命中计数随行漫游');
      expect(hit.deleted, false);
      expect(hit.syncPending, false, reason: '云端权威数据无需回推');

      // B 侧指认幂等：同文本同分类不产生新变更
      await repoB.assign(matchText: '美团外卖', categoryId: diningId, source: 0);
      final count = await deviceB.select(deviceB.categoryRules).get();
      expect(count, hasLength(1), reason: 'UNIQUE(match_text) 兜底单行');
    });

    test('双端对同一文本并发指认不同分类：拉取侧按 matchText 归并收敛',
        () async {
      // A 指认美团 → 餐饮（早，v1）
      final repoA = CategoryRuleRepository(deviceA);
      await repoA.assign(matchText: '美团', categoryId: diningId, source: 0);
      await devicePush(deviceA);

      // B 离线指认美团 → 宠物（晚，v3）——双端不同 id、同 matchText
      final repoB = CategoryRuleRepository(deviceB);
      await repoB.assign(matchText: '美团', categoryId: petId, source: 1);
      // B 本地行造高版本（模拟多次编辑后的并发）
      await (deviceB.update(deviceB.categoryRules)
            ..where((r) => r.matchText.equals('美团')))
          .write(CategoryRulesCompanion(
        version: const Value(3),
        updatedAt: Value(DateTime(2026, 10, 5, 9)),
      ));
      await devicePush(deviceB); // v3 上云（id 不同，服务端两条并存）

      // A 拉取 B 的条目：matchText 相同 id 不同 → 归并 LWW（v3 胜），
      // A 本地行更新为 B 的指认（保留 A 本地行 id 占位）
      await devicePull(deviceA);
      final aRule = await repoA.findByMatchText('美团');
      expect(aRule!.categoryId, petId, reason: '收敛到 version 高者的指认');
      expect(aRule.version, 3);
      expect(aRule.syncPending, false);

      // A 本地表仍单行（UNIQUE 占位不破坏）
      final aRows = await deviceA.select(deviceA.categoryRules).get();
      expect(aRows, hasLength(1));

      // B 拉取 A 的旧条目（v1）：本地 v3 更高 → 跳过，指认不被冲掉
      await devicePull(deviceB);
      final bRule = await repoB.findByMatchText('美团');
      expect(bRule!.categoryId, petId);
      expect(bRule.version, 3);
    });

    test('收集通道：currentFamilyId 为 null 时跳过学习表收集', () async {
      final repoA = CategoryRuleRepository(deviceA);
      await repoA.assign(matchText: '饿了么', categoryId: diningId, source: 0);

      final rowsWithFamily = await SyncOutbox.collectAll(deviceA, 'f1');
      expect(rowsWithFamily, hasLength(1));
      expect(rowsWithFamily.first.recordType, 'categoryRule');
      expect(rowsWithFamily.first.familyId, 'f1',
          reason: '用户级数据走当前家庭通道');
      expect(rowsWithFamily.first.payload['matchText'], '饿了么');

      final rowsNoFamily = await SyncOutbox.collectAll(deviceA, null);
      expect(rowsNoFamily, isEmpty, reason: '无家庭上下文时跳过学习表');
    });

    test('云端胜本地：更高版本云端条目覆盖本地未推送指认', () async {
      // 云端已有 v1 美团→餐饮
      final repoA = CategoryRuleRepository(deviceA);
      await repoA.assign(matchText: '美团', categoryId: diningId, source: 0);
      await devicePush(deviceA);

      // B 拉取后本地指认为餐饮 → 改指宠物且未推送（v2）
      await devicePull(deviceB);
      final repoB = CategoryRuleRepository(deviceB);
      await repoB.assign(matchText: '美团', categoryId: petId, source: 1);

      // 云端出现新的 v5 餐饮条目（另一设备 C 指认后推送）
      final deviceC = AppDatabase(NativeDatabase.memory());
      addTearDown(deviceC.close);
      final repoC = CategoryRuleRepository(deviceC);
      await repoC.assign(matchText: '美团', categoryId: diningId, source: 0);
      await (deviceC.update(deviceC.categoryRules)
            ..where((r) => r.matchText.equals('美团')))
          .write(CategoryRulesCompanion(
        version: const Value(5),
        updatedAt: Value(DateTime(2026, 10, 6, 9)),
        syncPending: const Value(true),
      ));
      final cRows = await SyncOutbox.collectAll(deviceC, 'f1');
      final cRecords = <Map<String, dynamic>>[];
      for (final row in cRows) {
        cRecords.add(await SyncOutbox.encryptRecord(dataKey, row));
      }
      server.push('f1', cRecords);

      // B 拉取：本地 v2 更低，被云端 v5 覆盖收敛（且本地行保留单行）
      await devicePull(deviceB);
      final bRule = await repoB.findByMatchText('美团');
      expect(bRule!.categoryId, diningId, reason: 'v5 云端胜出覆盖本地 v2');
      expect(bRule.version, 5);
      expect(bRule.syncPending, false);
      expect(await deviceB.select(deviceB.categoryRules).get(), hasLength(1));
    });
  });
}
