import 'package:flutter/material.dart';

import '../../data/models/council_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'avatar_badge.dart';
import 'optimized_network_image.dart';

class OpportunityOwnerIdentity extends StatelessWidget {
  const OpportunityOwnerIdentity({
    super.key,
    required this.council,
    this.onDark = false,
    this.compact = false,
    this.avatarSize,
    this.onTap,
  });

  final CouncilModel council;
  final bool onDark;
  final bool compact;
  final double? avatarSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = avatarSize ?? (compact ? 32.0 : 42.0);
    final nameColor = onDark ? AppColors.cardWhite : AppColors.primaryDarkGreen;
    final categoryColor = onDark
        ? AppColors.goldLight.withValues(alpha: .96)
        : AppColors.textGray;

    return Semantics(
      label: '${council.ownerDisplayName}، ${council.category}',
      container: true,
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _OwnerAvatar(
                council: council,
                size: size,
                onDark: onDark,
              ),
              SizedBox(width: compact ? 8 : 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      council.ownerDisplayName,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: nameColor,
                        fontSize: compact ? 11.5 : 13.5,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 4),
                    Text(
                      council.category,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: categoryColor,
                        fontSize: compact ? 9.5 : 10.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
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
  }
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({
    required this.council,
    required this.size,
    required this.onDark,
  });

  final CouncilModel council;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final photoUrl = council.createdByPhotoUrl?.trim() ?? '';
    if (photoUrl.isEmpty) return _fallback();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: onDark
              ? AppColors.cardWhite.withValues(alpha: .90)
              : AppColors.gold.withValues(alpha: .56),
          width: onDark ? 1.8 : 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F4A35),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: OptimizedNetworkImage(
          url: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          quality: OptimizedImageQuality.thumbnail,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _fallback();
          },
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return AvatarBadge(
      label: council.ownerAvatarLabel,
      size: size,
      border: onDark,
    );
  }
}
