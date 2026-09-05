import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class DemoPaymentScreen extends StatefulWidget {
  final ContractRecord contract;

  const DemoPaymentScreen({super.key, required this.contract});

  @override
  State<DemoPaymentScreen> createState() => _DemoPaymentScreenState();
}

class _DemoPaymentScreenState extends State<DemoPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _holderController = TextEditingController();
  final _cardController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  DemoPaymentMethod _method = DemoPaymentMethod.mada;
  bool _processing = false;
  DemoPaymentResult? _result;
  String _failureText = '';
  String _resultBrand = '';
  String _resultLast4 = '';

  @override
  void dispose() {
    _holderController.dispose();
    _cardController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: DetailAppBar(
        title: 'دفع رسوم العقد',
        backEnabled: !_processing,
        onBack: _processing ? null : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 700,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          child: result?.success == true
              ? _PaymentReceipt(
                  contract: widget.contract,
                  result: result!,
                  method: _method,
                  cardBrand: _resultBrand,
                  cardLast4: _resultLast4,
                )
              : _PaymentForm(
                  formKey: _formKey,
                  contract: widget.contract,
                  method: _method,
                  processing: _processing,
                  failureText: _failureText,
                  holderController: _holderController,
                  cardController: _cardController,
                  expiryController: _expiryController,
                  cvvController: _cvvController,
                  onMethodChanged: (method) {
                    if (_processing) return;
                    setState(() {
                      _method = method;
                      _failureText = '';
                    });
                  },
                  onPay: _submit,
                ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_processing) return;
    FocusScope.of(context).unfocus();
    if (_method.requiresCardForm &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final digits = _cardDigits;
    final cardLast4 =
        _method.requiresCardForm ? digits.substring(digits.length - 4) : '';
    final brand = _method.requiresCardForm ? _cardBrand(digits) : _method.label;
    final success = !_method.requiresCardForm || !digits.endsWith('0000');
    final controller = AppScope.of(context, listen: false);
    if (widget.contract.pendingSync) {
      setState(() {
        _failureText = 'لا يمكن الدفع قبل مزامنة الطلب مع الخادم.';
      });
      return;
    }

    setState(() {
      _processing = true;
      _failureText = '';
      _result = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1700));

    try {
      final result = await controller.submitDemoPayment(
        contract: widget.contract,
        method: _method,
        cardBrand: brand,
        cardLast4: cardLast4,
        success: success,
      );
      if (!mounted) return;
      setState(() {
        _processing = false;
        _resultBrand = brand;
        _resultLast4 = cardLast4;
        if (result.success) {
          _result = result;
        } else {
          _failureText = result.failureReason.isEmpty
              ? 'تعذر إتمام عملية الدفع، يرجى التحقق من البيانات أو تجربة طريقة أخرى.'
              : result.failureReason;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _failureText =
            'تعذر إتمام عملية الدفع، يرجى التحقق من البيانات أو تجربة طريقة أخرى.';
      });
    }
  }

  String get _cardDigits => _cardController.text.replaceAll(RegExp(r'\D'), '');

  String _cardBrand(String digits) {
    if (_method == DemoPaymentMethod.mada) return 'Mada';
    if (digits.startsWith('4')) return 'Visa';
    if (digits.startsWith('5')) return 'Mastercard';
    return 'Card';
  }
}

class _PaymentForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final ContractRecord contract;
  final DemoPaymentMethod method;
  final bool processing;
  final String failureText;
  final TextEditingController holderController;
  final TextEditingController cardController;
  final TextEditingController expiryController;
  final TextEditingController cvvController;
  final ValueChanged<DemoPaymentMethod> onMethodChanged;
  final VoidCallback onPay;

  const _PaymentForm({
    required this.formKey,
    required this.contract,
    required this.method,
    required this.processing,
    required this.failureText,
    required this.holderController,
    required this.cardController,
    required this.expiryController,
    required this.cvvController,
    required this.onMethodChanged,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryCard(contract: contract),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('طريقة الدفع',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final item in DemoPaymentMethod.values)
                    _MethodChip(
                      method: item,
                      selected: item == method,
                      onTap: () => onMethodChanged(item),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (method.requiresCardForm)
          _CardForm(
            formKey: formKey,
            holderController: holderController,
            cardController: cardController,
            expiryController: expiryController,
            cvvController: cvvController,
          )
        else
          _WalletDemoCard(method: method),
        if (failureText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          InfoBanner(
            text: failureText,
            icon: Icons.error_outline_rounded,
            color: AppColors.red,
          ),
        ],
        const SizedBox(height: 14),
        PrimaryButton(
          label: processing
              ? 'جاري معالجة الدفع...'
              : 'دفع ${contract.totalFees.toStringAsFixed(2)} ر.س',
          icon: processing ? Icons.hourglass_top_rounded : Icons.lock_rounded,
          onPressed: processing ? null : onPay,
        ),
        const SizedBox(height: 8),
        Text(
          'عملية تجريبية فقط، ولا يتم خصم أي مبلغ فعلي.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.ejarzTheme.muted,
            fontSize: context.sp(11.5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ContractRecord contract;

  const _SummaryCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  contract.requestNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(19),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  contract.type.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            contract.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: context.sp(12.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          for (final label in ['رسوم السنة الأولى', 'رسوم المدة الإضافية'])
            if (contract.contractDetails.containsKey(label))
              _FeeLine(label: label, value: contract.contractDetails[label]!),
          const Text('الأسعار شاملة رسوم منصة إيجار',
              style: TextStyle(color: Colors.white)),
          Divider(color: Colors.white.withValues(alpha: 0.18)),
          _FeeLine(
              label: 'الإجمالي',
              value: '${contract.totalFees.toStringAsFixed(2)} ر.س',
              strong: true),
        ],
      ),
    );
  }
}

class _FeeLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _FeeLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: strong ? 1 : 0.82),
                fontSize: context.sp(strong ? 14.5 : 12.3),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: context.sp(strong ? 18 : 13),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final DemoPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 154,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : context.ejarzTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : context.ejarzTheme.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(method.icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                method.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : context.ejarzTheme.text,
                  fontSize: context.sp(11.5),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController holderController;
  final TextEditingController cardController;
  final TextEditingController expiryController;
  final TextEditingController cvvController;

  const _CardForm({
    required this.formKey,
    required this.holderController,
    required this.cardController,
    required this.expiryController,
    required this.cvvController,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.credit_card_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'بيانات البطاقة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: holderController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم حامل البطاقة',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                if ((value ?? '').trim().length < 3) {
                  return 'اكتب اسم حامل البطاقة';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: cardController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: const InputDecoration(
                labelText: 'رقم البطاقة',
                hintText: '4111111111111111',
                prefixIcon: Icon(Icons.credit_card_rounded),
                counterText: '',
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length != 16) {
                  return 'رقم البطاقة يجب أن يكون 16 رقمًا';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                final fieldWidth = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: expiryController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          _ExpiryFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'MM/YY',
                          prefixIcon: Icon(Icons.date_range_rounded),
                          counterText: '',
                        ),
                        validator: _validateExpiry,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: cvvController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'CVV',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          counterText: '',
                        ),
                        validator: (value) {
                          if ((value ?? '').length != 3) {
                            return 'CVV من 3 أرقام';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletDemoCard extends StatelessWidget {
  final DemoPaymentMethod method;

  const _WalletDemoCard({required this.method});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(13),
      color: AppColors.secondaryLight.withValues(alpha: 0.55),
      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(method.icon, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(method.label,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  'سيتم تسجيل عملية تجريبية بدون الاتصال بأي مزود دفع، ثم تتم محاكاة المعالجة تلقائيًا لأغراض العرض.',
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    fontSize: context.sp(11.4),
                    fontWeight: FontWeight.w700,
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

class _PaymentReceipt extends StatelessWidget {
  final ContractRecord contract;
  final DemoPaymentResult result;
  final DemoPaymentMethod method;
  final String cardBrand;
  final String cardLast4;

  const _PaymentReceipt({
    required this.contract,
    required this.result,
    required this.method,
    required this.cardBrand,
    required this.cardLast4,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 38,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'تم تسجيل الدفع',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              Text(
                'تم استلام الدفع التجريبي، وتمت محاكاة معالجة الطلب تلقائيًا لأغراض العرض. أصبح نموذج العقد جاهزًا للمعاينة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  fontSize: context.sp(12.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'عملية تجريبية',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: <Widget>[
              _ReceiptLine(label: 'رقم الفاتورة', value: result.invoiceNumber),
              _ReceiptLine(
                label: 'رقم العملية',
                value: result.providerReference,
              ),
              _ReceiptLine(label: 'طريقة الدفع', value: method.label),
              if (cardLast4.isNotEmpty)
                _ReceiptLine(
                  label: 'البطاقة',
                  value: '$cardBrand •••• $cardLast4',
                ),
              _ReceiptLine(
                  label: 'الإجمالي',
                  value: '${contract.totalFees.toStringAsFixed(2)} ر.س'),
              _ReceiptLine(label: 'رقم الطلب', value: contract.requestNumber),
              const _ReceiptLine(
                  label: 'الحالة', value: 'مدفوع - اكتمل تلقائيًا Demo'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'العودة لتفاصيل الطلب',
          icon: Icons.description_outlined,
          onPressed: () {
            final controller = AppScope.of(context, listen: false);
            final updated = controller.contracts.firstWhere(
              (item) => item.id == contract.id,
              orElse: () => contract.copyWith(
                status: ContractStatus.authenticated,
                finalPdfUrl: kDemoContractPdfUrl,
                finalPdfFileName: kDemoContractPdfFileName,
                paymentStatus: 'paid',
                paymentId: result.paymentId,
                invoiceId: result.invoiceId,
                invoiceNumber: result.invoiceNumber,
                paymentMethod: method.code,
                paymentProvider: 'demo',
                paymentReference: result.providerReference,
                cardBrand: cardBrand,
                cardLast4: cardLast4,
              ),
            );
            Navigator.of(context).pop(updated);
          },
        ),
      ],
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

String? _validateExpiry(String? value) {
  final raw = (value ?? '').trim();
  if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(raw)) return 'صيغة التاريخ MM/YY';
  final month = int.tryParse(raw.substring(0, 2)) ?? 0;
  final year = int.tryParse(raw.substring(3, 5)) ?? -1;
  if (month < 1 || month > 12) return 'الشهر غير صحيح';
  final now = DateTime.now();
  final fullYear = 2000 + year;
  final expiresAt = DateTime(fullYear, month + 1, 0);
  if (expiresAt.isBefore(DateTime(now.year, now.month, 1))) {
    return 'البطاقة منتهية';
  }
  return null;
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
