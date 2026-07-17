import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SubscriptionScreen extends StatefulWidget {
  final bool allowBack;

  const SubscriptionScreen({super.key, this.allowBack = false});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  SubscriptionPlan _selected = SubscriptionPlan.professional;
  PaymentMethod _paymentMethod = PaymentMethod.mada;
  bool _loading = false;

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    AppScope.of(context, listen: false).activateSubscription(_selected);
    setState(() => _loading = false);
    if (widget.allowBack && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      showAppSnackBar(context, 'تم تحديث اشتراكك بنجاح');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.allowBack
          ? AppBar(title: const Text('الاشتراك والباقات'))
          : null,
      body: SafeArea(
        child: LoadingOverlay(
          visible: _loading,
          label: 'جارٍ تفعيل الاشتراك...',
          child: ResponsiveContent(
            maxWidth: 720,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!widget.allowBack) ...<Widget>[
                  const Align(
                    alignment: Alignment.centerRight,
                    child: BrandLogo(),
                  ),
                  const SizedBox(height: 14),
                ],
                const AppPageHeader(
                  title: 'اختر الباقة المناسبة',
                  subtitle:
                      'ابدأ بإدارة عقودك من تطبيق واحد، ويمكنك تغيير الباقة أو إلغاؤها لاحقًا.',
                  icon: Icons.workspace_premium_outlined,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 680;
                    final cards = <Widget>[
                      _PlanCard(
                        plan: SubscriptionPlan.basic,
                        selected: _selected == SubscriptionPlan.basic,
                        title: 'الأساسية',
                        price: '49',
                        period: 'شهريًا',
                        description: 'للأفراد بعقود محدودة',
                        features: const <String>[
                          'طلبا عقد شهريًا',
                          'متابعة حالة الطلب',
                          'حفظ العقود والمستندات',
                          'دعم عبر المحادثة',
                        ],
                        onTap: () => setState(
                          () => _selected = SubscriptionPlan.basic,
                        ),
                      ),
                      _PlanCard(
                        plan: SubscriptionPlan.professional,
                        selected: _selected == SubscriptionPlan.professional,
                        title: 'الاحترافية',
                        price: '99',
                        period: 'شهريًا',
                        description: 'الأكثر مناسبة للملاك',
                        highlighted: true,
                        features: const <String>[
                          '10 طلبات عقد شهريًا',
                          'أولوية المراجعة',
                          'تجديد العقود',
                          'تنبيهات واتساب وداخل التطبيق',
                          'دعم فني ذو أولوية',
                        ],
                        onTap: () => setState(
                          () => _selected = SubscriptionPlan.professional,
                        ),
                      ),
                      _PlanCard(
                        plan: SubscriptionPlan.business,
                        selected: _selected == SubscriptionPlan.business,
                        title: 'الأعمال',
                        price: '249',
                        period: 'شهريًا',
                        description: 'للملاك وشركات إدارة الأملاك',
                        features: const <String>[
                          'طلبات عقود غير محدودة',
                          'إدارة عدة عقارات',
                          'تقارير شهرية',
                          'خدمة مستعجلة',
                          'مدير حساب مخصص',
                        ],
                        onTap: () => setState(
                          () => _selected = SubscriptionPlan.business,
                        ),
                      ),
                    ];
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (var i = 0; i < cards.length; i++) ...<Widget>[
                            Expanded(child: cards[i]),
                            if (i < cards.length - 1) const SizedBox(width: 8),
                          ],
                        ],
                      );
                    }
                    return Column(
                      children: <Widget>[
                        for (var i = 0; i < cards.length; i++) ...<Widget>[
                          cards[i],
                          if (i < cards.length - 1) const SizedBox(height: 9),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                const SectionTitle(
                  title: 'طريقة الدفع',
                  icon: Icons.credit_card_outlined,
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  title: 'بطاقة مدى',
                  subtitle: 'الدفع الآمن باستخدام بطاقات مدى',
                  icon: Icons.credit_card_rounded,
                  value: PaymentMethod.mada,
                  selected: _paymentMethod,
                  onChanged: (value) => setState(() => _paymentMethod = value),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  title: 'Apple Pay',
                  subtitle: 'ادفع مباشرة من محفظة Apple Pay',
                  icon: Icons.phone_iphone_rounded,
                  value: PaymentMethod.applePay,
                  selected: _paymentMethod,
                  onChanged: (value) => setState(() => _paymentMethod = value),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  title: 'تحويل بنكي',
                  subtitle: 'تحويل المبلغ إلى الحساب البنكي',
                  icon: Icons.account_balance_outlined,
                  value: PaymentMethod.bankTransfer,
                  selected: _paymentMethod,
                  onChanged: (value) => setState(() => _paymentMethod = value),
                ),
                const SizedBox(height: 12),
                const InfoBanner(
                  text:
                      'رسوم إصدار العقد الرسمية ورسوم الخدمات الإضافية لا تدخل ضمن قيمة الاشتراك، وتظهر لك بوضوح قبل الدفع.',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'اشترك وابدأ الآن',
                  icon: Icons.lock_outline_rounded,
                  onPressed: _subscribe,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool selected;
  final String title;
  final String price;
  final String period;
  final String description;
  final List<String> features;
  final bool highlighted;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.title,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      color: selected ? AppColors.primary.withValues(alpha: 0.035) : null,
      border: Border.all(
        color: selected
            ? AppColors.primary
            : highlighted
                ? AppColors.secondary
                : context.ejarzTheme.border,
        width: selected ? 1.8 : 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (highlighted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'الأكثر اختيارًا',
                    style: TextStyle(
                      color: Color(0xFF916400),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(width: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : context.ejarzTheme.border,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              fontSize: context.sp(11.2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                price,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: context.sp(27),
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'ر.س / $period',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 17,
                    height: 17,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        fontSize: context.sp(11.2),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
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

class _PaymentMethodTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final PaymentMethod value;
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  const _PaymentMethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = value == selected;
    return AppCard(
      onTap: () => onChanged(value),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      shadows: const <BoxShadow>[],
      border: Border.all(
        color: active ? AppColors.primary : context.ejarzTheme.border,
        width: active ? 1.5 : 1,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primaryLight
                  : context.ejarzTheme.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: active ? AppColors.primary : context.ejarzTheme.muted),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(10.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: active ? AppColors.primary : context.ejarzTheme.muted,
          ),
        ],
      ),
    );
  }
}
