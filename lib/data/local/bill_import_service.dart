import 'package:drift/drift.dart' show Value;

import '../../parser/bill_csv_parser.dart';
import 'app_database.dart' as local;
import 'builtin_categories.dart';
import 'category_engine.dart';
import 'category_rule_loader.dart';
import 'category_rule_repository.dart';
import 'current_family_store.dart';
import 'db_provider.dart';
import 'local_user.dart';
import 'transaction_repository.dart';
import '../../utils/money.dart' show Money;

/// 导入预览条目：一行账单 + 引擎预填分类 + 重复单号标记。
/// categoryId 可变——预览页批量指认后就地更新
class BillImportPreviewItem {
  final ParsedBillRow row; // 退款修正后的解析行
  final bool duplicate; // 本地已存在相同单号，导入时跳过
  String categoryId; // 预填/指认分类

  BillImportPreviewItem({
    required this.row,
    required this.duplicate,
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

/// 账单导入服务：解析行 → 预览（分类预填/重复标记）→ 批量指认回写 → 入库。
///
/// 全程本地完成，无网络请求。去重按平台单号（tradeNo）单键，空单号不去重
/// （对齐 spec「依据交易单号去重」，同一单号不重复入库；与历史账单及
/// 本次批次内重复均生效）。分类未命中走「未分类」兜底入库，不阻塞、
/// 不猜测填充（spec：不得猜测填充未经确认的具体分类）。
class BillImportService {
  static BillImportService? _instance;

  final TransactionRepository _transactions;
  final CategoryRuleRepository _rules;
  final CategoryEngine _engine;

  BillImportService.withRepos(
    this._transactions,
    this._rules,
    this._engine,
  );

  /// 应用内单例：Db 单例仓储 + 内置规则加载的分类引擎
  static Future<BillImportService> instance() async {
    _instance ??= BillImportService.withRepos(
      Db.transactions,
      Db.categoryRules,
      await CategoryRuleLoader.loadDefaultEngine(),
    );
    return _instance!;
  }

  /// 预览准备：退款修正（描述/状态含「退款」→ 收入，对齐服务端）+
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
        await _transactions.findExistingTradeNos(familyId, tradeNos);

    final items = <BillImportPreviewItem>[];
    for (final row in corrected) {
      final categoryId = await _engine.classify(
        [row.counterparty, row.description],
        expectedType: row.type == 2 ? 1 : row.type,
        categoryTypeCache: typeCache,
      );
      items.add(BillImportPreviewItem(
        row: row,
        duplicate:
            row.tradeNo != null && existing.contains(row.tradeNo),
        categoryId: categoryId ?? _fallbackCategoryId(row.type),
      ));
    }
    return items;
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

  /// 入库：重复单号跳过、收/支未知行判失败、其余批量写入本地库。
  /// 家庭维度：写入当前家庭，同家庭内去重
  Future<BillImportOutcome> importRows(List<BillImportPreviewItem> items) async {
    final familyId = await CurrentFamilyStore.get();
    // 导入时刻重新查询已存在单号（prepare 与导入之间可能已有写入）
    final tradeNos = items
        .where((i) => !i.duplicate)
        .map((i) => i.row.tradeNo)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    final seen = await _transactions.findExistingTradeNos(familyId, tradeNos);

    var skipCount = 0;
    var failCount = 0;
    final failures = <String>[];
    final toInsert = <local.TransactionsCompanion>[];
    final user = await LocalUser.load();

    for (final item in items) {
      if (item.duplicate) {
        skipCount++;
        continue;
      }
      final tradeNo = item.row.tradeNo;
      if (tradeNo != null && tradeNo.isNotEmpty) {
        if (seen.contains(tradeNo)) {
          skipCount++; // 历史已存在或本次批次内重复
          continue;
        }
        seen.add(tradeNo);
      }
      final type = item.row.type;
      if (type == null) {
        failCount++;
        failures.add('收/支类型未知: ${item.row.description ?? tradeNo ?? ''}');
        continue;
      }

      toInsert.add(local.TransactionsCompanion.insert(
        type: type,
        categoryId: item.categoryId,
        amountCents: Money.yuanToCents(item.row.amount),
        date: item.row.date,
        userId: user?.id ?? '',
        familyId: Value(familyId),
        description: Value(item.row.description),
        counterparty: Value(item.row.counterparty),
        tradeNo: Value(tradeNo),
        merchantOrderNo: Value(item.row.merchantOrderNo),
        payMethod: Value(item.row.payMethod),
        platform:
            Value(kBillPlatformNames[item.row.platformCode]),
      ));
    }

    await _transactions.insertAll(toInsert);

    return BillImportOutcome(
      totalCount: items.length,
      successCount: toInsert.length,
      skipCount: skipCount,
      failCount: failCount,
      failures: failures,
    );
  }

  /// 退款规则：描述或交易状态含「退款」→ 强制收入类型（对齐服务端导入语义）
  ParsedBillRow _applyRefundRule(ParsedBillRow row) {
    final isRefund = (row.description?.contains('退款') ?? false) ||
        (row.status?.contains('退款') ?? false);
    if (!isRefund || row.type == 0) return row;
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

  /// 未分类兜底：收入挂收入侧未分类，支出/不计收支挂支出侧未分类
  String _fallbackCategoryId(int? type) {
    return type == 0
        ? BuiltinCategories.uncategorizedIncomeId
        : BuiltinCategories.uncategorizedExpenseId;
  }
}
