import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../parser/bill_csv_parser.dart';
import '../../sync/sync_scheduler.dart';
import 'app_database.dart' as local;
import 'builtin_categories.dart';
import 'category_engine.dart';
import 'category_rule_loader.dart';
import 'category_rule_repository.dart';
import 'current_family_store.dart';
import 'db_provider.dart';
import 'local_user.dart';
import 'transaction_repository.dart';
import 'uuid_v7.dart';
import '../../utils/money.dart' show Money;

/// 导入预览条目：一行账单 + 引擎预填分类 + 重复单号标记。
/// categoryId 可变——预览页批量指认后就地更新
class BillImportPreviewItem {
  final ParsedBillRow row; // 退款修正后的解析行
  final bool duplicate; // 本地已存在相同单号，导入时跳过
  final bool refund; // 收/支未标注且带退款文本的行（可关联原支出）
  String categoryId; // 预填/指认分类
  bool refundLinked = false; // 预览即判定会被关联冲抵（展示按不计收支）

  BillImportPreviewItem({
    required this.row,
    required this.duplicate,
    this.refund = false,
    required this.categoryId,
  });

  bool get isUncategorized =>
      categoryId == BuiltinCategories.uncategorizedExpenseId ||
      categoryId == BuiltinCategories.uncategorizedIncomeId;
}

/// 导入结果（spec：重复导入仅提示新增条数）
class BillImportOutcome {
  final int totalCount;
  final int successCount;
  final int skipCount;
  final int failCount;
  final List<String> failures; // 失败原因（行内摘要）

  const BillImportOutcome({
    required this.totalCount,
    required this.successCount,
    required this.skipCount,
    required this.failCount,
    required this.failures,
  });
}

/// 待写入行：id 预生成（同批次退款行可直接指向原支出），关联字段可改写
class _PendingImport {
  final BillImportPreviewItem item;
  final String id = UuidV7.generate();
  final int cents;
  int type;
  String categoryId;
  String? refundOfId;
  int refundedCents = 0;

  _PendingImport(this.item)
      : type = item.row.type!,
        categoryId = item.categoryId,
        cents = Money.yuanToCents(item.row.amount);
}

/// 账单导入服务：解析行 → 预览（分类预填/重复标记）→ 批量指认回写 → 入库。
///
/// 全程本地完成，无网络请求。去重键为「平台单号 + 商家单号」组合
/// （TransactionRepository.importKey）：京东同一订单的付款行与退款行
/// 商家单号不同，属两笔独立交易，不可按单号单键合并；空单号不去重
/// （与历史账单及本次批次内重复均生效）。分类未命中走「未分类」兜底入库，
/// 不阻塞、不猜测填充（spec：不得猜测填充未经确认的具体分类）。
class BillImportService {
  static BillImportService? _instance;
  static int _generation = -1;

  final TransactionRepository _transactions;
  final CategoryRuleRepository _rules;
  final CategoryEngine _engine;

  BillImportService.withRepos(
    this._transactions,
    this._rules,
    this._engine,
  );

  /// 应用内单例：Db 单例仓储 + 内置规则加载的分类引擎。
  /// 随库世代自动重绑：Db.close() 后（登出/账号切换）重开新库时
  /// 重建实例，防止持有已关闭旧库的引用。
  static Future<BillImportService> instance() async {
    final g = Db.generation;
    if (_instance == null || _generation != g) {
      _instance = BillImportService.withRepos(
        Db.transactions,
        Db.categoryRules,
        await CategoryRuleLoader.loadDefaultEngine(),
      );
      _generation = g;
    }
    return _instance!;
  }

  /// 预览准备：退款修正（仅收/支未标注的退款行转收入）+
  /// 引擎分类预填 + 本地重复单号标记。家庭维度：当前家庭内去重
  Future<List<BillImportPreviewItem>> prepare(List<ParsedBillRow> rows) async {
    final corrected = rows.map(_applyRefundRule).toList();
    final typeCache = await _engine.loadCategoryTypeCache();
    final familyId = await CurrentFamilyStore.get();

    final tradeNos = corrected
        .map((r) => r.tradeNo)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    final existing =
        await _transactions.findExistingImportKeys(familyId, tradeNos);

    final items = <BillImportPreviewItem>[];
    for (var i = 0; i < corrected.length; i++) {
      final row = corrected[i];
      final categoryId = await _engine.classify(
        [row.counterparty, row.description],
        expectedType: row.type == 2 ? 1 : row.type,
        categoryTypeCache: typeCache,
      );
      items.add(BillImportPreviewItem(
        row: row,
        duplicate: row.tradeNo != null &&
            existing.contains(
              TransactionRepository.importKey(row.tradeNo!, row.merchantOrderNo),
            ),
        refund: _isRefundRow(rows[i]),
        categoryId: categoryId ?? _fallbackCategoryId(row.type),
      ));
    }
    // 预览即判定退款行能否关联冲抵，避免预览按收入展示、入库后变不计收支
    await _markRefundLinks(items, familyId);
    return items;
  }

  /// 预判退款关联（与导入时的判定规则一致）：同单号支出行 + 退款额不超剩余可退额。
  /// 命中：标记 refundLinked 并沿用原支出分类（金额仍按正数展示）
  Future<void> _markRefundLinks(
      List<BillImportPreviewItem> items, String familyId) async {
    final batchExpenses = <String, BillImportPreviewItem>{};
    for (final item in items) {
      if (item.duplicate || item.row.type != 1) continue;
      final tradeNo = item.row.tradeNo;
      if (tradeNo == null || tradeNo.isEmpty) continue;
      batchExpenses.putIfAbsent(tradeNo, () => item);
    }

    final refundTradeNos = items
        .where((i) => !i.duplicate && i.refund)
        .map((i) => i.row.tradeNo)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    final dbExpenses =
        await _transactions.findLinkableExpenses(familyId, refundTradeNos);
    final dbByTradeNo = <String, local.Transaction>{};
    for (final e in dbExpenses) {
      dbByTradeNo.putIfAbsent(e.tradeNo!, () => e);
    }

    final batchRefunded = <String, int>{};
    final dbRefunded = <String, int>{};
    for (final item in items) {
      if (item.duplicate || !item.refund) continue;
      final tradeNo = item.row.tradeNo;
      if (tradeNo == null || tradeNo.isEmpty) continue;
      final cents = Money.yuanToCents(item.row.amount);

      final batch = batchExpenses[tradeNo];
      if (batch != null) {
        final used = batchRefunded[tradeNo] ?? 0;
        if (Money.yuanToCents(batch.row.amount) - used < cents) continue;
        batchRefunded[tradeNo] = used + cents;
        item
          ..refundLinked = true
          ..categoryId = batch.categoryId;
        continue;
      }

      final db = dbByTradeNo[tradeNo];
      if (db == null) continue;
      final used = db.refundedCents + (dbRefunded[db.id] ?? 0);
      if (db.amountCents - used < cents) continue;
      dbRefunded[db.id] = used + cents;
      item
        ..refundLinked = true
        ..categoryId = db.categoryId;
    }
  }

  /// 批量指认回写学习表（matchText = 交易对方，source = 0 账单导入）。
  /// 预览页组内条目的 categoryId 由调用方就地更新
  Future<void> assignCategory({
    required String counterparty,
    required String categoryId,
  }) {
    return _rules.assign(
      matchText: counterparty,
      categoryId: categoryId,
      source: 0,
    );
  }

  /// 入库：重复单号跳过、收/支未知行判失败、退款行关联原支出后批量写入。
  /// 家庭维度：写入当前家庭，同家庭内去重。
  ///
  /// 净额法：能关联到原支出（同单号、支出行、退款额不超剩余可退额）的退款行
  /// 落 type=2（不计收支）并挂 refundOfId，原支出累计 refundedCents；
  /// 关联失败的退款行保留原行为（独立收入行），金额与统计不受影响
  Future<BillImportOutcome> importRows(List<BillImportPreviewItem> items) async {
    final familyId = await CurrentFamilyStore.get();
    // 导入时刻重新查询已存在单号（prepare 与导入之间可能已有写入）
    final tradeNos = items
        .where((i) => !i.duplicate)
        .map((i) => i.row.tradeNo)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    final seen = await _transactions.findExistingImportKeys(familyId, tradeNos);

    var skipCount = 0;
    var failCount = 0;
    final failures = <String>[];
    final accepted = <BillImportPreviewItem>[];
    final user = await LocalUser.load();

    for (final item in items) {
      if (item.duplicate) {
        skipCount++;
        continue;
      }
      final tradeNo = item.row.tradeNo;
      if (tradeNo != null && tradeNo.isNotEmpty) {
        final key = TransactionRepository.importKey(
            tradeNo, item.row.merchantOrderNo);
        if (seen.contains(key)) {
          skipCount++; // 历史已存在或本次批次内重复
          continue;
        }
        seen.add(key);
      }
      if (item.row.type == null) {
        failCount++;
        failures.add('收/支类型未知: ${item.row.description ?? tradeNo ?? ''}');
        continue;
      }
      accepted.add(item);
    }

    // 待写入行：id 预生成，便于同批次退款行直接指向原支出
    final pending = [
      for (final item in accepted) _PendingImport(item),
    ];

    // 同批次支出行：同单号取业务日期最早一笔
    final batchExpenses = <String, _PendingImport>{};
    for (final p in pending) {
      final tradeNo = p.item.row.tradeNo;
      if (p.type == 1 && tradeNo != null && tradeNo.isNotEmpty) {
        batchExpenses.putIfAbsent(tradeNo, () => p);
      }
    }

    // 库中已存在支出：一次批量查询，避免逐条单查
    final refundTradeNos = pending
        .where((p) => p.item.refund)
        .map((p) => p.item.row.tradeNo)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    final dbExpenses = await _transactions.findLinkableExpenses(
        familyId, refundTradeNos);
    final dbByTradeNo = <String, local.Transaction>{};
    for (final e in dbExpenses) {
      dbByTradeNo.putIfAbsent(e.tradeNo!, () => e);
    }
    final dbDeltas = <String, int>{};

    // 退款行关联：不超剩余可退额才关联，否则降级为独立收入行
    for (final p in pending) {
      if (!p.item.refund) continue;
      var linked = false;
      final tradeNo = p.item.row.tradeNo;
      if (tradeNo != null && tradeNo.isNotEmpty) {
        final cents = p.cents;
        final batchTarget = batchExpenses[tradeNo];
        if (batchTarget != null) {
          if (batchTarget.cents - batchTarget.refundedCents >= cents) {
            p
              ..type = 2
              ..refundOfId = batchTarget.id
              ..categoryId = batchTarget.categoryId;
            batchTarget.refundedCents += cents;
            linked = true;
          }
        } else {
          final dbTarget = dbByTradeNo[tradeNo];
          if (dbTarget != null) {
            final alreadyRefunded =
                dbTarget.refundedCents + (dbDeltas[dbTarget.id] ?? 0);
            if (dbTarget.amountCents - alreadyRefunded >= cents) {
              p
                ..type = 2
                ..refundOfId = dbTarget.id
                ..categoryId = dbTarget.categoryId;
              dbDeltas[dbTarget.id] = alreadyRefunded + cents;
              linked = true;
            }
          }
        }
      }
      // 预览已按冲抵展示但入库时无可关联目标（如另一端已删改），回退收入口径
      if (!linked && p.item.refundLinked) {
        p.categoryId = _fallbackCategoryId(0);
      }
    }

    final toInsert = [
      for (final p in pending)
        local.TransactionsCompanion.insert(
          id: Value(p.id),
          type: p.type,
          categoryId: p.categoryId,
          amountCents: p.cents,
          date: p.item.row.date,
          userId: user?.id ?? '',
          familyId: Value(familyId),
          description: Value(p.item.row.description),
          counterparty: Value(p.item.row.counterparty),
          tradeNo: Value(p.item.row.tradeNo),
          merchantOrderNo: Value(p.item.row.merchantOrderNo),
          payMethod: Value(p.item.row.payMethod),
          platform: Value(kBillPlatformNames[p.item.row.platformCode]),
          refundOfId: Value(p.refundOfId),
          refundedCents: Value(p.refundedCents),
        ),
    ];

    await _transactions.insertAll(toInsert);
    if (dbDeltas.isNotEmpty) {
      await _transactions.addRefundedCents(dbDeltas);
    }
    // 发件箱后台推送（fire-and-forget；本次无新增则不触发）
    if (toInsert.isNotEmpty) {
      unawaited(SyncScheduler.instance.maybePush());
    }

    return BillImportOutcome(
      totalCount: items.length,
      successCount: toInsert.length,
      skipCount: skipCount,
      failCount: failCount,
      failures: failures,
    );
  }

  /// 退款规则守卫：账单明确标注收支方向的行（type=0 收入、type=1 支出）
  /// 永不被文本改写；仅收/支未标注的行（type=2）可凭描述/状态含「退款」
  /// 佐证转为收入入账（全额退款净 0、部分退款净余支出，如实入账自然对）
  ParsedBillRow _applyRefundRule(ParsedBillRow row) {
    if (!_isRefundRow(row)) return row;
    return ParsedBillRow(
      platformCode: row.platformCode,
      tradeNo: row.tradeNo,
      merchantOrderNo: row.merchantOrderNo,
      date: row.date,
      amount: row.amount,
      type: 0,
      counterparty: row.counterparty,
      description: row.description,
      payMethod: row.payMethod,
      status: row.status,
    );
  }

  /// 收/支未标注且带退款文本证据的行（可关联原支出，做净额冲抵）
  bool _isRefundRow(ParsedBillRow row) {
    if (row.type != 2) return false;
    return (row.description?.contains('退款') ?? false) ||
        (row.status?.contains('退款') ?? false);
  }

  /// 未分类兜底：收入挂收入侧未分类，支出/不计收支挂支出侧未分类
  String _fallbackCategoryId(int? type) {
    return type == 0
        ? BuiltinCategories.uncategorizedIncomeId
        : BuiltinCategories.uncategorizedExpenseId;
  }
}
