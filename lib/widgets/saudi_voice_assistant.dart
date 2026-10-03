import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/assistant/contract_assistant_controller.dart';
import '../core/assistant/contract_manual_answer_observer.dart';
import '../core/assistant/voice_session_manager.dart';
import '../core/contract_calculation_engine.dart';
import '../core/theme.dart';

class SaudiVoiceAssistant extends StatefulWidget {
  final ContractAssistantController controller;

  /// An injected transport is used by widget tests; production owns its session.
  final VoiceSessionManager? voiceSession;
  const SaudiVoiceAssistant(
      {super.key, required this.controller, this.voiceSession});
  @override
  State<SaudiVoiceAssistant> createState() => _SaudiVoiceAssistantState();
}

class _SaudiVoiceAssistantState extends State<SaudiVoiceAssistant> {
  late final VoiceSessionManager _voice;
  late final ContractManualAnswerObserver _manualAnswers;
  bool _consent = false, _consentOpen = false, _wasConnected = false;
  bool _awaitingReady = true;
  String? _feedback;
  final List<String> _history = [];

  String _nextQuestion() {
    _manualAnswers.trackCurrentQuestion();
    return widget.controller.nextQuestion;
  }

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceSession ??
        VoiceSessionManager(
            onUtterance: _understand, nextQuestion: _nextQuestion);
    _manualAnswers = ContractManualAnswerObserver(
        controller: widget.controller,
        isActive: () => mounted && _voice.connected,
        onAnswer: (message) {
          _awaitingReady = false;
          _voice.instruct('تحديث مؤكد من النموذج: $message');
          if (mounted) setState(() => _feedback = message);
        });
    _voice.addListener(_voiceChanged);
    widget.controller.addListener(_changed);
    if (_voice.connected) {
      _wasConnected = true;
      _manualAnswers.start();
    }
  }

  void _voiceChanged() {
    if (_voice.connected != _wasConnected) {
      _wasConnected = _voice.connected;
      if (_wasConnected) {
        _manualAnswers.start();
      } else {
        _manualAnswers.stop();
      }
    }
  }

  void _changed() {
    if (mounted) setState(() => _feedback = null);
  }

  Future<bool> _ensureConsent() async {
    if (_consent) return true;
    final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: const Text('مساعد العقود بالذكاء الاصطناعي'),
              content: const SingleChildScrollView(
                  child: Text(
                      'خالد يساعدك في تعبئة طلب العقد خطوة بخطوة. يمكنك التحدث أو الكتابة مباشرة في الحقول.\n\n'
                      'سيتم إرسال صوتك وإجاباتك وبيانات المسودة اللازمة إلى OpenAI لمعالجتها. لا نحفظ التسجيل الصوتي في التطبيق. راجع الأسماء والهويات والمبالغ قبل اعتمادها.\n\n'
                      'لا تشارك بيانات البطاقة البنكية أو رمز التحقق. تستطيع إيقاف الجلسة وإكمال الطلب يدويًا في أي وقت.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إكمال يدويًا')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('موافق، ابدأ')),
              ],
            ));
    _consent = agreed == true;
    return _consent;
  }

  Future<Map<String, Object?>> _understand(String text) async {
    if (_awaitingReady && VoiceSessionManager.isReadyAnswer(text)) {
      _awaitingReady = false;
      if (widget.controller.next case final field?) {
        widget.controller.focus(field.path);
      }
      return {'message': 'على بركة الله، نبدأ خطوة بخطوة. ${_nextQuestion()}'};
    }
    final voiceGeneration = _voice.sessionGeneration;
    widget.controller.manualChanged();
    final contextData = widget.controller.context();
    final revision = widget.controller.revision;
    final result = await FirebaseFunctions.instance
        .httpsCallable('extractContractVoiceFields',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 55)))
        .call({
      'text': text,
      'context': {...contextData, 'recentUserAnswers': _history},
      'consent': _consent,
    });
    if (mounted) widget.controller.manualChanged();
    if (!mounted ||
        revision != widget.controller.revision ||
        (voiceGeneration != _voice.sessionGeneration)) {
      return {
        'message':
            'تم تعديل النموذج أثناء المعالجة. سأعتمد آخر بيانات أمامك. ${widget.controller.nextQuestion}'
      };
    }
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['action'] == 'confirm') {
      final pending = widget.controller.pending.firstOrNull;
      if (pending != null) widget.controller.confirm(pending.path);
      return {'message': widget.controller.nextQuestion};
    }
    _history.add(text);
    if (_history.length > 3) _history.removeAt(0);
    if (data['action'] == 'undo') {
      widget.controller.undo();
      return {
        'message':
            'تم التراجع عن آخر تعبئة من المساعد. ${widget.controller.nextQuestion}'
      };
    }
    if (data['action'] == 'review') {
      return {
        'message':
            'ستصل إلى شاشة مراجعة العقد بعد إكمال الخطوات. يمكنك مراجعة بياناتك هناك قبل الإرسال.'
      };
    }
    final updates = List<dynamic>.from(data['updates'] as List? ?? []);
    final monthly = data['monthlyRent'];
    if (monthly is String) {
      final amount = ContractCalculationEngine.money(monthly);
      if (amount != null && amount > 0) {
        updates.removeWhere(
            (item) => item is Map && item['path'] == 'financial.rentValue');
        updates.add({
          'path': 'financial.rentValue',
          'value': ContractCalculationEngine.amount(amount * 12)
        });
      }
    }
    final applied = updates.isEmpty
        ? null
        : widget.controller.apply(updates, revision, source: 'voice');
    if (applied?['applied'] == true) _awaitingReady = false;
    final message = applied?['applied'] == true
        ? 'أضفت المعلومات إلى النموذج للمراجعة. ${widget.controller.nextQuestion}'
        : (applied?['errors'] is Map && (applied!['errors'] as Map).isNotEmpty)
            ? 'تحتاج بعض القيم إلى تصحيح: ${(applied['errors'] as Map).values.join('، ')}'
            : '${data['reply'] ?? widget.controller.nextQuestion}';
    if (mounted) setState(() => _feedback = message);
    return {'message': message};
  }

  Future<void> _start() async {
    if (_consentOpen || _voice.connected || _voice.starting) return;
    _consentOpen = true;
    try {
      if (!await _ensureConsent() || !mounted) return;
      setState(() => _feedback = null);
      _awaitingReady = true;
      await _voice.start();
    } finally {
      _consentOpen = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _voice.removeListener(_voiceChanged);
    _manualAnswers.dispose();
    if (widget.voiceSession == null) _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _voice,
        builder: (context, _) {
          final connected = _voice.connected;
          final active = connected || _voice.starting;
          final input = connected && !_voice.micMuted ? _voice.inputLevel : 0.0;
          final output =
              connected && !_voice.speakerMuted ? _voice.outputLevel : 0.0;
          final status = _voice.starting
              ? 'جارٍ الاتصال بخالد…'
              : !connected
                  ? 'اضغط هنا، ولنُكمل طلبك معًا'
                  : _voice.micMuted
                      ? 'الميكروفون متوقف'
                      : input > .015
                          ? 'أسمعك الآن… تفضل بإجابتك'
                          : output > .015
                              ? 'خالد يتحدث إليك…'
                              : _voice.phase == VoiceAssistantPhase.thinking
                                  ? 'خالد يراجع إجابتك…'
                                  : 'جاري الاستماع • تحدث أو اكتب في الحقل';
          return Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                child: Material(
                  elevation: 3,
                  shadowColor: Colors.black.withValues(alpha: .1),
                  color: context.ejarzTheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('assistant-start-card'),
                    onTap: active ? null : _start,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          SaudiAssistantAvatar(
                              level: output,
                              size: 60,
                              listening: connected &&
                                  !_voice.micMuted &&
                                  output <= .015),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('مساعد العقود',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                              const SizedBox(height: 3),
                              Text(status,
                                  style: TextStyle(
                                      fontSize: 11,
                                      height: 1.5,
                                      color: context.ejarzTheme.muted)),
                            ],
                          )),
                          const SizedBox(width: 6),
                          if (_voice.starting)
                            const SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                          else if (!connected)
                            const VoiceMicrophoneIndicator(level: 0)
                          else
                            IconButton(
                              tooltip: _voice.micMuted
                                  ? 'تشغيل الميكروفون'
                                  : 'إيقاف الميكروفون',
                              onPressed: _voice.toggleMicrophone,
                              icon: VoiceMicrophoneIndicator(
                                  level: input, muted: _voice.micMuted),
                            ),
                        ]),
                        if (active)
                          Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (connected)
                                  IconButton(
                                    tooltip: _voice.speakerMuted
                                        ? 'تشغيل صوت خالد'
                                        : 'كتم صوت خالد',
                                    onPressed: _voice.toggleSpeaker,
                                    icon: Icon(_voice.speakerMuted
                                        ? Icons.volume_off
                                        : Icons.volume_up),
                                  ),
                                TextButton.icon(
                                  onPressed: () => _voice.stop(),
                                  icon: const Icon(Icons.stop_circle_outlined,
                                      size: 20),
                                  label: const Text('إنهاء الجلسة'),
                                ),
                              ]),
                        if (_voice.phase == VoiceAssistantPhase.error)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_voice.message,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        if (connected && _feedback != null)
                          Text(_feedback!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        // Keep playback mounted throughout the session.
                        if (_voice.speaker case final renderer?)
                          SizedBox(
                              width: 1,
                              height: 1,
                              child: RTCVideoView(renderer)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// The pulse uses the microphone's measured input level, not assistant output.
class VoiceMicrophoneIndicator extends StatelessWidget {
  final double level;
  final bool muted;
  const VoiceMicrophoneIndicator(
      {super.key, required this.level, this.muted = false});
  @override
  Widget build(BuildContext context) {
    final strength = muted || !level.isFinite ? 0.0 : level.clamp(0.0, 1.0);
    return AnimatedContainer(
      key: const ValueKey('assistant-microphone-level'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: .09 + .24 * strength),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: .2 + .6 * strength),
            width: 1 + 2 * strength),
        boxShadow: strength > .015
            ? [
                BoxShadow(
                    color: AppColors.primary.withValues(alpha: .2 * strength),
                    blurRadius: 5 + 7 * strength,
                    spreadRadius: 1 + 3 * strength)
              ]
            : [],
      ),
      child: Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: AppColors.primary, size: 21),
    );
  }
}

class SaudiAssistantAvatar extends StatefulWidget {
  final double level, size;
  final bool listening;
  const SaudiAssistantAvatar(
      {super.key, this.level = 0, this.size = 70, this.listening = false});
  @override
  State<SaudiAssistantAvatar> createState() => _SaudiAssistantAvatarState();
}

class _SaudiAssistantAvatarState extends State<SaudiAssistantAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _speech = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  bool _motionAllowed = false;

  double get _level => widget.level.isFinite ? widget.level.clamp(0, 1) : 0;
  bool get _speaking => _level > .015;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionAllowed = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(SaudiAssistantAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_speaking && _motionAllowed) {
      // Do not restart for each audio sample: sustained speech must keep moving.
      if (!_speech.isAnimating) _speech.repeat();
    } else {
      _speech.stop();
      _speech.value = 0;
    }
  }

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
        label: 'شخصية مساعد عقدك',
        image: true,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: ClipOval(
              key: const ValueKey('assistant-portrait-circle'),
              child: RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _speech,
                builder: (context, _) {
                  final active = _speaking && _motionAllowed;
                  final t = _speech.value * 2 * math.pi;
                  // Audio-gated articulation, not phoneme/viseme lip synchronization.
                  // Two rhythms avoid a fixed open mouth even at a constant level.
                  final pulse =
                      (.5 + .38 * math.sin(t * 9) + .18 * math.sin(t * 13 + .7))
                          .clamp(0.0, 1.0);
                  final mouth = active
                      ? Curves.easeInOut.transform(pulse) *
                          (.45 + .55 * math.sqrt(_level))
                      : 0.0;
                  return Transform.translate(
                      key: const ValueKey('assistant-head-motion'),
                      offset: Offset(
                          0,
                          widget.size * .02 +
                              (active ? -.65 * math.sin(t) : 0)),
                      child: Transform.rotate(
                          angle: active ? .009 * math.sin(t * 2) : 0,
                          child: Transform.scale(
                              scale: 1.2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFFE7F4EF),
                                    border: Border.all(
                                        color:
                                            const Color(0xFF07836E).withValues(
                                                alpha: _speaking
                                                    ? .5
                                                    : widget.listening
                                                        ? .3
                                                        : .12),
                                        width: 2)),
                                child: Stack(fit: StackFit.expand, children: [
                                  Image.asset(
                                      'assets/images/saudi_contract_assistant.png',
                                      cacheWidth: 240,
                                      fit: BoxFit.contain),
                                  // Keep the eyes, clothes and silhouette stable. Only blend
                                  // the mouth area between the matching existing portraits.
                                  ClipOval(
                                      clipper: const _AssistantMouthClipper(),
                                      child: Opacity(
                                          key:
                                              const ValueKey('assistant-mouth'),
                                          opacity: mouth,
                                          child: Image.asset(
                                              'assets/images/saudi_contract_assistant_speaking.png',
                                              cacheWidth: 240,
                                              fit: BoxFit.contain))),
                                ]),
                              ))));
                },
              ))),
        ));
  }
}

class _AssistantMouthClipper extends CustomClipper<Rect> {
  const _AssistantMouthClipper();
  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width * .408,
      size.height * .412, size.width * .574, size.height * .499);
  @override
  bool shouldReclip(_AssistantMouthClipper oldClipper) => false;
}
