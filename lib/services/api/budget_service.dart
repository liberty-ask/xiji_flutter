import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/budget_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/local_user.dart';
import '../../data/local/statistics_repository.dart';
import '../../sync/sync_scheduler.dart';
import '../../utils/money.dart';

/// 预算数据门面：本地优先架构下的唯一读写入口。
///
/// 对外保持既有 Service 签名与返回结构（页面零改动），内部读写本地
/// budgets 表，不发起任何网络请求。预算归属当前登录用户（D8 个人
/// 预算制：各成员每月各自一条，家庭视图口径由 8.5 收口）。
class BudgetService {
  // 单例实例
  static BudgetService? _instance;
  static int _generation = -1;

  final BudgetRepository _budgets;
  final StatisticsRepository _stats;

  BudgetService._internal(this._budgets, this._stats);

  // 获取单例实例（本地库应用级唯一实例）。
  // 随库世代自动重绑：Db.close() 后（登出/账号切换）重开新库时
  // 重建实例，防止持有已关闭旧库的引用。
  factory BudgetService() {
    final g = Db.generation;
    if (_instance == null || _generation != g) {
      _instance = BudgetService._internal(Db.budgets, Db.statistics);
      _generation = g;
    }
    return _instance!;
  }

  /// 测试专用：注入内存库构造独立实例
  @visibleForTesting
  BudgetService.withRepo(this._budgets, this._stats);

  /// 获取预算信息：个人口径（D8：本人预算 vs 本人支出）。
  /// 返回 {'budget', 'used', 'remaining', 'percentage'}，未设置预算
  /// （或墓碑）时 budget 为 null、used 仍返回本月支出。
  Future<Map<String, dynamic>> getBudget({
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final user = await LocalUser.load();
    final familyId = await CurrentFamilyStore.get();
    final y = year ?? now.year;
    final m = month ?? now.month;
    final progress = await _stats.personalBudgetProgress(
        familyId, user?.id ?? '', y, m);
    return <String, dynamic>{
      'budget':
          progress.hasBudget ? Money.centsToYuan(progress.budgetCents!) : null,
      'used': Money.centsToYuan(progress.usedCents),
      'remaining': Money.centsToYuan(progress.remainingCents),
      'percentage': progress.percentage,
    };
  }

  /// 设置预算：同成员同月已存在（含墓碑）则覆盖更新，否则新插入。
  /// 个人口径：写入当前用户在当前家庭的预算
  Future<void> setBudget({
    required double total,
    required int year,
    required int month,
  }) async {
    final user = await LocalUser.load();
    await _budgets.upsertMonth(
      familyId: await CurrentFamilyStore.get(),
      userId: user?.id ?? '',
      year: year,
      month: month,
      amountCents: Money.yuanToCents(total),
    );
    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
  }
}
