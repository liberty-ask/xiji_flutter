import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/local/bill_import_service.dart';
import '../../data/local/builtin_categories.dart';
import '../../l10n/app_localizations.dart';
import '../../models/bill_platform.dart';
import '../../models/category.dart';
import '../../parser/bill_csv_parser.dart';
import '../../parser/bill_xlsx_parser.dart';
import '../../services/api/category_service.dart';
import '../../utils/icon_constants.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/scaled_text.dart';
import '../../widgets/custom/category_selector.dart';

/// 账单导入页（本地优先：全程离线，无网络请求）。
///
/// 流程：选平台卡 → 选文件（支付宝/京东 CSV，微信 XLSX）→ 本地解析
/// （GBK/UTF-8/xlsx）→ 预览
/// （按交易对方分组、点击组分类批量指认、指认回写学习表）→ 确认入库
/// （tradeNo 去重、未分类兜底）→ 结果页。
enum ImportStep {
  platformList, // 选择平台
  preview, // 预览与批量指认
  result, // 导入结果
}

class ImportBillsScreen extends StatefulWidget {
  const ImportBillsScreen({super.key});

  @override
  State<ImportBillsScreen> createState() => _ImportBillsScreenState();
}

class _ImportBillsScreenState extends State<ImportBillsScreen> {
  // 本地静态平台列表（原服务端 getSupportedPlatforms 退役；微信官方邮箱导出
  // 仅 XLSX，支付宝/京东官方导出为 CSV）
  static final _platforms = [
    BillPlatform(code: 'alipay', name: '支付宝', supportedFormats: ['csv']),
    BillPlatform(code: 'wechat', name: '微信', supportedFormats: ['xlsx']),
    BillPlatform(code: 'jd', name: '京东', supportedFormats: ['csv']),
  ];

  BillImportService? _service; // 首次选文件时异步初始化（含规则库加载）
  List<Category> _categories = []; // 分类选择器数据
  Map<String, Category> _categoryById = {};

  ImportStep _currentStep = ImportStep.platformList;
  bool _isLoading = false;
  String? _error;

  BillParseResult? _parseResult; // 解析统计与异常行
  List<BillImportPreviewItem> _items = []; // 预览条目（含分类预填）
  BillImportOutcome? _outcome; // 导入结果

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.billImport),
        actions: _currentStep != ImportStep.platformList
            ? [
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(
                    overlayColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                  ),
                  child: ScaledText(AppLocalizations.of(context)!.retry),
                ),
              ]
            : null,
      ),
      body: SafeArea(child: _buildContent()),
    );
  }

  void _reset() {
    setState(() {
      _currentStep = ImportStep.platformList;
      _parseResult = null;
      _items = [];
      _outcome = null;
      _error = null;
    });
  }

  Widget _buildContent() {
    if (_isLoading) {
      return LoadingIndicator(message: AppLocalizations.of(context)!.loading);
    }
    if (_error != null) {
      return _buildErrorView();
    }
    switch (_currentStep) {
      case ImportStep.platformList:
        return _buildPlatformList();
      case ImportStep.preview:
        return _buildPreviewView();
      case ImportStep.result:
        return _buildResultView();
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.containerMargin(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: ThemeHelper.expenseColor(context),
            ),
            const SizedBox(height: 16),
            ScaledText(
              AppLocalizations.of(context)!.error,
              style: ResponsiveHelper.responsiveTitleStyle(context),
            ),
            const SizedBox(height: 8),
            ScaledText(
              _error ?? AppLocalizations.of(context)!.unknown,
              style: ResponsiveHelper.responsiveTextStyle(
                context,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _reset,
              style: ElevatedButton.styleFrom(
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
              ),
              child: ScaledText(AppLocalizations.of(context)!.back),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 平台选择 ----------------

  Widget _buildPlatformList() {
    return SingleChildScrollView(
      padding: ResponsiveHelper.containerMargin(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 24, normal: 32, large: 40)),
          ScaledText(
            AppLocalizations.of(context)!.billImport,
            style: ResponsiveHelper.responsiveTitleStyle(
              context,
              color: Colors.white,
            ),
          ),
          SizedBox(
              height: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
          ScaledText(
            AppLocalizations.of(context)!.billImportSubtitle,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 32, normal: 48, large: 56)),
          ..._platforms.map((platform) => Padding(
                padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context),
                ),
                child: _buildPlatformCard(platform),
              )),
        ],
      ),
    );
  }

  Widget _buildPlatformCard(BillPlatform platform) {
    return InkWell(
      onTap: () => _selectFile(platform),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeHelper.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                platform.code == 'wechat'
                    ? Icons.wechat
                    : Icons.account_balance_wallet,
                color: ThemeHelper.primary(context),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScaledText(
                    platform.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ScaledText(
                    '${AppLocalizations.of(context)!.supportedFormats}${platform.supportedFormats.join(', ').toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  // ---------------- 文件选择与本地解析 ----------------

  Future<void> _selectFile(BillPlatform platform) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: platform.supportedFormats, // 微信 xlsx，其余 csv
        withData: true, // 直接读 bytes，规避移动端 path 访问差异
      );
      final files = result?.files;
      if (files == null || files.isEmpty) return; // 用户取消

      final file = files.single;
      Uint8List bytes;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        bytes = file.bytes!;
      } else if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw Exception(l10n.cannotGetFileData);
      }

      await _parseAndPrepare(bytes);
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString();
        if (errorStr.contains('User cancelled') || errorStr.contains('取消')) {
          return;
        }
        CustomSnackBar.showError(
            context, errorStr.replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _parseAndPrepare(Uint8List bytes) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. 本地解析：xlsx 为 zip 容器（PK 魔数）→ 微信账单 xlsx 解析，
      //    其余按 CSV 解析（自动识别平台与编码）
      final isXlsx = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
      final parsed = isXlsx
          ? BillXlsxParser().parse(bytes)
          : BillCsvParser().parse(bytes);
      if (parsed == null) {
        throw Exception(AppLocalizations.of(context)!.billParseFailed);
      }
      if (parsed.rows.isEmpty) {
        final l10n = AppLocalizations.of(context)!;
        if (parsed.errors.isEmpty) {
          // 平台与表头已识别成功，仅账单内无交易记录——与「文件无法识别」区分
          throw Exception(l10n.billNoTransactions(parsed.platform));
        }
        if (parsed.errors.any((e) => e.row == 0)) {
          // row==0 为表头级错误
          throw Exception(l10n.billHeaderUnrecognized);
        }
        throw Exception(l10n.billRowsUnparsed(parsed.errors.length));
      }

      // 2. 初始化服务（含内置规则库加载）与分类缓存
      _service ??= await BillImportService.instance();
      final categories = await CategoryService().getCategories();
      _categories = categories;
      _categoryById = {for (final c in categories) c.id: c};

      // 3. 分类预填 + 重复单号标记
      final items = await _service!.prepare(parsed.rows);

      if (!mounted) return;
      setState(() {
        _parseResult = parsed;
        _items = items;
        _isLoading = false;
        _currentStep = ImportStep.preview;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // ---------------- 预览与批量指认 ----------------

  /// 按交易对方分组（保持账单内出现顺序）；无交易对方的行归入空组末尾
  Map<String, List<BillImportPreviewItem>> get _groups {
    final groups = <String, List<BillImportPreviewItem>>{};
    for (final item in _items) {
      final key = (item.row.counterparty ?? '').trim();
      groups.putIfAbsent(key, () => []).add(item);
    }
    // 空交易对方组挪到最后
    final empty = groups.remove('');
    if (empty != null) groups[''] = empty;
    return groups;
  }

  /// 组内主导分类类型（0/1）：按条目数计，type=2 归支出侧；未知类型不计
  int? _majorTypeOf(List<BillImportPreviewItem> items) {
    final counts = <int, int>{};
    for (final item in items) {
      final type = item.row.type;
      if (type == null) continue;
      final side = type == 0 ? 0 : 1;
      counts[side] = (counts[side] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  Widget _buildPreviewView() {
    final parse = _parseResult!;
    final padding = ResponsiveHelper.containerMargin(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildParseSummaryCard(parse),
                    if (parse.errors.isNotEmpty)
                      _buildParseErrorsCard(parse),
                    SizedBox(height: ResponsiveHelper.spacing(context)),
                    ScaledText(
                      AppLocalizations.of(context)!.billAssignHint,
                      style: ResponsiveHelper.responsiveTextStyle(
                        context,
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context)),
                  ]),
                ),
              ),
              SliverPadding(
                padding: padding.copyWith(top: 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = _groups.entries.elementAt(index);
                      return _buildGroupCard(
                          entry.key, entry.value, entry.value.first);
                    },
                    childCount: _groups.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                    height: ResponsiveHelper.spacing(context,
                        small: 16, normal: 24)),
              ),
            ],
          ),
        ),
        Padding(
          padding: padding.copyWith(top: 8),
          child: ElevatedButton(
            onPressed: _confirmImport,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: ThemeHelper.primary(context),
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: ScaledText(
              AppLocalizations.of(context)!.confirmImport,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParseSummaryCard(BillParseResult parse) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: ThemeHelper.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScaledText(
            AppLocalizations.of(context)!.successfullySaved,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatRow(AppLocalizations.of(context)!.platform, parse.platform),
          _buildStatRow(
              AppLocalizations.of(context)!.total, '${parse.totalCount}'),
          _buildStatRow(
              '${AppLocalizations.of(context)!.income}${AppLocalizations.of(context)!.total}',
              '${AppLocalizations.of(context)!.currencySymbol}${parse.totalIncome.toStringAsFixed(2)}',
              color: Colors.green),
          _buildStatRow(
              '${AppLocalizations.of(context)!.expense}${AppLocalizations.of(context)!.total}',
              '${AppLocalizations.of(context)!.currencySymbol}${parse.totalExpense.toStringAsFixed(2)}',
              color: ThemeHelper.expenseColor(context)),
          if (parse.errors.isNotEmpty)
            _buildStatRow(AppLocalizations.of(context)!.fail,
                '${parse.errors.length}',
                color: ThemeHelper.expenseColor(context)),
          if (parse.startDate != null && parse.endDate != null)
            _buildStatRow(
              AppLocalizations.of(context)!.date,
              '${dateFormat.format(parse.startDate!)} ${AppLocalizations.of(context)!.to} ${dateFormat.format(parse.endDate!)}',
            ),
        ],
      ),
    );
  }

  Widget _buildParseErrorsCard(BillParseResult parse) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: ThemeHelper.expenseColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: ThemeHelper.expenseColor(context),
                size: 20,
              ),
              const SizedBox(width: 8),
              ScaledText(
                '${AppLocalizations.of(context)!.fail} (${parse.errors.length}${AppLocalizations.of(context)!.transactions})',
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  fontWeight: FontWeight.bold,
                  color: ThemeHelper.expenseColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...parse.errors.take(5).map((error) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ScaledText(
                  '${AppLocalizations.of(context)!.row} ${error.row}: ${error.reason}',
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// 分组卡片：组头（交易对方 + 分类 chip 批量指认入口）+ 组内条目
  Widget _buildGroupCard(
      String counterparty, List<BillImportPreviewItem> groupItems,
      BillImportPreviewItem first) {
    final category = _categoryById[first.categoryId];
    final isUncategorized = groupItems.any((i) => i.isUncategorized);
    final canAssign =
        counterparty.isNotEmpty && _majorTypeOf(groupItems) != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelper.surfaceDark(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUncategorized
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头：交易对方 + 分类 chip
          Row(
            children: [
              Expanded(
                child: ScaledText(
                  counterparty.isNotEmpty
                      ? counterparty
                      : AppLocalizations.of(context)!.unknown,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ScaledText(
                AppLocalizations.of(context)!
                    .billGroupCount(groupItems.length),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(category, canAssign,
                  () => _assignGroupCategory(counterparty, groupItems)),
            ],
          ),
          const SizedBox(height: 8),
          // 组内条目
          ...groupItems.map(_buildGroupItemRow),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(
      Category? category, bool canAssign, VoidCallback onTap) {
    final isUncategorized = category != null &&
        (category.id == BuiltinCategories.uncategorizedExpenseId ||
            category.id == BuiltinCategories.uncategorizedIncomeId);
    return InkWell(
      onTap: canAssign ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (isUncategorized ? Colors.orange : ThemeHelper.primary(context))
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isUncategorized
                    ? Colors.orange
                    : ThemeHelper.primary(context))
                .withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconConstants.getIconFromString(category?.icon ?? 'category'),
              size: 14,
              color: isUncategorized ? Colors.orange : Colors.white70,
            ),
            const SizedBox(width: 4),
            ScaledText(
              category?.name ?? AppLocalizations.of(context)!.unknown,
              style: TextStyle(
                fontSize: 12,
                color: isUncategorized ? Colors.orange : Colors.white,
              ),
            ),
            if (canAssign) ...[
              const SizedBox(width: 2),
              const Icon(
                Icons.expand_more,
                size: 14,
                color: Colors.white54,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItemRow(BillImportPreviewItem item) {
    final dateFormat = DateFormat('MM-dd HH:mm');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ScaledText(
              item.row.description ?? '',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.duplicate) ...[
            const SizedBox(width: 6),
            ScaledText(
              AppLocalizations.of(context)!.billDuplicateSkip,
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ],
          const SizedBox(width: 6),
          ScaledText(
            dateFormat.format(item.row.date),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          ScaledText(
            '${AppLocalizations.of(context)!.currencySymbol}${item.row.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: item.row.type == 0
                  ? Colors.green
                  : ThemeHelper.expenseColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 批量指认：弹分类选择器 → 组内主导类型的条目统一改分类 → 回写学习表
  Future<void> _assignGroupCategory(
      String counterparty, List<BillImportPreviewItem> groupItems) async {
    final majorType = _majorTypeOf(groupItems);
    if (majorType == null || counterparty.isEmpty) return;

    final candidates =
        _categories.where((c) => c.type == majorType).toList();
    final currentId = groupItems.first.categoryId;
    final selected = await showModalBottomSheet<Category>(
      context: context,
      backgroundColor: ThemeHelper.surfaceDark(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScaledText(
                '${AppLocalizations.of(context)!.selectCategory} · $counterparty',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              CategorySelector(
                categories: candidates,
                selectedCategory: _categoryById[currentId],
                onSelected: (c) => Navigator.of(context).pop(c),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    // 组内主导类型条目统一改分类（type=2 沿用支出侧，对齐服务端语义）
    for (final item in groupItems) {
      final type = item.row.type;
      if (type == null) continue;
      final side = type == 0 ? 0 : 1;
      if (side == majorType) item.categoryId = selected.id;
    }

    // 指认回写学习表：下次同商户自动命中
    await _service?.assignCategory(
      counterparty: counterparty,
      categoryId: selected.id,
    );

    setState(() {});
  }

  // ---------------- 确认导入与结果 ----------------

  Future<void> _confirmImport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final outcome = await _service!.importRows(_items);
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _isLoading = false;
        _currentStep = ImportStep.result;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildResultView() {
    final outcome = _outcome!;
    return SingleChildScrollView(
      padding: ResponsiveHelper.containerMargin(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 32, normal: 48)),
          const Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green,
          ),
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 16, normal: 24)),
          ScaledText(
            AppLocalizations.of(context)!.importCompleted,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 32, normal: 48)),
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: ThemeHelper.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScaledText(
                  AppLocalizations.of(context)!.importResult,
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatRow(AppLocalizations.of(context)!.totalRecords,
                    '${outcome.totalCount}'),
                _buildStatRow(
                    AppLocalizations.of(context)!.successfullyImported,
                    '${outcome.successCount}',
                    color: Colors.green),
                if (outcome.skipCount > 0)
                  _buildStatRow(AppLocalizations.of(context)!.skippedDuplicate,
                      '${outcome.skipCount}',
                      color: Colors.orange),
                if (outcome.failCount > 0)
                  _buildStatRow(AppLocalizations.of(context)!.fail,
                      '${outcome.failCount}',
                      color: ThemeHelper.expenseColor(context)),
              ],
            ),
          ),
          SizedBox(
              height: ResponsiveHelper.spacing(context,
                  small: 24, normal: 32)),
          if (outcome.failures.isNotEmpty)
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color:
                        ThemeHelper.expenseColor(context).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScaledText(
                    '${AppLocalizations.of(context)!.importFailedReason} (${outcome.failures.length}${AppLocalizations.of(context)!.items})',
                    style: ResponsiveHelper.responsiveTextStyle(
                      context,
                      fontWeight: FontWeight.bold,
                      color: ThemeHelper.expenseColor(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...outcome.failures.take(10).map((reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ScaledText(
                          reason,
                          style: ResponsiveHelper.responsiveTextStyle(
                            context,
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      )),
                ],
              ),
            ),
          SizedBox(
              height: ResponsiveHelper.spacing(context, small: 24, normal: 32)),
          ElevatedButton(
            onPressed: () => context.pushReplacement('/home'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: ThemeHelper.primary(context),
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: ScaledText(
              AppLocalizations.of(context)!.viewTransactions,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context)),
          TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: ScaledText(AppLocalizations.of(context)!.continueImport),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ScaledText(
            label,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              color: Colors.white70,
            ),
          ),
          ScaledText(
            value,
            style: ResponsiveHelper.responsiveTextStyle(
              context,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
