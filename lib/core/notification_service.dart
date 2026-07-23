import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class AppNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'contracts_high_importance',
    'إشعارات العقود',
    description: 'تنبيهات حالات العقود والمدفوعات والنواقص',
    importance: Importance.high,
  );

  static void Function(Map<String, dynamic> data)? onNotificationTap;
  static bool _initialized = false;
  static Map<String, dynamic>? _pendingNotificationTap;

  static void deferNotificationTap(Map<String, dynamic> data) {
    _pendingNotificationTap = Map<String, dynamic>.from(data);
  }

  static void flushPendingNotificationTap() {
    final data = _pendingNotificationTap;
    final handler = onNotificationTap;
    if (data == null || handler == null) return;
    _pendingNotificationTap = null;
    handler(Map<String, dynamic>.from(data));
  }

  static void _dispatchNotificationTap(Map<String, dynamic> data) {
    final handler = onNotificationTap;
    if (handler == null) {
      deferNotificationTap(data);
      return;
    }
    handler(data);
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Web or platform permission errors must not block app startup.
    }

    if (!kIsWeb) {
      const initialization = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localNotifications.initialize(
        initialization,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.trim().isEmpty) return;
          try {
            final data = jsonDecode(payload);
            if (data is Map) {
              _dispatchNotificationTap(Map<String, dynamic>.from(data));
            }
          } catch (_) {}
        },
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.trim().isNotEmpty) {
        try {
          final data = jsonDecode(launchPayload);
          if (data is Map) {
            deferNotificationTap(Map<String, dynamic>.from(data));
          }
        } catch (_) {}
      }
    }

    FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _dispatchNotificationTap(_messageData(message));
    });

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) deferNotificationTap(_messageData(initial));
    } catch (_) {}
  }

  static Future<String?> currentToken() async {
    try {
      return FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static Stream<String> get tokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  static Map<String, dynamic> _messageData(RemoteMessage message) {
    final data = <String, dynamic>{...message.data};
    final contractId = data['contractId'] ?? data['actionPayload.contractId'];
    if (contractId != null) data['contractId'] = '$contractId';
    return data;
  }

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    if (kIsWeb) return;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'تنبيه';
    final body = notification?.body ?? message.data['body'] ?? '';
    final payload = jsonEncode(_messageData(message));
    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
