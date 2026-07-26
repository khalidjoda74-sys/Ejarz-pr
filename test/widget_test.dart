import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/app.dart';
import 'package:majalisna/core/constants/app_strings.dart';
import 'package:majalisna/navigation/app_routes.dart';

void main() {
  testWidgets('Majalisna app applies its title and Arabic locale',
      (tester) async {
    await tester.pumpWidget(
      const MajalisnaApp(initialRoute: AppRoutes.onboarding),
    );
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, AppStrings.appName);
    expect(app.locale, const Locale('ar', 'SA'));
  });
}
