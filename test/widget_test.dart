import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/app.dart';
import 'package:majalisna/core/constants/app_strings.dart';

void main() {
  testWidgets('Majalisna app boots to splash', (tester) async {
    await tester.pumpWidget(const MajalisnaApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text(AppStrings.appName), findsOneWidget);
  });
}
