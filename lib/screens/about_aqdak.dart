import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/illustrations.dart';

class AboutAqdakScreen extends StatelessWidget {
  const AboutAqdakScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('عن عقدك')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 27),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [AppColors.primaryDark, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: const BrandMark(size: 46),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'عقدك',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'أسهل طريق لعقودك',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('كل ما تحتاجه لطلب عقد الإيجار',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'عقدك مساحة واحدة لتنظيم طلبات عقود الإيجار السكنية والتجارية. '
                  'ابدأ طلبك، أدخل بيانات الأطراف والعقار، أرفق المتطلبات، '
                  'وتابع حالة الطلب وخطواته بوضوح من حسابك.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: context.ejarzTheme.muted,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 20),
                const _AboutFeature(
                  icon: Icons.home_work_outlined,
                  title: 'عقود سكنية وتجارية',
                  description:
                      'قدّم طلب العقد المناسب لنوع العقار، مع خطوات واضحة للبيانات والمرفقات المطلوبة.',
                ),
                const SizedBox(height: 10),
                const _AboutFeature(
                  icon: Icons.apartment_outlined,
                  title: 'عقاراتك وبيانات أطرافك',
                  description:
                      'احفظ بيانات العقارات والوحدات والأطراف لتعود إليها بسهولة عند إعداد طلب جديد.',
                ),
                const SizedBox(height: 10),
                const _AboutFeature(
                  icon: Icons.fact_check_outlined,
                  title: 'متابعة واضحة للطلبات',
                  description:
                      'راجع حالة عقودك، والمتطلبات الناقصة، والإشعارات والمدفوعات من مكان واحد.',
                ),
                const SizedBox(height: 22),
                Center(
                  child: SizedBox(
                    width: 220,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إغلاق'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const _AppVersion(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppVersion extends StatefulWidget {
  const _AppVersion();

  @override
  State<_AppVersion> createState() => _AppVersionState();
}

class _AppVersionState extends State<_AppVersion> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _packageInfo,
        builder: (context, snapshot) {
          final version = snapshot.data?.version.trim() ?? '';
          if (version.isEmpty) return const SizedBox.shrink();
          return Text(
            'الإصدار $version',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.ejarzTheme.muted,
                ),
          );
        },
      );
}

class _AboutFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AboutFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.ejarzTheme.muted,
                    height: 1.55,
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
