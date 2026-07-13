import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  const MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.status,
    required this.readBy,
    this.imageUrl,
    this.imagePath,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String text;
  final String type;
  final String status;
  final List<String> readBy;
  final String? imageUrl;
  final String? imagePath;
  final DateTime? createdAt;

  bool get isImage => type == 'image' && (imageUrl?.isNotEmpty ?? false);

  factory MessageModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return MessageModel(
      id: snapshot.id,
      senderId: _stringValue(data['senderId']),
      text: _stringValue(data['text']),
      type: _stringValue(data['type'], fallback: 'text'),
      status: _stringValue(data['status'], fallback: 'sent'),
      readBy: _stringList(data['readBy']),
      imageUrl: _nullableString(data['imageUrl']),
      imagePath: _nullableString(data['imagePath']),
      createdAt: _dateValue(data['createdAt']),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static DateTime? _dateValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String? _nullableString(Object? value) {
    final text = _stringValue(value);
    return text.isEmpty ? null : text;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}