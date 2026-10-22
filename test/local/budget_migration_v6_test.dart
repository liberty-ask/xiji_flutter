import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:xiji_flutter/data/local/app_database.dart';

/// 任务 7.1：预算个人化 schema 迁移（v5 → v6）。
///
/// 验证两点：存量行补种本地登录用户 ID；新唯一约束
/// UNIQUE(family_id, user_id, year, month) 生效（同成员同月撞约束、
/// 不同成员同月并存）。
void main() {
  test('v5 -> v6：存量预算行补种当前登录用户 ID，新约束生效', () async {
    final dir = await Directory.systemTemp.createTemp('xiji_v6_migration');
    final dbPath = '${dir.path}/xiji.sqlite';
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    // 手工造 v5 形态库：budgets 无 user_id，唯一约束(family_id, year, month)
    final raw = sqlite3.sqlite3.open(dbPath);
    raw.execute('CREATE TABLE budgets('
        'id TEXT NOT NULL, '
        "family_id TEXT NOT NULL DEFAULT '', "
        'year INTEGER NOT NULL, '
        'month INTEGER NOT NULL, '
        'amount_cents INTEGER NOT NULL, '
        'version INTEGER NOT NULL DEFAULT 1, '
        'updated_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'sync_pending INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id), '
        'UNIQUE (family_id, year, month))');
    raw.execute(
        "INSERT INTO budgets(id, family_id, year, month, amount_cents, "
        'updated_at) VALUES (\'b1\', \'f1\', 2026, 10, 500000, 0)');
    raw.execute('PRAGMA user_version = 5');
    raw.dispose();

    // 打开触发 v6 迁移：存量行 user_id 补种迁移种子提供者的返回值
    // （生产为登录用户；测试注入固定值，不依赖 prefs mock，
    //  避免与同 isolate 其他测试文件的 SharedPreferences 实例缓存互染）
    final db = AppDatabase(NativeDatabase(File(dbPath)),
        migrationSeedUserIdProvider: () async => 'u-seed');
    addTearDown(() => db.close());

    final rows = await db.select(db.budgets).get();
    expect(rows.length, 1);
    expect(rows.first.userId, 'u-seed', reason: '存量行补种登录用户 ID');
    expect(rows.first.amountCents, 500000, reason: '金额原样保留');

    // 新唯一约束：同家庭同用户同月第二行拒绝
    var threw = false;
    try {
      await db.customStatement(
          "INSERT INTO budgets(id, family_id, user_id, year, month, "
          'amount_cents, updated_at) VALUES (\'b2\', \'f1\', \'u-seed\', '
          '2026, 10, 1, 0)');
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue, reason: '同家庭同用户同月应撞唯一约束');

    // 不同用户同月并存
    await db.customStatement(
        "INSERT INTO budgets(id, family_id, user_id, year, month, "
        'amount_cents, updated_at) VALUES (\'b3\', \'f1\', \'u-other\', '
        '2026, 10, 2, 0)');
    expect((await db.select(db.budgets).get()).length, 2,
        reason: '不同成员同月各自一条');
  });
}
