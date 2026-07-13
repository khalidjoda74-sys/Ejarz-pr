import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'fcm_token_service.dart';
import 'notification_router.dart';

@pragma('vm:entry-point')
Future<void> majalisnaMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    try {
      await FcmTokenService.instance.initialize();
    } catch (_) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(majalisnaMessagingBackgroundHandler);

    try {
      FirebaseMessaging.onMessage.listen(
        (message) {
          final conversationId = message.data['conversationId']?.toString();
          if (conversationId != null &&
              NotificationRouter.isConversationActive(conversationId)) {
            return;
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(
        NotificationRouter.openFromMessage,
        onError: (_) {},
      );
    } catch (_) {}

    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        await NotificationRouter.openFromMessage(initialMessage);
      }
    } catch (_) {}
  }

  Future<void> enableForSignedInUser(String uid) {
    return FcmTokenService.instance.enableForUser(uid);
  }

  Future<void> refreshTokenSilently(String uid) {
    return FcmTokenService.instance.refreshSilently(uid);
  }

  Future<void> disableForSignedOutUser(String uid) {
    return FcmTokenService.instance.disableForUser(uid);
  }
}
