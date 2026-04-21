import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityLogEntry {
  final String id;
  final String workspaceUid;
  final String actorUid;
  final String actorName;
  final String actorEmail;
  final String actorRole;
  final String actorType;
  final String actionType;
  final String entityType;
  final String entityId;
  final String entityName;
  final String description;
  final DateTime occurredAt;
  final List<String> changedFields;
  final Map<String, dynamic> changes;
  final Map<String, dynamic> metadata;

  const ActivityLogEntry({
    required this.id,
    required this.workspaceUid,
    required this.actorUid,
    required this.actorName,
    required this.actorEmail,
    required this.actorRole,
    required this.actorType,
    required this.actionType,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    required this.description,
    required this.occurredAt,
    required this.changedFields,
    required this.changes,
    required this.metadata,
  });

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final ms = int.tryParse(v);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.now();
  }

  factory ActivityLogEntry.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ActivityLogEntry(
      id: id,
      workspaceUid: (data['workspaceUid'] ?? '').toString(),
      actorUid: (data['actorUid'] ?? '').toString(),
      actorName: (data['actorName'] ?? '').toString(),
      actorEmail: (data['actorEmail'] ?? '').toString(),
      actorRole: (data['actorRole'] ?? '').toString(),
      actorType: (data['actorType'] ?? '').toString(),
      actionType: (data['actionType'] ?? '').toString(),
      entityType: (data['entityType'] ?? '').toString(),
      entityId: (data['entityId'] ?? '').toString(),
      entityName: (data['entityName'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      occurredAt: _toDate(data['occurredAt'] ?? data['createdAt']),
      changedFields: (data['changedFields'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[],
      changes: (data['changes'] is Map)
          ? Map<String, dynamic>.from(data['changes'] as Map)
          : const <String, dynamic>{},
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : const <String, dynamic>{},
    );
  }
}

