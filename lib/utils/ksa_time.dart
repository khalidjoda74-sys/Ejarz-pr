// lib/utils/ksa_time.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hijri/hijri_calendar.dart';

/// خدمة وقت السعودية (UTC+3) مبنية على وقت الخادم (Firestore serverTimestamp)
/// لضمان التطابق 100% بين التطبيق ولوحة التحكم.
///
/// مبادئ مهمّة:
/// - كل الحسابات تتم انطلاقًا من وقت الخادم (serverNow = deviceNow + drift).
/// - التخزين يكون دائمًا بصيغة UTC.
/// - العرض للمستخدم يكون KSA (UTC+3).
/// - يوجد آليات مساعدة لعقود شهرية/ليالي، وتنسيق هجري/ميلادي.
class KsaTime {
  KsaTime._();

  /// فرق جهازك عن وقت الخادم (UTC). موجب يعني الخادم متقدّم على جهازك.
  static Duration _drift = Duration.zero;

  /// هل تمت مزامنة أولية ناجحة؟
  static bool _initialized = false;
  static final ValueNotifier<bool> syncListenable = ValueNotifier<bool>(false);

  /// مؤقّت مزامنة دورية اختيارية.
  static Timer? _periodic;

  /// مرجع مستند خاص لطلب serverTimestamp
  static final _tsRef =
      FirebaseFirestore.instance.collection('_meta').doc('server_time');

  /// عدد مرات إعادة المحاولة للحصول على serverTimestamp إن كان null فورياً.
  static const int _retriesIfNull = 2;

  /// الفترة بين إعادة المحاولة عند غياب الـ timestamp (قصيرة).
  static const Duration _retryGap = Duration(milliseconds: 150);

  /// مزامنة مع وقت الخادم. نادِها بعد تسجيل الدخول وقبل أي حسابات زمنية.
  ///
  /// - force: لإجبار المزامنة حتى لو كانت مهيأة مسبقًا.
  /// تعيد ضبط [_drift] بحيث: serverUtc ≈ deviceUtc + _drift
  static Future<void> ensureSynced({bool force = false}) async {
    if (_initialized && !force) {
      _setSyncState(true);
      return;
    }

    final hadSuccessfulSync = _initialized;

    try {
      // 1) أرسل طلب serverTimestamp (دمجًا حتى لا نمحو حقولًا أخرى)
      await _tsRef
          .set({'ts': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      // 2) اجلب القراءة من الخادم بشكل صريح
      Timestamp? ts;
      for (int i = 0; i <= _retriesIfNull; i++) {
        final snap = await _tsRef.get(const GetOptions(source: Source.server));
        ts = (snap.data()?['ts']) as Timestamp?;
        if (ts != null) break;
        await Future.delayed(_retryGap);
      }

      if (ts == null) {
        if (!hadSuccessfulSync) {
          _drift = Duration.zero;
          _initialized = false;
        }
      } else {
        final serverUtc = ts.toDate().toUtc();
        _drift = serverUtc.difference(DateTime.now().toUtc());
        _initialized = true;
      }
    } catch (_) {
      if (!hadSuccessfulSync) {
        _drift = Duration.zero;
        _initialized = false;
      }
    }

    _setSyncState(_initialized);

    // تهيئة تنسيقات اللغة العربية (intl) وتعيين لغة التقويم الهجري
    try {
      await initializeDateFormatting('ar');
    } catch (_) {}
    try {
      HijriCalendar.setLocal('ar');
    } catch (_) {}
  }

  /// هل المزامنة ناجحة حاليًا (آخر محاولة)؟
  static bool get isSynced => _initialized;

  @visibleForTesting
  static void debugForceSynced({Duration drift = Duration.zero}) {
    _drift = drift;
    _initialized = true;
    _setSyncState(true);
  }

  @visibleForTesting
  static void debugResetSyncForTesting() {
    _periodic?.cancel();
    _periodic = null;
    _drift = Duration.zero;
    _initialized = false;
    _setSyncState(false);
  }

  static void _setSyncState(bool value) {
    if (syncListenable.value != value) {
      syncListenable.value = value;
    }
  }

  /// فارق وقت الخادم بالنسبة للجهاز (بالثواني عادة).
  static Duration get drift => _drift;

  // ---------------------------------------------------------------------------
  //                     لحظات الآن والتحويلات UTC/KSA
  // ---------------------------------------------------------------------------

  /// الآن من منظور الخادم (UTC) = deviceUtcNow + drift
  static DateTime nowUtc() => DateTime.now().toUtc().add(_drift);

  /// الآن KSA = nowUtc + 3h
  static DateTime nowKsa() => nowUtc().add(const Duration(hours: 3));

  /// توافق قديم: الآن KSA
  static DateTime now() => nowKsa();

  /// تحويل أي لحظة إلى KSA (للعرض فقط).
  static DateTime toKsa(DateTime any) =>
      any.toUtc().add(const Duration(hours: 3));

  /// تحويل تاريخ/وقت KSA إلى UTC (للتخزين).
  /// مهم: لا نعتمد على `toUtc()` هنا لأن `DateTime(year, month, day, ...)`
  /// يكون محليًا على الجهاز، بينما نحن نمرر له مكونات تمثل KSA صراحةً.
  static DateTime fromKsaToUtc(DateTime ksa) => DateTime.utc(
        ksa.year,
        ksa.month,
        ksa.day,
        ksa.hour,
        ksa.minute,
        ksa.second,
        ksa.millisecond,
        ksa.microsecond,
      ).subtract(const Duration(hours: 3));

  // ---------------------------------------------------------------------------
  //                      تواريخ اليوم KSA (تاريخ-فقط)
  // ---------------------------------------------------------------------------

  /// تاريخ اليوم KSA (بدون وقت). مفيد للفلاتر/العرض.
  /// ملاحظة: هذا الكائن بلا منطقة زمنية فعلية؛ لكنه يحمل (year/month/day) الصحيحة لـ KSA.
  static DateTime today() {
    final n = nowKsa();
    return DateTime(n.year, n.month, n.day);
  }

  /// يجرّد الوقت من أي DateTime (يبقي التاريخ فقط).
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 00:00 KSA ممثّلة كـ UTC (للتخزين القياسي).
  /// أي: KSA_midnight(y,m,d) == UTC(y,m,d) - 3h
  static DateTime _ksaMidnightUtcFromYmd(int y, int m, int d) =>
      DateTime.utc(y, m, d).subtract(const Duration(hours: 3));

  /// بداية اليوم KSA ممثّلة كـ UTC (نافعة للفلاتر الزمنية في الاستعلام).
  static DateTime ksaStartOfDayUtc([DateTime? baseUtc]) {
    final utc = (baseUtc ?? nowUtc()).toUtc();
    final ksa = utc.add(const Duration(hours: 3));
    return _ksaMidnightUtcFromYmd(ksa.year, ksa.month, ksa.day);
  }

  /// نهاية اليوم KSA (حصرية) ممثّلة كـ UTC.
  static DateTime ksaEndOfDayUtc([DateTime? baseUtc]) =>
      ksaStartOfDayUtc(baseUtc).add(const Duration(days: 1));

  // ---------------------------------------------------------------------------
  //                اشتراكات/عقود شهرية (تقويمية) — سياسة اليوم
  // ---------------------------------------------------------------------------
  //
  // السياسة:
  // - نحافظ على نفس رقم اليوم إن وُجد.
  // - لو البداية 31 وشهر الهدف لا يملك 31 → 1 من الشهر الذي يلي شهر الهدف (March 1 في مثال Jan 31 + 1 شهر).
  // - لو اليوم 29/30 ووقعنا في فبراير → آخر يوم في الشهر المستهدف.
  //
  // الدالة تستقبل تاريخ-فقط KSA ممثّل كـ UTC (بداية اليوم KSA)،
  // وتُعيد "اليوم الأخير المشمول" كـ تاريخ-فقط KSA ممثّل كـ UTC.
  static DateTime addMonthsKsaDateOnlyUtc(
      DateTime startKsaDateOnlyUtc, int months) {
    final startKsa = toKsa(startKsaDateOnlyUtc); // صار لدينا تاريخ KSA حقيقي
    final startDay = startKsa.day;

    int targetYear = startKsa.year + ((startKsa.month - 1 + months) ~/ 12);
    int targetMonth = ((startKsa.month - 1 + months) % 12) + 1;

    final lastDayOfTarget = DateTime.utc(targetYear, targetMonth + 1, 0).day;

    if (startDay != 31) {
      final endDay = (startDay <= lastDayOfTarget) ? startDay : lastDayOfTarget;
      return _ksaMidnightUtcFromYmd(targetYear, targetMonth, endDay);
    }

    // يوم 31: 1 من الشهر الذي يلي الشهر المستهدف.
    final afterYear = targetYear + (targetMonth == 12 ? 1 : 0);
    final afterMonth = (targetMonth == 12) ? 1 : (targetMonth + 1);
    return _ksaMidnightUtcFromYmd(afterYear, afterMonth, 1);
  }

  /// نهاية حصرية = اليوم الأخير المشمول + 1 يوم (بداية اليوم التالي KSA كـ UTC).
  static DateTime endExclusiveUtcFromInclusiveDateOnlyUtc(
          DateTime endInclusiveDateOnlyUtc) =>
      endInclusiveDateOnlyUtc.add(const Duration(days: 1));

  // ---------------------------------------------------------------------------
  //              عقود يومية (نظام الليالي: check-in / check-out)
  // ---------------------------------------------------------------------------

  /// يبني لحظة KSA (تاريخ + ساعة/دقيقة) ممثّلة كـ UTC للتخزين.
  /// مثال: 2025-10-03 15:00 KSA → نخزّنها كـ 2025-10-03 12:00 UTC.
  static DateTime ksaDateTimeUtc(int y, int m, int d,
      {int hour = 0, int minute = 0}) {
    return DateTime.utc(y, m, d, hour, minute)
        .subtract(const Duration(hours: 3));
  }

  /// نهاية حصرية لعقد يومي:
  /// startUtc = لحظة البداية المخزّنة (UTC) لكنها تمثل وقت KSA الحقيقي،
  /// nights = عدد الليالي.
  ///
  /// مثال: checkIn 15:00، checkOut 12:00، nights = 3
  /// → النهاية الحصرية = يوم (start + 3 أيام) عند 12:00 KSA (مخزّنة كـ UTC).
  static DateTime nightlyEndExclusiveUtcFromStart({
    required DateTime startUtc,
    required int nights,
    int checkOutHour = 12,
    int checkOutMinute = 0,
  }) {
    final sKsa = toKsa(startUtc);
    final checkoutDateKsa =
        DateTime(sKsa.year, sKsa.month, sKsa.day).add(Duration(days: nights));
    final checkoutKsa = DateTime(
      checkoutDateKsa.year,
      checkoutDateKsa.month,
      checkoutDateKsa.day,
      checkOutHour,
      checkOutMinute,
    );
    return checkoutKsa.subtract(const Duration(hours: 3));
  }

  // ---------------------------------------------------------------------------
  //                 تنسيقات العرض — ميلادي / هجري
  // ---------------------------------------------------------------------------

  /// تنسيق وقت/تاريخ KSA (ميلادي).
  static String formatKsa(DateTime any, {String pattern = 'yyyy-MM-dd'}) {
    return DateFormat(pattern, 'ar').format(toKsa(any));
  }

  /// صياغات شائعة
  static String formatKsaDate(DateTime any) =>
      formatKsa(any, pattern: 'yyyy/MM/dd');
  static String formatKsaDateTime(DateTime any) =>
      formatKsa(any, pattern: 'yyyy/MM/dd HH:mm');

  /// يعرض التاريخ حسب النظام المختار انطلاقًا من "لحظة" (UTC/محلي) بعد تحويلها إلى KSA.
  /// system: 'gregorian' | 'hijri'
  static String formatWithSystem(DateTime any, String system,
      {String gPattern = 'yyyy/MM/dd'}) {
    final ksaInstant = toKsa(any);
    if (system == 'hijri') {
      final h = HijriCalendar.fromDate(ksaInstant);
      // صيغة رقمية ثابتة (لتجنّب اختلاف أسماء الأشهر عبر الإصدارات)
      return '${h.hDay}/${h.hMonth}/${h.hYear} هـ';
    } else {
      return DateFormat(gPattern, 'ar').format(ksaInstant);
    }
  }

  /// يعرض التاريخ حسب النظام المختار عندما يكون الإدخال "تاريخ-فقط KSA".
  /// لا يُجري أي إزاحة زمنية (يستخدم y/m/d كما هي).
  static String formatDateOnlyWithSystem(DateTime ksaDateOnly, String system,
      {String gPattern = 'yyyy/MM/dd'}) {
    if (system == 'hijri') {
      final h = HijriCalendar.fromDate(ksaDateOnly);
      return '${h.hDay}/${h.hMonth}/${h.hYear} هـ';
    } else {
      return DateFormat(gPattern, 'ar').format(ksaDateOnly);
    }
  }

  // ---------------------------------------------------------------------------
  //                                أدوات مساعدة
  // ---------------------------------------------------------------------------

  /// يحاول تحويل قيمة متنوعة إلى UTC (Timestamp/DateTime/String ISO8601).
  static DateTime? parseToUtc(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      try {
        return DateTime.parse(v).toUtc();
      } catch (_) {}
    }
    return null;
  }

  /// تشغيل مزامنة دورية تلقائية (مثلاً كل 6 ساعات).
  static void startAutoSync({Duration every = const Duration(hours: 6)}) {
    _periodic?.cancel();
    _periodic = Timer.periodic(every, (_) => ensureSynced(force: true));
  }

  /// إيقاف المؤقّت الدوري.
  static void dispose() {
    _periodic?.cancel();
    _periodic = null;
  }
}
