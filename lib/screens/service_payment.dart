import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../core/app_telemetry.dart';
import '../core/models.dart';
import '../core/payment_gateway.dart';
import '../core/payment_navigation.dart';
import '../core/payment_return_context.dart';
import '../core/runtime_config.dart';
import '../core/theme.dart';
import '../firebase_options.dart';
import '../widgets/common.dart';
import '../widgets/account_confirmation_dialog.dart';
import '../widgets/hosted_payment.dart';

class PaymentViewConfiguration {
  final String checkoutUrl, paymentId;
  final Uri returnUri;
  final VoidCallback onReturn;
  final ValueChanged<int> onProgress;
  final ValueChanged<String> onError;
  const PaymentViewConfiguration(
      {required this.checkoutUrl,
      required this.paymentId,
      required this.returnUri,
      required this.onReturn,
      required this.onProgress,
      required this.onError});
}

class ServicePaymentScreen extends StatefulWidget {
  final ContractRecord contract;
  final ContractPaymentGateway? gateway;
  final Widget Function(PaymentViewConfiguration)? hostedViewBuilder;
  const ServicePaymentScreen(
      {super.key,
      required this.contract,
      this.gateway,
      this.hostedViewBuilder});
  @override
  State<ServicePaymentScreen> createState() => _ServicePaymentState();
}

class _ServicePaymentState extends State<ServicePaymentScreen>
    with WidgetsBindingObserver {
  late final gateway = widget.gateway ?? FirebaseContractPaymentGateway();
  final reference = TextEditingController();
  bool restoring = true, busy = false, checking = false, showBank = false;
  bool paid = false, submitted = false, returned = false;
  bool allowPaidPop = false;
  bool closeDialogOpen = false;
  int progress = 0, viewGeneration = 0;
  String? paymentId, checkoutUrl;
  String message = '', bankError = '';
  ContractRecord? updatedContract;
  Timer? poll;
  Timer? loadingTimeout;
  DateTime? pollingStarted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTelemetry.record('checkout_start', 'contract_details');
    _restore();
  }

  Future<void> _restore() async {
    try {
      final data = await gateway.restore(widget.contract.id);
      if (!mounted) return;
      if (data['paymentId'] is String && data['status'] != 'failed') {
        paymentId = data['paymentId'] as String;
        checkoutUrl = data['checkoutUrl'] as String?;
        await _verify(silent: true);
      } else if (widget.contract.paymentStatus == 'paid') {
        // A server-loaded contract already paid cannot start a new checkout.
        paid = true;
        updatedContract = widget.contract;
      }
    } catch (_) {
      if (mounted) {
        message =
            'تعذر استعادة حالة الدفع. أعد التحقق من اتصالك ثم حاول مجددًا.';
      }
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && paymentId != null && !paid) {
      unawaited(_verify(silent: true));
    }
  }

  void _startPolling() {
    poll?.cancel();
    pollingStarted = DateTime.now();
    poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted ||
          paid ||
          (!showBank && !returned) ||
          DateTime.now().difference(pollingStarted!) >
              const Duration(minutes: 10)) {
        poll?.cancel();
        return;
      }
      unawaited(_verify(silent: true));
    });
  }

  Future<String?> _verify({bool silent = false}) async {
    final currentId = paymentId;
    if (currentId == null || checking || paid) return null;
    setState(() => checking = true);
    try {
      final status = await gateway.check(currentId);
      if (!mounted) return status;
      if (status == 'paid') {
        poll?.cancel();
        loadingTimeout?.cancel();
        setState(() {
          paid = true;
          showBank = false;
          message = '';
          bankError = '';
        });
        // Refresh failure must not turn a confirmed payment into a failed one.
        try {
          final result = await gateway.contract(widget.contract.id);
          if (mounted) setState(() => updatedContract = result);
        } catch (_) {/* The return button can retry loading the contract. */}
      } else if (status == 'failed') {
        poll?.cancel();
        loadingTimeout?.cancel();
        setState(() {
          showBank = false;
          paymentId = null;
          checkoutUrl = null;
          returned = false;
          bankError = '';
          message =
              'لم تكتمل عملية الدفع. يمكنك إعادة المحاولة دون تغيير طلبك.';
        });
      } else if (!silent || returned) {
        setState(() => message =
            'ننتظر تأكيد البنك. إذا خُصم المبلغ، تحقق من الحالة قبل إعادة الدفع.');
      }
      return status;
    } catch (error) {
      if (mounted && (!silent || returned)) {
        setState(() => message = _error(
            error, 'تعذر التحقق الآن. العملية محفوظة ويمكنك التحقق مجددًا.'));
      }
      return null;
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  String _error(Object error, String fallback) =>
      error is FirebaseFunctionsException
          ? error.message ?? fallback
          : fallback;

  Future<void> _openBank() async {
    if (busy || restoring || checking || paid) return;
    setState(() {
      busy = true;
      message = '';
    });
    poll?.cancel();
    loadingTimeout?.cancel();
    try {
      if (paymentId != null) {
        final status = await _verify();
        if (!mounted || paid || status == null) return;
      }
      // The server reuses a pending attempt; retries never create a second charge.
      final data = await gateway.create(widget.contract.id);
      if (!mounted) return;
      if (data['paymentId'] is! String ||
          data['checkoutUrl'] is! String ||
          !PaymentNavigationPolicy.validCheckout(
              data['checkoutUrl'] as String)) {
        throw StateError('Invalid bank checkout');
      }
      setState(() {
        paymentId = data['paymentId'] as String;
        checkoutUrl = data['checkoutUrl'] as String;
        showBank = true;
        returned = false;
        progress = 0;
        bankError = '';
        message = '';
        viewGeneration++;
      });
      _startPolling();
      loadingTimeout = Timer(const Duration(seconds: 45), () {
        if (mounted && showBank && progress < 100) {
          setState(() {
            progress = 100;
            bankError =
                'استغرق تحميل صفحة البنك وقتًا أطول من المعتاد. تحقق من اتصالك أو أعد فتح الدفع.';
          });
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => message = _error(
            error, 'تعذر تجهيز الدفع. تحقق من اتصال الإنترنت ثم حاول مجددًا.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _bankReturned() {
    if (!mounted || paid) return;
    setState(() {
      returned = true;
      showBank = false;
      message = 'جاري تأكيد نتيجة العملية من البنك…';
    });
    loadingTimeout?.cancel();
    unawaited(_verify());
  }

  Future<void> _closeBank() async {
    if (closeDialogOpen) return;
    closeDialogOpen = true;
    bool close;
    try {
      close = await showAccountConfirmation(
        context,
        title: 'العودة إلى ملخص الدفع',
        message:
            'ستبقى عملية الدفع محفوظة. العودة إلى الملخص لا تلغي الدفع لدى البنك، ويمكنك التحقق من حالته من هناك.',
        confirmLabel: 'العودة إلى الملخص',
        cancelLabel: 'مواصلة الدفع',
        icon: Icons.receipt_long_rounded,
      );
    } finally {
      closeDialogOpen = false;
    }
    if (close != true || !mounted) return;
    poll?.cancel();
    loadingTimeout?.cancel();
    setState(() => showBank = false);
    await _verify();
  }

  Future<void> _returnToContract() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final record =
          updatedContract ?? await gateway.contract(widget.contract.id);
      if (!mounted) return;
      if (record == null) throw StateError('Contract not loaded');
      setState(() => allowPaidPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.pop(context, record);
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'تم تأكيد السداد. تعذر تحديث الطلب الآن؛ أعد فتح تفاصيله أو حاول مجددًا.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    loadingTimeout?.cancel();
    reference.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !showBank && (!paid || allowPaidPop),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (showBank) {
              unawaited(_closeBank());
            } else if (paid) {
              unawaited(_returnToContract());
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(showBank ? 'الدفع الآمن' : 'دفع رسوم العقد'),
              leading: IconButton(
                  tooltip:
                      showBank ? 'العودة إلى ملخص الدفع' : 'العودة إلى الطلب',
                  onPressed: showBank
                      ? _closeBank
                      : paid
                          ? _returnToContract
                          : () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back))),
          body: showBank ? _bankBody(context) : _summary(context),
        ),
      );

  Widget _summary(BuildContext context) => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(padding: const EdgeInsets.all(22), children: [
          _amountCard(context),
          const SizedBox(height: 22),
          if (paid) ...[
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 66),
            const SizedBox(height: 12),
            Text('تم الدفع بنجاح',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('تم تأكيد السداد من البنك. يمكنك متابعة حالة طلبك.',
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            PrimaryButton(
                label: 'عرض تفاصيل الطلب',
                loading: busy,
                onPressed: _returnToContract),
          ] else ...[
            Text('خطوة واحدة لإكمال طلبك',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 9),
            const Text(
                'أدخل بيانات البطاقة في صفحة البنك الآمنة، ثم أكمل التحقق البنكي عند طلبه.'),
            const SizedBox(height: 18),
            _secureNote(),
            const SizedBox(height: 22),
            PrimaryButton(
                label: restoring
                    ? 'جاري استعادة حالة الدفع'
                    : paymentId == null
                        ? 'الدفع الآن'
                        : 'استكمال الدفع',
                loading: busy || restoring || checking,
                onPressed: checking ? null : _openBank),
            if (paymentId != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: checking || busy ? null : () => _verify(),
                  icon: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: const Text('التحقق من حالة الدفع')),
            ],
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 14),
            InfoBanner(text: message)
          ],
          if (!paid &&
              paymentId == null &&
              AppRuntime.payments['manualTransferEnabled'] == true)
            _manualTransfer(),
          const SizedBox(height: 18),
          const Text('رقم الطلب',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted)),
          Text(widget.contract.requestNumber,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ));

  Widget _amountCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.receipt_long_rounded, color: Color(0xFFFFDEA0)),
            SizedBox(width: 9),
            Expanded(
                child: Text('رسوم خدمة العقد',
                    style: TextStyle(color: Colors.white)))
          ]),
          const SizedBox(height: 14),
          Text('${widget.contract.totalFees.toStringAsFixed(2)} ر.س',
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 7),
          Text(
              widget.contract.type == ContractType.residential
                  ? 'عقد سكني'
                  : 'عقد تجاري',
              style: const TextStyle(color: Colors.white70)),
        ]),
      );

  Widget _secureNote() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16)),
        child:
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 21),
          SizedBox(width: 10),
          Expanded(
              child: Text(
                  'دفع آمن عبر neoleap\nبيانات البطاقة تُدخل لدى البنك ولا تُحفظ في عقدك.',
                  style: TextStyle(color: AppColors.primaryDark))),
        ]),
      );

  Widget _bankBody(BuildContext context) {
    final configuration = PaymentViewConfiguration(
        checkoutUrl: checkoutUrl!,
        paymentId: paymentId!,
        returnUri: Uri.parse(
            'https://us-central1-${DefaultFirebaseOptions.currentPlatform.projectId}.cloudfunctions.net/neoleapReturn'),
        onReturn: _bankReturned,
        onProgress: (value) {
          if (value == 100) loadingTimeout?.cancel();
          if (mounted &&
              (value != progress || (value == 100 && bankError.isNotEmpty))) {
            setState(() {
              progress = value;
              if (value == 100) bankError = '';
            });
          }
        },
        onError: (value) {
          loadingTimeout?.cancel();
          if (mounted) {
            setState(() {
              bankError = value;
              progress = 100;
            });
          }
        });
    return SafeArea(
        child: Column(children: [
      Container(
          width: double.infinity,
          color: AppColors.primaryLight,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            const Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('صفحة البنك الآمنة',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            Text('${widget.contract.totalFees.toStringAsFixed(2)} ر.س',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
      if (progress < 100)
        LinearProgressIndicator(value: progress == 0 ? null : progress / 100),
      if (bankError.isNotEmpty || returned)
        Padding(
            padding: const EdgeInsets.all(12),
            child:
                InfoBanner(text: bankError.isNotEmpty ? bankError : message)),
      Expanded(
        key: const ValueKey('hosted-bank-content'),
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                    color: Colors.white,
                    child: KeyedSubtree(
                        key: ValueKey(viewGeneration),
                        child: widget.hostedViewBuilder?.call(configuration) ??
                            HostedPaymentView(
                                checkoutUrl: configuration.checkoutUrl,
                                paymentId: configuration.paymentId,
                                returnUri: configuration.returnUri,
                                onReturn: configuration.onReturn,
                                onProgress: configuration.onProgress,
                                onError: configuration.onError))))),
      ),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: TextButton.icon(
                      onPressed: checking ? null : () => _verify(),
                      icon: checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync, size: 18),
                      label: const Text('تحقق من الدفع'))),
              if (bankError.isNotEmpty)
                TextButton(
                    onPressed: checking || busy ? null : _openBank,
                    child: const Text('إعادة فتح الدفع')),
            ]),
            if (canContinuePaymentInSameTab)
              TextButton(
                  onPressed: () {
                    rememberPaymentContract(widget.contract.id);
                    continuePaymentInSameTab(checkoutUrl!);
                  },
                  child: const Text(
                      'إذا تعذر التحقق البنكي: استكمل في نفس التبويب',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.muted))),
          ])),
    ]));
  }

  Widget _manualTransfer() {
    final settings = AppRuntime.payments;
    return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: ExpansionTile(
          title: const Text('الدفع بالتحويل البنكي'),
          leading: const Icon(Icons.account_balance_outlined),
          childrenPadding: const EdgeInsets.all(14),
          children: [
            SelectableText(
                'البنك: ${settings['bankName']}\nالمستفيد: ${settings['bankAccountName']}\nIBAN: ${settings['bankIban']}'),
            const SizedBox(height: 14),
            if (submitted)
              const InfoBanner(
                  text:
                      'أُرسل مرجع التحويل للمراجعة. يُعتمد السداد بعد تأكيد المالية.')
            else ...[
              AppTextField(
                  hint: '', label: 'مرجع التحويل', controller: reference),
              const SizedBox(height: 12),
              PrimaryButton(
                  label: 'إرسال التحويل للمراجعة',
                  loading: busy,
                  onPressed: () async {
                    if (reference.text.trim().isEmpty) {
                      showAppSnackBar(context, 'أدخل مرجع التحويل.');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await gateway.transfer(
                          widget.contract.id, reference.text.trim());
                      if (mounted) setState(() => submitted = true);
                    } catch (error) {
                      if (mounted) {
                        setState(() => message =
                            _error(error, 'تعذر إرسال مرجع التحويل.'));
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
            ],
          ],
        ));
  }
}
