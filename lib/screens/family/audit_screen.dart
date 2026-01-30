import 'package:flutter/material.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/custom_snackbar.dart';
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_helper.dart';
import '../../models/application.dart';
import '../../l10n/app_localizations.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final FamilyService _familyService = FamilyService();
  List<Application> _applications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final applications = await _familyService.getPendingApplications();
      setState(() {
        _applications = applications;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _applications = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _processApplication(String id, String action) async {
    try {
      await _familyService.processApplication(id, action);
      await _loadApplications();
      if (mounted) {
        CustomSnackBar.showSuccess(
          context,
          action == 'approve' ? AppLocalizations.of(context)!.approved : AppLocalizations.of(context)!.rejected,
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorHelper.extractErrorMessage(
          e,
          defaultMessage: AppLocalizations.of(context)!.operationFailed,
        );
        CustomSnackBar.showError(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.joinAudit),
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _error != null
              ? custom.CustomErrorWidget(
                  message: _error!,
                  onRetry: _loadApplications,
                )
              : _applications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: ResponsiveHelper.responsiveValue(
                              context,
                              small: 56.0,
                              normal: 64.0,
                              large: 72.0,
                            ),
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context)),
                          ScaledText(
                            AppLocalizations.of(context)!.noPendingApplications,
                            style: ResponsiveHelper.responsiveTextStyle(
                              context,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadApplications,
                      child: ListView.builder(
                        padding: ResponsiveHelper.containerMargin(context),
                        itemCount: _applications.length,
                        itemBuilder: (context, index) {
                          final application = _applications[index];
                          return _buildApplicationCard(application);
                        },
                      ),
                    ),
    );
  }

  Widget _buildApplicationCard(Application application) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelper.surface(context),
        border: Border.all(
          color: application.isNew == true
              ? ThemeHelper.primary(context).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
          width: application.isNew == true ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: application.avatar != null && application.avatar!.isNotEmpty
                    ? NetworkImage(application.avatar!)
                    : null,
                backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.2),
                child: application.avatar == null || application.avatar!.isEmpty
                    ? Icon(
                        Icons.person,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ScaledText(
                          application.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (application.isNew == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ThemeHelper.primary(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ScaledText(
                              AppLocalizations.of(context)!.newLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    ScaledText(
                      application.time,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (application.note != null && application.note!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ScaledText(
                application.note!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _processApplication(application.id, 'reject'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: ThemeHelper.expenseColor(context).withValues(alpha: 0.5)),
                  ),
                  child: ScaledText(
                    AppLocalizations.of(context)!.reject,
                    style: TextStyle(color: ThemeHelper.expenseColor(context)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _processApplication(application.id, 'approve'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: ScaledText(AppLocalizations.of(context)!.approve),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


