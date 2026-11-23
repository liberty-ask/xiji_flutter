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
import '../../l10n/category_l10n.dart';
import '../../models/bill_platform.dart';
import '../../models/category.dart';
import '../../parser/bill_csv_parser.dart';
import '../../parser/bill_xlsx_parser.dart';
import '../../services/api/category_service.dart';
import '../../utils/error_helper.dart';
import '../../utils/page_error_helper.dart';
import '../../utils/icon_constants.dart';
import '../../utils/amount_format.dart';
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
/// （一个交易对方一张卡片、一个分类 chip 同时覆盖收入行与支出行，
///  type=2/退款关联行只能行级覆盖；批量指认回写学习表）→
/// 确认入库（tradeNo 去重、未分类兜底）→ 结果页。
enum ImportStep {
  platformList, // 选择平台
  preview, // 预览与批量指认
  result, // 导入结果
}

/// 预览分组：一个交易对方一张卡片。
/// 分类是中性标签，同一商户的收入行与支出行共用一个 chip；
/// type=2（不计收支）/退款关联行不参与批量写入，只能行级覆盖。
class BillPreviewGroup {
  const BillPreviewGroup(this.counterparty, this.items);

  final String counterparty;
  final List<BillImportPreviewItem> items;

  int get length => items.length;

  /// 批量指认范围：排除退款关联行（继承原支出分类）与 type=2 不计收支行
  List<BillImportPreviewItem> get assignable => [
        for (final i in items)
          if (!i.refundLinked && i.row.type != 2) i
      ];

  /// chip 展示的分类取批量指认范围内的第一条；全部不可指认时退回首条
  BillImportPreviewItem get representative =>
      assignable.isNotEmpty ? assignable.first : items.first;

  bool get hasUncategorized => items.any((i) => i.isUncategorized);

  /// 是否存在已指认（非未分类）的可指认行：决定卡片级撤销入口是否显示
  bool get hasAssigned => assignable.any((i) => !i.isUncategorized);
}

/// 按交易对方分组（保持账单内出现顺序，空交易对方置末）。
List<BillPreviewGroup> groupBillPreviewItems(
    List<BillImportPreviewItem> items) {
  final groups = <String, List<BillImportPreviewItem>>{};
  for (final item in items) {
    final key = (item.row.counterparty ?? '').trim();
    groups.putIfAbsent(key, () => []).add(item);
  }
  final empty = groups.remove('');
  if (empty != null) groups[''] = empty;
  return [
    for (final entry in groups.entries)
      BillPreviewGroup(entry.key, entry.value),
  ];
}

/// 卡片级撤销：该组可指认行全部置未分类（退款关联行与 type=2 天然不在范围内）
void resetGroupCategories(BillPreviewGroup group) {
  for (final item in group.assignable) {
    item.categoryId = BuiltinCategories.uncategorizedId;
  }
}

/// 全局撤销：所有可指认行置未分类；退款关联行与 type=2 保持原分类
void resetAllCategories(List<BillImportPreviewItem> items) {
  for (final item in items) {
    if (!item.refundLinked && item.row.type != 2) {
      item.categoryId = BuiltinCategories.uncategorizedId;
    }
  }
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
    // 注：name 为数据层默认标识（备份/恢复序列化用）；UI 展示一律走
    // _platformName 的 l10n 词条（platform.name 不直接进界面）
  ];

  BillImportService? _service; // 首次选文件时异步初始化（含规则库加载）
  List<Category> _categories = []; // 分类选择器数据
  Map<String, Category> _categoryById = {};
  Map<String, int> _usageCounts = {}; // 近 90 天使用频次（软排序提示）

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

  /// 平台名 l10n：展示层唯一入口，按 code 映射词条（fallback 用
  /// 数据层 name，防未知 code 空 tag）
  String _platformName(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context)!;
    switch (code) {
      case 'alipay':
        return l10n.platformAlipay;
      case 'wechat':
        return l10n.platformWechat;
      case 'jd':
        return l10n.platformJd;
      default:
        return code;
    }
  }

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
                    _platformName(context, platform.code),
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
        CustomSnackBar.showError(context, ErrorHelper.extractErrorMessage(e));
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
      final categoryService = CategoryService();
      final categories = await categoryService.getCategories();
      _categories = categories;
      _categoryById = {for (final c in categories) c.id: c};
      _usageCounts = await categoryService.getRecentUsageCounts();

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
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = PageErrorHelper.resolveLoadMessage(
            context,
            e,
            networkMessage: l10n.networkConnectionError,
            fallbackMessage: l10n.billParseFailed,
          );
          _isLoading = false;
        });
      }
    }
  }

  // ---------------- 预览与批量指认 ----------------

  /// 按交易对方分组（一个商户一张卡片，见 [groupBillPreviewItems]）
  List<BillPreviewGroup> get _groups => groupBillPreviewItems(_items);

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
                    _buildPreviewActions(),
                    SizedBox(height: ResponsiveHelper.spacing(context, small: 4)),
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
                      final group = _groups[index];
                      return _buildGroupCard(group);
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

  /// 预览页的两个全局入口：一键把本次预览置为未分类 / 清空学习表。
  /// 学习表是四层链路的第一层，指认错误会立即压制平台与关键词结果，
  /// 因此必须留一条清空后路；清空后当场重算本次预览。
  Widget _buildPreviewActions() {
    final l10n = AppLocalizations.of(context)!;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Colors.white.withValues(alpha: 0.7),
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 32),
    );
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: _resetAll,
            style: buttonStyle,
            icon: const Icon(Icons.layers_clear, size: 16),
            label: ScaledText(l10n.billResetAll),
          ),
          TextButton.icon(
            onPressed: _clearLearning,
            style: buttonStyle,
            icon: const Icon(Icons.delete_sweep, size: 16),
            label: ScaledText(l10n.billClearLearning),
          ),
        ],
      ),
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
              '${AppLocalizations.of(context)!.currencySymbol}${AmountFormat.format(parse.totalIncome)}',
              color: Colors.green,
              autoFit: true),
          _buildStatRow(
              '${AppLocalizations.of(context)!.expense}${AppLocalizations.of(context)!.total}',
              '${AppLocalizations.of(context)!.currencySymbol}${AmountFormat.format(parse.totalExpense)}',
              color: ThemeHelper.expenseColor(context),
              autoFit: true),
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

  /// 分组卡片：一个商户一张卡片，一个 chip 同时覆盖该商户的收入行与支出行
  Widget _buildGroupCard(BillPreviewGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelper.surfaceDark(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: group.hasUncategorized
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupHeader(
            group.counterparty,
            group.length,
            chip: _buildGroupChip(group),
            onUndo: group.hasAssigned ? () => _resetGroup(group) : null,
          ),
          const SizedBox(height: 8),
          ...group.items.map((item) => _buildGroupItemRow(group, item)),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String counterparty, int count,
      {Widget? chip, VoidCallback? onUndo}) {
    return Row(
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
          AppLocalizations.of(context)!.billGroupCount(count),
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        if (onUndo != null)
          IconButton(
            onPressed: onUndo,
            tooltip: AppLocalizations.of(context)!.billResetGroup,
            icon: const Icon(Icons.undo, size: 18),
            color: Colors.white54,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        if (chip != null) ...[
          const SizedBox(width: 8),
          chip,
        ],
      ],
    );
  }

  /// 商户分类 chip：一个 chip 同时覆盖该商户收入行与支出行；
  /// 退款关联行与 type=2 不计收支行不参与批量指认
  Widget _buildGroupChip(BillPreviewGroup group) {
    final category = _categoryById[group.representative.categoryId];
    final canAssign =
        group.counterparty.isNotEmpty && group.assignable.isNotEmpty;
    return _buildCategoryChip(category, canAssign,
        () => _assignGroupCategory(group));
  }

  Widget _buildCategoryChip(
      Category? category, bool canAssign, VoidCallback onTap) {
    final isUncategorized =
        category != null && category.id == BuiltinCategories.uncategorizedId;
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
              category == null
                  ? AppLocalizations.of(context)!.unknown
                  : CategoryL10n.ofModel(AppLocalizations.of(context)!, category),
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

  /// 行级展示：次要入口——点单行可只覆盖这一行的分类
  /// （type=2 不计收支行只能走这里单独指认）
  Widget _buildGroupItemRow(
      BillPreviewGroup group, BillImportPreviewItem item) {
    final dateFormat = DateFormat('MM-dd HH:mm');
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => _assignItemCategory(group, item),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
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
            if (item.row.type == 0) ...[
              const SizedBox(width: 6),
              _buildSideBadge(l10n.income, Colors.green),
            ] else if (item.row.type == 2) ...[
              const SizedBox(width: 6),
              _buildSideBadge(l10n.noCount, Colors.white54),
            ],
            if (item.duplicate) ...[
              const SizedBox(width: 6),
              ScaledText(
                l10n.billDuplicateSkip,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],
            if (item.refundLinked) ...[
              const SizedBox(width: 6),
              ScaledText(
                l10n.noCount,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
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
              '${l10n.currencySymbol}${AmountFormat.format(item.row.amount)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: item.refundLinked
                    ? Colors.white.withValues(alpha: 0.7)
                    : item.row.type == 0
                        ? Colors.green
                        : item.row.type == 2
                            ? Colors.white54
                            : ThemeHelper.expenseColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ScaledText(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  /// 批量指认：一个 chip 同时写该商户的收入行与支出行
  /// （type=2 与退款关联行不参与），并回写学习表。
  /// 学习表只有 matchText 单键，分类中性化后同一商户收支共用分类，
  /// 不再存在「写一侧污染另一侧」的问题。
  Future<void> _assignGroupCategory(BillPreviewGroup group) async {
    final counterparty = group.counterparty;
    if (counterparty.isEmpty) return;
    final targets = group.assignable;
    if (targets.isEmpty) return;

    final selected = await _pickCategory(
      title: counterparty,
      currentCategoryId: targets.first.categoryId,
      direction: targets.first.row.type == 0 ? 0 : 1,
    );
    if (selected == null || !mounted) return;

    // 指认前快照：同一商户本轮预填若已跨多个分类，服务层会跳过学习表写入
    final roundCategories = <String>{
      for (final item in targets) item.categoryId,
    };
    for (final item in targets) {
      item.categoryId = selected.id;
    }
    await _service?.assignCategory(
      counterparty: counterparty,
      categoryId: selected.id,
      roundCategories: roundCategories,
    );

    setState(() {});
  }

  /// 行级覆盖（次要入口）：只改这一条，不写学习表、不影响同商户其他行
  Future<void> _assignItemCategory(
      BillPreviewGroup group, BillImportPreviewItem item) async {
    final selected = await _pickCategory(
      title: group.counterparty,
      currentCategoryId: item.categoryId,
      direction: item.row.type == 0 ? 0 : 1,
    );
    if (selected == null || !mounted) return;
    setState(() {
      item.categoryId = selected.id;
    });
  }

  /// 卡片级撤销：该组可指认行全部置未分类（不写学习表，只影响本次预览）
  void _resetGroup(BillPreviewGroup group) {
    if (group.assignable.isEmpty) return;
    setState(() => resetGroupCategories(group));
  }

  /// 全局撤销：本次预览所有可指认行置未分类（退款关联行与 type=2 不动）
  Future<void> _resetAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _showConfirm(
      title: l10n.billResetAll,
      message: l10n.billResetAllConfirm,
    );
    if (confirmed != true || !mounted) return;
    setState(() => resetAllCategories(_items));
  }

  /// 清空学习表并当场重算本次预览：
  /// 学习表指认错误会压制平台分类与关键词，必须有这条后路。
  Future<void> _clearLearning() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _showConfirm(
      title: l10n.billClearLearning,
      message: l10n.billClearLearningConfirm,
    );
    if (confirmed != true || !mounted) return;

    final service = _service;
    final rows = _parseResult?.rows;
    if (service == null || rows == null) return;

    setState(() => _isLoading = true);
    try {
      final count = await service.clearLearningTable();
      final refreshed = await service.prepare(rows);
      if (!mounted) return;
      setState(() {
        _items = refreshed;
        _isLoading = false;
      });
      CustomSnackBar.showSuccess(context, l10n.billLearningCleared(count));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      CustomSnackBar.showError(context, ErrorHelper.extractErrorMessage(e));
    }
  }

  Future<bool?> _showConfirm({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: ScaledText(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: ScaledText(
          message,
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
            child: ScaledText(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  Future<Category?> _pickCategory({
    required String title,
    required String currentCategoryId,
    required int direction,
  }) {
    return showModalBottomSheet<Category>(
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
                '${AppLocalizations.of(context)!.selectCategory} · $title',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              CategorySelector(
                categories: _categories,
                selectedCategory: _categoryById[currentCategoryId],
                direction: direction,
                usageCounts: _usageCounts,
                onSelected: (c) => Navigator.of(context).pop(c),
              ),
            ],
          ),
        ),
      ),
    );
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
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = PageErrorHelper.resolveLoadMessage(
            context,
            e,
            networkMessage: l10n.networkConnectionError,
            fallbackMessage: l10n.importFailed,
          );
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

  Widget _buildStatRow(String label, String value, {Color? color, bool autoFit = false}) {
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
          if (autoFit)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: ScaledText(
                  value,
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    fontWeight: FontWeight.bold,
                    color: color ?? Colors.white,
                  ),
                  maxLines: 1,
                ),
              ),
            )
          else
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
