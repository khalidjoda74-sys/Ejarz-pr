import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/illustrations.dart';
import 'contracts.dart';
import 'create_contract.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final VoidCallback onCreate;
  final VoidCallback onContracts;
  final VoidCallback onProperties;

  const HomeScreen({
    super.key,
    required this.onMenu,
    required this.onNotifications,
    required this.onCreate,
    required this.onContracts,
    required this.onProperties,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final recent = controller.contracts.take(2).toList();
    final recentProperties = controller.properties.take(2).toList();

    return SafeArea(
      child: ResponsiveContent(
        maxWidth: 780,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BrandHeader(
              onMenu: onMenu,
              onNotifications: onNotifications,
              showMenu: false,
              useSplashLogo: true,
            ),
            const SizedBox(height: 16),
            Text(
              '${controller.homeGreetingPrefix}، ${controller.userName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              controller.homeWelcomeText,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontSize: context.sp(13.5),
              ),
            ),
            const SizedBox(height: 14),
            _HomeHero(controller: controller, onCreate: onCreate),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatCard(
                    title: 'العقود النشطة',
                    value: '${controller.activeContracts}',
                    subtitle: 'عقدًا نشطًا',
                    icon: Icons.description_outlined,
                    color: AppColors.primary,
                    onTap: onContracts,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: StatCard(
                    title: 'قيد المعالجة',
                    value: '${controller.awaitingContracts}',
                    subtitle: 'عقود',
                    icon: Icons.schedule_rounded,
                    color: AppColors.orange,
                    onTap: onContracts,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: StatCard(
                    title: 'العقود المكتملة',
                    value: '${controller.completedContracts}',
                    subtitle: 'عقدًا مكتملًا',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    onTap: onContracts,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SectionTitle(
              title: controller.homeServicesTitle,
              action: controller.homeServicesAction,
              onAction: onCreate,
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 98,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _ServiceTile(
                        icon: Icons.home_work_outlined,
                        title: controller.serviceResidentialTitle,
                        subtitle: controller.serviceResidentialSubtitle,
                        onTap: () => _openNewContract(
                          context,
                          ContractType.residential,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _ServiceTile(
                        icon: Icons.storefront_outlined,
                        title: controller.serviceCommercialTitle,
                        subtitle: controller.serviceCommercialSubtitle,
                        onTap: () => _openNewContract(
                          context,
                          ContractType.commercial,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _ServiceTile(
                        icon: Icons.refresh_rounded,
                        title: controller.serviceRenewalTitle,
                        subtitle: controller.serviceRenewalSubtitle,
                        onTap: () => _openRenewalContracts(context),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _ServiceTile(
                        icon: Icons.apartment_outlined,
                        title: 'عقاراتي',
                        subtitle: 'إدارة العقارات',
                        onTap: onProperties,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionTitle(
              title: controller.homeContractsTitle,
              action: controller.homeContractsAction,
              onAction: onContracts,
            ),
            const SizedBox(height: 6),
            if (recent.isEmpty)
              EmptyState(
                icon: Icons.description_outlined,
                title: controller.homeEmptyContractsTitle,
                subtitle: controller.homeEmptyContractsSubtitle,
                actionLabel: controller.homeEmptyContractsAction,
                onAction: onCreate,
              )
            else
              for (var i = 0; i < recent.length; i++) ...<Widget>[
                ContractListCard(
                  contract: recent[i],
                  showOwner: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ContractDetailsScreen(
                        contract: recent[i],
                      ),
                    ),
                  ),
                ),
                if (i < recent.length - 1) const SizedBox(height: 7),
              ],
            const SizedBox(height: 16),
            SectionTitle(
              title: controller.homePropertiesTitle,
              action: controller.homePropertiesAction,
              onAction: onProperties,
            ),
            const SizedBox(height: 6),
            if (recentProperties.isEmpty)
              EmptyState(
                icon: Icons.apartment_outlined,
                title: controller.homeEmptyPropertiesTitle,
                subtitle: controller.homeEmptyPropertiesSubtitle,
                actionLabel: controller.homeEmptyPropertiesAction,
                onAction: onProperties,
              )
            else
              for (var i = 0; i < recentProperties.length; i++) ...<Widget>[
                _RecentPropertyTile(property: recentProperties[i]),
                if (i < recentProperties.length - 1) const SizedBox(height: 7),
              ],
          ],
        ),
      ),
    );
  }

  void _openNewContract(BuildContext context, ContractType type) {
    final draft = createContractDraftForType(type);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateContractScreen(
          initialDraft: draft,
          initialStep: 0,
        ),
      ),
    );
  }

  void _openRenewalContracts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RenewContractSelectionScreen(),
      ),
    );
  }
}

class RenewContractSelectionScreen extends StatelessWidget {
  const RenewContractSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final renewableContracts = controller.contracts
        .where((contract) => contract.status == ContractStatus.authenticated)
        .toList();

    return Scaffold(
      appBar: const DetailAppBar(title: 'تجديد عقد'),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppPageHeader(
                title: 'اختر العقد المراد تجديده',
                subtitle:
                    'سننسخ بيانات العقد ونوعه إلى طلب جديد لتراجعها قبل الإرسال.',
                icon: Icons.refresh_rounded,
              ),
              const SizedBox(height: 14),
              if (renewableContracts.isEmpty)
                EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'لا توجد عقود متاحة للتجديد',
                  subtitle:
                      'يظهر هنا العقد المكتمل بعد صدوره. يمكنك إنشاء عقد جديد الآن.',
                  actionLabel: 'إنشاء عقد جديد',
                  onAction: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateContractScreen(),
                    ),
                  ),
                )
              else ...<Widget>[
                const InfoBanner(
                  text:
                      'التجديد ينشئ طلبًا جديدًا ولا يغيّر العقد السابق. راجع التواريخ والمبالغ والمرفقات قبل الإرسال.',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 12),
                for (var index = 0;
                    index < renewableContracts.length;
                    index++) ...<Widget>[
                  _RenewableContractCard(
                    contract: renewableContracts[index],
                    onTap: () => _renew(context, renewableContracts[index]),
                  ),
                  if (index != renewableContracts.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _renew(BuildContext context, ContractRecord contract) {
    final draft = _renewalDraft(contract);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CreateContractScreen(
          initialDraft: draft,
          initialStep: 0,
          renewalMode: true,
          renewalSourceNumber: contract.requestNumber,
        ),
      ),
    );
  }

  ContractDraft _renewalDraft(ContractRecord contract) {
    final savedDraft = contract.draftData;
    final draft = savedDraft == null
        ? createContractDraftForType(contract.type)
        : ContractDraft.copyOf(savedDraft);
    draft
      ..type = contract.type
      ..role = contract.role
      ..acceptAccuracyDeclaration = false
      ..acceptDataSharing = false
      ..acceptTerms = false;

    if (savedDraft == null) {
      draft.lessor.fullName = contract.lessorName;
      draft.tenant.fullName = contract.tenantName;
      final address = contract.property
          .split('-')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (address.isNotEmpty) draft.property.city = address.first;
      if (address.length > 1) draft.property.district = address[1];
      if (address.length > 2) draft.property.street = address[2];
    }
    return draft;
  }
}

class _RenewableContractCard extends StatelessWidget {
  final ContractRecord contract;
  final VoidCallback onTap;

  const _RenewableContractCard({
    required this.contract,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: ValueKey<String>('renew-contract-${contract.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(contract.type.icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  contract.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contract.requestNumber} • ${contract.type.label}',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  contract.property,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
        ],
      ),
    );
  }
}

class _RecentPropertyTile extends StatelessWidget {
  final PropertyRecord property;

  const _RecentPropertyTile({required this.property});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child:
                const Icon(Icons.apartment_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  property.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${property.location} • ${property.totalUnits} وحدة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              property.usage,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: context.sp(10.5),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  final AppController controller;
  final VoidCallback onCreate;

  const _HomeHero({required this.controller, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFF0B8062), Color(0xFF005C48)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _HeroCopy(
                        controller: controller,
                        onCreate: onCreate,
                      ),
                    ),
                    const HeroContractIllustration(width: 94, height: 88),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(
                flex: 6,
                child: _HeroCopy(controller: controller, onCreate: onCreate),
              ),
              const SizedBox(width: 8),
              const Expanded(
                flex: 4,
                child: Center(
                  child: HeroContractIllustration(width: 132, height: 112),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  final AppController controller;
  final VoidCallback onCreate;

  const _HeroCopy({required this.controller, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          controller.homeHeroTitle,
          style: TextStyle(
            color: Colors.white,
            fontSize: context.sp(19),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          controller.homeHeroSubtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontSize: context.sp(11.6),
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: FilledButton.icon(
            onPressed: onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              controller.homeHeroButtonText,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      radius: 13,
      padding: const EdgeInsets.fromLTRB(5, 8, 5, 7),
      child: Tooltip(
        message: subtitle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: context.sp(11.4),
                height: 1.05,
                fontFamily: AppTheme.fontFamily,
                fontFamilyFallback: AppTheme.fontFallback,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontWeight: FontWeight.w600,
                fontSize: context.sp(8.7),
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 23,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
