import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment_model.dart';
import 'council_model.dart';

class CouncilResultModel {
  const CouncilResultModel({
    required this.councilId,
    required this.title,
    required this.description,
    required this.categoryName,
    required this.totalVotes,
    required this.supportVotes,
    required this.againstVotes,
    required this.neutralVotes,
    required this.supportPercent,
    required this.againstPercent,
    required this.neutralPercent,
    required this.bestComments,
    required this.summaryText,
    this.createdAt,
  });

  final String councilId;
  final String title;
  final String description;
  final String categoryName;
  final int totalVotes;
  final int supportVotes;
  final int againstVotes;
  final int neutralVotes;
  final int supportPercent;
  final int againstPercent;
  final int neutralPercent;
  final List<CommentModel> bestComments;
  final String summaryText;
  final DateTime? createdAt;

  factory CouncilResultModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return CouncilResultModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory CouncilResultModel.fromMap(String id, Map<String, dynamic> data) {
    final voteCounts = _mapValue(data['voteCounts']);
    final percentages = _mapValue(data['percentages']);
    final totalVotes = _intValue(data['totalVotes']);

    return CouncilResultModel(
      councilId: _stringValue(data['councilId'], fallback: id),
      title: _stringValue(data['title'], fallback: 'فرصة بدون عنوان'),
      description: _stringValue(
        data['description'],
        fallback: 'تم إغلاق هذه الفرصة وظهرت نتيجتها النهائية.',
      ),
      categoryName: _stringValue(data['categoryName'], fallback: 'عام'),
      totalVotes: totalVotes,
      supportVotes: _intValue(voteCounts['support']),
      againstVotes: _intValue(voteCounts['against']),
      neutralVotes: _intValue(voteCounts['neutral']),
      supportPercent: _intValue(
        percentages['support'],
        fallback: _percent(_intValue(voteCounts['support']), totalVotes),
      ),
      againstPercent: _intValue(
        percentages['against'],
        fallback: _percent(_intValue(voteCounts['against']), totalVotes),
      ),
      neutralPercent: _intValue(
        percentages['neutral'],
        fallback: _percent(_intValue(voteCounts['neutral']), totalVotes),
      ),
      bestComments: _commentsFromValue(data['bestComments']),
      summaryText: _stringValue(
        data['summaryText'],
        fallback: 'ظهرت نتيجة الفرصة النهائية ويمكن مراجعة أبرز الآراء.',
      ),
      createdAt: _dateTimeValue(data['createdAt']),
    );
  }

  CouncilModel toCouncilModel() {
    return CouncilModel(
      id: councilId,
      title: title,
      description: description,
      category: categoryName,
      status: CouncilStatus.closed,
      participants: totalVotes,
      commentsCount: bestComments.length,
      votesCount: totalVotes,
      supportPercent: supportPercent,
      againstPercent: againstPercent,
      neutralPercent: neutralPercent,
      endsIn: 'انتهى',
      comments: List<CommentModel>.from(bestComments),
      allowComments: false,
      createdAt: createdAt,
      hasVoted: true,
    );
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

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int _percent(int count, int total) {
    if (total <= 0) return 0;
    return ((count / total) * 100).round();
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
}
