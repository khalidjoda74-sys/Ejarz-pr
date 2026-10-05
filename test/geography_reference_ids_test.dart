import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:aqdak/core/saudi_reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('location reference IDs survive property, party and draft round trips',
      () {
    final property = PropertyData(
        city: 'الرياض',
        district: 'النرجس',
        cityReferenceId: 'municipal_21282',
        districtReferenceId: 'municipal_999');
    final draft = ContractDraft()..property = property;
    draft.lessor = PartyData(
        city: 'جدة',
        district: 'الزمرد',
        cityReferenceId: 'municipal_18394',
        districtReferenceId: 'municipal_123');
    final copy = ContractDraft.copyOf(draft);
    final restored =
        FirebaseRepository.draftFromMap(FirebaseRepository.draftToMap(copy))!;
    expect(restored.property.cityReferenceId, property.cityReferenceId);
    expect(
        restored.lessor.districtReferenceId, draft.lessor.districtReferenceId);
    expect(copy.property.cityReferenceId, property.cityReferenceId);
    expect(copy.lessor.districtReferenceId, draft.lessor.districtReferenceId);
    final party = FirebaseRepository.partyFromMap(
        FirebaseRepository.partyDataToMap(draft.lessor));
    expect(party.cityReferenceId, draft.lessor.cityReferenceId);
    final document = FirebaseRepository.propertyDocumentData(
        propertyId: 'property',
        uid: 'customer',
        contractId: 'contract',
        data: property);
    expect(document['cityReferenceId'], property.cityReferenceId);
    expect((document['address'] as Map)['districtReferenceId'],
        property.districtReferenceId);
    final map = FirebaseRepository.propertyDataToMap(property);
    expect(map['districtReferenceId'], property.districtReferenceId);
  });
  test('ambiguous legacy city names are not bound to an arbitrary city',
      () async {
    final catalog = await SaudiReferenceCatalog.load();
    final names = <String, int>{};
    for (final city in catalog.cities) {
      names.update(city.name, (count) => count + 1, ifAbsent: () => 1);
    }
    final ambiguous = names.entries.firstWhere((entry) => entry.value > 1).key;
    expect(catalog.resolveCity(ambiguous), isNull);
  });
}
