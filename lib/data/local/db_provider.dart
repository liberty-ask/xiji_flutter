import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'category_repository.dart';
import 'category_rule_repository.dart';
import 'statistics_repository.dart';
import 'transaction_repository.dart';

/// 本地库单例：AppDatabase 与各 Repository 的应用级唯一实例。
///
/// 数据真身生命周期 = 应用生命周期；测试中直接构造 AppDatabase 内存库，
/// 不经由此处。
class Db {
  Db._();

  static AppDatabase? _db;
  static TransactionRepository? _transactions;
  static CategoryRepository? _categories;
  static CategoryRuleRepository? _categoryRules;
  static StatisticsRepository? _statistics;

  static AppDatabase get database {
    if (_db == null) {
      _db = AppDatabase(_openConnection());
      _transactions = TransactionRepository(_db!);
      _categories = CategoryRepository(_db!);
      _categoryRules = CategoryRuleRepository(_db!);
      _statistics = StatisticsRepository(_db!);
    }
    return _db!;
  }

  static TransactionRepository get transactions {
    database; // 确保初始化
    return _transactions!;
  }

  static CategoryRepository get categories {
    database; // 确保初始化
    return _categories!;
  }

  static CategoryRuleRepository get categoryRules {
    database; // 确保初始化
    return _categoryRules!;
  }

  static StatisticsRepository get statistics {
    database; // 确保初始化
    return _statistics!;
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/xiji.sqlite');
      return NativeDatabase.createInBackground(file);
    });
  }

  /// 仅测试/迁移后全量核对用：立即关闭并重置单例
  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _transactions = null;
    _categories = null;
    _categoryRules = null;
    _statistics = null;
  }
}
