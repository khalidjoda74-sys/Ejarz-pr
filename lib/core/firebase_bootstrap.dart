import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  static bool initialized = false;
  static Object? error;
  static Future<void>? _initialization;

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
    if (initialized) return Future<void>.value();
    return _initialization ??= _initialize(options: options, timeout: timeout);
  }

  static Future<void> scheduleInitialization({
    required FirebaseOptions options,
    Duration delay = Duration.zero,
    Duration? timeout,
  }) {
    if (initialized) return Future<void>.value();
    return _initialization ??= Future<void>.delayed(delay).then(
      (_) => _initialize(options: options, timeout: timeout),
    );
  }

  static Future<void> get ready => _initialization ?? Future<void>.value();

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
      markReady();
    } catch (exception) {
      markFailed(exception);
      rethrow;
    }
  }
}
