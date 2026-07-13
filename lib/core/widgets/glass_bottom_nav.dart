import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_sizes.dart';
import '../theme/app_text_styles.dart';

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.profileBadgeCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int profileBadgeCount;

  static const _items = [
    _NavItem('الرئيسية', Icons.home_rounded, Icons.home_outlined),
    _NavItem('الفرص', Icons.groups_rounded, Icons.groups_outlined),
    _NavItem('أنشئ', Icons.add_rounded, Icons.add_rounded),
    _NavItem('نشاطي', Icons.bar_chart_rounded, Icons.bar_chart_outlined),
    _NavItem('حسابي', Icons.account_circle_rounded, Icons.account_circle_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final navHeight = sizes.bottomNavHeight.clamp(66, 70).toDouble();
    final iconSize = sizes.bottomNavIcon.clamp(23, 25).toDouble();
    final labelSize = sizes.bottomNavLabel.clamp(12, 13).toDouble();
    final centerSize = sizes.centerAddButton.clamp(52, 56).toDouble();
    final totalHeight = navHeight + 14;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: AppColors.cardWhite,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: AppColors.borderBeige,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        bottom: true,
        child: SizedBox(
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: navHeight,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardWhite.withValues(alpha: .92),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: AppColors.borderBeige.withValues(alpha: .72),
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.primaryDarkGreen.withValues(alpha: .11),
                            blurRadius: 16,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Row(
                          children: List.generate(_items.length, (index) {
                            final item = _items[index];
                            final selected = currentIndex == index;

                            if (index == 2) {
                              return Expanded(
                                child: SizedBox(height: navHeight),
                              );
                            }

                            return Expanded(
                              child: _BottomNavItem(
                                buttonKey: ValueKey('bottom_nav_$index'),
                                item: item,
                                selected: selected,
                                iconSize: iconSize,
                                labelSize: labelSize,
                                badgeCount: index == 4 ? profileBadgeCount : 0,
                                onTap: () => onTap(index),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: _CenterCreateButton(
                  buttonKey: const ValueKey('bottom_nav_2'),
                  label: _items[2].label,
                  selected: currentIndex == 2,
                  size: centerSize,
                  onTap: () => onTap(2),
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

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.buttonKey,
    required this.item,
    required this.selected,
    required this.iconSize,
    required this.labelSize,
    required this.badgeCount,
    required this.onTap,
  });

  final Key buttonKey;
  final _NavItem item;
  final bool selected;
  final double iconSize;
  final double labelSize;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryDarkGreen : AppColors.textGray;
    final icon = selected ? item.activeIcon : item.icon;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 40 : 34,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryDarkGreen.withValues(alpha: .08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: selected ? 1.05 : 1,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(icon, size: iconSize, color: color),
                      if (badgeCount > 0)
                        PositionedDirectional(
                          top: -7,
                          end: -9,
                          child: _BottomNavBadge(count: badgeCount),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.navLabel.copyWith(
                  color: color,
                  fontSize: labelSize,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavBadge extends StatelessWidget {
  const _BottomNavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cardWhite, width: 1.2),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.cardWhite,
          fontSize: 8.8,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _CenterCreateButton extends StatefulWidget {
  const _CenterCreateButton({
    required this.buttonKey,
    required this.label,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  State<_CenterCreateButton> createState() => _CenterCreateButtonState();
}

class _CenterCreateButtonState extends State<_CenterCreateButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _pressed;
    final dockSize = widget.size + 4;
    final haloSize = active ? dockSize + 14 : dockSize + 8;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        key: widget.buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: SizedBox(
          width: haloSize + 8,
          height: haloSize + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeOutCubic,
                width: haloSize,
                height: haloSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: active ? .13 : .06),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: active ? .32 : .16),
                    width: 1.2,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeOutCubic,
                width: dockSize,
                height: dockSize,
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: .98),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cardWhite,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDarkGreen.withValues(alpha: .10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOutCubic,
                scale: _pressed ? .92 : (widget.selected ? 1.04 : 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOutCubic,
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.cardWhite.withValues(alpha: .86),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDarkGreen.withValues(
                          alpha: active ? .28 : .20,
                        ),
                        blurRadius: active ? 16 : 11,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    turns: _pressed ? .035 : 0,
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.cardWhite,
                      size: 30,
                    ),
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

class _NavItem {
  const _NavItem(this.label, this.activeIcon, this.icon);

  final String label;
  final IconData activeIcon;
  final IconData icon;
}