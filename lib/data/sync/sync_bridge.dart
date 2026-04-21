// lib/data/sync/sync_bridge.dart
//
// مزامنة ثنائية الاتجاه Firestore <-> Hive.
// مطابق تمامًا لموديلات المشروع الحالي:
//
// - Tenant: fullName, nationalId, phone, email? (+ كل الحقول الاختيارية)
// - Property: name, address, type, rentalMode?, totalUnits, occupiedUnits,
//             parentBuildingId?, area?, floors?, rooms?, price?, currency?, description?
// - Contract: tenantId, propertyId, startDate, endDate, rentAmount, totalAmount, isTerminated?, notes?, serialNo?, isArchived?
// - Invoice: tenantId, contractId, propertyId, issueDate, dueDate, amount, paidAmount, currency,
//            paymentMethod, isArchived, isCanceled, serialNo(String?), note?, createdAt, updatedAt
// - MaintenanceRequest: propertyId, tenantId?, title, (note/description), requestType?,
//                       priority, status, createdAt, scheduledDate?, completedDate?,
//                       assignedTo?, cost, isArchived, invoiceId?
//
// يكسر حلقة المزامنة عبر _muted. يعتمد عمليًا على آخر كتابة للـ serverTimestamp.
// ملاحظة: الأفضل تخزين العناصر في Hive بمفتاح = id (put(id, value)).
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

// موديلات وصناديق
import '../../data/constants/boxes.dart';
import '../../ui/invoices_screen.dart' show Invoice;
import '../../models/tenant.dart' show Tenant;
import '../../models/property.dart' show Property, PropertyType, RentalMode;
// ✅ اجعل الاستيراد يصرّح بالأنواع/التعدادات اللازمة
import '../../ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle, AdvanceMode, SaTimeLite;

import '../../ui/maintenance_screen.dart'
    show MaintenanceRequest, MaintenancePriority, MaintenanceStatus;

// لتسمية الصناديق باسم يحتوي uid
import '../services/user_scope.dart' as scope;
// لضمان فتح الصناديق قبل الاستماع
import '../services/hive_service.dart';
import '../services/entity_audit_service.dart';

typedef BoxGetter<T> = Box<T> Function();
typedef FromMap<T> = T Function(String id, Map<String, dynamic> m);
typedef ToMap<T> = Map<String, dynamic> Function(T value);
typedef IdOf<T> = String Function(T value);

class _AttachmentSyncResult {
  _AttachmentSyncResult({required this.map});
  final Map<String, dynamic> map;
  final Map<String, List<String>> normalized = <String, List<String>>{};
  final Set<String> localFilesToDelete = <String>{};
}

class GenericSyncBridge<T> {
  GenericSyncBridge({
    required this.collectionName,
    required this.box,
    required this.fromMap,
    required this.toMap,
    required this.idOf,
    this.softDeleteField = 'isDeleted',
    this.attachmentFields = const <String>[],
    this.attachmentStorageDir,
  });

  final String collectionName;
  final BoxGetter<T> box;
  final FromMap<T> fromMap;
  final ToMap<T> toMap;
  final IdOf<T> idOf;
  final String softDeleteField;
  final List<String> attachmentFields;
  final String? attachmentStorageDir;

  StreamSubscription? _fsSub;
  StreamSubscription? _hiveSub;
  bool _muted = false;
  bool _started = false;
  bool _permissionDenied = false;
  final Set<String> _knownIds = <String>{};

  // نحتفظ بالـ UID الذي بُدئ به الجسر لضمان الكتابة/القراءة لنفس المسار
  String _uidAtStart = '';
  bool _scopeRecoveryAttempted = false;
  bool _scopeRecoveryInProgress = false;

  CollectionReference<Map<String, dynamic>> _colFor(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(collectionName)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
          toFirestore: (m, _) => m,
        );
  }

  String get _entityType {
    switch (collectionName) {
      case 'properties':
        return 'property';
      case 'tenants':
        return 'tenant';
      case 'contracts':
        return 'contract';
      case 'invoices':
        return 'invoice';
      case 'maintenance':
        return 'maintenance';
      default:
        return collectionName;
    }
  }

  Map<String, dynamic> _pickSummary(
      Map<String, dynamic> src, String id, List<String> keys) {
    final out = <String, dynamic>{'id': id};
    for (final key in keys) {
      if (src.containsKey(key)) out[key] = src[key];
    }
    return out;
  }

  void _trace(String message) {
    debugPrint('[SyncBridge:$collectionName] $message');
  }

  bool _isRemoteAttachmentPath(String v) {
    final s = v.trim().toLowerCase();
    return s.startsWith('https://') ||
        s.startsWith('http://') ||
        s.startsWith('gs://');
  }

  bool _isLikelyLocalAttachmentPath(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    if (_isRemoteAttachmentPath(s)) return false;
    if (s.startsWith('/') || s.startsWith(r'\')) return true;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s)) return true;
    return false;
  }

  Future<String?> _uploadLocalAttachment({
    required String docId,
    required String localPath,
  }) async {
    if (attachmentStorageDir == null || attachmentStorageDir!.trim().isEmpty) {
      return null;
    }
    final f = File(localPath);
    if (!f.existsSync()) return null;
    final ext = () {
      final dot = f.path.lastIndexOf('.');
      if (dot <= 0 || dot >= f.path.length - 1) return '';
      final e = f.path.substring(dot + 1).toLowerCase();
      if (e.length > 8) return '';
      return '.$e';
    }();
    final fileName = '${KsaTime.now().microsecondsSinceEpoch}$ext';
    final ref = FirebaseStorage.instance
        .ref()
        .child('users')
        .child(_uidAtStart)
        .child(attachmentStorageDir!)
        .child(docId)
        .child(fileName);
    await ref.putFile(f);
    return ref.getDownloadURL();
  }

  Future<_AttachmentSyncResult> _syncAttachmentFields({
    required String docId,
    required Map<String, dynamic> map,
  }) async {
    final result = _AttachmentSyncResult(map: map);
    if (attachmentFields.isEmpty) return result;

    for (final field in attachmentFields) {
      final raw = map[field];
      final list = (raw is List)
          ? raw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      if (list.isEmpty) {
        map[field] = <String>[];
        continue;
      }

      final next = <String>[];
      for (final entry in list) {
        if (_isRemoteAttachmentPath(entry)) {
          next.add(entry);
          continue;
        }
        if (!_isLikelyLocalAttachmentPath(entry)) {
          continue;
        }
        try {
          final uploaded = await _uploadLocalAttachment(docId: docId, localPath: entry);
          if (uploaded != null && uploaded.isNotEmpty) {
            next.add(uploaded);
            result.localFilesToDelete.add(entry);
          } else {
            next.add(entry);
          }
        } catch (e) {
          _trace('attachment-upload-failed id=$docId field=$field path=$entry err=$e');
          next.add(entry);
        }
      }
      map[field] = next;
      result.normalized[field] = List<String>.from(next);
    }
    return result;
  }

  Future<void> _deleteRemovedRemoteAttachments({
    required CollectionReference<Map<String, dynamic>> col,
    required String docId,
    required Map<String, dynamic> nextMap,
  }) async {
    if (attachmentFields.isEmpty) return;
    try {
      final existing = await col.doc(docId).get();
      final current = existing.data() ?? const <String, dynamic>{};
      for (final field in attachmentFields) {
        final oldList = ((current[field] as List?) ?? const [])
            .whereType<String>()
            .map((e) => e.trim())
            .where(_isRemoteAttachmentPath)
            .toSet();
        final newList = ((nextMap[field] as List?) ?? const [])
            .whereType<String>()
            .map((e) => e.trim())
            .where(_isRemoteAttachmentPath)
            .toSet();
        final removed = oldList.difference(newList);
        for (final url in removed) {
          try {
            await FirebaseStorage.instance.refFromURL(url).delete();
          } catch (e) {
            _trace('attachment-delete-remote-failed id=$docId field=$field url=$url err=$e');
          }
        }
      }
    } catch (e) {
      _trace('attachment-load-remote-before-diff-failed id=$docId err=$e');
    }
  }

  void _applyAttachmentListsToEntity(T entity, Map<String, List<String>> normalized) {
    if (normalized.isEmpty) return;
    if (entity is Tenant) {
      final v = normalized['attachmentPaths'];
      if (v != null) {
        entity.attachmentPaths = List<String>.from(v);
      }
      return;
    }
    if (entity is Invoice) {
      final v = normalized['attachmentPaths'];
      if (v != null) {
        entity.attachmentPaths = List<String>.from(v);
      }
      return;
    }
    if (entity is MaintenanceRequest) {
      final v = normalized['attachmentPaths'];
      if (v != null) {
        entity.attachmentPaths = List<String>.from(v);
      }
      return;
    }
    if (entity is Contract) {
      final v = normalized['attachmentPaths'];
      if (v != null) {
        entity.attachmentPaths = List<String>.from(v);
      }
      return;
    }
    if (entity is Property) {
      final v = normalized['documentAttachmentPaths'];
      if (v != null) {
        entity.documentAttachmentPaths = List<String>.from(v);
        entity.documentAttachmentPath = v.isNotEmpty ? v.first : null;
      }
    }
  }

  Future<void> _tryRecoverScopeAfterPermissionDenied() async {
    if (_scopeRecoveryInProgress || _scopeRecoveryAttempted) return;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isEmpty) return;
    if (_uidAtStart == authUid) return;
    _scopeRecoveryAttempted = true;
    _scopeRecoveryInProgress = true;
    try {
      _trace(
        'permission-denied: attempting scope recovery oldScope=$_uidAtStart authUid=$authUid',
      );
      scope.setFixedUid(authUid);
      await stop();
      await start();
      _trace('permission-denied: scope recovery completed newScope=$authUid');
    } catch (e, st) {
      _trace('permission-denied: scope recovery failed err=$e');
      debugPrintStack(stackTrace: st);
    } finally {
      _scopeRecoveryInProgress = false;
    }
  }

  Map<String, dynamic> _activitySummary(Map<String, dynamic> m, String id) {
    switch (_entityType) {
      case 'property':
        return _pickSummary(m, id, [
          'name',
          'address',
          'type',
          'rentalMode',
          'totalUnits',
          'occupiedUnits',
          'isArchived',
          'isDeleted',
        ]);
      case 'tenant':
        return _pickSummary(m, id, [
          'fullName',
          'nationalId',
          'phone',
          'email',
          'clientType',
          'isArchived',
          'isBlacklisted',
          'activeContractsCount',
          'isDeleted',
        ]);
      case 'contract':
        return _pickSummary(m, id, [
          'serialNo',
          'tenantId',
          'propertyId',
          'startDate',
          'endDate',
          'rentAmount',
          'totalAmount',
          'currency',
          'term',
          'paymentCycle',
          'advanceMode',
          'isTerminated',
          'isArchived',
          'isDeleted',
        ]);
      case 'invoice':
        return _pickSummary(m, id, [
          'serialNo',
          'tenantId',
          'contractId',
          'propertyId',
          'issueDate',
          'dueDate',
          'amount',
          'paidAmount',
          'currency',
          'paymentMethod',
          'isArchived',
          'isCanceled',
          'isDeleted',
        ]);
      case 'maintenance':
        return _pickSummary(m, id, [
          'serialNo',
          'title',
          'propertyId',
          'tenantId',
          'priority',
          'status',
          'cost',
          'isArchived',
          'invoiceId',
          'isDeleted',
        ]);
      default:
        return _pickSummary(m, id, const []);
    }
  }

  String _entityName(Map<String, dynamic> m, String id) {
    if (_entityType == 'property') return (m['name'] ?? id).toString();
    if (_entityType == 'tenant') return (m['fullName'] ?? id).toString();
    if (_entityType == 'contract') return (m['serialNo'] ?? id).toString();
    if (_entityType == 'invoice') return (m['serialNo'] ?? id).toString();
    if (_entityType == 'maintenance') return (m['title'] ?? id).toString();
    return id;
  }

  void _logAction({
    required String actionType,
    required String entityId,
    required String entityName,
    Map<String, dynamic>? newData,
  }) {
    // Activity log disabled by product request.
  }

  Future<bool> _isAllowedScopedUid(String authUid, String scopedUid) async {
    var claimOfficeId = '';
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      final claims = token?.claims ?? const <String, dynamic>{};
      claimOfficeId =
          (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
    } catch (_) {}
    if (claimOfficeId.isNotEmpty && claimOfficeId == scopedUid) return true;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUid)
          .get();
      final map = doc.data() ?? const <String, dynamic>{};
      final docOfficeId =
          (map['officeId'] ?? map['office_id'] ?? '').toString().trim();
      if (docOfficeId.isNotEmpty && docOfficeId == scopedUid) return true;
    } catch (_) {}

    try {
      final directClientDoc = await FirebaseFirestore.instance
          .collection('offices')
          .doc(authUid)
          .collection('clients')
          .doc(scopedUid)
          .get();
      if (directClientDoc.exists) return true;
    } catch (_) {}

    try {
      final q = await FirebaseFirestore.instance
          .collection('offices')
          .doc(authUid)
          .collection('clients')
          .where('clientUid', isEqualTo: scopedUid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  Future<void> start() async {
    if (_started) return;
    _permissionDenied = false;
    _scopeRecoveryAttempted = false;

    await HiveService.ensureReportsBoxesOpen();

    // ❌ لا تبدأ على "guest"
    if (scope.isGuest()) {
      // لا يوجد مستخدم فعلي ولا انتحال محدد → لا مزامنة
      return;
    }
    // ✅ استخدم الـ UID الفعّال (انتحال إن وُجد، وإلا UID Firebase الحالي)
    var uid = scope.uidOrThrow();
    if (uid.isEmpty) return;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isNotEmpty && authUid != uid) {
      final allowOfficeWorkspace = await _isAllowedScopedUid(authUid, uid);
      _trace(
        'uid-mismatch authUid=$authUid effectiveUid=$uid allowOfficeWorkspace=$allowOfficeWorkspace',
      );
      if (!allowOfficeWorkspace) {
        if (authUid.isEmpty) {
          _trace('uid-mismatch: sync bridge disabled (auth uid empty)');
          return;
        }
        _trace('uid-mismatch: forcing scope to authUid=$authUid');
        scope.setFixedUid(authUid);
        uid = authUid;
      }
    }

    _uidAtStart = uid;

    final col = _colFor(_uidAtStart);
    final bx = box();
    _knownIds
      ..clear()
      ..addAll(bx.keys.map((e) => e.toString()));

    // Firestore -> Hive
    _fsSub = col.snapshots().listen(
      (snap) async {
        if (_permissionDenied) return;
        try {
          for (final ch in snap.docChanges) {
            final doc = ch.doc;
            final data = doc.data();
            final id = doc.id;

            final deletedHard =
                (data == null) || (ch.type == DocumentChangeType.removed);
            final deletedSoft =
                (data != null && (data[softDeleteField] == true));

            if (deletedHard || deletedSoft) {
              _muted = true;
              try {
                if (bx.containsKey(id)) {
                  await bx.delete(id);
                }
                _knownIds.remove(id);
              } finally {
                _muted = false;
              }
              continue;
            }

            final model = fromMap(id, data);
            _muted = true;
            try {
              await bx.put(idOf(model), model);
              _knownIds.add(id);
            } finally {
              _muted = false;
            }
          }
        } on FirebaseException catch (e, st) {
          _trace(
              'remote-listen-callback-failed code=${e.code} msg=${e.message}');
          if (e.code == 'permission-denied') {
            _permissionDenied = true;
            _trace('permission-denied: remote listener disabled');
            unawaited(_tryRecoverScopeAfterPermissionDenied());
          }
          debugPrintStack(stackTrace: st);
        } catch (e, st) {
          _trace('remote-listen-callback-failed err=$e');
          debugPrintStack(stackTrace: st);
        }
      },
      onError: (Object error, StackTrace st) {
        final code = error is FirebaseException ? error.code : '';
        _trace('remote-listen-error code=$code err=$error');
        if (code == 'permission-denied') {
          _permissionDenied = true;
          _trace('permission-denied: remote listener disabled');
          unawaited(_tryRecoverScopeAfterPermissionDenied());
        }
        debugPrintStack(stackTrace: st);
      },
    );

    // Hive -> Firestore
    _hiveSub = bx.watch().listen(
      (evt) async {
        if (_muted) return;
        try {
          final keyStr = evt.key?.toString();
          final val = (keyStr != null) ? bx.get(keyStr) : null;

          // حذف
          if (evt.deleted == true) {
            if (keyStr == null) return;
            await EntityAuditService.instance.recordLocalAudit(
              workspaceUid: scope.effectiveUid(),
              collectionName: collectionName,
              entityId: keyStr,
              isCreate: false,
            );
            if (_permissionDenied) {
              _trace(
                  'permission-denied: cached local delete-audit only id=$keyStr');
              _knownIds.remove(keyStr);
              return;
            }
            final deleteAudit =
                await EntityAuditService.instance.buildWriteAuditFields(
              isCreate: false,
              workspaceUid: scope.effectiveUid(),
            );
            final deletePayload = <String, dynamic>{
              'id': keyStr,
              softDeleteField: true,
              'updatedAt': FieldValue.serverTimestamp(),
            }..addAll(deleteAudit);
            await col.doc(keyStr).set(deletePayload, SetOptions(merge: true));
            _knownIds.remove(keyStr);
            _logAction(
              actionType: 'delete',
              entityId: keyStr,
              entityName: keyStr,
              newData: const <String, dynamic>{'isDeleted': true},
            );
            return;
          }

          if (val == null) return;

          // إضافة/تحديث
          final docId = idOf(val);
          final existedBefore = _knownIds.contains(docId);
          final map = toMap(val)
            ..['id'] = docId
            ..['updatedAt'] = FieldValue.serverTimestamp()
            ..[softDeleteField] = false;
          final attachmentSync =
              await _syncAttachmentFields(docId: docId, map: map);
          await EntityAuditService.instance.recordLocalAudit(
            workspaceUid: scope.effectiveUid(),
            collectionName: collectionName,
            entityId: docId,
            isCreate: !existedBefore,
          );
          if (_permissionDenied) {
            _trace(
                'permission-denied: cached local upsert-audit only id=$docId');
            _knownIds.add(docId);
            return;
          }
          map.addAll(await EntityAuditService.instance.buildWriteAuditFields(
            isCreate: !existedBefore,
            workspaceUid: scope.effectiveUid(),
          ));

          map.removeWhere((k, v) => v == null);
          await _deleteRemovedRemoteAttachments(
            col: col,
            docId: docId,
            nextMap: map,
          );
          await col.doc(docId).set(map, SetOptions(merge: true));
          if (attachmentSync.normalized.isNotEmpty) {
            _muted = true;
            try {
              _applyAttachmentListsToEntity(val, attachmentSync.normalized);
              if ((val as dynamic).key == null) {
                await bx.put(docId, val);
              } else {
                await (val as dynamic).save();
              }
            } catch (e) {
              _trace('attachment-local-model-update-failed id=$docId err=$e');
            } finally {
              _muted = false;
            }
          }
          for (final path in attachmentSync.localFilesToDelete) {
            try {
              final f = File(path);
              if (f.existsSync()) {
                await f.delete();
              }
            } catch (_) {}
          }
          _knownIds.add(docId);
          final summary = _activitySummary(map, docId);
          _logAction(
            actionType: existedBefore ? 'update' : 'create',
            entityId: docId,
            entityName: _entityName(summary, docId),
            newData: summary,
          );
        } on FirebaseException catch (e, st) {
          _trace('local-write-failed code=${e.code} msg=${e.message}');
          if (e.code == 'permission-denied') {
            _permissionDenied = true;
            _trace('permission-denied: local->remote sync paused');
            unawaited(_tryRecoverScopeAfterPermissionDenied());
          }
          debugPrintStack(stackTrace: st);
        } catch (e, st) {
          _trace('local-write-failed err=$e');
          debugPrintStack(stackTrace: st);
        }
      },
      onError: (Object error, StackTrace st) {
        final code = error is FirebaseException ? error.code : '';
        _trace('local-watch-error code=$code err=$error');
        if (code == 'permission-denied') {
          _permissionDenied = true;
          _trace('permission-denied: local->remote sync paused');
          unawaited(_tryRecoverScopeAfterPermissionDenied());
        }
        debugPrintStack(stackTrace: st);
      },
    );

    _started = true;
  }

  Future<void> stop() async {
    await _fsSub?.cancel();
    await _hiveSub?.cancel();
    _fsSub = null;
    _hiveSub = null;
    _permissionDenied = false;
    _uidAtStart = '';
    _started = false;
  }
}

// =================== جسور الكيانات ===================

// 1) الفواتير
class SyncBridgeInvoices extends GenericSyncBridge<Invoice> {
  SyncBridgeInvoices()
      : super(
          collectionName: 'invoices',
          box: () => Hive.box<Invoice>(scope.boxName(kInvoicesBox)),
          idOf: (inv) => inv.id,
          attachmentFields: const <String>['attachmentPaths'],
          attachmentStorageDir: 'invoice_attachments',
          toMap: (inv) {
            final paid = !inv.isCanceled &&
                inv.paidAmount >= (inv.amount.abs() - 0.000001);
            final m = <String, dynamic>{
              'tenantId': inv.tenantId,
              'contractId': inv.contractId,
              'propertyId': inv.propertyId,
              'issueDate': inv.issueDate.millisecondsSinceEpoch,
              'dueDate': inv.dueDate.millisecondsSinceEpoch,
              'amount': inv.amount,
              'paidAmount': inv.paidAmount, // مهم
              'paidAt': paid ? inv.issueDate.millisecondsSinceEpoch : null,
              'paymentDate': paid ? inv.issueDate.millisecondsSinceEpoch : null,
              'remainingAmount': (inv.amount.abs() - inv.paidAmount).clamp(0.0, double.infinity),
              'currency': inv.currency,
              'paymentMethod': inv.paymentMethod,
              'maintenanceRequestId': inv.maintenanceRequestId,
              'maintenanceSnapshot': inv.maintenanceSnapshot,
              'waterAmount': inv.waterAmount,
              'isArchived': inv.isArchived == true,
              'isCanceled': inv.isCanceled == true,
              'serialNo': inv.serialNo, // String? ← مهم
              'note': inv.note,
              'attachmentPaths': inv.attachmentPaths,
              'createdAt': inv.createdAt.millisecondsSinceEpoch,
              'updatedAt': inv.updatedAt.millisecondsSinceEpoch,
            };
            m.removeWhere((k, v) => v == null);
            return m;
          },
          fromMap: (id, m) {
            final amount = _toD(m['amount']);
            final paidDate = _toDate(m['paidAt']) ??
                _toDate(m['paid_on']) ??
                _toDate(m['paymentDate']) ??
                _toDate(m['paidDate']);
            final rawPaidAmount = _toD(m['paidAmount']);
            final paidAmount = rawPaidAmount > 0
                ? rawPaidAmount
                : (((m['isCanceled'] == true) || paidDate == null)
                    ? 0.0
                    : amount.abs());
            return Invoice(
            id: id,
            tenantId: (m['tenantId'] ?? '').toString(),
            contractId: (m['contractId'] ?? '').toString(),
            propertyId: (m['propertyId'] ?? '').toString(),
            issueDate: _toDate(m['issueDate']) ?? KsaTime.now(),
            dueDate: _toDate(m['dueDate']) ?? _todayEnd(),
            amount: amount,
            paidAmount: paidAmount,
            currency: (m['currency'] ?? 'SAR').toString(),
            paymentMethod: (m['paymentMethod'] as String?) ?? 'نقدًا',
            maintenanceRequestId: (m['maintenanceRequestId'] == null)
                ? null
                : m['maintenanceRequestId'].toString(),
            maintenanceSnapshot: (m['maintenanceSnapshot'] as Map?)
                ?.cast<String, dynamic>(),
            waterAmount: _toD(m['waterAmount']),
            isArchived: (m['isArchived'] == true),
            isCanceled: (m['isCanceled'] == true),
            serialNo: (m['serialNo'] == null) ? null : m['serialNo'].toString(),
            note: (m['note'] as String?),
            attachmentPaths: (() {
              final remote = (m['attachmentPaths'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  <String>[];
              if (remote.isNotEmpty) return remote;
              try {
                final b = Hive.box<Invoice>(scope.boxName(kInvoicesBox));
                final local = b.get(id)?.attachmentPaths ?? const <String>[];
                return local.where((e) => e.trim().isNotEmpty).toList();
              } catch (_) {
                return <String>[];
              }
            })(),
            createdAt: _toDate(m['createdAt']) ?? KsaTime.now(),
            updatedAt: _toDate(m['updatedAt']) ?? KsaTime.now(),
          );
          },
        );
}

// 2) المستأجرون
class SyncBridgeTenants extends GenericSyncBridge<Tenant> {
  SyncBridgeTenants()
      : super(
          collectionName: 'tenants',
          box: () => Hive.box<Tenant>(scope.boxName(kTenantsBox)),
          idOf: (t) => t.id,
          attachmentFields: const <String>['attachmentPaths'],
          attachmentStorageDir: 'tenant_attachments',
          toMap: (t) => {
            'fullName': t.fullName,
            'nationalId': t.nationalId,
            'phone': t.phone,
            'email': t.email,
            'dateOfBirth': t.dateOfBirth?.millisecondsSinceEpoch,
            'clientType': t.clientType,
            'nationality': t.nationality,
            'idExpiry': t.idExpiry?.millisecondsSinceEpoch,
            'addressLine': t.addressLine,
            'city': t.city,
            'region': t.region,
            'postalCode': t.postalCode,
            'emergencyName': t.emergencyName,
            'emergencyPhone': t.emergencyPhone,
            'notes': t.notes,
            'tags': t.tags,
            'tenantBankName': t.tenantBankName,
            'tenantBankAccountNumber': t.tenantBankAccountNumber,
            'tenantTaxNumber': t.tenantTaxNumber,
            'companyName': t.companyName,
            'companyCommercialRegister': t.companyCommercialRegister,
            'companyTaxNumber': t.companyTaxNumber,
            'companyRepresentativeName': t.companyRepresentativeName,
            'companyRepresentativePhone': t.companyRepresentativePhone,
            'companyBankAccountNumber': t.companyBankAccountNumber,
            'companyBankName': t.companyBankName,
            'serviceSpecialization': t.serviceSpecialization,
            'attachmentPaths': t.attachmentPaths,
            'isArchived': t.isArchived,
            'isBlacklisted': t.isBlacklisted,
            'blacklistReason': t.blacklistReason,
            'activeContractsCount': t.activeContractsCount,
            'createdAt': t.createdAt.millisecondsSinceEpoch,
          },
          fromMap: (id, m) => Tenant(
            id: id,
            fullName: (m['fullName'] ?? '') as String,
            nationalId: (m['nationalId'] ?? '') as String,
            phone: (m['phone'] ?? '') as String,
            email: (m['email'] as String?),
            dateOfBirth: _toDate(m['dateOfBirth']),
            clientType: (m['clientType'] as String?)?.trim().isNotEmpty == true
                ? (m['clientType'] as String).trim()
                : 'tenant',
            nationality: (m['nationality'] as String?),
            idExpiry: _toDate(m['idExpiry']),
            addressLine: (m['addressLine'] as String?),
            city: (m['city'] as String?),
            region: (m['region'] as String?),
            postalCode: (m['postalCode'] as String?),
            emergencyName: (m['emergencyName'] as String?),
            emergencyPhone: (m['emergencyPhone'] as String?),
            notes: (m['notes'] == null) ? null : m['notes'].toString(),
            tags: (m['tags'] as List?)?.whereType<String>().toList() ??
                const <String>[],
            tenantBankName: (m['tenantBankName'] as String?),
            tenantBankAccountNumber: (m['tenantBankAccountNumber'] as String?),
            tenantTaxNumber: (m['tenantTaxNumber'] as String?),
            companyName: (m['companyName'] as String?),
            companyCommercialRegister:
                (m['companyCommercialRegister'] as String?),
            companyTaxNumber: (m['companyTaxNumber'] as String?),
            companyRepresentativeName:
                (m['companyRepresentativeName'] as String?),
            companyRepresentativePhone:
                (m['companyRepresentativePhone'] as String?),
            companyBankAccountNumber:
                (m['companyBankAccountNumber'] as String?),
            companyBankName: (m['companyBankName'] as String?),
            serviceSpecialization: (m['serviceSpecialization'] as String?),
            attachmentPaths:
                (m['attachmentPaths'] as List?)?.whereType<String>().toList() ??
                    const <String>[],
            isArchived: (m['isArchived'] == true),
            isBlacklisted: (m['isBlacklisted'] == true),
            blacklistReason: (m['blacklistReason'] as String?),
            activeContractsCount: (m['activeContractsCount'] is int)
                ? m['activeContractsCount'] as int
                : int.tryParse('${m['activeContractsCount'] ?? 0}') ?? 0,
            createdAt: _toDate(m['createdAt']),
            updatedAt: _toDate(m['updatedAt']),
          ),
        );
}

// 3) العقارات
class SyncBridgeProperties extends GenericSyncBridge<Property> {
  SyncBridgeProperties()
      : super(
          collectionName: 'properties',
          box: () => Hive.box<Property>(scope.boxName(kPropertiesBox)),
          idOf: (p) => p.id,
          attachmentFields: const <String>['documentAttachmentPaths'],
          attachmentStorageDir: 'property_documents',
          toMap: (p) {
            final m = <String, dynamic>{
              'name': p.name,
              'address': p.address,
              'type': p.type.name,
              'rentalMode': p.rentalMode?.name,
              'totalUnits': p.totalUnits,
              'occupiedUnits': p.occupiedUnits,
              'parentBuildingId': p.parentBuildingId,
              'area': p.area,
              'floors': p.floors,
              'rooms': p.rooms,
              'price': p.price,
              'currency': p.currency,
              'description': p.description,
              'isArchived': p.isArchived == true,
              'documentType': p.documentType,
              'documentNumber': p.documentNumber,
              'documentDate': p.documentDate?.millisecondsSinceEpoch,
              'documentAttachmentPath': p.documentAttachmentPath,
              'documentAttachmentPaths':
                  p.documentAttachmentPaths ?? const <String>[],
              'electricityNumber': p.electricityNumber,
              'electricityMode': p.electricityMode,
              'electricityShare': p.electricityShare,
              'waterNumber': p.waterNumber,
              'waterMode': p.waterMode,
              'waterShare': p.waterShare,
              'waterAmount': p.waterAmount,

              // 👇 الجديد:
              'createdAt': p.createdAt?.millisecondsSinceEpoch,
              'updatedAt': p.updatedAt?.millisecondsSinceEpoch,
            };
            m.removeWhere((k, v) => v == null);
            return m;
          },
          fromMap: (id, m) {
            final name = (m['name'] ?? '') as String;
            final address = (m['address'] ?? '') as String;
            final typeStr = m['type'];
            final modeStr = m['rentalMode'];

            return Property(
              id: id,
              name: name.isEmpty ? 'بدون اسم' : name,
              address: address,
              type: _enumByName<PropertyType>(typeStr, PropertyType.values,
                  fallback: PropertyType.apartment),
              rentalMode: _enumByName<RentalMode>(modeStr, RentalMode.values),
              totalUnits: _toInt(m['totalUnits']) ?? 0,
              occupiedUnits: _toInt(m['occupiedUnits']) ?? 0,
              parentBuildingId: (m['parentBuildingId'] as String?),
              area: (m['area'] == null) ? null : (_toD(m['area'])),
              floors: _toInt(m['floors']),
              rooms: _toInt(m['rooms']),
              price: (m['price'] == null) ? null : (_toD(m['price'])),
              currency: (m['currency'] ?? 'SAR').toString(),
              description: (m['description'] as String?),
              isArchived: (m['isArchived'] == true),
              documentType: (m['documentType'] as String?),
              documentNumber: (m['documentNumber'] as String?),
              documentDate: _toDate(m['documentDate']),
              documentAttachmentPath: (m['documentAttachmentPath'] as String?),
              documentAttachmentPaths: (m['documentAttachmentPaths'] as List?)
                  ?.whereType<String>()
                  .toList(),
              electricityNumber: (m['electricityNumber'] as String?),
              electricityMode: (m['electricityMode'] as String?),
              electricityShare: (m['electricityShare'] as String?),
              waterNumber: (m['waterNumber'] as String?),
              waterMode: (m['waterMode'] as String?),
              waterShare: (m['waterShare'] as String?),
              waterAmount: (m['waterAmount'] as String?),

              // 👇 الجديد:
              createdAt: _toDate(m['createdAt']),
              updatedAt: _toDate(m['updatedAt']),
            );
          },
        );
}

// 4) العقود
class SyncBridgeContracts extends GenericSyncBridge<Contract> {
  SyncBridgeContracts()
      : super(
          collectionName: 'contracts',
          box: () => Hive.box<Contract>(scope.boxName(kContractsBox)),
          idOf: (c) => c.id,
          attachmentFields: const <String>['attachmentPaths'],
          attachmentStorageDir: 'contract_attachments',
          toMap: (c) {
            final m = <String, dynamic>{
              'tenantId': c.tenantId,
              'propertyId': c.propertyId,
              'startDate': c.startDate.millisecondsSinceEpoch,
              'endDate': c.endDate.millisecondsSinceEpoch,

              // مبالغ
              'rentAmount': c.rentAmount,
              'totalAmount': c.totalAmount,

              // حقول إضافية
              'currency': c.currency,
              'term': c.term.index,
              'termYears': c.termYears,
              'paymentCycle': c.paymentCycle.index,
              'paymentCycleYears': c.paymentCycleYears,
              'advanceMode': c.advanceMode.index,
              'advancePaid': c.advancePaid,
              'dailyCheckoutHour': c.dailyCheckoutHour,

              // ملاحظات/حالة
              'isTerminated': c.isTerminated == true,
              'terminatedAt': c.terminatedAt?.millisecondsSinceEpoch,
              'notes': c.notes,
              'attachmentPaths': c.attachmentPaths,
              'serialNo': c.serialNo,
              'ejarContractNo': c.ejarContractNo,
              'isArchived': c.isArchived == true,
              'tenantSnapshot': c.tenantSnapshot,
              'propertySnapshot': c.propertySnapshot,
              'buildingSnapshot': c.buildingSnapshot,

              // طوابع زمنية
              'createdAt': c.createdAt.millisecondsSinceEpoch,
              'updatedAt': c.updatedAt.millisecondsSinceEpoch,
            };
            m.removeWhere((k, v) => v == null);
            return m;
          },
          fromMap: (id, m) => Contract(
            id: id,
            tenantId: (m['tenantId'] ?? '').toString(),
            propertyId: (m['propertyId'] ?? '').toString(),
            startDate: _toDate(m['startDate']) ?? KsaTime.now(),
            endDate: _toDate(m['endDate']) ?? _todayEnd(),

            // مبالغ
            rentAmount: _toD(m['rentAmount']),
            totalAmount: _toD(m['totalAmount']),

            // افتراضات معقولة عند غياب القيم
            currency: (m['currency'] ?? 'SAR').toString(),
            term: (() {
              final i = _toEnumIndex(m['term'], ContractTerm.values);
              if (i != null) return ContractTerm.values[i];
              return ContractTerm.monthly;
            })(),
            termYears: _toInt(m['termYears']) ?? 1,
            paymentCycle: (() {
              final i = _toEnumIndex(m['paymentCycle'], PaymentCycle.values);
              if (i != null) return PaymentCycle.values[i];
              return PaymentCycle.monthly;
            })(),
            paymentCycleYears: _toInt(m['paymentCycleYears']) ?? 1,
            advanceMode: (() {
              final i = _toEnumIndex(m['advanceMode'], AdvanceMode.values);
              if (i != null) return AdvanceMode.values[i];
              return AdvanceMode.none;
            })(),
            advancePaid: m['advancePaid'] == null ? null : _toD(m['advancePaid']),
            dailyCheckoutHour: _toInt(m['dailyCheckoutHour']),

            // ملاحظات/حالة
            isTerminated: (m['isTerminated'] == true),
            terminatedAt: _toDate(m['terminatedAt']),
            notes: (m['notes'] == null) ? null : m['notes'].toString(),
            attachmentPaths: (m['attachmentPaths'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                const <String>[],
            serialNo: (m['serialNo'] == null) ? null : m['serialNo'].toString(),
            ejarContractNo: (m['ejarContractNo'] == null)
                ? null
                : m['ejarContractNo'].toString(),
            isArchived: (m['isArchived'] == true),
            tenantSnapshot: (m['tenantSnapshot'] is Map)
                ? Map<String, dynamic>.from(m['tenantSnapshot'] as Map)
                : null,
            propertySnapshot: (m['propertySnapshot'] is Map)
                ? Map<String, dynamic>.from(m['propertySnapshot'] as Map)
                : null,
            buildingSnapshot: (m['buildingSnapshot'] is Map)
                ? Map<String, dynamic>.from(m['buildingSnapshot'] as Map)
                : null,

            // طوابع زمنية
            createdAt: _toDate(m['createdAt']) ?? SaTimeLite.now(),
            updatedAt: _toDate(m['updatedAt']) ?? SaTimeLite.now(),
          ),
        );
}

// 5) الصيانة
class SyncBridgeMaintenance extends GenericSyncBridge<MaintenanceRequest> {
  SyncBridgeMaintenance()
      : super(
          collectionName: 'maintenance',
          box: () =>
              Hive.box<MaintenanceRequest>(scope.boxName(kMaintenanceBox)),
          idOf: (m) => m.id,
          attachmentFields: const <String>['attachmentPaths'],
          attachmentStorageDir: 'maintenance_attachments',
          toMap: (m) {
            final map = <String, dynamic>{
              'serialNo': m.serialNo,
              'propertyId': m.propertyId,
              'tenantId': m.tenantId,
              'title': m.title,
              'note': m.description,
              'description': m.description,
              'requestType': m.requestType,
              'priority': m.priority.name, // low/medium/high/urgent
              'status': m.status.name, // open/inProgress/completed/canceled
              'createdAt': m.createdAt.millisecondsSinceEpoch,
              'scheduledDate': m.scheduledDate?.millisecondsSinceEpoch,
              'executionDeadline': m.executionDeadline?.millisecondsSinceEpoch,
              'completedDate': m.completedDate?.millisecondsSinceEpoch,
              'assignedTo': m.assignedTo,
              'providerSnapshot': m.providerSnapshot,
              'attachmentPaths': m.attachmentPaths,
              'cost': m.cost,
              'isArchived': m.isArchived == true,
              'invoiceId': m.invoiceId,
              'periodicServiceType': m.periodicServiceType,
              'periodicCycleDate':
                  m.periodicCycleDate?.millisecondsSinceEpoch,
            };
            map.removeWhere((k, v) => v == null);
            return map;
          },
          fromMap: (id, mp) => MaintenanceRequest(
            id: id,
            serialNo: (mp['serialNo'] == null) ? null : mp['serialNo'].toString(),
            propertyId: (mp['propertyId'] ?? '') as String,
            tenantId: (mp['tenantId'] as String?),
            title: (mp['title'] ?? '') as String,
            description: ((mp['note'] ?? mp['description']) ?? '') as String,
            requestType: (mp['requestType'] as String?) ?? 'خدمات',
            priority: _enumByName<MaintenancePriority>(
              mp['priority'],
              MaintenancePriority.values,
              fallback: MaintenancePriority.medium,
            ),
            status: _enumByName<MaintenanceStatus>(
              mp['status'],
              MaintenanceStatus.values,
              fallback: MaintenanceStatus.open,
            ),
            createdAt: _toDate(mp['createdAt']) ?? KsaTime.now(),
            scheduledDate: _toDate(mp['scheduledDate']),
            executionDeadline: _toDate(mp['executionDeadline']),
            completedDate: _toDate(mp['completedDate']),
            cost: _toD(mp['cost']),
            assignedTo: (mp['assignedTo'] as String?),
            providerSnapshot: (mp['providerSnapshot'] as Map?)
                ?.cast<String, dynamic>(),
            attachmentPaths: (mp['attachmentPaths'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                <String>[],
            isArchived: (mp['isArchived'] == true),
            invoiceId: (mp['invoiceId'] as String?),
            periodicServiceType: (mp['periodicServiceType'] as String?),
            periodicCycleDate: _toDate(mp['periodicCycleDate']),
          ),
        );
}

// ================ مدير موحّد ================
class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  SyncBridgeInvoices? _invoices;
  SyncBridgeTenants? _tenants;
  SyncBridgeProperties? _properties;
  SyncBridgeContracts? _contracts;
  SyncBridgeMaintenance? _maintenance;

  bool _started = false;

  Future<void> _normalizeScopeBeforeStart() async {
    if (scope.isGuest()) return;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final effectiveUid = scope.effectiveUid();
    if (authUid.isEmpty || effectiveUid.isEmpty || effectiveUid == authUid) {
      return;
    }
    var allowOfficeWorkspace = false;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      final claims = token?.claims ?? const <String, dynamic>{};
      final claimOfficeId =
          (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
      allowOfficeWorkspace =
          claimOfficeId.isNotEmpty && claimOfficeId == effectiveUid;
    } catch (_) {}
    if (!allowOfficeWorkspace) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authUid)
            .get();
        final map = doc.data() ?? const <String, dynamic>{};
        final docOfficeId =
            (map['officeId'] ?? map['office_id'] ?? '').toString().trim();
        allowOfficeWorkspace =
            docOfficeId.isNotEmpty && docOfficeId == effectiveUid;
      } catch (_) {}
    }
    if (!allowOfficeWorkspace) {
      try {
        final directClientDoc = await FirebaseFirestore.instance
            .collection('offices')
            .doc(authUid)
            .collection('clients')
            .doc(effectiveUid)
            .get();
        allowOfficeWorkspace = directClientDoc.exists;
      } catch (_) {}
    }
    if (!allowOfficeWorkspace) {
      try {
        final q = await FirebaseFirestore.instance
            .collection('offices')
            .doc(authUid)
            .collection('clients')
            .where('clientUid', isEqualTo: effectiveUid)
            .limit(1)
            .get();
        allowOfficeWorkspace = q.docs.isNotEmpty;
      } catch (_) {}
    }
    if (!allowOfficeWorkspace) {
      scope.setFixedUid(authUid);
      debugPrint(
        '[SyncManager] scope-normalize authUid=$authUid oldScope=$effectiveUid',
      );
    } else {
      debugPrint(
        '[SyncManager] scope-keep authUid=$authUid scope=$effectiveUid',
      );
    }
  }

  Future<void> startAll() async {
    if (_started) return;
    final sw = Stopwatch()..start();
    debugPrint(
      '[SyncPerf] startAll begin authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${scope.effectiveUid()}',
    );
    await _normalizeScopeBeforeStart();
    debugPrint('[SyncPerf] normalize-scope +${sw.elapsedMilliseconds}ms');

    _invoices ??= SyncBridgeInvoices();
    _tenants ??= SyncBridgeTenants();
    _properties ??= SyncBridgeProperties();
    _contracts ??= SyncBridgeContracts();
    _maintenance ??= SyncBridgeMaintenance();

    await _invoices!.start();
    debugPrint('[SyncPerf] invoices-started +${sw.elapsedMilliseconds}ms');
    await _tenants!.start();
    debugPrint('[SyncPerf] tenants-started +${sw.elapsedMilliseconds}ms');
    await _properties!.start();
    debugPrint('[SyncPerf] properties-started +${sw.elapsedMilliseconds}ms');
    await _contracts!.start();
    debugPrint('[SyncPerf] contracts-started +${sw.elapsedMilliseconds}ms');
    await _maintenance!.start();
    debugPrint('[SyncPerf] maintenance-started +${sw.elapsedMilliseconds}ms');

    _started = true;
    debugPrint('[SyncPerf] startAll done total=${sw.elapsedMilliseconds}ms');
  }

  Future<void> stopAll() async {
    final sw = Stopwatch()..start();
    debugPrint('[SyncPerf] stopAll begin');
    await _invoices?.stop();
    await _tenants?.stop();
    await _properties?.stop();
    await _contracts?.stop();
    await _maintenance?.stop();

    _invoices = null;
    _tenants = null;
    _properties = null;
    _contracts = null;
    _maintenance = null;

    _started = false;
    debugPrint('[SyncPerf] stopAll done total=${sw.elapsedMilliseconds}ms');
  }
}

/* ==================== Helpers ==================== */

double _toD(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int? _toEnumIndex(dynamic v, List<dynamic> values) {
  final idx = _toInt(v);
  if (idx != null && idx >= 0 && idx < values.length) return idx;
  if (v == null) return null;
  String text;
  try {
    final n = (v as dynamic).name;
    text = (n is String ? n : v.toString()).trim().toLowerCase();
  } catch (_) {
    text = v.toString().trim().toLowerCase();
  }
  if (text.isEmpty) return null;
  text = text.split('.').last;
  for (var i = 0; i < values.length; i++) {
    try {
      final n = (values[i] as dynamic).name;
      if (n is String && n.toLowerCase() == text) return i;
    } catch (_) {}
    if (values[i].toString().split('.').last.toLowerCase() == text) return i;
  }
  return null;
}

DateTime _todayEnd() {
  final n = KsaTime.now();
  return DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
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
    return null;
  }
  if (v is Timestamp) return v.toDate();
  return null;
}

T _enumByName<T>(dynamic raw, List<T> values, {T? fallback}) {
  if (raw == null) return fallback ?? values.first;
  // String by name
  if (raw is String) {
    final ls = raw.toLowerCase();
    for (final v in values) {
      final name = v.toString().split('.').last.toLowerCase();
      if (name == ls) return v;
    }
  }
  // int by index
  if (raw is int) {
    if (raw >= 0 && raw < values.length) return values[raw];
  }
  return fallback ?? values.first;
}
