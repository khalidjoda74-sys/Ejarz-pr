import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One recovery draft per account. Never shares a draft with another UID.
/// Web storage is origin-bound; users must still trust the device/browser.
class ContractDraftStore {
  static const _storage = FlutterSecureStorage();
  static Future<void>? _writes;
  static Future<void> _enqueue(Future<void> Function() operation) {
    final result = (_writes ?? Future<void>.value()).then((_) => operation());
    final tail = result.catchError((Object _) {});
    _writes = tail;
    tail.then((_) {
      if (identical(_writes, tail)) _writes = null;
    });
    return result;
  }

  static String _key(String uid) => 'aqood.contract.recovery.v1.$uid';
  Future<Map<String, dynamic>?> read(String uid) async {
    await _writes;
    final value = await _storage.read(key: _key(uid));
    if (value == null) return null;
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final time = DateTime.tryParse('${data['savedAt']}');
      if (time == null || DateTime.now().difference(time).inDays > 30) {
        await clear(uid);
        return null;
      }
      return data;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(String uid, Map<String, Object?> data) {
    final encoded = jsonEncode(
        {...data, 'savedAt': DateTime.now().toUtc().toIso8601String()});
    return _enqueue(() => _storage.write(key: _key(uid), value: encoded));
  }

  Future<void> clear(String uid) =>
      _enqueue(() => _storage.delete(key: _key(uid)));
}
