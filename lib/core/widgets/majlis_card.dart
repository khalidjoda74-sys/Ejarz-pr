import 'package:flutter/material.dart';

import '../../data/models/council_model.dart';
import '../../data/models/sponsorship_campaign.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/opportunity_vote_copy.dart';
import 'optimized_network_image.dart';
import 'result_bar.dart';
import 'vote_button.dart';

class MajlisCard extends StatelessWidget {
  const MajlisCard({
    super.key,
    required this.council,
    required this.onVote,
    this.afterTodayCard,
    this.showVotingActions = true,
    this.onOpen,
    this.sponsorship,
    this.onSponsorTap,
    this.onSponsorBookTap,
  });

  final CouncilModel council;
  final ValueChanged<VoteOption> onVote;
  final Widget? afterTodayCard;
  final bool showVotingActions;
  final VoidCallback? onOpen;
  final SponsorshipCampaign? sponsorship;
  final VoidCallback? onSponsorTap;
  final VoidCallback? onSponsorBookTap;

  @override
  Widget build(BuildContext context) {
    final voteCopy = OpportunityVoteCopy.forCouncil(council);

    return Column(
      children: [
        _TodayQuestionCard(
          council: council,
          onOpen: onOpen,
          sponsorship: sponsorship,
          onSponsorTap: onSponsorTap,
          onSponsorBookTap: onSponsorBookTap,
        ),
        if (afterTodayCard != null) ...[
          const SizedBox(height: 12),
          afterTodayCard!,
        ],
        if (showVotingActions) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              voteCopy.prompt,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textGray,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              VoteButton(
                label: voteCopy.labelFor(VoteOption.support),
                icon: voteCopy.iconFor(VoteOption.support),
                option: VoteOption.support,
                colorOverride: voteCopy.colorFor(VoteOption.support),
                selected: council.selectedOption == VoteOption.support,
                onTap: () => _handleVote(context, VoteOption.support),
              ),
              const SizedBox(width: 8),
              VoteButton(
                label: voteCopy.labelFor(VoteOption.against),
                icon: voteCopy.iconFor(VoteOption.against),
                option: VoteOption.against,
                colorOverride: voteCopy.colorFor(VoteOption.against),
                selected: council.selectedOption == VoteOption.against,
                onTap: () => _handleVote(context, VoteOption.against),
              ),
              const SizedBox(width: 8),
              VoteButton(
                label: voteCopy.labelFor(VoteOption.neutral),
                icon: voteCopy.iconFor(VoteOption.neutral),
                option: VoteOption.neutral,
                colorOverride: voteCopy.colorFor(VoteOption.neutral),
                selected: council.selectedOption == VoteOption.neutral,
                onTap: () => _handleVote(context, VoteOption.neutral),
              ),
            ],
          ),
        ],
        if (showVotingActions && council.hasVoted) ...[
          const SizedBox(height: 10),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.support),
            percent: council.supportPercent,
            color: voteCopy.colorFor(VoteOption.support),
          ),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.against),
            percent: council.againstPercent,
            color: voteCopy.colorFor(VoteOption.against),
          ),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.neutral),
            percent: council.neutralPercent,
            color: voteCopy.colorFor(VoteOption.neutral),
          ),
        ],
      ],
    );
  }
  void _handleVote(BuildContext context, VoteOption option) => onVote(option);
}

class _TodayQuestionCard extends StatelessWidget {
  const _TodayQuestionCard({
    required this.council,
    this.onOpen,
    this.sponsorship,
    this.onSponsorTap,
    this.onSponsorBookTap,
  });

  static const _backgroundAsset = 'assets/images/today_majlis_card_bg.png';

  final CouncilModel council;
  final VoidCallback? onOpen;
  final SponsorshipCampaign? sponsorship;
  final VoidCallback? onSponsorTap;
  final VoidCallback? onSponsorBookTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasSponsorSlot = sponsorship != null || onSponsorBookTap != null;
        final cardHeight = (constraints.maxWidth / (hasSponsorSlot ? 1.58 : 1.72))
            .clamp(hasSponsorSlot ? 236.0 : 214.0, hasSponsorSlot ? 264.0 : 238.0)
            .toDouble();

        return GestureDetector(
          onTap: onOpen,
          child: Container(
            width: double.infinity,
            height: cardHeight,
            decoration: BoxDecoration(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _backgroundAsset,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.primaryDarkGreen.withValues(alpha: .03),
                          AppColors.primaryDarkGreen.withValues(alpha: .18),
                        ],
                        stops: const [0, .58, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      hasSponsorSlot ? 14 : 16,
                      16,
                      hasSponsorSlot ? 8 : 12,
                    ),
                    child: Column(
                      children: [
                        _TodayBadge(),
                        SizedBox(height: hasSponsorSlot ? 8 : 11),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    council.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.headline.copyWith(
                                      color: AppColors.cardWhite,
                                      fontSize:
                                          hasSponsorSlot ? 17.4 : 18.6,
                                      height: 1.27,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: AppColors.textDark
                                              .withValues(alpha: .50),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (hasSponsorSlot) ...[
                                  const SizedBox(height: 9),
                                  sponsorship != null
                                      ? _SponsorStrip(
                                          sponsorship: sponsorship!,
                                          onTap: onSponsorTap,
                                        )
                                      : _SponsorInviteStrip(
                                          onTap: onSponsorBookTap,
                                        ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  _FeaturedCategoryPill(
                                    category: council.category,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final sideWidth = (rowConstraints.maxWidth * .25)
                                .clamp(72.0, 96.0)
                                .toDouble();

                            return Row(
                              textDirection: TextDirection.ltr,
                              children: [
                                SizedBox(width: sideWidth),
                                Expanded(
                                  child: Center(
                                    child: _OpinionsRow(
                                      count: council.votesCount,
                                    ),
                                  ),
                                ),
                                SizedBox(width: sideWidth),
                              ],
                            );
                          },
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
}

class _SponsorStrip extends StatelessWidget {
  const _SponsorStrip({
    required this.sponsorship,
    this.onTap,
  });

  final SponsorshipCampaign sponsorship;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryDarkGreen.withValues(alpha: .54),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: .64)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: .18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _SponsorLogo(url: sponsorship.logoUrl),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'برعاية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.gold,
                          fontSize: 9.5,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sponsorship.sponsorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cardWhite,
                          fontSize: 12.4,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 27,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.cardWhite.withValues(alpha: .24),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'اعرف أكثر',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cardWhite,
                          fontSize: 10.4,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: AppColors.gold,
                        size: 13,
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

class _SponsorInviteStrip extends StatelessWidget {
  const _SponsorInviteStrip({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.cardWhite.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: .44)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDarkGreen.withValues(alpha: .36),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .48),
                    ),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: AppColors.gold,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'مساحة إعلان راعي متاحة لهذه الفرصة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.cardWhite,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 27,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      'احجز',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primaryDarkGreen,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w900,
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
}

class _SponsorLogo extends StatelessWidget {
  const _SponsorLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final validImageUrl = uri != null && uri.hasScheme;

    return Container(
      width: 32,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardWhite.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.gold.withValues(alpha: .40)),
      ),
      child: validImageUrl
          ? OptimizedNetworkImage(
              url: url,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              quality: OptimizedImageQuality.thumbnail,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_rounded,
                color: AppColors.primaryDarkGreen,
                size: 18,
              ),
            )
          : const Icon(
              Icons.storefront_rounded,
              color: AppColors.primaryDarkGreen,
              size: 18,
            ),
    );
  }
}

class _FeaturedCategoryPill extends StatelessWidget {
  const _FeaturedCategoryPill({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final label = category.trim();
    if (label.isEmpty) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryDarkGreen.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.gold.withValues(alpha: .44)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.cardWhite.withValues(alpha: .92),
            fontSize: 11.3,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _TodayBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 126,
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.primaryDarkGreen.withValues(alpha: .46),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.gold.withValues(alpha: .54)),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: .16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          'فرصة مميزة',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.cardWhite,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OpinionsRow extends StatelessWidget {
  const _OpinionsRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count <= 0 ? 'كن أول من يبدي رأيه' : '$count رأي';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.how_to_vote_outlined, color: AppColors.gold, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.cardWhite.withValues(alpha: .88),
                fontSize: 11.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
