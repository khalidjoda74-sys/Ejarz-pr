import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/demo_config.dart';
import 'package:aqdak/screens/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production startup has no sample customer records', () {
    expect(kEjarzDemoMode, isFalse);
    expect(kEjarzLocalDemoMode, isFalse);
    final controller = AppController();
    expect(controller.loggedIn, isFalse);
    expect(controller.contracts, isEmpty);
    expect(controller.properties, isEmpty);
    expect(controller.transactions, isEmpty);
    expect(controller.notifications, isEmpty);
    controller.dispose();
  });

  test('Saudi mobile formats resolve to the same Firebase number', () {
    for (final input in [
      '0512345678',
      '512345678',
      '+966512345678',
      '00966512345678'
    ]) {
      expect(normalizeSaudiMobile(input)?.e164, '+966512345678');
    }
    expect(normalizeSaudiMobile('0412345678'), isNull);
    expect(normalizeSaudiMobile('051234567'), isNull);
  });
}
