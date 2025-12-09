// lib/ui/login_screen.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/constants/boxes.dart';   // أو المسار الصحيح حسب مكان الملف
import '../data/services/offline_sync_service.dart';
import '../data/services/hive_service.dart';
import '../data/sync/sync_bridge.dart';
import '../data/services/user_scope.dart' as scope;
import 'package:hive_flutter/hive_flutter.dart';
import '../data/services/office_client_guard.dart';






// ✳️ Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✳️ للتذكّر المحلي
import 'package:shared_preferences/shared_preferences.dart';



// ✳️ وقت السعودية (KSA/UTC) — جديد
import '../utils/ksa_time.dart';

// ✳️ مزامنة البيانات بعد تسجيل الدخول (Repos + UserCollections)
import '../data/services/firestore_user_collections.dart';
import '../data/repos/tenants_repo.dart';
import '../data/repos/properties_repo.dart';
import '../data/repos/contracts_repo.dart';
import '../data/repos/maintenance_repo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess; // اختياري: استدعاء عند نجاح الدخول

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _authError; // يظهر هنا تنبيه الخطأ
  bool _rememberEmail = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final sp = await SharedPreferences.getInstance();
    _rememberEmail = sp.getBool('remember_email') ?? true;
    final saved = sp.getString('remembered_email');
    if (saved != null) _emailCtrl.text = saved;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب من قبل الإدارة.';
      case 'user-not-found':
      case 'wrong-password':
        return 'بيانات الدخول غير صحيحة.';
      case 'too-many-requests':
        return 'محاولات كثيرة، الرجاء المحاولة لاحقًا.';
      case 'network-request-failed':
        return 'تحقق من اتصال الإنترنت.';
      default:
        return 'تعذّر تسجيل الدخول. حاول لاحقًا.';
    }
  }

  // ✳️ دالة ترقية ذاتية لأول مرّة (حسب allowlist في السحابة)
  Future<void> _tryPromoteToAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sp = await SharedPreferences.getInstance();
    final flagKey = 'promoted_admin_${user.uid}';
    final already = sp.getBool(flagKey) ?? false;
    if (already) return; // لا نكرر الطلب

    try {
      // حدّث الـ token قبل وبعد
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      // المنطقة نفسها المعرّفة في ملف Functions عندك (us-central1)
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final promote = functions.httpsCallable('promoteToAdmin');

      await promote.call({'email': user.email});
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      await sp.setBool(flagKey, true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'تم ترقية حسابك إلى أدمن ✅',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      // لو مو مسموح (مش ضمن ALLOWED_FIRST_ADMINS) أو أنت أصلاً أدمن — تجاهل بصمت
      if (e.code == 'permission-denied' ||
          e.code == 'unauthenticated' ||
          e.code == 'failed-precondition' ||
          e.code == 'not-found') {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'تعذّر طلب الترقية: ${e.message ?? e.code}',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (_) {
      // تجاهل أي خطأ آخر
    }
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _authError = null;
    });

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // حفظ البريد إذا مفعّل
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('remember_email', _rememberEmail);
      if (_rememberEmail) {
        await sp.setString('remembered_email', email);
      } else {
        await sp.remove('remembered_email');
      }

      // حدّث الـ claims
      await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);

      // ✅ فحص حالة الحظر من Firestore (احتياط إضافي)
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final udoc = await FirebaseFirestore.instance.doc('users/$uid').get();
      final umap = udoc.data() ?? {};
      final isBlocked = (umap['blocked'] == true) || (umap['disabled'] == true);
      if (isBlocked) {
        final msg = (umap['block_message'] as String?) ??
            'عذرًا، تم إيقافك من استخدام التطبيق. إذا كنت تعتقد أن هذا عن طريق الخطأ، يُرجى التواصل مع الإدارة.';

        if (!mounted) return;
        await showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('تم إيقاف الحساب'),
      content: Text(msg, textAlign: TextAlign.right),
actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  ),
);


        await FirebaseAuth.instance.signOut();
        return; // لا نكمل للواجهة
      }



      // ✅ مزامنة وقت الخادم (KSA/UTC) مباشرة بعد نجاح الدخول
      try {
        await KsaTime.ensureSynced(force: true); // يجلب serverTimestamp ويحسب الانحراف
      } catch (_) {
        // لا توقف التدفق لو كان المستخدم أوفلاين؛ سيتم الاعتماد مؤقتًا على ساعة الجهاز
      }
      KsaTime.startAutoSync(); // مزامنة دورية كل عدة ساعات

      // ✅ فحص حالة الاشتراك (انتهاء / تعطيل) قبل الدخول لأي شاشة (هوم أو مكتب)
      final bool subActiveFlag = (umap['subscription_active'] ?? true) == true;

      // نحسب "تاريخ نهاية الاشتراك" كتاريخ فقط بتوقيت السعودية
      DateTime? inclusiveEndKsaDate;

      // 1️⃣ نحاول end_date_ksa إن وُجد (yyyy-MM-dd أو yyyy/MM/dd)
      final endKsaText = (umap['end_date_ksa'] as String?)?.trim();
      if (endKsaText != null && endKsaText.isNotEmpty) {
        final normalized = endKsaText.replaceAll('/', '-');
        final parts = normalized.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            // هذا هو "اليوم الأخير للاشتراك" في السعودية
            inclusiveEndKsaDate = DateTime(y, m, d);
          }
        }
      }

      // 2️⃣ لو ما عندنا end_date_ksa نرجع نحسب من subscription_end (حسابات قديمة)
      if (inclusiveEndKsaDate == null) {
        final rawEnd = umap['subscription_end'];
        DateTime? endUtc;
        if (rawEnd is Timestamp) {
          endUtc = rawEnd.toDate().toUtc();
        } else if (rawEnd is DateTime) {
          endUtc = rawEnd.toUtc();
        } else if (rawEnd is String) {
          final parsed = DateTime.tryParse(rawEnd);
          if (parsed != null) endUtc = parsed.toUtc();
        }

        if (endUtc != null) {
          // نحولها إلى السعودية ونأخذ التاريخ فقط (اليوم الأخير)
          final endKsa = endUtc.add(const Duration(hours: 3)); // UTC+3
          inclusiveEndKsaDate = DateTime(endKsa.year, endKsa.month, endKsa.day);
        }
      }

      // 3️⃣ نحدد إذا انتهى الاشتراك بالفعل
      bool isExpired = false;
      if (inclusiveEndKsaDate != null) {
        final todayKsa = KsaTime.dateOnly(KsaTime.nowKsa());
        // انتهى فقط إذا كان اليوم في السعودية بعد اليوم الأخير
        // مثال: end = 29 → التطبيق شغال طول يوم 29، وينتهي من بداية يوم 30
        isExpired = todayKsa.isAfter(inclusiveEndKsaDate);
      }

      if (!subActiveFlag || isExpired) {
        if (!mounted) return;
        final msg = !subActiveFlag
            ? 'تم تعطيل اشتراكك. يُرجى التواصل مع الإدارة.'
            : 'انتهى اشتراكك. لا يمكنك تسجيل الدخول إلا بعد تجديد الاشتراك.';

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('انتهاء الاشتراك'),
              content: Text(msg, textAlign: TextAlign.right),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسنًا'),
                ),
              ],
            ),
          ),
        );

        await FirebaseAuth.instance.signOut();
        return; // لا نكمل للواجهة ولا نفتح /office ولا /home
      }


      // ✳️ حاول ترقية نفسك لأدمن (مرة واحدة) — اختياري لأول إعداد
      await _tryPromoteToAdmin();



// ← هنا بعد registerFcmOnce() وقبل _globalSync.start()
// نضمن فتح صناديق UID الحالي وإعادة تشغيل الجسور قبل الذهاب للهوم

final uidNow = FirebaseAuth.instance.currentUser!.uid;


// 👇 مهم جدًا: ثبّت UID الحالي في user_scope حتى لا يرث الجهاز UID قديم
scope.setFixedUid(uidNow);

// 1) أوقف أي جسور قديمة (ضيف/مستخدم سابق)
try { await SyncManager.instance.stopAll(); } catch (_) {}

// 2) أعد تهيئة خدمة الأوفلاين على الـ uid الحالي
final uc = UserCollections(uidNow);
final tenantsRepo = TenantsRepo(uc);
try { OfflineSyncService.instance.dispose(); } catch (_) {}

await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

// 3) افتح صناديق Hive الخاصة بالمستخدم الحالي
await HiveService.ensureReportsBoxesOpen();

// 4) شغّل جسور التزامن Firestore <-> Hive على uid الحالي
await SyncManager.instance.startAll();

// (يبقى كما هو بعد الكتلة)
await _globalSync.start(); // يعمل مرة واحدة فقط حتى مع تكرار النداء


// احصل على الدور من الـ claims أولاً، ولو فاضي خذه من وثيقة Firestore
      // احصل على الدور من الـ claims أولاً، ولو فاضي خذه من وثيقة Firestore
      final user = FirebaseAuth.instance.currentUser!;
      String role = 'client';
      try {
        final t = await user.getIdTokenResult(true);
        final r = t.claims?['role']?.toString();
        if (r != null && r.isNotEmpty) role = r.toLowerCase();
      } catch (_) {}

      if (role == 'client' || role == 'reseller' || role == 'admin') {
        // لو ما قدرنا نستخرج من الـ claims نقرأ من users/{uid}
        try {
          final d = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final rr = d.data()?['role']?.toString();
          if (rr != null && rr.isNotEmpty) role = rr.toLowerCase();
        } catch (_) {}
      }

      // 👈 هنا نحدد هل هذا المستخدم "عميل مكتب" فعليًا من السيرفر
      final isOfficeClient = await _isOfficeManagedClient();

      // 💾 تخزين بيانات هذا المستخدم للسماح بتسجيل الدخول أوفلاين مستقبلاً
      try {
        final sp2 = await SharedPreferences.getInstance();

        // بيانات هذا الإيميل نفسه (للدخول الأوفلاين لهذا البريد)
        await sp2.setString('offline_uid_$email', user.uid);
        await sp2.setString('offline_role_$email', role);
        await sp2.setString('offline_pass_$email', pass);

        // 👈 تمييز إن كان هذا الحساب تابعًا لمكتب (عميل مكتب)
        await sp2.setBool('offline_is_office_client_$email', isOfficeClient);

        // 👇 حفظ آخر مستخدم نشط لفتح التطبيق تلقائيًا لاحقًا
        await sp2.setString('last_login_email', email);
        await sp2.setString('last_login_uid', user.uid);
        await sp2.setString('last_login_role', role);
        await sp2.setBool('last_login_offline', false);
      } catch (_) {}

      if (!mounted) return;

      // 👈 افتح/استخدم sessionBox
      const boxName = 'sessionBox';
      final session = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);

// نخزن حالة الدخول ونوع الجلسة
await session.put('loggedIn', true);
await session.put('isOfficeClient', isOfficeClient);

// 🔴 هذا الحساب يحتاج اتصال إنترنت لو كان "عميل مكتب"
await session.put('clientNeedsInternet', isOfficeClient == true);

// حدّث الكاش في الحارس حتى تشتغل القيود فورًا
await OfficeClientGuard.refreshFromLocal();


      widget.onLoginSuccess?.call();

      if (role == 'office') {
        Navigator.of(context).pushReplacementNamed('/office');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }


} on FirebaseAuthException catch (e) {
      // في حالة انقطاع الإنترنت نحاول أولاً تسجيل الدخول أوفلاين لنفس البريد
      if (e.code == 'network-request-failed') {
        final ok = await _tryOfflineLogin(email, pass);
        if (ok) return;

        // لو _tryOfflineLogin كتب رسالة خطأ خاصة (مثل حساب مكتب)، لا نستبدلها
        if (_authError != null) {
          return;
        }
      }

      // 🛑 حالة الحساب الموقوف من Firebase Auth
      if (e.code == 'user-disabled') {
        

        if (!mounted) return;
       await showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('تم إيقاف الحساب'),
      content: const Text(
        'عذرًا، تم إيقافك من استخدام التطبيق. إذا كنت تعتقد أن هذا عن طريق الخطأ، يُرجى التواصل مع الإدارة.',
        textAlign: TextAlign.right,
      ),
actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  ),
);

        setState(() => _authError = null); // لا نُظهر بانر إضافي
      } else {
        setState(() => _authError = _friendlyError(e));
      }
    } catch (_) {
      setState(() => _authError = 'حدث خطأ غير متوقع. حاول لاحقًا.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

Future<bool> _isOfficeManagedClient() async {
  try {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;

    // 1) من الـ claims
    try {
      final id = await u.getIdTokenResult();
      final c = id.claims ?? {};
      final viaClaims =
          (c['officeId'] != null) ||
          (c['office_id'] != null) ||
          (c['is_office_client'] == true) ||
          (c['createdByRole'] == 'office');
      if (viaClaims) return true;
    } catch (_) {}

    // 2) من وثيقة users/{uid}
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final m = doc.data() ?? {};
      final viaDoc =
          (m['officeId'] != null) ||
          (m['office_id'] != null) ||
          (m['origin'] == 'officeClient') ||
          (m['createdByRole'] == 'office') ||
          (m['is_office_client'] == true);
      if (viaDoc) return true;
    } catch (_) {}

    // 3) هل uid موجود تحت أي offices/*/clients/*
    try {
      final cg = await FirebaseFirestore.instance
          .collectionGroup('clients')
          .where(FieldPath.documentId, isEqualTo: u.uid)
          .limit(1)
          .get();
      if (cg.docs.isNotEmpty) return true;
    } catch (_) {}

    return false;
  } catch (_) {
    return false;
  }
}


  /// محاولة تسجيل الدخول أوفلاين باستخدام بيانات تم حفظها مسبقًا لهذا البريد
  Future<bool> _tryOfflineLogin(String email, String pass) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final savedUid  = sp.getString('offline_uid_$email');
    final savedRole = sp.getString('offline_role_$email');
    final savedPass = sp.getString('offline_pass_$email');

    // لم نَجِد بيانات محفوظة لهذا البريد
    if (savedUid == null || savedRole == null || savedPass == null) {
      if (mounted) {
        setState(() {
          _authError =
              'لا يوجد اتصال بالإنترنت، ويجب أن تسجّل الدخول مرة واحدة بهذا البريد وأنت متصل قبل استخدامه أوفلاين.';
        });
      }
      return false;
    }

    // 👈 معرفة إن كان هذا الحساب "عميل مكتب" من التخزين السابق
    final isOfficeClientOffline =
        sp.getBool('offline_is_office_client_$email') ?? false;

    final roleLower = savedRole.toLowerCase();
    final isOfficeRole = roleLower == 'office';

    // 🚫 منع الدخول الأوفلاين لحسابات المكتب + عملاء المكتب
    if (isOfficeRole || isOfficeClientOffline) {
      if (mounted) {
        setState(() {
          _authError =
              'حسابات المكتب وعملاء المكتب تتطلّب اتصالًا بالإنترنت لتسجيل الدخول.';
        });
      }
      return false;
    }

    // الباسورد لا يطابق الباسورد المحفوظ
    if (savedPass != pass) {
      if (mounted) {
        setState(() {
          _authError = 'بيانات الدخول غير صحيحة (أوفلاين).';
        });
      }
      return false;
    }

    // ثبّت UID للأوفلاين حتى ولو لم يكن هناك مستخدم Firebase حالي
    scope.setFixedUid(savedUid);

    // 🧠 مهم: أعد تهيئة المزامنة والجسور على هذا الـ UID
    try {
      await SyncManager.instance.stopAll();
    } catch (_) {}

    final uc = UserCollections(savedUid);
    final tenantsRepo = TenantsRepo(uc);

    try {
      OfflineSyncService.instance.dispose();
    } catch (_) {}

    await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

    // افتح صناديق هذا المستخدم محليًا (Hive)
    await HiveService.ensureReportsBoxesOpen();

    // 👇 حفظ آخر مستخدم نشط لفتح التطبيق تلقائيًا لاحقًا
    await sp.setString('last_login_email', email);
    await sp.setString('last_login_uid', savedUid);
    await sp.setString('last_login_role', savedRole);
    await sp.setBool('last_login_offline', true);

    if (mounted) {
      setState(() {
        _authError = null;
      });
    }

    // ملاحظة: هنا لن يكون الدور office لأننا منعناه فوق
    if (!mounted) return true;

    Navigator.of(context).pushReplacementNamed('/home');

    return true;
  } catch (_) {
    if (mounted) {
      setState(() {
        _authError = 'لا يمكن تسجيل الدخول أوفلاين حاليًا.';
      });
    }
    return false;
  }
}



  Future<void> _sendResetEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _authError = 'اكتب بريدك أولًا ثم أعد المحاولة.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم إرسال رابط إعادة التعيين إلى بريدك.',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _authError = _friendlyError(e));
    } catch (_) {
      setState(() => _authError = 'تعذّر إرسال رابط إعادة التعيين.');
    }
  }

  // نافذة الدعم الفني
  void _showSupportDialog() {
    const primary = Color(0xFF1E40AF);

    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          titlePadding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 0),
          contentPadding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 8.h),
          actionsPadding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 10.h),
          title: Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: primary),
              SizedBox(width: 8.w),
              Text(
                'الدعم الفني',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
             Text(
  'تواجه صعوبة في تسجيل الدخول؟\nراسل فريق الدعم الفني:',
  style: GoogleFonts.tajawal(
    fontSize: 14.sp,
    height: 1.5,
    color: Colors.black.withOpacity(0.80),
  ),
),

              SizedBox(height: 8.h),
              SelectableText(
                'support@darvoo.com',
                style: GoogleFonts.tajawal(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                  color: primary,
                ),
              ),
              SizedBox(height: 14.h),
              SizedBox(
                width: double.infinity,
child: IgnorePointer( // يمنع الضغط مع الحفاظ على الشكل والرِبل
  ignoring: true,
  child: OutlinedButton.icon(
    onPressed: _sendResetEmail, // اتركها كما هي؛ IgnorePointer سيمنع أي نقر
    icon: const Icon(Icons.refresh_rounded),
    label: Text(
      ' تواصل معنا لإرسال رابط إعادة تعيين كلمة المرور',
      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
    ),
  ),
),

              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'إغلاق',
                style: GoogleFonts.tajawal(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ألوان الهوية
    const primary = Color(0xFF1E40AF); // لون الأزرار/العناصر الأساسية
    const bgNeutral = Color(0xFFECEFF1); // رصاصي فاتح محايد

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
Color(0xFFDCE6F3),
Color(0xFFC9D8F0),





      ],
    ),
  ),
),

            CustomPaint(
              size: Size.infinite,
              painter: RealEstateScatterPainter(
                seed: 2025,
                layer: 0,
                tint: primary,
                baseOpacityNear: 0.045,
                extraOpacityNear: 0.040,
              ),
            ),
            CustomPaint(
              size: Size.infinite,
              painter: RealEstateScatterPainter(
                seed: 2102,
                layer: 1,
                tint: primary,
                baseOpacityNear: 0.070,
                extraOpacityNear: 0.050,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      20.w,
                      20.h,
                      20.w,
                      20.h + bottomInset,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28.r),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              width: (600.w).clamp(0, 600).toDouble(),
                              padding: EdgeInsets.symmetric(
                                horizontal: 22.w,
                                vertical: 24.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.86),
                                borderRadius: BorderRadius.circular(28.r),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.95),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 18.r,
                                    offset: Offset(0, 10.h),
                                  )
                                ],
                              ),
                              child: _buildForm(context, primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Color primary) {
    final titleStyle = GoogleFonts.tajawal(
      fontSize: 26.sp,
      fontWeight: FontWeight.w700,
      color: Colors.black.withOpacity(0.88),
      height: 1.25,
    );

    final subtitleStyle = GoogleFonts.tajawal(
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      color: Colors.black.withOpacity(0.60),
    );

    final labelStyle = GoogleFonts.tajawal(
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
      color: Colors.black.withOpacity(0.78),
    );

    final inputTextStyle = GoogleFonts.tajawal(
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      color: Colors.black.withOpacity(0.92),
    );

    final hintStyle = GoogleFonts.tajawal(
      fontSize: 14.sp,
      color: Colors.black.withOpacity(0.35),
      fontWeight: FontWeight.w500,
    );

    final errorStyle = GoogleFonts.tajawal(
      fontSize: 13.sp,
      color: Colors.red.shade700,
      fontWeight: FontWeight.w700,
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16.r),
      borderSide: BorderSide(color: Colors.black.withOpacity(0.12), width: 1),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16.r),
      borderSide: BorderSide(color: primary, width: 1.4),
    );

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100.w,
            height: 100.w,
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: 10.h),

          Text('تسجيل الدخول', style: titleStyle),
          SizedBox(height: 6.h),
          Text(
            'أدخل بيانات حسابك للوصول إلى لوحة إدارة العقارات.',
            style: subtitleStyle,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 22.h),

          if (_authError != null) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.red.withOpacity(0.35), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_rounded, color: Colors.red.shade700, size: 20.r),
                  SizedBox(width: 8.w),
                  Expanded(child: Text(_authError!, style: errorStyle)),
                ],
              ),
            ),
            SizedBox(height: 14.h),
          ],

          Align(
            alignment: Alignment.centerRight,
            child: Text('البريد الإلكتروني', style: labelStyle),
          ),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            style: inputTextStyle,
            decoration: InputDecoration(
              hintText: 'example@email.com',
              hintStyle: hintStyle,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: border,
              focusedBorder: focusedBorder,
              errorStyle: errorStyle,
              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'يرجى إدخال البريد الإلكتروني';
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(value)) return 'صيغة بريد إلكتروني غير صحيحة';
              return null;
            },
          ),
          SizedBox(height: 14.h),

          Align(
            alignment: Alignment.centerRight,
            child: Text('كلمة المرور', style: labelStyle),
          ),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            style: inputTextStyle,
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: hintStyle,
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              ),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: border,
              focusedBorder: focusedBorder,
              errorStyle: errorStyle,
              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            ),
            onFieldSubmitted: (_) => _onLogin(),
            validator: (v) {
              final value = v ?? '';
              if (value.isEmpty) return 'يرجى إدخال كلمة المرور';
              if (value.length < 6) return 'الحد الأدنى 6 أحرف';
              return null;
            },
          ),
          SizedBox(height: 10.h),

          Row(
            children: [
              Checkbox(
                value: _rememberEmail,
                onChanged: (v) => setState(() => _rememberEmail = v ?? true),
              ),
              Text('تذكّر البريد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: _showSupportDialog,
                icon: const Icon(Icons.support_agent_rounded),
                label: Text(
                  'نسيت كلمة المرور؟',
                  style: GoogleFonts.tajawal(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withOpacity(0.70),
                    decoration: TextDecoration.underline,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),

          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton(
              onPressed: _loading ? null : _onLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                disabledBackgroundColor: const Color(0xFF1E40AF).withOpacity(0.5),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
              ),
              child: _loading
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'تسجيل الدخول',
                      style: GoogleFonts.tajawal(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 14.h),

          Text(
            'تسجيل الدخول مطلوب لإدارة عقاراتك وعقودك.',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black.withOpacity(0.60),
            ),
          ),
        ],
      ),
    );
  }
}

/// رسّام نقش عشوائي...
class RealEstateScatterPainter extends CustomPainter {
  RealEstateScatterPainter({
    required this.seed,
    required this.layer,
    required this.tint,
    this.baseOpacityNear = 0.10,
    this.extraOpacityNear = 0.08,
  });

  final int seed;
  final int layer;
  final Color tint;
  final double baseOpacityNear;
  final double extraOpacityNear;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final icons = <IconData>[
      Icons.apartment_rounded,
      Icons.home_work_rounded,
      Icons.location_city_rounded,
      Icons.domain_rounded,
      Icons.business_rounded,
      Icons.location_on_rounded,
    ];

    final shortest = math.min(size.width, size.height);
    final minDist = (layer == 0) ? shortest * 0.075 : shortest * 0.055;
    final maxPoints = (layer == 0) ? 80 : 140;

    final points = _poissonSample(size, minDist, maxPoints, rnd);

    for (final p in points) {
      final icon = icons[rnd.nextInt(icons.length)];
      final baseSize = (layer == 0) ? minDist * 0.95 : minDist * 0.78;
      final fontSize = baseSize * (0.85 + rnd.nextDouble() * 0.50);
      final color = tint.withOpacity(
        baseOpacityNear + rnd.nextDouble() * extraOpacityNear,
      );
      final angle = (rnd.nextDouble() - 0.5) * (math.pi / 3);

      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: fontSize,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  List<Offset> _poissonSample(
    Size size,
    double minDist,
    int maxPoints,
    math.Random rnd, {
    int maxAttemptsPerPoint = 25,
  }) {
    final points = <Offset>[];
    int attempts = 0;

    while (points.length < maxPoints && attempts < maxPoints * maxAttemptsPerPoint) {
      attempts++;
      final candidate = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );

      bool ok = true;
      for (final p in points) {
        final dx = p.dx - candidate.dx;
        final dy = p.dy - candidate.dy;
        if (dx * dx + dy * dy < minDist * minDist) {
          ok = false;
          break;
        }
      }
      if (ok) points.add(candidate);
    }
    return points;
  }

  @override
  bool shouldRepaint(covariant RealEstateScatterPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.layer != layer ||
        oldDelegate.tint != tint ||
        oldDelegate.baseOpacityNear != baseOpacityNear ||
        oldDelegate.extraOpacityNear != extraOpacityNear;
  }
}

/* ============================================================
   منسّق مزامنة بسيط: يشغّل مستمعات Firestore بعد تسجيل الدخول
   — يوضع في نفس الملف لتسهيل الدمج. يمكنك لاحقًا نقله إلى:
   lib/data/sync/sync_coordinator.dart
   ============================================================ */

final _globalSync = _GlobalSync();

class _GlobalSync {
  TenantsRepo? _tenantsRepo;
  PropertiesRepo? _propertiesRepo;
  ContractsRepo? _contractsRepo;
  MaintenanceRepo? _maintenanceRepo;

  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final uc = UserCollections(uid);

    _tenantsRepo     = TenantsRepo(uc);
    _propertiesRepo  = PropertiesRepo(uc);
    _contractsRepo   = ContractsRepo(uc);
    _maintenanceRepo = MaintenanceRepo(uc);

    // ملاحظة: ضع حفظ Hive الحقيقي هنا إن رغبت (بدل TODO)
    _tenantsRepo!.startTenantsListener(
      onUpsert: (t) async {
        // TODO: مثال كتابة إلى Hive:
        // final box = Hive.box<Tenant>(boxName('tenantsBox'));
        // await box.put(t.id, t);
      },
      onDelete: (id) async {
        // TODO: مثال حذف من Hive:
        // final box = Hive.box<Tenant>(boxName('tenantsBox'));
        // await box.delete(id);
      },
    );

    _propertiesRepo!.startPropertiesListener(
      onUpsert: (p) async {
        // TODO: اكتب إلى Hive إن رغبت
      },
      onDelete: (id) async {
        // TODO: احذف من Hive إن رغبت
      },
    );

    _contractsRepo!.startContractsListener(
      onUpsert: (c) async {
        // TODO: اكتب إلى Hive (contractsBox) إن رغبت
      },
      onDelete: (id) async {
        // TODO: احذف من Hive إن رغبت
      },
    );

    _maintenanceRepo!.startMaintenanceListener(
      onUpsert: (m) async {
        // TODO: اكتب إلى Hive (maintenanceBox) إن رغبت
      },
      onDelete: (id) async {
        // TODO: احذف من Hive إن رغبت
      },
    );

    _running = true;
  }

  void stop() {
    _tenantsRepo?.stopTenantsListener();
    _propertiesRepo?.stopPropertiesListener();
    _contractsRepo?.stopContractsListener();
    _maintenanceRepo?.stopMaintenanceListener();

    _tenantsRepo = null;
    _propertiesRepo = null;
    _contractsRepo = null;
    _maintenanceRepo = null;
    _running = false;
  }
}
