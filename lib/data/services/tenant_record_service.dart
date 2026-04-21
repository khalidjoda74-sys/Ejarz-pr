import '../../models/tenant.dart';
import '../../utils/ksa_time.dart';

class TenantValidationIssue {
  final String field;
  final String label;
  final String message;

  const TenantValidationIssue({
    required this.field,
    required this.label,
    required this.message,
  });

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'label': label,
      'message': message,
    };
  }
}

class TenantUpsertResult {
  final TenantDraft? draft;
  final String? errorMessage;
  final List<TenantValidationIssue> missingFields;

  const TenantUpsertResult.success(this.draft)
      : errorMessage = null,
        missingFields = const <TenantValidationIssue>[];

  const TenantUpsertResult.error(this.errorMessage)
      : draft = null,
        missingFields = const <TenantValidationIssue>[];

  const TenantUpsertResult.missing(this.missingFields)
      : draft = null,
        errorMessage = null;

  bool get isValid =>
      draft != null && errorMessage == null && missingFields.isEmpty;

  String? get firstIssueMessage {
    final message = (errorMessage ?? '').trim();
    if (message.isNotEmpty) return message;
    if (missingFields.isNotEmpty) return missingFields.first.message;
    return null;
  }

  bool get requiresScreenCompletion =>
      missingFields.any((issue) => issue.field == 'attachmentPaths');
}

class TenantDraft {
  final String clientType;
  final String fullName;
  final String nationalId;
  final String phone;
  final String? email;
  final DateTime? dateOfBirth;
  final String? nationality;
  final DateTime? idExpiry;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? notes;
  final String? tenantBankName;
  final String? tenantBankAccountNumber;
  final String? tenantTaxNumber;
  final String? companyName;
  final String? companyCommercialRegister;
  final String? companyTaxNumber;
  final String? companyRepresentativeName;
  final String? companyRepresentativePhone;
  final String? companyBankAccountNumber;
  final String? companyBankName;
  final String? serviceSpecialization;
  final List<String> attachmentPaths;

  const TenantDraft({
    required this.clientType,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.email,
    required this.dateOfBirth,
    required this.nationality,
    required this.idExpiry,
    required this.emergencyName,
    required this.emergencyPhone,
    required this.notes,
    required this.tenantBankName,
    required this.tenantBankAccountNumber,
    required this.tenantTaxNumber,
    required this.companyName,
    required this.companyCommercialRegister,
    required this.companyTaxNumber,
    required this.companyRepresentativeName,
    required this.companyRepresentativePhone,
    required this.companyBankAccountNumber,
    required this.companyBankName,
    required this.serviceSpecialization,
    required this.attachmentPaths,
  });

  void applyTo(Tenant tenant) {
    tenant.clientType = clientType;
    tenant.fullName = fullName;
    tenant.nationalId = nationalId;
    tenant.phone = phone;
    tenant.email = email;
    tenant.dateOfBirth = dateOfBirth;
    tenant.nationality = nationality;
    tenant.idExpiry = idExpiry;
    tenant.emergencyName = emergencyName;
    tenant.emergencyPhone = emergencyPhone;
    tenant.notes = notes;
    tenant.tenantBankName = tenantBankName;
    tenant.tenantBankAccountNumber = tenantBankAccountNumber;
    tenant.tenantTaxNumber = tenantTaxNumber;
    tenant.companyName = companyName;
    tenant.companyCommercialRegister = companyCommercialRegister;
    tenant.companyTaxNumber = companyTaxNumber;
    tenant.companyRepresentativeName = companyRepresentativeName;
    tenant.companyRepresentativePhone = companyRepresentativePhone;
    tenant.companyBankAccountNumber = companyBankAccountNumber;
    tenant.companyBankName = companyBankName;
    tenant.serviceSpecialization = serviceSpecialization;
    tenant.attachmentPaths = List<String>.from(attachmentPaths);
  }

  Tenant createNew({
    required String id,
    DateTime? now,
  }) {
    final effectiveNow = now ?? KsaTime.now();
    return Tenant(
      id: id,
      clientType: clientType,
      fullName: fullName,
      nationalId: nationalId,
      phone: phone,
      email: email,
      dateOfBirth: dateOfBirth,
      nationality: nationality,
      idExpiry: idExpiry,
      emergencyName: emergencyName,
      emergencyPhone: emergencyPhone,
      notes: notes,
      tenantBankName: tenantBankName,
      tenantBankAccountNumber: tenantBankAccountNumber,
      tenantTaxNumber: tenantTaxNumber,
      companyName: companyName,
      companyCommercialRegister: companyCommercialRegister,
      companyTaxNumber: companyTaxNumber,
      companyRepresentativeName: companyRepresentativeName,
      companyRepresentativePhone: companyRepresentativePhone,
      companyBankAccountNumber: companyBankAccountNumber,
      companyBankName: companyBankName,
      serviceSpecialization: serviceSpecialization,
      attachmentPaths: List<String>.from(attachmentPaths),
      isArchived: false,
      isBlacklisted: false,
      blacklistReason: null,
      createdAt: effectiveNow,
      updatedAt: effectiveNow,
    );
  }
}

class TenantRecordService {
  static const String clientTypeTenant = 'tenant';
  static const String clientTypeCompany = 'company';
  static const String clientTypeServiceProvider = 'serviceProvider';

  static final RegExp _lettersOnly = RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$");
  static final RegExp _digitsUpToTen = RegExp(r'^\d{1,10}$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _emailPattern =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');

  static String normalizeClientType(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return clientTypeTenant;
    if (value == 'tenant' || value == 'مستأجر') return clientTypeTenant;
    if (value == 'company' || value == 'مستأجر (شركة)' || value == 'شركة') {
      return clientTypeCompany;
    }
    if (value == 'serviceprovider' ||
        value == 'service_provider' ||
        value == 'service provider' ||
        value == 'مقدم خدمة') {
      return clientTypeServiceProvider;
    }
    return clientTypeTenant;
  }

  static String effectiveClientType(Tenant tenant) {
    final normalized = normalizeClientType(tenant.clientType);
    if (normalized != clientTypeTenant) return normalized;

    final hasProviderHints =
        (tenant.serviceSpecialization ?? '').trim().isNotEmpty &&
            (tenant.companyName ?? '').trim().isEmpty &&
            (tenant.companyCommercialRegister ?? '').trim().isEmpty &&
            (tenant.tenantBankName ?? '').trim().isEmpty;
    if (hasProviderHints) return clientTypeServiceProvider;
    return normalized;
  }

  static bool clientTypeRequiresAttachments(String type) {
    return normalizeClientType(type) != clientTypeServiceProvider;
  }

  static String clientTypeLabel(String type) {
    switch (normalizeClientType(type)) {
      case clientTypeCompany:
        return 'مستأجر (شركة)';
      case clientTypeServiceProvider:
        return 'مقدم خدمة';
      case clientTypeTenant:
      default:
        return 'مستأجر';
    }
  }

  static List<TenantValidationIssue> requiredFieldsForType(String type) {
    switch (normalizeClientType(type)) {
      case clientTypeCompany:
        return const <TenantValidationIssue>[
          TenantValidationIssue(
            field: 'companyName',
            label: 'اسم الشركة',
            message: 'اسم الشركة مطلوب',
          ),
          TenantValidationIssue(
            field: 'companyCommercialRegister',
            label: 'رقم السجل التجاري',
            message: 'رقم السجل التجاري مطلوب',
          ),
          TenantValidationIssue(
            field: 'companyTaxNumber',
            label: 'الرقم الضريبي',
            message: 'الرقم الضريبي مطلوب',
          ),
          TenantValidationIssue(
            field: 'companyRepresentativeName',
            label: 'اسم ممثل الشركة',
            message: 'اسم ممثل الشركة مطلوب',
          ),
          TenantValidationIssue(
            field: 'companyRepresentativePhone',
            label: 'رقم جوال ممثل الشركة',
            message: 'رقم جوال ممثل الشركة مطلوب',
          ),
          TenantValidationIssue(
            field: 'attachmentPaths',
            label: 'المرفقات',
            message: 'أضف مرفقًا واحدًا على الأقل',
          ),
        ];
      case clientTypeServiceProvider:
        return const <TenantValidationIssue>[
          TenantValidationIssue(
            field: 'fullName',
            label: 'الاسم الكامل',
            message: 'الاسم الكامل مطلوب',
          ),
          TenantValidationIssue(
            field: 'phone',
            label: 'رقم الجوال',
            message: 'رقم الجوال مطلوب',
          ),
          TenantValidationIssue(
            field: 'serviceSpecialization',
            label: 'التخصص/الخدمة',
            message: 'التخصص/الخدمة مطلوب',
          ),
        ];
      case clientTypeTenant:
      default:
        return const <TenantValidationIssue>[
          TenantValidationIssue(
            field: 'fullName',
            label: 'الاسم الكامل',
            message: 'الاسم الكامل مطلوب',
          ),
          TenantValidationIssue(
            field: 'nationalId',
            label: 'رقم الهوية',
            message: 'رقم الهوية مطلوب',
          ),
          TenantValidationIssue(
            field: 'phone',
            label: 'رقم الجوال',
            message: 'رقم الجوال مطلوب',
          ),
          TenantValidationIssue(
            field: 'attachmentPaths',
            label: 'المرفقات',
            message: 'أضف مرفقًا واحدًا على الأقل',
          ),
        ];
    }
  }

  static List<Map<String, dynamic>> requiredFieldDescriptors(String type) {
    return requiredFieldsForType(type)
        .map((issue) => issue.toJson())
        .toList(growable: false);
  }

  static String addedClientSuccessMessage(String type) {
    switch (normalizeClientType(type)) {
      case clientTypeCompany:
        return 'تم إضافة مستأجر (شركة) بنجاح';
      case clientTypeServiceProvider:
        return 'تم إضافة مزود خدمة بنجاح';
      case clientTypeTenant:
      default:
        return 'تم إضافة مستأجر بنجاح';
    }
  }

  static String? archiveBlockedMessage(
    Tenant tenant, {
    required int currentProviderRequests,
  }) {
    final type = effectiveClientType(tenant);
    if (type == clientTypeServiceProvider) {
      if (currentProviderRequests > 0) {
        return 'لا يمكن أرشفة مقدم الخدمة لوجود طلبات خدمات سارية مرتبطة به. '
            'يمكنك أرشفته فقط إذا لم تعد هناك طلبات خدمات سارية.';
      }
      return null;
    }

    if (tenant.activeContractsCount > 0) {
      return 'لا يمكن أرشفة هذا العميل لوجود عقود نشطة مرتبطة به. '
          'يمكنك أرشفته بعد إنهاء العقود النشطة.';
    }
    return null;
  }

  static TenantUpsertResult prepareForUpsert({
    required String clientType,
    String? fullName,
    String? nationalId,
    String? phone,
    String? email,
    String? nationality,
    DateTime? dateOfBirth,
    DateTime? idExpiry,
    String? emergencyName,
    String? emergencyPhone,
    String? notes,
    String? companyName,
    String? companyCommercialRegister,
    String? companyTaxNumber,
    String? companyRepresentativeName,
    String? companyRepresentativePhone,
    String? serviceSpecialization,
    Object? attachmentPaths,
    Iterable<Tenant> existingTenants = const <Tenant>[],
    String? editingTenantId,
  }) {
    final normalizedType = normalizeClientType(clientType);
    final normalizedAttachments = _normalizeAttachmentPaths(attachmentPaths);

    final normalizedFullName = normalizedType == clientTypeCompany
        ? _optional(companyName)
        : _optional(fullName);
    final normalizedNationalId = normalizedType == clientTypeCompany
        ? _optional(companyCommercialRegister)
        : _optional(nationalId);
    final normalizedPhone = normalizedType == clientTypeCompany
        ? _optional(companyRepresentativePhone)
        : _optional(phone);
    final emailValue =
        normalizedType == clientTypeCompany ? null : _optional(email);
    final nationalityValue = normalizedType == clientTypeTenant
        ? _optional(nationality)
        : null;
    final dateOfBirthValue = normalizedType == clientTypeTenant
        ? (dateOfBirth == null ? null : KsaTime.dateOnly(dateOfBirth))
        : null;
    final idExpiryValue = normalizedType == clientTypeTenant
        ? (idExpiry == null ? null : KsaTime.dateOnly(idExpiry))
        : null;
    final emergencyNameValue = normalizedType == clientTypeTenant
        ? _optional(emergencyName)
        : null;
    final emergencyPhoneValue = normalizedType == clientTypeTenant
        ? _optional(emergencyPhone)
        : null;
    final notesValue =
        normalizedType == clientTypeCompany ? null : _optional(notes);
    final companyNameValue = normalizedType == clientTypeCompany
        ? _optional(companyName)
        : null;
    final companyRegisterValue = normalizedType == clientTypeCompany
        ? _optional(companyCommercialRegister)
        : null;
    final companyTaxValue = normalizedType == clientTypeCompany
        ? _optional(companyTaxNumber)
        : null;
    final companyRepNameValue = normalizedType == clientTypeCompany
        ? _optional(companyRepresentativeName)
        : null;
    final companyRepPhoneValue = normalizedType == clientTypeCompany
        ? _optional(companyRepresentativePhone)
        : null;
    final serviceSpecializationValue =
        normalizedType == clientTypeServiceProvider
            ? _optional(serviceSpecialization)
            : null;

    final missingFields = <TenantValidationIssue>[];

    if (normalizedType != clientTypeCompany && normalizedFullName == null) {
      missingFields.add(_missing(
        'fullName',
        'الاسم الكامل',
        'الاسم الكامل مطلوب',
      ));
    }
    if (normalizedType != clientTypeCompany && normalizedPhone == null) {
      missingFields.add(_missing(
        'phone',
        'رقم الجوال',
        'رقم الجوال مطلوب',
      ));
    }
    if (normalizedType == clientTypeTenant && normalizedNationalId == null) {
      missingFields.add(_missing(
        'nationalId',
        'رقم الهوية',
        'رقم الهوية مطلوب',
      ));
    }
    if (normalizedType == clientTypeCompany && companyNameValue == null) {
      missingFields.add(_missing(
        'companyName',
        'اسم الشركة',
        'اسم الشركة مطلوب',
      ));
    }
    if (normalizedType == clientTypeCompany && companyRegisterValue == null) {
      missingFields.add(_missing(
        'companyCommercialRegister',
        'رقم السجل التجاري',
        'رقم السجل التجاري مطلوب',
      ));
    }
    if (normalizedType == clientTypeCompany && companyTaxValue == null) {
      missingFields.add(_missing(
        'companyTaxNumber',
        'الرقم الضريبي',
        'الرقم الضريبي مطلوب',
      ));
    }
    if (normalizedType == clientTypeCompany && companyRepNameValue == null) {
      missingFields.add(_missing(
        'companyRepresentativeName',
        'اسم ممثل الشركة',
        'اسم ممثل الشركة مطلوب',
      ));
    }
    if (normalizedType == clientTypeCompany && companyRepPhoneValue == null) {
      missingFields.add(_missing(
        'companyRepresentativePhone',
        'رقم جوال ممثل الشركة',
        'رقم جوال ممثل الشركة مطلوب',
      ));
    }
    if (normalizedType == clientTypeServiceProvider &&
        serviceSpecializationValue == null) {
      missingFields.add(_missing(
        'serviceSpecialization',
        'التخصص/الخدمة',
        'التخصص/الخدمة مطلوب',
      ));
    }
    if (clientTypeRequiresAttachments(normalizedType) &&
        normalizedAttachments.isEmpty) {
      missingFields.add(_missing(
        'attachmentPaths',
        'المرفقات',
        'أضف مرفقًا واحدًا على الأقل',
      ));
    }
    if (missingFields.isNotEmpty) {
      return TenantUpsertResult.missing(missingFields);
    }

    if (normalizedType != clientTypeCompany &&
        normalizedFullName != null &&
        !_lettersOnly.hasMatch(normalizedFullName)) {
      return const TenantUpsertResult.error(
        'الاسم يجب أن يكون حروفًا ومسافات فقط',
      );
    }
    if (normalizedType != clientTypeCompany &&
        normalizedFullName != null &&
        normalizedFullName.length > 50) {
      return const TenantUpsertResult.error('الحد الأقصى للاسم 50 حرفًا');
    }
    if (normalizedType != clientTypeCompany &&
        normalizedPhone != null &&
        !_digitsUpToTen.hasMatch(normalizedPhone)) {
      return const TenantUpsertResult.error(
        'رقم الجوال يجب أن يكون أرقامًا فقط وبحد أقصى 10 أرقام',
      );
    }
    if (normalizedType != clientTypeCompany &&
        normalizedNationalId != null &&
        !_digitsUpToTen.hasMatch(normalizedNationalId)) {
      return const TenantUpsertResult.error(
        'رقم الهوية يجب أن يكون أرقامًا فقط وبحد أقصى 10 أرقام',
      );
    }
    if (companyRegisterValue != null && !_digitsOnly.hasMatch(companyRegisterValue)) {
      return const TenantUpsertResult.error(
        'رقم السجل التجاري يجب أن يحتوي على أرقام فقط',
      );
    }
    if (companyTaxValue != null && !_digitsOnly.hasMatch(companyTaxValue)) {
      return const TenantUpsertResult.error(
        'الرقم الضريبي يجب أن يحتوي على أرقام فقط',
      );
    }
    if (companyRepPhoneValue != null &&
        !_digitsUpToTen.hasMatch(companyRepPhoneValue)) {
      return const TenantUpsertResult.error(
        'رقم جوال ممثل الشركة يجب أن يكون أرقامًا فقط وبحد أقصى 10 أرقام',
      );
    }
    if (emailValue != null && emailValue.length > 40) {
      return const TenantUpsertResult.error('الحد الأقصى للبريد الإلكتروني 40 حرفًا');
    }
    if (emailValue != null && !_emailPattern.hasMatch(emailValue)) {
      return const TenantUpsertResult.error(
        'صيغة البريد الإلكتروني غير صحيحة',
      );
    }
    if (nationalityValue != null && !_lettersOnly.hasMatch(nationalityValue)) {
      return const TenantUpsertResult.error(
        'الجنسية يجب أن تكون حروفًا ومسافات فقط',
      );
    }
    if (nationalityValue != null && nationalityValue.length > 20) {
      return const TenantUpsertResult.error('الحد الأقصى للجنسية 20 حرفًا');
    }
    if (emergencyNameValue != null && !_lettersOnly.hasMatch(emergencyNameValue)) {
      return const TenantUpsertResult.error(
        'اسم الطوارئ يجب أن يكون حروفًا ومسافات فقط',
      );
    }
    if (emergencyNameValue != null && emergencyNameValue.length > 50) {
      return const TenantUpsertResult.error('الحد الأقصى لاسم الطوارئ 50 حرفًا');
    }
    if (emergencyPhoneValue != null &&
        !_digitsUpToTen.hasMatch(emergencyPhoneValue)) {
      return const TenantUpsertResult.error(
        'رقم طوارئ الجوال يجب أن يكون أرقامًا فقط وبحد أقصى 10 أرقام',
      );
    }
    if (notesValue != null && notesValue.length > 300) {
      return const TenantUpsertResult.error('الحد الأقصى للملاحظات 300 حرف');
    }

    if (normalizedType != clientTypeCompany && normalizedNationalId != null) {
      final currentId = (editingTenantId ?? '').trim();
      final hasDuplicateNationalId = existingTenants.any((tenant) {
        if (tenant.id.trim() == currentId) return false;
        return tenant.nationalId.trim() == normalizedNationalId;
      });
      if (hasDuplicateNationalId) {
        return const TenantUpsertResult.error('رقم الهوية مسجل مسبقًا');
      }
    }

    return TenantUpsertResult.success(
      TenantDraft(
        clientType: normalizedType,
        fullName: normalizedFullName ?? '',
        nationalId: normalizedNationalId ?? '',
        phone: normalizedPhone ?? '',
        email: emailValue,
        dateOfBirth: dateOfBirthValue,
        nationality: nationalityValue,
        idExpiry: idExpiryValue,
        emergencyName: emergencyNameValue,
        emergencyPhone: emergencyPhoneValue,
        notes: notesValue,
        tenantBankName: null,
        tenantBankAccountNumber: null,
        tenantTaxNumber: null,
        companyName: companyNameValue,
        companyCommercialRegister: companyRegisterValue,
        companyTaxNumber: companyTaxValue,
        companyRepresentativeName: companyRepNameValue,
        companyRepresentativePhone: companyRepPhoneValue,
        companyBankAccountNumber: null,
        companyBankName: null,
        serviceSpecialization: serviceSpecializationValue,
        attachmentPaths: normalizedAttachments,
      ),
    );
  }

  static TenantValidationIssue _missing(
    String field,
    String label,
    String message,
  ) {
    return TenantValidationIssue(
      field: field,
      label: label,
      message: message,
    );
  }

  static String? _optional(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<String> _normalizeAttachmentPaths(Object? raw) {
    if (raw is Iterable) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = (raw ?? '').toString().trim();
    if (single.isEmpty) return const <String>[];
    return <String>[single];
  }
}
