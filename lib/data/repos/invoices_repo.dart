// lib/data/repos/invoices_repo.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
// استورد موديلك الحقيقي:
import '../../ui/invoices_screen.dart' show Invoice; // عدّل المسار إذا لزم

class InvoicesRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  InvoicesRepo(this.uc);

  // ===== Helpers =====
  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) return DateTime.tryParse(v);
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Map<String, dynamic> _toFirestoreMap(Invoice inv) {
    return {
      'id'           : inv.id,
      'tenantId'     : inv.tenantId,
      'contractId'   : inv.contractId,
      'propertyId'   : inv.propertyId,
      'issueDate'    : inv.issueDate.millisecondsSinceEpoch,
      'dueDate'      : inv.dueDate.millisecondsSinceEpoch,
      'amount'       : inv.amount,
      'paidAmount'   : inv.paidAmount,              // 👈 مهم لظهور الحالة "مدفوع"
      'currency'     : inv.currency,
      'paymentMethod': inv.paymentMethod,
      'isArchived'   : inv.isArchived == true,
      'isCanceled'   : inv.isCanceled == true,
      'serialNo'     : inv.serialNo,
      'note'         : inv.note,
      'createdAt'    : inv.createdAt.millisecondsSinceEpoch,
      // updatedAt server-side حتى يُرتّب حسب آخر تعديل
      'updatedAt'    : FieldValue.serverTimestamp(),
      'isDeleted'    : false,
    }..removeWhere((k, v) => v == null);
  }

  Invoice _fromFirestoreMap(String id, Map<String, dynamic> m) {
    return Invoice(
      id         : m['id'] ?? id,
      tenantId   : (m['tenantId'] ?? '') as String,
      contractId : (m['contractId'] ?? '') as String,
      propertyId : (m['propertyId'] ?? '') as String,
      issueDate  : _toDate(m['issueDate']) ?? DateTime.now(),
      dueDate    : _toDate(m['dueDate']) ?? DateTime.now(),
      amount     : _toD(m['amount']),
      paidAmount : _toD(m['paidAmount']),                    // 👈 سيقرأ القيمة الصحيحة إن وُجدت
      currency   : (m['currency'] as String?) ?? 'SAR',
      paymentMethod: (m['paymentMethod'] as String?) ?? 'نقدًا',
      isArchived : (m['isArchived'] == true),
      isCanceled : (m['isCanceled'] == true),
      serialNo   : _toInt(m['serialNo']),
      note       : (m['note'] as String?),
      createdAt  : _toDate(m['createdAt']) ?? DateTime.now(),
      updatedAt  : _toDate(m['updatedAt']) ?? DateTime.now(),
    );
  }

  // (B) إنشاء/تحديث — يحافظ على paidAmount ليظهر كـ "مدفوع" فورًا
  Future<void> saveInvoice(Invoice inv) async {
    await uc.invoices.doc(inv.id).set(
      _toFirestoreMap(inv),
      SetOptions(merge: true),
    );
  }

  // (C) قراءة مستند
  Future<Invoice?> getInvoice(String id) async {
    final snap = await uc.invoices.doc(id).get();
    if (!snap.exists) return null;
    final m = snap.data()!;
    return _fromFirestoreMap(snap.id, m);
  }

  // (C) قراءة قائمة
  Future<List<Invoice>> listInvoices() async {
    final q = await uc.invoices.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) => _fromFirestoreMap(d.id, d.data())).toList();
  }

  // (D) الاستماع لحظيًا — مرّر callbacks
  void startInvoicesListener({
    required void Function(Invoice inv) onUpsert,
    required void Function(String id) onDelete,
  }) {
    _sub?.cancel();
    _sub = uc.invoices.snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        final m = ch.doc.data();
        final id = ch.doc.id;

        final deleted = (m?['isDeleted'] == true) ||
                        ch.type == DocumentChangeType.removed;
        if (deleted) {
          onDelete(id);
          continue;
        }

        final inv = _fromFirestoreMap(id, m!);
        onUpsert(inv);
      }
    });
  }

  void stopInvoicesListener() {
    _sub?.cancel();
    _sub = null;
  }

  // (E) حذف ناعم/نهائي
  Future<void> deleteInvoiceSoft(String id) async {
    await uc.invoices.doc(id).set({
      'id'       : id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteInvoiceHard(String id) async {
    await uc.invoices.doc(id).delete();
  }
}
