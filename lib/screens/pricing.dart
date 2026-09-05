import 'package:flutter/material.dart';
import '../core/contract_pricing.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('أسعار العقود')),
        body: SafeArea(
            child: ResponsiveContent(
                maxWidth: 700,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppPageHeader(
                        title: 'أسعار واضحة لكل عقد',
                        subtitle:
                            'تُحسب الرسوم تلقائيًا بحسب نوع العقد ومدته، وتظهر قبل تأكيد الطلب والدفع.',
                        icon: Icons.receipt_long_outlined),
                    const SizedBox(height: 20),
                    for (final type in ContractType.values) ...[
                      _PriceCard(type: type),
                      const SizedBox(height: 14),
                    ],
                    const InfoBanner(
                        text: ContractPrice.inclusionNote,
                        icon: Icons.verified_outlined),
                    const SizedBox(height: 14),
                    const Text(ContractPrice.durationNote,
                        style: TextStyle(height: 1.7)),
                    const SizedBox(height: 12),
                    const Text(
                        'هذه رسوم خدمة العقد. قيمة إيجار العقار والضمان وأي مبالغ متفق عليها بين الأطراف تظهر بصورة مستقلة في العقد.',
                        style: TextStyle(height: 1.7)),
                  ],
                ))),
      );
}

class _PriceCard extends StatelessWidget {
  final ContractType type;
  const _PriceCard({required this.type});
  @override
  Widget build(BuildContext context) {
    final price =
        ContractPrice.calculate(commercial: type == ContractType.commercial);
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(type.icon, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(type.label, style: Theme.of(context).textTheme.titleLarge))
      ]),
      const SizedBox(height: 14),
      Text('${price.firstYear.toStringAsFixed(0)} ريال',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.primary, fontWeight: FontWeight.w800)),
      const Text('للسنة الأولى'),
      const Divider(height: 24),
      Text(
          '+ ${price.additionalYearRate.toStringAsFixed(0)} ريال لكل سنة إضافية',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Text(
          'مثال: عقد لسنتين = ${(price.firstYear + price.additionalYearRate).toStringAsFixed(0)} ريال'),
    ]));
  }
}
