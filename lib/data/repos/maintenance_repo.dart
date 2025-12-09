// lib/data/repos/maintenance_repo.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';

// استورد الأنواع المطلوبة من شاشة الصيانة (نفس أسلوب المشروع)
import '../../ui/maintenance_screen.dart'
  show MaintenanceRequest, MaintenancePriority, MaintenanceStatus;

class MaintenanceRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  MaintenanceRepo(this.uc);

  /* ===================== CRUD ===================== */

  Future<void> saveRequest(MaintenanceRequest r) async {
    await uc.maintenance.doc(_idOf(r)).set(
      _toRemote(r),
      SetOptions(merge: true),
    );
  }

  Future<MaintenanceRequest?> getRequest(String id) async {
    final snap = await uc.maintenance.doc(id).get();
    if (!snap.exists) return null;
    final m = snap.data() ?? <String, dynamic>{};
    m.putIfAbsent('id', () => snap.id);
    return _fromRemote(m);
  }

  Future<List<MaintenanceRequest>> listRequests() async {
    final q = await uc.maintenance.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) {
      final m = d.data();
      m.putIfAbsent('id', () => d.id);
      return _fromRemote(m);
    }).toList();
  }

  /* ===================== Realtime listener ===================== */
  /// ملاحظة مهمة:
  /// هذا المستمع يُرجِع عنصرًا *كاملاً* من السحابة.
  /// ولمنع فقدان الحقول الاختيارية بسبب وثيقة ناقصة، تأكّد أن الكتابة (_toRemote) ترسل كل الحقول.
  void startMaintenanceListener({
    required void Function(MaintenanceRequest r) onUpsert,
    required void Function(String id) onDelete,
  }) {
    _sub?.cancel();
    _sub = uc.maintenance.snapshots().listen((snap) {
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

  void stopMaintenanceListener() {
    _sub?.cancel();
    _sub = null;
  }

  /* ===================== Delete ===================== */

  Future<void> deleteRequestSoft(String id) async {
    await uc.maintenance.doc(id).set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteRequestHard(String id) async {
    await uc.maintenance.doc(id).delete();
  }

  /* ===================== تحويلات ===================== */

  Map<String, dynamic> _toRemote(MaintenanceRequest r) {
    // نقرأ عبر dynamic لتجنب كسر الاستيراد إن تغيّر الموديل
    final d = r as dynamic;

    String _s(dynamic v) => (v ?? '').toString().trim();
    T? _get<T>(T Function() f) { try { return f(); } catch (_) { return null; } }

    // تواريخ كـ Timestamp (توافق Firestore)
    final DateTime? createdAt    = _get(() => d.createdAt) as DateTime?;
    final DateTime? scheduledAt  = _get(() => d.scheduledDate) as DateTime?;
    final DateTime? completedAt  = _get(() => d.completedDate) as DateTime?;

    String? _enumName(dynamic v) {
      if (v == null) return null;
      try {
        final n = (v as dynamic).name;
        if (n is String && n.isNotEmpty) return n;
      } catch (_) {}
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    // الحقول
    final id          = _s(_get(() => d.id));
    final title       = _s(_get(() => d.title));
    final propertyId  = _s(_get(() => d.propertyId));
    final description = _s(_get(() => d.description));
    final requestType = _s(_get(() => d.requestType));
    final tenantId    = _s(_get(() => d.tenantId));
    final assignedTo  = _s(_get(() => d.assignedTo));
    final invoiceId   = _s(_get(() => d.invoiceId));

    // أرقام
    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }
    final double? cost   = _toDouble(_get(() => d.cost));
    final bool?   arch   = _get(() => d.isArchived) as bool?;

    final map = <String, dynamic>{
      'id'          : id.isEmpty ? null : id,
      'title'       : title.isEmpty ? null : title,
      'propertyId'  : propertyId.isEmpty ? null : propertyId,
      // ⚠️ وحّدنا المفتاح: نستخدم 'note' (نفس ما تستخدمه الشاشة). سنقرأ لاحقًا من note أو description.
      'note'        : description.isEmpty ? null : description,
      'requestType' : requestType.isEmpty ? null : requestType,
      'tenantId'    : tenantId.isEmpty ? null : tenantId,
      'priority'    : _enumName(_get(() => d.priority)),     // low/medium/high/urgent
      'status'      : _enumName(_get(() => d.status)),       // open/inProgress/completed/canceled
      'createdAt'   : createdAt != null ? Timestamp.fromDate(createdAt) : null,
      'scheduledDate': scheduledAt != null ? Timestamp.fromDate(scheduledAt) : null,
      'completedDate': completedAt != null ? Timestamp.fromDate(completedAt) : null,
      'assignedTo'  : assignedTo.isEmpty ? null : assignedTo,
      'cost'        : cost,
      'isArchived'  : arch,
      'invoiceId'   : invoiceId.isEmpty ? null : invoiceId,
      'isDeleted'   : false,
      'updatedAt'   : FieldValue.serverTimestamp(),
    };

    // أزل null أو سلاسل فارغة
    map.removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));
    return map;
  }

  MaintenanceRequest _fromRemote(Map<String, dynamic> m) {
    String _s(dynamic v) => (v ?? '').toString().trim();

    MaintenancePriority _priorityOf(dynamic raw) {
      final s = _s(raw).toLowerCase();
      switch (s) {
        case 'low':    return MaintenancePriority.low;
        case 'high':   return MaintenancePriority.high;
        case 'urgent': return MaintenancePriority.urgent;
        case 'medium':
        default:       return MaintenancePriority.medium;
      }
    }

    MaintenanceStatus _statusOf(dynamic raw) {
      final s = _s(raw).toLowerCase();
      switch (s) {
        case 'inprogress': return MaintenanceStatus.inProgress;
        case 'completed':  return MaintenanceStatus.completed;
        case 'canceled':   return MaintenanceStatus.canceled;
        case 'open':
        default:           return MaintenanceStatus.open;
      }
    }

    DateTime? _toDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      if (v is String) {
        // جرّب parse ISO، أو parse أرقام millis إن كانت نصًا رقميًا
        final iso = DateTime.tryParse(v);
        if (iso != null) return iso;
        final ms = int.tryParse(v);
        if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      return null;
    }

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
      return 0.0;
    }

    // نقرأ الوصف من 'note' أو 'description' للتوافق
    final desc = _s(m['note'] ?? m['description']);

    return MaintenanceRequest(
      id           : _s(m['id']),
      propertyId   : _s(m['propertyId']),
      tenantId     : _s(m['tenantId']).isEmpty ? null : _s(m['tenantId']),
      title        : _s(m['title']),
      description  : desc,
      requestType  : _s(m['requestType']).isEmpty ? 'صيانة' : _s(m['requestType']),
      priority     : _priorityOf(m['priority']),
      status       : _statusOf(m['status']),
      createdAt    : _toDate(m['createdAt']) ?? DateTime.now(),
      scheduledDate: _toDate(m['scheduledDate']),
      completedDate: _toDate(m['completedDate']),
      cost         : _toDouble(m['cost']),
      assignedTo   : _s(m['assignedTo']).isEmpty ? null : _s(m['assignedTo']),
      isArchived   : (m['isArchived'] == true),
      invoiceId    : _s(m['invoiceId']).isEmpty ? null : _s(m['invoiceId']),
    );
  }

  /* ===================== Helpers ===================== */

  static T? _safe<T>(T Function() f) {
    try { return f(); } catch (_) { return null; }
  }

  String _idOf(MaintenanceRequest r) {
    final d = r as dynamic;
    final v = _safe(() => d.id);
    return (v ?? '').toString();
  }
}
