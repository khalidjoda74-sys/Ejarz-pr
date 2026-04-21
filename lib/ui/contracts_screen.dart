// lib/ui/contracts_screen.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'invoices_screen.dart' show Invoice, kInvoicesBox;
import '../data/services/comprehensive_reports_service.dart';
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart'; // أو المسار الصحيح حسب مكان الملف
import '../data/services/pdf_export_service.dart';
import '../widgets/darvoo_app_bar.dart';
import '../widgets/custom_confirm_dialog.dart';

import '../models/tenant.dart';
import '../models/property.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// استيرادات للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui
    show TenantsScreen, TenantDetailsScreen;

/// عناصر الواجهة المشتركة (مطابقة لما استُخدم في شاشة المستأجرين)
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/entity_audit_info_button.dart';

// ✅ مولِّد رقم سند لحظة الإنشاء (يعتمد على أكبر رقم فعلي غير ملغى في نفس السنة)
// مولّد رقم سند لعقود الإيجار، يعتمد فقط على أعلى رقم غير ملغى في نفس السنة
String _nextInvoiceSerialForContracts(Box<Invoice> invoices) {
  // استخدم SaTimeLite أو KsaTime بحسب ما هو متوفر عندك
  final int year = SaTimeLite.now().year;

  int maxSeq = 0;
  for (final inv in invoices.values) {
    // 🚫 تم إزالة التخطي (continue) للسندات الملغاة لضمان عدم تكرار رقم السند أبدًا
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

String _invoiceNoteLower(Invoice inv) =>
    (inv.note ?? '').toString().trim().toLowerCase();

bool _isOfficeCommissionInvoice(Invoice inv) {
  final note = _invoiceNoteLower(inv);
  return note.contains('[office_commission]');
}

bool _isAdvanceContractInvoice(Contract c, Invoice inv) {
  if (c.advanceMode != AdvanceMode.deductFromTotal) return false;
  final note = (inv.note ?? '').toString();
  return note.contains('سداد مقدم عقد');
}

bool _isPaidRentInvoiceForContract(Contract c, Invoice inv) {
  if (inv.contractId != c.id) return false;
  if (inv.isCanceled == true) return false;
  if (inv.paidAmount + 0.000001 < inv.amount.abs()) return false;
  if (_isOfficeCommissionInvoice(inv)) return false;
  if (_isAdvanceContractInvoice(c, inv)) return false;
  return true;
}

bool _dailyAlreadyPaid(Contract c) {
  if (c.term != ContractTerm.daily) return false;
  try {
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));
    // أي سند لنفس العقد، غير ملغاة، ومدفوعة بالكامل
    return box.values.any((inv) => _isPaidRentInvoiceForContract(c, inv));
  } catch (_) {
    return false;
  }
}

void showSnackSafe(BuildContext ctx, String message) {
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  if (messenger == null || !messenger.mounted) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(message)),
  );
}

Future<void> _showArchiveNoticeDialog(
  BuildContext context, {
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Directionality(
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
                    onPressed: () => Navigator.pop(context),
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

const String _kContractsEjarNoBox = 'contractsEjarNoMap';

Future<void> _saveEjarNoLocal(String contractId, String? ejarNo) async {
  final id = contractId.trim();
  if (id.isEmpty) return;
  final boxId = boxName(_kContractsEjarNoBox);
  if (!Hive.isBoxOpen(boxId)) {
    await Hive.openBox<String>(boxId);
  }
  final box = Hive.box<String>(boxId);
  final v = (ejarNo ?? '').trim();
  if (v.isEmpty) {
    await box.delete(id);
  } else {
    await box.put(id, v);
  }
}

String _readEjarNoLocal(String contractId) {
  final id = contractId.trim();
  if (id.isEmpty) return '';
  final boxId = boxName(_kContractsEjarNoBox);
  if (!Hive.isBoxOpen(boxId)) return '';
  final v = Hive.box<String>(boxId).get(id);
  return (v ?? '').trim();
}

String _composeContractVoucherPropertyReference({
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

String _contractVoucherPropertyReference({
  Property? property,
  Property? building,
}) {
  final unitName = (property?.name ?? '').trim();
  final buildingName = (building?.name ?? '').trim();
  return _composeContractVoucherPropertyReference(
    unitName: unitName,
    buildingName: buildingName,
  );
}

String _buildContractRentVoucherNote({
  required String ejarNo,
  required String propertyRef,
  required double waterAmount,
  required String commissionMode,
  required double commissionValue,
  required double commissionAmount,
}) {
  final normalizedEjarNo = ejarNo.trim();
  final normalizedPropertyRef = propertyRef.trim();
  var firstLine = normalizedEjarNo.isNotEmpty
      ? 'سداد قيمة إيجار عقد رقم $normalizedEjarNo'
      : 'سداد قيمة إيجار';
  if (normalizedPropertyRef.isNotEmpty) {
    firstLine = '$firstLine • $normalizedPropertyRef';
  }
  final lines = <String>[firstLine];
  if (waterAmount > 0) {
    lines.add('مياه (قسط): ${_fmtMoneyTrunc(waterAmount)}');
  }
  if (commissionMode.trim().isNotEmpty) {
    lines.add('[COMMISSION_MODE: ${commissionMode.trim()}]');
  }
  if (commissionValue > 0) {
    lines.add('[COMMISSION_VALUE: ${commissionValue.toStringAsFixed(6)}]');
  }
  if (commissionMode.trim() == 'percent' && commissionAmount > 0) {
    lines.add('[COMMISSION_AMOUNT: ${commissionAmount.toStringAsFixed(6)}]');
  }
  return lines.join('\n').trim();
}

double _commissionConfigNumber(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0.0;
  return 0.0;
}

Future<({String mode, double value, double amount})>
    _loadGlobalCommissionSnapshotForVoucher(double baseAmount) async {
  final financeBoxName = boxName('financeConfigBox');
  final box = Hive.isBoxOpen(financeBoxName)
      ? Hive.box(financeBoxName)
      : await Hive.openBox(financeBoxName);
  final raw = box.get('commission::global');
  if (raw is! Map) {
    return (mode: '', value: 0.0, amount: 0.0);
  }
  final mode = (raw['mode'] ?? '').toString().trim();
  final value = _commissionConfigNumber(raw['value']);
  final base = baseAmount.abs();
  if (mode != 'percent' || value <= 0 || base <= 0) {
    return (mode: mode, value: value, amount: 0.0);
  }
  final amount = ((base * value) / 100).clamp(0, base).toDouble();
  return (mode: mode, value: value, amount: amount);
}

Future<({String mode, double value, double amount})>
    _loadCommissionSnapshotForContractVoucher(
  Contract contract,
  double baseAmount,
) async {
  if (contract.term == ContractTerm.daily) {
    return (mode: '', value: 0.0, amount: 0.0);
  }
  return _loadGlobalCommissionSnapshotForVoucher(baseAmount);
}

Future<void> _syncOfficeCommissionForContractVoucher(String invoiceId) async {
  final id = invoiceId.trim();
  if (id.isEmpty) return;
  try {
    await ComprehensiveReportsService.syncOfficeCommissionVouchers(
      contractVoucherId: id,
    );
  } catch (e, st) {
    debugPrint('Failed to sync office commission voucher for $id: $e');
    debugPrintStack(stackTrace: st);
  }
}

String _appendCommissionSnapshotToNote(
  String baseNote, {
  required String commissionMode,
  required double commissionValue,
  required double commissionAmount,
}) {
  final lines = <String>[baseNote.trim()];
  if (commissionMode.trim().isNotEmpty) {
    lines.add('[COMMISSION_MODE: ${commissionMode.trim()}]');
  }
  if (commissionValue > 0) {
    lines.add('[COMMISSION_VALUE: ${commissionValue.toStringAsFixed(6)}]');
  }
  if (commissionMode.trim() == 'percent' && commissionAmount > 0) {
    lines.add('[COMMISSION_AMOUNT: ${commissionAmount.toStringAsFixed(6)}]');
  }
  return lines.where((line) => line.trim().isNotEmpty).join('\n').trim();
}

Future<void> _resetPeriodicServicesForProperty(String propertyId) async {
  if (propertyId.trim().isEmpty) return;
  final box = await openServicesConfigBox();
  const services = ['water', 'cleaning', 'elevator', 'internet', 'electricity'];
  final activeContract =
      _activeContractForPropertyGlobal(propertyId, excludeContractId: null);
  for (final service in services) {
    final key = '$propertyId::$service';
    final raw = box.get(key);
    final cfg =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final normalized =
        normalizePeriodicServiceConfigForNoActiveContract(service, cfg);
    if (normalized.isNotEmpty) {
      await box.put(key, normalized);
      if (service == 'water' && activeContract != null) {
        await linkWaterConfigToContractIfNeeded(activeContract);
      }
      continue;
    }
    await box.put(key, <String, dynamic>{});
  }
}

// ================== WhatsApp helpers (top-level) ==================
Map<String, dynamic>? _asMap(dynamic o) {
  if (o == null) return null;
  if (o is Map<String, dynamic>) return o;
  try {
    final j = (o as dynamic).toJson();
    if (j is Map<String, dynamic>) return j;
  } catch (_) {}
  try {
    final m = (o as dynamic).toMap();
    if (m is Map<String, dynamic>) return m;
  } catch (_) {}
  return null;
}

// اسم المستأجر من أي مصدر محتمل (Tenant/Contract/Maps)
// اسم المستأجر من أي مصدر محتمل (Object-first ثم Maps)
String _tenantNameUniversal({
  Tenant? tenantObj,
  Contract? contractObj,
  Map<String, dynamic>? tenantMap,
  Map<String, dynamic>? contractMap,
}) {
  String? nz(String? s) => (s != null && s.trim().isNotEmpty) ? s.trim() : null;

  // 1) أولاً: من كائن Tenant نفسه (مثل زر الدفعات)
  try {
    final dyn = tenantObj as dynamic;
    final direct = nz(dyn.fullName) ?? // كثير من الأزرار تستخدمه
        nz(dyn.name) ??
        nz(dyn.label);
    if (direct != null) return direct;

    final f = nz(dyn.firstName) ?? nz(dyn.givenName);
    final l = nz(dyn.lastName) ?? nz(dyn.familyName) ?? nz(dyn.surname);
    if (f != null && l != null) return '$f $l';
    if (f != null) return f;
  } catch (_) {
    // تجاهل أي أخطاء ديناميكية
  }

  // 2) ثانياً: من الخرائط (toJson/toMap أو سنابات محفوظة)
  String? pick(Map<String, dynamic>? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    for (final e in m.entries) {
      final val = e.value;
      if (val is Map<String, dynamic>) {
        final vv = val[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }
    }
    return null;
  }

  String? firstNonEmpty(List<String?> xs) {
    for (final x in xs) {
      if (x != null && x.trim().isNotEmpty) return x.trim();
    }
    return null;
  }

  final tm = tenantMap ?? _asMap(tenantObj);
  final cm = contractMap ?? _asMap(contractObj);

  final fromMaps = firstNonEmpty([
    pick(tm, 'fullName'),
    pick(tm, 'displayName'),
    pick(tm, 'name'),
    pick(tm, 'arabicName'),
    pick(tm, 'enName'),
    pick(tm, 'label'),
    pick(tm, 'tenantName'),
    pick(tm, 'title'),
    pick(tm, 'payerName'),
    pick(tm, 'customerName'),
    pick(tm, 'clientName'),
    pick(cm, 'tenantName'),
    pick(cm, 'tenant_label'),
  ]);
  if (fromMaps != null) return fromMaps;

  final f = firstNonEmpty([
    pick(tm, 'firstName'),
    pick(tm, 'first_name'),
    pick(tm, 'givenName'),
    pick(tm, 'given_name'),
  ]);
  final l = firstNonEmpty([
    pick(tm, 'lastName'),
    pick(tm, 'last_name'),
    pick(tm, 'familyName'),
    pick(tm, 'family_name'),
    pick(tm, 'surname'),
  ]);
  if (f != null && l != null) return '$f $l';
  if (f != null) return f;

  // 3) افتراضي
  return 'المستأجر الكريم';
}

// نص رسالة واتساب للعقد (near / overdue) بدون رقم عقد وبدون مبالغ
String _waMessageContract({
  required Contract c,
  required DateTime due,
  required String kind, // 'near' | 'overdue'
  Tenant? tenantObj,
  Map<String, dynamic>? tenantMap,
  Map<String, dynamic>? propertyMap,
}) {
  String fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  String? pick(Map<String, dynamic>? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    for (final e in m.entries) {
      final ev = e.value;
      if (ev is Map<String, dynamic>) {
        final vv = ev[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }
    }
    return null;
  }

  String propertyLabel(Map<String, dynamic>? pm) {
    return pick(pm, 'displayName') ??
        pick(pm, 'name') ??
        pick(pm, 'title') ??
        pick(pm, 'label') ??
        pick(pm, 'arabicName') ??
        pick(pm, 'enName') ??
        '';
  }

  final name = _tenantNameUniversal(
    tenantObj: tenantObj,
    contractObj: c,
    tenantMap: tenantMap,
    contractMap: _asMap(c),
  );

  final prop = propertyLabel(propertyMap);
  final propPart = prop.isNotEmpty ? ' لعقار $prop' : '';
  final dateStr = fmtDate(due);

  if (kind == 'near') {
    return 'عزيزي المستأجر $name، نود تنبيهك بأن عقد إيجارك$propPart يقترب من الانتهاء بتاريخ $dateStr. '
        'نرجو التواصل بشأن التجديد أو ترتيبات التسليم.';
  } else {
    return 'عزيزي المستأجر $name، نلفت انتباهك إلى أن عقد إيجارك$propPart انتهى بتاريخ $dateStr. '
        'يرجى التنسيق فورًا بخصوص التجديد أو تسليم العقار.';
  }
}

/// ============================================================================
/// SaTimeLite: وقت السعودية (قراءة الإزاحة من sessionBox إن وُجدت)
/// ضع الإزاحة بالملي ثانية في sessionBox['saOffsetMs'] عبر دالة السحابة.
/// ============================================================================
class SaTimeLite {
  static int _offsetMsCache = 0;
  static bool _loaded = false;

  static int _readOffsetMs() {
    if (!Hive.isBoxOpen('sessionBox')) return 0;
    try {
      final box = Hive.box('sessionBox');
      final v = box.get('saOffsetMs') ?? box.get('saTimeOffsetMs') ?? 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
    } catch (_) {}
    return 0;
  }

  static DateTime now() {
    if (!_loaded) {
      _offsetMsCache = _readOffsetMs();
      _loaded = true;
    }
    return KsaTime.now().add(Duration(milliseconds: _offsetMsCache));
  }

  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }
}

/// =================================================================================
/// أدوات مساعدة
/// =================================================================================

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

const String kDailyContractEndHourField = 'daily_contract_end_hour';

int? _normalizeDailyCheckoutHour(dynamic value) {
  if (value == null) return null;
  final int? parsed = switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v.trim()),
    _ => null,
  };
  if (parsed == null || parsed < 0 || parsed > 23) return null;
  return parsed;
}

int _resolvedDailyCheckoutHour(int? hour) {
  final direct = _normalizeDailyCheckoutHour(hour);
  if (direct != null) return direct;
  try {
    if (Hive.isBoxOpen('sessionBox')) {
      final fallback = _normalizeDailyCheckoutHour(
        Hive.box('sessionBox').get(kDailyContractEndHourField),
      );
      if (fallback != null) return fallback;
    }
  } catch (_) {}
  return 12;
}

int _dailyContractDays(DateTime start, DateTime end) {
  final diff = _dateOnly(end).difference(_dateOnly(start)).inDays;
  return diff < 0 ? 0 : diff;
}

String _formatHourAmPm(int hour24) {
  final normalized = hour24.clamp(0, 23);
  final hour12 = normalized % 12 == 0 ? 12 : normalized % 12;
  final period = normalized >= 12 ? 'PM' : 'AM';
  return '$hour12:00 $period';
}

class Contract extends HiveObject {
  String id;
  String? serialNo; // رقم العقد التسلسلي مثل 2025-1
  String? ejarContractNo; // رقم العقد بمنصة إيجار

  // الربط
  String tenantId;
  String propertyId;
  Map<String, dynamic>? tenantSnapshot;
  Map<String, dynamic>? propertySnapshot;
  Map<String, dynamic>? buildingSnapshot;

  // معلومات أساسية
  DateTime startDate;
  DateTime endDate;

  /// ملاحظة مهمة:
  /// - في العقود غير اليومية: rentAmount = قيمة القسط لكل قسط سداد، و totalAmount = إجمالي العقد.
  /// - في العقود اليومية: rentAmount = totalAmount = إجمالي العقد (دفعة واحدة).
  double rentAmount;
  String currency; // مثل SAR

  // فترة العقد
  ContractTerm term;
  int termYears;

  // دورة السداد (تُخفى في "يومي")
  PaymentCycle paymentCycle;
  int paymentCycleYears;

  // إجمالي العقد
  double totalAmount;

  // الدفعة المقدمة
  double? advancePaid;
  AdvanceMode advanceMode;

  // لليومي: ساعة الخروج (0..23) اختيارية
  int? dailyCheckoutHour;

  // الحالة
  bool isTerminated; // إنهاء مبكر
  DateTime? terminatedAt;

  // وصف/ملاحظات
  String? notes;
  List<String> attachmentPaths;

  // تتبع
  DateTime createdAt;
  DateTime updatedAt;

  // الأرشفة (جديد)
  bool isArchived;

  Contract({
    String? id,
    this.serialNo,
    this.ejarContractNo,
    required this.tenantId,
    required this.propertyId,
    this.tenantSnapshot,
    this.propertySnapshot,
    this.buildingSnapshot,
    required this.startDate,
    required this.endDate,
    required this.rentAmount,
    required this.totalAmount,
    this.currency = 'SAR',
    this.term = ContractTerm.monthly,
    this.termYears = 1,
    this.paymentCycle = PaymentCycle.monthly,
    this.paymentCycleYears = 1,
    this.advancePaid,
    this.advanceMode = AdvanceMode.none,
    this.dailyCheckoutHour,
    this.notes,
    List<String>? attachmentPaths,
    this.isTerminated = false,
    this.terminatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isArchived = false,
  })  : attachmentPaths = attachmentPaths ?? <String>[],
        id = id ?? KsaTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? SaTimeLite.now(),
        updatedAt = updatedAt ?? SaTimeLite.now();

// داخل class Contract
  int get resolvedDailyCheckoutHour => _resolvedDailyCheckoutHour(
        dailyCheckoutHour,
      );

  DateTime get dailyStartBoundary => DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        resolvedDailyCheckoutHour,
      );

  DateTime get dailyEndBoundary => DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        resolvedDailyCheckoutHour,
      );

  bool get isActiveNow {
    if (isTerminated) return false;

    final now = SaTimeLite.now();

    // 🟡 تخصيص "اليومي": نشط حتى 12:00 ظهرًا من يوم endDate
    if (term == ContractTerm.daily) {
      return !now.isBefore(dailyStartBoundary) && now.isBefore(dailyEndBoundary);
    }

    // باقي الأنواع: يبقى العقد ساريًا طوال يوم endDate نفسه.
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  bool get isExpiredByTime {
    // يعتبر منتهيًا بعد مرور يوم endDate كاملًا لغير اليومي
    final n = SaTimeLite.now();
    if (term == ContractTerm.daily) {
      return !isTerminated && !n.isBefore(dailyEndBoundary);
    }
    final today = DateTime(n.year, n.month, n.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !isTerminated && today.isAfter(end);
  }
}

Map<String, dynamic>? _snapshotMapOrNull(dynamic raw) {
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

void _putSnapshotValue(Map<String, dynamic> target, String key, dynamic value) {
  if (value == null) return;
  if (value is String && value.trim().isEmpty) return;
  target[key] = value;
}

void _putSnapshotDate(
    Map<String, dynamic> target, String key, DateTime? value) {
  if (value == null) return;
  target[key] = value.millisecondsSinceEpoch;
}

void _putSnapshotList(
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

bool _snapshotHasValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

dynamic _cloneSnapshotValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List) return List<dynamic>.from(value);
  return value;
}

String _snapshotClientTypeLabel(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value == 'company' ||
      value == 'مستأجر (شركة)' ||
      value == 'شركة') {
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

Map<String, dynamic> _buildTenantSnapshot(Tenant tenant) {
  final map = <String, dynamic>{};
  _putSnapshotValue(map, 'id', tenant.id);
  _putSnapshotValue(map, 'fullName', tenant.fullName);
  _putSnapshotValue(map, 'nationalId', tenant.nationalId);
  _putSnapshotValue(map, 'phone', tenant.phone);
  _putSnapshotValue(map, 'email', tenant.email);
  _putSnapshotDate(map, 'dateOfBirth', tenant.dateOfBirth);
  _putSnapshotValue(map, 'nationality', tenant.nationality);
  _putSnapshotDate(map, 'idExpiry', tenant.idExpiry);
  _putSnapshotValue(map, 'addressLine', tenant.addressLine);
  _putSnapshotValue(map, 'city', tenant.city);
  _putSnapshotValue(map, 'region', tenant.region);
  _putSnapshotValue(map, 'postalCode', tenant.postalCode);
  _putSnapshotValue(map, 'emergencyName', tenant.emergencyName);
  _putSnapshotValue(map, 'emergencyPhone', tenant.emergencyPhone);
  _putSnapshotValue(map, 'notes', tenant.notes);
  _putSnapshotValue(map, 'clientType', tenant.clientType);
  _putSnapshotValue(
      map, 'clientTypeLabel', _snapshotClientTypeLabel(tenant.clientType));
  _putSnapshotValue(map, 'tenantBankName', tenant.tenantBankName);
  _putSnapshotValue(
      map, 'tenantBankAccountNumber', tenant.tenantBankAccountNumber);
  _putSnapshotValue(map, 'tenantTaxNumber', tenant.tenantTaxNumber);
  _putSnapshotValue(map, 'companyName', tenant.companyName);
  _putSnapshotValue(
      map, 'companyCommercialRegister', tenant.companyCommercialRegister);
  _putSnapshotValue(map, 'companyTaxNumber', tenant.companyTaxNumber);
  _putSnapshotValue(
      map, 'companyRepresentativeName', tenant.companyRepresentativeName);
  _putSnapshotValue(
      map, 'companyRepresentativePhone', tenant.companyRepresentativePhone);
  _putSnapshotValue(
      map, 'companyBankAccountNumber', tenant.companyBankAccountNumber);
  _putSnapshotValue(map, 'companyBankName', tenant.companyBankName);
  _putSnapshotValue(map, 'serviceSpecialization', tenant.serviceSpecialization);
  _putSnapshotList(map, 'tags', tenant.tags);
  _putSnapshotList(map, 'attachmentPaths', tenant.attachmentPaths);
  _putSnapshotValue(map, 'isArchived', tenant.isArchived);
  _putSnapshotValue(map, 'isBlacklisted', tenant.isBlacklisted);
  _putSnapshotValue(map, 'blacklistReason', tenant.blacklistReason);
  _putSnapshotValue(map, 'activeContractsCount', tenant.activeContractsCount);
  _putSnapshotDate(map, 'createdAt', tenant.createdAt);
  _putSnapshotDate(map, 'updatedAt', tenant.updatedAt);
  return map;
}

Map<String, dynamic> _buildPropertySnapshot(Property property) {
  final map = <String, dynamic>{};
  final documentPaths = <String>{
    ...?property.documentAttachmentPaths,
    if ((property.documentAttachmentPath ?? '').trim().isNotEmpty)
      property.documentAttachmentPath!.trim(),
  }.toList();
  _putSnapshotValue(map, 'id', property.id);
  _putSnapshotValue(map, 'name', property.name);
  _putSnapshotValue(map, 'type', property.type.name);
  _putSnapshotValue(map, 'typeLabel', property.type.label);
  _putSnapshotValue(map, 'address', property.address);
  _putSnapshotValue(map, 'price', property.price);
  _putSnapshotValue(map, 'currency', property.currency);
  _putSnapshotValue(map, 'rooms', property.rooms);
  _putSnapshotValue(map, 'area', property.area);
  _putSnapshotValue(map, 'floors', property.floors);
  _putSnapshotValue(map, 'totalUnits', property.totalUnits);
  _putSnapshotValue(map, 'occupiedUnits', property.occupiedUnits);
  _putSnapshotValue(map, 'rentalMode', property.rentalMode?.name);
  _putSnapshotValue(map, 'rentalModeLabel', property.rentalMode?.label);
  _putSnapshotValue(map, 'parentBuildingId', property.parentBuildingId);
  _putSnapshotValue(map, 'description', property.description);
  _putSnapshotValue(map, 'documentType', property.documentType);
  _putSnapshotValue(map, 'documentNumber', property.documentNumber);
  _putSnapshotDate(map, 'documentDate', property.documentDate);
  _putSnapshotValue(map, 'electricityNumber', property.electricityNumber);
  _putSnapshotValue(map, 'electricityMode', property.electricityMode);
  _putSnapshotValue(map, 'electricityShare', property.electricityShare);
  _putSnapshotValue(map, 'waterNumber', property.waterNumber);
  _putSnapshotValue(map, 'waterMode', property.waterMode);
  _putSnapshotValue(map, 'waterShare', property.waterShare);
  _putSnapshotValue(map, 'waterAmount', property.waterAmount);
  _putSnapshotValue(map, 'isArchived', property.isArchived);
  _putSnapshotDate(map, 'createdAt', property.createdAt);
  _putSnapshotDate(map, 'updatedAt', property.updatedAt);
  _putSnapshotList(map, 'documentAttachmentPaths', documentPaths);
  return map;
}

bool _storeContractSnapshotField({
  required Map<String, dynamic>? current,
  required Map<String, dynamic>? next,
  required bool overwrite,
  required void Function(Map<String, dynamic> value) assign,
}) {
  if (next == null || next.isEmpty) return false;
  final existing = _snapshotMapOrNull(current);
  if (!overwrite && existing != null && existing.isNotEmpty) {
    final merged = Map<String, dynamic>.from(existing);
    var changed = false;
    next.forEach((key, value) {
      if (!_snapshotHasValue(merged[key]) && _snapshotHasValue(value)) {
        merged[key] = _cloneSnapshotValue(value);
        changed = true;
      }
    });
    if (!changed || mapEquals(existing, merged)) return false;
    assign(merged);
    return true;
  }
  if (existing != null && mapEquals(existing, next)) return false;
  assign(Map<String, dynamic>.from(next));
  return true;
}

bool _applyContractSnapshots(
  Contract contract, {
  Tenant? tenant,
  Property? property,
  Property? building,
  bool overwrite = false,
}) {
  var changed = false;
  if (_storeContractSnapshotField(
    current: contract.tenantSnapshot,
    next: tenant == null ? null : _buildTenantSnapshot(tenant),
    overwrite: overwrite,
    assign: (value) => contract.tenantSnapshot = value,
  )) {
    changed = true;
  }
  if (_storeContractSnapshotField(
    current: contract.propertySnapshot,
    next: property == null ? null : _buildPropertySnapshot(property),
    overwrite: overwrite,
    assign: (value) => contract.propertySnapshot = value,
  )) {
    changed = true;
  }
  if (_storeContractSnapshotField(
    current: contract.buildingSnapshot,
    next: building == null ? null : _buildPropertySnapshot(building),
    overwrite: overwrite,
    assign: (value) => contract.buildingSnapshot = value,
  )) {
    changed = true;
  }
  return changed;
}

String? _snapshotString(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _snapshotDateValue(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

String? _snapshotNumberText(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  if (value is num) return _fmtMoneyTrunc(value);
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _snapshotIntValue(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

Map<String, String> _snapshotPropertySpecMap(String? desc) {
  final text = (desc ?? '').trim();
  if (text.isEmpty) return const <String, String>{};
  final start = text.indexOf('[[SPEC]]');
  final end = text.indexOf('[[/SPEC]]');
  if (start == -1 || end == -1 || end <= start) {
    return const <String, String>{};
  }
  final body = text.substring(start + 8, end).trim();
  if (body.isEmpty) return const <String, String>{};
  final map = <String, String>{};
  for (final line in body.split('\n')) {
    final parts = line.split(':');
    if (parts.length < 2) continue;
    final key = parts.first.trim();
    final value = parts.sublist(1).join(':').trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      map[key] = value;
    }
  }
  return map;
}

String? _snapshotPropertyFreeDescription(Map<String, dynamic>? snapshot) {
  final text = _snapshotString(snapshot, 'description');
  if (text == null) return null;
  final start = text.indexOf('[[SPEC]]');
  final end = text.indexOf('[[/SPEC]]');
  if (start != -1 && end != -1 && end > start) {
    final free = text.substring(end + 9).trim();
    return free.isEmpty ? null : free;
  }
  return text.trim().isEmpty ? null : text.trim();
}

String? _snapshotPropertyFurnishingText(Map<String, dynamic>? snapshot) {
  final raw =
      _snapshotPropertySpecMap(_snapshotString(snapshot, 'description'))['المفروشات'];
  if (raw == null) return null;
  final normalized = raw.trim();
  if (normalized.isEmpty) return null;
  if (normalized.contains('غير')) return 'غير مفروش';
  if (normalized.contains('مفروش')) return 'مفروش';
  return normalized;
}

String _snapshotPropertyTypeDisplayLabel(
  Map<String, dynamic> propertySnapshot, {
  Map<String, dynamic>? buildingSnapshot,
}) {
  final rawType = _snapshotString(propertySnapshot, 'type')?.toLowerCase().trim();
  final hasBuilding = (_snapshotString(propertySnapshot, 'parentBuildingId') ?? '')
          .trim()
          .isNotEmpty ||
      (buildingSnapshot != null && buildingSnapshot.isNotEmpty);
  if (rawType == 'apartment' && hasBuilding) {
    return 'وحدة';
  }
  return _snapshotString(propertySnapshot, 'typeLabel') ??
      (rawType == 'apartment' ? 'شقة' : null) ??
      '—';
}

String _snapshotBuildingTypeDisplayLabel(Map<String, dynamic>? buildingSnapshot) {
  final rawType = _snapshotString(buildingSnapshot, 'type')?.toLowerCase().trim();
  final rentalMode =
      _snapshotString(buildingSnapshot, 'rentalMode')?.toLowerCase().trim();
  if (rawType == 'building' && rentalMode == 'perunit') {
    return 'عمارة ذات وحدات';
  }
  return _snapshotString(buildingSnapshot, 'typeLabel') ??
      (rawType == 'building' ? 'عمارة' : null) ??
      '—';
}

List<String> _snapshotStringList(Map<String, dynamic>? snapshot, String key) {
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

bool? _snapshotBoolValue(Map<String, dynamic>? snapshot, String key) {
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

String? _snapshotBoolText(
  Map<String, dynamic>? snapshot,
  String key, {
  String yes = 'نعم',
  String no = 'لا',
}) {
  final value = _snapshotBoolValue(snapshot, key);
  if (value == null) return null;
  return value ? yes : no;
}

bool _isSnapshotImageAttachment(String path) {
  final lower = path.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

bool _isSnapshotRemoteAttachment(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://') || p.startsWith('gs://');
}

Future<String> _resolveSnapshotRemoteUrl(String path) async {
  if (path.startsWith('gs://')) {
    return FirebaseStorage.instance.refFromURL(path).getDownloadURL();
  }
  return path;
}

Widget _buildSnapshotAttachmentThumb(String path) {
  if (_isSnapshotImageAttachment(path)) {
    if (_isSnapshotRemoteAttachment(path)) {
      return FutureBuilder<String>(
        future: _resolveSnapshotRemoteUrl(path),
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

Future<void> _openSnapshotAttachment(BuildContext context, String path) async {
  try {
    final raw = path.trim();
    String launchable = raw;
    if (raw.startsWith('gs://')) {
      launchable = await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
    }
    Uri? uri;
    if (_isSnapshotRemoteAttachment(launchable)) {
      uri = Uri.tryParse(launchable);
    } else {
      final file = File(launchable);
      if (!file.existsSync()) throw Exception('attachment missing');
      uri = Uri.file(file.path);
    }
    if (uri == null) throw Exception('bad uri');
    var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
    );
  }
}

enum ContractTerm { daily, monthly, quarterly, semiAnnual, annual }

extension ContractTermLabel on ContractTerm {
  String get label {
    switch (this) {
      case ContractTerm.daily:
        return 'يومي';
      case ContractTerm.monthly:
        return 'شهري';
      case ContractTerm.quarterly:
        return 'ربع سنوي';
      case ContractTerm.semiAnnual:
        return 'نصف سنوي';
      case ContractTerm.annual:
        return 'سنوي';
    }
  }
}

enum PaymentCycle { monthly, quarterly, semiAnnual, annual }

extension PaymentCycleLabel on PaymentCycle {
  String get label {
    switch (this) {
      case PaymentCycle.monthly:
        return 'شهري';
      case PaymentCycle.quarterly:
        return 'ربع سنوي';
      case PaymentCycle.semiAnnual:
        return 'نصف سنوي';
      case PaymentCycle.annual:
        return 'سنوي';
    }
  }
}

String _termLabelForContract(Contract c) {
  if (c.term == ContractTerm.annual && c.termYears > 1) {
    return '${c.termYears} سنة';
  }
  return c.term.label;
}

String _paymentCycleLabelForContract(Contract c) {
  if (c.paymentCycle == PaymentCycle.annual && c.paymentCycleYears > 1) {
    return '${c.paymentCycleYears} سنة';
  }
  return c.paymentCycle.label;
}

String _cycleDurationLabelForContract(Contract c) {
  final months = _monthsPerCycleFor(c);
  if (months <= 1) return '1 شهر';
  if (months % 12 == 0) {
    final years = (months ~/ 12).clamp(1, 10);
    return years == 1 ? '1 سنة' : '$years سنة';
  }
  return '$months شهور';
}

String _dailyRentalDaysLabel(int days) {
  if (days <= 0) return '0 يوم';
  if (days == 1) return '1 يوم';
  if (days == 2) return '2 يوم';
  return '$days أيام';
}

String _fmtDateTimeDynamic(DateTime d) =>
    '${_fmtDateDynamic(d)} ${_formatHourAmPm(d.hour)}';

String _dailyContractPeriodLabel(Contract c) =>
    'من ${_fmtDateTimeDynamic(c.dailyStartBoundary)} إلى ${_fmtDateTimeDynamic(c.dailyEndBoundary)}';

List<InlineSpan> _dateTimeInlineSpans(
  DateTime d, {
  required TextStyle baseStyle,
  required TextStyle dateStyle,
}) {
  return <InlineSpan>[
    TextSpan(text: _fmtDateDynamic(d), style: dateStyle),
    TextSpan(text: ' ', style: baseStyle),
    TextSpan(text: _formatHourAmPm(d.hour), style: baseStyle),
  ];
}

Widget _dailyPeriodDetailsWidget(
  DateTime start,
  DateTime end, {
  TextStyle? baseStyle,
  TextStyle? dateStyle,
}) {
  final effectiveBase = baseStyle ??
      GoogleFonts.cairo(
        color: Colors.white,
        fontSize: 11.sp,
        fontWeight: FontWeight.w700,
      );
  final effectiveDate =
      dateStyle ?? effectiveBase.copyWith(color: const Color(0xFF93C5FD));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RichText(
        text: TextSpan(
          style: effectiveBase,
          children: _dateTimeInlineSpans(
            start,
            baseStyle: effectiveBase,
            dateStyle: effectiveDate,
          ),
        ),
      ),
      SizedBox(height: 2.h),
      Text('إلى', style: effectiveBase),
      SizedBox(height: 2.h),
      RichText(
        text: TextSpan(
          style: effectiveBase,
          children: _dateTimeInlineSpans(
            end,
            baseStyle: effectiveBase,
            dateStyle: effectiveDate,
          ),
        ),
      ),
    ],
  );
}

String _paymentPeriodLabelForDue(Contract c, DateTime dueDate) {
  if (c.term == ContractTerm.daily) {
    final days = _dailyContractDays(c.startDate, c.endDate);
    return '${_dailyRentalDaysLabel(days)}: ${_dailyContractPeriodLabel(c)}';
  }
  final start = _dateOnly(dueDate);
  final months = _monthsPerCycleFor(c);
  final duration = _cycleDurationLabelForContract(c);
  final endDate = _dateOnly(_addMonths(start, months));
  return '$duration: من ${_fmtDateDynamic(start)} إلى ${_fmtDateDynamic(endDate)}';
}

Widget _paymentPeriodChipForDue(Contract c, DateTime dueDate) {
  if (c.term == ContractTerm.daily) {
    const dateColor = Color(0xFF93C5FD);
    final baseStyle = GoogleFonts.cairo(
        color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700);
    final dateStyle = baseStyle.copyWith(color: dateColor);
    final days = _dailyContractDays(c.startDate, c.endDate);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dailyRentalDaysLabel(days),
            style: baseStyle,
          ),
          SizedBox(height: 4.h),
          _dailyPeriodDetailsWidget(
            c.dailyStartBoundary,
            c.dailyEndBoundary,
            baseStyle: baseStyle,
            dateStyle: dateStyle,
          ),
        ],
      ),
    );
  }
  final start = _dateOnly(dueDate);
  final months = _monthsPerCycleFor(c);
  final duration = _cycleDurationLabelForContract(c);
  const dateColor = Color(0xFF93C5FD);
  final baseStyle = GoogleFonts.cairo(
      color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700);
  final dateStyle = baseStyle.copyWith(color: dateColor);

  final List<InlineSpan> spans;
  final endDate = _dateOnly(_addMonths(start, months));
  spans = [
    TextSpan(text: '$duration: من ', style: baseStyle),
    TextSpan(text: _fmtDateDynamic(start), style: dateStyle),
    TextSpan(text: ' إلى ', style: baseStyle),
    TextSpan(text: _fmtDateDynamic(endDate), style: dateStyle),
  ];

  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
    decoration: BoxDecoration(
      color: const Color(0xFF1F2937),
      borderRadius: BorderRadius.circular(10.r),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
    ),
    child: RichText(text: TextSpan(children: spans)),
  );
}

enum AdvanceMode { none, deductFromTotal, coverMonths }

extension AdvanceModeLabel on AdvanceMode {
  String get label {
    switch (this) {
      case AdvanceMode.none:
        return 'بدون مقدم';
      case AdvanceMode.deductFromTotal:
        return 'يخصم من الإجمالي';
      case AdvanceMode.coverMonths:
        return 'يغطي أشهر معينة';
    }
  }
}

// جديد — فلاتر شاشة العقود
enum _ArchiveFilter { all, notArchived, archived }

enum _StatusFilter {
  all,
  active,
  endsToday,
  nearExpiry,
  due,
  expired,
  inactive,
  ended,
  canceled,
  nearContract
}

enum _TermFilter { all, daily, monthly, quarterly, semiAnnual, annual }

class ContractAdapter extends TypeAdapter<Contract> {
  @override
  final int typeId = 30; // تأكد عدم تعارضه مع مشروعك

  @override
  Contract read(BinaryReader r) {
    final numOfFields = r.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) r.readByte(): r.read(),
    };

    // قراءة قديمة + توافق
    final start = fields[3] as DateTime;
    final end = fields[4] as DateTime;

    int monthsBetween(DateTime a, DateTime b) {
      final y = b.year - a.year;
      final m = b.month - a.month;
      int mm = y * 12 + m;
      if (!DateTime(b.year, b.month, a.day).isAfter(b)) {
        // لا شيء
      } else {
        mm = (mm - 1).clamp(0, 1200);
      }
      return mm <= 0 ? 1 : mm;
    }

    final legacyPerCycle = (fields[5] as double?) ?? 0.0;
    final legacyCycleIndex = (fields[7] as int?) ?? 0;
    final legacyCycle = PaymentCycle
        .values[legacyCycleIndex.clamp(0, PaymentCycle.values.length - 1)];
    final termIndex = (fields[14] as int?);
    final advModeIndex = (fields[15] as int?);
    final readTerm = termIndex == null
        ? ContractTerm.monthly
        : ContractTerm
            .values[termIndex.clamp(0, ContractTerm.values.length - 1)];
    final readAdvanceMode = advModeIndex == null
        ? AdvanceMode.none
        : AdvanceMode
            .values[advModeIndex.clamp(0, AdvanceMode.values.length - 1)];

    double estimatedTotal = (fields[16] as double?) ?? 0.0;
    if (estimatedTotal == 0.0) {
      final months = monthsBetween(start, end);
      int monthsPerCycle = _monthsPerCycle(legacyCycle);
      final installments = (months / monthsPerCycle).ceil().clamp(1, 1000);
      estimatedTotal = legacyPerCycle * installments;
    }

    final readTermYears = (fields[20] as int?) ?? 1;
    final readCycleYears = (fields[21] as int?) ?? 1;
    final readEjarNo = (fields[22] as String?)?.trim();
    return Contract(
      id: fields[0] as String?,
      tenantId: fields[1] as String,
      propertyId: fields[2] as String,
      startDate: start,
      endDate: end,
      rentAmount: legacyPerCycle <= 0 ? estimatedTotal : legacyPerCycle,
      currency: fields[6] as String? ?? 'SAR',
      term: readTerm,
      termYears: readTermYears <= 0 ? 1 : readTermYears,
      paymentCycle: legacyCycle,
      paymentCycleYears: readCycleYears <= 0 ? 1 : readCycleYears,
      totalAmount:
          estimatedTotal > 0 ? estimatedTotal : (fields[5] as double? ?? 0.0),
      advancePaid: fields[8] as double?,
      advanceMode: readAdvanceMode,
      notes: fields[9] as String?,
      attachmentPaths:
          (fields[23] as List?)?.whereType<String>().toList() ?? <String>[],
      isTerminated: fields[10] as bool? ?? false,
      terminatedAt: fields[11] as DateTime?,
      createdAt: fields[12] as DateTime? ?? SaTimeLite.now(),
      updatedAt: fields[13] as DateTime? ?? SaTimeLite.now(),
      isArchived: fields[17] as bool? ?? false,
      dailyCheckoutHour: fields[18] as int?,
      serialNo: fields[19] as String?, // ← الجديد
      ejarContractNo:
          (readEjarNo == null || readEjarNo.isEmpty) ? null : readEjarNo,
      tenantSnapshot: _snapshotMapOrNull(fields[24]),
      propertySnapshot: _snapshotMapOrNull(fields[25]),
      buildingSnapshot: _snapshotMapOrNull(fields[26]),
    );
  }

  @override
  void write(BinaryWriter w, Contract c) {
    w
      ..writeByte(27)
      ..writeByte(0)
      ..write(c.id)
      ..writeByte(1)
      ..write(c.tenantId)
      ..writeByte(2)
      ..write(c.propertyId)
      ..writeByte(3)
      ..write(c.startDate)
      ..writeByte(4)
      ..write(c.endDate)
      ..writeByte(5)
      ..write(c.rentAmount)
      ..writeByte(6)
      ..write(c.currency)
      ..writeByte(7)
      ..write(c.paymentCycle.index)
      ..writeByte(8)
      ..write(c.advancePaid)
      ..writeByte(9)
      ..write(c.notes)
      ..writeByte(10)
      ..write(c.isTerminated)
      ..writeByte(11)
      ..write(c.terminatedAt)
      ..writeByte(12)
      ..write(c.createdAt)
      ..writeByte(13)
      ..write(c.updatedAt)
      ..writeByte(14)
      ..write(c.term.index)
      ..writeByte(15)
      ..write(c.advanceMode.index)
      ..writeByte(16)
      ..write(c.totalAmount)
      ..writeByte(17)
      ..write(c.isArchived)
      ..writeByte(18)
      ..write(c.dailyCheckoutHour)
      ..writeByte(19) // ← فهرس الحقل الجديد
      ..write(c.serialNo) // ← قيمة الحقل الجديد
      ..writeByte(20)
      ..write(c.termYears)
      ..writeByte(21)
      ..write(c.paymentCycleYears)
      ..writeByte(22)
      ..write(c.ejarContractNo)
      ..writeByte(23)
      ..write(c.attachmentPaths)
      ..writeByte(24)
      ..write(c.tenantSnapshot)
      ..writeByte(25)
      ..write(c.propertySnapshot)
      ..writeByte(26)
      ..write(c.buildingSnapshot);
  }
}

int _monthsPerCycle(PaymentCycle c) {
  switch (c) {
    case PaymentCycle.monthly:
      return 1;
    case PaymentCycle.quarterly:
      return 3;
    case PaymentCycle.semiAnnual:
      return 6;
    case PaymentCycle.annual:
      return 12;
  }
}

int _monthsInTerm(ContractTerm t) {
  switch (t) {
    case ContractTerm.daily:
      return 0;
    case ContractTerm.monthly:
      return 1;
    case ContractTerm.quarterly:
      return 3;
    case ContractTerm.semiAnnual:
      return 6;
    case ContractTerm.annual:
      return 12;
  }
}

List<PaymentCycle> _allowedCyclesForTerm(ContractTerm t) {
  if (t == ContractTerm.daily) return const [];
  final termMonths = _monthsInTerm(t);
  return PaymentCycle.values
      .where((pc) => _monthsPerCycle(pc) <= termMonths)
      .toList();
}

int _monthsInContract(Contract c) {
  if (c.term == ContractTerm.annual) {
    final y = c.termYears <= 0 ? 1 : c.termYears;
    return 12 * y;
  }
  return _monthsInTerm(c.term);
}

int _monthsPerCycleFor(Contract c) {
  if (c.paymentCycle == PaymentCycle.annual) {
    final y = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
    return 12 * y;
  }
  return _monthsPerCycle(c.paymentCycle);
}

bool _termEqualsCycle(ContractTerm t, PaymentCycle c) {
  switch (t) {
    case ContractTerm.monthly:
      return c == PaymentCycle.monthly;
    case ContractTerm.quarterly:
      return c == PaymentCycle.quarterly;
    case ContractTerm.semiAnnual:
      return c == PaymentCycle.semiAnnual;
    case ContractTerm.annual:
      return c == PaymentCycle.annual;
    case ContractTerm.daily:
      return false; // اليومي لا يملك دورة سداد
  }
}

int _coveredMonthsByAdvance(Contract c) {
  if (c.advanceMode != AdvanceMode.coverMonths) return 0;
  if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
  final months = _monthsInContract(c);
  if (months <= 0) return 0;
  final monthlyValue = c.totalAmount / months;
  final covered = ((c.advancePaid ?? 0) / monthlyValue).floor();
  return covered.clamp(0, months);
}

int _daysInMonth(int year, int month) {
  if (month == 12) return DateTime(year + 1, 1, 0).day;
  return DateTime(year, month + 1, 0).day;
}

DateTime _addMonths(DateTime d, int months) {
  if (months == 0) return d;
  final y0 = d.year;
  final m0 = d.month;
  final totalM = m0 - 1 + months;
  final y = y0 + totalM ~/ 12;
  final m = totalM % 12 + 1;
  final day = d.day;
  final maxDay = _daysInMonth(y, m);
  final safeDay = day > maxDay ? maxDay : day;
  return DateTime(
      y, m, safeDay, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => SaTimeLite.today();

Future<Box<Map>> openServicesConfigBox() async {
  final boxId = boxName('servicesConfig');
  if (!Hive.isBoxOpen(boxId)) {
    await Hive.openBox<Map>(boxId);
  }
  return Hive.box<Map>(boxId);
}

double _serviceConfigNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString().trim()) ?? 0.0;
}

DateTime? _serviceConfigDate(dynamic value) {
  if (value is DateTime) return _dateOnly(value);
  if (value is String && value.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed != null) return _dateOnly(parsed);
  }
  return null;
}

String _waterBillingModeFromConfig(Map<String, dynamic> cfg) {
  return (cfg['waterBillingMode'] ?? cfg['mode'] ?? 'separate')
      .toString()
      .trim()
      .toLowerCase();
}

String _waterSharedMethodFromConfig(Map<String, dynamic> cfg) {
  return (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
}

bool isWaterSharedFixedConfig(Map<String, dynamic> cfg) =>
    _waterBillingModeFromConfig(cfg) == 'shared' &&
    _waterSharedMethodFromConfig(cfg) == 'fixed';

bool isWaterSharedPercentConfig(Map<String, dynamic> cfg) =>
    _waterBillingModeFromConfig(cfg) == 'shared' &&
    _waterSharedMethodFromConfig(cfg) == 'percent';

List<Map<String, dynamic>> waterInstallmentsFromConfig(Map<String, dynamic> cfg) {
  final raw = cfg['waterInstallments'];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
      .whereType<Map<String, dynamic>>()
      .toList();
}

List<Map<String, dynamic>> waterPercentRequestsFromConfig(
    Map<String, dynamic> cfg) {
  final raw = cfg['waterPercentRequests'];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
      .whereType<Map<String, dynamic>>()
      .toList();
}

double waterTotalAmountFromConfig(Map<String, dynamic> cfg) {
  final rawTotal = cfg['totalWaterAmount'] ?? cfg['waterTotalAmount'];
  if (rawTotal is num) return rawTotal.toDouble();
  return double.tryParse((rawTotal ?? '').toString()) ?? 0.0;
}

double waterSharePercentFromConfig(Map<String, dynamic> cfg) {
  final rawPercent = cfg['sharePercent'];
  if (rawPercent is num) return rawPercent.toDouble();
  return double.tryParse((rawPercent ?? '').toString()) ?? 0.0;
}

String _waterNextDueIsoFromConfig(Map<String, dynamic> cfg) {
  final raw = cfg['nextDueDate'];
  if (raw is String) return raw.trim();
  return '';
}

String _sharedUnitsModeFromConfig(Map<String, dynamic> cfg) {
  return (cfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
}

String _sharedUnitsModeForService(
  Map<String, dynamic> cfg,
  String serviceType,
) {
  final raw = _sharedUnitsModeFromConfig(cfg);
  if (serviceType.trim().toLowerCase() == 'water') {
    if (raw == 'units') return 'units_fixed';
    if (raw == 'units_fixed' || raw == 'units_separate') return raw;
  }
  return raw;
}

bool _isWaterFixedAmountConfigReady(Map<String, dynamic> cfg) {
  if (!isWaterSharedFixedConfig(cfg)) return false;
  if (waterInstallmentsFromConfig(cfg).isNotEmpty) return true;
  return waterTotalAmountFromConfig(cfg) > 0;
}

List<Map<String, dynamic>> sharedPercentUnitSharesFromConfig(
  Map<String, dynamic> cfg,
) {
  final raw = cfg['sharedPercentUnitShares'];
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
      .whereType<Map<String, dynamic>>()
      .toList();
}

List<Map<String, dynamic>> _listOfMap(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
      .whereType<Map<String, dynamic>>()
      .toList();
}

double _sharedUnitsSharePercentForProperty(
  Map<String, dynamic> cfg,
  String propertyId,
) {
  final normalizedPropertyId = propertyId.trim();
  if (normalizedPropertyId.isEmpty) return 0.0;
  final row = firstWhereOrNull(
    sharedPercentUnitSharesFromConfig(cfg),
    (item) => (item['unitId'] ?? '').toString().trim() == normalizedPropertyId,
  );
  if (row == null) return 0.0;
  return _serviceConfigNumber(row['percent']);
}

bool _isSharedUnitsPercentConfigReady(Map<String, dynamic> cfg) {
  if (_sharedUnitsModeFromConfig(cfg) != 'shared_percent') return false;
  return _serviceConfigDate(cfg['nextDueDate']) != null;
}

String _electricityBillingModeFromConfig(Map<String, dynamic> cfg) {
  return (cfg['electricityBillingMode'] ?? cfg['mode'] ?? 'separate')
      .toString()
      .trim()
      .toLowerCase();
}

String _internetBillingModeFromConfig(Map<String, dynamic> cfg) {
  return (cfg['internetBillingMode'] ?? cfg['mode'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
}

bool isWaterConfigReady(Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return false;
  final mode = _waterBillingModeFromConfig(cfg);
  if (mode == 'separate') return true;
  if (mode != 'shared') return false;
  final method = _waterSharedMethodFromConfig(cfg);
  if (method == 'percent') {
    return waterSharePercentFromConfig(cfg) > 0;
  }
  if (method == 'fixed') {
    if (waterInstallmentsFromConfig(cfg).isNotEmpty) return true;
    return waterTotalAmountFromConfig(cfg) > 0;
  }
  return false;
}

bool isElectricityConfigReady(Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return false;
  final mode = _electricityBillingModeFromConfig(cfg);
  if (mode == 'separate') return true;
  if (mode != 'shared') return false;
  final method = (cfg['electricitySharedMethod'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (method != 'percent') return false;
  return _serviceConfigNumber(cfg['electricitySharePercent']) > 0;
}

bool isInternetConfigReady(Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return false;
  final mode = _internetBillingModeFromConfig(cfg);
  if (mode == 'separate') return true;
  if (mode != 'owner') return false;
  return _serviceConfigDate(cfg['startDate']) != null &&
      (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
}

bool isCleaningConfigReady(Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return false;
  return _serviceConfigDate(cfg['startDate']) != null &&
      (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
}

bool isElevatorConfigReady(Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return false;
  return _serviceConfigDate(cfg['startDate']) != null &&
      (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
}

String periodicServiceDisplayName(String type) {
  switch (type) {
    case 'water':
      return 'المياه';
    case 'electricity':
      return 'الكهرباء';
    case 'internet':
      return 'الإنترنت';
    case 'cleaning':
      return 'النظافة';
    case 'elevator':
      return 'صيانة المصعد';
    default:
      return type;
  }
}

bool _isPeriodicServiceConfigReady(String type, Map<String, dynamic> cfg) {
  switch (type) {
    case 'water':
      return isWaterConfigReady(cfg);
    case 'electricity':
      return isElectricityConfigReady(cfg);
    case 'internet':
      return isInternetConfigReady(cfg);
    case 'cleaning':
      return isCleaningConfigReady(cfg);
    case 'elevator':
      return isElevatorConfigReady(cfg);
    default:
      return cfg.isNotEmpty;
  }
}

List<String> requiredPeriodicServiceTypesForProperty(Property property) {
  final isRootBuilding = property.type == PropertyType.building &&
      (property.parentBuildingId == null ||
          property.parentBuildingId!.trim().isEmpty);
  if (property.type == PropertyType.building &&
      property.rentalMode == RentalMode.perUnit) {
    return const <String>['cleaning', 'elevator'];
  }
  if (isRootBuilding) {
    return const <String>[
      'water',
      'electricity',
      'internet',
      'cleaning',
      'elevator',
    ];
  }
  if ((property.parentBuildingId ?? '').trim().isNotEmpty) {
    return const <String>['water', 'electricity', 'internet'];
  }
  return const <String>['water', 'electricity', 'internet', 'cleaning'];
}

Future<List<String>> missingRequiredPeriodicServicesForProperty(
  String propertyId, {
  Property? property,
}) async {
  final normalizedPropertyId = propertyId.trim();
  if (normalizedPropertyId.isEmpty) return const <String>[];
  final box = await openServicesConfigBox();
  final missing = <String>[];
  final propertiesBoxId = boxName(kPropertiesBox);
  final propertiesBox = Hive.isBoxOpen(propertiesBoxId)
      ? Hive.box<Property>(propertiesBoxId)
      : await Hive.openBox<Property>(propertiesBoxId);

  Map<String, dynamic> cfgFor(String type) {
    final raw = box.get('$normalizedPropertyId::$type');
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Map<String, dynamic> cfgForPropertyId(String targetPropertyId, String type) {
    final raw = box.get('${targetPropertyId.trim()}::$type');
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  var targetProperty = property;
  if (targetProperty == null) {
    targetProperty = firstWhereOrNull(
      propertiesBox.values,
      (item) => item.id == normalizedPropertyId,
    );
  }

  final parentBuildingId = (targetProperty?.parentBuildingId ?? '').trim();
  final parentBuilding = parentBuildingId.isEmpty
      ? null
      : firstWhereOrNull(
          propertiesBox.values,
          (item) => item.id == parentBuildingId,
        );

  final requiredTypes = targetProperty == null
      ? const <String>['water', 'electricity', 'internet']
      : requiredPeriodicServiceTypesForProperty(targetProperty);
  for (final type in requiredTypes) {
    final isUnitInsidePerUnitBuilding = parentBuilding != null &&
        parentBuilding.type == PropertyType.building &&
        parentBuilding.rentalMode == RentalMode.perUnit &&
        (type == 'water' || type == 'electricity');
    if (isUnitInsidePerUnitBuilding) {
      final buildingCfg = cfgForPropertyId(parentBuilding.id, type);
      final buildingMode = _sharedUnitsModeForService(buildingCfg, type);
      if (buildingMode == 'shared_percent') {
        if (_isSharedUnitsPercentConfigReady(buildingCfg)) {
          continue;
        }
        missing.add(periodicServiceDisplayName(type));
        continue;
      }
      if (type == 'water' && buildingMode == 'units_separate') {
        continue;
      }
      if (type == 'water' && buildingMode == 'units_fixed') {
        if (_isWaterFixedAmountConfigReady(cfgFor(type))) {
          continue;
        }
        missing.add('المياه (المبلغ المقطوع للوحدة)');
        continue;
      }
      if (buildingMode != 'units') {
        missing.add(periodicServiceDisplayName(type));
        continue;
      }
    }
    if (_isPeriodicServiceConfigReady(type, cfgFor(type))) continue;
    missing.add(periodicServiceDisplayName(type));
  }

  return missing;
}

Map<String, dynamic> _normalizeOwnerPeriodicServiceConfig({
  required String type,
  required Map<String, dynamic> cfg,
}) {
  if (cfg.isEmpty) return <String, dynamic>{};
  final providerName = (cfg['providerName'] ?? '').toString().trim();
  final startDate = _serviceConfigDate(cfg['startDate']);
  if (providerName.isEmpty || startDate == null) return <String, dynamic>{};
  final nextDue = _serviceConfigDate(cfg['nextDueDate']);
  return {
    ...cfg,
    'serviceType': type,
    'payer': 'owner',
    'providerId': (cfg['providerId'] ?? '').toString().trim(),
    'providerName': providerName,
    'startDate': startDate.toIso8601String(),
    'nextDueDate': nextDue?.toIso8601String() ?? '',
  };
}

Map<String, dynamic> normalizeElectricityConfigForNoActiveContract(
    Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return <String, dynamic>{};
  final sharedUnitsMode = _sharedUnitsModeFromConfig(cfg);
  if (sharedUnitsMode == 'shared_percent') {
    final shares = sharedPercentUnitSharesFromConfig(cfg);
    final nextDue = _serviceConfigDate(cfg['nextDueDate']);
    return {
      ...cfg,
      'serviceType': 'electricity',
      'payer': 'owner',
      'sharedUnitsMode': 'shared_percent',
      'sharedPercentUnitShares': shares,
      'electricityBillingMode': '',
      'electricitySharedMethod': '',
      'electricitySharePercent': null,
      'electricityMeterNo': '',
      'nextDueDate': nextDue?.toIso8601String() ?? '',
      'dueDay': nextDue?.day ?? 0,
      'recurrenceMonths': 1,
      'electricityPercentRequests': _listOfMap(cfg['electricityPercentRequests']),
    };
  }
  if (sharedUnitsMode == 'units') {
    return {
      ...cfg,
      'serviceType': 'electricity',
      'payer': '',
      'sharedUnitsMode': 'units',
      'sharedPercentUnitShares': <Map<String, dynamic>>[],
      'electricityBillingMode': '',
      'electricitySharedMethod': '',
      'electricitySharePercent': null,
      'electricityMeterNo': '',
      'electricityPercentRequests': <Map<String, dynamic>>[],
      'nextDueDate': '',
      'dueDay': 0,
      'recurrenceMonths': 0,
      'remindBeforeDays': 0,
    };
  }
  final mode = _electricityBillingModeFromConfig(cfg);
  if (mode == 'shared') {
    final percent = _serviceConfigNumber(cfg['electricitySharePercent']);
    if (percent <= 0) return <String, dynamic>{};
    return {
      ...cfg,
      'serviceType': 'electricity',
      'payer': 'owner',
      'electricityBillingMode': 'shared',
      'electricitySharedMethod': 'percent',
      'electricitySharePercent': percent,
      'electricityMeterNo': '',
    };
  }
  return {
    ...cfg,
    'serviceType': 'electricity',
    'payer': 'tenant',
    'electricityBillingMode': 'separate',
    'electricitySharedMethod': '',
    'electricitySharePercent': null,
    'electricityPercentRequests': <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> normalizeInternetConfigForNoActiveContract(
    Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return <String, dynamic>{};
  final mode = _internetBillingModeFromConfig(cfg);
  if (mode == 'owner') {
    final normalized =
        _normalizeOwnerPeriodicServiceConfig(type: 'internet', cfg: cfg);
    if (normalized.isEmpty) return normalized;
    return {
      ...normalized,
      'internetBillingMode': 'owner',
    };
  }
  return {
    ...cfg,
    'serviceType': 'internet',
    'payer': 'tenant',
    'internetBillingMode': 'separate',
    'providerId': '',
    'providerName': '',
    'startDate': '',
    'nextDueDate': '',
    'recurrenceMonths': 0,
    'targetId': '',
    'lastGeneratedRequestId': '',
    'lastGeneratedRequestDate': '',
    'suppressedRequestDate': '',
  };
}

Map<String, dynamic> normalizeCleaningConfigForNoActiveContract(
    Map<String, dynamic> cfg) {
  return _normalizeOwnerPeriodicServiceConfig(type: 'cleaning', cfg: cfg);
}

Map<String, dynamic> normalizeElevatorConfigForNoActiveContract(
    Map<String, dynamic> cfg) {
  return _normalizeOwnerPeriodicServiceConfig(type: 'elevator', cfg: cfg);
}

Map<String, dynamic> normalizePeriodicServiceConfigForNoActiveContract(
  String serviceType,
  Map<String, dynamic> cfg,
) {
  switch (serviceType) {
    case 'water':
      return normalizeWaterConfigForNoActiveContract(cfg);
    case 'electricity':
      return normalizeElectricityConfigForNoActiveContract(cfg);
    case 'internet':
      return normalizeInternetConfigForNoActiveContract(cfg);
    case 'cleaning':
      return normalizeCleaningConfigForNoActiveContract(cfg);
    case 'elevator':
      return normalizeElevatorConfigForNoActiveContract(cfg);
    default:
      return cfg.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(cfg);
  }
}

Future<List<String>> missingContractPeriodicServicesForProperty(
    String propertyId) async {
  final normalizedPropertyId = propertyId.trim();
  if (normalizedPropertyId.isEmpty) return const <String>[];
  final box = await openServicesConfigBox();
  final missing = <String>[];

  Map<String, dynamic> cfgFor(String type) {
    final raw = box.get('$normalizedPropertyId::$type');
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  if (!isWaterConfigReady(cfgFor('water'))) {
    missing.add('المياه');
  }
  if (!isElectricityConfigReady(cfgFor('electricity'))) {
    missing.add('الكهرباء');
  }
  if (!isInternetConfigReady(cfgFor('internet'))) {
    missing.add('الإنترنت');
  }

  return missing;
}

Map<String, dynamic> normalizeWaterConfigForNoActiveContract(
    Map<String, dynamic> cfg) {
  if (cfg.isEmpty) return <String, dynamic>{};
  final history = _waterHistorySnapshotFromConfig(cfg);
  final sharedUnitsMode = _sharedUnitsModeForService(cfg, 'water');
  if (sharedUnitsMode == 'shared_percent') {
    final shares = sharedPercentUnitSharesFromConfig(cfg);
    final nextDue = _serviceConfigDate(cfg['nextDueDate']);
    return {
      ...cfg,
      ...history,
      'serviceType': 'water',
      'payer': 'owner',
      'sharedUnitsMode': 'shared_percent',
      'sharedPercentUnitShares': shares,
      'waterBillingMode': '',
      'waterSharedMethod': '',
      'sharePercent': null,
      'totalWaterAmount': null,
      'waterPerInstallment': null,
      'waterLinkedContractId': '',
      'waterLinkedTenantId': '',
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'waterPercentRequests': waterPercentRequestsFromConfig(cfg),
      'waterMeterNo': '',
      'nextDueDate': nextDue?.toIso8601String() ?? '',
      'dueDay': nextDue?.day ?? 0,
      'recurrenceMonths': 1,
    };
  }
  if (sharedUnitsMode == 'units_fixed') {
    return {
      ...cfg,
      ...history,
      'serviceType': 'water',
      'payer': '',
      'sharedUnitsMode': 'units_fixed',
      'sharedPercentUnitShares': <Map<String, dynamic>>[],
      'waterBillingMode': '',
      'waterSharedMethod': '',
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'totalWaterAmount': null,
      'waterPerInstallment': null,
      'waterLinkedContractId': '',
      'waterLinkedTenantId': '',
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'nextDueDate': '',
      'dueDay': 0,
      'recurrenceMonths': 0,
      'remindBeforeDays': 0,
      'waterMeterNo': '',
    };
  }
  if (sharedUnitsMode == 'units_separate') {
    final meterNo = (cfg['waterMeterNo'] ?? '').toString().trim();
    return {
      ...cfg,
      ...history,
      'serviceType': 'water',
      'payer': '',
      'sharedUnitsMode': 'units_separate',
      'sharedPercentUnitShares': <Map<String, dynamic>>[],
      'waterBillingMode': 'separate',
      'waterSharedMethod': '',
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'totalWaterAmount': null,
      'waterPerInstallment': null,
      'waterLinkedContractId': '',
      'waterLinkedTenantId': '',
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'nextDueDate': '',
      'dueDay': 0,
      'recurrenceMonths': 0,
      'remindBeforeDays': 0,
      'waterMeterNo': meterNo,
    };
  }
  final mode = _waterBillingModeFromConfig(cfg);
  if (mode == 'shared') {
    final method = _waterSharedMethodFromConfig(cfg);
    if (method == 'fixed') {
      final total = waterTotalAmountFromConfig(cfg);
      if (total <= 0) return <String, dynamic>{};
      return {
        ...cfg,
        ...history,
        'serviceType': 'water',
        'payer': 'owner',
        'waterBillingMode': 'shared',
        'waterSharedMethod': 'fixed',
        'sharePercent': null,
        'waterPercentRequests': <Map<String, dynamic>>[],
        'totalWaterAmount': total,
        'waterPerInstallment': 0.0,
        'waterLinkedContractId': '',
        'waterLinkedTenantId': '',
        'waterInstallments': <Map<String, dynamic>>[],
        'remainingInstallmentsCount': 0,
        'nextDueDate': '',
        'waterMeterNo': '',
      };
    }
    if (method == 'percent') {
      final percent = waterSharePercentFromConfig(cfg);
      if (percent <= 0) return <String, dynamic>{};
      return {
        ...cfg,
        ...history,
        'serviceType': 'water',
        'payer': 'owner',
        'waterBillingMode': 'shared',
        'waterSharedMethod': 'percent',
        'sharePercent': percent,
        'totalWaterAmount': null,
        'waterPerInstallment': null,
        'waterLinkedContractId': '',
        'waterLinkedTenantId': '',
        'waterInstallments': <Map<String, dynamic>>[],
        'remainingInstallmentsCount': 0,
        'waterPercentRequests': waterPercentRequestsFromConfig(cfg),
        'waterMeterNo': '',
      };
    }
    return <String, dynamic>{};
  }
  final meterNo = (cfg['waterMeterNo'] ?? '').toString().trim();
  if (mode == 'separate') {
    return {
      ...cfg,
      ...history,
      'serviceType': 'water',
      'payer': 'tenant',
      'waterBillingMode': 'separate',
      'waterSharedMethod': '',
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'totalWaterAmount': null,
      'waterPerInstallment': null,
      'waterLinkedContractId': '',
      'waterLinkedTenantId': '',
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'nextDueDate': '',
      'waterMeterNo': meterNo,
    };
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _waterHistorySnapshotFromConfig(
  Map<String, dynamic> cfg,
) {
  final linkedContractId = (cfg['waterLinkedContractId'] ?? '').toString().trim();
  final rows = waterInstallmentsFromConfig(cfg);
  if (linkedContractId.isEmpty || rows.isEmpty) return <String, dynamic>{};

  final invoicesBoxId = boxName(kInvoicesBox);
  final invoicesBox = Hive.isBoxOpen(invoicesBoxId)
      ? Hive.box<Invoice>(invoicesBoxId)
      : null;

  var paidCount = 0;
  var canceledCount = 0;
  var paidAmount = 0.0;
  var canceledAmount = 0.0;

  for (final row in rows) {
    final amount = _serviceConfigNumber(row['amount']);
    final invoiceId = (row['invoiceId'] ?? '').toString().trim();
    final status = (row['status'] ?? '').toString().trim().toLowerCase();

    var isPaid = status == 'paid';
    var isCanceled = false;

    if (invoiceId.isNotEmpty && invoicesBox != null) {
      final invoice = firstWhereOrNull(
        invoicesBox.values,
        (item) => item.id == invoiceId,
      );
      if (invoice != null) {
        if (invoice.isCanceled) {
          isCanceled = true;
          isPaid = false;
        } else if (invoice.paidAmount + 0.000001 >= invoice.amount.abs()) {
          isPaid = true;
        }
      }
    }

    if (!isPaid && !isCanceled) {
      isCanceled = true;
    }

    if (isPaid) {
      paidCount += 1;
      paidAmount += amount;
    } else if (isCanceled) {
      canceledCount += 1;
      canceledAmount += amount;
    }
  }

  return {
    'waterLastContractId': linkedContractId,
    'waterLastInstallmentsCount': rows.length,
    'waterLastPaidInstallmentsCount': paidCount,
    'waterLastCanceledInstallmentsCount': canceledCount,
    'waterLastPaidAmount': paidAmount,
    'waterLastCanceledAmount': canceledAmount,
    'waterLastHistoryCapturedAt': KsaTime.now().toIso8601String(),
  };
}

bool _isContractDueFullyPaidByInvoices(
  Iterable<Invoice> invoices,
  Contract contract,
  DateTime due,
) {
  final dueOnly = _dateOnly(due);
  for (final inv in invoices) {
    if (!_isPaidRentInvoiceForContract(contract, inv)) continue;
    if (_dateOnly(inv.dueDate) != dueOnly) continue;
    return true;
  }
  return false;
}

Map<String, dynamic> rebuildWaterFixedConfigForContract({
  required Map<String, dynamic> currentCfg,
  required Contract contract,
  required Iterable<Invoice> invoices,
  required double totalWaterAmount,
}) {
  if (contract.term == ContractTerm.daily) {
    return normalizeWaterConfigForNoActiveContract({
      ...currentCfg,
      'serviceType': 'water',
      'payer': 'owner',
      'waterBillingMode': 'shared',
      'waterSharedMethod': 'fixed',
      'totalWaterAmount': totalWaterAmount,
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'waterMeterNo': '',
    });
  }

  final mpc = _monthsPerCycleFor(contract);
  final firstDue = _firstDueAfterAdvance(contract);
  final end = _dateOnly(contract.endDate);
  final allDues = <DateTime>[];
  if (firstDue != null) {
    var cursor = _dateOnly(firstDue);
    while (!cursor.isAfter(end)) {
      allDues.add(cursor);
      cursor = _dateOnly(_addMonths(cursor, mpc));
    }
  }
  if (allDues.isEmpty) {
    return {
      ...currentCfg,
      'serviceType': 'water',
      'payer': 'owner',
      'waterBillingMode': 'shared',
      'waterSharedMethod': 'fixed',
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'waterMeterNo': '',
      'waterLinkedContractId': contract.id,
      'waterLinkedTenantId': contract.tenantId,
      'totalWaterAmount': totalWaterAmount,
      'waterPerInstallment': 0.0,
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'nextDueDate': '',
      'recurrenceMonths': mpc,
    };
  }

  final previous = waterInstallmentsFromConfig(currentCfg);
  final prevByDue = <String, Map<String, dynamic>>{
    for (final row in previous)
      (row['dueDate'] ?? '').toString(): Map<String, dynamic>.from(row),
  };
  final includedDues = allDues.where((due) {
    final key = _dateOnly(due).toIso8601String();
    final prev = prevByDue[key];
    if (prev != null) return true;
    return !_isContractDueFullyPaidByInvoices(invoices, contract, due);
  }).toList();
  final paidRows = <String, Map<String, dynamic>>{};
  for (final due in includedDues) {
    final key = _dateOnly(due).toIso8601String();
    final prev = prevByDue[key];
    if (prev == null) continue;
    final status = (prev['status'] ?? '').toString();
    final invoiceId = (prev['invoiceId'] ?? '').toString().trim();
    if (status == 'paid' || invoiceId.isNotEmpty) {
      paidRows[key] = prev;
    }
  }
  final pendingDues = includedDues
      .where((due) => !paidRows.containsKey(_dateOnly(due).toIso8601String()))
      .toList();
  final preservedPaidAmount = paidRows.values.fold<double>(
    0.0,
    (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0.0),
  );
  final distributableTotal = ((totalWaterAmount - preservedPaidAmount)
          .clamp(0.0, double.infinity) as num)
      .toDouble();
  final perRaw = (distributableTotal <= 0 || pendingDues.isEmpty)
      ? 0.0
      : (distributableTotal / pendingDues.length);
  final perRounded = ((perRaw * 100).roundToDouble()) / 100.0;
  final rows = <Map<String, dynamic>>[];
  var pendingIndex = 0;
  final pendingCount = pendingDues.length;
  var distributed = 0.0;

  for (final due in includedDues) {
    final key = _dateOnly(due).toIso8601String();
    final prev = prevByDue[key];
    final isPaid = paidRows.containsKey(key);
    double amountForRow;
    if (isPaid) {
      amountForRow = ((paidRows[key]?['amount'] as num?)?.toDouble() ??
          ((prev?['amount'] as num?)?.toDouble() ?? 0.0));
    } else {
      pendingIndex++;
      if (pendingIndex == pendingCount) {
        amountForRow = distributableTotal - distributed;
      } else {
        amountForRow = perRounded;
        distributed += perRounded;
      }
    }
    rows.add({
      'id': key,
      'dueDate': key,
      'amount': amountForRow,
      'status': isPaid ? 'paid' : 'pending',
      'invoiceId': (prev?['invoiceId'] ?? '').toString(),
      'officeExpenseInvoiceId':
          (prev?['officeExpenseInvoiceId'] ?? '').toString(),
    });
  }

  final firstUnpaid = firstWhereOrNull(
    rows,
    (row) => (row['status'] ?? 'pending').toString() != 'paid',
  );
  return {
    ...currentCfg,
    'serviceType': 'water',
    'payer': 'owner',
    'waterBillingMode': 'shared',
    'waterSharedMethod': 'fixed',
    'sharePercent': null,
    'waterPercentRequests': <Map<String, dynamic>>[],
    'waterMeterNo': '',
    'waterLinkedContractId': contract.id,
    'waterLinkedTenantId': contract.tenantId,
    'totalWaterAmount': totalWaterAmount,
    'waterPerInstallment': perRaw,
    'waterInstallments': rows,
    'remainingInstallmentsCount':
        rows.where((row) => (row['status'] ?? 'pending').toString() != 'paid').length,
    'nextDueDate': (firstUnpaid?['dueDate'] ?? '').toString(),
    'recurrenceMonths': mpc,
  };
}

Contract? _activeContractForPropertyGlobal(
  String propertyId, {
  String? excludeContractId,
}) {
  if (propertyId.trim().isEmpty) return null;
  final boxId = boxName(kContractsBox);
  if (!Hive.isBoxOpen(boxId)) return null;
  final now = KsaTime.now();
  final excluded = (excludeContractId ?? '').trim();
  final list = Hive.box<Contract>(boxId)
      .values
      .where((contract) =>
          contract.propertyId == propertyId &&
          !contract.isTerminated &&
          !contract.isArchived &&
          contract.id != excluded &&
          contract.startDate.isBefore(now.add(const Duration(days: 1))) &&
          contract.endDate.isAfter(now.subtract(const Duration(days: 1))))
      .toList()
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
  return list.isNotEmpty ? list.first : null;
}

Future<void> detachWaterConfigFromContractIfNeeded({
  required String propertyId,
  required String contractId,
}) async {
  try {
    if (propertyId.trim().isEmpty || contractId.trim().isEmpty) return;
    final box = await openServicesConfigBox();
    final key = '$propertyId::water';
    final raw = box.get(key);
    if (raw is! Map) return;
    final cfg = Map<String, dynamic>.from(raw);
    final linked = (cfg['waterLinkedContractId'] ?? '').toString().trim();
    if (linked != contractId.trim()) return;
    await box.put(key, normalizeWaterConfigForNoActiveContract(cfg));
    final replacement = _activeContractForPropertyGlobal(
      propertyId,
      excludeContractId: contractId,
    );
    if (replacement != null) {
      await linkWaterConfigToContractIfNeeded(replacement);
    }
  } catch (_) {}
}

Future<void> syncWaterConfigForContractChange(
  Contract contract, {
  String? previousPropertyId,
}) async {
  try {
    final oldPropertyId = (previousPropertyId ?? '').trim();
    if (oldPropertyId.isNotEmpty && oldPropertyId != contract.propertyId) {
      await detachWaterConfigFromContractIfNeeded(
        propertyId: oldPropertyId,
        contractId: contract.id,
      );
    }
    if (contract.term == ContractTerm.daily) {
      await detachWaterConfigFromContractIfNeeded(
        propertyId: contract.propertyId,
        contractId: contract.id,
      );
      return;
    }
    await linkWaterConfigToContractIfNeeded(contract);
  } catch (_) {}
}

Future<void> linkWaterConfigToContractIfNeeded(Contract c) async {
  try {
    if (c.term == ContractTerm.daily) return;
    final box = await openServicesConfigBox();
    final key = '${c.propertyId}::water';
    final raw = box.get(key);
    if (raw is! Map) return;

    final cfg = Map<String, dynamic>.from(raw);
    if (!isWaterSharedFixedConfig(cfg)) return;

    final total = waterTotalAmountFromConfig(cfg);
    if (total <= 0) return;

    final linked = (cfg['waterLinkedContractId'] ?? '').toString().trim();
    if (linked.isNotEmpty && linked != c.id) {
      final linkedContract = firstWhereOrNull(
        Hive.box<Contract>(boxName(kContractsBox)).values,
        (contract) => contract.id == linked,
      );
      if (linkedContract != null && linkedContract.isActiveNow) {
        return;
      }
    }
    final invoicesBoxId = boxName(kInvoicesBox);
    final invoices = Hive.isBoxOpen(invoicesBoxId)
        ? Hive.box<Invoice>(invoicesBoxId).values
        : (await Hive.openBox<Invoice>(invoicesBoxId)).values;
    final rebuilt = rebuildWaterFixedConfigForContract(
      currentCfg: cfg,
      contract: c,
      invoices: invoices,
      totalWaterAmount: total,
    );
    await box.put(key, rebuilt);
  } catch (_) {}
}

/// خطوة دورة واحدة حسب دورة السداد
DateTime _stepOneCycle(DateTime d, PaymentCycle cycle) {
  final base = _dateOnly(d);
  switch (cycle) {
    case PaymentCycle.monthly:
      return DateTime(base.year, base.month + 1, base.day);
    case PaymentCycle.quarterly:
      return DateTime(base.year, base.month + 3, base.day);
    case PaymentCycle.semiAnnual:
      return DateTime(base.year, base.month + 6, base.day);
    case PaymentCycle.annual:
      return DateTime(base.year + 1, base.month, base.day);
  }
}

/// كوّن قائمة بكل الاستحقاقات غير المدفوعة من أقدم غير مدفوع حتى "اليوم"
List<DateTime> _buildUnpaidStack(Contract c) {
  final List<DateTime> out = [];
  if (c.term == ContractTerm.daily) return out;

  final first = _earliestUnpaidDueDate(c); // أقدم غير مدفوع فعليًا
  if (first == null) return out;

  final todayOnly = _dateOnly(SaTimeLite.now());
  final endOnly = _dateOnly(c.endDate);
  var cursor = _dateOnly(first);

  while (cursor.isBefore(endOnly) && !cursor.isAfter(todayOnly)) {
    if (!_paidForDue(c, cursor)) out.add(cursor);
    cursor = _dateOnly(_addMonths(cursor, _monthsPerCycleFor(c)));
  }
  return out;
}

bool _hasStarted(Contract c) {
  if (c.term == ContractTerm.daily) {
    return !SaTimeLite.now().isBefore(c.dailyStartBoundary);
  }
  return !_dateOnly(SaTimeLite.now()).isBefore(_dateOnly(c.startDate));
}
bool _endsToday(Contract c) {
  if (c.isTerminated) return false;
  final now = SaTimeLite.now();
  final today = _dateOnly(now);
  final endOnly = _dateOnly(c.endDate);

  if (c.term == ContractTerm.daily) {
    return today == endOnly &&
        !now.isBefore(c.dailyStartBoundary) &&
        now.isBefore(c.dailyEndBoundary);
  }

  return today == endOnly && !_dateOnly(now).isBefore(_dateOnly(c.startDate));
}

bool _hasEnded(Contract c) {
  if (c.term == ContractTerm.daily) {
    return !SaTimeLite.now().isBefore(c.dailyEndBoundary);
  }
  return _dateOnly(SaTimeLite.now()).isAfter(_dateOnly(c.endDate));
}

DateTime _resolveNonDailyEndDate(DateTime start, int months) {
  if (months <= 0) return _dateOnly(start);
  final startOnly = _dateOnly(start);
  final nextAnchor = _addMonths(startOnly, months);
  final hasMatchingDay = nextAnchor.day == startOnly.day;
  final resolved = hasMatchingDay
      ? nextAnchor.subtract(const Duration(days: 1))
      : nextAnchor;
  return _dateOnly(resolved);
}

/// نهاية غير اليومي:
/// إذا كان اليوم المماثل موجودًا في الفترة القادمة نطرح يومًا واحدًا،
/// وإذا لم يكن موجودًا نثبت على آخر يوم متاح بدون خصم.
DateTime _termEndInclusive(DateTime start, ContractTerm term) {
  final months = _monthsInTerm(term);
  return _resolveNonDailyEndDate(start, months);
}

DateTime _termEndInclusiveWithYears(
    DateTime start, ContractTerm term, int termYears) {
  final months = term == ContractTerm.annual
      ? 12 * (termYears <= 0 ? 1 : termYears)
      : _monthsInTerm(term);
  return _resolveNonDailyEndDate(start, months);
}

/// أول موعد استحقاق بعد احتساب الدفعة المقدّمة (إصلاح يغطي محاذاة دورة السداد)
DateTime? _firstDueAfterAdvance(Contract c) {
  if (c.term == ContractTerm.daily) return null;

  final start = _dateOnly(c.startDate);
  final end = _dateOnly(c.endDate);

  if (c.advanceMode == AdvanceMode.coverMonths) {
    final covered = _coveredMonthsByAdvance(c);
    final termMonths = _monthsInContract(c);

    // المقدم يغطي كامل مدة العقد
    if (covered >= termMonths) return null;

    final mpc = _monthsPerCycleFor(c); // أشهر كل قسط
    // اقفز لحد الدورة التالي بعد الأشهر المغطّاة: ceil(covered / mpc) * mpc
    final cyclesCovered = (covered / mpc).ceil();
    final first = _addMonths(start, cyclesCovered * mpc);

    if (!first.isBefore(start) && !first.isAfter(end)) {
      // يشمل first == end
      return first;
    }

    return null;
  }

  return start;
}

/// هل هناك سند مدفوعة بالكامل لهذا الاستحقاق؟
bool _paidForDue(Contract c, DateTime due) {
  try {
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return false;
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));
    final dOnly = _dateOnly(due);

    for (final inv in box.values) {
      // تجاهل سند "سداد مقدم عقد" فقط عند خصم المقدم من الإجمالي
      final note = (inv.note ?? '').toString();
      final isAdvanceInvoice = (c.advanceMode == AdvanceMode.deductFromTotal) &&
          note.contains('سداد مقدم عقد');

      if (_isPaidRentInvoiceForContract(c, inv) &&
          _dateOnly(inv.dueDate) == dOnly) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}

/// أوّل استحقاق غير مدفوع فعليًا (بعد احتساب المقدم)، وإلا null إن كانت كل الأقساط مدفوعة.
DateTime? _earliestUnpaidDueDate(Contract c) {
  if (c.term == ContractTerm.daily) return null;
  final first = _firstDueAfterAdvance(c);
  if (first == null) return null;

  final end = _dateOnly(c.endDate);
  final stepM = _monthsPerCycleFor(c);
  var cursor = _dateOnly(first);

  while (!cursor.isAfter(end)) {
    // شامل لليوم الأخير end
    if (!_paidForDue(c, cursor)) return cursor;
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }

  return null; // لا يوجد أقساط غير مدفوعة
}

/// يحسب أقرب استحقاق ≥ اليوم ضمن مدة العقد
DateTime? _nextDueDate(Contract c) {
  if (c.term == ContractTerm.daily) return null;
  final first = _firstDueAfterAdvance(c);
  if (first == null) return null;

  final end = _dateOnly(c.endDate);
  final today = _dateOnly(SaTimeLite.now());
  final step = _monthsPerCycleFor(c);
  var due = _dateOnly(first);

  while (due.isBefore(end)) {
    // رجّع أول قسط غير مدفوع ويكون اليوم أو بعده
    if (!_paidForDue(c, due) && !due.isBefore(today)) return due;
    due = _dateOnly(_addMonths(due, step));
  }
  return null;
}

/// تُرجِع نفس التاريخ إذا كان صالحًا كـ"دفعة قادمة"، وإلا null.
/// صالح = (التاريخ < نهاية العقد) && (غير مدفوع).
DateTime? _sanitizeUpcoming(Contract c, DateTime? candidate) {
  if (candidate == null) return null;
  final d = _dateOnly(candidate);

  // ملاحظة مهمة: نعتبر نهاية العقد حدًا "حصريًا"
  // أي أي تاريخ >= endDate يُعتبر خارج المدة (وهذا يحذف 16-11 في مثال الصورة).
  if (!d.isBefore(_dateOnly(c.endDate))) return null;

  // لو التاريخ هذا مدفوع أصلًا لا نعرضه كقادم
  if (_paidForDue(c, d)) return null;

  return d;
}

bool _isOverdue(Contract c) {
  if (c.isTerminated) return false;
  if (c.term == ContractTerm.daily) {
    // اليومي: متأخرة إذا لم تُسدَّد والبدء قبل اليوم
    if (_dailyAlreadyPaid(c)) return false;
    return _dateOnly(c.startDate).isBefore(_dateOnly(SaTimeLite.now()));
  }
  final d = _earliestUnpaidDueDate(c);
  if (d == null) return false;
  return _dateOnly(d).isBefore(_dateOnly(SaTimeLite.now()));
}

bool _isDueToday(Contract c) {
  if (!_hasStarted(c) || c.isTerminated) return false;
  if (c.term == ContractTerm.daily) {
    // اليومي: مستحقة فقط في يوم البداية إذا لم تُسدَّد
    return !_dailyAlreadyPaid(c) &&
        _dateOnly(c.startDate) == _dateOnly(SaTimeLite.now());
  }
  final d = _earliestUnpaidDueDate(c);
  if (d == null) return false;
  return _dateOnly(d) == _dateOnly(SaTimeLite.now());
}

// تُستخدم في الفلترة فقط: تشمل العقود المنتهية أيضًا

bool _isDueTodayForFilter(Contract c) {
  final today = _dateOnly(SaTimeLite.now());

  if (c.term == ContractTerm.daily) {
    // اليومي: مستحقة فقط في يوم البداية إذا لم تُسدَّد
    return !_dailyAlreadyPaid(c) && _dateOnly(c.startDate) == today;
  }

  // أول قسط غير مدفوع "اليوم أو بعده"
  final d = _earliestUnpaidDueDate(c);
  if (d == null) return false;
  return _dateOnly(d) == today; // مستحقة = نفس تاريخ اليوم
}

bool _isOverdueForFilter(Contract c) {
  final today = _dateOnly(SaTimeLite.now());

  if (c.term == ContractTerm.daily) {
    // اليومي: متأخرة إذا لم تُسدَّد وكان البدء قبل اليوم
    return !_dailyAlreadyPaid(c) && _dateOnly(c.startDate).isBefore(today);
  }

  // نحتاج أي قسط غير مدفوع "قبل اليوم"
  // ملاحظة: _earliestUnpaidDueDate تُرجع اليوم أو بعده فقط،
  // لذلك نتحقق بالتكرار إلى ما قبل اليوم.
  final first = _firstDueAfterAdvance(c);
  if (first == null) return false;

  final endOnly = _dateOnly(c.endDate);
  var due = _dateOnly(first);

  while (due.isBefore(endOnly) && due.isBefore(today)) {
    if (!_paidForDue(c, due)) return true; // وجدنا قسطًا غير مدفوع قبل اليوم
    // تقدم دورة واحدة
    due = _dateOnly(_addMonths(due, _monthsPerCycleFor(c)));
  }
  return false;
}

bool isContractOverdueForHome(Contract c) => _isOverdueForFilter(c);

bool _isDueSoon(Contract c) {
  // "قاربت (دفعات)" يجب أن تنطبق على الأقساط المستقبلية فقط،
  // بغض النظر عن وجود متأخرات قديمة.
  if (!_hasStarted(c) || c.isTerminated) return false;
  if (c.term == ContractTerm.daily) {
    return false; // استبعاد اليومي من "قاربت (دفعات)"
  }

  // احصل على أول قسط غير مدفوع بتاريخ اليوم أو بعده
  final next = _sanitizeUpcoming(c, _nextDueDate(c));
  if (next == null) return false; // مافيه قسط قادم صالح

  final today = _dateOnly(SaTimeLite.now());
  final diff = _dateOnly(next).difference(today).inDays;
  final window = _nearWindowDaysForContract(c);

  // "قاربت" = داخل النافذة 1..window (يستثني اليوم)
  return diff >= 1 && diff <= window;
}

bool _isNearContractEnd(Contract c) {
  if (!c.isActiveNow || c.isTerminated) return false;
  if (_endsToday(c)) return false;

  final today = _dateOnly(SaTimeLite.now());
  final end = _dateOnly(c.endDate);
  final diff = end.difference(today).inDays;

  // اليومي: "قارب" يظهر في اليوم السابق (diff=1) ويوم الانتهاء (diff=0)
  if (c.term == ContractTerm.daily) {
    return diff >= 0 && diff <= 1;
  }

  // باقي العقود كما هي
  final window = _nearEndWindowDays(c);
  return diff >= 0 && diff <= window;
}

/// تاريخ الاستحقاق الذي نعرضه للمستخدم (أقدم غير مدفوع، أو القادم)
DateTime? _displayDueDate(Contract c) {
  if (c.term == ContractTerm.daily) return null;
  return _earliestUnpaidDueDate(c);
}

int _expectedInstallments(Contract c) {
  if (c.term == ContractTerm.daily) return 1;
  final months = _monthsInContract(c);
  final per = _monthsPerCycleFor(c);
  return (months / per).ceil().clamp(1, 1000);
}

int _paidInstallments(Contract c) {
  try {
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return 0;
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));

    // نستبعد سند "سداد مقدم عقد" فقط في حالة deductFromTotal
    bool isAdvanceInvoice(Invoice i) {
      if (c.advanceMode != AdvanceMode.deductFromTotal) return false;
      final n = (i.note ?? '').toString();
      return n.contains('سداد مقدم عقد');
    }

    // نعدّ السندات غير الملغاة والمدفوعة بالكامل باستثناء سند المقدم
    return box.values
        .where((i) =>
            i.contractId == c.id &&
            !i.isCanceled &&
            (i.paidAmount >= i.amount - 0.000001) &&
            !isAdvanceInvoice(i) &&
            !_isOfficeCommissionInvoice(i))
        .length;
  } catch (_) {
    return 0;
  }
}

bool _allInstallmentsPaid(Contract c) {
  // اليومي = قسط واحد
  return c.term == ContractTerm.daily
      ? _dailyAlreadyPaid(c)
      : _earliestUnpaidDueDate(c) == null;
}

double _perCycleAmount(Contract c) {
  if (c.term == ContractTerm.daily) return c.totalAmount;
  final months = _monthsInContract(c);
  final perCycleCount = (months / _monthsPerCycleFor(c)).ceil().clamp(1, 1000);
  if (c.advanceMode == AdvanceMode.deductFromTotal) {
    final net =
        (c.totalAmount - (c.advancePaid ?? 0)).clamp(0, double.infinity);
    return net / perCycleCount;
  } else {
    return c.totalAmount / perCycleCount;
  }
}

String _dueStatus(DateTime due) {
  final t = _dateOnly(SaTimeLite.now());
  if (due.isAtSameMomentAs(t)) return 'سداد اليوم';
  if (due.isBefore(t)) return 'متأخرة';
  return 'قادمة';
}

Color _dueStatusColor(String status) {
  switch (status) {
    case 'سداد اليوم':
      return const Color(0xFF0EA5E9);
    case 'متأخرة':
      return const Color(0xFFB91C1C);
    default:
      return const Color(0xFF065F46);
  }
}

int _inclusiveDays(DateTime a, DateTime b) =>
    _dateOnly(b).difference(_dateOnly(a)).inDays + 1;

int _daysUntil(DateTime d) =>
    _dateOnly(d).difference(_dateOnly(SaTimeLite.now())).inDays;

bool _isNearExpiry(Contract c, {int withinDays = 14}) {
  if (c.isTerminated) return false;
  if (!c.isActiveNow) return false;
  final d = _daysUntil(c.endDate);
  return d >= 0 && d <= withinDays; // خلال 14 يومًا افتراضيًا
}

/// =================================================================================
/// عناصر تصميم مشتركة
/// =================================================================================
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
              offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

/// بطاقة الدفعات بنفس ستايل بطاقة العقود
Widget _paymentCard(Widget child) => _DarkCard(
      padding: EdgeInsets.all(12.w),
      child: child,
    );

/// بطاقة ملاحظة/تنبيه بخلفية موحّدة
Widget _noteCard(String t) => _paymentCard(
      Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.white70, size: 18),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              t,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

String _limitChars(String t, int max) =>
    t.length <= max ? t : '${t.substring(0, max)}…';

/// الميلادي القياسي: yyyy-MM-dd
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// تحديد هل نعرض هجريًا من sessionBox
bool get _useHijri {
  if (!Hive.isBoxOpen('sessionBox')) return false;
  try {
    return Hive.box('sessionBox').get('useHijri', defaultValue: false) == true;
  } catch (_) {
    return false;
  }
}

/// تنسيق ديناميكي: هجري أو ميلادي للعرض فقط (التخزين يبقى ميلادي)
String _fmtDateDynamic(DateTime d) {
  if (!_useHijri) return _fmtDate(d);
  final h = HijriCalendar.fromDate(d);
  final yy = h.hYear.toString();
  final mm = h.hMonth.toString().padLeft(2, '0');
  final dd = h.hDay.toString().padLeft(2, '0');
  return '$yy-$mm-$dd هـ';
}

/// تقطيع إلى خانتين بدون زيادة
String _fmtMoneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
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

Widget _dateChip(String from, String to, {Color bg = const Color(0xFF1F2937)}) {
  const dateColor = Color(0xFF93C5FD); // لون أزرق فاتح مميز
  final baseStyle = GoogleFonts.cairo(
      color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700);
  final dateStyle = baseStyle.copyWith(color: dateColor);

  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10.r),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
    ),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'من ', style: baseStyle),
          TextSpan(text: from, style: dateStyle),
          TextSpan(text: ' إلى ', style: baseStyle),
          TextSpan(text: to, style: dateStyle),
        ],
      ),
    ),
  );
}

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

Widget _rowInfoWidget(String label, Widget child) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120.w,
          child: Text(
            label,
            style:
                GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: child),
      ],
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

// ===== إعدادات "قاربت" (Top-level) =====
int _cfgMonthlyDays = 7;
int _cfgQuarterlyDays = 15;
int _cfgSemiAnnualDays = 30;
int _cfgAnnualDays = 45;
Map<int, int> _cfgAnnualYearsDays = {for (var y = 1; y <= 10; y++) y: 45};
int _cfgContractMonthlyDays = 7;
int _cfgContractQuarterlyDays = 15;
int _cfgContractSemiAnnualDays = 30;
int _cfgContractAnnualDays = 45;
Map<int, int> _cfgContractAnnualYearsDays = {
  for (var y = 1; y <= 10; y++) y: 45
};

int _asInt(dynamic v, int f) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? f;
  return f;
}

int _cfgAnnualDaysForYears(int years) {
  final y = years <= 0 ? 1 : years;
  return (_cfgAnnualYearsDays[y] ?? _cfgAnnualDays).clamp(1, 45);
}

int _cfgContractAnnualDaysForYears(int years) {
  final y = years <= 0 ? 1 : years;
  return (_cfgContractAnnualYearsDays[y] ?? _cfgContractAnnualDays)
      .clamp(1, 45);
}

// نافذة "قاربت" حسب **دورة السداد** (وليس مدة العقد)
int _nearWindowDaysForContract(Contract c) {
  switch (c.paymentCycle) {
    case PaymentCycle.monthly:
      return _cfgMonthlyDays; // 1..7
    case PaymentCycle.quarterly:
      return _cfgQuarterlyDays; // 1..15
    case PaymentCycle.semiAnnual:
      return _cfgSemiAnnualDays; // 1..30
    case PaymentCycle.annual:
      return _cfgAnnualDaysForYears(c.paymentCycleYears); // 1..45
  }
}

int _nearEndWindowDays(Contract c) {
  switch (c.term) {
    case ContractTerm.daily:
      return 0;
    case ContractTerm.monthly:
      return _cfgContractMonthlyDays;
    case ContractTerm.quarterly:
      return _cfgContractQuarterlyDays;
    case ContractTerm.semiAnnual:
      return _cfgContractSemiAnnualDays;
    case ContractTerm.annual:
      return _cfgContractAnnualDaysForYears(c.termYears);
  }
}

// (توافق للأماكن التي تنادي بالـ Term مباشرة)
int _nearWindowDaysForTerm(ContractTerm term) {
  switch (term) {
    case ContractTerm.daily:
      return 0;
    case ContractTerm.monthly:
      return _cfgMonthlyDays;
    case ContractTerm.quarterly:
      return _cfgQuarterlyDays;
    case ContractTerm.semiAnnual:
      return _cfgSemiAnnualDays;
    case ContractTerm.annual:
      return _cfgAnnualDays;
  }
}

// اسم قديم ظهر في الخطأ — نخليه Alias للتوافق
int _dueSoonDaysForTerm(ContractTerm term) => _nearWindowDaysForTerm(term);

enum ContractQuickFilter {
  all,
  overdue,
  nearExpiry,
  active,
  inactive,
  nearContract,
  endsToday,
  ended,
  canceled,
  terminated,
  due,
  expired
}

_StatusFilter _statusFromQuick(ContractQuickFilter? f) {
  switch (f) {
    case ContractQuickFilter.overdue:
    case ContractQuickFilter.expired:
      return _StatusFilter.expired; // متأخرة
    case ContractQuickFilter.nearExpiry:
      return _StatusFilter.nearExpiry; // قاربت (دفعات)
    case ContractQuickFilter.active:
      return _StatusFilter.active;
    case ContractQuickFilter.inactive:
      return _StatusFilter.inactive;
    case ContractQuickFilter.nearContract:
      return _StatusFilter.nearContract; // عقد قارب على الانتهاء
    case ContractQuickFilter.endsToday:
      return _StatusFilter.endsToday;
    case ContractQuickFilter.ended:
      return _StatusFilter.ended;
    case ContractQuickFilter.canceled:
    case ContractQuickFilter.terminated:
      return _StatusFilter.canceled;
    case ContractQuickFilter.due:
      return _StatusFilter.due;
    case ContractQuickFilter.all:
    case null:
      return _StatusFilter.all;
  }
}

/// =================================================================================
/// شاشة قائمة العقود
/// =================================================================================
class ContractsScreen extends StatefulWidget {
  final ContractQuickFilter? initialFilter;
  final DateTimeRange? initialDateRange; // جديد لدعم التقارير
  const ContractsScreen({super.key, this.initialFilter, this.initialDateRange});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

// ======== واتساب: رقم + رسالة + فتح المحادثة ========

// يستخرج رقم الهاتف من Tenant بأمان حتى لو اسم الحقل مختلف (phone / phoneNumber / mobile)
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

// يحول الرقم إلى صيغة WhatsApp (wa.me) بدون علامة +
String? _waNumberE164(Tenant? t) {
  var raw = _tenantRawPhone(t);
  if (raw == null) return null;

  // digits only
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;

  // إزالة 00 من البداية إن وجدت
  if (d.startsWith('00')) d = d.substring(2);

  // إذا الرقم يبدأ بصفر محلياً، أزله وأضف 966 (افتراضي السعودية)
  if (d.startsWith('0')) d = d.substring(1);
  // إن لم يبدأ بكود دولة واضح (طول قصير)، أضف 966 كافتراضي
  final looksInternational = d.length >= 11; // غالباً 9665xxxxxxxx
  if (!looksInternational && !d.startsWith('966')) d = '966$d';

  // إن كان على شكل 9660... أصلحه
  if (d.startsWith('9660')) d = '966${d.substring(4)}';

  // تحقق أخير
  if (d.length < 9) return null;
  return d;
}

// يولّد نص الرسالة حسب الحالة: 'overdue' | 'due' | 'near'
// ❌ بدون رقم عقد
// ❌ بدون ذكر "لعقار ..." نهائيًا
// ✅ استبدال SAR بـ "ريال"
String _waMessage({
  required Contract c,
  required DateTime due,
  required String kind, // 'overdue' | 'due' | 'near'
  Tenant? tenant,
  Property? property, // لم نعد نستخدمه في النص
}) {
  final name = (tenant?.fullName.trim().isNotEmpty ?? false)
      ? tenant!.fullName.trim()
      : 'العميل';

  final curr = (c.currency ?? '').trim();
  final currLabel =
      curr.isEmpty ? 'ريال' : (curr.toLowerCase() == 'sar' ? 'ريال' : curr);

  final amount = _fmtMoneyTrunc(
    c.term == ContractTerm.daily ? c.totalAmount : _perCycleAmount(c),
  );

  final dateTxt = _fmtDateDynamic(due);

  switch (kind) {
    case 'due':
      return 'عزيزي المستأجر $name، لديك دفعة سداد مستحقة بتاريخ اليوم ($dateTxt) بقيمة $amount $currLabel. نرجو إكمال السداد اليوم. شكرًا.';
    case 'overdue':
      return 'عزيزي المستأجر $name، توجد عليك دفعة سداد متأخرة بتاريخ $dateTxt بقيمة $amount $currLabel. نرجو المبادرة بالسداد في أقرب وقت.';
    default: // 'near'
      return 'عزيزي المستأجر $name، تذكير: توجد دفعة إيجار قريبة بتاريخ $dateTxt بقيمة $amount $currLabel. نرجو ترتيب السداد في الوقت المناسب.';
  }
}

// يفتح محادثة واتساب عبر wa.me (يمرَّر له context بدل الاعتماد على mounted)
Future<void> _openWhatsAppToTenant(
    BuildContext context, Tenant? t, String message) async {
  final phone = _waNumberE164(t);
  if (phone == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('لا يوجد رقم واتساب صالح للمستأجر.',
              style: GoogleFonts.cairo())),
    );
    return;
  }
  final uri =
      Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذّر فتح واتساب.', style: GoogleFonts.cairo())),
    );
  }
}

class _ContractsScreenState extends State<ContractsScreen> {
  Box<Contract> get _contracts => Hive.box<Contract>(boxName(kContractsBox));
  Box<Tenant> get _tenants => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties => Hive.box<Property>(boxName(kPropertiesBox));

  String _q = '';
  String? _filterTenantId;
  String? _filterPreviousTenantName;
  String? _filterPropertyId;
  String? _filterPropertyName;
  bool _showPreviousPropertyContracts = false;
  bool _showPreviousTenantContracts = false;

  String get _contractsBoxName => HiveService.contractsBoxName();
  Box<Contract> get _box => Hive.box<Contract>(_contractsBoxName);

// فلاتر
  _ArchiveFilter _fArchive =
      _ArchiveFilter.notArchived; // الافتراضي: غير مؤرشفة
  _StatusFilter _fStatus = _StatusFilter.all;
  _TermFilter _fTerm = _TermFilter.all;
  DateTimeRange? _fDateRange; // جديد

  bool get _homePaymentsQuickScoped =>
      widget.initialFilter == ContractQuickFilter.overdue ||
      widget.initialFilter == ContractQuickFilter.nearExpiry;

  InputDecoration _dropdownDeco(String label) => InputDecoration(
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

  bool get _hasActiveFilters =>
      (_fArchive == _ArchiveFilter.archived) ||
      (_fStatus != _StatusFilter.all) ||
      (_fTerm != _TermFilter.all) ||
      (_filterTenantId != null) ||
      _showPreviousTenantContracts ||
      _showPreviousPropertyContracts;

  String _currentFilterLabel({
    bool hideArchive = false,
    bool hideScopeLabels = false,
  }) {
    final parts = <String>[];
    final filteredTenantName = _filterTenantId == null
        ? null
        : firstWhereOrNull(_tenants.values, (x) => x.id == _filterTenantId)
            ?.fullName
            .trim();
    if (!hideArchive) {
      parts.add(_fArchive == _ArchiveFilter.archived ? 'المؤرشفة' : 'الكل');
    }

// الحالة
    switch (_fStatus) {
      case _StatusFilter.active:
        parts.add('نشطة');
        break;
      case _StatusFilter.endsToday:
        parts.add('ينتهي اليوم');
        break;
      case _StatusFilter.nearContract:
        parts.add('عقد قارب');
        break; // ← أضِف هذا
      case _StatusFilter.nearExpiry:
        parts.add('قاربت');
        break; // (قاربت الدفعات)
      case _StatusFilter.due:
        parts.add('مستحقة');
        break;
      case _StatusFilter.expired:
        parts.add('متأخرة');
        break;
      case _StatusFilter.inactive:
        parts.add('غير نشطة');
        break;
      case _StatusFilter.ended:
        parts.add('منتهية');
        break;
      case _StatusFilter.canceled:
        parts.add('ملغية');
        break;
      case _StatusFilter.all:
        break;
    }

    // فترة العقد
    switch (_fTerm) {
      case _TermFilter.daily:
        parts.add('يومي');
        break;
      case _TermFilter.monthly:
        parts.add('شهري');
        break;
      case _TermFilter.quarterly:
        parts.add('ربع سنوي');
        break;
      case _TermFilter.semiAnnual:
        parts.add('نصف سنوي');
        break;
      case _TermFilter.annual:
        parts.add('سنوي');
        break;
      case _TermFilter.all:
        break;
    }
    if (!hideScopeLabels) {
      if (_filterTenantId != null) {
        parts.add(
          (filteredTenantName ?? '').isNotEmpty
              ? filteredTenantName!
              : 'مستأجر محدد',
        );
      }
      if (_showPreviousPropertyContracts || _showPreviousTenantContracts) {
        parts.add('عقود سابقة');
      }
    }
    return parts.join(' • ');
  }

  @override
  void initState() {
    super.initState();
    (() async {
      await HiveService.ensureReportsBoxesOpen();
      if (mounted) setState(() {}); // لو تحب تحدّث الواجهة بعد الفتح
    })();

    // ✅ طبّق الفلتر القادم من الرئيسية فورًا (بدون setState) لمنع الوميض
    _fStatus = _statusFromQuick(widget.initialFilter);
    if (_fStatus == _StatusFilter.ended || _fStatus == _StatusFilter.canceled) {
      _fArchive = _ArchiveFilter.archived;
    }
    _fDateRange = widget.initialDateRange; // جديد

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }

      await _autoReleaseExpiredOccupancies();
      _handleInitialRouteIntent(); // يفتح عقد معيّن إن طُلب عبر arguments
      await _loadNotifPrefs(); // تحميل إعدادات نافذة "قاربت"
      // ⛔️ لا تستدعِ هنا أي setState يغيّر _fStatus مرة ثانية
    });
  }

  void _openFilterSheet() {
    final historyScoped =
        _showPreviousPropertyContracts || _showPreviousTenantContracts;
    final tenantActiveScoped =
        !historyScoped && (_filterTenantId ?? '').trim().isNotEmpty;
    final hideArchiveControls =
        historyScoped || tenantActiveScoped || _homePaymentsQuickScoped;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        var tArchive = _fArchive;
        var tStatus = _fStatus;
        var tTerm = _fTerm;

        bool arch = tArchive == _ArchiveFilter.archived; // مثل شاشة المستأجرين

        return StatefulBuilder(
          builder: (context, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  16.h + MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                      child: Text('تصفية',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800))),
                  SizedBox(height: 12.h),

                  // الحالة
                  DropdownButtonFormField<_StatusFilter>(
                    initialValue: tStatus,
                    decoration: _dropdownDeco('الحالة'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(
                          value: _StatusFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _StatusFilter.active,
                          child: Text('عقود نشطة')),
                      DropdownMenuItem(
                          value: _StatusFilter.inactive,
                          child: Text('عقود غير نشطة')),
                      DropdownMenuItem(
                          value: _StatusFilter.nearContract,
                          child: Text('عقود قاربت')), // ← أضِف هذا
                      DropdownMenuItem(
                          value: _StatusFilter.endsToday,
                          child: Text('عقود تنتهي اليوم')),
                      DropdownMenuItem(
                          value: _StatusFilter.ended,
                          child: Text('عقود منتهية')),
                      DropdownMenuItem(
                          value: _StatusFilter.canceled,
                          child: Text('عقود ملغية')),
                      DropdownMenuItem(
                          value: _StatusFilter.nearExpiry,
                          child: Text('دفعات قاربت')), // (دفعات)
                      DropdownMenuItem(
                          value: _StatusFilter.due,
                          child: Text('دفعات مستحقة')),
                      DropdownMenuItem(
                          value: _StatusFilter.expired,
                          child: Text('دفعات متأخرة')),
                    ],
                    onChanged: (v) => setM(() {
                      tStatus = v ?? _StatusFilter.all;
                      arch = tStatus == _StatusFilter.ended ||
                          tStatus == _StatusFilter.canceled;
                    }),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                  SizedBox(height: 10.h),

                  // فترة العقد
                  DropdownButtonFormField<_TermFilter>(
                    initialValue: tTerm,
                    decoration: _dropdownDeco('فترة العقد'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(
                          value: _TermFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _TermFilter.daily, child: Text('يومي')),
                      DropdownMenuItem(
                          value: _TermFilter.monthly, child: Text('شهري')),
                      DropdownMenuItem(
                          value: _TermFilter.quarterly,
                          child: Text('ربع سنوي')),
                      DropdownMenuItem(
                          value: _TermFilter.semiAnnual,
                          child: Text('نصف سنوي')),
                      DropdownMenuItem(
                          value: _TermFilter.annual, child: Text('سنوي')),
                    ],
                    onChanged: (v) => setM(() => tTerm = v ?? _TermFilter.all),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),

                  if (!hideArchiveControls) ...[
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
                            label:
                                Text('غير مؤرشفة', style: GoogleFonts.cairo()),
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
                  ],

                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _fStatus = tStatus;
                              _fTerm = tTerm;
                              if (!hideArchiveControls) {
                                _fArchive = (tStatus == _StatusFilter.ended ||
                                        tStatus == _StatusFilter.canceled)
                                    ? _ArchiveFilter.archived
                                    : (arch
                                        ? _ArchiveFilter.archived
                                        : _ArchiveFilter.notArchived);
                              }
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          child: Text('تطبيق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _fStatus = _StatusFilter.all;
                              _fTerm = _TermFilter.all;
                              if (!hideArchiveControls) {
                                _fArchive = _ArchiveFilter.notArchived;
                              }
                            });
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24)),
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
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

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  // (جديد) تشغيل تحرير الإشغال لمرة واحدة عند فتح الشاشة
  bool _autoReleasedOnce = false;

  // (جديد) منع تكرار نية الفتح عبر arguments
  bool _handledInitialIntent = false;

  Future<void> _loadNotifPrefs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('user_prefs')
          .doc(uid)
          .get();
      final m = snap.data() ?? {};
      int yearDays(String key, int fallback) =>
          _asInt(m[key], fallback).clamp(1, 45);
      final annualYears = <int, int>{
        for (var y = 1; y <= 10; y++)
          y: yearDays(
              'notif_annual_${y}y_days', _asInt(m['notif_annual_days'], 45)),
      };
      final contractAnnualYears = <int, int>{
        for (var y = 1; y <= 10; y++)
          y: yearDays(
            'notif_contract_annual_${y}y_days',
            _asInt(m['notif_contract_annual_days'], annualYears[y] ?? 45),
          ),
      };

      setState(() {
        _cfgMonthlyDays = _asInt(m['notif_monthly_days'], 7).clamp(1, 7);
        _cfgQuarterlyDays = _asInt(m['notif_quarterly_days'], 15).clamp(1, 15);
        _cfgSemiAnnualDays =
            _asInt(m['notif_semiannual_days'], 30).clamp(1, 30);
        _cfgAnnualYearsDays = annualYears;
        _cfgAnnualDays = _cfgAnnualYearsDays[1] ?? 45;
        _cfgContractMonthlyDays =
            _asInt(m['notif_contract_monthly_days'], _cfgMonthlyDays)
                .clamp(1, 7);
        _cfgContractQuarterlyDays =
            _asInt(m['notif_contract_quarterly_days'], _cfgQuarterlyDays)
                .clamp(1, 15);
        _cfgContractSemiAnnualDays =
            _asInt(m['notif_contract_semiannual_days'], _cfgSemiAnnualDays)
                .clamp(1, 30);
        _cfgContractAnnualYearsDays = contractAnnualYears;
        _cfgContractAnnualDays =
            _cfgContractAnnualYearsDays[1] ?? _cfgAnnualDays;
      });

      if (Hive.isBoxOpen('sessionBox')) {
        final box = Hive.box('sessionBox');
        await box.put('notif_monthly_days', _cfgMonthlyDays);
        await box.put('notif_quarterly_days', _cfgQuarterlyDays);
        await box.put('notif_semiannual_days', _cfgSemiAnnualDays);
        await box.put('notif_annual_days', _cfgAnnualDays);
      }
    } catch (_) {
      // تجاهل — نستخدم الافتراضيات
    }
  }

  void _handleInitialRouteIntent() {
    if (_handledInitialIntent) return;
    _handledInitialIntent = true;

    final args = ModalRoute.of(context)?.settings.arguments;

    String? openPropertyId;
    String? openContractId;
    String? filterTenantId;
    String? filterPreviousTenantId;
    String? filterPreviousTenantName;
    String? filterPreviousPropertyId;
    String? filterPreviousPropertyName;

    if (args is String) {
      openPropertyId = args;
    } else if (args is Map) {
      final m = args.cast<String, dynamic>();
      openPropertyId = m['openPropertyId'] as String?;
      openContractId = m['openContractId'] as String?;
      filterTenantId = m['filterTenantId'] as String?;
      filterPreviousTenantId = m['filterPreviousTenantId'] as String?;
      filterPreviousTenantName = m['filterPreviousTenantName'] as String?;
      filterPreviousPropertyId = m['filterPreviousPropertyId'] as String?;
      filterPreviousPropertyName = m['filterPreviousPropertyName'] as String?;
    }

    // حفظ معيار التصفية إن وصل من شاشة المستأجر
    if (filterTenantId != null) {
      setState(() => _filterTenantId = filterTenantId);
    }

    if (filterPreviousTenantId != null &&
        filterPreviousTenantId.trim().isNotEmpty) {
      setState(() {
        _filterTenantId = filterPreviousTenantId!.trim();
        _filterPreviousTenantName =
            (filterPreviousTenantName ?? '').trim().isEmpty
                ? null
                : filterPreviousTenantName!.trim();
        _showPreviousTenantContracts = true;
      });
    }

    if (filterPreviousPropertyId != null &&
        filterPreviousPropertyId.trim().isNotEmpty) {
      setState(() {
        _filterPropertyId = filterPreviousPropertyId!.trim();
        _filterPropertyName = (filterPreviousPropertyName ?? '').trim().isEmpty
            ? null
            : filterPreviousPropertyName!.trim();
        _showPreviousPropertyContracts = true;
      });
    }

    // منطق فتح عقد معيّن أو حسب العقار (كما هو موجود سابقاً)
    Contract? target;
    if (_showPreviousPropertyContracts || _showPreviousTenantContracts) {
      target = null;
    } else if (openContractId != null) {
      target =
          firstWhereOrNull(_contracts.values, (c) => c.id == openContractId);
    } else if (openPropertyId != null) {
      final byProp = _contracts.values
          .where((c) => c.propertyId == openPropertyId && !c.isArchived)
          .toList();
      byProp.sort((a, b) => b.startDate.compareTo(a.startDate));
      target = firstWhereOrNull(byProp, (c) => c.isActiveNow) ??
          (byProp.isNotEmpty ? byProp.first : null);
    }

    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ContractDetailsScreen(contract: target!)));
      });
    }
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
        // أنت هنا
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final routeMap =
        routeArgs is Map ? routeArgs.cast<String, dynamic>() : null;
    final routePreviousTenantId =
        routeMap?['filterPreviousTenantId']?.toString().trim();
    final routePreviousTenantName =
        routeMap?['filterPreviousTenantName']?.toString().trim();
    final routePropertyId =
        routeMap?['filterPreviousPropertyId']?.toString().trim();
    final routePropertyName =
        routeMap?['filterPreviousPropertyName']?.toString().trim();
    final effectivePreviousTenantId = _showPreviousTenantContracts &&
            (_filterTenantId ?? '').isNotEmpty
        ? _filterTenantId
        : routePreviousTenantId;
    final effectivePreviousTenantName =
        (_filterPreviousTenantName ?? '').isNotEmpty
            ? _filterPreviousTenantName
            : ((routePreviousTenantName ?? '').isNotEmpty
                ? routePreviousTenantName
                : null);
    final effectivePropertyFilterId =
        (_filterPropertyId ?? '').isNotEmpty ? _filterPropertyId : routePropertyId;
    final effectivePropertyFilterName =
        (_filterPropertyName ?? '').isNotEmpty
            ? _filterPropertyName
            : ((routePropertyName ?? '').isNotEmpty ? routePropertyName : null);
    final tenantHistoryScoped =
        (effectivePreviousTenantId ?? '').isNotEmpty;
    final propertyHistoryScoped =
        (effectivePropertyFilterId ?? '').isNotEmpty;
    final historyScoped = propertyHistoryScoped || tenantHistoryScoped;
    final tenantActiveScoped =
        !historyScoped && (_filterTenantId ?? '').trim().isNotEmpty;
    final activeTenantName = tenantActiveScoped
        ? firstWhereOrNull(_tenants.values, (x) => x.id == _filterTenantId)
            ?.fullName
            .trim()
        : null;
    final filterSummaryText = _currentFilterLabel(
      hideArchive:
          historyScoped || tenantActiveScoped || _homePaymentsQuickScoped,
      hideScopeLabels: historyScoped || tenantActiveScoped,
    );
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
              historyScoped
                  ? 'عقود سابقة'
                  : (tenantActiveScoped ? 'عقود نشطة' : 'العقود'),
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20.sp)),
          actions: [
            IconButton(
              tooltip: 'تصفية',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
              onPressed: _openFilterSheet,
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
                // شريط البحث
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالمستأجر/العقار/المبلغ',
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

                // ⬅️ وسم ملخص الفلاتر — بعد البحث مباشرة
                if ((_hasActiveFilters || _homePaymentsQuickScoped) &&
                    filterSummaryText.isNotEmpty)
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
                              filterSummaryText,
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
                if (tenantActiveScoped)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B3D2E),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Text(
                          'المستأجر: ${activeTenantName ?? '—'}',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (propertyHistoryScoped)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF065F46),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Text(
                          'العقار: ${effectivePropertyFilterName ?? '—'}',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (tenantHistoryScoped)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4338CA),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Text(
                          'المستأجر: ${effectivePreviousTenantName ?? '—'}',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),

                // قائمة العقود
// قائمة العقود
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      Hive.box<Contract>(_contractsBoxName)
                          .listenable(), // اسمع تغييرات العقود
                      Hive.box<Invoice>(boxName(kInvoicesBox))
                          .listenable(), // ✅ اسمع تغييرات السندات
                    ]),
                    builder: (_, __) {
                      final box = Hive.box<Contract>(
                          _contractsBoxName); // استخدم نفس الصندوق كما كنت
                      final bypassArchiveFilter = historyScoped ||
                          tenantActiveScoped ||
                          _homePaymentsQuickScoped;
                      final effectiveArchiveFilter = bypassArchiveFilter
                          ? _ArchiveFilter.all
                          : _fArchive;
                      // ضع هنا نفس المحتوى الذي كان داخل builder سابقًا (فلترة/بحث/ترتيب/ ListView ...)
                      // فقط استبدل "box" الممرَّر سابقًا بالمتغير المحلي أعلاه.
                      // مثال: var items = box.values.toList();
                      // اجلب العقود
                      var items = box.values.toList();

                      // إزالة التكرار بالأمان
                      final byId = <String, Contract>{};
                      for (final c in items) {
                        byId[c.id] = c;
                      }
                      items = byId.values.toList();

                      // فلاتر الأرشفة
                      if (!bypassArchiveFilter) {
                        if (effectiveArchiveFilter ==
                            _ArchiveFilter.notArchived) {
                          items = items.where((c) => !c.isArchived).toList();
                        } else if (effectiveArchiveFilter ==
                            _ArchiveFilter.archived) {
                          items = items.where((c) => c.isArchived).toList();
                        }
                      }

                      // تصفية من شاشة المستأجر
                      if (_filterTenantId != null) {
                        items = items
                            .where((c) => c.tenantId == _filterTenantId)
                            .toList();
                      }

                      if (tenantHistoryScoped) {
                        final targetTenantId = effectivePreviousTenantId!;
                        items = items.where((c) {
                          final ended = _hasEnded(c) || c.isExpiredByTime;
                          return c.tenantId == targetTenantId &&
                              (c.isTerminated || ended);
                        }).toList();
                      }

                      if (propertyHistoryScoped) {
                        final targetPropertyId = effectivePropertyFilterId!;
                        items = items.where((c) {
                          final ended = _hasEnded(c) || c.isExpiredByTime;
                          return c.propertyId == targetPropertyId &&
                              (c.isTerminated || ended);
                        }).toList();
                      }

// فلتر الحالة
                      if (_fStatus != _StatusFilter.all) {
                        items = items.where((c) {
                          switch (_fStatus) {
                            case _StatusFilter.active:
                              return c
                                  .isActiveNow; // يظهر أي عقد نشط بغض النظر عن الدفعات أو قرب الانتهاء

                            case _StatusFilter.endsToday:
                              return _endsToday(c);

                            case _StatusFilter.nearContract:
                              return _isNearContractEnd(
                                  c); // الجديد: قرب انتهاء العقد

                            case _StatusFilter.nearExpiry:
                              return _isDueSoon(c); // قاربت "الدفعات" كما هي

                            case _StatusFilter.due:
                              return _isDueTodayForFilter(c);

                            case _StatusFilter.expired:
                              return _isOverdueForFilter(c);

                            case _StatusFilter.inactive:
                              return !c.isActiveNow &&
                                  !c.isTerminated &&
                                  !(_hasEnded(c) || c.isExpiredByTime) &&
                                  !_isOverdue(c) &&
                                  !_isDueToday(c) &&
                                  !_isDueSoon(c) &&
                                  !_isNearContractEnd(c);

                            case _StatusFilter.ended:
                              return !c.isTerminated &&
                                  (_hasEnded(c) || c.isExpiredByTime);

                            case _StatusFilter.canceled:
                              return c.isTerminated;

                            case _StatusFilter.all:
                              return true;
                          }
                        }).toList();
                      }

                      // فلتر فترة العقد
                      if (_fTerm != _TermFilter.all) {
                        ContractTerm target;
                        switch (_fTerm) {
                          case _TermFilter.daily:
                            target = ContractTerm.daily;
                            break;
                          case _TermFilter.monthly:
                            target = ContractTerm.monthly;
                            break;
                          case _TermFilter.quarterly:
                            target = ContractTerm.quarterly;
                            break;
                          case _TermFilter.semiAnnual:
                            target = ContractTerm.semiAnnual;
                            break;
                          case _TermFilter.annual:
                            target = ContractTerm.annual;
                            break;
                          case _TermFilter.all:
                            target = ContractTerm.monthly;
                            break; // لن تُستخدم
                        }
                        items = items.where((c) => c.term == target).toList();
                      }

                      // فلتر التاريخ (جديد لدعم التقارير)
                      if (_fDateRange != null) {
                        items = items.where((c) {
                          final start = _dateOnly(c.startDate);
                          final end = _dateOnly(c.endDate);
                          final fStart = _dateOnly(_fDateRange!.start);
                          final fEnd = _dateOnly(_fDateRange!.end);
                          // تداخل الفترات
                          return !start.isAfter(fEnd) && !end.isBefore(fStart);
                        }).toList();
                      }

                      // البحث (اسم مستأجر/عقار/مبلغ/رقم تسلسلي)
                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        items = items.where((c) {
                          final Tenant? t = firstWhereOrNull(
                              _tenants.values, (x) => x.id == c.tenantId);
                          final Property? p = firstWhereOrNull(
                              _properties.values, (x) => x.id == c.propertyId);
                          final tenantDisplayName = t?.fullName ??
                              _snapshotString(
                                  _snapshotMapOrNull(c.tenantSnapshot),
                                  'fullName') ??
                              effectivePreviousTenantName ??
                              '—';
                          final propertyDisplayName = p?.name ??
                              _snapshotString(
                                  _snapshotMapOrNull(c.propertySnapshot),
                                  'name') ??
                              effectivePropertyFilterName ??
                              '—';
                          final tn = tenantDisplayName.toLowerCase();
                          final pn = propertyDisplayName.toLowerCase();
                          final total = c.totalAmount.toString().toLowerCase();
                          final sn = (c.serialNo ?? '').toLowerCase();

                          bool serialMatch = false;
                          if (sn.isNotEmpty) {
                            if (sn.contains(q)) {
                              serialMatch = true;
                            } else {
                              final parts = q.split('-');
                              if (parts.length == 2) {
                                final left = parts[0].trim();
                                final rightNum = int.tryParse(parts[1].trim());
                                if (rightNum != null) {
                                  final padded =
                                      '$left-${rightNum.toString().padLeft(4, '0')}';
                                  serialMatch = (sn == padded);
                                }
                              }
                            }
                          }
                          return tn.contains(q) ||
                              pn.contains(q) ||
                              total.contains(q) ||
                              serialMatch;
                        }).toList();
                      }

                      // ترتيب
                      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                      // فارغة؟
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            propertyHistoryScoped
                                ? 'لا توجد عقود سابقة لهذا العقار'
                                : tenantHistoryScoped
                                    ? 'لا توجد عقود سابقة لهذا المستأجر'
                                : ((effectiveArchiveFilter ==
                                        _ArchiveFilter.archived)
                                    ? 'لا توجد عقود مؤرشفة'
                                    : 'لا توجد عقود'),
                            style: GoogleFonts.cairo(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      // القائمة
                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final c = items[i];
                          final number = (c.serialNo?.isNotEmpty == true)
                              ? c.serialNo!
                              : c.id; // ← أضِفه هنا

                          final Tenant? t = firstWhereOrNull(
                              _tenants.values, (x) => x.id == c.tenantId);
                          final Property? p = firstWhereOrNull(
                              _properties.values, (x) => x.id == c.propertyId);
                          final tenantDisplayName = t?.fullName ??
                              _snapshotString(
                                  _snapshotMapOrNull(c.tenantSnapshot),
                                  'fullName') ??
                              effectivePreviousTenantName ??
                              '—';
                          final propertyDisplayName = p?.name ??
                              _snapshotString(
                                  _snapshotMapOrNull(c.propertySnapshot),
                                  'name') ??
                              effectivePropertyFilterName ??
                              '—';

// حالة العقد نفسها فقط (لا علاقة لها بالدفعات)
                          String statusText;
                          Color statusColor;
                          final started = _hasStarted(c);
                          final ended = _hasEnded(c) || c.isExpiredByTime;

                          if (c.isTerminated) {
                            statusText = 'ملغي';
                            statusColor = const Color(0xFF7F1D1D);
                          } else if (ended) {
                            statusText = 'منتهي';
                            statusColor = const Color(0xFF7F1D1D);
                          } else if (_endsToday(c)) {
                            statusText = 'ينتهي اليوم';
                            statusColor = const Color(0xFFEA580C);
                          } else if (!started) {
                            statusText = 'غير نشطة (قبل البدء)';
                            statusColor = const Color(0xFF334155);
                          } else if (_isNearContractEnd(c)) {
                            // ← جديد: قرب انتهاء العقد
                            statusText = 'عقد قارب';
                            statusColor = const Color(0xFFF59E0B);
                          } else {
                            statusText = 'نشطة';
                            statusColor = const Color(0xFF065F46);
                          }

// --- حالة الدفعات (تلخيص متعدد يظهر أكثر من حالة معًا)
                          final todayOnly = _dateOnly(SaTimeLite.now());

// لغير اليومي: نبني كومة غير المسدّد حتى اليوم
                          final unpaidStack = (c.term == ContractTerm.daily)
                              ? <DateTime>[]
                              : _buildUnpaidStack(c);

// متأخرة
                          final startOnly = _dateOnly(c.startDate);
                          final bool hasOverdue = (c.term == ContractTerm.daily)
                              ? (!_dailyAlreadyPaid(c) &&
                                  startOnly.isBefore(
                                      todayOnly)) // اليومي: غير مسدّد وبداية قبل اليوم
                              : unpaidStack
                                  .any((d) => _dateOnly(d).isBefore(todayOnly));

// مستحقة (اليوم)
                          final bool hasDueToday = (c.term ==
                                  ContractTerm.daily)
                              ? (!_dailyAlreadyPaid(c) &&
                                  startOnly ==
                                      todayOnly) // اليومي: غير مسدّد واليوم هو يوم البداية
                              : unpaidStack
                                  .any((d) => _dateOnly(d) == todayOnly);

// قاربت (القسط التالي بعد الكومة ضمن النافذة)
                          DateTime? nextAfterStack;
                          if (c.term != ContractTerm.daily &&
                              !_allInstallmentsPaid(c)) {
                            nextAfterStack = unpaidStack.isNotEmpty
                                ? _dateOnly(_addMonths(
                                    unpaidStack.last, _monthsPerCycleFor(c)))
                                : _nextDueDate(c);
                          }
                          nextAfterStack = _sanitizeUpcoming(c, nextAfterStack);

                          final bool hasNearing = (c.term == ContractTerm.daily)
                              ? _isDueSoon(c) // اليومي: باقي يوم واحد
                              : (() {
                                  if (nextAfterStack == null) return false;
                                  final d = _dateOnly(nextAfterStack);
                                  final diff = d.difference(todayOnly).inDays;
                                  final window = _nearWindowDaysForContract(c);
                                  return diff >= 1 && diff <= window;
                                })();

                          final showOverdueChip = started && hasOverdue;
                          final showDueTodayChip = started && hasDueToday;
                          final showNearingChip = started &&
                              !ended &&
                              !c.isTerminated &&
                              hasNearing &&
                              c.term != ContractTerm.daily;
                          final hasSecondaryStatusChips = showOverdueChip ||
                              showDueTodayChip ||
                              showNearingChip;

                          return InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ContractDetailsScreen(contract: c)),
                              );
                            },
                            onLongPress: () async {
                              // 🚫 منع عميل المكتب من الأرشفة / فكّ الأرشفة من قائمة العقود
                              if (await OfficeClientGuard.blockIfOfficeClient(
                                  context)) {
                                return;
                              }

                              if (c.isArchived) {
                                await _showArchiveNoticeDialog(
                                  context,
                                  message:
                                      'لا يمكن إلغاء الأرشفة، العقود الملغاة والمنتهية تتأرشف تلقائيًا.',
                                );
                                return;
                              }

                              if (!c.isArchived && !c.isTerminated) {
                                await _showArchiveNoticeDialog(
                                  context,
                                  message:
                                      'لا يمكن الأرشفة، العقود الملغاة والمنتهية تتأرشف تلقائيًا.',
                                );

                                return;
                              }

                              // الحالة الجديدة للأرشفة (true = مؤرشف، false = غير مؤرشف)
                              final newArchived = !c.isArchived;
                              c.isArchived = newArchived;
                              await c.save();

                              // 🔁 مزامنة حالة الأرشفة مع سندات هذا العقد (يبقى كما هو عندك)
                              try {
                                if (Hive.isBoxOpen(boxName(kInvoicesBox))) {
                                  final invBox =
                                      Hive.box<Invoice>(boxName(kInvoicesBox));
                                  for (final inv in invBox.values) {
                                    try {
                                      if (inv.contractId == c.id) {
                                        inv.isArchived = newArchived;
                                        await inv.save();
                                      }
                                    } catch (_) {}
                                  }
                                }
                              } catch (_) {}

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      newArchived
                                          ? 'تمت أرشفة العقد وسنداته'
                                          : 'تم إلغاء الأرشفة عن العقد وسنداته',
                                      style: GoogleFonts.cairo(),
                                    ),
                                  ),
                                );
                              }
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
                                        end: Alignment.bottomLeft,
                                      ),
                                    ),
                                    child: const Icon(Icons.description_rounded,
                                        color: Colors.white),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tenantDisplayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.cairo(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15.sp,
                                                  ),
                                                ),
                                                SizedBox(height: 2.h),
                                                Text(
                                                  propertyDisplayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.cairo(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13.sp,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          _chip(statusText, bg: statusColor),
                                        ]),
                                        SizedBox(height: 6.h),
                                        Wrap(
                                          spacing: 6.w,
                                          runSpacing: 6.h,
                                          children: [
                                            _chip(
                                                'العقد: ${_termLabelForContract(c)}',
                                                bg: const Color(0xFF1F2937)),
                                            if (c.term != ContractTerm.daily)
                                              _chip(
                                                  'الدفع: ${_paymentCycleLabelForContract(c)}',
                                                  bg: const Color(0xFF1F2937)),
                                            _dateChip(
                                                _fmtDateDynamic(c.startDate),
                                                _fmtDateDynamic(c.endDate)),
                                            if (hasSecondaryStatusChips)
                                              const SizedBox(
                                                width: double.infinity,
                                                height: 0,
                                              ),
                                            if (showOverdueChip)
                                              _chip('متأخرة',
                                                  bg: const Color(0xFF7F1D1D)),
                                            if (showDueTodayChip)
                                              _chip('مستحقة',
                                                  bg: const Color(0xFF0EA5E9)),
                                            if (showNearingChip)
                                              _chip('قاربت',
                                                  bg: const Color(0xFFB45309)),
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
                // ====== نهاية القائمة ======
              ],
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.note_add_rounded),
          label: Text('إضافة عقد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            // 🚫 منع عميل المكتب من إضافة عقد
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final created = await Navigator.of(context).push<Contract?>(
              MaterialPageRoute(
                  builder: (_) => const AddOrEditContractScreen()),
            );

            if (created != null) {
              // ✅ احفظ بنفس المعرّف لضمان تشغيل المزامنة بدون ازدواج
              await _box.put(created.id, created);

              // (اختياري) منطقك الحالي بعد الإضافة: إشغال العقار، تحديث عدّاد المستأجر...
              await _onContractCreated(created);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم إضافة العقد', style: GoogleFonts.cairo()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContractDetailsScreen(contract: created),
                ),
              );
            }
          },
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 3,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Future<void> _autoReleaseExpiredOccupancies() async {
    if (_autoReleasedOnce) return;
    _autoReleasedOnce = true;

    final now = SaTimeLite.now();
    final today = _dateOnly(now);

    final Box<Property> propsBox = Hive.box<Property>(boxName(kPropertiesBox));
    final Box<Contract> contBox = Hive.box<Contract>(boxName(kContractsBox));
    final Box<Tenant> tenantsBox = Hive.box<Tenant>(boxName(kTenantsBox));

    for (final c in contBox.values) {
      // إذا العقد مُنهى مسبقًا تجاهله
      if (c.isTerminated) continue;

      // انتهت مدة العقد؟ (بعد مرور يوم endDate كاملًا لغير اليومي)
      final ended = c.isExpiredByTime;
      if (!ended) continue;

      // 1) فك إشغال العقار إذا لم يعد هناك عقد نشط عليه
      final prop =
          firstWhereOrNull(propsBox.values, (p) => p.id == c.propertyId);
      if (prop != null) {
        // هل يوجد أي عقد نشط حاليًا على نفس العقار؟
        final hasActive = contBox.values.any((cc) =>
            !cc.isTerminated &&
            cc.propertyId == c.propertyId &&
            cc.isActiveNow);

        if (!hasActive) {
          if (prop.parentBuildingId != null) {
            if (prop.occupiedUnits != 0) {
              prop.occupiedUnits = 0;
              await prop.save();
              await _recalcBuildingOccupiedUnits(prop.parentBuildingId!);
            }
          } else {
            if (prop.occupiedUnits != 0) {
              prop.occupiedUnits = 0;
              await prop.save();
            }
          }
        }
      }

      // 2) إنهاء العقد كما لو تم الضغط على زر "إنهاء"
      final building = prop?.parentBuildingId == null
          ? null
          : firstWhereOrNull(
              propsBox.values, (x) => x.id == prop!.parentBuildingId);
      final t = firstWhereOrNull(tenantsBox.values, (x) => x.id == c.tenantId);
      _applyContractSnapshots(
        c,
        tenant: t,
        property: prop,
        building: building,
        overwrite: true,
      );
      c.isTerminated = true;
      c.isArchived = true; // المنتهي يُؤرشف تلقائيًا
      c.terminatedAt = now;
      c.updatedAt = now;
      await c.save();
      await _resetPeriodicServicesForProperty(c.propertyId);

      // 3) إنقاص عدّاد العقود النشطة للمستأجر (إن كان > 0)
      if (t != null && t.activeContractsCount > 0) {
        t.activeContractsCount -= 1;
        t.updatedAt = now;
        await t.save();
      }
    }
  }

  Future<void> _onContractCreated(Contract c) async {
    final prop =
        firstWhereOrNull(_properties.values, (p) => p.id == c.propertyId);
    if (prop != null) await _occupyProperty(prop);

    final t = firstWhereOrNull(_tenants.values, (x) => x.id == c.tenantId);
    if (t != null && c.isActiveNow) {
      t.activeContractsCount += 1;
      t.updatedAt = SaTimeLite.now();
      await t.save();
    }

    // ربط تلقائي لإعدادات المياه بالعقد الجديد
    await linkWaterConfigToContractIfNeeded(c);
  }

  Future<void> _occupyProperty(Property p) async {
    if (p.parentBuildingId != null) {
      p.occupiedUnits = 1;
      await p.save();
      await _recalcBuildingOccupiedUnits(p.parentBuildingId!);
    } else {
      p.occupiedUnits = 1;
      await p.save();
    }
  }

  Future<void> _recalcBuildingOccupiedUnits(String buildingId) async {
    final all = Hive.box<Property>(boxName(kPropertiesBox))
        .values
        .where((e) => e.parentBuildingId == buildingId);
    final count = all.where((e) => e.occupiedUnits > 0).length;
    final building = firstWhereOrNull(
        Hive.box<Property>(boxName(kPropertiesBox)).values,
        (e) => e.id == buildingId);
    if (building != null) {
      building.occupiedUnits = count;
      await building.save();
    }
  }
}

/// =================================================================================
/// تفاصيل العقد
/// =================================================================================
class ContractDetailsScreen extends StatefulWidget {
  final Contract contract;
  const ContractDetailsScreen({super.key, required this.contract});

  @override
  State<ContractDetailsScreen> createState() => _ContractDetailsScreenState();
}

class _ContractDetailsScreenState extends State<ContractDetailsScreen> {
  Box<Contract> get _contracts => Hive.box<Contract>(boxName(kContractsBox));
  Box<Tenant> get _tenants => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties => Hive.box<Property>(boxName(kPropertiesBox));
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;
  bool _snapshotBackfillAttempted = false;

  DateTime? _overrideNextDue; // نعتبر القسط التالي بعد السداد مباشرة (عرض محلي)

  DateTime? _effectiveNextDue(Contract c) =>
      _overrideNextDue ?? _nextDueDate(c);

  bool _isContractInactive(Contract c) =>
      c.isTerminated || _hasEnded(c) || c.isExpiredByTime;

  Map<String, dynamic>? _resolvedTenantSnapshot(Contract c, Tenant? tenant) {
    return _snapshotMapOrNull(c.tenantSnapshot) ??
        (tenant == null ? null : _buildTenantSnapshot(tenant));
  }

  Map<String, dynamic>? _resolvedPropertySnapshot(
      Contract c, Property? property) {
    return _snapshotMapOrNull(c.propertySnapshot) ??
        (property == null ? null : _buildPropertySnapshot(property));
  }

  Map<String, dynamic>? _resolvedBuildingSnapshot(
      Contract c, Property? property, Property? building) {
    return _snapshotMapOrNull(c.buildingSnapshot) ??
        (building == null ? null : _buildPropertySnapshot(building));
  }

  Future<void> _ensureInactiveContractSnapshotsBackfilled() async {
    if (_snapshotBackfillAttempted) return;
    _snapshotBackfillAttempted = true;

    var contract = widget.contract;
    final live = firstWhereOrNull(_contracts.values, (c) => c.id == contract.id);
    if (live != null) {
      contract = live;
    }
    if (!_isContractInactive(contract)) return;

    final tenant =
        firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
    final property =
        firstWhereOrNull(_properties.values, (x) => x.id == contract.propertyId);
    final building = property?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (x) => x.id == property!.parentBuildingId);
    final changed = _applyContractSnapshots(
      contract,
      tenant: tenant,
      property: property,
      building: building,
      overwrite: false,
    );
    if (!changed) return;

    if (contract.isInBox) {
      contract.updatedAt = SaTimeLite.now();
      await contract.save();
    }
    if (mounted) setState(() {});
  }

  Future<void> _renewContract(BuildContext context, Contract contract) async {
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    final created = await Navigator.of(context).pushNamed(
      '/contracts/new',
      arguments: {'renewFromContract': contract},
    );

    if (!mounted || created is! Contract) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractDetailsScreen(contract: created),
      ),
    );

    if (mounted) setState(() {});
  }

// عرض اسم العملة للمستخدم (مثلاً: SAR => ريال)
  String _displayCurrency(String c) {
    try {
      if (c.toUpperCase() == 'SAR') return 'ريال';
    } catch (_) {}
    return c;
  }

  Map<String, dynamic> _waterCfgForProperty(String propertyId) {
    try {
      final bName = boxName('servicesConfig');
      if (!Hive.isBoxOpen(bName)) return const <String, dynamic>{};
      final box = Hive.box<Map>(bName);
      final raw = box.get('$propertyId::water');
      if (raw is! Map) return const <String, dynamic>{};
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);

  double _waterInstallmentAmountForDue(Contract c, DateTime due) {
    final cfg = _waterCfgForProperty(c.propertyId);
    if (cfg.isEmpty) return 0.0;
    final mode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '').toString();
    final method =
        (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '').toString();
    if (mode != 'shared') return 0.0;
    if (method != 'fixed') return 0.0;
    final linked = (cfg['waterLinkedContractId'] ?? '').toString();
    if (linked.isNotEmpty && linked != c.id) return 0.0;
    final rows = cfg['waterInstallments'];
    if (rows is! List) return 0.0;
    final dueIso = _d0(due).toIso8601String();
    for (final row in rows) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final rowDue = (m['dueDate'] ?? '').toString();
      if (rowDue != dueIso) continue;
      final status = (m['status'] ?? '').toString();
      if (status == 'paid') return 0.0;
      return ((m['amount'] as num?)?.toDouble() ?? 0.0);
    }
    return 0.0;
  }

  Future<void> _markWaterInstallmentPaid(
      Contract c, DateTime due, String invoiceId) async {
    try {
      final bName = boxName('servicesConfig');
      if (!Hive.isBoxOpen(bName)) return;
      final box = Hive.box<Map>(bName);
      final key = '${c.propertyId}::water';
      final raw = box.get(key);
      if (raw is! Map) return;
      final cfg = Map<String, dynamic>.from(raw);
      if ((cfg['waterBillingMode'] ?? '').toString() != 'shared') return;
      if ((cfg['waterSharedMethod'] ?? '').toString() != 'fixed') return;
      if ((cfg['waterLinkedContractId'] ?? '').toString() != c.id) return;
      final rowsRaw = cfg['waterInstallments'];
      if (rowsRaw is! List) return;
      final dueIso = _d0(due).toIso8601String();
      final rows = rowsRaw
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
      for (final row in rows) {
        if ((row['dueDate'] ?? '').toString() == dueIso) {
          row['status'] = 'paid';
          row['invoiceId'] = invoiceId;
        }
      }
      Map<String, dynamic>? next;
      for (final row in rows) {
        if ((row['status'] ?? '').toString() != 'paid') {
          next = row;
          break;
        }
      }
      cfg['waterInstallments'] = rows;
      cfg['remainingInstallmentsCount'] =
          rows.where((r) => (r['status'] ?? '').toString() != 'paid').length;
      cfg['nextDueDate'] = (next?['dueDate'] ?? '').toString();
      await box.put(key, cfg);
    } catch (_) {}
  }

  ({double total, double per})? _waterTotalsForContract(Contract c) {
    try {
      final boxId = boxName('servicesConfig');
      if (!Hive.isBoxOpen(boxId)) return null;
      final box = Hive.box<Map>(boxId);
      final raw = box.get('${c.propertyId}::water');
      if (raw is! Map) return null;

      final cfg = Map<String, dynamic>.from(raw);
      final mode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '').toString();
      final method =
          (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '').toString();
      if (mode != 'shared' || method != 'fixed') return null;

      final linked = (cfg['waterLinkedContractId'] ?? '').toString();
      if (linked.isNotEmpty && linked != c.id) return null;

      final rowsRaw = cfg['waterInstallments'];
      final rows = rowsRaw is List
          ? rowsRaw
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
              .whereType<Map<String, dynamic>>()
              .toList()
          : const <Map<String, dynamic>>[];

      final hasAnyWaterInstallment = rows.any(
        (r) => ((r['amount'] as num?)?.toDouble() ?? 0.0) > 0,
      );
      if (!hasAnyWaterInstallment) return null;

      final total = ((cfg['totalWaterAmount'] as num?)?.toDouble() ??
          (cfg['waterTotalAmount'] as num?)?.toDouble() ??
          rows.fold<double>(
            0.0,
            (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0),
          ));

      var per = ((cfg['waterPerInstallment'] as num?)?.toDouble() ?? 0.0);
      if (per <= 0) {
        final firstPositive = firstWhereOrNull(
          rows,
          (r) => ((r['amount'] as num?)?.toDouble() ?? 0.0) > 0,
        );
        per = ((firstPositive?['amount'] as num?)?.toDouble() ?? 0.0);
      }

      if (total <= 0 || per <= 0) return null;
      return (total: total, per: per);
    } catch (_) {
      return null;
    }
  }

  String _waterSummaryText(Contract c) {
    final totals = _waterTotalsForContract(c);
    if (totals == null) return '';
    return '\u0627\u0644\u0645\u064a\u0627\u0647: \u0625\u062c\u0645\u0627\u0644\u064a ${_fmtMoneyTrunc(totals.total)} \u2014 \u0627\u0644\u0642\u0633\u0637 ${_fmtMoneyTrunc(totals.per)} \u0644\u0643\u0644 \u062f\u0641\u0639\u0629';
  }

  Future<void> _autoTerminateIfEnded(Contract c) async {
    // إذا انتهى وقت العقد بعد مرور يوم endDate كاملًا ولم يُنهَ بعد ⇒ أنهِه فعليًا
    if (c.isTerminated) return;
    if (!c.isExpiredByTime) return;

    final propsBox = Hive.box<Property>(boxName(kPropertiesBox));
    final contBox = Hive.box<Contract>(boxName(kContractsBox));
    final tenantsBox = Hive.box<Tenant>(boxName(kTenantsBox));

    // حرر إشغال العقار فقط إن لم يعد هناك عقد نشط آخر على نفس العقار
    final prop = firstWhereOrNull(propsBox.values, (p) => p.id == c.propertyId);
    final building = prop?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            propsBox.values, (x) => x.id == prop!.parentBuildingId);
    final t = firstWhereOrNull(tenantsBox.values, (x) => x.id == c.tenantId);
    _applyContractSnapshots(
      c,
      tenant: t,
      property: prop,
      building: building,
      overwrite: true,
    );

    if (prop != null) {
      final hasActive = contBox.values.any((cc) =>
          !cc.isTerminated && cc.propertyId == c.propertyId && cc.isActiveNow);
      if (!hasActive) {
        if (prop.parentBuildingId != null) {
          if (prop.occupiedUnits != 0) {
            prop.occupiedUnits = 0;
            await prop.save();
            // أعِد حساب إشغال البناية
            final siblings = propsBox.values
                .where((e) => e.parentBuildingId == prop.parentBuildingId);
            final count = siblings.where((e) => e.occupiedUnits > 0).length;
            final building = firstWhereOrNull(
                propsBox.values, (e) => e.id == prop.parentBuildingId);
            if (building != null) {
              building.occupiedUnits = count;
              await building.save();
            }
          }
        } else {
          if (prop.occupiedUnits != 0) {
            prop.occupiedUnits = 0;
            await prop.save();
          }
        }
      }
    }

    // أعلِم العقد والمستأجر
    final now = SaTimeLite.now();
    c.isTerminated = true;
    c.isArchived = true; // المنتهي يُؤرشف تلقائيًا
    c.terminatedAt = now;
    c.updatedAt = now;
    await c.save();
    await _resetPeriodicServicesForProperty(c.propertyId);

    if (t != null && t.activeContractsCount > 0) {
      t.activeContractsCount -= 1;
      t.updatedAt = now;
      await t.save();
    }

    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();

    (() async {
      await HiveService.ensureReportsBoxesOpen();
      final ejarBox = boxName(_kContractsEjarNoBox);
      if (!Hive.isBoxOpen(ejarBox)) {
        await Hive.openBox<String>(ejarBox);
      }
      await openServicesConfigBox();
      if (mounted) setState(() {});
    })();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ✅ إنهاء تلقائي فعلي إذا التاريخ تعدّى نهاية العقد
      await _autoTerminateIfEnded(widget.contract);
      await _ensureInactiveContractSnapshotsBackfilled();

      // نفس منطق حساب ارتفاع البوتوم ناف
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
        Navigator.popUntil(context, (r) => r.isFirst);
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  Future<void> _exportContractDetailsPdf(
      Contract contract, Tenant? tenant, Property? property) async {
    final ejarDirect = (contract.ejarContractNo ?? '').trim();
    final ejarLocal = _readEjarNoLocal(contract.id).trim();
    final ejarForPdf = ejarDirect.isNotEmpty ? ejarDirect : ejarLocal;
    debugPrint(
      '[PDF_TRACE] contracts_screen export '
      'contractId=${contract.id} '
      'ejarDirect="$ejarDirect" '
      'ejarLocal="$ejarLocal"',
    );
    await PdfExportService.shareContractDetailsPdf(
      context: context,
      contract: contract,
      tenant: tenant,
      property: property,
      waterSummary: _waterSummaryText(contract),
      ejarContractNo: ejarForPdf,
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
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
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
          throw Exception('attachment missing');
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
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
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
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        await Share.shareXFiles([XFile(f.path, mimeType: _mimeFromPath(f.path))]);
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
                title:
                    Text('تحميل', style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title:
                    Text('مشاركة', style: GoogleFonts.cairo(color: Colors.white)),
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

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable = await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
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
          SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // نبدأ من العقد القادم من الشاشة الأم
    Contract contract = widget.contract;

    // نحاول جلب النسخة الحيّة من بوكس العقود (هذي اللي فيها save/delete شغّال)
    final live = firstWhereOrNull(
      _contracts.values,
      (c) => c.id == contract.id,
    );
    if (live != null) {
      contract = live;
    }

    final Tenant? t =
        firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
    final Property? p = firstWhereOrNull(
        _properties.values, (x) => x.id == contract.propertyId);
    final ejarNoForView = (() {
      final direct = (contract.ejarContractNo ?? '').trim();
      if (direct.isNotEmpty) return direct;
      return _readEjarNoLocal(contract.id);
    })();

    Property? building;
    if (p?.parentBuildingId != null) {
      building = firstWhereOrNull(
          _properties.values, (x) => x.id == p!.parentBuildingId);
    }
    final tenantSnapshot = _resolvedTenantSnapshot(contract, t);
    final propertySnapshot = _resolvedPropertySnapshot(contract, p);
    final buildingSnapshot = _resolvedBuildingSnapshot(contract, p, building);
    final inactive = _isContractInactive(contract);
    final tenantName =
        t?.fullName ?? _snapshotString(tenantSnapshot, 'fullName') ?? '—';
    final secondLineName =
        p?.name ??
        _snapshotString(propertySnapshot, 'name') ??
        building?.name ??
        _snapshotString(buildingSnapshot, 'name') ??
        '—';

    final bool dueToday = _isDueToday(contract);
    final bool overdue = _isOverdue(contract);
    final bool dueSoon = _isDueSoon(contract);

// لا نستخدم قاربت/مستحقة/متأخرة لحالة العقد نفسه
    String statusText;
    Color statusColor;
    final started = _hasStarted(contract);
    final ended = _hasEnded(contract) || contract.isExpiredByTime;

    if (contract.isTerminated) {
      statusText = 'ملغي';
      statusColor = const Color(0xFF7F1D1D);
    } else if (ended) {
      statusText = 'منتهي';
      statusColor = const Color(0xFF7F1D1D);
    } else if (_endsToday(contract)) {
      statusText = 'ينتهي اليوم';
      statusColor = const Color(0xFFEA580C);
    } else if (!started) {
      statusText = 'غير نشطة (قبل البدء)';
      statusColor = const Color(0xFF334155);
    } else if (_isNearContractEnd(contract)) {
      // ← جديد
      statusText = 'عقد قارب';
      statusColor = const Color(0xFFF59E0B);
    } else {
      statusText = 'نشطة';
      statusColor = const Color(0xFF065F46);
    }

    final coveredMonths = _coveredMonthsByAdvance(contract);
    final firstDueAfterAdvance = _firstDueAfterAdvance(contract);
    final bool allPaid = _allInstallmentsPaid(contract);
// كوّن كومة الدفعات غير المسدّدة حتى اليوم
    final unpaidStack = _buildUnpaidStack(contract);

// القسط القادم بعد الكومة (يعرض "قارب/قادم" حتى لو توجد متأخرات)
    DateTime? upcomingAfterStack;
    if (contract.term != ContractTerm.daily &&
        !_allInstallmentsPaid(contract) &&
        !contract.isTerminated &&
        !contract.isExpiredByTime &&
        !_hasEnded(contract)) {
      if (unpaidStack.isNotEmpty) {
        upcomingAfterStack = _dateOnly(
            _addMonths(unpaidStack.last, _monthsPerCycleFor(contract)));
      } else {
        // لا توجد كومة (كل ما قبل اليوم مدفوع) — خذ أول غير مدفوع اليوم أو بعده
        upcomingAfterStack = _nextDueDate(contract);
      }
    }
    upcomingAfterStack = _sanitizeUpcoming(contract, upcomingAfterStack);
    if (contract.isTerminated ||
        contract.isExpiredByTime ||
        _hasEnded(contract)) {
      upcomingAfterStack = null;
    }

// عنوان القسم
    final sectionHeaderTitle =
        unpaidStack.isNotEmpty ? 'دفعات غير مسددة' : 'الدفعة القادمة';

// الحالة + اللون (مطابقة لأعلى الشاشة والقائمة)
    String? nextLabel;
    Color? nextColor;

    final perCycleAmount = _perCycleAmount(contract);

    // لليومي: حساب القيمة اليومية من الإجمالي
    final dailyDays = contract.term == ContractTerm.daily
        ? _dailyContractDays(contract.startDate, contract.endDate)
        : 0;
    double? dailyRate;
    if (contract.term == ContractTerm.daily) {
      if (dailyDays > 0) dailyRate = contract.totalAmount / dailyDays;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
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
          title: Text('تفاصيل العقد',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'طباعة',
              onPressed: () => _exportContractDetailsPdf(contract, t, p),
              icon:
                  const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            ),
            IconButton(
              tooltip: contract.isArchived ? 'فك الأرشفة' : 'أرشفة',
              onPressed: () async {
                // 🚫 منع عميل المكتب من الأرشفة / فكّ الأرشفة
                if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                  return;
                }

                // 🔒 تأكد أن العقد مرتبط بصندوق Hive

                // 🔒 تأكد أن العقد مرتبط بصندوق Hive
                if (!contract.isInBox) {
                  final box = Hive.box<Contract>(boxName(kContractsBox));
                  final live =
                      firstWhereOrNull(box.values, (c) => c.id == contract.id);
                  if (live == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تعذّر تحديث حالة العقد لأنه غير موجود في البيانات.',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  contract = live;
                }

                if (contract.isArchived) {
                  await _showArchiveNoticeDialog(
                    context,
                    message:
                        'لا يمكن إلغاء الأرشفة، العقود الملغاة والمنتهية تتأرشف تلقائيًا.',
                  );
                  return;
                }

                // العقود المنتهية/الملغاة تُؤرشف تلقائيًا ولا تُؤرشف يدويًا
                if (contract.isTerminated ||
                    contract.isExpiredByTime ||
                    _hasEnded(contract)) {
                  if (!contract.isArchived) {
                    contract.isArchived = true;
                    await contract.save();
                  }
                  await _showArchiveNoticeDialog(
                    context,
                    message:
                        'لا يمكن الأرشفة، العقود الملغاة والمنتهية تتأرشف تلقائيًا.',
                  );
                  if (mounted) setState(() {});
                  return;
                }

                // منع الأرشفة إن لم يُنهَ العقد بعد
                if (!contract.isArchived && !contract.isTerminated) {
                  await _showArchiveNoticeDialog(
                    context,
                    message:
                        'لا يمكن الأرشفة، العقود الملغاة والمنتهية تتأرشف تلقائيًا.',
                  );

                  return;
                }

                // لو العقد مُنتهٍ لكن عليه دفعات مستحقة/متأخرة غير مسددة → منع الأرشفة
                if (!contract.isArchived && contract.isTerminated) {
                  var hasUnpaid = false;
                  try {
                    if (contract.term == ContractTerm.daily) {
                      // العقود اليومية: غير مسدّد بالكامل
                      hasUnpaid = !_dailyAlreadyPaid(contract);
                    } else {
                      // غير اليومي: أي قسط غير مدفوع حتى اليوم (مستحق أو متأخر)
                      final unpaid = _buildUnpaidStack(contract);
                      hasUnpaid = unpaid.isNotEmpty;
                    }
                  } catch (_) {}

                  if (hasUnpaid) {
                    await _showArchiveNoticeDialog(
                      context,
                      message:
                          'لا يمكن أرشفة هذا العقد لوجود دفعات مستحقة أو متأخرة لم تُسدَّد بعد.\n'
                          'يجب سداد جميع الدفعات قبل أرشفة العقد.',
                    );
                    return;
                  }
                }

                // ✅ مسموح: فك الأرشفة أو أرشفة عقد مُنتهي
                final newArchived = !contract.isArchived;
                contract.isArchived = newArchived;
                await contract.save();

                // 🔁 مزامنة حالة الأرشفة مع سندات هذا العقد
                try {
                  if (Hive.isBoxOpen(boxName(kInvoicesBox))) {
                    final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
                    for (final inv in invBox.values) {
                      try {
                        if (inv.contractId == contract.id) {
                          inv.isArchived = newArchived;
                          await inv.save();
                        }
                      } catch (_) {}
                    }
                  }
                } catch (_) {}

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newArchived
                            ? 'تمت أرشفة العقد وسنداته'
                            : 'تم إلغاء الأرشفة عن العقد وسنداته',
                        style: GoogleFonts.cairo(),
                      ),
                    ),
                  );
                }

                setState(() {});
              },
              icon: Icon(
                contract.isArchived
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

            // === AnimatedBuilder يبدأ هنا ===
            AnimatedBuilder(
              animation: Listenable.merge([
                Hive.box<Invoice>(boxName(kInvoicesBox)).listenable(),
                Hive.box<Contract>(boxName(kContractsBox)).listenable(),
              ]),
              builder: (_, __) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== بطاقة الرأس (مبسطة) =====
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Column(
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
                                      end: Alignment.bottomLeft,
                                    ),
                                  ),
                                  child: const Icon(Icons.description_rounded,
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
                                            child: InkWell(
                                              onTap: () => _openTenant(
                                                context,
                                                contract,
                                                t,
                                                tenantSnapshot,
                                              ),
                                              child: Text(
                                                tenantName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.cairo(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16.sp,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (contract.serialNo != null) ...[
                                            SizedBox(width: 8.w),
                                            _chip('${contract.serialNo}',
                                                bg: const Color(0xFF334155)),
                                          ],
                                        ],
                                      ),
                                      SizedBox(height: 4.h),
                                      InkWell(
                                        onTap: () => _openProperty(
                                          context,
                                          contract,
                                          p,
                                          propertySnapshot,
                                          buildingSnapshot,
                                          tenantName,
                                        ),
                                        child: Text(
                                          secondLineName,
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
                                      Wrap(
                                        spacing: 8.w,
                                        runSpacing: 8.h,
                                        children: [
                                          _chip(statusText, bg: statusColor),
                                          _chip(
                                              'العقد: ${_termLabelForContract(contract)}',
                                              bg: const Color(0xFF1F2937)),
                                          _dateChip(
                                              _fmtDateDynamic(
                                                  contract.startDate),
                                              _fmtDateDynamic(
                                                  contract.endDate)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // واتساب (أسفل البطاقة)
                            SizedBox(height: 24.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // زر واتساب (على اليسار في RTL)
                                Builder(builder: (context) {
                                  final bool nearEnd =
                                      _isNearContractEnd(contract);
                                  final bool endedOrTerminated =
                                      _hasEnded(contract) ||
                                          contract.isTerminated;

                                  if (!nearEnd && !endedOrTerminated) {
                                    return const SizedBox.shrink();
                                  }

                                  final t = firstWhereOrNull(_tenants.values,
                                      (x) => x.id == contract.tenantId);
                                  final p = firstWhereOrNull(_properties.values,
                                      (x) => x.id == contract.propertyId);

                                  final bool phoneOk = _waNumberE164(t) != null;
                                  final msg = _waMessageContract(
                                    c: contract,
                                    due: _dateOnly(contract.endDate),
                                    kind:
                                        endedOrTerminated ? 'overdue' : 'near',
                                    tenantObj: t,
                                    tenantMap: _asMap(t),
                                    propertyMap: _asMap(p),
                                  );

                                  return AbsorbPointer(
                                    absorbing: !phoneOk,
                                    child: Opacity(
                                      opacity: phoneOk ? 1.0 : 0.45,
                                      child: _miniAction(
                                        icon: Icons.chat_bubble_rounded,
                                        label: 'واتس اب',
                                        bg: const Color(0xFF25D366),
                                        onTap: () {
                                          if (!phoneOk) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'لا يوجد رقم واتساب صالح لهذا المستأجر.')),
                                            );
                                            return;
                                          }
                                          _openWhatsAppToTenant(
                                              context, t, msg);
                                        },
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ===== قسم تفاصيل العقد (جديد) =====
                      SizedBox(height: 10.h),
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Builder(
                          builder: (_) {
                            final waterTotals = _waterTotalsForContract(contract);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('تفاصيل العقد'),
                                if (contract.term != ContractTerm.daily)
                                  _rowInfo('دورة الدفع',
                                      _paymentCycleLabelForContract(contract)),
                                if (contract.term != ContractTerm.daily)
                                  _rowInfo('إجمالي قيمة الإيجار',
                                      '${_fmtMoneyTrunc(contract.totalAmount)} ${_displayCurrency(contract.currency)}'),
                                if (contract.term == ContractTerm.daily)
                                  _rowInfo('عدد أيام الإيجار',
                                      _dailyRentalDaysLabel(dailyDays)),
                                if (contract.term == ContractTerm.daily)
                                  _rowInfoWidget(
                                    'فترة الإيجار',
                                    Padding(
                                      padding: EdgeInsets.only(top: 2.h),
                                      child: _dailyPeriodDetailsWidget(
                                        contract.dailyStartBoundary,
                                        contract.dailyEndBoundary,
                                        baseStyle: GoogleFonts.cairo(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (contract.term == ContractTerm.daily)
                                  _rowInfo('القيمة الإجمالية',
                                      '${_fmtMoneyTrunc(contract.totalAmount)} ${_displayCurrency(contract.currency)}'),
                                if (contract.term == ContractTerm.daily &&
                                    dailyRate != null)
                                  _rowInfo('قيمة اليوم',
                                      '${_fmtMoneyTrunc(dailyRate)} ${_displayCurrency(contract.currency)}'),
                                if (contract.term != ContractTerm.daily &&
                                    (contract.advanceMode == AdvanceMode.none ||
                                        (contract.advancePaid ?? 0) <= 0))
                                  _rowInfo('عدد الدفعات',
                                      '${((_monthsInContract(contract) / _monthsPerCycleFor(contract)).ceil()).clamp(1, 1000)}'),
                                if (contract.term != ContractTerm.daily)
                                  _rowInfo('قيمة الدفعة',
                                      '${_fmtMoneyTrunc(contract.rentAmount)} ${_displayCurrency(contract.currency)}'),
                                if (contract.advanceMode != AdvanceMode.none &&
                                    (contract.advancePaid ?? 0) > 0)
                                  _rowInfo('مبلغ المقدم',
                                      '${_fmtMoneyTrunc(contract.advancePaid ?? 0)} ${_displayCurrency(contract.currency)}'),
                                if (ejarNoForView.isNotEmpty)
                                  _rowInfo('رقم منصة إيجار', ejarNoForView),
                                if (_waterSummaryText(contract).trim().isNotEmpty)
                                  _rowInfo('خدمات المياه',
                                      _waterSummaryText(contract)),
                              ],
                            );
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: EntityAuditInfoButton(
                          collectionName: 'contracts',
                          entityId: contract.id,
                        ),
                      ),

                      // ===== تفاصيل الدفعة المقدمة (إن وجدت) =====
                      if (contract.term != ContractTerm.daily &&
                          contract.advanceMode != AdvanceMode.none &&
                          (contract.advancePaid ?? 0) > 0) ...[
                        SizedBox(height: 10.h),
                        _DarkCard(
                          padding: EdgeInsets.all(14.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('تفاصيل الدفعة المقدمة'),
                              _rowInfo('إجمالي المقدم',
                                  '${_fmtMoneyTrunc(contract.advancePaid ?? 0)} ${_displayCurrency(contract.currency)}'),
                              Builder(
                                builder: (_) {
                                  if (contract.advanceMode ==
                                      AdvanceMode.deductFromTotal) {
                                    final months = _monthsInContract(contract);
                                    final installments =
                                        (months / _monthsPerCycleFor(contract))
                                            .ceil()
                                            .clamp(1, 1000);
                                    final net = (contract.totalAmount -
                                            (contract.advancePaid ?? 0))
                                        .clamp(0, double.infinity);
                                    final per = net / installments;
                                    return Column(
                                      children: [
                                        _rowInfo('المتبقي للتقسيط',
                                            '${_fmtMoneyTrunc(net)} ${contract.currency}'),
                                        _rowInfo(
                                            'عدد الدفعات', '$installments'),
                                        _rowInfo('قيمة كل دفعة',
                                            '${_fmtMoneyTrunc(per)} ${_displayCurrency(contract.currency)}'),
                                      ],
                                    );
                                  } else {
                                    final months = _monthsInContract(contract);
                                    final mPerCycle =
                                        _monthsPerCycleFor(contract);
                                    final perCycleAll =
                                        ((months / mPerCycle).ceil())
                                            .clamp(1, 1000);
                                    final monthly = months > 0
                                        ? (contract.totalAmount / months)
                                        : 0.0;

                                    final advPaid =
                                        (contract.advancePaid ?? 0).toDouble();
                                    final coveredCycles = monthly > 0
                                        ? (advPaid / (monthly * mPerCycle))
                                            .floor()
                                            .clamp(0, perCycleAll)
                                        : 0;
                                    final outstanding =
                                        (contract.totalAmount - advPaid)
                                            .clamp(0, double.infinity);
                                    final remainingInst =
                                        (perCycleAll - coveredCycles)
                                            .clamp(0, 1000);
                                    final perCycleAmount = (remainingInst > 0)
                                        ? (outstanding / remainingInst)
                                        : 0.0;

                                    return Column(
                                      children: [
                                        _rowInfo(
                                            'إجمالي الدفعات', '$perCycleAll'),
                                        _rowInfo('دفعات المقدم',
                                            '$coveredCycles فترات'),
                                        _rowInfo('المتبقي الكلي',
                                            '${_fmtMoneyTrunc(outstanding)} ${contract.currency}'),
                                        _rowInfo('الدفعات المتبقية',
                                            '$remainingInst'),
                                        _rowInfo('قيمة كل دفعة',
                                            '${_fmtMoneyTrunc(perCycleAmount)} ${_displayCurrency(contract.currency)}'),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (contract.attachmentPaths.isNotEmpty) ...[
                        SizedBox(height: 10.h),
                        _DarkCard(
                          padding: EdgeInsets.all(14.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(
                                  'المرفقات (${contract.attachmentPaths.length}/3)'),
                              SizedBox(height: 8.h),
                              Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                children: contract.attachmentPaths.map((path) {
                                  return InkWell(
                                    onTap: () => _showAttachmentActions(path),
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
                      ],

                      SizedBox(height: 10.h),

                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8.w,
                          children: [
                            if (!contract.isTerminated)
                              _miniAction(
                                icon: Icons.cancel_schedule_send_rounded,
                                label: 'إنهاء',
                                bg: const Color(0xFFB91C1C),
                                onTap: () async {
                                  // 🚫 منع عميل المكتب من إنهاء العقد
                                  if (await OfficeClientGuard
                                      .blockIfOfficeClient(context)) {
                                    return;
                                  }

                                  _terminate(context, contract);
                                },
                              ),
                            if (inactive)
                              _miniAction(
                                icon: Icons.autorenew_rounded,
                                label: 'تجديد',
                                bg: const Color(0xFF0F766E),
                                onTap: () => _renewContract(context, contract),
                              ),
                            _miniAction(
                              icon: Icons.sticky_note_2_rounded,
                              label: 'ملاحظات',
                              bg: const Color(0xFF1E293B),
                              onTap: () async {
                                // 🚫 منع عميل المكتب من تعديل الملاحظات
                                if (await OfficeClientGuard.blockIfOfficeClient(
                                    context)) {
                                  return;
                                }

                                _editNotes(context, contract);
                              },
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 10.h),

                      if (contract.isTerminated ||
                          _hasEnded(contract) ||
                          contract.isExpiredByTime) ...[
                        _noteCard(
                            contract.isTerminated ? 'العقد ملغي' : 'العقد منتهي'),
                        SizedBox(
                            height: 8
                                .h), // مسافة بسيطة (عدّلها 6.h أو 10.h حسب رغبتك)
                      ] else if (_endsToday(contract)) ...[
                        _noteCard('العقد ينتهي اليوم'),
                        SizedBox(height: 8.h),
                      ],

                      if (!_hasStarted(contract)) ...[
                        _noteCard('العقد لم يبدأ بعد'),
                      ]
                      // ============ يومي ============
                      else if (contract.term == ContractTerm.daily) ...[
                        if (_dailyAlreadyPaid(contract))
                          _noteCard('لا توجد دفعات قادمة ضمن مدة العقد.')
                        else ...[
                          _paymentCard(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8.w,
                                  runSpacing: 8.h,
                                  children: [
                                    _chip(
                                        'عدد أيام الإيجار: ${_dailyRentalDaysLabel(dailyDays)}',
                                        bg: const Color(0xFF1F2937)),
                                    _chip(
                                        'المبلغ: ${_fmtMoneyTrunc(contract.totalAmount)} ${_displayCurrency(contract.currency)}',
                                        bg: const Color(0xFF1F2937)),
                                    _chip(
                                      'الحالة: ${_dateOnly(SaTimeLite.now()).isAfter(_dateOnly(contract.startDate)) ? 'متأخرة' : 'مستحقة'}',
                                      bg: _dateOnly(SaTimeLite.now()).isAfter(
                                              _dateOnly(contract.startDate))
                                          ? const Color(0xFF7F1D1D)
                                          : const Color(0xFF0EA5E9),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8.h),
                                _paymentPeriodChipForDue(
                                    contract, _dateOnly(contract.startDate)),
                                SizedBox(height: 10.h),
                                Padding(
                                  padding: EdgeInsets.only(top: 8.h),
                                  child: Row(
                                    // يثبّت "يسار/يمين" بغض النظر عن RTL
                                    textDirection: TextDirection.ltr,
                                    children: [
                                      // يسار: زر واتساب بنفس منطقك الحالي
                                      Builder(builder: (_) {
                                        final isLate =
                                            _dateOnly(SaTimeLite.now()).isAfter(
                                                _dateOnly(contract.startDate));
                                        final kind = isLate ? 'overdue' : 'due';
                                        final t = firstWhereOrNull(
                                            _tenants.values,
                                            (x) => x.id == contract.tenantId);
                                        final msg = _waMessage(
                                          c: contract,
                                          due: _dateOnly(contract.startDate),
                                          kind: kind,
                                          tenant: t,
                                          property: p,
                                        );

                                        final phoneOk =
                                            _waNumberE164(t) != null;
                                        if (!phoneOk) {
                                          return const SizedBox.shrink();
                                        }

                                        return _miniAction(
                                          icon: Icons.chat_bubble_rounded,
                                          label: 'واتس اب',
                                          bg: const Color(0xFF25D366),
                                          onTap: () => _openWhatsAppToTenant(
                                              context, t, msg),
                                        );
                                      }),

                                      const Spacer(),

                                      // يمين: زر سداد في موضعه القديم (أقصى اليمين)
                                      _miniAction(
                                        icon: Icons.receipt_long_rounded,
                                        label: 'سداد',
                                        onTap: () async {
                                          // 🚫 منع عميل المكتب من السداد
                                          if (await OfficeClientGuard
                                              .blockIfOfficeClient(context)) {
                                            return;
                                          }

                                          _confirmAndPay(context, contract,
                                              _dateOnly(contract.startDate));
                                        },
                                        bg: const Color(0xFF0EA5E9),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      if (contract.term != ContractTerm.daily) ...[
                        // 👈 نفس سلسلة if/else، من غير فاصلة قبلها
                        if (unpaidStack.isEmpty &&
                            upcomingAfterStack == null &&
                            !contract.isTerminated &&
                            !contract.isExpiredByTime &&
                            !_hasEnded(contract)) ...[
                          _noteCard('لا توجد دفعات قادمة ضمن مدة العقد.'),
                        ] else ...[
                          if (unpaidStack.isNotEmpty) ...[
                            ...unpaidStack.asMap().entries.map<Widget>((entry) {
                              final d = entry.value;
                              final waterAmount = _waterInstallmentAmountForDue(
                                  contract, _dateOnly(d));
                              final hasWaterLinked = waterAmount > 0;
                              final dueAmount =
                                  _perCycleAmount(contract) + waterAmount;
                              final isToday =
                                  _dateOnly(d) == _dateOnly(SaTimeLite.now());
                              final status = isToday ? 'مستحقة' : 'متأخرة';
                              final color = isToday
                                  ? const Color(0xFF0EA5E9)
                                  : const Color(0xFF7F1D1D);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _paymentCard(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8.w,
                                          runSpacing: 8.h,
                                          children: [
                                            _chip(
                                                '${hasWaterLinked ? 'المبلغ الكلي' : 'المبلغ'}: ${_fmtMoneyTrunc(dueAmount)} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF1F2937)),
                                            _chip('الحالة: $status', bg: color),
                                          ],
                                        ),
                                        SizedBox(height: 8.h),
                                        _paymentPeriodChipForDue(contract, d),
                                        if (hasWaterLinked) ...[
                                          SizedBox(height: 8.h),
                                          Wrap(
                                            spacing: 8.w,
                                            runSpacing: 8.h,
                                            children: [
                                              _chip(
                                                'قيمة الإيجار: ${_fmtMoneyTrunc(_perCycleAmount(contract))} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF1F2937),
                                              ),
                                              _chip(
                                                'قسط المياه: ${_fmtMoneyTrunc(waterAmount)} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF0B3A53),
                                              ),
                                            ],
                                          ),
                                        ],
                                        SizedBox(height: 10.h),
                                        Padding(
                                          padding: EdgeInsets.only(top: 8.h),
                                          child: Row(
                                            // يثبّت "يسار/يمين" بغض النظر عن RTL
                                            textDirection: TextDirection.ltr,
                                            children: [
                                              // يسار: زر واتساب بنفس منطقك الحالي
                                              Builder(builder: (_) {
                                                final isLate = _dateOnly(
                                                        SaTimeLite.now())
                                                    .isAfter(_dateOnly(
                                                        contract.startDate));
                                                final kind =
                                                    isLate ? 'overdue' : 'due';
                                                final t = firstWhereOrNull(
                                                    _tenants.values,
                                                    (x) =>
                                                        x.id ==
                                                        contract.tenantId);
                                                final msg = _waMessage(
                                                  c: contract,
                                                  due: _dateOnly(
                                                      contract.startDate),
                                                  kind: kind,
                                                  tenant: t,
                                                  property: p,
                                                );

                                                final phoneOk =
                                                    _waNumberE164(t) != null;
                                                if (!phoneOk) {
                                                  return const SizedBox
                                                      .shrink();
                                                }

                                                return _miniAction(
                                                  icon:
                                                      Icons.chat_bubble_rounded,
                                                  label: 'واتس اب',
                                                  bg: const Color(0xFF25D366),
                                                  onTap: () =>
                                                      _openWhatsAppToTenant(
                                                          context, t, msg),
                                                );
                                              }),

                                              const Spacer(),

                                              // يمين: زر سداد في موضعه القديم (أقصى اليمين)
                                              _miniAction(
                                                icon:
                                                    Icons.receipt_long_rounded,
                                                label: 'سداد',
                                                onTap: () async {
                                                  // 🚫 منع عميل المكتب من السداد
                                                  if (await OfficeClientGuard
                                                      .blockIfOfficeClient(
                                                          context)) {
                                                    return;
                                                  }

                                                  _confirmAndPay(
                                                      context,
                                                      contract,
                                                      _dateOnly(
                                                          d)); // ← الأقدم أو المحدد
                                                },
                                                bg: const Color(0xFF0EA5E9),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (entry.key != unpaidStack.length - 1) ...[
                                    SizedBox(height: 10.h),
                                    const Divider(color: Colors.white24),
                                    SizedBox(height: 10.h),
                                  ],
                                ],
                              );
                            }),
                          ],
                          if (upcomingAfterStack != null) ...[
                            if (unpaidStack.isNotEmpty) ...[
                              SizedBox(height: 10.h),
                              const Divider(color: Colors.white24),
                              SizedBox(height: 10.h),
                            ],
                            Builder(builder: (_) {
                              final t = _dateOnly(SaTimeLite.now());
                              final d = _dateOnly(upcomingAfterStack!);
                              final waterAmount =
                                  _waterInstallmentAmountForDue(contract, d);
                              final hasWaterLinked = waterAmount > 0;
                              final dueAmount =
                                  _perCycleAmount(contract) + waterAmount;
                              final diff = d.difference(t).inDays;
                              final window =
                                  _nearWindowDaysForContract(contract);
                              final nearing = diff >= 1 && diff <= window;
                              final status = nearing ? 'قارب' : 'قادمة';
                              final color = nearing
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF065F46);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _paymentCard(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8.w,
                                          runSpacing: 8.h,
                                          children: [
                                            _chip(
                                                '${hasWaterLinked ? 'المبلغ الكلي' : 'المبلغ'}: ${_fmtMoneyTrunc(dueAmount)} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF1F2937)),
                                            _chip('الحالة: $status', bg: color),
                                          ],
                                        ),
                                        SizedBox(height: 8.h),
                                        _paymentPeriodChipForDue(
                                            contract, upcomingAfterStack),
                                        if (hasWaterLinked) ...[
                                          SizedBox(height: 8.h),
                                          Wrap(
                                            spacing: 8.w,
                                            runSpacing: 8.h,
                                            children: [
                                              _chip(
                                                'قيمة الإيجار: ${_fmtMoneyTrunc(_perCycleAmount(contract))} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF1F2937),
                                              ),
                                              _chip(
                                                'قسط المياه: ${_fmtMoneyTrunc(waterAmount)} ${_displayCurrency(contract.currency)}',
                                                bg: const Color(0xFF0B3A53),
                                              ),
                                            ],
                                          ),
                                        ],
                                        SizedBox(height: 10.h),
                                        Padding(
                                          padding: EdgeInsets.only(top: 8.h),
                                          child: Row(
                                            // يثبّت "يسار/يمين" بغض النظر عن RTL
                                            textDirection: TextDirection.ltr,
                                            children: [
                                              // يسار: زر واتساب بنفس منطقك الحالي
                                              Builder(builder: (_) {
                                                final dOnly = _dateOnly(
                                                    upcomingAfterStack!);
                                                final todayOnly =
                                                    _dateOnly(SaTimeLite.now());
                                                final isLate =
                                                    todayOnly.isAfter(dOnly);
                                                final isToday =
                                                    dOnly == todayOnly;

// أضف منطق "near" باستخدام نفس نافذة القرب المعتمدة في الواجهة
                                                final diff = dOnly
                                                    .difference(todayOnly)
                                                    .inDays;
                                                final nearWin =
                                                    _nearWindowDaysForContract(
                                                        contract);
                                                final isNear = diff >= 1 &&
                                                    diff <= nearWin;

// اسمح بالزر في (متأخرة/اليوم/قاربت). اخفِه فقط إن كانت "قادمة" بعيدة
                                                if (!isLate &&
                                                    !isToday &&
                                                    !isNear) {
                                                  return const SizedBox
                                                      .shrink();
                                                }

// مرّر النوع الصحيح للرسالة (يدعم 'near' بالفعل في _waMessage)
                                                final kind = isLate
                                                    ? 'overdue'
                                                    : (isToday
                                                        ? 'due'
                                                        : 'near');

                                                final t = firstWhereOrNull(
                                                    _tenants.values,
                                                    (x) =>
                                                        x.id ==
                                                        contract.tenantId);
                                                final msg = _waMessage(
                                                  c: contract,
                                                  due: dOnly,
                                                  kind: kind,
                                                  tenant: t,
                                                  property: p,
                                                );

                                                final phoneOk =
                                                    _waNumberE164(t) != null;
                                                if (!phoneOk) {
                                                  return const SizedBox
                                                      .shrink();
                                                }

                                                return _miniAction(
                                                  icon:
                                                      Icons.chat_bubble_rounded,
                                                  label: 'واتس اب',
                                                  bg: const Color(0xFF25D366),
                                                  onTap: () =>
                                                      _openWhatsAppToTenant(
                                                          context, t, msg),
                                                );
                                              }),

                                              const Spacer(),

                                              // يمين: زر سداد في موضعه القديم (أقصى اليمين)
                                              _miniAction(
                                                icon:
                                                    Icons.receipt_long_rounded,
                                                label: 'سداد',
                                                onTap: () async {
                                                  // 🚫 منع عميل المكتب من السداد
                                                  if (await OfficeClientGuard
                                                      .blockIfOfficeClient(
                                                          context)) {
                                                    return;
                                                  }

                                                  _confirmAndPay(
                                                      context,
                                                      contract,
                                                      _dateOnly(
                                                          upcomingAfterStack!));
                                                },
                                                bg: const Color(0xFF0EA5E9),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ],
                      ], // 👈 فاصلة واحدة بعد نهاية السلسلة كلها لأنها عنصر داخل children

                      SizedBox(height: 10.h),

                      InkWell(
                        onTap: () => _openInvoicesHistory(context, contract),
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1220),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.12)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.history_rounded,
                                  color: Colors.white),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  'الدفعات السابقة',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ); // ← مهم: سيمي كولون
              }, // ← إغلاق builder
            ), // ← إغلاق AnimatedBuilder
            // === AnimatedBuilder ينتهي هنا ===
          ],
        ), // ← يُغلق Stack
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 3,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Widget _miniAction(
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color bg = const Color(0xFF1E293B)}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: Colors.white.withOpacity(0.15))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16.sp, color: Colors.white),
          SizedBox(width: 6.w),
          Text(label,
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp)),
        ]),
      ),
    );
  }

  Future<void> _openOriginalTenantFromSnapshot(
    BuildContext context,
    Map<String, dynamic> snapshot,
  ) async {
    final tenantId = (_snapshotString(snapshot, 'id') ?? '').trim();
    final tenant = tenantId.isEmpty
        ? null
        : firstWhereOrNull(_tenants.values, (x) => x.id == tenantId);
    if (tenant == null) {
      showSnackSafe(
        context,
        'تعذر فتح المستأجر الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => tenants_ui.TenantDetailsScreen(tenant: tenant),
      ),
    );
  }

  Future<void> _openOriginalPropertyFromSnapshot(
    BuildContext context,
    Map<String, dynamic>? snapshot, {
    required bool isBuilding,
  }) async {
    final propertyId = (_snapshotString(snapshot, 'id') ?? '').trim();
    final property = propertyId.isEmpty
        ? null
        : firstWhereOrNull(_properties.values, (x) => x.id == propertyId);
    if (property == null) {
      showSnackSafe(
        context,
        isBuilding
            ? 'تعذر فتح العمارة الأصلية لأنها لم تعد موجودة في البيانات الحالية.'
            : 'تعذر فتح العقار الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(item: property),
      ),
    );
  }

  void _openTenant(
    BuildContext context,
    Contract contract,
    Tenant? tenant,
    Map<String, dynamic>? snapshot,
  ) async {
    if (_isContractInactive(contract)) {
      final resolved = snapshot ?? _resolvedTenantSnapshot(contract, tenant);
      if (resolved == null || resolved.isEmpty) {
        showSnackSafe(context, 'لا تتوفر نسخة محفوظة من بيانات المستأجر لهذا العقد.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ContractTenantSnapshotScreen(
            snapshot: resolved,
            onAttachmentTap: _showAttachmentActions,
            onOpenOriginal: () => _openOriginalTenantFromSnapshot(context, resolved),
          ),
        ),
      );
      return;
    }

    if (tenant == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => tenants_ui.TenantDetailsScreen(tenant: tenant),
      ),
    );
  }

  void _openProperty(
    BuildContext context,
    Contract contract,
    Property? property,
    Map<String, dynamic>? propertySnapshot,
    Map<String, dynamic>? buildingSnapshot,
    String? tenantName,
  ) async {
    if (_isContractInactive(contract)) {
      final resolvedProperty =
          propertySnapshot ?? _resolvedPropertySnapshot(contract, property);
      if (resolvedProperty == null || resolvedProperty.isEmpty) {
        showSnackSafe(context, 'لا تتوفر نسخة محفوظة من بيانات العقار لهذا العقد.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ContractPropertySnapshotScreen(
            propertySnapshot: resolvedProperty,
            buildingSnapshot: buildingSnapshot,
            tenantName: tenantName,
            onAttachmentTap: _showAttachmentActions,
            onOpenOriginalTenant: () {
              final tenant = firstWhereOrNull(
                _tenants.values,
                (x) => x.id == contract.tenantId,
              );
              final resolvedTenant = _resolvedTenantSnapshot(contract, tenant);
              if (resolvedTenant == null || resolvedTenant.isEmpty) {
                showSnackSafe(
                  context,
                  'تعذر فتح المستأجر الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
                );
                return Future.value();
              }
              return _openOriginalTenantFromSnapshot(context, resolvedTenant);
            },
            onOpenOriginalProperty: () => _openOriginalPropertyFromSnapshot(
              context,
              resolvedProperty,
              isBuilding: false,
            ),
            onOpenOriginalBuilding: buildingSnapshot == null ||
                    buildingSnapshot.isEmpty
                ? null
                : () => _openOriginalPropertyFromSnapshot(
                      context,
                      buildingSnapshot,
                      isBuilding: true,
                    ),
          ),
        ),
      );
      return;
    }

    if (property == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(item: property),
      ),
    );
  }

  Future<void> _confirmAndPay(
      BuildContext context, Contract c, DateTime due) async {
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد السداد',
      message:
          'هل أنت متأكد من المتابعة؟ سيتم إصدار سند تلقائيًا، ولا يمكن التراجع عن هذه العملية لاحقًا.',
    );

    if (!ok) return;
    await _goPay(context, c, due);
  }

  Future<void> _goPay(BuildContext context, Contract c, DateTime due) async {
    final number = (c.serialNo?.isNotEmpty == true) ? c.serialNo! : c.id;

    try {
      // منع السداد قبل بداية العقد
      if (!_hasStarted(c)) {
        if (context.mounted) {
          await CustomConfirmDialog.show(
            context: context,
            title: 'غير ممكن',
            message: 'العقد لم يبدأ بعد. لا يمكن السداد قبل تاريخ البداية.',
            confirmLabel: 'حسنًا',
          );
        }
        return;
      }

// منع تكرار سداد اليومي
      if (c.term == ContractTerm.daily && _dailyAlreadyPaid(c)) {
        if (context.mounted) {
          await CustomConfirmDialog.show(
            context: context,
            title: 'غير ممكن',
            message: 'تم سداد الإيجار اليومي لهذا العقد مسبقًا.',
            confirmLabel: 'حسنًا',
          );
        }
        return;
      }

      final today = _dateOnly(SaTimeLite.now());
// 👇 ضع هذا داخل _goPay قبل إنشاء السند (بعد فحوصات البداية/اليومي)
      final earliest = _earliestUnpaidDueDate(c); // أقدم قسط غير مسدَّد فعليًا
      if (earliest != null) {
        final d0 = _dateOnly(earliest);
        final due0 = _dateOnly(due);

        // لا تسمح بسداد قسط “أبعد” بينما يوجد قسط أقدم غير مسدَّد
        if (due0.isAfter(d0)) {
          if (context.mounted) {
            await CustomConfirmDialog.show(
              context: context,
              title: 'لا يمكن السداد',
              message:
                  'توجد دفعة غير مسددة بتاريخ ${_fmtDateDynamic(d0)}. يجب سداد الأقدم أولًا.',
              confirmLabel: 'حسنًا',
              showCancel: false,
            );
          }
          return;
        }
      }

      // *** الباقي كما هو (إصدار السند وتحريك المؤشر) ***

      final amount = _perCycleAmount(c);
      final commissionSnapshot =
          await _loadCommissionSnapshotForContractVoucher(c, amount);
      final waterAmount = _waterInstallmentAmountForDue(c, _dateOnly(due));
      final totalAmount = amount + waterAmount;
      final now = SaTimeLite.now();
      final property =
          firstWhereOrNull(_properties.values, (x) => x.id == c.propertyId);
      final building = property?.parentBuildingId == null
          ? null
          : firstWhereOrNull(
              _properties.values, (x) => x.id == property!.parentBuildingId);
      final ejarNoForNote = (c.ejarContractNo ?? '').trim().isNotEmpty
          ? (c.ejarContractNo ?? '').trim()
          : _readEjarNoLocal(c.id);
      final propertyRefForNote = _contractVoucherPropertyReference(
        property: property,
        building: building,
      );

// جهّز رقم عقد للعرض بصيغة سنة-تسلسل حتى لو كان مخزّن بالعكس
      String displaySerial(String? s) {
        final v = (s ?? '').trim();
        if (v.isEmpty) return v;

        final parts = v.split('-');
        if (parts.length == 2) {
          final a = parts[0].trim();
          final b = parts[1].trim();

          bool isYear(String x) =>
              int.tryParse(x) != null &&
              x.length == 4 &&
              int.parse(x) >= 1900 &&
              int.parse(x) <= 2100;

          // إذا التسلسل أولاً والسنة ثانيًا: اقلبها إلى سنة-تسلسل
          if (!isYear(a) && isYear(b)) {
            final seq = a.padLeft(4, '0');
            return '$b-$seq';
          }
        }
        return v;
      }

// تجهيز رقم العقد للعرض الصحيح
      final serialDisplay = displaySerial(c.serialNo); // سنة-تسلسل
      final serialLtr = '\u200E$serialDisplay\u200E'; // عرض من اليسار لليمين

      final inv = Invoice(
        tenantId: c.tenantId,
        contractId: c.id,
        propertyId: c.propertyId,
        issueDate: now,
        dueDate: _dateOnly(due),
        amount: totalAmount,
        paidAmount: totalAmount, // لو تبغيه “مدفوع تلقائيًا”
        currency: c.currency,
        waterAmount: waterAmount,

        note: _buildContractRentVoucherNote(
          ejarNo: ejarNoForNote,
          propertyRef: propertyRefForNote,
          waterAmount: waterAmount,
          commissionMode: commissionSnapshot.mode,
          commissionValue: commissionSnapshot.value,
          commissionAmount: commissionSnapshot.amount,
        ),

        paymentMethod: 'نقدًا',
        createdAt: now,
        updatedAt: now,
      );

// أضف السند
      final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
// ترقيم عند الإنشاء: لجميع السندات غير الملغاة
      if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
        inv.serialNo = _nextInvoiceSerialForContracts(invBox);
        inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
      }

      await invBox.put(inv.id, inv);
      await _syncOfficeCommissionForContractVoucher(inv.id);
      if (waterAmount > 0) {
        await _markWaterInstallmentPaid(c, _dateOnly(due), inv.id);
      }
      if (mounted) {
        setState(() {
          // ✅ اعرض أقدم استحقاق غير مدفوع مباشرةً بعد السداد
          _overrideNextDue = _earliestUnpaidDueDate(c);
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('تم إصدار السند تلقائيًا', style: GoogleFonts.cairo())),
      );

      await Navigator.of(context)
          .pushNamed('/invoices/history', arguments: {'contractId': c.id});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تعذر إصدار السند: $e', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  void _openInvoicesHistory(BuildContext context, Contract c) async {
    try {
      await Navigator.of(context)
          .pushNamed('/invoices/history', arguments: {'contractId': c.id});
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('شاشة سندات الدفعات السابقة غير متوفرة بعد.',
              style: GoogleFonts.cairo())));
    }
  }

  Future<void> _editNotes(BuildContext context, Contract contract) async {
    final controller = TextEditingController(text: contract.notes ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16.w,
              right: 16.w,
              top: 16.h),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('الملاحظات',
                style: GoogleFonts.cairo(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            SizedBox(height: 10.h),
            TextField(
              controller: controller,
              maxLines: 6,
              style: GoogleFonts.cairo(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظاتك هنا',
                hintStyle: GoogleFonts.cairo(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12))),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            SizedBox(height: 12.h),
            Row(children: [
              Expanded(
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text('حفظ',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)))),
              SizedBox(width: 8.w),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.white)))),
            ]),
            SizedBox(height: 12.h),
          ]),
        );
      },
    );

    if (saved == true) {
      contract.notes =
          controller.text.trim().isEmpty ? null : controller.text.trim();
      contract.updatedAt = SaTimeLite.now();
      await contract.save();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تم حفظ الملاحظات', style: GoogleFonts.cairo())));
      }
      setState(() {});
    }
  }

  Future<void> _terminate(BuildContext context, Contract contract) async {
    final now = SaTimeLite.now();
    final todayOnly = _dateOnly(now);
    final originalEndOnly = _dateOnly(contract.endDate);
    final hadStartedBeforeTermination = _hasStarted(contract);

    // تصنيف الدفعات غير المسددة: مستحقة / متأخرة / قادمة
    final List<DateTime> dueNowDates = <DateTime>[];
    final List<DateTime> overdueDates = <DateTime>[];
    final List<DateTime> upcomingDates = <DateTime>[];

    try {
      if (contract.term == ContractTerm.daily) {
        if (!_dailyAlreadyPaid(contract)) {
          final due = _dateOnly(contract.startDate);
          if (due.isBefore(todayOnly)) {
            overdueDates.add(due);
          } else if (due.isAfter(todayOnly)) {
            upcomingDates.add(due);
          } else {
            dueNowDates.add(due);
          }
        }
      } else {
        final first = _firstDueAfterAdvance(contract);
        if (first != null) {
          final stepM = _monthsPerCycleFor(contract);
          var cursor = _dateOnly(first);
          while (!cursor.isAfter(originalEndOnly)) {
            if (!_paidForDue(contract, cursor)) {
              if (cursor.isBefore(todayOnly)) {
                overdueDates.add(cursor);
              } else if (cursor.isAfter(todayOnly)) {
                upcomingDates.add(cursor);
              } else {
                dueNowDates.add(cursor);
              }
            }
            cursor = _dateOnly(_addMonths(cursor, stepM));
          }
        }
      }
    } catch (_) {}

    final hasDueNow = dueNowDates.isNotEmpty;
    final hasOverdue = overdueDates.isNotEmpty;
    final hasUpcoming = upcomingDates.isNotEmpty;
    final hasAnyPending = hasDueNow || hasOverdue || hasUpcoming;
    final String confirmMessage;
    final String confirmLabel;
    if (!hadStartedBeforeTermination) {
      confirmMessage =
          'العقد لم يبدأ بعد. سيتم إلغاء العقد دون إنشاء سندات جديدة.\n'
          'إذا كانت هناك سندات صادرة مسبقًا لهذا العقد فسيتم إلغاؤها فقط.';
      confirmLabel = 'إلغاء العقد';
    } else if (hasAnyPending) {
      confirmMessage =
          'إذا ضغطت "استمرار"، فسيتم التعامل مع جميع الأقساط المستحقة أو المتأخرة أو القادمة على أنها "ملغية".\n'
          'إذا كانت لديك دفعات تريد الاحتفاظ بها في السندات كـ"مدفوعة"، يجب سداد هذه الدفعات أولًا ثم تنفيذ إنهاء العقد.';
      confirmLabel = 'استمرار';
    } else {
      confirmMessage = 'سيتم إنهاء العقد وإتاحة العقار للتأجير';
      confirmLabel = 'إنهاء';
    }

    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تنبيه',
      message: confirmMessage,
      confirmLabel: confirmLabel,
      cancelLabel: 'إلغاء',
    );

    if (!ok) return;

    if (hasAnyPending) {
      final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
      final perCycleAmount = _perCycleAmount(contract);
      final allPending = <DateTime>[
        ...overdueDates,
        ...dueNowDates,
        ...upcomingDates,
      ];

      for (final due in allPending) {
        final dueOnly = _dateOnly(due);
        final dueIso = dueOnly.toIso8601String();
        final dueInvoices = invBox.values
            .where((inv) =>
                inv.contractId == contract.id &&
                _dateOnly(inv.dueDate).toIso8601String() == dueIso)
            .toList();

        if (dueInvoices.isNotEmpty) {
          for (final inv in dueInvoices) {
            if (inv.isCanceled) continue;
            if ((inv.serialNo ?? '').trim().isEmpty) {
              inv.serialNo = _nextInvoiceSerialForContracts(invBox);
            }
            inv.isCanceled = true;
            inv.isArchived = true;
            inv.updatedAt = now;
            final note = (inv.note ?? '').trim();
            if (!note.contains('ملغي بسبب إنهاء العقد')) {
              inv.note = note.isEmpty
                  ? 'ملغي بسبب إنهاء العقد'
                  : '$note\nملغي بسبب إنهاء العقد';
            }
            await inv.save();
            await _syncOfficeCommissionForContractVoucher(inv.id);
          }
          continue;
        }

        if (!hadStartedBeforeTermination) {
          continue;
        }

        // لا يوجد سند لهذا الموعد: أنشئ سندًا ملغيًا مؤرشفًا
        final amount = contract.term == ContractTerm.daily
            ? contract.totalAmount
            : perCycleAmount;
        final inv = Invoice(
          id: '${contract.id}_${dueOnly.microsecondsSinceEpoch}_cancelled',
          serialNo: _nextInvoiceSerialForContracts(invBox),
          tenantId: contract.tenantId,
          contractId: contract.id,
          propertyId: contract.propertyId,
          issueDate: dueOnly,
          dueDate: dueOnly,
          amount: amount,
          paidAmount: 0.0,
          currency: contract.currency,
          note: 'ملغي بسبب إنهاء العقد',
          paymentMethod: 'غير محدد',
          isArchived: true,
          isCanceled: true,
          createdAt: now,
          updatedAt: now,
        );
        await invBox.put(inv.id, inv);
      }
    }

    final properties = Hive.box<Property>(boxName(kPropertiesBox));
    final tenants = Hive.box<Tenant>(boxName(kTenantsBox));

    final prop =
        firstWhereOrNull(properties.values, (p) => p.id == contract.propertyId);
    final snapshotBuilding = prop?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            properties.values, (x) => x.id == prop!.parentBuildingId);
    final tenant =
        firstWhereOrNull(tenants.values, (x) => x.id == contract.tenantId);
    _applyContractSnapshots(
      contract,
      tenant: tenant,
      property: prop,
      building: snapshotBuilding,
      overwrite: true,
    );

    if (prop != null) {
      if (prop.parentBuildingId != null) {
        prop.occupiedUnits = 0;
        await prop.save();
        final siblings = properties.values
            .where((e) => e.parentBuildingId == prop.parentBuildingId);
        final count = siblings.where((e) => e.occupiedUnits > 0).length;
        final building = firstWhereOrNull(
            properties.values, (e) => e.id == prop.parentBuildingId);
        if (building != null) {
          building.occupiedUnits = count;
          await building.save();
        }
      } else {
        prop.occupiedUnits = 0;
        await prop.save();
      }
    }

    final wasActive = contract.isActiveNow;

    // قصّر نهاية العقد إلى يوم الإنهاء
    contract.endDate = _dateOnly(now);

    // علّم العقد أنه منتهي
    contract.isTerminated = true;
    contract.isArchived = true; // الملغى/المنتهي يُؤرشف تلقائيًا
    contract.terminatedAt = now;
    contract.updatedAt = now;
    await contract.save();
    await _resetPeriodicServicesForProperty(contract.propertyId);

    if (!mounted) return;
    setState(() {});

    // تحديث عدّاد العقود النشطة للمستأجر
    if (tenant != null) {
      if (wasActive && tenant.activeContractsCount > 0) {
        tenant.activeContractsCount -= 1;
      }
      tenant.updatedAt = now;
      await tenant.save();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم إنهاء العقد', style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating));
      setState(() {});
    }
  }

  Future<void> _delete(BuildContext context, Contract contract) async {
    // 🚫 حماية إضافية: منع عميل المكتب من الحذف حتى لو استُدعيت الدالة مباشرة
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    // ✅ أولاً: اجلب النسخة الحية من بوكس العقود
    final contractsBox = Hive.box<Contract>(boxName(kContractsBox));

    Contract? live = contract;

    // لو النسخة التي وصلت ليست داخل الصندوق، حاول إيجادها عن طريق id
    if (!(live.isInBox ?? false)) {
      live = firstWhereOrNull(
        contractsBox.values,
        (c) => c.id == contract.id,
      );
    }

    // لو ما قدرنا نلقى العقد في الصندوق، لا نحاول نحذف شيء
    if (live == null || !(live.isInBox)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذّر حذف العقد لأنه غير موجود في البيانات.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
      return;
    }

    // من هنا وطالع نشتغل دائمًا على نسخة غير null
    final cLive = live;

    // امنع الحذف ما لم يكن العقد مُنتهياً
    if (!cLive.isTerminated) {
      await CustomConfirmDialog.show(
        context: context,
        title: 'لا يمكن الحذف',
        message: 'لا يمكن حذف العقد لأنه غير مُنتهي. يجب إنهاء العقد أولًا.',
        confirmLabel: 'حسنًا',
      );
      return;
    }

    // 🚫 منع حذف عقد تم إصدار سندات مرتبطة به
    try {
      final invBoxCheck = Hive.box<Invoice>(boxName(kInvoicesBox));
      final cidCheck = cLive.id;
      final hasInvoices =
          invBoxCheck.values.any((i) => i.contractId == cidCheck);

      if (hasInvoices) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن الحذف',
          message: 'لا يمكن حذف العقد بعد إصدار سندات مرتبطة به.\n'
              'يمكنك فقط أرشفة العقد إذا لم تعد بحاجة لظهوره.',
          confirmLabel: 'حسنًا',
        );
        return; // ⛔ إيقاف الحذف نهائيًا
      }
    } catch (_) {
      // لو صار خطأ في قراءة صندوق السندات لا نكسر الشاشة
    }

    // ✅ من هنا يبدأ تأكيد الحذف العادي (عقد منتهي وبدون سندات)
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message:
          'هل تريد حذف هذا العقد نهائيًا؟ سيتم حذف جميع السندات المرتبطة بهذا العقد.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );

    if (!ok) return;

    final properties = Hive.box<Property>(boxName(kPropertiesBox));
    final tenants = Hive.box<Tenant>(boxName(kTenantsBox));

    // تحديث إشغال العقار
    final prop =
        firstWhereOrNull(properties.values, (p) => p.id == cLive.propertyId);
    if (prop != null) {
      if (prop.parentBuildingId != null) {
        prop.occupiedUnits = 0;
        await prop.save();
        final siblings = properties.values
            .where((e) => e.parentBuildingId == prop.parentBuildingId);
        final count = siblings.where((e) => e.occupiedUnits > 0).length;
        final building = firstWhereOrNull(
            properties.values, (e) => e.id == prop.parentBuildingId);
        if (building != null) {
          building.occupiedUnits = count;
          await building.save();
        }
      } else {
        prop.occupiedUnits = 0;
        await prop.save();
      }
    }

    // تحديث عدّاد عقود المستأجر (لو كان حسابك يعتمد عليه)
    final t = firstWhereOrNull(tenants.values, (x) => x.id == cLive.tenantId);
    if (t != null && cLive.isActiveNow && t.activeContractsCount > 0) {
      t.activeContractsCount -= 1;
      t.updatedAt = SaTimeLite.now();
      await t.save();
    }

    // 🔻 حذف السندات المرتبطة (احتياط إضافي)
    final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
    final cid = cLive.id; // احفظ المعرف قبل الحذف
    for (final inv
        in invBox.values.where((i) => i.contractId == cid).toList()) {
      await inv.delete();
    }

    // ✅ الحذف الفعلي للعقد من الـ box
    await cLive.delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف العقد',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      Navigator.of(context).pop(); // رجوع من شاشة التفاصيل
    }
  }
}

/// =================================================================================
/// شاشة إضافة/تعديل عقد
/// =================================================================================
class _ContractSnapshotScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ContractSnapshotScaffold({
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

Widget _snapshotVisibleRowInfo(String label, String? value, {VoidCallback? onTap}) {
  final has = (value ?? '').trim().isNotEmpty;
  if (!has) return const SizedBox.shrink();
  final valueText = Text(
    value!,
    style: GoogleFonts.cairo(
      color: onTap == null ? Colors.white : const Color(0xFF93C5FD),
      decoration: onTap == null ? null : TextDecoration.underline,
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
                color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: onTap == null
              ? valueText
              : InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8.r),
                  child: valueText,
                ),
        ),
      ],
    ),
  );
}

class _SnapshotAttachmentGrid extends StatelessWidget {
  final String title;
  final List<String> paths;
  final Future<void> Function(String path) onTapAttachment;

  const _SnapshotAttachmentGrid({
    required this.title,
    required this.paths,
    required this.onTapAttachment,
  });

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return _DarkCard(
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('$title (${paths.length})'),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: paths.map((path) {
              return InkWell(
                onTap: () => onTapAttachment(path),
                borderRadius: BorderRadius.circular(10.r),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    width: 92.w,
                    height: 92.w,
                    color: Colors.white.withOpacity(0.08),
                    child: _buildSnapshotAttachmentThumb(path),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ContractTenantSnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  final Future<void> Function(String path) onAttachmentTap;
  final Future<void> Function()? onOpenOriginal;

  const _ContractTenantSnapshotScreen({
    required this.snapshot,
    required this.onAttachmentTap,
    this.onOpenOriginal,
  });

  Widget _dateRow(String label, String key) {
    final value = _snapshotDateValue(snapshot, key);
    return _snapshotVisibleRowInfo(
        label, value == null ? null : _fmtDateDynamic(value));
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = _snapshotString(snapshot, 'addressLine') != null ||
        _snapshotString(snapshot, 'city') != null ||
        _snapshotString(snapshot, 'region') != null ||
        _snapshotString(snapshot, 'postalCode') != null;
    final hasCompany = _snapshotString(snapshot, 'companyName') != null ||
        _snapshotString(snapshot, 'companyCommercialRegister') != null ||
        _snapshotString(snapshot, 'companyRepresentativeName') != null ||
        _snapshotString(snapshot, 'companyRepresentativePhone') != null ||
        _snapshotString(snapshot, 'companyBankName') != null ||
        _snapshotString(snapshot, 'companyBankAccountNumber') != null ||
        _snapshotString(snapshot, 'companyTaxNumber') != null;
    final hasService = _snapshotString(snapshot, 'serviceSpecialization') != null;
    final tags = _snapshotStringList(snapshot, 'tags');
    final attachments = _snapshotStringList(snapshot, 'attachmentPaths');
    final isBlacklisted = _snapshotBoolValue(snapshot, 'isBlacklisted') == true;
    final hasAdditional = _snapshotString(snapshot, 'emergencyName') != null ||
        _snapshotString(snapshot, 'emergencyPhone') != null ||
        _snapshotString(snapshot, 'tenantBankName') != null ||
        _snapshotString(snapshot, 'tenantBankAccountNumber') != null ||
        _snapshotString(snapshot, 'tenantTaxNumber') != null ||
        tags.isNotEmpty ||
        isBlacklisted ||
        _snapshotString(snapshot, 'blacklistReason') != null ||
        _snapshotString(snapshot, 'notes') != null;

    return _ContractSnapshotScaffold(
      title: 'نسخة المستأجر',
      children: [
        _noteCard(
          'هذه نسخة محفوظة من بيانات المستأجر وقت العقد، وتبقى ثابتة حتى لو تغيرت البيانات الحالية لاحقًا. إذا أردت فتح بيانات المستأجر الأصلية، اضغط على اسم المستأجر.',
        ),
        SizedBox(height: 10.h),
        _DarkCard(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('بيانات المستأجر وقت العقد'),
                _snapshotVisibleRowInfo(
                  'الاسم',
                  _snapshotString(snapshot, 'fullName'),
                  onTap: onOpenOriginal == null ? null : () => onOpenOriginal!(),
                ),
                _snapshotVisibleRowInfo(
                    'نوع العميل', _snapshotString(snapshot, 'clientTypeLabel')),
              _snapshotVisibleRowInfo(
                  'رقم الهوية', _snapshotString(snapshot, 'nationalId')),
              _snapshotVisibleRowInfo(
                  'رقم الجوال', _snapshotString(snapshot, 'phone')),
              _snapshotVisibleRowInfo(
                  'البريد الإلكتروني', _snapshotString(snapshot, 'email')),
              _dateRow('تاريخ الميلاد', 'dateOfBirth'),
              _snapshotVisibleRowInfo(
                  'الجنسية', _snapshotString(snapshot, 'nationality')),
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
                _sectionTitle('العنوان وقت العقد'),
                _snapshotVisibleRowInfo(
                    'العنوان', _snapshotString(snapshot, 'addressLine')),
                _snapshotVisibleRowInfo(
                    'المدينة', _snapshotString(snapshot, 'city')),
                _snapshotVisibleRowInfo(
                    'المنطقة', _snapshotString(snapshot, 'region')),
                _snapshotVisibleRowInfo(
                    'الرمز البريدي', _snapshotString(snapshot, 'postalCode')),
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
                _sectionTitle('بيانات إضافية'),
                _snapshotVisibleRowInfo(
                    'اسم الطوارئ', _snapshotString(snapshot, 'emergencyName')),
                _snapshotVisibleRowInfo(
                    'جوال الطوارئ', _snapshotString(snapshot, 'emergencyPhone')),
                _snapshotVisibleRowInfo(
                    'اسم البنك', _snapshotString(snapshot, 'tenantBankName')),
                _snapshotVisibleRowInfo(
                    'رقم الحساب',
                    _snapshotString(snapshot, 'tenantBankAccountNumber')),
                _snapshotVisibleRowInfo(
                    'الرقم الضريبي', _snapshotString(snapshot, 'tenantTaxNumber')),
                _snapshotVisibleRowInfo(
                    'الوسوم', tags.isEmpty ? null : tags.join('، ')),
                _snapshotVisibleRowInfo(
                    'في القائمة السوداء', isBlacklisted ? 'نعم' : null),
                _snapshotVisibleRowInfo('سبب القائمة السوداء',
                    _snapshotString(snapshot, 'blacklistReason')),
                _snapshotVisibleRowInfo(
                    'الملاحظات', _snapshotString(snapshot, 'notes')),
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
                _sectionTitle('بيانات الشركة وقت العقد'),
                _snapshotVisibleRowInfo(
                    'اسم الشركة', _snapshotString(snapshot, 'companyName')),
                _snapshotVisibleRowInfo('السجل التجاري',
                    _snapshotString(snapshot, 'companyCommercialRegister')),
                _snapshotVisibleRowInfo(
                    'الرقم الضريبي', _snapshotString(snapshot, 'companyTaxNumber')),
                _snapshotVisibleRowInfo('اسم الممثل',
                    _snapshotString(snapshot, 'companyRepresentativeName')),
                _snapshotVisibleRowInfo('جوال الممثل',
                    _snapshotString(snapshot, 'companyRepresentativePhone')),
                _snapshotVisibleRowInfo('بنك الشركة',
                    _snapshotString(snapshot, 'companyBankName')),
                _snapshotVisibleRowInfo('حساب الشركة',
                    _snapshotString(snapshot, 'companyBankAccountNumber')),
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
                _sectionTitle('بيانات الخدمة وقت العقد'),
                _snapshotVisibleRowInfo(
                    'التخصص', _snapshotString(snapshot, 'serviceSpecialization')),
              ],
            ),
          ),
        ],
        if (attachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _SnapshotAttachmentGrid(
            title: 'مرفقات المستأجر وقت العقد',
            paths: attachments,
            onTapAttachment: onAttachmentTap,
          ),
        ],
      ],
    );
  }
}

class _ContractPropertySnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> propertySnapshot;
  final Map<String, dynamic>? buildingSnapshot;
  final String? tenantName;
  final Future<void> Function(String path) onAttachmentTap;
  final Future<void> Function()? onOpenOriginalTenant;
  final Future<void> Function()? onOpenOriginalProperty;
  final Future<void> Function()? onOpenOriginalBuilding;

  const _ContractPropertySnapshotScreen({
    required this.propertySnapshot,
    this.buildingSnapshot,
    this.tenantName,
    required this.onAttachmentTap,
    this.onOpenOriginalTenant,
    this.onOpenOriginalProperty,
    this.onOpenOriginalBuilding,
  });

  Widget _dateRow(Map<String, dynamic> source, String label, String key) {
    final value = _snapshotDateValue(source, key);
    return _snapshotVisibleRowInfo(
        label, value == null ? null : _fmtDateDynamic(value));
  }

  String? _moneyText(Map<String, dynamic> source, String amountKey) {
    final amount = _snapshotNumberText(source, amountKey);
    if (amount == null) return null;
    final currency = _snapshotString(source, 'currency');
    if (currency == null) return amount;
    return '$amount $currency';
  }

  String? _areaText(Map<String, dynamic> source) {
    final area = _snapshotNumberText(source, 'area');
    return area == null ? null : '$area م2';
  }

  @override
  Widget build(BuildContext context) {
    final hasBuilding = buildingSnapshot != null && buildingSnapshot!.isNotEmpty;
    final propertyAttachments =
        _snapshotStringList(propertySnapshot, 'documentAttachmentPaths');
    final buildingAttachments = hasBuilding
        ? _snapshotStringList(buildingSnapshot, 'documentAttachmentPaths')
        : const <String>[];
    final propertyDescription = _snapshotPropertyFreeDescription(propertySnapshot);
    final buildingDescription =
        hasBuilding ? _snapshotPropertyFreeDescription(buildingSnapshot) : null;
    final furnishingText = _snapshotPropertyFurnishingText(propertySnapshot);
    final propertyTypeLabel = _snapshotPropertyTypeDisplayLabel(
      propertySnapshot,
      buildingSnapshot: buildingSnapshot,
    );
    final propertyDescriptionLabel = hasBuilding ? 'وصف الوحدة' : 'وصف العقار';
    final propertyTotalUnits = _snapshotIntValue(propertySnapshot, 'totalUnits');
    final propertyOccupiedUnits = _snapshotIntValue(propertySnapshot, 'occupiedUnits');
    final effectivePropertyTotalUnits =
        propertyTotalUnits != null && propertyTotalUnits > 0
            ? propertyTotalUnits
            : null;
    final propertyOccupiedDisplay = effectivePropertyTotalUnits == null
        ? null
        : ((propertyOccupiedUnits ?? 0) < 0
            ? 0
            : ((propertyOccupiedUnits ?? 0) > effectivePropertyTotalUnits
                ? effectivePropertyTotalUnits
                : (propertyOccupiedUnits ?? 0)));
    final propertyVacantDisplay =
        effectivePropertyTotalUnits == null || propertyOccupiedDisplay == null
            ? null
            : (effectivePropertyTotalUnits - propertyOccupiedDisplay);
    final buildingTotalUnits =
        hasBuilding ? _snapshotIntValue(buildingSnapshot, 'totalUnits') : null;
    final effectiveBuildingTotalUnits =
        buildingTotalUnits != null && buildingTotalUnits > 0
            ? buildingTotalUnits
            : null;
    final rawBuildingOccupiedUnits =
        hasBuilding ? _snapshotIntValue(buildingSnapshot, 'occupiedUnits') : null;
    final buildingOccupiedDisplay = !hasBuilding || effectiveBuildingTotalUnits == null
        ? null
        : (() {
            var occupied = rawBuildingOccupiedUnits ?? 0;
            if (occupied <= 0) {
              occupied = (propertyOccupiedUnits != null && propertyOccupiedUnits! > 0)
                  ? propertyOccupiedUnits!
                  : 1;
            }
            if (occupied < 0) return 0;
            if (occupied > effectiveBuildingTotalUnits) {
              return effectiveBuildingTotalUnits;
            }
            return occupied;
          })();
    final buildingVacantDisplay =
        effectiveBuildingTotalUnits == null || buildingOccupiedDisplay == null
            ? null
            : (effectiveBuildingTotalUnits - buildingOccupiedDisplay);
    final buildingTypeLabel =
        hasBuilding ? _snapshotBuildingTypeDisplayLabel(buildingSnapshot) : null;

    return _ContractSnapshotScaffold(
      title: 'نسخة العقار',
      children: [
        _noteCard(
          'هذه نسخة محفوظة من بيانات العقار وقت العقد، وتبقى ثابتة حتى لو تغيرت بيانات العقار الحالية لاحقًا. إذا أردت فتح تفاصيل العقار الأصلي، اضغط على اسم العقار.',
        ),
        SizedBox(height: 10.h),
        _DarkCard(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('بيانات العقار وقت العقد'),
              _snapshotVisibleRowInfo(
                'اسم العقار',
                _snapshotString(propertySnapshot, 'name'),
                onTap: onOpenOriginalProperty == null
                    ? null
                    : () => onOpenOriginalProperty!(),
              ),
              _snapshotVisibleRowInfo(
                'اسم المستأجر',
                tenantName?.trim(),
                onTap: onOpenOriginalTenant == null
                    ? null
                    : () => onOpenOriginalTenant!(),
              ),
              _snapshotVisibleRowInfo('نوع العقار', propertyTypeLabel),
              _snapshotVisibleRowInfo('المفروشات', furnishingText),
              _snapshotVisibleRowInfo(
                  'العنوان', _snapshotString(propertySnapshot, 'address')),
              _snapshotVisibleRowInfo(
                  'القيمة الإيجارية', _moneyText(propertySnapshot, 'price')),
              _snapshotVisibleRowInfo(
                  'المساحة', _areaText(propertySnapshot)),
              _snapshotVisibleRowInfo('عدد الغرف',
                  _snapshotNumberText(propertySnapshot, 'rooms')),
              _snapshotVisibleRowInfo('عدد الطوابق',
                  _snapshotNumberText(propertySnapshot, 'floors')),
              if (!hasBuilding)
                _snapshotVisibleRowInfo(
                    'عدد الوحدات',
                    effectivePropertyTotalUnits == null
                        ? null
                        : '$effectivePropertyTotalUnits'),
              if (!hasBuilding)
                _snapshotVisibleRowInfo(
                    'عدد الوحدات المشغولة',
                    propertyOccupiedDisplay == null
                        ? null
                        : '$propertyOccupiedDisplay'),
              if (!hasBuilding)
                _snapshotVisibleRowInfo(
                    'عدد الوحدات الخالية',
                    propertyVacantDisplay == null ? null : '$propertyVacantDisplay'),
              _snapshotVisibleRowInfo('وضع التأجير',
                  _snapshotString(propertySnapshot, 'rentalModeLabel')),
              _snapshotVisibleRowInfo(
                  'نوع الوثيقة', _snapshotString(propertySnapshot, 'documentType')),
              _snapshotVisibleRowInfo(
                  'رقم الوثيقة', _snapshotString(propertySnapshot, 'documentNumber')),
              _dateRow(propertySnapshot, 'تاريخ الوثيقة', 'documentDate'),
              _snapshotVisibleRowInfo('رقم الكهرباء',
                  _snapshotString(propertySnapshot, 'electricityNumber')),
              _snapshotVisibleRowInfo('وضع الكهرباء',
                  _snapshotString(propertySnapshot, 'electricityMode')),
              _snapshotVisibleRowInfo('حصة الكهرباء',
                  _snapshotString(propertySnapshot, 'electricityShare')),
              _snapshotVisibleRowInfo(
                  'رقم المياه', _snapshotString(propertySnapshot, 'waterNumber')),
              _snapshotVisibleRowInfo(
                  'وضع المياه', _snapshotString(propertySnapshot, 'waterMode')),
              _snapshotVisibleRowInfo(
                  'حصة المياه', _snapshotString(propertySnapshot, 'waterShare')),
              _snapshotVisibleRowInfo(
                  'قيمة المياه', _snapshotString(propertySnapshot, 'waterAmount')),
              _snapshotVisibleRowInfo(
                  propertyDescriptionLabel, propertyDescription),
              if (hasBuilding) ...[
                _snapshotVisibleRowInfo(
                  'اسم العمارة',
                  _snapshotString(buildingSnapshot, 'name'),
                  onTap: onOpenOriginalBuilding == null
                      ? null
                      : () => onOpenOriginalBuilding!(),
                ),
                _snapshotVisibleRowInfo(
                    'نوع العقار', buildingTypeLabel),
                _snapshotVisibleRowInfo(
                    'عنوان العمارة', _snapshotString(buildingSnapshot, 'address')),
                _snapshotVisibleRowInfo('عدد طوابق العمارة',
                    _snapshotNumberText(buildingSnapshot, 'floors')),
                _snapshotVisibleRowInfo(
                    'عدد وحدات العمارة',
                    effectiveBuildingTotalUnits == null
                        ? null
                        : '$effectiveBuildingTotalUnits'),
                _snapshotVisibleRowInfo(
                    'عدد الوحدات المشغولة',
                    buildingOccupiedDisplay == null
                        ? null
                        : '$buildingOccupiedDisplay'),
                _snapshotVisibleRowInfo(
                    'عدد الوحدات الخالية',
                    buildingVacantDisplay == null ? null : '$buildingVacantDisplay'),
                _snapshotVisibleRowInfo('نوع وثيقة\nالعمارة',
                    _snapshotString(buildingSnapshot, 'documentType')),
                _snapshotVisibleRowInfo('رقم وثيقة العمارة',
                    _snapshotString(buildingSnapshot, 'documentNumber')),
                _dateRow(buildingSnapshot!, 'تاريخ وثيقة العمارة', 'documentDate'),
                _snapshotVisibleRowInfo('رقم كهرباء العمارة',
                    _snapshotString(buildingSnapshot, 'electricityNumber')),
                _snapshotVisibleRowInfo('رقم مياه العمارة',
                    _snapshotString(buildingSnapshot, 'waterNumber')),
                _snapshotVisibleRowInfo('وصف العمارة', buildingDescription),
              ],
            ],
          ),
        ),
        if (propertyAttachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _SnapshotAttachmentGrid(
            title: 'مرفقات العقار وقت العقد',
            paths: propertyAttachments,
            onTapAttachment: onAttachmentTap,
          ),
        ],
        if (buildingAttachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _SnapshotAttachmentGrid(
            title: 'مرفقات العمارة وقت العقد',
            paths: buildingAttachments,
            onTapAttachment: onAttachmentTap,
          ),
        ],
      ],
    );
  }
}

class AddOrEditContractScreen extends StatefulWidget {
  final Contract? existing;
  const AddOrEditContractScreen({super.key, this.existing});

  @override
  State<AddOrEditContractScreen> createState() =>
      _AddOrEditContractScreenState();
}

class _AddOrEditContractScreenState extends State<AddOrEditContractScreen> {
  final _formKey = GlobalKey<FormState>();

  Tenant? _selectedTenant;
  Property? _selectedProperty;

  DateTime? _startDate;
  DateTime? _endDate;
  final _rent = TextEditingController();
  final _advance = TextEditingController();
  final _daysCtrl = TextEditingController(text: '1'); // لليومي
  final _ejarNo = TextEditingController();

  PaymentCycle _cycle = PaymentCycle.monthly;
  int _cycleYears = 1;
  ContractTerm _term = ContractTerm.monthly;
  int _termYears = 1;
  AdvanceMode _advMode = AdvanceMode.none;
  String _currency = 'SAR';
  final _notes = TextEditingController();
  final List<String> _attachments = <String>[];
  final Set<String> _initialLocalAttachments = <String>{};
  final Map<String, Future<String>> _remoteThumbUrls = {};
  bool _processingAttachments = false;
  bool _advanceLimitExceeded = false; // المقدم تجاوز المبلغ الكلي
  bool _rentLimitExceeded = false; // ✅ هنا بالضبط
  bool _ejarLimitExceeded = false;
  int? _dailyContractEndHour;
  int _termFieldResetTick = 0;

  int _inferAnnualYearsFromDates(DateTime start, DateTime end) {
    int months = (end.year - start.year) * 12 + (end.month - start.month);
    if (end.day < start.day) months -= 1;
    final y = (months / 12).round();
    return y.clamp(1, 10);
  }

  Box<Contract> get _contracts => Hive.box<Contract>(boxName(kContractsBox));
  Box<Tenant> get _tenants => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties => Hive.box<Property>(boxName(kPropertiesBox));

  String _formatRentPrefillValue(double? value) {
    if (value == null || value <= 0) return '';
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _applySelectedPropertyRent(Property property) {
    if (isEdit) return;
    _rent.text = _formatRentPrefillValue(property.price);
  }

  Future<Box> _sessionBox() async {
    if (Hive.isBoxOpen('sessionBox')) return Hive.box('sessionBox');
    return Hive.openBox('sessionBox');
  }

  int? _effectiveDailyCheckoutHour() {
    final existing = widget.existing;
    if (existing?.term == ContractTerm.daily) {
      final saved = _normalizeDailyCheckoutHour(existing?.dailyCheckoutHour);
      if (saved != null) return saved;
    }
    return _dailyContractEndHour;
  }

  Future<void> _loadDailyContractSettings() async {
    try {
      final session = await _sessionBox();
      final localHour = _normalizeDailyCheckoutHour(
        session.get(kDailyContractEndHourField),
      );
      if (mounted) {
        setState(() => _dailyContractEndHour = localHour);
      } else {
        _dailyContractEndHour = localHour;
      }
    } catch (_) {}

    final workspaceUid = effectiveUid().trim();
    if (workspaceUid.isEmpty || workspaceUid == 'guest') return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_prefs')
          .doc(workspaceUid)
          .get();
      final remoteHour = _normalizeDailyCheckoutHour(
        snap.data()?[kDailyContractEndHourField],
      );
      final session = await _sessionBox();
      if (remoteHour == null) {
        await session.delete(kDailyContractEndHourField);
      } else {
        await session.put(kDailyContractEndHourField, remoteHour);
      }
      if (mounted) {
        setState(() => _dailyContractEndHour = remoteHour);
      } else {
        _dailyContractEndHour = remoteHour;
      }
    } catch (_) {
      // نكتفي بالقيمة المحلية عند تعذر الوصول للسيرفر.
    }
  }

  Future<bool> _ensureDailySettingsConfigured() async {
    if (_effectiveDailyCheckoutHour() != null) return true;

    final shouldOpenSettings = await CustomConfirmDialog.show(
      context: context,
      title: 'تنبيه',
      message:
          'يجب أولًا إعداد وقت انتهاء العقود اليومية من شاشة الإعدادات.',
      confirmLabel: 'موافق',
      cancelLabel: 'إلغاء',
      confirmColor: const Color(0xFF0F766E),
    );
    if (!mounted) return false;
    if (!shouldOpenSettings) {
      if (!isEdit) {
        await Navigator.of(context).maybePop();
      }
      return false;
    }

    await AppSideDrawer.openSettingsSheet(context);
    await _loadDailyContractSettings();
    return _effectiveDailyCheckoutHour() != null;
  }

  void _applySelectedTerm(ContractTerm nextTerm) {
    setState(() {
      _term = nextTerm;
      if (_term != ContractTerm.annual) _termYears = 1;
      if (_term != ContractTerm.annual) _cycleYears = 1;
      _applyTermDatesFromToday();
      _ensureCycleFitsTerm();
      if (_isTermEqualsCycleSelection()) {
        _advMode = AdvanceMode.none;
        _advance.clear();
      }
    });
  }

  void _resetTermFieldSelection() {
    if (!mounted) return;
    setState(() {
      _termFieldResetTick++;
    });
  }

  Future<void> _handleTermChanged(ContractTerm? value) async {
    final nextTerm = value ?? ContractTerm.monthly;
    if (nextTerm == _term) return;
    if (nextTerm == ContractTerm.daily) {
      final ready = await _ensureDailySettingsConfigured();
      if (!ready) {
        _resetTermFieldSelection();
        return;
      }
    }
    if (!mounted) return;
    _applySelectedTerm(nextTerm);
  }

  Future<String> _nextContractSerial() async {
    final year = SaTimeLite.now().year;

    int maxSeq = 0;
    try {
      // احسب أكبر تسلسل لنفس السنة من العقود الموجودة حاليًا في الصندوق
      for (final c in _contracts.values) {
        final s = c.serialNo; // أمثلة: 2025-12 أو 2025-0007
        if (s != null && s.startsWith('$year-')) {
          final tail = s.split('-').last; // "12" أو "0007"
          final n = int.tryParse(tail) ?? 0; // 12 أو 7
          if (n > maxSeq) maxSeq = n;
        }
      }
    } catch (_) {
      // لو صار أي خطأ، نعتبر أنه لا يوجد عقود (maxSeq = 0)
    }

    final next = maxSeq + 1;
    return '$year-${next.toString().padLeft(4, '0')}'; // 2025-0001, 2025-0002 ...
  }

  bool get isEdit => widget.existing != null;

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    _loadDailyContractSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }

      // ✅ التقاط وسائط المسار لملء الحقول تلقائيًا (/contracts/new)
      _prefillFromRouteArgs();
    });

    final c = widget.existing;
    if (c != null) {
      _selectedTenant =
          firstWhereOrNull(_tenants.values, (t) => t.id == c.tenantId);
      _selectedProperty =
          firstWhereOrNull(_properties.values, (p) => p.id == c.propertyId);
      _startDate = _dateOnly(c.startDate);
      _endDate = _dateOnly(c.endDate);
      _term = c.term;
      _termYears = c.term == ContractTerm.annual
          ? ((c.termYears > 1)
              ? c.termYears.clamp(1, 10)
              : _inferAnnualYearsFromDates(c.startDate, c.endDate))
          : 1;
      _cycle = c.paymentCycle;
      _cycleYears =
          c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears.clamp(1, 10);
      if (_term != ContractTerm.daily) {
        final allowed = _allowedCyclesForSelection();
        if (!allowed.contains(_cycle) && allowed.isNotEmpty) {
          _cycle = allowed.first;
        }
      }

      _currency = c.currency;
      _advMode = c.advanceMode;
      _advance.text = c.advancePaid?.toString() ?? '';
      if (c.term == ContractTerm.daily) {
        final days = _dailyContractDays(c.startDate, c.endDate);
        _daysCtrl.text = days.toString();
        final perDay = days > 0 ? (c.totalAmount / days) : c.totalAmount;
        _rent.text = perDay.toStringAsFixed(2);
      } else {
        _rent.text = c.totalAmount.toString();
      }
      _notes.text = c.notes ?? '';
      _attachments
        ..clear()
        ..addAll(c.attachmentPaths);
      _initialLocalAttachments
        ..clear()
        ..addAll(_attachments.where((path) => !_isRemoteAttachment(path)));
      _ejarNo.text = c.ejarContractNo ?? '';
    } else {
      // ضبط افتراضي على اليوم بناءً على فترة العقد الافتراضية
      _startDate = today();
      _endDate = _termEndInclusiveWithYears(_startDate!, _term, _termYears);
    }
    _ensureCycleFitsTerm();
    _daysCtrl.addListener(_onDailyInputsChanged);
  }

  void _prefillFromRouteArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final m = args.cast<String, dynamic>();
      final renewalSource = m['renewFromContract'];
      final hasRenewalPrefill = renewalSource is Contract;
      final propertyId = m['prefillPropertyId'] as String?;
      final tenantId = m['prefillTenantId'] as String?;

      if (hasRenewalPrefill) {
        _applyRenewalPrefill(renewalSource);
      }

      if (propertyId != null) {
        final p = firstWhereOrNull(
            _properties.values, (x) => x.id == propertyId && !x.isArchived);
        if (p != null) {
          _selectedProperty = p;
          if (!hasRenewalPrefill) {
            _applySelectedPropertyRent(p);
          }
        }
      }
      if (tenantId != null) {
        final t = firstWhereOrNull(
            _tenants.values, (x) => x.id == tenantId && !x.isArchived);
        if (t != null) _selectedTenant = t;
      }
      if (mounted) setState(() {});
    } else if (args is String) {
      // دعم تمرير المعرّف كسلسلة مباشرة (اعتبره propertyId)
      final p = firstWhereOrNull(
          _properties.values, (x) => x.id == args && !x.isArchived);
      if (p != null) {
        _selectedProperty = p;
        _applySelectedPropertyRent(p);
        if (mounted) setState(() {});
      }
    }
  }

  void _applyRenewalPrefill(Contract source) {
    final property = firstWhereOrNull(
        _properties.values, (x) => x.id == source.propertyId && !x.isArchived);
    final tenant = firstWhereOrNull(
        _tenants.values, (x) => x.id == source.tenantId && !x.isArchived);

    if (property != null) _selectedProperty = property;
    if (tenant != null) _selectedTenant = tenant;

    _startDate = source.term == ContractTerm.daily
        ? _dateOnly(source.endDate)
        : _dateOnly(source.endDate).add(const Duration(days: 1));
    _term = source.term;
    _termYears = source.term == ContractTerm.annual
        ? (source.termYears <= 0 ? 1 : source.termYears.clamp(1, 10))
        : 1;
    _cycle = source.paymentCycle;
    _cycleYears =
        source.paymentCycleYears <= 0 ? 1 : source.paymentCycleYears.clamp(1, 10);
    _currency = source.currency;
    _advMode = AdvanceMode.none;
    _notes.text = source.notes ?? '';
    _attachments
      ..clear()
      ..addAll(source.attachmentPaths);
    _ejarNo.text = source.ejarContractNo ?? '';

    if (_term == ContractTerm.daily) {
      final days = _dailyContractDays(source.startDate, source.endDate);
      _daysCtrl.text = days.toString();
      final perDay = days > 0 ? (source.totalAmount / days) : source.totalAmount;
      _rent.text = perDay.toStringAsFixed(2);
    } else {
      _rent.text = source.totalAmount.toString();
    }

    _ensureCycleFitsTerm();

    _advance.clear();

    _recalcEndByTermAfterStartChange();
  }

  @override
  void dispose() {
    _rent.dispose();
    _advance.dispose();
    _notes.dispose();
    _ejarNo.dispose();
    _daysCtrl.removeListener(_onDailyInputsChanged);
    _daysCtrl.dispose();
    super.dispose();
  }

  void _onDailyInputsChanged() {
    if (_term != ContractTerm.daily) return;

    final d = int.tryParse(_daysCtrl.text.trim()) ?? 0;

    _startDate ??= today();

    if (d <= 0) {
      setState(() => _endDate = _startDate);
      return;
    }

    setState(() {
      // d أيام ⇒ النهاية = بداية اليوم + d أيام (بدون -1)
      _endDate = _dateOnly(_startDate!).add(Duration(days: d));
    });
  }

  int _computeDays() {
    if (_startDate == null || _endDate == null) return 0;
    return _dailyContractDays(_startDate!, _endDate!);
  }

  void _recalcEndByTermAfterStartChange() {
    if (_startDate == null) return;

    if (_term == ContractTerm.daily) {
      final d = int.tryParse(_daysCtrl.text.trim()) ?? 1;
      // يوم واحد => النهاية في اليوم التالي (بدون -1)
      _endDate = _dateOnly(_startDate!).add(Duration(days: (d <= 0 ? 1 : d)));
    } else {
      _endDate = _termEndInclusiveWithYears(_startDate!, _term, _termYears);
    }
  }

  void _applyTermDatesFromToday() {
    _startDate = today();
    if (_term == ContractTerm.daily) {
      final d = int.tryParse(_daysCtrl.text.trim()) ?? 1;
      _endDate = _dateOnly(_startDate!).add(Duration(days: (d <= 0 ? 1 : d)));
    } else {
      _endDate = _termEndInclusiveWithYears(_startDate!, _term, _termYears);
    }
  }

  int _termMonthsForSelection() {
    if (_term == ContractTerm.annual) return 12 * _termYears.clamp(1, 10);
    return _monthsInTerm(_term);
  }

  int _cycleMonthsForSelection(PaymentCycle cycle) {
    if (_term == ContractTerm.annual && cycle == PaymentCycle.annual) {
      return 12 * _cycleYears.clamp(1, 10);
    }
    return _monthsPerCycle(cycle);
  }

  List<PaymentCycle> _allowedCyclesForSelection() {
    return _allowedCyclesForTerm(_term);
  }

  bool _isTermEqualsCycleSelection() {
    if (_term == ContractTerm.daily) return false;
    return _cycleMonthsForSelection(_cycle) == _termMonthsForSelection();
  }

  String _cycleLabelForSelection(PaymentCycle pc) {
    if (_term == ContractTerm.annual &&
        pc == PaymentCycle.annual &&
        _cycleYears > 1) {
      return '$_cycleYears سنة';
    }
    return pc.label;
  }

  void _ensureCycleFitsTerm() {
    if (_term == ContractTerm.daily) return;
    if (_term != ContractTerm.annual) _cycleYears = 1;
    if (_cycleYears > _termYears) _cycleYears = _termYears;
    final allowed = _allowedCyclesForSelection();
    if (allowed.isEmpty) return;
    if (!allowed.contains(_cycle)) {
      _cycle = allowed.first; // أقرب خيار صحيح (غالبًا شهري)
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantWarn = _selectedTenant?.isBlacklisted == true;

    final days = _computeDays();
    final isDaily = _term == ContractTerm.daily;
    final rentInput = double.tryParse(_rent.text.trim()) ?? 0.0;
    final advanceVal = double.tryParse(_advance.text.trim()) ?? 0.0;
    final dailyCheckoutHour = _effectiveDailyCheckoutHour();
    final dailyCheckoutLabel = dailyCheckoutHour == null
        ? null
        : _formatHourAmPm(dailyCheckoutHour);
    final dailyRentValue = isDaily ? rentInput : 0.0;
    final totalDaily = isDaily ? (rentInput * (days > 0 ? days : 0)) : 0.0;
    final dailyStartPreview =
        isDaily && _startDate != null && dailyCheckoutHour != null
            ? DateTime(
                _startDate!.year,
                _startDate!.month,
                _startDate!.day,
                dailyCheckoutHour,
              )
            : null;
    final dailyEndPreview = isDaily && _endDate != null && dailyCheckoutHour != null
        ? DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            dailyCheckoutHour,
          )
        : null;

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
          title: Text(isEdit ? 'تعديل عقد' : 'إضافة عقد',
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
                      // المستأجر (إجباري)
                      _selectorTile(
                        title: 'المستأجر',
                        valueText: _selectedTenant?.fullName ?? 'اختر مستأجرًا',
                        onTap: _pickTenant,
                        leading: const Icon(Icons.person_rounded,
                            color: Colors.white),
                        errorText: _selectedTenant == null ? 'مطلوب' : null,
                      ),
                      if (tenantWarn) ...[
                        SizedBox(height: 6.h),
                        Align(
                            alignment: Alignment.centerRight,
                            child: _chip('المستأجر محظور',
                                bg: const Color(0xFF7F1D1D))),
                      ],
                      SizedBox(height: 12.h),

                      // العقار (إجباري)
                      _selectorTile(
                        title: 'العقار/الوحدة',
                        valueText:
                            _selectedProperty?.name ?? 'اختر عقارًا أو وحدة',
                        onTap: _pickProperty,
                        leading: const Icon(Icons.home_work_rounded,
                            color: Colors.white),
                        errorText: _selectedProperty == null ? 'مطلوب' : null,
                      ),
                      SizedBox(height: 12.h),

                      // فترة العقد (إجباري) + ضبط التواريخ فورًا من اليوم
                      DropdownButtonFormField<ContractTerm>(
                        key: ValueKey(
                          'contract_term_${_term.index}_$_termFieldResetTick',
                        ),
                        initialValue: _term,
                        decoration: _dd('فترة العقد'),
                        dropdownColor: const Color(0xFF0F172A),
                        iconEnabledColor: Colors.white70,
                        style: GoogleFonts.cairo(
                            color: Colors.white, fontWeight: FontWeight.w700),
                        items: ContractTerm.values
                            .map((t) => DropdownMenuItem(
                                value: t, child: Text(t.label)))
                            .toList(),
                        onChanged: (v) {
                          _handleTermChanged(v);
                        },
                      ),
                      SizedBox(height: 12.h),
                      if (!isDaily && _term == ContractTerm.annual) ...[
                        DropdownButtonFormField<int>(
                          initialValue: _termYears,
                          decoration: _dd('مدة العقد (بالسنوات)'),
                          dropdownColor: const Color(0xFF0F172A),
                          iconEnabledColor: Colors.white70,
                          style: GoogleFonts.cairo(
                              color: Colors.white, fontWeight: FontWeight.w700),
                          items: List.generate(
                            10,
                            (i) => i + 1,
                          )
                              .map((y) => DropdownMenuItem(
                                  value: y, child: Text('$y سنة')))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _termYears = v.clamp(1, 10);
                              if (_cycleYears > _termYears) {
                                _cycleYears = _termYears;
                              }
                              _recalcEndByTermAfterStartChange();
                              _ensureCycleFitsTerm();
                              if (_isTermEqualsCycleSelection()) {
                                _advMode = AdvanceMode.none;
                                _advance.clear();
                              }
                            });
                          },
                        ),
                        SizedBox(height: 12.h),
                      ],

                      // لليومي: عدد أيام الإيجار + ساعة الخروج
                      if (isDaily) ...[
                        _field(
                          controller: _daysCtrl,
                          label: 'عدد أيام الإيجار',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim()) ?? 0;
                            if (n <= 0) return 'أدخل رقمًا صحيحًا';
                            return null;
                          },
                        ),
                        SizedBox(height: 10.h),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 12.h,
                          ),
                          decoration: BoxDecoration(
                            color: dailyCheckoutHour == null
                                ? const Color(0xFF7C2D12).withOpacity(0.18)
                                : const Color(0xFF0F766E).withOpacity(0.16),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: dailyCheckoutHour == null
                                  ? const Color(0xFFF97316).withOpacity(0.35)
                                  : const Color(0xFF14B8A6).withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            dailyCheckoutLabel == null
                                ? 'يجب أولًا إعداد وقت انتهاء العقود اليومية من شاشة الإعدادات.'
                                : 'وقت انتهاء العقد اليومي المعتمد: $dailyCheckoutLabel',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.sp,
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                      ],

                      // التواريخ (تاريخ النهاية ثابت ومحسوب)
                      // التواريخ (تاريخ النهاية ثابت ومحسوب) — كل واحد في سطر
                      Column(
                        children: [
                          _datePickerTile(
                            label: 'تاريخ البداية',
                            date: _startDate,
                            onPick: () async {
                              final d = await _pickDate(context, _startDate);
                              if (d != null) {
                                setState(() {
                                  _startDate = _dateOnly(d);
                                  _recalcEndByTermAfterStartChange();
                                });
                              }
                            },
                          ),
                          SizedBox(height: 10.h),
                          _datePickerTile(
                            label: 'تاريخ النهاية (محسوب)',
                            date: _endDate,
                            onPick: null, // معطّل
                            enabled: false,
                          ),
                        ],
                      ),

                      SizedBox(height: 12.h),

                      // المبلغ + العملة (إجباريان)
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _rent,
                              label: isDaily
                                  ? 'قيمة الإيجار اليومي'
                                  : 'قيمة الإيجار الكلي',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                // نفس التقييد القديم: أرقام + نقطتين عشريتين
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}$'),
                                ),
                                // فورماتّر إضافي يمنع تجاوز 100,000,000 في الإيجار الكلي
                                TextInputFormatter.withFunction(
                                    (oldValue, newValue) {
                                  final text = newValue.text;

                                  // نسمح بالحذف
                                  if (text.isEmpty) {
                                    if (_rentLimitExceeded) {
                                      _rentLimitExceeded = false;
                                      // إعادة بناء لتحديث الرسالة لو كانت ظاهرة
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        setState(() {});
                                      });
                                    }
                                    return newValue;
                                  }

                                  final n = double.tryParse(text);
                                  if (n == null) return oldValue;

                                  // لو العقد يومي لا نقيّد بالحد
                                  if (isDaily) {
                                    if (_rentLimitExceeded) {
                                      _rentLimitExceeded = false;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        setState(() {});
                                      });
                                    }
                                    return newValue;
                                  }

                                  // لو حاول يتجاوز 100 مليون
                                  if (n > 100000000) {
                                    if (!_rentLimitExceeded) {
                                      _rentLimitExceeded = true;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        setState(() {});
                                      });
                                    }
                                    // نرجّع القيمة القديمة (يمنع الكتابة)
                                    return oldValue;
                                  }

                                  // داخل الحد → نلغي حالة التجاوز لو كانت مفعّلة
                                  if (_rentLimitExceeded) {
                                    _rentLimitExceeded = false;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      setState(() {});
                                    });
                                  }

                                  return newValue;
                                }),
                              ],
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) return 'مطلوب';

                                final n = double.tryParse(s);
                                if (n == null || n <= 0) {
                                  return 'أدخل مبلغًا صحيحًا';
                                }

                                // ✅ هنا نستخدم الفلاغ بدل فحص القيمة مباشرة
                                if (!isDaily && _rentLimitExceeded) {
                                  return 'تجاوزت الحد المسموح';
                                }

                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10.w),
                          // العملة ثابتة ريال سعودي
                          SizedBox(
                            width: 120.w,
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: _dd('العملة'),
                              dropdownColor: const Color(0xFF0F172A),
                              iconEnabledColor: Colors.white70,
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: 'SAR',
                                  child: Text('ريال'),
                                ),
                              ],
                              onChanged: (v) {
                                // ثبّت العملة دائمًا على SAR
                                setState(() => _currency = 'SAR');
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // دورة السداد (إجباري في غير اليومي)
                      // دورة السداد (إجباري في غير اليومي)
                      if (!isDaily) ...[
                        DropdownButtonFormField<PaymentCycle>(
                          initialValue: (() {
                            final allowed = _allowedCyclesForSelection();
                            return allowed.contains(_cycle)
                                ? _cycle
                                : (allowed.isNotEmpty
                                    ? allowed.first
                                    : PaymentCycle.monthly);
                          })(),
                          decoration: _dd('دورة السداد'),
                          dropdownColor: const Color(0xFF0F172A),
                          iconEnabledColor: Colors.white70,
                          style: GoogleFonts.cairo(
                              color: Colors.white, fontWeight: FontWeight.w700),
                          items: _allowedCyclesForSelection()
                              .map((pc) => DropdownMenuItem(
                                  value: pc,
                                  child: Text(_cycleLabelForSelection(pc))))
                              .toList(),
                          onChanged: (v) => setState(() {
                            final allowed = _allowedCyclesForSelection();
                            _cycle = v ??
                                (allowed.isNotEmpty
                                    ? allowed.first
                                    : PaymentCycle.monthly);
                            if (!(_term == ContractTerm.annual &&
                                _cycle == PaymentCycle.annual)) {
                              _cycleYears = 1;
                            } else {
                              if (_cycleYears > _termYears) {
                                _cycleYears = _termYears;
                              }
                              if (_cycleYears < 1) _cycleYears = 1;
                            }
                            if (_isTermEqualsCycleSelection()) {
                              _advMode = AdvanceMode.none;
                              _advance.clear();
                            }
                          }),
                        ),
                        if (_term == ContractTerm.annual &&
                            _termYears > 1 &&
                            _cycle == PaymentCycle.annual) ...[
                          SizedBox(height: 10.h),
                          DropdownButtonFormField<int>(
                            initialValue: _cycleYears.clamp(1, _termYears),
                            decoration: _dd('عدد سنوات دورة السداد'),
                            dropdownColor: const Color(0xFF0F172A),
                            iconEnabledColor: Colors.white70,
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                            items: List.generate(_termYears, (i) => i + 1)
                                .map(
                                  (y) => DropdownMenuItem<int>(
                                    value: y,
                                    child: Text(y == 1 ? 'سنوي' : '$y سنة'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _cycleYears = v.clamp(1, _termYears);
                                if (_isTermEqualsCycleSelection()) {
                                  _advMode = AdvanceMode.none;
                                  _advance.clear();
                                }
                              });
                            },
                          ),
                        ],

                        SizedBox(height: 6.h),

                        // ⬅️ التنبيه (بدون مقدم) يظهر هنا تحت "دورة السداد"
                        if (rentInput > 0 && _advMode == AdvanceMode.none)
                          Builder(builder: (_) {
                            final months = _termMonthsForSelection();
                            final perCycle =
                                (months / _cycleMonthsForSelection(_cycle))
                                    .ceil()
                                    .clamp(1, 1000);
                            final total = rentInput;
                            final per = total / perCycle;
                            return Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'عدد الأشهر: $months • عدد الدفعات: $perCycle • قيمة الدفعة: ${_fmtMoneyTrunc(per)} $_currency',
                                style: GoogleFonts.cairo(
                                    color: Colors.white70, fontSize: 12.sp),
                              ),
                            );
                          }),

                        SizedBox(height: 12.h),
                      ],

                      _field(
                        controller: _ejarNo,
                        label: 'رقم العقد بمنصة إيجار',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;
                            if (text.length <= 30) {
                              if (_ejarLimitExceeded) {
                                _ejarLimitExceeded = false;
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) setState(() {});
                                });
                              }
                              return newValue;
                            }
                            if (!_ejarLimitExceeded) {
                              _ejarLimitExceeded = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() {});
                              });
                            }
                            return oldValue;
                          }),
                        ],
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (_ejarLimitExceeded) return 'تجاوزت الحد المسموح';
                          if (s.isEmpty) return 'هذا الحقل مطلوب';
                          if (s.length > 30) return 'الحد الأقصى 30 رقم';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // اليومي: ملخص
                      if (isDaily &&
                          _startDate != null &&
                          _endDate != null &&
                          rentInput > 0) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'عدد أيام الإيجار: ${_dailyRentalDaysLabel(days)}',
                            style: GoogleFonts.cairo(
                                color: Colors.white70, fontSize: 12.sp),
                          ),
                        ),
                        if (dailyStartPreview != null &&
                            dailyEndPreview != null) ...[
                          SizedBox(height: 4.h),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'فترة الإيجار',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white70, fontSize: 12.sp),
                                ),
                                SizedBox(height: 4.h),
                                _dailyPeriodDetailsWidget(
                                  dailyStartPreview,
                                  dailyEndPreview,
                                  baseStyle: GoogleFonts.cairo(
                                    color: Colors.white70,
                                    fontSize: 12.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: 4.h),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'قيمة الإيجار اليومي: ${_fmtMoneyTrunc(dailyRentValue)} $_currency',
                            style: GoogleFonts.cairo(
                                color: Colors.white70, fontSize: 12.sp),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'قيمة الإيجار الإجمالي: ${_fmtMoneyTrunc(totalDaily)} $_currency',
                            style: GoogleFonts.cairo(
                                color: Colors.white70, fontSize: 12.sp),
                          ),
                        ),
                        SizedBox(height: 6.h),
                      ],

                      // الملاحظات (اختياري)
                      _field(
                          controller: _notes,
                          label: 'ملاحظات (اختياري)',
                          maxLines: 3),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'المرفقات (${_attachments.length}/3)',
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
                            onPressed:
                                _processingAttachments ? null : _pickAttachments,
                            icon: _processingAttachments
                                ? SizedBox(
                                    width: 16.w,
                                    height: 16.w,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.attach_file_rounded),
                            label: Text('إرفاق',
                                style:
                                    GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      if (_attachments.isNotEmpty) ...[
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
                                    borderRadius: BorderRadius.circular(10.r),
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
                                    onTap: () => _confirmRemoveAttachment(path),
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
                        SizedBox(height: 16.h),
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
                          label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ العقد',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_processingAttachments)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Container(
                    color: Colors.black.withOpacity(0.30),
                    alignment: Alignment.center,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
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
          currentIndex: 3,
          onTap: (i) {
            switch (i) {
              case 0:
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()));
                break;
              case 1:
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PropertiesScreen()));
                break;
              case 2:
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const tenants_ui.TenantsScreen()));
                break;
              case 3:
                // أنت هنا
                break;
            }
          },
        ),
      ),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      autovalidateMode: autovalidateMode,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: _dd(label),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _selectorTile({
    required String title,
    required String valueText,
    required VoidCallback onTap,
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

  Widget _datePickerTile(
      {required String label,
      required DateTime? date,
      required VoidCallback? onPick,
      bool enabled = true}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: enabled && onPick != null ? onPick : null,
      child: InputDecorator(
        decoration: _dd(label).copyWith(
          enabled: enabled,
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined,
                color: enabled ? Colors.white70 : Colors.white24),
            SizedBox(width: 8.w),
            // ✅ تم الاستبدال هنا لمنع الـ overflow مع التاريخ الهجري الطويل
            Expanded(
              child: Tooltip(
                message: date == null ? '—' : _fmtDateDynamic(date),
                child: Text(
                  date == null ? '—' : _fmtDateDynamic(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.cairo(
                    color: enabled ? Colors.white : Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime? init) async {
    final now = SaTimeLite.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: init ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
      helpText: 'اختر التاريخ',
      confirmText: 'اختيار',
      cancelText: 'إلغاء',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF0B1220),
              onSurface: Colors.white),
          dialogTheme:
              const DialogThemeData(backgroundColor: Color(0xFF0B1220)),
        ),
        child: child!,
      ),
    );
    return picked == null ? null : _dateOnly(picked);
  }

  Future<void> _pickTenant() async {
    final result = await showModalBottomSheet<Tenant>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TenantPickerSheet(),
    );
    if (result != null) setState(() => _selectedTenant = result);
  }

  Future<void> _pickProperty() async {
    final result = await showModalBottomSheet<Property>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PropertyPickerSheet(),
    );
    if (result != null) {
      setState(() {
        _selectedProperty = result;
        _applySelectedPropertyRent(result);
      });
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
                leading: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                title:
                    Text('فتح', style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable = await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
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
          SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<String?> _saveAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}contract_attachments');
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('لا يمكن رفع أكثر من 3 مرفقات', style: GoogleFonts.cairo()),
        ),
      );
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
    setState(() => _processingAttachments = true);
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
      if (failed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ $failed مرفق', style: GoogleFonts.cairo()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingAttachments = false);
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

  Future<bool> _confirmPeriodicServicesReadyForCreate(Property property) async {
    while (true) {
      final missing = await missingRequiredPeriodicServicesForProperty(
        property.id,
        property: property,
      );
      if (missing.isEmpty) return true;
      if (!mounted) return false;

      final openSettings = await CustomConfirmDialog.show(
        context: context,
        title: 'الخدمات الدورية غير مكتملة',
        message:
            'الخدمات غير المضبوطة: ${missing.join('، ')}.\nيُفضّل ضبطها قبل إنشاء العقد لضمان احتساب المستحقات وربطها بالعقد بشكل صحيح من أول دفعة.',
        confirmLabel: 'ضبط الآن',
        cancelLabel: 'تجاوز',
        confirmColor: const Color(0xFF0F766E),
      );

      if (!mounted) return false;
      if (openSettings != true) return true;

      await Navigator.of(context).pushNamed(
        '/property/services',
        arguments: {'propertyId': property.id},
      );

      if (!mounted) return false;
    }
  }

  Future<void> _save() async {
    // جميع الحقول إجبـارية باستثناء الملاحظات
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedTenant == null || _selectedProperty == null) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('اختر تواريخ العقد', style: GoogleFonts.cairo())));
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('تاريخ النهاية قبل البداية', style: GoogleFonts.cairo())));
      return;
    }
    if (_selectedTenant!.isBlacklisted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('المستأجر محظور — لا يمكن إنشاء عقد',
              style: GoogleFonts.cairo())));
      return;
    }

    final prop = _selectedProperty!;
    if (!_isPropertyAvailableForContract(prop)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('العقار/الوحدة غير متاحة', style: GoogleFonts.cairo())));
      return;
    }

    if (!isEdit) {
      final ready = await _confirmPeriodicServicesReadyForCreate(prop);
      if (!ready) return;
    }

    final entered = double.tryParse(_rent.text.trim()) ?? 0.0;
    double total = 0.0;
    double perCycleAmount = 0.0;
    if (_term != ContractTerm.daily) {
      final allowed = _allowedCyclesForSelection();
      if (!allowed.contains(_cycle) && allowed.isNotEmpty) {
        _cycle = allowed.first;
      }
    }

    int? checkoutHour;
    if (_term == ContractTerm.daily) {
      checkoutHour = _effectiveDailyCheckoutHour();
      if (checkoutHour == null) {
        final ready = await _ensureDailySettingsConfigured();
        if (!ready) return;
        checkoutHour = _effectiveDailyCheckoutHour();
        if (checkoutHour == null) return;
      }
      final days = int.tryParse(_daysCtrl.text.trim()) ?? 0;
      total = (entered * (days > 0 ? days : 0));
      perCycleAmount = total;
    } else {
      total = entered;
      final months = _termMonthsForSelection();
      final perCycleCount =
          (months / _cycleMonthsForSelection(_cycle)).ceil().clamp(1, 1000);
// عند coverMonths لا ننقص من الإجمالي هنا (الخصم يكون مكافئًا فقط عند التسجيل في advancePaid)
      double advAmount = 0.0;
      if (_advMode == AdvanceMode.deductFromTotal) {
        advAmount = double.tryParse(_advance.text.trim()) ?? 0.0;
      }
      final net = (total - advAmount).clamp(0, double.infinity);
      perCycleAmount = net / perCycleCount; // int → يحسب double بدون مشاكل

      checkoutHour = null;
    }

    double? advPaid;
    if (_advMode == AdvanceMode.none) {
      advPaid = null;
    } else if (_advMode == AdvanceMode.deductFromTotal) {
      // مبلغ نقدي كما هو
      advPaid = double.tryParse(_advance.text.trim()) ?? 0.0;
    } else {
      // AdvanceMode.coverMonths → المستخدم أدخل عدد الدفعات
      final cyclesInput = int.tryParse(_advance.text.trim()) ?? 0;

      // نحسب المطلوب محليًا هنا حتى لا نعتمد على متغيّرات خارج النطاق
      final months = _termMonthsForSelection(); // إجمالي أشهر مدة العقد
      final mPerCycle = _cycleMonthsForSelection(_cycle); // أشهر كل دفعة/قسط
      final perCycleCt =
          ((months / mPerCycle).ceil()).clamp(1, 1000); // عدد الدفعات في المدة
      final monthlyVal =
          months > 0 ? (total / months) : 0.0; // قيمة الشهر الواحدة

      // تأمين الحدود
      final safeCycles = cyclesInput.clamp(0, perCycleCt).toInt();
      final coveredMonths = safeCycles * mPerCycle;

      // نحول "عدد الدفعات" إلى مبلغ مكافئ ونخزّنه
      advPaid = (coveredMonths * monthlyVal).toDouble();
    }

    final selectedTenant = _selectedTenant!;
    final selectedBuilding = prop.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (e) => e.id == prop.parentBuildingId);

    if (isEdit) {
      final c = widget.existing!;
      final previousPropertyId = c.propertyId;
      final removedLocalAttachments = _removedInitialLocalAttachments();
      if (c.propertyId != prop.id) {
        final oldProp =
            firstWhereOrNull(_properties.values, (e) => e.id == c.propertyId);
        if (oldProp != null) await _releaseProperty(oldProp);
        await _occupyProperty(prop);
        c.propertyId = prop.id;
      }

      final wasActiveBefore = c.isActiveNow;

      c.tenantId = selectedTenant.id;
      c.startDate = _dateOnly(_startDate!);
      c.endDate = _dateOnly(_endDate!);
      c.term = _term;
      c.termYears = _term == ContractTerm.annual ? _termYears : 1;
      c.paymentCycle = _cycle;
      c.paymentCycleYears =
          (_term == ContractTerm.annual && _cycle == PaymentCycle.annual)
              ? _cycleYears
              : 1;
      c.currency = _currency;
      c.totalAmount = total;
      c.rentAmount = perCycleAmount;
      c.advanceMode = _advMode;
      c.advancePaid = advPaid;
      c.dailyCheckoutHour = checkoutHour;
      c.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      c.attachmentPaths = List<String>.from(_attachments);
      c.ejarContractNo = _ejarNo.text.trim();
      c.updatedAt = SaTimeLite.now();
      _applyContractSnapshots(
        c,
        tenant: selectedTenant,
        property: prop,
        building: selectedBuilding,
        overwrite: true,
      );

      await c.save();
      await _saveEjarNoLocal(c.id, c.ejarContractNo);
      await syncWaterConfigForContractChange(
        c,
        previousPropertyId: previousPropertyId,
      );

      final t = firstWhereOrNull(_tenants.values, (x) => x.id == c.tenantId);
      if (t != null) {
        final isActiveNow = c.isActiveNow;
        if (wasActiveBefore != isActiveNow) {
          if (isActiveNow) {
            t.activeContractsCount += 1;
          } else if (t.activeContractsCount > 0) {
            t.activeContractsCount -= 1;
          }
          t.updatedAt = SaTimeLite.now();
          await t.save();
        }
      }
      await _deleteLocalAttachments(removedLocalAttachments);

      if (!mounted) return;
      Navigator.of(context).pop(c);
    } else {
      // 1) احصل على الرقم التسلسلي قبل بناء العقد
      final serial = await _nextContractSerial();

      // 2) ابنِ العقد ومرّر serialNo
      final c = Contract(
        tenantId: selectedTenant.id,
        propertyId: prop.id,
        startDate: _dateOnly(_startDate!),
        endDate: _dateOnly(_endDate!),
        term: _term,
        termYears: _term == ContractTerm.annual ? _termYears : 1,
        paymentCycle: _cycle,
        paymentCycleYears:
            (_term == ContractTerm.annual && _cycle == PaymentCycle.annual)
                ? _cycleYears
                : 1,
        rentAmount: perCycleAmount,
        totalAmount: total,
        currency: _currency,
        advanceMode: _advMode,
        advancePaid: advPaid,
        dailyCheckoutHour: checkoutHour,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        attachmentPaths: List<String>.from(_attachments),
        serialNo: serial, // ← هنا
        ejarContractNo: _ejarNo.text.trim(),
      );
      _applyContractSnapshots(
        c,
        tenant: selectedTenant,
        property: prop,
        building: selectedBuilding,
        overwrite: true,
      );
      await _saveEjarNoLocal(c.id, c.ejarContractNo);

// إصدار سندات المقدم تلقائيًا (إن وجدت) — دون التأثير على أقساط السداد
      try {
        if (c.term != ContractTerm.daily &&
            c.advanceMode != AdvanceMode.none &&
            (c.advancePaid ?? 0) > 0) {
          final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
          final now = SaTimeLite.now();

          // تجهيز نص رقم العقد للعرض الجميل (سنة-تسلسل) إن وُجد
          String displaySerial(String? s) {
            final v = (s ?? '').trim();
            if (v.isEmpty) return v;
            final parts = v.split('-');
            if (parts.length == 2) {
              final a = parts[0].trim();
              final b = parts[1].trim();
              bool isYear(String x) =>
                  int.tryParse(x) != null &&
                  x.length == 4 &&
                  int.parse(x) >= 1900 &&
                  int.parse(x) <= 2100;
              if (!isYear(a) && isYear(b)) {
                final seq = a.padLeft(4, '0');
                return '$b-$seq';
              }
            }
            return v;
          }

          final serialDisplay = displaySerial(c.serialNo);
          final serialLtr = '\u200E$serialDisplay\u200E';
          final baseNote = serialDisplay.isNotEmpty
              ? 'سداد مقدم عقد رقم $serialLtr'
              : 'سداد مقدم عقد';

          if (c.advanceMode == AdvanceMode.deductFromTotal) {
            // حالة: "مقدم يخصم من الإجمالي" → سند واحدة (مدفوعة) بقيمة المقدم وتاريخها بداية العقد
            final amount = (c.advancePaid ?? 0).toDouble();
            if (amount > 0) {
              final commissionSnapshot =
                  await _loadCommissionSnapshotForContractVoucher(c, amount);
              final inv = Invoice(
                tenantId: c.tenantId,
                contractId: c.id,
                propertyId: c.propertyId,
                issueDate: now,
                dueDate:
                    _dateOnly(c.startDate), // تظهر في السجل كسند مدفوعة مسبقًا
                amount: amount,
                paidAmount: amount, // مدفوعة بالكامل
                currency: c.currency,
                note: _appendCommissionSnapshotToNote(
                  baseNote,
                  commissionMode: commissionSnapshot.mode,
                  commissionValue: commissionSnapshot.value,
                  commissionAmount: commissionSnapshot.amount,
                ),
                paymentMethod: 'نقدًا',
                createdAt: now,
                updatedAt: now,
              );
// ترقيم عند الإنشاء: لجميع السندات غير الملغاة
              if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
                inv.serialNo = _nextInvoiceSerialForContracts(invBox);
                inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
              }

              await invBox.put(inv.id, inv);
              await _syncOfficeCommissionForContractVoucher(inv.id);
            }
          } else {
            // حالة: "يغطي أشهر معينة" → أنشئ سند مدفوعة لكل قسط مغطّى (مرتّبة: الأقدم أسفل، الأحدث أعلى)
            final coveredMonths = _coveredMonthsByAdvance(c); // أشهر مغطّاة
            final mpc = _monthsPerCycleFor(c); // أشهر كل قسط
            final cyclesCovered =
                (coveredMonths / mpc).floor(); // عدد الأقساط المغطّاة
            if (cyclesCovered > 0) {
              var due = _dateOnly(c.startDate);
              final end = _dateOnly(c.endDate);
              final commissionSnapshot =
                  await _loadCommissionSnapshotForContractVoucher(
                    c,
                    c.rentAmount,
                  );
              for (int k = 0; k < cyclesCovered; k++) {
                if (due.isAfter(end)) break;

                // طابع زمني متزايد لضمان ترتيب الإدراج (الأقدم أسفل)
                final issuedAt = now.add(Duration(milliseconds: k));

                // تجنّب التكرار إن كانت هناك سند مدفوعة لنفس استحقاق القسط
                if (!_paidForDue(c, due)) {
                  final amount = c.rentAmount; // قيمة القسط القياسية
                  final inv = Invoice(
                    tenantId: c.tenantId,
                    contractId: c.id,
                    propertyId: c.propertyId,
                    issueDate: issuedAt, // كان: now
                    dueDate: _dateOnly(due), // تاريخ استحقاق القسط المغطّى
                    amount: amount,
                    paidAmount: amount, // مدفوعة بالكامل
                    currency: c.currency,
                    note: _appendCommissionSnapshotToNote(
                      baseNote,
                      commissionMode: commissionSnapshot.mode,
                      commissionValue: commissionSnapshot.value,
                      commissionAmount: commissionSnapshot.amount,
                    ),
                    paymentMethod: 'نقدًا',
                    createdAt: issuedAt, // كان: now
                    updatedAt: issuedAt, // كان: now
                  );
// ترقيم عند الإنشاء: لجميع السندات غير الملغاة
                  if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
                    inv.serialNo = _nextInvoiceSerialForContracts(invBox);
                    inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
                  }

                  await invBox.put(inv.id, inv);
                  await _syncOfficeCommissionForContractVoucher(inv.id);
                }

                // انتقل إلى استحقاق القسط التالي بحسب دورة السداد
                due = _addMonths(_dateOnly(due), mpc);
              }
            }
          }
        }
      } catch (_) {
        // عدم تعطيل حفظ العقد عند أي خطأ في إصدار السند — نتجاهل بهدوء
      }

      if (!mounted) return;
      Navigator.of(context).pop(c);
    }
  }

  bool _isPropertyAvailableForContract(Property p) {
    if (p.parentBuildingId != null) return p.occupiedUnits == 0;
    if (p.type == PropertyType.building) {
      if (p.rentalMode == RentalMode.perUnit) return false;
      return p.occupiedUnits == 0;
    }
    return p.occupiedUnits == 0;
  }

  Future<void> _occupyProperty(Property p) async {
    if (p.parentBuildingId != null) {
      p.occupiedUnits = 1;
      await p.save();
      await _recalcBuildingOccupiedUnits(p.parentBuildingId!);
      return;
    }
    p.occupiedUnits = 1;
    await p.save();
  }

  Future<void> _releaseProperty(Property p) async {
    if (p.parentBuildingId != null) {
      p.occupiedUnits = 0;
      await p.save();
      await _recalcBuildingOccupiedUnits(p.parentBuildingId!);
      return;
    }
    p.occupiedUnits = 0;
    await p.save();
  }

  Future<void> _recalcBuildingOccupiedUnits(String buildingId) async {
    final all =
        _properties.values.where((e) => e.parentBuildingId == buildingId);
    final count = all.where((e) => e.occupiedUnits > 0).length;
    final building =
        firstWhereOrNull(_properties.values, (e) => e.id == buildingId);
    if (building != null) {
      building.occupiedUnits = count;
      await building.save();
    }
  }
}

Widget _pickerSheetHandle() {
  return Container(
    width: 44.w,
    height: 5.h,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(999.r),
    ),
  );
}

Widget _pickerSheetHeader({
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

InputDecoration _pickerSheetSearchDecoration(String hintText) {
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

/// شيت اختيار المستأجر
class _TenantPickerSheet extends StatefulWidget {
  @override
  State<_TenantPickerSheet> createState() => _TenantPickerSheetState();
}

class _TenantPickerSheetState extends State<_TenantPickerSheet> {
  Box<Tenant> get _tenants => Hive.box<Tenant>(boxName(kTenantsBox));
  String _q = '';

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
                Center(child: _pickerSheetHandle()),
                SizedBox(height: 14.h),
                _pickerSheetHeader(
                  title: 'اختيار المستأجر',
                  subtitle:
                      'اختر المستأجر الذي تريد إنشاء العقد باسمه',
                ),
                SizedBox(height: 12.h),
                TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  style: GoogleFonts.cairo(color: Colors.white),
                  decoration: _pickerSheetSearchDecoration(
                    'ابحث بالاسم أو الهوية أو الجوال',
                  ),
                ),
                SizedBox(height: 10.h),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _tenants.listenable(),
                    builder: (context, Box<Tenant> b, _) {
                    bool allowedForContract(Tenant t) {
                      final raw = t.clientType.trim().toLowerCase();
                      if (raw.isEmpty) return true; // بيانات قديمة = مستأجر
                      if (raw == 'tenant' || raw == 'مستأجر') return true;
                      if (raw == 'company' ||
                          raw == 'tenant_company' ||
                          raw == 'شركة' ||
                          raw == 'مستأجر (شركة)') {
                        return true;
                      }
                      return false; // يستبعد مقدم الخدمة وأي نوع آخر
                    }

                    var items = b.values
                        .where((t) => !t.isArchived && allowedForContract(t))
                        .toList();
                    if (_q.isNotEmpty) {
                      final q = _q.toLowerCase();
                      items = items
                          .where((t) =>
                              t.fullName.toLowerCase().contains(q) ||
                              t.nationalId.toLowerCase().contains(q) ||
                              t.phone.toLowerCase().contains(q))
                          .toList();
                    }
                    items.sort((a, c) => a.fullName.compareTo(c.fullName));

                    if (items.isEmpty) {
                      return Center(
                          child: Text('لا يوجد مستأجرون',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)));
                    }

                    return Scrollbar(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 6.h),
                        itemBuilder: (_, i) {
                          final t = items[i];
                          return ListTile(
                            onTap: () => Navigator.of(context).pop(t),
                            leading:
                                const Icon(Icons.person, color: Colors.white),
                            title: Text(
                              t.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                            subtitle: Text(
                              'هوية: ${t.nationalId} • جوال: ${t.phone}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(color: Colors.white70),
                            ),
                            trailing: t.isBlacklisted
                                ? _chip('محظور', bg: const Color(0xFF7F1D1D))
                                : null,
                          );
                        },
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

/// شيت اختيار العقار/الوحدة المتاحة فقط
class _PropertyPickerSheet extends StatefulWidget {
  @override
  State<_PropertyPickerSheet> createState() => _PropertyPickerSheetState();
}

class _PropertyPickerSheetState extends State<_PropertyPickerSheet> {
  Box<Property> get _properties => Hive.box<Property>(boxName(kPropertiesBox));
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
                Center(child: _pickerSheetHandle()),
                SizedBox(height: 14.h),
                _pickerSheetHeader(
                  title: 'اختيار العقار أو الوحدة',
                  subtitle:
                      'اختر العقار أو الوحدة التي تريد ربط العقد بها',
                ),
                SizedBox(height: 12.h),
                TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  style: GoogleFonts.cairo(color: Colors.white),
                  decoration: _pickerSheetSearchDecoration(
                    'ابحث باسم العقار أو العنوان',
                  ),
                ),
                SizedBox(height: 10.h),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _properties.listenable(),
                    builder: (context, Box<Property> b, _) {
                    final all =
                        b.values.where((p) => !p.isArchived).toList();
                    final q = _q.toLowerCase();

                    bool matches(Property p) {
                      if (q.isEmpty) return true;
                      return p.name.toLowerCase().contains(q) ||
                          p.address.toLowerCase().contains(q);
                    }

                    final topLevel =
                        all.where((p) => p.parentBuildingId == null).toList();
                    final unitsByBuilding = <String, List<Property>>{};
                    for (final p in all) {
                      final parentId = p.parentBuildingId;
                      if (parentId == null) continue;
                      if (p.occupiedUnits > 0) continue; // فقط الوحدات المتاحة
                      final list = unitsByBuilding.putIfAbsent(
                          parentId, () => <Property>[]);
                      list.add(p);
                    }
                    for (final units in unitsByBuilding.values) {
                      units.sort((a, c) => a.name.compareTo(c.name));
                    }

                    topLevel.sort((a, c) {
                      final aHasUnits = a.type == PropertyType.building &&
                          (unitsByBuilding[a.id]?.isNotEmpty ?? false);
                      final cHasUnits = c.type == PropertyType.building &&
                          (unitsByBuilding[c.id]?.isNotEmpty ?? false);
                      if (aHasUnits != cHasUnits) return aHasUnits ? -1 : 1;
                      return a.name.compareTo(c.name);
                    });

                    final hasAny = topLevel.any((p) {
                      final units = unitsByBuilding[p.id] ?? const <Property>[];
                      if (p.type == PropertyType.building && units.isNotEmpty) {
                        return matches(p) || units.any(matches);
                      }
                      if (p.occupiedUnits > 0) return false;
                      if (p.type == PropertyType.building &&
                          p.rentalMode == RentalMode.perUnit) {
                        return false;
                      }
                      return matches(p);
                    });

                    if (!hasAny) {
                      return Center(
                          child: Text('لا توجد عناصر متاحة',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)));
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
                        final expanded =
                            _expandedBuildingIds.contains(p.id) || q.isNotEmpty;
                        widgets.add(
                          Container(
                            margin: EdgeInsets.only(bottom: 6.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.10)),
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
                                Padding(
                                  padding:
                                      EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'اختر وحدة من هذه العمارة',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w700,
                                      ),
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
                                    trailing: _chip('وحدة',
                                        bg: const Color(0xFF334155)),
                                  ),
                              ],
                            ),
                          ),
                        );
                        continue;
                      }

                      if (p.occupiedUnits > 0) continue;
                      if (p.type == PropertyType.building &&
                          p.rentalMode == RentalMode.perUnit) {
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
                            title: Text(p.name,
                                style: GoogleFonts.cairo(color: Colors.white)),
                            subtitle: Text(p.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    GoogleFonts.cairo(color: Colors.white70)),
                            trailing: _chip(
                                p.type == PropertyType.building
                                    ? 'عمارة (كامل)'
                                    : 'مستقل',
                                bg: const Color(0xFF334155)),
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

/// ============================================================================
/// مسارات جاهزة للإدراج في MaterialApp.routes
/// - '/contracts'    : شاشة العقود (تقبل openPropertyId أو openContractId)
/// - '/contracts/new': شاشة إضافة عقد
///   (تقبل prefillPropertyId و/أو prefillTenantId أو renewFromContract)
/// ============================================================================
class ContractsRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/contracts': (_) => const ContractsScreen(),
        '/contracts/new': (_) => const AddContractScreen(),
      };
}

/// شاشة مختصرة لاستخدامها في المسار '/contracts/new'
class AddContractScreen extends StatelessWidget {
  const AddContractScreen({super.key});
  @override
  Widget build(BuildContext context) => const AddOrEditContractScreen();
}
