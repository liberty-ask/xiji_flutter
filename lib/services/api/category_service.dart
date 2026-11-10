import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/local/app_database.dart' as local;
import '../../data/local/category_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../models/category.dart';
import '../../utils/error_helper.dart';
import '../../sync/sync_scheduler.dart';

/// 分类数据门面：内置分类 + 自定义分类的本地读写，不发起任何网络请求。
///
/// 保护规则（分类中性化）：
/// - 内置分类随版本发布、ID 固定，不可编辑、不可删除
/// - 自定义分类增删改自由，软删除墓碑参与后续同步
/// - 名称全局唯一（trim、不区分大小写，含与内置分类重名），不再按收支分别校验
class CategoryService {
  static CategoryService? _instance;
  static int _generation = -1;

  final CategoryRepository _categories;

  CategoryService._(this._categories);

  /// 应用内单例（本地库应用级唯一实例）。
  /// 随库世代自动重绑：Db.close() 后（登出/账号切换）重开新库时
  /// 重建实例，防止持有已关闭旧库的引用。
  factory CategoryService() {
    final g = Db.generation;
    if (_instance == null || _generation != g) {
      _instance = CategoryService._(Db.categories);
      _generation = g;
    }
    return _instance!;
  }

  /// 测试专用：注入内存库构造独立实例
  @visibleForTesting
  CategoryService.withRepos(this._categories);

  /// 获取分类列表：单一列表按 sortOrder 升序（内置 25 个在前，自建在后）。
  /// 家庭维度：内置（全局共享）+ 当前家庭自定义
  Future<List<Category>> getCategories() async {
    final rows = await _categories.listAll(await CurrentFamilyStore.get());
    return rows
        .map((r) => Category(
              id: r.id,
              name: r.name,
              icon: r.icon,
              nameKey: r.nameKey,
              sortOrder: r.sortOrder,
            ))
        .toList();
  }

  /// 近 90 天分类使用频次（选择器软提示排序用），key 为 `分类ID|方向`
  Future<Map<String, int>> getRecentUsageCounts({
    Duration window = const Duration(days: 90),
  }) async {
    return _categories.recentUsageCounts(
      await CurrentFamilyStore.get(),
      DateTime.now().subtract(window),
    );
  }

  /// 添加自定义分类（中性分类：无收支类型；nameKey 恒为 null）
  Future<Map<String, dynamic>> addCategory({
    required String name,
    required String icon,
  }) async {
    final trimmed = name.trim();
    final familyId = await CurrentFamilyStore.get();
    if (await _categories.countByName(familyId, trimmed) > 0) {
      throw const LocalizedException(LocalizedErrorCode.categoryNameExists);
    }

    final row = await _categories.insert(
      familyId,
      local.CategoriesCompanion.insert(
        name: trimmed,
        icon: icon,
      ),
    );

    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
    return <String, dynamic>{
      'id': row.id,
      'name': row.name,
      'icon': row.icon,
      'nameKey': row.nameKey,
    };
  }

  /// 删除分类：内置分类不可删，自定义分类软删除
  Future<void> deleteCategory(String id) async {
    final category = await _categories.findById(id);
    if (category == null) {
      throw const LocalizedException(LocalizedErrorCode.categoryNotFound);
    }
    if (category.isBuiltin) {
      throw const LocalizedException(LocalizedErrorCode.builtinCategoryNotDeletable);
    }
    await _categories.softDelete(id);
    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
  }

  /// 更新分类：仅限自定义分类，名称全局查重（排除自身）。
  /// 分类中性化后不再有 type 字段可改。
  Future<Map<String, dynamic>> updateCategory({
    required String id,
    required String name,
    required String icon,
  }) async {
    final category = await _categories.findById(id);
    if (category == null) {
      throw const LocalizedException(LocalizedErrorCode.categoryNotFound);
    }
    if (category.isBuiltin) {
      throw const LocalizedException(LocalizedErrorCode.builtinCategoryNotEditable);
    }

    final trimmed = name.trim();
    if (trimmed.isNotEmpty &&
        await _categories.countByName(
          await CurrentFamilyStore.get(),
          trimmed,
          excludeId: id,
        ) >
            0) {
      throw const LocalizedException(LocalizedErrorCode.categoryNameExists);
    }

    final row = await _categories.update(
      id,
      local.CategoriesCompanion(
        name: Value(trimmed),
        icon: Value(icon),
      ),
    );

    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
    return <String, dynamic>{
      'id': row.id,
      'name': row.name,
      'icon': row.icon,
      'nameKey': row.nameKey,
    };
  }
}
