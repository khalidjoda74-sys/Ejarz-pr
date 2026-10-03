import 'package:aqdak/core/assistant/contract_assistant_controller.dart';
import 'package:aqdak/core/assistant/voice_session_manager.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/theme.dart';
import 'package:aqdak/widgets/saudi_voice_assistant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoice extends VoiceSessionManager {
  FakeVoice() : super(onUtterance: (_) async => {}, nextQuestion: () => '');
  int starts = 0;
  final instructions = <String>[];
  @override
  Future<void> start() async {
    starts++;
    connected = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    connected = false;
    notifyListeners();
  }

  @override
  void instruct(String content) => instructions.add(content);
  void input(double value) {
    inputLevel = value;
    notifyListeners();
  }
}

void main() {
  testWidgets('card consent, listening effect, manual answer and stop',
      (tester) async {
    var draft = ContractDraft();
    final controller = ContractAssistantController(
        readDraft: () => draft,
        onApply: (value, _) => draft = value,
        onFocus: (_) {});
    final voice = FakeVoice();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 340,
                  child: SaudiVoiceAssistant(
                      controller: controller, voiceSession: voice))),
        )));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('مراجعة العقد'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    await tester.tap(find.byType(SaudiAssistantAvatar));
    await tester.pumpAndSettle();
    expect(voice.starts, 0);
    expect(find.text('مساعد العقود بالذكاء الاصطناعي'), findsOneWidget);
    await tester.tap(find.text('موافق، ابدأ'));
    await tester.pumpAndSettle();
    expect(voice.starts, 1);
    expect(find.text('جاري الاستماع • تحدث أو اكتب في الحقل'), findsOneWidget);
    voice.input(.8);
    await tester.pumpAndSettle();
    expect(find.text('أسمعك الآن… تفضل بإجابتك'), findsOneWidget);
    final pulse = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('assistant-microphone-level')));
    expect((pulse.decoration as BoxDecoration).boxShadow, isNotEmpty);
    draft.property.unitNumber = '17';
    controller.manualChanged();
    await tester.pump(const Duration(seconds: 2));
    expect(voice.instructions.single, contains('وصلت إجابتك المكتوبة'));
    await tester.tap(find.text('إنهاء الجلسة'));
    await tester.pumpAndSettle();
    expect(voice.connected, isFalse);
    expect(find.text('اضغط هنا، ولنُكمل طلبك معًا'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // Test fake owns no platform transport or observers after disposal.
    voice.dispose();
    controller.dispose();
  });

  test('Khalid greeting identifies AI and waits for readiness', () {
    expect(VoiceSessionManager.greeting, contains('أنا خالد'));
    expect(VoiceSessionManager.greeting, contains('بالذكاء الاصطناعي'));
    expect(VoiceSessionManager.greeting, endsWith('هل أنت جاهز لنبدأ؟'));
    expect(VoiceSessionManager.isReadyAnswer('أنا جاهز.'), isTrue);
    expect(VoiceSessionManager.isReadyAnswer('نعم'), isTrue);
    expect(VoiceSessionManager.isReadyAnswer('لا، لست جاهز'), isFalse);
    expect(VoiceSessionManager.isReadyAnswer('اسمي خالد'), isFalse);
  });
}
