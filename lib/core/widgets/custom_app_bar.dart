import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_sizes.dart';
import '../theme/app_text_styles.dart';

class CustomGreenHeader extends StatelessWidget {
  const CustomGreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.height = 96,
    this.showBack = false,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final double height;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final effectiveHeight = _effectiveHeight(height, sizes);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final minimumContentHeight = subtitle == null ? 54.0 : 64.0;
    final containerHeight = effectiveHeight < topInset + minimumContentHeight
        ? topInset + minimumContentHeight
        : effectiveHeight;
    final titleSidePadding = sizes.horizontalPadding + 54;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: containerHeight,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppColors.headerGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x140F4A35),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showBack)
                  PositionedDirectional(
                    start: sizes.horizontalPadding,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _RoundIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: onBack ?? () => Navigator.of(context).maybePop(),
                        compact: true,
                      ),
                    ),
                  ),
                if (trailing != null)
                  PositionedDirectional(
                    end: sizes.horizontalPadding,
                    top: 0,
                    bottom: 0,
                    child: Center(child: trailing!),
                  ),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: titleSidePadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.pageTitle.copyWith(
                            color: AppColors.cardWhite,
                            fontSize:
                                sizes.pageTitleFont.clamp(18, 19).toDouble(),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: sizes.itemSpacing * .5),
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.cardWhite.withValues(alpha: .78),
                              fontSize:
                                  sizes.captionFont.clamp(11.5, 12.5).toDouble(),
                            ),
                          ),
                        ],
                      ],
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

  double _effectiveHeight(double requestedHeight, AppSizes sizes) {
    if (requestedHeight > 150) {
      return requestedHeight.clamp(105, 150).toDouble();
    }
    final responsiveHeight = requestedHeight * sizes.scale;
    return responsiveHeight.clamp(90, 104).toDouble();
  }
}

class HeaderRoundButton extends StatelessWidget {
  const HeaderRoundButton({
    super.key,
    required this.icon,
    this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) =>
      _RoundIconButton(icon: icon, onTap: onTap, badge: badge);
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    this.onTap,
    this.badge = false,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final baseButtonSize = compact ? 24.0 : 36.0;
    final baseIconSize = compact ? 14.0 : 20.0;
    final buttonSize = (baseButtonSize * sizes.scale)
        .clamp(compact ? 23 : 34, compact ? 26 : 38)
        .toDouble();
    final iconSize = (baseIconSize * sizes.scale)
        .clamp(compact ? 13 : 19, compact ? 15 : 21)
        .toDouble();
    final tapSize = compact ? 40.0 : buttonSize;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: tapSize,
        height: tapSize,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: AppColors.cardWhite.withValues(alpha: .16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cardWhite.withValues(alpha: .20),
                  ),
                ),
                child: Icon(icon, color: AppColors.cardWhite, size: iconSize),
              ),
              if (badge)
                Positioned(
                  left: 0,
                  top: 1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
