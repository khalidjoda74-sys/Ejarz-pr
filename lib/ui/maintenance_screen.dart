// lib/ui/maintenance_screen.dart
// شاشة الخدمات: موديل + Adapters + (قائمة/تفاصيل/إضافة-تعديل) + مسارات
//
// تأكد من التسجيل/الفتح في main.dart قبل استخدام الشاشة:
// Hive.registerAdapter(MaintenancePriorityAdapter());
// Hive.registerAdapter(MaintenanceStatusAdapter());
// Hive.registerAdapter(MaintenanceRequestAdapter());
// await Hive.openBox<MaintenanceRequest>(scope.boxName('maintenanceBox'));
//
// await Hive.openBox<Property>(scope.boxName('propertiesBox'));
// await Hive.openBox<Invoice>(scope.boxName('invoicesBox'));              // ← افتح السندات بنفس الاسم والنوع
//
// منطق العقود (مبسّط):
// - لا مقارنة تواريخ.
// - أول عقد مرتبط بالعقار ⇒ نأخذ tenantId.
// - إن تعذر قراءة الصندوق أو لا يوجد عقد ⇒ بدون مستأجر.
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart'; // ✅ لعرض التاريخ الهجري
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'invoices_screen.dart'
    show Invoice, InvoiceAdapter, InvoiceDetailsScreen;
import '../data/services/user_scope.dart' as scope;
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/pdf_export_service.dart';
import '../data/services/entity_audit_service.dart';
import '../data/constants/boxes.dart' as bx;
// أو المسار الصحيح حسب مكان الملف
import '../widgets/darvoo_app_bar.dart';
import '../widgets/custom_confirm_dialog.dart';

// موديلات موجودة لديك
import '../models/tenant.dart';
import '../models/property.dart';

// ===== استيرادات التنقل أسفل الشاشة =====
import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui
    show TenantsScreen, TenantDetailsScreen;
import 'contracts_screen.dart';

// ===== عناصر الواجهة المشتركة (Drawer + زر القائمة + BottomNav) =====
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/entity_audit_info_button.dart';

// ✅ مصدر الوقت السعودي
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// =================== Firestore sync helpers (local to maintenance screen) ===================
Future<void> _maintenanceUpsertFS(MaintenanceRequest m) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final data = _maintenanceToMap(m)
    ..['updatedAt'] = FieldValue.serverTimestamp();
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('maintenance')
      .doc(m.id);
  final before = await ref.get();
  data.addAll(await EntityAuditService.instance.buildWriteAuditFields(
    isCreate: !before.exists,
    workspaceUid: uid,
  ));
  await EntityAuditService.instance.recordLocalAudit(
    workspaceUid: uid,
    collectionName: 'maintenance',
    entityId: m.id,
    isCreate: !before.exists,
  );
  await ref.set(data, SetOptions(merge: true));
}

Future<void> _maintenanceDeleteFS(String id) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('maintenance')
      .doc(id)
      .delete();
}

// Map dart model to firestore fields (adjust if your model uses different names)
Map<String, dynamic> _maintenanceToMap(MaintenanceRequest m) {
  final map = <String, dynamic>{};

  void put(String k, dynamic v) {
    if (v == null) return; // لا نكتب null حتى لا نمسح القيم عند الدمج
    map[k] = v;
  }

  put('id', m.id);
  put('propertyId', m.propertyId);
  put('tenantId', m.tenantId);
  put('title', m.title);
  put('note', m.description);
  put('requestType', m.requestType);
  put('priority',
      (m.priority is Enum) ? (m.priority as Enum).name : m.priority.toString());
  put('status',
      (m.status is Enum) ? (m.status as Enum).name : m.status.toString());
  put('isArchived', m.isArchived);
  put('cost', m.cost);

  // ✅ جهة التنفيذ
  put('assignedTo', m.assignedTo);
  put('attachmentPaths', m.attachmentPaths);

  // ✅ التواريخ الاختيارية
  put('createdAt', m.createdAt.millisecondsSinceEpoch);
  put('scheduledDate', m.scheduledDate?.millisecondsSinceEpoch);
  put('executionDeadline', m.executionDeadline?.millisecondsSinceEpoch);
  put('completedDate', m.completedDate?.millisecondsSinceEpoch);

  // ختم تحديث محلي (لا يؤثر على الحقول الاختيارية)
  put('updatedAtLocal', KsaTime.now().millisecondsSinceEpoch);

  put('invoiceId', m.invoiceId);
  put('providerSnapshot', m.providerSnapshot);
  put('periodicServiceType', m.periodicServiceType);
  put('periodicCycleDate', m.periodicCycleDate?.millisecondsSinceEpoch);

  return map;
}

String _maintenanceProviderClientTypeLabel(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value == 'company' || value == 'مستأجر (شركة)' || value == 'شركة') {
    return 'مستأجر (شركة)';
  }
  if (value == 'serviceprovider' ||
      value == 'service_provider' ||
      value == 'service provider' ||
      value == 'مقدم خدمة') {
    return 'مقدم خدمة';
  }
  return 'مستأجر';
}

void _putMaintenanceProviderSnapshotValue(
    Map<String, dynamic> target, String key, dynamic value) {
  if (value == null) return;
  if (value is String && value.trim().isEmpty) return;
  target[key] = value;
}

void _putMaintenanceProviderSnapshotDate(
    Map<String, dynamic> target, String key, DateTime? value) {
  if (value == null) return;
  target[key] = value.millisecondsSinceEpoch;
}

void _putMaintenanceProviderSnapshotList(
    Map<String, dynamic> target, String key, List<String>? values) {
  if (values == null) return;
  final cleaned = values
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (cleaned.isEmpty) return;
  target[key] = cleaned;
}

Map<String, dynamic> buildMaintenanceProviderSnapshot(Tenant tenant) {
  final map = <String, dynamic>{};
  _putMaintenanceProviderSnapshotValue(map, 'id', tenant.id);
  _putMaintenanceProviderSnapshotValue(map, 'fullName', tenant.fullName);
  _putMaintenanceProviderSnapshotValue(map, 'nationalId', tenant.nationalId);
  _putMaintenanceProviderSnapshotValue(map, 'phone', tenant.phone);
  _putMaintenanceProviderSnapshotValue(map, 'email', tenant.email);
  _putMaintenanceProviderSnapshotDate(map, 'dateOfBirth', tenant.dateOfBirth);
  _putMaintenanceProviderSnapshotValue(
      map, 'nationality', tenant.nationality);
  _putMaintenanceProviderSnapshotDate(map, 'idExpiry', tenant.idExpiry);
  _putMaintenanceProviderSnapshotValue(
      map, 'addressLine', tenant.addressLine);
  _putMaintenanceProviderSnapshotValue(map, 'city', tenant.city);
  _putMaintenanceProviderSnapshotValue(map, 'region', tenant.region);
  _putMaintenanceProviderSnapshotValue(map, 'postalCode', tenant.postalCode);
  _putMaintenanceProviderSnapshotValue(
      map, 'emergencyName', tenant.emergencyName);
  _putMaintenanceProviderSnapshotValue(
      map, 'emergencyPhone', tenant.emergencyPhone);
  _putMaintenanceProviderSnapshotValue(map, 'notes', tenant.notes);
  _putMaintenanceProviderSnapshotValue(map, 'clientType', tenant.clientType);
  _putMaintenanceProviderSnapshotValue(
      map, 'clientTypeLabel', _maintenanceProviderClientTypeLabel(tenant.clientType));
  _putMaintenanceProviderSnapshotValue(
      map, 'tenantBankName', tenant.tenantBankName);
  _putMaintenanceProviderSnapshotValue(
      map, 'tenantBankAccountNumber', tenant.tenantBankAccountNumber);
  _putMaintenanceProviderSnapshotValue(
      map, 'tenantTaxNumber', tenant.tenantTaxNumber);
  _putMaintenanceProviderSnapshotValue(map, 'companyName', tenant.companyName);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyCommercialRegister', tenant.companyCommercialRegister);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyTaxNumber', tenant.companyTaxNumber);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyRepresentativeName', tenant.companyRepresentativeName);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyRepresentativePhone', tenant.companyRepresentativePhone);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyBankAccountNumber', tenant.companyBankAccountNumber);
  _putMaintenanceProviderSnapshotValue(
      map, 'companyBankName', tenant.companyBankName);
  _putMaintenanceProviderSnapshotValue(
      map, 'serviceSpecialization', tenant.serviceSpecialization);
  _putMaintenanceProviderSnapshotList(map, 'tags', tenant.tags);
  _putMaintenanceProviderSnapshotList(
      map, 'attachmentPaths', tenant.attachmentPaths);
  _putMaintenanceProviderSnapshotValue(map, 'isArchived', tenant.isArchived);
  _putMaintenanceProviderSnapshotValue(
      map, 'isBlacklisted', tenant.isBlacklisted);
  _putMaintenanceProviderSnapshotValue(
      map, 'blacklistReason', tenant.blacklistReason);
  _putMaintenanceProviderSnapshotValue(
      map, 'activeContractsCount', tenant.activeContractsCount);
  _putMaintenanceProviderSnapshotDate(map, 'createdAt', tenant.createdAt);
  _putMaintenanceProviderSnapshotDate(map, 'updatedAt', tenant.updatedAt);
  return map;
}

Map<String, dynamic>? _maintenanceProviderSnapshotMapOrNull(dynamic raw) {
  if (raw is! Map) return null;
  try {
    final map = Map<String, dynamic>.from(raw);
    return map.isEmpty ? null : map;
  } catch (_) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key == null) return;
      map[key.toString()] = value;
    });
    return map.isEmpty ? null : map;
  }
}

String? _maintenanceProviderSnapshotString(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _maintenanceProviderSnapshotDateValue(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

List<String> _maintenanceProviderSnapshotStringList(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is List) {
    return value
        .whereType<dynamic>()
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const <String>[] : <String>[text];
}

bool? _maintenanceProviderSnapshotBoolValue(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

const String kContractsBox = 'contractsBox';

/// ------------------------------------------------------------------------------
/// ربط مبسّط: أول عقد يطابق العقار ⇒ يُرجع tenantId (بدون تواريخ).
/// يدعم حالتين: عنصر العقد Map أو كائن مtyped.
/// ------------------------------------------------------------------------------
String? tenantIdForProperty(String? propertyId) {
  if (propertyId == null) return null;
  if (!Hive.isBoxOpen(kContractsBox)) return null;

  dynamic box;
  try {
    box = Hive.box(kContractsBox);
  } catch (_) {
    return null;
  }

  try {
    for (final e in (box as Box).values) {
      try {
        final pid = e is Map
            ? e['propertyId'] as String?
            : (e as dynamic).propertyId as String?;
        if (pid != propertyId) continue;

        final tid = e is Map
            ? e['tenantId'] as String?
            : (e as dynamic).tenantId as String?;
        if (tid != null && tid.isNotEmpty) return tid;
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}

bool _isOwnerPaidMaintenanceServiceType(String raw) {
  final hay = raw.trim().toLowerCase();
  if (hay.isEmpty) return false;
  return hay.contains('نظاف') ||
      hay.contains('clean') ||
      hay.contains('مصعد') ||
      hay.contains('اسانسير') ||
      hay.contains('elevator') ||
      hay.contains('internet') ||
      hay.contains('انترنت') ||
      hay.contains('إنترنت');
}

String? maintenanceLinkedPartyIdForProperty(
  String? propertyId, {
  String? serviceType,
}) {
  if (_isSharedWaterOrElectricMaintenanceType(serviceType ?? '') ||
      _isOwnerPaidMaintenanceServiceType(serviceType ?? '')) {
    return '';
  }
  return tenantIdForProperty(propertyId);
}

bool _isSharedWaterOrElectricMaintenanceType(String raw) {
  final hay = raw.trim().toLowerCase();
  if (hay.isEmpty) return false;
  return hay.contains('water') ||
      hay.contains('Ù…ÙŠØ§Ù‡') ||
      hay.contains('Ù…Ø§Ø¡') ||
      hay.contains('electric') ||
      hay.contains('electricity') ||
      hay.contains('ÙƒÙ‡Ø±Ø¨');
}

String? _extraPeriodicServiceTypeToken(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'water' ||
      value.contains('water') ||
      value.contains('Ù…ÙŠØ§Ù‡') ||
      value.contains('Ù…Ø§Ø¡')) {
    return 'water';
  }
  if (value == 'electricity' ||
      value.contains('electric') ||
      value.contains('electricity') ||
      value.contains('ÙƒÙ‡Ø±Ø¨')) {
    return 'electricity';
  }
  return null;
}

/// ===============================================================================
/// الموديل + الـAdapters
/// ===============================================================================
enum MaintenancePriority { low, medium, high, urgent }

enum MaintenanceStatus { open, inProgress, completed, canceled }

class MaintenancePriorityAdapter extends TypeAdapter<MaintenancePriority> {
  @override
  final int typeId = 60;
  @override
  MaintenancePriority read(BinaryReader r) {
    final v = r.readByte();
    switch (v) {
      case 0:
        return MaintenancePriority.low;
      case 1:
        return MaintenancePriority.medium;
      case 2:
        return MaintenancePriority.high;
      case 3:
        return MaintenancePriority.urgent;
      default:
        return MaintenancePriority.low;
    }
  }

  @override
  void write(BinaryWriter w, MaintenancePriority obj) {
    switch (obj) {
      case MaintenancePriority.low:
        w.writeByte(0);
        break;
      case MaintenancePriority.medium:
        w.writeByte(1);
        break;
      case MaintenancePriority.high:
        w.writeByte(2);
        break;
      case MaintenancePriority.urgent:
        w.writeByte(3);
        break;
    }
  }
}

class MaintenanceStatusAdapter extends TypeAdapter<MaintenanceStatus> {
  @override
  final int typeId = 61;
  @override
  MaintenanceStatus read(BinaryReader r) {
    final v = r.readByte();
    switch (v) {
      case 0:
        return MaintenanceStatus.open;
      case 1:
        return MaintenanceStatus.inProgress;
      case 2:
        return MaintenanceStatus.completed;
      case 3:
        return MaintenanceStatus.canceled;
      default:
        return MaintenanceStatus.open;
    }
  }

  @override
  void write(BinaryWriter w, MaintenanceStatus obj) {
    switch (obj) {
      case MaintenanceStatus.open:
        w.writeByte(0);
        break;
      case MaintenanceStatus.inProgress:
        w.writeByte(1);
        break;
      case MaintenanceStatus.completed:
        w.writeByte(2);
        break;
      case MaintenanceStatus.canceled:
        w.writeByte(3);
        break;
    }
  }
}

class MaintenanceRequest extends HiveObject {
  String id;
  String? serialNo; // رقم الطلب التسلسلي

  String propertyId; // مطلوب
  String? tenantId; // من العقد تلقائيًا إن وجد

  String title; // نوع الخدمة/العنوان الرئيسي
  String description; // وصف
  String requestType; // نوع الخدمة المفهرس

  MaintenancePriority priority;
  MaintenanceStatus status;

  DateTime createdAt;
  DateTime? scheduledDate;
  DateTime? executionDeadline;
  DateTime? completedDate;

  double cost; // تكلفة (افتراضي 0)
  String? assignedTo; // جهة التنفيذ (فني/شركة)
  Map<String, dynamic>? providerSnapshot;
  List<String> attachmentPaths;
  bool isArchived;

  String? invoiceId; // معرف السند التي تُنشأ تلقائيًا عند الإكمال
  String? periodicServiceType; // cleaning / elevator / internet
  DateTime? periodicCycleDate; // تاريخ دورة الطلب الدوري

  MaintenanceRequest({
    String? id,
    this.serialNo,
    required this.propertyId,
    this.tenantId,
    required this.title,
    this.description = '',
    this.requestType = 'خدمات',
    this.priority = MaintenancePriority.medium,
    this.status = MaintenanceStatus.open,
    DateTime? createdAt,
    this.scheduledDate,
    this.executionDeadline,
    this.completedDate,
    this.cost = 0.0,
    this.assignedTo,
    this.providerSnapshot,
    List<String>? attachmentPaths,
    this.isArchived = false,
    this.invoiceId,
    this.periodicServiceType,
    this.periodicCycleDate,
  })  : id = id ?? KsaTime.now().microsecondsSinceEpoch.toString(),
        attachmentPaths = attachmentPaths ?? <String>[],
        createdAt = createdAt ?? KsaTime.now();
}

class MaintenanceRequestAdapter extends TypeAdapter<MaintenanceRequest> {
  @override
  final int typeId = 62;

  @override
  MaintenanceRequest read(BinaryReader r) {
    final numOfFields = r.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) r.readByte(): r.read(),
    };
    return MaintenanceRequest(
      id: fields[0] as String? ??
          KsaTime.now().microsecondsSinceEpoch.toString(),
      propertyId: fields[1] as String,
      tenantId: fields[2] as String?,
      title: fields[3] as String,
      description: fields[4] as String? ?? '',
      priority: fields[5] as MaintenancePriority? ?? MaintenancePriority.medium,
      status: fields[6] as MaintenanceStatus? ?? MaintenanceStatus.open,
      createdAt: fields[7] as DateTime? ?? KsaTime.now(),
      scheduledDate: fields[8] as DateTime?,
      executionDeadline: fields[16] as DateTime?,
      completedDate: fields[9] as DateTime?,
      cost: (fields[10] as double?) ?? 0.0,
      assignedTo: fields[11] as String?,
      providerSnapshot: (fields[18] as Map?)?.cast<String, dynamic>(),
      attachmentPaths:
          (fields[15] as List?)?.whereType<String>().toList() ?? <String>[],
      isArchived: fields[12] as bool? ?? false,
      invoiceId: fields[13] as String?,
      requestType: fields[14] as String? ?? 'خدمات',
      serialNo: fields[17] as String?,
      periodicServiceType: fields[19] as String?,
      periodicCycleDate: fields[20] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter w, MaintenanceRequest m) {
    w
      ..writeByte(21)
      ..writeByte(0)
      ..write(m.id)
      ..writeByte(1)
      ..write(m.propertyId)
      ..writeByte(2)
      ..write(m.tenantId)
      ..writeByte(3)
      ..write(m.title)
      ..writeByte(4)
      ..write(m.description)
      ..writeByte(5)
      ..write(m.priority)
      ..writeByte(6)
      ..write(m.status)
      ..writeByte(7)
      ..write(m.createdAt)
      ..writeByte(8)
      ..write(m.scheduledDate)
      ..writeByte(9)
      ..write(m.completedDate)
      ..writeByte(10)
      ..write(m.cost)
      ..writeByte(11)
      ..write(m.assignedTo)
      ..writeByte(12)
      ..write(m.isArchived)
      ..writeByte(13)
      ..write(m.invoiceId)
      ..writeByte(14)
      ..write(m.requestType)
      ..writeByte(15)
      ..write(m.attachmentPaths)
      ..writeByte(16)
      ..write(m.executionDeadline)
      ..writeByte(17)
      ..write(m.serialNo)
      ..writeByte(18)
      ..write(m.providerSnapshot)
      ..writeByte(19)
      ..write(m.periodicServiceType)
      ..writeByte(20)
      ..write(m.periodicCycleDate);
  }
}

// توليد رقم تسلسلي لطلب الخدمات (YYYY-####) - معالجة جذرية للتكرار
final Map<int, int> _maintenanceSerialMaxByYear = <int, int>{};

String _nextMaintenanceRequestSerial(Box<MaintenanceRequest> box) {
  final int year = KsaTime.now().year;
  int maxSeq = _maintenanceSerialMaxByYear[year] ?? 0;

  try {
    for (final m in box.values) {
      final s = m.serialNo;
      if (s != null && s.contains('-')) {
        final parts = s.split('-');
        if (parts.length >= 2 && parts[0] == year.toString()) {
          final n = int.tryParse(parts[1]) ?? 0;
          if (n > maxSeq) maxSeq = n;
        }
      }
    }
  } catch (e) {
    debugPrint('Error calculating max maintenance sequence: $e');
  }

  final next = maxSeq + 1;
  _maintenanceSerialMaxByYear[year] = next;
  return '$year-${next.toString().padLeft(4, '0')}';
}

String nextMaintenanceRequestSerialForBox(Box<MaintenanceRequest> box) =>
    _nextMaintenanceRequestSerial(box);

String? _normalizePeriodicServiceTypeToken(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'cleaning' || value.contains('clean') || value.contains('نظاف')) {
    return 'cleaning';
  }
  if (value == 'elevator' ||
      value.contains('elevator') ||
      value.contains('مصعد') ||
      value.contains('اسانسير')) {
    return 'elevator';
  }
  if (value == 'internet' ||
      value.contains('internet') ||
      value.contains('انترنت') ||
      value.contains('إنترنت')) {
    return 'internet';
  }
  return null;
}

Future<void> saveMaintenanceRequestLocalAndSync(MaintenanceRequest m) async {
  final box = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());
  if (m.isInBox) {
    await m.save();
  } else {
    await box.put(m.id, m);
  }
  unawaited(_maintenanceUpsertFS(m));
}

Future<void> deleteMaintenanceRequestOnlyLocalAndSync(
    MaintenanceRequest m) async {
  await markPeriodicServiceRequestSuppressedForCurrentCycle(m);
  final maintBox = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());
  dynamic keyToDelete;

  if (m.key != null && maintBox.containsKey(m.key)) {
    final direct = maintBox.get(m.key);
    if (direct is MaintenanceRequest && direct.id == m.id) {
      keyToDelete = m.key;
    }
  }

  for (final k in maintBox.keys) {
    final v = maintBox.get(k);
    if (v?.id == m.id) {
      keyToDelete = k;
      break;
    }
  }

  if (keyToDelete != null) {
    await maintBox.delete(keyToDelete);
    unawaited(_maintenanceDeleteFS(m.id));
  }
}

String? _periodicServiceTypeForMaintenanceRequest(MaintenanceRequest request) {
  final tagged = _normalizePeriodicServiceTypeToken(request.periodicServiceType);
  if (tagged != null) return tagged;
  final extraTagged = _extraPeriodicServiceTypeToken(request.periodicServiceType);
  if (extraTagged != null) return extraTagged;
  final hay =
      '${request.title} ${request.description} ${request.requestType}'.toLowerCase();
  final extraHay = _extraPeriodicServiceTypeToken(hay);
  if (extraHay != null) return extraHay;
  if (hay.contains('نظاف') || hay.contains('clean')) {
    return 'cleaning';
  }
  if (hay.contains('مصعد') ||
      hay.contains('اسانسير') ||
      hay.contains('elevator')) {
    return 'elevator';
  }
  if (hay.contains('internet') ||
      hay.contains('انترنت') ||
      hay.contains('إنترنت')) {
    return 'internet';
  }
  return null;
}

DateTime _periodicServiceAnchorForMaintenanceRequest(
  MaintenanceRequest request,
) =>
    KsaTime.dateOnly(
      request.periodicCycleDate ??
          request.executionDeadline ??
          request.scheduledDate ??
          request.createdAt,
    );

DateTime? _periodicServiceConfigParseDate(dynamic raw) {
  if (raw is DateTime) return KsaTime.dateOnly(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      return KsaTime.dateOnly(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

DateTime? _periodicServiceConfigDueDateFromConfig(
  String type,
  Map<String, dynamic> cfg,
) {
  dynamic raw;
  if (type == 'elevator') {
    raw = cfg['nextServiceDate'] ?? cfg['nextDueDate'];
  } else if (type == 'cleaning' || type == 'internet') {
    raw = cfg['nextDueDate'];
  } else {
    return null;
  }
  return _periodicServiceConfigParseDate(raw);
}

DateTime? _periodicServiceConfigStartDateFromConfig(Map<String, dynamic> cfg) =>
    _periodicServiceConfigParseDate(cfg['startDate']);

DateTime? _periodicServiceConfigLastGeneratedDateFromConfig(
        Map<String, dynamic> cfg) =>
    _periodicServiceConfigParseDate(cfg['lastGeneratedRequestDate']);

DateTime? _periodicServiceExecutionDateForTodayFromConfig(
  String type,
  Map<String, dynamic> cfg,
  DateTime today,
) {
  final normalizedToday = KsaTime.dateOnly(today);
  final lastGenerated = _periodicServiceConfigLastGeneratedDateFromConfig(cfg);
  if (lastGenerated != null && KsaTime.dateOnly(lastGenerated) == normalizedToday) {
    return normalizedToday;
  }

  final startDate = _periodicServiceConfigStartDateFromConfig(cfg);
  if (lastGenerated == null &&
      startDate != null &&
      KsaTime.dateOnly(startDate) == normalizedToday) {
    return normalizedToday;
  }

  final dueDate = _periodicServiceConfigDueDateFromConfig(type, cfg);
  if (dueDate != null && KsaTime.dateOnly(dueDate) == normalizedToday) {
    return normalizedToday;
  }

  return null;
}

Future<void> _markPeriodicServiceRequestSuppressedOnDelete(
  MaintenanceRequest request,
) async {
  final serviceType = _periodicServiceTypeForMaintenanceRequest(request);
  if (serviceType == null) return;
  if (request.propertyId.trim().isEmpty) return;

  final boxId = scope.boxName('servicesConfig');
  if (!Hive.isBoxOpen(boxId)) {
    try {
      await Hive.openBox<Map>(boxId);
    } catch (_) {
      return;
    }
  }

  final servicesBox = Hive.box<Map>(boxId);
  final serviceKey = '${request.propertyId}::$serviceType';
  final raw = servicesBox.get(serviceKey);
  if (raw is! Map) return;

  final cfg = Map<String, dynamic>.from(raw);
  final suppressionDate =
      _periodicServiceExecutionDateForTodayFromConfig(
            serviceType,
            cfg,
            KsaTime.today(),
          ) ??
          _periodicServiceAnchorForMaintenanceRequest(request);

  final updated = Map<String, dynamic>.from(cfg)
    ..['suppressedRequestDate'] = suppressionDate.toIso8601String()
    ..['lastGeneratedRequestId'] = ''
    ..['targetId'] = '';
  await servicesBox.put(serviceKey, updated);
}

Future<void> markPeriodicServiceRequestSuppressedForCurrentCycle(
  MaintenanceRequest request,
) async {
  await _markPeriodicServiceRequestSuppressedOnDelete(request);
}

/// ===============================================================================
/// إنشاء/تحديث سند الخدمات مرة واحدة بنوع Invoice
/// ===============================================================================

// نفس منطق أرقام السندات في invoices_screen.dart لكن مخصص للخدمات
// مولّد رقم سند للخدمات بناءً على أعلى رقم موجود في نفس السنة
String _nextInvoiceSerialForMaintenance(Box<Invoice> invoices) {
  final year = KsaTime.now().year;

  int maxSeq = 0;
  for (final inv in invoices.values) {
    final s = inv.serialNo;
    if (s != null && s.startsWith('$year-')) {
      final tail = s.split('-').last;
      final n = int.tryParse(tail) ?? 0;
      if (n > maxSeq) maxSeq = n;
    }
  }

  final next = maxSeq + 1;
  return '$year-${next.toString().padLeft(4, '0')}';
}

String _cleanMaintenanceServiceTypeText(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return '';
  if (normalized.startsWith('طلب ')) {
    final stripped = normalized.substring(4).trim();
    if (stripped.isNotEmpty) return stripped;
  }
  return normalized;
}

String _normalizeMaintenanceRequestTypeForStorage(String raw) {
  final cleaned = _cleanMaintenanceServiceTypeText(raw);
  return cleaned.isEmpty ? 'خدمات' : cleaned;
}

String _maintenanceDisplayServiceType(MaintenanceRequest request) {
  final titleType = _cleanMaintenanceServiceTypeText(request.title);
  if (titleType.isNotEmpty) return titleType;
  final requestType = _cleanMaintenanceServiceTypeText(request.requestType);
  if (requestType.isNotEmpty &&
      requestType != 'خدمات' &&
      requestType != 'خدمة دورية') {
    return requestType;
  }
  final voucherType = _maintenanceVoucherTypeLabel(request).trim();
  return voucherType.isEmpty ? 'خدمات' : voucherType;
}

String _maintenanceVoucherTypeLabel(MaintenanceRequest request) {
  final hay =
      '${request.title} ${request.description} ${request.requestType}'.toLowerCase();
  final hasSharedService =
      hay.contains('مشترك') || hay.contains('مشتركة') || hay.contains('shared');
  if (hay.contains('مصعد') ||
      hay.contains('اسانسير') ||
      hay.contains('elevator')) {
    return 'صيانة مصعد';
  }
  if (hay.contains('نظاف') || hay.contains('clean')) {
    return 'نظافة عمارة';
  }
  if (hay.contains('internet') ||
      hay.contains('انترنت') ||
      hay.contains('إنترنت')) {
    return 'خدمة إنترنت';
  }
  if (hasSharedService &&
      (hay.contains('water') || hay.contains('مياه') || hay.contains('ماء'))) {
    return 'خدمة مياه مشتركة';
  }
  if (hasSharedService &&
      (hay.contains('electric') || hay.contains('كهرب'))) {
    return 'خدمة كهرباء مشتركة';
  }
  if (hay.contains('water') || hay.contains('مياه') || hay.contains('ماء')) {
    return 'خدمة مياه';
  }
  if (hay.contains('electric') || hay.contains('كهرب')) {
    return 'خدمة كهرباء';
  }
  final requestType = request.requestType.trim();
  if (requestType.isNotEmpty &&
      requestType != 'خدمات' &&
      requestType != 'خدمة دورية') {
    return requestType;
  }
  if (hay.contains('صيانة') || hay.contains('maint')) {
    return 'صيانة';
  }
  return 'خدمات';
}

String _composeMaintenancePropertyReference({
  String unitName = '',
  String buildingName = '',
}) {
  final normalizedUnit = unitName.trim();
  final normalizedBuilding = buildingName.trim();
  if (normalizedBuilding.isEmpty) return normalizedUnit;
  if (normalizedUnit.isEmpty || normalizedUnit == normalizedBuilding) {
    return normalizedBuilding;
  }
  return '$normalizedBuilding ($normalizedUnit)';
}

String _maintenancePropertyReference({
  Property? property,
  Property? building,
}) {
  return _composeMaintenancePropertyReference(
    unitName: (property?.name ?? '').trim(),
    buildingName: (building?.name ?? '').trim(),
  );
}

Future<String> _resolveMaintenancePropertyReference({
  Property? property,
  String? propertyId,
}) async {
  final rawId = (propertyId ?? '').trim();
  Property? current = property;
  Property? building;

  try {
    final boxId = scope.boxName('propertiesBox');
    if (!Hive.isBoxOpen(boxId)) {
      await Hive.openBox<Property>(boxId);
    }
    final box = Hive.box<Property>(boxId);
    current ??= rawId.isEmpty ? null : box.get(rawId);
    final parentId = (current?.parentBuildingId ?? '').trim();
    if (parentId.isNotEmpty) {
      building = box.get(parentId);
    }
  } catch (_) {}

  return _maintenancePropertyReference(
    property: current,
    building: building,
  );
}

String _appendMaintenancePropertyReference(String text, String propertyRef) {
  final cleanText = text.trim();
  final cleanPropertyRef = propertyRef.trim();
  if (cleanPropertyRef.isEmpty) return cleanText;
  if (cleanText.isEmpty) return cleanPropertyRef;

  final lines = cleanText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return cleanPropertyRef;

  final joinedLower = lines.join('\n').toLowerCase();
  if (joinedLower.contains(cleanPropertyRef.toLowerCase())) {
    return lines.join('\n').trim();
  }

  lines[0] = '${lines[0]} • $cleanPropertyRef';
  return lines.join('\n').trim();
}

String _buildMaintenanceInvoiceNote(
  MaintenanceRequest request, {
  String propertyRef = '',
}) {
  final lines = <String>[];
  final serviceTypeToken = _periodicServiceTypeForMaintenanceRequest(request) ?? '';
  final title = request.title.trim();
  final description = request.description.trim();
  final typeLabel = _maintenanceVoucherTypeLabel(request);
  final sharedServiceType = (() {
    final hay =
        '${request.title} ${request.description} ${request.requestType}'.toLowerCase();
    final hasSharedService =
        hay.contains('مشترك') || hay.contains('مشتركة') || hay.contains('shared');
    if (!hasSharedService) return '';
    if (hay.contains('water') || hay.contains('مياه') || hay.contains('ماء')) {
      return 'water';
    }
    if (hay.contains('electric') || hay.contains('كهرب')) {
      return 'electricity';
    }
    return '';
  })();
  if (serviceTypeToken.isNotEmpty) {
    lines.add('[SERVICE] type=$serviceTypeToken');
  }
  if (sharedServiceType.isNotEmpty) {
    lines.add('[SHARED_SERVICE_OFFICE: $sharedServiceType]');
  }

  String firstLine;
  if (title.isEmpty) {
    firstLine = typeLabel;
  } else if (title.toLowerCase() == typeLabel.toLowerCase()) {
    firstLine = title;
  } else {
    firstLine = '$typeLabel - $title';
  }
  lines.add(_appendMaintenancePropertyReference(firstLine, propertyRef));

  if (description.isNotEmpty && description.toLowerCase() != title.toLowerCase()) {
    lines.add(description);
  }

  return lines.join('\n').trim();
}

Future<String> createOrUpdateInvoiceForMaintenance(MaintenanceRequest m) async {
  try {
    final box =
        Hive.box<Invoice>(scope.boxName('invoicesBox')); // لا تفتح ولا تغلق

    final now = KsaTime.now();
    final String id = (m.invoiceId?.isNotEmpty == true)
        ? m.invoiceId!
        : now.microsecondsSinceEpoch.toString();

    // 🔹 حافظ على رقم السند القديم إن وجد، وإلا أنشئ رقم جديد
    String? serialNo;
    try {
      final existing = box.get(id);
      if (existing != null &&
          existing.serialNo != null &&
          existing.serialNo!.isNotEmpty) {
        // سند قديمة للخدمات لها رقم → نستخدمه كما هو
        serialNo = existing.serialNo;
      } else {
        // سند جديدة أو قديمة بدون رقم → نولّد رقم جديد
        serialNo = _nextInvoiceSerialForMaintenance(box);
      }
    } catch (_) {
      // في حالة أي خطأ غير متوقع، لا نكسر الكود
      serialNo = null;
    }
    final propertyRef =
        await _resolveMaintenancePropertyReference(propertyId: m.propertyId);

    final inv = Invoice(
      id: id,
      serialNo: serialNo,
      tenantId: m.tenantId ?? '',
      contractId: '',
      propertyId: m.propertyId,
      issueDate: m.completedDate ?? now,
      dueDate: m.completedDate ?? now,
      amount: -m.cost, // ← سالب: مصروف
      paidAmount: m.cost, // دفع كامل
      currency: 'SAR',
      note: _buildMaintenanceInvoiceNote(m, propertyRef: propertyRef),
      paymentMethod: 'نقدًا',
      isArchived: m.isArchived,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );
    final maintenanceDetails = MaintenanceReceiptDetails.fromRequest(m);
    inv.maintenanceRequestId = m.id;
    inv.maintenanceSnapshot = maintenanceDetails.toMap();

    await box.put(id, inv);
    return id;
  } catch (e) {
    debugPrint('Invoice create/update failed: $e');
    return '';
  }
}

/// ===============================================================================
String _fmtDate(DateTime d) {
  final x = KsaTime.dateOnly(d);
  return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

String _fmtDateOrDash(DateTime? d) => d == null ? '—' : _fmtDate(d);

// ✅ تفعيل/تعطيل العرض الهجري من sessionBox
bool get _useHijri {
  if (!Hive.isBoxOpen('sessionBox')) return false;
  try {
    return Hive.box('sessionBox').get('useHijri', defaultValue: false) == true;
  } catch (_) {
    return false;
  }
}

// ✅ ديناميكي هجري/ميلادي
String _fmtDateDynamic(DateTime d) {
  final dd = KsaTime.dateOnly(d);
  if (!_useHijri) return _fmtDate(dd);
  final h = HijriCalendar.fromDate(dd);
  final yy = h.hYear.toString();
  final mm = h.hMonth.toString().padLeft(2, '0');
  final ddh = h.hDay.toString().padLeft(2, '0');
  return '$yy-$mm-$ddh هـ';
}

String _fmtDateOrDashDynamic(DateTime? d) =>
    d == null ? '—' : _fmtDateDynamic(d);

// قصّ إلى خانتين
String _fmtMoneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
}

Widget _softCircle(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

class _DarkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const _DarkCard({required this.child, this.padding});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0x26FFFFFF)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10))
        ],
      ),
      child: child,
    );
  }
}

class _MaintenanceProviderSnapshotScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MaintenanceProviderSnapshotScaffold({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text(
            title,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -120,
              right: -80,
              child: _softCircle(220.r, const Color(0x33FFFFFF)),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _softCircle(260.r, const Color(0x22FFFFFF)),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _maintenanceProviderSnapshotNoteCard(String text) => _DarkCard(
      padding: EdgeInsets.all(14.w),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A).withOpacity(0.32),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Text(
          text,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 13.sp,
            height: 1.7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

Widget _maintenanceProviderSnapshotSectionTitle(String t) => Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        t,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14.sp,
        ),
      ),
    );

Widget _maintenanceProviderSnapshotRowInfo(String label, String? value,
    {VoidCallback? onTap}) {
  final has = (value ?? '').trim().isNotEmpty;
  if (!has) return const SizedBox.shrink();
  final valueText = Text(
    value!,
    style: GoogleFonts.cairo(
      color: onTap == null ? Colors.white : const Color(0xFF93C5FD),
      decoration: onTap == null ? null : TextDecoration.underline,
      fontWeight: FontWeight.w700,
    ),
  );

  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      children: [
        SizedBox(
          width: 120.w,
          child: Text(
            label,
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: onTap == null ? valueText : InkWell(onTap: onTap, child: valueText)),
      ],
    ),
  );
}

bool _isMaintenanceProviderSnapshotImageAttachment(String path) {
  final lower = path.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

bool _isMaintenanceProviderSnapshotRemoteAttachment(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://') || p.startsWith('gs://');
}

Future<String> _resolveMaintenanceProviderSnapshotRemoteUrl(String path) async {
  if (path.startsWith('gs://')) {
    return FirebaseStorage.instance.refFromURL(path).getDownloadURL();
  }
  return path;
}

Widget _buildMaintenanceProviderSnapshotAttachmentThumb(String path) {
  if (_isMaintenanceProviderSnapshotImageAttachment(path)) {
    if (_isMaintenanceProviderSnapshotRemoteAttachment(path)) {
      return FutureBuilder<String>(
        future: _resolveMaintenanceProviderSnapshotRemoteUrl(path),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) {
            return const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white70,
            );
          }
          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white70,
            ),
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          );
        },
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white70,
      ),
    );
  }
  return const Icon(
    Icons.picture_as_pdf_rounded,
    color: Colors.white70,
  );
}

class _MaintenanceProviderSnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  final Future<void> Function(String path) onAttachmentTap;
  final Future<void> Function()? onOpenOriginal;

  const _MaintenanceProviderSnapshotScreen({
    required this.snapshot,
    required this.onAttachmentTap,
    this.onOpenOriginal,
  });

  Widget _dateRow(String label, String key) {
    final value = _maintenanceProviderSnapshotDateValue(snapshot, key);
    return _maintenanceProviderSnapshotRowInfo(
      label,
      value == null ? null : _fmtDateDynamic(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress =
        _maintenanceProviderSnapshotString(snapshot, 'addressLine') != null ||
            _maintenanceProviderSnapshotString(snapshot, 'city') != null ||
            _maintenanceProviderSnapshotString(snapshot, 'region') != null ||
            _maintenanceProviderSnapshotString(snapshot, 'postalCode') != null;
    final hasCompany =
        _maintenanceProviderSnapshotString(snapshot, 'companyName') != null ||
            _maintenanceProviderSnapshotString(
                    snapshot, 'companyCommercialRegister') !=
                null ||
            _maintenanceProviderSnapshotString(
                    snapshot, 'companyRepresentativeName') !=
                null ||
            _maintenanceProviderSnapshotString(
                    snapshot, 'companyRepresentativePhone') !=
                null ||
            _maintenanceProviderSnapshotString(snapshot, 'companyBankName') !=
                null ||
            _maintenanceProviderSnapshotString(
                    snapshot, 'companyBankAccountNumber') !=
                null ||
            _maintenanceProviderSnapshotString(snapshot, 'companyTaxNumber') !=
                null;
    final hasService =
        _maintenanceProviderSnapshotString(snapshot, 'serviceSpecialization') !=
            null;
    final tags = _maintenanceProviderSnapshotStringList(snapshot, 'tags');
    final attachments =
        _maintenanceProviderSnapshotStringList(snapshot, 'attachmentPaths');
    final isBlacklisted =
        _maintenanceProviderSnapshotBoolValue(snapshot, 'isBlacklisted') ==
            true;
    final hasAdditional =
        _maintenanceProviderSnapshotString(snapshot, 'emergencyName') != null ||
            _maintenanceProviderSnapshotString(snapshot, 'emergencyPhone') !=
                null ||
            _maintenanceProviderSnapshotString(snapshot, 'tenantBankName') !=
                null ||
            _maintenanceProviderSnapshotString(
                    snapshot, 'tenantBankAccountNumber') !=
                null ||
            _maintenanceProviderSnapshotString(snapshot, 'tenantTaxNumber') !=
                null ||
            tags.isNotEmpty ||
            isBlacklisted ||
            _maintenanceProviderSnapshotString(snapshot, 'blacklistReason') !=
                null ||
            _maintenanceProviderSnapshotString(snapshot, 'notes') != null;

    return _MaintenanceProviderSnapshotScaffold(
      title: 'نسخة مقدم الخدمة',
      children: [
        _maintenanceProviderSnapshotNoteCard(
          'هذه نسخة محفوظة من بيانات مقدم الخدمة وقت حفظ الطلب. إذا أردت فتح بيانات مقدم الخدمة الأصلية، اضغط على اسم مقدم الخدمة.',
        ),
        SizedBox(height: 10.h),
        _DarkCard(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _maintenanceProviderSnapshotSectionTitle(
                  'بيانات مقدم الخدمة وقت حفظ الطلب'),
              _maintenanceProviderSnapshotRowInfo(
                'اسم مقدم الخدمة',
                _maintenanceProviderSnapshotString(snapshot, 'fullName'),
                onTap: onOpenOriginal == null ? null : () => onOpenOriginal!(),
              ),
              _maintenanceProviderSnapshotRowInfo(
                'نوع العميل',
                _maintenanceProviderSnapshotString(snapshot, 'clientTypeLabel'),
              ),
              _maintenanceProviderSnapshotRowInfo(
                'رقم الهوية',
                _maintenanceProviderSnapshotString(snapshot, 'nationalId'),
              ),
              _maintenanceProviderSnapshotRowInfo(
                'رقم الجوال',
                _maintenanceProviderSnapshotString(snapshot, 'phone'),
              ),
              _maintenanceProviderSnapshotRowInfo(
                'البريد الإلكتروني',
                _maintenanceProviderSnapshotString(snapshot, 'email'),
              ),
              _dateRow('تاريخ الميلاد', 'dateOfBirth'),
              _maintenanceProviderSnapshotRowInfo(
                'الجنسية',
                _maintenanceProviderSnapshotString(snapshot, 'nationality'),
              ),
              _dateRow('تاريخ انتهاء الهوية', 'idExpiry'),
            ],
          ),
        ),
        if (hasAddress) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceProviderSnapshotSectionTitle(
                    'العنوان وقت حفظ الطلب'),
                _maintenanceProviderSnapshotRowInfo(
                  'العنوان',
                  _maintenanceProviderSnapshotString(snapshot, 'addressLine'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'المدينة',
                  _maintenanceProviderSnapshotString(snapshot, 'city'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'المنطقة',
                  _maintenanceProviderSnapshotString(snapshot, 'region'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'الرمز البريدي',
                  _maintenanceProviderSnapshotString(snapshot, 'postalCode'),
                ),
              ],
            ),
          ),
        ],
        if (hasAdditional) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceProviderSnapshotSectionTitle('بيانات إضافية'),
                _maintenanceProviderSnapshotRowInfo(
                  'اسم الطوارئ',
                  _maintenanceProviderSnapshotString(snapshot, 'emergencyName'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'جوال الطوارئ',
                  _maintenanceProviderSnapshotString(snapshot, 'emergencyPhone'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'اسم البنك',
                  _maintenanceProviderSnapshotString(snapshot, 'tenantBankName'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'رقم الحساب',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'tenantBankAccountNumber'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'الرقم الضريبي',
                  _maintenanceProviderSnapshotString(snapshot, 'tenantTaxNumber'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'الوسوم',
                  tags.isEmpty ? null : tags.join('، '),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'في القائمة السوداء',
                  isBlacklisted ? 'نعم' : null,
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'سبب القائمة السوداء',
                  _maintenanceProviderSnapshotString(snapshot, 'blacklistReason'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'الملاحظات',
                  _maintenanceProviderSnapshotString(snapshot, 'notes'),
                ),
              ],
            ),
          ),
        ],
        if (hasCompany) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceProviderSnapshotSectionTitle(
                    'بيانات الشركة وقت حفظ الطلب'),
                _maintenanceProviderSnapshotRowInfo(
                  'اسم الشركة',
                  _maintenanceProviderSnapshotString(snapshot, 'companyName'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'السجل التجاري',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'companyCommercialRegister'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'الرقم الضريبي',
                  _maintenanceProviderSnapshotString(snapshot, 'companyTaxNumber'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'اسم الممثل',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'companyRepresentativeName'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'جوال الممثل',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'companyRepresentativePhone'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'بنك الشركة',
                  _maintenanceProviderSnapshotString(snapshot, 'companyBankName'),
                ),
                _maintenanceProviderSnapshotRowInfo(
                  'حساب الشركة',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'companyBankAccountNumber'),
                ),
              ],
            ),
          ),
        ],
        if (hasService) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceProviderSnapshotSectionTitle(
                    'بيانات الخدمة وقت حفظ الطلب'),
                _maintenanceProviderSnapshotRowInfo(
                  'التخصص',
                  _maintenanceProviderSnapshotString(
                      snapshot, 'serviceSpecialization'),
                ),
              ],
            ),
          ),
        ],
        if (attachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maintenanceProviderSnapshotSectionTitle(
                    'مرفقات مقدم الخدمة وقت حفظ الطلب (${attachments.length})'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: attachments.map((path) {
                    return InkWell(
                      onTap: () => onAttachmentTap(path),
                      borderRadius: BorderRadius.circular(10.r),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: Container(
                          width: 92.w,
                          height: 92.w,
                          color: Colors.white.withOpacity(0.08),
                          child: _buildMaintenanceProviderSnapshotAttachmentThumb(
                              path),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Widget _chip(String text, {Color bg = const Color(0xFF334155)}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text,
          style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700)),
    );

String _limitChars(String t, int max) =>
    t.length <= max ? t : '${t.substring(0, max)}…';

Color _statusColor(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return const Color(0xFF0EA5E9);
    case MaintenanceStatus.inProgress:
      return const Color(0xFFF59E0B);
    case MaintenanceStatus.completed:
      return const Color(0xFF065F46);
    case MaintenanceStatus.canceled:
      return const Color(0xFF7F1D1D);
  }
}

// ✅ تحسين الأداء: لا نستدعي Hive.box لكل عنصر داخل حلقة where
bool _isInvoiceCanceledWithBox(MaintenanceRequest m, Box<Invoice>? invBox) {
  if (m.invoiceId == null || m.invoiceId!.isEmpty || invBox == null)
    return false;
  try {
    final inv = invBox.get(m.invoiceId);
    return inv?.isCanceled ?? false;
  } catch (_) {
    return false;
  }
}

// دالة مساعدة للحفاظ على التوافق إذا لزم الأمر في مكان آخر
bool _isInvoiceCanceledSync(MaintenanceRequest m) {
  if (m.invoiceId == null || m.invoiceId!.isEmpty) return false;
  try {
    final boxId = scope.boxName(bx.kInvoicesBox);
    if (!Hive.isBoxOpen(boxId)) return false;
    final box = Hive.box<Invoice>(boxId);
    return _isInvoiceCanceledWithBox(m, box);
  } catch (_) {
    return false;
  }
}

String _statusText(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return 'جديد';
    case MaintenanceStatus.inProgress:
      return 'قيد التنفيذ';
    case MaintenanceStatus.completed:
      return 'مكتمل';
    case MaintenanceStatus.canceled:
      return 'ملغاة';
  }
}

String _priorityText(MaintenancePriority p) {
  switch (p) {
    case MaintenancePriority.low:
      return 'منخفضة';
    case MaintenancePriority.medium:
      return 'متوسطة';
    case MaintenancePriority.high:
      return 'عالية';
    case MaintenancePriority.urgent:
      return 'عاجلة';
  }
}

Color _priorityColor(MaintenancePriority p) {
  switch (p) {
    case MaintenancePriority.low:
      return const Color(0xFF475569);
    case MaintenancePriority.medium:
      return const Color(0xFF0D9488);
    case MaintenancePriority.high:
      return const Color(0xFFB45309);
    case MaintenancePriority.urgent:
      return const Color(0xFFB91C1C);
  }
}

// ✅ تنبيه منع الأرشفة قبل «مكتملة»
Future<void> _showServicesArchiveNoticeDialog(
  BuildContext context, {
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Text(
                  'تنبيه',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF1E293B),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF475569),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'حسنًا',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showArchiveBlockedDialog(BuildContext context) async {
  await _showServicesArchiveNoticeDialog(
    context,
    message:
        'لا يمكن الأرشفة. تتم أرشفة الطلبات الملغية تلقائيًا فقط بعد إلغاء السند الذي يُستخرج عند إكمال الطلب.',
  );
}

Future<void> showEditBlockedDialog(BuildContext context) async {
  await CustomConfirmDialog.show(
    context: context,
    title: 'لا يمكن التعديل',
    message: 'لا يمكن تعديل طلب الخدمات بعد اعتماده "مكتمل".\n',
    confirmLabel: 'حسنًا',
    showCancel: false,
  );
}

/// ===============================================================================
/// شاشة القائمة
/// ===============================================================================
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Box<MaintenanceRequest> get _box =>
      Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

  Box<Property> get _properties =>
      Hive.box<Property>(scope.boxName('propertiesBox'));

  String _q = '';
  String? _assignedToFilter;
  String? _propertyFilterId;
  String? _propertyFilterName;
  String? _providerRequestsView;
  final bool _showArchived = false;
  MaintenanceStatus? _statusFilter;
  MaintenancePriority? _priorityFilter;
  bool? _archivedFilter; // ✅ يظهر فقط عندما تكون الحالة «مكتملة»

  bool _hasActiveFilters({
    required bool propertyScoped,
    required bool providerScoped,
  }) {
    return propertyScoped ||
        providerScoped ||
        _statusFilter != null ||
        _priorityFilter != null ||
        (!propertyScoped && _archivedFilter == true);
  }

  String _currentFilterLabel({
    required bool propertyScoped,
    required bool providerCurrentScoped,
    required bool providerHistoryScoped,
  }) {
    final parts = <String>[];
    parts.add((!propertyScoped && _archivedFilter == true) ? 'المؤرشفة' : 'الكل');

    if ((_assignedToFilter ?? '').isNotEmpty) {
      parts.add('مقدم الخدمة: ${_assignedToFilter!}');
    }

    if (propertyScoped) {
      parts.add('العقار: ${_propertyFilterName ?? '—'}');
    }

    if (providerCurrentScoped) {
      parts.add('طلبات الخدمات');
    } else if (providerHistoryScoped) {
      parts.add('خدمات سابقة');
    }

    if (_statusFilter != null) {
      parts.add(_statusFilter == MaintenanceStatus.canceled
          ? 'ملغية'
          : _statusText(_statusFilter!));
    }

    if (_priorityFilter != null) {
      parts.add(_priorityText(_priorityFilter!));
    }

    return parts.join(' • ');
  }

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;
// لفتح طلب عند الوصول عبر التنبيهات مرة واحدة فقط
  bool _didReadArgs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadArgs) return;
    _didReadArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final assignedRaw = args?['filterAssignedTo']?.toString().trim();
    if (assignedRaw != null && assignedRaw.isNotEmpty) {
      _assignedToFilter = assignedRaw;
    }
    final providerViewRaw = args?['providerRequestsView']?.toString().trim();
    if (providerViewRaw == 'current' || providerViewRaw == 'history') {
      _providerRequestsView = providerViewRaw;
    }
    final propertyIdRaw = args?['filterPropertyId']?.toString().trim();
    if (propertyIdRaw != null && propertyIdRaw.isNotEmpty) {
      _propertyFilterId = propertyIdRaw;
    }
    final propertyNameRaw = args?['filterPropertyName']?.toString().trim();
    if (propertyNameRaw != null && propertyNameRaw.isNotEmpty) {
      _propertyFilterName = propertyNameRaw;
    }
    final statusArg = _maintenanceStatusFromArg(args?['filterStatus']);
    if (statusArg != null) {
      _statusFilter = statusArg;
      if (statusArg == MaintenanceStatus.canceled) {
        _archivedFilter = true;
      }
    }
    final priorityArg = _maintenancePriorityFromArg(args?['filterPriority']);
    if (priorityArg != null) {
      _priorityFilter = priorityArg;
    }
    final id = args?['openMaintenanceId']?.toString();
    if (id != null && id.isNotEmpty) {
      Future.microtask(() => _openMaintenanceById(id));
    }
  }

  MaintenanceStatus? _maintenanceStatusFromArg(dynamic raw) {
    if (raw is MaintenanceStatus) return raw;
    final value = raw?.toString().trim();
    switch (value) {
      case 'open':
        return MaintenanceStatus.open;
      case 'inProgress':
        return MaintenanceStatus.inProgress;
      case 'completed':
        return MaintenanceStatus.completed;
      case 'canceled':
        return MaintenanceStatus.canceled;
      default:
        return null;
    }
  }

  MaintenancePriority? _maintenancePriorityFromArg(dynamic raw) {
    if (raw is MaintenancePriority) return raw;
    final value = raw?.toString().trim();
    switch (value) {
      case 'low':
        return MaintenancePriority.low;
      case 'medium':
        return MaintenancePriority.medium;
      case 'high':
        return MaintenancePriority.high;
      case 'urgent':
        return MaintenancePriority.urgent;
      default:
        return null;
    }
  }

  void _openMaintenanceById(String id) {
    MaintenanceRequest? item;
    for (final m in _box.values) {
      if (m.id == id) {
        item = m;
        break;
      }
    }
    if (item == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MaintenanceDetailsScreen(item: item!)),
    );
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyScoped = (_propertyFilterId ?? '').isNotEmpty;
    final providerScoped = (_assignedToFilter ?? '').isNotEmpty;
    final providerCurrentScoped =
        providerScoped && _providerRequestsView == 'current';
    final providerHistoryScoped =
        providerScoped && _providerRequestsView == 'history';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // الدروَر يبدأ أسفل الـAppBar وينتهي فوق الـBottomNav
        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset = kToolbarHeight + media.padding.top;
            final double bottomInset = _bottomBarHeight + media.padding.bottom;
            return Padding(
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: MediaQuery.removePadding(
                context: ctx,
                removeTop: true,
                removeBottom: true,
                child: const AppSideDrawer(),
              ),
            );
          },
        ),

        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text(
              propertyScoped
                  ? 'طلبات الخدمات'
                  : (providerHistoryScoped
                      ? 'خدمات سابقة'
                      : (providerCurrentScoped ? 'طلبات الخدمات' : 'الخدمات')),
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20.sp)),
          actions: [
            IconButton(
              tooltip: 'تصفية',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
              onPressed: _openFilters,
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF0F766E),
                      Color(0xFF14B8A6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالعنوان/العقار/التكلفة',
                      hintStyle: GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ),
                if (_hasActiveFilters(
                  propertyScoped: propertyScoped,
                  providerScoped: providerScoped,
                ))
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded,
                                size: 16, color: Colors.white70),
                            SizedBox(width: 6.w),
                            Text(
                              _currentFilterLabel(
                                propertyScoped: propertyScoped,
                                providerCurrentScoped: providerCurrentScoped,
                                providerHistoryScoped: providerHistoryScoped,
                              ),
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _box.listenable(),
                    builder: (context, Box<MaintenanceRequest> box, _) {
                      final bool showArchivedEffective =
                          _archivedFilter ?? _showArchived;
                      final bool bypassArchiveFilter =
                          providerHistoryScoped || propertyScoped;

                      // 🚀 تحسين الأداء: لا نستدعي FirebaseAuth (عبر boxName) داخل الحلقة!
                      final String invBoxId = scope.boxName(bx.kInvoicesBox);
                      final Box<Invoice>? invBox = Hive.isBoxOpen(invBoxId)
                          ? Hive.box<Invoice>(invBoxId)
                          : null;

                      var items = box.values.toList();
                      if (!bypassArchiveFilter) {
                        items = items.where((e) {
                          // القاعدة الأساسية: الطلبات التي سُندها ملغى تعتبر مؤرشفة حكماً
                          final isInvCanceled =
                              _isInvoiceCanceledWithBox(e, invBox);
                          final effectiveArchived = e.isArchived || isInvCanceled;
                          return effectiveArchived == showArchivedEffective;
                        }).toList();
                      }

                      if (propertyScoped) {
                        final targetPropertyId = _propertyFilterId!;
                        items = items
                            .where((e) => e.propertyId == targetPropertyId)
                            .toList();
                      }
                      if (_statusFilter != null) {
                        items = items.where((e) {
                          if (_statusFilter == MaintenanceStatus.canceled) {
                            return e.status == MaintenanceStatus.canceled ||
                                _isInvoiceCanceledWithBox(e, invBox);
                          }
                          return e.status == _statusFilter;
                        }).toList();
                      }
                      if (_priorityFilter != null) {
                        items = items
                            .where((e) => e.priority == _priorityFilter)
                            .toList();
                      }
                      if ((_assignedToFilter ?? '').isNotEmpty) {
                        final target = _assignedToFilter!.toLowerCase().trim();
                        items = items
                            .where((e) =>
                                (e.assignedTo ?? '').toLowerCase().trim() ==
                                target)
                            .toList();
                      }
                      if (providerCurrentScoped) {
                        items = items
                            .where((e) =>
                                e.status == MaintenanceStatus.open ||
                                e.status == MaintenanceStatus.inProgress)
                            .toList();
                      } else if (providerHistoryScoped) {
                        items = items
                            .where((e) =>
                                e.status == MaintenanceStatus.completed ||
                                e.status == MaintenanceStatus.canceled)
                            .toList();
                      }

                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        // جرّب نحول الإدخال إلى رقم (نقبل 123 أو 123.45 وحتى مع فواصل)
                        final qNum = double.tryParse(
                            _q.replaceAll(RegExp(r'[^0-9.]'), ''));

                        items = items.where((m) {
                          // اسم العقار
                          final pMatch = _properties.values
                              .where((x) => x.id == m.propertyId);
                          final pn = pMatch.isNotEmpty
                              ? pMatch.first.name.toLowerCase()
                              : '';

                          final titleHit = m.title.toLowerCase().contains(q);
                          final descHit =
                              m.description.toLowerCase().contains(q);
                          final propHit = pn.contains(q);

                          // مطابقة التكلفة:
                          // - إذا المستخدم كتب رقمًا: نطابق مساواة تقريبية ±0.01
                          // - وإلا نعمل contains على سلسلة التكلفة
                          bool costHit = false;
                          if (qNum != null) {
                            costHit = (m.cost - qNum).abs() < 0.01;
                          } else {
                            final costStr =
                                _fmtMoneyTrunc(m.cost).toLowerCase();
                            costHit = costStr.contains(q);
                          }

                          return titleHit || descHit || propHit || costHit;
                        }).toList();
                      }

                      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                      if (items.isEmpty) {
                        final emptyText = providerHistoryScoped
                            ? 'لا توجد خدمات سابقة'
                            : (providerCurrentScoped
                                ? 'لا توجد طلبات خدمات'
                                : (showArchivedEffective
                                    ? (propertyScoped
                                        ? 'لا توجد طلبات مؤرشفة لهذا العقار'
                                        : 'لا توجد طلبات مؤرشفة')
                                    : (propertyScoped
                                        ? 'لا توجد طلبات خدمات لهذا العقار'
                                        : 'لا توجد طلبات خدمات')));
                        return Center(
                          child: Text(
                              emptyText,
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final m = items[i];

                          final pMatch = _properties.values
                              .where((x) => x.id == m.propertyId);
                          final p = pMatch.isNotEmpty ? pMatch.first : null;
                          final propertyName =
                              p?.name ?? _propertyFilterName ?? '—';

                          return InkWell(
                            borderRadius: BorderRadius.circular(16.r),
                            onLongPress: () async {
                              await _openRowMenu(context, m);
                            },
                            onTap: () async {
                              await Navigator.of(context)
                                  .push(MaterialPageRoute(
                                builder: (_) =>
                                    MaintenanceDetailsScreen(item: m),
                              ));
                            },
                            child: _DarkCard(
                              padding: EdgeInsets.all(12.w),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 52.w,
                                    height: 52.w,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.r),
                                      gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0F766E),
                                            Color(0xFF14B8A6)
                                          ],
                                          begin: Alignment.topRight,
                                          end: Alignment.bottomLeft),
                                    ),
                                    child: const Icon(Icons.build_rounded,
                                        color: Colors.white),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _limitChars(
                                                  _maintenanceDisplayServiceType(
                                                    m,
                                                  ),
                                                  60,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.cairo(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15.sp),
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                _chip(_statusText(m.status),
                                                    bg: _statusColor(m.status)),
                                                if (m.status ==
                                                        MaintenanceStatus
                                                            .completed &&
                                                    _isInvoiceCanceledSync(m))
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                        top: 4.h),
                                                    child: Text(
                                                      'ملغي',
                                                      style: GoogleFonts.cairo(
                                                        color: const Color(
                                                            0xFFEF4444),
                                                        fontSize: 10.sp,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 6.h),
                                        Text(
                                          propertyName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 6.h),
                                        Wrap(
                                          spacing: 6.w,
                                          runSpacing: 6.h,
                                          children: [
                                            _chip(
                                                'الأولوية: ${_priorityText(m.priority)}',
                                                bg: _priorityColor(m.priority)),
                                            _chip(
                                                'البدء: ${_fmtDateOrDashDynamic(m.scheduledDate)}',
                                                bg: const Color(0xFF1F2937)),
                                            if (_maintenanceDisplayServiceType(m)
                                                .isNotEmpty)
                                              _chip(
                                                  'النوع: ${_maintenanceDisplayServiceType(m)}',
                                                  bg: const Color(0xFF1F2937)),
                                            if (m.cost > 0)
                                              _chip(
                                                  'التكلفة: ${_fmtMoneyTrunc(m.cost)} ريال',
                                                  bg: const Color(0xFF1F2937)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_left_rounded,
                                      color: Colors.white70),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0, // لا توجد تبويبة "خدمات" ضمن الـBottomNav؛ اخترنا 0
          onTap: _handleBottomTap,
        ),

        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.add_rounded),
          label: Text('طلب جديد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            // 🚫 منع عميل المكتب من إضافة طلب خدمات
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final result =
                await Navigator.of(context).push<MaintenanceRequest?>(
              MaterialPageRoute(
                  builder: (_) => const AddOrEditMaintenanceScreen()),
            );
            if (result != null && context.mounted) {
              // رجعنا من إنشاء جديد بنجاح
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('تم إضافة طلب الخدمات',
                        style: GoogleFonts.cairo()),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MaintenanceDetailsScreen(item: result),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    final providerScoped = (_assignedToFilter ?? '').isNotEmpty;
    final propertyScoped = (_propertyFilterId ?? '').isNotEmpty;
    final providerSpecialScope = providerScoped &&
        (_providerRequestsView == 'current' ||
            _providerRequestsView == 'history');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        MaintenanceStatus? st = _statusFilter;
        MaintenancePriority? pr = _priorityFilter;
        bool? arch = _archivedFilter;

        return StatefulBuilder(
          builder: (ctx, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  16.h + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('التصفية',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  if (!providerSpecialScope) ...[
                    DropdownButtonFormField<MaintenanceStatus?>(
                      initialValue: st,
                      decoration: _dd('الحالة'),
                      dropdownColor: const Color(0xFF0F172A),
                      iconEnabledColor: Colors.white70,
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w700),
                      items: <MaintenanceStatus?>[null, ...MaintenanceStatus.values]
                          .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v == null
                                  ? 'الكل'
                                  : (v == MaintenanceStatus.canceled
                                      ? 'ملغية'
                                      : _statusText(v)))))
                          .toList(),
                      onChanged: (v) => setM(() {
                        st = v;
                        arch = st == MaintenanceStatus.canceled ? true : false;
                      }),
                    ),
                    SizedBox(height: 10.h),
                  ],

                  // 2) الأولوية
                  DropdownButtonFormField<MaintenancePriority?>(
                    initialValue: pr,
                    decoration: _dd('الأولوية'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    items: <MaintenancePriority?>[
                      null,
                      ...MaintenancePriority.values
                    ]
                        .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == null ? 'الكل' : _priorityText(v))))
                        .toList(),
                    onChanged: (v) => setM(() => pr = v),
                  ),
                  SizedBox(height: 10.h),

                  if (!providerSpecialScope && !propertyScoped) ...[
                    // 3) الأرشفة — مثل شاشة العقود
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('الأرشفة',
                          style: GoogleFonts.cairo(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('غير مؤرشف', style: GoogleFonts.cairo()),
                            selected: arch == false,
                            onSelected: (_) => setM(() => arch = false),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('مؤرشف', style: GoogleFonts.cairo()),
                            selected: arch == true,
                            onSelected: (_) => setM(() => arch = true),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          onPressed: () {
                            setState(() {
                              _statusFilter = providerSpecialScope ? null : st;
                              _priorityFilter = pr;
                              _archivedFilter =
                                  (providerSpecialScope || propertyScoped)
                                      ? null
                                      : (st == MaintenanceStatus.canceled
                                          ? true
                                          : arch);
                            });
                            Navigator.pop(context);
                          },
                          child: Text('تطبيق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _statusFilter = null;
                              _priorityFilter = null;
                              _archivedFilter = null;
                            });
                            Navigator.pop(context);
                          },
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openRowMenu(
    BuildContext context,
    MaintenanceRequest m,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إجراءات سريعة',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12.h),

                // تعديل
                if (m.status != MaintenanceStatus.completed &&
                    !_isInvoiceCanceledSync(m))
                  ListTile(
                    onTap: () async {
                      if (await OfficeClientGuard.blockIfOfficeClient(
                          sheetCtx)) {
                        return;
                      }

                      if (m.status == MaintenanceStatus.completed ||
                          m.status == MaintenanceStatus.canceled) {
                        Navigator.pop(sheetCtx);
                        await showEditBlockedDialog(sheetCtx);
                        return;
                      }

                      Navigator.pop(sheetCtx);
                      final updated =
                          await Navigator.of(context).push<MaintenanceRequest?>(
                        MaterialPageRoute(
                          builder: (_) =>
                              AddOrEditMaintenanceScreen(existing: m),
                        ),
                      );
                      if (updated != null && context.mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MaintenanceDetailsScreen(item: updated),
                          ),
                        );
                      }
                    },
                    leading:
                        const Icon(Icons.edit_rounded, color: Colors.white),
                    title: Text(
                      'تعديل',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                  ),

                // تغيير الحالة
                if (m.status != MaintenanceStatus.completed &&
                    m.status != MaintenanceStatus.canceled &&
                    !_isInvoiceCanceledSync(m))
                  ListTile(
                    onTap: () async {
                      if (await OfficeClientGuard.blockIfOfficeClient(
                          sheetCtx)) {
                        return;
                      }

                      Navigator.pop(sheetCtx);
                      await _changeStatus(
                        context,
                        m,
                        openDetailsAfterSave: true,
                      );
                    },
                    leading:
                        const Icon(Icons.flag_rounded, color: Colors.white),
                    title: Text(
                      'تغيير الحالة',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                  ),

                // أرشفة / فك الأرشفة
                ListTile(
                  onTap: () async {
                    if (await OfficeClientGuard.blockIfOfficeClient(sheetCtx)) {
                      return;
                    }

                    // 🚫 منع فك أرشفة طلب ملغي السند
                    if (_isInvoiceCanceledSync(m)) {
                      Navigator.pop(sheetCtx);
                      await _showServicesArchiveNoticeDialog(
                        sheetCtx,
                        message:
                            'لا يمكن إلغاء الأرشفة، الطلبات المكتملة التي صُدرت لها سندات ثم أُلغيت تُؤرشف تلقائيًا.',
                      );
                      return;
                    }

                    // لا نسمح بالأرشفة اليدوية مطلقًا، تتم تلقائيًا فقط بعد إلغاء السند
                    if (!m.isArchived) {
                      Navigator.pop(sheetCtx);
                      await _showArchiveBlockedDialog(sheetCtx);
                      return;
                    }

                    // 🚫 منع فك أرشفة طلب ملغي يدويًا
                    if (m.isArchived &&
                        m.status == MaintenanceStatus.canceled) {
                      Navigator.pop(sheetCtx);
                      await _showServicesArchiveNoticeDialog(
                        sheetCtx,
                        message:
                            'لا يمكن إلغاء الأرشفة، الطلبات المكتملة التي صُدرت لها سندات ثم أُلغيت تُؤرشف تلقائيًا.',
                      );
                      return;
                    }

                    Navigator.pop(sheetCtx);

                    final box = Hive.box<MaintenanceRequest>(
                      HiveService.maintenanceBoxName(),
                    );

                    final newArchived = !m.isArchived;
                    m.isArchived = newArchived;
                    await box.put(m.id, m);

                    // مزامنة مع السيرفر
                    unawaited(_maintenanceUpsertFS(m));

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            newArchived ? 'تم الأرشفة' : 'تم إلغاء الأرشفة',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      );
                    }
                  },
                  leading: Icon(
                    (m.isArchived || _isInvoiceCanceledSync(m))
                        ? Icons.unarchive_rounded
                        : Icons.archive_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    (m.isArchived || _isInvoiceCanceledSync(m))
                        ? 'فك الأرشفة'
                        : 'أرشفة',
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                ),

                // حذف
                if (!_isInvoiceCanceledSync(m))
                  ListTile(
                    onTap: () async {
                      if (await OfficeClientGuard.blockIfOfficeClient(
                          sheetCtx)) {
                        return;
                      }

                      // 🚫 منع حذف طلب الخدمات بعد اعتماده "مكتمل"
                      if (m.status == MaintenanceStatus.completed) {
                        Navigator.pop(sheetCtx);

                        await CustomConfirmDialog.show(
                          context: sheetCtx,
                          title: 'لا يمكن الحذف',
                          message:
                              'لا يمكن حذف طلب الخدمات بعد صدور السند الخاص بهذه الخدمة.\n'
                              'فقط يمكن إلغاء هذا الطلب عن طريق إلغاء السند الخاص بهذه الخدمة.',
                          confirmLabel: 'حسنًا',
                          showCancel: false,
                        );
                        return;
                      }

                      Navigator.pop(sheetCtx);

                      final ok = await _confirm(
                        sheetCtx,
                        'حذف الطلب',
                        'هل أنت متأكد من حذف هذا الطلب نهائيًا؟ لن تتمكن من استرجاعه مرة أخرى.',
                      );
                      if (!ok) return;

                      try {
                        await _deleteMaintenanceAndInvoice(m);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم الحذف',
                                style: GoogleFonts.cairo(),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تعذّر الحذف: $e',
                                style: GoogleFonts.cairo(),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.white,
                    ),
                    title: Text(
                      'حذف',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    return await CustomConfirmDialog.show(
      context: context,
      title: title,
      message: msg,
      cancelLabel: 'تراجع',
    );
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius: BorderRadius.all(Radius.circular(12))),
      );

  // ==== نافذة تغيير الحالة (مع إنشاء السند لمرة واحدة) ====
  Future<void> _changeStatus(
    BuildContext context,
    MaintenanceRequest m, {
    bool openDetailsAfterSave = false,
  }) async {
    // ✅ إن كانت الحالة الحالية "ملغاة" لعنصر قديم، عيّن الابتدائية "جديدة"
    MaintenanceStatus st = m.status == MaintenanceStatus.canceled
        ? MaintenanceStatus.open
        : m.status;

    final costCtl = TextEditingController(
        text: m.cost > 0 ? m.cost.toStringAsFixed(2) : '');
    DateTime? doneDate = m.completedDate;
    bool saving = false; // خارج StatefulBuilder

    // ✅ حذف "ملغاة" من خيارات تغيير الحالة
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16.w, 16.h, 16.w, 16.h + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تغيير حالة الطلب',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<MaintenanceStatus>(
                    initialValue: st,
                    decoration: _dd('اختر الحالة'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    items: statusesNoCanceled
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(_statusText(s))))
                        .toList(),
                    onChanged: (v) => setM(() {
                      st = v ?? st;
                      if (st == MaintenanceStatus.completed &&
                          doneDate == null) {
                        doneDate = KsaTime.today();
                      }
                    }),
                  ),
                  SizedBox(height: 10.h),
                  if (st == MaintenanceStatus.completed) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: const Color(0x334256F1),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: const Color(0x554256F1)),
                      ),
                      child: Text(
                          'تنبيه مهم: التكلفة ضرورية جدًا لعمل السند وحفظها في التقارير.',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: costCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'))
                      ],
                      style: GoogleFonts.cairo(color: Colors.white),
                      decoration: _dd('التكلفة الإجمالية'),
                    ),
                    SizedBox(height: 10.h),
                    InkWell(
                      borderRadius: BorderRadius.circular(12.r),
                      onTap: () async {
                        final now = KsaTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: doneDate ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                          helpText: 'تاريخ الإنهاء',
                          confirmText: 'اختيار',
                          cancelText: 'إلغاء',
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Colors.white,
                                onPrimary: Colors.black,
                                surface: Color(0xFF0B1220),
                                onSurface: Colors.white,
                              ),
                              dialogTheme: const DialogThemeData(
                                  backgroundColor: Color(0xFF0B1220)),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setM(() => doneDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: _dd('تاريخ الإنهاء'),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available,
                                color: Colors.white70),
                            SizedBox(width: 8.w),
                            Text(
                                _fmtDateOrDashDynamic(
                                    doneDate ?? KsaTime.now()),
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0EA5E9)),
                          onPressed: saving
                              ? null
                                : () async {
                                    setM(() => saving = true);
                                    try {
                                      m.status = st;
                                      if (st == MaintenanceStatus.canceled ||
                                          st == MaintenanceStatus.completed) {
                                        await markPeriodicServiceRequestSuppressedForCurrentCycle(
                                            m);
                                      }
                                      if (st == MaintenanceStatus.completed) {
                                        final c =
                                            double.tryParse(costCtl.text.trim());
                                      if (c != null && c >= 0) {
                                        m.cost = c;
                                      }
                                      m.completedDate =
                                          doneDate ?? KsaTime.now();

                                      final invId =
                                          await createOrUpdateInvoiceForMaintenance(
                                              m);
                                      if (invId.isNotEmpty) {
                                        m.invoiceId = invId;
                                      }
                                    }
                                    final box = Hive.box<MaintenanceRequest>(
                                        HiveService.maintenanceBoxName());

                                    if (m.isInBox) {
                                      await m.save();
                                    } else {
                                      await box.put(m.id, m);
                                    }

                                    unawaited(_maintenanceUpsertFS(m));

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      if (openDetailsAfterSave &&
                                          context.mounted) {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => MaintenanceDetailsScreen(
                                              item: m,
                                            ),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('تم تحديث الحالة',
                                                style: GoogleFonts.cairo()),
                                          ),
                                        );
                                      }
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('حدث خطأ أثناء الحفظ',
                                              style: GoogleFonts.cairo()),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setM(() => saving = false);
                                    }
                                  }
                                },
                          child: Text('حفظ',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// ===============================================================================
/// تفاصيل الطلب
/// ===============================================================================
class MaintenanceDetailsScreen extends StatefulWidget {
  final MaintenanceRequest item;
  const MaintenanceDetailsScreen({super.key, required this.item});

  @override
  State<MaintenanceDetailsScreen> createState() =>
      _MaintenanceDetailsScreenState();
}

class _MaintenanceDetailsScreenState extends State<MaintenanceDetailsScreen> {
  Box<Property> get _properties =>
      Hive.box<Property>(scope.boxName('propertiesBox'));
  Box<Tenant> get _tenants => Hive.box<Tenant>(scope.boxName('tenantsBox'));
  late MaintenanceRequest _liveItem;

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  @override
  void initState() {
    super.initState();
    _liveItem = widget.item;

    // ✅ الحل الجذري: توليد رقم الطلب فوراً إذا كان مفقوداً عند فتح التفاصيل
    if (_liveItem.serialNo == null || _liveItem.serialNo!.isEmpty) {
      Future.microtask(() async {
        try {
          final boxId = scope.boxName(bx.kMaintenanceBox);
          if (Hive.isBoxOpen(boxId)) {
            final box = Hive.box<MaintenanceRequest>(boxId);
            _liveItem.serialNo = _nextMaintenanceRequestSerial(box);
            await _liveItem.save();
            if (mounted) setState(() {});
          }
        } catch (e) {
          debugPrint('Failed to auto-assign serialNo on open: $e');
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  Future<void> _openAssignedProviderDetails(String rawName) async {
    final target = rawName.trim();
    if (target.isEmpty) return;
    Tenant? found;
    for (final t in _tenants.values) {
      if (t.fullName.trim() == target) {
        found = t;
        break;
      }
    }
    if (found == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => tenants_ui.TenantDetailsScreen(tenant: found!),
      ),
    );
  }

  Tenant? _findAssignedProvider(String? rawName) {
    final target = (rawName ?? '').trim();
    if (target.isEmpty) return null;
    for (final t in _tenants.values) {
      if (t.fullName.trim() == target) return t;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _ensureProviderSnapshotForItem(
      MaintenanceRequest item) async {
    final existing = _maintenanceProviderSnapshotMapOrNull(item.providerSnapshot);
    if (existing != null && existing.isNotEmpty) return existing;

    final provider = _findAssignedProvider(item.assignedTo);
    if (provider == null) return null;

    final snapshot = buildMaintenanceProviderSnapshot(provider);
    item.providerSnapshot = snapshot;

    final boxId = HiveService.maintenanceBoxName();
    if (item.isInBox) {
      await item.save();
    } else {
      if (!Hive.isBoxOpen(boxId)) {
        await Hive.openBox<MaintenanceRequest>(boxId);
      }
      await Hive.box<MaintenanceRequest>(boxId).put(item.id, item);
    }

    try {
      final invoiceId = (item.invoiceId ?? '').trim();
      if (invoiceId.isNotEmpty) {
        final invoicesBoxId = scope.boxName('invoicesBox');
        if (!Hive.isBoxOpen(invoicesBoxId)) {
          await Hive.openBox<Invoice>(invoicesBoxId);
        }
        final invBox = Hive.box<Invoice>(invoicesBoxId);
        final inv = invBox.get(invoiceId);
        if (inv != null) {
          final merged = Map<String, dynamic>.from(
              inv.maintenanceSnapshot ?? const <String, dynamic>{});
          merged['providerSnapshot'] = snapshot;
          if ((merged['assignedTo'] ?? '').toString().trim().isEmpty &&
              (item.assignedTo ?? '').trim().isNotEmpty) {
            merged['assignedTo'] = item.assignedTo!.trim();
          }
          inv.maintenanceSnapshot = merged;
          await inv.save();
        }
      }
    } catch (_) {}

    unawaited(_maintenanceUpsertFS(item));
    if (mounted) setState(() {});
    return snapshot;
  }

  Future<void> _openOriginalProviderFromSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final providerId =
        (_maintenanceProviderSnapshotString(snapshot, 'id') ?? '').trim();
    final providerName =
        (_maintenanceProviderSnapshotString(snapshot, 'fullName') ?? '').trim();
    Tenant? provider;
    if (providerId.isNotEmpty) {
      for (final t in _tenants.values) {
        if (t.id == providerId) {
          provider = t;
          break;
        }
      }
    }
    provider ??= _findAssignedProvider(providerName);
    if (provider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح مقدم الخدمة الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => tenants_ui.TenantDetailsScreen(tenant: provider!),
      ),
    );
  }

  Future<void> _openAssignedProviderForItem(MaintenanceRequest item) async {
    final useSnapshot =
        item.status == MaintenanceStatus.canceled || _isInvoiceCanceledSync(item);
    if (useSnapshot) {
      final snapshot = await _ensureProviderSnapshotForItem(item);
      if (snapshot == null || snapshot.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا تتوفر نسخة محفوظة من بيانات مقدم الخدمة لهذا الطلب.',
              style: GoogleFonts.cairo(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MaintenanceProviderSnapshotScreen(
            snapshot: snapshot,
            onAttachmentTap: _showAttachmentActions,
            onOpenOriginal: () => _openOriginalProviderFromSnapshot(snapshot),
          ),
        ),
      );
      return;
    }

    final provider = _findAssignedProvider(item.assignedTo);
    if (provider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح مقدم الخدمة لأنه غير موجود في البيانات الحالية.',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _openAssignedProviderDetails(item.assignedTo!);
  }

  String? _tenantRawPhone(Tenant? t) {
    if (t == null) return null;
    try {
      final v = (t as dynamic).phone;
      if (v is String && v.trim().isNotEmpty) return v;
    } catch (_) {}
    try {
      final v = (t as dynamic).phoneNumber;
      if (v is String && v.trim().isNotEmpty) return v;
    } catch (_) {}
    try {
      final v = (t as dynamic).mobile;
      if (v is String && v.trim().isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  String? _waNumberE164(Tenant? t) {
    var raw = _tenantRawPhone(t);
    if (raw == null) return null;
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    final looksInternational = d.length >= 11;
    if (!looksInternational && !d.startsWith('966')) d = '966$d';
    if (d.startsWith('9660')) d = '966${d.substring(4)}';
    if (d.length < 9) return null;
    return d;
  }

  String _buildWhatsAppMessage(MaintenanceRequest item, Tenant provider) {
    final providerName = provider.fullName.trim().isEmpty
        ? 'مقدم الخدمة'
        : provider.fullName.trim();
    final details =
        item.description.trim().isEmpty ? '—' : item.description.trim();
    final start = _fmtDateOrDashDynamic(item.scheduledDate);
    if (item.status == MaintenanceStatus.inProgress) {
      return 'السلام عليكم\n'
          'إلى: $providerName\n\n'
          'متابعة بخصوص طلب الخدمات التالي:\n'
          '- نوع الخدمة: ${_maintenanceDisplayServiceType(item)}\n'
          '- التفاصيل: $details\n'
          '- موعد بدء التنفيذ: $start\n'
          '- الحالة الحالية: ${_statusText(item.status)}\n\n'
          'نأمل إفادتنا بموعد الانتهاء المتوقع.\n'
          'شاكرين تعاونكم.';
    }
    return 'السلام عليكم\n'
        'إلى: $providerName\n\n'
        'نأمل تنفيذ طلب الخدمات التالي:\n'
        '- نوع الخدمة: ${_maintenanceDisplayServiceType(item)}\n'
        '- التفاصيل: $details\n'
        '- موعد بدء التنفيذ: $start\n'
        '- الأولوية: ${_priorityText(item.priority)}\n\n'
        'شاكرين تعاونكم.';
  }

  Future<void> _openWhatsAppForRequest(MaintenanceRequest item) async {
    final provider = _findAssignedProvider(item.assignedTo);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن العثور على مقدم الخدمة لهذا الطلب.',
              style: GoogleFonts.cairo()),
        ),
      );
      return;
    }
    final phone = _waNumberE164(provider);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يوجد رقم واتساب صالح لمقدم الخدمة.',
              style: GoogleFonts.cairo()),
        ),
      );
      return;
    }
    final message = _buildWhatsAppMessage(item, provider);
    final uri =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذّر فتح واتساب.', style: GoogleFonts.cairo()),
        ),
      );
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    return await CustomConfirmDialog.show(
      context: context,
      title: title,
      message: msg,
      cancelLabel: 'تراجع',
    );
  }

  // Fallback محلي لتغيير الحالة (يستخدم الدالة العلوية المشتركة)
  Future<void> _openChangeStatusSheetLocal(MaintenanceRequest m) async {
    // ✅ إن كانت الحالة الحالية "ملغاة" لعنصر قديم، عيّن الابتدائية "جديدة"
    MaintenanceStatus st = m.status == MaintenanceStatus.canceled
        ? MaintenanceStatus.open
        : m.status;

    final costCtl = TextEditingController(
        text: m.cost > 0 ? m.cost.toStringAsFixed(2) : '');
    DateTime? doneDate = m.completedDate;
    bool saving = false;

    // ✅ حذف "ملغاة" من خيارات تغيير الحالة
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16.w, 16.h, 16.w, 16.h + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تغيير حالة الطلب',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<MaintenanceStatus>(
                    initialValue: st,
                    decoration: InputDecoration(
                      labelText: 'اختر الحالة',
                      labelStyle: GoogleFonts.cairo(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    items: statusesNoCanceled
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(_statusText(s))))
                        .toList(),
                    onChanged: (v) => setM(() {
                      st = v ?? st;
                      if (st == MaintenanceStatus.completed &&
                          doneDate == null) {
                        doneDate = KsaTime.today();
                      }
                    }),
                  ),
                  SizedBox(height: 10.h),
                  if (st == MaintenanceStatus.completed) ...[
                    TextField(
                      controller: costCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'))
                      ],
                      style: GoogleFonts.cairo(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'التكلفة الإجمالية',
                        labelStyle: GoogleFonts.cairo(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.15))),
                        focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                            borderRadius:
                                BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    InkWell(
                      borderRadius: BorderRadius.circular(12.r),
                      onTap: () async {
                        final now = KsaTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: doneDate ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Colors.white,
                                onPrimary: Colors.black,
                                surface: Color(0xFF0B1220),
                                onSurface: Colors.white,
                              ),
                              dialogTheme: const DialogThemeData(
                                  backgroundColor: Color(0xFF0B1220)),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setM(() => doneDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'تاريخ الإنهاء',
                          labelStyle: GoogleFonts.cairo(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.15))),
                          focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12))),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available,
                                color: Colors.white70),
                            SizedBox(width: 8.w),
                            Text(
                                _fmtDateOrDashDynamic(
                                    doneDate ?? KsaTime.now()),
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0EA5E9)),
                          onPressed: saving
                              ? null
                                : () async {
                                    setM(() => saving = true);
                                    try {
                                      m.status = st;
                                      if (st == MaintenanceStatus.canceled ||
                                          st == MaintenanceStatus.completed) {
                                        await markPeriodicServiceRequestSuppressedForCurrentCycle(
                                            m);
                                      }
                                      if (st == MaintenanceStatus.completed) {
                                        final c =
                                            double.tryParse(costCtl.text.trim());
                                      if (c != null && c >= 0) {
                                        m.cost = c;
                                      }
                                      m.completedDate =
                                          doneDate ?? KsaTime.now();

                                      final invId =
                                          await createOrUpdateInvoiceForMaintenance(
                                              m);
                                      if (invId.isNotEmpty) {
                                        m.invoiceId = invId;
                                      }
                                    }
                                    final box = Hive.box<MaintenanceRequest>(
                                        HiveService.maintenanceBoxName());

                                    if (m.isInBox) {
                                      await m.save();
                                    } else {
                                      await box.put(m.id, m);
                                    }

                                    unawaited(_maintenanceUpsertFS(m));

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('تم تحديث الحالة',
                                              style: GoogleFonts.cairo()),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('حدث خطأ أثناء الحفظ',
                                              style: GoogleFonts.cairo()),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setM(() => saving = false);
                                    }
                                  }
                                },
                          child: Text('حفظ',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: Text('إغلاق',
                              style: GoogleFonts.cairo(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showDescriptionSheet(BuildContext context, MaintenanceRequest m) {
    final controller = TextEditingController(text: (m.description).trim());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16.w,
            16.h,
            16.w,
            16.h + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white70),
                  SizedBox(width: 8.w),
                  Text(
                    'الوصف',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: controller,
                maxLines: 6,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب وصف الطلب هنا…',
                  hintStyle: GoogleFonts.cairo(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        m.description = controller.text.trim();
                        final box = Hive.box<MaintenanceRequest>(
                            HiveService.maintenanceBoxName());

                        if (m.isInBox) {
                          await m.save();
                        } else {
                          await box.put(m.id, m);
                        }

                        unawaited(_maintenanceUpsertFS(m));
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم حفظ الوصف',
                                  style: GoogleFonts.cairo()),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          setState(() {}); // تحديث العرض
                        }
                      },
                      child: Text('حفظ',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إغلاق',
                          style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportMaintenancePdf(
      MaintenanceRequest item, Property? property) async {
    await PdfExportService.shareMaintenanceRequestDetailsPdf(
      context: context,
      details: MaintenanceReceiptDetails.fromRequest(item),
      property: property,
    );
  }

  Widget _sectionTitle(String t) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(t,
            style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14.sp)),
      );

  Widget _rowInfo(String label, String? value) {
    final has = (value ?? '').trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              has ? value! : '—',
              style:
                  GoogleFonts.cairo(color: has ? Colors.white : Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(String text, {Color bg = const Color(0xFF1E293B)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text,
          style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 11.sp,
              fontWeight: FontWeight.w800)),
    );
  }

  String _displayCurrency(String? currency) {
    if (currency == null || currency.isEmpty) return 'ريال';
    return currency;
  }

  @override
  Widget build(BuildContext context) {
    final item = _liveItem;
    final pMatch = _properties.values.where((x) => x.id == item.propertyId);
    final p = pMatch.isNotEmpty ? pMatch.first : null;
    final building = p?.parentBuildingId == null
        ? null
        : firstWhereOrNull(_properties.values, (x) => x.id == p!.parentBuildingId);
    final propertyDisplayName = (() {
      final ref = _maintenancePropertyReference(
        property: p,
        building: building,
      );
      return ref.isNotEmpty ? ref : '—';
    })();
    final providerSnapshot =
        _maintenanceProviderSnapshotMapOrNull(item.providerSnapshot);
    final providerDisplayName = (item.assignedTo ?? '').trim().isNotEmpty
        ? item.assignedTo
        : _maintenanceProviderSnapshotString(providerSnapshot, 'fullName');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset = kToolbarHeight + media.padding.top;
            final double bottomInset = _bottomBarHeight + media.padding.bottom;
            return Padding(
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: MediaQuery.removePadding(
                context: ctx,
                removeTop: true,
                removeBottom: true,
                child: const AppSideDrawer(),
              ),
            );
          },
        ),

        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text('تفاصيل الخدمة',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Export PDF',
              onPressed: () => _exportMaintenancePdf(item, p),
              icon:
                  const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            ),
            // ✅ أيقونة الأرشفة بالأعلى (بدل زر السند) + منع الأرشفة قبل «مكتملة»
            // ✅ أيقونة الأرشفة بالأعلى (بدل زر السند) + منع الأرشفة قبل «مكتملة»
            IconButton(
              tooltip: (item.isArchived || _isInvoiceCanceledSync(item))
                  ? 'فك الأرشفة'
                  : 'أرشفة',
              onPressed: () async {
                // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
                if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                  return;
                }

                // 🚫 منع فك أرشفة طلب ملغي السند
                if (_isInvoiceCanceledSync(item)) {
                  await _showServicesArchiveNoticeDialog(
                    context,
                    message:
                        'لا يمكن إلغاء الأرشفة، الطلبات المكتملة التي صُدرت لها سندات ثم أُلغيت تُؤرشف تلقائيًا.',
                  );
                  return;
                }

                // ✅ منع الأرشفة اليدوية مطلقًا، تتم تلقائيًا فقط بعد إلغاء السند
                if (!item.isArchived) {
                  await _showArchiveBlockedDialog(context);
                  return;
                }

                // الحالة الجديدة للأرشفة
                final bool newArchived = !item.isArchived;
                item.isArchived = newArchived;

                final box = Hive.box<MaintenanceRequest>(
                    HiveService.maintenanceBoxName());

                if (item.isInBox) {
                  await item.save();
                } else {
                  await box.put(item.id, item);
                }

                // ✅ مزامنة حالة الأرشفة مع السند المرتبط (إن وجدت)
                try {
                  if (item.invoiceId != null && item.invoiceId!.isNotEmpty) {
                    final invBox =
                        Hive.box<Invoice>(scope.boxName('invoicesBox'));
                    final inv = invBox.get(item.invoiceId);
                    if (inv != null) {
                      inv.isArchived = newArchived;
                      await inv.save();
                    }
                  }
                } catch (_) {
                  // تجاهل أي خطأ هنا حتى لا يمنع الأرشفة عن طلب الخدمات
                }

                unawaited(_maintenanceUpsertFS(item));

                if (context.mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newArchived ? 'تمت الأرشفة' : 'تم فك الأرشفة',
                        style: GoogleFonts.cairo(),
                      ),
                    ),
                  );
                }
              },
              icon: Icon(
                (item.isArchived || _isInvoiceCanceledSync(item))
                    ? Icons.inventory_2_rounded
                    : Icons.archive_rounded,
                color: Colors.white,
              ),
            ),

          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF0F766E),
                      Color(0xFF14B8A6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== بطاقة الرأس (مبسطة) =====
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 56.w,
                                  height: 56.w,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12.r),
                                    gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF0F766E),
                                          Color(0xFF14B8A6)
                                        ],
                                        begin: Alignment.topRight,
                                        end: Alignment.bottomLeft),
                                  ),
                                  child: const Icon(Icons.build_rounded,
                                      color: Colors.white),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_maintenanceDisplayServiceType(item),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16.sp)),
                                      SizedBox(height: 4.h),
                                      // اسم العقار (قابل للنقر دائمًا)
                                      InkWell(
                                        onTap: () async {
                                          if (p == null) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'تعذر فتح العقار لأنه غير موجود في البيانات الحالية.',
                                                  style: GoogleFonts.cairo(),
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                            return;
                                          }
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PropertyDetailsScreen(item: p),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          propertyDisplayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5.sp,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 8.h),
                                      _chip(
                                          'الأولوية: ${_priorityText(item.priority)}',
                                          bg: _priorityColor(item.priority)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // حالة الطلب (فوق على اليسار)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () async {
                              if (_isInvoiceCanceledSync(item)) return;
                              final host = context.findAncestorStateOfType<
                                  _MaintenanceScreenState>();
                              if (host != null) {
                                await host._changeStatus(context, item);
                              } else {
                                await _openChangeStatusSheetLocal(item);
                              }
                              if (mounted) setState(() {});
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _infoPill(_statusText(item.status),
                                    bg: _statusColor(item.status)),
                                if (_isInvoiceCanceledSync(item))
                                  Padding(
                                    padding: EdgeInsets.only(top: 4.h),
                                    child: Text(
                                      'ملغي',
                                      style: GoogleFonts.cairo(
                                        color: const Color(0xFFEF4444),
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ===== قسم تفاصيل الخدمة (جديد) =====
                  SizedBox(height: 10.h),
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('بيانات أساسية'),
                        _rowInfo('الرقم التسلسلي', item.serialNo),
                        _rowInfo(
                          'نوع الخدمة',
                          _maintenanceDisplayServiceType(item),
                        ),
                        _rowInfo('تاريخ البدء',
                            _fmtDateOrDashDynamic(item.scheduledDate)),
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('بيانات إضافية'),
                        _rowInfo(
                          'آخر موعد',
                          item.executionDeadline == null
                              ? null
                              : _fmtDateDynamic(item.executionDeadline!),
                        ),
                        if (item.completedDate != null)
                          _rowInfo(
                            'تاريخ الاكتمال',
                            _fmtDateDynamic(item.completedDate!),
                          ),
                        if ((providerDisplayName ?? '').trim().isNotEmpty)
                          _rowInfoAction(
                            'جهة التنفيذ',
                            providerDisplayName,
                            onTap: () async {
                              await _openAssignedProviderForItem(item);
                            },
                          )
                        else
                          _rowInfo('جهة التنفيذ', null),
                        _rowInfo(
                          'التكلفة',
                          item.cost > 0
                              ? '${_fmtMoneyTrunc(item.cost)} ${_displayCurrency('ريال')}'
                              : null,
                        ),
                        _rowInfo(
                          'الوصف',
                          item.description.trim().isEmpty
                              ? null
                              : item.description,
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: EntityAuditInfoButton(
                      collectionName: 'maintenance',
                      entityId: item.id,
                    ),
                  ),

                  SizedBox(height: 10.h),
                  if (item.attachmentPaths.isNotEmpty) ...[
                    _DarkCard(
                      padding: EdgeInsets.all(14.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                              'المرفقات (${item.attachmentPaths.length}/3)'),
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 8.w,
                            runSpacing: 8.h,
                            children: item.attachmentPaths.map((path) {
                              return InkWell(
                                onTap: () => _showAttachmentActions(path),
                                borderRadius: BorderRadius.circular(10.r),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10.r),
                                  child: Container(
                                    width: 92.w,
                                    height: 92.w,
                                    color: Colors.white.withOpacity(0.08),
                                    child: _buildAttachmentThumb(path),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10.h),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 6.h,
                      children: [
                        if (!_isInvoiceCanceledSync(item))
                          _miniAction(
                            icon: Icons.edit_rounded,
                            label: 'تعديل',
                            onTap: () async {
                              // 🚫 منع عميل المكتب من تعديل طلب الخدمات
                              if (await OfficeClientGuard.blockIfOfficeClient(
                                  context)) {
                                return;
                              }

                              if (item.status == MaintenanceStatus.completed) {
                                await showEditBlockedDialog(context);
                                return;
                              }

                              final updated = await Navigator.of(context)
                                  .push<MaintenanceRequest?>(
                                MaterialPageRoute(
                                  builder: (_) => AddOrEditMaintenanceScreen(
                                      existing: item),
                                ),
                              );
                              if (updated != null && context.mounted) {
                                setState(() => _liveItem = updated);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم التحديث',
                                      style: GoogleFonts.cairo(),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        if (!_isInvoiceCanceledSync(item))
                          _miniAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'حذف',
                            onTap: () =>
                                _deleteMaintenanceItemFromDetails(context, item),
                            bg: const Color(0xFF7F1D1D),
                          ),
                        if (!_isInvoiceCanceledSync(item) &&
                            (item.status == MaintenanceStatus.open ||
                                item.status == MaintenanceStatus.inProgress))
                          _miniAction(
                            icon: Icons.autorenew_rounded,
                            label: 'تغيير الحالة',
                            bg: const Color(0xFFF59E0B),
                            onTap: () async {
                              // 🚫 منع عميل المكتب من تغيير حالة الطلب
                              if (await OfficeClientGuard.blockIfOfficeClient(
                                  context)) {
                                return;
                              }

                              final host = context.findAncestorStateOfType<
                                  _MaintenanceScreenState>();
                              if (host != null) {
                                await host._changeStatus(context, item);
                              } else {
                                await _openChangeStatusSheetLocal(item);
                              }
                              if (mounted) setState(() {});
                            },
                          ),
                        if (item.status == MaintenanceStatus.open ||
                            item.status == MaintenanceStatus.inProgress)
                          _miniAction(
                            icon: Icons.chat_rounded,
                            label: 'واتس اب',
                            bg: const Color(0xFF059669),
                            onTap: () => _openWhatsAppForRequest(item),
                          ),
                        if (item.invoiceId?.isNotEmpty == true)
                          _miniAction(
                            icon: Icons.receipt_long_rounded,
                            label: 'عرض السند',
                            bg: const Color(0xFF0EA5E9),
                            onTap: () async {
                              // فتح تفاصيل السند مباشرة بدون المرور بشاشة قائمة السندات
                              if (item.invoiceId == null ||
                                  item.invoiceId!.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'لا يوجد سند مرتبط بهذا الطلب.',
                                      style: GoogleFonts.cairo(),
                                    ),
                                  ),
                                );
                                return;
                              }

                              try {
                                final invBox = Hive.box<Invoice>(
                                    scope.boxName('invoicesBox'));
                                final invoice = invBox.get(item.invoiceId);
                                if (invoice == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تعذّر العثور على السند المرتبط بهذا الطلب.',
                                        style: GoogleFonts.cairo(),
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        InvoiceDetailsScreen(invoice: invoice),
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'حدث خطأ أثناء فتح السند.',
                                      style: GoogleFonts.cairo(),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Widget _rowInfoAction(
    String label,
    String? value, {
    required VoidCallback onTap,
    Color valueColor = const Color(0xFFFBBF24),
  }) {
    final has = (value ?? '').trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: has
                ? InkWell(
                    onTap: onTap,
                    child: Text(
                      value!,
                      style: GoogleFonts.cairo(
                        color: valueColor,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                : Text(
                    '—',
                    style: GoogleFonts.cairo(color: Colors.white54),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMaintenanceItemFromDetails(
    BuildContext context,
    MaintenanceRequest item,
  ) async {
    if (await OfficeClientGuard.blockIfOfficeClient(context)) {
      return;
    }

    if (item.status == MaintenanceStatus.completed &&
        item.invoiceId?.isNotEmpty == true) {
      await CustomConfirmDialog.show(
        context: context,
        title: 'لا يمكن الحذف',
        message: 'لا يمكن حذف طلب الخدمات بعد صدور السند الخاص بهذه الخدمة.\n'
            'فقط يمكن إلغاء هذا الطلب عن طريق إلغاء السند الخاص بهذه الخدمة.',
        confirmLabel: 'حسنًا',
        showCancel: false,
      );
      return;
    }

    final ok = await _confirm(
      context,
      'حذف الطلب',
      'هل أنت متأكد من حذف هذا الطلب نهائيًا؟ لن تتمكن من استرجاعه مرة أخرى.',
    );
    if (!ok) return;

    try {
      await _deleteMaintenanceAndInvoice(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم الحذف',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذّر الحذف: $e',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
    }
  }

  bool _isImageAttachment(String path) {
    final lower = path.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isRemoteAttachment(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<String> _resolveRemoteUrl(String path) async {
    if (path.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }
    return path;
  }

  Future<String> _resolveRemoteImageUrl(String path) {
    return _remoteThumbUrls.putIfAbsent(path, () => _resolveRemoteUrl(path));
  }

  Widget _buildAttachmentThumb(String path) {
    if (_isImageAttachment(path)) {
      if (_isRemoteAttachment(path)) {
        return FutureBuilder<String>(
          future: _resolveRemoteImageUrl(path),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              );
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Colors.white70,
    );
  }

  Future<void> _showAttachmentActions(String path) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: Colors.white),
                title: Text('تحميل',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: Text('مشاركة',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  String _mimeFromPath(String path) {
    final p = path.toLowerCase().split('?').first;
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close();
    }
  }

  Future<bool> _ensureDownloadPermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      if (_isImageAttachment(path)) {
        final photos = await Permission.photos.request();
        if (photos.isGranted) return true;
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;
    } catch (_) {}
    return true;
  }

  Future<bool> _saveBytesToDownloads(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    try {
      final res = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      return res != null && res.isNotEmpty;
    } catch (e, s) {
      debugPrint('[attachments] download channel failed: $e');
      debugPrint('[attachments] download channel stack: $s');
      return false;
    }
  }

  Future<Directory?> _targetDownloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (dir.existsSync()) return dir;
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _downloadAttachment(String path) async {
    try {
      debugPrint('[attachments] download start: $path');
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
        debugPrint('[attachments] download permission denied');
        _showTopNotice('يلزم إذن التخزين لتحميل الملف', isError: true);
        return;
      }
      final String name;
      Uint8List bytes;
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final uri = Uri.tryParse(url);
        name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        bytes = await _downloadBytes(url);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] download local missing');
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        name = f.path.split(Platform.pathSeparator).last;
        bytes = await f.readAsBytes();
      }

      if (Platform.isAndroid) {
        final saved =
            await _saveBytesToDownloads(bytes, name, _mimeFromPath(name));
        if (!saved) {
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        _showTopNotice('تم التحميل');
        return;
      }

      final dir = await _targetDownloadsDir();
      if (dir == null) {
        debugPrint('[attachments] download target dir is null');
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      debugPrint('[attachments] download saved: ${dest.path}');
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
      debugPrint('[attachments] share start: $path');
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final bytes = await _downloadBytes(url);
        final uri = Uri.tryParse(url);
        final name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        await Share.shareXFiles([
          XFile.fromData(bytes, name: name, mimeType: _mimeFromPath(name)),
        ]);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] share local missing');
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        debugPrint('[attachments] share local path: ${f.path}');
        await Share.shareXFiles(
            [XFile(f.path, mimeType: _mimeFromPath(f.path))]);
      }
    } catch (e, s) {
      debugPrint('[attachments] share failed: $e');
      debugPrint('[attachments] share stack: $s');
      _showTopNotice('تعذر مشاركة المرفق', isError: true);
    }
  }

  void _showTopNotice(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 12;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), entry.remove);
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color bg = const Color(0xFF1E293B),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16.sp, color: Colors.white),
            SizedBox(width: 6.w),
            Text(label,
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp)),
          ],
        ),
      ),
    );
  }
}

Future<void> _deleteMaintenanceAndInvoice(MaintenanceRequest m) async {
  try {
    // 1) احذف السند المرتبط (لو فيه)
    if (m.invoiceId?.isNotEmpty == true) {
      final invBox = Hive.box<Invoice>(scope.boxName('invoicesBox'));
      if (invBox.containsKey(m.invoiceId)) {
        await invBox.delete(m.invoiceId);
      } else {
        for (final k in invBox.keys) {
          final v = invBox.get(k);
          if (v?.id == m.invoiceId) {
            await invBox.delete(k);
            break;
          }
        }
      }
    }

    // 2) احذف طلب الخدمات نفسه مع منع إعادة توليده تلقائيًا إن كان دوريًا.
    await deleteMaintenanceRequestOnlyLocalAndSync(m);
  } catch (e) {
    debugPrint('Delete maintenance/invoice failed: $e');
    rethrow;
  }
}

/// ===============================================================================
/// إنشاء/تعديل
/// ===============================================================================
class AddOrEditMaintenanceScreen extends StatefulWidget {
  final MaintenanceRequest? existing;
  const AddOrEditMaintenanceScreen({super.key, this.existing});

  @override
  State<AddOrEditMaintenanceScreen> createState() =>
      _AddOrEditMaintenanceScreenState();
}

class _AddOrEditMaintenanceScreenState
    extends State<AddOrEditMaintenanceScreen> {
  static const String _providerPickerNoSelection = '__provider_none__';
  final _formKey = GlobalKey<FormState>();

  Property? _property;
  Tenant? _selectedProvider;
  String? _providerError;
  bool _providerLockedFromArgs = false;
  bool _prefillApplied = false;

  final _title = TextEditingController();
  final _desc = TextEditingController();

  MaintenancePriority _priority = MaintenancePriority.medium;
  MaintenanceStatus _status = MaintenanceStatus.open;

  DateTime? _schedule;
  DateTime? _executionDeadline;
  final _cost = TextEditingController(text: '0');
  final List<String> _attachments = [];
  final Set<String> _initialLocalAttachments = <String>{};
  bool _uploadingAttachments = false;
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  DateTime? _lastExceedShownAt;

  void _showTempSnack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  TextInputFormatter _limitWithFeedbackFormatter({
    required int max,
    required String exceedMsg,
  }) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.length > max) {
        final now = KsaTime.now();
        if (_lastExceedShownAt == null ||
            now.difference(_lastExceedShownAt!).inMilliseconds > 800) {
          _lastExceedShownAt = now;
          _showTempSnack(exceedMsg);
        }
        return oldValue; // منع الزيادة
      }
      return newValue;
    });
  }

  String _normalizeLocalizedNumberText(String input) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const easternDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var text = input.trim();
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabicDigits[i], '$i');
      text = text.replaceAll(easternDigits[i], '$i');
    }
    return text
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('،', '');
  }

  double? _tryParseLocalizedDouble(String input) {
    final normalized = _normalizeLocalizedNumberText(input);
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  TextInputFormatter _moneyInputFormatter({
    required double max,
    required String exceedMsg,
  }) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty) return newValue;

      final normalized = _normalizeLocalizedNumberText(text);
      if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(normalized)) {
        return oldValue;
      }

      final value = double.tryParse(normalized);
      if (value == null) return oldValue;

      if (value > max) {
        final now = KsaTime.now();
        if (_lastExceedShownAt == null ||
            now.difference(_lastExceedShownAt!).inMilliseconds > 800) {
          _lastExceedShownAt = now;
          _showTempSnack(exceedMsg);
        }
        return oldValue;
      }

      return newValue;
    });
  }

  Box<MaintenanceRequest> get _box =>
      Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

  Box<Property> get _properties =>
      Hive.box<Property>(scope.boxName('propertiesBox'));
  Box<Tenant> get _tenants => Hive.box<Tenant>(scope.boxName('tenantsBox'));

  bool get isEdit => widget.existing != null;

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!isEdit && !_prefillApplied) {
      _prefillApplied = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        DateTime? readDate(dynamic v) {
          if (v is DateTime) return v;
          if (v is String) {
            try {
              return DateTime.parse(v);
            } catch (_) {
              return null;
            }
          }
          return null;
        }

        final pid = args['prefillPropertyId']?.toString();
        if ((pid ?? '').isNotEmpty) {
          final pMatch =
              _properties.values.where((p) => p.id == pid && !p.isArchived);
          if (pMatch.isNotEmpty) _property = pMatch.first;
        }

        final preTitle = args['prefillTitle']?.toString().trim() ?? '';
        if (preTitle.isNotEmpty && _title.text.trim().isEmpty) {
          _title.text = preTitle;
        }

        final preDesc = args['prefillDescription']?.toString().trim() ?? '';
        if (preDesc.isNotEmpty && _desc.text.trim().isEmpty) {
          _desc.text = preDesc;
        }

        final s = readDate(args['prefillScheduleDate']);
        if (s != null) _schedule = s;
        final d = readDate(args['prefillExecutionDeadline']);
        if (d != null) _executionDeadline = d;

        final preCost = args['prefillCost'];
        if (preCost != null) {
          final c = preCost is num
              ? preCost.toDouble()
              : double.tryParse(preCost.toString());
          if (c != null && c >= 0) {
            _cost.text = c.toStringAsFixed(2);
          }
        }

        final providerId = args['prefillProviderId']?.toString().trim() ?? '';
        final providerName =
            args['prefillProviderName']?.toString().trim() ?? '';
        if (providerId.isNotEmpty || providerName.isNotEmpty) {
          final providers = _tenants.values
              .where((t) => t.clientType == 'serviceProvider' && !t.isArchived);
          Tenant? match;
          if (providerId.isNotEmpty) {
            final byId = providers.where((t) => t.id == providerId);
            if (byId.isNotEmpty) match = byId.first;
          }
          if (match == null && providerName.isNotEmpty) {
            final byName =
                providers.where((t) => t.fullName.trim() == providerName);
            if (byName.isNotEmpty) match = byName.first;
          }
          if (match != null) {
            _selectedProvider = match;
            _providerError = null;
          }
        }

        _providerLockedFromArgs = args['prefillProviderLocked'] == true;
      }
    }

    if (isEdit) {
      final m = widget.existing!;
      if (_title.text.isEmpty && _desc.text.isEmpty) {
        // تحميل بيانات الطلب
        final pMatch = _properties.values.where((p) => p.id == m.propertyId);
        if (pMatch.isNotEmpty) _property = pMatch.first;

        _title.text = _maintenanceDisplayServiceType(m);
        _desc.text = m.description;
        _priority = m.priority;
        _status = m.status;
        _schedule = m.scheduledDate;
        _executionDeadline = m.executionDeadline;
        final providerSnapshot =
            _maintenanceProviderSnapshotMapOrNull(m.providerSnapshot);
        final providerId =
            (_maintenanceProviderSnapshotString(providerSnapshot, 'id') ?? '')
                .trim();
        if (providerId.isNotEmpty) {
          final providerMatch = _tenants.values.where((t) {
            return t.clientType == 'serviceProvider' &&
                !t.isArchived &&
                t.id == providerId;
          });
          if (providerMatch.isNotEmpty) {
            _selectedProvider = providerMatch.first;
          }
        }
        if (_selectedProvider == null && (m.assignedTo ?? '').trim().isNotEmpty) {
          final providerMatch = _tenants.values.where((t) {
            return t.clientType == 'serviceProvider' &&
                !t.isArchived &&
                t.fullName.trim() == m.assignedTo!.trim();
          });
          if (providerMatch.isNotEmpty) {
            _selectedProvider = providerMatch.first;
          }
        }
        if (m.cost > 0) _cost.text = m.cost.toStringAsFixed(2);
        _attachments
          ..clear()
          ..addAll(m.attachmentPaths);
        _initialLocalAttachments
          ..clear()
          ..addAll(_attachments.where((path) => !_isRemoteAttachment(path)));
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ حذف "ملغاة" من شاشة الإضافة/التعديل
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    return WillPopScope(
      onWillPop: () async => !_uploadingAttachments,
      child: AbsorbPointer(
        absorbing: _uploadingAttachments,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            drawer: Builder(
              builder: (ctx) {
                final media = MediaQuery.of(ctx);
                final double topInset = kToolbarHeight + media.padding.top;
                final double bottomInset =
                    _bottomBarHeight + media.padding.bottom;
                return Padding(
                  padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                  child: MediaQuery.removePadding(
                    context: ctx,
                    removeTop: true,
                    removeBottom: true,
                    child: const AppSideDrawer(),
                  ),
                );
              },
            ),

            appBar: AppBar(
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              leading: darvooLeading(context, iconColor: Colors.white),
              title: Text(isEdit ? 'تعديل طلب' : 'إضافة خدمة',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            body: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF0F766E),
                          Color(0xFF14B8A6)
                        ]),
                  ),
                ),
                Positioned(
                    top: -120,
                    right: -80,
                    child: _softCircle(220.r, const Color(0x33FFFFFF))),
                Positioned(
                    bottom: -140,
                    left: -100,
                    child: _softCircle(260.r, const Color(0x22FFFFFF))),
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                  child: _DarkCard(
                    padding: EdgeInsets.all(16.w),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // 1) العقار/الوحدة (مطلوب)
                          _selectorTile(
                            title: 'العقار/الوحدة (مطلوب)',
                            valueText: _property?.name ?? 'اختر عقارًا/وحدة',
                            onTap: _pickProperty,
                            leading: const Icon(Icons.home_work_rounded,
                                color: Colors.white),
                            errorText: _property == null ? 'مطلوب' : null,
                          ),
                          SizedBox(height: 12.h),

                          _field(
                            controller: _title,
                            label: 'نوع الخدمة',
                            inputFormatters: [
                              _limitWithFeedbackFormatter(
                                  max: 35,
                                  exceedMsg: 'تجاوزت الحد الأقصى (35)'),
                            ],
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'مطلوب';
                              if (s.length > 35) {
                                return 'تجاوزت الحد الأقصى (35) حرفاً';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 12.h),

                          _field(
                            controller: _desc,
                            label: 'الوصف',
                            maxLines: 4,
                            inputFormatters: [
                              _limitWithFeedbackFormatter(
                                max: 2000,
                                exceedMsg: 'تجاوزت الحد الأقصى (2000)',
                              ),
                            ],
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.length > 2000) {
                                return 'تجاوزت الحد الأقصى (2000) حرفاً';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 12.h),

                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<
                                    MaintenancePriority>(
                                  initialValue: _priority,
                                  decoration: _dd('الأولوية'),
                                  dropdownColor: const Color(0xFF0F172A),
                                  iconEnabledColor: Colors.white70,
                                  style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                  items: MaintenancePriority.values
                                      .map((p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(_priorityText(p))))
                                      .toList(),
                                  onChanged: (v) => setState(
                                      () => _priority = v ?? _priority),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child:
                                    DropdownButtonFormField<MaintenanceStatus>(
                                  initialValue: _status,
                                  decoration: _dd('الحالة'),
                                  dropdownColor: const Color(0xFF0F172A),
                                  iconEnabledColor: Colors.white70,
                                  style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                  items: statusesNoCanceled
                                      .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(_statusText(s))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _status = v ?? _status),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12.h),

                          InkWell(
                            borderRadius: BorderRadius.circular(12.r),
                            onTap: () async {
                              final now = KsaTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _schedule ?? now,
                                firstDate: DateTime(now.year - 1),
                                lastDate: DateTime(now.year + 2),
                                helpText: 'موعد بدء التنفيذ (اختياري)',
                                confirmText: 'اختيار',
                                cancelText: 'إلغاء',
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.white,
                                      onPrimary: Colors.black,
                                      surface: Color(0xFF0B1220),
                                      onSurface: Colors.white,
                                    ),
                                    dialogTheme: const DialogThemeData(
                                        backgroundColor: Color(0xFF0B1220)),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setState(() {
                                  _schedule = picked;
                                  if (_executionDeadline != null &&
                                      _executionDeadline!.isBefore(picked)) {
                                    _executionDeadline = null;
                                  }
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: _dd('موعد بدء التنفيذ (اختياري)'),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_rounded,
                                      color: Colors.white70),
                                  SizedBox(width: 8.w),
                                  Text(_fmtDateOrDashDynamic(_schedule),
                                      style: GoogleFonts.cairo(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 12.h),

                          InkWell(
                            borderRadius: BorderRadius.circular(12.r),
                            onTap: () async {
                              final now = KsaTime.now();
                              final firstAllowed = _schedule == null
                                  ? DateTime(now.year - 1)
                                  : DateTime(_schedule!.year, _schedule!.month,
                                          _schedule!.day)
                                      .add(const Duration(days: 0));
                              final initial = _executionDeadline ??
                                  (_schedule == null || _schedule!.isAfter(now)
                                      ? _schedule ?? now
                                      : now);
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initial.isBefore(firstAllowed)
                                    ? firstAllowed
                                    : initial,
                                firstDate: firstAllowed,
                                lastDate: DateTime(now.year + 2),
                                helpText: 'آخر موعد للتنفيذ (اختياري)',
                                confirmText: 'اختيار',
                                cancelText: 'إلغاء',
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.white,
                                      onPrimary: Colors.black,
                                      surface: Color(0xFF0B1220),
                                      onSurface: Colors.white,
                                    ),
                                    dialogTheme: const DialogThemeData(
                                        backgroundColor: Color(0xFF0B1220)),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setState(() => _executionDeadline = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: _dd('آخر موعد للتنفيذ (اختياري)'),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_busy_rounded,
                                      color: Colors.white70),
                                  SizedBox(width: 8.w),
                                  Text(
                                    _fmtDateOrDashDynamic(_executionDeadline),
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 12.h),

                          _selectorTile(
                            title: 'مقدم الخدمة (اختياري)',
                            valueText:
                                (_selectedProvider?.fullName ?? 'غير محدد'),
                            onTap:
                                _providerLockedFromArgs ? null : _pickProvider,
                            leading: const Icon(Icons.engineering_rounded,
                                color: Colors.white70),
                          ),
                          SizedBox(height: 12.h),
                          _field(
                            controller: _cost,
                            label: 'التكلفة (اختياري)',
                            textAlign: TextAlign.right,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              _moneyInputFormatter(
                                max: 100000000,
                                exceedMsg: 'تجاوزت الحد الأقصى (100,000,000)',
                              ),
                            ],
                          ),

                          SizedBox(height: 12.h),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'يمكنك إضافة صور لهذا الطلب (اختياري)',
                              style: GoogleFonts.cairo(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'المرفقات (${_attachments.length}/3)',
                                  style: GoogleFonts.cairo(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0EA5E9),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _uploadingAttachments
                                    ? null
                                    : _pickAttachments,
                                icon: _uploadingAttachments
                                    ? SizedBox(
                                        width: 16.w,
                                        height: 16.w,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.attach_file_rounded),
                                label: Text(
                                  'إرفاق',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          if (_attachments.isNotEmpty) ...[
                            SizedBox(height: 10.h),
                            Wrap(
                              spacing: 8.w,
                              runSpacing: 8.h,
                              children: _attachments.map((path) {
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    InkWell(
                                      onTap: () => _showAttachmentActions(path),
                                      borderRadius: BorderRadius.circular(10.r),
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        child: Container(
                                          width: 88.w,
                                          height: 88.w,
                                          color: Colors.white.withOpacity(0.08),
                                          child: _buildAttachmentThumb(path),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            _confirmRemoveAttachment(path),
                                        child: Container(
                                          width: 28.w,
                                          height: 28.w,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFB91C1C),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 16.sp,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                          SizedBox(height: 16.h),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0EA5E9),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r)),
                              ),
                              onPressed: _save,
                              icon: const Icon(Icons.save_rounded),
                              label: Text(
                                  isEdit ? 'حفظ التعديلات' : 'حفظ الطلب',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_uploadingAttachments)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: false,
                      child: Container(
                        color: Colors.black.withOpacity(0.30),
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 18.w, vertical: 14.h),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.90),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20.w,
                                height: 20.w,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2.4),
                              ),
                              SizedBox(width: 10.w),
                              Text(
                                'جاري المعالجة...',
                                style: GoogleFonts.cairo(
                                  color: const Color(0xFF111827),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // ——— Bottom Nav
            bottomNavigationBar: AppBottomNav(
              key: _bottomNavKey,
              currentIndex: 0,
              onTap: _handleBottomTap,
            ),
          ),
        ),
      ),
    );
  }

  // عناصر الإدخال المشتركة
  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius: BorderRadius.all(Radius.circular(12))),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
    TextAlign textAlign = TextAlign.start,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      textAlign: textAlign,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: _dd(label),
    );
  }

  Widget _selectorTile({
    required String title,
    required String valueText,
    required VoidCallback? onTap,
    required Widget leading,
    String? errorText,
  }) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: onTap,
          child: InputDecorator(
            decoration: _dd(title).copyWith(errorText: errorText),
            child: Row(
              children: [
                leading,
                SizedBox(width: 8.w),
                Expanded(
                    child: Text(valueText,
                        style: GoogleFonts.cairo(
                            color: Colors.white, fontWeight: FontWeight.w700))),
                const Icon(Icons.arrow_drop_down, color: Colors.white70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickProperty() async {
    final result = await showModalBottomSheet<Property>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _PropertyPickerSheet(),
    );
    if (result != null) {
      setState(() {
        _property = result;
      });
    }
  }

  Future<void> _pickProvider() async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _ProviderPickerSheet(),
    );
    if (result == _providerPickerNoSelection) {
      setState(() {
        _selectedProvider = null;
        _providerError = null;
      });
      return;
    }
    if (result is Tenant) {
      setState(() {
        _selectedProvider = result;
        _providerError = null;
      });
    }
  }

  Future<void> _save() async {
    // التحقق من صحة الحقول
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // يجب اختيار عقار/وحدة
    if (_property == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اختر العقار/الوحدة',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }
    // قراءة التكلفة (إن وجدت)
    if (_schedule != null &&
        _executionDeadline != null &&
        _executionDeadline!.isBefore(_schedule!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'آخر موعد للتنفيذ يجب أن يكون في نفس يوم أو بعد موعد بدء التنفيذ',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }

    final cost = _tryParseLocalizedDouble(_cost.text.trim());
    final normalizedCost = cost == null || cost < 0 ? 0.0 : cost;
    final normalizedServiceType =
        _normalizeMaintenanceRequestTypeForStorage(_title.text);
    final m = widget.existing;
    final providerSnapshot = _selectedProvider == null
        ? null
        : buildMaintenanceProviderSnapshot(_selectedProvider!);

    // ==========================
    // حالة "تعديل" طلب موجود
    // ==========================
    if (isEdit && m != null) {
      final removedLocalAttachments = _removedInitialLocalAttachments();
      m.propertyId = _property!.id;
      m.tenantId = maintenanceLinkedPartyIdForProperty(
        _property!.id,
        serviceType: normalizedServiceType,
      );
      m.title = normalizedServiceType;
      m.description = _desc.text.trim();
      m.requestType = normalizedServiceType;
      m.priority = _priority;
      m.status = _status;
      m.scheduledDate = _schedule;
      m.executionDeadline = _executionDeadline;
      m.assignedTo = _selectedProvider?.fullName.trim();
      m.providerSnapshot = providerSnapshot;
      m.cost = normalizedCost;
      m.attachmentPaths = List<String>.from(_attachments);
      if (_status == MaintenanceStatus.canceled ||
          _status == MaintenanceStatus.completed) {
        await markPeriodicServiceRequestSuppressedForCurrentCycle(m);
      }

      // ✅ لو الحالة الآن "مكتمل" ولا يوجد سند بعد → نصدر/نحدّث السند
      if (_status == MaintenanceStatus.completed &&
          (m.invoiceId == null || m.invoiceId!.isEmpty)) {
        // لو ما في completedDate نحط الآن
        m.completedDate ??= KsaTime.now();

        final invId = await createOrUpdateInvoiceForMaintenance(m);
        if (invId.isNotEmpty) {
          m.invoiceId = invId;
        }
      }

      final box =
          Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

      if (m.isInBox) {
        await m.save();
      } else {
        await box.put(m.id, m);
      }

      unawaited(_maintenanceUpsertFS(m));
      await _deleteLocalAttachments(removedLocalAttachments);

      if (!mounted) return;
      Navigator.of(context).pop(m);
    }

    // ==========================
    // حالة "إضافة" طلب جديد
    // ==========================
    else {
      final boxId = scope.boxName(bx.kMaintenanceBox);
      final mBox = Hive.box<MaintenanceRequest>(boxId);
      final nextSerial = _nextMaintenanceRequestSerial(mBox);

      final n = MaintenanceRequest(
        serialNo: nextSerial,
        propertyId: _property!.id,
        tenantId: maintenanceLinkedPartyIdForProperty(
          _property!.id,
          serviceType: normalizedServiceType,
        ),
        title: normalizedServiceType,
        description: _desc.text.trim(),
        requestType: normalizedServiceType,
        priority: _priority,
        status: _status,
        scheduledDate: _schedule,
        executionDeadline: _executionDeadline,
        // لو أضفنا الطلب مباشرة كمكتمل نضع completedDate الآن
        completedDate:
            _status == MaintenanceStatus.completed ? KsaTime.now() : null,
        assignedTo: _selectedProvider?.fullName.trim(),
        providerSnapshot: providerSnapshot,
        cost: normalizedCost,
        attachmentPaths: List<String>.from(_attachments),
      );

      // ✅ لو الطلب جديد وتم حفظه مباشرة بحالة "مكتمل" → نصدر السند فورًا
      if (_status == MaintenanceStatus.completed) {
        final invId = await createOrUpdateInvoiceForMaintenance(n);
        if (invId.isNotEmpty) {
          n.invoiceId = invId;
        }
      }

      await mBox.put(n.id, n);
      unawaited(_maintenanceUpsertFS(n));

      if (!mounted) return;
      Navigator.of(context).pop(n);
    }
  }

  bool _isImageAttachment(String path) {
    final lower = path.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isRemoteAttachment(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<String> _resolveRemoteUrl(String path) async {
    if (path.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }
    return path;
  }

  Future<String> _resolveRemoteImageUrl(String path) {
    return _remoteThumbUrls.putIfAbsent(path, () => _resolveRemoteUrl(path));
  }

  Widget _buildAttachmentThumb(String path) {
    if (_isImageAttachment(path)) {
      if (_isRemoteAttachment(path)) {
        return FutureBuilder<String>(
          future: _resolveRemoteImageUrl(path),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              );
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Colors.white70,
    );
  }

  Future<void> _showAttachmentActions(String path) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: Colors.white),
                title: Text('تحميل',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: Text('مشاركة',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadToFile(String url, File outFile) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(res);
      await outFile.writeAsBytes(bytes, flush: true);
    } finally {
      client.close();
    }
  }

  String _mimeFromPath(String path) {
    final p = path.toLowerCase().split('?').first;
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close();
    }
  }

  Future<bool> _ensureDownloadPermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      if (_isImageAttachment(path)) {
        final photos = await Permission.photos.request();
        if (photos.isGranted) return true;
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;
    } catch (_) {}
    return true;
  }

  Future<bool> _saveBytesToDownloads(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    try {
      final res = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      return res != null && res.isNotEmpty;
    } catch (e, s) {
      debugPrint('[attachments] download channel failed: $e');
      debugPrint('[attachments] download channel stack: $s');
      return false;
    }
  }

  Future<Directory?> _targetDownloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (dir.existsSync()) return dir;
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _downloadAttachment(String path) async {
    try {
      debugPrint('[attachments] download start: $path');
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
        debugPrint('[attachments] download permission denied');
        _showTopNotice('يلزم إذن التخزين لتحميل الملف', isError: true);
        return;
      }
      final String name;
      Uint8List bytes;
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final uri = Uri.tryParse(url);
        name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        bytes = await _downloadBytes(url);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] download local missing');
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        name = f.path.split(Platform.pathSeparator).last;
        bytes = await f.readAsBytes();
      }

      if (Platform.isAndroid) {
        final saved =
            await _saveBytesToDownloads(bytes, name, _mimeFromPath(name));
        if (!saved) {
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        _showTopNotice('تم التحميل');
        return;
      }

      final dir = await _targetDownloadsDir();
      if (dir == null) {
        debugPrint('[attachments] download target dir is null');
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      debugPrint('[attachments] download saved: ${dest.path}');
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
      debugPrint('[attachments] share start: $path');
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final bytes = await _downloadBytes(url);
        final uri = Uri.tryParse(url);
        final name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        await Share.shareXFiles([
          XFile.fromData(bytes, name: name, mimeType: _mimeFromPath(name)),
        ]);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] share local missing');
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        debugPrint('[attachments] share local path: ${f.path}');
        await Share.shareXFiles(
            [XFile(f.path, mimeType: _mimeFromPath(f.path))]);
      }
    } catch (e, s) {
      debugPrint('[attachments] share failed: $e');
      debugPrint('[attachments] share stack: $s');
      _showTopNotice('تعذر مشاركة المرفق', isError: true);
    }
  }

  void _showTopNotice(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 12;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable =
            await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      Uri? uri;
      if (_isRemoteAttachment(launchable)) {
        uri = Uri.tryParse(launchable);
      } else {
        final f = File(launchable);
        if (!f.existsSync()) throw Exception('attachment missing');
        uri = Uri.file(f.path);
      }
      if (uri == null) throw Exception('bad uri');

      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && mounted) {
        _showTempSnack('تعذر تحميل المرفق');
      }
    } catch (_) {
      if (!mounted) return;
      _showTempSnack('تعذر تحميل المرفق');
    }
  }

  Future<String?> _uploadAttachmentToStorage(
    File localFile,
    String fileName,
  ) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('maintenance_attachments')
          .child(fileName);
      await ref.putFile(localFile);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
          '${docs.path}${Platform.pathSeparator}maintenance_attachments');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName =
          '${KsaTime.now().microsecondsSinceEpoch}_${safeName.isEmpty ? 'doc' : safeName}';
      final outFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (file.bytes != null) {
        await outFile.writeAsBytes(file.bytes!, flush: true);
        return outFile.path;
      }
      final src = file.path;
      if (src != null && src.isNotEmpty) {
        await File(src).copy(outFile.path);
        return outFile.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= 3) {
      _showTempSnack('لا يمكن رفع أكثر من 3');
      return;
    }

    final remaining = 3 - _attachments.length;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final selectedFiles = picked.files.take(remaining).toList();
    if (picked.files.length > remaining) {
      _showTempSnack('لا يمكن رفع أكثر من 3');
    }

    setState(() => _uploadingAttachments = true);
    try {
      int failed = 0;
      for (final file in selectedFiles) {
        final localPath = await _saveAttachmentLocally(file);
        if (localPath == null) {
          failed += 1;
          continue;
        }
        if (!_attachments.contains(localPath)) {
          _attachments.add(localPath);
        }
      }
      if (failed > 0) {
        _showTempSnack('تعذر حفظ $failed مرفق');
      }
      if (mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _uploadingAttachments = false);
    }
  }

  List<String> _removedInitialLocalAttachments() {
    final currentPaths = _attachments
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return _initialLocalAttachments
        .where((path) => !currentPaths.contains(path))
        .toList(growable: false);
  }

  Future<void> _deleteLocalAttachments(Iterable<String> paths) async {
    final uniquePaths = paths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_isRemoteAttachment(e))
        .toSet();
    for (final path in uniquePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmRemoveAttachment(String path) async {
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف المرفق؟ لن يتم استرجاعه مجددًا.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (ok != true || !mounted) return;
    setState(() => _attachments.remove(path));
  }
}

/// ===============================================================================
/// Picker للعقار فقط
/// ===============================================================================
Widget _maintenancePropertyPickerHandle() {
  return Container(
    width: 44.w,
    height: 5.h,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(999.r),
    ),
  );
}

Widget _maintenancePropertyPickerHeader({
  required String title,
  required String subtitle,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15.sp,
        ),
      ),
      SizedBox(height: 4.h),
      Text(
        subtitle,
        style: GoogleFonts.cairo(
          color: Colors.white60,
          fontWeight: FontWeight.w600,
          fontSize: 12.sp,
          height: 1.6,
        ),
      ),
    ],
  );
}

InputDecoration _maintenancePropertyPickerSearchDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: GoogleFonts.cairo(color: Colors.white70),
    prefixIcon: const Icon(Icons.search, color: Colors.white70),
    filled: true,
    fillColor: Colors.white.withOpacity(0.08),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.r),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.r),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Colors.white),
      borderRadius: BorderRadius.circular(12.r),
    ),
  );
}

class _PropertyPickerSheet extends StatefulWidget {
  const _PropertyPickerSheet();

  @override
  State<_PropertyPickerSheet> createState() => _PropertyPickerSheetState();
}

class _PropertyPickerSheetState extends State<_PropertyPickerSheet> {
  Box<Property> get _properties =>
      Hive.box<Property>(scope.boxName('propertiesBox'));
  String _q = '';
  final Set<String> _expandedBuildingIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rawSheetHeight = media.size.height * 0.72;
    final availableHeight =
        media.size.height - media.viewInsets.bottom - 12.h;
    final sheetHeight =
        availableHeight > 0 && availableHeight < rawSheetHeight
            ? availableHeight
            : rawSheetHeight;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _maintenancePropertyPickerHandle()),
                SizedBox(height: 14.h),
                _maintenancePropertyPickerHeader(
                  title: 'اختيار العقار أو الوحدة',
                  subtitle:
                      'اختر العقار أو الوحدة التي تريد ربط الخدمة بها',
                ),
                SizedBox(height: 12.h),
                TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  style: GoogleFonts.cairo(color: Colors.white),
                  decoration: _maintenancePropertyPickerSearchDecoration(
                    'ابحث باسم العقار أو العنوان',
                  ),
                ),
                SizedBox(height: 10.h),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _properties.listenable(),
                    builder: (context, Box<Property> b, _) {
                    final allItems =
                        b.values.where((p) => !p.isArchived).toList();
                    final query = _q.toLowerCase();
                    bool matches(Property p) =>
                        query.isEmpty ||
                        p.name.toLowerCase().contains(query) ||
                        p.address.toLowerCase().contains(query);

                    final topLevel = allItems
                        .where((p) => p.parentBuildingId == null)
                        .toList();
                    final unitsByBuilding = <String, List<Property>>{};
                    for (final p in allItems) {
                      final parentId = p.parentBuildingId;
                      if (parentId == null) continue;
                      final list = unitsByBuilding.putIfAbsent(
                          parentId, () => <Property>[]);
                      list.add(p);
                    }
                    for (final units in unitsByBuilding.values) {
                      units.sort((a, c) => a.name.compareTo(c.name));
                    }
                    topLevel.sort((a, c) {
                      final aIsBuildingWithUnits =
                          a.type == PropertyType.building &&
                              (unitsByBuilding[a.id]?.isNotEmpty ?? false);
                      final cIsBuildingWithUnits =
                          c.type == PropertyType.building &&
                              (unitsByBuilding[c.id]?.isNotEmpty ?? false);
                      if (aIsBuildingWithUnits != cIsBuildingWithUnits) {
                        return aIsBuildingWithUnits ? -1 : 1;
                      }
                      return a.name.compareTo(c.name);
                    });

                    final hasAny = topLevel.any((p) {
                      final units = unitsByBuilding[p.id] ?? const <Property>[];
                      if (p.type == PropertyType.building && units.isNotEmpty) {
                        return matches(p) || units.any(matches);
                      }
                      return matches(p);
                    });
                    if (!hasAny) {
                      return Center(
                        child: Text(
                          'لا توجد عناصر',
                          style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }

                    final widgets = <Widget>[];
                    for (final p in topLevel) {
                      final units = unitsByBuilding[p.id] ?? const <Property>[];
                      final isBuildingWithUnits =
                          p.type == PropertyType.building && units.isNotEmpty;

                      if (isBuildingWithUnits) {
                        final showBuilding = matches(p);
                        final visibleUnits = showBuilding
                            ? units
                            : units.where(matches).toList(growable: false);
                        if (!showBuilding && visibleUnits.isEmpty) {
                          continue;
                        }
                        final expanded = _expandedBuildingIds.contains(p.id) ||
                            query.isNotEmpty;
                        widgets.add(
                          Container(
                            margin: EdgeInsets.only(bottom: 6.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10)),
                            ),
                            child: ExpansionTile(
                              key: ValueKey('building_${p.id}'),
                              initiallyExpanded: expanded,
                              onExpansionChanged: (isOpen) {
                                setState(() {
                                  if (isOpen) {
                                    _expandedBuildingIds.add(p.id);
                                  } else {
                                    _expandedBuildingIds.remove(p.id);
                                  }
                                });
                              },
                              iconColor: Colors.white70,
                              collapsedIconColor: Colors.white70,
                              title: Text(
                                p.name,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                p.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(color: Colors.white70),
                              ),
                              childrenPadding:
                                  EdgeInsets.only(right: 8.w, left: 8.w),
                              children: [
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10.w, vertical: 0),
                                  onTap: () => Navigator.of(context).pop(p),
                                  leading: const Icon(Icons.apartment_rounded,
                                      color: Colors.white70),
                                  title: Text(
                                    'اختيار العمارة نفسها',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                for (final u in visibleUnits)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 0),
                                    onTap: () => Navigator.of(context).pop(u),
                                    leading: const Icon(
                                      Icons.meeting_room_rounded,
                                      color: Colors.white70,
                                    ),
                                    title: Text(
                                      u.name,
                                      style: GoogleFonts.cairo(
                                          color: Colors.white),
                                    ),
                                    subtitle: (u.address).trim().isEmpty
                                        ? null
                                        : Text(
                                            u.address,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.cairo(
                                                color: Colors.white70),
                                          ),
                                  ),
                              ],
                            ),
                          ),
                        );
                        continue;
                      }

                      if (!matches(p)) continue;
                      widgets.add(
                        Padding(
                          padding: EdgeInsets.only(bottom: 6.h),
                          child: ListTile(
                            onTap: () => Navigator.of(context).pop(p),
                            leading: const Icon(Icons.home_work_rounded,
                                color: Colors.white),
                            title: Text(
                              p.name,
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                            subtitle: Text(
                              p.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(color: Colors.white70),
                            ),
                          ),
                        ),
                      );
                    }

                    return Scrollbar(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: widgets,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _ProviderPickerSheet extends StatefulWidget {
  const _ProviderPickerSheet();

  @override
  State<_ProviderPickerSheet> createState() => _ProviderPickerSheetState();
}

class _ProviderPickerSheetState extends State<_ProviderPickerSheet> {
  Box<Tenant> get _tenants => Hive.box<Tenant>(scope.boxName('tenantsBox'));
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم مقدم الخدمة',
                  hintStyle: GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _tenants.listenable(),
                  builder: (context, Box<Tenant> b, _) {
                    var items = b.values
                        .where((t) =>
                            t.clientType == 'serviceProvider' && !t.isArchived)
                        .toList();
                    if (_q.isNotEmpty) {
                      final q = _q.toLowerCase();
                      items = items
                          .where((t) =>
                              t.fullName.toLowerCase().contains(q) ||
                              (t.serviceSpecialization ?? '')
                                  .toLowerCase()
                                  .contains(q))
                          .toList();
                    }
                    items.sort((a, c) => a.fullName.compareTo(c.fullName));

                    if (items.isEmpty) {
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            onTap: () => Navigator.of(context).pop(
                                _AddOrEditMaintenanceScreenState
                                    ._providerPickerNoSelection),
                            leading: const Icon(Icons.remove_circle_outline_rounded,
                                color: Colors.white70),
                            title: Text(
                              'غير محدد',
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Center(
                            child: Text(
                              'لا يوجد مزودو خدمة',
                              style: GoogleFonts.cairo(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length + 1,
                      separatorBuilder: (_, __) => SizedBox(height: 6.h),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return ListTile(
                            onTap: () => Navigator.of(context).pop(
                                _AddOrEditMaintenanceScreenState
                                    ._providerPickerNoSelection),
                            leading:
                                const Icon(Icons.remove_circle_outline_rounded,
                                    color: Colors.white70),
                            title: Text(
                              'غير محدد',
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                          );
                        }
                        final t = items[i - 1];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(t),
                          leading: const Icon(Icons.engineering_rounded,
                              color: Colors.white),
                          title: Text(
                            t.fullName,
                            style: GoogleFonts.cairo(color: Colors.white),
                          ),
                          subtitle: Text(
                            (t.serviceSpecialization ?? '').trim().isEmpty
                                ? 'بدون تخصص محدد'
                                : t.serviceSpecialization!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(color: Colors.white70),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================================
/// مسارات NamedRoutes
/// ===============================================================================
class MaintenanceRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/maintenance': (context) => const MaintenanceScreen(),
        '/maintenance/new': (context) => const AddOrEditMaintenanceScreen(),
      };
}
