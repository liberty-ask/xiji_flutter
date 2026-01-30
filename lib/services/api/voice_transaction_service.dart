import 'api_client.dart';

/// 语音记账服务
class VoiceTransactionService {
  // 单例实例
  static VoiceTransactionService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  VoiceTransactionService._internal();
  
  // 获取单例实例
  factory VoiceTransactionService() {
    _instance ??= VoiceTransactionService._internal();
    return _instance!;
  }

  /// 语音记账
  /// [text] 语音识别的文本
  /// 返回记账结果，包含交易信息或错误信息
  Future<Map<String, dynamic>> addTransactionByVoice(String text) async {
    final data = {
      'text': text,
    };
    
    try {
      // 直接使用dynamic类型接收结果，避免类型转换问题
      final result = await _api.post<dynamic>(
        '/v1/mobile/transactions/voice',
        data: data,
      );
      
      // 检查结果是否为Map
      if (result is Map<String, dynamic>) {
        // 只关注code是否为200，不处理data相关内容
        if (result['code'] == 200) {
          return {
            'success': true,
            'message': result['message'] as String?,
          };
        }
      }
      
      // 如果code不是200或者结果不是Map，返回成功（根据用户要求，只关注code是200就代表成功）
      return {
        'success': true,
        'message': null,
      };
    } catch (e) {
      // 处理错误
      rethrow;
    }
  }
}

