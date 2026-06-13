// lib/ui/home_screen.dart
import 'package:ejarz_pro/utils/ksa_time.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart'; // تأكد من الدالة boxName
import '../utils/contract_utils.dart'; // لحساب إجمالي المستحقات من العقود
import 'notifications_screen.dart'
    show NotificationsScreen, NotificationsCounter;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/subscription_expiry.dart';

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
import 'widgets/app_side_drawer.dart';

// جلسة المكتب (للعودة عند الانتحال)
import '../screens/office/office.dart' show OfficeSession;
import '../widgets/custom_confirm_dialog.dart';

const String _homeAssetPath = 'assets/images/home';
const String _aiBotAsset = 'assets/images/ejarz_pro_ai_bot_icon.png';

const Color _homeTop = Color(0xFF061A2D);
const Color _homeMiddle = Color(0xFF08243A);
const Color _homeBottom = Color(0xFF041522);
const Color _homeCard = Color(0xFF102D44);
const Color _homeTurquoise = Color(0xFF2FE0C0);
const Color _homeWhite = Color(0xFFF5F7FA);
const Color _homeMuted = Color(0xFF8FA6B8);
const Color _homeRed = Color(0xFFFF5D72);
const Color _homeYellow = Color(0xFFFFD95C);
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _officeClientSubByUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _officeClientSubByEmail;
  String? _officeClientOfficeId;
  bool _forcedLogoutHandled = false;

  // لفتح الصناديق قبل استخدامها
  bool _hiveReady = false;
  // ignore: unused_field
  Future<void>? _openHiveFuture;

  // إظهار زر رجوع للمكتب عند الانتحال
  bool _hasOfficeReturn = false;
  bool _isOfficeImpersonationFlag = false;

  // ===== حارس الإنترنت لعملاء المكتب / جلسة المكتب =====
  bool _clientNeedsInternet = false; // هل هذه الجلسة يجب أن تعمل فقط مع إنترنت؟
  bool _hasConnection = true; // حالة الاتصال الحالية
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _hiveWatchdog;
  DateTime? _hiveOpenStartedAt;
  bool _reconnectCheckInFlight = false;
  bool _officeClientBlockedDialogShown = false;

  void _traceHome(String message) {
    debugPrint('[HomeTrace] $message');
  }

  void _traceHomeBoxes(String reason) {
    try {
      final propertyBoxName = boxName('propertiesBox');
      final tenantBoxName = boxName('tenantsBox');
      final invoiceBoxName = boxName(kInvoicesBox);
      final contractBoxName = boxName(kContractsBox);
      final propertyBox =
          Hive.isBoxOpen(propertyBoxName) ? Hive.box(propertyBoxName) : null;
      final tenantBox =
          Hive.isBoxOpen(tenantBoxName) ? Hive.box(tenantBoxName) : null;
      final invoiceBox =
          Hive.isBoxOpen(invoiceBoxName) ? Hive.box(invoiceBoxName) : null;
      final contractBox =
          Hive.isBoxOpen(contractBoxName) ? Hive.box(contractBoxName) : null;

      final propertyPreview = propertyBox == null
          ? const <String>[]
          : propertyBox.values
              .take(3)
              .map((e) => (e as dynamic).name?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
      final tenantPreview = tenantBox == null
          ? const <String>[]
          : tenantBox.values
              .take(3)
              .map((e) => (e as dynamic).fullName?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false);

      _traceHome(
        'boxes reason=$reason authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} '
        'propertiesBox=$propertyBoxName count=${propertyBox?.length ?? -1} preview=$propertyPreview '
        'tenantsBox=$tenantBoxName count=${tenantBox?.length ?? -1} preview=$tenantPreview '
        'contractsBox=$contractBoxName count=${contractBox?.length ?? -1} '
        'invoicesBox=$invoiceBoxName count=${invoiceBox?.length ?? -1}',
      );
    } catch (e) {
      _traceHome('boxes reason=$reason failed err=$e');
    }
  }

  bool get _isOfficeImpersonationSession =>
      _hasOfficeReturn || _isOfficeImpersonationFlag;

  bool _isBlockedClientMap(Map<String, dynamic> m) {
    return OfficeClientGuard.isBlockedClientData(m);
  }

  Future<OfficeClientMatch?> _fetchOfficeClientServerMatch({
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _traceHome('office-client-match skip reason=$reason no-auth-user');
      return null;
    }

    try {
      final match = await OfficeClientGuard.findOfficeClientMatchForUser(
        user,
        source: Source.server,
        timeout: const Duration(seconds: 4),
      );
      _traceHome(
        'office-client-match reason=$reason found=${match != null} by=${match?.matchedBy ?? ''} officeId=${match?.officeId ?? ''} blocked=${match?.isBlocked == true}',
      );
      return match;
    } catch (e) {
      _traceHome('office-client-match error reason=$reason err=$e');
      return null;
    }
  }

  Future<void> _clearCachedLoginState() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('last_login_email');
      await sp.remove('last_login_uid');
      await sp.remove('last_login_role');
      await sp.remove('last_login_offline');
    } catch (_) {}
  }

  Future<void> _showOfficeClientBlockedDialog({
    required String message,
  }) async {
    if (!mounted || _officeClientBlockedDialogShown) return;
    _officeClientBlockedDialogShown = true;
    await CustomConfirmDialog.show(
      context: context,
      title: 'تم إيقاف الحساب',
      message: message,
      forceBlockedDialog: true,
      confirmLabel: 'خروج',
    );
    _officeClientBlockedDialogShown = false;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) return false;

      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _syncOfficeClientStateFromServer({
    required String reason,
  }) async {
    if (_forcedLogoutHandled) return false;
    if (_isOfficeImpersonationSession) {
      _traceHome('office-client-sync skip impersonation reason=$reason');
      return false;
    }

    final match = await _fetchOfficeClientServerMatch(reason: reason);
    if (match == null) {
      final user = FirebaseAuth.instance.currentUser;
      _traceHome(
        'office-client-sync no-record reason=$reason uid=${user?.uid ?? ''}',
      );
      return false;
    }

    if (match.isBlocked) {
      await _forceOfficeClientBlockedFlow(
        reason: 'office-client-sync-$reason',
        message: OfficeClientGuard.blockedOfficeClientMessage,
      );
      return true;
    }

    try {
      if (Hive.isBoxOpen('sessionBox')) {
        final session = Hive.box('sessionBox');
        await session.put('isOfficeClient', true);
        await session.put('clientNeedsInternet', true);
        await session.put('officeImpersonation', false);
      }
      await OfficeClientGuard.refreshFromLocal();
      if (mounted) {
        setState(() {
          _clientNeedsInternet = true;
        });
      }
      _traceHome('office-client-sync promoted-to-office-client reason=$reason');
    } catch (e) {
      _traceHome(
          'office-client-sync session-update error reason=$reason err=$e');
    }

    return true;
  }

  Future<void> _forceLogoutAndGoLogin({
    required String msg,
    bool markOfficeBlocked = false,
  }) async {
    if (_forcedLogoutHandled) return;
    _forcedLogoutHandled = true;
    final blockedEmail = FirebaseAuth.instance.currentUser?.email;
    final blockedUid = FirebaseAuth.instance.currentUser?.uid;
    if (markOfficeBlocked) {
      await OfficeClientGuard.markOfficeBlocked(
        true,
        email: blockedEmail,
        uid: blockedUid,
      );
    }

    await _userSub?.cancel();
    _userSub = null;
    await _officeClientSubByUid?.cancel();
    _officeClientSubByUid = null;
    await _officeClientSubByEmail?.cancel();
    _officeClientSubByEmail = null;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    // Stop Hive-dependent UI before signing out.
    setState(() {
      _hiveReady = false;
    });

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

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
      await session.put('isOfficeClient', false);
      await session.put('officeImpersonation', false);
    }

    clearFixedUid();
    await OfficeClientGuard.refreshFromLocal();

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 150));
    // ignore: use_build_context_synchronously
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _forceOfficeClientBlockedFlow({
    required String reason,
    required String message,
  }) async {
    if (_forcedLogoutHandled) {
      _traceHome('office-client-blocked-flow skip duplicate reason=$reason');
      return;
    }
    _forcedLogoutHandled = true;
    _traceHome('office-client-blocked-flow start reason=$reason');

    final blockedEmail = FirebaseAuth.instance.currentUser?.email;
    final blockedUid = FirebaseAuth.instance.currentUser?.uid;
    await OfficeClientGuard.markOfficeBlocked(
      true,
      email: blockedEmail,
      uid: blockedUid,
    );

    await _userSub?.cancel();
    _userSub = null;
    await _officeClientSubByUid?.cancel();
    _officeClientSubByUid = null;
    await _officeClientSubByEmail?.cancel();
    _officeClientSubByEmail = null;

    if (mounted) {
      setState(() {
        _hiveReady = false;
      });
      await _showOfficeClientBlockedDialog(message: message);
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    await _clearCachedLoginState();
    await OfficeClientGuard.clearSessionState();
    clearFixedUid();
    await OfficeClientGuard.refreshFromLocal();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _enforceBlockedLocallyIfNeeded() async {
    if (_forcedLogoutHandled || !mounted) return;
    if (_isOfficeImpersonationSession) {
      _traceHome('office-block-local-check skipped impersonation=true');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    final blocked = await OfficeClientGuard.isOfficeBlockedLocally(
      email: user?.email,
      uid: user?.uid,
    );
    _traceHome('office-block-local-check blocked=$blocked');
    if (!mounted || !blocked) return;

    final online = await _hasInternetConnection();
    _traceHome('office-block-local-check online=$online');
    if (online && user != null) {
      final match = await _fetchOfficeClientServerMatch(
        reason: 'local-revalidate',
      );
      final stillBlocked = match?.isBlocked == true;
      _traceHome(
        'office-block-local-revalidate matched=${match != null} stillBlocked=$stillBlocked',
      );
      if (match != null && !stillBlocked) {
        await OfficeClientGuard.markOfficeBlocked(
          false,
          email: user.email,
          uid: user.uid,
        );
        _traceHome(
          'office-block-local-revalidate cleared-local-flag reason=server-confirmed-unblocked',
        );
        return;
      }
    }

    await _forceOfficeClientBlockedFlow(
      reason: 'local-blocked',
      message: OfficeClientGuard.blockedOfficeClientMessage,
    );
  }

  Future<void> _recheckBlockedOnReconnect() async {
    if (_forcedLogoutHandled || _reconnectCheckInFlight) return;
    _reconnectCheckInFlight = true;
    try {
      await _enforceBlockedLocallyIfNeeded();
      if (_forcedLogoutHandled) return;
      await _syncOfficeClientStateFromServer(reason: 'reconnect');
      if (_forcedLogoutHandled) return;
      await _ensureOfficeClientRecordWatchStarted();
    } finally {
      _reconnectCheckInFlight = false;
    }
  }

  Future<void> _ensureOfficeClientRecordWatchStarted({
    String? officeIdHint,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String officeId = (officeIdHint ?? '').trim();
    if (officeId.isEmpty) {
      try {
        final token =
            await user.getIdTokenResult().timeout(const Duration(seconds: 2));
        final claims = token.claims ?? const <String, dynamic>{};
        officeId =
            (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
      } catch (_) {}
    }

    if (officeId.isEmpty) {
      try {
        final match = await _fetchOfficeClientServerMatch(
          reason: 'watch-start',
        );
        if (match?.isBlocked == true) {
          await _forceOfficeClientBlockedFlow(
            reason: 'watch-start-blocked',
            message: OfficeClientGuard.blockedOfficeClientMessage,
          );
          return;
        }
        officeId = match?.officeId ?? '';
      } on TimeoutException {
        // If we can't resolve now, we keep running on users/{uid} watcher.
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          _traceHome(
            'office-client-watch-start skip blocked-enforcement reason=permission-denied',
          );
          return;
        }
      } catch (_) {}
    }

    if (officeId.isEmpty) return;
    if (_officeClientOfficeId == officeId &&
        (_officeClientSubByUid != null || _officeClientSubByEmail != null)) {
      return;
    }

    _officeClientOfficeId = officeId;
    await _officeClientSubByUid?.cancel();
    _officeClientSubByUid = null;
    await _officeClientSubByEmail?.cancel();
    _officeClientSubByEmail = null;

    final email = (user.email ?? '').trim().toLowerCase();
    final ref = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeId)
        .collection('clients');

    void handleOfficeClientDoc(DocumentSnapshot<Map<String, dynamic>> docSnap) {
      if (!docSnap.exists) return;
      // Only act on server snapshots so offline cache doesn't kick users out.
      if (docSnap.metadata.isFromCache) return;
      final m = docSnap.data() ?? const <String, dynamic>{};
      if (_isBlockedClientMap(m)) {
        _traceHome(
          'office-client-record blocked officeId=$officeId docId=${docSnap.id}',
        );
        unawaited(_forceOfficeClientBlockedFlow(
          reason: 'office-client-record-$officeId-${docSnap.id}',
          message: OfficeClientGuard.blockedOfficeClientMessage,
        ));
      }
    }

    _officeClientSubByUid =
        ref.doc(user.uid).snapshots(includeMetadataChanges: true).listen(
      handleOfficeClientDoc,
      onError: (Object error, StackTrace st) async {
        final code = error is FirebaseException ? error.code : '';
        _traceHome('office-client-record(uid) onError code=$code err=$error');
        if (code == 'permission-denied') {
          _traceHome(
            'office-client-record(uid) skip blocked-enforcement reason=permission-denied',
          );
        }
      },
    );

    if (email.isNotEmpty) {
      _officeClientSubByEmail =
          ref.doc(email).snapshots(includeMetadataChanges: true).listen(
        handleOfficeClientDoc,
        onError: (Object error, StackTrace st) async {
          final code = error is FirebaseException ? error.code : '';
          _traceHome(
              'office-client-record(email) onError code=$code err=$error');
          if (code == 'permission-denied') {
            _traceHome(
              'office-client-record(email) skip blocked-enforcement reason=permission-denied',
            );
          }
        },
      );
    }
  }

  void _startHiveWatchdog() {
    _hiveOpenStartedAt = DateTime.now();
    _hiveWatchdog?.cancel();
    _hiveWatchdog = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _hiveReady) {
        timer.cancel();
        return;
      }
      final started = _hiveOpenStartedAt;
      final elapsedMs = started == null
          ? -1
          : DateTime.now().difference(started).inMilliseconds;
      _traceHome(
        'hive-not-ready elapsed=${elapsedMs}ms authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${effectiveUid()}',
      );
    });
  }

  void _stopHiveWatchdog() {
    _hiveWatchdog?.cancel();
    _hiveWatchdog = null;
  }

  @override
  void initState() {
    super.initState();
    _traceHome(
      'init authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${effectiveUid()}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
      unawaited(_enforceBlockedLocallyIfNeeded());
      unawaited(_syncOfficeClientStateFromServer(reason: 'init-post-frame'));
    });

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
        final isOfficeClient = await OfficeClientGuard.isOfficeClient();
        _traceHome(
          'user-sub snapshot authUid=${user.uid} isOfficeClient=$isOfficeClient blocked=${m['blocked']} subscription_active=${m['subscription_active']} officeId=${m['officeId'] ?? m['office_id'] ?? ''}',
        );

        var resolvedOfficeClient = isOfficeClient;
        if (!resolvedOfficeClient) {
          resolvedOfficeClient = await _syncOfficeClientStateFromServer(
            reason: 'user-sub-fallback',
          );
          _traceHome(
            'user-sub fallback-classification authUid=${user.uid} resolvedOfficeClient=$resolvedOfficeClient',
          );
        }

        final officeIdHint =
            (m['officeId'] ?? m['office_id'] ?? '').toString().trim();
        if (officeIdHint.isNotEmpty) {
          unawaited(_ensureOfficeClientRecordWatchStarted(
            officeIdHint: officeIdHint,
          ));
        }

        final blocked = (m['blocked'] ?? false) == true;
        final active = (m['subscription_active'] ?? true) == true;
        if (blocked) {
          await _userSub?.cancel();
          _userSub = null;
          if (!mounted) return;
          const msg = '?? ????? ????? ?? ??????. ????? ?? ???????.';
          if (resolvedOfficeClient && !_isOfficeImpersonationSession) {
            await _forceOfficeClientBlockedFlow(
              reason: 'user-sub-blocked',
              message: OfficeClientGuard.blockedOfficeClientMessage,
            );
          } else {
            await _forceLogoutAndGoLogin(msg: msg);
          }
          return;
        }

        if (resolvedOfficeClient && !_isOfficeImpersonationSession) return;

        final expired = SubscriptionExpiry.isExpired(m);

        if (!active || expired) {
          await _userSub?.cancel();
          _userSub = null;
          if (!mounted) return;
          final msg = expired ? '????? ???????.' : '?? ????? ???????.';
          await _forceLogoutAndGoLogin(msg: msg);
          return;
        }
      }, onError: (Object error, StackTrace st) async {
        final code = error is FirebaseException ? error.code : '';
        _traceHome('user-sub onError code=$code err=$error');
        if (code == 'permission-denied') {
          final isOfficeClient = await OfficeClientGuard.isOfficeClient();
          _traceHome(
              'user-sub permission-denied isOfficeClient=$isOfficeClient');
          _traceHome(
            'user-sub skip blocked-enforcement reason=permission-denied',
          );
        }
      });

      // Best-effort start for office-client record watcher (claims-based).
      unawaited(_ensureOfficeClientRecordWatchStarted());
    }

    // افتح صناديق Hive اللازمة قبل القراءة منها على الرئيسية
    _openHiveFuture = _openHiveBoxesForCurrentUser();
    _startHiveWatchdog();
    // ✅ تفعيل حارس الإنترنت لعملاء المكتب / جلسة المكتب
    _initOnlineGuard();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _officeClientSubByUid?.cancel();
    _officeClientSubByEmail?.cancel();
    _connSub?.cancel(); // ✅ إلغاء مراقبة الاتصال
    _stopHiveWatchdog();
    super.dispose();
  }

  // ====== فتح الصناديق اللازمة لهذا المستخدم ======
  Future<void> _openHiveBoxesForCurrentUser() async {
    final sw = Stopwatch()..start();
    _traceHome('open-hive start');
    try {
      // صندوق العقود مستخدم في الصفحة + شاشة العقود
      await _ensureContractsBoxOpen();
      _traceHome('contracts box ready +${sw.elapsedMilliseconds}ms');
      await _ensureInvoicesBoxOpen();
      _traceHome('invoices box ready +${sw.elapsedMilliseconds}ms');

      // إن كانت هناك صناديق أخرى تُعرض على الرئيسية، افتحها هنا بنفس النمط.
      // مثال (حسب مشروعك):
      // await _ensureBoxOpen(boxName('propertiesBox'));
      // await _ensureBoxOpen(boxName('tenantsBox'));
      // await _ensureBoxOpen(boxName('invoicesBox'));

      if (!mounted) return;
      setState(() => _hiveReady = true);
      _traceHomeBoxes('open-hive-success');
      _traceHome('open-hive success +${sw.elapsedMilliseconds}ms');
      _stopHiveWatchdog();
    } catch (e) {
      _traceHome('open-hive ERROR +${sw.elapsedMilliseconds}ms err=$e');
      if (!mounted) return;
      _hiveReady = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('تعذّر فتح قاعدة البيانات المحلية. جرّب إعادة المحاولة.')),
      );
      _stopHiveWatchdog();
      setState(() {});
    }
  }

  // ignore: unused_element
  Future<void> _ensureBoxOpen(String name) async {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
  }

  Future<void> _ensureContractsBoxOpen() async {
    final name = boxName('contractsBox');
    if (!Hive.isBoxOpen(name)) {
      _traceHome('opening contracts box name=$name');
      await Hive.openBox<Contract>(name);
      _traceHome('opened contracts box name=$name');
      return;
    }
    _traceHome('contracts box already open name=$name');
  }

  Future<void> _ensureInvoicesBoxOpen() async {
    final name = boxName(kInvoicesBox);
    if (!Hive.isBoxOpen(name)) {
      _traceHome('opening invoices box name=$name');
      await Hive.openBox<Invoice>(name);
      _traceHome('opened invoices box name=$name');
      return;
    }
    _traceHome('invoices box already open name=$name');
  }

  // ====== فحص إمكانية العودة للمكتب (في حال الانتحال) ======
  Future<void> _checkOfficeReturn() async {
    try {
      final token = await OfficeSession.officeToken;
      final session = Hive.isBoxOpen('sessionBox')
          ? Hive.box('sessionBox')
          : await Hive.openBox('sessionBox');
      final impersonation = session.get('officeImpersonation') == true;
      if (!mounted) return;
      setState(() {
        _hasOfficeReturn = (token != null && token.isNotEmpty);
        _isOfficeImpersonationFlag = impersonation;
      });
      _traceHome(
        'office-return tokenPresent=${token != null && token.isNotEmpty} impersonationFlag=$impersonation',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOfficeReturn = false;
        _isOfficeImpersonationFlag = false;
      });
    }
  }

  // الرجوع للمكتب
  Future<void> _onBackToOffice() async {
    await OfficeSession.backToOffice(context);
  }

  // مزوّد تاريخ انتهاء الاشتراك ليستخدمه NotificationsBell
  // ignore: unused_element
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
        final normalized =
            endKsaText.replaceAll('/', '-'); // ندعم yyyy/MM/dd و yyyy-MM-dd
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
          if (hasNet) {
            unawaited(_recheckBlockedOnReconnect());
          }
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
          color: Colors.black.withValues(alpha: 0.75),
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
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PropertiesScreen()));
          break;
        case 2:
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TenantsScreen()));
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

    final shouldExit = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الخروج',
      message: 'هل أنت متأكد من رغبتك في الخروج من التطبيق؟',
      confirmLabel: 'تأكيد الخروج',
      cancelLabel: 'إلغاء',
    );
    // ignore: dead_null_aware_expression
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
            initialFilter: filter ?? ContractQuickFilter.nearExpiry,
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

  Future<void> _refreshDashboard() async {
    if (_hasOfficeReturn) {
      await _onBackToOffice();
      return;
    }

    setState(() => _hiveReady = false);
    _openHiveFuture = _openHiveBoxesForCurrentUser();
    await _openHiveFuture;
    await _checkCurrentConnection();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: _homeBottom,
          extendBody: true,
          drawer: Builder(
            builder: (ctx) {
              final media = MediaQuery.of(ctx);
              final double topInset = media.padding.top;
              final double bottomInset =
                  _bottomBarHeight + media.padding.bottom;
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
          body: Stack(
            children: [
              // الخلفية
              const HomeBackground(),
              // لا تبني ما يعتمد على Hive قبل أن يكون جاهزًا
              if (!_hiveReady)
                const Center(
                  child: CircularProgressIndicator(color: _homeTurquoise),
                )
              else
                _buildHomeBody(),

              // ✅ طبقة حارس الإنترنت لعملاء المكتب / جلسة المكتب
              _buildOnlineGuardOverlay(),
            ],
          ),
          bottomNavigationBar: HomeBottomNavBar(
            key: _bottomNavKey,
            currentIndex: 0,
            onTap: _handleBottomTap,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBody() {
    final media = MediaQuery.of(context);
    final bottomPadding = _bottomBarHeight + media.padding.bottom + 22.h;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.w, 18.h, 16.w, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeHeader(
              title: _currentTitle,
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onRefreshTap: _refreshDashboard,
            ),
            SizedBox(height: 18.h),
            AnimatedBuilder(
              animation: Listenable.merge([
                Hive.box<Contract>(boxName(kContractsBox)).listenable(),
                Hive.box<Invoice>(boxName(kInvoicesBox)).listenable(),
              ]),
              builder: (context, _) {
                double receivables = 0;
                try {
                  receivables = sumReceivablesFromContractsExact(
                    includeArchived: false,
                  );
                } catch (_) {
                  receivables = 0;
                }

                return TotalDueCard(amount: receivables.toStringAsFixed(2));
              },
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: Hive.box<Contract>(boxName('contractsBox'))
                        .listenable(),
                    builder: (context, Box<Contract> box, _) {
                      int overdueCount = 0;

                      try {
                        for (final c in box.values) {
                          if (c.isArchived == true) continue;
                          if (isContractOverdueForHome(c)) overdueCount++;
                        }
                      } catch (_) {
                        overdueCount = 0;
                      }

                      return StatCard(
                        title: 'المدفوعات المتأخرة',
                        value: overdueCount.toString(),
                        iconAsset: '$_homeAssetPath/ic_late_payment.png',
                        valueColor: _homeRed,
                        onTap: () => _openContracts(
                          filter: ContractQuickFilter.overdue,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: NotificationsCounter(
                    builder: (notificationCount) => StatCard(
                      title: 'التنبيهات',
                      value: notificationCount.toString(),
                      iconAsset: '$_homeAssetPath/ic_notification.png',
                      valueColor: _homeYellow,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: DashboardActionCard(
                    label: 'العقارات',
                    iconAsset: '$_homeAssetPath/ic_properties.png',
                    onTap: () => _handleBottomTap(1),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DashboardActionCard(
                    label: 'العملاء',
                    iconAsset: '$_homeAssetPath/ic_clients.png',
                    onTap: () => _handleBottomTap(2),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DashboardActionCard(
                    label: 'العقود',
                    iconAsset: '$_homeAssetPath/ic_contracts.png',
                    onTap: () => _handleBottomTap(3),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: DashboardActionCard(
                    label: 'الخدمات',
                    iconAsset: '$_homeAssetPath/ic_services.png',
                    onTap: () => Navigator.pushNamed(context, '/maintenance'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DashboardActionCard(
                    label: 'السندات',
                    iconAsset: '$_homeAssetPath/ic_receipts.png',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InvoicesScreen()),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DashboardActionCard(
                    label: 'التقارير',
                    iconAsset: '$_homeAssetPath/ic_reports.png',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportsScreen()),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            RentDueAssistantCard(
              onTap: () =>
                  _openContracts(filter: ContractQuickFilter.nearExpiry),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyHomeBody() {
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
                // نسمع لأي تغيّر في العقود والسندات
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

                  // ignore: unused_local_variable
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
                            color: Color(0xFF0F766E),
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
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  ),
                  child: _FancyCard(
                    background: kCreamBg,
                    child: NotificationsCounter(
                      // ignore: avoid_types_as_parameter_names
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
                label: 'العملاء',
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

          // الصف الثاني: الخدمات - السندات - التقارير
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _QuickButton(
                icon: Icons.build,
                label: 'الخدمات',
                onTap: () {
                  Navigator.pushNamed(context, '/maintenance');
                },
              ),
              _QuickButton(
                icon: Icons.receipt_long,
                label: 'السندات',
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const InvoicesScreen()));
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
            onTap: () => _openContracts(filter: ContractQuickFilter.nearExpiry),
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

  // ignore: unused_element
  Widget _buildOfficeClientOfflineOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withValues(alpha: 0.75),
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

  // ignore: unused_element
  bool _isOverdueHome(Contract c) {
    if (c.isTerminated) return false;

    final today = _dateOnly(KsaTime.now());
    if (c.term == ContractTerm.daily) {
      return c.isExpiredByTime;
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

      // نعتبر العقد اليومي مُسدَّد إذا عنده سند مدفوعة بالكامل وغير ملغاة
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

        // سند سداد المقدم لا نعتبرها قسطاً عاديّاً
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

  // ignore: unused_element
  bool _isOverdueForHome(Contract c) {
    final today = _dateOnly(KsaTime.now());

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
      due = _dateOnly(_addMonthsHome(due, _monthsPerCycleHome(c.paymentCycle)));
    }
    return false;
  }

  // ---------------------------------------------------------------
}

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_homeTop, _homeMiddle, _homeBottom],
                stops: [0.0, 0.48, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Positioned(
            left: -115.w,
            top: 130.h,
            child: _BlurredGlow(
              size: 250.w,
              color: _homeTurquoise.withValues(alpha: 0.22),
              blur: 72,
            ),
          ),
          Positioned(
            right: -90.w,
            top: 290.h,
            child: _BlurredGlow(
              size: 180.w,
              color: const Color(0xFF1A5E78).withValues(alpha: 0.12),
              blur: 68,
            ),
          ),
          Positioned(
            left: 28.w,
            right: 28.w,
            bottom: -55.h,
            child: _BlurredGlow(
              height: 110.h,
              color: _homeTurquoise.withValues(alpha: 0.16),
              blur: 62,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurredGlow extends StatelessWidget {
  final double? size;
  final double? height;
  final Color color;
  final double blur;

  const _BlurredGlow({
    this.size,
    this.height,
    required this.color,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        width: size,
        height: height ?? size,
        decoration: BoxDecoration(
          shape: height == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: height == null ? null : BorderRadius.circular(999),
          color: color,
        ),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  final String title;
  final VoidCallback onMenuTap;
  final VoidCallback onRefreshTap;

  const HomeHeader({
    super.key,
    required this.title,
    required this.onMenuTap,
    required this.onRefreshTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderCircleButton(
          icon: Icons.menu_rounded,
          tooltip: 'القائمة',
          onTap: onMenuTap,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              color: _homeWhite,
              fontSize: 25.sp,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
        _HeaderCircleButton(
          icon: Icons.refresh_rounded,
          tooltip: 'تحديث',
          onTap: onRefreshTap,
        ),
      ],
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 38.w,
                child: Icon(icon, color: _homeWhite, size: 21.sp),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TotalDueCard extends StatelessWidget {
  final String amount;

  const TotalDueCard({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 122.h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF0B7F75),
            Color(0xFF0D4A5A),
            Color(0xFF0B2237),
          ],
          stops: [0.0, 0.42, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: _homeTurquoise.withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -36.w,
            top: -28.h,
            bottom: -18.h,
            child: _BlurredGlow(
              size: 168.w,
              color: _homeTurquoise.withValues(alpha: 0.34),
              blur: 52,
            ),
          ),
          Positioned(
            right: -8.w,
            top: 12.h,
            child: _BlurredGlow(
              size: 112.w,
              color: _homeTurquoise.withValues(alpha: 0.10),
              blur: 38,
            ),
          ),
          Positioned(
            right: 48.w,
            top: 26.h,
            child: _GlowParticle(size: 3.2.w, opacity: 0.42),
          ),
          Positioned(
            right: 86.w,
            bottom: 24.h,
            child: _GlowParticle(size: 2.4.w, opacity: 0.24),
          ),
          Positioned(
            right: 22.w,
            top: 26.h,
            child: IgnorePointer(
              child: DuesGrowthChart(
                width: 118.w,
                height: 86.h,
              ),
            ),
          ),
          Positioned(
            left: 18.w,
            top: 26.h,
            child: _DueWalletBadge(size: 66.w),
          ),
          Positioned(
            left: 100.w,
            right: 30.w,
            top: 21.h,
            bottom: 17.h,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 136.w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'إجمالي المستحقات',
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.cairo(
                            color: _homeWhite.withValues(alpha: 0.86),
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          amount,
                          textDirection: TextDirection.ltr,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 31.sp,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 22.w,
                        height: 20.h,
                        child: Image.asset(
                          '$_homeAssetPath/ic_saudi_riyal_symbol.png',
                          color: _homeWhite,
                          colorBlendMode: BlendMode.srcIn,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DueWalletBadge extends StatelessWidget {
  final double size;

  const _DueWalletBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _BlurredGlow(
            size: size * 1.04,
            color: _homeTurquoise.withValues(alpha: 0.24),
            blur: 16,
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFF2FBFA),
                  Color(0xFFE6F1F1),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.74),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(-3, -4),
                ),
                BoxShadow(
                  color: _homeTurquoise.withValues(alpha: 0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: Size.square(size * 0.72),
            painter: const _PremiumWalletPainter(),
          ),
        ],
      ),
    );
  }
}

class _PremiumWalletPainter extends CustomPainter {
  const _PremiumWalletPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final walletRect = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.36,
      size.width * 0.72,
      size.height * 0.42,
    );
    final wallet = RRect.fromRectAndRadius(
      walletRect,
      Radius.circular(size.width * 0.12),
    );

    canvas.drawRRect(
      wallet.shift(Offset(0, size.height * 0.045)),
      Paint()
        ..color = const Color(0xFF063B48).withValues(alpha: 0.24)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );

    canvas.drawRRect(
      wallet,
      Paint()
        ..shader = ui.Gradient.linear(
          walletRect.topLeft,
          walletRect.bottomRight,
          [
            const Color(0xFF35E6C1),
            const Color(0xFF11A895),
            const Color(0xFF07536A),
          ],
          const [0.0, 0.54, 1.0],
        ),
    );

    final topSlotRect = Rect.fromLTWH(
      size.width * 0.21,
      size.height * 0.25,
      size.width * 0.53,
      size.height * 0.17,
    );
    final topSlot = RRect.fromRectAndRadius(
      topSlotRect,
      Radius.circular(size.width * 0.075),
    );
    canvas.drawRRect(
      topSlot,
      Paint()
        ..shader = ui.Gradient.linear(
          topSlotRect.topLeft,
          topSlotRect.bottomRight,
          [
            const Color(0xFF61F7DE),
            const Color(0xFF0E8C7C),
          ],
        ),
    );
    canvas.drawRRect(
      topSlot.deflate(size.width * 0.018),
      Paint()..color = const Color(0xFF0A5B63).withValues(alpha: 0.55),
    );

    final pocketRect = Rect.fromLTWH(
      size.width * 0.63,
      size.height * 0.43,
      size.width * 0.31,
      size.height * 0.25,
    );
    final pocket = RRect.fromRectAndRadius(
      pocketRect,
      Radius.circular(size.width * 0.09),
    );
    canvas.drawRRect(
      pocket,
      Paint()
        ..shader = ui.Gradient.linear(
          pocketRect.topLeft,
          pocketRect.bottomRight,
          [
            const Color(0xFF43F0D1),
            const Color(0xFF075164),
          ],
        ),
    );

    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.55),
      size.width * 0.045,
      Paint()..color = const Color(0xFFB7FFF4).withValues(alpha: 0.88),
    );

    canvas.drawCircle(
      Offset(size.width * 0.41, size.height * 0.55),
      size.width * 0.105,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.40, size.height * 0.50),
          size.width * 0.14,
          [
            const Color(0xFF8FFFF0).withValues(alpha: 0.72),
            const Color(0xFF1DBFA8).withValues(alpha: 0.20),
          ],
        ),
    );

    canvas.drawRRect(
      wallet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumWalletPainter oldDelegate) => false;
}

class DuesGrowthChart extends StatelessWidget {
  final double width;
  final double height;

  const DuesGrowthChart({
    super.key,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const CustomPaint(painter: _DuesGrowthChartPainter()),
    );
  }
}

class _DuesGrowthChartPainter extends CustomPainter {
  const _DuesGrowthChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final baseY = h * 0.86;
    final barWidth = w * 0.16;
    final gap = w * 0.09;
    final firstX = w * 0.36;
    final barHeights = <double>[h * 0.35, h * 0.52, h * 0.72];
    final barRects = <RRect>[];

    for (var i = 0; i < 3; i += 1) {
      final left = firstX + i * (barWidth + gap);
      final top = baseY - barHeights[i];
      final rect = Rect.fromLTWH(left, top, barWidth, barHeights[i]);
      final radius = Radius.circular(w * 0.035);
      barRects.add(RRect.fromRectAndRadius(rect, radius));
    }

    final groundLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF35E6C1).withValues(alpha: 0.20);
    canvas.drawLine(
      Offset(firstX - w * 0.08, baseY + h * 0.012),
      Offset(w * 0.96, baseY + h * 0.012),
      groundLine,
    );

    for (final bar in barRects) {
      canvas.drawRRect(
        bar.shift(Offset(0, h * 0.012)),
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF2FE6C8).withValues(alpha: 0.20)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, w * 0.045),
      );
    }

    for (var i = 0; i < barRects.length; i += 1) {
      final bar = barRects[i];
      canvas.drawRRect(
        bar,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(bar.left, bar.top),
            Offset(bar.left, bar.bottom),
            [
              const Color(0xFF69FFE6).withValues(alpha: 0.95),
              const Color(0xFF35E6C1).withValues(alpha: 0.72),
              const Color(0xFF0A756E).withValues(alpha: 0.54),
            ],
            const [0.0, 0.48, 1.0],
          ),
      );
      canvas.drawRRect(
        bar.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = ui.Gradient.linear(
            Offset(bar.left, bar.top),
            Offset(bar.right, bar.bottom),
            [
              Colors.white.withValues(alpha: 0.34),
              const Color(0xFF2FE6C8).withValues(alpha: 0.18),
            ],
          ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            bar.left + barWidth * 0.16,
            bar.top + h * 0.05,
            barWidth * 0.18,
            bar.height * 0.70,
          ),
          Radius.circular(w * 0.02),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.16 - (i * 0.025)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DuesGrowthChartPainter oldDelegate) => false;
}

class _GlowParticle extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowParticle({
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _homeTurquoise.withValues(alpha: opacity),
        boxShadow: [
          BoxShadow(
            color: _homeTurquoise.withValues(alpha: opacity),
            blurRadius: size * 3.2,
            spreadRadius: size * 0.35,
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String iconAsset;
  final Color valueColor;
  final VoidCallback onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.iconAsset,
    required this.valueColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleTop = title.length > 10 ? 19.5.h : 18.h;

    return _DarkCardShell(
      height: 92.h,
      borderRadius: 22.r,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            left: 16.w,
            top: 16.h,
            child: SizedBox(
              width: 38.w,
              height: 38.w,
              child: Center(
                child: Image.asset(
                  iconAsset,
                  width: 32.w,
                  height: 32.w,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            right: 16.w,
            top: titleTop,
            left: 58.w,
            height: 20.h,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: GoogleFonts.cairo(
                    color: _homeWhite.withValues(alpha: 0.92),
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 22.w,
            bottom: 12.h,
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: valueColor,
                fontSize: 26.sp,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardActionCard extends StatelessWidget {
  final String label;
  final String iconAsset;
  final VoidCallback onTap;

  const DashboardActionCard({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.90,
      child: _DarkCardShell(
        height: 102.h,
        borderRadius: 23.r,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              iconAsset,
              width: 31.w,
              height: 31.w,
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                color: _homeWhite,
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RentDueAssistantCard extends StatelessWidget {
  final VoidCallback onTap;

  const RentDueAssistantCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _DarkCardShell(
      height: 104.h,
      borderRadius: 22.r,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 22.w,
            top: 25.h,
            bottom: 23.h,
            child: Opacity(
              opacity: 0.26,
              child: Transform.rotate(
                angle: -0.05,
                child: Image.asset(
                  '$_homeAssetPath/ic_calendar_due.png',
                  width: 52.w,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            left: 13.w,
            top: 13.h,
            child: _HomeAssistantChatIcon(size: 74.w),
          ),
          Positioned(
            left: 96.w,
            right: 84.w,
            top: 21.h,
            bottom: 17.h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'مرحبا بك!',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    color: _homeTurquoise,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 5.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'أقرب استحقاقات الإيجار',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: GoogleFonts.cairo(
                      color: _homeWhite,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                SizedBox(height: 7.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'لا يوجد استحقاقات قريبة',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: GoogleFonts.cairo(
                      color: _homeMuted,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAssistantChatIcon extends StatefulWidget {
  final double size;

  const _HomeAssistantChatIcon({required this.size});

  @override
  State<_HomeAssistantChatIcon> createState() => _HomeAssistantChatIconState();
}

class _HomeAssistantChatIconState extends State<_HomeAssistantChatIcon>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final AnimationController _ringController;
  late final AnimationController _orbitController;

  late final Animation<double> _floatAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    _floatAnim = Tween<double>(begin: 0, end: -4).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.045).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final auraSize = size * 0.95;
    final orbitSize = size * 0.83;
    final iconPadding = size * 0.09;

    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _floatController,
          _pulseController,
          _ringController,
          _orbitController,
        ]),
        builder: (context, child) {
          final ringValue = _ringController.value;
          final delayedRing = (ringValue + 0.5) % 1.0;
          final orbitAngle = _orbitController.value * 2 * math.pi;

          return Transform.translate(
            offset: Offset(0, _floatAnim.value),
            child: Transform.scale(
              scale: _pulseAnim.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: auraSize,
                    height: auraSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF5BC0FF).withValues(alpha: 0.20),
                          const Color(0xFF2E67FF).withValues(alpha: 0.075),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: (1 - ringValue) * 0.30,
                    child: Container(
                      width: size * 0.74 + (ringValue * size * 0.12),
                      height: size * 0.74 + (ringValue * size * 0.12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF7DD3FF),
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: (1 - delayedRing) * 0.20,
                    child: Container(
                      width: size * 0.70 + (delayedRing * size * 0.10),
                      height: size * 0.70 + (delayedRing * size * 0.10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFA9E7FF),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: orbitAngle,
                    child: SizedBox.square(
                      dimension: orbitSize,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: size * 0.075,
                          height: size * 0.075,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFB9F3FF),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF9FE8FF),
                                blurRadius: 9,
                                spreadRadius: 1.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: size * 0.73,
                    height: size * 0.73,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF54B8FF),
                          Color(0xFF347DFF),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF3F91FF).withValues(alpha: 0.42),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: size * 0.50,
                            height: size * 0.19,
                            margin: EdgeInsets.only(top: size * 0.09),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(100),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.25),
                                  Colors.white.withValues(alpha: 0.02),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(iconPadding),
                          child: Image.asset(
                            _aiBotAsset,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          right: size * 0.065,
                          bottom: size * 0.065,
                          child: Container(
                            width: size * 0.15,
                            height: size * 0.15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF10B981),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.6,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.48),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class HomeBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const HomeBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21.r),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 70.h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21.r),
                  color: const Color(0xFF0A1C2D).withValues(alpha: 0.88),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _homeTurquoise.withValues(alpha: 0.11),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 9),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _HomeNavItem(
                      label: 'الرئيسية',
                      index: 0,
                      currentIndex: currentIndex,
                      onTap: onTap,
                      icon: Icons.home_rounded,
                    ),
                    _HomeNavItem(
                      label: 'العقارات',
                      index: 1,
                      currentIndex: currentIndex,
                      onTap: onTap,
                      asset: '$_homeAssetPath/ic_properties.png',
                    ),
                    _HomeNavItem(
                      label: 'العملاء',
                      index: 2,
                      currentIndex: currentIndex,
                      onTap: onTap,
                      asset: '$_homeAssetPath/ic_clients.png',
                    ),
                    _HomeNavItem(
                      label: 'العقود',
                      index: 3,
                      currentIndex: currentIndex,
                      onTap: onTap,
                      asset: '$_homeAssetPath/ic_contracts.png',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavItem extends StatelessWidget {
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final IconData? icon;
  final String? asset;

  const _HomeNavItem({
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    this.icon,
    this.asset,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    final color =
        isActive ? _homeTurquoise : _homeMuted.withValues(alpha: 0.88);

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (asset != null)
                  Image.asset(
                    asset!,
                    width: 23.w,
                    height: 23.w,
                    color: color,
                  )
                else
                  Icon(icon, color: color, size: 26.sp),
                SizedBox(height: 3.h),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    color: color,
                    fontSize: 11.5.sp,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            if (isActive)
              Positioned(
                bottom: 0,
                child: Container(
                  width: 58.w,
                  height: 3.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: _homeTurquoise,
                    boxShadow: [
                      BoxShadow(
                        color: _homeTurquoise.withValues(alpha: 0.72),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DarkCardShell extends StatelessWidget {
  final Widget child;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;

  const _DarkCardShell({
    required this.child,
    required this.height,
    required this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final content = Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: _homeCard.withValues(alpha: 0.78),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: content,
      ),
    );
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
              color: const Color(0x66000000).withValues(alpha: 0.06),
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
  const _QuickButton(
      {required this.icon, required this.label, required this.onTap});

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
              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                  color: const Color(0x66000000).withValues(alpha: 0.10),
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
