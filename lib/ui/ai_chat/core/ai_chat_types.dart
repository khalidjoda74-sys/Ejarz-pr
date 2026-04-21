import 'dart:convert';

enum AiToolOperationType { read, write, report, deleteAction, export, system }

enum AiToolRiskLevel { low, medium, high, critical }

enum AiAssistantResponseType {
  plainAnswer,
  clarificationQuestion,
  disambiguation,
  confirmationRequired,
  toolResult,
  reportSummary,
  permissionDenied,
  executionFailed,
  verificationFailed,
  unsupported,
}

class AiDisambiguationCandidate {
  final String id;
  final String label;
  final String subtitle;
  final String entityType;
  final Map<String, dynamic> meta;

  const AiDisambiguationCandidate({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.entityType,
    this.meta = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'subtitle': subtitle,
      'entityType': entityType,
      'meta': meta,
    };
  }
}

class AiToolInvocation {
  final String toolCallId;
  final String name;
  final Map<String, dynamic> arguments;

  const AiToolInvocation({
    required this.toolCallId,
    required this.name,
    required this.arguments,
  });
}

class AiToolDefinition {
  final String name;
  final List<String> aliases;
  final String description;
  final String category;
  final AiToolOperationType operationType;
  final AiToolRiskLevel riskLevel;
  final bool requiresConfirmation;
  final List<String> requiredPermissions;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic>? resultSchema;
  final List<String> businessRules;
  final String handlerName;
  final String? readBackTool;
  final List<String> examplesAr;
  final String disambiguationStrategy;
  final String validationStrategy;
  final bool supported;

  const AiToolDefinition({
    required this.name,
    required this.aliases,
    required this.description,
    required this.category,
    required this.operationType,
    required this.riskLevel,
    required this.requiresConfirmation,
    required this.requiredPermissions,
    required this.inputSchema,
    required this.resultSchema,
    required this.businessRules,
    required this.handlerName,
    required this.readBackTool,
    required this.examplesAr,
    required this.disambiguationStrategy,
    required this.validationStrategy,
    this.supported = true,
  });

  bool matches(String toolName) {
    if (toolName == name) return true;
    return aliases.contains(toolName);
  }

  Map<String, dynamic> toCatalogJson() {
    return <String, dynamic>{
      'name': name,
      'aliases': aliases,
      'description': description,
      'category': category,
      'operationType': _operationTypeName(operationType),
      'riskLevel': _riskLevelName(riskLevel),
      'requiresConfirmation': requiresConfirmation,
      'requiredPermissions': requiredPermissions,
      'inputSchema': inputSchema,
      if (resultSchema != null) 'resultSchema': resultSchema,
      'businessRules': businessRules,
      'handler': handlerName,
      if ((readBackTool ?? '').trim().isNotEmpty) 'readBackTool': readBackTool,
      'examplesAr': examplesAr,
      'disambiguationStrategy': disambiguationStrategy,
      'validationStrategy': validationStrategy,
      'supported': supported,
    };
  }

  static String _operationTypeName(AiToolOperationType type) {
    switch (type) {
      case AiToolOperationType.read:
        return 'read';
      case AiToolOperationType.write:
        return 'write';
      case AiToolOperationType.report:
        return 'report';
      case AiToolOperationType.deleteAction:
        return 'delete';
      case AiToolOperationType.export:
        return 'export';
      case AiToolOperationType.system:
        return 'system';
    }
  }

  static String _riskLevelName(AiToolRiskLevel level) {
    switch (level) {
      case AiToolRiskLevel.low:
        return 'low';
      case AiToolRiskLevel.medium:
        return 'medium';
      case AiToolRiskLevel.high:
        return 'high';
      case AiToolRiskLevel.critical:
        return 'critical';
    }
  }
}

class AiGatewayResponse {
  final AiAssistantResponseType type;
  final String text;
  final Map<String, dynamic> payload;
  final String? toolName;
  final String? pendingActionId;
  final String? toolHistoryResult;

  const AiGatewayResponse({
    required this.type,
    required this.text,
    this.payload = const <String, dynamic>{},
    this.toolName,
    this.pendingActionId,
    this.toolHistoryResult,
  });
}

enum AiPendingActionClaimStatus {
  claimed,
  alreadyClaimed,
  alreadyExecuted,
  expired,
  unavailable,
}

class AiPendingActionClaimResult {
  final AiPendingActionClaimStatus status;
  final AiPendingActionRecord? record;
  final Map<String, dynamic> resultReference;
  final String? message;

  const AiPendingActionClaimResult({
    required this.status,
    this.record,
    this.resultReference = const <String, dynamic>{},
    this.message,
  });
}

class AiPendingActionRecord {
  final String id;
  final String conversationId;
  final String userId;
  final String scopeId;
  final String toolName;
  final Map<String, dynamic> normalizedArguments;
  final Map<String, dynamic> preview;
  final AiToolRiskLevel riskLevel;
  final List<String> requiredPermissions;
  final String argsHash;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? confirmedAt;
  final DateTime? executedAt;
  final Map<String, dynamic>? resultReference;
  final String? errorMessage;
  final String? idempotencyKey;

  const AiPendingActionRecord({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.scopeId,
    required this.toolName,
    required this.normalizedArguments,
    required this.preview,
    required this.riskLevel,
    required this.requiredPermissions,
    required this.argsHash,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.confirmedAt,
    required this.executedAt,
    required this.resultReference,
    required this.errorMessage,
    required this.idempotencyKey,
  });

  AiPendingActionRecord copyWith({
    String? status,
    DateTime? confirmedAt,
    DateTime? executedAt,
    Map<String, dynamic>? resultReference,
    String? errorMessage,
  }) {
    return AiPendingActionRecord(
      id: id,
      conversationId: conversationId,
      userId: userId,
      scopeId: scopeId,
      toolName: toolName,
      normalizedArguments: normalizedArguments,
      preview: preview,
      riskLevel: riskLevel,
      requiredPermissions: requiredPermissions,
      argsHash: argsHash,
      status: status ?? this.status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      executedAt: executedAt ?? this.executedAt,
      resultReference: resultReference ?? this.resultReference,
      errorMessage: errorMessage ?? this.errorMessage,
      idempotencyKey: idempotencyKey,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'conversation_id': conversationId,
      'user_id': userId,
      'organization_id': scopeId,
      'tool_name': toolName,
      'normalized_arguments': normalizedArguments,
      'preview': preview,
      'risk_level': AiToolDefinition._riskLevelName(riskLevel),
      'required_permissions': requiredPermissions,
      'args_hash': argsHash,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
      'executed_at': executedAt?.toIso8601String(),
      'result_reference': resultReference,
      'error_message': errorMessage,
      'idempotency_key': idempotencyKey,
    };
  }

  factory AiPendingActionRecord.fromJson(Map<String, dynamic> json) {
    AiToolRiskLevel parseRisk(dynamic raw) {
      switch ((raw ?? '').toString().trim()) {
        case 'critical':
          return AiToolRiskLevel.critical;
        case 'high':
          return AiToolRiskLevel.high;
        case 'medium':
          return AiToolRiskLevel.medium;
        default:
          return AiToolRiskLevel.low;
      }
    }

    DateTime? parseDate(dynamic raw) {
      final text = (raw ?? '').toString().trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    return AiPendingActionRecord(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversation_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      scopeId: (json['organization_id'] ?? '').toString(),
      toolName: (json['tool_name'] ?? '').toString(),
      normalizedArguments:
          Map<String, dynamic>.from(json['normalized_arguments'] as Map? ?? const <String, dynamic>{}),
      preview: Map<String, dynamic>.from(json['preview'] as Map? ?? const <String, dynamic>{}),
      riskLevel: parseRisk(json['risk_level']),
      requiredPermissions: (json['required_permissions'] as List? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
      argsHash: (json['args_hash'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      expiresAt: parseDate(json['expires_at']) ?? DateTime.now(),
      confirmedAt: parseDate(json['confirmed_at']),
      executedAt: parseDate(json['executed_at']),
      resultReference: json['result_reference'] is Map
          ? Map<String, dynamic>.from(json['result_reference'] as Map)
          : null,
      errorMessage: json['error_message']?.toString(),
      idempotencyKey: json['idempotency_key']?.toString(),
    );
  }
}

String aiStableHash(String input) {
  final bytes = utf8.encode(input);
  var hash = 5381;
  for (final byte in bytes) {
    hash = ((hash << 5) + hash) ^ byte;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}
