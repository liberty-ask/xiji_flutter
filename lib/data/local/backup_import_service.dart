import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import 'app_database.dart' as local;
import 'builtin_categories.dart';
import 'current_family_store.dart';
import 'fts_tokenizer.dart';

/// 在线版 -> 离线版 备份导入器（5.8，格式见 openspec design.md D10）。
///
/// 输入：export_offline_migration 产出的 xiji_backup.json（version=1）。
/// 映射口径：
/// - 分类：名称+类型命中本地内置分类 -> 映射到固定 UUID（不插入）；
///   未命中的自定义分类保原 ID 插入（归属当前家庭，sortOrder 顺延）
/// - 交易：ID 保留原雪花值；categoryId 经映射转换；createdBy -> userId；
///   familyId 归一化为当前家庭；updatedAt 保留导出值；version=1、非墓碑
/// - 预算：服务端家庭级单条 -> 当前家庭当月
/// 幂等：按 ID 已存在则跳过（含自定义分类同名已存在时映射到已有行），重复导入零副作用。
class BackupImportService {
  final local.AppDatabase _db;

  BackupImportService(this._db);

  Future<BackupImportResult> importFromPath(String path) async {
    final content = await File(path).readAsString(encoding: utf8);
    return importFromString(content);
  }

  Future<BackupImportResult> importFromString(String content) async {
    final dynamic root;
    try {
      root = jsonDecode(content);
    } catch (e) {
      throw const FormatException('备份文件不是合法的 JSON');
    }
    if (root is! Map<String, dynamic> || root['version'] != 1) {
      throw const FormatException('备份文件版本不受支持（期望 version=1）');
    }
    final categories = (root['categories'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final transactions = (root['transactions'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final budgets = (root['budgets'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final familyId = await CurrentFamilyStore.get();
    final now = DateTime.now();
    final result = BackupImportResult();

    await _db.transaction(() async {
      // ---- 分类：先建映射，再插入自定义 ----
      final catIdMap = <String, String>{}; // 服务端分类 ID -> 本地分类 ID
      final customToInsert = <local.CategoriesCompanion>[];

      // 内置 sortOrder 起点：同类型最大值顺延（含内置与已存在自定义）
      var maxSortExpense = 0, maxSortIncome = 0;
      final existingCats = await _db.select(_db.categories).get();
      for (final c in existingCats) {
        if (c.type == 1) {
          maxSortExpense = c.sortOrder > maxSortExpense ? c.sortOrder : maxSortExpense;
        } else if (c.type == 0) {
          maxSortIncome = c.sortOrder > maxSortIncome ? c.sortOrder : maxSortIncome;
        }
      }

      // 幂等索引（全量拉取内存查重，替代逐条单查——万级数据逐条
      // count 是真机导入小时级卡顿的根因）
      final existingCatById = <String, local.Category>{
        for (final c in existingCats)
          if (!c.deleted) c.id: c,
      };
      final existingCatByName = <String, local.Category>{
        for (final c in existingCats)
          if (!c.deleted && c.familyId == familyId) '${c.type}:${c.name}': c,
      };

      for (final cat in categories) {
        final oldId = cat['id'] as String?;
        final name = cat['name'] as String?;
        final type = cat['type'] as int?;
        if (oldId == null || name == null || type == null) continue;

        // 1) 名称+类型命中内置分类 -> 映射固定 UUID
        final builtin = BuiltinCategories.byName(name, type);
        if (builtin != null) {
          catIdMap[oldId] = builtin.id;
          result.categoriesMappedBuiltin++;
          continue;
        }
        // 2) 同 ID 已存在（重复导入）-> 幂等映射自身
        final byId = existingCatById[oldId];
        if (byId != null) {
          catIdMap[oldId] = byId.id;
          result.categoriesSkipped++;
          continue;
        }
        // 3) 同名同型的自定义分类已存在（换设备/重复迁移）-> 映射到已有行
        final byName = existingCatByName['$type:$name'];
        if (byName != null) {
          catIdMap[oldId] = byName.id;
          result.categoriesSkipped++;
          continue;
        }
        // 4) 新自定义分类：保原 ID，sortOrder 顺延，icon 保留服务端值
        final isExpense = type == 1;
        final sort = isExpense ? ++maxSortExpense : ++maxSortIncome;
        catIdMap[oldId] = oldId;
        customToInsert.add(local.CategoriesCompanion.insert(
          id: Value(oldId),
          name: name,
          type: type,
          icon: (cat['icon'] as String?) ?? 'help_outline',
          sortOrder: Value(sort),
          isBuiltin: const Value(false),
          familyId: Value(familyId),
          version: const Value(1),
          updatedAt: Value(now),
        ));
        result.categoriesInserted++;
      }
      if (customToInsert.isNotEmpty) {
        await _db.batch((b) => b.insertAll(
            _db.categories, customToInsert, mode: InsertMode.insertOrIgnore));
      }

      // ---- 交易 ----
      // 幂等：一次拉全部已存在 ID，内存 Set 查重。逐条 count 是 8948 条
      // 真机导入跑一个多小时的根因（万级数据改为两次查询，毫秒级）。
      final existingTxIds = (await (_db.selectOnly(_db.transactions)
              ..addColumns([_db.transactions.id]))
            .get())
          .map((row) => row.read(_db.transactions.id))
          .toSet();
      final txToInsert = <local.TransactionsCompanion>[];
      for (final tx in transactions) {
        final id = tx['id'] as String?;
        final type = tx['type'] as int?;
        final amount = (tx['amount'] as num?)?.toDouble();
        final categoryId = catIdMap[tx['categoryId'] as String?];
        final dateStr = tx['date'] as String?;
        if (id == null ||
            type == null ||
            amount == null ||
            categoryId == null ||
            dateStr == null) {
          result.failures.add('字段缺失: ${tx['id'] ?? '?'}');
          continue;
        }
        // 幂等：同 ID 已存在则跳过（保留本地数据）
        if (existingTxIds.contains(id)) {
          result.transactionsSkipped++;
          continue;
        }
        DateTime? updatedAt;
        final ua = tx['updatedAt'] as String?;
        if (ua != null) {
          updatedAt = DateTime.tryParse(ua.replaceAll(' ', 'T'));
        }
        txToInsert.add(local.TransactionsCompanion.insert(
          id: Value(id),
          type: type,
          categoryId: categoryId,
          amount: amount,
          date: DateTime.parse(dateStr),
          userId: tx['createdBy'] as String? ?? '',
          familyId: Value(familyId),
          description: Value(tx['description'] as String?),
          counterparty: Value(tx['counterparty'] as String?),
          tradeNo: Value(tx['tradeNo'] as String?),
          merchantOrderNo: Value(tx['merchantOrderNo'] as String?),
          payMethod: Value(tx['payMethod'] as String?),
          platform: Value(tx['platform'] as String?),
          updatedAt: Value(updatedAt ?? now),
        ));
      }
      if (txToInsert.isNotEmpty) {
        await _db.batch((b) => b.insertAll(
            _db.transactions, txToInsert, mode: InsertMode.insertOrIgnore));
      }
      result.transactionsInserted = txToInsert.length;

      // ---- 预算：家庭级单条 -> 当前家庭当月 ----
      if (budgets.isNotEmpty) {
        final amount = (budgets.first['amount'] as num?)?.toDouble();
        if (amount != null) {
          final existing = await (_db.select(_db.budgets)
                ..where((b) =>
                    b.familyId.equals(familyId) &
                    b.year.equals(now.year) &
                    b.month.equals(now.month)))
              .getSingleOrNull();
          if (existing == null) {
            await _db.into(_db.budgets).insert(local.BudgetsCompanion.insert(
                  familyId: Value(familyId),
                  year: now.year,
                  month: now.month,
                  amount: amount,
                  updatedAt: Value(now),
                ));
            result.budgetsImported = 1;
          }
        }
      }

      // ---- FTS 全量重建 ----
      // 导入器直写主表 batch 绕过了 Repository 的 FTS 双写，历史导入
      // 数据不在搜索索引中（真机 5.8 验证：关键词搜不到任何导入交易）。
      // 导入末尾统一重建：回填存量 + 覆盖本次新增，幂等可重复执行。
      await _rebuildFts();
    });
    return result;
  }

  /// 全量重建 FTS 索引：清空后按 Repository 同规则回填全部未删除交易
  /// （描述 + 交易对方，中文拆字）。墓碑行不进索引。
  Future<void> _rebuildFts() async {
    await _db.customStatement('DELETE FROM transactions_fts');
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.deleted.equals(false)))
        .get();
    for (final row in rows) {
      final parts = [row.description, row.counterparty]
          .whereType<String>()
          .where((s) => s.isNotEmpty);
      final fts = FtsTokenizer.tokenize(parts.join(' '));
      if (fts.isEmpty) continue;
      await _db.customInsert(
        'INSERT INTO transactions_fts(fts_text, tx_id) VALUES (?, ?)',
        variables: [Variable(fts), Variable(row.id)],
      );
    }
  }
}

/// 导入结果统计（导入完成弹窗展示）
class BackupImportResult {
  int categoriesMappedBuiltin = 0; // 命中内置分类，仅映射
  int categoriesInserted = 0; // 新插入自定义分类
  int categoriesSkipped = 0; // 已存在（幂等跳过或同名映射）
  int transactionsInserted = 0;
  int transactionsSkipped = 0; // 同 ID 已存在
  int budgetsImported = 0;
  final List<String> failures = []; // 字段缺失等无法导入的行
}
