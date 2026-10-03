import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/phone_session.dart';
import 'package:aqdak/main.dart';
import 'package:aqdak/screens/auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final returningDevice in [false, true]) {
    testWidgets(
        'startup keeps the logo until its route is ready, returning=$returningDevice',
        (tester) async {
      final controller = AppController();
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await pumpEventQueue();
      });
      controller.onboardingCompleted = returningDevice;
      controller.preferencesLoaded = false;
      controller.accountPhase = AccountPhase.loading;

      await tester.pumpWidget(AqdakApp(controller: controller));
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(controller.splashCompleted, isFalse);
      expect(find.byType(SessionStatusScreen), findsNothing);

      controller.preferencesLoaded = true;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(SessionStatusScreen), findsNothing);

      controller.accountPhase = AccountPhase.signedOut;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byType(SessionStatusScreen), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(returningDevice ? LoginScreen : OnboardingScreen),
          findsOneWidget);
      expect(find.byType(SessionStatusScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('startup connection failure leaves the logo for a retry screen',
      (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await pumpEventQueue();
    });
    controller.preferencesLoaded = true;
    controller.accountPhase = AccountPhase.loading;
    await tester.pumpWidget(AqdakApp(controller: controller));
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    controller.accountPhase = AccountPhase.error;
    controller.sessionError = 'تعذر الاتصال الآن. أعد المحاولة.';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
