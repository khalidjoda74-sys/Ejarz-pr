// lib/ui/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/services/user_scope.dart';
import '../data/services/hive_service.dart';
import '../data/constants/boxes.dart';   // تأكد من الدالة boxName
import '../utils/contract_utils.dart';   // لحساب إجمالي المستحقات من العقود
import 'notifications_screen.dart' show NotificationsScreen, NotificationsCounter;
import 'widgets/notifications_bell.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/office_client_guard.dart';




import 'contracts_screen.dart'
    show
        Contract,
        ContractTerm,
        PaymentCycle,
        AdvanceMode,
        ContractsScreen,
        ContractQuickFilter,
        isContractOverdueForHome;


// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Hive + موديلات/شاشة العقود
import 'package:hive_flutter/hive_flutter.dart';


// باقي الشاشات
import 'properties_screen.dart';
import 'tenants_screen.dart';
import 'invoices_screen.dart';
import 'reports_screen.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// جلسة المكتب (للعودة عند الانتحال)
import '../screens/office/office.dart' show OfficeSession;

const Color kCreamBg = Color(0xFFFFFBEB);

class HomeScreen extends StatefulWidget {
  final String title;
  const HomeScreen({super.key, this.title = 'الرئيسية'});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final int _index = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  String get _currentTitle => 'الرئيسية';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  // لفتح الصناديق قبل استخدامها
  bool _hiveReady = false;
  Future<void>? _openHiveFuture;

  // إظهار زر رجوع للمكتب عند الانتحال
  bool _hasOfficeReturn = false;

  // ===== حارس الإنترنت لعملاء المكتب / جلسة المكتب =====
  bool _clientNeedsInternet = false; // هل هذه الجلسة يجب أن تعمل فقط مع إنترنت؟
  bool _hasConnection = true;        // حالة الاتصال الحالية
  StreamSubscription<List<ConnectivityResult>>? _connSub;


  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });

    _checkOfficeReturn(); // هل نحن في وضع الانتحال؟

    _checkOfficeReturn(); // هل نحن في وضع الانتحال؟

   

    // راقب قيود الاشتراك/الحظر


    // راقب قيود الاشتراك/الحظر
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) async {
        if (!doc.exists) return;
        final m = doc.data() ?? {};

final blocked = (m['blocked'] ?? false) == true;
final active  = (m['subscription_active'] ?? true) == true;

// 1️⃣ نحاول أولاً end_date_ksa كـ "اليوم الأخير" في السعودية
DateTime? inclusiveEndKsa;
final endKsaText = (m['end_date_ksa'] as String?)?.trim();
if (endKsaText != null && endKsaText.isNotEmpty) {
  final parts = endKsaText.split('-'); // yyyy-MM-dd
  if (parts.length >= 3) {
    final y  = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    final d  = int.tryParse(parts[2]);
    if (y != null && mo != null && d != null) {
      inclusiveEndKsa = DateTime(y, mo, d);
    }
  }
}

// 2️⃣ fallback من subscription_end لو end_date_ksa غير موجود
if (inclusiveEndKsa == null) {
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
    final endUtc = end.toUtc();
    final endKsa = endUtc.add(const Duration(hours: 3));
    inclusiveEndKsa = DateTime(endKsa.year, endKsa.month, endKsa.day);
  }
}

// 3️⃣ نحسب "تاريخ اليوم" بتوقيت السعودية
final nowUtc  = DateTime.now().toUtc();
final nowKsa  = nowUtc.add(const Duration(hours: 3));
final todayKsa = DateTime(nowKsa.year, nowKsa.month, nowKsa.day);

// 4️⃣ يعتبر منتهي فقط إذا اليوم بعد اليوم الأخير
final expired = inclusiveEndKsa != null && todayKsa.isAfter(inclusiveEndKsa);


        if (blocked || !active || expired) {
          await _userSub?.cancel();
          _userSub = null;

          if (!mounted) return;

          final msg = blocked
              ? 'تم إيقاف حسابك. تواصل مع الإدارة.'
              : expired
                  ? 'انتهى اشتراكك.'
                  : 'تم تعطيل اشتراكك.';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));

          // 🔐 إيقاف بناء الواجهة التي تعتمد على Hive قبل تسجيل الخروج
          if (mounted) {
            setState(() {
              _hiveReady = false;
            });
          }

          // 🔐 تسجيل خروج كامل مثل زر "تسجيل الخروج" تمامًا
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
            await session.put('isOfficeClient', false); // رجوع للوضع الطبيعي
          }

          // 👇 امسح أي UID ثابت من user_scope
          clearFixedUid();

          // 👇 حدّث حارس عميل المكتب
          await OfficeClientGuard.refreshFromLocal();

          if (!mounted) return;
          await Future.delayed(const Duration(milliseconds: 150));
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        }

      });
    }

    // افتح صناديق Hive اللازمة قبل القراءة منها على الرئيسية
    _openHiveFuture = _openHiveBoxesForCurrentUser();
    // ✅ تفعيل حارس الإنترنت لعملاء المكتب / جلسة المكتب
    _initOnlineGuard();

  }

  @override
  void dispose() {
    _userSub?.cancel();
    _connSub?.cancel(); // ✅ إلغاء مراقبة الاتصال
    super.dispose();
  }



  // ====== فتح الصناديق اللازمة لهذا المستخدم ======
  Future<void> _openHiveBoxesForCurrentUser() async {
    try {
      // صندوق العقود مستخدم في الصفحة + شاشة العقود
      await _ensureContractsBoxOpen();

      // إن كانت هناك صناديق أخرى تُعرض على الرئيسية، افتحها هنا بنفس النمط.
      // مثال (حسب مشروعك):
      // await _ensureBoxOpen(boxName('propertiesBox'));
      // await _ensureBoxOpen(boxName('tenantsBox'));
      // await _ensureBoxOpen(boxName('invoicesBox'));

      if (!mounted) return;
      setState(() => _hiveReady = true);
    } catch (e) {
      if (!mounted) return;
      _hiveReady = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح قاعدة البيانات المحلية. جرّب إعادة المحاولة.')),
      );
      setState(() {});
    }
  }

  Future<void> _ensureBoxOpen(String name) async {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
  }

  Future<void> _ensureContractsBoxOpen() async {
    final name = boxName('contractsBox');
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<Contract>(name);
    }
  }

  // ====== فحص إمكانية العودة للمكتب (في حال الانتحال) ======
  Future<void> _checkOfficeReturn() async {
    try {
      final token = await OfficeSession.officeToken;
      if (!mounted) return;
      setState(() => _hasOfficeReturn = (token != null && token.isNotEmpty));
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasOfficeReturn = false);
    }
  }

  // الرجوع للمكتب
  Future<void> _onBackToOffice() async {
    await OfficeSession.backToOffice(context);
  }

  // مزوّد تاريخ انتهاء الاشتراك ليستخدمه NotificationsBell
Future<DateTime?> _subscriptionEndProvider() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;

    final data = doc.data() ?? {};

    // 1) نحاول أولاً استخدام end_date_ksa إن وُجد (نفس الذي تستخدمه نافذة "اشتراكي")
    final endKsaText = (data['end_date_ksa'] as String?)?.trim();
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final normalized = endKsaText.replaceAll('/', '-'); // ندعم yyyy/MM/dd و yyyy-MM-dd
      final parts = normalized.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          // هذا هو "اليوم الأخير للاشتراك" في السعودية
          return DateTime(y, m, d);
        }
      }
    }

    // 2) لو ما عندنا end_date_ksa (حسابات قديمة) نرجع نحسب من subscription_end
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

    // نحول الـ DateTime إلى "تاريخ فقط" بتوقيت السعودية (نفس منطق subscription_sheet.dart)
    final utc = dt.toUtc();
    final ksa = utc.add(const Duration(hours: 3)); // KSA = UTC+3
    return DateTime(ksa.year, ksa.month, ksa.day); // اليوم فقط بدون ساعة

  } catch (_) {
    return null;
  }
}


 
  // ===== حارس الإنترنت لعملاء المكتب / جلسة المكتب =====
  Future<void> _initOnlineGuard() async {
    try {
      const boxName = 'sessionBox';
      final session = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);

      final needs = (session.get('clientNeedsInternet') ?? false) == true;

      if (!mounted) return;
      setState(() {
        _clientNeedsInternet = needs;
      });

      if (!needs) {
        // هذا الحساب لا يحتاج إنترنت ⇒ لا حارس
        _hasConnection = true;
        _connSub?.cancel();
        _connSub = null;
        return;
      }

      // فحص مبدئي + الاشتراك في تغيّر الاتصال
      await _checkCurrentConnection();

      _connSub?.cancel();
      _connSub = Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> results) async {
          bool hasNet = results.any((r) => r != ConnectivityResult.none);

          if (hasNet) {
            // نحاول التأكد من اتصال فعلي
            try {
              final lookup = await InternetAddress.lookup('google.com')
                  .timeout(const Duration(seconds: 3));
              hasNet = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
            } catch (_) {
              hasNet = false;
            }
          }

          if (!mounted) return;
          setState(() {
            _hasConnection = hasNet;
          });
        },
      );
    } catch (_) {
      // لو حدث خطأ لا نحجب المستخدم (سلامة)
    }
  }

  Future<void> _checkCurrentConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      bool hasNet = results.any((r) => r != ConnectivityResult.none);

      if (hasNet) {
        try {
          final lookup = await InternetAddress.lookup('google.com')
              .timeout(const Duration(seconds: 3));
          hasNet = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
        } catch (_) {
          hasNet = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _hasConnection = hasNet;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasConnection = false;
      });
    }
  }

  /// طبقة شفافة تحجب الشاشة عندما لا يوجد اتصال
  Widget _buildOnlineGuardOverlay() {
    // لو الحارس غير مفعّل أو الاتصال شغال → لا شيء
    if (!_clientNeedsInternet || _hasConnection) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withOpacity(0.75),
          alignment: Alignment.center,
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 52,
                color: Colors.white,
              ),
              SizedBox(height: 16.h),
              Text(
                'هذا الحساب مرتبط بمكتب عقاري',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'يحتاج إلى اتصال بالإنترنت لاستخدام التطبيق.\nتحقّق من الاتصال ثم حاول مرة أخرى.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ====== تنقل سفلي مع ضمان فتح الصناديق قبل الدخول ======
  void _handleBottomTap(int i) async {
    if (i == _index) return;

    try {
      if (i == 3) {
        // العقود
        await _ensureContractsBoxOpen();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContractsScreen()),
        );
        return;
      }

      switch (i) {
        case 1:
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
          break;
        case 2:
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح الشاشة: $e')),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return false;
    }

final shouldExit = await showDialog<bool>(
  context: context,
  useRootNavigator: true,
  builder: (dialogCtx) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      backgroundColor: Colors.white,

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
                'تأكيد الخروج',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.w900,
                  fontSize: 16.sp,
                  color: const Color(0xFFB91C1C),
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

      contentPadding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
      content: Text(
        'هل أنت متأكد من رغبتك في الخروج من التطبيق؟',
        style: GoogleFonts.tajawal(fontSize: 14.sp, height: 1.5, fontWeight: FontWeight.w700),
        textAlign: TextAlign.right,
      ),

      actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                child: Text('خروج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900)),
              ),
            ),
            SizedBox(height: 10.h),
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

    return shouldExit ?? false;
  }

  // ====== اختصارات تفتح العقود بعد ضمان الصندوق ======
  Future<void> _openContracts({ContractQuickFilter? filter}) async {
    try {
      await _ensureContractsBoxOpen();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractsScreen(
            initialFilter: filter ?? ContractQuickFilter.nearDue,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح العقود: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          key: _scaffoldKey,
          

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
  automaticallyImplyLeading: false,
  centerTitle: true,
  // 👇 دائمًا زر القائمة الجانبية
  leading: const AppMenuButton(iconColor: Colors.white),
  title: Text(
    _currentTitle,
    style: GoogleFonts.cairo(
      fontSize: 22.sp,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    ),
  ),
  actions: [
    NotificationsBell(
      subscriptionEndProvider: _subscriptionEndProvider,
      iconColor: Colors.white,
      iconSize: 25,
    ),
  ],
),


                    body: Stack(
            children: [
              // الخلفية
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
                  ),
                ),
              ),
              Positioned(
                  top: -120,
                  right: -80,
                  child: _softCircle(220.r, const Color(0x33FFFFFF))),
              Positioned(
                  bottom: -140,
                  left: -100,
                  child: _softCircle(260.r, const Color(0x22FFFFFF))),

              // لا تبني ما يعتمد على Hive قبل أن يكون جاهزًا
              if (!_hiveReady)
                const Center(child: CircularProgressIndicator())
              else
                _buildHomeBody(),

              // ✅ طبقة حارس الإنترنت لعملاء المكتب / جلسة المكتب
              _buildOnlineGuardOverlay(),
            ],
          ),



          bottomNavigationBar: AppBottomNav(
            key: _bottomNavKey,
            currentIndex: 0,
            onTap: _handleBottomTap,
          ),
        ),
      ),
    );
  }



  Widget _buildHomeBody() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                   Align(
  alignment: Alignment.centerRight,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 230.w),
    child: AnimatedBuilder(
      // نسمع لأي تغيّر في العقود والفواتير
      animation: Listenable.merge([
        Hive.box<Contract>(boxName(kContractsBox)).listenable(),
        Hive.box<Invoice>(boxName(kInvoicesBox)).listenable(),
      ]),
      builder: (context, _) {
        double receivables = 0;
        try {
          // نفس منطق "المستحقات" في شاشة التقارير
          receivables = sumReceivablesFromContractsExact(
            includeArchived: false,
          );
        } catch (_) {
          receivables = 0;
        }

        final display = _moneyTrunc(receivables);

        return _FancyCard(
          background: kCreamBg,
          // لا يفتح أي شاشة عند الضغط
          child: Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: const Icon(
                  Icons.payments,
                  color: Color(0xFF1E40AF),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي المستحقات',
                      style: GoogleFonts.cairo(
                        fontSize: 13.sp,
                        color: const Color(0xFF2D2D2D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4.h),
Text(
  '${receivables.toStringAsFixed(2)} ريال',
  style: GoogleFonts.cairo(
    fontSize: 20.sp,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0F172A),
  ),
),

                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
),


                    SizedBox(height: 14.h),
Row(
  children: [
    // 🔴 كرت "المدفوعات المتأخرة"
    Expanded(
      child: ValueListenableBuilder(
        valueListenable:
            Hive.box<Contract>(boxName('contractsBox')).listenable(),
        builder: (context, Box<Contract> box, _) {
          int overdueCount = 0;

          try {
            for (final c in box.values) {
              // تجاهل العقود المؤرشفة
              if (c.isArchived == true) continue;

              // نفس منطق فلتر "المدفوعات المتأخرة" في شاشة العقود
              if (isContractOverdueForHome(c)) {
                overdueCount++;
              }
            }
          } catch (_) {
            overdueCount = 0;
          }

          return _FancyCard(
            background: kCreamBg,
            onTap: () => _openContracts(
              filter: ContractQuickFilter.overdue,
            ),
            child: _StatTile(
              title: 'المدفوعات المتأخرة',
              value: overdueCount.toString(),
              valueColor: Colors.red.shade700,
            ),
          );
        },
      ),
    ),

    SizedBox(width: 10.w),

    // 🟡 كرت "التنبيهات" (يرجع كما كان بالضبط)
    Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18.r),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
        child: _FancyCard(
          background: kCreamBg,
          child: NotificationsCounter(
            builder: (count) => _StatTile(
              title: 'التنبيهات',
              value: count.toString(),
              valueColor: count > 0 ? Colors.red.shade700 : null,
            ),
          ),
        ),
      ),
    ),
  ],
),


          SizedBox(height: 22.h),

          // الصف الأول: العقارات - المستأجرين - العقود
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _QuickButton(
                icon: Icons.apartment,
                label: 'العقارات',
                onTap: () => _handleBottomTap(1),
              ),
              _QuickButton(
                icon: Icons.people,
                label: 'المستأجرين',
                onTap: () => _handleBottomTap(2),
              ),
              _QuickButton(
                icon: Icons.assignment,
                label: 'العقود',
                onTap: () => _handleBottomTap(3),
              ),
            ],
          ),

          SizedBox(height: 14.h),

          // الصف الثاني: الصيانة - الفواتير - التقارير
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _QuickButton(
                icon: Icons.build,
                label: 'الصيانة',
                onTap: () {
                  Navigator.pushNamed(context, '/maintenance');
                },
              ),
              _QuickButton(
                icon: Icons.receipt_long,
                label: 'الفواتير',
                onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const InvoicesScreen()));
                },
              ),
              _QuickButton(
                icon: Icons.insights,
                label: 'التقارير',
                onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ReportsScreen()));
                },
              ),
            ],
          ),

          SizedBox(height: 22.h),
          _FancyCard(
            background: kCreamBg,
            onTap: () => _openContracts(
                filter: ContractQuickFilter.nearDue),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'أقرب استحقاقات الإيجار',
                    style: GoogleFonts.cairo(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A)),
                  ),
                ),
                const Icon(Icons.arrow_back_ios,
                    size: 16, color: Color(0xFF334155)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfficeClientOfflineOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withOpacity(0.75),
          alignment: Alignment.center,
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.white),
              SizedBox(height: 16.h),
              Text(
                'هذا الحساب تابع لمكتب عقاري',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'يحتاج إلى اتصال بالإنترنت لاستخدام التطبيق.\nتحقّق من الاتصال ثم حاول مرة أخرى.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // تنسيق المبلغ مثل شاشة التقارير (بدون كسور مزعجة)
  String _moneyTrunc(num v) {
    final t = (v * 100).truncate() / 100.0;
    return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
  }

  // ---------- Helpers (منطق مختصر لشاشة العقود) ----------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _monthsPerCycleHome(PaymentCycle c) {
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

  int _monthsInTermHome(ContractTerm t) {
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

  DateTime _addMonthsHome(DateTime d, int months) {
    if (months == 0) return d;
    final y0 = d.year;
    final m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final day = d.day;
    final lastDay =
        (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(y, m, safeDay);
  }

  int _coveredMonthsByAdvanceHome(Contract c) {
    if (c.advanceMode != AdvanceMode.coverMonths) return 0;
    if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
    final months = _monthsInTermHome(c.term);
    if (months <= 0) return 0;
    final monthlyValue = c.totalAmount / months;
    final covered = ((c.advancePaid ?? 0) / monthlyValue).floor();
    return covered.clamp(0, months);
  }

  DateTime? _firstDueAfterAdvanceHome(Contract c) {
    if (c.term == ContractTerm.daily) return null;
    final start = _dateOnly(c.startDate);
    final end = _dateOnly(c.endDate);

    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvanceHome(c);
      final termMonths = _monthsInTermHome(c.term);
      if (covered >= termMonths) return null;

      final mpc = _monthsPerCycleHome(c.paymentCycle);
      final cyclesCovered = (covered / mpc).ceil();
      final first = _addMonthsHome(start, cyclesCovered * mpc);
      if (!first.isBefore(start) && !first.isAfter(end)) return first;
      return null;
    }
    return start;
  }

  bool _isOverdueHome(Contract c) {
    if (c.isTerminated) return false;

    final today = _dateOnly(DateTime.now());
    if (c.term == ContractTerm.daily) {
      return _dateOnly(c.endDate).isBefore(today);
    }
    final first = _firstDueAfterAdvanceHome(c);
    if (first == null) return false;
    return _dateOnly(first).isBefore(today);
  }

  // === منطق "المدفوعات المتأخرة" كما في فلتر شاشة العقود ===

  bool _dailyAlreadyPaidHome(Contract c) {
    if (c.term != ContractTerm.daily) return false;
    try {
      if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return false;
      final box = Hive.box<Invoice>(boxName(kInvoicesBox));

      // نعتبر العقد اليومي مُسدَّد إذا عنده فاتورة مدفوعة بالكامل وغير ملغاة
      return box.values.any((inv) {
        if (inv.contractId != c.id) return false;
        if (inv.isCanceled == true) return false;
        return (inv.paidAmount >= (inv.amount - 0.000001));
      });
    } catch (_) {
      return false;
    }
  }

  bool _paidForDueHome(Contract c, DateTime due) {
    try {
      if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return false;
      final box = Hive.box<Invoice>(boxName(kInvoicesBox));
      final dOnly = _dateOnly(due);

      for (final inv in box.values) {
        if (inv.contractId != c.id) continue;
        if (inv.isCanceled == true) continue;

        final note = (inv.note ?? '').toString();

        // فاتورة سداد المقدم لا نعتبرها قسطاً عاديّاً
        final isAdvanceInvoice =
            (c.advanceMode == AdvanceMode.deductFromTotal) &&
            note.contains('سداد مقدم عقد');

        if (isAdvanceInvoice) continue;

        final fullyPaid = inv.paidAmount >= (inv.amount - 0.000001);
        if (fullyPaid && _dateOnly(inv.dueDate) == dOnly) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  bool _isOverdueForHome(Contract c) {
    final today = _dateOnly(DateTime.now());

    if (c.term == ContractTerm.daily) {
      // اليومي: متأخرة إذا لم تُسدَّد وكان البدء قبل اليوم
      return !_dailyAlreadyPaidHome(c) &&
          _dateOnly(c.startDate).isBefore(today);
    }

    // نحتاج أي قسط غير مدفوع "قبل اليوم"
    final first = _firstDueAfterAdvanceHome(c);
    if (first == null) return false;

    final endOnly = _dateOnly(c.endDate);
    var due = _dateOnly(first);

    while (due.isBefore(endOnly) && due.isBefore(today)) {
      if (!_paidForDueHome(c, due)) {
        // وجدنا قسطاً غير مدفوع قبل اليوم
        return true;
      }
      // نتقدّم دورة واحدة حسب الـ paymentCycle
      due = _dateOnly(
          _addMonthsHome(due, _monthsPerCycleHome(c.paymentCycle)));
    }
    return false;
  }


  // ---------------------------------------------------------------

  static Widget _softCircle(double size, Color color) {
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }
}

class _FancyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? background;
  final VoidCallback? onTap;

  const _FancyCard({
    required this.child,
    this.padding,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16.r);

    final content = Container(
      padding: padding ?? EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: background,
        gradient: background == null
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFF)],
              )
            : null,
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0x1A0F172A)),
        boxShadow: [
          BoxShadow(
              color: const Color(0x66000000).withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;
  const _StatTile({required this.title, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: GoogleFonts.cairo(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155))),
      SizedBox(height: 8.h),
      Text(value,
          style: GoogleFonts.cairo(
              fontSize: 22.sp,
              fontWeight: FontWeight.w900,
              color: valueColor ?? const Color(0xFF0F172A))),
    ]);
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final double size = 92.w;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        borderRadius: BorderRadius.circular(16.r),
        elevation: 6,
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                  color: const Color(0x66000000).withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16.r),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 28.sp),
                SizedBox(height: 8.h),
                Text(label,
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.sp)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
