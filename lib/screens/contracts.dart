import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/draft_resume_policy.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/illustrations.dart';
import 'create_contract.dart';
import 'payment_demo.dart';
import 'wallet_profile.dart';

Widget _contractDetailsBottomNavigation(BuildContext context) {
  final controller = AppScope.of(context);
  return EjarzBottomNavigation(
    currentIndex: controller.mainNavigationIndex,
    onSelect: (index) {
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      controller.setNavigationIndex(index);
    },
    onCreate: () {
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const CreateContractScreen(),
        ),
      );
    },
  );
}

class ContractsScreen extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final VoidCallback onCreate;

  const ContractsScreen({
    super.key,
    required this.onMenu,
    required this.onNotifications,
    required this.onCreate,
  });

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen> {
  String _query = '';
  ContractStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final allContracts = controller.contracts;
    final filtered = allContracts.where((contract) {
      final matchesFilter = _filter == null || contract.status == _filter;
      final normalized = _query.trim().toLowerCase();
      final matchesQuery = normalized.isEmpty ||
          contract.title.toLowerCase().contains(normalized) ||
          contract.requestNumber.toLowerCase().contains(normalized) ||
          contract.id.toLowerCase().contains(normalized) ||
          contract.property.toLowerCase().contains(normalized) ||
          contract.lessorName.toLowerCase().contains(normalized) ||
          contract.tenantName.toLowerCase().contains(normalized);
      return matchesFilter && matchesQuery;
    }).toList();

    return SafeArea(
      child: ResponsiveContent(
        maxWidth: 760,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BrandHeader(
              onMenu: widget.onMenu,
              onNotifications: widget.onNotifications,
              showMenu: false,
              showNotification: false,
              showLogo: false,
            ),
            const SizedBox(height: 14),
            const AppPageHeader(
              title: 'عقودي',
              subtitle: 'ابحث في جميع طلباتك وتابع حالة كل عقد.',
              icon: Icons.description_outlined,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'ابحث برقم العقد أو العقار أو الطرف الآخر',
                suffixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: <Widget>[
                    _FilterChip(
                      label: 'الكل',
                      selected: _filter == null,
                      color: AppColors.primary,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final status in ContractStatus.values) ...<Widget>[
                      const SizedBox(width: 6),
                      _FilterChip(
                        label: status.label,
                        selected: _filter == status,
                        color: status.color,
                        onTap: () => setState(() => _filter = status),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 88,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: StatCard(
                        title: 'الكل',
                        value: '${allContracts.length}',
                        subtitle: 'جميع العقود',
                        icon: Icons.description_outlined,
                        color: AppColors.primary,
                        compact: true,
                        onTap: () => setState(() => _filter = null),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatCard(
                        title: 'قيد المعالجة',
                        value:
                            '${allContracts.where((item) => item.status == ContractStatus.processing).length}',
                        subtitle: 'طلبًا',
                        icon: Icons.miscellaneous_services_outlined,
                        color: AppColors.blue,
                        compact: true,
                        onTap: () => setState(
                          () => _filter = ContractStatus.processing,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatCard(
                        title: 'بانتظار الدفع',
                        value:
                            '${allContracts.where((item) => item.status == ContractStatus.awaitingPayment).length}',
                        subtitle: 'طلبات',
                        icon: Icons.payments_outlined,
                        color: AppColors.orange,
                        compact: true,
                        onTap: () => setState(
                          () => _filter = ContractStatus.awaitingPayment,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatCard(
                        title: 'مكتمل',
                        value:
                            '${allContracts.where((item) => item.status == ContractStatus.authenticated).length}',
                        subtitle: 'عقدًا',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                        compact: true,
                        onTap: () => setState(
                          () => _filter = ContractStatus.authenticated,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SectionTitle(
              title: 'قائمة العقود',
              action: '${filtered.length} عقد',
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'لا توجد نتائج',
                subtitle: 'جرّب تغيير عبارة البحث أو فلتر الحالة.',
                actionLabel: 'إنشاء عقد جديد',
                onAction: widget.onCreate,
              )
            else
              for (var i = 0; i < filtered.length; i++) ...<Widget>[
                ContractListCard(
                  contract: filtered[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ContractDetailsScreen(
                        contract: filtered[i],
                      ),
                    ),
                  ),
                ),
                if (i != filtered.length - 1) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : context.ejarzTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : context.ejarzTheme.border,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: context.sp(10.6),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContractDetailsScreen extends StatelessWidget {
  final ContractRecord contract;

  const ContractDetailsScreen({super.key, required this.contract});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: DetailAppBar(
        title: 'تفاصيل العقد',
        onBack: () => Navigator.of(context).pop(),
      ),
      bottomNavigationBar: _contractDetailsBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ContractHero(contract: contract),
              if (contract.status == ContractStatus.rejected) ...<Widget>[
                const SizedBox(height: 12),
                _RejectedContractBanner(contract: contract),
              ] else if (contract.customerVisibleNote
                  .trim()
                  .isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                InfoBanner(
                  text: contract.customerVisibleNote,
                  icon: Icons.info_outline_rounded,
                  color: contract.status.color,
                ),
              ],
              if (contract.status != ContractStatus.rejected &&
                  contract.missingRequirements.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _MissingRequirementsCard(contract: contract),
              ],
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'حالة العقد',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _StatusTimeline(items: contract.timeline),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _DetailsRow(
                      icon: Icons.description_outlined,
                      title: 'بيانات العقد',
                      subtitle: 'عرض تفاصيل العقد الأساسية والمدة',
                      onTap: () => _openContractData(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.people_outline_rounded,
                      title: 'الأطراف',
                      subtitle: 'عرض بيانات المؤجر والمستأجر',
                      onTap: () => _openParties(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: contract.type.icon,
                      title: 'العقار',
                      subtitle: 'تفاصيل العقار وعنوانه',
                      onTap: () => _openProperty(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'الرسوم',
                      subtitle: 'تفاصيل الرسوم والمدفوعات',
                      onTap: () => _openFees(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.attach_file_rounded,
                      title: 'المرفقات',
                      subtitle: 'المستندات والنسخ المرتبطة بالطلب',
                      onTap: () => _openAttachments(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (contract.pendingSync || controller.offlineMode) ...<Widget>[
                InfoBanner(
                  text: contract.pendingSync
                      ? 'هذا العقد محفوظ محليًا وينتظر المزامنة. سيظهر الدفع والإرسال الرسمي بعد عودة الاتصال ورفع الطلب.'
                      : 'أنت غير متصل. يمكنك تصفح التفاصيل المحفوظة، لكن الدفع والدعم والإجراءات الرسمية تحتاج اتصالًا.',
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.orange,
                ),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final children = <Widget>[
                    if (contract.status == ContractStatus.draft)
                      PrimaryButton(
                        label: 'إكمال المسودة',
                        icon: Icons.edit_note_rounded,
                        onPressed: () => _resumeDraft(context),
                      )
                    else if (contract.status == ContractStatus.rejected)
                      PrimaryButton(
                        label: 'إنشاء طلب جديد',
                        icon: Icons.add_circle_outline_rounded,
                        onPressed: () => _openNewContract(context),
                      )
                    else if (contract.status ==
                            ContractStatus.awaitingPayment &&
                        contract.paymentStatus != 'paid')
                      PrimaryButton(
                        label: 'دفع الرسوم',
                        icon: Icons.credit_card_rounded,
                        onPressed: contract.pendingSync
                            ? () => showAppSnackBar(
                                  context,
                                  'لا يمكن الدفع قبل مزامنة الطلب مع الخادم.',
                                )
                            : () => _openPaymentScreen(context),
                      )
                    else
                      PrimaryButton(
                        label: contract.status == ContractStatus.authenticated
                            ? contract.isDemoPayment
                                ? 'تحميل نموذج العقد'
                                : 'تحميل العقد'
                            : 'تحميل ملخص الطلب',
                        icon: Icons.download_rounded,
                        onPressed: () => _downloadContract(context),
                      ),
                    if (contract.status != ContractStatus.draft)
                      SecondaryButton(
                        label: 'الدعم الفني',
                        icon: Icons.support_agent_rounded,
                        onPressed: () => _openContractSupport(context),
                      ),
                  ];
                  if (children.length == 1) return children.first;
                  if (constraints.maxWidth >= 520) {
                    return Row(
                      children: <Widget>[
                        Expanded(child: children[0]),
                        const SizedBox(width: 12),
                        Expanded(child: children[1]),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      children[0],
                      const SizedBox(height: 10),
                      children[1],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ContractDraft get _draftSnapshot {
    final stored = contract.draftData;
    if (stored != null) return ContractDraft.copyOf(stored);
    final fallback = ContractDraft()..type = contract.type;
    if (_meaningfulDraftText(contract.lessorName)) {
      fallback.lessor.fullName = contract.lessorName.trim();
    }
    if (_meaningfulDraftText(contract.tenantName)) {
      fallback.tenant.fullName = contract.tenantName.trim();
    }
    final address = contract.property
        .split('-')
        .map((item) => item.trim())
        .where(_meaningfulDraftText)
        .toList();
    if (address.isNotEmpty) fallback.property.city = address.first;
    if (address.length > 1) fallback.property.district = address[1];
    if (address.length > 2) fallback.property.street = address[2];
    final contractData = contract.contractDetails;
    fallback
      ..startDate = _legacyDraftValue(
        contractData,
        const <String>['تاريخ بداية العقد'],
      )
      ..endDate = _legacyDraftValue(
        contractData,
        const <String>['تاريخ نهاية العقد'],
      )
      ..rentValue = _legacyMoneyValue(
        _legacyDraftValue(
          contractData,
          const <String>['قيمة الإيجار', 'قيمة الإيجار السنوي'],
        ),
      )
      ..firstPaymentDate = _legacyDraftValue(
        contractData,
        const <String>['تاريخ أول دفعة'],
      );
    final partyData = contract.partyDetails;
    fallback.lessor
      ..fullName = _legacyDraftValue(
        partyData,
        const <String>['اسم المؤجر'],
        fallback: fallback.lessor.fullName,
      )
      ..idNumber = _legacyDraftValue(
        partyData,
        const <String>['هوية المؤجر'],
      )
      ..mobile = _legacyDraftValue(
        partyData,
        const <String>['جوال المؤجر'],
      )
      ..district = _legacyDraftValue(
        partyData,
        const <String>['حي المؤجر'],
      )
      ..nationalAddress = _legacyDraftValue(
        partyData,
        const <String>['العنوان الوطني للمؤجر'],
      )
      ..iban = _legacyDraftValue(
        partyData,
        const <String>['آيبان المؤجر'],
      )
      ..bankName = _legacyDraftValue(
        partyData,
        const <String>['بنك المؤجر'],
      );
    fallback.tenant
      ..fullName = _legacyDraftValue(
        partyData,
        const <String>['اسم المستأجر'],
        fallback: fallback.tenant.fullName,
      )
      ..idNumber = _legacyDraftValue(
        partyData,
        const <String>['هوية المستأجر'],
      )
      ..mobile = _legacyDraftValue(
        partyData,
        const <String>['جوال المستأجر'],
      )
      ..district = _legacyDraftValue(
        partyData,
        const <String>['حي المستأجر'],
      )
      ..nationalAddress = _legacyDraftValue(
        partyData,
        const <String>['العنوان الوطني للمستأجر'],
      );
    final propertyData = contract.propertyDetails;
    fallback.property
      ..ownershipDocumentNumber = _legacyDraftValue(
        propertyData,
        const <String>['رقم وثيقة الملكية'],
      )
      ..ownershipDocumentDate = _legacyDraftValue(
        propertyData,
        const <String>['تاريخ وثيقة الملكية'],
      )
      ..district = _legacyDraftValue(
        propertyData,
        const <String>['الحي'],
        fallback: fallback.property.district,
      )
      ..street = _legacyDraftValue(
        propertyData,
        const <String>['الشارع'],
        fallback: fallback.property.street,
      )
      ..buildingNumber = _legacyDraftValue(
        propertyData,
        const <String>['رقم المبنى'],
      )
      ..additionalNumber = _legacyDraftValue(
        propertyData,
        const <String>['الرقم الإضافي'],
      )
      ..postalCode = _legacyDraftValue(
        propertyData,
        const <String>['الرمز البريدي'],
      )
      ..unitNumber = _legacyDraftValue(
        propertyData,
        const <String>['رقم الوحدة'],
      )
      ..unitName = _legacyDraftValue(
        propertyData,
        const <String>['اسم الوحدة'],
      )
      ..floor = _legacyDraftValue(propertyData, const <String>['الدور'])
      ..area = _legacyMoneyValue(
        _legacyDraftValue(propertyData, const <String>['المساحة']),
      )
      ..electricityMeter = _legacyDraftValue(
        propertyData,
        const <String>['عداد الكهرباء'],
      )
      ..waterMeter = _legacyDraftValue(
        propertyData,
        const <String>['عداد المياه'],
      );
    for (final attachment in fallback.attachments) {
      final file = contract.attachmentFiles[attachment.title]?.trim() ?? '';
      if (_meaningfulDraftText(file) && file != 'مطلوب' && file != 'اختياري') {
        attachment
          ..uploaded = true
          ..fileName = file;
      }
    }
    return fallback;
  }

  static String _legacyDraftValue(
    Map<String, String> source,
    List<String> labels, {
    String fallback = '',
  }) {
    for (final label in labels) {
      final value = source[label]?.trim() ?? '';
      if (_meaningfulDraftText(value)) return value;
    }
    return fallback;
  }

  static String _legacyMoneyValue(String value) => value
      .replaceAll('ريال', '')
      .replaceAll('ر.س', '')
      .replaceAll('م²', '')
      .replaceAll(',', '')
      .trim();

  void _resumeDraft(BuildContext context, {int? step}) {
    final draft = _draftSnapshot;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateContractScreen(
          initialDraft: draft,
          draftId: contract.id,
          initialStep: step ?? firstIncompleteDraftStep(draft),
          initialTouchedSections: contract.draftProgress.touchedSections,
        ),
      ),
    );
  }

  void _openNewContract(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateContractScreen(),
      ),
    );
  }

  static bool _meaningfulDraftText(String value) {
    final text = value.trim();
    return text.isNotEmpty &&
        text != '-' &&
        text != 'غير محدد' &&
        !text.contains('لم يتم تحديد') &&
        !text.contains('غير محدد');
  }

  Future<void> _downloadContract(BuildContext context) async {
    if (contract.status != ContractStatus.authenticated) {
      showAppSnackBar(context, 'لم يتم إصدار ملف العقد النهائي بعد.');
      return;
    }
    if (contract.finalPdfUrl.trim().isEmpty) {
      showAppSnackBar(
        context,
        contract.isDemoPayment
            ? 'نموذج العقد التجريبي غير متاح الآن.'
            : 'لم يتم إصدار ملف العقد النهائي بعد.',
      );
      return;
    }
    final opened = await launchUrl(
      Uri.parse(contract.finalPdfUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      showAppSnackBar(
        context,
        contract.isDemoPayment
            ? 'تعذر فتح نموذج العقد الآن.'
            : 'تعذر فتح ملف العقد الآن.',
      );
    }
  }

  void _openContractSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportScreen(
          initialSubject: 'دعم عقد ${contract.requestNumber}',
          initialMessage:
              'أحتاج مساعدة بخصوص الطلب ${contract.requestNumber} - ${contract.title}.',
          initialPriority:
              contract.status == ContractStatus.missingData ? 'عالية' : 'عادية',
        ),
      ),
    );
  }

  Future<void> _openPaymentScreen(BuildContext context) async {
    final updated = await Navigator.of(context).push<ContractRecord>(
      MaterialPageRoute<ContractRecord>(
        builder: (_) => DemoPaymentScreen(contract: contract),
      ),
    );
    if (updated == null || !context.mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ContractDetailsScreen(contract: updated),
      ),
    );
  }

  void _openDetailsPage(
    BuildContext context, {
    required String title,
    required List<_ContractDetailSection> sections,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ContractSectionDetailsScreen(
          title: title,
          sections: sections,
        ),
      ),
    );
  }

  void _openDraftEmptySection(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required int step,
    required IconData icon,
  }) {
    _openDetailsPage(
      context,
      title: title,
      sections: <_ContractDetailSection>[
        _ContractDetailSection.custom(
          title: 'المسودة',
          icon: icon,
          child: _DraftEmptyState(
            message: message,
            actionLabel: actionLabel,
            icon: icon,
            onPressed: () => _resumeDraft(context, step: step),
          ),
        ),
      ],
    );
  }

  void _openDraftContractData(BuildContext context) {
    final draft = _draftSnapshot;
    if (!draftHasContractData(draft)) {
      _openDraftEmptySection(
        context,
        title: 'بيانات العقد الأساسية',
        message: 'لم تُضف بيانات العقد بعد.',
        actionLabel: 'إكمال بيانات العقد',
        step: 4,
        icon: Icons.description_outlined,
      );
      return;
    }
    final items = <_ContractDetailItem>[
      _ContractDetailItem(label: 'نوع العقد', value: draft.type.label),
      if (_meaningfulDraftText(draft.startDate))
        _ContractDetailItem(label: 'تاريخ بداية العقد', value: draft.startDate),
      if (_meaningfulDraftText(draft.endDate))
        _ContractDetailItem(label: 'تاريخ نهاية العقد', value: draft.endDate),
      if (_meaningfulDraftText(draft.rentValue))
        _ContractDetailItem(
          label: 'قيمة الإيجار',
          value: '${draft.rentValue.trim()} ريال',
        ),
      if (_meaningfulDraftText(draft.firstPaymentDate))
        _ContractDetailItem(
          label: 'تاريخ أول دفعة',
          value: draft.firstPaymentDate,
        ),
      if (_meaningfulDraftText(draft.otherServices))
        _ContractDetailItem(
          label: 'خدمات إضافية',
          value: draft.otherServices,
        ),
      if (_meaningfulDraftText(draft.specialTerms))
        _ContractDetailItem(
          label: 'شروط إضافية',
          value: draft.specialTerms,
        ),
    ];
    _openDetailsPage(
      context,
      title: 'بيانات العقد الأساسية',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'البيانات المحفوظة',
          icon: Icons.description_outlined,
          items: items,
        ),
      ],
    );
  }

  void _openDraftParties(BuildContext context) {
    final draft = _draftSnapshot;
    if (!draftHasPartyData(draft)) {
      _openDraftEmptySection(
        context,
        title: 'أطراف العقد',
        message: 'لم تُضف بيانات الأطراف بعد.',
        actionLabel: 'إكمال بيانات الأطراف',
        step: 2,
        icon: Icons.people_outline_rounded,
      );
      return;
    }
    final sections = <_ContractDetailSection>[];
    final lessor = _draftPartyItems(draft.lessor);
    final tenant = _draftPartyItems(draft.tenant);
    if (lessor.isNotEmpty) {
      sections.add(
        _ContractDetailSection(
          title: 'المؤجر',
          icon: Icons.person_outline_rounded,
          items: lessor,
        ),
      );
    }
    if (tenant.isNotEmpty) {
      sections.add(
        _ContractDetailSection(
          title: 'المستأجر',
          icon: Icons.person_pin_outlined,
          items: tenant,
        ),
      );
    }
    final representative = draft.representative;
    final representativeItems = <_ContractDetailItem>[
      if (representative.enabled)
        _ContractDetailItem(
          label: 'نوع التمثيل',
          value: '${representative.type} عن ${representative.represents}',
        ),
      if (_meaningfulDraftText(representative.fullName))
        _ContractDetailItem(label: 'الاسم', value: representative.fullName),
      if (_meaningfulDraftText(representative.idNumber))
        _ContractDetailItem(
          label: 'رقم الهوية',
          value: representative.idNumber,
        ),
      if (_meaningfulDraftText(representative.mobile))
        _ContractDetailItem(label: 'الجوال', value: representative.mobile),
      if (_meaningfulDraftText(representative.authorizationNumber))
        _ContractDetailItem(
          label: 'رقم الوكالة أو التفويض',
          value: representative.authorizationNumber,
        ),
    ];
    if (representativeItems.isNotEmpty) {
      sections.add(
        _ContractDetailSection(
          title: 'الوكيل / المفوض',
          icon: Icons.verified_user_outlined,
          items: representativeItems,
        ),
      );
    }
    _openDetailsPage(context, title: 'أطراف العقد', sections: sections);
  }

  List<_ContractDetailItem> _draftPartyItems(PartyData party) =>
      <_ContractDetailItem>[
        if (_meaningfulDraftText(party.fullName))
          _ContractDetailItem(label: 'الاسم', value: party.fullName),
        if (_meaningfulDraftText(party.idNumber))
          _ContractDetailItem(label: 'رقم الهوية', value: party.idNumber),
        if (_meaningfulDraftText(party.birthDate))
          _ContractDetailItem(label: 'تاريخ الميلاد', value: party.birthDate),
        if (_meaningfulDraftText(party.commercialRegistration))
          _ContractDetailItem(
            label: 'رقم السجل التجاري',
            value: party.commercialRegistration,
          ),
        if (_meaningfulDraftText(party.unifiedNumber))
          _ContractDetailItem(
            label: 'الرقم الموحد',
            value: party.unifiedNumber,
          ),
        if (_meaningfulDraftText(party.mobile))
          _ContractDetailItem(label: 'رقم الجوال', value: party.mobile),
        if (_meaningfulDraftText(party.email))
          _ContractDetailItem(label: 'البريد الإلكتروني', value: party.email),
        if (_meaningfulDraftText(party.district))
          _ContractDetailItem(label: 'الحي', value: party.district),
        if (_meaningfulDraftText(party.nationalAddress))
          _ContractDetailItem(
            label: 'العنوان الوطني',
            value: party.nationalAddress,
          ),
        if (_meaningfulDraftText(party.iban))
          _ContractDetailItem(label: 'الآيبان', value: party.iban),
        if (_meaningfulDraftText(party.bankName))
          _ContractDetailItem(label: 'البنك', value: party.bankName),
      ];

  void _openDraftProperty(BuildContext context) {
    final draft = _draftSnapshot;
    if (!draftHasPropertyData(draft)) {
      _openDraftEmptySection(
        context,
        title: 'بيانات العقار والوحدة',
        message: 'لم تُضف بيانات العقار بعد.',
        actionLabel: 'إكمال بيانات العقار',
        step: 1,
        icon: Icons.apartment_outlined,
      );
      return;
    }
    final property = draft.property;
    final values = <String, String>{
      'رقم وثيقة الملكية': property.ownershipDocumentNumber,
      'تاريخ وثيقة الملكية': property.ownershipDocumentDate,
      'الحي': property.district,
      'الشارع': property.street,
      'رقم المبنى': property.buildingNumber,
      'الرقم الإضافي': property.additionalNumber,
      'الرمز البريدي': property.postalCode,
      'اسم المبنى': property.buildingName,
      'عدد الأدوار': property.floorsCount,
      'إجمالي الوحدات': property.totalUnits,
      'رقم الوحدة': property.unitNumber,
      'اسم الوحدة': property.unitName,
      'الدور': property.floor,
      'المساحة':
          property.area.trim().isEmpty ? '' : '${property.area.trim()} م²',
      'عدد الغرف': property.roomsCount,
      'دورات المياه': property.bathroomsCount,
      'عدد الصالات': property.hallsCount,
      'عداد الكهرباء': property.electricityMeter,
      'عداد المياه': property.waterMeter,
      'عداد الغاز': property.gasMeter,
      'ملاحظات العقار': property.notes,
    };
    _openDetailsPage(
      context,
      title: 'بيانات العقار والوحدة',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'البيانات المحفوظة',
          icon: Icons.apartment_outlined,
          items: values.entries
              .where((entry) => _meaningfulDraftText(entry.value))
              .map(
                (entry) => _ContractDetailItem(
                  label: entry.key,
                  value: entry.value,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _openDraftFinancial(BuildContext context) {
    final draft = _draftSnapshot;
    if (!draftHasFinancialData(draft)) {
      _openDraftEmptySection(
        context,
        title: 'الرسوم والمدفوعات',
        message: 'لم تُضف البيانات المالية بعد.',
        actionLabel: 'إكمال البيانات المالية',
        step: 4,
        icon: Icons.account_balance_wallet_outlined,
      );
      return;
    }
    final values = <String, String>{
      'تاريخ بداية العقد': draft.startDate,
      'تاريخ نهاية العقد': draft.endDate,
      'قيمة الإيجار': draft.rentValue.trim().isEmpty
          ? ''
          : '${draft.rentValue.trim()} ريال',
      'مبلغ الضمان': draft.securityDeposit.trim().isEmpty
          ? ''
          : '${draft.securityDeposit.trim()} ريال',
      'عمولة السعي': draft.brokerageFee.trim().isEmpty
          ? ''
          : '${draft.brokerageFee.trim()} ريال',
      'ضريبة القيمة المضافة':
          draft.vatValue.trim().isEmpty ? '' : '${draft.vatValue.trim()} ريال',
      'مبالغ أخرى': draft.otherAmounts.trim().isEmpty
          ? ''
          : '${draft.otherAmounts.trim()} ريال',
      'تاريخ أول دفعة': draft.firstPaymentDate,
    };
    final items = values.entries
        .where((entry) => _meaningfulDraftText(entry.value))
        .map(
          (entry) => _ContractDetailItem(label: entry.key, value: entry.value),
        )
        .toList();
    if (_meaningfulDraftText(draft.rentValue)) {
      items.addAll(<_ContractDetailItem>[
        const _ContractDetailItem(
          label: 'رسوم منصة إيجار',
          value: '299.00 ريال',
        ),
        const _ContractDetailItem(
          label: 'عمولة عقود برو',
          value: '99.00 ريال',
        ),
      ]);
    }
    _openDetailsPage(
      context,
      title: 'الرسوم والمدفوعات',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'البيانات المالية المحفوظة',
          icon: Icons.account_balance_wallet_outlined,
          items: items,
        ),
      ],
    );
  }

  void _openDraftAttachments(BuildContext context) {
    final draft = _draftSnapshot;
    final files = draft.attachments.where((item) => item.uploaded).toList();
    if (files.isEmpty) {
      _openDraftEmptySection(
        context,
        title: 'المرفقات',
        message: 'لا توجد مرفقات محفوظة.',
        actionLabel: 'إضافة المرفقات',
        step: 5,
        icon: Icons.attach_file_rounded,
      );
      return;
    }
    _openDetailsPage(
      context,
      title: 'المرفقات',
      sections: <_ContractDetailSection>[
        _ContractDetailSection.custom(
          title: 'المرفقات المحفوظة',
          icon: Icons.folder_copy_outlined,
          child: Column(
            children: <Widget>[
              for (var index = 0; index < files.length; index++) ...<Widget>[
                _AttachmentRow(
                  title: files[index].title,
                  file: files[index].fileName.trim().isEmpty
                      ? 'مرفق محفوظ'
                      : files[index].fileName.trim(),
                ),
                if (index != files.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openContractData(BuildContext context) {
    if (contract.status == ContractStatus.draft) {
      _openDraftContractData(context);
      return;
    }
    final remaining = contract.contractDetails.entries
        .where((entry) => !_contractIdentityLabels.contains(entry.key))
        .toList();
    final schedule = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'تاريخ بداية',
        'تاريخ نهاية',
        'مدة العقد',
        'قيمة الإيجار',
        'فترة الإيجار',
        'دورة السداد',
        'الدفعات',
        'دفعة',
        'قناة السداد',
        'الضمان',
        'رسوم',
        'عمولة',
        'إجمالي',
      ]),
    );
    final terms = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'الكهرباء',
        'المياه',
        'الغاز',
        'تأجير من الباطن',
        'تجديد تلقائي',
        'خدمات إضافية',
        'شروط إضافية',
      ]),
    );

    _openDetailsPage(
      context,
      title: 'بيانات العقد الأساسية',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'معلومات الطلب',
          icon: Icons.badge_outlined,
          items: <_ContractDetailItem>[
            _ContractDetailItem(label: 'رقم العقد', value: contract.id),
            _ContractDetailItem(
              label: 'رقم الطلب',
              value: contract.requestNumber,
            ),
            _ContractDetailItem(
              label: 'نوع العقد',
              value: contract.type.label,
            ),
            _ContractDetailItem(label: 'تاريخ الطلب', value: contract.date),
            _ContractDetailItem(
              label: 'الحالة الحالية',
              value: contract.status.label,
            ),
          ],
        ),
        if (schedule.isNotEmpty)
          _ContractDetailSection(
            title: 'المدة والقيمة والسداد',
            icon: Icons.event_note_outlined,
            items: _detailItems(schedule),
          ),
        if (terms.isNotEmpty)
          _ContractDetailSection(
            title: 'الشروط والخدمات',
            icon: Icons.rule_folder_outlined,
            items: _detailItems(terms),
          ),
        if (remaining.isNotEmpty)
          _ContractDetailSection(
            title: 'تفاصيل إضافية',
            icon: Icons.info_outline_rounded,
            items: _detailItems(remaining),
          ),
      ],
    );
  }

  void _openParties(BuildContext context) {
    if (contract.status == ContractStatus.draft) {
      _openDraftParties(context);
      return;
    }
    final detailedLessorName = contract.partyDetails['اسم المؤجر']?.trim();
    final detailedTenantName = contract.partyDetails['اسم المستأجر']?.trim();
    final lessorName = detailedLessorName == null || detailedLessorName.isEmpty
        ? contract.lessorName
        : detailedLessorName;
    final tenantName = detailedTenantName == null || detailedTenantName.isEmpty
        ? contract.tenantName
        : detailedTenantName;
    final remaining = contract.partyDetails.entries.toList();
    remaining.removeWhere(
      (entry) => entry.key == 'اسم المؤجر' || entry.key == 'اسم المستأجر',
    );
    final lessor = _takeEntries(
      remaining,
      (label) => label.contains('المؤجر') || label.contains('للمؤجر'),
    );
    final tenant = _takeEntries(
      remaining,
      (label) => label.contains('المستأجر') || label.contains('للمستأجر'),
    );
    final representative = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'الوكيل',
        'الوكالة',
        'المفوض',
        'التفويض',
        'يمثل',
        'جهة الإصدار',
      ]),
    );

    _openDetailsPage(
      context,
      title: 'أطراف العقد',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'المؤجر',
          icon: Icons.person_outline_rounded,
          items: <_ContractDetailItem>[
            _ContractDetailItem(label: 'الاسم', value: lessorName),
            ..._detailItems(lessor),
          ],
        ),
        _ContractDetailSection(
          title: 'المستأجر',
          icon: Icons.person_pin_outlined,
          items: <_ContractDetailItem>[
            _ContractDetailItem(label: 'الاسم', value: tenantName),
            ..._detailItems(tenant),
          ],
        ),
        if (representative.isNotEmpty)
          _ContractDetailSection(
            title: 'الوكيل / المفوض',
            icon: Icons.verified_user_outlined,
            items: _detailItems(representative),
          ),
        if (remaining.isNotEmpty)
          _ContractDetailSection(
            title: 'تفاصيل إضافية',
            icon: Icons.info_outline_rounded,
            items: _detailItems(remaining),
          ),
      ],
    );
  }

  void _openProperty(BuildContext context) {
    if (contract.status == ContractStatus.draft) {
      _openDraftProperty(context);
      return;
    }
    final remaining = contract.propertyDetails.entries.toList();
    final ownership = _takeEntries(
      remaining,
      (label) =>
          label.contains('وثيقة') ||
          label.contains('الملكية') ||
          label == 'مصدر العقار',
    );
    final address = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'المدينة',
        'الحي',
        'الشارع',
        'رقم المبنى',
        'الرقم الإضافي',
        'الرمز البريدي',
        'العنوان الوطني',
      ]),
    );
    final facilities = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'غرفة عاملة',
        'مطبخ',
        'مستودع',
        'مجلس',
        'مكيف',
        'تكييف',
        'موقف',
        'عداد',
      ]),
    );
    final propertyAndUnit = _takeEntries(
      remaining,
      (label) => _containsAny(label, const <String>[
        'استخدام العقار',
        'نوع العقار',
        'اسم المبنى',
        'عدد الأدوار',
        'الوحدات',
        'الوحدة',
        'الدور',
        'المساحة',
        'الغرف',
        'دورات المياه',
        'الصالات',
        'حالة التأثيث',
        'ملاحظات العقار',
      ]),
    );

    _openDetailsPage(
      context,
      title: 'بيانات العقار والوحدة',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'ملخص العقار',
          icon: Icons.apartment_outlined,
          items: <_ContractDetailItem>[
            _ContractDetailItem(label: 'العنوان', value: contract.property),
            _ContractDetailItem(
              label: 'نوع العقد',
              value: contract.type.label,
            ),
          ],
        ),
        if (ownership.isNotEmpty)
          _ContractDetailSection(
            title: 'بيانات الملكية',
            icon: Icons.verified_outlined,
            items: _detailItems(ownership),
          ),
        if (address.isNotEmpty)
          _ContractDetailSection(
            title: 'العنوان الوطني',
            icon: Icons.location_on_outlined,
            items: _detailItems(address),
          ),
        if (propertyAndUnit.isNotEmpty)
          _ContractDetailSection(
            title: 'العقار والوحدة',
            icon: Icons.home_work_outlined,
            items: _detailItems(propertyAndUnit),
          ),
        if (facilities.isNotEmpty)
          _ContractDetailSection(
            title: 'المرافق والعدادات',
            icon: Icons.home_repair_service_outlined,
            items: _detailItems(facilities),
          ),
        if (remaining.isNotEmpty)
          _ContractDetailSection(
            title: 'تفاصيل إضافية',
            icon: Icons.info_outline_rounded,
            items: _detailItems(remaining),
          ),
      ],
    );
  }

  void _openFees(BuildContext context) {
    if (contract.status == ContractStatus.draft) {
      _openDraftFinancial(context);
      return;
    }
    final paid = contract.paymentStatus == 'paid' ||
        contract.paymentId.trim().isNotEmpty ||
        contract.status == ContractStatus.processing ||
        contract.status == ContractStatus.authenticated;
    final paymentItems = <_ContractDetailItem>[
      _ContractDetailItem(
        label: 'حالة الدفع',
        value: paid ? 'مدفوع' : 'بانتظار الدفع',
      ),
      const _ContractDetailItem(
        label: 'طرق الدفع',
        value: 'مدى، Visa / Mastercard، Apple Pay، STC Pay',
      ),
      if (paid && contract.paymentReference.trim().isNotEmpty)
        _ContractDetailItem(
          label: 'رقم العملية',
          value: contract.paymentReference,
        ),
      if (paid && contract.invoiceNumber.trim().isNotEmpty)
        _ContractDetailItem(
          label: 'رقم الفاتورة',
          value: contract.invoiceNumber,
        ),
      if (paid && contract.paymentMethod.trim().isNotEmpty)
        _ContractDetailItem(
          label: 'طريقة الدفع',
          value: _paymentMethodLabel(contract.paymentMethod),
        ),
      if (paid && contract.cardLast4.trim().isNotEmpty)
        _ContractDetailItem(
          label: 'البطاقة',
          value: '${contract.cardBrand} •••• ${contract.cardLast4}',
        ),
      if (paid && contract.paidAt.trim().isNotEmpty)
        _ContractDetailItem(
          label: 'تاريخ الدفع',
          value: contract.paidAt,
        ),
    ];

    _openDetailsPage(
      context,
      title: 'الرسوم والمدفوعات',
      sections: <_ContractDetailSection>[
        _ContractDetailSection(
          title: 'ملخص الرسوم',
          icon: Icons.receipt_long_outlined,
          items: <_ContractDetailItem>[
            const _ContractDetailItem(
              label: 'رسوم منصة إيجار',
              value: '299.00 ريال',
            ),
            const _ContractDetailItem(
              label: 'عمولة عقود برو',
              value: '99.00 ريال',
            ),
            _ContractDetailItem(
              label: 'إجمالي الرسوم',
              value: '${contract.totalFees.toStringAsFixed(2)} ريال',
            ),
          ],
        ),
        _ContractDetailSection(
          title: 'حالة وبيانات الدفع',
          icon: Icons.payments_outlined,
          items: paymentItems,
        ),
      ],
    );
  }

  void _openAttachments(BuildContext context) {
    if (contract.status == ContractStatus.draft) {
      _openDraftAttachments(context);
      return;
    }
    final attachments = contract.attachmentFiles;
    if (contract.status == ContractStatus.rejected && attachments.isEmpty) {
      _openDetailsPage(
        context,
        title: 'المرفقات',
        sections: const <_ContractDetailSection>[
          _ContractDetailSection.custom(
            title: 'مستندات العقد',
            icon: Icons.folder_copy_outlined,
            child: EmptyState(
              icon: Icons.attach_file_rounded,
              title: 'لا توجد مرفقات محفوظة',
              subtitle: 'لا توجد ملفات مرفوعة مرتبطة بهذا الطلب.',
            ),
          ),
        ],
      );
      return;
    }
    final files = attachments.isEmpty
        ? const <MapEntry<String, String>>[
            MapEntry<String, String>('هوية المؤجر', 'lessor_id.pdf'),
            MapEntry<String, String>('هوية المستأجر', 'tenant_id.pdf'),
            MapEntry<String, String>('وثيقة الملكية', 'ownership.pdf'),
          ]
        : attachments.entries.toList();
    _openDetailsPage(
      context,
      title: 'المرفقات',
      sections: <_ContractDetailSection>[
        _ContractDetailSection.custom(
          title: 'مستندات العقد',
          icon: Icons.folder_copy_outlined,
          child: Column(
            children: <Widget>[
              for (var index = 0; index < files.length; index++) ...<Widget>[
                _AttachmentRow(
                  title: files[index].key,
                  file: files[index].value,
                  showDownload: contract.status != ContractStatus.rejected,
                ),
                if (index != files.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const Set<String> _contractIdentityLabels = <String>{
    'رقم العقد',
    'رقم الطلب',
    'نوع العقد',
    'تاريخ الطلب',
    'الحالة الحالية',
  };

  static bool _containsAny(String value, List<String> parts) {
    return parts.any(value.contains);
  }

  static List<MapEntry<String, String>> _takeEntries(
    List<MapEntry<String, String>> source,
    bool Function(String label) predicate,
  ) {
    final result = source.where((entry) => predicate(entry.key)).toList();
    source.removeWhere((entry) => predicate(entry.key));
    return result;
  }

  static List<_ContractDetailItem> _detailItems(
    Iterable<MapEntry<String, String>> entries,
  ) {
    return entries
        .map(
          (entry) => _ContractDetailItem(
            label: entry.key,
            value: entry.value,
          ),
        )
        .toList();
  }

  String _paymentMethodLabel(String value) {
    return switch (value) {
      'mada' => 'مدى',
      'visaMastercard' => 'Visa / Mastercard',
      'applePay' => 'Apple Pay - Demo',
      'stcPay' => 'STC Pay - Demo',
      _ => value,
    };
  }
}

class _DraftEmptyState extends StatelessWidget {
  final String message;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onPressed;

  const _DraftEmptyState({
    required this.message,
    required this.actionLabel,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 42, color: context.ejarzTheme.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: actionLabel,
            icon: Icons.edit_note_rounded,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _ContractSectionDetailsScreen extends StatelessWidget {
  final String title;
  final List<_ContractDetailSection> sections;

  const _ContractSectionDetailsScreen({
    required this.title,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DetailAppBar(title: title),
      bottomNavigationBar: _contractDetailsBottomNavigation(context),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < sections.length; index++) ...<Widget>[
                SectionTitle(
                  title: sections[index].title,
                  icon: sections[index].icon,
                ),
                const SizedBox(height: 8),
                if (sections[index].child != null)
                  sections[index].child!
                else
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 3,
                    ),
                    child: Column(
                      children: <Widget>[
                        for (var itemIndex = 0;
                            itemIndex < sections[index].items.length;
                            itemIndex++) ...<Widget>[
                          _InfoLine(
                            label: sections[index].items[itemIndex].label,
                            value: sections[index].items[itemIndex].value,
                          ),
                          if (itemIndex != sections[index].items.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                if (index != sections.length - 1) const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContractDetailSection {
  final String title;
  final IconData icon;
  final List<_ContractDetailItem> items;
  final Widget? child;

  const _ContractDetailSection({
    required this.title,
    required this.icon,
    required this.items,
  }) : child = null;

  const _ContractDetailSection.custom({
    required this.title,
    required this.icon,
    required Widget this.child,
  }) : items = const <_ContractDetailItem>[];
}

class _ContractDetailItem {
  final String label;
  final String value;

  const _ContractDetailItem({required this.label, required this.value});
}

class _MissingRequirementsCard extends StatelessWidget {
  final ContractRecord contract;

  const _MissingRequirementsCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      color: AppColors.red.withValues(alpha: 0.045),
      border: Border.all(color: AppColors.red.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'نواقص مطلوبة لاستكمال الطلب',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: context.sp(13),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in contract.missingRequirements) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: context.ejarzTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.ejarzTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(12),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SecondaryButton(
            label: 'استكمال النواقص',
            icon: Icons.edit_note_rounded,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _MissingResponseSheet(contract: contract),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingResponseSheet extends StatefulWidget {
  final ContractRecord contract;

  const _MissingResponseSheet({required this.contract});

  @override
  State<_MissingResponseSheet> createState() => _MissingResponseSheetState();
}

class _MissingResponseSheetState extends State<_MissingResponseSheet> {
  late MissingRequirement _selected;
  final TextEditingController _message = TextEditingController();
  final TextEditingController _fileName = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.contract.missingRequirements.first;
  }

  @override
  void dispose() {
    _message.dispose();
    _fileName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unresolved = widget.contract.missingRequirements
        .where((item) => !item.resolved)
        .toList();
    final items =
        unresolved.isEmpty ? widget.contract.missingRequirements : unresolved;
    if (!items.contains(_selected)) _selected = items.first;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: ResponsiveContent(
          maxWidth: 620,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppPageHeader(
                title: 'استكمال النواقص',
                subtitle:
                    'أرسل البيانات أو المرفقات المطلوبة ليتم مراجعتها من الإدارة.',
                icon: Icons.task_alt_outlined,
              ),
              const SizedBox(height: 12),
              AppDropdownField(
                label: 'النقص المطلوب',
                value: _selected.title,
                items: items.map((item) => item.title).toList(),
                icon: Icons.error_outline_rounded,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selected = items.firstWhere((item) => item.title == value);
                  });
                },
              ),
              const SizedBox(height: 6),
              Text(
                _selected.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (_selected.description.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  _selected.description,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(12),
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AppTextField(
                label: 'ملاحظات أو توضيح',
                hint: 'اكتب ما تم تعديله أو أي ملاحظة مهمة',
                controller: _message,
                icon: Icons.edit_note_rounded,
                maxLines: 4,
                required: true,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'اسم الملف المرفق',
                hint: 'اختياري - مثال: commercial_record.pdf',
                controller: _fileName,
                icon: Icons.attach_file_rounded,
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: _sending ? 'جاري الإرسال...' : 'إرسال التصحيح',
                icon: Icons.send_rounded,
                loading: _sending,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.isEmpty && _fileName.text.trim().isEmpty) {
      showAppSnackBar(context, 'أدخل توضيحًا أو اسم ملف مرفق');
      return;
    }
    setState(() => _sending = true);
    try {
      await AppScope.of(context, listen: false)
          .submitMissingRequirementResponse(
        contract: widget.contract,
        requirement: _selected,
        message: message.isEmpty ? 'تم استكمال المطلوب.' : message,
        fileName: _fileName.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(context, 'تم إرسال التصحيح للمراجعة');
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'تعذر إرسال التصحيح الآن');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _RejectedContractBanner extends StatelessWidget {
  final ContractRecord contract;

  const _RejectedContractBanner({required this.contract});

  @override
  Widget build(BuildContext context) {
    final reason = contract.rejectionReason
        .trim()
        .replaceFirst(RegExp(r'[.!؟،؛:]+$'), '')
        .trim();
    final message = reason.isEmpty
        ? 'تم رفض هذا الطلب نهائيًا بعد مراجعته. لا يمكن تعديله أو إعادة إرساله. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني لمعرفة المزيد.'
        : 'تم رفض الطلب رقم ${contract.requestNumber} نهائيًا بسبب: $reason. لا يمكن تعديل هذا الطلب أو إعادة إرساله. يمكنك تقديم طلب جديد، أو التواصل مع الدعم الفني إذا احتجت إلى توضيح.';
    return AppCard(
      padding: const EdgeInsets.all(14),
      color: AppColors.red.withValues(alpha: 0.055),
      border: Border.all(color: AppColors.red.withValues(alpha: 0.24)),
      shadows: const <BoxShadow>[],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cancel_outlined, color: AppColors.red),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'تم رفض طلب العقد نهائيًا',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: TextStyle(
                    color: context.ejarzTheme.text,
                    fontSize: context.sp(12.5),
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

class _ContractHero extends StatelessWidget {
  final ContractRecord contract;

  const _ContractHero({required this.contract});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 18,
            17,
            compact ? 13 : 16,
            17,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[Color(0xFF0B8062), Color(0xFF005E49)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'رقم الطلب',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: context.sp(12),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contract.requestNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: context.sp(compact ? 20 : 22),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'تاريخ الطلب: ${contract.date}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: context.sp(12.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: contract.status.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            contract.status.icon,
                            color: Colors.white,
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              contract.status.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 4 : 8),
              HeroContractIllustration(
                width: compact ? 94 : 122,
                height: compact ? 92 : 110,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final List<StatusTimelineItem> items;

  const _StatusTimeline({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var i = 0; i < items.length; i++)
          _TimelineItem(
            item: items[i],
            isLast: i == items.length - 1,
          ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final StatusTimelineItem item;
  final bool isLast;

  const _TimelineItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final rejected = item.eventStatus == ContractStatus.rejected;
    final color = rejected
        ? ContractStatus.rejected.color
        : item.current
            ? AppColors.orange
            : item.completed
                ? AppColors.primary
                : context.ejarzTheme.border;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: item.current
          ? const EdgeInsets.symmetric(vertical: 10, horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 8),
      decoration: item.current
          ? BoxDecoration(
              color: rejected
                  ? ContractStatus.rejected.paleColor
                  : AppColors.secondaryLight.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 32,
            child: Column(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: item.completed || item.current
                        ? color
                        : context.ejarzTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: rejected
                      ? const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18)
                      : item.completed
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 18)
                          : item.current
                              ? const Icon(Icons.schedule_rounded,
                                  color: Colors.white, size: 17)
                              : null,
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 46,
                    color: item.completed
                        ? AppColors.primary
                        : context.ejarzTheme.border,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: context.sp(14),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.5),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                item.date,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  fontSize: context.sp(10.5),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.time,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  fontSize: context.sp(10.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DetailsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
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
                      fontSize: context.sp(11.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_back_ios_new_rounded,
                size: 15, color: context.ejarzTheme.muted),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            textAlign: TextAlign.start,
            style: TextStyle(
              color: context.ejarzTheme.muted,
              fontWeight: FontWeight.w600,
            ),
          );
          final valueWidget = Text(
            value,
            textAlign:
                constraints.maxWidth >= 520 ? TextAlign.end : TextAlign.start,
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                labelWidget,
                const SizedBox(height: 5),
                valueWidget,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final String title;
  final String file;
  final bool showDownload;

  const _AttachmentRow({
    required this.title,
    required this.file,
    this.showDownload = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(13),
      shadows: const <BoxShadow>[],
      child: Row(
        children: <Widget>[
          const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(file,
                    style: TextStyle(
                        color: context.ejarzTheme.muted, fontSize: 12)),
              ],
            ),
          ),
          if (showDownload)
            IconButton(
              onPressed: () => showAppSnackBar(context, 'بدأ تنزيل $file'),
              icon: const Icon(Icons.download_rounded),
            ),
        ],
      ),
    );
  }
}
