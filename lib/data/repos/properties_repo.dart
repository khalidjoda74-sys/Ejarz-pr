// lib/data/repos/properties_repo.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_user_collections.dart';
import '../../models/property.dart';

class PropertiesRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  PropertiesRepo(this.uc);

  Future<void> saveProperty(Property p) async {
    await uc.properties.doc(p.id).set(_toRemote(p), SetOptions(merge: true));
  }

  Future<Property?> getProperty(String id) async {
    final snap = await uc.properties.doc(id).get();
    if (!snap.exists) return null;
    final m = snap.data() ?? <String, dynamic>{};
    m.putIfAbsent('id', () => snap.id);
    return _fromRemote(m);
  }

  Future<List<Property>> listProperties() async {
    final q = await uc.properties.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) {
      final m = d.data();
      m.putIfAbsent('id', () => d.id);
      return _fromRemote(m);
    }).toList();
  }

  void startPropertiesListener({
    required void Function(Property p) onUpsert,
    required void Function(String id) onDelete,
  }) {
    _sub?.cancel();
    _sub = uc.properties.snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        final m = ch.doc.data();
        final id = ch.doc.id;

        final deleted = (m?['isDeleted'] == true) ||
            ch.type == DocumentChangeType.removed;

        if (deleted) {
          onDelete(id);
          continue;
        }

        final data = {...?m, 'id': id};
        onUpsert(_fromRemote(data));
      }
    });
  }

  void stopPropertiesListener() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> deletePropertySoft(String id) async {
    await uc.properties.doc(id).set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deletePropertyHard(String id) async {
    await uc.properties.doc(id).delete();
  }

  /* ===================== تحويلات ===================== */

  Map<String, dynamic> _toRemote(Property p) {
    String? _enumName(Object? e) {
      if (e == null) return null;
      try {
        final n = (e as dynamic).name;
        if (n is String && n.isNotEmpty) return n;
      } catch (_) {}
      final s = e.toString();
      return s.isEmpty ? null : s;
    }

    // أرسل كل الحقول (يشمل الاختيارية). لا نرسل null أو نصوصًا فارغة.
    return <String, dynamic>{
      'id'              : p.id,
      'name'            : p.name,
      'address'         : p.address,
      'type'            : _enumName(p.type),
      'rentalMode'      : _enumName(p.rentalMode), // قد تكون null لغير العمائر
      'totalUnits'      : p.totalUnits,
      'occupiedUnits'   : p.occupiedUnits,
      'parentBuildingId': p.parentBuildingId,
      // الحقول الاختيارية:
      'area'            : p.area,
      'floors'          : p.floors,
      'rooms'           : p.rooms,
      'price'           : p.price,
      'currency'        : p.currency,
      'description'     : p.description,
      // المزامنة:
      'isDeleted'       : false,
      'updatedAt'       : FieldValue.serverTimestamp(),
    }..removeWhere((k, v) =>
        v == null || (v is String && v.trim().isEmpty));
  }

  Property _fromRemote(Map<String, dynamic> m) {
    final id      = (m['id'] ?? '').toString();
    final name    = (m['name'] ?? '').toString();
    final address = (m['address'] ?? '').toString();

    final typeStr = (m['type'] ?? '').toString();
    final modeStr = (m['rentalMode'] ?? '').toString();

    final type = _enumFromName<PropertyType>(typeStr);
    final mode = _enumFromName<RentalMode>(modeStr);

    final total = _toInt(m['totalUnits']) ?? 0;
    final occ   = _toInt(m['occupiedUnits']) ?? 0;

    final parentRaw = m['parentBuildingId'];
    final parent    = parentRaw == null ? null : parentRaw.toString();
    final parentId  = (parent != null && parent.trim().isEmpty) ? null : parent;

    // نوع العقار مطلوب — وفّر fallback
    final safeType = type ?? PropertyType.values.first;

    return Property(
      id: id,
      name: name,
      address: address,
      type: safeType,
      // اترك rentalMode كما هو (قد يكون null لغير العمائر)
      rentalMode: mode,
      totalUnits: total,
      occupiedUnits: occ,
      parentBuildingId: parentId,
      // الحقول الاختيارية:
      area: _toDOrNull(m['area']),
      floors: _toInt(m['floors']),
      rooms: _toInt(m['rooms']),
      price: _toDOrNull(m['price']),
      currency: (m['currency'] as String?) ?? 'SAR',
      description: (m['description'] as String?),
    );
  }

  // مطابقة ديناميكية لأي Enum بواسطة الاسم (name أو جزء من toString)
  T? _enumFromName<T>(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final values = (T as dynamic).values as List<dynamic>;
      for (final v in values) {
        final name = (v as dynamic).name?.toString();
        if (name != null && name.toLowerCase() == s.toLowerCase()) {
          return v as T;
        }
        final ts = v.toString(); // "PropertyType.building"
        final last = ts.contains('.') ? ts.split('.').last : ts;
        if (last.toLowerCase() == s.toLowerCase()) return v as T;
      }
    } catch (_) {}
    return null;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _toDOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
