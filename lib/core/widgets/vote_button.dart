import 'package:flutter/material.dart';

import '../../data/models/council_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class VoteButton extends StatelessWidget {
  const VoteButton({
    super.key,
    required this.label,
    required this.icon,
    required this.option,
    required this.onTap,
    this.selected = false,
    this.colorOverride,
  });

  final String label;
  final IconData icon;
  final VoteOption option;
  final VoidCallback onTap;
  final bool selected;
  final Color? colorOverride;

  Color get color {
    final override = colorOverride;
    if (override != null) return override;
    switch (option) {
      case VoteOption.support:
        return AppColors.green700;
      case VoteOption.against:
        return AppColors.red;
      case VoteOption.neutral:
        return AppColors.amber;
    }
  }

  Color get softColor {
    return color.withValues(alpha: .12);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 70,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F4A35),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.cardWhite.withValues(alpha: .20)
                      : softColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: selected ? AppColors.cardWhite : color,
                  size: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.button.copyWith(
                  color: selected ? AppColors.cardWhite : color,
                  fontSize: 10.8,
                  height: 1.08,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
