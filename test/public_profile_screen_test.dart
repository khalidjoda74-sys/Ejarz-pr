import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/data/mock/demo_profile_catalog.dart';
import 'package:majalisna/data/models/public_profile_model.dart';
import 'package:majalisna/features/profile/public_profile_screen.dart';

void main() {
  testWidgets('demo profile is explicit and messaging stays informational',
      (tester) async {
    final target = PublicProfileTarget.demo(
      seed: DemoProfileCatalog.ownerLaundry,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(target: target),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الملف العام'), findsOneWidget);
    expect(
      find.text('حساب تجريبي · شخصية توضيحية غير حقيقية'),
      findsOneWidget,
    );
    expect(find.text('فهد الزهراني'), findsWidgets);
    expect(
      find.text('مغسلة ملابس للتقبيل بكامل التجهيزات'),
      findsOneWidget,
    );

    await tester.tap(find.text('إرسال رسالة'));
    await tester.pumpAndSettle();

    expect(find.text('حساب توضيحي'), findsOneWidget);
    expect(
      find.textContaining('لا تتوفر لها مراسلة'),
      findsOneWidget,
    );
  });
}
