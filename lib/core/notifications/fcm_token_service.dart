import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/firebase_user_repository.dart';

class FcmTokenService {
  FcmTokenService._();

  static final FcmTokenService instance = FcmTokenService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseUserRepository _users = FirebaseUserRepository.instance;
  StreamSubscription<String>? _refreshSubscription;

  String? _lastToken;

  Future<void> initialize() async {
    try {
      _refreshSubscription ??= _messaging.onTokenRefresh.listen((token) async {
        _lastToken = token;
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || token.isEmpty) return;
        if (!await _users.notificationPreferenceEnabled(user.uid)) return;

        await _users.saveFcmToken(uid: user.uid, token: token);
      }, onError: (_) {});
    } catch (_) {
      return;
    }
  }

  Future<void> enableForUser(String uid) async {
    final allowed = await _requestPermissionIfNeeded();
    if (!allowed) return;

    final token = await _currentToken();
    if (token == null || token.isEmpty) return;

    _lastToken = token;
    await _users.saveFcmToken(uid: uid, token: token, enabled: true);
  }

  Future<void> refreshSilently(String uid) async {
    try {
      if (!await _users.notificationPreferenceEnabled(uid)) return;
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      final token = await _currentToken();
      if (token == null || token.isEmpty) return;

      _lastToken = token;
      await _users.saveFcmToken(uid: uid, token: token, enabled: true);
    } catch (_) {
      return;
    }
  }

  Future<void> disableForUser(String uid) async {
    final token = _lastToken ?? await _currentToken();
    if (token == null || token.isEmpty) return;

    await _users.disableFcmToken(uid: uid, token: token);
  }

  Future<String?> _currentToken() async {
    try {
      const webVapidKey = String.fromEnvironment(
        'FIREBASE_WEB_PUSH_VAPID_KEY',
      );

      if (kIsWeb && webVapidKey.isNotEmpty) {
        return _messaging.getToken(vapidKey: webVapidKey);
      }

      return _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _requestPermissionIfNeeded() async {
    try {
      final current = await _messaging.getNotificationSettings();
      if (current.authorizationStatus == AuthorizationStatus.authorized ||
          current.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }

      if (current.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }

      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }
}
