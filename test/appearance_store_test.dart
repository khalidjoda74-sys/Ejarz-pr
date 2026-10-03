import 'package:aqdak/core/appearance_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('dark mode survives a new store instance and rapid changes', () async {
    final store = AppearanceStore();
    expect(await store.readDarkMode(), isFalse);
    await store.saveDarkMode(true);
    expect(await AppearanceStore().readDarkMode(), isTrue);
    await Future.wait([store.saveDarkMode(false), store.saveDarkMode(true)]);
    expect(await AppearanceStore().readDarkMode(), isTrue);
  });
}
