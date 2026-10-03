import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/main.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/widgets/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop navigation opens pages and survives mobile resize',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AqdakApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final controller =
        AppScope.of(tester.element(find.byType(AppWorkspace)), listen: false);
    controller.completeOnboarding();
    controller.login(name: 'عميل اختبار الويب');
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('desktop-navigation'));
    expect(sidebar, findsOneWidget);
    await tester
        .tap(find.descendant(of: sidebar, matching: find.text('عقودي')));
    await tester.pumpAndSettle();
    expect(find.text('قائمة العقود'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('desktop-create-contract')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateContractScreen), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    expect(find.byType(CreateContractScreen), findsOneWidget);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(sidebar, findsOneWidget);
    expect(find.byType(CreateContractScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(360, 640),
    const Size(820, 900),
    const Size(1366, 540)
  ]) {
    testWidgets('natural-height card layout fits $size with large Arabic text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: const TextScaler.linear(1.6)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
                body: SingleChildScrollView(
                    child: AdaptiveCardGrid(
              children: List.generate(
                  4,
                  (index) => Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'عقار $index: ${'تفاصيل عقار وعنوان وبيانات عربية طويلة ' * 12}',
                              key: ValueKey('card-$index'),
                            )),
                      )),
            ))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('card-3')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
