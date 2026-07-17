import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/contracts.dart';
import 'package:aqood_pro/screens/create_contract.dart';
import 'package:aqood_pro/screens/home.dart';
import 'package:aqood_pro/screens/wallet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sizes = <Size>[
    const Size(360, 640),
    const Size(375, 812),
    const Size(390, 844),
    const Size(412, 915),
  ];

  for (final size in sizes) {
    testWidgets('core app screens fit ${size.width}x${size.height}',
        (tester) async {
      await _pumpAtSize(
        tester,
        size,
        HomeScreen(
          onMenu: () {},
          onNotifications: () {},
          onCreate: () {},
          onContracts: () {},
          onProperties: () {},
        ),
      );

      await _pumpAtSize(
        tester,
        size,
        ContractsScreen(
          onMenu: () {},
          onNotifications: () {},
          onCreate: () {},
        ),
      );

      await _pumpAtSize(tester, size, const CreateContractScreen());

      await _pumpAtSize(
        tester,
        size,
        PropertiesScreen(onMenu: () {}, onNotifications: () {}),
      );

      await _pumpAtSize(
        tester,
        size,
        ProfileScreen(onMenu: () {}, onNotifications: () {}),
      );

      await _pumpAtSize(tester, size, const NotificationsScreen());
      await _pumpAtSize(tester, size, const SupportScreen());
      await _pumpAtSize(tester, size, const SettingsScreen());
    });
  }

  for (final status in ContractStatus.values) {
    testWidgets('contract details renders ${status.name}', (tester) async {
      await _pumpAtSize(
        tester,
        const Size(390, 844),
        ContractDetailsScreen(contract: _contract(status)),
      );
    });
  }
}

Future<void> _pumpAtSize(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = AppController()
    ..splashCompleted = true
    ..onboardingCompleted = true
    ..loggedIn = true;

  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

ContractRecord _contract(ContractStatus status) {
  return ContractRecord(
    id: 'contract-${status.name}',
    requestNumber: 'REQ-2026-${status.index.toString().padLeft(3, '0')}',
    uid: 'demo-user',
    type: status.index.isEven
        ? ContractType.residential
        : ContractType.commercial,
    role: UserRole.lessor,
    title: 'طلب عقد تجريبي',
    property: 'الرياض - حي النرجس',
    lessorName: 'محمد العتيبي',
    tenantName: 'شركة الرواد',
    date: '2026/07/04',
    status: status,
    totalFees: 398,
    customerVisibleNote:
        status == ContractStatus.rejected ? 'تم رفض الطلب للتجربة.' : '',
    missingRequirements: status == ContractStatus.missingData
        ? const <MissingRequirement>[
            MissingRequirement(
              id: 'missing-1',
              title: 'تحديث رقم وثيقة الملكية',
              description: 'يرجى مراجعة رقم الوثيقة وإعادة إرسال الطلب.',
              type: 'field',
              fieldPath: 'draftData.property.ownershipDocumentNumber',
            ),
          ]
        : const <MissingRequirement>[],
    timeline: <StatusTimelineItem>[
      StatusTimelineItem(
        title: 'تم استلام الطلب',
        subtitle: 'تم استلام الطلب وسيتم مراجعته.',
        date: '2026/07/04',
        time: '09:00',
        completed: status == ContractStatus.authenticated,
        current: status != ContractStatus.authenticated,
      ),
    ],
  );
}
