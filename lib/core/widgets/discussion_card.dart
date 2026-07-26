import 'package:flutter/material.dart';

import '../../data/models/council_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'opportunity_owner_identity.dart';
import 'relative_time_text.dart';

class DiscussionCard extends StatelessWidget {
  const DiscussionCard({
    super.key,
    required this.council,
    this.onTap,
    this.onOwnerTap,
    this.compact = false,
    this.showRelativeTime = true,
  });

  final CouncilModel council;
  final VoidCallback? onTap;
  final VoidCallback? onOwnerTap;
  final bool compact;
  final bool showRelativeTime;

  Color get statusColor {
    switch (council.status) {
      case CouncilStatus.active:
        return AppColors.green700;
      case CouncilStatus.endingSoon:
        return AppColors.amber;
      case CouncilStatus.closed:
        return AppColors.muted;
    }
  }

  String get statusLabel {
    switch (council.status) {
      case CouncilStatus.active:
        return 'نشط';
      case CouncilStatus.endingSoon:
        return 'ينتهي قريبًا';
      case CouncilStatus.closed:
        return 'منتهي';
    }
  }

  IconData get categoryIcon {
    if (council.category.contains('مشاريع') ||
        council.category.contains('أعمال') ||
        council.category.contains('فلوس')) {
      return Icons.storefront_rounded;
    }
    if (council.category.contains('عقارات') ||
        council.category.contains('أملاك') ||
        council.category.contains('عقار')) {
      return Icons.real_estate_agent_rounded;
    }
    if (council.category.contains('سيارات')) {
      return Icons.directions_car_filled_rounded;
    }
    if (council.category.contains('وظائف') ||
        council.category.contains('مهن') ||
        council.category.contains('رواتب')) {
      return Icons.work_rounded;
    }
    return Icons.forum_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: EdgeInsets.all(compact ? 11 : 13),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: AppColors.borderBeige.withValues(alpha: .86),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F4A35),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _CategoryChip(text: council.category),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    council.title,
                    textAlign: TextAlign.right,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle.copyWith(
                      fontSize: compact ? 14.5 : 15,
                      height: 1.32,
                    ),
                  ),
                  const SizedBox(height: 7),
                  OpportunityOwnerIdentity(
                    council: council,
                    compact: true,
                    onTap: onOwnerTap,
                  ),
                  const SizedBox(height: 7),
                  Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 9,
                          runSpacing: 6,
                          children: [
                            _Meta(
                              icon: Icons.chat_bubble_outline_rounded,
                              text: '${council.commentsCount} تعليق',
                            ),
                            _Meta(
                              icon: Icons.how_to_vote_outlined,
                              text: council.votesCount <= 0
                                  ? 'كن أول من يبدي رأيه'
                                  : '${council.votesCount} رأي',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            _CardSideInfo(
              city: council.city,
              compact: compact,
              createdAt: showRelativeTime ? council.createdAt : null,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Color get _softIconColor {
    switch (council.status) {
      case CouncilStatus.active:
        return AppColors.primaryGreen.withValues(alpha: .10);
      case CouncilStatus.endingSoon:
        return AppColors.warningGold.withValues(alpha: .14);
      case CouncilStatus.closed:
        return AppColors.textGray.withValues(alpha: .10);
    }
  }
}

class _CardSideInfo extends StatelessWidget {
  const _CardSideInfo({
    required this.city,
    required this.compact,
    required this.createdAt,
  });

  final String city;
  final bool compact;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 76.0 : 84.0;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _CityBadge(
              city: city,
              compact: compact,
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 5),
            RelativeTimeText(
              dateTime: createdAt,
              textAlign: TextAlign.left,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textGray.withValues(alpha: .72),
                fontSize: compact ? 9.0 : 9.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CityBadge extends StatelessWidget {
  const _CityBadge({required this.city, required this.compact});

  final String city;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = city.trim().isEmpty ? 'غير محددة' : city.trim();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 76 : 84),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: AppColors.primaryDarkGreen,
            size: 11,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primaryDarkGreen,
                fontSize: compact ? 8.8 : 9.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.borderBeige.withValues(alpha: .54),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primaryDarkGreen,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textGray, size: 13),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.caption.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}
