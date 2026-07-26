import 'package:flutter/material.dart';

import '../../core/navigation/profile_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/opportunity_vote_copy.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/opportunity_owner_identity.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/result_bar.dart';
import '../../data/models/comment_model.dart';
import '../../data/models/council_model.dart';
import '../../data/repositories/council_repository.dart';

class ResultDetailsScreen extends StatelessWidget {
  const ResultDetailsScreen({super.key, required this.councilId});

  final String councilId;

  @override
  Widget build(BuildContext context) {
    final repo = CouncilRepository.instance;

    return AnimatedBuilder(
      animation: repo.resultsState,
      builder: (context, _) {
        final sizes = AppSizes.of(context);
        final result = repo.resultById(councilId);
        final council =
            result?.toCouncilModel() ?? repo.findCouncilById(councilId);
        if (council == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                CustomGreenHeader(title: 'تقرير الفرصة', showBack: true),
                Expanded(
                  child: Center(
                    child: Text('تقرير هذه الفرصة غير متاح.'),
                  ),
                ),
              ],
            ),
          );
        }
        final topComments =
            (result?.bestComments ?? council.comments).take(3).toList();
        final summaryText = result?.summaryText ??
            'ظهرت نتيجة الرأي السريع ويمكن مراجعة أبرز الآراء لفهم اتجاه المشاركين.';

        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackground(
            showPattern: false,
            child: Column(
              children: [
                const CustomGreenHeader(title: 'تقرير الفرصة', showBack: true),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      sizes.horizontalPadding,
                      10,
                      sizes.horizontalPadding,
                      18,
                    ),
                    children: [
                      _QuestionReportCard(council: council),
                      const SizedBox(height: 10),
                      _FinalResultCard(council: council),
                      const SizedBox(height: 10),
                      _SummaryCard(summaryText: summaryText),
                      const SizedBox(height: 12),
                      Text(
                        'أفضل 3 آراء',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14.5),
                      ),
                      const SizedBox(height: 8),
                      ...topComments.map(
                        (comment) => _TopCommentCard(
                          comment,
                          onAuthorTap: () =>
                              ProfileNavigation.openCommentAuthor(
                            context,
                            comment,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestionReportCard extends StatelessWidget {
  const _QuestionReportCard({required this.council});

  final CouncilModel council;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.forum_rounded,
            title: 'بطاقة السؤال',
            accent: AppColors.gold,
          ),
          const SizedBox(height: 8),
          Text(
            council.title,
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 15.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            council.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textGray,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          OpportunityOwnerIdentity(
            council: council,
            compact: true,
            onTap: () => ProfileNavigation.openCouncilOwner(context, council),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MetaPill(
                icon: Icons.groups_2_outlined,
                label: '${council.participants} مشارك',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinalResultCard extends StatelessWidget {
  const _FinalResultCard({required this.council});

  final CouncilModel council;

  @override
  Widget build(BuildContext context) {
    final voteCopy = OpportunityVoteCopy.forCouncil(council);

    return _ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.bar_chart_rounded,
            title: 'النتيجة النهائية',
            accent: AppColors.primaryGreen,
          ),
          const SizedBox(height: 7),
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
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summaryText});

  final String summaryText;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: 'خلاصة الفرصة',
            accent: AppColors.gold,
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: .16),
              ),
            ),
            child: Text(
              summaryText,
              style: AppTextStyles.body.copyWith(
                color: AppColors.primaryDarkGreen,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCommentCard extends StatelessWidget {
  const _TopCommentCard(
    this.comment, {
    required this.onAuthorTap,
  });

  final CommentModel comment;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: comment.isBest ? AppColors.gold : AppColors.borderBeige,
          width: comment.isBest ? 1.2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAuthorTap,
            child: AvatarBadge(label: comment.avatarEmoji, size: 36),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onAuthorTap,
                        borderRadius: BorderRadius.circular(7),
                        child: Text(
                          comment.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppTextStyles.cardTitle.copyWith(fontSize: 12.5),
                        ),
                      ),
                    ),
                    if (comment.isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'أفضل رأي',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primaryDarkGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.thumb_up_alt_outlined,
                      size: 14,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.convincingCount} مقنع',
                      style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: accent, size: 15),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.gold),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
