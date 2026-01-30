import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../services/api/family_service.dart';
import '../../models/family.dart';
import '../../widgets/common/scaled_text.dart';
import '../../l10n/app_localizations.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final FamilyService _familyService = FamilyService();
  Family? _currentFamily;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentFamily();
  }

  Future<void> _loadCurrentFamily() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final families = await _familyService.getFamiliesList();
      if (families.isNotEmpty) {
        setState(() {
          _currentFamily = families.firstWhere(
            (f) => f.isCurrent,
            orElse: () => families.first,
          );
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getQrCodeData() {
    if (_currentFamily == null) return '';
    // 二维码内容格式：family:familyId
    return 'family:${_currentFamily!.id}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScaledText(AppLocalizations.of(context)!.familyInvite),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              context.push('/scanner');
            },
            tooltip: AppLocalizations.of(context)!.scan,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _currentFamily == null
                ? Center(
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
                          AppLocalizations.of(context)!.error,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: ResponsiveHelper.containerMargin(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                              height: ResponsiveHelper.spacing(
                                  context, small: 24, normal: 32, large: 40)),
                          ScaledText(
                            AppLocalizations.of(context)!.familyInvite,
                            style: ResponsiveHelper.responsiveTitleStyle(
                              context,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(
                                  context, small: 6, normal: 8)),
                          ScaledText(
                            AppLocalizations.of(context)!.scanQrCodeToJoin,
                            style: ResponsiveHelper.responsiveTextStyle(
                              context,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(
                                  context, small: 32, normal: 40, large: 48)),
                          // 二维码卡片
                          Container(
                            padding: ResponsiveHelper.cardPadding(context),
                            decoration: BoxDecoration(
                              color: ThemeHelper.surface(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              children: [
                                ScaledText(
                                  AppLocalizations.of(context)!.familyInvite,
                                  style: ResponsiveHelper.responsiveTextStyle(
                                    context,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 16, normal: 20, large: 24)),
                                // 二维码
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: QrImageView(
                                    data: _getQrCodeData(),
                                    version: QrVersions.auto,
                                    size: ResponsiveHelper.responsiveValue(
                                      context,
                                      small: 200.0,
                                      normal: 250.0,
                                      large: 300.0,
                                    ),
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 16, normal: 20, large: 24)),
                                ScaledText(
                                  _currentFamily?.name ?? AppLocalizations.of(context)!.family,
                                  style: ResponsiveHelper.responsiveTextStyle(
                                    context,
                                    fontSize: ResponsiveHelper.responsiveValue(
                                      context,
                                      small: 14.0,
                                      normal: 16.0,
                                      large: 18.0,
                                    ),
                                    fontWeight: FontWeight.bold,
                                    color: ThemeHelper.primary(context),
                                  ),
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 8, normal: 12)),
                                ScaledText(
                                  AppLocalizations.of(context)!.scanQrCodeToJoin,
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
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(context,
                                  small: 24, normal: 32, large: 40)),
                          // 提示信息
                          Container(
                            padding: ResponsiveHelper.cardPadding(context),
                            decoration: BoxDecoration(
                              color: ThemeHelper.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: ResponsiveHelper.iconSize(context,
                                          defaultSize: 20),
                                      color: Colors.white70,
                                    ),
                                    SizedBox(
                                        width: ResponsiveHelper.spacing(context,
                                            small: 6, normal: 8)),
                                    ScaledText(
                                      AppLocalizations.of(context)!.tip,
                                      style: ResponsiveHelper.responsiveTextStyle(
                                        context,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 8, normal: 12)),
                                _buildInstructionItem(
                                  context,
                                  '1',
                                  AppLocalizations.of(context)!.clickScanButton,
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 6, normal: 8)),
                                _buildInstructionItem(
                                  context,
                                  '2',
                                  AppLocalizations.of(context)!.scanFamilyQrCode,
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 6, normal: 8)),
                                _buildInstructionItem(
                                  context,
                                  '3',
                                  AppLocalizations.of(context)!.enterRemarkAndSubmit,
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(context,
                                        small: 6, normal: 8)),
                                _buildInstructionItem(
                                  context,
                                  '4',
                                  AppLocalizations.of(context)!.waitAdminApproval,
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

  Widget _buildInstructionItem(
      BuildContext context, String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: ThemeHelper.primary(context),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: ScaledText(
              number,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, small: 8, normal: 12)),
        Expanded(
          child: ScaledText(
            text,
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
    );
  }
}
