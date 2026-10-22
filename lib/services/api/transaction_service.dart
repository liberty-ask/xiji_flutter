import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/local/app_database.dart' as local;
import '../../data/local/category_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/local_user.dart';
import '../../data/local/statistics_repository.dart';
import '../../data/local/transaction_repository.dart';
import '../../models/transaction.dart';
import '../../utils/money.dart';

/// 交易数据门面：本地优先架构下的唯一读写入口。
///
/// 对外保持既有 Service 签名与返回结构（页面零改动），内部全部读写本地库，
/// 不发起任何网络请求。分类参数沿用既有语义：传分类名称，门面按名称
/// 解析为分类 ID 落库（与服务端行为一致，findFirst）。
class TransactionService {
  static TransactionService? _instance;

  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final StatisticsRepository _stats;

  TransactionService._(
    this._transactions,
    this._categories,
    this._stats,
  );

  /// 应用内单例（本地库应用级唯一实例）
  factory TransactionService() {
    _instance ??= TransactionService._(
      Db.transactions,
      Db.categories,
      Db.statistics,
    );
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

  /// 添加交易：分类按名称解析为 ID，本地生成 UUIDv7 主键
  Future<Map<String, dynamic>> addTransaction({
    required int type,
    required String category,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final familyId = await CurrentFamilyStore.get();
    final cat = await _categories.findByName(familyId, category, type);
    if (cat == null) {
      throw Exception('分类不存在');
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
              icon: categoryById[r.categoryId]?.icon,
              amount: Money.centsToYuan(r.amountCents),
              date: r.date,
              userId: r.userId,
              description: r.description,
              counterparty: r.counterparty,
            ))
        .toList();
  }

  /// 更新交易：分类按名称解析为 ID；备注传 null 表示清空（表单语义）
  Future<Map<String, dynamic>> updateTransaction({
    required String id,
    required int type,
    required String category,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final existing = await _transactions.findById(id);
    if (existing == null) {
      throw Exception('交易记录不存在');
    }
    final familyId = await CurrentFamilyStore.get();
    final cat = await _categories.findByName(familyId, category, type);
    if (cat == null) {
      throw Exception('分类不存在');
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

    return <String, dynamic>{};
  }

  /// 删除交易（软删除墓碑，参与后续同步）
  Future<void> deleteTransaction(String id) async {
    final existing = await _transactions.findById(id);
    if (existing == null) {
      throw Exception('交易记录不存在');
    }
    await _transactions.softDelete(id);
  }

  /// 获取首页数据：月度概览 + 预算 + 近期动态，全部本地聚合。
  /// 返回结构对齐既有服务端 /v1/home 响应（页面零改动）。
  /// [now] 仅供测试注入基准时间，生产不传。
  Future<Map<String, dynamic>> getHomeData([DateTime? now]) async {
    final current = now ?? DateTime.now();
    final familyId = await CurrentFamilyStore.get();
    final overview = await _stats.monthlyOverview(familyId, current);
    final budgetTotal =
        await _stats.monthBudget(familyId, current.year, current.month);

    // 近期动态：最近 10 条，排除不计收支（type=2），口径对齐服务端
    final recent = await _transactions.recent(familyId, 10);

    final user = await LocalUser.load();
    final userName = (user != null && user.nickname.isNotEmpty)
        ? user.nickname
        : '未知用户';

    final catIds = recent.map((r) => r.categoryId).toSet();
    final cats = await _categories.findByIds(catIds);
    final categoryById = {for (final c in cats) c.id: c};

    final activities = recent.map((r) {
      final category = categoryById[r.categoryId];
      // 标题：分类名 > 描述 > 默认（与服务端一致）
      final title =
          category?.name ?? r.description ?? '支出';
      final icon = category?.icon ?? 'payments';
      return <String, dynamic>{
        'title': title,
        'icon': icon,
        'user': userName,
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
        'used': overview.expense,
        'total': budgetTotal,
      },
      'activities': activities,
    };
  }
}
