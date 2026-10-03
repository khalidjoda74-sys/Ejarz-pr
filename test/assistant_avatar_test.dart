import 'package:aqdak/widgets/saudi_voice_assistant.dart';
import 'package:aqdak/core/assistant/voice_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget avatar(double level,
        {bool reduced = false,
        bool enabled = true,
        double size = 70,
        bool listening = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: enabled,
          child: Center(
              child: RepaintBoundary(
            key: const ValueKey('avatar-capture'),
            child: SaudiAssistantAvatar(
                level: level, size: size, listening: listening),
          )),
        ),
      ),
    );

double mouth(WidgetTester tester) => tester
    .widget<Opacity>(find.byKey(const ValueKey('assistant-mouth')))
    .opacity;

void main() {
  testWidgets('speaker mute clears output immediately', (tester) async {
    final voice = VoiceSessionManager(
        onUtterance: (_) async => {}, nextQuestion: () => '');
    voice.outputLevel = 1;
    voice.toggleSpeaker();
    expect(voice.speakerMuted, isTrue);
    expect(voice.outputLevel, 0);
    voice.toggleSpeaker();
    expect(voice.outputLevel, 0);
    await voice.stop();
    voice.dispose();
  });

  testWidgets('stop clears output before transport cleanup completes',
      (tester) async {
    final voice = VoiceSessionManager(
        onUtterance: (_) async => {}, nextQuestion: () => '');
    voice.outputLevel = 1;
    voice.connected = true;
    var notified = false;
    voice.addListener(() => notified = true);
    final closing = voice.stop();
    expect(voice.outputLevel, 0);
    expect(voice.connected, isFalse);
    expect(notified, isTrue);
    await closing;
    voice.dispose();
  });

  testWidgets('sustained speech articulates without fresh level samples',
      (tester) async {
    await tester.pumpWidget(avatar(1));
    final frames = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      frames.add(mouth(tester));
    }
    expect(frames.where((v) => v < .1), isNotEmpty);
    expect(frames.where((v) => v > .8), isNotEmpty);
    expect(frames.toSet().length, greaterThan(20));
    await tester.pumpWidget(avatar(0));
    expect(mouth(tester), 0);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('sampling does not restart motion; collapse preserves animation',
      (tester) async {
    await tester.pumpWidget(avatar(.7));
    await tester.pump(const Duration(milliseconds: 80));
    final before = mouth(tester);
    await tester.pumpWidget(avatar(.7, size: 46));
    expect(mouth(tester), closeTo(before, .0001));
    await tester.pump(const Duration(milliseconds: 80));
    expect(mouth(tester), isNot(closeTo(before, .01)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('silence and listening never animate the mouth', (tester) async {
    for (final level in [0.0, .01, -.5, double.nan, double.infinity]) {
      await tester.pumpWidget(avatar(level, listening: true));
      await tester.pumpAndSettle();
      expect(mouth(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    }
  });

  testWidgets('reduced motion and hidden ticker stop and resume safely',
      (tester) async {
    await tester.pumpWidget(avatar(1));
    await tester.pump(const Duration(milliseconds: 100));
    for (final config in [
      avatar(1, reduced: true),
      avatar(1, enabled: false),
    ]) {
      await tester.pumpWidget(config);
      await tester.pumpAndSettle();
      expect(mouth(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    }
    await tester.pumpWidget(avatar(1));
    await tester.pump(const Duration(milliseconds: 40));
    expect(mouth(tester), greaterThan(0));
    await tester.pumpWidget(avatar(0));
    expect(mouth(tester), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('portrait visual frames', (tester) async {
    if (!const bool.fromEnvironment('AVATAR_CAPTURE')) return;
    await tester.pumpWidget(avatar(0, size: 280));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(SaudiAssistantAvatar));
      await precacheImage(
          const AssetImage('assets/images/saudi_contract_assistant.png'),
          context);
      if (!context.mounted) return;
      await precacheImage(
          const AssetImage(
              'assets/images/saudi_contract_assistant_speaking.png'),
          context);
    });
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const ValueKey('avatar-capture')),
        matchesGoldenFile('../build/qa/avatar-closed.png'));
    await tester.pumpWidget(avatar(1, size: 280));
    await tester.pump(const Duration(milliseconds: 40));
    await expectLater(find.byKey(const ValueKey('avatar-capture')),
        matchesGoldenFile('../build/qa/avatar-speaking.png'));
    await tester.pump(const Duration(milliseconds: 140));
    await expectLater(find.byKey(const ValueKey('avatar-capture')),
        matchesGoldenFile('../build/qa/avatar-next.png'));
    await tester.pumpWidget(const SizedBox());
  });
}
