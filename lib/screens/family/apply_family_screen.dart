import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';

class ApplyFamilyScreen extends StatefulWidget {
  final String? familyId;

  const ApplyFamilyScreen({
    super.key,
    this.familyId,
  });

  @override
  State<ApplyFamilyScreen> createState() => _ApplyFamilyScreenState();
}

class _ApplyFamilyScreenState extends State<ApplyFamilyScreen> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _noteController = TextEditingController();
  final bool _isLoading = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitApplication() async {
    final familyId = widget.familyId;
    if (familyId == null || familyId.isEmpty) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.familyIdCannotBeEmpty);
      return;
    }

    final note = _noteController.text.trim();
    if (note.isEmpty) {
      CustomSnackBar.showError(context, AppLocalizations.of(context)!.pleaseEnterApplicationNote);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _familyService.applyToFamily(
        familyId: familyId,
        note: note,
      );

      if (mounted) {
        CustomSnackBar.showSuccess(context, AppLocalizations.of(context)!.applicationSubmittedWaitingApproval);
        // 延迟后返回
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            context.pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(
          e,
          defaultMessage: AppLocalizations.of(context)!.submitFailed,
        );
        CustomSnackBar.showError(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.familyId == null || widget.familyId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: ScaledText(AppLocalizations.of(context)!.applyToJoinFamily),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              ScaledText(
                AppLocalizations.of(context)!.invalidFamilyInviteCode,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: ScaledText(AppLocalizations.of(context)!.back),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.applyToJoinFamily),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: LoadingIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: ResponsiveHelper.containerMargin(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 24, normal: 32, large: 40)),
                      Icon(
                        Icons.group_add,
                        size: 64,
                        color: ThemeHelper.primary(context),
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 16, normal: 20, large: 24)),
                      ScaledText(
                        AppLocalizations.of(context)!.applyToJoinFamily,
                        style: ResponsiveHelper.responsiveTitleStyle(
                          context,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 8, normal: 12)),
                      ScaledText(
                        AppLocalizations.of(context)!.pleaseEnterApplicationNote,
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 32, normal: 40, large: 48)),
                      TextField(
                        controller: _noteController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.applicationNote,
                          hintText: AppLocalizations.of(context)!.pleaseEnterReasonForJoining,
                          prefixIcon: Icon(Icons.note,
                              size: ResponsiveHelper.iconSize(context)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 24, normal: 32, large: 40)),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitApplication,
                        style: ElevatedButton.styleFrom(
                          padding: ResponsiveHelper.buttonPadding(context),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : ScaledText(
                                AppLocalizations.of(context)!.submitApplication,
                                style:
                                    ResponsiveHelper.responsiveTextStyle(context),
                              ),
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context,
                              small: 16, normal: 20, large: 24)),
                      Container(
                        padding: ResponsiveHelper.cardPadding(context),
                        decoration: BoxDecoration(
                          color: ThemeHelper.surface(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: ResponsiveHelper.iconSize(context,
                                  defaultSize: 20),
                              color: Colors.white70,
                            ),
                            SizedBox(
                                width: ResponsiveHelper.spacing(context,
                                    small: 8, normal: 12)),
                            Expanded(
                              child: ScaledText(
                                AppLocalizations.of(context)!.applicationSubmittedWaitingApproval,
                                style: ResponsiveHelper.responsiveTextStyle(
                                  context,
                                  fontSize: ResponsiveHelper.responsiveValue(
                                    context,
                                    small: 11.0,
                                    normal: 12.0,
                                    large: 13.0,
                                  ),
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
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
  }
}

