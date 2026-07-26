import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../navigation/app_page_route.dart';
import '../../data/models/notification_model.dart';
import '../../features/councils/council_details_screen.dart';
import '../../features/messages/conversation_screen.dart';
import '../../features/results/result_details_screen.dart';
import '../../navigation/app_routes.dart';

class NotificationRouter {
  const NotificationRouter._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static String? activeConversationId;
  static bool _routeOpening = false;

  static bool isConversationActive(String conversationId) {
    return activeConversationId == conversationId;
  }

  static Future<void> openFromMessage(RemoteMessage message) async {
    await openData(message.data);
  }

  static Future<void> openNotification(
    NotificationModel notification, {
    BuildContext? context,
  }) async {
    await openData(
      {
        if (notification.targetRoute != null)
          'targetRoute': notification.targetRoute!,
        if (notification.councilId != null)
          'councilId': notification.councilId!,
        if (notification.commentId != null)
          'commentId': notification.commentId!,
        if (notification.conversationId != null)
          'conversationId': notification.conversationId!,
        if (notification.messageId != null)
          'messageId': notification.messageId!,
        'type': notification.type,
      },
      context: context,
    );
  }

  static Future<void> openData(
    Map<String, dynamic> data, {
    BuildContext? context,
  }) async {
    final navigator = context == null
        ? navigatorKey.currentState
        : Navigator.maybeOf(context);
    if (navigator == null) return;

    final targetRoute = data['targetRoute']?.toString();
    final councilId = data['councilId']?.toString();

    if (targetRoute != null && targetRoute.startsWith('/conversation/')) {
      final id = targetRoute.split('/').where((part) => part.isNotEmpty).last;
      await _pushOnce(
        navigator,
        (_) => ConversationScreen(conversationId: id),
      );
      return;
    }

    final conversationId = data['conversationId']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      await _pushOnce(
        navigator,
        (_) => ConversationScreen(conversationId: conversationId),
      );
      return;
    }
    if (targetRoute != null && targetRoute.startsWith('/result/')) {
      final id = targetRoute.split('/').where((part) => part.isNotEmpty).last;
      await _pushOnce(
        navigator,
        (_) => ResultDetailsScreen(councilId: id),
      );
      return;
    }

    if (targetRoute != null && targetRoute.startsWith('/council/')) {
      final id = targetRoute.split('/').where((part) => part.isNotEmpty).last;
      await _pushOnce(
        navigator,
        (_) => CouncilDetailsScreen(councilId: id),
      );
      return;
    }

    if (data['type'] == 'result_ready' && councilId != null) {
      await _pushOnce(
        navigator,
        (_) => ResultDetailsScreen(councilId: councilId),
      );
      return;
    }

    if (councilId != null && councilId.isNotEmpty) {
      await _pushOnce(
        navigator,
        (_) => CouncilDetailsScreen(councilId: councilId),
      );
      return;
    }

    if (_routeOpening) return;
    _routeOpening = true;
    try {
      await navigator.pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
    } finally {
      _routeOpening = false;
    }
  }

  static Future<void> _pushOnce(
    NavigatorState navigator,
    WidgetBuilder builder,
  ) async {
    if (_routeOpening) return;
    _routeOpening = true;
    try {
      await navigator.push(
        AppPageRoute(builder: builder),
      );
    } finally {
      _routeOpening = false;
    }
  }
}
