// lib/ui/contracts_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoices_screen.dart' show Invoice, kInvoicesBox;
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart';   // أو المسار الصحيح حسب مكان الملف
import '../utils/contract_utils.dart';
import '../widgets/darvoo_app_bar.dart';





import '../models/tenant.dart';
import '../models/property.dart';
import 'package:url_launcher/url_launcher.dart';


/// استيرادات للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;

/// عناصر الواجهة المشتركة (مطابقة لما استُخدم في شاشة المستأجرين)
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// ✅ مولِّد رقم فاتورة لحظة الإنشاء (يعتمد على أكبر رقم فعلي غير ملغى في نفس السنة)
// مولّد رقم فاتورة لعقود الإيجار، يعتمد فقط على أعلى رقم غير ملغى في نفس السنة
String _nextInvoiceSerialForContracts(Box<Invoice> invoices) {
  // استخدم SaTimeLite أو KsaTime بحسب ما هو متوفر عندك
  final int year = SaTimeLite.now().year;

  int maxSeq = 0;
  for (final inv in invoices.values) {
    if (inv.isCanceled == true) continue; // نتجاهل الفواتير الملغاة
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


bool _dailyAlreadyPaid(Contract c) {
  if (c.term != ContractTerm.daily) return false;
  try {
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));
    // أي فاتورة لنفس العقد، غير ملغاة، ومدفوعة بالكامل
    return box.values.any((inv) =>
      inv.contractId == c.id &&
      (inv.isCanceled != true) &&
      (inv.paidAmount >= (inv.amount - 0.000001))
    );
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
  String? _nz(String? s) => (s != null && s.trim().isNotEmpty) ? s.trim() : null;

  // 1) أولاً: من كائن Tenant نفسه (مثل زر الدفعات)
  try {
    final dyn = tenantObj as dynamic;
    final direct =
        _nz(dyn.fullName) ?? // كثير من الأزرار تستخدمه
        _nz(dyn.name) ??
        _nz(dyn.label);
    if (direct != null) return direct;

    final f = _nz(dyn.firstName) ?? _nz(dyn.givenName);
    final l = _nz(dyn.lastName)  ?? _nz(dyn.familyName) ?? _nz(dyn.surname);
    if (f != null && l != null) return '$f $l';
    if (f != null) return f;
  } catch (_) {
    // تجاهل أي أخطاء ديناميكية
  }

  // 2) ثانياً: من الخرائط (toJson/toMap أو سنابات محفوظة)
  String? _pick(Map<String, dynamic>? m, String k) {
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



  String? _firstNonEmpty(List<String?> xs) {
    for (final x in xs) {
      if (x != null && x.trim().isNotEmpty) return x.trim();
    }
    return null;
  }

  final tm = tenantMap ?? _asMap(tenantObj);
  final cm = contractMap ?? _asMap(contractObj);

  final fromMaps = _firstNonEmpty([
    _pick(tm, 'fullName'),
    _pick(tm, 'displayName'),
    _pick(tm, 'name'),
    _pick(tm, 'arabicName'),
    _pick(tm, 'enName'),
    _pick(tm, 'label'),
    _pick(tm, 'tenantName'),
    _pick(tm, 'title'),
    _pick(tm, 'payerName'),
    _pick(tm, 'customerName'),
    _pick(tm, 'clientName'),
    _pick(cm, 'tenantName'),
    _pick(cm, 'tenant_label'),
  ]);
  if (fromMaps != null) return fromMaps;

  final f = _firstNonEmpty([
    _pick(tm, 'firstName'),
    _pick(tm, 'first_name'),
    _pick(tm, 'givenName'),
    _pick(tm, 'given_name'),
  ]);
  final l = _firstNonEmpty([
    _pick(tm, 'lastName'),
    _pick(tm, 'last_name'),
    _pick(tm, 'familyName'),
    _pick(tm, 'family_name'),
    _pick(tm, 'surname'),
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
  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  String? _pick(Map<String, dynamic>? m, String k) {
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

  String _propertyLabel(Map<String, dynamic>? pm) {
    return _pick(pm, 'displayName') ??
           _pick(pm, 'name') ??
           _pick(pm, 'title') ??
           _pick(pm, 'label') ??
           _pick(pm, 'arabicName') ??
           _pick(pm, 'enName') ??
           '';
  }

  final name = _tenantNameUniversal(
    tenantObj: tenantObj,
    contractObj: c,
    tenantMap: tenantMap,
    contractMap: _asMap(c),
  );

  final prop = _propertyLabel(propertyMap);
  final propPart = prop.isNotEmpty ? ' لعقار $prop' : '';
  final dateStr = _fmtDate(due);

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
    return DateTime.now().add(Duration(milliseconds: _offsetMsCache));
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

class Contract extends HiveObject {
  String id;
String? serialNo; // رقم العقد التسلسلي مثل 2025-1


  // الربط
  String tenantId;
  String propertyId;

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

  // دورة السداد (تُخفى في "يومي")
  PaymentCycle paymentCycle;

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

  // تتبع
  DateTime createdAt;
  DateTime updatedAt;

  // الأرشفة (جديد)
  bool isArchived;

  Contract({
    String? id,
this.serialNo,

    required this.tenantId,
    required this.propertyId,
    required this.startDate,
    required this.endDate,
    required this.rentAmount,
    required this.totalAmount,
    this.currency = 'SAR',
    this.term = ContractTerm.monthly,
    this.paymentCycle = PaymentCycle.monthly,
    this.advancePaid,
    this.advanceMode = AdvanceMode.none,
    this.dailyCheckoutHour,
    this.notes,
    this.isTerminated = false,
    this.terminatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isArchived = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? SaTimeLite.now(),
        updatedAt = updatedAt ?? SaTimeLite.now();

// داخل class Contract
bool get isActiveNow {
  if (isTerminated) return false;

  final now = SaTimeLite.now();

  // 🟡 تخصيص "اليومي": نشط حتى 12:00 ظهرًا من يوم endDate
  if (term == ContractTerm.daily) {
    final start00 = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final endNoon = DateTime(endDate.year,   endDate.month,   endDate.day,   12, 0, 0);
    return !now.isBefore(start00) && now.isBefore(endNoon);
  }

  // باقي الأنواع كما هي (تاريخ فقط)
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final end   = DateTime(endDate.year,   endDate.month,   endDate.day);
  return !today.isBefore(start) && !today.isAfter(end);
}


bool get isExpiredByTime {
  // يعتبر منتهي من بداية اليوم الذي بعد تاريخ النهاية
  final n = SaTimeLite.now();
  final today = DateTime(n.year, n.month, n.day);
  final end   = DateTime(endDate.year, endDate.month, endDate.day);
  return !isTerminated && today.isAfter(end);
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
enum _StatusFilter { all, active, nearExpiry, due, expired, inactive, terminated, nearContract }



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
    final legacyCycle = PaymentCycle.values[legacyCycleIndex.clamp(0, PaymentCycle.values.length - 1)];
    final termIndex = (fields[14] as int?);
    final advModeIndex = (fields[15] as int?);
    final readTerm = termIndex == null
        ? ContractTerm.monthly
        : ContractTerm.values[termIndex.clamp(0, ContractTerm.values.length - 1)];
    final readAdvanceMode = advModeIndex == null
        ? AdvanceMode.none
        : AdvanceMode.values[advModeIndex.clamp(0, AdvanceMode.values.length - 1)];

    double estimatedTotal = (fields[16] as double?) ?? 0.0;
    if (estimatedTotal == 0.0) {
      final months = monthsBetween(start, end);
      int monthsPerCycle = _monthsPerCycle(legacyCycle);
      final installments = (months / monthsPerCycle).ceil().clamp(1, 1000);
      estimatedTotal = legacyPerCycle * installments;
    }

    return Contract(
  id: fields[0] as String?,
  tenantId: fields[1] as String,
  propertyId: fields[2] as String,
  startDate: start,
  endDate: end,
  rentAmount: legacyPerCycle <= 0 ? estimatedTotal : legacyPerCycle,
  currency: fields[6] as String? ?? 'SAR',
  term: readTerm,
  paymentCycle: legacyCycle,
  totalAmount: estimatedTotal > 0 ? estimatedTotal : (fields[5] as double? ?? 0.0),
  advancePaid: fields[8] as double?,
  advanceMode: readAdvanceMode,
  notes: fields[9] as String?,
  isTerminated: fields[10] as bool? ?? false,
  terminatedAt: fields[11] as DateTime?,
  createdAt: fields[12] as DateTime? ?? SaTimeLite.now(),
  updatedAt: fields[13] as DateTime? ?? SaTimeLite.now(),
  isArchived: fields[17] as bool? ?? false,
  dailyCheckoutHour: fields[18] as int?,
  serialNo: fields[19] as String?, // ← الجديد
);

  }

 @override
void write(BinaryWriter w, Contract c) {
  w
    ..writeByte(20) // ← كان 19، صار 20 لأننا أضفنا serialNo
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
    ..writeByte(19)           // ← فهرس الحقل الجديد
    ..write(c.serialNo);      // ← قيمة الحقل الجديد
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

bool _termEqualsCycle(ContractTerm t, PaymentCycle c) {
  switch (t) {
    case ContractTerm.monthly:     return c == PaymentCycle.monthly;
    case ContractTerm.quarterly:   return c == PaymentCycle.quarterly;
    case ContractTerm.semiAnnual:  return c == PaymentCycle.semiAnnual;
    case ContractTerm.annual:      return c == PaymentCycle.annual;
    case ContractTerm.daily:       return false; // اليومي لا يملك دورة سداد
  }
}


int _coveredMonthsByAdvance(Contract c) {
  if (c.advanceMode != AdvanceMode.coverMonths) return 0;
  if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
  final months = _monthsInTerm(c.term);
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
  return DateTime(y, m, safeDay, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => SaTimeLite.today();

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

  final first = _earliestUnpaidDueDate(c);  // أقدم غير مدفوع فعليًا
  if (first == null) return out;

  final todayOnly = _dateOnly(SaTimeLite.now());
  final endOnly   = _dateOnly(c.endDate);
  var cursor      = _dateOnly(first);

  while (cursor.isBefore(endOnly) && !cursor.isAfter(todayOnly)) {

    if (!_paidForDue(c, cursor)) out.add(cursor);
    cursor = _stepOneCycle(cursor, c.paymentCycle);
  }
  return out;
}


bool _hasStarted(Contract c) => !_dateOnly(SaTimeLite.now()).isBefore(_dateOnly(c.startDate));
bool _hasEnded(Contract c) {
  if (c.term == ContractTerm.daily) {
    final now     = SaTimeLite.now();
    final endNoon = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 12, 0, 0);
    // منتهي ابتداءً من 12:00 ظهرًا في يوم endDate
    return !now.isBefore(endNoon); // true عند 12:00 وما بعدها
  }
  return _dateOnly(SaTimeLite.now()).isAfter(_dateOnly(c.endDate));
}




/// نهاية شاملة للفترة (شهري/ربع/نصف/سنوي) — نفس رقم اليوم إذا وُجد، وإلا آخر يوم بالشهر.
DateTime _termEndInclusive(DateTime start, ContractTerm term) {
  final months = _monthsInTerm(term);
  if (months <= 0) return _dateOnly(start);
  final end = _addMonths(_dateOnly(start), months);
  // لا نطرح يومًا هنا؛ النهاية “شاملة” بنفس رقم اليوم/آخر يوم.
  return _dateOnly(end);
}

/// أول موعد استحقاق بعد احتساب الدفعة المقدّمة (إصلاح يغطي محاذاة دورة السداد)
DateTime? _firstDueAfterAdvance(Contract c) {
  if (c.term == ContractTerm.daily) return null;

  final start = _dateOnly(c.startDate);
  final end = _dateOnly(c.endDate);

  if (c.advanceMode == AdvanceMode.coverMonths) {
    final covered = _coveredMonthsByAdvance(c);
    final termMonths = _monthsInTerm(c.term);

    // المقدم يغطي كامل مدة العقد
    if (covered >= termMonths) return null;

    final mpc = _monthsPerCycle(c.paymentCycle); // أشهر كل قسط
    // اقفز لحد الدورة التالي بعد الأشهر المغطّاة: ceil(covered / mpc) * mpc
    final cyclesCovered = (covered / mpc).ceil();
    final first = _addMonths(start, cyclesCovered * mpc);

if (!first.isBefore(start) && !first.isAfter(end)) { // يشمل first == end
  return first;
}

    return null;
  }

  return start;
}

/// هل هناك فاتورة مدفوعة بالكامل لهذا الاستحقاق؟
bool _paidForDue(Contract c, DateTime due) {
  try {
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return false;
    final box   = Hive.box<Invoice>(boxName(kInvoicesBox));
    final dOnly = _dateOnly(due);

    for (final inv in box.values) {
      // تجاهل فاتورة "سداد مقدم عقد" فقط عند خصم المقدم من الإجمالي
      final note = (inv.note ?? '').toString();
      final isAdvanceInvoice =
          (c.advanceMode == AdvanceMode.deductFromTotal) &&
          note.contains('سداد مقدم عقد');

      if (inv.contractId == c.id &&
          !(inv.isCanceled == true) &&
          !isAdvanceInvoice &&
          (inv.paidAmount >= (inv.amount - 0.000001)) &&
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
  final stepM = _monthsPerCycle(c.paymentCycle);
  var cursor = _dateOnly(first);

while (!cursor.isAfter(end)) { // شامل لليوم الأخير end
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

  final end   = _dateOnly(c.endDate);
  final today = _dateOnly(SaTimeLite.now());
  final step  = _monthsPerCycle(c.paymentCycle);
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
    return !_dailyAlreadyPaid(c) && _dateOnly(c.startDate) == _dateOnly(SaTimeLite.now());
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
    due = _dateOnly(_addMonths(due, _monthsPerCycle(c.paymentCycle)));
  }
  return false;
}

bool isContractOverdueForHome(Contract c) => _isOverdueForFilter(c);


bool _isDueSoon(Contract c) {
  // "قاربت (دفعات)" يجب أن تنطبق على الأقساط المستقبلية فقط،
  // بغض النظر عن وجود متأخرات قديمة.
  if (!_hasStarted(c) || c.isTerminated) return false;
  if (c.term == ContractTerm.daily) return false; // استبعاد اليومي من "قاربت (دفعات)"

  // احصل على أول قسط غير مدفوع بتاريخ اليوم أو بعده
  final next = _sanitizeUpcoming(c, _nextDueDate(c));
  if (next == null) return false; // مافيه قسط قادم صالح

  final today = _dateOnly(SaTimeLite.now());
  final diff  = _dateOnly(next).difference(today).inDays;
  final window = _nearWindowDaysForContract(c);

  // "قاربت" = داخل النافذة 1..window (يستثني اليوم)
  return diff >= 1 && diff <= window;
}


bool _isNearContractEnd(Contract c) {
  if (!c.isActiveNow || c.isTerminated) return false;

  final today = _dateOnly(SaTimeLite.now());
  final end   = _dateOnly(c.endDate);
  final diff  = end.difference(today).inDays;

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
  final months = _monthsInTerm(c.term);
  final per = _monthsPerCycle(c.paymentCycle);
  return (months / per).ceil().clamp(1, 1000);
}

int _paidInstallments(Contract c) {
  try {
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return 0;
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));

    // نستبعد فاتورة "سداد مقدم عقد" فقط في حالة deductFromTotal
    bool _isAdvanceInvoice(Invoice i) {
      if (c.advanceMode != AdvanceMode.deductFromTotal) return false;
      final n = (i.note ?? '').toString();
      return n.contains('سداد مقدم عقد');
    }

    // نعدّ الفواتير غير الملغاة والمدفوعة بالكامل باستثناء فاتورة المقدم
    return box.values.where((i) =>
      i.contractId == c.id &&
      !i.isCanceled &&
      (i.paidAmount >= i.amount - 0.000001) &&
      !_isAdvanceInvoice(i)
    ).length;
  } catch (_) {
    return 0;
  }
}


bool _allInstallmentsPaid(Contract c) {
  // اليومي = قسط واحد
  final expected = _expectedInstallments(c);
  final paid = _paidInstallments(c);
  return paid >= expected;
}



double _perCycleAmount(Contract c) {
  if (c.term == ContractTerm.daily) return c.totalAmount;
  final months = _monthsInTerm(c.term);
  final perCycleCount = (months / _monthsPerCycle(c.paymentCycle)).ceil().clamp(1, 1000);
  if (c.advanceMode == AdvanceMode.deductFromTotal) {
    final net = (c.totalAmount - (c.advancePaid ?? 0)).clamp(0, double.infinity);
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

int _inclusiveDays(DateTime a, DateTime b) => _dateOnly(b).difference(_dateOnly(a)).inDays + 1;

int _daysUntil(DateTime d) => _dateOnly(d).difference(_dateOnly(SaTimeLite.now())).inDays;

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
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 10)),
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
      const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 18),
      SizedBox(width: 8.w),
      Expanded(
        child: Text(
          t,
          style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  ),
);


String _limitChars(String t, int max) => t.length <= max ? t : '${t.substring(0, max)}…';

/// الميلادي القياسي: yyyy-MM-dd
String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      child: Text(text, style: GoogleFonts.cairo(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700)),
    );

Widget _sectionTitle(String t) => Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(t, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.sp)),
    );

// ===== إعدادات "قاربت" (Top-level) =====
int _cfgMonthlyDays    = 7;
int _cfgQuarterlyDays  = 15;
int _cfgSemiAnnualDays = 30;
int _cfgAnnualDays     = 45;
int _cfgContractMonthlyDays    = 7;
int _cfgContractQuarterlyDays  = 15;
int _cfgContractSemiAnnualDays = 30;
int _cfgContractAnnualDays     = 45;


int _asInt(dynamic v, int f) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? f;
  return f;
}

// نافذة "قاربت" حسب **دورة السداد** (وليس مدة العقد)
int _nearWindowDaysForContract(Contract c) {
  switch (c.paymentCycle) {
    case PaymentCycle.monthly:    return _cfgMonthlyDays;    // 1..7
    case PaymentCycle.quarterly:  return _cfgQuarterlyDays;  // 1..15
    case PaymentCycle.semiAnnual: return _cfgSemiAnnualDays; // 1..30
    case PaymentCycle.annual:     return _cfgAnnualDays;     // 1..45
  }
}

int _nearEndWindowDays(Contract c) {
  switch (c.term) {
    case ContractTerm.daily:       return 0;
    case ContractTerm.monthly:     return _cfgContractMonthlyDays;
    case ContractTerm.quarterly:   return _cfgContractQuarterlyDays;
    case ContractTerm.semiAnnual:  return _cfgContractSemiAnnualDays;
    case ContractTerm.annual:      return _cfgContractAnnualDays;
  }
}


// (توافق للأماكن التي تنادي بالـ Term مباشرة)
int _nearWindowDaysForTerm(ContractTerm term) {
  switch (term) {
    case ContractTerm.daily:      return 0;
    case ContractTerm.monthly:    return _cfgMonthlyDays;
    case ContractTerm.quarterly:  return _cfgQuarterlyDays;
    case ContractTerm.semiAnnual: return _cfgSemiAnnualDays;
    case ContractTerm.annual:     return _cfgAnnualDays;
  }
}

// اسم قديم ظهر في الخطأ — نخليه Alias للتوافق
int _dueSoonDaysForTerm(ContractTerm term) => _nearWindowDaysForTerm(term);



enum ContractQuickFilter { all, overdue, nearDue }

_StatusFilter _statusFromQuick(ContractQuickFilter? f) {
  switch (f) {
    case ContractQuickFilter.overdue:  return _StatusFilter.expired;    // متأخرة
    case ContractQuickFilter.nearDue:  return _StatusFilter.nearExpiry; // قاربت
    case ContractQuickFilter.all:
    case null:                         return _StatusFilter.all;
  }
}


/// =================================================================================
/// شاشة قائمة العقود
/// =================================================================================
class ContractsScreen extends StatefulWidget {
  final ContractQuickFilter? initialFilter; // جديد
  const ContractsScreen({super.key, this.initialFilter});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

// ======== واتساب: رقم + رسالة + فتح المحادثة ========

// يستخرج رقم الهاتف من Tenant بأمان حتى لو اسم الحقل مختلف (phone / phoneNumber / mobile)
String? _tenantRawPhone(Tenant? t) {
  if (t == null) return null;
  try { final v = (t as dynamic).phone;        if (v is String && v.trim().isNotEmpty) return v; } catch (_) {}
  try { final v = (t as dynamic).phoneNumber;  if (v is String && v.trim().isNotEmpty) return v; } catch (_) {}
  try { final v = (t as dynamic).mobile;       if (v is String && v.trim().isNotEmpty) return v; } catch (_) {}
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
  final name = (tenant?.fullName?.trim().isNotEmpty ?? false)
      ? tenant!.fullName!.trim()
      : 'العميل';

  final curr = (c.currency ?? '').trim();
  final currLabel = curr.isEmpty
      ? 'ريال'
      : (curr.toLowerCase() == 'sar' ? 'ريال' : curr);

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
Future<void> _openWhatsAppToTenant(BuildContext context, Tenant? t, String message) async {
  final phone = _waNumberE164(t);
  if (phone == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('لا يوجد رقم واتساب صالح للمستأجر.', style: GoogleFonts.cairo())),
    );
    return;
  }
  final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذّر فتح واتساب.', style: GoogleFonts.cairo())),
    );
  }
}





class _ContractsScreenState extends State<ContractsScreen> {
  Box<Contract> get _contracts => Hive.box<Contract>(boxName(kContractsBox));
  Box<Tenant>   get _tenants   => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties=> Hive.box<Property>(boxName(kPropertiesBox));

String _q = '';
String? _filterTenantId;

String get _contractsBoxName => HiveService.contractsBoxName();
Box<Contract> get _box => Hive.box<Contract>(_contractsBoxName);


// فلاتر
_ArchiveFilter _fArchive = _ArchiveFilter.notArchived; // الافتراضي: غير مؤرشفة
_StatusFilter _fStatus = _StatusFilter.all;
_TermFilter _fTerm = _TermFilter.all;




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
    (_filterTenantId != null);

String _currentFilterLabel() {
  final parts = <String>[];
  // الأرشفة
  parts.add(_fArchive == _ArchiveFilter.archived ? 'المؤرشفة' : 'الكل');

// الحالة
switch (_fStatus) {
  case _StatusFilter.active:        parts.add('نشطة'); break;
  case _StatusFilter.nearContract:  parts.add('عقد قارب'); break;   // ← أضِف هذا
  case _StatusFilter.nearExpiry:    parts.add('قاربت'); break;       // (قاربت الدفعات)
  case _StatusFilter.due:           parts.add('مستحقة'); break;
  case _StatusFilter.expired:       parts.add('متأخرة'); break;
  case _StatusFilter.inactive:      parts.add('غير نشطة'); break;
  case _StatusFilter.terminated:    parts.add('منتهية'); break;
  case _StatusFilter.all: break;
}


  // فترة العقد
  switch (_fTerm) {
    case _TermFilter.daily: parts.add('يومي'); break;
    case _TermFilter.monthly: parts.add('شهري'); break;
    case _TermFilter.quarterly: parts.add('ربع سنوي'); break;
    case _TermFilter.semiAnnual: parts.add('نصف سنوي'); break;
    case _TermFilter.annual: parts.add('سنوي'); break;
    case _TermFilter.all: break;
  }
  // تصفية قادمة من شاشة المستأجر
  if (_filterTenantId != null) parts.add('مستأجر محدد');
  return parts.join(' • ');
}

@override
void initState() {
  super.initState();
(() async {
await HiveService.ensureReportsBoxesOpen(); // يفتح صناديق هذا المستخدم + يحلّ aliases
if (mounted) setState(() {});               // لو تحب تحدّث الواجهة بعد الفتح
})();

  // ✅ طبّق الفلتر القادم من الرئيسية فورًا (بدون setState) لمنع الوميض
  _fStatus = _statusFromQuick(widget.initialFilter);

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final h = _bottomNavKey.currentContext?.size?.height;
    if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
      setState(() => _bottomBarHeight = h);
    }

    await _autoReleaseExpiredOccupancies();
    _handleInitialRouteIntent();   // يفتح عقد معيّن إن طُلب عبر arguments
    await _loadNotifPrefs();       // تحميل إعدادات نافذة "قاربت"
    // ⛔️ لا تستدعِ هنا أي setState يغيّر _fStatus مرة ثانية
  });
}




void _openFilterSheet() {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0B1220),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      var tArchive = _fArchive;
      var tStatus  = _fStatus;
      var tTerm    = _fTerm;

      bool arch = tArchive == _ArchiveFilter.archived; // مثل شاشة المستأجرين

      return StatefulBuilder(
        builder: (context, setM) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16.w, 16.h, 16.w, 16.h + MediaQuery.of(context).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Text('تصفية',
                  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800))),
                SizedBox(height: 12.h),

 // الحالة
DropdownButtonFormField<_StatusFilter>(
  value: tStatus,
  decoration: _dropdownDeco('الحالة'),
  dropdownColor: const Color(0xFF0B1220),
  iconEnabledColor: Colors.white70,
  items: const [
    DropdownMenuItem(value: _StatusFilter.all,         child: Text('الكل')),
    DropdownMenuItem(value: _StatusFilter.active,      child: Text('عقود نشطة')),
   DropdownMenuItem(value: _StatusFilter.inactive,    child: Text('عقود غير نشطة')),
    DropdownMenuItem(value: _StatusFilter.nearContract,child: Text('عقود قاربت')), // ← أضِف هذا
  DropdownMenuItem(value: _StatusFilter.terminated,  child: Text('عقود منتهية')),
    DropdownMenuItem(value: _StatusFilter.nearExpiry,  child: Text('دفعات قاربت')),    // (دفعات)
    DropdownMenuItem(value: _StatusFilter.due,         child: Text('دفعات مستحقة')),
    DropdownMenuItem(value: _StatusFilter.expired,     child: Text('دفعات متأخرة')),
  ],


                  onChanged: (v) => setM(() => tStatus = v ?? _StatusFilter.all),
                  style: GoogleFonts.cairo(color: Colors.white),
                ),
                SizedBox(height: 10.h),

                // فترة العقد
                DropdownButtonFormField<_TermFilter>(
                  value: tTerm,
                  decoration: _dropdownDeco('فترة العقد'),
                  dropdownColor: const Color(0xFF0B1220),
                  iconEnabledColor: Colors.white70,
                  items: const [
                    DropdownMenuItem(value: _TermFilter.all, child: Text('الكل')),
                    DropdownMenuItem(value: _TermFilter.daily, child: Text('يومي')),
                    DropdownMenuItem(value: _TermFilter.monthly, child: Text('شهري')),
                    DropdownMenuItem(value: _TermFilter.quarterly, child: Text('ربع سنوي')),
                    DropdownMenuItem(value: _TermFilter.semiAnnual, child: Text('نصف سنوي')),
                    DropdownMenuItem(value: _TermFilter.annual, child: Text('سنوي')),
                  ],
                  onChanged: (v) => setM(() => tTerm = v ?? _TermFilter.all),
                  style: GoogleFonts.cairo(color: Colors.white),
                ),

                // — الأرشفة مثل شاشة المستأجرين (خياران جنب بعض: الكل/الأرشفة)
                SizedBox(height: 14.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('الأرشفة',
                    style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
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
                        onPressed: () {
                          setState(() {
                            _fStatus  = tStatus;
                            _fTerm    = tTerm;
                            _fArchive = arch ? _ArchiveFilter.archived : _ArchiveFilter.notArchived;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
                        child: Text('تطبيق', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _fStatus  = _StatusFilter.all;
                            _fTerm    = _TermFilter.all;
                            _fArchive = _ArchiveFilter.notArchived;
                          });
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                        child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
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

    setState(() {
      _cfgMonthlyDays    = _asInt(m['notif_monthly_days'],     7).clamp(1, 7);
      _cfgQuarterlyDays  = _asInt(m['notif_quarterly_days'],  15).clamp(1, 15);
      _cfgSemiAnnualDays = _asInt(m['notif_semiannual_days'], 30).clamp(1, 30);
      _cfgAnnualDays     = _asInt(m['notif_annual_days'],     45).clamp(1, 45);
          _cfgContractMonthlyDays    = _asInt(m['notif_contract_monthly_days'],    _cfgMonthlyDays).clamp(1, 7);
_cfgContractQuarterlyDays  = _asInt(m['notif_contract_quarterly_days'],  _cfgQuarterlyDays).clamp(1, 15);
_cfgContractSemiAnnualDays = _asInt(m['notif_contract_semiannual_days'], _cfgSemiAnnualDays).clamp(1, 30);
_cfgContractAnnualDays     = _asInt(m['notif_contract_annual_days'],     _cfgAnnualDays).clamp(1, 45);

    });

    if (Hive.isBoxOpen('sessionBox')) {
      final box = Hive.box('sessionBox');
      await box.put('notif_monthly_days',    _cfgMonthlyDays);
      await box.put('notif_quarterly_days',  _cfgQuarterlyDays);
      await box.put('notif_semiannual_days', _cfgSemiAnnualDays);
      await box.put('notif_annual_days',     _cfgAnnualDays);
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

  if (args is String) {
    openPropertyId = args;
  } else if (args is Map) {
    final m = args.cast<String, dynamic>();
    openPropertyId   = m['openPropertyId']   as String?;
    openContractId   = m['openContractId']   as String?;
    filterTenantId   = m['filterTenantId']   as String?;
  }

  // حفظ معيار التصفية إن وصل من شاشة المستأجر
  if (filterTenantId != null) {
    setState(() => _filterTenantId = filterTenantId);
  }

  // منطق فتح عقد معيّن أو حسب العقار (كما هو موجود سابقاً)
  Contract? target;
  if (openContractId != null) {
    target = firstWhereOrNull(_contracts.values, (c) => c.id == openContractId);
  } else if (openPropertyId != null) {
    final byProp = _contracts.values.where((c) => c.propertyId == openPropertyId && !c.isArchived).toList();
    byProp.sort((a, b) => b.startDate.compareTo(a.startDate));
    target = firstWhereOrNull(byProp, (c) => c.isActiveNow) ?? (byProp.isNotEmpty ? byProp.first : null);
  }

  if (target != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailsScreen(contract: target!)));
    });
  }
}


  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        // أنت هنا
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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

          title: Text('العقود', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20.sp)),
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
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)]),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

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
        ),
      ),
    ),

    // ⬅️ وسم ملخص الفلاتر — بعد البحث مباشرة
    if (_hasActiveFilters)
      Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_alt_rounded, size: 16, color: Colors.white70),
                SizedBox(width: 6.w),
                Text(
                  _currentFilterLabel(),
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

    // قائمة العقود
// قائمة العقود
Expanded(
  child: AnimatedBuilder(
    animation: Listenable.merge([
      Hive.box<Contract>(_contractsBoxName).listenable(),      // اسمع تغييرات العقود
      Hive.box<Invoice>(boxName(kInvoicesBox)).listenable(),   // ✅ اسمع تغييرات الفواتير
    ]),
    builder: (_, __) {
      final box = Hive.box<Contract>(_contractsBoxName);       // استخدم نفس الصندوق كما كنت
      // ضع هنا نفس المحتوى الذي كان داخل builder سابقًا (فلترة/بحث/ترتيب/ ListView ...)
      // فقط استبدل "box" الممرَّر سابقًا بالمتغير المحلي أعلاه.
      // مثال: var items = box.values.toList();
      // اجلب العقود
      var items = box.values.toList();

      // إزالة التكرار بالأمان
      final byId = <String, Contract>{};
      for (final c in items) byId[c.id] = c;
      items = byId.values.toList();

      // فلاتر الأرشفة
      if (_fArchive == _ArchiveFilter.notArchived) {
        items = items.where((c) => !c.isArchived).toList();
      } else if (_fArchive == _ArchiveFilter.archived) {
        items = items.where((c) => c.isArchived).toList();
      }

      // تصفية من شاشة المستأجر
      if (_filterTenantId != null) {
        items = items.where((c) => c.tenantId == _filterTenantId).toList();
      }

// فلتر الحالة
if (_fStatus != _StatusFilter.all) {
  items = items.where((c) {
    switch (_fStatus) {
case _StatusFilter.active:
  return c.isActiveNow; // يظهر أي عقد نشط بغض النظر عن الدفعات أو قرب الانتهاء


      case _StatusFilter.nearContract:
        return _isNearContractEnd(c);  // الجديد: قرب انتهاء العقد

      case _StatusFilter.nearExpiry:
        return _isDueSoon(c);          // قاربت "الدفعات" كما هي

      case _StatusFilter.due:
        return _isDueTodayForFilter(c); 

      case _StatusFilter.expired:
        return _isOverdueForFilter(c); 

      case _StatusFilter.inactive:
        return !c.isActiveNow
            && !c.isTerminated
            && !_isOverdue(c)
            && !_isDueToday(c)
            && !_isDueSoon(c)
            && !_isNearContractEnd(c);

      case _StatusFilter.terminated:
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
          case _TermFilter.daily:      target = ContractTerm.daily; break;
          case _TermFilter.monthly:    target = ContractTerm.monthly; break;
          case _TermFilter.quarterly:  target = ContractTerm.quarterly; break;
          case _TermFilter.semiAnnual: target = ContractTerm.semiAnnual; break;
          case _TermFilter.annual:     target = ContractTerm.annual; break;
          case _TermFilter.all:        target = ContractTerm.monthly; break; // لن تُستخدم
        }
        items = items.where((c) => c.term == target).toList();
      }

      // البحث (اسم مستأجر/عقار/مبلغ/رقم تسلسلي)
      if (_q.isNotEmpty) {
        final q = _q.toLowerCase();
        items = items.where((c) {
          final Tenant? t = firstWhereOrNull(_tenants.values, (x) => x.id == c.tenantId);
          final Property? p = firstWhereOrNull(_properties.values, (x) => x.id == c.propertyId);
          final tn = (t?.fullName ?? '').toLowerCase();
          final pn = (p?.name ?? '').toLowerCase();
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
                  final padded = '$left-${rightNum.toString().padLeft(4, '0')}';
                  serialMatch = (sn == padded);
                }
              }
            }
          }
          return tn.contains(q) || pn.contains(q) || total.contains(q) || serialMatch;
        }).toList();
      }

      // ترتيب
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // فارغة؟
      if (items.isEmpty) {
        return Center(
          child: Text(
            (_fArchive == _ArchiveFilter.archived) ? 'لا توجد عقود مؤرشفة' : 'لا توجد عقود',
            style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
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
final number = (c.serialNo?.isNotEmpty == true) ? c.serialNo! : c.id; // ← أضِفه هنا

          final Tenant? t = firstWhereOrNull(_tenants.values, (x) => x.id == c.tenantId);
          final Property? p = firstWhereOrNull(_properties.values, (x) => x.id == c.propertyId);

 

// حالة العقد نفسها فقط (لا علاقة لها بالدفعات)
String statusText;
Color statusColor;
final started = _hasStarted(c);
final ended   = _hasEnded(c) || c.isExpiredByTime;

if (c.isTerminated || ended) {
  statusText = 'منتهية';
  statusColor = const Color(0xFF7F1D1D);
} else if (!started) {
  statusText = 'غير نشطة (قبل البدء)';
  statusColor = const Color(0xFF334155);
} else if (_isNearContractEnd(c)) { // ← جديد: قرب انتهاء العقد
  statusText = 'عقد قارب';
  statusColor = const Color(0xFFF59E0B);
} else {
  statusText = 'نشطة';
  statusColor = const Color(0xFF065F46);
}


// --- حالة الدفعات (تلخيص متعدد يظهر أكثر من حالة معًا)
final todayOnly  = _dateOnly(SaTimeLite.now());

// لغير اليومي: نبني كومة غير المسدّد حتى اليوم
final unpaidStack = (c.term == ContractTerm.daily) ? <DateTime>[] : _buildUnpaidStack(c);

// متأخرة
final startOnly = _dateOnly(c.startDate);
final bool hasOverdue = (c.term == ContractTerm.daily)
    ? (!_dailyAlreadyPaid(c) && startOnly.isBefore(todayOnly)) // اليومي: غير مسدّد وبداية قبل اليوم
    : unpaidStack.any((d) => _dateOnly(d).isBefore(todayOnly));

// مستحقة (اليوم)
final bool hasDueToday = (c.term == ContractTerm.daily)
    ? (!_dailyAlreadyPaid(c) && startOnly == todayOnly)       // اليومي: غير مسدّد واليوم هو يوم البداية
    : unpaidStack.any((d) => _dateOnly(d) == todayOnly);


// قاربت (القسط التالي بعد الكومة ضمن النافذة)
DateTime? nextAfterStack;
if (c.term != ContractTerm.daily && !_allInstallmentsPaid(c)) {
  nextAfterStack = unpaidStack.isNotEmpty
      ? _stepOneCycle(unpaidStack.last, c.paymentCycle)
      : _nextDueDate(c);
}
nextAfterStack = _sanitizeUpcoming(c, nextAfterStack);

final bool hasNearing = (c.term == ContractTerm.daily)
    ? _isDueSoon(c)                                          // اليومي: باقي يوم واحد
    : (() {
        if (nextAfterStack == null) return false;
        final d = _dateOnly(nextAfterStack!);
        final diff = d.difference(todayOnly).inDays;
        final window = _nearWindowDaysForContract(c);
        return diff >= 1 && diff <= window;
      })();


          return InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ContractDetailsScreen(contract: c)),
              );
            },
                      onLongPress: () async {
    // 🚫 منع عميل المكتب من الأرشفة / فكّ الأرشفة من قائمة العقود
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    if (!c.isArchived && !c.isTerminated) {
      final reason = c.isActiveNow ? 'نشط حاليًا' : 'غير مُنتهي';
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actionsAlignment: MainAxisAlignment.center,
          title: Text(
            'لا يمكن الأرشفة',
            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'لا يمكن أرشفة العقد لأنه $reason. يجب إنهاء العقد أولًا.',
            style: GoogleFonts.cairo(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'حسنًا',
                style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // الحالة الجديدة للأرشفة (true = مؤرشف، false = غير مؤرشف)
    final newArchived = !c.isArchived;
    c.isArchived = newArchived;
    await c.save();

    // 🔁 مزامنة حالة الأرشفة مع فواتير هذا العقد (يبقى كما هو عندك)
    try {
      if (Hive.isBoxOpen(boxName(kInvoicesBox))) {
        final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
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
                ? 'تمت أرشفة العقد وفواتيره'
                : 'تم إلغاء الأرشفة عن العقد وفواتيره',
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
                    width: 52.w, height: 52.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.r),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                        begin: Alignment.topRight, end: Alignment.bottomLeft,
                      ),
                    ),
                    child: const Icon(Icons.description_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t?.fullName ?? '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15.sp,
        ),
      ),
      SizedBox(height: 2.h),
      Text(
        p?.name ?? '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
                          spacing: 6.w, runSpacing: 6.h,
                          children: [
                            _chip('العقد: ${c.term.label}', bg: const Color(0xFF1F2937)),
                            if (c.term != ContractTerm.daily)
                              _chip('الدفع: ${c.paymentCycle.label}', bg: const Color(0xFF1F2937)),
                            _chip('من ${_fmtDateDynamic(c.startDate)} إلى ${_fmtDateDynamic(c.endDate)}', bg: const Color(0xFF1F2937)),
if (started && hasOverdue)  _chip('متأخرة',  bg: const Color(0xFF7F1D1D)),
if (started && hasDueToday) _chip('مستحقة',  bg: const Color(0xFF0EA5E9)),
if (started && !ended && !c.isTerminated && hasNearing && c.term != ContractTerm.daily)
  _chip('قاربت', bg: const Color(0xFFB45309)),




                                                

                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Colors.white70),
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
          backgroundColor: const Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.note_add_rounded),
          label: Text('إضافة عقد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            // 🚫 منع عميل المكتب من إضافة عقد
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final created = await Navigator.of(context).push<Contract?>(
              MaterialPageRoute(builder: (_) => AddOrEditContractScreen()),
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
  final Box<Contract> contBox  = Hive.box<Contract>(boxName(kContractsBox));
  final Box<Tenant>   tenantsBox = Hive.box<Tenant>(boxName(kTenantsBox));

  for (final c in contBox.values) {
    // إذا العقد مُنهى مسبقًا تجاهله
    if (c.isTerminated) continue;

    // إنتهت مدة العقد؟ (بداية اليوم التالي)
    final ended = today.isAfter(_dateOnly(c.endDate));
    if (!ended) continue;

    // 1) فك إشغال العقار إذا لم يعد هناك عقد نشط عليه
    final prop = firstWhereOrNull(propsBox.values, (p) => p.id == c.propertyId);
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
    c.isTerminated = true;
    c.terminatedAt = now;
    c.updatedAt = now;
    await c.save();

    // 3) إنقاص عدّاد العقود النشطة للمستأجر (إن كان > 0)
    final t = firstWhereOrNull(tenantsBox.values, (x) => x.id == c.tenantId);
    if (t != null && t.activeContractsCount > 0) {
      t.activeContractsCount -= 1;
      t.updatedAt = now;
      await t.save();
    }
  }
}


  Future<void> _onContractCreated(Contract c) async {
    final prop = firstWhereOrNull(_properties.values, (p) => p.id == c.propertyId);
    if (prop != null) await _occupyProperty(prop);

    final t = firstWhereOrNull(_tenants.values, (x) => x.id == c.tenantId);
    if (t != null && c.isActiveNow) {
      t.activeContractsCount += 1;
      t.updatedAt = SaTimeLite.now();
      await t.save();
    }
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
    final all = Hive.box<Property>(boxName(kPropertiesBox)).values.where((e) => e.parentBuildingId == buildingId);
    final count = all.where((e) => e.occupiedUnits > 0).length;
    final building = firstWhereOrNull(Hive.box<Property>(boxName(kPropertiesBox)).values, (e) => e.id == buildingId);
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
  Box<Tenant>   get _tenants   => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties=> Hive.box<Property>(boxName(kPropertiesBox));

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

DateTime? _overrideNextDue; // نعتبر القسط التالي بعد السداد مباشرة (عرض محلي)

DateTime? _effectiveNextDue(Contract c) => _overrideNextDue ?? _nextDueDate(c);

// عرض اسم العملة للمستخدم (مثلاً: SAR => ريال)
String _displayCurrency(String c) {
  try {
    if (c.toUpperCase() == 'SAR') return 'ريال';
  } catch (_) {}
  return c;
}

Future<void> _autoTerminateIfEnded(Contract c) async {
  // إذا انتهى وقت العقد (اليوم > تاريخ النهاية) ولم يُنهَ بعد ⇒ أنهِه فعليًا
  if (c.isTerminated) return;
  final today = _dateOnly(SaTimeLite.now());
  if (!today.isAfter(_dateOnly(c.endDate))) return;

  final propsBox   = Hive.box<Property>(boxName(kPropertiesBox));
  final contBox    = Hive.box<Contract>(boxName(kContractsBox));
  final tenantsBox = Hive.box<Tenant>(boxName(kTenantsBox));

  // حرر إشغال العقار فقط إن لم يعد هناك عقد نشط آخر على نفس العقار
  final prop = firstWhereOrNull(propsBox.values, (p) => p.id == c.propertyId);
  if (prop != null) {
    final hasActive = contBox.values.any((cc) =>
      !cc.isTerminated && cc.propertyId == c.propertyId && cc.isActiveNow);
    if (!hasActive) {
      if (prop.parentBuildingId != null) {
        if (prop.occupiedUnits != 0) {
          prop.occupiedUnits = 0;
          await prop.save();
          // أعِد حساب إشغال البناية
          final siblings = propsBox.values.where((e) => e.parentBuildingId == prop.parentBuildingId);
          final count = siblings.where((e) => e.occupiedUnits > 0).length;
          final building = firstWhereOrNull(propsBox.values, (e) => e.id == prop.parentBuildingId);
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
  c.terminatedAt = now;
  c.updatedAt = now;
  await c.save();

  final t = firstWhereOrNull(tenantsBox.values, (x) => x.id == c.tenantId);
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
    if (mounted) setState(() {});
  })();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ✅ إنهاء تلقائي فعلي إذا التاريخ تعدّى نهاية العقد
    _autoTerminateIfEnded(widget.contract);

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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.popUntil(context, (r) => r.isFirst);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
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



    final Tenant? t = firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
    final Property? p = firstWhereOrNull(_properties.values, (x) => x.id == contract.propertyId);

    Property? building;
    if (p?.parentBuildingId != null) {
      building = firstWhereOrNull(_properties.values, (x) => x.id == p!.parentBuildingId);
    }
    final secondLineName = building?.name ?? p?.name ?? '—';
    final secondLineId = building?.id ?? p?.id;

final bool dueToday = _isDueToday(contract);
final bool overdue  = _isOverdue(contract);
final bool dueSoon  = _isDueSoon(contract);



// لا نستخدم قاربت/مستحقة/متأخرة لحالة العقد نفسه
String statusText;
Color statusColor;
final started = _hasStarted(contract);
final ended   = _hasEnded(contract) || contract.isExpiredByTime;

if (contract.isTerminated || ended) {
  statusText = 'منتهية';
  statusColor = const Color(0xFF7F1D1D);
} else if (!started) {
  statusText = 'غير نشطة (قبل البدء)';
  statusColor = const Color(0xFF334155);
} else if (_isNearContractEnd(contract)) { // ← جديد
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
if (contract.term != ContractTerm.daily 
    && !_allInstallmentsPaid(contract)
    && !contract.isTerminated 
    && !contract.isExpiredByTime 
    && !_hasEnded(contract)) {
  if (unpaidStack.isNotEmpty) {
    upcomingAfterStack = _stepOneCycle(unpaidStack.last, contract.paymentCycle);
  } else {
    // لا توجد كومة (كل ما قبل اليوم مدفوع) — خذ أول غير مدفوع اليوم أو بعده
    upcomingAfterStack = _nextDueDate(contract);
  }
}
upcomingAfterStack = _sanitizeUpcoming(contract, upcomingAfterStack);
if (contract.isTerminated || contract.isExpiredByTime || _hasEnded(contract)) {
  upcomingAfterStack = null;
}

// عنوان القسم
final sectionHeaderTitle = unpaidStack.isNotEmpty
    ? 'دفعات غير مسددة'
    : 'الدفعة القادمة';




// الحالة + اللون (مطابقة لأعلى الشاشة والقائمة)
String? nextLabel;
Color? nextColor;



    final perCycleAmount = _perCycleAmount(contract);

    // لليومي: حساب القيمة اليومية من الإجمالي
    double? dailyRate;
    if (contract.term == ContractTerm.daily) {
      final d = _inclusiveDays(contract.startDate, contract.endDate);
      if (d > 0) dailyRate = contract.totalAmount / d;
    }

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

          title: Text('تفاصيل العقد', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
IconButton(
  tooltip: contract.isArchived ? 'فك الأرشفة' : 'أرشفة',
  onPressed: () async {
    // 🚫 منع عميل المكتب من الأرشفة / فكّ الأرشفة
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    // 🔒 تأكد أن العقد مرتبط بصندوق Hive

    // 🔒 تأكد أن العقد مرتبط بصندوق Hive
    if (!contract.isInBox) {
      final box = Hive.box<Contract>(boxName(kContractsBox));
      final live = firstWhereOrNull(box.values, (c) => c.id == contract.id);
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

    // منع الأرشفة إن لم يُنهَ العقد بعد
    if (!contract.isArchived && !contract.isTerminated) {
      final reason = contract.isActiveNow ? 'نشط حاليًا' : 'غير مُنتهي';
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actionsAlignment: MainAxisAlignment.center,
          title: Text(
            'لا يمكن الأرشفة',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'لا يمكن أرشفة العقد لأنه $reason. يجب إنهاء العقد أولًا.',
            style: GoogleFonts.cairo(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'حسنًا',
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
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
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            actionsAlignment: MainAxisAlignment.center,
            title: Text(
              'لا يمكن الأرشفة',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              'لا يمكن أرشفة هذا العقد لوجود دفعات مستحقة أو متأخرة لم تُسدَّد بعد.\n'
              'يجب سداد جميع الدفعات قبل أرشفة العقد.',
              style: GoogleFonts.cairo(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'حسنًا',
                  style: GoogleFonts.cairo(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }
    }


    // ✅ مسموح: فك الأرشفة أو أرشفة عقد مُنتهي
    final newArchived = !contract.isArchived;
    contract.isArchived = newArchived;
    await contract.save();

    // 🔁 مزامنة حالة الأرشفة مع فواتير هذا العقد
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
                ? 'تمت أرشفة العقد وفواتيره'
                : 'تم إلغاء الأرشفة عن العقد وفواتيره',
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



            IconButton(
              tooltip: 'حذف',
              onPressed: () async {
                // 🚫 منع عميل المكتب من حذف العقد
                if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                await _delete(context, contract);
              },
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
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
          colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
        ),
      ),
    ),
    Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
    Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

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
              // ===== بطاقة الرأس =====
              _DarkCard(
                padding: EdgeInsets.all(14.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56.w,
                          height: 56.w,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.r),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: const Icon(Icons.description_rounded, color: Colors.white),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _openTenant(context, t),
                                      child: Text(
                                        t?.fullName ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.cairo(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16.sp,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (contract.serialNo != null) ...[
                                    SizedBox(width: 8.w),
                                    _chip('${contract.serialNo}', bg: const Color(0xFF334155)),
                                  ],
                                ],
                              ),
                              SizedBox(height: 4.h),
                              InkWell(
                                onTap: () => _openProperty(context, secondLineId),
                                child: Text(
                                  secondLineName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5.sp,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                children: [
                                  _chip(statusText, bg: statusColor),
                                  _chip('العقد: ${contract.term.label}', bg: const Color(0xFF1F2937)),
                                  _chip('من ${_fmtDateDynamic(contract.startDate)} إلى ${_fmtDateDynamic(contract.endDate)}', bg: const Color(0xFF1F2937)),
                                  if (contract.term != ContractTerm.daily)
                                    _chip('الدفع: ${contract.paymentCycle.label}', bg: const Color(0xFF1F2937)),
                                  if (contract.term == ContractTerm.daily && dailyRate != null)
                                    _chip('قيمة الإيجار اليومي: ${_fmtMoneyTrunc(dailyRate!)} ${_displayCurrency(contract.currency)}', bg: const Color(0xFF1F2937)),
                                  _chip('إجمالي  القيمة: ${_fmtMoneyTrunc(contract.totalAmount)} ${_displayCurrency(contract.currency)}', bg: const Color(0xFF1F2937)),
if (contract.term != ContractTerm.daily &&
    (contract.advanceMode == AdvanceMode.none || (contract.advancePaid ?? 0) <= 0))
  _chip(
    'إجمالي عدد الدفعات: ${((_monthsInTerm(contract.term) / _monthsPerCycle(contract.paymentCycle)).ceil()).clamp(1, 1000)}',
    bg: const Color(0xFF1F2937),
  ),

                                 if (contract.term != ContractTerm.daily)
  _chip(
    'قيمة الدفعة: ${_fmtMoneyTrunc(contract.rentAmount)} ${_displayCurrency(contract.currency)}',
    bg: const Color(0xFF1F2937),
  ),

if (contract.advanceMode != AdvanceMode.none && (contract.advancePaid ?? 0) > 0)
  _chip(
    'مقدم: ${_fmtMoneyTrunc(contract.advancePaid ?? 0)} ${_displayCurrency(contract.currency)}',
    bg: const Color(0xFF1F2937),
  ),

if (contract.createdAt != null)
  _chip(
    'تاريخ الإنشاء: ${_fmtDateDynamic(contract.createdAt!)}',
    bg: const Color(0xFF1D4ED8), // 🔵 نفس لون تاريخ الإنشاء في المستأجرين
  ),




                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
// ▼▼ زر واتساب أسفل-يسار البطاقة (يظهر عند قرب/انتهاء العقد)
Padding(
  padding: EdgeInsets.only(top: 10.h),
  child: Builder(builder: (context) {
    final bool nearEnd = _isNearContractEnd(contract);
    final bool endedOrTerminated = _hasEnded(contract) || contract.isTerminated;

    if (!nearEnd && !endedOrTerminated) {
      debugPrint('[WA-BTN] hidden: not nearEnd and not ended');
      return const SizedBox.shrink();
    }

    final t = firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
    final p = firstWhereOrNull(_properties.values, (x) => x.id == contract.propertyId);

    final bool phoneOk = _waNumberE164(t) != null;
    if (!phoneOk) {
      debugPrint('[WA-BTN] disabled: tenant has no valid WhatsApp number');
      // ملاحظة: لا نخفي الزر.. فقط سنعطّله
    }

// حوّل الكائنات إلى خرائط إن أمكن
// ——— بناء الرسالة (باستخدام الدوال المساعدة المعرفة خارج الـBuilder) ———
final msg = _waMessageContract(
  c: contract,
  due: _dateOnly(contract.endDate),
  kind: endedOrTerminated ? 'overdue' : 'near',
  tenantObj: t,
  tenantMap: _asMap(t),
  propertyMap: _asMap(p),
);





    // تثبيت أسفل-يسار داخل البطاقة حتى مع RTL
    return Align(
      alignment: Alignment.bottomLeft,

      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          AbsorbPointer(
            absorbing: !phoneOk, // تعطيل الضغط إذا لا يوجد رقم
            child: Opacity(
              opacity: phoneOk ? 1.0 : 0.45,
              child: _miniAction(
                icon: Icons.chat_bubble_rounded,
                label: 'واتس اب',
                bg: const Color(0xFF25D366),
                onTap: () {
                  if (!phoneOk) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('لا يوجد رقم واتساب صالح لهذا المستأجر.')),
                    );
                    return;
                  }
                  _openWhatsAppToTenant(context, t, msg);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }),
),


                    if (contract.term != ContractTerm.daily &&
                        contract.advanceMode != AdvanceMode.none &&
                        (contract.advancePaid ?? 0) > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('تفاصيل الدفعة المقدمة'),
SizedBox(height: 6.h),
Text(
  'قيمة إجمالي المقدم: ${_fmtMoneyTrunc(contract.advancePaid ?? 0)} ${_displayCurrency(contract.currency)}',
  style: GoogleFonts.cairo(color: Colors.white70, height: 1.5),
),
SizedBox(height: 6.h),





                          Builder(
                            builder: (_) {
                              if (contract.advanceMode == AdvanceMode.deductFromTotal) {
                                final months = _monthsInTerm(contract.term);
                                final installments = (months / _monthsPerCycle(contract.paymentCycle)).ceil().clamp(1, 1000);
                                final net = (contract.totalAmount - (contract.advancePaid ?? 0)).clamp(0, double.infinity);
                                final per = net / installments;
                                return Text(
                                  'بعد خصم المقدم • المتبقي: ${_fmtMoneyTrunc(net)} ${contract.currency}\n'
                                  'عدد الدفعات: $installments • قيمة الدفعة: ${_fmtMoneyTrunc(per)} ${_displayCurrency(contract.currency)}',
                                  style: GoogleFonts.cairo(color: Colors.white70, height: 1.5),
                                );
                             } else {
  final months      = _monthsInTerm(contract.term);
  final mPerCycle   = _monthsPerCycle(contract.paymentCycle);
  final perCycleAll = ((months / mPerCycle).ceil()).clamp(1, 1000);
  final monthly     = months > 0 ? (contract.totalAmount / months) : 0.0;

  final advPaid        = (contract.advancePaid ?? 0).toDouble();
  final coveredCycles  = monthly > 0
      ? (advPaid / (monthly * mPerCycle)).floor().clamp(0, perCycleAll)
      : 0;
  final coveredMonths  = coveredCycles * mPerCycle; // ⬅️ أضف هذا
  final outstanding    = (contract.totalAmount - advPaid).clamp(0, double.infinity);
  final remainingInst  = (perCycleAll - coveredCycles).clamp(0, 1000);
  final perCycleAmount = (remainingInst > 0) ? (outstanding / remainingInst) : 0.0;

  return Text(
    'اجمالي عدد الدفعات: $perCycleAll\n'
    'عدد دفعات المقدم: $coveredCycles أشهر\n'
    'المتبقي من الاجمالي: ${_fmtMoneyTrunc(outstanding)} ${contract.currency}\n'
    'عدد الدفعات المتبقية: $remainingInst\n'
    'قيمة كل دفعة: ${_fmtMoneyTrunc(perCycleAmount)} ${_displayCurrency(contract.currency)}',
    style: GoogleFonts.cairo(color: Colors.white70, height: 1.5),
  );
}

                            },
                          ),
                          SizedBox(height: 8.h),
                        ],
                      ),
                  ],
                ),
              ),

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
                          if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                          _terminate(context, contract);
                        },
                      ),
                    _miniAction(
                      icon: Icons.sticky_note_2_rounded,
                      label: 'ملاحظات',
                      bg: const Color(0xFF1E293B),
                      onTap: () async {
                        // 🚫 منع عميل المكتب من تعديل الملاحظات
                        if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                        _editNotes(context, contract);
                      },
                    ),

                  ],
                ),
              ),

              SizedBox(height: 10.h),

if (contract.isTerminated || contract.isExpiredByTime) ...[
  _noteCard('العقد منتهي'),
  SizedBox(height: 8.h), // مسافة بسيطة (عدّلها 6.h أو 10.h حسب رغبتك)
],



      if (!_hasStarted(contract)) ...[

        _noteCard('العقد لم يبدأ بعد')
,
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
  _chip('التاريخ: ${_fmtDateDynamic(contract.startDate)}', bg: const Color(0xFF1F2937)),
  _chip('المبلغ: ${_fmtMoneyTrunc(contract.totalAmount)} ${_displayCurrency(contract.currency)}', bg: const Color(0xFF1F2937)),
  _chip(
    'الحالة: ${_dateOnly(SaTimeLite.now()).isAfter(_dateOnly(contract.startDate)) ? 'متأخرة' : 'مستحقة'}',
    bg: _dateOnly(SaTimeLite.now()).isAfter(_dateOnly(contract.startDate)) ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
  ),
],

    ),
    SizedBox(height: 10.h),
    Padding(
  padding: EdgeInsets.only(top: 8.h),
  child: Row(
    // يثبّت "يسار/يمين" بغض النظر عن RTL
    textDirection: TextDirection.ltr,
    children: [
      // يسار: زر واتساب بنفس منطقك الحالي
      Builder(builder: (_) {
        final isLate = _dateOnly(SaTimeLite.now()).isAfter(_dateOnly(contract.startDate));
        final kind = isLate ? 'overdue' : 'due';
        final t = firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
        final msg = _waMessage(
          c: contract,
          due: _dateOnly(contract.startDate),
          kind: kind,
          tenant: t,
          property: p,
        );

        final phoneOk = _waNumberE164(t) != null;
        if (!phoneOk) return const SizedBox.shrink();

        return _miniAction(
          icon: Icons.chat_bubble_rounded,
          label: 'واتس اب',
          bg: const Color(0xFF25D366),
          onTap: () => _openWhatsAppToTenant(context, t, msg),
        );
      }),

      const Spacer(),

      // يمين: زر سداد في موضعه القديم (أقصى اليمين)
      _miniAction(
        icon: Icons.receipt_long_rounded,
        label: 'سداد',
        onTap: () async {
          // 🚫 منع عميل المكتب من السداد
          if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

          _confirmAndPay(context, contract, _dateOnly(contract.startDate));
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
], if (contract.term != ContractTerm.daily) ...[
 // 👈 نفس سلسلة if/else، من غير فاصلة قبلها
 if (unpaidStack.isEmpty && upcomingAfterStack == null 
    && !contract.isTerminated 
    && !contract.isExpiredByTime 
    && !_hasEnded(contract)) ...[

    _noteCard('لا توجد دفعات قادمة ضمن مدة العقد.')
,
  ] else ...[
    if (unpaidStack.isNotEmpty) ...[
      ...unpaidStack.asMap().entries.map<Widget>((entry) {
        final d = entry.value;
        final isToday = _dateOnly(d) == _dateOnly(SaTimeLite.now());
        final status  = isToday ? 'مستحقة' : 'متأخرة';
        final color   = isToday ? const Color(0xFF0EA5E9) : const Color(0xFF7F1D1D);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _paymentCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                _chip('التاريخ: ${_fmtDateDynamic(d)}', bg: const Color(0xFF1F2937)),
                _chip('المبلغ: ${_fmtMoneyTrunc(_perCycleAmount(contract))} ${_displayCurrency(contract.currency)}', bg: const Color(0xFF1F2937)),
                _chip('الحالة: $status', bg: color),
              ],
            ),
            SizedBox(height: 10.h),
           Padding(
  padding: EdgeInsets.only(top: 8.h),
  child: Row(
    // يثبّت "يسار/يمين" بغض النظر عن RTL
    textDirection: TextDirection.ltr,
    children: [
      // يسار: زر واتساب بنفس منطقك الحالي
      Builder(builder: (_) {
        final isLate = _dateOnly(SaTimeLite.now()).isAfter(_dateOnly(contract.startDate));
        final kind = isLate ? 'overdue' : 'due';
        final t = firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
        final msg = _waMessage(
          c: contract,
          due: _dateOnly(contract.startDate),
          kind: kind,
          tenant: t,
          property: p,
        );

        final phoneOk = _waNumberE164(t) != null;
        if (!phoneOk) return const SizedBox.shrink();

        return _miniAction(
          icon: Icons.chat_bubble_rounded,
          label: 'واتس اب',
          bg: const Color(0xFF25D366),
          onTap: () => _openWhatsAppToTenant(context, t, msg),
        );
      }),

      const Spacer(),

      // يمين: زر سداد في موضعه القديم (أقصى اليمين)
_miniAction(
  icon: Icons.receipt_long_rounded,
  label: 'سداد',
  onTap: () async {
    // 🚫 منع عميل المكتب من السداد
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    _confirmAndPay(context, contract, _dateOnly(d)); // ← الأقدم أو المحدد
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
      }).toList(),
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
        final diff = d.difference(t).inDays;
        final window = _nearWindowDaysForContract(contract);
        final nearing = diff >= 1 && diff <= window;
        final status  = nearing ? 'قارب' : 'قادمة';
        final color   = nearing ? const Color(0xFFB45309) : const Color(0xFF065F46);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _paymentCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                _chip('التاريخ: ${_fmtDateDynamic(upcomingAfterStack!)}', bg: const Color(0xFF1F2937)),
                _chip('المبلغ: ${_fmtMoneyTrunc(_perCycleAmount(contract))} ${_displayCurrency(contract.currency)}', bg: const Color(0xFF1F2937)),
                _chip('الحالة: $status', bg: color),
              ],
            ),
            SizedBox(height: 10.h),
           Padding(
  padding: EdgeInsets.only(top: 8.h),
  child: Row(
    // يثبّت "يسار/يمين" بغض النظر عن RTL
    textDirection: TextDirection.ltr,
    children: [
      // يسار: زر واتساب بنفس منطقك الحالي
      Builder(builder: (_) {
final dOnly     = _dateOnly(upcomingAfterStack!);
final todayOnly = _dateOnly(SaTimeLite.now());
final isLate    = todayOnly.isAfter(dOnly);
final isToday   = dOnly == todayOnly;

// أضف منطق "near" باستخدام نفس نافذة القرب المعتمدة في الواجهة
final diff    = dOnly.difference(todayOnly).inDays;
final nearWin = _nearWindowDaysForContract(contract);
final isNear  = diff >= 1 && diff <= nearWin;

// اسمح بالزر في (متأخرة/اليوم/قاربت). اخفِه فقط إن كانت "قادمة" بعيدة
if (!isLate && !isToday && !isNear) return const SizedBox.shrink();

// مرّر النوع الصحيح للرسالة (يدعم 'near' بالفعل في _waMessage)
final kind = isLate ? 'overdue' : (isToday ? 'due' : 'near');


        final t = firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
        final msg = _waMessage(
          c: contract,
          due: dOnly,

          kind: kind,
          tenant: t,
          property: p,
        );

        final phoneOk = _waNumberE164(t) != null;
        if (!phoneOk) return const SizedBox.shrink();

        return _miniAction(
          icon: Icons.chat_bubble_rounded,
          label: 'واتس اب',
          bg: const Color(0xFF25D366),
          onTap: () => _openWhatsAppToTenant(context, t, msg),
        );
      }),

      const Spacer(),

      // يمين: زر سداد في موضعه القديم (أقصى اليمين)
      _miniAction(
        icon: Icons.receipt_long_rounded,
        label: 'سداد',
        onTap: () async {
          // 🚫 منع عميل المكتب من السداد
          if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

          _confirmAndPay(context, contract, _dateOnly(upcomingAfterStack!));
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
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, color: Colors.white),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          'الدفعات السابقة',
                          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ); // ← مهم: سيمي كولون
      },   // ← إغلاق builder
    ),     // ← إغلاق AnimatedBuilder
    // === AnimatedBuilder ينتهي هنا ===
  ],
),  // ← يُغلق Stack
bottomNavigationBar: AppBottomNav(
  key: _bottomNavKey,
  currentIndex: 3,
  onTap: _handleBottomTap,
),

      ),
    );
  }

  Widget _miniAction({required IconData icon, required String label, required VoidCallback onTap, Color bg = const Color(0xFF1E293B)}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r), border: Border.all(color: Colors.white.withOpacity(0.15))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16.sp, color: Colors.white),
          SizedBox(width: 6.w),
          Text(label, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.sp)),
        ]),
      ),
    );
  }

 void _openTenant(BuildContext context, Tenant? t) async {
  if (t == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const tenants_ui.TenantsScreen(),
      settings: RouteSettings(arguments: {'openTenantId': t.id}),
    ),
  );
}


  void _openProperty(BuildContext context, String? propertyId) async {
  if (propertyId == null) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const PropertiesScreen(),
      settings: RouteSettings(arguments: {'openPropertyId': propertyId}),
    ),
  );
}

Future<void> _confirmAndPay(BuildContext context, Contract c, DateTime due) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionsAlignment: MainAxisAlignment.center,
      title: Text('تأكيد السداد',
          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text(
        'هل أنت متأكد من المتابعة؟ سيتم إصدار فاتورة تلقائيًا، ولا يمكن التراجع عن هذه العملية لاحقًا.',
        style: GoogleFonts.cairo(color: Colors.white70),
      ),
      actions: [
        // زر التأكيد أولاً ليتوضع يمينًا في RTL
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9)),
          onPressed: () => Navigator.pop(context, true),
          child: Text('تأكيد', style: GoogleFonts.cairo(color: Colors.white)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('إلغاء',
              style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  ) ?? false;

  if (!ok) return;
  await _goPay(context, c, due);
}


  Future<void> _goPay(BuildContext context, Contract c, DateTime due) async {
final number = (c.serialNo?.isNotEmpty == true) ? c.serialNo! : c.id;

  try {
    // منع السداد قبل بداية العقد
    if (!_hasStarted(c)) {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            actionsAlignment: MainAxisAlignment.center,
            title: Text('غير ممكن', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Text('العقد لم يبدأ بعد. لا يمكن السداد قبل تاريخ البداية.', style: GoogleFonts.cairo(color: Colors.white70)),
            actions: [ TextButton(onPressed: () => Navigator.pop(context), child: Text('حسنًا', style: GoogleFonts.cairo(color: Colors.white70))) ],
          ),
        );
      }
      return;
    }

// منع تكرار سداد اليومي
if (c.term == ContractTerm.daily && _dailyAlreadyPaid(c)) {
  if (context.mounted) {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actionsAlignment: MainAxisAlignment.center,
        title: Text('غير ممكن', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text('تم سداد الإيجار اليومي لهذا العقد مسبقًا.', style: GoogleFonts.cairo(color: Colors.white70)),
        actions: [ TextButton(onPressed: () => Navigator.pop(context), child: Text('حسنًا', style: GoogleFonts.cairo(color: Colors.white70))) ],
      ),
    );
  }
  return;
}

    final today    = _dateOnly(SaTimeLite.now());
// 👇 ضع هذا داخل _goPay قبل إنشاء الفاتورة (بعد فحوصات البداية/اليومي)
final earliest = _earliestUnpaidDueDate(c);  // أقدم قسط غير مسدَّد فعليًا
if (earliest != null) {
  final d0   = _dateOnly(earliest);
  final due0 = _dateOnly(due);

  // لا تسمح بسداد قسط “أبعد” بينما يوجد قسط أقدم غير مسدَّد
  if (due0.isAfter(d0)) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actionsAlignment: MainAxisAlignment.center,
          title: Text('لا يمكن السداد',
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Text(
            'توجد دفعة غير مسددة بتاريخ ${_fmtDateDynamic(d0)}. يجب سداد الأقدم أولًا.',
            style: GoogleFonts.cairo(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('حسنًا',
                  style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    return;
  }
}


    // *** الباقي كما هو (إصدار الفاتورة وتحريك المؤشر) ***
   
final box = Hive.box<Invoice>(boxName(kInvoicesBox));
final amount = _perCycleAmount(c);
final now = SaTimeLite.now();


// جهّز رقم عقد للعرض بصيغة سنة-تسلسل حتى لو كان مخزّن بالعكس
String _displaySerial(String? s) {
  final v = (s ?? '').trim();
  if (v.isEmpty) return v;

  final parts = v.split('-');
  if (parts.length == 2) {
    final a = parts[0].trim();
    final b = parts[1].trim();

    bool isYear(String x) =>
        int.tryParse(x) != null && x.length == 4 && int.parse(x) >= 1900 && int.parse(x) <= 2100;

    // إذا التسلسل أولاً والسنة ثانيًا: اقلبها إلى سنة-تسلسل
    if (!isYear(a) && isYear(b)) {
      final seq = a.padLeft(4, '0');
      return '$b-$seq';
    }
  }
  return v;
}

// تجهيز رقم العقد للعرض الصحيح
final serialDisplay = _displaySerial(c.serialNo);        // سنة-تسلسل
final serialLtr     = '\u200E${serialDisplay}\u200E';    // عرض من اليسار لليمين

final inv = Invoice(
  tenantId:   c.tenantId,
  contractId: c.id,
  propertyId: c.propertyId,
  issueDate:  now,
  dueDate:    _dateOnly(due),
  amount:     amount,
  paidAmount: amount, // لو تبغيه “مدفوع تلقائيًا”
  currency:   c.currency,

  note: serialDisplay.isNotEmpty ? 'سداد عقد رقم $serialLtr' : 'سداد عقد',

  paymentMethod: 'نقدًا',
  createdAt:  now,
  updatedAt:  now,
);



// أضف الفاتورة
final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
// ترقيم عند الإنشاء: لجميع الفواتير غير الملغاة
if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
  inv.serialNo  = _nextInvoiceSerialForContracts(invBox);
  inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
}

await invBox.put(inv.id, inv);
if (mounted) {
  setState(() {
    // ✅ اعرض أقدم استحقاق غير مدفوع مباشرةً بعد السداد
    _overrideNextDue = _earliestUnpaidDueDate(c);
  });
}




    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إصدار الفاتورة تلقائيًا', style: GoogleFonts.cairo())),
    );

    

    await Navigator.of(context).pushNamed('/invoices/history', arguments: {'contractId': c.id});
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إصدار الفاتورة: $e', style: GoogleFonts.cairo())),
      );
    }
  }
}


  void _openInvoicesHistory(BuildContext context, Contract c) async {
    try {
      await Navigator.of(context).pushNamed('/invoices/history', arguments: {'contractId': c.id});
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('شاشة فواتير الدفعات السابقة غير متوفرة بعد.', style: GoogleFonts.cairo())));
    }
  }

  Future<void> _editNotes(BuildContext context, Contract contract) async {
    final controller = TextEditingController(text: contract.notes ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16.w, right: 16.w, top: 16.h),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('الملاحظات', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
            SizedBox(height: 10.h),
            TextField(
              controller: controller,
              maxLines: 6,
              style: GoogleFonts.cairo(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'اكتب ملاحظاتك هنا',
                hintStyle: GoogleFonts.cairo(color: Colors.white54),
                filled: true, fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            SizedBox(height: 12.h),
            Row(children: [
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9)), onPressed: () => Navigator.of(ctx).pop(true), child: Text('حفظ', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)))),
              SizedBox(width: 8.w),
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white)))),
            ]),
            SizedBox(height: 12.h),
          ]),
        );
      },
    );

    if (saved == true) {
      contract.notes = controller.text.trim().isEmpty ? null : controller.text.trim();
      contract.updatedAt = SaTimeLite.now();
      await contract.save();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ الملاحظات', style: GoogleFonts.cairo())));
      }
      setState(() {});
    }
  }

Future<void> _terminate(BuildContext context, Contract contract) async {
  // قبل إنهاء العقد: التأكد من عدم وجود دفعات مستحقة أو متأخرة
  bool hasUnpaid = false;

  try {
    if (contract.term == ContractTerm.daily) {
      // العقود اليومية: غير مسدّد بالكامل
      hasUnpaid = !_dailyAlreadyPaid(contract);
    } else {
      // غير اليومي: أي قسط غير مدفوع حتى اليوم (مستحق أو متأخر)
      final unpaid = _buildUnpaidStack(contract);
      hasUnpaid = unpaid.isNotEmpty;
    }
  } catch (_) {
    // في حال حصل خطأ غير متوقّع، نترك hasUnpaid = false ولا نكسر التطبيق
  }

  if (hasUnpaid) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          title: Text(
            'لا يمكن إنهاء العقد',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'لا يمكن إنهاء هذا العقد لوجود دفعات مستحقة أو متأخرة لم تُسدَّد بعد.\n'
            'يرجى تسوية جميع المستحقات أولاً، ثم إعادة محاولة الإنهاء.',
            style: GoogleFonts.cairo(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'حسناً',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    return; // إيقاف عملية الإنهاء بالكامل
  }


    final ok = await showDialog<bool>(
  context: context,
  builder: (_) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionsAlignment: MainAxisAlignment.center, // وسط الأزرار
      title: Text('إنهاء العقد',
          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text('سيتم إنهاء العقد وإتاحة العقار للتأجير',
          style: GoogleFonts.cairo(color: Colors.white70)),
      actions: [
        // ← اجعل "إنهاء" أولاً ليظهر يمينًا في RTL
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('إنهاء', style: GoogleFonts.cairo(color: Colors.white)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('إلغاء',
              style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  },
) ?? false;


    if (!ok) return;

    final properties = Hive.box<Property>(boxName(kPropertiesBox));
    final tenants    = Hive.box<Tenant>(boxName(kTenantsBox));

    final prop = firstWhereOrNull(properties.values, (p) => p.id == contract.propertyId);
    if (prop != null) {
      if (prop.parentBuildingId != null) {
        prop.occupiedUnits = 0;
        await prop.save();
        final siblings = properties.values.where((e) => e.parentBuildingId == prop.parentBuildingId);
        final count = siblings.where((e) => e.occupiedUnits > 0).length;
        final building = firstWhereOrNull(properties.values, (e) => e.id == prop.parentBuildingId);
        if (building != null) {
          building.occupiedUnits = count;
          await building.save();
        }
      } else {
        prop.occupiedUnits = 0;
        await prop.save();
      }
    }

    // وقت الإنهاء
    final now = SaTimeLite.now();

    // نحسب إذا كان العقد كان نشطًا قبل أن نغيّر endDate
    final wasActive = !now.isBefore(contract.startDate) && !now.isAfter(contract.endDate);

    // ✅ قصّر نهاية العقد إلى يوم الإنهاء
    // هذا يضمن أن كل منطق الدفعات لن يولّد أي دفعات بعد هذا اليوم
    contract.endDate = _dateOnly(now);

    // علّم العقد أنه منتهي
    contract.isTerminated = true;
    contract.terminatedAt = now;
    contract.updatedAt = now;
    await contract.save();

    if (!mounted) return;
    setState(() {});

    // تحديث عدّاد العقود النشطة للمستأجر (باستخدام wasActive القديم)
    final t = firstWhereOrNull(tenants.values, (x) => x.id == contract.tenantId);
    if (t != null) {
      if (wasActive && t.activeContractsCount > 0) {
        t.activeContractsCount -= 1;
      }
      t.updatedAt = now;
      await t.save();
    }


    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إنهاء العقد', style: GoogleFonts.cairo()), behavior: SnackBarBehavior.floating));
      setState(() {}); // ابقَ في نفس الشاشة بعد الإنهاء وتحديث الواجهة

    }
  }

Future<void> _delete(BuildContext context, Contract contract) async {
  // 🚫 حماية إضافية: منع عميل المكتب من الحذف حتى لو استُدعيت الدالة مباشرة
  if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

  // ✅ أولاً: اجلب النسخة الحية من بوكس العقود
  final contractsBox = Hive.box<Contract>(boxName(kContractsBox));

  Contract? live = contract;


  // لو النسخة التي وصلت ليست داخل الصندوق، حاول إيجادها عن طريق id
  if (!(live?.isInBox ?? false)) {
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
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actionsAlignment: MainAxisAlignment.center,
        title: Text(
          'لا يمكن الحذف',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'لا يمكن حذف العقد لأنه غير مُنتهي. يجب إنهاء العقد أولًا.',
          style: GoogleFonts.cairo(
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'حسنًا',
              style: GoogleFonts.cairo(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return;
  }

  // 🚫 منع حذف عقد تم إصدار فواتير مرتبطة به
  try {
    final invBoxCheck = Hive.box<Invoice>(boxName(kInvoicesBox));
    final cidCheck = cLive.id;
    final hasInvoices =
        invBoxCheck.values.any((i) => i.contractId == cidCheck);

    if (hasInvoices) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actionsAlignment: MainAxisAlignment.center,
          title: Text(
            'لا يمكن الحذف',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'لا يمكن حذف العقد بعد إصدار فواتير مرتبطة به.\n'
            'يمكنك فقط أرشفة العقد إذا لم تعد بحاجة لظهوره.',
            style: GoogleFonts.cairo(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'حسنًا',
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      return; // ⛔ إيقاف الحذف نهائيًا
    }
  } catch (_) {
    // لو صار خطأ في قراءة صندوق الفواتير لا نكسر الشاشة
  }

  // ✅ من هنا يبدأ تأكيد الحذف العادي (عقد منتهي وبدون فواتير)
  final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          actionsAlignment: MainAxisAlignment.center,
          title: Text(
            'تاكيد الحذف',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'هل تريد حذف هذا العقد نهائيًا؟ سيتم حذف جميع الفواتير المرتبطة بهذا العقد.',
            style: GoogleFonts.cairo(
              color: Colors.white70,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'حذف',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;

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
      final count =
          siblings.where((e) => e.occupiedUnits > 0).length;
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
  final t =
      firstWhereOrNull(tenants.values, (x) => x.id == cLive.tenantId);
  if (t != null && cLive.isActiveNow && t.activeContractsCount > 0) {
    t.activeContractsCount -= 1;
    t.updatedAt = SaTimeLite.now();
    await t.save();
  }

  // 🔻 حذف الفواتير المرتبطة (احتياط إضافي)
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
class AddOrEditContractScreen extends StatefulWidget {
  final Contract? existing;
  const AddOrEditContractScreen({super.key, this.existing});

  @override
  State<AddOrEditContractScreen> createState() => _AddOrEditContractScreenState();
}

class _AddOrEditContractScreenState extends State<AddOrEditContractScreen> {
  final _formKey = GlobalKey<FormState>();

  Tenant? _selectedTenant;
  Property? _selectedProperty;

  DateTime? _startDate;
  DateTime? _endDate;
  final _rent = TextEditingController();
  final _advance = TextEditingController();
  final _daysCtrl = TextEditingController(text: '1'); // لليومي (ليالي)

  PaymentCycle _cycle = PaymentCycle.monthly;
  ContractTerm _term = ContractTerm.monthly;
  AdvanceMode _advMode = AdvanceMode.none;
  String _currency = 'SAR';
  final _notes = TextEditingController();
  bool _advanceLimitExceeded = false; // المقدم تجاوز المبلغ الكلي
bool _rentLimitExceeded = false; // ✅ هنا بالضبط

  Box<Contract> get _contracts => Hive.box<Contract>(boxName(kContractsBox));
  Box<Tenant>   get _tenants   => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get _properties=> Hive.box<Property>(boxName(kPropertiesBox));

Future<String> _nextContractSerial() async {
  final year = SaTimeLite.now().year;

  int maxSeq = 0;
  try {
    // احسب أكبر تسلسل لنفس السنة من العقود الموجودة حاليًا في الصندوق
    for (final c in _contracts.values) {
      final s = c.serialNo; // أمثلة: 2025-12 أو 2025-0007
      if (s != null && s.startsWith('$year-')) {
        final tail = s.split('-').last;      // "12" أو "0007"
        final n = int.tryParse(tail) ?? 0;   // 12 أو 7
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
      _selectedTenant = firstWhereOrNull(_tenants.values, (t) => t.id == c.tenantId);
      _selectedProperty = firstWhereOrNull(_properties.values, (p) => p.id == c.propertyId);
      _startDate = _dateOnly(c.startDate);
      _endDate = _dateOnly(c.endDate);
      _term = c.term;
      _cycle = c.paymentCycle;
if (_term != ContractTerm.daily) {
  final allowed = _allowedCyclesForTerm(_term);
  if (!allowed.contains(_cycle) && allowed.isNotEmpty) _cycle = allowed.first;
}

      _currency = c.currency;
      _advMode = c.advanceMode;
      _advance.text = c.advancePaid?.toString() ?? '';
      if (c.term == ContractTerm.daily) {
        final days = _inclusiveDays(c.startDate, c.endDate);
        _daysCtrl.text = days.toString();
        final perDay = days > 0 ? (c.totalAmount / days) : c.totalAmount;
        _rent.text = perDay.toStringAsFixed(2);
        
      } else {
        _rent.text = c.totalAmount.toString();
      }
      _notes.text = c.notes ?? '';
    } else {
      // ضبط افتراضي على اليوم بناءً على فترة العقد الافتراضية
      _startDate = today();
      _endDate = _termEndInclusive(_startDate!, _term);
    }
_ensureCycleFitsTerm();
    _daysCtrl.addListener(_onDailyInputsChanged);
  }

  void _prefillFromRouteArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final m = args.cast<String, dynamic>();
      final propertyId = m['prefillPropertyId'] as String?;
      final tenantId = m['prefillTenantId'] as String?;

      if (propertyId != null) {
        final p = firstWhereOrNull(_properties.values, (x) => x.id == propertyId);
        if (p != null) _selectedProperty = p;
      }
      if (tenantId != null) {
        final t = firstWhereOrNull(_tenants.values, (x) => x.id == tenantId);
        if (t != null) _selectedTenant = t;
      }
      if (mounted) setState(() {});
    } else if (args is String) {
      // دعم تمرير المعرّف كسلسلة مباشرة (اعتبره propertyId)
      final p = firstWhereOrNull(_properties.values, (x) => x.id == args);
      if (p != null) {
        _selectedProperty = p;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _rent.dispose();
    _advance.dispose();
    _notes.dispose();
    _daysCtrl.removeListener(_onDailyInputsChanged);
    _daysCtrl.dispose();
    super.dispose();
  }

 void _onDailyInputsChanged() {
  if (_term != ContractTerm.daily) return;

  final d = int.tryParse(_daysCtrl.text.trim()) ?? 0;

  if (_startDate == null) {
    _startDate = today();
  }

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
    return _inclusiveDays(_startDate!, _endDate!);
  }

void _recalcEndByTermAfterStartChange() {
  if (_startDate == null) return;

  if (_term == ContractTerm.daily) {
    final d = int.tryParse(_daysCtrl.text.trim()) ?? 1;
    // يوم واحد => النهاية في اليوم التالي (بدون -1)
    _endDate = _dateOnly(_startDate!).add(Duration(days: (d <= 0 ? 1 : d)));
  } else {
    _endDate = _termEndInclusive(_startDate!, _term);
  }
}

void _applyTermDatesFromToday() {
  _startDate = today();
  if (_term == ContractTerm.daily) {
    final d = int.tryParse(_daysCtrl.text.trim()) ?? 1;
    _endDate = _dateOnly(_startDate!).add(Duration(days: (d <= 0 ? 1 : d)));
  } else {
    _endDate = _termEndInclusive(_startDate!, _term);
  }
}






void _ensureCycleFitsTerm() {
  if (_term == ContractTerm.daily) return;
  final allowed = _allowedCyclesForTerm(_term);
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

    final totalDaily = isDaily ? (rentInput * (days > 0 ? days : 0)) : 0.0;



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

          title: Text(isEdit ? 'تعديل عقد' : 'إضافة عقد', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)]),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

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
                        leading: const Icon(Icons.person_rounded, color: Colors.white),
                        errorText: _selectedTenant == null ? 'مطلوب' : null,
                      ),
                      if (tenantWarn) ...[
                        SizedBox(height: 6.h),
                        Align(alignment: Alignment.centerRight, child: _chip('المستأجر محظور', bg: const Color(0xFF7F1D1D))),
                      ],
                      SizedBox(height: 12.h),

                      // العقار (إجباري)
                      _selectorTile(
                        title: 'العقار/الوحدة',
                        valueText: _selectedProperty?.name ?? 'اختر عقارًا أو وحدة',
                        onTap: _pickProperty,
                        leading: const Icon(Icons.home_work_rounded, color: Colors.white),
                        errorText: _selectedProperty == null ? 'مطلوب' : null,
                      ),
                      SizedBox(height: 12.h),

                      // فترة العقد (إجباري) + ضبط التواريخ فورًا من اليوم
                      DropdownButtonFormField<ContractTerm>(
                        value: _term,
                        decoration: _dd('فترة العقد'),
                        dropdownColor: const Color(0xFF0F172A),
                        iconEnabledColor: Colors.white70,
                        style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                        items: ContractTerm.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
      onChanged: (v) {
  setState(() {
    _term = v ?? ContractTerm.monthly;
    _applyTermDatesFromToday(); // ✅ الآن موجودة
    _ensureCycleFitsTerm();
if (_termEqualsCycle(_term, _cycle)) {
  _advMode = AdvanceMode.none;
  _advance.clear();
}

  });
},


                      ),
                      SizedBox(height: 12.h),

                      // لليومي: عدد الأيام (ليالي) + ساعة الخروج
                     if (isDaily) ...[
  _field(
    controller: _daysCtrl,
    label: 'عدد الأيام (ليالي)',
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (v) {
      final n = int.tryParse((v ?? '').trim()) ?? 0;
      if (n <= 0) return 'أدخل رقمًا صحيحًا';
      return null;
    },
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
  label: isDaily ? 'قيمة الإيجار اليومي' : 'قيمة الإيجار الكلي',
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [
    // نفس التقييد القديم: أرقام + نقطتين عشريتين
    FilteringTextInputFormatter.allow(
      RegExp(r'^\d*\.?\d{0,2}$'),
    ),
    // فورماتّر إضافي يمنع تجاوز 100,000,000 في الإيجار الكلي
    TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;

      // نسمح بالحذف
      if (text.isEmpty) {
        if (_rentLimitExceeded) {
          _rentLimitExceeded = false;
          // إعادة بناء لتحديث الرسالة لو كانت ظاهرة
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {});
          });
        }
        return newValue;
      }

      // لو حاول يتجاوز 100 مليون
      if (n > 100000000) {
        if (!_rentLimitExceeded) {
          _rentLimitExceeded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {});
          });
        }
        // نرجّع القيمة القديمة (يمنع الكتابة)
        return oldValue;
      }

      // داخل الحد → نلغي حالة التجاوز لو كانت مفعّلة
      if (_rentLimitExceeded) {
        _rentLimitExceeded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {});
        });
      }

      return newValue;
    }),
  ],
  autovalidateMode: AutovalidateMode.onUserInteraction,
  validator: (v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'مطلوب';

    final n = double.tryParse(s);
    if (n == null || n <= 0) return 'أدخل مبلغًا صحيحًا';

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
    value: _currency,
    decoration: _dd('العملة'),
    dropdownColor: const Color(0xFF0F172A),
    iconEnabledColor: Colors.white70,
    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
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
    value: (() {
      final allowed = _allowedCyclesForTerm(_term);
      return allowed.contains(_cycle)
          ? _cycle
          : (allowed.isNotEmpty ? allowed.first : PaymentCycle.monthly);
    })(),
    decoration: _dd('دورة السداد'),
    dropdownColor: const Color(0xFF0F172A),
    iconEnabledColor: Colors.white70,
    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
    items: _allowedCyclesForTerm(_term)
        .map((pc) => DropdownMenuItem(value: pc, child: Text(pc.label)))
        .toList(),
    onChanged: (v) => setState(() {
      final allowed = _allowedCyclesForTerm(_term);
      _cycle = v ?? (allowed.isNotEmpty ? allowed.first : PaymentCycle.monthly);
if (_termEqualsCycle(_term, _cycle)) {
  _advMode = AdvanceMode.none;
  _advance.clear();
}

    }),
  ),

  SizedBox(height: 6.h),

  // ⬅️ التنبيه (بدون مقدم) يظهر هنا تحت "دورة السداد"
  if (rentInput > 0 && _advMode == AdvanceMode.none)
    Builder(builder: (_) {
      final months = _monthsInTerm(_term);
      final perCycle = (months / _monthsPerCycle(_cycle)).ceil().clamp(1, 1000);
      final total = rentInput;
      final per = total / perCycle;
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          'عدد الأشهر: $months • عدد الدفعات: $perCycle • قيمة الدفعة: ${_fmtMoneyTrunc(per)} $_currency',

          style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12.sp),
        ),
      );
    }),

  SizedBox(height: 12.h),
],


                      // هل هنالك دفعة مقدمة؟
                      if (!isDaily && _term != ContractTerm.monthly && !_termEqualsCycle(_term, _cycle))

                        DropdownButtonFormField<String>(
                          value: _advMode == AdvanceMode.none ? 'لا' : 'نعم',
                          decoration: _dd('هل هنالك دفعة مقدمة؟'),
                          dropdownColor: const Color(0xFF0F172A),
                          iconEnabledColor: Colors.white70,
                          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                          items: const ['نعم', 'لا'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                          onChanged: (v) => setState(() {
                            if (v == 'نعم') {
                              _advMode = AdvanceMode.deductFromTotal;
                            } else {
                              _advMode = AdvanceMode.none;
                              _advance.clear();
                            }
                          }),
                        ),
                      if (!isDaily && _term != ContractTerm.monthly) SizedBox(height: 10.h),


                      // نوع المقدم + القيمة
                      if (!isDaily && _term != ContractTerm.monthly && _advMode != AdvanceMode.none) ...[

                        DropdownButtonFormField<AdvanceMode>(
  value: _advMode,
  decoration: _dd('حدد نوع المقدم'),
  dropdownColor: const Color(0xFF0F172A),
  iconEnabledColor: Colors.white70,
  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
  items: const [AdvanceMode.deductFromTotal, AdvanceMode.coverMonths]
      .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
      .toList(),
  onChanged: (v) {
    setState(() {
      _advMode = v ?? AdvanceMode.deductFromTotal;
      _advance.clear(); // مهم لتجنّب بقاء قيمة غير مناسبة لنوع الإدخال
    });
  },
),
SizedBox(height: 10.h),

_field(
  controller: _advance,
  label: _advMode == AdvanceMode.coverMonths
      ? 'عدد الدفعات المقدمة'
      : 'قيمة الدفعة المقدمة',
  keyboardType: _advMode == AdvanceMode.coverMonths
      ? TextInputType.number
      : const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: _advMode == AdvanceMode.coverMonths
      ? [
          FilteringTextInputFormatter.digitsOnly,
          TextInputFormatter.withFunction((oldValue, newValue) {
            final text = newValue.text;

            // مسح الحقل
            if (text.isEmpty) {
              _advanceLimitExceeded = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
              return newValue;
            }

            final n = int.tryParse(text);
            if (n == null) return oldValue;

            // إجمالي عدد الدفعات في العقد
            final months = _monthsInTerm(_term);
            final perCycle =
                (months / _monthsPerCycle(_cycle)).ceil().clamp(1, 1000);

            // لو تجاوز إجمالي الدفعات → امنع واكتب فلاغ
            if (n > perCycle) {
              _advanceLimitExceeded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
              return oldValue; // يمنع الزيادة
            }

            // داخل الحد → ألغِ حالة التجاوز
            if (_advanceLimitExceeded) {
              _advanceLimitExceeded = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }

            return newValue;
          }),
        ]
      : [
          FilteringTextInputFormatter.allow(
            RegExp(r'^\d*\.?\d{0,2}$'),
          ),
          TextInputFormatter.withFunction((oldValue, newValue) {
            final text = newValue.text;

            // مسح الحقل
            if (text.isEmpty) {
              _advanceLimitExceeded = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
              return newValue;
            }

            final n = double.tryParse(text);
            if (n == null) return oldValue;

            // قيمة الإيجار الكلي من حقل الإيجار
            final totalRent = double.tryParse(_rent.text) ?? 0;

            // لو وضع "يخصم من الإجمالي" والمقدم > الإيجار الكلي
            if (_advMode == AdvanceMode.deductFromTotal &&
                totalRent > 0 &&
                n > totalRent) {
              _advanceLimitExceeded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
              return oldValue; // يمنع الكتابة الزائدة
            }

            // داخل الحد → ألغِ حالة التجاوز
            if (_advanceLimitExceeded) {
              _advanceLimitExceeded = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }

            return newValue;
          }),
        ],
  autovalidateMode: AutovalidateMode.onUserInteraction,
  validator: (v) {
    final s = (v ?? '').trim();
    if (_advMode == AdvanceMode.none) return null;
    if (s.isEmpty) return 'مطلوب';

    if (_advMode == AdvanceMode.coverMonths) {
      final n = int.tryParse(s);
      if (n == null) return 'أدخل عددًا صحيحًا';
      if (n < 1) return 'الحد الأدنى دفعة واحدة';

      final months = _monthsInTerm(_term);
      final perCycle =
          (months / _monthsPerCycle(_cycle)).ceil().clamp(1, 1000);

      if (n > perCycle || _advanceLimitExceeded) {
        return 'لا يمكن أن يتجاوز عدد الدفعات الكلي ($perCycle)';
      }
      return null;
    }

    // وضع "يخصم من الإجمالي" (مبلغ مالي)
    final n = double.tryParse(s);
    if (n == null || n <= 0) return 'أدخل مبلغًا صحيحًا';

    final totalRent = double.tryParse(_rent.text) ?? 0;
    if (_advMode == AdvanceMode.deductFromTotal &&
        totalRent > 0 &&
        (n > totalRent || _advanceLimitExceeded)) {
      return 'لا يمكن أن يتجاوز المقدم قيمة الإيجار الكلي';
    }

    return null;
  },
),


                        SizedBox(height: 6.h),
                      ],

                      // ملخص المقدم
                      if (!isDaily && rentInput > 0 && _advMode != AdvanceMode.none) ...[
                       Builder(builder: (_) {
  final months = _monthsInTerm(_term);
  final perCycle = (months / _monthsPerCycle(_cycle)).ceil().clamp(1, 1000);
  final total = rentInput;
  final monthlyValue = months > 0 ? total / months : 0.0;
  final mPerCycle = _monthsPerCycle(_cycle);

  double advAmount; // المبلغ المكافئ للمقدم (حتى مع coverMonths نحسبه من العدد)
  int coveredCycles; // عدد الدفعات (الأقساط) المقدّمة
  int coveredMonths; // الأشهر التي سيغطيها

  if (_advMode == AdvanceMode.coverMonths) {
    coveredCycles = int.tryParse(_advance.text.trim()) ?? 0;
    if (coveredCycles < 0) coveredCycles = 0;
    if (coveredCycles > perCycle) coveredCycles = perCycle;
    coveredMonths = coveredCycles * mPerCycle;
    advAmount = coveredMonths * monthlyValue;
  } else {
    final adv = advanceVal; // القيمة المدخلة كمبلغ
    coveredCycles = 0;
    coveredMonths = (monthlyValue > 0) ? (adv / monthlyValue).floor() : 0;
    advAmount = adv;
  }

  final net = (total - (_advMode == AdvanceMode.deductFromTotal ? advAmount : 0)).clamp(0, double.infinity);
  final per = perCycle > 0 ? net / perCycle : 0.0;

// لعرض تفاصيل تغطية الدفعات (حتى مع coverMonths):
final perCycleAmount = perCycle > 0 ? (total / perCycle) : 0.0;            // قيمة كل دفعة (الإجمالي/عدد الدفعات)
final remainingInst = (perCycle - coveredCycles).clamp(0, 1000);           // الدفعات المتبقية
final outstanding   = (perCycleAmount * remainingInst).clamp(0, double.infinity); // المتبقي من الإجمالي


  return Align(
    alignment: Alignment.centerRight,
    child: Text(
      _advMode == AdvanceMode.coverMonths
  ? 'إجمالي عدد الدفعات: $perCycle • كل دفعة = $mPerCycle شهر\n'
    'عدد الدفعات المقدمة: $coveredCycles • سيغطي: $coveredMonths شهر\n'
    'قيمة إجمالي المقدم: ${_fmtMoneyTrunc(advAmount)} $_currency\n'
    'المتبقي من الإجمالي: ${_fmtMoneyTrunc(outstanding)} $_currency • الدفعات المتبقية: $remainingInst • قيمة كل دفعة: ${_fmtMoneyTrunc(perCycleAmount)} $_currency'
: 'إجمالي عدد الدفعات: $perCycle\n'
  'بعد خصم المقدم: صافي الإجمالي = ${_fmtMoneyTrunc(net)} $_currency\n'
  'القسط (قيمة الدفعة) = ${_fmtMoneyTrunc(per)} $_currency',


      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12.sp, height: 1.5),
    ),
  );
}),

                        SizedBox(height: 6.h),
                      ],

                      // اليومي: ملخص
                      if (isDaily && _startDate != null && _endDate != null && rentInput > 0) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'الأيام: $days • إجمالي العقد (محسوب): ${_fmtMoneyTrunc(totalDaily)} $_currency',
                            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12.sp),
                          ),
                        ),
                        SizedBox(height: 6.h),
                      ],

                      // الملاحظات (اختياري)
                      _field(controller: _notes, label: 'ملاحظات (اختياري)', maxLines: 3),
                      SizedBox(height: 16.h),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0EA5E9),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                          ),
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ العقد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
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
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                break;
              case 1:
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
                break;
              case 2:
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const tenants_ui.TenantsScreen()));
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
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12))),
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
                Expanded(child: Text(valueText, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700))),
                const Icon(Icons.arrow_drop_down, color: Colors.white70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _datePickerTile({required String label, required DateTime? date, required VoidCallback? onPick, bool enabled = true}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: enabled && onPick != null ? onPick : null,
      child: InputDecorator(
        decoration: _dd(label).copyWith(
          enabled: enabled,
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: enabled ? Colors.white70 : Colors.white24),
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
          colorScheme: const ColorScheme.dark(primary: Colors.white, onPrimary: Colors.black, surface: Color(0xFF0B1220), onSurface: Colors.white),
          dialogBackgroundColor: const Color(0xFF0B1220),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TenantPickerSheet(),
    );
    if (result != null) setState(() => _selectedTenant = result);
  }

  Future<void> _pickProperty() async {
    final result = await showModalBottomSheet<Property>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PropertyPickerSheet(),
    );
    if (result != null) setState(() => _selectedProperty = result);
  }

  Future<void> _save() async {
    // جميع الحقول إجبـارية باستثناء الملاحظات
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedTenant == null || _selectedProperty == null) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('اختر تواريخ العقد', style: GoogleFonts.cairo())));
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تاريخ النهاية قبل البداية', style: GoogleFonts.cairo())));
      return;
    }
    if (_selectedTenant!.isBlacklisted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المستأجر محظور — لا يمكن إنشاء عقد', style: GoogleFonts.cairo())));
      return;
    }

    final prop = _selectedProperty!;
    if (!_isPropertyAvailableForContract(prop)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('العقار/الوحدة غير متاحة', style: GoogleFonts.cairo())));
      return;
    }

    final entered = double.tryParse(_rent.text.trim()) ?? 0.0;
    double total = 0.0;
    double perCycleAmount = 0.0;
if (_term != ContractTerm.daily) {
  final allowed = _allowedCyclesForTerm(_term);
  if (!allowed.contains(_cycle) && allowed.isNotEmpty) _cycle = allowed.first;
}


    int? checkoutHour;
   if (_term == ContractTerm.daily) {
  final days = int.tryParse(_daysCtrl.text.trim()) ?? 0;
  total = (entered * (days > 0 ? days : 0));
  perCycleAmount = total;
      
    } else {
      total = entered;
      final months = _monthsInTerm(_term);
      final perCycleCount = (months / _monthsPerCycle(_cycle)).ceil().clamp(1, 1000);
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
} else { // AdvanceMode.coverMonths → المستخدم أدخل عدد الدفعات
  final cyclesInput = int.tryParse(_advance.text.trim()) ?? 0;

  // نحسب المطلوب محليًا هنا حتى لا نعتمد على متغيّرات خارج النطاق
  final months     = _monthsInTerm(_term);               // إجمالي أشهر مدة العقد
  final mPerCycle  = _monthsPerCycle(_cycle);            // أشهر كل دفعة/قسط
  final perCycleCt = ((months / mPerCycle).ceil()).clamp(1, 1000) as int; // عدد الدفعات في المدة
  final monthlyVal = months > 0 ? (total / months) : 0.0;                 // قيمة الشهر الواحدة

  // تأمين الحدود
  final safeCycles    = cyclesInput.clamp(0, perCycleCt).toInt();
  final coveredMonths = safeCycles * mPerCycle;

  // نحول "عدد الدفعات" إلى مبلغ مكافئ ونخزّنه
  advPaid = (coveredMonths * monthlyVal).toDouble();
}



    if (isEdit) {
      final c = widget.existing!;
      if (c.propertyId != prop.id) {
        final oldProp = firstWhereOrNull(_properties.values, (e) => e.id == c.propertyId);
        if (oldProp != null) await _releaseProperty(oldProp);
        await _occupyProperty(prop);
        c.propertyId = prop.id;
      }

      final wasActiveBefore = c.isActiveNow;

      c.tenantId = _selectedTenant!.id;
      c.startDate = _dateOnly(_startDate!);
      c.endDate = _dateOnly(_endDate!);
      c.term = _term;
      c.paymentCycle = _cycle;
      c.currency = _currency;
      c.totalAmount = total;
      c.rentAmount = perCycleAmount;
      c.advanceMode = _advMode;
      c.advancePaid = advPaid;
      c.dailyCheckoutHour = checkoutHour;
      c.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      c.updatedAt = SaTimeLite.now();

      await c.save();

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

      if (!mounted) return;
      Navigator.of(context).pop(c);
    } else {
  // 1) احصل على الرقم التسلسلي قبل بناء العقد
  final serial = await _nextContractSerial();

  // 2) ابنِ العقد ومرّر serialNo
  final c = Contract(
    tenantId: _selectedTenant!.id,
    propertyId: prop.id,
    startDate: _dateOnly(_startDate!),
    endDate: _dateOnly(_endDate!),
    term: _term,
    paymentCycle: _cycle,
    rentAmount: perCycleAmount,
    totalAmount: total,
    currency: _currency,
    advanceMode: _advMode,
    advancePaid: advPaid,
    dailyCheckoutHour: checkoutHour,
    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    serialNo: serial, // ← هنا
  );

// إصدار فواتير المقدم تلقائيًا (إن وجدت) — دون التأثير على أقساط السداد
try {
  if (c.term != ContractTerm.daily &&
      c.advanceMode != AdvanceMode.none &&
      (c.advancePaid ?? 0) > 0) {

    final invBox = Hive.box<Invoice>(boxName(kInvoicesBox));
    final now = SaTimeLite.now();

    // تجهيز نص رقم العقد للعرض الجميل (سنة-تسلسل) إن وُجد
    String _displaySerial(String? s) {
      final v = (s ?? '').trim();
      if (v.isEmpty) return v;
      final parts = v.split('-');
      if (parts.length == 2) {
        final a = parts[0].trim();
        final b = parts[1].trim();
        bool isYear(String x) =>
            int.tryParse(x) != null && x.length == 4 && int.parse(x) >= 1900 && int.parse(x) <= 2100;
        if (!isYear(a) && isYear(b)) {
          final seq = a.padLeft(4, '0');
          return '$b-$seq';
        }
      }
      return v;
    }
    final serialDisplay = _displaySerial(c.serialNo);
    final serialLtr     = '\u200E${serialDisplay}\u200E';
    final baseNote      = serialDisplay.isNotEmpty ? 'سداد مقدم عقد رقم $serialLtr' : 'سداد مقدم عقد';

    if (c.advanceMode == AdvanceMode.deductFromTotal) {
      // حالة: "مقدم يخصم من الإجمالي" → فاتورة واحدة (مدفوعة) بقيمة المقدم وتاريخها بداية العقد
      final amount = (c.advancePaid ?? 0).toDouble();
      if (amount > 0) {
        final inv = Invoice(
          tenantId:   c.tenantId,
          contractId: c.id,
          propertyId: c.propertyId,
          issueDate:  now,
          dueDate:    _dateOnly(c.startDate), // تظهر في السجل كفاتورة مدفوعة مسبقًا
          amount:     amount,
          paidAmount: amount,  // مدفوعة بالكامل
          currency:   c.currency,
          note:       baseNote,
          paymentMethod: 'نقدًا',
          createdAt:  now,
          updatedAt:  now,
        );
// ترقيم عند الإنشاء: لجميع الفواتير غير الملغاة
if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
  inv.serialNo  = _nextInvoiceSerialForContracts(invBox);
  inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
}


        await invBox.put(inv.id, inv);
      }
    } else {
      // حالة: "يغطي أشهر معينة" → أنشئ فاتورة مدفوعة لكل قسط مغطّى (مرتّبة: الأقدم أسفل، الأحدث أعلى)
      final coveredMonths = _coveredMonthsByAdvance(c);       // أشهر مغطّاة
      final mpc           = _monthsPerCycle(c.paymentCycle);  // أشهر كل قسط
      final cyclesCovered = (coveredMonths / mpc).floor();    // عدد الأقساط المغطّاة
      if (cyclesCovered > 0) {
        var due = _dateOnly(c.startDate);
        final end = _dateOnly(c.endDate);
        for (int k = 0; k < cyclesCovered; k++) {
          if (due.isAfter(end)) break;

          // طابع زمني متزايد لضمان ترتيب الإدراج (الأقدم أسفل)
          final issuedAt = now.add(Duration(milliseconds: k));

          // تجنّب التكرار إن كانت هناك فاتورة مدفوعة لنفس استحقاق القسط
          if (!_paidForDue(c, due)) {
            final amount = c.rentAmount; // قيمة القسط القياسية
            final inv = Invoice(
              tenantId:   c.tenantId,
              contractId: c.id,
              propertyId: c.propertyId,
              issueDate:  issuedAt,              // كان: now
              dueDate:    _dateOnly(due),        // تاريخ استحقاق القسط المغطّى
              amount:     amount,
              paidAmount: amount,                // مدفوعة بالكامل
              currency:   c.currency,
              note:       baseNote,
              paymentMethod: 'نقدًا',
              createdAt:  issuedAt,              // كان: now
              updatedAt:  issuedAt,              // كان: now
            );
// ترقيم عند الإنشاء: لجميع الفواتير غير الملغاة
if ((inv.serialNo ?? '').isEmpty && inv.isCanceled != true) {
  inv.serialNo  = _nextInvoiceSerialForContracts(invBox);
  inv.updatedAt = SaTimeLite.now(); // أو KsaTime.now()
}


            await invBox.put(inv.id, inv);
          }

          // انتقل إلى استحقاق القسط التالي بحسب دورة السداد
          due = _addMonths(_dateOnly(due), mpc);
        }
      }
    }
  }
} catch (_) {
  // عدم تعطيل حفظ العقد عند أي خطأ في إصدار الفاتورة — نتجاهل بهدوء
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
    final all = _properties.values.where((e) => e.parentBuildingId == buildingId);
    final count = all.where((e) => e.occupiedUnits > 0).length;
    final building = firstWhereOrNull(_properties.values, (e) => e.id == buildingId);
    if (building != null) {
      building.occupiedUnits = count;
      await building.save();
    }
  }
}

/// شيت اختيار المستأجر
class _TenantPickerSheet extends StatefulWidget {
  @override
  State<_TenantPickerSheet> createState() => _TenantPickerSheetState();
}
class _TenantPickerSheetState extends State<_TenantPickerSheet> {
  Box<Tenant>   get _tenants   => Hive.box<Tenant>(boxName(kTenantsBox));
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم/الهوية/الجوال',
                  hintStyle: GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true, fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _tenants.listenable(),
                  builder: (context, Box<Tenant> b, _) {
                    var items = b.values.where((t) => !t.isArchived).toList();
                    if (_q.isNotEmpty) {
                      final q = _q.toLowerCase();
                      items = items.where((t) => t.fullName.toLowerCase().contains(q) || t.nationalId.toLowerCase().contains(q) || t.phone.toLowerCase().contains(q)).toList();
                    }
                    items.sort((a, c) => a.fullName.compareTo(c.fullName));

                    if (items.isEmpty) {
                      return Center(child: Text('لا يوجد مستأجرون', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)));
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => SizedBox(height: 6.h),
                      itemBuilder: (_, i) {
                        final t = items[i];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(t),
                          leading: const Icon(Icons.person, color: Colors.white),
                          title: Text(t.fullName, style: GoogleFonts.cairo(color: Colors.white)),
                          subtitle: Text('هوية: ${t.nationalId} • جوال: ${t.phone}', style: GoogleFonts.cairo(color: Colors.white70)),
                          trailing: t.isBlacklisted ? _chip('محظور', bg: const Color(0xFF7F1D1D)) : null,
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

/// شيت اختيار العقار/الوحدة المتاحة فقط
class _PropertyPickerSheet extends StatefulWidget {
  @override
  State<_PropertyPickerSheet> createState() => _PropertyPickerSheetState();
}
class _PropertyPickerSheetState extends State<_PropertyPickerSheet> {
  Box<Property> get _properties=> Hive.box<Property>(boxName(kPropertiesBox));
  String _q = '';
  bool _showUnits = true;
  bool _showWholeBuildings = true;
  bool _showStandalone = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم العقار/العنوان',
                  hintStyle: GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true, fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 8.h),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8.w, runSpacing: 8.h, crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: Text('الوحدات', style: GoogleFonts.cairo(color: Colors.white)),
                      selected: _showUnits,
                      onSelected: (v) => setState(() => _showUnits = v),
                      selectedColor: const Color(0xFF1F2937),
                      checkmarkColor: Colors.white,
                    ),
                    FilterChip(
                      label: Text('عمائر (كامل)', style: GoogleFonts.cairo(color: Colors.white)),
                      selected: _showWholeBuildings,
                      onSelected: (v) => setState(() => _showWholeBuildings = v),
                      selectedColor: const Color(0xFF1F2937),
                      checkmarkColor: Colors.white,
                    ),
                    FilterChip(
                      label: Text('عقارات مستقلة', style: GoogleFonts.cairo(color: Colors.white)),
                      selected: _showStandalone,
                      onSelected: (v) => setState(() => _showStandalone = v),
                      selectedColor: const Color(0xFF1F2937),
                      checkmarkColor: Colors.white,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _properties.listenable(),
                  builder: (context, Box<Property> b, _) {
                    var all = b.values.toList();

                    List<Property> available = all.where((p) {
                      if (p.parentBuildingId != null) {
                        return _showUnits && p.occupiedUnits == 0;
                      }
                      if (p.type == PropertyType.building) {
                        if (p.rentalMode == RentalMode.perUnit) return false;
                        return _showWholeBuildings && p.occupiedUnits == 0;
                      }
                      return _showStandalone && p.occupiedUnits == 0;
                    }).toList();

                    if (_q.isNotEmpty) {
                      final q = _q.toLowerCase();
                      available = available.where((p) => p.name.toLowerCase().contains(q) || p.address.toLowerCase().contains(q)).toList();
                    }
                    available.sort((a, c) => a.name.compareTo(c.name));

                    if (available.isEmpty) {
                      return Center(child: Text('لا توجد عناصر متاحة', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)));
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: available.length,
                      separatorBuilder: (_, __) => SizedBox(height: 6.h),
                      itemBuilder: (_, i) {
                        final p = available[i];
                        final isUnit = p.parentBuildingId != null;
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(p),
                          leading: const Icon(Icons.home_work_rounded, color: Colors.white),
                          title: Text(p.name, style: GoogleFonts.cairo(color: Colors.white)),
                          subtitle: Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.cairo(color: Colors.white70)),
                          trailing: _chip(isUnit ? 'وحدة' : (p.type == PropertyType.building ? 'عمارة (كامل)' : 'مستقل'), bg: const Color(0xFF334155)),
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

/// ============================================================================
/// مسارات جاهزة للإدراج في MaterialApp.routes
/// - '/contracts'    : شاشة العقود (تقبل openPropertyId أو openContractId)
/// - '/contracts/new': شاشة إضافة عقد (تقبل prefillPropertyId و/أو prefillTenantId)
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