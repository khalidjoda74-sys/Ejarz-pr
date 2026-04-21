import 'package:hive/hive.dart';

import 'ai_audit_log_store.dart';
import 'ai_chat_types.dart';

class AiAuditLogger {
  AiAuditLogger._();

  static const Duration _retentionWindow = Duration(days: 30);

  static Future<Box<Map>> _openBox() async {
    return AiAuditLogStore.openLocalBox();
  }

  static Future<void> log({
    required String userId,
    required String scopeId,
    required String conversationId,
    required String requestId,
    required String toolName,
    required AiToolOperationType operationType,
    required AiToolRiskLevel riskLevel,
    required String status,
    required Map<String, dynamic> arguments,
    Map<String, dynamic>? resultReference,
    String? pendingActionId,
    String? verificationStatus,
    String? error,
    String? model,
    int? latencyMs,
  }) async {
    final box = await _openBox();
    await purgeOldLogs(box: box);
    final now = DateTime.now();
    final logId = 'audit_${now.microsecondsSinceEpoch}';
    await AiAuditLogStore.append(
      userId: userId,
      logId: logId,
      box: box,
      entry: <String, dynamic>{
        'user_id': userId,
        'organization_id': scopeId,
        'conversation_id': conversationId,
        'request_id': requestId,
        'tool_name': toolName,
        'operation_type': _operationTypeName(operationType),
        'risk_level': _riskLevelName(riskLevel),
        'pending_action_id': pendingActionId,
        'arguments': _redact(arguments),
        'result_reference': resultReference ?? const <String, dynamic>{},
        'status': status,
        'verification_status': verificationStatus,
        'error': error,
        'model': model,
        'latency_ms': latencyMs,
        'timestamp': now.toIso8601String(),
        'timestamp_ms': now.millisecondsSinceEpoch,
      },
    );
  }

  static Future<void> purgeOldLogs({Box<Map>? box}) async {
    final targetBox = box ?? await _openBox();
    final now = DateTime.now();
    final keysToDelete = <dynamic>[];
    for (final key in targetBox.keys) {
      final raw = targetBox.get(key);
      if (raw is! Map) continue;
      final timestamp = DateTime.tryParse((raw['timestamp'] ?? '').toString());
      if (timestamp == null) continue;
      if (now.difference(timestamp) > _retentionWindow) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) {
      await targetBox.deleteAll(keysToDelete);
    }
  }

  static Map<String, dynamic> _redact(Map<String, dynamic> source) {
    const sensitiveKeys = <String>{
      'attachmentPaths',
      'documentAttachmentPaths',
      'nationalId',
      'api_key',
      'password',
      'token',
    };
    final redacted = <String, dynamic>{};
    source.forEach((key, value) {
      if (sensitiveKeys.contains(key)) {
        redacted[key] = '[REDACTED]';
      } else {
        redacted[key] = value;
      }
    });
    return redacted;
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
