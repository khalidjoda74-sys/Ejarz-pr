class AppArchitectureRegistry {
  AppArchitectureRegistry._();

  static Map<String, dynamic> _screen({
    required String key,
    required String title,
    required String audience,
    required String entryKind,
    required String routeAvailability,
    required String chatCoverage,
    required bool chatReadSupported,
    required bool chatWriteSupported,
    required bool chatNavigationEnabled,
    required bool appRouteRegistered,
    String? route,
    List<String> aliases = const <String>[],
    List<String> requiredNavigationArgs = const <String>[],
    List<String> primaryActions = const <String>[],
    List<String> relatedModules = const <String>[],
    List<String> notes = const <String>[],
    String description = '',
    bool requiresOfficeWideRead = false,
  }) {
    return <String, dynamic>{
      'key': key,
      'title': title,
      'audience': audience,
      'entryKind': entryKind,
      'routeAvailability': routeAvailability,
      'chatCoverage': chatCoverage,
      'chatReadSupported': chatReadSupported,
      'chatWriteSupported': chatWriteSupported,
      'chatNavigationEnabled': chatNavigationEnabled,
      'appRouteRegistered': appRouteRegistered,
      'requiresOfficeWideRead': requiresOfficeWideRead,
      'description': description,
      'route': route,
      'aliases': aliases,
      'requiredNavigationArgs': requiredNavigationArgs,
      'primaryActions': primaryActions,
      'relatedModules': relatedModules,
      'notes': notes,
    };
  }

  static Map<String, dynamic> _module({
    required String key,
    required String title,
    required String audience,
    required String chatCoverage,
    required bool chatReadSupported,
    required bool chatWriteSupported,
    required List<String> screenKeys,
    required List<String> primaryActions,
    List<String> readTools = const <String>[],
    List<String> writeTools = const <String>[],
    List<String> notes = const <String>[],
    String description = '',
    bool requiresOfficeWideRead = false,
  }) {
    return <String, dynamic>{
      'key': key,
      'title': title,
      'audience': audience,
      'chatCoverage': chatCoverage,
      'chatReadSupported': chatReadSupported,
      'chatWriteSupported': chatWriteSupported,
      'requiresOfficeWideRead': requiresOfficeWideRead,
      'description': description,
      'screenKeys': screenKeys,
      'primaryActions': primaryActions,
      'readTools': readTools,
      'writeTools': writeTools,
      'notes': notes,
    };
  }

  static final List<Map<String, dynamic>> _screens = <Map<String, dynamic>>[
    _screen(
      key: 'login',
      title: 'تسجيل الدخول',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app',
      chatCoverage: 'reference_only',
      chatReadSupported: false,
      chatWriteSupported: false,
      chatNavigationEnabled: false,
      appRouteRegistered: true,
      route: '/login',
      aliases: <String>['signin', 'auth'],
      description: 'بوابة المصادقة وتحديد نوع الحساب قبل دخول التطبيق.',
      primaryActions: <String>['تسجيل الدخول', 'تحديد وضع الحساب'],
      relatedModules: <String>['security'],
      notes: <String>[
        'هذه الشاشة مرجعية داخل المخطط ولا تُفتح من الدردشة أثناء الجلسة العادية.',
      ],
    ),
    _screen(
      key: 'home',
      title: 'الرئيسية',
      audience: 'owner',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/home',
      aliases: <String>['dashboard', 'main'],
      description:
          'الشاشة الرئيسية الأساسية للحساب العادي وتعرض بطاقات الملخص والأزرار السريعة ومدخل أقرب الاستحقاقات.',
      primaryActions: <String>['ملخص سريع', 'الوصول إلى الأقسام', 'متابعة الحالة العامة'],
      relatedModules: <String>['dashboard', 'navigation'],
      notes: <String>[
        'الشات يقرأ بطاقات الرئيسية والأزرار السريعة ومدخل أقرب استحقاقات الإيجار عبر أداة مخصصة مطابقة للشاشة.',
      ],
    ),
    _screen(
      key: 'office',
      title: 'رئيسية لوحة المكتب',
      audience: 'office',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      requiresOfficeWideRead: true,
      route: '/office',
      aliases: <String>['office_dashboard', 'office_home'],
      description: 'واجهة المكتب الرئيسية وما يرتبط بها من مؤشرات وأدوات إدارية.',
      primaryActions: <String>['ملخص المكتب', 'فتح الأقسام', 'متابعة حالة المكتب'],
      relatedModules: <String>['office_dashboard', 'office_clients', 'navigation'],
      notes: <String>[
        'الشات يقرأ قشرة لوحة المكتب نفسها، وعدّاد التنبيهات، وملخص العملاء، وملخص المستخدمين، مع ربط أن جسم الشاشة الافتراضي هو عملاء المكتب.',
      ],
    ),
    _screen(
      key: 'properties',
      title: 'العقارات',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: false,
      route: '/properties',
      aliases: <String>['property', 'real_estate'],
      description: 'إدارة العقارات والوحدات ووثائق الملكية والأرشفة.',
      primaryActions: <String>['إضافة عقار', 'تعديل عقار', 'أرشفة', 'إضافة وحدة'],
      relatedModules: <String>['properties', 'property_services'],
      notes: <String>[
        'هذا المسار يفتحه الشات داخليًا حتى لو لم يكن مسجلًا في MaterialApp.routes.',
      ],
    ),
    _screen(
      key: 'tenants',
      title: 'العملاء',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: false,
      route: '/tenants',
      aliases: <String>['clients', 'tenants_clients'],
      description: 'إدارة العملاء بمختلف أنواعهم مع القيود والحقول الإلزامية.',
      primaryActions: <String>['إضافة عميل', 'تعديل عميل', 'أرشفة', 'قائمة سوداء'],
      relatedModules: <String>['tenants'],
      notes: <String>[
        'هذا المسار يفتحه الشات داخليًا حتى لو لم يكن مسجلًا في MaterialApp.routes.',
      ],
    ),
    _screen(
      key: 'contracts',
      title: 'العقود',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/contracts',
      aliases: <String>['contract'],
      description: 'إدارة العقود وإنشاؤها وتعديلها وتجديدها وإنهاؤها.',
      primaryActions: <String>['إنشاء عقد', 'تعديل عقد', 'تجديد', 'إنهاء'],
      relatedModules: <String>['contracts'],
    ),
    _screen(
      key: 'contracts_new',
      title: 'إضافة عقد',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: false,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/contracts/new',
      aliases: <String>['new_contract', 'add_contract'],
      description: 'مدخل شاشة إضافة عقد جديد أو بدء عملية تجديد.',
      primaryActions: <String>['بدء إنشاء عقد', 'استكمال الحقول من الشاشة'],
      relatedModules: <String>['contracts'],
      notes: <String>[
        'الشات يستطيع تنفيذ إنشاء العقد مباشرة وفق نفس القيود، كما يستطيع فتح الشاشة نفسها مع تعبئة أولية للعقار أو العميل عند الحاجة.',
        'في الحالات التي تتطلب استكمال خدمات العقار أو خطوة مرئية فعلية، يعيد الشات requiresScreenCompletion مع توجيه واضح للشاشة المناسبة.',
      ],
    ),
    _screen(
      key: 'invoices',
      title: 'الفواتير',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/invoices',
      aliases: <String>['invoice', 'vouchers'],
      description: 'إدارة الفواتير والسندات والمدفوعات والإلغاء.',
      primaryActions: <String>['إصدار فاتورة', 'تسجيل دفعة', 'إنشاء سند يدوي', 'إلغاء فاتورة'],
      relatedModules: <String>['invoices'],
    ),
    _screen(
      key: 'invoices_history',
      title: 'سجل فواتير العقد',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_requires_args',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      chatNavigationEnabled: false,
      appRouteRegistered: true,
      route: '/invoices/history',
      aliases: <String>['invoice_history'],
      requiredNavigationArgs: <String>['contractId'],
      description: 'سجل فواتير عقد محدد، ويحتاج contractId لفتحه.',
      primaryActions: <String>['عرض تاريخ الفواتير لعقد محدد'],
      relatedModules: <String>['invoices'],
      notes: <String>[
        'الشات يقرأ محتوى هذه الشاشة لعقد محدد عبر مرجع العقد، ويستطيع أيضًا فتحها عبر أداة مخصصة بعد حل contractId الصحيح.',
        'هذه الشاشة لا تُفتح مباشرة بالاسم العام فقط لأنها تحتاج contractId.',
      ],
    ),
    _screen(
      key: 'maintenance',
      title: 'الصيانة',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/maintenance',
      aliases: <String>['service_requests', 'maintenance_requests'],
      description: 'إدارة طلبات الصيانة والخدمات الدورية ومتابعة الحالات.',
      primaryActions: <String>['إنشاء طلب', 'تحديث الحالة', 'متابعة الخدمة الدورية'],
      relatedModules: <String>['maintenance', 'property_services'],
    ),
    _screen(
      key: 'maintenance_new',
      title: 'إضافة صيانة',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: false,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/maintenance/new',
      aliases: <String>['new_maintenance', 'add_maintenance'],
      description: 'مدخل إنشاء طلب صيانة جديد من الشاشة المخصصة.',
      primaryActions: <String>['بدء طلب صيانة', 'استكمال الحقول من الشاشة'],
      relatedModules: <String>['maintenance'],
      notes: <String>[
        'الشات يستطيع تنفيذ إنشاء الطلب مباشرة وفق قيود الشاشة، ويستطيع أيضًا فتح شاشة الإضافة نفسها مع تعبئة أولية للعقار والعنوان والوصف والتواريخ والتكلفة ومقدم الخدمة.',
        'إنشاء الطلب بحالة مكتمل من الدردشة أصبح يطابق منطق الشاشة بتوليد السند المرتبط عند الحاجة.',
      ],
    ),
    _screen(
      key: 'reports',
      title: 'التقارير',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/reports',
      aliases: <String>['report', 'analytics'],
      description: 'التقارير المالية والتشغيلية وتقارير الملاك والمكتب.',
      primaryActions: <String>[
        'ملخص مالي',
        'تقارير العقارات',
        'تقارير العملاء',
        'تقارير العقود',
        'تقارير الخدمات',
        'تقارير المكتب والملاك',
      ],
      relatedModules: <String>['reports'],
    ),
    _screen(
      key: 'property_services',
      title: 'خدمات العقار',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_requires_args',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: false,
      appRouteRegistered: true,
      route: '/property/services',
      aliases: <String>['property_service', 'services', 'property/services'],
      requiredNavigationArgs: <String>['propertyId'],
      description:
          'الشاشة المتخصصة للخدمات الدورية حسب العقار، وتحتاج propertyId لفتحها مباشرة.',
      primaryActions: <String>[
        'عرض الخدمات الدورية',
        'قراءة السجل',
        'إنشاء خدمة',
        'تعديل خدمة',
      ],
      relatedModules: <String>['property_services', 'maintenance'],
      notes: <String>[
        'الشات يقرأ بطاقات الخدمات الخمس وحالة كل خدمة ونمط إدارتها وجدولها وسجلها المختصر كما في الشاشة.',
        'الشات ينفذ التدفقات القياسية المسموحة، ويعيد requiresScreenCompletion بوضوح عندما تبقى الخطوة المرئية داخل الشاشة مثل توزيع الوحدات أو بعض تدفقات التنفيذ الخاصة.',
        'فتح الشاشة نفسها ما زال يحتاج propertyId.',
      ],
    ),
    _screen(
      key: 'notifications',
      title: 'الإشعارات',
      audience: 'shared',
      entryKind: 'screen',
      routeAvailability: 'material_app_and_chat_internal',
      chatCoverage: 'partial',
      chatReadSupported: true,
      chatWriteSupported: false,
      chatNavigationEnabled: true,
      appRouteRegistered: true,
      route: '/notifications',
      aliases: <String>['alerts', 'alert_center'],
      description: 'مركز الإشعارات والتنبيهات المتعلقة بالعقود والفواتير والخدمات الدورية.',
      primaryActions: <String>['عرض التنبيهات', 'الانتقال من التنبيه إلى الشاشة المستهدفة'],
      relatedModules: <String>['notifications'],
      notes: <String>[
        'تغطية الشات هنا ما زالت جزئية؛ الشات يقرأ الإشعارات ويصفّيها لكن التثبيت والإخفاء والانتقال من الإشعار يبقى من الشاشة.',
      ],
    ),
    _screen(
      key: 'settings',
      title: 'الإعدادات',
      audience: 'shared',
      entryKind: 'drawer_action',
      routeAvailability: 'drawer_only',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: false,
      appRouteRegistered: false,
      aliases: <String>['preferences'],
      description:
          'إعدادات اللغة والتقويم والتنبيهات والقوالب الرسائلية المحفوظة في user_prefs.',
      primaryActions: <String>[
        'قراءة الإعدادات الحالية',
        'تعديل التفضيلات الفعلية',
        'تعديل القوالب والتنبيهات',
      ],
      relatedModules: <String>['settings'],
      notes: <String>[
        'الشات يقرأ الإعدادات الفعلية من user_prefs ويعدل اللغة ونظام التاريخ والتنبيهات الأساسية والسنوية حسب السنوات وساعة الإرسال اليومية والقوالب النصية المدعومة.',
        'هذه الشاشة تبقى من نوع drawer_action وليست مسار تنقل مباشر من الدردشة.',
      ],
    ),
    _screen(
      key: 'office_clients',
      title: 'عملاء المكتب',
      audience: 'office',
      entryKind: 'module_only',
      routeAvailability: 'module_only',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: false,
      appRouteRegistered: false,
      aliases: <String>['office_clients_list', 'office_clients_module'],
      description:
          'إدارة عملاء المكتب وبياناتهم ووصولهم واشتراكاتهم من خلال الأدوات والعمليات المكتبية.',
      primaryActions: <String>[
        'قائمة عملاء المكتب',
        'تفاصيل العميل',
        'إدارة الوصول',
        'إدارة الاشتراك',
      ],
      relatedModules: <String>['office_clients'],
      notes: <String>[
        'هذه وحدة تشغيلية داخل الشات وليست شاشة Route مستقلة في التطبيق.',
      ],
      requiresOfficeWideRead: true,
    ),
    _screen(
      key: 'office_users',
      title: 'مستخدمو المكتب',
      audience: 'office',
      entryKind: 'drawer_push',
      routeAvailability: 'drawer_push',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      chatNavigationEnabled: false,
      appRouteRegistered: false,
      aliases: <String>['office_staff', 'users'],
      description: 'شاشة إدارة مستخدمي المكتب التي تُفتح عبر Push من قائمة المكتب.',
      primaryActions: <String>[
        'إدارة مستخدمي المكتب',
        'إدارة الصلاحيات',
        'إدارة حالة الدخول',
        'إرسال روابط إعادة التعيين',
      ],
      relatedModules: <String>['office_users'],
      notes: <String>[
        'الشات يدعم العمليات الأساسية لهذه الشاشة، لكن فتحها بصريًا ما زال من القائمة الداخلية للمكتب.',
      ],
      requiresOfficeWideRead: true,
    ),
    _screen(
      key: 'activity_log',
      title: 'سجل النشاط',
      audience: 'office',
      entryKind: 'reference_only',
      routeAvailability: 'reference_only',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      chatNavigationEnabled: false,
      appRouteRegistered: false,
      aliases: <String>['activity', 'audit_log'],
      description: 'سجل نشاط المكتب وعملياته الإدارية.',
      primaryActions: <String>['متابعة السجل', 'مراجعة الأحداث'],
      relatedModules: <String>['activity_log'],
      notes: <String>[
        'الوحدة للقراءة فقط، وقد يفرض الشات onlyMine تلقائيًا إذا كانت الصلاحية الفعلية لا تسمح بعرض كامل السجل.',
      ],
      requiresOfficeWideRead: true,
    ),
  ];

  static final List<Map<String, dynamic>> _modules = <Map<String, dynamic>>[
    _module(
      key: 'dashboard',
      title: 'لوحة الرئيسية',
      audience: 'owner',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      screenKeys: <String>['home'],
      primaryActions: <String>['ملخصات عامة', 'الوصول إلى الشاشات الرئيسية'],
      readTools: <String>[
        'get_home_dashboard',
        'get_properties_summary',
        'get_total_receivables',
        'get_overdue_count',
        'get_notifications',
      ],
      notes: <String>[
        'الشات يملك الآن أداة مستقلة تمثل بطاقات الرئيسية والأزرار السريعة ومدخل أقرب الاستحقاقات كما تظهر في الصفحة.',
      ],
      description: 'الوحدة الكاملة للشاشة الرئيسية للحساب العادي مع البطاقات والتنبيهات والأزرار السريعة.',
    ),
    _module(
      key: 'properties',
      title: 'إدارة العقارات',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['properties'],
      primaryActions: <String>['إضافة', 'تعديل', 'أرشفة', 'إضافة وحدة', 'عرض التفاصيل'],
      readTools: <String>[
        'get_properties_summary',
        'get_properties_list',
        'get_property_details',
        'get_building_units',
      ],
      writeTools: <String>[
        'add_property',
        'edit_property',
        'archive_property',
        'unarchive_property',
        'add_building_unit',
      ],
      description: 'الوحدة الكاملة للعقارات والوحدات وقيود الأرشفة.',
    ),
    _module(
      key: 'tenants',
      title: 'إدارة العملاء',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['tenants'],
      primaryActions: <String>['إضافة', 'تعديل', 'أرشفة', 'قائمة سوداء', 'عرض التفاصيل'],
      readTools: <String>[
        'get_tenants_list',
        'get_tenant_details',
      ],
      writeTools: <String>[
        'add_client_record',
        'edit_tenant',
        'archive_tenant',
        'unarchive_tenant',
        'blacklist_tenant',
        'unblacklist_tenant',
      ],
      description: 'الوحدة الكاملة للعملاء مع الأنواع والحقول المطلوبة والقيود.',
    ),
    _module(
      key: 'contracts',
      title: 'إدارة العقود',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['contracts', 'contracts_new'],
      primaryActions: <String>['إنشاء', 'تعديل', 'تجديد', 'إنهاء', 'تفاصيل'],
      readTools: <String>[
        'get_contracts_list',
        'get_active_contracts',
        'get_contract_details',
      ],
      writeTools: <String>[
        'create_contract',
        'edit_contract',
        'renew_contract',
        'terminate_contract',
      ],
      notes: <String>[
        'الشات ينفذ إنشاء العقد مباشرة، ويفتح شاشة الإدخال نفسها مع تعبئة أولية عندما يطلب المستخدم ذلك.',
        'إذا كانت خدمات العقار المطلوبة غير مكتملة فالشات لا يدّعي النجاح، بل يوجّه إلى شاشة خدمات العقار لإكمالها.',
      ],
      description: 'الوحدة الكاملة للعقود وربطها بالعميل والعقار والخدمات الدورية.',
    ),
    _module(
      key: 'invoices',
      title: 'الفواتير والسندات',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['invoices', 'invoices_history'],
      primaryActions: <String>['إصدار', 'تحصيل', 'سند يدوي', 'إلغاء', 'سجل دفعات'],
      readTools: <String>[
        'get_invoices_list',
        'get_unpaid_invoices',
        'get_invoices_by_type',
        'get_invoice_payment_history',
        'get_contract_invoice_history',
      ],
      writeTools: <String>[
        'create_invoice',
        'record_payment',
        'create_manual_voucher',
        'cancel_invoice',
      ],
      notes: <String>[
        'الشات يقرأ سجل سندات العقد نفسه عبر مرجع العقد، ويستطيع فتح شاشة invoices_history بأداة مخصصة عند الحاجة.',
      ],
      description: 'الوحدة الكاملة للفواتير والسندات والتحصيل وسجل الدفع.',
    ),
    _module(
      key: 'maintenance',
      title: 'الصيانة والخدمات الدورية',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['maintenance', 'maintenance_new'],
      primaryActions: <String>['إنشاء طلب', 'تغيير حالة', 'إدارة خدمات دورية'],
      readTools: <String>[
        'get_maintenance_list',
        'get_maintenance_details',
      ],
      writeTools: <String>[
        'create_maintenance_request',
        'update_maintenance_status',
      ],
      notes: <String>[
        'الشات ينفذ إنشاء الطلب بنفس قيود الشاشة، ويدعم فتح شاشة الإضافة مع تعبئة أولية عندما تكون الخطوة المرئية مطلوبة أو مرغوبة.',
        'إنشاء الطلب بحالة مكتمل من الدردشة يطابق سلوك الشاشة في توليد السند عند الحاجة.',
      ],
      description: 'الوحدة الأساسية للصيانة وطلبات التنفيذ.',
    ),
    _module(
      key: 'property_services',
      title: 'خدمات العقار',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['property_services'],
      primaryActions: <String>['قراءة خدمات العقار', 'سجل الخدمة الدورية', 'إنشاء وتحديث الخدمة'],
      readTools: <String>[
        'get_property_services',
        'get_property_service_details',
        'get_periodic_service_history',
      ],
      writeTools: <String>[
        'create_periodic_service',
        'update_periodic_service',
      ],
      notes: <String>[
        'الشات يطابق منطق الشاشة في أوضاع النظافة والمصعد والإنترنت والمياه والكهرباء، ويعرض حدود الكتابة عندما تحتاج العملية استكمالًا بصريًا من الشاشة.',
        'فتح الشاشة نفسها يحتاج propertyId، وبعض تدفقات توزيع الوحدات أو التنفيذ المرئي تبقى من الواجهة ويعاد التصريح بها بوضوح.',
      ],
      description: 'الوحدة الخاصة بخدمات العقار الدورية وربطها بالعقار المستهدف.',
    ),
    _module(
      key: 'reports',
      title: 'التقارير المالية',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['reports'],
      primaryActions: <String>['ملخص مالي', 'تقارير العقارات', 'الملاك', 'المكتب', 'التسويات'],
      readTools: <String>[
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
      writeTools: <String>[
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
      description: 'الوحدة الأقوى في الشات حاليًا لقراءة وتشغيل التقارير الفعلية.',
    ),
    _module(
      key: 'notifications',
      title: 'الإشعارات',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['notifications'],
      primaryActions: <String>['قراءة التنبيهات الحالية', 'فتح الهدف المرتبط', 'تعليم التنبيه كمقروء'],
      readTools: <String>['get_notifications', 'open_notification_target'],
      writeTools: <String>['mark_notification_read'],
      notes: <String>[
        'الشات يغطي قراءة الإشعارات الفعلية وفتح الهدف المرتبط وتعليم التنبيه كمقروء، مع بقاء العرض البصري للشاشة نفسها داخل الواجهة.',
      ],
      description: 'ملخص التنبيهات والعقود القريبة والفواتير المتأخرة والخدمات.',
    ),
    _module(
      key: 'settings',
      title: 'الإعدادات',
      audience: 'shared',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['settings'],
      primaryActions: <String>[
        'قراءة الإعدادات الحالية',
        'تعديل التفضيلات الأساسية',
        'تعديل قوالب الرسائل والتنبيهات',
      ],
      readTools: <String>['get_settings'],
      writeTools: <String>['update_settings'],
      notes: <String>[
        'الشات يقرأ ويعدل الإعدادات الفعلية المسموحة داخل user_prefs، بما فيها خرائط السنوات السنوية والقوالب النصية المدعومة.',
        'هذه وحدة مرجعية كاملة للشات، مع بقاء العرض البصري للشاشة نفسها داخل القائمة الجانبية.',
      ],
      description: 'الوحدة المرجعية للإعدادات والتفضيلات.',
    ),
    _module(
      key: 'office_dashboard',
      title: 'لوحة المكتب',
      audience: 'office',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      screenKeys: <String>['office'],
      primaryActions: <String>['ملخص المكتب', 'الوصول إلى الوحدات المكتبية'],
      readTools: <String>[
        'get_office_dashboard',
        'get_office_summary',
      ],
      requiresOfficeWideRead: true,
      notes: <String>[
        'الشات يقرأ قشرة لوحة المكتب مع العدّاد والتنبيهات وملخص العملاء والمستخدمين، ويعرف أن جسم الشاشة الافتراضي هو صفحة عملاء المكتب.',
      ],
      description: 'المرجع التشغيلي الكامل لرئيسية لوحة المكتب وربطها بصفحة عملاء المكتب والتنبيهات.',
    ),
    _module(
      key: 'office_clients',
      title: 'عملاء المكتب',
      audience: 'office',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['office_clients'],
      primaryActions: <String>['قائمة العملاء', 'الوصول', 'الاشتراك', 'إعادة التعيين'],
      readTools: <String>[
        'get_office_clients_list',
        'get_office_client_details',
        'get_office_summary',
        'get_office_client_access',
        'get_office_client_subscription',
      ],
      writeTools: <String>[
        'add_office_client',
        'edit_office_client',
        'delete_office_client',
        'set_office_client_access',
        'set_office_client_subscription',
        'generate_office_client_reset_link',
      ],
      requiresOfficeWideRead: true,
      description: 'الوحدة الكاملة لإدارة عملاء المكتب داخل الشات.',
    ),
    _module(
      key: 'office_users',
      title: 'مستخدمو المكتب',
      audience: 'office',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: true,
      screenKeys: <String>['office_users'],
      primaryActions: <String>[
        'قائمة المستخدمين',
        'تفاصيل المستخدم',
        'إدارة الصلاحيات',
        'إدارة الدخول',
        'إعادة التعيين',
      ],
      readTools: <String>[
        'get_office_users_list',
        'get_office_user_details',
      ],
      writeTools: <String>[
        'add_office_user',
        'edit_office_user',
        'set_office_user_permission',
        'set_office_user_access',
        'delete_office_user',
        'generate_office_user_reset_link',
      ],
      notes: <String>[
        'الشات يدير المنطق التشغيلي لهذه الوحدة، لكن الشاشة نفسها ما زالت تُفتح عبر القائمة الداخلية للمكتب.',
      ],
      requiresOfficeWideRead: true,
      description: 'الوحدة الكاملة لإدارة مستخدمي المكتب داخل الشات.',
    ),
    _module(
      key: 'activity_log',
      title: 'سجل النشاط',
      audience: 'office',
      chatCoverage: 'full',
      chatReadSupported: true,
      chatWriteSupported: false,
      screenKeys: <String>['activity_log'],
      primaryActions: <String>['عرض السجل', 'تصفية الأحداث', 'تقييد العرض حسب الصلاحية'],
      readTools: <String>['get_activity_log'],
      notes: <String>[
        'سجل النشاط للقراءة فقط، وقد يفرض الشات عرض العمليات الخاصة بالحساب الحالي فقط حسب الصلاحية الفعلية.',
      ],
      requiresOfficeWideRead: true,
      description: 'وحدة قراءة سجل نشاط المكتب داخل الشات.',
    ),
  ];

  static String normalizeScreenKey(String value) {
    var normalized = value.trim().toLowerCase();
    normalized = normalized.replaceAll('\\', '/');
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');
    normalized = normalized.replaceAll(RegExp(r'[\s\-]+'), '_');
    normalized = normalized.replaceAll('/', '_');
    return normalized;
  }

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> source) {
    final clone = <String, dynamic>{};
    source.forEach((String key, dynamic value) {
      if (value is List) {
        clone[key] = List<dynamic>.from(value);
      } else if (value is Map) {
        clone[key] = Map<String, dynamic>.from(value as Map);
      } else {
        clone[key] = value;
      }
    });
    return clone;
  }

  static bool _isVisibleForMode(
    Map<String, dynamic> item, {
    required bool isOfficeMode,
  }) {
    final audience = (item['audience'] ?? 'shared').toString();
    switch (audience) {
      case 'office':
        return isOfficeMode;
      case 'owner':
        return !isOfficeMode;
      default:
        return true;
    }
  }

  static bool _sessionCanRead(
    Map<String, dynamic> item, {
    required bool canReadAll,
  }) {
    if (item['chatReadSupported'] != true) return false;
    if (item['requiresOfficeWideRead'] == true && !canReadAll) return false;
    return true;
  }

  static bool _sessionCanWrite(
    Map<String, dynamic> item, {
    required bool canWrite,
  }) {
    return item['chatWriteSupported'] == true && canWrite;
  }

  static bool _sessionCanAccessItem(
    Map<String, dynamic> item, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    return _sessionCanRead(item, canReadAll: canReadAll) ||
        _sessionCanWrite(item, canWrite: canWrite);
  }

  static bool _sessionCanNavigateScreen(
    Map<String, dynamic> screen, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    if (screen['chatNavigationEnabled'] != true) return false;
    return _sessionCanAccessItem(
      screen,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
  }

  static String _availabilityStatus({
    required bool supported,
    required bool granted,
  }) {
    if (!supported) return 'not_supported';
    return granted ? 'available' : 'blocked_by_permission';
  }

  static String _screenNavigationStatus(
    Map<String, dynamic> screen, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    final requiredArgs =
        ((screen['requiredNavigationArgs'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);

    if (_sessionCanNavigateScreen(
      screen,
      canWrite: canWrite,
      canReadAll: canReadAll,
    )) {
      return 'direct_navigation';
    }
    if (screen['chatNavigationEnabled'] == true) {
      return 'blocked_by_permission';
    }
    if (requiredArgs.isNotEmpty) {
      return 'tool_with_required_args';
    }
    if (_sessionCanRead(screen, canReadAll: canReadAll) ||
        _sessionCanWrite(screen, canWrite: canWrite)) {
      return 'supported_without_direct_navigation';
    }
    return 'not_available';
  }

  static String _screenOverallStatus(
    Map<String, dynamic> screen, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    final canRead = _sessionCanRead(screen, canReadAll: canReadAll);
    final canWriteNow = _sessionCanWrite(screen, canWrite: canWrite);
    final navigationStatus = _screenNavigationStatus(
      screen,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );

    if (canRead && canWriteNow) return 'full_access';
    if (canRead) {
      return navigationStatus == 'tool_with_required_args'
          ? 'read_access_with_special_entry'
          : 'read_only';
    }
    if (canWriteNow) return 'write_entry_only';
    if (screen['requiresOfficeWideRead'] == true && !canReadAll) {
      return 'blocked_by_permission';
    }
    if (screen['chatWriteSupported'] == true && !canWrite) {
      return 'blocked_by_permission';
    }
    if (screen['chatReadSupported'] != true &&
        screen['chatWriteSupported'] != true) {
      return 'reference_only';
    }
    return 'not_available';
  }

  static String _screenValidationReason(
    Map<String, dynamic> screen, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    final requiredArgs =
        ((screen['requiredNavigationArgs'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);

    if (screen['requiresOfficeWideRead'] == true && !canReadAll) {
      return 'يحتاج هذا المسار صلاحية قراءة عامة للمكتب.';
    }
    if (screen['chatWriteSupported'] == true &&
        screen['chatReadSupported'] != true &&
        !canWrite) {
      return 'هذه شاشة إدخال أو تعديل وتتطلب صلاحية كتابة.';
    }
    if (requiredArgs.isNotEmpty) {
      return 'هذا المسار يحتاج أدوات فتح خاصة مع حقول إضافية: ${requiredArgs.join(', ')}.';
    }
    if (screen['chatReadSupported'] != true &&
        screen['chatWriteSupported'] != true) {
      return 'هذه الشاشة مرجعية داخل المخطط وليست مسار تشغيل مباشر من الشات.';
    }
    if (screen['chatWriteSupported'] == true && !canWrite) {
      return 'هذه الشاشة تتضمن كتابة لكن الجلسة الحالية للقراءة فقط.';
    }
    if (screen['chatNavigationEnabled'] != true) {
      return 'هذه الشاشة مدعومة منطقيًا لكن ليس لها تنقل مباشر عام من الشات.';
    }
    return 'الشاشة متاحة ضمن حدود هذه الجلسة.';
  }

  static String _moduleOverallStatus(
    Map<String, dynamic> module, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    final canRead = _sessionCanRead(module, canReadAll: canReadAll);
    final canWriteNow = _sessionCanWrite(module, canWrite: canWrite);

    if (canRead && canWriteNow) return 'full_access';
    if (canRead) return 'read_only';
    if (canWriteNow) return 'write_only';
    if (module['requiresOfficeWideRead'] == true && !canReadAll) {
      return 'blocked_by_permission';
    }
    if (module['chatReadSupported'] != true &&
        module['chatWriteSupported'] != true) {
      return 'reference_only';
    }
    if (module['chatWriteSupported'] == true && !canWrite) {
      return 'blocked_by_permission';
    }
    return 'not_available';
  }

  static String _moduleValidationReason(
    Map<String, dynamic> module, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    if (module['requiresOfficeWideRead'] == true && !canReadAll) {
      return 'هذه الوحدة تحتاج صلاحية قراءة عامة للمكتب.';
    }
    if (module['chatWriteSupported'] == true && !canWrite) {
      return 'هذه الوحدة تتضمن كتابة لكن الجلسة الحالية لا تملكها.';
    }
    if (module['chatReadSupported'] != true &&
        module['chatWriteSupported'] != true) {
      return 'هذه الوحدة مرجعية فقط داخل المخطط المعماري.';
    }
    return 'الوحدة متاحة ضمن حدود هذه الجلسة.';
  }

  static int _countOverallStatus(
    List<Map<String, dynamic>> items,
    String status,
  ) {
    return items.where((Map<String, dynamic> item) {
      final validation = item['validation'];
      return validation is Map && validation['overall'] == status;
    }).length;
  }

  static Map<String, dynamic> _withSessionAccess(
    Map<String, dynamic> item, {
    required bool canWrite,
    required bool canReadAll,
  }) {
    final clone = _cloneMap(item);
    clone['sessionAccess'] = <String, dynamic>{
      'canRead': _sessionCanRead(item, canReadAll: canReadAll),
      'canWrite': _sessionCanWrite(item, canWrite: canWrite),
      'canReadAllClients': canReadAll,
    };
    return clone;
  }

  static List<Map<String, dynamic>> visibleScreens({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    return _screens
        .where((Map<String, dynamic> screen) =>
            _isVisibleForMode(screen, isOfficeMode: isOfficeMode))
        .where(
          (Map<String, dynamic> screen) => _sessionCanAccessItem(
            screen,
            canWrite: canWrite,
            canReadAll: canReadAll,
          ),
        )
        .map(
          (Map<String, dynamic> screen) => _withSessionAccess(
            screen,
            canWrite: canWrite,
            canReadAll: canReadAll,
          ),
        )
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> visibleModules({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    return _modules
        .where((Map<String, dynamic> module) =>
            _isVisibleForMode(module, isOfficeMode: isOfficeMode))
        .where(
          (Map<String, dynamic> module) => _sessionCanAccessItem(
            module,
            canWrite: canWrite,
            canReadAll: canReadAll,
          ),
        )
        .map(
          (Map<String, dynamic> module) => _withSessionAccess(
            module,
            canWrite: canWrite,
            canReadAll: canReadAll,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> buildReferencePayload({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final screens = visibleScreens(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
    final modules = visibleModules(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
    return <String, dynamic>{
      'version': 8,
      'mode': isOfficeMode ? 'office' : 'owner',
      'screens': screens,
      'modules': modules,
      'navigation': <String, dynamic>{
        'supportedScreens': supportedChatNavigationTitles(
          isOfficeMode: isOfficeMode,
          canWrite: canWrite,
          canReadAll: canReadAll,
        ).keys.toList(growable: false),
        'routes': chatNavigationRoutes(
          isOfficeMode: isOfficeMode,
          canWrite: canWrite,
          canReadAll: canReadAll,
        ),
        'nonDirectScreens': screens
            .where((Map<String, dynamic> screen) =>
                screen['chatNavigationEnabled'] != true)
            .map(
              (Map<String, dynamic> screen) => <String, dynamic>{
                'key': screen['key'],
                'title': screen['title'],
                'entryKind': screen['entryKind'],
                'requiredNavigationArgs': screen['requiredNavigationArgs'],
              },
            )
            .toList(growable: false),
      },
    };
  }

  static Map<String, String> supportedChatNavigationTitles({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final titles = <String, String>{};
    for (final Map<String, dynamic> screen in _screens) {
      if (!_isVisibleForMode(screen, isOfficeMode: isOfficeMode)) {
        continue;
      }
      if (!_sessionCanNavigateScreen(
        screen,
        canWrite: canWrite,
        canReadAll: canReadAll,
      )) {
        continue;
      }
      final key = (screen['key'] ?? '').toString();
      final title = (screen['title'] ?? '').toString();
      if (key.isEmpty || title.isEmpty) continue;
      titles[key] = title;
    }
    return titles;
  }

  static Map<String, String> chatNavigationRoutes({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final routes = <String, String>{};
    for (final Map<String, dynamic> screen in _screens) {
      if (!_isVisibleForMode(screen, isOfficeMode: isOfficeMode)) {
        continue;
      }
      if (!_sessionCanNavigateScreen(
        screen,
        canWrite: canWrite,
        canReadAll: canReadAll,
      )) {
        continue;
      }
      final key = (screen['key'] ?? '').toString();
      final route = (screen['route'] ?? '').toString();
      if (key.isEmpty || route.isEmpty) continue;
      routes[key] = route;
    }
    return routes;
  }

  static String chatNavigationKeysDescription({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final keys = supportedChatNavigationTitles(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    ).keys.toList(growable: false);
    return keys.join('/');
  }

  static Map<String, dynamic>? findScreen(
    String value, {
    required bool isOfficeMode,
    bool? canWrite,
    bool? canReadAll,
  }) {
    final normalizedInput = normalizeScreenKey(value);
    if (normalizedInput.isEmpty) return null;

    for (final Map<String, dynamic> rawScreen in _screens) {
      if (!_isVisibleForMode(rawScreen, isOfficeMode: isOfficeMode)) {
        continue;
      }
      final candidates = <String>{
        (rawScreen['key'] ?? '').toString(),
        if ((rawScreen['route'] ?? '').toString().trim().isNotEmpty)
          (rawScreen['route'] ?? '').toString(),
        ...((rawScreen['aliases'] as List?) ?? const <dynamic>[])
            .whereType<String>(),
      };
      final normalizedCandidates = candidates
          .where((String item) => item.trim().isNotEmpty)
          .map(normalizeScreenKey)
          .toSet();
      if (normalizedCandidates.contains(normalizedInput)) {
        if (canWrite != null &&
            canReadAll != null &&
            !_sessionCanAccessItem(
              rawScreen,
              canWrite: canWrite,
              canReadAll: canReadAll,
            )) {
          continue;
        }
        if (canWrite != null && canReadAll != null) {
          return _withSessionAccess(
            rawScreen,
            canWrite: canWrite,
            canReadAll: canReadAll,
          );
        }
        return _cloneMap(rawScreen);
      }
    }
    return null;
  }

  static Map<String, dynamic> buildValidationMatrix({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final screens = _screens
        .where(
          (Map<String, dynamic> screen) =>
              _isVisibleForMode(screen, isOfficeMode: isOfficeMode),
        )
        .map((Map<String, dynamic> screen) {
          final requiredArgs =
              ((screen['requiredNavigationArgs'] as List?) ??
                      const <dynamic>[])
                  .whereType<String>()
                  .toList(growable: false);
          final canRead = _sessionCanRead(screen, canReadAll: canReadAll);
          final canWriteNow = _sessionCanWrite(screen, canWrite: canWrite);
          final canNavigate = _sessionCanNavigateScreen(
            screen,
            canWrite: canWrite,
            canReadAll: canReadAll,
          );
          final navigationStatus = _screenNavigationStatus(
            screen,
            canWrite: canWrite,
            canReadAll: canReadAll,
          );
          return <String, dynamic>{
            'key': screen['key'],
            'title': screen['title'],
            'chatCoverage': screen['chatCoverage'],
            'audience': screen['audience'],
            'route': screen['route'],
            'requiredNavigationArgs': requiredArgs,
            'sessionAccess': <String, dynamic>{
              'canRead': canRead,
              'canWrite': canWriteNow,
              'canNavigate': canNavigate,
              'canReadAllClients': canReadAll,
            },
            'validation': <String, dynamic>{
              'read': _availabilityStatus(
                supported: screen['chatReadSupported'] == true,
                granted: canRead,
              ),
              'write': _availabilityStatus(
                supported: screen['chatWriteSupported'] == true,
                granted: canWriteNow,
              ),
              'navigation': navigationStatus,
              'overall': _screenOverallStatus(
                screen,
                canWrite: canWrite,
                canReadAll: canReadAll,
              ),
              'reason': _screenValidationReason(
                screen,
                canWrite: canWrite,
                canReadAll: canReadAll,
              ),
            },
          };
        })
        .toList(growable: false);

    final modules = _modules
        .where(
          (Map<String, dynamic> module) =>
              _isVisibleForMode(module, isOfficeMode: isOfficeMode),
        )
        .map((Map<String, dynamic> module) {
          final canRead = _sessionCanRead(module, canReadAll: canReadAll);
          final canWriteNow = _sessionCanWrite(module, canWrite: canWrite);
          return <String, dynamic>{
            'key': module['key'],
            'title': module['title'],
            'chatCoverage': module['chatCoverage'],
            'audience': module['audience'],
            'sessionAccess': <String, dynamic>{
              'canRead': canRead,
              'canWrite': canWriteNow,
              'canReadAllClients': canReadAll,
            },
            'validation': <String, dynamic>{
              'read': _availabilityStatus(
                supported: module['chatReadSupported'] == true,
                granted: canRead,
              ),
              'write': _availabilityStatus(
                supported: module['chatWriteSupported'] == true,
                granted: canWriteNow,
              ),
              'overall': _moduleOverallStatus(
                module,
                canWrite: canWrite,
                canReadAll: canReadAll,
              ),
              'reason': _moduleValidationReason(
                module,
                canWrite: canWrite,
                canReadAll: canReadAll,
              ),
            },
          };
        })
        .toList(growable: false);

    return <String, dynamic>{
      'version': 1,
      'mode': isOfficeMode ? 'office' : 'owner',
      'summary': <String, dynamic>{
        'screensTotal': screens.length,
        'modulesTotal': modules.length,
        'screenStatuses': <String, dynamic>{
          'fullAccess': _countOverallStatus(screens, 'full_access'),
          'readOnly': _countOverallStatus(screens, 'read_only'),
          'readWithSpecialEntry':
              _countOverallStatus(screens, 'read_access_with_special_entry'),
          'writeEntryOnly': _countOverallStatus(screens, 'write_entry_only'),
          'blockedByPermission':
              _countOverallStatus(screens, 'blocked_by_permission'),
          'referenceOnly': _countOverallStatus(screens, 'reference_only'),
        },
        'moduleStatuses': <String, dynamic>{
          'fullAccess': _countOverallStatus(modules, 'full_access'),
          'readOnly': _countOverallStatus(modules, 'read_only'),
          'writeOnly': _countOverallStatus(modules, 'write_only'),
          'blockedByPermission':
              _countOverallStatus(modules, 'blocked_by_permission'),
          'referenceOnly': _countOverallStatus(modules, 'reference_only'),
        },
      },
      'screens': screens,
      'modules': modules,
      'closureRule':
          'أي شاشة أو وحدة يجب أن تكون موصوفة هنا بوضوح: متاحة، قراءة فقط، تحتاج مدخل خاص، أو محجوبة بالصلاحية.',
    };
  }

  static Map<String, String> allChatNavigationTitles() {
    final titles = <String, String>{};
    for (final Map<String, dynamic> screen in _screens) {
      if (screen['chatNavigationEnabled'] != true) continue;
      final key = (screen['key'] ?? '').toString();
      final title = (screen['title'] ?? '').toString();
      if (key.isEmpty || title.isEmpty) continue;
      titles[key] = title;
    }
    return titles;
  }
}
