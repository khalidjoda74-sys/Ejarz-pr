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

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

typedef BoxGetter<T> = Box<T> Function();
typedef FromMap<T> = T Function(String id, Map<String, dynamic> m);
typedef ToMap<T> = Map<String, dynamic> Function(T value);
typedef IdOf<T> = String Function(T value);

class GenericSyncBridge<T> {
  GenericSyncBridge({
    required this.collectionName,
    required this.box,
    required this.fromMap,
    required this.toMap,
    required this.idOf,
    this.softDeleteField = 'isDeleted',
  });

  final String collectionName;
  final BoxGetter<T> box;
  final FromMap<T> fromMap;
  final ToMap<T> toMap;
  final IdOf<T> idOf;
  final String softDeleteField;

  StreamSubscription? _fsSub;
  StreamSubscription? _hiveSub;
  bool _muted = false;
  bool _started = false;

  // نحتفظ بالـ UID الذي بُدئ به الجسر لضمان الكتابة/القراءة لنفس المسار
  late final String _uidAtStart;

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

  Future<void> start() async {
    if (_started) return;

    await HiveService.ensureReportsBoxesOpen();

    // ❌ لا تبدأ على "guest"
    if (scope.isGuest()) {
      // لا يوجد مستخدم فعلي ولا انتحال محدد → لا مزامنة
      return;
    }
    // ✅ استخدم الـ UID الفعّال (انتحال إن وُجد، وإلا UID Firebase الحالي)
    final uid = scope.uidOrThrow();
    if (uid.isEmpty) return;

    _uidAtStart = uid;

    final col = _colFor(_uidAtStart);
    final bx = box();

    // Firestore -> Hive
    _fsSub = col.snapshots().listen((snap) async {
      for (final ch in snap.docChanges) {
        final doc = ch.doc;
        final data = doc.data();
        final id = doc.id;

        final deletedHard = (data == null) || (ch.type == DocumentChangeType.removed);
        final deletedSoft = (data != null && (data[softDeleteField] == true));

        if (deletedHard || deletedSoft) {
          _muted = true;
          try {
            if (bx.containsKey(id)) {
              await bx.delete(id);
            }
          } finally {
            _muted = false;
          }
          continue;
        }

        final model = fromMap(id, data!);
        _muted = true;
        try {
          // نخزن دايمًا بمفتاح = id لضمان توافق الحذف/التحديث
          await bx.put(idOf(model), model);
        } finally {
          _muted = false;
        }
      }
    });

    // Hive -> Firestore
    _hiveSub = bx.watch().listen((evt) async {
      if (_muted) return;

      final keyStr = evt.key?.toString();
      final val = (keyStr != null) ? bx.get(keyStr) : null;

      // حذف
      if (evt.deleted == true) {
        if (keyStr == null) return;
        await col.doc(keyStr).set({
          'id': keyStr,
          softDeleteField: true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      if (val == null) return;

      // إضافة/تحديث
      final docId = idOf(val);
      final map = toMap(val)
        ..['id'] = docId
        ..['updatedAt'] = FieldValue.serverTimestamp()
        ..[softDeleteField] = false;

      map.removeWhere((k, v) => v == null);
      await col.doc(docId).set(map, SetOptions(merge: true));
    });

    _started = true;
  }

  Future<void> stop() async {
    await _fsSub?.cancel();
    await _hiveSub?.cancel();
    _fsSub = null;
    _hiveSub = null;
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
          toMap: (inv) {
            final m = <String, dynamic>{
              'tenantId': inv.tenantId,
              'contractId': inv.contractId,
              'propertyId': inv.propertyId,
              'issueDate': inv.issueDate.millisecondsSinceEpoch,
              'dueDate': inv.dueDate.millisecondsSinceEpoch,
              'amount': inv.amount,
              'paidAmount': inv.paidAmount, // مهم
              'currency': inv.currency,
              'paymentMethod': inv.paymentMethod,
              'isArchived': inv.isArchived == true,
              'isCanceled': inv.isCanceled == true,
              'serialNo': inv.serialNo, // String? ← مهم
              'note': inv.note,
              'createdAt': inv.createdAt.millisecondsSinceEpoch,
            };
            m.removeWhere((k, v) => v == null);
            return m;
          },
          fromMap: (id, m) => Invoice(
            id: id,
            tenantId: (m['tenantId'] ?? '') as String,
            contractId: (m['contractId'] ?? '') as String,
            propertyId: (m['propertyId'] ?? '') as String,
            issueDate: _toDate(m['issueDate']) ?? DateTime.now(),
            dueDate: _toDate(m['dueDate']) ?? _todayEnd(),
            amount: _toD(m['amount']),
            paidAmount: _toD(m['paidAmount']),
            currency: (m['currency'] as String?) ?? 'SAR',
            paymentMethod: (m['paymentMethod'] as String?) ?? 'نقدًا',
            isArchived: (m['isArchived'] == true),
            isCanceled: (m['isCanceled'] == true),
            serialNo: (m['serialNo'] == null) ? null : m['serialNo'].toString(),
            note: (m['note'] as String?),
            createdAt: _toDate(m['createdAt']) ?? DateTime.now(),
            updatedAt: _toDate(m['updatedAt']) ?? DateTime.now(),
          ),
        );
}

// 2) المستأجرون
class SyncBridgeTenants extends GenericSyncBridge<Tenant> {
  SyncBridgeTenants()
      : super(
          collectionName: 'tenants',
          box: () => Hive.box<Tenant>(scope.boxName(kTenantsBox)),
          idOf: (t) => t.id,
          toMap: (t) => {
            'fullName': t.fullName,
            'nationalId': t.nationalId,
            'phone': t.phone,
            'email': t.email,
            'nationality': t.nationality,
            'idExpiry': t.idExpiry?.millisecondsSinceEpoch,
            'emergencyName': t.emergencyName,
            'emergencyPhone': t.emergencyPhone,
            'notes': t.notes,
            'isArchived': t.isArchived,
            'isBlacklisted': t.isBlacklisted,
            'blacklistReason': t.blacklistReason,
            'activeContractsCount': t.activeContractsCount,
            'createdAt': t.createdAt?.millisecondsSinceEpoch,
          },
          fromMap: (id, m) => Tenant(
            id: id,
            fullName: (m['fullName'] ?? '') as String,
            nationalId: (m['nationalId'] ?? '') as String,
            phone: (m['phone'] ?? '') as String,
            email: (m['email'] as String?),
            nationality: (m['nationality'] as String?),
            idExpiry: _toDate(m['idExpiry']),
            emergencyName: (m['emergencyName'] as String?),
            emergencyPhone: (m['emergencyPhone'] as String?),
            notes: (m['notes'] as String?),
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
  type: _enumByName<PropertyType>(typeStr, PropertyType.values, fallback: PropertyType.apartment),
  rentalMode: _enumByName<RentalMode>(modeStr, RentalMode.values),
  totalUnits: _toInt(m['totalUnits']) ?? 0,
  occupiedUnits: _toInt(m['occupiedUnits']) ?? 0,
  parentBuildingId: (m['parentBuildingId'] as String?),
  area: (m['area'] == null) ? null : (_toD(m['area'])),
  floors: _toInt(m['floors']),
  rooms: _toInt(m['rooms']),
  price: (m['price'] == null) ? null : (_toD(m['price'])),
  currency: (m['currency'] as String?) ?? 'SAR',
  description: (m['description'] as String?),
  isArchived: (m['isArchived'] == true),

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
              'paymentCycle': c.paymentCycle.index,
              'advanceMode': c.advanceMode.index,
              'advancePaid': c.advancePaid,
              'dailyCheckoutHour': c.dailyCheckoutHour,

              // ملاحظات/حالة
              'isTerminated': c.isTerminated == true,
              'notes': c.notes,
              'serialNo': c.serialNo,
              'isArchived': c.isArchived == true,

              // طوابع زمنية
              'createdAt': c.createdAt.millisecondsSinceEpoch,
              'updatedAt': c.updatedAt.millisecondsSinceEpoch,
            };
            m.removeWhere((k, v) => v == null);
            return m;
          },
          fromMap: (id, m) => Contract(
            id: id,
            tenantId: (m['tenantId'] ?? '') as String,
            propertyId: (m['propertyId'] ?? '') as String,
            startDate: _toDate(m['startDate']) ?? DateTime.now(),
            endDate: _toDate(m['endDate']) ?? _todayEnd(),

            // مبالغ
            rentAmount: _toD(m['rentAmount']),
            totalAmount: _toD(m['totalAmount']),

            // افتراضات معقولة عند غياب القيم
            currency: (m['currency'] as String?) ?? 'SAR',
            term: (() {
              final i = m['term'];
              if (i is int && i >= 0 && i < ContractTerm.values.length) {
                return ContractTerm.values[i];
              }
              return ContractTerm.monthly;
            })(),
            paymentCycle: (() {
              final i = m['paymentCycle'];
              if (i is int && i >= 0 && i < PaymentCycle.values.length) {
                return PaymentCycle.values[i];
              }
              return PaymentCycle.monthly;
            })(),
            advanceMode: (() {
              final i = m['advanceMode'];
              if (i is int && i >= 0 && i < AdvanceMode.values.length) {
                return AdvanceMode.values[i];
              }
              return AdvanceMode.none;
            })(),
            advancePaid: (m['advancePaid'] is num) ? (m['advancePaid'] as num).toDouble() : null,
            dailyCheckoutHour: (m['dailyCheckoutHour'] as int?),

            // ملاحظات/حالة
            isTerminated: (m['isTerminated'] == true),
            notes: (m['notes'] as String?),
            serialNo: (m['serialNo'] == null) ? null : m['serialNo'].toString(),
            isArchived: (m['isArchived'] == true),

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
          box: () => Hive.box<MaintenanceRequest>(scope.boxName(kMaintenanceBox)),
          idOf: (m) => m.id,
          toMap: (m) {
            final map = <String, dynamic>{
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
              'completedDate': m.completedDate?.millisecondsSinceEpoch,
              'assignedTo': m.assignedTo,
              'cost': m.cost,
              'isArchived': m.isArchived == true,
              'invoiceId': m.invoiceId,
            };
            map.removeWhere((k, v) => v == null);
            return map;
          },
          fromMap: (id, mp) => MaintenanceRequest(
            id: id,
            propertyId: (mp['propertyId'] ?? '') as String,
            tenantId: (mp['tenantId'] as String?),
            title: (mp['title'] ?? '') as String,
            description: ((mp['note'] ?? mp['description']) ?? '') as String,
            requestType: (mp['requestType'] as String?) ?? 'صيانة',
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
            createdAt: _toDate(mp['createdAt']) ?? DateTime.now(),
            scheduledDate: _toDate(mp['scheduledDate']),
            completedDate: _toDate(mp['completedDate']),
            cost: _toD(mp['cost']),
            assignedTo: (mp['assignedTo'] as String?),
            isArchived: (mp['isArchived'] == true),
            invoiceId: (mp['invoiceId'] as String?),
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

  Future<void> startAll() async {
    if (_started) return;

    _invoices ??= SyncBridgeInvoices();
    _tenants ??= SyncBridgeTenants();
    _properties ??= SyncBridgeProperties();
    _contracts ??= SyncBridgeContracts();
    _maintenance ??= SyncBridgeMaintenance();

    await _invoices!.start();
    await _tenants!.start();
    await _properties!.start();
    await _contracts!.start();
    await _maintenance!.start();

    _started = true;
  }

  Future<void> stopAll() async {
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

DateTime _todayEnd() {
  final n = DateTime.now();
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
