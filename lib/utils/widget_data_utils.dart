import 'package:shared_preferences/shared_preferences.dart';

/// 小部件数据工具类
/// 用于在应用和小部件之间共享数据
class WidgetDataUtils {
  /// 收支数据的SharedPreferences键
  static const String _incomeKey = 'widget_income';
  static const String _expenseKey = 'widget_expense';
  
  /// 保存本月收支数据到SharedPreferences
  static Future<void> saveMonthlyFinancialData({
    required double income,
    required double expense,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_incomeKey, income);
    await prefs.setDouble(_expenseKey, expense);
  }
}