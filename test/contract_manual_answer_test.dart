import 'package:aqdak/core/assistant/contract_assistant_controller.dart';
import 'package:aqdak/core/assistant/contract_manual_answer_observer.dart';
import 'package:aqdak/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ContractDraft draft;
  late ContractAssistantController controller;
  late ContractManualAnswerObserver observer;
  late List<String> replies;
  late bool active;
  setUp(() {
    draft = ContractDraft();
    replies = [];
    active = true;
    controller = ContractAssistantController(
        readDraft: () => draft,
        onApply: (value, _) => draft = value,
        onFocus: (_) {});
    observer = ContractManualAnswerObserver(
        controller: controller, onAnswer: replies.add, isActive: () => active)
      ..start();
  });
  tearDown(() {
    observer.dispose();
    controller.dispose();
  });

  testWidgets('typing answer waits for stable input then advances once',
      (tester) async {
    expect(controller.next?.path, 'property.unitNumber');
    draft.property.unitNumber = '1';
    controller.manualChanged();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(replies, isEmpty);
    draft.property.unitNumber = '17';
    controller.manualChanged();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(replies, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    expect(replies, hasLength(1));
    expect(replies.single, contains(controller.nextQuestion));
    expect(controller.pending, isEmpty);
    expect(draft.assistantFields['property.unitNumber']?['source'], 'manual');
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 3));
    expect(replies, hasLength(1));
  });

  testWidgets(
      'empty answer, unrelated edits and stopped session do not advance',
      (tester) async {
    draft.property.unitNumber = '1';
    controller.manualChanged();
    draft.property.unitNumber = '';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(replies, isEmpty);
    draft.tenant.fullName = 'خالد أحمد';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(replies, isEmpty);
    draft.property.unitNumber = '10';
    controller.manualChanged();
    active = false;
    await tester.pump(const Duration(seconds: 2));
    expect(replies, isEmpty);
  });

  testWidgets('voice updates are not mistaken for manual answers',
      (tester) async {
    controller.apply([
      {'path': 'property.unitNumber', 'value': '17'}
    ], controller.revision);
    await tester.pump(const Duration(seconds: 2));
    expect(replies, isEmpty);
    // Editing a proposed value confirms the manual value and acknowledges it.
    draft.property.unitNumber = '18';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(replies, hasLength(1));
    expect(controller.pending, isEmpty);
  });

  testWidgets(
      'invalid ID is not acknowledged and sensitive value is not spoken',
      (tester) async {
    controller.apply([
      {'path': 'tenant.idNumber', 'value': '1234567890'}
    ], controller.revision);
    draft.tenant.idNumber = '2';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(replies, isEmpty);
    draft.tenant.idNumber = '1234567891';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(replies, hasLength(1));
    expect(replies.single, isNot(contains('1234567891')));
  });

  testWidgets('stop cancels pending acknowledgement and resume starts fresh',
      (tester) async {
    draft.property.unitNumber = '3';
    controller.manualChanged();
    observer.stop();
    await tester.pump(const Duration(seconds: 3));
    expect(replies, isEmpty);
    observer.start();
    await tester.pump(const Duration(seconds: 3));
    expect(replies, isEmpty);
  });
}
