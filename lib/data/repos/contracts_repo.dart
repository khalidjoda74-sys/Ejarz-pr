import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';

// ✅ مهم: صرّح بالتعدادات المطلوبة وليس Contract فقط
import '../../ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle, AdvanceMode;

class ContractsRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  ContractsRepo(this.uc);

  /* ===================== Utils ===================== */

  DateTime? _fromTs(dynamic v) =>
      (v is Timestamp) ? v.toDate() : (v is DateTime ? v : null);

  DateTime _safeDate(dynamic v, {DateTime? orElse}) =>
      _fromTs(v) ?? (orElse ?? DateTime.now());

  double _toDouble(dynamic v, [double def = 0.0]) =>
      (v is num) ? v.toDouble() : def;

  int? _toIntOrNull(dynamic v) => (v is num) ? v.toInt() : null;

  // تحويل تعداد ↔️ index بأمان
  int? _termIndex(ContractTerm? t) => t?.index;
  int? _cycleIndex(PaymentCycle? p) => p?.index;
  int? _advIndex(AdvanceMode? a) => a?.index;

  ContractTerm _termFrom(dynamic i, {ContractTerm fallback = ContractTerm.monthly}) {
    if (i is int && i >= 0 && i < ContractTerm.values.length) {
      return ContractTerm.values[i];
    }
    return fallback;
  }

  PaymentCycle _cycleFrom(dynamic i, {PaymentCycle fallback = PaymentCycle.monthly}) {
    if (i is int && i >= 0 && i < PaymentCycle.values.length) {
      return PaymentCycle.values[i];
    }
    return fallback;
  }

  AdvanceMode _advFrom(dynamic i, {AdvanceMode fallback = AdvanceMode.none}) {
    if (i is int && i >= 0 && i < AdvanceMode.values.length) {
      return AdvanceMode.values[i];
    }
    return fallback;
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
    await uc.contracts.doc(c.id).set(_toRemote(c), SetOptions(merge: true));
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

        final deleted =
            (m?['isDeleted'] == true) ||
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
    await uc.contracts.doc(id).set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteContractHard(String id) async {
    await uc.contracts.doc(id).delete();
  }

  /* ===================== تحويلات ===================== */

  /// 🔁 إلى السحابة: أرسل كل الحقول المهمة حتى لا تضيع القيم غير الافتراضية
  Map<String, dynamic> _toRemote(Contract c) {
    final map = <String, dynamic>{
      'id'           : c.id,
      'tenantId'     : c.tenantId,
      'propertyId'   : c.propertyId,

      // تواريخ
      'startDate'    : (c.startDate is DateTime) ? c.startDate : null,
      'endDate'      : (c.endDate   is DateTime) ? c.endDate   : null,

      // مبالغ
      'rentAmount'   : _toDouble(c.rentAmount, 0.0),
      // بعض المشاريع عندها totalAmount مطلوب بالموديل:
      'totalAmount'  : _toDouble((c as dynamic).totalAmount, _toDouble(c.rentAmount, 0.0)),

      // 👇 الحقول التي كانت مفقودة (سبب المشكلة):
      'currency'         : _cleanStr((c as dynamic).currency),        // مثال: 'SAR'/'USD'
      'term'             : _termIndex((c as dynamic).term),           // index of enum
      'paymentCycle'     : _cycleIndex((c as dynamic).paymentCycle),  // index of enum
      'advanceMode'      : _advIndex((c as dynamic).advanceMode),     // index of enum
      'advancePaid'      : _toDouble((c as dynamic).advancePaid, 0.0),
      'dailyCheckoutHour': _toIntOrNull((c as dynamic).dailyCheckoutHour),

      // حالة/نصوص
      'isTerminated' : (c.isTerminated ?? false),
      'isArchived'   : ((c as dynamic).isArchived == true),
      'notes'        : _cleanStr((c as dynamic).notes),
      'serialNo'     : _cleanStr((c as dynamic).serialNo),

      // طوابع الزمن
      'createdAt'    : (c as dynamic).createdAt is DateTime
          ? (c as dynamic).createdAt
          : FieldValue.serverTimestamp(),
      'updatedAt'    : FieldValue.serverTimestamp(),

      // علم الحذف اللين
      'isDeleted'    : false,
    };

    return _removeNulls(map);
  }

  /// 🔁 من السحابة: اقرأ كل الحقول وحوّلها بأمان للتعدادات/التواريخ
  Contract _fromRemote(Map<String, dynamic> m) {
    final id         = (m['id'] ?? '').toString();
    final tenantId   = (m['tenantId'] ?? '').toString();
    final propertyId = (m['propertyId'] ?? '').toString();

    final start      = _safeDate(m['startDate']);
    final end        = _safeDate(m['endDate'], orElse: start.add(const Duration(days: 365)));

    final rent       = _toDouble(m['rentAmount'], 0.0);
    final total      = _toDouble(m['totalAmount'], rent);

    final terminated = (m['isTerminated'] == true);
    final archived   = (m['isArchived'] == true);

    // نصوص
    final currency   = _cleanStr(m['currency']) ?? 'SAR';
    final notes      = _cleanStr(m['notes']);
    final serialNo   = _cleanStr(m['serialNo']);

    // تعداد
    final term          = _termFrom(m['term']);
    final paymentCycle  = _cycleFrom(m['paymentCycle']);
    final advanceMode   = _advFrom(m['advanceMode']);

    // مبالغ/أرقام إضافية
    final advancePaid       = (m['advancePaid'] is num) ? (m['advancePaid'] as num).toDouble() : null;
    final dailyCheckoutHour = _toIntOrNull(m['dailyCheckoutHour']);

    // الطوابع
    final createdAt = _fromTs(m['createdAt']) ?? DateTime.now();
    final updatedAt = _fromTs(m['updatedAt']) ?? DateTime.now();

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
      paymentCycle: paymentCycle,
      advanceMode: advanceMode,
      advancePaid: advancePaid,
      dailyCheckoutHour: dailyCheckoutHour,

      isTerminated: terminated,
      isArchived: archived,
      notes: notes,
      serialNo: serialNo,

      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
