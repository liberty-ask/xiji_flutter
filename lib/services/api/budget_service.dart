import 'api_client.dart';

class BudgetService {
  // 单例实例
  static BudgetService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  BudgetService._internal();
  
  // 获取单例实例
  factory BudgetService() {
    _instance ??= BudgetService._internal();
    return _instance!;
  }

  // 获取预算信息
  Future<Map<String, dynamic>> getBudget({
    int? year,
    int? month,
  }) async {
    final queryParams = <String, dynamic>{};
    if (year != null) queryParams['year'] = year;
    if (month != null) queryParams['month'] = month;
    return await _api.get('/v1/budgets', queryParameters: queryParams.isNotEmpty ? queryParams : null);
  }

  // 设置预算
  Future<void> setBudget({
    required double total,
    required int year,
    required int month,
  }) async {
    await _api.post('/v1/budgets', data: {
      'total': total,
      'year': year,
      'month': month,
    });
  }
}

