import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/contract_calculation_engine.dart';
import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/widgets/assistant_field_scope.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'contract_form_audit_test.dart' show shell, textField, shown;

ContractDraft completeDraft({bool commercial = false}) {
  PartyData party(String name, String id) => PartyData(
      fullName: name,
      idNumber: id,
      birthDate: '1980/01/01',
      mobile: '0501234567',
      email: 'qa@example.test',
      city: 'الرياض',
      district: 'النرجس',
      nationalAddress: 'شارع الاختبار 1234',
      iban: 'SA0380000000608010167519',
      bankName: 'مصرف الراجحي',
      accountOwner: name,
      kind: commercial ? PartyKind.company : PartyKind.individual,
      commercialRegistration: '1234567890',
      unifiedNumber: '7123456789',
      authorizedPersonName: 'المفوض التجريبي',
      authorizedPersonId: '1123456789');
  final draft = ContractDraft()
    ..type = commercial ? ContractType.commercial : ContractType.residential
    ..lessor = party('المؤجر التجريبي', '1123456789')
    ..tenant = party('المستأجر التجريبي', '1234567890')
    ..startDate = '2027/01/01'
    ..endDate = '2027/12/31'
    ..firstPaymentDate = '2027/01/01'
    ..rentValue = '12000.50'
    ..paymentChannel = 'تحويل بنكي'
    ..property = PropertyData(
        ownershipDocumentNumber: '1234567890',
        ownershipDocumentDate: '2025/01/01',
        propertyUsage: commercial ? 'تجاري' : 'سكن عوائل',
        unitType: commercial ? 'مكتب إداري' : 'شقة',
        floorsCount: '2',
        unitsPerFloor: '2',
        totalUnits: '4',
        city: 'الرياض',
        district: 'النرجس',
        street: 'شارع الاختبار',
        buildingNumber: '1234',
        additionalNumber: '5678',
        postalCode: '12345',
        buildingName: 'العقار التجريبي',
        unitNumber: '1',
        unitName: 'الوحدة التجريبية',
        floor: '1',
        area: '120.5',
        roomsCount: '3',
        bathroomsCount: '2',
        hallsCount: '1');
  if (commercial) {
    draft.representative = RepresentativeData(
        enabled: true,
        fullName: 'الوكيل التجريبي',
        idNumber: '1123456789',
        birthDate: '1980/01/01',
        mobile: '0501234567',
        authorizationNumber: '1234567890');
  }
  for (final a in draft.attachments) {
    a.uploaded = true;
    a.fileName = 'qa.pdf';
    a.downloadUrl = 'https://example.test/qa.pdf';
  }
  return draft;
}

class AuditController extends AppController {
  ContractDraft? submitted;
  int submissions = 0;
  @override
  Future<ContractRecord> submitContract(ContractDraft draft,
      {String draftId = '',
      DraftProgress progress = const DraftProgress()}) async {
    submissions++;
    submitted =
        FirebaseRepository.draftFromMap(FirebaseRepository.draftToMap(draft));
    return ContractRecord(
        id: 'qa-contract',
        requestNumber: 'QA-0001',
        type: draft.type,
        role: draft.role,
        title: draft.title,
        property: 'عقار اختبار',
        lessorName: draft.lessor.fullName,
        tenantName: draft.tenant.fullName,
        date: '2026/10/04',
        status: ContractStatus.awaitingPayment,
        totalFees: draft.totalPayable,
        timeline: []);
  }
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final f = textField(label).first;
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PrimaryButton, 'التالي'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

ContractDraft activeDraft(WidgetTester tester) => tester
    .widget<AssistantFieldScope>(find.byType(AssistantFieldScope))
    .controller
    .readDraft();
Future<void> choose(WidgetTester tester, String label, String value) async {
  final field =
      find.byWidgetPredicate((w) => w is AppDropdownField && w.label == label);
  await tester.ensureVisible(field);
  await tester.tap(find.descendant(
      of: field, matching: find.byType(DropdownButtonFormField<String>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppRuntime.config = {};
  });
  testWidgets(
      'manual typing preserves cursor while external dropdown value updates',
      (tester) async {
    String value = '1234', choice = 'سنوي';
    late StateSetter rebuild;
    await tester.pumpWidget(shell(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return Scaffold(
          body: Column(children: [
        AppTextField(
            label: 'قيمة',
            hint: '',
            initialValue: value,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => setState(() => value = v)),
        AppDropdownField(
            label: 'الدورية',
            value: choice,
            items: const ['سنوي', 'شهري'],
            onChanged: (v) => setState(() => choice = v!)),
      ]));
    })));
    await fill(tester, 'قيمة', '١٢٣٤٥');
    expect(value, '12345');
    expect(shown(tester, 'قيمة'), '12345');
    final controller =
        tester.widget<EditableText>(textField('قيمة')).controller;
    controller.selection = const TextSelection.collapsed(offset: 2);
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(controller.selection.baseOffset, 2);
    rebuild(() => choice = 'شهري');
    await tester.pumpAndSettle();
    expect(
        tester
            .state<FormFieldState<String>>(
                find.byType(DropdownButtonFormField<String>))
            .value,
        'شهري');
  });

  for (final commercial in [false, true]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
          'complete ${commercial ? 'commercial-company-agent' : 'residential-individual'} flow $width retains seven steps and submission data',
          (tester) async {
        await tester.runAsync(SaudiReferenceCatalog.load);
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AuditController();
        addTearDown(app.dispose);
        await tester.pumpWidget(AppScope(
            controller: app,
            child: shell(CreateContractScreen(
                initialDraft: completeDraft(commercial: commercial),
                initialStep: 0))));
        await tester.pumpAndSettle();
        await next(tester);
        expect(find.byType(DateField), findsOneWidget);
        await fill(tester, 'رقم الوثيقة', '١٢٣٤٥٦٧٨٩٠');
        await next(tester);
        expect(find.text('بيانات الأطراف'), findsOneWidget);
        final nameLabel = commercial ? 'اسم المنشأة' : 'الاسم الكامل';
        await fill(tester, nameLabel, 'المؤجر بعد التعديل');
        await tester.ensureVisible(find.text('المستأجر').first);
        await tester.tap(find.text('المستأجر').first);
        await tester.pumpAndSettle();
        await fill(tester, nameLabel, 'المستأجر بعد التعديل');
        await next(tester);
        expect(find.text('بيانات العقار والوحدة'), findsOneWidget);
        await fill(tester, 'رقم الوحدة', '12');
        await fill(tester, 'اسم الوحدة', 'وحدة الاختبار المعدلة');
        await fill(tester, 'مساحة الوحدة (م²)', '١٥٠٫٥');
        await tester.tap(find.widgetWithText(SecondaryButton, 'السابق'));
        await tester.pumpAndSettle();
        await next(tester);
        expect(shown(tester, 'رقم الوحدة'), '12');
        expect(shown(tester, 'مساحة الوحدة (م²)'), '150.5');
        await next(tester);
        expect(find.text('البيانات المالية'), findsOneWidget);
        await fill(tester, 'مبلغ الإيجار السنوي', '٢٤٬٠٠٠٫٥٠');
        await choose(tester, 'تكرار الدفع', 'شهري');
        expect(activeDraft(tester).rentPeriod, 'شهري');
        expect(shown(tester, 'عدد الدفعات'), '12');
        await fill(
            tester, 'شروط إضافية', 'شروط اختبار محفوظة دون إرسال إلى الإنتاج');
        await next(tester);
        expect(activeDraft(tester).installments.length, 12);
        expect(
            activeDraft(tester).installments.every((i) => i.dueDate.isNotEmpty),
            isTrue);
        await next(tester);
        expect(find.text('إرسال الطلب'), findsOneWidget);
        await tester.tap(find.widgetWithText(PrimaryButton, 'إرسال الطلب'));
        await tester.pumpAndSettle();
        expect(app.submissions, 0);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        for (final title in [
          'أقر بصحة البيانات والمستندات',
          'أوافق على مشاركة البيانات اللازمة',
          'أوافق على الشروط والأحكام'
        ]) {
          final toggle = find
              .byWidgetPredicate((w) => w is ToggleCard && w.title == title);
          await tester.ensureVisible(toggle);
          await tester
              .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(PrimaryButton, 'إرسال الطلب'));
        await tester.pumpAndSettle();
        expect(app.submissions, 1);
        expect(find.text('تم إنشاء الطلب بنجاح'), findsOneWidget);
        final sent = app.submitted!;
        expect(sent.rentValue, '24000.50');
        expect(sent.property.ownershipDocumentNumber, '1234567890');
        expect(sent.property.ownershipDocumentDate, '2025/01/01');
        expect(sent.property.unitNumber, '12');
        expect(sent.property.unitName, 'وحدة الاختبار المعدلة');
        expect(sent.property.area, '150.5');
        expect(sent.lessor.fullName, 'المؤجر بعد التعديل');
        expect(sent.tenant.fullName, 'المستأجر بعد التعديل');
        expect(sent.representative.enabled, commercial);
        expect(sent.installments.length, 12);
        expect(
            sent.installments
                .map((i) => ContractCalculationEngine.money(i.amount)!)
                .reduce((a, b) => a + b),
            2400050);
        expect(sent.specialTerms, 'شروط اختبار محفوظة دون إرسال إلى الإنتاج');
        expect(
            sent.attachments
                .every((a) => a.uploaded && a.downloadUrl.isNotEmpty),
            isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'final review rejects invalid financial date and returns to editable financial step',
      (tester) async {
    final app = AuditController();
    addTearDown(app.dispose);
    final draft = completeDraft()
      ..firstPaymentDate = '2027/02/31'
      ..acceptAccuracyDeclaration = true
      ..acceptDataSharing = true
      ..acceptTerms = true;
    await tester.pumpWidget(AppScope(
        controller: app,
        child:
            shell(CreateContractScreen(initialDraft: draft, initialStep: 6))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();
    expect(app.submissions, 0);
    expect(find.text('البيانات المالية'), findsOneWidget);
  });

  test(
      'custom schedules have complete dates within the contract and exact totals',
      () {
    final draft = completeDraft()
      ..paymentScheduleType = 'مخصص'
      ..paymentCount = 7;
    draft.regenerateInstallments();
    expect(draft.installments.length, 7);
    expect(
        draft.installments
            .every((i) => ContractCalculationEngine.date(i.dueDate) != null),
        isTrue);
    expect(
        draft.installments.last.dueDate.compareTo(draft.endDate) <= 0, isTrue);
    expect(
        draft.installments
            .map((i) => ContractCalculationEngine.money(i.amount)!)
            .reduce((a, b) => a + b),
        1200050);
  });

  final invalidCases = <String, (void Function(ContractDraft), int)>{
    'future ownership date': (
      (d) => d.property.ownershipDocumentDate = '2200/01/01',
      1
    ),
    'invalid ownership number': (
      (d) => d.property.ownershipDocumentNumber = '12',
      1
    ),
    'missing lessor city': ((d) => d.lessor.city = '', 2),
    'minor tenant': ((d) => d.tenant.birthDate = '2020/01/01', 2),
    'invalid tenant identity': ((d) => d.tenant.idNumber = '123', 2),
    'invalid iban': ((d) => d.lessor.iban = 'SA123', 2),
    'negative property count': ((d) => d.property.roomsCount = '-3', 3),
    'invalid meter': ((d) => d.property.waterMeter = 'bad', 3),
    'three decimal money': ((d) => d.rentValue = '12000.123', 4),
    'zero custom installments': (
      (d) {
        d.paymentScheduleType = 'مخصص';
        d.paymentCount = 0;
      },
      4
    ),
    'last payment after expiry': ((d) => d.firstPaymentDate = '2027/12/01', 4),
    'missing fixed gas charge': (
      (d) {
        d.gas.enabled = true;
        d.gas.calculationMethod = 'مبلغ مقطوع';
      },
      4
    ),
    'required attachment missing url': (
      (d) => d.attachments.first.downloadUrl = '',
      5
    ),
    'invalid representative date': (
      (d) {
        d.representative = completeDraft(commercial: true).representative;
        d.representative.authorizationDate = '2025/02/31';
      },
      2
    ),
    'reversed representative dates': (
      (d) {
        d.representative = completeDraft(commercial: true).representative;
        d.representative.authorizationDate = '2025/05/01';
        d.representative.expiryDate = '2025/04/01';
      },
      2
    ),
  };
  for (final entry in invalidCases.entries) {
    testWidgets('review rejects ${entry.key} and opens its step',
        (tester) async {
      final app = AuditController();
      addTearDown(app.dispose);
      final draft = completeDraft()
        ..acceptAccuracyDeclaration = true
        ..acceptDataSharing = true
        ..acceptTerms = true;
      entry.value.$1(draft);
      await tester.pumpWidget(AppScope(
          controller: app,
          child: shell(
              CreateContractScreen(initialDraft: draft, initialStep: 6))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PrimaryButton, 'إرسال الطلب'));
      await tester.pumpAndSettle();
      expect(app.submissions, 0);
      expect(
          tester
              .widget<AssistantFieldScope>(find.byType(AssistantFieldScope))
              .step,
          entry.value.$2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (step, label) in [
    (2, 'تاريخ الميلاد'),
    (4, 'تاريخ بداية العقد'),
    (4, 'تاريخ أول دفعة')
  ]) {
    testWidgets('$label remains displayed after selecting a date',
        (tester) async {
      final app = AuditController();
      addTearDown(app.dispose);
      await tester.pumpWidget(AppScope(
          controller: app,
          child: shell(CreateContractScreen(
              initialDraft: completeDraft(), initialStep: step))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(textField(label));
      await tester.tap(textField(label));
      await tester.pumpAndSettle();
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      final expected =
          ContractCalculationEngine.formatDate(picker.initialDate!);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(shown(tester, label), expected);
      expect(tester.takeException(), isNull);
    });
  }
}
