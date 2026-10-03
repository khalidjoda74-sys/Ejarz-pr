import 'dart:typed_data';
import 'package:aqdak/core/contract_files.dart';
import 'package:aqdak/core/document_links.dart';
import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploads reject empty, oversized and disguised files', () {
    expect(() => ContractFiles.contentType('x.pdf', Uint8List(0)),
        throwsFormatException);
    expect(
        () => ContractFiles.contentType(
            'x.pdf', Uint8List(ContractFiles.maxBytes + 1)),
        throwsFormatException);
    expect(
        () => ContractFiles.contentType('x.pdf', Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
    expect(
        ContractFiles.contentType(
            'x.PDF', Uint8List.fromList('%PDF-1.4'.codeUnits)),
        'application/pdf');
    expect(
        ContractFiles.contentType(
            'x.jpg', Uint8List.fromList([255, 216, 255, 0])),
        'image/jpeg');
  });
  test('only safe HTTPS document links are opened', () {
    for (final value in [
      'javascript:alert(1)',
      'file:///secret',
      'http://example.com/a',
      'https://user:pass@example.com/a',
      'attachment.pdf'
    ]) {
      expect(safeDocumentUri(value), isNull);
    }
    expect(safeDocumentUri(ContractFiles.demoPdf), isNotNull);
  });
  test('draft copy and serialization preserve download links', () {
    final draft = ContractDraft();
    draft.attachments.first
      ..uploaded = true
      ..fileName = 'sample.pdf'
      ..downloadUrl = ContractFiles.demoPdf;
    expect(FirebaseRepository.attachmentFilesFromDraft(draft).values,
        contains(ContractFiles.demoPdf));
    final attachment =
        FirebaseRepository.attachmentToMap(draft.attachments.first);
    expect(attachment['downloadUrl'], ContractFiles.demoPdf);
  });
}
