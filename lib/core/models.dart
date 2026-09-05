import 'package:flutter/material.dart';
import 'contract_pricing.dart';

const String kDemoContractPdfFileName = 'ejarz-demo-contract.pdf';
const String kDemoContractPdfUrl =
    'https://ejarz-pro-20260624.web.app/demo/ejarz-demo-contract.pdf';

enum ContractType { residential, commercial }

enum UserRole { lessor, tenant, authorized }

enum PartyKind { individual, company }

enum ContractStatus {
  draft,
  awaitingPayment,
  processing,
  missingData,
  authenticated,
  rejected,
}

enum PaymentMethod { mada, applePay, bankTransfer }

enum DemoPaymentMethod { mada, visaMastercard, applePay, stcPay }

extension DemoPaymentMethodX on DemoPaymentMethod {
  String get code => switch (this) {
        DemoPaymentMethod.mada => 'mada',
        DemoPaymentMethod.visaMastercard => 'visaMastercard',
        DemoPaymentMethod.applePay => 'applePay',
        DemoPaymentMethod.stcPay => 'stcPay',
      };

  String get label => switch (this) {
        DemoPaymentMethod.mada => 'مدى',
        DemoPaymentMethod.visaMastercard => 'Visa / Mastercard',
        DemoPaymentMethod.applePay => 'Apple Pay - Demo',
        DemoPaymentMethod.stcPay => 'STC Pay - Demo',
      };

  IconData get icon => switch (this) {
        DemoPaymentMethod.mada => Icons.credit_card_rounded,
        DemoPaymentMethod.visaMastercard => Icons.credit_score_rounded,
        DemoPaymentMethod.applePay => Icons.phone_iphone_rounded,
        DemoPaymentMethod.stcPay => Icons.account_balance_wallet_rounded,
      };

  bool get requiresCardForm =>
      this == DemoPaymentMethod.mada ||
      this == DemoPaymentMethod.visaMastercard;
}

extension ContractTypeX on ContractType {
  String get label => switch (this) {
        ContractType.residential => 'عقد سكني',
        ContractType.commercial => 'عقد تجاري',
      };

  String get description => switch (this) {
        ContractType.residential => 'إيجار وحدات سكنية',
        ContractType.commercial => 'إيجار وحدات تجارية وإدارية',
      };

  IconData get icon => switch (this) {
        ContractType.residential => Icons.home_work_outlined,
        ContractType.commercial => Icons.storefront_outlined,
      };
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.lessor => 'مؤجر',
        UserRole.tenant => 'مستأجر',
        UserRole.authorized => 'وكيل / وسيط',
      };

  String get description => switch (this) {
        UserRole.lessor => 'أقدم العقار للإيجار',
        UserRole.tenant => 'أستأجر العقار',
        UserRole.authorized => 'أتعامل كوكيل أو وسيط عقاري',
      };
}

extension ContractStatusX on ContractStatus {
  String get label => switch (this) {
        ContractStatus.draft => 'مسودة',
        ContractStatus.awaitingPayment => 'بانتظار الدفع',
        ContractStatus.processing => 'قيد المعالجة',
        ContractStatus.missingData => 'نواقص مطلوبة',
        ContractStatus.authenticated => 'مكتمل',
        ContractStatus.rejected => 'مرفوض',
      };

  Color get color => switch (this) {
        ContractStatus.draft => const Color(0xFF7A7F84),
        ContractStatus.awaitingPayment => const Color(0xFF9D6C00),
        ContractStatus.processing => const Color(0xFF2D73E0),
        ContractStatus.missingData => const Color(0xFFD85151),
        ContractStatus.authenticated => const Color(0xFF13875D),
        ContractStatus.rejected => const Color(0xFFC43D3D),
      };

  Color get paleColor => color.withValues(alpha: 0.11);

  IconData get icon => switch (this) {
        ContractStatus.draft => Icons.edit_note_rounded,
        ContractStatus.awaitingPayment => Icons.payments_outlined,
        ContractStatus.processing => Icons.miscellaneous_services_outlined,
        ContractStatus.missingData => Icons.error_outline_rounded,
        ContractStatus.authenticated => Icons.check_circle_outline_rounded,
        ContractStatus.rejected => Icons.cancel_outlined,
      };
}

class PartyData {
  PartyKind kind;
  String fullName;
  String idType;
  String idNumber;
  String birthDate;
  String mobile;
  String email;
  String city;
  String district;
  String nationalAddress;
  bool mobileRegisteredInAbsher;
  String commercialRegistration;
  String unifiedNumber;
  String authorizedPersonName;
  String authorizedPersonId;
  String iban;
  String bankName;
  String accountOwner;

  PartyData({
    this.kind = PartyKind.individual,
    this.fullName = '',
    this.idType = 'هوية وطنية',
    this.idNumber = '',
    this.birthDate = '',
    this.mobile = '',
    this.email = '',
    this.city = 'الرياض',
    this.district = '',
    this.nationalAddress = '',
    this.mobileRegisteredInAbsher = true,
    this.commercialRegistration = '',
    this.unifiedNumber = '',
    this.authorizedPersonName = '',
    this.authorizedPersonId = '',
    this.iban = '',
    this.bankName = '',
    this.accountOwner = '',
  });

  String get displayName => fullName.trim().isEmpty ? 'غير محدد' : fullName;
}

class RepresentativeData {
  bool enabled;
  String represents;
  String type;
  String fullName;
  String idType;
  String idNumber;
  String birthDate;
  String mobile;
  String authorizationNumber;
  String authorizationDate;
  String issuer;
  String expiryDate;

  RepresentativeData({
    this.enabled = false,
    this.represents = 'المؤجر',
    this.type = 'وكيل',
    this.fullName = '',
    this.idType = 'هوية وطنية',
    this.idNumber = '',
    this.birthDate = '',
    this.mobile = '',
    this.authorizationNumber = '',
    this.authorizationDate = '',
    this.issuer = '',
    this.expiryDate = '',
  });
}

class PropertyData {
  /// Empty for legacy records; `whole` or `units` for managed buildings.
  String rentalMode;
  String savedPropertyId;
  String propertySource;
  String ownershipDocumentNumber;
  String ownershipDocumentType;
  String ownershipDocumentDate;
  String propertyUsage;
  String propertyType;
  String floorsCount;
  String unitsPerFloor;
  String totalUnits;
  String city;
  String district;
  String street;
  String buildingNumber;
  String additionalNumber;
  String postalCode;
  String buildingName;
  String unitNumber;
  String unitName;
  String unitType;
  String floor;
  String area;
  String roomsCount;
  String bathroomsCount;
  String hallsCount;
  bool maidRoom;
  bool kitchen;
  bool storage;
  bool majlis;
  String furnishingStatus;
  bool acWindow;
  bool acSplit;
  bool acCentral;
  bool privateParking;
  String electricityMeter;
  String waterMeter;
  String gasMeter;
  String notes;

  PropertyData({
    this.rentalMode = '',
    this.savedPropertyId = '',
    this.propertySource = 'إضافة عقار جديد',
    this.ownershipDocumentNumber = '',
    this.ownershipDocumentType = 'صك إلكتروني',
    this.ownershipDocumentDate = '',
    this.propertyUsage = 'سكن عوائل',
    this.propertyType = 'عمارة',
    this.floorsCount = '',
    this.unitsPerFloor = '',
    this.totalUnits = '',
    this.city = 'الرياض',
    this.district = '',
    this.street = '',
    this.buildingNumber = '',
    this.additionalNumber = '',
    this.postalCode = '',
    this.buildingName = '',
    this.unitNumber = '',
    this.unitName = '',
    this.unitType = 'شقة',
    this.floor = '',
    this.area = '',
    this.roomsCount = '',
    this.bathroomsCount = '',
    this.hallsCount = '',
    this.maidRoom = false,
    this.kitchen = true,
    this.storage = false,
    this.majlis = false,
    this.furnishingStatus = 'غير مؤثثة',
    this.acWindow = false,
    this.acSplit = true,
    this.acCentral = false,
    this.privateParking = false,
    this.electricityMeter = '',
    this.waterMeter = '',
    this.gasMeter = '',
    this.notes = '',
  });

  String get displayAddress {
    final parts = <String>[
      if (city.trim().isNotEmpty) city,
      if (district.trim().isNotEmpty) district,
      if (street.trim().isNotEmpty) street,
    ];
    return parts.isEmpty ? 'العقار غير محدد' : parts.join(' - ');
  }

  factory PropertyData.copyOf(PropertyData source) => PropertyData(
        rentalMode: source.rentalMode,
        savedPropertyId: source.savedPropertyId,
        propertySource: source.propertySource,
        ownershipDocumentNumber: source.ownershipDocumentNumber,
        ownershipDocumentType: source.ownershipDocumentType,
        ownershipDocumentDate: source.ownershipDocumentDate,
        propertyUsage: source.propertyUsage,
        propertyType: source.propertyType,
        floorsCount: source.floorsCount,
        unitsPerFloor: source.unitsPerFloor,
        totalUnits: source.totalUnits,
        city: source.city,
        district: source.district,
        street: source.street,
        buildingNumber: source.buildingNumber,
        additionalNumber: source.additionalNumber,
        postalCode: source.postalCode,
        buildingName: source.buildingName,
        unitNumber: source.unitNumber,
        unitName: source.unitName,
        unitType: source.unitType,
        floor: source.floor,
        area: source.area,
        roomsCount: source.roomsCount,
        bathroomsCount: source.bathroomsCount,
        hallsCount: source.hallsCount,
        maidRoom: source.maidRoom,
        kitchen: source.kitchen,
        storage: source.storage,
        majlis: source.majlis,
        furnishingStatus: source.furnishingStatus,
        acWindow: source.acWindow,
        acSplit: source.acSplit,
        acCentral: source.acCentral,
        privateParking: source.privateParking,
        electricityMeter: source.electricityMeter,
        waterMeter: source.waterMeter,
        gasMeter: source.gasMeter,
        notes: source.notes,
      );
}

class ServiceCharge {
  bool enabled;
  String calculationMethod;
  String fixedAmount;
  String currentReading;

  ServiceCharge({
    this.enabled = false,
    this.calculationMethod = 'حسب الفاتورة',
    this.fixedAmount = '',
    this.currentReading = '',
  });
}

class UnitRecord {
  final String number;
  final String name;
  final String type;
  final String floor;
  final String area;
  final String status;
  final PropertyData? data;

  const UnitRecord({
    required this.number,
    required this.name,
    required this.type,
    required this.floor,
    required this.area,
    required this.status,
    this.data,
  });

  factory UnitRecord.fromData(PropertyData data, {String status = 'متاحة'}) =>
      UnitRecord(
        number: data.unitNumber.trim(),
        name: data.unitName.trim(),
        type: data.unitType,
        floor: data.floor,
        area: data.area,
        status: status,
        data: PropertyData.copyOf(data),
      );

  bool get isAvailable => status == 'available' || status == 'متاحة';

  PropertyData detailsFor(PropertyRecord property) {
    final result = data == null
        ? PropertyData(
            roomsCount: '',
            hallsCount: '',
            bathroomsCount: '',
          )
        : PropertyData.copyOf(data!);
    final parent = property.data;
    result
      ..savedPropertyId = property.id
      ..rentalMode = parent?.rentalMode ?? ''
      ..propertySource = 'عقار محفوظ'
      ..ownershipDocumentType = parent?.ownershipDocumentType ?? 'صك إلكتروني'
      ..ownershipDocumentNumber = parent?.ownershipDocumentNumber ?? ''
      ..ownershipDocumentDate = parent?.ownershipDocumentDate ?? ''
      ..propertyType = property.type
      ..propertyUsage = property.usage
      ..buildingName = property.title
      ..floorsCount = '${property.floors}'
      ..totalUnits = '${property.totalUnits}'
      ..unitsPerFloor = parent?.unitsPerFloor ?? ''
      ..city = property.city
      ..district = property.district
      ..street = parent?.street ?? ''
      ..buildingNumber = parent?.buildingNumber ?? ''
      ..additionalNumber = parent?.additionalNumber ?? ''
      ..postalCode = parent?.postalCode ?? ''
      ..unitNumber = number
      ..unitName = name
      ..unitType = type
      ..floor = floor
      ..area = area.replaceAll(' م²', '');
    // Older records stored the first unit's full details on the property.
    if (data == null && parent != null && parent.unitNumber == number) {
      return PropertyData.copyOf(parent)
        ..savedPropertyId = property.id
        ..propertySource = 'عقار محفوظ';
    }
    return result;
  }
}

class PropertyRecord {
  final String id;
  final String title;
  final String city;
  final String district;
  final String type;
  final String usage;
  final int floors;
  final int totalUnits;
  final List<UnitRecord> units;
  final PropertyData? data;

  const PropertyRecord({
    required this.id,
    required this.title,
    required this.city,
    required this.district,
    required this.type,
    required this.usage,
    required this.floors,
    required this.totalUnits,
    required this.units,
    this.data,
  });

  String get location => '$city - $district';

  bool get managesUnits =>
      data?.rentalMode == 'units' ||
      ((data?.rentalMode.isEmpty ?? true) &&
          (type == 'عمارة' || type == 'برج'));

  int get remainingUnits => (totalUnits - units.length).clamp(0, totalUnits);
}

class InstallmentData {
  int index;
  String amount;
  String dueDate;
  String note;

  InstallmentData({
    required this.index,
    this.amount = '',
    this.dueDate = '',
    this.note = '',
  });
}

class AttachmentData {
  final String keyName;
  final String title;
  final bool required;
  bool uploaded;
  String fileName;
  String sizeLabel;

  AttachmentData({
    required this.keyName,
    required this.title,
    this.required = true,
    this.uploaded = false,
    this.fileName = '',
    this.sizeLabel = '',
  });
}

class ContractDraft {
  ContractType type;
  UserRole role;
  PropertyData property;
  PartyData lessor;
  PartyData tenant;
  RepresentativeData representative;

  String startDate;
  String durationYears;
  String durationMonths;
  String durationDays;
  String endDate;
  String rentValue;
  String rentPeriod;
  bool hasSecurityDeposit;
  String securityDeposit;
  String brokerageFee;
  String brokeragePayer;
  bool ownerSubjectToVat;
  String vatValue;
  String otherAmounts;
  String paymentScheduleType;
  String paymentFrequency;
  int paymentCount;
  String firstPaymentDate;
  String paymentChannel;
  String officialFeePayer;
  String serviceFeePayer;

  ServiceCharge electricity;
  ServiceCharge water;
  ServiceCharge gas;
  String otherServices;

  bool allowSublease;
  bool autoRenewal;
  String specialTerms;
  bool acceptAccuracyDeclaration;
  bool acceptDataSharing;
  bool acceptTerms;
  PaymentMethod paymentMethod;

  List<InstallmentData> installments;
  List<AttachmentData> attachments;

  ContractDraft()
      : type = ContractType.residential,
        role = UserRole.lessor,
        property = PropertyData(),
        lessor = PartyData(),
        tenant = PartyData(),
        representative = RepresentativeData(),
        startDate = '',
        durationYears = '1',
        durationMonths = '0',
        durationDays = '0',
        endDate = '',
        rentValue = '',
        rentPeriod = 'سنوي',
        hasSecurityDeposit = false,
        securityDeposit = '',
        brokerageFee = '',
        brokeragePayer = 'المستأجر',
        ownerSubjectToVat = false,
        vatValue = '',
        otherAmounts = '',
        paymentScheduleType = 'دوري',
        paymentFrequency = 'ربع سنوي',
        paymentCount = 4,
        firstPaymentDate = '',
        paymentChannel = 'سداد / إيجار',
        officialFeePayer = 'المؤجر',
        serviceFeePayer = 'المستأجر',
        electricity = ServiceCharge(enabled: true),
        water = ServiceCharge(enabled: true),
        gas = ServiceCharge(),
        otherServices = '',
        allowSublease = false,
        autoRenewal = false,
        specialTerms = '',
        acceptAccuracyDeclaration = false,
        acceptDataSharing = false,
        acceptTerms = false,
        paymentMethod = PaymentMethod.mada,
        installments = <InstallmentData>[],
        attachments = <AttachmentData>[
          AttachmentData(keyName: 'lessor_id', title: 'هوية المؤجر'),
          AttachmentData(keyName: 'tenant_id', title: 'هوية المستأجر'),
          AttachmentData(keyName: 'ownership', title: 'وثيقة الملكية'),
          AttachmentData(
            keyName: 'authorization',
            title: 'الوكالة أو التفويض',
            required: false,
          ),
          AttachmentData(keyName: 'iban', title: 'الآيبان', required: false),
          AttachmentData(
            keyName: 'commercial_registration',
            title: 'السجل التجاري',
            required: false,
          ),
          AttachmentData(
            keyName: 'national_address',
            title: 'العنوان الوطني',
            required: false,
          ),
        ];

  factory ContractDraft.copyOf(ContractDraft source) {
    final copy = ContractDraft()
      ..type = source.type
      ..role = source.role
      ..property = PropertyData(
        rentalMode: source.property.rentalMode,
        savedPropertyId: source.property.savedPropertyId,
        propertySource: source.property.propertySource,
        ownershipDocumentNumber: source.property.ownershipDocumentNumber,
        ownershipDocumentType: source.property.ownershipDocumentType,
        ownershipDocumentDate: source.property.ownershipDocumentDate,
        propertyUsage: source.property.propertyUsage,
        propertyType: source.property.propertyType,
        floorsCount: source.property.floorsCount,
        unitsPerFloor: source.property.unitsPerFloor,
        totalUnits: source.property.totalUnits,
        city: source.property.city,
        district: source.property.district,
        street: source.property.street,
        buildingNumber: source.property.buildingNumber,
        additionalNumber: source.property.additionalNumber,
        postalCode: source.property.postalCode,
        buildingName: source.property.buildingName,
        unitNumber: source.property.unitNumber,
        unitName: source.property.unitName,
        unitType: source.property.unitType,
        floor: source.property.floor,
        area: source.property.area,
        roomsCount: source.property.roomsCount,
        bathroomsCount: source.property.bathroomsCount,
        hallsCount: source.property.hallsCount,
        maidRoom: source.property.maidRoom,
        kitchen: source.property.kitchen,
        storage: source.property.storage,
        majlis: source.property.majlis,
        furnishingStatus: source.property.furnishingStatus,
        acWindow: source.property.acWindow,
        acSplit: source.property.acSplit,
        acCentral: source.property.acCentral,
        privateParking: source.property.privateParking,
        electricityMeter: source.property.electricityMeter,
        waterMeter: source.property.waterMeter,
        gasMeter: source.property.gasMeter,
        notes: source.property.notes,
      )
      ..lessor = _copyParty(source.lessor)
      ..tenant = _copyParty(source.tenant)
      ..representative = RepresentativeData(
        enabled: source.representative.enabled,
        represents: source.representative.represents,
        type: source.representative.type,
        fullName: source.representative.fullName,
        idType: source.representative.idType,
        idNumber: source.representative.idNumber,
        birthDate: source.representative.birthDate,
        mobile: source.representative.mobile,
        authorizationNumber: source.representative.authorizationNumber,
        authorizationDate: source.representative.authorizationDate,
        issuer: source.representative.issuer,
        expiryDate: source.representative.expiryDate,
      )
      ..startDate = source.startDate
      ..durationYears = source.durationYears
      ..durationMonths = source.durationMonths
      ..durationDays = source.durationDays
      ..endDate = source.endDate
      ..rentValue = source.rentValue
      ..rentPeriod = source.rentPeriod
      ..hasSecurityDeposit = source.hasSecurityDeposit
      ..securityDeposit = source.securityDeposit
      ..brokerageFee = source.brokerageFee
      ..brokeragePayer = source.brokeragePayer
      ..ownerSubjectToVat = source.ownerSubjectToVat
      ..vatValue = source.vatValue
      ..otherAmounts = source.otherAmounts
      ..paymentScheduleType = source.paymentScheduleType
      ..paymentFrequency = source.paymentFrequency
      ..paymentCount = source.paymentCount
      ..firstPaymentDate = source.firstPaymentDate
      ..paymentChannel = source.paymentChannel
      ..officialFeePayer = source.officialFeePayer
      ..serviceFeePayer = source.serviceFeePayer
      ..electricity = _copyService(source.electricity)
      ..water = _copyService(source.water)
      ..gas = _copyService(source.gas)
      ..otherServices = source.otherServices
      ..allowSublease = source.allowSublease
      ..autoRenewal = source.autoRenewal
      ..specialTerms = source.specialTerms
      ..acceptAccuracyDeclaration = source.acceptAccuracyDeclaration
      ..acceptDataSharing = source.acceptDataSharing
      ..acceptTerms = source.acceptTerms
      ..paymentMethod = source.paymentMethod
      ..installments = source.installments
          .map(
            (item) => InstallmentData(
              index: item.index,
              amount: item.amount,
              dueDate: item.dueDate,
              note: item.note,
            ),
          )
          .toList()
      ..attachments = source.attachments
          .map(
            (item) => AttachmentData(
              keyName: item.keyName,
              title: item.title,
              required: item.required,
              uploaded: item.uploaded,
              fileName: item.fileName,
              sizeLabel: item.sizeLabel,
            ),
          )
          .toList();
    return copy;
  }

  static PartyData _copyParty(PartyData source) => PartyData(
        kind: source.kind,
        fullName: source.fullName,
        idType: source.idType,
        idNumber: source.idNumber,
        birthDate: source.birthDate,
        mobile: source.mobile,
        email: source.email,
        city: source.city,
        district: source.district,
        nationalAddress: source.nationalAddress,
        mobileRegisteredInAbsher: source.mobileRegisteredInAbsher,
        commercialRegistration: source.commercialRegistration,
        unifiedNumber: source.unifiedNumber,
        authorizedPersonName: source.authorizedPersonName,
        authorizedPersonId: source.authorizedPersonId,
        iban: source.iban,
        bankName: source.bankName,
        accountOwner: source.accountOwner,
      );

  static ServiceCharge _copyService(ServiceCharge source) => ServiceCharge(
        enabled: source.enabled,
        calculationMethod: source.calculationMethod,
        fixedAmount: source.fixedAmount,
        currentReading: source.currentReading,
      );

  double get rentValueNumber =>
      double.tryParse(rentValue.replaceAll(',', '')) ?? 0;

  double get depositNumber =>
      double.tryParse(securityDeposit.replaceAll(',', '')) ?? 0;

  ContractPrice get price => ContractPrice.calculate(
        commercial: type == ContractType.commercial,
        years: int.tryParse(durationYears) ?? 0,
        months: int.tryParse(durationMonths) ?? 0,
        days: int.tryParse(durationDays) ?? 0,
      );

  double get totalPayable => price.total;

  String get title {
    final unit = property.unitType.trim().isEmpty ? 'وحدة' : property.unitType;
    final district =
        property.district.trim().isEmpty ? property.city : property.district;
    return '${type.label} - $unit $district';
  }

  void regenerateInstallments() {
    final count = paymentCount <= 0 ? 1 : paymentCount;
    final total = rentValueNumber;
    final each = count == 0 ? total : total / count;
    installments = List<InstallmentData>.generate(
      count,
      (index) => InstallmentData(
        index: index + 1,
        amount: each == 0 ? '' : each.toStringAsFixed(2),
        dueDate: index == 0 ? firstPaymentDate : '',
        note: index == 0 ? 'دفعة مقدمة' : 'دفعة دورية',
      ),
    );
  }
}

class DraftProgress {
  final int lastStep;
  final List<String> touchedSections;

  const DraftProgress({
    this.lastStep = 0,
    this.touchedSections = const <String>[],
  });

  bool touched(String section) => touchedSections.contains(section);
}

class ContractRecord {
  final String id;
  final String requestNumber;
  final String uid;
  final ContractType type;
  final UserRole role;
  final String title;
  final String property;
  final String lessorName;
  final String tenantName;
  final String date;
  ContractStatus status;
  final double totalFees;
  final List<StatusTimelineItem> timeline;
  final String customerVisibleNote;
  final String rejectionReason;
  final DateTime? rejectedAt;
  final String rejectedBy;
  final String finalPdfUrl;
  final String finalPdfFileName;
  final List<MissingRequirement> missingRequirements;
  final String paymentStatus;
  final String paymentId;
  final String invoiceId;
  final String invoiceNumber;
  final String paymentMethod;
  final String paymentProvider;
  final String paymentReference;
  final String cardBrand;
  final String cardLast4;
  final String paidAt;
  final bool isDemo;
  final Map<String, String> contractDetails;
  final Map<String, String> partyDetails;
  final Map<String, String> propertyDetails;
  final Map<String, String> attachmentFiles;
  final bool pendingSync;
  final ContractDraft? draftData;
  final DraftProgress draftProgress;

  ContractRecord({
    required this.id,
    required this.requestNumber,
    this.uid = '',
    required this.type,
    required this.role,
    required this.title,
    required this.property,
    required this.lessorName,
    required this.tenantName,
    required this.date,
    required this.status,
    required this.totalFees,
    required this.timeline,
    this.customerVisibleNote = '',
    this.rejectionReason = '',
    this.rejectedAt,
    this.rejectedBy = '',
    this.finalPdfUrl = '',
    this.finalPdfFileName = '',
    this.missingRequirements = const <MissingRequirement>[],
    this.paymentStatus = '',
    this.paymentId = '',
    this.invoiceId = '',
    this.invoiceNumber = '',
    this.paymentMethod = '',
    this.paymentProvider = '',
    this.paymentReference = '',
    this.cardBrand = '',
    this.cardLast4 = '',
    this.paidAt = '',
    this.isDemo = false,
    this.contractDetails = const <String, String>{},
    this.partyDetails = const <String, String>{},
    this.propertyDetails = const <String, String>{},
    this.attachmentFiles = const <String, String>{},
    this.pendingSync = false,
    this.draftData,
    this.draftProgress = const DraftProgress(),
  });

  ContractRecord copyWith({
    ContractStatus? status,
    double? totalFees,
    List<StatusTimelineItem>? timeline,
    String? customerVisibleNote,
    String? rejectionReason,
    DateTime? rejectedAt,
    String? rejectedBy,
    String? finalPdfUrl,
    String? finalPdfFileName,
    String? paymentStatus,
    String? paymentId,
    String? invoiceId,
    String? invoiceNumber,
    String? paymentMethod,
    String? paymentProvider,
    String? paymentReference,
    String? cardBrand,
    String? cardLast4,
    String? paidAt,
    List<MissingRequirement>? missingRequirements,
    bool? isDemo,
    Map<String, String>? contractDetails,
    Map<String, String>? partyDetails,
    Map<String, String>? propertyDetails,
    Map<String, String>? attachmentFiles,
    bool? pendingSync,
    ContractDraft? draftData,
    DraftProgress? draftProgress,
  }) {
    return ContractRecord(
      id: id,
      requestNumber: requestNumber,
      uid: uid,
      type: type,
      role: role,
      title: title,
      property: property,
      lessorName: lessorName,
      tenantName: tenantName,
      date: date,
      status: status ?? this.status,
      totalFees: totalFees ?? this.totalFees,
      timeline: timeline ?? this.timeline,
      customerVisibleNote: customerVisibleNote ?? this.customerVisibleNote,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      finalPdfUrl: finalPdfUrl ?? this.finalPdfUrl,
      finalPdfFileName: finalPdfFileName ?? this.finalPdfFileName,
      missingRequirements: missingRequirements ?? this.missingRequirements,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentId: paymentId ?? this.paymentId,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentProvider: paymentProvider ?? this.paymentProvider,
      paymentReference: paymentReference ?? this.paymentReference,
      cardBrand: cardBrand ?? this.cardBrand,
      cardLast4: cardLast4 ?? this.cardLast4,
      paidAt: paidAt ?? this.paidAt,
      isDemo: isDemo ?? this.isDemo,
      contractDetails: contractDetails ?? this.contractDetails,
      partyDetails: partyDetails ?? this.partyDetails,
      propertyDetails: propertyDetails ?? this.propertyDetails,
      attachmentFiles: attachmentFiles ?? this.attachmentFiles,
      pendingSync: pendingSync ?? this.pendingSync,
      draftData: draftData ?? this.draftData,
      draftProgress: draftProgress ?? this.draftProgress,
    );
  }

  bool get isDemoPayment =>
      paymentProvider == 'demo' ||
      paymentReference.startsWith('DEMO-') ||
      paymentId.startsWith('PAY-DEMO');
}

class DemoPaymentResult {
  final bool success;
  final String paymentId;
  final String invoiceId;
  final String invoiceNumber;
  final String providerReference;
  final String failureReason;

  const DemoPaymentResult({
    required this.success,
    this.paymentId = '',
    this.invoiceId = '',
    this.invoiceNumber = '',
    this.providerReference = '',
    this.failureReason = '',
  });
}

class MissingRequirement {
  final String id;
  final String title;
  final String description;
  final String type;
  final String issueCode;
  final String fieldPath;
  final bool required;
  final bool resolved;

  const MissingRequirement({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.issueCode = '',
    this.fieldPath = '',
    this.required = true,
    this.resolved = false,
  });
}

class SupportReplyRecord {
  final String id;
  final String message;
  final String createdByName;
  final String visibility;
  final DateTime? createdAt;

  const SupportReplyRecord({
    required this.id,
    required this.message,
    required this.createdByName,
    this.visibility = 'customer',
    this.createdAt,
  });
}

class SupportTicketRecord {
  final String id;
  final String contractId;
  final String subject;
  final String message;
  final String status;
  final String priority;
  final DateTime? createdAt;
  final List<SupportReplyRecord> replies;

  const SupportTicketRecord({
    required this.id,
    this.contractId = '',
    required this.subject,
    this.message = '',
    this.status = 'open',
    this.priority = 'normal',
    this.createdAt,
    this.replies = const <SupportReplyRecord>[],
  });

  String get statusLabel => switch (status) {
        'pending' => 'بانتظار الرد',
        'resolved' => 'محلولة',
        'closed' => 'مغلقة',
        _ => 'مفتوحة',
      };
}

class StatusTimelineItem {
  final String title;
  final String subtitle;
  final String date;
  final String time;
  final bool completed;
  final bool current;
  final ContractStatus? eventStatus;

  const StatusTimelineItem({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.time,
    this.completed = false,
    this.current = false,
    this.eventStatus,
  });
}

class NotificationItem {
  final String id;
  final String contractId;
  final String title;
  final String body;
  final String time;
  final DateTime? createdAt;
  final String type;
  final String actionType;
  final Map<String, dynamic> actionPayload;
  final Map<String, bool> channels;
  final String priority;
  final DateTime? readAt;
  final DateTime? sentAt;
  final Map<String, dynamic> delivery;
  final IconData icon;
  final Color color;
  bool read;

  NotificationItem({
    this.id = '',
    this.contractId = '',
    required this.title,
    required this.body,
    required this.time,
    this.createdAt,
    this.type = 'general',
    this.actionType = '',
    this.actionPayload = const <String, dynamic>{},
    this.channels = const <String, bool>{},
    this.priority = 'normal',
    this.readAt,
    this.sentAt,
    this.delivery = const <String, dynamic>{},
    required this.icon,
    required this.color,
    this.read = false,
  });
}

class WalletTransaction {
  final String title;
  final String reference;
  final String date;
  final double amount;
  final bool incoming;
  final String contractId;

  const WalletTransaction({
    required this.title,
    required this.reference,
    required this.date,
    required this.amount,
    this.incoming = false,
    this.contractId = '',
  });
}
