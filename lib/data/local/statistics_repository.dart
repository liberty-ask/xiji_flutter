import 'package:drift/drift.dart';

import 'app_database.dart';
import '../../utils/money.dart';

/// 收支统计聚合：对齐服务端统计口径，聚合下推 SQLite（SUM GROUP BY）。
///
/// 口径纪律（与既有服务端一致）：
/// - type=2（不计收支）排除在一切收支统计之外：总额查询 type IN (0,1)，
///   分类统计/今日支出仅取显式 type 0/1
/// - 墓碑（deleted=1）排除在统计之外
/// - 分类关联批量 IN 拉取，禁止循环单查（N+1）
class StatisticsRepository {
  final AppDatabase _db;

  StatisticsRepository(this._db);

  /// 首页月度概览：本月收入、支出、结余、今日支出、昨日支出。
  /// 家庭维度：仅 [familyId] 家庭的交易
  Future<MonthlyOverview> monthlyOverview(
    String familyId, [
    DateTime? now,
  ]) async {
    final n = now ?? DateTime.now();
    final monthStart = DateTime(n.year, n.month, 1);
    final monthEnd = DateTime(n.year, n.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final rows = await _db.customSelect(
      'SELECT SUM(CASE WHEN type = 0 THEN amount_cents ELSE 0 END) AS income, '
      'SUM(CASE WHEN type = 1 THEN amount_cents ELSE 0 END) AS expense '
      'FROM transactions WHERE deleted = 0 AND type IN (0, 1) '
      'AND family_id = ? AND date >= ? AND date <= ?',
      variables: [
        Variable(familyId),
        Variable<DateTime>(monthStart),
        Variable<DateTime>(monthEnd),
      ],
      readsFrom: {_db.transactions},
    ).get();

    // 今日/昨日支出（type=1）
    final todayExpense = await _sumExpense(familyId, today);
    final yesterdayExpense = await _sumExpense(familyId, yesterday);

    final r = rows.single;
    final incomeCents = (r.readNullable<int>('income') ?? 0);
    final expenseCents = (r.readNullable<int>('expense') ?? 0);
    return MonthlyOverview(
      income: Money.centsToYuan(incomeCents),
      expense: Money.centsToYuan(expenseCents),
      // 结余在分域整数相减后一次性转元，避免元 double 减法尾巴
      balance: Money.centsToYuan(incomeCents - expenseCents),
      todayExpense: todayExpense,
      yesterdayExpense: yesterdayExpense,
    );
  }

  Future<double> _sumExpense(String familyId, DateTime day) async {
    final dayEnd = day.add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    final rows = await _db.customSelect(
      'SELECT SUM(amount_cents) AS total FROM transactions '
      'WHERE deleted = 0 AND type = 1 AND family_id = ? '
      'AND date >= ? AND date <= ?',
      variables: [
        Variable(familyId),
        Variable<DateTime>(day),
        Variable<DateTime>(dayEnd),
      ],
      readsFrom: {_db.transactions},
    ).get();
    return Money.centsToYuan(rows.single.readNullable<int>('total') ?? 0);
  }

  /// 指定月份预算金额（无预算或墓碑返回 0）。个人口径（D8）：
  /// 当前用户在 [familyId] 家庭的预算
  Future<double> monthBudget(
      String familyId, String userId, int year, int month) async {
    final rows = await (_db.select(_db.budgets)
          ..where((b) =>
              b.familyId.equals(familyId) &
              b.userId.equals(userId) &
              b.year.equals(year) &
              b.month.equals(month) &
              b.deleted.equals(false)))
        .get();
    if (rows.isEmpty) return 0;
    return Money.centsToYuan(rows.first.amountCents);
  }

  /// 分类统计：指定收支类型与日期区间，按分类聚合金额并降序。
  /// 家庭维度：仅 [familyId] 家庭的交易
  Future<List<CategoryStatisticsItem>> categoryStatistics({
    required String familyId,
    required int type, // 0-收入 1-支出（2 禁止传入）
    required DateTime start,
    required DateTime end,
  }) async {
    assert(type == 0 || type == 1, '收支统计禁止 type=2');
    final endInclusive = end.add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    // 聚合下推：SUM GROUP BY category_id（分域整数聚合）
    final rows = await _db.customSelect(
      'SELECT category_id, SUM(amount_cents) AS total FROM transactions '
      'WHERE deleted = 0 AND type = ? AND family_id = ? '
      'AND date >= ? AND date <= ? '
      'GROUP BY category_id ORDER BY total DESC',
      variables: [
        Variable(type),
        Variable(familyId),
        Variable<DateTime>(start),
        Variable<DateTime>(endInclusive),
      ],
      readsFrom: {_db.transactions},
    ).get();

    if (rows.isEmpty) return const [];

    // 分类信息批量拉取（IN，禁止循环单查）
    final ids = rows.map((r) => r.read<String>('category_id')).toSet();
    final categories = await (_db.select(_db.categories)
          ..where((c) => c.id.isIn(ids) & c.deleted.equals(false)))
        .get();
    final categoryById = {for (final c in categories) c.id: c};

    // 总额分母含全部命中交易（对齐服务端 currentTotal 口径）；分域整数
    final totalCents =
        rows.fold<int>(0, (sum, r) => sum + (r.read<int>('total')));

    // 对齐服务端行为：分类查不到（已删除）则该条目不展示，
    // 但其金额已计入上面的 total 分母
    return rows
        .map((r) {
          final categoryId = r.read<String>('category_id');
          final category = categoryById[categoryId];
          if (category == null) return null;
          final amountCents = r.read<int>('total');
          return CategoryStatisticsItem(
            categoryId: categoryId,
            name: category.name,
            icon: category.icon,
            amount: Money.centsToYuan(amountCents),
            // 比例在分域整数比计算，与元域结果一致且无精度损失
            percentage:
                totalCents == 0 ? 0 : amountCents / totalCents * 100,
          );
        })
        .whereType<CategoryStatisticsItem>()
        .toList();
  }

  // ---------- 统计页（2.6）聚合：概览、趋势、日历、成员 ----------

  DateTime _endInclusive(DateTime end) => end
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));

  /// 本地时区偏移修饰符（如 '+08:00'）。
  /// date 列存储 unix 秒，SQL 按天/按月分组需先经 'unixepoch' 转成 UTC
  /// 再加本地偏移才得到本地日历日；禁止使用 'localtime' 修饰符——
  /// 在 dart sqlite3 的 Windows 构建下其返回 NULL（已用探针验证）。
  String get _tzModifier {
    final o = DateTime.now().timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final h = o.inHours.abs().toString().padLeft(2, '0');
    final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  void _typeWhere(
    int? type,
    List<String> where,
    List<Variable> variables,
  ) {
    if (type == null) {
      // 与服务端一致：type 为空表示全部收支，排除不计收支（type=2）
      where.add('type IN (0, 1)');
    } else {
      where.add('type = ?');
      variables.add(Variable(type));
    }
  }

  /// 统计页概览：区间收入、支出、笔数（type IN (0,1)）。家庭维度
  Future<RangeSummary> rangeSummary({
    required String familyId,
    required DateTime start,
    required DateTime end,
  }) async {
    final r = (await _db.customSelect(
      'SELECT SUM(CASE WHEN type = 0 THEN amount_cents ELSE 0 END) AS income, '
      'SUM(CASE WHEN type = 1 THEN amount_cents ELSE 0 END) AS expense, '
      'COUNT(*) AS cnt FROM transactions '
      'WHERE deleted = 0 AND type IN (0, 1) AND family_id = ? '
      'AND date >= ? AND date <= ?',
      variables: [
        Variable(familyId),
        Variable<DateTime>(start),
        Variable<DateTime>(_endInclusive(end)),
      ],
      readsFrom: {_db.transactions},
    ).get()).single;
    return RangeSummary(
      income: Money.centsToYuan(r.readNullable<int>('income') ?? 0),
      expense: Money.centsToYuan(r.readNullable<int>('expense') ?? 0),
      count: r.read<int>('cnt'),
    );
  }

  /// 指定类型（可加分类过滤）的区间总额与笔数；type 为空表示 IN (0,1)。
  /// 服务于分类统计环比分母与成员统计（一期单成员）。家庭维度
  Future<TypeTotals> typeTotals({
    required String familyId,
    int? type,
    String? categoryId,
    required DateTime start,
    required DateTime end,
  }) async {
    final where = <String>['deleted = 0', 'family_id = ?'];
    final variables = <Variable>[Variable(familyId)];
    _typeWhere(type, where, variables);
    if (categoryId != null && categoryId.isNotEmpty) {
      where.add('category_id = ?');
      variables.add(Variable(categoryId));
    }
    where
      ..add('date >= ?')
      ..add('date <= ?');
    variables
      ..add(Variable<DateTime>(start))
      ..add(Variable<DateTime>(_endInclusive(end)));
    final r = (await _db.customSelect(
      'SELECT SUM(amount_cents) AS total, COUNT(*) AS cnt FROM transactions '
      'WHERE ${where.join(' AND ')}',
      variables: variables,
      readsFrom: {_db.transactions},
    ).get()).single;
    return TypeTotals(
      amount: Money.centsToYuan(r.readNullable<int>('total') ?? 0),
      count: r.read<int>('cnt'),
    );
  }

  /// 按天聚合（趋势与日历）：键为本地日期 yyyy-MM-dd。
  /// type 过滤语义对齐服务端：null 拆分收支两列、0 仅收入列、1 仅支出列。
  /// 家庭维度
  Future<List<DailyTotals>> dailyTotals({
    required String familyId,
    int? type,
    required DateTime start,
    required DateTime end,
  }) async {
    final where = <String>['deleted = 0', 'family_id = ?'];
    final variables = <Variable>[Variable(familyId)];
    _typeWhere(type, where, variables);
    where
      ..add('date >= ?')
      ..add('date <= ?');
    variables
      ..add(Variable<DateTime>(start))
      ..add(Variable<DateTime>(_endInclusive(end)));
    final rows = await _db.customSelect(
      "SELECT strftime('%Y-%m-%d', date, 'unixepoch', ?) AS day_key, "
      'SUM(CASE WHEN type = 0 THEN amount_cents ELSE 0 END) AS income, '
      'SUM(CASE WHEN type = 1 THEN amount_cents ELSE 0 END) AS expense, '
      'COUNT(*) AS cnt FROM transactions '
      'WHERE ${where.join(' AND ')} '
      'GROUP BY day_key ORDER BY day_key',
      variables: [Variable(_tzModifier), ...variables],
      readsFrom: {_db.transactions},
    ).get();
    return rows
        .map((r) => DailyTotals(
              day: r.read<String>('day_key'),
              income: Money.centsToYuan(r.readNullable<int>('income') ?? 0),
              expense: Money.centsToYuan(r.readNullable<int>('expense') ?? 0),
              count: r.read<int>('cnt'),
            ))
        .toList();
  }

  /// 年维度按月聚合（趋势图）：1-12 月。家庭维度
  Future<List<MonthlyTotals>> monthlyTotals({
    required String familyId,
    int? type,
    required DateTime start,
    required DateTime end,
  }) async {
    final where = <String>['deleted = 0', 'family_id = ?'];
    final variables = <Variable>[Variable(familyId)];
    _typeWhere(type, where, variables);
    where
      ..add('date >= ?')
      ..add('date <= ?');
    variables
      ..add(Variable<DateTime>(start))
      ..add(Variable<DateTime>(_endInclusive(end)));
    final rows = await _db.customSelect(
      "SELECT CAST(strftime('%m', date, 'unixepoch', ?) AS INTEGER) AS m, "
      'SUM(CASE WHEN type = 0 THEN amount_cents ELSE 0 END) AS income, '
      'SUM(CASE WHEN type = 1 THEN amount_cents ELSE 0 END) AS expense '
      'FROM transactions '
      'WHERE ${where.join(' AND ')} '
      'GROUP BY m ORDER BY m',
      variables: [Variable(_tzModifier), ...variables],
      readsFrom: {_db.transactions},
    ).get();
    return rows
        .map((r) => MonthlyTotals(
              month: r.read<int>('m'),
              income: Money.centsToYuan(r.readNullable<int>('income') ?? 0),
              expense: Money.centsToYuan(r.readNullable<int>('expense') ?? 0),
            ))
        .toList();
  }

  /// 区间内单笔最大金额（日历热力值分母，对齐服务端 maxAmount 口径）。
  /// 家庭维度
  Future<double> maxAmount({
    required String familyId,
    int? type,
    required DateTime start,
    required DateTime end,
  }) async {
    final where = <String>['deleted = 0', 'family_id = ?'];
    final variables = <Variable>[Variable(familyId)];
    _typeWhere(type, where, variables);
    where
      ..add('date >= ?')
      ..add('date <= ?');
    variables
      ..add(Variable<DateTime>(start))
      ..add(Variable<DateTime>(_endInclusive(end)));
    final r = (await _db.customSelect(
      'SELECT MAX(amount_cents) AS max_amount FROM transactions '
      'WHERE ${where.join(' AND ')}',
      variables: variables,
      readsFrom: {_db.transactions},
    ).get()).single;
    return Money.centsToYuan(r.readNullable<int>('max_amount') ?? 0);
  }
}

class MonthlyOverview {
  final double income;
  final double expense;
  final double balance;
  final double todayExpense;
  final double yesterdayExpense;

  MonthlyOverview({
    required this.income,
    required this.expense,
    required this.balance,
    required this.todayExpense,
    required this.yesterdayExpense,
  });
}

class CategoryStatisticsItem {
  final String categoryId;
  final String name;
  final String icon;
  final double amount;
  final double percentage; // 0-100

  CategoryStatisticsItem({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.amount,
    required this.percentage,
  });
}

/// 统计页概览聚合结果
class RangeSummary {
  final double income;
  final double expense;
  final int count;

  RangeSummary({
    required this.income,
    required this.expense,
    required this.count,
  });
}

/// 指定类型（可含分类过滤）的聚合结果
class TypeTotals {
  final double amount;
  final int count;

  TypeTotals({required this.amount, required this.count});
}

/// 按天聚合结果（day 为本地日期 yyyy-MM-dd）
class DailyTotals {
  final String day;
  final double income;
  final double expense;
  final int count;

  DailyTotals({
    required this.day,
    required this.income,
    required this.expense,
    required this.count,
  });
}

/// 按月聚合结果（month 为 1-12）
class MonthlyTotals {
  final int month;
  final double income;
  final double expense;

  MonthlyTotals({
    required this.month,
    required this.income,
    required this.expense,
  });
}
