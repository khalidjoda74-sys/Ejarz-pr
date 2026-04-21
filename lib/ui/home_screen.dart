// lib/ui/home_screen.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart'; // تأكد من الدالة boxName
import '../utils/contract_utils.dart'; // لحساب إجمالي المستحقات من العقود
import 'notifications_screen.dart'
    show NotificationsScreen, NotificationsCounter;
import 'widgets/notifications_bell.dart';
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
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// جلسة المكتب (للعودة عند الانتحال)
import '../screens/office/office.dart' show OfficeSession;
import '../widgets/custom_confirm_dialog.dart';
import 'ai_chat/ai_chat_icon.dart';

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
      final propertyBox = Hive.isBoxOpen(propertyBoxName)
          ? Hive.box(propertyBoxName)
          : null;
      final tenantBox =
          Hive.isBoxOpen(tenantBoxName) ? Hive.box(tenantBoxName) : null;
      final invoiceBox = Hive.isBoxOpen(invoiceBoxName)
          ? Hive.box(invoiceBoxName)
          : null;
      final contractBox = Hive.isBoxOpen(contractBoxName)
          ? Hive.box(contractBoxName)
          : null;

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
          final msg = '?? ????? ????? ?? ??????. ????? ?? ???????.';
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
              if (_hasOfficeReturn)
                IconButton(
                  tooltip: 'الرجوع إلى لوحة المكتب',
                  onPressed: _onBackToOffice,
                  icon: const Icon(
                    Icons.autorenew_rounded,
                    color: Colors.white,
                  ),
                ),
              if (!_hasOfficeReturn)
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
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF0F766E),
                      Color(0xFF14B8A6)
                    ],
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

              const AiChatFloatingIcon(),
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
