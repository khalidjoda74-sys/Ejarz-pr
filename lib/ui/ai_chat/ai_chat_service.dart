import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_chat_tools.dart';
import 'ai_chat_permissions.dart';
import 'core/ai_openai_config.dart';

class ChatMessage {
  final String role; // 'user', 'assistant', 'system', 'tool'
  final String? content;
  final List<Map<String, dynamic>>? toolCalls;
  final String? toolCallId;
  final String? name;

  ChatMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'role': role};
    if (content != null) m['content'] = content;
    if (toolCalls != null) m['tool_calls'] = toolCalls;
    if (toolCallId != null) m['tool_call_id'] = toolCallId;
    if (name != null) m['name'] = name;
    return m;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'];
    final List<Map<String, dynamic>>? toolCalls;
    if (rawToolCalls is List) {
      toolCalls = rawToolCalls
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } else {
      toolCalls = null;
    }

    return ChatMessage(
      role: (json['role'] ?? '').toString(),
      content: json['content']?.toString(),
      toolCalls: toolCalls,
      toolCallId: json['tool_call_id']?.toString(),
      name: json['name']?.toString(),
    );
  }
}

class _AiChatStreamResponse {
  final String content;
  final List<Map<String, dynamic>>? toolCalls;

  const _AiChatStreamResponse({
    this.content = '',
    this.toolCalls,
  });

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

enum AiChatApiKeyStatus {
  unknown,
  loading,
  ready,
  missing,
  error,
}

enum AiChatScopeType {
  ownerSelf,
  officeGlobal,
  officeClient,
}

@immutable
class AiChatScope {
  final AiChatScopeType type;
  final String scopeId;
  final String? label;

  const AiChatScope._({
    required this.type,
    required this.scopeId,
    this.label,
  });

  const AiChatScope.ownerSelf({
    String ownerUid = '',
    String? ownerName,
  }) : this._(
          type: AiChatScopeType.ownerSelf,
          scopeId: ownerUid,
          label: ownerName,
        );

  const AiChatScope.officeGlobal({
    String officeUid = '',
    String? officeName,
  }) : this._(
          type: AiChatScopeType.officeGlobal,
          scopeId: officeUid,
          label: officeName,
        );

  const AiChatScope.officeClient({
    required String clientUid,
    String? clientName,
  }) : this._(
          type: AiChatScopeType.officeClient,
          scopeId: clientUid,
          label: clientName,
        );

  bool get usesOfficeModeForArchitecture =>
      type == AiChatScopeType.officeGlobal;

  bool get allowsOfficeWideData => type == AiChatScopeType.officeGlobal;

  String get storageTypeKey {
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'owner_self';
      case AiChatScopeType.officeGlobal:
        return 'office_global';
      case AiChatScopeType.officeClient:
        return 'office_client';
    }
  }

  String get normalizedScopeId {
    final normalizedId = scopeId.trim();
    if (normalizedId.isNotEmpty) return normalizedId;
    final normalizedLabel = (label ?? '').trim();
    if (normalizedLabel.isNotEmpty) return normalizedLabel;
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'self';
      case AiChatScopeType.officeGlobal:
        return 'office';
      case AiChatScopeType.officeClient:
        return 'client';
    }
  }

  String get contextTitle {
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'محادثتي';
      case AiChatScopeType.officeGlobal:
        return 'محادثة المكتب';
      case AiChatScopeType.officeClient:
        return 'محادثة العميل';
    }
  }

  String get contextSubtitle {
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'هذا الحساب فقط';
      case AiChatScopeType.officeGlobal:
        return 'بيانات المكتب العامة';
      case AiChatScopeType.officeClient:
        return _entityLabel();
    }
  }

  String get welcomeLabel {
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'هذه المحادثة تخص حسابك الحالي فقط';
      case AiChatScopeType.officeGlobal:
        return 'هذه محادثة المكتب العامة';
      case AiChatScopeType.officeClient:
        return 'هذه محادثة العميل ${_entityLabel()}';
    }
  }

  String buildSystemScopeInstruction({required bool canWrite}) {
    switch (type) {
      case AiChatScopeType.ownerSelf:
        return 'نطاق هذه المحادثة هو هذا الحساب الحالي فقط. '
            'تعامل فقط مع البيانات الموجودة داخل هذا الحساب، '
            'ولا تعرض بيانات مكتب عامة أو بيانات أي عميل آخر.';
      case AiChatScopeType.officeGlobal:
        return 'نطاق هذه المحادثة هو المكتب العام. '
            'يمكنك التعامل مع بيانات المكتب الكاملة حسب الصلاحية الحالية، '
            'ولا تخلط هذه المحادثة مع محادثات العملاء الفردية.';
      case AiChatScopeType.officeClient:
        final entity = _entityLabel();
        if (canWrite) {
          return 'نطاق هذه المحادثة مقصور على العميل المحدد فقط: $entity. '
              'يمكنك القراءة والكتابة داخل بيانات هذا العميل فقط وفق قيود التطبيق، '
              'لكن لا تطلع على بيانات المكتب العامة ولا بيانات أي عميل آخر، '
              'ولا تستخدم أدوات المكتب العامة من هذه المحادثة.';
        }
        return 'نطاق هذه المحادثة مقصور على العميل المحدد فقط: $entity. '
            'هذه الجلسة للقراءة فقط داخل بيانات هذا العميل، '
            'ولا يجوز إظهار بيانات المكتب العامة أو بيانات أي عميل آخر، '
            'ولا تنفيذ أي كتابة من هذه المحادثة.';
    }
  }

  String _entityLabel() {
    final normalizedLabel = (label ?? '').trim();
    if (normalizedLabel.isNotEmpty) return normalizedLabel;
    final normalizedId = scopeId.trim();
    if (normalizedId.isNotEmpty) return normalizedId;
    return 'العميل الحالي';
  }
}

class AiChatService {
  static String get _apiUrl => AiOpenAiConfig.apiUrl;
  static const String _storagePrefix = 'ai_chat_history_v2';
  static const int _maxVisibleMessagesForFullContext = 8;
  static const int _recentVisibleMessagesToKeep = 6;
  static const int _summaryVisibleMessagesToInclude = 6;
  static const int _summaryLineCharLimit = 120;
  static final http.Client _httpClient = http.Client();

  // المفتاح يُحفظ هنا مؤقتاً — يجب نقله لـ Firestore أو Cloud Function لاحقاً
  static String _apiKey = '';
  static final ValueNotifier<AiChatApiKeyStatus> _apiKeyStatusNotifier =
      ValueNotifier<AiChatApiKeyStatus>(AiChatApiKeyStatus.unknown);

  static ValueListenable<AiChatApiKeyStatus> get apiKeyStatusListenable =>
      _apiKeyStatusNotifier;
  static AiChatApiKeyStatus get apiKeyStatus => _apiKeyStatusNotifier.value;

  static void setApiKey(String key) {
    _apiKey = key.trim();
    _apiKeyStatusNotifier.value = _hasConfiguredTransport
        ? AiChatApiKeyStatus.ready
        : AiChatApiKeyStatus.missing;
  }

  static void _applyCompileTimeTransportIfAvailable() {
    if (AiOpenAiConfig.usesServerProxy) {
      _apiKeyStatusNotifier.value = AiChatApiKeyStatus.ready;
      return;
    }

    final compileTimeKey = AiOpenAiConfig.openAiDirectApiKey.trim();
    if (compileTimeKey.isNotEmpty && _apiKey != compileTimeKey) {
      _apiKey = compileTimeKey;
    }
    if (_apiKey.isNotEmpty) {
      _apiKeyStatusNotifier.value = AiChatApiKeyStatus.ready;
    }
  }

  static bool get _hasConfiguredTransport {
    _applyCompileTimeTransportIfAvailable();
    return AiOpenAiConfig.usesServerProxy || _apiKey.trim().isNotEmpty;
  }

  static void markApiKeyLoading() {
    if (_hasConfiguredTransport) return;
    _apiKeyStatusNotifier.value = AiChatApiKeyStatus.loading;
  }

  static void markApiKeyMissing() {
    if (AiOpenAiConfig.usesServerProxy || AiOpenAiConfig.hasDirectApiKey) {
      _applyCompileTimeTransportIfAvailable();
      return;
    }
    _apiKey = '';
    _apiKeyStatusNotifier.value = AiChatApiKeyStatus.missing;
  }

  static void markApiKeyError() {
    if (AiOpenAiConfig.usesServerProxy || AiOpenAiConfig.hasDirectApiKey) {
      _applyCompileTimeTransportIfAvailable();
      return;
    }
    _apiKey = '';
    _apiKeyStatusNotifier.value = AiChatApiKeyStatus.error;
  }

  static bool get hasApiKey => _hasConfiguredTransport;

  static Future<AiChatApiKeyStatus> refreshApiKeyFromRemote() async {
    _applyCompileTimeTransportIfAvailable();
    if (_hasConfiguredTransport) return apiKeyStatus;

    if (!AiOpenAiConfig.allowFirestoreOpenAiKeyFallback) {
      markApiKeyMissing();
      return apiKeyStatus;
    }

    markApiKeyLoading();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('_meta')
          .doc('openai')
          .get()
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) {
        markApiKeyMissing();
        return apiKeyStatus;
      }
      final key = (snap.data()?['api_key'] ?? '').toString().trim();
      if (key.isEmpty) {
        markApiKeyMissing();
        return apiKeyStatus;
      }
      setApiKey(key);
      return apiKeyStatus;
    } catch (_) {
      markApiKeyError();
      return apiKeyStatus;
    }
  }

  static String configurationMessage() {
    _applyCompileTimeTransportIfAvailable();
    switch (apiKeyStatus) {
      case AiChatApiKeyStatus.loading:
      case AiChatApiKeyStatus.unknown:
        return 'جاري تهيئة الشات الآن. انتظر قليلًا ثم أعد المحاولة.';
      case AiChatApiKeyStatus.missing:
        return 'لم يتم ضبط اتصال الذكاء الاصطناعي. اضبط DARFO_AI_PROXY_URL للإنتاج أو OPENAI_API_KEY للتجربة.';
      case AiChatApiKeyStatus.error:
        return 'تعذر قراءة إعدادات الشات. تحقق من اتصال الإنترنت أو من إعدادات DARFO_AI_PROXY_URL / OPENAI_API_KEY.';
      case AiChatApiKeyStatus.ready:
        if (hasApiKey) return '';
        return 'تهيئة الشات غير مكتملة حاليًا.';
    }
  }

  static Map<String, String> _buildRequestHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (!AiOpenAiConfig.usesServerProxy && _apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_apiKey.trim()}';
    }
    return headers;
  }

  final List<ChatMessage> _history = [];
  String? _pendingRequestContext;
  final ChatUserRole userRole;
  final String userName;
  final String userId;
  final bool isOfficeMode;
  final AiChatScope chatScope;

  AiChatService({
    required this.userRole,
    required this.userName,
    required this.userId,
    required this.isOfficeMode,
    AiChatScope? chatScope,
  }) : chatScope = chatScope ??
            (isOfficeMode
                ? AiChatScope.officeGlobal(
                    officeUid: userId,
                    officeName: userName,
                  )
                : AiChatScope.ownerSelf(
                    ownerUid: userId,
                    ownerName: userName,
                  )) {
    _history.add(ChatMessage(
      role: 'system',
      content: _buildSystemPrompt(),
    ));
  }

  List<ChatMessage> get history => visibleMessages;

  List<ChatMessage> get visibleMessages => _history
      .where(
        (m) =>
            m.role == 'user' ||
            (m.role == 'assistant' && (m.content?.trim().isNotEmpty ?? false)),
      )
      .toList(growable: false);

  String get _storageKey {
    final mode = chatScope.usesOfficeModeForArchitecture ? 'office' : 'home';
    final normalizedUserId =
        userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$_storagePrefix:$mode:$normalizedUserId:${chatScope.storageTypeKey}:${chatScope.normalizedScopeId}';
  }

  bool _isVisibleMessage(ChatMessage message) {
    return message.role == 'user' ||
        (message.role == 'assistant' &&
            (message.content?.trim().isNotEmpty ?? false));
  }

  String _latestUserMessage() {
    for (var i = _history.length - 1; i >= 0; i--) {
      final message = _history[i];
      if (message.role == 'user') {
        return (message.content ?? '').trim();
      }
    }
    return '';
  }

  List<Map<String, dynamic>> _buildRequestMessages() {
    final fullHistory =
        _history.map((message) => message.toJson()).toList(growable: true);
    final visibleCount = visibleMessages.length;
    if (visibleCount <= _maxVisibleMessagesForFullContext) {
      return _withPendingRequestContext(fullHistory);
    }

    final recentStartIndex =
        _findRawStartIndexForLastVisibleMessages(_recentVisibleMessagesToKeep);
    if (recentStartIndex <= 1) return _withPendingRequestContext(fullHistory);

    final olderVisibleMessages = _history
        .sublist(1, recentStartIndex)
        .where(_isVisibleMessage)
        .toList(growable: false);
    final summary = _buildOlderConversationSummary(olderVisibleMessages);
    if (summary.isEmpty) return _withPendingRequestContext(fullHistory);

    final requestMessages = <ChatMessage>[
      _history.first,
      ChatMessage(role: 'system', content: summary),
      ..._history.sublist(recentStartIndex),
    ];
    return _withPendingRequestContext(
      requestMessages
          .map((message) => message.toJson())
          .toList(growable: true),
    );
  }

  List<Map<String, dynamic>> _withPendingRequestContext(
    List<Map<String, dynamic>> messages,
  ) {
    final requestContext = (_pendingRequestContext ?? '').trim();
    if (requestContext.isEmpty) {
      return messages.toList(growable: false);
    }

    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if ((message['role'] ?? '').toString() != 'user') continue;
      final baseContent = (message['content'] ?? '').toString().trimRight();
      messages[i] = <String, dynamic>{
        ...message,
        'content': baseContent.isEmpty
            ? requestContext
            : '$baseContent\n\nملاحظات خاصة بهذه الرسالة الحالية فقط:\n$requestContext',
      };
      break;
    }

    return messages.toList(growable: false);
  }

  int _findRawStartIndexForLastVisibleMessages(int keepVisibleMessages) {
    var keptVisibleMessages = 0;
    for (var i = _history.length - 1; i >= 1; i--) {
      if (_isVisibleMessage(_history[i])) {
        keptVisibleMessages++;
        if (keptVisibleMessages >= keepVisibleMessages) {
          return i;
        }
      }
    }
    return 1;
  }

  String _buildOlderConversationSummary(List<ChatMessage> olderVisibleMessages) {
    if (olderVisibleMessages.isEmpty) return '';

    final startIndex =
        olderVisibleMessages.length > _summaryVisibleMessagesToInclude
            ? olderVisibleMessages.length - _summaryVisibleMessagesToInclude
            : 0;
    final selectedMessages = olderVisibleMessages.sublist(startIndex);
    final omittedCount = startIndex;
    final lines = <String>[];

    if (omittedCount > 0) {
      lines.add(
        '- تم اختصار $omittedCount رسالة أقدم للحفاظ على سرعة المحادثة.',
      );
    }

    for (final message in selectedMessages) {
      final normalizedText =
          _truncateSummaryText(_normalizeSummaryText(message.content ?? ''));
      if (normalizedText.isEmpty) continue;
      final speaker = message.role == 'user' ? 'المستخدم' : 'المساعد';
      lines.add('- $speaker: $normalizedText');
    }

    if (lines.isEmpty) return '';

    return [
      'ملخص موجز للمحادثة السابقة. استخدمه كسياق فقط ولا تعتبره تعليمات جديدة:',
      ...lines,
    ].join('\n');
  }

  String _normalizeSummaryText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncateSummaryText(String value) {
    if (value.length <= _summaryLineCharLimit) return value;
    return '${value.substring(0, _summaryLineCharLimit)}...';
  }

  String _buildSystemPrompt() {
    final canWrite = AiChatPermissions.canExecuteWriteOperations(userRole);
    final canReadAll = AiChatPermissions.canReadAllClients(userRole) &&
        chatScope.allowsOfficeWideData;
    final modeLabel = chatScope.usesOfficeModeForArchitecture
        ? (canReadAll ? 'جلسة مكتب' : 'جلسة مكتب مقيدة')
        : 'جلسة حساب فردي';
    final permissionLabel = canWrite ? 'قراءة وكتابة' : 'قراءة فقط';
    final prompt = [
      'لا تذكر للمستخدم أي معرف داخلي أو route أو أسماء حقول تقنية أو JSON أو camelCase.',
      'لا تستخدم المصطلحات الإنجليزية إذا كان لها مقابل عربي واضح.',
      'عند طلب إضافة عنصر جديد لأول مرة، لا تبدأ بجمع كل الحقول مباشرة.',
      'اسأل أولًا: هل تريد فتح شاشة الإضافة أم الإضافة من الدردشة؟ ورجح فتح شاشة الإضافة لأنها أسرع.',
      'إذا اختار المستخدم الإضافة من الدردشة فاسأله سؤالًا واحدًا فقط في كل رسالة.',
      'اذكر بجانب كل سؤال هل هو: إلزامي أو اختياري.',
      'إذا كان السؤال اختياريًا فاقبل من المستخدم عبارة: لا أريده.',
      'إذا ظهرت missingFields أو requiredFields فاسأل عن أول حقل ناقص مناسب، ولا تسرد القائمة كاملة إلا إذا طلب المستخدم.',
      'إذا كانت المرفقات مطلوبة أو متاحة فاذكر أن الدردشة تدعم رفع حتى 3 مرفقات في الرسالة.',
      'عند قراءة نتائج الأدوات، لخص المعنى العملي فقط مثل الدفعة الحالية والمتأخرات والحالة والإجراء التالي.',
      'عند السؤال عن عدد العقارات، اعتبر العمارة ذات الوحدات عقارًا رئيسيًا واحدًا، ثم افصل وحداتها المضافة والمشغولة والمتاحة داخل الإجابة.',
      'عند الإجابة عن العقارات، فرّق دائمًا بين العقار الرئيسي والوحدة داخل عمارة، ولا تعدّ الوحدة داخل العمارة عقارًا مستقلاً ضمن الإجمالي العام.',
      'عند السؤال الدقيق عن عقد أو دفعاته أو أقساطه أو المتبقي أو المسدد أو الدفعة الحالية أو القادمة، استخدم get_contract_details أولًا ثم get_contract_invoice_history قبل الإجابة النهائية.',
      'عند السؤال في جلسة المكتب عن إجماليات العقارات أو العقود أو بيانات جميع العملاء، استخدم get_office_dashboard أولًا.',
      'عند السؤال في جلسة المكتب عن عميل محدد وعقاراته أو عقوده أو تفاصيله، استخدم get_office_client_details أولًا ثم ابنِ الإجابة على ملخص مساحة العمل الخاص به إن كان متاحًا.',
      'إذا أوضحت الأداة أن بيانات مساحة العمل غير متاحة لعميل مكتب معين، فاذكر ذلك صراحة ولا تخمّن عقاراته أو عقوده أو تقاريره.',
      'عند سؤال المستخدم عن التقارير أو الإيرادات أو المصروفات أو أرصدة الملاك أو المكتب، استخدم أدوات التقارير أولًا ثم أجب بالعربية الواضحة بحسب بيانات الشاشة الفعلية.',
      'إذا سأل المستخدم: كيف تكوّن هذا الرصيد؟ أو من أين جاءت هذه المصروفات/الإيرادات؟ فلا تكتفِ بالملخص. تتبّع الدفتر والسندات المرتبطة واذكر رقم السند ونوع الحركة ومصدرها والعقار والعقد والمستأجر متى كانت البيانات متاحة.',
      'عند سؤال المستخدم عن بند محدد داخل التقارير، اشرح سبب دخوله ضمن الإيرادات أو المصروفات أو التحويلات أو الخصومات اعتمادًا على السندات الفعلية لا على التخمين.',
      'إذا طلب المستخدم تنفيذ عملية من شاشة التقارير مثل خصم/تسوية مالك أو تحويل مالك أو مصروف/عمولة مكتب، اقرأ التقرير أو المعاينة المناسبة أولًا ثم استخدم أداة التنفيذ الصحيحة، ولا تدّعِ نجاح العملية قبل تنفيذها فعليًا.',
      'أنت مساعد دارفو لإدارة العقارات.',
      'اسم المستخدم: $userName',
      'تتحدث بالعربية فقط. كن مختصرًا وواضحًا.',
      'هذه الدردشة تنفذ عمليات حقيقية داخل التطبيق.',
      'لا تخترع حقولًا أو قيماً ناقصة.',
      'اجمع الحقول الإلزامية قبل أي عملية كتابة.',
      'إذا ظهرت missingFields أو validationError أو requiresScreenCompletion فاطلب النواقص بوضوح.',
      'استخدم get_app_blueprint فقط عند السؤال عن الشاشات أو الصلاحيات أو المسارات أو عند تعذر تحديد الأداة المناسبة.',
      'التواريخ بصيغة YYYY-MM-DD والمبالغ بالريال السعودي SAR.',
      'نوع الجلسة: $modeLabel.',
      'الصلاحية الحالية: $permissionLabel.',
      if (!canWrite)
        'لا تستخدم أدوات الكتابة ولا أدوات فتح شاشات الإدخال في هذه الجلسة.',
    ].join('\n');
    final scopeInstruction =
        chatScope.buildSystemScopeInstruction(canWrite: canWrite).trim();
    if (scopeInstruction.isEmpty) return prompt;
    return '$prompt\n\nنطاق المحادثة الحالي:\n$scopeInstruction';

    /* final buf = StringBuffer();
    buf.writeln('أنت مساعد دارفو الذكي، مساعد تطبيق دارفو لإدارة العقارات.');
    buf.writeln('اسم المستخدم: $userName');
    buf.writeln('تتحدث بالعربية فقط. كن مختصراً ومهنياً وودوداً.');
    buf.writeln('');

    if (isOfficeMode && canReadAll) {
      buf.writeln('أنت في وضع المكتب. تستطيع الاطلاع على بيانات جميع العملاء.');
      if (canWrite) {
        buf.writeln('تستطيع تنفيذ جميع العمليات (إضافة/تعديل/حذف) على أي عميل.');
      } else {
        buf.writeln(
            'حسابك للمشاهدة فقط. لا تنفذ أي عملية كتابة. أخبر المستخدم بذلك إذا طلب تعديل أو إضافة أو حذف.');
      }
    } else if (!canWrite) {
      buf.writeln(
          'المستخدم لديه صلاحية مشاهدة فقط. لا تنفذ أي عملية كتابة (إضافة/تعديل/حذف/إلغاء). أخبره بذلك إذا طلب.');
    } else {
      buf.writeln('أنت في وضع المالك. تستطيع تنفيذ جميع العمليات.');
    }

    buf.writeln('');
    buf.writeln('قواعد مهمة:');
    buf.writeln('- قبل أي عملية كتابة (إضافة/تعديل/حذف/إلغاء/أرشفة)، اعرض ملخصاً بالبيانات واطلب التأكيد صراحة.');
    buf.writeln('- إذا طلب المستخدم حذف شيء مرتبط ببيانات أخرى (مستأجر له عقود مثلاً)، حذّره.');
    buf.writeln('- عند الاستفسار، أعطِ إجابة مباشرة ومختصرة مع الأرقام والتفاصيل.');
    buf.writeln('- إذا لم تجد بيانات، قل ذلك بوضوح.');
    buf.writeln('- استخدم الأدوات المتاحة لك للوصول للبيانات وتنفيذ العمليات.');
    buf.writeln('- عند التحية، رحّب بالمستخدم باسمه.');
    buf.writeln('- عند إنشاء عقد، تأكد من وجود المستأجر والعقار أولاً.');
    buf.writeln('- عند إضافة مستأجر، اطلب الاسم ورقم الهوية والجوال كحد أدنى.');
    buf.writeln('- عند طلب تقرير أو إحصائية، اجمع البيانات من عدة أدوات وقدّم ملخصاً شاملاً.');
    buf.writeln('- المبالغ بالريال السعودي SAR.');
    buf.writeln('- التواريخ بصيغة YYYY-MM-DD.');
    buf.writeln('- الخدمات الدورية المتاحة: نظافة (cleaning)، مصعد (elevator)، إنترنت (internet)، مياه (water)، كهرباء (electricity).');
    buf.writeln('- عند السؤال عن خدمات عقار، استخدم get_property_services لعرض كل الخدمات المُعدة.');
    buf.writeln('- عند السؤال عن خدمة واحدة داخل عقار محدد، استخدم get_property_service_details ثم أجب بناءً على الإعدادات الفعلية للخدمة.');
    buf.writeln('- عند إنشاء خدمة دورية، اسأل عن العقار ونوع الخدمة ومقدم الخدمة والتكلفة.');
    buf.writeln('- عند تعديل عقد، ابحث برقم العقد التسلسلي (serialNo) وعدّل الحقول المطلوبة فقط.');
    buf.writeln('- عند تجديد عقد، أنشئ عقداً جديداً بنفس بيانات المستأجر والعقار مع تواريخ ومبالغ جديدة.');
    buf.writeln('- السندات اليدوية (manual voucher) لا تتطلب عقداً. يمكن ربطها بمستأجر أو عقار اختيارياً.');
    buf.writeln('- عند إضافة وحدة لعمارة، تأكد أن العقار من نوع عمارة (building).');
    buf.writeln('- عند طلب تقرير تفصيلي، استخدم أدوات التقارير المخصصة (properties_report, clients_report, contracts_report, services_report, invoices_report).');
    buf.writeln('- عند طلب الإشعارات، استخدم get_notifications لعرض الإشعارات الفعلية بكل أنواعها الحالية بدل الاكتفاء بملخص عام.');
    buf.writeln('- عند طلب فتح إشعار أو الانتقال إلى الشيء المرتبط به، استخدم open_notification_target مع notificationRef القادم من get_notifications.');
    buf.writeln('- عند طلب تعليم إشعار كمقروء أو إخفائه من القائمة، استخدم mark_notification_read مع notificationRef نفسه.');
    buf.writeln('- عند طلب مستخدمي المكتب، استخدم get_office_users_list أو get_office_user_details ولا تتجاوز صلاحياتهم أو حالات الحظر.');
    buf.writeln('- عند طلب سجل النشاط، استخدم get_activity_log مع الفلاتر المناسبة، وقد تُفرض onlyMine تلقائيًا حسب الصلاحية الفعلية.');
    buf.writeln('- عند طلب الإعدادات، استخدم get_settings لقراءة user_prefs الفعلية بدل الإجابة العامة.');
    buf.writeln('- عند طلب تعديل الإعدادات الأساسية، استخدم update_settings ولا تدّعِ نجاح أي تعديل قبل تنفيذ الأداة فعليًا.');
    buf.writeln('- عند طلب وحدات عمارة، استخدم get_building_units واذكر اسم العمارة.');
    buf.writeln('- يمكنك فلترة الفواتير حسب النوع (عقد/صيانة/يدوي) باستخدام get_invoices_by_type.');

    return buf.toString(); */
  }

  Future<String> sendMessage(
    String userMessage, {
    String? requestContext,
    void Function(String text)? onPartialText,
  }) async {
    if (!hasApiKey) {
      final errMsg = configurationMessage().isNotEmpty
          ? configurationMessage()
          : 'لم تكتمل تهيئة الشات بعد أو لم يتم تعيين مفتاح الخدمة.';
      _history.add(ChatMessage(role: 'user', content: userMessage));
      _history.add(ChatMessage(role: 'assistant', content: errMsg));
      _saveHistoryInBackground();
      return errMsg;
    }

    _history.add(ChatMessage(role: 'user', content: userMessage));
    _saveHistoryInBackground();

    try {
      _pendingRequestContext = requestContext?.trim();
      return await _callApi(onPartialText: onPartialText);
    } catch (e) {
      final errMsg = _buildConnectionFailureMessage(e);
      _history.add(ChatMessage(role: 'assistant', content: errMsg));
      _saveHistoryInBackground();
      return errMsg;
    } finally {
      _pendingRequestContext = null;
    }
  }

  Future<String> _callApi({void Function(String text)? onPartialText}) async {
    final tools = AiChatTools.getTools(
      isOfficeMode: chatScope.usesOfficeModeForArchitecture,
      canWrite: AiChatPermissions.canExecuteWriteOperations(userRole),
      canReadAll: AiChatPermissions.canReadAllClients(userRole) &&
          chatScope.allowsOfficeWideData,
      userMessage: _latestUserMessage(),
    );

    final selectedModel = AiOpenAiConfig.pickModelForMessage(_latestUserMessage());
    final body = <String, dynamic>{
      'model': selectedModel,
      'messages': _buildRequestMessages(),
    };
    if (AiOpenAiConfig.supportsTemperatureParameter(selectedModel)) {
      body['temperature'] = AiOpenAiConfig.temperature;
    }
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final streamedResponse = await _callApiStream(
      body,
      onPartialText: onPartialText,
    );
    if (streamedResponse != null) {
      if (streamedResponse.hasToolCalls) {
        _history.add(ChatMessage(
          role: 'assistant',
          toolCalls: streamedResponse.toolCalls,
        ));
        _saveHistoryInBackground();
        return '__TOOL_CALLS__';
      }

      final content = streamedResponse.content;
      if (content.isNotEmpty) {
        _history.add(ChatMessage(role: 'assistant', content: content));
        _saveHistoryInBackground();
        return content;
      }
    }

    return _callApiNonStream(body, onPartialText: onPartialText);
  }

  Future<String> _callApiNonStream(
    Map<String, dynamic> body, {
    void Function(String text)? onPartialText,
  }) async {
    final response = await _httpClient
        .post(
          Uri.parse(_apiUrl),
          headers: _buildRequestHeaders(),
          body: jsonEncode(body),
        )
        .timeout(AiOpenAiConfig.timeout);

    final serverErrMsg = _buildApiErrorMessage(response);
    if (response.statusCode != 200) {
      _history.add(ChatMessage(role: 'assistant', content: serverErrMsg));
      _saveHistoryInBackground();
      return serverErrMsg;
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final choice = (data['choices'] as List).first;
    final message = choice['message'];
    final finishReason = choice['finish_reason'];

    if (finishReason == 'tool_calls' && message['tool_calls'] != null) {
      final toolCalls =
          (message['tool_calls'] as List).cast<Map<String, dynamic>>();

      _history.add(ChatMessage(
        role: 'assistant',
        toolCalls: toolCalls,
      ));
      _saveHistoryInBackground();

      return '__TOOL_CALLS__';
    }

    final content = (message['content'] ?? '').toString();
    onPartialText?.call(content);
    _history.add(ChatMessage(role: 'assistant', content: content));
    _saveHistoryInBackground();
    return content;
  }

  Future<_AiChatStreamResponse?> _callApiStream(
    Map<String, dynamic> body, {
    void Function(String text)? onPartialText,
  }) async {
    final request = http.Request('POST', Uri.parse(_apiUrl));
    request.headers.addAll(_buildRequestHeaders());
    request.body = jsonEncode(<String, dynamic>{
      ...body,
      'stream': true,
    });

    final response = await _httpClient.send(request).timeout(AiOpenAiConfig.timeout);
    if (response.statusCode != 200) {
      final failedResponse = await http.Response.fromStream(response);
      return _AiChatStreamResponse(
        content: _buildApiErrorMessage(failedResponse),
      );
    }

    final contentBuffer = StringBuffer();
    final streamedToolCalls = <int, Map<String, dynamic>>{};
    var streamBuffer = '';
    var sawStreamEvent = false;
    var isDone = false;

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      streamBuffer += chunk;

      while (true) {
        final newlineIndex = streamBuffer.indexOf('\n');
        if (newlineIndex == -1) break;

        final rawLine = streamBuffer.substring(0, newlineIndex);
        streamBuffer = streamBuffer.substring(newlineIndex + 1);

        final line = rawLine.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') {
          isDone = true;
          break;
        }

        final decoded = _tryDecodeJsonMap(payload);
        if (decoded == null) continue;

        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;

        final choice = choices.first;
        if (choice is! Map) continue;

        final castedChoice = choice.cast<String, dynamic>();
        final delta = castedChoice['delta'];
        if (delta is! Map) continue;

        sawStreamEvent = true;

        final castedDelta = delta.cast<String, dynamic>();
        final contentPart = (castedDelta['content'] ?? '').toString();
        if (contentPart.isNotEmpty) {
          contentBuffer.write(contentPart);
          onPartialText?.call(contentBuffer.toString());
        }

        final rawToolCalls = castedDelta['tool_calls'];
        if (rawToolCalls is List) {
          for (final rawToolCall in rawToolCalls) {
            _mergeStreamToolCall(streamedToolCalls, rawToolCall);
          }
        }
      }

      if (isDone) break;
    }

    if (streamedToolCalls.isNotEmpty) {
      return _AiChatStreamResponse(
        toolCalls: _finalizeStreamToolCalls(streamedToolCalls),
      );
    }

    final content = contentBuffer.toString().trimRight();
    if (content.isNotEmpty) {
      return _AiChatStreamResponse(content: content);
    }

    if (sawStreamEvent) {
      return const _AiChatStreamResponse(content: '');
    }

    return null;
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  void _mergeStreamToolCall(
    Map<int, Map<String, dynamic>> accumulator,
    dynamic rawToolCall,
  ) {
    if (rawToolCall is! Map) return;

    final toolCall = rawToolCall.cast<String, dynamic>();
    final rawIndex = toolCall['index'];
    final index = rawIndex is int ? rawIndex : accumulator.length;

    final current = accumulator.putIfAbsent(index, () {
      return <String, dynamic>{
        'id': '',
        'type': 'function',
        'function': <String, dynamic>{
          'name': '',
          'arguments': '',
        },
      };
    });

    final id = (toolCall['id'] ?? '').toString();
    if (id.isNotEmpty) {
      current['id'] = id;
    }

    final type = (toolCall['type'] ?? '').toString();
    if (type.isNotEmpty) {
      current['type'] = type;
    }

    final rawFunction = toolCall['function'];
    if (rawFunction is! Map) return;

    final incomingFunction = rawFunction.cast<String, dynamic>();
    final currentFunction = current['function'] is Map<String, dynamic>
        ? current['function'] as Map<String, dynamic>
        : Map<String, dynamic>.from(current['function'] as Map);
    current['function'] = currentFunction;

    final namePart = (incomingFunction['name'] ?? '').toString();
    if (namePart.isNotEmpty) {
      currentFunction['name'] = _mergeNameFragment(
        (currentFunction['name'] ?? '').toString(),
        namePart,
      );
    }

    final argsPart = (incomingFunction['arguments'] ?? '').toString();
    if (argsPart.isNotEmpty) {
      currentFunction['arguments'] =
          '${(currentFunction['arguments'] ?? '').toString()}$argsPart';
    }
  }

  String _mergeNameFragment(String current, String incoming) {
    if (current.isEmpty) return incoming;
    if (incoming.isEmpty) return current;
    if (incoming.startsWith(current)) return incoming;
    if (current.endsWith(incoming)) return current;
    return '$current$incoming';
  }

  List<Map<String, dynamic>> _finalizeStreamToolCalls(
    Map<int, Map<String, dynamic>> accumulator,
  ) {
    final orderedKeys = accumulator.keys.toList()..sort();
    return orderedKeys.map((key) {
      final current = Map<String, dynamic>.from(accumulator[key]!);
      final rawFunction = current['function'];
      if (rawFunction is Map) {
        current['function'] = Map<String, dynamic>.from(rawFunction);
      }
      return current;
    }).toList(growable: false);
  }

  String _buildConnectionFailureMessage(Object error) {
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بالمساعد. تحقق من الإنترنت أو من إعدادات خادم الذكاء الاصطناعي ثم حاول مرة أخرى.';
    }
    return 'حدث خطأ في الاتصال بالمساعد. تحقق من الإنترنت أو من إعدادات الشات ثم حاول مرة أخرى.';
  }

  String _buildApiErrorMessage(http.Response response) {
    final status = response.statusCode;
    String details = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = (error['message'] ?? '').toString().trim();
          if (message.isNotEmpty) {
            details = message;
          }
        }
      }
    } catch (_) {}

    if (details.isNotEmpty) {
      return 'خطأ في الخادم ($status): $details';
    }
    return 'خطأ في الخادم ($status). حاول لاحقًا.';
  }

  List<Map<String, dynamic>>? getPendingToolCalls() {
    if (_history.isEmpty) return null;
    final last = _history.last;
    if (last.role == 'assistant' && last.toolCalls != null) {
      return last.toolCalls;
    }
    return null;
  }

  void addToolResult(String toolCallId, String result) {
    _history.add(ChatMessage(
      role: 'tool',
      content: result,
      toolCallId: toolCallId,
    ));
    _saveHistoryInBackground();
  }

  Future<String> continueAfterToolCalls({
    void Function(String text)? onPartialText,
  }) =>
      _callApi(onPartialText: onPartialText);

  void addLocalUserMessage(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _history.add(ChatMessage(role: 'user', content: value));
    _saveHistoryInBackground();
  }

  void addLocalAssistantMessage(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _history.add(ChatMessage(role: 'assistant', content: value));
    _saveHistoryInBackground();
  }

  Future<bool> restoreHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return false;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;

      final restored = decoded
          .whereType<Map>()
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .where((message) => message.role.isNotEmpty && message.role != 'system')
          .toList(growable: false);

      clearHistory(persist: false);
      _history.addAll(restored);
      return _history.length > 1;
    } catch (_) {
      await prefs.remove(_storageKey);
      return false;
    }
  }

  Future<void> deleteConversation() async {
    clearHistory(persist: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  void clearHistory({bool persist = true}) {
    final system = _history.first;
    _history.clear();
    _history.add(system);
    if (persist) _saveHistoryInBackground();
  }

  void _saveHistoryInBackground() {
    unawaited(_persistHistory());
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _history
        .where((message) => message.role != 'system')
        .map((message) => message.toJson())
        .toList(growable: false);
    await prefs.setString(_storageKey, jsonEncode(payload));
  }
}
