import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

  GoogleSignIn get _nativeGoogleSignIn {
    return _googleSignIn ??= GoogleSignIn(
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
    final provider = OAuthProvider('apple.com')
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

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = provider.credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    return _signInWithCredentialPreservingAnonymous(oauthCredential);
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
    await Future.wait([
      _auth.signOut(),
      if (!kIsWeb) _nativeGoogleSignIn.signOut(),
    ]);
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool _hasVisibleIdentity(User user) {
    return (user.email?.isNotEmpty ?? false) ||
        (user.displayName?.isNotEmpty ?? false) ||
        (user.photoURL?.isNotEmpty ?? false);
  }
}
