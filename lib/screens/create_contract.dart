import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/runtime_config.dart';
import '../core/app_telemetry.dart';
import '../widgets/service_unavailable.dart';
import 'account_records.dart';
import 'package:flutter/material.dart';
import '../widgets/load_more_records.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_bootstrap.dart';
import '../core/firebase_repository.dart';
import '../core/assistant/contract_assistant_controller.dart';
import '../core/assistant/contract_field_catalog.dart';
import '../core/assistant/contract_draft_store.dart';
import '../widgets/assistant_field_scope.dart';
import '../widgets/saudi_voice_assistant.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/app_controller.dart';
import '../core/admin_contract_session.dart';
import '../core/admin_editor_navigation.dart';
import '../widgets/admin_contract_fee_panel.dart';
import '../core/contract_files.dart';
import '../core/demo_config.dart';
import '../core/contract_validators.dart';
import '../core/contract_calculation_engine.dart';
import '../core/contract_pricing.dart';
import '../core/draft_resume_policy.dart';
import '../core/draft_sync_policy.dart';
import '../widgets/account_confirmation_dialog.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/contract_review.dart';
import '../widgets/unit_count_field.dart';
import '../core/property_management.dart';
import '../widgets/illustrations.dart';
import '../widgets/saudi_reference_fields.dart';
import 'contracts.dart';

String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String? _requiredValue(String? value) {
  if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
  return null;
}

String? _requiredName(String? value) {
  final cleaned = value?.trim() ?? '';
  if (cleaned.isEmpty) return 'هذا الحقل مطلوب';
  if (cleaned.length < 2) return 'أدخل اسمًا صحيحًا';
  return null;
}

String? _optionalEmail(String? value) {
  final cleaned = value?.trim() ?? '';
  if (cleaned.isEmpty) return null;
  final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailPattern.hasMatch(cleaned)) return 'أدخل بريدًا إلكترونيًا صحيحًا';
  return null;
}

String? _requiredSaudiMobile(String? value) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length == 10 && digits.startsWith('05')) return null;
  if (digits.length == 9 && digits.startsWith('5')) return null;
  return 'أدخل رقم جوال سعودي صحيح يبدأ بـ 05 أو 5';
}

String? _requiredSaudiPersonId(String? value) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length == 10 &&
      (digits.startsWith('1') || digits.startsWith('2'))) {
    return null;
  }
  return 'أدخل رقم هوية أو إقامة صحيح من 10 أرقام';
}

String? _requiredCrNumber(String? value) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length == 10) return null;
  return 'رقم السجل التجاري يجب أن يكون 10 أرقام';
}

String? _requiredUnifiedNumber(String? value) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length == 10 && digits.startsWith('7')) return null;
  return 'الرقم الموحد للمنشأة يجب أن يكون 10 أرقام ويبدأ بـ 7';
}

String? _requiredOwnershipDocumentNumber(String? value) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length >= 8 && digits.length <= 20) return null;
  return 'أدخل رقم وثيقة صحيحًا من 8 إلى 20 رقمًا';
}

String? _requiredReferenceNumber(String? value, String label) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length >= 6 && digits.length <= 20) return null;
  return '$label يجب أن يكون من 6 إلى 20 رقمًا';
}

String? _requiredPositiveInt(String? value, {int? min, int? max}) {
  final digits = ContractCalculationEngine.normalizeDigits(value ?? '').trim();
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  final number = int.tryParse(digits);
  if (number == null) return 'أدخل رقمًا صحيحًا';
  if (min != null && number < min) return 'القيمة يجب ألا تقل عن $min';
  if (max != null && number > max) return 'القيمة يجب ألا تزيد عن $max';
  return null;
}

String? _requiredFixedDigits(String? value, int length, String label) {
  final digits = _digitsOnly(value ?? '');
  if (digits.isEmpty) return 'هذا الحقل مطلوب';
  if (digits.length == length) return null;
  return '$label يجب أن يكون $length أرقام';
}

String? _requiredPositiveAmount(String? value) {
  final amount = ContractCalculationEngine.money(value ?? '');
  if (amount == null || amount <= 0) return 'أدخل مبلغًا صحيحًا أكبر من صفر';
  return null;
}

String? _requiredPositiveNumber(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  final number = double.tryParse(normalized);
  if (number == null || !number.isFinite || number <= 0) {
    return 'أدخل رقمًا صحيحًا أكبر من صفر';
  }
  return null;
}

String? _optionalPositiveAmount(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  if (normalized.isEmpty) return null;
  final amount = ContractCalculationEngine.money(normalized);
  if (amount == null || amount < 0) return 'أدخل مبلغًا صحيحًا';
  return null;
}

String? _optionalPositiveNumber(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  if (normalized.isEmpty) return null;
  final number = double.tryParse(normalized);
  if (number == null || !number.isFinite || number < 0) {
    return 'أدخل رقمًا صحيحًا';
  }
  return null;
}

String? _requiredIban(String? value) {
  final cleaned = (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (cleaned.isEmpty) return 'هذا الحقل مطلوب';
  if (RegExp(r'^SA\d{22}$').hasMatch(cleaned)) return null;
  return 'الآيبان السعودي يجب أن يبدأ بـ SA ويتكون من 24 خانة';
}

DateTime? _parseAppDate(String value) {
  final parts = value.split(RegExp(r'[/\-]'));
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime.tryParse(
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  );
  if (parsed == null ||
      parsed.year != year ||
      parsed.month != month ||
      parsed.day != day) {
    return null;
  }
  return parsed;
}

String? _ownershipDateError(String? value) {
  if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
  final date = _parseAppDate(value);
  if (date == null || date.year < 1900) return 'أدخل تاريخ وثيقة صحيحًا';
  if (date.isAfter(DateTime.now())) {
    return 'تاريخ الوثيقة لا يمكن أن يكون مستقبليًا';
  }
  return null;
}

String? _optionalDateError(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return ContractCalculationEngine.date(value) == null
      ? 'أدخل تاريخًا صحيحًا'
      : null;
}

bool _attachmentReady(AttachmentData attachment) =>
    attachment.uploaded && attachment.downloadUrl.trim().isNotEmpty;

const String _newPropertySource = 'إضافة عقار جديد';

String _contractEndDate(ContractDraft draft) {
  final start = _parseAppDate(draft.startDate);
  if (start == null) return '';
  final years = int.tryParse(draft.durationYears) ?? 0;
  final months = int.tryParse(draft.durationMonths) ?? 0;
  final days = int.tryParse(draft.durationDays) ?? 0;
  final monthIndex = start.month + months;
  final year = start.year + years + (monthIndex - 1) ~/ 12;
  final month = (monthIndex - 1) % 12 + 1;
  final day = start.day.clamp(1, DateTime(year, month + 1, 0).day);
  final end = DateTime.utc(year, month, day).add(Duration(days: days - 1));
  return '${end.year}/${end.month.toString().padLeft(2, '0')}/${end.day.toString().padLeft(2, '0')}';
}

class _SavedPropertyOption {
  final String label;
  final PropertyRecord property;

  const _SavedPropertyOption({
    required this.label,
    required this.property,
  });
}

List<_SavedPropertyOption> _savedPropertyOptions(
  List<PropertyRecord> properties,
  ContractType type,
) {
  final labels = <String, int>{};
  return properties
      .where((property) => _propertyMatchesContractType(property, type))
      .map((property) {
    final baseLabel = _savedPropertyLabel(property);
    final labelIndex = labels[baseLabel] ?? 0;
    labels[baseLabel] = labelIndex + 1;
    return _SavedPropertyOption(
      label: labelIndex == 0 ? baseLabel : '$baseLabel (${labelIndex + 1})',
      property: property,
    );
  }).toList(growable: false);
}

bool _propertyMatchesContractType(PropertyRecord property, ContractType type) {
  final data = property.data;
  final usage = (data?.propertyUsage ?? property.usage).trim();
  if (usage == 'سكني تجاري') return true;
  final unitType = (data?.unitType ??
          (property.units.isEmpty ? '' : property.units.first.type))
      .trim();
  final commercial = usage.contains('تجاري') ||
      unitType == 'محل' ||
      unitType == 'مستودع' ||
      unitType == 'مكتب إداري';
  return type == ContractType.commercial ? commercial : !commercial;
}

String _savedPropertyLabel(PropertyRecord property) {
  final data = property.data;
  final title = _cleanPropertyText(data?.buildingName ?? property.title);
  final unitNumber = _cleanPropertyText(data?.unitNumber ??
      (property.units.isEmpty ? '' : property.units.first.number));
  final district = _cleanPropertyText(data?.district ?? property.district);
  return <String>[
    title.isEmpty ? property.type : title,
    if (!property.managesUnits && unitNumber.isNotEmpty) 'وحدة $unitNumber',
    if (district.isNotEmpty) district,
  ].join(' - ');
}

String _cleanPropertyText(String value) {
  final text = value.trim();
  return text == '-' || text == 'غير محدد' ? '' : text;
}

String _numericPropertyText(String value) {
  return value.trim().replaceAll(RegExp(r'[^0-9.]'), '');
}

PropertyData _propertyDataFromRecord(
  PropertyRecord property,
  String sourceLabel,
) {
  final data = property.data;
  if (data != null) {
    return PropertyData(
      savedPropertyId: property.id,
      rentalMode: data.rentalMode,
      propertySource: sourceLabel,
      ownershipDocumentNumber: data.ownershipDocumentNumber,
      ownershipDocumentType: data.ownershipDocumentType,
      ownershipDocumentDate: data.ownershipDocumentDate,
      propertyUsage: data.propertyUsage,
      propertyType: data.propertyType,
      floorsCount: data.floorsCount,
      unitsPerFloor: data.unitsPerFloor,
      totalUnits: data.totalUnits,
      city: data.city,
      cityReferenceId: data.cityReferenceId,
      districtReferenceId: data.districtReferenceId,
      district: data.district,
      street: data.street,
      buildingNumber: data.buildingNumber,
      additionalNumber: data.additionalNumber,
      postalCode: data.postalCode,
      buildingName: data.buildingName,
      unitNumber: property.managesUnits ? '' : data.unitNumber,
      unitName: property.managesUnits ? '' : data.unitName,
      unitType: data.unitType,
      residentialCategory: data.residentialCategory,
      floor: data.floor,
      area: data.area,
      roomsCount: data.roomsCount,
      bathroomsCount: data.bathroomsCount,
      hallsCount: data.hallsCount,
      maidRoom: data.maidRoom,
      kitchen: data.kitchen,
      storage: data.storage,
      majlis: data.majlis,
      kitchenCount: data.kitchenCount,
      storageCount: data.storageCount,
      majlisCount: data.majlisCount,
      furnishingStatus: data.furnishingStatus,
      acWindow: data.acWindow,
      acSplit: data.acSplit,
      acCentral: data.acCentral,
      acWindowCount: data.acWindowCount,
      acSplitCount: data.acSplitCount,
      acCentralCount: data.acCentralCount,
      privateParking: data.privateParking,
      electricityMeter: data.electricityMeter,
      waterMeter: data.waterMeter,
      gasMeter: data.gasMeter,
      notes: data.notes,
    );
  }
  final unit = property.units.isEmpty ? null : property.units.first;
  final unitType = _cleanPropertyText(unit?.type ?? '');
  return PropertyData(
    savedPropertyId: property.id,
    rentalMode: property.data?.rentalMode ?? '',
    propertySource: sourceLabel,
    propertyUsage: property.usage,
    propertyType: property.type,
    floorsCount: property.floors.toString(),
    unitsPerFloor: '1',
    totalUnits: property.totalUnits.toString(),
    city: property.city,
    cityReferenceId: property.data?.cityReferenceId ?? '',
    districtReferenceId: property.data?.districtReferenceId ?? '',
    district: property.district,
    buildingName: property.title,
    unitNumber: _cleanPropertyText(unit?.number ?? ''),
    unitName: _cleanPropertyText(unit?.name ?? ''),
    unitType: unitType.isEmpty ? 'شقة' : unitType,
    floor: _cleanPropertyText(unit?.floor ?? ''),
    area: _numericPropertyText(unit?.area ?? ''),
  );
}

PropertyData _newPropertyDataForContractType(ContractType type) {
  final data = PropertyData(propertySource: _newPropertySource);
  if (type == ContractType.commercial) {
    data
      ..propertyUsage = 'تجاري'
      ..propertyType = 'برج'
      ..unitType = 'محل';
  }
  return data;
}

void _applyContractType(ContractDraft draft, ContractType type) {
  final typeChanged = draft.type != type;
  final savedPropertySelected =
      draft.property.propertySource.trim() != _newPropertySource;
  draft.type = type;
  if (typeChanged && savedPropertySelected) {
    draft.property = _newPropertyDataForContractType(type);
    return;
  }
  if (!typeChanged && savedPropertySelected) return;
  if (type == ContractType.commercial) {
    draft.property
      ..unitType = 'محل'
      ..propertyType = 'برج'
      ..propertyUsage = 'تجاري';
  } else {
    draft.property
      ..unitType = 'شقة'
      ..propertyType = 'عمارة'
      ..propertyUsage = 'سكن عوائل';
  }
}

ContractDraft createContractDraftForType(ContractType type) {
  final draft = ContractDraft();
  _applyContractType(draft, type);
  return draft;
}

class CreateContractScreen extends StatefulWidget {
  final AdminContractSession? adminSession;
  final ContractDraft? initialDraft;
  final String draftId;
  final int? initialStep;
  final List<String> initialTouchedSections;
  final bool renewalMode;
  final String renewalSourceNumber;

  const CreateContractScreen({
    super.key,
    this.adminSession,
    this.initialDraft,
    this.draftId = '',
    this.initialStep,
    this.initialTouchedSections = const <String>[],
    this.renewalMode = false,
    this.renewalSourceNumber = '',
  });

  @override
  State<CreateContractScreen> createState() => _CreateContractScreenState();
}

class _CreateContractScreenState extends State<CreateContractScreen> {
  static const List<String> _steps = <String>[
    'النوع',
    'الملكية',
    'الأطراف',
    'العقار',
    'المالية',
    'المرفقات',
    'المراجعة',
  ];

  late ContractDraft _draft;
  late final ContractAssistantController _assistant;
  final _fieldAnchors = <String, GlobalKey>{};
  final _recoveryStore = ContractDraftStore();
  Timer? _localSaveTimer, _cloudSaveTimer;
  Future<void>? _cloudSaveFuture;
  String _draftOwner = '';
  AppController? _accountController;
  int? _draftSessionEpoch;
  bool get _sameDraftAccount =>
      _accountController != null &&
      _accountController!.sessionEpoch == _draftSessionEpoch;
  String _saveStatus = '';
  bool _localRecoveryAvailable = true;
  bool _hasEdits = false, _submitted = false;
  DateTime _lastManualInteraction = DateTime(2000);
  late String _draftId;
  final Set<String> _touchedSections = <String>{};
  final List<GlobalKey<FormState>> _formKeys =
      List<GlobalKey<FormState>>.generate(
    7,
    (_) => GlobalKey<FormState>(),
  );
  final ScrollController _scrollController = ScrollController();

  int _currentStep = 0;
  int _partyTab = 0;
  final String _flowId = DateTime.now().microsecondsSinceEpoch.toString();
  bool _submitting = false;
  bool _draftConflict = false;
  bool _savingDraft = false;
  bool _recoveringDraft = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft == null
        ? ContractDraft()
        : ContractDraft.copyOf(widget.initialDraft!);
    _draft.frozenTotal = null;
    _syncPaymentPeriod();
    _draft.frozenPrice = null;
    _draft.renewal = widget.renewalMode;
    if (widget.renewalMode) _draft.submissionId = '';
    _draftId = widget.draftId.trim();
    _touchedSections.addAll(widget.initialTouchedSections);
    _currentStep = (widget.initialStep ??
            (widget.initialDraft == null
                ? 0
                : firstIncompleteDraftStep(_draft)))
        .clamp(0, _steps.length - 1);
    _assistant = ContractAssistantController(
        readDraft: () => _draft,
        renewal: widget.renewalMode,
        onApply: (draft, paths) {
          if (!mounted) return;
          setState(() {
            _draft = draft;
            _syncPaymentPeriod();
          });
          _scheduleAutosave();
        },
        onFocus: _focusAssistantField);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _offerRecovery();
      if (widget.adminSession == null) {
        AppTelemetry.record('contract_start', 'create_contract',
            step: _currentStep, flowId: _flowId);
      }
    });
  }

  @override
  void dispose() {
    if (!_submitted && widget.adminSession == null) {
      AppTelemetry.record('contract_exit', 'create_contract',
          step: _currentStep, flowId: _flowId);
    }
    _localSaveTimer?.cancel();
    _cloudSaveTimer?.cancel();
    if (_hasEdits && !_submitted) unawaited(_saveLocal());
    _assistant.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  bool _isBlank(String value) => value.trim().isEmpty;

  List<String> _missingPartyFields(PartyData party, {bool isLessor = false}) {
    if (party.kind == PartyKind.individual) {
      return <String>[
        if (_requiredName(party.fullName) != null) 'الاسم الكامل',
        if (validateContractIdentityNumber(party.idNumber, party.idType) !=
            null)
          'رقم الهوية',
        if (validateAdultBirthDate(party.birthDate) != null) 'تاريخ الميلاد',
        if (_requiredSaudiMobile(party.mobile) != null) 'رقم جوال أبشر',
        if (_optionalEmail(party.email) != null) 'البريد الإلكتروني',
        if (_requiredValue(party.city) != null) 'مدينة العنوان الوطني',
        if (_requiredName(party.district) != null) 'حي العنوان الوطني',
        if (_requiredValue(party.nationalAddress) != null)
          'تفاصيل العنوان الوطني',
        if (!party.mobileRegisteredInAbsher) 'تأكيد تسجيل الجوال في أبشر',
        if (isLessor && _requiredIban(party.iban) != null) 'آيبان المؤجر',
        if (isLessor && _requiredName(party.bankName) != null) 'اسم البنك',
        if (isLessor && _requiredName(party.accountOwner) != null)
          'اسم صاحب الحساب',
      ];
    }
    return <String>[
      if (_requiredName(party.fullName) != null) 'اسم المنشأة',
      if (_requiredCrNumber(party.commercialRegistration) != null)
        'رقم السجل التجاري',
      if (_requiredUnifiedNumber(party.unifiedNumber) != null)
        'الرقم الموحد للمنشأة',
      if (_requiredName(party.authorizedPersonName) != null) 'اسم المفوض',
      if (_requiredSaudiPersonId(party.authorizedPersonId) != null)
        'هوية المفوض',
      if (_requiredSaudiMobile(party.mobile) != null) 'رقم جوال أبشر للمفوض',
      if (_optionalEmail(party.email) != null) 'البريد الإلكتروني',
      if (_requiredValue(party.city) != null) 'مدينة العنوان الوطني',
      if (_requiredName(party.district) != null) 'حي العنوان الوطني',
      if (_requiredValue(party.nationalAddress) != null)
        'تفاصيل العنوان الوطني',
      if (!party.mobileRegisteredInAbsher) 'تأكيد تسجيل الجوال في أبشر',
      if (isLessor && _requiredIban(party.iban) != null) 'آيبان المؤجر',
      if (isLessor && _requiredName(party.bankName) != null) 'اسم البنك',
      if (isLessor && _requiredName(party.accountOwner) != null)
        'اسم صاحب الحساب',
    ];
  }

  void _markChanged() {
    _syncPaymentPeriod();
    _touchedSections.add(draftSectionForStep(_currentStep));
    _assistant.manualChanged();
    _scheduleAutosave();
    setState(() {});
  }

  void _formChanged() {
    _lastManualInteraction = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _submitting) return;
      _assistant.manualChanged();
      _scheduleAutosave();
      setState(() {});
    });
  }

  void _focusAssistantField(ContractFieldSpec field) {
    if (!mounted) return;
    // Don't move a user's cursor or wrestle with a manual scroll.
    if (DateTime.now().difference(_lastManualInteraction).inMilliseconds <
        1400) {
      return;
    }
    setState(() {
      _currentStep = field.step;
      if (field.path.startsWith('lessor.')) _partyTab = 0;
      if (field.path.startsWith('tenant.')) _partyTab = 1;
      if (field.path.startsWith('representative.')) _partyTab = 2;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _fieldAnchors[field.path]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target,
            alignment: .15,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 380));
      }
    });
  }

  void _scheduleAutosave() {
    if (_submitted || _submitting || _savingDraft) return;
    _hasEdits = true;
    if (widget.adminSession != null) {
      setAdminEditorDirty(true);
      if (_currentStep != 6) widget.adminSession!.acknowledged = false;
      return;
    }
    _localSaveTimer?.cancel();
    _cloudSaveTimer?.cancel();
    _localSaveTimer =
        Timer(const Duration(milliseconds: 450), () => unawaited(_saveLocal()));
    if (!_draftConflict) {
      _cloudSaveTimer =
          Timer(const Duration(seconds: 3), () => unawaited(_saveCloud()));
    }
  }

  Future<void> _saveLocal({bool showStatus = true}) async {
    if (widget.adminSession != null) return;
    if (!_sameDraftAccount || _draftOwner.isEmpty || _submitted) return;
    if (_draftOwner != 'local-demo' &&
        (!FirebaseBootstrap.initialized ||
            FirebaseAuth.instance.currentUser?.uid != _draftOwner)) {
      return;
    }
    try {
      await _recoveryStore.save(_draftOwner, {
        'draft': FirebaseRepository.draftToMap(_draft),
        'draftId': _draftId,
        'step': _currentStep,
        'renewal': widget.renewalMode
      });
      _localRecoveryAvailable = true;
      if (mounted && showStatus) {
        setState(() => _saveStatus = 'تم الحفظ على هذا الجهاز');
      }
    } catch (error) {
      _localRecoveryAvailable = false;
      // Classify failures without logging draft contents, storage keys or UID.
      final category = RegExp(
              r'QuotaExceededError|SecurityError|OperationError|TypeError|MissingPluginException|UnsupportedError|JsonUnsupportedObjectError|InvalidAccessError')
          .firstMatch('$error')
          ?.group(0);
      debugPrint(
          'Contract recovery unavailable: ${category ?? 'storage_error'}');
      if (mounted && showStatus) {
        setState(
            () => _saveStatus = 'تعذر الحفظ على الجهاز؛ استخدم حفظ كمسودة');
      }
    }
  }

  Future<void> _saveCloud() async {
    if (!_sameDraftAccount ||
        _submitted ||
        !mounted ||
        !FirebaseBootstrap.initialized ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    if (_cloudSaveFuture != null) {
      await _cloudSaveFuture;
      return;
    }
    final revision = _assistant.revision;
    _cloudSaveFuture = () async {
      try {
        final result = await AppScope.of(context, listen: false).saveDraft(
            ContractDraft.copyOf(_draft),
            draftId: _draftId,
            progress: _draftProgress);
        if (!_sameDraftAccount) return;
        _draftId = result.id;
        _draft.serverRevision = result.draftData?.serverRevision;
        // A failed local recovery copy must not overwrite a successful cloud save.
        if (!_submitted) await _saveLocal(showStatus: false);
        if (mounted) {
          setState(() => _saveStatus = result.pendingSync
              ? (_localRecoveryAvailable
                  ? 'محفوظ على الجهاز • بانتظار المزامنة'
                  : 'لم تتم المزامنة بعد؛ أبقِ الشاشة مفتوحة وأعد المحاولة')
              : (_localRecoveryAvailable
                  ? 'تمت مزامنة المسودة'
                  : 'تم الحفظ في حسابك • النسخة المحلية غير متاحة'));
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _draftConflict =
                error is FirebaseFunctionsException && error.code == 'aborted';
            _saveStatus = _draftConflict
                ? 'توجد نسخة أحدث؛ تعديلاتك محفوظة على الجهاز. اضغط حفظ التعديلات'
                : 'تعذرت المزامنة؛ حاول مجددًا أو استخدم حفظ كمسودة';
          });
        }
      }
    }();
    await _cloudSaveFuture;
    _cloudSaveFuture = null;
    if (mounted && !_submitted && revision != _assistant.revision) {
      _scheduleAutosave();
    }
  }

  Future<void> _offerRecovery() async {
    if (!mounted) return;
    if (widget.adminSession != null) return;
    _accountController = AppScope.of(context, listen: false);
    _draftSessionEpoch = _accountController!.sessionEpoch;
    _draftOwner = FirebaseBootstrap.initialized
        ? FirebaseAuth.instance.currentUser?.uid ?? 'local-demo'
        : 'local-demo';
    if (widget.initialDraft != null || widget.renewalMode) return;
    try {
      final stored = await _recoveryStore.read(_draftOwner);
      if (!mounted || !_sameDraftAccount || stored == null || _hasEdits) return;
      final restore = await showAccountConfirmation(context,
          title: 'لديك عقد غير مكتمل',
          message: 'هل تريد متابعة المسودة المحفوظة على هذا الجهاز؟',
          confirmLabel: 'متابعة العقد',
          cancelLabel: 'عقد جديد',
          icon: Icons.edit_document);
      if (!mounted || !_sameDraftAccount || restore != true) return;
      final recovered = FirebaseRepository.draftFromMap(stored['draft']);
      if (recovered == null) return;
      setState(() {
        _draft = recovered;
        _syncPaymentPeriod();
        _draftId = '${stored['draftId'] ?? ''}';
        _currentStep = (stored['step'] as int? ?? 0).clamp(0, 6);
      });
      _assistant.resetObservation();
    } catch (_) {/* Recovery cannot block ordinary manual creation. */}
  }

  DraftProgress get _draftProgress => DraftProgress(
        lastStep: _currentStep,
        touchedSections: _touchedSections.toList(),
      );

  List<String> _missingRepresentativeFields(RepresentativeData representative) {
    if (!representative.enabled) return const <String>[];
    return <String>[
      if (_requiredName(representative.fullName) != null)
        'اسم الوكيل أو المفوض',
      if (validateContractIdentityNumber(
              representative.idNumber, representative.idType) !=
          null)
        'رقم هوية الوكيل',
      if (validateAdultBirthDate(representative.birthDate) != null)
        'تاريخ ميلاد الوكيل',
      if (_requiredSaudiMobile(representative.mobile) != null) 'جوال الوكيل',
      if (_requiredReferenceNumber(
              representative.authorizationNumber, 'رقم الوكالة أو التفويض') !=
          null)
        'رقم الوكالة أو التفويض',
      if (_optionalDateError(representative.authorizationDate) != null)
        'تاريخ الوكالة',
      if (_optionalDateError(representative.expiryDate) != null)
        'تاريخ انتهاء الوكالة',
      if (ContractCalculationEngine.date(representative.authorizationDate)
          case final issued?)
        if (ContractCalculationEngine.date(representative.expiryDate)
            case final expiry?)
          if (expiry.isBefore(issued)) 'تاريخ الانتهاء بعد تاريخ الوكالة',
    ];
  }

  void _syncPaymentPeriod() {
    _draft.rentPeriod = _draft.paymentScheduleType == 'دوري'
        ? _draft.paymentFrequency
        : _draft.paymentScheduleType;
  }

  bool _validatePartiesStep() {
    final lessorMissing = _missingPartyFields(_draft.lessor, isLessor: true);
    if (lessorMissing.isNotEmpty) {
      setState(() => _partyTab = 0);
      showAppSnackBar(
        context,
        'أكمل بيانات المؤجر المطلوبة: ${lessorMissing.join('، ')}',
      );
      return false;
    }
    final tenantMissing = _missingPartyFields(_draft.tenant);
    if (tenantMissing.isNotEmpty) {
      setState(() => _partyTab = 1);
      showAppSnackBar(
        context,
        'أكمل بيانات المستأجر المطلوبة: ${tenantMissing.join('، ')}',
      );
      return false;
    }
    final representativeMissing =
        _missingRepresentativeFields(_draft.representative);
    if (representativeMissing.isNotEmpty) {
      setState(() => _partyTab = 2);
      showAppSnackBar(
        context,
        'أكمل بيانات الوكيل أو المفوض المطلوبة: ${representativeMissing.join('، ')}',
      );
      return false;
    }
    return true;
  }

  bool _isPositiveNumber(String value) {
    final amount = double.tryParse(value.replaceAll(',', '').trim());
    return amount != null && amount.isFinite && amount > 0;
  }

  List<String> _missingPropertyFields() {
    final property = _draft.property;
    final ownershipDate = _parseAppDate(property.ownershipDocumentDate);
    return <String>[
      if (_requiredOwnershipDocumentNumber(property.ownershipDocumentNumber) !=
          null)
        'رقم وثيقة الملكية',
      if (_isBlank(property.ownershipDocumentDate)) 'تاريخ وثيقة الملكية',
      if (!_isBlank(property.ownershipDocumentDate) && ownershipDate == null)
        'تاريخ وثيقة الملكية بصيغة صحيحة',
      if (ownershipDate != null && ownershipDate.isAfter(DateTime.now()))
        'تاريخ وثيقة الملكية غير مستقبلي',
      if (ownershipDate != null && ownershipDate.year < 1900)
        'تاريخ وثيقة الملكية بصيغة ميلادية صحيحة',
      if (_requiredValue(property.city) != null) 'المدينة',
      if (_requiredPositiveInt(property.floorsCount, min: 1, max: 200) != null)
        'عدد الأدوار',
      if (property.unitsPerFloor.trim().isNotEmpty &&
          _requiredPositiveInt(property.unitsPerFloor, min: 1, max: 200) !=
              null)
        'عدد الوحدات في كل دور',
      if (_requiredPositiveInt(property.totalUnits, min: 1, max: 9999) != null)
        'إجمالي عدد الوحدات',
      if (_requiredName(property.district) != null) 'الحي',
      if (_requiredName(property.street) != null) 'الشارع',
      if (_requiredFixedDigits(property.buildingNumber, 4, 'رقم المبنى') !=
          null)
        'رقم المبنى',
      if (_requiredFixedDigits(property.additionalNumber, 4, 'الرقم الإضافي') !=
          null)
        'الرقم الإضافي',
      if (_requiredFixedDigits(property.postalCode, 5, 'الرمز البريدي') != null)
        'الرمز البريدي',
      if (_requiredValue(property.unitNumber) != null) 'رقم الوحدة',
      if (_requiredName(property.unitName) != null) 'اسم الوحدة',
      if (_requiredValue(property.floor) != null) 'رقم الدور',
      if (!_isPositiveNumber(property.area)) 'مساحة الوحدة',
      if (_draft.type == ContractType.residential &&
          _requiredPositiveInt(property.roomsCount, min: 1, max: 50) != null)
        'عدد الغرف',
      if (_requiredPositiveInt(property.bathroomsCount, min: 1, max: 50) !=
          null)
        'دورات المياه',
      if (_requiredPositiveInt(property.hallsCount, min: 0, max: 50) != null)
        'الصالات',
      if (_requiredPositiveInt(property.acWindowCount, min: 0, max: 50) != null)
        'عدد مكيفات الشباك',
      if (_requiredPositiveInt(property.acSplitCount, min: 0, max: 50) != null)
        'عدد مكيفات السبليت',
      if (_requiredPositiveInt(property.acCentralCount, min: 0, max: 50) !=
          null)
        'عدد أجهزة التكييف المركزي',
      if (_requiredPositiveInt(property.kitchenCount, min: 0, max: 50) != null)
        'عدد المطابخ',
      if (_requiredPositiveInt(property.majlisCount, min: 0, max: 50) != null)
        'عدد المجالس',
      if (_requiredPositiveInt(property.storageCount, min: 0, max: 50) != null)
        'عدد المخازن',
      if ((int.tryParse(property.acWindowCount) ?? 0) +
              (int.tryParse(property.acSplitCount) ?? 0) +
              (int.tryParse(property.acCentralCount) ?? 0) ==
          0)
        'حدد عدد جهاز تكييف واحد على الأقل',
      if (validateUnitMeterNumber(property.electricityMeter) != null)
        'رقم عداد الكهرباء',
      if (validateUnitMeterNumber(property.waterMeter) != null)
        'رقم عداد المياه',
      if (validateUnitMeterNumber(property.gasMeter) != null) 'رقم عداد الغاز',
    ];
  }

  bool _validatePropertyStep() {
    final saved = AppScope.of(context, listen: false)
        .properties
        .where((p) => p.id == _draft.property.savedPropertyId)
        .firstOrNull;
    if (saved?.managesUnits == true &&
        !saved!.units.any((u) => u.number == _draft.property.unitNumber)) {
      showAppSnackBar(context, 'اختر وحدة مسجلة داخل العمارة أولًا.');
      return false;
    }
    final missing = _missingPropertyFields();
    if (missing.isEmpty) {
      final floors = int.tryParse(_draft.property.floorsCount) ?? 0;
      final unitsPerFloor = int.tryParse(_draft.property.unitsPerFloor) ?? 0;
      final totalUnits = int.tryParse(_draft.property.totalUnits) ?? 0;
      if (_draft.property.rentalMode != 'whole' &&
          floors > 0 &&
          unitsPerFloor > 0 &&
          totalUnits > 0 &&
          totalUnits < floors * unitsPerFloor) {
        showAppSnackBar(
          context,
          'إجمالي عدد الوحدات لا يمكن أن يكون أقل من عدد الأدوار × الوحدات في كل دور',
        );
        return false;
      }
      return true;
    }
    showAppSnackBar(
      context,
      'أكمل بيانات العقار والوحدة المطلوبة: ${missing.join('، ')}',
    );
    return false;
  }

  List<String> _missingFinancialFields() {
    final years = int.tryParse(_draft.durationYears) ?? 0;
    final months = int.tryParse(_draft.durationMonths) ?? 0;
    final days = int.tryParse(_draft.durationDays) ?? 0;
    final startDate = _parseAppDate(_draft.startDate);
    final endDate = _parseAppDate(_draft.endDate);
    final firstPaymentDate = _parseAppDate(_draft.firstPaymentDate);
    final calculation = _draft.rentalCalculation;
    return <String>[
      if (_isBlank(_draft.startDate)) 'تاريخ بداية العقد',
      if (_isBlank(_draft.endDate)) 'تاريخ نهاية العقد',
      if (startDate == null || startDate.year < 1900) 'تاريخ بداية صحيح',
      if (endDate == null || endDate.year > 2200) 'تاريخ نهاية صحيح',
      if (startDate != null && endDate != null && endDate.isBefore(startDate))
        'تاريخ نهاية العقد بعد تاريخ البداية',
      if (startDate != null &&
          endDate != null &&
          _draft.endDate != _contractEndDate(_draft))
        'تاريخ نهاية العقد مطابق للمدة المحددة',
      if (years <= 0 && months <= 0 && days <= 0) 'مدة العقد',
      if (_requiredPositiveInt(_draft.durationYears, min: 0, max: 50) != null)
        'عدد السنوات من 0 إلى 50',
      if (int.tryParse(_draft.durationMonths) == null) 'عدد الأشهر',
      if (int.tryParse(_draft.durationDays) == null) 'عدد الأيام',
      if (months < 0 || months > 11) 'عدد الأشهر من 0 إلى 11',
      if (days < 0 || days > 30) 'عدد الأيام من 0 إلى 30',
      if (_requiredPositiveAmount(_draft.rentValue) != null)
        'مبلغ الإيجار السنوي',
      if (calculation == null ||
          calculation.installments.any((amount) => amount <= 0))
        'جدول دفعات صالح بمبالغ أكبر من صفر',
      if (_draft.hasSecurityDeposit &&
          _requiredPositiveAmount(_draft.securityDeposit) != null)
        'قيمة الضمان',
      if (_optionalPositiveAmount(_draft.brokerageFee) != null) 'عمولة السعي',
      if (_optionalPositiveAmount(_draft.otherAmounts) != null) 'مبالغ أخرى',
      if (_draft.ownerSubjectToVat &&
          _requiredPositiveAmount(_draft.vatValue) != null)
        'قيمة ضريبة القيمة المضافة',
      if (_draft.paymentScheduleType == 'مخصص' &&
          (_draft.paymentCount <= 0 || _draft.paymentCount > 1200))
        'عدد الدفعات',
      if (_isBlank(_draft.firstPaymentDate)) 'تاريخ أول دفعة',
      if (firstPaymentDate == null) 'تاريخ أول دفعة صحيح',
      if (startDate != null &&
          firstPaymentDate != null &&
          firstPaymentDate.isBefore(startDate))
        'تاريخ أول دفعة بعد بداية العقد',
      if (endDate != null &&
          firstPaymentDate != null &&
          firstPaymentDate.isAfter(endDate))
        'تاريخ أول دفعة قبل نهاية العقد',
      if (_draft.paymentScheduleType == 'دوري' &&
          calculation != null &&
          firstPaymentDate != null &&
          endDate != null &&
          ContractCalculationEngine.addMonths(
                  firstPaymentDate,
                  ContractCalculationEngine.frequencyMonths(
                          _draft.paymentFrequency) *
                      (calculation.installments.length - 1))
              .isAfter(ContractCalculationEngine.date(_draft.endDate)!))
        'جدول الدفعات ينتهي داخل مدة العقد؛ عدّل تاريخ أول دفعة أو تكرار الدفع',
      if (!_draft.electricity.enabled) 'الكهرباء',
      if (!_draft.water.enabled) 'المياه',
      for (final service in {
        'الكهرباء': _draft.electricity,
        'المياه': _draft.water,
        'الغاز': _draft.gas
      }.entries)
        if (service.value.enabled) ...[
          if (service.value.calculationMethod == 'مبلغ مقطوع' &&
              _requiredPositiveAmount(service.value.fixedAmount) != null)
            'قيمة مبلغ ${service.key}',
          if (_optionalPositiveNumber(service.value.currentReading) != null)
            'قراءة عداد ${service.key}',
        ],
    ];
  }

  bool _validateFinancialStep() {
    final missing = _missingFinancialFields();
    if (missing.isEmpty) return true;
    showAppSnackBar(
      context,
      'أكمل البيانات المالية المطلوبة: ${missing.join('، ')}',
    );
    return false;
  }

  void _next() {
    FocusScope.of(context).unfocus();
    final form = _formKeys[_currentStep].currentState;
    if (form != null && !form.validate()) {
      showAppSnackBar(context, 'راجع الحقول المطلوبة قبل المتابعة');
      return;
    }

    if (_currentStep == 0 &&
        _draft.property.propertySource.trim() == _newPropertySource) {
      _draft.property.propertyUsage =
          _draft.type == ContractType.residential ? 'سكن عوائل' : 'تجاري';
    }
    if (_currentStep == 2 && !_validatePartiesStep()) {
      return;
    }
    if (_currentStep == 3 && !_validatePropertyStep()) {
      return;
    }
    if (_currentStep == 4 && !_validateFinancialStep()) {
      return;
    }
    if (_currentStep == 4) {
      _draft.regenerateInstallments();
    }
    if (_currentStep == 5) {
      final missing = _requiredAttachments
          .where((attachment) => !_attachmentReady(attachment))
          .map((attachment) => attachment.title)
          .toList();
      if (missing.isNotEmpty) {
        showAppSnackBar(
          context,
          'يرجى رفع المستندات المطلوبة: ${missing.join('، ')}',
        );
        return;
      }
    }

    _touchedSections.add(draftSectionForStep(_currentStep));

    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep += 1);
      if (widget.adminSession == null) {
        AppTelemetry.record('contract_step', 'create_contract',
            step: _currentStep, flowId: _flowId);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
    }
  }

  Future<void> _cancelAdminEditor() async {
    if (_submitting) return;
    if (_hasEdits) {
      final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('تعديلات غير محفوظة'),
                  content: const Text(
                      'احفظ المسودة قبل المغادرة للحفاظ على تعديلاتك.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('متابعة التحرير')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('مغادرة دون حفظ'))
                  ]));
      if (leave != true) return;
    }
    cancelAdminEditor();
  }

  void _previous() {
    if (_currentStep == 0) {
      if (widget.adminSession != null) {
        _cancelAdminEditor();
        return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _currentStep -= 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
  }

  List<AttachmentData> get _requiredAttachments {
    return _draft.attachments.where((attachment) {
      if (AppRuntime.attachment(attachment.keyName, false)) return true;
      if (attachment.keyName == 'authorization') {
        return _draft.representative.enabled;
      }
      if (attachment.keyName == 'iban') {
        return _draft.paymentChannel.contains('سداد');
      }
      if (attachment.keyName == 'commercial_registration') {
        return _draft.lessor.kind == PartyKind.company ||
            _draft.tenant.kind == PartyKind.company;
      }
      return AppRuntime.attachment(attachment.keyName, attachment.required);
    }).toList();
  }

  bool _validateAllRequiredFields() {
    if (_requiredOwnershipDocumentNumber(
                _draft.property.ownershipDocumentNumber) !=
            null ||
        _ownershipDateError(_draft.property.ownershipDocumentDate) != null) {
      setState(() => _currentStep = 1);
      _scrollTop();
      showAppSnackBar(context, 'راجع رقم وثيقة الملكية وتاريخها');
      return false;
    }
    if (!_validatePartiesStep()) {
      setState(() => _currentStep = 2);
      _scrollTop();
      return false;
    }
    if (!_validatePropertyStep()) {
      setState(() => _currentStep = 3);
      _scrollTop();
      return false;
    }
    if (!_validateFinancialStep()) {
      setState(() => _currentStep = 4);
      _scrollTop();
      return false;
    }
    final missingAttachments = _requiredAttachments
        .where((attachment) => !_attachmentReady(attachment))
        .map((attachment) => attachment.title)
        .toList();
    if (missingAttachments.isNotEmpty) {
      setState(() => _currentStep = 5);
      _scrollTop();
      showAppSnackBar(
        context,
        'توجد مرفقات مطلوبة: ${missingAttachments.join('، ')}',
      );
      return false;
    }
    _draft.regenerateInstallments();
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_draftConflict) {
      await _recoverDraftConflict();
      return;
    }
    if (_assistant.pending.isNotEmpty) {
      showAppSnackBar(
          context, 'أكّد القيم التي أدخلها المساعد قبل إرسال الطلب');
      _assistant.focus(_assistant.pending.first.path);
      return;
    }
    if (!_validateAllRequiredFields()) return;
    if (widget.adminSession == null &&
        (!_draft.acceptAccuracyDeclaration ||
            !_draft.acceptDataSharing ||
            !_draft.acceptTerms)) {
      showAppSnackBar(context, 'يجب الموافقة على الإقرارات والشروط');
      return;
    }
    _touchedSections.addAll(const <String>{
      draftSectionContract,
      draftSectionParties,
      draftSectionProperty,
      draftSectionFinancial,
      draftSectionAttachments,
    });
    setState(() => _submitting = true);
    _localSaveTimer?.cancel();
    _cloudSaveTimer?.cancel();
    await _cloudSaveFuture;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final controller = AppScope.of(context, listen: false);
    late final ContractRecord record;
    try {
      record = await controller.submitContract(_draft,
          draftId: _draftId, progress: _draftProgress);
    } catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        if (error is FirebaseFunctionsException && error.code == 'aborted') {
          await _recoverDraftConflict();
          return;
        }
        showAppSnackBar(
            context,
            error is FirebaseFunctionsException
                ? error.message ?? 'تعذر إرسال العقد.'
                : widget.adminSession != null
                    ? '$error'
                    : 'تعذر إرسال العقد. راجع البيانات والإعدادات.');
      }
      return;
    }
    if (!record.pendingSync && widget.adminSession == null) {
      AppTelemetry.record('contract_submit', 'create_contract',
          step: _currentStep, flowId: _flowId);
    }
    final waitsForConnection = record.pendingSync;
    // The controller owns offline submissions too; don't restore a second copy.
    _submitted = true;
    if (widget.adminSession != null) {
      setState(() => _submitting = false);
      completeAdminEditor(record.id);
      return;
    }
    try {
      if (_draftOwner.isNotEmpty) await _recoveryStore.clear(_draftOwner);
    } catch (_) {/* A storage error must not undo a successful submission. */}
    if (!mounted) return;
    setState(() => _submitting = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SuccessBurst(size: 110),
            const SizedBox(height: 14),
            Text(
              waitsForConnection
                  ? 'تم حفظ الطلب محليًا'
                  : 'تم إنشاء الطلب بنجاح',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              waitsForConnection
                  ? 'رقم الطلب: ${record.requestNumber}\nسيتم رفع الطلب تلقائيًا عند عودة الاتصال، وبعدها يظهر الدفع والمتابعة.'
                  : 'رقم الطلب: ${record.requestNumber}\nادفع رسوم الطلب للانتقال إلى قيد المعالجة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: waitsForConnection ? 'عرض الطلب' : 'عرض ودفع الرسوم',
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => ContractDetailsScreen(contract: record),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: const Text('العودة للرئيسية'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDraft() async {
    if (_savingDraft || _submitting) return;
    if (widget.adminSession == null && _draftConflict) {
      await _recoverDraftConflict();
      return;
    }
    if (widget.adminSession != null) {
      if (_submitting) return;
      setState(() => _submitting = true);
      try {
        final record = await widget.adminSession!
            .saveDraft(_draft, progress: _draftProgress);
        _draftId = record.id;
        _hasEdits = false;
        setAdminEditorDirty(false);
        if (mounted) showAppSnackBar(context, 'تم حفظ المسودة في حساب العميل');
      } catch (error) {
        if (mounted) {
          showAppSnackBar(
              context,
              error is FirebaseFunctionsException
                  ? error.message ?? 'تعذر حفظ المسودة'
                  : '$error');
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    _localSaveTimer?.cancel();
    _cloudSaveTimer?.cancel();
    _savingDraft = true;
    await _saveLocal();
    await _cloudSaveFuture;
    if (!mounted) return;
    _touchedSections.add(draftSectionForStep(_currentStep));
    final controller = AppScope.of(context, listen: false);
    late final ContractRecord record;
    try {
      record = await controller.saveDraft(_draft,
          draftId: _draftId, progress: _draftProgress);
    } catch (error) {
      _savingDraft = false;
      if (mounted &&
          error is FirebaseFunctionsException &&
          error.code == 'aborted') {
        await _recoverDraftConflict();
        return;
      }
      if (mounted) {
        showAppSnackBar(
            context,
            error is FirebaseFunctionsException
                ? error.message ?? 'تعذر حفظ المسودة'
                : 'تعذر حفظ المسودة. احتفظ بتعديلاتك وأعد المحاولة.');
      }
      return;
    }
    if (!mounted) return;
    _draftId = record.id;
    _draft.serverRevision = record.draftData?.serverRevision;
    await _saveLocal(showStatus: false);
    _savingDraft = false;
    if (!mounted) return;
    setState(() => _saveStatus = record.pendingSync
        ? 'محفوظ على الجهاز • بانتظار المزامنة'
        : 'تمت مزامنة المسودة');
    showAppSnackBar(
      context,
      record.pendingSync
          ? 'تم حفظ المسودة محليًا وستتم مزامنتها عند عودة الاتصال'
          : 'تم حفظ المسودة برقم ${record.requestNumber}',
    );
  }

  Future<void> _recoverDraftConflict() async {
    if (!mounted || widget.adminSession != null || _recoveringDraft) return;
    _recoveringDraft = true;
    _draftConflict = true;
    _cloudSaveTimer?.cancel();
    await _saveLocal();
    if (!mounted) return;
    final keepEdits = await showAccountConfirmation(context,
        title: 'احتفظ بتعديلاتك',
        message:
            'توجد نسخة أحدث من هذه المسودة في حسابك. يمكنك حفظ جميع بياناتك ومرفقاتك الحالية في مسودة جديدة، ثم مراجعتها وإرسالها.',
        confirmLabel: 'حفظ تعديلاتي في مسودة جديدة',
        cancelLabel: 'متابعة المراجعة',
        icon: Icons.copy_all_rounded);
    _recoveringDraft = false;
    if (!mounted || !keepEdits || !_sameDraftAccount) return;
    AppScope.of(context, listen: false).discardPendingDraftSync(_draftId);
    setState(() {
      _draft = forkConflictedDraft(_draft);
      _draftId = '';
      _draftConflict = false;
    });
    _assistant.resetObservation();
    await _saveDraft();
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    if (!AppRuntime.service(_draft.type.name) ||
        (widget.renewalMode && !AppRuntime.service('renewal'))) {
      return const ServiceUnavailable();
    }
    final compactAssistantLayout =
        MediaQuery.viewInsetsOf(context).bottom > 0 ||
            MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.adminSession != null
              ? 'عقد للعميل ${widget.adminSession!.userName}'
              : widget.renewalMode
                  ? 'تجديد عقد'
                  : _draftId.isEmpty
                      ? 'إنشاء عقد جديد'
                      : 'استكمال المسودة',
        ),
        leading: IconButton(
          onPressed: _previous,
          icon: const BackButtonIcon(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saveDraft,
            child: Text(_draftId.isEmpty ? 'حفظ كمسودة' : 'حفظ التعديلات'),
          ),
        ],
      ),
      body: SafeArea(
        child: LoadingOverlay(
          visible: _submitting,
          label: 'جارٍ إنشاء الطلب...',
          child: Column(
            children: <Widget>[
              if (!compactAssistantLayout)
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: WizardProgress(
                        labels: _steps,
                        current: _currentStep,
                      ),
                    ),
                  ),
                ),
              if (!compactAssistantLayout)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListenableBuilder(
                        listenable: _assistant,
                        builder: (context, _) => Column(children: [
                              LinearProgressIndicator(
                                  value: _assistant.progress,
                                  minHeight: 3,
                                  borderRadius: BorderRadius.circular(4)),
                              Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                      'اكتمال البيانات ${(_assistant.progress * 100).round()}٪ • ${_assistant.missing.length} معلومة ناقصة${_assistant.pending.isEmpty ? '' : ' • ${_assistant.pending.length} بانتظار التأكيد'}${_saveStatus.isEmpty ? '' : '\n$_saveStatus'}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: context.ejarzTheme.muted))),
                            ]))),
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                    onNotification: (_) {
                      _lastManualInteraction = DateTime.now();
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 92),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: AssistantFieldScope(
                              controller: _assistant,
                              anchors: _fieldAnchors,
                              step: _currentStep,
                              party: _partyTab,
                              child: Form(
                                key: _formKeys[_currentStep],
                                onChanged: _formChanged,
                                child: _buildStep(),
                              )),
                        ),
                      ),
                    )),
              ),
              if (widget.adminSession == null &&
                  !_submitting &&
                  AppRuntime.assistantEnabled)
                SaudiVoiceAssistant(controller: _assistant),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
                decoration: BoxDecoration(
                  color: context.ejarzTheme.surface,
                  border: Border(
                    top: BorderSide(color: context.ejarzTheme.border),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: PrimaryButton(
                              label: _currentStep == _steps.length - 1
                                  ? 'إرسال الطلب'
                                  : 'التالي',
                              icon: _currentStep == _steps.length - 1
                                  ? Icons.lock_outline_rounded
                                  : null,
                              onPressed: _currentStep == _steps.length - 1
                                  ? _submit
                                  : _next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SecondaryButton(
                              label: _currentStep == 0 ? 'إلغاء' : 'السابق',
                              onPressed: _previous,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_currentStep) {
      0 => _TypeStep(
          draft: _draft,
          onChanged: _markChanged,
          renewalMode: widget.renewalMode,
          renewalSourceNumber: widget.renewalSourceNumber,
        ),
      1 => _OwnershipStep(
          draft: _draft,
          onChanged: _markChanged,
        ),
      2 => _PartiesStep(
          draft: _draft,
          selectedTab: _partyTab,
          onTabChanged: (value) => setState(() => _partyTab = value),
          onChanged: _markChanged,
        ),
      3 => _PropertyStep(
          draft: _draft,
          onChanged: _markChanged,
        ),
      4 => _FinancialStep(
          draft: _draft,
          onChanged: _markChanged,
        ),
      5 => _AttachmentsStep(
          draft: _draft,
          adminSession: widget.adminSession,
          requiredAttachments: _requiredAttachments,
          onChanged: _markChanged,
        ),
      6 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.adminSession != null)
            AdminContractFeePanel(
                session: widget.adminSession!,
                draft: _draft,
                onChanged: _markChanged),
          ContractReview(
              draft: _draft,
              requiredAttachments: _requiredAttachments,
              onChanged: _markChanged,
              administrative: widget.adminSession != null),
        ]),
      _ => const SizedBox.shrink(),
    };
  }
}

class _TypeStep extends StatelessWidget {
  final ContractDraft draft;
  final VoidCallback onChanged;
  final bool renewalMode;
  final String renewalSourceNumber;

  const _TypeStep({
    required this.draft,
    required this.onChanged,
    required this.renewalMode,
    required this.renewalSourceNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppPageHeader(
          title: renewalMode ? 'تجديد عقد قائم' : 'إنشاء عقد جديد',
          subtitle: renewalMode
              ? 'راجع نوع العقد المنسوخ وبياناته قبل إنشاء طلب التجديد.'
              : 'اختر نوع العقد وتصنيف الوحدة للبدء.',
          icon: renewalMode
              ? Icons.refresh_rounded
              : Icons.add_home_work_outlined,
        ),
        if (renewalMode) ...<Widget>[
          const SizedBox(height: 12),
          InfoBanner(
            text: renewalSourceNumber.trim().isEmpty
                ? 'نوع العقد محفوظ من العقد السابق ولا يمكن تغييره أثناء التجديد.'
                : 'يتم إنشاء طلب تجديد جديد بالاعتماد على العقد رقم $renewalSourceNumber. نوع العقد محفوظ من الطلب السابق.',
            icon: Icons.lock_outline_rounded,
            color: AppColors.blue,
          ),
        ],
        const SizedBox(height: 16),
        SectionTitle(
          title: renewalMode ? 'نوع العقد الأصلي' : 'اختر نوع العقد',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = <Widget>[
              _ContractTypeCard(
                type: ContractType.residential,
                selected: draft.type == ContractType.residential,
                enabled: !renewalMode,
                onTap: () {
                  _applyContractType(draft, ContractType.residential);
                  onChanged();
                },
              ),
              _ContractTypeCard(
                type: ContractType.commercial,
                selected: draft.type == ContractType.commercial,
                enabled: !renewalMode,
                onTap: () {
                  _applyContractType(draft, ContractType.commercial);
                  onChanged();
                },
              ),
            ];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: cards[0]),
                SizedBox(width: constraints.maxWidth >= 540 ? 12 : 8),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        AppDropdownField(
          label: 'تصنيف الوحدة',
          value: draft.property.unitType,
          items: draft.type == ContractType.residential
              ? const <String>['فيلا', 'شقة', 'عمارة']
              : const <String>['محل', 'مستودع', 'مكتب إداري'],
          required: true,
          icon: draft.type.icon,
          onChanged: (value) {
            if (draft.property.propertySource.trim() != _newPropertySource) {
              draft.property = _newPropertyDataForContractType(draft.type);
            }
            draft.property.unitType = value!;
            draft.property.propertyType = value == 'مكتب إداري' ? 'برج' : value;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        const InfoBanner(
          text:
              'سيتم مراجعة بيانات العقد والمرفقات من فريق عقدك قبل إدخاله في منصة إيجار للتأكد من اكتمالها وصحتها.',
        ),
      ],
    );
  }
}

class _ContractTypeCard extends StatelessWidget {
  final ContractType type;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const _ContractTypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: ValueKey<String>('contract-type-${type.name}'),
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      border: Border.all(
        color: selected ? AppColors.primary : context.ejarzTheme.border,
        width: selected ? 1.8 : 1,
      ),
      color: selected ? AppColors.primary.withValues(alpha: 0.025) : null,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              PropertyIllustration(
                commercial: type == ContractType.commercial,
                size: 86,
              ),
              const SizedBox(height: 6),
              Text(
                type.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : context.ejarzTheme.text,
                  fontWeight: FontWeight.w900,
                  fontSize: context.sp(13.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                type.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  fontSize: context.sp(9.8),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                  '${ContractPrice.calculate(commercial: type == ContractType.commercial).firstYear.toStringAsFixed(0)} ريال للسنة الأولى',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(11))),
              const SizedBox(height: 7),
              Container(width: 28, height: 2, color: AppColors.secondary),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected ? AppColors.primary : context.ejarzTheme.border,
                ),
              ),
              child: selected
                  ? Icon(
                      enabled ? Icons.check_rounded : Icons.lock_rounded,
                      key: ValueKey<String>(
                        'contract-type-selected-${type.name}',
                      ),
                      color: Colors.white,
                      size: 15,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnershipStep extends StatelessWidget {
  final ContractDraft draft;
  final VoidCallback onChanged;

  const _OwnershipStep({required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final property = draft.property;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'بيانات الملكية',
          subtitle: 'أدخل وثيقة الملكية كما ستتم مراجعتها قبل توثيق العقد.',
          icon: Icons.verified_outlined,
        ),
        const SizedBox(height: 16),
        const SectionTitle(
          title: 'نوع الإثبات والوثيقة',
          icon: Icons.file_present_outlined,
        ),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            AppDropdownField(
              label: 'نوع الإثبات',
              value: property.ownershipDocumentType,
              items: const <String>[
                'صك إلكتروني',
                'تسجيل عيني',
              ],
              required: true,
              icon: Icons.fact_check_outlined,
              onChanged: (value) {
                property.ownershipDocumentType = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'رقم الوثيقة',
              hint: 'أدخل رقم الوثيقة',
              initialValue: property.ownershipDocumentNumber,
              icon: Icons.description_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              required: true,
              onChanged: (value) => property.ownershipDocumentNumber = value,
              validator: _requiredOwnershipDocumentNumber,
            ),
            DateField(
              label: 'تاريخ الوثيقة',
              value: property.ownershipDocumentDate,
              required: true,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              validator: _ownershipDateError,
              onChanged: (value) {
                property.ownershipDocumentDate = value;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        const InfoBanner(
          text:
              'بيانات الملكية منفصلة عن بيانات العقار حتى يسهل التحقق من الوثيقة قبل إدخال العقد في منصة إيجار.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

class _PropertyStep extends StatelessWidget {
  final ContractDraft draft;
  final VoidCallback onChanged;

  const _PropertyStep({required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final property = draft.property;
    final savedOptions =
        _savedPropertyOptions(controller.properties, draft.type);
    final propertySourceItems = <String>[
      _newPropertySource,
      ...savedOptions.map((option) => option.label),
    ];
    final selectedSource = property.propertySource.trim().isEmpty
        ? _newPropertySource
        : property.propertySource;
    final savedProperty = controller.properties
        .where((p) => p.id == property.savedPropertyId)
        .firstOrNull;
    return Column(
      key: ValueKey<String>('property-step-$selectedSource'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'بيانات العقار والوحدة',
          subtitle: 'أدخل تفاصيل العقار والوحدة بدقة كما ستظهر في العقد.',
          icon: Icons.apartment_rounded,
        ),
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'بيانات العقار', icon: Icons.business_outlined),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            AppDropdownField(
              label: 'مصدر العقار',
              value: selectedSource,
              items: propertySourceItems,
              required: true,
              icon: Icons.apartment_outlined,
              onChanged: (value) {
                final selected = value ?? _newPropertySource;
                _SavedPropertyOption? savedOption;
                for (final option in savedOptions) {
                  if (option.label == selected) {
                    savedOption = option;
                    break;
                  }
                }
                if (savedOption == null) {
                  draft.property = selected == _newPropertySource
                      ? _newPropertyDataForContractType(draft.type)
                      : (property..propertySource = selected);
                } else {
                  draft.property = _propertyDataFromRecord(
                    savedOption.property,
                    savedOption.label,
                  );
                }
                onChanged();
              },
            ),
            if (savedProperty?.managesUnits == true)
              AppDropdownField(
                label: 'الوحدة داخل العمارة',
                value: property.unitNumber.isEmpty
                    ? 'اختر الوحدة'
                    : '${property.unitNumber} • ${property.unitName}',
                items: [
                  'اختر الوحدة',
                  for (final unit in savedProperty!.units)
                    if (unit.isAvailable || unit.number == property.unitNumber)
                      '${unit.number} • ${unit.name}'
                ],
                required: true,
                icon: Icons.meeting_room_outlined,
                onChanged: (value) {
                  final unit = savedProperty.units
                      .where((u) => '${u.number} • ${u.name}' == value)
                      .firstOrNull;
                  if (unit == null) return;
                  draft.property = unit.detailsFor(savedProperty)
                    ..propertySource = selectedSource;
                  onChanged();
                },
              ),
            if (savedProperty?.managesUnits == true &&
                savedProperty!.units.isEmpty)
              const InfoBanner(
                  text:
                      'لم تُضف وحدات لهذه العمارة بعد. أضف الوحدات من «عقاراتي» ثم اختر الوحدة المطلوبة.'),
            const LoadMoreRecords('properties'),
            AppDropdownField(
              label: 'استخدام العقار',
              value: property.propertyUsage,
              items: const <String>[
                'سكن عوائل',
                'سكن أفراد',
                'سكن جماعي',
                'تجاري',
              ],
              icon: Icons.home_work_outlined,
              onChanged: (value) {
                property.propertyUsage = value!;
                onChanged();
              },
            ),
            AppDropdownField(
              label: 'نوع العقار الرئيسي',
              value: property.propertyType,
              items: const <String>[
                'عمارة',
                'برج',
                'أرض',
                'شقة',
                'فيلا',
              ],
              icon: Icons.apartment_rounded,
              onChanged: (value) {
                property.propertyType = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'عدد الأدوار',
              hint: 'مثال: 4',
              initialValue: property.floorsCount,
              icon: Icons.layers_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              required: true,
              onChanged: (value) => property.floorsCount = value,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 200),
            ),
            AppTextField(
              label: 'عدد الوحدات في كل دور',
              hint: 'مثال: 2',
              initialValue: property.unitsPerFloor,
              icon: Icons.grid_view_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              required: false,
              onChanged: (value) => property.unitsPerFloor = value,
              validator: (value) => value?.trim().isEmpty == true
                  ? null
                  : _requiredPositiveInt(value, min: 1, max: 200),
            ),
            AppTextField(
              label: 'إجمالي عدد الوحدات',
              hint: 'مثال: 8',
              initialValue: property.totalUnits,
              icon: Icons.format_list_numbered_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              required: true,
              onChanged: (value) => property.totalUnits = value,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 9999),
            ),
            SaudiLocationFields(
              city: property.city,
              cityReferenceId: property.cityReferenceId,
              districtReferenceId: property.districtReferenceId,
              onReferencesChanged: (cityId, districtId) {
                property.cityReferenceId = cityId;
                property.districtReferenceId = districtId;
              },
              district: property.district,
              onCityChanged: (value) {
                property.city = value;
                onChanged();
              },
              onDistrictChanged: (value) {
                property.district = value;
                onChanged();
              },
            ),
            AppTextField(
              label: 'الشارع',
              hint: 'اسم الشارع',
              initialValue: property.street,
              icon: Icons.signpost_outlined,
              required: true,
              onChanged: (value) => property.street = value,
              validator: _requiredName,
            ),
            AppTextField(
              label: 'اسم العقار أو المبنى',
              hint: 'مثال: عمارة النرجس',
              initialValue: property.buildingName,
              icon: Icons.domain_outlined,
              onChanged: (value) => property.buildingName = value,
            ),
            AppTextField(
              label: 'رقم المبنى',
              hint: 'رقم المبنى',
              initialValue: property.buildingNumber,
              icon: Icons.numbers_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              required: true,
              onChanged: (value) => property.buildingNumber = value,
              validator: (value) =>
                  _requiredFixedDigits(value, 4, 'رقم المبنى'),
            ),
            AppTextField(
              label: 'الرقم الإضافي',
              hint: 'الرقم الإضافي',
              initialValue: property.additionalNumber,
              icon: Icons.add_box_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              required: true,
              onChanged: (value) => property.additionalNumber = value,
              validator: (value) =>
                  _requiredFixedDigits(value, 4, 'الرقم الإضافي'),
            ),
            AppTextField(
              label: 'الرمز البريدي',
              hint: 'الرمز البريدي',
              initialValue: property.postalCode,
              icon: Icons.markunread_mailbox_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              required: true,
              onChanged: (value) => property.postalCode = value,
              validator: (value) =>
                  _requiredFixedDigits(value, 5, 'الرمز البريدي'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(10),
          shadows: const <BoxShadow>[],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      property.displayAddress,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'بيانات الوحدة', icon: Icons.home_outlined),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            AppTextField(
              label: 'رقم الوحدة',
              hint: 'أدخل رقم الوحدة',
              initialValue: property.unitNumber,
              icon: Icons.tag_rounded,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(20),
              ],
              required: true,
              onChanged: (value) => property.unitNumber = value,
              validator: _requiredValue,
            ),
            AppTextField(
              label: 'اسم الوحدة',
              hint: 'مثال: شقة 101',
              initialValue: property.unitName,
              icon: Icons.drive_file_rename_outline,
              required: true,
              onChanged: (value) => property.unitName = value,
              validator: _requiredName,
            ),
            AppDropdownField(
              label: 'نوع الوحدة',
              value: property.unitType,
              items: draft.type == ContractType.residential
                  ? const <String>['شقة', 'استديو', 'دور', 'فيلا']
                  : const <String>['محل', 'مستودع', 'مكتب إداري'],
              icon: draft.type.icon,
              onChanged: (value) {
                property.unitType = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'رقم الدور',
              hint: 'مثال: 3، أو 0 للأرضي',
              initialValue: property.floor,
              keyboardType: TextInputType.number,
              icon: Icons.layers_outlined,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(12),
              ],
              required: true,
              onChanged: (value) => property.floor = value,
              validator: _requiredValue,
            ),
            AppTextField(
              label: 'مساحة الوحدة (م²)',
              hint: 'أدخل المساحة',
              initialValue: property.area,
              icon: Icons.square_foot_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              required: true,
              onChanged: (value) => property.area = value,
              validator: _requiredPositiveNumber,
            ),
            AppDropdownField(
              label: 'حالة التأثيث',
              value: property.furnishingStatus,
              items: const <String>[
                'غير مؤثثة',
                'مؤثثة بأثاث جديد',
                'مؤثثة بأثاث مستخدم',
              ],
              icon: Icons.chair_outlined,
              onChanged: (value) {
                property.furnishingStatus = value!;
                onChanged();
              },
            ),
            if (draft.type == ContractType.residential)
              AppTextField(
                label: 'عدد الغرف',
                hint: 'أدخل عدد الغرف',
                initialValue: property.roomsCount,
                icon: Icons.bed_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                required: true,
                onChanged: (value) => property.roomsCount = value,
                validator: (value) =>
                    _requiredPositiveInt(value, min: 1, max: 50),
              ),
            AppTextField(
              label: 'دورات المياه',
              hint: 'أدخل العدد',
              initialValue: property.bathroomsCount,
              icon: Icons.bathtub_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: (value) => property.bathroomsCount = value,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 50),
            ),
            AppTextField(
              label: 'الصالات',
              hint: 'أدخل العدد',
              initialValue: property.hallsCount,
              icon: Icons.weekend_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: (value) => property.hallsCount = value,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 0, max: 50),
            ),
            AppTextField(
              label: 'رقم عداد الكهرباء',
              hint: 'اختياري، إن وجد',
              initialValue: property.electricityMeter,
              icon: Icons.bolt_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (value) => property.electricityMeter = value,
              validator: validateUnitMeterNumber,
            ),
            AppTextField(
              label: 'رقم عداد المياه',
              hint: 'إن وجد',
              initialValue: property.waterMeter,
              icon: Icons.water_drop_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (value) => property.waterMeter = value,
              validator: validateUnitMeterNumber,
            ),
            AppTextField(
              label: 'رقم عداد الغاز',
              hint: 'إن وجد',
              initialValue: property.gasMeter,
              icon: Icons.local_fire_department_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (value) => property.gasMeter = value,
              validator: validateUnitMeterNumber,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionTitle(title: 'مرافق الوحدة', icon: Icons.widgets_outlined),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _FeatureToggle(
              label: 'غرفة خادمة',
              selected: property.maidRoom,
              onSelected: (value) {
                property.maidRoom = value;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        FieldGrid(children: [
          UnitCountField(
              label: 'المطبخ',
              value: property.kitchenCount,
              icon: Icons.countertops_outlined,
              onChanged: (value) {
                property.kitchenCount = value;
                onChanged();
              }),
          UnitCountField(
              label: 'المجلس',
              value: property.majlisCount,
              icon: Icons.weekend_outlined,
              onChanged: (value) {
                property.majlisCount = value;
                onChanged();
              }),
          UnitCountField(
              label: 'المخزن',
              value: property.storageCount,
              icon: Icons.inventory_2_outlined,
              onChanged: (value) {
                property.storageCount = value;
                onChanged();
              }),
        ]),
        const SizedBox(height: 14),
        const SectionTitle(title: 'التكييف', icon: Icons.ac_unit_outlined),
        const SizedBox(height: 8),
        FieldGrid(children: [
          for (final item
              in <(String, String, IconData, void Function(String))>[
            (
              'عدد مكيفات الشباك',
              property.acWindowCount,
              Icons.window_outlined,
              (value) {
                property.acWindowCount = value;
                property.acWindow = (int.tryParse(value) ?? 0) > 0;
                onChanged();
              }
            ),
            (
              'عدد مكيفات السبليت',
              property.acSplitCount,
              Icons.ac_unit_outlined,
              (value) {
                property.acSplitCount = value;
                property.acSplit = (int.tryParse(value) ?? 0) > 0;
                onChanged();
              }
            ),
            (
              'عدد أجهزة التكييف المركزي',
              property.acCentralCount,
              Icons.air_outlined,
              (value) {
                property.acCentralCount = value;
                property.acCentral = (int.tryParse(value) ?? 0) > 0;
                onChanged();
              }
            ),
          ])
            UnitCountField(
                label: item.$1,
                value: item.$2,
                icon: item.$3,
                onChanged: item.$4),
        ]),
        const SizedBox(height: 14),
        ToggleCard(
          title: 'يوجد موقف خاص',
          subtitle: 'فعّل الخيار إذا كانت الوحدة لها موقف سيارة خاص',
          value: property.privateParking,
          icon: Icons.local_parking_outlined,
          onChanged: (value) {
            property.privateParking = value;
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'ملاحظات على الوحدة',
          hint: 'أي تفاصيل إضافية مهمة عن العقار أو الوحدة',
          initialValue: property.notes,
          icon: Icons.notes_rounded,
          maxLines: 3,
          onChanged: (value) => property.notes = value,
        ),
      ],
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _FeatureToggle({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      showCheckmark: true,
      label: Text(label),
      avatar: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 16,
        color: selected ? AppColors.primary : context.ejarzTheme.muted,
      ),
      selectedColor: AppColors.primaryLight,
      side: BorderSide(
        color: selected ? AppColors.primary : context.ejarzTheme.border,
      ),
      onSelected: onSelected,
    );
  }
}

class _PartiesStep extends StatelessWidget {
  final ContractDraft draft;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onChanged;

  const _PartiesStep({
    required this.draft,
    required this.selectedTab,
    required this.onTabChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <String>['المؤجر', 'المستأجر', 'الوكيل / المفوض'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'بيانات الأطراف',
          subtitle: 'أدخل بيانات المؤجر والمستأجر كما هي في الوثائق الرسمية.',
          icon: Icons.people_outline_rounded,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.ejarzTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.ejarzTheme.border),
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTabChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 4),
                      decoration: BoxDecoration(
                        color: selectedTab == i
                            ? AppColors.primaryLight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: selectedTab == i
                            ? Border.all(color: AppColors.primary)
                            : null,
                      ),
                      child: Text(
                        tabs[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selectedTab == i
                              ? AppColors.primary
                              : context.ejarzTheme.text,
                          fontWeight: FontWeight.w800,
                          fontSize: context.sp(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (selectedTab != 2 && AppRuntime.service('savedParties')) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            TextButton.icon(
                icon: const Icon(Icons.people_outline),
                label: const Text('اختيار طرف محفوظ'),
                onPressed: () async {
                  final party = await chooseSavedParty(context);
                  if (party != null) {
                    if (selectedTab == 0) {
                      draft.lessor = party;
                    } else {
                      draft.tenant = party;
                    }
                    onChanged();
                  }
                }),
            TextButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('حفظ الطرف'),
                onPressed: () => editSavedParty(context,
                    initial: selectedTab == 0 ? draft.lessor : draft.tenant)),
          ]),
          const SizedBox(height: 12),
        ],
        if (selectedTab == 0)
          _PartyForm(
            key: ValueKey<String>(
                'lessor-${draft.lessor.kind.name}-${identityHashCode(draft.lessor)}'),
            title: 'بيانات المؤجر',
            data: draft.lessor,
            isLessor: true,
            onChanged: onChanged,
          )
        else if (selectedTab == 1)
          _PartyForm(
            key: ValueKey<String>(
                'tenant-${draft.tenant.kind.name}-${identityHashCode(draft.tenant)}'),
            title: 'بيانات المستأجر',
            data: draft.tenant,
            isLessor: false,
            onChanged: onChanged,
          )
        else
          _RepresentativeForm(
            data: draft.representative,
            onChanged: onChanged,
          ),
        const SizedBox(height: 16),
        if (selectedTab != 2)
          InfoBanner(
            text: selectedTab == 0
                ? 'يجب أن تكون بيانات المؤجر متطابقة مع وثيقة الملكية، ويطلب الآيبان عند استخدام قنوات الدفع المرتبطة بالعقد.'
                : 'سيتم إرسال إشعارات التوثيق إلى رقم جوال المستأجر المدخل، لذلك تحقق من صحته وأنه متاح لصاحبه.',
          ),
      ],
    );
  }
}

class _PartyForm extends StatelessWidget {
  final String title;
  final PartyData data;
  final bool isLessor;
  final VoidCallback onChanged;

  const _PartyForm({
    super.key,
    required this.title,
    required this.data,
    required this.isLessor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionTitle(title: title, icon: Icons.person_outline_rounded),
        const SizedBox(height: 12),
        SegmentedChoice<PartyKind>(
          values: PartyKind.values,
          selected: data.kind,
          labelBuilder: (value) =>
              value == PartyKind.individual ? 'فرد' : 'منشأة',
          iconBuilder: (value) => value == PartyKind.individual
              ? Icons.person_outline_rounded
              : Icons.business_outlined,
          onChanged: (value) {
            data.kind = value;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        if (data.kind == PartyKind.individual)
          FieldGrid(
            children: <Widget>[
              AppTextField(
                label: 'الاسم الكامل',
                hint: 'أدخل الاسم كما في الهوية',
                initialValue: data.fullName,
                icon: Icons.person_outline_rounded,
                required: true,
                onChanged: (value) => data.fullName = value,
                validator: _requiredName,
              ),
              AppDropdownField(
                label: 'نوع الهوية',
                value: data.idType,
                items: const <String>[
                  'هوية وطنية',
                  'إقامة',
                  'هوية خليجية',
                  'جواز سفر',
                ],
                icon: Icons.badge_outlined,
                onChanged: (value) {
                  data.idType = value!;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'رقم الهوية',
                hint: 'أدخل رقم الهوية',
                initialValue: data.idNumber,
                icon: Icons.badge_outlined,
                keyboardType: data.idType == 'جواز سفر'
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: data.idType == 'جواز سفر'
                    ? <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(15),
                      ]
                    : <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          data.idType == 'هوية خليجية' ? 15 : 10,
                        ),
                      ],
                required: true,
                onChanged: (value) => data.idNumber = value,
                validator: (value) =>
                    validateContractIdentityNumber(value, data.idType),
              ),
              DateField(
                label: 'تاريخ الميلاد',
                value: data.birthDate,
                required: true,
                firstDate: DateTime(1900),
                lastDate: adultBirthDateCutoff(),
                validator: validateAdultBirthDate,
                onChanged: (value) {
                  data.birthDate = value;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'رقم جوال أبشر',
                hint: '05xxxxxxxx',
                initialValue: data.mobile,
                icon: Icons.phone_android_rounded,
                keyboardType: TextInputType.phone,
                required: true,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (value) => data.mobile = value,
                validator: _requiredSaudiMobile,
              ),
              AppTextField(
                label: 'البريد الإلكتروني',
                hint: 'name@example.com',
                initialValue: data.email,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) => data.email = value,
                validator: _optionalEmail,
              ),
            ],
          )
        else
          FieldGrid(
            children: <Widget>[
              AppTextField(
                label: 'اسم المنشأة',
                hint: 'الاسم التجاري للمنشأة',
                initialValue: data.fullName,
                icon: Icons.business_outlined,
                required: true,
                onChanged: (value) => data.fullName = value,
                validator: _requiredName,
              ),
              AppTextField(
                label: 'رقم السجل التجاري',
                hint: 'أدخل رقم السجل التجاري',
                initialValue: data.commercialRegistration,
                icon: Icons.article_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                required: true,
                onChanged: (value) => data.commercialRegistration = value,
                validator: _requiredCrNumber,
              ),
              AppTextField(
                label: 'الرقم الموحد',
                hint: 'رقم المنشأة الموحد',
                initialValue: data.unifiedNumber,
                icon: Icons.numbers_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                required: true,
                onChanged: (value) => data.unifiedNumber = value,
                validator: _requiredUnifiedNumber,
              ),
              AppTextField(
                label: 'اسم المفوض بالتوقيع',
                hint: 'الاسم الكامل للمفوض',
                initialValue: data.authorizedPersonName,
                icon: Icons.person_pin_outlined,
                required: true,
                onChanged: (value) => data.authorizedPersonName = value,
                validator: _requiredName,
              ),
              AppTextField(
                label: 'هوية المفوض',
                hint: 'رقم هوية المفوض',
                initialValue: data.authorizedPersonId,
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                required: true,
                onChanged: (value) => data.authorizedPersonId = value,
                validator: _requiredSaudiPersonId,
              ),
              AppTextField(
                label: 'رقم جوال أبشر',
                hint: 'رقم جوال أبشر للمفوض',
                initialValue: data.mobile,
                icon: Icons.phone_android_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                required: true,
                onChanged: (value) => data.mobile = value,
                validator: _requiredSaudiMobile,
              ),
              AppTextField(
                label: 'البريد الإلكتروني',
                hint: 'company@example.com',
                initialValue: data.email,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) => data.email = value,
                validator: _optionalEmail,
              ),
            ],
          ),
        const SizedBox(height: 14),
        ToggleCard(
          title: 'الجوال مسجل في أبشر',
          subtitle: 'تأكيد جاهزية الرقم لاستقبال إشعارات التوثيق',
          value: data.mobileRegisteredInAbsher,
          icon: Icons.verified_user_outlined,
          onChanged: (value) {
            data.mobileRegisteredInAbsher = value;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        const SectionTitle(
            title: 'العنوان الوطني', icon: Icons.location_on_outlined),
        const SizedBox(height: 12),
        SaudiLocationFields(
          city: data.city,
          cityReferenceId: data.cityReferenceId,
          districtReferenceId: data.districtReferenceId,
          onReferencesChanged: (cityId, districtId) {
            data.cityReferenceId = cityId;
            data.districtReferenceId = districtId;
          },
          district: data.district,
          onCityChanged: (value) {
            data.city = value;
            onChanged();
          },
          onDistrictChanged: (value) {
            data.district = value;
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'تفاصيل العنوان الوطني',
          hint: 'رقم المبنى، الشارع، الرمز البريدي...',
          initialValue: data.nationalAddress,
          icon: Icons.home_outlined,
          maxLines: 2,
          required: true,
          onChanged: (value) => data.nationalAddress = value,
          validator: _requiredValue,
        ),
        if (isLessor) ...<Widget>[
          const SizedBox(height: 14),
          const SectionTitle(
            title: 'البيانات البنكية للمؤجر',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 12),
          FieldGrid(
            children: <Widget>[
              AppTextField(
                label: 'رقم الآيبان',
                hint: 'SA00 0000 0000 0000 0000 0000',
                initialValue: data.iban,
                icon: Icons.account_balance_outlined,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                  LengthLimitingTextInputFormatter(29),
                ],
                required: true,
                onChanged: (value) => data.iban = value,
                validator: _requiredIban,
              ),
              SaudiBankField(
                value: data.bankName,
                onChanged: (value) {
                  data.bankName = value;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'اسم صاحب الحساب',
                hint: 'كما يظهر في البنك',
                initialValue: data.accountOwner,
                icon: Icons.person_outline_rounded,
                onChanged: (value) => data.accountOwner = value,
                required: true,
                validator: _requiredName,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RepresentativeForm extends StatelessWidget {
  final RepresentativeData data;
  final VoidCallback onChanged;

  const _RepresentativeForm({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ToggleCard(
          title: 'يوجد ممثل قانوني أو وكيل',
          subtitle: 'فعّل هذا الخيار عند وجود وكالة أو سند تمثيل رسمي',
          value: data.enabled,
          icon: Icons.gavel_outlined,
          onChanged: (value) {
            data.enabled = value;
            onChanged();
          },
        ),
        if (data.enabled) ...<Widget>[
          const SizedBox(height: 12),
          FieldGrid(
            children: <Widget>[
              AppDropdownField(
                label: 'يمثل من؟',
                value: data.represents,
                items: const <String>['المؤجر', 'المستأجر'],
                icon: Icons.people_outline_rounded,
                onChanged: (value) {
                  data.represents = value!;
                  onChanged();
                },
              ),
              AppDropdownField(
                label: 'نوع الممثل',
                value: data.type,
                items: const <String>['وكيل', 'وصي', 'ولي', 'ممثل منشأة'],
                icon: Icons.badge_outlined,
                onChanged: (value) {
                  data.type = value!;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'الاسم الكامل',
                hint: 'اسم الممثل أو الوكيل',
                initialValue: data.fullName,
                icon: Icons.person_outline_rounded,
                required: true,
                onChanged: (value) => data.fullName = value,
                validator: _requiredName,
              ),
              AppDropdownField(
                label: 'نوع الهوية',
                value: data.idType,
                items: const <String>['هوية وطنية', 'إقامة', 'هوية خليجية'],
                icon: Icons.badge_outlined,
                onChanged: (value) {
                  data.idType = value!;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'رقم الهوية',
                hint: 'رقم هوية الممثل',
                initialValue: data.idNumber,
                icon: Icons.badge_outlined,
                keyboardType: data.idType == 'جواز سفر'
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: data.idType == 'جواز سفر'
                    ? <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(15),
                      ]
                    : <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          data.idType == 'هوية خليجية' ? 15 : 10,
                        ),
                      ],
                required: true,
                onChanged: (value) => data.idNumber = value,
                validator: (value) =>
                    validateContractIdentityNumber(value, data.idType),
              ),
              DateField(
                label: 'تاريخ الميلاد',
                value: data.birthDate,
                required: true,
                firstDate: DateTime(1900),
                lastDate: adultBirthDateCutoff(),
                validator: validateAdultBirthDate,
                onChanged: (value) {
                  data.birthDate = value;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'رقم جوال أبشر',
                hint: '05xxxxxxxx',
                initialValue: data.mobile,
                icon: Icons.phone_android_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                required: true,
                onChanged: (value) => data.mobile = value,
                validator: _requiredSaudiMobile,
              ),
              AppTextField(
                label: 'رقم الوكالة أو السند',
                hint: 'أدخل رقم الوثيقة',
                initialValue: data.authorizationNumber,
                icon: Icons.article_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
                required: true,
                onChanged: (value) => data.authorizationNumber = value,
                validator: (value) =>
                    _requiredReferenceNumber(value, 'رقم الوكالة أو التفويض'),
              ),
              DateField(
                label: 'تاريخ الوكالة',
                value: data.authorizationDate,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                validator: _optionalDateError,
                onChanged: (value) {
                  data.authorizationDate = value;
                  onChanged();
                },
              ),
              AppTextField(
                label: 'جهة الإصدار',
                hint: 'مثال: وزارة العدل',
                initialValue: data.issuer,
                icon: Icons.account_balance_outlined,
                onChanged: (value) => data.issuer = value,
              ),
              DateField(
                label: 'تاريخ الانتهاء',
                value: data.expiryDate,
                firstDate:
                    _parseAppDate(data.authorizationDate) ?? DateTime(1900),
                lastDate: DateTime(2200),
                validator: _optionalDateError,
                onChanged: (value) {
                  data.expiryDate = value;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          const InfoBanner(
            text:
                'ستظهر وثيقة الوكالة أو التفويض ضمن المرفقات المطلوبة في الخطوة التالية.',
          ),
        ],
      ],
    );
  }
}

class _FinancialStep extends StatelessWidget {
  final ContractDraft draft;
  final VoidCallback onChanged;

  const _FinancialStep({required this.draft, required this.onChanged});

  void _updatePaymentCount(String value) {
    final parsed = int.tryParse(value);
    draft.paymentCount = parsed ?? 0;
    onChanged();
  }

  DateTime? _parseDate(String value) {
    final parts = value.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  String _formatDate(DateTime value) {
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  void _recalculateEndDate() {
    final start = _parseDate(draft.startDate);
    if (start == null) return;
    final years = int.tryParse(draft.durationYears) ?? 0;
    final months = int.tryParse(draft.durationMonths) ?? 0;
    final days = int.tryParse(draft.durationDays) ?? 0;
    final totalMonth = start.month + months;
    final targetYear = start.year + years + ((totalMonth - 1) ~/ 12);
    final targetMonth = ((totalMonth - 1) % 12) + 1;
    final targetDay =
        start.day.clamp(1, _daysInMonth(targetYear, targetMonth)).toInt();
    final end = DateTime.utc(targetYear, targetMonth, targetDay)
        .add(Duration(days: days))
        .subtract(const Duration(days: 1));
    draft.endDate = _formatDate(end);
  }

  @override
  Widget build(BuildContext context) {
    final calculation = draft.rentalCalculation;
    final installmentValue = (calculation?.installments.firstOrNull ?? 0) / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'البيانات المالية',
          subtitle:
              'حدد مدة العقد وقيمة الإيجار وطريقة السداد والرسوم المرتبطة بالطلب.',
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'مدة العقد', icon: Icons.event_available_outlined),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            DateField(
              label: 'تاريخ بداية العقد',
              value: draft.startDate,
              required: true,
              onChanged: (value) {
                draft.startDate = value;
                _recalculateEndDate();
                if (draft.firstPaymentDate.isEmpty) {
                  draft.firstPaymentDate = value;
                }
                onChanged();
              },
            ),
            AppTextField(
              label: 'تاريخ نهاية العقد',
              hint: 'يُحسب تلقائيًا من البداية والمدة',
              key: ValueKey('contract-end-${draft.endDate}'),
              initialValue: draft.endDate,
              readOnly: true,
              required: true,
              icon: Icons.event_available_outlined,
            ),
            AppTextField(
              label: 'عدد السنوات',
              hint: 'مثال: 1',
              initialValue: draft.durationYears,
              icon: Icons.calendar_view_month_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: (value) {
                draft.durationYears = value;
                _recalculateEndDate();
                onChanged();
              },
              validator: (value) =>
                  _requiredPositiveInt(value, min: 0, max: 50),
            ),
            AppTextField(
              label: 'عدد الأشهر',
              hint: 'مثال: 0',
              initialValue: draft.durationMonths,
              icon: Icons.calendar_month_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: (value) {
                draft.durationMonths = value;
                _recalculateEndDate();
                onChanged();
              },
              validator: (value) =>
                  _requiredPositiveInt(value, min: 0, max: 11),
            ),
            AppTextField(
              label: 'عدد الأيام',
              hint: 'مثال: 0',
              initialValue: draft.durationDays,
              icon: Icons.today_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: (value) {
                draft.durationDays = value;
                _recalculateEndDate();
                onChanged();
              },
              validator: (value) =>
                  _requiredPositiveInt(value, min: 0, max: 30),
            ),
            AppDropdownField(
              label: 'دورة سداد الإيجار',
              value: draft.rentPeriod,
              items: const <String>[
                'شهري',
                'ربع سنوي',
                'نصف سنوي',
                'سنوي',
                'دفعة واحدة',
                'مخصص',
              ],
              icon: Icons.repeat_rounded,
              onChanged: (value) {
                draft.rentPeriod = value!;
                if (value == 'دفعة واحدة' || value == 'مخصص') {
                  draft.paymentScheduleType = value;
                } else {
                  draft.paymentFrequency = value;
                  draft.paymentScheduleType = 'دوري';
                }
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'المبالغ والرسوم',
            icon: Icons.account_balance_wallet_outlined),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            AppTextField(
              label: 'مبلغ الإيجار السنوي',
              hint: 'أدخل مبلغ الإيجار السنوي',
              initialValue: draft.rentValue,
              icon: Icons.payments_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              required: true,
              onChanged: (value) {
                draft.rentValue = value;
                onChanged();
              },
              validator: _requiredPositiveAmount,
            ),
            ToggleCard(
              title: 'هل يوجد ضمان؟',
              subtitle: draft.hasSecurityDeposit
                  ? 'سيتم طلب قيمة الضمان ضمن بيانات العقد'
                  : 'لا يوجد ضمان على هذا العقد',
              value: draft.hasSecurityDeposit,
              icon: Icons.savings_outlined,
              onChanged: (value) {
                draft.hasSecurityDeposit = value;
                if (!value) draft.securityDeposit = '';
                onChanged();
              },
            ),
            if (draft.hasSecurityDeposit)
              AppTextField(
                label: 'قيمة الضمان',
                hint: 'أدخل قيمة الضمان',
                initialValue: draft.securityDeposit,
                icon: Icons.savings_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                required: true,
                onChanged: (value) {
                  draft.securityDeposit = value;
                  onChanged();
                },
                validator: _requiredPositiveAmount,
              ),
            AppTextField(
              label: 'عمولة السعي',
              hint: 'إن وجدت',
              initialValue: draft.brokerageFee,
              icon: Icons.handshake_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              onChanged: (value) => draft.brokerageFee = value,
              validator: _optionalPositiveAmount,
            ),
            AppDropdownField(
              label: 'دافع عمولة السعي',
              value: draft.brokeragePayer,
              items: const <String>['المؤجر', 'المستأجر', 'مناصفة'],
              icon: Icons.person_outline_rounded,
              onChanged: (value) {
                draft.brokeragePayer = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'مبالغ أخرى',
              hint: 'رسوم أو بنود إضافية',
              initialValue: draft.otherAmounts,
              icon: Icons.add_card_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              onChanged: (value) => draft.otherAmounts = value,
              validator: _optionalPositiveAmount,
            ),
            if (draft.ownerSubjectToVat)
              AppTextField(
                label: 'قيمة ضريبة القيمة المضافة',
                hint: 'أدخل قيمة الضريبة',
                initialValue: draft.vatValue,
                icon: Icons.receipt_long_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                required: true,
                onChanged: (value) => draft.vatValue = value,
                validator: _requiredPositiveAmount,
              ),
          ],
        ),
        const SizedBox(height: 14),
        ToggleCard(
          title: 'المؤجر خاضع لضريبة القيمة المضافة',
          subtitle: 'فعّل هذا الخيار لإضافة قيمة الضريبة ضمن بيانات العقد',
          value: draft.ownerSubjectToVat,
          icon: Icons.percent_rounded,
          onChanged: (value) {
            draft.ownerSubjectToVat = value;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'جدولة الدفعات', icon: Icons.table_rows_outlined),
        const SizedBox(height: 12),
        FieldGrid(
          children: <Widget>[
            AppDropdownField(
              label: 'نوع الجدولة',
              value: draft.paymentScheduleType,
              items: const <String>['دوري', 'دفعة واحدة', 'مخصص'],
              icon: Icons.timeline_outlined,
              onChanged: (value) {
                draft.paymentScheduleType = value!;
                draft.rentPeriod =
                    value == 'دوري' ? draft.paymentFrequency : value;
                onChanged();
              },
            ),
            if (draft.paymentScheduleType == 'دوري')
              AppDropdownField(
                label: 'تكرار الدفع',
                value: draft.paymentFrequency,
                items: const <String>['شهري', 'ربع سنوي', 'نصف سنوي', 'سنوي'],
                icon: Icons.repeat_on_rounded,
                onChanged: (value) {
                  draft.paymentFrequency = value!;
                  draft.rentPeriod = value;
                  onChanged();
                },
              ),
            AppTextField(
              label: 'عدد الدفعات',
              hint: 'مثال: 4',
              key: draft.paymentScheduleType == 'مخصص'
                  ? const ValueKey('custom-payment-count')
                  : ValueKey(
                      'auto-payment-count-${calculation?.installments.length}'),
              initialValue:
                  '${draft.paymentScheduleType == 'مخصص' ? draft.paymentCount : calculation?.installments.length ?? 0}',
              readOnly: draft.paymentScheduleType != 'مخصص',
              icon: Icons.format_list_numbered_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              required: true,
              onChanged: _updatePaymentCount,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 1200),
            ),
            DateField(
              label: 'تاريخ أول دفعة',
              value: draft.firstPaymentDate,
              required: true,
              firstDate: _parseAppDate(draft.startDate),
              lastDate: _parseAppDate(draft.endDate)?.isBefore(
                          _parseAppDate(draft.startDate) ?? DateTime(1900)) ==
                      true
                  ? _parseAppDate(draft.startDate)
                  : _parseAppDate(draft.endDate),
              onChanged: (value) {
                draft.firstPaymentDate = value;
                onChanged();
              },
            ),
            AppDropdownField(
              label: 'قناة الدفع',
              value: draft.paymentChannel,
              items: const <String>[
                'سداد / إيجار',
                'تحويل بنكي',
                'خارج المنصة'
              ],
              icon: Icons.account_balance_outlined,
              onChanged: (value) {
                draft.paymentChannel = value!;
                onChanged();
              },
            ),
            AppDropdownField(
              label: 'دافع رسوم منصة إيجار',
              value: draft.officialFeePayer,
              items: const <String>['المؤجر', 'المستأجر', 'مناصفة'],
              icon: Icons.receipt_outlined,
              onChanged: (value) {
                draft.officialFeePayer = value!;
                onChanged();
              },
            ),
            AppDropdownField(
              label: 'دافع عمولة عقدك',
              value: draft.serviceFeePayer,
              items: const <String>['المؤجر', 'المستأجر', 'مناصفة'],
              icon: Icons.support_agent_outlined,
              onChanged: (value) {
                draft.serviceFeePayer = value!;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (draft.paymentScheduleType == 'مخصص') ...[
          const InfoBanner(
            text:
                'حدد عدد الدفعات؛ تُوزع المبالغ والتواريخ بالتساوي بين تاريخ أول دفعة ونهاية العقد، وتُضبط الدفعة الأخيرة لفارق التقريب.',
            icon: Icons.event_note_outlined,
          ),
          const SizedBox(height: 10),
        ],
        InfoBanner(
          text: calculation == null
              ? 'أكمل المدة والإيجار لإنشاء جدول الدفعات.'
              : 'إجمالي الإيجار طوال العقد: ${_money(calculation.totalHalalas / 100)}\nعدد الدفعات: ${calculation.installments.length} • الدفعة الأولى: ${_money(installmentValue)}\nالأيام الإضافية تُحسب من الإيجار السنوي ÷ 365. قد تختلف الدفعة الأخيرة للفترة الجزئية أو التقريب. لا يشمل هذا الإجمالي الضمان أو رسوم الخدمة.',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'الخدمات', icon: Icons.electrical_services_outlined),
        const SizedBox(height: 12),
        _ServiceChargePanel(
          title: 'الكهرباء',
          icon: Icons.bolt_outlined,
          data: draft.electricity,
          onChanged: onChanged,
        ),
        const SizedBox(height: 10),
        _ServiceChargePanel(
          title: 'المياه',
          icon: Icons.water_drop_outlined,
          data: draft.water,
          onChanged: onChanged,
        ),
        const SizedBox(height: 10),
        _ServiceChargePanel(
          title: 'الغاز',
          icon: Icons.local_fire_department_outlined,
          data: draft.gas,
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'خدمات أو شروط مالية إضافية',
          hint: 'اكتب أي رسوم خدمات أو ملاحظات مالية خاصة',
          initialValue: draft.otherServices,
          icon: Icons.notes_rounded,
          maxLines: 3,
          onChanged: (value) => draft.otherServices = value,
        ),
        const SizedBox(height: 16),
        const SectionTitle(
          title: 'الشروط الإضافية',
          icon: Icons.rule_folder_outlined,
        ),
        const SizedBox(height: 10),
        ToggleCard(
          title: 'التأجير من الباطن مسموح',
          subtitle: draft.allowSublease
              ? 'يسمح للمستأجر بالتأجير من الباطن'
              : 'غير مسموح للمستأجر بالتأجير من الباطن',
          value: draft.allowSublease,
          icon: Icons.handshake_outlined,
          onChanged: (value) {
            draft.allowSublease = value;
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        AppTextField(
          label: 'شروط إضافية',
          hint: 'أدخل أي شروط خاصة بالعقد',
          initialValue: draft.specialTerms,
          icon: Icons.edit_note_outlined,
          maxLines: 4,
          onChanged: (value) {
            draft.specialTerms = value;
            onChanged();
          },
        ),
        if (draft.type == ContractType.commercial &&
            draft.specialTerms.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          const InfoBanner(
            text:
                'تنبيه: عند إضافة شروط خاصة في عقد تجاري قد يصبح العقد غير تنفيذي حسب الشرط المذكور.',
            icon: Icons.warning_amber_rounded,
            color: AppColors.orange,
          ),
        ],
        const SizedBox(height: 16),
        const SectionTitle(
            title: 'طريقة دفع رسوم الطلب', icon: Icons.credit_card_outlined),
        const SizedBox(height: 12),
        SegmentedChoice<PaymentMethod>(
          values: PaymentMethod.values,
          selected: draft.paymentMethod,
          labelBuilder: _paymentMethodLabel,
          iconBuilder: _paymentMethodIcon,
          onChanged: (value) {
            draft.paymentMethod = value;
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        _FinancialSummaryCard(draft: draft),
      ],
    );
  }
}

class _ServiceChargePanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final ServiceCharge data;
  final VoidCallback onChanged;

  const _ServiceChargePanel({
    required this.title,
    required this.icon,
    required this.data,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      shadows: const <BoxShadow>[],
      child: Column(
        children: <Widget>[
          Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: data.enabled,
                activeThumbColor: AppColors.primary,
                secondary: Icon(icon, color: AppColors.primary),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  data.enabled
                      ? 'سيتم تضمين بيانات الخدمة في العقد'
                      : 'الخدمة غير مضافة',
                  style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11.5)),
                ),
                onChanged: (value) {
                  data.enabled = value;
                  onChanged();
                },
              )),
          if (data.enabled) ...<Widget>[
            const SizedBox(height: 12),
            FieldGrid(
              children: <Widget>[
                AppDropdownField(
                  label: 'آلية الاحتساب',
                  value: data.calculationMethod,
                  items: const <String>[
                    'حسب الفاتورة',
                    'مبلغ مقطوع',
                  ],
                  icon: Icons.calculate_outlined,
                  onChanged: (value) {
                    data.calculationMethod = value!;
                    onChanged();
                  },
                ),
                if (data.calculationMethod == 'مبلغ مقطوع')
                  AppTextField(
                    label: 'قيمة المبلغ',
                    hint: 'أدخل قيمة المبلغ المقطوع',
                    initialValue: data.fixedAmount,
                    icon: Icons.payments_outlined,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    required: true,
                    onChanged: (value) => data.fixedAmount = value,
                    validator: _requiredPositiveAmount,
                  ),
                AppTextField(
                  label: 'القراءة الحالية',
                  hint: 'رقم قراءة العداد',
                  initialValue: data.currentReading,
                  icon: Icons.speed_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  onChanged: (value) => data.currentReading = value,
                  validator: _optionalPositiveNumber,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  final ContractDraft draft;

  const _FinancialSummaryCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          const _FeeRow(
              label: 'رسوم العقد',
              icon: Icons.support_agent_outlined,
              value: null),
          _AmountRow(
              label: 'السنة الأولى • ${draft.type.label}',
              value: draft.price.firstYear),
          _AmountRow(
              label: 'المدة الإضافية', value: draft.price.additionalAmount),
          const SizedBox(height: 8),
          const Text(ContractPrice.inclusionNote),
          const Divider(height: 22),
          _AmountRow(
              label: 'الإجمالي المستحق الآن',
              value: draft.totalPayable,
              strong: true),
          const SizedBox(height: 8),
          const Text(ContractPrice.durationNote,
              style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;

  const _FeeRow({required this.label, required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (value != null)
          Text(
            value!,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final bool strong;

  const _AmountRow(
      {required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: strong ? AppColors.primary : context.ejarzTheme.text,
      fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
      fontSize: strong ? context.sp(15) : context.sp(13),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(_money(value), style: style),
        ],
      ),
    );
  }
}

class _AttachmentsStep extends StatelessWidget {
  final AdminContractSession? adminSession;
  final ContractDraft draft;
  final List<AttachmentData> requiredAttachments;
  final VoidCallback onChanged;

  const _AttachmentsStep({
    this.adminSession,
    required this.draft,
    required this.requiredAttachments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final missingCount = requiredAttachments
        .where((attachment) => !_attachmentReady(attachment))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'المرفقات',
          subtitle:
              'ارفع المستندات المطلوبة لمراجعة الطلب قبل إدخاله في منصة إيجار.',
          icon: Icons.attach_file_rounded,
        ),
        const SizedBox(height: 14),
        InfoBanner(
          text: missingCount == 0
              ? 'كل المستندات المطلوبة مكتملة ويمكنك المتابعة للمراجعة النهائية.'
              : 'المستندات المطلوبة المتبقية: $missingCount. ارفع الملفات المطلوبة للمتابعة.',
          icon: missingCount == 0
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded,
          color: missingCount == 0 ? AppColors.primary : AppColors.orange,
        ),
        const SizedBox(height: 16),
        for (final attachment in draft.attachments) ...<Widget>[
          _AttachmentTile(
            uploader: adminSession == null
                ? null
                : (name, bytes) =>
                    adminSession!.upload(name, bytes, draft: draft),
            attachment: attachment,
            requiredAttachment: requiredAttachments.contains(attachment),
            onChanged: onChanged,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatefulWidget {
  final Future<String> Function(String, Uint8List)? uploader;
  final AttachmentData attachment;
  final bool requiredAttachment;
  final VoidCallback onChanged;

  const _AttachmentTile({
    this.uploader,
    required this.attachment,
    required this.requiredAttachment,
    required this.onChanged,
  });

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _uploading = false;
  AttachmentData get attachment => widget.attachment;
  bool get requiredAttachment => widget.requiredAttachment;
  VoidCallback get onChanged => widget.onChanged;

  Future<void> _pick() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || selection == null) return;
      final file = selection.files.single;
      if (file.size > ContractFiles.maxBytes || file.bytes == null) {
        throw const FormatException(
            'تعذر قراءة الملف أو أن حجمه أكبر من 10 ميجابايت.');
      }
      final url = await (widget.uploader ?? ContractFiles.upload)(
          file.name, file.bytes!);
      if (!mounted) return;
      attachment
        ..uploaded = true
        ..fileName = file.name
        ..sizeLabel = '${(file.size / 1024).ceil()} KB'
        ..downloadUrl = url;
      onChanged();
      showAppSnackBar(context, 'تم رفع ${attachment.title} وحفظه بنجاح');
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
            context,
            error is FormatException
                ? error.message
                : 'تعذر رفع المرفق. تحقق من الاتصال ثم أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploaded = _attachmentReady(attachment);
    return AppCard(
      padding: const EdgeInsets.all(14),
      shadows: const <BoxShadow>[],
      border: Border.all(
        color: uploaded
            ? AppColors.primary.withValues(alpha: 0.45)
            : requiredAttachment
                ? AppColors.orange.withValues(alpha: 0.55)
                : context.ejarzTheme.border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: uploaded
                    ? AppColors.primaryLight
                    : context.ejarzTheme.background,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                uploaded ? Icons.task_outlined : Icons.upload_file_outlined,
                color: uploaded ? AppColors.primary : context.ejarzTheme.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          attachment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _AttachmentBadge(requiredAttachment: requiredAttachment),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    uploaded
                        ? '${attachment.fileName} - ${attachment.sizeLabel}'
                        : 'لم يتم الرفع بعد',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_uploading)
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (uploaded)
              IconButton(
                tooltip: 'حذف المرفق',
                onPressed: () {
                  attachment.uploaded = false;
                  attachment.fileName = '';
                  attachment.sizeLabel = '';
                  attachment.downloadUrl = '';
                  onChanged();
                },
                icon: const Icon(Icons.delete_outline_rounded),
              )
            else
              TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('رفع'),
              ),
          ]),
          if (kEjarzDemoMode && !uploaded && !_uploading) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                attachment
                  ..uploaded = true
                  ..fileName = '${attachment.keyName}.pdf'
                  ..sizeLabel = 'نموذج تجريبي'
                  ..downloadUrl = ContractFiles.demoPdf;
                onChanged();
              },
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('استخدام مرفق تجريبي دون رفع وثائق شخصية'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentBadge extends StatelessWidget {
  final bool requiredAttachment;

  const _AttachmentBadge({required this.requiredAttachment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: requiredAttachment
            ? AppColors.orange.withValues(alpha: 0.12)
            : context.ejarzTheme.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        requiredAttachment ? 'مطلوب' : 'اختياري',
        style: TextStyle(
          color:
              requiredAttachment ? AppColors.orange : context.ejarzTheme.muted,
          fontSize: context.sp(10.5),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _paymentMethodLabel(PaymentMethod method) {
  return switch (method) {
    PaymentMethod.mada => 'بطاقة مدى',
    PaymentMethod.applePay => 'Apple Pay',
    PaymentMethod.bankTransfer => 'تحويل بنكي',
  };
}

IconData _paymentMethodIcon(PaymentMethod method) {
  return switch (method) {
    PaymentMethod.mada => Icons.credit_card_rounded,
    PaymentMethod.applePay => Icons.phone_iphone_rounded,
    PaymentMethod.bankTransfer => Icons.account_balance_outlined,
  };
}

String _money(num value) => '${value.toStringAsFixed(2)} ريال';
