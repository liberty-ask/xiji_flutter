import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'budget_repository.dart';
import 'category_repository.dart';
import 'category_rule_repository.dart';
import 'local_user.dart';
import 'statistics_repository.dart';
import 'transaction_repository.dart';

/// 账号库文件名（纯函数，单测引用）。
String dbFileNameFor(String userId) => 'xiji_$userId.sqlite';

/// 旧单库认领（design.md D12）：目标账号库不存在且旧 xiji.sqlite 存在时，
/// rename 原地过户——唯一真实用户升级场景下，旧库导入的数据零感知跟随账号。
/// 目标库已存在（该账号用过）或无旧库（新账号）时不做任何事。
Future<void> claimLegacyDb({required Directory dir, required String userId}) async {
  if (userId.isEmpty) return;
  final legacy = File('${dir.path}/xiji.sqlite');
  final target = File('${dir.path}/${dbFileNameFor(userId)}');
  if (await target.exists()) return;
  if (await legacy.exists()) {
    await legacy.rename(target.path);
  }
}

/// 本地库单例：AppDatabase 与各 Repository 的应用级唯一实例。
///
/// 账号分库（design.md D12）：库文件按登录用户命名 xiji_{userId}.sqlite，
/// 登录切换账号关旧开新，登出关库不删文件（回登复用）；不同账号的
/// 数据、学习表、将来的同步密钥与游标随分库天然隔离。
///
/// 数据真身生命周期 = 应用生命周期；测试中直接构造 AppDatabase 内存库，
/// 不经由此处。
class Db {
  Db._();

  static AppDatabase? _db;
  static String? _accountUserId;
  static int _generation = 0;
  static TransactionRepository? _transactions;
  static CategoryRepository? _categories;
  static CategoryRuleRepository? _categoryRules;
  static StatisticsRepository? _statistics;
  static BudgetRepository? _budgets;

  /// 当前账号锚点：登录成功时由 [switchAccount] 设置；
  /// 未设置时（冷启动 UI 先行）打开路径回退读本地缓存的用户，
  /// 打开成功后同样锚定（避免冷启动 refreshUser 确认同账号时误关库）。
  static String? get accountUserId => _accountUserId;

  /// 库世代号：close() 真正关库时递增。持有本库实例的门面单例
  /// （TransactionService 等）比对世代发现变化即自动重绑新库，
  /// 防止账号切换后继续持有已关闭的旧库引用。
  static int get generation => _generation;

  static AppDatabase get database {
    if (_db == null) {
      _db = AppDatabase(_openConnection(),
          migrationSeedUserIdProvider: () async =>
              _accountUserId ?? (await LocalUser.load())?.id ?? '');
      _transactions = TransactionRepository(_db!);
      _categories = CategoryRepository(_db!);
      _categoryRules = CategoryRuleRepository(_db!);
      _statistics = StatisticsRepository(_db!);
      _budgets = BudgetRepository(_db!);
    }
    return _db!;
  }

  /// 登录成功后切换到该账号的库：记录锚点并关闭当前库，
  /// 下次访问时按新账号打开对应库文件。同一账号重复登录为 no-op。
  static Future<void> switchAccount(String userId) async {
    if (userId.isEmpty) return;
    if (_accountUserId == userId && _db != null) return;
    _accountUserId = userId;
    await close();
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

  static BudgetRepository get budgets {
    database; // 确保初始化
    return _budgets!;
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final userId = _accountUserId ?? (await LocalUser.load())?.id ?? '';
      if (userId.isEmpty) {
        // 无账号信息（未登录兜底/异常态）：沿用旧单库路径，保持既有行为
        return NativeDatabase.createInBackground(
            File('${dir.path}/xiji.sqlite'));
      }
      // 锚定实际打开的账号：冷启动按 LocalUser 缓存打开后，
      // refreshUser 确认为同一账号时 switchAccount 不再关库
      //（修复：关库与门面旧引用叠加导致 connection was closed 崩溃）
      _accountUserId ??= userId;
      await claimLegacyDb(dir: dir, userId: userId);
      return NativeDatabase.createInBackground(
          File('${dir.path}/${dbFileNameFor(userId)}'));
    });
  }

  /// 关闭并重置单例：登出/会话过期（文件保留，回登复用）、
  /// 账号切换、测试/迁移后全量核对时调用。库未打开时为 no-op
  ///（不递增世代，避免无谓触发门面单例重绑）。
  static Future<void> close() async {
    if (_db == null) return;
    await _db!.close();
    _db = null;
    _generation++;
    _transactions = null;
    _categories = null;
    _categoryRules = null;
    _statistics = null;
    _budgets = null;
  }
}
