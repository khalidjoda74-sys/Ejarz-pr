import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/illustrations.dart';
import 'payment_demo.dart';

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
      appBar: AppBar(
        title: const Text('تفاصيل العقد'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ContractHero(contract: contract),
              if (contract.customerVisibleNote.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                InfoBanner(
                  text: contract.customerVisibleNote,
                  icon: Icons.info_outline_rounded,
                  color: contract.status.color,
                ),
              ],
              if (contract.missingRequirements.isNotEmpty) ...<Widget>[
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
                      onTap: () => _showContractData(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.people_outline_rounded,
                      title: 'الأطراف',
                      subtitle: 'عرض بيانات المؤجر والمستأجر',
                      onTap: () => _showParties(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: contract.type.icon,
                      title: 'العقار',
                      subtitle: 'تفاصيل العقار وعنوانه',
                      onTap: () => _showProperty(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'الرسوم',
                      subtitle: 'تفاصيل الرسوم والمدفوعات',
                      onTap: () => _showFees(context),
                    ),
                    const Divider(),
                    _DetailsRow(
                      icon: Icons.attach_file_rounded,
                      title: 'المرفقات',
                      subtitle: 'المستندات والنسخ المرتبطة بالطلب',
                      onTap: () => _showAttachments(context),
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
                    if (contract.status == ContractStatus.awaitingPayment &&
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
                    SecondaryButton(
                      label: 'الدعم الفني',
                      icon: Icons.support_agent_rounded,
                      onPressed: () => _createContractSupportTicket(context),
                    ),
                  ];
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

  Future<void> _createContractSupportTicket(BuildContext context) async {
    try {
      await AppScope.of(context, listen: false).createSupportTicket(
        contract: contract,
        subject: 'دعم عقد ${contract.requestNumber}',
        message:
            'أحتاج مساعدة بخصوص الطلب ${contract.requestNumber} - ${contract.title}.',
        priority:
            contract.status == ContractStatus.missingData ? 'high' : 'normal',
      );
      if (context.mounted) {
        showAppSnackBar(context, 'تم إنشاء تذكرة دعم لهذا العقد');
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(context, 'تعذر إرسال طلب الدعم الآن');
      }
    }
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

  void _showSheet(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            6,
            18,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  void _showContractData(BuildContext context) {
    _showSheet(
      context,
      title: 'بيانات العقد',
      children: <Widget>[
        _InfoLine(label: 'رقم العقد', value: contract.id),
        _InfoLine(label: 'رقم الطلب', value: contract.requestNumber),
        _InfoLine(label: 'نوع العقد', value: contract.type.label),
        _InfoLine(label: 'تاريخ الطلب', value: contract.date),
        _InfoLine(label: 'الحالة الحالية', value: contract.status.label),
        for (final entry in contract.contractDetails.entries)
          _InfoLine(label: entry.key, value: entry.value),
      ],
    );
  }

  void _showParties(BuildContext context) {
    _showSheet(
      context,
      title: 'أطراف العقد',
      children: <Widget>[
        _InfoLine(label: 'المؤجر', value: contract.lessorName),
        _InfoLine(label: 'المستأجر', value: contract.tenantName),
        for (final entry in contract.partyDetails.entries)
          _InfoLine(label: entry.key, value: entry.value),
      ],
    );
  }

  void _showProperty(BuildContext context) {
    _showSheet(
      context,
      title: 'بيانات العقار',
      children: <Widget>[
        _InfoLine(label: 'العنوان', value: contract.property),
        _InfoLine(label: 'النوع', value: contract.type.label),
        for (final entry in contract.propertyDetails.entries)
          _InfoLine(label: entry.key, value: entry.value),
      ],
    );
  }

  void _showFees(BuildContext context) {
    final paid = contract.paymentStatus == 'paid' ||
        contract.paymentId.trim().isNotEmpty ||
        contract.status == ContractStatus.processing ||
        contract.status == ContractStatus.authenticated;
    _showSheet(
      context,
      title: 'الرسوم والمدفوعات',
      children: <Widget>[
        const _InfoLine(label: 'رسوم منصة إيجار', value: '299.00 ريال'),
        const _InfoLine(label: 'عمولة عقود برو', value: '99.00 ريال'),
        _InfoLine(
          label: 'إجمالي الرسوم',
          value: '${contract.totalFees.toStringAsFixed(2)} ريال',
        ),
        _InfoLine(
          label: 'حالة الدفع',
          value: paid ? 'مدفوع' : 'بانتظار الدفع',
        ),
        const _InfoLine(
          label: 'طرق الدفع',
          value: 'مدى، Visa / Mastercard، Apple Pay، STC Pay',
        ),
        if (paid && contract.paymentReference.trim().isNotEmpty)
          _InfoLine(label: 'رقم العملية', value: contract.paymentReference),
        if (paid && contract.invoiceNumber.trim().isNotEmpty)
          _InfoLine(label: 'رقم الفاتورة', value: contract.invoiceNumber),
        if (paid && contract.paymentMethod.trim().isNotEmpty)
          _InfoLine(
            label: 'طريقة الدفع',
            value: _paymentMethodLabel(contract.paymentMethod),
          ),
        if (paid && contract.cardLast4.trim().isNotEmpty)
          _InfoLine(
            label: 'البطاقة',
            value: '${contract.cardBrand} •••• ${contract.cardLast4}',
          ),
        if (paid && contract.paidAt.trim().isNotEmpty)
          _InfoLine(label: 'تاريخ الدفع', value: contract.paidAt),
      ],
    );
  }

  void _showAttachments(BuildContext context) {
    final attachments = contract.attachmentFiles;
    _showSheet(
      context,
      title: 'المرفقات',
      children: <Widget>[
        if (attachments.isEmpty) ...const <Widget>[
          _AttachmentRow(title: 'هوية المؤجر', file: 'lessor_id.pdf'),
          SizedBox(height: 10),
          _AttachmentRow(title: 'هوية المستأجر', file: 'tenant_id.pdf'),
          SizedBox(height: 10),
          _AttachmentRow(title: 'وثيقة الملكية', file: 'ownership.pdf'),
        ] else
          for (final entry in attachments.entries) ...<Widget>[
            _AttachmentRow(title: entry.key, file: entry.value),
            if (entry.key != attachments.keys.last) const SizedBox(height: 10),
          ],
      ],
    );
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
    final color = item.current
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
              color: AppColors.secondaryLight.withValues(alpha: 0.60),
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
                  child: item.completed
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final String title;
  final String file;

  const _AttachmentRow({required this.title, required this.file});

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
          IconButton(
            onPressed: () => showAppSnackBar(context, 'بدأ تنزيل $file'),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
    );
  }
}
