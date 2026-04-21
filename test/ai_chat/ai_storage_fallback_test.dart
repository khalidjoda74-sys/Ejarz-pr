import 'dart:io';

import 'package:darvoo/data/services/user_scope.dart';
import 'package:darvoo/ui/ai_chat/core/ai_audit_log_store.dart';
import 'package:darvoo/ui/ai_chat/core/ai_chat_types.dart';
import 'package:darvoo/ui/ai_chat/core/ai_pending_action_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'ai_test_support.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await initAiTestHive('darvoo_ai_storage_test_');
    await openAiCoreBoxes();
  });

  setUp(() async {
    await Hive.box<Map>(boxName('aiPendingActionsBox')).clear();
    await Hive.box<Map>(boxName('aiAuditLogsBox')).clear();
  });

  tearDownAll(() async {
    await closeAiTestHive(tempDir);
  });

  test('pending action store keeps working locally without Firebase setup', () async {
    final record = AiPendingActionRecord(
      id: 'pending_local_only',
      conversationId: 'conv_local',
      userId: 'user_local',
      scopeId: 'scope_local',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't1'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.high,
      requiredPermissions: const <String>['contracts.create'],
      argsHash: 'hash_local',
      status: 'pending',
      createdAt: DateTime(2026, 4, 20, 10),
      expiresAt: DateTime(2026, 4, 20, 11),
      confirmedAt: null,
      executedAt: null,
      resultReference: null,
      errorMessage: null,
      idempotencyKey: 'idem_local',
    );

    await AiPendingActionStore.save(record);
    final loaded = await AiPendingActionStore.get(
      record.id,
      userId: record.userId,
    );
    final matching = await AiPendingActionStore.query(
      userId: record.userId,
      scopeId: record.scopeId,
      conversationId: record.conversationId,
      statuses: const <String>['pending'],
    );

    expect(loaded, isNotNull);
    expect(loaded!.toolName, record.toolName);
    expect(matching, hasLength(1));
    expect(matching.first.id, record.id);
  });

  test('audit log store persists locally without Firebase setup', () async {
    final box = await AiAuditLogStore.openLocalBox();
    await AiAuditLogStore.append(
      userId: 'user_local',
      logId: 'audit_local_only',
      entry: <String, dynamic>{
        'user_id': 'user_local',
        'organization_id': 'scope_local',
        'conversation_id': 'conv_local',
        'request_id': 'req_local',
        'tool_name': 'properties.create',
        'operation_type': 'write',
        'risk_level': 'high',
        'arguments': const <String, dynamic>{'name': 'برج محلي'},
        'result_reference': const <String, dynamic>{},
        'status': 'confirmation_created',
        'timestamp': DateTime(2026, 4, 20, 10).toIso8601String(),
        'timestamp_ms': DateTime(2026, 4, 20, 10).millisecondsSinceEpoch,
      },
      box: box,
    );

    final stored = box.get('audit_local_only');
    expect(stored, isNotNull);
    expect(stored!['tool_name'], 'properties.create');
    expect(stored['status'], 'confirmation_created');
  });
}
