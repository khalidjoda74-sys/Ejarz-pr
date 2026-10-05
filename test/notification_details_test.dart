import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/wallet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = 'هذه رسالة إدارية طويلة تظهر كاملة عند فتح تفاصيل الإشعار.';

  Future<void> showNotifications(WidgetTester tester, {String initialId = ''}) async {
    final controller = AppController()
      ..splashCompleted = true
      ..onboardingCompleted = true
      ..loggedIn = true;
    controller.notifications.add(NotificationItem(
      id: 'admin-message-1',
      title: 'رسالة من الإدارة',
      body: message,
      time: 'الآن',
      actionType: 'notifications',
      icon: Icons.notifications_outlined,
      color: Colors.green,
    ));
    await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: NotificationsScreen(initialNotificationId: initialId),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a general notification opens its full message', (tester) async {
    await showNotifications(tester);
    await tester.tap(find.text('رسالة من الإدارة'));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل الإشعار'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('a push notification ID opens its message', (tester) async {
    await showNotifications(tester, initialId: 'admin-message-1');

    expect(find.text('تفاصيل الإشعار'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });
}
