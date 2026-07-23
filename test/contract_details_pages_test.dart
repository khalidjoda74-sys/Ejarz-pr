import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all contract detail entries open full-screen pages',
      (tester) async {
    await _pumpContract(tester, const Size(390, 844), _richContract());

    final routes = <String, String>{
      'بيانات العقد': 'بيانات العقد الأساسية',
      'الأطراف': 'أطراف العقد',
      'العقار': 'بيانات العقار والوحدة',
      'الرسوم': 'الرسوم والمدفوعات',
      'المرفقات': 'المرفقات',
    };

    for (final route in routes.entries) {
      final trigger = find.text(route.key);
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text(route.value), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Scaffold), findsWidgets);

      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();
    }
  });

  for (final size in <Size>[
    const Size(360, 640),
    const Size(390, 844),
    const Size(412, 915),
  ]) {
    testWidgets(
        'long property snapshot scrolls at ${size.width}x${size.height}',
        (tester) async {
      await _pumpContract(tester, size, _richContract());

      final propertyTrigger = find.text('العقار');
      await tester.ensureVisible(propertyTrigger);
      await tester.tap(propertyTrigger);
      await tester.pumpAndSettle();

      expect(find.text('بيانات الملكية'), findsOneWidget);
      expect(find.text('العنوان الوطني'), findsOneWidget);
      expect(find.text('العقار والوحدة'), findsOneWidget);
      expect(find.text('المرافق والعدادات'), findsOneWidget);
      expect(find.text('تفاصيل إضافية'), findsOneWidget);

      final savedValue = find.text('قيمة إضافية محفوظة داخل العقد');
      await tester.scrollUntilVisible(
        savedValue,
        350,
        scrollable: find.byType(Scrollable).last,
      );
      expect(savedValue, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('parties are grouped without duplicate names', (tester) async {
    await _pumpContract(tester, const Size(390, 844), _richContract());

    final trigger = find.text('الأطراف');
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.text('محمد العتيبي'), findsOneWidget);
    expect(find.text('شركة الرواد'), findsOneWidget);
    expect(find.text('الوكيل / المفوض'), findsOneWidget);
    expect(find.text('مرجع طرف مخصص'), findsOneWidget);
    expect(find.text('تفاصيل إضافية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty attachment data keeps fallback files and download action',
      (tester) async {
    await _pumpContract(
      tester,
      const Size(390, 844),
      _richContract(attachments: const <String, String>{}),
    );

    final trigger = find.text('المرفقات');
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.text('هوية المؤجر'), findsOneWidget);
    expect(find.text('هوية المستأجر'), findsOneWidget);
    expect(find.text('وثيقة الملكية'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_rounded).first);
    await tester.pump();
    expect(find.text('بدأ تنزيل lessor_id.pdf'), findsOneWidget);
  });

  testWidgets('draft shows resume action and professional empty states',
      (tester) async {
    final draft = ContractDraft();
    final contract = ContractRecord(
      id: 'draft-1',
      requestNumber: 'DRAFT-2026-1',
      uid: 'demo-user',
      type: ContractType.residential,
      role: UserRole.lessor,
      title: 'مسودة عقد',
      property: 'العقار غير محدد',
      lessorName: 'غير محدد',
      tenantName: 'غير محدد',
      date: '2026/07/22',
      status: ContractStatus.draft,
      totalFees: 0,
      timeline: const <StatusTimelineItem>[],
      draftData: draft,
    );
    await _pumpContract(tester, const Size(390, 844), contract);

    expect(find.text('إكمال المسودة'), findsOneWidget);
    expect(find.text('تحميل ملخص الطلب'), findsNothing);
    expect(find.text('الدعم الفني'), findsNothing);

    final emptySections = <String, String>{
      'بيانات العقد': 'لم تُضف بيانات العقد بعد.',
      'الأطراف': 'لم تُضف بيانات الأطراف بعد.',
      'الرسوم': 'لم تُضف البيانات المالية بعد.',
    };
    for (final section in emptySections.entries) {
      await tester.ensureVisible(find.text(section.key));
      await tester.tap(find.text(section.key));
      await tester.pumpAndSettle();
      expect(find.text(section.value), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.text('العقار'));
    await tester.tap(find.text('العقار'));
    await tester.pumpAndSettle();
    expect(find.text('لم تُضف بيانات العقار بعد.'), findsOneWidget);
    expect(find.text('إكمال بيانات العقار'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('المرفقات'));
    await tester.tap(find.text('المرفقات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد مرفقات محفوظة.'), findsOneWidget);
    expect(find.text('هوية المؤجر'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إكمال المسودة'));
    await tester.tap(find.text('إكمال المسودة'));
    await tester.pumpAndSettle();
    expect(find.text('استكمال المسودة'), findsOneWidget);
    expect(find.text('بيانات الملكية'), findsWidgets);
  });

  testWidgets('rejected contract is terminal and keeps submitted data visible',
      (tester) async {
    final contract = _richContract().copyWith(
      status: ContractStatus.rejected,
      rejectionReason: 'تعذر التحقق من وثيقة الملكية.',
      timeline: const <StatusTimelineItem>[
        StatusTimelineItem(
          title: 'تم استلام الطلب',
          subtitle: 'تم استلام الطلب بنجاح',
          date: '2026/07/22',
          time: '10:00',
          completed: true,
        ),
        StatusTimelineItem(
          title: 'قيد المعالجة',
          subtitle: 'تمت مراجعة بيانات الطلب',
          date: '2026/07/22',
          time: '10:30',
          completed: true,
          eventStatus: ContractStatus.processing,
        ),
        StatusTimelineItem(
          title: 'تم رفض الطلب نهائيًا',
          subtitle: 'سبب الرفض: تعذر التحقق من وثيقة الملكية.',
          date: '2026/07/22',
          time: '11:00',
          current: true,
          eventStatus: ContractStatus.rejected,
        ),
      ],
    );
    await _pumpContract(tester, const Size(390, 844), contract);

    expect(find.text('تم رفض طلب العقد نهائيًا'), findsOneWidget);
    expect(
      find.text(
        'تم رفض الطلب رقم REQ-2026-101 نهائيًا بسبب: تعذر التحقق من وثيقة الملكية. لا يمكن تعديل هذا الطلب أو إعادة إرساله. يمكنك تقديم طلب جديد، أو التواصل مع الدعم الفني إذا احتجت إلى توضيح.',
      ),
      findsOneWidget,
    );
    expect(find.text('تم رفض الطلب نهائيًا'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('مكتمل'), findsNothing);
    expect(find.text('تحميل ملخص الطلب'), findsNothing);
    expect(find.text('دفع الرسوم'), findsNothing);
    expect(find.text('إنشاء طلب جديد'), findsOneWidget);
    expect(find.text('الدعم الفني'), findsOneWidget);

    await tester.ensureVisible(find.text('الأطراف'));
    await tester.tap(find.text('الأطراف'));
    await tester.pumpAndSettle();
    expect(find.text('محمد العتيبي'), findsOneWidget);
    expect(find.text('شركة الرواد'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إنشاء طلب جديد'));
    await tester.tap(find.text('إنشاء طلب جديد'));
    await tester.pumpAndSettle();
    expect(find.text('إنشاء عقد جديد'), findsWidgets);
    expect(find.text('استكمال المسودة'), findsNothing);
  });

  testWidgets('rejected contract never invents attachment files',
      (tester) async {
    final contract = _richContract(
      attachments: const <String, String>{},
    ).copyWith(
      status: ContractStatus.rejected,
      rejectionReason: 'تعذر التحقق من بيانات الطلب',
    );
    await _pumpContract(tester, const Size(390, 844), contract);

    await tester.ensureVisible(find.text('المرفقات'));
    await tester.tap(find.text('المرفقات'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد مرفقات محفوظة'), findsOneWidget);
    expect(find.text('هوية المؤجر'), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
  });

  testWidgets('contract support opens the form and demo submission is blocked',
      (tester) async {
    final contract = _richContract();
    final controller = await _pumpContract(
      tester,
      const Size(390, 844),
      contract,
    );

    await tester.ensureVisible(find.text('الدعم الفني'));
    await tester.tap(find.text('الدعم الفني'));
    await tester.pumpAndSettle();

    expect(find.text('نحن هنا لمساعدتك'), findsOneWidget);
    final fields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields[0].controller?.text, 'دعم عقد REQ-2026-101');
    expect(fields[1].controller?.text, contains('REQ-2026-101'));

    final sendButton = find.text('إرسال الطلب');
    await tester.scrollUntilVisible(
      sendButton,
      450,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(
      find.text('الدعم الفني غير متاح في النسخة التجريبية'),
      findsOneWidget,
    );
    expect(find.text('حسنًا، فهمت'), findsOneWidget);
    expect(controller.supportTickets, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<AppController> _pumpContract(
  WidgetTester tester,
  Size size,
  ContractRecord contract,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = AppController()
    ..splashCompleted = true
    ..onboardingCompleted = true
    ..loggedIn = true;

  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ContractDetailsScreen(contract: contract),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return controller;
}

ContractRecord _richContract({Map<String, String>? attachments}) {
  return ContractRecord(
    id: 'contract-history-1',
    requestNumber: 'REQ-2026-101',
    uid: 'demo-user',
    type: ContractType.residential,
    role: UserRole.lessor,
    title: 'طلب عقد تجريبي',
    property: 'الرياض - حي النرجس - الوحدة 12',
    lessorName: 'محمد العتيبي',
    tenantName: 'شركة الرواد',
    date: '2026/07/22',
    status: ContractStatus.processing,
    totalFees: 398,
    paymentStatus: 'paid',
    paymentReference: 'PAY-101',
    invoiceNumber: 'INV-101',
    paymentMethod: 'mada',
    cardBrand: 'mada',
    cardLast4: '1234',
    paidAt: '2026/07/22 10:30',
    contractDetails: const <String, String>{
      'نوع العقد': 'سكني',
      'تاريخ بداية العقد': '2026/08/01',
      'تاريخ نهاية العقد': '2027/07/31',
      'مدة العقد': '12 شهرًا',
      'قيمة الإيجار': '48,000 ريال',
      'دورة السداد': 'ربع سنوي',
      'عدد الدفعات': '4',
      'الكهرباء': 'على المستأجر',
      'تجديد تلقائي': 'لا',
      'حقل عقد مخصص': 'قيمة عقد إضافية',
    },
    partyDetails: const <String, String>{
      'اسم المؤجر': 'محمد العتيبي',
      'جوال المؤجر': '0500000000',
      'اسم المستأجر': 'شركة الرواد',
      'جوال المستأجر': '0550000000',
      'اسم الوكيل': 'خالد السالم',
      'رقم التفويض': 'AUTH-101',
      'مرجع طرف مخصص': 'PARTY-CUSTOM-1',
    },
    propertyDetails: const <String, String>{
      'مصدر العقار': 'نسخة محفوظة في العقد',
      'رقم وثيقة الملكية': '550000101',
      'نوع وثيقة الملكية': 'صك إلكتروني',
      'المدينة': 'الرياض',
      'الحي': 'النرجس',
      'الشارع': 'شارع الأمير',
      'رقم المبنى': '1010',
      'الرمز البريدي': '13321',
      'استخدام العقار': 'سكني',
      'نوع العقار': 'عمارة',
      'اسم المبنى': 'عمارة النرجس',
      'عدد الأدوار': '4',
      'إجمالي الوحدات': '16',
      'رقم الوحدة': '12',
      'نوع الوحدة': 'شقة',
      'الدور': 'الثالث',
      'المساحة': '140 م²',
      'عدد الغرف': '4',
      'عدد دورات المياه': '3',
      'مطبخ': 'نعم',
      'مكيفات سبليت': 'نعم',
      'موقف خاص': 'نعم',
      'عداد الكهرباء': 'E-101',
      'حقل عقار مستقبلي': 'قيمة إضافية محفوظة داخل العقد',
    },
    attachmentFiles: attachments ??
        const <String, String>{
          'هوية المؤجر': 'lessor.pdf',
          'هوية المستأجر': 'tenant.pdf',
          'وثيقة الملكية': 'ownership.pdf',
        },
    timeline: const <StatusTimelineItem>[
      StatusTimelineItem(
        title: 'تم استلام الطلب',
        subtitle: 'الطلب قيد المعالجة.',
        date: '2026/07/22',
        time: '10:00',
        completed: true,
        current: true,
      ),
    ],
  );
}
