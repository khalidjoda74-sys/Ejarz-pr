import 'dart:io';

import 'package:darvoo/data/constants/boxes.dart';
import 'package:darvoo/data/services/user_scope.dart';
import 'package:darvoo/models/property.dart';
import 'package:darvoo/models/tenant.dart';
import 'package:darvoo/ui/contracts_screen.dart' show ContractAdapter;
import 'package:darvoo/ui/invoices_screen.dart' show InvoiceAdapter;
import 'package:darvoo/ui/maintenance_screen.dart'
    show
        MaintenancePriorityAdapter,
        MaintenanceRequestAdapter,
        MaintenanceStatusAdapter;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Future<Directory> initAiTestHive(String prefix) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp(prefix);
  Hive.init(dir.path);
  setFixedUid('ai_test');
  _registerAdapters();
  return dir;
}

Future<void> closeAiTestHive(Directory dir) async {
  clearFixedUid();
  await Hive.close();
  if (dir.existsSync()) {
    await dir.delete(recursive: true);
  }
}

void _registerAdapters() {
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

Future<void> openAiCoreBoxes() async {
  await Hive.openBox<Map>(boxName('aiPendingActionsBox'));
  await Hive.openBox<Map>(boxName('aiAuditLogsBox'));
}

Future<void> openDomainBoxes() async {
  await Hive.openBox<Property>(boxName(kPropertiesBox));
  await Hive.openBox<Tenant>(boxName(kTenantsBox));
}
