import 'package:ejarz_pro/data/services/comprehensive_reports_service.dart';
import 'package:ejarz_pro/models/property.dart';
import 'package:ejarz_pro/models/tenant.dart';
import 'package:ejarz_pro/ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle;
import 'package:ejarz_pro/ui/invoices_screen.dart' show Invoice;
import 'package:flutter_test/flutter_test.dart';

import '../support/operational_uat_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ComprehensiveReportsService', () {
    late OperationalUatHarness harness;

    setUpAll(() async {
      harness = await OperationalUatHarness.create(scopeUid: 'reports_logic');
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    setUp(() async {
      await harness.tenantsBox.clear();
      await harness.propertiesBox.clear();
      await harness.contractsBox.clear();
      await harness.invoicesBox.clear();
    });

    test('contract reports include partial paid amounts', () async {
      final property = Property(
        id: 'property_partial',
        name: 'Partial Property',
        type: PropertyType.apartment,
        address: 'Riyadh',
      );
      final tenant = Tenant(
        id: 'tenant_partial',
        fullName: 'Partial Tenant',
        nationalId: '1000000001',
        phone: '0500000001',
      );
      final contract = Contract(
        id: 'contract_partial',
        serialNo: 'C-PARTIAL',
        tenantId: tenant.id,
        propertyId: property.id,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        rentAmount: 1000,
        totalAmount: 1000,
        term: ContractTerm.annual,
        paymentCycle: PaymentCycle.annual,
      );
      final invoice = Invoice(
        id: 'invoice_partial',
        serialNo: 'V-PARTIAL',
        tenantId: tenant.id,
        contractId: contract.id,
        propertyId: property.id,
        issueDate: DateTime(2026, 1, 2),
        dueDate: DateTime(2026, 1, 1),
        amount: 1000,
        paidAmount: 300,
      );

      await harness.propertiesBox.put(property.id, property);
      await harness.tenantsBox.put(tenant.id, tenant);
      await harness.contractsBox.put(contract.id, contract);
      await harness.invoicesBox.put(invoice.id, invoice);

      final snapshot = await ComprehensiveReportsService.load(
        const ComprehensiveReportFilters(),
      );
      final row = snapshot.contracts.singleWhere(
        (item) => item.contractId == contract.id,
      );

      expect(row.paidAmount, 300);
      expect(row.remainingAmount, 700);
    });

    test('property net excludes owner payouts and office withdrawals',
        () async {
      final property = Property(
        id: 'property_net',
        name: 'Net Property',
        type: PropertyType.apartment,
        address: 'Jeddah',
      );
      final tenant = Tenant(
        id: 'tenant_net',
        fullName: 'Net Tenant',
        nationalId: '1000000002',
        phone: '0500000002',
      );
      final contract = Contract(
        id: 'contract_net',
        serialNo: 'C-NET',
        tenantId: tenant.id,
        propertyId: property.id,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        rentAmount: 1000,
        totalAmount: 1000,
        term: ContractTerm.annual,
        paymentCycle: PaymentCycle.annual,
      );
      final rentReceipt = Invoice(
        id: 'invoice_rent',
        serialNo: 'V-RENT',
        tenantId: tenant.id,
        contractId: contract.id,
        propertyId: property.id,
        issueDate: DateTime(2026, 1, 2),
        dueDate: DateTime(2026, 1, 1),
        amount: 1000,
        paidAmount: 1000,
      );
      final serviceExpense = Invoice(
        id: 'invoice_service_expense',
        serialNo: 'V-SERVICE',
        tenantId: '',
        contractId: '',
        propertyId: property.id,
        issueDate: DateTime(2026, 1, 3),
        dueDate: DateTime(2026, 1, 3),
        amount: -200,
        paidAmount: 200,
        note: '[SERVICE]\n[POSTED] service expense',
      );
      final ownerPayout = Invoice(
        id: 'invoice_owner_payout',
        serialNo: 'V-PAYOUT',
        tenantId: 'owner_1',
        contractId: '',
        propertyId: property.id,
        issueDate: DateTime(2026, 1, 4),
        dueDate: DateTime(2026, 1, 4),
        amount: -300,
        paidAmount: 300,
        note: '[OWNER_PAYOUT]\nowner=owner_1\n[POSTED] owner payout',
      );
      final officeWithdrawal = Invoice(
        id: 'invoice_office_withdrawal',
        serialNo: 'V-WITHDRAW',
        tenantId: '',
        contractId: '',
        propertyId: property.id,
        issueDate: DateTime(2026, 1, 5),
        dueDate: DateTime(2026, 1, 5),
        amount: -100,
        paidAmount: 100,
        note: '[OFFICE_WITHDRAWAL]\n[POSTED] office withdrawal',
      );

      await harness.propertiesBox.put(property.id, property);
      await harness.tenantsBox.put(tenant.id, tenant);
      await harness.contractsBox.put(contract.id, contract);
      await harness.invoicesBox.put(rentReceipt.id, rentReceipt);
      await harness.invoicesBox.put(serviceExpense.id, serviceExpense);
      await harness.invoicesBox.put(ownerPayout.id, ownerPayout);
      await harness.invoicesBox.put(officeWithdrawal.id, officeWithdrawal);

      final snapshot = await ComprehensiveReportsService.load(
        const ComprehensiveReportFilters(),
      );
      final row = snapshot.properties.singleWhere(
        (item) => item.propertyId == property.id,
      );

      expect(row.revenues, 1000);
      expect(row.expenses, 200);
      expect(row.net, 800);
    });
  });
}
