import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/moderation/content_moderation.dart';
import '../../core/utils/reusable_stream.dart';

import '../models/conversation_model.dart';
import '../models/council_model.dart';
import '../models/message_model.dart';
import '../models/public_profile_model.dart';
import '../services/firestore_service.dart';

String directConversationDocumentId(String firstUid, String secondUid) {
  final first = firstUid.trim();
  final second = secondUid.trim();
  if (first.isEmpty || second.isEmpty) {
    throw ArgumentError('Both participant UIDs are required.');
  }
  final ordered = <String>[first, second]..sort();
  return 'direct_${ordered[0]}_${ordered[1]}';
}

class MessagingRepository {
  MessagingRepository._();

  static final MessagingRepository instance = MessagingRepository._();

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get viewerUid {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return '';
    return user.uid;
  }

  String directConversationId(String firstUid, String secondUid) {
    return directConversationDocumentId(firstUid, secondUid);
  }

  ConversationModel buildDirectConversationDraft(
    PublicProfileTarget target,
  ) {
    final user = _requireSignedInUser(
      message: 'يجب تسجيل الدخول لبدء محادثة مباشرة.',
    );
    final targetUid = _directTargetUidOrThrow(target, user.uid);
    return ConversationModel(
      id: directConversationId(user.uid, targetUid),
      contextType: ConversationContextType.direct,
      targetId: targetUid,
      initiatorId: user.uid,
      participantIds: <String>[user.uid, targetUid],
      participantSnapshots: <String, ParticipantSnapshot>{
        user.uid: const ParticipantSnapshot(displayName: 'أنت'),
        targetUid: _publicTargetSnapshot(target),
      },
      unreadCounts: <String, int>{
        user.uid: 0,
        targetUid: 0,
      },
      status: 'active',
    );
  }

  Future<ConversationModel> getOrCreateDirectConversation(
    PublicProfileTarget target,
  ) async {
    final user = _requireSignedInUser(
      message: 'يجب تسجيل الدخول لبدء محادثة مباشرة.',
    );
    final targetUid = _directTargetUidOrThrow(target, user.uid);
    final conversationId = directConversationId(user.uid, targetUid);
    final ref = _firestore.conversation(conversationId);

    final existing = await _readConversationForCreate(ref);
    if (existing != null) {
      _ensureExpectedDirectParticipants(
        existing,
        currentUid: user.uid,
        targetUid: targetUid,
      );
      return existing;
    }

    final participantSnapshots = await Future.wait<ParticipantSnapshot>([
      _fetchPublicParticipantSnapshot(user.uid),
      _fetchPublicParticipantSnapshot(targetUid),
    ]);
    final initiatorSnapshot = participantSnapshots[0];
    final targetSnapshot = participantSnapshots[1];
    final participantIds = <String>[user.uid, targetUid];
    final data = <String, dynamic>{
      'contextType': conversationContextTypeToFirestore(
        ConversationContextType.direct,
      ),
      'initiatorId': user.uid,
      'targetId': targetUid,
      'participantIds': participantIds,
      'participantSnapshots': {
        user.uid: initiatorSnapshot.toMap(),
        targetUid: targetSnapshot.toMap(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageText': '',
      'lastMessageAt': null,
      'lastSenderId': null,
      'unreadCounts': {
        user.uid: 0,
        targetUid: 0,
      },
      'lastReadAt': <String, dynamic>{},
      'status': 'active',
      'blockedBy': <String>[],
      'archivedBy': <String>[],
      'deletedBy': <String>[],
      'reportCount': 0,
    };

    try {
      await ref.set(data);
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' && error.code != 'already-exists') {
        rethrow;
      }
      final raced = await _readConversationAfterCreateRace(ref);
      if (raced != null) {
        _ensureExpectedDirectParticipants(
          raced,
          currentUid: user.uid,
          targetUid: targetUid,
        );
        return raced;
      }
      rethrow;
    }

    final created = await ref.get();
    final conversation = ConversationModel.fromFirestore(created);
    _ensureExpectedDirectParticipants(
      conversation,
      currentUid: user.uid,
      targetUid: targetUid,
    );
    return conversation;
  }

  Future<ConversationModel> getOrCreateConversation(
      CouncilModel council) async {
    final user = _requireSignedInUser(
      message: 'يجب تسجيل الدخول للتواصل مع صاحب المنشور.',
    );

    if (council.isEditorialContent) {
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

    final existing = await _readConversationForCreate(ref);
    if (existing != null) return existing;

    final participantSnapshots = await Future.wait<ParticipantSnapshot>([
      _fetchPublicParticipantSnapshot(ownerId),
      _fetchPublicParticipantSnapshot(user.uid),
    ]);
    final ownerSnapshot = participantSnapshots[0];
    final requesterSnapshot = participantSnapshots[1];

    final data = {
      'contextType': conversationContextTypeToFirestore(
        ConversationContextType.opportunity,
      ),
      'targetId': ownerId,
      'initiatorId': user.uid,
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

    try {
      await ref.set(data);
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' && error.code != 'already-exists') {
        rethrow;
      }

      // A simultaneous tap/device may have created the same deterministic
      // conversation after the first read. In that case the set is evaluated
      // as a forbidden overwrite; read and reuse the winning document.
      final raced = await _readConversationAfterCreateRace(ref);
      if (raced != null) return raced;
      rethrow;
    }
    final created = await ref.get();
    return ConversationModel.fromFirestore(created);
  }

  Stream<ConversationModel?> watchConversation(String conversationId) {
    return _firestore.conversation(conversationId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return ConversationModel.fromFirestore(snapshot);
    });
  }

  Stream<List<ConversationModel>> watchMyConversations({
    bool includeArchived = false,
  }) {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return reusableValueStream<List<ConversationModel>>(
        const <ConversationModel>[],
      );
    }

    return _firestore.conversations
        .where('participantIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
      final conversations = snapshot.docs
          .map(ConversationModel.fromFirestore)
          .where(
            (conversation) =>
                conversation.status == 'active' &&
                conversation.isArchivedFor(user.uid) == includeArchived &&
                !conversation.isDeletedFor(user.uid) &&
                !_isDemoConversation(conversation),
          )
          .toList(growable: false);
      conversations.sort((a, b) {
        final aTime = a.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.sortAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return List<ConversationModel>.unmodifiable(conversations);
    });
  }

  Stream<int> watchUnreadTotal() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return reusableValueStream<int>(0);
    }
    return watchMyConversations()
        .map(
          (conversations) => conversations.fold<int>(
            0,
            (total, conversation) => total + conversation.unreadFor(user.uid),
          ),
        )
        .distinct();
  }

  Stream<List<MessageModel>> watchMessages(String conversationId) {
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

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(image.name)}';
    final ref =
        _firestore.conversationImageRef(conversationId, user.uid, fileName);
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
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'unreadCounts.${user.uid}': 0,
      'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveConversation(String conversationId) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'archivedBy': FieldValue.arrayUnion([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unarchiveConversation(String conversationId) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    await _firestore.conversation(conversationId).update({
      'archivedBy': FieldValue.arrayRemove([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteConversationForMe(String conversationId) async {
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
        throw FirebaseException(
            plugin: 'majlisna', code: 'missing-participant');
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

      final councilId = _stringValue(data['councilId']);
      final contextType = conversationContextTypeFromFirestore(
        data['contextType'],
        hasLegacyOpportunityContext: councilId.isNotEmpty ||
            data.containsKey('ownerId') ||
            data.containsKey('requesterId'),
      );
      final targetPreview = contextType == ConversationContextType.direct
          ? _directConversationPreview(data, user.uid)
          : _stringValue(
              data['councilTitle'],
              fallback: conversationId,
            );

      transaction.set(reportRef, {
        'targetType': 'conversation',
        'targetId': conversationId,
        'targetPreview': targetPreview,
        'conversationId': conversationId,
        if (councilId.isNotEmpty) 'councilId': councilId,
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

  User _requireSignedInUser({required String message}) {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: message,
      );
    }
    return user;
  }

  String _directTargetUidOrThrow(
      PublicProfileTarget target, String currentUid) {
    final targetUid = target.uid?.trim() ?? '';
    if (target.isDemo || targetUid.isEmpty) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'invalid-direct-target',
        message: 'لا يمكن بدء محادثة مع هذا الحساب.',
      );
    }
    if (targetUid == currentUid) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'self-message',
        message: 'لا يمكنك مراسلة نفسك.',
      );
    }
    return targetUid;
  }

  ParticipantSnapshot _publicTargetSnapshot(PublicProfileTarget target) {
    return ParticipantSnapshot(
      displayName: _stringValue(
        target.displayName,
        fallback: 'عضو Forsa Pro',
      ),
      username: _stringValue(target.username),
      avatarEmoji: _stringValue(target.avatarEmoji),
      photoUrl: _stringValue(target.publicPhotoUrl),
    );
  }

  Future<ParticipantSnapshot> _fetchPublicParticipantSnapshot(
    String uid,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final snapshot = await _firestore.publicProfile(uid).get();
      if (snapshot.exists) {
        final profile = PublicProfileModel.fromFirestore(snapshot);
        if (profile.isVisible && !profile.demo && profile.uid == uid) {
          return ParticipantSnapshot(
            displayName: profile.displayName,
            username: profile.username,
            avatarEmoji: profile.avatarEmoji,
            photoUrl: profile.publicPhotoUrl,
          );
        }
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'invalid-public-profile',
          message: 'هذا الملف غير متاح للمراسلة المباشرة.',
        );
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (attempt + 1)),
        );
      }
    }
    throw FirebaseException(
      plugin: 'majlisna',
      code: 'missing-public-profile',
      message: 'تعذر العثور على الملف العام لهذا العضو.',
    );
  }

  Future<ConversationModel?> _readConversationForCreate(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final existing = await ref.get();
      if (!existing.exists) return null;
      return ConversationModel.fromFirestore(existing);
    } on FirebaseException catch (error) {
      // Firestore evaluates a get on a missing document against resource.data.
      // The read can therefore be denied even when create is allowed.
      if (error.code != 'permission-denied') rethrow;
      return null;
    }
  }

  Future<ConversationModel?> _readConversationAfterCreateRace(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final raced = await ref.get();
      if (!raced.exists) return null;
      return ConversationModel.fromFirestore(raced);
    } catch (_) {
      // Preserve the original create failure when no readable winner exists.
      return null;
    }
  }

  void _ensureExpectedDirectParticipants(
    ConversationModel conversation, {
    required String currentUid,
    required String targetUid,
  }) {
    final participants = conversation.participantIds.toSet();
    if (!conversation.isDirect ||
        participants.length != 2 ||
        !participants.contains(currentUid) ||
        !participants.contains(targetUid)) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'conversation-id-conflict',
        message: 'تعذر التحقق من المحادثة المباشرة.',
      );
    }
  }

  String _directConversationPreview(
    Map<String, dynamic> data,
    String currentUid,
  ) {
    final participants = _stringList(data['participantIds']);
    final otherUid = participants.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );
    final snapshots = data['participantSnapshots'];
    if (otherUid.isNotEmpty && snapshots is Map) {
      final other = snapshots[otherUid];
      if (other is Map) {
        final name = _stringValue(other['displayName']);
        if (name.isNotEmpty) return 'محادثة مباشرة مع $name';
      }
    }
    return 'محادثة مباشرة';
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

  bool _isDemoConversation(ConversationModel conversation) {
    return conversation.id.startsWith('demo_') ||
        conversation.councilId?.startsWith('demo_') == true;
  }
}

class UploadedMessageImage {
  const UploadedMessageImage({required this.url, required this.path});

  final String url;
  final String path;
}
