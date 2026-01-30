import 'package:flutter/foundation.dart';
import '../services/api/transaction_service.dart';
import '../utils/widget_data_utils.dart';

class HomeProvider with ChangeNotifier {
  final TransactionService _transactionService = TransactionService();
  
  Map<String, dynamic>? _homeData;
  bool _isLoading = false;
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
      
      // 将收支数据保存到SharedPreferences，供小部件使用
      if (_homeData != null) {
        final income = _homeData!['totalIncome'] as double? ?? 0.0;
        final expense = _homeData!['totalExpense'] as double? ?? 0.0;
        await WidgetDataUtils.saveMonthlyFinancialData(
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

