import 'api_client.dart';

class StatisticsService {
  // 单例实例
  static StatisticsService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  StatisticsService._internal();
  
  // 获取单例实例
  factory StatisticsService() {
    _instance ??= StatisticsService._internal();
    return _instance!;
  }

  // 获取统计数据（分类统计）
  Future<Map<String, dynamic>> getStatistics({
    required int type, // 0-收入(INCOME), 1-支出(EXPENSE)
    required int year, // 年份
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId, // 可选：成员ID
    int? limit, // 可选：返回Top N分类
  }) async {
    final queryParams = <String, dynamic>{
      'type': type,
      'year': year,
      'period': period,
    };
    if (month != null) {
      queryParams['month'] = month;
    }
    if (weekStartDate != null) {
      queryParams['weekStartDate'] = weekStartDate;
    }
    if (weekEndDate != null) {
      queryParams['weekEndDate'] = weekEndDate;
    }
    if (memberId != null) {
      queryParams['memberId'] = memberId;
    }
    if (limit != null) {
      queryParams['limit'] = limit;
    }
    return await _api.get('/v1/statistics', queryParameters: queryParams);
  }

  // 获取统计概览数据
  Future<Map<String, dynamic>> getOverview({
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId,
  }) async {
    final queryParams = <String, dynamic>{
      'year': year,
      'period': period,
    };
    if (month != null) {
      queryParams['month'] = month;
    }
    if (weekStartDate != null) {
      queryParams['weekStartDate'] = weekStartDate;
    }
    if (weekEndDate != null) {
      queryParams['weekEndDate'] = weekEndDate;
    }
    if (memberId != null) {
      queryParams['memberId'] = memberId;
    }
    return await _api.get('/v1/statistics/overview', queryParameters: queryParams);
  }

  // 获取时间趋势统计
  Future<Map<String, dynamic>> getTrend({
    int? type, // 0-收入，1-支出，null-全部
    required int year,
    required String period, // 'day' | 'week' | 'month' | 'year'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'day'且查询周维度时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'day'且查询周维度时必传，格式：yyyy-MM-dd
    String? memberId,
  }) async {
    final queryParams = <String, dynamic>{
      'year': year,
      'period': period,
    };
    if (type != null) {
      queryParams['type'] = type;
    }
    if (month != null) {
      queryParams['month'] = month;
    }
    if (weekStartDate != null) {
      queryParams['weekStartDate'] = weekStartDate;
    }
    if (weekEndDate != null) {
      queryParams['weekEndDate'] = weekEndDate;
    }
    if (memberId != null) {
      queryParams['memberId'] = memberId;
    }
    return await _api.get('/v1/statistics/trend', queryParameters: queryParams);
  }

  // 获取成员统计
  Future<Map<String, dynamic>> getByMember({
    required int type, // 0-收入，1-支出
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? categoryId,
  }) async {
    final queryParams = <String, dynamic>{
      'type': type,
      'year': year,
      'period': period,
    };
    if (month != null) {
      queryParams['month'] = month;
    }
    if (weekStartDate != null) {
      queryParams['weekStartDate'] = weekStartDate;
    }
    if (weekEndDate != null) {
      queryParams['weekEndDate'] = weekEndDate;
    }
    if (categoryId != null) {
      queryParams['categoryId'] = categoryId;
    }
    return await _api.get('/v1/statistics/by-member', queryParameters: queryParams);
  }

  // 获取日期统计
  Future<Map<String, dynamic>> getByDate({
    int? type, // 0-收入，1-支出，null-全部
    required int year,
    required String period, // 'year', 'month', 'week'
    int? month, // 当period为'month'时必传
    String? weekStartDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? weekEndDate, // 当period为'week'时必传，格式：yyyy-MM-dd
    String? memberId,
  }) async {
    final queryParams = <String, dynamic>{
      'year': year,
      'period': period,
    };
    if (month != null) {
      queryParams['month'] = month;
    }
    if (weekStartDate != null) {
      queryParams['weekStartDate'] = weekStartDate;
    }
    if (weekEndDate != null) {
      queryParams['weekEndDate'] = weekEndDate;
    }
    if (type != null) {
      queryParams['type'] = type;
    }
    if (memberId != null) {
      queryParams['memberId'] = memberId;
    }
    return await _api.get('/v1/statistics/by-date', queryParameters: queryParams);
  }

  // 获取对比数据
  Future<Map<String, dynamic>> getCompare({
    required String type, // 'period' | 'member'
    required String comparisonType, // 'month' | 'year'
    required Map<String, dynamic> period1,
    required Map<String, dynamic> period2,
    List<String>? memberIds,
    int? transactionType,
  }) async {
    final queryParams = <String, dynamic>{
      'type': type,
      'comparisonType': comparisonType,
      'period1': period1,
      'period2': period2,
    };
    if (memberIds != null && memberIds.isNotEmpty) {
      queryParams['memberIds'] = memberIds;
    }
    if (transactionType != null) {
      queryParams['transactionType'] = transactionType;
    }
    return await _api.get('/v1/statistics/compare', queryParameters: queryParams);
  }
}

