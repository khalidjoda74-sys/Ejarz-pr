import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearanceStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'aqdak.appearance.dark.v1';
  static const _onboardingKey = 'aqdak.onboarding.completed.v1';
  static Future<void>? _writes;

  static Future<void> _enqueue(Future<void> Function() operation) {
    final write = (_writes ?? Future<void>.value()).then((_) => operation());
    final tail = write.catchError((Object _) {});
    _writes = tail;
    tail.then((_) {
      if (identical(_writes, tail)) _writes = null;
    });
    return write;
  }

  Future<bool> readDarkMode() async {
    await _writes;
    return await _storage.read(key: _key) == 'true';
  }

  Future<void> saveDarkMode(bool enabled) {
    return _enqueue(() => _storage.write(key: _key, value: enabled.toString()));
  }

  Future<bool> readOnboardingCompleted() async {
    await _writes;
    return await _storage.read(key: _onboardingKey) == 'true';
  }

  Future<void> completeOnboarding() {
    return _enqueue(() => _storage.write(key: _onboardingKey, value: 'true'));
  }
}
