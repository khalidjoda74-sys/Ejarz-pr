enum MissingReviewIssue {
  unclear,
  incorrect,
  expired,
  mismatch,
  unverifiable,
  additionalDocument,
  clarification,
}

extension MissingReviewIssueX on MissingReviewIssue {
  String get code => name;

  String get label => switch (this) {
        MissingReviewIssue.unclear => 'المستند غير واضح',
        MissingReviewIssue.incorrect => 'البيان أو المستند غير صحيح',
        MissingReviewIssue.expired => 'المستند منتهي الصلاحية',
        MissingReviewIssue.mismatch => 'غير مطابق لبيانات الطلب',
        MissingReviewIssue.unverifiable => 'تعذر التحقق من القيمة',
        MissingReviewIssue.additionalDocument => 'مطلوب مستند إضافي',
        MissingReviewIssue.clarification => 'مطلوب توضيح إضافي',
      };
}

String buildMissingReviewDescription({
  required String target,
  required MissingReviewIssue issue,
  String note = '',
}) {
  final title = target.trim();
  if (title.isEmpty) {
    throw ArgumentError.value(target, 'target', 'حدد المتطلب محل المراجعة');
  }
  final base = switch (issue) {
    MissingReviewIssue.unclear =>
      '$title المرفق غير واضح. يرجى إعادة رفع نسخة واضحة وكاملة.',
    MissingReviewIssue.incorrect =>
      '$title غير صحيح. يرجى مراجعته وإرسال البيانات أو المستند الصحيح.',
    MissingReviewIssue.expired =>
      '$title المرفق منتهي الصلاحية. يرجى رفع نسخة سارية.',
    MissingReviewIssue.mismatch =>
      '$title غير مطابق لبيانات الطلب. يرجى مراجعته وإرسال نسخة مطابقة.',
    MissingReviewIssue.unverifiable =>
      'تعذر التحقق من $title. يرجى مراجعته وإدخال القيمة الصحيحة.',
    MissingReviewIssue.additionalDocument =>
      'يلزم تقديم $title كمستند إضافي لاستكمال مراجعة الطلب.',
    MissingReviewIssue.clarification =>
      'نحتاج إلى توضيح إضافي بخصوص $title لاستكمال مراجعة الطلب.',
  };
  final detail = note.trim();
  return detail.isEmpty ? base : '$base ملاحظة الفريق: $detail';
}

bool containsIllogicalMissingClaim(String value) {
  return RegExp(
    r'(غير\s+مرفق|لم\s+يتم\s+إرفاق|غير\s+مكتمل|لم\s+يكتمل)',
    caseSensitive: false,
  ).hasMatch(value);
}
