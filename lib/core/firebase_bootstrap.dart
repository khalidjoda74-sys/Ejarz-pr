import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'app_check_bootstrap.dart';

class FirebaseBootstrap {
  static bool initialized = false;
  static Object? error;
  static Future<void>? _initialization;
  static FirebaseOptions? _lastOptions;

  static void markReady() {
    initialized = true;
    error = null;
  }

  static void markFailed(Object exception) {
    initialized = false;
    error = exception;
  }

  static Future<void> ensureInitialized({
    required FirebaseOptions options,
    Duration? timeout,
  }) {
    _lastOptions = options;
    if (initialized) return Future<void>.value();
    return _initialization ??= _initialize(options: options, timeout: timeout);
  }

  static Future<void> scheduleInitialization({
    required FirebaseOptions options,
    Duration delay = Duration.zero,
    Duration? timeout,
  }) {
    _lastOptions = options;
    if (initialized) return Future<void>.value();
    return _initialization ??= Future<void>.delayed(delay).then(
      (_) => _initialize(options: options, timeout: timeout),
    );
  }

  static Future<void> get ready => _initialization ?? Future<void>.value();

  static Future<void> retry() async {
    if (initialized) return;
    final options = _lastOptions;
    if (options == null) throw StateError('Firebase options unavailable');
    _initialization = null;
    await ensureInitialized(
        options: options, timeout: const Duration(seconds: 12));
  }

  static Future<void> _initialize({
    required FirebaseOptions options,
    Duration? timeout,
  }) async {
    try {
      final init = Firebase.initializeApp(options: options);
      if (timeout == null) {
        await init;
      } else {
        await init.timeout(timeout);
      }
      await AppCheckBootstrap.initialize();
      // Native Firestore uses its bounded on-device cache before network updates.
      // Web keeps the in-memory cache to avoid retaining customer documents on shared PCs.
      if (!kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
            persistenceEnabled: true, cacheSizeBytes: 40 * 1024 * 1024);
      }
      markReady();
    } catch (exception) {
      markFailed(exception);
      rethrow;
    }
  }
}
