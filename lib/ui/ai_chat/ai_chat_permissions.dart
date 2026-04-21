import 'package:firebase_auth/firebase_auth.dart';

import '../../data/services/office_client_guard.dart';

enum ChatUserRole {
  owner,
  officeOwner,
  officeStaff,
  officeClient,
  viewOnly,
}

class AiChatPermissions {
  AiChatPermissions._();

  static const Duration _roleCacheTtl = Duration(minutes: 5);
  static ChatUserRole? _cachedRole;
  static String _cachedRoleUserId = '';
  static DateTime? _cachedRoleAt;

  static Future<ChatUserRole> resolveRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cachedRole = ChatUserRole.viewOnly;
      _cachedRoleUserId = '';
      _cachedRoleAt = DateTime.now();
      return ChatUserRole.viewOnly;
    }

    final userId = user.uid.trim();
    final cachedAt = _cachedRoleAt;
    if (_cachedRole != null &&
        _cachedRoleUserId == userId &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) <= _roleCacheTtl) {
      return _cachedRole!;
    }

    ChatUserRole resolvedRole = ChatUserRole.owner;
    try {
      final token = await user.getIdTokenResult();
      final role = (token.claims?['role'] ?? '').toString().toLowerCase();

      if (role == 'office' || role == 'office_owner') {
        resolvedRole = ChatUserRole.officeOwner;
      } else if (role == 'office_staff') {
        resolvedRole = ChatUserRole.officeStaff;
      }
    } catch (_) {}

    if (resolvedRole == ChatUserRole.owner) {
      final isClient = await OfficeClientGuard.isOfficeClient();
      if (isClient) {
        resolvedRole = ChatUserRole.officeClient;
      }
    }

    _cachedRole = resolvedRole;
    _cachedRoleUserId = userId;
    _cachedRoleAt = DateTime.now();
    return resolvedRole;
  }

  static bool canExecuteWriteOperations(ChatUserRole role) {
    switch (role) {
      case ChatUserRole.owner:
      case ChatUserRole.officeOwner:
        return true;
      case ChatUserRole.officeStaff:
      case ChatUserRole.officeClient:
      case ChatUserRole.viewOnly:
        return false;
    }
  }

  static bool canReadAllClients(ChatUserRole role) {
    return role == ChatUserRole.officeOwner ||
        role == ChatUserRole.officeStaff;
  }

  static bool isReadOnlyRole(ChatUserRole role) {
    return !canExecuteWriteOperations(role);
  }

  static String denyMessage(ChatUserRole role) {
    switch (role) {
      case ChatUserRole.officeClient:
        return 'هذا الحساب تابع لعميل المكتب وهو للمشاهدة فقط. يمكنك السؤال والاطلاع ضمن ما يسمح به هذا الحساب، لكن لا يمكن تنفيذ عمليات إضافة أو تعديل أو حذف.';
      case ChatUserRole.officeStaff:
        return 'ليس لديك صلاحية لتنفيذ هذا الإجراء من هذا الحساب. يمكنك القراءة على بيانات المكتب المسموح بها فقط.';
      case ChatUserRole.viewOnly:
        return 'ليس لديك صلاحية لتنفيذ هذا الإجراء. حسابك للمشاهدة فقط.';
      case ChatUserRole.owner:
      case ChatUserRole.officeOwner:
        return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
  }
}
