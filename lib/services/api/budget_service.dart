import 'package:flutter/foundation.dart';

import '../../data/local/budget_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../utils/money.dart';

/// 预算数据门面：本地优先架构下的唯一读写入口。
///
/// 对外保持既有 Service 签名与返回结构（页面零改动），内部读写本地 budgets 表，
/// 不发起任何网络请求。中间态：无 userId 与跨设备漫游（见 design.md D9），
/// 由 7.0/7.5 收口。写入后首页预算进度（statistics_repository.monthBudget）
/// 数据源分裂随之修复。
class BudgetService {
  // 单例实例
  static BudgetService? _instance;

  final BudgetRepository _budgets;

  BudgetService._internal(this._budgets);

  // 获取单例实例（本地库应用级唯一实例）
  factory BudgetService() {
    _instance ??= BudgetService._internal(Db.budgets);
    return _instance!;
  }

  /// 测试专用：注入内存库构造独立实例
  @visibleForTesting
  BudgetService.withRepo(this._budgets);

  /// 获取预算信息：返回 {'budget': amount}，未设置（或墓碑）返回 {'budget': null}。
  /// 家庭维度：当前家庭的月预算
  Future<Map<String, dynamic>> getBudget({
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final row = await _budgets.findByMonth(
      await CurrentFamilyStore.get(),
      year ?? now.year,
      month ?? now.month,
    );
    return {'budget': row == null ? null : Money.centsToYuan(row.amountCents)};
  }

  /// 设置预算：同月已存在（含墓碑）则覆盖更新，否则新插入。
  /// 家庭维度：写入当前家庭
  Future<void> setBudget({
    required double total,
    required int year,
    required int month,
  }) async {
    await _budgets.upsertMonth(
      familyId: await CurrentFamilyStore.get(),
      year: year,
      month: month,
      amountCents: Money.yuanToCents(total),
    );
  }
}
