// lib/ui/notifications_bg.dart
// تشغيل التنبيهات كإشعارات نظام منطقياً (محلياً) سواء foreground أو من WorkManager.
//
// يعتمد على نفس قواعد NotificationsScreen، ويستخدم نفس مفاتيح الإخفاء.
// يمنع التكرار عبر صندوق notificationsPushed.
//
// ملاحظات:
// - يجب أن تكون Adapters مسجّلة قبل فتح الصناديق (أنت مسجّلها في main).
// - في عزل الخلفية (WorkManager) نعمل initialize للـ FlutterLocalNotificationsPlugin محلياً.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/services/user_scope.dart' show boxName;
import '../ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle, AdvanceMode;
import '../ui/invoices_screen.dart' show Invoice;
import '../ui/maintenance_screen.dart'
    show MaintenanceRequest, MaintenanceStatus;

// ===== مفاتيح وأدوات تاريخ (مطابقة لمنطق الشاشة) =====
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _stableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return '${k.name}:$id:${_dateOnly(anchor).toIso8601String()}';
}

// دعم رجعي (كما بالشاشة)
String _legacyStableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return '${k.name}:$id:${anchor.toIso8601String()}';
}

bool _isDismissed({
  required Box<String> dismissedBox,
  required NotificationKind kind,
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final kNew = _stableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);
  final kOld = _legacyStableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);
  return dismissedBox.containsKey(kNew) || dismissedBox.containsKey(kOld);
}

// ===== نسخة مصغرة من أنواع التنبيه (نفس enum المستخدم في الشاشة) =====
enum NotificationKind {
  contractExpiring,
  contractEnded,
  contractDueToday,
  contractDueOverdue,
  invoiceOverdue,
  maintenanceToday,
}

// ===== كائن الإشعار المنطقي =====
class _AppNotificationLite {
  final NotificationKind kind;
  final String title;
  final String body;
  final String? contractId;
  final String? invoiceId;
  final String? maintenanceId;
  final DateTime anchor; // لمفتاح مستقر

  _AppNotificationLite({
    required this.kind,
    required this.title,
    required this.body,
    required this.anchor,
    this.contractId,
    this.invoiceId,
    this.maintenanceId,
  });
}

// ===== قنوات إشعار محلية =====
const AndroidNotificationChannel _dailyChannel = AndroidNotificationChannel(
  'daily_local',
  'التنبيهات المحلية اليومية',
  description: 'إشعارات منطقية من التطبيق (عقود/فواتير/صيانة).',
  importance: Importance.high,
);

class NotificationsBg {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  static Future<void> _ensureLocalInit() async {
    if (_inited) return;
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings();
    const init = InitializationSettings(android: initAndroid, iOS: initIOS);
    await _local.initialize(init);
    // إنشاء القناة على أندرويد
    final androidImpl =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_dailyChannel);
    _inited = true;
  }

  // مولد الإشعارات المنطقية (مبسّط)
  static List<_AppNotificationLite> _generate(
    Box<Contract> contracts,
    Box<Invoice> invoices,
    Box<MaintenanceRequest> maintenance,
  ) {
    final List<_AppNotificationLite> out = [];
    final today = _dateOnly(DateTime.now());

    // Helpers من الشاشة (نسخ مبسط)
    int monthsPerCycle(PaymentCycle c) {
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

    int monthsInTerm(ContractTerm t) {
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

    DateTime addMonths(DateTime d, int months) {
      if (months == 0) return _dateOnly(d);
      final y0 = d.year, m0 = d.month;
      final totalM = m0 - 1 + months;
      final y = y0 + totalM ~/ 12;
      final m = totalM % 12 + 1;
      final lastDay = (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
      final safeDay = d.day > lastDay ? lastDay : d.day;
      return _dateOnly(DateTime(y, m, safeDay));
    }

    int coveredMonthsByAdvance(Contract c) {
      if (c.advanceMode != AdvanceMode.coverMonths) return 0;
      if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
      final months = monthsInTerm(c.term);
      if (months <= 0) return 0;
      final monthlyValue = c.totalAmount / months;
      final covered = ((c.advancePaid ?? 0) / monthlyValue).floor();
      return covered.clamp(0, months);
    }

    DateTime? firstDueAfterAdvance(Contract c) {
      if (c.term == ContractTerm.daily) return null;
      final start = _dateOnly(c.startDate), end = _dateOnly(c.endDate);
      if (c.advanceMode == AdvanceMode.coverMonths) {
        final covered = coveredMonthsByAdvance(c);
        final termMonths = monthsInTerm(c.term);
        if (covered >= termMonths) return null;
        final mpc = monthsPerCycle(c.paymentCycle);
        final cyclesCovered = (covered / mpc).ceil();
        final first = addMonths(start, cyclesCovered * mpc);
        if (!first.isBefore(start) && !first.isAfter(end)) return first;
        return null;
      }
      return start;
    }

    bool isContractDueToday(Contract c) {
      if (c.term == ContractTerm.daily) return false;
      if ((c as dynamic).isTerminated == true) return false;
      final first = firstDueAfterAdvance(c);
      if (first == null) return false;
      return _dateOnly(first) == today;
    }

    bool isContractOverdue(Contract c) {
      if ((c as dynamic).isTerminated == true) return false;
      if (c.term == ContractTerm.daily) {
        return _dateOnly(c.endDate).isBefore(today);
      }
      final first = firstDueAfterAdvance(c);
      if (first == null) return false;
      return _dateOnly(first).isBefore(today);
    }

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    int daysBetween(DateTime a, DateTime b) => _dateOnly(b).difference(_dateOnly(a)).inDays;

    // عقود
    for (final c in contracts.values) {
      try {
        if ((c as dynamic).isArchived == true) continue;
      } catch (_) {}
      String? cid;
      try {
        cid = (c as dynamic).id?.toString();
      } catch (_) {}

      DateTime? end;
      try {
        end = (c as dynamic).endDate as DateTime?;
      } catch (_) {}
      if (end != null) {
        final ended = _dateOnly(end).isBefore(today);
        final d2e = daysBetween(today, end);

        if (ended) {
          final anchor = _dateOnly(end);
          out.add(_AppNotificationLite(
            kind: NotificationKind.contractEnded,
            title: 'عقد منتهٍ',
            body: 'العقد ${cid ?? ''} انتهى بتاريخ ${fmt(end)}',
            anchor: anchor,
            contractId: cid,
          ));
        } else if (d2e >= 1 && d2e <= 7) {
          final anchor = _dateOnly(end);
          out.add(_AppNotificationLite(
            kind: NotificationKind.contractExpiring,
            title: 'عقد يقترب من الانتهاء',
            body: 'العقد ${cid ?? ''} يتبقى له $d2e يوم',
            anchor: anchor,
            contractId: cid,
          ));
        }
      }

      try {
        if (isContractDueToday(c)) {
          final first = firstDueAfterAdvance(c);
          final anchor = _dateOnly(first ?? today);
          out.add(_AppNotificationLite(
            kind: NotificationKind.contractDueToday,
            title: 'دفعة عقد مستحقة اليوم',
            body: 'العقد ${cid ?? ''} مستحق اليوم${first != null ? ' (${fmt(first)})' : ''}',
            anchor: anchor,
            contractId: cid,
          ));
        } else if (isContractOverdue(c)) {
          final first = firstDueAfterAdvance(c);
          final anchor = _dateOnly(first ?? today);
          out.add(_AppNotificationLite(
            kind: NotificationKind.contractDueOverdue,
            title: 'دفعة عقد متأخرة',
            body: 'العقد ${cid ?? ''} متجاوز تاريخ الاستحقاق${first != null ? ' (${fmt(first)})' : ''}',
            anchor: anchor,
            contractId: cid,
          ));
        }
      } catch (_) {}
    }

    // فواتير
    for (final inv in invoices.values) {
      try {
        if ((inv as dynamic).isArchived == true) continue;
        if ((inv as dynamic).isPaid == true) continue;
        final due = (inv as dynamic).dueDate as DateTime?;
        if (due == null) continue;
        final iid = (inv as dynamic).id?.toString();
        final cid = (inv as dynamic).contractId?.toString();

        final delta = daysBetween(due, today);
        final anchor = _dateOnly(due);

        if (delta == 0) {
          out.add(_AppNotificationLite(
            kind: NotificationKind.invoiceOverdue,
            title: 'فاتورة مستحقة اليوم',
            body: 'فاتورة ${iid ?? ''} لعقد ${cid ?? ''} مستحقة اليوم (${fmt(due)})',
            anchor: anchor,
            invoiceId: iid,
            contractId: cid,
          ));
        } else if (delta > 0) {
          out.add(_AppNotificationLite(
            kind: NotificationKind.invoiceOverdue,
            title: 'فاتورة متأخرة',
            body: 'فاتورة ${iid ?? ''} لعقد ${cid ?? ''} متجاوزة (${fmt(due)})',
            anchor: anchor,
            invoiceId: iid,
            contractId: cid,
          ));
        }
      } catch (_) {}
    }

    // صيانة
    for (final m in maintenance.values) {
      try {
        if ((m as dynamic).isArchived == true) continue;
        final s = (m as dynamic).scheduledDate as DateTime?;
        final st = (m as dynamic).status as MaintenanceStatus?;
        if (s == null) continue;
        if (_dateOnly(s) != today) continue;
        if (st == MaintenanceStatus.completed) continue;
        final mid = (m as dynamic).id?.toString();
        final anchor = _dateOnly(s);

        out.add(_AppNotificationLite(
          kind: NotificationKind.maintenanceToday,
          title: 'صيانة يبدأ موعدها اليوم',
          body: 'طلب الصيانة ${mid ?? ''} موعده ${fmt(s)}',
          anchor: anchor,
          maintenanceId: mid,
        ));
      } catch (_) {}
    }

    return out;
  }

  // عرض الإشعارات (مع منع تكرار)
  static Future<void> run() async {
    // تهيئة flutter_local_notifications داخل العزل الحالي
    await _ensureLocalInit();

    // افتح الصناديق اللازمة (لو كانت مغلقة في هذا العزل)
    if (!Hive.isBoxOpen(boxName('contractsBox'))) {
      await Hive.openBox<Contract>(boxName('contractsBox'));
    }
    if (!Hive.isBoxOpen(boxName('invoicesBox'))) {
      await Hive.openBox<Invoice>(boxName('invoicesBox'));
    }
    if (!Hive.isBoxOpen(boxName('maintenanceBox'))) {
      await Hive.openBox<MaintenanceRequest>(boxName('maintenanceBox'));
    }
    if (!Hive.isBoxOpen(boxName('notificationsDismissed'))) {
      await Hive.openBox<String>(boxName('notificationsDismissed'));
    }
    if (!Hive.isBoxOpen(boxName('notificationsPushed'))) {
      await Hive.openBox<String>(boxName('notificationsPushed'));
    }

    final contracts = Hive.box<Contract>(boxName('contractsBox'));
    final invoices = Hive.box<Invoice>(boxName('invoicesBox'));
    final maintenance = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
    final dismissed = Hive.box<String>(boxName('notificationsDismissed'));
    final pushed = Hive.box<String>(boxName('notificationsPushed'));

    final items = _generate(contracts, invoices, maintenance);

    // فلترة: استثناء ما تمّ إخفاؤه + ما تمّ دفعه سابقًا (pushed)
    final visible = items.where((n) {
      final dismissedNow = _isDismissed(
        dismissedBox: dismissed,
        kind: n.kind,
        cid: n.contractId,
        iid: n.invoiceId,
        mid: n.maintenanceId,
        anchor: n.anchor,
      );
      if (dismissedNow) return false;

      final k = _stableKey(
        n.kind,
        cid: n.contractId,
        iid: n.invoiceId,
        mid: n.maintenanceId,
        anchor: n.anchor,
      );
      return !pushed.containsKey(k);
    }).toList();

    if (visible.isEmpty) return;

    // اعرض إشعارًا لكل عنصر (ID فريد من الهاش)
    for (final n in visible) {
      final k = _stableKey(
        n.kind,
        cid: n.contractId,
        iid: n.invoiceId,
        mid: n.maintenanceId,
        anchor: n.anchor,
      );
      final id = k.hashCode & 0x7fffffff;

      await _local.show(
        id,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_local',
            'التنبيهات المحلية اليومية',
            channelDescription: 'إشعارات منطقية من التطبيق (عقود/فواتير/صيانة).',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: k, // يمكنك لاحقًا توجيه المستخدم بناءً عليه
      );

      // علّم أنه تم دفعه
      try {
        await pushed.put(k, '1');
      } catch (_) {}
    }
  }
}
