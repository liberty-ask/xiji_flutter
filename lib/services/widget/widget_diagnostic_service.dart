import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Widget 诊断服务
/// 用于检查 Widget 是否正确注册和可用
class WidgetDiagnosticService {
  static const MethodChannel _channel = MethodChannel('com.xiji/widget');

  /// 检查 Widget 是否已注册
  static Future<bool> checkWidgetRegistered() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkWidgetRegistered');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('检查 Widget 注册状态失败: $e');
      }
      return false;
    }
  }

  /// 获取 Widget 信息
  static Future<Map<String, dynamic>?> getWidgetInfo() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getWidgetInfo');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('获取 Widget 信息失败: $e');
      }
      return null;
    }
  }

  /// 打开 Widget 设置页面
  static Future<void> openWidgetSettings() async {
    try {
      await _channel.invokeMethod('openWidgetSettings');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('打开 Widget 设置失败: $e');
      }
    }
  }
}

