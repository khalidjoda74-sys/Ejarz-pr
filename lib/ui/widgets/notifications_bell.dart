// lib/ui/widgets/notifications_bell.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// إشعارات الاشتراك
import '../../data/services/subscription_alerts.dart';

// فحص الدور
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// لوحة المكتب + Runtime (للتنظيف فقط)
import '../../screens/office/office.dart'; // OfficeHomePage و OfficeRuntime.clear()

class NotificationsBell extends StatefulWidget {
  final Future<DateTime?> Function() subscriptionEndProvider;
  final VoidCallback? onOpenSheetOverride;

  // تخصيص مظهر الأيقونة:
  final Color iconColor;
  final double? iconSize;

  const NotificationsBell({
    super.key,
    required this.subscriptionEndProvider,
    this.onOpenSheetOverride,
    this.iconColor = Colors.white,
    this.iconSize,
  });

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell>
    with WidgetsBindingObserver {
  int _badge = 0;
  SubscriptionAlert? _pending;
  Timer? _midnightTimer;

  bool? _isOffice;
  bool _isImpersonating = false;

  // ===== Overlay spinner (نفس دائرة لوحة المكتب) =====
  OverlayEntry? _spinner;

  void _showSpinner() {
    if (_spinner != null) return;
    final entry = OverlayEntry(
      builder: (_) => const _OfficeStyleSpinnerOverlay(),
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;
    overlay.insert(entry);
    _spinner = entry;
  }

  void _hideSpinner() {
    try {
      _spinner?.remove();
    } catch (_) {}
    _spinner = null;
  }

  Future<T> _withSpinner<T>(Future<T> Function() task) async {
    _showSpinner();
    try {
      // إطار واحد لرسم اللودر
      await Future.delayed(const Duration(milliseconds: 16));
      return await task();
    } finally {
      if (mounted) _hideSpinner();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOfficeOrImpersonation();
    _refresh();
    _scheduleNextCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _hideSpinner(); // تأكد من إزالة أي Overlay قبل التخلص
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOfficeOrImpersonation();
      _refresh();
    }
  }

  Future<void> _checkOfficeOrImpersonation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isOffice = false;
          _isImpersonating = false;
        });
      }
      return;
    }

    var office = false;
    var impersonating = false;

    try {
      final token = await user.getIdTokenResult(); // بدون true
      final claims = token.claims ?? {};
      if (claims['role'] == 'office' || claims['office'] == true) {
        office = true;
      }
      if (claims['impersonatedBy'] != null) {
        impersonating = true;
      }
    } catch (_) {/* ignore */}

    if (!office && !impersonating) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = snap.data() ?? {};
        if (data['role'] == 'office' || data['isOffice'] == true) {
          office = true;
        }
      } catch (_) {/* ignore */}
    }

    if (!mounted) return;
    setState(() {
      _isOffice = office;
      _isImpersonating = impersonating;
    });
  }

  void _scheduleNextCheck() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1, minutes: 1));
    _midnightTimer = Timer(next.difference(now), () {
      _refresh();
      _scheduleNextCheck();
    });
  }

  Future<void> _refresh() async {
    if (_isOffice == true || _isImpersonating == true) return;
    final endAt = await widget.subscriptionEndProvider();
    final alert = SubscriptionAlerts.compute(endAt: endAt);
    if (!mounted) return;
    setState(() {
      _pending = alert;
      _badge = alert == null ? 0 : 1;
    });
  }

  Future<void> _openSheet() async {
    if (widget.onOpenSheetOverride != null) {
      widget.onOpenSheetOverride!.call();
      return;
    }
    if (_pending == null) return;
    final alert = _pending!;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final df = DateFormat('d MMMM yyyy', 'ar');
        return Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.notifications_active,
                    size: 24.sp, color: const Color(0xFFDC2626)),
                SizedBox(width: 8.w),
                Text('التنبيهات',
                    style: GoogleFonts.cairo(
                        fontSize: 18.sp, fontWeight: FontWeight.w800)),
              ]),
              SizedBox(height: 12.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.45)),
                ),
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 22.sp, color: const Color(0xFFF59E0B)),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alert.title,
                              style: GoogleFonts.tajawal(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 6.h),
                          Text(alert.body,
                              style: GoogleFonts.tajawal(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF111827))),
                          SizedBox(height: 8.h),
                          Text('تاريخ الانتهاء: ${df.format(alert.endAt)}',
                              style: GoogleFonts.tajawal(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6B7280))),
                        ]),
                  ),
                ]),
              ),
              SizedBox(height: 16.h),
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 44.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r)),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: Text('إغلاق',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800, fontSize: 15.sp)),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  /// مصادقة رجوع لصلاحية المكتب أثناء الانتحال — دون أي تنقّل هنا
  /// تُعيد true عند النجاح، أو ترمي استثناء عند الفشل.
  Future<bool> _returnToOfficeAuthOnly() async {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('officeReturnToSelf');
    final res = await callable.call(<String, dynamic>{});
    final data = (res.data is Map) ? (res.data as Map) : const {};
    final token = (data['customToken'] as String?) ?? '';

    if (token.isEmpty) {
      throw Exception('لا يوجد توكن عودة صالح.');
    }

    await FirebaseAuth.instance.signInWithCustomToken(token);
    final idTok =
        await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
    final role = idTok?.claims?['role']?.toString();
    if (role != 'office') {
      throw Exception('تعذّر التأكد من صلاحية المكتب بعد الرجوع.');
    }

    // نظّف اختيار العميل المؤقت
    OfficeRuntime.clear();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // مكتب أو انتحال → نعرض زر تبديل (سهم دائري)
    if (_isOffice == true || _isImpersonating == true) {
      return IconButton(
        tooltip: _isImpersonating
            ? 'وضع الاستبدال — الرجوع للمكتب'
            : 'لوحة المكتب',
        icon: Icon(Icons.autorenew_rounded,
            size: widget.iconSize ?? 26.sp, color: widget.iconColor),
        onPressed: () async {
          if (_isImpersonating == true) {
            // رجوع فعلي للمكتب مع دائرة التحميل (Overlay)
            try {
              final ok = await _withSpinner(() => _returnToOfficeAuthOnly());
              if (!mounted) return;
              if (ok) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const OfficeHomePage()),
                  (r) => false,
                );
              }
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('فشل الرجوع للمكتب: ${e.toString()}')),
              );
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (r) => false);
            }
          } else {
            // مكتب أصلًا: إظهار الدائرة بشكل سريع ثم فتح لوحة المكتب
            await _withSpinner(() async {
              OfficeRuntime.clear();
              await Future.delayed(const Duration(milliseconds: 150));
            });
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OfficeHomePage()),
            );
          }
        },
      );
    }

    // أثناء الفحص: مساحة فارغة تمنع الوميض
    if (_isOffice == null) {
      return SizedBox(
        width: (widget.iconSize ?? 26.sp) + 16,
        height: (widget.iconSize ?? 26.sp) + 16,
      );
    }

    // غير مكتب وغير منتحل → الجرس
    // غير مكتب وغير منتحل → الجرس

// لو فيه تنبيه (badge) نخلي اللون نشِط، بدون تنبيه يكون خامل (باهت)
final bool hasAlert = _badge > 0;
final Color bellColor = hasAlert
    ? widget.iconColor
    : widget.iconColor.withOpacity(0.35);

return Stack(
  children: [
    IconButton(
      onPressed: _openSheet,
      icon: Icon(
        Icons.notifications_none_rounded,
        size: widget.iconSize ?? 26.sp,
        color: bellColor, // ← هنا استخدمنا اللون حسب حالة التنبيه
      ),
      tooltip: 'التنبيهات',
    ),
    if (hasAlert)
      Positioned(
        right: 6.w,
        top: 6.h,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.0),
          ),
          child: Text(
            '$_badge',
            style: GoogleFonts.cairo(
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
  ],
);

  }
}

/// ===== ويدجت دائرة الانتظار بنمط لوحة المكتب (شفافة + إطار) =====
class _OfficeStyleSpinnerOverlay extends StatelessWidget {
  const _OfficeStyleSpinnerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.transparent, // “فاضية”
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: const CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
