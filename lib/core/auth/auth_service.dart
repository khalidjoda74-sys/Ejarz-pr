import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  static const String _iosGoogleClientId =
      '163358763366-ooooamp4lkcd1ie1b185bl0gba2tsm7b.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

  GoogleSignIn get _nativeGoogleSignIn {
    final usesAppleGoogleClientId =
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS;

    return _googleSignIn ??= GoogleSignIn(
      clientId: usesAppleGoogleClientId ? _iosGoogleClientId : null,
      scopes: const ['email', 'profile'],
    );
  }

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn {
    final user = currentUser;
    return user != null &&
        !user.isAnonymous &&
        user.providerData.isNotEmpty &&
        _hasVisibleIdentity(user);
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      final current = _auth.currentUser;
      if (current?.isAnonymous == true) {
        try {
          return await current!.linkWithPopup(provider);
        } on FirebaseAuthException catch (error) {
          if (!_credentialBelongsToExistingAccount(error)) rethrow;
        }
      }
      return _auth.signInWithPopup(provider);
    }

    final googleUser = await _nativeGoogleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'sign-in-cancelled',
        message: 'تم إلغاء تسجيل الدخول.',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _signInWithCredentialPreservingAnonymous(credential);
  }

  Future<UserCredential> signInAnonymously() {
    return _auth.signInAnonymously();
  }

  Future<UserCredential> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');

    if (kIsWeb) {
      final current = _auth.currentUser;
      if (current?.isAnonymous == true) {
        try {
          return await current!.linkWithPopup(provider);
        } on FirebaseAuthException catch (error) {
          if (!_credentialBelongsToExistingAccount(error)) rethrow;
        }
      }
      return _auth.signInWithPopup(provider);
    }

    final platform = defaultTargetPlatform;
    final nativeApplePlatform =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    if (!nativeApplePlatform || !await SignInWithApple.isAvailable()) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-unavailable',
        message: 'تسجيل الدخول عبر Apple غير متاح على هذا الجهاز.',
      );
    }

    final current = _auth.currentUser;
    if (current?.isAnonymous == true) {
      try {
        return await current!.linkWithProvider(provider);
      } on FirebaseAuthException catch (error) {
        if (!_credentialBelongsToExistingAccount(error)) rethrow;
      }
    }

    return _auth.signInWithProvider(provider);
  }

  Future<UserCredential> _signInWithCredentialPreservingAnonymous(
    AuthCredential credential,
  ) async {
    final current = _auth.currentUser;
    if (current?.isAnonymous == true) {
      try {
        return await current!.linkWithCredential(credential);
      } on FirebaseAuthException catch (error) {
        if (!_credentialBelongsToExistingAccount(error)) rethrow;
      }
    }
    return _auth.signInWithCredential(credential);
  }

  bool _credentialBelongsToExistingAccount(FirebaseAuthException error) {
    return error.code == 'credential-already-in-use' ||
        error.code == 'email-already-in-use' ||
        error.code == 'account-exists-with-different-credential';
  }

  Future<void> revokeAppleAuthorizationIfNeeded() async {
    final user = _auth.currentUser;
    final usesApple = user?.providerData.any(
          (provider) => provider.providerId == 'apple.com',
        ) ==
        true;
    if (!usesApple || kIsWeb) return;

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
    );
    final authorizationCode = appleCredential.authorizationCode.trim();
    if (authorizationCode.isEmpty) {
      throw FirebaseAuthException(
        code: 'apple-token-revocation-failed',
        message: 'تعذر إلغاء تفويض Apple قبل حذف الحساب.',
      );
    }
    await _auth.revokeTokenWithAuthorizationCode(authorizationCode);
  }

  Future<bool> canUseAppleSignIn() async {
    if (kIsWeb) return false;

    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS) {
      return false;
    }

    return SignInWithApple.isAvailable();
  }

  Future<void> signOut() async {
    // Firebase is the authoritative application session. End it first, then
    // clean up the optional Google provider session without allowing a native
    // provider error to leave the application in a stale signed-in state.
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await _nativeGoogleSignIn.signOut();
      } catch (_) {}
    }
  }

  bool _hasVisibleIdentity(User user) {
    return (user.email?.isNotEmpty ?? false) ||
        (user.displayName?.isNotEmpty ?? false) ||
        (user.photoURL?.isNotEmpty ?? false);
  }
}
