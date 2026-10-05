import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/assistant/contract_assistant_controller.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/screens/create_contract.dart';
import 'package:aqdak/widgets/assistant_field_scope.dart';
import 'package:aqdak/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget shell(Widget home) => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: AppTheme.light(),
      home: home,
    );
Finder textField(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
      matching: find.byType(EditableText),
    );
String shown(WidgetTester tester, String label) =>
    tester.widget<EditableText>(textField(label).first).controller.text;

void main() {
  testWidgets(
      'document date stays visible after picker confirm and form rebuild',
      (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(AppScope(
        controller: app,
        child: shell(const CreateContractScreen(initialStep: 1))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(textField('تاريخ الوثيقة'));
    await tester.tap(textField('تاريخ الوثيقة'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final expected =
        '${picker.initialDate!.year}/${picker.initialDate!.month.toString().padLeft(2, '0')}/${picker.initialDate!.day.toString().padLeft(2, '0')}';
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    expect(shown(tester, 'تاريخ الوثيقة'), expected);
    await tester.pump(const Duration(seconds: 2));
    expect(shown(tester, 'تاريخ الوثيقة'), expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved-party replacement updates fields held by assistant anchors',
      (tester) async {
    var party = PartyData()..fullName = 'الاسم الأول';
    var draft = ContractDraft()..lessor = party;
    final assistant = ContractAssistantController(
        readDraft: () => draft, onApply: (d, _) => draft = d, onFocus: (_) {});
    addTearDown(assistant.dispose);
    final anchors = <String, GlobalKey>{};
    late StateSetter rebuild;
    await tester.pumpWidget(shell(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return Scaffold(
          body: AssistantFieldScope(
              controller: assistant,
              anchors: anchors,
              step: 2,
              party: 0,
              child: Column(key: ValueKey(identityHashCode(party)), children: [
                AppTextField(
                    label: 'الاسم الكامل',
                    hint: '',
                    initialValue: party.fullName,
                    onChanged: (v) => party.fullName = v),
              ])));
    })));
    expect(shown(tester, 'الاسم الكامل'), 'الاسم الأول');
    rebuild(() {
      party = PartyData()..fullName = 'الطرف المحفوظ';
      draft.lessor = party;
    });
    await tester.pumpAndSettle();
    expect(shown(tester, 'الاسم الكامل'), 'الطرف المحفوظ');
  });
}
