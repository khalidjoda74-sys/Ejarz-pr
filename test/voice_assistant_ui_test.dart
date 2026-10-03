import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/runtime_config.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const capture = bool.fromEnvironment('ASSISTANT_CAPTURE');
  testWidgets('disabled assistant is absent from the contract form',
      (tester) async {
    AppRuntime.config = {};
    final controller = AppController()..loggedIn = true;
    await tester.pumpWidget(AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          home: const CreateContractScreen(),
        )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-start-card')), findsNothing);
    expect(find.byType(CreateContractScreen), findsOneWidget);
  });
  for (final size in [
    const Size(360, 640),
    const Size(412, 915),
    const Size(1366, 768)
  ]) {
    testWidgets('compact assistant card asks consent at $size', (tester) async {
      AppRuntime.config = {'assistantEnabled': true};
      if (capture) {
        // Flutter tests default unstyled RichText to Ahem; use the same Arabic
        // glyphs the app bundles under its Roboto fallback in production.
        await (FontLoader('Ahem')
              ..addFont(rootBundle
                  .load('assets/fonts/IBMPlexSansArabic-Regular.ttf')))
            .load();
        await (FontLoader('IBM Plex Sans Arabic')
              ..addFont(rootBundle
                  .load('assets/fonts/IBMPlexSansArabic-Regular.ttf')))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      }
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = AppController()..loggedIn = true;
      await tester.pumpWidget(AppScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: const RepaintBoundary(
                key: ValueKey('assistant-qa'), child: CreateContractScreen()),
          )));
      await tester.pumpAndSettle();
      expect(find.text('مساعد العقود'), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-portrait-circle')),
          findsOneWidget);
      if (capture) {
        await tester.runAsync(() async {
          final imageContext =
              tester.element(find.byType(CreateContractScreen));
          await precacheImage(
              const AssetImage('assets/images/saudi_contract_assistant.png'),
              imageContext);
          if (!imageContext.mounted) return;
          await precacheImage(
              const AssetImage(
                  'assets/images/saudi_contract_assistant_speaking.png'),
              imageContext);
        });
        await tester.pumpAndSettle();
      }
      expect(find.text('مساعد العقود بالذكاء الاصطناعي'), findsNothing);
      expect(find.byTooltip('توسيع المساعد'), findsNothing);
      expect(find.byTooltip('الكتابة بدل الصوت'), findsNothing);
      expect(find.text('اضغط هنا، ولنُكمل طلبك معًا'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (capture) {
        await expectLater(
            find.byKey(const ValueKey('assistant-qa')),
            matchesGoldenFile(
                '../build/qa/assistant-${size.width.toInt()}.png'));
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, 'اكتب إجابتك أو التعديل المطلوب…'),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('assistant-start-card')));
      await tester.pumpAndSettle();
      expect(find.text('مساعد العقود بالذكاء الاصطناعي'), findsOneWidget);
      await tester.tap(find.text('إكمال يدويًا'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
