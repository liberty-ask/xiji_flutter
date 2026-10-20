import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// 手机小部件服务
/// 用于管理语音记账 Widget
/// 注意：当前使用纯原生实现，不依赖 home_widget 插件
class HomeWidgetService {
  static const MethodChannel _channel = MethodChannel('com.xiji/widget');
  static GoRouter? _router;

  /// 设置路由（用于从 Widget 导航）
  static void setRouter(GoRouter router) {
    _router = router;
  }

  /// 初始化 Widget
  /// 注意：Widget 功能完全由原生 Android 代码实现
  static Future<void> initialize() async {
    try {
      // 监听原生端的路由导航
      _channel.setMethodCallHandler((call) async {
        if (call.method == "navigateToRoute") {
          final route = call.arguments as String?;
          if (route != null && _router != null) {
            _router!.go(route);
          }
        }
      });

      if (kDebugMode) {
        debugPrint('Home Widget 服务初始化成功（使用原生实现）');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Home Widget 服务初始化失败: $e');
      }
    }
  }

  /// 更新财务汇总小部件：收支数据经 MethodChannel 直传原生存储并刷新
  static Future<void> updateFinanceWidget({
    required double income,
    required double expense,
  }) async {
    try {
      await _channel.invokeMethod('updateFinanceWidget', {
        'income': income,
        'expense': expense,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('刷新财务汇总小部件失败: $e');
      }
    }
  }
}

