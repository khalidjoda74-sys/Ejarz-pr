import 'package:cloud_firestore/cloud_firestore.dart';

enum ConversationContextType {
  opportunity,
  direct,
}

ConversationContextType conversationContextTypeFromFirestore(
  Object? value, {
  required bool hasLegacyOpportunityContext,
}) {
  switch (value?.toString().trim().toLowerCase()) {
    case 'direct':
      return ConversationContextType.direct;
    case 'opportunity':
      return ConversationContextType.opportunity;
    default:
      return hasLegacyOpportunityContext
          ? ConversationContextType.opportunity
          : ConversationContextType.direct;
  }
}

String conversationContextTypeToFirestore(ConversationContextType value) {
  return switch (value) {
    ConversationContextType.opportunity => 'opportunity',
    ConversationContextType.direct => 'direct',
  };
}

class ParticipantSnapshot {
  const ParticipantSnapshot({
    required this.displayName,
    this.username,
    this.avatarEmoji,
    this.photoUrl,
  });

  final String displayName;
  final String? username;
  final String? avatarEmoji;
  final String? photoUrl;

  factory ParticipantSnapshot.fromMap(Map<String, dynamic> data) {
    return ParticipantSnapshot(
      displayName: _stringValue(
        data['displayName'],
        fallback: _stringValue(data['name'], fallback: 'عضو Forsa Pro'),
      ),
      username: _stringValue(data['username']),
      avatarEmoji: _stringValue(data['avatarEmoji'],
          fallback: _stringValue(data['avatar'])),
      photoUrl: _stringValue(data['photoUrl'],
          fallback: _stringValue(data['photoURL'])),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      if (username != null && username!.isNotEmpty) 'username': username,
      if (avatarEmoji != null && avatarEmoji!.isNotEmpty)
        'avatarEmoji': avatarEmoji,
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
    this.contextType = ConversationContextType.opportunity,
    this.councilId,
    this.councilTitle,
    String? targetId,
    String? initiatorId,
    String? ownerId,
    String? requesterId,
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
  })  : targetId = targetId ?? ownerId ?? '',
        initiatorId = initiatorId ?? requesterId ?? '';

  final String id;
  final ConversationContextType contextType;
  final String? councilId;
  final String? councilTitle;
  final String targetId;
  final String initiatorId;
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

  bool get isDirect => contextType == ConversationContextType.direct;

  bool get hasOpportunityContext =>
      contextType == ConversationContextType.opportunity &&
      councilId?.isNotEmpty == true;

  @Deprecated('Use targetId instead.')
  String get ownerId => targetId;

  @Deprecated('Use initiatorId instead.')
  String get requesterId => initiatorId;

  factory ConversationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ConversationModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory ConversationModel.fromMap(String id, Map<String, dynamic> data) {
    final councilId = _nullableStringValue(data['councilId']);
    final councilTitle = _nullableStringValue(data['councilTitle']);
    final hasLegacyOpportunityContext = councilId != null ||
        data.containsKey('ownerId') ||
        data.containsKey('requesterId');
    return ConversationModel(
      id: id,
      contextType: conversationContextTypeFromFirestore(
        data['contextType'],
        hasLegacyOpportunityContext: hasLegacyOpportunityContext,
      ),
      councilId: councilId,
      councilTitle:
          councilTitle ?? (hasLegacyOpportunityContext ? 'منشور' : null),
      targetId: _stringValue(
        data['targetId'],
        fallback: _stringValue(data['ownerId']),
      ),
      initiatorId: _stringValue(
        data['initiatorId'],
        fallback: _stringValue(data['requesterId']),
      ),
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
    final otherUid = otherParticipantUid(currentUid);
    if (otherUid.isEmpty) return null;
    return participantSnapshots[otherUid];
  }

  String otherParticipantUid(String currentUid) {
    return participantIds.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );
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

  static String? _nullableStringValue(Object? value) {
    final parsed = _stringValue(value);
    return parsed.isEmpty ? null : parsed;
  }
}
