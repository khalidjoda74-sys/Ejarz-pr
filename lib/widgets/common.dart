import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'illustrations.dart';

class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final bool scrollable;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 18),
    this.maxWidth = 720,
    this.scrollable = true,
    this.controller,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!scrollable) return content;
    final platform = Theme.of(context).platform;
    final defaultPhysics =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const ClampingScrollPhysics();
    return SingleChildScrollView(
      controller: controller,
      physics: physics ?? defaultPhysics,
      child: content,
    );
  }
}

/// A restrained, consistent app bar for entity and transaction details.
///
/// The global theme supplies the transparent surface and hairline divider;
/// this widget standardises navigation, title truncation and action spacing.
class DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final bool backEnabled;
  final List<Widget>? actions;

  const DetailAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.backEnabled = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: backEnabled && onBack == null,
      leading: !backEnabled
          ? const IconButton(
              tooltip: 'الرجوع غير متاح أثناء تنفيذ العملية',
              onPressed: null,
              icon: BackButtonIcon(),
            )
          : onBack == null
              ? null
              : IconButton(
                  tooltip: 'رجوع',
                  onPressed: onBack,
                  icon: const BackButtonIcon(),
                ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: actions,
    );
  }
}

class BrandLogo extends StatelessWidget {
  final double markSize;
  final bool compact;
  final Color? textColor;

  const BrandLogo({
    super.key,
    this.markSize = 34,
    this.compact = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      children: <Widget>[
        BrandMark(size: markSize),
        SizedBox(width: compact ? 6 : 8),
        Text(
          compact ? 'عقود' : 'عقود برو',
          style: TextStyle(
            color: textColor ?? AppColors.primary,
            fontSize: compact ? context.sp(17) : context.sp(18.5),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class BrandHeader extends StatelessWidget {
  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;
  final bool showMenu;
  final bool showNotification;
  final bool showLogo;
  final bool useSplashLogo;
  final IconData menuIcon;
  final bool placeMenuAtStart;
  final Widget? trailing;

  const BrandHeader({
    super.key,
    this.onMenu,
    this.onNotifications,
    this.showMenu = false,
    this.showNotification = true,
    this.showLogo = true,
    this.useSplashLogo = false,
    this.menuIcon = Icons.arrow_back_rounded,
    this.placeMenuAtStart = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLogo && !showNotification && !showMenu && trailing == null) {
      return const SizedBox.shrink();
    }
    final controller = showNotification ? AppScope.of(context) : null;
    final menuButton =
        showMenu ? _HeaderIconButton(icon: menuIcon, onTap: onMenu) : null;
    final content = <Widget>[
      if (showNotification)
        _HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
          badge: controller?.unreadNotifications ?? 0,
        ),
      if (showMenu && !placeMenuAtStart) ...<Widget>[
        const SizedBox(width: 6),
        menuButton!,
      ],
      if (trailing != null) trailing!,
      if (showLogo) ...<Widget>[
        const Spacer(),
        if (useSplashLogo)
          Image.asset(
            'assets/images/ejarz_splash_logo.png',
            height: 44,
            fit: BoxFit.contain,
          )
        else
          const BrandLogo(),
      ],
      if (showMenu && placeMenuAtStart) ...<Widget>[
        const Spacer(),
        menuButton!,
      ],
    ];
    return Row(
      textDirection: TextDirection.ltr,
      children: content,
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;

  const _HeaderIconButton({
    required this.icon,
    this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Material(
          color: context.ejarzTheme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 21, color: context.ejarzTheme.text),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -1,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: context.ejarzTheme.surface, width: 1.5),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}

class EjarzBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  const EjarzBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.ejarzTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: SizedBox(
          height: 50,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: <Widget>[
                _BottomNavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'الرئيسية',
                  selected: currentIndex == 0,
                  onTap: () => onSelect(0),
                ),
                _BottomNavItem(
                  icon: Icons.description_outlined,
                  selectedIcon: Icons.description_rounded,
                  label: 'عقودي',
                  selected: currentIndex == 1,
                  onTap: () => onSelect(1),
                ),
                _BottomCreateItem(onTap: onCreate),
                _BottomNavItem(
                  icon: Icons.apartment_outlined,
                  selectedIcon: Icons.apartment_rounded,
                  label: 'عقاراتي',
                  selected: currentIndex == 2,
                  onTap: () => onSelect(2),
                ),
                _BottomNavItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'حسابي',
                  selected: currentIndex == 3,
                  onTap: () => onSelect(3),
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
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.ejarzTheme.muted;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(selected ? selectedIcon : icon, size: 24, color: color),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: context.sp(11.6),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                    fontFamily: AppTheme.fontFamily,
                    fontFamilyFallback: AppTheme.fontFallback,
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

class _BottomCreateItem extends StatelessWidget {
  final VoidCallback onTap;

  const _BottomCreateItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  top: -18,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.09),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: <Color>[
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.ejarzTheme.surface,
                              width: 3,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.32),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
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
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final Border? border;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadows;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.radius = 12,
    this.border,
    this.onTap,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: padding,
      decoration: appCardDecoration(
        context,
        color: color,
        radius: radius,
        border: border,
        shadows: shadows,
      ),
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: container,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.icon,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 19, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.ejarzTheme.text,
                fontSize: context.sp(15),
                fontWeight: FontWeight.w800,
                height: 1.1,
                fontFamily: AppTheme.fontFamily,
                fontFamilyFallback: AppTheme.fontFallback,
              ),
            ),
          ),
          if (action != null)
            TextButton.icon(
              onPressed: onAction,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 13),
              label: Text(action!),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: TextStyle(
                  fontSize: context.sp(12.4),
                  fontWeight: FontWeight.w800,
                  fontFamily: AppTheme.fontFamily,
                  fontFamilyFallback: AppTheme.fontFallback,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      iconAlignment: IconAlignment.end,
      icon: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.1, color: Colors.white),
            )
          : Icon(icon, size: 21),
      label: Text(label),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, child: Text(label));
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      label: Text(label),
    );
  }
}

class AppTextField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool required;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.suffix,
    this.controller,
    this.focusNode,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            style: TextStyle(
              color: context.ejarzTheme.text,
              fontSize: context.sp(12.3),
              fontWeight: FontWeight.w700,
            ),
            children: <InlineSpan>[
              TextSpan(text: label),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppColors.red),
                ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          initialValue: controller == null ? initialValue : null,
          onChanged: onChanged,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            suffixIcon: suffix ?? (icon == null ? null : Icon(icon, size: 19)),
          ),
        ),
      ],
    );
  }
}

class AppDropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final IconData? icon;
  final bool required;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeItems = <String>{...items, value}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            style: TextStyle(
              color: context.ejarzTheme.text,
              fontSize: context.sp(12.3),
              fontWeight: FontWeight.w700,
            ),
            children: <InlineSpan>[
              TextSpan(text: label),
              if (required)
                const TextSpan(
                    text: ' *', style: TextStyle(color: AppColors.red)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          decoration: InputDecoration(
            suffixIcon: icon == null ? null : Icon(icon, size: 19),
          ),
          items: safeItems
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(item, overflow: TextOverflow.ellipsis),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class DateField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool required;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final FormFieldValidator<String>? validator;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.firstDate,
    this.lastDate,
    this.validator,
  });

  Future<void> _pick(BuildContext context) async {
    final resolvedFirstDate = firstDate ?? DateTime(1950);
    final resolvedLastDate = lastDate ?? DateTime(2100);
    final parts = value.split(RegExp(r'[/\-]'));
    DateTime initialDate = DateTime.now();
    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        final parsed = DateTime(year, month, day);
        if (parsed.year == year && parsed.month == month && parsed.day == day) {
          initialDate = parsed;
        }
      }
    }
    if (initialDate.isBefore(resolvedFirstDate)) {
      initialDate = resolvedFirstDate;
    } else if (initialDate.isAfter(resolvedLastDate)) {
      initialDate = resolvedLastDate;
    }
    final result = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: resolvedFirstDate,
      lastDate: resolvedLastDate,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (result != null) {
      onChanged(
        '${result.year}/${result.month.toString().padLeft(2, '0')}/${result.day.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: ValueKey<String>('date-$label-$value'),
      label: label,
      hint: 'اختر التاريخ',
      initialValue: value,
      readOnly: true,
      onTap: () => _pick(context),
      icon: Icons.calendar_month_outlined,
      required: required,
      validator: validator ??
          (required
              ? (value) => value == null || value.trim().isEmpty
                  ? 'هذا الحقل مطلوب'
                  : null
              : null),
    );
  }
}

class FieldGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final int minColumns;

  const FieldGrid({
    super.key,
    required this.children,
    this.spacing = 10,
    this.minColumns = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 590;
        final columns = twoColumns ? 2 : minColumns;
        if (columns == 1) {
          return Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: children[i]),
                SizedBox(width: spacing),
                Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox()),
              ],
            ),
          );
          if (i + 2 < children.length) rows.add(SizedBox(height: spacing));
        }
        return Column(children: rows);
      },
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const InfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.ejarzTheme.text,
                fontSize: context.sp(12),
                fontWeight: FontWeight.w600,
                height: 1.42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final ContractStatus status;
  final bool compact;

  const StatusChip({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: status.paleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, color: status.color, size: compact ? 13 : 15),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 86 : 130),
            child: Text(
              status.label,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: status.color,
                fontSize: compact ? context.sp(10) : context.sp(11.5),
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool compact;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      radius: compact ? 12 : 14,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 7 : 9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.sp(compact ? 8.2 : 10.2),
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(icon, color: color, size: compact ? 16 : 19),
            ],
          ),
          SizedBox(height: compact ? 5 : 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: context.sp(compact ? 18 : 22),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              fontSize: context.sp(compact ? 8.2 : 9.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ContractListCard extends StatelessWidget {
  final ContractRecord contract;
  final VoidCallback? onTap;
  final bool showOwner;

  const ContractListCard({
    super.key,
    required this.contract,
    this.onTap,
    this.showOwner = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(11),
      radius: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: contract.type == ContractType.residential
                  ? AppColors.primaryLight
                  : AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              contract.type.icon,
              color: contract.type == ContractType.residential
                  ? AppColors.primary
                  : const Color(0xFFA27008),
              size: 22,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  contract.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.sp(13),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'رقم الطلب: ${contract.requestNumber}',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(10.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: <Widget>[
                    _MetaText(
                        icon: Icons.location_on_outlined,
                        text: contract.property),
                    _MetaText(
                        icon: Icons.calendar_month_outlined,
                        text: contract.date),
                    if (showOwner)
                      _MetaText(
                          icon: Icons.person_outline_rounded,
                          text: contract.lessorName),
                  ],
                ),
                if (contract.pendingSync) ...<Widget>[
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 14,
                        color: AppColors.orange,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'محفوظ محليًا وينتظر المزامنة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.orange,
                            fontSize: context.sp(10.5),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: <Widget>[
              StatusChip(status: contract.status, compact: true),
              const SizedBox(height: 6),
              Icon(Icons.arrow_back_ios_new_rounded,
                  size: 15, color: context.ejarzTheme.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: context.ejarzTheme.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontSize: context.sp(10),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WizardProgress extends StatelessWidget {
  final List<String> labels;
  final int current;

  const WizardProgress({
    super.key,
    required this.labels,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final circle = constraints.maxWidth < 360 ? 22.0 : 25.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < labels.length; i++) ...<Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (i > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i <= current
                                  ? AppColors.primary
                                  : context.ejarzTheme.border,
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          width: circle,
                          height: circle,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < current
                                ? AppColors.primary
                                : i == current
                                    ? Colors.white
                                    : context.ejarzTheme.surface,
                            border: Border.all(
                              color: i <= current
                                  ? AppColors.primary
                                  : context.ejarzTheme.border,
                              width: i == current ? 3 : 1.5,
                            ),
                          ),
                          child: Center(
                            child: i < current
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 15)
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: i == current
                                          ? AppColors.primary
                                          : context.ejarzTheme.muted,
                                      fontWeight: FontWeight.w800,
                                      fontSize: context.sp(10.2),
                                    ),
                                  ),
                          ),
                        ),
                        if (i < labels.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i < current
                                  ? AppColors.primary
                                  : context.ejarzTheme.border,
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i == current
                            ? AppColors.primary
                            : context.ejarzTheme.muted,
                        fontSize: context.sp(8.8),
                        fontWeight:
                            i == current ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class SegmentedChoice<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelBuilder;
  final IconData Function(T)? iconBuilder;
  final ValueChanged<T> onChanged;

  const SegmentedChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
    this.iconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.ejarzTheme.surface,
        border: Border.all(color: context.ejarzTheme.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          for (final value in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: value == selected
                        ? Border.all(color: AppColors.primary)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (iconBuilder != null) ...<Widget>[
                        Icon(
                          iconBuilder!(value),
                          size: 17,
                          color: value == selected
                              ? AppColors.primary
                              : context.ejarzTheme.muted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          labelBuilder(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: value == selected
                                ? AppColors.primary
                                : context.ejarzTheme.text,
                            fontSize: context.sp(12),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ToggleCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const ToggleCard({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shadows: const <BoxShadow>[],
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
          secondary: icon == null
              ? null
              : Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(10.8)),
                ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
      child: Column(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
                color: AppColors.primaryLight, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ejarzTheme.muted, height: 1.55),
          ),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: 220,
              child: PrimaryButton(label: actionLabel!, onPressed: onAction),
            ),
          ],
        ],
      ),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(12),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class LoadingOverlay extends StatelessWidget {
  final bool visible;
  final Widget child;
  final String label;

  const LoadingOverlay({
    super.key,
    required this.visible,
    required this.child,
    this.label = 'جارٍ المعالجة...',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        if (visible)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.28),
              child: Center(
                child: AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 14),
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
