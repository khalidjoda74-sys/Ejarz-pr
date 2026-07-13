import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/moderation/content_moderation.dart';

import '../models/conversation_model.dart';
import '../models/council_model.dart';
import '../models/message_model.dart';
import '../services/firestore_service.dart';

class MessagingRepository {
  MessagingRepository._();

  static final MessagingRepository instance = MessagingRepository._();

  static const String _demoCurrentUid = 'demo_current_user';

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, List<MessageModel>> _demoMessages =
      <String, List<MessageModel>>{};
  final Map<String, StreamController<List<MessageModel>>> _demoMessageStreams =
      <String, StreamController<List<MessageModel>>>{};
  final StreamController<void> _demoConversationChanges =
      StreamController<void>.broadcast();
  final Set<String> _demoArchivedConversationIds = <String>{};
  final Set<String> _demoDeletedConversationIds = <String>{};
  final Set<String> _demoBlockedConversationIds = <String>{};
  final Set<String> _demoReadConversationIds = <String>{};

  String get viewerUid {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return _demoCurrentUid;
    return user.uid;
  }

  Future<ConversationModel> getOrCreateConversation(CouncilModel council) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول للتواصل مع صاحب المنشور.',
      );
    }

    if (council.isSeedContent) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'editorial-content',
        message: 'هذا منشور تعريفي ولا يرتبط بحساب عضو حقيقي.',
      );
    }

    final ownerId = council.createdBy?.trim() ?? '';
    if (ownerId.isEmpty) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'missing-owner',
        message: 'تعذر تحديد صاحب المنشور.',
      );
    }

    if (ownerId == user.uid) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'self-message',
        message: 'لا يمكنك مراسلة نفسك.',
      );
    }

    if (council.status != CouncilStatus.active) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'inactive-council',
        message: 'هذا المنشور غير متاح للتواصل حاليًا.',
      );
    }

    final conversationId = _conversationId(
      councilId: council.id,
      ownerId: ownerId,
      requesterId: user.uid,
    );
    final ref = _firestore.conversation(conversationId);

    final existing = await ref.get();
    if (existing.exists) return ConversationModel.fromFirestore(existing);

    final ownerSnapshot = await _participantSnapshot(
      ownerId,
      fallbackName: council.createdByName,
    );
    final requesterSnapshot = await _participantSnapshot(
      user.uid,
      fallbackName: user.displayName,
      fallbackPhotoUrl: user.photoURL,
    );

    final data = {
      'councilId': council.id,
      'councilTitle': council.title,
      'ownerId': ownerId,
      'requesterId': user.uid,
      'participantIds': [ownerId, user.uid],
      'participantSnapshots': {
        ownerId: ownerSnapshot.toMap(),
        user.uid: requesterSnapshot.toMap(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageText': '',
      'lastMessageAt': null,
      'lastSenderId': null,
      'unreadCounts': {
        ownerId: 0,
        user.uid: 0,
      },
      'lastReadAt': <String, dynamic>{},
      'status': 'active',
      'blockedBy': <String>[],
      'archivedBy': <String>[],
      'deletedBy': <String>[],
      'reportCount': 0,
    };

    await ref.set(data);
    final created = await ref.get();
    return ConversationModel.fromFirestore(created);
  }

  Stream<ConversationModel?> watchConversation(String conversationId) {
    if (_isDemoConversation(conversationId)) {
      return Stream<ConversationModel?>.multi((controller) {
        void emit() {
          controller.add(_demoConversationById(conversationId, viewerUid));
        }

        emit();
        final subscription = _demoConversationChanges.stream.listen((_) => emit());
        controller.onCancel = subscription.cancel;
      });
    }

    return _firestore.conversation(conversationId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return ConversationModel.fromFirestore(snapshot);
    });
  }

  Stream<List<ConversationModel>> watchMyConversations({
    bool includeArchived = false,
  }) {
    final user = _auth.currentUser;
    final currentUid = user == null || user.isAnonymous ? _demoCurrentUid : user.uid;

    return Stream<List<ConversationModel>>.multi((controller) {
      List<ConversationModel>? firestoreConversations;

      void emit() {
        final remote = firestoreConversations;
        if (remote != null && remote.isNotEmpty) {
          controller.add(List<ConversationModel>.unmodifiable(remote));
          return;
        }
        controller.add(_demoConversationsForView(currentUid, includeArchived));
      }

      emit();
      final demoSubscription = _demoConversationChanges.stream.listen((_) => emit());
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firestoreSubscription;

      if (user != null && !user.isAnonymous) {
        firestoreSubscription = _firestore.conversations
            .where('participantIds', arrayContains: user.uid)
            .snapshots()
            .listen((snapshot) {
          final conversations = snapshot.docs
              .map(ConversationModel.fromFirestore)
              .where((conversation) =>
                  conversation.status == 'active' &&
                  conversation.isArchivedFor(user.uid) == includeArchived &&
                  !conversation.isDeletedFor(user.uid))
              .toList(growable: false);
          conversations.sort((a, b) {
            final aTime = a.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
          firestoreConversations = conversations;
          emit();
        }, onError: (_) {
          firestoreConversations = const <ConversationModel>[];
          emit();
        });
      }

      controller.onCancel = () async {
        await demoSubscription.cancel();
        await firestoreSubscription?.cancel();
      };
    });
  }

  List<ConversationModel> _demoConversationsForView(
    String currentUid,
    bool includeArchived,
  ) {
    final conversations = _demoConversations(currentUid)
        .where((conversation) =>
            conversation.isArchivedFor(currentUid) == includeArchived &&
            !conversation.isDeletedFor(currentUid))
        .toList(growable: false);
    return List<ConversationModel>.unmodifiable(conversations);
  }
  Stream<int> watchUnreadTotal() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return Stream.value(0);
    return watchMyConversations().map(
      (conversations) => conversations.fold<int>(
        0,
        (total, conversation) => total + conversation.unreadFor(user.uid),
      ),
    );
  }

  Stream<List<MessageModel>> watchMessages(String conversationId) {
    if (_isDemoConversation(conversationId)) {
      return _watchDemoMessages(conversationId);
    }

    return _firestore
        .conversationMessages(conversationId)
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(MessageModel.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> sendMessage(String conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 1000) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'message-too-long',
        message: 'الرسالة طويلة جدًا.',
      );
    }

    ContentModeration.ensureAllowed(<String>[trimmed]);

    if (_isDemoConversation(conversationId)) {
      _addDemoMessage(conversationId, trimmed);
      return;
    }

    await _sendMessageRecord(
      conversationId: conversationId,
      lastMessageText: trimmed,
      messageData: {
        'text': trimmed,
        'type': 'text',
      },
    );
  }

  Future<UploadedMessageImage> uploadConversationImage(
    String conversationId,
    XFile image,
  ) async {
    if (_isDemoConversation(conversationId)) {
      return const UploadedMessageImage(
        url: 'demo-image',
        path: 'demo-image',
      );
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(plugin: 'majlisna', code: 'unauthenticated');
    }

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'invalid-image',
        message: 'حجم الصورة يجب ألا يتجاوز 5 ميجا.',
      );
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(image.name)}';
    final ref = _firestore.conversationImageRef(conversationId, user.uid, fileName);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: image.mimeType ?? _contentTypeFor(image.name),
        customMetadata: {
          'conversationId': conversationId,
          'uploadedBy': user.uid,
        },
      ),
    );
    return UploadedMessageImage(
      url: await ref.getDownloadURL(),
      path: ref.fullPath,
    );
  }

  Future<void> sendImageMessage(
    String conversationId, {
    required String imageUrl,
    required String imagePath,
  }) async {
    if (_isDemoConversation(conversationId)) {
      _addDemoMessage(conversationId, 'تم إرفاق صورة ضمن محادثة تجريبية.');
      return;
    }

    final cleanUrl = imageUrl.trim();
    final cleanPath = imagePath.trim();
    if (cleanUrl.isEmpty || cleanPath.isEmpty) {
      throw FirebaseException(plugin: 'majlisna', code: 'invalid-image');
    }

    await _sendMessageRecord(
      conversationId: conversationId,
      lastMessageText: 'صورة',
      messageData: {
        'text': 'صورة',
        'type': 'image',
        'imageUrl': cleanUrl,
        'imagePath': cleanPath,
      },
    );
  }

  Future<void> markConversationRead(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoReadConversationIds.add(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'unreadCounts.${user.uid}': 0,
      'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveConversation(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoArchivedConversationIds.add(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'archivedBy': FieldValue.arrayUnion([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unarchiveConversation(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoArchivedConversationIds.remove(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'archivedBy': FieldValue.arrayRemove([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteConversationForMe(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoDeletedConversationIds.add(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'deletedBy': FieldValue.arrayUnion([user.uid]),
      'unreadCounts.${user.uid}': 0,
      'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> blockConversation(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoBlockedConversationIds.add(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(plugin: 'majlisna', code: 'unauthenticated');
    }

    final conversationRef = _firestore.conversation(conversationId);
    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(conversationRef);
      if (!snapshot.exists) {
        throw FirebaseException(plugin: 'majlisna', code: 'not-found');
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
      final participantIds = _stringList(data['participantIds']);
      if (!participantIds.contains(user.uid)) {
        throw FirebaseException(plugin: 'majlisna', code: 'permission-denied');
      }
      final otherUid = participantIds.firstWhere(
        (uid) => uid != user.uid,
        orElse: () => '',
      );
      if (otherUid.isEmpty) {
        throw FirebaseException(plugin: 'majlisna', code: 'missing-participant');
      }
      final blockedUserRef = _firestore.db
          .collection('users')
          .doc(user.uid)
          .collection('blockedUsers')
          .doc(otherUid);
      transaction.set(blockedUserRef, {
        'uid': otherUid,
        'conversationId': conversationId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(conversationRef, {
        'blockedBy': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> unblockConversation(String conversationId) async {
    if (_isDemoConversation(conversationId)) {
      _demoBlockedConversationIds.remove(conversationId);
      _demoConversationChanges.add(null);
      return;
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(plugin: 'majlisna', code: 'unauthenticated');
    }

    final conversationRef = _firestore.conversation(conversationId);
    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(conversationRef);
      if (!snapshot.exists) {
        throw FirebaseException(plugin: 'majlisna', code: 'not-found');
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
      final participantIds = _stringList(data['participantIds']);
      if (!participantIds.contains(user.uid)) {
        throw FirebaseException(plugin: 'majlisna', code: 'permission-denied');
      }
      final otherUid = participantIds.firstWhere(
        (uid) => uid != user.uid,
        orElse: () => '',
      );
      if (otherUid.isNotEmpty) {
        final blockedUserRef = _firestore.db
            .collection('users')
            .doc(user.uid)
            .collection('blockedUsers')
            .doc(otherUid);
        transaction.delete(blockedUserRef);
      }
      transaction.update(conversationRef, {
        'blockedBy': FieldValue.arrayRemove([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reportConversation(
    String conversationId, {
    required String reason,
    String? details,
  }) async {
    if (_isDemoConversation(conversationId)) return;

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(plugin: 'majlisna', code: 'unauthenticated');
    }

    final cleanReason = reason.trim();
    final cleanDetails = details?.trim() ?? '';
    if (cleanReason.length < 2) {
      throw FirebaseException(plugin: 'majlisna', code: 'invalid-report');
    }

    final conversationRef = _firestore.conversation(conversationId);
    final reportRef = _firestore.reports.doc();
    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(conversationRef);
      if (!snapshot.exists) {
        throw FirebaseException(plugin: 'majlisna', code: 'not-found');
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
      final participantIds = _stringList(data['participantIds']);
      if (!participantIds.contains(user.uid)) {
        throw FirebaseException(plugin: 'majlisna', code: 'permission-denied');
      }

      transaction.set(reportRef, {
        'targetType': 'conversation',
        'targetId': conversationId,
        'targetPreview': _stringValue(data['councilTitle'], fallback: conversationId),
        'conversationId': conversationId,
        'councilId': _stringValue(data['councilId']),
        'reason': cleanReason,
        'description': cleanDetails.length > 500
            ? cleanDetails.substring(0, 500)
            : cleanDetails,
        'details': cleanDetails.length > 500
            ? cleanDetails.substring(0, 500)
            : cleanDetails,
        'reportedBy': user.uid,
        'reporterId': user.uid,
        'status': 'pending',
        'priority': 'high',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(conversationRef, {
        'reportCount': FieldValue.increment(1),
        'lastReportedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _sendMessageRecord({
    required String conversationId,
    required String lastMessageText,
    required Map<String, dynamic> messageData,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لإرسال الرسائل.',
      );
    }

    final conversationRef = _firestore.conversation(conversationId);
    final messageRef = _firestore.conversationMessages(conversationId).doc();

    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(conversationRef);
      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'not-found',
          message: 'المحادثة غير موجودة.',
        );
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final participantIds = _stringList(data['participantIds']);
      if (!participantIds.contains(user.uid)) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'permission-denied',
          message: 'لا يمكنك إرسال رسالة في هذه المحادثة.',
        );
      }
      if (data['status'] != 'active') {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'inactive-conversation',
          message: 'هذه المحادثة غير متاحة للإرسال.',
        );
      }
      if (_stringList(data['blockedBy']).isNotEmpty) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'blocked-conversation',
          message: 'لا يمكن إرسال رسائل جديدة بعد حظر المحادثة.',
        );
      }

      final receiverIds = participantIds.where((id) => id != user.uid).toList();
      final updateData = <String, dynamic>{
        'lastMessageText': lastMessageText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'archivedBy': FieldValue.arrayRemove(participantIds),
        'deletedBy': FieldValue.arrayRemove(participantIds),
      };
      for (final receiverId in receiverIds) {
        updateData['unreadCounts.$receiverId'] = FieldValue.increment(1);
      }
      updateData['unreadCounts.${user.uid}'] = 0;

      transaction.set(messageRef, {
        ...messageData,
        'senderId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
        'readBy': [user.uid],
      });
      transaction.update(conversationRef, updateData);
    });
  }

  String _conversationId({
    required String councilId,
    required String ownerId,
    required String requesterId,
  }) {
    final raw = '${councilId}_${ownerId}_$requesterId';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  Future<ParticipantSnapshot> _participantSnapshot(
    String uid, {
    String? fallbackName,
    String? fallbackPhotoUrl,
  }) async {
    try {
      final snapshot = await _firestore.user(uid).get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      return ParticipantSnapshot.fromMap({
        'displayName': _stringValue(
          data['nickname'],
          fallback: _stringValue(
            data['displayName'],
            fallback: _stringValue(fallbackName, fallback: 'عضو Forsa Pro'),
          ),
        ),
        'avatarEmoji': _stringValue(data['avatarEmoji'], fallback: _stringValue(data['avatar'])),
        'photoUrl': _stringValue(data['photoUrl'], fallback: _stringValue(fallbackPhotoUrl)),
      });
    } catch (_) {
      return ParticipantSnapshot(
        displayName: _stringValue(fallbackName, fallback: 'عضو Forsa Pro'),
        photoUrl: _stringValue(fallbackPhotoUrl),
      );
    }
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  String _safeFileName(String name) {
    final clean = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return clean.isEmpty ? 'message_image.jpg' : clean;
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  bool _isDemoConversation(String conversationId) {
    return conversationId.startsWith('demo_message_');
  }

  List<ConversationModel> _demoConversations(String currentUid) {
    final conversations = <ConversationModel>[
      _demoConversation(
        id: 'demo_message_partner_riyadh',
        currentUid: currentUid,
        otherUid: 'demo_noura',
        otherName: 'نورة العتيبي',
        otherAvatar: 'business:handshake',
        councilId: 'demo_council_partner_riyadh',
        councilTitle: 'شراكة لتوسعة مطعم صحي قائم في شمال الرياض',
        lastMessageText: 'ممتاز، أرسل لي تفاصيل المبيعات الشهرية وموقع الفرع.',
        unread: 2,
        minutesAgo: 7,
      ),
      _demoConversation(
        id: 'demo_message_transfer_jeddah',
        currentUid: currentUid,
        otherUid: 'demo_fahad',
        otherName: 'فهد الزهراني',
        otherAvatar: 'business:transfer',
        councilId: 'demo_council_transfer_jeddah',
        councilTitle: 'فرصة تقبيل مغسلة سيارات في جدة مع عقود ثابتة',
        lastMessageText: 'هل يشمل التقبيل المعدات والعمالة الحالية؟',
        unread: 1,
        minutesAgo: 32,
      ),
      _demoConversation(
        id: 'demo_message_funding_dammam',
        currentUid: currentUid,
        otherUid: 'demo_sara',
        otherName: 'سارة القحطاني',
        otherAvatar: 'business:funding',
        councilId: 'demo_council_funding_dammam',
        councilTitle: 'أبحث عن فرصة تشغيلية بمبلغ 180 ألف في الدمام',
        lastMessageText: 'الأهم عندي وضوح المصاريف قبل الدخول.',
        unread: 0,
        minutesAgo: 118,
      ),
      _demoConversation(
        id: 'demo_message_market_makkah',
        currentUid: currentUid,
        otherUid: 'demo_mansour',
        otherName: 'منصور الحربي',
        otherAvatar: 'business:experience',
        councilId: 'demo_council_market_makkah',
        councilTitle: 'تجربة تشغيل متجر قهوة مختصة داخل مجمع تجاري',
        lastMessageText: 'التجربة مفيدة، خصوصًا نقطة الإيجار ونسبة العمالة.',
        unread: 0,
        minutesAgo: 260,
      ),
    ];
    conversations.sort((a, b) {
      final aTime = a.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return conversations;
  }

  ConversationModel _demoConversationById(String id, String currentUid) {
    return _demoConversations(currentUid).firstWhere(
      (conversation) => conversation.id == id,
      orElse: () => _demoConversations(currentUid).first,
    );
  }

  ConversationModel _demoConversation({
    required String id,
    required String currentUid,
    required String otherUid,
    required String otherName,
    required String otherAvatar,
    required String councilId,
    required String councilTitle,
    required String lastMessageText,
    required int unread,
    required int minutesAgo,
  }) {
    final now = DateTime.now();
    return ConversationModel(
      id: id,
      councilId: councilId,
      councilTitle: councilTitle,
      ownerId: otherUid,
      requesterId: currentUid,
      participantIds: <String>[currentUid, otherUid],
      participantSnapshots: <String, ParticipantSnapshot>{
        currentUid: const ParticipantSnapshot(
          displayName: 'أنت',
          avatarEmoji: 'business:person_growth',
        ),
        otherUid: ParticipantSnapshot(
          displayName: otherName,
          avatarEmoji: otherAvatar,
        ),
      },
      unreadCounts: <String, int>{
        currentUid: _demoReadConversationIds.contains(id) ? 0 : unread,
        otherUid: 0,
      },
      status: 'active',
      blockedBy: _demoBlockedConversationIds.contains(id)
          ? <String>[currentUid]
          : const <String>[],
      archivedBy: _demoArchivedConversationIds.contains(id)
          ? <String>[currentUid]
          : const <String>[],
      deletedBy: _demoDeletedConversationIds.contains(id)
          ? <String>[currentUid]
          : const <String>[],
      lastMessageText: lastMessageText,
      lastMessageAt: now.subtract(Duration(minutes: minutesAgo)),
      lastSenderId: unread > 0 ? otherUid : currentUid,
      createdAt: now.subtract(Duration(days: 2, hours: minutesAgo ~/ 60)),
      updatedAt: now.subtract(Duration(minutes: minutesAgo)),
    );
  }

  Stream<List<MessageModel>> _watchDemoMessages(String conversationId) async* {
    yield List<MessageModel>.unmodifiable(
      _demoMessagesFor(conversationId, viewerUid),
    );
    final controller = _demoMessageStreams.putIfAbsent(
      conversationId,
      () => StreamController<List<MessageModel>>.broadcast(),
    );
    yield* controller.stream;
  }

  List<MessageModel> _demoMessagesFor(String conversationId, String currentUid) {
    final existing = _demoMessages[conversationId];
    if (existing != null) return existing;

    final otherUid = _demoConversationById(conversationId, currentUid)
        .participantIds
        .firstWhere((uid) => uid != currentUid, orElse: () => 'demo_member');
    final now = DateTime.now();
    List<MessageModel> messages;

    switch (conversationId) {
      case 'demo_message_partner_riyadh':
        messages = <MessageModel>[
          _demoMessage('m1', otherUid, 'السلام عليكم، شفت فرصة الشراكة لتوسعة المطعم. هل التوسعة لفرع جديد أو زيادة الطاقة الحالية؟', now, 95, currentUid),
          _demoMessage('m2', currentUid, 'وعليكم السلام. الخطة فرع ثاني داخل نفس النطاق، والمطبخ المركزي موجود.', now, 82, currentUid),
          _demoMessage('m3', otherUid, 'ممتاز. كم متوسط المبيعات الشهرية للفرع الحالي؟ وهل يوجد قوائم مالية مختصرة؟', now, 54, currentUid),
          _demoMessage('m4', currentUid, 'المتوسط قريب من 165 ألف، وصافي التشغيل يتغير حسب المواسم. أقدر أرسل ملخص بدون بيانات حساسة.', now, 26, currentUid),
          _demoMessage('m5', otherUid, 'ممتاز، أرسل لي تفاصيل المبيعات الشهرية وموقع الفرع.', now, 7, currentUid),
        ];
        break;
      case 'demo_message_transfer_jeddah':
        messages = <MessageModel>[
          _demoMessage('m1', currentUid, 'مرحبًا فهد، هل فرصة المغسلة لا تزال متاحة للتقبيل؟', now, 190, currentUid),
          _demoMessage('m2', otherUid, 'نعم متاحة. الموقع على شارع نشط وفيه عقود شهرية مع شركتين.', now, 160, currentUid),
          _demoMessage('m3', currentUid, 'ممتاز. هل الإيجار طويل وهل توجد مديونيات على النشاط؟', now, 80, currentUid),
          _demoMessage('m4', otherUid, 'العقد باقي عليه 18 شهر ولا توجد مديونيات تشغيلية.', now, 36, currentUid),
          _demoMessage('m5', otherUid, 'هل يشمل التقبيل المعدات والعمالة الحالية؟', now, 32, currentUid),
        ];
        break;
      case 'demo_message_funding_dammam':
        messages = <MessageModel>[
          _demoMessage('m1', otherUid, 'أهلاً، ذكرت أنك تبحث عن فرصة تشغيلية بمبلغ 180 ألف. هل تفضل قطاع غذائي أو خدمات؟', now, 280, currentUid),
          _demoMessage('m2', currentUid, 'أفضل الخدمات لأنها أوضح في التكاليف، لكن إذا الغذائي أرقامه قوية ممكن أدرسه.', now, 244, currentUid),
          _demoMessage('m3', otherUid, 'عندي فرصة توريد وتشغيل صغيرة تحتاج شريك ممول ومتابعة أسبوعية.', now, 170, currentUid),
          _demoMessage('m4', currentUid, 'الأهم عندي وضوح المصاريف قبل الدخول.', now, 118, currentUid),
        ];
        break;
      default:
        messages = <MessageModel>[
          _demoMessage('m1', otherUid, 'السلام عليكم، قرأت تجربتك في تشغيل متجر القهوة. أكثر نقطة شدتني موضوع الإيجار.', now, 430, currentUid),
          _demoMessage('m2', currentUid, 'وعليكم السلام، فعلًا الإيجار كان العامل الأكبر في الضغط على الربحية.', now, 390, currentUid),
          _demoMessage('m3', otherUid, 'هل تنصح بالبدء داخل مجمع أو شارع تجاري؟', now, 330, currentUid),
          _demoMessage('m4', currentUid, 'حسب المنتج. إذا العلامة جديدة أفضل موقع بتكلفة أخف وتجربة بيع واضحة قبل مجمع مكلف.', now, 260, currentUid),
        ];
        break;
    }

    _demoMessages[conversationId] = messages;
    return messages;
  }

  MessageModel _demoMessage(
    String id,
    String senderId,
    String text,
    DateTime now,
    int minutesAgo,
    String currentUid,
  ) {
    return MessageModel(
      id: id,
      senderId: senderId,
      text: text,
      type: 'text',
      status: 'sent',
      readBy: <String>[currentUid],
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
    );
  }

  void _addDemoMessage(String conversationId, String text) {
    final messages = _demoMessagesFor(conversationId, viewerUid);
    messages.add(
      MessageModel(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        senderId: viewerUid,
        text: text,
        type: 'text',
        status: 'sent',
        readBy: <String>[viewerUid],
        createdAt: DateTime.now(),
      ),
    );
    _demoMessageStreams[conversationId]?.add(
      List<MessageModel>.unmodifiable(messages),
    );
  }
}

class UploadedMessageImage {
  const UploadedMessageImage({required this.url, required this.path});

  final String url;
  final String path;
}
