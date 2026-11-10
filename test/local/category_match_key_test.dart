import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_match_key.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';

/// 学习表匹配键归一化：写入与读取共用同一实现。
void main() {
  final diningId = BuiltinCategories.byName('餐饮')!.id;
  final entertainmentId = BuiltinCategories.byName('娱乐')!.id;

  group('归一化规则', () {
    test('折叠并去除空白（含全角空格）、转小写', () {
      expect(
        normalizeCategoryMatchKey('  星巴克  Coffee \u3000'),
        '星巴克coffee',
      );
    });

    test('去掉常见门店后缀', () {
      expect(normalizeCategoryMatchKey('星巴克旗舰店'), '星巴克');
      expect(normalizeCategoryMatchKey('某某专营店'), '某某');
      expect(normalizeCategoryMatchKey('瑞幸咖啡（杭州分店）'), '瑞幸咖啡');
      expect(normalizeCategoryMatchKey('便利店第3号店'), '便利店');
    });

    test('主体过短时不裁剪，避免把店名本身吃掉', () {
      expect(normalizeCategoryMatchKey('旗舰店'), '旗舰店');
      expect(normalizeCategoryMatchKey('分店'), '分店');
    });

    test('空串归一化后仍为空', () {
      expect(normalizeCategoryMatchKey('   '), '');
    });
  });

  group('仓储读写共用归一化', () {
    late AppDatabase db;
    late CategoryRuleRepository rules;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      rules = CategoryRuleRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('不同写法收敛为同一条，读取命中同一分类', () async {
      await rules.assign(
        matchText: ' 星巴克  咖啡旗舰店 ',
        categoryId: diningId,
        source: 0,
      );

      expect((await rules.findByMatchText('星巴克咖啡'))!.categoryId, diningId);
      expect(
        (await rules.findByMatchText('  星巴克咖啡  '))!.categoryId,
        diningId,
      );

      // 再次指认应覆盖同一条，不新增
      await rules.assign(
        matchText: '星巴克咖啡',
        categoryId: entertainmentId,
        source: 0,
      );
      final rows = await db.select(db.categoryRules).get();
      expect(rows, hasLength(1));
      expect(rows.single.categoryId, entertainmentId);
    });

    test('旧数据兼容：归一化键未命中时按原文回退', () async {
      await db.into(db.categoryRules).insert(
            CategoryRulesCompanion.insert(
              matchText: 'Starbucks',
              categoryId: diningId,
              source: 0,
            ),
          );

      final hit = await rules.findByMatchText('Starbucks');
      expect(hit!.categoryId, diningId, reason: '大小写差异不应导致丢命中');
    });

    test('clearAll 软删全部、返回条数，墓碑可被重新指认复活', () async {
      await rules.assign(matchText: '甲商户', categoryId: diningId, source: 0);
      await rules.assign(matchText: '乙商户', categoryId: diningId, source: 0);

      expect(await rules.clearAll(), 2);
      expect(await rules.findByMatchText('甲商户'), isNull);
      expect(await rules.clearAll(), 0, reason: '已清空时不再重复计数');

      await rules.assign(
          matchText: '甲商户', categoryId: entertainmentId, source: 0);
      expect(
        (await rules.findByMatchText('甲商户'))!.categoryId,
        entertainmentId,
        reason: '墓碑占据唯一键，重新指认应复活而非插入重复行',
      );
      expect(await db.select(db.categoryRules).get(), hasLength(2));
    });
  });
}
