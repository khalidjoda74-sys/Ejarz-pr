import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';

import '../../../data/services/user_scope.dart';
import 'ai_chat_types.dart';

class AiPendingActionStore {
  AiPendingActionStore._();

  static const String _boxBaseName = 'aiPendingActionsBox';
  static const String _collectionName = 'ai_pending_actions';
  static const Duration _remoteReadTimeout = Duration(seconds: 2);
  static const Duration _remoteWriteTimeout = Duration(seconds: 2);
  static const Duration _remoteRetentionWindow = Duration(days: 14);
  static const Duration _claimStaleWindow = Duration(minutes: 2);
  static const Set<String> _finalStatuses = <String>{
    'executed',
    'cancelled',
    'failed',
    'expired',
  };

  static Future<Box<Map>> openLocalBox() async {
    final name = boxName(_boxBaseName);
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<Map>(name);
    }
    return Hive.box<Map>(name);
  }

  static Future<void> save(
    AiPendingActionRecord record, {
    Box<Map>? box,
    bool awaitRemote = false,
  }) async {
    final targetBox = box ?? await openLocalBox();
    final payload = _recordPayload(record);
    await targetBox.put(record.id, payload);
    if (!_canUseRemote(record.userId)) return;
    if (awaitRemote) {
      await _syncRemote(record);
    } else {
      unawaited(_syncRemote(record));
    }
    if (_finalStatuses.contains(record.status)) {
      unawaited(_purgeRemoteFinalizedRecords(userId: record.userId));
    }
  }

  static Future<AiPendingActionClaimResult> claimForExecution(
    AiPendingActionRecord record, {
    Box<Map>? box,
  }) async {
    final targetBox = box ?? await openLocalBox();
    if (_canUseRemote(record.userId)) {
      final remoteResult = await _claimRemote(
        record,
        box: targetBox,
      );
      if (remoteResult.status != AiPendingActionClaimStatus.unavailable) {
        return remoteResult;
      }
    }
    return _claimLocally(
      record,
      box: targetBox,
    );
  }

  static Future<AiPendingActionRecord?> get(
    String id, {
    String? userId,
    Box<Map>? box,
  }) async {
    if (id.trim().isEmpty) return null;
    final targetBox = box ?? await openLocalBox();
    final raw = targetBox.get(id);
    if (raw is Map) {
      return AiPendingActionRecord.fromJson(Map<String, dynamic>.from(raw));
    }
    if (!_canUseRemote(userId ?? '')) return null;
    return _readRemoteById(
      id,
      userId: userId!,
      box: targetBox,
    );
  }

  static Future<List<AiPendingActionRecord>> query({
    required String userId,
    String? scopeId,
    String? conversationId,
    String? toolName,
    String? idempotencyKey,
    List<String>? statuses,
    int remoteLimit = 80,
    Box<Map>? box,
  }) async {
    final targetBox = box ?? await openLocalBox();
    final localRecords = _filterRecords(
      targetBox.values
          .whereType<Map>()
          .map((raw) => AiPendingActionRecord.fromJson(Map<String, dynamic>.from(raw))),
      userId: userId,
      scopeId: scopeId,
      conversationId: conversationId,
      toolName: toolName,
      idempotencyKey: idempotencyKey,
      statuses: statuses,
    );
    if (localRecords.isNotEmpty || !_canUseRemote(userId)) {
      return localRecords;
    }
    final remoteRecords = await _readRemoteRecords(
      userId,
      limit: remoteLimit,
      box: targetBox,
    );
    return _filterRecords(
      remoteRecords,
      userId: userId,
      scopeId: scopeId,
      conversationId: conversationId,
      toolName: toolName,
      idempotencyKey: idempotencyKey,
      statuses: statuses,
    );
  }

  static List<AiPendingActionRecord> _filterRecords(
    Iterable<AiPendingActionRecord> records, {
    required String userId,
    String? scopeId,
    String? conversationId,
    String? toolName,
    String? idempotencyKey,
    List<String>? statuses,
  }) {
    final statusSet = (statuses ?? const <String>[]).toSet();
    final filtered = records.where((record) {
      if (record.userId != userId) return false;
      if ((scopeId ?? '').isNotEmpty && record.scopeId != scopeId) return false;
      if ((conversationId ?? '').isNotEmpty &&
          record.conversationId != conversationId) {
        return false;
      }
      if ((toolName ?? '').isNotEmpty && record.toolName != toolName) {
        return false;
      }
      if ((idempotencyKey ?? '').isNotEmpty &&
          record.idempotencyKey != idempotencyKey) {
        return false;
      }
      if (statusSet.isNotEmpty && !statusSet.contains(record.status)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  static bool _canUseRemote(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty || normalized == 'guest') {
      return false;
    }
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<AiPendingActionRecord?> _readRemoteById(
    String id, {
    required String userId,
    required Box<Map> box,
  }) async {
    try {
      final snap = await _remoteCollection(userId)
          .doc(id)
          .get()
          .timeout(_remoteReadTimeout);
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      final record = AiPendingActionRecord.fromJson(
        <String, dynamic>{...data, 'id': snap.id},
      );
      await box.put(record.id, _recordPayload(record));
      return record;
    } catch (_) {
      return null;
    }
  }

  static Future<List<AiPendingActionRecord>> _readRemoteRecords(
    String userId, {
    required int limit,
    required Box<Map> box,
  }) async {
    try {
      final snap = await _remoteCollection(userId)
          .limit(limit)
          .get()
          .timeout(_remoteReadTimeout);
      final records = <AiPendingActionRecord>[];
      for (final doc in snap.docs) {
        final record = AiPendingActionRecord.fromJson(
          <String, dynamic>{...doc.data(), 'id': doc.id},
        );
        await box.put(record.id, _recordPayload(record));
        records.add(record);
      }
      return records;
    } catch (_) {
      return const <AiPendingActionRecord>[];
    }
  }

  static Future<void> _syncRemote(AiPendingActionRecord record) async {
    try {
      await _remoteCollection(record.userId)
          .doc(record.id)
          .set(
            _recordPayload(record),
            SetOptions(merge: true),
          )
          .timeout(_remoteWriteTimeout);
    } catch (_) {}
  }

  static Future<AiPendingActionClaimResult> _claimRemote(
    AiPendingActionRecord seedRecord, {
    required Box<Map> box,
  }) async {
    final now = DateTime.now();
    try {
      final result = await FirebaseFirestore.instance.runTransaction(
        (transaction) async {
          final ref = _remoteCollection(seedRecord.userId).doc(seedRecord.id);
          final snap = await transaction.get(ref);
          if (!snap.exists) {
            return const AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.unavailable,
            );
          }
          final data = snap.data();
          if (data == null) {
            return const AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.unavailable,
            );
          }
          final remoteRecord = AiPendingActionRecord.fromJson(
            <String, dynamic>{...data, 'id': snap.id},
          );
          if (_isExpired(remoteRecord, now: now)) {
            final expiredRecord = remoteRecord.copyWith(
              status: 'expired',
              errorMessage:
                  '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.',
            );
            transaction.set(
              ref,
              _recordPayload(expiredRecord),
              SetOptions(merge: true),
            );
            return AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.expired,
              record: expiredRecord,
              message:
                  '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.',
            );
          }
          if (remoteRecord.status == 'executed') {
            return AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.alreadyExecuted,
              record: remoteRecord,
              resultReference:
                  remoteRecord.resultReference ?? const <String, dynamic>{},
              message:
                  '\u062a\u0645 \u062a\u0646\u0641\u064a\u0630 \u0647\u0630\u0627 \u0627\u0644\u0637\u0644\u0628 \u0645\u0633\u0628\u0642\u064b\u0627.',
            );
          }
          if (remoteRecord.status == 'confirmed' &&
              !_isClaimStale(remoteRecord, now: now)) {
            return AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.alreadyClaimed,
              record: remoteRecord,
              message:
                  '\u0647\u0630\u0627 \u0627\u0644\u0637\u0644\u0628 \u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630 \u0628\u0627\u0644\u0641\u0639\u0644.',
            );
          }
          if (remoteRecord.status != 'pending' &&
              remoteRecord.status != 'confirmed') {
            return AiPendingActionClaimResult(
              status: AiPendingActionClaimStatus.unavailable,
              record: remoteRecord,
              message:
                  '\u062d\u0627\u0644\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f \u0644\u0627 \u062a\u0633\u0645\u062d \u0628\u0625\u0639\u0627\u062f\u0629 \u062a\u0646\u0641\u064a\u0630\u0647.',
            );
          }
          final claimedRecord = remoteRecord.copyWith(
            status: 'confirmed',
            confirmedAt: now,
            errorMessage: null,
          );
          transaction.set(
            ref,
            _recordPayload(claimedRecord),
            SetOptions(merge: true),
          );
          return AiPendingActionClaimResult(
            status: AiPendingActionClaimStatus.claimed,
            record: claimedRecord,
          );
        },
      ).timeout(_remoteWriteTimeout);
      if (result.record != null) {
        await box.put(result.record!.id, _recordPayload(result.record!));
      }
      return result;
    } catch (_) {
      return const AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.unavailable,
      );
    }
  }

  static Future<AiPendingActionClaimResult> _claimLocally(
    AiPendingActionRecord seedRecord, {
    required Box<Map> box,
  }) async {
    final now = DateTime.now();
    final current = await get(
          seedRecord.id,
          userId: seedRecord.userId,
          box: box,
        ) ??
        seedRecord;
    if (_isExpired(current, now: now)) {
      final expiredRecord = current.copyWith(
        status: 'expired',
        errorMessage:
            '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.',
      );
      await save(
        expiredRecord,
        box: box,
        awaitRemote: true,
      );
      return AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.expired,
        record: expiredRecord,
        message:
            '\u0627\u0646\u062a\u0647\u062a \u0635\u0644\u0627\u062d\u064a\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f.',
      );
    }
    if (current.status == 'executed') {
      return AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.alreadyExecuted,
        record: current,
        resultReference: current.resultReference ?? const <String, dynamic>{},
        message:
            '\u062a\u0645 \u062a\u0646\u0641\u064a\u0630 \u0647\u0630\u0627 \u0627\u0644\u0637\u0644\u0628 \u0645\u0633\u0628\u0642\u064b\u0627.',
      );
    }
    if (current.status == 'confirmed' && !_isClaimStale(current, now: now)) {
      return AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.alreadyClaimed,
        record: current,
        message:
            '\u0647\u0630\u0627 \u0627\u0644\u0637\u0644\u0628 \u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630 \u0628\u0627\u0644\u0641\u0639\u0644.',
      );
    }
    if (current.status != 'pending' && current.status != 'confirmed') {
      return AiPendingActionClaimResult(
        status: AiPendingActionClaimStatus.unavailable,
        record: current,
        message:
            '\u062d\u0627\u0644\u0629 \u0637\u0644\u0628 \u0627\u0644\u062a\u0623\u0643\u064a\u062f \u0644\u0627 \u062a\u0633\u0645\u062d \u0628\u0625\u0639\u0627\u062f\u0629 \u062a\u0646\u0641\u064a\u0630\u0647.',
      );
    }
    final claimedRecord = current.copyWith(
      status: 'confirmed',
      confirmedAt: now,
      errorMessage: null,
    );
    await save(
      claimedRecord,
      box: box,
      awaitRemote: true,
    );
    return AiPendingActionClaimResult(
      status: AiPendingActionClaimStatus.claimed,
      record: claimedRecord,
    );
  }

  static Future<void> _purgeRemoteFinalizedRecords({
    required String userId,
  }) async {
    final cutoff = DateTime.now().subtract(_remoteRetentionWindow);
    for (final status in _finalStatuses) {
      try {
        final snap = await _remoteCollection(userId)
            .where('status', isEqualTo: status)
            .limit(20)
            .get()
            .timeout(_remoteReadTimeout);
        for (final doc in snap.docs) {
          final updatedAtMs = (doc.data()['updated_at_ms'] as num?)?.toInt() ?? 0;
          if (updatedAtMs <= 0) continue;
          final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
          if (updatedAt.isAfter(cutoff)) continue;
          await doc.reference.delete().timeout(_remoteWriteTimeout);
        }
      } catch (_) {}
    }
  }

  static Map<String, dynamic> _recordPayload(AiPendingActionRecord record) {
    final updatedAt = record.executedAt ?? record.confirmedAt ?? record.createdAt;
    return <String, dynamic>{
      ...record.toJson(),
      'created_at_ms': record.createdAt.millisecondsSinceEpoch,
      'expires_at_ms': record.expiresAt.millisecondsSinceEpoch,
      'updated_at_ms': updatedAt.millisecondsSinceEpoch,
    };
  }

  static CollectionReference<Map<String, dynamic>> _remoteCollection(
    String userId,
  ) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(_collectionName);
  }

  static bool _isExpired(
    AiPendingActionRecord record, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    return currentTime.isAfter(record.expiresAt);
  }

  static bool _isClaimStale(
    AiPendingActionRecord record, {
    DateTime? now,
  }) {
    final claimedAt = record.confirmedAt;
    if (claimedAt == null) return true;
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(claimedAt) > _claimStaleWindow;
  }
}
