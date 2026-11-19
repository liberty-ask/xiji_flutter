import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/local/db_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../services/api/transaction_service.dart';
import '../../widgets/custom/category_selector.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/constants.dart';
import '../../utils/date_picker_helper.dart';
import '../../screens/settings/backup_guidance.dart';
import '../../models/category.dart';
import '../../models/transaction.dart' as transaction_model;
import '../../l10n/app_localizations.dart';
import '../../l10n/category_l10n.dart';

/// 记一笔表单的预填参数：
/// - 语音记账解析无把握：带金额/类型/日期/备注预填，无 transactionId（新增）
/// - 语音记账直接入库后的「修改」入口：带 transactionId 进入编辑模式
class TransactionPrefill {
  final String? transactionId; // 非空 = 编辑既有交易
  final int? type; // 0-收入 1-支出
  final double? amount;
  final String? categoryId;
  final DateTime? date;
  final String? note;

  /// 语音识别原文：提交后回写学习表（source=1 语音记账），
  /// 下次说同一句话自动命中所选分类
  final String? voiceMatchText;

  const TransactionPrefill({
    this.transactionId,
    this.type,
    this.amount,
    this.categoryId,
    this.date,
    this.note,
    this.voiceMatchText,
  });
}

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key, this.prefill});

  final TransactionPrefill? prefill;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  transaction_model.TransactionType _transactionType =
      transaction_model.TransactionType.expense;
  Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 静态预填（金额/备注/类型/日期）不依赖分类列表，立即生效
    final f = widget.prefill;
    if (f != null) {
      if (f.type != null) {
        _transactionType = transaction_model.TransactionType.fromInt(f.type!);
      }
      if (f.amount != null) {
        _amountController.text = f.amount! % 1 == 0
            ? f.amount!.toStringAsFixed(0)
            : f.amount!.toString();
      }
      if (f.note != null) {
        _noteController.text = f.note!;
      }
      if (f.date != null) {
        _selectedDate = f.date!;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CategoryProvider>().loadCategories();
      // 分类预选依赖分类列表加载完成（按 ID 定位，禁止按名称匹配）
      if (!mounted || f?.categoryId == null) return;
      final provider = context.read<CategoryProvider>();
      final match = provider.categories.cast<Category?>().firstWhere(
            (c) => c!.id == f!.categoryId,
            orElse: () => null,
          );
      if (match != null) {
        setState(() {
          _selectedCategory = match;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final result = await DatePickerHelper.showYearMonthDayPicker(
      context,
      initialYear: _selectedDate.year,
      initialMonth: _selectedDate.month,
      initialDay: _selectedDate.day,
      startYear: AppConstants.datePickerFirstYear,
    );
    if (result != null) {
      setState(() {
        _selectedDate = DateTime(
          result['year']!,
          result['month']!,
          result['day']!,
        );
      });
    }
  }

  /// 备注编辑弹层：与页面共用同一个 controller，关闭后回填 chip 摘要
  Future<void> _editNote() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeHelper.surface(context),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.noteOptional,
                    prefixIcon: Icon(
                      Icons.note,
                      size: ResponsiveHelper.iconSize(context),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.confirm),
                ),
              ],
            ),
          ),
        );
      },
    );
    // 回到页面刷新备注 chip 摘要
    if (mounted) setState(() {});
  }

  /// 键盘态的分类 chip 点开：完整分类选择器（列数随宽度自适应、可滚动），
  /// 选中即关闭弹层并回填
  Future<void> _pickCategory() async {
    // 先收起金额输入的键盘，弹层不被顶到过窄
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CategoryProvider>();
    final direction =
        _transactionType == transaction_model.TransactionType.income ? 0 : 1;

    final picked = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeHelper.surface(context),
      builder: (sheetContext) {
        final horizontal = ResponsiveHelper.horizontalPadding(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ScaledText(
                    l10n.category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      // adaptiveLabels：列数随弹层宽度自适应、格子 1:1，
                      // 长英文名折两行，超出 60% 屏高时内部滚动
                      child: CategorySelector(
                        categories: provider.categories,
                        selectedCategory: _selectedCategory,
                        direction: direction,
                        usageCounts: provider.usageCounts,
                        adaptiveLabels: true,
                        onSelected: (c) => Navigator.of(sheetContext).pop(c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedCategory = picked;
      });
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategory == null) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.pleaseSelectCategory);
      return;
    }

    final editId = widget.prefill?.transactionId;
    final l10n = AppLocalizations.of(context)!;

    try {
      if (editId != null) {
        // 编辑模式（语音「修改」入口）：更新既有交易
        await TransactionService().updateTransaction(
          id: editId,
          type: _transactionType.toInt(),
          categoryId: _selectedCategory!.id,
          amount: double.parse(_amountController.text),
          date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          note: _noteController.text.isNotEmpty ? _noteController.text : null,
        );
      } else {
        final transactionProvider = context.read<TransactionProvider>();
        await transactionProvider.addTransaction(
          type: _transactionType.toInt(),
          categoryId: _selectedCategory!.id,
          amount: double.parse(_amountController.text),
          date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          note: _noteController.text.isNotEmpty ? _noteController.text : null,
        );
      }

      // 语音入口带入的识别原文：把本次所选分类回写学习表，
      // 下次说同一句话自动命中（source=1 语音记账）
      final matchText = widget.prefill?.voiceMatchText;
      if (matchText != null && matchText.isNotEmpty) {
        await Db.categoryRules.assign(
          matchText: matchText,
          categoryId: _selectedCategory!.id,
          source: 1,
        );
      }

      if (mounted) {
        CustomSnackBar.showSuccess(
          context,
          editId != null ? l10n.editSuccess : l10n.addSuccess,
        );
        if (editId == null) {
          // 首次记账后的云备份引导（仅一次，见 BackupGuidance）
          await BackupGuidance.maybeShowAfterFirstSave(context);
        }
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.resolveMessage(
          context,
          e,
          defaultMessage: editId != null ? l10n.editFailed : l10n.addFailed,
        );
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categoryProvider = context.watch<CategoryProvider>();
    final transactionProvider = context.watch<TransactionProvider>();

    final isEditing = widget.prefill?.transactionId != null;
    // 键盘弹起时分类区收成单个 chip，让金额、日期、备注、保存都落在键盘上方
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final horizontal = ResponsiveHelper.horizontalPadding(context);
    final selectedName = _selectedCategory == null
        ? null
        : CategoryL10n.ofModel(l10n, _selectedCategory!);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: ScaledText(
          isEditing ? l10n.editTransaction : l10n.addTransaction,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: _AdaptiveFormBody(
                  categoryCount: categoryProvider.categories.length,
                  children: [
                    // 收支切换：带文字与图标，放在内容区顶部，一眼可见可点
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                      child: _buildTypeSwitch(context, l10n),
                    ),

                    // 金额输入：置顶，键盘弹起时第一眼可见
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: l10n.amount,
                          prefixIcon: Icon(
                            Icons.attach_money,
                            size: ResponsiveHelper.iconSize(context),
                          ),
                          suffixText: l10n.currencySymbol,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.pleaseEnterAmount;
                          }
                          if (double.tryParse(value) == null) {
                            return l10n.pleaseEnterValidAmount;
                          }
                          if (double.parse(value) <= 0) {
                            return l10n.amountMustBeGreaterThanZero;
                          }
                          return null;
                        },
                      ),
                    ),

                    // 分类标题 + 已选分类回显（键盘态由 chip 自身承载，避免重复）
                    if (!keyboardVisible) ...[
                      Padding(
                        padding:
                            EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
                        child: Row(
                          children: [
                            ScaledText(
                              l10n.category,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (selectedName != null) ...[
                              const SizedBox(width: 8),
                              const Spacer(),
                              Flexible(
                                child: ScaledText(
                                  l10n.selectedCategory(selectedName),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ThemeHelper.primary(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 24),

                    if (keyboardVisible)
                      // 键盘态：分类收成单个 chip，点击弹出完整选择器
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: SizedBox(
                          key: const Key('categoryChip'),
                          height: 44,
                          child: _buildInfoChip(
                            context,
                            icon: Icons.category_outlined,
                            label: selectedName == null
                                ? l10n.category
                                : l10n.selectedCategory(selectedName),
                            onTap: _pickCategory,
                            trailingIcon: Icons.keyboard_arrow_down,
                          ),
                        ),
                      )
                    else if (categoryProvider.isLoading)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(
                              color: ThemeHelper.primary(context),
                            ),
                          ),
                        ),
                      )
                    else if (categoryProvider.error != null)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: Center(
                          child: Padding(
                            padding: ResponsiveHelper.cardPadding(context),
                            child: ScaledText(
                              l10n.loadCategoryFailed(
                                  categoryProvider.error ?? ''),
                              style: TextStyle(
                                color: ThemeHelper.expenseColor(context),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      // 一次铺开全部分类：列数随宽度自适应、格子接近正方形；
                      // 页面整体滚动，分类区不再自己滚动
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: CategorySelector(
                          categories: categoryProvider.categories,
                          selectedCategory: _selectedCategory,
                          direction: _transactionType ==
                                  transaction_model.TransactionType.income
                              ? 0
                              : 1,
                          usageCounts: categoryProvider.usageCounts,
                          adaptiveLabels: true,
                          onSelected: (category) {
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                        ),
                      ),

                    // 日期：独立一行，完整显示年月日，不省略
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
                      child: SizedBox(
                        key: const Key('dateChip'),
                        height: 44,
                        child: _buildInfoChip(
                          context,
                          icon: Icons.calendar_today,
                          label: l10n.date,
                          value:
                              DateFormat('yyyy-MM-dd').format(_selectedDate),
                          onTap: _selectDate,
                          trailingIcon: Icons.chevron_right,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 备注：独立一行，可见 20 字以上，超长省略、点开弹层查看编辑
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 16),
                      child: SizedBox(
                        key: const Key('noteChip'),
                        height: 44,
                        child: _buildInfoChip(
                          context,
                          icon: Icons.notes,
                          label: _noteController.text.isEmpty
                              ? l10n.addNote
                              // 多行备注压成单行摘要，避免 chip 内换行
                              : _noteController.text.replaceAll('\n', ' '),
                          onTap: _editNote,
                          trailingIcon: Icons.chevron_right,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 常驻底栏保存按钮：键盘弹起时仍贴在键盘上方
              Container(
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                // 大屏与正文同宽居中，按钮不被拉成整屏宽
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _AdaptiveFormBody.maxWidth),
                    child: ElevatedButton(
                      onPressed: transactionProvider.isLoading
                          ? null
                          : _submitTransaction,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: EdgeInsets.zero,
                      ),
                      child: transactionProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ScaledText(
                              l10n.confirmAdd,
                              style: ResponsiveHelper.responsiveTextStyle(context),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 收支切换：文字 + 图标的分段控件，明确可点；
  /// 英文文案偏长时用 FittedBox 等比缩小，不截断、不溢出
  Widget _buildTypeSwitch(BuildContext context, AppLocalizations l10n) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeHelper.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeOption(
              l10n.expense,
              transaction_model.TransactionType.expense,
              Icons.arrow_downward,
              ThemeHelper.expenseColor(context),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTypeOption(
              l10n.income,
              transaction_model.TransactionType.income,
              Icons.arrow_upward,
              ThemeHelper.primary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption(
    String label,
    transaction_model.TransactionType type,
    IconData icon,
    Color color,
  ) {
    final isSelected = _transactionType == type;
    final foreground = isSelected ? color : Colors.white70;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            setState(() {
              _transactionType = type;
              _selectedCategory = null; // 切换类型时清空分类选择
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 6),
                  ScaledText(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 日期 / 备注 / 键盘态分类的单行 chip
  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? value,
    required VoidCallback onTap,
    IconData? trailingIcon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: ThemeHelper.surface(context),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: ScaledText(
                  label,
                  style: ResponsiveHelper.responsiveTextStyle(
                    context,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                ),
              ),
              // 值优先展示：标签先让位，两段都可收缩，杜绝窄屏横向溢出
              if (value != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: ScaledText(
                    value,
                    style: ResponsiveHelper.responsiveTextStyle(
                      context,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 18, color: Colors.white54),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 记一笔正文的自适应容器：
/// - 小屏 / 横屏放不下时整页滚动，只用这一个滚动容器，不做嵌套滚动
/// - 大屏限制正文宽度并居中，表单不被横向拉宽
/// - 内容不足一屏时把余量摊到区块间距上（每段最多 +[_maxGapGrowth]），
///   再多的余量留在底部，既不拉高分类格，也不在内容中间挖空洞
class _AdaptiveFormBody extends StatelessWidget {
  const _AdaptiveFormBody({
    required this.children,
    required this.categoryCount,
  });

  final List<Widget> children;
  final int categoryCount;

  /// 正文最大宽度：宽于该值（平板 / 横屏）时居中留白
  static const double maxWidth = 560;

  /// 除分类网格外的固定高度合计（收支 44 + 金额 56 + 标题 30 + 日期 44 +
  /// 备注 44 + 各段间距），仅用于估算可摊余量，估小了只是少摊一点
  static const double _baseHeight = 324;

  /// 每个区块间距最多再多摊多少，避免超高屏把表单拉得过于稀疏
  static const double _maxGapGrowth = 24;

  /// 正文里可摊余量的区块间距个数
  static const int _gapCount = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = ResponsiveHelper.horizontalPadding(context);
        final contentWidth =
            math.min(constraints.maxWidth, maxWidth) - horizontal * 2;
        final isEnglish =
            Localizations.localeOf(context).languageCode == 'en';
        final columns =
            CategorySelector.columnsFor(contentWidth, isEnglish: isEnglish);
        final cellWidth =
            CategorySelector.cellWidthFor(contentWidth, columns);
        final rows = math.max(1, (categoryCount / columns).ceil());
        final gridHeight =
            rows * cellWidth + (rows - 1) * CategorySelector.spacing;
        final estimated = _baseHeight + gridHeight;

        return SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // 至少铺满一屏（或估算内容 + 可摊余量），余量交给 spaceBetween
                minHeight: math.min(
                  constraints.maxHeight,
                  estimated + _gapCount * _maxGapGrowth,
                ),
                maxWidth: maxWidth,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}
