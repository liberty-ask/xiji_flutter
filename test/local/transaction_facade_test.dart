import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/utils/money.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/statistics_repository.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/models/transaction.dart' as models;
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/services/api/transaction_service.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository txRepo;
  late TransactionService txService;

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36'; // 餐饮（内置）

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 本地用户缓存 mock：离线身份来源
    SharedPreferences.setMockInitialValues({
      LocalUser.profileKey: jsonEncode(User(
        id: 'u1',
        nickname: '测试用户',
        phone: '13800000000',
        role: 0,
      ).toJson()),
    });

    db = AppDatabase(NativeDatabase.memory());
    txRepo = TransactionRepository(db);
    txService = TransactionService.withRepos(
      txRepo,
      CategoryRepository(db),
      StatisticsRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  models.TransactionType txType(int v) => models.TransactionType.fromInt(v);

  // 经仓储直接种入（type=2 中性交易真实路径仅账单导入，其 userId/分类
  // 由导入流程决定，不经记账门面的名称解析，测试同样直接落库）
  Future<void> seedRaw({
    required String desc,
    required int type,
    required double amount,
    required DateTime date,
    String userId = 'u1',
  }) async {
    await txRepo.insert(TransactionsCompanion.insert(
      type: type,
      categoryId: diningId,
      amountCents: Money.yuanToCents(amount),
      date: date,
      userId: userId,
      description: Value(desc),
    ));
  }

  group('任务 2.1：记账门面（写入走本地库）', () {
    test('新增：分类按名称解析为 ID，用户取本地缓存，落库 UUIDv7', () async {
      final now = DateTime.now();
      await txService.addTransaction(
        type: 1,
        category: '餐饮',
        amount: 30,
        date: '2026-10-15',
        note: '瑞幸拿铁',
      );

      final list = await txRepo.listAll('');
      expect(list, hasLength(1));
      final row = list.single;
      expect(row.categoryId, diningId, reason: '分类名称应解析为内置餐饮 ID');
      expect(row.userId, 'u1', reason: '用户取本地缓存，离线可用');
      expect(row.id, isNotEmpty);
      expect(row.description, '瑞幸拿铁');
      expect(row.date, DateTime(2026, 10, 15));
      expect(row.syncPending, true);
      expect(row.version, 1, reason: '业务变更 version 从 1 起');
      // 静态验证 now 仅用于框定时间范围，落库 ID 为 UUIDv7 格式
      expect(row.updatedAt.isBefore(now.add(const Duration(minutes: 1))), true);
    });

    test('新增：分类名称不存在时拒绝', () async {
      await expectLater(
        txService.addTransaction(
          type: 1,
          category: '不存在的分类',
          amount: 10,
          date: '2026-10-15',
        ),
        throwsA(isA<Exception>()),
      );
      expect(await txRepo.listAll(''), isEmpty);
    });

    test('编辑：改名分类重解析、version+1、备注传 null 清空', () async {
      await txService.addTransaction(
        type: 1,
        category: '餐饮',
        amount: 30,
        date: '2026-10-15',
        note: '瑞幸拿铁',
      );
      final before = (await txRepo.listAll('')).single;

      await txService.updateTransaction(
        id: before.id,
        type: 1,
        category: '交通',
        amount: 15,
        date: '2026-10-16',
        note: null,
      );

      final row = await txRepo.findById(before.id);
      expect(row!.categoryId,
          isNot(diningId), reason: '编辑应把分类解析为新的 ID');
      expect(row.amountCents, 1500);
      expect(row.date, DateTime(2026, 10, 16));
      expect(row.description, isNull, reason: '备注传 null 应清空');
      expect(row.version, before.version + 1);
      expect(row.syncPending, true);
    });

    test('删除：软删除墓碑，列表不可见', () async {
      await txService.addTransaction(
        type: 1,
        category: '餐饮',
        amount: 30,
        date: '2026-10-15',
      );
      final id = (await txRepo.listAll('')).single.id;

      await txService.deleteTransaction(id);

      expect(await txRepo.findById(id), isNull);
      expect(await txRepo.listAll(''), isEmpty);
      // 墓碑行保留参与同步
      final tombstone = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tombstone.deleted, true);
    });

    test('删除：记录不存在时拒绝', () async {
      await expectLater(
        txService.deleteTransaction('00000000-0000-7000-8000-000000000000'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('任务 2.3：明细列表/筛选/搜索门面', () {
    Future<String> seed({
      required String desc,
      int type = 1,
      double amount = 10,
      required DateTime date,
    }) async {
      final result = await txService.addTransaction(
        type: type,
        category: type == 0 ? '工资' : '餐饮',
        amount: amount,
        date: date.toString().split(' ').first,
        note: desc,
      );
      return result['id'] as String;
    }

    test('全量列表：分类名称与图标回填，type=2 亦可见（明细列表口径）', () async {
      await seed(desc: '午餐', date: DateTime(2026, 10, 15));
      await seed(desc: '工资', type: 0, amount: 100, date: DateTime(2026, 10, 15));
      await seedRaw(desc: '转账', type: 2, amount: 50, date: DateTime(2026, 10, 15));

      final list = await txService.getTransactions();
      expect(list, hasLength(3), reason: '明细列表可见 type=2（不计收支）记录');

      final lunch = list.firstWhere((t) => t.description == '午餐');
      expect(lunch.category, '餐饮');
      expect(lunch.icon, isNotNull);
      expect(lunch.type, txType(1));

      final neutral = list.firstWhere((t) => t.description == '转账');
      expect(neutral.type, txType(2));
    });

    test('收支类型筛选：收入/支出各自命中', () async {
      await seed(desc: '午餐', date: DateTime(2026, 10, 15));
      await seed(desc: '工资', type: 0, amount: 100, date: DateTime(2026, 10, 15));
      await seedRaw(desc: '转账', type: 2, amount: 50, date: DateTime(2026, 10, 15));

      final income = await txService.getTransactions(type: 0);
      expect(income.map((t) => t.description), ['工资']);
      final expense = await txService.getTransactions(type: 1);
      expect(expense.map((t) => t.description), ['午餐']);
      final neutral = await txService.getTransactions(type: 2);
      expect(neutral.map((t) => t.description), ['转账']);
    });

    test('日期范围与单日筛选', () async {
      await seed(desc: '一号', date: DateTime(2026, 10, 1));
      await seed(desc: '五号', date: DateTime(2026, 10, 5));
      await seed(desc: '十号', date: DateTime(2026, 10, 10));

      final range = await txService.getTransactions(
        startDate: '2026-10-02',
        endDate: '2026-10-08',
      );
      expect(range.map((t) => t.description), ['五号']);

      final day = await txService.getTransactions(date: '2026-10-05');
      expect(day.map((t) => t.description), ['五号'], reason: '单日含当天全天');
    });

    test('关键词搜索：中文逐字命中、空串不抛错、命中项含分类回填', () async {
      await seed(desc: '瑞幸拿铁', date: DateTime(2026, 10, 15));
      await seed(desc: '星巴克美式', date: DateTime(2026, 10, 15));

      final hits = await txService.getTransactions(keyword: '拿铁');
      expect(hits.map((t) => t.description), ['瑞幸拿铁']);
      expect(hits.single.category, '餐饮', reason: '搜索结果同样回填分类名称');

      final empty = await txService.getTransactions(keyword: '  ');
      expect(empty, hasLength(2), reason: '空白关键词应返回全量');
    });

    test('分页：按日期倒序取页', () async {
      for (var i = 1; i <= 5; i++) {
        await seed(desc: '第${i.toString()}笔', date: DateTime(2026, 10, i));
      }

      final page2 = await txService.getTransactions(page: 2, pageSize: 2);
      expect(page2.map((t) => t.description), ['第3笔', '第2笔']);
    });

    test('用户筛选', () async {
      await seed(desc: '我的', date: DateTime(2026, 10, 15));
      await seedRaw(desc: '他人的', type: 1, amount: 10, date: DateTime(2026, 10, 15), userId: 'u2');

      final mine = await txService.getTransactions(userId: 'u1');
      expect(mine.map((t) => t.description), ['我的']);
    });
  });

  group('任务 2.2：首页门面（月度概览 + 预算 + 近期动态）', () {
    test('结构与口径：收支排除 type=2、预算读库、动态排除 type=2', () async {
      final now = DateTime(2026, 11, 15, 12); // 固定基准，避免真实日期边界

      await txService.addTransaction(
          type: 0, category: '工资', amount: 100, date: '2026-11-15', note: '工资');
      await txService.addTransaction(
          type: 1, category: '餐饮', amount: 30, date: '2026-11-15', note: '午餐');
      await txService.addTransaction(
          type: 1,
          category: '餐饮',
          amount: 20,
          date: '2026-11-14',
          note: '晚餐');
      await txService.addTransaction(
          type: 1, category: '餐饮', amount: 50, date: '2026-10-15', note: '上月');
      await seedRaw(desc: '转账', type: 2, amount: 50, date: DateTime(2026, 11, 15));

      // 当月预算
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            year: 2026,
            month: 11,
            amountCents: 100000,
          ));

      final home = await txService.getHomeData(now);

      expect(home['income'], 100);
      expect(home['expense'], 50, reason: '本月支出 = 30 + 20，排除上月与 type=2');
      expect(home['balance'], 50);
      expect(home['todayExpense'], 30, reason: '今日支出排除 type=2');
      expect(home['yesterdayExpense'], 20);

      final budget = home['budget'] as Map<String, dynamic>;
      expect(budget['total'], 1000);
      expect(budget['used'], 50);

      final activities = home['activities'] as List;
      expect(activities, hasLength(4), reason: '近期动态排除 type=2');
      final first = activities.first as Map<String, dynamic>;
      expect(first['title'], '工资', reason: '动态标题取分类名');
      expect(first['isIncome'], true);
      expect(first['user'], '测试用户', reason: '昵称取本地缓存，离线可用');
      // 同日两笔按 updatedAt 倒序，最后插入的工资排最前
      expect(first['description'], '工资');
      expect(first['date'], '2026-11-15');
      expect(
          first['time'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
          reason: '动态时间为真实操作时间（updatedAt），格式 yyyy-MM-dd HH:mm');
    });

    test('动态标题与图标兜底：分类被删时降级', () async {
      final now = DateTime.now();

      // 经仓储挂一条自定义分类的交易，再软删分类
      final catRepo = CategoryRepository(db);
      final cat = await catRepo.insert(
        '',
        CategoriesCompanion.insert(
          name: '猫舍',
          icon: 'pets',
          type: 1,
        ),
      );
      await txRepo.insert(TransactionsCompanion.insert(
        type: 1,
        categoryId: cat.id,
        amountCents: 8800,
        date: now,
        userId: 'u1',
        description: const Value('猫粮'),
      ));
      await catRepo.softDelete(cat.id);

      final home = await txService.getHomeData();
      final first = (home['activities'] as List).first as Map<String, dynamic>;
      expect(first['title'], '猫粮', reason: '分类被删后标题降级为描述');
      expect(first['icon'], 'payments', reason: '图标兜底默认值');
    });
  });
}
