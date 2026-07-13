class ContentModerationException implements Exception {
  const ContentModerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ContentModeration {
  const ContentModeration._();

  static const Set<String> _blockedTerms = {
    'احتيال مضمون',
    'ارسل الرقم السري',
    'تحويل خارج التطبيق',
    'خطاب كراهية',
    'تهديد بالقتل',
    'محتوى اباحي',
    'ترويج مخدرات',
    'انتحال شخصية',
  };

  static void ensureAllowed(Iterable<String> values) {
    for (final value in values) {
      final normalized = _normalize(value);
      if (_blockedTerms.any(normalized.contains)) {
        throw const ContentModerationException(
          'يتضمن النص محتوى غير مسموح. عدّل النص ثم حاول مرة أخرى.',
        );
      }
    }
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}