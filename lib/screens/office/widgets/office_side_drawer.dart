// lib/screens/office/widgets/office_side_drawer.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:darvoo/widgets/custom_confirm_dialog.dart';

import '../../../data/services/user_scope.dart' as scope;
import '../../../data/services/office_client_guard.dart';
import '../../../data/services/package_limit_service.dart';
import '../office_users_screen.dart';

//
class _KsaTime {
  static const Duration _ksaOffset = Duration(hours: 3);
  static DateTime toKsa(DateTime dt) {
    final u = dt.isUtc ? dt : dt.toUtc();
    return u.add(_ksaOffset);
  }

  static DateTime nowKsa() => KsaTime.now();
  static DateTime dateOnly(DateTime ksa) =>
      DateTime(ksa.year, ksa.month, ksa.day);
}

class OfficeSideDrawer extends StatelessWidget {
  const OfficeSideDrawer({super.key});

  static const Color _drawerBg = Color(0xFFFFFBEB);
  static const Color _primary = Color(0xFF0F766E);

  static final Uri _privacyUri = Uri.parse(
      'https://www.notion.so/darvoo-2c2c4186d1998080a134eeba1cc8e0b6?source=copy_link');
  static final Uri _termsUri = Uri.parse(
      'https://www.notion.so/darvoo-2-2c2c4186d199809995f2e4168dd95d75?source=copy_link');
  static const String _officeProfilePrefsPrefix = 'office_profile_v1_';

  String _traceNowIso() => DateTime.now().toIso8601String();

  String _compactStackTrace(StackTrace stackTrace, [int maxLines = 3]) {
    return stackTrace
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(maxLines)
        .join(' | ');
  }

  void _traceDrawer(String scope, String message) {
    debugPrint('[OfficeDrawerTrace][${_traceNowIso()}][$scope] $message');
  }

  String? _officeWorkspaceUid() {
    final scopedUid = scope.effectiveUid();
    if (scopedUid.isNotEmpty && scopedUid != 'guest') return scopedUid;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<Map<String, dynamic>> _safeReadDocData(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration timeout = const Duration(seconds: 8),
    String traceLabel = '',
  }) async {
    final sw = Stopwatch()..start();
    final label = traceLabel.trim().isEmpty ? ref.path : traceLabel.trim();
    _traceDrawer(
      'Firestore',
      'doc-get start label=$label path=${ref.path} timeoutMs=${timeout.inMilliseconds}',
    );
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      _traceDrawer(
        'Firestore',
        'doc-get hit source=server label=$label exists=${snap.exists} fromCache=${snap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return snap.data() ?? const <String, dynamic>{};
    } on TimeoutException catch (e, st) {
      _traceDrawer(
        'Firestore',
        'doc-get timeout label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        _traceDrawer(
          'Firestore',
          'doc-get hit source=cache-after-timeout label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
        );
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (cacheError, cacheStack) {
        _traceDrawer(
          'Firestore',
          'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${_compactStackTrace(cacheStack)}',
        );
        return const <String, dynamic>{};
      }
    } catch (e, st) {
      _traceDrawer(
        'Firestore',
        'doc-get error label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        _traceDrawer(
          'Firestore',
          'doc-get hit source=cache-after-error label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
        );
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (cacheError, cacheStack) {
        _traceDrawer(
          'Firestore',
          'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${_compactStackTrace(cacheStack)}',
        );
        return const <String, dynamic>{};
      }
    }
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط.')),
      );
    }
  }

  Future<T?> _runFromDrawerRoot<T>(
    BuildContext context, {
    required Future<T?> Function(NavigatorState rootNavigator) action,
    required String traceLabel,
  }) async {
    final sw = Stopwatch()..start();
    _traceDrawer(
      'Navigation',
      'drawer-action start label=$traceLabel authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${scope.effectiveUid()}',
    );
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    _traceDrawer(
      'Navigation',
      'drawer-action drawer-pop label=$traceLabel +${sw.elapsedMilliseconds}ms',
    );
    await Future<void>.delayed(Duration.zero);
    if (!rootNavigator.mounted) {
      _traceDrawer(
        'Navigation',
        'drawer-action abort root-navigator-unmounted label=$traceLabel +${sw.elapsedMilliseconds}ms',
      );
      return null;
    }
    try {
      final result = await action(rootNavigator);
      _traceDrawer(
        'Navigation',
        'drawer-action done label=$traceLabel +${sw.elapsedMilliseconds}ms',
      );
      return result;
    } catch (e, st) {
      _traceDrawer(
        'Navigation',
        'drawer-action error label=$traceLabel +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      rethrow;
    }
  }

  //
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
    return months != null ? _durationLabelFromMonths(months) : '-';
  }

  String _durationLabelFromMonths(int m) {
    switch (m) {
      case 1:
        return 'شهر';
      case 3:
        return '3 أشهر';
      case 6:
        return '6 أشهر';
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
    return '-';
  }

  Future<_SubscriptionData> _fetchSubscription() async {
    final sw = Stopwatch()..start();
    final user = FirebaseAuth.instance.currentUser;
    final officeUid = _officeWorkspaceUid();
    final email = user?.email ?? '-';
    _traceDrawer(
      'Subscription',
      'fetch start authUid=${user?.uid ?? ''} officeUid=${officeUid ?? ''} email=$email',
    );
    if (user == null || officeUid == null || officeUid.isEmpty) {
      _traceDrawer(
        'Subscription',
        'fetch abort missing-user-or-office authUid=${user?.uid ?? ''} officeUid=${officeUid ?? ''} +${sw.elapsedMilliseconds}ms',
      );
      return _SubscriptionData.empty(email: email);
    }

    try {
      final data = await _safeReadDocData(
        FirebaseFirestore.instance.collection('users').doc(officeUid),
        traceLabel: 'subscription users/$officeUid',
      );

      final startKsaText = (data['start_date_ksa'] as String?)?.trim();
      final endKsaText = (data['end_date_ksa'] as String?)?.trim();

      final startAtUtc = _parseDateUtc(data['subscription_start']);
      final endAtUtc = _parseDateUtc(data['subscription_end']);

      final todayKsaDate = _KsaTime.dateOnly(_KsaTime.nowKsa());

      DateTime? endInclusiveKsaDateOnly;
      if (endKsaText != null && endKsaText.isNotEmpty) {
        final endMidUtc = _parseKsaYmdToUtcMidnight(endKsaText);
        if (endMidUtc != null) {
          endInclusiveKsaDateOnly =
              _KsaTime.dateOnly(_KsaTime.toKsa(endMidUtc));
        }
      }
      if (endInclusiveKsaDateOnly == null && endAtUtc != null) {
        final endKsa = _KsaTime.toKsa(endAtUtc);

        endInclusiveKsaDateOnly = _KsaTime.dateOnly(endKsa);
      }

      final bool active = endInclusiveKsaDateOnly != null &&
          !endInclusiveKsaDateOnly.isBefore(todayKsaDate);
      final int daysLeft = active
          ? (endInclusiveKsaDateOnly.difference(todayKsaDate).inDays + 1)
          : 0;

      final planDurationLabel = _extractPlanDurationLabel(data);
      final planPriceLabel = _extractPlanPriceLabel(data);
      final packageSnapshot = OfficePackageSnapshot.fromUserDoc(data);

      _traceDrawer(
        'Subscription',
        'fetch success officeUid=$officeUid active=$active daysLeft=$daysLeft startKsa=$startKsaText endKsa=$endKsaText +${sw.elapsedMilliseconds}ms',
      );

      return _SubscriptionData(
        email: (data['email'] ?? email).toString(),
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
    } catch (e, st) {
      _traceDrawer(
        'Subscription',
        'fetch error officeUid=$officeUid +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      rethrow;
    }
  }

  Future<void> _openSubscription(BuildContext context) async {
    const primary = _primary;
    final df = DateFormat('yyyy/MM/dd', 'ar');
    final sw = Stopwatch()..start();
    final future = _fetchSubscription();
    _traceDrawer(
      'Subscription',
      'sheet-open start officeUid=${_officeWorkspaceUid() ?? ''}',
    );

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
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
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return SizedBox(
                    height: 180.h,
                    child: const Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return SizedBox(
                  height: 180.h,
                  child: Center(
                    child: Text(
                      'تعذر تحميل تفاصيل الاشتراك.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w900, color: Colors.red),
                    ),
                  ),
                );
              }

              final sub = snap.data ?? _SubscriptionData.empty(email: '-');
              final active = sub.active;
              final leftDays = sub.daysLeft;

              final DateTime? startKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.startKsaText) ??
                      (sub.startAtUtc != null
                          ? _KsaTime.dateOnly(_KsaTime.toKsa(sub.startAtUtc!))
                          : null);
              final String startStr =
                  startKsaDateOnly == null ? '-' : df.format(startKsaDateOnly);

              final DateTime? endKsaDateOnly =
                  _ksaDateOnlyFromKsaText(sub.endKsaText) ??
                      sub.endInclusiveKsaDateOnly;
              final String endStr =
                  endKsaDateOnly == null ? '-' : df.format(endKsaDateOnly);

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
                              active ? 'فعال' : 'منتهي',
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
                              child: Text('إغلاق',
                                  style: GoogleFonts.tajawal(
                                      fontWeight: FontWeight.w900,
                                      color: primary)),
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
    _traceDrawer(
      'Subscription',
      'sheet-close officeUid=${_officeWorkspaceUid() ?? ''} +${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _openMyProfile(BuildContext context) async {
    const primary = _primary;
    final user = FirebaseAuth.instance.currentUser;
    final officeUid = _officeWorkspaceUid();
    if (user == null || officeUid == null || officeUid.isEmpty) return;

    final initial = await _fetchOfficeProfile();
    const allowedWorkTypes = {'مكتب', 'مؤسسة'};
    String workType =
        allowedWorkTypes.contains(initial.workType) ? initial.workType : '';
    final officeNameCtl = TextEditingController(text: initial.officeName);
    final addressCtl = TextEditingController(text: initial.address);
    final commercialCtl = TextEditingController(text: initial.commercialNo);
    final mobileCtl = TextEditingController(text: initial.mobile);
    final phoneCtl = TextEditingController(text: initial.phone);
    String logoBase64 = initial.logoBase64;
    String? workTypeError;
    bool isSaving = false;

    void showError(String msg, [BuildContext? targetCtx]) {
      final messenger = ScaffoldMessenger.maybeOf(targetCtx ?? context) ??
          ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
            content: Text(msg,
                style: GoogleFonts.tajawal(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        );
    }

    void showSuccess(String msg, [BuildContext? targetCtx]) {
      final messenger = ScaffoldMessenger.maybeOf(targetCtx ?? context) ??
          ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(msg,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
        );
    }

    Future<void> save(
        BuildContext dialogCtx, void Function(VoidCallback fn) setModal) async {
      if (isSaving) return;
      FocusScope.of(dialogCtx).unfocus();
      setModal(() => isSaving = true);

      final officeName = officeNameCtl.text.trim();
      final selectedWorkType = workType.trim();
      final address = addressCtl.text.trim();
      final commercialNo = commercialCtl.text.trim();
      final mobile = mobileCtl.text.trim();
      final phone = phoneCtl.text.trim();

      if (selectedWorkType.isEmpty) {
        setModal(() => workTypeError = 'يجب اختيار جهة العمل.');
        setModal(() => isSaving = false);
        return;
      }
      if (logoBase64.isNotEmpty && logoBase64.length > 700000) {
        showError('تعذر حفظ الشعار: حجم الصورة كبير.', dialogCtx);
        setModal(() => isSaving = false);
        return;
      }

      try {
        final profilePayload = <String, dynamic>{
          'office_name': officeName,
          'work_type': selectedWorkType,
          'address': address,
          'commercial_no': commercialNo,
          'mobile': mobile,
          'phone': phone,
          'logo_base64': logoBase64,
          'updated_at': KsaTime.nowUtc().toIso8601String(),
        };

        // Save locally first so the UI always responds even if cloud fails.
        await _saveOfficeProfileLocal(officeUid, profilePayload);

        // Cloud sync is best-effort and should not block the local save UX.
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(officeUid)
              .set({
            'office_profile': {
              ...profilePayload,
              'updated_at': FieldValue.serverTimestamp(),
            }
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 20));
        } catch (e) {
          debugPrint('office profile cloud sync failed: $e');
        }

        if (!dialogCtx.mounted) return;
        Navigator.of(dialogCtx).pop();
        showSuccess('تم حفظ بيانات المكتب بنجاح.', context);
      } catch (_) {
        if (!dialogCtx.mounted) return;
        showError('تعذر حفظ البيانات. حاول مرة أخرى.', dialogCtx);
      } finally {
        if (dialogCtx.mounted) {
          setModal(() => isSaving = false);
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22.r))),
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setM) {
            Uint8List? logoBytes() {
              final raw = logoBase64.trim();
              if (raw.isEmpty) return null;
              try {
                return base64Decode(raw);
              } catch (_) {
                return null;
              }
            }

            Future<void> pickLogo() async {
              if (isSaving) return;
              final picked = await FilePicker.platform.pickFiles(
                withData: true,
                type: FileType.custom,
                allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
              );
              if (picked == null || picked.files.isEmpty) return;

              final f = picked.files.first;
              Uint8List? bytes = f.bytes;
              if (bytes == null && (f.path ?? '').isNotEmpty) {
                try {
                  bytes = await File(f.path!).readAsBytes();
                } catch (_) {}
              }
              if (bytes == null || bytes.isEmpty) return;

              final optimized = await _optimizeLogoBase64(bytes);
              if (optimized == null) {
                showError('تعذر حفظ الشعار: حجم الصورة كبير جدًا.');
                return;
              }

              logoBase64 = optimized;
              setM(() {});
            }

            String valueOrDash(String v) => v.trim().isEmpty ? '-' : v.trim();

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w,
                      16.h + MediaQuery.of(ctx).viewInsets.bottom),
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
                                borderRadius: BorderRadius.circular(8.r))),
                        Center(
                            child: Text('بياناتي',
                                style: GoogleFonts.tajawal(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A)))),
                        SizedBox(height: 12.h),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14.r),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0))),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(valueOrDash(officeNameCtl.text),
                                        style: GoogleFonts.tajawal(
                                            fontSize: 17.sp,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF0F172A))),
                                    SizedBox(height: 3.h),
                                    Text(
                                        'العنوان: ${valueOrDash(addressCtl.text)}',
                                        style: GoogleFonts.tajawal(
                                            color: const Color(0xFF334155),
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        'رقم السجل: ${valueOrDash(commercialCtl.text)}',
                                        style: GoogleFonts.tajawal(
                                            color: const Color(0xFF334155),
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        'الجوال: ${valueOrDash(mobileCtl.text)}',
                                        style: GoogleFonts.tajawal(
                                            color: const Color(0xFF334155),
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        'الهاتف: ${valueOrDash(phoneCtl.text)}',
                                        style: GoogleFonts.tajawal(
                                            color: const Color(0xFF334155),
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Container(
                                width: 58.w,
                                height: 58.w,
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10.r),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0))),
                                clipBehavior: Clip.antiAlias,
                                child: logoBytes() == null
                                    ? Icon(Icons.business_rounded,
                                        color: const Color(0xFF94A3B8),
                                        size: 22.sp)
                                    : Image.memory(
                                        logoBytes()!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.business_rounded,
                                          color: const Color(0xFF94A3B8),
                                          size: 22.sp,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12.h),
                        TextField(
                            controller: officeNameCtl,
                            maxLength: 40,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            decoration: const InputDecoration(
                                labelText: 'اسم المكتب', counterText: ''),
                            onChanged: (_) => setM(() {})),
                        SizedBox(height: 8.h),
                        DropdownButtonFormField<String>(
                          initialValue: workType.isEmpty ? null : workType,
                          decoration: InputDecoration(
                            labelText: 'جهة العمل',
                            errorText: workTypeError,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'مكتب', child: Text('مكتب')),
                            DropdownMenuItem(
                                value: 'مؤسسة', child: Text('مؤسسة')),
                          ],
                          onChanged: isSaving
                              ? null
                              : (v) {
                                  workType = (v ?? '').trim();
                                  workTypeError = null;
                                  setM(() {});
                                },
                        ),
                        SizedBox(height: 8.h),
                        TextField(
                            controller: addressCtl,
                            maxLength: 40,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            decoration: const InputDecoration(
                                labelText: 'العنوان', counterText: ''),
                            onChanged: (_) => setM(() {})),
                        SizedBox(height: 8.h),
                        TextField(
                            controller: commercialCtl,
                            maxLength: 15,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'رقم السجل', counterText: '')),
                        SizedBox(height: 8.h),
                        TextField(
                            controller: mobileCtl,
                            maxLength: 10,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'رقم الجوال', counterText: '')),
                        SizedBox(height: 8.h),
                        TextField(
                            controller: phoneCtl,
                            maxLength: 10,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'رقم الهاتف', counterText: '')),
                        SizedBox(height: 8.h),
                        Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                                onPressed: isSaving ? null : pickLogo,
                                icon: const Icon(Icons.image_rounded),
                                label: Text('إرفاق شعار المكتب',
                                    style: GoogleFonts.tajawal(
                                        fontWeight: FontWeight.w800)))),
                        SizedBox(height: 10.h),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: primary),
                                onPressed:
                                    isSaving ? null : () => save(ctx, setM),
                                child: isSaving
                                    ? SizedBox(
                                        height: 18.h,
                                        width: 18.h,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Text('حفظ',
                                        style: GoogleFonts.tajawal(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900)),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () => Navigator.of(ctx).pop(),
                                    child: Text('إلغاء',
                                        style: GoogleFonts.tajawal(
                                            fontWeight: FontWeight.w900)))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSaving)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withOpacity(0.08),
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                              SizedBox(width: 10.w),
                              Text(
                                'جاري الحفظ',
                                style: GoogleFonts.tajawal(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

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
          titlePadding: EdgeInsets.zero,
          title: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
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
                    '\u0645\u0646 \u0646\u062d\u0646',
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
          contentPadding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          content: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF5FF),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE9D5FF)),
            ),
            padding: EdgeInsets.all(12.w),
            child: Text(
              '\u062f\u0627\u0631\u0641\u0648 \u062a\u0637\u0628\u064a\u0642 \u0644\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u0639\u0642\u0627\u0631\u0627\u062a \u0648\u0627\u0644\u0639\u0642\u0648\u062f \u0628\u0633\u0647\u0648\u0644\u0629 \u0648\u0643\u0641\u0627\u0621\u0629\u060c \u0645\u062e\u0635\u0635 \u0644\u0644\u0645\u0627\u0644\u0643\u064a\u0646 \u0648\u0627\u0644\u0645\u0643\u0627\u062a\u0628 \u0627\u0644\u0639\u0642\u0627\u0631\u064a\u0629 \u0644\u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0623\u0645\u0644\u0627\u0643 \u0648\u0627\u0644\u0645\u0633\u062a\u0623\u062c\u0631\u064a\u0646 \u0648\u0627\u0644\u062f\u0641\u0639\u0627\u062a \u0648\u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631 \u0641\u064a \u0645\u0643\u0627\u0646 \u0648\u0627\u062d\u062f.',
              style: GoogleFonts.tajawal(
                  fontSize: 14.sp,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4C1D95)),
              textAlign: TextAlign.right,
            ),
          ),
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
                child: Text('\u0625\u063a\u0644\u0627\u0642',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          titlePadding: EdgeInsets.zero,
          title: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
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
                    '\u0627\u062a\u0635\u0644 \u0628\u0646\u0627',
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
                  '\u0625\u0630\u0627 \u0648\u0627\u062c\u0647\u062a \u0645\u0634\u0643\u0644\u0629 \u0623\u0648 \u0644\u062f\u064a\u0643 \u0627\u0633\u062a\u0641\u0633\u0627\u0631\u060c \u064a\u0633\u0639\u062f \u0641\u0631\u064a\u0642 \u0627\u0644\u062f\u0639\u0645 \u0628\u0645\u0633\u0627\u0639\u062f\u062a\u0643. \u0631\u0627\u0633\u0644\u0646\u0627 \u0639\u0628\u0631 \u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u062a\u0627\u0644\u064a:',
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
                child: Text('\u0625\u063a\u0644\u0627\u0642',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    final sw = Stopwatch()..start();
    _traceDrawer(
      'Logout',
      'start authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${scope.effectiveUid()}',
    );
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    _traceDrawer('Logout', 'drawer-pop +${sw.elapsedMilliseconds}ms');
    await Future<void>.delayed(Duration.zero);
    if (!rootNavigator.mounted) {
      _traceDrawer(
        'Logout',
        'abort root-navigator-unmounted +${sw.elapsedMilliseconds}ms',
      );
      return;
    }

    final bool ok = await CustomConfirmDialog.show(
      context: rootNavigator.context,
      title:
          '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c',
      message:
          '\u0647\u0644 \u062a\u0631\u064a\u062f \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c \u0627\u0644\u0622\u0646\u061f \u0644\u0625\u062f\u0627\u0631\u0629 \u0639\u0642\u0627\u0631\u0627\u062a\u0643 \u0644\u0627\u062d\u0642\u064b\u0627 \u0633\u062a\u062d\u062a\u0627\u062c \u0625\u0644\u0649 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0645\u0646 \u062c\u062f\u064a\u062f.',
      confirmLabel:
          '\u062a\u0623\u0643\u064a\u062f \u0627\u0644\u062e\u0631\u0648\u062c',
      cancelLabel: '\u0625\u0644\u063a\u0627\u0621',
    );
    _traceDrawer(
        'Logout', 'confirm-result ok=$ok +${sw.elapsedMilliseconds}ms');

    if (ok == true) {
      final currentUser = FirebaseAuth.instance.currentUser;
      final wasOfficeClient = await OfficeClientGuard.isOfficeClient();
      await OfficeClientGuard.setIntentionalLogoutInProgress(true);
      _traceDrawer(
        'Logout',
        'intentional-logout flag=true +${sw.elapsedMilliseconds}ms',
      );
      try {
        try {
          await FirebaseAuth.instance.signOut();
          _traceDrawer(
              'Logout', 'firebase signOut done +${sw.elapsedMilliseconds}ms');
        } catch (e, st) {
          _traceDrawer(
            'Logout',
            'firebase signOut error +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
          );
        }

        try {
          final sp = await SharedPreferences.getInstance();
          await sp.remove('last_login_email');
          await sp.remove('last_login_uid');
          await sp.remove('last_login_role');
          await sp.remove('last_login_offline');
          _traceDrawer('Logout', 'prefs cleared +${sw.elapsedMilliseconds}ms');
        } catch (e, st) {
          _traceDrawer(
            'Logout',
            'prefs clear error +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
          );
        }

        if (Hive.isBoxOpen('sessionBox')) {
          final session = Hive.box('sessionBox');
          await session.put('loggedIn', false);
          await session.put('isOfficeClient', false);
          _traceDrawer(
            'Logout',
            'sessionBox flags updated +${sw.elapsedMilliseconds}ms',
          );
        }

        if (currentUser != null && !wasOfficeClient) {
          await OfficeClientGuard.markOfficeBlocked(
            false,
            email: currentUser.email,
            uid: currentUser.uid,
          );
          _traceDrawer(
            'Logout',
            'clear-local-office-client-block-for-office-account uid=${currentUser.uid}',
          );
        }

        scope.clearFixedUid();
        _traceDrawer('Logout', 'scope cleared +${sw.elapsedMilliseconds}ms');

        await OfficeClientGuard.refreshFromLocal();
        _traceDrawer(
          'Logout',
          'office client guard refreshed +${sw.elapsedMilliseconds}ms',
        );

        if (!rootNavigator.mounted) {
          _traceDrawer(
            'Logout',
            'abort root-navigator-unmounted +${sw.elapsedMilliseconds}ms',
          );
          return;
        }
        _traceDrawer('Logout', 'navigate /login +${sw.elapsedMilliseconds}ms');
        rootNavigator.pushNamedAndRemoveUntil('/login', (route) => false);
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await OfficeClientGuard.setIntentionalLogoutInProgress(false);
        _traceDrawer(
          'Logout',
          'intentional-logout flag=false +${sw.elapsedMilliseconds}ms',
        );
      }
    }
  }

  Widget _coloredIcon({
    required IconData icon,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: 20.sp),
    );
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
    final isPrimaryOfficeUser =
        FirebaseAuth.instance.currentUser?.uid == _officeWorkspaceUid();

    //
    final double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      //
      child: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Drawer(
          backgroundColor: _drawerBg,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                //
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

                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.badge_rounded,
                    bg: const Color(0xFFEFF4FF),
                    fg: const Color(0xFF0D9488),
                  ),
                  title: Text('بياناتي', style: itemStyle),
                  onTap: () => _openMyProfile(context),
                ),

                //
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.card_membership_rounded,
                    bg: const Color(0xFFE6FFFA),
                    fg: const Color(0xFF14B8A6),
                  ),
                  title: Text('اشتراكي', style: itemStyle),
                  onTap: () => _runFromDrawerRoot(
                    context,
                    action: (rootNavigator) =>
                        _openSubscription(rootNavigator.context),
                    traceLabel: 'subscription-sheet',
                  ),
                ),
                if (isPrimaryOfficeUser)
                  ListTile(
                    leading: _coloredIcon(
                      icon: Icons.manage_accounts_rounded,
                      bg: const Color(0xFFEFF4FF),
                      fg: const Color(0xFF0F766E),
                    ),
                    title: Text('مستخدمو المكتب', style: itemStyle),
                    onTap: () => _runFromDrawerRoot(
                      context,
                      action: (rootNavigator) => rootNavigator.push(
                        MaterialPageRoute(
                          builder: (_) => const OfficeUsersScreen(),
                        ),
                      ),
                      traceLabel: 'office-users-screen',
                    ),
                  ),

                if (false)
                  ListTile(
                    leading: _coloredIcon(
                      icon: Icons.history_rounded,
                      bg: const Color(0xFFEFF6FF),
                      fg: const Color(0xFF0D9488),
                    ),
                    title: Text('سجل النشاط', style: itemStyle),
                    onTap: () {},
                  ),

                //
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.description_rounded,
                    bg: const Color(0xFFFFF7ED),
                    fg: const Color(0xFFF59E0B),
                  ),
                  title: Text('سياسة الاستخدام', style: itemStyle),
                  onTap: () {
                    //
                    _openExternal(context, _termsUri);
                  },
                ),

                //
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.privacy_tip_rounded,
                    bg: const Color(0xFFEFFBF6),
                    fg: const Color(0xFF10B981),
                  ),
                  title: Text('سياسة الخصوصية', style: itemStyle),
                  onTap: () {
                    //
                    _openExternal(context, _privacyUri);
                  },
                ),

                //
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.info_outline_rounded,
                    bg: const Color(0xFFF3E8FF),
                    fg: const Color(0xFF8B5CF6),
                  ),
                  title: Text('من نحن', style: itemStyle),
                  onTap: () {
                    //
                    _showAboutDialog(context);
                  },
                ),

                //
                ListTile(
                  leading: _coloredIcon(
                    icon: Icons.support_agent_rounded,
                    bg: const Color(0xFFEFF4FF),
                    fg: _primary,
                  ),
                  title: Text('اتصل بنا', style: itemStyle),
                  onTap: () {
                    //
                    _showSupportDialog(context);
                  },
                ),

                const Spacer(),

                //
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
      ),
    );
  }

  Future<_OfficeProfileData> _fetchOfficeProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final officeUid = _officeWorkspaceUid();
    if (user == null || officeUid == null || officeUid.isEmpty) {
      return _OfficeProfileData.empty();
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(officeUid)
          .get()
          .timeout(const Duration(seconds: 20));

      final data = doc.data();
      if (data == null) {
        final local = await _readOfficeProfileLocal(officeUid);
        if (local == null) return _OfficeProfileData.empty();
        return _profileFromMap(local);
      }

      final rawProfile = data['office_profile'];
      final profile = rawProfile is Map
          ? Map<String, dynamic>.from(rawProfile)
          : <String, dynamic>{};

      String pick(String key, [String fallback = '']) {
        final v = profile[key];
        if (v is String) return v.trim();
        final root = data[key];
        if (root is String) return root.trim();
        return fallback;
      }

      final normalized = <String, dynamic>{
        'office_name': pick('office_name'),
        'work_type': pick('work_type'),
        'address': pick('address'),
        'commercial_no': pick('commercial_no'),
        'mobile': pick('mobile'),
        'phone': pick('phone'),
        'logo_base64': pick('logo_base64'),
      };
      await _saveOfficeProfileLocal(officeUid, normalized);
      return _profileFromMap(normalized);
    } catch (_) {
      final local = await _readOfficeProfileLocal(officeUid);
      if (local != null) return _profileFromMap(local);
      return _OfficeProfileData.empty();
    }
  }

  _OfficeProfileData _profileFromMap(Map<String, dynamic> profile) {
    String pick(String key) {
      final v = profile[key];
      return v is String ? v.trim() : '';
    }

    return _OfficeProfileData(
      officeName: pick('office_name'),
      workType: pick('work_type'),
      address: pick('address'),
      commercialNo: pick('commercial_no'),
      mobile: pick('mobile'),
      phone: pick('phone'),
      logoBase64: pick('logo_base64'),
    );
  }

  Future<void> _saveOfficeProfileLocal(
      String uid, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_officeProfilePrefsPrefix$uid', jsonEncode(data));
  }

  Future<Map<String, dynamic>?> _readOfficeProfileLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_officeProfilePrefsPrefix$uid');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _optimizeLogoBase64(Uint8List bytes) async {
    const maxEncodedChars = 700000;
    var encoded = base64Encode(bytes);
    if (encoded.length <= maxEncodedChars) return encoded;

    for (final width in const [768, 512, 384, 256, 192]) {
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;

        encoded = base64Encode(data.buffer.asUint8List());
        if (encoded.length <= maxEncodedChars) return encoded;
      } catch (_) {
        // Keep trying smaller sizes.
      }
    }

    return null;
  }
}

//
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
        planDurationLabel: '-',
        planPriceLabel: '-',
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

class _OfficeProfileData {
  final String officeName;
  final String workType;
  final String address;
  final String commercialNo;
  final String mobile;
  final String phone;
  final String logoBase64;

  const _OfficeProfileData({
    required this.officeName,
    required this.workType,
    required this.address,
    required this.commercialNo,
    required this.mobile,
    required this.phone,
    required this.logoBase64,
  });

  factory _OfficeProfileData.empty() => const _OfficeProfileData(
        officeName: '',
        workType: '',
        address: '',
        commercialNo: '',
        mobile: '',
        phone: '',
        logoBase64: '',
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
        SizedBox(width: valueWidth, child: valueText),
        const Spacer(),
      ],
    );
  }
}
