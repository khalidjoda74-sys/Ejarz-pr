// lib/ui/notifications_screen.dart
// شاشة التنبيهات: تُولّد ديناميكيًا من العقود والفواتير والصيانة
// - التنبيهات لا تُخزَّن؛ تُستنبط لحظيًا من الصناديق.
// - يمكن للمستخدم حذف التنبيه بالسحب يمينًا؛ نُسجّل المحذوفات في Box<String> باسم notificationsDismissed.
// - الفئات:
//   • عقود: "قاربت على الانتهاء" (endDate خلال 7 أيام)، "منتهٍ" (endDate < اليوم)
//   • استحقاقات العقد: "مستحق اليوم" و"متأخر" حتى بدون وجود فواتير
//   • صيانة: "موعد بداية اليوم" (scheduledDate == اليوم ولم تُكمَّل)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:darvoo/data/services/user_scope.dart' as scope;

import '../data/services/user_scope.dart' show boxName;
import '../data/services/office_client_guard.dart'; // ✅ جديد


import 'contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle, AdvanceMode,
         ContractsScreen, ContractDetailsScreen;

import 'invoices_screen.dart' show Invoice;

import 'maintenance_screen.dart'
    show MaintenanceRequest, MaintenanceStatus, MaintenanceDetailsScreen;


import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;

import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';
import '../widgets/darvoo_app_bar.dart';



// ==============================
// المسارات
// ==============================
class NotificationsRoutes {
  static const String notifications = '/notifications';
  static Map<String, WidgetBuilder> routes() => {
        notifications: (_) => const NotificationsScreen(),
      };
}

// ==============================
// أنواع التنبيه
// ==============================
enum NotificationKind {
    contractStartedToday,
contractExpiring,
  contractEnded,
  contractDueSoon, 
  contractDueToday,
  contractDueOverdue,
  invoiceOverdue,
  maintenanceToday,
}

// ==============================
// Helpers مشتركة (Top-level) لمفاتيح الإخفاء
// ==============================

DateTime _dateOnlyGlobal(DateTime d) => DateTime(d.year, d.month, d.day);

String stableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  // الشكل المعتمد: anchor مؤرّخ day-only
  return '${k.name}:$id:${_dateOnlyGlobal(anchor).toIso8601String()}';
}

// دعم رجعي للمفاتيح القديمة (كانت تستخدم anchor بكامل الوقت)
String legacyStableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return '${k.name}:$id:${anchor.toIso8601String()}';
}

// مفتاح شامل (ALL) لنفس الكيان/اليوم بغض النظر عن نوع التنبيه
String anyStableKey({
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return 'ALL:' + id + ':' + _dateOnlyGlobal(anchor).toIso8601String();
}

// فاحص موحّد يُستخدم في الشاشة والعداد
bool isDismissed({
  required Box<String> dismissedBox,
  required NotificationKind kind,
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final kNew = stableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);
  final kOld = legacyStableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);

  // لا نستخدم المفتاح العام (ANY) حتى لا نمنع ظهور التنبيهات بحالة مختلفة
  // لنفس العقد أو الدفعة (مثلاً من "قارب" إلى "منتهي").
  return dismissedBox.containsKey(kNew) || dismissedBox.containsKey(kOld);
}


// ==============================
// نموذج التنبيه
// ==============================
class AppNotification {
  final NotificationKind kind;
  final String title;
  final String subtitle;
  final String? contractId;
  final String? invoiceId;
  final String? maintenanceId;

  /// للعرض (الأحدث زمنيًا أولًا)
  final DateTime sortKey;

  /// مرساة ثابتة لتكوين الهوية/الإخفاء
  final DateTime anchor;

  /// ترتيب الظهور الأول (أكبر = أحدث ظهورًا)
  final int appearOrder;

  AppNotification({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sortKey,
    required this.anchor,
    required this.appearOrder,
    this.contractId,
    this.invoiceId,
    this.maintenanceId,
  });
}

// ==============================
// مستودع ترتيب يظهر حتى بدون صندوق Hive
// ==============================
class _OrderStore {
  final Box<int>? _box;
  final Map<String, int> _mem = {};
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  _OrderStore._(this._box);

  static _OrderStore createSync(String logicalName) {
    final name = boxName(logicalName);
    try {
      final b = Hive.box<int>(name);
      return _OrderStore._(b);
    } catch (_) {
      // نحاول فتحه بالخلفية، ولو فشل يبقى الذاكرة المؤقتة شغالة بدون كراش
      try {
        Hive.openBox<int>(name);
      } catch (_) {}
      return _OrderStore._(null);
    }
  }

  Listenable listenable() => _box?.listenable() ?? _tick;

  int? get(String key) => _box?.get(key) ?? _mem[key];

  void put(String key, int value) {
    if (_box != null) {
      _box!.put(key, value);
    } else {
      _mem[key] = value;
      _tick.value++; // يوقظ الـ AnimatedBuilder
    }
  }

  int getCounter() {
    const ck = '__counter__';
    if (_box != null) return _box!.get(ck, defaultValue: 0) ?? 0;
    return _mem[ck] ?? 0;
  }

  int bumpCounter() {
    final next = getCounter() + 1;
    put('__counter__', next);
    return next;
  }
}

// ==============================
// Merged Listenable
// ==============================
class _MergedListenable extends ChangeNotifier {
  final List<Listenable> _sources;
  final List<VoidCallback> _removers = [];
  _MergedListenable(this._sources) {
    for (final s in _sources) {
      s.addListener(_onChange);
      _removers.add(() => s.removeListener(_onChange));
    }
  }
  void _onChange() => notifyListeners();
  @override
  void dispose() {
    for (final r in _removers) {
      try {
        r();
      } catch (_) {}
    }
    _removers.clear();
    super.dispose();
  }
}

// ==============================
// شاشة التنبيهات
// ==============================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  Box<Contract>? _contracts;
  Box<Invoice>? _invoices;
  Box<MaintenanceRequest>? _maintenance;
  Box<String>? _dismissed; // notificationsDismissed
   Box<String>? _stickyMaint; // notificationsStickyMaintenance

  Box<String>? _knownContracts; // notificationsKnownContracts
  Box<String>? _pinnedKinds; // notificationsPinnedKind
  late final _OrderStore _order; // notificationsOrder (أو ذاكرة)
  _MergedListenable? _merged;
  List<AppNotification> _items = const [];

  Future<void>? _ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });

    _order = _OrderStore.createSync('notificationsOrder');
    _ready = _ensureOpenAndWire();
  }

  Future<void> _ensureOpenAndWire() async {
    Future<void> openIfNeeded<T>(String logical) async {
      final real = boxName(logical);
      if (!Hive.isBoxOpen(real)) {
        await Hive.openBox<T>(real);
      }
    }

    await Future.wait([
      openIfNeeded<Contract>('contractsBox'),
      openIfNeeded<Invoice>('invoicesBox'),
      openIfNeeded<MaintenanceRequest>('maintenanceBox'),
      openIfNeeded<String>('notificationsDismissed'),
          openIfNeeded<String>('notificationsStickyMaintenance'),

      openIfNeeded<String>('notificationsKnownContracts'),
      openIfNeeded<String>('notificationsPinnedKind'),
      // اختياري: ترتيب الظهور
      openIfNeeded<int>('notificationsOrder'),
    ]);

    _contracts = Hive.box<Contract>(boxName('contractsBox'));
    _invoices = Hive.box<Invoice>(boxName('invoicesBox'));
    _maintenance = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
    _dismissed = Hive.box<String>(boxName('notificationsDismissed'));
      _stickyMaint = Hive.box<String>(boxName('notificationsStickyMaintenance'));

    _knownContracts = Hive.box<String>(boxName('notificationsKnownContracts'));
    _pinnedKinds = Hive.box<String>(boxName('notificationsPinnedKind'));
    _pinnedKinds = Hive.box<String>(boxName('notificationsPinnedKind'));

    _merged = _MergedListenable([
      _contracts!.listenable(),
      _invoices!.listenable(),
      _maintenance!.listenable(),
      _dismissed!.listenable(),
          if (_stickyMaint != null) _stickyMaint!.listenable(),

      if (_knownContracts != null) _knownContracts!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      if (_pinnedKinds != null) _pinnedKinds!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      _order.listenable(),
    ]);

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _merged?.dispose();
    super.dispose();
  }

  // ==============================
  // Helpers تواريخ/دفعات
  // ==============================
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _todayDateOnly() => _dateOnly(DateTime.now());
  int _daysBetween(DateTime a, DateTime b) => _dateOnly(b).difference(_dateOnly(a)).inDays;

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

  DateTime _addMonths(DateTime d, int months) {
    if (months == 0) return _dateOnly(d);
    final y0 = d.year, m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final lastDay = (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
    final safeDay = d.day > lastDay ? lastDay : d.day;
    return _dateOnly(DateTime(y, m, safeDay));
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

  DateTime? _firstDueAfterAdvance(Contract c) {
    if (c.term == ContractTerm.daily) return null;
    final start = _dateOnly(c.startDate), end = _dateOnly(c.endDate);
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      final termMonths = _monthsInTerm(c.term);
      if (covered >= termMonths) return null;
      final mpc = _monthsPerCycle(c.paymentCycle);
      final cyclesCovered = (covered / mpc).ceil();
      final first = _addMonths(start, cyclesCovered * mpc);
      if (!first.isBefore(start) && !first.isAfter(end)) return first;
      return null;
    }
    return start;
  }


  /// جميع تواريخ استحقاق الدفعات (أقساط العقد) بعد خصم الأشهر المغطاة بالمقدم
  /// نستخدمها لبناء تنبيهات "دفعة مستحقة / دفعة متأخرة" بحيث تظهر كل دفعة بتنبيه مستقل.
  List<DateTime> _allInstallmentDueDates(Contract c) {
    final List<DateTime> out = [];
    if (c.term == ContractTerm.daily) return out;

    DateTime start;
    DateTime end;
    try {
      start = _dateOnly(c.startDate);
      end = _dateOnly(c.endDate);
    } catch (_) {
      return out;
    }

    final termMonths = _monthsInTerm(c.term);
    if (termMonths <= 0) return out;
    final mpc = _monthsPerCycle(c.paymentCycle);
    if (mpc <= 0) return out;

    final totalCycles = (termMonths / mpc).ceil();

    int startCycle = 0;
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      if (covered >= termMonths) return out;
      final cyclesCovered = (covered / mpc).ceil();
      startCycle = cyclesCovered;
    }

    for (int i = startCycle; i < totalCycles; i++) {
      final due = _addMonths(start, i * mpc);
      final d0 = _dateOnly(due);
      if (d0.isBefore(start) || d0.isAfter(end)) continue;
      out.add(d0);
    }

    return out;
  }

  bool _isContractDueToday(Contract c) {
    if (c.term == ContractTerm.daily) return false;
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first) == _todayDateOnly();
  }

  bool _isContractOverdue(Contract c) {
    final today = _todayDateOnly();
    if (c.term == ContractTerm.daily) {
      return _dateOnly(c.endDate).isBefore(today);
    }
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first).isBefore(today);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  // قفل النوع: يثبت نوع التنبيه لأول ظهور لمرساة (id + anchor) حتى لا يتغير لاحقًا
  NotificationKind _lockKind(NotificationKind proposed, {String? cid, String? iid, String? mid, required DateTime anchor}) {
    // لم نعد نثبّت أول نوع يظهر؛ نسمح للتنبيه بأن يتغيّر
    // من "قارب على الانتهاء" إلى "منتهٍ" أو من "مستحق اليوم" إلى "متأخر"
    // بحسب حالة العقد أو استحقاقاته في كل إعادة توليد.
    return proposed;
  }


// تعقب أول مشاهدة للعقد لتفريق العقود المضافة حديثًا
  void _markContractSeen(String? cid) {
    if (cid == null || _knownContracts == null) return;
    if (!_knownContracts!.containsKey(cid)) {
      try { _knownContracts!.put(cid, _dateOnly(DateTime.now()).toIso8601String()); } catch (_) {}
    }
  }

  DateTime? _firstSeen(String? cid) {
    if (cid == null || _knownContracts == null) return null;
    final s = _knownContracts!.get(cid);
    if (s == null) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }

  bool _existedBeforeDate(String? cid, DateTime date) {
    final fs = _firstSeen(cid);
    if (fs == null) return false;
    return _dateOnly(fs).isBefore(_dateOnly(date));
  }


  // =====================================
  // أرقام العقود: تطبيع + عرض موثوق
  // =====================================

  // تغليف LTR لتثبيت اتجاه رقم مثل 2025-0003 داخل RTL
  String _ltr(Object? v) {
    final s = (v == null) ? '' : v.toString();
    if (s.isEmpty) return s;
    return '\u200E$s\u200E';
  }

  // تطبيع: لو الرقم مخزَّن كـ "0003-2025" نقلبه إلى "2025-0003"
  String _normalizeSerial(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return v;
    final parts = v.split('-');
    if (parts.length == 2) {
      final a = parts[0].trim();
      final b = parts[1].trim();
      bool isYear(String x) {
        final n = int.tryParse(x);
        return n != null && x.length == 4 && n >= 1900 && n <= 2100;
      }
      if (!isYear(a) && isYear(b)) {
        // seq-year => year-seq
        final seq = a.padLeft(4, '0');
        return '$b-$seq';
      }
    }
    return v;
  }

  // يعيد "رقم العقد" كما في بطاقة العقود (serialNo أولًا، ثم حقول بديلة)، بدون السقوط إلى id
  String _contractLabel(Contract c) {
    try {
      final d = c as dynamic;
      final cand = [
        d.serialNo,
        d.number,
        d.contractNumber,
        d.code,
        d.ref,
        d.displayNo,
        d.displayId,
        d.serial,
      ].firstWhere(
        (v) => v != null && v.toString().trim().isNotEmpty,
        orElse: () => null,
      );
      if (cand != null) {
        final t = _normalizeSerial(cand.toString().trim());
        return _ltr(t);
      }
    } catch (_) {}
    return '';
  }

  // استرجاع نص رقم العقد من الBox بالمعرف (لا نعرض الid الطويل إطلاقًا)
  String contractTextById(String? cid) {
    if (cid == null || _contracts == null) return '';
    try {
      final c = _contracts!.get(cid);
      if (c != null) {
        final s = _contractLabel(c);
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return '';
  }

  // ==============================
  // مفاتيح وترتيب ظهور
  // ==============================
  String _stableKey(NotificationKind k, {String? cid, String? iid, String? mid, required DateTime anchor}) {
    final id = cid ?? iid ?? mid ?? 'na';
    return '${k.name}:$id:${_dateOnly(anchor).toIso8601String()}';
  }

  int _ensureAppearOrder(String stableKeyStr) {
    final existing = _order.get(stableKeyStr);
    if (existing != null) return existing;
    final next = _order.bumpCounter();
    _order.put(stableKeyStr, next);
    return next;
  }

  // ==============================
  // توليد التنبيهات
  // ==============================
  List<AppNotification> _generate() {
    final today = _todayDateOnly();
    final out = <AppNotification>[];

  // --- عقود ---
  for (final c in _contracts!.values) {
    try {
      if ((c as dynamic).isArchived == true) continue;
      if ((c as dynamic).isTerminated == true) continue; // 👈 استبعاد العقود المنتهية مبكرًا
    } catch (_) {}
    final String? cid = (() {
      try {
        return (c as dynamic).id?.toString();
      } catch (_) {
        return null;
      }
    })();







      // عقد بدأ اليوم (فقط إن كان العقد موجودًا قبل اليوم ولم يكن مضافًا حديثًا)
      DateTime? _start;
      try { _start = (c as dynamic).startDate as DateTime?; } catch (_) {}
      if (_start != null) {
        final d0 = _dateOnly(_start!);
if (d0 == today && _existedBeforeDate(cid, d0)) {
  final anchor = d0;
  final skey = _stableKey(NotificationKind.contractStartedToday, cid: cid, anchor: anchor);
  final order = _ensureAppearOrder(skey);
  out.add(AppNotification(
    kind: NotificationKind.contractStartedToday,
    title: 'لديك عقد بدأ اليوم',
    subtitle: 'تاريخ البداية ${_fmt(_start!)}',
    sortKey: today,
    anchor: anchor,
    appearOrder: order,
    contractId: cid,
  ));
        }
      }
      // سجل "أول مشاهدة" لهذا العقد
      _markContractSeen(cid);

      // اجلب رقم العقد للعرض (بدون السقوط إلى id)
      final _label = _contractLabel(c);
      final _contractText = _label.isNotEmpty ? _label : 'بدون رقم';

      DateTime? end;
      try {
        end = (c as dynamic).endDate as DateTime?;
      } catch (_) {}
      if (end != null) {
        final ended = _dateOnly(end).isBefore(today);
        final daysToEnd = _daysBetween(today, end);

        if (ended) {
          final anchor = _dateOnly(end);
          final proposed = NotificationKind.contractEnded;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: finalKind,
            title: 'لديك عقد منتهي',
            subtitle: 'انتهى بتاريخ ${_fmt(end)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
} else if (daysToEnd >= 0 && daysToEnd <= 7) {
          final anchor = _dateOnly(end);
          final proposed = NotificationKind.contractExpiring;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: finalKind,
            title: 'لديك عقد قارب على الانتهاء',
            subtitle: 'ينتهي بتاريخ ${_fmt(end)}',
            sortKey: today,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
}
      }

      // استحقاقات عقد: نبني تنبيه مستقل لكل دفعة (قسط) مستحقة أو متأخرة
      try {
        final Contract cObj = c as Contract;
        if (cObj.term != ContractTerm.daily) {
          final dues = _allInstallmentDueDates(cObj);
         for (final due in dues) {
  final delta = _daysBetween(due, today); // اليوم - تاريخ الاستحقاق
  final daysAhead = -delta;               // كم يوم باقي على الاستحقاق (موجب = في المستقبل)

  // تجاهل الدفعات البعيدة جداً (أكثر من 7 أيام قبل الاستحقاق)
  if (delta < 0 && daysAhead > 7) continue;

  final anchor = _dateOnly(due);
  NotificationKind kind;
  String title;
  String subtitle;

  if (delta < 0) {
    // دفعة قريبة (لم يحن موعدها بعد لكن خلال 7 أيام)
    kind = NotificationKind.contractDueSoon;
    title = 'لديك دفعة قاربت ';
    subtitle = 'تاريخ الاستحقاق ${_fmt(due)}';
  } else if (delta == 0) {
    // دفعة مستحقة اليوم
    kind = NotificationKind.contractDueToday;
    title = 'لديك دفعة مستحقة اليوم';
    subtitle = 'تاريخ الاستحقاق ${_fmt(due)}';
  } else {
    // دفعة متأخرة
    kind = NotificationKind.contractDueOverdue;
    title = 'لديك دفعة متأخرة';
    subtitle = 'تاريخ الاستحقاق ${_fmt(due)}';
  }

  final skey = _stableKey(kind, cid: cid, anchor: anchor);
  final order = _ensureAppearOrder(skey);
  out.add(AppNotification(
    kind: kind,
    title: title,
    subtitle: subtitle,
    sortKey: anchor,
    anchor: anchor,
    appearOrder: order,
    contractId: cid,
  ));
}

        }
      } catch (_) {}
      _markContractSeen(cid);
      }


// --- فواتير ---
    for (final inv in _invoices!.values) {
      try {
        if ((inv as dynamic).isArchived == true) continue;
        final isPaid = (inv as dynamic).isPaid == true;
        if (isPaid) continue;
        final due = (inv as dynamic).dueDate as DateTime?;
        final iid = (inv as dynamic).id?.toString();
        final cid = (inv as dynamic).contractId?.toString();
        if (due == null) continue;

        final delta = _daysBetween(due, today);
        final anchor = _dateOnly(due);
        final skey = _stableKey(NotificationKind.invoiceOverdue, iid: iid, anchor: anchor);
        final order = _ensureAppearOrder(skey);

        // ابنِ العنوان الفرعي بدون تداخل سلاسل لنتجنب أخطاء التجميع
        String _buildInvoiceSubtitle(String statusText) {
          final cText = contractTextById(cid);
          String s = 'فاتورة ${_ltr(iid)}';
          if (cText.isNotEmpty) {
            s += ' لعقد $cText';
          }
          s += ' $statusText (${_fmt(due)})';
          return s;
        }

        if (delta == 0) {
          out.add(AppNotification(
            kind: NotificationKind.invoiceOverdue,
            title: delta == 0 ? 'فاتورة مستحقة اليوم' : 'فاتورة متأخرة',
            subtitle: 'تاريخ الاستحقاق ${_fmt(due)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            invoiceId: iid,
            contractId: cid,
          ));
} else if (delta > 0) {
          out.add(AppNotification(
            kind: NotificationKind.invoiceOverdue,
            title: 'فاتورة متأخرة',
            subtitle: 'تاريخ الاستحقاق ${_fmt(due)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            invoiceId: iid,
            contractId: cid,
          ));
        }
      } catch (_) {}
    }

    // --- صيانة ---
   // --- صيانة ---
for (final m in _maintenance!.values) {
  try {
    if ((m as dynamic).isArchived == true) continue;
    final s = (m as dynamic).scheduledDate as DateTime?;
    final mid = (m as dynamic).id?.toString();
    if (s == null) continue;

    final isToday = _dateOnly(s) == today;

    // مرساة مثبتة لكل طلب صيانة
    final midKey = mid ?? 'na';
    final pinnedIso = _stickyMaint?.get(midKey);
    final DateTime? pinnedAnchor = pinnedIso != null ? DateTime.tryParse(pinnedIso) : null;

    // أول يوم يظهر فيه (اليوم): نثبّت المرساة
    if (isToday && pinnedAnchor == null) {
      try { _stickyMaint?.put(midKey, _dateOnly(s).toIso8601String()); } catch (_) {}
    }

    // نعرض التنبيه إن كان اليوم موعده أو تم تثبيته سابقًا
    final DateTime anchor = pinnedAnchor ?? _dateOnly(s);
    final bool shouldShow = isToday || pinnedAnchor != null;

    if (shouldShow) {
      final skey = _stableKey(NotificationKind.maintenanceToday, mid: mid, anchor: anchor);
      final order = _ensureAppearOrder(skey);
      out.add(AppNotification(
        kind: NotificationKind.maintenanceToday,
        title: 'لديك طلب صيانة موعده اليوم',
        subtitle: 'التاريخ: ${_fmt(anchor)}', // ثابت حسب المرساة
        sortKey: anchor,
        anchor: anchor,
        appearOrder: order,
        maintenanceId: mid,
      ));
    }
  } catch (_) {}
}


    // فرز نهائي: (1) sortKey تنازلي ثم (2) appearOrder تنازلي
    out.sort((a, b) {
      final c1 = b.sortKey.compareTo(a.sortKey);
      if (c1 != 0) return c1;
      return b.appearOrder.compareTo(a.appearOrder);
    });

    return out;
  }

  (IconData, Color) _iconOf(NotificationKind k, BuildContext context) {
    switch (k) {
      case NotificationKind.contractExpiring:
        return (Icons.hourglass_top_rounded, Colors.amber.shade700);
      case NotificationKind.contractEnded:
        return (Icons.event_busy_rounded, Colors.blueGrey);
      case NotificationKind.contractStartedToday:
        return (Icons.play_circle_fill_rounded, Colors.green.shade600);
      case NotificationKind.contractDueSoon:
        return (Icons.event_available_rounded, Colors.teal.shade600);
      case NotificationKind.contractDueToday:
        return (Icons.event_available_rounded, Colors.teal.shade600);
      case NotificationKind.contractDueOverdue:
        return (Icons.schedule_rounded, Colors.orange.shade700);
      case NotificationKind.invoiceOverdue:
        return (Icons.warning_rounded, Colors.red.shade600);
      case NotificationKind.maintenanceToday:
        return (Icons.build_circle_rounded, Theme.of(context).colorScheme.primary);
    }
  }

  String _dismissKey(AppNotification n) =>
      _stableKey(n.kind, cid: n.contractId, iid: n.invoiceId, mid: n.maintenanceId, anchor: n.anchor);

  
  String _baseDismissKey(AppNotification n) =>
      anyStableKey(cid: n.contractId, iid: n.invoiceId, mid: n.maintenanceId, anchor: n.anchor);

  Future<void> _dismissAll(AppNotification n) async {
    final dis = _dismissed;
    if (dis == null) return;
    try { await dis.put(_dismissKey(n), '1'); } catch (_) {}
    // لا نسجّل بعد الآن المفتاح العام (ALL) حتى نسمح بظهور تنبيه جديد
    // عند تغيّر حالة نفس العقد أو الدفعة (مثلاً من "قارب" إلى "منتهي").
  }


  void _open(AppNotification n) {
    switch (n.kind) {
      // 🔹 تنبيهات العقود → افتح شاشة تفاصيل العقد مباشرة
      case NotificationKind.contractExpiring:
      case NotificationKind.contractEnded:
      case NotificationKind.contractDueSoon:
      case NotificationKind.contractDueToday:
      case NotificationKind.contractDueOverdue:
      case NotificationKind.contractStartedToday:
        {
          final cid = n.contractId;
          if (cid != null && cid.isNotEmpty && _contracts != null) {
            Contract? target;
            for (final c in _contracts!.values) {
              if (c.id == cid) {
                target = c;
                break;
              }
            }
            if (target != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContractDetailsScreen(contract: target!),
                ),
              );
              break; // ✅ لا نكمل إلى الـ fallback
            }
          }

          // احتياط: لو ما لقينا العقد لأي سبب، نرجع للسلوك القديم
          Navigator.of(context).pushNamed(
            '/contracts',
            arguments: {'openContractId': n.contractId},
          );
          break;
        }

      // 🔹 تنبيهات الفواتير: نتركها كما هي (ما عندنا الآن شاشة تفاصيل مفصولة)
      case NotificationKind.invoiceOverdue:
        Navigator.of(context).pushNamed(
          '/invoices',
          arguments: {'openInvoiceId': n.invoiceId},
        );
        break;

      // 🔹 تنبيه صيانة اليوم → افتح تفاصيل طلب الصيانة مباشرة
      case NotificationKind.maintenanceToday:
        {
          final mid = n.maintenanceId;
          if (mid != null && mid.isNotEmpty && _maintenance != null) {
            MaintenanceRequest? item;
            for (final m in _maintenance!.values) {
              if (m.id == mid) {
                item = m;
                break;
              }
            }
            if (item != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MaintenanceDetailsScreen(item: item!),
                ),
              );
              break; // ✅ لا نكمل إلى الـ fallback
            }
          }

          // احتياط: لو ما لقينا الطلب لأي سبب، نرجع للسلوك القديم
          Navigator.of(context).pushNamed(
            '/maintenance',
            arguments: {'openMaintenanceId': n.maintenanceId},
          );
          break;
        }
    }
  }


  @override
  Widget build(BuildContext context) {
    // لو لسه ما تهيأت الصناديق، اعرض Loader ريثما تجهز
    if (_merged == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            color: const Color(0xFFE5E7EB),

            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
              backgroundColor: const Color(0xFF0B1220), // أو const Color(0xFF0B1220) لو تبيه أسود ثابت
                elevation: 0,
                centerTitle: true,
automaticallyImplyLeading: false,
leading: darvooLeading(context, iconColor: Colors.white),

                title: Text(
                  'التنبيهات',
                  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),

              // ✅ drawer متموضع بين AppBar و BottomNav
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

              body: const Center(child: CircularProgressIndicator()),

              // ✅ BottomNav مضافة
              bottomNavigationBar: Container(
              color: const Color(0xFF0B1220),
              child: AppBottomNav(
                key: _bottomNavKey,
                currentIndex: 2,
                onTap: _handleBottomTap,
              ),
            ),
          ),
        ),
      ));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: const Color(0xFFE5E7EB),

          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: const Color(0xFF0B1220), // أو const Color(0xFF0B1220) لو تبيه أسود ثابت
              elevation: 0,
              centerTitle: true,
automaticallyImplyLeading: false,
leading: darvooLeading(context, iconColor: Colors.white),

              title: Text(
                'التنبيهات',
                style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),

            // ✅ drawer متموضع بين AppBar و BottomNav
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

            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: AnimatedBuilder(
                animation: _merged!,
                builder: (context, _) {
                  _items = _generate();

                  // استثناء المحذوف (دعم جديد + رجعي)
                  final visible = _items
                      .where((n) => !isDismissed(
                            dismissedBox: _dismissed!,
                            kind: n.kind,
                            cid: n.contractId,
                            iid: n.invoiceId,
                            mid: n.maintenanceId,
                            anchor: n.anchor,
                          ))
                      .toList();

                  if (visible.isEmpty) return _EmptyState();

                  return ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, i) {
                      final n = visible[i];
                      final (icon, color) = _iconOf(n.kind, context);
                      final k = _dismissKey(n); // نكتب بالمفتاح الجديد

                      return Dismissible(
                        key: ValueKey(k),
                        direction: DismissDirection.startToEnd,
                        onDismissed: (_) async {
  if (await OfficeClientGuard.blockIfOfficeClient(context)) return;
  await _dismissAll(n);
},

                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(18.r),

                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Text('تم إخفاء التنبيه',
                                  style: GoogleFonts.cairo(
                                      color: Colors.green.shade700, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        child: _NotifCard(
                          icon: icon,
                          color: color,
                          title: n.title,
                          subtitle: n.subtitle,
                          onTap: () => _open(n),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ✅ BottomNav مضافة
            bottomNavigationBar: Container(
              color: const Color(0xFF0B1220),
              child: AppBottomNav(
              key: _bottomNavKey,
              currentIndex: 2,
              onTap: _handleBottomTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ دالة التنقل السفلي داخل الكلاس
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }
}

// ==============================
// Widgets مساعدة
// ==============================
class _NotifCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NotifCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });


  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.r),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.white,


          borderRadius: BorderRadius.circular(18.r),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: color, size: 26.w),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_off_rounded,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'لا توجد تنبيهات حالياً',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================
// عداد حي لعدد التنبيهات (لاستخدامه في الرئيسية)
// ==============================
class NotificationsCounter extends StatefulWidget {
  final Widget Function(int count) builder;
  const NotificationsCounter({super.key, required this.builder});

  @override
  State<NotificationsCounter> createState() => _NotificationsCounterState();
}

class _NotificationsCounterState extends State<NotificationsCounter> {
  Box<Contract>? _contracts;
  Box<Invoice>? _invoices;
  Box<MaintenanceRequest>? _maintenance;
  Box<String>? _dismissed;
  Box<String>? _knownContracts; // notificationsKnownContracts
  Box<String>? _pinnedKinds; // notificationsPinnedKind
  late final _OrderStore _order;
  _MergedListenable? _merged;
  // آخر عدد تم رفعه للـ Cloud حتى لا نكرر الكتابة بلا داعي
  int _lastPushedCount = -1;

    Future<void> _pushCountToCloud(int count) async {
    // لو لم يتغيّر العدد لا نكتب ثانية
    if (count == _lastPushedCount) return;
    _lastPushedCount = count;

    try {
      // 👈 نستخدم الـ effectiveUid من user_scope حتى في وضع "عميل مكتب"
      final uid = scope.effectiveUid();
      if (uid == 'guest') return; // لو ما في مستخدم فعّال نتجاهل

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
        {
          'notificationsCount': count,
          'notificationsUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // أوفلاين / خطأ صلاحيات ➜ نتجاهل تمامًا حتى لا يتأثر الـ UI
    }
  }



  Future<void>? _ready;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _today() => _dateOnly(DateTime.now());
  int _daysBetween(DateTime a, DateTime b) => _dateOnly(b).difference(_dateOnly(a)).inDays;

  @override
  void initState() {
    super.initState();
    _order = _OrderStore.createSync('notificationsOrder');
    _ready = _ensureOpenAndWire();
  }

  Future<void> _ensureOpenAndWire() async {
    Future<void> openIfNeeded<T>(String logical) async {
      final real = boxName(logical);
      if (!Hive.isBoxOpen(real)) {
        await Hive.openBox<T>(real);
      }
    }

    await Future.wait([
      openIfNeeded<Contract>('contractsBox'),
      openIfNeeded<Invoice>('invoicesBox'),
      openIfNeeded<MaintenanceRequest>('maintenanceBox'),
      openIfNeeded<String>('notificationsDismissed'),
          openIfNeeded<String>('notificationsStickyMaintenance'),

      openIfNeeded<String>('notificationsPinnedKind'),
      openIfNeeded<String>('notificationsKnownContracts'),
      openIfNeeded<int>('notificationsOrder'),
    ]);

    _contracts = Hive.box<Contract>(boxName('contractsBox'));
    _invoices = Hive.box<Invoice>(boxName('invoicesBox'));
    _maintenance = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
    _dismissed = Hive.box<String>(boxName('notificationsDismissed'));

    _merged = _MergedListenable([
      _contracts!.listenable(),
      _invoices!.listenable(),
      _maintenance!.listenable(),
      _dismissed!.listenable(),
      if (_pinnedKinds != null) _pinnedKinds!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      _order.listenable(),
    ]);

    if (mounted) setState(() {});
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

  DateTime _addMonths(DateTime d, int months) {
    if (months == 0) return _dateOnly(d);
    final y0 = d.year, m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final lastDay = (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
    final safeDay = d.day > lastDay ? lastDay : d.day;
    return _dateOnly(DateTime(y, m, safeDay));
  

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

  DateTime? _firstDueAfterAdvance(Contract c) {
    if (c.term == ContractTerm.daily) return null;
    final start = _dateOnly(c.startDate), end = _dateOnly(c.endDate);
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      final termMonths = _monthsInTerm(c.term);
      if (covered >= termMonths) return null;
      final mpc = _monthsPerCycle(c.paymentCycle);
      final cyclesCovered = (covered / mpc).ceil();
      final first = _addMonths(start, cyclesCovered * mpc);
      if (!first.isBefore(start) && !first.isAfter(end)) return first;
      return null;
    }
    return start;
  }


  /// جميع تواريخ استحقاق الدفعات (أقساط العقد) بعد خصم الأشهر المغطاة بالمقدم
  /// نستخدمها لبناء تنبيهات "دفعة مستحقة / دفعة متأخرة" بحيث تظهر كل دفعة بتنبيه مستقل.
  List<DateTime> _allInstallmentDueDates(Contract c) {
    final List<DateTime> out = [];
    if (c.term == ContractTerm.daily) return out;

    DateTime start;
    DateTime end;
    try {
      start = _dateOnly(c.startDate);
      end = _dateOnly(c.endDate);
    } catch (_) {
      return out;
    }

    final termMonths = _monthsInTerm(c.term);
    if (termMonths <= 0) return out;
    final mpc = _monthsPerCycle(c.paymentCycle);
    if (mpc <= 0) return out;

    final totalCycles = (termMonths / mpc).ceil();

    int startCycle = 0;
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      if (covered >= termMonths) return out;
      final cyclesCovered = (covered / mpc).ceil();
      startCycle = cyclesCovered;
    }

    for (int i = startCycle; i < totalCycles; i++) {
      final due = _addMonths(start, i * mpc);
      final d0 = _dateOnly(due);
      if (d0.isBefore(start) || d0.isAfter(end)) continue;
      out.add(d0);
    }

    return out;
  }

  bool _isDueToday(Contract c) {
    if (c.term == ContractTerm.daily) return false;
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first) == _today();
  }

  bool _isOverdue(Contract c) {
    if (c.term == ContractTerm.daily) return _dateOnly(c.endDate).isBefore(_today());
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first).isBefore(_today());
  }

  
  // قفل النوع في العداد
  NotificationKind _lockKind(NotificationKind proposed, {String? cid, String? iid, String? mid, required DateTime anchor}) {
    // نفس منطق الشاشة الرئيسية: لا نثبّت النوع في العداد أيضًا
    // حتى يعكس العدّاد الحالة الحالية (قارب / منتهٍ / مستحق / متأخر).
    return proposed;
  }


void _markContractSeen(String? cid) {
    if (cid == null || _knownContracts == null) return;
    if (!_knownContracts!.containsKey(cid)) {
      try { _knownContracts!.put(cid, _dateOnly(DateTime.now()).toIso8601String()); } catch (_) {}
    }
  }

  DateTime? _firstSeen(String? cid) {
    if (cid == null || _knownContracts == null) return null;
    final s = _knownContracts!.get(cid);
    if (s == null) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }

  bool _existedBeforeDate(String? cid, DateTime date) {
    final fs = _firstSeen(cid);
    if (fs == null) return false;
    return _dateOnly(fs).isBefore(_dateOnly(date));
  }
String _stableKey(NotificationKind k, {String? cid, String? iid, String? mid, required DateTime anchor}) {
    final id = cid ?? iid ?? mid ?? 'na';
    return '${k.name}:$id:${_dateOnly(anchor).toIso8601String()}';
  }

  List<AppNotification> _gen() {
    final today = _today();
    final out = <AppNotification>[];

    for (final c in _contracts!.values) {
      try {
        if ((c as dynamic).isArchived == true) continue;
        if ((c as dynamic).isTerminated == true) continue; // 👈 نفس الشرط هنا
      } catch (_) {}
      final String? cid = (() {
        try {
          return (c as dynamic).id?.toString();
        } catch (_) {
          return null;
        }
      })();







      // عقد بدأ اليوم (غير مضاف حديثًا)
      DateTime? _start;
      try { _start = (c as dynamic).startDate as DateTime?; } catch (_) {}
      if (_start != null) {
        final d0 = _dateOnly(_start!);
        if (d0 == _today() && _existedBeforeDate(cid, d0)) {
          final anchor = d0;
          final proposed = NotificationKind.contractStartedToday;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: _today(),
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }
      _markContractSeen(cid);

      DateTime? end;
      try {
        end = (c as dynamic).endDate as DateTime?;
      } catch (_) {}
      if (end != null) {
        final ended = _dateOnly(end).isBefore(today);
        final daysToEnd = _daysBetween(today, end);
        if (ended) {
          final anchor = _dateOnly(end);
          final proposed = NotificationKind.contractEnded;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        } else if (daysToEnd >= 0 && daysToEnd <= 7) {
          final anchor = _dateOnly(end);
          final proposed = NotificationKind.contractExpiring;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: today,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }

            try {
        final Contract cObj = c as Contract;
        if (cObj.term != ContractTerm.daily) {
          final dues = _allInstallmentDueDates(cObj);
          for (final due in dues) {
            // نفس منطق الشاشة الكاملة تقريبًا
            final delta = _daysBetween(due, today); // اليوم - تاريخ الاستحقاق
            final daysAhead = -delta;               // كم يوم باقي على الاستحقاق (لو موجب = في المستقبل)

            // تجاهل الدفعات البعيدة جدًا (أكثر من 7 أيام قبل الاستحقاق)
            if (delta < 0 && daysAhead > 7) continue;

            final anchor = _dateOnly(due);
            NotificationKind kind;

            if (delta < 0) {
              // دفعة "قاربت" (قريبة من الاستحقاق)
              kind = NotificationKind.contractDueSoon;
            } else if (delta == 0) {
              // دفعة مستحقة اليوم
              kind = NotificationKind.contractDueToday;
            } else {
              // دفعة متأخرة
              kind = NotificationKind.contractDueOverdue;
            }

            final proposed = kind;
            final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
            final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
            final order = _order.get(skey) ?? 0;

            out.add(AppNotification(
              kind: finalKind,
              title: '',
              subtitle: '',
              sortKey: anchor,
              anchor: anchor,
              appearOrder: order,
              contractId: cid,
            ));
          }
        }
      } catch (_) {}

      _markContractSeen(cid);
    }

    for (final inv in _invoices!.values) {
      try {
        if ((inv as dynamic).isArchived == true) continue;
        if ((inv as dynamic).isPaid == true) continue;
        final due = (inv as dynamic).dueDate as DateTime?;
        if (due == null) continue;
        final iid = (inv as dynamic).id?.toString();
        final anchor = _dateOnly(due);
        final skey = _stableKey(NotificationKind.invoiceOverdue, iid: iid, anchor: anchor);
        final order = _order.get(skey) ?? 0;
        out.add(AppNotification(
          kind: NotificationKind.invoiceOverdue,
          title: '',
          subtitle: '',
          sortKey: anchor,
          anchor: anchor,
          appearOrder: order,
          invoiceId: iid,
        ));
      } catch (_) {}
    }

    for (final m in _maintenance!.values) {
      try {
        if ((m as dynamic).isArchived == true) continue;
        final s = (m as dynamic).scheduledDate as DateTime?;
        final st = (m as dynamic).status as MaintenanceStatus?;
        if (s == null) continue;
        if (_dateOnly(s) != today) continue;
        final mid = (m as dynamic).id?.toString();
        final anchor = _dateOnly(s);
        final skey = _stableKey(NotificationKind.maintenanceToday, mid: mid, anchor: anchor);
        final order = _order.get(skey) ?? 0;
        out.add(AppNotification(
          kind: NotificationKind.maintenanceToday,
          title: '',
          subtitle: '',
          sortKey: anchor,
          anchor: anchor,
          appearOrder: order,
          maintenanceId: mid,
        ));
      } catch (_) {}
    }

    out.sort((a, b) {
      final c1 = b.sortKey.compareTo(a.sortKey);
      if (c1 != 0) return c1;
      return b.appearOrder.compareTo(a.appearOrder);
    });
    return out;
  }

   @override
  Widget build(BuildContext context) {
    // لو لسه ما تهيأت الصناديق، اعرض 0 بدل رمية خطأ
    if (_merged == null) {
      return widget.builder(0);
    }
    return AnimatedBuilder(
      animation: _merged!,
      builder: (context, _) {
        final all = _gen();
        final visibleCount = all
            .where((n) => !isDismissed(
                  dismissedBox: _dismissed!,
                  kind: n.kind,
                  cid: n.contractId,
                  iid: n.invoiceId,
                  mid: n.maintenanceId,
                  anchor: n.anchor,
                ))
            .length;

        // 🔁 مزامنة العدد مع Cloud Firestore (يُستخدم في شاشة المكتب)
        _pushCountToCloud(visibleCount);

        return widget.builder(visibleCount);
      },
    );
  }
}
