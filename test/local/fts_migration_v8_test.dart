import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3; // ignore: depend_on_referenced_packages
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';

/// 搜索索引自愈：v7 -> v8 一次性全量重建。
///
/// 背景：v8 之前同步入库（首轮全量恢复/日常增量）只写主表不维护
/// transactions_fts，重装/换机后整库搜不到。迁移负责回填历史缺口。
void main() {
  test('v7 -> v8：存量交易回填索引，墓碑与空文本不进索引', () async {
    final dir = await Directory.systemTemp.createTemp('xiji_v8_migration');
    final dbPath = '${dir.path}/xiji.sqlite';
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    // 手工造 v7 形态库：交易表全列（含 v7 退款冲抵列）+ 空的 FTS 表，
    // 模拟「升级前同步入库不会写索引」的存量缺口
    final raw = sqlite3.sqlite3.open(dbPath);
    raw.execute('CREATE TABLE transactions('
        'id TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'category_id TEXT NOT NULL, '
        'amount_cents INTEGER NOT NULL, '
        'date INTEGER NOT NULL, '
        'user_id TEXT NOT NULL, '
        "family_id TEXT NOT NULL DEFAULT '', "
        'description TEXT NULL, '
        'counterparty TEXT NULL, '
        'trade_no TEXT NULL, '
        'merchant_order_no TEXT NULL, '
        'pay_method TEXT NULL, '
        'platform TEXT NULL, '
        'refund_of_id TEXT NULL, '
        'refunded_cents INTEGER NOT NULL DEFAULT 0, '
        'version INTEGER NOT NULL DEFAULT 1, '
        'updated_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'sync_pending INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id))');
    raw.execute(
        'CREATE VIRTUAL TABLE transactions_fts USING fts5(fts_text, tx_id UNINDEXED)');
    // v9 迁移会补种内置「保险」分类，真实 v7 库同样有 categories 表（本用例留空）
    raw.execute('CREATE TABLE categories('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'icon TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'is_builtin INTEGER NOT NULL DEFAULT 0, '
        'sort_order INTEGER NOT NULL DEFAULT 0, '
        "family_id TEXT NOT NULL DEFAULT '', "
        'version INTEGER NOT NULL DEFAULT 1, '
        'updated_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'sync_pending INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id))');
    raw.execute(
        "INSERT INTO transactions(id, type, category_id, amount_cents, date, "
        "user_id, family_id, description, updated_at) VALUES "
        "('tx-sync-1', 1, 'cat', 1000, 0, 'u1', 'f1', '同步来的账', 0)");
    raw.execute(
        "INSERT INTO transactions(id, type, category_id, amount_cents, date, "
        "user_id, family_id, description, updated_at, deleted) VALUES "
        "('tx-deleted', 1, 'cat', 1000, 0, 'u1', 'f1', '已删的账', 0, 1)");
    raw.execute(
        "INSERT INTO transactions(id, type, category_id, amount_cents, date, "
        "user_id, family_id, updated_at) VALUES "
        "('tx-empty', 1, 'cat', 1000, 0, 'u1', 'f1', 0)");
    raw.execute('PRAGMA user_version = 7');
    raw.dispose();

    // 打开触发 v8 迁移：一次性重建索引
    final db = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(() => db.close());
    final repo = TransactionRepository(db);

    expect((await repo.search('f1', '同步')).map((t) => t.id), ['tx-sync-1']);
    expect(await repo.search('f1', '已删'), isEmpty, reason: '墓碑不进索引');
    final count = await db
        .customSelect('SELECT COUNT(*) AS c FROM transactions_fts')
        .getSingle();
    expect(count.read<int>('c'), 1, reason: '只有一条非墓碑且有文本的交易');
  });
}
