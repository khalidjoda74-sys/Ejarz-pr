// lib/data/services/offline_sync_service.dart
// تعديل جذري يضمن:
// - لا تنبيهات خاصة بالأوفلاين: كل شيء يعمل بصيغة "تم الحفظ" طبيعي.
// - الإضافة تظهر فورًا في الواجهة وتبقى ثابتة في موضعها (يُدار الترتيب في الواجهة عبر سجل محلي).
// - التعديل على عميل "محلي" يندمج مباشرةً مع عنصر الإضافة المعلّق بدل محاولة إرسال تعديل على UID غير موجود.
// - تفريغ الطوابير يتم بهدوء عند توفر الإنترنت، دون تغيير سلوك الواجهة.
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// 🔹 Firestore/Functions
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/tenant.dart';
import '../../models/property.dart';
import '../repos/tenants_repo.dart';
import '../services/firestore_user_collections.dart';
import '../services/entity_audit_service.dart';

// ثوابت الصناديق العامة (لا تحوي boxName)

// ✅ استدعِ boxName من user_scope
import '../services/user_scope.dart' as scope;

/// أسماء صناديق صفّ الانتظار (تُطبّق عليها scope عبر boxName)
const String kPendingTenantUpserts = 'pendingTenantUpserts';
const String kPendingTenantDeletes = 'pendingTenantDeletes';

/// صفوف عملاء المكتب (إضافة/تعديل/حذف) — تُخزّن محليًا وتُرفع لاحقًا
const String kPendingOfficeClientCreates =
    'pendingOfficeClientCreates'; // Map<String,dynamic> (tempId key)
const String kPendingOfficeClientEdits =
    'pendingOfficeClientEdits'; // key: clientUid -> Map<String,dynamic>
const String kPendingOfficeClientDeletes =
    'pendingOfficeClientDeletes'; // key: clientUid -> {'requestedAtIso': ...}

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  late TenantsRepo _repo;
  late UserCollections _uc;
  StreamSubscription? _connSub;
  bool _initialized = false;
  Future<void>? _officeClientsFlushInFlight;

  // حالة تقريبية للاتصال
  bool _isOnline = false;

  // ========= مساعدات Hive (بنطاق المستخدم) =========
  Future<Box> _ensureOpenBox(String logical) async {
    final name = scope.boxName(logical);
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  Box _boxOf(String logical) => Hive.box(scope.boxName(logical));

  String _makeTempId() => 'tmp_${KsaTime.now().microsecondsSinceEpoch}';

  String _officeAuditWorkspaceUid() {
    final scoped = scope.effectiveUid().trim();
    if (scoped.isNotEmpty && scoped != 'guest') return scoped;
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  Future<String> _findExistingOfficeClientUidByEmail({
    required String officeUid,
    required String email,
  }) async {
    final emailNorm = email.trim().toLowerCase();
    if (officeUid.isEmpty || emailNorm.isEmpty) return '';
    try {
      final direct = await FirebaseFirestore.instance
          .collection('offices')
          .doc(officeUid)
          .collection('clients')
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();
      if (direct.docs.isNotEmpty) {
        final m = direct.docs.first.data();
        return (m['clientUid'] ?? m['uid'] ?? direct.docs.first.id)
            .toString()
            .trim();
      }
    } catch (_) {}
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: emailNorm)
          .limit(1)
          .get();
      if (userDoc.docs.isNotEmpty) {
        return userDoc.docs.first.id.trim();
      }
    } catch (_) {}
    return '';
  }

  void _scheduleStartupFlushRetries() {
    for (final seconds in const [2, 6]) {
      unawaited(() async {
        await Future<void>.delayed(Duration(seconds: seconds));
        if (!_initialized) return;
        await tryFlushAllIfOnline();
      }());
    }
  }

  // ========= شبكة: فحص سريع =========
  Future<bool> _quickOnlineProbe() async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isOnlineQuick() => _quickOnlineProbe();

  Future<void> init(
      {required UserCollections uc, required TenantsRepo repo}) async {
    _uc = uc;
    _repo = repo;
    _connSub?.cancel();
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork || !_initialized) return;
      unawaited(tryFlushAllIfOnline());
    });

    // فتح صناديق الطوابير (مع scope)
    final upBoxName = scope.boxName(kPendingTenantUpserts);
    final delBoxName = scope.boxName(kPendingTenantDeletes);
    if (!Hive.isBoxOpen(upBoxName)) {
      await Hive.openBox<Tenant>(upBoxName);
    }
    if (!Hive.isBoxOpen(delBoxName)) {
      await Hive.openBox<String>(delBoxName);
    }

    await _ensureOpenBox(kPendingOfficeClientCreates);
    await _ensureOpenBox(kPendingOfficeClientEdits);
    await _ensureOpenBox(kPendingOfficeClientDeletes);

    _initialized = true;

    // حالة أولية للشبكة + محاولة تفريغ
    _isOnline = await _quickOnlineProbe();
    if (_isOnline) {
      unawaited(_flushTenantsQueue());
      unawaited(_flushOfficeClientsQueue());
    }
    _scheduleStartupFlushRetries();
  }

  void dispose() {
    _connSub?.cancel();
    _connSub = null;
    _initialized = false;
    _isOnline = false;
  }

  bool _ensureInit() {
    if (!_initialized) {
      return false;
    }
    return true;
  }

  /// استدعِها من أماكن متعددة (الدخول للشاشة، بعد إضافة/تعديل، إلخ)
  Future<void> tryFlushAllIfOnline() async {
    if (!_initialized) return;
    final ok = await _quickOnlineProbe();
    _isOnline = ok;
    if (!ok) return;
    await Future.wait([
      _flushTenantsQueue(),
      _flushOfficeClientsQueue(),
    ]);
  }

  // ==========================
  // ✅ مزامنة المستأجرين (طوابير)
  // ==========================
  Future<void> enqueueUpsertTenant(Tenant t) async {
    if (!_ensureInit()) return;
    final qUp = Hive.box<Tenant>(scope.boxName(kPendingTenantUpserts));
    // Never enqueue the same HiveObject instance from another box.
    // We store a detached clone to avoid:
    // "The same instance of an HiveObject cannot be stored in two different boxes."
    await qUp.put(t.id, _cloneTenant(t));
    if (_isOnline) {
      await _flushTenantsQueue();
    }
  }

  Tenant _cloneTenant(Tenant t) {
    return Tenant(
      id: t.id,
      fullName: t.fullName,
      nationalId: t.nationalId,
      phone: t.phone,
      email: t.email,
      dateOfBirth: t.dateOfBirth,
      nationality: t.nationality,
      idExpiry: t.idExpiry,
      addressLine: t.addressLine,
      city: t.city,
      region: t.region,
      postalCode: t.postalCode,
      emergencyName: t.emergencyName,
      emergencyPhone: t.emergencyPhone,
      notes: t.notes,
      tags: List<String>.from(t.tags),
      clientType: t.clientType,
      tenantBankName: t.tenantBankName,
      tenantBankAccountNumber: t.tenantBankAccountNumber,
      tenantTaxNumber: t.tenantTaxNumber,
      companyName: t.companyName,
      companyCommercialRegister: t.companyCommercialRegister,
      companyTaxNumber: t.companyTaxNumber,
      companyRepresentativeName: t.companyRepresentativeName,
      companyRepresentativePhone: t.companyRepresentativePhone,
      companyBankAccountNumber: t.companyBankAccountNumber,
      companyBankName: t.companyBankName,
      serviceSpecialization: t.serviceSpecialization,
      attachmentPaths: List<String>.from(t.attachmentPaths),
      isArchived: t.isArchived,
      isBlacklisted: t.isBlacklisted,
      blacklistReason: t.blacklistReason,
      activeContractsCount: t.activeContractsCount,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    );
  }

  Future<void> enqueueDeleteTenantSoft(String tenantId) async {
    if (!_ensureInit()) return;
    final qDel = Hive.box<String>(scope.boxName(kPendingTenantDeletes));
    await qDel.put(tenantId, tenantId);
    if (_isOnline) {
      await _flushTenantsQueue();
    }
  }

  Future<void> _flushTenantsQueue() async {
    if (!_ensureInit()) return;
    final qUp = Hive.box<Tenant>(scope.boxName(kPendingTenantUpserts));
    final qDel = Hive.box<String>(scope.boxName(kPendingTenantDeletes));

    // 1) upserts
    final upserts = qUp.values.toList(growable: false);
    for (final t in upserts) {
      try {
        await _repo.saveTenant(t);
        await qUp.delete(t.id);
      } catch (_) {
        /* يعاد لاحقًا */
      }
    }

    // 2) deletions
    final deletions = qDel.values.toList(growable: false);
    for (final id in deletions) {
      try {
        await _repo.deleteTenantSoft(id);
        await qDel.delete(id);
      } catch (_) {
        /* يعاد لاحقًا */
      }
    }
  }

  // ==========================
  // ✅ عملاء المكتب — إضافة/تعديل/حذف (طوابير)
  // ==========================

  // قائمة الإضافات المعلقة (لعرضها فورًا في UI)
  List<Map<String, dynamic>> listPendingOfficeCreates() {
    try {
      final b = _boxOf(kPendingOfficeClientCreates);
      final list = b.values
          .cast<dynamic>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // ترتيب حديث أولًا (للواجهات التي لا تستخدم سجل ترتيب مستقل)
      list.sort((a, b) {
        final aa = DateTime.tryParse((a['createdAtIso'] ?? '') as String) ??
            DateTime(2000);
        final bb = DateTime.tryParse((b['createdAtIso'] ?? '') as String) ??
            DateTime(2000);
        return bb.compareTo(aa);
      });
      return list;
    } catch (_) {
      return const [];
    }
  }

  // خريطة تعديلات معلقة: uid -> patch
  Map<String, Map<String, dynamic>> mapPendingOfficeEdits() {
    try {
      final b = _boxOf(kPendingOfficeClientEdits);
      final out = <String, Map<String, dynamic>>{};
      for (final k in b.keys) {
        final v = b.get(k);
        if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // مجموعة الحذف المعلق (يمكن استخدامها لإخفاء العناصر فورًا من UI)
  Set<String> setPendingOfficeDeletesIds() {
    try {
      final b = _boxOf(kPendingOfficeClientDeletes);
      return b.keys.map((e) => e.toString()).toSet();
    } catch (_) {
      return const {};
    }
  }

  // إلغاء عنصر إنشاء محلي (زر الحذف لبطاقة "محلية")
  Future<void> removePendingOfficeCreateByTempId(String tempId) async {
    final box = await _ensureOpenBox(kPendingOfficeClientCreates);
    await box.delete(tempId);
  }

  // دمج تعديل مع سجل إنشاء محلي (حسب localUid)
  Future<bool> _mergeEditIntoLocalCreate({
    required String localUid,
    String? name,
    String? phone,
    String? notes,
  }) async {
    final creates = await _ensureOpenBox(kPendingOfficeClientCreates);
    String? hitKey;
    Map<String, dynamic>? hitMap;
    for (final k in creates.keys) {
      final v = creates.get(k);
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        if ((m['localUid'] ?? '') == localUid) {
          hitKey = k.toString();
          hitMap = m;
          break;
        }
      }
    }
    if (hitKey == null || hitMap == null) return false;

    final patched = <String, dynamic>{}
      ..addAll(hitMap)
      ..addAll({
        if (name != null) 'name': name.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (notes != null) 'notes': notes.trim(),
        'updatedAtIso': KsaTime.now().toIso8601String(),
      });
    await creates.put(hitKey, patched);
    return true;
  }

  // إضافة عميل محليًا (يظهر فورًا) + محاولة رفع لاحقًا
  Future<String> enqueueCreateOfficeClient({
    required String name,
    required String email,
    String? phone,
    String? notes,
  }) async {
    final box = await _ensureOpenBox(kPendingOfficeClientCreates);
    final workspaceUid = _officeAuditWorkspaceUid();

    final localUid = 'local_${KsaTime.now().microsecondsSinceEpoch}';
    final tempId = _makeTempId();

    await box.put(tempId, <String, dynamic>{
      'tempId': tempId,
      'localUid': localUid, // يُستخدم للدخول محليًا
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': (phone ?? '').trim(),
      'notes': (notes ?? '').trim(),
      'workspaceUid': workspaceUid,
      'createdAtIso': KsaTime.now().toIso8601String(),
      'status': 'pending',
    });

    if (workspaceUid.isNotEmpty) {
      await EntityAuditService.instance.recordLocalAudit(
        workspaceUid: workspaceUid,
        collectionName: 'clients',
        entityId: localUid,
        isCreate: true,
      );
    }

    // محاولة تفريغ هادئة
    unawaited(tryFlushAllIfOnline());
    return tempId;
  }

  // تعديل عميل محليًا (patch) + رفع لاحقًا
  Future<void> enqueueEditOfficeClient({
    required String clientUid,
    String? name,
    String? phone,
    String? notes,
  }) async {
    final workspaceUid = _officeAuditWorkspaceUid();
    // إذا كان UID محليًا، ندمج التعديل مباشرة في عنصر الإنشاء المعلّق بدلاً من وضعه في صندوق "التعديلات"
    if (clientUid.startsWith('local_')) {
      final merged = await _mergeEditIntoLocalCreate(
        localUid: clientUid,
        name: name,
        phone: phone,
        notes: notes,
      );
      if (merged) {
        if (workspaceUid.isNotEmpty) {
          await EntityAuditService.instance.recordLocalAudit(
            workspaceUid: workspaceUid,
            collectionName: 'clients',
            entityId: clientUid,
            isCreate: false,
          );
        }
        // محاولة تفريغ إن وُجد اتصال
        unawaited(tryFlushAllIfOnline());
        return;
      }
      // إن لم نجد عنصر إنشاء لهذا الـ localUid نكمل كحالة عامة (احتياط)
    }

    final b = await _ensureOpenBox(kPendingOfficeClientEdits);
    final prev = (b.get(clientUid) as Map?) ?? const {};
    final merged = <String, dynamic>{}
      ..addAll(Map<String, dynamic>.from(prev))
      ..addAll({
        if (name != null) 'name': name.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (notes != null) 'notes': notes.trim(),
        if (workspaceUid.isNotEmpty) 'workspaceUid': workspaceUid,
        'updatedAtIso': KsaTime.now().toIso8601String(),
      });
    await b.put(clientUid, merged);

    if (workspaceUid.isNotEmpty) {
      await EntityAuditService.instance.recordLocalAudit(
        workspaceUid: workspaceUid,
        collectionName: 'clients',
        entityId: clientUid,
        isCreate: false,
      );
    }

    unawaited(tryFlushAllIfOnline());
  }

  // حذف عميل (فوري محليًا) + رفع لاحقًا
  Future<void> enqueueDeleteOfficeClient(String clientUid) async {
    // إن كان محليًا: لا نرسل شيئًا للسحابة، والمفترض أن الواجهة تزيل عنصر الإنشاء بالمفتاح المؤقت.
    if (clientUid.startsWith('local_')) {
      // لا إجراء هنا — الحذف المحلي يتم عبر removePendingOfficeCreateByTempId من الواجهة
      return;
    }

    final b = await _ensureOpenBox(kPendingOfficeClientDeletes);
    if (!b.containsKey(clientUid)) {
      await b.put(clientUid, {
        'requestedAtIso': KsaTime.now().toIso8601String(),
      });
    }
    unawaited(tryFlushAllIfOnline());
  }

  // تفريغ طوابير المكتب: إنشاء/تعديل/حذف
  Future<void> _flushOfficeClientsQueue() async {
    final inFlight = _officeClientsFlushInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _flushOfficeClientsQueueUnlocked();
    _officeClientsFlushInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_officeClientsFlushInFlight, future)) {
        _officeClientsFlushInFlight = null;
      }
    }
  }

  Future<void> _flushOfficeClientsQueueUnlocked() async {
    final officeUid = FirebaseAuth.instance.currentUser?.uid;
    if (officeUid == null || officeUid.isEmpty) return;

    final createsBox = await _ensureOpenBox(kPendingOfficeClientCreates);
    final editsBox = await _ensureOpenBox(kPendingOfficeClientEdits);
    final delsBox = await _ensureOpenBox(kPendingOfficeClientDeletes);

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    // 1) إنشاءات معلّقة
    final creates = createsBox.values
        .cast<dynamic>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    for (final item in creates) {
      final tempId = (item['tempId'] ?? '') as String;
      final workspaceUid =
          (item['workspaceUid'] ?? '').toString().trim().isNotEmpty
              ? (item['workspaceUid'] ?? '').toString().trim()
              : officeUid;
      try {
        final result = await functions.httpsCallable('officeCreateClient').call({
          'name': item['name'],
          'email': item['email'],
          'phone': item['phone'],
          'notes': item['notes'],
        });
        final createdUid = result.data is Map
            ? ((result.data as Map)['uid'] ?? '').toString().trim()
            : '';
        if (workspaceUid.isNotEmpty && createdUid.isNotEmpty) {
          await EntityAuditService.instance.recordLocalAudit(
            workspaceUid: workspaceUid,
            collectionName: 'clients',
            entityId: createdUid,
            isCreate: true,
          );
        }
        await createsBox.delete(tempId);
      } on FirebaseFunctionsException catch (e) {
        final code = e.code.trim().toLowerCase();
        if (code == 'already-exists') {
          final existingUid = await _findExistingOfficeClientUidByEmail(
            officeUid: officeUid,
            email: (item['email'] ?? '').toString(),
          );
          if (existingUid.isNotEmpty) {
            if (workspaceUid.isNotEmpty) {
              await EntityAuditService.instance.recordLocalAudit(
                workspaceUid: workspaceUid,
                collectionName: 'clients',
                entityId: existingUid,
                isCreate: true,
              );
            }
            await createsBox.delete(tempId);
            continue;
          }
        }
        // يعاد لاحقًا
      } catch (_) {
        // يعاد لاحقًا
      }
    }

    // 2) تعديلات معلّقة
    final editKeys =
        editsBox.keys.map((e) => e.toString()).toList(growable: false);
    for (final uid in editKeys) {
      try {
        // تجاهل أي UID محلي وصل إلى هنا لأي سبب (احتياط/توافق)
        if (uid.startsWith('local_')) {
          await editsBox.delete(uid);
          continue;
        }

        final patch = Map<String, dynamic>.from(editsBox.get(uid) as Map);
        final name = patch['name'] as String?;
        final phone = patch['phone'] as String?;
        final notes = patch['notes'] as String?;

        if (name != null || phone != null) {
          try {
            await functions.httpsCallable('updateUserProfile').call({
              'uid': uid,
              if (name != null) 'name': name,
              if (phone != null) 'phone': phone,
            });
          } catch (_) {/* يعاد لاحقًا */}
        }

        try {
          final cref = FirebaseFirestore.instance
              .collection('offices')
              .doc(officeUid)
              .collection('clients')
              .doc(uid);
          await cref.set({
            if (name != null) 'name': name,
            if (phone != null) 'phone': phone,
            if (notes != null) 'notes': notes,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {/* يعاد لاحقًا */}

        await editsBox.delete(uid);
      } catch (_) {
        // يعاد لاحقًا
      }
    }

    // 3) حذف معلّق
    final delKeys =
        delsBox.keys.map((e) => e.toString()).toList(growable: false);
    for (final uid in delKeys) {
      try {
        await functions
            .httpsCallable('officeDeleteClient')
            .call({'clientUid': uid});
        await delsBox.delete(uid);
      } catch (_) {
        // يعاد لاحقًا
      }
    }
  }

  // ==========================
  // ==========================
// ✅ مزامنة العقارات (Firestore persistence)
// ==========================
  Future<void> enqueueUpsertProperty(Property p) async {
    // ✅ استخدم الـ UID الفعّال (يدعم الانتحال)
    String uid;
    try {
      uid = scope.uidOrThrow(); // يرمي إن كان "guest"
    } catch (_) {
      return;
    }
    final data = _propertyToFirestore(p)
      ..['updatedAt'] = FieldValue.serverTimestamp();
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('properties')
          .doc(p.id);
      final before = await ref.get();
      data.addAll(await EntityAuditService.instance.buildWriteAuditFields(
        isCreate: !before.exists,
        workspaceUid: uid,
      ));
      await EntityAuditService.instance.recordLocalAudit(
        workspaceUid: uid,
        collectionName: 'properties',
        entityId: p.id,
        isCreate: !before.exists,
      );
      await ref.set(data, SetOptions(merge: true));
    } catch (_) {/* Firestore سيتكفّل بالمزامنة */}
  }

  Future<void> enqueueDeleteProperty(String propertyId) async {
    // ✅ استخدم الـ UID الفعّال (يدعم الانتحال)
    String uid;
    try {
      uid = scope.uidOrThrow(); // يرمي إن كان "guest"
    } catch (_) {
      return;
    }
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('properties')
          .doc(propertyId);
      await ref.delete();
    } catch (_) {/* Firestore سيعيد المحاولة */}
  }

  Map<String, dynamic> _propertyToFirestore(Property p) {
    return {
      'id': p.id,
      'name': p.name,
      'address': p.address,
      'type': p.type.name,
      'rentalMode': p.rentalMode?.name,
      'totalUnits': p.totalUnits,
      'occupiedUnits': p.occupiedUnits,
      'area': p.area,
      'floors': p.floors,
      'rooms': p.rooms,
      'price': p.price,
      'currency': p.currency,
      'description': p.description,
      'parentBuildingId': p.parentBuildingId,
    };
  }
}
