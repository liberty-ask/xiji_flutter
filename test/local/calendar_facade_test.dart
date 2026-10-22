import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiji_flutter/utils/money.dart';
import 'package:xiji_flutter/data/local/app_database.dart';
import 'package:xiji_flutter/data/local/builtin_categories.dart';
import 'package:xiji_flutter/data/local/category_repository.dart';
import 'package:xiji_flutter/data/local/statistics_repository.dart';
import 'package:xiji_flutter/data/local/transaction_repository.dart';
import 'package:xiji_flutter/services/api/calendar_service.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactions;
  late CalendarService service;

  setUp(() {
    // 门面内部经 CurrentFamilyStore 解析当前家庭（mock prefs 下为 ''）
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    transactions = TransactionRepository(db);
    service = CalendarService.withRepos(
      transactions,
      CategoryRepository(db),
      StatisticsRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  final diningId = BuiltinCategories.byName('餐饮', 1)!.id;
  final salaryId = BuiltinCategories.byName('工资', 0)!.id;

  Future<void> addTx({
    required DateTime date,
    required int type,
    required String categoryId,
    required double amount,
    String? description,
    String? counterparty,
  }) {
    return transactions.insert(TransactionsCompanion.insert(
      type: type,
      categoryId: categoryId,
      amountCents: Money.yuanToCents(amount),
      date: date,
      userId: 'user-1',
      description: Value(description),
      counterparty: Value(counterparty),
    ));
  }

  group('日历门面（对齐服务端 MobileCalendarController 响应结构）', () {
    test('整月概览：收支、结余、每日汇总覆盖当月每天', () async {
      await addTx(
          date: DateTime(2026, 9, 5, 8, 30),
          type: 1,
          categoryId: diningId,
          amount: 25.5);
      await addTx(
          date: DateTime(2026, 9, 5, 19, 0),
          type: 1,
          categoryId: diningId,
          amount: 60);
      await addTx(
          date: DateTime(2026, 9, 20, 10, 0),
          type: 0,
          categoryId: salaryId,
          amount: 8000);

      final data = await service.getCalendarOverview(year: 2026, month: 9);

      expect(data['monthlyIncome'], 8000.0);
      expect(data['monthlyExpense'], 85.5);
      expect(data['surplus'], 8000.0 - 85.5);

      final dailySummary = data['dailySummary'] as Map<String, dynamic>;
      expect(dailySummary.length, 30, reason: '9 月每天均有键（含零值）');
      expect((dailySummary['5'] as Map<String, dynamic>)['income'], 0);
      expect((dailySummary['5'] as Map<String, dynamic>)['expense'], 85.5);
      expect((dailySummary['20'] as Map<String, dynamic>)['income'], 8000.0);
      expect((dailySummary['1'] as Map<String, dynamic>)['expense'], 0,
          reason: '无交易日为零值');
    });

    test('每日明细：字段结构、name 回退链、amount 正负号格式', () async {
      await addTx(
          date: DateTime(2026, 9, 5, 8, 30),
          type: 1,
          categoryId: diningId,
          amount: 25.5,
          description: '早餐豆浆油条',
          counterparty: '某早餐店');
      // 无描述、有分类：name 回退分类名
      await addTx(
          date: DateTime(2026, 9, 5, 12, 0),
          type: 0,
          categoryId: salaryId,
          amount: 8000);

      final data = await service.getCalendarOverview(year: 2026, month: 9);
      final dailyDetails = data['dailyDetails'] as Map<String, dynamic>;
      expect(dailyDetails.length, 30, reason: '每天均有键');

      final day5 = dailyDetails['5'] as List<dynamic>;
      expect(day5, hasLength(2));

      final first = day5[0] as Map<String, dynamic>;
      expect(first['name'], '工资', reason: '无描述时回退分类名');
      expect(first['cat'], '工资');
      expect(first['icon'], 'payments');
      expect(first['type'], 0);
      expect(first['amount'], '+ 8000.00');
      expect(first['time'], '12:00');

      final second = day5[1] as Map<String, dynamic>;
      expect(second['name'], '早餐豆浆油条', reason: '优先描述');
      expect(second['description'], '早餐豆浆油条');
      expect(second['counterparty'], '某早餐店');
      expect(second['amount'], '- 25.50');
      expect(second['time'], '08:30');
    });

    test('type=2（不计收支）与墓碑排除在日历外', () async {
      final t2 = await transactions.insert(TransactionsCompanion.insert(
        type: 2,
        categoryId: diningId,
        amountCents: 10000,
        date: DateTime(2026, 9, 8, 10, 0),
        userId: 'user-1',
      ));
      await transactions.softDelete(t2.id);
      await addTx(
          date: DateTime(2026, 9, 8, 11, 0),
          type: 2,
          categoryId: diningId,
          amount: 50);

      final data = await service.getCalendarOverview(year: 2026, month: 9);

      expect(data['monthlyIncome'], 0);
      expect(data['monthlyExpense'], 0);
      final day8 = (data['dailyDetails'] as Map<String, dynamic>)['8'];
      expect(day8, isEmpty, reason: 'type=2 与墓碑不进日历明细');
    });

    test('跨月交易不出现在结果中', () async {
      await addTx(
          date: DateTime(2026, 8, 31, 23, 0),
          type: 1,
          categoryId: diningId,
          amount: 10);
      await addTx(
          date: DateTime(2026, 10, 1, 0, 30),
          type: 1,
          categoryId: diningId,
          amount: 20);

      final data = await service.getCalendarOverview(year: 2026, month: 9);

      expect(data['monthlyExpense'], 0);
      final details = data['dailyDetails'] as Map<String, dynamic>;
      for (final dayList in details.values) {
        expect(dayList as List<dynamic>, isEmpty);
      }
    });
  });
}
