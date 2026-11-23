import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../data/local/current_family_store.dart';
import '../../data/local/family_member_cache.dart';
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
  const MembersScreen({super.key, this.memberLoader});

  /// 测试注入用：默认走 FamilyService 网络 + 本地缓存回退
  final Future<List<FamilyMember>> Function()? memberLoader;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final FamilyService _familyService = FamilyService();
  List<FamilyMember> _members = [];
  bool _isLoading = true;
  // 无缓存且加载失败：展示可读提示（不暴露原始异常文本）
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    // 先展示本地缓存（离线可用、切换家庭后立即更新），再静默刷新
    final familyId = await CurrentFamilyStore.get();
    final cached = await FamilyMemberCache.load(familyId);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _members = cached;
        _isLoading = false;
      });
    }

    try {
      // 服务层网络失败会回退同一份缓存，无缓存才抛错
      final members =
          await (widget.memberLoader?.call() ?? _familyService.getMembers());
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // 已有缓存/已展示成员时保留列表、静默降级；无成员才提示可读文案
        _loadFailed = _members.isEmpty;
      });
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
        title: ScaledText(AppLocalizations.of(context)!.member),
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _loadFailed
              ? custom.CustomErrorWidget(
                  message: AppLocalizations.of(context)!.membersLoadFailed,
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
    // 描述行：备注（超宽省略）
    final desc = [
      if (member.label != null && member.label!.isNotEmpty) member.label!,
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
                ? CachedNetworkImageProvider(member.avatar!)
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
          // 右侧状态区：两态徽章显式区分——开启=主题色胶囊「已开启同步」，
          // 未开启=灰胶囊「未开启同步」（家庭内可辨识谁的账单会出现在云端）
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
            _buildBadge(
              AppLocalizations.of(context)!.memberSyncActive,
              badgeScale,
              textColor: ThemeHelper.primary(context),
              borderColor: ThemeHelper.primary(context).withValues(alpha: 0.6),
              backgroundColor:
                  ThemeHelper.primary(context).withValues(alpha: 0.2),
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

