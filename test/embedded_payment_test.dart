import 'dart:async';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/payment_gateway.dart';
import 'package:aqdak/core/payment_navigation.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/service_payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final testContract = ContractRecord(
    id: 'test',
    requestNumber: 'TEST-ONLY-001',
    type: ContractType.residential,
    role: UserRole.lessor,
    title: 'اختبار الدفع',
    property: 'عقار تجريبي',
    lessorName: 'مؤجر تجريبي',
    tenantName: 'مستأجر تجريبي',
    date: '2026/10/05',
    status: ContractStatus.awaitingPayment,
    totalFees: 1,
    timeline: []);

class FakeGateway implements ContractPaymentGateway {
  Map<String, dynamic> restored = {'paymentId': null};
  Map<String, dynamic> created = {
    'paymentId': 'attempt',
    'checkoutUrl':
        'https://digitalpayments.neoleap.com.sa/pg/paymentpage.htm?PaymentID=123'
  };
  String status = 'pending';
  int creates = 0, checks = 0;
  bool checkError = false, refreshError = false;
  Completer<Map<String, dynamic>>? restoreWait, createWait;
  @override
  Future<Map<String, dynamic>> restore(String id) async =>
      restoreWait != null ? await restoreWait!.future : restored;
  @override
  Future<Map<String, dynamic>> create(String id) async {
    creates++;
    return createWait != null ? await createWait!.future : created;
  }

  @override
  Future<String> check(String id) async {
    checks++;
    if (checkError) throw StateError('offline');
    return status;
  }

  @override
  Future<ContractRecord?> contract(String id) async {
    if (refreshError) throw StateError('offline');
    return testContract.copyWith(
        paymentStatus: 'paid', status: ContractStatus.processing);
  }

  @override
  Future<void> transfer(String id, String reference) async {}
}

class FakeBankPage extends StatefulWidget {
  final PaymentViewConfiguration configuration;
  final bool loads;
  const FakeBankPage(this.configuration, {super.key, this.loads = true});
  @override
  State<FakeBankPage> createState() => _FakeBankPageState();
}

class _FakeBankPageState extends State<FakeBankPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.loads) widget.configuration.onProgress(100);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('صفحة بنك تجريبية'));
}

Future<void> pumpPayment(WidgetTester tester, FakeGateway gateway,
    void Function(PaymentViewConfiguration) capture,
    {Size size = const Size(390, 844), bool bankLoads = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar')],
      home: ServicePaymentScreen(
          contract: testContract,
          gateway: gateway,
          hostedViewBuilder: (configuration) {
            capture(configuration);
            return FakeBankPage(configuration, loads: bankLoads);
          })));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> openBank(WidgetTester tester) async {
  final button = find.byWidgetPredicate((widget) =>
      widget is Text &&
      (widget.data == 'الدفع الآن' || widget.data == 'استكمال الدفع'));
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(button, 150,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> cleanup(WidgetTester tester) async =>
    tester.pumpWidget(const SizedBox());

void main() {
  testWidgets(
      'late bank load clears timeout without replacing the page or attempt',
      (tester) async {
    final gateway = FakeGateway();
    PaymentViewConfiguration? config;
    await pumpPayment(tester, gateway, (value) => config = value,
        bankLoads: false);
    await tester.tap(find.text('الدفع الآن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final page = tester.state(find.byType(FakeBankPage));
    await tester.pump(const Duration(seconds: 46));
    await tester.pumpAndSettle();
    expect(find.textContaining('استغرق تحميل صفحة البنك'), findsOneWidget);
    expect(identical(tester.state(find.byType(FakeBankPage)), page), isTrue);
    config!.onProgress(100);
    await tester.pumpAndSettle();
    expect(find.textContaining('استغرق تحميل صفحة البنك'), findsNothing);
    expect(identical(tester.state(find.byType(FakeBankPage)), page), isTrue);
    expect(gateway.creates, 1);
    expect(find.text('تم الدفع بنجاح'), findsNothing);
    await cleanup(tester);
  });
  testWidgets('back from confirmed payment returns the updated request',
      (tester) async {
    final gateway = FakeGateway()
      ..restored = {'paymentId': 'attempt', 'status': 'paid'}
      ..status = 'paid';
    ContractRecord? returned;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('ar')],
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    child: const Text('فتح الدفع'),
                    onPressed: () async {
                      returned = await Navigator.of(context)
                          .push<ContractRecord>(MaterialPageRoute(
                              builder: (_) => ServicePaymentScreen(
                                  contract: testContract, gateway: gateway)));
                    })))));
    await tester.tap(find.text('فتح الدفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('العودة إلى الطلب'));
    await tester.pumpAndSettle();
    expect(returned?.paymentStatus, 'paid');
    expect(returned?.status, ContractStatus.processing);
    expect(find.text('فتح الدفع'), findsOneWidget);
  });
  test('checkout accepts only bank HTTPS domains; return cannot be spoofed',
      () {
    const samples = [
      'http://digitalpayments.neoleap.com.sa/pg',
      'https://neoleap.com.sa.evil.test/pg',
      'https://user:pass@neoleap.com.sa/pg',
      'https://neoleap.com.sa:8443/pg',
      'javascript:alert(1)'
    ];
    for (final value in samples) {
      expect(PaymentNavigationPolicy.validCheckout(value), false);
    }
    expect(
        PaymentNavigationPolicy.validCheckout(
            'https://digitalpayments.neoleap.com.sa/pg'),
        true);
    final policy = PaymentNavigationPolicy(
        Uri.parse('https://us-central1-test.cloudfunctions.net/neoleapReturn'));
    expect(
        policy.isReturn(
            'https://us-central1-test.cloudfunctions.net/neoleapReturn?status=paid'),
        true);
    expect(policy.isReturn('https://evil.test/neoleapReturn'), false);
    expect(policy.isReturn('about:blank'), false);
    expect(policy.isReturn('javascript:alert(1)'), false);
    expect(
        policy.isReturn(
            'https://us-central1-test.cloudfunctions.net/neoleapReturnFake'),
        false);
    expect(
        policy.allowsNavigation('https://3dverify2.bankalbilad.com/challenge'),
        true);
    expect(policy.allowsNavigation('intent://card'), false);
  });
  testWidgets('restore disables checkout until finished, preventing races',
      (tester) async {
    final gateway = FakeGateway()..restoreWait = Completer();
    await pumpPayment(tester, gateway, (_) {});
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(gateway.creates, 0);
    gateway.restoreWait!.complete({'paymentId': null});
    await tester.pumpAndSettle();
    expect(find.text('الدفع الآن'), findsOneWidget);
  });
  testWidgets(
      'bank appears within screen, callback pending never claims success',
      (tester) async {
    final gateway = FakeGateway();
    PaymentViewConfiguration? config;
    await pumpPayment(tester, gateway, (value) => config = value);
    await openBank(tester);
    expect(find.text('صفحة بنك تجريبية'), findsOneWidget);
    config!.onReturn();
    await tester.pumpAndSettle();
    expect(find.text('تم الدفع بنجاح'), findsNothing);
    expect(find.textContaining('ننتظر تأكيد البنك'), findsOneWidget);
    expect(gateway.checks, 1);
    await cleanup(tester);
  });
  testWidgets('server confirmation alone displays success and closes bank',
      (tester) async {
    final gateway = FakeGateway();
    PaymentViewConfiguration? config;
    await pumpPayment(tester, gateway, (value) => config = value);
    await openBank(tester);
    gateway.status = 'paid';
    config!.onReturn();
    await tester.pumpAndSettle();
    expect(find.text('تم الدفع بنجاح'), findsOneWidget);
    expect(find.text('صفحة بنك تجريبية'), findsNothing);
    expect(find.text('عرض تفاصيل الطلب'), findsOneWidget);
    expect(gateway.creates, 1);
    await cleanup(tester);
  });
  testWidgets('failed bank attempt allows retry with new server attempt',
      (tester) async {
    final gateway = FakeGateway();
    PaymentViewConfiguration? config;
    await pumpPayment(tester, gateway, (value) => config = value);
    await openBank(tester);
    gateway.status = 'failed';
    config!.onReturn();
    await tester.pumpAndSettle();
    expect(find.textContaining('لم تكتمل عملية الدفع'), findsOneWidget);
    gateway.status = 'pending';
    await openBank(tester);
    expect(gateway.creates, 2);
    await cleanup(tester);
  });
  testWidgets('double press cannot create concurrent checkout attempts',
      (tester) async {
    final gateway = FakeGateway()..createWait = Completer();
    await pumpPayment(tester, gateway, (_) {});
    await tester.tap(find.text('الدفع الآن'));
    await tester.pump();
    expect(gateway.creates, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    gateway.createWait!.complete(gateway.created);
    await tester.pumpAndSettle();
    expect(gateway.creates, 1);
    await cleanup(tester);
  });
  testWidgets('restored paid checkout never offers repayment', (tester) async {
    final gateway = FakeGateway()
      ..restored = {'paymentId': 'attempt', 'status': 'paid'}
      ..status = 'paid';
    await pumpPayment(tester, gateway, (_) {});
    await tester.pumpAndSettle();
    expect(find.text('تم الدفع بنجاح'), findsOneWidget);
    expect(find.text('الدفع الآن'), findsNothing);
    expect(gateway.creates, 0);
  });
  testWidgets(
      'bank/network error stays pending; confirmed payment survives refresh failure',
      (tester) async {
    final gateway = FakeGateway();
    PaymentViewConfiguration? config;
    await pumpPayment(tester, gateway, (value) => config = value);
    await openBank(tester);
    gateway.checkError = true;
    config!.onReturn();
    await tester.pumpAndSettle();
    expect(find.text('تم الدفع بنجاح'), findsNothing);
    expect(find.textContaining('تعذر التحقق الآن'), findsOneWidget);
    gateway.checkError = false;
    gateway.refreshError = true;
    gateway.status = 'paid';
    config!.onReturn();
    await tester.pumpAndSettle();
    expect(find.text('تم الدفع بنجاح'), findsOneWidget);
    await cleanup(tester);
  });
  testWidgets('unsafe checkout URL is not rendered', (tester) async {
    final gateway = FakeGateway()
      ..created = {'paymentId': 'attempt', 'checkoutUrl': 'https://evil.test/'};
    await pumpPayment(tester, gateway, (_) {});
    await openBank(tester);
    expect(find.text('صفحة بنك تجريبية'), findsNothing);
    expect(find.textContaining('تعذر تجهيز الدفع'), findsOneWidget);
  });
  testWidgets('small phones and enlarged Arabic text have no layout overflow',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = FakeGateway();
    await pumpPayment(tester, gateway, (_) {}, size: const Size(320, 568));
    await openBank(tester);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });
  testWidgets(
      'closing bank preserves the attempt and verifies before continuing',
      (tester) async {
    final gateway = FakeGateway();
    await pumpPayment(tester, gateway, (_) {});
    await openBank(tester);
    await tester.tap(find.byTooltip('العودة إلى ملخص الدفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العودة إلى الملخص'));
    await tester.pumpAndSettle();
    expect(find.text('استكمال الدفع'), findsOneWidget);
    expect(gateway.checks, 1);
    expect(gateway.creates, 1);
    await openBank(tester);
    expect(gateway.checks, 2);
    expect(gateway.creates, 2);
    await cleanup(tester);
  });
}
