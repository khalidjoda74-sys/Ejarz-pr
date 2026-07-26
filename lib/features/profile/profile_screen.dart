import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_guard.dart';
import '../../core/navigation/app_page_route.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/tab_activity_scope.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/council_repository.dart';
import '../sponsorship/sponsorship_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onSignedOut});

  final VoidCallback? onSignedOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _avatarOptions = businessAvatarOptions;
  static final Uri _privacyUrl = Uri.parse(
    'https://us-central1-majalisna-discussions-20260629.cloudfunctions.net/privacyPolicy',
  );
  static final Uri _termsUrl = Uri.parse(
    'https://us-central1-majalisna-discussions-20260629.cloudfunctions.net/termsOfUse',
  );
  static const _supportEmail = 'Info@forsabro.sa';

  bool _subpageOpening = false;
  bool _savingAvatar = false;
  bool _signingOut = false;

  Future<void> _confirmAndSignOut() async {
    if (_signingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .34),
      builder: (_) => const AppConfirmationDialog(
        title: 'تسجيل الخروج؟',
        message:
            'ستحتاج إلى تسجيل الدخول مرة أخرى للمشاركة وإضافة رأيك داخل الفرص.',
        confirmLabel: 'تسجيل الخروج',
        icon: Icons.logout_rounded,
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _signingOut = true);
    final controller = AuthController.instance;
    final signedOut = await controller.signOut();
    if (!mounted) return;
    setState(() => _signingOut = false);

    if (signedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الخروج بنجاح')),
      );
      widget.onSignedOut?.call();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.errorMessage ??
              'تعذر تسجيل الخروج الآن. تحقق من اتصالك وحاول مرة أخرى.',
        ),
      ),
    );
  }

  Future<void> _openSubpage(WidgetBuilder builder) async {
    if (_subpageOpening || !mounted) return;
    _subpageOpening = true;
    try {
      await Navigator.of(context).push<void>(
        AppPageRoute(builder: builder),
      );
    } finally {
      _subpageOpening = false;
    }
  }

  Future<void> _openSettings() {
    return AuthGuard.requireAuth(
      context,
      () async {
        if (!mounted) return;
        await _openSubpage(
          (routeContext) => SettingsScreen(
            onBack: () => Navigator.of(routeContext).maybePop(),
          ),
        );
      },
    );
  }

  void _openAdsAndSponsorships() {
    _openSubpage(
      (routeContext) => SponsorshipScreen(
        onBack: () => Navigator.of(routeContext).maybePop(),
      ),
    );
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط حاليًا.')),
      );
    }
  }

  Future<void> _openSupportDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .34),
      builder: (_) => _SupportDialog(
        email: _supportEmail,
        onCopyEmail: () async {
          await Clipboard.setData(const ClipboardData(text: _supportEmail));
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم نسخ بريد الدعم')),
          );
        },
        onSendEmail: () async {
          final uri = Uri(
            scheme: 'mailto',
            path: _supportEmail,
            queryParameters: const {'subject': 'طلب دعم - فرصة برو'},
          );
          Navigator.of(context).pop();
          await _openExternal(uri);
        },
      ),
    );
  }

  Future<void> _openAboutDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .34),
      builder: (_) => const _AboutDialog(),
    );
  }

  Future<void> _requestLogin() {
    return AuthGuard.requireAuth(
      context,
      () async {},
      allowAnonymous: false,
    );
  }

  Future<void> _openAvatarPicker(UserModel user) async {
    if (_savingAvatar) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.textDark.withValues(alpha: .28),
      builder: (_) => _AvatarPickerSheet(
        avatars: _avatarOptions,
        currentAvatar: user.avatarEmoji,
      ),
    );

    if (selected == null || selected == user.avatarEmoji || !mounted) return;

    setState(() => _savingAvatar = true);
    try {
      final changed =
          await CouncilRepository.instance.updateAvatarEmoji(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(changed
                ? 'تم تغيير الصورة الرمزية'
                : 'لم تتغير الصورة الرمزية')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تعذر تغيير الصورة الرمزية. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = CouncilRepository.instance;
    final auth = AuthController.instance;
    final sizes = AppSizes.of(context);
    final active = TabActivityScope.isActiveOf(context);

    return AnimatedBuilder(
      animation: active
          ? Listenable.merge([repo.userState, auth])
          : kAlwaysCompleteAnimation,
      builder: (context, _) {
        final localUser = repo.user;
        final firebaseUser = auth.user;

        if (!auth.isSignedIn || firebaseUser == null) {
          return _GuestProfileView(
            onLogin: _requestLogin,
            onOpenAdsAndSponsorships: _openAdsAndSponsorships,
            onOpenAbout: _openAboutDialog,
            onOpenPrivacy: () => _openExternal(_privacyUrl),
            onOpenTerms: () => _openExternal(_termsUrl),
            onOpenSupport: _openSupportDialog,
          );
        }

        Widget buildProfile(UserModel user) {
          final displayName = user.name;
          final accountEmail = firebaseUser.email?.trim();

          return Scaffold(
            backgroundColor: AppColors.background,
            body: PremiumBackground(
              showPattern: false,
              child: Column(
                children: [
                  const CustomGreenHeader(title: 'حسابي', height: 96),
                  const SizedBox(height: 10),
                  Center(
                    child: _EditableProfileAvatar(
                      label: user.avatarEmoji,
                      photoUrl: null,
                      size: 76,
                      saving: _savingAvatar,
                      onTap: () => _openAvatarPicker(user),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        sizes.horizontalPadding,
                        10,
                        sizes.horizontalPadding,
                        sizes.bottomNavHeight +
                            18 +
                            MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      children: [
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.pageTitle.copyWith(fontSize: 18),
                        ),
                        if (accountEmail?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            accountEmail!,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: AppTextStyles.caption.copyWith(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Center(child: _ActiveBadge(label: user.badge)),
                        const SizedBox(height: 12),
                        _StatsCard(user: user),
                        const SizedBox(height: 10),
                        _MenuCard(
                          children: [
                            _MenuRow(
                              icon: Icons.settings_outlined,
                              label: 'الإعدادات',
                              onTap: () {
                                _openSettings();
                              },
                            ),
                            _MenuRow(
                              icon: Icons.campaign_outlined,
                              label: 'إعلانات ورعايات',
                              onTap: _openAdsAndSponsorships,
                            ),
                            _MenuRow(
                              icon: Icons.info_outline_rounded,
                              label: 'عن فرصة برو',
                              onTap: _openAboutDialog,
                            ),
                            _MenuRow(
                              icon: Icons.privacy_tip_outlined,
                              label: 'سياسة الخصوصية',
                              external: true,
                              onTap: () => _openExternal(_privacyUrl),
                            ),
                            _MenuRow(
                              icon: Icons.description_outlined,
                              label: 'شروط الاستخدام',
                              external: true,
                              onTap: () => _openExternal(_termsUrl),
                            ),
                            _MenuRow(
                              icon: Icons.help_outline_rounded,
                              label: 'الدعم والمساعدة',
                              onTap: _openSupportDialog,
                            ),
                            _MenuRow(
                              icon: Icons.logout_rounded,
                              label: 'تسجيل الخروج',
                              danger: true,
                              showDivider: false,
                              onTap: _confirmAndSignOut,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return buildProfile(localUser);
      },
    );
  }
}

class _GuestProfileView extends StatelessWidget {
  const _GuestProfileView({
    required this.onLogin,
    required this.onOpenAdsAndSponsorships,
    required this.onOpenAbout,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
    required this.onOpenSupport,
  });

  final Future<void> Function() onLogin;
  final VoidCallback onOpenAdsAndSponsorships;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            const CustomGreenHeader(title: 'حسابي', height: 96),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  sizes.horizontalPadding,
                  14,
                  sizes.horizontalPadding,
                  sizes.bottomNavHeight +
                      18 +
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  _GuestLoginCard(onLogin: onLogin),
                  const SizedBox(height: 10),
                  _MenuCard(
                    children: [
                      _MenuRow(
                        icon: Icons.campaign_outlined,
                        label: 'إعلانات ورعايات',
                        onTap: onOpenAdsAndSponsorships,
                      ),
                      _MenuRow(
                        icon: Icons.info_outline_rounded,
                        label: 'عن فرصة برو',
                        onTap: onOpenAbout,
                      ),
                      _MenuRow(
                        icon: Icons.privacy_tip_outlined,
                        label: 'سياسة الخصوصية',
                        external: true,
                        onTap: onOpenPrivacy,
                      ),
                      _MenuRow(
                        icon: Icons.description_outlined,
                        label: 'شروط الاستخدام',
                        external: true,
                        onTap: onOpenTerms,
                      ),
                      _MenuRow(
                        icon: Icons.help_outline_rounded,
                        label: 'الدعم والمساعدة',
                        showDivider: false,
                        onTap: onOpenSupport,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestLoginCard extends StatelessWidget {
  const _GuestLoginCard({required this.onLogin});

  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderBeige),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F4A35),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: .14),
                    ),
                  ),
                  child: const Icon(
                    Icons.account_circle_outlined,
                    color: AppColors.primaryDarkGreen,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أهلًا بك في فرصة برو',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'سجّل الدخول لإدارة فرصك ورسائلك وتعديل هويتك.',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: Material(
                color: AppColors.primaryDarkGreen,
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  onTap: () => onLogin(),
                  borderRadius: BorderRadius.circular(15),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.login_rounded,
                          color: AppColors.cardWhite,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'تسجيل الدخول',
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.cardWhite,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderBeige),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textDark.withValues(alpha: .16),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppColors.primaryGreen.withValues(alpha: .16),
                          ),
                        ),
                        child: const Icon(
                          Icons.business_center_outlined,
                          color: AppColors.primaryDarkGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'عن فرصة برو',
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 17,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'فرصة برو منصة متخصصة لعرض ومناقشة فرص الأعمال بوضوح أعلى. نساعدك على اكتشاف فرص قائمة، طلب فرص مناسبة، بناء شراكات، وقراءة تجارب حقيقية من السوق قبل اتخاذ قرارك.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textGray,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _AboutPoint(
                    icon: Icons.storefront_rounded,
                    title: 'فرص للتقبيل',
                    text:
                        'مشاريع ومحلات قائمة معروضة للبيع أو التقبيل مثل مطعم، كوفي، مغسلة، متجر أو نشاط قائم.',
                  ),
                  const _AboutPoint(
                    icon: Icons.manage_search_rounded,
                    title: 'فرص مطلوبة',
                    text:
                        'طلبات من أشخاص يبحثون عن فرصة مناسبة للاستثمار، التشغيل، أو دخول قطاع محدد.',
                  ),
                  const _AboutPoint(
                    icon: Icons.handshake_outlined,
                    title: 'فرص شراكة',
                    text:
                        'طلبات شراكة من أشخاص يبحثون عن ممول، مشغّل، أو صاحب خبرة.',
                  ),
                  const _AboutPoint(
                    icon: Icons.insights_rounded,
                    title: 'تجارب السوق',
                    text:
                        'تجارب واقعية تساعدك على فهم الأخطاء، النتائج، الموردين، الإعلانات، والتكاليف.',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderBeige),
                    ),
                    child: Text(
                      'تنبيه مهم: فرصة برو مساحة عرض ونقاش وتواصل، وليس وسيطًا أو ضامنًا للصفقات ولا يقدم نصيحة استثمارية أو قانونية. تحقق دائمًا من البيانات والجهات والتراخيص قبل أي اتفاق.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primaryDarkGreen,
                        fontSize: 11.7,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SupportActionButton(
                    label: 'تم',
                    icon: Icons.check_rounded,
                    primary: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutPoint extends StatelessWidget {
  const _AboutPoint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderBeige),
            ),
            child: Icon(icon, size: 18, color: AppColors.primaryDarkGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textDark,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textGray,
                    fontSize: 11.4,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportDialog extends StatelessWidget {
  const _SupportDialog({
    required this.email,
    required this.onCopyEmail,
    required this.onSendEmail,
  });

  final String email;
  final VoidCallback onCopyEmail;
  final VoidCallback onSendEmail;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 370),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: .16),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primaryGreen.withValues(alpha: .16),
                        ),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: AppColors.primaryDarkGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'الدعم والمساعدة',
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: 17,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'نعتني بكل ملاحظة تصلنا. للدعم، البلاغات، الشراكات، أو أي مشكلة تخص الحساب والفرص والرسائل، راسلنا وسنراجع طلبك بعناية.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderBeige),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.alternate_email_rounded,
                        color: AppColors.primaryDarkGreen,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          email,
                          textDirection: TextDirection.ltr,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SupportActionButton(
                        label: 'إرسال بريد',
                        icon: Icons.mail_outline_rounded,
                        primary: true,
                        onTap: onSendEmail,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _SupportActionButton(
                        label: 'نسخ البريد',
                        icon: Icons.copy_rounded,
                        onTap: onCopyEmail,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportActionButton extends StatelessWidget {
  const _SupportActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? AppColors.cardWhite : AppColors.textDark;
    final background =
        primary ? AppColors.primaryDarkGreen : AppColors.background;
    final borderColor =
        primary ? AppColors.primaryDarkGreen : AppColors.borderBeige;

    return SizedBox(
      height: 44,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.button.copyWith(
                      color: foreground,
                      fontSize: 12.4,
                    ),
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.label,
    required this.photoUrl,
    required this.size,
  });

  final String label;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = photoUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return AvatarBadge(label: label, size: size, border: true);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cardWhite, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F4A35),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
        image: DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _EditableProfileAvatar extends StatelessWidget {
  const _EditableProfileAvatar({
    required this.label,
    required this.photoUrl,
    required this.size,
    required this.saving,
    required this.onTap,
  });

  final String label;
  final String? photoUrl;
  final double size;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: saving ? null : onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: saving ? .72 : 1,
              child:
                  _ProfileAvatar(label: label, photoUrl: photoUrl, size: size),
            ),
            Positioned(
              left: -1,
              bottom: -1,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryDarkGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardWhite, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x220F4A35),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: saving
                    ? const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          color: AppColors.cardWhite,
                        ),
                      )
                    : const Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: AppColors.cardWhite,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet({
    required this.avatars,
    required this.currentAvatar,
  });

  final List<String> avatars;
  final String currentAvatar;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderBeige),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'اختر صورة رمزية',
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: avatars.map((avatar) {
                  final selected = avatar == currentAvatar;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(avatar),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryDarkGreen
                            : AppColors.background.withValues(alpha: .58),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              selected ? AppColors.gold : AppColors.borderBeige,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: AvatarBadge(label: avatar, size: 38),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primaryDarkGreen,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _Stat(
              value: '${(user.points / 1000).toStringAsFixed(1)}K',
              label: 'النقاط'),
          const _Divider(),
          _Stat(value: '${user.comments}', label: 'التعليقات'),
          const _Divider(),
          _Stat(value: '${user.councils}', label: 'الفرص'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.primaryDarkGreen,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 28, width: 1, color: AppColors.borderBeige);
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.borderBeige),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
    this.showDivider = true,
    this.external = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool showDivider;
  final bool external;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.primaryDarkGreen;

    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: danger ? AppColors.red : AppColors.textDark,
                        fontFamily: AppTextStyles.fontFamily,
                        fontFamilyFallback: AppTextStyles.fontFamilyFallback,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    external
                        ? Icons.open_in_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: external ? 16 : 13,
                    color: danger ? AppColors.red : AppColors.textGray,
                  ),
                ],
              ),
            ),
          ),
          if (showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: AppColors.borderBeige,
            ),
        ],
      ),
    );
  }
}
