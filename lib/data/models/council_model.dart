import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment_model.dart';

enum VoteOption { support, against, neutral }

enum CouncilStatus { active, endingSoon, closed }

String voteOptionToFirestore(VoteOption option) {
  switch (option) {
    case VoteOption.support:
      return 'support';
    case VoteOption.against:
      return 'against';
    case VoteOption.neutral:
      return 'neutral';
  }
}

VoteOption? voteOptionFromFirestore(Object? value) {
  switch (value) {
    case 'support':
    case 'مع':
      return VoteOption.support;
    case 'against':
    case 'ضد':
      return VoteOption.against;
    case 'neutral':
    case 'محايد':
      return VoteOption.neutral;
  }

  return null;
}

String councilStatusToFirestore(CouncilStatus status) {
  switch (status) {
    case CouncilStatus.active:
      return 'active';
    case CouncilStatus.endingSoon:
      return 'endingSoon';
    case CouncilStatus.closed:
      return 'closed';
  }
}

CouncilStatus councilStatusFromFirestore(Object? value) {
  switch (value) {
    case 'endingSoon':
      return CouncilStatus.endingSoon;
    case 'closed':
    case 'ended':
    case 'hidden':
    case 'deleted':
    case 'scheduled':
    case 'draft':
      return CouncilStatus.closed;
    case 'active':
    case 'votingClosed':
      return CouncilStatus.active;
    default:
      return CouncilStatus.active;
  }
}

class CouncilModel {
  CouncilModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.participants,
    required this.commentsCount,
    required this.votesCount,
    required this.supportPercent,
    required this.againstPercent,
    required this.neutralPercent,
    required this.endsIn,
    required this.comments,
    this.isPrivate = false,
    this.allowComments = true,
    this.categoryId = 'general',
    this.city = '',
    this.isSeedContent = false,
    this.isCouncilOfDay = false,
    this.isPinned = false,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.coverImageUrl,
    this.coverThumbnailUrl,
    this.coverMediumUrl,
    this.imageUrls = const [],
    this.thumbnailUrls = const [],
    this.mediumImageUrls = const [],
    this.hasVoted = false,
    this.selectedOption,
  });

  final String id;
  String title;
  String description;
  String categoryId;
  String category;
  String city;
  bool isSeedContent;
  CouncilStatus status;
  int participants;
  int commentsCount;
  int votesCount;
  int supportPercent;
  int againstPercent;
  int neutralPercent;
  String endsIn;
  List<CommentModel> comments;
  bool isPrivate;
  bool allowComments;
  bool isCouncilOfDay;
  bool isPinned;
  String? createdBy;
  String? createdByName;
  DateTime? createdAt;
  String? coverImageUrl;
  String? coverThumbnailUrl;
  String? coverMediumUrl;
  List<String> imageUrls;
  List<String> thumbnailUrls;
  List<String> mediumImageUrls;
  bool hasVoted;
  VoteOption? selectedOption;

  bool get isVotingClosed => status == CouncilStatus.closed;

  String? get thumbnailCoverUrl =>
      coverThumbnailUrl ?? coverMediumUrl ?? coverImageUrl;

  String? get mediumCoverUrl =>
      coverMediumUrl ?? coverThumbnailUrl ?? coverImageUrl;

  List<String> get thumbnailImageUrls =>
      thumbnailUrls.isNotEmpty ? thumbnailUrls : imageUrls;

  List<String> get mediumDisplayImageUrls =>
      mediumImageUrls.isNotEmpty ? mediumImageUrls : imageUrls;

  factory CouncilModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return CouncilModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory CouncilModel.fromMap(String id, Map<String, dynamic> data) {
    final voteCounts = _mapValue(data['voteCounts']);
    final percentages = _mapValue(data['percentages']);
    final supportCount = _intValue(
      voteCounts['support'],
      fallback: _intValue(voteCounts['yes']),
    );
    final againstCount = _intValue(
      voteCounts['against'],
      fallback: _intValue(voteCounts['no']),
    );
    final neutralCount = _intValue(voteCounts['neutral']);
    final countedVotes = supportCount + againstCount + neutralCount;
    final totalVotes = _intValue(data['votesCount'], fallback: countedVotes);
    final imageUrls = _stringListValue(data['imageUrls']);
    final thumbnailUrls = _stringListValue(data['thumbnailUrls']);
    final mediumImageUrls = _stringListValue(data['mediumImageUrls']);
    final coverImageUrl = _stringValue(data['coverImageUrl']);
    final coverThumbnailUrl = _stringValue(data['coverThumbnailUrl']);
    final coverMediumUrl = _stringValue(data['coverMediumUrl']);

    return CouncilModel(
      id: id,
      title: _stringValue(data['title'], fallback: 'فرصة بدون عنوان'),
      description: _stringValue(
        data['description'],
        fallback: 'شاركنا رأيك في هذه الفرصة.',
      ),
      categoryId: _stringValue(
        data['categoryId'],
        fallback: _stringValue(data['category'], fallback: 'general'),
      ),
      category: _stringValue(
        data['categoryName'],
        fallback: _stringValue(data['category'], fallback: 'عام'),
      ),
      city: _stringValue(data['city']),
      isSeedContent: _boolValue(data['isSeedContent'], fallback: false),
      status: councilStatusFromFirestore(data['status']),
      participants: _intValue(
        data['participantsCount'],
        fallback: _intValue(data['participants'], fallback: totalVotes),
      ),
      commentsCount: _intValue(data['commentsCount']),
      votesCount: totalVotes,
      supportPercent: _intValue(
        percentages['support'],
        fallback: _intValue(
          data['supportPercent'],
          fallback: _percent(supportCount, totalVotes),
        ),
      ),
      againstPercent: _intValue(
        percentages['against'],
        fallback: _intValue(
          data['againstPercent'],
          fallback: _percent(againstCount, totalVotes),
        ),
      ),
      neutralPercent: _intValue(
        percentages['neutral'],
        fallback: _intValue(
          data['neutralPercent'],
          fallback: _percent(neutralCount, totalVotes),
        ),
      ),
      endsIn: _stringValue(data['endsIn']),
      comments: _commentsFromValue(data['comments']),
      isPrivate: data['visibility'] == 'private' ||
          data['visibility'] == 'linkOnly' ||
          data['visibility'] == 'link_only' ||
          _boolValue(data['isPrivate'], fallback: false),
      allowComments: _boolValue(data['allowComments'], fallback: true),
      isCouncilOfDay: _boolValue(data['isCouncilOfDay'], fallback: false),
      isPinned: _boolValue(data['isPinned'], fallback: false),
      createdBy: _stringValue(
        data['createdBy'],
        fallback: _stringValue(data['ownerId']),
      ),
      createdByName: _stringValue(
        data['createdByName'],
        fallback: _stringValue(_mapValue(data['ownerSnapshot'])['displayName']),
      ),
      createdAt: _dateTimeValue(data['createdAt']),
      coverImageUrl: coverImageUrl.isNotEmpty
          ? coverImageUrl
          : (imageUrls.isNotEmpty ? imageUrls.first : null),
      coverThumbnailUrl: coverThumbnailUrl.isNotEmpty
          ? coverThumbnailUrl
          : (thumbnailUrls.isNotEmpty ? thumbnailUrls.first : null),
      coverMediumUrl: coverMediumUrl.isNotEmpty
          ? coverMediumUrl
          : (mediumImageUrls.isNotEmpty ? mediumImageUrls.first : null),
      imageUrls: imageUrls.isNotEmpty
          ? imageUrls
          : (coverImageUrl.isNotEmpty ? [coverImageUrl] : const []),
      thumbnailUrls: thumbnailUrls,
      mediumImageUrls: mediumImageUrls,
      hasVoted: _boolValue(data['hasVoted'], fallback: false),
      selectedOption: voteOptionFromFirestore(data['selectedOption']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'categoryName': category,
      'category': category,
      if (city.trim().isNotEmpty) 'city': city.trim(),
      if (city.trim().isNotEmpty) 'countryCode': 'SA',
      if (city.trim().isNotEmpty) 'countryName': 'المملكة العربية السعودية',
      'isSeedContent': isSeedContent,
      if (createdBy != null) 'createdBy': createdBy,
      if (createdByName != null) 'createdByName': createdByName,
      'status': councilStatusToFirestore(status),
      'visibility': isPrivate ? 'linkOnly' : 'public',
      'type': isPrivate ? 'private' : 'public',
      'allowComments': allowComments,
      'allowReplies': true,
      'participantsCount': participants,
      'commentsCount': commentsCount,
      'votesCount': votesCount,
      'voteCounts': {
        'support': _countFromPercent(supportPercent),
        'against': _countFromPercent(againstPercent),
        'neutral': _countFromPercent(neutralPercent),
      },
      'percentages': {
        'support': supportPercent,
        'against': againstPercent,
        'neutral': neutralPercent,
      },
      'endsIn': endsIn,
      'isPrivate': isPrivate,
      'isCouncilOfDay': isCouncilOfDay,
      'isPinned': isPinned,
      'coverImageUrl': coverImageUrl,
      if (coverThumbnailUrl != null) 'coverThumbnailUrl': coverThumbnailUrl,
      if (coverMediumUrl != null) 'coverMediumUrl': coverMediumUrl,
      'imageUrls': imageUrls,
      if (thumbnailUrls.isNotEmpty) 'thumbnailUrls': thumbnailUrls,
      if (mediumImageUrls.isNotEmpty) 'mediumImageUrls': mediumImageUrls,
      'imagesCount': imageUrls.length,
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

  static List<String> _stringListValue(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList(growable: false);
  }

  // ignore: unused_element
  static String _normalizeEndsIn(String value) {
    final label = value.trim();
    return label == 'انتهى' ? 'انتهى الرأي السريع' : label;
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
  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int _percent(int count, int total) {
    if (total <= 0) return 0;
    return ((count / total) * 100).round();
  }

  int _countFromPercent(int percent) {
    if (votesCount <= 0 || percent <= 0) return 0;
    return ((percent / 100) * votesCount).round();
  }

  static List<CommentModel> _commentsFromValue(Object? value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map(
          (comment) => CommentModel.fromMap(
            comment['id']?.toString() ?? '',
            Map<String, dynamic>.from(comment),
          ),
        )
        .toList();
  }

  // ignore: unused_element
  static String _endsInLabel(Object? value) {
    if (value is! Timestamp) return '';

    final difference = value.toDate().difference(DateTime.now());
    if (difference.isNegative) return 'انتهى الرأي السريع';

    final minutes = difference.inMinutes;
    if (minutes < 60) return 'ينتهي خلال $minutes دقيقة';

    final hours = difference.inHours;
    if (hours < 24) return 'ينتهي خلال $hours ساعة';

    final days = difference.inDays;
    return 'ينتهي خلال $days يوم';
  }
}
