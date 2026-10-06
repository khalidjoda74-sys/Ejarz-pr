import 'package:aqdak/core/draft_sync_policy.dart';
import 'package:aqdak/core/models.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only connection failures are queued; conflicts stay visible', () {
    for (final code in [
      'aborted',
      'permission-denied',
      'failed-precondition',
      'invalid-argument'
    ]) {
      expect(
          canQueueDraftSave(
              FirebaseFunctionsException(code: code, message: code)),
          isFalse);
    }
    for (final code in [
      'unavailable',
      'deadline-exceeded',
      'network-request-failed'
    ]) {
      expect(
          canQueueDraftSave(
              FirebaseException(plugin: 'cloud_firestore', code: code)),
          isTrue);
    }
    expect(canQueueDraftSave(StateError('unexpected')), isFalse);
  });

  test(
      'conflict recovery keeps edited content and attachments in a separate draft',
      () {
    final original = ContractDraft()
      ..serverRevision = 123
      ..submissionId = 'old-request'
      ..rentValue = '12000'
      ..specialTerms = 'بيانات اختبار'
      ..acceptAccuracyDeclaration = true
      ..acceptDataSharing = true
      ..acceptTerms = true;
    original.tenant.fullName = 'مستأجر الاختبار';
    original.property.ownershipDocumentDate = '2026/10/01';
    original.attachments.first
      ..uploaded = true
      ..fileName = 'test.pdf'
      ..downloadUrl = 'https://example.com/test.pdf';
    final copy = forkConflictedDraft(original);
    expect(copy.serverRevision, isNull);
    expect(copy.submissionId, isEmpty);
    expect(copy.rentValue, '12000');
    expect(copy.tenant.fullName, 'مستأجر الاختبار');
    expect(copy.property.ownershipDocumentDate, '2026/10/01');
    expect(copy.attachments.first.downloadUrl,
        original.attachments.first.downloadUrl);
    expect(copy.attachments.first.uploaded, isTrue);
    expect(copy.acceptTerms, isFalse);
    expect(original.acceptTerms, isTrue);
    expect(original.serverRevision, 123);
    copy.tenant.fullName = 'اسم آخر';
    expect(original.tenant.fullName, 'مستأجر الاختبار');
  });
}
