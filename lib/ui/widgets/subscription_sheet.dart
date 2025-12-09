// lib/ui/widgets/subscription_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

Future<void> showSubscriptionSheet(
  BuildContext context, {
  required String email,
  required DateTime startAt,
  required DateTime endAt,
  String? plan,    // شهري/3 شهور/6 شهور/سنوي
  String? status,  // active/expired
}) async {
  const primary = Color(0xFF1E40AF);

  // دالة صغيرة لتحويل أي DateTime إلى "تاريخ فقط" بتوقيت السعودية (UTC+3)
  DateTime _toKsaDateOnly(DateTime dt) {
    final utc = dt.toUtc();                       // نتأكد أنه UTC
    final ksa = utc.add(const Duration(hours: 3)); // نحوله لـ KSA
    return DateTime(ksa.year, ksa.month, ksa.day); // نحذف الساعة ونحتفظ باليوم فقط
  }

  // ✅ نثبت أن البداية والنهاية حسب تاريخ السعودية فقط
  final startDateKsa = _toKsaDateOnly(startAt);
  final endDateKsa   = _toKsaDateOnly(endAt);

  // ✅ اليوم الحالي بتوقيت السعودية
  final nowDateKsa   = _toKsaDateOnly(DateTime.now());

  // ✅ الأيام المتبقية = الفرق بين تاريخ نهاية الاشتراك وتاريخ اليوم في السعودية
  final leftDays = endDateKsa.difference(nowDateKsa).inDays;

  // حالة الاشتراك
  final active = leftDays >= 0 && (status ?? 'active') == 'active';

  // فورمات التاريخ
  final df = DateFormat('yyyy/MM/dd', 'ar');



  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withOpacity(0.35),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22.r))),
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض صغير
            Center(
              child: Container(
                width: 42.w, height: 5.h,
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
            ),

            // العنوان + شارة الحالة
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
                    style: GoogleFonts.tajawal(fontSize: 18.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
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
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: active ? const Color(0xFF059669) : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),

            // البيانات
            _RowItem(label: 'البريد الإلكتروني', value: email),
            SizedBox(height: 8.h),
            _RowItem(label: 'الخطة', value: plan ?? '—'),
            SizedBox(height: 8.h),
_RowItem(label: 'تاريخ البداية', value: df.format(startDateKsa)),
SizedBox(height: 8.h),
_RowItem(label: 'تاريخ الانتهاء', value: df.format(endDateKsa)),
SizedBox(height: 8.h),

if (active) _RowItem(label: 'الأيام المتبقية', value: '$leftDays يوم'),


            if (!active)
              Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                  'انتهى اشتراكك — يرجى التجديد لمتابعة إدارة عقاراتك.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontSize: 13.sp, fontWeight: FontWeight.w800, color: const Color(0xFFB91C1C)),
                ),
              ),

            SizedBox(height: 14.h),

            // الأزرار
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
                    child: Text('إغلاق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, color: primary)),
                  ),
                ),
                SizedBox(width: 10.w),
                if (!active)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: الانتقال لبوابة التجديد/الدفع
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      child: Text('تجديد الاشتراك', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RowItem extends StatelessWidget {
  final String label;
  final String value;
  const _RowItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: GoogleFonts.tajawal(fontSize: 14.sp, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.70))),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.tajawal(fontSize: 14.sp, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
