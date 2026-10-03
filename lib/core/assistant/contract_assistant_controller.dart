import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../contract_calculation_engine.dart';
import '../firebase_repository.dart';
import '../models.dart';
import 'contract_field_catalog.dart';

class ContractAssistantController extends ChangeNotifier {
  final ContractDraft Function() readDraft;
  final void Function(ContractDraft, List<String>) onApply;
  final void Function(ContractFieldSpec) onFocus;
  final bool renewal;
  final Map<String, int> fieldRevisions = {};
  Map<String, Object?> _observed = {};
  final List<Map<String, Object?>> _undo = [];
  int revision = 0;
  int manualRevision = 0;
  Set<String> lastManualPaths = {};
  String? focusedPath;
  bool disposed = false;

  ContractAssistantController(
      {required this.readDraft,
      required this.onApply,
      required this.onFocus,
      this.renewal = false}) {
    _observed = snapshot;
  }
  Map<String, Object?> get snapshot => Map<String, Object?>.from(
      jsonDecode(jsonEncode(FirebaseRepository.draftToMap(readDraft())))
          as Map);

  List<ContractFieldSpec> get pending {
    final state = snapshot;
    return ContractFieldCatalog.fields
        .where((f) =>
            ContractFieldCatalog.applicable(f, state) &&
            readDraft().assistantFields[f.path]?['status'] ==
                'needsConfirmation')
        .toList();
  }

  List<ContractFieldSpec> get missing {
    final state = snapshot;
    return ContractFieldCatalog.fields
        .where((f) =>
            f.required &&
            ContractFieldCatalog.applicable(f, state) &&
            ContractFieldCatalog.validate(
                    f, readContractPath(state, f.path), state) !=
                null)
        .toList();
  }

  double get progress {
    final state = snapshot;
    final total = ContractFieldCatalog.fields
        .where((f) => f.required && ContractFieldCatalog.applicable(f, state))
        .length;
    return total == 0
        ? 1
        : ((total - missing.length - pending.where((f) => f.required).length) /
                total)
            .clamp(0, 1);
  }

  ContractFieldSpec? get next => pending.firstOrNull ?? missing.firstOrNull;
  String get nextQuestion => pending.isNotEmpty
      ? 'راجع ${pending.first.question.replaceFirst("ما ", "").replaceAll("؟", "")}: ${confirmationValue(pending.first, spoken: true)}. هل القيمة صحيحة؟'
      : next?.question ??
          'اكتملت الحقول التي يتابعها المساعد. راجع المرفقات والمتطلبات النهائية قبل الإرسال.';
  bool get canUndo => _undo.isNotEmpty;

  String confirmationValue(ContractFieldSpec field, {bool spoken = false}) {
    final value = readContractPath(snapshot, field.path);
    if (value is bool) return value ? 'نعم' : 'لا';
    final text = '$value';
    if (spoken &&
        RegExp(r'(idNumber|iban|mobile|authorizedPersonId)$')
            .hasMatch(field.path)) {
      return text.length > 4
          ? 'تنتهي بـ ${text.substring(text.length - 4)}، والقيمة كاملة أمامك'
          : 'القيمة المعروضة أمامك';
    }
    return switch (text) {
      'residential' => 'سكني',
      'commercial' => 'تجاري',
      'individual' => 'فرد',
      'company' => 'منشأة',
      _ => text,
    };
  }

  Map<String, Object?> context() {
    final state = snapshot;
    return {
      'revision': revision,
      'fields': [
        for (final f in ContractFieldCatalog.fields)
          if (ContractFieldCatalog.applicable(f, state))
            {
              'path': f.path,
              'label': f.label,
              'value': readContractPath(state, f.path),
              'choices': f.choices,
              'status': readDraft().assistantFields[f.path]?['status'],
            }
      ],
      'nextQuestion': nextQuestion,
      'annualRentMeaning':
          'financial.rentValue is always annual SAR, never the whole-contract total',
      'pendingConfirmation': pending.map((f) => f.path).toList(),
    };
  }

  void manualChanged() {
    final current = snapshot;
    final paths = <String>{};
    var changed = false;
    for (final field in ContractFieldCatalog.fields) {
      if (readContractPath(current, field.path) !=
          readContractPath(_observed, field.path)) {
        changed = true;
        paths.add(field.path);
        readDraft().assistantFields[field.path] = {
          'value': readContractPath(current, field.path),
          'source': 'manual',
          'status': ContractFieldCatalog.validate(
                      field, readContractPath(current, field.path), current) ==
                  null
              ? 'confirmed'
              : 'invalid',
          'requiresConfirmation': false,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
      }
    }
    final previousData = Map<String, Object?>.from(_observed)
      ..remove('assistantFields');
    final currentData = Map<String, Object?>.from(current)
      ..remove('assistantFields');
    changed = changed || jsonEncode(previousData) != jsonEncode(currentData);
    if (!changed) return;
    revision++;
    manualRevision++;
    lastManualPaths = paths;
    _observed = snapshot;
    _undo.clear(); // Never undo across a user's subsequent manual change.
    notifyListeners();
  }

  Map<String, Object?> apply(List<dynamic> updates, int expectedRevision,
      {String source = 'voice'}) {
    if (!disposed) manualChanged();
    if (disposed || expectedRevision != revision) {
      return {
        'applied': false,
        'reason':
            'تغيرت البيانات يدويًا. اقرأ الحالة الجديدة ولا تستبدل التعديل.',
        'nextQuestion': nextQuestion
      };
    }
    final before = snapshot;
    final data = snapshot;
    final changed = <String>[];
    final errors = <String, String>{};
    for (final update in updates.take(20)) {
      if (update is! Map) continue;
      final path = update['path'];
      final spec = ContractFieldCatalog.byPath[path];
      if (spec == null ||
          (renewal && path == 'type') ||
          path == 'property.savedPropertyId' ||
          (path == 'property.unitNumber' &&
              readDraft().property.savedPropertyId.isNotEmpty)) {
        errors['$path'] =
            'اختر العقار المحفوظ من النموذج؛ لا يمكن تعديل هذا الحقل بهذا الأمر';
        continue;
      }
      Object? value = update['value'];
      final old = readContractPath(data, spec.path);
      if (old is bool) {
        if (value == 'true') value = true;
        if (value == 'false') value = false;
        if (value is! bool) {
          errors[spec.path] = 'قيمة غير صالحة';
          continue;
        }
      } else {
        if (value is! String) {
          errors[spec.path] = 'القيمة يجب أن تكون نصًا';
          continue;
        }
        value = value.trim();
        if (RegExp(
                r'(Number|Date|mobile|iban|Value|Amount|Deposit|Fee|years|months|days|Count|area|Code)$')
            .hasMatch(spec.path)) {
          value = ContractCalculationEngine.normalizeDigits(value);
        }
      }
      if (old == value) continue;
      writeContractPath(data, spec.path, value);
      changed.add(spec.path);
    }
    // Validate against the whole proposed batch (e.g. ID type + ID number).
    for (final path in List<String>.from(changed)) {
      final error = ContractFieldCatalog.validate(
          ContractFieldCatalog.byPath[path]!,
          readContractPath(data, path),
          data);
      if (error != null) {
        errors[path] = error;
        writeContractPath(data, path, readContractPath(before, path)!);
        changed.remove(path);
      }
    }
    for (final prefix in ['lessor', 'tenant', 'representative']) {
      final idPath = '$prefix.idNumber';
      final typePath = '$prefix.idType';
      if (changed.contains(typePath) &&
          '${readContractPath(data, idPath) ?? ''}'.isNotEmpty &&
          ContractFieldCatalog.validate(ContractFieldCatalog.byPath[idPath]!,
                  readContractPath(data, idPath), data) !=
              null) {
        errors[typePath] =
            'نوع الهوية لا يتوافق مع الرقم الحالي؛ صحّح النوع والرقم معًا';
        writeContractPath(data, typePath, readContractPath(before, typePath)!);
        changed.remove(typePath);
      }
    }
    if (changed.isEmpty) {
      return {'applied': false, 'errors': errors, 'nextQuestion': nextQuestion};
    }
    final draft = FirebaseRepository.draftFromMap(data)!;
    for (final path in changed) {
      draft.assistantFields[path] = {
        'value': readContractPath(data, path), 'source': source,
        'confidence': null, // Not a model-invented confidence percentage.
        'status': 'needsConfirmation', 'requiresConfirmation': true,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      fieldRevisions[path] = (fieldRevisions[path] ?? 0) + 1;
    }
    final start = ContractCalculationEngine.date(draft.startDate);
    if (start != null) {
      final months = (int.tryParse(draft.durationYears) ?? 0) * 12 +
          (int.tryParse(draft.durationMonths) ?? 0);
      final days = int.tryParse(draft.durationDays) ?? 0;
      if (months + days > 0) {
        draft.endDate = ContractCalculationEngine.formatDate(
            ContractCalculationEngine.addMonths(start, months)
                .add(Duration(days: days - 1)));
      }
    }
    if (changed
        .any((p) => p.startsWith('duration.') || p.startsWith('financial.'))) {
      draft.rentPeriod = draft.paymentScheduleType == 'دفعة واحدة'
          ? 'دفعة واحدة'
          : draft.paymentFrequency;
      draft.regenerateInstallments();
    }
    _undo.add(before);
    if (_undo.length > 10) _undo.removeAt(0);
    revision++;
    onApply(draft, changed);
    _observed = snapshot;
    focus(changed.first);
    notifyListeners();
    return {
      'applied': true,
      'requiresUserConfirmation': true,
      'fields': changed,
      'errors': errors,
      'nextQuestion': nextQuestion
    };
  }

  void confirm(String path) {
    final metadata = readDraft().assistantFields[path];
    if (metadata == null || metadata['status'] != 'needsConfirmation') return;
    final spec = ContractFieldCatalog.byPath[path];
    if (spec == null ||
        ContractFieldCatalog.validate(
                spec, readContractPath(snapshot, path), snapshot) !=
            null) {
      return;
    }
    metadata['status'] = 'confirmed';
    metadata['requiresConfirmation'] = false;
    revision++;
    _observed = snapshot;
    onApply(readDraft(), []);
    if (next case final question?) focus(question.path);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final restored = FirebaseRepository.draftFromMap(_undo.removeLast())!;
    revision++;
    for (final f in ContractFieldCatalog.fields) {
      fieldRevisions[f.path] = (fieldRevisions[f.path] ?? 0) + 1;
    }
    onApply(restored, []);
    _observed = snapshot;
    notifyListeners();
  }

  void focus(String path) {
    final field = ContractFieldCatalog.byPath[path];
    if (field == null) return;
    focusedPath = path;
    onFocus(field);
  }

  void resetObservation() {
    revision++;
    _observed = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
