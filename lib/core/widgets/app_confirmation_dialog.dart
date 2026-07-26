import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
    this.cancelLabel = 'إلغاء',
    this.confirmIcon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final IconData? confirmIcon;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: .16),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: .18),
                        ),
                      ),
                      child: Icon(icon, color: AppColors.red, size: 23),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: 17,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ConfirmationActionButton(
                        label: confirmLabel,
                        icon: confirmIcon ?? icon,
                        destructive: true,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _ConfirmationActionButton(
                        label: cancelLabel,
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmationActionButton extends StatelessWidget {
  const _ConfirmationActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? AppColors.cardWhite : AppColors.textDark;
    final background = destructive ? AppColors.red : AppColors.background;
    final borderColor = destructive
        ? AppColors.red.withValues(alpha: .72)
        : AppColors.borderBeige;

    return SizedBox(
      height: 44,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.button.copyWith(
                      color: foreground,
                      fontSize: 12.4,
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
