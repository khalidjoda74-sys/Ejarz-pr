import 'package:flutter/material.dart';
import '../widgets/load_more_records.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/app_telemetry.dart';
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
                        '${p['isDemo'] == true ? 'تجريبي · ' : ''}${p['contractId']}\n${_date(p['createdAt'])}')))),
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
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${invoice['invoiceNumber'] ?? invoice['id']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          '${_amount(invoice['amount'])} ر.س · ${_state(invoice['status'])}'),
                      Text('الطلب: ${invoice['contractId']}'),
                      Text(_date(invoice['createdAt'])),
                      if (invoice['isDemo'] == true)
                        const Text('مستند تجريبي لا يثبت تحصيلًا.'),
                      const SizedBox(height: 12),
                      SecondaryButton(
                          label: 'تنزيل إيصال HTML قابل للطباعة',
                          icon: Icons.download_outlined,
                          onPressed: () async {
                            try {
                              await downloadReceipt(invoice);
                            } catch (_) {
                              if (context.mounted) {
                                showAppSnackBar(context,
                                    'تعذر تنزيل المستند. حاول مرة أخرى.');
                              }
                            }
                          }),
                    ]))),
          const LoadMoreRecords('invoices'),
        ]));
  }
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

class ServicePaymentScreen extends StatefulWidget {
  final ContractRecord contract;
  const ServicePaymentScreen({super.key, required this.contract});
  @override
  State<ServicePaymentScreen> createState() => _ServicePaymentState();
}

class _ServicePaymentState extends State<ServicePaymentScreen> {
  final reference = TextEditingController();
  bool busy = false, submitted = false;
  String? neoleapPaymentId;
  String? neoleapCheckoutUrl;
  @override
  void initState() {
    super.initState();
    AppTelemetry.record('checkout_start', 'contract_details');
    _restorePaymentAttempt();
  }

  Future<void> _restorePaymentAttempt() async {
    try {
      final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getContractPaymentAttempt')
          .call({'contractId': widget.contract.id});
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted || data['paymentId'] is! String ||
          !['pending', 'initializing', 'initUncertain'].contains(data['status'])) {
        return;
      }
      setState(() {
        neoleapPaymentId = data['paymentId'] as String;
        neoleapCheckoutUrl = data['checkoutUrl'] as String?;
      });
    } catch (_) {
      // The create call will still show the server's actionable error.
    }
  }

  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final p = AppRuntime.payments;
    return Scaffold(
        appBar: AppBar(title: const Text('رسوم خدمة العقد')),
        body: ListView(padding: const EdgeInsets.all(22), children: [
          Text('${widget.contract.totalFees.toStringAsFixed(2)} ر.س',
              style: Theme.of(context).textTheme.headlineMedium),
          Text('الطلب: ${widget.contract.requestNumber}'),
          const SizedBox(height: 20),
          const InfoBanner(
              text: 'يُفتح الدفع الآمن في صفحة البنك. بعد العودة إلى التطبيق اضغط التحقق من حالة الدفع؛ لا يُعتمد السداد قبل تأكيده من البنك.'),
          const SizedBox(height: 14),
          PrimaryButton(
              label: neoleapPaymentId == null ? 'الدفع الإلكتروني' : 'تحقق من حالة الدفع',
              loading: busy,
              onPressed: () async {
                setState(() => busy = true);
                try {
                  if (neoleapPaymentId == null) {
                    final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
                        .httpsCallable('createPaymentAttempt')
                        .call({'contractId': widget.contract.id, 'method': 'neoleap'});
                    final data = Map<String, dynamic>.from(response.data as Map);
                    final paymentId = data['paymentId'] as String?;
                    final checkoutUrl = data['checkoutUrl'] as String?;
                    if (paymentId == null || checkoutUrl == null) {
                      throw StateError('تعذر إنشاء صفحة الدفع.');
                    }
                    if (mounted) {
                      setState(() {
                        neoleapPaymentId = paymentId;
                        neoleapCheckoutUrl = checkoutUrl;
                      });
                    }
                    if (!await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication)) {
                      throw StateError('تعذر فتح صفحة الدفع.');
                    }
                  } else {
                    final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
                        .httpsCallable('checkNeoleapPayment')
                        .call({'paymentId': neoleapPaymentId});
                    final data = Map<String, dynamic>.from(response.data as Map);
                    if (context.mounted) {
                      if (data['status'] == 'paid') {
                        final updated = await FirebaseRepository().fetchContract(widget.contract.id);
                        if (!context.mounted) return;
                        if (updated != null) {
                          Navigator.of(context).pop(updated);
                          return;
                        }
                        showAppSnackBar(context, 'تم تأكيد الدفع من البنك.');
                      } else if (data['status'] == 'failed') {
                        setState(() {
                          neoleapPaymentId = null;
                          neoleapCheckoutUrl = null;
                        });
                        showAppSnackBar(context, 'لم تكتمل العملية. يمكنك إعادة محاولة الدفع.');
                      } else {
                        showAppSnackBar(context, 'لم يؤكد البنك اكتمال الدفع بعد. يمكنك التحقق لاحقًا.');
                      }
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    showAppSnackBar(context, e is FirebaseFunctionsException
                        ? e.message ?? 'تعذر تنفيذ عملية الدفع'
                        : 'تعذر فتح صفحة الدفع أو التحقق منها.');
                  }
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              }),
          if (neoleapCheckoutUrl != null) ...[
            const SizedBox(height: 8),
            TextButton(
                onPressed: () async {
                  final url = neoleapCheckoutUrl;
                  if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                child: const Text('إعادة فتح صفحة البنك')),
          ],
          if (p['manualTransferEnabled'] == true) ...[
            const SizedBox(height: 18),
            const SectionTitle(title: 'تحويل بنكي'),
            SelectableText(
                'البنك: ${p['bankName']}\nالمستفيد: ${p['bankAccountName']}\nIBAN: ${p['bankIban']}'),
            const SizedBox(height: 14),
            if (submitted)
              const InfoBanner(
                  text:
                      'سُجل طلب مراجعة التحويل. يظل الدفع معلقًا حتى تعتمد المالية المبلغ والمرجع.')
            else ...[
              AppTextField(
                  hint: '', label: 'مرجع التحويل', controller: reference),
              const SizedBox(height: 14),
              PrimaryButton(
                  label: 'أرسلت التحويل — طلب مراجعة',
                  loading: busy,
                  onPressed: () async {
                    if (reference.text.trim().isEmpty) {
                      showAppSnackBar(context, 'أدخل مرجع التحويل.');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await FirebaseFunctions.instanceFor(region: 'us-central1')
                          .httpsCallable('createPaymentAttempt')
                          .call({
                        'contractId': widget.contract.id,
                        'method': 'bankTransfer',
                        'reference': reference.text.trim()
                      });
                      if (mounted) setState(() => submitted = true);
                    } catch (e) {
                      if (context.mounted) {
                        showAppSnackBar(
                            context,
                            e is FirebaseFunctionsException
                                ? e.message ?? 'تعذر تسجيل التحويل'
                                : 'تعذر تسجيل التحويل');
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  })
            ]
          ] else
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child: InfoBanner(
                    text:
                        'وسائل التحصيل غير مهيأة حاليًا. تواصل مع الدعم قبل إرسال أي مبلغ.')),
        ]));
  }
}
