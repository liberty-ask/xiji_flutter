import 'api_client.dart';
import '../../models/category.dart';

class CategoryService {
  // 单例实例
  static CategoryService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  CategoryService._internal();
  
  // 获取单例实例
  factory CategoryService() {
    _instance ??= CategoryService._internal();
    return _instance!;
  }

  // 获取分类列表
  Future<List<Category>> getCategories() async {
    final result = await _api.get('/v1/mobile/categories');
    final List<dynamic> list = result as List<dynamic>;
    return list.map((json) => Category.fromJson(json as Map<String, dynamic>)).toList();
  }

  // 获取支出分类
  Future<List<Category>> getExpenseCategories() async {
    final categories = await getCategories();
    return categories.where((c) => c.type == 1).toList();
  }

  // 获取收入分类
  Future<List<Category>> getIncomeCategories() async {
    final categories = await getCategories();
    return categories.where((c) => c.type == 0).toList();
  }

  // 添加新分类
  Future<Map<String, dynamic>> addCategory({
    required String name,
    required String icon,
    required int type,
  }) async {
    final data = {
      'name': name,
      'icon': icon,
      'type': type,
    };
    final result = await _api.post<Map<String, dynamic>>('/v1/mobile/categories', data: data);
    return result;
  }

  // 删除分类
  Future<void> deleteCategory(String id) async {
    await _api.delete('/v1/mobile/categories/$id');
  }

  // 更新分类
  Future<Map<String, dynamic>> updateCategory({
    required String id,
    required String name,
    required String icon,
    required int type,
  }) async {
    final data = {
      'name': name,
      'icon': icon,
      'type': type,
    };
    final result = await _api.put<Map<String, dynamic>>('/v1/mobile/categories/$id', data: data);
    return result;
  }
}
