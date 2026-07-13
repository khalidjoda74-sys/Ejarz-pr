import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/comment_model.dart';
import '../models/council_model.dart';
import '../models/council_result_model.dart';
import '../services/firestore_service.dart';

class VotedCouncilActivity {
  const VotedCouncilActivity({
    required this.council,
    required this.vote,
  });

  final CouncilModel council;
  final VoteOption vote;
}

class CommentedCouncilActivity {
  const CommentedCouncilActivity({
    required this.council,
    required this.comment,
  });

  final CouncilModel council;
  final CommentModel comment;
}

class FirebaseCouncilRepository {
  FirebaseCouncilRepository._();

  static final FirebaseCouncilRepository instance =
      FirebaseCouncilRepository._();

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<CouncilModel>> watchCouncils({
    CouncilStatus? status,
    String? category,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _firestore.councils.where(
      'visibility',
      isEqualTo: 'public',
    );

    if (status != null) {
      query = query.where(
        'status',
        isEqualTo: councilStatusToFirestore(status),
      );
    } else {
      query = query.where('status', isEqualTo: 'active');
    }

    if (category != null && category.isNotEmpty && category != 'الكل') {
      query = query.where('categoryId', isEqualTo: category);
    }

    return query
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final councils = snapshot.docs
              .map(CouncilModel.fromFirestore)
              .where(
                (council) => status == CouncilStatus.closed ||
                    council.status != CouncilStatus.closed,
              )
              .where((council) {
                final uid = _auth.currentUser?.uid;
                if (!council.id.startsWith('demo_laundry_')) return true;
                return uid != null && council.createdBy == uid;
              })
              .toList(growable: false);
          councils.sort((a, b) {
            final aDemo = a.id.startsWith('demo_laundry_');
            final bDemo = b.id.startsWith('demo_laundry_');
            if (aDemo != bDemo) return aDemo ? -1 : 1;
            final aCreatedAt = a.createdAt;
            final bCreatedAt = b.createdAt;
            if (aCreatedAt == null && bCreatedAt == null) return 0;
            if (aCreatedAt == null) return 1;
            if (bCreatedAt == null) return -1;
            return bCreatedAt.compareTo(aCreatedAt);
          });
          return councils;
        });
  }

  Stream<List<CouncilModel>> watchActiveCouncils({int limit = 50}) {
    return watchCouncils(status: CouncilStatus.active, limit: limit);
  }

  Stream<List<CouncilModel>> watchClosedCouncils({int limit = 50}) {
    return watchCouncils(status: CouncilStatus.closed, limit: limit);
  }

  Stream<List<CouncilModel>> watchUserCouncils({
    required String uid,
    bool privateOnly = false,
    int limit = 80,
  }) {
    return _firestore.councils
        .where('createdBy', isEqualTo: uid)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final councils = snapshot.docs
          .map(CouncilModel.fromFirestore)
          .where((council) => council.status != CouncilStatus.closed)
          .where((council) => !privateOnly || council.isPrivate)
          .toList(growable: false);
      councils.sort((a, b) {
        final aDemo = a.id.startsWith('demo_laundry_');
        final bDemo = b.id.startsWith('demo_laundry_');
        if (aDemo != bDemo) return aDemo ? -1 : 1;
        return a.status.index.compareTo(b.status.index);
      });
      return councils;
    });
  }

  Stream<List<CouncilModel>> watchVotedCouncils({
    required String uid,
    int limit = 80,
  }) {
    return watchVotedCouncilActivities(uid: uid, limit: limit).map(
      (activities) => activities
          .map((activity) => activity.council)
          .toList(growable: false),
    );
  }

  Stream<List<VotedCouncilActivity>> watchVotedCouncilActivities({
    required String uid,
    int limit = 80,
  }) {
    return _firestore.db
        .collectionGroup(FirestoreCollections.votes)
        .where('uid', isEqualTo: uid)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      final votes = <MapEntry<String, VoteOption>>[];
      for (final doc in snapshot.docs) {
        final councilId = doc.reference.parent.parent?.id;
        final vote = voteOptionFromFirestore(doc.data()['option']);
        if (councilId != null && councilId.isNotEmpty && vote != null) {
          votes.add(MapEntry(councilId, vote));
        }
      }

      final councils =
          await _fetchCouncilsByIds(votes.map((vote) => vote.key).toList());
      final councilsById = {
        for (final council in councils) council.id: council,
      };
      final activities = <VotedCouncilActivity>[];
      for (final vote in votes) {
        final council = councilsById[vote.key];
        if (council != null) {
          activities.add(
            VotedCouncilActivity(council: council, vote: vote.value),
          );
        }
      }
      return activities;
    });
  }

  Stream<List<CouncilModel>> watchCommentedCouncils({
    required String uid,
    int limit = 80,
  }) {
    return watchCommentedCouncilActivities(uid: uid, limit: limit).map(
      (activities) => activities
          .map((activity) => activity.council)
          .toList(growable: false),
    );
  }

  Stream<List<CommentedCouncilActivity>> watchCommentedCouncilActivities({
    required String uid,
    int limit = 80,
  }) {
    return _firestore.comments
        .where('authorId', isEqualTo: uid)
        .where('status', isEqualTo: 'visible')
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      final ids = <String>[];
      final commentsByCouncilId = <String, CommentModel>{};
      for (final doc in snapshot.docs) {
        final councilId = doc.data()['councilId']?.toString();
        if (councilId == null || councilId.isEmpty) continue;

        final comment = CommentModel.fromFirestore(doc);
        final currentComment = commentsByCouncilId[councilId];
        if (currentComment == null) {
          ids.add(councilId);
          commentsByCouncilId[councilId] = comment;
        } else if (comment.minutesAgo < currentComment.minutesAgo) {
          commentsByCouncilId[councilId] = comment;
        }
      }
      ids.sort(
        (a, b) => commentsByCouncilId[a]!.minutesAgo.compareTo(
          commentsByCouncilId[b]!.minutesAgo,
        ),
      );

      final councils = await _fetchCouncilsByIds(ids);
      final councilsById = {
        for (final council in councils) council.id: council,
      };
      final activities = <CommentedCouncilActivity>[];
      for (final councilId in ids) {
        final council = councilsById[councilId];
        final comment = commentsByCouncilId[councilId];
        if (council != null && comment != null) {
          activities.add(
            CommentedCouncilActivity(council: council, comment: comment),
          );
        }
      }
      return activities;
    });
  }

  Future<List<CouncilModel>> _fetchCouncilsByIds(List<String> ids) async {
    if (ids.isEmpty) return const <CouncilModel>[];

    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (seen.add(id)) uniqueIds.add(id);
    }

    final councils = <CouncilModel>[];
    for (final id in uniqueIds) {
      try {
        final snapshot = await _firestore.council(id).get();
        if (snapshot.exists) {
          councils.add(CouncilModel.fromFirestore(snapshot));
        }
      } catch (_) {
        // A hidden/deleted council should not break the whole activity screen.
      }
    }

    final byId = {for (final council in councils) council.id: council};
    return uniqueIds
        .map((id) => byId[id])
        .whereType<CouncilModel>()
        .toList(growable: false);
  }

  Stream<CouncilModel?> watchCouncil(String councilId) {
    return _firestore.council(councilId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return CouncilModel.fromFirestore(snapshot);
    });
  }

  Future<CouncilModel?> fetchCouncil(String councilId) async {
    final snapshot = await _firestore.council(councilId).get();
    if (!snapshot.exists) return null;
    return CouncilModel.fromFirestore(snapshot);
  }

  Future<void> ensureDemoOpportunityForUser({
    required String uid,
    required String ownerName,
    String? ownerPhotoUrl,
    String ownerAvatarEmoji = 'business:person_growth',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous || currentUser.uid != uid) {
      return;
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'ensureDemoOpportunity',
    );
    await callable.call<Object?>({
      'ownerName': ownerName.trim(),
      'ownerPhotoUrl': ownerPhotoUrl?.trim(),
      'ownerAvatarEmoji': ownerAvatarEmoji.trim(),
    });
  }
  Stream<List<CommentModel>> watchComments(
    String councilId, {
    int limit = 50,
  }) {
    return _firestore.comments
        .where('councilId', isEqualTo: councilId)
        .where('status', isEqualTo: 'visible')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final comments = snapshot.docs
              .map(CommentModel.fromFirestore)
              .toList(growable: false);
          comments.sort((a, b) => a.minutesAgo.compareTo(b.minutesAgo));
          return comments;
        });
  }

  Stream<bool> watchConvincingVote({
    required String commentId,
    required String uid,
  }) {
    return _firestore.comments
        .doc(commentId)
        .collection('convincingVotes')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Stream<List<CommentModel>> watchUserComments({
    required String uid,
    int limit = 80,
  }) {
    return _firestore.comments
        .where('authorId', isEqualTo: uid)
        .where('status', isEqualTo: 'visible')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final comments =
          snapshot.docs.map(CommentModel.fromFirestore).toList(growable: false);
      comments.sort((a, b) => a.minutesAgo.compareTo(b.minutesAgo));
      return comments;
    });
  }

  Stream<VoteOption?> watchUserVote({
    required String councilId,
    required String uid,
  }) {
    return _firestore
        .councilVotes(councilId)
        .doc(uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      return voteOptionFromFirestore(snapshot.data()?['option']);
    });
  }

  Future<String> createCouncil({
    required String title,
    required String description,
    required String category,
    required String city,
    required String ownerId,
    required String ownerName,
    String? ownerPhotoUrl,
    String? ownerAvatarEmoji,
    String? categoryId,
    List<XFile> imageFiles = const [],
    bool isPrivate = false,
    bool allowComments = true,
  }) async {
    final doc = _firestore.councils.doc();
    final shareCode = isPrivate ? _shareCode(doc.id) : null;
    final pendingImageFiles = imageFiles.take(10).toList(growable: false);

    await doc.set({
      'title': title.trim(),
      'description': description.trim(),
      'categoryId': categoryId ?? category,
      'categoryName': category,
      'city': city.trim(),
      'countryCode': 'SA',
      'countryName': 'المملكة العربية السعودية',
      'createdBy': ownerId,
      'createdByName': ownerName,
      'ownerId': ownerId,
      'ownerSnapshot': {
        'displayName': ownerName,
        'photoUrl': ownerPhotoUrl,
        'avatarEmoji': ownerAvatarEmoji,
      },
      'visibility': isPrivate ? 'linkOnly' : 'public',
      'shareCode': shareCode,
      'status': 'active',
      'type': isPrivate ? 'private' : 'public',
      'allowComments': allowComments,
      'allowReplies': true,
      'isCouncilOfDay': false,
      'isPinned': false,
      'pinnedUntil': null,
      'sponsorId': null,
      'bestCommentId': null,
      'coverImageUrl': null,
      'imageUrls': const <String>[],
      'imagesCount': 0,
      'options': const ['support', 'against', 'neutral'],
      'voteOptions': const [
        {'id': 'support', 'label': 'إيجابي', 'color': '#0F4A35'},
        {'id': 'against', 'label': 'تحفظ', 'color': '#D94F4F'},
        {'id': 'neutral', 'label': 'تحتاج تفاصيل', 'color': '#D9A441'},
      ],
      'voteCounts': const {
        'support': 0,
        'against': 0,
        'neutral': 0,
      },
      'percentages': const {
        'support': 0,
        'against': 0,
        'neutral': 0,
      },
      'participantsCount': 0,
      'commentsCount': 0,
      'votesCount': 0,
      'viewsCount': 0,
      'sharesCount': 0,
      'reportsCount': 0,
      'closesAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      ),
      'createdAt': FieldValue.serverTimestamp(),
      'visibilityUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (pendingImageFiles.isNotEmpty) {
      try {
        final imageUrls = await _uploadCouncilImages(
          councilId: doc.id,
          ownerId: ownerId,
          imageFiles: pendingImageFiles,
        );
        if (imageUrls.isNotEmpty) {
          await doc.update({
            'coverImageUrl': imageUrls.first,
            'imageUrls': imageUrls,
            'imagesCount': imageUrls.length,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        await doc.delete();
        rethrow;
      }
    }

    return doc.id;
  }

  Future<List<String>> _uploadCouncilImages({
    required String councilId,
    required String ownerId,
    required List<XFile> imageFiles,
  }) async {
    if (imageFiles.isEmpty) return const [];

    final urls = <String>[];
    final limitedFiles = imageFiles.take(10).toList(growable: false);
    for (var index = 0; index < limitedFiles.length; index++) {
      final image = limitedFiles[index];
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) continue;
      if (bytes.length > 5 * 1024 * 1024) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'image-too-large',
          message: 'حجم الصورة أكبر من الحد المسموح.',
        );
      }

      final extension = _imageExtension(image.name, image.mimeType);
      final fileName = '${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
      final ref = _firestore.councilImageRef(councilId, ownerId, fileName);
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: image.mimeType ?? _contentTypeForExtension(extension),
        ),
      );
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  String _imageExtension(String name, String? mimeType) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.png')) return 'png';
    if (lowerName.endsWith('.webp')) return 'webp';
    if (lowerName.endsWith('.heic')) return 'heic';
    if (mimeType == 'image/png') return 'png';
    if (mimeType == 'image/webp') return 'webp';
    if (mimeType == 'image/heic') return 'heic';
    return 'jpg';
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
  Future<void> refreshCouncilVisibility({required String councilId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لتحديث ظهور الفرصة.',
      );
    }

    final ref = _firestore.council(councilId);
    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'not-found',
          message: 'الفرصة غير موجودة.',
        );
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final ownerId = (data['createdBy'] ?? data['ownerId'])?.toString();
      if (ownerId != user.uid) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'permission-denied',
          message: 'تحديث الظهور متاح لصاحب الفرصة فقط.',
        );
      }

      final lastRefresh = _dateValue(
        data['lastVisibilityRefreshAt'] ?? data['visibilityUpdatedAt'],
      );
      if (lastRefresh != null &&
          DateTime.now().difference(lastRefresh) < const Duration(hours: 24)) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'too-soon',
          message: 'يمكن تحديث ظهور الفرصة مرة واحدة كل 24 ساعة.',
        );
      }

      transaction.update(ref, {
        'createdAt': FieldValue.serverTimestamp(),
        'visibilityUpdatedAt': FieldValue.serverTimestamp(),
        'lastVisibilityRefreshAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deleteCouncil({required String councilId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لحذف الفرصة.',
      );
    }

    final ref = _firestore.council(councilId);
    await _firestore.db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? const <String, dynamic>{};
      final ownerId = (data['createdBy'] ?? data['ownerId'])?.toString();
      if (ownerId != user.uid) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'permission-denied',
          message: 'حذف الفرصة متاح لصاحبها فقط.',
        );
      }

      transaction.update(ref, {
        'status': 'deleted',
        'visibility': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DateTime? _dateValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<void> castVote({
    required String councilId,
    required VoteOption option,
  }) async {
    final callable = _functions.httpsCallable('castVote');
    await callable.call<Object?>({
      'councilId': councilId,
      'option': voteOptionToFirestore(option),
    });
  }

  Future<String?> addComment({
    required String councilId,
    required String text,
    String? parentId,
  }) async {
    final callable = _functions.httpsCallable(
      'addComment',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'councilId': councilId,
      'text': text.trim(),
      'parentId': parentId,
    });
    return result.data['commentId']?.toString();
  }

  Future<void> toggleConvincingVote({
    required String councilId,
    required String commentId,
  }) async {
    final callable = _functions.httpsCallable('toggleConvincingVote');
    await callable.call<Object?>({
      'councilId': councilId,
      'commentId': commentId,
    });
  }

  Future<String?> createReport({
    required String targetType,
    required String targetPath,
    required String reason,
    String? councilId,
    String? commentId,
    String? details,
  }) async {
    final callable = _functions.httpsCallable('createReport');
    final result = await callable.call<Map<String, dynamic>>({
      'targetType': targetType,
      'targetPath': targetPath,
      'councilId': councilId,
      'commentId': commentId,
      'reason': reason,
      'details': details,
    });

    return result.data['reportId']?.toString();
  }

  Stream<List<CouncilResultModel>> watchCouncilResults({int limit = 50}) {
    return _firestore.councilResults
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(CouncilResultModel.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<CouncilResultModel?> watchCouncilResult(String councilId) {
    return _firestore.councilResult(councilId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return CouncilResultModel.fromFirestore(snapshot);
    });
  }

  String _shareCode(String councilId) {
    final source = councilId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (source.length <= 8) return source.toUpperCase();
    return source.substring(0, 8).toUpperCase();
  }
}
