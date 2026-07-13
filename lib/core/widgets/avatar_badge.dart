import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const businessAvatarOptions = [
  'business:person_growth',
  'business:storefront',
  'business:handshake',
  'business:funding',
  'business:growth',
  'business:briefcase',
  'business:marketing',
  'business:search',
  'business:verified',
  'business:idea',
  'business:transfer',
  'business:experience',
];

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.label,
    this.size = 42,
    this.backgroundColor,
    this.border = false,
  });

  final String label;
  final double size;
  final Color? backgroundColor;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final businessStyle = businessAvatarStyle(label);
    if (businessStyle != null) {
      return _BusinessAvatarBadge(
        label: label,
        style: businessStyle,
        size: size,
        border: border,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.goldLight,
        shape: BoxShape.circle,
        border:
            border ? Border.all(color: AppColors.cardWhite, width: 3) : null,
        boxShadow: border
            ? const [
                BoxShadow(
                  color: Color(0x180F4A35),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * .45,
          height: 1,
        ),
      ),
    );
  }
}

class BusinessAvatarStyle {
  const BusinessAvatarStyle({
    required this.icon,
    required this.accent,
    required this.surface,
  });

  final IconData icon;
  final Color accent;
  final Color surface;
}

BusinessAvatarStyle? businessAvatarStyle(String label) {
  switch (label) {
    case 'business:person_growth':
      return const BusinessAvatarStyle(
        icon: Icons.person_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:storefront':
      return const BusinessAvatarStyle(
        icon: Icons.storefront_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:handshake':
      return const BusinessAvatarStyle(
        icon: Icons.handshake_rounded,
        accent: Color(0xFFB78A2A),
        surface: Color(0xFFFFF6DD),
      );
    case 'business:funding':
      return const BusinessAvatarStyle(
        icon: Icons.account_balance_wallet_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:growth':
      return const BusinessAvatarStyle(
        icon: Icons.trending_up_rounded,
        accent: Color(0xFFB78A2A),
        surface: Color(0xFFFFF6DD),
      );
    case 'business:briefcase':
      return const BusinessAvatarStyle(
        icon: Icons.business_center_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:marketing':
      return const BusinessAvatarStyle(
        icon: Icons.campaign_rounded,
        accent: Color(0xFFB78A2A),
        surface: Color(0xFFFFF6DD),
      );
    case 'business:search':
      return const BusinessAvatarStyle(
        icon: Icons.manage_search_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:verified':
      return const BusinessAvatarStyle(
        icon: Icons.verified_rounded,
        accent: Color(0xFFB78A2A),
        surface: Color(0xFFFFF6DD),
      );
    case 'business:idea':
      return const BusinessAvatarStyle(
        icon: Icons.tips_and_updates_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
    case 'business:transfer':
      return const BusinessAvatarStyle(
        icon: Icons.sell_rounded,
        accent: Color(0xFFB78A2A),
        surface: Color(0xFFFFF6DD),
      );
    case 'business:experience':
      return const BusinessAvatarStyle(
        icon: Icons.insights_rounded,
        accent: Color(0xFF0F6B4E),
        surface: Color(0xFFEAF4EF),
      );
  }
  if (label.startsWith('business:')) {
    return businessAvatarStyle('business:person_growth');
  }
  return null;
}

class _BusinessAvatarBadge extends StatelessWidget {
  const _BusinessAvatarBadge({
    required this.label,
    required this.style,
    required this.size,
    required this.border,
  });

  final String label;
  final BusinessAvatarStyle style;
  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * .48;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.cardWhite,
            style.surface,
          ],
        ),
        border: Border.all(
          color: border
              ? AppColors.cardWhite
              : style.accent.withValues(alpha: .24),
          width: border ? 3 : 1,
        ),
        boxShadow: border
            ? const [
                BoxShadow(
                  color: Color(0x180F4A35),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: label == 'business:person_growth'
          ? Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.person_rounded,
                  color: style.accent,
                  size: iconSize,
                ),
                PositionedDirectional(
                  start: size * .22,
                  top: size * .19,
                  child: Icon(
                    Icons.trending_up_rounded,
                    color: AppColors.gold,
                    size: size * .27,
                  ),
                ),
              ],
            )
          : Icon(
              style.icon,
              color: style.accent,
              size: iconSize,
            ),
    );
  }
}