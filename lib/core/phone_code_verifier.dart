import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'web_phone_auth.dart';

class PhoneCodeVerifier {
  const PhoneCodeVerifier();

  Future<void> verify(String verificationId, String code,
      {String? expectedUid, required String phone}) async {
    if (kIsWeb && expectedUid == null) {
      await WebPhoneAuth.confirm(verificationId, code);
      return;
    }
    await accept(
        PhoneAuthProvider.credential(
            verificationId: verificationId, smsCode: code),
        expectedUid: expectedUid,
        phone: phone);
  }

  Future<void> accept(PhoneAuthCredential credential,
      {String? expectedUid, required String phone}) async {
    if (expectedUid == null) {
      await FirebaseAuth.instance.signInWithCredential(credential);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != expectedUid || user.phoneNumber != phone) {
      throw StateError('تغير الحساب');
    }
    await user.reauthenticateWithCredential(credential);
    await user.getIdToken(true);
  }
}
