import '../../models/property.dart';
import '../../ui/contracts_screen.dart'
    show AdvanceMode, Contract, ContractTerm, PaymentCycle;
import '../../ui/maintenance_screen.dart'
    show MaintenancePriority, MaintenanceStatus;
import '../../utils/ksa_time.dart';
import 'app_architecture_registry.dart';
import 'comprehensive_reports_service.dart';
import 'tenant_record_service.dart';

class AiChatValidationIssue {
  final String field;
  final String label;
  final String message;
  final bool requiresScreenCompletion;
  final String? suggestedScreen;

  const AiChatValidationIssue({
    required this.field,
    required this.label,
    required this.message,
    this.requiresScreenCompletion = false,
    this.suggestedScreen,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'field': field,
      'label': label,
      'message': message,
      'requiresScreenCompletion': requiresScreenCompletion,
      if ((suggestedScreen ?? '').trim().isNotEmpty)
        'suggestedScreen': suggestedScreen,
    };
  }
}

class AiChatValidationResult<T> {
  final T? draft;
  final String? errorMessage;
  final List<AiChatValidationIssue> missingFields;

  const AiChatValidationResult.success(this.draft)
      : errorMessage = null,
        missingFields = const <AiChatValidationIssue>[];

  const AiChatValidationResult.error(this.errorMessage)
      : draft = null,
        missingFields = const <AiChatValidationIssue>[];

  const AiChatValidationResult.missing(this.missingFields)
      : draft = null,
        errorMessage = null;

  bool get isValid =>
      draft != null && errorMessage == null && missingFields.isEmpty;

  String? get firstIssueMessage {
    final error = (errorMessage ?? '').trim();
    if (error.isNotEmpty) return error;
    if (missingFields.isNotEmpty) return missingFields.first.message;
    return null;
  }

  bool get requiresScreenCompletion {
    for (final issue in missingFields) {
      if (issue.requiresScreenCompletion) return true;
    }
    return false;
  }

  String? get suggestedScreen {
    for (final issue in missingFields) {
      final screen = (issue.suggestedScreen ?? '').trim();
      if (screen.isNotEmpty) return screen;
    }
    return null;
  }
}

class AiChatPropertyDraft {
  final String name;
  final PropertyType type;
  final String address;
  final RentalMode? rentalMode;
  final int totalUnits;
  final int? floors;
  final int? rooms;
  final double? area;
  final double? price;
  final String currency;
  final String description;
  final String documentType;
  final String documentNumber;
  final DateTime documentDate;
  final List<String> documentAttachmentPaths;

  const AiChatPropertyDraft({
    required this.name,
    required this.type,
    required this.address,
    required this.rentalMode,
    required this.totalUnits,
    required this.floors,
    required this.rooms,
    required this.area,
    required this.price,
    required this.currency,
    required this.description,
    required this.documentType,
    required this.documentNumber,
    required this.documentDate,
    required this.documentAttachmentPaths,
  });
}

class AiChatBuildingUnitDraft {
  final String unitName;
  final PropertyType unitType;
  final int? rooms;
  final double? area;
  final double? price;
  final String currency;
  final String description;

  const AiChatBuildingUnitDraft({
    required this.unitName,
    required this.unitType,
    required this.rooms,
    required this.area,
    required this.price,
    required this.currency,
    required this.description,
  });
}

class AiChatContractDraft {
  final DateTime startDate;
  final DateTime endDate;
  final double rentAmount;
  final double totalAmount;
  final ContractTerm term;
  final int termYears;
  final PaymentCycle paymentCycle;
  final int paymentCycleYears;
  final AdvanceMode advanceMode;
  final double? advancePaid;
  final int? dailyCheckoutHour;
  final String notes;
  final String ejarContractNo;
  final List<String> attachmentPaths;

  const AiChatContractDraft({
    required this.startDate,
    required this.endDate,
    required this.rentAmount,
    required this.totalAmount,
    required this.term,
    required this.termYears,
    required this.paymentCycle,
    required this.paymentCycleYears,
    required this.advanceMode,
    required this.advancePaid,
    required this.dailyCheckoutHour,
    required this.notes,
    required this.ejarContractNo,
    required this.attachmentPaths,
  });
}

class AiChatContractEditDraft {
  final double? rentAmount;
  final double? totalAmount;
  final String? notes;
  final String? ejarContractNo;
  final DateTime? endDate;
  final PaymentCycle? paymentCycle;
  final int? paymentCycleYears;
  final AdvanceMode? advanceMode;
  final double? advancePaid;
  final int? dailyCheckoutHour;

  const AiChatContractEditDraft({
    required this.rentAmount,
    required this.totalAmount,
    required this.notes,
    required this.ejarContractNo,
    required this.endDate,
    required this.paymentCycle,
    required this.paymentCycleYears,
    required this.advanceMode,
    required this.advancePaid,
    required this.dailyCheckoutHour,
  });
}

class AiChatContractRenewDraft {
  final DateTime newStartDate;
  final DateTime newEndDate;
  final double? newRentAmount;
  final double? newTotalAmount;
  final String? notes;

  const AiChatContractRenewDraft({
    required this.newStartDate,
    required this.newEndDate,
    required this.newRentAmount,
    required this.newTotalAmount,
    required this.notes,
  });
}

class AiChatInvoiceDraft {
  final double amount;
  final DateTime dueDate;
  final String note;

  const AiChatInvoiceDraft({
    required this.amount,
    required this.dueDate,
    required this.note,
  });
}

class AiChatManualVoucherDraft {
  final String kind;
  final double amount;
  final double signedAmount;
  final DateTime issueDate;
  final String title;
  final String partyName;
  final String description;
  final String paymentMethod;
  final List<String> attachmentPaths;
  final String? tenantName;
  final String? propertyName;

  const AiChatManualVoucherDraft({
    required this.kind,
    required this.amount,
    required this.signedAmount,
    required this.issueDate,
    required this.title,
    required this.partyName,
    required this.description,
    required this.paymentMethod,
    required this.attachmentPaths,
    required this.tenantName,
    required this.propertyName,
  });

  String buildInvoiceNote() {
    final lines = <String>[
      title,
      description,
      'الطرف: $partyName',
    ];
    return '${lines.join('\n').trim()}\n[POSTED] تم اعتماد السند';
  }
}

class AiChatMaintenanceDraft {
  final String title;
  final String description;
  final String requestType;
  final MaintenancePriority priority;
  final DateTime? scheduledDate;
  final DateTime? executionDeadline;
  final double cost;
  final String? providerName;
  final List<String> attachmentPaths;

  const AiChatMaintenanceDraft({
    required this.title,
    required this.description,
    required this.requestType,
    required this.priority,
    required this.scheduledDate,
    required this.executionDeadline,
    required this.cost,
    required this.providerName,
    required this.attachmentPaths,
  });
}

class AiChatMaintenanceStatusDraft {
  final MaintenanceStatus status;
  final double? cost;
  final String? providerName;
  final DateTime? scheduledDate;
  final DateTime? executionDeadline;

  const AiChatMaintenanceStatusDraft({
    required this.status,
    required this.cost,
    required this.providerName,
    required this.scheduledDate,
    required this.executionDeadline,
  });
}

class AiChatPeriodicServiceDraft {
  final String serviceType;
  final String? providerName;
  final double cost;
  final DateTime dueDate;

  const AiChatPeriodicServiceDraft({
    required this.serviceType,
    required this.providerName,
    required this.cost,
    required this.dueDate,
  });
}

class AiChatOfficeClientDraft {
  final String name;
  final String email;
  final String phone;
  final String notes;

  const AiChatOfficeClientDraft({
    required this.name,
    required this.email,
    required this.phone,
    required this.notes,
  });
}

class AiChatOfficeClientAccessDraft {
  final bool allowAccess;
  final bool blocked;

  const AiChatOfficeClientAccessDraft({
    required this.allowAccess,
    required this.blocked,
  });
}

class AiChatOfficeClientSubscriptionDraft {
  final DateTime? startDate;
  final double price;
  final int? reminderDays;

  const AiChatOfficeClientSubscriptionDraft({
    required this.startDate,
    required this.price,
    required this.reminderDays,
  });
}

class AiChatReportsPeriodDraft {
  final DateTime? fromDate;
  final DateTime? toDate;

  const AiChatReportsPeriodDraft({
    required this.fromDate,
    required this.toDate,
  });
}

class AiChatReportsOfficeVoucherDraft {
  final bool isExpense;
  final double amount;
  final DateTime transactionDate;
  final String note;

  const AiChatReportsOfficeVoucherDraft({
    required this.isExpense,
    required this.amount,
    required this.transactionDate,
    required this.note,
  });
}

class AiChatReportsOfficeWithdrawalDraft {
  final double amount;
  final DateTime transferDate;
  final String note;
  final DateTime? fromDate;
  final DateTime? toDate;

  const AiChatReportsOfficeWithdrawalDraft({
    required this.amount,
    required this.transferDate,
    required this.note,
    required this.fromDate,
    required this.toDate,
  });
}

class AiChatReportsCommissionRuleDraft {
  final CommissionMode mode;
  final double value;

  const AiChatReportsCommissionRuleDraft({
    required this.mode,
    required this.value,
  });
}

class AiChatReportsAssignPropertyOwnerDraft {
  final String propertyQuery;
  final String ownerQuery;

  const AiChatReportsAssignPropertyOwnerDraft({
    required this.propertyQuery,
    required this.ownerQuery,
  });
}

class AiChatReportsOwnerPayoutDraft {
  final String ownerQuery;
  final String? propertyQuery;
  final double amount;
  final DateTime transferDate;
  final String note;
  final DateTime? fromDate;
  final DateTime? toDate;

  const AiChatReportsOwnerPayoutDraft({
    required this.ownerQuery,
    required this.propertyQuery,
    required this.amount,
    required this.transferDate,
    required this.note,
    required this.fromDate,
    required this.toDate,
  });
}

class AiChatReportsOwnerAdjustmentDraft {
  final String ownerQuery;
  final String? propertyQuery;
  final OwnerAdjustmentCategory category;
  final double amount;
  final DateTime adjustmentDate;
  final String note;
  final DateTime? fromDate;
  final DateTime? toDate;

  const AiChatReportsOwnerAdjustmentDraft({
    required this.ownerQuery,
    required this.propertyQuery,
    required this.category,
    required this.amount,
    required this.adjustmentDate,
    required this.note,
    required this.fromDate,
    required this.toDate,
  });
}

class AiChatReportsOwnerBankAccountDraft {
  final String ownerQuery;
  final String bankName;
  final String accountNumber;
  final String iban;

  const AiChatReportsOwnerBankAccountDraft({
    required this.ownerQuery,
    required this.bankName,
    required this.accountNumber,
    required this.iban,
  });
}

class AiChatReportsOwnerBankAccountEditDraft {
  final String ownerQuery;
  final String accountQuery;
  final String bankName;
  final String accountNumber;
  final String iban;

  const AiChatReportsOwnerBankAccountEditDraft({
    required this.ownerQuery,
    required this.accountQuery,
    required this.bankName,
    required this.accountNumber,
    required this.iban,
  });
}

class AiChatReportsOwnerBankAccountDeleteDraft {
  final String ownerQuery;
  final String accountQuery;

  const AiChatReportsOwnerBankAccountDeleteDraft({
    required this.ownerQuery,
    required this.accountQuery,
  });
}

class AiChatDomainRulesService {
  AiChatDomainRulesService._();

  static Map<String, String> get supportedScreens =>
      AppArchitectureRegistry.allChatNavigationTitles();

  static const List<String> periodicServiceTypes = <String>[
    'cleaning',
    'elevator',
    'internet',
    'water',
    'electricity',
  ];

  static final RegExp _emailPattern =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static Map<String, dynamic> buildModulesPayload() {
    return <String, dynamic>{
      'clients': <String, dynamic>{
        'createTool': 'add_client_record',
        'editTool': 'edit_tenant',
        'detailsTool': 'get_tenant_details',
        'types': <Map<String, dynamic>>[
          _clientTypePayload(TenantRecordService.clientTypeTenant),
          _clientTypePayload(TenantRecordService.clientTypeCompany),
          _clientTypePayload(TenantRecordService.clientTypeServiceProvider),
        ],
        'archiveRules': const <String>[
          'لا يمكن أرشفة عميل لديه عقود نشطة.',
          'لا يمكن أرشفة مقدم خدمة لديه طلبات صيانة جارية.',
        ],
      },
      'properties': <String, dynamic>{
        'createTool': 'add_property',
        'editTool': 'edit_property',
        'archiveTool': 'archive_property',
        'unitTool': 'add_building_unit',
        'requiredFields': <String, dynamic>{
          'base': propertyBaseRequiredFields(),
          'document': propertyDocumentRequiredFields(),
          'buildingPerUnit': propertyPerUnitRequiredFields(),
          'unit': buildingUnitRequiredFields(),
        },
        'rules': const <String>[
          'اسم العقار مطلوب ولا يزيد عن 25 حرفًا.',
          'العنوان مطلوب ولا يزيد عن 50 حرفًا.',
          'نوع الوثيقة ورقمها وتاريخها ومرفقاتها مطلوبة دائمًا.',
          'العمارة تتطلب تحديد نمط التأجير.',
          'العمارة بنمط الوحدات تتطلب عدد وحدات من 1 إلى 500.',
          'لا يمكن تغيير نوع العقار إذا كان مرتبطًا بعقود أو وحدات.',
          'لا يمكن أرشفة عقار أو عمارة لها إشغال أو عقود نشطة.',
        ],
      },
      'contracts': <String, dynamic>{
        'createTool': 'create_contract',
        'editTool': 'edit_contract',
        'renewTool': 'renew_contract',
        'terminateTool': 'terminate_contract',
        'requiredFields': <String, dynamic>{
          'create': contractCreateRequiredFields(),
          'dailyExtra': contractDailyRequiredFields(),
        },
        'rules': const <String>[
          'يجب اختيار عميل غير محظور وعقار متاح وغير مؤرشف.',
          'تاريخ النهاية يجب أن يكون بعد تاريخ البداية.',
          'العقود اليومية تتطلب ساعة خروج.',
          'دورة السداد يجب أن تكون متوافقة مع مدة العقد.',
          'إذا كانت الخدمات الدورية المطلوبة غير مضبوطة يجب إكمالها قبل الإنشاء.',
        ],
      },
      'invoices': <String, dynamic>{
        'createTool': 'create_invoice',
        'manualVoucherTool': 'create_manual_voucher',
        'paymentTool': 'record_payment',
        'requiredFields': <String, dynamic>{
          'invoice': invoiceRequiredFields(),
          'manualVoucher': manualVoucherRequiredFields(),
        },
        'rules': const <String>[
          'إصدار الفاتورة العادية يتطلب رقم عقد صحيحًا.',
          'المبلغ يجب أن يكون أكبر من صفر.',
          'السند اليدوي يتطلب نوع السند والطرف والعنوان والبيان وطريقة الدفع.',
          'المبلغ في السند اليدوي لا يتجاوز 500000000.',
        ],
      },
      'maintenance': <String, dynamic>{
        'createTool': 'create_maintenance_request',
        'updateTool': 'update_maintenance_status',
        'periodicCreateTool': 'create_periodic_service',
        'periodicUpdateTool': 'update_periodic_service',
        'requiredFields': <String, dynamic>{
          'request': maintenanceRequiredFields(),
          'periodicService': periodicServiceRequiredFields(),
        },
        'periodicServiceTypes': periodicServiceTypes,
        'rules': const <String>[
          'العقار مطلوب ويجب ألا يكون مؤرشفًا هو أو العمارة التابعة له.',
          'عنوان طلب الصيانة مطلوب ولا يزيد عن 35 حرفًا.',
          'الوصف لا يزيد عن 2000 حرف.',
          'آخر موعد للتنفيذ يجب ألا يسبق تاريخ الجدولة.',
          'مقدم الخدمة إن وُجد يجب أن يكون من نوع مقدم خدمة.',
        ],
      },
      'officeClients': <String, dynamic>{
        'listTool': 'get_office_clients_list',
        'detailsTool': 'get_office_client_details',
        'summaryTool': 'get_office_summary',
        'createTool': 'add_office_client',
        'editTool': 'edit_office_client',
        'deleteTool': 'delete_office_client',
        'accessReadTool': 'get_office_client_access',
        'accessWriteTool': 'set_office_client_access',
        'subscriptionReadTool': 'get_office_client_subscription',
        'subscriptionWriteTool': 'set_office_client_subscription',
        'resetLinkTool': 'generate_office_client_reset_link',
        'requiredFields': officeClientRequiredFields(),
        'accessRequiredFields': officeClientAccessRequiredFields(),
        'subscriptionRequiredFields': officeClientSubscriptionRequiredFields(),
        'rules': const <String>[
          'اسم العميل مطلوب ولا يزيد عن 50 حرفًا.',
          'البريد الإلكتروني مطلوب وصالح ولا يزيد عن 40 حرفًا.',
          'رقم الجوال اختياري لكن إن وُجد يجب أن يكون 10 أرقام بالضبط.',
          'الملاحظات لا تزيد عن 1000 حرف.',
          'يجب احترام حدود الباقة قبل إضافة عميل جديد.',
          'تعديل عميل المكتب من الدردشة يدعم الاسم والجوال والملاحظات فقط، ولا يغيّر البريد الإلكتروني.',
          'حذف العميل يتم فقط بعد تأكيد المستخدم، سواء كان العميل محفوظًا أو لا يزال محليًا بانتظار المزامنة.',
          'إدارة الدخول وتوليد رابط إعادة التعيين متاحان فقط للعميل المحفوظ فعليًا وليس السجل المحلي المعلّق.',
          'إذا لم يكن للعميل حساب دخول فعلي بعد، فلا يمكن إيقافه أو السماح له أو توليد رابط إعادة تعيين له.',
          'تفعيل أو تجديد الاشتراك متاح فقط للعميل المحفوظ فعليًا وليس السجل المحلي المعلّق.',
          'اشتراك عميل المكتب في الدردشة شهري فقط مثل الشاشة، وسعره يجب أن يكون أكبر من صفر.',
          'موعد تنبيه الاشتراك يجب أن يكون من 1 إلى 3 أيام فقط.',
          'إذا كان للعميل اشتراك سابق محفوظ، فموعد بداية التجديد يُحدد تلقائيًا حسب منطق الشاشة ولا يُفرض يدويًا من الدردشة.',
        ],
      },
      'reports': <String, dynamic>{
        'tabs': const <String>[
          'dashboard',
          'properties',
          'clients',
          'contracts',
          'services',
          'vouchers',
          'office',
          'owners',
        ],
        'readTools': const <String>[
          'get_financial_summary',
          'get_properties_report',
          'get_clients_report',
          'get_contracts_report',
          'get_services_report',
          'get_invoices_report',
          'get_office_report',
          'get_owners_report',
          'get_owner_report_details',
          'preview_owner_settlement',
          'preview_office_settlement',
          'get_owner_bank_accounts',
        ],
        'writeTools': const <String>[
          'assign_property_owner_from_reports',
          'record_office_report_voucher',
          'record_office_withdrawal',
          'set_report_commission_rule',
          'record_owner_payout',
          'record_owner_adjustment',
          'add_owner_bank_account',
          'edit_owner_bank_account',
          'delete_owner_bank_account',
        ],
        'requiredFields': <String, dynamic>{
          'assignPropertyOwner': reportsAssignPropertyOwnerRequiredFields(),
          'officeVoucher': reportsOfficeVoucherRequiredFields(),
          'officeWithdrawal': reportsOfficeWithdrawalRequiredFields(),
          'commissionRule': reportsCommissionRuleRequiredFields(),
          'ownerPayout': reportsOwnerPayoutRequiredFields(),
          'ownerAdjustment': reportsOwnerAdjustmentRequiredFields(),
          'ownerBankAccount': reportsOwnerBankAccountRequiredFields(),
          'ownerBankAccountEdit': reportsOwnerBankAccountEditRequiredFields(),
          'ownerBankAccountDelete':
              reportsOwnerBankAccountDeleteRequiredFields(),
        },
        'rules': const <String>[
          'فلاتر التقارير تعتمد على fromDate و toDate بصيغة YYYY-MM-DD عند الحاجة.',
          'الربحية وصافي العقار والتقارير المالية يجب أن تُقرأ من شاشة التقارير نفسها وليس من تخمينات عامة.',
          'تحويل المالك وخصم/تسوية المالك لا يتجاوزان الرصيد القابل للتحويل حسب شاشة التقارير.',
          'مصروف المكتب وتحويل المكتب يلتزمان بنفس حدود شاشة التقارير، ومنها حد المبلغ والرصيد المتاح للتحويل.',
          'إيراد عمولة المكتب اليدوي متاح فقط عندما يكون نظام العمولة مبلغًا ثابتًا.',
          'لا يوجد إجراء مستقل باسم مصروف على المالك داخل شاشة التقارير؛ المتاح هو خصم/تسوية للمالك أو مصروفات خدمات مرتبطة فعليًا.',
          'حسابات البنوك للمالك تتطلب اسم البنك ورقم الحساب، وحذفها يحتاج تأكيد من المستخدم قبل التنفيذ.',
        ],
      },
      'navigation': <String, dynamic>{
        'supportedScreens': supportedScreens.keys.toList(growable: false),
      },
    };
  }

  static List<Map<String, dynamic>> propertyBaseRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('name', 'اسم العقار', 'اسم العقار مطلوب'),
      _issue('type', 'نوع العقار', 'نوع العقار مطلوب'),
      _issue('address', 'العنوان', 'العنوان مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> propertyDocumentRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('documentType', 'نوع الوثيقة', 'نوع الوثيقة مطلوب'),
      _issue('documentNumber', 'رقم الوثيقة', 'رقم الوثيقة مطلوب'),
      _issue('documentDate', 'تاريخ الوثيقة', 'تاريخ الوثيقة مطلوب'),
      _issue(
        'documentAttachmentPaths',
        'مرفقات الوثيقة',
        'مرفقات الوثيقة مطلوبة',
        requiresScreenCompletion: true,
        suggestedScreen: 'properties',
      ),
    ];
  }

  static List<Map<String, dynamic>> propertyPerUnitRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('rentalMode', 'نمط التأجير', 'نمط التأجير مطلوب'),
      _issue('totalUnits', 'عدد الوحدات', 'عدد الوحدات مطلوب في العمارة بنمط الوحدات'),
    ];
  }

  static List<Map<String, dynamic>> buildingUnitRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('buildingName', 'اسم العمارة', 'اسم العمارة مطلوب'),
      _issue('unitName', 'اسم الوحدة', 'اسم الوحدة مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> contractCreateRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('tenantName', 'العميل', 'اسم العميل مطلوب'),
      _issue('propertyName', 'العقار', 'اسم العقار مطلوب'),
      _issue('startDate', 'تاريخ البداية', 'تاريخ البداية مطلوب'),
      _issue('endDate', 'تاريخ النهاية', 'تاريخ النهاية مطلوب'),
      _issue('rentAmount', 'قيمة الإيجار', 'قيمة الإيجار مطلوبة'),
      _issue('totalAmount', 'إجمالي العقد', 'إجمالي العقد مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> contractDailyRequiredFields() {
    return <Map<String, dynamic>>[
      _issue(
        'dailyCheckoutHour',
        'ساعة الخروج',
        'ساعة الخروج مطلوبة في العقد اليومي',
      ),
    ];
  }

  static List<Map<String, dynamic>> invoiceRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('contractSerialNo', 'رقم العقد', 'رقم العقد مطلوب'),
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('dueDate', 'تاريخ الاستحقاق', 'تاريخ الاستحقاق مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> manualVoucherRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('kind', 'نوع السند', 'نوع السند مطلوب'),
      _issue('issueDate', 'تاريخ السند', 'تاريخ السند مطلوب'),
      _issue('partyName', 'اسم الطرف', 'اسم الطرف مطلوب'),
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('paymentMethod', 'طريقة الدفع', 'طريقة الدفع مطلوبة'),
      _issue('title', 'عنوان السند', 'عنوان السند مطلوب'),
      _issue('description', 'البيان', 'البيان مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> maintenanceRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('propertyName', 'العقار', 'العقار مطلوب'),
      _issue('title', 'نوع الخدمة', 'نوع الخدمة مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> periodicServiceRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('propertyName', 'العقار', 'العقار مطلوب'),
      _issue('serviceType', 'نوع الخدمة الدورية', 'نوع الخدمة الدورية مطلوب'),
      _issue('scheduledDate', 'تاريخ الدورة القادمة', 'تاريخ الدورة القادمة مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> officeClientRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('name', 'اسم العميل', 'اسم العميل مطلوب'),
      _issue('email', 'البريد الإلكتروني', 'البريد الإلكتروني مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> officeClientAccessRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('query', 'العميل', 'تحديد العميل مطلوب'),
      _issue('allowAccess', 'السماح بالدخول', 'حالة السماح أو الإيقاف مطلوبة'),
    ];
  }

  static List<Map<String, dynamic>> officeClientSubscriptionRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('query', 'العميل', 'تحديد العميل مطلوب'),
      _issue('price', 'سعر الاشتراك', 'سعر الاشتراك مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsAssignPropertyOwnerRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('propertyQuery', 'العقار', 'تحديد العقار مطلوب'),
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOfficeVoucherRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('isExpense', 'نوع العملية', 'تحديد هل العملية مصروف مكتب أم إيراد عمولة مطلوب'),
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('transactionDate', 'تاريخ العملية', 'تاريخ العملية مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOfficeWithdrawalRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('transferDate', 'تاريخ التحويل', 'تاريخ التحويل مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsCommissionRuleRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('mode', 'نوع العمولة', 'نوع العمولة مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOwnerPayoutRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('transferDate', 'تاريخ التحويل', 'تاريخ التحويل مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOwnerAdjustmentRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
      _issue('category', 'نوع الخصم/التسوية', 'نوع الخصم/التسوية مطلوب'),
      _issue('amount', 'المبلغ', 'المبلغ مطلوب'),
      _issue('adjustmentDate', 'تاريخ الخصم/التسوية', 'تاريخ الخصم/التسوية مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOwnerBankAccountRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
      _issue('bankName', 'اسم البنك', 'اسم البنك مطلوب'),
      _issue('accountNumber', 'رقم الحساب', 'رقم الحساب مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOwnerBankAccountEditRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
      _issue('accountQuery', 'الحساب البنكي', 'تحديد الحساب البنكي المطلوب مطلوب'),
      _issue('bankName', 'اسم البنك', 'اسم البنك مطلوب'),
      _issue('accountNumber', 'رقم الحساب', 'رقم الحساب مطلوب'),
    ];
  }

  static List<Map<String, dynamic>> reportsOwnerBankAccountDeleteRequiredFields() {
    return <Map<String, dynamic>>[
      _issue('ownerQuery', 'المالك', 'تحديد المالك مطلوب'),
      _issue('accountQuery', 'الحساب البنكي', 'تحديد الحساب البنكي المطلوب مطلوب'),
    ];
  }

  static AiChatValidationResult<AiChatPropertyDraft> validatePropertyUpsert({
    required Object? name,
    required Object? type,
    required Object? address,
    Object? rentalMode,
    Object? totalUnits,
    Object? floors,
    Object? rooms,
    Object? area,
    Object? price,
    Object? currency,
    Object? baths,
    Object? halls,
    Object? apartmentFloor,
    Object? furnished,
    Object? description,
    Object? documentType,
    Object? documentNumber,
    Object? documentDate,
    Object? documentAttachmentPaths,
    Property? existing,
    required bool isLinkedForEdit,
    required int existingUnitsCount,
  }) {
    final normalizedName = _optionalString(name);
    final normalizedType = normalizePropertyType(type);
    final normalizedAddress = _optionalString(address);
    final normalizedRentalMode = normalizeRentalMode(rentalMode);
    final parsedTotalUnits = _intValue(totalUnits);
    final parsedFloors = _intValue(floors);
    final parsedRooms = _intValue(rooms);
    final parsedArea = _doubleValue(area);
    final parsedPrice = _doubleValue(price);
    final parsedBaths = _intValue(baths);
    final parsedHalls = _intValue(halls);
    final parsedApartmentFloor = _intValue(apartmentFloor);
    final parsedFurnished = _boolValue(furnished);
    final parsedDocumentType = _optionalString(documentType);
    final parsedDocumentNumber = _optionalString(documentNumber);
    final parsedDocumentDate = _dateOnly(documentDate);
    final parsedDocumentAttachments = _stringList(documentAttachmentPaths);
    final parsedCurrency = _optionalString(currency) ?? 'SAR';
    final freeDescription = _optionalString(description) ?? '';

    final missing = <AiChatValidationIssue>[];

    if (normalizedName == null) {
      missing.add(_missing('name', 'اسم العقار', 'اسم العقار مطلوب'));
    }
    if (normalizedType == null) {
      missing.add(_missing('type', 'نوع العقار', 'نوع العقار مطلوب'));
    }
    if (normalizedAddress == null) {
      missing.add(_missing('address', 'العنوان', 'العنوان مطلوب'));
    }
    if (parsedDocumentType == null) {
      missing.add(_missing('documentType', 'نوع الوثيقة', 'نوع الوثيقة مطلوب'));
    }
    if (parsedDocumentNumber == null) {
      missing.add(_missing('documentNumber', 'رقم الوثيقة', 'رقم الوثيقة مطلوب'));
    }
    if (parsedDocumentDate == null) {
      missing.add(_missing('documentDate', 'تاريخ الوثيقة', 'تاريخ الوثيقة مطلوب'));
    }
    if (parsedDocumentAttachments.isEmpty) {
      missing.add(
        _missing(
          'documentAttachmentPaths',
          'مرفقات الوثيقة',
          'مرفقات الوثيقة مطلوبة',
          requiresScreenCompletion: true,
          suggestedScreen: 'properties',
        ),
      );
    }

    if (normalizedType == PropertyType.building && normalizedRentalMode == null) {
      missing.add(_missing('rentalMode', 'نمط التأجير', 'نمط التأجير مطلوب'));
    }

    if ((normalizedType == PropertyType.apartment ||
            normalizedType == PropertyType.villa) &&
        parsedFurnished == null) {
      missing.add(_missing('furnished', 'المفروشات', 'حالة المفروشات مطلوبة'));
    }

    if (normalizedType == PropertyType.building &&
        normalizedRentalMode == RentalMode.perUnit &&
        parsedTotalUnits == null) {
      missing.add(
        _missing('totalUnits', 'عدد الوحدات', 'عدد الوحدات مطلوب للعمارة بنمط الوحدات'),
      );
    }

    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatPropertyDraft>.missing(missing);
    }

    if (normalizedName!.length > 25) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'اسم العقار لا يزيد عن 25 حرفًا.',
      );
    }
    if (normalizedAddress!.length > 50) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'العنوان لا يزيد عن 50 حرفًا.',
      );
    }

    if (parsedFloors != null && (parsedFloors < 1 || parsedFloors > 100)) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'عدد الأدوار يجب أن يكون بين 1 و100.',
      );
    }
    if (parsedRooms != null && (parsedRooms < 0 || parsedRooms > 20)) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'عدد الغرف يجب أن يكون بين 0 و20.',
      );
    }
    if (parsedArea != null && (parsedArea < 1 || parsedArea > 100000)) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'المساحة يجب أن تكون بين 1 و100000.',
      );
    }
    if (normalizedType == PropertyType.land && parsedArea == null) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'مساحة الأرض مطلوبة.',
      );
    }
    if (parsedPrice != null && (parsedPrice < 1 || parsedPrice > 999999999)) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'السعر يجب أن يكون بين 1 و999999999.',
      );
    }
    if (normalizedType == PropertyType.building &&
        normalizedRentalMode == RentalMode.perUnit) {
      if (parsedTotalUnits == null || parsedTotalUnits < 1 || parsedTotalUnits > 500) {
        return const AiChatValidationResult<AiChatPropertyDraft>.error(
          'عدد وحدات العمارة يجب أن يكون بين 1 و500.',
        );
      }
    }
    if (existing != null &&
        normalizedType != existing.type &&
        isLinkedForEdit) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'لا يمكن تغيير نوع العقار لأنه مرتبط بوحدات أو عقود.',
      );
    }
    if (existing != null &&
        existing.type == PropertyType.building &&
        existing.rentalMode == RentalMode.perUnit &&
        normalizedRentalMode == RentalMode.wholeBuilding &&
        existingUnitsCount > 0) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'لا يمكن تحويل العمارة إلى تأجير كامل أثناء وجود وحدات مضافة.',
      );
    }
    if (existing != null &&
        normalizedType == PropertyType.building &&
        normalizedRentalMode == RentalMode.perUnit &&
        parsedTotalUnits != null &&
        parsedTotalUnits < existingUnitsCount) {
      return const AiChatValidationResult<AiChatPropertyDraft>.error(
        'لا يمكن تقليل عدد الوحدات إلى أقل من الوحدات المنشأة حاليًا.',
      );
    }

    return AiChatValidationResult<AiChatPropertyDraft>.success(
      AiChatPropertyDraft(
        name: normalizedName!,
        type: normalizedType!,
        address: normalizedAddress!,
        rentalMode: normalizedType == PropertyType.building
            ? normalizedRentalMode
            : null,
        totalUnits: normalizedType == PropertyType.building
            ? (parsedTotalUnits ?? 0)
            : 0,
        floors: parsedFloors,
        rooms: parsedRooms,
        area: parsedArea,
        price: normalizedType == PropertyType.building &&
                normalizedRentalMode == RentalMode.perUnit
            ? null
            : parsedPrice,
        currency: parsedCurrency,
        description: buildPropertyDescription(
          type: normalizedType!,
          baths: parsedBaths,
          halls: parsedHalls,
          apartmentFloor: parsedApartmentFloor,
          furnished: parsedFurnished,
          freeDescription: freeDescription,
        ),
        documentType: parsedDocumentType!,
        documentNumber: parsedDocumentNumber!,
        documentDate: parsedDocumentDate!,
        documentAttachmentPaths: parsedDocumentAttachments,
      ),
    );
  }

  static AiChatValidationResult<AiChatBuildingUnitDraft> validateBuildingUnit({
    required Object? unitName,
    Object? unitType,
    Object? rooms,
    Object? area,
    Object? price,
    Object? currency,
    Object? baths,
    Object? halls,
    Object? apartmentFloor,
    Object? furnished,
    Object? description,
    required bool isPerUnitBuilding,
    required int remainingCapacity,
    required bool hasLimitedCapacity,
  }) {
    final normalizedName = _optionalString(unitName);
    final normalizedType = normalizeUnitType(unitType);
    final parsedRooms = _intValue(rooms);
    final parsedArea = _doubleValue(area);
    final parsedPrice = _doubleValue(price);
    final parsedBaths = _intValue(baths);
    final parsedHalls = _intValue(halls);
    final parsedApartmentFloor = _intValue(apartmentFloor);
    final parsedFurnished = _boolValue(furnished);
    final normalizedDescription = _optionalString(description) ?? '';
    final normalizedCurrency = _optionalString(currency) ?? 'SAR';

    final missing = <AiChatValidationIssue>[];
    if (normalizedName == null) {
      missing.add(_missing('unitName', 'اسم الوحدة', 'اسم الوحدة مطلوب'));
    }
    if (!isPerUnitBuilding) {
      return const AiChatValidationResult<AiChatBuildingUnitDraft>.error(
        'إضافة الوحدات متاحة فقط للعمارة بنمط تأجير الوحدات.',
      );
    }
    if (parsedFurnished == null) {
      missing.add(_missing('furnished', 'المفروشات', 'حالة المفروشات مطلوبة'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatBuildingUnitDraft>.missing(missing);
    }

    if (parsedRooms != null && (parsedRooms < 0 || parsedRooms > 20)) {
      return const AiChatValidationResult<AiChatBuildingUnitDraft>.error(
        'عدد الغرف يجب أن يكون بين 0 و20.',
      );
    }
    if (parsedArea != null && (parsedArea < 1 || parsedArea > 100000)) {
      return const AiChatValidationResult<AiChatBuildingUnitDraft>.error(
        'المساحة يجب أن تكون بين 1 و100000.',
      );
    }
    if (parsedPrice != null && (parsedPrice < 1 || parsedPrice > 999999999)) {
      return const AiChatValidationResult<AiChatBuildingUnitDraft>.error(
        'السعر يجب أن يكون بين 1 و999999999.',
      );
    }
    if (hasLimitedCapacity && remainingCapacity <= 0) {
      return const AiChatValidationResult<AiChatBuildingUnitDraft>.error(
        'لا يمكن إضافة وحدة جديدة لأن عدد الوحدات وصل إلى الحد المحدد.',
      );
    }

    return AiChatValidationResult<AiChatBuildingUnitDraft>.success(
      AiChatBuildingUnitDraft(
        unitName: normalizedName!,
        unitType: normalizedType,
        rooms: parsedRooms,
        area: parsedArea,
        price: parsedPrice,
        currency: normalizedCurrency,
        description: buildPropertyDescription(
          type: normalizedType,
          baths: parsedBaths,
          halls: parsedHalls,
          apartmentFloor: parsedApartmentFloor,
          furnished: parsedFurnished,
          freeDescription: normalizedDescription,
        ),
      ),
    );
  }

  static AiChatValidationResult<AiChatContractDraft> validateContractCreate({
    required Object? startDate,
    required Object? endDate,
    required Object? rentAmount,
    required Object? totalAmount,
    Object? term,
    Object? termYears,
    Object? paymentCycle,
    Object? paymentCycleYears,
    Object? advanceMode,
    Object? advancePaid,
    Object? dailyCheckoutHour,
    Object? notes,
    Object? ejarContractNo,
    Object? attachmentPaths,
  }) {
    final parsedStartDate = _dateOnly(startDate);
    final parsedEndDate = _dateOnly(endDate);
    final parsedTerm = normalizeContractTerm(term);
    final parsedTermYears = _intValue(termYears) ?? 1;
    final parsedCycle = normalizePaymentCycle(paymentCycle);
    final parsedCycleYears = _intValue(paymentCycleYears) ?? 1;
    final parsedAdvanceMode = normalizeAdvanceMode(advanceMode);
    final parsedAdvancePaid = _doubleValue(advancePaid);
    final parsedCheckoutHour = _intValue(dailyCheckoutHour);
    final parsedNotes = _optionalString(notes) ?? '';
    final parsedEjarNo = _optionalString(ejarContractNo) ?? '';
    final parsedAttachments = _stringList(attachmentPaths);

    double? parsedRentAmount = _doubleValue(rentAmount);
    double? parsedTotalAmount = _doubleValue(totalAmount);

    final missing = <AiChatValidationIssue>[];
    if (parsedStartDate == null) {
      missing.add(_missing('startDate', 'تاريخ البداية', 'تاريخ البداية مطلوب'));
    }
    if (parsedEndDate == null) {
      missing.add(_missing('endDate', 'تاريخ النهاية', 'تاريخ النهاية مطلوب'));
    }
    if (parsedRentAmount == null) {
      missing.add(_missing('rentAmount', 'قيمة الإيجار', 'قيمة الإيجار مطلوبة'));
    }
    if (parsedTotalAmount == null) {
      missing.add(_missing('totalAmount', 'إجمالي العقد', 'إجمالي العقد مطلوب'));
    }

    if (parsedTerm == ContractTerm.daily) {
      if (parsedCheckoutHour == null) {
        missing.add(
          _missing(
            'dailyCheckoutHour',
            'ساعة الخروج',
            'ساعة الخروج مطلوبة في العقد اليومي',
          ),
        );
      }
      if (parsedRentAmount == null && parsedTotalAmount != null) {
        parsedRentAmount = parsedTotalAmount;
      }
      if (parsedTotalAmount == null && parsedRentAmount != null) {
        parsedTotalAmount = parsedRentAmount;
      }
    }

    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatContractDraft>.missing(missing);
    }

    if (!parsedEndDate!.isAfter(parsedStartDate!)) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'تاريخ النهاية يجب أن يكون بعد تاريخ البداية.',
      );
    }
    if (parsedRentAmount! <= 0 || parsedTotalAmount! <= 0) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'المبالغ يجب أن تكون أكبر من صفر.',
      );
    }
    if (parsedTermYears < 1 || parsedTermYears > 10) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'عدد سنوات المدة يجب أن يكون بين 1 و10.',
      );
    }
    if (parsedCycleYears < 1 || parsedCycleYears > 10) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'عدد سنوات دورة السداد يجب أن يكون بين 1 و10.',
      );
    }
    if (parsedTerm == ContractTerm.daily) {
      if (parsedCheckoutHour! < 0 || parsedCheckoutHour > 23) {
        return const AiChatValidationResult<AiChatContractDraft>.error(
          'ساعة الخروج يجب أن تكون بين 0 و23.',
        );
      }
      if ((parsedRentAmount! - parsedTotalAmount!).abs() > 0.0001) {
        return const AiChatValidationResult<AiChatContractDraft>.error(
          'في العقد اليومي يجب أن تتطابق قيمة الإيجار مع إجمالي العقد.',
        );
      }
    } else {
      final allowedCycles = _allowedCyclesForTerm(parsedTerm);
      if (!allowedCycles.contains(parsedCycle)) {
        return AiChatValidationResult<AiChatContractDraft>.error(
          'دورة السداد غير متوافقة مع مدة العقد ${contractTermLabel(parsedTerm)}.',
        );
      }
      if (parsedCycle == PaymentCycle.annual && parsedCycleYears > parsedTermYears) {
        return const AiChatValidationResult<AiChatContractDraft>.error(
          'سنوات دورة السداد لا يمكن أن تتجاوز سنوات مدة العقد.',
        );
      }
    }
    if (parsedAdvanceMode == AdvanceMode.none && (parsedAdvancePaid ?? 0) > 0) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'حدد نوع الدفعة المقدمة قبل إدخال مبلغها.',
      );
    }
    if (parsedAdvanceMode != AdvanceMode.none &&
        ((parsedAdvancePaid ?? 0) <= 0)) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'مبلغ الدفعة المقدمة يجب أن يكون أكبر من صفر.',
      );
    }
    if (parsedAdvanceMode == AdvanceMode.deductFromTotal &&
        (parsedAdvancePaid ?? 0) > parsedTotalAmount!) {
      return const AiChatValidationResult<AiChatContractDraft>.error(
        'الدفعة المقدمة لا يمكن أن تتجاوز إجمالي العقد عند الخصم من الإجمالي.',
      );
    }

    return AiChatValidationResult<AiChatContractDraft>.success(
      AiChatContractDraft(
        startDate: parsedStartDate!,
        endDate: parsedEndDate!,
        rentAmount: parsedRentAmount!,
        totalAmount: parsedTotalAmount!,
        term: parsedTerm,
        termYears: parsedTerm == ContractTerm.annual ? parsedTermYears : 1,
        paymentCycle: parsedTerm == ContractTerm.daily
            ? PaymentCycle.monthly
            : parsedCycle,
        paymentCycleYears:
            parsedCycle == PaymentCycle.annual ? parsedCycleYears : 1,
        advanceMode: parsedAdvanceMode,
        advancePaid: parsedAdvanceMode == AdvanceMode.none
            ? null
            : parsedAdvancePaid,
        dailyCheckoutHour:
            parsedTerm == ContractTerm.daily ? parsedCheckoutHour : null,
        notes: parsedNotes,
        ejarContractNo: parsedEjarNo,
        attachmentPaths: parsedAttachments,
      ),
    );
  }

  static AiChatValidationResult<AiChatContractEditDraft> validateContractEdit({
    required Contract contract,
    Object? rentAmount,
    Object? totalAmount,
    Object? notes,
    Object? ejarContractNo,
    Object? endDate,
    Object? paymentCycle,
    Object? paymentCycleYears,
    Object? advanceMode,
    Object? advancePaid,
    Object? dailyCheckoutHour,
  }) {
    final parsedRent = _doubleValue(rentAmount);
    final parsedTotal = _doubleValue(totalAmount);
    final parsedNotes = _optionalString(notes);
    final parsedEjarNo = _optionalString(ejarContractNo);
    final parsedEndDate = _dateOnly(endDate);
    final parsedCycle = paymentCycle == null
        ? null
        : normalizePaymentCycle(paymentCycle);
    final parsedCycleYears = _intValue(paymentCycleYears);
    final parsedAdvanceMode = advanceMode == null
        ? null
        : normalizeAdvanceMode(advanceMode);
    final parsedAdvancePaid = _doubleValue(advancePaid);
    final parsedCheckoutHour = _intValue(dailyCheckoutHour);

    if (contract.isTerminated) {
      return const AiChatValidationResult<AiChatContractEditDraft>.error(
        'لا يمكن تعديل عقد منتهي.',
      );
    }
    if (parsedRent != null && parsedRent <= 0) {
      return const AiChatValidationResult<AiChatContractEditDraft>.error(
        'قيمة الإيجار يجب أن تكون أكبر من صفر.',
      );
    }
    if (parsedTotal != null && parsedTotal <= 0) {
      return const AiChatValidationResult<AiChatContractEditDraft>.error(
        'إجمالي العقد يجب أن يكون أكبر من صفر.',
      );
    }
    if (parsedEndDate != null && !parsedEndDate.isAfter(contract.startDate)) {
      return const AiChatValidationResult<AiChatContractEditDraft>.error(
        'تاريخ النهاية يجب أن يكون بعد تاريخ بداية العقد.',
      );
    }
    if (contract.term == ContractTerm.daily) {
      if (parsedCheckoutHour != null &&
          (parsedCheckoutHour < 0 || parsedCheckoutHour > 23)) {
        return const AiChatValidationResult<AiChatContractEditDraft>.error(
          'ساعة الخروج يجب أن تكون بين 0 و23.',
        );
      }
    } else if (parsedCycle != null) {
      final allowedCycles = _allowedCyclesForTerm(contract.term);
      if (!allowedCycles.contains(parsedCycle)) {
        return AiChatValidationResult<AiChatContractEditDraft>.error(
          'دورة السداد غير متوافقة مع مدة العقد ${contractTermLabel(contract.term)}.',
        );
      }
      if (parsedCycle == PaymentCycle.annual &&
          parsedCycleYears != null &&
          contract.term == ContractTerm.annual &&
          parsedCycleYears > contract.termYears) {
        return const AiChatValidationResult<AiChatContractEditDraft>.error(
          'سنوات دورة السداد لا يمكن أن تتجاوز سنوات مدة العقد.',
        );
      }
    }
    if (parsedAdvanceMode != null && parsedAdvanceMode != AdvanceMode.none) {
      if ((parsedAdvancePaid ?? contract.advancePaid ?? 0) <= 0) {
        return const AiChatValidationResult<AiChatContractEditDraft>.error(
          'مبلغ الدفعة المقدمة يجب أن يكون أكبر من صفر.',
        );
      }
    }
    if (parsedAdvanceMode == AdvanceMode.none && parsedAdvancePaid != null) {
      return const AiChatValidationResult<AiChatContractEditDraft>.error(
        'لا يمكن إدخال مبلغ دفعة مقدمة مع اختيار بدون دفعة مقدمة.',
      );
    }

    return AiChatValidationResult<AiChatContractEditDraft>.success(
      AiChatContractEditDraft(
        rentAmount: parsedRent,
        totalAmount: parsedTotal,
        notes: parsedNotes,
        ejarContractNo: parsedEjarNo,
        endDate: parsedEndDate,
        paymentCycle: parsedCycle,
        paymentCycleYears: parsedCycle == PaymentCycle.annual
            ? (parsedCycleYears ?? contract.paymentCycleYears)
            : null,
        advanceMode: parsedAdvanceMode,
        advancePaid: parsedAdvancePaid,
        dailyCheckoutHour:
            contract.term == ContractTerm.daily ? parsedCheckoutHour : null,
      ),
    );
  }

  static AiChatValidationResult<AiChatContractRenewDraft> validateContractRenew({
    required Object? newStartDate,
    required Object? newEndDate,
    Object? newRentAmount,
    Object? newTotalAmount,
    Object? notes,
  }) {
    final parsedStart = _dateOnly(newStartDate);
    final parsedEnd = _dateOnly(newEndDate);
    final parsedRent = _doubleValue(newRentAmount);
    final parsedTotal = _doubleValue(newTotalAmount);
    final parsedNotes = _optionalString(notes);

    final missing = <AiChatValidationIssue>[];
    if (parsedStart == null) {
      missing.add(_missing('newStartDate', 'تاريخ البداية الجديد', 'تاريخ البداية الجديد مطلوب'));
    }
    if (parsedEnd == null) {
      missing.add(_missing('newEndDate', 'تاريخ النهاية الجديد', 'تاريخ النهاية الجديد مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatContractRenewDraft>.missing(missing);
    }

    if (!parsedEnd!.isAfter(parsedStart!)) {
      return const AiChatValidationResult<AiChatContractRenewDraft>.error(
        'تاريخ النهاية الجديد يجب أن يكون بعد تاريخ البداية الجديد.',
      );
    }
    if (parsedRent != null && parsedRent <= 0) {
      return const AiChatValidationResult<AiChatContractRenewDraft>.error(
        'قيمة الإيجار الجديدة يجب أن تكون أكبر من صفر.',
      );
    }
    if (parsedTotal != null && parsedTotal <= 0) {
      return const AiChatValidationResult<AiChatContractRenewDraft>.error(
        'إجمالي العقد الجديد يجب أن يكون أكبر من صفر.',
      );
    }

    return AiChatValidationResult<AiChatContractRenewDraft>.success(
      AiChatContractRenewDraft(
        newStartDate: parsedStart!,
        newEndDate: parsedEnd!,
        newRentAmount: parsedRent,
        newTotalAmount: parsedTotal,
        notes: parsedNotes,
      ),
    );
  }

  static AiChatValidationResult<AiChatInvoiceDraft> validateInvoiceCreate({
    required Object? amount,
    required Object? dueDate,
    Object? note,
  }) {
    final parsedAmount = _doubleValue(amount);
    final parsedDate = _dateOnly(dueDate);
    final parsedNote = _optionalString(note) ?? '';

    final missing = <AiChatValidationIssue>[];
    if (parsedAmount == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedDate == null) {
      missing.add(_missing('dueDate', 'تاريخ الاستحقاق', 'تاريخ الاستحقاق مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatInvoiceDraft>.missing(missing);
    }
    if (parsedAmount! <= 0) {
      return const AiChatValidationResult<AiChatInvoiceDraft>.error(
        'المبلغ يجب أن يكون أكبر من صفر.',
      );
    }
    return AiChatValidationResult<AiChatInvoiceDraft>.success(
      AiChatInvoiceDraft(
        amount: parsedAmount!,
        dueDate: parsedDate!,
        note: parsedNote,
      ),
    );
  }

  static AiChatValidationResult<AiChatManualVoucherDraft> validateManualVoucher({
    required Object? kind,
    required Object? amount,
    required Object? issueDate,
    required Object? partyName,
    required Object? paymentMethod,
    required Object? title,
    required Object? description,
    Object? tenantName,
    Object? propertyName,
    Object? attachmentPaths,
  }) {
    final parsedKind = normalizeVoucherKind(kind);
    final parsedAmount = _doubleValue(amount);
    final parsedIssueDate = _dateOnly(issueDate);
    final parsedPartyName = _optionalString(partyName);
    final parsedPaymentMethod = normalizePaymentMethod(paymentMethod);
    final parsedTitle = _optionalString(title);
    final parsedDescription = _optionalString(description);
    final parsedTenantName = _optionalString(tenantName);
    final parsedPropertyName = _optionalString(propertyName);
    final parsedAttachments = _stringList(attachmentPaths);

    final missing = <AiChatValidationIssue>[];
    if (parsedKind == null) {
      missing.add(_missing('kind', 'نوع السند', 'نوع السند مطلوب'));
    }
    if (parsedAmount == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedIssueDate == null) {
      missing.add(_missing('issueDate', 'تاريخ السند', 'تاريخ السند مطلوب'));
    }
    if (parsedPartyName == null) {
      missing.add(_missing('partyName', 'اسم الطرف', 'اسم الطرف مطلوب'));
    }
    if (parsedPaymentMethod == null) {
      missing.add(_missing('paymentMethod', 'طريقة الدفع', 'طريقة الدفع مطلوبة'));
    }
    if (parsedTitle == null) {
      missing.add(_missing('title', 'عنوان السند', 'عنوان السند مطلوب'));
    }
    if (parsedDescription == null) {
      missing.add(_missing('description', 'البيان', 'البيان مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatManualVoucherDraft>.missing(missing);
    }

    if (parsedPartyName!.length > 40) {
      return const AiChatValidationResult<AiChatManualVoucherDraft>.error(
        'اسم الطرف لا يزيد عن 40 حرفًا.',
      );
    }
    if (parsedTitle!.length > 15) {
      return const AiChatValidationResult<AiChatManualVoucherDraft>.error(
        'عنوان السند لا يزيد عن 15 حرفًا.',
      );
    }
    if (parsedDescription!.length > 300) {
      return const AiChatValidationResult<AiChatManualVoucherDraft>.error(
        'البيان لا يزيد عن 300 حرف.',
      );
    }
    if (parsedAmount! <= 0 || parsedAmount > 500000000) {
      return const AiChatValidationResult<AiChatManualVoucherDraft>.error(
        'المبلغ يجب أن يكون أكبر من صفر ولا يزيد عن 500000000.',
      );
    }

    return AiChatValidationResult<AiChatManualVoucherDraft>.success(
      AiChatManualVoucherDraft(
        kind: parsedKind!,
        amount: parsedAmount!,
        signedAmount:
            parsedKind == 'expense' ? -parsedAmount! : parsedAmount!,
        issueDate: parsedIssueDate!,
        title: parsedTitle!,
        partyName: parsedPartyName!,
        description: parsedDescription!,
        paymentMethod: parsedPaymentMethod!,
        attachmentPaths: parsedAttachments,
        tenantName: parsedTenantName,
        propertyName: parsedPropertyName,
      ),
    );
  }

  static AiChatValidationResult<AiChatMaintenanceDraft> validateMaintenanceRequest({
    required Object? title,
    Object? description,
    Object? requestType,
    Object? priority,
    Object? scheduledDate,
    Object? executionDeadline,
    Object? cost,
    Object? provider,
    Object? attachmentPaths,
  }) {
    final parsedTitle = _optionalString(title);
    final parsedDescription = _optionalString(description) ?? '';
    final parsedRequestType =
        _optionalString(requestType) ?? _optionalString(title) ?? 'خدمات';
    final parsedPriority = normalizePriority(priority);
    final parsedScheduledDate = _dateOnly(scheduledDate);
    final parsedExecutionDeadline = _dateOnly(executionDeadline);
    final parsedCost = _doubleValue(cost);
    final parsedProvider = _optionalString(provider);
    final parsedAttachments = _stringList(attachmentPaths);

    final missing = <AiChatValidationIssue>[];
    if (parsedTitle == null) {
      missing.add(_missing('title', 'نوع الخدمة', 'نوع الخدمة مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatMaintenanceDraft>.missing(missing);
    }

    if (parsedTitle!.length > 35) {
      return const AiChatValidationResult<AiChatMaintenanceDraft>.error(
        'عنوان طلب الصيانة لا يزيد عن 35 حرفًا.',
      );
    }
    if (parsedDescription.length > 2000) {
      return const AiChatValidationResult<AiChatMaintenanceDraft>.error(
        'وصف طلب الصيانة لا يزيد عن 2000 حرف.',
      );
    }
    if (parsedExecutionDeadline != null &&
        parsedScheduledDate != null &&
        parsedExecutionDeadline.isBefore(parsedScheduledDate)) {
      return const AiChatValidationResult<AiChatMaintenanceDraft>.error(
        'آخر موعد للتنفيذ يجب أن يكون في نفس يوم الجدولة أو بعده.',
      );
    }

    return AiChatValidationResult<AiChatMaintenanceDraft>.success(
      AiChatMaintenanceDraft(
        title: parsedTitle!,
        description: parsedDescription,
        requestType: parsedRequestType,
        priority: parsedPriority,
        scheduledDate: parsedScheduledDate,
        executionDeadline: parsedExecutionDeadline,
        cost: parsedCost == null || parsedCost < 0 ? 0 : parsedCost,
        providerName: parsedProvider,
        attachmentPaths: parsedAttachments,
      ),
    );
  }

  static AiChatValidationResult<AiChatMaintenanceStatusDraft> validateMaintenanceStatus({
    required Object? status,
    Object? cost,
    Object? provider,
    Object? scheduledDate,
    Object? executionDeadline,
  }) {
    final parsedStatus = normalizeStatus(status);
    final parsedCost = _doubleValue(cost);
    final parsedProvider = _optionalString(provider);
    final parsedScheduledDate = _dateOnly(scheduledDate);
    final parsedExecutionDeadline = _dateOnly(executionDeadline);

    if (parsedExecutionDeadline != null &&
        parsedScheduledDate != null &&
        parsedExecutionDeadline.isBefore(parsedScheduledDate)) {
      return const AiChatValidationResult<AiChatMaintenanceStatusDraft>.error(
        'آخر موعد للتنفيذ يجب أن يكون في نفس يوم الجدولة أو بعده.',
      );
    }

    return AiChatValidationResult<AiChatMaintenanceStatusDraft>.success(
      AiChatMaintenanceStatusDraft(
        status: parsedStatus,
        cost: parsedCost == null || parsedCost < 0 ? 0 : parsedCost,
        providerName: parsedProvider,
        scheduledDate: parsedScheduledDate,
        executionDeadline: parsedExecutionDeadline,
      ),
    );
  }

  static AiChatValidationResult<AiChatPeriodicServiceDraft> validatePeriodicService({
    required Object? serviceType,
    Object? provider,
    Object? cost,
    Object? scheduledDate,
    Object? nextDueDate,
  }) {
    final parsedType = normalizePeriodicServiceType(serviceType);
    final parsedProvider = _optionalString(provider);
    final parsedCost = _doubleValue(cost);
    final parsedDate = _dateOnly(nextDueDate) ?? _dateOnly(scheduledDate);

    final missing = <AiChatValidationIssue>[];
    if (parsedType == null) {
      missing.add(
        _missing('serviceType', 'نوع الخدمة الدورية', 'نوع الخدمة الدورية مطلوب'),
      );
    }
    if (parsedDate == null) {
      missing.add(
        _missing('scheduledDate', 'تاريخ الدورة القادمة', 'تاريخ الدورة القادمة مطلوب'),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatPeriodicServiceDraft>.missing(missing);
    }
    if (parsedCost != null && parsedCost < 0) {
      return const AiChatValidationResult<AiChatPeriodicServiceDraft>.error(
        'تكلفة الخدمة لا يمكن أن تكون سالبة.',
      );
    }

    return AiChatValidationResult<AiChatPeriodicServiceDraft>.success(
      AiChatPeriodicServiceDraft(
        serviceType: parsedType!,
        providerName: parsedProvider,
        cost: parsedCost ?? 0,
        dueDate: parsedDate!,
      ),
    );
  }

  static AiChatValidationResult<AiChatOfficeClientDraft> validateOfficeClient({
    required Object? name,
    required Object? email,
    Object? phone,
    Object? notes,
  }) {
    final parsedName = _optionalString(name);
    final parsedEmail = _optionalString(email)?.toLowerCase();
    final parsedNotes = _optionalString(notes) ?? '';
    final normalizedPhone = normalizeOfficePhone(phone);

    final missing = <AiChatValidationIssue>[];
    if (parsedName == null) {
      missing.add(_missing('name', 'اسم العميل', 'اسم العميل مطلوب'));
    }
    if (parsedEmail == null) {
      missing.add(_missing('email', 'البريد الإلكتروني', 'البريد الإلكتروني مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatOfficeClientDraft>.missing(missing);
    }
    if (parsedName!.length > 50) {
      return const AiChatValidationResult<AiChatOfficeClientDraft>.error(
        'اسم العميل لا يزيد عن 50 حرفًا.',
      );
    }
    if (parsedEmail!.length > 40) {
      return const AiChatValidationResult<AiChatOfficeClientDraft>.error(
        'البريد الإلكتروني لا يزيد عن 40 حرفًا.',
      );
    }
    if (!_emailPattern.hasMatch(parsedEmail)) {
      return const AiChatValidationResult<AiChatOfficeClientDraft>.error(
        'البريد الإلكتروني غير صالح.',
      );
    }
    if (parsedNotes.length > 1000) {
      return const AiChatValidationResult<AiChatOfficeClientDraft>.error(
        'الملاحظات لا تزيد عن 1000 حرف.',
      );
    }
    if (normalizedPhone == null) {
      return const AiChatValidationResult<AiChatOfficeClientDraft>.error(
        'رقم الجوال يجب أن يكون 10 أرقام بالضبط أو يترك فارغًا.',
      );
    }

    return AiChatValidationResult<AiChatOfficeClientDraft>.success(
      AiChatOfficeClientDraft(
        name: parsedName!,
        email: parsedEmail!,
        phone: normalizedPhone!,
        notes: parsedNotes,
      ),
    );
  }

  static AiChatValidationResult<AiChatOfficeClientAccessDraft>
      validateOfficeClientAccess({
    Object? allowAccess,
    Object? blocked,
  }) {
    final parsedAllow = _boolAccessValue(allowAccess);
    final parsedBlocked = _boolAccessValue(blocked);

    if (parsedAllow == null && parsedBlocked == null) {
      return AiChatValidationResult<AiChatOfficeClientAccessDraft>.missing(
        <AiChatValidationIssue>[
          _missing(
            'allowAccess',
            'السماح بالدخول',
            'يجب تحديد هل تريد السماح بالدخول أم إيقافه.',
          ),
        ],
      );
    }

    if (parsedAllow != null &&
        parsedBlocked != null &&
        parsedAllow == parsedBlocked) {
      return const AiChatValidationResult<AiChatOfficeClientAccessDraft>.error(
        'القيمتان allowAccess و blocked متعارضتان. أرسل واحدة واضحة فقط أو اجعلهما متعاكستين.',
      );
    }

    final resolvedAllow = parsedAllow ?? !parsedBlocked!;
    return AiChatValidationResult<AiChatOfficeClientAccessDraft>.success(
      AiChatOfficeClientAccessDraft(
        allowAccess: resolvedAllow,
        blocked: !resolvedAllow,
      ),
    );
  }

  static AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>
      validateOfficeClientSubscription({
    Object? price,
    Object? reminderDays,
    Object? startDate,
  }) {
    final parsedPrice = _doubleValue(price);
    final parsedReminder = _intValue(reminderDays);
    final parsedStartDate = _dateOnly(startDate);
    final hasPrice = _optionalString(price) != null;
    final hasReminder = _optionalString(reminderDays) != null;
    final hasStartDate = _optionalString(startDate) != null;

    if (!hasPrice) {
      return AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.missing(
        <AiChatValidationIssue>[
          _missing(
            'price',
            'سعر الاشتراك',
            'سعر الاشتراك مطلوب.',
          ),
        ],
      );
    }

    if (parsedPrice == null || parsedPrice <= 0) {
      return const AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.error(
        'سعر الاشتراك يجب أن يكون أكبر من صفر.',
      );
    }

    if (hasReminder && parsedReminder == null) {
      return const AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.error(
        'موعد تنبيه الاشتراك يجب أن يكون رقمًا صحيحًا من 1 إلى 3 أيام.',
      );
    }
    if (parsedReminder != null && (parsedReminder < 1 || parsedReminder > 3)) {
      return const AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.error(
        'موعد تنبيه الاشتراك يجب أن يكون من 1 إلى 3 أيام فقط.',
      );
    }

    if (hasStartDate && parsedStartDate == null) {
      return const AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.error(
        'تاريخ بداية الاشتراك يجب أن يكون بصيغة YYYY-MM-DD.',
      );
    }

    return AiChatValidationResult<AiChatOfficeClientSubscriptionDraft>.success(
      AiChatOfficeClientSubscriptionDraft(
        startDate: parsedStartDate,
        price: parsedPrice,
        reminderDays: parsedReminder,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsAssignPropertyOwnerDraft>
      validateReportsAssignPropertyOwner({
    Object? propertyQuery,
    Object? ownerQuery,
  }) {
    final parsedProperty = _optionalString(propertyQuery);
    final parsedOwner = _optionalString(ownerQuery);
    final missing = <AiChatValidationIssue>[];

    if (parsedProperty == null) {
      missing.add(_missing('propertyQuery', 'العقار', 'تحديد العقار مطلوب'));
    }
    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsAssignPropertyOwnerDraft>.missing(
        missing,
      );
    }

    return AiChatValidationResult<AiChatReportsAssignPropertyOwnerDraft>.success(
      AiChatReportsAssignPropertyOwnerDraft(
        propertyQuery: parsedProperty!,
        ownerQuery: parsedOwner!,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOfficeVoucherDraft>
      validateReportsOfficeVoucher({
    Object? isExpense,
    Object? amount,
    Object? transactionDate,
    Object? note,
  }) {
    final parsedType = _boolValue(isExpense);
    final parsedAmount = _doubleValue(amount);
    final parsedDate = _dateOnly(transactionDate);
    final parsedNote = _optionalString(note) ?? '';
    final missing = <AiChatValidationIssue>[];

    if (parsedType == null) {
      missing.add(
        _missing(
          'isExpense',
          'نوع العملية',
          'حدد هل العملية مصروف مكتب أم إيراد عمولة.',
        ),
      );
    }
    if (_optionalString(amount) == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedDate == null) {
      missing.add(
        _missing('transactionDate', 'تاريخ العملية', 'تاريخ العملية مطلوب'),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOfficeVoucherDraft>.missing(
        missing,
      );
    }

    final amountError = _validateReportsAmount(parsedAmount);
    if (amountError != null) {
      return AiChatValidationResult<AiChatReportsOfficeVoucherDraft>.error(
        amountError,
      );
    }
    final noteError = _validateReportsNote(parsedNote);
    if (noteError != null) {
      return AiChatValidationResult<AiChatReportsOfficeVoucherDraft>.error(
        noteError,
      );
    }
    final dateError = _validateActionDate(parsedDate!);
    if (dateError != null) {
      return AiChatValidationResult<AiChatReportsOfficeVoucherDraft>.error(
        dateError,
      );
    }

    return AiChatValidationResult<AiChatReportsOfficeVoucherDraft>.success(
      AiChatReportsOfficeVoucherDraft(
        isExpense: parsedType!,
        amount: parsedAmount!.abs(),
        transactionDate: parsedDate,
        note: parsedNote,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>
      validateReportsOfficeWithdrawal({
    Object? amount,
    Object? transferDate,
    Object? note,
    Object? fromDate,
    Object? toDate,
  }) {
    final parsedAmount = _doubleValue(amount);
    final parsedTransferDate = _dateOnly(transferDate);
    final parsedNote = _optionalString(note) ?? '';
    final period = _validateReportsPeriod(fromDate: fromDate, toDate: toDate);
    if (!period.isValid) {
      return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.error(
        period.firstIssueMessage,
      );
    }

    final missing = <AiChatValidationIssue>[];
    if (_optionalString(amount) == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedTransferDate == null) {
      missing.add(
        _missing('transferDate', 'تاريخ التحويل', 'تاريخ التحويل مطلوب'),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.missing(
        missing,
      );
    }

    final amountError = _validateReportsAmount(parsedAmount);
    if (amountError != null) {
      return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.error(
        amountError,
      );
    }
    final noteError = _validateReportsNote(parsedNote);
    if (noteError != null) {
      return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.error(
        noteError,
      );
    }
    final dateError = _validateActionDate(parsedTransferDate!);
    if (dateError != null) {
      return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.error(
        dateError,
      );
    }

    return AiChatValidationResult<AiChatReportsOfficeWithdrawalDraft>.success(
      AiChatReportsOfficeWithdrawalDraft(
        amount: parsedAmount!.abs(),
        transferDate: parsedTransferDate,
        note: parsedNote,
        fromDate: period.draft?.fromDate,
        toDate: period.draft?.toDate,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsCommissionRuleDraft>
      validateReportsCommissionRule({
    Object? mode,
    Object? value,
  }) {
    final parsedMode = normalizeCommissionMode(mode);
    if (parsedMode == null) {
      return AiChatValidationResult<AiChatReportsCommissionRuleDraft>.missing(
        <AiChatValidationIssue>[
          _missing('mode', 'نوع العمولة', 'نوع العمولة مطلوب'),
        ],
      );
    }

    if (parsedMode == CommissionMode.percent) {
      final parsedValue = _doubleValue(value);
      if (parsedValue == null || parsedValue < 0) {
        return const AiChatValidationResult<AiChatReportsCommissionRuleDraft>.error(
          'أدخل نسبة عمولة صحيحة.',
        );
      }
      if (parsedValue > 100) {
        return const AiChatValidationResult<AiChatReportsCommissionRuleDraft>.error(
          'نسبة العمولة لا يمكن أن تتجاوز 100%.',
        );
      }
      return AiChatValidationResult<AiChatReportsCommissionRuleDraft>.success(
        AiChatReportsCommissionRuleDraft(
          mode: parsedMode,
          value: parsedValue,
        ),
      );
    }

    return AiChatValidationResult<AiChatReportsCommissionRuleDraft>.success(
      AiChatReportsCommissionRuleDraft(mode: parsedMode, value: 0),
    );
  }

  static AiChatValidationResult<AiChatReportsOwnerPayoutDraft>
      validateReportsOwnerPayout({
    Object? ownerQuery,
    Object? propertyQuery,
    Object? amount,
    Object? transferDate,
    Object? note,
    Object? fromDate,
    Object? toDate,
  }) {
    final parsedOwner = _optionalString(ownerQuery);
    final parsedProperty = _optionalString(propertyQuery);
    final parsedAmount = _doubleValue(amount);
    final parsedDate = _dateOnly(transferDate);
    final parsedNote = _optionalString(note) ?? '';
    final period = _validateReportsPeriod(fromDate: fromDate, toDate: toDate);
    if (!period.isValid) {
      return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.error(
        period.firstIssueMessage,
      );
    }

    final missing = <AiChatValidationIssue>[];
    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (_optionalString(amount) == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedDate == null) {
      missing.add(
        _missing('transferDate', 'تاريخ التحويل', 'تاريخ التحويل مطلوب'),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.missing(
        missing,
      );
    }

    final amountError = _validateReportsAmount(parsedAmount);
    if (amountError != null) {
      return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.error(
        amountError,
      );
    }
    final noteError = _validateReportsNote(parsedNote);
    if (noteError != null) {
      return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.error(
        noteError,
      );
    }
    final dateError = _validateActionDate(parsedDate!);
    if (dateError != null) {
      return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.error(
        dateError,
      );
    }

    return AiChatValidationResult<AiChatReportsOwnerPayoutDraft>.success(
      AiChatReportsOwnerPayoutDraft(
        ownerQuery: parsedOwner!,
        propertyQuery: parsedProperty,
        amount: parsedAmount!.abs(),
        transferDate: parsedDate,
        note: parsedNote,
        fromDate: period.draft?.fromDate,
        toDate: period.draft?.toDate,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>
      validateReportsOwnerAdjustment({
    Object? ownerQuery,
    Object? propertyQuery,
    Object? category,
    Object? amount,
    Object? adjustmentDate,
    Object? note,
    Object? fromDate,
    Object? toDate,
  }) {
    final parsedOwner = _optionalString(ownerQuery);
    final parsedProperty = _optionalString(propertyQuery);
    final parsedCategory = normalizeOwnerAdjustmentCategory(category);
    final parsedAmount = _doubleValue(amount);
    final parsedDate = _dateOnly(adjustmentDate);
    final parsedNote = _optionalString(note) ?? '';
    final period = _validateReportsPeriod(fromDate: fromDate, toDate: toDate);
    if (!period.isValid) {
      return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.error(
        period.firstIssueMessage,
      );
    }

    final missing = <AiChatValidationIssue>[];
    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (parsedCategory == null) {
      missing.add(
        _missing(
          'category',
          'نوع الخصم/التسوية',
          'نوع الخصم/التسوية مطلوب',
        ),
      );
    }
    if (_optionalString(amount) == null) {
      missing.add(_missing('amount', 'المبلغ', 'المبلغ مطلوب'));
    }
    if (parsedDate == null) {
      missing.add(
        _missing(
          'adjustmentDate',
          'تاريخ الخصم/التسوية',
          'تاريخ الخصم/التسوية مطلوب',
        ),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.missing(
        missing,
      );
    }

    final amountError = _validateReportsAmount(parsedAmount);
    if (amountError != null) {
      return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.error(
        amountError,
      );
    }
    final noteError = _validateReportsNote(parsedNote);
    if (noteError != null) {
      return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.error(
        noteError,
      );
    }
    final dateError = _validateActionDate(parsedDate!);
    if (dateError != null) {
      return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.error(
        dateError,
      );
    }

    return AiChatValidationResult<AiChatReportsOwnerAdjustmentDraft>.success(
      AiChatReportsOwnerAdjustmentDraft(
        ownerQuery: parsedOwner!,
        propertyQuery: parsedProperty,
        category: parsedCategory!,
        amount: parsedAmount!.abs(),
        adjustmentDate: parsedDate,
        note: parsedNote,
        fromDate: period.draft?.fromDate,
        toDate: period.draft?.toDate,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOwnerBankAccountDraft>
      validateReportsOwnerBankAccount({
    Object? ownerQuery,
    Object? bankName,
    Object? accountNumber,
    Object? iban,
  }) {
    final parsedOwner = _optionalString(ownerQuery);
    final parsedBank = _optionalString(bankName);
    final parsedAccount = _optionalString(accountNumber);
    final parsedIban = _optionalString(iban) ?? '';
    final missing = <AiChatValidationIssue>[];

    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (parsedBank == null) {
      missing.add(_missing('bankName', 'اسم البنك', 'اسم البنك مطلوب'));
    }
    if (parsedAccount == null) {
      missing.add(_missing('accountNumber', 'رقم الحساب', 'رقم الحساب مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOwnerBankAccountDraft>.missing(
        missing,
      );
    }

    final bankError = _validateBankFieldLengths(
      bankName: parsedBank!,
      accountNumber: parsedAccount!,
      iban: parsedIban,
    );
    if (bankError != null) {
      return AiChatValidationResult<AiChatReportsOwnerBankAccountDraft>.error(
        bankError,
      );
    }

    return AiChatValidationResult<AiChatReportsOwnerBankAccountDraft>.success(
      AiChatReportsOwnerBankAccountDraft(
        ownerQuery: parsedOwner!,
        bankName: parsedBank,
        accountNumber: parsedAccount,
        iban: parsedIban,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOwnerBankAccountEditDraft>
      validateReportsOwnerBankAccountEdit({
    Object? ownerQuery,
    Object? accountQuery,
    Object? bankName,
    Object? accountNumber,
    Object? iban,
  }) {
    final parsedOwner = _optionalString(ownerQuery);
    final parsedAccountQuery = _optionalString(accountQuery);
    final parsedBank = _optionalString(bankName);
    final parsedAccount = _optionalString(accountNumber);
    final parsedIban = _optionalString(iban) ?? '';
    final missing = <AiChatValidationIssue>[];

    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (parsedAccountQuery == null) {
      missing.add(
        _missing(
          'accountQuery',
          'الحساب البنكي',
          'تحديد الحساب البنكي المطلوب مطلوب',
        ),
      );
    }
    if (parsedBank == null) {
      missing.add(_missing('bankName', 'اسم البنك', 'اسم البنك مطلوب'));
    }
    if (parsedAccount == null) {
      missing.add(_missing('accountNumber', 'رقم الحساب', 'رقم الحساب مطلوب'));
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOwnerBankAccountEditDraft>.missing(
        missing,
      );
    }

    final bankError = _validateBankFieldLengths(
      bankName: parsedBank!,
      accountNumber: parsedAccount!,
      iban: parsedIban,
    );
    if (bankError != null) {
      return AiChatValidationResult<AiChatReportsOwnerBankAccountEditDraft>.error(
        bankError,
      );
    }

    return AiChatValidationResult<AiChatReportsOwnerBankAccountEditDraft>.success(
      AiChatReportsOwnerBankAccountEditDraft(
        ownerQuery: parsedOwner!,
        accountQuery: parsedAccountQuery!,
        bankName: parsedBank,
        accountNumber: parsedAccount,
        iban: parsedIban,
      ),
    );
  }

  static AiChatValidationResult<AiChatReportsOwnerBankAccountDeleteDraft>
      validateReportsOwnerBankAccountDelete({
    Object? ownerQuery,
    Object? accountQuery,
  }) {
    final parsedOwner = _optionalString(ownerQuery);
    final parsedAccountQuery = _optionalString(accountQuery);
    final missing = <AiChatValidationIssue>[];

    if (parsedOwner == null) {
      missing.add(_missing('ownerQuery', 'المالك', 'تحديد المالك مطلوب'));
    }
    if (parsedAccountQuery == null) {
      missing.add(
        _missing(
          'accountQuery',
          'الحساب البنكي',
          'تحديد الحساب البنكي المطلوب مطلوب',
        ),
      );
    }
    if (missing.isNotEmpty) {
      return AiChatValidationResult<AiChatReportsOwnerBankAccountDeleteDraft>.missing(
        missing,
      );
    }

    return AiChatValidationResult<AiChatReportsOwnerBankAccountDeleteDraft>.success(
      AiChatReportsOwnerBankAccountDeleteDraft(
        ownerQuery: parsedOwner!,
        accountQuery: parsedAccountQuery!,
      ),
    );
  }

  static String buildPropertyDescription({
    required PropertyType type,
    int? baths,
    int? halls,
    int? apartmentFloor,
    bool? furnished,
    String? freeDescription,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('[[SPEC]]');
    if ((type == PropertyType.apartment || type == PropertyType.villa) &&
        baths != null) {
      buffer.writeln('حمامات: $baths');
    }
    if ((type == PropertyType.apartment || type == PropertyType.villa) &&
        halls != null) {
      buffer.writeln('صالات: $halls');
    }
    if (type == PropertyType.apartment && apartmentFloor != null) {
      buffer.writeln('الدور: $apartmentFloor');
    }
    if ((type == PropertyType.apartment || type == PropertyType.villa) &&
        furnished != null) {
      buffer.writeln('المفروشات: ${furnished ? "مفروشة" : "غير مفروشة"}');
    }
    buffer.writeln('[[/SPEC]]');
    final desc = (freeDescription ?? '').trim();
    if (desc.isNotEmpty) {
      buffer.writeln(desc);
    }
    return buffer.toString().trim();
  }

  static PropertyType? normalizePropertyType(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'apartment':
      case 'شقة':
        return PropertyType.apartment;
      case 'villa':
      case 'فيلا':
        return PropertyType.villa;
      case 'building':
      case 'عمارة':
      case 'مبنى':
        return PropertyType.building;
      case 'land':
      case 'ارض':
      case 'أرض':
        return PropertyType.land;
      case 'office':
      case 'مكتب':
        return PropertyType.office;
      case 'shop':
      case 'محل':
        return PropertyType.shop;
      case 'warehouse':
      case 'مستودع':
        return PropertyType.warehouse;
      default:
        return null;
    }
  }

  static PropertyType normalizeUnitType(Object? raw) {
    return normalizePropertyType(raw) ?? PropertyType.apartment;
  }

  static String propertyTypeKey(PropertyType type) {
    return type.name;
  }

  static String propertyTypeLabel(PropertyType type) {
    switch (type) {
      case PropertyType.apartment:
        return 'شقة';
      case PropertyType.villa:
        return 'فيلا';
      case PropertyType.building:
        return 'عمارة';
      case PropertyType.land:
        return 'أرض';
      case PropertyType.office:
        return 'مكتب';
      case PropertyType.shop:
        return 'محل';
      case PropertyType.warehouse:
        return 'مستودع';
    }
  }

  static RentalMode? normalizeRentalMode(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'wholebuilding':
      case 'whole_building':
      case 'تاجيركاملالعمارة':
      case 'تأجيركاملالعمارة':
      case 'كامل':
      case 'whole':
        return RentalMode.wholeBuilding;
      case 'perunit':
      case 'per_unit':
      case 'تاجيرالوحدات':
      case 'تأجيرالوحدات':
      case 'الوحدات':
        return RentalMode.perUnit;
      default:
        return null;
    }
  }

  static String rentalModeKey(RentalMode mode) {
    return mode.name;
  }

  static String rentalModeLabel(RentalMode mode) {
    switch (mode) {
      case RentalMode.wholeBuilding:
        return 'تأجير كامل العمارة';
      case RentalMode.perUnit:
        return 'تأجير الوحدات';
    }
  }

  static ContractTerm normalizeContractTerm(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'daily':
      case 'يومي':
        return ContractTerm.daily;
      case 'quarterly':
      case 'ربعسنوي':
      case 'ربعسنوية':
        return ContractTerm.quarterly;
      case 'semiannual':
      case 'semiannualy':
      case 'نصفسنوي':
      case 'نصفسنوية':
        return ContractTerm.semiAnnual;
      case 'annual':
      case 'سنوي':
        return ContractTerm.annual;
      default:
        return ContractTerm.monthly;
    }
  }

  static String contractTermLabel(ContractTerm term) {
    switch (term) {
      case ContractTerm.daily:
        return 'يومي';
      case ContractTerm.monthly:
        return 'شهري';
      case ContractTerm.quarterly:
        return 'ربع سنوي';
      case ContractTerm.semiAnnual:
        return 'نصف سنوي';
      case ContractTerm.annual:
        return 'سنوي';
    }
  }

  static PaymentCycle normalizePaymentCycle(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'quarterly':
      case 'ربعسنوي':
      case 'ربعسنوية':
        return PaymentCycle.quarterly;
      case 'semiannual':
      case 'semiannualy':
      case 'نصفسنوي':
      case 'نصفسنوية':
        return PaymentCycle.semiAnnual;
      case 'annual':
      case 'سنوي':
        return PaymentCycle.annual;
      default:
        return PaymentCycle.monthly;
    }
  }

  static String paymentCycleLabel(PaymentCycle cycle) {
    switch (cycle) {
      case PaymentCycle.monthly:
        return 'شهري';
      case PaymentCycle.quarterly:
        return 'ربع سنوي';
      case PaymentCycle.semiAnnual:
        return 'نصف سنوي';
      case PaymentCycle.annual:
        return 'سنوي';
    }
  }

  static AdvanceMode normalizeAdvanceMode(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'deductfromtotal':
      case 'خصممنالاجمالي':
      case 'خصممنالإجمالي':
        return AdvanceMode.deductFromTotal;
      case 'covermonths':
      case 'تغطيةاشهر':
      case 'تغطيةأشهر':
        return AdvanceMode.coverMonths;
      default:
        return AdvanceMode.none;
    }
  }

  static String advanceModeLabel(AdvanceMode mode) {
    switch (mode) {
      case AdvanceMode.none:
        return 'بدون دفعة مقدمة';
      case AdvanceMode.deductFromTotal:
        return 'خصم من الإجمالي';
      case AdvanceMode.coverMonths:
        return 'تغطية أشهر';
    }
  }

  static MaintenancePriority normalizePriority(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'low':
      case 'منخفض':
        return MaintenancePriority.low;
      case 'high':
      case 'مرتفع':
        return MaintenancePriority.high;
      case 'urgent':
      case 'عاجل':
        return MaintenancePriority.urgent;
      default:
        return MaintenancePriority.medium;
    }
  }

  static String priorityLabel(MaintenancePriority priority) {
    switch (priority) {
      case MaintenancePriority.low:
        return 'منخفض';
      case MaintenancePriority.medium:
        return 'متوسط';
      case MaintenancePriority.high:
        return 'مرتفع';
      case MaintenancePriority.urgent:
        return 'عاجل';
    }
  }

  static MaintenanceStatus normalizeStatus(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'inprogress':
      case 'قيدالتنفيذ':
        return MaintenanceStatus.inProgress;
      case 'completed':
      case 'مكتمل':
        return MaintenanceStatus.completed;
      case 'canceled':
      case 'ملغي':
        return MaintenanceStatus.canceled;
      default:
        return MaintenanceStatus.open;
    }
  }

  static String statusLabel(MaintenanceStatus status) {
    switch (status) {
      case MaintenanceStatus.open:
        return 'مفتوح';
      case MaintenanceStatus.inProgress:
        return 'قيد التنفيذ';
      case MaintenanceStatus.completed:
        return 'مكتمل';
      case MaintenanceStatus.canceled:
        return 'ملغي';
    }
  }

  static String? normalizeVoucherKind(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'revenue':
      case 'قبض':
        return 'revenue';
      case 'expense':
      case 'صرف':
        return 'expense';
      default:
        return null;
    }
  }

  static String? normalizePaymentMethod(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'cash':
      case 'نقدا':
      case 'نقداً':
        return 'نقدًا';
      case 'banktransfer':
      case 'تحويلبنكي':
        return 'تحويل بنكي';
      case 'check':
      case 'شيك':
        return 'شيك';
      default:
        return null;
    }
  }

  static String? normalizePeriodicServiceType(Object? raw) {
    final value = _normalizeToken(raw);
    if (value.contains('clean') || value.contains('نظاف')) {
      return 'cleaning';
    }
    if (value.contains('elevator') || value.contains('مصعد')) {
      return 'elevator';
    }
    if (value.contains('internet') || value.contains('انترنت') || value.contains('إنترنت')) {
      return 'internet';
    }
    if (value.contains('water') || value.contains('مياه') || value.contains('ماء')) {
      return 'water';
    }
    if (value.contains('electric') || value.contains('كهرب')) {
      return 'electricity';
    }
    return null;
  }

  static String serviceTypeLabel(String type) {
    switch (type) {
      case 'cleaning':
        return 'نظافة';
      case 'elevator':
        return 'مصعد';
      case 'internet':
        return 'إنترنت';
      case 'water':
        return 'مياه';
      case 'electricity':
        return 'كهرباء';
      default:
        return type;
    }
  }

  static String? normalizeOfficePhone(Object? raw) {
    final digits = _digits(raw);
    if (digits.isEmpty) return '';
    if (digits.length == 10) return digits;
    return null;
  }

  static CommissionMode? normalizeCommissionMode(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'unspecified':
      case 'none':
      case 'بدون':
      case 'غيرمحدد':
        return CommissionMode.unspecified;
      case 'percent':
      case 'percentage':
      case 'نسبة':
        return CommissionMode.percent;
      case 'fixed':
      case 'مبلغثابت':
      case 'ثابت':
        return CommissionMode.fixed;
      default:
        return null;
    }
  }

  static OwnerAdjustmentCategory? normalizeOwnerAdjustmentCategory(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'ownerdiscount':
      case 'خصممستحقالمالك':
        return OwnerAdjustmentCategory.ownerDiscount;
      case 'admindiscount':
      case 'خصماداري':
        return OwnerAdjustmentCategory.adminDiscount;
      case 'paymentsettlement':
      case 'تسويةدفعة':
      case 'تسوية':
        return OwnerAdjustmentCategory.paymentSettlement;
      case 'other':
      case 'اخرى':
        return OwnerAdjustmentCategory.other;
      default:
        return null;
    }
  }

  static Map<String, dynamic> _clientTypePayload(String type) {
    return <String, dynamic>{
      'key': type,
      'label': TenantRecordService.clientTypeLabel(type),
      'requiresAttachments':
          TenantRecordService.clientTypeRequiresAttachments(type),
      'requiredFields': TenantRecordService.requiredFieldDescriptors(type),
    };
  }

  static Map<String, dynamic> _issue(
    String field,
    String label,
    String message, {
    bool requiresScreenCompletion = false,
    String? suggestedScreen,
  }) {
    return AiChatValidationIssue(
      field: field,
      label: label,
      message: message,
      requiresScreenCompletion: requiresScreenCompletion,
      suggestedScreen: suggestedScreen,
    ).toJson();
  }

  static AiChatValidationIssue _missing(
    String field,
    String label,
    String message, {
    bool requiresScreenCompletion = false,
    String? suggestedScreen,
  }) {
    return AiChatValidationIssue(
      field: field,
      label: label,
      message: message,
      requiresScreenCompletion: requiresScreenCompletion,
      suggestedScreen: suggestedScreen,
    );
  }

  static String _normalizeToken(Object? raw) {
    return _string(raw)
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[\s_\-]+'), '')
        .trim();
  }

  static String _string(Object? raw) {
    return (raw ?? '').toString().trim();
  }

  static String? _optionalString(Object? raw) {
    final value = _string(raw);
    return value.isEmpty ? null : value;
  }

  static int? _intValue(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(_string(raw));
  }

  static double? _doubleValue(Object? raw) {
    if (raw == null) return null;
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.tryParse(_string(raw));
  }

  static bool? _boolValue(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    final value = _normalizeToken(raw);
    if (value == 'true' ||
        value == '1' ||
        value == 'yes' ||
        value == 'نعم' ||
        value == 'مفروشة') {
      return true;
    }
    if (value == 'false' ||
        value == '0' ||
        value == 'no' ||
        value == 'لا' ||
        value == 'غيرمفروشة') {
      return false;
    }
    return null;
  }

  static bool? _boolAccessValue(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    final value = _normalizeToken(raw);
    if (value == 'true' ||
        value == '1' ||
        value == 'yes' ||
        value == 'allow' ||
        value == 'allowed' ||
        value == 'enabled' ||
        value == 'enable' ||
        value == 'open' ||
        value == 'active' ||
        value == 'unblocked' ||
        value == 'نعم' ||
        value == 'سماح' ||
        value == 'مسموح' ||
        value == 'تفعيل' ||
        value == 'مفعل' ||
        value == 'فتح') {
      return true;
    }
    if (value == 'false' ||
        value == '0' ||
        value == 'no' ||
        value == 'block' ||
        value == 'blocked' ||
        value == 'disable' ||
        value == 'disabled' ||
        value == 'close' ||
        value == 'inactive' ||
        value == 'لا' ||
        value == 'ايقاف' ||
        value == 'إيقاف' ||
        value == 'موقوف' ||
        value == 'حظر' ||
        value == 'محظور') {
      return false;
    }
    return null;
  }

  static DateTime? _dateOnly(Object? raw) {
    final value = _string(raw);
    if (value.isEmpty) return null;
    try {
      return KsaTime.dateOnly(DateTime.parse(value));
    } catch (_) {
      return null;
    }
  }

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = _string(raw);
    if (single.isEmpty) return const <String>[];
    return <String>[single];
  }

  static String _digits(Object? raw) {
    final value = _string(raw).replaceAll(RegExp(r'\D'), '');
    if (value.isEmpty) return '';
    return _digitsOnly.hasMatch(value) ? value : '';
  }

  static AiChatValidationResult<AiChatReportsPeriodDraft> _validateReportsPeriod({
    Object? fromDate,
    Object? toDate,
  }) {
    final hasFrom = _optionalString(fromDate) != null;
    final hasTo = _optionalString(toDate) != null;
    final parsedFrom = _dateOnly(fromDate);
    final parsedTo = _dateOnly(toDate);

    if (hasFrom && parsedFrom == null) {
      return const AiChatValidationResult<AiChatReportsPeriodDraft>.error(
        'تاريخ البداية يجب أن يكون بصيغة YYYY-MM-DD.',
      );
    }
    if (hasTo && parsedTo == null) {
      return const AiChatValidationResult<AiChatReportsPeriodDraft>.error(
        'تاريخ النهاية يجب أن يكون بصيغة YYYY-MM-DD.',
      );
    }
    if (parsedFrom != null &&
        parsedTo != null &&
        parsedFrom.isAfter(parsedTo)) {
      return const AiChatValidationResult<AiChatReportsPeriodDraft>.error(
        'تاريخ البداية يجب أن يكون قبل أو يساوي تاريخ النهاية.',
      );
    }

    return AiChatValidationResult<AiChatReportsPeriodDraft>.success(
      AiChatReportsPeriodDraft(fromDate: parsedFrom, toDate: parsedTo),
    );
  }

  static String? _validateReportsAmount(double? amount) {
    if (amount == null || amount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من صفر.';
    }
    if (amount > 500000000) {
      return 'الحد الأقصى للمبلغ هو 500,000,000.';
    }
    return null;
  }

  static String? _validateReportsNote(String note) {
    if (note.length > 150) {
      return 'الملاحظات لا تزيد عن 150 حرفًا.';
    }
    return null;
  }

  static String? _validateActionDate(DateTime date) {
    if (date.isAfter(KsaTime.today())) {
      return 'تاريخ العملية لا يمكن أن يكون بعد اليوم.';
    }
    return null;
  }

  static String? _validateBankFieldLengths({
    required String bankName,
    required String accountNumber,
    required String iban,
  }) {
    if (bankName.length > 30) {
      return 'اسم البنك لا يزيد عن 30 حرفًا.';
    }
    if (accountNumber.length > 40) {
      return 'رقم الحساب لا يزيد عن 40 حرفًا.';
    }
    if (iban.length > 40) {
      return 'رقم الآيبان لا يزيد عن 40 حرفًا.';
    }
    return null;
  }

  static List<PaymentCycle> _allowedCyclesForTerm(ContractTerm term) {
    switch (term) {
      case ContractTerm.daily:
        return const <PaymentCycle>[];
      case ContractTerm.monthly:
        return const <PaymentCycle>[PaymentCycle.monthly];
      case ContractTerm.quarterly:
        return const <PaymentCycle>[
          PaymentCycle.monthly,
          PaymentCycle.quarterly,
        ];
      case ContractTerm.semiAnnual:
        return const <PaymentCycle>[
          PaymentCycle.monthly,
          PaymentCycle.quarterly,
          PaymentCycle.semiAnnual,
        ];
      case ContractTerm.annual:
        return const <PaymentCycle>[
          PaymentCycle.monthly,
          PaymentCycle.quarterly,
          PaymentCycle.semiAnnual,
          PaymentCycle.annual,
        ];
    }
  }
}
