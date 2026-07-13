import 'package:flutter_test/flutter_test.dart';
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
  });
}
