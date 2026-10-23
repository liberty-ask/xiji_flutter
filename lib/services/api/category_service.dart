import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../data/local/app_database.dart' as local;
import '../../data/local/category_repository.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/db_provider.dart';
import '../../models/category.dart';
import '../../sync/sync_scheduler.dart';

/// 分类数据门面：内置分类 + 自定义分类的本地读写，不发起任何网络请求。
///
/// 保护规则（对齐既有服务端语义）：
/// - 内置分类随版本发布、ID 固定，不可编辑、不可删除
/// - 自定义分类增删改自由，软删除墓碑参与后续同步
/// - 同类型下分类名称不可重复（含与内置分类重名）
class CategoryService {
  static CategoryService? _instance;

  final CategoryRepository _categories;

  CategoryService._(this._categories);

  /// 应用内单例（本地库应用级唯一实例）
  factory CategoryService() {
    _instance ??= CategoryService._(Db.categories);
    return _instance!;
  }

  /// 测试专用：注入内存库构造独立实例
  @visibleForTesting
  CategoryService.withRepos(this._categories);

  /// 获取分类列表：内置在前（种子序），自定义在后（创建序）。
  /// 家庭维度：内置（全局共享）+ 当前家庭自定义
  Future<List<Category>> getCategories() async {
    final rows = await _categories.listAll(await CurrentFamilyStore.get());
    return rows
        .map((r) => Category(
              id: r.id,
              name: r.name,
              icon: r.icon,
              type: r.type,
            ))
        .toList();
  }

  /// 添加自定义分类
  Future<Map<String, dynamic>> addCategory({
    required String name,
    required String icon,
    required int type,
  }) async {
    final trimmed = name.trim();
    final familyId = await CurrentFamilyStore.get();
    if (await _categories.countByName(familyId, trimmed, type) > 0) {
      throw Exception('该类型下分类名称已存在');
    }

    final row = await _categories.insert(
      familyId,
      local.CategoriesCompanion.insert(
        name: trimmed,
        icon: icon,
        type: type,
      ),
    );

    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
    return <String, dynamic>{
      'id': row.id,
      'name': row.name,
      'icon': row.icon,
      'type': row.type,
    };
  }

  /// 删除分类：内置分类不可删，自定义分类软删除
  Future<void> deleteCategory(String id) async {
    final category = await _categories.findById(id);
    if (category == null) {
      throw Exception('分类不存在');
    }
    if (category.isBuiltin) {
      throw Exception('内置分类不可删除');
    }
    await _categories.softDelete(id);
    // 发件箱后台推送（fire-and-forget）
    unawaited(SyncScheduler.instance.maybePush());
  }

  /// 更新分类：仅限自定义分类，同类型下名称查重（排除自身）。
  /// type 不随更新改变（对齐既有服务端语义：分类类型不可变，
  /// 防止已挂交易的分类改型污染收支统计）。
  Future<Map<String, dynamic>> updateCategory({
    required String id,
    required String name,
    required String icon,
    required int type,
  }) async {
    final category = await _categories.findById(id);
    if (category == null) {
      throw Exception('分类不存在');
    }
    if (category.isBuiltin) {
      throw Exception('内置分类不可修改');
    }

    final trimmed = name.trim();
    if (trimmed.isNotEmpty &&
        await _categories.countByName(
          await CurrentFamilyStore.get(),
          trimmed,
          category.type,
          excludeId: id,
        ) >
            0) {
      throw Exception('该类型下分类名称已存在');
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
      'type': row.type,
    };
  }
}
