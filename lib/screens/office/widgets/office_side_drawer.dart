// lib/screens/office/widgets/office_side_drawer.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/user_scope.dart' as scope;
import '../../../data/services/office_client_guard.dart';


/// بديل خفيف لـ KsaTime داخل الملف
class _KsaTime {
  static const Duration _ksaOffset = Duration(hours: 3);
  static DateTime toKsa(DateTime dt) {
    final u = dt.isUtc ? dt : dt.toUtc();
    return u.add(_ksaOffset);
  }
  static DateTime nowKsa() => DateTime.now().toUtc().add(_ksaOffset);
  static DateTime dateOnly(DateTime ksa) => DateTime(ksa.year, ksa.month, ksa.day);
}

class OfficeSideDrawer extends StatelessWidget {
  const OfficeSideDrawer({super.key});

  static const Color _drawerBg = Color(0xFFFFFBEB);
  static const Color _primary  = Color(0xFF1E40AF);

  static final Uri _privacyUri = Uri.parse('https://www.notion.so/darvoo-2c2c4186d1998080a134eeba1cc8e0b6?source=copy_link');
  static final Uri _termsUri   = Uri.parse('https://www.notion.so/darvoo-2-2c2c4186d199809995f2e4168dd95d75?source=copy_link');

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الرابط.')),
      );
    }
  }

  // -------------------- اشتراكي --------------------
  static DateTime? _parseDateUtc(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is DateTime) return v.toUtc();
    if (v is String) { try { return DateTime.parse(v).toUtc(); } catch (_) {} }
    return null;
  }

  DateTime? _parseKsaYmdToUtcMidnight(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      final parts = t.replaceAll('/', '-').split('-');
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      return DateTime.utc(y, m, d).subtract(const Duration(hours: 3));
    } catch (_) {
      return null;
    }
  }

  DateTime? _ksaDateOnlyFromKsaText(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final utcMid = _parseKsaYmdToUtcMidnight(t.replaceAll('/', '-'));
    if (utcMid == null) return null;
    return _KsaTime.dateOnly(_KsaTime.toKsa(utcMid));
  }

  int? _extractMonths(Map<String, dynamic> data) {
    final pm = data['planMonths'];
    if (pm is num) return pm.toInt();
    final dur = data['duration'];
    if (dur is String && dur.trim().isNotEmpty) {
      final m = RegExp(r'(\d+)m').firstMatch(dur.trim().toLowerCase());
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  String _durationLabelFromMonths(int m) {
    switch (m) {
      case 1:  return '1 شهر';
      case 3:  return '3 شهور';
      case 6:  return '6 شهور';
      case 12: return 'سنة';
      default: return '$m شهر';
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
      final currency = (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
      return _formatMoney(v, currency);
    }
    for (final k in [
      'plan_price','price','amount','subscription_price','amount_sar',
      'plan_amount','plan_cost','billing_amount','price_sar',
    ]) {
      final val = data[k];
      if (val is num) {
        final currency = (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
        return _formatMoney(val, currency);
      }
      if (val is String && val.trim().isNotEmpty) {
        final cleaned = val.replaceAll(RegExp(r'[^\d\.\-]'), '');
        final num? n = num.tryParse(cleaned);
        if (n != null) {
          final currency = (data['currency'] ?? data['plan_currency'] ?? 'SAR').toString();
          return _formatMoney(n, currency);
        }
      }
    }
    return '—';
  }

  Future<_SubscriptionData> _fetchSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '—';
    if (user == null) return _SubscriptionData.empty(email: email);

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};

    final startKsaText = (data['start_date_ksa'] as String?)?.trim();
    final endKsaText   = (data['end_date_ksa']   as String?)?.trim();

    final startAtUtc = _parseDateUtc(data['subscription_start']);
    final endAtUtc   = _parseDateUtc(data['subscription_end']); // حصرية

    final todayKsaDate = _KsaTime.dateOnly(_KsaTime.nowKsa());

    DateTime? endInclusiveKsaDateOnly;
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final endMidUtc = _parseKsaYmdToUtcMidnight(endKsaText);
      if (endMidUtc != null) {
        endInclusiveKsaDateOnly = _KsaTime.dateOnly(_KsaTime.toKsa(endMidUtc));
      }
    }
if (endInclusiveKsaDateOnly == null && endAtUtc != null) {
  // نعتبر أن subscription_end هو نفسه تاريخ نهاية الاشتراك بتوقيت السعودية
  final endKsa = _KsaTime.toKsa(endAtUtc);

  // ❌ لا نطرح أي يوم هنا
  endInclusiveKsaDateOnly = _KsaTime.dateOnly(endKsa);
}


    final bool active = endInclusiveKsaDateOnly != null && !endInclusiveKsaDateOnly.isBefore(todayKsaDate);
    final int daysLeft = active ? (endInclusiveKsaDateOnly!.difference(todayKsaDate).inDays + 1) : 0;

    final months = _extractMonths(data);
    final planDurationLabel = months != null ? _durationLabelFromMonths(months) : '—';
    final planPriceLabel = _extractPlanPriceLabel(data);

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
    );
  }

  Future<void> _openSubscription(BuildContext context) async {
    const primary = _primary;
    final df = DateFormat('yyyy/MM/dd', 'ar');

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22.r))),
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h + MediaQuery.of(context).viewInsets.bottom),
          child: FutureBuilder<_SubscriptionData>(
            future: _fetchSubscription(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return SizedBox(height: 180.h, child: const Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return SizedBox(
                  height: 180.h,
                  child: Center(
                    child: Text(
                      'تعذّر تحميل تفاصيل الاشتراك.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, color: Colors.red),
                    ),
                  ),
                );
              }

              final sub = snap.data ?? _SubscriptionData.empty(email: '—');
              final active   = sub.active;
              final leftDays = sub.daysLeft;

              final DateTime? startKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.startKsaText) ??
                  (sub.startAtUtc != null ? _KsaTime.dateOnly(_KsaTime.toKsa(sub.startAtUtc!)) : null);
              final String startStr = startKsaDateOnly == null ? '—' : df.format(startKsaDateOnly);

              final DateTime? endKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.endKsaText) ?? sub.endInclusiveKsaDateOnly;
              final String endStr = endKsaDateOnly == null ? '—' : df.format(endKsaDateOnly);

              final double labelW = 110.w;
              final double valueW = 180.w;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42.w, height: 5.h,
                    margin: EdgeInsets.only(bottom: 12.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 40.w, height: 40.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.card_membership_rounded, color: primary),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          'اشتراكي',
                          style: GoogleFonts.tajawal(
                            fontSize: 18.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFFEFFBF6) : const Color(0xFFFFEFEF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: active ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                        ),
                        child: Text(
                          active ? 'فعّال' : 'منتهي',
                          style: GoogleFonts.tajawal(
                            fontSize: 12.sp, fontWeight: FontWeight.w900,
                            color: active ? const Color(0xFF059669) : const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),

                  _RowItem(label: 'البريد الإلكتروني', value: sub.email, wrap: true, labelWidth: labelW, valueWidth: valueW),
                  SizedBox(height: 8.h),
                  _RowItem(label: 'الخطة', value: sub.planDurationLabel, labelWidth: labelW, valueWidth: valueW),
                  SizedBox(height: 8.h),
                  _RowItem(label: 'تاريخ البداية', value: startStr, labelWidth: labelW, valueWidth: valueW),
                  SizedBox(height: 8.h),
                  _RowItem(label: 'تاريخ الانتهاء', value: endStr, labelWidth: labelW, valueWidth: valueW),
                  SizedBox(height: 8.h),
                  _RowItem(label: 'قيمة الخطة', value: sub.planPriceLabel, labelWidth: labelW, valueWidth: valueW),
                  SizedBox(height: 8.h),
                  _RowItem(label: 'الأيام المتبقية', value: active ? '$leftDays يوم' : '0 يوم', labelWidth: labelW, valueWidth: valueW),

                               SizedBox(height: 14.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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
              );
            },
          ),
        ),
      ),
    );
  }

   // نافذة "من نحن"
void _showAboutDialog(BuildContext context) {
  showDialog(
    context: context,
    useRootNavigator: true,
    builder: (dialogCtx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),

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
              const Icon(Icons.info_outline_rounded, color: Color(0xFF8B5CF6), size: 22),
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
                    applyHeightToFirstAscent: false, applyHeightToLastDescent: false,
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
            style: GoogleFonts.tajawal(fontSize: 14.sp, height: 1.6, fontWeight: FontWeight.w700, color: const Color(0xFF4C1D95)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
              child: Text('إغلاق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    ),
  );
}


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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),

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
              const Icon(Icons.support_agent_rounded, color: Color(0xFF1D4ED8), size: 22),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'اتصل بنا',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900,
                    fontSize: 16.sp,
                    color: const Color(0xFF1D4ED8),
                    height: 1.0,
                  ),
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false, applyHeightToLastDescent: false,
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
                style: GoogleFonts.tajawal(fontSize: 14.sp, height: 1.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
              ),
              SizedBox(height: 8.h),
              SelectableText(
                'support@darvoo.com',
                style: GoogleFonts.tajawal(fontSize: 15.sp, fontWeight: FontWeight.w900, color: primary),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
              child: Text('إغلاق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    ),
  );
}


  
  // تأكيد وتسجيل الخروج
Future<void> _confirmAndLogout(BuildContext context) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogCtx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),

        // شريط عنوان بخلفية رقيقة ومقاس مضبوط
        titlePadding: EdgeInsets.zero,
        title: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'تسجيل الخروج',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w900,
                    fontSize: 17.sp,                // أكبر من نص المحتوى
                    color: const Color(0xFFB91C1C),
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

        contentPadding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
        content: Text(
          'هل تريد تسجيل الخروج الآن؟ لإدارة عقاراتك لاحقًا ستحتاج إلى تسجيل الدخول من جديد.',
          style: GoogleFonts.tajawal(fontSize: 14.sp, height: 1.5, fontWeight: FontWeight.w700),
          textAlign: TextAlign.right,
        ),

        // أزرار تحت بعض: تأكيد ثم إلغاء
        actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // تأكيد الخروج (أول زر)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: Text('تأكيد الخروج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
                ),
              ),
              SizedBox(height: 10.h),
              // إلغاء (زر ثاني بخلفية فاتحة ونفس المقاس)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFECEFF1),
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFECEFF1)),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: Text('إلغاء', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // منطق ما بعد التأكيد (كما لديك)
// منطق ما بعد التأكيد (كما لديك)
if (ok == true) {
  Navigator.of(context).maybePop(); // أغلق الدرج إن كان مفتوحًا

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

  await OfficeClientGuard.refreshFromLocal();    // ✅ حدّث الكاش في الحارس

  await Future.delayed(const Duration(milliseconds: 150));
  // ignore: use_build_context_synchronously
  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
}

}


  Widget _coloredIcon({
    required IconData icon,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      width: 36.w, height: 36.w,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: 20.sp),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.tajawal(
      fontSize: 16.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A),
    );
    final itemStyle = GoogleFonts.tajawal(
      fontSize: 14.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A),
    );

    // ✅ إزاحة اللوح كاملًا تحت شريط الـAppBar (حل جذري)
    final double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      // لاحظ: نُمرّر Widget للـScaffold.drawer، ليس من الضروري أن يكون Drawer مباشرة.
      child: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Drawer(
          backgroundColor: _drawerBg,
          child: SafeArea(
            top: false, // لأننا أزحنا اللوح كاملًا للأعلى بالفعل
            child: Column(
              children: [
                // رأس: شعار + اسم التطبيق
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 10.h),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36.w, height: 36.w,
                        child: Image.asset('assets/images/app_logo.png', fit: BoxFit.contain),
                      ),
                      SizedBox(width: 10.w),
                      Text('Darvoo', style: titleStyle),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // اشتراكي
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.card_membership_rounded,
                    bg: const Color(0xFFE6FFFA),
                    fg: const Color(0xFF14B8A6),
                  ),
                  title: Text('اشتراكي', style: itemStyle),
                  onTap: () => _openSubscription(context),
                ),

              // سياسة الاستخدام
ListTile(
  leading: _coloredIcon(
    icon: Icons.description_rounded,
    bg: const Color(0xFFFFF7ED),
    fg: const Color(0xFFF59E0B),
  ),
  title: Text('سياسة الاستخدام', style: itemStyle),
  onTap: () {
    // ❌ لا نستدعي maybePop هنا
    _openExternal(context, _termsUri); // ✅ فتح رابط سياسة الاستخدام مباشرة
  },
),

// سياسة الخصوصية
ListTile(
  leading: _coloredIcon(
    icon: Icons.privacy_tip_rounded,
    bg: const Color(0xFFEFFBF6),
    fg: const Color(0xFF10B981),
  ),
  title: Text('سياسة الخصوصية', style: itemStyle),
  onTap: () {
    // ❌ لا نستدعي maybePop هنا
    _openExternal(context, _privacyUri); // ✅ فتح رابط سياسة الخصوصية مباشرة
  },
),


                // من نحن
ListTile(
  leading: _coloredIcon(
    icon: Icons.info_outline_rounded,
    bg: const Color(0xFFF3E8FF),
    fg: const Color(0xFF8B5CF6),
  ),
  title: Text('من نحن', style: itemStyle),
  onTap: () {
    // ❌ لا تغلق القائمة، ولا تستدعي maybePop
    _showAboutDialog(context);  // ✅ افتح نافذة "من نحن" فقط
  },
),



                // اتصل بنا
ListTile(
  leading: _coloredIcon(
    icon: Icons.support_agent_rounded,
    bg: const Color(0xFFEFF4FF),
    fg: _primary,
  ),
  title: Text('اتصل بنا', style: itemStyle),
  onTap: () {
    // ❌ لا تغلق الدرج
    _showSupportDialog(context);  // ✅ فقط افتح نافذة اتصل بنا
  },
),


                const Spacer(),

                // تسجيل الخروج
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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
      ),
    );
  }
}

// -------------------- نماذج مساعدة --------------------
class _SubscriptionData {
  final String email;
  final String planDurationLabel;
  final String planPriceLabel;
  final String? startKsaText;
  final String? endKsaText;
  final DateTime? startAtUtc;
  final DateTime? endAtUtc;
  final DateTime? endInclusiveKsaDateOnly;
  final bool active;
  final int daysLeft;

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
  });

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
      );
}

class _RowItem extends StatelessWidget {
  final String label;
  final String value;
  final bool wrap;
  final double labelWidth;
  final double valueWidth;

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
        fontSize: 14.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A),
      ),
    );

    return Row(
      crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(
              fontSize: 14.sp, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.70),
            ),
          ),
        ),
        SizedBox(width: 50.w),
        SizedBox(width: valueWidth, child: valueText),
        const Spacer(),
      ],
    );
  }
}
