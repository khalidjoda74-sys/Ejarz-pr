// lib/data/repos/invoices_repo.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
import '../services/activity_log_service.dart';
import '../services/entity_audit_service.dart';
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
    if (v is String) {
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final ms = int.tryParse(v);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (v is Timestamp) return v.toDate();
    return null;
  }

  bool _isPaidInvoice(Invoice inv) {
    if (inv.isCanceled == true) return false;
    return inv.paidAmount >= (inv.amount.abs() - 0.000001);
  }

  double _resolvedPaidAmount(Map<String, dynamic> m, double amount) {
    final paid = _toD(m['paidAmount']);
    if (paid > 0) return paid;
    final hasPaidDate = _toDate(m['paidAt']) != null ||
        _toDate(m['paid_on']) != null ||
        _toDate(m['paymentDate']) != null ||
        _toDate(m['paidDate']) != null;
    final canceled = m['isCanceled'] == true;
    return (!canceled && hasPaidDate) ? amount.abs() : 0.0;
  }

  Map<String, dynamic> _toFirestoreMap(Invoice inv) {
    final paid = _isPaidInvoice(inv);
    return {
      'id': inv.id,
      'tenantId': inv.tenantId,
      'contractId': inv.contractId,
      'propertyId': inv.propertyId,
      'issueDate': inv.issueDate.millisecondsSinceEpoch,
      'dueDate': inv.dueDate.millisecondsSinceEpoch,
      'amount': inv.amount,
      'paidAmount': inv.paidAmount, // 👈 مهم لظهور الحالة "مدفوع"
      'paidAt': paid ? inv.issueDate.millisecondsSinceEpoch : null,
      'paymentDate': paid ? inv.issueDate.millisecondsSinceEpoch : null,
      'remainingAmount': (inv.amount.abs() - inv.paidAmount).clamp(0.0, double.infinity),
      'currency': inv.currency,
      'paymentMethod': inv.paymentMethod,
      'attachmentPaths': inv.attachmentPaths,
      'maintenanceRequestId': inv.maintenanceRequestId,
      'maintenanceSnapshot': inv.maintenanceSnapshot,
      'waterAmount': inv.waterAmount,
      'isArchived': inv.isArchived == true,
      'isCanceled': inv.isCanceled == true,
      'serialNo': inv.serialNo,
      'note': inv.note,
      'createdAt': inv.createdAt.millisecondsSinceEpoch,
      // updatedAt server-side حتى يُرتّب حسب آخر تعديل
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    }..removeWhere((k, v) => v == null);
  }

  Invoice _fromFirestoreMap(String id, Map<String, dynamic> m) {
    final amount = _toD(m['amount']);
    return Invoice(
      id: m['id'] ?? id,
      tenantId: (m['tenantId'] ?? '').toString(),
      contractId: (m['contractId'] ?? '').toString(),
      propertyId: (m['propertyId'] ?? '').toString(),
      issueDate: _toDate(m['issueDate']) ?? KsaTime.now(),
      dueDate: _toDate(m['dueDate']) ?? KsaTime.now(),
      amount: amount,
      paidAmount: _resolvedPaidAmount(m, amount), // يقرأ paidAmount أو يستنتجه من paidAt للبيانات القديمة
      currency: (m['currency'] as String?) ?? 'SAR',
      paymentMethod: (m['paymentMethod'] as String?) ?? 'نقدًا',
      attachmentPaths:
          (m['attachmentPaths'] as List?)?.whereType<String>().toList() ??
              const <String>[],
      maintenanceRequestId: (m['maintenanceRequestId'] == null)
          ? null
          : m['maintenanceRequestId'].toString(),
      maintenanceSnapshot:
          (m['maintenanceSnapshot'] as Map?)?.cast<String, dynamic>(),
      waterAmount: _toD(m['waterAmount']),
      isArchived: (m['isArchived'] == true),
      isCanceled: (m['isCanceled'] == true),
      serialNo: m['serialNo']?.toString(),
      note: (m['note'] as String?),
      createdAt: _toDate(m['createdAt']) ?? KsaTime.now(),
      updatedAt: _toDate(m['updatedAt']) ?? KsaTime.now(),
    );
  }

  // (B) إنشاء/تحديث — يحافظ على paidAmount ليظهر كـ "مدفوع" فورًا
  Future<void> saveInvoice(Invoice inv) async {
    final ref = uc.invoices.doc(inv.id);
    final before = await ref.get();
    final oldData = before.data();
    final payload = _toFirestoreMap(inv);
    payload.addAll(await EntityAuditService.instance.buildWriteAuditFields(
      isCreate: !before.exists,
      workspaceUid: uc.uid,
    ));
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: uc.uid,
      collectionName: 'invoices',
      entityId: inv.id,
      isCreate: !before.exists,
    );
    await ref.set(
          payload,
          SetOptions(merge: true),
        );
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: before.exists ? 'update' : 'create',
      entityType: 'invoice',
      entityId: inv.id,
      entityName: inv.serialNo ?? inv.id,
      oldData: oldData == null ? null : _summaryFromMap(oldData),
      newData: _summaryFromInvoice(inv),
    ));
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

        final deleted =
            (m?['isDeleted'] == true) || ch.type == DocumentChangeType.removed;
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
    final ref = uc.invoices.doc(id);
    final before = await ref.get();
    await ref.set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'invoice',
      entityId: id,
      entityName: (before.data()?['serialNo'] ?? id).toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{'isDeleted': true},
    ));
  }

  Future<void> deleteInvoiceHard(String id) async {
    final ref = uc.invoices.doc(id);
    final before = await ref.get();
    await ref.delete();
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'invoice',
      entityId: id,
      entityName: (before.data()?['serialNo'] ?? id).toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{},
    ));
  }

  Map<String, dynamic> _summaryFromInvoice(Invoice inv) {
    return <String, dynamic>{
      'id': inv.id,
      'serialNo': inv.serialNo,
      'tenantId': inv.tenantId,
      'contractId': inv.contractId,
      'propertyId': inv.propertyId,
      'issueDate': inv.issueDate.toIso8601String(),
      'dueDate': inv.dueDate.toIso8601String(),
      'amount': inv.amount,
      'paidAmount': inv.paidAmount,
      'paidAt': _isPaidInvoice(inv) ? inv.issueDate.toIso8601String() : null,
      'paymentDate': _isPaidInvoice(inv) ? inv.issueDate.toIso8601String() : null,
      'remainingAmount': (inv.amount.abs() - inv.paidAmount).clamp(0.0, double.infinity),
      'currency': inv.currency,
      'paymentMethod': inv.paymentMethod,
      'attachmentPaths': inv.attachmentPaths,
      'maintenanceRequestId': inv.maintenanceRequestId,
      'maintenanceSnapshot': inv.maintenanceSnapshot,
      'waterAmount': inv.waterAmount,
      'isArchived': inv.isArchived,
      'isCanceled': inv.isCanceled,
      'isDeleted': false,
    };
  }

  Map<String, dynamic> _summaryFromMap(Map<String, dynamic> m) {
    return <String, dynamic>{
      'id': (m['id'] ?? '').toString(),
      'serialNo': (m['serialNo'] ?? '').toString(),
      'tenantId': (m['tenantId'] ?? '').toString(),
      'contractId': (m['contractId'] ?? '').toString(),
      'propertyId': (m['propertyId'] ?? '').toString(),
      'issueDate': _toDate(m['issueDate'])?.toIso8601String(),
      'dueDate': _toDate(m['dueDate'])?.toIso8601String(),
      'amount': _toD(m['amount']),
      'paidAmount': _resolvedPaidAmount(m, _toD(m['amount'])),
      'paidAt': _toDate(m['paidAt'])?.toIso8601String() ?? _toDate(m['paymentDate'])?.toIso8601String(),
      'remainingAmount': (_toD(m['amount']).abs() - _resolvedPaidAmount(m, _toD(m['amount']))).clamp(0.0, double.infinity),
      'currency': (m['currency'] ?? '').toString(),
      'paymentMethod': (m['paymentMethod'] ?? '').toString(),
      'attachmentPaths': (m['attachmentPaths'] as List?)?.whereType<String>().toList() ?? const <String>[],
      'maintenanceRequestId': (m['maintenanceRequestId'] ?? '').toString(),
      'waterAmount': _toD(m['waterAmount']),
      'isArchived': m['isArchived'] == true,
      'isCanceled': m['isCanceled'] == true,
      'isDeleted': m['isDeleted'] == true,
    };
  }
}



