import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({
    super.key,
    this.onRetry,
    this.lastUpdatedAt,
  });

  final VoidCallback? onRetry;
  final DateTime? lastUpdatedAt;

  @override
  Widget build(BuildContext context) {
    final message = lastUpdatedAt == null
        ? 'تعذر تحديث البيانات الآن. تأكد من اتصال الإنترنت ثم حاول مرة أخرى.'
        : 'نعرض آخر بيانات متاحة. قد لا تكون الفرص والرسائل محدثة الآن.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warningGold.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.warningGold.withValues(alpha: .26),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.cardWhite.withValues(alpha: .72),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.primaryDarkGreen,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'الاتصال غير مستقر',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primaryDarkGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textGray,
                      fontSize: 10.8,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'إعادة المحاولة',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                style: IconButton.styleFrom(
                  fixedSize: const Size(36, 36),
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.cardWhite,
                  foregroundColor: AppColors.primaryDarkGreen,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
