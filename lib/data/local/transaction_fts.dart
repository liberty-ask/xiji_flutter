import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'app_database.dart';
import 'fts_tokenizer.dart';

/// 单条交易的索引素材：主表写库与索引写入同源。
///
/// [deleted] 为 true 表示墓碑，只摘除索引不写入文本；文本为空（无描述
/// 且无交易对方）的行同样只摘除不写入。
class TransactionFtsEntry {
  const TransactionFtsEntry({
    required this.id,
    required this.deleted,
    this.description,
    this.counterparty,
  });

  factory TransactionFtsEntry.fromRow(Transaction row) => TransactionFtsEntry(
        id: row.id,
        deleted: row.deleted,
        description: row.description,
        counterparty: row.counterparty,
      );

  final String id;
  final bool deleted;
  final String? description;
  final String? counterparty;

  String get text => TransactionFts.textOf(
        description: description,
        counterparty: counterparty,
      );
}

/// `transactions_fts` 的唯一写入器：分词口径、先删后插、全量重建都在这里。
///
/// 收口约定：除本文件外，任何写库路径都不得直接操作 `transactions_fts`
/// ——仓储（正常记账/编辑/软删/账单导入）、同步入库（单条/整页）、备份
/// 导入与 schema 迁移全部经由本类，新增写库路径也不会再漏维护索引。
///
/// 索引口径：描述 + 交易对方，中文逐字、英文数字整词（[FtsTokenizer]）。
/// 先按 tx_id 批量删除再插入，保证同一交易只有一行索引（查询侧 JOIN
/// 主表未加 DISTINCT，重复索引行会让结果重复）。
class TransactionFts {
  TransactionFts._();

  /// 单次 SQL 的 tx_id 个数（保守避开 SQLite 变量数量上限）
  static const int _chunkSize = 400;

  /// 唯一分词口径：描述 + 交易对方拼成索引文本（空文本返回空串）
  static String textOf({String? description, String? counterparty}) {
    final parts = [description, counterparty]
        .whereType<String>()
        .where((s) => s.isNotEmpty);
    return FtsTokenizer.tokenize(parts.join(' '));
  }

  /// 把「先删后插」语句排进调用方已有的 batch/事务（同步入库整页路径用）。
  static void queueInBatch(Batch batch, List<TransactionFtsEntry> entries) {
    if (entries.isEmpty) return;
    // 同一批内重复 id 只保留最后一次，避免插入重复索引行
    final byId = <String, TransactionFtsEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final values = byId.values.toList();

    for (final chunk in _chunks([for (final e in values) e.id])) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      batch.customStatement(
        'DELETE FROM transactions_fts WHERE tx_id IN ($placeholders)',
        chunk,
      );
    }
    for (final entry in values) {
      if (entry.deleted) continue;
      final text = entry.text;
      if (text.isEmpty) continue;
      batch.customStatement(
        'INSERT INTO transactions_fts(fts_text, tx_id) VALUES (?, ?)',
        [text, entry.id],
      );
    }
  }

  /// 独立写入一批索引（仓储单条/小批量路径用，自带一个 batch）。
  /// 调用方若已在事务中，drift 会将其并入外层事务。
  static Future<void> sync(
    AppDatabase db,
    List<TransactionFtsEntry> entries,
  ) {
    if (entries.isEmpty) return Future<void>.value();
    return db.batch((b) => queueInBatch(b, entries));
  }

  /// 全量重建：清空后按同一分词口径回填全部未删除且有文本的交易，
  /// 墓碑与空文本行不进索引。完成后校验条数，不一致仅打日志不抛错
  /// （索引缺失不应阻断升级/恢复流程，后续写入会继续自愈）。
  static Future<void> rebuild(AppDatabase db) async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM transactions_fts');
      final rows = await (db.select(db.transactions)
            ..where((t) => t.deleted.equals(false)))
          .get();

      var indexed = 0;
      await db.batch((b) {
        for (final row in rows) {
          final text = textOf(
            description: row.description,
            counterparty: row.counterparty,
          );
          if (text.isEmpty) continue;
          b.customStatement(
            'INSERT INTO transactions_fts(fts_text, tx_id) VALUES (?, ?)',
            [text, row.id],
          );
          indexed++;
        }
      });

      final actual = (await db
              .customSelect('SELECT COUNT(*) AS c FROM transactions_fts')
              .getSingle())
          .read<int>('c');
      if (actual != indexed) {
        debugPrint(
          '[TransactionFts] 索引重建计数不一致：期望 $indexed 行，实际 $actual 行',
        );
      }
    });
  }

  static Iterable<List<T>> _chunks<T>(List<T> items) sync* {
    for (var start = 0; start < items.length; start += _chunkSize) {
      final end = start + _chunkSize > items.length
          ? items.length
          : start + _chunkSize;
      yield items.sublist(start, end);
    }
  }
}
