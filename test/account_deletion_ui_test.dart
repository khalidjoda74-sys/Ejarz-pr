import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/wallet_profile.dart';
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
        'سيُحذف حسابك وملفك الشخصي وعقودك وعقاراتك ومرفقاتك وإشعاراتك وطلبات الدعم وبيانات الدفع المرتبطة بالحساب. لا يمكن التراجع عن هذا الإجراء.',
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الحساب نهائيًا'), findsNothing);
  });
}
