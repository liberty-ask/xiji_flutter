import 'package:flutter/foundation.dart';

/// 全局异常处理器
/// 用于捕获和处理应用中的各种异常，防止应用崩溃
class GlobalErrorHandler {
  /// 初始化全局异常处理
  static void initialize() {
    // 捕获Flutter框架异常
    FlutterError.onError = (FlutterErrorDetails details) {
      // 在debug模式下，Flutter会显示红色错误页面
      // 在生产模式下，我们需要自己处理
      if (kDebugMode) {
        FlutterError.presentError(details);
      } else {
        // 生产模式下，只记录错误，不显示红色页面
        _handleError(details.exception, details.stack);
      }
    };

    // 捕获异步异常（Zone外的异常）
    PlatformDispatcher.instance.onError = (error, stack) {
      _handleError(error, stack);
      return true; // 返回true表示异常已被处理，防止应用崩溃
    };
  }

  /// 处理错误
  static void _handleError(dynamic error, StackTrace? stack) {
    _logError(error, stack);
  }

  /// 处理未捕获的异步错误（由runZonedGuarded调用）
  static void handleUncaughtError(dynamic error, StackTrace stack) {
    _logError(error, stack);
  }

  /// 记录错误信息
  static void _logError(dynamic error, StackTrace? stack) {
    // 记录错误信息
    if (kDebugMode) {
      // 开发模式下打印详细错误信息
      debugPrint('=== 全局异常捕获 ===');
      debugPrint('错误类型: ${error.runtimeType}');
      debugPrint('错误信息: $error');
      if (stack != null) {
        debugPrint('堆栈跟踪: $stack');
      }
      debugPrint('==================');
    }

    // 在生产模式下，可以考虑将错误信息上报到错误监控平台
    // 例如：Sentry、Firebase Crashlytics等
    if (!kDebugMode) {
      // TODO: 上报错误到监控平台
      // final errorMessage = ErrorHelper.extractErrorMessage(error);
      // _reportError(error, stack, errorMessage);
    }

    // 注意：全局异常处理器通常没有BuildContext，无法直接显示UI
    // 真正的错误提示应该在业务代码的catch块中使用ErrorHelper和CustomSnackBar
    // 全局异常处理的主要目的是防止应用崩溃，记录错误信息
  }
}
