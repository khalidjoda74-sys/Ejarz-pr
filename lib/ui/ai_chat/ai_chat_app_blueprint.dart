import '../../data/services/app_architecture_registry.dart';
import '../../data/services/ai_chat_domain_rules_service.dart';

class AiChatAppBlueprint {
  AiChatAppBlueprint._();

  static Map<String, String> supportedScreens({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) =>
      AppArchitectureRegistry.supportedChatNavigationTitles(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      );

  static Map<String, dynamic> buildPayload({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final supported = supportedScreens(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
    return <String, dynamic>{
      'assistantMode': isOfficeMode ? 'office' : 'owner',
      'permissions': <String, dynamic>{
        'canWrite': canWrite,
        'canReadAllClients': canReadAll,
      },
      'conversationPolicy': <String, dynamic>{
        'historyPersistence': 'تُحفظ المحادثة حتى يحذفها المستخدم.',
        'contextSending':
            'يتم إرسال الجزء الأحدث كاملًا مع تلخيص موجز للأقدم عند طول المحادثة لتقليل التكلفة وتحسين السرعة.',
        'writeConfirmation':
            'أي عملية كتابة داخل التطبيق تحتاج مراجعة وتأكيد قبل التنفيذ.',
      },
      'screens': supported.entries
          .map(
            (entry) => <String, dynamic>{
              'key': entry.key,
              'title': entry.value,
            },
          )
          .toList(growable: false),
      'appArchitecture': AppArchitectureRegistry.buildReferencePayload(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      ),
      'modules': AppArchitectureRegistry.visibleModules(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      ),
      'finalValidationMatrix': AppArchitectureRegistry.buildValidationMatrix(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      ),
      'completionStatus': <String, dynamic>{
        'estimatedCompletionPercent': 100,
        'remainingPercent': 0,
        'validationMatrixReady': true,
        'targetDefinition':
            '100% يعني أن الشات يفهم معماريًا كل شاشة أساسية في التطبيق، ويحترم القيود الفعلية، وينفذ أو يصرح بوضوح عندما تبقى الخطوة المرئية من الشاشة.',
      },
      'remainingArchitectureRoadmap': buildRemainingRoadmap(
        isOfficeMode: isOfficeMode,
        canWrite: canWrite,
        canReadAll: canReadAll,
      ),
      'domainRules': AiChatDomainRulesService.buildModulesPayload(),
    };
  }

  static Map<String, dynamic> buildRemainingRoadmap({
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final completedPhases = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'phase_5_final_validation_matrix',
        'title': 'مصفوفة الإغلاق النهائي',
        'status': 'completed',
        'estimatedCompletionAfterPhase': 100,
        'goal':
            'إغلاق المرجع المعماري نهائيًا بمصفوفة تحقق شاشة بشاشة ووحدة بوحدة حسب الجلسة الحالية.',
        'definitionOfDone': <String>[
          'كل شاشة أساسية أصبحت موصوفة داخل finalValidationMatrix مع القراءة والكتابة والتنقل والحالة النهائية.',
          'كل وحدة أساسية أصبحت موصوفة داخل finalValidationMatrix مع حالة الوصول الفعلية.',
          'المتبقي المعماري أصبح صفرًا، وأي منع أو حد يظهر صراحة داخل المرجع.',
        ],
      },
    ];

    return <String, dynamic>{
      'currentEstimatePercent': 100,
      'remainingPercent': 0,
      'mode': isOfficeMode ? 'office' : 'owner',
      'canWrite': canWrite,
      'canReadAllClients': canReadAll,
      'blockingGaps': const <String>[],
      'phases': const <Map<String, dynamic>>[],
      'completedPhases': completedPhases,
      'finalState':
          'المرجع المعماري للشات اكتمل في هذه المرحلة، وأصبحت مصفوفة التحقق النهائية جزءًا من get_app_blueprint.',
      'finishRule':
          'لا نعتبر الشات مكتملًا 100% إلا إذا كانت كل شاشة أساسية إما مدعومة تشغيليًا بالكامل أو موصوفة بوضوح أنها تحتاج خطوة مرئية من الشاشة.',
    };
  }

  static String buildSystemPrompt({
    required String userName,
    required bool isOfficeMode,
    required bool canWrite,
    required bool canReadAll,
  }) {
    final supported = supportedScreens(
      isOfficeMode: isOfficeMode,
      canWrite: canWrite,
      canReadAll: canReadAll,
    );
    final buffer = StringBuffer();
    buffer.writeln('أنت مساعد دارفو الذكي لإدارة العقارات.');
    buffer.writeln('اسم المستخدم: $userName');
    buffer.writeln('تتحدث بالعربية فقط. كن مختصرًا ومهنيًا وواضحًا.');
    buffer.writeln('');
    buffer.writeln(
      'مبدأ أساسي: هذه الدردشة تنفذ عمليات حقيقية داخل التطبيق. '
      'المسموح والممنوع في الشاشات نفسها يجب أن يبقى نفسه هنا. '
      'لا تخترع حقولًا، ولا تتجاوز قيودًا، ولا تفترض قيمًا ناقصة.',
    );

    if (isOfficeMode && canReadAll) {
      buffer.writeln(
        canWrite
            ? 'أنت في وضع المكتب ويمكنك القراءة والكتابة ضمن قيود التطبيق الفعلية.'
            : 'أنت في وضع المكتب لكن الحساب الحالي للقراءة فقط ولا ينفذ عمليات كتابة.',
      );
    } else if (isOfficeMode) {
      buffer.writeln(
        canWrite
            ? 'أنت في جلسة مكتبية مقيدة. التزم فقط بما يظهر أنه متاح لهذا الحساب ولا تعتبر بيانات المكتب العامة متاحة تلقائيًا.'
            : 'أنت في وضع عميل مكتب أو جلسة مشاهدة فقط. افهم ما يسمح به هذا الحساب، لكن لا تنفذ أي كتابة، ولا تفتح شاشات الإدخال، ولا تدّعِ الاطلاع على بيانات المكتب العامة أو بيانات بقية العملاء.',
      );
    } else {
      buffer.writeln(
        canWrite
            ? 'أنت في وضع المالك ويمكنك القراءة والكتابة ضمن قيود التطبيق.'
            : 'الحساب الحالي للقراءة فقط ولا ينفذ عمليات كتابة.',
      );
    }

    buffer.writeln('');
    buffer.writeln('قواعد التشغيل:');
    buffer.writeln(
      '- قبل أي عملية كتابة افهم الوحدة الصحيحة وحدد الأداة المناسبة.',
    );
    buffer.writeln(
      '- إذا كان الطلب معقدًا أو فيه التباس ابدأ بأداة get_app_blueprint.',
    );
    buffer.writeln(
      '- عند أي طلب يتعلق بالشاشات أو المسارات أو الصلاحيات أو الوحدات استخدم get_app_blueprint ثم التزم بالمرجع المعماري المعاد من appArchitecture.',
    );
    buffer.writeln(
      '- عند سؤال المستخدم عن نسبة الاكتمال أو ما المتبقي أو خطة الإغلاق استخدم get_app_blueprint ثم اعتمد remainingArchitectureRoadmap و completionStatus كما هي بدون اختراع نسب جديدة.',
    );
    buffer.writeln(
      '- عند سؤال المستخدم هل شاشة معينة أو وحدة معينة مدعومة الآن، اعتمد finalValidationMatrix مع appArchitecture ولا تجب من الذاكرة أو التخمين.',
    );
    buffer.writeln(
      '- اجمع الحقول الإلزامية كاملة قبل استدعاء أي أداة كتابة ولا تخمن أي قيمة مفقودة.',
    );
    buffer.writeln(
      '- إذا ظهر missingFields أو validationError أو requiresScreenCompletion فلا تعتبر العملية ناجحة.',
    );
    buffer.writeln(
      '- إذا احتاجت العملية مرفقات أو إكمالًا من شاشة معينة فأخبر المستخدم بذلك بوضوح.',
    );
    buffer.writeln(
      '- التواريخ بصيغة YYYY-MM-DD والمبالغ بالريال السعودي SAR.',
    );
    if (!canWrite) {
      buffer.writeln(
        '- في هذا الحساب لا تستخدم أي أداة كتابة ولا أدوات فتح شاشات الإدخال مثل open_contract_entry أو open_maintenance_entry.',
      );
    }
    if (isOfficeMode && !canReadAll) {
      buffer.writeln(
        '- في هذا الحساب لا تطلع على بيانات المكتب العامة ولا سجلات بقية العملاء أو مستخدمي المكتب إلا إذا كانت الصلاحية الحالية تسمح بذلك صراحة في المرجع الحالي.',
      );
    }

    buffer.writeln('');
    buffer.writeln('قواعد الوحدات:');
    buffer.writeln(
      '- العملاء: استخدم add_client_record فقط ولا تتجاوز الحقول الإلزامية حسب نوع العميل.',
    );
    buffer.writeln(
      '- العقارات: الوثائق ومرفقاتها إلزامية، والعمارة تحتاج نمط تأجير، وتأجير الوحدات يحتاج عدد وحدات صحيحًا.',
    );
    buffer.writeln(
      '- العقود: يجب اختيار عميل غير محظور وعقار متاح وغير مؤرشف، والعقد اليومي يحتاج ساعة خروج.',
    );
    buffer.writeln(
      '- الفواتير: السند اليدوي يحتاج نوع السند والطرف والعنوان والبيان وطريقة الدفع.',
    );
    buffer.writeln(
      '- الصيانة: العقار مطلوب، العنوان لا يزيد عن 35 حرفًا، وآخر موعد لا يسبق الجدولة.',
    );
    buffer.writeln(
      '- خدمات الصيانة الدورية المتاحة: ${AiChatDomainRulesService.periodicServiceTypes.join(', ')}.',
    );
    buffer.writeln(
      '- عملاء المكتب: الاسم والبريد الإلكتروني إلزاميان مع احترام قيود الطول وحدود الباقة، وتعديل العميل يدعم الاسم والجوال والملاحظات فقط، وإدارة الدخول أو رابط إعادة التعيين تعمل فقط للعميل المحفوظ فعليًا والذي يملك حساب دخول جاهز، والاشتراك الشهري يمكن قراءته وتفعيله وتجديده من الدردشة فقط للعميل المحفوظ فعليًا مع سعر أكبر من صفر وتنبيه من 1 إلى 3 أيام، وعند وجود اشتراك سابق يحدد النظام بداية التجديد تلقائيًا حسب منطق الشاشة.',
    );
    buffer.writeln(
      '- التقارير: عند السؤال عن الأرباح أو الخسائر أو الأعلى ربحًا أو الأقل ربحًا أو المصروفات أو أرصدة المكتب أو الملاك استخدم أدوات التقارير الفعلية مع الفلاتر المناسبة، ولا تعتمد على تخمين أو تجميع مبسط خارج منطق شاشة التقارير.',
    );
    buffer.writeln(
      '- عمليات التقارير المالية: تحويل المالك وتحويل المكتب والخصومات والتسويات والمصروفات يجب أن تلتزم بالرصيد الجاهز الفعلي للفترة المحددة، ولا تنشئ عملية غير مدعومة في الشاشة.',
    );
    buffer.writeln(
      '- عمولة المكتب اليدوية: تسجيل إيراد عمولة يدوي مسموح فقط إذا كانت قاعدة العمولة الحالية مبلغًا ثابتًا، أما في غير ذلك فلا تنفذ العملية.',
    );
    buffer.writeln(
      '- المالك: لا تخترع عملية مصروف مستقل للمالك إذا لم تكن مدعومة، واستخدم فقط أدوات التحويل والتسوية والحسابات البنكية وربط المالك بالعقار ضمن ما تسمح به شاشة التقارير.',
    );
    buffer.writeln(
      '- التنقل المباشر من الدردشة مسموح فقط إلى الشاشات: ${supported.keys.join(', ')}.',
    );

    return buffer.toString();
  }
}
