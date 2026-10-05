import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/renewal_request.dart';
import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/screens/external_renewal.dart';
import 'package:aqdak/screens/home.dart';
import 'package:aqdak/screens/contracts.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'building_units_flow_test.dart' show mount, field, fill;

RenewalRequest readyRequest() => RenewalRequest(
    idNumber: '1234567890',
    birthDate: '1990/01/01',
    mobile: '0501234567',
    fileName: 'عقد.pdf',
    fileUrl: 'https://example.test/ejar.pdf');
ContractRecord record(RenewalRequest r) => ContractRecord(
    id: r.submissionId,
    requestNumber: 'REN-QA-1234',
    type: ContractType.residential,
    role: UserRole.tenant,
    requestKind: 'externalRenewal',
    renewalRequest: r.toMap().map((k, v) => MapEntry(k, v.toString())),
    title: 'تجديد عقد منصة إيجار',
    property: 'عقد سابق مرفق للمراجعة',
    lessorName: '',
    tenantName: '',
    date: '2026/10/05',
    status: ContractStatus.processing,
    totalFees: 0,
    timeline: [],
    paymentStatus: 'notRequested',
    partyDetails: {
      'هوية المستأجر': r.idNumber,
      'تاريخ ميلاد المستأجر': r.birthDate,
      'جوال المستأجر': r.mobile
    },
    attachmentFiles: {'عقد منصة إيجار السابق': r.fileUrl});

class RenewalController extends AppController {
  int submissions = 0;
  bool fail = false;
  Completer<void>? pending;
  final List<String> submittedIds = [];
  @override
  Future<ContractRecord> submitExternalRenewal(RenewalRequest request) async {
    submissions++;
    submittedIds.add(request.submissionId);
    request.validate();
    if (pending != null) await pending!.future;
    if (fail) throw StateError('network unavailable');
    final saved = record(request);
    contracts.add(saved);
    notifyListeners();
    return saved;
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('unit-counts-qa-screen')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp/renewal-qa').create(recursive: true);
    await File('tmp/renewal-qa/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('IBM Plex Sans Arabic')
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() {
    AppRuntime.config = {};
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  test('request validates tenant data and keeps the same id for retries', () {
    final r = readyRequest()
      ..idNumber = '١٢٣٤٥٦٧٨٩٠'
      ..mobile = '۰۵۰۱۲۳۴۵۶۷';
    r.validate();
    expect(r.toMap()['mobile'], '0501234567');
    expect(r.toMap()['contractId'], r.toMap()['contractId']);
    for (final v in ['123', '3234567890', 'abc1234567890']) {
      r.idNumber = v;
      expect(r.validate, throwsFormatException);
    }
  });
  for (final width in [360.0, 1280.0]) {
    testWidgets('renewal selection and minimal form fit width $width',
        (tester) async {
      final app = RenewalController();
      addTearDown(app.dispose);
      await mount(tester, app, const RenewContractSelectionScreen(),
          size: Size(width, 900));
      expect(find.text('إضافة تجديد عقد سابق'), findsOneWidget);
      await capture(tester, 'selection-${width.toInt()}');
      await tester.tap(find.text('إضافة تجديد عقد سابق'));
      await tester.pumpAndSettle();
      expect(find.byType(AppTextField), findsNWidgets(3));
      expect(field('رقم هوية المستأجر'), findsOneWidget);
      expect(field('رقم جوال المستأجر'), findsOneWidget);
      await capture(tester, 'form-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty submission is blocked and picker date stays displayed',
      (tester) async {
    final app = RenewalController();
    addTearDown(app.dispose);
    await mount(tester, app, const ExternalRenewalScreen());
    await tester.tap(find.text('إرسال طلب التجديد'));
    await tester.pumpAndSettle();
    expect(app.submissions, 0);
    expect(find.text('أرفق عقد منصة إيجار قبل إرسال الطلب'), findsOneWidget);
    await fill(tester, 'رقم هوية المستأجر', '١٢٣٤٥٦٧٨٩٠');
    await fill(tester, 'رقم جوال المستأجر', '٠٥٠١٢٣٤٥٦٧');
    await tester.ensureVisible(field('تاريخ ميلاد المستأجر'));
    await tester.tap(field('تاريخ ميلاد المستأجر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    final shown = tester
        .widget<EditableText>(find.descendant(
            of: field('تاريخ ميلاد المستأجر'),
            matching: find.byType(EditableText)))
        .controller
        .text;
    expect(shown, isNotEmpty);
    await fill(tester, 'رقم جوال المستأجر', '0509876543');
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('تاريخ ميلاد المستأجر'),
                matching: find.byType(EditableText)))
            .controller
            .text,
        shown);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'PDF upload succeeds, fake PDF is rejected and cancellation preserves selection',
      (tester) async {
    final app = RenewalController();
    addTearDown(app.dispose);
    var selected = PlatformFile(
        name: 'ejar.pdf',
        size: 8,
        bytes: Uint8List.fromList('%PDF-1.4'.codeUnits));
    bool cancel = false;
    var uploads = 0;
    final r = RenewalRequest();
    await mount(
        tester,
        app,
        ExternalRenewalScreen(
            initialRequest: r,
            picker: () async => cancel ? null : selected,
            uploader: (name, bytes) async {
              uploads++;
              return 'https://example.test/ejar.pdf';
            }));
    await tester.tap(find.text('اضغط لاختيار عقد PDF'));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(r.fileName, 'ejar.pdf');
    selected = PlatformFile(
        name: 'fake.pdf', size: 3, bytes: Uint8List.fromList([1, 2, 3]));
    await tester.tap(find.text('ejar.pdf'));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(r.fileName, 'ejar.pdf');
    cancel = true;
    await tester.tap(find.text('ejar.pdf'));
    await tester.pumpAndSettle();
    expect(r.fileName, 'ejar.pdf');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed submission preserves data and retry cannot double submit',
      (tester) async {
    final app = RenewalController()..fail = true;
    addTearDown(app.dispose);
    final r = readyRequest();
    await mount(tester, app, ExternalRenewalScreen(initialRequest: r));
    await tester.tap(find.text('إرسال طلب التجديد'));
    await tester.pumpAndSettle();
    expect(app.submissions, 1);
    expect(find.byType(ExternalRenewalScreen), findsOneWidget);
    app.fail = false;
    app.pending = Completer<void>();
    await tester.tap(find.text('إرسال طلب التجديد'));
    await tester.pump();
    expect(app.submissions, 2);
    final button =
        tester.widget<PrimaryButton>(find.byType(PrimaryButton).first);
    expect(button.onPressed, isNull);
    app.pending!.complete();
    await tester.pumpAndSettle();
    expect(app.submittedIds.toSet().length, 1);
    expect(app.contracts.length, 1);
    expect(find.byType(ContractDetailsScreen), findsOneWidget);
    expect(find.text('فتح عقد إيجار المرفق'), findsOneWidget);
    expect(find.text('دفع الرسوم'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('الرسوم'));
    await tester.tap(find.text('الرسوم'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يُطلب منك الدفع بعد'), findsOneWidget);
    expect(find.text('مدفوع'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'submitted request displays tenant details and live payment status',
      (tester) async {
    final app = RenewalController();
    addTearDown(app.dispose);
    final r = readyRequest(), saved = record(readyRequest());
    app.contracts.add(saved);
    await mount(tester, app, ContractDetailsScreen(contract: saved));
    await tester.ensureVisible(find.text('بيانات المستأجر'));
    await tester.tap(find.text('بيانات المستأجر'));
    await tester.pumpAndSettle();
    expect(find.text(r.idNumber), findsOneWidget);
    expect(find.text(r.birthDate), findsOneWidget);
    expect(find.text(r.mobile), findsOneWidget);
    Navigator.of(tester.element(find.text(r.idNumber))).pop();
    await tester.pumpAndSettle();
    app.contracts[0] = saved.copyWith(
        status: ContractStatus.awaitingPayment,
        paymentStatus: 'pending',
        totalFees: 299);
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('دفع الرسوم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'completed external renewal reuses its approved PDF and tenant data',
      (tester) async {
    final app = RenewalController();
    addTearDown(app.dispose);
    final saved = record(readyRequest()).copyWith(
        status: ContractStatus.authenticated,
        paymentStatus: 'paid',
        finalPdfFileName: 'renewed.pdf',
        finalPdfUrl: 'https://example.test/renewed.pdf');
    app.contracts.add(saved);
    await mount(tester, app, const RenewContractSelectionScreen());
    final card = find.byKey(ValueKey<String>('renew-contract-${saved.id}'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    final screen = tester
        .widget<ExternalRenewalScreen>(find.byType(ExternalRenewalScreen));
    expect(screen.initialRequest!.sourceContractId, saved.id);
    expect(screen.initialRequest!.fileUrl, saved.finalPdfUrl);
    expect(screen.initialRequest!.idNumber, readyRequest().idNumber);
    expect(screen.initialRequest!.submissionId, isNot(saved.id));
    expect(tester.takeException(), isNull);
  });
}
