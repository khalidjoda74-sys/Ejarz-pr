class AiErrorMapper {
  const AiErrorMapper();

  String mapToolError(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return 'تعذر تنفيذ الطلب حاليًا.';
    }
    if (normalized.contains('لا تملك صلاحية')) {
      return normalized;
    }
    if (normalized.contains('not supported')) {
      return 'هذه العملية غير مدعومة بعد من الدردشة.';
    }
    return normalized;
  }
}
