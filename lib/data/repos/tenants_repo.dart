import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
import '../services/activity_log_service.dart';
import '../services/entity_audit_service.dart';
import '../../models/tenant.dart';

class TenantsRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  TenantsRepo(this.uc);

  /* ===================== حفظ / تحديث ===================== */
  Future<void> saveTenant(Tenant t) async {
    final ref = uc.tenants.doc(t.id);
    final before = await ref.get();
    final oldData = before.data();
    final payload = _toRemote(t);
    payload.addAll(await EntityAuditService.instance.buildWriteAuditFields(
      isCreate: !before.exists,
      workspaceUid: uc.uid,
    ));
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: uc.uid,
      collectionName: 'tenants',
      entityId: t.id,
      isCreate: !before.exists,
    );
    await ref.set(payload, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: before.exists ? 'update' : 'create',
      entityType: 'tenant',
      entityId: t.id,
      entityName: t.fullName,
      oldData: oldData == null ? null : _summaryFromMap(oldData),
      newData: _summaryFromTenant(t),
    ));
  }

  /* ===================== قراءة عنصر ===================== */
  Future<Tenant?> getTenant(String id) async {
    final snap = await uc.tenants.doc(id).get();
    if (!snap.exists) return null;
    final m = snap.data() ?? <String, dynamic>{};
    m.putIfAbsent('id', () => snap.id);
    return _fromRemote(m);
  }

  /* ===================== قراءة قائمة ===================== */
  Future<List<Tenant>> listTenants() async {
    final q = await uc.tenants.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) {
      final m = d.data();
      m.putIfAbsent('id', () => d.id);
      return _fromRemote(m);
    }).toList();
  }

  /* ===================== استماع لحظي ===================== */
  void startTenantsListener({
    required void Function(Tenant t) onUpsert,
    required void Function(String id) onDelete,
  }) {
    _sub?.cancel();
    _sub = uc.tenants.snapshots().listen((snap) {
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

  void stopTenantsListener() {
    _sub?.cancel();
    _sub = null;
  }

  /* ===================== حذف ===================== */
  Future<void> deleteTenantSoft(String id) async {
    final ref = uc.tenants.doc(id);
    final before = await ref.get();
    await ref.set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'tenant',
      entityId: id,
      entityName: (before.data()?['fullName'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{'isDeleted': true},
    ));
  }

  Future<void> deleteTenantHard(String id) async {
    final ref = uc.tenants.doc(id);
    final before = await ref.get();
    await ref.delete();
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'tenant',
      entityId: id,
      entityName: (before.data()?['fullName'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{},
    ));
  }

  /* ===================== تحويلات ===================== */

  String _normalizeClientType(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return 'tenant';
    if (v == 'tenant' || v == 'مستأجر') return 'tenant';
    if (v == 'company' || v == 'شركة' || v == 'مستأجر (شركة)') return 'company';
    if (v == 'serviceprovider' ||
        v == 'service_provider' ||
        v == 'service provider' ||
        v == 'مقدم خدمة') {
      return 'serviceProvider';
    }
    return 'tenant';
  }


  DateTime? _toDateValue(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
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

  Map<String, dynamic> _toRemote(Tenant t) {
    // مساعد يضع قيمة/يحذف المفتاح إذا null
    void putOpt(Map<String, dynamic> map, String key, String? val) {
      final v = val?.trim();
      if (v == null) {
        map[key] = FieldValue.delete();
      } else {
        map[key] = v;
      }
    }

    final map = <String, dynamic>{
      // إلزامية / أساسية (نستخدم trim حيث يناسب)
      'id': t.id,
      'fullName': t.fullName.trim(),
      'nationalId': t.nationalId.trim(),
      'phone': t.phone.trim(),

      'isArchived': t.isArchived,
      'isBlacklisted': t.isBlacklisted,
      'activeContractsCount': t.activeContractsCount,

      // مهم لتصحيح أي حالة سابقة
      'isDeleted': false,

      // createdAt: لو null خليه من السيرفر، وإلا استعمل الموجود
      'createdAt': Timestamp.fromDate(t.createdAt),

      // updatedAt: دائمًا من السيرفر (الحسم يكون بالـ server time)
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // الإختياريات النصية — نحذف المفتاح إذا null بدل تجاهله
    putOpt(map, 'email', t.email);
    putOpt(map, 'nationality', t.nationality);
    putOpt(map, 'addressLine', t.addressLine);
    putOpt(map, 'city', t.city);
    putOpt(map, 'region', t.region);
    putOpt(map, 'postalCode', t.postalCode);
    putOpt(map, 'emergencyName', t.emergencyName);
    putOpt(map, 'emergencyPhone', t.emergencyPhone);
    putOpt(map, 'notes', t.notes);
    putOpt(map, 'blacklistReason', t.blacklistReason);
    putOpt(map, 'clientType', _normalizeClientType(t.clientType));
    putOpt(map, 'tenantBankName', t.tenantBankName);
    putOpt(map, 'tenantBankAccountNumber', t.tenantBankAccountNumber);
    putOpt(map, 'tenantTaxNumber', t.tenantTaxNumber);
    putOpt(map, 'companyName', t.companyName);
    putOpt(map, 'companyCommercialRegister', t.companyCommercialRegister);
    putOpt(map, 'companyTaxNumber', t.companyTaxNumber);
    putOpt(map, 'companyRepresentativeName', t.companyRepresentativeName);
    putOpt(map, 'companyRepresentativePhone', t.companyRepresentativePhone);
    putOpt(map, 'companyBankAccountNumber', t.companyBankAccountNumber);
    putOpt(map, 'companyBankName', t.companyBankName);
    putOpt(map, 'serviceSpecialization', t.serviceSpecialization);
    map['tags'] = t.tags;
    map['attachmentPaths'] = t.attachmentPaths;

    // تاريخ الميلاد وتاريخ انتهاء الهوية: Timestamp أو حذف الحقل
    if (t.dateOfBirth == null) {
      map['dateOfBirth'] = FieldValue.delete();
    } else {
      map['dateOfBirth'] = Timestamp.fromDate(KsaTime.dateOnly(t.dateOfBirth!));
    }

    if (t.idExpiry == null) {
      map['idExpiry'] = FieldValue.delete();
    } else {
      map['idExpiry'] = Timestamp.fromDate(KsaTime.dateOnly(t.idExpiry!));
    }

    return map;
  }

  Tenant _fromRemote(Map<String, dynamic> m) {
    DateTime? tsToDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
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

    return Tenant(
      id: (m['id'] ?? '').toString(),
      fullName: (m['fullName'] ?? '').toString(),
      nationalId: (m['nationalId'] ?? '').toString(),
      phone: ((m['phone'] ?? '') as Object).toString(),
      email: (m['email'] as String?)?.trim(),
      dateOfBirth: tsToDate(m['dateOfBirth']),
      nationality: (m['nationality'] as String?)?.trim(),
      idExpiry: tsToDate(m['idExpiry']),
      addressLine: (m['addressLine'] as String?)?.trim(),
      city: (m['city'] as String?)?.trim(),
      region: (m['region'] as String?)?.trim(),
      postalCode: (m['postalCode'] as String?)?.trim(),
      emergencyName: (m['emergencyName'] as String?)?.trim(),
      emergencyPhone: (m['emergencyPhone'] as String?)?.trim(),
      notes: (m['notes'] as String?)?.trim(),
      tags: (m['tags'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      blacklistReason: (m['blacklistReason'] as String?)?.trim(),
      clientType: _normalizeClientType(m['clientType'] as String?),
      tenantBankName: (m['tenantBankName'] as String?)?.trim(),
      tenantBankAccountNumber:
          (m['tenantBankAccountNumber'] as String?)?.trim(),
      tenantTaxNumber: (m['tenantTaxNumber'] as String?)?.trim(),
      companyName: (m['companyName'] as String?)?.trim(),
      companyCommercialRegister:
          (m['companyCommercialRegister'] as String?)?.trim(),
      companyTaxNumber: (m['companyTaxNumber'] as String?)?.trim(),
      companyRepresentativeName:
          (m['companyRepresentativeName'] as String?)?.trim(),
      companyRepresentativePhone:
          (m['companyRepresentativePhone'] as String?)?.trim(),
      companyBankAccountNumber:
          (m['companyBankAccountNumber'] as String?)?.trim(),
      companyBankName: (m['companyBankName'] as String?)?.trim(),
      serviceSpecialization: (m['serviceSpecialization'] as String?)?.trim(),
      attachmentPaths:
          (m['attachmentPaths'] as List?)?.whereType<String>().toList() ??
              const <String>[],
      isArchived: (m['isArchived'] == true),
      isBlacklisted: (m['isBlacklisted'] == true),
      activeContractsCount: (m['activeContractsCount'] is int)
          ? m['activeContractsCount'] as int
          : int.tryParse('${m['activeContractsCount'] ?? 0}') ?? 0,
      createdAt: tsToDate(m['createdAt']),
      updatedAt: tsToDate(m['updatedAt']),
    );
  }

  Map<String, dynamic> _summaryFromTenant(Tenant t) {
    return <String, dynamic>{
      'id': t.id,
      'fullName': t.fullName,
      'nationalId': t.nationalId,
      'phone': t.phone,
      'email': t.email,
      'dateOfBirth': t.dateOfBirth?.toIso8601String(),
      'addressLine': t.addressLine,
      'city': t.city,
      'region': t.region,
      'postalCode': t.postalCode,
      'tags': t.tags,
      'clientType': t.clientType,
      'isArchived': t.isArchived,
      'isBlacklisted': t.isBlacklisted,
      'activeContractsCount': t.activeContractsCount,
      'isDeleted': false,
    };
  }

  Map<String, dynamic> _summaryFromMap(Map<String, dynamic> m) {
    return <String, dynamic>{
      'id': (m['id'] ?? '').toString(),
      'fullName': (m['fullName'] ?? '').toString(),
      'nationalId': (m['nationalId'] ?? '').toString(),
      'phone': (m['phone'] ?? '').toString(),
      'email': (m['email'] ?? '').toString(),
      'dateOfBirth': _toDateValue(m['dateOfBirth'])?.toIso8601String(),
      'addressLine': (m['addressLine'] ?? '').toString(),
      'city': (m['city'] ?? '').toString(),
      'region': (m['region'] ?? '').toString(),
      'postalCode': (m['postalCode'] ?? '').toString(),
      'tags': (m['tags'] as List?)?.whereType<String>().toList() ?? const <String>[],
      'clientType': (m['clientType'] ?? '').toString(),
      'isArchived': m['isArchived'] == true,
      'isBlacklisted': m['isBlacklisted'] == true,
      'activeContractsCount': m['activeContractsCount'],
      'isDeleted': m['isDeleted'] == true,
    };
  }
}


