// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';


// Firebase (للأوفلاين والمزامنة وتسجيل الدخول)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Data / Repos / Sync
import 'data/constants/boxes.dart';
import 'data/services/hive_service.dart';
import 'data/services/user_scope.dart';
import 'data/sync/sync_bridge.dart';
import 'data/services/offline_sync_service.dart';
import 'data/services/firestore_user_collections.dart';
import 'data/repos/tenants_repo.dart';

// Models
import 'models/property.dart';
import 'models/tenant.dart';

// العقود
import 'ui/contracts_screen.dart'
    show Contract, ContractAdapter, AddOrEditContractScreen;
import 'ui/contracts_screen.dart' as contracts_ui show ContractsScreen;

// الفواتير
import 'ui/invoices_screen.dart'
    show Invoice, InvoiceAdapter, InvoicesRoutes, kInvoicesBox;

// الصيانة
import 'ui/maintenance_screen.dart'
    show
        MaintenanceRequest,
        MaintenanceRequestAdapter,
        MaintenancePriorityAdapter,
        MaintenanceStatusAdapter,
        MaintenanceRoutes;

// التقارير
import 'ui/reports_screen.dart' show ReportsRoutes;

// UI
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

// لوحة المكتب
import 'screens/office/office.dart';

// خلفية عامة فاتحة (لا نجعلها سوداء حتى لا تتأثر الشاشات الداخلية والأزرار)
const Color kRouteBg = Color(0xFFFFFFFF);

// يجعل انتقال الصفحات بدون أي أنيميشن
class NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // لا نستخدم أي حركة
  }
}

/// ============================================================================
/// مزوّد الوقت (السعودي) عبر Cloud Function
/// ============================================================================
class SaTime {
  static int _offsetMs = 0;

  static DateTime now() => DateTime.now().add(Duration(milliseconds: _offsetMs));

  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  static Future<void> init() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getSaudiTime');
      final res = await callable.call();
      final data = res.data as Map;
      final serverMs = (data['millisecondsSinceEpoch'] as num).toInt();
      final localMs = DateTime.now().millisecondsSinceEpoch;
      _offsetMs = serverMs - localMs;
    } catch (_) {
      _offsetMs = 0;
    }
  }
}

Future<String?> __resolveUserRole(User u) async {
  try {
    final t = await u.getIdTokenResult(true);
    final r = t.claims?['role']?.toString();
    if (r != null && r.isNotEmpty) return r;
  } catch (_) {}
  try {
    final d =
        await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    return d.data()?['role']?.toString();
  } catch (_) {}
  return null;
}

/* ===================== main ===================== */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // شريط الحالة وشريط النظام السفلي بالأسود كما تريد
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // مقاس مرجعي؛ غيّره عند الحاجة
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp(
          useInheritedMediaQuery: true, // مهم لتناسق القياسات
          debugShowCheckedModeBanner: false,
          title: 'Real Estate Owner',
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: NoGlowScrollBehavior(),

          // ✅ قفل تكبير النص + SafeArea سفلي عالمي لمنع تجاوز شريط الرجوع/التنقل
          builder: (context, innerChild) {
            final mq = MediaQuery.of(context);
            final body = ColoredBox(
              color: kRouteBg,
              child: innerChild ?? const SizedBox.shrink(),
            );
            final safe = SafeArea(top: false, bottom: true, child: body);
            return MediaQuery(
              data: mq.copyWith(
                // يمنع تضخيم النص على أندرويد 15
                textScaler: const TextScaler.linear(1.0),
                // للنسخ الأقدم من Flutter يمكن استخدام:
                // textScaleFactor: 1.0,
              ),
              child: safe,
            );
          },

          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,

            // خلفيات عامة بيضاء
            scaffoldBackgroundColor: kRouteBg,
            canvasColor: kRouteBg,

            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E40AF),
              brightness: Brightness.light,
            ),
            fontFamily: GoogleFonts.cairo().fontFamily,

            // AppBar أسود
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              elevation: 0,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.black,
                statusBarIconBrightness: Brightness.light,
              ),
            ),

            // BottomNavigationBar أسود (ثابت)
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.black,
              selectedItemColor: Colors.white,
              unselectedItemColor: Color(0xFF9CA3AF),
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),

            // NavigationBar (Material 3) عند الحاجة
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.black,
              indicatorColor: Colors.white12,
              elevation: 8,
              labelTextStyle: MaterialStateProperty.all(
                const TextStyle(color: Colors.white),
              ),
              iconTheme: MaterialStateProperty.all(
                const IconThemeData(color: Colors.white),
              ),
            ),

            // توافق مع نسختك: BottomAppBarThemeData
            bottomAppBarTheme: const BottomAppBarThemeData(
              color: Colors.black,
              elevation: 8,
            ),

            // الأزرار الافتراضية بخلفية بيضاء
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(Colors.white),
                foregroundColor: MaterialStateProperty.all(Colors.black),
                elevation: MaterialStateProperty.all(2),
              ),
            ),

            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.fuchsia: NoAnimationPageTransitionsBuilder(),
              },
            ),
          ),

          routes: {
            ...InvoicesRoutes.routes(),
            ...MaintenanceRoutes.routes(),
            ...ReportsRoutes.routes(),
            '/home': (_) => const HomeScreen(),
            '/login': (_) => const LoginScreen(),
            '/office': (_) => const OfficeHomePage(),
            '/contracts': (_) => const contracts_ui.ContractsScreen(),
            '/contracts/new': (_) => const AddOrEditContractScreen(),
          },
          home: const SplashRouter(),
        );
      },
    );
  }
}

/// شاشة شعار/توجيه تعتمد على Firebase Auth
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  StreamSubscription<User?>? _authSub;

  // خدمة المزامنة للأوفلاين (سنجلتون)
  final _offlineSync = OfflineSyncService.instance;

  @override
  void initState() {
    super.initState();
    _kickoff();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _offlineSync.dispose();
    super.dispose();
  }

  /// تهيئة Firebase الأساسية مرّة واحدة فقط (دون ربطها بسرعة الشبكة)
  Future<void> _ensureFirebaseCore() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }


  /// كل التهيئة الثقيلة هنا وتعمل أثناء عرض السبلاش
  Future<void> _bootstrapAll() async {
    // 1) Firebase
    await _ensureFirebaseCore();

    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);


    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    try {
      await FirebaseAuth.instance.setLanguageCode('ar');
    } catch (_) {}

    // 2) Hive + Adapters + فتح الصناديق
    await Hive.initFlutter();
    _registerHiveAdapters();

    // افتح صناديق هذا المستخدم (أو "guest")
    await HiveService.ensureReportsBoxesOpen();

    // جسور المزامنة
    await SyncManager.instance.startAll();

    // خدمة الأوفلاين للمستخدم الحالي (إن وُجد)
    final currUser = FirebaseAuth.instance.currentUser;
    if (currUser != null) {
      final uc = UserCollections(currUser.uid);
      final repo = TenantsRepo(uc);
      _offlineSync.dispose();
      await _offlineSync.init(uc: uc, repo: repo);
    }

    // توقيت السعودية (سيرفر)
    await SaTime.init();

    // متابعة تغيّر تسجيل الدخول
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await SyncManager.instance.stopAll();
      _offlineSync.dispose();

      // أغلق صناديق المستخدم السابق
      final candidates = <String>{
        boxName('sessionBox'),
        boxName('contractsBox'),
        boxName('propertiesBox'),
        boxName('tenantsBox'),
        boxName(kInvoicesBox),
        boxName('maintenanceBox'),
        boxName('reportsBox'),
      };

      for (final name in candidates) {
        if (Hive.isBoxOpen(name)) {
          try {
            await Hive.box(name).close();
          } catch (_) {}
        }
      }

      // افتح صناديق المستخدم الحالي
      await HiveService.ensureReportsBoxesOpen();

      // جسور هذا المستخدم
      await SyncManager.instance.startAll();

      // خدمة الأوفلاين لهذا المستخدم
      if (user != null) {
        final uc = UserCollections(user.uid);
        final repo = TenantsRepo(uc);
        await _offlineSync.init(uc: uc, repo: repo);
      }

      if (mounted) setState(() {});
    });
  }

  Future<void> _kickoff() async {
    // 1) تهيئة Firebase الأساسية بسرعة (غير مرتبطة بسرعة الإنترنت)
    await _ensureFirebaseCore();

    // 2) ابدأ التهيئة الثقيلة في الخلفية أثناء عرض شاشة الشعار
    _bootstrapAll(); // لا ننتظر هذه الـ Future هنا

    // 3) نضمن بقاء شاشة الشعار لفترة قصيرة فقط
    await const Duration(seconds: 2).delay();

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    // 👇 أولاً: لو ما في مستخدم Firebase نحاول نفتح آخر مستخدم محفوظ (أوفلاين)
    if (user == null) {
      final sp = await SharedPreferences.getInstance();
      final lastUid  = sp.getString('last_login_uid');
      final lastRole = sp.getString('last_login_role');

      if (lastUid == null || lastRole == null) {
        // ما في أي دخول سابق محفوظ → نذهب لتسجيل الدخول
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // ثبّت الـ UID للأوفلاين
      setFixedUid(lastUid);

      // افتح صناديق هذا المستخدم
      await HiveService.ensureReportsBoxesOpen();

      // تهيئة خدمة الأوفلاين لهذا المستخدم (حتى لو مافيش FirebaseAuth user)
      final uc = UserCollections(lastUid);
      final repo = TenantsRepo(uc);
      await _offlineSync.init(uc: uc, repo: repo);

      if (!mounted) return;

      final role = lastRole.toLowerCase();
      if (role == 'office') {
        Navigator.of(context).pushReplacementNamed('/office');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
      return;
    }

    // هنا في مستخدم Firebase عادي → المنطق السابق كما هو
    final role = (await __resolveUserRole(user))?.toLowerCase() ?? 'client';
    if (role == 'office') {
      Navigator.of(context).pushReplacementNamed('/office');
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }

  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // خلفية السبلاش بيضاء (لا سوداء)
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 200.w,
                    height: 200.w,
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ====== امتداد صغير لتأخير أنيق ====== */
extension _Delay on Duration {
  Future<void> delay() => Future.delayed(this);
}

// ===================== تسجيل Adapters بأمان =====================
void _registerHiveAdapters() {
  if (!Hive.isAdapterRegistered(PropertyTypeAdapter().typeId)) {
    Hive.registerAdapter(PropertyTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(RentalModeAdapter().typeId)) {
    Hive.registerAdapter(RentalModeAdapter());
  }
  if (!Hive.isAdapterRegistered(PropertyAdapter().typeId)) {
    Hive.registerAdapter(PropertyAdapter());
  }
  if (!Hive.isAdapterRegistered(TenantAdapter().typeId)) {
    Hive.registerAdapter(TenantAdapter());
  }
  if (!Hive.isAdapterRegistered(ContractAdapter().typeId)) {
    Hive.registerAdapter(ContractAdapter());
  }
  if (!Hive.isAdapterRegistered(InvoiceAdapter().typeId)) {
    Hive.registerAdapter(InvoiceAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenancePriorityAdapter().typeId)) {
    Hive.registerAdapter(MaintenancePriorityAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenanceStatusAdapter().typeId)) {
    Hive.registerAdapter(MaintenanceStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenanceRequestAdapter().typeId)) {
    Hive.registerAdapter(MaintenanceRequestAdapter());
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
