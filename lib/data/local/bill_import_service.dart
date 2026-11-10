import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../parser/bill_csv_parser.dart';
import '../../sync/sync_scheduler.dart';
import 'app_database.dart' as local;
import 'bill_category_mapper.dart';
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

  bool get isUncategorized => categoryId == BuiltinCategories.uncategorizedId;
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
      // 统一四层链路，对所有平台（含微信）一视同仁：
      // 学习表 → 平台分类列（可信度分级）→ 关键词规则 → 未分类。
      // type=2 不计收支的行不参与任何分类推断。
      String? categoryId;
      if (row.type != 2) {
        categoryId =
            await _engine.matchLearned([row.counterparty, row.description]);
        categoryId ??= BillCategoryMapper.mapRow(row);
        categoryId ??=
            await _engine.classifyKeywords([row.counterparty, row.description]);
      }
      items.add(BillImportPreviewItem(
        row: row,
        duplicate: row.tradeNo != null &&
            existing.contains(
              TransactionRepository.importKey(row.tradeNo!, row.merchantOrderNo),
            ),
        refund: _isRefundRow(rows[i]) || _wechatIsRefundRow(rows[i]),
        categoryId: categoryId ?? _fallbackCategoryId,
      ));
    }
    // 预览即判定退款行能否关联冲抵，避免预览按收入展示、入库后变不计收支
    await _markRefundLinks(items, familyId);
    // 微信独立退款行无共同单号，按「对方去 -退款 后缀 + 金额 + 日期」唯一命中关联
    await _markWechatRefundLinks(items, familyId);
    return items;
  }

  /// 预判退款关联（与导入时的判定规则一致）：同单号支出行
  /// （支付宝按首个下划线前的基单号；京东三条线索见 [_refundTradeKeys]）
  /// + 退款额不超剩余可退额 + 退款不早于原单。
  /// 命中：标记 refundLinked 并沿用原支出分类（金额仍按正数展示）
  Future<void> _markRefundLinks(
      List<BillImportPreviewItem> items, String familyId) async {
    final batchByTradeNo = <String, BillImportPreviewItem>{};
    final batchByMerchantNo = <String, BillImportPreviewItem>{};
    for (final item in items) {
      // 微信走下方按交易对方的专属关联，不参与单号匹配
      if (item.duplicate ||
          item.row.type != 1 ||
          item.row.platformCode == 'wechat') {
        continue;
      }
      final tradeNo = item.row.tradeNo;
      if (tradeNo == null || tradeNo.isEmpty) continue;
      batchByTradeNo.putIfAbsent(
          _refundLinkKey(tradeNo, item.row.platformCode), () => item);
      final merchantOrderNo = item.row.merchantOrderNo;
      if (merchantOrderNo != null && merchantOrderNo.isNotEmpty) {
        batchByMerchantNo.putIfAbsent(merchantOrderNo, () => item);
      }
    }

    final refundTradeNos = <String>{};
    final refundMerchantNos = <String>{};
    for (final i in items) {
      if (i.duplicate || !i.refund || i.row.platformCode == 'wechat') continue;
      refundTradeNos
          .addAll(_refundTradeKeys(i.row.tradeNo, i.row.merchantOrderNo,
              i.row.platformCode));
      refundMerchantNos
          .addAll(_refundMerchantKeys(i.row.tradeNo, i.row.platformCode));
    }
    final dbExpenses =
        await _transactions.findLinkableExpenses(familyId, refundTradeNos);
    final dbByTradeNo = <String, local.Transaction>{};
    for (final e in dbExpenses) {
      dbByTradeNo.putIfAbsent(e.tradeNo!, () => e);
    }
    final dbByMerchantNo = <String, local.Transaction>{};
    for (final e in await _transactions.findLinkableExpensesByMerchantOrderNo(
        familyId, refundMerchantNos)) {
      final key = e.merchantOrderNo;
      if (key != null && key.isNotEmpty) dbByMerchantNo.putIfAbsent(key, () => e);
    }

    final batchRefunded = <BillImportPreviewItem, int>{};
    final dbRefunded = <String, int>{};
    for (final item in items) {
      if (item.duplicate ||
          !item.refund ||
          item.row.platformCode == 'wechat') {
        continue;
      }
      final cents = Money.yuanToCents(item.row.amount);

      // 批次内已有候选原支出时不再跨库匹配，避免同一笔退款被算两次
      final batchPools =
          _refundPools(item.row, batchByTradeNo, batchByMerchantNo);
      if (batchPools.isNotEmpty) {
        final valid = batchPools.where((t) {
          // 京东原支出行已用括号标注退款额，不再重复冲抵
          if (_isAnchoredRefund(t.row)) return false;
          final remaining =
              Money.yuanToCents(t.row.amount) - (batchRefunded[t] ?? 0);
          if (!_refundFits(remaining, cents, item.row.platformCode)) {
            return false;
          }
          // 退款不可能早于原支付
          return !item.row.date.isBefore(t.row.date);
        }).toList();
        if (valid.length == 1) {
          final target = valid.single;
          final remaining =
              Money.yuanToCents(target.row.amount) - (batchRefunded[target] ?? 0);
          batchRefunded[target] = (batchRefunded[target] ?? 0) +
              _refundOffset(remaining, cents, item.row.platformCode);
          item
            ..refundLinked = true
            ..categoryId = target.categoryId;
        }
        continue;
      }

      final dbPools = _refundPools(item.row, dbByTradeNo, dbByMerchantNo);
      final validDb = dbPools.where((e) {
        final remaining =
            e.amountCents - e.refundedCents - (dbRefunded[e.id] ?? 0);
        return _refundFits(remaining, cents, item.row.platformCode) &&
            !item.row.date.isBefore(e.date);
      }).toList();
      if (validDb.length != 1) continue;
      final target = validDb.single;
      final remaining =
          target.amountCents - target.refundedCents - (dbRefunded[target.id] ?? 0);
      dbRefunded[target.id] = target.refundedCents +
          (dbRefunded[target.id] ?? 0) +
          _refundOffset(remaining, cents, item.row.platformCode);
      item
        ..refundLinked = true
        ..categoryId = target.categoryId;
    }
  }

  /// 微信退款预判：退款行与退款原单无共同单号，只能按交易对方关联。
  /// 候选必须同时满足「对方去 `-退款` 后缀相同 + 退款不早于原单 +
  /// 退款额不超剩余可退额」，且在批次与库中合计唯一命中才标记；
  /// 多候选/零候选一律不关联（宁可退出统计，也不虚增收入）。
  /// 原支出行状态已自带退款金额时以原行锚点为准，不参与此处关联，避免重复冲抵。
  Future<void> _markWechatRefundLinks(
      List<BillImportPreviewItem> items, String familyId) async {
    final refundItems = items
        .where((i) =>
            !i.duplicate && i.row.platformCode == 'wechat' && i.refund)
        .toList();
    if (refundItems.isEmpty) return;

    final keys = refundItems
        .map((i) => _wechatCounterpartyKey(i.row.counterparty))
        .where((k) => k.isNotEmpty)
        .toSet();
    final dbExpenses = await _transactions
        .findLinkableExpensesByCounterparty(familyId, keys);
    final dbByKey = <String, List<local.Transaction>>{};
    for (final e in dbExpenses) {
      final key = _wechatCounterpartyKey(e.counterparty);
      if (key.isEmpty) continue;
      dbByKey.putIfAbsent(key, () => []).add(e);
    }

    // 状态已锚定退款额的原支出不进入候选，避免同一笔退款被算两次
    final batchExpenses = items
        .where((i) =>
            !i.duplicate &&
            i.row.platformCode == 'wechat' &&
            i.row.type == 1 &&
            _wechatStatusRefundCents(i.row) == 0)
        .toList();
    final batchUsed = <BillImportPreviewItem, int>{};
    final dbUsed = <String, int>{};

    for (final item in refundItems) {
      final key = _wechatCounterpartyKey(item.row.counterparty);
      if (key.isEmpty) continue;
      final cents = Money.yuanToCents(item.row.amount);

      final batchCandidates = batchExpenses.where((e) {
        if (_wechatCounterpartyKey(e.row.counterparty) != key) return false;
        final remaining =
            Money.yuanToCents(e.row.amount) - (batchUsed[e] ?? 0);
        return remaining >= cents && !item.row.date.isBefore(e.row.date);
      }).toList();
      final dbCandidates = (dbByKey[key] ?? []).where((e) {
        final remaining =
            e.amountCents - e.refundedCents - (dbUsed[e.id] ?? 0);
        return remaining >= cents && !item.row.date.isBefore(e.date);
      }).toList();
      if (batchCandidates.length + dbCandidates.length != 1) continue;

      if (batchCandidates.isNotEmpty) {
        final target = batchCandidates.single;
        batchUsed[target] = (batchUsed[target] ?? 0) + cents;
        item
          ..refundLinked = true
          ..categoryId = target.categoryId;
      } else {
        final target = dbCandidates.single;
        dbUsed[target.id] = (dbUsed[target.id] ?? 0) + cents;
        item
          ..refundLinked = true
          ..categoryId = target.categoryId;
      }
    }
  }

  /// 平台汇总账户：账单里的「XX平台商户」「XX支付」是聚合收单口径，
  /// 同一名称下混着多个真实商户，写成一条学习规则会把整组拉平，永不学习。
  /// 后缀为「平台商户」的一律按汇总账户处理（覆盖各平台后续新增名称）。
  static const Set<String> _platformAggregateAccounts = {
    '淘宝闪购',
    '京东外卖',
    '京东支付',
    '京东白条',
    '京东金融',
    '京东小金库',
    '京东物流',
    '支付宝',
    '微信支付',
    '财付通',
    '财付通支付科技有限公司',
  };

  /// 是否属于平台汇总账户（学习表黑名单）
  static bool isPlatformAggregateAccount(String counterparty) {
    final key = counterparty.trim().toLowerCase();
    if (key.isEmpty) return false;
    if (key.endsWith('平台商户')) return true;
    return _platformAggregateAccounts.contains(key);
  }

  /// 学习表写入守卫：
  /// - 平台汇总账户永不学习（同一名称下混着多个真实商户）；
  /// - 同一交易对方在本轮预填里已跨多个具体分类时不学习，
  ///   避免第二次导入把整组拉平成同一个分类。
  ///   未分类只是「还没认出来」，不算分类信号，不参与跨界判定。
  static bool shouldLearn(String counterparty, {Set<String>? roundCategories}) {
    if (isPlatformAggregateAccount(counterparty)) return false;
    if (roundCategories == null) return true;
    final known = roundCategories
        .where((id) => id != BuiltinCategories.uncategorizedId)
        .toSet();
    return known.length <= 1;
  }

  /// 批量指认回写学习表（matchText = 交易对方，source = 0 账单导入）。
  /// 匹配键由仓储统一归一化，预览页组内条目的 categoryId 由调用方就地更新。
  /// [roundCategories] 为该商户本轮预填的分类集合（指认前快照），
  /// 用于识别跨多个分类的商户并跳过学习。
  Future<void> assignCategory({
    required String counterparty,
    required String categoryId,
    Set<String>? roundCategories,
  }) async {
    if (!shouldLearn(counterparty, roundCategories: roundCategories)) return;
    await _rules.assign(
      matchText: counterparty,
      categoryId: categoryId,
      source: 0,
    );
  }

  /// 清空学习表（全部软删除），返回清掉的条数。
  /// 学习表置顶后既有错误指认会立即生效，导入页需要这条后路。
  Future<int> clearLearningTable() => _rules.clearAll();

  /// 入库：重复单号跳过、收/支未知行判失败、退款行关联原支出后批量写入。
  /// 家庭维度：写入当前家庭，同家庭内去重。
  ///
  /// 净额法：能关联到原支出（同单号、支出行、退款额不超剩余可退额、
  /// 退款不早于原单）的退款行落 type=2（不计收支）并挂 refundOfId，
  /// 原支出累计 refundedCents；支付宝按基单号匹配，未关联时保持不计收支，
  /// 其他平台未关联时仍按退款文本降级为独立收入行
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

    // 微信/京东原支出行：账单自带退款额（微信在交易状态、京东在金额括号），
    // 以原行自身金额为上限直接锚定，无需跨行匹配。京东锚定后不再接受
    // 独立退款行重复冲抵（见 [_isAnchoredRefund]）
    for (final p in pending) {
      final annotated = p.item.row.refundedAmount;
      if (p.item.row.platformCode == 'jd' && annotated != null) {
        final cents = Money.yuanToCents(annotated);
        p.refundedCents = cents > p.cents ? p.cents : cents;
        continue;
      }
      if (p.item.row.platformCode == 'wechat' && p.type == 1) {
        p.refundedCents = _wechatStatusRefundCents(p.item.row);
      }
    }

    // 同批次支出行：同单号取业务日期最早一笔（支付宝按基单号归并）；
    // 京东退款行可能反查原单商家单号，另行建索引
    final batchByTradeNo = <String, _PendingImport>{};
    final batchByMerchantNo = <String, _PendingImport>{};
    for (final p in pending) {
      final tradeNo = p.item.row.tradeNo;
      if (p.type != 1 || tradeNo == null || tradeNo.isEmpty) continue;
      batchByTradeNo.putIfAbsent(
          _refundLinkKey(tradeNo, p.item.row.platformCode), () => p);
      final merchantOrderNo = p.item.row.merchantOrderNo;
      if (merchantOrderNo != null && merchantOrderNo.isNotEmpty) {
        batchByMerchantNo.putIfAbsent(merchantOrderNo, () => p);
      }
    }

    // 库中已存在支出：一次批量查询，避免逐条单查
    final refundTradeNos = <String>{};
    final refundMerchantNos = <String>{};
    for (final p in pending) {
      if (!p.item.refund) continue;
      refundTradeNos.addAll(_refundTradeKeys(p.item.row.tradeNo,
          p.item.row.merchantOrderNo, p.item.row.platformCode));
      refundMerchantNos.addAll(
          _refundMerchantKeys(p.item.row.tradeNo, p.item.row.platformCode));
    }
    final dbExpenses = await _transactions.findLinkableExpenses(
        familyId, refundTradeNos);
    final dbByTradeNo = <String, local.Transaction>{};
    for (final e in dbExpenses) {
      dbByTradeNo.putIfAbsent(e.tradeNo!, () => e);
    }
    final dbByMerchantNo = <String, local.Transaction>{};
    for (final e in await _transactions.findLinkableExpensesByMerchantOrderNo(
        familyId, refundMerchantNos)) {
      final key = e.merchantOrderNo;
      if (key != null && key.isNotEmpty) {
        dbByMerchantNo.putIfAbsent(key, () => e);
      }
    }
    final dbDeltas = <String, int>{};

    // 退款行关联：不超剩余可退额才关联；未关联时一律保持不计收支。
    // 京东原行已用金额括号锚定退款额的，不再重复冲抵
    for (final p in pending) {
      // 微信退款行无共同单号，走下方交易对方唯一匹配
      if (!p.item.refund || p.item.row.platformCode == 'wechat') continue;
      var linked = false;
      final cents = p.cents;
      final batchPools =
          _refundPools(p.item.row, batchByTradeNo, batchByMerchantNo);
      if (batchPools.isNotEmpty) {
        final valid = batchPools.where((t) {
          if (_isAnchoredRefund(t.item.row)) return false;
          final remaining = t.cents - t.refundedCents;
          return _refundFits(remaining, cents, p.item.row.platformCode) &&
              !p.item.row.date.isBefore(t.item.row.date);
        }).toList();
        if (valid.length == 1) {
          final target = valid.single;
          p
            ..type = 2
            ..refundOfId = target.id
            ..categoryId = target.categoryId;
          target.refundedCents += _refundOffset(
              target.cents - target.refundedCents, cents,
              p.item.row.platformCode);
          linked = true;
        }
      } else {
        final dbPools = _refundPools(p.item.row, dbByTradeNo, dbByMerchantNo);
        final validDb = dbPools.where((e) {
          final remaining =
              e.amountCents - e.refundedCents - (dbDeltas[e.id] ?? 0);
          return _refundFits(remaining, cents, p.item.row.platformCode) &&
              !p.item.row.date.isBefore(e.date);
        }).toList();
        if (validDb.length == 1) {
          final target = validDb.single;
          p
            ..type = 2
            ..refundOfId = target.id
            ..categoryId = target.categoryId;
          final remaining =
              target.amountCents - target.refundedCents - (dbDeltas[target.id] ?? 0);
          dbDeltas[target.id] = target.refundedCents +
              (dbDeltas[target.id] ?? 0) +
              _refundOffset(remaining, cents, p.item.row.platformCode);
          linked = true;
        }
      }

      // 预览已按冲抵展示但入库时无可关联目标（如另一端已删改）：
      // 京东退款行仍是不计收支，其余平台回退收入分类
      if (!linked && p.item.refundLinked) {
        p.categoryId = _fallbackCategoryId;
      }
    }

    // 微信独立退款行：原账单常标为「收入」且与原单无共同单号。
    // 一律落 type=2（不计收支），能唯一关联原支出时挂 refundOfId 冲抵；
    // 零候选/多候选保持不计收支，绝不改回收入虚增统计。
    final wechatRefundRows = pending
        .where((p) =>
            p.item.refund && p.item.row.platformCode == 'wechat')
        .toList();
    for (final p in wechatRefundRows) {
      p.type = 2;
    }
    if (wechatRefundRows.isNotEmpty) {
      final keys = wechatRefundRows
          .map((p) => _wechatCounterpartyKey(p.item.row.counterparty))
          .where((k) => k.isNotEmpty)
          .toSet();
      final wechatDbExpenses = await _transactions
          .findLinkableExpensesByCounterparty(familyId, keys);
      final dbByKey = <String, List<local.Transaction>>{};
      for (final e in wechatDbExpenses) {
        final key = _wechatCounterpartyKey(e.counterparty);
        if (key.isEmpty) continue;
        dbByKey.putIfAbsent(key, () => []).add(e);
      }
      // 状态已锚定退款额的原支出不参与关联，避免同一笔退款被算两次
      final wechatExpenses = pending
          .where((p) =>
              p.type == 1 &&
              p.item.row.platformCode == 'wechat' &&
              p.refundedCents == 0)
          .toList();

      for (final p in wechatRefundRows) {
        final key = _wechatCounterpartyKey(p.item.row.counterparty);
        if (key.isEmpty) continue;
        final batchCandidates = wechatExpenses.where((e) =>
            _wechatCounterpartyKey(e.item.row.counterparty) == key &&
            e.cents - e.refundedCents >= p.cents &&
            !p.item.row.date.isBefore(e.item.row.date)).toList();
        final dbCandidates = (dbByKey[key] ?? []).where((e) {
          final used = e.refundedCents + (dbDeltas[e.id] ?? 0);
          return e.amountCents - used >= p.cents &&
              !p.item.row.date.isBefore(e.date);
        }).toList();
        if (batchCandidates.length + dbCandidates.length != 1) continue;

        if (batchCandidates.isNotEmpty) {
          final target = batchCandidates.single;
          p
            ..refundOfId = target.id
            ..categoryId = target.categoryId;
          target.refundedCents += p.cents;
        } else {
          final target = dbCandidates.single;
          p
            ..refundOfId = target.id
            ..categoryId = target.categoryId;
          dbDeltas[target.id] = (dbDeltas[target.id] ?? 0) + p.cents;
        }
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
  /// 永不被文本改写；退款行只按平台口径归入不计收支或冲抵原支出
  ///
  /// - 支付宝：退款行已被官方明确标为「不计收支」，不得改写成收入，
  ///   改由净额法按基单号关联原支出冲抵
  /// - 微信：退款语义行（含状态/交易类型/对方「对方已退还」）一律不计收支
  /// - 京东：退款行恒为不计收支，绝不转收入（京东无「退款收入」）
  ParsedBillRow _applyRefundRule(ParsedBillRow row) {
    if (row.platformCode == 'alipay') return row;
    if (row.platformCode == 'wechat') {
      if (!_wechatIsRefundRow(row)) return row;
      return _withType(row, 2);
    }
    // 京东：退款行恒为不计收支，绝不转收入。京东账单没有「退款收入」，
    // 退款只是原支出的负向冲抵；超出剩余可退额的部分同样留在不计收支
    return row;
  }

  /// 京东原支出行已用金额括号标注退款额（如 `100.00(已退款10.00)`），
  /// 该行已按标注锚定，独立退款行不得再次冲抵
  bool _isAnchoredRefund(ParsedBillRow row) =>
      row.platformCode == 'jd' && row.refundedAmount != null;

  /// 收/支未标注且带退款文本证据的行（可关联原支出，做净额冲抵）
  bool _isRefundRow(ParsedBillRow row) {
    if (row.type != 2) return false;
    return (row.description?.contains('退款') ?? false) ||
        (row.status?.contains('退款') ?? false);
  }

  /// 微信独立退款行：原账单标为收入（或已是不计收支）且带退款语义。
  /// 支出行是原单锚点，不在此列；「对方已退还」不含「退款」二字但同属退款。
  /// 交易类型含 `-退款` 时微信商品列会回退成「交易类型/交易对方」，故一并识别。
  bool _wechatIsRefundRow(ParsedBillRow row) {
    if (row.platformCode != 'wechat' || row.type == 1) return false;
    final status = row.status ?? '';
    final description = row.description ?? '';
    final counterparty = row.counterparty ?? '';
    return status.contains('退款') ||
        status.contains('对方已退还') ||
        description.contains('-退款') ||
        counterparty.contains('-退款');
  }

  /// 微信原支出行状态里的退款金额（分）；无退款语义返回 0。
  /// 支持「已全额退款」「对方已退还」整笔退款，及「已退款(¥10.00)」
  /// 「已退款¥10.00」部分退款。以原行金额为上限，避免异常状态超退。
  int _wechatStatusRefundCents(ParsedBillRow row) {
    final status = row.status;
    if (status == null) return 0;
    final amountCents = Money.yuanToCents(row.amount);
    if (status.contains('已全额退款') || status.contains('对方已退还')) {
      return amountCents;
    }
    final match = RegExp(r'已退款[（(]?[¥￥]?\s*([0-9][0-9,]*(?:\.[0-9]+)?)')
        .firstMatch(status);
    if (match == null) return 0;
    final cents = Money.yuanToCents(
        double.parse(match.group(1)!.replaceAll(',', '')));
    return cents > amountCents ? amountCents : cents;
  }

  /// 微信退款关联用交易对方键：去掉 `-退款` 后缀；「/」是无值占位返回空。
  String _wechatCounterpartyKey(String? counterparty) {
    final s = counterparty?.trim() ?? '';
    if (s.isEmpty || s == '/') return '';
    return s.endsWith('-退款')
        ? s.substring(0, s.length - '-退款'.length).trim()
        : s;
  }

  /// 复制解析行并改写收支类型（仅字段透传，不做其他变更）
  ParsedBillRow _withType(ParsedBillRow row, int type) {
    return ParsedBillRow(
      platformCode: row.platformCode,
      tradeNo: row.tradeNo,
      merchantOrderNo: row.merchantOrderNo,
      date: row.date,
      amount: row.amount,
      type: type,
      counterparty: row.counterparty,
      description: row.description,
      payMethod: row.payMethod,
      status: row.status,
      refundedAmount: row.refundedAmount,
    );
  }

  /// 退款关联键：支付宝退款单号为「原单号 + 后缀」（`_M…`/`_INP…`/19 位数字），
  /// 取首个下划线前的基单号；其他平台保持精确单号（京东付款行与退款行同号）。
  /// 禁止用金额做匹配键（同额行过多会误连）
  String _refundLinkKey(String tradeNo, String platformCode) {
    if (platformCode != 'alipay') return tradeNo;
    final i = tradeNo.indexOf('_');
    return i > 0 ? tradeNo.substring(0, i) : tradeNo;
  }

  /// 退款行用于匹配原支出的交易单号线索：
  /// - 各平台：退款行交易单号（支付宝取基单号）
  /// - 京东：商家单号形如 `流水号-原交易订单号`，尾段即原单交易单号
  Set<String> _refundTradeKeys(
      String? tradeNo, String? merchantOrderNo, String platformCode) {
    final keys = <String>{};
    if (tradeNo != null && tradeNo.isNotEmpty) {
      keys.add(_refundLinkKey(tradeNo, platformCode));
    }
    if (platformCode == 'jd' && merchantOrderNo != null) {
      final i = merchantOrderNo.lastIndexOf('-');
      if (i > 0 && i < merchantOrderNo.length - 1) {
        keys.add(merchantOrderNo.substring(i + 1));
      }
    }
    keys.remove('');
    return keys;
  }

  /// 退款行用于匹配原支出商家单号的线索：京东退款行交易单号可能等于
  /// 原单商家单号（部分票务类商户退款即此形态，方向与原单相反）
  Set<String> _refundMerchantKeys(String? tradeNo, String platformCode) {
    if (platformCode != 'jd' || tradeNo == null || tradeNo.isEmpty) {
      return const {};
    }
    return {tradeNo};
  }

  /// 退款能否关联到该原支出：京东允许超额（封顶冲抵），
  /// 其余平台保持「退款额不得超剩余可退额」的原口径
  bool _refundFits(int remaining, int cents, String platformCode) {
    if (remaining <= 0) return false;
    return platformCode == 'jd' ? true : remaining >= cents;
  }

  /// 实际冲抵额：京东超额部分封顶在剩余可退额，超出部分留作不计收支
  int _refundOffset(int remaining, int cents, String platformCode) {
    if (platformCode != 'jd' || remaining >= cents) return cents;
    return remaining;
  }

  /// 退款行可能指向的原支出（交易单号线索 + 商家单号线索取并集）。
  /// 单号相同但两处索引指向同一行时自动去重
  List<T> _refundPools<T>(
    ParsedBillRow refund,
    Map<String, T> byTradeNo,
    Map<String, T> byMerchantNo,
  ) {
    final pools = <T>{};
    for (final key in _refundTradeKeys(
        refund.tradeNo, refund.merchantOrderNo, refund.platformCode)) {
      final target = byTradeNo[key];
      if (target != null) pools.add(target);
    }
    for (final key in _refundMerchantKeys(refund.tradeNo, refund.platformCode)) {
      final target = byMerchantNo[key];
      if (target != null) pools.add(target);
    }
    return pools.toList();
  }

  /// 未分类兜底：分类中性化后只有一个未分类 ID（方向由 transactions.type 决定）
  String get _fallbackCategoryId => BuiltinCategories.uncategorizedId;
}
