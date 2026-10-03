import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/phone_session.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/main.dart';
import 'package:aqdak/screens/about_aqdak.dart';
import 'package:aqdak/screens/wallet_profile.dart';
import 'package:aqdak/widgets/account_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() => PackageInfo.setMockInitialValues(
        appName: 'عقدك',
        packageName: 'sa.aqdak.app',
        version: '1.0.1',
        buildNumber: '2',
        buildSignature: '',
      ));
  testWidgets('confirmation puts the requested action before cancel',
      (tester) async {
    var confirmed = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async {
              confirmed = await showAccountConfirmation(
                context,
                title: 'تسجيل الخروج',
                message: 'هل تريد تسجيل الخروج؟',
                confirmLabel: 'تسجيل الخروج',
                icon: Icons.logout_rounded,
              );
            },
            child: const Text('فتح التأكيد'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('فتح التأكيد'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'تسجيل الخروج');
    final cancel = find.widgetWithText(OutlinedButton, 'إلغاء');
    expect(
        tester.getTopLeft(confirm).dy, lessThan(tester.getTopLeft(cancel).dy));
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  testWidgets('dialog and About page fit a small dark screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
        child: Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () => showAccountConfirmation(
                context,
                title: 'إغلاق التطبيق',
                message: 'هل تريد إغلاق عقدك الآن؟',
                confirmLabel: 'إغلاق التطبيق',
                icon: Icons.exit_to_app_rounded,
              ),
              child: const Text('فتح التأكيد'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('فتح التأكيد'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, 'إلغاء'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const AboutAqdakScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'إغلاق'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile opens the custom About page without licenses',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ProfileScreen(onMenu: _noop, onNotifications: _noop),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('عن عقدك'), 280,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('عن عقدك'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAqdakScreen), findsOneWidget);
    expect(find.text('عقود سكنية وتجارية'), findsOneWidget);
    expect(find.text('عرض التراخيص'), findsNothing);
    expect(find.text('VIEW LICENSES'), findsNothing);
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'إغلاق'), 260,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(find.text('الإصدار 1.0.1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'إغلاق'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAqdakScreen), findsNothing);
  });

  testWidgets('logout confirmation cancels or signs out as chosen',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.loggedIn = true;
    await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ProfileScreen(onMenu: _noop, onNotifications: _noop),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final logout = find.widgetWithText(OutlinedButton, 'تسجيل الخروج');
    await tester.scrollUntilVisible(logout, 280,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(controller.loggedIn, isTrue);

    await tester.tap(logout);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(controller.loggedIn, isFalse);
  });

  testWidgets('back from home asks before closing the app', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.runAsync(() async => await pumpEventQueue());
    controller.splashCompleted = true;
    controller.onboardingCompleted = true;
    controller.preferencesLoaded = true;
    controller.accountPhase = AccountPhase.authenticated;
    controller.loggedIn = true;
    await tester.pumpWidget(AqdakApp(controller: controller));
    await tester.pumpAndSettle();

    controller.setNavigationIndex(2);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.mainNavigationIndex, 0);
    expect(find.byType(Dialog), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('إغلاق التطبيق'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(controller.loggedIn, isTrue);

    var exitRequested = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitRequested = true;
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'إغلاق التطبيق'));
    await tester.pumpAndSettle();
    expect(exitRequested, isTrue);
  });
}

void _noop() {}
