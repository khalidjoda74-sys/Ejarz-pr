import 'package:cloud_firestore/cloud_firestore.dart';

class ParticipantSnapshot {
  const ParticipantSnapshot({
    required this.displayName,
    this.avatarEmoji,
    this.photoUrl,
  });

  final String displayName;
  final String? avatarEmoji;
  final String? photoUrl;

  factory ParticipantSnapshot.fromMap(Map<String, dynamic> data) {
    return ParticipantSnapshot(
      displayName: _stringValue(
        data['displayName'],
        fallback: _stringValue(data['name'], fallback: 'عضو Forsa Pro'),
      ),
      avatarEmoji: _stringValue(data['avatarEmoji'], fallback: _stringValue(data['avatar'])),
      photoUrl: _stringValue(data['photoUrl'], fallback: _stringValue(data['photoURL'])),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      if (avatarEmoji != null && avatarEmoji!.isNotEmpty) 'avatarEmoji': avatarEmoji,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
    };
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}

class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.councilId,
    required this.councilTitle,
    required this.ownerId,
    required this.requesterId,
    required this.participantIds,
    required this.participantSnapshots,
    required this.unreadCounts,
    required this.status,
    this.blockedBy = const [],
    this.archivedBy = const [],
    this.deletedBy = const [],
    this.reportCount = 0,
    this.lastMessageText = '',
    this.lastMessageAt,
    this.lastSenderId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String councilId;
  final String councilTitle;
  final String ownerId;
  final String requesterId;
  final List<String> participantIds;
  final Map<String, ParticipantSnapshot> participantSnapshots;
  final Map<String, int> unreadCounts;
  final String status;
  final List<String> blockedBy;
  final List<String> archivedBy;
  final List<String> deletedBy;
  final int reportCount;
  final String lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ConversationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ConversationModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory ConversationModel.fromMap(String id, Map<String, dynamic> data) {
    return ConversationModel(
      id: id,
      councilId: _stringValue(data['councilId']),
      councilTitle: _stringValue(data['councilTitle'], fallback: 'منشور'),
      ownerId: _stringValue(data['ownerId']),
      requesterId: _stringValue(data['requesterId']),
      participantIds: _stringList(data['participantIds']),
      participantSnapshots: _snapshotsFromValue(data['participantSnapshots']),
      unreadCounts: _intMap(data['unreadCounts']),
      status: _stringValue(data['status'], fallback: 'active'),
      blockedBy: _stringList(data['blockedBy']),
      archivedBy: _stringList(data['archivedBy']),
      deletedBy: _stringList(data['deletedBy']),
      reportCount: _intValue(data['reportCount']),
      lastMessageText: _stringValue(data['lastMessageText']),
      lastMessageAt: _dateValue(data['lastMessageAt']),
      lastSenderId: _stringValue(data['lastSenderId']),
      createdAt: _dateValue(data['createdAt']),
      updatedAt: _dateValue(data['updatedAt']),
    );
  }

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  bool get isBlocked => blockedBy.isNotEmpty;

  bool isArchivedFor(String uid) => archivedBy.contains(uid);

  bool isDeletedFor(String uid) => deletedBy.contains(uid);

  DateTime? get sortAt => lastMessageAt ?? updatedAt ?? createdAt;

  ParticipantSnapshot? otherParticipant(String currentUid) {
    final otherUid = participantIds.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );
    if (otherUid.isEmpty) return null;
    return participantSnapshots[otherUid];
  }

  static Map<String, ParticipantSnapshot> _snapshotsFromValue(Object? value) {
    if (value is! Map) return const {};
    final result = <String, ParticipantSnapshot>{};
    value.forEach((key, raw) {
      if (raw is Map) {
        result[key.toString()] = ParticipantSnapshot.fromMap(
          Map<String, dynamic>.from(raw),
        );
      }
    });
    return result;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    value.forEach((key, raw) {
      if (raw is int) result[key.toString()] = raw;
      if (raw is num) result[key.toString()] = raw.round();
    });
    return result;
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  static DateTime? _dateValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}