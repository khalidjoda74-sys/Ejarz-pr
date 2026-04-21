import 'dart:convert';
import 'dart:io';

import 'package:darvoo/data/constants/boxes.dart';
import 'package:darvoo/data/services/user_scope.dart';
import 'package:darvoo/models/property.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_executor.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_permissions.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_service.dart';
import 'package:darvoo/ui/ai_chat/core/ai_chat_gateway.dart';
import 'package:darvoo/ui/ai_chat/core/ai_chat_types.dart';
import 'package:darvoo/ui/ai_chat/core/ai_confirmation_service.dart';
import 'package:darvoo/ui/ai_chat/core/ai_read_back_verifier.dart';
import 'package:darvoo/ui/ai_chat/core/ai_tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'ai_test_support.dart';

class _FakeLegacyExecutor extends AiChatExecutor {
  _FakeLegacyExecutor();

  int addPropertyCalls = 0;

  @override
  Future<String> executeCached(
    String functionName,
    Map<String, dynamic> args,
  ) async {
    if (functionName == 'add_property') {
      addPropertyCalls++;
      final property = Property(
        id: 'property_$addPropertyCalls',
        name: (args['name'] ?? '').toString(),
        type: PropertyType.apartment,
        address: (args['address'] ?? '').toString(),
      );
      await Hive.box<Property>(boxName(kPropertiesBox)).put(property.id, property);
      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'Property created',
        'property': <String, dynamic>{
          'id': property.id,
          'name': property.name,
        },
      });
    }

    return jsonEncode(<String, dynamic>{
      'success': true,
      'message': 'ok',
    });
  }
}

class _FailingVerifier extends AiReadBackVerifier {
  const _FailingVerifier();

  @override
  Future<Map<String, dynamic>> verify({
    required AiToolDefinition definition,
    required Map<String, dynamic> normalizedArguments,
    required Map<String, dynamic> executionPayload,
  }) async {
    return <String, dynamic>{
      'verified': false,
      'message': 'تعذر التحقق المقصود داخل الاختبار.',
      'result_reference': const <String, dynamic>{},
    };
  }
}

void main() {
  late Directory tempDir;
  late _FakeLegacyExecutor legacyExecutor;

  setUpAll(() async {
    tempDir = await initAiTestHive('darvoo_ai_gateway_test_');
    await openAiCoreBoxes();
    await openDomainBoxes();
  });

  setUp(() async {
    legacyExecutor = _FakeLegacyExecutor();
    await Hive.box<Map>(boxName('aiPendingActionsBox')).clear();
    await Hive.box<Map>(boxName('aiAuditLogsBox')).clear();
    await Hive.box<Property>(boxName(kPropertiesBox)).clear();
  });

  tearDownAll(() async {
    await closeAiTestHive(tempDir);
  });

  AiChatGateway _buildGateway(
    ChatUserRole role, {
    AiReadBackVerifier? verifier,
  }) {
    return AiChatGateway(
      userId: 'user_1',
      role: role,
      chatScope: role == ChatUserRole.officeStaff
          ? const AiChatScope.officeGlobal(
              officeUid: 'office_1',
              officeName: 'Office',
            )
          : const AiChatScope.ownerSelf(
              ownerUid: 'owner_1',
              ownerName: 'Owner',
            ),
      conversationId: 'conv_1',
      toolExecutor: AiToolExecutor(legacyExecutor: legacyExecutor),
      verifier: verifier,
    );
  }

  test('creates confirmation preview for write tool', () async {
    final gateway = _buildGateway(ChatUserRole.owner);
    final response = await gateway.handleToolCalls(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_1',
          'function': <String, dynamic>{
            'name': 'properties.create',
            'arguments': jsonEncode(<String, dynamic>{
              'name': 'برج الندى',
              'type': 'apartment',
              'address': 'الرياض',
              'rentalMode': null,
              'totalUnits': null,
              'notes': null,
            }),
          },
        },
      ],
    );

    expect(response.type, AiAssistantResponseType.confirmationRequired);
    expect((response.pendingActionId ?? '').isNotEmpty, isTrue);
  });

  test('denies write tool when role lacks permission', () async {
    final gateway = _buildGateway(ChatUserRole.officeStaff);
    final response = await gateway.handleToolCalls(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_2',
          'function': <String, dynamic>{
            'name': 'payments.create',
            'arguments': jsonEncode(<String, dynamic>{
              'invoice_id': null,
              'invoiceSerialNo': 'INV-1',
              'query': null,
              'amount': 1000,
              'paymentMethod': null,
            }),
          },
        },
      ],
    );

    expect(response.type, AiAssistantResponseType.permissionDenied);
  });

  test('reuses executed pending action by idempotency key on second confirmation', () async {
    final gateway = _buildGateway(ChatUserRole.owner);

    Future<AiGatewayResponse> createPending() {
      return gateway.handleToolCalls(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'call_${DateTime.now().microsecondsSinceEpoch}',
            'function': <String, dynamic>{
              'name': 'properties.create',
              'arguments': jsonEncode(<String, dynamic>{
                'name': 'برج الريان',
                'type': 'apartment',
                'address': 'جدة',
                'rentalMode': null,
                'totalUnits': null,
                'notes': null,
              }),
            },
          },
        ],
      );
    }

    final firstPending = await createPending();
    final firstConfirmed = await gateway.confirmPendingAction(
      firstPending.pendingActionId!,
      confirmed: true,
    );

    expect(firstConfirmed.type, AiAssistantResponseType.toolResult);
    expect(legacyExecutor.addPropertyCalls, 1);

    final secondPending = await createPending();
    final secondConfirmed = await gateway.confirmPendingAction(
      secondPending.pendingActionId!,
      confirmed: true,
    );

    expect(secondConfirmed.type, AiAssistantResponseType.toolResult);
    expect(secondConfirmed.payload['idempotent_reuse'], isTrue);
    expect(legacyExecutor.addPropertyCalls, 1);
  });

  test('cancels pending action when user declines confirmation', () async {
    final gateway = _buildGateway(ChatUserRole.owner);
    final pending = await gateway.handleToolCalls(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_cancel',
          'function': <String, dynamic>{
            'name': 'properties.create',
            'arguments': jsonEncode(<String, dynamic>{
              'name': 'برج الإلغاء',
              'type': 'apartment',
              'address': 'الرياض',
              'rentalMode': null,
              'totalUnits': null,
              'notes': null,
            }),
          },
        },
      ],
    );

    final cancelled = await gateway.confirmPendingAction(
      pending.pendingActionId!,
      confirmed: false,
    );
    final stored = await AiConfirmationService.get(pending.pendingActionId!);

    expect(cancelled.type, AiAssistantResponseType.plainAnswer);
    expect(stored, isNotNull);
    expect(stored!.status, 'cancelled');
  });

  test('returns verification failed when read-back verification does not pass', () async {
    final gateway = _buildGateway(
      ChatUserRole.owner,
      verifier: const _FailingVerifier(),
    );
    final pending = await gateway.handleToolCalls(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_verify_fail',
          'function': <String, dynamic>{
            'name': 'properties.create',
            'arguments': jsonEncode(<String, dynamic>{
              'name': 'برج التحقق',
              'type': 'apartment',
              'address': 'جدة',
              'rentalMode': null,
              'totalUnits': null,
              'notes': null,
            }),
          },
        },
      ],
    );

    final confirmed = await gateway.confirmPendingAction(
      pending.pendingActionId!,
      confirmed: true,
    );
    final stored = await AiConfirmationService.get(pending.pendingActionId!);

    expect(confirmed.type, AiAssistantResponseType.verificationFailed);
    expect(stored, isNotNull);
    expect(stored!.status, 'failed');
  });

  test('blocks duplicate confirmation while the request is already claimed', () async {
    final gateway = _buildGateway(ChatUserRole.owner);
    final pending = await gateway.handleToolCalls(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_lock',
          'function': <String, dynamic>{
            'name': 'properties.create',
            'arguments': jsonEncode(<String, dynamic>{
              'name': 'Ø¨Ø±Ø¬ Ø§Ù„Ø­Ø¬Ø²',
              'type': 'apartment',
              'address': 'Ø§Ù„Ø±ÙŠØ§Ø¶',
              'rentalMode': null,
              'totalUnits': null,
              'notes': null,
            }),
          },
        },
      ],
    );

    final claim = await AiConfirmationService.claimForExecution(
      pending.pendingActionId!,
    );
    final duplicate = await gateway.confirmPendingAction(
      pending.pendingActionId!,
      confirmed: true,
    );

    expect(claim.status, AiPendingActionClaimStatus.claimed);
    expect(duplicate.type, AiAssistantResponseType.plainAnswer);
    expect(legacyExecutor.addPropertyCalls, 0);
  });
}
