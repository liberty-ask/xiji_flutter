import 'package:flutter/foundation.dart';
import '../services/api/transaction_service.dart';

class TransactionProvider with ChangeNotifier {
  final TransactionService _transactionService = TransactionService();
  
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<Map<String, dynamic>> addTransaction({
    required int type,
    required String category,
    required double amount,
    required String date,
    String? note,
    String? location,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionService.addTransaction(
        type: type,
        category: category,
        amount: amount,
        date: date,
        note: note,
        location: location,
      );
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

