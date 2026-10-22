import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/local/db_provider.dart';
import '../../data/local/local_user.dart';
import '../../data/local/statistics_repository.dart';

/// 统计数据门面：本地优先架构下的统计页唯一数据源。
///
/// 对外保持既有 Service 签名与响应 JSON 结构（页面零改动），内部全部
/// 走本地库聚合（聚合下推 SQLite），不发任何网络请求。
/// 一期单成员语义：本地库全部交易归属当前用户，memberId 参数忽略。
class StatisticsService {
  // 单例实例
  static StatisticsService? _instance;

  final StatisticsRepository _stats;

  // 私有构造函数
  StatisticsService._internal(this._stats);

  // 获取单例实例（本地库应用级唯一实例）
  factory StatisticsService() {
    _instance ??= StatisticsService._internal(Db.statistics);
    return _instance!;
  }

  // 测试专用：注入内存库构造独立实例
  @visibleForTesting
  StatisticsService.withRepos(this._stats);

  // ---------- 周期区间（对齐服务端 getDateRangeByPeriod / getPreviousPeriodRange）----------

  // 当前周期：零点闭区间 [start, end]
  ({DateTime start, DateTime end}) _currentRange(
    String period,
    int year,
    int? month,
    String? weekStartDate,
    String? weekEndDate,
  ) {
    switch (period) {
      case 'year':
        return (start: DateTime(year, 1, 1), end: DateTime(year, 12, 31));
      case 'month':
        return (
          start: DateTime(year, month!, 1),
          end: DateTime(year, month + 1, 0),
        );
      case 'week':
        return (
          start: DateTime.parse(weekStartDate!),
          end: DateTime.parse(weekEndDate!),
        );
      default:
        throw ArgumentError('period 参数不正确，应为 year、month 或 week');
    }
  }

  // 上一周期（环比分母）
  ({DateTime start, DateTime end}) _previousRange(
    String period,
    int year,
    int? month,
    String? weekStartDate,
    String? weekEndDate,
  ) {
    switch (period) {
      case 'year':
        return (
          start: DateTime(year - 1, 1, 1),
          end: DateTime(year - 1, 12, 31),
        );
      case 'month':
        // DateTime 自动进位：month=1 时上月为去年 12 月
        return (
          start: DateTime(year, month! - 1, 1),
          end: DateTime(year, month, 0),
        );
      case 'week':
        final start = DateTime.parse(weekStartDate!);
        final days =
            start.difference(DateTime.parse(weekEndDate!)).inDays.abs() + 1;
        return (
          start: start.subtract(Duration(days: days)),
          end: start.subtract(const Duration(days: 1)),
        );
      default:
        throw ArgumentError('period 参数不正确，应为 year、month 或 week');
    }
  }

  // ---------- 格式化（对齐服务端 NumberFormat：千分位、无小数）----------

  // en_US 分组符同为 ,，输出与服务端 zh-CN 一致
  static final NumberFormat _grouped = NumberFormat('#,##0', 'en_US');

  // 金额格式化（带 ¥，对齐服务端 formatAmount）
  String _formatAmount(double v) => '¥${_grouped.format(v)}';

  // 总金额格式化（无 ¥，对齐服务端 formatTotalAmount）
  String _formatTotal(double v) => _grouped.format(v);

  // 环比字符串（对齐 calculateChangePercentage：整数百分比带符号）
  String _changeString(double current, double previous) {
    if (previous == 0) return current == 0 ? '0%' : '+100%';
    final change = (current - previous) / previous * 100;
    return '${change >= 0 ? '+' : ''}${change.round()}%';
  }

  // 环比数值（对齐 calculateChangeRate：百分比数值）
  double _changeRate(double current, double previous) {
    if (previous == 0) return current == 0 ? 0 : 100;
    return (current - previous) / previous * 100;
  }

  // 日期键 yyyy-MM-dd（与 SQL strftime 输出一致，零填充）
  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- 五个统计接口（响应结构对齐服务端）----------

  // 获取统计数据（分类统计）
  Future<Map<String, dynamic>> getStatistics({
    required int type, // 0-收入(INCOME), 1-支出(EXPENSE)
    required int year, // 年份
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId, // 一期忽略：本地库全部为本人交易
    int? limit, // 可选：返回Top N分类
  }) async {
    final cur =
        _currentRange(period, year, month, weekStartDate, weekEndDate);
    final prev =
        _previousRange(period, year, month, weekStartDate, weekEndDate);

    final items = await _stats.categoryStatistics(
        type: type, start: cur.start, end: cur.end);
    // 总额与环比分母：同类型区间总额（分母含已删分类金额，与分类统计口径一致）
    final total =
        await _stats.typeTotals(type: type, start: cur.start, end: cur.end);
    final previous =
        await _stats.typeTotals(type: type, start: prev.start, end: prev.end);

    // 颜色按排序后名次循环分配（服务端按构建顺序分配、无稳定契约，取名次更直观）
    const colors = [
      '#13ec5b', '#fbbf24', '#3b82f6', '#ef4444',
      '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16',
    ];
    var list = items.asMap().entries.map((e) {
      return {
        'name': e.value.name,
        'amount': _formatAmount(e.value.amount),
        'pct': '${e.value.percentage.round()}%',
        'color': colors[e.key % colors.length],
        'icon': e.value.icon,
      };
    }).toList();
    if (limit != null && limit > 0 && list.length > limit) {
      list = list.sublist(0, limit);
    }

    return {
      'total': _formatTotal(total.amount),
      'change': _changeString(total.amount, previous.amount),
      'items': list,
    };
  }

  // 获取统计概览数据
  Future<Map<String, dynamic>> getOverview({
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId, // 一期忽略
  }) async {
    final cur =
        _currentRange(period, year, month, weekStartDate, weekEndDate);
    final prev =
        _previousRange(period, year, month, weekStartDate, weekEndDate);

    final current = await _stats.rangeSummary(start: cur.start, end: cur.end);
    final previous = await _stats.rangeSummary(start: prev.start, end: prev.end);

    return {
      'totalIncome': current.income,
      'totalExpense': current.expense,
      'netIncome': current.income - current.expense,
      'incomeChange': _changeRate(current.income, previous.income),
      'expenseChange': _changeRate(current.expense, previous.expense),
      // 服务端未赋值日均字段，保留占位 null 对齐响应结构
      'avgDailyIncome': null,
      'avgDailyExpense': null,
      'transactionCount': current.count,
    };
  }

  // 获取时间趋势统计
  Future<Map<String, dynamic>> getTrend({
    int? type, // 0-收入，1-支出，null-全部
    required int year,
    required String period, // 'day'（周维度按天）| 'month'（按天）| 'year'（按月）
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'day'且查询周维度时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'day'且查询周维度时必传，格式：yyyy-MM-dd
    String? memberId, // 一期忽略
  }) async {
    final List<({String date, String dateLabel, double income, double expense})>
        points;
    if (period == 'year') {
      // 年维度：按月聚合
      final rows = await _stats.monthlyTotals(
          type: type, start: DateTime(year, 1, 1), end: DateTime(year, 12, 31));
      final byMonth = {for (final r in rows) r.month: r};
      points = [
        for (var m = 1; m <= 12; m++)
          (
            date: '$year-${m.toString().padLeft(2, '0')}',
            dateLabel: '$year年$m月',
            income: byMonth[m]?.income ?? 0,
            expense: byMonth[m]?.expense ?? 0,
          ),
      ];
    } else if (period == 'month') {
      // 月维度：按天聚合
      final lastDay = DateTime(year, month! + 1, 0).day;
      final rows = await _stats.dailyTotals(
          type: type,
          start: DateTime(year, month, 1),
          end: DateTime(year, month + 1, 0));
      final byDay = {for (final r in rows) r.day: r};
      points = [
        for (var d = 1; d <= lastDay; d++)
          (
            date: '$year-'
                '${month.toString().padLeft(2, '0')}-'
                '${d.toString().padLeft(2, '0')}',
            dateLabel: '$month月$d日',
            income: byDay[_ymd(DateTime(year, month, d))]?.income ?? 0,
            expense: byDay[_ymd(DateTime(year, month, d))]?.expense ?? 0,
          ),
      ];
    } else if (period == 'day') {
      // 周维度：period='day'，周内按天聚合
      final start = DateTime.parse(weekStartDate!);
      final end = DateTime.parse(weekEndDate!);
      final rows = await _stats.dailyTotals(type: type, start: start, end: end);
      final byDay = {for (final r in rows) r.day: r};
      points = [
        for (var d = start;
            !d.isAfter(end);
            d = d.add(const Duration(days: 1)))
          (
            date: _ymd(d),
            dateLabel: '${d.month}月${d.day}日',
            income: byDay[_ymd(d)]?.income ?? 0,
            expense: byDay[_ymd(d)]?.expense ?? 0,
          ),
      ];
    } else {
      throw ArgumentError('period 参数不正确，应为 year、month 或 day');
    }

    // 逐项环比（对齐服务端：首项无环比）
    final items = <Map<String, dynamic>>[];
    for (final p in points) {
      final hasPrev = items.isNotEmpty;
      final prev = items.isEmpty ? null : items.last;
      items.add({
        'date': p.date,
        'dateLabel': p.dateLabel,
        'income': p.income,
        'expense': p.expense,
        'net': p.income - p.expense,
        'incomeChange': hasPrev
            ? _changeRate(p.income, prev!['income'] as double)
            : null,
        'expenseChange': hasPrev
            ? _changeRate(p.expense, prev!['expense'] as double)
            : null,
      });
    }

    var totalIncome = 0.0;
    var totalExpense = 0.0;
    var maxIncome = 0.0;
    var maxExpense = 0.0;
    for (final p in points) {
      totalIncome += p.income;
      totalExpense += p.expense;
      if (p.income > maxIncome) maxIncome = p.income;
      if (p.expense > maxExpense) maxExpense = p.expense;
    }

    return {
      'period': period,
      'items': items,
      'summary': {
        // 对齐服务端：均值保留 2 位（HALF_UP）
        'avgIncome': items.isEmpty ? 0 : (totalIncome / items.length * 100).round() / 100,
        'avgExpense': items.isEmpty ? 0 : (totalExpense / items.length * 100).round() / 100,
        'totalIncome': totalIncome,
        'totalExpense': totalExpense,
        'maxIncome': maxIncome,
        'maxExpense': maxExpense,
      },
    };
  }

  // 获取成员统计（一期单成员：本人即唯一成员）
  Future<Map<String, dynamic>> getByMember({
    required int type, // 0-收入，1-支出
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? categoryId,
  }) async {
    final cur =
        _currentRange(period, year, month, weekStartDate, weekEndDate);
    final totals = await _stats.typeTotals(
        type: type, categoryId: categoryId, start: cur.start, end: cur.end);

    final items = <Map<String, dynamic>>[];
    if (totals.count > 0) {
      final user = await LocalUser.load();
      final amount = totals.amount;
      // 单成员占比：金额非 0 即 100%
      final percentage = amount == 0 ? 0.0 : 100.0;
      items.add({
        'memberId': user?.id ?? '',
        'memberName': user?.nickname ?? '',
        'avatar': user?.avatar,
        'amount': amount,
        'amountStr': _formatAmount(amount),
        'percentage': percentage,
        'percentageStr': '${percentage.round()}%',
        'count': totals.count,
        // 对齐服务端：均值保留 2 位（HALF_UP）
        'avgAmount': (amount / totals.count * 100).round() / 100,
      });
    }

    return {'total': _formatTotal(totals.amount), 'items': items};
  }

  // 获取日期统计（日历视图）
  Future<Map<String, dynamic>> getByDate({
    int? type, // 0-收入，1-支出，null-全部
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId, // 一期忽略
  }) async {
    final cur =
        _currentRange(period, year, month, weekStartDate, weekEndDate);
    final rows =
        await _stats.dailyTotals(type: type, start: cur.start, end: cur.end);
    // 热力值分母：区间内单笔最大金额（对齐服务端 maxAmount 口径）
    final maxSingle =
        await _stats.maxAmount(type: type, start: cur.start, end: cur.end);
    final byDay = {for (final r in rows) r.day: r};

    // 区间内逐日生成（对齐服务端 dateList：无交易日也占位）
    final days = <Map<String, dynamic>>[];
    DateTime? maxDate;
    var maxDayAmount = 0.0;
    for (var d = cur.start;
        !d.isAfter(cur.end);
        d = d.add(const Duration(days: 1))) {
      final row = byDay[_ymd(d)];
      final income = row?.income ?? 0;
      final expense = row?.expense ?? 0;
      final dayTotal = income + expense;
      // 热力值 1-5：当日总额 / 单笔最大值，向上取整后收敛
      final intensity =
          maxSingle > 0 ? ((dayTotal / maxSingle * 5).ceil()).clamp(1, 5) : 1;
      days.add({
        'date': _ymd(d),
        'day': d.day,
        'income': income,
        'expense': expense,
        'net': income - expense,
        'count': row?.count ?? 0,
        'intensity': intensity,
      });
      // 对齐服务端：严格大于才刷新最大日期
      if (dayTotal > maxDayAmount) {
        maxDayAmount = dayTotal;
        maxDate = d;
      }
    }

    return {
      'year': year,
      // 服务端仅当传入 month 才返回该字段
      if (month != null) 'month': month,
      'days': days,
      'summary': {
        'maxAmount': maxDayAmount,
        'maxDate': maxDate == null ? null : _ymd(maxDate),
      },
    };
  }
}
