import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/navigation/app_page_route.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/reusable_stream.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/discussion_card.dart';
import '../../core/widgets/optimized_network_image.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/council_model.dart';
import '../../data/models/public_profile_model.dart';
import '../../data/repositories/firebase_council_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../navigation/app_routes.dart';
import '../messages/conversation_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    super.key,
    required this.target,
  });

  final PublicProfileTarget target;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Stream<PublicProfileModel?> _profileStream;
  late Stream<List<CouncilModel>> _councilsStream;
  List<CouncilModel>? _initialCouncils;
  bool _openingConversation = false;

  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }

  @override
  void didUpdateWidget(covariant PublicProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.kind != widget.target.kind ||
        oldWidget.target.id != widget.target.id) {
      _initializeStreams();
    }
  }

  void _initializeStreams() {
    if (widget.target.isDemo) {
      _profileStream =
          reusableValueStream<PublicProfileModel?>(widget.target.seed);
      final profileId = widget.target.id;
      final councils = MockData.councils()
          .where(
            (council) =>
                council.createdBy == profileId &&
                (council.status == CouncilStatus.active ||
                    council.status == CouncilStatus.endingSoon),
          )
          .toList(growable: false);
      _initialCouncils = councils;
      _councilsStream = reusableValueStream<List<CouncilModel>>(councils);
      return;
    }

    _initialCouncils = null;
    _profileStream =
        PublicProfileRepository.instance.watchPublicProfile(widget.target);
    _councilsStream =
        FirebaseCouncilRepository.instance.watchPublicActiveCouncilsByOwner(
      uid: widget.target.uid ?? '',
    );
  }

  bool _isSelf(PublicProfileModel profile) {
    if (profile.demo) return false;
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous && user.uid == profile.uid;
  }

  Future<void> _onMessage(PublicProfileModel profile) async {
    if (profile.demo || widget.target.isDemo) {
      await _showDemoMessageNotice();
      return;
    }
    if (_openingConversation) return;

    await AuthGuard.requireAuth(
      context,
      () async {
        if (!mounted || _openingConversation) return;
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null &&
            !currentUser.isAnonymous &&
            currentUser.uid == profile.uid) {
          setState(() {});
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                  content: Text('هذا حسابك، ولا يمكنك مراسلة نفسك.')),
            );
          return;
        }
        final target = PublicProfileTarget.member(
          uid: profile.uid,
          seed: profile,
        );
        setState(() => _openingConversation = true);
        try {
          final repository = MessagingRepository.instance;
          final draft = repository.buildDirectConversationDraft(target);
          final pending = repository.getOrCreateDirectConversation(target);
          await Navigator.of(context).push<void>(
            AppPageRoute<void>(
              builder: (_) => ConversationScreen(
                conversationId: draft.id,
                initialConversation: draft,
                pendingCreation: pending,
              ),
            ),
          );
        } catch (error) {
          if (!mounted) return;
          final message = error.toString().contains('self-message')
              ? 'لا يمكنك مراسلة نفسك.'
              : error.toString().contains('invalid-direct-target')
                  ? 'المراسلة غير متاحة لهذا الحساب.'
                  : 'تعذر فتح المحادثة. حاول مرة أخرى.';
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(message)));
        } finally {
          if (mounted) setState(() => _openingConversation = false);
        }
      },
      allowAnonymous: false,
    );
  }

  Future<void> _showDemoMessageNotice() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: .1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryDarkGreen,
            size: 27,
          ),
        ),
        title: const Text(
          'حساب توضيحي',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'هذه شخصية تحريرية غير حقيقية أُضيفت لشرح التطبيق، لذلك لا تتوفر لها مراسلة.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: 150,
            child: FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDarkGreen,
                foregroundColor: AppColors.cardWhite,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('فهمت'),
            ),
          ),
        ],
      ),
    );
  }

  void _openCouncil(CouncilModel council) {
    Navigator.of(context).pushNamed<void>(AppRoutes.council(council.id));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PublicProfileModel?>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        final waiting =
            profileSnapshot.connectionState == ConnectionState.waiting &&
                !profileSnapshot.hasData;
        final profile =
            profileSnapshot.data ?? (waiting ? widget.target.seed : null);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackground(
            showPattern: false,
            child: Column(
              children: [
                const CustomGreenHeader(
                  title: 'الملف العام',
                  showBack: true,
                ),
                Expanded(
                  child: profile == null
                      ? _UnavailableProfile(loading: waiting)
                      : _buildProfile(context, profile),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfile(
    BuildContext context,
    PublicProfileModel profile,
  ) {
    final sizes = AppSizes.of(context);
    final isSelf = _isSelf(profile);
    return StreamBuilder<List<CouncilModel>>(
      stream: _councilsStream,
      initialData: _initialCouncils,
      builder: (context, councilsSnapshot) {
        final councils = (councilsSnapshot.data ?? const <CouncilModel>[])
            .where(
              (council) =>
                  council.status == CouncilStatus.active ||
                  council.status == CouncilStatus.endingSoon,
            )
            .toList(growable: false);
        final loadingCouncils =
            councilsSnapshot.connectionState == ConnectionState.waiting &&
                !councilsSnapshot.hasData;

        return CustomScrollView(
          key: PageStorageKey<String>('public_profile_${widget.target.id}'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sizes.horizontalPadding,
                12,
                sizes.horizontalPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _ProfileIdentityCard(
                  profile: profile,
                  isSelf: isSelf,
                  openingConversation: _openingConversation,
                  onMessage: () => _onMessage(profile),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sizes.horizontalPadding,
                18,
                sizes.horizontalPadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'الفرص الحالية',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
              ),
            ),
            if (loadingCouncils)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else if (councils.isEmpty)
              const SliverToBoxAdapter(child: _NoPublicCouncils())
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  sizes.horizontalPadding,
                  0,
                  sizes.horizontalPadding,
                  20 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final council = councils[index];
                      return DiscussionCard(
                        council: council,
                        compact: true,
                        onTap: () => _openCouncil(council),
                      );
                    },
                    childCount: councils.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileIdentityCard extends StatelessWidget {
  const _ProfileIdentityCard({
    required this.profile,
    required this.isSelf,
    required this.openingConversation,
    required this.onMessage,
  });

  final PublicProfileModel profile;
  final bool isSelf;
  final bool openingConversation;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F4A35),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (profile.demo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: .34),
                ),
              ),
              child: Text(
                'حساب تجريبي · شخصية توضيحية غير حقيقية',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primaryDarkGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _PublicAvatar(profile: profile),
          const SizedBox(height: 10),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: AppTextStyles.pageTitle.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: AppColors.primaryDarkGreen,
                ),
                const SizedBox(width: 5),
                Text(
                  _membershipLabel(profile.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primaryDarkGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (isSelf)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'هذا حسابك',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primaryDarkGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: openingConversation ? null : onMessage,
                icon: openingConversation
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cardWhite,
                        ),
                      )
                    : const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                label: Text(
                  openingConversation ? 'جارٍ فتح المحادثة...' : 'إرسال رسالة',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDarkGreen,
                  foregroundColor: AppColors.cardWhite,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _membershipLabel(DateTime? createdAt) {
  if (createdAt == null) return 'عضو منذ فترة';

  final now = DateTime.now();
  final joined = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final joinedDay = DateTime(joined.year, joined.month, joined.day);
  final days = today.difference(joinedDay).inDays;

  if (days <= 0) return 'عضو منذ اليوم';
  if (days < 30) return 'عضو منذ ${_arabicDuration(days, _DurationUnit.day)}';

  if (days < 365) {
    final months = days ~/ 30;
    return 'عضو منذ ${_arabicDuration(months, _DurationUnit.month)}';
  }

  final years = days ~/ 365;
  return 'عضو منذ ${_arabicDuration(years, _DurationUnit.year)}';
}

enum _DurationUnit { day, month, year }

String _arabicDuration(int value, _DurationUnit unit) {
  switch (unit) {
    case _DurationUnit.day:
      if (value == 1) return 'يوم';
      if (value == 2) return 'يومين';
      if (value >= 3 && value <= 10) return '$value أيام';
      return '$value يومًا';
    case _DurationUnit.month:
      if (value == 1) return 'شهر';
      if (value == 2) return 'شهرين';
      if (value >= 3 && value <= 10) return '$value أشهر';
      return '$value شهرًا';
    case _DurationUnit.year:
      if (value == 1) return 'سنة';
      if (value == 2) return 'سنتين';
      if (value >= 3 && value <= 10) return '$value سنوات';
      return '$value عامًا';
  }
}

class _PublicAvatar extends StatelessWidget {
  const _PublicAvatar({required this.profile});

  final PublicProfileModel profile;

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.publicPhotoUrl?.trim() ?? '';
    if (photoUrl.isEmpty) {
      return AvatarBadge(label: profile.avatarEmoji, size: 82, border: true);
    }
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 2),
      ),
      child: ClipOval(
        child: OptimizedNetworkImage(
          url: photoUrl,
          width: 82,
          height: 82,
          fit: BoxFit.cover,
          quality: OptimizedImageQuality.thumbnail,
          errorBuilder: (_, __, ___) =>
              AvatarBadge(label: profile.avatarEmoji, size: 82, border: true),
        ),
      ),
    );
  }
}

class _UnavailableProfile extends StatelessWidget {
  const _UnavailableProfile({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              color: AppColors.textGray,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'هذا الملف غير متاح حاليًا.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textGray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPublicCouncils extends StatelessWidget {
  const _NoPublicCouncils();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: Text(
          'لا توجد فرص نشطة لهذا الحساب حاليًا.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textGray,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
