import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_engine.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/category_rule_repository.dart';
import 'package:xiji_flutter/data/local/voice_transaction_parser.dart';
import 'package:xiji_flutter/models/category_keyword_rule.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late CategoryRuleRepository rules;
  late VoiceTransactionParser parser;

  // 内置规则（测试内固定样例，与 asset 结构一致）
  final testRules = CategoryKeywordRule.parseList('''
  {
    "rules": [
      { "keywords": ["瑞幸"], "category": "餐饮", "type": 1 },
      { "keywords": ["超市"], "category": "购物", "type": 1 },
      { "keywords": ["工资"], "category": "工资", "type": 0 }
    ]
  }
  ''');

  setUp(() async {
    // 引擎类型缓存经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    rules = CategoryRuleRepository(db);
    final engine = CategoryEngine(rules, categories, testRules);
    parser = VoiceTransactionParser(engine, categories);
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime(2026, 10, 21, 15, 0);
  final diningId = BuiltinCategories.byName('餐饮', 1)!.id;
  final salaryId = BuiltinCategories.byName('工资', 0)!.id;

  group('任务 4.1：解析引擎 + 分类命中 + 置信度自评', () {
    test('典型句式：金额/类型/分类齐备 → 有把握直接入库', () async {
      final result = await parser.parse('在瑞幸买了杯咖啡三十块', now: now);
      expect(result.amount, 30);
      expect(result.type, 1);
      expect(result.categoryId, diningId);
      expect(result.categoryName, '餐饮');
      expect(result.date, isNull, reason: '未提日期，由调用方默认今天');
      expect(result.isConfident, isTrue);
    });

    test('分类未命中 → 不猜测，无把握落预填表单', () async {
      final result = await parser.parse('买了点东西花了二十块', now: now);
      expect(result.amount, 20);
      expect(result.type, 1);
      expect(result.categoryId, isNull);
      expect(result.categoryName, isNull);
      expect(result.isConfident, isFalse);
    });

    test('无金额：分类命中也不算有把握', () async {
      final result = await parser.parse('在瑞幸买了杯咖啡', now: now);
      expect(result.amount, isNull);
      expect(result.categoryId, diningId);
      expect(result.isConfident, isFalse);
    });

    test('多金额冲突：分类命中也不算有把握', () async {
      final result =
          await parser.parse('在瑞幸买咖啡30块又买蛋糕15元', now: now);
      expect(result.amount, 30);
      expect(result.amountConflict, isTrue);
      expect(result.categoryId, diningId);
      expect(result.isConfident, isFalse);
    });

    test('类型未明示：不做分类判定，无把握', () async {
      final result = await parser.parse('瑞幸咖啡三十元', now: now);
      expect(result.type, isNull);
      expect(result.categoryId, isNull, reason: '类型未知时跳过分类判定');
      expect(result.isConfident, isFalse);
    });

    test('类型词决定分类侧：收入词过滤掉支出侧规则命中', () async {
      // 「瑞幸」是支出规则，但「退款」收入词更早出现 → 收入口径判定，
      // 支出规则被过滤，文本又无收入侧关键词可命中
      final result = await parser.parse('收到退款，顺便在瑞幸买了三十块', now: now);
      expect(result.type, 0);
      expect(result.categoryId, isNull, reason: '瑞幸支出规则被收入口径过滤');
      expect(result.isConfident, isFalse);
    });

    test('学习表命中：语音指认过的原文再次说出自动命中', () async {
      // 用户曾把这句口语指认为「工资」收入分类（source=1 语音记账）
      await rules.assign(
          matchText: '这个月补贴到账五千块', categoryId: salaryId, source: 1);

      final result = await parser.parse('这个月补贴到账五千块', now: now);
      expect(result.type, 0);
      expect(result.categoryId, salaryId);
      expect(result.categoryName, '工资');
      expect(result.amount, 5000);
      expect(result.isConfident, isTrue);
    });
  });
}
