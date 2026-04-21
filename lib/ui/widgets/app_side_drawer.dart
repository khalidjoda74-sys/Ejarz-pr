// lib/ui/widgets/app_side_drawer.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'dart:ui' as ui; // لاستخدام ui.TextDirection.rtl
import 'package:flutter/material.dart';
import 'package:darvoo/widgets/custom_confirm_dialog.dart';
// MaxLengthEnforcement
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/constants/boxes.dart' as bx;
import '../../data/services/user_scope.dart' as scope;
import '../../data/services/firestore_user_collections.dart';
import '../../data/services/office_client_guard.dart'; // ✅ جديد
import '../../data/services/activity_log_service.dart';
import '../../data/services/package_limit_service.dart';

// ✅ ضبط الوقت/التاريخ على توقيت الرياض (نسخة متوافقة مع لوحة التحكم)

class AppSideDrawer extends StatelessWidget {
  const AppSideDrawer({super.key});

  // خلفية مائلة للأصفر
  static const Color _drawerBg = Color(0xFFFFFBEB); // #FFFBEB
  static const Color _primary = Color(0xFF0F766E);

  // روابط
  static final Uri _privacyUri = Uri.parse(
      'https://www.notion.so/darvoo-2c2c4186d1998080a134eeba1cc8e0b6?source=copy_link');
  static final Uri _termsUri = Uri.parse(
      'https://www.notion.so/darvoo-2-2c2c4186d199809995f2e4168dd95d75?source=copy_link');
  static const String _supportEmail = 'support@darvoo.com';
  static const String _kDailyContractEndHourField = 'daily_contract_end_hour';

  static Future<void> openSettingsSheet(BuildContext context) async {
    await const AppSideDrawer()._openSettings(context);
  }

  // نص الرسالة الافتراضي (قبل الانتهاء) — المرجع لطول الحروف
  static const String _kDefaultMsg =
      'عزيزي المستأجر، عقد الإيجار ربع السنوي ينتهي بتاريخ [التاريخ]. نرجو تأكيد رغبتك في التجديد أو إنهاء العقد.';

  // نص افتراضي عند الانتهاء
  static const String _kDefaultMsgEnded =
      'عزيزي المستأجر، عقد الإيجار ربع السنوي انتهى بتاريخ [التاريخ].';

  // فتح روابط خارجية
  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الرابط.')),
      );
    }
  }

  /// يحوّل أي قيمة إلى DateTime.utc()
  int? _normalizeDailyContractEndHour(dynamic value) {
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

  int _hour12From24(int hour24) {
    final normalized = hour24.clamp(0, 23);
    final hour = normalized % 12;
    return hour == 0 ? 12 : hour;
  }

  String _periodFrom24(int hour24) => hour24 >= 12 ? 'PM' : 'AM';

  int? _hour24FromParts(int? hour12, String? period) {
    if (hour12 == null || period == null) return null;
    final h = hour12.clamp(1, 12);
    if (period == 'AM') return h == 12 ? 0 : h;
    if (period == 'PM') return h == 12 ? 12 : h + 12;
    return null;
  }

  String _formatHourAmPm(int hour24) {
    final normalized = hour24.clamp(0, 23);
    return '${_hour12From24(normalized)}:00 ${_periodFrom24(normalized)}';
  }

  int? _readDailyContractEndHourFromSession() {
    try {
      if (!Hive.isBoxOpen('sessionBox')) return null;
      final box = Hive.box('sessionBox');
      return _normalizeDailyContractEndHour(
        box.get(_kDailyContractEndHourField),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _mirrorDailyContractEndHourToSessionBox(int? hour24) async {
    try {
      if (await _openBoxIfClosed('sessionBox')) {
        final session = Hive.box('sessionBox');
        if (hour24 == null) {
          await session.delete(_kDailyContractEndHourField);
        } else {
          await session.put(_kDailyContractEndHourField, hour24);
        }
      }
    } catch (_) {
      // غير حرج
    }
  }

  DocumentReference<Map<String, dynamic>>? _workspacePrefsRef() {
    final workspaceUid = scope.effectiveUid().trim();
    if (workspaceUid.isEmpty || workspaceUid == 'guest') return null;
    return FirebaseFirestore.instance.collection('user_prefs').doc(workspaceUid);
  }

  Future<Map<String, dynamic>> _safeReadDocData(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      return snap.data() ?? const <String, dynamic>{};
    } on TimeoutException {
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (_) {
        return const <String, dynamic>{};
      }
    } catch (_) {
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
  }

  static DateTime? _parseDateUtc(dynamic v) {
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

  /// تحويل نص yyyy-MM-dd أو yyyy/MM/dd إلى "منتصف ليل KSA" ممثل كـ UTC.
  DateTime? _parseKsaYmdToUtcMidnight(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      final parts = t.replaceAll('/', '-').split('-');
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      // 00:00 KSA = (اليوم نفسه 21:00 UTC لليوم السابق)
      return DateTime.utc(y, m, d).subtract(const Duration(hours: 3));
    } catch (_) {
      return null;
    }
  }

  // يحوّل نص yyyy-MM-dd (أو yyyy/MM/dd) إلى تاريخ KSA (date-only) صالح للعرض
  DateTime? _ksaDateOnlyFromKsaText(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final fixed = t.replaceAll('/', '-');
    final utcMid = _parseKsaYmdToUtcMidnight(fixed);
    if (utcMid == null) return null;
    return KsaTime.dateOnly(KsaTime.toKsa(utcMid));
  }

  String _normSlash(String s) => s.replaceAll('-', '/');

  // ======= مساعدات الخطة (المدة والسعر) =======
  int? _extractMonths(Map<String, dynamic> data) {
    final pm = data['planMonths'];
    if (pm is num) {
      final months = pm.toInt();
      if (months > 0) return months;
    }
    final dur = data['duration'];
    if (dur is String && dur.trim().isNotEmpty) {
      final m = RegExp(r'(\d+)m').firstMatch(dur.trim().toLowerCase());
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  String _extractPlanDurationLabel(Map<String, dynamic> data) {
    final dur = (data['duration'] ?? '').toString().trim().toLowerCase();
    if (dur == 'demo3d') return '3 أيام';
    if (dur == 'trial24h') return '24 ساعة';
    final months = _extractMonths(data);
    return months != null ? _durationLabelFromMonths(months) : '—';
  }

  String _durationLabelFromMonths(int m) {
    switch (m) {
      case 1:
        return '1 شهر';
      case 3:
        return '3 شهور';
      case 6:
        return '6 شهور';
      case 12:
        return 'سنة';
      default:
        return '$m شهر';
    }
  }

  String _formatMoney(num n, [String? currency]) {
    final nf = NumberFormat('#,##0.##', 'ar');
    final amount = nf.format(n);
    final cur = (currency ?? 'SAR').toString();
    return '$amount $cur';
  }

  String _extractPlanPriceLabel(Map<String, dynamic> data) {
    final v = data['planCost'];
    if (v is num) {
      final currency =
          (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
      return _formatMoney(v, currency);
    }
    for (final k in [
      'plan_price',
      'price',
      'amount',
      'subscription_price',
      'amount_sar',
      'plan_amount',
      'plan_cost',
      'billing_amount',
      'price_sar',
    ]) {
      final val = data[k];
      if (val is num) {
        final currency =
            (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
        return _formatMoney(val, currency);
      }
      if (val is String && val.trim().isNotEmpty) {
        final cleaned = val.replaceAll(RegExp(r'[^\d\.\-]'), '');
        final num? n = num.tryParse(cleaned);
        if (n != null) {
          final currency =
              (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
          return _formatMoney(n, currency);
        }
      }
    }
    return '—';
  }

  // ——————————————————————————————————————————————————————————
  // ✅ مزامنة تفضيل نظام التاريخ مع Hive ليقرأه باقي أجزاء التطبيق
  // ——————————————————————————————————————————————————————————
  Future<bool> _openBoxIfClosed(String name) async {
    if (Hive.isBoxOpen(name)) return true;
    try {
      await Hive.openBox(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _mirrorDateSystemToHive(String dateSystem) async {
    final isHijri = dateSystem.toLowerCase() == 'hijri';
    try {
      // settingsBox
      if (await _openBoxIfClosed('settingsBox')) {
        final settings = Hive.box('settingsBox');
        await settings.put('settings_date_system', dateSystem);
        await settings.put('isHijri', isHijri);
        await settings.put('useHijri', isHijri);
        await settings.put('calendar', isHijri ? 'hijri' : 'gregorian');
        await settings.put('dateMode', isHijri ? 'hijri' : 'gregorian');
        await settings.put('calendarMode', isHijri ? 'hijri' : 'gregorian');
        await settings.put('dateCalendar', isHijri ? 'hijri' : 'gregorian');
      }
      // sessionBox (تأثير فوري أثناء الجلسة)
      if (await _openBoxIfClosed('sessionBox')) {
        final session = Hive.box('sessionBox');
        await session.put('isHijri', isHijri);
        await session.put('useHijri', isHijri);
        await session.put('calendar', isHijri ? 'hijri' : 'gregorian');
        await session.put('dateMode', isHijri ? 'hijri' : 'gregorian');
        await session.put('calendarMode', isHijri ? 'hijri' : 'gregorian');
        await session.put('dateCalendar', isHijri ? 'hijri' : 'gregorian');
      }
    } catch (_) {
      // نتجاهل أي خطأ محلي — ليس حرجًا
    }
  }

  // ✅ مساعد: عكس قيم أيام "قاربت" إلى sessionBox ليستعملها UI فورًا
  Future<void> _mirrorDueSoonDaysToSessionBox({
    required int monthlyDays,
    required int quarterlyDays,
    required int semiAnnualDays,
    required int annualDays,
  }) async {
    try {
      if (await _openBoxIfClosed('sessionBox')) {
        final s = Hive.box('sessionBox');
        await s.put('dueSoonMonthly', monthlyDays.clamp(1, 7));
        await s.put('dueSoonQuarterly', quarterlyDays.clamp(1, 15));
        await s.put('dueSoonSemiannual', semiAnnualDays.clamp(1, 30));
        await s.put('dueSoonAnnual', annualDays.clamp(1, 45));
      }
    } catch (_) {
      // غير حرِج
    }
  }

  /// ===== اشتراكي: قراءة من Firestore =====
  Future<_SubscriptionData> _fetchSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '—';
    if (user == null) {
      return _SubscriptionData.empty(email: email);
    }

    final data = await _safeReadDocData(
      FirebaseFirestore.instance.collection('users').doc(user.uid),
    );

    final startKsaText = (data['start_date_ksa'] as String?)?.trim();
    final endKsaText = (data['end_date_ksa'] as String?)?.trim();

    final startAtUtc = _parseDateUtc(data['subscription_start']);
    final endAtUtc = _parseDateUtc(data['subscription_end']); // حصرية

    final todayKsaDate = KsaTime.dateOnly(KsaTime.nowKsa());

    DateTime? endInclusiveKsaDateOnly;
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final endMidUtc = _parseKsaYmdToUtcMidnight(endKsaText);
      if (endMidUtc != null) {
        endInclusiveKsaDateOnly = KsaTime.dateOnly(KsaTime.toKsa(endMidUtc));
      }
    }
    if (endInclusiveKsaDateOnly == null && endAtUtc != null) {
      // نعتبر أن subscription_end هو نفسه تاريخ نهاية الاشتراك بتوقيت السعودية
      final endKsa = KsaTime.toKsa(endAtUtc);

      // ❌ لا نطرح أي يوم هنا
      endInclusiveKsaDateOnly = KsaTime.dateOnly(endKsa);
    }

    final bool active = endInclusiveKsaDateOnly != null &&
        !endInclusiveKsaDateOnly.isBefore(todayKsaDate);
    final int daysLeft = active
        ? (endInclusiveKsaDateOnly.difference(todayKsaDate).inDays + 1)
        : 0;

    final planDurationLabel = _extractPlanDurationLabel(data);

    final planPriceLabel = _extractPlanPriceLabel(data);
    final packageSnapshot = OfficePackageSnapshot.fromUserDoc(data);

    return _SubscriptionData(
      email: email,
      planDurationLabel: planDurationLabel,
      planPriceLabel: planPriceLabel,
      startKsaText: startKsaText,
      endKsaText: endKsaText,
      startAtUtc: startAtUtc,
      endAtUtc: endAtUtc,
      endInclusiveKsaDateOnly: endInclusiveKsaDateOnly,
      active: active,
      daysLeft: daysLeft,
      packageName: packageSnapshot?.name ?? '',
      officeUsersDisplay: packageSnapshot?.officeUsersDisplay ?? 'غير محدد',
      clientsDisplay: packageSnapshot?.clientsDisplay ?? 'غير محدد',
      propertiesDisplay: packageSnapshot?.propertiesDisplay ?? 'غير محدد',
    );
  }

  // ==== أدوات مساعدة آمنة للأعداد ====
  int _toInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    if (v is String) {
      final t = int.tryParse(v.trim());
      if (t != null) return t;
    }
    return fallback;
  }

  // ==== الإعدادات: قراءة / حفظ Firestore — على user_prefs/{uid} ====
  Future<_SettingsData> _fetchSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _SettingsData.empty();
    }

    final m = await _safeReadDocData(
      FirebaseFirestore.instance.collection('user_prefs').doc(user.uid),
    );
    final workspacePrefs = _workspacePrefsRef();
    final workspaceMap = workspacePrefs == null
        ? const <String, dynamic>{}
        : await _safeReadDocData(workspacePrefs);
    final dailyContractEndHour = _normalizeDailyContractEndHour(
      workspaceMap[_kDailyContractEndHourField] ??
          m[_kDailyContractEndHourField] ??
          _readDailyContractEndHourFromSession(),
    );

    String read(String k, String fallback) => (m[k] ?? fallback).toString();
    int yearDays(String key, int fallback) =>
        _toInt(m[key], fallback).clamp(1, 45);
    final annualYears = <int, int>{
      for (var y = 1; y <= 10; y++)
        y: yearDays(
            'notif_annual_${y}y_days', _toInt(m['notif_annual_days'], 45)),
    };
    final contractAnnualYears = <int, int>{
      for (var y = 1; y <= 10; y++)
        y: yearDays(
          'notif_contract_annual_${y}y_days',
          _toInt(m['notif_contract_annual_days'], annualYears[y] ?? 45),
        ),
    };

    final result = _SettingsData(
      language: read('settings_language', 'ar'),
      dateSystem: read('settings_date_system', 'gregorian'),
      monthlyDays: _toInt(m['notif_monthly_days'], 7),
      quarterlyDays: _toInt(m['notif_quarterly_days'], 15),
      semiAnnualDays: _toInt(m['notif_semiannual_days'], 30),
      annualDays: annualYears[1] ?? 45,

      // رسائل الدفعات قبل الانتهاء
      monthlyMsgBefore: read(
        'notif_monthly_msg_before',
        read('notif_monthly_msg', _kDefaultMsg),
      ),
      quarterlyMsgBefore: read(
        'notif_quarterly_msg_before',
        read('notif_quarterly_msg', _kDefaultMsg),
      ),
      semiAnnualMsgBefore: read(
        'notif_semiannual_msg_before',
        read('notif_semiannual_msg', _kDefaultMsg),
      ),
      annualMsgBefore: read(
        'notif_annual_msg_before',
        read('notif_annual_msg', _kDefaultMsg),
      ),

      // رسائل عند الانتهاء
      monthlyMsgOn: read('notif_monthly_msg_on', _kDefaultMsgEnded),
      quarterlyMsgOn: read('notif_quarterly_msg_on', _kDefaultMsgEnded),
      semiAnnualMsgOn: read('notif_semiannual_msg_on', _kDefaultMsgEnded),
      annualMsgOn: read('notif_annual_msg_on', _kDefaultMsgEnded),

      // تبويب عقود: أيام "قاربت"
      contractMonthlyDays: _toInt(
        m['notif_contract_monthly_days'],
        _toInt(m['notif_monthly_days'], 7),
      ),
      contractQuarterlyDays: _toInt(
        m['notif_contract_quarterly_days'],
        _toInt(m['notif_quarterly_days'], 15),
      ),
      contractSemiAnnualDays: _toInt(
        m['notif_contract_semiannual_days'],
        _toInt(m['notif_semiannual_days'], 30),
      ),
      contractAnnualDays: contractAnnualYears[1] ?? (annualYears[1] ?? 45),
      annualYearsDays: annualYears,
      contractAnnualYearsDays: contractAnnualYears,

      // تبويب عقود: الرسائل قبل الانتهاء
      contractMonthlyMsgBefore: read(
        'notif_contract_monthly_msg_before',
        read('notif_monthly_msg_before', _kDefaultMsg),
      ),
      contractQuarterlyMsgBefore: read(
        'notif_contract_quarterly_msg_before',
        read('notif_quarterly_msg_before', _kDefaultMsg),
      ),
      contractSemiAnnualMsgBefore: read(
        'notif_contract_semiannual_msg_before',
        read('notif_semiannual_msg_before', _kDefaultMsg),
      ),
      contractAnnualMsgBefore: read(
        'notif_contract_annual_msg_before',
        read('notif_annual_msg_before', _kDefaultMsg),
      ),
      dailyContractEndHour: dailyContractEndHour,
    );

    // 👈 نضمن أن Hive محدثة دائماً (حتى لو فتح الإعدادات بعد استعادة من السيرفر)
    await _mirrorDateSystemToHive(result.dateSystem);
    await _mirrorDueSoonDaysToSessionBox(
      monthlyDays: result.monthlyDays,
      quarterlyDays: result.quarterlyDays,
      semiAnnualDays: result.semiAnnualDays,
      annualDays: result.annualDays,
    );
    await _mirrorDailyContractEndHourToSessionBox(
      result.dailyContractEndHour,
    );

    return result;
  }

  Future<void> _saveSettings(
    Map<String, dynamic> payload,
    BuildContext context, {
    String successMessage = 'تم الحفظ بنجاح.',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final dailyContractEndHour = payload.containsKey(_kDailyContractEndHourField)
        ? _normalizeDailyContractEndHour(payload[_kDailyContractEndHourField])
        : null;

    // 1) إرسال التغييرات إلى Firestore في الخلفية (إن وُجد إنترنت)
    FirebaseFirestore.instance
        .collection('user_prefs')
        .doc(user.uid)
        .set(payload, SetOptions(merge: true))
        .catchError((_) {
      // في حال عدم وجود إنترنت أو خطأ مؤقت، سيتم الاعتماد على Hive
      // وFirestore سيحاول المزامنة لاحقًا تلقائيًا.
    });

    // 2) تحديث Hive دائمًا (حتى بدون إنترنت)
    final ds = payload['settings_date_system'];
    if (ds is String && ds.trim().isNotEmpty) {
      await _mirrorDateSystemToHive(ds);
    }
    if (payload.containsKey(_kDailyContractEndHourField)) {
      await _mirrorDailyContractEndHourToSessionBox(dailyContractEndHour);
      final workspacePrefs = _workspacePrefsRef();
      if (workspacePrefs != null) {
        FirebaseFirestore.instance
            .collection('user_prefs')
            .doc(workspacePrefs.id)
            .set({
          'uid': workspacePrefs.id,
          _kDailyContractEndHourField: dailyContractEndHour,
        }, SetOptions(merge: true))
            .catchError((_) {
          // نعتمد على التخزين المحلي عند فشل الشبكة.
        });
      }
    }

    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final md = asInt(payload['notif_monthly_days']);
    final qd = asInt(payload['notif_quarterly_days']);
    final sd = asInt(payload['notif_semiannual_days']);
    final ad = asInt(payload['notif_annual_days']);

    if (md != null || qd != null || sd != null || ad != null) {
      int curM = 7, curQ = 15, curS = 30, curA = 45;
      try {
        if (await _openBoxIfClosed('sessionBox')) {
          final s = Hive.box('sessionBox');
          curM = (s.get('dueSoonMonthly') ?? 7) as int;
          curQ = (s.get('dueSoonQuarterly') ?? 15) as int;
          curS = (s.get('dueSoonSemiannual') ?? 30) as int;
          curA = (s.get('dueSoonAnnual') ?? 45) as int;
        }
      } catch (_) {}

      await _mirrorDueSoonDaysToSessionBox(
        monthlyDays: md ?? curM,
        quarterlyDays: qd ?? curQ,
        semiAnnualDays: sd ?? curS,
        annualDays: ad ?? curA,
      );
    }

    // 3) رسالة للمستخدم (تُعرض دائمًا حتى بدون إنترنت)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
      ),
    );
  }

  // ✅ يضمن وجود مستند users/{uid} لدعم القواعد التي تشترط وجوده
  Future<void> _ensureUsersDocForRules(FirebaseFirestore fs, String uid) async {
    try {
      final usersRef = fs.collection('users').doc(uid);
      final snap = await usersRef.get();
      if (!snap.exists) {
        await usersRef.set({
          'uid': uid,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await usersRef.set({
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // بدون إنترنت / rules error → نتجاهل
      // لا نريد أن نفشل إعادة الضبط المحلية بسبب هذه الدالة
    }
  }

  Future<void> _confirmFactoryReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text('إعادة ضبط كامل',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
          content: Text(
            'سيتم حذف جميع بياناتك (العقارات، العقود، السندات، المستأجرون، الإشعارات، والإعدادات). هل تريد المتابعة؟',
            style: GoogleFonts.tajawal(
                fontSize: 14.sp, height: 1.6, fontWeight: FontWeight.w700),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('تأكيد الحذف',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _factoryReset(context);
    }
  }

  Future<void> _factoryReset(BuildContext context) async {
    final fs = FirebaseFirestore.instance;

    // ✅ استخدم الـ uid الفعلي (يدعم وضع دخول عميل المكتب)
    final uid = scope.effectiveUid();

    // لو ما في uid حقيقي، نسمح بالمسح المحلي فقط ونتجاهل السيرفر
    final bool canTouchServer = uid != 'guest';

    // ========== دوال مساعدة للحذف من Firestore ==========

    Future<void> deleteOwnedDocs(String collection,
        {required String field}) async {
      const int batchLimit = 450;
      while (true) {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await fs
              .collection(collection)
              .where(field, isEqualTo: uid)
              .limit(batchLimit)
              .get();
        } catch (_) {
          break;
        }

        if (snap.docs.isEmpty) break;

        final batch = fs.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        try {
          await batch.commit();
        } catch (_) {
          break;
        }
        if (snap.docs.length < batchLimit) break;
      }
    }

    Future<void> deleteOwnedDocsByFields(
        String collection, List<String> fields) async {
      for (final f in fields) {
        await deleteOwnedDocs(collection, field: f);
      }
    }

    Future<void> deleteUserNotifications() async {
      final notifCol =
          fs.collection('users').doc(uid).collection('notifications');
      const int batchLimit = 500;
      while (true) {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await notifCol.limit(batchLimit).get();
        } catch (_) {
          break;
        }

        if (snap.docs.isEmpty) break;

        final batch = fs.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        try {
          await batch.commit();
        } catch (_) {
          break;
        }

        if (snap.docs.length < batchLimit) break;
      }
    }

    Future<void> deleteUserSubcollection(
      CollectionReference<Map<String, dynamic>> ref,
    ) async {
      const int batchLimit = 450;
      while (true) {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await ref.limit(batchLimit).get();
        } catch (_) {
          break;
        }

        if (snap.docs.isEmpty) break;

        final batch = fs.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        try {
          await batch.commit();
        } catch (_) {
          break;
        }

        if (snap.docs.length < batchLimit) break;
      }
    }

    try {
      // ... نفس كود مسح الصناديق عندك ...

      // تنظيف أي آثار قديمة لعداد تسلسل العقود إن وجدت
      if (await _openBoxIfClosed('sessionBox')) {
        final session = Hive.box('sessionBox');
        final keysToDelete = session.keys
            .where((k) => k is String && k.startsWith('lastContractSeq-'))
            .toList();
        for (final k in keysToDelete) {
          await session.delete(k);
        }
        await session.delete(_kDailyContractEndHourField);
      }
    } catch (_) {
      // نتجاهل أي خطأ في المسح المحلي حتى لا تفشل العملية بالكامل
    }

    // ========== إظهار شاشة التحميل (تمنع الرجوع) ==========
    showDialog(
      context: context,
      barrierDismissible: false, // لا يمكن إغلاقها بالضغط خارجها
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => false, // يمنع زر الرجوع
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48.w,
                    height: 48.w,
                    child: const CircularProgressIndicator(),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'جاري إعادة الضبط...',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
// 1) نحاول حذف بيانات Firestore + إعادة ضبط user_prefs في الخلفية مع حد زمني
      try {
        await Future.any([
          () async {
            // ✅ لو ما عندنا uid حقيقي (guest) لا نحاول لمس السيرفر
            if (!canTouchServer) return;

            const ownerFields = ['ownerId', 'userId', 'uid', 'createdBy'];

            // مجموعات قديمة في root (للرجعية)
            await deleteOwnedDocsByFields('properties', ownerFields);
            await deleteOwnedDocsByFields('contracts', ownerFields);
            await deleteOwnedDocsByFields('invoices', ownerFields);
            await deleteOwnedDocsByFields('tenants', ownerFields);

            // مجموعات المستخدم الحالية تحت users/{uid}/...
            final uc = UserCollections(uid, db: fs);
            await deleteUserSubcollection(uc.properties);
            await deleteUserSubcollection(uc.contracts);
            await deleteUserSubcollection(uc.invoices);
            await deleteUserSubcollection(uc.tenants);
            await deleteUserSubcollection(uc.maintenance);
            await deleteUserSubcollection(uc.session);

            // حذف إشعارات المستخدم
            await deleteUserNotifications();

            // 2) إعادة ضبط user_prefs للقيم الافتراضية في Firestore
            final prefsRef = fs.collection('user_prefs').doc(uid);
            await prefsRef.set({
              'uid': uid,
              'settings_language': 'ar',
              'settings_date_system': 'gregorian',
              _kDailyContractEndHourField: FieldValue.delete(),
              'notif_monthly_days': 7,
              'notif_quarterly_days': 15,
              'notif_semiannual_days': 30,
              'notif_annual_days': 45,
              'notif_monthly_msg_before': _kDefaultMsg,
              'notif_quarterly_msg_before': _kDefaultMsg,
              'notif_semiannual_msg_before': _kDefaultMsg,
              'notif_annual_msg_before': _kDefaultMsg,
              'notif_monthly_msg_on': _kDefaultMsgEnded,
              'notif_quarterly_msg_on': _kDefaultMsgEnded,
              'notif_semiannual_msg_on': _kDefaultMsgEnded,
              'notif_annual_msg_on': _kDefaultMsgEnded,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            await _ensureUsersDocForRules(fs, uid);

            // تأكيد المزامنة (اختياري – لا نسمح أن تعلّق العملية أكثر من 5 ثواني)
            try {
              await fs
                  .waitForPendingWrites()
                  .timeout(const Duration(seconds: 5));
            } catch (_) {
              // لا مشكلة، سيتم الإرسال عند توفر الإنترنت
            }

            try {
              await fs.disableNetwork();
              await fs.enableNetwork();
            } catch (_) {}
          }(),
          // حد أقصى 8 ثواني لجزء السيرفر حتى لا يتجمّد بدون إنترنت
          Future.delayed(const Duration(seconds: 8)),
        ]);
      } catch (_) {
        // أي خطأ هنا لا يجب أن يوقف إعادة الضبط المحلي
      }

      // 2) عكس الإعدادات إلى Hive (محلي دائمًا)
      await _mirrorDateSystemToHive('gregorian');
      await _mirrorDueSoonDaysToSessionBox(
        monthlyDays: 7,
        quarterlyDays: 15,
        semiAnnualDays: 30,
        annualDays: 45,
      );

      // 3) مسح كل بيانات Hive المحلية
      try {
        final scopedBoxes = <String>[
          bx.kTenantsBox,
          bx.kPropertiesBox,
          bx.kContractsBox,
          bx.kInvoicesBox,
          bx.kMaintenanceBox,
          bx.kSessionBox,
          bx.kArchivedProps,
          'notificationsDismissed',
          'notificationsPushed',
          'pendingTenantUpserts',
          'pendingTenantDeletes',
          'pendingOfficeClientCreates',
          'pendingOfficeClientEdits',
          'pendingOfficeClientDeletes',
        ];

        for (final logical in scopedBoxes) {
          final boxName = scope.boxName(logical);
          if (await _openBoxIfClosed(boxName)) {
            await Hive.box(boxName).clear();
          }
        }

        final globalBoxes = <String>[
          'settingsBox',
          'sessionBox',
        ];
        for (final name in globalBoxes) {
          if (await _openBoxIfClosed(name)) {
            await Hive.box(name).clear();
          }
        }
      } catch (_) {
        // نتجاهل أي خطأ في المسح المحلي حتى لا تفشل العملية بالكامل
      }

      // 4) رسالة نجاح للمستخدم (حتى لو كان أوفلاين)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم حذف جميع بياناتك وإعادة ضبط التطبيق بنجاح.')),
      );
    } finally {
      // إغلاق شاشة "جاري إعادة الضبط..."
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ==== اشتراكي: Bottom Sheet ====
  Future<void> _openSubscription(BuildContext context) async {
    const primary = _primary;
    final df = DateFormat('yyyy/MM/dd', 'ar');

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22.r))),
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w,
              16.h + MediaQuery.of(context).viewInsets.bottom),
          child: FutureBuilder<_SubscriptionData>(
            future: _fetchSubscription(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return SizedBox(
                  height: 180.h,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return SizedBox(
                  height: 180.h,
                  child: Center(
                    child: Text(
                      'تعذّر تحميل تفاصيل الاشتراك.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w900, color: Colors.red),
                    ),
                  ),
                );
              }

              final sub = snap.data ?? _SubscriptionData.empty(email: '—');
              final active = sub.active;
              final leftDays = sub.daysLeft;

              final DateTime? startKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.startKsaText) ??
                      (sub.startAtUtc != null
                          ? KsaTime.dateOnly(KsaTime.toKsa(sub.startAtUtc!))
                          : null);
              final String startStr =
                  startKsaDateOnly == null ? '—' : df.format(startKsaDateOnly);

              final DateTime? endKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.endKsaText) ??
                      sub.endInclusiveKsaDateOnly;
              final String endStr =
                  endKsaDateOnly == null ? '—' : df.format(endKsaDateOnly);

              final double labelW = 110.w;
              final double valueW = 180.w;

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42.w,
                        height: 5.h,
                        margin: EdgeInsets.only(bottom: 12.h),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 40.w,
                            height: 40.w,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF4FF),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.card_membership_rounded,
                                color: primary),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              'اشتراكي',
                              style: GoogleFonts.tajawal(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 6.h),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFEFFBF6)
                                  : const Color(0xFFFFEFEF),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: active
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444)),
                            ),
                            child: Text(
                              active ? 'فعّال' : 'منتهي',
                              style: GoogleFonts.tajawal(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w900,
                                color: active
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      _RowItem(
                          label: 'البريد الإلكتروني',
                          value: sub.email,
                          wrap: true,
                          labelWidth: labelW,
                          valueWidth: valueW),
                      SizedBox(height: 8.h),
                      _RowItem(
                          label: 'الخطة',
                          value: sub.planDurationLabel,
                          labelWidth: labelW,
                          valueWidth: valueW),
                      SizedBox(height: 8.h),
                      _RowItem(
                          label: 'تاريخ البداية',
                          value: startStr,
                          labelWidth: labelW,
                          valueWidth: valueW),
                      SizedBox(height: 8.h),
                      _RowItem(
                          label: 'تاريخ الانتهاء',
                          value: endStr,
                          labelWidth: labelW,
                          valueWidth: valueW),
                      SizedBox(height: 8.h),
                      _RowItem(
                          label: 'قيمة الخطة',
                          value: sub.planPriceLabel,
                          labelWidth: labelW,
                          valueWidth: valueW),
                      SizedBox(height: 8.h),
                      _RowItem(
                          label: 'الأيام المتبقية',
                          value: active ? '$leftDays يوم' : '0 يوم',
                          labelWidth: labelW,
                          valueWidth: valueW),
                      if (sub.hasPackageDetails) ...[
                        SizedBox(height: 8.h),
                        _RowItem(
                          label: 'نوع الخطة',
                          value: sub.packageName.isEmpty
                              ? 'غير محدد'
                              : sub.packageName,
                          labelWidth: labelW,
                          valueWidth: valueW,
                        ),
                        SizedBox(height: 8.h),
                        _RowItem(
                          label: 'المستخدمين',
                          value: sub.officeUsersDisplay,
                          labelWidth: labelW,
                          valueWidth: valueW,
                        ),
                        SizedBox(height: 8.h),
                        _RowItem(
                          label: 'العملاء',
                          value: sub.clientsDisplay,
                          labelWidth: labelW,
                          valueWidth: valueW,
                        ),
                        SizedBox(height: 8.h),
                        _RowItem(
                          label: 'العقارات',
                          value: sub.propertiesDisplay,
                          labelWidth: labelW,
                          valueWidth: valueW,
                        ),
                      ],
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: primary),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r)),
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                              ),
                              child: Text(
                                'إغلاق',
                                style: GoogleFonts.tajawal(
                                  fontWeight: FontWeight.w900,
                                  color: primary,
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
        ),
      ),
    );
  }

  // ==== الإعدادات: Bottom Sheet (مع ScaffoldMessenger داخلي) ====
  Future<void> _openSettings(BuildContext context) async {
    const maxMsgLen = _kDefaultMsg.length;

    // Controllers للحالتين: قبل الانتهاء / عند الانتهاء
    TextEditingController? msgMonthlyBeforeCtrl, msgMonthlyOnCtrl;
    TextEditingController? msgQuarterlyBeforeCtrl, msgQuarterlyOnCtrl;
    TextEditingController? msgSemiBeforeCtrl, msgSemiOnCtrl;
    TextEditingController? msgAnnualBeforeCtrl, msgAnnualOnCtrl;
    // Controllers لخيار "العقود" (بدون 'عند الانتهاء')
    TextEditingController? cMsgMonthlyBeforeCtrl,
        cMsgQuarterlyBeforeCtrl,
        cMsgSemiBeforeCtrl,
        cMsgAnnualBeforeCtrl;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22.r))),
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        // 👇 لضمان ظهور SnackBar داخل النافذة نفسها
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Builder(
              builder: (sheetCtx) => FractionallySizedBox(
                heightFactor: 0.98, // أو 0.96 لو تفضّل

                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16.w,
                    12.h,
                    16.w,
                    8.h + MediaQuery.of(sheetCtx).viewInsets.bottom,
                  ),
                  child: FutureBuilder<_SettingsData>(
                    future: _fetchSettings(),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'تعذّر تحميل الإعدادات.\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.w900, color: Colors.red),
                          ),
                        );
                      }

                      var data = snap.data ?? _SettingsData.empty();

                      // الحالة المحلية داخل النافذة
                      String dateSystem =
                          data.dateSystem; // 'gregorian' / 'hijri'
                      int monthlyDays = data.monthlyDays;
                      int quarterlyDays = data.quarterlyDays;
                      int semiDays = data.semiAnnualDays;
                      final annualYearsDays =
                          Map<int, int>.from(data.annualYearsDays);
                      int annualSelectedYears = 1;
                      int annualDays = annualYearsDays[annualSelectedYears] ??
                          data.annualDays;
                      int? dailyContractEndHour = data.dailyContractEndHour;
                      int? dailyContractHour12 = dailyContractEndHour == null
                          ? null
                          : _hour12From24(dailyContractEndHour);
                      String? dailyContractPeriod = dailyContractEndHour == null
                          ? null
                          : _periodFrom24(dailyContractEndHour);

                      // تبويب علوي: 0 = دورة السداد (افتراضي), 1 = العقود
                      int topTab = 0; // 0=دورة السداد (افتراضي), 1=العقود
// removed: old init from persistent variable

                      // إعدادات تبويب "العقود" (قيم منفصلة عن دورة السداد)
                      int cMonthlyDays = data.contractMonthlyDays;
                      int cQuarterlyDays = data.contractQuarterlyDays;
                      int cSemiDays = data.contractSemiAnnualDays;
                      final cAnnualYearsDays =
                          Map<int, int>.from(data.contractAnnualYearsDays);
                      int cAnnualSelectedYears = 1;
                      int cAnnualDays =
                          cAnnualYearsDays[cAnnualSelectedYears] ??
                              data.contractAnnualDays;

                      bool cMonthlyOpen = false,
                          cQuarterlyOpen = false,
                          cSemiOpen = false,
                          cAnnualOpen = false;

                      bool cDailyOpen = false;
// أي عقد مفتوح؟
                      bool monthlyOpen = false,
                          quarterlyOpen = false,
                          semiOpen = false,
                          annualOpen = false;

                      bool dailyOpen = false;
// أي تبويب مُختار لكل عقد؟ 0=قبل الانتهاء، 1=عند الانتهاء
                      int monthlyMode = 0,
                          quarterlyMode = 0,
                          semiMode = 0,
                          annualMode = 0;

                      // تهيئة الكنترولرز
                      msgMonthlyBeforeCtrl ??=
                          TextEditingController(text: data.monthlyMsgBefore);
                      msgMonthlyOnCtrl ??=
                          TextEditingController(text: data.monthlyMsgOn);

                      msgQuarterlyBeforeCtrl ??=
                          TextEditingController(text: data.quarterlyMsgBefore);
                      msgQuarterlyOnCtrl ??=
                          TextEditingController(text: data.quarterlyMsgOn);

                      msgSemiBeforeCtrl ??=
                          TextEditingController(text: data.semiAnnualMsgBefore);
                      msgSemiOnCtrl ??=
                          TextEditingController(text: data.semiAnnualMsgOn);

                      msgAnnualBeforeCtrl ??=
                          TextEditingController(text: data.annualMsgBefore);
                      msgAnnualOnCtrl ??=
                          TextEditingController(text: data.annualMsgOn);

                      // Controllers الخاصة بتبويب "العقود" (قبل الانتهاء فقط)
                      cMsgMonthlyBeforeCtrl ??= TextEditingController(
                          text: data.contractMonthlyMsgBefore);
                      cMsgQuarterlyBeforeCtrl ??= TextEditingController(
                          text: data.contractQuarterlyMsgBefore);
                      cMsgSemiBeforeCtrl ??= TextEditingController(
                          text: data.contractSemiAnnualMsgBefore);
                      cMsgAnnualBeforeCtrl ??= TextEditingController(
                          text: data.contractAnnualMsgBefore);

                      Widget redBanner(String text) {
                        return Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12.w),
                          margin: EdgeInsets.only(bottom: 12.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEFEF),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: Text(
                            text,
                            style: GoogleFonts.tajawal(
                              fontSize: 13.5.sp,
                              height: 1.6,
                              color: const Color(0xFFB91C1C),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }

// removed duplicate  (moved above)
                      return StatefulBuilder(
                        builder: (context, setState) {
                          Widget generalCard() {
                            return _CardSection(
                              title: 'الإعدادات العامة',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // اللغة (ثابتة عربية)
                                  Row(
                                    children: [
                                      Text('اللغة',
                                          style: GoogleFonts.tajawal(
                                              fontWeight: FontWeight.w800)),
                                      const Spacer(),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10.w, vertical: 6.h),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFFBF6),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                              color: const Color(0xFF10B981)),
                                        ),
                                        child: Text(
                                          'العربية فقط',
                                          style: GoogleFonts.tajawal(
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF059669)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12.h),

                                  // نظام التاريخ
                                  Text('نظام التاريخ',
                                      style: GoogleFonts.tajawal(
                                          fontWeight: FontWeight.w800)),
                                  SizedBox(height: 8.h),
                                   Wrap(
                                     spacing: 8.w,
                                     children: [
                                      ChoiceChip(
                                        label: Text('ميلادي',
                                            style: GoogleFonts.tajawal(
                                                fontWeight: FontWeight.w900)),
                                        selected: dateSystem == 'gregorian',
                                        onSelected: (_) => setState(() =>
                                            dateSystem =
                                                'gregorian'), // ✅ تبديل فوري
                                      ),
                                      ChoiceChip(
                                        label: Text('هجري',
                                            style: GoogleFonts.tajawal(
                                                fontWeight: FontWeight.w900)),
                                        selected: dateSystem == 'hijri',
                                        onSelected: (_) => setState(() =>
                                            dateSystem =
                                                'hijri'), // ✅ تبديل فوري
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12.h),
                                  Divider(
                                    height: 24.h,
                                    thickness: 1,
                                    color: Colors.black.withOpacity(0.08),
                                  ),
                                  Text(
                                    'إعدادات العقود اليومية',
                                    style: GoogleFonts.tajawal(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(12.w),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12.r),
                                      border: Border.all(
                                        color: Colors.black.withOpacity(0.08),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'وقت انتهاء اليومي المعتمد',
                                                style: GoogleFonts.tajawal(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 10.w,
                                                vertical: 6.h,
                                              ),
                                              decoration: BoxDecoration(
                                                color: dailyContractEndHour ==
                                                        null
                                                    ? const Color(0xFFFFF7ED)
                                                    : const Color(0xFFEFFBF6),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: dailyContractEndHour ==
                                                          null
                                                      ? const Color(0xFFF97316)
                                                      : const Color(0xFF10B981),
                                                ),
                                              ),
                                              child: Text(
                                                dailyContractEndHour == null
                                                    ? 'غير مضبوط'
                                                    : _formatHourAmPm(
                                                        dailyContractEndHour!),
                                                style: GoogleFonts.tajawal(
                                                  fontWeight: FontWeight.w900,
                                                  color:
                                                      dailyContractEndHour ==
                                                              null
                                                          ? const Color(
                                                              0xFF9A3412)
                                                          : const Color(
                                                              0xFF059669),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 10.h),
                                        Row(
                                          children: [
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<int>(
                                                initialValue:
                                                    dailyContractHour12,
                                                isExpanded: true,
                                                decoration: InputDecoration(
                                                  labelText: 'الساعة',
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10.r),
                                                  ),
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    horizontal: 12.w,
                                                    vertical: 10.h,
                                                  ),
                                                ),
                                                items: List.generate(12,
                                                        (i) => i + 1)
                                                    .map(
                                                      (hour) =>
                                                          DropdownMenuItem<int>(
                                                        value: hour,
                                                        child:
                                                            Text(hour.toString()),
                                                      ),
                                                    )
                                                    .toList(),
                                                onChanged: (v) {
                                                  setState(() {
                                                    dailyContractHour12 = v;
                                                    dailyContractEndHour =
                                                        _hour24FromParts(
                                                      dailyContractHour12,
                                                      dailyContractPeriod,
                                                    );
                                                  });
                                                },
                                              ),
                                            ),
                                            SizedBox(width: 10.w),
                                            Expanded(
                                              child: DropdownButtonFormField<
                                                  String>(
                                                initialValue:
                                                    dailyContractPeriod,
                                                isExpanded: true,
                                                decoration: InputDecoration(
                                                  labelText: 'AM / PM',
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10.r),
                                                  ),
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    horizontal: 12.w,
                                                    vertical: 10.h,
                                                  ),
                                                ),
                                                items: const [
                                                  DropdownMenuItem<String>(
                                                    value: 'AM',
                                                    child: Text('AM'),
                                                  ),
                                                  DropdownMenuItem<String>(
                                                    value: 'PM',
                                                    child: Text('PM'),
                                                  ),
                                                ],
                                                onChanged: (v) {
                                                  setState(() {
                                                    dailyContractPeriod = v;
                                                    dailyContractEndHour =
                                                        _hour24FromParts(
                                                      dailyContractHour12,
                                                      dailyContractPeriod,
                                                    );
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8.h),
                                        Text(
                                          'يُستخدم هذا الوقت تلقائيًا في جميع العقود اليومية داخل هذا المكتب.',
                                          style: GoogleFonts.tajawal(
                                            fontSize: 12.5.sp,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                Colors.black.withOpacity(0.65),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 12.h),
                                ],
                              ),
                            );
                          }

                          // عنصر العقد القابل للطي
                          Widget contractCard({
                            required String title,
                            required int minDays,
                            required int maxDays,
                            required int valueDays,
                            required ValueChanged<int> onDaysChanged,
                            required bool expanded,
                            required VoidCallback onToggleExpanded,
                            required int mode, // 0 قبل الانتهاء، 1 عند الانتهاء
                            required ValueChanged<int> onMode,
                            required TextEditingController beforeCtrl,
                            required TextEditingController onCtrl,
                            required String saveFieldDays,
                            required String saveFieldMsgBefore,
                            required String saveFieldMsgOn,
                            Widget? headerExtra,
                          }) {
                            final TextEditingController activeCtrl =
                                (mode == 0) ? beforeCtrl : onCtrl;
                            final atLimit = activeCtrl.text.length >= maxMsgLen;

                            return Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(bottom: 8.h),
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                    color: Colors.black.withOpacity(0.08)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: onToggleExpanded,
                                    borderRadius: BorderRadius.circular(12.r),
                                    child: Row(
                                      children: [
                                        Text(title,
                                            style: GoogleFonts.tajawal(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15.5.sp)),
                                        const Spacer(),
                                        Icon(expanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded),
                                      ],
                                    ),
                                  ),
                                  if (expanded) ...[
                                    SizedBox(height: 10.h),
                                    if (headerExtra != null) ...[
                                      headerExtra,
                                      SizedBox(height: 10.h),
                                    ],
                                    Text(
                                      'ملاحظة: يمكنك إضافة تنبيه قبل $minDays يوم إلى $maxDays يوم.',
                                      style: GoogleFonts.tajawal(
                                          fontSize: 13.5.sp,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              Colors.black.withOpacity(0.75)),
                                    ),
                                    SizedBox(height: 10.h),

                                    // اختيار الأيام (Slider)
                                    Row(
                                      children: [
                                        Text('أيام التنبيه مسبقًا',
                                            style: GoogleFonts.tajawal(
                                                fontWeight: FontWeight.w800)),
                                        const Spacer(),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10.w, vertical: 6.h),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF4FF),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(color: _primary),
                                          ),
                                          child: Text('$valueDays يوم',
                                              style: GoogleFonts.tajawal(
                                                  fontWeight: FontWeight.w900,
                                                  color: _primary)),
                                        ),
                                      ],
                                    ),
                                    Slider.adaptive(
                                      value: valueDays.toDouble(),
                                      min: minDays.toDouble(),
                                      max: maxDays.toDouble(),
                                      divisions: (maxDays - minDays),
                                      onChanged: (v) =>
                                          onDaysChanged(v.round()),
                                      label: '$valueDays',
                                    ),

                                    SizedBox(height: 12.h),

                                    // خيارات نوع الرسالة

                                    SizedBox(height: 10.h),
                                  ],
                                ],
                              ),
                            );
                          }

                          // عنصر عقد مبسّط لتبويب "العقود" (بدون خيار "عند الانتهاء")
                          Widget contractCardSimple({
                            required String title,
                            required int minDays,
                            required int maxDays,
                            required int valueDays,
                            required ValueChanged<int> onDaysChanged,
                            required bool expanded,
                            required VoidCallback onToggleExpanded,
                            required TextEditingController beforeCtrl,
                            required String saveFieldDays,
                            required String saveFieldMsgBefore,
                            Widget? headerExtra,
                          }) {
                            final atLimit = beforeCtrl.text.length >= maxMsgLen;
                            return Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(bottom: 8.h),
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                    color: Colors.black.withOpacity(0.08)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: onToggleExpanded,
                                    borderRadius: BorderRadius.circular(12.r),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(title,
                                              style: GoogleFonts.tajawal(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15.5.sp)),
                                        ),
                                        const Icon(Icons.expand_more_rounded,
                                            color: _primary),
                                      ],
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    crossFadeState: expanded
                                        ? CrossFadeState.showFirst
                                        : CrossFadeState.showSecond,
                                    duration: const Duration(milliseconds: 180),
                                    firstChild: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(height: 10.h),
                                        if (headerExtra != null) ...[
                                          headerExtra,
                                          SizedBox(height: 10.h),
                                        ],
                                        Row(
                                          children: [
                                            Container(
                                              width: 40.w,
                                              height: 40.w,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF4FF),
                                                borderRadius:
                                                    BorderRadius.circular(12.r),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Icon(
                                                  Icons.settings_rounded,
                                                  color: _primary),
                                            ),
                                            SizedBox(width: 10.w),
                                            Expanded(
                                              child: Text(
                                                'الإعدادات',
                                                style: GoogleFonts.tajawal(
                                                  fontSize: 18.sp,
                                                  fontWeight: FontWeight.w900,
                                                  color:
                                                      const Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 10.h),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'ذكّرني قبل (بالأيام):',
                                              style: GoogleFonts.tajawal(
                                                  fontWeight: FontWeight.w800),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 10.w,
                                                  vertical: 4.h),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF4FF),
                                                borderRadius:
                                                    BorderRadius.circular(8.r),
                                              ),
                                              child: Text(
                                                '$valueDays يوم',
                                                style: GoogleFonts.tajawal(
                                                    fontWeight: FontWeight.w900,
                                                    color: _primary),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Slider.adaptive(
                                          value: valueDays.toDouble(),
                                          min: minDays.toDouble(),
                                          max: maxDays.toDouble(),
                                          divisions: (maxDays - minDays),
                                          onChanged: (v) =>
                                              onDaysChanged(v.round()),
                                          label: '$valueDays',
                                        ),
                                        SizedBox(height: 12.h),
                                      ],
                                    ),
                                    secondChild: const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // أعلى النافذة: زر رجوع + مقبض بالوسط
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'رجوع',
                                    onPressed: () => Navigator.of(context)
                                        .pop(), // يغلق الـBottomSheet
                                    icon: Icon(
                                      Theme.of(context).platform ==
                                              TargetPlatform.iOS
                                          ? Icons.arrow_back_ios_new_rounded
                                          : Icons.arrow_back_rounded,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    width: 42.w,
                                    height: 5.h,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                              SizedBox(height: 12.h),

                              // عنوان
                              Row(
                                children: [
                                  Container(
                                    width: 40.w,
                                    height: 40.w,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF4FF),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.settings_rounded,
                                        color: _primary),
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Text(
                                      'الإعدادات',
                                      style: GoogleFonts.tajawal(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.h),

                              // 🔴 التنبيه الأحمر المختصر

                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      generalCard(),
                                      SizedBox(height: 12.h),

                                      // تبويب الاختيار بين "دورة السداد" و"العقود"
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ChoiceChip(
                                              label: Text('دورة السداد',
                                                  style: GoogleFonts.tajawal(
                                                      fontWeight:
                                                          FontWeight.w900)),
                                              selected: topTab == 0,
                                              onSelected: (_) => setState(() {
                                                topTab = 0;
                                              }),
                                            ),
                                          ),
                                          SizedBox(width: 8.w),
                                          Expanded(
                                            child: ChoiceChip(
                                              label: Text('العقود',
                                                  style: GoogleFonts.tajawal(
                                                      fontWeight:
                                                          FontWeight.w900)),
                                              selected: topTab == 1,
                                              onSelected: (_) => setState(() {
                                                topTab = 1;
                                              }),
                                            ),
                                          ),
                                        ],
                                      ),

                                      SizedBox(height: 12.h),

                                      if (topTab == 0) ...[
                                        // ---- تبويب دورة السداد (كما الوضع الحالي) ----

                                        // ✅ دفعات يومية (ثابت يوم واحد)

                                        Container(
                                          width: double.infinity,
                                          margin: EdgeInsets.only(bottom: 8.h),
                                          padding: EdgeInsets.all(12.w),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(14.r),
                                            border: Border.all(
                                                color: Colors.black
                                                    .withOpacity(0.08)),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.04),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2)),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              InkWell(
                                                onTap: () => setState(() {
                                                  dailyOpen = !dailyOpen;
                                                  if (dailyOpen) {
                                                    monthlyOpen =
                                                        quarterlyOpen =
                                                            semiOpen =
                                                                annualOpen =
                                                                    false;
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(12.r),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                        child: Text(
                                                            'دفعات يومية (يوم)',
                                                            style: GoogleFonts
                                                                .tajawal(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w900,
                                                                    fontSize: 15.5
                                                                        .sp))),
                                                    const Icon(
                                                        Icons
                                                            .expand_more_rounded,
                                                        color: _primary),
                                                  ],
                                                ),
                                              ),
                                              AnimatedCrossFade(
                                                crossFadeState: dailyOpen
                                                    ? CrossFadeState.showFirst
                                                    : CrossFadeState.showSecond,
                                                duration: const Duration(
                                                    milliseconds: 180),
                                                firstChild: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SizedBox(height: 10.h),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 40.w,
                                                          height: 40.w,
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFEFF4FF),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12.r)),
                                                          alignment:
                                                              Alignment.center,
                                                          child: const Icon(
                                                              Icons
                                                                  .settings_rounded,
                                                              color: _primary),
                                                        ),
                                                        SizedBox(width: 10.w),
                                                        Expanded(
                                                            child: Text(
                                                                'الإعدادات',
                                                                style: GoogleFonts.tajawal(
                                                                    fontSize:
                                                                        18.sp,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w900,
                                                                    color: const Color(
                                                                        0xFF0F172A)))),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10.h),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                            'ذكّرني قبل (بالأيام):',
                                                            style: GoogleFonts
                                                                .tajawal(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800)),
                                                        Container(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal:
                                                                      10.w,
                                                                  vertical:
                                                                      4.h),
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFEFF4FF),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8.r)),
                                                          child: Text('1 يوم',
                                                              style: GoogleFonts.tajawal(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  color:
                                                                      _primary)),
                                                        ),
                                                      ],
                                                    ),
                                                    GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapDown: (_) {
                                                        ScaffoldMessenger.of(
                                                                sheetCtx)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'دورة السداد اليومية: التنبيه فقط قبل يوم واحد',
                                                                    style: GoogleFonts.tajawal(
                                                                        fontWeight:
                                                                            FontWeight.w800))));
                                                      },
                                                      onHorizontalDragStart:
                                                          (_) {
                                                        ScaffoldMessenger.of(
                                                                sheetCtx)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'دورة السداد اليومية: التنبيه فقط قبل يوم واحد',
                                                                    style: GoogleFonts.tajawal(
                                                                        fontWeight:
                                                                            FontWeight.w800))));
                                                      },
                                                      child:
                                                          const AbsorbPointer(
                                                        absorbing: true,
                                                        child: Slider.adaptive(
                                                            value: 1.0,
                                                            min: 1.0,
                                                            max: 2.0,
                                                            divisions: 1,
                                                            onChanged: null,
                                                            label: '1'),
                                                      ),
                                                    ),
                                                    SizedBox(height: 8.h),
                                                    Text(
                                                        'ملاحظة: دورة السداد اليومية — التنبيه فقط قبل يوم واحد ولا يمكن تعديله.',
                                                        style: GoogleFonts.tajawal(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: const Color(
                                                                0xFFB91C1C))),
                                                  ],
                                                ),
                                                secondChild:
                                                    const SizedBox.shrink(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        contractCard(
                                          title: 'دفعات شهرية',
                                          minDays: 1,
                                          maxDays: 7,
                                          valueDays: monthlyDays,
                                          onDaysChanged: (v) =>
                                              setState(() => monthlyDays = v),
                                          expanded: monthlyOpen,
                                          onToggleExpanded: () => setState(() {
                                            monthlyOpen = !monthlyOpen;
                                            if (monthlyOpen) {
                                              dailyOpen = quarterlyOpen =
                                                  semiOpen = annualOpen = false;
                                            }
                                          }),
                                          mode: monthlyMode,
                                          onMode: (m) =>
                                              setState(() => monthlyMode = m),
                                          beforeCtrl: msgMonthlyBeforeCtrl!,
                                          onCtrl: msgMonthlyOnCtrl!,
                                          saveFieldDays: 'notif_monthly_days',
                                          saveFieldMsgBefore:
                                              'notif_monthly_msg_before',
                                          saveFieldMsgOn:
                                              'notif_monthly_msg_on',
                                        ),
                                        contractCard(
                                          title: 'دفعات 3 شهور (ربع سنوي)',
                                          minDays: 1,
                                          maxDays: 15,
                                          valueDays: quarterlyDays,
                                          onDaysChanged: (v) =>
                                              setState(() => quarterlyDays = v),
                                          expanded: quarterlyOpen,
                                          onToggleExpanded: () => setState(() {
                                            quarterlyOpen = !quarterlyOpen;
                                            if (quarterlyOpen) {
                                              dailyOpen = monthlyOpen =
                                                  semiOpen = annualOpen = false;
                                            }
                                          }),
                                          mode: quarterlyMode,
                                          onMode: (m) =>
                                              setState(() => quarterlyMode = m),
                                          beforeCtrl: msgQuarterlyBeforeCtrl!,
                                          onCtrl: msgQuarterlyOnCtrl!,
                                          saveFieldDays: 'notif_quarterly_days',
                                          saveFieldMsgBefore:
                                              'notif_quarterly_msg_before',
                                          saveFieldMsgOn:
                                              'notif_quarterly_msg_on',
                                        ),
                                        contractCard(
                                          title: 'دفعات 6 شهور (نصف سنوي)',
                                          minDays: 1,
                                          maxDays: 30,
                                          valueDays: semiDays,
                                          onDaysChanged: (v) =>
                                              setState(() => semiDays = v),
                                          expanded: semiOpen,
                                          onToggleExpanded: () => setState(() {
                                            semiOpen = !semiOpen;
                                            if (semiOpen) {
                                              dailyOpen = monthlyOpen =
                                                  quarterlyOpen =
                                                      annualOpen = false;
                                            }
                                          }),
                                          mode: semiMode,
                                          onMode: (m) =>
                                              setState(() => semiMode = m),
                                          beforeCtrl: msgSemiBeforeCtrl!,
                                          onCtrl: msgSemiOnCtrl!,
                                          saveFieldDays:
                                              'notif_semiannual_days',
                                          saveFieldMsgBefore:
                                              'notif_semiannual_msg_before',
                                          saveFieldMsgOn:
                                              'notif_semiannual_msg_on',
                                        ),
                                        contractCard(
                                          title: 'دفعات سنوية',
                                          minDays: 1,
                                          maxDays: 45,
                                          valueDays: annualDays,
                                          onDaysChanged: (v) => setState(() {
                                            annualDays = v;
                                            annualYearsDays[
                                                annualSelectedYears] = v;
                                          }),
                                          expanded: annualOpen,
                                          onToggleExpanded: () => setState(() {
                                            annualOpen = !annualOpen;
                                            if (annualOpen) {
                                              dailyOpen = monthlyOpen =
                                                  quarterlyOpen =
                                                      semiOpen = false;
                                            }
                                          }),
                                          mode: annualMode,
                                          onMode: (m) =>
                                              setState(() => annualMode = m),
                                          beforeCtrl: msgAnnualBeforeCtrl!,
                                          onCtrl: msgAnnualOnCtrl!,
                                          saveFieldDays: 'notif_annual_days',
                                          saveFieldMsgBefore:
                                              'notif_annual_msg_before',
                                          saveFieldMsgOn: 'notif_annual_msg_on',
                                          headerExtra: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'المدة السنوية',
                                                  style: GoogleFonts.tajawal(
                                                      fontWeight:
                                                          FontWeight.w800),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 150.w,
                                                child: DropdownButtonFormField<
                                                    int>(
                                                  initialValue:
                                                      annualSelectedYears,
                                                  isDense: true,
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10.w,
                                                            vertical: 8.h),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10.r),
                                                    ),
                                                  ),
                                                  items: List.generate(10, (i) {
                                                    final y = i + 1;
                                                    return DropdownMenuItem<
                                                        int>(
                                                      value: y,
                                                      child: Text(
                                                        y == 1
                                                            ? 'سنة'
                                                            : '$y سنوات',
                                                        style:
                                                            GoogleFonts.tajawal(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700),
                                                      ),
                                                    );
                                                  }),
                                                  onChanged: (v) {
                                                    if (v == null) return;
                                                    setState(() {
                                                      annualSelectedYears = v;
                                                      annualDays =
                                                          annualYearsDays[v] ??
                                                              45;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        // ---- تبويب العقود (بدون 'عند الانتهاء') ----

                                        // ✅ عقد يومي (ثابت يوم واحد)

                                        Container(
                                          width: double.infinity,
                                          margin: EdgeInsets.only(bottom: 8.h),
                                          padding: EdgeInsets.all(12.w),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(14.r),
                                            border: Border.all(
                                                color: Colors.black
                                                    .withOpacity(0.08)),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.04),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2)),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              InkWell(
                                                onTap: () => setState(() {
                                                  cDailyOpen = !cDailyOpen;
                                                  if (cDailyOpen) {
                                                    cMonthlyOpen =
                                                        cQuarterlyOpen =
                                                            cSemiOpen =
                                                                cAnnualOpen =
                                                                    false;
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(12.r),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                        child: Text(
                                                            'عقد يومي (يوم)',
                                                            style: GoogleFonts
                                                                .tajawal(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w900,
                                                                    fontSize: 15.5
                                                                        .sp))),
                                                    const Icon(
                                                        Icons
                                                            .expand_more_rounded,
                                                        color: _primary),
                                                  ],
                                                ),
                                              ),
                                              AnimatedCrossFade(
                                                crossFadeState: cDailyOpen
                                                    ? CrossFadeState.showFirst
                                                    : CrossFadeState.showSecond,
                                                duration: const Duration(
                                                    milliseconds: 180),
                                                firstChild: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SizedBox(height: 10.h),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 40.w,
                                                          height: 40.w,
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFEFF4FF),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12.r)),
                                                          alignment:
                                                              Alignment.center,
                                                          child: const Icon(
                                                              Icons
                                                                  .settings_rounded,
                                                              color: _primary),
                                                        ),
                                                        SizedBox(width: 10.w),
                                                        Expanded(
                                                            child: Text(
                                                                'الإعدادات',
                                                                style: GoogleFonts.tajawal(
                                                                    fontSize:
                                                                        18.sp,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w900,
                                                                    color: const Color(
                                                                        0xFF0F172A)))),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10.h),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                            'ذكّرني قبل (بالأيام):',
                                                            style: GoogleFonts
                                                                .tajawal(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800)),
                                                        Container(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal:
                                                                      10.w,
                                                                  vertical:
                                                                      4.h),
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFEFF4FF),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8.r)),
                                                          child: Text('1 يوم',
                                                              style: GoogleFonts.tajawal(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  color:
                                                                      _primary)),
                                                        ),
                                                      ],
                                                    ),
                                                    GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapDown: (_) {
                                                        ScaffoldMessenger.of(
                                                                sheetCtx)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'التنبيه فقط قبل يوم واحد من العقد اليومي ولا يمكن تغييره',
                                                                    style: GoogleFonts.tajawal(
                                                                        fontWeight:
                                                                            FontWeight.w800))));
                                                      },
                                                      onHorizontalDragStart:
                                                          (_) {
                                                        ScaffoldMessenger.of(
                                                                sheetCtx)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'التنبيه فقط قبل يوم واحد من العقد اليومي ولا يمكن تغييره',
                                                                    style: GoogleFonts.tajawal(
                                                                        fontWeight:
                                                                            FontWeight.w800))));
                                                      },
                                                      child:
                                                          const AbsorbPointer(
                                                        absorbing: true,
                                                        child: Slider.adaptive(
                                                            value: 1.0,
                                                            min: 1.0,
                                                            max: 2.0,
                                                            divisions: 1,
                                                            onChanged: null,
                                                            label: '1'),
                                                      ),
                                                    ),
                                                    SizedBox(height: 8.h),
                                                    Text(
                                                        'ملاحظة: العقد اليومي — التنبيه فقط قبل يوم واحد ولا يمكن تغييره.',
                                                        style: GoogleFonts.tajawal(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: const Color(
                                                                0xFFB91C1C))),
                                                  ],
                                                ),
                                                secondChild:
                                                    const SizedBox.shrink(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        contractCardSimple(
                                          title: 'عقد شهري (شهر)',
                                          minDays: 1,
                                          maxDays: 7,
                                          valueDays: cMonthlyDays,
                                          onDaysChanged: (v) =>
                                              setState(() => cMonthlyDays = v),
                                          expanded: cMonthlyOpen,
                                          onToggleExpanded: () => setState(() {
                                            cMonthlyOpen = !cMonthlyOpen;
                                            if (cMonthlyOpen) {
                                              cDailyOpen = cQuarterlyOpen =
                                                  cSemiOpen =
                                                      cAnnualOpen = false;
                                            }
                                          }),
                                          beforeCtrl: cMsgMonthlyBeforeCtrl!,
                                          saveFieldDays:
                                              'notif_contract_monthly_days',
                                          saveFieldMsgBefore:
                                              'notif_contract_monthly_msg_before',
                                        ),
                                        contractCardSimple(
                                          title: 'عقد 3 شهور (ربع سنوي)',
                                          minDays: 1,
                                          maxDays: 15,
                                          valueDays: cQuarterlyDays,
                                          onDaysChanged: (v) => setState(
                                              () => cQuarterlyDays = v),
                                          expanded: cQuarterlyOpen,
                                          onToggleExpanded: () => setState(() {
                                            cQuarterlyOpen = !cQuarterlyOpen;
                                            if (cQuarterlyOpen) {
                                              cDailyOpen = cMonthlyOpen =
                                                  cSemiOpen =
                                                      cAnnualOpen = false;
                                            }
                                          }),
                                          beforeCtrl: cMsgQuarterlyBeforeCtrl!,
                                          saveFieldDays:
                                              'notif_contract_quarterly_days',
                                          saveFieldMsgBefore:
                                              'notif_contract_quarterly_msg_before',
                                        ),
                                        contractCardSimple(
                                          title: 'عقد 6 شهور (نصف سنوي)',
                                          minDays: 1,
                                          maxDays: 30,
                                          valueDays: cSemiDays,
                                          onDaysChanged: (v) =>
                                              setState(() => cSemiDays = v),
                                          expanded: cSemiOpen,
                                          onToggleExpanded: () => setState(() {
                                            cSemiOpen = !cSemiOpen;
                                            if (cSemiOpen) {
                                              cDailyOpen = cMonthlyOpen =
                                                  cQuarterlyOpen =
                                                      cAnnualOpen = false;
                                            }
                                          }),
                                          beforeCtrl: cMsgSemiBeforeCtrl!,
                                          saveFieldDays:
                                              'notif_contract_semiannual_days',
                                          saveFieldMsgBefore:
                                              'notif_contract_semiannual_msg_before',
                                        ),
                                        contractCardSimple(
                                          title: 'عقد سنوي (سنة)',
                                          minDays: 1,
                                          maxDays: 45,
                                          valueDays: cAnnualDays,
                                          onDaysChanged: (v) => setState(() {
                                            cAnnualDays = v;
                                            cAnnualYearsDays[
                                                cAnnualSelectedYears] = v;
                                          }),
                                          expanded: cAnnualOpen,
                                          onToggleExpanded: () => setState(() {
                                            cAnnualOpen = !cAnnualOpen;
                                            if (cAnnualOpen) {
                                              cDailyOpen = cMonthlyOpen =
                                                  cQuarterlyOpen =
                                                      cSemiOpen = false;
                                            }
                                          }),
                                          beforeCtrl: cMsgAnnualBeforeCtrl!,
                                          saveFieldDays:
                                              'notif_contract_annual_days',
                                          saveFieldMsgBefore:
                                              'notif_contract_annual_msg_before',
                                          headerExtra: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'مدة العقد السنوي',
                                                  style: GoogleFonts.tajawal(
                                                      fontWeight:
                                                          FontWeight.w800),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 150.w,
                                                child: DropdownButtonFormField<
                                                    int>(
                                                  initialValue:
                                                      cAnnualSelectedYears,
                                                  isDense: true,
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10.w,
                                                            vertical: 8.h),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10.r),
                                                    ),
                                                  ),
                                                  items: List.generate(10, (i) {
                                                    final y = i + 1;
                                                    return DropdownMenuItem<
                                                        int>(
                                                      value: y,
                                                      child: Text(
                                                        y == 1
                                                            ? 'سنة'
                                                            : '$y سنوات',
                                                        style:
                                                            GoogleFonts.tajawal(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700),
                                                      ),
                                                    );
                                                  }),
                                                  onChanged: (v) {
                                                    if (v == null) return;
                                                    setState(() {
                                                      cAnnualSelectedYears = v;
                                                      cAnnualDays =
                                                          cAnnualYearsDays[v] ??
                                                              45;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      // ✅ زر إعادة ضبط كامل — في نهاية الشاشة تحت عقد سنوي
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          // 🚫 منع عميل المكتب من إعادة الضبط
                                          if (await OfficeClientGuard
                                              .blockIfOfficeClient(sheetCtx)) {
                                            return;
                                          }

                                          await _confirmFactoryReset(sheetCtx);
                                        },
                                        icon: const Icon(
                                            Icons.delete_forever_rounded),
                                        label: Text('إعادة ضبط كامل',
                                            style: GoogleFonts.tajawal(
                                                fontWeight: FontWeight.w900)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFEF4444),
                                          foregroundColor: Colors.white,
                                          minimumSize:
                                              Size(double.infinity, 46.h),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12.r)),
                                        ),
                                      ),

                                      SizedBox(height: 28.h),
                                    ],
                                  ),
                                ),
                              ),

                              // زر إغلاق
                              Row(
                                children: [
                                  Expanded(
                                      child: ElevatedButton(
                                    onPressed: () async {
                                      // 🚫 منع عميل المكتب من حفظ الإعدادات
                                      if (await OfficeClientGuard
                                          .blockIfOfficeClient(sheetCtx)) {
                                        return;
                                      }

                                      final hasPartialDailyTime =
                                          (dailyContractHour12 == null) !=
                                              (dailyContractPeriod == null);
                                      if (hasPartialDailyTime) {
                                        ScaffoldMessenger.of(sheetCtx)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'حدد الساعة ونوعها AM / PM لوقت انتهاء العقود اليومية.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      _saveSettings({
                                        // الإعدادات العامة
                                        'settings_language': 'ar',
                                        'settings_date_system': dateSystem,
                                        _kDailyContractEndHourField:
                                            _hour24FromParts(
                                          dailyContractHour12,
                                          dailyContractPeriod,
                                        ),
                                        // دورة السداد
                                        'notif_monthly_days': monthlyDays,
                                        'notif_monthly_msg_before':
                                            msgMonthlyBeforeCtrl!.text,
                                        'notif_monthly_msg_on':
                                            msgMonthlyOnCtrl!.text,
                                        'notif_quarterly_days': quarterlyDays,
                                        'notif_quarterly_msg_before':
                                            msgQuarterlyBeforeCtrl!.text,
                                        'notif_quarterly_msg_on':
                                            msgQuarterlyOnCtrl!.text,
                                        'notif_semiannual_days': semiDays,
                                        'notif_semiannual_msg_before':
                                            msgSemiBeforeCtrl!.text,
                                        'notif_semiannual_msg_on':
                                            msgSemiOnCtrl!.text,
                                        'notif_annual_days':
                                            (annualYearsDays[1] ?? annualDays),
                                        'notif_annual_msg_before':
                                            msgAnnualBeforeCtrl!.text,
                                        'notif_annual_msg_on':
                                            msgAnnualOnCtrl!.text,
                                        for (int y = 1; y <= 10; y++)
                                          'notif_annual_${y}y_days':
                                              (annualYearsDays[y] ??
                                                      annualYearsDays[1] ??
                                                      annualDays)
                                                  .clamp(1, 45),
                                        // العقود
                                        'notif_contract_monthly_days':
                                            cMonthlyDays,
                                        'notif_contract_monthly_msg_before':
                                            cMsgMonthlyBeforeCtrl!.text,
                                        'notif_contract_quarterly_days':
                                            cQuarterlyDays,
                                        'notif_contract_quarterly_msg_before':
                                            cMsgQuarterlyBeforeCtrl!.text,
                                        'notif_contract_semiannual_days':
                                            cSemiDays,
                                        'notif_contract_semiannual_msg_before':
                                            cMsgSemiBeforeCtrl!.text,
                                        'notif_contract_annual_days':
                                            (cAnnualYearsDays[1] ??
                                                cAnnualDays),
                                        'notif_contract_annual_msg_before':
                                            cMsgAnnualBeforeCtrl!.text,
                                        for (int y = 1; y <= 10; y++)
                                          'notif_contract_annual_${y}y_days':
                                              (cAnnualYearsDays[y] ??
                                                      cAnnualYearsDays[1] ??
                                                      cAnnualDays)
                                                  .clamp(1, 45),
                                      }, sheetCtx);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.r)),
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12.h),
                                    ),
                                    child: Text('حفظ',
                                        style: GoogleFonts.tajawal(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white)),
                                  )),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // نافذة "اتصل بنا"
  // نافذة "اتصل بنا"
  void _showSupportDialog(BuildContext context) {
    const primary = _primary;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),

          // شريط عنوان بخلفية
          titlePadding: EdgeInsets.zero,
          title: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF), // أزرق فاتح مناسب للدعم
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.support_agent_rounded,
                    color: Color(0xFF0D9488), size: 22),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'اتصل بنا',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w900,
                      fontSize: 16.sp,
                      color: const Color(0xFF0D9488),
                      height: 1.0,
                    ),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // محتوى بخلفية ناعمة وإطار
          contentPadding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          content: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: EdgeInsets.all(12.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إذا واجهت مشكلة أو لديك استفسار، يسعد فريق الدعم بمساعدتك. راسلنا عبر البريد التالي:',
                  style: GoogleFonts.tajawal(
                      fontSize: 14.sp,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155)),
                ),
                SizedBox(height: 8.h),
                SelectableText(
                  'support@darvoo.com',
                  style: GoogleFonts.tajawal(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w900,
                      color: primary),
                ),
              ],
            ),
          ),

          // زر إغلاق في المنتصف وبخلفية
          actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 180.w,
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFECEFF1),
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFECEFF1)),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text('إغلاق',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة "من نحن"
  // نافذة "من نحن"
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),

          // شريط عنوان بخلفية
          titlePadding: EdgeInsets.zero,
          title: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF), // بنفسجي فاتح للمعلومات
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF8B5CF6), size: 22),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'من نحن',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w900,
                      fontSize: 16.sp,
                      color: const Color(0xFF7C3AED),
                      height: 1.0,
                    ),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // محتوى بخلفية ناعمة وإطار
          contentPadding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          content: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF5FF),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE9D5FF)),
            ),
            padding: EdgeInsets.all(12.w),
            child: Text(
              'دارفو تطبيق لإدارة العقارات والعقود بسهولة وكفاءة، مخصص للمالكين والمكاتب العقارية لمتابعة الأملاك والمستأجرين والدفعات والتقارير في مكان واحد.',
              style: GoogleFonts.tajawal(
                  fontSize: 14.sp,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4C1D95)),
              textAlign: TextAlign.right,
            ),
          ),

          // زر إغلاق في المنتصف وبخلفية
          actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 180.w,
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFECEFF1),
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFECEFF1)),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text('إغلاق',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // تأكيد وتسجيل الخروج
  Future<void> _confirmAndLogout(BuildContext context) async {
    final bool ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تسجيل الخروج',
      message:
          'هل تريد تسجيل الخروج الآن؟ لإدارة عقاراتك لاحقًا ستحتاج إلى تسجيل الدخول من جديد.',
      confirmLabel: 'تأكيد الخروج',
      cancelLabel: 'إلغاء',
    );

    // منطق ما بعد التأكيد (كما لديك)
// منطق ما بعد التأكيد (كما لديك)
    if (ok == true) {
      Navigator.of(context).maybePop(); // أغلق الدرج إن كان مفتوحًا

      try {
        await ActivityLogService.instance.logAuth(
          actionType: 'logout',
          description: 'تم تسجيل الخروج.',
        );
      } catch (_) {}

      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      // 🧹 مسح آخر مستخدم مسجّل دخول تلقائيًا
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('last_login_email');
        await sp.remove('last_login_uid');
        await sp.remove('last_login_role');
        await sp.remove('last_login_offline');
      } catch (_) {}

      if (Hive.isBoxOpen('sessionBox')) {
        final session = Hive.box('sessionBox');
        await session.put('loggedIn', false);
        await session.put('isOfficeClient', false); // ✅ رجّع الوضع الطبيعي
      }

      // 👇 امسح أي UID ثابت من user_scope حتى لا يرثه الدخول التالي
      scope.clearFixedUid();

      await OfficeClientGuard.refreshFromLocal(); // ✅ حدّث الكاش في الحارس

      await Future.delayed(const Duration(milliseconds: 150));
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // صانع أيقونة ملوّنة دائرية
  Widget _coloredIcon({
    required IconData icon,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: 20.sp),
    );
  }

  // يخفي بند "اشتراكي" إذا كان المستخدم عميل مكتب
  Future<bool> _shouldHideSubscription() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return false; // الضيف/غير مسجل → لا نخفي

      // 1) نفحص الـ claims أولًا (أسرع)
      try {
        final id = await u.getIdTokenResult();
        final c = id.claims ?? {};
        final viaClaims = (c['officeId'] != null) ||
            (c['office_id'] != null) ||
            (c['is_office_client'] == true) ||
            (c['createdByRole'] == 'office');
        if (viaClaims) return true;
      } catch (_) {}

      // 2) نفحص وثيقة users/{uid}
      final m = await _safeReadDocData(
        FirebaseFirestore.instance.collection('users').doc(u.uid),
        timeout: const Duration(seconds: 5),
      );
      final viaDoc = (m['officeId'] != null) ||
          (m['office_id'] != null) ||
          (m['origin'] == 'officeClient') ||
          (m['createdByRole'] == 'office') ||
          (m['is_office_client'] == true);
      if (viaDoc) return true;

      // 3) تحقّق إضافي: هل uid موجود تحت أي offices/*/clients/*
      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
        if (cg.docs.isNotEmpty) return true;
      } catch (_) {}

      return false;
    } catch (_) {
      return false; // عند الخطأ لا نخفي
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.tajawal(
      fontSize: 16.sp,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF0F172A),
    );
    final itemStyle = GoogleFonts.tajawal(
      fontSize: 14.sp,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF0F172A),
    );

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Drawer(
        backgroundColor: _drawerBg,
        child: SafeArea(
          child: Column(
            children: [
              // رأس مع الشعار
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 10.h),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36.w,
                      height: 36.w,
                      child: Image.asset('assets/images/app_logo.png',
                          fit: BoxFit.contain),
                    ),
                    SizedBox(width: 10.w),
                    Text('Darvoo', style: titleStyle),
                  ],
                ),
              ),
              const Divider(height: 1),

// 1) اشتراكي (مخفية لعميل المكتب)
              FutureBuilder<bool>(
                future: _shouldHideSubscription(),
                initialData: false, // 👈 مهم: نظهر "اشتراكي" فورًا بشكل افتراضي
                builder: (_, snap) {
                  final hide = snap.data ?? false; // لو طلع عميل مكتب نخفيه
                  if (hide) return const SizedBox.shrink();
                  return ListTile(
                    leading: _coloredIcon(
                      icon: Icons.card_membership_rounded,
                      bg: const Color(0xFFE6FFFA),
                      fg: const Color(0xFF14B8A6),
                    ),
                    title: Text('اشتراكي', style: itemStyle),
                    onTap: () => _openSubscription(context),
                  );
                },
              ),

              // 1.5) الإعدادات
              ListTile(
                leading: _coloredIcon(
                  icon: Icons.settings_rounded,
                  bg: const Color(0xFFEFF4FF),
                  fg: _primary,
                ),
                title: Text('الإعدادات', style: itemStyle),
                onTap: () => _openSettings(context),
              ),

              // 2) سياسة الاستخدام
              ListTile(
                leading: _coloredIcon(
                  icon: Icons.description_rounded,
                  bg: const Color(0xFFFFF7ED),
                  fg: const Color(0xFFF59E0B),
                ),
                title: Text('سياسة الاستخدام', style: itemStyle),
                onTap: () {
                  Navigator.of(context).maybePop();
                  _openExternal(context, _termsUri);
                },
              ),

              // 3) سياسة الخصوصية
              ListTile(
                leading: _coloredIcon(
                  icon: Icons.privacy_tip_rounded,
                  bg: const Color(0xFFEFFBF6),
                  fg: const Color(0xFF10B981),
                ),
                title: Text('سياسة الخصوصية', style: itemStyle),
                onTap: () {
                  Navigator.of(context).maybePop();
                  _openExternal(context, _privacyUri);
                },
              ),

              // 4) من نحن
              ListTile(
                leading: _coloredIcon(
                  icon: Icons.info_outline_rounded,
                  bg: const Color(0xFFF3E8FF),
                  fg: const Color(0xFF8B5CF6),
                ),
                title: Text('من نحن', style: itemStyle),
                onTap: () {
                  _showAboutDialog(context); // لا تغلق الدرج
                },
              ),

              // 5) اتصل بنا
              ListTile(
                leading: _coloredIcon(
                  icon: Icons.support_agent_rounded,
                  bg: const Color(0xFFEFF4FF),
                  fg: _primary,
                ),
                title: Text('اتصل بنا', style: itemStyle),
                onTap: () {
                  _showSupportDialog(context); // لا تغلق الدرج
                },
              ),

              const Spacer(),

              // تسجيل الخروج
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                  leading: _coloredIcon(
                    icon: Icons.logout_rounded,
                    bg: const Color(0xFFFFEFEF),
                    fg: const Color(0xFFEF4444),
                  ),
                  title: Text(
                    'تسجيل الخروج',
                    style: GoogleFonts.tajawal(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                  onTap: () => _confirmAndLogout(context),
                ),
              ),

              Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Text(
                  'الإصدار 1.0.3',
                  style: GoogleFonts.tajawal(
                    fontSize: 12.sp,
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionData {
  final String email;

  final String planDurationLabel; // مثل: 1 شهر / 3 شهور / 6 شهور / سنة
  final String planPriceLabel; // مثل: 499 SAR

  final String? startKsaText; // yyyy-MM-dd
  final String? endKsaText; // yyyy-MM-dd

  final DateTime? startAtUtc; // UTC
  final DateTime? endAtUtc; // UTC (حصرية)

  final DateTime? endInclusiveKsaDateOnly;

  final bool active;
  final int daysLeft;
  final String packageName;
  final String officeUsersDisplay;
  final String clientsDisplay;
  final String propertiesDisplay;

  _SubscriptionData({
    required this.email,
    required this.planDurationLabel,
    required this.planPriceLabel,
    required this.startKsaText,
    required this.endKsaText,
    required this.startAtUtc,
    required this.endAtUtc,
    required this.endInclusiveKsaDateOnly,
    required this.active,
    required this.daysLeft,
    required this.packageName,
    required this.officeUsersDisplay,
    required this.clientsDisplay,
    required this.propertiesDisplay,
  });

  bool get hasPackageDetails =>
      packageName.trim().isNotEmpty ||
      officeUsersDisplay != 'غير محدد' ||
      clientsDisplay != 'غير محدد' ||
      propertiesDisplay != 'غير محدد';

  factory _SubscriptionData.empty({required String email}) => _SubscriptionData(
        email: email,
        planDurationLabel: '—',
        planPriceLabel: '—',
        startKsaText: null,
        endKsaText: null,
        startAtUtc: null,
        endAtUtc: null,
        endInclusiveKsaDateOnly: null,
        active: false,
        daysLeft: 0,
        packageName: '',
        officeUsersDisplay: 'غير محدد',
        clientsDisplay: 'غير محدد',
        propertiesDisplay: 'غير محدد',
      );
}

class _SettingsData {
  final String language; // 'ar'
  final String dateSystem; // 'gregorian' | 'hijri'
  final int monthlyDays;
  final int quarterlyDays;
  final int semiAnnualDays;
  final int annualDays;
  // تبويب العقود
  final int contractMonthlyDays;
  final int contractQuarterlyDays;
  final int contractSemiAnnualDays;
  final int contractAnnualDays;
  final Map<int, int> annualYearsDays;
  final Map<int, int> contractAnnualYearsDays;

  final String contractMonthlyMsgBefore;
  final String contractQuarterlyMsgBefore;
  final String contractSemiAnnualMsgBefore;
  final String contractAnnualMsgBefore;
  final int? dailyContractEndHour;

  // رسائل قبل الانتهاء
  final String monthlyMsgBefore;
  final String quarterlyMsgBefore;
  final String semiAnnualMsgBefore;
  final String annualMsgBefore;

  // رسائل عند الانتهاء
  final String monthlyMsgOn;
  final String quarterlyMsgOn;
  final String semiAnnualMsgOn;
  final String annualMsgOn;

  _SettingsData({
    required this.language,
    required this.dateSystem,
    required this.monthlyDays,
    required this.quarterlyDays,
    required this.semiAnnualDays,
    required this.annualDays,
    required this.monthlyMsgBefore,
    required this.quarterlyMsgBefore,
    required this.semiAnnualMsgBefore,
    required this.annualMsgBefore,
    required this.monthlyMsgOn,
    required this.quarterlyMsgOn,
    required this.semiAnnualMsgOn,
    required this.annualMsgOn,
    required this.contractMonthlyDays,
    required this.contractQuarterlyDays,
    required this.contractSemiAnnualDays,
    required this.contractAnnualDays,
    required this.annualYearsDays,
    required this.contractAnnualYearsDays,
    required this.contractMonthlyMsgBefore,
    required this.contractQuarterlyMsgBefore,
    required this.contractSemiAnnualMsgBefore,
    required this.contractAnnualMsgBefore,
    required this.dailyContractEndHour,
  });

  factory _SettingsData.empty() => _SettingsData(
        language: 'ar',
        dateSystem: 'gregorian',
        monthlyDays: 7,
        quarterlyDays: 15,
        semiAnnualDays: 30,
        annualDays: 45,
        monthlyMsgBefore: AppSideDrawer._kDefaultMsg,
        quarterlyMsgBefore: AppSideDrawer._kDefaultMsg,
        semiAnnualMsgBefore: AppSideDrawer._kDefaultMsg,
        annualMsgBefore: AppSideDrawer._kDefaultMsg,
        monthlyMsgOn: AppSideDrawer._kDefaultMsgEnded,
        quarterlyMsgOn: AppSideDrawer._kDefaultMsgEnded,
        semiAnnualMsgOn: AppSideDrawer._kDefaultMsgEnded,
        annualMsgOn: AppSideDrawer._kDefaultMsgEnded,
        // تبويب العقود (قيم افتراضية)
        contractMonthlyDays: 7,
        contractQuarterlyDays: 15,
        contractSemiAnnualDays: 30,
        contractAnnualDays: 45,
        annualYearsDays: {for (var y = 1; y <= 10; y++) y: 45},
        contractAnnualYearsDays: {for (var y = 1; y <= 10; y++) y: 45},
        contractMonthlyMsgBefore: AppSideDrawer._kDefaultMsg,
        contractQuarterlyMsgBefore: AppSideDrawer._kDefaultMsg,
        contractSemiAnnualMsgBefore: AppSideDrawer._kDefaultMsg,
        contractAnnualMsgBefore: AppSideDrawer._kDefaultMsg,
        dailyContractEndHour: null,
      );
}

class _CardSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w900, fontSize: 15.5.sp)),
              const Spacer(),
            ],
          ),
          SizedBox(height: 10.h),
          child,
        ],
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  final String label;
  final String value;
  final bool wrap; // للسماح بلف النص (مثل البريد الإلكتروني)
  final double labelWidth; // عرض عمود التسمية (يمينه)
  final double valueWidth; // عرض عمود القيمة (بجواره مباشرة)

  const _RowItem({
    required this.label,
    required this.value,
    this.wrap = false,
    required this.labelWidth,
    required this.valueWidth,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      textAlign: TextAlign.right,
      softWrap: wrap,
      overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
      maxLines: wrap ? null : 1,
      style: GoogleFonts.tajawal(
        fontSize: 14.sp,
        fontWeight: FontWeight.w900,
        color: const Color(0xFF0F172A),
      ),
    );

    return Row(
      crossAxisAlignment:
          wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: Colors.black.withOpacity(0.70),
            ),
          ),
        ),
        SizedBox(width: 50.w),
        SizedBox(
          width: valueWidth,
          child: valueText,
        ),
        const Spacer(),
      ],
    );
  }
}
