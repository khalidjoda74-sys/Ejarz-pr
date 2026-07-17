import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqood_pro/main.dart';

void main() {
  testWidgets('app starts without the Flutter demo screen', (tester) async {
    await tester.pumpWidget(const AqoodProApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Flutter Demo Home Page'), findsNothing);
    expect(
        find.text('You have pushed the button this many times:'), findsNothing);
  });
}
