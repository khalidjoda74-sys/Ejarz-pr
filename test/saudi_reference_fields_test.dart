import 'package:aqood_pro/core/saudi_reference_data.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/widgets/saudi_reference_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Saudi reference catalog is complete and linked', () async {
    final catalog = await SaudiReferenceCatalog.load();

    expect(catalog.cities, hasLength(4581));
    expect(catalog.districts, hasLength(3732));

    final riyadh = catalog.resolveCity(
      'الرياض',
      districtName: 'حي العمل',
    );
    expect(riyadh, isNotNull);
    expect(
      catalog.districtsForCity(riyadh!.id).map((item) => item.name),
      contains('حي العمل'),
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
    final districtResult = find.widgetWithText(ListTile, 'حي الزمرد');
    await tester.ensureVisible(districtResult);
    await tester.pump();
    await tester.tap(districtResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(district, 'حي الزمرد');

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
}
