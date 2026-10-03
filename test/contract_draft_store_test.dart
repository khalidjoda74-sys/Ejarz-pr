import 'package:aqdak/core/assistant/contract_draft_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('serial saves retain latest draft and separate accounts', () async {
    final store = ContractDraftStore();
    final first = store.save('a', {'value': 'old'});
    final next = store.save('a', {'value': 'new'});
    final another = store.save('b', {'value': 'other account'});
    await Future.wait([first, next, another]);
    expect((await store.read('a'))?['value'], 'new');
    expect((await store.read('b'))?['value'], 'other account');
  });
  test('clear runs after outstanding write, not before it', () async {
    final store = ContractDraftStore();
    final write = store.save('a', {'value': 'private draft'});
    final clear = store.clear('a');
    await Future.wait([write, clear]);
    expect(await store.read('a'), isNull);
  });
  test('expired recovery is not offered', () async {
    FlutterSecureStorage.setMockInitialValues({
      'aqood.contract.recovery.v1.a':
          '{"savedAt":"2000-01-01T00:00:00Z","value":"expired"}',
    });
    expect(await ContractDraftStore().read('a'), isNull);
  });
}
