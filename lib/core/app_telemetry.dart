import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'firebase_bootstrap.dart';
/// Only named events and navigation metadata; never field values or voice.
class AppTelemetry extends NavigatorObserver {
  static final String sessionId = DateTime.now().microsecondsSinceEpoch.toString();
  static final _random = Random.secure();
  static void record(String event, String screen, {int? step, String? flowId}) {
    if (!FirebaseBootstrap.initialized || FirebaseAuth.instance.currentUser == null) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 30)}';
    unawaited(FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('trackAppEvent').call({
      'eventId': id, 'event': event, 'screen': screen, 'sessionId': sessionId,
      if (step != null) 'step': step, if (flowId != null) 'flowId': flowId,
    }).then<void>((_) {}, onError: (Object _) {}));
  }
  void _view(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && !name.startsWith('/')) record('screen_view', name);
  }
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _view(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _view(previousRoute);
}
