// lib/ui/login_screen.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/services/offline_sync_service.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/hive_service.dart';
import '../data/sync/sync_bridge.dart';
import '../data/services/user_scope.dart' as scope;
import 'package:hive_flutter/hive_flutter.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/activity_log_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/custom_confirm_dialog.dart';

import '../data/services/firestore_user_collections.dart';
import '../data/repos/tenants_repo.dart';
import '../data/services/subscription_expiry.dart';

class _BlockedLoginDecision {
  final bool shouldBlock;
  final bool confirmedUnblocked;

  const _BlockedLoginDecision({
    required this.shouldBlock,
    required this.confirmedUnblocked,
  });
}

class _OfficeClientBlockedProbe {
  final bool confirmed;
  final bool blocked;
  final bool permissionDenied;

  const _OfficeClientBlockedProbe({
    required this.confirmed,
    required this.blocked,
    required this.permissionDenied,
  });
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _disabledLoginMessage =
      'تم إيقافك عن تسجيل الدخول إلى هذا الحساب. يرجى مراجعة الإدارة لاستعادة صلاحية الدخول.';

  void _traceWorkspace(String message) {
    debugPrint('[WorkspaceTrace][Login] $message');
  }

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _authError;
  bool _rememberEmail = true;
  bool _officeBlockedFlag = false;
  bool _officeBlockedDialogShown = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_handleEmailChanged);
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final sp = await SharedPreferences.getInstance();
    _rememberEmail = sp.getBool('remember_email') ?? true;
    final saved = sp.getString('remembered_email');
    if (saved != null) _emailCtrl.text = saved;
    await _checkOfficeBlockedFlag();
    if (mounted) setState(() {});
  }

  Future<void> _checkOfficeBlockedFlag() async {
    final email = OfficeClientGuard.normalizeEmail(_emailCtrl.text);
    final state = await OfficeClientGuard.localBlockStateForInput(email: email);
    final blocked = state == OfficeLocalBlockState.confirmedBlocked;
    if (!mounted) return;
    if (!blocked) {
      if (_officeBlockedFlag) {
        setState(() => _officeBlockedFlag = false);
      }
      _traceWorkspace(
        'office-block-init state=$state blocked=false email=$email',
      );
      return;
    }
    _officeBlockedFlag = true;
    final online = await _hasUsableInternet();
    _traceWorkspace(
      'office-block-init blocked=$blocked online=$online email=$email',
    );
    if (!online) {
      await _showOfficeBlockedDialog();
    }
  }

  void _handleEmailChanged() {
    unawaited(_refreshBlockedFlagForTypedEmail());
  }

  Future<void> _refreshBlockedFlagForTypedEmail() async {
    final email = OfficeClientGuard.normalizeEmail(_emailCtrl.text);
    final state = await OfficeClientGuard.localBlockStateForInput(email: email);
    final blocked = state == OfficeLocalBlockState.confirmedBlocked;
    if (!mounted) return;
    if (_officeBlockedFlag != blocked) {
      setState(() => _officeBlockedFlag = blocked);
    }
    _traceWorkspace(
      'office-block-email-changed email=$email state=$state blocked=$blocked',
    );
  }

  Future<OfficeLocalBlockState> _localBlockedStateForInputEmail(
    String email,
  ) async {
    final normalizedEmail = OfficeClientGuard.normalizeEmail(email);
    return OfficeClientGuard.localBlockStateForInput(email: normalizedEmail);
  }

  Future<bool> _enforceLocalBlockedIfNeeded({
    required String reason,
  }) async {
    final email = OfficeClientGuard.normalizeEmail(_emailCtrl.text);
    final state = await _localBlockedStateForInputEmail(email);
    final blocked = state == OfficeLocalBlockState.confirmedBlocked;
    final online = blocked ? await _hasUsableInternet() : false;
    _traceWorkspace(
      'office-block-local-check reason=$reason email=$email state=$state blocked=$blocked online=$online',
    );
    if (!mounted || !blocked) return false;
    _officeBlockedFlag = true;
    if (online) {
      // Allow one online login attempt to revalidate with server and clear the
      // local block if the office re-enabled the account.
      return false;
    }
    _officeBlockedFlag = true;
    await _showOfficeBlockedDialog();
    return true;
  }

  Future<bool> _hasUsableInternet() async {
    try {
      final r = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 2));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      try {
        final r = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 2));
        return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _showOfficeBlockedDialog() async {
    if (_officeBlockedDialogShown || !mounted) return;
    _officeBlockedDialogShown = true;
    await CustomConfirmDialog.show(
      context: context,
      title: 'تم إيقاف الحساب',
      message: OfficeClientGuard.blockedOfficeClientMessage,
      forceBlockedDialog: true,
      confirmLabel: 'خروج',
    );
    _officeBlockedDialogShown = false;
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_handleEmailChanged);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _isOfficeStaffMap(Map<String, dynamic> m) {
    final role = (m['role'] ?? '').toString().toLowerCase();
    final accountType = (m['accountType'] ?? '').toString().toLowerCase();
    final entityType = (m['entityType'] ?? '').toString().toLowerCase();
    final targetRole = (m['targetRole'] ?? '').toString().toLowerCase();
    final officePermission =
        (m['officePermission'] ?? '').toString().toLowerCase();
    final permission = (m['permission'] ?? '').toString().toLowerCase();
    return role == 'office_staff' ||
        accountType == 'office_staff' ||
        entityType == 'office_user' ||
        targetRole == 'office' ||
        officePermission == 'full' ||
        officePermission == 'view' ||
        permission == 'full' ||
        permission == 'view';
  }

  bool _isExplicitOfficeClientMap(Map<String, dynamic> m) {
    if (_isOfficeStaffMap(m)) return false;
    final origin = (m['origin'] ?? '').toString().toLowerCase();
    final accountType = (m['accountType'] ?? '').toString().toLowerCase();
    final entityType = (m['entityType'] ?? '').toString().toLowerCase();
    final targetRole = (m['targetRole'] ?? '').toString().toLowerCase();

    return m['is_office_client'] == true ||
        origin == 'officeclient' ||
        accountType == 'office_client' ||
        entityType == 'office_client' ||
        targetRole == 'client';
  }

  Future<bool> _hasOfficeStaffRecordUnderOffice(User u, String officeId) async {
    if (officeId.isEmpty) return false;
    final ref = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeId)
        .collection('clients');

    try {
      final byUidDoc = await ref.doc(u.uid).get();
      if (byUidDoc.exists && _isOfficeStaffMap(byUidDoc.data() ?? {})) {
        return true;
      }
    } catch (_) {}

    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      try {
        final byEmailDoc = await ref.doc(email).get();
        if (byEmailDoc.exists && _isOfficeStaffMap(byEmailDoc.data() ?? {})) {
          return true;
        }
      } catch (_) {}
    }

    try {
      final byUid = await ref.where('uid', isEqualTo: u.uid).limit(5).get();
      for (final d in byUid.docs) {
        if (_isOfficeStaffMap(d.data())) return true;
      }
    } catch (_) {}

    if (email.isNotEmpty) {
      try {
        final byEmail =
            await ref.where('email', isEqualTo: email).limit(5).get();
        for (final d in byEmail.docs) {
          if (_isOfficeStaffMap(d.data())) return true;
        }
      } catch (_) {}
    }

    return false;
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب من قِبل الإدارة.';
      case 'user-not-found':
      case 'wrong-password':
        return 'بيانات الدخول غير صحيحة.';
      case 'too-many-requests':
        return 'محاولات كثيرة، يرجى المحاولة لاحقًا.';
      case 'network-request-failed':
        return 'تحقق من اتصال الإنترنت.';
      default:
        return 'تعذر تسجيل الدخول. حاول لاحقًا.';
    }
  }

  Future<void> _showLoginAlert({
    required String title,
    required String message,
    bool showCancel = true,
  }) async {
    if (!mounted) return;
    final effectiveTitle = showCancel ? title : 'تنبيه';
    final isOfflineFirstLoginAlert = message.contains('أول مرة عبر الإنترنت') ||
        message.contains('Ù…Ø±Ø© Ø¹Ø¨Ø± Ø§Ù„Ø¥Ù†ØªØ±Ù†Øª') ||
        title.contains('بدون إنترنت') ||
        title.contains('Ø¨Ø¯ÙˆÙ† Ø¥Ù†ØªØ±Ù†Øª');
    final computedShowCancel = isOfflineFirstLoginAlert ? false : showCancel;
    final computedTitle = computedShowCancel ? effectiveTitle : 'تنبيه';
    await CustomConfirmDialog.show(
      context: context,
      title: computedTitle,
      message: message,
      showCancel: computedShowCancel,
      confirmLabel: 'حسنًا',
    );
  }

  Future<void> _showDisabledLoginDialog() async {
    if (!mounted) return;
    await CustomConfirmDialog.show(
      context: context,
      title: 'تنبيه',
      message: _disabledLoginMessage,
      showCancel: false,
      confirmLabel: 'حسنًا',
    );
  }

  bool _isBlockedClientMap(Map<String, dynamic> m) {
    return OfficeClientGuard.isBlockedClientData(m);
  }

  Future<void> _clearBlockedLoginSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    await OfficeClientGuard.clearSessionState();
    await OfficeClientGuard.refreshFromLocal();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('last_login_email');
      await sp.remove('last_login_uid');
      await sp.remove('last_login_role');
      await sp.remove('last_login_offline');
    } catch (_) {}
  }

  Future<void> _enforceBlockedOfficeClientLogin(User user) async {
    await OfficeClientGuard.markOfficeBlocked(
      true,
      email: user.email,
      uid: user.uid,
    );
    _officeBlockedFlag = true;
    await _showOfficeBlockedDialog();
    await _clearBlockedLoginSession();
  }

  Future<_OfficeClientBlockedProbe> _probeBlockedInOfficeClientRecords({
    required User user,
    required Map<String, dynamic> userDoc,
  }) async {
    final officeHints = <String>{};
    final fromDoc =
        (userDoc['officeId'] ?? userDoc['office_id'] ?? '').toString().trim();
    if (fromDoc.isNotEmpty) officeHints.add(fromDoc);

    try {
      final token = await user.getIdTokenResult().timeout(
            const Duration(seconds: 2),
          );
      final claims = token.claims ?? const <String, dynamic>{};
      final fromClaims =
          (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
      if (fromClaims.isNotEmpty) officeHints.add(fromClaims);
    } catch (_) {}

    if (officeHints.isEmpty) {
      return const _OfficeClientBlockedProbe(
        confirmed: false,
        blocked: false,
        permissionDenied: false,
      );
    }

    final email = (user.email ?? '').trim().toLowerCase();
    var confirmed = false;
    var permissionDenied = false;
    for (final officeId in officeHints) {
      final ref = FirebaseFirestore.instance
          .collection('offices')
          .doc(officeId)
          .collection('clients');
      try {
        final byUid = await ref.doc(user.uid).get().timeout(
              const Duration(seconds: 2),
            );
        confirmed = true;
        if (byUid.exists &&
            _isBlockedClientMap(byUid.data() ?? const <String, dynamic>{})) {
          return const _OfficeClientBlockedProbe(
            confirmed: true,
            blocked: true,
            permissionDenied: false,
          );
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          permissionDenied = true;
        }
      } catch (_) {}

      if (email.isNotEmpty) {
        try {
          final byEmail = await ref.doc(email).get().timeout(
                const Duration(seconds: 2),
              );
          confirmed = true;
          if (byEmail.exists &&
              _isBlockedClientMap(
                  byEmail.data() ?? const <String, dynamic>{})) {
            return const _OfficeClientBlockedProbe(
              confirmed: true,
              blocked: true,
              permissionDenied: false,
            );
          }
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            permissionDenied = true;
          }
        } catch (_) {}
      }
    }

    return _OfficeClientBlockedProbe(
      confirmed: confirmed,
      blocked: false,
      permissionDenied: permissionDenied,
    );
  }

  Future<_BlockedLoginDecision> _handleBlockedLoginIfNeeded({
    required User user,
    required Map<String, dynamic> userDoc,
    required bool userDocReadOk,
  }) async {
    final blockedInUserDoc =
        userDocReadOk && OfficeClientGuard.isBlockedClientData(userDoc);
    bool blockedInOfficeRecords = false;
    bool officeCheckConfirmed = false;
    bool officeCheckPermissionDenied = false;
    try {
      final officeClientMatch =
          await OfficeClientGuard.findOfficeClientMatchForUser(
        user,
        source: Source.server,
        timeout: const Duration(seconds: 3),
      );
      officeCheckConfirmed = true;
      blockedInOfficeRecords = officeClientMatch?.isBlocked == true;
      _traceWorkspace(
        'office-block-server-check uid=${user.uid} matched=${officeClientMatch != null} by=${officeClientMatch?.matchedBy ?? ''} officeId=${officeClientMatch?.officeId ?? ''} blocked=$blockedInOfficeRecords',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        officeCheckPermissionDenied = true;
      }
      _traceWorkspace(
        'office-block-server-check firebase-error uid=${user.uid} code=${e.code} err=$e',
      );
    } catch (e) {
      _traceWorkspace('office-block-server-check error uid=${user.uid} err=$e');
    }
    if (!officeCheckConfirmed) {
      final probe = await _probeBlockedInOfficeClientRecords(
        user: user,
        userDoc: userDoc,
      );
      blockedInOfficeRecords = probe.blocked;
      officeCheckConfirmed = probe.confirmed;
      officeCheckPermissionDenied =
          officeCheckPermissionDenied || probe.permissionDenied;
      _traceWorkspace(
        'office-block-fallback confirmed=$officeCheckConfirmed blocked=$blockedInOfficeRecords permissionDenied=$officeCheckPermissionDenied',
      );
    }
    if (!blockedInUserDoc && !blockedInOfficeRecords) {
      final confirmedUnblocked =
          (userDocReadOk || officeCheckConfirmed) &&
              !blockedInUserDoc &&
              !blockedInOfficeRecords;
      return _BlockedLoginDecision(
        shouldBlock: false,
        confirmedUnblocked: confirmedUnblocked,
      );
    }

    if (blockedInOfficeRecords) {
      await _enforceBlockedOfficeClientLogin(user);
    } else {
      await _enforceBlockedOfficeClientLogin(user);
    }
    return const _BlockedLoginDecision(
      shouldBlock: true,
      confirmedUnblocked: false,
    );
  }

  Future<void> _tryPromoteToAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sp = await SharedPreferences.getInstance();
    final flagKey = 'promoted_admin_${user.uid}';
    final already = sp.getBool(flagKey) ?? false;
    if (already) return;

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

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
            'تمت ترقية حسابك إلى أدمن.',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
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
            'تعذر طلب الترقية: ${e.message ?? e.code}',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _onLogin() async {
    if (await _enforceLocalBlockedIfNeeded(reason: 'login-tap')) {
      return;
    }
    if (_officeBlockedFlag) {
      _traceWorkspace('office-block-local-check allowing-online-revalidation');
    }
    if (!_formKey.currentState!.validate()) return;

    final hasInternet = await ConnectivityService.instance.refresh();
    if (!hasInternet) {
      await _showLoginAlert(
        title: 'يجب الاتصال بالإنترنت',
        message:
            'تم إيقاف تسجيل الدخول بدون إنترنت. يجب الاتصال بالإنترنت للتحقق من الحساب ووقت خادم السعودية قبل المتابعة.',
        showCancel: false,
      );
      return;
    }

    final loginSw = Stopwatch()..start();

    setState(() {
      _loading = true;
      _authError = null;
    });

    final email = OfficeClientGuard.normalizeEmail(_emailCtrl.text);
    final pass = _passCtrl.text;

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final sp = await SharedPreferences.getInstance();
      await sp.setBool('remember_email', _rememberEmail);
      if (_rememberEmail) {
        await sp.setString('remembered_email', email);
      } else {
        await sp.remove('remembered_email');
      }

      await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);

      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      Map<String, dynamic> umap = <String, dynamic>{};
      var userDocReadOk = false;
      try {
        final udoc = await FirebaseFirestore.instance.doc('users/$uid').get();
        umap = udoc.data() ?? <String, dynamic>{};
        userDocReadOk = true;
      } catch (_) {}

      final blockedDecision = await _handleBlockedLoginIfNeeded(
        user: user,
        userDoc: umap,
        userDocReadOk: userDocReadOk,
      ).timeout(
        const Duration(seconds: 4),
        onTimeout: () => const _BlockedLoginDecision(
          shouldBlock: false,
          confirmedUnblocked: false,
        ),
      );
      if (blockedDecision.shouldBlock) return;
      if (blockedDecision.confirmedUnblocked) {
        await OfficeClientGuard.markOfficeBlocked(
          false,
          email: user.email,
          uid: user.uid,
        );
        _officeBlockedFlag = false;
        _officeBlockedDialogShown = false;
      } else if (_officeBlockedFlag) {
        _traceWorkspace(
          'office-block-revalidate unresolved keep-local-block=true',
        );
        await _showOfficeBlockedDialog();
        await _clearBlockedLoginSession();
        return;
      }
      _traceWorkspace(
          'login-phase blocked-check-ms=${loginSw.elapsedMilliseconds}');

      try {
        await KsaTime.ensureSynced(force: true);
      } catch (_) {}
      if (!KsaTime.isSynced) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        await _showLoginAlert(
          title: 'تعذر التحقق من وقت الخادم',
          message:
              'تعذر تأكيد وقت خادم السعودية حاليًا. تحقق من اتصال الإنترنت ثم أعد المحاولة.',
          showCancel: false,
        );
        return;
      }
      KsaTime.startAutoSync();

      final bool subActiveFlag = (umap['subscription_active'] ?? true) == true;

      final bool isExpired = SubscriptionExpiry.isExpired(umap);

      if (!subActiveFlag || isExpired) {
        if (!mounted) return;
        final msg = !subActiveFlag
            ? 'تم تعطيل اشتراكك. يرجى التواصل مع الإدارة.'
            : 'انتهى اشتراكك. لا يمكنك تسجيل الدخول إلا بعد تجديد الاشتراك.';

        await CustomConfirmDialog.show(
          context: context,
          title: 'انتهاء الاشتراك',
          message: msg,
          confirmLabel: 'حسنًا',
        );

        await FirebaseAuth.instance.signOut();
        return;
      }

      unawaited(_tryPromoteToAdmin());

      try {
        await SyncManager.instance.stopAll();
      } catch (_) {}

      try {
        OfflineSyncService.instance.dispose();
      } catch (_) {}

      String rawRole = 'client';
      String role = 'client';
      Map<String, dynamic> userProfileData = const <String, dynamic>{};
      try {
        final t = await user.getIdTokenResult(true);
        final claims = (t.claims ?? {}).map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final r = t.claims?['role']?.toString();
        if (r != null && r.isNotEmpty) {
          rawRole = r.toLowerCase();
        } else if (_isOfficeStaffMap(claims)) {
          rawRole = 'office_staff';
        }
        role = rawRole == 'office_owner' ? 'office' : rawRole;
      } catch (_) {}

      if (role == 'client' || role == 'reseller' || role == 'admin') {
        try {
          final d = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final data = d.data() ?? <String, dynamic>{};
          userProfileData = data;
          final rr = d.data()?['role']?.toString();
          if (rr != null && rr.isNotEmpty) {
            rawRole = rr.toLowerCase();
          } else if (_isOfficeStaffMap(data)) {
            rawRole = 'office_staff';
          }
          role = rawRole == 'office_owner' ? 'office' : rawRole;
        } catch (_) {}
      }

      // Resolve office workspace before classifying as office client
      var workspaceUid = user.uid;
      String? resolvedOfficeUid;
      final likelyOfficeStaff = rawRole == 'office' ||
          rawRole == 'office_owner' ||
          rawRole == 'office_staff';
      if (likelyOfficeStaff) {
        resolvedOfficeUid = await _resolveParentOfficeUidForStaff()
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
      }
      if (resolvedOfficeUid != null && resolvedOfficeUid.isNotEmpty) {
        final isStaffWorkspace = resolvedOfficeUid == user.uid
            ? true
            : await _hasOfficeStaffRecordUnderOffice(user, resolvedOfficeUid);
        if (isStaffWorkspace) {
          role = 'office';
          workspaceUid = resolvedOfficeUid;
        } else {
          _traceWorkspace(
            'login-reject-workspace candidate=$resolvedOfficeUid authUid=${user.uid}',
          );
        }
      }
      _traceWorkspace(
        'login-classification uid=${user.uid} rawRole=$rawRole role=$role workspaceUid=$workspaceUid',
      );
      if (rawRole == 'office_staff' && role != 'office') {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        scope.clearFixedUid();
        if (!mounted) return;
        await CustomConfirmDialog.show(
          context: context,
          title: 'تنبيه',
          message:
              'تعذر ربط حساب موظف المكتب بالمكتب الرئيسي. يرجى إعادة حفظ المستخدم من حساب المكتب الرئيسي ثم المحاولة مرة أخرى.',
          confirmLabel: 'حسنًا',
        );
        return;
      }
      final isOfficeClient = role == 'office'
          ? false
          : await _isOfficeManagedClient()
              .timeout(const Duration(seconds: 4), onTimeout: () => false);
      _traceWorkspace('login-phase classify-ms=${loginSw.elapsedMilliseconds}');

      await _initializeWorkspaceScope(workspaceUid);
      _traceWorkspace(
          'scope-initialized workspaceUid=$workspaceUid role=$role');

      try {
        final sp2 = await SharedPreferences.getInstance();
        final rawEmailKey = _emailCtrl.text.trim();

        await sp2.remove('offline_uid_$email');
        await sp2.remove('offline_role_$email');
        await sp2.remove('offline_pass_$email');
        await sp2.remove('offline_is_office_client_$email');
        if (rawEmailKey.isNotEmpty && rawEmailKey != email) {
          await sp2.remove('offline_uid_$rawEmailKey');
          await sp2.remove('offline_role_$rawEmailKey');
          await sp2.remove('offline_pass_$rawEmailKey');
          await sp2.remove('offline_is_office_client_$rawEmailKey');
        }
        if (role == 'office') {
          await sp2.setString('office_workspace_uid_${user.uid}', workspaceUid);
        } else {
          await sp2.remove('office_workspace_uid_${user.uid}');
        }

        await sp2.setString('last_login_email', email);
        await sp2.setString('last_login_uid', workspaceUid);
        await sp2.setString('last_login_role', role);
        await sp2.setBool('last_login_offline', false);
      } catch (_) {}

      if (!mounted) return;

      const boxName = 'sessionBox';
      final session = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);

      String pickWorkspaceOwnerName() {
        final candidates = <Object?>[
          userProfileData['name'],
          userProfileData['fullName'],
          userProfileData['displayName'],
          user.displayName,
          user.email,
          workspaceUid,
        ];
        for (final candidate in candidates) {
          final text = (candidate ?? '').toString().trim();
          if (text.isNotEmpty) return text;
        }
        return workspaceUid;
      }

      await session.put('loggedIn', true);
      await session.put('isOfficeClient', isOfficeClient);
      await session.put('clientNeedsInternet', isOfficeClient == true);
      await session.put('officeImpersonation', false);
      await session.put('workspaceOwnerUid', workspaceUid);
      await session.put('workspaceOwnerName', pickWorkspaceOwnerName());

      await OfficeClientGuard.refreshFromLocal();
      _traceWorkspace(
          'login-phase ready-to-route-ms=${loginSw.elapsedMilliseconds}');

      widget.onLoginSuccess?.call();
      unawaited(ActivityLogService.instance.logAuth(
        actionType: 'login',
        description: 'تم تسجيل الدخول بنجاح.',
      ));

      if (role == 'office') {
        _traceWorkspace('navigate /office workspaceUid=$workspaceUid');
        Navigator.of(context).pushReplacementNamed('/office');
      } else {
        _traceWorkspace('navigate /home workspaceUid=$workspaceUid');
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        await _showLoginAlert(
          title: 'يجب الاتصال بالإنترنت',
          message:
              'تم إيقاف تسجيل الدخول بدون إنترنت. تحقق من الاتصال ثم أعد المحاولة.',
          showCancel: false,
        );
        return;
      }

      if (e.code == 'user-disabled') {
        await OfficeClientGuard.markOfficeBlocked(
          true,
          email: email,
        );
        _officeBlockedFlag = true;
        await _showOfficeBlockedDialog();
        await _clearBlockedLoginSession();
        if (mounted) {
          setState(() => _authError = null);
        }
      } else if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        final localState = await _localBlockedStateForInputEmail(email);
        if (localState == OfficeLocalBlockState.confirmedBlocked) {
          _traceWorkspace(
            'credential-error with confirmed local block email=$email -> show blocked dialog',
          );
          _officeBlockedFlag = true;
          await _showOfficeBlockedDialog();
          return;
        }
        await _showLoginAlert(
          showCancel: false,
          title: 'تنبيه',
          message:
              'البريد الإلكتروني أو كلمة المرور غير صحيحين. تأكد من إدخال البيانات بدقة ثم أعد المحاولة.',
        );
        if (mounted) {
          setState(() => _authError = null);
        }
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
      bool explicitOfficeClient = false;
      final hintedOfficeIds = <String>{};
      _traceWorkspace(
        'office-client-detect start uid=${u.uid} email=${(u.email ?? '').trim().toLowerCase()}',
      );

      try {
        final id = await u.getIdTokenResult();
        final c = (id.claims ?? {}).map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        if (_isExplicitOfficeClientMap(c)) explicitOfficeClient = true;
        if (_isOfficeStaffMap(c)) {
          _traceWorkspace('office-client-detect claims matched office-staff');
          return false;
        }
        final officeId =
            (c['officeId'] ?? c['office_id'] ?? '').toString().trim();
        if (officeId.isNotEmpty) hintedOfficeIds.add(officeId);
        _traceWorkspace(
          'office-client-detect claims explicit=$explicitOfficeClient officeId=$officeId',
        );
      } catch (_) {}

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get();
        final m = doc.data() ?? {};
        if (_isExplicitOfficeClientMap(m)) explicitOfficeClient = true;
        if (_isOfficeStaffMap(m)) {
          _traceWorkspace('office-client-detect user-doc matched office-staff');
          return false;
        }
        final officeId =
            (m['officeId'] ?? m['office_id'] ?? '').toString().trim();
        if (officeId.isNotEmpty) hintedOfficeIds.add(officeId);
        _traceWorkspace(
          'office-client-detect user-doc explicit=$explicitOfficeClient officeId=$officeId',
        );
      } catch (_) {}

      for (final officeId in hintedOfficeIds) {
        if (await _hasOfficeStaffRecordUnderOffice(u, officeId)) {
          _traceWorkspace(
            'office-client-detect officeId=$officeId classified-as-staff',
          );
          return false;
        }
      }

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(1)
            .get();
        if (cg.docs.isNotEmpty && !_isOfficeStaffMap(cg.docs.first.data())) {
          _traceWorkspace(
            'office-client-detect collectionGroup(uid,limit1) matched docId=${cg.docs.first.id}',
          );
          return true;
        }
      } catch (_) {}

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(5)
            .get();
        for (final d in cg.docs) {
          if (!_isOfficeStaffMap(d.data())) {
            _traceWorkspace(
              'office-client-detect collectionGroup(uid,limit5) matched docId=${d.id}',
            );
            return true;
          }
        }
      } catch (_) {}

      try {
        final email = (u.email ?? '').trim().toLowerCase();
        if (email.isEmpty) return false;

        final byDocId = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('email', isEqualTo: email)
            .limit(5)
            .get();
        for (final d in byDocId.docs) {
          if (!_isOfficeStaffMap(d.data())) {
            _traceWorkspace(
              'office-client-detect collectionGroup(email) matched docId=${d.id}',
            );
            return true;
          }
        }

        final byEmail = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('email', isEqualTo: email)
            .limit(5)
            .get();
        for (final d in byEmail.docs) {
          if (!_isOfficeStaffMap(d.data())) {
            _traceWorkspace(
              'office-client-detect collectionGroup(email-repeat) matched docId=${d.id}',
            );
            return true;
          }
        }
      } catch (_) {}

      _traceWorkspace(
        'office-client-detect fallback-explicit result=$explicitOfficeClient',
      );
      return explicitOfficeClient;
    } catch (_) {
      _traceWorkspace('office-client-detect error');
      return false;
    }
  }

  Future<bool> _isOfficeStaffUser() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return false;

      try {
        final id = await u.getIdTokenResult(true);
        final c = (id.claims ?? {}).map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        if (_isOfficeStaffMap(c)) return true;
      } catch (_) {}

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get();
        final m = doc.data() ?? {};
        if (_isOfficeStaffMap(m)) return true;
      } catch (_) {}

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(1)
            .get();
        if (cg.docs.isNotEmpty && _isOfficeStaffMap(cg.docs.first.data())) {
          return true;
        }
      } catch (_) {}

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(5)
            .get();
        for (final d in cg.docs) {
          if (_isOfficeStaffMap(d.data())) return true;
        }
      } catch (_) {}

      try {
        final email = (u.email ?? '').trim().toLowerCase();
        if (email.isNotEmpty) {
          final byDocId = await FirebaseFirestore.instance
              .collectionGroup('clients')
              .where('email', isEqualTo: email)
              .limit(5)
              .get();
          for (final d in byDocId.docs) {
            if (_isOfficeStaffMap(d.data())) return true;
          }

          final cg = await FirebaseFirestore.instance
              .collectionGroup('clients')
              .where('email', isEqualTo: email)
              .limit(5)
              .get();
          for (final d in cg.docs) {
            if (_isOfficeStaffMap(d.data())) return true;
          }
        }
      } catch (_) {}

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveParentOfficeUidForStaff() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      _traceWorkspace('resolve-start uid=${u.uid} email=${u.email ?? ''}');
      final hintedOfficeIds = <String>{};

      try {
        final id = await u.getIdTokenResult(true);
        final claims = (id.claims ?? {}).map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final officeId =
            (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
        if (officeId.isNotEmpty) {
          _traceWorkspace(
            'claims officeId=$officeId officeStaffMarker=${_isOfficeStaffMap(claims)}',
          );
          if (_isOfficeStaffMap(claims)) {
            _traceWorkspace('resolve-hit source=claims officeId=$officeId');
            return officeId;
          }
          hintedOfficeIds.add(officeId);
        }
      } catch (_) {}

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get();
        final m = doc.data() ?? {};
        final officeId =
            (m['officeId'] ?? m['office_id'] ?? '').toString().trim();
        if (officeId.isNotEmpty) {
          _traceWorkspace(
            'users-doc officeId=$officeId officeStaffMarker=${_isOfficeStaffMap(m)}',
          );
          if (_isOfficeStaffMap(m)) {
            _traceWorkspace('resolve-hit source=users-doc officeId=$officeId');
            return officeId;
          }
          hintedOfficeIds.add(officeId);
        }
      } catch (_) {}

      try {
        final sp = await SharedPreferences.getInstance();
        final saved = sp.getString('office_workspace_uid_${u.uid}')?.trim();
        if (saved != null && saved.isNotEmpty) {
          final ok = await _hasOfficeStaffRecordUnderOffice(u, saved);
          _traceWorkspace('prefs uid-key=$saved verified=$ok');
          if (ok) {
            _traceWorkspace('resolve-hit source=prefs-uid officeId=$saved');
            return saved;
          }
        }
        final email = (u.email ?? '').trim().toLowerCase();
        if (email.isNotEmpty) {
          final savedByEmail =
              sp.getString('office_workspace_email_$email')?.trim();
          if (savedByEmail != null && savedByEmail.isNotEmpty) {
            final ok = await _hasOfficeStaffRecordUnderOffice(u, savedByEmail);
            _traceWorkspace('prefs email-key=$savedByEmail verified=$ok');
            if (ok) {
              _traceWorkspace(
                'resolve-hit source=prefs-email officeId=$savedByEmail',
              );
              return savedByEmail;
            }
          }
        }
      } catch (_) {}

      for (final officeId in hintedOfficeIds) {
        final ok = await _hasOfficeStaffRecordUnderOffice(u, officeId);
        _traceWorkspace('hint officeId=$officeId verified=$ok');
        if (ok) {
          _traceWorkspace('resolve-hit source=hint officeId=$officeId');
          return officeId;
        }
      }

      String? officeUidFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final parent = d.reference.parent.parent;
        if (parent == null) return null;
        return parent.id;
      }

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(5)
            .get();
        for (final d in cg.docs) {
          if (_isOfficeStaffMap(d.data())) {
            final officeUid = officeUidFromDoc(d);
            if (officeUid != null && officeUid.isNotEmpty) {
              _traceWorkspace(
                  'resolve-hit source=cg-docId officeId=$officeUid');
              return officeUid;
            }
          }
        }
      } catch (_) {}

      try {
        final cg = await FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('uid', isEqualTo: u.uid)
            .limit(10)
            .get();
        for (final d in cg.docs) {
          if (_isOfficeStaffMap(d.data())) {
            final officeUid = officeUidFromDoc(d);
            if (officeUid != null && officeUid.isNotEmpty) {
              _traceWorkspace('resolve-hit source=cg-uid officeId=$officeUid');
              return officeUid;
            }
          }
        }
      } catch (_) {}

      try {
        final email = (u.email ?? '').trim().toLowerCase();
        if (email.isNotEmpty) {
          final byDocId = await FirebaseFirestore.instance
              .collectionGroup('clients')
              .where('email', isEqualTo: email)
              .limit(10)
              .get();
          for (final d in byDocId.docs) {
            if (_isOfficeStaffMap(d.data())) {
              final officeUid = officeUidFromDoc(d);
              if (officeUid != null && officeUid.isNotEmpty) {
                _traceWorkspace(
                  'resolve-hit source=cg-emailDocId officeId=$officeUid',
                );
                return officeUid;
              }
            }
          }

          final cg = await FirebaseFirestore.instance
              .collectionGroup('clients')
              .where('email', isEqualTo: email)
              .limit(10)
              .get();
          for (final d in cg.docs) {
            if (_isOfficeStaffMap(d.data())) {
              final officeUid = officeUidFromDoc(d);
              if (officeUid != null && officeUid.isNotEmpty) {
                _traceWorkspace(
                  'resolve-hit source=cg-emailField officeId=$officeUid',
                );
                return officeUid;
              }
            }
          }
        }
      } catch (_) {}

      _traceWorkspace('resolve-result null uid=${u.uid}');
      return null;
    } catch (_) {
      _traceWorkspace('resolve-error');
      return null;
    }
  }

  /// Decorative login background painter.
  Future<void> _initializeWorkspaceScope(String workspaceUid) async {
    scope.setFixedUid(workspaceUid);

    try {
      await SyncManager.instance.stopAll();
    } catch (_) {}

    try {
      OfflineSyncService.instance.dispose();
    } catch (_) {}

    final uc = UserCollections(workspaceUid);
    final tenantsRepo = TenantsRepo(uc);
    await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);
    await HiveService.ensureReportsBoxesOpen();
    await SyncManager.instance.startAll();
  }

  Future<bool> _tryOfflineLogin(String email, String pass) async {
    await _showLoginAlert(
      title: 'يجب الاتصال بالإنترنت',
      message:
          'تم إيقاف وضع الأوفلاين في التطبيق. يجب تسجيل الدخول والعمل عبر الإنترنت فقط.',
      showCancel: false,
    );
    if (mounted) {
      setState(() {
        _authError = null;
      });
    }
    return false;

    try {
      final normalizedEmail = OfficeClientGuard.normalizeEmail(email);
      final localState =
          await _localBlockedStateForInputEmail(normalizedEmail);
      if (localState == OfficeLocalBlockState.confirmedBlocked) {
        _traceWorkspace(
          'offline-login blocked-before-credentials email=$normalizedEmail',
        );
        _officeBlockedFlag = true;
        await _showOfficeBlockedDialog();
        if (mounted) setState(() => _authError = null);
        return false;
      }

      final sp = await SharedPreferences.getInstance();
      final rawEmailKey = email.trim();
      final savedUid = sp.getString('offline_uid_$normalizedEmail') ??
          sp.getString('offline_uid_$rawEmailKey');
      final savedRole = sp.getString('offline_role_$normalizedEmail') ??
          sp.getString('offline_role_$rawEmailKey');
      final savedPass = sp.getString('offline_pass_$normalizedEmail') ??
          sp.getString('offline_pass_$rawEmailKey');

      if (savedUid == null || savedRole == null || savedPass == null) {
        await _showLoginAlert(
          title: 'لا يمكن تسجيل الدخول بدون إنترنت',
          message:
              'هذا الحساب جديد على هذا الجهاز ولم يُحفظ محليًا بعد. يجب تسجيل الدخول أول مرة عبر الإنترنت لحفظ الحساب، وبعدها يمكنك المتابعة بدون إنترنت.',
        );
        if (mounted) setState(() => _authError = null);
        return false;
      }

      if (savedPass != pass) {
        await _showLoginAlert(
          showCancel: false,
          title: 'تنبيه',
          message:
              'البريد الإلكتروني أو كلمة المرور غير صحيحين. تأكد من إدخال البيانات بدقة ثم أعد المحاولة.',
        );
        if (mounted) setState(() => _authError = null);
        return false;
      }

      scope.setFixedUid(savedUid);

      try {
        await SyncManager.instance.stopAll();
      } catch (_) {}

      final uc = UserCollections(savedUid);
      final tenantsRepo = TenantsRepo(uc);

      try {
        OfflineSyncService.instance.dispose();
      } catch (_) {}

      await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

      await HiveService.ensureReportsBoxesOpen();

      await sp.setString('last_login_email', normalizedEmail);
      await sp.setString('last_login_uid', savedUid);
      await sp.setString('last_login_role', savedRole);
      await sp.setBool('last_login_offline', true);

      if (mounted) {
        setState(() {
          _authError = null;
        });
      }

      if (!mounted) return true;

      final savedRoleLower = savedRole.trim().toLowerCase();
      final isOfficeAccount = savedRoleLower == 'office' ||
          savedRoleLower == 'office_owner' ||
          savedRoleLower == 'office_staff';
      Navigator.of(context)
          .pushReplacementNamed(isOfficeAccount ? '/office' : '/home');

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
      setState(() => _authError = 'تعذر إرسال رابط إعادة التعيين.');
    }
  }

  Future<void> _showSupportDialog() async {
    await CustomConfirmDialog.show(
      context: context,
      title: 'الدعم الفني',
      message:
          'تواجه صعوبة في تسجيل الدخول؟\nيرجى التواصل مع فريق الدعم الفني عبر البريد التالي:\nsupport@darvoo.com',
      confirmLabel: 'حسنًا',
      showCancel: false,
      confirmColor: const Color(0xFF0F766E),
    );
    return;
    const primary = Color(0xFF0F766E);

    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                child: IgnorePointer(
                  ignoring: true,
                  child: OutlinedButton.icon(
                    onPressed: _sendResetEmail,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      'إرسال رابط إعادة تعيين كلمة المرور',
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
    const primary = Color(0xFF0F766E);
    const bgNeutral = Color(0xFFECEFF1);

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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      20.w,
                      20.h,
                      20.w,
                      20.h + bottomInset,
                    ),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
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
                border:
                    Border.all(color: Colors.red.withOpacity(0.35), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_rounded,
                      color: Colors.red.shade700, size: 20.r),
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
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'يرجى إدخال البريد الإلكتروني';
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(value)) {
                return 'صيغة البريد الإلكتروني غير صحيحة';
              }
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
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
              ),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: border,
              focusedBorder: focusedBorder,
              errorStyle: errorStyle,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
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
              Text('تذكّر البريد',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
                backgroundColor: const Color(0xFF0F766E),
                disabledBackgroundColor:
                    const Color(0xFF0F766E).withOpacity(0.5),
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
            'تسجيل الدخول مخصص لإدارة عقاراتك وعقودك.',
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

/// Decorative login background painter.
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

    while (points.length < maxPoints &&
        attempts < maxPoints * maxAttemptsPerPoint) {
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

