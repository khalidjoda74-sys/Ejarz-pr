import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/premium_background.dart';
import '../../navigation/app_routes.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final items = [
      _OnboardItem(
        Icons.how_to_vote_rounded,
        'قيّم فرص يومية',
        'كل يوم موضوع جديد يجمع الآراء ويظهر نتيجة واضحة.',
      ),
      _OnboardItem(
        Icons.person_pin_circle_rounded,
        'شارك رأيك باسم مستعار',
        'اكتب رأيك بحرية واحترام بدون تعقيد في التسجيل.',
      ),
      _OnboardItem(
        Icons.emoji_events_rounded,
        'شاهد أفضل الآراء',
        'بعد انتهاء الفرصة تظهر النتيجة وأقوى التعليقات.',
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              sizes.horizontalPadding,
              16,
              sizes.horizontalPadding,
              20,
            ),
            children: [
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0F4A35),
                        blurRadius: 14,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: AppColors.cardWhite,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: AppTextStyles.display,
              ),
              const SizedBox(height: 5),
              Text(
                AppStrings.tagline,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.primaryDarkGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OnboardCard(item: item),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.main),
                  child: const Text('ابدأ الآن'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardItem {
  _OnboardItem(this.icon, this.title, this.message);

  final IconData icon;
  final String title;
  final String message;
}

class _OnboardCard extends StatelessWidget {
  const _OnboardCard({required this.item});

  final _OnboardItem item;

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
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: AppColors.primaryGreen, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 14.5),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
