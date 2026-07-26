import 'package:cloud_firestore/cloud_firestore.dart';

enum PublicProfileKind { member, demo }

class PublicProfileTarget {
  const PublicProfileTarget({
    required this.kind,
    required this.id,
    required this.uid,
    this.seed,
  });

  factory PublicProfileTarget.member({
    required String uid,
    PublicProfileModel? seed,
  }) {
    final normalizedUid = uid.trim();
    return PublicProfileTarget(
      kind: PublicProfileKind.member,
      id: normalizedUid,
      uid: normalizedUid,
      seed: seed,
    );
  }

  factory PublicProfileTarget.demo({
    required PublicProfileModel seed,
  }) {
    return PublicProfileTarget(
      kind: PublicProfileKind.demo,
      id: seed.id,
      uid: null,
      seed: seed,
    );
  }

  final PublicProfileKind kind;
  final String id;
  final String? uid;
  final PublicProfileModel? seed;

  bool get isDemo => kind == PublicProfileKind.demo;
  String get displayName => seed?.displayName ?? 'عضو فرصة برو';
  String get username => seed?.username ?? '';
  String get avatarEmoji => seed?.avatarEmoji ?? 'business:person_growth';
  String? get publicPhotoUrl => seed?.publicPhotoUrl;
}

class PublicProfileModel {
  const PublicProfileModel({
    required this.uid,
    required this.id,
    required this.displayName,
    required this.username,
    required this.avatarEmoji,
    required this.publicPhotoUrl,
    required this.createdAt,
    required this.isVisible,
    required this.demo,
  });

  final String uid;
  final String id;
  final String displayName;
  final String username;
  final String avatarEmoji;
  final String? publicPhotoUrl;
  final DateTime? createdAt;
  final bool isVisible;
  final bool demo;

  PublicProfileKind get kind =>
      demo ? PublicProfileKind.demo : PublicProfileKind.member;

  factory PublicProfileModel.seed({
    required String uid,
    String? id,
    required String displayName,
    String username = '',
    String avatarEmoji = 'business:person_growth',
    String? publicPhotoUrl,
    DateTime? createdAt,
    bool isVisible = true,
    bool demo = false,
  }) {
    final normalizedUid = uid.trim();
    final normalizedId = id?.trim();
    return PublicProfileModel(
      uid: normalizedUid,
      id: normalizedId == null || normalizedId.isEmpty
          ? normalizedUid
          : normalizedId,
      displayName: _stringValue(
        displayName,
        fallback: 'عضو فرصة برو',
      ),
      username: username.trim(),
      avatarEmoji: _stringValue(
        avatarEmoji,
        fallback: 'business:person_growth',
      ),
      publicPhotoUrl: _nullableString(publicPhotoUrl),
      createdAt: createdAt,
      isVisible: isVisible,
      demo: demo,
    );
  }

  factory PublicProfileModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return PublicProfileModel.fromMap(
      snapshot.data() ?? const <String, dynamic>{},
      documentId: snapshot.id,
    );
  }

  factory PublicProfileModel.fromMap(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    final safeDocumentId = documentId.trim();
    return PublicProfileModel(
      uid: _stringValue(data['uid'], fallback: safeDocumentId),
      id: _stringValue(data['id'], fallback: safeDocumentId),
      displayName: _stringValue(
        data['displayName'],
        fallback: 'عضو فرصة برو',
      ),
      username: _stringValue(data['username']),
      avatarEmoji: _stringValue(
        data['avatarEmoji'],
        fallback: 'business:person_growth',
      ),
      publicPhotoUrl: _nullableString(data['publicPhotoUrl']),
      createdAt: _dateTimeValue(data['createdAt']),
      isVisible: data['isVisible'] == true,
      demo: data['demo'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'uid': uid,
      'id': id,
      'displayName': displayName,
      'username': username,
      'avatarEmoji': avatarEmoji,
      'publicPhotoUrl': publicPhotoUrl,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'isVisible': isVisible,
      'demo': demo,
    };
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _nullableString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }
}
