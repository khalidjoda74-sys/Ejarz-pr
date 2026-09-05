import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/firebase_repository.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:aqood_pro/core/property_management.dart';
import 'package:flutter_test/flutter_test.dart';

PropertyData buildingData() => PropertyData(
      rentalMode: 'units',
      buildingName: 'عمارة الاختبار',
      propertyType: 'عمارة',
      floorsCount: '3',
      totalUnits: '10',
      city: 'الرياض',
      district: 'النرجس',
      ownershipDocumentNumber: '1234567890',
      ownershipDocumentDate: '2026/01/01',
      street: 'شارع الاختبار',
      buildingNumber: '1234',
      additionalNumber: '5678',
      postalCode: '12345',
    );

UnitRecord newUnit(String number, {String rooms = '3'}) =>
    UnitRecord.fromData(PropertyData(
      unitNumber: number,
      unitName: 'شقة $number',
      floor: '1',
      area: '120.5',
      roomsCount: rooms,
      hallsCount: '2',
      bathroomsCount: '2',
      electricityMeter: '700$number',
      waterMeter: '800$number',
      gasMeter: '900$number',
      maidRoom: true,
      privateParking: true,
      storage: true,
      majlis: true,
      acCentral: true,
      furnishingStatus: 'مؤثثة بأثاث جديد',
      notes: 'مدخل مستقل',
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prices reflect contract type, all years and fractional duration', () {
    final draft = ContractDraft();
    expect(draft.totalPayable, 299);
    draft.durationYears = '2';
    expect(draft.totalPayable, 424);
    draft.durationYears = '3';
    expect(draft.totalPayable, 549);
    draft.type = ContractType.commercial;
    expect(draft.totalPayable, 1199);
    draft.durationYears = '1';
    expect(draft.totalPayable, 399);
    draft.durationMonths = '6';
    expect(draft.totalPayable, 599);
    draft.type = ContractType.residential;
    expect(draft.totalPayable, 361.5);
    draft.durationYears = '0';
    expect(draft.totalPayable, 299);
    draft.durationYears = '1';
    draft.durationMonths = '0';
    draft.durationDays = '1';
    expect(draft.totalPayable, 299.34);
    final restored =
        FirebaseRepository.draftFromMap(FirebaseRepository.draftToMap(draft))!;
    expect(restored.totalPayable, draft.totalPayable);
  });

  test('building capacity, normalized duplicate numbers and replacements', () {
    final existing = [newUnit('1')];
    expect(
        () => mergePropertyUnits(
            current: existing, additions: [newUnit('01')], capacity: 10),
        throwsStateError);
    expect(
        () => mergePropertyUnits(
            current: existing, additions: [newUnit('١')], capacity: 10),
        throwsStateError);
    expect(
        () => mergePropertyUnits(
            current: existing,
            additions: [newUnit('2'), newUnit('3')],
            capacity: 2),
        throwsStateError);
    final replaced = mergePropertyUnits(
        current: existing,
        additions: [newUnit('1', rooms: '5')],
        capacity: 10,
        replacingNumber: '1');
    expect(replaced.single.data!.roomsCount, '5');
    expect(existing.single.data!.roomsCount, '3');
  });

  test(
      'five units survive metadata edits and unit edits with complete serialization',
      () async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final building = await controller.saveProperty(buildingData());
    expect(building.units, isEmpty);
    final units = List.generate(5, (i) => newUnit('${i + 1}'));
    final saved = await controller.saveProperty(building.data!,
        existing: building, unitEdits: units);
    expect(saved.units.length, 5);
    expect(saved.remainingUnits, 5);
    final snapshot = saved.units[2].detailsFor(saved);
    final modified = PropertyData.copyOf(saved.data!)
      ..buildingName = 'الاسم المعدل';
    final renamed = await controller.saveProperty(modified, existing: saved);
    expect(renamed.units.length, 5);
    final edited = await controller.saveProperty(renamed.data!,
        existing: renamed,
        unitEdits: [newUnit('3', rooms: '4')],
        replacingNumber: '3');
    expect(
        edited.units.firstWhere((u) => u.number == '3').data!.roomsCount, '4');
    expect(edited.units.map((u) => u.number), ['1', '2', '3', '4', '5']);
    await expectLater(
        controller.saveProperty(
            PropertyData.copyOf(edited.data!)..rentalMode = 'whole',
            existing: edited),
        throwsStateError);
    await expectLater(
        controller.saveProperty(
            PropertyData.copyOf(edited.data!)..floorsCount = '1',
            existing: edited),
        throwsStateError);
    expect(controller.properties.single.units.length, 5);
    expect(snapshot.roomsCount, '3');
    expect(snapshot.buildingName, 'عمارة الاختبار');
    final payload = FirebaseRepository.propertyDocumentData(
        propertyId: edited.id,
        uid: 'test',
        contractId: '',
        data: edited.data!,
        units: edited.units);
    final restored = (payload['units'] as List)
        .map((u) =>
            FirebaseRepository.unitFromMap(Map<String, dynamic>.from(u as Map)))
        .toList();
    expect(restored.length, 5);
    expect(restored.first.data!.electricityMeter, '7001');
    expect(restored.first.data!.privateParking, isTrue);
    expect(restored.first.data!.notes, 'مدخل مستقل');
    expect(restored.first.data!.area, '120.5');
    expect(restored.first.data!.hallsCount, '2');
    expect(restored.first.data!.bathroomsCount, '2');
    expect(restored.first.detailsFor(edited).ownershipDocumentNumber,
        '1234567890');
  });

  test(
      'legacy unit details are preserved without copying them to unrelated units',
      () {
    final first = FirebaseRepository.unitFromMap(
        {'number': '1', 'name': 'الأولى', 'floor': '0'});
    final second = FirebaseRepository.unitFromMap(
        {'number': '2', 'name': 'الثانية', 'floor': '1'});
    final parent = managedPropertyRecord(
        buildingData()
          ..unitNumber = '1'
          ..roomsCount = '7',
        'LEGACY',
        [first, second]);
    expect(first.detailsFor(parent).roomsCount, '7');
    expect(first.detailsFor(parent).savedPropertyId, 'LEGACY');
    expect(first.detailsFor(parent).propertySource, 'عقار محفوظ');
    expect(second.detailsFor(parent).roomsCount, isEmpty);
  });

  test('demo payment and wallet keep the submitted commercial price', () async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final draft = ContractDraft()
      ..type = ContractType.commercial
      ..durationYears = '3';
    final contract = ContractRecord(
        id: 'TEST-PAY',
        requestNumber: 'REQ-TEST',
        type: draft.type,
        role: UserRole.lessor,
        title: 'تجاري ثلاث سنوات',
        property: 'الرياض',
        lessorName: 'مؤجر',
        tenantName: 'مستأجر',
        date: '2026/09/05',
        status: ContractStatus.awaitingPayment,
        totalFees: draft.totalPayable,
        timeline: const []);
    controller.contracts.add(contract);
    final result = await controller.submitDemoPayment(
        contract: contract,
        method: DemoPaymentMethod.mada,
        cardBrand: 'Mada',
        cardLast4: '1111',
        success: true);
    expect(result.success, isTrue);
    expect(controller.contracts.single.totalFees, 1199);
    expect(controller.transactions.single.amount, 1199);
  });
}
