import 'package:aqood_pro/core/draft_resume_policy.dart';
import 'package:aqood_pro/core/app_controller.dart';
import 'package:aqood_pro/core/firebase_repository.dart';
import 'package:aqood_pro/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draft serialization restores every editable field', () {
    final source = ContractDraft()
      ..type = ContractType.commercial
      ..startDate = '2026/08/01'
      ..endDate = '2027/07/31'
      ..rentValue = '120000'
      ..brokerageFee = '4500'
      ..brokeragePayer = 'المؤجر'
      ..ownerSubjectToVat = true
      ..vatValue = '18000'
      ..otherAmounts = '750'
      ..paymentScheduleType = 'مخصص'
      ..firstPaymentDate = '2026/08/01'
      ..paymentMethod = PaymentMethod.bankTransfer
      ..acceptAccuracyDeclaration = true
      ..acceptDataSharing = true
      ..acceptTerms = true;
    source.property
      ..ownershipDocumentNumber = '310123456789'
      ..district = 'العليا';
    source.attachments.first
      ..uploaded = true
      ..fileName = 'identity.pdf';

    final restored = FirebaseRepository.draftFromMap(
      FirebaseRepository.draftToMap(source),
    );

    expect(restored, isNotNull);
    expect(restored!.type, ContractType.commercial);
    expect(restored.brokerageFee, '4500');
    expect(restored.brokeragePayer, 'المؤجر');
    expect(restored.ownerSubjectToVat, isTrue);
    expect(restored.vatValue, '18000');
    expect(restored.otherAmounts, '750');
    expect(restored.paymentScheduleType, 'مخصص');
    expect(restored.firstPaymentDate, '2026/08/01');
    expect(restored.paymentMethod, PaymentMethod.bankTransfer);
    expect(restored.acceptAccuracyDeclaration, isTrue);
    expect(restored.acceptDataSharing, isTrue);
    expect(restored.acceptTerms, isTrue);
    expect(restored.attachments.first.uploaded, isTrue);
    expect(restored.attachments.first.fileName, 'identity.pdf');
  });

  test('resume starts at the first incomplete step', () {
    final draft = ContractDraft();
    expect(firstIncompleteDraftStep(draft), 1);

    draft.property
      ..ownershipDocumentNumber = '310123456789'
      ..ownershipDocumentDate = '2026/06/20';
    expect(firstIncompleteDraftStep(draft), 2);
  });

  test('empty draft sections contain no user data', () {
    final draft = ContractDraft();
    expect(draftHasContractData(draft), isFalse);
    expect(draftHasPartyData(draft), isFalse);
    expect(draftHasPropertyData(draft), isFalse);
    expect(draftHasFinancialData(draft), isFalse);
    expect(draftHasAttachments(draft), isFalse);
  });

  test('saving and submitting a local draft keeps the same id', () async {
    final controller = AppController();
    final draft = ContractDraft();
    final first = await controller.saveDraft(draft);
    final savedAgain = await controller.saveDraft(
      draft,
      draftId: first.id,
      progress: const DraftProgress(lastStep: 1),
    );

    expect(savedAgain.id, first.id);
    expect(
      controller.contracts.where((item) => item.id == first.id).length,
      1,
    );

    final submitted = await controller.submitContract(
      draft,
      draftId: first.id,
    );
    expect(submitted.id, first.id);
    expect(submitted.status, ContractStatus.awaitingPayment);
    expect(
      controller.contracts.where((item) => item.id == first.id).length,
      1,
    );
    controller.dispose();
  });
}
