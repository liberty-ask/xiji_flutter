import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../services/api/api_client.dart';
import 'error_helper.dart';

/// 页面级加载错误：统一区分「网络/超时」与「业务错误」，杜绝原始异常文本
abstract final class PageErrorHelper {
  /// 传输层失败（断网、超时、证书、取消）返回 true；
  /// 服务端明确响应（4xx/5xx）与业务异常返回 false。
  static bool isNetworkFailure(Object? error) {
    if (error is ApiException) return error.statusCode == null;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
          return true;
        case DioExceptionType.unknown:
          final inner = (error.error?.toString() ?? '').toLowerCase();
          return inner.contains('socket') ||
              inner.contains('network') ||
              inner.contains('connection');
        case DioExceptionType.badResponse:
          return false;
      }
    }
    final text = (error?.toString() ?? '').toLowerCase();
    return text.contains('connection error') ||
        text.contains('network error') ||
        text.contains('socketexception') ||
        text.contains('timeout') ||
        text.contains('request canceled');
  }

  /// 按场景给出可读文案：
  /// 1. 业务异常（LocalizedException）走既有本地化映射；
  /// 2. 服务端有明确 message 时展示该 message；
  /// 3. 网络类失败用 [networkMessage]，其余用 [fallbackMessage]。
  static String resolveLoadMessage(
    BuildContext context,
    Object? error, {
    required String networkMessage,
    required String fallbackMessage,
  }) {
    if (error is LocalizedException) {
      return ErrorHelper.resolveMessage(context, error);
    }
    if (error is ApiException) {
      final message = error.message.trim();
      if (error.statusCode != null &&
          message.isNotEmpty &&
          !_genericHttpMessages.contains(message)) {
        return message;
      }
      return error.statusCode == null ? networkMessage : fallbackMessage;
    }
    return isNetworkFailure(error) ? networkMessage : fallbackMessage;
  }

  static const Set<String> _genericHttpMessages = {
    'Unauthorized',
    'Forbidden',
    'Not Found',
    'Server Error',
    'Request failed',
  };
}
