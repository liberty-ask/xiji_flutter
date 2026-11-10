import 'package:drift/drift.dart';

import 'app_database.dart';
import 'category_match_key.dart';

/// 学习表 Repository：账单导入与语音记账共用（同一匹配文本收敛为单条）。
///
/// 同步纪律与其他表一致：每次变更 version+1、updatedAt=now、syncPending=true；
/// 删除为软删除墓碑。match_text 唯一约束兜底同一文本的唯一性。
class CategoryRuleRepository {
  final AppDatabase _db;

  CategoryRuleRepository(this._db);

  /// 按匹配键查找（排除墓碑），分类引擎学习表命中用。
  ///
  /// 入参先经 [normalizeCategoryMatchKey] 归一化，与写入口径一致；
  /// 归一化键未命中时回退按原文查找，兼容归一化上线前写入的旧条目。
  Future<CategoryRule?> findByMatchText(String matchText) async {
    final key = normalizeCategoryMatchKey(matchText);
    if (key.isEmpty) return null;

    final hit = await _findByExactText(key);
    if (hit != null) return hit;

    final raw = matchText.trim();
    if (raw.isEmpty || raw == key) return null;
    return _findByExactText(raw);
  }

  Future<CategoryRule?> _findByExactText(String text) {
    return (_db.select(_db.categoryRules)
          ..where((r) => r.matchText.equals(text) & r.deleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 指认回写：upsert 匹配文本 → 分类。
  /// - 新文本：插入条目（hitCount 从 0 起）
  /// - 已存在且分类不同：覆盖分类（version+1）
  /// - 已存在且分类相同：幂等 no-op
  /// - 命中墓碑行（唯一约束仍占位）：复活并覆盖分类
  Future<void> assign({
    required String matchText,
    required String categoryId,
    required int source, // 0-账单导入 1-语音记账
  }) async {
    // 写入与读取共用同一归一化实现，保证同一商户的不同写法收敛到同一键
    final key = normalizeCategoryMatchKey(matchText);
    if (key.isEmpty) return;

    final existing = await (_db.select(_db.categoryRules)
          ..where((r) => r.matchText.equals(key))
          ..limit(1))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.categoryRules).insert(
            CategoryRulesCompanion.insert(
              matchText: key,
              categoryId: categoryId,
              source: source,
            ),
          );
      return;
    }

    // 幂等：指认分类未变则不产生变更
    if (existing.categoryId == categoryId && !existing.deleted) return;

    await (_db.update(_db.categoryRules)
          ..where((r) => r.id.equals(existing.id)))
        .write(CategoryRulesCompanion(
      categoryId: Value(categoryId),
      deleted: const Value(false), // 墓碑复活
      version: Value(existing.version + 1),
      updatedAt: Value(DateTime.now()),
      syncPending: const Value(true),
    ));
  }

  /// 命中计数 +1（分类引擎学习表命中时调用），version+1 参与后续同步仲裁
  Future<void> recordHit(String id) async {
    final current = await (_db.select(_db.categoryRules)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    if (current == null) return;

    await (_db.update(_db.categoryRules)..where((r) => r.id.equals(id)))
        .write(CategoryRulesCompanion(
      hitCount: Value(current.hitCount + 1),
      version: Value(current.version + 1),
      updatedAt: Value(DateTime.now()),
      syncPending: const Value(true),
    ));
  }

  /// 清空学习表（软删除全部未删除条目），返回被清掉的条数。
  /// 学习表置顶后既有错误指认会立即生效，需要这条后路。
  Future<int> clearAll() async {
    final rows = await (_db.select(_db.categoryRules)
          ..where((r) => r.deleted.equals(false)))
        .get();
    if (rows.isEmpty) return 0;

    final now = DateTime.now();
    await _db.batch((b) {
      for (final row in rows) {
        b.update(
          _db.categoryRules,
          CategoryRulesCompanion(
            deleted: const Value(true),
            version: Value(row.version + 1),
            updatedAt: Value(now),
            syncPending: const Value(true),
          ),
          where: (r) => r.id.equals(row.id),
        );
      }
    });
    return rows.length;
  }
}
