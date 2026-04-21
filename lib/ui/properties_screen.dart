// lib/ui/properties_screen.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/package_limit_service.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart'; // أو المسار الصحيح حسب مكان الملف
import '../data/services/offline_sync_service.dart';
import 'dart:async' show unawaited;
import '../widgets/darvoo_app_bar.dart';
import '../widgets/custom_confirm_dialog.dart';

// 👇 هذا السطر الجديد لاستيراد نوع العقد نفسه
import 'contracts_screen.dart'
    show Contract, ContractDetailsScreen, linkWaterConfigToContractIfNeeded;
import 'invoices_screen.dart' show Invoice;
import 'maintenance_screen.dart' show MaintenanceRequest;

import '../models/property.dart';
import '../models/tenant.dart';

// للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'tenants_screen.dart';
import 'contracts_screen.dart' as contracts_ui show ContractsScreen;

// عناصر الواجهة المشتركة
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/entity_audit_info_button.dart';

// ===== SnackBar throttle لتفادي تكرار التنبيهات =====
DateTime? _lastExceedSnackAtProps;
bool _exceedSnackQueuedProps = false;

void _showExceedSnackOnce(
    {BuildContext? ctx,
    required String msg,
    Duration dur = const Duration(seconds: 2)}) {
  final now = KsaTime.now();
  // تهدئة: لا تظهر أكثر من مرة كل 800ms
  if (_lastExceedSnackAtProps != null &&
      now.difference(_lastExceedSnackAtProps!).inMilliseconds < 800) {
    return;
  }
  _lastExceedSnackAtProps = now;

  // لا تحجز أكثر من callback واحد في نفس الوقت
  if (_exceedSnackQueuedProps) return;
  _exceedSnackQueuedProps = true;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final focusCtx = WidgetsBinding.instance.focusManager.primaryFocus?.context;
    final useCtx = ctx ?? focusCtx;
    if (useCtx != null) {
      final sm = ScaffoldMessenger.maybeOf(useCtx);
      if (sm != null && sm.mounted) {
        sm
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(msg, style: GoogleFonts.cairo()),
              behavior: SnackBarBehavior.floating,
              duration: dur,
            ),
          );
      }
    }
    _exceedSnackQueuedProps = false;
  });
}

// قصّ أي إدخال يتجاوز الحد ويُظهر تنبيه لحظي (مع تهدئة)
TextInputFormatter _limitWithFeedbackFormatter({
  required int max,
  required String exceedMsg,
  BuildContext? ctx, // اختياري
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    if (newV.text.characters.length <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV; // امنع التجاوز
  });
}

// حدّ أقصى لعدد صحيح مع تنبيه SnackBar (مع تهدئة)
TextInputFormatter _maxIntWithFeedback({
  required int max,
  required String exceedMsg,
  BuildContext? ctx,
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    final t = newV.text;
    if (t.isEmpty) return newV;
    final n = int.tryParse(t);
    if (n != null && n <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV;
  });
}

// حدّ أقصى لعدد عشري/عددي مع تنبيه SnackBar (مع تهدئة)
TextInputFormatter _maxNumWithFeedback({
  required num max,
  required String exceedMsg,
  BuildContext? ctx,
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    final t = newV.text;
    if (t.isEmpty) return newV;
    final n = num.tryParse(t);
    if (n != null && n <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV;
  });
}

class _PropertyDocSnapshot {
  final String? documentType;
  final String? documentNumber;
  final DateTime? documentDate;
  final List<String> attachmentPaths;

  const _PropertyDocSnapshot({
    required this.documentType,
    required this.documentNumber,
    required this.documentDate,
    required this.attachmentPaths,
  });
}

final Map<String, _PropertyDocSnapshot> _propertyDocCache =
    <String, _PropertyDocSnapshot>{};

const String kArchivedPropsBoxBase = 'archivedPropsBox';
String archivedBoxName() => boxName(kArchivedPropsBoxBase);

/// فتح صندوق الأرشفة (إن لم يكن مفتوحًا)
Future<Box<bool>> _openArchivedBox() async {
  if (!Hive.isBoxOpen(archivedBoxName())) {
    try {
      return await Hive.openBox<bool>(archivedBoxName());
    } catch (_) {}
  }
  return Hive.box<bool>(archivedBoxName());
}

/// قراءة حالة الأرشفة
bool _isArchivedProp(String propertyId) {
  try {
    final b = Hive.box<Property>(boxName(kPropertiesBox));
    for (final e in b.values) {
      if (e.id == propertyId) {
        return e.isArchived == true;
      }
    }
  } catch (_) {}
  return false;
}

/// ضبط حالة الأرشفة
Future<void> _setArchivedProp(String propertyId, bool archived) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));
  for (final e in b.values) {
    if (e.id == propertyId) {
      e.isArchived = archived;
      await b.put(e.id, e);
      break;
    }
  }
}

/// ضبط حالة الأرشفة لمجموعة معًا
Future<void> _setArchivedMany(Iterable<String> ids, bool archived) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));
  for (final e in b.values) {
    if (ids.contains(e.id)) {
      e.isArchived = archived;
      await b.put(e.id, e);
    }
  }
}

/// فكّ الأرشفة للعقار نفسه وللأب (إن كانت وحدة)
Future<void> _unarchiveSelfAndParent(Property p) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));

  // فك أرشفة العنصر نفسه
  if (p.isArchived == true) {
    p.isArchived = false;
    await b.put(p.id, p);
  }

  // فك أرشفة الأب (إن وُجد)
  final parentId = p.parentBuildingId;
  if (parentId != null) {
    for (final e in b.values) {
      if (e.id == parentId && e.isArchived == true) {
        e.isArchived = false;
        await b.put(e.id, e);
        break;
      }
    }
  }
}

/// دائرة ناعمة للخلفية
Widget _softCircle(double size, Color color) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// منطق المساعدة
bool _isBuilding(Property p) => p.type == PropertyType.building;
bool _isPerUnit(Property p) =>
    _isBuilding(p) && p.rentalMode == RentalMode.perUnit;
bool _isWholeBuilding(Property p) =>
    _isBuilding(p) && p.rentalMode == RentalMode.wholeBuilding;
bool _isUnit(Property p) => p.parentBuildingId != null;

/// يعيد عددًا صحيحًا موجبًا كحد أدنى
int _availableUnits(Property p) {
  final d = p.totalUnits - p.occupiedUnits;
  return d > 0 ? d : 0;
}

bool _isAvailable(Property p) {
  if (_isPerUnit(p)) return _availableUnits(p) > 0;
  return p.occupiedUnits == 0;
}

/// أيقونة النوع
IconData _iconOf(PropertyType type) {
  switch (type) {
    case PropertyType.apartment:
      return Icons.apartment_rounded;
    case PropertyType.villa:
      return Icons.house_rounded;
    case PropertyType.building:
      return Icons.business_rounded;
    case PropertyType.land:
      return Icons.terrain_rounded;
    case PropertyType.office:
      return Icons.domain_rounded;
    case PropertyType.shop:
      return Icons.storefront_rounded;
    case PropertyType.warehouse:
      return Icons.warehouse_rounded;
  }
}

// يستخرج الرقم في آخر الاسم (يدعم "شقة 3" و"شقة3").
// إذا لم يوجد رقم، يُعيد -1 ليأتي بعد المرقّمات.
int _extractTrailingNumber(String name) {
  final noSpaces = name.replaceAll(' ', '');
  final m = RegExp(r'(\d+)$').firstMatch(noSpaces);
  return m == null ? -1 : int.tryParse(m.group(1)!) ?? -1;
}

/// محاولة آمنة لمعرفة هل هناك عقد نشط مرتبط بـ propertyId
bool _hasActiveContractForPropertyId(String propertyId) {
  final cname = HiveService.contractsBoxName(); // قد يكون alias+scoped
  if (!Hive.isBoxOpen(cname)) return false;
  dynamic box;
  try {
    box = Hive.box(cname);
  } catch (_) {
    return false;
  }
  try {
    final now = KsaTime.now();
    for (final e in (box as Box).values) {
      if (e is Map) {
        final pid = e['propertyId'];
        final isActive = e['isActive'];
        final terminated = e['isTerminated'] == true;
        DateTime? start, end;
        try {
          start = e['startDate'] as DateTime?;
        } catch (_) {}
        try {
          end = e['endDate'] as DateTime?;
        } catch (_) {}
        if (pid == propertyId) {
          if (isActive == true && !terminated) return true;
          if (start != null && end != null && !terminated) {
            final sd = DateTime(start.year, start.month, start.day);
            final ed = DateTime(end.year, end.month, end.day);
            final today = DateTime(now.year, now.month, now.day);
            final active = !today.isBefore(sd) && !today.isAfter(ed);
            if (active) return true;
          }
        }
      } else {
        try {
          final c = e as dynamic;
          final pid = c.propertyId as String?;
          final start = c.startDate as DateTime?;
          final end = c.endDate as DateTime?;
          final terminated = (c.isTerminated as bool?) ?? false;
          if (pid == propertyId &&
              start != null &&
              end != null &&
              !terminated) {
            final sd = DateTime(start.year, start.month, start.day);
            final ed = DateTime(end.year, end.month, end.day);
            final today = DateTime(now.year, now.month, now.day);
            final active = !today.isBefore(sd) && !today.isAfter(ed);
            if (active) return true;
          }
        } catch (_) {}
      }
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// هل مرتبط بعقد؟
/// - الوحدة/العقار العادي: فحص مباشر.
/// - العمارة: أي عقد على العمارة نفسها أو على أي وحدة تابعة يعتبر ارتباطًا نشطًا.
bool _hasActiveContract(Property p) {
  if (_hasActiveContractForPropertyId(p.id)) return true;
  if (!_isPerUnit(p) && p.occupiedUnits > 0) return true;

  if (_isBuilding(p)) {
    final box = Hive.box<Property>(boxName(kPropertiesBox));
    for (final u in box.values.where((e) => e.parentBuildingId == p.id)) {
      if (_hasActiveContractForPropertyId(u.id) || u.occupiedUnits > 0) {
        return true;
      }
    }
  }
  return false;
}

/// استخراج مواصفات [[SPEC]] من الوصف (بدون تعديل الموديل)
Map<String, String> _parseSpec(String? desc) {
  if (desc == null || desc.isEmpty) return {};
  final start = desc.indexOf('[[SPEC]]');
  final end = desc.indexOf('[[/SPEC]]');
  if (start == -1 || end == -1 || end <= start) return {};
  final body = desc.substring(start + 8, end).trim();
  final map = <String, String>{};
  for (final line in body.split('\n')) {
    final parts = line.split(':');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      final value = parts.sublist(1).join(':').trim();
      if (key.isNotEmpty && value.isNotEmpty) map[key] = value;
    }
  }
  return map;
}

/// استخراج الوصف الحر (بعد كتلة SPEC)
String _extractFreeDesc(String? desc) {
  final d = (desc ?? '').trim();
  if (d.isEmpty) return '';
  final start = d.indexOf('[[SPEC]]');
  final end = d.indexOf('[[/SPEC]]');
  if (start != -1 && end != -1 && end > start) {
    final after = d.substring(end + 9).trim();
    return after;
  }
  return d;
}

bool? _parseFurnishedSpecValue(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.contains('غير')) return false;
  if (normalized.contains('مفروش')) return true;
  return null;
}

/// دمج مواصفات [[SPEC]] مع وصف حر
String _buildSpec({
  int? baths,
  int? halls,
  int? floorNo,
  bool? furnished,
  String? extraDesc,
}) {
  final b = StringBuffer();
  b.writeln('[[SPEC]]');
  if (baths != null) b.writeln('حمامات: $baths');
  if (halls != null) b.writeln('صالات: $halls');
  if (floorNo != null) b.writeln('الدور: $floorNo');
  if (furnished != null) {
    b.writeln('المفروشات: ${furnished ? "مفروشة" : "غير مفروشة"}');
  }
  b.writeln('[[/SPEC]]');
  if ((extraDesc ?? '').trim().isNotEmpty) {
    b.writeln(extraDesc!.trim());
  }
  return b.toString().trim();
}

/// لعرض حتى 50 حرف في النصوص (الاسم)
String _limitChars(String text, int max) =>
    (text.length <= max) ? text : '${text.substring(0, max)}…';

/// فلاتر خارجيّة (مستوى الملف)
enum AvailabilityFilter { all, availableOnly, occupiedOnly }

enum _RentalModeFilter { all, whole, perUnit, nonBuilding }

String _archiveBlockedMessageForProperty(Property p) {
  if (_isPerUnit(p)) {
    return 'هذه العمارة تحتوي على وحدة أو أكثر مرتبطة بعقد نشط، لذلك لا يمكن أرشفتها الآن.\n'
        'يجب أولًا إنهاء العقود المرتبطة بهذه الوحدات، ثم يمكنك أرشفة العمارة.';
  }
  return 'العقار مرتبط بعقد نشط، لذلك لا يمكن أرشفته الآن.\n'
      'يجب أولًا إنهاء العقد، ثم يمكنك أرشفة العقار.';
}

/// ============================================================================
/// أدوات مشتركة للأرشفة (تفعيل/تعطيل + تتبّع للوحدات إن كانت عمارة)
/// ============================================================================
Future<void> _toggleArchiveForProperty(BuildContext context, Property p) async {
  // منع الأرشفة في حال وجود عقد نشط (يشمل عقود الوحدات عند كون p عمارة)
  if (_hasActiveContract(p)) {
    await CustomConfirmDialog.show(
      context: context,
      title: 'لا يمكن الأرشفة',
      message: _archiveBlockedMessageForProperty(p),
      confirmLabel: 'حسنًا',
      showCancel: false,
    );
    return;
  }

  // 1) احسب القيمة الجديدة وحدّث الكائن
  final newVal = !(p.isArchived == true);
  p.isArchived = newVal;

  // 2) خزّن في Hive بمفتاح = id (مهم جدًّا لتجنّب الارتداد/الدبل)
  final box = Hive.box<Property>(boxName(kPropertiesBox));
  await box.put(p.id, p); // لا تستخدم add

  // 3) ادفع المزامنة (إن وجدت خدمة/ريبو)
  unawaited(OfflineSyncService.instance.enqueueUpsertProperty(p));
  // أو: unawaited(propertiesRepo.saveProperty(p));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newVal ? 'تم الأرشفة' : 'تم فك الأرشفة',
            style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// إزالة الحالة من صندوق الأرشفة (مع تتبّع للوحدات عند الحاجة)
Future<void> _clearArchiveState(Property p) async {
  try {
    final ab = await _openArchivedBox();
    // احذف حالة الأرشفة للعقار فقط — لا تلمس الوحدات إطلاقًا
    await ab.delete(p.id);
  } catch (_) {}
}

Future<void> deletePropertyById(String id) async {
  final box = Hive.box<Property>(boxName(kPropertiesBox));
  dynamic keyToDelete;
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Property && v.id == id) {
      keyToDelete = k;
      break;
    }
  }
  if (keyToDelete != null) {
    await box.delete(keyToDelete);
  }
}

class _PropertyHardDeletePlan {
  _PropertyHardDeletePlan({
    required this.rootPropertyId,
    required this.properties,
    required this.contracts,
    required this.contractInvoices,
    required this.maintenanceRequests,
    required this.maintenanceInvoices,
    required this.affectedTenantIds,
    required this.affectedParentBuildingIds,
  });

  final String rootPropertyId;
  final List<Property> properties;
  final List<Contract> contracts;
  final List<Invoice> contractInvoices;
  final List<MaintenanceRequest> maintenanceRequests;
  final List<Invoice> maintenanceInvoices;
  final Set<String> affectedTenantIds;
  final Set<String> affectedParentBuildingIds;

  Set<String> get propertyIds => properties.map((e) => e.id).toSet();

  bool get hasChildUnits =>
      properties.any((e) => e.parentBuildingId == rootPropertyId);

  List<Invoice> get allInvoices {
    final byId = <String, Invoice>{};
    for (final invoice in contractInvoices) {
      byId[invoice.id] = invoice;
    }
    for (final invoice in maintenanceInvoices) {
      byId[invoice.id] = invoice;
    }
    return byId.values.toList(growable: false);
  }
}

Property _livePropertyById(String id) {
  final box = Hive.box<Property>(boxName(kPropertiesBox));
  for (final property in box.values) {
    if (property.id == id) return property;
  }
  throw StateError('Property not found: $id');
}

_PropertyHardDeletePlan _buildPropertyHardDeletePlan(Property property) {
  final propertiesBox = Hive.box<Property>(boxName(kPropertiesBox));
  final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
  final invoicesBox = Hive.box<Invoice>(boxName(kInvoicesBox));
  final maintenanceBox =
      Hive.box<MaintenanceRequest>(boxName(kMaintenanceBox));

  Property root = property;
  for (final candidate in propertiesBox.values) {
    if (candidate.id == property.id) {
      root = candidate;
      break;
    }
  }

  final targetProperties = <Property>[root];
  for (final child in propertiesBox.values) {
    if (child.parentBuildingId == root.id) {
      targetProperties.add(child);
    }
  }

  final propertyIds = targetProperties.map((e) => e.id).toSet();
  final affectedParentBuildingIds = <String>{};
  for (final target in targetProperties) {
    final parentId = (target.parentBuildingId ?? '').trim();
    if (parentId.isNotEmpty && !propertyIds.contains(parentId)) {
      affectedParentBuildingIds.add(parentId);
    }
  }

  final targetContracts = <Contract>[];
  final contractIds = <String>{};
  final affectedTenantIds = <String>{};
  for (final contract in contractsBox.values) {
    if (!propertyIds.contains(contract.propertyId)) continue;
    targetContracts.add(contract);
    contractIds.add(contract.id);
    final tenantId = contract.tenantId.trim();
    if (tenantId.isNotEmpty) {
      affectedTenantIds.add(tenantId);
    }
  }

  final targetRequests = <MaintenanceRequest>[];
  final requestIds = <String>{};
  for (final request in maintenanceBox.values) {
    if (!propertyIds.contains(request.propertyId)) continue;
    targetRequests.add(request);
    requestIds.add(request.id);
  }

  final contractInvoicesById = <String, Invoice>{};
  final maintenanceInvoicesById = <String, Invoice>{};
  for (final invoice in invoicesBox.values) {
    final contractId = invoice.contractId.trim();
    final requestId = (invoice.maintenanceRequestId ?? '').trim();
    final isManualInvoice =
        (invoice.note ?? '').toLowerCase().contains('[manual]');
    final contractMatch =
        contractId.isNotEmpty && contractIds.contains(contractId);
    final requestMatch = requestId.isNotEmpty && requestIds.contains(requestId);
    final propertyMatch = propertyIds.contains(invoice.propertyId);

    if (requestMatch) {
      maintenanceInvoicesById[invoice.id] = invoice;
      continue;
    }
    if (contractMatch) {
      contractInvoicesById[invoice.id] = invoice;
      continue;
    }
    if (propertyMatch && !isManualInvoice) {
      maintenanceInvoicesById[invoice.id] = invoice;
    }
  }

  return _PropertyHardDeletePlan(
    rootPropertyId: root.id,
    properties: targetProperties,
    contracts: targetContracts,
    contractInvoices: contractInvoicesById.values.toList(growable: false),
    maintenanceRequests: targetRequests,
    maintenanceInvoices: maintenanceInvoicesById.values.toList(growable: false),
    affectedTenantIds: affectedTenantIds,
    affectedParentBuildingIds: affectedParentBuildingIds,
  );
}

Future<void> _deleteEntityById<T>(
  Box<T> box,
  String id,
  String Function(T value) idOf,
) async {
  dynamic keyToDelete;
  for (final key in box.keys) {
    final value = box.get(key);
    if (value == null) continue;
    if (idOf(value) == id) {
      keyToDelete = key;
      break;
    }
  }
  if (keyToDelete != null) {
    await box.delete(keyToDelete);
  }
}

Future<void> _clearArchiveStatesByIds(Iterable<String> propertyIds) async {
  try {
    final archived = await _openArchivedBox();
    for (final id in propertyIds) {
      await archived.delete(id);
    }
  } catch (_) {}
}

Future<void> _clearServiceConfigsForProperties(Set<String> propertyIds) async {
  if (propertyIds.isEmpty) return;
  try {
    final boxId = boxName('servicesConfig');
    final box = Hive.isBoxOpen(boxId)
        ? Hive.box<Map>(boxId)
        : await Hive.openBox<Map>(boxId);
    final keys = box.keys
        .map((e) => e.toString())
        .where((key) => propertyIds.contains(key.split('::').first.trim()))
        .toList(growable: false);
    for (final key in keys) {
      await box.delete(key);
    }
  } catch (_) {}
}

Future<void> _recomputeTenantActiveContracts(Set<String> tenantIds) async {
  if (tenantIds.isEmpty) return;
  final tenantsBox = Hive.box<Tenant>(boxName(kTenantsBox));
  final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
  for (final tenantId in tenantIds) {
    Tenant? tenant;
    for (final candidate in tenantsBox.values) {
      if (candidate.id == tenantId) {
        tenant = candidate;
        break;
      }
    }
    if (tenant == null) continue;
    var activeCount = 0;
    for (final contract in contractsBox.values) {
      if (contract.tenantId == tenantId && contract.isActiveNow) {
        activeCount += 1;
      }
    }
    tenant.activeContractsCount = activeCount;
    tenant.updatedAt = KsaTime.now();
    await tenantsBox.put(tenant.id, tenant);
  }
}

Future<void> _recomputeBuildingUnitStats(Set<String> buildingIds) async {
  if (buildingIds.isEmpty) return;
  final propertiesBox = Hive.box<Property>(boxName(kPropertiesBox));
  for (final buildingId in buildingIds) {
    Property? building;
    for (final candidate in propertiesBox.values) {
      if (candidate.id == buildingId) {
        building = candidate;
        break;
      }
    }
    if (building == null) continue;
    final units = <Property>[];
    for (final property in propertiesBox.values) {
      if (property.parentBuildingId == buildingId) {
        units.add(property);
      }
    }
    // إجمالي الوحدات هو السعة الثابتة للعمارة كما حُددت عند إنشائها،
    // ولا يجب أن ينخفض عند حذف وحدة؛ الذي يُعاد حسابه هنا هو الإشغال فقط.
    final occupiedCount = units.where((u) => u.occupiedUnits > 0).length;
    final safeTotalUnits = building.totalUnits < 0 ? 0 : building.totalUnits;
    building.occupiedUnits = occupiedCount.clamp(0, safeTotalUnits);
    building.updatedAt = KsaTime.now();
    await propertiesBox.put(building.id, building);
  }
}

Widget _hardDeleteNoticeLine(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.circle,
            size: 8,
            color: Color(0xFFB91C1C),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.cairo(
              color: const Color(0xFF334155),
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<bool> _showPropertyHardDeleteDialog(
  BuildContext context,
  Property property,
  _PropertyHardDeletePlan plan,
) async {
  var agreed = false;
  Future<void> requireConsentWarning(BuildContext dialogInnerContext) async {
    await showDialog<void>(
      context: dialogInnerContext,
      barrierColor: Colors.black54,
      builder: (warningContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x26FFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تأكيد مطلوب',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قبل الحذف النهائي، يجب الإقرار بالموافقة على الحذف عبر تفعيل مربع التأكيد.',
                  style: GoogleFonts.cairo(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(warningContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B6B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('حسنًا'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) {
                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x26FFFFFF)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0x26FF4D4D),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0x40FF4D4D)),
                              ),
                              child: const Icon(
                                Icons.delete_forever_rounded,
                                color: Color(0xFFFF6B6B),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'حذف العقار',
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            property.parentBuildingId != null
                                ? 'سيؤدي حذف العقار "${property.name}" نهائيًا إلى حذف كل ما يرتبط به، ولن تظهر العقود والسندات والخدمات المرتبطة به في التقارير بعد ذلك. إذا كنت تريد الاحتفاظ بالسجلات المرتبطة بهذا العقار، فلا تقم بحذف العقار حذفًا نهائيًا.'
                                : 'سيؤدي حذف العقار "${property.name}" نهائيًا إلى حذف كل ما يرتبط به، ولن تظهر العقود والسندات والخدمات المرتبطة به في التقارير بعد ذلك. إذا كنت لا تريد تأجير هذا العقار مع الاحتفاظ بالسجلات، فاستخدم أرشفة العقار بدل الحذف النهائي.',
                            style: GoogleFonts.cairo(
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0x14FF4D4D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x26FF4D4D)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFFFA726),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'هذا الإجراء دائم وسيؤدي إلى فقدان كل السجلات المرتبطة بهذا العقار.',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '• سوف يتم حذف جميع العقود المرتبطة بهذا العقار حتى لو كانت نشطة.',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        height: 1.6,
                                      ),
                                    ),
                                    Text(
                                      '• سوف يتم حذف جميع السندات المتعلقة بالعقود المرتبطة بهذا العقار.',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        height: 1.6,
                                      ),
                                    ),
                                    Text(
                                      '• سوف يتم حذف جميع طلبات الخدمات المتعلقة بهذا العقار.',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        height: 1.6,
                                      ),
                                    ),
                                    Text(
                                      '• سوف يتم حذف جميع سندات طلبات الخدمات المتعلقة بهذا العقار.',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        height: 1.6,
                                      ),
                                    ),
                                    if (plan.hasChildUnits)
                                      Text(
                                        '• وبما أن هذا العقار عمارة ذات وحدات، فسوف يتم أيضًا حذف جميع الوحدات التابعة لها مع عقودها وسنداتها وخدماتها وكل ما يرتبط بها.',
                                        style: GoogleFonts.cairo(
                                          color: Colors.white70,
                                          height: 1.6,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: agreed,
                          onChanged: (value) =>
                              setState(() => agreed = value ?? false),
                          activeColor: const Color(0xFFFF6B6B),
                          checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'نعم، أفهم العواقب وأرغب في حذف هذا العقار نهائيًا.',
                            style: GoogleFonts.cairo(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  if (!agreed) {
                                    await requireConsentWarning(context);
                                    return;
                                  }
                                  Navigator.pop(dialogContext, true);
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('حذف نهائي'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7F1D1D),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'رجوع',
                                  style: GoogleFonts.cairo(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ) ??
      false;

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) {
                return Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 8,
                  backgroundColor: Colors.white,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0xFFFECACA),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              'تنبيه',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                color: const Color(0xFFB91C1C),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  property.parentBuildingId != null
                                      ? 'سيؤدي حذف العقار "${property.name}" إلى حذف كل ما يرتبط به نهائيًا، لذلك لن تظهر العقود والسندات والخدمات المرتبطة به في التقارير بعد ذلك.\n\nإذا كنت تريد الاحتفاظ بالسجلات المرتبطة بهذا العقار، فلا تقم بحذف العقار حذفًا نهائيًا.'
                                      : 'سيؤدي حذف العقار "${property.name}" إلى حذف كل ما يرتبط به نهائيًا، لذلك لن تظهر العقود والسندات والخدمات المرتبطة به في التقارير بعد ذلك.\n\nإذا كنت لا تريد تأجير هذا العقار مع الاحتفاظ بالسجلات، فاستخدم أرشفة العقار بدل الحذف النهائي.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    color: const Color(0xFF475569),
                                    fontSize: 15,
                                    height: 1.7,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _hardDeleteNoticeLine(
                                        'سوف يتم حذف جميع العقود المرتبطة بهذا العقار حتى لو كانت نشطة.',
                                      ),
                                      _hardDeleteNoticeLine(
                                        'سوف يتم حذف جميع السندات المتعلقة بالعقود المرتبطة بهذا العقار.',
                                      ),
                                      _hardDeleteNoticeLine(
                                        'سوف يتم حذف جميع طلبات الخدمات المتعلقة بهذا العقار.',
                                      ),
                                      _hardDeleteNoticeLine(
                                        'سوف يتم حذف جميع سندات طلبات الخدمات المتعلقة بهذا العقار.',
                                      ),
                                      if (plan.hasChildUnits)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 0),
                                          child: _hardDeleteNoticeLine(
                                            'وبما أن هذا العقار عمارة ذات وحدات، فسوف يتم أيضًا حذف جميع الوحدات التابعة لها مع عقودها وسنداتها وخدماتها وكل ما يرتبط بها.',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                InkWell(
                                  onTap: () {
                                    setState(() => agreed = !agreed);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: agreed
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: agreed,
                                          activeColor:
                                              const Color(0xFFDC2626),
                                          onChanged: (value) {
                                            setState(() =>
                                                agreed = value ?? false);
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'أؤكد أنني أريد حذف هذا العقار وكل ما يرتبط به حذفًا نهائيًا.',
                                            style: GoogleFonts.cairo(
                                              color: const Color(0xFF334155),
                                              fontSize: 14,
                                              height: 1.6,
                                              fontWeight: FontWeight.w800,
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: agreed
                                        ? () =>
                                            Navigator.pop(dialogContext, true)
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFDC2626),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          const Color(0xFFFCA5A5),
                                      disabledForegroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      'حذف نهائي',
                                      style: GoogleFonts.cairo(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    style: TextButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFF1F5F9),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'تراجع',
                                      style: GoogleFonts.cairo(
                                        color: const Color(0xFF475569),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ) ??
      false;
}

Future<void> _deletePropertyWithRelations(
  Property property,
  _PropertyHardDeletePlan plan,
) async {
  final propertiesBox = Hive.box<Property>(boxName(kPropertiesBox));
  final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
  final invoicesBox = Hive.box<Invoice>(boxName(kInvoicesBox));
  final maintenanceBox =
      Hive.box<MaintenanceRequest>(boxName(kMaintenanceBox));

  final invoiceIds = plan.allInvoices.map((e) => e.id).toSet();
  for (final invoiceId in invoiceIds) {
    await _deleteEntityById<Invoice>(
      invoicesBox,
      invoiceId,
      (value) => value.id,
    );
  }

  for (final request in plan.maintenanceRequests) {
    await _deleteEntityById<MaintenanceRequest>(
      maintenanceBox,
      request.id,
      (value) => value.id,
    );
  }

  for (final contract in plan.contracts) {
    await _deleteEntityById<Contract>(
      contractsBox,
      contract.id,
      (value) => value.id,
    );
  }

  final propertyIds = plan.propertyIds;
  final orderedProperties = [...plan.properties]
    ..sort((a, b) {
      if (a.id == plan.rootPropertyId) return 1;
      if (b.id == plan.rootPropertyId) return -1;
      return 0;
    });
  for (final target in orderedProperties) {
    await _deleteEntityById<Property>(
      propertiesBox,
      target.id,
      (value) => value.id,
    );
    unawaited(OfflineSyncService.instance.enqueueDeleteProperty(target.id));
  }

  await _clearArchiveStatesByIds(propertyIds);
  await _clearServiceConfigsForProperties(propertyIds);
  await _recomputeTenantActiveContracts(plan.affectedTenantIds);
  await _recomputeBuildingUnitStats(plan.affectedParentBuildingIds);
}

Future<bool> _runPropertyHardDeleteFlow(
  BuildContext context,
  Property property,
) async {
  final liveProperty = _livePropertyById(property.id);
  final plan = _buildPropertyHardDeletePlan(liveProperty);
  final confirmed =
      await _showPropertyHardDeleteDialog(context, liveProperty, plan);
  if (!confirmed) return false;
  await _deletePropertyWithRelations(liveProperty, plan);
  return true;
}

/// ============================================================================
/// شاشة قائمة العقارات
/// ============================================================================
class PropertiesScreen extends StatefulWidget {
  final PropertyType? initialType;
  final AvailabilityFilter? initialAvailability;
  final bool initialShowArchived;
  const PropertiesScreen(
      {super.key,
      this.initialType,
      this.initialAvailability,
      this.initialShowArchived = false});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  Box<Property> get _box => Hive.box<Property>(boxName(kPropertiesBox));

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  bool _handledOpen = false;

  // بحث + تصفية + أرشيف
  String _q = '';
  bool _showArchived = false;
  AvailabilityFilter _availability = AvailabilityFilter.all;
  PropertyType? _typeFilter;
  _RentalModeFilter _rentalModeFilter = _RentalModeFilter.all;

  @override
  void initState() {
    super.initState();
    // ✅ تطبيق الفلاتر القادمة من الخارج (مثل التقارير)
    if (widget.initialType != null) _typeFilter = widget.initialType;
    if (widget.initialAvailability != null) {
      _availability = widget.initialAvailability!;
    }
    if (widget.initialShowArchived) {
      _showArchived = true;
    }

    // افتح صندوق الأرشفة مبكرًا
    () async {
      await HiveService
          .ensureReportsBoxesOpen(); // يفتح صناديق هذا المستخدم + يحلّ aliases
      await _openArchivedBox();
      if (mounted) setState(() {});
    }();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }

      // ✅ فتح عقار معيّن عند الوصول من شاشة العقد
      if (_handledOpen) return;
      _handledOpen = true;

      final args = ModalRoute.of(context)?.settings.arguments;
      final String? openId =
          (args is Map) ? args['openPropertyId'] as String? : null;
      if (openId != null) _openPropertyDetailsById(openId);
    });
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        break;
      case 2:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        AvailabilityFilter av = _availability;
        PropertyType? tp = _typeFilter;
        _RentalModeFilter rm = _rentalModeFilter;
        bool arch = _showArchived; // ← خيار الأرشفة داخل الفلتر

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

                  DropdownButtonFormField<AvailabilityFilter>(
                    initialValue: av,
                    decoration: _dd('التوفّر'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    items: const [
                      DropdownMenuItem(
                          value: AvailabilityFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: AvailabilityFilter.availableOnly,
                          child: Text('المتاحة فقط')),
                      DropdownMenuItem(
                          value: AvailabilityFilter.occupiedOnly,
                          child: Text('المشغولة فقط')),
                    ],
                    onChanged: (v) => setM(() => av = v ?? av),
                  ),
                  SizedBox(height: 10.h),

                  DropdownButtonFormField<PropertyType?>(
                    initialValue: tp,
                    decoration: _dd('نوع العقار'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    items: <PropertyType?>[null, ...PropertyType.values]
                        .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t == null ? 'الكل' : t.label)))
                        .toList(),
                    onChanged: (v) => setM(() {
                      tp = v;
                      if (tp != PropertyType.building) {
                        rm = _RentalModeFilter
                            .all; // صفّر نمط التأجير إذا لم تكن "عمارة"
                      }
                    }),
                  ),

                  if (tp == PropertyType.building) ...[
                    SizedBox(height: 10.h),
                    DropdownButtonFormField<_RentalModeFilter>(
                      initialValue: rm,
                      decoration: _dd('نمط التأجير'),
                      dropdownColor: const Color(0xFF0F172A),
                      iconEnabledColor: Colors.white70,
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w700),
                      items: const [
                        DropdownMenuItem(
                            value: _RentalModeFilter.all, child: Text('الكل')),
                        DropdownMenuItem(
                            value: _RentalModeFilter.whole,
                            child: Text('تأجير كامل')),
                        DropdownMenuItem(
                            value: _RentalModeFilter.perUnit,
                            child: Text('تأجير وحدات')),
                        DropdownMenuItem(
                            value: _RentalModeFilter.nonBuilding,
                            child: Text('غير عمارة')),
                      ],
                      onChanged: (v) => setM(() => rm = v ?? rm),
                    ),
                  ],

                  // —— الأرشفة: خياران يمين/يسار (الكل / الأرشفة)
                  SizedBox(height: 14.h),
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
                          label: Text('غير مؤرشفة', style: GoogleFonts.cairo()),
                          selected: !arch,
                          onSelected: (_) => setM(() => arch = false),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('مؤرشفة', style: GoogleFonts.cairo()),
                          selected: arch,
                          onSelected: (_) => setM(() => arch = true),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          onPressed: () {
                            setState(() {
                              _availability = av;
                              _typeFilter = tp;
                              _rentalModeFilter = rm;
                              _showArchived = arch; // ← تطبيق الأرشفة
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
                              _availability = AvailabilityFilter.all;
                              _typeFilter = null;
                              _rentalModeFilter = _RentalModeFilter.all;
                              _showArchived =
                                  false; // ← رجوع للوضع الافتراضي (الكل)
                            });
                            Navigator.pop(context);
                          },
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(color: Colors.white)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openPropertyDetailsById(String id) {
    final box = _box; // Hive.box<Property>('propertiesBox');
    Property? p;
    try {
      p = box.values.firstWhere((e) => e.id == id);
    } catch (_) {}

    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('العقار غير موجود', style: GoogleFonts.cairo())),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PropertyDetailsScreen(item: _box.get(p!.id) ?? p)),
    );
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    return await CustomConfirmDialog.show(
      context: context,
      title: title,
      message: msg,
      cancelLabel: 'إلغاء',
    );
  }

  // —— هل هناك فلاتر نشطة؟
  bool get _hasActiveFilters =>
      _showArchived ||
      _availability != AvailabilityFilter.all ||
      _typeFilter != null ||
      _rentalModeFilter != _RentalModeFilter.all;

  // —— نص موجز للفلتر الحالي
  String _currentFilterLabel() {
    final parts = <String>[];
    parts.add(_showArchived ? 'المؤرشفة' : 'الكل');

    switch (_availability) {
      case AvailabilityFilter.availableOnly:
        parts.add('المتاحة فقط');
        break;
      case AvailabilityFilter.occupiedOnly:
        parts.add('المشغولة فقط');
        break;
      case AvailabilityFilter.all:
        break;
    }

    if (_typeFilter != null) {
      parts.add(_typeFilter!.label);
    }

    switch (_rentalModeFilter) {
      case _RentalModeFilter.whole:
        parts.add('تأجير كامل');
        break;
      case _RentalModeFilter.perUnit:
        parts.add('تأجير وحدات');
        break;
      case _RentalModeFilter.nonBuilding:
        parts.add('غير عمارة');
        break;
      case _RentalModeFilter.all:
        break;
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text('العقارات',
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
            // خلفية
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6)
                  ],
                ),
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
                // شريط البحث
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم/العنوان',
                      hintStyle: GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
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
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ),

                // وسم الفلاتر
                if (_hasActiveFilters)
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
                            Text(_currentFilterLabel(),
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // قائمة العقارات
                Expanded(
                  child: AnimatedBuilder(
                    animation: Hive.isBoxOpen(archivedBoxName())
                        ? Hive.box<bool>(archivedBoxName()).listenable()
                        : ValueNotifier(0),
                    builder: (_, __) {
                      return ValueListenableBuilder(
                        valueListenable: _box.listenable(),
                        builder: (context, box, _) {
                          final b = box;

// أظهر الوحدات فقط إذا كان هناك فلاتر مفعّلة، وعند "نوع العقار: الكل" أو "شقة"
                          var items = b.values.where((p) {
                            if (p.parentBuildingId == null) {
                              return true; // العقارات/العمائر تظهر دائمًا
                            }
                            final showUnits = _hasActiveFilters &&
                                ((_typeFilter == null) ||
                                    (_typeFilter == PropertyType.apartment));
                            return showUnits;
                          }).toList();
// إزالة التكرار حسب id قبل الفرز/العرض
                          final byId = <String, Property>{};
                          for (final p in items) {
                            byId[p.id] = p; // آخر قيمة تفوز
                          }
                          items = byId.values.toList();

                          // ✅ أمان إضافي: أي عقار مؤرشف وعليه عقد نشط (هو أو أي وحدة) نفك أرشفته تلقائيًا
                          for (final top in items
                              .where((e) => e.parentBuildingId == null)) {
                            if (_isArchivedProp(top.id) &&
                                _hasActiveContract(top)) {
                              _setArchivedProp(top.id, false);
                            }
                          }

                          // أرشيف (باستخدام صندوق منفصل)
                          items = items
                              .where((p) =>
                                  (p.isArchived == true) == _showArchived)
                              .toList();

                          // فلاتر
                          if (_typeFilter != null) {
                            items = items
                                .where((p) => p.type == _typeFilter)
                                .toList();
                          }
                          switch (_rentalModeFilter) {
                            case _RentalModeFilter.whole:
                              items = items
                                  .where((p) => _isWholeBuilding(p))
                                  .toList();
                              break;
                            case _RentalModeFilter.perUnit:
                              items =
                                  items.where((p) => _isPerUnit(p)).toList();
                              break;
                            case _RentalModeFilter.nonBuilding:
                              items =
                                  items.where((p) => !_isBuilding(p)).toList();
                              break;
                            case _RentalModeFilter.all:
                              break;
                          }
                          switch (_availability) {
                            case AvailabilityFilter.availableOnly:
                              items =
                                  items.where((p) => _isAvailable(p)).toList();
                              break;
                            case AvailabilityFilter.occupiedOnly:
                              items =
                                  items.where((p) => !_isAvailable(p)).toList();
                              break;
                            case AvailabilityFilter.all:
                              break;
                          }

                          // بحث
                          if (_q.isNotEmpty) {
                            final q = _q.toLowerCase();
                            items = items
                                .where((p) =>
                                    p.name.toLowerCase().contains(q) ||
                                    p.address.toLowerCase().contains(q))
                                .toList();
                          }

                          // الأحدث أولاً اعتمادًا على أن id رقم زمني (microsecondsSinceEpoch) محفوظ كسلسلة
                          items.sort((a, c) {
                            final ai = int.tryParse(a.id) ?? 0;
                            final ci = int.tryParse(c.id) ?? 0;
                            return ci.compareTo(ai);
                          });

                          if (items.isEmpty) {
                            return Center(
                              child: Text(
                                  _showArchived
                                      ? 'لا توجد عقارات مؤرشفة'
                                      : 'لا توجد عقارات بعد',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700)),
                            );
                          }

                          return ListView.separated(
                            padding:
                                EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => SizedBox(height: 12.h),
                            itemBuilder: (context, i) {
                              final p = items[i];

                              return InkWell(
                                borderRadius: BorderRadius.circular(16.r),
                                // الضغط المطوّل: أرشفة/فك الأرشفة مباشرة (مع منع الأرشفة إذا هناك عقد نشط)
                                // الضغط المطوّل: أرشفة/فك الأرشفة مباشرة (مع منع الأرشفة إذا هناك عقد نشط)
                                onLongPress: () async {
                                  // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
                                  if (await OfficeClientGuard
                                      .blockIfOfficeClient(context)) {
                                    return;
                                  }

                                  if (_hasActiveContract(p)) {
                                    await CustomConfirmDialog.show(
                                      context: context,
                                      title: 'لا يمكن الأرشفة',
                                      message:
                                          _archiveBlockedMessageForProperty(p),
                                      confirmLabel: 'حسنًا',
                                      showCancel: false,
                                    );
                                    return;
                                  }

                                  await _toggleArchiveForProperty(context, p);
                                  if (mounted) setState(() {});
                                },

                                // الضغط العادي: فتح التفاصيل
                                onTap: () async {
                                  final box = Hive.box<Property>(
                                      boxName(kPropertiesBox));
                                  final latest = box.get(p.id) ?? p;
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => PropertyDetailsScreen(
                                            item: latest)),
                                  );
                                },
                                child: _DarkCard(
                                  padding: EdgeInsets.all(12.w),
                                  child: Stack(
                                    children: [
                                      ConstrainedBox(
                                        constraints:
                                            BoxConstraints(minHeight: 118.h),
                                        child: Row(
                                          children: [
                                            // أيقونة حسب النوع
                                            Container(
                                              width: 56.w,
                                              height: 56.w,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12.r),
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF0F766E),
                                                    Color(0xFF14B8A6)
                                                  ],
                                                  begin: Alignment.topRight,
                                                  end: Alignment.bottomLeft,
                                                ),
                                              ),
                                              child: Icon(_iconOf(p.type),
                                                  color: Colors.white),
                                            ),
                                            SizedBox(width: 12.w),

                                            Expanded(
                                              child: Padding(
                                                padding: EdgeInsets.only(
                                                    left: 128.w),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _limitChars(
                                                                p.name, 50),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: GoogleFonts
                                                                .cairo(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 16.sp,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 4.h),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .location_on_outlined,
                                                            size: 16.sp,
                                                            color:
                                                                Colors.white70),
                                                        SizedBox(width: 4.w),
                                                        Expanded(
                                                          child: Text(
                                                            p.address,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: GoogleFonts
                                                                .cairo(
                                                              color: Colors
                                                                  .white70,
                                                              fontSize: 12.sp,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 8.h),

                                                    // معلومات عدد الوحدات:
                                                    // معلومات عدد الوحدات:
                                                    if (_isBuilding(p) &&
                                                        p.totalUnits > 0) ...[
                                                      Wrap(
                                                        spacing: 6.w,
                                                        runSpacing: 6.h,
                                                        children: [
                                                          _chip(
                                                              'عدد الوحدات: ${p.totalUnits}',
                                                              bg: const Color(
                                                                  0xFF1F2937)),

                                                          // نحافظ على ارتفاع موحّد للبطاقة باستخدام Visibility مع maintainSize
                                                          Visibility(
                                                            visible:
                                                                _isPerUnit(p),
                                                            maintainState: true,
                                                            maintainAnimation:
                                                                true,
                                                            maintainSize: true,
                                                            child: _chip(
                                                                'مشغولة: ${p.occupiedUnits}',
                                                                bg: const Color(
                                                                    0xFF7F1D1D)),
                                                          ),
                                                          Visibility(
                                                            visible:
                                                                _isPerUnit(p),
                                                            maintainState: true,
                                                            maintainAnimation:
                                                                true,
                                                            maintainSize: true,
                                                            child: _chip(
                                                                'المتاحة: ${_availableUnits(p)}',
                                                                bg: const Color(
                                                                    0xFF064E3B)),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            const Icon(
                                                Icons.chevron_left_rounded,
                                                color: Colors.white70),
                                          ],
                                        ),
                                      ),
                                      // نوع العقار
                                      Positioned(
                                        left: 8,
                                        top: 8,
                                        child: _chip(
                                            _isUnit(p)
                                                ? 'وحدة (${p.type.label})'
                                                : p.type.label,
                                            bg: const Color(0xFF334155)),
                                      ),
                                      // شارة نمط التأجير (عمارة فقط)
                                      if (_isBuilding(p))
                                        Positioned(
                                          left: 8,
                                          top: 38,
                                          child: _chip(
                                              _isPerUnit(p)
                                                  ? 'تأجير وحدات'
                                                  : 'تأجير كامل',
                                              bg: const Color(0xFF1E293B)),
                                        ),
                                      // الحالة
                                      Positioned(
                                        left: 8,
                                        bottom: 8,
                                        child: _chip(
                                            _isAvailable(p)
                                                ? 'متاحة'
                                                : 'مشغولة',
                                            bg: _isAvailable(p)
                                                ? const Color(0xFF065F46)
                                                : const Color(0xFF7F1D1D)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.add_business_rounded),
          label: Text('إضافة عقار',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            try {
            // 🚫 منع عميل المكتب من إضافة عقار
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final limitDecision = await PackageLimitService.canAddProperty();
            if (!limitDecision.allowed) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      limitDecision.message ??
                          'لا يمكن إضافة عقار جديد، لقد وصلت إلى الحد الأقصى المسموح.',
                      style: GoogleFonts.cairo(),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return;
            }

            final created = await Navigator.of(context).push<Property?>(
              MaterialPageRoute(
                  builder: (_) => const AddOrEditPropertyScreen()),
            );
            if (created != null) {
              await _box.put(created.id, created); // ← put باستخدام id
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تمت إضافة العقار بنجاح.',
                        style: GoogleFonts.cairo()),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailsScreen(item: created),
                  ),
                );
              }
            }
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      'تعذر التحقق من حد العقارات الآن. أعد المحاولة بعد قليل.',
                      style: GoogleFonts.cairo(),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
        ),
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Future<void> _openRowMenu(BuildContext context, Property p) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        final archived = _isArchivedProp(p.id);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('إجراءات سريعة',
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                SizedBox(height: 12.h),
                ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من التعديل
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                      return;
                    }

                    Navigator.pop(context);

                    final updated = await Navigator.of(context).push<Property?>(
                      MaterialPageRoute(
                          builder: (_) => AddOrEditPropertyScreen(existing: p)),
                    );
                    if (updated != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تحديث بيانات العقار بنجاح.',
                              style: GoogleFonts.cairo()),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {}); // للتحديث إن لزم
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PropertyDetailsScreen(item: updated),
                        ),
                      );
                    }
                  },
                  leading: const Icon(Icons.edit_rounded, color: Colors.white),
                  title: Text('تعديل',
                      style: GoogleFonts.cairo(color: Colors.white)),
                ),
                ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من الأرشفة/فك الأرشفة
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                      return;
                    }

                    Navigator.pop(context);
                    await _toggleArchiveForProperty(context, p);
                    if (mounted) setState(() {});
                  },
                  leading: Icon(
                      archived
                          ? Icons.unarchive_rounded
                          : Icons.archive_rounded,
                      color: Colors.white),
                  title: Text(archived ? 'فك الأرشفة' : 'أرشفة',
                      style: GoogleFonts.cairo(color: Colors.white)),
                ),
                ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من الحذف
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                      return;
                    }

                    Navigator.pop(context);
                    await _confirmDelete(context, p);
                  },
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.white),
                  title: Text('حذف',
                      style: GoogleFonts.cairo(color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Property p) async {
    final deleted = await _runPropertyHardDeleteFlow(context, p);
    if (!deleted) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف العقار وكل ما يرتبط به نهائيًا',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    }
    return;

    if (_isBuilding(p)) {
      final hasUnits = Hive.box<Property>(boxName(kPropertiesBox))
          .values
          .any((e) => e.parentBuildingId == p.id);
      if (hasUnits) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن الحذف',
          message: 'لا يمكن حذف العمارة قبل حذف جميع الوحدات التابعة لها.',
          confirmLabel: 'حسنًا',
        );
        return;
      }
    }

    // 🚫 منع حذف العقار في حال وجود أي عقد (نشط أو منتهي) مرتبط بهذا العقار
    try {
      final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
      final hasAnyContract = contractsBox.values.any(
        (c) => c.propertyId == p.id,
      );

      if (hasAnyContract) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن الحذف',
          message:
              'لا يمكن حذف هذا العقار لوجود عقود مرتبطة به حتى لو كانت منتهية.\n'
              'لحذف العقار يجب أولًا حذف جميع العقود المرتبطة به من شاشة العقود.',
          confirmLabel: 'حسنًا',
        );
        return;
      }
    } catch (_) {
      // لو حصل خطأ في قراءة صندوق العقود لا نكسر الشاشة
    }

    final confirmed =
        await _confirm(context, 'تأكيد الحذف', 'هل تريد حذف "${p.name}"؟');
    if (!confirmed) return;

    final parentId = p.parentBuildingId;
    await deletePropertyById(p.id);

    OfflineSyncService.instance.enqueueDeleteProperty(p.id); // بدون await

    // احذف حالة الأرشفة المخزنة له (وتتبّع للوحدات)
    await _clearArchiveState(p);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم حذف "${p.name}"', style: GoogleFonts.cairo()),
            behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).maybePop();
    }
  }

  Widget _alert(BuildContext ctx,
      {required String title, required String message}) {
    return CustomConfirmDialog(
      title: title,
      message: message,
      confirmLabel: 'حسنًا',
    );
  }

  Widget _chip(String text, {Color bg = const Color(0xFF334155)}) {
    return Container(
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
  }
}

/// ============================================================================
/// تفاصيل العقار
/// ============================================================================
class PropertyDetailsScreen extends StatefulWidget {
  final Property item;
  const PropertyDetailsScreen({super.key, required this.item});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  Box<Property> get _box => Hive.box<Property>(boxName(kPropertiesBox));
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');
  late Property _liveItem;

  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    _liveItem = widget.item;
    // افتح صندوق الأرشفة مبكرًا
    () async {
      await HiveService.ensureReportsBoxesOpen();
      await _openArchivedBox();
      if (mounted) setState(() {});
    }();
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  Property? _parentBuildingFor(Property p) {
    final parentId = (p.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return null;
    for (final candidate in _box.values) {
      if (candidate.id == parentId) return candidate;
    }
    return null;
  }

  bool _isPropertyArchivedNow(Property p) {
    if (_isArchivedProp(p.id) || p.isArchived) return true;
    final parent = _parentBuildingFor(p);
    if (parent == null) return false;
    return _isArchivedProp(parent.id) || parent.isArchived;
  }

  Future<void> _showArchivedPropertyActionDialog(
    Property p, {
    required bool forService,
  }) async {
    final parent = _parentBuildingFor(p);
    final selfArchived = _isArchivedProp(p.id) || p.isArchived;
    final parentArchived =
        parent != null && (_isArchivedProp(parent.id) || parent.isArchived);
    final entityLabel = p.parentBuildingId != null ? 'هذه الوحدة' : 'هذا العقار';
    final objectPronoun = p.parentBuildingId != null ? 'بها' : 'به';
    final usagePronoun = p.parentBuildingId != null ? 'استخدامها' : 'استخدامه';
    final message = parentArchived && !selfArchived && p.parentBuildingId != null
        ? (forService
            ? 'هذه الوحدة تابعة لعمارة مؤرشفة، لذلك لا يمكن إضافة خدمة جديدة أو ربط طلب خدمة بها قبل فك أرشفة العمارة أولًا.\n'
                'إذا كنت تريد استخدامها مرة أخرى في الخدمات، فقم بفك أرشفة العمارة ثم أعد المحاولة.'
            : 'هذه الوحدة تابعة لعمارة مؤرشفة، لذلك لا يمكن إضافة عقد جديد لها قبل فك أرشفة العمارة أولًا.\n'
                'إذا كنت تريد استخدامها مرة أخرى في التأجير، فقم بفك أرشفة العمارة ثم أعد المحاولة.')
        : (forService
            ? '$entityLabel مؤرشف حاليًا، لذلك لا يمكن إضافة خدمة جديدة أو ربط طلب خدمة $objectPronoun قبل فك الأرشفة.\n'
                'إذا كنت تريد $usagePronoun مرة أخرى في الخدمات، فقم بفك الأرشفة أولًا ثم أعد المحاولة.'
            : '$entityLabel مؤرشف حاليًا، لذلك لا يمكن إضافة عقد جديد قبل فك الأرشفة.\n'
                'إذا كنت تريد $usagePronoun مرة أخرى في التأجير، فقم بفك الأرشفة أولًا ثم أعد المحاولة.');
    await CustomConfirmDialog.show(
      context: context,
      title: 'تنبيه',
      message: message,
      confirmLabel: 'حسنًا',
      showCancel: false,
    );
  }

  /// فتح تفاصيل العقد مباشرة لعقار معيّن بدون المرور على شاشة العقود (لتفادي الوميض)
  List<String> _documentPaths(Property p) {
    final paths = <String>[
      ...?p.documentAttachmentPaths,
      if ((p.documentAttachmentPath ?? '').trim().isNotEmpty)
        p.documentAttachmentPath!.trim(),
    ];
    final out = <String>[];
    for (final x in paths) {
      if (x.trim().isEmpty) continue;
      if (!out.contains(x)) out.add(x);
    }
    return out;
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

  Future<void> _openDocumentAttachment(String path) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  bool _hasDocumentInfo(Property item) {
    return (item.documentType ?? '').trim().isNotEmpty ||
        (item.documentNumber ?? '').trim().isNotEmpty ||
        item.documentDate != null;
  }

  Widget _documentInfoInline(Property item) {
    if (!_hasDocumentInfo(item)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 10.h),
        Text(
          'معلومات الوثيقة',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13.5.sp,
          ),
        ),
        SizedBox(height: 6.h),
        if ((item.documentType ?? '').trim().isNotEmpty)
          _docRow('نوع الوثيقة', item.documentType!),
        if ((item.documentNumber ?? '').trim().isNotEmpty)
          _docRow('رقم الوثيقة', item.documentNumber!),
        if (item.documentDate != null)
          _docRow(
            'تاريخ الوثيقة',
            '${item.documentDate!.year}-${item.documentDate!.month.toString().padLeft(2, '0')}-${item.documentDate!.day.toString().padLeft(2, '0')}',
          ),
      ],
    );
  }

  Widget _docRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentAttachmentsBlock(Property item) {
    final paths = _documentPaths(item);
    if (paths.isEmpty) return const SizedBox.shrink();
    return _DarkCard(
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مرفقات الوثيقة',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: paths.map((path) {
              return InkWell(
                onTap: () => _showAttachmentActions(path),
                borderRadius: BorderRadius.circular(10.r),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    width: 88.w,
                    height: 88.w,
                    color: Colors.white.withOpacity(0.08),
                    child: _buildAttachmentThumb(path),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Property _resolveLatestProperty(Property current, Box<Property> box) {
    Property? found = box.get(current.id);
    if (found == null) {
      for (final v in box.values) {
        if (v.id == current.id) {
          found = v;
          break;
        }
      }
    }

    if (found == null) return current;

    final currentHasDoc = _hasDocumentInfo(current);
    final currentPaths = _documentPaths(current);
    final cached = _propertyDocCache[current.id];
    if (currentHasDoc || currentPaths.isNotEmpty) {
      bool changed = false;
      if ((found.documentType ?? '').trim().isEmpty &&
          (current.documentType ?? '').trim().isNotEmpty) {
        found.documentType = current.documentType;
        changed = true;
      }
      if ((found.documentNumber ?? '').trim().isEmpty &&
          (current.documentNumber ?? '').trim().isNotEmpty) {
        found.documentNumber = current.documentNumber;
        changed = true;
      }
      if (found.documentDate == null && current.documentDate != null) {
        found.documentDate = current.documentDate;
        changed = true;
      }
      final foundPaths = _documentPaths(found);
      if (foundPaths.isEmpty && currentPaths.isNotEmpty) {
        found.documentAttachmentPaths = List<String>.from(currentPaths);
        found.documentAttachmentPath = currentPaths.first;
        changed = true;
      }
      if (changed) {
        unawaited(box.put(found.id, found));
      }
    }

    if (_hasDocumentInfo(found) || _documentPaths(found).isNotEmpty) {
      return found;
    }

    if (cached != null) {
      bool changed = false;
      if ((found.documentType ?? '').trim().isEmpty &&
          (cached.documentType ?? '').trim().isNotEmpty) {
        found.documentType = cached.documentType;
        changed = true;
      }
      if ((found.documentNumber ?? '').trim().isEmpty &&
          (cached.documentNumber ?? '').trim().isNotEmpty) {
        found.documentNumber = cached.documentNumber;
        changed = true;
      }
      if (found.documentDate == null && cached.documentDate != null) {
        found.documentDate = cached.documentDate;
        changed = true;
      }
      final foundPaths = _documentPaths(found);
      if (foundPaths.isEmpty && cached.attachmentPaths.isNotEmpty) {
        found.documentAttachmentPaths =
            List<String>.from(cached.attachmentPaths);
        found.documentAttachmentPath = cached.attachmentPaths.first;
        changed = true;
      }
      if (changed) {
        unawaited(box.put(found.id, found));
      }
    }

    return found;
  }

  Future<void> _openContractDetailsDirect(Property p) async {
    try {
      final cname = HiveService.contractsBoxName();
      final contractsBox = Hive.isBoxOpen(cname)
          ? Hive.box<Contract>(cname)
          : await Hive.openBox<Contract>(cname);

      // كل العقود غير المؤرشفة المرتبطة بهذا العقار
      final byProp = contractsBox.values
          .where((c) => c.propertyId == p.id && !c.isArchived)
          .toList();

      if (byProp.isEmpty) {
        // احتياط: لو ما لقينا عقد (مع إن _hasActiveContract رجّع true) نرجع للسلوك القديم
        await Navigator.pushNamed(
          context,
          '/contracts',
          arguments: {'openPropertyId': p.id},
        );
        return;
      }

      // نفس منطق ContractsScreen: الأحدث، مع تفضيل العقد النشط الآن
      byProp.sort((a, b) => b.startDate.compareTo(a.startDate));
      final Contract target =
          byProp.firstWhere((c) => c.isActiveNow, orElse: () => byProp.first);

      // فتح شاشة تفاصيل العقد مباشرة
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractDetailsScreen(contract: target),
        ),
      );

      // بعد الرجوع: فك الأرشفة وتحديث الواجهة
      await _unarchiveSelfAndParent(p);
      if (mounted) setState(() {});
    } catch (_) {
      // في حالة أي خطأ، نفتح شاشة العقود الكاملة كحل احتياطي
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const contracts_ui.ContractsScreen(),
        ),
      );
    }
  }

  // في _PropertyDetailsScreenState
  // في _PropertyDetailsScreenState
  Future<void> _goToAddOrViewContract(Property p) async {
    if (_isPropertyArchivedNow(p)) {
      await _showArchivedPropertyActionDialog(p, forService: false);
      return;
    }
    final has = _hasActiveContract(p);
    try {
      if (has) {
        // 🔄 افتح تفاصيل العقد مباشرة بدون وميض شاشة العقود
        await _openContractDetailsDirect(p);
        return;
      }

      // شاشة إضافة عقد تُرجع Contract عند الحفظ والرجوع
      final result = await Navigator.pushNamed(
        context,
        '/contracts/new',
        arguments: {'prefillPropertyId': p.id},
      );

        if (result is Contract) {
          // خزّن العقد محليًا
          final cname = HiveService.contractsBoxName();
          final contractsBox = Hive.isBoxOpen(cname)
              ? Hive.box<Contract>(cname)
              : await Hive.openBox<Contract>(cname);
          await contractsBox.add(result);
          await linkWaterConfigToContractIfNeeded(result);

          // ✅ فورًا: فك الأرشفة عن العقار نفسه وإن كان وحدة فك عن العمارة الأب أيضًا
          await _unarchiveSelfAndParent(p);

        // حدّث عدّاد عقود المستأجر النشطة
        final tenants = Hive.box<Tenant>(boxName(kTenantsBox));
        Tenant? t;
        for (final e in tenants.values) {
          if (e.id == result.tenantId) {
            t = e;
            break;
          }
        }
        if (t != null && (result as dynamic).isActiveNow == true) {
          t.activeContractsCount += 1;
          t.updatedAt = KsaTime.now();
          await t.save();
        }

        // حدّث إشغال العقار/الوحدة
        final props = Hive.box<Property>(boxName(kPropertiesBox));
        Property? target;
        for (final e in props.values) {
          if (e.id == p.id) {
            target = e;
            break;
          }
        }

        if (target != null) {
          if (target.parentBuildingId != null) {
            // وحدة داخل عمارة
            target.occupiedUnits = 1;
            await props.put(target.id, target); // ← بدل save()

            // تحديث إشغال العمارة
            Property? building;
            for (final e in props.values) {
              if (e.id == target.parentBuildingId) {
                building = e;
                break;
              }
            }
            if (building != null) {
              final units =
                  props.values.where((e) => e.parentBuildingId == building!.id);
              final occupiedCount =
                  units.where((u) => u.occupiedUnits > 0).length;
              building.occupiedUnits = occupiedCount;
              await props.put(building.id, building); // ← بدل save()
            }
          } else {
            // عقار مستقل
            target.occupiedUnits = 1;
            await props.put(target.id, target); // ← بدل save()
          }
        }

        // افتح شاشة العقود بعد الحفظ وحدّث الواجهة
        if (mounted) {
          await Navigator.pushNamed(
            context,
            '/contracts',
            arguments: {'openPropertyId': p.id},
          );

          // ✅ تأكيد فكّ الأرشفة مجددًا بعد العودة
          await _unarchiveSelfAndParent(p);
          setState(() {});
        }
      }
    } catch (_) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const contracts_ui.ContractsScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _box.listenable(),
      builder: (context, Box<Property> b, _) {
        final item = _resolveLatestProperty(_liveItem, b);
        _liveItem = item;
        final parentBuilding = item.parentBuildingId == null
            ? null
            : (() {
                for (final e in b.values) {
                  if (e.id == item.parentBuildingId) return e;
                }
                return null;
              })();
        final available = _availableUnits(item);
        final bool fullyOccupied =
            _isPerUnit(item) ? (available == 0) : (item.occupiedUnits > 0);
        final String statusText = fullyOccupied ? 'مشغولة' : 'متاحة';
        final Color statusColor =
            fullyOccupied ? const Color(0xFFB91C1C) : const Color(0xFF059669);
        final spec = _parseSpec(item.description);
        final freeDesc = _extractFreeDesc(item.description).trim();
        final archived = _isArchivedProp(item.id);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
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
              title: Text('تفاصيل العقار',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              actions: [
                if (item.parentBuildingId ==
                    null) // إظهار الزر للعقار/العمارة فقط، وليس للوحدة
                  IconButton(
                    tooltip: archived ? 'فك الأرشفة' : 'أرشفة',
                    onPressed: () async {
                      // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
                      if (await OfficeClientGuard.blockIfOfficeClient(
                          context)) {
                        return;
                      }

                      await _toggleArchiveForProperty(context, item);
                      if (mounted) setState(() {});
                    },
                    icon: Icon(
                      archived
                          ? Icons.inventory_2_rounded
                          : Icons.archive_rounded,
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
                      ],
                    ),
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
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 140.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== بطاقة الرأس (مبسطة) =====
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: 128.h),
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
                                        borderRadius:
                                            BorderRadius.circular(12.r),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0F766E),
                                            Color(0xFF14B8A6)
                                          ],
                                          begin: Alignment.topRight,
                                          end: Alignment.bottomLeft,
                                        ),
                                      ),
                                      child: Icon(_iconOf(item.type),
                                          color: Colors.white),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 80.w),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(_limitChars(item.name, 50),
                                                maxLines: 2,
                                                softWrap: true,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.cairo(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16.sp)),
                                            SizedBox(height: 6.h),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.location_on_outlined,
                                                    size: 16.sp,
                                                    color: Colors.white70),
                                                SizedBox(width: 4.w),
                                                Expanded(
                                                  child: Text(
                                                    item.address,
                                                    style: GoogleFonts.cairo(
                                                        color: Colors.white70,
                                                        fontSize: 13.sp,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.5),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // --- التسميات في الزوايا (فقط الحالات) ---
                            // 1) نوع العقار (فوق على اليسار)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: _infoPill(item.type.label,
                                  bg: const Color(0xFF065F46)),
                            ),
                            // 2) تاجير وحدات (تحت نوع العقار)
                            if (_isBuilding(item) ||
                                item.parentBuildingId != null)
                              Positioned(
                                left: 0,
                                top: 32.h,
                                child: InkWell(
                                  onTap: item.parentBuildingId != null &&
                                          parentBuilding != null
                                      ? () async {
                                          final latestParent =
                                              b.get(parentBuilding.id) ??
                                                  parentBuilding;
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PropertyDetailsScreen(
                                                item: latestParent,
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(10.r),
                                  child: _infoPill(
                                    item.parentBuildingId != null
                                        ? 'عمارة'
                                        : (_isPerUnit(item)
                                            ? 'تأجير وحدات'
                                            : 'تأجير كامل'),
                                    bg: const Color(0xFF1E2937),
                                  ),
                                ),
                              ),
                            // 3) متاحة او مشغولة (تحت على اليسار)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: _infoPill(statusText, bg: statusColor),
                            ),
                            ],
                          ),
                        ),
                      ),
                      // ===== قسم تفاصيل العقار (جديد) =====
                      SizedBox(height: 10.h),
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('بيانات أساسية'),
                            _rowInfo('نوع العقار', item.type.label),
                            _rowInfo('العنوان', item.address),
                            if (_isBuilding(item))
                              _rowInfo('إجمالي الوحدات', '${item.totalUnits}'),
                            if (_isPerUnit(item)) ...[
                              _rowInfo('المشغولة', '${item.occupiedUnits}'),
                              _rowInfo('المتاحة', '$available'),
                            ],
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
                            if (item.type == PropertyType.building ||
                                item.type == PropertyType.villa)
                              _rowInfo(
                                'عدد الطوابق',
                                item.floors == null ? null : '${item.floors}',
                              ),
                            if (item.type == PropertyType.apartment ||
                                item.type == PropertyType.villa) ...[
                              _rowInfo(
                                'عدد الغرف',
                                item.rooms == null ? null : '${item.rooms}',
                              ),
                              _rowInfo(
                                'دورات المياه',
                                spec['حمامات']?.toString(),
                              ),
                              _rowInfo(
                                'عدد الصالات',
                                spec['صالات']?.toString(),
                              ),
                              _rowInfo(
                                'حالة الأثاث',
                                spec['المفروشات']?.toString(),
                              ),
                            ],
                            if (item.type == PropertyType.apartment)
                              _rowInfo(
                                'رقم الدور',
                                spec['الدور']?.toString(),
                              ),
                            if (!_isPerUnit(item))
                              _rowInfo(
                                'سعر التأجير',
                                item.price == null
                                    ? null
                                    : '${item.price!.toStringAsFixed(0)} ريال',
                              ),
                            _rowInfo(
                              'المساحة',
                              item.area == null ? null : '${item.area} م²',
                            ),
                            _rowInfo(
                              'الملاحظات',
                              freeDesc.isEmpty ? null : freeDesc,
                            ),
                          ],
                        ),
                      ),
                      if (_hasDocumentInfo(item) ||
                          _documentPaths(item).isNotEmpty) ...[
                        SizedBox(height: 10.h),
                        _DarkCard(
                          padding: EdgeInsets.all(12.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _documentInfoInline(item),
                              if (_documentPaths(item).isNotEmpty) ...[
                                SizedBox(height: 8.h),
                                _documentAttachmentsBlock(item),
                              ],
                            ],
                          ),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: EntityAuditInfoButton(
                          collectionName: 'properties',
                          entityId: item.id,
                        ),
                      ),
                      // ===== أزرار الإجراءات تحت البطاقة =====
                      SizedBox(height: 10.h),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8.w,
                              runSpacing: 8.h,
                              alignment: WrapAlignment.start,
                              textDirection: TextDirection.rtl,
                              children: [
                                _miniAction(
                                  icon: Icons
                                      .delete_forever_rounded, // ✅ أضفنا الأيقونة
                                  label: 'حذف',
                                  bg: const Color(0xFF7F1D1D),
                                  onTap: () async {
                                    // 🚫 منع عميل المكتب من الحذف
                                    if (await OfficeClientGuard
                                        .blockIfOfficeClient(context)) {
                                      return;
                                    }

                                    await _confirmDeleteHere(context, item);
                                  },
                                ),
                                _miniAction(
                                  icon: Icons.edit_rounded,
                                  label: 'تعديل',
                                  bg: const Color(0xFF334155),
                                  onTap: () async {
                                    // 🚫 منع عميل المكتب من التعديل
                                    if (await OfficeClientGuard
                                        .blockIfOfficeClient(context)) {
                                      return;
                                    }

                                    final updated = await Navigator.of(context)
                                        .push<Property?>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            item.parentBuildingId != null
                                                ? EditUnitScreen(unit: item)
                                                : AddOrEditPropertyScreen(
                                                    existing: item),
                                      ),
                                    );
                                    if (updated != null && mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'تم تحديث بيانات العقار بنجاح.',
                                              style: GoogleFonts.cairo()),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      setState(() => _liveItem = updated);
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PropertyDetailsScreen(
                                            item: updated,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                _miniAction(
                                  icon: Icons.description_outlined,
                                  label: 'الملاحظات',
                                  bg: const Color(0xFF334155),
                                  onTap: () async {
                                    // 🚫 منع عميل المكتب من فتح / تعديل الملاحظات
                                    if (await OfficeClientGuard
                                        .blockIfOfficeClient(context)) {
                                      return;
                                    }

                                    _showDescriptionSheet(context, item);
                                  },
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 8.h),

                          if (!_isPerUnit(item))
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _compactGridAction(
                                        icon: Icons.settings_suggest_rounded,
                                        label: 'الخدمات الدورية',
                                        bg: const Color(0xFF059669),
                                        onTap: () async {
                                          if (_isPropertyArchivedNow(item)) {
                                            await _showArchivedPropertyActionDialog(
                                              item,
                                              forService: true,
                                            );
                                            return;
                                          }
                                          await Navigator.pushNamed(
                                            context,
                                            '/property/services',
                                            arguments: {'propertyId': item.id},
                                          );
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                      SizedBox(height: 8.h),
                                      _compactGridAction(
                                        icon: _hasActiveContract(item)
                                            ? Icons
                                                .assignment_turned_in_rounded
                                            : Icons.note_add_rounded,
                                        label: _hasActiveContract(item)
                                            ? 'تفاصيل العقد'
                                            : 'إضافة عقد',
                                        bg: const Color(0xFF0EA5E9),
                                        onTap: () async {
                                          // 🚫 منع عميل المكتب من إضافة / فتح عقد
                                          if (await OfficeClientGuard
                                              .blockIfOfficeClient(context)) {
                                            return;
                                          }

                                          await _goToAddOrViewContract(item);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _compactGridAction(
                                        icon: Icons.build_circle_outlined,
                                        label: 'طلبات الخدمات',
                                        bg: const Color(0xFF9A3412),
                                        onTap: () async {
                                          await Navigator.pushNamed(
                                            context,
                                            '/maintenance',
                                            arguments: {
                                              'filterPropertyId': item.id,
                                              'filterPropertyName': item.name,
                                            },
                                          );
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                      SizedBox(height: 8.h),
                                      _compactGridAction(
                                        icon: Icons.history_rounded,
                                        label: 'عقود سابقة',
                                        bg: const Color(0xFF4338CA),
                                        onTap: () async {
                                          await Navigator.pushNamed(
                                            context,
                                            '/contracts',
                                            arguments: {
                                              'filterPreviousPropertyId':
                                                  item.id,
                                              'filterPreviousPropertyName':
                                                  item.name,
                                            },
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: _compactGridAction(
                                    icon: Icons.settings_suggest_rounded,
                                    label: 'الخدمات الدورية',
                                    bg: const Color(0xFF059669),
                                    onTap: () async {
                                      if (_isPropertyArchivedNow(item)) {
                                        await _showArchivedPropertyActionDialog(
                                          item,
                                          forService: true,
                                        );
                                        return;
                                      }
                                      await Navigator.pushNamed(
                                        context,
                                        '/property/services',
                                        arguments: {'propertyId': item.id},
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Expanded(
                                  child: _compactGridAction(
                                    icon: Icons.build_circle_outlined,
                                    label: 'طلبات الخدمات',
                                    bg: const Color(0xFF9A3412),
                                    onTap: () async {
                                      await Navigator.pushNamed(
                                        context,
                                        '/maintenance',
                                        arguments: {
                                          'filterPropertyId': item.id,
                                          'filterPropertyName': item.name,
                                        },
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // زر إضافة وحدات (إن كانت عمارة ووضع تأجير وحدات)
                      if (_isPerUnit(item)) ...[
                        SizedBox(height: 12.h),
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
                            onPressed: () async {
                              final existing = _countUnits(item);
                              if (item.totalUnits > 0 &&
                                  existing >= item.totalUnits) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'تم إضافة جميع الوحدات المتعلقة بالعمارة سابقًا',
                                          style: GoogleFonts.cairo()),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                                return;
                              }

                              final list = await Navigator.of(context)
                                  .push<List<Property>?>(
                                MaterialPageRoute(
                                    builder: (_) => AddUnitsScreen(
                                        building: item,
                                        existingUnitsCount: existing)),
                              );

                              if (list != null && list.isNotEmpty) {
                                final box =
                                    Hive.box<Property>(boxName(kPropertiesBox));
                                for (final u in list) {
                                  await box.put(
                                      u.id, u); // ← استخدم المفتاح = id
                                }

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'تمت إضافة ${list.length} وحدة',
                                            style: GoogleFonts.cairo()),
                                        behavior: SnackBarBehavior.floating),
                                  );
                                  setState(() {});
                                }
                              }
                            },
                            icon: const Icon(Icons.add_home_work_rounded),
                            label: Text('إضافة وحدات العمارة',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],

                      // ===== قائمة الوحدات للوضع "تأجير وحدات" =====
                      if (_isPerUnit(item)) ...[
                        SizedBox(height: 14.h),
                        Text('الوحدات',
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 8.h),
                        ValueListenableBuilder(
                          valueListenable: _box.listenable(),
                          builder: (context, box, _) {
                            final b = box;
                            final units = b.values
                                .where((e) => e.parentBuildingId == item.id)
                                .toList()
                              ..sort((a, c) {
                                // 1) الأحدث أولًا بالاعتماد على id الزمني (microsecondsSinceEpoch)
                                final ai = int.tryParse(a.id) ?? 0;
                                final ci = int.tryParse(c.id) ?? 0;
                                final byIdDesc = ci.compareTo(ai);
                                if (byIdDesc != 0) return byIdDesc;

                                // 2) تعادل الوقت: فكّ الترتيب بحسب الرقم في نهاية الاسم (الأكبر أولًا)
                                final an = _extractTrailingNumber(a.name);
                                final cn = _extractTrailingNumber(c.name);
                                if (an != cn) return cn.compareTo(an);

                                // 3) تعادل تام: ترتيب أبجدي تنازلي كحل أخير
                                return c.name.compareTo(a.name);
                              });

                            if (units.isEmpty) {
                              return Text('لا توجد وحدات بعد',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700));
                            }

                            return Column(
                              children: [
                                for (final u in units) ...[
                                  _unitCard(u),
                                  SizedBox(height: 10.h),
                                ]
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: AppBottomNav(
              key: _bottomNavKey,
              currentIndex: 1,
              onTap: _handleBottomTap,
            ),
          ),
        );
      },
    );
  }

  // ===== إجراءات الملاحظات =====
  void _showDescriptionSheet(BuildContext context, Property p) {
    final String oldDesc = p.description ?? '';
    final String existingFree = _extractFreeDesc(oldDesc);
    final controller = TextEditingController(text: existingFree);

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
                    'الملاحظات',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),

              // حقل تحرير الملاحظات الحر
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: 500,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب ملاحظات العقار هنا…',
                  hintStyle: GoogleFonts.cairo(color: Colors.white54),
                  counterText: '',
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
                        // نفس كود الحفظ بدون أي تغيير
                        final newFree = controller.text.trim();
                        String newDesc;
                        final d = oldDesc;
                        final start = d.indexOf('[[SPEC]]');
                        final end = d.indexOf('[[/SPEC]]');
                        if (start != -1 && end != -1 && end > start) {
                          final specBlock = d.substring(0, end + 9).trimRight();
                          newDesc = newFree.isEmpty
                              ? specBlock
                              : '$specBlock\n$newFree';
                        } else {
                          newDesc = newFree;
                        }
                        p.description = newDesc.trim();
                        final box = Hive.box<Property>(boxName(kPropertiesBox));
                        await box.put(p.id, p);

                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('تم حفظ الملاحظات',
                                    style: GoogleFonts.cairo()),
                                behavior: SnackBarBehavior.floating),
                          );
                          setState(() {});
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
  }

  int _countUnits(Property building) {
    final all = Hive.box<Property>(boxName(kPropertiesBox)).values;
    return all.where((e) => e.parentBuildingId == building.id).length;
  }

  // بطاقة وحدة ضمن شاشة تفاصيل العمارة — بدون زر تعديل، والضغط يفتح التفاصيل
  Widget _unitCard(Property u) {
    final available = _isAvailable(u);

    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => PropertyDetailsScreen(item: _box.get(u.id) ?? u)),
        );
        if (mounted) setState(() {});
      },
      child: _DarkCard(
        padding: EdgeInsets.all(12.w),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 108.h),
              child: Row(
                children: [
                  Container(
                    width: 48.w,
                    height: 48.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.r),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                    child: Icon(_iconOf(u.type), color: Colors.white),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 120.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _limitChars(u.name, 50),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.sp,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14.sp, color: Colors.white70),
                              SizedBox(width: 4.w),
                              Expanded(
                                child: Text(
                                  u.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    color: Colors.white70,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6.h),
                          Wrap(
                            spacing: 6.w,
                            runSpacing: 6.h,
                            children: [
                              _infoPill(
                                available ? 'متاحة' : 'مشغولة',
                                bg: available
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF7F1D1D),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                ],
              ),
            ),

            // شارة نوع العنصر (وحدة)
            Positioned(
              left: 8,
              top: 8,
              child: _infoPill('وحدة (${u.type.label})',
                  bg: const Color(0xFF334155)),
            ),

            // ✅ تمت إزالة زر "تعديل" نهائيًا
          ],
        ),
      ),
    );
  }

  // عناصر UI صغيرة
  Widget _miniAction(
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color bg = const Color(0xFF334155)}) {
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

  Widget _compactGridAction(
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color bg = const Color(0xFF334155)}) {
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        child: _miniAction(
          icon: icon,
          label: label,
          onTap: onTap,
          bg: bg,
        ),
      ),
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

  Widget _pill(String text, {Color bg = const Color(0xFF1E293B)}) {
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
              fontSize: 12.sp,
              fontWeight: FontWeight.w700)),
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

  // حوار تنبيه محلي لهذه الشاشة
  Widget _alertHere(BuildContext ctx,
      {required String title, required String message}) {
    return CustomConfirmDialog(
      title: title,
      message: message,
      confirmLabel: 'حسنًا',
    );
  }

  Future<void> _confirmDeleteHere(BuildContext context, Property p) async {
    final deleted = await _runPropertyHardDeleteFlow(context, p);
    if (!deleted) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف العقار وكل ما يرتبط به نهائيًا',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    }
    return;

    // منع حذف العمارة التي بها وحدات
    if (_isBuilding(p)) {
      final hasUnits = Hive.box<Property>(boxName(kPropertiesBox))
          .values
          .any((e) => e.parentBuildingId == p.id);
      if (hasUnits) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن الحذف',
          message: 'لا يمكن حذف العمارة قبل حذف جميع الوحدات التابعة لها.',
          confirmLabel: 'حسنًا',
        );
        return;
      }
    }

    // 🚫 منع الحذف في حال وجود أي عقد (نشط أو منتهي) مرتبط بهذا العقار
    try {
      final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
      final hasAnyContract = contractsBox.values.any(
        (c) => c.propertyId == p.id,
      );

      if (hasAnyContract) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن الحذف',
          message:
              'لا يمكن حذف هذا العقار لوجود عقود مرتبطة به حتى لو كانت منتهية.\n'
              'لحذف العقار يجب أولًا حذف جميع العقود المرتبطة به من شاشة العقود.',
          confirmLabel: 'حسنًا',
        );
        return;
      }
    } catch (_) {
      // لو حصل خطأ في قراءة صندوق العقود لا نكسر الشاشة
    }

    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل تريد حذف "${p.name}"؟',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (!ok) return;

    final parentId = p.parentBuildingId;
    await deletePropertyById(p.id);

    // إزالة حالة الأرشفة (مع تتبّع)
    await _clearArchiveState(p);

    // إن كانت وحدة: حدّث إجمالي وحدات العمارة

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم حذف "${p.name}"', style: GoogleFonts.cairo()),
            behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).maybePop();
    }
  }
}

/// ============================================================================
/// إضافة/تعديل عقار (شاشة واحدة تدعم الوضعين)
/// ============================================================================
class AddOrEditPropertyScreen extends StatefulWidget {
  final Property? existing; // null = إضافة

  const AddOrEditPropertyScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AddOrEditPropertyScreen> createState() =>
      _AddOrEditPropertyScreenState();
}

class _AddOrEditPropertyScreenState extends State<AddOrEditPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Bottom nav + drawer ضبط
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  // Controllers
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _units = TextEditingController();
  final _floors = TextEditingController();
  final _rooms = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _documentNumber = TextEditingController();

  // المواصفات
  final _baths = TextEditingController();
  final _halls = TextEditingController();
  final _aptFloorNo = TextEditingController();
  bool? _furnished;
  String? _documentType;
  DateTime? _documentDate;
  final List<String> _documentAttachments = <String>[];
  final Set<String> _initialLocalDocumentAttachments = <String>{};
  bool _uploadingDocumentAttachments = false;
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  PropertyType? _selectedType;
  RentalMode? _rentalMode;
  String _currency = 'SAR';

  bool get isBuilding => _selectedType == PropertyType.building;
  bool get isPerUnit => isBuilding && _rentalMode == RentalMode.perUnit;
  int get _existingUnitsCountForEdit {
    final current = widget.existing;
    if (current == null) return 0;
    return Hive.box<Property>(boxName(kPropertiesBox))
        .values
        .where((e) => e.parentBuildingId == current.id)
        .length;
  }

  bool get _hasExistingUnitsForEdit =>
      widget.isEdit && _existingUnitsCountForEdit > 0;

  bool get _isLinkedForEdit {
    final current = widget.existing;
    if (current == null) return false;
    return _hasActiveContract(current) || _existingUnitsCountForEdit > 0;
  }

  void _showLockedTypeMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لا يمكن تغيير نوع العقار لأنه مرتبط بوحدات/عقود. لتغييره احذف العقار وأضِفه من جديد.',
          style: GoogleFonts.cairo(),
        ),
      ),
    );
  }

  void _showLockedRentalModeMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لا يمكن تحويل نمط التأجير إلى تأجير كامل العمارة أثناء وجود وحدات مضافة. احذف الوحدات أولا ثم أعد المحاولة.',
          style: GoogleFonts.cairo(),
        ),
      ),
    );
  }

  void _showUnitsLessThanExistingMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لا يمكن تقليل عدد الوحدات إلى أقل من الوحدات المنشأة حاليا. يمكنك زيادة العدد الآن، ولتقليل العدد يجب حذف الوحدات الحالية أولا.',
          style: GoogleFonts.cairo(),
        ),
      ),
    );
  }

  // يظهر حقل عدد الوحدات للعمارة
  bool get showUnitsField => isBuilding;

  bool get showFloors =>
      _selectedType == PropertyType.building ||
      _selectedType == PropertyType.villa;
  bool get showRooms =>
      _selectedType == PropertyType.apartment ||
      _selectedType == PropertyType.villa;
  bool get requireArea => _selectedType == PropertyType.land;
  bool get showArea => true;

  bool get showBathsHallsFurnished =>
      _selectedType == PropertyType.apartment ||
      _selectedType == PropertyType.villa;
  bool get showApartmentFloorNo => _selectedType == PropertyType.apartment;

  @override
  void initState() {
    super.initState();

    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _address.text = e.address;
      _selectedType = e.type;
      _rentalMode = e.rentalMode;
      _units.text = e.totalUnits > 0 ? e.totalUnits.toString() : '';
      _floors.text = e.floors?.toString() ?? '';
      _rooms.text = e.rooms?.toString() ?? '';
      _area.text = e.area?.toString() ?? '';
      _price.text = e.price?.toString() ?? '';
      _currency = e.currency;
      final spec = _parseSpec(e.description);
      _baths.text = spec['حمامات'] ?? '';
      _halls.text = spec['صالات'] ?? '';
      _aptFloorNo.text = spec['الدور'] ?? '';
      _furnished = _parseFurnishedSpecValue(spec['المفروشات']);
      _desc.text = _extractFreeDesc(e.description);
      _documentType = e.documentType;
      _documentNumber.text = e.documentNumber ?? '';
      _documentDate = e.documentDate;
      final paths = <String>[
        ...?e.documentAttachmentPaths,
        if ((e.documentAttachmentPath ?? '').trim().isNotEmpty)
          e.documentAttachmentPath!.trim(),
      ];
      for (final p in paths) {
        if (!_documentAttachments.contains(p)) {
          _documentAttachments.add(p);
        }
      }
      _initialLocalDocumentAttachments
        ..clear()
        ..addAll(_documentAttachments.where((path) => !_isRemoteAttachment(path)));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _units.dispose();
    _floors.dispose();
    _rooms.dispose();
    _area.dispose();
    _price.dispose();
    _desc.dispose();
    _documentNumber.dispose();
    _baths.dispose();
    _halls.dispose();
    _aptFloorNo.dispose();
    super.dispose();
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  // ⬇️ بدّل الدالة الموجودة بنفس الاسم بهذه
  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final fmts = <TextInputFormatter>[];
    if (inputFormatters != null) fmts.addAll(inputFormatters);
    if (maxLength != null) {
      fmts.add(_limitWithFeedbackFormatter(
        max: maxLength,
        exceedMsg: 'تجاوزت الحد الأقصى ($maxLength)',
      ));
    }

    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      inputFormatters: fmts,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      // لا نعرض 0/XX
      buildCounter: (ctx,
              {required int? currentLength,
              required bool? isFocused,
              required int? maxLength}) =>
          null,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        counterText: '', // احتياط لإخفاء 0/XX
      ),
    );
  }

  Future<PropertyType?> _pickPropertyType() async {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<PropertyType>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PropertyTypePickerSheet(selectedType: _selectedType),
    );
  }

  Widget _propertyTypeField({required bool enabled}) {
    return FormField<PropertyType>(
      initialValue: _selectedType,
      validator: (value) => value == null ? 'اختر نوع العقار' : null,
      builder: (state) {
        final selectedType = state.value;
        final hasSelection = selectedType != null;
        return InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: () async {
            if (!enabled) {
              _showLockedTypeMessage();
              return;
            }
            final picked = await _pickPropertyType();
            if (picked == null || !mounted) return;
            setState(() {
              _selectedType = picked;
              if (_selectedType != PropertyType.building) {
                _rentalMode = null;
              }
            });
            state.didChange(picked);
            if (state.hasError) {
              state.validate();
            }
          },
          child: InputDecorator(
            isEmpty: !hasSelection,
            decoration: InputDecoration(
              errorText: state.errorText,
              filled: true,
              fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              suffixIcon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: enabled ? Colors.white70 : Colors.white38,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasSelection
                      ? _propertyTypePickerIcon(selectedType!)
                      : Icons.apartment_rounded,
                  color: hasSelection ? Colors.white : Colors.white60,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    hasSelection ? selectedType!.label : 'اختر نوع العقار',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      color: hasSelection ? Colors.white : Colors.white70,
                      fontWeight:
                          hasSelection ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

  Future<void> _openDocumentAttachment(String path) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<String?> _uploadDocumentAttachmentToStorage(
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
          .child('property_documents')
          .child(fileName);
      await ref.putFile(localFile);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveDocumentAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}property_documents');
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

  Future<void> _pickDocumentDate() async {
    final nowKsa = KsaTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: KsaTime.dateOnly(_documentDate ?? nowKsa),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(nowKsa.year + 50, 12, 31),
      helpText: 'اختر تاريخ الوثيقة',
      confirmText: 'اختيار',
      cancelText: 'إلغاء',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF0B1220),
              onSurface: Colors.white,
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: Color(0xFF0B1220)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _documentDate = KsaTime.dateOnly(picked));
    }
  }

  Future<void> _pickDocumentAttachments() async {
    if (_documentAttachments.length >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3',
              style: GoogleFonts.cairo(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    final remaining = 3 - _documentAttachments.length;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final selectedFiles = picked.files.take(remaining).toList();
    if (picked.files.length > remaining && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3',
              style: GoogleFonts.cairo(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }

    setState(() => _uploadingDocumentAttachments = true);
    try {
      int failed = 0;
      for (final file in selectedFiles) {
        final localPath = await _saveDocumentAttachmentLocally(file);
        if (localPath == null) {
          failed += 1;
          continue;
        }
        if (!_documentAttachments.contains(localPath)) {
          _documentAttachments.add(localPath);
        }
      }
      if (failed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ $failed مرفق',
                style: GoogleFonts.cairo(color: Colors.white)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDocumentAttachments = false);
    }
  }

  List<String> _removedInitialLocalDocumentAttachments() {
    final currentPaths = _documentAttachments
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return _initialLocalDocumentAttachments
        .where((path) => !currentPaths.contains(path))
        .toList(growable: false);
  }

  Future<void> _deleteLocalDocumentAttachments(Iterable<String> paths) async {
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

  Future<void> _confirmRemoveDocumentAttachment(String path) async {
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف المرفق؟ لن يتم استرجاعه مجددًا.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (ok != true || !mounted) return;
    setState(() => _documentAttachments.remove(path));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;

    // في وضع التعديل: نسمح بالتعديل مع قيود مرتبطة بالعقود/الوحدات فقط
    final canChangeType = !isEdit || !_isLinkedForEdit;
    final canChangeRentalMode = !isEdit || !_hasExistingUnitsForEdit;

    return WillPopScope(
      onWillPop: () async => !_uploadingDocumentAttachments,
      child: AbsorbPointer(
        absorbing: _uploadingDocumentAttachments,
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
              title: Text(isEdit ? 'تعديل عقار' : 'إضافة عقار',
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
                      ],
                    ),
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
                          // الاسم: مطلوب، حتى 60 حرف (يُمنع تجاوزها + تظهر رسالة "هذا أقصى حد")
                          _field(
                            controller: _name,
                            label: 'اسم العقار أو رقم العقار',
                            maxLength: 25,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'هذا الحقل مطلوب';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // العنوان: مطلوب، حتى 50 حرف
                          _field(
                            controller: _address,
                            label: 'العنوان ',
                            maxLength: 50,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'هذا الحقل مطلوب';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // نوع العقار
                          _propertyTypeField(enabled: canChangeType),
                          const SizedBox(height: 12),

                          // نمط التأجير (للعمارة فقط)
                          DropdownButtonFormField<String>(
                            initialValue: _documentType,
                            decoration: _dd('نوع الوثيقة'),
                            dropdownColor: const Color(0xFF0F172A),
                            iconEnabledColor: Colors.white70,
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                            items: const [
                              DropdownMenuItem(
                                  value: 'صك الكتروني',
                                  child: Text('صك الكتروني')),
                              DropdownMenuItem(
                                  value: 'صك ورقي', child: Text('صك ورقي')),
                              DropdownMenuItem(
                                  value: 'تسجيل عيني',
                                  child: Text('تسجيل عيني')),
                            ],
                            onChanged: (v) => setState(() => _documentType = v),
                          ),
                          const SizedBox(height: 12),
                          if (_documentType != null) ...[
                            _field(
                              controller: _documentNumber,
                              label: 'رقم الوثيقة',
                              maxLength: 25,
                              keyboardType: TextInputType.text,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9A-Za-z\u0600-\u06FF ]'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(12.r),
                              onTap: _pickDocumentDate,
                              child: InputDecorator(
                                decoration: _dd('تاريخ الوثيقة'),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded,
                                        color: Colors.white70),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: Text(
                                        _documentDate == null
                                            ? 'اختر التاريخ'
                                            : '${_documentDate!.year}-${_documentDate!.month.toString().padLeft(2, '0')}-${_documentDate!.day.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.cairo(
                                            color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'مرفقات الوثيقة (${_documentAttachments.length}/3)',
                                    style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0EA5E9),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _uploadingDocumentAttachments
                                      ? null
                                      : _pickDocumentAttachments,
                                  icon: _uploadingDocumentAttachments
                                      ? SizedBox(
                                          width: 16.w,
                                          height: 16.w,
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.attach_file_rounded),
                                  label: Text('إرفاق',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            SizedBox(height: 8.h),
                            if (_documentAttachments.isNotEmpty) ...[
                              Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                children: _documentAttachments.map((path) {
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      InkWell(
                                        onTap: () =>
                                            _showAttachmentActions(path),
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                          child: Container(
                                            width: 88.w,
                                            height: 88.w,
                                            color:
                                                Colors.white.withOpacity(0.08),
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
                                              _confirmRemoveDocumentAttachment(
                                                  path),
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
                              const SizedBox(height: 12),
                            ],
                          ],

                          if (_selectedType == PropertyType.building) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text('نمط التأجير',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 6),
                            _rentalChoice(
                              value: RentalMode.wholeBuilding,
                              group: _rentalMode,
                              onChanged: (v) {
                                if (!canChangeRentalMode &&
                                    v == RentalMode.wholeBuilding &&
                                    _hasExistingUnitsForEdit) {
                                  _showLockedRentalModeMessage();
                                  return;
                                }
                                setState(() => _rentalMode = v);
                              },
                              title: 'تأجير كامل العمارة',
                              subtitle:
                                  'عقد واحد يشمل المبنى كاملًا، بدون وحدات داخلية.',
                            ),
                            const SizedBox(height: 8),
                            _rentalChoice(
                              value: RentalMode.perUnit,
                              group: _rentalMode,
                              onChanged: (v) {
                                if (!canChangeRentalMode &&
                                    v == RentalMode.wholeBuilding &&
                                    _hasExistingUnitsForEdit) {
                                  _showLockedRentalModeMessage();
                                  return;
                                }
                                setState(() => _rentalMode = v);
                              },
                              title: 'تأجير الوحدات',
                              subtitle:
                                  'إضافة وحدات (شقق/مكاتب) لكل عقد مستقل.',
                            ),
                            const SizedBox(height: 12),
                          ],

                          // عدد الوحدات (للعمارة): يمنع > 500
                          if (showUnitsField) ...[
                            _field(
                              controller: _units,
                              label: isPerUnit
                                  ? 'عدد الوحدات (مطلوب 1–500)'
                                  : 'عدد الوحدات (اختياري 1–500)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 500,
                                    exceedMsg: 'الحد الأقصى للوحدات هو 500'),
                              ],
                              enabled: true,
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (isPerUnit && t.isEmpty) {
                                  return 'عدد الوحدات مطلوب';
                                }
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 1 || n > 500) {
                                  return 'أدخل عددًا صحيحًا (1–500)';
                                }
                                if (widget.isEdit &&
                                    isPerUnit &&
                                    n < _existingUnitsCountForEdit) {
                                  return 'لا يمكن أن يكون أقل من عدد الوحدات المضافة حاليا ($_existingUnitsCountForEdit)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // الطوابق: يمنع > 100
                          if (showFloors) ...[
                            _field(
                              controller: _floors,
                              label: 'عدد الطوابق (1–100)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 100,
                                    exceedMsg: 'الحد الأقصى للطوابق هو 100'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null; // اختياري
                                final n = int.tryParse(t);
                                if (n == null || n < 1 || n > 100) {
                                  return 'أدخل رقمًا بين 1 و 100';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // الغرف: يمنع > 20
                          if (showRooms) ...[
                            _field(
                              controller: _rooms,
                              label: 'عدد الغرف (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 20,
                                    exceedMsg: 'الحد الأقصى للغرف هو 20'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 0 || n > 20) {
                                  return 'أدخل رقمًا بين 0 و 20';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // حمامات/صالات: يمنع > 20 و > 10
                          if (showBathsHallsFurnished) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    controller: _baths,
                                    label: 'عدد الحمامات (اختياري)',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      _maxIntWithFeedback(
                                          max: 20,
                                          exceedMsg: 'الحد الأقصى هو 20'),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _field(
                                    controller: _halls,
                                    label: 'عدد الصالات (اختياري)',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      _maxIntWithFeedback(
                                          max: 10,
                                          exceedMsg: 'الحد الأقصى هو 10'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FormField<bool?>(
                              initialValue: _furnished,
                              validator: (_) =>
                                  _furnished == null ? 'هذا الحقل مطلوب' : null,
                              builder: (field) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text('المفروشات:',
                                            style: GoogleFonts.cairo(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w700)),
                                        ChoiceChip(
                                          label: const Text('مفروشة'),
                                          selected: _furnished == true,
                                          onSelected: (_) {
                                            setState(() => _furnished = true);
                                            field.didChange(true);
                                          },
                                          showCheckmark: false,
                                          selectedColor: const Color(
                                              0xFF059669), // أخضر عند التحديد
                                          backgroundColor: const Color(
                                              0xFF1F2937), // ✅ لون افتراضي داكن بدل الأبيض
                                          labelStyle: GoogleFonts.cairo(
                                            color: _furnished == true
                                                ? Colors.white
                                                : Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        ChoiceChip(
                                          label: const Text('غير مفروشة'),
                                          selected: _furnished == false,
                                          onSelected: (_) {
                                            setState(() => _furnished = false);
                                            field.didChange(false);
                                          },
                                          showCheckmark: false,
                                          selectedColor: const Color(
                                              0xFF059669), // أخضر عند التحديد
                                          backgroundColor: const Color(
                                              0xFF1F2937), // ✅ لون افتراضي داكن بدل الأبيض
                                          labelStyle: GoogleFonts.cairo(
                                            color: _furnished == false
                                                ? Colors.white
                                                : Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (field.hasError)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(field.errorText!,
                                          style: GoogleFonts.cairo(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // رقم الدور: يمنع > 100
                          if (showApartmentFloorNo) ...[
                            _field(
                              controller: _aptFloorNo,
                              label: 'رقم الدور (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 100,
                                    exceedMsg: 'الحد الأقصى لرقم الدور هو 100'),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          // المساحة: تمنع > 100000
                          if (showArea) ...[
                            _field(
                              controller: _area,
                              label: requireArea
                                  ? 'المساحة (اختياري)'
                                  : 'المساحة (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                                _maxNumWithFeedback(
                                    max: 100000,
                                    exceedMsg: 'الحد الأقصى للمساحة هو 100000'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (requireArea && t.isEmpty) {
                                  return 'المساحة مطلوبة للأراضي';
                                }
                                if (t.isEmpty) return null;
                                final n = double.tryParse(t);
                                if (n == null || n < 1) {
                                  return 'أدخل رقمًا بين 1 و 100000';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          if (!isPerUnit) ...[
                            // سعر التأجير: يمنع > 999,999,999
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    controller: _price,
                                    label: 'سعر التأجير (اختياري)',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.]')),
                                      _maxNumWithFeedback(
                                          max: 999999999,
                                          exceedMsg:
                                              'الحد الأقصى لسعر التأجير هو 999,999,999'),
                                    ],
                                    validator: (v) {
                                      final t = (v ?? '').trim();
                                      if (t.isEmpty) return null;
                                      final n = double.tryParse(t);
                                      if (n == null || n < 1) {
                                        return 'أدخل رقمًا بين 1 و 999,999,999';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _currency,
                                    decoration: _dd('العملة'),
                                    dropdownColor: const Color(0xFF0F172A),
                                    iconEnabledColor: Colors.white70,
                                    style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700),
                                    items: const ['SAR']
                                        .map(
                                          (c) => DropdownMenuItem<String>(
                                            value: c,
                                            child: const Text('ريال'),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _currency = v ?? 'ريال'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          // الوصف: حتى 500 حرف (منع + تنبيه)
                          _field(
                            controller: _desc,
                            label: 'الوصف/ملاحظات (اختياري)',
                            maxLines: 4,
                            maxLength: 500,
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _save,
                              icon: const Icon(Icons.check),
                              label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_uploadingDocumentAttachments)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.25),
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
              ],
            ),
            bottomNavigationBar: AppBottomNav(
              key: _bottomNavKey,
              currentIndex: 1,
              onTap: _handleBottomTap,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedType == null) return;

    if (_selectedType == PropertyType.building && _rentalMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('اختر نمط التأجير للعمارة', style: GoogleFonts.cairo())),
      );
      return;
    }

    // الوثيقة إلزامية في الإضافة والتعديل.
    if ((_documentType ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حقل نوع الوثيقة مطلوب', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (_documentNumber.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حقل رقم الوثيقة مطلوب', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (_documentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حقل تاريخ الوثيقة مطلوب', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (_documentAttachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حقل مرفقات الوثيقة مطلوب', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final baths = int.tryParse(_baths.text.trim());
    final halls = int.tryParse(_halls.text.trim());
    final aptFloor = int.tryParse(_aptFloorNo.text.trim());
    final furnished = _furnished;

    // 👈 وقت موحّد لهذي العملية (إضافة/تعديل)
    final now = KsaTime.now();

    final mergedDesc = _buildSpec(
      baths: (_selectedType == PropertyType.apartment ||
              _selectedType == PropertyType.villa)
          ? baths
          : null,
      halls: (_selectedType == PropertyType.apartment ||
              _selectedType == PropertyType.villa)
          ? halls
          : null,
      floorNo: (_selectedType == PropertyType.apartment) ? aptFloor : null,
      furnished: (_selectedType == PropertyType.apartment ||
              _selectedType == PropertyType.villa)
          ? furnished
          : null,
      extraDesc: _desc.text,
    );

    final parsedUnits = int.tryParse(_units.text.trim()) ?? 0;

    if (widget.isEdit && widget.existing != null) {
      debugPrint('[property/save][edit] id=${widget.existing!.id}');
      debugPrint('[property/save][edit] documentType=${_documentType?.trim()}');
      debugPrint(
          '[property/save][edit] documentNumber=${_documentNumber.text.trim()}');
      debugPrint(
          '[property/save][edit] documentDate=${_documentDate == null ? 'null' : KsaTime.dateOnly(_documentDate!).toIso8601String()}');
      debugPrint(
          '[property/save][edit] attachments=${_documentAttachments.length}');
      final m = widget.existing!;
      _propertyDocCache[m.id] = _PropertyDocSnapshot(
        documentType: _documentType?.trim(),
        documentNumber: _documentNumber.text.trim(),
        documentDate:
            _documentDate == null ? null : KsaTime.dateOnly(_documentDate!),
        attachmentPaths: List<String>.from(_documentAttachments),
      );
      if (_selectedType != m.type && _isLinkedForEdit) {
        _showLockedTypeMessage();
        return;
      }
      if (_isBuilding(m) &&
          m.rentalMode == RentalMode.perUnit &&
          _rentalMode == RentalMode.wholeBuilding &&
          _existingUnitsCountForEdit > 0) {
        _showLockedRentalModeMessage();
        return;
      }
      if (_selectedType == PropertyType.building &&
          _rentalMode == RentalMode.perUnit &&
          parsedUnits < _existingUnitsCountForEdit) {
        _showUnitsLessThanExistingMessage();
        return;
      }
      m.name = _name.text.trim();
      m.address = _address.text.trim();
      m.type = _selectedType!;
      m.rentalMode =
          _selectedType == PropertyType.building ? _rentalMode : null;
      if (_selectedType == PropertyType.building) {
        m.totalUnits = parsedUnits;
      } else {
        m.totalUnits = 0;
      }

      m.area =
          _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim());
      m.floors = _floors.text.trim().isEmpty
          ? null
          : int.tryParse(_floors.text.trim());
      m.rooms =
          _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim());
      m.price = isPerUnit
          ? null
          : (_price.text.trim().isEmpty
              ? null
              : double.tryParse(_price.text.trim()));
      m.currency = _currency;
      m.description = mergedDesc;
      m.documentType = _documentType?.trim();
      m.documentNumber = _documentNumber.text.trim();
      m.documentDate =
          _documentDate == null ? null : KsaTime.dateOnly(_documentDate!);
      m.documentAttachmentPaths = List<String>.from(_documentAttachments);
      m.documentAttachmentPath =
          _documentAttachments.isNotEmpty ? _documentAttachments.first : null;
      m.updatedAt = now; // 👈 آخر تعديل

      final box = Hive.box<Property>(boxName(kPropertiesBox));
      final removedLocalDocumentAttachments =
          _removedInitialLocalDocumentAttachments();
      await box.put(m.id, m);
      unawaited(OfflineSyncService.instance.enqueueUpsertProperty(m));
      await _deleteLocalDocumentAttachments(removedLocalDocumentAttachments);

      if (mounted) Navigator.of(context).pop(m);
    } else {
      // نستخدم نفس now الذي عرفناه فوق
      final nowId = now.microsecondsSinceEpoch.toString();
      _propertyDocCache[nowId] = _PropertyDocSnapshot(
        documentType: _documentType?.trim(),
        documentNumber: _documentNumber.text.trim(),
        documentDate:
            _documentDate == null ? null : KsaTime.dateOnly(_documentDate!),
        attachmentPaths: List<String>.from(_documentAttachments),
      );
      debugPrint('[property/save][new] id=$nowId');
      debugPrint('[property/save][new] documentType=${_documentType?.trim()}');
      debugPrint(
          '[property/save][new] documentNumber=${_documentNumber.text.trim()}');
      debugPrint(
          '[property/save][new] documentDate=${_documentDate == null ? 'null' : KsaTime.dateOnly(_documentDate!).toIso8601String()}');
      debugPrint(
          '[property/save][new] attachments=${_documentAttachments.length}');

      final p = Property(
        id: nowId, // ⬅️ معرّف مبني على الوقت
        name: _name.text.trim(),
        address: _address.text.trim(),
        type: _selectedType!,
        rentalMode: _selectedType == PropertyType.building ? _rentalMode : null,
        totalUnits: _selectedType == PropertyType.building ? parsedUnits : 0,
        occupiedUnits: 0,
        area: _area.text.trim().isEmpty
            ? null
            : double.tryParse(_area.text.trim()),
        floors: _floors.text.trim().isEmpty
            ? null
            : int.tryParse(_floors.text.trim()),
        rooms: _rooms.text.trim().isEmpty
            ? null
            : int.tryParse(_rooms.text.trim()),
        price: isPerUnit
            ? null
            : (_price.text.trim().isEmpty
                ? null
                : double.tryParse(_price.text.trim())),
        currency: _currency,
        description: mergedDesc,
        documentType: _documentType?.trim(),
        documentNumber: _documentNumber.text.trim(),
        documentDate:
            _documentDate == null ? null : KsaTime.dateOnly(_documentDate!),
        documentAttachmentPath:
            _documentAttachments.isNotEmpty ? _documentAttachments.first : null,
        documentAttachmentPaths: List<String>.from(_documentAttachments),

        // 👇 هنا الحل الجذري: تخزين تاريخ الإنشاء والتحديث
        createdAt: now,
        updatedAt: now,
      );

      final box = Hive.box<Property>(boxName(kPropertiesBox));
      await box.put(p.id, p);
      unawaited(OfflineSyncService.instance.enqueueUpsertProperty(p));

      if (mounted) Navigator.of(context).pop(p);
    }
  }

  Widget _rentalChoice({
    required RentalMode value,
    required RentalMode? group,
    required ValueChanged<RentalMode?>? onChanged,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: RadioListTile<RentalMode>(
        value: value,
        groupValue: group,
        onChanged: onChanged,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: Colors.white,
        selectedTileColor: Colors.white.withOpacity(0.08),
        title: Text(title,
            style: GoogleFonts.cairo(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            style: GoogleFonts.cairo(
                color: Colors.white70, fontSize: 12.sp, height: 1.4)),
      ),
    );
  }
}

IconData _propertyTypePickerIcon(PropertyType type) {
  switch (type) {
    case PropertyType.apartment:
      return Icons.apartment_rounded;
    case PropertyType.villa:
      return Icons.villa_rounded;
    case PropertyType.building:
      return Icons.business_rounded;
    case PropertyType.land:
      return Icons.terrain_rounded;
    case PropertyType.office:
      return Icons.business_center_rounded;
    case PropertyType.shop:
      return Icons.storefront_rounded;
    case PropertyType.warehouse:
      return Icons.warehouse_rounded;
  }
}

Widget _propertyTypePickerHandle() {
  return Container(
    width: 44.w,
    height: 5.h,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(999.r),
    ),
  );
}

Widget _propertyTypePickerHeader({
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

InputDecoration _propertyTypePickerSearchDecoration(String hintText) {
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
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white),
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );
}

class _PropertyTypePickerSheet extends StatefulWidget {
  final PropertyType? selectedType;

  const _PropertyTypePickerSheet({this.selectedType});

  @override
  State<_PropertyTypePickerSheet> createState() =>
      _PropertyTypePickerSheetState();
}

class _PropertyTypePickerSheetState extends State<_PropertyTypePickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rawSheetHeight = media.size.height * 0.68;
    final availableHeight =
        media.size.height - media.viewInsets.bottom - 12.h;
    final sheetHeight =
        availableHeight > 0 && availableHeight < rawSheetHeight
            ? availableHeight
            : rawSheetHeight;
    final query = _q.trim().toLowerCase();
    final items = PropertyType.values.where((type) {
      if (query.isEmpty) return true;
      return type.label.toLowerCase().contains(query);
    }).toList(growable: false);

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
                Center(child: _propertyTypePickerHandle()),
                SizedBox(height: 14.h),
                _propertyTypePickerHeader(
                  title: 'اختيار نوع العقار',
                  subtitle:
                      'اختر نوع العقار الذي تريد إضافته',
                ),
                SizedBox(height: 12.h),
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  style: GoogleFonts.cairo(color: Colors.white),
                  decoration: _propertyTypePickerSearchDecoration(
                    'ابحث باسم نوع العقار',
                  ),
                ),
                SizedBox(height: 10.h),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد أنواع مطابقة',
                            style: GoogleFonts.cairo(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Scrollbar(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: 6.h),
                            itemBuilder: (_, i) {
                              final type = items[i];
                              final isSelected = type == widget.selectedType;
                              return ListTile(
                                onTap: () => Navigator.of(context).pop(type),
                                leading: Icon(
                                  _propertyTypePickerIcon(type),
                                  color: Colors.white,
                                ),
                                title: Text(
                                  type.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF60A5FA),
                                      )
                                    : const Icon(
                                        Icons.chevron_left_rounded,
                                        color: Colors.white38,
                                      ),
                              );
                            },
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
}

/// ============================================================================
/// شاشة إضافة وحدات تابعة لعمارة
/// ============================================================================
/// ============================================================================
/// شاشة إضافة وحدات تابعة لعمارة (مع قيود الحقول)
/// ============================================================================
class AddUnitsScreen extends StatefulWidget {
  final Property building;
  final int existingUnitsCount;

  const AddUnitsScreen(
      {super.key, required this.building, this.existingUnitsCount = 0});

  @override
  State<AddUnitsScreen> createState() => _AddUnitsScreenState();
}

class _AddUnitsScreenState extends State<AddUnitsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Bottom nav + drawer ضبط
  final GlobalKey _bottomNavKey = GlobalKey();
  final double _bottomBarHeight = kBottomNavigationBarHeight;

  // تفاصيل الوحدة
  final _baseName = TextEditingController(text: 'شقة');

  // الحقول بقيود:
  final _rooms = TextEditingController(); // 0..20 (اختياري)
  final _baths = TextEditingController(); // 0..20 (اختياري)
  final _halls = TextEditingController(); // 0..10 (اختياري)
  final _aptFloorNo = TextEditingController(); // 0..100 (اختياري)
  final _area = TextEditingController(); // 1..100000 (اختياري)
  final _price = TextEditingController(); // 1..999,999,999 (اختياري)
  final _desc = TextEditingController(); // حتى 500 حرف

  bool? _furnished;
  String _currency = 'SAR';

  bool _bulk = false;

  final _bulkCount = TextEditingController();

  int _remaining() {
    final total = widget.building.totalUnits;
    final existing = widget.existingUnitsCount;
    if (total <= 0) return 0;
    final r = total - existing;
    return r < 0 ? 0 : r;
  }

  Iterable<Property> _existingBuildingUnits() {
    return Hive.box<Property>(boxName(kPropertiesBox))
        .values
        .where((e) => e.parentBuildingId == widget.building.id);
  }

  String _unitNamePrefix(String name) {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.replaceFirst(RegExp(r'[\s-]*\d+$'), '').trim();
  }

  String _buildAutoUnitName(String baseName, int number) {
    final prefix = _unitNamePrefix(baseName);
    return prefix.isEmpty ? number.toString() : '$prefix $number';
  }

  List<int> _nextAvailableUnitNumbers(String baseName, int count) {
    final prefix = _unitNamePrefix(baseName);
    final usedNumbers = <int>{};
    for (final unit in _existingBuildingUnits()) {
      if (_unitNamePrefix(unit.name) != prefix) continue;
      final n = _extractTrailingNumber(unit.name);
      if (n > 0) usedNumbers.add(n);
    }

    final explicitStart = _extractTrailingNumber(baseName);
    int candidate = explicitStart > 0 ? explicitStart : 1;
    final result = <int>[];
    while (result.length < count) {
      if (!usedNumbers.contains(candidate)) {
        result.add(candidate);
      }
      candidate += 1;
    }
    return result;
  }

  bool _shouldAutoNumberSingleUnit(String baseName) {
    final normalized = baseName.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _extractTrailingNumber(normalized) < 0 &&
        (normalized == 'شقة' || normalized == 'وحدة');
  }

  @override
  void initState() {
    super.initState();
    () async {
      await _openArchivedBox();
    }();
    _bulkCount.text = '1'; // العدد = 1 افتراضيًا عندما الإضافة ليست جماعية
  }

  @override
  void dispose() {
    _baseName.dispose();
    _rooms.dispose();
    _baths.dispose();
    _halls.dispose();
    _aptFloorNo.dispose();
    _area.dispose();
    _price.dispose();
    _desc.dispose();
    _bulkCount.dispose();
    super.dispose();
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  Widget _field({
    TextEditingController? controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final fmts = <TextInputFormatter>[];
    if (inputFormatters != null) fmts.addAll(inputFormatters);
    if (maxLength != null) {
      fmts.add(_limitWithFeedbackFormatter(
        max: maxLength,
        exceedMsg: 'تجاوزت الحد الأقصى ($maxLength)',
      ));
    }

    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: fmts,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: (ctx,
              {required int? currentLength,
              required bool? isFocused,
              required int? maxLength}) =>
          null,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        counterText: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    final remaining = _remaining();

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
          title: Text('إضافة وحدات',
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
                  ],
                ),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('العمارة: ${b.name}',
                            style: GoogleFonts.cairo(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(height: 10.h),

                      SwitchListTile(
                        value: _bulk,
                        onChanged: (v) => setState(() {
                          _bulk = v;
                          if (!v) {
                            _bulkCount.text =
                                '1'; // إذا ألغيت الإضافة الجماعية يرجّع 1 ويثبّته
                          }
                        }),
                        title: Text('إضافة كل الوحدات بنفس التفاصيل',
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          _bulk
                              ? 'سيتم إنشاء عدة شقق متتالية بنفس المواصفات.'
                              : 'ستتم إضافة شقة واحدة فقط بهذه المواصفات.',
                          style: GoogleFonts.cairo(
                              color: Colors.white70, fontSize: 12.sp),
                        ),
                        activeThumbColor: const Color(0xFF22C55E),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SizedBox(height: 8.h),

                      // اسم الوحدة — سطر مستقل
                      _field(
                        controller: _baseName,
                        label: 'الاسم أو رقم الوحدة',
                        maxLength: 25,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'هذا الحقل مطلوب'
                            : null,
                      ),
                      SizedBox(height: 12.h),

// عدد الوحدات — سطر مستقل تحت الاسم
                      TextFormField(
                        controller: _bulkCount,
                        enabled:
                            _bulk, // ✅ يتفعّل فقط عند تفعيل الإضافة الجماعية

                        keyboardType: TextInputType.number,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: GoogleFonts.cairo(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'عدد الوحدات',
                          labelStyle: GoogleFonts.cairo(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.15)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'هذا الحقل مطلوب';
                          final rem = remaining; // دالة remaining موجودة فوق
                          if (widget.building.totalUnits > 0 && n > rem) {
                            return 'يوجد $rem وحدات فقط';
                          }
                          return null;
                        },
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          final rem = remaining;
                          if (widget.building.totalUnits > 0 &&
                              n != null &&
                              n > rem) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('يوجد $rem وحدات فقط',
                                    style: GoogleFonts.cairo()),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                      ),
                      SizedBox(height: 12.h),

                      // الغرف: 0–20 (اختياري)
                      _field(
                        controller: _rooms,
                        label: 'عدد الغرف (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _maxIntWithFeedback(
                              max: 20, exceedMsg: 'الحد الأقصى هو 20'),
                        ],
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          if (n == null || n < 0) {
                            return 'أدخل رقمًا بين 0 و 20';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // حمامات/صالات: 0–20 و 0–10 (اختياري)
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _baths,
                              label: 'عدد الحمامات (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 20, exceedMsg: 'الحد الأقصى هو 20'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 0) {
                                  return 'أدخل رقمًا بين 0 و 20';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: _field(
                              controller: _halls,
                              label: 'عدد الصالات (اختياري) ',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 10, exceedMsg: 'الحد الأقصى هو 10'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 0) {
                                  return 'أدخل رقمًا بين 0 و 10';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // رقم الدور: 0–100 (اختياري)
                      _field(
                        controller: _aptFloorNo,
                        label: 'رقم الدور (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _maxIntWithFeedback(
                              max: 100, exceedMsg: 'الحد الأقصى هو 100'),
                        ],
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          if (n == null || n < 0) {
                            return 'أدخل رقمًا بين 0 و 100';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // حالة المفروشات
                      FormField<bool?>(
                        initialValue: _furnished,
                        validator: (_) =>
                            _furnished == null ? 'هذا الحقل مطلوب' : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('المفروشات:',
                                      style: GoogleFonts.cairo(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w700)),
                                  ChoiceChip(
                                    label: const Text('مفروشة'),
                                    selected: _furnished == true,
                                    onSelected: (_) {
                                      setState(() => _furnished = true);
                                      field.didChange(true);
                                    },
                                    showCheckmark: false,
                                    selectedColor: const Color(
                                        0xFF059669), // أخضر عند التحديد
                                    backgroundColor: const Color(
                                        0xFF1F2937), // ✅ لون افتراضي داكن بدل الأبيض
                                    labelStyle: GoogleFonts.cairo(
                                      color: _furnished == true
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('غير مفروشة'),
                                    selected: _furnished == false,
                                    onSelected: (_) {
                                      setState(() => _furnished = false);
                                      field.didChange(false);
                                    },
                                    showCheckmark: false,
                                    selectedColor: const Color(
                                        0xFF059669), // أخضر عند التحديد
                                    backgroundColor: const Color(
                                        0xFF1F2937), // ✅ لون افتراضي داكن بدل الأبيض
                                    labelStyle: GoogleFonts.cairo(
                                      color: _furnished == false
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (field.hasError)
                              Padding(
                                padding: EdgeInsets.only(top: 6.h),
                                child: Text(field.errorText!,
                                    style: GoogleFonts.cairo(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),

                      // المساحة: 1–100000 (اختياري، عشري)
                      _field(
                        controller: _area,
                        label: 'المساحة (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          _maxNumWithFeedback(
                              max: 100000,
                              exceedMsg: 'الحد الأقصى للمساحة هو 100000'),
                        ],
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = double.tryParse(t);
                          if (n == null || n < 1) {
                            return 'أدخل رقمًا بين 1 و 100000';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // سعر التأجير + العملة: 1–999,999,999 (اختياري، عشري)
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _price,
                              label: 'سعر التأجير (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                                _maxNumWithFeedback(
                                    max: 999999999,
                                    exceedMsg:
                                        'الحد الأقصى لسعر التأجير هو 999,999,999'),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = double.tryParse(t);
                                if (n == null || n < 1) {
                                  return 'أدخل رقمًا بين 1 و 999,999,999';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: _dd('العملة'),
                              dropdownColor: const Color(0xFF0F172A),
                              iconEnabledColor: Colors.white70,
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                              items: const ['SAR']
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c,
                                      child: const Text('ريال'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _currency = v ?? 'ريال'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // الوصف: حتى 500 حرف مع تنبيه أقصى حد
                      _field(
                        controller: _desc,
                        label: 'الوصف/ملاحظات (اختياري)',
                        maxLines: 3,
                        maxLength: 500,
                      ),
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
                          onPressed: _saveUnits,
                          icon: const Icon(Icons.save_rounded),
                          label: Text('حفظ الوحدات',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  void _saveUnits() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tsBase =
        KsaTime.now().microsecondsSinceEpoch; // بذرة زمنية واحدة لكل الدفعة
    final unitBaseName =
        _baseName.text.trim().isEmpty ? 'وحدة' : _baseName.text.trim();
    final count =
        _bulk ? int.parse(_bulkCount.text.trim()) : 1; // كم وحدة هننشئ؟
    final generatedNumbers = (_bulk || _shouldAutoNumberSingleUnit(unitBaseName))
        ? _nextAvailableUnitNumbers(unitBaseName, count)
        : const <int>[];

    final createdAt = KsaTime.now(); // 👈 وقت إنشاء هذه الوحدات

    final rooms =
        _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim());
    final baths =
        _baths.text.trim().isEmpty ? null : int.tryParse(_baths.text.trim());
    final halls =
        _halls.text.trim().isEmpty ? null : int.tryParse(_halls.text.trim());
    final aptFloor = _aptFloorNo.text.trim().isEmpty
        ? null
        : int.tryParse(_aptFloorNo.text.trim());
    final furnished = _furnished;

    final area =
        _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim());
    final price =
        _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
    final descFree = _desc.text.trim().isEmpty ? null : _desc.text.trim();

    final specDesc = _buildSpec(
      baths: baths,
      halls: halls,
      floorNo: aptFloor,
      furnished: furnished,
      extraDesc: descFree,
    );
    final List<Property> created = [];

    final remaining = _remaining();
    if (_bulk && widget.building.totalUnits > 0) {
      final requested = int.tryParse(_bulkCount.text.trim()) ?? 0;
      if (requested <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('أدخل عدد وحدات صحيح', style: GoogleFonts.cairo())),
        );
        return;
      }
      if (requested > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('لا يمكن إضافة أكثر من $remaining وحدة',
                  style: GoogleFonts.cairo())),
        );
        return;
      }
    }

    if (_bulk) {
      final count = int.tryParse(_bulkCount.text.trim()) ?? 0;
      for (int i = 0; i < count; i++) {
        created.add(
          Property(
            name: _buildAutoUnitName(unitBaseName, generatedNumbers[i]),
            type: PropertyType.apartment,
            address: widget.building.address,
            rooms: rooms,
            area: area,
            price: price,
            currency: _currency,
            rentalMode: null,
            totalUnits: 0,
            occupiedUnits: 0,
            parentBuildingId: widget.building.id,
            description: specDesc,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
      }
    } else {
      created.add(
        Property(
          name: _shouldAutoNumberSingleUnit(unitBaseName)
              ? _buildAutoUnitName(unitBaseName, generatedNumbers.first)
              : unitBaseName,
          type: PropertyType.apartment,
          address: widget.building.address,
          rooms: rooms,
          area: area,
          price: price,
          currency: _currency,
          rentalMode: null,
          totalUnits: 0,
          occupiedUnits: 0,
          parentBuildingId: widget.building.id,
          description: specDesc,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
    }

    Navigator.of(context).pop(created);
  }
}

/// ============================================================================
/// تعديل وحدة (نفس حقول إضافة الوحدات)
/// ============================================================================
class EditUnitScreen extends StatefulWidget {
  final Property unit;
  const EditUnitScreen({super.key, required this.unit});

  @override
  State<EditUnitScreen> createState() => _EditUnitScreenState();
}

class _EditUnitScreenState extends State<EditUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  final _name = TextEditingController();
  final _rooms = TextEditingController();
  final _baths = TextEditingController();
  final _halls = TextEditingController();
  final _aptFloorNo = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  bool? _furnished;
  String _currency = 'SAR';

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    final spec = _parseSpec(u.description);
    _name.text = u.name;
    _rooms.text = u.rooms?.toString() ?? '';
    _baths.text = spec['حمامات'] ?? '';
    _halls.text = spec['صالات'] ?? '';
    _aptFloorNo.text = spec['الدور'] ?? '';
    _furnished = _parseFurnishedSpecValue(spec['المفروشات']);
    _area.text = u.area?.toString() ?? '';
    _price.text = u.price?.toString() ?? '';
    _currency = u.currency;
    _desc.text = _extractFreeDesc(u.description);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _rooms.dispose();
    _baths.dispose();
    _halls.dispose();
    _aptFloorNo.dispose();
    _area.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final fmts = <TextInputFormatter>[];
    if (inputFormatters != null) fmts.addAll(inputFormatters);
    if (maxLength != null) {
      fmts.add(_limitWithFeedbackFormatter(
        max: maxLength,
        exceedMsg: 'تجاوزت الحد الأقصى ($maxLength)',
      ));
    }
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: fmts,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: (ctx,
              {required int? currentLength,
              required bool? isFocused,
              required int? maxLength}) =>
          null,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        counterText: '',
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final u = widget.unit;

    final baths =
        _baths.text.trim().isEmpty ? null : int.tryParse(_baths.text.trim());
    final halls =
        _halls.text.trim().isEmpty ? null : int.tryParse(_halls.text.trim());
    final floorNo = _aptFloorNo.text.trim().isEmpty
        ? null
        : int.tryParse(_aptFloorNo.text.trim());
    final desc = _buildSpec(
      baths: baths,
      halls: halls,
      floorNo: floorNo,
      furnished: _furnished,
      extraDesc: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
    );

    u.name = _name.text.trim();
    u.rooms =
        _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim());
    u.area =
        _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim());
    u.price =
        _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
    u.currency = _currency;
    u.description = desc;
    u.updatedAt = KsaTime.now();

    await Hive.box<Property>(boxName(kPropertiesBox)).put(u.id, u);
    if (!mounted) return;
    Navigator.of(context).pop(u);
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text('تعديل الوحدة',
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
                  ],
                ),
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
                      _field(
                        controller: _name,
                        label: 'الاسم أو رقم الوحدة',
                        maxLength: 25,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'هذا الحقل مطلوب'
                            : null,
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _rooms,
                        label: 'عدد الغرف (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _maxIntWithFeedback(
                              max: 20, exceedMsg: 'الحد الأقصى هو 20'),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _baths,
                              label: 'عدد الحمامات (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 20, exceedMsg: 'الحد الأقصى هو 20'),
                              ],
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: _field(
                              controller: _halls,
                              label: 'عدد الصالات (اختياري) ',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _maxIntWithFeedback(
                                    max: 10, exceedMsg: 'الحد الأقصى هو 10'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _aptFloorNo,
                        label: 'رقم الدور (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _maxIntWithFeedback(
                              max: 100, exceedMsg: 'الحد الأقصى هو 100'),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      FormField<bool?>(
                        initialValue: _furnished,
                        validator: (_) =>
                            _furnished == null ? 'هذا الحقل مطلوب' : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                children: [
                                  Text('المفروشات:',
                                      style: GoogleFonts.cairo(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w700)),
                                  ChoiceChip(
                                    label: const Text('مفروشة'),
                                    selected: _furnished == true,
                                    onSelected: (_) {
                                      setState(() => _furnished = true);
                                      field.didChange(true);
                                    },
                                    showCheckmark: false,
                                    selectedColor: const Color(0xFF059669),
                                    backgroundColor: const Color(0xFF1F2937),
                                    labelStyle: GoogleFonts.cairo(
                                      color: _furnished == true
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('غير مفروشة'),
                                    selected: _furnished == false,
                                    onSelected: (_) {
                                      setState(() => _furnished = false);
                                      field.didChange(false);
                                    },
                                    showCheckmark: false,
                                    selectedColor: const Color(0xFF059669),
                                    backgroundColor: const Color(0xFF1F2937),
                                    labelStyle: GoogleFonts.cairo(
                                      color: _furnished == false
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (field.hasError)
                              Padding(
                                padding: EdgeInsets.only(top: 6.h),
                                child: Text(field.errorText!,
                                    style: GoogleFonts.cairo(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _area,
                        label: 'المساحة (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          _maxNumWithFeedback(
                              max: 100000,
                              exceedMsg: 'الحد الأقصى للمساحة هو 100000'),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _price,
                              label: 'سعر التأجير (اختياري)',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                                _maxNumWithFeedback(
                                    max: 999999999,
                                    exceedMsg:
                                        'الحد الأقصى لسعر التأجير هو 999,999,999'),
                              ],
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: _dd('العملة'),
                              dropdownColor: const Color(0xFF0F172A),
                              iconEnabledColor: Colors.white70,
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                              items: const ['SAR']
                                  .map((c) => DropdownMenuItem<String>(
                                        value: c,
                                        child: const Text('ريال'),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _currency = v ?? 'SAR'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _desc,
                        label: 'الوصف/ملاحظات (اختياري)',
                        maxLines: 3,
                        maxLength: 500,
                      ),
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
                          label: Text('حفظ التعديلات',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }
}

/// ============================================================================
/// عناصر تصميم غامقة مشتركة
/// ============================================================================
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

// امتداد صغير للـ Iterable لتفادي الأخطاء عند عدم وجود عنصر
extension on Iterable<Property?> {
  Property? get firstOrNull => isEmpty ? null : first;
}
