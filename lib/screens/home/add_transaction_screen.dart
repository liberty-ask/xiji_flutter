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

  /// 键盘态的分类 chip 点开：完整分类选择器（6 列全量铺开、可滚动），
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
                      // 不传 rowsPerPage：6 列全量铺开、可滚动；
                      // adaptiveLabels 让长英文名按语言自适应列数并折两行
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
    // 键盘弹起时分类区收成 1 行，让金额、分类、保存都落在键盘上方
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
        actions: [
          _buildTypeAction(
            l10n.expense,
            transaction_model.TransactionType.expense,
            Icons.arrow_downward,
            ThemeHelper.expenseColor(context),
          ),
          _buildTypeAction(
            l10n.income,
            transaction_model.TransactionType.income,
            Icons.arrow_upward,
            ThemeHelper.primary(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    16,
                    horizontal,
                    keyboardVisible ? 8 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 金额输入：置顶，键盘弹起时第一眼可见
                      TextFormField(
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

                      const SizedBox(height: 24),

                      if (keyboardVisible)
                        // 键盘态：分类收成单个 chip，点击弹出完整选择器
                        SizedBox(
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
                        )
                      else ...[
                        // 分类标题 + 已选分类回显
                        SizedBox(
                          height: 20,
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

                        if (categoryProvider.isLoading)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(
                                color: ThemeHelper.primary(context),
                              ),
                            ),
                          )
                        else if (categoryProvider.error != null)
                          Center(
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
                          )
                        else
                          CategorySelector(
                            categories: categoryProvider.categories,
                            selectedCategory: _selectedCategory,
                            direction: _transactionType ==
                                    transaction_model.TransactionType.income
                                ? 0
                                : 1,
                            usageCounts: categoryProvider.usageCounts,
                            // 3 行 × 6 列/页，带页码点
                            rowsPerPage: 3,
                            onSelected: (category) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                          ),
                      ],

                      const SizedBox(height: 24),

                      // 日期与备注收成同行 chip
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 115,
                              child: _buildInfoChip(
                                context,
                                icon: Icons.calendar_today,
                                label: l10n.date,
                                value: DateFormat('yyyy-MM-dd')
                                    .format(_selectedDate),
                                onTap: _selectDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 100,
                              child: _buildInfoChip(
                                context,
                                icon: Icons.note,
                                label: _noteController.text.isEmpty
                                    ? l10n.addNote
                                    : _noteController.text,
                                onTap: _editNote,
                                trailingIcon: Icons.chevron_right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 顶栏的类型切换：图标常驻，Tooltip 与语义标签补齐可读性
  Widget _buildTypeAction(
    String label,
    transaction_model.TransactionType type,
    IconData icon,
    Color color,
  ) {
    final isSelected = _transactionType == type;

    return Center(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          // 外层 Semantics 已提供可读标签，避免读屏重复播报
          excludeFromSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _transactionType = type;
                _selectedCategory = null; // 切换类型时清空分类选择
              });
            },
            child: Container(
              width: 42,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isSelected
                    ? color.withValues(alpha: 0.2)
                    : Colors.transparent,
              ),
              child: Icon(
                icon,
                size: 18,
                color: isSelected ? color : Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 日期 / 备注的并排 chip
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
