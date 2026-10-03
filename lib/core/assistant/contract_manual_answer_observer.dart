import 'dart:async';
import 'contract_assistant_controller.dart';
import 'contract_field_catalog.dart';

/// Observes the actual form, never a separate chat input. Manual answers remain
/// authoritative and do not make an extraction request or repeat sensitive data.
class ContractManualAnswerObserver {
  final ContractAssistantController controller;
  final void Function(String message) onAnswer;
  final bool Function() isActive;
  Timer? _settled;
  String? _askedPath;
  int _manualRevision = 0;
  bool _running = false;

  ContractManualAnswerObserver(
      {required this.controller,
      required this.onAnswer,
      required this.isActive}) {
    controller.addListener(_changed);
  }

  void start() {
    _running = true;
    _manualRevision = controller.manualRevision;
    trackCurrentQuestion();
  }

  void trackCurrentQuestion() {
    _settled?.cancel();
    _askedPath = controller.next?.path;
  }

  void _changed() {
    if (!_running || !isActive()) {
      stop();
      return;
    }
    if (_manualRevision == controller.manualRevision) {
      // A voice proposal, confirmation or undo establishes a new question.
      trackCurrentQuestion();
      return;
    }
    _manualRevision = controller.manualRevision;
    final path = _askedPath;
    if (path == null || !controller.lastManualPaths.contains(path)) return;
    _settled?.cancel();
    final value = readContractPath(controller.snapshot, path);
    _settled = Timer(const Duration(milliseconds: 1800), () {
      if (!_running ||
          !isActive() ||
          controller.disposed ||
          _askedPath != path) {
        return;
      }
      final state = controller.snapshot;
      final field = ContractFieldCatalog.byPath[path]!;
      if (readContractPath(state, path) != value ||
          !ContractFieldCatalog.applicable(field, state) ||
          ContractFieldCatalog.validate(field, value, state) != null ||
          controller.readDraft().assistantFields[path]?['source'] != 'manual') {
        return;
      }
      trackCurrentQuestion();
      onAnswer(
          'وصلت إجابتك المكتوبة في الحقل، شكرًا لك. ${controller.nextQuestion}');
      if (controller.next case final next?) controller.focus(next.path);
    });
  }

  void stop() {
    _running = false;
    _askedPath = null;
    _settled?.cancel();
  }

  void dispose() {
    stop();
    controller.removeListener(_changed);
  }
}
