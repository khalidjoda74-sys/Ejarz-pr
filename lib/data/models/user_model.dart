import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  UserModel({
    required this.name,
    required this.username,
    required this.avatarEmoji,
    required this.points,
    required this.comments,
    required this.councils,
    required this.badge,
    this.nicknameLocked = false,
    this.hasChosenPublicIdentity = true,
  });

  String name;
  String username;
  String avatarEmoji;
  int points;
  int comments;
  int councils;
  String badge;
  bool nicknameLocked;
  bool hasChosenPublicIdentity;

  factory UserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return UserModel.fromMap(snapshot.data() ?? const {});
  }

  factory UserModel.fromMap(Map<String, dynamic> data) {
    final stats = _mapValue(data['stats']);
    final nickname = _stringValue(data['nickname']);
    final nicknameKey = _stringValue(data['nicknameKey']);
    final username = _stringValue(data['username']);
    final displayName = _stringValue(
      data['displayName'],
      fallback: _stringValue(data['name']),
    );
    final explicitlyIncomplete = data['identityCompleted'] == false;
    final hasChosenPublicIdentity = !explicitlyIncomplete &&
        (nickname.isNotEmpty ||
            nicknameKey.isNotEmpty ||
            (!data.containsKey('identityCompleted') &&
                username.isNotEmpty &&
                displayName.isNotEmpty));

    return UserModel(
      name: _stringValue(
        nickname,
        fallback: _stringValue(
          displayName,
          fallback: _stringValue(data['name'], fallback: 'عضو Forsa Pro'),
        ),
      ),
      username: _stringValue(
        username,
        fallback: '@forsa_pro_member',
      ),
      avatarEmoji: _stringValue(
        data['avatar'],
        fallback: _stringValue(
          data['avatarEmoji'],
          fallback: 'business:person_growth',
        ),
      ),
      points: _intValue(data['points'], fallback: _intValue(stats['points'])),
      comments: _intValue(
        data['commentsCount'],
        fallback: _intValue(
          stats['commentsCount'],
          fallback: _intValue(data['comments']),
        ),
      ),
      councils: _intValue(
        data['councilsCount'],
        fallback: _intValue(
          stats['councilsCount'],
          fallback: _intValue(data['councils']),
        ),
      ),
      badge: _stringValue(data['badge'], fallback: 'عضو نشط'),
      nicknameLocked: data['nicknameLocked'] == true,
      hasChosenPublicIdentity: hasChosenPublicIdentity,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': name,
      'nickname': name,
      'name': name,
      'username': username,
      'avatar': avatarEmoji,
      'avatarEmoji': avatarEmoji,
      'badge': badge,
      'nicknameLocked': nicknameLocked,
      'role': 'user',
      'subscriptionType': 'free',
      'points': points,
      'commentsCount': comments,
      'councilsCount': councils,
      'reportsCount': 0,
      'stats': {
        'points': points,
        'commentsCount': comments,
        'councilsCount': councils,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, dynamic> newUserDocument({
    required String uid,
    String? displayName,
    String? username,
    String? email,
    String? photoUrl,
    List<String> providerIds = const [],
  }) {
    final safeName = _stringValue(displayName, fallback: 'عضو Forsa Pro');

    return {
      'uid': uid,
      'id': uid,
      'displayName': safeName,
      'nickname': safeName,
      'name': safeName,
      'username': _stringValue(
        username,
        fallback: '@${uid.substring(0, uid.length < 6 ? uid.length : 6)}',
      ),
      'email': email,
      'photoUrl': photoUrl,
      'avatarEmoji': 'business:person_growth',
      'avatar': 'business:person_growth',
      'providerIds': providerIds,
      'nicknameKey': null,
      'nicknameLocked': false,
      'identityCompleted': false,
      'role': 'user',
      'status': 'active',
      'badge': 'عضو نشط',
      'subscriptionType': 'free',
      'points': 0,
      'councilsCount': 0,
      'commentsCount': 0,
      'reportsCount': 0,
      'badges': <String>[],
      'fcmTokens': <String>[],
      'stats': {
        'points': 0,
        'commentsCount': 0,
        'councilsCount': 0,
        'votesCount': 0,
      },
      'notificationPrefs': {
        'pushEnabled': false,
        'inAppEnabled': true,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
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

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return fallback;
  }
}
