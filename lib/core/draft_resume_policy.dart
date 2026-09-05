import 'models.dart';

const String draftSectionContract = 'contract';
const String draftSectionParties = 'parties';
const String draftSectionProperty = 'property';
const String draftSectionFinancial = 'financial';
const String draftSectionAttachments = 'attachments';

String draftSectionForStep(int step) => switch (step) {
      0 => draftSectionContract,
      1 || 3 => draftSectionProperty,
      2 => draftSectionParties,
      4 => draftSectionFinancial,
      5 => draftSectionAttachments,
      _ => draftSectionContract,
    };

bool draftHasContractData(ContractDraft draft) => <String>[
      draft.startDate,
      draft.endDate,
      draft.rentValue,
      draft.firstPaymentDate,
      draft.otherServices,
      draft.specialTerms,
    ].any(_hasText);

bool draftHasPartyData(ContractDraft draft) =>
    _partyHasData(draft.lessor) ||
    _partyHasData(draft.tenant) ||
    draft.representative.enabled ||
    <String>[
      draft.representative.fullName,
      draft.representative.idNumber,
      draft.representative.mobile,
      draft.representative.authorizationNumber,
    ].any(_hasText);

bool draftHasPropertyData(ContractDraft draft) {
  final property = draft.property;
  return <String>[
    property.ownershipDocumentNumber,
    property.ownershipDocumentDate,
    property.floorsCount,
    property.unitsPerFloor,
    property.totalUnits,
    property.district,
    property.street,
    property.buildingNumber,
    property.additionalNumber,
    property.postalCode,
    property.buildingName,
    property.unitNumber,
    property.unitName,
    property.floor,
    property.area,
    property.roomsCount,
    property.bathroomsCount,
    property.hallsCount,
    property.electricityMeter,
    property.waterMeter,
    property.gasMeter,
    property.notes,
  ].any(_hasText);
}

bool draftHasFinancialData(ContractDraft draft) => <String>[
      draft.startDate,
      draft.endDate,
      draft.rentValue,
      draft.securityDeposit,
      draft.brokerageFee,
      draft.vatValue,
      draft.otherAmounts,
      draft.firstPaymentDate,
      draft.electricity.fixedAmount,
      draft.electricity.currentReading,
      draft.water.fixedAmount,
      draft.water.currentReading,
      draft.gas.fixedAmount,
      draft.gas.currentReading,
      draft.otherServices,
      draft.specialTerms,
    ].any(_hasText);

bool draftHasAttachments(ContractDraft draft) =>
    draft.attachments.any((item) => item.uploaded);

int firstIncompleteDraftStep(ContractDraft draft) {
  final property = draft.property;
  if (!_allText(<String>[
    property.ownershipDocumentNumber,
    property.ownershipDocumentDate,
  ])) {
    return 1;
  }
  if (!_partyComplete(draft.lessor, isLessor: true) ||
      !_partyComplete(draft.tenant) ||
      !_representativeComplete(draft.representative)) {
    return 2;
  }
  if (!_allText(<String>[
        property.floorsCount,
        property.totalUnits,
        property.district,
        property.street,
        property.buildingNumber,
        property.additionalNumber,
        property.postalCode,
        property.unitNumber,
        property.unitName,
        property.floor,
        property.area,
        property.bathroomsCount,
        property.hallsCount,
        property.electricityMeter,
        property.waterMeter,
      ]) ||
      (draft.type == ContractType.residential &&
          !_hasText(property.roomsCount)) ||
      (!property.acWindow && !property.acSplit && !property.acCentral)) {
    return 3;
  }
  if (!_allText(<String>[
        draft.startDate,
        draft.endDate,
        draft.rentValue,
        draft.firstPaymentDate,
      ]) ||
      !draft.electricity.enabled ||
      !draft.water.enabled ||
      draft.paymentCount <= 0) {
    return 4;
  }
  final requiredAttachments = draft.attachments.where((attachment) {
    if (attachment.keyName == 'authorization') {
      return draft.representative.enabled;
    }
    if (attachment.keyName == 'iban') {
      return draft.paymentChannel.contains('سداد');
    }
    if (attachment.keyName == 'commercial_registration') {
      return draft.lessor.kind == PartyKind.company ||
          draft.tenant.kind == PartyKind.company;
    }
    return attachment.required;
  });
  if (requiredAttachments.any((item) => !item.uploaded)) return 5;
  return 6;
}

bool _partyHasData(PartyData party) => <String>[
      party.fullName,
      party.idNumber,
      party.birthDate,
      party.mobile,
      party.email,
      party.district,
      party.nationalAddress,
      party.commercialRegistration,
      party.unifiedNumber,
      party.authorizedPersonName,
      party.authorizedPersonId,
      party.iban,
      party.bankName,
      party.accountOwner,
    ].any(_hasText);

bool _partyComplete(PartyData party, {bool isLessor = false}) {
  final identityComplete = party.kind == PartyKind.individual
      ? _allText(<String>[
          party.fullName,
          party.idNumber,
          party.birthDate,
          party.mobile,
          party.district,
          party.nationalAddress,
        ])
      : _allText(<String>[
          party.fullName,
          party.commercialRegistration,
          party.unifiedNumber,
          party.authorizedPersonName,
          party.authorizedPersonId,
          party.mobile,
          party.district,
          party.nationalAddress,
        ]);
  if (!identityComplete || !party.mobileRegisteredInAbsher) return false;
  return !isLessor ||
      _allText(<String>[party.iban, party.bankName, party.accountOwner]);
}

bool _representativeComplete(RepresentativeData representative) =>
    !representative.enabled ||
    _allText(<String>[
      representative.fullName,
      representative.idNumber,
      representative.mobile,
      representative.authorizationNumber,
    ]);

bool _allText(Iterable<String> values) => values.every(_hasText);

bool _hasText(String value) => value.trim().isNotEmpty;
