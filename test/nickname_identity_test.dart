import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/core/auth/auth_controller.dart';
import 'package:majalisna/data/repositories/firebase_user_repository.dart';

void main() {
  group('nickname identity', () {
    test('normalizes equivalent Arabic nicknames to the same key', () {
      expect(
        FirebaseUserRepository.nicknameKeyFor('أحمد الهادئ'),
        FirebaseUserRepository.nicknameKeyFor('احمد الهادي'),
      );
    });

    test('rejects taken-looking empty normalized nicknames', () {
      expect(
        () => FirebaseUserRepository.cleanNicknameOrThrow('ــ'),
        throwsA(isA<NicknameValidationException>()),
      );
    });

    test('accepts clear Arabic nickname with spaces', () {
      expect(
        FirebaseUserRepository.cleanNicknameOrThrow('  صاحب   رأي  '),
        'صاحب رأي',
      );
    });

    test('cooldown message reports remaining days', () {
      final availableAt = DateTime.now().add(const Duration(days: 3));
      final error = NicknameCooldownException(availableAt);

      expect(error.message, contains('3'));
      expect(error.message, contains('يوم'));
    });

    test('recognizes a completed modern identity', () {
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'identityCompleted': true,
        }),
        isTrue,
      );
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'nicknameKey': 'legacy-owner',
        }),
        isTrue,
      );
    });

    test('recognizes a legacy nickname when completion flag is absent', () {
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'nickname': 'صاحب فرصة',
        }),
        isTrue,
      );
    });

    test('recognizes legacy username and name pair', () {
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'username': '@legacy-owner',
          'displayName': 'صاحب فرصة',
        }),
        isTrue,
      );
    });

    test('keeps an explicitly incomplete placeholder profile incomplete', () {
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'identityCompleted': false,
          'nickname': 'Google User',
          'username': '@abc123',
          'displayName': 'Google User',
          'name': 'Google User',
        }),
        isFalse,
      );
    });

    test('does not treat a provider display name as a chosen identity', () {
      expect(
        FirebaseUserRepository.hasCompletedIdentityData({
          'identityCompleted': false,
          'displayName': 'Google User',
          'name': 'Google User',
        }),
        isFalse,
      );
      expect(FirebaseUserRepository.hasCompletedIdentityData(null), isFalse);
    });
  });

  group('returning sign-in detection', () {
    test('recognizes a returning account from a signed-out session', () {
      expect(
        AuthController.isKnownReturningSignIn(
          isNewUser: false,
          anonymousUidBeforeSignIn: null,
          signedInUid: 'existing-user',
        ),
        isTrue,
      );
    });

    test('does not treat an anonymous account linked in place as returning',
        () {
      expect(
        AuthController.isKnownReturningSignIn(
          isNewUser: false,
          anonymousUidBeforeSignIn: 'anonymous-user',
          signedInUid: 'anonymous-user',
        ),
        isFalse,
      );
    });

    test('recognizes existing account selected after anonymous fallback', () {
      expect(
        AuthController.isKnownReturningSignIn(
          isNewUser: false,
          anonymousUidBeforeSignIn: 'anonymous-user',
          signedInUid: 'existing-user',
        ),
        isTrue,
      );
    });

    test('does not classify a new Firebase account as returning', () {
      expect(
        AuthController.isKnownReturningSignIn(
          isNewUser: true,
          anonymousUidBeforeSignIn: null,
          signedInUid: 'new-user',
        ),
        isFalse,
      );
    });

    test('recognizes an account with an earlier Firebase creation time', () {
      final createdAt = DateTime.utc(2025, 1, 1);

      expect(
        AuthController.hasPreviousAuthSignIn(
          creationTime: createdAt,
          lastSignInTime: createdAt.add(const Duration(days: 30)),
        ),
        isTrue,
      );
    });

    test('does not classify a freshly created Firebase account as previous',
        () {
      final createdAt = DateTime.utc(2025, 1, 1);

      expect(
        AuthController.hasPreviousAuthSignIn(
          creationTime: createdAt,
          lastSignInTime: createdAt,
        ),
        isFalse,
      );
    });
  });
}
