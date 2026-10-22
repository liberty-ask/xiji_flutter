import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/services/api/category_service.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late CategoryService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRepository(db);
    service = CategoryService.withRepos(repo);
  });

  tearDown(() async {
    await db.close();
  });

  CategoriesCompanion newCat(
    String name,
    int type, {
    String icon = 'category',
    String? id,
  }) =>
      CategoriesCompanion.insert(
        name: name,
        icon: icon,
        type: type,
        id: id == null ? const Value.absent() : Value(id),
      );

  group('任务 2.5：分类仓储（列表/查重/墓碑）', () {
    test('列表：类型分组（支出在前），同类型内置种子序在前、自定义在后', () async {
      final custom = await repo.insert(newCat('猫舍', 1, icon: 'pets'));

      final list = await repo.listAll();
      expect(list.first.id, BuiltinCategories.all.first.id,
          reason: '支出内置分类固定排在最前（与常量表顺序一致）');
      // 0-12 位为支出内置分类种子（含「未分类」兜底），自定义支出紧随其后、先于收入内置分类
      expect(list.indexOf(custom), 13);
      expect(list.last.type, 0, reason: '收入分类整体排在支出之后');

      // 内置分类种子顺序完整保留
      final builtinIds = list.where((c) => c.isBuiltin).map((c) => c.id);
      expect(builtinIds, BuiltinCategories.all.map((c) => c.id));
    });

    test('新增：sortOrder 取同类型最大值 +1', () async {
      final first = await repo.insert(newCat('自定义甲', 1));
      final second = await repo.insert(newCat('自定义乙', 1));
      final incomeCat = await repo.insert(newCat('自定义收入', 0));

      expect(second.sortOrder, first.sortOrder + 1);
      // 不同类型独立计数：收入自定义从内置收入最大序号 +1 起
      expect(incomeCat.sortOrder, lessThan(first.sortOrder),
          reason: '内置收入分类少（6 项），收入自定义序号应小于支出侧');
    });

    test('按名称查找：命中名称与类型，墓碑不可见', () async {
      final hit = await repo.findByName('餐饮', 1);
      expect(hit, isNotNull, reason: '内置分类按名称可解析（记账写入路径）');
      expect(await repo.findByName('餐饮', 0), isNull,
          reason: '餐饮是支出分类，收入侧不得命中');

      final custom = await repo.insert(newCat('猫舍', 1));
      await repo.softDelete(custom.id);
      expect(await repo.findByName('猫舍', 1), isNull, reason: '墓碑不可见');
    });

    test('同名计数：排除自身后改名查重', () async {
      final custom = await repo.insert(newCat('猫舍', 1));
      expect(await repo.countByName('猫舍', 1), 1);
      expect(await repo.countByName('猫舍', 1, excludeId: custom.id), 0,
          reason: '排除自身后改回原名应放行');
    });

    test('编辑：version+1、updatedAt 刷新、发件箱置位', () async {
      final custom = await repo.insert(newCat('猫舍', 1, icon: 'pets'));

      final updated =
          await repo.update(custom.id, const CategoriesCompanion(name: Value('猫咪乐园')));

      expect(updated.version, custom.version + 1);
      expect(updated.updatedAt.isBefore(custom.updatedAt), false);
      expect(updated.syncPending, true);
      expect(updated.name, '猫咪乐园');
    });

    test('软删除墓碑：行保留、查询不可见', () async {
      final custom = await repo.insert(newCat('猫舍', 1));
      await repo.softDelete(custom.id);

      final tombstone = await (db.select(db.categories)
            ..where((c) => c.id.equals(custom.id)))
          .getSingle();
      expect(tombstone.deleted, true, reason: '删除为软删除墓碑');
      expect(tombstone.syncPending, true);

      expect(await repo.findById(custom.id), isNull);
      expect((await repo.listAll()).map((c) => c.id),
          isNot(contains(custom.id)));
    });
  });

  group('任务 2.5：分类门面（内置保护 + 自定义增删改）', () {
    test('getCategories：内置在前 + 自定义在后', () async {
      final custom = await repo.insert(newCat('猫舍', 1, icon: 'pets'));
      final categories = await service.getCategories();

      expect(categories.first.id, BuiltinCategories.all.first.id);
      expect(categories.any((c) => c.id == custom.id && c.name == '猫舍'),
          isTrue);
    });

    test('新增自定义分类：与内置分类重名被拒，正常新增放行', () async {
      await expectLater(
        service.addCategory(name: '餐饮', icon: 'restaurant', type: 1),
        throwsA(isA<Exception>()),
        reason: '与内置分类重名必须拒绝',
      );

      final result =
          await service.addCategory(name: '猫舍', icon: 'pets', type: 1);
      expect(result['name'], '猫舍');
      expect(result['id'], isNotEmpty);
      expect((await service.getCategories()).any((c) => c.name == '猫舍'),
          isTrue);
    });

    test('删除：内置分类被拒，自定义分类软删除', () async {
      final diningId =
          BuiltinCategories.all.firstWhere((c) => c.name == '餐饮').id;
      await expectLater(
        service.deleteCategory(diningId),
        throwsA(isA<Exception>()),
        reason: '内置分类不可删除',
      );

      final custom = await repo.insert(newCat('猫舍', 1));
      await service.deleteCategory(custom.id);
      expect(await repo.findById(custom.id), isNull, reason: '自定义分类墓碑后不可见');
    });

    test('更新：内置分类被拒；自定义可改名，type 不随更新改变', () async {
      final diningId =
          BuiltinCategories.all.firstWhere((c) => c.name == '餐饮').id;
      await expectLater(
        service.updateCategory(id: diningId, name: '饭钱', icon: 'restaurant', type: 1),
        throwsA(isA<Exception>()),
        reason: '内置分类不可修改',
      );

      final custom = await repo.insert(newCat('猫舍', 1, icon: 'pets'));
      final result = await service.updateCategory(
        id: custom.id,
        name: '猫咪乐园',
        icon: 'cruelty_free',
        type: 0, // 传入不同 type 也不得改型
      );

      expect(result['name'], '猫咪乐园');
      expect(result['type'], 1, reason: '分类类型不可变（对齐服务端语义）');
      expect((await repo.findById(custom.id))!.icon, 'cruelty_free');
    });

    test('更新：改成同类型既有名称被拒，改回自身原名放行', () async {
      final custom = await repo.insert(newCat('猫舍', 1));
      final other = await repo.insert(newCat('猫咪乐园', 1));

      await expectLater(
        service.updateCategory(
            id: custom.id, name: '猫咪乐园', icon: 'pets', type: 1),
        throwsA(isA<Exception>()),
        reason: '与其他分类重名必须拒绝',
      );

      final result = await service.updateCategory(
          id: other.id, name: '猫咪乐园', icon: 'pets', type: 1);
      expect(result['name'], '猫咪乐园', reason: '改回自身原名应放行');
    });
  });
}
