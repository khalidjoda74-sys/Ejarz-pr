import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    required this.type,
    this.read = false,
    this.targetRoute,
    this.councilId,
    this.commentId,
    this.conversationId,
    this.messageId,
    this.iconKey,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final IconData icon;
  final String type;
  final bool read;
  final String? targetRoute;
  final String? councilId;
  final String? commentId;
  final String? conversationId;
  final String? messageId;
  final String? iconKey;
  final DateTime? createdAt;

  factory NotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return NotificationModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory NotificationModel.fromMap(String id, Map<String, dynamic> data) {
    final type = _stringValue(data['type'], fallback: 'general');
    final createdAt = _dateTimeValue(data['createdAt']);

    return NotificationModel(
      id: id,
      title: _stringValue(data['title'], fallback: 'إشعار جديد'),
      message: _stringValue(
        data['body'],
        fallback: _stringValue(data['message']),
      ),
      time: _stringValue(
        data['time'],
        fallback: _timeLabel(createdAt),
      ),
      icon: notificationIconForType(
        _stringValue(data['iconKey'], fallback: type),
      ),
      type: type,
      read: _boolValue(data['read']),
      targetRoute: _nullableString(data['targetRoute']),
      councilId: _nullableString(data['councilId']),
      commentId: _nullableString(data['commentId']),
      conversationId: _nullableString(data['conversationId']),
      messageId: _nullableString(data['messageId']),
      iconKey: _nullableString(data['iconKey']),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'title': title,
      'body': message,
      'message': message,
      'read': read,
      'targetRoute': targetRoute,
      'councilId': councilId,
      'commentId': commentId,
      'conversationId': conversationId,
      'messageId': messageId,
      'iconKey': iconKey ?? type,
      'createdAt':
          createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
    };
  }

  static IconData notificationIconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      case 'reply':
        return Icons.mode_comment_outlined;
      case 'result_ready':
      case 'council_closed':
        return Icons.insights_rounded;
      case 'owner_activity':
        return Icons.groups_rounded;
      case 'report':
        return Icons.flag_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _nullableString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
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

  static String _timeLabel(DateTime? createdAt) {
    if (createdAt == null) return 'الآن';

    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'الآن';
    if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    }
    if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    }
    return 'منذ ${difference.inDays} يوم';
  }
}
