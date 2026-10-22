import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/local/category_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/statistics_repository.dart';
import '../../data/local/transaction_repository.dart';

/// 日历数据门面：本地优先架构下的日历页唯一数据源。
///
/// 对外保持既有 Service 签名与响应 JSON 结构（页面零改动），内部全部
/// 走本地库，不发任何网络请求。响应结构对齐服务端
/// MobileCalendarController.getCalendarOverview：
/// - monthlyIncome/monthlyExpense/surplus：数值
/// - dailySummary：{"1": {income, expense}, ...} 覆盖当月每天（含零值）
/// - dailyDetails：{"1": [{name, cat, icon, time, type, amount,
///   description, counterparty}], ...}
/// 排除 type=2（不计收支）与墓碑，与收支统计口径一致。
class CalendarService {
  // 单例实例
  static CalendarService? _instance;

  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final StatisticsRepository _stats;

  // 私有构造函数
  CalendarService._internal(this._transactions, this._categories, this._stats);

  // 获取单例实例（本地库应用级唯一实例）
  factory CalendarService() {
    _instance ??= CalendarService._internal(
      Db.transactions,
      Db.categories,
      Db.statistics,
    );
    return _instance!;
  }

  // 测试专用：注入内存库构造独立实例
  @visibleForTesting
  CalendarService.withRepos(this._transactions, this._categories, this._stats);

  // 获取日历概览数据（整月）。day 参数保留兼容，服务端同为整月返回未使用
  Future<Map<String, dynamic>> getCalendarOverview({
    required int year,
    required int month,
    int? day,
  }) async {
    final start = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 汇总聚合约定传日历日零点（内部转当天末尾含尾）
    final monthEnd = DateTime(year, month + 1, 0);
    // 明细查询需要精确到月末最后一微秒
    final monthEndExact =
        DateTime(year, month + 1, 1).subtract(const Duration(microseconds: 1));

    final familyId = await CurrentFamilyStore.get();

    // 每日汇总：复用统计聚合（SUM CASE 口径，排除墓碑与 type=2 的收支）
    final totals = await _stats.dailyTotals(
        familyId: familyId, start: start, end: monthEnd);
    final totalsByDay = <int, DailyTotals>{
      for (final t in totals) int.parse(t.day.substring(8, 10)): t,
    };

    // 每日明细：排除 type=2（对齐服务端），按业务日期倒序
    final monthTransactions = await _transactions.query(
        familyId: familyId, start: start, end: monthEndExact);
    final categories = await _categories.listAll(familyId);
    final categoryById = {
      for (final c in categories) c.id: c,
    };

    var monthlyIncome = 0.0;
    var monthlyExpense = 0.0;
    final dailySummary = <String, dynamic>{};

    // 汇总覆盖当月每天（含无交易日的零值），保持服务端键序
    for (var d = 1; d <= daysInMonth; d++) {
      final t = totalsByDay[d];
      final income = t?.income ?? 0;
      final expense = t?.expense ?? 0;
      monthlyIncome += income;
      monthlyExpense += expense;
      dailySummary['$d'] = {'income': income, 'expense': expense};
    }

    // 明细按日分组（每天均有键，空日为空列表）
    final dailyDetails = <String, dynamic>{
      for (var d = 1; d <= daysInMonth; d++) '$d': <dynamic>[],
    };
    for (final tx in monthTransactions) {
      if (tx.type == 2) continue; // 不计收支不进日历
      final category = categoryById[tx.categoryId];
      dailyDetails.putIfAbsent('${tx.date.day}', () => <dynamic>[]);

      // name：优先描述，其次分类名，最后按类型兜底（对齐服务端）
      String name;
      if ((tx.description ?? '').isNotEmpty) {
        name = tx.description!;
      } else if (category != null) {
        name = category.name;
      } else {
        name = tx.type == 0 ? '收入' : '支出';
      }

      (dailyDetails['${tx.date.day}'] as List<dynamic>).add({
        'name': name,
        'cat': category?.name ?? '',
        'icon': category?.icon ?? '',
        'time': DateFormat('HH:mm').format(tx.date),
        'type': tx.type,
        'amount':
            '${tx.type == 0 ? '+' : '-'} ${tx.amount.toStringAsFixed(2)}',
        'description': tx.description,
        'counterparty': tx.counterparty,
      });
    }

    return {
      'monthlyIncome': monthlyIncome,
      'monthlyExpense': monthlyExpense,
      'surplus': monthlyIncome - monthlyExpense,
      'dailySummary': dailySummary,
      'dailyDetails': dailyDetails,
    };
  }
}
