import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/connection_status_banner.dart';
import '../../core/widgets/discussion_card.dart';
import '../../core/widgets/majlis_card.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/council_model.dart';
import '../../data/models/sponsorship_campaign.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenCouncil,
    required this.onOpenCategory,
    required this.onOpenMessages,
    required this.onOpenNotifications,
  });

  final ValueChanged<String> onOpenCouncil;
  final ValueChanged<String> onOpenCategory;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenNotifications;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _homeHorizontalPadding = 10;
  final PageController _featuredPageController = PageController();
  Timer? _featuredCarouselTimer;
  int _featuredPage = 0;

  @override
  void initState() {
    super.initState();
    _featuredCarouselTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _advanceFeaturedCarousel(),
    );
  }

  void _advanceFeaturedCarousel() {
    if (!mounted || !_featuredPageController.hasClients) return;

    final nextPage = (_featuredPage + 1) % 3;
    _featuredPageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 1300),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _featuredCarouselTimer?.cancel();
    _featuredPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = CouncilRepository.instance;
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        final sizes = AppSizes.of(context);
        final featuredCouncil = _homeFeaturedCouncil(repo);
        final active = _mostInteractiveCouncils(
          repo.activeCouncils,
          featuredCouncilId: featuredCouncil.id,
        ).take(4).toList();
        final bottomPadding =
            sizes.bottomNavHeight + 18 + MediaQuery.viewPaddingOf(context).bottom;
        final topInset = MediaQuery.viewPaddingOf(context).top;
        final headerBackdropHeight = topInset + 78;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
            child: PremiumBackground(
            showPattern: false,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerBackdropHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFFFFAEF),
                            Color(0xFFF7EFD7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryDarkGreen.withValues(alpha: .05),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            SafeArea(
              bottom: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  _homeHorizontalPadding,
                  12,
                  _homeHorizontalPadding,
                  bottomPadding,
                ),
                children: [
                  SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PositionedDirectional(
                          start: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: SizedBox(
                              width: 120,
                              height: 40,
                              child: Image.asset(
                                'assets/images/forsa_pro_logo_header.png',
                                alignment: Alignment.centerRight,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                semanticLabel: 'فرصة برو',
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          end: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StreamBuilder<int>(
                                  stream: MessagingRepository.instance
                                      .watchUnreadTotal(),
                                  builder: (context, snapshot) => _MessageButton(
                                    onTap: widget.onOpenMessages,
                                    count: snapshot.data ?? 0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _NotificationButton(
                                  onTap: widget.onOpenNotifications,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _HomeFeaturedCarousel(
                    controller: _featuredPageController,
                    activeIndex: _featuredPage,
                    onPageChanged: (value) =>
                        setState(() => _featuredPage = value),
                    council: featuredCouncil,
                    onVote: (option) {
                      if (featuredCouncil.isVotingClosed) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'هذه الفرصة غير متاحة للتصويت حاليًا، ويمكنك متابعة النقاش والتعليق.',
                            ),
                          ),
                        );
                        return;
                      }

                      AuthGuard.requireAuth(context, () async {
                        try {
                          await repo.vote(featuredCouncil.id, option);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تسجيل رأيك السريع في الفرصة'),
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تعذر تسجيل الرأي. حاول مرة أخرى.',
                              ),
                            ),
                          );
                        }
                      });
                    },
                    onOpen: () => widget.onOpenCouncil(featuredCouncil.id),
                    showVotingActions: false,
                    afterTodayCard: _HomeCategoryStrip(
                      categories: repo.categories,
                      onSelected: widget.onOpenCategory,
                    ),
                  ),
                  _HomeAdSlot(onOpenCouncil: widget.onOpenCouncil),
                  if (repo.hasConnectionIssue) ...[
                    const SizedBox(height: 12),
                    ConnectionStatusBanner(
                      lastUpdatedAt: repo.lastRemoteSyncAt,
                      onRetry: repo.retryFirestoreSync,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SectionHeader(
                    title: 'أكثر الفرص تفاعلًا',
                    actionText: 'عرض الكل',
                    onAction: () => widget.onOpenCategory('الكل'),
                  ),
                  const SizedBox(height: 8),
                  ...active.map(
                    (council) => DiscussionCard(
                      council: council,
                      compact: true,
                      onTap: () => widget.onOpenCouncil(council.id),
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
  List<CouncilModel> _mostInteractiveCouncils(
    List<CouncilModel> councils, {
    required String featuredCouncilId,
  }) {
    final sorted = councils
        .where((council) => council.id != featuredCouncilId)
        .toList(growable: false);

    sorted.sort((a, b) {
      final scoreCompare =
          _interactionScore(b).compareTo(_interactionScore(a));
      if (scoreCompare != 0) return scoreCompare;

      final bCreatedAt = b.createdAt;
      final aCreatedAt = a.createdAt;
      if (bCreatedAt != null && aCreatedAt != null) {
        return bCreatedAt.compareTo(aCreatedAt);
      }
      if (bCreatedAt != null) return 1;
      if (aCreatedAt != null) return -1;
      return b.id.compareTo(a.id);
    });

    return sorted;
  }

  int _interactionScore(CouncilModel council) {
    return (council.commentsCount * 3) + council.votesCount;
  }

  CouncilModel _homeFeaturedCouncil(CouncilRepository repo) {
    for (final council in repo.activeCouncils) {
      if (council.id.startsWith('demo_laundry_')) return council;
    }
    for (final council in repo.activeCouncils) {
      if (council.title.contains('مغسلة')) return council;
    }
    return repo.todayCouncil;
  }
}

class _HomeFeaturedCarousel extends StatelessWidget {
  const _HomeFeaturedCarousel({
    required this.controller,
    required this.activeIndex,
    required this.onPageChanged,
    required this.council,
    required this.onVote,
    required this.onOpen,
    required this.showVotingActions,
    this.afterTodayCard,
  });

  static const _carShowroomAsset = 'assets/images/home_ad_car_showroom.png';
  static const _projectSetupAsset = 'assets/images/home_ad_project_setup.png';

  final PageController controller;
  final int activeIndex;
  final ValueChanged<int> onPageChanged;
  final CouncilModel council;
  final ValueChanged<VoteOption> onVote;
  final VoidCallback onOpen;
  final bool showVotingActions;
  final Widget? afterTodayCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight =
                (constraints.maxWidth / 1.72).clamp(214.0, 238.0).toDouble();

            return SizedBox(
              height: cardHeight,
              child: PageView(
                controller: controller,
                onPageChanged: onPageChanged,
                physics: const BouncingScrollPhysics(),
                children: [
                  MajlisCard(
                    council: council,
                    onVote: onVote,
                    onOpen: onOpen,
                    showVotingActions: showVotingActions,
                  ),
                  const _HomeImageBanner(
                    asset: _carShowroomAsset,
                    backgroundColor: Color(0xFF001A38),
                  ),
                  const _HomeImageBanner(
                    asset: _projectSetupAsset,
                    backgroundColor: Color(0xFFF8F6F1),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _HomeFeaturedDots(activeIndex: activeIndex),
        if (afterTodayCard != null) ...[
          const SizedBox(height: 12),
          afterTodayCard!,
        ],
      ],
    );
  }
}

class _HomeImageBanner extends StatelessWidget {
  const _HomeImageBanner({
    required this.asset,
    required this.backgroundColor,
  });

  final String asset;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: .82)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDarkGreen.withValues(alpha: .14),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _HomeFeaturedDots extends StatelessWidget {
  const _HomeFeaturedDots({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final current = activeIndex < 0 ? 0 : (activeIndex > 2 ? 2 : activeIndex);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final selected = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: selected ? 18 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold
                : AppColors.primaryDarkGreen.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _HomeAdSlot extends StatefulWidget {
  const _HomeAdSlot({required this.onOpenCouncil});

  final ValueChanged<String> onOpenCouncil;

  @override
  State<_HomeAdSlot> createState() => _HomeAdSlotState();
}

class _HomeAdSlotState extends State<_HomeAdSlot> {
  final _sponsorshipRepo = SponsorshipRepository.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SponsorshipCampaign?>(
      stream: _sponsorshipRepo.watchActiveHomePlacement(),
      builder: (context, snapshot) {
        final ad = snapshot.data;
        if (ad == null) return const SizedBox.shrink();

        _recordImpression(ad);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _HomeAdCard(
            ad: ad,
            onTap: () => _openAd(ad),
          ),
        );
      },
    );
  }

  void _recordImpression(SponsorshipCampaign ad) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sponsorshipRepo.recordImpression(ad.id));
    });
  }

  Future<void> _openAd(SponsorshipCampaign ad) async {
    if (ad.placement == AdPlacement.homeFeaturedCouncil &&
        ad.councilId?.isNotEmpty == true) {
      unawaited(_sponsorshipRepo.recordClick(ad.id));
      widget.onOpenCouncil(ad.councilId!);
      return;
    }

    final uri = Uri.tryParse(ad.targetUrl);
    if (uri == null || !uri.hasScheme) return;

    unawaited(_sponsorshipRepo.recordClick(ad.id));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _HomeAdCard extends StatelessWidget {
  const _HomeAdCard({
    required this.ad,
    required this.onTap,
  });

  final SponsorshipCampaign ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBanner = ad.placement == AdPlacement.homeBanner;
    final badge = isBanner ? 'إعلان' : 'فرصة مميزة';
    final title = ad.title.isNotEmpty
        ? ad.title
        : (isBanner ? ad.sponsorName : ad.packageLabel);
    final subtitle = ad.description.isNotEmpty
        ? ad.description
        : (isBanner
            ? 'بنر رئيسي برعاية ${ad.sponsorName}'
            : 'نقاش مثبت في الرئيسية برعاية ${ad.sponsorName}');

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        height: 154,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isBanner
              ? const LinearGradient(
                  colors: [Color(0xFF143B31), Color(0xFF2F735F)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                )
              : null,
          color: isBanner ? null : AppColors.cardWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isBanner
                ? AppColors.gold.withValues(alpha: .42)
                : AppColors.borderBeige,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F4A35),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: isBanner
                    ? AppColors.cardWhite.withValues(alpha: .12)
                    : AppColors.primaryGreen.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isBanner
                    ? Icons.view_carousel_rounded
                    : Icons.push_pin_rounded,
                color: isBanner ? AppColors.gold : AppColors.primaryDarkGreen,
                size: 29,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeAdBadge(label: badge, dark: isBanner),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle.copyWith(
                      color: isBanner ? AppColors.cardWhite : AppColors.textDark,
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: isBanner
                          ? AppColors.cardWhite.withValues(alpha: .84)
                          : AppColors.textGray,
                      fontSize: 11.3,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: isBanner ? AppColors.gold : AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAdBadge extends StatelessWidget {
  const _HomeAdBadge({required this.label, required this.dark});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.cardWhite.withValues(alpha: .13)
            : AppColors.primaryGreen.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? AppColors.gold.withValues(alpha: .40)
              : AppColors.primaryGreen.withValues(alpha: .22),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: dark ? AppColors.cardWhite : AppColors.primaryDarkGreen,
          fontSize: 10.4,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HomeCategoryStrip extends StatefulWidget {
  const _HomeCategoryStrip({
    required this.categories,
    required this.onSelected,
  });

  final List<String> categories;
  final ValueChanged<String> onSelected;

  @override
  State<_HomeCategoryStrip> createState() => _HomeCategoryStripState();
}

class _HomeCategoryStripState extends State<_HomeCategoryStrip> {
  final ScrollController _scrollController = ScrollController();
  bool _playedDiscovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playDiscoveryAnimation();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _categoryItems(widget.categories);

    return Container(
      width: double.infinity,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _categoryRowChildren(items),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playDiscoveryAnimation() async {
    if (_playedDiscovery) return;
    _playedDiscovery = true;

    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (!mounted || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll < 12) return;

    await _scrollController.animateTo(
      maxScroll,
      duration: const Duration(milliseconds: 820),
      curve: Curves.easeInOutCubic,
    );

    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted || !_scrollController.hasClients) return;

    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeInOutCubic,
    );
  }

  List<Widget> _categoryRowChildren(List<_HomeCategory> items) {
    final children = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final selected = item.label == 'الكل';

      children.add(
        SizedBox(
          width: selected ? 54 : 66,
          child: _HomeCategoryItem(
            item: item,
            selected: selected,
            onTap: () => widget.onSelected(item.category),
          ),
        ),
      );

      if (index < items.length - 1) {
        final nextSelected = items[index + 1].label == 'الكل';
        children.add(
          _CategorySeparator(hidden: selected || nextSelected),
        );
      }
    }
    return children;
  }

  List<_HomeCategory> _categoryItems(List<String> source) {
    _HomeCategory itemFor(String raw) {
      if (raw.contains('تقبيل') ||
          raw.contains('للبيع') ||
          raw.contains('بيع') ||
          raw.contains('تنازل') ||
          raw.contains('محل') ||
          raw.contains('كوفي') ||
          raw.contains('مغسلة') ||
          raw.contains('صالون') ||
          raw.contains('ورشة')) {
        return const _HomeCategory(
          category: 'فرص للتقبيل',
          label: 'فرص للتقبيل',
          icon: Icons.storefront_rounded,
        );
      }
      if (raw.contains('مطلوبة') ||
          raw.contains('مطلوب') ||
          raw.contains('أبحث') ||
          raw.contains('ابحث') ||
          raw.contains('ميزانية')) {
        return const _HomeCategory(
          category: 'فرص مطلوبة',
          label: 'فرص مطلوبة',
          icon: Icons.manage_search_rounded,
        );
      }
      if (raw.contains('شراكة') ||
          raw.contains('شريك') ||
          raw.contains('شركاء') ||
          raw.contains('ممول') ||
          raw.contains('تشغيل') ||
          raw.contains('تسويق')) {
        return const _HomeCategory(
          category: 'فرص شراكة',
          label: 'فرص شراكة',
          icon: Icons.handshake_rounded,
        );
      }
      return const _HomeCategory(
        category: 'تجارب السوق',
        label: 'تجارب السوق',
        icon: Icons.insights_rounded,
      );
    }

    final preferredOrder = [
      'الكل',
      'فرص للتقبيل',
      'فرص مطلوبة',
      'فرص شراكة',
      'تجارب السوق',
    ];
    final mapped = <String, _HomeCategory>{};

    for (final raw in source) {
      final item = raw == 'الكل'
          ? const _HomeCategory(
              category: 'الكل',
              label: 'الكل',
              icon: Icons.grid_view_rounded,
            )
          : itemFor(raw);
      if (preferredOrder.contains(item.label)) {
        mapped.putIfAbsent(item.label, () => item);
      }
    }

    return [
      for (final label in preferredOrder)
        mapped[label] ??
            _HomeCategory(
              category: _categoryValueForLabel(label),
              label: label,
              icon: label == 'الكل' ? Icons.grid_view_rounded : Icons.circle,
            ),
    ];
  }

  String _categoryValueForLabel(String label) {
    switch (label) {
      case 'فرص للتقبيل':
      case 'فرص مطلوبة':
      case 'فرص شراكة':
      case 'تجارب السوق':
        return label;
      default:
        return 'الكل';
    }
  }
}

class _HomeCategoryItem extends StatelessWidget {
  const _HomeCategoryItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _HomeCategory item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? AppColors.cardWhite : AppColors.primaryDarkGreen;
    final iconColor = selected ? AppColors.gold : _iconColor(item.label);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.headerGradient : null,
              color: selected ? null : AppColors.cardWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppColors.gold.withValues(alpha: .44)
                    : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color:
                            AppColors.primaryDarkGreen.withValues(alpha: .14),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _CategoryIconMark(
                  icon: item.icon,
                  color: iconColor,
                  selected: selected,
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 21,
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: foreground,
                        fontSize: 9.8,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                        height: 1.05,
                      ),
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

  Color _iconColor(String label) {
    switch (label) {
      case 'فرص للتقبيل':
        return AppColors.primaryGreen;
      case 'فرص مطلوبة':
        return AppColors.primaryDarkGreen;
      case 'فرص شراكة':
        return AppColors.warningGold;
      case 'تجارب السوق':
        return AppColors.warningGold;
      default:
        return AppColors.primaryDarkGreen;
    }
  }
}

class _CategorySeparator extends StatelessWidget {
  const _CategorySeparator({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      height: double.infinity,
      child: Center(
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 1,
            height: 27,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.borderBeige.withValues(alpha: 0),
                  AppColors.borderBeige.withValues(alpha: .68),
                  AppColors.borderBeige.withValues(alpha: .68),
                  AppColors.borderBeige.withValues(alpha: 0),
                ],
                stops: const [0, .22, .78, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryIconMark extends StatelessWidget {
  const _CategoryIconMark({
    required this.icon,
    required this.color,
    required this.selected,
  });

  final IconData icon;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 23,
      height: 23,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: AppColors.cardWhite.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: .38),
                ),
              ),
            ),
          Icon(icon, size: 20, color: color),
        ],
      ),
    );
  }
}

class _HomeCategory {
  const _HomeCategory({
    required this.category,
    required this.label,
    required this.icon,
  });

  final String category;
  final String label;
  final IconData icon;
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F4A35),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.primaryDarkGreen,
              size: 20,
            ),
          ),
          Positioned(
            top: 3,
            left: 3,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageButton extends StatelessWidget {
  const _MessageButton({required this.onTap, required this.count});

  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final displayCount = count > 99 ? '99+' : '$count';
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F4A35),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_chat_unread_outlined,
              color: AppColors.primaryDarkGreen,
              size: 20,
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              left: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.cardWhite, width: 1.5),
                ),
                child: Text(
                  displayCount,
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.cardWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
