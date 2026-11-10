import 'package:flutter/foundation.dart';
import '../services/api/category_service.dart';
import '../models/category.dart' as models;

class CategoryProvider with ChangeNotifier {
  // 随库世代动态解析：登出关库换世代后旧实例持死引用，禁止构造捕获
  CategoryService get _categoryService => CategoryService();
  
  List<models.Category> _categories = [];
  Map<String, int> _usageCounts = {};
  bool _isLoading = false;
  String? _error;

  List<models.Category> get categories => _categories;

  /// 近 90 天使用频次，key 为 `分类ID|方向`（选择器软提示排序用）
  Map<String, int> get usageCounts => _usageCounts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadCategories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _categories = await _categoryService.getCategories();
      _usageCounts = await _categoryService.getRecentUsageCounts();
      _error = null;
    } catch (e) {
      _error = e.toString();
      _categories = [];
      _usageCounts = {};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
