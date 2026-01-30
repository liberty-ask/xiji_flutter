import 'api_client.dart';

class CalendarService {
  // 单例实例
  static CalendarService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  CalendarService._internal();
  
  // 获取单例实例
  factory CalendarService() {
    _instance ??= CalendarService._internal();
    return _instance!;
  }

  // 获取日历概览数据
  Future<Map<String, dynamic>> getCalendarOverview({
    required int year,
    required int month,
    int? day,
  }) async {
    final queryParams = <String, dynamic>{
      'year': year,
      'month': month,
    };
    if (day != null) {
      queryParams['day'] = day;
    }
    return await _api.get('/v1/calendar/overview', queryParameters: queryParams);
  }
}

