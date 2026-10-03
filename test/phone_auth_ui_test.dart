import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/phone_code_verifier.dart';
import 'package:aqdak/core/phone_session.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/main.dart';
import 'package:aqdak/screens/auth.dart';
import 'package:aqdak/widgets/auth_reference.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVerifier extends PhoneCodeVerifier {
  String code = '', error = 'invalid-verification-code';
  int calls = 0;
  Completer<void>? pending;
  VoidCallback? onVerified;
  @override
  Future<void> verify(String verificationId, String code,
      {String? expectedUid, required String phone}) async {
    calls++;
    this.code = code;
    if (pending != null) await pending!.future;
    if (error.isNotEmpty) throw FirebaseAuthException(code: error);
    onVerified?.call();
  }
}

class PendingPhoneController extends AppController {
  Completer<void> resolved = Completer<void>();
  AccountPhase destination = AccountPhase.profileRequired;
  @override
  Future<void> retryAccountSession() async {
    await resolved.future;
    accountPhase = destination;
    loggedIn = destination == AccountPhase.authenticated;
    sessionError = destination == AccountPhase.error ? 'تعذر الاتصال الآن' : '';
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    // Layout assertions must use the same Arabic glyph metrics as production.
    await (FontLoader(AppTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf')))
        .load();
    await (FontLoader('Dubai')
          ..addFont(rootBundle.load('assets/fonts/Dubai-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Dubai-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  Future<AppController> mount(WidgetTester tester, Widget screen,
      {bool dark = false, double scale = 1, GlobalKey? capture}) async {
    final c = AppController();
    c.userPhone = '+966512345678';
    addTearDown(c.dispose);
    await tester.pumpWidget(AppScope(
        controller: c,
        child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: RepaintBoundary(key: capture, child: screen))));
    await tester.pumpAndSettle();
    return c;
  }

  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(1440, 900)
  ]) {
    for (final dark in [false, true]) {
      testWidgets('auth layouts ${size.width} dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (const bool.fromEnvironment('AUTH_SCREENSHOTS')) {
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);
        }
        for (final entry in <String, Widget>{
          'phone': const LoginScreen(),
          'profile': const CompleteProfileScreen(),
          'otp': const OtpScreen(
              phone: SaudiPhoneNumber('512345678'), verificationId: 'qa')
        }.entries) {
          final key = GlobalKey();
          await mount(tester, entry.value,
              dark: dark, scale: size.width == 360 ? 1.3 : 1, capture: key);
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('AUTH_SCREENSHOTS')) {
            await tester.runAsync(() async {
              await Future.wait([
                precacheImage(
                    const AssetImage(
                        'assets/images/auth_botanical_background.png'),
                    key.currentContext!),
                precacheImage(
                    const AssetImage('assets/images/aqdak_horizontal.png'),
                    key.currentContext!),
              ]);
            });
            await tester.pumpAndSettle();
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'tmp/auth-qa/${entry.key}-${size.width.toInt()}-${dark ? 'dark' : 'light'}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final background = find.byWidgetPredicate((widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/auth_botanical_background.png');
          final backgroundRect =
              background.evaluate().isEmpty ? null : tester.getRect(background);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (backgroundRect != null) {
            expect(tester.getRect(background), backgroundRect,
                reason: 'Keyboard must not resize or zoom the background');
          }
          tester.view.resetViewInsets();
          await tester.pumpWidget(const SizedBox());
        }
        if (const bool.fromEnvironment('AUTH_SCREENSHOTS')) {
          debugDisableShadows = true;
        }
      });
    }
  }
  testWidgets(
      'phone support opens official email dialog and continue has no arrow',
      (tester) async {
    await mount(tester, const LoginScreen());
    expect(find.text('تحتاج مساعدة؟'), findsOneWidget);
    expect(find.text('تحتاج مساعدة؟ تواصل معنا'), findsNothing);
    final button =
        tester.widget<AuthReferenceButton>(find.byType(AuthReferenceButton));
    expect(button.label, 'متابعة');
    expect(button.arrow, isFalse);
    await tester.ensureVisible(find.text('تحتاج مساعدة؟'));
    await tester.tap(find.text('تحتاج مساعدة؟'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Info@aqdak.sa'), findsOneWidget);
    expect(find.text('إرسال بريد إلكتروني'), findsOneWidget);
    if (const bool.fromEnvironment('AUTH_SCREENSHOTS')) {
      final boundary = tester
          .element(find.byType(Dialog))
          .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tmp/auth-qa/help-dialog-light.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byTooltip('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets(
      'OTP accepts Arabic paste, reports errors and prevents duplicate verification',
      (tester) async {
    final verifier = FakeVerifier();
    await mount(
        tester,
        OtpScreen(
            phone: const SaudiPhoneNumber('512345678'),
            verificationId: 'qa',
            verifier: verifier));
    await tester.enterText(find.byType(TextField), '١٢٣٤٥٦');
    final confirm = find.text('تأكيد الرمز');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(verifier.code, '123456');
    expect(find.text('رمز التحقق غير صحيح'), findsOneWidget);
    verifier.error = 'session-expired';
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('انتهت صلاحية الرمز. أعد الإرسال'), findsOneWidget);
    verifier.error = 'network-request-failed';
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('تحقق من اتصال الإنترنت وحاول مرة أخرى'), findsOneWidget);
    verifier.pending = Completer<void>();
    await tester.tap(confirm);
    await tester.pump();
    final calls = verifier.calls;
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(verifier.calls, calls);
    verifier.pending!.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('new identity removes an open private route', (tester) async {
    final c = AppController();
    addTearDown(c.dispose);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    c.completeOnboarding();
    c.completeSplash();
    c.preferencesLoaded = true;
    c.accountPhase = AccountPhase.signedOut;
    await tester.pumpWidget(AqdakApp(controller: c));
    await tester.pumpAndSettle();
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('بيانات الحساب السابق')))));
    await tester.pumpAndSettle();
    expect(find.text('بيانات الحساب السابق'), findsOneWidget);
    c.beginAccountSession('new-user');
    c.accountPhase = AccountPhase.profileRequired;
    c.userPhone = '+966598765432';
    await tester.pumpAndSettle();
    expect(find.text('بيانات الحساب السابق'), findsNothing);
    expect(find.text('أكمل حسابك'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final destination in [
    AccountPhase.profileRequired,
    AccountPhase.authenticated,
    AccountPhase.error
  ]) {
    testWidgets('OTP stays visible until account resolution: $destination',
        (tester) async {
      final c = PendingPhoneController()..destination = destination;
      addTearDown(c.dispose);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      c.completeOnboarding();
      c.completeSplash();
      c.preferencesLoaded = true;
      c.accountPhase = AccountPhase.signedOut;
      final verifier = FakeVerifier()
        ..error = ''
        ..onVerified = () => c.beginAccountSession('verified-user');
      await tester.pumpWidget(AqdakApp(controller: c));
      await tester.pumpAndSettle();
      unawaited(tester.state<NavigatorState>(find.byType(Navigator).first).push(
          MaterialPageRoute<void>(
              builder: (_) => OtpScreen(
                  phone: const SaudiPhoneNumber('512345678'),
                  verificationId: 'qa',
                  verifier: verifier))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.ensureVisible(find.text('تأكيد الرمز'));
      await tester.tap(find.text('تأكيد الرمز'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.byType(SessionStatusScreen), findsNothing);
      expect(find.byType(CompleteProfileScreen), findsNothing);
      expect(c.loggedIn, isFalse);
      c.resolved.complete();
      await tester.pumpAndSettle();
      if (destination == AccountPhase.error) {
        expect(find.byType(OtpScreen), findsOneWidget);
        expect(find.text('تعذر الاتصال الآن'), findsOneWidget);
        c.resolved = Completer<void>();
        c.destination = AccountPhase.profileRequired;
        await tester.ensureVisible(find.text('إعادة المحاولة'));
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pump();
        expect(verifier.calls, 1,
            reason: 'Retry must reuse the verified session');
        c.resolved.complete();
        await tester.pumpAndSettle();
      }
      expect(find.byType(OtpScreen), findsNothing);
      expect(find.byType(SessionStatusScreen), findsNothing);
      expect(
          find.byType(CompleteProfileScreen),
          destination == AccountPhase.authenticated
              ? findsNothing
              : findsOneWidget);
      expect(c.loggedIn, destination == AccountPhase.authenticated);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
