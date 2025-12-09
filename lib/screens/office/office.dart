// lib/screens/office/office.dart
// ملف موحّد يضم شاشات المكتب: OfficeHomePage + OfficeClientsPage
// + AddOfficeClientDialog + EditOfficeClientDialog + ClientAccessDialog + DeleteClientDialog
//
// التعديل الجذري المطلوب:
// - كل العمليات (إضافة/تعديل/دخول/حذف) تعمل محليًا فورًا دون أي حجب أو دوائر انتظار.
// - عند الإضافة يظهر العميل فورًا أعلى القائمة ويبقى ثابتًا في مكانه حتى مع المزامنة.
// - ثبات العرض بعد الرجوع من تطبيق العميل: تثبيت نطاق Hive إلى UID المكتب كلما ظهرت شاشة المكتب.
// - الأزرار (الجرس/صلاحيات الدخول) تظهر دائمًا؛ وتفتح حتى بدون إنترنت.
// - المزامنة تتم تلقائيًا عند رجوع الشبكة.
// - ✅ تأكيد الحذف دائمًا سواء العميل محلي (pending) أو سحابي.
// - ✅ شاشة التعديل تفضّل تعديلاتك المحلية المعلّقة ولا تعيد القيم القديمة.
//
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:darvoo/data/services/offline_sync_service.dart';
import 'package:darvoo/data/services/user_scope.dart' as scope;

import 'widgets/office_side_drawer.dart';
import 'package:darvoo/data/services/subscription_alerts.dart';
import 'package:darvoo/data/services/hive_service.dart';
import 'package:darvoo/data/services/office_client_guard.dart';
import 'package:darvoo/data/sync/sync_bridge.dart';
import 'package:darvoo/data/services/firestore_user_collections.dart';
import 'package:darvoo/data/repos/tenants_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';





/// ======================== OfficeSession ========================
class OfficeSession {
  static const _boxName = '_officeSessionBox';
  static const _kToken = 'returnToken';
  static const _kUid = 'expectedOfficeUid';
  static const _kSavedAt = 'savedAtIso';

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  static Future<void> storeReturnContext({
    required String expectedOfficeUid,
    String? officeReturnToken,
  }) async {
    final b = await _box();
    await b.put(_kUid, expectedOfficeUid);
    await b.put(_kToken, officeReturnToken ?? 'office-return'); // أي نص غير فارغ
    await b.put(_kSavedAt, DateTime.now().toIso8601String());
  }

  static Future<String?> get expectedOfficeUid async {
    final b = await _box();
    return b.get(_kUid) as String?;
  }

  static Future<String?> get officeToken async {
    final b = await _box();
    return b.get(_kToken) as String?;
  }

  static Future<void> clear() async {
    final b = await _box();
    await b.delete(_kToken);
    await b.delete(_kUid);
    await b.delete(_kSavedAt);
  }

 static Future<void> backToOffice(BuildContext context) async {
  final expectedUid = await expectedOfficeUid;

  if (expectedUid == null || expectedUid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لا يوجد جلسة مكتب محفوظة للرجوع.')),
    );
    return;
  }

  // ✅ رجّع الجلسة لوضع "مكتب" عادي (ليس عميل مكتب)
  if (Hive.isBoxOpen('sessionBox')) {
    final session = Hive.box('sessionBox');
    await session.put('isOfficeClient', false);
  }
  await OfficeClientGuard.refreshFromLocal();

  // ✅ ثبّت نطاق Hive على UID المكتب
  scope.setFixedUid(expectedUid);

  // ✅ أعد تهيئة جسور المزامنة وخدمة الأوفلاين للمكتب
  try {
    await SyncManager.instance.stopAll();
  } catch (_) {}

  try {
    OfflineSyncService.instance.dispose();
  } catch (_) {}

  final uc = UserCollections(expectedUid);
  final tenantsRepo = TenantsRepo(uc);
  await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

  await HiveService.ensureReportsBoxesOpen();

  try {
    await SyncManager.instance.startAll();
  } catch (_) {}

  await clear();
  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/office', (r) => false);
  }
}


}

/// ======================== Runtime ========================
class OfficeRuntime {
  static final selectedClientUid = ValueNotifier<String?>(null);
  static final selectedClientName = ValueNotifier<String?>(null);

  static void selectClient({required String uid, required String name}) {
    selectedClientUid.value = uid;
    selectedClientName.value = name;
  }

  static void clear() {
    selectedClientUid.value = null;
    selectedClientName.value = null;
  }
}

/// ======================== Helpers ========================
void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

String _fmtDateKsa(DateTime? utc) {
  if (utc == null) return '-';
  final ksa = utc.toUtc().add(const Duration(hours: 3));
  final y = ksa.year.toString().padLeft(4, '0');
  final m = ksa.month.toString().padLeft(2, '0');
  final d = ksa.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}

/// يجعل رقم الجوال اختياريًا، ولكن إن أُدخل يجب أن يكون 10 أرقام بالضبط.
String? normalizeLocalPhoneForUi(String? phone) {
  final raw = (phone ?? '').trim();
  if (raw.isEmpty) return '';
  final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length != 10) return null;
  return digitsOnly;
}

Widget _softCircle(double size, Color color) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _DarkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? minHeight;
  const _DarkCard({required this.child, this.padding, this.minHeight});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x26FFFFFF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

TextStyle get _titleStyle => GoogleFonts.cairo(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 18,
    );

TextStyle get _subStyle => GoogleFonts.cairo(
      color: Colors.white70,
      fontWeight: FontWeight.w700,
      fontSize: 12,
    );

/// ✅ فورماتر يمنع تجاوز حد الطول مع تنبيه فوري
class _LengthLimitFormatter extends TextInputFormatter {
  final int max;
  final VoidCallback? onExceed;
  _LengthLimitFormatter(this.max, {this.onExceed});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    onExceed?.call();
    HapticFeedback.selectionClick();
    return oldValue;
  }
}

/// زر دائري أيقونة فقط — مصغّر ومتناسق
class _IconCircleBtn extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  final String? tooltip;

  final double size; // قطر الزر
  final double iconSize; // حجم الأيقونة
  final bool disabled;

  const _IconCircleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.bg = const Color(0xFF1E293B),
    this.tooltip,
    this.size = 34,
    this.iconSize = 18,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: Colors.white),
    );

    return Tooltip(
      message: tooltip ?? '',
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? 0.55 : 1.0,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}

/// دائرة انتظار شفافة أثناء الانتحال فقط (لم نلغها لأنها لا تتعلق بالإضافة/التعديل)
class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.transparent,
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

/// ======================== (A) OfficeNotificationsBell ========================
class OfficeNotificationsBell extends StatefulWidget {
  const OfficeNotificationsBell({super.key});

  @override
  State<OfficeNotificationsBell> createState() => _OfficeNotificationsBellState();
}

class _OfficeNotificationsBellState extends State<OfficeNotificationsBell> {
  int _badge = 0;
  SubscriptionAlert? _pending;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _scheduleNextCheck();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextCheck() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day).add(const Duration(days: 1, minutes: 1));
    _midnightTimer = Timer(next.difference(now), () {
      _refresh();
      _scheduleNextCheck();
    });
  }

Future<DateTime?> _subscriptionEndProvider() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!snap.exists) return null;

    final data = snap.data() ?? {};

    // 1) نستخدم end_date_ksa إن وُجد (نفس نافذة "اشتراكي" للمكتب)
    final endKsaText = (data['end_date_ksa'] as String?)?.trim();
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final normalized = endKsaText.replaceAll('/', '-');
      final parts = normalized.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          return DateTime(y, m, d);
        }
      }
    }

    // 2) fallback للحسابات القديمة: نحسب من subscription_end بتوقيت السعودية
    final raw = data['subscription_end'];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return null;

    final utc = dt.toUtc();
    final ksa = utc.add(const Duration(hours: 3));
    return DateTime(ksa.year, ksa.month, ksa.day);

  } catch (_) {
    return null;
  }
}


  Future<void> _refresh() async {
    final endAt = await _subscriptionEndProvider();
    final alert = SubscriptionAlerts.compute(endAt: endAt);
    if (!mounted) return;
    setState(() {
      _pending = alert;
      _badge = alert == null ? 0 : 1;
    });
  }

  Future<void> _openSheet() async {
    if (_pending == null) return;
    final alert = _pending!;
    final df = DateFormat('d MMMM yyyy', 'ar');

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.notifications_active, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Text('التنبيهات', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.45)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(alert.title, style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(alert.body,
                          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                      const SizedBox(height: 8),
                      if (alert.endAt != null)
                        Text('تاريخ الانتهاء: ${df.format(alert.endAt)}',
                            style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

    @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,  // مساحة ضغط مريحة داخل الـ AppBar
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // أي ضغطة داخل الـ 48x48 تنحسب
        onTap: _openSheet,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
            ),
            if (_badge > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.0),
                  ),
                  child: Text(
                    '$_badge',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// ======================== 1) OfficeHomePage ========================
class OfficeHomePage extends StatefulWidget {
  const OfficeHomePage({super.key});

  @override
  State<OfficeHomePage> createState() => _OfficeHomePageState();
}

class _OfficeHomePageState extends State<OfficeHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>(); // 👈 هذا الجديد

  bool _online = true;        // هل يوجد اتصال بالإنترنت؟
  bool _maybeWeak = false;    // هل الاتصال ضعيف/غير مستقر؟
  StreamSubscription<List<ConnectivityResult>>? _connSub;



  @override
  void initState() {
    super.initState();
    _startConnectivityWatch();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

    void _startConnectivityWatch() {
    // فحص أولي
    _checkNow();

    // مراقبة أي تغيير في حالة الشبكة (واي فاي / بيانات / بدون شبكة)
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _updateFromResult(results);
    });
  }

  Future<void> _checkNow() async {
    final results = await Connectivity().checkConnectivity();
    await _updateFromResult(results);
  }

  Future<void> _updateFromResult(List<ConnectivityResult> results) async {
    // هل يوجد أي نوع اتصال غير none ؟
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    bool online = hasNetwork;
    bool weak = false;

    if (hasNetwork) {
      // نحاول نعمل طلب بسيط للتأكد من أن الإنترنت فعلاً شغّال
      try {
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
        weak = false;
      } catch (_) {
        // يوجد شبكة (واي فاي / بيانات) لكن يبدو الاتصال ضعيف أو غير مستقر
        online = true;   // نعتبره متصل لكن ضعيف
        weak = true;
      }
    } else {
      // لا يوجد واي فاي ولا بيانات
      online = false;
      weak = false;
    }

    if (!mounted) return;
    setState(() {
      _online = online;
      _maybeWeak = weak;
    });
  }

  Future<bool> _onWillPop() async {
    // لو القائمة الجانبية مفتوحة، نقفلها فقط ولا نعرض نافذة الخروج
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop(); // إغلاق الدرج
      return false; // لا نخرج من الشاشة
    }
    final bool? shouldExit = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          titlePadding: EdgeInsets.zero,
          title: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF1F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تأكيد الخروج',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFFB91C1C),
                      height: 1.0,
                    ),
                    textHeightBehavior: const ui.TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          content: Text(
            'هل أنت متأكد من رغبتك في الخروج من التطبيق؟',
            style: GoogleFonts.tajawal(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.right,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // زر تأكيد الخروج
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'تأكيد الخروج',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // زر إلغاء
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFECEFF1),
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFECEFF1)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

   if (shouldExit == true) {
      // ✅ إغلاق التطبيق مباشرة (مثل "تأكيد الخروج" الحقيقي)
      SystemNavigator.pop();
      // نرجّع false حتى لا يحاول Navigator يعمل pop لروت آخر
      return false;
    }

    // المستخدم لغى أو رجع للخلف من الديالوج
    return false;
  }
 


  @override
  Widget build(BuildContext context) {
    // ✅ تثبيت نطاق الصناديق على UID المكتب كلما ظهرت شاشة المكتب
    final officeUid = FirebaseAuth.instance.currentUser?.uid;
    if (officeUid != null && officeUid.isNotEmpty) {
      scope.setFixedUid(officeUid);
    }

     return WillPopScope(
      onWillPop: _onWillPop, // 👈 هنا ربطنا زر الرجوع
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Stack(
          children: [
            // الواجهة العادية كما كانت
Scaffold(
  key: _scaffoldKey, // 👈 أضف هذا السطر
  backgroundColor: Colors.transparent,
  drawer: const OfficeSideDrawer(),
  appBar: AppBar(

                elevation: 0,
                centerTitle: true,
                leading: Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'القائمة',
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                title: Text(
                  'لوحة المكتب',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: 6),
                    child: OfficeNotificationsBell(),
                  ),
                ],
              ),
              body: const OfficeClientsPage(),
            ),

            // 🔴 في حالة انقطاع الإنترنت بالكامل → حجب تام + رسالة
            if (!_online) _buildOfflineBlocker(context),

            // 🟠 في حالة الاتصال الضعيف → شريط تحذير فقط بدون حجب كامل
            if (_maybeWeak && _online) _buildWeakBanner(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBlocker(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false, // نمنع أي لمس تحت الطبقة
        child: Container(
          color: Colors.black.withOpacity(0.70),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'لا يوجد اتصال بالإنترنت',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'لا يمكن استخدام لوحة المكتب بدون إنترنت.\n'
                'تحقّق من الشبكة ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeakBanner(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.network_check_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الاتصال بالإنترنت ضعيف، قد تفشل بعض العمليات.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// نموذج عرض داخلي موحّد
class _ClientItem {
  final String name;
  final String email;
  final String phone;
  final String notes;
  final String clientUid; // قد يكون localUid للعملاء المحليين
  final DateTime? createdAt;
  final bool isLocal;
  final String? tempId; // لمحو العميل المحلي إن رغبت
  _ClientItem({
    required this.name,
    required this.email,
    required this.phone,
    required this.notes,
    required this.clientUid,
    required this.createdAt,
    required this.isLocal,
    this.tempId,
  });
}

/// ======================== 2) OfficeClientsPage ========================
class OfficeClientsPage extends StatefulWidget {
  const OfficeClientsPage({super.key});

  @override
  State<OfficeClientsPage> createState() => _OfficeClientsPageState();
}

class _OfficeClientsPageState extends State<OfficeClientsPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _officeSub;

  // 👇 كاش لمنع فلاش الشاشة عند الانتحال
  String? _officeUidAtStart;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _clientsStreamCache;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();


  User? get _me => FirebaseAuth.instance.currentUser;
  bool _impersonating = false; // اللودر يظهر فقط عند الانتحال

  // ✅ سجل ترتيب ثابت محليًا (يعتمد على البريد) — يحفظ المواضع
  static const _orderBoxLogical = '_officeClientsOrder';
  Map<String, int> _orderMap = {};
  int _orderLast = 0;
  bool _orderLoaded = false;

  // ✅ خريطة لحلّ UID السحابي لعملاء محليين عبر البريد (محجوزة للتوسّع لاحقًا)
  final Map<String, String> _resolvedUidByEmail = {};

  // نخزن آخر مجموعة Pending لمعرفة الجديد منها (محجوزة للتوسّع لاحقًا)
  Set<String> _lastPendingEmails = {};

  // ==== مراقبة الاتصال (اختياري للبُنى الداخلية) ====
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // ✅ حذف محلي مُجدول: إخفاؤهم فورًا من الواجهة
  final Set<String> _locallyDeleted = {};

  @override
  void initState() {
    super.initState();

    _officeUidAtStart = FirebaseAuth.instance.currentUser?.uid;

    // ✅ تثبيت نطاق المكتب كذلك هنا لضمان القراءة من صناديق المكتب دائمًا
    final officeUid = _officeUidAtStart;
    if (officeUid != null && officeUid.isNotEmpty) {
      scope.setFixedUid(officeUid);
    }

    _clientsStreamCache = _buildStreamFor(_officeUidAtStart);
    _watchOfficeSubscription(); // 👈 مراقبة حالة اشتراك المكتب (بدون signOut)
    _loadOrderBox(); // تحميل سجل الترتيب
    _startConnectivityWatch(); // مراقبة الاتصال (لا تحجب الواجهة مطلقًا)
  }

  @override
  void dispose() {
    _officeSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  // ===== صناديق/ستريم =====
  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildStreamFor(String? uid) {
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('offices')
        .doc(uid)
        .collection('clients')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);
  }

  void _watchOfficeSubscription() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  _officeSub = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .listen((doc) async {
    // نستخدم فقط آخر مزامنة حقيقية من السيرفر
    if (doc.metadata.isFromCache) return;
    if (!doc.exists) return;

    final m = doc.data() ?? {};

    // 1️⃣ حالة الحظر (هذه دائمًا تُخرج المكتب فورًا)
    final blocked = (m['blocked'] ?? false) == true;

    // 2️⃣ نقرأ end_date_ksa كنص مثل "2025-01-29"
    DateTime? inclusiveEndKsa;
    final endKsaText = (m['end_date_ksa'] as String?)?.trim();
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final parts = endKsaText.split('-'); // صيغة yyyy-MM-dd
      if (parts.length >= 3) {
        final y = int.tryParse(parts[0]);
        final mo = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && mo != null && d != null) {
          // هذا يمثل "اليوم الأخير" في السعودية
          inclusiveEndKsa = DateTime(y, mo, d);
        }
      }
    }

    // 3️⃣ نحسب "تاريخ اليوم" بتوقيت السعودية
    final nowUtc = DateTime.now().toUtc();
    final nowKsa = nowUtc.add(const Duration(hours: 3));
    final todayKsa = DateTime(nowKsa.year, nowKsa.month, nowKsa.day);

    // 4️⃣ منتهي فقط إذا كان اليوم في السعودية بعد اليوم الأخير
       // 4️⃣ منتهي فقط إذا كان اليوم في السعودية بعد اليوم الأخير
    bool expired = false;
    if (inclusiveEndKsa != null) {
      // end_date_ksa = 29 → شغال طول يوم 29، وينتهي من بداية يوم 30
      expired = todayKsa.isAfter(inclusiveEndKsa);
    } else {
      // 🔁 مسار احتياطي قديم لو end_date_ksa غير موجود (حسابات قديمة)
      DateTime? end;
      final v = m['subscription_end'];
      if (v is Timestamp) {
        end = v.toDate();
      } else if (v is DateTime) {
        end = v;
      } else if (v is String) {
        end = DateTime.tryParse(v);
      }

      if (end != null) {
        // ✅ نحول subscription_end إلى "تاريخ فقط" بتوقيت السعودية
        final endUtc = end.toUtc();
        final endKsa = endUtc.add(const Duration(hours: 3));
        final endDateKsa = DateTime(endKsa.year, endKsa.month, endKsa.day);

        // 👉 نفس منطق end_date_ksa:
        // endDateKsa = 29 → شغال طول يوم 29، وينتهي من بداية يوم 30
        expired = todayKsa.isAfter(endDateKsa);
      }
    }


    // ⚠️ هنا التعطيل في شاشة المكتب نعتمده فقط على:
    //  - blocked (موقوف من الإدارة)
    //  - expired (تجاوز اليوم الأخير في السعودية)
    if (blocked || expired) {
      await _officeSub?.cancel();
      _officeSub = null;

      if (!mounted) return;
      final msg = blocked
          ? 'تم إيقاف حساب المكتب (وفق آخر مزامنة مباشرة).'
          : 'انتهى اشتراك المكتب (وفق آخر مزامنة مباشرة).';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

      // 🔐 تسجيل خروج كامل من حساب المكتب
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      // 🧹 مسح بيانات آخر مستخدم محفوظ للـ auto-login
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('last_login_email');
        await sp.remove('last_login_uid');
        await sp.remove('last_login_role');
        await sp.remove('last_login_offline');
      } catch (_) {}

      // 🧹 تحديث sessionBox
      if (Hive.isBoxOpen('sessionBox')) {
        final session = Hive.box('sessionBox');
        await session.put('loggedIn', false);
        await session.put('isOfficeClient', false); // خروج من وضع "عميل مكتب"
      }

      // 👇 امسح UID الانتحال من user_scope
      scope.clearFixedUid();

      // 👇 حدّث حارس عميل المكتب
      await OfficeClientGuard.refreshFromLocal();

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    }

  });
}


  // ✅ ترجّع دائمًا نفس الستريم المخزّن أثناء الانتحال لمنع الفلاش
Stream<QuerySnapshot<Map<String, dynamic>>>? _clientsStream() {
  // لو نحن في وضع "انتحال" عميل من داخل المكتب، لا تغيّر الـ stream
  if (_impersonating) return _clientsStreamCache;

  // 👈 استخدم الـ uid الفعّال (من user_scope)
  final uid = scope.effectiveUid();

  // لو ما عندنا مستخدم فعّال (guest) نحافظ على الـ stream القديم إن وجد
  if (uid == 'guest') {
    return _clientsStreamCache;
  }

  // لو تغيّر الـ uid (دخول مكتب جديد أو عميل جديد) ابنِ stream جديد
  if (uid != _officeUidAtStart) {
    _officeUidAtStart = uid;
    _clientsStreamCache = _buildStreamFor(uid);
  }

  return _clientsStreamCache;
}


  // ===== ترتيب محلي =====
  Future<void> _loadOrderBox() async {
    final name = scope.boxName(_orderBoxLogical);
    final box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
    final raw = (box.get('map') as Map?) ?? {};
    final map = <String, int>{};
    for (final e in raw.entries) {
      final k = e.key.toString();
      final v = (e.value is int) ? e.value as int : int.tryParse('${e.value}') ?? 0;
      map[k] = v;
    }
    final last = (box.get('last') as int?) ?? (map.values.isEmpty ? 0 : map.values.reduce((a, b) => math.max(a, b)));
    setState(() {
      _orderMap = map;
      _orderLast = last;
      _orderLoaded = true;
    });
  }

  void _saveOrderBoxDebounced() {
    Future.microtask(() async {
      final name = scope.boxName(_orderBoxLogical);
      final box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
      await box.put('map', _orderMap);
      await box.put('last', _orderLast);
    });
  }

  int _ensureIndexForEmail(String email) {
    final key = email.trim().toLowerCase();
    if (key.isEmpty) {
      _orderLast += 1;
      _saveOrderBoxDebounced();
      return _orderLast;
    }
    final ex = _orderMap[key];
    if (ex != null) return ex;
    _orderLast += 1;
    _orderMap[key] = _orderLast;
    _saveOrderBoxDebounced();
    return _orderLast;
  }

  void _startConnectivityWatch() {
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> _) {});
  }

  // ===== أحداث واجهة =====
  Future<void> _onAdd() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => const AddOfficeClientDialog(),
    );
    if (!mounted) return;
    setState(() {}); // يظهر العميل المحلي فورًا
  }

  // ✅ تأكيد الحذف دائمًا (سواء محلي أو سحابي)
  Future<void> _confirmDelete({
    required bool isLocal,
    required String? tempIdForLocal,
    required String clientUidOrLocal,
    required String displayName,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dctx) => DeleteClientDialog(
        clientName: displayName,
        onConfirm: () => Navigator.pop(dctx, true),
        onCancel: () => Navigator.pop(dctx, false),
      ),
    );
    if (ok != true) return;

    if (isLocal && (tempIdForLocal ?? '').isNotEmpty) {
      try {
        await OfflineSyncService.instance.removePendingOfficeCreateByTempId(tempIdForLocal!);
        if (!mounted) return;
        setState(() {});
        _showSnack(context, 'تم الحذف بنجاح.');
      } catch (e) {
        _showSnack(context, 'تعذّر حذف العميل المحلي: $e');
      }
      return;
    }

    // سحابي: صفّ الحذف أوفلاين وأخفِ من الواجهة فورًا
    try {
      await OfflineSyncService.instance.enqueueDeleteOfficeClient(clientUidOrLocal);
      _locallyDeleted.add(clientUidOrLocal);
      if (!mounted) return;
      setState(() {});
      _showSnack(context, 'تم الحذف بنجاح .');
    } catch (e) {
      _showSnack(context, 'تعذّر جدولة الحذف: $e');
    }
  }

  Future<void> _onDelete(String clientUid, String clientName) async {
    // احتُفظ بها للاستخدام الداخلي إن احتجت (نستعمل _confirmDelete الآن)
    await _confirmDelete(
      isLocal: false,
      tempIdForLocal: null,
      clientUidOrLocal: clientUid,
      displayName: clientName,
    );
  }

  Future<void> _openEdit(
    String clientUid, {
    required String name,
    required String email,
    String? phone,
    String? notes,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => EditOfficeClientDialog(
        clientUid: clientUid,
        initialName: name,
        initialEmail: email,
        initialPhone: phone ?? '',
        initialNotes: notes ?? '',
      ),
    );
    if (!mounted) return;

    // تحديث فوري لتطبيق التعديلات المحلية على البطاقات
    setState(() {});
  }

  void _openAccess(String clientUid, String email) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => ClientAccessDialog(clientEmail: email, clientUid: clientUid),
    );
  }

  // ✅ زر الصلاحيات يفتح دائمًا حتى بدون نت (لا شروط)
  void _handleAccessPressed({
    required bool isLocalItem,
    required String email,
    required String clientUidOrLocal,
  }) {
    _openAccess(clientUidOrLocal, email);
  }

  // الجرس الحقيقي للعملاء السحابيين
   // الجرس الحقيقي للعملاء السحابيين — مربوط بعدد التنبيهات في تطبيق العميل
  Widget _NotifBell(String clientUid) {
    final docStream = FirebaseFirestore.instance
        .collection('users')
        .doc(clientUid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (ctx, snap) {
        int count = 0;

        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          final raw = data['notificationsCount'];
          if (raw is int) {
            count = raw;
          } else if (raw is num) {
            count = raw.toInt();
          }
        }

        return Stack(
  clipBehavior: Clip.none,
  children: [
    InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        // حاليًا مجرد تلميح، لاحقًا يمكننا فتح تطبيق العميل مباشرة على شاشة التنبيهات
        _showSnack(ctx, 'اضغط دخول ثم اضغط على "التنبيهات" لمشاهدة التفاصيل.');
      },
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(
          Icons.notifications_none_rounded,
          color: Colors.white,
        ),
      ),
    ),
    // ✅ البادج يظهر دائمًا حتى لو count = 0
  Positioned(
  top: 3.8,
  right: -6,
  child: IgnorePointer( // ✅ يخلي البادج لا يستقبل اللمس
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  ),
),


          ],
        );
      },
    );
  }


  // Placeholder للعميل المحلي (يظهر أيقونة فقط)
  Widget _NotifBellPlaceholder() {
    return const Padding(
      padding: EdgeInsets.all(6.0),
      child: Opacity(
        opacity: 0.85,
        child: Icon(Icons.notifications_none_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildClientCard({
    required String name,
    required String email,
    required String phone,
    required String notes,
    required String clientUid,
    DateTime? createdAt,
    required bool isPendingLocal,
    String? tempIdForLocal,
  }) {
    final createdStr = _fmtDateKsa(createdAt);

    final displayName = name.isEmpty ? (email.isEmpty ? clientUid : email) : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DarkCard(
          minHeight: 140,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Stack(
            children: [
              Positioned(
                top: -4,
                left: -4,
                child: isPendingLocal ? _NotifBellPlaceholder() : _NotifBell(clientUid),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                        ),
                        child: const Icon(Icons.business_center_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: _titleStyle),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 3,
                        ),
                        onPressed: () => _enterManageClient(
                          clientUid,
                          displayName,
                        ),
                        child: Text('دخول', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const Spacer(),
                      Text('الإضافة: $createdStr', style: _subStyle),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _IconCircleBtn(
              icon: Icons.vpn_key_rounded,
              tooltip: 'صلاحيات الدخول',
              onTap: () => _handleAccessPressed(
                isLocalItem: isPendingLocal,
                email: email,
                clientUidOrLocal: clientUid,
              ),
              bg: const Color(0xFF334155),
              disabled: false,
            ),
            const SizedBox(width: 8),
            _IconCircleBtn(
              icon: Icons.edit_rounded,
              tooltip: 'تعديل',
              onTap: () => _openEdit(
                clientUid,
                name: name,
                email: email,
                phone: phone,
                notes: notes,
              ),
              bg: const Color(0xFF1E293B),
            ),
            const SizedBox(width: 8),
            _IconCircleBtn(
              icon: Icons.delete_outline_rounded,
              tooltip: 'حذف',
              onTap: () => _confirmDelete(
                isLocal: isPendingLocal,
                tempIdForLocal: tempIdForLocal,
                clientUidOrLocal: clientUid,
                displayName: displayName,
              ),
              bg: const Color(0xFF7F1D1D),
            ),
          ],
        ),
      ],
    );
  }

  /// دخول المكتب لإدارة تطبيق العميل
  /// دخول المكتب لإدارة تطبيق العميل
Future<void> _enterManageClient(String clientUid, String clientName) async {
  // 🔒 في أول مرة بعد إضافة العميل: إذا كان UID محليًا لا ندخل بتاتًا
  // بل نحاول تفريغ طابور المزامنة ثم ننعش القائمة ليظهر الحساب الحقيقي.
  if (clientUid.startsWith('local_')) {
    try {
      // نحاول تفريغ طوابير الأوفلاين (ومنها officeCreateClient) بهدوء
      await OfflineSyncService.instance.tryFlushAllIfOnline();
    } catch (_) {
      // في أسوأ الأحوال لن تتم المزامنة الآن، ولا ندخل على UID محلي
    }

    // 🔄 إعادة بناء ستريم العملاء للمكتب الحالي (ريفرش بسيط لنفس الشاشة)
    final uid = _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      setState(() {
        _clientsStreamCache = _buildStreamFor(uid);
      });
    }

    _showSnack(
      context,
      'جاري تجهيز هذا العميل في السحابة، انتظر ثوانٍ قليلة ثم اضغط "دخول" مرة أخرى.',
    );
    return;
  }



    final officeUid = _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (officeUid.isEmpty) {
      _showSnack(context, 'يرجى تسجيل الدخول كمكتب أولًا.');
      return;
    }

    // 🔒 منع فتح تطبيق العميل بدون إنترنت مستقر
    try {
      final results = await Connectivity().checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      bool online = false;
      if (hasNetwork) {
        try {
          final lookup = await InternetAddress.lookup('google.com')
              .timeout(const Duration(seconds: 3));
          online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
        } catch (_) {
          online = false;
        }
      }

      if (!online) {
        _showSnack(
          context,
          'لا يمكن دخول تطبيق العميل بدون اتصال إنترنت. '
          'يرجى التحقق من الشبكة ثم المحاولة مرة أخرى.',
        );
        return;
      }
    } catch (_) {
      _showSnack(
        context,
        'تعذّر التحقق من الاتصال بالإنترنت. حاول مجددًا بعد قليل.',
      );
      return;
    }

    setState(() => _impersonating = true);
    await Future.delayed(const Duration(milliseconds: 16)); // إطار واحد لإظهار اللودر

    try {
      await OfficeSession.storeReturnContext(expectedOfficeUid: officeUid);


    // ✅ هذه الجلسة قادمة من شاشة المكتب نفسها → صلاحيات كاملة (NOT عميل مقيّد)
// ✅ هذه الجلسة قادمة من شاشة المكتب نفسها → صلاحيات كاملة (NOT عميل مقيّد)
const boxName = 'sessionBox';
final session = Hive.isBoxOpen(boxName)
    ? Hive.box(boxName)
    : await Hive.openBox(boxName);

// 👇 انتحال من مكتب: ليس "عميل مكتب" مقيّد، لكن لازم إنترنت
await session.put('isOfficeClient', false);      // صلاحيات كاملة
await session.put('clientNeedsInternet', true);  // لكن يحتاج إنترنت دائم

await OfficeClientGuard.refreshFromLocal();



        // ✅ ثبّت نطاق Hive على UID العميل
    scope.setFixedUid(clientUid);

    // ✅ أعد تهيئة الجسور والمزامنة لهذا العميل (بدون تغيير مستخدم Firebase)
    try {
      // إيقاف جسور المزامنة القديمة (كانت على UID المكتب)
      await SyncManager.instance.stopAll();
    } catch (_) {}

    try {
      // إيقاف خدمة الأوفلاين القديمة (كانت على UID المكتب)
      OfflineSyncService.instance.dispose();
    } catch (_) {}

    // خدمة الأوفلاين لهذا العميل
    final uc = UserCollections(clientUid);
    final tenantsRepo = TenantsRepo(uc);
    await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

    // ✅ افتح صناديق Hive الخاصة بهذا العميل قبل الدخول لتطبيقه
    await HiveService.ensureReportsBoxesOpen();

    // جسور هذا العميل (Firestore <-> Hive)
    try {
      await SyncManager.instance.startAll();
    } catch (_) {}

    // حفظ اسم العميل في الـ runtime (كما هو)
    OfficeRuntime.selectClient(uid: clientUid, name: clientName);

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
  } catch (e) {
    if (mounted) {
      _showSnack(context, 'فشل الدخول: $e');
    }
  } finally {
    if (mounted) setState(() => _impersonating = false);
  }
}


  @override
  Widget build(BuildContext context) {
    final stream = _clientsStream();
    return WillPopScope(
      onWillPop: () async => !_impersonating,
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Stack(
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
            Positioned(top: -120, right: -80, child: _softCircle(220, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260, const Color(0x22FFFFFF))),
            Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
              floatingActionButton: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                onPressed: _onAdd,
                icon: const Icon(Icons.add),
                label: Text('إضافة عميل', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
              body: stream == null
                  ? Center(
                      child: Text(
                        'يرجى تسجيل الدخول',
                        style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                    )
: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: stream,
  builder: (context, snap) {
    // ✅ أول مرة تفتح الشاشة والـ stream لسه يحمل → اعرض لودر بدل "ليس لديك عملاء بعد"
    if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    final docs = snap.data?.docs ?? [];

    // 1) الإضافات المحلية فورًا
    final pendingCreates = OfflineSyncService.instance.listPendingOfficeCreates();
    final pendingEdits = OfflineSyncService.instance.mapPendingOfficeEdits();


                        final pendingEmails = <String>{
                          for (final p in pendingCreates) ((p['email'] ?? '') as String).trim().toLowerCase()
                        };

                        // 2) عناصر محلية أولًا
                        final items = <_ClientItem>[];
                        for (final p in pendingCreates) {
                          final tempId = (p['tempId'] ?? '') as String;
                          final localUid = (p['localUid'] ?? tempId) as String;
                          final email = (p['email'] ?? '') as String;

                          items.add(_ClientItem(
                            name: (p['name'] ?? '') as String,
                            email: email,
                            phone: (p['phone'] ?? '') as String,
                            notes: (p['notes'] ?? '') as String,
                            clientUid: localUid,
                            createdAt: DateTime.tryParse((p['createdAtIso'] ?? '') as String),
                            isLocal: true,
                            tempId: tempId,
                          ));
                        }

                        // 3) عناصر السحابي + تطبيق تعديل أوفلاين وتجنّب الازدواجية + إخفاء المحذوف محليًا
                        for (final d in docs) {
                          final m = d.data();
                          var name = (m['name'] ?? '').toString();
                          final email = (m['email'] ?? '').toString();
                          var phone = (m['phone'] ?? '').toString();
                          var notes = (m['notes'] ?? '').toString();
                          final clientUid = (m['clientUid'] ?? m['uid'] ?? d.id).toString();

                          if (_locallyDeleted.contains(clientUid)) continue;
                          if (pendingEmails.contains(email.trim().toLowerCase())) continue;

                          final pe = pendingEdits[clientUid];
                          if (pe != null) {
                            if (pe.containsKey('name')) name = (pe['name'] ?? '') as String;
                            if (pe.containsKey('phone')) {
                              final ph = pe['phone'];
                              phone = (ph == null) ? '' : (ph as String);
                            }
                            if (pe.containsKey('notes')) {
                              final nt = pe['notes'];
                              notes = (nt == null) ? '' : (nt as String);
                            }
                          }

                          items.add(_ClientItem(
                            name: name,
                            email: email,
                            phone: phone,
                            notes: notes,
                            clientUid: clientUid,
                            createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
                            isLocal: false,
                          ));
                        }

                        // 4) ترتيب ثابت محليًا
                        final withOrder = <({int order, _ClientItem it})>[];
                        for (final it in items) {
                          final order = _ensureIndexForEmail(it.email);
                          withOrder.add((order: order, it: it));
                        }
                        withOrder.sort((a, b) => b.order.compareTo(a.order));

                        // 5) بناء الواجهة
                        if (withOrder.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt_outlined, size: 64, color: Colors.white54),
                                const SizedBox(height: 12),
                                Text('ليس لديك عملاء بعد',
                                    style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _onAdd,
                                  icon: const Icon(Icons.add),
                                  label: Text('إضافة عميل', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                                itemCount: withOrder.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) {
                                  final it = withOrder[i].it;
                                  return _buildClientCard(
                                    name: it.name,
                                    email: it.email,
                                    phone: it.phone,
                                    notes: it.notes,
                                    clientUid: it.clientUid,
                                    createdAt: it.createdAt,
                                    isPendingLocal: it.isLocal,
                                    tempIdForLocal: it.tempId,
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_impersonating) const _FullScreenLoader(),
          ],
        ),
      ),
    );
  }
} // ← نهاية _OfficeClientsPageState

/// ======================== 3) AddOfficeClientDialog ========================
class AddOfficeClientDialog extends StatefulWidget {
  const AddOfficeClientDialog({super.key});

  @override
  State<AddOfficeClientDialog> createState() => _AddOfficeClientDialogState();
}

class _AddOfficeClientDialogState extends State<AddOfficeClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ألغينا أي دوائر تحميل — حفظ محلي فوري
  static const _kNameMax = 50;
  static const _kEmailMax = 40;
  static const _kNotesMax = 1000;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    if (name.length > _kNameMax) {
      _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.');
      return;
    }
    if (email.length > _kEmailMax) {
      _showSnack(context, 'البريد الإلكتروني لا يزيد عن $_kEmailMax حرفًا.');
      return;
    }
    if (notes.length > _kNotesMax) {
      _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.');
      return;
    }

    String? phoneSend;
    final norm = normalizeLocalPhoneForUi(_phoneCtrl.text);
    if (norm == null) {
      _showSnack(context, 'أدخل رقم الجوال بشكل صحيح (10 أرقام بالضبط) أو اتركه فارغًا.');
      return;
    } else {
      phoneSend = norm;
    }

    try {
      // ✅ صف أوفلاين فوري + إغلاق الديالوج حالًا
      await OfflineSyncService.instance.enqueueCreateOfficeClient(
        name: name,
        email: email.toLowerCase(),
        phone: phoneSend,
        notes: notes,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(context, 'تم الإضافة بنجاح .');
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'حدث خطأ أثناء الحفظ: $e');
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mq = MediaQuery.of(context);
            final availableHeight = constraints.maxHeight - mq.viewInsets.bottom;
            final maxHeight = availableHeight.clamp(260.0, constraints.maxHeight);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _DarkCard(
                    minHeight: 0,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('إضافة عميل',
                              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: _dd('اسم العميل'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.singleLineFormatter,
                              _LengthLimitFormatter(
                                _kNameMax,
                                onExceed: () => _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dd('البريد الإلكتروني'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'مطلوب';
                              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
                              return ok ? null : 'صيغة بريد غير صحيحة';
                            },
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.singleLineFormatter,
                              _LengthLimitFormatter(
                                _kEmailMax,
                                onExceed: () => _showSnack(context, 'البريد الإلكتروني لا يزيد عن $_kEmailMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _dd('رقم الجوال (اختياري)'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _LengthLimitFormatter(
                                10,
                                onExceed: () => _showSnack(context, 'رقم الجوال لا يزيد عن 10 أرقام.'),
                              ),
                            ],
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return null; // اختياري
                              return s.length == 10 ? null : 'يجب أن يكون 10 أرقام بالضبط';
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _notesCtrl,
                            decoration: _dd('ملاحظات (اختياري)'),
                            minLines: 2,
                            maxLines: 6,
                            style: GoogleFonts.cairo(color: Colors.white),
                            textInputAction: TextInputAction.newline,
                            inputFormatters: [
                              _LengthLimitFormatter(
                                _kNotesMax,
                                onExceed: () => _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E40AF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text('إضافة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                                  child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ======================== 4) EditOfficeClientDialog ========================
class EditOfficeClientDialog extends StatefulWidget {
  final String clientUid;
  final String? initialName;
  final String? initialEmail;
  final String? initialPhone;
  final String? initialNotes;

  const EditOfficeClientDialog({
    super.key,
    required this.clientUid,
    this.initialName,
    this.initialEmail,
    this.initialPhone,
    this.initialNotes,
  });

  @override
  State<EditOfficeClientDialog> createState() => _EditOfficeClientDialogState();
}

class _EditOfficeClientDialogState extends State<EditOfficeClientDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const _kNameMax = 50;
  static const _kNotesMax = 1000;

  @override
  void initState() {
    super.initState();
    // ابدأ بالقيم القادمة من البطاقة (وهي نفسها مطبّق عليها pending edits)
    _nameCtrl.text = widget.initialName ?? '';
    _emailCtrl.text = widget.initialEmail ?? '';
    _phoneCtrl.text = widget.initialPhone ?? '';
    _notesCtrl.text = widget.initialNotes ?? '';
    _loadQuietly(); // تحميل هادئ يفضّل التعديلات المحلية إن وُجدت
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// ✅ تحميل هادئ لا يسبّب ارتدادًا: يفضّل أي تعديلات محليّة معلّقة ثم يكمّل من Firestore
  Future<void> _loadQuietly() async {
    try {
      // 1) إن وُجدت تعديلات محليّة معلّقة لهذا العميل، نطبّقها وننتهي (لا حاجة للشبكة)
      final pendingEdits = OfflineSyncService.instance.mapPendingOfficeEdits();
      final pe = pendingEdits[widget.clientUid];
      if (pe != null) {
        final newName  = (pe.containsKey('name'))  ? (pe['name']  ?? '') as String : _nameCtrl.text;
        final newPhone = (pe.containsKey('phone')) ? (pe['phone'] == null ? '' : pe['phone'] as String) : _phoneCtrl.text;
        final newNotes = (pe.containsKey('notes')) ? (pe['notes'] == null ? '' : pe['notes'] as String) : _notesCtrl.text;
        if (mounted) {
          setState(() {
            _nameCtrl.text  = newName;
            _phoneCtrl.text = newPhone;
            _notesCtrl.text = newNotes;
          });
        }
        // لا نرجّع للقيم القديمة حتى لو الشبكة أعادت بيانات أقدم
        return;
      }

      // 2) لو لا توجد تعديلات محلية، نقرأ بهدوء من Firestore لملء أي نقص فقط
      final officeUid = FirebaseAuth.instance.currentUser?.uid;
      if (officeUid == null) return;

      final ud = await FirebaseFirestore.instance.collection('users').doc(widget.clientUid).get();
      final um = ud.data() ?? {};

      final cd = await FirebaseFirestore.instance
          .collection('offices')
          .doc(officeUid)
          .collection('clients')
          .doc(widget.clientUid)
          .get();
      final cm = cd.data() ?? {};

      if (!mounted) return;
      setState(() {
        // لا نطغى على ما كتبه المستخدم في الحقول، نكمّل فقط ما هو فارغ
        if (_nameCtrl.text.trim().isEmpty)  _nameCtrl.text  = (um['name'] ?? cm['name'] ?? _nameCtrl.text).toString();
        if (_emailCtrl.text.trim().isEmpty) _emailCtrl.text = (um['email'] ?? cm['email'] ?? _emailCtrl.text).toString();
        if (_phoneCtrl.text.trim().isEmpty) _phoneCtrl.text = (um['phone'] ?? cm['phone'] ?? _phoneCtrl.text ?? '').toString();
        if (_notesCtrl.text.trim().isEmpty) _notesCtrl.text = (cm['notes'] ?? _notesCtrl.text ?? '').toString();
      });
    } catch (_) {/* تجاهل أي فشل شبكة */}
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    if (name.isEmpty) {
      _showSnack(context, 'اسم العميل مطلوب.');
      return;
    }
    if (name.length > _kNameMax) {
      _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.');
      return;
    }
    if (notes.length > _kNotesMax) {
      _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.');
      return;
    }

    final norm = normalizeLocalPhoneForUi(_phoneCtrl.text);
    if (norm == null) {
      _showSnack(context, 'أدخل رقم الجوال بشكل صحيح (10 أرقام بالضبط) أو اتركه فارغًا.');
      return;
    }

    try {
      // ✅ حفظ محلي فوري + إغلاق الديالوج
      await OfflineSyncService.instance.enqueueEditOfficeClient(
        clientUid: widget.clientUid,
        name: name,
        phone: norm.isEmpty ? null : norm, // null = حذف
        notes: notes,
      );
      if (!mounted) return;
      _showSnack(context, 'تم التعديل بنجاح .');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'تعذّر الحفظ: $e');
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mq = MediaQuery.of(context);
            final availableHeight = constraints.maxHeight - mq.viewInsets.bottom;
            final maxHeight = availableHeight.clamp(260.0, constraints.maxHeight);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _DarkCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('تعديل العميل',
                            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameCtrl,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('اسم العميل'),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.singleLineFormatter,
                            _LengthLimitFormatter(
                              _kNameMax,
                              onExceed: () => _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailCtrl,
                          enabled: false,
                          style: GoogleFonts.cairo(color: Colors.white60),
                          decoration: _dd('البريد الإلكتروني (غير قابل للتعديل)'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('رقم الجوال (اختياري)'),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _LengthLimitFormatter(
                              10,
                              onExceed: () => _showSnack(context, 'رقم الجوال لا يزيد عن 10 أرقام.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesCtrl,
                          minLines: 3,
                          maxLines: 6,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('ملاحظات (اختياري)'),
                          textInputAction: TextInputAction.newline,
                          inputFormatters: [
                            _LengthLimitFormatter(
                              _kNotesMax,
                              onExceed: () => _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E40AF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                                child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ======================== 5) ClientAccessDialog ========================
class ClientAccessDialog extends StatefulWidget {
  final String clientEmail;
  final String clientUid;
  const ClientAccessDialog({
    super.key,
    required this.clientEmail,
    required this.clientUid,
  });

  @override
  State<ClientAccessDialog> createState() => _ClientAccessDialogState();
}

class _ClientAccessDialogState extends State<ClientAccessDialog> {
  String? _link;
  bool _loadingLink = false;
  bool _toggling = false;
  bool? _blocked;

  Future<void> _loadBlocked() async {
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(widget.clientUid).get();
      _blocked = (d.data()?['blocked'] == true);
      if (mounted) setState(() {});
    } catch (_) {
      // أوفلاين: لا شيء، تبقى الواجهة مفتوحة
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

 Future<void> _genLink() async {
  // تحقّق مسبق: إن لم يوجد إنترنت لا نعرض لودر ونخرج برسالة
  bool online = false;
  try {
    final results = await Connectivity().checkConnectivity();
    online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      final r = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2));
      online = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    }
  } catch (_) {
    online = false;
  }

  if (!online) {
    _showSnack(context, 'لا يوجد اتصال بالإنترنت');
    return; // لا نُظهر أي دائرة تدور
  }

  setState(() {
    _loadingLink = true;
    _link = null;
  });

  try {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('generatePasswordResetLink');
    final res = await callable.call({'email': widget.clientEmail});
    _link = (res.data as Map?)?['resetLink']?.toString();
    if (_link == null || _link!.isEmpty) {
      _showSnack(context, 'تعذّر توليد الرابط.');
    }
    if (mounted) setState(() {});
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'unavailable') {
      _showSnack(context, 'لا يوجد اتصال بالإنترنت');
    } else {
      _showSnack(context, e.message ?? 'تعذّر توليد الرابط.');
    }
  } on SocketException {
    _showSnack(context, 'لا يوجد اتصال بالإنترنت');
  } catch (_) {
    _showSnack(context, 'تعذّر الاتصال. حاول عند توفر الإنترنت.');
  } finally {
    if (mounted) setState(() => _loadingLink = false);
  }
}


  Future<void> _toggleBlocked(bool value) async {
  // تحقّق مسبق من الاتصال قبل فتح نافذة التأكيد
  bool online = false;
  try {
    final results = await Connectivity().checkConnectivity();
    online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      final r = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2));
      online = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    }
  } catch (_) {
    online = false;
  }

  if (!online) {
    _showSnack(context, 'لا يوجد اتصال بالإنترنت');
    return; // لا نفتح نافذة التأكيد
  }

  // يوجد اتصال → تابع بعرض نافذة التأكيد
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: _DarkCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value ? 'إيقاف دخول العميل' : 'إلغاء الإيقاف',
                style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            Text(
              value
                  ? 'سيتم منع العميل من دخول التطبيق حتى إعادة التفعيل.\nهل ترغب بالمتابعة؟'
                  : 'سيُسمح للعميل بالدخول من جديد.\nهل ترغب بالمتابعة؟',
              style: GoogleFonts.cairo(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('تأكيد'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dctx, false),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                    child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true) return;

  setState(() => _toggling = true);
  try {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('updateUserStatus');
    await callable.call({'uid': widget.clientUid, 'blocked': value});
    _blocked = value;
    if (mounted) setState(() {});
    _showSnack(context, value ? 'تم إيقاف دخول العميل.' : 'تم السماح بدخول العميل.');
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'unavailable') {
      _showSnack(context, 'لا يوجد اتصال بالإنترنت');
    } else {
      _showSnack(context, e.message ?? 'تعذّر تعديل الحالة.');
    }
  } on SocketException {
    _showSnack(context, 'لا يوجد اتصال بالإنترنت');
  } catch (_) {
    _showSnack(context, 'تعذّر الاتصال. حاول عند توفر الإنترنت.');
  } finally {
    if (mounted) setState(() => _toggling = false);
  }
}


  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _DarkCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صلاحيات الدخول / كلمة المرور',
                  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              SelectableText('البريد: ${widget.clientEmail}', style: GoogleFonts.cairo(color: Colors.white70)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loadingLink ? null : _genLink,
                icon: const Icon(Icons.link),
                label: _loadingLink
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('توليد رابط تعيين كلمة مرور'),
              ),
              const SizedBox(height: 8),
              if (_link != null && _link!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _link!,
                          maxLines: 3,
                          style: GoogleFonts.cairo(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _link!));
                          if (mounted) _showSnack(context, 'تم النسخ.');
                        },
                        icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('السماح بدخول العميل', style: GoogleFonts.cairo(color: Colors.white)),
                  const Spacer(),
                  Switch(
                    value: !(_blocked ?? false),
                    onChanged: _toggling ? null : (v) => _toggleBlocked(!v),
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFF22C55E),
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                      child: Text('إغلاق', style: GoogleFonts.cairo(color: Colors.white70)),
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
}

/// ======================== 6) DeleteClientDialog ========================
class DeleteClientDialog extends StatefulWidget {
  final String clientName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const DeleteClientDialog({
    super.key,
    required this.clientName,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<DeleteClientDialog> createState() => _DeleteClientDialogState();
}

class _DeleteClientDialogState extends State<DeleteClientDialog> {
  bool _understand = false;

  Future<void> _requireConsentWarning() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: _DarkCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تأكيد مطلوب',
                  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'قبل الحذف النهائي، يجب الإقرار بالموافقة على الحذف عبر تفعيل مربع التأكيد.',
                style: GoogleFonts.cairo(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(dctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E40AF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _DarkCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x26FF4D4D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x40FF4D4D)),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFFF6B6B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('حذف العميل',
                        style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'سيتم حذف العميل "${widget.clientName}" نهائيًا مع كافة بياناته (العقارات، العقود، الفواتير، المرفقات، الإشعارات، وغيرها). لا يمكن التراجع.',
                  style: GoogleFonts.cairo(color: Colors.white70, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x14FF4D4D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x26FF4D4D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFA726)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('هذا الإجراء دائم وسيؤدي إلى فقدان كل السجلات المرتبطة بهذا العميل.',
                          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _understand,
                onChanged: (v) => setState(() => _understand = v ?? false),
                activeColor: const Color(0xFFFF6B6B),
                checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('نعم، أفهم العواقب وأرغب في حذف هذا العميل نهائيًا.',
                    style: GoogleFonts.cairo(color: Colors.white70)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (!_understand) {
                          _requireConsentWarning();
                          return;
                        }
                        widget.onConfirm();
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('حذف نهائي'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7F1D1D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('رجوع', style: GoogleFonts.cairo(color: Colors.white70)),
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
}
