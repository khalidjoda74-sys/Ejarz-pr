import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:aqdak/screens/wallet_profile.dart';
import 'package:aqdak/widgets/unit_count_field.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'property editor keeps one stable iOS scroll view and a fixed save action',
    (tester) async {
      await tester.runAsync(SaudiReferenceCatalog.load);
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

      for (final label in [
        'رقم عداد الكهرباء',
        'رقم عداد المياه',
        'رقم عداد الغاز',
        'ملاحظات على الوحدة',
      ]) {
        final field = tester.widgetList<AppTextField>(find.byType(AppTextField))
            .singleWhere((field) => field.label == label);
        expect(field.required, isFalse, reason: label);
        expect(field.validator?.call(''), isNull, reason: label);
      }

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

      final kitchen = tester.widget<UnitCountField>(find.byWidgetPredicate(
          (widget) => widget is UnitCountField && widget.label == 'المطبخ'));
      expect(kitchen.value, '0');
      expect(find.byTooltip('زيادة المطبخ'), findsOneWidget);
      expect(find.byTooltip('تقليل المطبخ'), findsOneWidget);
    },
  );
}
