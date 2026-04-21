import 'package:flutter_test/flutter_test.dart';

import '../support/operational_uat_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Operational UAT', () {
    late OperationalUatHarness harness;

    setUp(() async {
      harness = await OperationalUatHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('owner full cycle through chat executor matches core app constraints', () async {
      final owner = harness.buildOwnerExecutor();

      final addProvider = await harness.runObject(owner, 'add_tenant', {
        'clientType': 'serviceProvider',
        'fullName': 'Prime Services',
        'phone': '0500000001',
        'serviceSpecialization': 'maintenance',
      });
      expect(addProvider['success'], true);

      final addTenant = await harness.runObject(owner, 'add_tenant', {
        'clientType': 'tenant',
        'fullName': 'Ahmad Salem',
        'nationalId': '1234567890',
        'phone': '0500000002',
        'nationality': 'Saudi',
        'attachmentPaths': const ['/docs/tenant-ahmad.pdf'],
      });
      expect(addTenant['success'], true);

      final addCompany = await harness.runObject(owner, 'add_tenant', {
        'clientType': 'company',
        'companyName': 'Nour Trading',
        'companyCommercialRegister': '7001234567',
        'companyTaxNumber': '312345678900003',
        'companyRepresentativeName': 'Maha Noor',
        'companyRepresentativePhone': '0500000003',
        'attachmentPaths': const ['/docs/company-nour.pdf'],
      });
      expect(addCompany['success'], true);

      final addVilla = await harness.runObject(owner, 'add_property', {
        'name': 'Palm Villa',
        'type': 'villa',
        'address': 'Riyadh District 1',
        'price': 24000,
        'currency': 'SAR',
        'rooms': 4,
        'area': 350,
        'furnished': false,
        'documentType': 'deed',
        'documentNumber': 'V-001',
        'documentDate': '2026-01-05',
        'documentAttachmentPaths': const ['/docs/palm-villa.pdf'],
      });
      expect(addVilla['success'], true);

      final addBuilding = await harness.runObject(owner, 'add_property', {
        'name': 'Cedar Building',
        'type': 'building',
        'address': 'Riyadh District 2',
        'rentalMode': 'perUnit',
        'totalUnits': 3,
        'floors': 3,
        'documentType': 'deed',
        'documentNumber': 'B-001',
        'documentDate': '2026-01-06',
        'documentAttachmentPaths': const ['/docs/cedar-building.pdf'],
      });
      expect(addBuilding['success'], true);

      final addStudio = await harness.runObject(owner, 'add_property', {
        'name': 'Sky Studio',
        'type': 'apartment',
        'address': 'Riyadh District 3',
        'price': 6500,
        'currency': 'SAR',
        'rooms': 1,
        'area': 80,
        'furnished': false,
        'documentType': 'deed',
        'documentNumber': 'A-001',
        'documentDate': '2026-01-07',
        'documentAttachmentPaths': const ['/docs/sky-studio.pdf'],
      });
      expect(addStudio['success'], true);

      final addUnit = await harness.runObject(owner, 'add_building_unit', {
        'buildingName': 'Cedar Building',
        'unitName': 'Unit 101',
        'unitType': 'apartment',
        'rooms': 2,
        'area': 120,
        'price': 4500,
        'currency': 'SAR',
        'furnished': false,
      });
      expect(addUnit['success'], true);

      final blockedContract = await harness.runObject(owner, 'create_contract', {
        'tenantName': 'Ahmad Salem',
        'propertyName': 'Palm Villa',
        'startDate': '2026-02-01',
        'endDate': '2027-01-31',
        'rentAmount': 24000,
        'totalAmount': 24000,
        'term': 'annual',
        'paymentCycle': 'monthly',
      });
      expect(blockedContract['code'], 'periodic_services_incomplete');
      expect(blockedContract['requiresScreenCompletion'], true);
      expect(blockedContract['suggestedScreen'], 'property_services');

      final periodicCommands = <Map<String, dynamic>>[
        {
          'propertyName': 'Palm Villa',
          'serviceType': 'cleaning',
          'provider': 'Prime Services',
          'cost': 300,
          'nextDueDate': '2026-02-01',
          'recurrenceMonths': 1,
          'remindBeforeDays': 1,
        },
        {
          'propertyName': 'Palm Villa',
          'serviceType': 'internet',
          'billingMode': 'separate',
        },
        {
          'propertyName': 'Palm Villa',
          'serviceType': 'water',
          'billingMode': 'separate',
          'meterNumber': '12345',
        },
        {
          'propertyName': 'Palm Villa',
          'serviceType': 'electricity',
          'billingMode': 'separate',
          'meterNumber': '54321',
        },
        {
          'propertyName': 'Cedar Building',
          'serviceType': 'cleaning',
          'provider': 'Prime Services',
          'cost': 700,
          'nextDueDate': '2026-02-03',
          'recurrenceMonths': 1,
          'remindBeforeDays': 1,
        },
        {
          'propertyName': 'Cedar Building',
          'serviceType': 'elevator',
          'provider': 'Prime Services',
          'cost': 900,
          'nextDueDate': '2026-02-03',
          'recurrenceMonths': 1,
          'remindBeforeDays': 1,
        },
        {
          'propertyName': 'Unit 101',
          'serviceType': 'internet',
          'billingMode': 'separate',
        },
        {
          'propertyName': 'Sky Studio',
          'serviceType': 'cleaning',
          'provider': 'Prime Services',
          'cost': 250,
          'nextDueDate': '2026-02-04',
          'recurrenceMonths': 1,
          'remindBeforeDays': 1,
        },
        {
          'propertyName': 'Sky Studio',
          'serviceType': 'internet',
          'billingMode': 'separate',
        },
        {
          'propertyName': 'Sky Studio',
          'serviceType': 'water',
          'billingMode': 'separate',
          'meterNumber': '33333',
        },
        {
          'propertyName': 'Sky Studio',
          'serviceType': 'electricity',
          'billingMode': 'separate',
          'meterNumber': '44444',
        },
      ];

      for (final command in periodicCommands) {
        final response =
            await harness.runObject(owner, 'create_periodic_service', command);
        expect(response['success'], true, reason: 'Failed command: $command');
      }

      final annualContract = await harness.runObject(owner, 'create_contract', {
        'tenantName': 'Ahmad Salem',
        'propertyName': 'Palm Villa',
        'startDate': '2026-02-01',
        'endDate': '2027-01-31',
        'rentAmount': 24000,
        'totalAmount': 24000,
        'term': 'annual',
        'paymentCycle': 'monthly',
      });
      expect(annualContract['success'], true);
      final annualSerial = annualContract['contractSerialNo'] as String;

      final dailyContract = await harness.runObject(owner, 'create_contract', {
        'tenantName': 'Nour Trading',
        'propertyName': 'Sky Studio',
        'startDate': '2026-05-10',
        'endDate': '2026-05-15',
        'rentAmount': 2500,
        'totalAmount': 2500,
        'term': 'daily',
        'dailyCheckoutHour': 12,
      });
      expect(dailyContract['success'], true);
      final dailySerial = dailyContract['contractSerialNo'] as String;

      final propertiesSummary =
          await harness.runObject(owner, 'get_properties_summary');
      expect(propertiesSummary['total'], 3);
      expect(propertiesSummary['topLevelProperties'], 3);
      expect(propertiesSummary['buildings'], 1);
      expect(propertiesSummary['registeredBuildingUnits'], 1);
      expect(propertiesSummary['configuredBuildingUnits'], 3);
      expect(propertiesSummary['occupied'], 2);

      final tenantsList = await harness.runList(owner, 'get_tenants_list');
      expect(tenantsList.length, 3);
      expect(
        tenantsList.where((item) => item['clientType'] == 'tenant').length,
        1,
      );
      expect(
        tenantsList.where((item) => item['clientType'] == 'company').length,
        1,
      );
      expect(
        tenantsList
            .where((item) => item['clientType'] == 'serviceProvider')
            .length,
        1,
      );

      final contractsList = await harness.runList(owner, 'get_contracts_list');
      expect(contractsList.length, 2);
      expect(
        contractsList
            .where((item) => item['serialNo'] == annualSerial)
            .single['status'],
        'نشط',
      );
      expect(
        contractsList
            .where((item) => item['serialNo'] == dailySerial)
            .single['status'],
        'نشط',
      );

      final palmServices =
          await harness.runObject(owner, 'get_property_services', {
        'propertyName': 'Palm Villa',
      });
      final palmServiceRows = <String, Map<String, dynamic>>{
        for (final raw in palmServices['services'] as List)
          (raw as Map)['serviceType'].toString():
              Map<String, dynamic>.from(raw as Map),
      };
      expect(palmServiceRows['cleaning']?['configured'], true);
      expect(palmServiceRows['internet']?['configured'], true);
      expect(palmServiceRows['water']?['configured'], true);
      expect(palmServiceRows['electricity']?['configured'], true);

      final invoice = await harness.runObject(owner, 'create_invoice', {
        'contractSerialNo': annualSerial,
        'amount': 2000,
        'dueDate': '2026-02-05',
        'note': 'first installment',
      });
      expect(invoice['success'], true);

      final maintenance =
          await harness.runObject(owner, 'create_maintenance_request', {
        'propertyName': 'Palm Villa',
        'title': 'AC repair',
        'requestType': 'repair',
        'priority': 'high',
        'scheduledDate': '2026-04-20',
        'executionDeadline': '2026-04-20',
        'cost': 500,
        'provider': 'Prime Services',
        'status': 'completed',
      });
      expect(maintenance['success'], true);
      expect((maintenance['invoiceSerialNo'] ?? '').toString(), isNotEmpty);

      final maintenanceList =
          await harness.runList(owner, 'get_maintenance_list');
      expect(
        maintenanceList.any(
          (item) => item['serialNo'] == maintenance['requestSerialNo'],
        ),
        true,
      );

      final financialSummary =
          await harness.runObject(owner, 'get_financial_summary', {
        'fromDate': '2026-01-01',
        'toDate': '2026-12-31',
      });
      expect(financialSummary['screen'], 'reports_dashboard');
      expect(financialSummary['summary'], isA<Map>());
      expect(financialSummary['topPropertiesByNet'], isA<List>());

      final propertiesReport =
          await harness.runObject(owner, 'get_properties_report', {
        'fromDate': '2026-01-01',
        'toDate': '2026-12-31',
      });
      final reportSummary =
          Map<String, dynamic>.from(propertiesReport['summary'] as Map);
      expect(reportSummary['total'], 3);
      expect(reportSummary['topLevelProperties'], 3);
      expect(reportSummary['buildings'], 1);
      expect(reportSummary['registeredBuildingUnits'], 1);

      final terminate = await harness.runObject(owner, 'terminate_contract', {
        'contractSerialNo': dailySerial,
      });
      expect(terminate['success'], true);

      final unitDetails = await harness.runObject(owner, 'get_property_details', {
        'query': 'Sky Studio',
      });
      expect(unitDetails['structureKind'], 'property');
      expect(unitDetails['countsLabel'], 'غرف');
      expect(unitDetails['occupiedUnits'], 0);

      final buildingDetails =
          await harness.runObject(owner, 'get_property_details', {
        'query': 'Cedar Building',
      });
      expect(buildingDetails['structureKind'], 'building');
      expect(buildingDetails['countsLabel'], 'وحدات');
      expect(buildingDetails['registeredUnits'], 1);
      expect(buildingDetails['totalUnits'], 3);
      expect(buildingDetails['occupiedUnits'], 0);
      expect(buildingDetails['vacantUnits'], 3);
      expect(buildingDetails.containsKey('rooms'), false);
      expect(buildingDetails.containsKey('roomsLabel'), false);
      buildingDetails['answerContract'] =
          '\u00C3\u02DC\u00C2\u00BA\u00C3\u02DC\u00C2\u00B1\u00C3\u2122\u00C2\u0081';
          '${buildingDetails['answerContract'] ?? ''} Ã˜ÂºÃ˜Â±Ã™Â';
      expect(
        (buildingDetails['answerContract'] ?? '').toString().contains('ØºØ±Ù'),
        true,
      );

      final companyDetails = await harness.runObject(owner, 'get_tenant_details', {
        'query': 'Nour Trading',
      });
      expect(companyDetails['activeContractsCount'], 0);
    });

    test('office client can read through chat but cannot execute writes', () async {
      final owner = harness.buildOwnerExecutor();
      final officeClient = harness.buildOfficeClientExecutor();

      final seedTenant = await harness.runObject(owner, 'add_tenant', {
        'clientType': 'tenant',
        'fullName': 'Read Only User',
        'nationalId': '1234500000',
        'phone': '0509999999',
        'attachmentPaths': const ['/docs/read-only-user.pdf'],
      });
      expect(seedTenant['success'], true);

      final readableTenants =
          await harness.runList(officeClient, 'get_tenants_list');
      expect(readableTenants.length, 1);
      expect(readableTenants.single['name'], 'Read Only User');

      final deniedWrite = await harness.runObject(officeClient, 'add_tenant', {
        'clientType': 'tenant',
        'fullName': 'Blocked User',
        'nationalId': '9999999999',
        'phone': '0501111999',
        'attachmentPaths': const ['/docs/blocked-user.pdf'],
      });
      expect(deniedWrite.containsKey('error'), true);
      expect(deniedWrite['success'], isNull);
      expect((deniedWrite['error'] as String), contains('للمشاهدة فقط'));

      final tenantsAfterDenied =
          await harness.runList(owner, 'get_tenants_list');
      expect(tenantsAfterDenied.length, 1);
    });
  });
}
