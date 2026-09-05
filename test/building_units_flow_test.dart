import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:aqood_pro/core/saudi_reference_data.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/create_contract.dart';
import 'package:aqood_pro/screens/pricing.dart';
import 'package:aqood_pro/screens/wallet_profile.dart';
import 'package:aqood_pro/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'property_management_pricing_test.dart' show buildingData, newUnit;

Future<void> mount(WidgetTester tester, AppController controller, Widget home,
    {Size size = const Size(390, 844)}) async {
  await tester.runAsync(SaudiReferenceCatalog.load);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        home: Directionality(textDirection: TextDirection.rtl, child: home),
      )));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
    matching: find.byType(TextFormField));

Future<void> fill(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label).first);
  await tester.enterText(field(label).first, value);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label, String value) async {
  final dropdown =
      find.byWidgetPredicate((w) => w is AppDropdownField && w.label == label);
  await tester.ensureVisible(dropdown);
  await tester.tap(find.descendant(
      of: dropdown, matching: find.byType(DropdownButtonFormField<String>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(360, 640), const Size(412, 915)]) {
    testWidgets(
        'building plus five units fits iOS ${size.width}x${size.height}',
        (tester) async {
      final controller = AppController();
      addTearDown(controller.dispose);
      await mount(tester, controller,
          PropertiesScreen(onMenu: () {}, onNotifications: () {}),
          size: size);
      await tester.tap(find.byTooltip('إضافة عقار'));
      await tester.pumpAndSettle();
      final dropdowns =
          tester.widgetList<AppDropdownField>(find.byType(AppDropdownField));
      expect(dropdowns.first.label, 'نوع العقار');
      await choose(tester, 'طريقة تأجير العمارة', 'وحدات مستقلة');
      expect(find.text('بيانات الوحدة'), findsNothing);
      await fill(tester, 'رقم الوثيقة', '1234567890');
      await fill(tester, 'تاريخ الوثيقة', '2026/01/01');
      await fill(tester, 'اسم العقار', 'عمارة الاختبار');
      await fill(tester, 'الشارع', 'شارع الاختبار');
      await fill(tester, 'رقم المبنى', '1234');
      await fill(tester, 'الرقم الإضافي', '5678');
      await fill(tester, 'الرمز البريدي', '12345');
      await fill(tester, 'الحي', 'النرجس');
      await fill(tester, 'عدد الأدوار', '3');
      await fill(tester, 'إجمالي الوحدات', '10');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ العقار'));
      await tester.pumpAndSettle();
      expect(controller.properties.single.units, isEmpty);
      expect(find.text('إضافة وحدات للعمارة'), findsOneWidget);
      await tester.tap(find.text('إضافة وحدات للعمارة'));
      await tester.pumpAndSettle();
      await fill(tester, 'عدد الوحدات المراد إضافتها', '5');
      await fill(tester, 'مساحة الوحدة (م²)', '135.5');
      await fill(tester, 'عدد الغرف', '4');
      await fill(tester, 'الصالات', '2');
      await fill(tester, 'دورات المياه', '3');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -14000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إضافة 5 وحدات'));
      await tester.pumpAndSettle();
      final saved = controller.properties.single;
      expect(saved.units.length, 5);
      expect(saved.units.map((u) => u.number).toSet().length, 5);
      expect(
          saved.units.every((u) =>
              u.data!.roomsCount == '4' &&
              u.data!.bathroomsCount == '3' &&
              u.data!.area == '135.5'),
          isTrue);
      await tester.tap(find.text('شقة 1 • شقة • 0'));
      await tester.pumpAndSettle();
      expect(find.text('تفاصيل شقة 1'), findsOneWidget);
      expect(find.text('135.5 م²'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'whole building can be reopened and remains one rentable property',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final data =
        newUnit('1').detailsFor(await controller.saveProperty(buildingData()))
          ..rentalMode = 'whole'
          ..unitType = 'عمارة'
          ..unitName = 'العمارة كاملة'
          ..totalUnits = '1';
    // Use a separate record: converting a populated building must not discard units.
    controller.properties.clear();
    await controller.saveProperty(data);
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة وحدات للعمارة'), findsNothing);
    await tester.ensureVisible(find.text('تعديل العقار'));
    await tester.tap(find.text('تعديل العقار'));
    await tester.pumpAndSettle();
    expect(find.text('عمارة كاملة'), findsOneWidget);
    await fill(tester, 'عدد الغرف', '8');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ العقار'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.managesUnits, isFalse);
    expect(controller.properties.single.units.single.data!.roomsCount, '8');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'contract selects a specific saved unit and restores its own details',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final building = await controller.saveProperty(buildingData());
    final saved = await controller.saveProperty(building.data!,
        existing: building,
        unitEdits: [newUnit('1', rooms: '3'), newUnit('2', rooms: '5')]);
    final draft = ContractDraft()
      ..property = PropertyData.copyOf(saved.data!)
      ..property.savedPropertyId = saved.id
      ..property.propertySource = 'عقار محفوظ';
    await mount(tester, controller,
        CreateContractScreen(initialDraft: draft, initialStep: 3));
    await choose(tester, 'الوحدة داخل العمارة', '2 • شقة 2');
    final roomField = tester.widget<AppTextField>(find
        .byWidgetPredicate((w) => w is AppTextField && w.label == 'عدد الغرف'));
    expect(roomField.initialValue, '5');
    final meter = tester.widget<AppTextField>(find.byWidgetPredicate(
        (w) => w is AppTextField && w.label == 'رقم عداد الكهرباء'));
    expect(meter.initialValue, '7002');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pricing page fits small iPhone and lists inclusive examples',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await mount(tester, controller, const PricingScreen(),
        size: const Size(360, 640));
    expect(find.text('299 ريال'), findsOneWidget);
    expect(find.text('399 ريال'), findsOneWidget);
    expect(find.text('مثال: عقد لسنتين = 424 ريال'), findsOneWidget);
    expect(find.text('مثال: عقد لسنتين = 799 ريال'), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
