import 'package:hive/hive.dart';

import 'ai_chat_types.dart';
import 'ai_pending_action_store.dart';

class AiConfirmationService {
  AiConfirmationService._();

  static const Duration _defaultExpiry = Duration(minutes: 20);
  static const Duration _retentionWindow = Duration(days: 14);
  static const Set<String> _activeStatuses = <String>{'pending', 'confirmed'};

  static const String _expiredMessage =
      '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.';
  static const String _expiredRequestMessage =
      '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.';
  static const String _replacedMessage =
      '\u062a\u0645 \u0627\u0633\u062a\u0628\u062f\u0627\u0644 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f \u0628\u0637\u0644\u0628 \u0623\u062d\u062f\u062b.';

  static Future<Box<Map>> _openBox() async {
    return AiPendingActionStore.openLocalBox();
  }

  static bool isConfirmText(String text) {
    final normalized = text.trim().toLowerCase();
    return normalized == '\u0646\u0639\u0645' ||
        normalized == '\u062a\u0623\u0643\u064a\u062f' ||
        normalized == '\u0623\u0624\u0643\u062f' ||
        normalized == '\u0627\u0624\u0643\u062f' ||
        normalized == '\u0646\u0641\u0630' ||
        normalized == '\u0645\u0648\u0627\u0641\u0642' ||
        normalized ==
            '\u0623\u0624\u0643\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630' ||
        normalized ==
            '\u0627\u0624\u0643\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630';
  }

  static bool isCancelText(String text) {
    final normalized = text.trim().toLowerCase();
    return normalized == '\u0625\u0644\u063a\u0627\u0621' ||
        normalized == '\u0627\u0644\u063a\u0627\u0621' ||
        normalized == '\u0644\u0627' ||
        normalized == '\u062a\u0631\u0627\u062c\u0639';
  }

  static bool requiresStrongConfirmation(AiToolRiskLevel level) {
    return level == AiToolRiskLevel.critical;
  }

  static bool confirmTextMatchesRisk(String text, AiToolRiskLevel level) {
    if (!requiresStrongConfirmation(level)) {
      return isConfirmText(text);
    }
    final normalized = text.trim().toLowerCase();
    return normalized ==
            '\u0623\u0624\u0643\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630' ||
        normalized ==
            '\u0627\u0624\u0643\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630';
  }

  static Future<AiPendingActionRecord> create({
    required String conversationId,
    required String userId,
    required String scopeId,
    required String toolName,
    required Map<String, dynamic> normalizedArguments,
    required Map<String, dynamic> preview,
    required AiToolRiskLevel riskLevel,
    required List<String> requiredPermissions,
    String? idempotencyKey,
    Duration expiresIn = _defaultExpiry,
  }) async {
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    final now = DateTime.now();
    final payloadToHash = '$toolName|$scopeId|$userId|$normalizedArguments';
    final argsHash = aiStableHash(payloadToHash);
    final reusable = _findReusablePending(
      box: box,
      conversationId: conversationId,
      userId: userId,
      scopeId: scopeId,
      toolName: toolName,
      argsHash: argsHash,
    );
    if (reusable != null) {
      return reusable;
    }
    await _cancelOlderActiveRequests(
      box: box,
      conversationId: conversationId,
      userId: userId,
      scopeId: scopeId,
    );
    final record = AiPendingActionRecord(
      id: 'pending_${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      userId: userId,
      scopeId: scopeId,
      toolName: toolName,
      normalizedArguments: normalizedArguments,
      preview: preview,
      riskLevel: riskLevel,
      requiredPermissions: requiredPermissions,
      argsHash: argsHash,
      status: 'pending',
      createdAt: now,
      expiresAt: now.add(expiresIn),
      confirmedAt: null,
      executedAt: null,
      resultReference: null,
      errorMessage: null,
      idempotencyKey: idempotencyKey,
    );
    await AiPendingActionStore.save(
      record,
      box: box,
      awaitRemote: true,
    );
    return record;
  }

  static Future<AiPendingActionRecord?> get(
    String id, {
    String? userId,
  }) async {
    if (id.trim().isEmpty) return null;
    final box = await _openBox();
    return AiPendingActionStore.get(
      id,
      userId: userId,
      box: box,
    );
  }

  static Future<AiPendingActionRecord?> latestPendingForConversation({
    required String conversationId,
    required String userId,
    required String scopeId,
  }) async {
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    final candidates = await AiPendingActionStore.query(
      userId: userId,
      scopeId: scopeId,
      conversationId: conversationId,
      statuses: const <String>['pending'],
      box: box,
    );
    for (final record in candidates) {
      if (_isExpired(record)) {
        await AiPendingActionStore.save(
          record.copyWith(
            status: 'expired',
            errorMessage: _expiredMessage,
          ),
          box: box,
          awaitRemote: true,
        );
        continue;
      }
      return record;
    }
    return null;
  }

  static Future<AiPendingActionRecord?> findExecutedByIdempotencyKey({
    required String userId,
    required String scopeId,
    required String toolName,
    required String idempotencyKey,
  }) async {
    if (idempotencyKey.trim().isEmpty) return null;
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    final matches = await AiPendingActionStore.query(
      userId: userId,
      scopeId: scopeId,
      toolName: toolName,
      idempotencyKey: idempotencyKey,
      statuses: const <String>['executed'],
      box: box,
    );
    if (matches.isEmpty) return null;
    return matches.first;
  }

  static Future<void> markConfirmed(String id) async {
    final record = await get(id);
    if (record == null) return;
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    await AiPendingActionStore.save(
      record.copyWith(
        status: 'confirmed',
        confirmedAt: DateTime.now(),
      ),
      box: box,
      awaitRemote: true,
    );
  }

  static Future<void> markExecuted(
    String id, {
    Map<String, dynamic>? resultReference,
  }) async {
    final record = await get(id);
    if (record == null) return;
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    await AiPendingActionStore.save(
      record.copyWith(
        status: 'executed',
        executedAt: DateTime.now(),
        resultReference: resultReference ?? const <String, dynamic>{},
      ),
      box: box,
      awaitRemote: true,
    );
  }

  static Future<void> markCancelled(String id) async {
    final record = await get(id);
    if (record == null) return;
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    await AiPendingActionStore.save(
      record.copyWith(
        status: 'cancelled',
      ),
      box: box,
      awaitRemote: true,
    );
  }

  static Future<void> markFailed(String id, String errorMessage) async {
    final record = await get(id);
    if (record == null) return;
    final box = await _openBox();
    await cleanupExpiredAndStale(box: box);
    await AiPendingActionStore.save(
      record.copyWith(
        status: 'failed',
        errorMessage: errorMessage,
      ),
      box: box,
      awaitRemote: true,
    );
  }

  static Future<AiPendingActionClaimResult> claimForExecution(String id) async {
    final box = await _openBox();
    final record = await AiPendingActionStore.get(id, box: box);
    if (record == null) {
      return const AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.unavailable,
        message:
            '\u062a\u0639\u0630\u0631 \u0627\u0644\u0639\u062b\u0648\u0631 \u0639\u0644\u0649 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.',
      );
    }
    return AiPendingActionStore.claimForExecution(
      record,
      box: box,
    );
  }

  static bool _isExpired(AiPendingActionRecord record) {
    return DateTime.now().isAfter(record.expiresAt);
  }

  static Future<void> cleanupExpiredAndStale({Box<Map>? box}) async {
    final targetBox = box ?? await _openBox();
    final now = DateTime.now();
    final keysToDelete = <dynamic>[];
    final updates = <AiPendingActionRecord>[];
    for (final key in targetBox.keys) {
      final raw = targetBox.get(key);
      if (raw == null) continue;
      final record =
          AiPendingActionRecord.fromJson(Map<String, dynamic>.from(raw));
      if (_activeStatuses.contains(record.status) && _isExpired(record)) {
        updates.add(
          record.copyWith(
            status: 'expired',
            errorMessage: _expiredRequestMessage,
          ),
        );
        continue;
      }
      final keepUntil =
          record.executedAt ?? record.confirmedAt ?? record.createdAt;
      if (!_activeStatuses.contains(record.status) &&
          now.difference(keepUntil) > _retentionWindow) {
        keysToDelete.add(key);
      }
    }
    for (final record in updates) {
      await AiPendingActionStore.save(
        record,
        box: targetBox,
        awaitRemote: true,
      );
    }
    if (keysToDelete.isNotEmpty) {
      await targetBox.deleteAll(keysToDelete);
    }
  }

  static AiPendingActionRecord? _findReusablePending({
    required Box<Map> box,
    required String conversationId,
    required String userId,
    required String scopeId,
    required String toolName,
    required String argsHash,
  }) {
    for (final raw in box.values) {
      final record =
          AiPendingActionRecord.fromJson(Map<String, dynamic>.from(raw));
      if (record.conversationId != conversationId ||
          record.userId != userId ||
          record.scopeId != scopeId ||
          record.toolName != toolName ||
          record.argsHash != argsHash ||
          !_activeStatuses.contains(record.status) ||
          _isExpired(record)) {
        continue;
      }
      return record;
    }
    return null;
  }

  static Future<void> _cancelOlderActiveRequests({
    required Box<Map> box,
    required String conversationId,
    required String userId,
    required String scopeId,
  }) async {
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final record =
          AiPendingActionRecord.fromJson(Map<String, dynamic>.from(raw));
      if (record.conversationId != conversationId ||
          record.userId != userId ||
          record.scopeId != scopeId ||
          !_activeStatuses.contains(record.status) ||
          _isExpired(record)) {
        continue;
      }
      await AiPendingActionStore.save(
        record.copyWith(
          status: 'cancelled',
          errorMessage: _replacedMessage,
        ),
        box: box,
        awaitRemote: true,
      );
    }
  }
}
