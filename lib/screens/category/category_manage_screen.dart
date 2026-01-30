import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api/category_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../utils/icon_constants.dart';
import '../../models/category.dart';
import '../../models/user.dart';
import '../../l10n/app_localizations.dart';

class CategoryManageScreen extends StatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  State<CategoryManageScreen> createState() => _CategoryManageScreenState();
}

class _CategoryManageScreenState extends State<CategoryManageScreen> {
  final CategoryService _categoryService = CategoryService();
  late String _activeTab; // '支出', '收入'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activeTab = AppLocalizations.of(context)!.expense;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  bool get _isAdmin {
    final user = context.read<AuthProvider>().user;
    return UserRole.isAdmin(user?.role);
  }

  Future<void> _refreshCategories() async {
    await context.read<CategoryProvider>().loadCategories();
  }

  Future<void> _deleteCategory(Category category) async {
    if (!_isAdmin) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeHelper.surface(context),
        title: ScaledText(
          AppLocalizations.of(context)!.confirmDelete,
          style: TextStyle(color: Colors.white),
        ),
        content: ScaledText(
          AppLocalizations.of(context)!.confirmDeleteCategoryMessage(category.name),
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
        await _categoryService.deleteCategory(category.id);
        await _refreshCategories();
        if (mounted) {
          CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.deleteSuccess);
        }
      } catch (e) {
        if (mounted) {
          final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.deleteFailed);
          CustomSnackBar.showError(context, errorMessage);
        }
      }
    }
  }

  Future<void> _showAddDialog() async {
    if (!_isAdmin) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String selectedIcon = 'category';
    int selectedType = 1; // 1-支出, 0-收入

    final commonIcons = IconConstants.allIcons;

    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeHelper.surface(context),
          title: ScaledText(
            AppLocalizations.of(context)!.addCategoryDialog,
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 类别名称
                  TextFormField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.categoryName,
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.label, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.pleaseEnterCategoryName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // 交易类型
                  Container(
                    padding: const EdgeInsets.all(4),
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
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedType = 1; // 1-支出(EXPENSE)
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == 1
                                    ? ThemeHelper.expenseColor(context).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    size: 16,
                                    color: selectedType == 1
                                        ? ThemeHelper.expenseColor(context)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.expense,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == 1
                                          ? ThemeHelper.expenseColor(context)
                                          : Colors.white54,
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
                                selectedType = 0; // 0-收入(INCOME)
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == 0
                                    ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    size: 16,
                                    color: selectedType == 0
                                        ? ThemeHelper.primary(context)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.income,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == 0
                                          ? ThemeHelper.primary(context)
                                          : Colors.white54,
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
                  // 图标选择
                  ScaledText(
                    AppLocalizations.of(context)!.selectIcon,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: commonIcons.map((iconData) {
                          final isSelected = selectedIcon == iconData.name;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedIcon = iconData.name;
                              });
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                                    : ThemeHelper.surfaceLight(context),
                                border: Border.all(
                                  color: isSelected
                                      ? ThemeHelper.primary(context)
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                iconData.icon,
                                color: isSelected
                                    ? ThemeHelper.primary(context)
                                    : Colors.white.withValues(alpha: 0.8),
                                size: 24,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
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
                      setDialogState(() {
                        isLoading = true;
                      });
                      try {
                        await _categoryService.addCategory(
                          name: nameController.text.trim(),
                          icon: selectedIcon,
                          type: selectedType,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          await _refreshCategories();
                          CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.addSuccess);
                        }
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                        });
                        if (context.mounted) {
                          final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.addFailed);
                          CustomSnackBar.showError(context, errorMessage);
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ScaledText(
                      AppLocalizations.of(context)!.add,
                      style: TextStyle(color: ThemeHelper.primary(context)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(Category category) async {
    if (!_isAdmin) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: category.name);
    String selectedIcon = category.icon;
    int selectedType = category.type;

    final commonIcons = IconConstants.allIcons;

    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeHelper.surface(context),
          title: ScaledText(
            AppLocalizations.of(context)!.editCategory,
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 类别名称
                  TextFormField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.categoryName,
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.label, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.pleaseEnterCategoryName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // 交易类型
                  Container(
                    padding: const EdgeInsets.all(4),
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
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedType = 1; // 1-支出(EXPENSE)
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == 1
                                    ? ThemeHelper.expenseColor(context).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    size: 16,
                                    color: selectedType == 1
                                        ? ThemeHelper.expenseColor(context)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.expense,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == 1
                                          ? ThemeHelper.expenseColor(context)
                                          : Colors.white54,
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
                                selectedType = 0; // 0-收入(INCOME)
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: selectedType == 0
                                    ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    size: 16,
                                    color: selectedType == 0
                                        ? ThemeHelper.primary(context)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  ScaledText(
                                    AppLocalizations.of(context)!.income,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selectedType == 0
                                          ? ThemeHelper.primary(context)
                                          : Colors.white54,
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
                  // 图标选择
                  ScaledText(
                    AppLocalizations.of(context)!.selectIcon,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: commonIcons.map((iconData) {
                          final isSelected = selectedIcon == iconData.name;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedIcon = iconData.name;
                              });
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                                    : ThemeHelper.surfaceLight(context),
                                border: Border.all(
                                  color: isSelected
                                      ? ThemeHelper.primary(context)
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                iconData.icon,
                                color: isSelected
                                    ? ThemeHelper.primary(context)
                                    : Colors.white.withValues(alpha: 0.8),
                                size: 24,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
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
                      setDialogState(() {
                        isLoading = true;
                      });
                      try {
                        await _categoryService.updateCategory(
                          id: category.id,
                          name: nameController.text.trim(),
                          icon: selectedIcon,
                          type: selectedType,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          await _refreshCategories();
                          CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.updateSuccess);
                        }
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                        });
                        if (context.mounted) {
                          final errorMessage = ErrorHelper.extractErrorMessage(e, defaultMessage: AppLocalizations.of(context)!.updateFailed);
                          CustomSnackBar.showError(context, errorMessage);
                        }
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
                      style: TextStyle(color: ThemeHelper.primary(context)),
                    ),
            ),
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();

    final categories = _activeTab == AppLocalizations.of(context)!.expense
        ? categoryProvider.expenseCategories
        : categoryProvider.incomeCategories;

    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.categoryManagement),
        actions: _isAdmin
            ? [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddDialog,
                  tooltip: AppLocalizations.of(context)!.tooltipAddCategory,
                ),
              ]
            : null,
      ),
      body: categoryProvider.isLoading
          ? const LoadingIndicator()
          : categoryProvider.error != null
              ? custom.CustomErrorWidget(
                  message: categoryProvider.error!,
                  onRetry: _refreshCategories,
                )
              : Column(
                  children: [
                        // 选项卡
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.horizontalPadding(context),
                            vertical: ResponsiveHelper.verticalPadding(context),
                          ),
                          child: Row(
                            children: [AppLocalizations.of(context)!.expense, AppLocalizations.of(context)!.income].map((tab) {
                              final isActive = _activeTab == tab;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _activeTab = tab;
                                    });
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: ResponsiveHelper.spacing(context, small: 10, normal: 12, large: 14),
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: isActive
                                          ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                                          : Colors.transparent,
                                    ),
                                    child: ScaledText(
                                      tab,
                                      textAlign: TextAlign.center,
                                      style: ResponsiveHelper.responsiveTitleStyle(
                                        context,
                                        color: isActive
                                            ? ThemeHelper.primary(context)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        // 类别列表
                        Expanded(
                          child: categories.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.category_outlined,
                                        size: ResponsiveHelper.iconSize(context, defaultSize: 64),
                                        color: Colors.white.withValues(alpha: 0.3),
                                      ),
                                      SizedBox(height: ResponsiveHelper.spacing(context)),
                                      ScaledText(
                                        AppLocalizations.of(context)!.noCategories,
                                        style: ResponsiveHelper.responsiveTextStyle(
                                          context,
                                          color: Colors.white.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      if (_isAdmin) ...[
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: _showAddDialog,
                                          icon: const Icon(Icons.add),
                                          label: ScaledText(AppLocalizations.of(context)!.addCategory),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: ResponsiveHelper.containerMargin(context),
                                  itemCount: categories.length,
                                  itemBuilder: (context, index) {
                                    final category = categories[index];
                                    return _buildCategoryCard(category);
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildCategoryCard(Category category) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, small: 10, normal: 12)),
      padding: ResponsiveHelper.cardPadding(context),
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
              color: category.type == 0
                  ? ThemeHelper.primary(context).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            child: Icon(
              IconConstants.getIconFromString(category.icon),
              color: category.type == 0
                  ? ThemeHelper.primary(context)
                  : Colors.white70,
              size: 24,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context)),
          Expanded(
            child: ScaledText(
              category.name,
              style: ResponsiveHelper.responsiveTitleStyle(context, color: Colors.white),
            ),
          ),
          if (_isAdmin)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: ThemeHelper.primary(context).withValues(alpha: 0.8),
                  ),
                  onPressed: () => _showEditDialog(category),
                  tooltip: AppLocalizations.of(context)!.tooltipEdit,
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: ThemeHelper.expenseColor(context).withValues(alpha: 0.8),
                  ),
                  onPressed: () => _deleteCategory(category),
                  tooltip: AppLocalizations.of(context)!.tooltipDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

