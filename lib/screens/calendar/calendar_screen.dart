import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api/calendar_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/date_picker_helper.dart';
import '../../utils/icon_constants.dart';
import '../../l10n/app_localizations.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarService _calendarService = CalendarService();
  Map<String, dynamic>? _calendarData;
  bool _isLoading = true;
  String? _error;
  DateTime _currentDate = DateTime.now();
  String _selectedDate = ''; // 格式：'24' (日期数字)

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDate = today.day.toString();
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 获取整月数据，不传day参数
      final data = await _calendarService.getCalendarOverview(
        year: _currentDate.year,
        month: _currentDate.month,
      );
      setState(() {
        _calendarData = data;
        _error = null;
        // 如果当前选中的日期在新的月份中不存在，重置为今天或1号
        final daysInMonth = _getDaysInMonth(_currentDate);
        final selectedDay = int.tryParse(_selectedDate);
        if (selectedDay == null || selectedDay > daysInMonth) {
          final today = DateTime.now();
          if (today.year == _currentDate.year && today.month == _currentDate.month) {
            _selectedDate = today.day.toString();
          } else {
            _selectedDate = '1';
          }
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _calendarData = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _previousMonth() {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month - 1);
    });
    _loadCalendarData();
  }

  void _nextMonth() {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month + 1);
    });
    _loadCalendarData();
  }

  Future<void> _showYearMonthPicker() async {
    final result = await DatePickerHelper.showYearMonthPicker(
      context,
      initialYear: _currentDate.year,
      initialMonth: _currentDate.month,
    );

    if (result != null) {
      setState(() {
        _currentDate = DateTime(result['year']!, result['month']!);
      });
      _loadCalendarData();
    }
  }

  void _onDateSelected(int day) {
    setState(() {
      _selectedDate = day.toString();
    });
    // 由于后端返回整月数据，只需更新选中状态，无需重新加载
  }

  void _onTabTapped(int index) async {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/calendar');
        break;
      case 2:
        await context.push('/add-transaction');
        // 从添加交易页面返回后刷新数据
        if (mounted) {
          _loadCalendarData();
        }
        break;
      case 3:
        context.go('/statistics');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  // 获取月份的第一天是星期几（0=周日, 1=周一, ..., 6=周六）
  int _getFirstDayOfMonth(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    return firstDay.weekday % 7; // 转换为0-6（0=周日）
  }

  // 获取月份的天数
  int _getDaysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  // 获取星期几的文本
  String _getWeekday(int day) {
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    if (locale.startsWith('zh')) {
      const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
      return weekdays[day % 7];
    } else {
      const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return weekdays[day % 7];
    }
  }

  // 格式化年月显示
  String _formatYearMonth(DateTime date) {
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    if (locale.startsWith('zh')) {
      return '${date.year}年 ${date.month}月';
    } else {
      final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${monthNames[date.month]} ${date.year}';
    }
  }

  // 格式化日期显示
  String _formatDate(int day) {
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    if (locale.startsWith('zh')) {
      return '${_currentDate.month}月$day日';
    } else {
      final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${monthNames[_currentDate.month]} $day';
    }
  }

  // 格式化星期几显示
  String _formatWeekday(String weekday) {
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    if (locale.startsWith('zh')) {
      return '星期$weekday';
    } else {
      return weekday;
    }
  }

  // 获取指定日期的汇总信息（income, expense）
  Map<String, dynamic>? _getDailySummary(int day) {
    if (_calendarData == null || _calendarData!['dailySummary'] == null) {
      return null;
    }
    
    final dailySummary = _calendarData!['dailySummary'] as Map<String, dynamic>?;
    if (dailySummary == null) {
      return null;
    }
    
    final dayKey = day.toString();
    final summary = dailySummary[dayKey] as Map<String, dynamic>?;
    return summary;
  }

  // 获取指定日期是否有交易
  bool _hasActivity(int day) {
    final summary = _getDailySummary(day);
    if (summary == null) return false;
    
    final income = (summary['income'] as num?)?.toDouble() ?? 0;
    final expense = (summary['expense'] as num?)?.toDouble() ?? 0;
    return income > 0 || expense > 0;
  }

  // 获取指定日期的交易金额（显示净额）
  String? _getDateAmount(int day) {
    final summary = _getDailySummary(day);
    if (summary == null) return null;
    
    final income = (summary['income'] as num?)?.toDouble() ?? 0;
    final expense = (summary['expense'] as num?)?.toDouble() ?? 0;
    final net = income - expense;
    
    if (net == 0) return null;
    
    // 格式化金额（简化显示，不显示小数）
    final amount = net.abs();
    if (amount >= 10000) {
      return '${net > 0 ? '+' : '-'}${(amount / 10000).toStringAsFixed(1)}w';
    } else {
      return '${net > 0 ? '+' : '-'}${amount.toStringAsFixed(0)}';
    }
  }

  // 获取指定日期的交易列表
  List<dynamic> _getDailyTransactions(int day) {
    if (_calendarData == null || _calendarData!['dailyDetails'] == null) {
      return [];
    }
    
    final dailyDetails = _calendarData!['dailyDetails'] as Map<String, dynamic>?;
    if (dailyDetails == null) {
      return [];
    }
    
    final dayKey = day.toString();
    final transactions = dailyDetails[dayKey] as List<dynamic>?;
    return transactions ?? [];
  }

  // Material Icons名称转换
  IconData _getIconData(String iconName) {
    return IconConstants.getIconFromString(iconName);
  }

  // 显示交易详情弹窗
  void _showTransactionDetail(Map<String, dynamic> transaction) {
    final type = transaction['type'] as int?;
    final isIncome = type == 0; // 0 表示收入
    
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
              _buildDetailRow(AppLocalizations.of(context)!.name, transaction['name'] as String? ?? ''),
              _buildDetailRow(AppLocalizations.of(context)!.category, transaction['cat'] as String? ?? ''),
              _buildDetailRow(AppLocalizations.of(context)!.amount, transaction['amount'] as String? ?? ''),
              _buildDetailRow(AppLocalizations.of(context)!.time, transaction['time'] as String? ?? ''),
              if (transaction['counterparty'] != null && (transaction['counterparty'] as String).isNotEmpty)
                _buildDetailRow(AppLocalizations.of(context)!.counterparty, transaction['counterparty'] as String),
              if (transaction['description'] != null && (transaction['description'] as String).isNotEmpty)
                _buildDetailRow(AppLocalizations.of(context)!.note, transaction['description'] as String),
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

  // 构建详情行
  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: ScaledText(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: ScaledText(
              value,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: ScaledText(AppLocalizations.of(context)!.calendar),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_today, color: ThemeHelper.primary(context)),
            onPressed: () {
              // 跳转到今天的日期
              final now = DateTime.now();
              setState(() {
                _currentDate = DateTime(now.year, now.month);
                _selectedDate = now.day.toString();
              });
              _loadCalendarData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _error != null
              ? custom.CustomErrorWidget(
                  message: _error!,
                  onRetry: _loadCalendarData,
                )
              : _buildScrollableContent(context),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
        onTap: _onTabTapped,
      ),
    );
  }

  // 构建可滚动内容（使用CustomScrollView实现整页滑动和固定头部）
  Widget _buildScrollableContent(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // 顶部内容（月度汇总、月份导航、日历网格）
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 月度汇总卡片
              if (_calendarData != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          AppLocalizations.of(context)!.monthlyIncome,
                          '¥${_calendarData!['monthlyIncome'] ?? '0'}',
                          ThemeHelper.primary(context),
                          context,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          AppLocalizations.of(context)!.monthlyExpense,
                          '¥${_calendarData!['monthlyExpense'] ?? '0'}',
                          ThemeHelper.expenseColor(context),
                          context,
                        ),
                      ),
                    ],
                  ),
                ),

              // 月份导航
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: ThemeHelper.surface(context),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMonth,
                      color: Colors.grey[400],
                    ),
                    GestureDetector(
                      onTap: _showYearMonthPicker,
                      child: Column(
                        children: [
                          ScaledText(
                            _formatYearMonth(_currentDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (_calendarData != null)
                            ScaledText(
                              '${AppLocalizations.of(context)!.monthlySurplus} ¥${_calendarData!['surplus'] ?? '0'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: ThemeHelper.primary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),

              // 日历网格
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: ThemeHelper.surface(context),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: ThemeHelper.primary(context),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 星期标题行
                          Row(
                            children: [
                              AppLocalizations.of(context)!.sunday,
                              AppLocalizations.of(context)!.monday,
                              AppLocalizations.of(context)!.tuesday,
                              AppLocalizations.of(context)!.wednesday,
                              AppLocalizations.of(context)!.thursday,
                              AppLocalizations.of(context)!.friday,
                              AppLocalizations.of(context)!.saturday,
                            ].map((day) {
                              return Expanded(
                                child: Center(
                                  child: ScaledText(
                                    day,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          // 日期网格
                          _buildCalendarGrid(context),
                        ],
                      ),
              ),
            ],
          ),
        ),

        // 详情列表头部（跟随滑动，到达顶部时固定）
        _buildDetailHeader(context),

        // 交易列表
        _buildTransactionsSliver(context),
      ],
    );
  }

  // 构建详情列表头部（跟随滑动，到达顶部时固定）
  Widget _buildDetailHeader(BuildContext context) {
    final selectedDay = int.tryParse(_selectedDate) ?? 0;
    final selectedDateObj = DateTime(
      _currentDate.year,
      _currentDate.month,
      selectedDay > 0 ? selectedDay : 1,
    );
    final weekday = _getWeekday(selectedDateObj.weekday % 7);

    // 计算固定高度（确保与实际内容高度匹配）
    const double headerHeight = 240.0;

    return SliverPersistentHeader(
      pinned: true,
      floating: false,
      delegate: _DetailHeaderDelegate(
        minHeight: headerHeight,
        maxHeight: headerHeight,
        child: SizedBox(
          height: headerHeight,
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 分隔线
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),

                // 标题和按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ScaledText(
                            selectedDay > 0
                                ? _formatDate(selectedDay)
                                : AppLocalizations.of(context)!.selectDate,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ScaledText(
                            selectedDay > 0 ? _formatWeekday(weekday) : '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await context.push('/add-transaction');
                          // 从添加交易页面返回后刷新数据
                          if (mounted) {
                            _loadCalendarData();
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: ScaledText(AppLocalizations.of(context)!.addTransaction),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.1),
                          foregroundColor: ThemeHelper.primary(context),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 每日汇总卡片
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: selectedDay > 0
                      ? _buildDailySummaryCard(context, selectedDay)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建交易列表Sliver
  Widget _buildTransactionsSliver(BuildContext context) {
    final selectedDay = int.tryParse(_selectedDate) ?? 0;
    final transactions = _getDailyTransactions(selectedDay);

    if (selectedDay <= 0) {
      return SliverToBoxAdapter(
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_note,
                size: 64,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              ScaledText(
                AppLocalizations.of(context)!.selectDateToViewTransactions,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_note,
                size: 64,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              ScaledText(
                AppLocalizations.of(context)!.noTransactionRecords,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 分离收入和支出交易
    final incomeTransactions = <Map<String, dynamic>>[];
    final expenseTransactions = <Map<String, dynamic>>[];
    
    for (var item in transactions) {
      final transaction = item as Map<String, dynamic>;
      final type = transaction['type'] as int?;
      if (type == 0) {  // 0 表示收入
        incomeTransactions.add(transaction);
      } else {  // 1 表示支出
        expenseTransactions.add(transaction);
      }
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final Map<String, dynamic> item;
            if (index < incomeTransactions.length) {
              item = incomeTransactions[index];
            } else {
              item = expenseTransactions[index - incomeTransactions.length];
            }
            
            final iconName = item['icon'] as String? ?? 'category';
            final iconData = _getIconData(iconName);
            final type = item['type'] as int?;
            final isIncome = type == 0;  // 0 表示收入
            final amountText = item['amount'] as String? ?? '';
            
            return InkWell(
              onTap: () => _showTransactionDetail(item),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Icon(
                        iconData,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ScaledText(
                            item['name'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          ScaledText(
                            '${item['cat'] ?? ''} - ${item['time'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ScaledText(
                      amountText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isIncome
                            ? ThemeHelper.primary(context)
                            : ThemeHelper.expenseColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: incomeTransactions.length + expenseTransactions.length,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelper.surface(context),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ScaledText(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ScaledText(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  // 构建每日汇总卡片
  Widget _buildDailySummaryCard(BuildContext context, int day) {
    final summary = _getDailySummary(day);
    
    if (summary == null) {
      return Container(
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: ThemeHelper.surfaceLight(context),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
        child: Center(
          child: ScaledText(
                  AppLocalizations.of(context)!.noData,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
        ),
      );
    }

    final income = (summary['income'] as num?)?.toDouble() ?? 0;
    final expense = (summary['expense'] as num?)?.toDouble() ?? 0;
    final net = income - expense;
    
    // 格式化金额（千分位）
    String formatAmount(double amount) {
      if (amount == 0) return '0';
      final formatter = NumberFormat('#,###');
      return formatter.format(amount);
    }
    
    return Container(
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: ThemeHelper.surfaceLight(context),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ThemeHelper.primary(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ScaledText(
                      AppLocalizations.of(context)!.incomeAmount,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ScaledText(
                  '¥${formatAmount(income)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ThemeHelper.primary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ThemeHelper.expenseColor(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ScaledText(
                      AppLocalizations.of(context)!.expenseAmount,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ScaledText(
                  '¥${formatAmount(expense)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ThemeHelper.expenseColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ScaledText(
                  AppLocalizations.of(context)!.net,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                ScaledText(
                  '¥${formatAmount(net)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: net >= 0
                        ? ThemeHelper.primary(context)
                        : ThemeHelper.expenseColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final firstDay = _getFirstDayOfMonth(_currentDate);
    final daysInMonth = _getDaysInMonth(_currentDate);
    final today = DateTime.now();
    final selectedDay = int.tryParse(_selectedDate) ?? 0;

    // 创建日期列表
    final List<int?> dates = [];

    // 添加空单元格（月份第一天之前的日期）
    for (int i = 0; i < firstDay; i++) {
      dates.add(null);
    }

    // 添加月份的所有日期
    for (int i = 1; i <= daysInMonth; i++) {
      dates.add(i);
    }

    // 计算需要的行数
    final rows = ((firstDay + daysInMonth) / 7).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        final startIndex = rowIndex * 7;
        final endIndex = 
            (startIndex + 7 < dates.length) ? startIndex + 7 : dates.length;
        final rowDates = dates.sublist(startIndex, endIndex);

        // 如果最后一行不足7个，补齐空单元格
        while (rowDates.length < 7) {
          rowDates.add(null);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: rowDates.map((day) {
              if (day == null) {
                return const Expanded(child: SizedBox(height: 48));
              }

              final isTodayDate = today.year == _currentDate.year &&
                  today.month == _currentDate.month &&
                  today.day == day;
              final isSelected = selectedDay == day;
              final dateAmount = _getDateAmount(day);
              final hasActivity = _hasActivity(day);
              final summary = _getDailySummary(day);
              
              // 获取金额颜色（收入为绿色，支出为红色）
              Color? amountColor;
              if (dateAmount != null && summary != null) {
                final income = (summary['income'] as num?)?.toDouble() ?? 0;
                final expense = (summary['expense'] as num?)?.toDouble() ?? 0;
                if (income > expense) {
                  amountColor = ThemeHelper.primary(context);
                } else if (expense > income) {
                  amountColor = ThemeHelper.expenseColor(context);
                }
              }

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onDateSelected(day),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isSelected
                          ? ThemeHelper.primary(context)
                          : Colors.transparent,
                      border: isTodayDate && !isSelected
                          ? Border.all(
                              color: ThemeHelper.primary(context).withValues(alpha: 0.5),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ScaledText(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected || isTodayDate
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? ThemeHelper.background(context)
                                : Colors.white,
                          ),
                        ),
                        if (dateAmount != null) ...[
                          const SizedBox(height: 2),
                          ScaledText(
                            dateAmount,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? ThemeHelper.background(context).withValues(alpha: 0.8)
                                  : (amountColor ?? Colors.white.withValues(alpha: 0.6)),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else if (hasActivity) ...[
                          const SizedBox(height: 4),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? ThemeHelper.background(context).withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }),
    );
  }
}

// 详情头部代理类（用于SliverPersistentHeader）
class _DetailHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _DetailHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: maxExtent,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_DetailHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}