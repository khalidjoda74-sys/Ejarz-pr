import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_bootstrap.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SaudiCity {
  final int id;
  final int regionId;
  final String name;
  final String referenceId;

  const SaudiCity({
    required this.id,
    required this.regionId,
    required this.name,
    this.referenceId = '',
  });
}

class SaudiDistrict {
  final int id;
  final int cityId;
  final String name;
  final String referenceId;

  const SaudiDistrict({
    required this.id,
    required this.cityId,
    required this.name,
    this.referenceId = '',
  });
}

class SaudiReferenceCatalog {
  final List<SaudiCity> cities;
  final List<SaudiDistrict> districts;
  final Map<int, SaudiCity> _citiesById;
  final Map<int, List<SaudiDistrict>> _districtsByCity;
  final String _remoteVersion;
  final Future<List<Map<String, dynamic>>> Function(String, int)? _chunkLoader;
  final Set<int> _loadedBuckets = {};
  final Map<int, Future<List<SaudiDistrict>>> _pendingBuckets = {};

  SaudiReferenceCatalog._({
    required this.cities,
    required this.districts,
    required Map<int, SaudiCity> citiesById,
    required Map<int, List<SaudiDistrict>> districtsByCity,
    String remoteVersion = '',
    Future<List<Map<String, dynamic>>> Function(String, int)? chunkLoader,
  })  : _citiesById = citiesById,
        _remoteVersion = remoteVersion,
        _chunkLoader = chunkLoader,
        _districtsByCity = districtsByCity;

  static Future<SaudiReferenceCatalog>? _cachedCatalog;
  static SaudiReferenceCatalog? _loadedCatalog;
  static SaudiReferenceCatalog? _bundledCatalog;
  static String _bundledVersion = '';
  static final changes = ValueNotifier<SaudiReferenceCatalog?>(null);
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _subscription;
  static String _version = '';
  static Future<void>? _liveLoad;
  static int _loadGeneration = 0;

  static void connect() {
    if (!FirebaseBootstrap.initialized || _subscription != null) return;
    _subscription = FirebaseFirestore.instance
        .doc('geography/current')
        .snapshots()
        .listen((snapshot) {
      final meta = snapshot.data();
      if (meta == null || meta['version'] == _version) return;
      _liveLoad = _loadLive(meta).catchError((Object error) {
        debugPrint('Geography uses last complete catalog: $error');
      });
    }, onError: (Object error) {
      debugPrint('Geography update unavailable: $error');
    });
  }

  static Future<void> _loadLive(Map<String, dynamic> meta) async {
    final generation = ++_loadGeneration;
    final version = meta['version'] as String;
    final docs = await Future.wait((meta['cityChunks'] as List).map((key) =>
        FirebaseFirestore.instance
            .doc('geographyVersions/$version/chunks/$key')
            .get())).timeout(const Duration(seconds: 12));
    if (docs.any((doc) => !doc.exists)) {
      throw StateError('Incomplete city catalog');
    }
    if (generation != _loadGeneration) return;
    final rows = docs
        .expand((doc) => (doc.data()!['rows'] as List))
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final active = rows.where((row) => row['enabled'] != false).toList();
    final cities = active
        .map((r) => SaudiCity(
            id: (r['id'] as num).toInt(),
            regionId: (r['regionId'] as num).toInt(),
            name: r['name'] as String,
            referenceId: r['key'] as String))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _version = version;
    final catalog =
        SaudiReferenceCatalog.published(cities: cities, version: version);
    _loadedCatalog = catalog;
    changes.value = catalog;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saudi_geography_cities',
        jsonEncode({'version': version, 'rows': rows}));
  }

  static Future<SaudiReferenceCatalog> current({bool refresh = false}) async {
    await load();
    if (FirebaseBootstrap.initialized && _version.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('saudi_geography_cities');
        if (cached != null && _version.isEmpty) {
          final value = jsonDecode(cached) as Map<String, dynamic>;
          final rows = (value['rows'] as List).cast<Map<String, dynamic>>();
          final cities = rows
              .where((r) => r['enabled'] != false)
              .map((r) => SaudiCity(
                  id: (r['id'] as num).toInt(),
                  regionId: (r['regionId'] as num).toInt(),
                  name: r['name'] as String,
                  referenceId: r['key'] as String))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _version = value['version'] as String;
          _loadedCatalog = SaudiReferenceCatalog.published(
              cities: cities, version: _version);
        }
      } catch (_) {/* Bundled reference remains available. */}
    }
    connect();
    if (refresh && FirebaseBootstrap.initialized) {
      final meta = (await FirebaseFirestore.instance
              .doc('geography/current')
              .get()
              .timeout(const Duration(seconds: 12)))
          .data();
      if (meta != null) _liveLoad = _loadLive(meta);
    }
    if (_liveLoad != null) await _liveLoad;
    return _loadedCatalog!;
  }

  Future<List<SaudiDistrict>> fetchDistricts(int cityId) async {
    if (_remoteVersion.isEmpty) return districtsForCity(cityId);
    final key = cityId % 128;
    final pending = _pendingBuckets[key];
    if (pending != null) {
      await pending;
      return districtsForCity(cityId);
    }
    final task = _fetchDistricts(cityId);
    _pendingBuckets[key] = task;
    try {
      return await task;
    } finally {
      _pendingBuckets.remove(key);
    }
  }

  Future<List<SaudiDistrict>> _fetchDistricts(int cityId) async {
    if (_remoteVersion.isEmpty) return districtsForCity(cityId);
    final bucket = cityId % 128, version = _remoteVersion;
    if (!_loadedBuckets.contains(bucket)) {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'saudi_geography_${version}_$bucket';
      List<dynamic>? rows;
      try {
        if (_chunkLoader != null) {
          rows = await _chunkLoader(version, bucket);
        } else {
          final doc = await FirebaseFirestore.instance
              .doc('geographyVersions/$version/chunks/districts_$bucket')
              .get()
              .timeout(const Duration(seconds: 12));
          if (!doc.exists) throw StateError('Incomplete district catalog');
          rows = doc.data()!['rows'] as List;
        }
        await prefs.setString(cacheKey, jsonEncode(rows));
      } catch (_) {
        final cached = prefs.getString(cacheKey);
        if (cached != null) rows = jsonDecode(cached) as List;
        if (rows == null) rethrow;
      }
      final grouped = <int, List<SaudiDistrict>>{};
      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw as Map);
        if (r['enabled'] == false) continue;
        final parent = (r['cityId'] as num).toInt();
        grouped.putIfAbsent(parent, () => []).add(SaudiDistrict(
            id: (r['id'] as num).toInt(),
            cityId: parent,
            name: r['name'] as String,
            referenceId: r['key'] as String));
      }
      for (final list in grouped.values) {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
      _districtsByCity.addAll(grouped);
      _loadedBuckets.add(bucket);
    }
    return districtsForCity(cityId);
  }

  static Future<SaudiReferenceCatalog> load() {
    final loaded = _loadedCatalog;
    if (loaded != null) return SynchronousFuture(loaded);
    return _cachedCatalog ??= _loadFromAssets();
  }

  static Future<SaudiReferenceCatalog> _loadFromAssets() async {
    final sources = await Future.wait(<Future<String>>[
      rootBundle.loadString('assets/data/saudi_cities.json'),
      rootBundle.loadString('assets/data/saudi_districts.json'),
      rootBundle.loadString('assets/data/saudi_catalog_manifest.json'),
    ]);
    final manifest = jsonDecode(sources[2]) as Map<String, dynamic>;
    _bundledVersion =
        'municipal_${(manifest['commit'] as String).substring(0, 16)}';
    final decoded =
        await compute(_decodeSaudiReferenceJson, sources.take(2).toList());
    final cityRows = decoded['cities']!;
    final districtRows = decoded['districts']!;

    final cities = cityRows
        .map(
          (row) => SaudiCity(
            id: (row['city_id'] as num).toInt(),
            regionId: (row['region_id'] as num).toInt(),
            name: (row['name_ar'] as String).trim(),
            referenceId: 'municipal_${row['city_id']}',
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
            referenceId: 'municipal_${row['district_id']}',
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
      cityDistricts.add(district);
    }

    final catalog = SaudiReferenceCatalog._(
      cities: List<SaudiCity>.unmodifiable(cities),
      districts: List<SaudiDistrict>.unmodifiable(districts),
      citiesById: citiesById,
      districtsByCity: {
        for (final entry in districtsByCity.entries)
          entry.key: List<SaudiDistrict>.unmodifiable(entry.value),
      },
    );
    _bundledCatalog = catalog;
    _loadedCatalog ??= catalog;
    return _loadedCatalog!;
  }

  factory SaudiReferenceCatalog.published({
    required List<SaudiCity> cities,
    required String version,
    Future<List<Map<String, dynamic>>> Function(String, int)? chunkLoader,
  }) {
    // Published versions are immutable. The bundled reference can only satisfy
    // the exact seeded version; later administrative changes still load remotely.
    final bundled = version == _bundledVersion ? _bundledCatalog : null;
    final catalog = SaudiReferenceCatalog._(
      cities: cities,
      districts: bundled?.districts ?? const [],
      citiesById: {for (final c in cities) c.id: c},
      districtsByCity: bundled == null ? {} : Map.of(bundled._districtsByCity),
      remoteVersion: version,
      chunkLoader: chunkLoader,
    );
    if (bundled != null) {
      catalog._loadedBuckets.addAll(List.generate(128, (i) => i));
    }
    return catalog;
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
    if (matches.length == 1) {
      return matches.first;
    }

    final districtKey = normalizeSaudiLocation(districtName);
    final districtMatches = matches
        .where((city) => districtsForCity(city.id).any(
              (district) =>
                  normalizeSaudiLocation(district.name) == districtKey,
            ))
        .toList();
    return districtMatches.length == 1 ? districtMatches.first : null;
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
