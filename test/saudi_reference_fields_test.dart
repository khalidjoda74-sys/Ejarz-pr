import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/widgets/saudi_reference_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Saudi reference catalog is complete and linked', () async {
    final catalog = await SaudiReferenceCatalog.load();

    expect(catalog.cities, hasLength(15513));
    expect(catalog.districts, hasLength(21235));

    final riyadh = catalog.resolveCity(
      'الرياض',
      districtName: 'حي العمل',
    );
    expect(riyadh, isNotNull);
    expect(
      catalog.districtsForCity(riyadh!.id).map((item) => item.name),
      contains('العمل'),
    );
    expect(saudiLicensedBanks, contains('مصرف الراجحي'));
  });

  testWidgets('city selection filters districts and banks are searchable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var city = 'الرياض';
    var district = 'حي العمل';
    var bank = '';
    final catalog = await tester.runAsync(SaudiReferenceCatalog.load);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Form(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    SaudiLocationFields(
                      catalog: catalog,
                      city: city,
                      district: district,
                      onCityChanged: (value) => setState(() => city = value),
                      onDistrictChanged: (value) =>
                          setState(() => district = value),
                    ),
                    const SizedBox(height: 12),
                    SaudiBankField(
                      value: bank,
                      onChanged: (value) => setState(() => bank = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('الرياض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'جدة');
    await tester.pump();
    final jeddahResult = find.widgetWithText(ListTile, 'جدة');
    await tester.ensureVisible(jeddahResult);
    await tester.pump();
    await tester.tap(jeddahResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(city, 'جدة');
    expect(district, isEmpty);

    await tester.tap(find.text('اختر الحي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'الزمرد');
    await tester.pump();
    final districtResult = find.widgetWithText(ListTile, 'الزمرد');
    await tester.ensureVisible(districtResult);
    await tester.pump();
    await tester.tap(districtResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(district, 'الزمرد');

    await tester.tap(find.text('اختر البنك'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'الراجحي');
    await tester.pump();
    final bankResult = find.widgetWithText(ListTile, 'مصرف الراجحي');
    await tester.ensureVisible(bankResult);
    await tester.pump();
    await tester.tap(bankResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bank, 'مصرف الراجحي');
  });

  testWidgets(
      'region is inferred on edit and cascades city district and reference ids',
      (tester) async {
    final catalog = (await tester.runAsync(SaudiReferenceCatalog.load))!;
    var city = 'الرياض', district = 'النرجس';
    final riyadh = catalog.resolveCity(city, districtName: district)!;
    var cityId = riyadh.referenceId;
    var districtId = catalog
        .districtsForCity(riyadh.id)
        .firstWhere((d) => d.name == district)
        .referenceId;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Form(
                    key: form,
                    child: SaudiLocationFields(
                      showRegionSelector: true,
                      catalog: catalog,
                      city: city,
                      district: district,
                      cityReferenceId: cityId,
                      districtReferenceId: districtId,
                      onCityChanged: (v) => setState(() => city = v),
                      onDistrictChanged: (v) => setState(() => district = v),
                      onReferencesChanged: (c, d) {
                        cityId = c;
                        districtId = d;
                      },
                    ))))));
    await tester.pumpAndSettle();
    expect(find.text('منطقة الرياض'), findsOneWidget);
    expect(form.currentState!.validate(), isTrue);
    await tester.tap(find.text('منطقة الرياض'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'منطقة مكة المكرمة'));
    await tester.pumpAndSettle();
    expect([city, district, cityId, districtId], ['', '', '', '']);
    expect(form.currentState!.validate(), isFalse);
    await tester.tap(find.text('اختر المدينة'));
    await tester.pumpAndSettle();
    expect(find.text('منطقة الرياض'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'جدة');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'جدة').first);
    await tester.pumpAndSettle();
    expect(city, 'جدة');
    expect(
        catalog.cities.firstWhere((c) => c.referenceId == cityId).regionId, 2);
    expect(district, isEmpty);
    await tester.tap(find.text('اختر الحي'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'الزمرد');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'الزمرد').first);
    await tester.pumpAndSettle();
    expect(district, 'الزمرد');
    expect(districtId, isNotEmpty);
    expect(form.currentState!.validate(), isTrue);
    await tester.tap(find.text('منطقة مكة المكرمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'منطقة مكة المكرمة'));
    await tester.pumpAndSettle();
    expect([city, district], ['جدة', 'الزمرد']);
    expect(tester.takeException(), isNull);
  });
}
