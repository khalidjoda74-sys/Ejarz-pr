import 'dart:io';

import 'package:darvoo/data/services/user_scope.dart';
import 'package:darvoo/ui/ai_chat/core/ai_chat_types.dart';
import 'package:darvoo/ui/ai_chat/core/ai_confirmation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'ai_test_support.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await initAiTestHive('darvoo_ai_confirmation_test_');
    await openAiCoreBoxes();
  });

  tearDown(() async {
    await Hive.box<Map>(boxName('aiPendingActionsBox')).clear();
  });

  tearDownAll(() async {
    await closeAiTestHive(tempDir);
  });

  test('stores pending action and finds latest pending record', () async {
    final created = await AiConfirmationService.create(
      conversationId: 'conv_1',
      userId: 'user_1',
      scopeId: 'scope_1',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't1'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_1',
    );

    final loaded = await AiConfirmationService.get(created.id);
    final latest = await AiConfirmationService.latestPendingForConversation(
      conversationId: 'conv_1',
      userId: 'user_1',
      scopeId: 'scope_1',
    );

    expect(loaded, isNotNull);
    expect(loaded!.toolName, 'contracts.create');
    expect(latest, isNotNull);
    expect(latest!.id, created.id);
  });

  test('marks expired pending action and excludes it from latest', () async {
    await AiConfirmationService.create(
      conversationId: 'conv_2',
      userId: 'user_2',
      scopeId: 'scope_2',
      toolName: 'payments.create',
      normalizedArguments: const <String, dynamic>{'amount': 1200},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.high,
      requiredPermissions: const <String>['payments.create'],
      expiresIn: const Duration(seconds: -1),
    );

    final latest = await AiConfirmationService.latestPendingForConversation(
      conversationId: 'conv_2',
      userId: 'user_2',
      scopeId: 'scope_2',
    );

    expect(latest, isNull);
  });

  test('finds executed record by idempotency key', () async {
    final created = await AiConfirmationService.create(
      conversationId: 'conv_3',
      userId: 'user_3',
      scopeId: 'scope_3',
      toolName: 'properties.create',
      normalizedArguments: const <String, dynamic>{'name': 'Tower'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.high,
      requiredPermissions: const <String>['properties.create'],
      idempotencyKey: 'idem_3',
    );

    await AiConfirmationService.markExecuted(
      created.id,
      resultReference: const <String, dynamic>{'property_id': 'p1'},
    );

    final found = await AiConfirmationService.findExecutedByIdempotencyKey(
      userId: 'user_3',
      scopeId: 'scope_3',
      toolName: 'properties.create',
      idempotencyKey: 'idem_3',
    );

    expect(found, isNotNull);
    expect(found!.status, 'executed');
    expect(found.resultReference?['property_id'], 'p1');
  });

  test('reuses identical active pending action instead of creating a duplicate', () async {
    final first = await AiConfirmationService.create(
      conversationId: 'conv_4',
      userId: 'user_4',
      scopeId: 'scope_4',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't1', 'property_id': 'p1'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_4',
    );

    final second = await AiConfirmationService.create(
      conversationId: 'conv_4',
      userId: 'user_4',
      scopeId: 'scope_4',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't1', 'property_id': 'p1'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_4',
    );

    expect(second.id, first.id);
  });

  test('cancels older active request when a newer request is created in the same conversation', () async {
    final older = await AiConfirmationService.create(
      conversationId: 'conv_5',
      userId: 'user_5',
      scopeId: 'scope_5',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't1'},
      preview: const <String, dynamic>{'headline': 'old'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_5_old',
    );

    final newer = await AiConfirmationService.create(
      conversationId: 'conv_5',
      userId: 'user_5',
      scopeId: 'scope_5',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't2'},
      preview: const <String, dynamic>{'headline': 'new'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_5_new',
    );

    final olderLoaded = await AiConfirmationService.get(older.id);
    final latest = await AiConfirmationService.latestPendingForConversation(
      conversationId: 'conv_5',
      userId: 'user_5',
      scopeId: 'scope_5',
    );

    expect(olderLoaded, isNotNull);
    expect(olderLoaded!.status, 'cancelled');
    expect(latest, isNotNull);
    expect(latest!.id, newer.id);
  });

  test('claims a pending action once and blocks duplicate claims until it finishes', () async {
    final created = await AiConfirmationService.create(
      conversationId: 'conv_6',
      userId: 'user_6',
      scopeId: 'scope_6',
      toolName: 'contracts.create',
      normalizedArguments: const <String, dynamic>{'tenant_id': 't6'},
      preview: const <String, dynamic>{'headline': 'preview'},
      riskLevel: AiToolRiskLevel.critical,
      requiredPermissions: const <String>['contracts.create'],
      idempotencyKey: 'idem_6',
    );

    final firstClaim = await AiConfirmationService.claimForExecution(created.id);
    final secondClaim = await AiConfirmationService.claimForExecution(created.id);
    final stored = await AiConfirmationService.get(created.id);

    expect(firstClaim.status, AiPendingActionClaimStatus.claimed);
    expect(secondClaim.status, AiPendingActionClaimStatus.alreadyClaimed);
    expect(stored, isNotNull);
    expect(stored!.status, 'confirmed');
    expect(stored.confirmedAt, isNotNull);
  });
}
