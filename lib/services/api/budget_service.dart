import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/budget_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../data/local/local_user.dart';
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
  /// 个人口径：当前用户在当前家庭的月预算
  Future<Map<String, dynamic>> getBudget({
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final user = await LocalUser.load();
    final row = await _budgets.findByMonth(
      await CurrentFamilyStore.get(),
      user?.id ?? '',
      year ?? now.year,
      month ?? now.month,
    );
    return {'budget': row == null ? null : Money.centsToYuan(row.amountCents)};
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
