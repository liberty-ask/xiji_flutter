import 'package:drift/drift.dart';

import 'app_database.dart';

/// 分类 Repository：内置分类 + 自定义分类的统一读写入口。
///
/// 同步纪律与交易表一致：变更 version+1、updatedAt=now、syncPending=true；
/// 删除为软删除墓碑，不出现在任何查询结果。
/// 内置分类保护（不可改删）由上层门面校验，仓储仅提供机械读写。
class CategoryRepository {
  final AppDatabase _db;

  CategoryRepository(this._db);

  /// 全量列表（排除墓碑）：按类型分组（支出在前，与常量表顺序一致），
  /// 同类型内 sortOrder 升序——内置分类种子序 0-N，自定义分类从 N+1 起，
  /// 自然内置在前。
  /// 家庭维度：内置分类（全局共享）+ [familyId] 家庭的自定义分类
  Future<List<Category>> listAll(String familyId) {
    final query = _db.select(_db.categories)
      ..where((c) =>
          c.deleted.equals(false) &
          (c.isBuiltin.equals(true) | c.familyId.equals(familyId)))
      ..orderBy([
        (c) => OrderingTerm(expression: c.type, mode: OrderingMode.desc),
        (c) => OrderingTerm(expression: c.sortOrder),
      ]);
    return query.get();
  }

  /// 批量按 ID 拉取（排除墓碑），交易列表/近期动态关联分类用
  Future<List<Category>> findByIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (_db.select(_db.categories)
          ..where((c) => c.id.isIn(ids) & c.deleted.equals(false)))
        .get();
  }

  /// 按名称查找首个匹配（排除墓碑）。交易写入路径的名称→ID 解析，
  /// 与既有服务端行为一致（findFirst，类型过滤由调用方传入的类别列表保证）。
  /// 家庭维度：内置分类 + [familyId] 家庭的自定义分类
  Future<Category?> findByName(String familyId, String name, int type) {
    return (_db.select(_db.categories)
          ..where((c) =>
              c.name.equals(name) &
              c.type.equals(type) &
              c.deleted.equals(false) &
              (c.isBuiltin.equals(true) | c.familyId.equals(familyId)))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 同名分类计数（排除墓碑），新增/改名查重用；excludeId 跳过自身。
  /// 家庭维度：查重范围为内置 + [familyId] 家庭
  Future<int> countByName(String familyId, String name, int type,
      {String? excludeId}) {
    final query = _db.selectOnly(_db.categories)
      ..addColumns([_db.categories.id.count()])
      ..where(_db.categories.name.equals(name) &
          _db.categories.type.equals(type) &
          _db.categories.deleted.equals(false) &
          (_db.categories.isBuiltin.equals(true) |
              _db.categories.familyId.equals(familyId)));
    if (excludeId != null) {
      query.where(_db.categories.id.equals(excludeId).not());
    }
    return query
        .map((row) => row.read(_db.categories.id.count())!)
        .getSingle();
  }

  /// 新增自定义分类：sortOrder 取同类型最大值 +1（对齐服务端语义）。
  /// 家庭维度：归属 [familyId]（强制写入，调用方无需在 companion 重复传），
  /// 最大值在「内置 + [familyId] 家庭」范围内取
  Future<Category> insert(String familyId, CategoriesCompanion c) {
    return _db.transaction(() async {
      final maxRow = await (_db.selectOnly(_db.categories)
            ..addColumns([_db.categories.sortOrder.max()])
            ..where(_db.categories.type.equals(c.type.value) &
                _db.categories.deleted.equals(false) &
                (_db.categories.isBuiltin.equals(true) |
                    _db.categories.familyId.equals(familyId))))
          .getSingleOrNull();
      final maxSort = maxRow?.read(_db.categories.sortOrder.max()) ?? 0;

      return await _db.into(_db.categories).insertReturning(
            c.copyWith(
                sortOrder: Value(maxSort + 1), familyId: Value(familyId)),
          );
    });
  }

  /// 编辑自定义分类：version+1、updatedAt 刷新、syncPending 置位
  Future<Category> update(String id, CategoriesCompanion changes) {
    return _db.transaction(() async {
      final current = await (_db.select(_db.categories)
            ..where((c) => c.id.equals(id) & c.deleted.equals(false)))
          .getSingleOrNull();
      if (current == null) {
        throw StateError('分类不存在: $id');
      }

      final rows = await (_db.update(_db.categories)
            ..where((c) => c.id.equals(id)))
          .writeReturning(CategoriesCompanion(
        name: changes.name,
        icon: changes.icon,
        type: changes.type,
        version: Value(current.version + 1),
        updatedAt: Value(DateTime.now()),
        syncPending: const Value(true),
      ));
      return rows.single;
    });
  }

  /// 单条查询（排除墓碑）
  Future<Category?> findById(String id) {
    return (_db.select(_db.categories)
          ..where((c) => c.id.equals(id) & c.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// 软删除墓碑：行保留参与同步，不出现在查询结果
  Future<void> softDelete(String id) async {
    final current = await findById(id);
    if (current == null) return;
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        version: Value(current.version + 1),
        updatedAt: Value(DateTime.now()),
        deleted: const Value(true),
        syncPending: const Value(true),
      ),
    );
  }
}
