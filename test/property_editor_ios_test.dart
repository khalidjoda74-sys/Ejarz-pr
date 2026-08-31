import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/wallet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'property editor keeps one stable iOS scroll view and a fixed save action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppController()
        ..splashCompleted = true
        ..onboardingCompleted = true
        ..loggedIn = true;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: PropertiesScreen(
                onMenu: () {},
                onNotifications: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('إضافة عقار'));
      await tester.pumpAndSettle();

      expect(find.text('إضافة عقار'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('حفظ العقار'), findsOneWidget);

      final formScroll = find.byType(SingleChildScrollView);
      final scrollController =
          tester.widget<SingleChildScrollView>(formScroll).controller!;

      final saveInsideScroll = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('حفظ العقار'),
      );
      expect(saveInsideScroll, findsNothing);

      await tester.drag(formScroll, const Offset(0, -5000));
      await tester.pumpAndSettle();

      final settledOffset = scrollController.offset;
      expect(settledOffset, greaterThan(0));
      expect(
        settledOffset,
        closeTo(scrollController.position.maxScrollExtent, 1),
      );
      expect(find.text('مرافق الوحدة'), findsOneWidget);
      expect(find.text('حفظ العقار'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      expect(scrollController.offset, closeTo(settledOffset, 0.1));

      final saveRect = tester.getRect(find.text('حفظ العقار'));
      expect(saveRect.bottom, lessThanOrEqualTo(844));

      final kitchenChip = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('مطبخ'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(kitchenChip.selected, isTrue);
      final kitchenLabel = kitchenChip.label as Text;
      expect(kitchenLabel.style?.color, AppColors.primaryDark);
    },
  );
}
