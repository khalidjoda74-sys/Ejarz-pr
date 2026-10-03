import 'package:firebase_auth/firebase_auth.dart';

/// The browser challenge belongs to the latest request. Never reuse an older
/// reCAPTCHA/SMS challenge after the user asks for a new code.
class WebPhoneAuth {
  static ConfirmationResult? _challenge;
  static int _generation = 0;

  static Future<String> request(String phone) async {
    final generation = ++_generation;
    _challenge = null;
    final result = await FirebaseAuth.instance.signInWithPhoneNumber(phone);
    if (generation != _generation) {
      throw FirebaseAuthException(code: 'session-expired');
    }
    _challenge = result;
    return result.verificationId;
  }

  static Future<UserCredential> confirm(String verificationId, String code) {
    final challenge = _challenge;
    if (challenge == null || challenge.verificationId != verificationId) {
      throw FirebaseAuthException(code: 'session-expired');
    }
    return challenge.confirm(code);
  }

  static void clear(String verificationId) {
    if (_challenge?.verificationId == verificationId) {
      _challenge = null;
      _generation++;
    }
  }
}
