import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
import '../../models/tenant.dart';
import '../../utils/ksa_time.dart';

class TenantsRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  TenantsRepo(this.uc);

  /* ===================== حفظ / تحديث ===================== */
  Future<void> saveTenant(Tenant t) async {
    await uc.tenants.doc(t.id).set(_toRemote(t), SetOptions(merge: true));
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
            (m?['isDeleted'] == true) ||
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

  void stopTenantsListener() {
    _sub?.cancel();
    _sub = null;
  }

  /* ===================== حذف ===================== */
  Future<void> deleteTenantSoft(String id) async {
    await uc.tenants.doc(id).set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteTenantHard(String id) async {
    await uc.tenants.doc(id).delete();
  }

  /* ===================== تحويلات ===================== */

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
      'id'                  : t.id,
      'fullName'            : t.fullName.trim(),
      'nationalId'          : t.nationalId.trim(),
      'phone'               : t.phone.trim(),

      'isArchived'          : t.isArchived,
      'isBlacklisted'       : t.isBlacklisted,
      'activeContractsCount': t.activeContractsCount,

      // مهم لتصحيح أي حالة سابقة
      'isDeleted'           : false,

      // createdAt: لو null خليه من السيرفر، وإلا استعمل الموجود
      'createdAt'           : t.createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(t.createdAt!),

      // updatedAt: دائمًا من السيرفر (الحسم يكون بالـ server time)
      'updatedAt'           : FieldValue.serverTimestamp(),
    };

    // الإختياريات النصية — نحذف المفتاح إذا null بدل تجاهله
    putOpt(map, 'email', t.email);
    putOpt(map, 'nationality', t.nationality);
    putOpt(map, 'emergencyName', t.emergencyName);
    putOpt(map, 'emergencyPhone', t.emergencyPhone);
    putOpt(map, 'notes', t.notes);
    putOpt(map, 'blacklistReason', t.blacklistReason);

    // تاريخ انتهاء الهوية: إمّا Timestamp (بتاريخ KSA dateOnly) أو حذف الحقل
    if (t.idExpiry == null) {
      map['idExpiry'] = FieldValue.delete();
    } else {
      map['idExpiry'] = Timestamp.fromDate(KsaTime.dateOnly(t.idExpiry!));
    }

    return map;
  }

  Tenant _fromRemote(Map<String, dynamic> m) {
    DateTime? _tsToDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime)  return v;
      return null;
    }

    return Tenant(
      id:                 (m['id'] ?? '').toString(),
      fullName:           (m['fullName'] ?? '').toString(),
      nationalId:         (m['nationalId'] ?? '').toString(),
      phone:              ((m['phone'] ?? '') as Object).toString(),

      email:              (m['email'] as String?)?.trim(),
      nationality:        (m['nationality'] as String?)?.trim(),
      idExpiry:           _tsToDate(m['idExpiry']),
      emergencyName:      (m['emergencyName'] as String?)?.trim(),
      emergencyPhone:     (m['emergencyPhone'] as String?)?.trim(),
      notes:              (m['notes'] as String?)?.trim(),
      blacklistReason:    (m['blacklistReason'] as String?)?.trim(),

      isArchived:         (m['isArchived'] == true),
      isBlacklisted:      (m['isBlacklisted'] == true),

      activeContractsCount:
          (m['activeContractsCount'] is int)
              ? m['activeContractsCount'] as int
              : int.tryParse('${m['activeContractsCount'] ?? 0}') ?? 0,

      createdAt:          _tsToDate(m['createdAt']),
      updatedAt:          _tsToDate(m['updatedAt']),
    );
  }
}
