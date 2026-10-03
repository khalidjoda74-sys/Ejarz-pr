import 'package:cloud_functions/cloud_functions.dart';

enum AccountPhase {
  loading,
  signedOut,
  profileRequired,
  authenticated,
  blocked,
  error
}

class PhoneOtpCooldown {
  static final Map<String, DateTime> _sentUntil = {};
  static int remaining(String phone, {DateTime? now}) {
    final until = _sentUntil[phone];
    if (until == null) return 0;
    return (until.difference(now ?? DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 60);
  }

  static void sent(String phone, {DateTime? now}) {
    _sentUntil[phone] =
        (now ?? DateTime.now()).add(const Duration(seconds: 60));
  }
}

Future<Map<String, dynamic>> callPhoneSession(String name,
    [Map<String, Object?> data = const {}]) async {
  final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable(name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
      .call(data);
  return Map<String, dynamic>.from(result.data as Map);
}

String authFlowError(Object error) {
  if (error is FirebaseFunctionsException) {
    if (['invalid-argument', 'permission-denied', 'failed-precondition']
        .contains(error.code)) {
      return error.message ?? 'تعذر إكمال الطلب، تواصل مع الدعم';
    }
  }
  return 'تعذر الاتصال الآن. تحقق من الإنترنت وحاول مجددًا.';
}

String westernDigits(String value) => value.split('').map((c) {
      const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
      final a = arabic.indexOf(c), p = persian.indexOf(c);
      return a >= 0
          ? '$a'
          : p >= 0
              ? '$p'
              : c;
    }).join();

String? optionalEmailError(String? value) {
  final email = value?.trim() ?? '';
  return email.isEmpty ||
          (email.length <= 254 &&
              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email))
      ? null
      : 'أدخل بريدًا صحيحًا أو اتركه فارغًا';
}
