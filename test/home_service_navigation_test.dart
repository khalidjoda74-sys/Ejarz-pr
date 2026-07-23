import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:aqood_pro/core/theme.dart';
import 'package:aqood_pro/screens/create_contract.dart';
import 'package:aqood_pro/screens/home.dart';
import 'package:aqood_pro/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('commercial service opens a commercial contract draft',
      (tester) async {
    final controller = AppController();
    await _pumpHome(tester, controller);

    await tester.tap(find.text(controller.serviceCommercialTitle));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('contract-type-selected-commercial')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('contract-type-selected-residential')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewal selects an issued contract and preserves its type',
      (tester) async {
    final controller = AppController();
    final sourceDraft = createContractDraftForType(ContractType.commercial)
      ..role = UserRole.authorized
      ..acceptAccuracyDeclaration = true
      ..acceptDataSharing = true
      ..acceptTerms = true;
    controller.contracts.add(
      ContractRecord(
        id: 'renewable-commercial-1',
        requestNumber: 'REQ-RENEW-1001',
        uid: 'demo-user',
        type: ContractType.commercial,
        role: UserRole.authorized,
        title: 'عقد تجاري قابل للتجديد',
        property: 'الرياض - العليا - مكتب 12',
        lessorName: 'شركة المؤجر',
        tenantName: 'شركة المستأجر',
        date: '2026/07/23',
        status: ContractStatus.authenticated,
        totalFees: 398,
        timeline: const <StatusTimelineItem>[],
        draftData: sourceDraft,
      ),
    );
    await _pumpHome(tester, controller);

    await tester.tap(find.text(controller.serviceRenewalTitle));
    await tester.pumpAndSettle();

    expect(find.text('اختر العقد المراد تجديده'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('renew-contract-renewable-commercial-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تجديد عقد'), findsOneWidget);
    expect(find.textContaining('REQ-RENEW-1001'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('contract-type-selected-commercial')),
      findsOneWidget,
    );
    final commercialCard = tester.widget<AppCard>(
      find.byKey(const ValueKey<String>('contract-type-commercial')),
    );
    expect(commercialCard.onTap, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewal shows a professional empty state', (tester) async {
    final controller = AppController();
    await _pumpHome(tester, controller);

    await tester.tap(find.text(controller.serviceRenewalTitle));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد عقود متاحة للتجديد'), findsOneWidget);
    expect(find.text('إنشاء عقد جديد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHome(WidgetTester tester, AppController controller) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            onMenu: () {},
            onNotifications: () {},
            onCreate: () {},
            onContracts: () {},
            onProperties: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
