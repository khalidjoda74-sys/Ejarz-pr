import 'dart:convert';

import '../ai_chat_permissions.dart';
import '../ai_chat_service.dart';
import 'ai_audit_logger.dart';
import 'ai_confirmation_service.dart';
import 'ai_error_mapper.dart';
import 'ai_permission_guard.dart';
import 'ai_read_back_verifier.dart';
import 'ai_response_formatter.dart';
import 'ai_schema_validator.dart';
import 'ai_tool_executor.dart';
import 'ai_tool_registry.dart';
import 'ai_chat_types.dart';

class AiChatGateway {
  final String userId;
  final ChatUserRole role;
  final AiChatScope chatScope;
  final String conversationId;
  final String locale;
  final String timezone;
  final AiToolExecutor toolExecutor;
  final AiPermissionGuard permissionGuard;
  final AiSchemaValidator schemaValidator;
  final AiReadBackVerifier verifier;
  final AiResponseFormatter formatter;
  final AiErrorMapper errorMapper;

  AiChatGateway({
    required this.userId,
    required this.role,
    required this.chatScope,
    required this.conversationId,
    required this.toolExecutor,
    this.locale = 'ar',
    this.timezone = 'Africa/Cairo',
    AiPermissionGuard? permissionGuard,
    AiSchemaValidator? schemaValidator,
    AiReadBackVerifier? verifier,
    AiResponseFormatter? formatter,
    AiErrorMapper? errorMapper,
  })  : permissionGuard = permissionGuard ?? const AiPermissionGuard(),
        schemaValidator = schemaValidator ?? const AiSchemaValidator(),
        verifier = verifier ?? const AiReadBackVerifier(),
        formatter = formatter ?? const AiResponseFormatter(),
        errorMapper = errorMapper ?? const AiErrorMapper();

  AiPermissionSnapshot get _permissionSnapshot => permissionGuard.buildSnapshot(
        userId: userId,
        role: role,
        chatScope: chatScope,
        locale: locale,
        timezone: timezone,
      );

  Future<AiGatewayResponse> handleToolCalls(
    List<Map<String, dynamic>> calls, {
    String model = '',
  }) async {
    if (calls.isEmpty) {
      return formatter.plain('لم يتم استلام أداة صالحة للتنفيذ.');
    }

    final invocation = _parseInvocation(calls.first);
    if (invocation == null) {
      return formatter.executionFailed('تعذر قراءة طلب الأداة من الرد.');
    }

    final definition = AiToolRegistry.tryResolve(invocation.name);
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}';
    if (definition == null || !definition.supported) {
      await AiAuditLogger.log(
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        conversationId: conversationId,
        requestId: requestId,
        toolName: invocation.name,
        operationType: AiToolOperationType.system,
        riskLevel: AiToolRiskLevel.low,
        status: 'unknown_tool_rejected',
        arguments: invocation.arguments,
        model: model,
      );
      return formatter.executionFailed(
        'هذه العملية غير مسجلة ضمن أدوات دارفو الآمنة، لذلك لن يتم تنفيذها.',
      );
    }

    if (!permissionGuard.canExecuteTool(_permissionSnapshot, definition)) {
      await AiAuditLogger.log(
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        conversationId: conversationId,
        requestId: requestId,
        toolName: definition.name,
        operationType: definition.operationType,
        riskLevel: definition.riskLevel,
        status: 'permission_denied',
        arguments: invocation.arguments,
        model: model,
      );
      return formatter.permissionDenied(permissionGuard.denyMessage(definition));
    }

    final validation = schemaValidator.validateObjectSchema(
      definition.inputSchema,
      invocation.arguments,
    );
    if (!validation.isValid) {
      await AiAuditLogger.log(
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        conversationId: conversationId,
        requestId: requestId,
        toolName: definition.name,
        operationType: definition.operationType,
        riskLevel: definition.riskLevel,
        status: 'schema_rejected',
        arguments: invocation.arguments,
        error: validation.errors.join(' | '),
        model: model,
      );
      return formatter.clarification(
        'أحتاج بعض الحقول أو القيم الصحيحة قبل المتابعة:\n${validation.errors.map((e) => '- $e').join('\n')}',
        missingFields: validation.errors,
      );
    }

    final normalizedArguments = validation.normalizedArguments;

    if (definition.requiresConfirmation ||
        definition.operationType == AiToolOperationType.deleteAction ||
        definition.operationType == AiToolOperationType.export) {
      final preflight = await toolExecutor.preflight(
        definition: definition,
        requestedToolName: invocation.name,
        arguments: normalizedArguments,
        allowedPermissions: _permissionSnapshot.permissions,
      );
      final preflightResponse = await _formatPreflightResult(
        definition: definition,
        requestId: requestId,
        normalizedArguments: normalizedArguments,
        preflight: preflight,
        model: model,
      );
      if (preflightResponse != null) return preflightResponse;

      final preview = _buildPreview(definition, normalizedArguments);
      final pendingAction = await AiConfirmationService.create(
        conversationId: conversationId,
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        toolName: definition.name,
        normalizedArguments: normalizedArguments,
        preview: preview,
        riskLevel: definition.riskLevel,
        requiredPermissions: definition.requiredPermissions,
        idempotencyKey: _buildIdempotencyKey(definition, normalizedArguments),
      );
      await AiAuditLogger.log(
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        conversationId: conversationId,
        requestId: requestId,
        toolName: definition.name,
        operationType: definition.operationType,
        riskLevel: definition.riskLevel,
        status: 'confirmation_created',
        arguments: normalizedArguments,
        pendingActionId: pendingAction.id,
        resultReference: <String, dynamic>{'pending_action_id': pendingAction.id},
        model: model,
      );
      return formatter.confirmation(
        text: _buildConfirmationText(definition, preview),
        pendingActionId: pendingAction.id,
        preview: preview,
        toolName: definition.name,
      );
    }

    return _executeAndFormat(
      definition: definition,
      requestedToolName: invocation.name,
      normalizedArguments: normalizedArguments,
      requestId: requestId,
      model: model,
      pendingActionId: null,
    );
  }

  Future<AiGatewayResponse> confirmPendingAction(
    String pendingActionId, {
    required bool confirmed,
    String model = '',
  }) async {
    final pending = await AiConfirmationService.get(
      pendingActionId,
      userId: userId,
    );
    if (pending == null) {
      return formatter.executionFailed('تعذر العثور على طلب التأكيد المطلوب.');
    }
    if (pending.userId != userId ||
        pending.scopeId != chatScope.normalizedScopeId ||
        pending.conversationId != conversationId) {
      return formatter.permissionDenied('هذا التأكيد لا يخص هذه المحادثة.');
    }
    if (pending.status == 'executed') {
      return formatter.toolResult('تم تنفيذ هذا الطلب مسبقًا ولن أعيده مرة أخرى.');
    }
    if (pending.status == 'expired' ||
        DateTime.now().isAfter(pending.expiresAt)) {
      await AiConfirmationService.markFailed(
        pendingActionId,
        'انتهت صلاحية طلب التأكيد.',
      );
      return formatter.executionFailed(
        'انتهت صلاحية طلب التأكيد. أعد الطلب من جديد إذا رغبت.',
      );
    }

    if (!confirmed) {
      await AiConfirmationService.markCancelled(pendingActionId);
      return formatter.plain('تم إلغاء التنفيذ.');
    }

    final executedRecord =
        await AiConfirmationService.findExecutedByIdempotencyKey(
      userId: userId,
      scopeId: chatScope.normalizedScopeId,
      toolName: pending.toolName,
      idempotencyKey: pending.idempotencyKey ?? '',
    );
    if (executedRecord != null) {
      await AiConfirmationService.markExecuted(
        pendingActionId,
        resultReference: Map<String, dynamic>.from(
          executedRecord.resultReference ?? const <String, dynamic>{},
        ),
      );
      return formatter.toolResult(
        'تم تنفيذ هذا الطلب مسبقًا ولن أعيده مرة أخرى.',
        payload: <String, dynamic>{
          'result_reference':
              executedRecord.resultReference ?? const <String, dynamic>{},
          'idempotent_reuse': true,
        },
      );
    }

    final claim = await AiConfirmationService.claimForExecution(pendingActionId);
    if (claim.status == AiPendingActionClaimStatus.alreadyExecuted) {
      await AiConfirmationService.markExecuted(
        pendingActionId,
        resultReference: Map<String, dynamic>.from(
          claim.resultReference,
        ),
      );
      return formatter.toolResult(
        'تم تنفيذ هذا الطلب مسبقًا ولن أعيده مرة أخرى.',
        payload: <String, dynamic>{
          'result_reference': claim.resultReference,
          'idempotent_reuse': true,
        },
      );
    }
    if (claim.status == AiPendingActionClaimStatus.alreadyClaimed) {
      return formatter.plain(
        'هذا الطلب قيد التنفيذ بالفعل في جلسة أخرى. أعد التحقق بعد قليل.',
      );
    }
    if (claim.status == AiPendingActionClaimStatus.expired) {
      await AiConfirmationService.markFailed(
        pendingActionId,
        (claim.message ?? 'انتهت صلاحية طلب التأكيد.'),
      );
      return formatter.executionFailed(
        'انتهت صلاحية طلب التأكيد. أعد الطلب من جديد إذا رغبت.',
      );
    }
    if (claim.status != AiPendingActionClaimStatus.claimed) {
      return formatter.executionFailed(
        (claim.message ?? 'تعذر حجز طلب التأكيد للتنفيذ بشكل آمن.'),
      );
    }

    final definition = AiToolRegistry.resolve(pending.toolName);
    return _executeAndFormat(
      definition: definition,
      requestedToolName: definition.aliases.isNotEmpty
          ? definition.aliases.first
          : definition.handlerName,
      normalizedArguments: pending.normalizedArguments,
      requestId: 'req_${DateTime.now().microsecondsSinceEpoch}',
      model: model,
      pendingActionId: pendingActionId,
    );
  }

  Future<AiGatewayResponse> handleConfirmationText(
    String text, {
    String model = '',
  }) async {
    final pending = await AiConfirmationService.latestPendingForConversation(
      conversationId: conversationId,
      userId: userId,
      scopeId: chatScope.normalizedScopeId,
    );
    if (pending == null) {
      return formatter.plain('لا يوجد طلب معلق يحتاج إلى تأكيد حاليًا.');
    }
    if (AiConfirmationService.isCancelText(text)) {
      return confirmPendingAction(
        pending.id,
        confirmed: false,
        model: model,
      );
    }
    if (!AiConfirmationService.confirmTextMatchesRisk(text, pending.riskLevel)) {
      final hint = AiConfirmationService.requiresStrongConfirmation(
        pending.riskLevel,
      )
          ? 'اكتب: أؤكد التنفيذ'
          : 'اكتب: نعم أو تأكيد';
      return formatter.plain('هذا الطلب يحتاج تأكيدًا صريحًا. $hint');
    }
    return confirmPendingAction(
      pending.id,
      confirmed: true,
      model: model,
    );
  }

  Future<AiGatewayResponse> cancelPendingAction(
    String pendingActionId,
  ) async {
    final pending = await AiConfirmationService.get(
      pendingActionId,
      userId: userId,
    );
    if (pending == null) {
      return formatter.executionFailed('تعذر العثور على طلب التأكيد المطلوب.');
    }
    await AiConfirmationService.markCancelled(pendingActionId);
    return formatter.plain('تم إلغاء التنفيذ.');
  }

  Future<AiGatewayResponse?> _formatPreflightResult({
    required AiToolDefinition definition,
    required String requestId,
    required Map<String, dynamic> normalizedArguments,
    required Map<String, dynamic>? preflight,
    required String model,
  }) async {
    if (preflight == null) return null;
    final status = (preflight['status'] ?? 'success').toString();
    if (status == 'success' || status == 'ok') return null;

    final message = errorMapper.mapToolError(
      (preflight['message'] ?? 'تعذر تجهيز العملية قبل التأكيد.').toString(),
    );
    await AiAuditLogger.log(
      userId: userId,
      scopeId: chatScope.normalizedScopeId,
      conversationId: conversationId,
      requestId: requestId,
      toolName: definition.name,
      operationType: definition.operationType,
      riskLevel: definition.riskLevel,
      status: 'preflight_$status',
      arguments: normalizedArguments,
      error: status == 'error' ? message : null,
      model: model,
    );

    if (status == 'missing_fields') {
      return formatter.clarification(
        message,
        missingFields: preflight['missing_fields'] as List? ?? const <dynamic>[],
      );
    }
    if (status == 'disambiguation') {
      return formatter.disambiguation(
        message,
        candidates: preflight['candidates'] as List? ?? const <dynamic>[],
      );
    }
    if (status == 'unsupported') return formatter.executionFailed(message);
    if (status == 'error') {
      final payload = Map<String, dynamic>.from(
        preflight['payload'] as Map? ?? const <String, dynamic>{},
      );
      return formatter.executionFailed(message, payload: payload);
    }
    return formatter.executionFailed(message);
  }

  Future<AiGatewayResponse> _executeAndFormat({
    required AiToolDefinition definition,
    required String requestedToolName,
    required Map<String, dynamic> normalizedArguments,
    required String requestId,
    required String model,
    required String? pendingActionId,
  }) async {
    final startedAt = DateTime.now();
    final result = await toolExecutor.execute(
      definition: definition,
      requestedToolName: requestedToolName,
      arguments: normalizedArguments,
      allowedPermissions: _permissionSnapshot.permissions,
    );

    final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
    final status = (result['status'] ?? 'error').toString();
    final message = errorMapper.mapToolError((result['message'] ?? '').toString());
    final payload =
        Map<String, dynamic>.from(result['payload'] as Map? ?? const <String, dynamic>{});

    await AiAuditLogger.log(
      userId: userId,
      scopeId: chatScope.normalizedScopeId,
      conversationId: conversationId,
      requestId: requestId,
      toolName: definition.name,
      operationType: definition.operationType,
      riskLevel: definition.riskLevel,
      status: status,
      arguments: normalizedArguments,
      pendingActionId: pendingActionId,
      resultReference: payload,
      error: status == 'error' ? message : null,
      model: model,
      latencyMs: latencyMs,
    );

    if (status == 'missing_fields') {
      return formatter.clarification(
        message,
        missingFields: result['missing_fields'] as List? ?? const <dynamic>[],
      );
    }
    if (status == 'disambiguation') {
      return formatter.disambiguation(
        message,
        candidates: result['candidates'] as List? ?? const <dynamic>[],
      );
    }
    if (status == 'unsupported') {
      return formatter.executionFailed(message);
    }
    if (status == 'error') {
      if (pendingActionId != null) {
        await AiConfirmationService.markFailed(pendingActionId, message);
      }
      return formatter.executionFailed(message, payload: payload);
    }

    final historyResult = jsonEncode(<String, dynamic>{
      'tool': definition.name,
      'message': message,
      'payload': payload,
    });

    if (definition.operationType == AiToolOperationType.write ||
        definition.operationType == AiToolOperationType.deleteAction) {
      final verification = await verifier.verify(
        definition: definition,
        normalizedArguments: normalizedArguments,
        executionPayload: result,
      );
      if (verification['verified'] == true) {
        await AiAuditLogger.log(
          userId: userId,
          scopeId: chatScope.normalizedScopeId,
          conversationId: conversationId,
          requestId: requestId,
          toolName: definition.name,
          operationType: definition.operationType,
          riskLevel: definition.riskLevel,
          status: 'verification_succeeded',
          arguments: normalizedArguments,
          pendingActionId: pendingActionId,
          resultReference: Map<String, dynamic>.from(
            verification['result_reference'] as Map? ??
                const <String, dynamic>{},
          ),
          verificationStatus: 'verified',
          model: model,
          latencyMs: latencyMs,
        );
        if (pendingActionId != null) {
          await AiConfirmationService.markExecuted(
            pendingActionId,
            resultReference: Map<String, dynamic>.from(
              verification['result_reference'] as Map? ?? const <String, dynamic>{},
            ),
          );
        }
        return formatter.toolResult(
          message,
          payload: <String, dynamic>{
            ...payload,
            'verification': verification,
          },
          toolHistoryResult: historyResult,
        );
      }
      await AiAuditLogger.log(
        userId: userId,
        scopeId: chatScope.normalizedScopeId,
        conversationId: conversationId,
        requestId: requestId,
        toolName: definition.name,
        operationType: definition.operationType,
        riskLevel: definition.riskLevel,
        status: 'verification_failed',
        arguments: normalizedArguments,
        pendingActionId: pendingActionId,
        resultReference: payload,
        verificationStatus: 'failed',
        error: (verification['message'] ?? 'تعذر التحقق بعد التنفيذ.').toString(),
        model: model,
        latencyMs: latencyMs,
      );
      if (pendingActionId != null) {
        await AiConfirmationService.markFailed(
          pendingActionId,
          (verification['message'] ?? 'تعذر التحقق بعد التنفيذ.').toString(),
        );
      }
      return formatter.verificationFailed(
        'تمت محاولة التنفيذ، لكن تعذر التحقق من النتيجة من مصدر البيانات: ${(verification['message'] ?? '').toString()}',
        payload: <String, dynamic>{
          ...payload,
          'verification': verification,
        },
      );
    }

    if (definition.operationType == AiToolOperationType.report) {
      return formatter.report(
        message,
        report: payload,
        toolHistoryResult: historyResult,
      );
    }

    return formatter.toolResult(
      message,
      payload: payload,
      toolHistoryResult: historyResult,
    );
  }

  AiToolInvocation? _parseInvocation(Map<String, dynamic> rawCall) {
    final function = rawCall['function'];
    if (function is! Map) return null;
    final callId = (rawCall['id'] ?? '').toString();
    final rawName = (function['name'] ?? '').toString().trim();
    final name = AiToolRegistry.fromOpenAiName(rawName);
    if (name.isEmpty) return null;
    final rawArguments = (function['arguments'] ?? '{}').toString();
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, dynamic>) {
        return AiToolInvocation(
          toolCallId: callId,
          name: name,
          arguments: decoded,
        );
      }
      if (decoded is Map) {
        return AiToolInvocation(
          toolCallId: callId,
          name: name,
          arguments: Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return AiToolInvocation(
      toolCallId: callId,
      name: name,
      arguments: const <String, dynamic>{},
    );
  }

  String _buildConfirmationText(
    AiToolDefinition definition,
    Map<String, dynamic> preview,
  ) {
    final lines = <String>[
      'تأكيد قبل التنفيذ:',
      preview['headline']?.toString() ?? definition.description,
    ];
    final details =
        (preview['details'] as List? ?? const <dynamic>[]).map((item) => item.toString());
    for (final detail in details) {
      if (detail.trim().isEmpty) continue;
      lines.add('- $detail');
    }
    final strong = AiConfirmationService.requiresStrongConfirmation(
      definition.riskLevel,
    );
    lines.add(
      strong
          ? 'لن يتم التنفيذ حتى تؤكد. اكتب: أؤكد التنفيذ'
          : 'لن يتم التنفيذ حتى تؤكد. اكتب: نعم أو تأكيد',
    );
    return lines.join('\n');
  }

  Map<String, dynamic> _buildPreview(
    AiToolDefinition definition,
    Map<String, dynamic> arguments,
  ) {
    final details = <String>[];
    void add(String label, dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty || text == 'null') return;
      details.add('$label: $text');
    }

    add('الأداة', definition.description);
    add('العقار', arguments['property_query'] ?? arguments['propertyName']);
    add('الوحدة', arguments['unit_query'] ?? arguments['unitName']);
    add('نوع الخدمة', arguments['serviceType']);
    add('مقدم الخدمة', arguments['provider']);
    add('المستأجر', arguments['tenant_query'] ?? arguments['tenantName']);
    add('العقد', arguments['query'] ?? arguments['contractSerialNo']);
    add('الفاتورة', arguments['invoiceSerialNo']);
    add('المبلغ', arguments['amount'] ?? arguments['rentAmount']);
    add('تاريخ البداية', arguments['startDate']);
    add('تاريخ النهاية', arguments['endDate']);
    add('تاريخ الاستحقاق', arguments['dueDate'] ?? arguments['nextDueDate']);
    add('الوصف', arguments['description'] ?? arguments['notes']);

    return <String, dynamic>{
      'tool_name': definition.name,
      'headline': definition.description,
      'details': details,
      'risk_level': definition.riskLevel.name,
      'arguments': arguments,
    };
  }

  String _buildIdempotencyKey(
    AiToolDefinition definition,
    Map<String, dynamic> arguments,
  ) {
    return aiStableHash('${definition.name}|${chatScope.normalizedScopeId}|$arguments');
  }
}
