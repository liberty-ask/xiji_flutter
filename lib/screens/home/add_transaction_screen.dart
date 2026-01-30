import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../widgets/custom/category_selector.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/constants.dart';
import '../../utils/date_picker_helper.dart';
import '../../models/category.dart';
import '../../models/transaction.dart' as transaction_model;
import '../../l10n/app_localizations.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
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

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategory == null) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.pleaseSelectCategory);
      return;
    }

    try {
      final transactionProvider = context.read<TransactionProvider>();
      final result = await transactionProvider.addTransaction(
        type: _transactionType.toInt(),
        category: _selectedCategory!.name,
        amount: double.parse(_amountController.text),
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        note: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      if (mounted) {
        final resultMessage = result['message'] as String? ?? AppLocalizations.of(context)!.addSuccess;
        CustomSnackBar.showSuccess(context, resultMessage);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.addFailed);
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final transactionProvider = context.watch<TransactionProvider>();

    final categories = _transactionType == transaction_model.TransactionType.expense
        ? categoryProvider.expenseCategories
        : categoryProvider.incomeCategories;

    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.addTransaction),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: ResponsiveHelper.containerMargin(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 交易类型选择
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: ThemeHelper.surface(context),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTypeButton(
                          AppLocalizations.of(context)!.expense,
                          transaction_model.TransactionType.expense,
                          Icons.arrow_downward,
                          ThemeHelper.expenseColor(context),
                        ),
                      ),
                      Expanded(
                        child: _buildTypeButton(
                          AppLocalizations.of(context)!.income,
                          transaction_model.TransactionType.income,
                          Icons.arrow_upward,
                          ThemeHelper.primary(context),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),


                // 金额输入
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.amount,
                    prefixIcon: Icon(Icons.attach_money, size: ResponsiveHelper.iconSize(context)),
                    suffixText: '¥',
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

                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),

                // 分类选择
                ScaledText(
                  AppLocalizations.of(context)!.selectCategory,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, small: 8, normal: 12, large: 16)),

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
                        AppLocalizations.of(context)!.loadCategoryFailed(categoryProvider.error ?? ''),
                        style: TextStyle(color: ThemeHelper.expenseColor(context)),
                      ),
                    ),
                  )
                else
                  CategorySelector(
                    categories: categories,
                    selectedCategory: _selectedCategory,
                    onSelected: (category) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    },
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),

                // 日期选择
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ThemeHelper.surface(context),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.white70, size: ResponsiveHelper.iconSize(context)),
                        SizedBox(width: ResponsiveHelper.spacing(context)),
                        ScaledText(
                          AppLocalizations.of(context)!.date,
                          style: ResponsiveHelper.responsiveTextStyle(context, color: Colors.white70),
                        ),
                        const Spacer(),
                        ScaledText(
                          DateFormat('yyyy-MM-dd').format(_selectedDate),
                          style: ResponsiveHelper.responsiveTextStyle(
                            context,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
                        Icon(Icons.chevron_right, color: Colors.white54, size: ResponsiveHelper.iconSize(context)),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),

                // 备注输入
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.noteOptional,
                    prefixIcon: Icon(Icons.note, size: ResponsiveHelper.iconSize(context)),
                  ),
                  maxLines: 3,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, small: 32, normal: 40, large: 48)),

                // 提交按钮
                ElevatedButton(
                  onPressed: transactionProvider.isLoading ? null : _submitTransaction,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.buttonPadding(context).horizontal,
                      vertical: ResponsiveHelper.spacing(context, small: 12, normal: 16, large: 20),
                    ),
                  ),
                  child: transactionProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ScaledText(
                          AppLocalizations.of(context)!.confirmAdd,
                          style: ResponsiveHelper.responsiveTextStyle(context),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton(
    String label,
    transaction_model.TransactionType type,
    IconData icon,
    Color color,
  ) {
    final isSelected = _transactionType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _transactionType = type;
          _selectedCategory = null; // 切换类型时清空分类选择
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            ScaledText(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

