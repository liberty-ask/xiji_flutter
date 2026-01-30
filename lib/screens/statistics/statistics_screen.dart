import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/api/statistics_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/scaled_text.dart';
import 'package:intl/intl.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/date_picker_helper.dart';
import '../../models/transaction.dart';
import '../../l10n/app_localizations.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatisticsService _statisticsService = StatisticsService();
  Map<String, dynamic>? _statsData;
  Map<String, dynamic>? _overviewData; // 概览数据
  Map<String, dynamic>? _trendData; // 趋势数据
  Map<String, dynamic>? _memberData; // 成员数据
  Map<String, dynamic>? _dateData; // 日期数据
  bool _isLoading = true;
  bool _isLoadingOverview = false;
  bool _isLoadingTrend = false;
  bool _isLoadingMember = false;
  bool _isLoadingDate = false;
  String? _error;
  String? _trendError; // 趋势数据错误
  TransactionType _type = TransactionType.expense; // 支出(EXPENSE=1) 或 收入(INCOME=0)
  String _period = 'month'; // 'week', 'month', 'year'
  DateTime _selectedDate = DateTime.now(); // 当前选择的日期
  String _activeTab = 'category'; // 'category', 'trend', 'member', 'date'
  TransactionType? _typeFilter; // 日期Tab的类型筛选（null表示全部）

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _loadStatistics();
  }

  // 获取周的开始和结束日期
  Map<String, DateTime> _getWeekRange() {
    // 计算周的开始（周一）和结束（周日）
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return {'start': weekStart, 'end': weekEnd};
  }

  // 加载概览数据
  Future<void> _loadOverview() async {
    setState(() {
      _isLoadingOverview = true;
    });

    try {
      final year = _selectedDate.year;
      final period = _period; // 'year', 'month', 'week'
      
      Map<String, dynamic> data;
      if (period == 'week') {
        final weekRange = _getWeekRange();
        data = await _statisticsService.getOverview(
          year: year,
          period: period,
          weekStartDate: DateFormat('yyyy-MM-dd').format(weekRange['start']!),
          weekEndDate: DateFormat('yyyy-MM-dd').format(weekRange['end']!),
        );
      } else if (period == 'month') {
        data = await _statisticsService.getOverview(
          year: year,
          period: period,
          month: _selectedDate.month,
        );
      } else {
        // period == 'year'
        data = await _statisticsService.getOverview(
          year: year,
          period: period,
        );
      }
      if (mounted) {
        setState(() {
          _overviewData = data;
          _isLoadingOverview = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOverview = false;
        });
      }
      // 概览加载失败不影响其他功能
    }
  }

  // 加载分类统计
  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final year = _selectedDate.year;
      final period = _period; // 'year', 'month', 'week'
      
      Map<String, dynamic> data;
      if (period == 'week') {
        final weekRange = _getWeekRange();
        data = await _statisticsService.getStatistics(
          type: _type.toInt(),
          year: year,
          period: period,
          weekStartDate: DateFormat('yyyy-MM-dd').format(weekRange['start']!),
          weekEndDate: DateFormat('yyyy-MM-dd').format(weekRange['end']!),
        );
      } else if (period == 'month') {
        data = await _statisticsService.getStatistics(
          type: _type.toInt(),
          year: year,
          period: period,
          month: _selectedDate.month,
        );
      } else {
        // period == 'year'
        data = await _statisticsService.getStatistics(
          type: _type.toInt(),
          year: year,
          period: period,
        );
      }
      setState(() {
        _statsData = data;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statsData = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 加载趋势数据
  Future<void> _loadTrend() async {
    if (_trendData != null) return; // 已加载则跳过

    setState(() {
      _isLoadingTrend = true;
      _trendError = null;
    });

    try {
      final year = _selectedDate.year;
      // 趋势接口的period参数：
      // - 年维度：period='year'，返回按月份聚合的数据
      // - 月维度：period='month'，返回按天聚合的数据
      // - 周维度：period='day'，返回按天聚合的数据（需要传weekStartDate和weekEndDate）
      final String period;
      int? month;
      String? weekStartDate;
      String? weekEndDate;
      
      if (_period == 'year') {
        period = 'year';
      } else if (_period == 'month') {
        period = 'month';
        month = _selectedDate.month;
      } else {
        // _period == 'week'
        period = 'day';
        final weekRange = _getWeekRange();
        weekStartDate = DateFormat('yyyy-MM-dd').format(weekRange['start']!);
        weekEndDate = DateFormat('yyyy-MM-dd').format(weekRange['end']!);
      }
      
      final data = await _statisticsService.getTrend(
        year: year,
        period: period,
        month: month,
        weekStartDate: weekStartDate,
        weekEndDate: weekEndDate,
      );
      if (mounted) {
        setState(() {
          _trendData = data;
          _isLoadingTrend = false;
          _trendError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTrend = false;
          _trendData = null;
          _trendError = e.toString();
        });
      }
    }
  }

  // 加载成员数据
  Future<void> _loadMember() async {
    if (_memberData != null) return; // 已加载则跳过

    setState(() {
      _isLoadingMember = true;
    });

    try {
      final year = _selectedDate.year;
      final period = _period; // 'year', 'month', 'week'
      
      Map<String, dynamic> data;
      if (period == 'week') {
        final weekRange = _getWeekRange();
        data = await _statisticsService.getByMember(
          type: _type.toInt(),
          year: year,
          period: period,
          weekStartDate: DateFormat('yyyy-MM-dd').format(weekRange['start']!),
          weekEndDate: DateFormat('yyyy-MM-dd').format(weekRange['end']!),
        );
      } else if (period == 'month') {
        data = await _statisticsService.getByMember(
          type: _type.toInt(),
          year: year,
          period: period,
          month: _selectedDate.month,
        );
      } else {
        // period == 'year'
        data = await _statisticsService.getByMember(
          type: _type.toInt(),
          year: year,
          period: period,
        );
      }
      if (mounted) {
        setState(() {
          _memberData = data;
          _isLoadingMember = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMember = false;
        });
      }
    }
  }

  // 加载日期数据
  Future<void> _loadDate() async {
    setState(() {
      _isLoadingDate = true;
    });

    try {
      final year = _selectedDate.year;
      final period = _period; // 'year', 'month', 'week'
      
      Map<String, dynamic> data;
      if (period == 'week') {
        final weekRange = _getWeekRange();
        data = await _statisticsService.getByDate(
          year: year,
          period: period,
          weekStartDate: DateFormat('yyyy-MM-dd').format(weekRange['start']!),
          weekEndDate: DateFormat('yyyy-MM-dd').format(weekRange['end']!),
          type: _typeFilter?.toInt(),
        );
      } else if (period == 'month') {
        data = await _statisticsService.getByDate(
          year: year,
          period: period,
          month: _selectedDate.month,
          type: _typeFilter?.toInt(),
        );
      } else {
        // period == 'year'
        data = await _statisticsService.getByDate(
          year: year,
          period: period,
          type: _typeFilter?.toInt(),
        );
      }
      if (mounted) {
        setState(() {
          _dateData = data;
          _isLoadingDate = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDate = false;
        });
      }
    }
  }

  // 切换Tab时加载对应数据
  void _onTabChanged(String tab) {
    setState(() {
      _activeTab = tab;
    });

    switch (tab) {
      case 'trend':
        _loadTrend();
        break;
      case 'member':
        _loadMember();
        break;
      case 'date':
        _loadDate();
        break;
      case 'category':
      default:
        _loadStatistics();
        break;
    }
  }

  void _onTabTapped(int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/calendar');
        break;
      case 2:
        context.push('/add-transaction');
        break;
      case 3:
        context.go('/statistics');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  // Material Icons名称转换
  IconData? _getIconData(String iconName) {
    final iconMap = <String, IconData>{
      'restaurant': Icons.restaurant,
      'shopping_cart': Icons.shopping_cart,
      'directions_car': Icons.directions_car,
      'movie': Icons.movie,
      'payments': Icons.payments,
      'trending_up': Icons.trending_up,
    };
    return iconMap[iconName] ?? Icons.category;
  }

  // 颜色字符串转Color
  Color _parseColor(String colorStr, BuildContext context) {
    try {
      return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (e) {
      return ThemeHelper.primary(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: ScaledText(AppLocalizations.of(context)!.statistics),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _showDatePicker,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadOverview();
          await _loadStatistics();
          if (_activeTab == 'trend') await _loadTrend();
          if (_activeTab == 'member') await _loadMember();
          if (_activeTab == 'date') await _loadDate();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // 日期选择和周期选择
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.horizontalPadding(context),
                  ResponsiveHelper.verticalPadding(context),
                  ResponsiveHelper.horizontalPadding(context),
                  0,
                ),
                child: Column(
                  children: [
                    // 日期选择按钮
                    GestureDetector(
                      onTap: _showDatePicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: ThemeHelper.surface(context),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: ThemeHelper.primary(context),
                            ),
                            const SizedBox(width: 8),
                            ScaledText(
                              _getDateDisplayText(),
                              style: ResponsiveHelper.responsiveTextStyle(
                                context,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 周期选择
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: ThemeHelper.surface(context),
                      ),
                      child: Row(
                        children: [
                          _buildPeriodButton(AppLocalizations.of(context)!.week, 'week', context),
                          _buildPeriodButton(AppLocalizations.of(context)!.month, 'month', context),
                          _buildPeriodButton(AppLocalizations.of(context)!.year, 'year', context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 20, large: 24)),

              // 顶部概览卡片
              _buildOverviewCards(context),

              SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 28)),

              // Tab导航
              _buildTabNavigation(context),

              SizedBox(height: ResponsiveHelper.spacing(context, small: 16, normal: 20, large: 24)),

              // Tab内容区域
              _buildTabContent(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 3,
        onTap: _onTabTapped,
      ),
    );
  }

  // 构建顶部概览卡片
  Widget _buildOverviewCards(BuildContext context) {
    if (_isLoadingOverview || _overviewData == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: ThemeHelper.surface(context),
          ),
          child: const Center(
            child: LoadingIndicator(),
          ),
        ),
      );
    }

    final totalIncome = (_overviewData!['totalIncome'] as num?)?.toDouble() ?? 0.0;
    final totalExpense = (_overviewData!['totalExpense'] as num?)?.toDouble() ?? 0.0;
    final netIncome = (_overviewData!['netIncome'] as num?)?.toDouble() ?? 0.0;
    final incomeChange = (_overviewData!['incomeChange'] as num?)?.toDouble() ?? 0.0;
    final expenseChange = (_overviewData!['expenseChange'] as num?)?.toDouble() ?? 0.0;

    return SizedBox(
      height: 130,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
        children: [
          _buildOverviewCard(
            context,
            AppLocalizations.of(context)!.totalIncome,
            totalIncome,
            Icons.trending_up,
            ThemeHelper.primary(context),
            incomeChange,
          ),
          const SizedBox(width: 12),
          _buildOverviewCard(
            context,
            AppLocalizations.of(context)!.totalExpense,
            totalExpense,
            Icons.trending_down,
            ThemeHelper.expenseColor(context),
            expenseChange,
          ),
          const SizedBox(width: 12),
          _buildOverviewCard(
            context,
            AppLocalizations.of(context)!.netIncome,
            netIncome,
            Icons.account_balance_wallet,
            netIncome >= 0 ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
            null,
          ),
        ],
      ),
    );
  }

  // 构建单个概览卡片
  Widget _buildOverviewCard(
    BuildContext context,
    String title,
    double amount,
    IconData icon,
    Color color,
    double? change,
  ) {
    return Container(
      width: 160,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 20, color: color),
              if (change != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 12,
                              color: change >= 0 ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
                            ),
                            ScaledText(
                              '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 10,
                                color: change >= 0 ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
            ],
          ),
          const SizedBox(height: 6),
          ScaledText(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          ScaledText(
            '¥${_formatAmount(amount)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // 格式化金额
  String _formatAmount(double amount) {
    if (amount >= 10000) {
      return '${(amount / 10000).toStringAsFixed(1)}w';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}k';
    }
    return amount.toStringAsFixed(0);
  }

  // 构建Tab导航
  Widget _buildTabNavigation(BuildContext context) {
    final tabs = <Widget>[
      _buildTabButton(context, AppLocalizations.of(context)!.category, 'category', Icons.category),
      _buildTabButton(context, AppLocalizations.of(context)!.trend, 'trend', Icons.show_chart),
      _buildTabButton(context, AppLocalizations.of(context)!.member, 'member', Icons.people),
      _buildTabButton(context, AppLocalizations.of(context)!.date, 'date', Icons.calendar_view_month),
    ];
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelper.surface(context),
        ),
        child: Row(
          children: tabs,
        ),
      ),
    );
  }

  // 构建Tab按钮
  Widget _buildTabButton(BuildContext context, String label, String tab, IconData icon) {
    final isSelected = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? ThemeHelper.primary(context)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? ThemeHelper.background(context)
                    : Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ScaledText(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? ThemeHelper.background(context)
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建Tab内容
  Widget _buildTabContent(BuildContext context) {
    switch (_activeTab) {
      case 'trend':
        return _buildTrendTab(context);
      case 'member':
        return _buildMemberTab(context);
      case 'date':
        return _buildDateTab(context);
      case 'category':
      default:
        return _buildCategoryTab(context);
    }
  }

  // 构建分类Tab（原有功能）
  Widget _buildCategoryTab(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: LoadingIndicator(),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: custom.CustomErrorWidget(
          message: _error!,
          onRetry: _loadStatistics,
        ),
      );
    }

    if (_statsData == null) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(child: Text(AppLocalizations.of(context)!.noData, style: TextStyle(color: Colors.white54))),
      );
    }

    return Column(
      children: [
        // 环形图表
        _buildChartPreview(context),
        SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 40, large: 48)),
        // 分类明细标题和类型选择
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.horizontalPadding(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ScaledText(
                _type == TransactionType.expense ? AppLocalizations.of(context)!.expenseDetails : AppLocalizations.of(context)!.incomeDetails,
                style: ResponsiveHelper.responsiveTitleStyle(context, color: Colors.white),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: ThemeHelper.surface(context),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTypeToggleButton(AppLocalizations.of(context)!.expense, TransactionType.expense),
                      ),
                      Expanded(
                        child: _buildTypeToggleButton(AppLocalizations.of(context)!.income, TransactionType.income),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 分类统计列表
        if (_statsData!['items'] != null)
          ...((_statsData!['items'] as List).map((item) {
            return _buildCategoryItem(context, item);
          }).toList()),
      ],
    );
  }

  // 构建分类列表项
  Widget _buildCategoryItem(BuildContext context, dynamic item) {
    final itemMap = item as Map<String, dynamic>;
    final name = itemMap['name'] as String? ?? '';
    final amount = itemMap['amount'] as String? ?? '';
    final pct = itemMap['pct'] as String? ?? '0%';
    final color = itemMap['color'] as String? ?? '#13ec5b';
    final icon = itemMap['icon'] as String? ?? 'category';
    final iconData = _getIconData(icon);
    final colorObj = _parseColor(color, context);
    
    final percentValue = double.tryParse(pct.replaceAll('%', '')) ?? 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelper.surface(context),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: Icon(
                iconData,
                color: Colors.white.withValues(alpha: 0.6),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ScaledText(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      ScaledText(
                        amount,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: percentValue / 100,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(colorObj),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ScaledText(
                        pct,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.3),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建趋势Tab
  Widget _buildTrendTab(BuildContext context) {
    if (_isLoadingTrend) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: LoadingIndicator(),
      );
    }

    if (_trendError != null) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: custom.CustomErrorWidget(
          message: _trendError!,
          onRetry: () {
            _trendData = null; // 清空缓存，强制重新加载
            _loadTrend();
          },
        ),
      );
    }

    if (_trendData == null || ((_trendData!['items'] as List?)?.isEmpty ?? true)) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: ScaledText(
          AppLocalizations.of(context)!.noTrendData,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        ),
      );
    }

    final items = _trendData!['items'] as List;
    final summary = _trendData!['summary'] as Map<String, dynamic>?;

    return Column(
      children: [
        // 折线图
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
          child: Container(
            height: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: ThemeHelper.surface(context),
            ),
            child: _buildTrendLineChart(context, items),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 统计摘要
        if (summary != null) _buildTrendSummary(context, summary),
      ],
    );
  }

  // 构建趋势折线图
  Widget _buildTrendLineChart(BuildContext context, List items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noData,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }

    // 准备图表数据
    final spotsIncome = <FlSpot>[];
    final spotsExpense = <FlSpot>[];
    final bottomTitles = <String>[];

    double maxValue = 0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final income = ((item['income'] as num?) ?? 0).toDouble();
      final expense = ((item['expense'] as num?) ?? 0).toDouble();
      final dateLabel = item['dateLabel'] as String? ?? '';

      spotsIncome.add(FlSpot(i.toDouble(), income));
      spotsExpense.add(FlSpot(i.toDouble(), expense));
      bottomTitles.add(dateLabel);

      maxValue = [maxValue, income, expense].reduce((a, b) => a > b ? a : b);
    }

    // 计算Y轴最大值（向上取整到最近的整千或整万）
    // 如果所有数据都为0，设置一个最小值以确保图表正常显示
    double maxY = maxValue * 1.2;
    if (maxY <= 0) {
      maxY = 100.0; // 设置最小值为100，确保图表有可见的Y轴
    } else if (maxY < 1000) {
      maxY = ((maxY / 100).ceil() * 100).toDouble();
    } else if (maxY < 10000) {
      maxY = ((maxY / 1000).ceil() * 1000).toDouble();
    } else {
      maxY = ((maxY / 10000).ceil() * 10000).toDouble();
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withValues(alpha: 0.05),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 5,
              getTitlesWidget: (value, meta) {
                return ScaledText(
                  _formatAmount(value),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              // 根据数据量动态调整标签间隔，最多显示8个标签
              interval: items.length <= 8 
                  ? 1.0 
                  : (items.length / 8).ceil().toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < bottomTitles.length) {
                  final label = bottomTitles[index];
                  // 简化标签显示，根据数据量调整显示长度
                  String displayLabel = label;
                  if (items.length > 12) {
                    // 数据量多时，进一步简化标签
                    // 对于包含年份和月份的标签，只显示月份部分
                    // 处理中文格式 (e.g., "2026年01月")
                    if (label.contains('年')) {
                      final parts = label.split('年');
                      if (parts.length > 1) {
                        displayLabel = parts[1];
                      }
                    } 
                    // 处理英文格式 (e.g., "January 2026")
                    else if (label.contains(' ')) {
                      final parts = label.split(' ');
                      if (parts.length > 0) {
                        displayLabel = parts[0];
                      }
                    }
                    // 对于其他格式，限制长度
                    else if (label.length > 6) {
                      displayLabel = label.substring(0, 6);
                    }
                  } else if (label.length > 8) {
                    displayLabel = label.substring(0, 8);
                  }
                  return ScaledText(
                    displayLabel,
                    style: TextStyle(
                      fontSize: items.length > 12 ? 9 : 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        minX: 0,
        maxX: (items.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          // 收入折线
          LineChartBarData(
            spots: spotsIncome,
            isCurved: true,
            color: ThemeHelper.primary(context),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: ThemeHelper.primary(context).withValues(alpha: 0.1),
            ),
          ),
          // 支出折线
          LineChartBarData(
            spots: spotsExpense,
            isCurved: true,
            color: ThemeHelper.expenseColor(context),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final isIncome = touchedSpot.barIndex == 0;
                final value = touchedSpot.y;
                return LineTooltipItem(
                  '${isIncome ? AppLocalizations.of(context)!.income : AppLocalizations.of(context)!.expense}: ¥${_formatAmount(value)}',
                  TextStyle(
                    color: isIncome ? ThemeHelper.primary(context) : ThemeHelper.expenseColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  // 构建趋势摘要
  Widget _buildTrendSummary(BuildContext context, Map<String, dynamic> summary) {
    final avgIncome = ((summary['avgIncome'] as num?) ?? 0).toDouble();
    final avgExpense = ((summary['avgExpense'] as num?) ?? 0).toDouble();
    final totalIncome = ((summary['totalIncome'] as num?) ?? 0).toDouble();
    final totalExpense = ((summary['totalExpense'] as num?) ?? 0).toDouble();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelper.surface(context),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryItem(context, AppLocalizations.of(context)!.averageIncome, avgIncome, ThemeHelper.primary(context)),
            ),
            Expanded(
              child: _buildSummaryItem(context, AppLocalizations.of(context)!.averageExpense, avgExpense, ThemeHelper.expenseColor(context)),
            ),
            Expanded(
              child: _buildSummaryItem(context, AppLocalizations.of(context)!.totalIncomeLabel, totalIncome, ThemeHelper.primary(context)),
            ),
            Expanded(
              child: _buildSummaryItem(context, AppLocalizations.of(context)!.totalExpenseLabel, totalExpense, ThemeHelper.expenseColor(context)),
            ),
          ],
        ),
      ),
    );
  }

  // 构建摘要项
  Widget _buildSummaryItem(BuildContext context, String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ScaledText(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ScaledText(
              '¥${_formatAmount(value)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // 构建成员Tab
  Widget _buildMemberTab(BuildContext context) {
    if (_isLoadingMember) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: LoadingIndicator(),
      );
    }

    if (_memberData == null || ((_memberData!['items'] as List?)?.isEmpty ?? true)) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: ScaledText(
          AppLocalizations.of(context)!.noMemberData,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        ),
      );
    }

    final items = _memberData!['items'] as List;

    return Column(
      children: [
        // 类型切换
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ThemeHelper.surface(context),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTypeToggleButton(AppLocalizations.of(context)!.expense, TransactionType.expense),
                ),
                Expanded(
                  child: _buildTypeToggleButton(AppLocalizations.of(context)!.income, TransactionType.income),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 柱状图
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
          child: Container(
            height: 250,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: ThemeHelper.surface(context),
            ),
            child: _buildMemberBarChart(context, items),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 成员列表
        ...items.map((item) => _buildMemberItem(context, item as Map<String, dynamic>)),
      ],
    );
  }

  // 构建成员柱状图
  Widget _buildMemberBarChart(BuildContext context, List items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noData,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }

    // 准备柱状图数据
    final barGroups = <BarChartGroupData>[];
    final bottomTitles = <String>[];
    double maxValue = 0;

    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final amount = ((item['amount'] as num?) ?? 0).toDouble();
      final memberName = item['memberName'] as String? ?? '';
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: amount,
              color: _type == TransactionType.expense 
                  ? ThemeHelper.expenseColor(context)
                  : ThemeHelper.primary(context),
              width: 20,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
      bottomTitles.add(memberName.length > 4 ? '${memberName.substring(0, 4)}...' : memberName);
      maxValue = maxValue > amount ? maxValue : amount;
    }

    // 计算Y轴最大值
    double maxY = maxValue * 1.2;
    if (maxY < 1000) {
      maxY = ((maxY / 100).ceil() * 100).toDouble();
    } else if (maxY < 10000) {
      maxY = ((maxY / 1000).ceil() * 1000).toDouble();
    } else {
      maxY = ((maxY / 10000).ceil() * 10000).toDouble();
    }

    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withValues(alpha: 0.05),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 5,
              getTitlesWidget: (value, meta) {
                return ScaledText(
                  _formatAmount(value),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < bottomTitles.length) {
                  return ScaledText(
                    bottomTitles[value.toInt()],
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        minY: 0,
        maxY: maxY,
        barGroups: barGroups,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = items[groupIndex] as Map<String, dynamic>;
              final memberName = item['memberName'] as String? ?? '';
              return BarTooltipItem(
                '$memberName\n¥${_formatAmount(rod.toY)}',
                TextStyle(
                  color: _type == TransactionType.expense 
                      ? ThemeHelper.expenseColor(context)
                      : ThemeHelper.primary(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // 构建成员列表项
  Widget _buildMemberItem(BuildContext context, Map<String, dynamic> item) {
    final memberName = item['memberName'] as String? ?? '';
    final amount = item['amountStr'] as String? ?? '¥0';
    final percentage = item['percentageStr'] as String? ?? '0%';
    final count = item['count'] as int? ?? 0;
    final avatar = item['avatar'] as String?;

    final percentValue = double.tryParse(
        percentage.replaceAll('%', '')) ?? 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.horizontalPadding(context),
        0,
        ResponsiveHelper.horizontalPadding(context),
        12,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelper.surface(context),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: avatar != null && avatar.isNotEmpty
                  ? ClipOval(
                      child: Image.network(avatar, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.person,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 24,
                        );
                      }),
                    )
                  : Icon(
                      Icons.person,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 24,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ScaledText(
                        memberName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      ScaledText(
                        amount,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _type == TransactionType.expense
                              ? ThemeHelper.expenseColor(context)
                              : ThemeHelper.primary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: percentValue / 100,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _type == TransactionType.expense
                                  ? ThemeHelper.expenseColor(context)
                                  : ThemeHelper.primary(context),
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ScaledText(
                        '$percentage | $count${AppLocalizations.of(context)!.transactions}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.3),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建日期Tab
  Widget _buildDateTab(BuildContext context) {
    if (_isLoadingDate) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: LoadingIndicator(),
      );
    }

    if (_dateData == null || ((_dateData!['days'] as List?)?.isEmpty ?? true)) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: ScaledText(
          AppLocalizations.of(context)!.noDateData,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        ),
      );
    }

    final days = _dateData!['days'] as List;
    final year = (_dateData!['year'] as int?) ?? DateTime.now().year;
    final month = (_dateData!['month'] as int?) ?? DateTime.now().month;

    return Column(
      children: [
        // 类型切换
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: ThemeHelper.surface(context),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDateTypeToggleButton(AppLocalizations.of(context)!.all, null),
                    _buildDateTypeToggleButton(AppLocalizations.of(context)!.expense, TransactionType.expense),
                    _buildDateTypeToggleButton(AppLocalizations.of(context)!.income, TransactionType.income),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 日历热力图
        Padding(
          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.horizontalPadding(context)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: ThemeHelper.surface(context),
            ),
            child: _buildDateHeatmap(context, days, year, month),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context)),
        // 日期列表
        ..._buildDateList(context, days),
      ],
    );
  }

  // 构建日期类型切换按钮
  Widget _buildDateTypeToggleButton(String label, TransactionType? type) {
    final isSelected = type == null ? (_typeFilter == null) : (_typeFilter == type);
    return GestureDetector(
      onTap: () {
        setState(() {
          _typeFilter = type;
          _dateData = null; // 清空数据，强制重新加载
        });
        _loadDate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: ScaledText(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }

  // 构建日期热力图
  Widget _buildDateHeatmap(BuildContext context, List days, int year, int month) {
    // 创建日期映射
    final dateMap = <String, Map<String, dynamic>>{};
    for (final day in days) {
      final dayMap = day as Map<String, dynamic>;
      final date = dayMap['date'] as String? ?? '';
      dateMap[date] = dayMap;
    }

    // 获取月份的第一天和最后一天
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final firstWeekday = firstDay.weekday;
    final daysInMonth = lastDay.day;

    // 计算最大金额（用于颜色强度）
    double maxAmount = 0;
    for (final day in days) {
      final dayMap = day as Map<String, dynamic>;
      final income = ((dayMap['income'] as num?) ?? 0).toDouble();
      final expense = ((dayMap['expense'] as num?) ?? 0).toDouble();
      final amount = income + expense;
      if (amount > maxAmount) maxAmount = amount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 星期标题
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            AppLocalizations.of(context)!.sunday,
            AppLocalizations.of(context)!.monday,
            AppLocalizations.of(context)!.tuesday,
            AppLocalizations.of(context)!.wednesday,
            AppLocalizations.of(context)!.thursday,
            AppLocalizations.of(context)!.friday,
            AppLocalizations.of(context)!.saturday,
          ].map((day) {
            return SizedBox(
              width: 40,
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // 日期网格
        Column(
          children: List.generate((firstWeekday + daysInMonth + 6) ~/ 7, (week) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (day) {
                final index = week * 7 + day;
                if (index < firstWeekday || index >= firstWeekday + daysInMonth) {
                  // 空白格子
                  return const SizedBox(width: 40, height: 40);
                }

                final dayNum = index - firstWeekday + 1;
                final dateStr = DateFormat('yyyy-MM-dd').format(DateTime(year, month, dayNum));
                final dayData = dateMap[dateStr];

                if (dayData == null) {
                  // 无数据
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Center(
                      child: ScaledText(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  );
                }

                final income = ((dayData['income'] as num?) ?? 0).toDouble();
                final expense = ((dayData['expense'] as num?) ?? 0).toDouble();
                final amount = income + expense;

                // 根据金额计算颜色强度
                double opacity = 0.1;
                if (maxAmount > 0) {
                  opacity = 0.1 + (amount / maxAmount) * 0.9;
                }

                Color cellColor;
                if (income > expense) {
                  cellColor = ThemeHelper.primary(context).withValues(alpha: opacity);
                } else if (expense > income) {
                  cellColor = ThemeHelper.expenseColor(context).withValues(alpha: opacity);
                } else {
                  cellColor = Colors.white.withValues(alpha: 0.05);
                }

                return Tooltip(
                  message: '$dateStr\n${AppLocalizations.of(context)!.incomeAmount}: ¥${_formatAmount(income)}\n${AppLocalizations.of(context)!.expenseAmount}: ¥${_formatAmount(expense)}',
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: cellColor,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: ScaledText(
                        '$dayNum',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ],
    );
  }

  // 构建日期列表
  List<Widget> _buildDateList(BuildContext context, List days) {
    // 过滤数据
    List filteredDays = days;
    if (_typeFilter != null) {
      filteredDays = days.where((day) {
        final dayMap = day as Map<String, dynamic>;
        if (_typeFilter == TransactionType.expense) {
          return ((dayMap['expense'] as num?) ?? 0).toDouble() > 0;
        } else {
          return ((dayMap['income'] as num?) ?? 0).toDouble() > 0;
        }
      }).toList();
    }

    // 按日期降序排序
    filteredDays.sort((a, b) {
      final dateA = (a as Map<String, dynamic>)['date'] as String? ?? '';
      final dateB = (b as Map<String, dynamic>)['date'] as String? ?? '';
      return dateB.compareTo(dateA);
    });

    return filteredDays.map((day) {
      return _buildDateListItem(context, day as Map<String, dynamic>);
    }).toList();
  }

  // 构建日期列表项
  Widget _buildDateListItem(BuildContext context, Map<String, dynamic> dayData) {
    final date = dayData['date'] as String? ?? '';
    final income = ((dayData['income'] as num?) ?? 0).toDouble();
    final expense = ((dayData['expense'] as num?) ?? 0).toDouble();
    final net = ((dayData['net'] as num?) ?? 0).toDouble();
    final count = dayData['count'] as int? ?? 0;

    // 解析日期
    DateTime? dateObj;
    try {
      dateObj = DateTime.parse(date);
    } catch (e) {
      dateObj = DateTime.now();
    }

    // 根据当前语言环境格式化日期
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    String dateLabel;
    if (locale.startsWith('zh')) {
      dateLabel = DateFormat('MM月dd日 EEEE', 'zh_CN').format(dateObj);
      dateLabel = dateLabel.replaceAll('星期', '周');
    } else {
      dateLabel = DateFormat('MMM d, EEEE', locale).format(dateObj);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.horizontalPadding(context),
        0,
        ResponsiveHelper.horizontalPadding(context),
        12,
      ),
      child: Container(
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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ScaledText(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Expanded(
                  child: ScaledText(
                    '${AppLocalizations.of(context)!.net}: ¥${_formatAmount(net)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: net >= 0 
                          ? ThemeHelper.primary(context)
                          : ThemeHelper.expenseColor(context),
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 16,
                        color: ThemeHelper.primary(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ScaledText(
                          '${AppLocalizations.of(context)!.incomeAmount}: ¥${_formatAmount(income)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.trending_down,
                        size: 16,
                        color: ThemeHelper.expenseColor(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ScaledText(
                          '${AppLocalizations.of(context)!.expenseAmount}: ¥${_formatAmount(expense)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: ScaledText(
                    '$count${AppLocalizations.of(context)!.transactions}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartPreview(BuildContext context) {
    if (_statsData == null) return const SizedBox.shrink();

    final total = _statsData!['total'] as String? ?? '0';
    final change = _statsData!['change'] as String? ?? '0%';
    final items = _statsData!['items'] as List? ?? [];

    if (items.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.noData,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final pieChartData = items.map((item) {
      final itemMap = item as Map<String, dynamic>;
      final pct = itemMap['pct'] as String? ?? '0%';
      final color = itemMap['color'] as String? ?? '#13ec5b';
      final percentValue = double.tryParse(pct.replaceAll('%', '')) ?? 0.0;
      return PieChartSectionData(
        value: percentValue,
        color: _parseColor(color, context),
        radius: 80,
        showTitle: false,
      );
    }).toList();

    // 图表尺寸（缩小以匹配原始设计）
    const double chartSize = 200.0;
    const double centerSpaceRadius = 70.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        height: chartSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 环形图表（使用PieChart）
            SizedBox(
              width: chartSize,
              height: chartSize,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ThemeHelper.primary(context).withValues(alpha: 0.1),
                      blurRadius: 60,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: PieChart(
                  PieChartData(
                    sections: pieChartData,
                    sectionsSpace: 1.5,
                    centerSpaceRadius: centerSpaceRadius,
                    startDegreeOffset: -90,
                  ),
                ),
              ),
            ),
            // 中心文字
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '总${_type == TransactionType.expense ? AppLocalizations.of(context)!.totalExpenseLabel : AppLocalizations.of(context)!.totalIncomeLabel}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '¥$total',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '较上月 $change',
                  style: TextStyle(
                    fontSize: 10,
                    color: ThemeHelper.primary(context),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, String period, BuildContext context) {
    final isSelected = _period == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _period = period;
            // 清空缓存，强制刷新
            _overviewData = null;
            _statsData = null;
            _trendData = null;
            _memberData = null;
            _dateData = null;
            _trendError = null; // 清空趋势错误状态
          });
          _loadOverview();
          _loadStatistics();
          // 如果当前Tab需要加载数据，则加载
          if (_activeTab == 'trend') _loadTrend();
          if (_activeTab == 'member') _loadMember();
          if (_activeTab == 'date') _loadDate();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? ThemeHelper.primary(context)
                : Colors.transparent,
          ),
          child: ScaledText(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? ThemeHelper.background(context)
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggleButton(String label, TransactionType type) {
    final isSelected = _type == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _type = type;
          // 清空分类和成员数据缓存，强制刷新
          _statsData = null;
          _memberData = null;
        });
        _loadStatistics();
        if (_activeTab == 'member') _loadMember();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: ScaledText(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  String _getDateDisplayText() {
    // 获取当前语言环境
    final locale = AppLocalizations.of(context)?.localeName ?? 'zh_CN';
    final isChinese = locale.startsWith('zh');
    
    switch (_period) {
      case 'week':
        // 显示周的开始和结束日期
        final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        if (isChinese) {
          return '${DateFormat('MM月dd日').format(weekStart)} - ${DateFormat('MM月dd日').format(weekEnd)}';
        } else {
          return '${DateFormat('MM/dd').format(weekStart)} - ${DateFormat('MM/dd').format(weekEnd)}';
        }
      case 'month':
        if (isChinese) {
          return DateFormat('yyyy年MM月').format(_selectedDate);
        } else {
          return DateFormat('MMMM yyyy', 'en_US').format(_selectedDate);
        }
      case 'year':
        return '${_selectedDate.year}';
      default:
        if (isChinese) {
          return DateFormat('yyyy年MM月').format(_selectedDate);
        } else {
          return DateFormat('MMMM yyyy', 'en_US').format(_selectedDate);
        }
    }
  }

  Future<void> _showDatePicker() async {
    if (_period == 'year') {
      // 只选择年份
      final year = await DatePickerHelper.showYearPicker(
        context,
        initialYear: _selectedDate.year,
      );
      if (year != null) {
        setState(() {
          _selectedDate = DateTime(year, 1, 1);
          // 清空缓存，强制刷新
          _overviewData = null;
          _statsData = null;
          _trendData = null;
          _memberData = null;
          _dateData = null;
        });
        _loadOverview();
        _loadStatistics();
        // 如果当前Tab需要加载数据，则加载
        if (_activeTab == 'trend') _loadTrend();
        if (_activeTab == 'member') _loadMember();
        if (_activeTab == 'date') _loadDate();
      }
    } else if (_period == 'week') {
      // 选择日期（用于计算周）
      final now = DateTime.now();
      DateTime tempDate = _selectedDate;
      
      // 确保选择日期不超过今天
      if (tempDate.isAfter(now)) {
        tempDate = now;
      }
      
      // 日期的年、月、日
      int selectedYear = tempDate.year;
      int selectedMonth = tempDate.month;
      int selectedDay = tempDate.day;
      
      // 年范围
      const int minYear = 2010;
      int maxYear = now.year;
      
      // 生成年份列表
      List<int> years = List.generate(maxYear - minYear + 1, (index) => minYear + index);
      
      final result = await showDialog<DateTime>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            backgroundColor: ThemeHelper.surface(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.selectDate,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedYear = now.year;
                              selectedMonth = now.month;
                              selectedDay = now.day;
                            });
                          },
                          child: Text(
                            AppLocalizations.of(context)!.today,
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeHelper.primary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 日期选择器
                  Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
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
                                selectedYear = years[index];
                                
                                // 计算该年月的最大天数
                                int maxDays = DateTime(selectedYear, selectedMonth + 1, 0).day;
                                
                                // 如果是当前年份，月份和日期不能超过今天
                                if (selectedYear == now.year) {
                                  if (selectedMonth > now.month) {
                                    selectedMonth = now.month;
                                    maxDays = DateTime(selectedYear, selectedMonth + 1, 0).day;
                                  }
                                  if (selectedMonth == now.month) {
                                    maxDays = now.day;
                                  }
                                }
                                
                                // 调整天数为有效值
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            scrollController: FixedExtentScrollController(
                              initialItem: years.indexOf(selectedYear).clamp(0, years.length - 1),
                            ),
                            children: years.map((year) => Center(
                              child: Text(
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
                                selectedMonth = index + 1;
                                
                                // 计算该年月的最大天数
                                int maxDays = DateTime(selectedYear, selectedMonth + 1, 0).day;
                                
                                // 如果是当前年月，日期不能超过今天
                                if (selectedYear == now.year && selectedMonth == now.month) {
                                  maxDays = now.day;
                                }
                                
                                // 调整天数为有效值
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            scrollController: FixedExtentScrollController(initialItem: selectedMonth - 1),
                            children: List.generate(12, (index) => Center(
                              child: Text(
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
                                selectedDay = index + 1;
                                
                                // 计算该年月的最大天数
                                int maxDays = DateTime(selectedYear, selectedMonth + 1, 0).day;
                                
                                // 如果是当前年月，日期不能超过今天
                                if (selectedYear == now.year && selectedMonth == now.month) {
                                  maxDays = now.day;
                                }
                                
                                // 确保选择的天数不超过最大值
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            scrollController: FixedExtentScrollController(initialItem: selectedDay - 1),
                            children: List.generate(31, (index) => Center(
                              child: Text(
                                '${index + 1}${AppLocalizations.of(context)!.dayLabel}',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 按钮栏
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            AppLocalizations.of(context)!.cancelButton,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, DateTime(selectedYear, selectedMonth, selectedDay));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeHelper.primary(context),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(AppLocalizations.of(context)!.confirmButton),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      
      if (result != null) {
        setState(() {
          _selectedDate = result;
          // 清空缓存，强制刷新
          _overviewData = null;
          _statsData = null;
          _trendData = null;
          _memberData = null;
          _dateData = null;
        });
        _loadOverview();
        _loadStatistics();
        // 如果当前Tab需要加载数据，则加载
        if (_activeTab == 'trend') _loadTrend();
        if (_activeTab == 'member') _loadMember();
        if (_activeTab == 'date') _loadDate();
      }
    } else {
      // 选择年月
      final result = await DatePickerHelper.showYearMonthPicker(
        context,
        initialYear: _selectedDate.year,
        initialMonth: _selectedDate.month,
      );
      if (result != null) {
        setState(() {
          _selectedDate = DateTime(result['year']!, result['month']!, 1);
          // 清空缓存，强制刷新
          _overviewData = null;
          _statsData = null;
          _trendData = null;
          _memberData = null;
          _dateData = null;
        });
        _loadOverview();
        _loadStatistics();
        // 如果当前Tab需要加载数据，则加载
        if (_activeTab == 'trend') _loadTrend();
        if (_activeTab == 'member') _loadMember();
        if (_activeTab == 'date') _loadDate();
      }
    }
  }
}
