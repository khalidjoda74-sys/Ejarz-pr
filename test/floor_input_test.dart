import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/property_management.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/screens/wallet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'building_units_flow_test.dart' show mount, field, fill;
import 'contract_complete_flow_test.dart' show completeDraft, activeDraft, next;
import 'property_management_pricing_test.dart' show buildingData;

EditableText floorInput(WidgetTester tester) => tester.widget<EditableText>(find
    .descendant(of: field('رقم الدور'), matching: find.byType(EditableText)));

Future<void> tapLabel(WidgetTester tester, String label) async {
  tester.testTextInput.hide();
  // Allow the previous save confirmation to leave the bottom action area.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> checkDigitEntry(WidgetTester tester) async {
  expect(floorInput(tester).keyboardType, TextInputType.number);
  for (final value in ['12', '١٢', '۱۲']) {
    await fill(tester, 'رقم الدور', value);
    expect(floorInput(tester).controller.text, '12');
    expect(tester.state<FormFieldState<String>>(field('رقم الدور')).errorText,
        isNull);
  }
  // Editing in the middle must retain the caret and all digits.
  tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '1٠2', selection: TextSelection.collapsed(offset: 2)));
  await tester.pumpAndSettle();
  expect(floorInput(tester).controller.text, '102');
  expect(floorInput(tester).controller.selection.baseOffset, 2);
  await fill(tester, 'رقم الدور', '');
  expect(floorInput(tester).controller.text, isEmpty);
  tester.state<FormFieldState<String>>(field('رقم الدور')).validate();
  await tester.pumpAndSettle();
  expect(tester.state<FormFieldState<String>>(field('رقم الدور')).errorText,
      isNotNull);
  await fill(tester, 'رقم الدور', '١٢');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  testWidgets('new property accepts Arabic, Persian and English floor digits',
      (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    await mount(
        tester, app, PropertiesScreen(onMenu: () {}, onNotifications: () {}));
    await tester.tap(find.byTooltip('إضافة عقار'));
    await tester.pumpAndSettle();
    await checkDigitEntry(tester);
    expect(tester.takeException(), isNull);
  });

  for (final commercial in [false, true]) {
    testWidgets(
        'contract floor survives next and back (commercial=$commercial)',
        (tester) async {
      final app = AppController();
      addTearDown(app.dispose);
      await mount(
          tester,
          app,
          CreateContractScreen(
              initialDraft: completeDraft(commercial: commercial),
              initialStep: 3));
      await checkDigitEntry(tester);
      expect(activeDraft(tester).property.floor, '12');
      await next(tester);
      await tapLabel(tester, 'السابق');
      expect(floorInput(tester).controller.text, '12');
      expect(activeDraft(tester).property.floor, '12');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (floors, arabic, persian) in [
    (1, '٠', '۰'),
    (3, '٢', '۲'),
    (13, '١٢', '۱۲')
  ]) {
    testWidgets(
        'unit accepts digit forms, enforces $floors floors, saves and reopens',
        (tester) async {
      final app = AppController();
      addTearDown(app.dispose);
      await app.saveProperty(buildingData()..floorsCount = '$floors');
      await mount(
          tester, app, PropertiesScreen(onMenu: () {}, onNotifications: () {}));
      await tapLabel(tester, 'عمارة الاختبار');
      await tapLabel(tester, 'إضافة وحدات للعمارة');
      expect(floorInput(tester).keyboardType, TextInputType.number);
      for (final value in ['${floors - 1}', arabic, persian]) {
        await fill(tester, 'رقم الدور', value);
        expect(floorInput(tester).controller.text, '${floors - 1}');
        expect(
            tester.state<FormFieldState<String>>(field('رقم الدور')).errorText,
            isNull);
      }
      for (final invalid in ['', '-1', '1.5', '$floors', 'دور']) {
        await fill(tester, 'رقم الدور', invalid);
        expect(
            tester.state<FormFieldState<String>>(field('رقم الدور')).errorText,
            isNotNull);
      }
      await fill(tester, 'رقم الدور', arabic);
      await fill(tester, 'مساحة الوحدة (م²)', '120');
      await fill(tester, 'عدد الغرف', '3');
      await fill(tester, 'الصالات', '1');
      await fill(tester, 'دورات المياه', '2');
      await tapLabel(tester, 'إضافة الوحدة');
      expect(app.properties.single.units.single.floor, '${floors - 1}');
      expect(app.properties.single.units.single.data!.floor, '${floors - 1}');
      await tapLabel(tester, 'شقة 1 • شقة • ${floors - 1}');
      await tapLabel(tester, 'تعديل بيانات الوحدة');
      expect(floorInput(tester).controller.text, '${floors - 1}');
      await fill(tester, 'رقم الدور', '٠');
      await tapLabel(tester, 'حفظ الوحدة');
      expect(app.properties.single.units.single.floor, '0');
      expect(tester.takeException(), isNull);
    });
  }

  test(
      'floor bounds cover stored Arabic and Persian digits when resizing building',
      () {
    for (final floor in ['2', '٢', '۲']) {
      final unit = UnitRecord.fromData(PropertyData(floor: floor));
      expect(
          managedPropertyRecord(buildingData()..floorsCount = '٣', 'qa', [unit])
              .floors,
          3);
      expect(
          () => managedPropertyRecord(
              buildingData()..floorsCount = '٢', 'qa', [unit]),
          throwsStateError);
    }
  });
}
