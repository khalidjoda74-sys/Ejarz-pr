import 'package:aqood_pro/core/contract_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Saudi identity validation', () {
    test('national identity requires ten digits starting with 1', () {
      expect(
        validateContractIdentityNumber('1123456789', 'هوية وطنية'),
        isNull,
      );
      expect(
        validateContractIdentityNumber('2123456789', 'هوية وطنية'),
        contains('تبدأ بـ 1'),
      );
    });

    test('iqama requires ten digits starting with 2', () {
      expect(
        validateContractIdentityNumber('2123456789', 'إقامة'),
        isNull,
      );
      expect(
        validateContractIdentityNumber('1123456789', 'إقامة'),
        contains('يبدأ بـ 2'),
      );
    });
  });

  group('adult birth date validation', () {
    final today = DateTime(2026, 8, 31);

    test('accepts a person on their exact eighteenth birthday', () {
      expect(
        validateAdultBirthDate('2008/08/31', today: today),
        isNull,
      );
    });

    test('rejects a person one day younger than eighteen', () {
      expect(
        validateAdultBirthDate('2008/09/01', today: today),
        contains('18 سنة'),
      );
    });

    test('rejects invalid calendar dates', () {
      expect(
        validateAdultBirthDate('2008/02/31', today: today),
        contains('تاريخ ميلاد صحيح'),
      );
    });
  });
}
