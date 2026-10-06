import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/property_management.dart';
import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/screens/pricing.dart';
import 'package:aqdak/screens/wallet_profile.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:aqdak/widgets/unit_count_field.dart';
import 'package:aqdak/widgets/saudi_reference_fields.dart';
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
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('unit-counts-qa-screen'), child: child!),
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
  if (label == 'تاريخ الوثيقة') {
    await tester.ensureVisible(field(label));
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field(label), matching: find.byType(EditableText)))
            .readOnly,
        isTrue);
    await tester.tap(field(label));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final expected =
        '${picker.initialDate!.year}/${picker.initialDate!.month.toString().padLeft(2, '0')}/${picker.initialDate!.day.toString().padLeft(2, '0')}';
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field(label), matching: find.byType(EditableText)))
            .controller
            .text,
        expected);
    return;
  }
  if (label == 'الحي' || label == 'المنطقة' || label == 'المدينة') {
    final location = find.byType(SaudiLocationFields);
    await tester.ensureVisible(location);
    await tester
        .tap(find.descendant(of: location, matching: find.text('اختر $label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, value);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, value).first);
    await tester.pumpAndSettle();
    return;
  }
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
  testWidgets(
      'copy units preserves details, reserves numbers and edits independently',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final sourceData = PropertyData.copyOf(newUnit('١').data!)
      ..unitName = 'الوحدة الشمالية'
      ..residentialCategory = 'عوائل'
      ..electricityMeter = '7001'
      ..waterMeter = '8001'
      ..gasMeter = '9001'
      ..kitchenCount = '2'
      ..acCentralCount = '3';
    final source = UnitRecord.fromData(sourceData, status: 'مؤجرة');
    final building = managedPropertyRecord(
        buildingData(), 'copy-building', [source, newUnit('02'), newUnit('4')]);
    controller.properties.clear();
    controller.properties.add(building);
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار').first);
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('copy-unit-١'));
    await tester.ensureVisible(copy);
    await tester
        .tap(find.descendant(of: copy, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    String shown(String label, [int index = 0]) => tester
        .widget<EditableText>(find.descendant(
            of: field(label).at(index), matching: find.byType(EditableText)))
        .controller
        .text;
    expect(shown('رقم الوحدة'), '3');
    expect(field('اسم الوحدة'), findsNothing);
    expect(shown('مساحة الوحدة (م²)'), '120.5');
    expect(shown('رقم عداد الكهرباء'), sourceData.electricityMeter);
    await fill(tester, 'عدد النسخ', '2');
    expect(shown('رقم الوحدة', 0), '3');
    expect(shown('رقم الوحدة', 1), '5');
    await fill(tester, 'رقم الوحدة', '7');
    expect(field('اسم الوحدة'), findsNothing);
    await fill(tester, 'رقم الدور', '2');
    await fill(tester, 'عداد الكهرباء (اختياري)', '999');
    await fill(tester, 'عدد النسخ', '1');
    expect(shown('رقم الوحدة'), '7');
    expect(shown('رقم الدور'), '2');
    expect(shown('رقم عداد الكهرباء'), '999');
    await fill(tester, 'عدد النسخ', '2');
    expect(shown('رقم الوحدة', 0), '7');
    expect(shown('رقم الوحدة', 1), '3');
    final secondNumber = field('رقم الوحدة').at(1);
    await tester.ensureVisible(secondNumber);
    await tester.enterText(secondNumber, '٧');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.tap(find.text('إضافة 2 وحدات'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.units.length, 3);
    expect(find.text('رقم الوحدة مستخدم؛ اختر رقمًا آخر'), findsWidgets);
    await tester.ensureVisible(secondNumber);
    await tester.enterText(secondNumber, '3');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة 2 وحدات'));
    await tester.pumpAndSettle();
    final saved = controller.properties.single;
    expect(saved.units.map((unit) => unit.number), ['١', '02', '4', '7', '3']);
    final firstCopy = saved.units.firstWhere((unit) => unit.number == '7');
    final secondCopy = saved.units.firstWhere((unit) => unit.number == '3');
    expect(firstCopy.isAvailable, isTrue);
    expect(secondCopy.isAvailable, isTrue);
    expect(firstCopy.floor, '2');
    expect(firstCopy.name, source.name);
    expect(secondCopy.name, source.name);
    expect(firstCopy.data!.electricityMeter, '999');
    for (final unit in [firstCopy, secondCopy]) {
      expect(unit.data!.roomsCount, sourceData.roomsCount);
      expect(unit.data!.kitchenCount, '2');
      expect(unit.data!.acCentralCount, '3');
      expect(unit.data!.notes, sourceData.notes);
      expect(unit.data!.furnishingStatus, sourceData.furnishingStatus);
      expect(unit.data!.residentialCategory, 'عوائل');
    }
    expect(source.data!.electricityMeter, sourceData.electricityMeter);
    expect(source.floor, '1');
    expect(source.status, 'مؤجرة');
    final firstCopyLabel = find.text(
        'رقم ${firstCopy.number} • ${firstCopy.area.replaceAll(' م²', '')} م²');
    await tester.ensureVisible(firstCopyLabel);
    await tester.tap(firstCopyLabel);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تعديل بيانات الوحدة'));
    await tester.tap(find.text('تعديل بيانات الوحدة'));
    await tester.pumpAndSettle();
    await fill(tester, 'عدد الغرف', '6');
    await fill(tester, 'اسم الوحدة', 'الوحدة الشمالية المعدلة');
    tester.testTextInput.hide();
    await tester.tap(find.text('حفظ الوحدة'));
    await tester.pumpAndSettle();
    final updated = controller.properties.single;
    expect(updated.units.firstWhere((unit) => unit.number == '7').name,
        'الوحدة الشمالية المعدلة');
    expect(updated.units.firstWhere((unit) => unit.number == '3').name,
        source.name);
    expect(
        updated.units.firstWhere((unit) => unit.number == '7').data!.roomsCount,
        '6');
    expect(
        updated.units.firstWhere((unit) => unit.number == '3').data!.roomsCount,
        sourceData.roomsCount);
    expect(updated.units.first.data!.roomsCount, sourceData.roomsCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single copy can be cancelled and respects remaining capacity',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final source = UnitRecord.fromData(
        PropertyData.copyOf(newUnit('1').data!)..residentialCategory = 'عوائل');
    controller.properties.clear();
    controller.properties.add(managedPropertyRecord(
        buildingData()..totalUnits = '2', 'single-copy', [source]));
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('شقة 1 • شقة • 1'));
    await tester.tap(find.text('شقة 1 • شقة • 1'));
    await tester.pumpAndSettle();
    Future<void> openCopy() async {
      final copy = find.byKey(const ValueKey('copy-unit-1'));
      await tester.ensureVisible(copy);
      await tester.tap(
          find.descendant(of: copy, matching: find.byType(OutlinedButton)));
      await tester.pumpAndSettle();
    }

    await openCopy();
    await fill(tester, 'عدد الغرف', '8');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(controller.properties.single.units.length, 1);
    expect(source.data!.roomsCount, '3');
    await openCopy();
    await fill(tester, 'عدد النسخ', '2');
    tester.testTextInput.hide();
    await tester.tap(find.text('إضافة الوحدة'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.units.length, 1);
    expect(find.text('أدخل عددًا صحيحًا من 1 إلى 1'), findsOneWidget);
    await fill(tester, 'عدد النسخ', '1');
    await fill(tester, 'رقم الدور', '0');
    await fill(tester, 'ملاحظات على الوحدة', 'ملاحظة مستقلة للنسخة');
    tester.testTextInput.hide();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة الوحدة'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.units.map((unit) => unit.number),
        ['1', '2']);
    expect(controller.properties.single.units.last.floor, '0');
    expect(controller.properties.single.units.last.name, source.name);
    expect(controller.properties.single.units.last.data!.notes,
        'ملاحظة مستقلة للنسخة');
    expect(source.data!.notes, 'مدخل مستقل');
    final copy = find.byKey(const ValueKey('copy-unit-1'));
    expect(
        tester
            .widget<OutlinedButton>(find.descendant(
                of: copy, matching: find.byType(OutlinedButton)))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('90-unit building can correct floors while copying units',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final source = UnitRecord.fromData(PropertyData.copyOf(newUnit('1').data!)
      ..floor = '0'
      ..residentialCategory = 'عوائل');
    controller.properties.clear();
    controller.properties.add(managedPropertyRecord(
        buildingData()
          ..totalUnits = '90'
          ..floorsCount = '1',
        'ninety-unit-building',
        [source]));
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('شقة 1 • شقة • 0'));
    await tester.tap(find.text('شقة 1 • شقة • 0'));
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('copy-unit-1'));
    await tester.ensureVisible(copy);
    await tester
        .tap(find.descendant(of: copy, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await fill(tester, 'رقم الدور', '4');
    expect(find.text('العمارة مسجلة بدور أرضي فقط؛ صحح عدد أدوار العمارة'),
        findsOneWidget);
    expect(find.text('أدخل عددًا صحيحًا من 0 إلى 0'), findsNothing);
    await fill(tester, 'عدد أدوار العمارة', '٥');
    await fill(tester, 'عدد النسخ', '2');
    expect(controller.properties.single.floors, 1);
    final floors = field('رقم الدور');
    await tester.ensureVisible(floors.at(1));
    await tester.enterText(floors.at(1), '5');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.tap(find.text('إضافة 2 وحدات'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل عددًا صحيحًا من 0 إلى 4'), findsWidgets);
    expect(controller.properties.single.units.length, 1);
    await tester.ensureVisible(floors.at(1));
    await tester.enterText(floors.at(1), '2');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة 2 وحدات'));
    await tester.pumpAndSettle();
    final saved = controller.properties.single;
    expect(saved.floors, 5);
    expect(saved.data!.floorsCount, '5');
    expect(saved.totalUnits, 90);
    expect(saved.units.map((unit) => unit.floor), ['0', '4', '2']);
    expect(saved.units.map((unit) => unit.number), ['1', '2', '3']);
    expect(source.floor, '0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy is disabled when the building has reached its capacity',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.properties.clear();
    controller.properties.add(managedPropertyRecord(
        buildingData()..totalUnits = '1', 'full-building', [newUnit('1')]));
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار').first);
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('copy-unit-1'));
    expect(
        tester
            .widget<OutlinedButton>(find.descendant(
                of: copy, matching: find.byType(OutlinedButton)))
            .onPressed,
        isNull);
    expect(controller.properties.single.units.length, 1);
    expect(tester.takeException(), isNull);
  });

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
      expect(dropdowns.singleWhere((field) => field.label == 'الاستخدام').value,
          'سكني');
      for (final usage in ['سكني', 'تجاري', 'سكني تجاري', 'سكن جماعي']) {
        await choose(tester, 'الاستخدام', usage);
      }
      await choose(tester, 'طريقة تأجير العمارة', 'وحدات مستقلة');
      expect(find.text('بيانات الوحدة'), findsNothing);
      await fill(tester, 'رقم الوثيقة', '1234567890');
      await fill(tester, 'تاريخ الوثيقة', '2026/01/01');
      await fill(tester, 'اسم العقار', 'عمارة الاختبار');
      await fill(tester, 'الشارع', 'شارع الاختبار');
      await fill(tester, 'رقم المبنى', '1234');
      await fill(tester, 'الرقم الإضافي', '5678');
      await fill(tester, 'الرمز البريدي', '12345');
      await fill(tester, 'المنطقة', 'منطقة الرياض');
      await fill(tester, 'المدينة', 'الرياض');
      await fill(tester, 'الحي', 'النرجس');
      await fill(tester, 'عدد الأدوار', '3');
      await fill(tester, 'إجمالي الوحدات', '10');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ العقار'));
      await tester.pumpAndSettle();
      expect(controller.properties.single.units, isEmpty);
      expect(controller.properties.single.usage, 'سكن جماعي');
      expect(controller.properties.single.data!.propertyUsage, 'سكن جماعي');
      expect(
          controller.properties.single.data!.ownershipDocumentDate, isNotEmpty);
      expect(controller.properties.single.data!.cityReferenceId, isNotEmpty);
      expect(
          controller.properties.single.data!.districtReferenceId, isNotEmpty);
      expect(find.text('إضافة وحدات للعمارة'), findsOneWidget);
      await tester.tap(find.text('إضافة وحدات للعمارة'));
      await tester.pumpAndSettle();
      await fill(tester, 'عدد الوحدات المراد إضافتها', '5');
      await choose(tester, 'الفئة السكنية', 'عوائل');
      for (var i = 0; i < 5; i++) {
        final input = field('رقم الدور').at(i);
        await tester.ensureVisible(input);
        await tester.enterText(input, ['٠', '١', '۲', '1', '٢'][i]);
        await tester.pumpAndSettle();
      }
      await fill(tester, 'مساحة الوحدة (م²)', '135.5');
      await fill(tester, 'عدد الغرف', '4');
      await fill(tester, 'الصالات', '2');
      await fill(tester, 'دورات المياه', '3');
      for (final entry in {
        'المطبخ': '2',
        'المجلس': '3',
        'المخزن': '1',
        'مكيفات السبليت': '4'
      }.entries) {
        final counter = find.descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is UnitCountField && widget.label == entry.key),
            matching: find.byType(TextFormField));
        await tester.ensureVisible(counter);
        await tester.enterText(counter, entry.value);
        await tester.pumpAndSettle();
      }
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('المطبخ'));
      await tester.pumpAndSettle();
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
      expect(
          saved.units
              .every((unit) => unit.data!.residentialCategory == 'عوائل'),
          isTrue);
      expect(
          saved.units.map((u) => u.floor).toList(), ['0', '1', '2', '1', '2']);
      expect(saved.units.map((u) => u.number).toSet().length, 5);
      expect(
          saved.units.every((unit) =>
              unit.data!.kitchenCount == '2' &&
              unit.data!.majlisCount == '3' &&
              unit.data!.storageCount == '1' &&
              unit.data!.acSplitCount == '4'),
          isTrue);
      expect(
          saved.units.every((u) =>
              u.data!.roomsCount == '4' &&
              u.data!.bathroomsCount == '3' &&
              u.data!.area == '135.5'),
          isTrue);
      await tester.tap(find.text('شقة 1 • شقة • 0'));
      await tester.pumpAndSettle();
      expect(find.text('تفاصيل شقة 1'), findsOneWidget);
      expect(find.text('الفئة السكنية'), findsOneWidget);
      expect(find.text('عوائل'), findsOneWidget);
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
    expect(find.text('الفئة السكنية'), findsNothing);
    expect(
        tester
            .widgetList<AppDropdownField>(find.byType(AppDropdownField))
            .singleWhere((field) => field.label == 'الاستخدام')
            .value,
        'سكني');
    await choose(tester, 'الاستخدام', 'سكني تجاري');
    expect(find.text('منطقة الرياض'), findsOneWidget);
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('تاريخ الوثيقة'),
                matching: find.byType(EditableText)))
            .controller
            .text,
        data.ownershipDocumentDate);
    await fill(tester, 'عدد الغرف', '8');
    await fill(tester, 'رقم الدور', '١٢');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ العقار'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.managesUnits, isFalse);
    expect(controller.properties.single.usage, 'سكني تجاري');
    expect(controller.properties.single.data!.propertyUsage, 'سكني تجاري');
    expect(controller.properties.single.units.single.data!.roomsCount, '8');
    expect(controller.properties.single.data!.floor, '12');
    expect(controller.properties.single.units.single.floor, '12');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تعديل العقار'));
    await tester.tap(find.text('تعديل العقار'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('رقم الدور'), matching: find.byType(EditableText)))
            .controller
            .text,
        '12');
    expect(
        tester
            .widgetList<AppDropdownField>(find.byType(AppDropdownField))
            .singleWhere((field) => field.label == 'الاستخدام')
            .value,
        'سكني تجاري');
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

  for (final type in ContractType.values) {
    testWidgets('saved usage options match ${type.name} contracts',
        (tester) async {
      final controller = AppController();
      addTearDown(controller.dispose);
      controller.properties.clear();
      const usages = [
        'سكني',
        'تجاري',
        'سكني تجاري',
        'سكن جماعي',
        'سكن عوائل',
        'سكن أفراد'
      ];
      for (final usage in usages) {
        controller.properties.add(managedPropertyRecord(
            buildingData()
              ..buildingName = 'عقار $usage'
              ..propertyUsage = usage,
            'usage-${usages.indexOf(usage)}',
            []));
      }
      await mount(
          tester,
          controller,
          CreateContractScreen(
              initialDraft: ContractDraft()..type = type, initialStep: 3));
      final sources = tester
          .widgetList<AppDropdownField>(find.byType(AppDropdownField))
          .singleWhere((field) => field.label == 'مصدر العقار')
          .items;
      for (final usage in usages) {
        final expected = usage == 'سكني تجاري' ||
            (type == ContractType.commercial
                ? usage == 'تجاري'
                : usage != 'تجاري');
        expect(
            sources.any((label) => label.startsWith('عقار $usage -')), expected,
            reason: usage);
      }
      final mixed =
          sources.singleWhere((label) => label.startsWith('عقار سكني تجاري -'));
      await choose(tester, 'مصدر العقار', mixed);
      expect(
          tester
              .widgetList<AppDropdownField>(find.byType(AppDropdownField))
              .singleWhere((field) => field.label == 'استخدام العقار')
              .value,
          'سكني تجاري');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unit category is required, independent and cleared for commerce',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.properties.clear();
    final building = await controller.saveProperty(buildingData());
    await controller
        .saveProperty(building.data!, existing: building, unitEdits: [
      newUnit('1'),
      UnitRecord.fromData(PropertyData.copyOf(newUnit('2').data!)
        ..residentialCategory = 'عوائل')
    ]);
    await mount(tester, controller,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.text('عمارة الاختبار'));
    await tester.pumpAndSettle();
    Future<void> editFirst() async {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('شقة 1 • شقة • 1'));
      await tester.tap(find.text('شقة 1 • شقة • 1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('تعديل بيانات الوحدة'));
      await tester.tap(find.text('تعديل بيانات الوحدة'));
      await tester.pumpAndSettle();
    }

    await editFirst();
    await tester.tap(find.text('حفظ الوحدة'));
    await tester.pumpAndSettle();
    expect(find.text('اختر الفئة السكنية'), findsOneWidget);
    expect(controller.properties.single.units.first.data!.residentialCategory,
        isEmpty);
    await choose(tester, 'الفئة السكنية', 'أفراد');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الوحدة'));
    await tester.pumpAndSettle();
    expect(
        controller.properties.single.units
            .map((unit) => unit.data!.residentialCategory)
            .toList(),
        ['أفراد', 'عوائل']);
    await editFirst();
    expect(
        tester
            .widgetList<AppDropdownField>(find.byType(AppDropdownField))
            .singleWhere((field) => field.label == 'الفئة السكنية')
            .value,
        'أفراد');
    await choose(tester, 'نوع الوحدة', 'محل');
    expect(find.text('الفئة السكنية'), findsNothing);
    await tester.tap(find.text('حفظ الوحدة'));
    await tester.pumpAndSettle();
    expect(controller.properties.single.units.first.data!.residentialCategory,
        isEmpty);
    expect(controller.properties.single.units.last.data!.residentialCategory,
        'عوائل');
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
