import 'dart:async';
import 'dart:convert';
import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:aqdak/widgets/saudi_reference_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const city =
      SaudiCity(id: 1, regionId: 1, name: 'الرياض', referenceId: 'municipal_1');
  Map<String, dynamic> row(String name) => {
        'id': 7,
        'cityId': 1,
        'name': name,
        'key': 'municipal_7',
        'enabled': true
      };

  test('published seed keeps all bundled districts available without network',
      () async {
    final bundled = await SaudiReferenceCatalog.load();
    final manifest = jsonDecode(await rootBundle
        .loadString('assets/data/saudi_catalog_manifest.json')) as Map;
    final catalog = SaudiReferenceCatalog.published(
        cities: bundled.cities,
        version: 'municipal_${(manifest['commit'] as String).substring(0, 16)}',
        chunkLoader: (_, __) => throw StateError('network unavailable'));
    var count = 0;
    for (final city in catalog.cities) {
      count += (await catalog.fetchDistricts(city.id)).length;
    }
    expect(count, 21235);
    final riyadh = catalog.resolveCity('الرياض', districtName: 'حي العمل')!;
    expect((await catalog.fetchDistricts(riyadh.id)).map((d) => d.name),
        contains('العمل'));
  });

  test('concurrent versions never share pending loads or loaded buckets',
      () async {
    final first = Completer<List<Map<String, dynamic>>>();
    final second = Completer<List<Map<String, dynamic>>>();
    final a = SaudiReferenceCatalog.published(
        cities: [city], version: 'first', chunkLoader: (_, __) => first.future);
    final b = SaudiReferenceCatalog.published(
        cities: [city],
        version: 'second',
        chunkLoader: (_, __) => second.future);
    final oldLoad = a.fetchDistricts(1), newLoad = b.fetchDistricts(1);
    second.complete([row('الحي الجديد')]);
    expect((await newLoad).single.name, 'الحي الجديد');
    first.complete([row('الحي القديم')]);
    expect((await oldLoad).single.name, 'الحي القديم');
    expect(b.districtsForCity(1).single.name, 'الحي الجديد');
  });

  test('retry recovers failed load and newer versions do not use seed rows',
      () async {
    var calls = 0;
    final catalog = SaudiReferenceCatalog.published(
        cities: [city],
        version: 'updated',
        chunkLoader: (_, __) async {
          if (++calls == 1) throw StateError('offline');
          return [row('حي معتمد جديد')];
        });
    await expectLater(catalog.fetchDistricts(1), throwsStateError);
    expect((await catalog.fetchDistricts(1)).single.name, 'حي معتمد جديد');
    expect(calls, 2);
  });

  testWidgets(
      'failed district load is never displayed as no approved districts',
      (tester) async {
    final catalog = SaudiReferenceCatalog.published(
        cities: [city],
        version: 'broken',
        chunkLoader: (_, __) async => throw StateError('offline'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SaudiLocationFields(
                catalog: catalog,
                city: city.name,
                district: '',
                onCityChanged: (_) {},
                onDistrictChanged: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل الأحياء'), findsOneWidget);
    expect(find.text('لا توجد أحياء معتمدة'), findsNothing);
    expect(find.text('طلب استكمال الأحياء'), findsNothing);
    expect(find.text('إعادة تحميل المدن والأحياء'), findsOneWidget);
  });
}
