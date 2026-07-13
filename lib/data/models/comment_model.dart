import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  CommentModel({
    required this.id,
    required this.authorName,
    required this.avatarEmoji,
    required this.text,
    required this.minutesAgo,
    required this.convincingCount,
    required this.repliesCount,
    this.authorId,
    this.parentId,
    this.isBest = false,
    this.isSeedContent = false,
  });

  final String id;
  final String? authorId;
  final String? parentId;
  final String authorName;
  final String avatarEmoji;
  final String text;
  final int minutesAgo;
  int convincingCount;
  int repliesCount;
  bool isBest;
  final bool isSeedContent;

  factory CommentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return CommentModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory CommentModel.fromMap(String id, Map<String, dynamic> data) {
    final authorSnapshot = _mapValue(data['authorSnapshot']);

    return CommentModel(
      id: id,
      authorId: _stringValue(
        data['authorId'],
        fallback: _stringValue(data['userId']),
      ),
      authorName: _stringValue(
        authorSnapshot['displayName'],
        fallback: _stringValue(
          data['userNickname'],
          fallback: _stringValue(data['authorName'], fallback: 'عضو Forsa Pro'),
        ),
      ),
      avatarEmoji: _stringValue(
        authorSnapshot['avatarEmoji'],
        fallback: _stringValue(
          data['userAvatar'],
          fallback: _stringValue(data['avatarEmoji'], fallback: 'business:person_growth'),
        ),
      ),
      text: _stringValue(data['text']),
      parentId: _nullableStringValue(data['parentId']),
      minutesAgo: _minutesAgo(data['createdAt']),
      convincingCount: _intValue(
        data['convincingVotesCount'],
        fallback: _intValue(data['convincingCount']),
      ),
      repliesCount: _intValue(data['repliesCount']),
      isBest: _boolValue(
        data['isBestComment'],
        fallback: _boolValue(data['isBest']),
      ),
      isSeedContent: _boolValue(data['isSeedContent']),
    );
  }

  Map<String, dynamic> toFirestore({
    String? authorId,
    String? parentId,
  }) {
    return {
      if (authorId != null) 'authorId': authorId,
      if (authorId != null) 'userId': authorId,
      'authorSnapshot': {
        'displayName': authorName,
        'avatarEmoji': avatarEmoji,
      },
      'userNickname': authorName,
      'userAvatar': avatarEmoji,
      'authorName': authorName,
      'avatarEmoji': avatarEmoji,
      'text': text,
      'parentId': parentId,
      'status': 'visible',
      'convincingVotesCount': convincingCount,
      'convincingCount': convincingCount,
      'repliesCount': repliesCount,
      'reportsCount': 0,
      'isBestComment': isBest,
      'isBest': isBest,
      'isSeedContent': isSeedContent,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String get timeLabel {
    if (minutesAgo < 60) return 'منذ $minutesAgo دقيقة';
    final hours = (minutesAgo / 60).floor();
    if (hours < 24) return 'منذ $hours ساعة';
    return 'منذ ${(hours / 24).floor()} يوم';
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _nullableStringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return fallback;
  }

  static bool _boolValue(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    return fallback;
  }

  static int _minutesAgo(Object? value) {
    if (value is Timestamp) {
      final minutes = DateTime.now().difference(value.toDate()).inMinutes;
      return minutes < 1 ? 1 : minutes;
    }

    if (value is DateTime) {
      final minutes = DateTime.now().difference(value).inMinutes;
      return minutes < 1 ? 1 : minutes;
    }

    return 1;
  }
}
