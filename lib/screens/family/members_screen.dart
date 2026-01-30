import 'package:flutter/material.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/scaled_text.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../models/family_member.dart';
import '../../l10n/app_localizations.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final FamilyService _familyService = FamilyService();
  List<FamilyMember> _members = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final members = await _familyService.getMembers();
      setState(() {
        _members = members;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _members = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.member),
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _error != null
              ? custom.CustomErrorWidget(
                  message: _error!,
                  onRetry: _loadMembers,
                )
              : _members.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: ResponsiveHelper.iconSize(context, defaultSize: 64),
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context)),
                          ScaledText(
                            AppLocalizations.of(context)!.noMemberData,
                            style: ResponsiveHelper.responsiveTextStyle(
                              context,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: ResponsiveHelper.containerMargin(context),
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        return _buildMemberCard(member);
                      },
                    ),
    );
  }

  Widget _buildMemberCard(FamilyMember member) {
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
          CircleAvatar(
            radius: ResponsiveHelper.responsiveValue(
              context,
              small: 24.0,
              normal: 28.0,
              large: 32.0,
            ),
            backgroundImage: member.avatar != null && member.avatar!.isNotEmpty
                ? NetworkImage(member.avatar!)
                : null,
            backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.2),
            child: member.avatar == null || member.avatar!.isEmpty
                ? Icon(
                    Icons.person,
                    color: ThemeHelper.primary(context),
                    size: ResponsiveHelper.responsiveValue(
                      context,
                      small: 24.0,
                      normal: 28.0,
                      large: 32.0,
                    ),
                  )
                : null,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ScaledText(
                      member.name,
                      style: ResponsiveHelper.responsiveTitleStyle(context, color: Colors.white),
                    ),
                    if (FamilyMemberRole.isAdmin(member.role)) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, small: 6, normal: 8)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, small: 6, normal: 8),
                          vertical: ResponsiveHelper.spacing(context, small: 2, normal: 2),
                        ),
                        decoration: BoxDecoration(
                          color: ThemeHelper.primary(context).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ThemeHelper.primary(context),
                            width: 1,
                          ),
                        ),
                        child: ScaledText(
                          AppLocalizations.of(context)!.admin,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: ThemeHelper.primary(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.label != null && member.label!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ScaledText(
                    member.label!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

