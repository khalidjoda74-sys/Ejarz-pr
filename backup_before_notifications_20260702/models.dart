import 'package:flutter/material.dart';

enum ContractType { residential, commercial }

enum UserRole { lessor, tenant, authorized }

enum PartyKind { individual, company }

enum ContractStatus {
  draft,
  awaitingPayment,
  underReview,
  missingData,
  readyForEjar,
  enteredInEjar,
  awaitingAuthentication,
  authenticated,
  rejected,
}

enum PaymentMethod { mada, applePay, bankTransfer }

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
        ContractStatus.underReview => 'قيد المراجعة',
        ContractStatus.missingData => 'ناقص بيانات',
        ContractStatus.readyForEjar => 'جاهز للإدخال',
        ContractStatus.enteredInEjar => 'تم الإدخال في إيجار',
        ContractStatus.awaitingAuthentication => 'بانتظار التوثيق',
        ContractStatus.authenticated => 'مكتمل',
        ContractStatus.rejected => 'مرفوض',
      };

  Color get color => switch (this) {
        ContractStatus.draft => const Color(0xFF7A7F84),
        ContractStatus.awaitingPayment => const Color(0xFF9D6C00),
        ContractStatus.underReview => const Color(0xFF2D73E0),
        ContractStatus.missingData => const Color(0xFFD85151),
        ContractStatus.readyForEjar => const Color(0xFF7A5FD1),
        ContractStatus.enteredInEjar => const Color(0xFF0A7A5C),
        ContractStatus.awaitingAuthentication => const Color(0xFFE58B13),
        ContractStatus.authenticated => const Color(0xFF13875D),
        ContractStatus.rejected => const Color(0xFFC43D3D),
      };

  Color get paleColor => color.withValues(alpha: 0.11);

  IconData get icon => switch (this) {
        ContractStatus.draft => Icons.edit_note_rounded,
        ContractStatus.awaitingPayment => Icons.payments_outlined,
        ContractStatus.underReview => Icons.pending_actions_outlined,
        ContractStatus.missingData => Icons.error_outline_rounded,
        ContractStatus.readyForEjar => Icons.fact_check_outlined,
        ContractStatus.enteredInEjar => Icons.cloud_done_outlined,
        ContractStatus.awaitingAuthentication => Icons.schedule_rounded,
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

  const UnitRecord({
    required this.number,
    required this.name,
    required this.type,
    required this.floor,
    required this.area,
    required this.status,
  });
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
  });

  String get location => '$city - $district';
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
  bool urgent;
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
        urgent = false,
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

  double get rentValueNumber =>
      double.tryParse(rentValue.replaceAll(',', '')) ?? 0;

  double get depositNumber =>
      double.tryParse(securityDeposit.replaceAll(',', '')) ?? 0;

  double get serviceFee => 99;

  double get officialFee => 299;

  double get totalPayable => serviceFee + officialFee;

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
  final String finalPdfUrl;
  final String finalPdfFileName;
  final List<MissingRequirement> missingRequirements;

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
    this.finalPdfUrl = '',
    this.finalPdfFileName = '',
    this.missingRequirements = const <MissingRequirement>[],
  });
}

class MissingRequirement {
  final String id;
  final String title;
  final String description;
  final String type;
  final String fieldPath;
  final bool required;
  final bool resolved;

  const MissingRequirement({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.fieldPath = '',
    this.required = true,
    this.resolved = false,
  });
}

class StatusTimelineItem {
  final String title;
  final String subtitle;
  final String date;
  final String time;
  final bool completed;
  final bool current;

  const StatusTimelineItem({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.time,
    this.completed = false,
    this.current = false,
  });
}

class NotificationItem {
  final String title;
  final String body;
  final String time;
  final IconData icon;
  final Color color;
  bool read;

  NotificationItem({
    required this.title,
    required this.body,
    required this.time,
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

  const WalletTransaction({
    required this.title,
    required this.reference,
    required this.date,
    required this.amount,
    this.incoming = false,
  });
}
