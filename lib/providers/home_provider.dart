import 'package:flutter/foundation.dart';
import '../services/api/transaction_service.dart';
import '../services/widget/home_widget_service.dart';

class HomeProvider with ChangeNotifier {
  // 随库世代动态解析：登出关库换世代后旧实例持死引用，禁止构造捕获
  TransactionService get _transactionService => TransactionService();
  
  Map<String, dynamic>? _homeData;
  // 初始即加载中：首页首帧渲染 LoadingIndicator 而非「无数据」
  // 错误页（_bootstrap 先回填家庭再 fetch，存在数百毫秒空窗，
  // 此前空窗期错误占位页闪现后被数据替换，观感为报错一闪而过）
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic>? get homeData => _homeData;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchHomeData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _homeData = await _transactionService.getHomeData();
      _error = null;
      
      // 将收支数据直传原生并刷新财务汇总小部件
      if (_homeData != null) {
        final income = (_homeData!['income'] as num?)?.toDouble() ?? 0.0;
        final expense = (_homeData!['expense'] as num?)?.toDouble() ?? 0.0;
        await HomeWidgetService.updateFinanceWidget(
          income: income,
          expense: expense,
        );
      }
    } catch (e) {
      _error = e.toString();
      _homeData = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

