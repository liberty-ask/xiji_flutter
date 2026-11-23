import 'package:flutter/foundation.dart';
import '../data/local/current_family_store.dart';
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
  // 请求序号：家庭切换/同步刷新并发时只允许最新一次请求落地，
  // 防止晚到的旧家庭结果覆盖新家庭数据
  int _requestSeq = 0;
  // 当前 homeData 归属的家庭 ID：与页面当前家庭不一致时按加载态处理，
  // 避免切换家庭后旧家庭数据残留显示
  String? _dataFamilyId;

  Map<String, dynamic>? get homeData => _homeData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get dataFamilyId => _dataFamilyId;

  Future<void> fetchHomeData() async {
    final requestSeq = ++_requestSeq;
    // 闪屏修复（stale-while-revalidate）：有旧数据时静默刷新、原地
    // 替换，不先撕页换 loading——同步轮完成/切页触发的重拉不再闪屏；
    // 仅首次无数据才显示 loading。失败时保留旧数据兜底（与家庭信息
    // 缓存兜底同一哲学），仅无数据时走错误页
    final hasStale = _homeData != null;
    if (!hasStale) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // 先记家庭 ID 再取数据：中途切家庭时宁可让数据滞后（页面按
      // 加载态处理），也不能把 B 家庭的数据错标成 C
      final familyId = await CurrentFamilyStore.get();
      final data = await _transactionService.getHomeData();
      if (requestSeq != _requestSeq) return; // 晚到的旧请求，丢弃
      _homeData = data;
      _dataFamilyId = familyId;
      _error = null;

      // 将收支数据直传原生并刷新财务汇总小部件
      final income = (data['income'] as num?)?.toDouble() ?? 0.0;
      final expense = (data['expense'] as num?)?.toDouble() ?? 0.0;
      await HomeWidgetService.updateFinanceWidget(
        income: income,
        expense: expense,
      );
    } catch (e) {
      if (requestSeq != _requestSeq) return;
      _error = e.toString();
      if (!hasStale) _homeData = null;
    } finally {
      if (requestSeq == _requestSeq) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}

