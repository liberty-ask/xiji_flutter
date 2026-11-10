import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/utils/icon_constants.dart';

void main() {
  group('任务 1.3：系统内置分类固定 UUID 常量表（中性分类 v10）', () {
    test('常量表自身：25 项、ID/名称/nameKey 唯一、UUIDv7 格式、图标名全部可解析', () {
      expect(BuiltinCategories.all.length, 25);
      expect(BuiltinCategories.all.map((c) => c.id).toSet().length, 25,
          reason: '内置分类 ID 必须唯一');
      expect(BuiltinCategories.all.map((c) => c.name).toSet().length, 25,
          reason: '分类中性化后名称全局唯一（数据库同名查重依赖此约束）');
      expect(BuiltinCategories.all.map((c) => c.nameKey).toSet().length, 25,
          reason: '多语言词条 key 必须一一对应');

      final uuidPattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      for (final c in BuiltinCategories.all) {
        expect(c.id, matches(uuidPattern), reason: '${c.name} 的 ID 不是 UUIDv7');
        expect(c.nameKey, startsWith('category'),
            reason: '${c.name} 的 nameKey 命名不符合约定');
        // 图标名必须是 IconConstants 可解析的合法名称（工程约定：渲染统一走该映射器）
        expect(IconConstants.getIconFromString(c.icon), isNot(Icons.category),
            reason: '${c.name} 的图标 "${c.icon}" 未命中图标库，将回退为默认图标');
      }
    });

    test('sortOrder 为 0–24 连续序列，未分类固定排最后', () {
      final orders = BuiltinCategories.all.map((c) => c.sortOrder).toList();
      expect(orders, List.generate(25, (i) => i));
      expect(BuiltinCategories.byId(BuiltinCategories.uncategorizedId)!.name,
          '未分类');
      expect(BuiltinCategories.all.last.sortOrder, 24);
    });

    test('两台设备（独立库）初始化后同一内置分类 ID 完全一致', () async {
      final deviceA = AppDatabase(NativeDatabase.memory());
      final deviceB = AppDatabase(NativeDatabase.memory());

      // 触发 onCreate（含种子）
      final categoriesA = await (deviceA.select(deviceA.categories)
            ..where((c) => c.isBuiltin.equals(true)))
          .get();
      final categoriesB = await (deviceB.select(deviceB.categories)
            ..where((c) => c.isBuiltin.equals(true)))
          .get();
      await deviceA.close();
      await deviceB.close();

      expect(categoriesA.length, 25);
      expect(categoriesB.length, 25);

      final idsA = categoriesA.map((c) => c.id).toSet();
      final idsB = categoriesB.map((c) => c.id).toSet();
      expect(idsA, equals(idsB), reason: 'spec: 同一内置分类在两台设备上具有相同 ID');

      final nameKeyA = {for (final c in categoriesA) c.name: c.nameKey};
      for (final b in categoriesB) {
        expect(nameKeyA[b.name], b.nameKey,
            reason: '分类 ${b.name} 在两设备上的 nameKey 不一致');
      }

      // 内置分类不进发件箱（内容随 App 版本发布，无同步必要）
      expect(categoriesA.every((c) => !c.syncPending), true,
          reason: '内置分类 syncPending 应为 false');
      // 内置分类 nameKey 必须落库（显示层只认 nameKey）
      expect(categoriesA.every((c) => (c.nameKey ?? '').isNotEmpty), true,
          reason: '内置分类 nameKey 不得为空');
    });

    test('byId / byName 查找命中与未命中（名称全局唯一，无需类型）', () {
      const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36';
      final dining = BuiltinCategories.byId(diningId);
      expect(dining, isNotNull);
      expect(dining!.name, '餐饮');
      expect(BuiltinCategories.byName('餐饮')!.id, diningId);
      expect(BuiltinCategories.byName('不存在的分类'), isNull);
      expect(BuiltinCategories.byId('00000000-0000-7000-8000-000000000000'),
          isNull);
    });

    test('已删除的历史分类 ID 不再出现在常量表', () {
      expect(BuiltinCategories.byId(BuiltinCategories.removedInvestmentId),
          isNull);
      expect(
          BuiltinCategories.byId(
              BuiltinCategories.removedIncomeUncategorizedId),
          isNull);
      // 只保留一个未分类兜底 ID
      expect(
          BuiltinCategories.all.where((c) => c.name == '未分类').length, 1);
    });
  });
}
