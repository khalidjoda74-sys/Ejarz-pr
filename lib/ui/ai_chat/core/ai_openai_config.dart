class AiOpenAiConfig {
  AiOpenAiConfig._();

  static const String modelFast = String.fromEnvironment(
    'OPENAI_MODEL_FAST',
    defaultValue: 'gpt-5.4',
  );
  static const String modelDefault = String.fromEnvironment(
    'OPENAI_MODEL_DEFAULT',
    defaultValue: 'gpt-5.4',
  );
  static const String modelReasoning = String.fromEnvironment(
    'OPENAI_MODEL_REASONING',
    defaultValue: 'gpt-5.4',
  );
  static const String modelReports = String.fromEnvironment(
    'OPENAI_MODEL_REPORTS',
    defaultValue: 'gpt-5.4',
  );

  /// Prefer a server-side proxy / Cloud Function for all AI calls.
  /// The Flutter client must not contain or download the OpenAI API key in production.
  /// The proxy should accept the same Chat Completions JSON body and return OpenAI-compatible JSON/SSE.
  static const String serverProxyUrl = String.fromEnvironment(
    'DARFO_AI_PROXY_URL',
    defaultValue: '',
  );

  /// Development-only direct API key. Do not put a production OpenAI key in the mobile app.
  /// Example:
  /// flutter run --dart-define=ALLOW_CLIENT_OPENAI_DIRECT=true --dart-define=OPENAI_API_KEY=sk-...
  static const String openAiDirectApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  /// Development-only escape hatch. Keep false in production builds.
  static const bool allowClientOpenAiDirect = bool.fromEnvironment(
    'ALLOW_CLIENT_OPENAI_DIRECT',
    defaultValue: false,
  );

  /// Legacy compatibility for older installs that stored the key in Firestore _meta/openai.
  /// It remains supported, but the recommended production setup is DARFO_AI_PROXY_URL.
  static const bool allowFirestoreOpenAiKeyFallback = bool.fromEnvironment(
    'ALLOW_FIRESTORE_OPENAI_KEY_FALLBACK',
    defaultValue: true,
  );

  static const String openAiDirectApiUrl = String.fromEnvironment(
    'OPENAI_API_URL',
    defaultValue: 'https://api.openai.com/v1/chat/completions',
  );

  static bool get usesServerProxy => serverProxyUrl.trim().isNotEmpty;

  static bool get hasDirectApiKey => openAiDirectApiKey.trim().isNotEmpty;

  static bool get canUseDirectOpenAi =>
      allowClientOpenAiDirect || allowFirestoreOpenAiKeyFallback || hasDirectApiKey;

  static String get apiUrl => usesServerProxy
      ? serverProxyUrl.trim()
      : openAiDirectApiUrl.trim();

  static const String temperatureRaw = String.fromEnvironment(
    'OPENAI_TEMPERATURE',
    defaultValue: '0.1',
  );
  static const String maxToolStepsRaw = String.fromEnvironment(
    'OPENAI_MAX_TOOL_STEPS',
    defaultValue: '2',
  );
  static const String timeoutMsRaw = String.fromEnvironment(
    'OPENAI_TIMEOUT_MS',
    defaultValue: '45000',
  );

  static double get temperature {
    final value = double.tryParse(temperatureRaw.trim()) ?? 0.1;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  static int get maxToolSteps {
    final value = int.tryParse(maxToolStepsRaw.trim()) ?? 2;
    if (value < 1) return 1;
    if (value > 4) return 4;
    return value;
  }

  static Duration get timeout => Duration(
        milliseconds: int.tryParse(timeoutMsRaw.trim()) ?? 45000,
      );

  static String pickModelForMessage(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) return modelDefault;
    if (_containsAny(normalized, const <String>[
      'تقرير',
      'تقارير',
      'تقاارير',
      'متأخرات',
      'متاخرات',
      'تحصيل',
      'مالي',
      'رصيد',
      'أرصدة',
      'ارصدة',
    ])) {
      return modelReports;
    }
    if (_containsAny(normalized, const <String>[
      'عقد',
      'عقود',
      'دفعة',
      'دفعات',
      'سداد',
      'صيانة',
      'صيانه',
      'خدمة دورية',
      'خدمه دوريه',
      'حلل',
      'اربط',
      'صحح',
    ])) {
      return modelReasoning;
    }
    if (_containsAny(normalized, const <String>[
      'كيف',
      'وين',
      'أين',
      'اشرح',
      'شرح',
      'افتح',
    ])) {
      return modelFast;
    }
    return modelDefault;
  }

  static bool supportsTemperatureParameter(String model) {
    final normalizedModel = model.trim().toLowerCase();
    return !normalizedModel.startsWith('gpt-5');
  }

  static bool _containsAny(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (text.contains(pattern)) return true;
    }
    return false;
  }
}
