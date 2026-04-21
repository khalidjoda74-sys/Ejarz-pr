import 'package:darvoo/ui/ai_chat/ai_chat_permissions.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_service.dart';
import 'package:darvoo/ui/ai_chat/core/ai_permission_guard.dart';
import 'package:darvoo/ui/ai_chat/core/ai_tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guard = AiPermissionGuard();
  const scope = AiChatScope.ownerSelf(ownerUid: 'owner_1', ownerName: 'Owner');

  test('owner gets write permissions while office client does not', () {
    final ownerSnapshot = guard.buildSnapshot(
      userId: 'owner_1',
      role: ChatUserRole.owner,
      chatScope: scope,
    );
    final clientSnapshot = guard.buildSnapshot(
      userId: 'client_1',
      role: ChatUserRole.officeClient,
      chatScope: const AiChatScope.officeClient(
        clientUid: 'client_1',
        clientName: 'Client',
      ),
    );

    expect(ownerSnapshot.permissions, contains('contracts.create'));
    expect(ownerSnapshot.permissions, contains('payments.create'));

    expect(clientSnapshot.permissions, isNot(contains('contracts.create')));
    expect(clientSnapshot.permissions, isNot(contains('payments.create')));
  });

  test('permission guard blocks write tool for office staff', () {
    final staffSnapshot = guard.buildSnapshot(
      userId: 'staff_1',
      role: ChatUserRole.officeStaff,
      chatScope: const AiChatScope.officeGlobal(
        officeUid: 'office_1',
        officeName: 'Office',
      ),
    );
    final readTool = AiToolRegistry.resolve('properties.search');
    final writeTool = AiToolRegistry.resolve('payments.create');

    expect(guard.canExecuteTool(staffSnapshot, readTool), isTrue);
    expect(guard.canExecuteTool(staffSnapshot, writeTool), isFalse);
  });
}
