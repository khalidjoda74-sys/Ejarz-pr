import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/core/utils/reusable_stream.dart';

void main() {
  test('reusable value stream supports sequential subscriptions', () async {
    final stream = reusableValueStream<int>(7);

    expect(await stream.toList(), <int>[7]);
    expect(await stream.toList(), <int>[7]);
  });

  test('reusable stream creates a fresh source per listener', () async {
    var sourceCount = 0;
    final stream = reusableStream<int>(() {
      sourceCount++;
      return Stream<int>.fromIterable(<int>[1, 2]);
    });

    expect(await stream.toList(), <int>[1, 2]);
    expect(await stream.toList(), <int>[1, 2]);
    expect(sourceCount, 2);
  });
}
