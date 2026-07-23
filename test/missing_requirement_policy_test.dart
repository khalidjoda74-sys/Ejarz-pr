import 'package:flutter_test/flutter_test.dart';
import 'package:aqood_pro/core/missing_requirement_policy.dart';

void main() {
  test('review descriptions never claim a required upload is absent', () {
    final description = buildMissingReviewDescription(
      target: 'السجل التجاري',
      issue: MissingReviewIssue.unclear,
    );

    expect(description, contains('غير واضح'));
    expect(containsIllogicalMissingClaim(description), isFalse);
  });

  test('meter review asks for correction instead of completion', () {
    final description = buildMissingReviewDescription(
      target: 'رقم عداد الكهرباء',
      issue: MissingReviewIssue.unverifiable,
    );

    expect(description, contains('تعذر التحقق'));
    expect(description, contains('القيمة الصحيحة'));
    expect(containsIllogicalMissingClaim(description), isFalse);
  });
}
