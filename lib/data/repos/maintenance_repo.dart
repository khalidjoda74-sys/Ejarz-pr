// lib/data/repos/maintenance_repo.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';
import '../services/activity_log_service.dart';
import '../services/entity_audit_service.dart';

// استورد الأنواع المطلوبة من شاشة الصيانة (نفس أسلوب المشروع)
import '../../ui/maintenance_screen.dart'
    show MaintenanceRequest, MaintenancePriority, MaintenanceStatus;

class MaintenanceRepo {
  final UserCollections uc;
  StreamSubscription? _sub;

  MaintenanceRepo(this.uc);

  /* ===================== CRUD ===================== */

  Future<void> saveRequest(MaintenanceRequest r) async {
    final ref = uc.maintenance.doc(_idOf(r));
    final before = await ref.get();
    final oldData = before.data();
    final payload = _toRemote(r);
    payload.addAll(await EntityAuditService.instance.buildWriteAuditFields(
      isCreate: !before.exists,
      workspaceUid: uc.uid,
    ));
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: uc.uid,
      collectionName: 'maintenance',
      entityId: _idOf(r),
      isCreate: !before.exists,
    );
    await ref.set(
          payload,
          SetOptions(merge: true),
        );
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: before.exists ? 'update' : 'create',
      entityType: 'maintenance',
      entityId: _idOf(r),
      entityName: _titleOf(r),
      oldData: oldData == null ? null : _summaryFromMap(oldData),
      newData: _summaryFromRequest(r),
    ));
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

  void stopMaintenanceListener() {
    _sub?.cancel();
    _sub = null;
  }

  /* ===================== Delete ===================== */

  Future<void> deleteRequestSoft(String id) async {
    final ref = uc.maintenance.doc(id);
    final before = await ref.get();
    await ref.set({
      'id': id,
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'maintenance',
      entityId: id,
      entityName: (before.data()?['title'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{'isDeleted': true},
    ));
  }

  Future<void> deleteRequestHard(String id) async {
    final ref = uc.maintenance.doc(id);
    final before = await ref.get();
    await ref.delete();
    unawaited(ActivityLogService.instance.logEntityAction(
      actionType: 'delete',
      entityType: 'maintenance',
      entityId: id,
      entityName: (before.data()?['title'] ?? '').toString(),
      oldData: before.data() == null ? null : _summaryFromMap(before.data()!),
      newData: const <String, dynamic>{},
    ));
  }

  /* ===================== تحويلات ===================== */

  Map<String, dynamic> _toRemote(MaintenanceRequest r) {
    // نقرأ عبر dynamic لتجنب كسر الاستيراد إن تغيّر الموديل
    final d = r as dynamic;

    String s0(dynamic v) => (v ?? '').toString().trim();
    T? get<T>(T Function() f) {
      try {
        return f();
      } catch (_) {
        return null;
      }
    }

    // تواريخ كـ Timestamp (توافق Firestore)
    final DateTime? createdAt = get(() => d.createdAt) as DateTime?;
    final DateTime? scheduledAt = get(() => d.scheduledDate) as DateTime?;
    final DateTime? executionDeadline = get(() => d.executionDeadline) as DateTime?;
    final DateTime? completedAt = get(() => d.completedDate) as DateTime?;
    final DateTime? periodicCycleDate = get(() => d.periodicCycleDate) as DateTime?;

    String? enumName(dynamic v) {
      if (v == null) return null;
      try {
        final n = (v as dynamic).name;
        if (n is String && n.isNotEmpty) return n;
      } catch (_) {}
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    // الحقول
    final id = s0(get(() => d.id));
    final title = s0(get(() => d.title));
    final propertyId = s0(get(() => d.propertyId));
    final description = s0(get(() => d.description));
    final requestType = s0(get(() => d.requestType));
    final tenantId = s0(get(() => d.tenantId));
    final assignedTo = s0(get(() => d.assignedTo));
    final invoiceId = s0(get(() => d.invoiceId));
    final serialNo = s0(get(() => d.serialNo));
    final periodicServiceType = s0(get(() => d.periodicServiceType));
    final providerSnapshot = get(() => d.providerSnapshot);
    final rawAttachmentPaths = get(() => d.attachmentPaths);
    final attachmentPaths = rawAttachmentPaths is List
        ? rawAttachmentPaths
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];

    // أرقام
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    final double? cost = toDouble(get(() => d.cost));
    final bool? arch = get(() => d.isArchived) as bool?;

    final map = <String, dynamic>{
      'id': id.isEmpty ? null : id,
      'title': title.isEmpty ? null : title,
      'propertyId': propertyId.isEmpty ? null : propertyId,
      // ⚠️ وحّدنا المفتاح: نستخدم 'note' (نفس ما تستخدمه الشاشة). سنقرأ لاحقًا من note أو description.
      'note': description.isEmpty ? null : description,
      'requestType': requestType.isEmpty ? null : requestType,
      'tenantId': tenantId.isEmpty ? null : tenantId,
      'priority': enumName(get(() => d.priority)), // low/medium/high/urgent
      'status':
          enumName(get(() => d.status)), // open/inProgress/completed/canceled
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt) : null,
      'scheduledDate':
          scheduledAt != null ? Timestamp.fromDate(scheduledAt) : null,
      'executionDeadline': executionDeadline != null
          ? Timestamp.fromDate(executionDeadline)
          : null,
      'completedDate':
          completedAt != null ? Timestamp.fromDate(completedAt) : null,
      'assignedTo': assignedTo.isEmpty ? null : assignedTo,
      'providerSnapshot': providerSnapshot is Map
          ? Map<String, dynamic>.from(providerSnapshot)
          : null,
      'attachmentPaths': attachmentPaths,
      'cost': cost,
      'isArchived': arch,
      'invoiceId': invoiceId.isEmpty ? null : invoiceId,
      'serialNo': serialNo.isEmpty ? null : serialNo,
      'periodicServiceType':
          periodicServiceType.isEmpty ? null : periodicServiceType,
      'periodicCycleDate': periodicCycleDate != null
          ? Timestamp.fromDate(periodicCycleDate)
          : null,
      'isDeleted': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // أزل null أو سلاسل فارغة
    map.removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));
    return map;
  }

  MaintenanceRequest _fromRemote(Map<String, dynamic> m) {
    String s0(dynamic v) => (v ?? '').toString().trim();

    MaintenancePriority priorityOf(dynamic raw) {
      final s = s0(raw).toLowerCase();
      switch (s) {
        case 'low':
          return MaintenancePriority.low;
        case 'high':
          return MaintenancePriority.high;
        case 'urgent':
          return MaintenancePriority.urgent;
        case 'medium':
        default:
          return MaintenancePriority.medium;
      }
    }

    MaintenanceStatus statusOf(dynamic raw) {
      final s = s0(raw).toLowerCase();
      switch (s) {
        case 'inprogress':
          return MaintenanceStatus.inProgress;
        case 'completed':
          return MaintenanceStatus.completed;
        case 'canceled':
          return MaintenanceStatus.canceled;
        case 'open':
        default:
          return MaintenanceStatus.open;
      }
    }

    DateTime? toDate(dynamic v) {
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

    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
      return 0.0;
    }

    // نقرأ الوصف من 'note' أو 'description' للتوافق
    final desc = s0(m['note'] ?? m['description']);

    return MaintenanceRequest(
      id: s0(m['id']),
      propertyId: s0(m['propertyId']),
      tenantId: s0(m['tenantId']).isEmpty ? null : s0(m['tenantId']),
      title: s0(m['title']),
      description: desc,
      requestType:
          s0(m['requestType']).isEmpty ? 'خدمات' : s0(m['requestType']),
      priority: priorityOf(m['priority']),
      status: statusOf(m['status']),
      createdAt: toDate(m['createdAt']) ?? KsaTime.now(),
      scheduledDate: toDate(m['scheduledDate']),
      executionDeadline: toDate(m['executionDeadline']),
      completedDate: toDate(m['completedDate']),
      cost: toDouble(m['cost']),
      assignedTo: s0(m['assignedTo']).isEmpty ? null : s0(m['assignedTo']),
      providerSnapshot:
          (m['providerSnapshot'] as Map?)?.cast<String, dynamic>(),
      attachmentPaths:
          (m['attachmentPaths'] as List?)?.whereType<String>().toList() ??
              const <String>[],
      isArchived: (m['isArchived'] == true),
      invoiceId: s0(m['invoiceId']).isEmpty ? null : s0(m['invoiceId']),
      serialNo: s0(m['serialNo']).isEmpty ? null : s0(m['serialNo']),
      periodicServiceType: s0(m['periodicServiceType']).isEmpty
          ? null
          : s0(m['periodicServiceType']),
      periodicCycleDate: toDate(m['periodicCycleDate']),
    );
  }

  /* ===================== Helpers ===================== */

  static T? _safe<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  String _idOf(MaintenanceRequest r) {
    final d = r as dynamic;
    final v = _safe(() => d.id);
    return (v ?? '').toString();
  }

  String _titleOf(MaintenanceRequest r) {
    final d = r as dynamic;
    final v = _safe(() => d.title);
    return (v ?? '').toString();
  }

  Map<String, dynamic> _summaryFromRequest(MaintenanceRequest r) {
    final d = r as dynamic;
    return <String, dynamic>{
      'id': (d.id ?? '').toString(),
      'title': (d.title ?? '').toString(),
      'propertyId': (d.propertyId ?? '').toString(),
      'tenantId': (d.tenantId ?? '').toString(),
      'requestType': (d.requestType ?? '').toString(),
      'priority': (d.priority?.name ?? '').toString(),
      'status': (d.status?.name ?? '').toString(),
      'cost': d.cost,
      'attachmentPaths': d.attachmentPaths,
      'executionDeadline': d.executionDeadline?.toIso8601String(),
      'isArchived': d.isArchived == true,
      'invoiceId': (d.invoiceId ?? '').toString(),
      'serialNo': (d.serialNo ?? '').toString(),
      'periodicServiceType': (d.periodicServiceType ?? '').toString(),
      'periodicCycleDate': d.periodicCycleDate?.toIso8601String(),
      'isDeleted': false,
    };
  }

  Map<String, dynamic> _summaryFromMap(Map<String, dynamic> m) {
    return <String, dynamic>{
      'id': (m['id'] ?? '').toString(),
      'title': (m['title'] ?? '').toString(),
      'propertyId': (m['propertyId'] ?? '').toString(),
      'tenantId': (m['tenantId'] ?? '').toString(),
      'requestType': (m['requestType'] ?? '').toString(),
      'priority': (m['priority'] ?? '').toString(),
      'status': (m['status'] ?? '').toString(),
      'cost': m['cost'],
      'attachmentPaths': (m['attachmentPaths'] as List?)?.whereType<String>().toList() ?? const <String>[],
      'executionDeadline': m['executionDeadline']?.toString(),
      'isArchived': m['isArchived'] == true,
      'invoiceId': (m['invoiceId'] ?? '').toString(),
      'serialNo': (m['serialNo'] ?? '').toString(),
      'periodicServiceType': (m['periodicServiceType'] ?? '').toString(),
      'periodicCycleDate': m['periodicCycleDate']?.toString(),
      'isDeleted': m['isDeleted'] == true,
    };
  }
}



