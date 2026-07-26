import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/reusable_stream.dart';
import '../models/notification_model.dart';
import '../services/firestore_service.dart';

class FirebaseNotificationRepository {
  FirebaseNotificationRepository._();

  static final FirebaseNotificationRepository instance =
      FirebaseNotificationRepository._();

  final FirestoreService _firestore = FirestoreService.instance;

  Stream<List<NotificationModel>> watchNotifications({
    required String uid,
    String? type,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _firestore.userNotifications(uid);

    if (type != null && type.isNotEmpty && type != 'all' && type != 'الكل') {
      query = query.where('type', isEqualTo: type);
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(NotificationModel.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<int> watchUnreadCount(String uid) {
    if (uid.trim().isEmpty) return reusableValueStream(0);

    return _firestore
        .userNotifications(uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(NotificationModel.fromFirestore)
              .where(_isVisibleNotification)
              .length,
        );
  }

  bool _isVisibleNotification(NotificationModel notification) {
    if (notification.type == 'demo' ||
        notification.type == 'best_comment' ||
        notification.title.contains('أفضل مساهمة')) {
      return false;
    }

    final references = <String?>[
      notification.id,
      notification.targetRoute,
      notification.councilId,
      notification.conversationId,
      notification.messageId,
    ];
    return !references.whereType<String>().any((value) {
      final normalized = value.trim().toLowerCase();
      return normalized.startsWith('demo_') ||
          normalized.contains('/demo_');
    });
  }

  Future<String> createNotification({
    required String uid,
    required String type,
    required String title,
    required String body,
    String? targetRoute,
    String? councilId,
    String? commentId,
  }) async {
    final doc = _firestore.userNotifications(uid).doc();

    await doc.set({
      'type': type,
      'title': title,
      'body': body,
      'read': false,
      'targetRoute': targetRoute,
      'councilId': councilId,
      'commentId': commentId,
      'iconKey': type,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  Future<void> markAsRead({
    required String uid,
    required String notificationId,
  }) {
    return _firestore.userNotifications(uid).doc(notificationId).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAllAsRead(String uid) async {
    final snapshot = await _firestore
        .userNotifications(uid)
        .where('read', isEqualTo: false)
        .limit(100)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(
        doc.reference,
        {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> deleteNotification({
    required String uid,
    required String notificationId,
  }) {
    return _firestore.userNotifications(uid).doc(notificationId).delete();
  }
}
