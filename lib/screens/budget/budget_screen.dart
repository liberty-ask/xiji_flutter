import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api/budget_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetService _budgetService = BudgetService();
  final TextEditingController _amountController = TextEditingController();
  Map<String, dynamic>? _budgetData;
  bool _isLoading = true;
  bool _isSaving = false;
  final DateTime _currentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBudget();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadBudget() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _budgetService.getBudget(
        year: _currentDate.year,
        month: _currentDate.month,
      );
      setState(() {
        _budgetData = data;
        if (data['budget'] != null) {
          _amountController.text = (data['budget'] as num).toStringAsFixed(0);
        }
      });
    } catch (e) {
      setState(() {
        _budgetData = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveBudget() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseEnterValidAmount)),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _budgetService.setBudget(
        total: amount,
        year: _currentDate.year,
        month: _currentDate.month,
      );
      await _loadBudget();
      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.saveSuccessfully);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.changeFailed);
        CustomSnackBar.showError(context, errorMessage);
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.monthlyBudget),
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : SingleChildScrollView(
              padding: ResponsiveHelper.containerMargin(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 当前预算信息卡片
                  if (_budgetData != null) Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ThemeHelper.surfaceHighlight(context),
                          ThemeHelper.background(context),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScaledText(
                          '${DateFormat('yyyy${AppLocalizations.of(context)!.year}MM${AppLocalizations.of(context)!.month}').format(_currentDate)}${AppLocalizations.of(context)!.budget}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const ScaledText(
                              '¥',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            ScaledText(
                              '${_budgetData!['budget'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                AppLocalizations.of(context)!.expense,
                                '¥${_budgetData!['used'] ?? 0}',
                              ),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                AppLocalizations.of(context)!.net,
                                '¥${_budgetData!['remaining'] ?? 0}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: ((_budgetData!['percentage'] as num? ?? 0) / 100).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getBudgetProgressColor(_budgetData!),
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 设置预算
                  ScaledText(
                    AppLocalizations.of(context)!.monthlyBudget,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.amount,
                      prefixIcon: Icon(Icons.account_balance_wallet),
                      suffixText: '¥',
                      hintText: AppLocalizations.of(context)!.pleaseEnterAmount,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 快速设置按钮
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [3000, 5000, 8000, 10000, 15000, 20000].map((amount) {
                      return ElevatedButton(
                        onPressed: () {
                          _amountController.text = amount.toString();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeHelper.surface(context),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: ScaledText('¥${amount.toStringAsFixed(0)}'),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 32),

                  // 保存按钮
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveBudget,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ScaledText(AppLocalizations.of(context)!.save),
                  ),
                ],
              ),
            ),
    );
  }

  // Get budget progress color based on percentage
  Color _getBudgetProgressColor(Map<String, dynamic> budgetData) {
    final percentage = (budgetData['percentage'] as num? ?? 0).toDouble();
    
    // Return color based on percentage
    if (percentage > 100) {
      return ThemeHelper.expenseColor(context); // Red for over budget
    } else if (percentage > 80) {
      return Colors.orange; // Orange/Yellow for warning (80-100%)
    } else {
      return ThemeHelper.primary(context); // Primary color for normal (0-80%)
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScaledText(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        ScaledText(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

