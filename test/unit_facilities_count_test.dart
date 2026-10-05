import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/property_management.dart';
import 'package:aqdak/widgets/unit_count_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'property_management_pricing_test.dart' show buildingData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'legacy facilities become counts without losing explicit zero or multiple facilities',
      () {
    final legacy = FirebaseRepository.unitFromMap({
      'number': '1',
      'roomsCount': 3,
      'kitchen': true,
      'storage': false,
      'majlis': true,
    }).data!;
    expect(legacy.kitchenCount, '1');
    expect(legacy.storageCount, '0');
    expect(legacy.majlisCount, '1');
    final counted = FirebaseRepository.unitFromMap({
      'number': '2',
      'roomsCount': 3,
      'kitchen': true,
      'kitchenCount': 0,
      'storageCount': 2,
      'majlisCount': 3,
      'electricityMeter': '00012345678901234567',
    }).data!;
    expect(counted.kitchenCount, '0');
    expect(counted.kitchen, isFalse);
    expect(counted.storage, isTrue);
    expect(counted.majlisCount, '3');
    final copied = PropertyData.copyOf(counted);
    expect(copied.storageCount, '2');
    expect(copied.electricityMeter, '00012345678901234567');
  });

  test(
      'counts survive saved unit selection, contract copying, draft recovery and document serialization',
      () async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final building = await controller.saveProperty(buildingData());
    final data = PropertyData(
        unitNumber: '1',
        unitName: 'شقة 1',
        floor: '0',
        roomsCount: '3',
        kitchenCount: '2',
        storageCount: '3',
        majlisCount: '4',
        acWindowCount: '2',
        acSplitCount: '5',
        acCentralCount: '0',
        electricityMeter: '00012345',
        waterMeter: '',
        gasMeter: '00098765');
    final saved = await controller.saveProperty(building.data!,
        existing: building, unitEdits: [UnitRecord.fromData(data)]);
    final selected = saved.units.single.detailsFor(saved);
    expect(selected.kitchenCount, '2');
    final draft = ContractDraft()..property = selected;
    final restored = FirebaseRepository.draftFromMap(
        FirebaseRepository.draftToMap(ContractDraft.copyOf(draft)))!;
    expect(restored.property.storageCount, '3');
    expect(restored.property.majlisCount, '4');
    expect(restored.property.acSplitCount, '5');
    expect(restored.property.electricityMeter, '00012345');
    expect(restored.property.waterMeter, '');
    final units = FirebaseRepository.propertyDocumentData(
        propertyId: saved.id,
        uid: 'buyer',
        contractId: '',
        data: saved.data!,
        units: saved.units)['units'] as List;
    final recovered = FirebaseRepository.unitFromMap(
        Map<String, dynamic>.from(units.single as Map));
    expect(recovered.data!.kitchenCount, '2');
    expect(recovered.data!.storageCount, '3');
    expect(recovered.data!.gasMeter, '00098765');
  });

  test('meter identifiers preserve leading zeros and optional water and gas',
      () {
    expect(validateUnitMeterNumber('00012345678901234567', required: true),
        isNull);
    expect(validateUnitMeterNumber(''), isNull);
    expect(validateUnitMeterNumber('', required: true), isNotNull);
    for (final value in ['12x', '-1', '1.2', '0', '123456789012345678901']) {
      expect(validateUnitMeterNumber(value), isNotNull);
    }
  });

  testWidgets(
      'counter supports step buttons, numeric entry, validation and small RTL screens',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value = '0';
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl,
                child: StatefulBuilder(
                    builder: (context, setState) => Form(
                        key: key,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: UnitCountField(
                                label: 'المطبخ',
                                value: value,
                                icon: Icons.kitchen_outlined,
                                onChanged: (next) =>
                                    setState(() => value = next)))))))));
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'تقليل المطبخ'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('زيادة المطبخ'));
    await tester.pump();
    expect(value, '1');
    await tester.enterText(find.byType(TextFormField), '12');
    await tester.pump();
    await tester.tap(find.byTooltip('تقليل المطبخ'));
    await tester.pump();
    expect(value, '11');
    expect(key.currentState!.validate(), isTrue);
    await tester.enterText(find.byType(TextFormField), '99');
    await tester.pump();
    expect(key.currentState!.validate(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
