import '../ai_chat_permissions.dart';
import '../ai_chat_service.dart';
import 'ai_chat_types.dart';

class AiPermissionSnapshot {
  final String userId;
  final String scopeId;
  final String locale;
  final String timezone;
  final ChatUserRole role;
  final List<String> permissions;

  const AiPermissionSnapshot({
    required this.userId,
    required this.scopeId,
    required this.locale,
    required this.timezone,
    required this.role,
    required this.permissions,
  });
}

class AiPermissionGuard {
  const AiPermissionGuard();

  static const List<String> _allStandardPermissions = <String>[
    'properties.view',
    'properties.create',
    'properties.update',
    'units.view',
    'units.create',
    'units.update',
    'owners.view',
    'owners.create',
    'owners.update',
    'tenants.view',
    'tenants.create',
    'tenants.update',
    'contracts.view',
    'contracts.create',
    'contracts.update',
    'contracts.terminate',
    'invoices.view',
    'invoices.create',
    'payments.view',
    'payments.create',
    'payments.reverse',
    'maintenance.view',
    'maintenance.create',
    'maintenance.update',
    'expenses.view',
    'expenses.create',
    'reports.view',
    'reports.financial',
    'exports.create',
    'app.help',
    'app.navigate',
  ];

  AiPermissionSnapshot buildSnapshot({
    required String userId,
    required ChatUserRole role,
    required AiChatScope chatScope,
    String locale = 'ar',
    String timezone = 'Africa/Cairo',
  }) {
    return AiPermissionSnapshot(
      userId: userId.trim(),
      scopeId: chatScope.normalizedScopeId,
      locale: locale,
      timezone: timezone,
      role: role,
      permissions: permissionsForRole(role),
    );
  }

  List<String> permissionsForRole(ChatUserRole role) {
    switch (role) {
      case ChatUserRole.owner:
      case ChatUserRole.officeOwner:
        return List<String>.from(_allStandardPermissions);
      case ChatUserRole.officeStaff:
        return const <String>[
          'properties.view',
          'units.view',
          'owners.view',
          'tenants.view',
          'contracts.view',
          'invoices.view',
          'payments.view',
          'maintenance.view',
          'expenses.view',
          'reports.view',
          'reports.financial',
          'app.help',
          'app.navigate',
        ];
      case ChatUserRole.officeClient:
      case ChatUserRole.viewOnly:
        return const <String>[
          'properties.view',
          'units.view',
          'tenants.view',
          'contracts.view',
          'invoices.view',
          'maintenance.view',
          'reports.view',
          'app.help',
        ];
    }
  }

  bool hasPermission(
    AiPermissionSnapshot snapshot,
    String permission,
  ) {
    return snapshot.permissions.contains(permission);
  }

  bool canExecuteTool(
    AiPermissionSnapshot snapshot,
    AiToolDefinition definition,
  ) {
    if (definition.requiredPermissions.isEmpty) return true;
    for (final permission in definition.requiredPermissions) {
      if (!hasPermission(snapshot, permission)) return false;
    }
    return true;
  }

  String denyMessage(AiToolDefinition definition) {
    if (definition.operationType == AiToolOperationType.report ||
        definition.operationType == AiToolOperationType.export) {
      return 'لا تملك صلاحية الوصول إلى هذا التقرير أو التصدير من هذه المحادثة.';
    }
    return 'لا تملك صلاحية تنفيذ هذا الإجراء من هذه المحادثة.';
  }
}
