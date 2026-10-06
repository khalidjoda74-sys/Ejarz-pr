import 'package:flutter/material.dart';
import '../widgets/load_more_records.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/firebase_repository.dart';
import '../core/firebase_bootstrap.dart';
import '../core/demo_config.dart';
import '../core/models.dart';
import '../core/runtime_config.dart';
import '../core/receipt_document.dart';
import '../widgets/common.dart';
import '../widgets/service_unavailable.dart';

String _date(Object? value) => value is Timestamp
    ? value.toDate().toLocal().toString().split('.').first
    : '${value ?? ''}';
String _amount(Object? value) => (value is num ? value : 0).toStringAsFixed(2);
String _state(Object? v) =>
    const {
      'pending': 'بانتظار الاعتماد',
      'paid': 'مدفوع',
      'failed': 'فشل الدفع',
      'refunded': 'مسترد',
      'partiallyRefunded': 'استرداد جزئي'
    }[v] ??
    '${v ?? ''}';
Future<void> openSupportContact(BuildContext context, String kind) async {
  final value = AppRuntime.text(kind, '');
  if (value.isEmpty) {
    showAppSnackBar(
        context, 'لم يتم إعداد وسيلة التواصل هذه بعد. يمكنك إرسال تذكرة دعم.');
    return;
  }
  final uri = kind == 'supportEmail'
      ? Uri(scheme: 'mailto', path: value)
      : kind == 'supportWhatsapp'
          ? Uri.parse('https://wa.me/${value.replaceAll(RegExp(r'\D'), '')}')
          : Uri(scheme: 'tel', path: value);
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      showAppSnackBar(context, 'تعذر فتح تطبيق التواصل.');
    }
  } catch (_) {
    if (context.mounted) showAppSnackBar(context, 'تعذر فتح تطبيق التواصل.');
  }
}

class SavedPartiesScreen extends StatelessWidget {
  const SavedPartiesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (!AppRuntime.service('savedParties')) return const ServiceUnavailable();
    return Scaffold(
        appBar: AppBar(title: const Text('الأطراف المحفوظة')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editSavedParty(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('إضافة طرف')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (c.recordsError.isNotEmpty) InfoBanner(text: c.recordsError),
              if (c.savedParties.isEmpty)
                const InfoBanner(
                    text:
                        'لا توجد أطراف محفوظة. أضف طرفًا لاستخدامه في عقودك.'),
              for (final p in c.savedParties)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                        child: ListTile(
                            title: Text('${p['fullName']}'),
                            subtitle: Text(
                                '${p['mobile'] ?? ''} · ${p['kind'] == 'company' ? 'منشأة' : 'فرد'}'),
                            onTap: () => editSavedParty(context, record: p),
                            trailing: const Icon(Icons.edit_outlined)))),
              const LoadMoreRecords('savedParties'),
            ]));
  }
}

Future<void> editSavedParty(BuildContext context,
    {Map<String, dynamic>? record, PartyData? initial}) async {
  final result = await Navigator.of(context).push<PartyData>(MaterialPageRoute(
      settings: const RouteSettings(name: 'saved_parties'),
      builder: (_) => PartyEditorScreen(record: record, initial: initial)));
  if (result != null && context.mounted) {
    showAppSnackBar(context, 'تم حفظ الطرف.');
  }
}

class PartyEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? record;
  final PartyData? initial;
  const PartyEditorScreen({super.key, this.record, this.initial});
  @override
  State<PartyEditorScreen> createState() => _PartyEditorState();
}

class _PartyEditorState extends State<PartyEditorScreen> {
  late PartyData party;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    party = FirebaseRepository.partyFromMap(widget.record ??
        (widget.initial == null
            ? {}
            : FirebaseRepository.partyDataToMap(widget.initial!)));
  }

  Future<void> save({bool archived = false}) async {
    if (party.fullName.trim().isEmpty) {
      showAppSnackBar(context, 'أدخل اسم الطرف.');
      return;
    }
    setState(() => saving = true);
    try {
      await AppScope.of(context, listen: false)
          .saveParty(party, id: widget.record?['id'] ?? '', archived: archived);
      if (mounted) Navigator.pop(context, party);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
            context, 'تعذر حفظ الطرف. تحقق من الاتصال وإتاحة الخدمة.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.record == null ? 'إضافة طرف' : 'تعديل الطرف')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            AppDropdownField(
                label: 'نوع الطرف',
                value: party.kind == PartyKind.company ? 'منشأة' : 'فرد',
                items: const ['فرد', 'منشأة'],
                onChanged: (v) => setState(() => party.kind =
                    v == 'منشأة' ? PartyKind.company : PartyKind.individual)),
            for (final field in <(String, String, void Function(String))>[
              (
                'الاسم الكامل / المنشأة',
                party.fullName,
                (v) => party.fullName = v
              ),
              ('رقم الجوال', party.mobile, (v) => party.mobile = v),
              ('البريد', party.email, (v) => party.email = v),
              ('نوع الهوية', party.idType, (v) => party.idType = v),
              ('رقم الهوية', party.idNumber, (v) => party.idNumber = v),
              (
                'تاريخ الميلاد YYYY/MM/DD',
                party.birthDate,
                (v) => party.birthDate = v
              ),
              ('المدينة', party.city, (v) => party.city = v),
              ('الحي', party.district, (v) => party.district = v),
              (
                'العنوان الوطني',
                party.nationalAddress,
                (v) => party.nationalAddress = v
              ),
              if (party.kind == PartyKind.company) ...[
                (
                  'السجل التجاري',
                  party.commercialRegistration,
                  (v) => party.commercialRegistration = v
                ),
                (
                  'الرقم الموحد',
                  party.unifiedNumber,
                  (v) => party.unifiedNumber = v
                ),
                (
                  'اسم المفوض',
                  party.authorizedPersonName,
                  (v) => party.authorizedPersonName = v
                ),
                (
                  'هوية المفوض',
                  party.authorizedPersonId,
                  (v) => party.authorizedPersonId = v
                )
              ],
              ('الآيبان', party.iban, (v) => party.iban = v),
              ('البنك', party.bankName, (v) => party.bankName = v),
              (
                'صاحب الحساب',
                party.accountOwner,
                (v) => party.accountOwner = v
              ),
            ])
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AppTextField(
                      hint: '',
                      key: ValueKey(field.$1),
                      label: field.$1,
                      initialValue: field.$2,
                      onChanged: field.$3)),
            const SizedBox(height: 20),
            PrimaryButton(
                label: 'حفظ الطرف', loading: saving, onPressed: () => save()),
            if (widget.record != null)
              TextButton(
                  onPressed: saving ? null : () => save(archived: true),
                  child: const Text('أرشفة الطرف')),
          ])));
}

Future<PartyData?> chooseSavedParty(BuildContext context) async {
  final c = AppScope.of(context, listen: false);
  if (!AppRuntime.service('savedParties')) {
    showAppSnackBar(context, 'خدمة الأطراف متوقفة مؤقتًا.');
    return null;
  }
  if (c.savedParties.isEmpty) {
    showAppSnackBar(context, 'أضف طرفًا من صفحة الأطراف المحفوظة أولًا.');
    return null;
  }
  return showModalBottomSheet<PartyData>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => AnimatedBuilder(
          animation: c,
          builder: (_, __) => ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('اختيار طرف محفوظ')),
                for (final p in c.savedParties)
                  ListTile(
                      title: Text('${p['fullName']}'),
                      subtitle: Text('${p['mobile'] ?? ''}'),
                      onTap: () => Navigator.pop(
                          context, FirebaseRepository.partyFromMap(p))),
                const LoadMoreRecords('savedParties'),
              ])));
}

class AccountWallet extends StatelessWidget {
  const AccountWallet({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context), payments = c.paymentRecords;
    final gross = c.customerMetrics['grossHalalas'] is num
        ? (c.customerMetrics['grossHalalas'] as num) / 100
        : payments
            .where((p) =>
                p['isDemo'] != true &&
                p['verified'] == true &&
                ['paid', 'refunded', 'partiallyRefunded'].contains(p['status']))
            .fold<double>(
                0, (n, p) => n + (p['amount'] as num? ?? 0).toDouble());
    final refunds = c.customerMetrics['refundHalalas'] is num
        ? (c.customerMetrics['refundHalalas'] as num) / 100
        : payments
            .where((p) => p['isDemo'] != true && p['verified'] == true)
            .fold<double>(
                0,
                (n, p) =>
                    n +
                    (p['refundedAmount'] as num? ??
                            (p['status'] == 'refunded'
                                ? p['amount'] as num? ?? 0
                                : 0))
                        .toDouble());
    return SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
      const AppPageHeader(
          title: 'المحفظة والمدفوعات',
          subtitle: 'مدفوعات رسوم الخدمة والفواتير المرتبطة بها.',
          icon: Icons.account_balance_wallet_outlined),
      const SizedBox(height: 18),
      AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('صافي المدفوعات الفعلية'),
        Text('${(gross - refunds).toStringAsFixed(2)} ر.س',
            style: Theme.of(context).textTheme.headlineMedium),
        Text('الاستردادات: ${refunds.toStringAsFixed(2)} ر.س')
      ])),
      const SizedBox(height: 14),
      SecondaryButton(
          label: 'الفواتير والإيصالات',
          icon: Icons.receipt_long_outlined,
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  settings: const RouteSettings(name: 'wallet'),
                  builder: (_) => const CustomerInvoicesScreen()))),
      const SizedBox(height: 14),
      InfoBanner(
          text: AppRuntime.payments['manualTransferEnabled'] == true
              ? 'التحويل البنكي متاح من صفحة دفع العقد.'
              : 'الدفع الإلكتروني بانتظار استكمال الربط. لا توجد بطاقة محفوظة.'),
      if (c.recordsError.isNotEmpty) InfoBanner(text: c.recordsError),
      if (payments.isEmpty)
        InfoBanner(
            text: AppRuntime.text('walletEmptySubtitle',
                'ستظهر المدفوعات هنا بعد إنشاء عملية دفع.')),
      for (final p in payments)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
                child: ListTile(
                    title: Text(
                        '${_amount(p['amount'])} ر.س · ${_state(p['status'])}'),
                    subtitle: Text(
                        '${p['isDemo'] == true ? 'تجريبي · ' : ''}رقم الطلب: \u2066${c.requestNumberForRecord(p)}\u2069\n${_date(p['createdAt'])}')))),
      const LoadMoreRecords('payments'),
    ]));
  }
}

class CustomerInvoicesScreen extends StatelessWidget {
  const CustomerInvoicesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('الفواتير والإيصالات')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          if (c.invoices.isEmpty)
            const InfoBanner(text: 'لا توجد فواتير مرتبطة بحسابك بعد.'),
          for (final invoice in c.invoices)
            _InvoiceReceiptCard(key: ValueKey(invoice['id']), invoice: invoice),
          const LoadMoreRecords('invoices'),
        ]));
  }
}

class _InvoiceReceiptCard extends StatefulWidget {
  final Map<String, dynamic> invoice;
  const _InvoiceReceiptCard({super.key, required this.invoice});
  @override
  State<_InvoiceReceiptCard> createState() => _InvoiceReceiptCardState();
}

class _InvoiceReceiptCardState extends State<_InvoiceReceiptCard> {
  Future<Map<String, dynamic>>? _details;
  bool _downloading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _details ??= AppScope.of(context).invoiceReceiptDetails(widget.invoice);
  }

  @override
  void didUpdateWidget(covariant _InvoiceReceiptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.invoice, widget.invoice)) {
      _details = AppScope.of(context, listen: false)
          .invoiceReceiptDetails(widget.invoice);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    final controller = AppScope.of(context, listen: false);
    final generation = controller.accountGeneration;
    setState(() => _downloading = true);
    try {
      final details = await controller.invoiceReceiptDetails(widget.invoice);
      if (!mounted || !controller.isCurrentAccount(generation)) return;
      await downloadReceipt(details,
          isCurrentAccount: () =>
              mounted && controller.isCurrentAccount(generation));
    } catch (_) {
      if (mounted && controller.isCurrentAccount(generation)) {
        showAppSnackBar(context, 'تعذر تنزيل المستند. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _details,
        builder: (context, snapshot) {
          final invoice = snapshot.data ?? widget.invoice;
          final number = AppScope.of(context).requestNumberForRecord(invoice);
          return AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${invoice['invoiceNumber'] ?? 'رقم المستند غير متاح'}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    '${_amount(invoice['amount'])} ر.س · ${_state(invoice['status'])}'),
                Row(children: [
                  const Text('رقم الطلب: '),
                  Flexible(
                      child: Text(number, textDirection: TextDirection.ltr))
                ]),
                if (invoice['providerReference'] != null) ...[
                  const SizedBox(height: 4),
                  const Text('مرجع عملية الدفع'),
                  Text('${invoice['providerReference']}',
                      textDirection: TextDirection.ltr),
                ],
                Text(_date(invoice['createdAt'])),
                if (invoice['isDemo'] == true)
                  const Text('مستند تجريبي لا يثبت تحصيلًا.'),
                const SizedBox(height: 12),
                SecondaryButton(
                    label:
                        _downloading ? 'جاري تجهيز PDF...' : 'تنزيل إيصال PDF',
                    icon: Icons.download_outlined,
                    onPressed: _downloading ? null : _download),
              ]));
        },
      ));
}

class SupportConversation extends StatefulWidget {
  final String ticketId;
  const SupportConversation({super.key, required this.ticketId});
  @override
  State<SupportConversation> createState() => _SupportConversationState();
}

class _SupportConversationState extends State<SupportConversation> {
  final input = TextEditingController();
  bool busy = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ticketStream;
  String? _ticketKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context);
    _bindTicket();
  }

  @override
  void didUpdateWidget(covariant SupportConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) _bindTicket();
  }

  void _bindTicket() {
    if (!FirebaseBootstrap.initialized || kEjarzLocalDemoMode) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final key = uid == null ? null : '$uid/${widget.ticketId}';
    if (key == _ticketKey) return;
    _ticketKey = key;
    // One owned document, including tickets outside the paginated list.
    // StreamBuilder cancels it on navigation, account change or disposal.
    _ticketStream = uid == null
        ? null
        : FirebaseFirestore.instance
            .collection('supportTickets')
            .where('uid', isEqualTo: uid)
            .where(FieldPath.documentId, isEqualTo: widget.ticketId)
            .limit(1)
            .snapshots();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (FirebaseBootstrap.initialized && !kEjarzLocalDemoMode) {
      if (_ticketStream == null) {
        return const ServiceUnavailable(title: 'التذكرة غير متاحة');
      }
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey(_ticketKey),
        stream: _ticketStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ServiceUnavailable(title: 'تعذر تحميل التذكرة');
          }
          if (!snapshot.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final rows = snapshot.data!.docs;
          if (rows.isEmpty) {
            return const ServiceUnavailable(title: 'التذكرة غير متاحة');
          }
          return _conversation(
              c, FirebaseRepository().supportTicketFromDoc(rows.first));
        },
      );
    }
    final matches = c.supportTickets.where((t) => t.id == widget.ticketId);
    if (matches.isEmpty) {
      return const ServiceUnavailable(title: 'التذكرة غير متاحة');
    }
    return _conversation(c, matches.first);
  }

  Widget _conversation(AppController c, SupportTicketRecord t) {
    return Scaffold(
        appBar: AppBar(title: Text(t.subject)),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          InfoBanner(text: '${t.statusLabel}\n${t.message}'),
          const SizedBox(height: 12),
          for (final r in t.replies)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(r.createdByName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(r.message)
                    ]))),
          if (AppRuntime.service('support')) ...[
            AppTextField(
                hint: '', label: 'رسالتك', controller: input, maxLines: 4),
            const SizedBox(height: 12),
            PrimaryButton(
                label: 'إرسال الرد',
                loading: busy,
                onPressed: () async {
                  if (input.text.trim().isEmpty) return;
                  setState(() => busy = true);
                  try {
                    await c.replySupport(t.id, input.text.trim());
                    input.clear();
                  } catch (_) {
                    if (mounted) {
                      showAppSnackBar(context, 'تعذر إرسال الرد.');
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                }),
          ],
        ]));
  }
}
