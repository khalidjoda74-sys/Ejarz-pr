import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/draft_resume_policy.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/illustrations.dart';
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

String? _requiredIdentityNumber(String? value, String idType) {
  final cleaned = (value ?? '').trim();
  if (cleaned.isEmpty) return 'هذا الحقل مطلوب';
  final digits = _digitsOnly(cleaned);
  if (idType == 'هوية وطنية') {
    if (digits.length == 10 && digits.startsWith('1')) return null;
    return 'الهوية الوطنية يجب أن تكون 10 أرقام وتبدأ بـ 1';
  }
  if (idType == 'إقامة') {
    if (digits.length == 10 && digits.startsWith('2')) return null;
    return 'رقم الإقامة يجب أن يكون 10 أرقام ويبدأ بـ 2';
  }
  if (idType == 'هوية خليجية') {
    if (digits.length >= 8 && digits.length <= 15) return null;
    return 'أدخل رقم هوية خليجية صحيحًا';
  }
  if (cleaned.length >= 6 && cleaned.length <= 15) return null;
  return 'أدخل رقم جواز صحيحًا من 6 إلى 15 خانة';
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
  final digits = _digitsOnly(value ?? '');
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
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  final amount = double.tryParse(normalized);
  if (amount == null || amount <= 0) return 'أدخل مبلغًا صحيحًا أكبر من صفر';
  return null;
}

String? _requiredPositiveNumber(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  final number = double.tryParse(normalized);
  if (number == null || number <= 0) return 'أدخل رقمًا صحيحًا أكبر من صفر';
  return null;
}

String? _optionalPositiveAmount(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  if (normalized.isEmpty) return null;
  final amount = double.tryParse(normalized);
  if (amount == null || amount < 0) return 'أدخل مبلغًا صحيحًا';
  return null;
}

String? _optionalPositiveNumber(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  if (normalized.isEmpty) return null;
  final number = double.tryParse(normalized);
  if (number == null || number < 0) return 'أدخل رقمًا صحيحًا';
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

const String _newPropertySource = 'إضافة عقار جديد';

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
    if (unitNumber.isNotEmpty) 'وحدة $unitNumber',
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
      district: data.district,
      street: data.street,
      buildingNumber: data.buildingNumber,
      additionalNumber: data.additionalNumber,
      postalCode: data.postalCode,
      buildingName: data.buildingName,
      unitNumber: data.unitNumber,
      unitName: data.unitName,
      unitType: data.unitType,
      floor: data.floor,
      area: data.area,
      roomsCount: data.roomsCount,
      bathroomsCount: data.bathroomsCount,
      hallsCount: data.hallsCount,
      maidRoom: data.maidRoom,
      kitchen: data.kitchen,
      storage: data.storage,
      majlis: data.majlis,
      furnishingStatus: data.furnishingStatus,
      acWindow: data.acWindow,
      acSplit: data.acSplit,
      acCentral: data.acCentral,
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
    propertySource: sourceLabel,
    propertyUsage: property.usage,
    propertyType: property.type,
    floorsCount: property.floors.toString(),
    unitsPerFloor: '1',
    totalUnits: property.totalUnits.toString(),
    city: property.city,
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
  final ContractDraft? initialDraft;
  final String draftId;
  final int? initialStep;
  final List<String> initialTouchedSections;
  final bool renewalMode;
  final String renewalSourceNumber;

  const CreateContractScreen({
    super.key,
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

  late final ContractDraft _draft;
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
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft == null
        ? ContractDraft()
        : ContractDraft.copyOf(widget.initialDraft!);
    _draftId = widget.draftId.trim();
    _touchedSections.addAll(widget.initialTouchedSections);
    _currentStep = (widget.initialStep ??
            (widget.initialDraft == null
                ? 0
                : firstIncompleteDraftStep(_draft)))
        .clamp(0, _steps.length - 1);
  }

  @override
  void dispose() {
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
        if (_requiredIdentityNumber(party.idNumber, party.idType) != null)
          'رقم الهوية',
        if (_isBlank(party.birthDate)) 'تاريخ الميلاد',
        if (_requiredSaudiMobile(party.mobile) != null) 'رقم جوال أبشر',
        if (_optionalEmail(party.email) != null) 'البريد الإلكتروني',
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
    _touchedSections.add(draftSectionForStep(_currentStep));
    setState(() {});
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
      if (_requiredIdentityNumber(
              representative.idNumber, representative.idType) !=
          null)
        'رقم هوية الوكيل',
      if (_requiredSaudiMobile(representative.mobile) != null) 'جوال الوكيل',
      if (_requiredReferenceNumber(
              representative.authorizationNumber, 'رقم الوكالة أو التفويض') !=
          null)
        'رقم الوكالة أو التفويض',
    ];
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
    return amount != null && amount > 0;
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
      if (_requiredPositiveInt(property.floorsCount, min: 1, max: 200) != null)
        'عدد الأدوار',
      if (_requiredPositiveInt(property.unitsPerFloor, min: 1, max: 200) !=
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
      if (!property.acWindow && !property.acSplit && !property.acCentral)
        'نوع التكييف',
      if (_requiredPositiveInt(property.electricityMeter, min: 1) != null)
        'رقم عداد الكهرباء',
      if (_requiredPositiveInt(property.waterMeter, min: 1) != null)
        'رقم عداد المياه',
    ];
  }

  bool _validatePropertyStep() {
    final missing = _missingPropertyFields();
    if (missing.isEmpty) {
      final floors = int.tryParse(_draft.property.floorsCount) ?? 0;
      final unitsPerFloor = int.tryParse(_draft.property.unitsPerFloor) ?? 0;
      final totalUnits = int.tryParse(_draft.property.totalUnits) ?? 0;
      if (floors > 0 &&
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
    return <String>[
      if (_isBlank(_draft.startDate)) 'تاريخ بداية العقد',
      if (_isBlank(_draft.endDate)) 'تاريخ نهاية العقد',
      if (startDate != null && endDate != null && endDate.isBefore(startDate))
        'تاريخ نهاية العقد بعد تاريخ البداية',
      if (years <= 0 && months <= 0 && days <= 0) 'مدة العقد',
      if (months < 0 || months > 11) 'عدد الأشهر من 0 إلى 11',
      if (days < 0 || days > 30) 'عدد الأيام من 0 إلى 30',
      if (!_isPositiveNumber(_draft.rentValue)) 'مبلغ الإيجار السنوي',
      if (_draft.hasSecurityDeposit &&
          !_isPositiveNumber(_draft.securityDeposit))
        'قيمة الضمان',
      if (_optionalPositiveAmount(_draft.brokerageFee) != null) 'عمولة السعي',
      if (_optionalPositiveAmount(_draft.otherAmounts) != null) 'مبالغ أخرى',
      if (_draft.ownerSubjectToVat && !_isPositiveNumber(_draft.vatValue))
        'قيمة ضريبة القيمة المضافة',
      if (_draft.paymentCount <= 0) 'عدد الدفعات',
      if (_isBlank(_draft.firstPaymentDate)) 'تاريخ أول دفعة',
      if (startDate != null &&
          firstPaymentDate != null &&
          firstPaymentDate.isBefore(startDate))
        'تاريخ أول دفعة بعد بداية العقد',
      if (endDate != null &&
          firstPaymentDate != null &&
          firstPaymentDate.isAfter(endDate))
        'تاريخ أول دفعة قبل نهاية العقد',
      if (!_draft.electricity.enabled) 'الكهرباء',
      if (!_draft.water.enabled) 'المياه',
      if (_draft.electricity.enabled &&
          _draft.electricity.calculationMethod == 'مبلغ مقطوع' &&
          !_isPositiveNumber(_draft.electricity.fixedAmount))
        'قيمة مبلغ الكهرباء',
      if (_draft.water.enabled &&
          _draft.water.calculationMethod == 'مبلغ مقطوع' &&
          !_isPositiveNumber(_draft.water.fixedAmount))
        'قيمة مبلغ المياه',
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
          .where((attachment) => !attachment.uploaded)
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
    }
  }

  void _previous() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _currentStep -= 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
  }

  List<AttachmentData> get _requiredAttachments {
    return _draft.attachments.where((attachment) {
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
      return attachment.required;
    }).toList();
  }

  bool _validateAllRequiredFields() {
    if (!_validatePartiesStep()) return false;
    if (!_validatePropertyStep()) return false;
    if (!_validateFinancialStep()) return false;
    final missingAttachments = _requiredAttachments
        .where((attachment) => !attachment.uploaded)
        .map((attachment) => attachment.title)
        .toList();
    if (missingAttachments.isNotEmpty) {
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
    if (!_validateAllRequiredFields()) return;
    if (!_draft.acceptAccuracyDeclaration ||
        !_draft.acceptDataSharing ||
        !_draft.acceptTerms) {
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
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final controller = AppScope.of(context, listen: false);
    final record = await controller.submitContract(
      _draft,
      draftId: _draftId,
      progress: _draftProgress,
    );
    final waitsForConnection = record.pendingSync;
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
    _touchedSections.add(draftSectionForStep(_currentStep));
    final controller = AppScope.of(context, listen: false);
    final record = await controller.saveDraft(
      _draft,
      draftId: _draftId,
      progress: _draftProgress,
    );
    if (!mounted) return;
    _draftId = record.id;
    showAppSnackBar(
      context,
      record.pendingSync
          ? 'تم حفظ المسودة محليًا وستتم مزامنتها عند عودة الاتصال'
          : 'تم حفظ المسودة برقم ${record.requestNumber}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.renewalMode
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
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 92),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Form(
                        key: _formKeys[_currentStep],
                        child: _buildStep(),
                      ),
                    ),
                  ),
                ),
              ),
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
          requiredAttachments: _requiredAttachments,
          onChanged: _markChanged,
        ),
      6 => _ReviewStep(
          draft: _draft,
          requiredAttachments: _requiredAttachments,
          onChanged: _markChanged,
        ),
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
              'سيتم مراجعة بيانات العقد والمرفقات من فريق عقود برو قبل إدخاله في منصة إيجار للتأكد من اكتمالها وصحتها.',
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
              required: true,
              onChanged: (value) => property.unitsPerFloor = value,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 200),
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
            AppDropdownField(
              label: 'المدينة',
              value: property.city,
              items: const <String>[
                'الرياض',
                'جدة',
                'مكة المكرمة',
                'المدينة المنورة',
                'الدمام',
                'الخبر',
                'الطائف',
                'أبها',
                'تبوك',
              ],
              icon: Icons.location_city_outlined,
              onChanged: (value) {
                property.city = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'الحي',
              hint: 'أدخل اسم الحي',
              initialValue: property.district,
              icon: Icons.location_on_outlined,
              required: true,
              onChanged: (value) {
                property.district = value;
                onChanged();
              },
              validator: _requiredName,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: const MiniMapPreview(height: 126),
              ),
              const SizedBox(height: 10),
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
                  TextButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      'سيتم ربط اختيار الموقع بالخريطة عند إضافة خدمة الخرائط.',
                    ),
                    child: const Text('تحديد الموقع'),
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
              hint: 'مثال: 3',
              initialValue: property.floor,
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
              hint: 'أدخل رقم العداد',
              initialValue: property.electricityMeter,
              icon: Icons.bolt_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              required: true,
              onChanged: (value) => property.electricityMeter = value,
              validator: (value) => _requiredPositiveInt(value, min: 1),
            ),
            AppTextField(
              label: 'رقم عداد المياه',
              hint: 'أدخل رقم العداد',
              initialValue: property.waterMeter,
              icon: Icons.water_drop_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
              required: true,
              onChanged: (value) => property.waterMeter = value,
              validator: (value) => _requiredPositiveInt(value, min: 1),
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
            _FeatureToggle(
              label: 'مطبخ',
              selected: property.kitchen,
              onSelected: (value) {
                property.kitchen = value;
                onChanged();
              },
            ),
            _FeatureToggle(
              label: 'مخزن',
              selected: property.storage,
              onSelected: (value) {
                property.storage = value;
                onChanged();
              },
            ),
            _FeatureToggle(
              label: 'مجلس',
              selected: property.majlis,
              onSelected: (value) {
                property.majlis = value;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionTitle(title: 'التكييف', icon: Icons.ac_unit_outlined),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _FeatureToggle(
              label: 'شباك',
              selected: property.acWindow,
              onSelected: (value) {
                property.acWindow = value;
                onChanged();
              },
            ),
            _FeatureToggle(
              label: 'سبليت',
              selected: property.acSplit,
              onSelected: (value) {
                property.acSplit = value;
                onChanged();
              },
            ),
            _FeatureToggle(
              label: 'مركزي',
              selected: property.acCentral,
              onSelected: (value) {
                property.acCentral = value;
                onChanged();
              },
            ),
          ],
        ),
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
        if (selectedTab == 0)
          _PartyForm(
            key: ValueKey<String>('lessor-${draft.lessor.kind.name}'),
            title: 'بيانات المؤجر',
            data: draft.lessor,
            isLessor: true,
            onChanged: onChanged,
          )
        else if (selectedTab == 1)
          _PartyForm(
            key: ValueKey<String>('tenant-${draft.tenant.kind.name}'),
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
                    _requiredIdentityNumber(value, data.idType),
              ),
              DateField(
                label: 'تاريخ الميلاد',
                value: data.birthDate,
                required: true,
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
        FieldGrid(
          children: <Widget>[
            AppDropdownField(
              label: 'المدينة',
              value: data.city,
              items: const <String>[
                'الرياض',
                'جدة',
                'مكة المكرمة',
                'المدينة المنورة',
                'الدمام',
                'الخبر',
                'الطائف',
              ],
              icon: Icons.location_city_outlined,
              onChanged: (value) {
                data.city = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'الحي',
              hint: 'اسم الحي',
              initialValue: data.district,
              icon: Icons.location_on_outlined,
              required: true,
              onChanged: (value) => data.district = value,
              validator: _requiredName,
            ),
          ],
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
              AppTextField(
                label: 'اسم البنك',
                hint: 'أدخل اسم البنك',
                initialValue: data.bankName,
                icon: Icons.account_balance_outlined,
                onChanged: (value) => data.bankName = value,
                required: true,
                validator: _requiredName,
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
                    _requiredIdentityNumber(value, data.idType),
              ),
              DateField(
                label: 'تاريخ الميلاد',
                value: data.birthDate,
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
              AppTextField(
                label: 'تاريخ الوكالة',
                hint: 'YYYY/MM/DD',
                initialValue: data.authorizationDate,
                icon: Icons.calendar_month_outlined,
                onChanged: (value) => data.authorizationDate = value,
              ),
              AppTextField(
                label: 'جهة الإصدار',
                hint: 'مثال: وزارة العدل',
                initialValue: data.issuer,
                icon: Icons.account_balance_outlined,
                onChanged: (value) => data.issuer = value,
              ),
              AppTextField(
                label: 'تاريخ الانتهاء',
                hint: 'إن وجد',
                initialValue: data.expiryDate,
                icon: Icons.event_busy_outlined,
                onChanged: (value) => data.expiryDate = value,
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
    draft.paymentCount = parsed == null || parsed < 1 ? 1 : parsed;
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
    final end = DateTime(targetYear, targetMonth, targetDay)
        .add(Duration(days: days))
        .subtract(const Duration(days: 1));
    draft.endDate = _formatDate(end);
  }

  @override
  Widget build(BuildContext context) {
    final installmentValue = draft.paymentCount <= 0
        ? draft.rentValueNumber
        : draft.rentValueNumber / draft.paymentCount;

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
                onChanged();
              },
            ),
            DateField(
              label: 'تاريخ نهاية العقد',
              value: draft.endDate,
              required: true,
              onChanged: (value) {
                draft.endDate = value;
                onChanged();
              },
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
              ],
              icon: Icons.repeat_rounded,
              onChanged: (value) {
                draft.rentPeriod = value!;
                draft.paymentFrequency = value == 'دفعة واحدة' ? 'سنوي' : value;
                draft.paymentScheduleType =
                    value == 'دفعة واحدة' ? 'دفعة واحدة' : 'دوري';
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
                onChanged();
              },
            ),
            AppDropdownField(
              label: 'تكرار الدفع',
              value: draft.paymentFrequency,
              items: const <String>['شهري', 'ربع سنوي', 'نصف سنوي', 'سنوي'],
              icon: Icons.repeat_on_rounded,
              onChanged: (value) {
                draft.paymentFrequency = value!;
                onChanged();
              },
            ),
            AppTextField(
              label: 'عدد الدفعات',
              hint: 'مثال: 4',
              initialValue: draft.paymentCount.toString(),
              icon: Icons.format_list_numbered_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              required: true,
              onChanged: _updatePaymentCount,
              validator: (value) =>
                  _requiredPositiveInt(value, min: 1, max: 60),
            ),
            DateField(
              label: 'تاريخ أول دفعة',
              value: draft.firstPaymentDate,
              required: true,
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
              label: 'دافع عمولة عقود برو',
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
        InfoBanner(
          text:
              'قيمة الدفعة التقديرية: ${_money(installmentValue)}. سيتم إنشاء جدول الدفعات النهائي عند الانتقال للخطوة التالية.',
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
          SwitchListTile.adaptive(
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
                  color: context.ejarzTheme.muted, fontSize: context.sp(11.5)),
            ),
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
          _AmountRow(label: 'رسوم منصة إيجار', value: draft.officialFee),
          _AmountRow(label: 'عمولة عقود برو', value: draft.serviceFee),
          const Divider(height: 22),
          _AmountRow(
              label: 'الإجمالي المستحق الآن',
              value: draft.totalPayable,
              strong: true),
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
  final ContractDraft draft;
  final List<AttachmentData> requiredAttachments;
  final VoidCallback onChanged;

  const _AttachmentsStep({
    required this.draft,
    required this.requiredAttachments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final missingCount =
        requiredAttachments.where((attachment) => !attachment.uploaded).length;

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

class _AttachmentTile extends StatelessWidget {
  final AttachmentData attachment;
  final bool requiredAttachment;
  final VoidCallback onChanged;

  const _AttachmentTile({
    required this.attachment,
    required this.requiredAttachment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = attachment.uploaded;
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
      child: Row(
        children: <Widget>[
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
          if (uploaded)
            IconButton(
              tooltip: 'حذف المرفق',
              onPressed: () {
                attachment.uploaded = false;
                attachment.fileName = '';
                attachment.sizeLabel = '';
                onChanged();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            )
          else
            TextButton.icon(
              onPressed: () {
                attachment.uploaded = true;
                attachment.fileName = '${attachment.keyName}.pdf';
                attachment.sizeLabel = '1.2 MB';
                onChanged();
                showAppSnackBar(context, 'تم إرفاق ${attachment.title} بنجاح');
              },
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('رفع'),
            ),
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

class _ReviewStep extends StatelessWidget {
  final ContractDraft draft;
  final List<AttachmentData> requiredAttachments;
  final VoidCallback onChanged;

  const _ReviewStep({
    required this.draft,
    required this.requiredAttachments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final uploadedRequired =
        requiredAttachments.where((attachment) => attachment.uploaded).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppPageHeader(
          title: 'المراجعة النهائية',
          subtitle: 'راجع ملخص بيانات العقد وأكد الإقرارات قبل رفع الطلب.',
          icon: Icons.fact_check_outlined,
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'ملخص العقد',
          icon: Icons.article_outlined,
          children: <Widget>[
            _ReviewLine(label: 'نوع العقد', value: draft.type.label),
            _ReviewLine(
                label: 'العنوان',
                value: _valueOrDash(draft.property.displayAddress)),
            _ReviewLine(
                label: 'الوحدة',
                value: _valueOrDash(draft.property.unitNumber)),
            _ReviewLine(
                label: 'مدة العقد',
                value:
                    '${draft.durationYears} سنة / ${draft.durationMonths} شهر / ${draft.durationDays} يوم'),
            _ReviewLine(
                label: 'تاريخ البداية', value: _valueOrDash(draft.startDate)),
            _ReviewLine(
                label: 'تاريخ النهاية', value: _valueOrDash(draft.endDate)),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'بيانات الملكية',
          icon: Icons.verified_outlined,
          children: <Widget>[
            _ReviewLine(
              label: 'نوع الإثبات',
              value: draft.property.ownershipDocumentType,
            ),
            _ReviewLine(
              label: 'رقم الوثيقة',
              value: _valueOrDash(draft.property.ownershipDocumentNumber),
            ),
            _ReviewLine(
              label: 'تاريخ الوثيقة',
              value: _valueOrDash(draft.property.ownershipDocumentDate),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'الأطراف',
          icon: Icons.people_outline_rounded,
          children: <Widget>[
            _ReviewLine(
                label: 'المؤجر', value: _valueOrDash(draft.lessor.displayName)),
            _ReviewLine(
                label: 'المستأجر',
                value: _valueOrDash(draft.tenant.displayName)),
            _ReviewLine(
              label: 'الممثل القانوني',
              value: draft.representative.enabled
                  ? _valueOrDash(draft.representative.fullName)
                  : 'لا يوجد',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'العقار والوحدة',
          icon: Icons.apartment_outlined,
          children: <Widget>[
            _ReviewLine(
                label: 'مصدر العقار', value: draft.property.propertySource),
            _ReviewLine(
                label: 'نوع العقار الرئيسي',
                value: draft.property.propertyType),
            _ReviewLine(
                label: 'استخدام العقار', value: draft.property.propertyUsage),
            _ReviewLine(
                label: 'إجمالي الوحدات',
                value: _valueOrDash(draft.property.totalUnits)),
            _ReviewLine(
                label: 'اسم الوحدة',
                value: _valueOrDash(draft.property.unitName)),
            _ReviewLine(label: 'نوع الوحدة', value: draft.property.unitType),
            _ReviewLine(
                label: 'حالة التأثيث', value: draft.property.furnishingStatus),
            _ReviewLine(
                label: 'موقف خاص',
                value: draft.property.privateParking ? 'يوجد' : 'لا يوجد'),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'البيانات المالية',
          icon: Icons.payments_outlined,
          children: <Widget>[
            _ReviewLine(
                label: 'مبلغ الإيجار السنوي',
                value: _money(draft.rentValueNumber)),
            _ReviewLine(label: 'دورة السداد', value: draft.rentPeriod),
            _ReviewLine(
              label: 'الضمان',
              value: draft.hasSecurityDeposit
                  ? _money(draft.depositNumber)
                  : 'لا يوجد',
            ),
            _ReviewLine(label: 'عدد الدفعات', value: '${draft.paymentCount}'),
            _ReviewLine(label: 'قناة الدفع', value: draft.paymentChannel),
            _ReviewLine(
                label: 'طريقة دفع رسوم الطلب',
                value: _paymentMethodLabel(draft.paymentMethod)),
            _ReviewLine(
                label: 'الإجمالي المستحق الآن',
                value: _money(draft.totalPayable),
                strong: true),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'الشروط',
          icon: Icons.rule_folder_outlined,
          children: <Widget>[
            _ReviewLine(
              label: 'التأجير من الباطن',
              value: draft.allowSublease ? 'مسموح' : 'غير مسموح',
            ),
            _ReviewLine(
              label: 'الشروط الإضافية',
              value: _valueOrDash(draft.specialTerms),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'المرفقات',
          icon: Icons.attach_file_rounded,
          children: <Widget>[
            _ReviewLine(
                label: 'المرفقات المطلوبة',
                value:
                    '$uploadedRequired / ${requiredAttachments.length} مكتملة'),
            _ReviewLine(
              label: 'إجمالي المرفقات المرفوعة',
              value:
                  '${draft.attachments.where((attachment) => attachment.uploaded).length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        ToggleCard(
          title: 'أقر بصحة البيانات والمستندات',
          subtitle: 'أتحمل مسؤولية دقة المعلومات المدخلة في الطلب',
          value: draft.acceptAccuracyDeclaration,
          icon: Icons.verified_user_outlined,
          onChanged: (value) {
            draft.acceptAccuracyDeclaration = value;
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        ToggleCard(
          title: 'أوافق على مشاركة البيانات اللازمة',
          subtitle: 'تستخدم البيانات لإتمام إصدار العقد ومراجعته',
          value: draft.acceptDataSharing,
          icon: Icons.shield_outlined,
          onChanged: (value) {
            draft.acceptDataSharing = value;
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        ToggleCard(
          title: 'أوافق على الشروط والأحكام',
          subtitle: 'لن يتم رفع الطلب قبل قبول الشروط',
          value: draft.acceptTerms,
          icon: Icons.policy_outlined,
          onChanged: (value) {
            draft.acceptTerms = value;
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        const InfoBanner(
          text:
              'بعد التأكيد سيتم إنشاء طلب مراجعة جديد ويمكنك متابعة حالته من صفحة العقود.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionTitle(title: title, icon: icon),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shadows: const <BoxShadow>[],
          child: Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i < children.length - 1)
                  Divider(color: context.ejarzTheme.border, height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _ReviewLine(
      {required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.ejarzTheme.muted,
                fontSize: context.sp(12.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: strong ? AppColors.primary : context.ejarzTheme.text,
                fontSize: context.sp(13),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ),
        ],
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

String _valueOrDash(String value) => value.trim().isEmpty ? 'غير محدد' : value;
