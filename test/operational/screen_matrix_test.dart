import 'package:darvoo/ui/ai_chat/ai_chat_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/operational_uat_harness.dart';

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.map<Map<String, dynamic>>((item) => _map(item)).toList();
}

Map<String, dynamic> _byKey(
  List<Map<String, dynamic>> items,
  String key,
) {
  return items.firstWhere((item) => item['key'] == key);
}

void _expectScreenStatus(
  Map<String, dynamic> screen, {
  String? read,
  String? write,
  String? navigation,
  String? overall,
}) {
  final validation = _map(screen['validation']);
  if (read != null) expect(validation['read'], read);
  if (write != null) expect(validation['write'], write);
  if (navigation != null) expect(validation['navigation'], navigation);
  if (overall != null) expect(validation['overall'], overall);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Screen Matrix', () {
    late OperationalUatHarness harness;

    setUp(() async {
      harness = await OperationalUatHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('owner blueprint keeps shared and owner screens available without permission blocks', () async {
      final executor = harness.buildExecutor(ChatUserRole.owner);
      final blueprint = await harness.runObject(executor, 'get_app_blueprint');

      final completion = _map(blueprint['completionStatus']);
      expect(completion['estimatedCompletionPercent'], 100);
      expect(completion['validationMatrixReady'], true);

      final matrix = _map(blueprint['finalValidationMatrix']);
      final summary = _map(matrix['summary']);
      final screenStatuses = _map(summary['screenStatuses']);
      final moduleStatuses = _map(summary['moduleStatuses']);
      final screens = _list(matrix['screens']);
      final modules = _list(matrix['modules']);

      expect(matrix['mode'], 'owner');
      expect(screenStatuses['blockedByPermission'], 0);
      expect(moduleStatuses['blockedByPermission'], 0);

      final home = _byKey(screens, 'home');
      _expectScreenStatus(
        home,
        read: 'available',
        write: 'not_supported',
        navigation: 'direct_navigation',
        overall: 'read_only',
      );

      final properties = _byKey(screens, 'properties');
      _expectScreenStatus(
        properties,
        read: 'available',
        write: 'available',
        navigation: 'direct_navigation',
        overall: 'full_access',
      );

      final tenants = _byKey(screens, 'tenants');
      _expectScreenStatus(
        tenants,
        read: 'available',
        write: 'available',
        navigation: 'direct_navigation',
        overall: 'full_access',
      );

      final contracts = _byKey(screens, 'contracts');
      _expectScreenStatus(
        contracts,
        read: 'available',
        write: 'available',
        navigation: 'direct_navigation',
        overall: 'full_access',
      );

      final invoicesHistory = _byKey(screens, 'invoices_history');
      _expectScreenStatus(
        invoicesHistory,
        read: 'available',
        write: 'not_supported',
        navigation: 'tool_with_required_args',
      );

      final propertyServices = _byKey(screens, 'property_services');
      _expectScreenStatus(
        propertyServices,
        read: 'available',
        write: 'available',
        navigation: 'tool_with_required_args',
      );

      final reports = _byKey(screens, 'reports');
      _expectScreenStatus(
        reports,
        read: 'available',
        write: 'available',
        navigation: 'direct_navigation',
        overall: 'full_access',
      );

      final notifications = _byKey(screens, 'notifications');
      _expectScreenStatus(
        notifications,
        read: 'available',
        write: 'not_supported',
        navigation: 'direct_navigation',
        overall: 'read_only',
      );

      final settings = _byKey(screens, 'settings');
      _expectScreenStatus(
        settings,
        read: 'available',
        write: 'available',
        navigation: 'supported_without_direct_navigation',
        overall: 'full_access',
      );

      final contractsModule = _byKey(modules, 'contracts');
      expect(_map(contractsModule['validation'])['overall'], 'full_access');

      final reportsModule = _byKey(modules, 'reports');
      expect(_map(reportsModule['validation'])['overall'], 'full_access');
    });

    test('office client blueprint blocks office-wide areas and all write screens', () async {
      final executor = harness.buildExecutor(ChatUserRole.officeClient);
      final blueprint = await harness.runObject(executor, 'get_app_blueprint');

      final permissions = _map(blueprint['permissions']);
      expect(permissions['canWrite'], false);
      expect(permissions['canReadAllClients'], false);

      final matrix = _map(blueprint['finalValidationMatrix']);
      final screens = _list(matrix['screens']);
      final modules = _list(matrix['modules']);

      expect(matrix['mode'], 'office');

      final office = _byKey(screens, 'office');
      _expectScreenStatus(
        office,
        read: 'blocked_by_permission',
        write: 'not_supported',
        navigation: 'blocked_by_permission',
        overall: 'blocked_by_permission',
      );

      final officeClients = _byKey(screens, 'office_clients');
      _expectScreenStatus(
        officeClients,
        read: 'blocked_by_permission',
        write: 'blocked_by_permission',
        navigation: 'not_available',
        overall: 'blocked_by_permission',
      );

      final officeUsers = _byKey(screens, 'office_users');
      _expectScreenStatus(
        officeUsers,
        read: 'blocked_by_permission',
        write: 'blocked_by_permission',
        navigation: 'not_available',
        overall: 'blocked_by_permission',
      );

      final activityLog = _byKey(screens, 'activity_log');
      _expectScreenStatus(
        activityLog,
        read: 'blocked_by_permission',
        write: 'not_supported',
        navigation: 'not_available',
        overall: 'blocked_by_permission',
      );

      final properties = _byKey(screens, 'properties');
      _expectScreenStatus(
        properties,
        read: 'available',
        write: 'blocked_by_permission',
        navigation: 'direct_navigation',
        overall: 'read_only',
      );

      final contractsNew = _byKey(screens, 'contracts_new');
      _expectScreenStatus(
        contractsNew,
        read: 'not_supported',
        write: 'blocked_by_permission',
        navigation: 'blocked_by_permission',
        overall: 'blocked_by_permission',
      );

      final settings = _byKey(screens, 'settings');
      _expectScreenStatus(
        settings,
        read: 'available',
        write: 'blocked_by_permission',
        navigation: 'supported_without_direct_navigation',
        overall: 'read_only',
      );

      final officeDashboardModule = _byKey(modules, 'office_dashboard');
      expect(
        _map(officeDashboardModule['validation'])['overall'],
        'blocked_by_permission',
      );

      final reportsModule = _byKey(modules, 'reports');
      expect(_map(reportsModule['validation'])['overall'], 'read_only');
    });
  });
}
