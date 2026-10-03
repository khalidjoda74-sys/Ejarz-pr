import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Native secure storage is unavailable in widget tests. Reset it per test,
  // while allowing session tests to reopen controllers within the same test.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  await testMain();
}
