import '../contract_calculation_engine.dart';
import '../contract_validators.dart';
import '../saudi_reference_data.dart';

class ContractFieldSpec {
  final String path, label;
  final int step;
  final bool required, sensitive;
  final List<String> choices;
  const ContractFieldSpec(this.path, this.label, this.step,
      {this.required = true, this.sensitive = true, this.choices = const []});

  String get question {
    final owner = path.startsWith('lessor.')
        ? ' للمؤجر'
        : path.startsWith('tenant.')
            ? ' للمستأجر'
            : path.startsWith('representative.')
                ? ' للوكيل أو المفوض'
                : '';
    return 'ما $label$owner؟';
  }
}

Object? readContractPath(Map<String, Object?> root, String path) {
  Object? value = root;
  for (final part in path.split('.')) {
    value = value is Map ? value[part] : null;
  }
  return value;
}

void writeContractPath(Map<String, Object?> root, String path, Object? value) {
  Map current = root;
  final parts = path.split('.');
  for (final part in parts.take(parts.length - 1)) {
    current = current[part] as Map;
  }
  current[parts.last] = value;
}

class ContractFieldCatalog {
  static final fields = <ContractFieldSpec>[
    const ContractFieldSpec('type', 'نوع العقد', 0,
        choices: ['residential', 'commercial']),
    const ContractFieldSpec('property.savedPropertyId', 'العقار المحفوظ', 3,
        required: false),
    const ContractFieldSpec('property.unitNumber', 'رقم الوحدة', 3),
    ..._party('lessor'),
    ..._party('tenant'),
    const ContractFieldSpec('representative.enabled', 'وجود وكيل أو مفوض', 2,
        required: false),
    ..._representative,
    const ContractFieldSpec('duration.startDate', 'تاريخ بداية العقد', 4),
    const ContractFieldSpec('duration.years', 'عدد السنوات', 4),
    const ContractFieldSpec('duration.months', 'عدد الأشهر', 4),
    const ContractFieldSpec('duration.days', 'عدد الأيام', 4),
    const ContractFieldSpec('financial.rentValue', 'مبلغ الإيجار السنوي', 4),
    const ContractFieldSpec('financial.paymentScheduleType', 'نوع الجدولة', 4,
        choices: ['دوري', 'دفعة واحدة', 'مخصص']),
    const ContractFieldSpec('financial.paymentFrequency', 'تكرار الدفع', 4,
        choices: ['شهري', 'ربع سنوي', 'نصف سنوي', 'سنوي']),
    const ContractFieldSpec('financial.firstPaymentDate', 'تاريخ أول دفعة', 4),
    const ContractFieldSpec('financial.hasSecurityDeposit', 'وجود مبلغ ضمان', 4,
        required: false),
    const ContractFieldSpec('financial.securityDeposit', 'قيمة الضمان', 4),
    const ContractFieldSpec('financial.brokerageFee', 'عمولة السعي', 4,
        required: false),
    const ContractFieldSpec('financial.otherAmounts', 'مبالغ أخرى', 4,
        required: false),
    const ContractFieldSpec(
        'financial.ownerSubjectToVat', 'خضوع المؤجر للضريبة', 4,
        required: false),
    const ContractFieldSpec(
        'financial.vatValue', 'قيمة ضريبة القيمة المضافة', 4),
    for (final pair in _propertyLabels.entries)
      ContractFieldSpec('property.${pair.key}', pair.value,
          pair.key.startsWith('ownership') ? 1 : 3,
          required: !['buildingName', 'notes', 'unitsPerFloor', 'gasMeter']
              .contains(pair.key)),
    for (final entry in {
      'electricity': 'الكهرباء',
      'water': 'المياه',
      'gas': 'الغاز'
    }.entries) ...[
      ContractFieldSpec(
          'services.${entry.key}.enabled', 'تفعيل ${entry.value}', 4,
          required: false),
      ContractFieldSpec('services.${entry.key}.calculationMethod',
          'آلية احتساب ${entry.value}', 4,
          required: false,
          choices: [
            'حسب الفاتورة',
            'مبلغ مقطوع',
          ]),
      ContractFieldSpec(
          'services.${entry.key}.fixedAmount', 'مبلغ ${entry.value}', 4,
          required: false),
      ContractFieldSpec('services.${entry.key}.currentReading',
          'قراءة عداد ${entry.value}', 4,
          required: false),
    ],
    const ContractFieldSpec(
        'services.otherServices', 'خدمات أو شروط مالية إضافية', 4,
        required: false),
    const ContractFieldSpec('terms.specialTerms', 'شروط إضافية', 4,
        required: false),
  ];
  static final byPath = {for (final f in fields) f.path: f};

  static List<ContractFieldSpec> _party(String prefix) => [
        ContractFieldSpec('$prefix.kind', 'نوع الطرف', 2,
            choices: ['individual', 'company']),
        for (final entry in _partyLabels.entries)
          ContractFieldSpec('$prefix.${entry.key}', entry.value, 2,
              required: entry.key != 'email',
              choices: entry.key == 'idType'
                  ? ['هوية وطنية', 'إقامة', 'هوية خليجية', 'جواز سفر']
                  : entry.key == 'bankName'
                      ? saudiLicensedBanks
                      : const []),
      ];
  static const _partyLabels = {
    'fullName': 'الاسم الكامل',
    'idType': 'نوع الهوية',
    'idNumber': 'رقم الهوية',
    'birthDate': 'تاريخ الميلاد',
    'mobile': 'رقم جوال أبشر',
    'email': 'البريد الإلكتروني',
    'city': 'المدينة',
    'district': 'الحي',
    'nationalAddress': 'تفاصيل العنوان الوطني',
    'commercialRegistration': 'رقم السجل التجاري',
    'unifiedNumber': 'الرقم الموحد',
    'authorizedPersonName': 'اسم المفوض بالتوقيع',
    'authorizedPersonId': 'هوية المفوض',
    'iban': 'رقم الآيبان',
    'bankName': 'البنك',
    'accountOwner': 'اسم صاحب الحساب',
  };
  static final _representative = <ContractFieldSpec>[
    for (final entry in {
      'fullName': 'الاسم الكامل',
      'idNumber': 'رقم الهوية',
      'birthDate': 'تاريخ الميلاد',
      'mobile': 'رقم جوال أبشر',
      'authorizationNumber': 'رقم الوكالة أو السند',
      'authorizationDate': 'تاريخ الوكالة',
      'issuer': 'جهة الإصدار',
      'expiryDate': 'تاريخ الانتهاء',
    }.entries)
      ContractFieldSpec('representative.${entry.key}', entry.value, 2,
          required: !['authorizationDate', 'issuer', 'expiryDate']
              .contains(entry.key)),
    const ContractFieldSpec('representative.idType', 'نوع الهوية', 2,
        choices: ['هوية وطنية', 'إقامة', 'هوية خليجية']),
  ];
  static const _propertyLabels = {
    'ownershipDocumentNumber': 'رقم وثيقة الملكية',
    'ownershipDocumentDate': 'تاريخ وثيقة الملكية',
    'city': 'المدينة',
    'district': 'الحي',
    'street': 'الشارع',
    'buildingNumber': 'رقم المبنى',
    'additionalNumber': 'الرقم الإضافي',
    'postalCode': 'الرمز البريدي',
    'buildingName': 'اسم المبنى',
    'floorsCount': 'عدد الأدوار',
    'unitsPerFloor': 'عدد الوحدات في كل دور',
    'totalUnits': 'إجمالي عدد الوحدات',
    'unitName': 'اسم الوحدة',
    'floor': 'رقم الدور',
    'area': 'مساحة الوحدة',
    'roomsCount': 'عدد الغرف',
    'bathroomsCount': 'عدد دورات المياه',
    'hallsCount': 'عدد الصالات',
    'electricityMeter': 'رقم عداد الكهرباء',
    'waterMeter': 'رقم عداد المياه',
    'gasMeter': 'رقم عداد الغاز',
    'notes': 'ملاحظات العقار',
  };

  static bool applicable(ContractFieldSpec f, Map<String, Object?> data) {
    final p = f.path;
    if (p.startsWith('representative.') &&
        p != 'representative.enabled' &&
        readContractPath(data, 'representative.enabled') != true) {
      return false;
    }
    if (p == 'financial.securityDeposit' &&
        readContractPath(data, 'financial.hasSecurityDeposit') != true) {
      return false;
    }
    if (p == 'financial.vatValue' &&
        readContractPath(data, 'financial.ownerSubjectToVat') != true) {
      return false;
    }
    if (p == 'property.roomsCount' && data['type'] == 'commercial') {
      return false;
    }
    if (p.startsWith('lessor.') || p.startsWith('tenant.')) {
      final prefix = p.split('.').first;
      final field = p.split('.').last;
      final company = readContractPath(data, '$prefix.kind') == 'company';
      if (company && ['idNumber', 'idType', 'birthDate'].contains(field)) {
        return false;
      }
      if (!company &&
          [
            'commercialRegistration',
            'unifiedNumber',
            'authorizedPersonName',
            'authorizedPersonId'
          ].contains(field)) {
        return false;
      }
      if (prefix == 'tenant' &&
          ['iban', 'bankName', 'accountOwner'].contains(field)) {
        return false;
      }
    }
    return true;
  }

  static String? validate(
      ContractFieldSpec f, Object? value, Map<String, Object?> root) {
    if (value is bool) return null;
    final text = '$value'.trim();
    if (value == null || text.isEmpty) {
      return f.required ? 'هذا الحقل مطلوب' : null;
    }
    if (text.length > (f.path == 'terms.specialTerms' ? 4000 : 500)) {
      return 'القيمة طويلة جدًا';
    }
    if (f.choices.isNotEmpty && !f.choices.contains(text)) {
      return 'اختر قيمة من الخيارات المتاحة';
    }
    final key = f.path.split('.').last;
    if (key == 'idNumber') {
      return validateContractIdentityNumber(text,
          '${readContractPath(root, '${f.path.split('.').first}.idType')}');
    }
    if (key == 'birthDate') return validateAdultBirthDate(text);
    if (key.toLowerCase().contains('date')) {
      if (ContractCalculationEngine.date(text) == null) {
        return 'أدخل تاريخًا ميلاديًا صحيحًا سنة/شهر/يوم';
      }
    }
    if (key == 'mobile' && !RegExp(r'^(05\d{8}|5\d{8})$').hasMatch(text)) {
      return 'رقم الجوال غير صحيح';
    }
    if (key == 'iban' &&
        !RegExp(r'^SA\d{22}$')
            .hasMatch(text.replaceAll(' ', '').toUpperCase())) {
      return 'الآيبان السعودي غير صحيح';
    }
    if ([
      'rentValue',
      'securityDeposit',
      'brokerageFee',
      'otherAmounts',
      'vatValue',
      'fixedAmount'
    ].contains(key)) {
      final money = ContractCalculationEngine.money(text);
      if (money == null || (key == 'rentValue' && money <= 0)) {
        return 'أدخل مبلغًا صحيحًا';
      }
    }
    if ([
      'years',
      'months',
      'days',
      'floorsCount',
      'unitsPerFloor',
      'totalUnits',
      'roomsCount',
      'bathroomsCount',
      'hallsCount'
    ].contains(key)) {
      final number = int.tryParse(text);
      final max = switch (key) {
        'years' => 50,
        'months' => 11,
        'days' => 30,
        _ => 9999
      };
      if (number == null || number < 0 || number > max) {
        return 'أدخل عددًا صحيحًا ضمن الحدود';
      }
    }
    if (key == 'area' && (double.tryParse(text) ?? 0) <= 0) {
      return 'المساحة يجب أن تكون أكبر من صفر';
    }
    if (['buildingNumber', 'additionalNumber', 'postalCode'].contains(key) &&
        !RegExp('^\\d{${key == 'postalCode' ? 5 : 4}}\$').hasMatch(text)) {
      return 'عدد خانات غير صحيح';
    }
    return null;
  }
}
