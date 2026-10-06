import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/widgets/account_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(AppTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  final dialogs = <String, AccountConfirmationDialog>{
    'delete': const AccountConfirmationDialog(
        title: 'حذف الحساب نهائيًا',
        message:
            'سيُحذف حسابك وملفك الشخصي وعقودك وعقاراتك ومرفقاتك وإشعاراتك وطلبات الدعم وبيانات الدفع المرتبطة بالحساب. لا يمكن التراجع عن هذا الإجراء.',
        confirmLabel: 'حذف نهائي',
        icon: Icons.delete_forever_rounded,
        confirmationWord: 'حذف',
        destructive: true),
    'resume': const AccountConfirmationDialog(
        title: 'لديك عقد غير مكتمل',
        message: 'هل تريد متابعة المسودة المحفوظة على هذا الجهاز؟',
        confirmLabel: 'متابعة العقد',
        cancelLabel: 'عقد جديد',
        icon: Icons.edit_document),
    'conflict': const AccountConfirmationDialog(
        title: 'احتفظ بتعديلاتك',
        message:
            'توجد نسخة أحدث من هذه المسودة في حسابك. يمكنك حفظ جميع بياناتك ومرفقاتك الحالية في مسودة جديدة، ثم مراجعتها وإرسالها.',
        confirmLabel: 'حفظ تعديلاتي في مسودة جديدة',
        cancelLabel: 'متابعة المراجعة',
        icon: Icons.copy_all_rounded),
  };
  for (final dark in [false, true]) {
    for (final item in dialogs.entries) {
      testWidgets(
          '${item.key} dialog fits small ${dark ? 'dark' : 'light'} screen',
          (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(dark ? 1.2 : 1)),
                  child: child!),
              home: Scaffold(body: item.value),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final primary = find.byType(FilledButton),
            secondary = find.byType(OutlinedButton);
        expect(tester.getSize(primary).width, tester.getSize(secondary).width);
        expect(tester.getTopLeft(primary).dy,
            lessThan(tester.getTopLeft(secondary).dy));
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('output/screenshots/confirmations')
              .createSync(recursive: true);
          File('output/screenshots/confirmations/${item.key}-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        if (item.key == 'delete') {
          expect(tester.widget<FilledButton>(primary).onPressed, isNull);
          await tester.enterText(find.byType(TextField), 'حذف الآن');
          await tester.pump();
          expect(tester.widget<FilledButton>(primary).onPressed, isNull);
          await tester.enterText(find.byType(TextField), 'حذف');
          await tester.pump();
          expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
          await tester.enterText(find.byType(TextField), '');
          await tester.pump();
          expect(tester.widget<FilledButton>(primary).onPressed, isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.ensureVisible(secondary);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
        }
      });
    }
  }
}
