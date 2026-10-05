import 'package:aqdak/core/draft_resume_policy.dart';
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty meters and notes do not block resuming past the property step', () {
    final draft = ContractDraft();
    for (final party in [draft.lessor, draft.tenant]) {
      party
        ..fullName = 'خالد أحمد'
        ..idNumber = '1000000000'
        ..birthDate = '1990/01/01'
        ..mobile = '0500000000'
        ..district = 'العليا'
        ..nationalAddress = 'عنوان'
        ..mobileRegisteredInAbsher = true
        ..iban = 'SA0000000000000000000000'
        ..bankName = 'بنك'
        ..accountOwner = 'خالد أحمد';
    }
    draft.property
      ..ownershipDocumentNumber = '123'
      ..ownershipDocumentDate = '2026/01/01'
      ..floorsCount = '1'
      ..totalUnits = '1'
      ..district = 'العليا'
      ..street = 'شارع'
      ..buildingNumber = '1'
      ..additionalNumber = '1'
      ..postalCode = '12345'
      ..unitNumber = '1'
      ..unitName = 'شقة'
      ..floor = '0'
      ..area = '100'
      ..roomsCount = '2'
      ..bathroomsCount = '1'
      ..hallsCount = '0'
      ..acSplit = true
      ..electricityMeter = ''
      ..waterMeter = ''
      ..gasMeter = ''
      ..notes = '';
    expect(firstIncompleteDraftStep(draft), 4);
  });
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
      ..district = 'العليا'
      ..acWindow = true
      ..acWindowCount = '2'
      ..acSplit = true
      ..acSplitCount = '2'
      ..acCentral = true
      ..acCentralCount = '3';
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
    expect(restored.property.acWindowCount, '2');
    expect(restored.property.acSplitCount, '2');
    expect(restored.property.acCentralCount, '3');
  });

  test('older drafts with yes/no air conditioning remain readable', () {
    final saved = FirebaseRepository.draftToMap(ContractDraft());
    final property = Map<String, Object?>.from(saved['property'] as Map);
    property.remove('acWindowCount');
    property.remove('acSplitCount');
    property.remove('acCentralCount');
    property['acWindow'] = true;
    property['acSplit'] = false;
    property['acCentral'] = false;
    saved['property'] = property;
    final restored = FirebaseRepository.draftFromMap(saved)!.property;
    expect(restored.acWindowCount, '1');
    expect(restored.acSplitCount, '0');
    expect(restored.acCentralCount, '0');
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
