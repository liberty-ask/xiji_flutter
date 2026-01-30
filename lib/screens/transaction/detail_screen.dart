import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/api/transaction_service.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../providers/category_provider.dart';
import '../../models/category.dart' as models;
import '../../models/family_member.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/constants.dart';
import '../../models/transaction.dart';
import '../../l10n/app_localizations.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final TransactionService _transactionService = TransactionService();
  final FamilyService _familyService = FamilyService();
  List<Transaction> _transactions = [];
  List<FamilyMember> _members = [];
  bool _isLoading = true;
  bool _isLoadingMore = false; // 是否正在加载更多
  bool _hasMore = true; // 是否还有更多数据
  int _currentPage = 1; // 当前页码
  String? _error;
  
  // 筛选条件
  DateTime? _startDate; // 开始日期（null表示无限制）
  DateTime? _endDate; // 结束日期（null表示无限制）
  TransactionType? _selectedType; // 选择的交易类型（null表示全部）
  String? _selectedUserId; // 选择的用户ID（null表示全部）
  String? _searchKeyword; // 搜索关键词
  
  // 控制器
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始状态下日期筛选为空（无限制）
    _startDate = null;
    _endDate = null;
    _loadMembers();
    _loadTransactions();
    
    // 监听滚动，实现分页加载
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    // 当滚动到底部附近时，加载更多数据
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreTransactions();
    }
  }
  
  Future<void> _loadMembers() async {
    try {
      final members = await _familyService.getMembers();
      if (mounted) {
        setState(() {
          _members = members;
        });
      }
    } catch (e) {
      // 加载成员失败不影响主功能
      if (kDebugMode) {
        debugPrint('加载成员列表失败: $e');
      }
    }
  }

  Future<void> _loadTransactions({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
        _hasMore = true;
        _transactions = [];
      });
    }

    try {
      // 构建查询参数
      int? type;
      if (_selectedType != null) {
        type = _selectedType!.toInt();
      }
      
      // 处理日期范围，null表示无限制
      final startDate = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
      final endDate = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;
      
      // 获取交易列表
      List<Transaction> transactions = await _transactionService.getTransactions(
        type: type,
        startDate: startDate,
        endDate: endDate,
        userId: _selectedUserId,
        keyword: _searchKeyword?.trim(),
        page: _currentPage,
        pageSize: AppConstants.defaultPageSize,
      );
      
      // 如果API不支持userId参数，在前端过滤
      if (_selectedUserId != null && _selectedUserId!.isNotEmpty) {
        transactions = transactions.where((t) => t.userId == _selectedUserId).toList();
      }
      
      setState(() {
        if (reset) {
          _transactions = transactions;
        } else {
          _transactions.addAll(transactions);
        }
        _error = null;
        // 判断是否还有更多数据
        _hasMore = transactions.length >= AppConstants.defaultPageSize;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        if (reset) {
          _transactions = [];
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadMoreTransactions() async {
    // 如果正在加载或没有更多数据，不执行
    if (_isLoadingMore || !_hasMore || _isLoading) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    try {
      // 构建查询参数
      int? type;
      if (_selectedType != null) {
        type = _selectedType!.toInt();
      }
      
      // 处理日期范围，null表示无限制
      final startDate = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
      final endDate = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;
      
      // 获取交易列表
      List<Transaction> transactions = await _transactionService.getTransactions(
        type: type,
        startDate: startDate,
        endDate: endDate,
        userId: _selectedUserId,
        keyword: _searchKeyword?.trim(),
        page: _currentPage,
        pageSize: AppConstants.defaultPageSize,
      );
      
      // 如果API不支持userId参数，在前端过滤
      if (_selectedUserId != null && _selectedUserId!.isNotEmpty) {
        transactions = transactions.where((t) => t.userId == _selectedUserId).toList();
      }
      
      setState(() {
        _transactions.addAll(transactions);
        // 判断是否还有更多数据
        _hasMore = transactions.length >= AppConstants.defaultPageSize;
      });
    } catch (e) {
      // 加载失败，回退页码
      setState(() {
        _currentPage--;
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  String _getDateDisplayText() {
    if (_startDate == null || _endDate == null) {
      return AppLocalizations.of(context)!.allTime;
    }
    final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);
    if (startStr == endStr) {
      return DateFormat.yMMMMd().format(_startDate!);
    }
    return '$startStr ${AppLocalizations.of(context)!.to} $endStr';
  }

  Future<void> _showDateRangePicker() async {
    final now = DateTime.now();
    DateTime tempStartDate = _startDate ?? now;
    DateTime tempEndDate = _endDate ?? now;
    
    // 确保结束日期不超过今天
    if (tempEndDate.isAfter(now)) {
      tempEndDate = now;
    }
    
    // 开始日期的年、月、日
    int startYear = tempStartDate.year;
    int startMonth = tempStartDate.month;
    int startDay = tempStartDate.day;
    
    // 结束日期的年、月、日
    int endYear = tempEndDate.year;
    int endMonth = tempEndDate.month;
    int endDay = tempEndDate.day;
    
    // 年范围
    const int minYear = 1900;
    int maxYear = now.year;
    
    // 生成年份列表
    List<int> years = List.generate(maxYear - minYear + 1, (index) => minYear + index);
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeHelper.surface(context),
          title: ScaledText(
            AppLocalizations.of(context)!.selectDateRange,
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 开始日期标题
              Align(
                alignment: Alignment.centerLeft,
                child: ScaledText(
                  AppLocalizations.of(context)!.startDate,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              // 开始日期选择器
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: ThemeHelper.surfaceLight(context),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 年选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  startYear = years[index];
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(startYear, startMonth + 1, 0).day;
                                  
                                  // 调整天数为有效值
                                  if (startDay > maxDays) {
                                    startDay = maxDays;
                                  }
                                  
                                  // 更新开始日期
                                  tempStartDate = DateTime(startYear, startMonth, startDay);
                                  
                                  // 确保开始日期不超过结束日期
                                  if (tempStartDate.isAfter(tempEndDate)) {
                                    tempEndDate = tempStartDate;
                                    endYear = startYear;
                                    endMonth = startMonth;
                                    endDay = startDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: startYear - minYear),
                              children: years.map((year) => Center(
                                child: ScaledText(
                                  '$year${AppLocalizations.of(context)!.yearLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )).toList(),
                            ),
                          ),
                          // 月选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  startMonth = index + 1;
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(startYear, startMonth + 1, 0).day;
                                  
                                  // 调整天数为有效值
                                  if (startDay > maxDays) {
                                    startDay = maxDays;
                                  }
                                  
                                  // 更新开始日期
                                  tempStartDate = DateTime(startYear, startMonth, startDay);
                                  
                                  // 确保开始日期不超过结束日期
                                  if (tempStartDate.isAfter(tempEndDate)) {
                                    tempEndDate = tempStartDate;
                                    endYear = startYear;
                                    endMonth = startMonth;
                                    endDay = startDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: startMonth - 1),
                              children: List.generate(12, (index) => Center(
                                child: ScaledText(
                                  '${index + 1}${AppLocalizations.of(context)!.monthLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )),
                            ),
                          ),
                          // 日选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  startDay = index + 1;
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(startYear, startMonth + 1, 0).day;
                                  
                                  // 确保选择的天数不超过最大值
                                  if (startDay > maxDays) {
                                    startDay = maxDays;
                                  }
                                  
                                  // 更新开始日期
                                  tempStartDate = DateTime(startYear, startMonth, startDay);
                                  
                                  // 确保开始日期不超过结束日期
                                  if (tempStartDate.isAfter(tempEndDate)) {
                                    tempEndDate = tempStartDate;
                                    endYear = startYear;
                                    endMonth = startMonth;
                                    endDay = startDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: startDay - 1),
                              children: List.generate(31, (index) => Center(
                                child: ScaledText(
                                  '${index + 1}${AppLocalizations.of(context)!.dayLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
              const SizedBox(height: 20),
              // 结束日期标题
              Align(
                alignment: Alignment.centerLeft,
                child: ScaledText(
                  AppLocalizations.of(context)!.endDate,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              // 结束日期选择器
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: ThemeHelper.surfaceLight(context),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 年选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  endYear = years[index];
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(endYear, endMonth + 1, 0).day;
                                  
                                  // 如果是当前年份，月份和日期不能超过今天
                                  if (endYear == now.year) {
                                    if (endMonth > now.month) {
                                      endMonth = now.month;
                                      maxDays = DateTime(endYear, endMonth + 1, 0).day;
                                    }
                                    if (endMonth == now.month) {
                                      maxDays = now.day;
                                    }
                                  }
                                  
                                  // 调整天数为有效值
                                  if (endDay > maxDays) {
                                    endDay = maxDays;
                                  }
                                  
                                  // 更新结束日期
                                  tempEndDate = DateTime(endYear, endMonth, endDay);
                                  
                                  // 确保结束日期不早于开始日期
                                  if (tempEndDate.isBefore(tempStartDate)) {
                                    tempStartDate = tempEndDate;
                                    startYear = endYear;
                                    startMonth = endMonth;
                                    startDay = endDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: endYear - minYear),
                              children: years.map((year) => Center(
                                child: ScaledText(
                                  '$year${AppLocalizations.of(context)!.yearLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )).toList(),
                            ),
                          ),
                          // 月选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  endMonth = index + 1;
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(endYear, endMonth + 1, 0).day;
                                  
                                  // 如果是当前年月，日期不能超过今天
                                  if (endYear == now.year && endMonth == now.month) {
                                    maxDays = now.day;
                                  }
                                  
                                  // 调整天数为有效值
                                  if (endDay > maxDays) {
                                    endDay = maxDays;
                                  }
                                  
                                  // 更新结束日期
                                  tempEndDate = DateTime(endYear, endMonth, endDay);
                                  
                                  // 确保结束日期不早于开始日期
                                  if (tempEndDate.isBefore(tempStartDate)) {
                                    tempStartDate = tempEndDate;
                                    startYear = endYear;
                                    startMonth = endMonth;
                                    startDay = endDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: endMonth - 1),
                              children: List.generate(12, (index) => Center(
                                child: ScaledText(
                                  '${index + 1}${AppLocalizations.of(context)!.monthLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )),
                            ),
                          ),
                          // 日选择器
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  endDay = index + 1;
                                  
                                  // 计算该年月的最大天数
                                  int maxDays = DateTime(endYear, endMonth + 1, 0).day;
                                  
                                  // 如果是当前年月，日期不能超过今天
                                  if (endYear == now.year && endMonth == now.month) {
                                    maxDays = now.day;
                                  }
                                  
                                  // 确保选择的天数不超过最大值
                                  if (endDay > maxDays) {
                                    endDay = maxDays;
                                  }
                                  
                                  // 更新结束日期
                                  tempEndDate = DateTime(endYear, endMonth, endDay);
                                  
                                  // 确保结束日期不早于开始日期
                                  if (tempEndDate.isBefore(tempStartDate)) {
                                    tempStartDate = tempEndDate;
                                    startYear = endYear;
                                    startMonth = endMonth;
                                    startDay = endDay;
                                  }
                                });
                              },
                              scrollController: FixedExtentScrollController(initialItem: endDay - 1),
                              children: List.generate(31, (index) => Center(
                                child: ScaledText(
                                  '${index + 1}${AppLocalizations.of(context)!.dayLabel}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
              const SizedBox(height: 20),
              // 清空按钮
              TextButton(
                onPressed: () {
                  setState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                  Navigator.pop(context);
                  _loadTransactions();
                },
                child: ScaledText(
                  AppLocalizations.of(context)!.clearDate,
                  style: TextStyle(color: ThemeHelper.primary(context)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: ScaledText(
                AppLocalizations.of(context)!.cancel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _startDate = tempStartDate;
                  _endDate = tempEndDate;
                });
                Navigator.pop(context);
                _loadTransactions();
              },
              child: ScaledText(
                AppLocalizations.of(context)!.confirm,
                style: TextStyle(color: ThemeHelper.primary(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getTypeDisplayText() {
    if (_selectedType == null) {
      return AppLocalizations.of(context)!.all;
    }
    return _selectedType == TransactionType.income ? AppLocalizations.of(context)!.income : AppLocalizations.of(context)!.expense;
  }
  
  void _showTypeFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeHelper.surface(context),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTypeFilterOption(null, AppLocalizations.of(context)!.all),
            const SizedBox(height: 12),
            _buildTypeFilterOption(TransactionType.income, AppLocalizations.of(context)!.income),
            const SizedBox(height: 12),
            _buildTypeFilterOption(TransactionType.expense, AppLocalizations.of(context)!.expense),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTypeFilterOption(TransactionType? type, String label) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
        Navigator.pop(context);
        _loadTransactions();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? ThemeHelper.primary(context).withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? ThemeHelper.primary(context)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? ThemeHelper.primary(context)
                  : Colors.white54,
            ),
            const SizedBox(width: 12),
            ScaledText(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getUserDisplayText() {
    if (_selectedUserId == null || _selectedUserId!.isEmpty) {
      return AppLocalizations.of(context)!.all;
    }
    final member = _members.firstWhere(
      (m) => m.id == _selectedUserId,
      orElse: () => FamilyMember(id: '', name: AppLocalizations.of(context)!.unknown, role: FamilyMemberRole.member),
    );
    return member.name;
  }
  
  void _showUserFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeHelper.surface(context),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUserFilterOption(null, AppLocalizations.of(context)!.all),
            const SizedBox(height: 12),
            ..._members.map((member) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildUserFilterOption(member.id, member.name),
            )),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
  
  Widget _buildUserFilterOption(String? userId, String label) {
    final isSelected = _selectedUserId == userId;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedUserId = userId;
        });
        Navigator.pop(context);
        _loadTransactions();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? ThemeHelper.primary(context).withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? ThemeHelper.primary(context)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? ThemeHelper.primary(context)
                  : Colors.white54,
            ),
            const SizedBox(width: 12),
            ScaledText(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.transactionDetail),
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _error != null
              ? custom.CustomErrorWidget(
                  message: _error!,
                  onRetry: _loadTransactions,
                )
              : Column(
                  children: [
                    // 筛选条件
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.horizontalPadding(context),
                        vertical: ResponsiveHelper.spacing(context, small: 12, normal: 16, large: 20),
                      ),
                      decoration: BoxDecoration(
                        color: ThemeHelper.surface(context),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // 日期筛选
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showDateRangePicker,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: ThemeHelper.surfaceLight(context),
                                      border: Border.all(
                                        color: ThemeHelper.primary(context),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.date_range,
                                          size: 18,
                                          color: ThemeHelper.primary(context),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ScaledText(
                                            _getDateDisplayText(),
                                            style: ResponsiveHelper.responsiveTextStyle(
                                              context,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, small: 8, normal: 12)),
                          // 关键词搜索
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: ThemeHelper.surfaceLight(context),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          onChanged: (value) {
                                            _searchKeyword = value;
                                          },
                                          onSubmitted: (value) {
                                            _searchKeyword = value;
                                            _loadTransactions();
                                          },
                                          style: const TextStyle(color: Colors.white),
                                          decoration: InputDecoration(
                                            hintText: AppLocalizations.of(context)!.searchKeyword,
                                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          _searchKeyword = _searchController.text;
                                          _loadTransactions();
                                        },
                                        icon: Icon(
                                          Icons.search,
                                          color: ThemeHelper.primary(context),
                                          size: 18,
                                        ),
                                      ),
                                      if (_searchKeyword != null && _searchKeyword!.isNotEmpty)
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _searchKeyword = '';
                                              _searchController.clear();
                                            });
                                            _loadTransactions();
                                          },
                                          icon: Icon(
                                            Icons.clear,
                                            color: Colors.white.withValues(alpha: 0.6),
                                            size: 16,
                                          ),
                                        ),                                   ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, small: 8, normal: 12)),
                          // 交易类型和用户筛选
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showTypeFilter,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: ThemeHelper.surfaceLight(context),
                                      border: Border.all(
                                        color: _selectedType != null
                                            ? ThemeHelper.primary(context)
                                            : Colors.white.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.swap_vert,
                                          size: 18,
                                          color: _selectedType != null
                                              ? ThemeHelper.primary(context)
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 8),
                                        ScaledText(
                                          _getTypeDisplayText(),
                                          style: ResponsiveHelper.responsiveTextStyle(
                                            context,
                                            color: _selectedType != null
                                                ? Colors.white
                                                : Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, small: 8, normal: 12)),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showUserFilter,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: ThemeHelper.surfaceLight(context),
                                      border: Border.all(
                                        color: _selectedUserId != null && _selectedUserId!.isNotEmpty
                                            ? ThemeHelper.primary(context)
                                            : Colors.white.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.person,
                                          size: 18,
                                          color: _selectedUserId != null && _selectedUserId!.isNotEmpty
                                              ? ThemeHelper.primary(context)
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ScaledText(
                                            _getUserDisplayText(),
                                            style: ResponsiveHelper.responsiveTextStyle(
                                              context,
                                              color: _selectedUserId != null && _selectedUserId!.isNotEmpty
                                                  ? Colors.white
                                                  : Colors.white54,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 交易列表
                    Expanded(
                      child: _transactions.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long,
                                    size: ResponsiveHelper.iconSize(context, defaultSize: 64),
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                  SizedBox(height: ResponsiveHelper.spacing(context)),
                                  ScaledText(
                                    AppLocalizations.of(context)!.noTransactionRecords,
                                    style: ResponsiveHelper.responsiveTextStyle(
                                      context,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.horizontalPadding(context),
                              ),
                              itemCount: _transactions.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                // 如果是最后一项且还有更多数据，显示加载指示器
                                if (index == _transactions.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child: _isLoadingMore
                                          ? CircularProgressIndicator(
                                              color: ThemeHelper.primary(context),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  );
                                }
                                final transaction = _transactions[index];
                                return _buildTransactionItem(transaction);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isIncome = transaction.type == TransactionType.income;
    
    // 限制description显示长度
    String? displayNote;
    if (transaction.description != null && transaction.description!.isNotEmpty) {
      if (transaction.description!.length > 20) {
        displayNote = '${transaction.description!.substring(0, 20)}...';
      } else {
        displayNote = transaction.description;
      }
    }
    
    return InkWell(
      onTap: () => _showTransactionDetail(transaction),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelper.surface(context),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isIncome
                    ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              child: Icon(
                Icons.category,
                color: isIncome ? ThemeHelper.primary(context) : Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScaledText(
                    transaction.category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ScaledText(
                        DateFormat('yyyy-MM-dd').format(transaction.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      if (displayNote != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ScaledText(
                            '· $displayNote',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScaledText(
                '${isIncome ? '+' : '-'}¥${transaction.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isIncome ? ThemeHelper.primary(context) : Colors.white,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: Colors.white.withValues(alpha: 0.6),
                size: 20,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditDialog(transaction);
                } else if (value == 'delete') {
                  _showDeleteDialog(transaction);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18, color: Colors.white),
                      SizedBox(width: 12),
                      ScaledText(AppLocalizations.of(context)!.edit, style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: ThemeHelper.expenseColor(context)),
                      const SizedBox(width: 12),
                      ScaledText(AppLocalizations.of(context)!.delete, style: TextStyle(color: ThemeHelper.expenseColor(context))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  void _showTransactionDetail(Transaction transaction) {
    final isIncome = transaction.type == TransactionType.income;
    
    // 查找用户信息
    String userName = AppLocalizations.of(context)!.unknown;
    if (transaction.userId.isNotEmpty) {
      final member = _members.firstWhere(
        (m) => m.id == transaction.userId,
        orElse: () => FamilyMember(id: '', name: AppLocalizations.of(context)!.unknown, role: FamilyMemberRole.member),
      );
      userName = member.name;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: Row(
          children: [
            Icon(
              isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ScaledText(
                AppLocalizations.of(context)!.transactionDetail,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(AppLocalizations.of(context)!.type, isIncome ? AppLocalizations.of(context)!.income : AppLocalizations.of(context)!.expense,
                  color: isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context)),
              _buildDetailRow(AppLocalizations.of(context)!.category, transaction.category),
              _buildDetailRow(AppLocalizations.of(context)!.amount, '¥${transaction.amount.toStringAsFixed(2)}',
                  color: isIncome ? ThemeHelper.primary(context) : Colors.white),
              _buildDetailRow(AppLocalizations.of(context)!.date, DateFormat.yMMMMd(Localizations.localeOf(context).languageCode).format(transaction.date)),
              _buildDetailRow(AppLocalizations.of(context)!.user, userName),
              if (transaction.counterparty != null && transaction.counterparty!.isNotEmpty)
                _buildDetailRow(AppLocalizations.of(context)!.counterparty, transaction.counterparty!),
              if (transaction.description != null && transaction.description!.isNotEmpty)
                _buildDetailRow(AppLocalizations.of(context)!.note, transaction.description!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: ScaledText(
              AppLocalizations.of(context)!.close,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScaledText(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          ScaledText(
            value,
            style: TextStyle(
              fontSize: 16,
              color: color ?? Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(Transaction transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: ScaledText(
          AppLocalizations.of(context)!.confirmDelete,
          style: TextStyle(color: Colors.white),
        ),
        content: ScaledText(
          AppLocalizations.of(context)!.confirmDeleteMessage,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: ScaledText(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelper.expenseColor(context),
            ),
            child: ScaledText(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _transactionService.deleteTransaction(transaction.id);
        
        // 在异步操作后使用 mounted 检查，确保 widget 仍然存在
        if (mounted) {
          CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.deleteSuccess);
          _loadTransactions();
        }
      } catch (e) {
        // 在异步操作后使用 mounted 检查，确保 widget 仍然存在
        if (mounted) {
          final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.deleteFailed);
          CustomSnackBar.showError(context, errorMessage);
        }
      }
    }
  }

  Future<void> _showEditDialog(Transaction transaction) async {
    final categoryProvider = context.read<CategoryProvider>();
    await categoryProvider.loadCategories();

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(text: transaction.amount.toStringAsFixed(2));
    final noteController = TextEditingController(text: transaction.description ?? '');
    
    TransactionType selectedType = transaction.type;
    models.Category? selectedCategory;
    DateTime selectedDate = transaction.date;

    // 查找对应的分类
    final categories = selectedType == TransactionType.expense
        ? categoryProvider.expenseCategories
        : categoryProvider.incomeCategories;
    
    for (var cat in categories) {
      if (cat.name == transaction.category) {
        selectedCategory = cat;
        break;
      }
    }

    bool isLoading = false;

    // 在异步操作前保存 context 到局部变量
    final localContext = context;
    
    await showDialog(
      context: localContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (statefulContext, setDialogState) => AlertDialog(
          backgroundColor: ThemeHelper.surface(statefulContext),
          title: ScaledText(
            AppLocalizations.of(context)!.editTransaction,
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 交易类型
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ThemeHelper.surfaceLight(statefulContext),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedType = TransactionType.expense;
                                selectedCategory = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == TransactionType.expense
                                    ? ThemeHelper.expenseColor(statefulContext).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    size: 16,
                                    color: selectedType == TransactionType.expense
                                        ? ThemeHelper.expenseColor(statefulContext)
                                        : Colors.white.withValues(alpha: 0.54),
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.expense,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == TransactionType.expense
                                          ? ThemeHelper.expenseColor(statefulContext)
                                          : Colors.white.withValues(alpha: 0.54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedType = TransactionType.income;
                                selectedCategory = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == TransactionType.income
                                    ? ThemeHelper.primary(statefulContext).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    size: 16,
                                    color: selectedType == TransactionType.income
                                        ? ThemeHelper.primary(statefulContext)
                                        : Colors.white.withValues(alpha: 0.54),
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.income,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == TransactionType.income
                                          ? ThemeHelper.primary(statefulContext)
                                          : Colors.white.withValues(alpha: 0.54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 金额
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.amount,
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.attach_money, color: Colors.white.withValues(alpha: 0.6)),
                      suffixText: '¥',
                      suffixStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.pleaseEnterAmount;
                      }
                      if (double.tryParse(value) == null) {
                        return AppLocalizations.of(context)!.pleaseEnterValidAmount;
                      }
                      if (double.parse(value) <= 0) {
                        return AppLocalizations.of(context)!.amountMustBeGreaterThanZero;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // 分类选择
                  ScaledText(
                    AppLocalizations.of(context)!.category,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (categoryContext) {
                      final categories = selectedType == TransactionType.expense
                          ? categoryProvider.expenseCategories
                          : categoryProvider.incomeCategories;
                      
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: categories.map((category) {
                              final isSelected = selectedCategory?.name == category.name;
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    selectedCategory = category;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: isSelected
                                        ? ThemeHelper.primary(categoryContext).withValues(alpha: 0.2)
                                        : ThemeHelper.surfaceLight(categoryContext),
                                    border: Border.all(
                                      color: isSelected
                                          ? ThemeHelper.primary(categoryContext)
                                          : Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: ScaledText(
                                    category.name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? ThemeHelper.primary(categoryContext)
                                          : Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // 日期选择
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(AppConstants.datePickerFirstYear),
                        lastDate: DateTime.now(),
                        locale: const Locale('zh', 'CN'), // 设置为中文
                        builder: (pickerContext, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: ThemeHelper.primary(pickerContext),
                                onPrimary: Colors.black,
                                surface: ThemeHelper.surface(pickerContext),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = DateTime(picked.year, picked.month, picked.day);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: ThemeHelper.surfaceLight(statefulContext),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.white.withValues(alpha: 0.6), size: 18),
                          const SizedBox(width: 8),
                          ScaledText(
                            DateFormat('yyyy-MM-dd').format(selectedDate),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 备注
                  TextFormField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.noteOptional,
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.note, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              child: ScaledText(
                AppLocalizations.of(context)!.cancel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      if (selectedCategory == null) {
                        CustomSnackBar.showError(dialogContext, AppLocalizations.of(context)!.pleaseSelectCategory);
                        return;
                      }
                      setDialogState(() {
                        isLoading = true;
                      });
                      try {
                        // 在异步操作前保存 dialogContext 到局部变量
                        final localDialogContext = dialogContext;
                        
                        await _transactionService.updateTransaction(
                          id: transaction.id,
                          type: selectedType.toInt(),
                          category: selectedCategory!.name,
                          amount: double.parse(amountController.text),
                          date: DateFormat('yyyy-MM-dd').format(selectedDate),
                          note: noteController.text.isNotEmpty ? noteController.text : null,
                        );
                        
                        // 使用局部变量 localDialogContext 代替 dialogContext
                        Navigator.pop(localDialogContext);
                        CustomSnackBar.showSuccess(localDialogContext, AppLocalizations.of(localContext)!.editSuccess);
                        _loadTransactions();
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                        });
                        
                        // 在异步操作前保存 dialogContext 到局部变量
                        final localDialogContext = dialogContext;
                        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(localContext)!.editFailed);
                        CustomSnackBar.showError(localDialogContext, errorMessage);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ScaledText(
                      AppLocalizations.of(context)!.save,
                      style: TextStyle(color: ThemeHelper.primary(dialogContext)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
