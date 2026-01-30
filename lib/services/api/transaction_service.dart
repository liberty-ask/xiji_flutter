import 'api_client.dart';
import '../../models/transaction.dart';

class TransactionService {
  // 单例实例
  static TransactionService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  TransactionService._internal();
  
  // 获取单例实例
  factory TransactionService() {
    _instance ??= TransactionService._internal();
    return _instance!;
  }

  // 添加交易
  Future<Map<String, dynamic>> addTransaction({
    required int type,
    required String category,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final data = {
      'type': type,
      'category': category,
      'amount': amount,
      'date': date,
      if (note != null) 'note': note,
      if (location != null) 'location': location,
    };

    final result = await _api.post<Map<String, dynamic>>('/v1/mobile/transactions', data: data);
    return result;
  }

  // 获取交易列表
  Future<List<Transaction>> getTransactions({
    int? type,
    String? startDate,
    String? endDate,
    String? date, // 单个日期参数（用于查询某一天的数据）
    String? userId, // 用户ID筛选
    String? keyword, // 搜索关键词
    int? page,
    int? pageSize,
  }) async {
    final queryParams = <String, dynamic>{};
    if (type != null) queryParams['type'] = type;
    // 如果提供了单个日期，优先使用（更简洁）
    if (date != null) {
      queryParams['date'] = date;
    } else {
      // 否则使用日期范围
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
    }
    if (userId != null && userId.isNotEmpty) queryParams['userId'] = userId;
    if (keyword != null && keyword.isNotEmpty) queryParams['keyword'] = keyword;
    if (page != null) queryParams['page'] = page;
    if (pageSize != null) queryParams['pageSize'] = pageSize;

    final result = await _api.get('/v1/mobile/transactions', queryParameters: queryParams);
    
    // API 可能返回两种格式：
    // 1. 直接返回数组: [{...}, {...}]
    // 2. 返回对象: {list: [{...}, {...}], total: 100, page: 1, pageSize: 20}
    if (result is Map<String, dynamic> && result.containsKey('list')) {
      // 如果是对象格式，提取 list 字段
      final List<dynamic> list = result['list'] as List<dynamic>;
      return list.map((json) => Transaction.fromJson(json as Map<String, dynamic>)).toList();
    } else if (result is List) {
      // 如果是数组格式，直接转换
      return result.map((json) => Transaction.fromJson(json as Map<String, dynamic>)).toList();
    } else {
      // 默认返回空列表
      return [];
    }
  }

  // 更新交易
  Future<Map<String, dynamic>> updateTransaction({
    required String id,
    required int type,
    required String category,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    final data = {
      'type': type,
      'category': category,
      'amount': amount,
      'date': date,
      if (note != null) 'note': note,
      if (location != null) 'location': location,
    };

    final result = await _api.put<Map<String, dynamic>>('/v1/mobile/transactions/$id', data: data);
    return result;
  }

  // 删除交易
  Future<void> deleteTransaction(String id) async {
    await _api.delete('/v1/mobile/transactions/$id');
  }

  // 获取首页数据
  Future<Map<String, dynamic>> getHomeData() async {
    return await _api.get('/v1/home');
  }
}

