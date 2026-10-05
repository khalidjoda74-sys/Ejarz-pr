import 'package:aqdak/core/assistant/contract_assistant_controller.dart';
import 'package:aqdak/core/assistant/contract_field_catalog.dart';
import 'package:aqdak/core/contract_calculation_engine.dart';
import 'package:aqdak/core/firebase_repository.dart';
import 'package:aqdak/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assistant accepts omitted utility meters and property notes', () {
    for (final key in ['electricityMeter', 'waterMeter', 'gasMeter', 'notes']) {
      final field = ContractFieldCatalog.byPath['property.$key']!;
      expect(field.required, isFalse, reason: key);
      expect(ContractFieldCatalog.validate(field, '', {}), isNull);
      expect(ContractFieldCatalog.validate(field, null, {}), isNull);
    }
  });
  group('deterministic rental calculation', () {
    test('five years, 1000 monthly, quarterly = 20 x 3000', () {
      final result =
          ContractCalculationEngine.calculate(annualHalalas: 1200000, years: 5);
      expect(result.months, 60);
      expect(result.totalHalalas, 6000000);
      expect(result.installments, List.filled(20, 300000));
    });
    test('one year, 36000 annually, quarterly = 4 x 9000', () {
      final result =
          ContractCalculationEngine.calculate(annualHalalas: 3600000, years: 1);
      expect(result.installments, List.filled(4, 900000));
    });
    test('partial period and rounding preserve total exactly', () {
      for (var month = 0; month < 12; month++) {
        final result = ContractCalculationEngine.calculate(
            annualHalalas: 1000001, years: 1, months: month, days: 7);
        expect(
            result.installments.reduce((a, b) => a + b), result.totalHalalas);
        expect(result.installments.every((v) => v > 0), isTrue);
      }
    });
    test('single/custom installments, Arabic digits and invalid dates', () {
      expect(ContractCalculationEngine.money('١٢٬٠٠٠٫٥٠'), 1200050);
      expect(ContractCalculationEngine.money('-10'), isNull);
      expect(ContractCalculationEngine.date('2026/02/30'), isNull);
      expect(
          ContractCalculationEngine.formatDate(
              ContractCalculationEngine.addMonths(
                  DateTime.utc(2024, 1, 31), 1)),
          '2024/02/29');
      final single = ContractCalculationEngine.calculate(
          annualHalalas: 1200000, years: 5, singlePayment: true);
      expect(single.installments, [6000000]);
      final custom = ContractCalculationEngine.calculate(
          annualHalalas: 100, years: 1, customCount: 3);
      expect(custom.installments, [33, 34, 33]);
      expect(
          () => ContractCalculationEngine.calculate(annualHalalas: 1, years: 0),
          throwsFormatException);
    });
  });
  group('assistant patches', () {
    late ContractDraft draft;
    late ContractAssistantController controller;
    setUp(() {
      draft = ContractDraft();
      controller = ContractAssistantController(
          readDraft: () => draft,
          onApply: (value, _) => draft = value,
          onFocus: (_) {});
    });
    tearDown(() => controller.dispose());
    test('keeps long Arabic name and requires explicit confirmation', () {
      const name = 'خالد مصطفى أحمد محمد ياسين البلوشي القحطاني';
      final result = controller.apply([
        {'path': 'tenant.fullName', 'value': name}
      ], 0);
      expect(result['applied'], true);
      expect(draft.tenant.fullName, name);
      expect(controller.pending.single.path, 'tenant.fullName');
      controller.confirm('tenant.fullName');
      expect(controller.pending, isEmpty);
      expect(draft.assistantFields['tenant.fullName']?['status'], 'confirmed');
      final restored = FirebaseRepository.draftFromMap(
          FirebaseRepository.draftToMap(draft))!;
      expect(restored.assistantFields, draft.assistantFields);
    });
    test('manual edit defeats stale patch even before onChanged is observed',
        () {
      draft.tenant.fullName = 'كتابة يدوية';
      final result = controller.apply([
        {'path': 'tenant.fullName', 'value': 'صوت متأخر'}
      ], 0);
      expect(result['applied'], false);
      expect(draft.tenant.fullName, 'كتابة يدوية');
      expect(controller.canUndo, false);
    });
    test('unknown fields and legal consents are never writable', () {
      controller.apply([
        {'path': 'declarations.acceptTerms', 'value': 'true'},
        {'path': 'status', 'value': 'approved'}
      ], 0);
      expect(draft.acceptTerms, false);
      expect(controller.pending, isEmpty);
    });
    test('identity type plus number validate together; minors rejected', () {
      controller.apply([
        {'path': 'tenant.idType', 'value': 'إقامة'},
        {'path': 'tenant.idNumber', 'value': '2123456789'},
        {'path': 'tenant.birthDate', 'value': '2020/01/01'}
      ], 0);
      expect(draft.tenant.idNumber, '2123456789');
      expect(draft.tenant.birthDate, isEmpty);
      final result = controller.apply([
        {'path': 'tenant.idType', 'value': 'هوية وطنية'}
      ], controller.revision);
      expect(result['applied'], false);
      expect(draft.tenant.idType, 'إقامة');
    });
    test('multiple answers calculate schedule without approving values', () {
      controller.apply([
        {'path': 'duration.years', 'value': '5'},
        {'path': 'financial.rentValue', 'value': '12000'},
        {'path': 'financial.paymentFrequency', 'value': 'ربع سنوي'}
      ], 0);
      expect(draft.paymentCount, 20);
      expect(draft.installments.length, 20);
      expect(draft.installments.first.amount, '3000.00');
      expect(controller.pending, isNotEmpty);
      controller.undo();
      expect(draft.rentValue, isEmpty);
    });
    test('manual changes to uncatalogued consent cancel old responses/undo',
        () {
      controller.apply([
        {'path': 'tenant.fullName', 'value': 'خالد أحمد'}
      ], 0);
      final old = controller.revision;
      draft.acceptTerms = true;
      controller.manualChanged();
      expect(controller.revision, greaterThan(old));
      expect(controller.canUndo, false);
    });
    test('optional dependent fields are skipped', () {
      final data = controller.snapshot;
      expect(
          ContractFieldCatalog.applicable(
              ContractFieldCatalog.byPath['representative.fullName']!, data),
          false);
      expect(
          ContractFieldCatalog.applicable(
              ContractFieldCatalog.byPath['financial.securityDeposit']!, data),
          false);
      expect(
          ContractFieldCatalog.applicable(
              ContractFieldCatalog.byPath['tenant.iban']!, data),
          false);
    });
  });
}
