import 'package:flutter/material.dart';
import '../../services/api/family_service.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_widget.dart' as custom;
import '../../widgets/common/font_size_inherited.dart';
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
    // 8.2：休眠成员（未开启云备份）灰色标记——其账单不会上云，
    // 其他成员无法看到其数据，需要视觉上区分数据可见范围
    final dormant = !member.isSyncing;
    final nameColor =
        dormant ? Colors.white.withValues(alpha: 0.4) : Colors.white;
    // 徽章是状态装饰而非阅读主体：反比抵消应用内字号缩放，
    // 字号调大时徽章尺寸稳定，充当卡片的视觉比例锚点（不变形）
    final badgeScale = 1 / FontSizeInherited.of(context).fontSizeScale;
    // 描述行：备注与休眠说明共存（超宽省略，不再互斥顶替丢信息）
    final desc = [
      if (member.label != null && member.label!.isNotEmpty) member.label!,
      if (dormant) AppLocalizations.of(context)!.memberSyncDormantDesc,
    ].join(' · ');

    return Container(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, small: 8, normal: 10)),
      padding: EdgeInsets.all(ResponsiveHelper.responsiveValue(
          context, small: 10.0, normal: 12.0, large: 16.0)),
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
              small: 18.0,
              normal: 22.0,
              large: 26.0,
            ),
            backgroundImage: member.avatar != null && member.avatar!.isNotEmpty
                ? NetworkImage(member.avatar!)
                : null,
            backgroundColor: ThemeHelper.primary(context).withValues(alpha: 0.2),
            child: member.avatar == null || member.avatar!.isEmpty
                ? Icon(
                    Icons.person,
                    color: dormant
                        ? Colors.white.withValues(alpha: 0.4)
                        : ThemeHelper.primary(context),
                    size: ResponsiveHelper.responsiveValue(
                      context,
                      small: 18.0,
                      normal: 22.0,
                      large: 26.0,
                    ),
                  )
                : null,
          ),
          SizedBox(
              width: ResponsiveHelper.spacing(context, small: 10, normal: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: ScaledText(
                        member.name,
                        style: ResponsiveHelper.responsiveTextStyle(
                          context,
                          fontSize: ResponsiveHelper.responsiveValue(
                              context, small: 15.0, normal: 16.0, large: 18.0),
                          fontWeight: FontWeight.bold,
                          color: nameColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (FamilyMemberRole.isAdmin(member.role)) ...[
                      const SizedBox(width: 6),
                      _buildBadge(
                        AppLocalizations.of(context)!.admin,
                        badgeScale,
                        textColor: ThemeHelper.primary(context),
                        borderColor: ThemeHelper.primary(context),
                        backgroundColor:
                            ThemeHelper.primary(context).withValues(alpha: 0.2),
                      ),
                    ],
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  ScaledText(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white
                          .withValues(alpha: dormant ? 0.4 : 0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
          // 右侧状态区（方案 A）：休眠=灰胶囊（异常态显眼），
          // 同步中=主题色小圆点（正常态轻表达，几乎隐形）
          SizedBox(
              width: ResponsiveHelper.spacing(context, small: 8, normal: 10)),
          if (dormant)
            _buildBadge(
              AppLocalizations.of(context)!.memberSyncDormant,
              badgeScale,
              textColor: Colors.white.withValues(alpha: 0.5),
              borderColor: Colors.white.withValues(alpha: 0.3),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeHelper.primary(context),
              ),
            ),
        ],
      ),
    );
  }

  /// 徽章胶囊：9px 小字 + 紧凑内边距，锁定字号缩放
  Widget _buildBadge(
    String text,
    double scale, {
    required Color textColor,
    required Color borderColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ScaledText(
        text,
        textScaleFactor: scale,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

