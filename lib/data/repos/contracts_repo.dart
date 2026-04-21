import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
import '../services/activity_log_service.dart';
import '../services/entity_audit_service.dart';

// ✅ مهم: صرّح بالتعدادات المطلوبة وليس Contract فقط
import '../../ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle, AdvanceMode;

class ContractsRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  ContractsRepo(this.uc);

  /* ===================== Utils ===================== */

  DateTime? _fromTs(dynamic v) {
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

  DateTime _safeDate(dynamic v, {DateTime? orElse}) =>
      _fromTs(v) ?? (orElse ?? KsaTime.now());

  double _toDouble(dynamic v, [double def = 0.0]) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? def;
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  // تحويل تعداد ↔️ index بأمان
  int? _termIndex(ContractTerm? t) => t?.index;
  int? _cycleIndex(PaymentCycle? p) => p?.index;
  int? _advIndex(AdvanceMode? a) => a?.index;

  int? _enumIndex(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  ContractTerm _termFrom(dynamic i,
      {ContractTerm fallback = ContractTerm.monthly}) {
    final idx = _enumIndex(i);
    if (idx != null && idx >= 0 && idx < ContractTerm.values.length) {
      return ContractTerm.values[idx];
    }
    final name = _enumName(i);
    if (name != null) {
      for (final v in ContractTerm.values) {
        if (v.name.toLowerCase() == name) return v;
      }
    }
    return fallback;
  }

  PaymentCycle _cycleFrom(dynamic i,
      {PaymentCycle fallback = PaymentCycle.monthly}) {
    final idx = _enumIndex(i);
    if (idx != null && idx >= 0 && idx < PaymentCycle.values.length) {
      return PaymentCycle.values[idx];
    }
    final name = _enumName(i);
    if (name != null) {
      for (final v in PaymentCycle.values) {
        if (v.name.toLowerCase() == name) return v;
      }
    }
    return fallback;
  }

  AdvanceMode _advFrom(dynamic i, {AdvanceMode fallback = AdvanceMode.none}) {
    final idx = _enumIndex(i);
    if (idx != null && idx >= 0 && idx < AdvanceMode.values.length) {
      return AdvanceMode.values[idx];
    }
    final name = _enumName(i);
    if (name != null) {
      for (final v in AdvanceMode.values) {
        if (v.name.toLowerCase() == name) return v;
      }
    }
    return fallback;
  }

  String? _enumName(dynamic raw) {
    if (raw == null) return null;
    try {
      final n = (raw as dynamic).name;
      if (n is String && n.trim().isNotEmpty) {
        return n.trim().toLowerCase();
      }
    } catch (_) {}
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return s.split('.').last.toLowerCase();
  }

  String? _cleanStr(dynamic v) {
    final s = v?.toString();
    if (s == null) return null;
    return s.trim().isEmpty ? null : s.trim();
  }

  Map<String, dynamic> _removeNulls(Map<String, dynamic> m) {
    m.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
    return m;
  }

  /* ===================== CRUD ===================== */

  Future<void> saveContract(Contract c) async {
    // ملاحظة: إذا أردت جعل createdAt يُكتب فقط عند الإنشاء الأول،
    // اجعل منطق الإنشاء/التحديث منفصلين. هنا نستخدم merge: true.
    final ref = uc.contracts.doc(c.id);
    final before = await ref.get();
    final oldData = before.data();
    final payload = _toRemote(c);
    payload.addAll(await EntityAuditService.instance.buildWriteAuditFields(
      isCreate: !before.exists,
      workspaceUid: uc.uid,
    ));
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: uc.uid,
      collectionName: 'contracts',
      entityId: c.id,
      isCreate: !before.exists,
    );
    await ref.set(payload, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: before.exists ? 'update' : 'create',
      entityType: 'contract',
      entityId: c.id,
      entityName: c.serialNo ?? c.id,
      oldData: oldData == null ? null : _summaryFromMap(oldData),
      newData: _summaryFromContract(c),
    ));
  }

  Future<Contract?> getContract(String id) async {
    final snap = await uc.contracts.doc(id).get();
    if (!snap.exists) return null;
    final m = snap.data() ?? <String, dynamic>{};
    m.putIfAbsent('id', () => snap.id);
    return _fromRemote(m);
  }

  Future<List<Contract>> listContracts() async {
    // يعتمد على updatedAt (Timestamp) — جيّد مع serverTimestamp
    final q = await uc.contracts.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) {
      final m = d.data();
      m.putIfAbsent('id', () => d.id);
      return _fromRemote(m);
    }).toList();
  }

  void startContractsListener({
    required void Function(Contract c) onUpsert,
    required void Function(String id) onDelete,
  }) {
    _sub?.cancel();
    _sub = uc.contracts.snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        final m = ch.doc.data();
        final id = ch.doc.id;

        final deleted = (m?['isDeleted'] == true) ||
            (m?['isTerminated'] == true && m?['hardDeleted'] == true) ||
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

  void stopContractsListener() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> deleteContractSoft(String id) async {
    final ref = uc.contracts.doc(id);
    final before = await ref.get();
    await ref.set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'contract',
      entityId: id,
      entityName: (before.data()?['serialNo'] ?? id).toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{'isDeleted': true},
    ));
  }

  Future<void> deleteContractHard(String id) async {
    final ref = uc.contracts.doc(id);
    final before = await ref.get();
    await ref.delete();
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'contract',
      entityId: id,
      entityName: (before.data()?['serialNo'] ?? id).toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{},
    ));
  }

  /* ===================== تحويلات ===================== */

  /// 🔁 إلى السحابة: أرسل كل الحقول المهمة حتى لا تضيع القيم غير الافتراضية
  Map<String, dynamic> _toRemote(Contract c) {
    final map = <String, dynamic>{
      'id': c.id,
      'tenantId': c.tenantId,
      'propertyId': c.propertyId,

      // تواريخ
      'startDate': (c.startDate is DateTime) ? c.startDate : null,
      'endDate': (c.endDate is DateTime) ? c.endDate : null,

      // مبالغ
      'rentAmount': _toDouble(c.rentAmount, 0.0),
      // بعض المشاريع عندها totalAmount مطلوب بالموديل:
      'totalAmount':
          _toDouble((c as dynamic).totalAmount, _toDouble(c.rentAmount, 0.0)),

      // 👇 الحقول التي كانت مفقودة (سبب المشكلة):
      'currency': _cleanStr((c as dynamic).currency), // مثال: 'SAR'/'USD'
      'term': _termIndex((c as dynamic).term), // index of enum
      'termYears': _toIntOrNull((c as dynamic).termYears),
      'paymentCycle': _cycleIndex((c as dynamic).paymentCycle), // index of enum
      'paymentCycleYears': _toIntOrNull((c as dynamic).paymentCycleYears),
      'advanceMode': _advIndex((c as dynamic).advanceMode), // index of enum
      'advancePaid': _toDouble((c as dynamic).advancePaid, 0.0),
      'dailyCheckoutHour': _toIntOrNull((c as dynamic).dailyCheckoutHour),

      // حالة/نصوص وروابط
      'isTerminated': c.isTerminated == true,
      'terminatedAt': (c as dynamic).terminatedAt is DateTime
          ? (c as dynamic).terminatedAt
          : null,
      'isArchived': ((c as dynamic).isArchived == true),
      'notes': _cleanStr((c as dynamic).notes),
      'serialNo': _cleanStr((c as dynamic).serialNo),
      'ejarContractNo': _cleanStr((c as dynamic).ejarContractNo),
      'attachmentPaths': (c as dynamic).attachmentPaths,
      'tenantSnapshot': (c as dynamic).tenantSnapshot,
      'propertySnapshot': (c as dynamic).propertySnapshot,
      'buildingSnapshot': (c as dynamic).buildingSnapshot,

      // طوابع الزمن
      'createdAt': (c as dynamic).createdAt is DateTime
          ? (c as dynamic).createdAt
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),

      // علم الحذف اللين
      'isDeleted': false,
    };

    return _removeNulls(map);
  }

  /// 🔁 من السحابة: اقرأ كل الحقول وحوّلها بأمان للتعدادات/التواريخ
  Contract _fromRemote(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final tenantId = (m['tenantId'] ?? '').toString();
    final propertyId = (m['propertyId'] ?? '').toString();

    final start = _safeDate(m['startDate']);
    final end =
        _safeDate(m['endDate'], orElse: start.add(const Duration(days: 365)));

    final rent = _toDouble(m['rentAmount'], 0.0);
    final total = _toDouble(m['totalAmount'], rent);

    final terminated = (m['isTerminated'] == true);
    final archived = (m['isArchived'] == true);

    // نصوص
    final currency = _cleanStr(m['currency']) ?? 'SAR';
    final notes = _cleanStr(m['notes']);
    final serialNo = _cleanStr(m['serialNo']);

    // تعداد
    final term = _termFrom(m['term']);
    final termYears = _toIntOrNull(m['termYears']) ?? 1;
    final paymentCycle = _cycleFrom(m['paymentCycle']);
    final paymentCycleYears = _toIntOrNull(m['paymentCycleYears']) ?? 1;
    final advanceMode = _advFrom(m['advanceMode']);

    // مبالغ/أرقام إضافية
    final advancePaid = m['advancePaid'] == null
        ? null
        : _toDouble(m['advancePaid'], 0.0);
    final dailyCheckoutHour = _toIntOrNull(m['dailyCheckoutHour']);

    // الطوابع
    final createdAt = _fromTs(m['createdAt']) ?? KsaTime.now();
    final updatedAt = _fromTs(m['updatedAt']) ?? KsaTime.now();
    final terminatedAt = _fromTs(m['terminatedAt']);

    // ✅ أبني Contract مع كل الحقول (حسب مُنشئ موديلك)
    return Contract(
      id: id,
      tenantId: tenantId,
      propertyId: propertyId,

      startDate: start,
      endDate: end,

      rentAmount: rent,
      totalAmount: total,

      // 👇 هذه كانت تفقِد قيمها — الآن تُضبط من السحابة
      currency: currency,
      term: term,
      termYears: termYears,
      paymentCycle: paymentCycle,
      paymentCycleYears: paymentCycleYears,
      advanceMode: advanceMode,
      advancePaid: advancePaid,
      dailyCheckoutHour: dailyCheckoutHour,

      isTerminated: terminated,
      terminatedAt: terminatedAt,
      isArchived: archived,
      notes: notes,
      serialNo: serialNo,
      ejarContractNo: _cleanStr(m['ejarContractNo']),
      attachmentPaths:
          (m['attachmentPaths'] as List?)?.whereType<String>().toList() ??
              const <String>[],
      tenantSnapshot: (m['tenantSnapshot'] as Map?)?.cast<String, dynamic>(),
      propertySnapshot: (m['propertySnapshot'] as Map?)?.cast<String, dynamic>(),
      buildingSnapshot: (m['buildingSnapshot'] as Map?)?.cast<String, dynamic>(),

      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> _summaryFromContract(Contract c) {
    return <String, dynamic>{
      'id': c.id,
      'tenantId': c.tenantId,
      'propertyId': c.propertyId,
      'startDate': c.startDate.toIso8601String(),
      'endDate': c.endDate.toIso8601String(),
      'rentAmount': c.rentAmount,
      'totalAmount': c.totalAmount,
      'currency': c.currency,
      'term': c.term.name,
      'termYears': c.termYears,
      'paymentCycle': c.paymentCycle.name,
      'paymentCycleYears': c.paymentCycleYears,
      'advanceMode': c.advanceMode.name,
      'advancePaid': c.advancePaid,
      'dailyCheckoutHour': c.dailyCheckoutHour,
      'isTerminated': c.isTerminated,
      'terminatedAt': c.terminatedAt?.toIso8601String(),
      'isArchived': c.isArchived,
      'serialNo': c.serialNo,
      'ejarContractNo': c.ejarContractNo,
      'attachmentPaths': c.attachmentPaths,
      'isDeleted': false,
    };
  }

  Map<String, dynamic> _summaryFromMap(Map<String, dynamic> m) {
    return <String, dynamic>{
      'id': (m['id'] ?? '').toString(),
      'tenantId': (m['tenantId'] ?? '').toString(),
      'propertyId': (m['propertyId'] ?? '').toString(),
      'startDate': _fromTs(m['startDate'])?.toIso8601String(),
      'endDate': _fromTs(m['endDate'])?.toIso8601String(),
      'rentAmount': _toDouble(m['rentAmount']),
      'totalAmount': _toDouble(m['totalAmount']),
      'currency': (m['currency'] ?? '').toString(),
      'term': m['term'],
      'termYears': m['termYears'],
      'paymentCycle': m['paymentCycle'],
      'paymentCycleYears': m['paymentCycleYears'],
      'advanceMode': m['advanceMode'],
      'advancePaid': _toDouble(m['advancePaid']),
      'dailyCheckoutHour': _toIntOrNull(m['dailyCheckoutHour']),
      'isTerminated': m['isTerminated'] == true,
      'terminatedAt': _fromTs(m['terminatedAt'])?.toIso8601String(),
      'isArchived': m['isArchived'] == true,
      'serialNo': (m['serialNo'] ?? '').toString(),
      'ejarContractNo': (m['ejarContractNo'] ?? '').toString(),
      'attachmentPaths': (m['attachmentPaths'] as List?)?.whereType<String>().toList() ?? const <String>[],
      'isDeleted': m['isDeleted'] == true,
    };
  }
}



