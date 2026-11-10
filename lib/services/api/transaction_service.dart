import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/local/app_database.dart' as local;
import '../../data/local/category_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/local_user.dart';
import '../../data/local/member_nicknames.dart';
import '../../data/local/statistics_repository.dart';
import '../../data/local/transaction_repository.dart';
import '../../models/transaction.dart';
import '../../sync/sync_scheduler.dart';
import '../../utils/error_helper.dart';
import '../../utils/money.dart';

/// 交易数据门面：本地优先架构下的唯一读写入口。
///
/// 对外保持既有 Service 签名与返回结构（页面零改动），内部全部读写本地库，
/// 不发起任何网络请求。分类参数为分类 ID（分类中性化后名称不参与写入，
/// 方向只由 type 决定）。
class TransactionService {
  static TransactionService? _instance;
  static int _generation = -1;

  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final StatisticsRepository _stats;

  TransactionService._(
    this._transactions,
    this._categories,
    this._stats,
  );

  /// 应用内单例（本地库应用级唯一实例）。
  /// 随库世代自动重绑：Db.close() 后（登出/账号切换）重开新库时
  /// 重建实例，防止持有已关闭旧库的引用。
  factory TransactionService() {
    final g = Db.generation;
    if (_instance == null || _generation != g) {
      _instance = TransactionService._(
        Db.transactions,
        Db.categories,
        Db.statistics,
      );
      _generation = g;
    }
    return _instance!;
  }

  /// 测试专用：注入内存库构造独立实例
  @visibleForTesting
  TransactionService.withRepos(
    this._transactions,
    this._categories,
    this._stats,
  );

  /// 日期字符串（yyyy-MM-dd）转当天零点；空串转 null
  DateTime? _parseDate(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.parse(s);

  /// 日期字符串（yyyy-MM-dd）转当天最后时刻（含当天全天）
  DateTime? _parseEndOfDay(String? s) {
    final d = _parseDate(s);
    if (d == null) return null;
    return d.add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
  }

  /// 添加交易：分类按 ID 解析（分类中性化，名称不再参与写入），
  /// 方向只由 type 决定，本地生成 UUIDv7 主键
  Future<Map<String, dynamic>> addTransaction({
    required int type,
    required String categoryId,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final familyId = await CurrentFamilyStore.get();
    final cat = await _categories.findById(categoryId);
    if (cat == null || cat.deleted) {
      throw const LocalizedException(LocalizedErrorCode.categoryNotFound);
    }
    final user = await LocalUser.load();

    final row = await _transactions.insert(local.TransactionsCompanion.insert(
      type: type,
      categoryId: cat.id,
      amountCents: Money.yuanToCents(amount),
      date: _parseDate(date)!,
      userId: user?.id ?? '',
      familyId: Value(familyId),
      description: Value(note),
      payMethod: Value(location),
    ));

    // 成功提示文案由页面本地化兜底，不再依赖服务端中文消息；
    // id 返回给语音记账做「修改入口」定位
    // 发件箱后台推送（fire-and-forget，不阻塞本地操作）
    unawaited(SyncScheduler.instance.maybePush());
    return <String, dynamic>{'id': row.id};
  }

  /// 获取交易列表：明细列表、筛选、搜索共用，返回既有 Transaction 模型
  Future<List<Transaction>> getTransactions({
    int? type,
    String? startDate,
    String? endDate,
    String? date, // 单个日期参数（用于查询某一天的数据）
    String? userId, // 用户ID筛选
    String? keyword, // 搜索关键词
    int? page,
    int? pageSize,
  }) async {
    final rows = await _transactions.query(
      familyId: await CurrentFamilyStore.get(),
      type: type,
      start: _parseDate(startDate),
      end: _parseEndOfDay(endDate),
      day: _parseDate(date),
      userId: userId,
      keyword: keyword,
      page: page,
      pageSize: pageSize,
    );

    // 批量关联分类（分类被删则名称空、图标空，与服务端行为一致）
    final catIds = rows.map((r) => r.categoryId).toSet();
    final cats = await _categories.findByIds(catIds);
    final categoryById = {for (final c in cats) c.id: c};

    return rows
        .map((r) => Transaction(
              id: r.id,
              type: TransactionType.fromInt(r.type),
              category: categoryById[r.categoryId]?.name ?? '',
              categoryId: r.categoryId,
              nameKey: categoryById[r.categoryId]?.nameKey,
              icon: categoryById[r.categoryId]?.icon,
              amount: Money.centsToYuan(r.amountCents),
              date: r.date,
              userId: r.userId,
              description: r.description,
              counterparty: r.counterparty,
            ))
        .toList();
  }

  /// 更新交易：分类按 ID 写入；备注传 null 表示清空（表单语义）
  Future<Map<String, dynamic>> updateTransaction({
    required String id,
    required int type,
    required String categoryId,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final existing = await _transactions.findById(id);
    if (existing == null) {
      throw const LocalizedException(LocalizedErrorCode.transactionNotFound);
    }
    // 退款行不得改收支类型：否则退款金额会被重复计入收入/支出，
    // 且冲抵链条断裂
    if (existing.refundOfId != null &&
        existing.refundOfId!.isNotEmpty &&
        type != existing.type) {
      throw const LocalizedException(LocalizedErrorCode.refundTypeChangeNotAllowed);
    }
    final cat = await _categories.findById(categoryId);
    if (cat == null || cat.deleted) {
      throw const LocalizedException(LocalizedErrorCode.categoryNotFound);
    }

    await _transactions.update(
      id,
      local.TransactionsCompanion(
        type: Value(type),
        categoryId: Value(cat.id),
        amountCents: Value(Money.yuanToCents(amount)),
        date: Value(_parseDate(date)!),
        description: Value(note),
      ),
    );

    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
    return <String, dynamic>{};
  }

  /// 交易已累计退款额（分）。页面模型不含退款字段，
  /// 编辑改类型前按 id 查询完整行用于二次确认。
  Future<int> getRefundedCents(String id) async {
    final row = await _transactions.findById(id);
    return row?.refundedCents ?? 0;
  }

  /// 删除交易（软删除墓碑，参与后续同步）
  Future<void> deleteTransaction(String id) async {
    final existing = await _transactions.findById(id);
    if (existing == null) {
      throw const LocalizedException(LocalizedErrorCode.transactionNotFound);
    }
    await _transactions.softDelete(id);
    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
  }

  /// 获取首页数据：月度概览 + 预算 + 近期动态，全部本地聚合。
  /// 返回结构对齐既有服务端 /v1/home 响应（页面零改动）。
  /// [now] 仅供测试注入基准时间，生产不传。
  Future<Map<String, dynamic>> getHomeData([DateTime? now]) async {
    final current = now ?? DateTime.now();
    final familyId = await CurrentFamilyStore.get();
    final user = await LocalUser.load();
    final overview = await _stats.monthlyOverview(familyId, current);
    // 家庭预算进度（8.5）：预算与支出同为「已设预算成员」口径，
    // memberCount 供页面标注「预算按 X/N 位成员统计」
    final budgetProgress = await _stats.familyBudgetProgress(
        familyId, current.year, current.month);

    // 近期动态：最近 10 条，排除不计收支（type=2），口径对齐服务端
    final recent = await _transactions.recent(familyId, 10);

    // 归属者昵称：成员昵称缓存 → 本人 LocalUser → 「未知用户」
    final nicknameMap = await MemberNicknames.loadAll();

    final catIds = recent.map((r) => r.categoryId).toSet();
    final cats = await _categories.findByIds(catIds);
    final categoryById = {for (final c in cats) c.id: c};

    final activities = recent.map((r) {
      final category = categoryById[r.categoryId];
      // 标题：分类名 > 描述（兜底文案由 UI 按当前语言补全）
      final title = category?.name ?? r.description;
      final icon = category?.icon ?? 'payments';
      // 归属者：按记录 userId 走统一回退链
      final ownerName =
          MemberNicknames.displayName(nicknameMap, r.userId, user);
      return <String, dynamic>{
        'title': title,
        'nameKey': category?.nameKey,
        'icon': icon,
        'user': ownerName,
        'time': DateFormat('yyyy-MM-dd HH:mm').format(r.updatedAt),
        'date': DateFormat('yyyy-MM-dd').format(r.date),
        'amount': Money.centsToYuan(r.amountCents),
        'isIncome': r.type == 0,
        'counterparty': r.counterparty,
        'description': r.description,
      };
    }).toList();

    return <String, dynamic>{
      'balance': overview.balance,
      'income': overview.income,
      'expense': overview.expense,
      'todayExpense': overview.todayExpense,
      'yesterdayExpense': overview.yesterdayExpense,
      'budget': <String, dynamic>{
        'used': budgetProgress.used,
        'total': budgetProgress.total,
        'memberCount': budgetProgress.memberCount,
      },
      'activities': activities,
    };
  }
}
