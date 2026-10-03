import 'dart:async';
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/appearance_store.dart';
import 'package:aqdak/core/assistant/contract_draft_store.dart';
import 'package:aqdak/core/phone_session.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('onboarding persists independently of account sign out', () async {
    final controller = AppController();
    await pumpEventQueue();
    controller.completeOnboarding();
    controller.logout();
    expect(await AppearanceStore().readOnboardingCompleted(), isTrue);
    controller.dispose();
    final reopened = AppController();
    await pumpEventQueue();
    expect(reopened.onboardingCompleted, isTrue);
    reopened.dispose();
  });
  test('switching identity clears personal data and ignores a delayed profile',
      () async {
    final controller = AppController();
    await pumpEventQueue();
    final old = Completer<Map<String, dynamic>>();
    final pending =
        controller.resolveAccountSession('first', resolver: () => old.future);
    await ContractDraftStore().save('first', {'value': 'private draft'});
    controller.userName = 'عميل أول';
    controller.userEmail = 'first@example.com';
    controller.savedParties.add({'name': 'طرف الحساب الأول'});
    controller.paymentRecords.add({'amount': 100});
    final generation = controller.accountGeneration;
    await controller.resolveAccountSession('second',
        resolver: () async =>
            {'state': 'profileRequired', 'phone': '+966598765432'});
    expect(controller.isCurrentAccount(generation), isFalse);
    expect(controller.savedParties, isEmpty);
    expect(controller.paymentRecords, isEmpty);
    expect(controller.userEmail, isEmpty);
    expect(await ContractDraftStore().read('first'), isNull);
    old.complete({
      'state': 'ready',
      'profile': {
        'uid': 'first',
        'name': 'أول',
        'phone': '+966512345678',
        'email': 'first@example.com'
      }
    });
    await pending;
    expect(controller.accountPhase, AccountPhase.profileRequired);
    expect(controller.userPhone, '+966598765432');
    expect(controller.userEmail, isEmpty);
    controller.dispose();
  });
  test('session errors never open the account', () async {
    final controller = AppController();
    await pumpEventQueue();
    await controller.resolveAccountSession('a',
        resolver: () async => throw TimeoutException('offline'));
    expect(controller.loggedIn, isFalse);
    expect(controller.accountPhase, AccountPhase.error);
    controller.dispose();
  });
  test(
      'deleted remote identity clears the cached session and returns to phone entry',
      () async {
    final controller = AppController();
    await pumpEventQueue();
    var signedOut = false;
    await controller.resolveAccountSession('removed',
        resolver: () => throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'انتهت الجلسة',
            details: const {'reason': 'account-removed'}),
        onRemoved: () async {
          signedOut = true;
        });
    expect(signedOut, isTrue);
    expect(controller.accountPhase, AccountPhase.signedOut);
    expect(controller.loggedIn, isFalse);
    controller.dispose();
  });
  test('Arabic digits and optional email are accepted', () {
    expect(westernDigits('١٢٣٤٥٦'), '123456');
    expect(westernDigits('۱۲۳۴۵۶'), '123456');
    expect(optionalEmailError(''), isNull);
    expect(optionalEmailError('customer@example.com'), isNull);
    expect(optionalEmailError('bad'), isNotNull);
  });
  test('SMS cooldown follows the phone and starts only when sent', () {
    final now = DateTime.utc(2026, 10, 2);
    expect(PhoneOtpCooldown.remaining('+966500000001', now: now), 0);
    PhoneOtpCooldown.sent('+966500000001', now: now);
    expect(
        PhoneOtpCooldown.remaining('+966500000001',
            now: now.add(const Duration(seconds: 20))),
        40);
    expect(PhoneOtpCooldown.remaining('+966500000002', now: now), 0);
    expect(
        PhoneOtpCooldown.remaining('+966500000001',
            now: now.add(const Duration(seconds: 60))),
        0);
  });
}
