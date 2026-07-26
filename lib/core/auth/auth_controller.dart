import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/firebase_user_repository.dart';
import '../notifications/notification_service.dart';
import 'auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController._();

  static final AuthController instance = AuthController._();

  final AuthService _service = AuthService.instance;
  final FirebaseUserRepository _userRepository =
      FirebaseUserRepository.instance;
  StreamSubscription<User?>? _subscription;

  User? _user;
  bool _initialized = false;
  bool _busy = false;
  String? _errorMessage;
  final Set<String> _identityReadyUids = <String>{};
  final Set<String> _identityRequiredUids = <String>{};

  User? get user => _user;

  bool get isSignedIn {
    final user = _user;
    return user != null &&
        !user.isAnonymous &&
        user.providerData.isNotEmpty &&
        _hasVisibleIdentity(user);
  }

  bool get hasFirebaseSession => _user != null;

  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;

  bool isIdentityReady(String? uid) {
    return uid != null && uid.isNotEmpty && _identityReadyUids.contains(uid);
  }

  bool isIdentityRequired(String? uid) {
    return uid != null && uid.isNotEmpty && _identityRequiredUids.contains(uid);
  }

  void markIdentityRequired(String? uid) {
    if (uid == null || uid.isEmpty) return;
    _identityReadyUids.remove(uid);
    _identityRequiredUids.add(uid);
  }

  void markIdentityReady(String? uid) {
    if (uid == null || uid.isEmpty) return;
    _identityRequiredUids.remove(uid);
    _identityReadyUids.add(uid);
  }

  void clearError() {
    if (_errorMessage == null) return;

    _errorMessage = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _initialized = true;
    _user = _service.currentUser;
    final returningSession = _isKnownReturningSession(_user);
    if (returningSession) markIdentityReady(_user?.uid);
    unawaited(
      _syncFirestoreUser(
        _user,
        knownReturningUser: returningSession,
      ),
    );
    _subscription = _service.authStateChanges.listen((user) {
      _user = user;
      unawaited(_syncFirestoreUser(user));
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() {
    return _runSignIn(_service.signInWithGoogle);
  }

  Future<bool> signInAnonymously() {
    return _runSignIn(_service.signInAnonymously);
  }

  Future<bool> signInWithApple() {
    return _runSignIn(_service.signInWithApple);
  }

  Future<bool> canUseAppleSignIn() {
    return _service.canUseAppleSignIn();
  }

  Future<void> prepareAccountDeletion() {
    return _service.revokeAppleAuthorizationIfNeeded();
  }

  Future<void> finishAccountDeletion() async {
    final uid = _user?.uid;
    if (uid != null) {
      _identityReadyUids.remove(uid);
      _identityRequiredUids.remove(uid);
    }
    await _service.signOut();
    _user = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> signOut() async {
    _setBusy(true);
    final uid = _user?.uid;
    try {
      if (uid != null) {
        try {
          await NotificationService.instance.disableForSignedOutUser(uid);
        } catch (_) {}
      }
      await _service.signOut();
      if (uid != null) {
        _identityReadyUids.remove(uid);
        _identityRequiredUids.remove(uid);
      }
      _user = null;
      _errorMessage = null;
      return true;
    } catch (error) {
      if (uid != null) {
        try {
          await NotificationService.instance.enableForSignedInUser(uid);
        } catch (_) {}
      }
      _errorMessage = _friendlySignOutError(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> _runSignIn(
    Future<UserCredential> Function() signIn,
  ) async {
    _setBusy(true);
    try {
      final anonymousUidBeforeSignIn =
          _user?.isAnonymous == true ? _user?.uid : null;
      final credential = await signIn();
      _user = credential.user;
      final isNewUser = credential.additionalUserInfo?.isNewUser;
      final knownReturningUser = isKnownReturningSignIn(
        isNewUser: isNewUser,
        anonymousUidBeforeSignIn: anonymousUidBeforeSignIn,
        signedInUid: _user?.uid,
      );
      if (credential.additionalUserInfo?.isNewUser == true) {
        markIdentityRequired(_user?.uid);
      } else if (knownReturningUser) {
        markIdentityReady(_user?.uid);
      }
      unawaited(
        _syncFirestoreUser(
          _user,
          knownReturningUser: knownReturningUser,
        ),
      );
      final uid = _user?.uid;
      if (uid != null) {
        unawaited(NotificationService.instance.enableForSignedInUser(uid));
      }
      _errorMessage = null;
      return _user != null;
    } catch (error) {
      _errorMessage = _friendlyError(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @visibleForTesting
  static bool isKnownReturningSignIn({
    required bool? isNewUser,
    required String? anonymousUidBeforeSignIn,
    required String? signedInUid,
  }) {
    if (isNewUser != false || signedInUid == null || signedInUid.isEmpty) {
      return false;
    }

    return anonymousUidBeforeSignIn == null ||
        anonymousUidBeforeSignIn != signedInUid;
  }

  @visibleForTesting
  static bool hasPreviousAuthSignIn({
    required DateTime? creationTime,
    required DateTime? lastSignInTime,
  }) {
    if (creationTime == null || lastSignInTime == null) return false;
    return lastSignInTime.difference(creationTime) > const Duration(seconds: 1);
  }

  bool _isKnownReturningSession(User? user) {
    return user != null &&
        !user.isAnonymous &&
        hasPreviousAuthSignIn(
          creationTime: user.metadata.creationTime,
          lastSignInTime: user.metadata.lastSignInTime,
        );
  }

  Future<void> _syncFirestoreUser(
    User? user, {
    bool knownReturningUser = false,
  }) async {
    if (user == null) return;

    try {
      await _userRepository.ensureUserDocument(
        user,
        knownReturningUser: knownReturningUser,
      );
      await NotificationService.instance.refreshTokenSilently(user.uid);
    } catch (_) {
      // Profile and token sync run in the background. Their permission/network
      // failures should not leak into the sign-in sheet as user-facing errors.
    }
  }

  String _friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'sign-in-cancelled':
        case 'web-context-cancelled':
        case 'popup-closed-by-user':
          return 'تم إلغاء تسجيل الدخول.';
        case 'network-request-failed':
          return 'تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
        case 'account-exists-with-different-credential':
          return 'هذا البريد مرتبط بطريقة دخول أخرى.';
        case 'operation-not-allowed':
          return 'طريقة تسجيل الدخول غير مفعلة بعد في Firebase.';
        case 'admin-restricted-operation':
          return 'تسجيل الدخول المجهول غير مفعّل. سجّل دخولك للمتابعة.';
        case 'apple-sign-in-unavailable':
          return 'تسجيل الدخول عبر Apple غير متاح على هذا الجهاز.';
      }
      return error.message ?? 'تعذر تسجيل الدخول. حاول مرة أخرى.';
    }

    if (error is FirebaseException) {
      final message = (error.message ?? '').toLowerCase();
      if (error.code == 'permission-denied' ||
          message.contains('admin only') ||
          message.contains('restricted to admin')) {
        return 'هذا الإجراء يحتاج صلاحية إدارة.';
      }
      if (error.code == 'unauthenticated') {
        return 'سجّل دخولك للمتابعة.';
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
      }
    }

    return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  }

  String _friendlySignOutError(Object error) {
    if (error is FirebaseAuthException &&
        error.code == 'network-request-failed') {
      return 'تعذر الاتصال. تحقق من الإنترنت ثم حاول تسجيل الخروج مرة أخرى.';
    }
    return 'تعذر تسجيل الخروج الآن. حاول مرة أخرى.';
  }

  bool _hasVisibleIdentity(User user) {
    return (user.email?.isNotEmpty ?? false) ||
        (user.displayName?.isNotEmpty ?? false) ||
        (user.photoURL?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
