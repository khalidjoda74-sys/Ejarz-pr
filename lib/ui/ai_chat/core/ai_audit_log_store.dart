import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';

import '../../../data/services/user_scope.dart';

class AiAuditLogStore {
  AiAuditLogStore._();

  static const String _boxBaseName = 'aiAuditLogsBox';
  static const String _collectionName = 'ai_audit_logs';
  static const Duration _remoteReadTimeout = Duration(seconds: 2);
  static const Duration _remoteWriteTimeout = Duration(seconds: 2);
  static const Duration _remoteRetentionWindow = Duration(days: 30);

  static Future<Box<Map>> openLocalBox() async {
    final name = boxName(_boxBaseName);
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<Map>(name);
    }
    return Hive.box<Map>(name);
  }

  static Future<void> append({
    required String userId,
    required String logId,
    required Map<String, dynamic> entry,
    Box<Map>? box,
  }) async {
    final targetBox = box ?? await openLocalBox();
    await targetBox.put(logId, entry);
    if (!_canUseRemote(userId)) return;
    unawaited(_syncRemote(
      userId: userId,
      logId: logId,
      entry: entry,
    ));
    unawaited(_purgeRemoteOldLogs(userId: userId));
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

  static Future<void> _syncRemote({
    required String userId,
    required String logId,
    required Map<String, dynamic> entry,
  }) async {
    try {
      await _remoteCollection(userId)
          .doc(logId)
          .set(entry, SetOptions(merge: true))
          .timeout(_remoteWriteTimeout);
    } catch (_) {}
  }

  static Future<void> _purgeRemoteOldLogs({
    required String userId,
  }) async {
    final cutoffMs =
        DateTime.now().subtract(_remoteRetentionWindow).millisecondsSinceEpoch;
    try {
      final snap = await _remoteCollection(userId)
          .where('timestamp_ms', isLessThan: cutoffMs)
          .limit(25)
          .get()
          .timeout(_remoteReadTimeout);
      for (final doc in snap.docs) {
        await doc.reference.delete().timeout(_remoteWriteTimeout);
      }
    } catch (_) {}
  }

  static CollectionReference<Map<String, dynamic>> _remoteCollection(
    String userId,
  ) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(_collectionName);
  }
}
