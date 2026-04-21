import 'package:darvoo/ui/contracts_screen.dart';
import 'package:darvoo/ui/invoices_screen.dart';
import 'package:darvoo/ui/maintenance_screen.dart';
import 'package:darvoo/ui/notifications_screen.dart';
import 'package:darvoo/ui/property_services_screen.dart';
import 'package:darvoo/ui/properties_screen.dart';
import 'package:darvoo/ui/reports_screen.dart';
import 'package:darvoo/ui/tenants_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/operational_uat_harness.dart';

class _VisualScenario {
  const _VisualScenario({
    required this.label,
    required this.builder,
    required this.verify,
    this.extraPumps = 8,
    this.pumpStep = const Duration(milliseconds: 150),
  });

  final String label;
  final Widget Function(OperationalVisualSeed seed) builder;
  final void Function(WidgetTester tester, OperationalVisualSeed seed) verify;
  final int extraPumps;
  final Duration pumpStep;
}

Widget _buildVisualShell(Widget home) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (_, __) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: home,
      );
    },
  );
}

Future<void> _pumpVisualScreen(
  WidgetTester tester,
  Widget screen, {
  int extraPumps = 8,
  Duration pumpStep = const Duration(milliseconds: 150),
}) async {
  await tester.pumpWidget(_buildVisualShell(screen));
  await tester.pump();
  for (var i = 0; i < extraPumps; i++) {
    if (pumpStep == Duration.zero) {
      await tester.pump();
      continue;
    }
    await tester.pump(pumpStep);
  }
}

void _expectNoFlutterExceptions(WidgetTester tester, String label) {
  final errors = <Object>[];
  Object? error = tester.takeException();
  while (error != null) {
    errors.add(error);
    error = tester.takeException();
  }
  expect(errors, isEmpty, reason: '$label threw flutter exceptions: $errors');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Visual UAT', () {
    late OperationalUatHarness harness;
    late OperationalVisualSeed seed;

    setUpAll(() async {
      harness = await OperationalUatHarness.create();
      seed = await harness.seedOwnerVisualScenario();
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    Future<void> runScenario(
      WidgetTester tester,
      _VisualScenario scenario,
    ) async {
      await _pumpVisualScreen(
        tester,
        scenario.builder(seed),
        extraPumps: scenario.extraPumps,
        pumpStep: scenario.pumpStep,
      );
      _expectNoFlutterExceptions(tester, scenario.label);
      expect(find.byType(Scaffold), findsWidgets, reason: scenario.label);
      scenario.verify(tester, seed);
    }

    testWidgets('properties screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'properties',
          builder: (_) => const PropertiesScreen(),
          verify: (tester, _) {
            expect(find.byType(PropertiesScreen), findsOneWidget);
            expect(find.text('العقارات'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('tenants screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'tenants',
          builder: (_) => const TenantsScreen(),
          verify: (tester, _) {
            expect(find.byType(TenantsScreen), findsOneWidget);
            expect(find.text('العملاء'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('contracts screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'contracts',
          builder: (_) => const ContractsScreen(),
          verify: (tester, _) {
            expect(find.byType(ContractsScreen), findsOneWidget);
            expect(find.text('العقود'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('invoices screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'invoices',
          builder: (_) => const InvoicesScreen(),
          verify: (tester, _) {
            expect(find.byType(InvoicesScreen), findsOneWidget);
            expect(find.text('السندات'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('maintenance screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'maintenance',
          builder: (_) => const MaintenanceScreen(),
          verify: (tester, _) {
            expect(find.byType(MaintenanceScreen), findsOneWidget);
            expect(find.text('الخدمات'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('reports screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'reports',
          builder: (_) => const ReportsScreen(),
          verify: (tester, _) {
            expect(find.byType(ReportsScreen), findsOneWidget);
            expect(find.text('التقارير الشاملة'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('notifications screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'notifications',
          builder: (_) => const NotificationsScreen(),
          verify: (tester, _) {
            expect(find.byType(NotificationsScreen), findsOneWidget);
            expect(find.text('التنبيهات'), findsWidgets);
          },
        ),
      );
    });

    testWidgets('property services screen renders', (WidgetTester tester) async {
      await runScenario(
        tester,
        _VisualScenario(
          label: 'property_services',
          builder: (seed) => PropertyServicesScreen(
            propertyId: seed.primaryPropertyId,
            refreshPeriodicStateOnOpen: false,
          ),
          extraPumps: 1,
          pumpStep: const Duration(milliseconds: 1),
          verify: (tester, _) {
            expect(find.byType(PropertyServicesScreen), findsOneWidget);
            expect(find.text('الخدمات الدورية'), findsWidgets);
          },
        ),
      );
    });

    testWidgets(
      'entry forms render with seeded reference data',
      (WidgetTester tester) async {
        final forms = <_VisualScenario>[
          _VisualScenario(
            label: 'add_contract_form',
            builder: (_) => const AddOrEditContractScreen(),
            verify: (tester, _) {
              expect(find.byType(AddOrEditContractScreen), findsOneWidget);
              expect(find.byType(TextFormField), findsWidgets);
            },
          ),
          _VisualScenario(
            label: 'add_maintenance_form',
            builder: (_) => const AddOrEditMaintenanceScreen(),
            verify: (tester, _) {
              expect(find.byType(AddOrEditMaintenanceScreen), findsOneWidget);
              expect(find.byType(TextFormField), findsWidgets);
            },
          ),
        ];

        for (final form in forms) {
          await _pumpVisualScreen(tester, form.builder(seed));
          _expectNoFlutterExceptions(tester, form.label);
          expect(find.byType(Scaffold), findsWidgets, reason: form.label);
          form.verify(tester, seed);
        }
      },
    );
  });
}
