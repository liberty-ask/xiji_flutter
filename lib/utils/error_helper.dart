import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

/// 业务异常错误码：服务层只抛标识，由 UI 层映射为本地化文案
abstract final class LocalizedErrorCode {
  static const categoryNotFound = 'categoryNotFound';
  static const categoryNameExists = 'categoryNameExists';
  static const builtinCategoryNotDeletable = 'builtinCategoryNotDeletable';
  static const builtinCategoryNotEditable = 'builtinCategoryNotEditable';
  static const transactionNotFound = 'transactionNotFound';
  static const refundTypeChangeNotAllowed = 'refundTypeChangeNotAllowed';
  static const unsupportedFileType = 'unsupportedFileType';
  static const uploadFailedFormatError = 'uploadFailedFormatError';
}

/// 需要本地化展示的业务异常
class LocalizedException implements Exception {
  final String code;
  const LocalizedException(this.code);

  @override
  String toString() => 'LocalizedException($code)';
}

/// 错误处理工具类
/// 用于统一处理异常并提取错误消息
class ErrorHelper {
  /// 优先把可本地化的业务异常映射为当前语言词条；
  /// 其他异常沿用既有 extractErrorMessage 行为
  static String resolveMessage(
    BuildContext context,
    dynamic error, {
    String? defaultMessage,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (error is LocalizedException) {
      switch (error.code) {
        case LocalizedErrorCode.categoryNotFound:
          return l10n.categoryNotFound;
        case LocalizedErrorCode.categoryNameExists:
          return l10n.categoryNameExists;
        case LocalizedErrorCode.builtinCategoryNotDeletable:
          return l10n.builtinCategoryNotDeletable;
        case LocalizedErrorCode.builtinCategoryNotEditable:
          return l10n.builtinCategoryNotEditable;
        case LocalizedErrorCode.transactionNotFound:
          return l10n.transactionNotFound;
        case LocalizedErrorCode.refundTypeChangeNotAllowed:
          return l10n.refundTypeChangeNotAllowed;
        case LocalizedErrorCode.unsupportedFileType:
          return l10n.unsupportedFileType;
        case LocalizedErrorCode.uploadFailedFormatError:
          return l10n.uploadFailedFormatError;
      }
    }
    return extractErrorMessage(
      error,
      defaultMessage: defaultMessage ?? l10n.error,
    );
  }

  /// 从异常中提取错误消息
  /// 
  /// [error] 异常对象
  /// [defaultMessage] 默认错误消息
  /// 
  /// 返回友好的错误消息字符串
  static String extractErrorMessage(dynamic error, {String defaultMessage = 'Operation failed'}) {
    if (error == null) {
      return defaultMessage;
    }

    // 处理DioException
    if (error is DioException) {
      return _extractDioErrorMessage(error, defaultMessage: defaultMessage);
    }
    
    final errorStr = error.toString();
    
    // 如果包含 Exception:，提取后面的消息
    if (errorStr.contains('Exception:')) {
      final message = errorStr.split('Exception:').last.trim();
      return message.isNotEmpty ? message : defaultMessage;
    }
    
    // 如果错误字符串不为空，直接返回
    if (errorStr.isNotEmpty) {
      return errorStr;
    }
    
    return defaultMessage;
  }
  
  /// 从 DioException 中提取错误消息
  /// 
  /// [error] DioException 异常对象
  /// [defaultMessage] 默认错误消息
  /// 
  /// 返回友好的错误消息字符串
  static String _extractDioErrorMessage(DioException error, {String defaultMessage = 'Network request failed'}) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return error.message ?? defaultMessage;
      case DioExceptionType.connectionError:
        return error.message ?? defaultMessage;
      case DioExceptionType.badResponse:
        if (error.response != null) {
          final data = error.response?.data;
          if (data is Map<String, dynamic>) {
            final message = data['message'];
            if (message != null && message is String && message.isNotEmpty) {
              return message;
            }
          }
          final statusCode = error.response?.statusCode;
          if (statusCode == 401) {
            return 'Unauthorized';
          } else if (statusCode == 403) {
            return 'Forbidden';
          } else if (statusCode == 404) {
            return 'Not Found';
          } else if (statusCode != null && statusCode >= 500) {
            return 'Server Error';
          }
        }
        return 'Request failed';
      case DioExceptionType.cancel:
        return 'Request canceled';
      case DioExceptionType.badCertificate:
        return 'Certificate error';
      case DioExceptionType.unknown:
        // 检查是否是Socket异常
        if (error.error != null) {
          final errorStr = error.error.toString().toLowerCase();
          if (errorStr.contains('socket') || errorStr.contains('network')) {
            return 'Network error';
          }
        }
        return error.message ?? defaultMessage;
    }
  }
}


