import 'package:shared_preferences/shared_preferences.dart';

/// 小部件数据工具类
/// 用于在应用和小部件之间共享数据
class WidgetDataUtils {
  /// 收支数据的SharedPreferences键
  static const String _incomeKey = 'widget_income';
  static const String _expenseKey = 'widget_expense';
  static const String _updateTimeKey = 'widget_update_time';
  
  /// 保存本月收支数据到SharedPreferences
  static Future<void> saveMonthlyFinancialData({
    required double income,
    required double expense,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_incomeKey, income);
    await prefs.setDouble(_expenseKey, expense);
    await prefs.setInt(_updateTimeKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// 从SharedPreferences获取本月收入
  static Future<double> getIncome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_incomeKey) ?? 0.0;
  }
  
  /// 从SharedPreferences获取本月支出
  static Future<double> getExpense() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_expenseKey) ?? 0.0;
  }
  
  /// 从SharedPreferences获取数据更新时间
  static Future<int> getUpdateTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_updateTimeKey) ?? 0;
  }
  
  /// 清除所有小部件数据
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_incomeKey);
    await prefs.remove(_expenseKey);
    await prefs.remove(_updateTimeKey);
  }
}