import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/services/api/category_service.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late CategoryService service;

  setUp(() {
    // 门面内部经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRepository(db);
    service = CategoryService.withRepos(repo);
  });

  tearDown(() async {
    await db.close();
  });

  CategoriesCompanion newCat(
    String name, {
    String icon = 'category',
    String? id,
  }) =>
      CategoriesCompanion.insert(
        name: name,
        icon: icon,
        id: id == null ? const Value.absent() : Value(id),
      );

  group('分类仓储（中性分类 v10：单一列表/全局查重/墓碑）', () {
    test('列表：单一 sortOrder 序列，25 个内置在前、自定义顺延在后', () async {
      final custom = await repo.insert('', newCat('猫舍', icon: 'pets'));

      final list = await repo.listAll('');
      expect(list.first.id, BuiltinCategories.all.first.id,
          reason: '内置分类固定排在最前（与常量表顺序一致）');
      expect(list.indexOf(custom), BuiltinCategories.all.length,
          reason: '自定义分类排在 25 个内置分类之后');
      expect(list.last.id, custom.id);

      // 内置分类种子顺序完整保留
      final builtinIds = list.where((c) => c.isBuiltin).map((c) => c.id);
      expect(builtinIds, BuiltinCategories.all.map((c) => c.id));
    });

    test('新增：sortOrder 取全局最大值 +1（不再按收支分序列）', () async {
      final first = await repo.insert('', newCat('自定义甲'));
      final second = await repo.insert('', newCat('自定义乙'));

      expect(first.sortOrder, BuiltinCategories.all.last.sortOrder + 1);
      expect(second.sortOrder, first.sortOrder + 1);
    });

    test('按名称查找：大小写不敏感，墓碑不可见', () async {
      final hit = await repo.findByName('', '餐饮');
      expect(hit, isNotNull, reason: '内置分类按名称可解析');

      final custom = await repo.insert('', newCat('CoffeeShop'));
      expect((await repo.findByName('', 'coffeeshop'))?.id, custom.id,
          reason: '英文自建分类查名不区分大小写');

      await repo.softDelete(custom.id);
      expect(await repo.findByName('', 'CoffeeShop'), isNull, reason: '墓碑不可见');
    });

    test('同名计数：排除自身后改名查重', () async {
      final custom = await repo.insert('', newCat('猫舍'));
      expect(await repo.countByName('', '猫舍'), 1);
      expect(await repo.countByName('', '猫舍', excludeId: custom.id), 0,
          reason: '排除自身后改回原名应放行');
    });

    test('家庭隔离：自定义分类仅归属家庭可见，内置分类全局共享', () async {
      final f1Cat = await repo.insert('f1', newCat('猫舍'));
      await repo.insert('f2', newCat('会所'));

      final f1List = await repo.listAll('f1');
      expect(f1List.map((c) => c.id), contains(f1Cat.id));
      expect(f1List.where((c) => !c.isBuiltin).map((c) => c.name),
          isNot(contains('会所')),
          reason: '他家的自定义分类不可见');
      expect(f1List.where((c) => c.isBuiltin).length,
          BuiltinCategories.all.length,
          reason: '内置分类在任何家庭口径下都全局共享');
      expect(await repo.countByName('f2', '猫舍'), 0,
          reason: '查重范围不含他家的自定义分类');
    });

    test('近 90 天使用频次：按分类+方向聚合，type=2 不参与', () async {
      SharedPreferences.setMockInitialValues({});
      final cat = await repo.insert('', newCat('猫舍'));
      Future<void> addTx(String id, int type, DateTime date) async {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: Value(id),
              type: type,
              categoryId: cat.id,
              amountCents: 100,
              date: date,
              userId: 'user-1',
            ));
      }

      final now = DateTime.now();
      await addTx('t1', 1, now.subtract(const Duration(days: 1)));
      await addTx('t2', 1, now.subtract(const Duration(days: 2)));
      await addTx('t3', 0, now.subtract(const Duration(days: 3)));
      await addTx('t4', 2, now.subtract(const Duration(days: 4))); // 不计收支
      await addTx('t5', 1, now.subtract(const Duration(days: 120))); // 超窗口

      final counts = await repo.recentUsageCounts(
          '', now.subtract(const Duration(days: 90)));
      expect(counts['${cat.id}|1'], 2);
      expect(counts['${cat.id}|0'], 1);
      expect(counts['${cat.id}|2'], isNull, reason: 'type=2 不计收支不参与频次');
    });

    test('编辑：version+1、updatedAt 刷新、发件箱置位', () async {
      final custom = await repo.insert('', newCat('猫舍', icon: 'pets'));

      final updated = await repo.update(
          custom.id, const CategoriesCompanion(name: Value('猫咪乐园')));

      expect(updated.version, custom.version + 1);
      expect(updated.updatedAt.isBefore(custom.updatedAt), false);
      expect(updated.syncPending, true);
      expect(updated.name, '猫咪乐园');
    });

    test('软删除墓碑：行保留、查询不可见', () async {
      final custom = await repo.insert('', newCat('猫舍'));
      await repo.softDelete(custom.id);

      final tombstone = await (db.select(db.categories)
            ..where((c) => c.id.equals(custom.id)))
          .getSingle();
      expect(tombstone.deleted, true, reason: '删除为软删除墓碑');
      expect(tombstone.syncPending, true);

      expect(await repo.findById(custom.id), isNull);
      expect((await repo.listAll('')).map((c) => c.id),
          isNot(contains(custom.id)));
    });
  });

  group('分类门面（内置保护 + 自定义增删改，无 type 维度）', () {
    test('getCategories：内置 25 个在前 + 自定义在后，返回 nameKey', () async {
      final custom = await repo.insert('', newCat('猫舍', icon: 'pets'));
      final categories = await service.getCategories();

      expect(categories.first.id, BuiltinCategories.all.first.id);
      expect(categories.first.nameKey, 'categoryDining');
      final customDto = categories.firstWhere((c) => c.id == custom.id);
      expect(customDto.name, '猫舍');
      expect(customDto.nameKey, isNull, reason: '自建分类无 nameKey，显示原文');
    });

    test('新增自定义分类：与内置分类重名被拒（全局唯一），正常新增放行', () async {
      await expectLater(
        service.addCategory(name: '餐饮', icon: 'restaurant'),
        throwsA(isA<Exception>()),
        reason: '与内置分类重名必须拒绝',
      );

      final result = await service.addCategory(name: '猫舍', icon: 'pets');
      expect(result['name'], '猫舍');
      expect(result['nameKey'], isNull);
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

      final custom = await repo.insert('', newCat('猫舍'));
      await service.deleteCategory(custom.id);
      expect(await repo.findById(custom.id), isNull, reason: '自定义分类墓碑后不可见');
    });

    test('更新：内置分类被拒；自定义可改名', () async {
      final diningId =
          BuiltinCategories.all.firstWhere((c) => c.name == '餐饮').id;
      await expectLater(
        service.updateCategory(id: diningId, name: '饭钱', icon: 'restaurant'),
        throwsA(isA<Exception>()),
        reason: '内置分类不可修改',
      );

      final custom = await repo.insert('', newCat('猫舍', icon: 'pets'));
      final result = await service.updateCategory(
        id: custom.id,
        name: '猫咪乐园',
        icon: 'cruelty_free',
      );

      expect(result['name'], '猫咪乐园');
      expect(result.containsKey('type'), false, reason: '分类中性化后无 type 字段');
      expect((await repo.findById(custom.id))!.icon, 'cruelty_free');
    });

    test('更新：改成既有名称被拒，改回自身原名放行', () async {
      final custom = await repo.insert('', newCat('猫舍'));
      final other = await repo.insert('', newCat('猫咪乐园'));

      await expectLater(
        service.updateCategory(
            id: custom.id, name: '猫咪乐园', icon: 'pets'),
        throwsA(isA<Exception>()),
        reason: '与其他分类重名必须拒绝',
      );

      final result = await service.updateCategory(
          id: other.id, name: '猫咪乐园', icon: 'pets');
      expect(result['name'], '猫咪乐园', reason: '改回自身原名应放行');
    });
  });
}
