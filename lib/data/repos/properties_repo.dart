// lib/data/repos/properties_repo.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_user_collections.dart';
import '../services/activity_log_service.dart';
import '../services/entity_audit_service.dart';
import '../../models/property.dart';

class PropertiesRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  PropertiesRepo(this.uc);

  Future<void> saveProperty(Property p) async {
    final ref = uc.properties.doc(p.id);
    final before = await ref.get();
    final oldData = before.data();
    final payload = _toRemote(p);
    payload.addAll(await EntityAuditService.instance.buildWriteAuditFields(
      isCreate: !before.exists,
      workspaceUid: uc.uid,
    ));
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: uc.uid,
      collectionName: 'properties',
      entityId: p.id,
      isCreate: !before.exists,
    );
    await ref.set(payload, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: before.exists ? 'update' : 'create',
      entityType: 'property',
      entityId: p.id,
      entityName: p.name,
      oldData: oldData == null ? null : _summaryFromMap(oldData),
      newData: _summaryFromProperty(p),
    ));
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

        final deleted =
            (m?['isDeleted'] == true) || ch.type == DocumentChangeType.removed;

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
    final ref = uc.properties.doc(id);
    final before = await ref.get();
    await ref.set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'property',
      entityId: id,
      entityName: (before.data()?['name'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{'isDeleted': true},
    ));
  }

  Future<void> deletePropertyHard(String id) async {
    final ref = uc.properties.doc(id);
    final before = await ref.get();
    await ref.delete();
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'property',
      entityId: id,
      entityName: (before.data()?['name'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{},
    ));
  }

  /* ===================== تحويلات ===================== */

  Map<String, dynamic> _toRemote(Property p) {
    String? enumName(Object? e) {
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
      'id': p.id,
      'name': p.name,
      'address': p.address,
      'type': enumName(p.type),
      'rentalMode': enumName(p.rentalMode), // قد تكون null لغير العمائر
      'totalUnits': p.totalUnits,
      'occupiedUnits': p.occupiedUnits,
      'parentBuildingId': p.parentBuildingId,
      // الحقول الاختيارية:
      'area': p.area,
      'floors': p.floors,
      'rooms': p.rooms,
      'price': p.price,
      'currency': p.currency,
      'description': p.description,
      'documentType': p.documentType,
      'documentNumber': p.documentNumber,
      'documentDate': p.documentDate?.millisecondsSinceEpoch,
      'documentAttachmentPath': p.documentAttachmentPath,
      'documentAttachmentPaths': p.documentAttachmentPaths,
      'electricityNumber': p.electricityNumber,
      'electricityMode': p.electricityMode,
      'electricityShare': p.electricityShare,
      'waterNumber': p.waterNumber,
      'waterMode': p.waterMode,
      'waterShare': p.waterShare,
      'waterAmount': p.waterAmount,
      // الحالة والمزامنة:
      'isArchived': p.isArchived == true,
      'createdAt': p.createdAt == null ? null : Timestamp.fromDate(p.createdAt!),
      'isDeleted': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
  }

  Property _fromRemote(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final name = (m['name'] ?? '').toString();
    final address = (m['address'] ?? '').toString();

    final typeStr = (m['type'] ?? '').toString();
    final modeStr = (m['rentalMode'] ?? '').toString();

    final type = _enumFromName<PropertyType>(typeStr);
    final mode = _enumFromName<RentalMode>(modeStr);

    final total = _toInt(m['totalUnits']) ?? 0;
    final occ = _toInt(m['occupiedUnits']) ?? 0;

    final parentRaw = m['parentBuildingId'];
    final parent = parentRaw?.toString();
    final parentId = (parent != null && parent.trim().isEmpty) ? null : parent;

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
      documentType: (m['documentType'] as String?),
      documentNumber: (m['documentNumber'] as String?),
      documentDate: _toDate(m['documentDate']),
      documentAttachmentPath: (m['documentAttachmentPath'] as String?),
      documentAttachmentPaths:
          (m['documentAttachmentPaths'] as List?)?.whereType<String>().toList(),
      electricityNumber: (m['electricityNumber'] as String?),
      electricityMode: (m['electricityMode'] as String?),
      electricityShare: (m['electricityShare'] as String?),
      waterNumber: (m['waterNumber'] as String?),
      waterMode: (m['waterMode'] as String?),
      waterShare: (m['waterShare'] as String?),
      waterAmount: (m['waterAmount'] as String?),
      createdAt: _toDate(m['createdAt']),
      updatedAt: _toDate(m['updatedAt']),
      isArchived: m['isArchived'] == true,
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

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final ms = int.tryParse(v);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  Map<String, dynamic> _summaryFromProperty(Property p) {
    return <String, dynamic>{
      'id': p.id,
      'name': p.name,
      'address': p.address,
      'type': p.type.name,
      'rentalMode': p.rentalMode?.name,
      'totalUnits': p.totalUnits,
      'occupiedUnits': p.occupiedUnits,
      'isArchived': p.isArchived,
      'createdAt': p.createdAt?.toIso8601String(),
      'updatedAt': p.updatedAt?.toIso8601String(),
      'isDeleted': false,
    };
  }

  Map<String, dynamic> _summaryFromMap(Map<String, dynamic> m) {
    return <String, dynamic>{
      'id': (m['id'] ?? '').toString(),
      'name': (m['name'] ?? '').toString(),
      'address': (m['address'] ?? '').toString(),
      'type': (m['type'] ?? '').toString(),
      'rentalMode': (m['rentalMode'] ?? '').toString(),
      'totalUnits': _toInt(m['totalUnits']),
      'occupiedUnits': _toInt(m['occupiedUnits']),
      'isArchived': m['isArchived'] == true,
      'createdAt': _toDate(m['createdAt'])?.toIso8601String(),
      'updatedAt': _toDate(m['updatedAt'])?.toIso8601String(),
      'isDeleted': m['isDeleted'] == true,
    };
  }
}
