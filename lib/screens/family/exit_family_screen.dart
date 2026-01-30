import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/family_service.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class ExitFamilyScreen extends StatefulWidget {
  const ExitFamilyScreen({super.key});

  @override
  State<ExitFamilyScreen> createState() => _ExitFamilyScreenState();
}

class _ExitFamilyScreenState extends State<ExitFamilyScreen> {
  final FamilyService _familyService = FamilyService();
  bool _isLoading = false;

  Future<void> _exitFamily() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: ScaledText(AppLocalizations.of(context)!.confirmLogout),
        content: ScaledText(AppLocalizations.of(context)!.exitFamilyWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: ScaledText(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelper.expenseColor(context),
            ),
            child: ScaledText(AppLocalizations.of(context)!.confirmLogout),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _familyService.exitFamily();
      
      final authProvider = context.read<AuthProvider>();
      await authProvider.logout();

      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.exitFamilySuccess);
        context.go('/welcome');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(
          e,
          defaultMessage: AppLocalizations.of(context)!.operationFailed,
        );
        CustomSnackBar.showError(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.exitCurrentFamily),
      ),
      body: SafeArea(
        child: Padding(
          padding: ResponsiveHelper.containerMargin(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
              Icon(
                Icons.warning_amber_rounded,
                size: ResponsiveHelper.responsiveValue(
                  context,
                  small: 56.0,
                  normal: 64.0,
                  large: 72.0,
                ),
                color: ThemeHelper.expenseColor(context).withValues(alpha: 0.8),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, small: 20, normal: 24, large: 32)),
              ScaledText(
                AppLocalizations.of(context)!.exitCurrentFamily,
                style: ResponsiveHelper.responsiveTitleStyle(
                  context,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              ScaledText(
                AppLocalizations.of(context)!.exitFamilyConsequences,
                style: ResponsiveHelper.responsiveTextStyle(
                  context,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context)),
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: ThemeHelper.expenseColor(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ThemeHelper.expenseColor(context).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWarningItem(AppLocalizations.of(context)!.cannotViewFamilyData),
                    _buildWarningItem(AppLocalizations.of(context)!.cannotViewMemberInfo),
                    _buildWarningItem(AppLocalizations.of(context)!.cannotAddTransactions),
                    _buildWarningItem(AppLocalizations.of(context)!.needReapplyToJoin),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, small: 24, normal: 32, large: 40)),
              ElevatedButton(
                onPressed: _isLoading ? null : _exitFamily,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeHelper.expenseColor(context).withValues(alpha: 0.2),
                  foregroundColor: ThemeHelper.expenseColor(context),
                  padding: ResponsiveHelper.buttonPadding(context),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ScaledText(AppLocalizations.of(context)!.confirmLogout, style: ResponsiveHelper.responsiveTextStyle(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.remove, size: 16, color: ThemeHelper.expenseColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

