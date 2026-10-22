import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/local_user.dart';
import 'package:xiji_flutter/data/local/statistics_repository.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/models/user.dart';
import 'package:xiji_flutter/services/api/statistics_service.dart';

/// 任务 2.6：统计门面复刻服务端五个统计接口的响应结构
/// （概览 / 分类统计 / 趋势 / 成员 / 日历），页面零改动离线消费。
void main() {
  late AppDatabase db;
  late TransactionRepository txRepo;
  late StatisticsService service;

  const diningId = '01a15d13-bded-710c-a3bd-aba94a5aeb36'; // 餐饮（内置，支出）
  const shoppingId = '01a15d13-bdef-75ae-8342-df8b6acf41fa'; // 购物（内置，支出）
  const salaryId = '01a15d13-bdf0-7a5f-993a-8442815623e1'; // 工资（内置，收入）

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 本地用户缓存 mock：一期单成员语义下的成员身份来源
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
    service = StatisticsService.withRepos(StatisticsRepository(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(
    int type,
    double amount,
    DateTime date, {
    String categoryId = diningId,
  }) =>
      txRepo.insert(TransactionsCompanion.insert(
        type: type,
        categoryId: categoryId,
        amount: amount,
        date: date,
        userId: 'u1',
      ));

  group('任务 2.6：统计门面（对齐服务端响应结构）', () {
    test('分类统计：降序条目、格式化金额与占比、环比、limit', () async {
      await seed(1, 255, DateTime(2026, 10, 2)); // 餐饮
      await seed(1, 12345, DateTime(2026, 10, 3), categoryId: shoppingId);
      await seed(0, 8000, DateTime(2026, 10, 4), categoryId: salaryId); // 类型不匹配
      await seed(1, 12000, DateTime(2026, 9, 15)); // 上月环比分母

      final data = await service.getStatistics(
          type: 1, year: 2026, period: 'month', month: 10);

      expect(data['total'], '12,600', reason: '千分位、无小数、无¥');
      expect(data['change'], '+5%'); // (12600-12000)/12000*100
      final items = data['items'] as List;
      expect(items.length, 2, reason: '收入交易不计入支出统计');
      expect(items[0]['name'], '购物', reason: '按金额降序');
      expect(items[0]['amount'], '¥12,345');
      expect(items[0]['pct'], '98%'); // 12345/12600 = 97.98
      expect(items[0]['color'], '#13ec5b');
      expect(items[0]['icon'], isNotNull);
      expect(items[1]['name'], '餐饮');
      expect(items[1]['amount'], '¥255');
      expect(items[1]['pct'], '2%'); // 255/12600 = 2.02
      expect(items[1]['color'], '#fbbf24');

      final limited = await service.getStatistics(
          type: 1, year: 2026, period: 'month', month: 10, limit: 1);
      final limitedItems = limited['items'] as List;
      expect(limitedItems.length, 1);
      expect(limitedItems[0]['name'], '购物');
    });

    test('概览：收支与环比、笔数排除 type=2', () async {
      await seed(0, 8000, DateTime(2026, 10, 1), categoryId: salaryId);
      await seed(1, 100, DateTime(2026, 10, 2));
      await seed(2, 9999, DateTime(2026, 10, 3)); // 不计收支不进概览
      await seed(0, 4000, DateTime(2026, 9, 5), categoryId: salaryId);
      await seed(1, 200, DateTime(2026, 9, 8));

      final data =
          await service.getOverview(year: 2026, period: 'month', month: 10);

      expect(data['totalIncome'], 8000);
      expect(data['totalExpense'], 100);
      expect(data['netIncome'], 7900);
      expect(data['incomeChange'], 100.0); // (8000-4000)/4000*100
      expect(data['expenseChange'], -50.0); // (100-200)/200*100
      expect(data['transactionCount'], 2, reason: 'type=2 不计笔数');
      expect(data['avgDailyIncome'], null, reason: '服务端未赋值，保留占位');
      expect(data['avgDailyExpense'], null);
    });

    test('周维度：当周区间与上周环比分母', () async {
      await seed(1, 70, DateTime(2026, 10, 20)); // 本周二
      await seed(1, 30, DateTime(2026, 10, 13)); // 上周二
      await seed(1, 500, DateTime(2026, 10, 26)); // 区间后，不计入

      final stats = await service.getStatistics(
          type: 1,
          year: 2026,
          period: 'week',
          weekStartDate: '2026-10-19',
          weekEndDate: '2026-10-25');
      expect(stats['total'], '70');
      expect(stats['change'], '+133%'); // (70-30)/30*100 = 133.33

      final overview = await service.getOverview(
          year: 2026,
          period: 'week',
          weekStartDate: '2026-10-19',
          weekEndDate: '2026-10-25');
      expect(overview['totalExpense'], 70);
      expect(overview['expenseChange'], closeTo(133.33, 0.01));
      expect(overview['transactionCount'], 1);
    });

    test('趋势月维度：31 天逐日、首项无环比、汇总均值 2 位小数', () async {
      await seed(0, 8000, DateTime(2026, 10, 2), categoryId: salaryId);
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 70, DateTime(2026, 10, 5));
      await seed(1, 50, DateTime(2026, 11, 1)); // 区间外

      final data =
          await service.getTrend(year: 2026, period: 'month', month: 10);
      final items = data['items'] as List;
      expect(items.length, 31);

      final first = items[0] as Map<String, dynamic>;
      expect(first['date'], '2026-10-01');
      expect(first['dateLabel'], '10月1日');
      expect(first['incomeChange'], null, reason: '首项无环比');
      expect(first['expenseChange'], null);

      final d2 = items[1] as Map<String, dynamic>;
      expect(d2['income'], 8000);
      expect(d2['expense'], 30);
      expect(d2['net'], 7970);
      expect(d2['incomeChange'], 100.0, reason: '前一日为 0 时 +100');
      expect(d2['expenseChange'], 100.0);

      final d5 = items[4] as Map<String, dynamic>;
      expect(d5['expense'], 70);
      expect(d5['expenseChange'], 100.0);

      final summary = data['summary'] as Map<String, dynamic>;
      expect(summary['totalIncome'], 8000);
      expect(summary['totalExpense'], 100);
      expect(summary['avgIncome'], 258.06); // 8000/31 保留 2 位
      expect(summary['avgExpense'], 3.23); // 100/31 = 3.2258
      expect(summary['maxIncome'], 8000);
      expect(summary['maxExpense'], 70);
    });

    test('趋势年维度：12 个月按月聚合，type 过滤清零对侧列', () async {
      await seed(1, 100, DateTime(2026, 3, 10));
      await seed(0, 8000, DateTime(2026, 10, 2), categoryId: salaryId);
      await seed(1, 150, DateTime(2026, 10, 5));

      final data =
          await service.getTrend(type: 1, year: 2026, period: 'year');
      final items = data['items'] as List;
      expect(items.length, 12);
      expect((items[0] as Map<String, dynamic>)['date'], '2026-01');
      expect((items[0] as Map<String, dynamic>)['dateLabel'], '2026年1月');

      final march = items[2] as Map<String, dynamic>;
      expect(march['expense'], 100);
      expect(march['income'], 0, reason: 'type=1 时收入列清零');

      final oct = items[9] as Map<String, dynamic>;
      expect(oct['date'], '2026-10');
      expect(oct['dateLabel'], '2026年10月');
      expect(oct['expense'], 150);
      expect(oct['net'], -150);
      expect(oct['expenseChange'], 100.0, reason: '上月支出为 0 时 +100');

      final summary = data['summary'] as Map<String, dynamic>;
      expect(summary['totalExpense'], 250);
      expect(summary['avgExpense'], 20.83); // 250/12 = 20.833
      expect(summary['maxExpense'], 150);
      expect(summary['totalIncome'], 0);
    });

    test('趋势周维度：period=day 周内逐日', () async {
      await seed(1, 50, DateTime(2026, 10, 15)); // 周四
      await seed(0, 100, DateTime(2026, 10, 16), categoryId: salaryId);
      await seed(1, 25, DateTime(2026, 10, 18)); // 周日

      final data = await service.getTrend(
          year: 2026,
          period: 'day',
          weekStartDate: '2026-10-13',
          weekEndDate: '2026-10-19');
      final items = data['items'] as List;
      expect(items.length, 7);
      expect((items[0] as Map<String, dynamic>)['dateLabel'], '10月13日');

      final thu = items[2] as Map<String, dynamic>;
      expect(thu['date'], '2026-10-15');
      expect(thu['dateLabel'], '10月15日');
      expect(thu['expense'], 50);

      final fri = items[3] as Map<String, dynamic>;
      expect(fri['income'], 100);

      final sun = items[5] as Map<String, dynamic>;
      expect(sun['expense'], 25);
      expect(sun['expenseChange'], 100.0, reason: '前一日支出为 0 时 +100');
    });

    test('成员统计：一期单成员，含分类过滤与空月', () async {
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 70, DateTime(2026, 10, 3), categoryId: shoppingId);

      final data = await service.getByMember(
          type: 1, year: 2026, period: 'month', month: 10);
      final items = data['items'] as List;
      expect(items.length, 1, reason: '一期单成员：本人即唯一成员');
      final m = items[0] as Map<String, dynamic>;
      expect(m['memberId'], 'u1');
      expect(m['memberName'], '测试用户');
      expect(m['amount'], 100);
      expect(m['amountStr'], '¥100');
      expect(m['percentage'], 100.0);
      expect(m['percentageStr'], '100%');
      expect(m['count'], 2);
      expect(m['avgAmount'], 50);

      final filtered = await service.getByMember(
          type: 1, year: 2026, period: 'month', month: 10, categoryId: diningId);
      final fm = (filtered['items'] as List)[0] as Map<String, dynamic>;
      expect(fm['amount'], 30);
      expect(fm['count'], 1);
      expect(fm['avgAmount'], 30);

      final empty = await service.getByMember(
          type: 1, year: 2026, period: 'month', month: 11);
      expect(empty['total'], '0');
      expect(empty['items'] as List, isEmpty);
    });

    test('日历：逐日生成、type=2 与墓碑排除、热力值与汇总', () async {
      await seed(0, 8000, DateTime(2026, 10, 2), categoryId: salaryId);
      await seed(1, 30, DateTime(2026, 10, 2));
      await seed(1, 70, DateTime(2026, 10, 5));
      await seed(2, 9999, DateTime(2026, 10, 6)); // 不计收支排除
      final deleted = await txRepo.insert(TransactionsCompanion.insert(
        type: 1,
        categoryId: diningId,
        amount: 500,
        date: DateTime(2026, 10, 7),
        userId: 'u1',
      ));
      await txRepo.softDelete(deleted.id);

      final data =
          await service.getByDate(year: 2026, period: 'month', month: 10);
      expect(data['year'], 2026);
      expect(data['month'], 10);
      final days = data['days'] as List;
      expect(days.length, 31, reason: '区间内逐日生成，无交易日也占位');

      final d1 = days[0] as Map<String, dynamic>;
      expect(d1['date'], '2026-10-01');
      expect(d1['day'], 1);
      expect(d1['count'], 0);
      expect(d1['intensity'], 1, reason: '无交易热力值为 1');

      final d2 = days[1] as Map<String, dynamic>;
      expect(d2['income'], 8000);
      expect(d2['expense'], 30);
      expect(d2['net'], 7970);
      expect(d2['count'], 2);
      expect(d2['intensity'], 5, reason: 'ceil(8030/8000*5)=6 收敛到 5');

      final d5 = days[4] as Map<String, dynamic>;
      expect(d5['expense'], 70);
      expect(d5['count'], 1);
      expect(d5['intensity'], 1); // ceil(70/8000*5)=1

      final d6 = days[5] as Map<String, dynamic>;
      expect(d6['income'], 0, reason: 'type=2 不计收支排除');
      expect(d6['count'], 0);

      final d7 = days[6] as Map<String, dynamic>;
      expect(d7['expense'], 0, reason: '墓碑排除');

      final summary = data['summary'] as Map<String, dynamic>;
      expect(summary['maxAmount'], 8030);
      expect(summary['maxDate'], '2026-10-02');

      // 类型过滤：仅支出时收入列清零
      final expenseOnly =
          await service.getByDate(type: 1, year: 2026, period: 'month', month: 10);
      final e2 = (expenseOnly['days'] as List)[1] as Map<String, dynamic>;
      expect(e2['income'], 0);
      expect(e2['expense'], 30);
      expect(e2['count'], 1, reason: '类型过滤后仅计支出笔数');

      // 周维度 7 天；year 维度全年 365 天；week 不返回 month 字段
      final week = await service.getByDate(
          year: 2026,
          period: 'week',
          weekStartDate: '2026-10-13',
          weekEndDate: '2026-10-19');
      expect(week['days'] as List, hasLength(7));
      expect(week.containsKey('month'), false, reason: '未传 month 不返回该字段');

      final yearData = await service.getByDate(year: 2026, period: 'year');
      expect(yearData['days'] as List, hasLength(365));
      expect(yearData.containsKey('month'), false);
    });
  });
}
