import 'package:drift/drift.dart';

import 'app_database.dart';

/// 预算仓储：本地 budgets 表读写。
///
/// 月预算唯一（UNIQUE(year, month)）；upsert 含墓碑复活语义；
/// version/updatedAt 由本仓储维护，供后续同步 LWW 仲裁使用。
class BudgetRepository {
  final AppDatabase _db;

  BudgetRepository(this._db);

  /// 查询指定月预算（排除墓碑），无则返回 null。家庭维度
  Future<Budget?> findByMonth(
      String familyId, int year, int month) async {
    final rows = await (_db.select(_db.budgets)
          ..where((b) =>
              b.familyId.equals(familyId) &
              b.year.equals(year) &
              b.month.equals(month) &
              b.deleted.equals(false)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 写入月预算（金额单位分）：同月已存在（含墓碑行）则更新金额并复活、
  /// version+1；否则新插入。家庭维度：同家庭同月唯一（UNIQUE(family_id,
  /// year, month)）
  Future<void> upsertMonth({
    required String familyId,
    required int year,
    required int month,
    required int amountCents,
  }) async {
    final now = DateTime.now();
    final existing = await (_db.select(_db.budgets)
          ..where((b) =>
              b.familyId.equals(familyId) &
              b.year.equals(year) &
              b.month.equals(month)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.budgets).insert(BudgetsCompanion.insert(
            familyId: Value(familyId),
            year: year,
            month: month,
            amountCents: amountCents,
            updatedAt: Value(now),
          ));
      return;
    }
    await (_db.update(_db.budgets)
          ..where((b) => b.id.equals(existing.id)))
        .write(BudgetsCompanion(
          amountCents: Value(amountCents),
          version: Value(existing.version + 1),
          updatedAt: Value(now),
          deleted: const Value(false),
        ));
  }
}
