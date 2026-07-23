import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/wallet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account deletion requires the explicit Arabic confirmation',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const <Locale>[Locale('ar')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          home: const LegalScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deleteTile = find.text('حذف الحساب والبيانات نهائيًا');
    await tester.scrollUntilVisible(
      deleteTile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteTile);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'سيُحذف حساب التجربة الحالي وكل العقود والعقارات والمرفقات والبيانات التجريبية المرتبطة به. يمكنك بدء تجربة جديدة بعد تسجيل الدخول مرة أخرى.',
      ),
      findsOneWidget,
    );
    final deleteButtonFinder = find.widgetWithText(FilledButton, 'حذف نهائي');
    expect(deleteButtonFinder, findsOneWidget);
    expect(tester.widget<FilledButton>(deleteButtonFinder).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'حذف');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(deleteButtonFinder).onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الحساب نهائيًا'), findsNothing);
  });
}
