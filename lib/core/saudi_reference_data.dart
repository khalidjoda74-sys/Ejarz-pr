import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SaudiCity {
  final int id;
  final int regionId;
  final String name;

  const SaudiCity({
    required this.id,
    required this.regionId,
    required this.name,
  });
}

class SaudiDistrict {
  final int id;
  final int cityId;
  final String name;

  const SaudiDistrict({
    required this.id,
    required this.cityId,
    required this.name,
  });
}

class SaudiReferenceCatalog {
  final List<SaudiCity> cities;
  final List<SaudiDistrict> districts;
  final Map<int, SaudiCity> _citiesById;
  final Map<int, List<SaudiDistrict>> _districtsByCity;

  SaudiReferenceCatalog._({
    required this.cities,
    required this.districts,
    required Map<int, SaudiCity> citiesById,
    required Map<int, List<SaudiDistrict>> districtsByCity,
  })  : _citiesById = citiesById,
        _districtsByCity = districtsByCity;

  static Future<SaudiReferenceCatalog>? _cachedCatalog;
  static SaudiReferenceCatalog? _loadedCatalog;

  static Future<SaudiReferenceCatalog> load() {
    final loaded = _loadedCatalog;
    if (loaded != null) return SynchronousFuture(loaded);
    return _cachedCatalog ??= _loadFromAssets();
  }

  static Future<SaudiReferenceCatalog> _loadFromAssets() async {
    final sources = await Future.wait(<Future<String>>[
      rootBundle.loadString('assets/data/saudi_cities.json'),
      rootBundle.loadString('assets/data/saudi_districts.json'),
    ]);
    final decoded = await compute(_decodeSaudiReferenceJson, sources);
    final cityRows = decoded['cities']!;
    final districtRows = decoded['districts']!;

    final cities = cityRows
        .map(
          (row) => SaudiCity(
            id: (row['city_id'] as num).toInt(),
            regionId: (row['region_id'] as num).toInt(),
            name: (row['name_ar'] as String).trim(),
          ),
        )
        .where((city) => city.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final districts = districtRows
        .map(
          (row) => SaudiDistrict(
            id: (row['district_id'] as num).toInt(),
            cityId: (row['city_id'] as num).toInt(),
            name: (row['name_ar'] as String).trim(),
          ),
        )
        .where((district) => district.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final citiesById = <int, SaudiCity>{
      for (final city in cities) city.id: city,
    };
    final districtsByCity = <int, List<SaudiDistrict>>{};
    for (final district in districts) {
      districtsByCity.putIfAbsent(district.cityId, () => <SaudiDistrict>[]);
      final cityDistricts = districtsByCity[district.cityId]!;
      if (!cityDistricts.any(
        (existing) =>
            normalizeSaudiLocation(existing.name) ==
            normalizeSaudiLocation(district.name),
      )) {
        cityDistricts.add(district);
      }
    }

    return _loadedCatalog = SaudiReferenceCatalog._(
      cities: List<SaudiCity>.unmodifiable(cities),
      districts: List<SaudiDistrict>.unmodifiable(districts),
      citiesById: citiesById,
      districtsByCity: {
        for (final entry in districtsByCity.entries)
          entry.key: List<SaudiDistrict>.unmodifiable(entry.value),
      },
    );
  }

  SaudiCity? cityById(int? id) => id == null ? null : _citiesById[id];

  List<SaudiDistrict> districtsForCity(int cityId) {
    return _districtsByCity[cityId] ?? const <SaudiDistrict>[];
  }

  SaudiCity? resolveCity(String cityName, {String districtName = ''}) {
    final cityKey = normalizeSaudiLocation(cityName);
    if (cityKey.isEmpty) return null;
    final matches = cities
        .where((city) => normalizeSaudiLocation(city.name) == cityKey)
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1 || districtName.trim().isEmpty) {
      return matches.first;
    }

    final districtKey = normalizeSaudiLocation(districtName);
    for (final city in matches) {
      if (districtsForCity(city.id).any(
        (district) => normalizeSaudiLocation(district.name) == districtKey,
      )) {
        return city;
      }
    }
    return matches.first;
  }
}

Map<String, List<Map<String, dynamic>>> _decodeSaudiReferenceJson(
  List<String> sources,
) {
  List<Map<String, dynamic>> decode(String source) {
    return (jsonDecode(source) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  return <String, List<Map<String, dynamic>>>{
    'cities': decode(sources[0]),
    'districts': decode(sources[1]),
  };
}

String normalizeSaudiLocation(String value) {
  var normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp(r'[\u0622\u0623\u0625]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ـ', '')
      .replaceAll(RegExp(r'[^\u0621-\u064A0-9a-z]+'), ' ')
      .trim();
  if (normalized.startsWith('حي ')) {
    normalized = normalized.substring(3).trim();
  }
  return normalized;
}

const Map<int, String> saudiRegionNames = <int, String>{
  1: 'منطقة الرياض',
  2: 'منطقة مكة المكرمة',
  3: 'منطقة المدينة المنورة',
  4: 'منطقة القصيم',
  5: 'المنطقة الشرقية',
  6: 'منطقة عسير',
  7: 'منطقة تبوك',
  8: 'منطقة حائل',
  9: 'منطقة الحدود الشمالية',
  10: 'منطقة جازان',
  11: 'منطقة نجران',
  12: 'منطقة الباحة',
  13: 'منطقة الجوف',
};

const List<String> saudiLicensedBanks = <String>[
  'البنك الأهلي السعودي',
  'مصرف الراجحي',
  'بنك الرياض',
  'البنك السعودي الأول',
  'البنك العربي الوطني',
  'مصرف الإنماء',
  'البنك السعودي الفرنسي',
  'البنك السعودي للاستثمار',
  'بنك الجزيرة',
  'بنك البلاد',
  'بنك الخليج الدولي - السعودية',
  'إس تي سي بنك',
  'بنك فيزيون',
  'بنك D360',
  'بنك الإمارات دبي الوطني',
  'بنك البحرين الوطني',
  'بنك الكويت الوطني',
  'بنك مسقط',
  'دويتشه بنك',
  'بنك بي إن بي باريبا',
  'جي بي مورغان تشيس',
  'بنك باكستان الوطني',
  'بنك زيراعات بانكاسي',
  'البنك الصناعي والتجاري الصيني',
  'بنك قطر الوطني',
  'بنك MUFG',
  'بنك أبوظبي الأول',
  'بنك UBS',
  'ستاندرد تشارترد',
  'البنك الوطني العراقي',
  'بنك الصين، المحدود',
  'بنك مصر',
  'البنك الأهلي المصري',
  'بنك صحار الدولي',
  'بنك الأردن',
  'بنك أبوظبي التجاري',
];
