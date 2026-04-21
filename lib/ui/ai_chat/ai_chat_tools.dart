import '../../data/services/app_architecture_registry.dart';

class AiChatTools {
  AiChatTools._();

  static final Set<String> _writeToolNames = <String>{
    'add_tenant',
    'add_client_record',
    'edit_tenant',
    'archive_tenant',
    'unarchive_tenant',
    'blacklist_tenant',
    'unblacklist_tenant',
    'add_property',
    'edit_property',
    'archive_property',
    'unarchive_property',
    'create_contract',
    'edit_contract',
    'renew_contract',
    'terminate_contract',
    'create_invoice',
    'record_payment',
    'create_manual_voucher',
    'add_building_unit',
    'cancel_invoice',
    'create_maintenance_request',
    'update_maintenance_status',
    'create_periodic_service',
    'update_periodic_service',
    'update_settings',
    'mark_notification_read',
    'add_office_client',
    'edit_office_client',
    'delete_office_client',
    'set_office_client_access',
    'set_office_client_subscription',
    'generate_office_client_reset_link',
    'add_office_user',
    'edit_office_user',
    'set_office_user_permission',
    'set_office_user_access',
    'delete_office_user',
    'generate_office_user_reset_link',
    'assign_property_owner_from_reports',
    'record_office_report_voucher',
    'record_office_withdrawal',
    'set_report_commission_rule',
    'record_owner_payout',
    'record_owner_adjustment',
    'add_owner_bank_account',
    'edit_owner_bank_account',
    'delete_owner_bank_account',
  };

  static final Map<String, String> _toolLabels = <String, String>{
    'get_home_dashboard': 'ملخص الرئيسية',
    'get_office_dashboard': 'ملخص لوحة المكتب',
    'get_app_blueprint': 'عرض خريطة التطبيق',
    'get_contract_invoice_history': 'سجل فواتير العقد',
    'add_tenant': 'إضافة عميل',
    'add_client_record': 'إضافة عميل',
    'edit_tenant': 'تعديل عميل',
    'archive_tenant': 'أرشفة عميل',
    'unarchive_tenant': 'فك أرشفة عميل',
    'blacklist_tenant': 'إضافة للقائمة السوداء',
    'unblacklist_tenant': 'إزالة من القائمة السوداء',
    'add_property': 'إضافة عقار',
    'edit_property': 'تعديل عقار',
    'archive_property': 'أرشفة عقار',
    'unarchive_property': 'فك أرشفة عقار',
    'create_contract': 'إنشاء عقد',
    'edit_contract': 'تعديل عقد',
    'renew_contract': 'تجديد عقد',
    'terminate_contract': 'إنهاء عقد',
    'create_invoice': 'إصدار فاتورة',
    'record_payment': 'تسجيل دفعة',
    'create_manual_voucher': 'إنشاء سند يدوي',
    'add_building_unit': 'إضافة وحدة',
    'cancel_invoice': 'إلغاء فاتورة',
    'create_maintenance_request': 'إنشاء طلب صيانة',
    'update_maintenance_status': 'تحديث حالة الصيانة',
    'create_periodic_service': 'إنشاء خدمة دورية',
    'update_periodic_service': 'تحديث خدمة دورية',
    'update_settings': 'تعديل الإعدادات',
    'open_notification_target': 'فتح هدف الإشعار',
    'open_tenant_entry': 'فتح شاشة إضافة عميل',
    'open_property_entry': 'فتح شاشة إضافة عقار',
    'open_contract_entry': 'فتح شاشة إضافة عقد',
    'open_maintenance_entry': 'فتح شاشة إضافة صيانة',
    'open_contract_invoice_history': 'فتح سجل فواتير العقد',
    'mark_notification_read': 'تعليم إشعار كمقروء',
    'navigate_to_screen': 'فتح شاشة',
    'add_office_client': 'إضافة عميل مكتب',
    'edit_office_client': 'تعديل عميل مكتب',
    'delete_office_client': 'حذف عميل مكتب',
    'get_office_users_list': 'قائمة مستخدمي المكتب',
    'get_office_user_details': 'تفاصيل مستخدم مكتب',
    'add_office_user': 'إضافة مستخدم مكتب',
    'edit_office_user': 'تعديل مستخدم مكتب',
    'set_office_user_permission': 'تعديل صلاحية مستخدم مكتب',
    'set_office_user_access': 'إدارة دخول مستخدم مكتب',
    'delete_office_user': 'حذف مستخدم مكتب',
    'generate_office_user_reset_link': 'رابط إعادة تعيين مستخدم مكتب',
    'get_activity_log': 'سجل النشاط',
    'get_office_client_access': 'قراءة وصول عميل مكتب',
    'get_office_client_subscription': 'قراءة اشتراك عميل مكتب',
    'set_office_client_access': 'تعديل وصول عميل مكتب',
    'set_office_client_subscription': 'تعديل اشتراك عميل مكتب',
    'generate_office_client_reset_link': 'رابط إعادة تعيين عميل مكتب',
    'get_office_report': 'تقرير المكتب',
    'get_owners_report': 'تقرير الملاك',
    'get_owner_report_details': 'تفاصيل تقرير مالك',
    'preview_owner_settlement': 'معاينة تسوية مالك',
    'preview_office_settlement': 'معاينة تسوية المكتب',
    'get_owner_bank_accounts': 'الحسابات البنكية للمالك',
    'assign_property_owner_from_reports': 'ربط مالك بعقار',
    'record_office_report_voucher': 'تسجيل مصروف أو عمولة مكتب',
    'record_office_withdrawal': 'تحويل رصيد المكتب',
    'set_report_commission_rule': 'تعديل عمولة المكتب',
    'record_owner_payout': 'تحويل رصيد مالك',
    'record_owner_adjustment': 'تسجيل خصم أو تسوية مالك',
    'add_owner_bank_account': 'إضافة حساب بنكي للمالك',
    'edit_owner_bank_account': 'تعديل حساب بنكي للمالك',
    'delete_owner_bank_account': 'حذف حساب بنكي للمالك',
    'get_property_service_details': 'تفاصيل خدمة عقار',
  };

  static final Set<String> _officeReadToolNames = <String>{
    'get_office_dashboard',
    'get_office_clients_list',
    'get_office_client_details',
    'get_office_summary',
    'get_office_client_access',
    'get_office_client_subscription',
    'get_office_users_list',
    'get_office_user_details',
    'get_activity_log',
  };

  static bool isWriteTool(String name) => _writeToolNames.contains(name);
  static bool isOfficeWideReadTool(String name) =>
      _officeReadToolNames.contains(name);

  static final Set<String> _navigationToolNames = <String>{
    'navigate_to_screen',
    'open_tenant_entry',
    'open_property_entry',
    'open_contract_entry',
    'open_maintenance_entry',
    'open_contract_invoice_history',
  };

  static final Set<String> _architectureToolNames = <String>{
    'get_app_blueprint',
  };

  static final Set<String> _propertyToolNames = <String>{
    'get_properties_summary',
    'get_properties_list',
    'get_property_details',
    'add_property',
    'open_property_entry',
    'edit_property',
    'archive_property',
    'unarchive_property',
    'add_building_unit',
    'get_property_services',
    'get_property_service_details',
    'get_periodic_service_history',
    'create_periodic_service',
    'update_periodic_service',
  };

  static final Set<String> _tenantToolNames = <String>{
    'get_tenants_list',
    'get_tenant_details',
    'add_tenant',
    'add_client_record',
    'open_tenant_entry',
    'edit_tenant',
    'archive_tenant',
    'unarchive_tenant',
    'blacklist_tenant',
    'unblacklist_tenant',
  };

  static final Set<String> _contractToolNames = <String>{
    'get_contracts_list',
    'get_active_contracts',
    'get_contract_details',
    'get_contract_invoice_history',
    'create_contract',
    'edit_contract',
    'renew_contract',
    'terminate_contract',
    'open_contract_entry',
    'open_contract_invoice_history',
    'get_tenants_list',
    'get_tenant_details',
    'get_properties_list',
    'get_property_details',
  };

  static final Set<String> _invoiceToolNames = <String>{
    'get_invoices_list',
    'get_unpaid_invoices',
    'create_invoice',
    'record_payment',
    'create_manual_voucher',
    'cancel_invoice',
    'get_contract_details',
    'get_contract_invoice_history',
    'open_contract_invoice_history',
  };

  static final Set<String> _maintenanceToolNames = <String>{
    'get_maintenance_list',
    'get_maintenance_details',
    'create_maintenance_request',
    'update_maintenance_status',
    'create_periodic_service',
    'update_periodic_service',
    'get_property_services',
    'get_property_service_details',
    'get_periodic_service_history',
    'open_maintenance_entry',
    'get_properties_list',
    'get_property_details',
  };

  static final Set<String> _reportToolNames = <String>{
    'get_financial_summary',
    'get_total_receivables',
    'get_overdue_count',
    'get_office_report',
    'get_owners_report',
    'get_owner_report_details',
    'preview_owner_settlement',
    'preview_office_settlement',
    'get_owner_bank_accounts',
    'assign_property_owner_from_reports',
    'record_office_report_voucher',
    'record_office_withdrawal',
    'set_report_commission_rule',
    'record_owner_payout',
    'record_owner_adjustment',
    'add_owner_bank_account',
    'edit_owner_bank_account',
    'delete_owner_bank_account',
  };

  static final Set<String> _notificationToolNames = <String>{
    'get_notifications',
    'open_notification_target',
    'mark_notification_read',
  };

  static final Set<String> _officeToolNames = <String>{
    'get_office_dashboard',
    'get_office_clients_list',
    'get_office_client_details',
    'get_office_summary',
    'get_office_users_list',
    'get_office_user_details',
    'get_activity_log',
    'get_office_client_access',
    'get_office_client_subscription',
    'add_office_client',
    'edit_office_client',
    'delete_office_client',
    'set_office_client_access',
    'set_office_client_subscription',
    'generate_office_client_reset_link',
    'add_office_user',
    'edit_office_user',
    'set_office_user_permission',
    'set_office_user_access',
    'delete_office_user',
    'generate_office_user_reset_link',
  };

  static final List<String> _architectureKeywords = <String>[
    'شاشة',
    'شاشات',
    'المسار',
    'مسار',
    'واجهة',
    'واجهات',
    'صلاحية',
    'صلاحيات',
    'خريطة التطبيق',
    'المخطط',
    'المعمار',
    'البنية',
    'مدعوم',
    'يدعم',
    'مسموح',
    'ممنوع',
  ];

  static final List<String> _propertyKeywords = <String>[
    'عقار',
    'العقار',
    'عقارات',
    'العقارات',
    'عمارة',
    'مبنى',
    'مباني',
    'وحدة',
    'وحدات',
  ];

  static final List<String> _tenantKeywords = <String>[
    'مستأجر',
    'مستاجر',
    'مستأجرين',
    'مستاجرين',
    'عميل',
    'عملاء',
  ];

  static final List<String> _contractKeywords = <String>[
    'عقد',
    'عقود',
    'إيجار',
    'ايجار',
    'تجديد',
    'إنهاء',
    'انهاء',
    'فسخ',
  ];

  static final List<String> _invoiceKeywords = <String>[
    'فاتورة',
    'فاتوره',
    'فواتير',
    'سند',
    'سندات',
    'دفعة',
    'دفعات',
    'سداد',
    'دفع',
    'تحصيل',
    'مستحق',
    'مستحقات',
  ];

  static final List<String> _maintenanceKeywords = <String>[
    'صيانة',
    'صيانه',
    'صيانة دورية',
    'صيانه دوريه',
    'خدمة',
    'خدمه',
    'خدمات',
    'طلب صيانة',
    'طلب صيانه',
  ];

  static final List<String> _reportKeywords = <String>[
    'تقرير',
    'تقارير',
    'إحصائية',
    'احصائية',
    'إحصائيات',
    'احصائيات',
    'أرباح',
    'ارباح',
    'خسائر',
    'ملخص',
    'رصيد',
    'أرصدة',
    'ارصدة',
  ];

  static final List<String> _notificationKeywords = <String>[
    'إشعار',
    'اشعار',
    'إشعارات',
    'اشعارات',
    'تنبيه',
    'تنبيهات',
  ];

  static final List<String> _officeKeywords = <String>[
    'مكتب',
    'المكتب',
    'مستخدم',
    'مستخدمين',
    'المستخدمين',
    'اشتراك',
    'باقة',
    'باقات',
  ];

  static bool shouldExposeOfficeTools({
    required bool isOfficeMode,
    required bool canReadAll,
  }) {
    return isOfficeMode && canReadAll;
  }

  static String actionLabel(String name) => _toolLabels[name] ?? name;

  static String _toolName(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is! Map) return '';
    return (function['name'] ?? '').toString();
  }

  static String _normalizeMessage(String? text) {
    return (text ?? '').trim().toLowerCase();
  }

  static bool _containsAnyKeyword(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  static Set<String> _sessionBaseToolNames({
    required bool isOfficeMode,
    required bool canReadAll,
  }) {
    if (shouldExposeOfficeTools(
      isOfficeMode: isOfficeMode,
      canReadAll: canReadAll,
    )) {
      return <String>{'get_office_dashboard'};
    }
    return <String>{'get_home_dashboard'};
  }

  static Set<String>? _focusedToolNames({
    required bool isOfficeMode,
    required bool canReadAll,
    String? userMessage,
  }) {
    final normalized = _normalizeMessage(userMessage);
    if (normalized.isEmpty) return null;

    final names = <String>{
      ..._navigationToolNames,
      ..._sessionBaseToolNames(
        isOfficeMode: isOfficeMode,
        canReadAll: canReadAll,
      ),
    };

    final architectureOnly =
        _containsAnyKeyword(normalized, _architectureKeywords);
    if (architectureOnly) {
      names.addAll(_architectureToolNames);
      return names;
    }

    var hasFocusedDomain = false;

    void addDomainTools(List<String> keywords, Set<String> domainTools) {
      if (_containsAnyKeyword(normalized, keywords)) {
        hasFocusedDomain = true;
        names.addAll(domainTools);
      }
    }

    addDomainTools(_propertyKeywords, _propertyToolNames);
    addDomainTools(_tenantKeywords, _tenantToolNames);
    addDomainTools(_contractKeywords, _contractToolNames);
    addDomainTools(_invoiceKeywords, _invoiceToolNames);
    addDomainTools(_maintenanceKeywords, _maintenanceToolNames);
    addDomainTools(_reportKeywords, _reportToolNames);
    addDomainTools(_notificationKeywords, _notificationToolNames);
    addDomainTools(_officeKeywords, _officeToolNames);

    if (!hasFocusedDomain) return null;
    return names;
  }

  static List<Map<String, dynamic>> _filterTools(
    List<Map<String, dynamic>> tools, {
    Set<String>? includeNames,
    Set<String> excludeNames = const <String>{},
  }) {
    return tools.where((tool) {
      final name = _toolName(tool);
      if (name.isEmpty) return false;
      if (excludeNames.contains(name)) return false;
      if (includeNames != null) return includeNames.contains(name);
      return true;
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> getTools({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
    String? userMessage,
  }) {
    final tools = <Map<String, dynamic>>[];

    // ===== أدوات القراءة (متاحة للجميع) =====
    tools.addAll(
      _readTools.where((tool) {
        final function = tool['function'];
        final name = function is Map ? (function['name'] ?? '').toString() : '';
        if (isOfficeMode && name == 'get_home_dashboard') return false;
        return true;
      }),
    );

    // ===== أدوات الكتابة (فقط لمن يملك الصلاحية) =====
    if (canWrite) {
      tools.addAll(_writeTools);
    }

    // ===== أدوات المكتب =====
    if (shouldExposeOfficeTools(
      isOfficeMode: isOfficeMode,
      canReadAll: canReadAll,
    )) {
      tools.addAll(_officeReadTools);
      if (canWrite) tools.addAll(_officeWriteTools);
    }

    // ===== أدوات التنقل =====
    tools.addAll(
      _navTools(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      ),
    );

    final focusedNames = _focusedToolNames(
      isOfficeMode: isOfficeMode,
      canReadAll: canReadAll,
      userMessage: userMessage,
    );

    if (focusedNames != null) {
      return _filterTools(tools, includeNames: focusedNames);
    }

    return _filterTools(
      tools,
      excludeNames: _architectureToolNames,
    );
  }

  static Map<String, dynamic> _fn(
    String name,
    String description,
    Map<String, dynamic> parameters,
  ) {
    // استخراج الحقول المطلوبة ثم حذف 'required' من داخل كل property
    final requiredFields = parameters.entries
        .where(
            (e) => (e.value as Map<String, dynamic>)['required'] == true)
        .map((e) => e.key)
        .toList();

    final cleanProps = <String, dynamic>{};
    for (final entry in parameters.entries) {
      final prop = Map<String, dynamic>.from(entry.value as Map);
      prop.remove('required');
      cleanProps[entry.key] = prop;
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': cleanProps,
          'required': requiredFields,
        },
      },
    };
  }

  // ================================================================
  //  أدوات القراءة
  // ================================================================
  static final _readTools = <Map<String, dynamic>>[
    _fn(
      'get_home_dashboard',
      'جلب ملخص شاشة الرئيسية الفعلية للحساب العادي بما فيها بطاقات المستحقات والمدفوعات المتأخرة والتنبيهات، والأزرار السريعة، وأقرب استحقاقات الإيجار كما تظهر في الواجهة.',
      {},
    ),
    _fn(
      'get_app_blueprint',
      'عرض خريطة التطبيق وقواعده التشغيلية والحقول الإلزامية والقيود التي يجب الالتزام بها قبل تنفيذ أي عملية.',
      {},
    ),
    _fn(
      'get_properties_summary',
      'ملخص العقارات على مستوى العقارات الرئيسية فقط. اعتبر العمارة ذات الوحدات عقارًا رئيسيًا واحدًا، ثم أعد تفاصيل وحداتها المهيأة والمضافة والمشغولة والمتاحة.',
      {},
    ),
    _fn(
      'get_properties_list',
      'قائمة العقارات الرئيسية مع تفاصيلها الدلالية. أظهر العمارة ذات الوحدات كعقار واحد مع ملخص وحداتها، ولا تعدّ كل وحدة عقارًا مستقلاً ضمن القائمة العامة.',
      {},
    ),
    _fn(
      'get_property_details',
      'تفاصيل عقار معين بالاسم مع توضيح هل هو عقار رئيسي أم وحدة داخل عمارة، ومع شرح الإشغال والوحدات إن كان عمارة ذات وحدات.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العقار أو جزء منه',
          'required': true,
        },
      },
    ),
    _fn('get_tenants_list', 'قائمة المستأجرين مع بياناتهم', {}),
    _fn(
      'get_tenant_details',
      'تفاصيل مستأجر معين بالاسم أو الهوية أو الجوال',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستأجر أو رقم هويته أو جواله',
          'required': true,
        },
      },
    ),
    _fn('get_contracts_list', 'قائمة العقود مع حالاتها الأساسية وبيانات المستأجر والعقار والمبلغ وتاريخ البداية والنهاية.', {}),
    _fn('get_active_contracts', 'العقود النشطة فقط', {}),
    _fn(
      'get_contract_details',
      'تفاصيل عقد معين بالرقم التسلسلي أو اسم المستأجر، مع ملخص الدفعات: إجمالي الدفعات، المسدد، غير المسدد، الملغي، المتأخر، الدفعة الحالية، الدفعة القادمة، وآخر دفعة مسددة.',
      {
        'query': {
          'type': 'string',
          'description': 'رقم العقد أو اسم المستأجر',
          'required': true,
        },
      },
    ),
    _fn(
      'get_contract_invoice_history',
      'جلب سجل دفعات وسندات العقد بالتفصيل لعقد محدد، مع أعداد الدفعات والمسددة وغير المسددة والمتأخرة والمتبقي ومعاينة الدفعات كما تظهر في شاشة invoices_history. استخدمه عند السؤال الدقيق عن الأقساط والدفعات والاستحقاقات.',
      {
        'query': {
          'type': 'string',
          'description': 'رقم العقد أو اسم العميل أو اسم العقار',
          'required': true,
        },
      },
    ),
    _fn('get_invoices_list', 'قائمة الفواتير والسندات', {}),
    _fn('get_unpaid_invoices', 'الفواتير غير المدفوعة والمتأخرة', {}),
    _fn('get_maintenance_list', 'قائمة طلبات الصيانة والخدمات', {}),
    _fn(
      'get_maintenance_details',
      'تفاصيل طلب صيانة معين بالعنوان أو الرقم',
      {
        'query': {
          'type': 'string',
          'description': 'عنوان الطلب أو رقمه التسلسلي',
          'required': true,
        },
      },
    ),
    _fn('get_total_receivables', 'إجمالي المستحقات غير المدفوعة', {}),
    _fn('get_overdue_count', 'عدد الدفعات المتأخرة', {}),
    _fn(
      'get_financial_summary',
      'ملخص شاشة التقارير الرئيسية مع دعم الفلاتر الزمنية وفلاتر العقار والمالك والعقد والخدمة والسندات.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'contractQuery': {
          'type': 'string',
          'description': 'اختياري: رقم العقد أو معرّفه',
        },
        'serviceType': {
          'type': 'string',
          'description': 'اختياري: نوع الخدمة في التقارير',
        },
        'contractStatus': {
          'type': 'string',
          'description': 'اختياري: حالة العقد',
        },
        'voucherState': {
          'type': 'string',
          'description': 'اختياري: posted/draft/cancelled/reversed',
        },
        'voucherSource': {
          'type': 'string',
          'description': 'اختياري: contract/service/manual/owner/office',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_settings',
      'جلب شاشة الإعدادات الفعلية من user_prefs بما فيها اللغة والتقويم وتنبيهات الدفعات والعقود وساعة الإرسال اليومية، ويمكن إرجاع القوالب النصية عند الطلب.',
      {
        'includeTemplates': {
          'type': 'boolean',
          'description': 'اختياري: true لإرجاع نصوص القوالب الرسائلية أيضًا',
        },
      },
    ),
    _fn(
      'get_building_units',
      'عرض وحدات مبنى/عمارة معينة',
      {
        'buildingName': {
          'type': 'string',
          'description': 'اسم المبنى/العمارة',
          'required': true,
        },
      },
    ),
    _fn(
      'get_invoices_by_type',
      'فلترة الفواتير/السندات حسب النوع (عقود/خدمات/يدوي)',
      {
        'origin': {
          'type': 'string',
          'description': 'مصدر الفاتورة: contract/maintenance/manual/all',
          'required': true,
        },
      },
    ),
    _fn(
      'get_invoice_payment_history',
      'تفاصيل سند واحد بما فيها المبلغ والمدفوع والمتبقي وطريقة الدفع والملاحظة. استخدمها بعد تقارير السندات عندما يطلب المستخدم شرح سند محدد أو كيفية سداده.',
      {
        'invoiceSerialNo': {
          'type': 'string',
          'description': 'رقم الفاتورة التسلسلي',
          'required': true,
        },
      },
    ),
    _fn(
      'get_notifications',
      'جلب الإشعارات الحالية الفعلية مع أنواعها الكاملة وإمكانية التصفية حسب النوع، وتحديد عدد النتائج، وإظهار أو إخفاء التنبيهات المقروءة.',
      {
        'kind': {
          'type': 'string',
          'description':
              'اختياري: all أو contract_started_today أو contract_expiring أو contract_ended أو contract_due_soon أو contract_due_today أو contract_due_overdue أو invoice_overdue أو maintenance_today أو service_start أو service_due',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوب إرجاعها',
        },
        'includeDismissed': {
          'type': 'boolean',
          'description': 'اختياري: true لإرجاع التنبيهات المقروءة أيضًا',
        },
      },
    ),
    _fn(
      'open_notification_target',
      'فتح الشاشة أو العنصر المرتبط بإشعار محدد بالاعتماد على notificationRef القادم من get_notifications.',
      {
        'notificationRef': {
          'type': 'string',
          'description': 'مرجع الإشعار القادم من get_notifications',
          'required': true,
        },
      },
    ),
    _fn(
      'get_property_service_details',
      'تفاصيل خدمة عقار محددة كما تظهر في شاشة خدمات العقار، بما فيها نمط الإدارة والفوترة والجدولة والسجل المختصر وحدود ما يحتاج استكمالًا من الشاشة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'serviceType': {
          'type': 'string',
          'description':
              'نوع الخدمة: cleaning أو elevator أو internet أو water أو electricity',
          'required': true,
        },
      },
    ),
    _fn(
      'get_properties_report',
      'تقرير العقارات الفعلي من شاشة التقارير مع الفلاتر والترتيب وإبراز الأعلى والأقل ربحًا.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه لتقييد النطاق',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'contractQuery': {
          'type': 'string',
          'description': 'اختياري: رقم العقد أو معرّفه',
        },
        'propertyType': {
          'type': 'string',
          'description': 'اختياري: apartment/villa/building/office/shop/warehouse/land',
        },
        'availability': {
          'type': 'string',
          'description': 'اختياري: occupied/vacant/all',
        },
        'sortBy': {
          'type': 'string',
          'description': 'اختياري: net/revenues/expenses/name',
        },
        'sortDirection': {
          'type': 'string',
          'description': 'اختياري: asc/desc',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_clients_report',
      'تقرير العملاء والمستأجرين والشركات ومقدمي الخدمات مع الفلاتر الخاصة بالربط والأرشفة وانتهاء الهوية.',
      {
        'clientType': {
          'type': 'string',
          'description': 'اختياري: tenant/company/serviceProvider/all',
        },
        'linkedState': {
          'type': 'string',
          'description': 'اختياري: linked/unlinked/all',
        },
        'idExpiryState': {
          'type': 'string',
          'description': 'اختياري: expired/valid/all',
        },
        'includeArchived': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم احتساب المؤرشفين ضمن القائمة',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
      },
    ),
    _fn(
      'get_contracts_report',
      'تقرير العقود الفعلي من شاشة التقارير مع فلاتر المدة والحالة والانتهاء القريب.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'contractQuery': {
          'type': 'string',
          'description': 'اختياري: رقم العقد أو معرّفه',
        },
        'term': {
          'type': 'string',
          'description': 'اختياري: daily/monthly/quarterly/semiAnnual/annual',
        },
        'contractStatus': {
          'type': 'string',
          'description': 'اختياري: active/inactive/ended/terminated',
        },
        'expiringOnly': {
          'type': 'boolean',
          'description': 'اختياري: عرض العقود القريبة من الانتهاء فقط',
        },
        'endsTodayOnly': {
          'type': 'boolean',
          'description': 'اختياري: عرض العقود التي تنتهي اليوم فقط',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_services_report',
      'تقرير الخدمات والصيانة من شاشة التقارير مع فلاتر النوع والأولوية وحالة السداد.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'contractQuery': {
          'type': 'string',
          'description': 'اختياري: رقم العقد أو معرّفه',
        },
        'serviceType': {
          'type': 'string',
          'description': 'اختياري: نوع الخدمة',
        },
        'priority': {
          'type': 'string',
          'description': 'اختياري: low/medium/high/urgent',
        },
        'paymentState': {
          'type': 'string',
          'description': 'اختياري: paid/unpaid/all',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_invoices_report',
      'تقرير السندات والقيود المالية من شاشة التقارير مع فلاتر الاتجاه والمصدر والحالة. استخدمه لتتبع مصدر الإيرادات والمصروفات ومعرفة السندات المرتبطة بكل بند في التقارير.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'contractQuery': {
          'type': 'string',
          'description': 'اختياري: رقم العقد أو معرّفه',
        },
        'direction': {
          'type': 'string',
          'description': 'اختياري: receipt/payment',
        },
        'operation': {
          'type': 'string',
          'description': 'اختياري: rent/service/office_commission/office_expense/owner_payout/owner_adjustment وغيرها حسب شاشة التقارير',
        },
        'voucherState': {
          'type': 'string',
          'description': 'اختياري: posted/draft/cancelled/reversed',
        },
        'voucherSource': {
          'type': 'string',
          'description': 'اختياري: contract/service/manual/owner/office',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_office_report',
      'تقرير المكتب الكامل من شاشة التقارير مع الرصيد والدفتر وعمولة المكتب الحالية. يعيد دفتر المكتب مع السندات المرتبطة بحيث يمكن تفسير صافي الربح والمصروفات والتحويلات بندًا بندًا.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'ledgerLimit': {
          'type': 'integer',
          'description': 'اختياري: عدد حركات دفتر المكتب المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_owners_report',
      'تقرير الملاك من شاشة التقارير مع الجاهز للتحويل وأرصدة كل مالك.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه لتقييد النتائج',
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المالك أو معرّفه',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_owner_report_details',
      'تفاصيل تقرير مالك واحد مع تفصيل العقارات والدفتر والحسابات البنكية. استخدمه لشرح كيف تكوّن رصيد المالك وما السندات التي سببت الإيجارات أو المصروفات أو الخصومات أو التحويلات.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه لتقييد التفاصيل',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'ledgerLimit': {
          'type': 'integer',
          'description': 'اختياري: عدد حركات دفتر المالك المطلوبة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'preview_owner_settlement',
      'معاينة تسوية المالك قبل تنفيذ التحويل الفعلي.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'preview_office_settlement',
      'معاينة تسوية المكتب قبل تنفيذ سحب أو تحويل الرصيد.',
      {
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'includeDraft': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود غير المرحلة',
        },
        'includeCancelled': {
          'type': 'boolean',
          'description': 'اختياري: هل يتم تضمين القيود الملغاة',
        },
      },
    ),
    _fn(
      'get_owner_bank_accounts',
      'قراءة الحسابات البنكية المحفوظة لمالك محدد.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
      },
    ),
    _fn(
      'get_property_services',
      'جلب شاشة خدمات العقار كاملة لعقار معين، مع بطاقات الخدمات الخمس وحالة كل خدمة ونمط إدارتها وجدولها وحدود الكتابة التي قد تتطلب استكمالًا من الشاشة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
      },
    ),
    _fn(
      'get_periodic_service_history',
      'جلب سجل خدمة عقار معينة بحسب منطق الشاشة الفعلي: طلبات الصيانة أو سجل النسب أو الدفعات أو لا شيء إذا كانت الخدمة على المستأجر مباشرة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'serviceType': {
          'type': 'string',
          'description': 'نوع الخدمة: cleaning/elevator/internet/water/electricity',
          'required': true,
        },
      },
    ),
  ];

  // ================================================================
  //  أدوات الكتابة
  // ================================================================
  static final _writeTools = <Map<String, dynamic>>[
    // --- مستأجرين ---
    _fn(
      'edit_tenant',
      'تعديل بيانات عميل موجود من أي نوع مع الالتزام بالحقول الإلزامية الخاصة بنوعه الحالي أو الجديد.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو رقم هويته أو جواله للبحث',
          'required': true,
        },
        'clientType': {
          'type': 'string',
          'description': 'نوع العميل إذا كان المطلوب تغيير النوع: tenant/company/serviceProvider',
        },
        'fullName': {'type': 'string', 'description': 'الاسم الجديد'},
        'nationalId': {'type': 'string', 'description': 'رقم الهوية الجديد'},
        'phone': {'type': 'string', 'description': 'الجوال الجديد'},
        'email': {'type': 'string', 'description': 'البريد الجديد'},
        'nationality': {'type': 'string', 'description': 'الجنسية'},
        'companyName': {
          'type': 'string',
          'description': 'اسم الشركة عند تعديل عميل من نوع company',
        },
        'companyCommercialRegister': {
          'type': 'string',
          'description': 'رقم السجل التجاري عند تعديل عميل من نوع company',
        },
        'companyTaxNumber': {
          'type': 'string',
          'description': 'الرقم الضريبي عند تعديل عميل من نوع company',
        },
        'companyRepresentativeName': {
          'type': 'string',
          'description': 'اسم ممثل الشركة عند تعديل عميل من نوع company',
        },
        'companyRepresentativePhone': {
          'type': 'string',
          'description': 'جوال ممثل الشركة عند تعديل عميل من نوع company',
        },
        'serviceSpecialization': {
          'type': 'string',
          'description': 'التخصص/الخدمة عند تعديل عميل من نوع serviceProvider',
        },
      },
    ),
    _fn(
      'add_client_record',
      'إضافة عميل جديد من أي نوع. لا تستخدم هذه الأداة مباشرة عند أول طلب إضافة؛ اسأل أولًا هل يريد المستخدم فتح شاشة الإضافة أم الإضافة من الدردشة، ورجح فتح الشاشة لأنه أسرع. إذا اختار الدردشة فاجمع البيانات سؤالًا سؤالًا، واطلب المرفقات من الدردشة عند الحاجة بحد أقصى 3 ملفات.',
      {
        'clientType': {
          'type': 'string',
          'description': 'نوع العميل: tenant/company/serviceProvider',
          'required': true,
        },
        'fullName': {
          'type': 'string',
          'description': 'الاسم الكامل. مطلوب للمستأجر ومقدم الخدمة.',
        },
        'nationalId': {
          'type': 'string',
          'description': 'رقم الهوية. مطلوب للمستأجر واختياري لمقدم الخدمة.',
        },
        'phone': {
          'type': 'string',
          'description': 'رقم الجوال. مطلوب للمستأجر ومقدم الخدمة.',
        },
        'email': {'type': 'string', 'description': 'البريد الإلكتروني'},
        'nationality': {'type': 'string', 'description': 'الجنسية'},
        'companyName': {
          'type': 'string',
          'description': 'اسم الشركة. مطلوب إذا كان النوع company.',
        },
        'companyCommercialRegister': {
          'type': 'string',
          'description': 'رقم السجل التجاري. مطلوب إذا كان النوع company.',
        },
        'companyTaxNumber': {
          'type': 'string',
          'description': 'الرقم الضريبي. مطلوب إذا كان النوع company.',
        },
        'companyRepresentativeName': {
          'type': 'string',
          'description': 'اسم ممثل الشركة. مطلوب إذا كان النوع company.',
        },
        'companyRepresentativePhone': {
          'type': 'string',
          'description': 'رقم جوال ممثل الشركة. مطلوب إذا كان النوع company.',
        },
        'serviceSpecialization': {
          'type': 'string',
          'description': 'التخصص/الخدمة. مطلوب إذا كان النوع serviceProvider.',
        },
        'attachmentPaths': {
          'type': 'array',
          'description': 'مسارات المرفقات إذا كانت متاحة.',
          'items': {
            'type': 'string',
          },
        },
      },
    ),
    _fn(
      'archive_tenant',
      'أرشفة مستأجر (إخفاؤه من القوائم)',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستأجر أو رقم هويته',
          'required': true,
        },
      },
    ),
    _fn(
      'unarchive_tenant',
      'إلغاء أرشفة مستأجر (إعادته للقوائم)',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستأجر أو رقم هويته',
          'required': true,
        },
      },
    ),
    _fn(
      'blacklist_tenant',
      'إضافة مستأجر للقائمة السوداء',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستأجر أو رقم هويته',
          'required': true,
        },
        'reason': {
          'type': 'string',
          'description': 'سبب الإضافة للقائمة السوداء',
          'required': true,
        },
      },
    ),
    _fn(
      'unblacklist_tenant',
      'إزالة مستأجر من القائمة السوداء',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستأجر أو رقم هويته',
          'required': true,
        },
      },
    ),

    // --- عقارات ---
    _fn(
      'add_property',
      'إضافة عقار جديد مع الالتزام بقيود شاشة العقارات والوثائق الإلزامية. لا تستخدم هذه الأداة مباشرة عند أول طلب إضافة؛ اسأل أولًا هل يريد المستخدم فتح شاشة الإضافة أم الإضافة من الدردشة، ورجح فتح الشاشة لأنه أسرع. إذا اختار الدردشة فاجمع البيانات سؤالًا سؤالًا، واطلب المرفقات من الدردشة عند الحاجة بحد أقصى 3 ملفات.',
      {
        'name': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'type': {
          'type': 'string',
          'description': 'نوع العقار: apartment/villa/building/land/office/shop/warehouse',
          'required': true,
        },
        'address': {
          'type': 'string',
          'description': 'العنوان',
          'required': true,
        },
        'rentalMode': {
          'type': 'string',
          'description':
              'نمط تأجير العمارة فقط: wholeBuilding/perUnit',
        },
        'totalUnits': {
          'type': 'integer',
          'description':
              'عدد الوحدات إذا كانت العمارة بنمط perUnit',
        },
        'floors': {'type': 'integer', 'description': 'عدد الأدوار'},
        'rooms': {'type': 'integer', 'description': 'عدد الغرف'},
        'area': {'type': 'number', 'description': 'المساحة بالمتر المربع'},
        'price': {'type': 'number', 'description': 'السعر'},
        'baths': {'type': 'integer', 'description': 'عدد الحمامات'},
        'halls': {'type': 'integer', 'description': 'عدد الصالات'},
        'apartmentFloor': {
          'type': 'integer',
          'description': 'رقم الدور للشقة عند الحاجة',
        },
        'furnished': {
          'type': 'boolean',
          'description': 'هل العقار مفروش؟ مطلوب للشقة والفيلا',
        },
        'description': {'type': 'string', 'description': 'وصف إضافي'},
        'documentType': {
          'type': 'string',
          'description': 'نوع وثيقة العقار',
        },
        'documentNumber': {
          'type': 'string',
          'description': 'رقم وثيقة العقار',
        },
        'documentDate': {
          'type': 'string',
          'description': 'تاريخ الوثيقة (YYYY-MM-DD)',
        },
        'attachmentPaths': {
          'type': 'array',
          'description': 'مسارات مرفقات وثيقة العقار',
          'items': {'type': 'string'},
        },
      },
    ),
    _fn(
      'edit_property',
      'تعديل بيانات عقار موجود مع احترام قيود النوع والوحدات والوثائق',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العقار للبحث',
          'required': true,
        },
        'name': {'type': 'string', 'description': 'الاسم الجديد'},
        'type': {
          'type': 'string',
          'description': 'نوع العقار الجديد إن لزم',
        },
        'address': {'type': 'string', 'description': 'العنوان الجديد'},
        'rentalMode': {
          'type': 'string',
          'description': 'wholeBuilding/perUnit',
        },
        'totalUnits': {'type': 'integer', 'description': 'عدد الوحدات'},
        'floors': {'type': 'integer', 'description': 'عدد الأدوار'},
        'rooms': {'type': 'integer', 'description': 'عدد الغرف'},
        'area': {'type': 'number', 'description': 'المساحة'},
        'price': {'type': 'number', 'description': 'السعر'},
        'baths': {'type': 'integer', 'description': 'عدد الحمامات'},
        'halls': {'type': 'integer', 'description': 'عدد الصالات'},
        'apartmentFloor': {'type': 'integer', 'description': 'رقم الدور'},
        'furnished': {'type': 'boolean', 'description': 'حالة المفروشات'},
        'description': {'type': 'string', 'description': 'الوصف الجديد'},
        'documentType': {'type': 'string', 'description': 'نوع الوثيقة'},
        'documentNumber': {'type': 'string', 'description': 'رقم الوثيقة'},
        'documentDate': {
          'type': 'string',
          'description': 'تاريخ الوثيقة (YYYY-MM-DD)',
        },
        'attachmentPaths': {
          'type': 'array',
          'description': 'مسارات مرفقات الوثيقة',
          'items': {'type': 'string'},
        },
      },
    ),
    _fn(
      'archive_property',
      'أرشفة عقار (إخفاؤه من القوائم)',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
      },
    ),
    _fn(
      'unarchive_property',
      'إلغاء أرشفة عقار',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
      },
    ),

    // --- عقود ---
    _fn(
      'create_contract',
      'إنشاء عقد إيجار جديد مع الالتزام بقيود العميل والعقار ومدة العقد ودورة السداد. لا تستخدم هذه الأداة مباشرة عند أول طلب إنشاء عقد؛ اسأل أولًا هل يريد المستخدم فتح شاشة الإضافة أم الإضافة من الدردشة، ورجح فتح الشاشة لأنه أسرع. إذا اختار الدردشة فاجمع البيانات سؤالًا سؤالًا، ويمكن رفع المرفقات من الدردشة عند الحاجة بحد أقصى 3 ملفات. في العقد اليومي يمكن الاستفادة من ساعة الخروج المحفوظة في الإعدادات، وإذا كانت خدمات العقار المطلوبة غير مكتملة فسيظهر أن إكمال العملية من الشاشة أفضل.',
      {
        'tenantName': {
          'type': 'string',
          'description': 'اسم المستأجر',
          'required': true,
        },
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'startDate': {
          'type': 'string',
          'description': 'تاريخ البداية (YYYY-MM-DD)',
          'required': true,
        },
        'endDate': {
          'type': 'string',
          'description': 'تاريخ النهاية (YYYY-MM-DD)',
          'required': true,
        },
        'rentAmount': {
          'type': 'number',
          'description': 'مبلغ الإيجار لكل دورة دفع',
          'required': true,
        },
        'totalAmount': {
          'type': 'number',
          'description': 'إجمالي مبلغ العقد',
          'required': true,
        },
        'paymentCycle': {
          'type': 'string',
          'description': 'دورة الدفع: monthly/quarterly/semiAnnual/annual',
        },
        'term': {
          'type': 'string',
          'description': 'مدة العقد: daily/monthly/quarterly/semiAnnual/annual',
        },
        'termYears': {
          'type': 'integer',
          'description': 'عدد سنوات مدة العقد إذا كانت سنوية',
        },
        'paymentCycleYears': {
          'type': 'integer',
          'description': 'عدد سنوات دورة السداد إذا كانت سنوية',
        },
        'advanceMode': {
          'type': 'string',
          'description': 'نوع الدفعة المقدمة: none/deductFromTotal/coverMonths',
        },
        'advancePaid': {
          'type': 'number',
          'description': 'مبلغ الدفعة المقدمة',
        },
        'dailyCheckoutHour': {
          'type': 'integer',
          'description': 'ساعة الخروج في العقد اليومي من 0 إلى 23',
        },
        'ejarContractNo': {
          'type': 'string',
          'description': 'رقم عقد إيجار إن وجد',
        },
        'notes': {'type': 'string', 'description': 'ملاحظات'},
        'attachmentPaths': {
          'type': 'array',
          'description': 'مرفقات العقد',
          'items': {'type': 'string'},
        },
      },
    ),
    _fn(
      'edit_contract',
      'تعديل شروط عقد موجود ضمن القيود الفعلية للعقد',
      {
        'contractSerialNo': {
          'type': 'string',
          'description': 'رقم العقد التسلسلي',
          'required': true,
        },
        'rentAmount': {'type': 'number', 'description': 'مبلغ الإيجار الجديد'},
        'totalAmount': {'type': 'number', 'description': 'إجمالي العقد الجديد'},
        'notes': {'type': 'string', 'description': 'ملاحظات جديدة'},
        'ejarContractNo': {
          'type': 'string',
          'description': 'رقم عقد إيجار',
        },
        'endDate': {
          'type': 'string',
          'description': 'تاريخ نهاية العقد الجديد (YYYY-MM-DD)',
        },
        'paymentCycle': {
          'type': 'string',
          'description': 'monthly/quarterly/semiAnnual/annual',
        },
        'paymentCycleYears': {
          'type': 'integer',
          'description': 'عدد سنوات دورة السداد السنوية',
        },
        'advanceMode': {
          'type': 'string',
          'description': 'none/deductFromTotal/coverMonths',
        },
        'advancePaid': {
          'type': 'number',
          'description': 'مبلغ الدفعة المقدمة',
        },
        'dailyCheckoutHour': {
          'type': 'integer',
          'description': 'ساعة الخروج من 0 إلى 23 للعقد اليومي',
        },
      },
    ),
    _fn(
      'renew_contract',
      'تجديد عقد (إنشاء عقد جديد بناءً على عقد سابق مع تواريخ جديدة)',
      {
        'contractSerialNo': {
          'type': 'string',
          'description': 'رقم العقد الحالي',
          'required': true,
        },
        'newStartDate': {
          'type': 'string',
          'description': 'تاريخ بداية العقد الجديد (YYYY-MM-DD)',
          'required': true,
        },
        'newEndDate': {
          'type': 'string',
          'description': 'تاريخ نهاية العقد الجديد (YYYY-MM-DD)',
          'required': true,
        },
        'newRentAmount': {
          'type': 'number',
          'description':
              'مبلغ الإيجار الجديد (اختياري، يأخذ القديم إذا لم يُحدد)',
        },
        'newTotalAmount': {
          'type': 'number',
          'description': 'إجمالي العقد الجديد (اختياري)',
        },
        'notes': {'type': 'string', 'description': 'ملاحظات العقد المجدد'},
      },
    ),
    _fn(
      'terminate_contract',
      'إنهاء عقد مبكراً',
      {
        'contractSerialNo': {
          'type': 'string',
          'description': 'رقم العقد التسلسلي',
          'required': true,
        },
      },
    ),

    // --- فواتير ---
    _fn(
      'create_invoice',
      'إصدار فاتورة/سند جديد',
      {
        'contractSerialNo': {
          'type': 'string',
          'description': 'رقم العقد التسلسلي',
          'required': true,
        },
        'amount': {
          'type': 'number',
          'description': 'مبلغ الفاتورة',
          'required': true,
        },
        'dueDate': {
          'type': 'string',
          'description': 'تاريخ الاستحقاق (YYYY-MM-DD)',
          'required': true,
        },
        'note': {'type': 'string', 'description': 'ملاحظة'},
      },
    ),
    _fn(
      'record_payment',
      'تسجيل دفعة على فاتورة',
      {
        'invoiceSerialNo': {
          'type': 'string',
          'description': 'رقم الفاتورة التسلسلي',
          'required': true,
        },
        'amount': {
          'type': 'number',
          'description': 'مبلغ الدفعة',
          'required': true,
        },
      },
    ),
    _fn(
      'create_manual_voucher',
      'إنشاء سند يدوي قبض أو صرف بنفس قيود شاشة السندات اليدوية',
      {
        'kind': {
          'type': 'string',
          'description': 'نوع السند: revenue/expense',
          'required': true,
        },
        'issueDate': {
          'type': 'string',
          'description': 'تاريخ السند (YYYY-MM-DD)',
          'required': true,
        },
        'partyName': {
          'type': 'string',
          'description': 'اسم الطرف',
          'required': true,
        },
        'amount': {
          'type': 'number',
          'description': 'المبلغ',
          'required': true,
        },
        'paymentMethod': {
          'type': 'string',
          'description': 'طريقة الدفع: cash/bankTransfer/check',
          'required': true,
        },
        'title': {
          'type': 'string',
          'description': 'عنوان السند',
          'required': true,
        },
        'description': {
          'type': 'string',
          'description': 'بيان السند',
          'required': true,
        },
        'tenantName': {
          'type': 'string',
          'description': 'اسم العميل المرتبط إن وجد',
        },
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار (اختياري)',
        },
        'attachmentPaths': {
          'type': 'array',
          'description': 'مرفقات السند اليدوي',
          'items': {'type': 'string'},
        },
      },
    ),
    _fn(
      'add_building_unit',
      'إضافة وحدة داخل عمارة بنمط تأجير الوحدات',
      {
        'buildingName': {
          'type': 'string',
          'description': 'اسم المبنى/العمارة',
          'required': true,
        },
        'unitName': {
          'type': 'string',
          'description': 'اسم الوحدة (مثل: شقة 1، محل 3)',
          'required': true,
        },
        'rooms': {'type': 'integer', 'description': 'عدد الغرف'},
        'area': {'type': 'number', 'description': 'المساحة'},
        'price': {'type': 'number', 'description': 'السعر'},
        'baths': {'type': 'integer', 'description': 'عدد الحمامات'},
        'halls': {'type': 'integer', 'description': 'عدد الصالات'},
        'apartmentFloor': {'type': 'integer', 'description': 'رقم الدور'},
        'furnished': {'type': 'boolean', 'description': 'حالة المفروشات'},
        'description': {'type': 'string', 'description': 'وصف إضافي'},
      },
    ),
    _fn(
      'cancel_invoice',
      'إلغاء فاتورة/سند',
      {
        'invoiceSerialNo': {
          'type': 'string',
          'description': 'رقم الفاتورة التسلسلي',
          'required': true,
        },
      },
    ),

    // --- صيانة ---
    _fn(
      'create_maintenance_request',
      'إنشاء طلب صيانة أو خدمة مع الالتزام بقيود شاشة الصيانة. لا تستخدم هذه الأداة مباشرة عند أول طلب إضافة؛ اسأل أولًا هل يريد المستخدم فتح شاشة الإضافة أم الإضافة من الدردشة، ورجح فتح الشاشة لأنه أسرع. إذا اختار الدردشة فاجمع البيانات سؤالًا سؤالًا، ويمكن رفع المرفقات من الدردشة عند الحاجة بحد أقصى 3 ملفات. يدعم الإنشاء بحالات التشغيل المعتادة، وإذا أُنشىء الطلب كمكتمل فسيحاول توليد السند المرتبط مثل الشاشة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'title': {
          'type': 'string',
          'description': 'عنوان الطلب',
          'required': true,
        },
        'description': {'type': 'string', 'description': 'وصف المشكلة'},
        'priority': {
          'type': 'string',
          'description': 'الأولوية: low/medium/high/urgent',
        },
        'status': {
          'type': 'string',
          'description': 'اختياري: open/inProgress/completed',
        },
        'requestType': {
          'type': 'string',
          'description': 'نوع الخدمة (مثل: سباكة، كهرباء، تنظيف)',
        },
        'scheduledDate': {
          'type': 'string',
          'description': 'تاريخ الجدولة (YYYY-MM-DD)',
        },
        'executionDeadline': {
          'type': 'string',
          'description': 'آخر موعد للتنفيذ (YYYY-MM-DD)',
        },
        'cost': {'type': 'number', 'description': 'التكلفة المتوقعة'},
        'provider': {
          'type': 'string',
          'description': 'اسم مقدم الخدمة من قائمة مقدمي الخدمة',
        },
        'attachmentPaths': {
          'type': 'array',
          'description': 'مرفقات طلب الصيانة',
          'items': {'type': 'string'},
        },
      },
    ),
    _fn(
      'update_maintenance_status',
      'تحديث حالة طلب صيانة مع إمكانية تحديث التكلفة أو مقدم الخدمة أو المواعيد',
      {
        'query': {
          'type': 'string',
          'description': 'عنوان الطلب أو رقمه التسلسلي',
          'required': true,
        },
        'status': {
          'type': 'string',
          'description': 'الحالة الجديدة: open/inProgress/completed/canceled',
          'required': true,
        },
        'cost': {
          'type': 'number',
          'description': 'التكلفة (عند الإكمال)',
        },
        'provider': {
          'type': 'string',
          'description': 'اسم مقدم الخدمة',
        },
        'scheduledDate': {
          'type': 'string',
          'description': 'تاريخ الجدولة (YYYY-MM-DD)',
        },
        'executionDeadline': {
          'type': 'string',
          'description': 'آخر موعد للتنفيذ (YYYY-MM-DD)',
        },
      },
    ),

    // --- خدمات دورية ---
    _fn(
      'create_periodic_service',
      'إنشاء إعداد خدمة عقار وفق منطق شاشة خدمات العقار. يدعم النظافة والمصعد والإنترنت والمياه والكهرباء، ويعيد requiresScreenCompletion عندما تكون العملية من التدفقات المرئية الخاصة بالشاشة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'serviceType': {
          'type': 'string',
          'description': 'نوع الخدمة: cleaning/elevator/internet/water/electricity',
          'required': true,
        },
        'provider': {
          'type': 'string',
          'description': 'اختياري: اسم مقدم الخدمة للخدمات التي يدفعها المالك',
        },
        'cost': {
          'type': 'number',
          'description': 'اختياري: تكلفة الخدمة أو المبلغ الافتراضي',
        },
        'billingMode': {
          'type': 'string',
          'description':
              'اختياري: internet = owner/separate، water أو electricity = shared/separate',
        },
        'sharedMethod': {
          'type': 'string',
          'description': 'اختياري للمياه المشتركة فقط: percent أو fixed',
        },
        'meterNumber': {
          'type': 'string',
          'description': 'اختياري للمياه أو الكهرباء المنفصلة: رقم العداد',
        },
        'sharePercent': {
          'type': 'number',
          'description': 'اختياري للمياه أو الكهرباء المشتركة بالنسبة: النسبة المطلوبة',
        },
        'totalAmount': {
          'type': 'number',
          'description': 'اختياري للمياه المشتركة الثابتة: المبلغ الكلي',
        },
        'nextDueDate': {
          'type': 'string',
          'description': 'اختياري: تاريخ الدورة القادمة أو الاستحقاق القادم (YYYY-MM-DD)',
        },
        'scheduledDate': {
          'type': 'string',
          'description': 'اختياري كبديل عن nextDueDate (YYYY-MM-DD)',
        },
        'recurrenceMonths': {
          'type': 'integer',
          'description': 'اختياري للخدمات المدارة من المالك: 0 أو 1 أو 2 أو 3 أو 6 أو 12',
        },
        'remindBeforeDays': {
          'type': 'integer',
          'description': 'اختياري: عدد أيام التذكير قبل الموعد من 0 إلى 3',
        },
        'executeNow': {
          'type': 'boolean',
          'description': 'اختياري: إذا كانت العملية تتطلب تنفيذًا مرئيًا فسيعود الرد بطلب إكمالها من الشاشة',
        },
      },
    ),
    _fn(
      'update_periodic_service',
      'تحديث إعدادات خدمة عقار موجودة وفق نفس منطق شاشة خدمات العقار، مع إرجاع requiresScreenCompletion للتدفقات التي تبقى داخل الشاشة.',
      {
        'propertyName': {
          'type': 'string',
          'description': 'اسم العقار',
          'required': true,
        },
        'serviceType': {
          'type': 'string',
          'description': 'نوع الخدمة: cleaning/elevator/internet/water/electricity',
          'required': true,
        },
        'provider': {
          'type': 'string',
          'description': 'اختياري: مقدم الخدمة الجديد للخدمات التي يدفعها المالك',
        },
        'cost': {
          'type': 'number',
          'description': 'اختياري: التكلفة أو المبلغ الافتراضي الجديد',
        },
        'billingMode': {
          'type': 'string',
          'description':
              'اختياري: internet = owner/separate، water أو electricity = shared/separate',
        },
        'sharedMethod': {
          'type': 'string',
          'description': 'اختياري للمياه المشتركة فقط: percent أو fixed',
        },
        'meterNumber': {
          'type': 'string',
          'description': 'اختياري للمياه أو الكهرباء المنفصلة: رقم العداد',
        },
        'sharePercent': {
          'type': 'number',
          'description': 'اختياري للمياه أو الكهرباء المشتركة بالنسبة: النسبة المطلوبة',
        },
        'totalAmount': {
          'type': 'number',
          'description': 'اختياري للمياه المشتركة الثابتة: المبلغ الكلي',
        },
        'nextDueDate': {
          'type': 'string',
          'description': 'اختياري: تاريخ الدورة القادمة أو الاستحقاق القادم (YYYY-MM-DD)',
        },
        'scheduledDate': {
          'type': 'string',
          'description': 'اختياري كبديل عن nextDueDate (YYYY-MM-DD)',
        },
        'recurrenceMonths': {
          'type': 'integer',
          'description': 'اختياري للخدمات المدارة من المالك: 0 أو 1 أو 2 أو 3 أو 6 أو 12',
        },
        'remindBeforeDays': {
          'type': 'integer',
          'description': 'اختياري: عدد أيام التذكير قبل الموعد من 0 إلى 3',
        },
        'executeNow': {
          'type': 'boolean',
          'description': 'اختياري: إذا كانت العملية تتطلب تنفيذًا مرئيًا فسيعود الرد بطلب إكمالها من الشاشة',
        },
      },
    ),
    _fn(
      'update_settings',
      'تعديل الإعدادات الفعلية داخل user_prefs مثل اللغة ونظام التاريخ وأيام التنبيهات الأساسية والسنوية حسب السنوات وساعة الإرسال اليومية وقوالب الرسائل.',
      {
        'language': {
          'type': 'string',
          'description': 'اختياري: ar أو en أو العربية أو الإنجليزية',
        },
        'dateSystem': {
          'type': 'string',
          'description': 'اختياري: gregorian أو hijri أو ميلادي أو هجري',
        },
        'monthlyDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 7',
        },
        'quarterlyDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 15',
        },
        'semiAnnualDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 30',
        },
        'annualDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 45',
        },
        'annualYearsDays': {
          'type': 'object',
          'description': 'اختياري: خريطة السنوات من 1 إلى 10 لقيم تنبيه السنوات السنوية',
        },
        'contractMonthlyDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 7',
        },
        'contractQuarterlyDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 15',
        },
        'contractSemiAnnualDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 30',
        },
        'contractAnnualDays': {
          'type': 'integer',
          'description': 'اختياري: من 1 إلى 45',
        },
        'contractAnnualYearsDays': {
          'type': 'object',
          'description': 'اختياري: خريطة السنوات من 1 إلى 10 لقيم تنبيه العقود السنوية',
        },
        'dailyContractEndHour': {
          'type': 'integer',
          'description': 'اختياري: ساعة الإرسال اليومية من 0 إلى 23',
        },
        'paymentTemplatesBefore': {
          'type': 'object',
          'description':
              'اختياري: قوالب تنبيه الدفعات قبل الاستحقاق بصيغة monthly/quarterly/semiAnnual/annual',
        },
        'paymentTemplatesOn': {
          'type': 'object',
          'description':
              'اختياري: قوالب تنبيه الدفعات يوم الاستحقاق بصيغة monthly/quarterly/semiAnnual/annual',
        },
        'contractTemplatesBefore': {
          'type': 'object',
          'description':
              'اختياري: قوالب تنبيه العقود قبل الانتهاء بصيغة monthly/quarterly/semiAnnual/annual',
        },
      },
    ),
    _fn(
      'mark_notification_read',
      'تعليم إشعار محدد كمقروء/تمت قراءته باستخدام notificationRef القادم من get_notifications.',
      {
        'notificationRef': {
          'type': 'string',
          'description': 'مرجع الإشعار القادم من get_notifications',
          'required': true,
        },
      },
    ),
    _fn(
      'assign_property_owner_from_reports',
      'ربط مالك بعقار من منطق شاشة التقارير. يجب تحديد العقار والمالك بشكل واضح.',
      {
        'propertyQuery': {
          'type': 'string',
          'description': 'اسم العقار أو معرّفه',
          'required': true,
        },
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
      },
    ),
    _fn(
      'record_office_report_voucher',
      'تسجيل مصروف مكتب أو إيراد عمولة يدوي من شاشة التقارير. إيراد العمولة اليدوي مسموح فقط إذا كانت العمولة مبلغًا ثابتًا.',
      {
        'isExpense': {
          'type': 'boolean',
          'description': 'true لمصروف مكتب و false لإيراد عمولة',
          'required': true,
        },
        'amount': {
          'type': 'number',
          'description': 'مبلغ العملية',
          'required': true,
        },
        'transactionDate': {
          'type': 'string',
          'description': 'تاريخ العملية بصيغة YYYY-MM-DD',
          'required': true,
        },
        'note': {
          'type': 'string',
          'description': 'اختياري: ملاحظة مختصرة للعملية',
        },
      },
    ),
    _fn(
      'record_office_withdrawal',
      'تنفيذ سحب أو تحويل من رصيد المكتب الجاهز وفق فترة التقرير المحددة.',
      {
        'amount': {
          'type': 'number',
          'description': 'مبلغ السحب أو التحويل',
          'required': true,
        },
        'transferDate': {
          'type': 'string',
          'description': 'تاريخ التحويل بصيغة YYYY-MM-DD',
          'required': true,
        },
        'note': {
          'type': 'string',
          'description': 'اختياري: ملاحظة مختصرة للتحويل',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية فترة التقرير',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية فترة التقرير',
        },
      },
    ),
    _fn(
      'set_report_commission_rule',
      'تعديل قاعدة عمولة المكتب في شاشة التقارير.',
      {
        'mode': {
          'type': 'string',
          'description': 'نوع العمولة: none/fixed/percent',
          'required': true,
        },
        'value': {
          'type': 'number',
          'description': 'قيمة العمولة. تُستخدم فقط مع النسبة المئوية، وفي غير ذلك تكون 0.',
        },
      },
    ),
    _fn(
      'record_owner_payout',
      'تنفيذ تحويل رصيد لمالك حسب رصيد التقرير الجاهز للتحويل ويمكن تقييده بعقار أو فترة.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'amount': {
          'type': 'number',
          'description': 'مبلغ التحويل',
          'required': true,
        },
        'transferDate': {
          'type': 'string',
          'description': 'تاريخ التحويل بصيغة YYYY-MM-DD',
          'required': true,
        },
        'note': {
          'type': 'string',
          'description': 'اختياري: ملاحظة مختصرة للتحويل',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية فترة التقرير',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية فترة التقرير',
        },
      },
    ),
    _fn(
      'record_owner_adjustment',
      'تسجيل خصم أو تسوية أو إضافة على حساب مالك حسب منطق شاشة التقارير.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'propertyQuery': {
          'type': 'string',
          'description': 'اختياري: اسم العقار أو معرّفه',
        },
        'category': {
          'type': 'string',
          'description': 'نوع الخصم أو التسوية حسب الفئات المعتمدة في شاشة التقارير',
          'required': true,
        },
        'amount': {
          'type': 'number',
          'description': 'مبلغ الخصم أو التسوية',
          'required': true,
        },
        'adjustmentDate': {
          'type': 'string',
          'description': 'تاريخ العملية بصيغة YYYY-MM-DD',
          'required': true,
        },
        'note': {
          'type': 'string',
          'description': 'اختياري: ملاحظة مختصرة',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية فترة التقرير',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية فترة التقرير',
        },
      },
    ),
    _fn(
      'add_owner_bank_account',
      'إضافة حساب بنكي جديد لمالك داخل شاشة التقارير.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'bankName': {
          'type': 'string',
          'description': 'اسم البنك',
          'required': true,
        },
        'accountNumber': {
          'type': 'string',
          'description': 'رقم الحساب',
          'required': true,
        },
        'iban': {
          'type': 'string',
          'description': 'اختياري: رقم الآيبان',
        },
      },
    ),
    _fn(
      'edit_owner_bank_account',
      'تعديل حساب بنكي محفوظ لمالك داخل شاشة التقارير.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'accountQuery': {
          'type': 'string',
          'description': 'اسم البنك أو رقم الحساب أو معرّف الحساب البنكي',
          'required': true,
        },
        'bankName': {
          'type': 'string',
          'description': 'اسم البنك الجديد',
          'required': true,
        },
        'accountNumber': {
          'type': 'string',
          'description': 'رقم الحساب الجديد',
          'required': true,
        },
        'iban': {
          'type': 'string',
          'description': 'اختياري: رقم الآيبان الجديد',
        },
      },
    ),
    _fn(
      'delete_owner_bank_account',
      'حذف حساب بنكي محفوظ لمالك بعد التأكيد الواضح على الحذف.',
      {
        'ownerQuery': {
          'type': 'string',
          'description': 'اسم المالك أو معرّفه',
          'required': true,
        },
        'accountQuery': {
          'type': 'string',
          'description': 'اسم البنك أو رقم الحساب أو معرّف الحساب البنكي',
          'required': true,
        },
      },
    ),
  ];

  // ================================================================
  //  أدوات التنقل
  // ================================================================
  static List<Map<String, dynamic>> _navTools({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final keys = AppArchitectureRegistry.chatNavigationKeysDescription(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
    final description = keys.isEmpty
        ? 'اسم الشاشة المراد فتحها'
        : 'اسم الشاشة: $keys';
    final tools = <Map<String, dynamic>>[
      _fn(
        'navigate_to_screen',
        'فتح شاشة مدعومة في التطبيق وفق المرجع المعماري الحالي',
        {
          'screen': {
            'type': 'string',
            'description': description,
            'required': true,
          },
        },
      ),
    ];

    if (canWrite) {
      tools.add(
        _fn(
          'open_tenant_entry',
          'فتح شاشة إضافة عميل. استخدمها عندما يختار المستخدم فتح الشاشة بدل الإضافة من الدردشة، وهذا هو الخيار المفضل والأسرع عادة.',
          {},
        ),
      );
      tools.add(
        _fn(
          'open_property_entry',
          'فتح شاشة إضافة عقار. استخدمها عندما يختار المستخدم فتح الشاشة بدل الإضافة من الدردشة، وهذا هو الخيار المفضل والأسرع عادة.',
          {},
        ),
      );
      tools.add(
        _fn(
          'open_contract_entry',
          'فتح شاشة إضافة عقد مع تعبئة أولية اختيارية للعقار أو العميل إذا كانت البيانات معروفة مسبقًا.',
          {
            'propertyName': {
              'type': 'string',
              'description': 'اختياري: اسم العقار لملء الشاشة مسبقًا',
            },
            'tenantName': {
              'type': 'string',
              'description': 'اختياري: اسم العميل لملء الشاشة مسبقًا',
            },
          },
        ),
      );
      tools.add(
        _fn(
          'open_maintenance_entry',
          'فتح شاشة إضافة صيانة مع تعبئة أولية اختيارية مثل العقار والعنوان والوصف والتواريخ والتكلفة ومقدم الخدمة.',
          {
            'propertyName': {
              'type': 'string',
              'description': 'اختياري: اسم العقار لملء الشاشة مسبقًا',
            },
            'title': {
              'type': 'string',
              'description': 'اختياري: عنوان الطلب',
            },
            'description': {
              'type': 'string',
              'description': 'اختياري: وصف الطلب',
            },
            'scheduledDate': {
              'type': 'string',
              'description': 'اختياري: موعد بدء التنفيذ بصيغة YYYY-MM-DD',
            },
            'executionDeadline': {
              'type': 'string',
              'description': 'اختياري: آخر موعد للتنفيذ بصيغة YYYY-MM-DD',
            },
            'cost': {
              'type': 'number',
              'description': 'اختياري: التكلفة الأولية',
            },
            'provider': {
              'type': 'string',
              'description': 'اختياري: اسم مقدم الخدمة',
            },
          },
        ),
      );
    }

    tools.add(
      _fn(
        'open_contract_invoice_history',
        'فتح شاشة سجل سندات العقد لعقد محدد بعد تحديد العقد المقصود.',
        {
          'query': {
            'type': 'string',
            'description': 'رقم العقد أو اسم العميل أو اسم العقار',
            'required': true,
          },
        },
      ),
    );

    return tools;
  }

  // ================================================================
  //  أدوات المكتب - قراءة
  // ================================================================
  static final _officeReadTools = <Map<String, dynamic>>[
    _fn(
      'get_office_dashboard',
      'جلب ملخص لوحة المكتب الفعلية، ويشمل بالإضافة إلى ملخص العملاء والمستخدمين والتنبيهات: إجمالي العقارات الرئيسية لكل العملاء المتاحين محليًا، عدد العمائر، الوحدات المضافة والمشغولة والمتاحة، وإجمالي العقود وحالاتها والمتبقي فيها.',
      {},
    ),
    _fn('get_office_clients_list', 'قائمة عملاء المكتب', {}),
    _fn(
      'get_office_client_details',
      'تفاصيل عميل مكتب معين مثل الاسم والبريد والجوال والملاحظات وحالة الاشتراك، ومعها ملخص مساحة عمله التشغيلية إن كانت متاحة: عقاراته الرئيسية، عمائره، وحداته، عقوده، ومعاينة عقاراته وعقوده.',
      {
        'clientName': {
          'type': 'string',
          'description': 'اسم العميل',
          'required': true,
        },
      },
    ),
    _fn(
      'get_office_client_access',
      'قراءة حالة دخول عميل المكتب وهل هو موقوف أو مسموح له، مع بيان إن كان السجل محليًا معلّقًا أو محفوظًا فعليًا.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
      },
    ),
    _fn(
      'get_office_client_subscription',
      'قراءة حالة اشتراك عميل المكتب الحالية: هل الاشتراك مفعل، وما تاريخ البداية والنهاية والسعر والتنبيه، مع بيان إن كان التفعيل ممكنًا من الدردشة.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
      },
    ),
    _fn(
      'get_office_summary',
      'ملخص عملاء المكتب الحالي: إجمالي العملاء، النشطون، المحظورون، ومن لديهم اشتراك.',
      {},
    ),
    _fn('get_office_users_list', 'قائمة مستخدمي المكتب الحاليين مع الصلاحية وحالة الدخول.', {}),
    _fn(
      'get_office_user_details',
      'تفاصيل مستخدم مكتب محدد، مثل الاسم والبريد والصلاحية وحالة الحظر وإمكانية توليد رابط إعادة التعيين.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
      },
    ),
    _fn(
      'get_activity_log',
      'قراءة سجل نشاط المكتب مع الفلاتر الزمنية وفلاتر نوع العملية والعنصر والمستخدم. إذا كانت الصلاحية محدودة فقد يُفرض onlyMine تلقائيًا.',
      {
        'query': {
          'type': 'string',
          'description': 'اختياري: بحث عام داخل الوصف أو العنصر أو المنفذ',
        },
        'actorQuery': {
          'type': 'string',
          'description': 'اختياري: اسم المستخدم المنفذ أو بريده أو uid',
        },
        'actionType': {
          'type': 'string',
          'description':
              'اختياري: create أو update أو delete أو archive أو unarchive أو terminate أو status_change أو login أو logout أو payment_add أو payment_update أو payment_delete أو password_reset_link',
        },
        'entityType': {
          'type': 'string',
          'description':
              'اختياري: property أو tenant أو contract أو invoice أو maintenance أو office_user أو office_client',
        },
        'quickDate': {
          'type': 'string',
          'description': 'اختياري: all أو today أو week أو month',
        },
        'fromDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لبداية الفترة',
        },
        'toDate': {
          'type': 'string',
          'description': 'اختياري بصيغة YYYY-MM-DD لنهاية الفترة',
        },
        'onlyMine': {
          'type': 'boolean',
          'description': 'اختياري: true لإرجاع العمليات المنفذة بواسطة الحساب الحالي فقط',
        },
        'limit': {
          'type': 'integer',
          'description': 'اختياري: عدد النتائج المطلوبة',
        },
      },
    ),
  ];

  // ================================================================
  //  أدوات المكتب - كتابة
  // ================================================================
  static final _officeWriteTools = <Map<String, dynamic>>[
    _fn(
      'add_office_client',
      'إضافة عميل جديد للمكتب مع احترام قيود الاسم والبريد والجوال وحدود الباقة',
      {
        'name': {
          'type': 'string',
          'description': 'اسم العميل',
          'required': true,
        },
        'email': {
          'type': 'string',
          'description': 'البريد الإلكتروني',
          'required': true,
        },
        'phone': {'type': 'string', 'description': 'رقم الجوال'},
        'notes': {'type': 'string', 'description': 'ملاحظات العميل'},
      },
    ),
    _fn(
      'edit_office_client',
      'تعديل عميل مكتب موجود. التعديل المدعوم من الدردشة يشمل الاسم والجوال والملاحظات فقط، أما البريد الإلكتروني فيبقى كما هو.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
        'name': {'type': 'string', 'description': 'الاسم الجديد'},
        'phone': {
          'type': 'string',
          'description': 'الجوال الجديد أو اتركه فارغًا عند الرغبة بمسحه حسب منطق الشاشة',
        },
        'notes': {'type': 'string', 'description': 'الملاحظات الجديدة'},
      },
    ),
    _fn(
      'delete_office_client',
      'حذف عميل مكتب موجود أو حذف عميل محلي معلّق قبل رفعه. هذه العملية تخضع لتأكيد التنفيذ قبل الإرسال.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
      },
    ),
    _fn(
      'set_office_client_access',
      'إيقاف أو سماح دخول عميل المكتب. هذه العملية متاحة فقط للعميل المحفوظ فعليًا والذي يملك حساب دخول جاهز، وليست للسجل المحلي المعلّق.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
        'allowAccess': {
          'type': 'boolean',
          'description': 'true للسماح بالدخول و false لإيقاف الدخول',
          'required': true,
        },
      },
    ),
    _fn(
      'set_office_client_subscription',
      'تفعيل أو تجديد اشتراك عميل المكتب الشهري بنفس منطق شاشة المكتب. العملية متاحة فقط للعميل المحفوظ فعليًا، وتتطلب سعرًا أكبر من صفر، وموعد تنبيه من 1 إلى 3 أيام، وقد تحتاج اتصالًا فعليًا بالخدمة.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
        'price': {
          'type': 'number',
          'description': 'سعر الاشتراك الشهري ويجب أن يكون أكبر من صفر',
          'required': true,
        },
        'reminderDays': {
          'type': 'integer',
          'description': 'اختياري: 1 أو 2 أو 3 أيام قبل انتهاء الاشتراك',
        },
        'startDate': {
          'type': 'string',
          'description':
              'اختياري بصيغة YYYY-MM-DD عند التفعيل الأول فقط. إذا كان للعميل اشتراك سابق فسيحدد النظام البداية تلقائيًا حسب منطق الشاشة.',
        },
      },
    ),
    _fn(
      'generate_office_client_reset_link',
      'توليد رابط إعادة تعيين كلمة المرور لعميل مكتب محفوظ فعليًا ويملك حساب دخول جاهز. يحتاج اتصالًا فعليًا بالخدمة.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم العميل أو بريده الإلكتروني أو clientUid',
          'required': true,
        },
      },
    ),
    _fn(
      'add_office_user',
      'إضافة مستخدم مكتب جديد مع الاسم والبريد الإلكتروني والصلاحية، مع احترام حدود الباقة وقيود الشاشة.',
      {
        'name': {
          'type': 'string',
          'description': 'اسم المستخدم',
          'required': true,
        },
        'email': {
          'type': 'string',
          'description': 'البريد الإلكتروني',
          'required': true,
        },
        'permission': {
          'type': 'string',
          'description': 'اختياري: full أو view. الافتراضي view',
        },
      },
    ),
    _fn(
      'edit_office_user',
      'تعديل مستخدم مكتب موجود. التعديل المدعوم من الشات يشمل الاسم والصلاحية فقط، أما البريد فيبقى كما هو.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
        'name': {
          'type': 'string',
          'description': 'الاسم الجديد',
        },
        'permission': {
          'type': 'string',
          'description': 'اختياري: full أو view',
        },
      },
    ),
    _fn(
      'set_office_user_permission',
      'تعديل صلاحية مستخدم مكتب بشكل مباشر بين full و view.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
        'permission': {
          'type': 'string',
          'description': 'القيمة المطلوبة: full أو view',
          'required': true,
        },
      },
    ),
    _fn(
      'set_office_user_access',
      'إيقاف أو السماح بدخول مستخدم المكتب عبر تحديث حالة الحظر.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
        'allowAccess': {
          'type': 'boolean',
          'description': 'true للسماح بالدخول و false لإيقاف الدخول',
          'required': true,
        },
      },
    ),
    _fn(
      'delete_office_user',
      'حذف مستخدم مكتب محفوظ فعليًا بعد التأكيد الواضح على الحذف.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
      },
    ),
    _fn(
      'generate_office_user_reset_link',
      'توليد رابط إعادة تعيين كلمة المرور لمستخدم مكتب محفوظ فعليًا ويملك بريدًا جاهزًا.',
      {
        'query': {
          'type': 'string',
          'description': 'اسم المستخدم أو بريده الإلكتروني أو uid',
          'required': true,
        },
      },
    ),
  ];
}
