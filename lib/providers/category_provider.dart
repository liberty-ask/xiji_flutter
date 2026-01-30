import 'package:flutter/foundation.dart';
import '../services/api/category_service.dart';
import '../models/category.dart' as models;

class CategoryProvider with ChangeNotifier {
  final CategoryService _categoryService = CategoryService();
  
  List<models.Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  List<models.Category> get categories => _categories;
  List<models.Category> get expenseCategories => _categories
      .where((c) => c.type == 1)
      .toList();
  List<models.Category> get incomeCategories => _categories
      .where((c) => c.type == 0)
      .toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadCategories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _categories = await _categoryService.getCategories();
      _error = null;
    } catch (e) {
      _error = e.toString();
      _categories = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
