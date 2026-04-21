import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:darvoo/data/constants/boxes.dart';
import 'package:darvoo/data/services/hive_service.dart';
import 'package:darvoo/data/services/user_scope.dart';
import 'package:darvoo/firebase_options.dart';
import 'package:darvoo/models/property.dart';
import 'package:darvoo/models/tenant.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_executor.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_permissions.dart';
import 'package:darvoo/ui/contracts_screen.dart'
    show Contract, ContractAdapter, kDailyContractEndHourField;
import 'package:darvoo/ui/invoices_screen.dart' show Invoice, InvoiceAdapter;
import 'package:darvoo/ui/maintenance_screen.dart'
    show
        MaintenancePriorityAdapter,
        MaintenanceRequest,
        MaintenanceRequestAdapter,
        MaintenanceStatusAdapter;
import 'package:darvoo/utils/ksa_time.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OperationalVisualSeed {
  const OperationalVisualSeed({
    required this.primaryPropertyId,
    required this.primaryPropertyName,
    required this.tenantName,
    required this.providerName,
    required this.annualContractSerial,
    required this.dailyContractSerial,
    required this.invoiceSerial,
    required this.invoiceNote,
    required this.maintenanceTitle,
  });

  final String primaryPropertyId;
  final String primaryPropertyName;
  final String tenantName;
  final String providerName;
  final String annualContractSerial;
  final String dailyContractSerial;
  final String invoiceSerial;
  final String invoiceNote;
  final String maintenanceTitle;
}

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform({
    List<ConnectivityResult> initial = const <ConnectivityResult>[
      ConnectivityResult.wifi,
    ],
  }) : _current = List<ConnectivityResult>.from(initial) {
    _controller.add(_current);
  }

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> _current;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  Future<void> dispose() async {
    await _controller.close();
  }
}

class OperationalUatHarness {
  OperationalUatHarness._(
    this._tempDir,
    this.scopeUid,
    this._previousConnectivityPlatform,
    this._fakeConnectivityPlatform,
  );

  final Directory _tempDir;
  final String scopeUid;
  final ConnectivityPlatform _previousConnectivityPlatform;
  final _FakeConnectivityPlatform _fakeConnectivityPlatform;

  static Future<OperationalUatHarness> create({
    String scopeUid = 'uat_owner',
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (_) {}
    final tempDir =
        await Directory.systemTemp.createTemp('darvoo_operational_uat_');
    Hive.init(tempDir.path);
    _registerAdaptersIfNeeded();
    final previousConnectivityPlatform = ConnectivityPlatform.instance;
    final fakeConnectivityPlatform = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakeConnectivityPlatform;
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await _configureDownloadsMock(tempDir);
    setFixedUid(scopeUid);
    KsaTime.debugForceSynced();

    await HiveService.ensureReportsBoxesOpen();
    await Hive.openBox<Map>(boxName('servicesConfig'));
    await Hive.openBox<String>(boxName('contractsEjarNoMap'));
    await Hive.openBox(boxName(kSessionBox));
    await Hive.openBox<Map>(boxName('settingsBox'));
    await _primeSessionBox();

    return OperationalUatHarness._(
      tempDir,
      scopeUid,
      previousConnectivityPlatform,
      fakeConnectivityPlatform,
    );
  }

  static Future<void> _configureDownloadsMock(Directory tempDir) async {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('darvoo/downloads'),
      (MethodCall call) async {
        if (call.method != 'saveToDownloads') return null;
        final args = Map<String, dynamic>.from(
          (call.arguments as Map?) ?? const <String, dynamic>{},
        );
        final name = (args['fileName'] ?? 'mock-download.bin').toString();
        final file = File('${tempDir.path}${Platform.pathSeparator}$name');
        final rawBytes = args['bytes'];
        if (rawBytes is Uint8List) {
          await file.writeAsBytes(rawBytes, flush: true);
        } else {
          await file.writeAsBytes(const <int>[], flush: true);
        }
        return file.path;
      },
    );
  }

  static Future<void> _primeSessionBox() async {
    final session = Hive.box(boxName(kSessionBox));
    await session.put('useHijri', false);
    await session.put('isOfficeClient', false);
    await session.put('officeImpersonation', false);
    await session.put(kDailyContractEndHourField, 12);
    await session.put('notif_monthly_days', 7);
    await session.put('notif_quarterly_days', 15);
    await session.put('notif_semiannual_days', 30);
    await session.put('notif_annual_days', 45);
  }

  static void _registerAdaptersIfNeeded() {
    final propertyTypeAdapter = PropertyTypeAdapter();
    if (!Hive.isAdapterRegistered(propertyTypeAdapter.typeId)) {
      Hive.registerAdapter(propertyTypeAdapter);
    }

    final rentalModeAdapter = RentalModeAdapter();
    if (!Hive.isAdapterRegistered(rentalModeAdapter.typeId)) {
      Hive.registerAdapter(rentalModeAdapter);
    }

    final propertyAdapter = PropertyAdapter();
    if (!Hive.isAdapterRegistered(propertyAdapter.typeId)) {
      Hive.registerAdapter(propertyAdapter);
    }

    final tenantAdapter = TenantAdapter();
    if (!Hive.isAdapterRegistered(tenantAdapter.typeId)) {
      Hive.registerAdapter(tenantAdapter);
    }

    final contractAdapter = ContractAdapter();
    if (!Hive.isAdapterRegistered(contractAdapter.typeId)) {
      Hive.registerAdapter(contractAdapter);
    }

    final invoiceAdapter = InvoiceAdapter();
    if (!Hive.isAdapterRegistered(invoiceAdapter.typeId)) {
      Hive.registerAdapter(invoiceAdapter);
    }

    final maintenancePriorityAdapter = MaintenancePriorityAdapter();
    if (!Hive.isAdapterRegistered(maintenancePriorityAdapter.typeId)) {
      Hive.registerAdapter(maintenancePriorityAdapter);
    }

    final maintenanceStatusAdapter = MaintenanceStatusAdapter();
    if (!Hive.isAdapterRegistered(maintenanceStatusAdapter.typeId)) {
      Hive.registerAdapter(maintenanceStatusAdapter);
    }

    final maintenanceRequestAdapter = MaintenanceRequestAdapter();
    if (!Hive.isAdapterRegistered(maintenanceRequestAdapter.typeId)) {
      Hive.registerAdapter(maintenanceRequestAdapter);
    }
  }

  AiChatExecutor buildOwnerExecutor() {
    return AiChatExecutor(userRole: ChatUserRole.owner);
  }

  AiChatExecutor buildExecutor(ChatUserRole role) {
    return AiChatExecutor(userRole: role);
  }

  AiChatExecutor buildOfficeClientExecutor() {
    return AiChatExecutor(userRole: ChatUserRole.officeClient);
  }

  Future<OperationalVisualSeed> seedOwnerVisualScenario() async {
    final owner = buildOwnerExecutor();
    final now = KsaTime.dateOnly(KsaTime.now());
    final annualStart = now.subtract(const Duration(days: 40));
    final annualEnd = now.add(const Duration(days: 325));
    final dailyStart = now.add(const Duration(days: 1));
    final dailyEnd = now.add(const Duration(days: 5));
    final invoiceDue = now.subtract(const Duration(days: 2));
    final maintenanceDate = now;

    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    Future<void> expectSuccess(String functionName, Map<String, dynamic> args) async {
      final result = await runObject(owner, functionName, args);
      if (result['success'] != true) {
        throw StateError('Seed failed for $functionName: $result');
      }
    }

    await expectSuccess('add_tenant', <String, dynamic>{
      'clientType': 'serviceProvider',
      'fullName': 'Prime Services',
      'phone': '0500000001',
      'serviceSpecialization': 'maintenance',
    });

    await expectSuccess('add_tenant', <String, dynamic>{
      'clientType': 'tenant',
      'fullName': 'Ahmad Salem',
      'nationalId': '1234567890',
      'phone': '0500000002',
      'nationality': 'Saudi',
      'attachmentPaths': const <String>['/docs/tenant-ahmad.pdf'],
    });

    await expectSuccess('add_tenant', <String, dynamic>{
      'clientType': 'company',
      'companyName': 'Nour Trading',
      'companyCommercialRegister': '7001234567',
      'companyTaxNumber': '312345678900003',
      'companyRepresentativeName': 'Maha Noor',
      'companyRepresentativePhone': '0500000003',
      'attachmentPaths': const <String>['/docs/company-nour.pdf'],
    });

    await expectSuccess('add_property', <String, dynamic>{
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
      'documentDate': ymd(now.subtract(const Duration(days: 80))),
      'documentAttachmentPaths': const <String>['/docs/palm-villa.pdf'],
    });

    await expectSuccess('add_property', <String, dynamic>{
      'name': 'Cedar Building',
      'type': 'building',
      'address': 'Riyadh District 2',
      'rentalMode': 'perUnit',
      'totalUnits': 3,
      'floors': 3,
      'documentType': 'deed',
      'documentNumber': 'B-001',
      'documentDate': ymd(now.subtract(const Duration(days: 79))),
      'documentAttachmentPaths': const <String>['/docs/cedar-building.pdf'],
    });

    await expectSuccess('add_property', <String, dynamic>{
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
      'documentDate': ymd(now.subtract(const Duration(days: 78))),
      'documentAttachmentPaths': const <String>['/docs/sky-studio.pdf'],
    });

    await expectSuccess('add_building_unit', <String, dynamic>{
      'buildingName': 'Cedar Building',
      'unitName': 'Unit 101',
      'unitType': 'apartment',
      'rooms': 2,
      'area': 120,
      'price': 4500,
      'currency': 'SAR',
      'furnished': false,
    });

    final periodicCommands = <Map<String, dynamic>>[
      <String, dynamic>{
        'propertyName': 'Palm Villa',
        'serviceType': 'cleaning',
        'provider': 'Prime Services',
        'cost': 300,
        'nextDueDate': ymd(now.add(const Duration(days: 1))),
        'recurrenceMonths': 1,
        'remindBeforeDays': 1,
      },
      <String, dynamic>{
        'propertyName': 'Palm Villa',
        'serviceType': 'internet',
        'billingMode': 'separate',
      },
      <String, dynamic>{
        'propertyName': 'Palm Villa',
        'serviceType': 'water',
        'billingMode': 'separate',
        'meterNumber': '12345',
      },
      <String, dynamic>{
        'propertyName': 'Palm Villa',
        'serviceType': 'electricity',
        'billingMode': 'separate',
        'meterNumber': '54321',
      },
      <String, dynamic>{
        'propertyName': 'Cedar Building',
        'serviceType': 'cleaning',
        'provider': 'Prime Services',
        'cost': 700,
        'nextDueDate': ymd(now.add(const Duration(days: 2))),
        'recurrenceMonths': 1,
        'remindBeforeDays': 1,
      },
      <String, dynamic>{
        'propertyName': 'Cedar Building',
        'serviceType': 'elevator',
        'provider': 'Prime Services',
        'cost': 900,
        'nextDueDate': ymd(now.add(const Duration(days: 2))),
        'recurrenceMonths': 1,
        'remindBeforeDays': 1,
      },
      <String, dynamic>{
        'propertyName': 'Unit 101',
        'serviceType': 'internet',
        'billingMode': 'separate',
      },
      <String, dynamic>{
        'propertyName': 'Sky Studio',
        'serviceType': 'cleaning',
        'provider': 'Prime Services',
        'cost': 250,
        'nextDueDate': ymd(now),
        'recurrenceMonths': 1,
        'remindBeforeDays': 1,
      },
      <String, dynamic>{
        'propertyName': 'Sky Studio',
        'serviceType': 'internet',
        'billingMode': 'separate',
      },
      <String, dynamic>{
        'propertyName': 'Sky Studio',
        'serviceType': 'water',
        'billingMode': 'separate',
        'meterNumber': '33333',
      },
      <String, dynamic>{
        'propertyName': 'Sky Studio',
        'serviceType': 'electricity',
        'billingMode': 'separate',
        'meterNumber': '44444',
      },
    ];

    for (final command in periodicCommands) {
      await expectSuccess('create_periodic_service', command);
    }

    final annualContract = await runObject(owner, 'create_contract', <String, dynamic>{
      'tenantName': 'Ahmad Salem',
      'propertyName': 'Palm Villa',
      'startDate': ymd(annualStart),
      'endDate': ymd(annualEnd),
      'rentAmount': 24000,
      'totalAmount': 24000,
      'term': 'annual',
      'paymentCycle': 'monthly',
    });
    if (annualContract['success'] != true) {
      throw StateError('Seed failed for annual contract: $annualContract');
    }

    final dailyContract = await runObject(owner, 'create_contract', <String, dynamic>{
      'tenantName': 'Nour Trading',
      'propertyName': 'Sky Studio',
      'startDate': ymd(dailyStart),
      'endDate': ymd(dailyEnd),
      'rentAmount': 2500,
      'totalAmount': 2500,
      'term': 'daily',
      'dailyCheckoutHour': 12,
    });
    if (dailyContract['success'] != true) {
      throw StateError('Seed failed for daily contract: $dailyContract');
    }

    const invoiceNote = 'first installment visual';
    final invoice = await runObject(owner, 'create_invoice', <String, dynamic>{
      'contractSerialNo': annualContract['contractSerialNo'],
      'amount': 2000,
      'dueDate': ymd(invoiceDue),
      'note': invoiceNote,
    });
    if (invoice['success'] != true) {
      throw StateError('Seed failed for invoice: $invoice');
    }

    const maintenanceTitle = 'AC repair visual';
    final maintenance = await runObject(owner, 'create_maintenance_request', <String, dynamic>{
      'propertyName': 'Palm Villa',
      'title': maintenanceTitle,
      'requestType': 'repair',
      'priority': 'high',
      'scheduledDate': ymd(maintenanceDate),
      'executionDeadline': ymd(maintenanceDate),
      'cost': 500,
      'provider': 'Prime Services',
      'status': 'completed',
    });
    if (maintenance['success'] != true) {
      throw StateError('Seed failed for maintenance: $maintenance');
    }

    final primaryProperty = propertiesBox.values.firstWhere(
      (Property item) => item.name == 'Palm Villa',
    );

    return OperationalVisualSeed(
      primaryPropertyId: primaryProperty.id,
      primaryPropertyName: primaryProperty.name,
      tenantName: 'Ahmad Salem',
      providerName: 'Prime Services',
      annualContractSerial: annualContract['contractSerialNo'].toString(),
      dailyContractSerial: dailyContract['contractSerialNo'].toString(),
      invoiceSerial: invoice['invoiceSerialNo'].toString(),
      invoiceNote: invoiceNote,
      maintenanceTitle: maintenanceTitle,
    );
  }

  Future<Map<String, dynamic>> runObject(
    AiChatExecutor executor,
    String functionName, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    return decodeMap(await executor.execute(functionName, args));
  }

  Future<List<Map<String, dynamic>>> runList(
    AiChatExecutor executor,
    String functionName, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    return decodeList(await executor.execute(functionName, args));
  }

  Map<String, dynamic> decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    throw FormatException('Expected JSON object but got: $raw');
  }

  List<Map<String, dynamic>> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Expected JSON list but got: $raw');
    }
    return decoded.map<Map<String, dynamic>>((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      throw FormatException('Expected JSON list item to be a map: $item');
    }).toList(growable: false);
  }

  Box<Tenant> get tenantsBox => Hive.box<Tenant>(boxName(kTenantsBox));
  Box<Property> get propertiesBox => Hive.box<Property>(boxName(kPropertiesBox));
  Box<Contract> get contractsBox => Hive.box<Contract>(boxName(kContractsBox));
  Box<Invoice> get invoicesBox => Hive.box<Invoice>(boxName(kInvoicesBox));
  Box<MaintenanceRequest> get maintenanceBox =>
      Hive.box<MaintenanceRequest>(boxName(kMaintenanceBox));

  Future<void> dispose() async {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('darvoo/downloads'),
      null,
    );
    ConnectivityPlatform.instance = _previousConnectivityPlatform;
    await _fakeConnectivityPlatform.dispose();
    clearFixedUid();
    KsaTime.debugResetSyncForTesting();
    await Hive.close();
    if (_tempDir.existsSync()) {
      await _tempDir.delete(recursive: true);
    }
  }
}
