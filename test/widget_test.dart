import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/app.dart';
import 'package:majalisna/core/constants/app_strings.dart';
import 'package:majalisna/navigation/app_routes.dart';

void main() {
  testWidgets('Majalisna app boots to onboarding', (tester) async {
    await tester.pumpWidget(
      const MajalisnaApp(initialRoute: AppRoutes.onboarding),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text(AppStrings.appName), findsOneWidget);
  });
}
