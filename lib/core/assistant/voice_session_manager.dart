import 'dart:async';
import '../runtime_config.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum VoiceAssistantPhase {
  idle,
  greeting,
  listening,
  thinking,
  speaking,
  success,
  error
}

/// Audio lives on WebRTC tracks; the data channel carries only Live events.
/// No project key, audio recording, or invented TTS fallback is shipped here.
class VoiceSessionManager extends ChangeNotifier with WidgetsBindingObserver {
  static const greeting = 'مرحبًا بك عزيزي العميل في عقدك. '
      'أنا خالد، مساعدك بالذكاء الاصطناعي. '
      'سأساعدك في تقديم طلب عقدك خطوة بخطوة، بكل سهولة ووضوح. '
      'يمكنك الإجابة بصوتك أو الكتابة مباشرة في الحقول. هل أنت جاهز لنبدأ؟';

  static bool isReadyAnswer(String text) {
    final normalized = text
        .trim()
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ.!،؟?]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll(RegExp(r'\s+'), ' ');
    return RegExp(
            r'^(نعم|ايوه|ايوا|اي|جاهز|جاهزة|جاهزين|انا جاهز|انا جاهزة|ابدا|نبدا|يلا|توكل على الله|نعم جاهز|نعم انا جاهز)$')
        .hasMatch(normalized);
  }

  final Future<Map<String, Object?>> Function(String text) onUtterance;
  final String Function() nextQuestion;
  VoiceSessionManager({required this.onUtterance, required this.nextQuestion}) {
    WidgetsBinding.instance.addObserver(this);
  }
  RTCPeerConnection? _peer;
  RTCDataChannel? _channel;
  MediaStream? _microphone;
  RTCVideoRenderer? _speaker;
  Timer? _levelTimer, _durationTimer, _silenceTimer;
  Completer<void>? _started, _closed;
  bool _disposed = false, _busy = false, _readingLevels = false;
  int _generation = 0, _sequence = 0;
  String _utterance = '';
  String? _sessionId;
  final Set<String> _handledDelegations = {};
  Future<void>? _stopping;
  int get sessionGeneration => _generation;
  VoiceAssistantPhase phase = VoiceAssistantPhase.idle;
  String message = 'أجبني وسأساعدك في تعبئة العقد';
  String caption = '';
  bool connected = false,
      starting = false,
      micMuted = false,
      speakerMuted = false;
  double inputLevel = 0, outputLevel = 0;
  RTCVideoRenderer? get speaker => _speaker;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _send(String type,
      [Map<String, Object?> payload = const {}]) async {
    final channel = _channel;
    if (channel?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      await channel!.send(RTCDataChannelMessage(jsonEncode({
        'type': type,
        'event_id': 'aqood_${++_sequence}',
        ...payload,
      })));
    } catch (_) {
      // A channel can close between the state check and the asynchronous send.
      // Transport callbacks handle reconnection; never expose an unhandled error.
    }
  }

  void instruct(String content) {
    if (!connected) return;
    _send('session.instructions.append',
        {'delegation_id': null, 'content': content});
  }

  Future<void> start() async {
    if (_stopping != null) await _stopping;
    if (starting || connected || _disposed) return;
    _utterance = '';
    _busy = false;
    _handledDelegations.clear();
    final generation = ++_generation;
    bool current() => generation == _generation && !_disposed;
    starting = true;
    phase = VoiceAssistantPhase.greeting;
    message = 'جارٍ تجهيز اتصال صوتي آمن…';
    _notify();
    try {
      final availability = await FirebaseFunctions.instance
          .httpsCallable('contractVoiceAvailability')
          .call();
      if (!current()) return;
      if (availability.data['enabled'] != true) {
        throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message:
                'المساعد لم يتم تفعيله بعد. يمكنك متابعة تعبئة العقد يدويًا.',
            details: null);
      }
      _speaker = RTCVideoRenderer();
      await _speaker!.initialize();
      if (!current()) {
        await _cleanup();
        return;
      }
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true
        },
        'video': false
      });
      if (!current()) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        return;
      }
      _microphone = stream;
      final peer = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      if (!current()) {
        await peer.close();
        return;
      }
      _peer = peer;
      peer.onTrack = (event) {
        if (current() && event.streams.isNotEmpty) {
          _speaker?.srcObject = event.streams.first;
        }
      };
      peer.onConnectionState = (state) {
        if (!current()) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          unawaited(stop());
          phase = VoiceAssistantPhase.error;
          message = 'انقطع الاتصال. بياناتك باقية؛ اضغط بدء للاتصال من جديد.';
          _notify();
        }
      };
      for (final track in stream.getAudioTracks()) {
        await peer.addTrack(track, stream);
      }
      _started = Completer<void>();
      _closed = Completer<void>();
      final channel =
          await peer.createDataChannel('oai-events', RTCDataChannelInit());
      _channel = channel;
      channel.onMessage = (msg) {
        if (!_disposed && !msg.isBinary && (current() || _stopping != null)) {
          _event(msg.text);
        }
      };
      final ice = Completer<void>();
      peer.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !ice.isCompleted) {
          ice.complete();
        }
      };
      await peer.setLocalDescription(await peer.createOffer());
      if (peer.iceGatheringState !=
          RTCIceGatheringState.RTCIceGatheringStateComplete) {
        await ice.future.timeout(const Duration(seconds: 12));
      }
      final offer = await peer.getLocalDescription();
      final result = await FirebaseFunctions.instance
          .httpsCallable('createContractVoiceSession',
              options:
                  HttpsCallableOptions(timeout: const Duration(seconds: 55)))
          .call({
        'sdp': offer?.sdp,
        'consent': true,
      });
      if (!current()) {
        final id = result.data['sessionId'];
        if (id is String) await _closeOnServer(id);
        return;
      }
      _sessionId = result.data['sessionId'] as String?;
      await peer.setRemoteDescription(
          RTCSessionDescription('${result.data['sdp']}', 'answer'));
      await _started!.future.timeout(const Duration(seconds: 20));
      if (!current()) return;
      connected = true;
      starting = false;
      micMuted = false;
      speakerMuted = false;
      phase = VoiceAssistantPhase.listening;
      final configuredGreeting=AppRuntime.text('assistantGreeting',greeting);
      message = configuredGreeting;
      instruct('ابدأ الآن بهذا الترحيب بالعربية بنبرة ودودة وواثقة: $configuredGreeting '
          'انتظر جواب الجاهزية، ولا تسأل عن بيانات العقد مع الترحيب. '
          'عند الجاهزية فوّض التطبيق أولًا ليظهر الحقل، ثم اسأل سؤاله التالي فقط: ${nextQuestion()} '
          'إذا وصل إشعار من التطبيق بإجابة مكتوبة، اقبلها وانتقل للسؤال المرفق دون طلب تكرارها صوتيًا.');
      _durationTimer =
          Timer(const Duration(minutes: 10), () => unawaited(stop()));
      _resetSilence();
      _levelTimer =
          Timer.periodic(const Duration(milliseconds: 140), (_) => _levels());
      _notify();
    } catch (error) {
      if (current()) {
        final id = _sessionId;
        _sessionId = null;
        if (id != null) await _closeOnServer(id);
        await _cleanup();
        starting = false;
        connected = false;
        phase = VoiceAssistantPhase.error;
        message = _friendly(error);
        _notify();
      }
    }
  }

  void _event(String text) {
    try {
      final event = jsonDecode(text) as Map<String, dynamic>;
      if (_stopping != null && event['type'] != 'session.closed') return;
      switch (event['type']) {
        case 'session.started':
          if (_started?.isCompleted == false) _started!.complete();
          break;
        case 'session.closed':
          if (_closed?.isCompleted == false) _closed!.complete();
          unawaited(stop());
          break;
        case 'session.input_transcript.delta':
          final delta = '${event['delta'] ?? ''}';
          _utterance += delta;
          if (_utterance.length > 6000) {
            _utterance = _utterance.substring(_utterance.length - 6000);
          }
          caption = _utterance;
          _resetSilence();
          _notify();
          break;
        case 'session.output_transcript.delta':
          caption = '${event['delta'] ?? ''}';
          _resetSilence();
          _notify();
          break;
        case 'session.delegation.created':
          final id = event['delegation']?['id'];
          if (id is String) unawaited(_delegate(id));
          break;
        case 'error':
          phase = VoiceAssistantPhase.error;
          message = 'تعذر تنفيذ الطلب الصوتي. يمكنك الكتابة أو إعادة الاتصال.';
          _notify();
          break;
      }
    } catch (_) {
      /* Ignore malformed/unknown transport events, never apply them. */
    }
  }

  Future<void> _delegate(String id) async {
    if (!_handledDelegations.add(id)) return;
    if (_busy || _utterance.trim().isEmpty) {
      _send('session.commentary.append',
          {'delegation_id': id, 'content': nextQuestion()});
      return;
    }
    _busy = true;
    final generation = _generation;
    _resetSilence();
    final currentText = _utterance;
    _utterance = '';
    phase = VoiceAssistantPhase.thinking;
    message = 'لحظة، أراجع إجابتك…';
    _notify();
    try {
      final result = await onUtterance(currentText);
      if (!connected || _disposed || generation != _generation) return;
      final spoken = '${result['message'] ?? nextQuestion()}';
      _send('session.commentary.append', {
        'delegation_id': id,
        'content': spoken.substring(0, math.min(spoken.length, 900))
      });
      message = spoken;
      phase = VoiceAssistantPhase.success;
    } catch (error) {
      if (!connected || _disposed || generation != _generation) return;
      message = _friendly(error);
      phase = VoiceAssistantPhase.error;
      _send('session.commentary.append',
          {'delegation_id': id, 'content': message});
    } finally {
      if (generation == _generation) _busy = false;
      if (connected && generation == _generation) _resetSilence();
      _notify();
    }
  }

  Future<void> _levels() async {
    if (_readingLevels || !connected || _disposed) return;
    _readingLevels = true;
    final generation = _generation;
    try {
      final stats = await _peer?.getStats() ?? [];
      if (!connected || _disposed || generation != _generation) return;
      var input = 0.0, output = 0.0;
      for (final stat in stats) {
        final level = double.tryParse('${stat.values['audioLevel'] ?? 0}') ?? 0;
        if (stat.type == 'inbound-rtp') output = math.max(output, level);
        if (stat.type == 'media-source' || stat.type == 'outbound-rtp') {
          input = math.max(input, level);
        }
      }
      inputLevel = micMuted ? 0 : (input * 5).clamp(0, 1);
      outputLevel = speakerMuted ? 0 : (output * 5).clamp(0, 1);
      if (inputLevel > .015 || output > .003 || _busy) _resetSilence();
      if (!_busy && phase != VoiceAssistantPhase.error) {
        phase = outputLevel > .015
            ? VoiceAssistantPhase.speaking
            : VoiceAssistantPhase.listening;
      }
      _notify();
    } catch (_) {
      // Never leave the avatar speaking on a stale sample after a stats failure.
      if (generation == _generation && !_disposed) {
        inputLevel = 0;
        outputLevel = 0;
        _notify();
      }
    } finally {
      _readingLevels = false;
    }
  }

  void _resetSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 90), () {
      if (_busy) {
        _resetSilence();
        return;
      }
      unawaited(stop());
      message = 'توقف المساعد لعدم النشاط. يمكنك استئنافه متى شئت.';
      _notify();
    });
  }

  void toggleMicrophone() {
    micMuted = !micMuted;
    if (micMuted) inputLevel = 0;
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !micMuted;
    }
    _send(micMuted ? 'session.input_audio.mute' : 'session.input_audio.unmute');
    _notify();
  }

  void toggleSpeaker() {
    speakerMuted = !speakerMuted;
    _speaker?.muted = speakerMuted;
    if (speakerMuted) outputLevel = 0;
    _notify();
  }

  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);

  Future<void> _stop() async {
    // Cancel processing immediately, before awaiting a transport acknowledgement.
    _generation++;
    final wasConnected = connected;
    connected = false;
    starting = false;
    _busy = false;
    inputLevel = 0;
    outputLevel = 0;
    _notify();
    final id = _sessionId;
    _sessionId = null;
    for (final track in _microphone?.getTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = false;
    }
    if (wasConnected) {
      await _send('session.close');
      try {
        await _closed?.future.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    // The server-side deadline remains a fallback when the network is lost.
    final serverClose = id == null ? Future<void>.value() : _closeOnServer(id);
    await _cleanup();
    await serverClose;
    if (phase != VoiceAssistantPhase.error) {
      phase = VoiceAssistantPhase.idle;
      message = 'توقف المساعد. بياناتك باقية في النموذج.';
    }
    _notify();
  }

  Future<void> _closeOnServer(String id) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('closeContractVoiceSession',
              options:
                  HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call({'sessionId': id});
    } catch (_) {
      // The authenticated deadline task retries closure without the client.
    }
  }

  Future<void> _cleanup() async {
    _levelTimer?.cancel();
    _durationTimer?.cancel();
    _silenceTimer?.cancel();
    final stream = _microphone;
    _microphone = null;
    for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      await _release(() => track.stop());
    }
    await _release(() async => stream?.dispose());
    final channel = _channel;
    _channel = null;
    await _release(() async => channel?.close());
    final peer = _peer;
    _peer = null;
    await _release(() async => peer?.close());
    await _release(() async => peer?.dispose());
    final renderer = _speaker;
    _speaker = null;
    await _release(() async => renderer?.dispose());
    inputLevel = 0;
    outputLevel = 0;
  }

  Future<void> _release(Future<void> Function() release) async {
    try {
      await release();
    } catch (_) {
      // Still release all other microphone/peer/renderer resources.
    }
  }

  static String _friendly(Object error) {
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      if (details is Map && details['reason'] == 'provider_billing') {
        return 'خدمة الصوت تحتاج مراجعة إعدادات الفوترة لدى مزود الخدمة. بيانات عقدك محفوظة.';
      }
      return switch (error.code) {
        'unauthenticated' => 'سجل الدخول أولًا لاستخدام المساعد.',
        'not-found' ||
        'failed-precondition' =>
          'المساعد الصوتي لم يتم تفعيله على الخادم بعد. يمكنك إكمال العقد يدويًا.',
        'resource-exhausted' =>
          'خدمة المساعد مشغولة مؤقتًا. حاول مرة أخرى بعد قليل.',
        _ => 'تعذر الاتصال بالمساعد الآن. تحقق من الإنترنت ثم حاول مجددًا.',
      };
    }
    final text = '$error'.toLowerCase();
    if (text.contains('permission') ||
        text.contains('notallowed') ||
        text.contains('denied')) {
      return 'اسمح باستخدام الميكروفون من إعدادات التطبيق أو المتصفح، أو أكمل بالكتابة.';
    }
    return 'لم يكتمل الاتصال الصوتي. بياناتك لم تتغير؛ أعد المحاولة أو أكمل يدويًا.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop());
    super.dispose();
  }
}
