import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/utils/reusable_stream.dart';
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

class CouncilPage {
  const CouncilPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<CouncilModel> items;
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;
  final bool hasMore;
}

class CouncilListSnapshot {
  const CouncilListSnapshot({
    required this.councils,
    required this.isFromCache,
    required this.dataChanged,
  });

  final List<CouncilModel> councils;
  final bool isFromCache;
  final bool dataChanged;
}

class CreatedCouncilResult {
  const CreatedCouncilResult({
    required this.id,
    this.pendingImageUpload,
  });

  final String id;
  final Future<CouncilImageUploadResult>? pendingImageUpload;
}

class CouncilImageUploadInput {
  const CouncilImageUploadInput({
    required this.bytes,
    required this.name,
    this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String? mimeType;
}

class CouncilImageUploadResult {
  const CouncilImageUploadResult({
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.mediumImageUrls,
  });

  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final List<String> mediumImageUrls;
}

class _UploadedCouncilImage {
  const _UploadedCouncilImage({
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  final String imageUrl;
  final String thumbnailUrl;
}

class FirebaseCouncilRepository {
  FirebaseCouncilRepository._();

  static final FirebaseCouncilRepository instance =
      FirebaseCouncilRepository._();
  static const publicDemoCouncilId = 'demo_laundry_public';
  static const int _maxCouncilImageBytes = 5 * 1024 * 1024;
  static const int _imageUploadAttempts = 2;
  static const Duration _imageUploadTimeout = Duration(seconds: 90);
  static const Duration _downloadUrlTimeout = Duration(seconds: 20);

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<CouncilModel>> watchCouncils({
    CouncilStatus? status,
    String? category,
    int limit = 50,
  }) {
    return watchCouncilSnapshots(
      status: status,
      category: category,
      limit: limit,
    ).map((snapshot) => snapshot.councils);
  }

  Stream<CouncilListSnapshot> watchCouncilSnapshots({
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

    var initialized = false;
    var cachedDataFingerprint = 0;
    var cachedCouncils = const <CouncilModel>[];
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final dataFingerprint = Object.hashAll(
        snapshot.docs.map(
          (document) => Object.hash(
            document.id,
            _deepFirestoreValueHash(document.data()),
          ),
        ),
      );
      final dataChanged =
          !initialized || dataFingerprint != cachedDataFingerprint;
      if (dataChanged) {
        final councils = snapshot.docs
            .map(CouncilModel.fromFirestore)
            .where(
              (council) =>
                  status == CouncilStatus.closed ||
                  council.status != CouncilStatus.closed,
            )
            .where(_isVisiblePublicCouncil)
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
        cachedCouncils = councils;
        cachedDataFingerprint = dataFingerprint;
        initialized = true;
      }
      return CouncilListSnapshot(
        councils: cachedCouncils,
        isFromCache: snapshot.metadata.isFromCache,
        dataChanged: dataChanged,
      );
    });
  }

  int _deepFirestoreValueHash(Object? value) {
    if (value is Map) {
      final keys = value.keys.toList()
        ..sort((left, right) => '$left'.compareTo('$right'));
      return Object.hashAll(
        keys.map(
          (key) => Object.hash(
            key,
            _deepFirestoreValueHash(value[key]),
          ),
        ),
      );
    }
    if (value is Iterable) {
      return Object.hashAll(value.map(_deepFirestoreValueHash));
    }
    return value.hashCode;
  }

  bool _isVisiblePublicCouncil(CouncilModel council) {
    final id = council.id;
    return !id.startsWith('demo_laundry_') || id == publicDemoCouncilId;
  }

  Future<CouncilPage> fetchCouncilsPage({
    CouncilStatus? status,
    String? category,
    int pageSize = 30,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final safePageSize = pageSize.clamp(1, 50);
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

    query = query.orderBy('createdAt', descending: true);
    if (cursor != null) query = query.startAfterDocument(cursor);

    final snapshot = await query.limit(safePageSize + 1).get();
    final visibleDocs =
        snapshot.docs.take(safePageSize).toList(growable: false);
    return CouncilPage(
      items: visibleDocs
          .map(CouncilModel.fromFirestore)
          .where(_isVisiblePublicCouncil)
          .toList(growable: false),
      nextCursor: visibleDocs.isEmpty ? cursor : visibleDocs.last,
      hasMore: snapshot.docs.length > safePageSize,
    );
  }

  Stream<List<CouncilModel>> watchActiveCouncils({int limit = 50}) {
    return watchCouncils(status: CouncilStatus.active, limit: limit);
  }

  Stream<List<CouncilModel>> watchPublicActiveCouncilsByOwner({
    required String uid,
    int limit = 40,
  }) {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) {
      return reusableValueStream<List<CouncilModel>>(
        const <CouncilModel>[],
      );
    }
    final safeLimit = limit < 1 ? 1 : (limit > 80 ? 80 : limit);

    return _firestore.councils
        .where('createdBy', isEqualTo: safeUid)
        .where('visibility', isEqualTo: 'public')
        .where(
          'status',
          whereIn: const <String>['active', 'endingSoon'],
        )
        .orderBy('createdAt', descending: true)
        .limit(safeLimit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(CouncilModel.fromFirestore)
              .where(
                (council) =>
                    !council.isSeedContent && !council.id.startsWith('demo_'),
              )
              .toList(growable: false),
        );
  }

  Stream<List<CouncilModel>> watchClosedCouncils({int limit = 50}) {
    return watchCouncils(status: CouncilStatus.closed, limit: limit);
  }

  Stream<List<CouncilModel>> watchUserCouncils({
    required String uid,
    bool privateOnly = false,
    int limit = 80,
  }) {
    return reusableStream<List<CouncilModel>>(
      () => _watchUserCouncils(
        uid: uid,
        privateOnly: privateOnly,
        limit: limit,
      ),
    );
  }

  Stream<List<CouncilModel>> _watchUserCouncils({
    required String uid,
    required bool privateOnly,
    required int limit,
  }) async* {
    final safeLimit = limit < 1 ? 1 : limit;
    final indexedQuery = _firestore.councils
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(safeLimit);

    try {
      await for (final snapshot in indexedQuery.snapshots()) {
        yield _userCouncilsFromSnapshot(
          snapshot,
          privateOnly: privateOnly,
          limit: safeLimit,
        );
      }
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;

      // Keep "My opportunities" functional while a newly deployed composite
      // index is still building. This fallback uses the automatic createdBy
      // index, then applies stable ordering and the limit on the client.
      await for (final snapshot in _firestore.councils
          .where('createdBy', isEqualTo: uid)
          .snapshots()) {
        yield _userCouncilsFromSnapshot(
          snapshot,
          privateOnly: privateOnly,
          limit: safeLimit,
        );
      }
    }
  }

  List<CouncilModel> _userCouncilsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required bool privateOnly,
    required int limit,
  }) {
    final councils = snapshot.docs
        .map(CouncilModel.fromFirestore)
        .where((council) => council.status != CouncilStatus.closed)
        .where(_isVisiblePublicCouncil)
        .where(
          (council) =>
              !council.isSeedContent && !council.id.startsWith('demo_'),
        )
        .where((council) => !privateOnly || council.isPrivate)
        .toList(growable: false);
    councils.sort((a, b) {
      final aCreatedAt = a.createdAt;
      final bCreatedAt = b.createdAt;
      if (aCreatedAt != null && bCreatedAt != null) {
        return bCreatedAt.compareTo(aCreatedAt);
      }
      if (aCreatedAt != null) return -1;
      if (bCreatedAt != null) return 1;
      return b.id.compareTo(a.id);
    });
    return councils.take(limit).toList(growable: false);
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

    final chunks = <List<String>>[
      for (var index = 0; index < uniqueIds.length; index += 10)
        uniqueIds.skip(index).take(10).toList(growable: false),
    ];
    final chunkResults = await Future.wait(
      chunks.map((chunk) async {
        try {
          final snapshot = await _firestore.councils
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          return snapshot.docs
              .map(CouncilModel.fromFirestore)
              .toList(growable: false);
        } catch (_) {
          // A hidden/deleted council should not break the activity screen.
          return const <CouncilModel>[];
        }
      }),
    );
    final councils = chunkResults.expand((chunk) => chunk).toList();

    final byId = {for (final council in councils) council.id: council};
    return uniqueIds
        .map((id) => byId[id])
        .whereType<CouncilModel>()
        .where(_isVisiblePublicCouncil)
        .toList(growable: false);
  }

  Stream<CouncilModel?> watchCouncil(String councilId) {
    return _firestore.council(councilId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final council = CouncilModel.fromFirestore(snapshot);
      return _isVisiblePublicCouncil(council) ? council : null;
    });
  }

  Future<CouncilModel?> fetchCouncil(String councilId) async {
    final snapshot = await _firestore.council(councilId).get();
    if (!snapshot.exists) return null;
    final council = CouncilModel.fromFirestore(snapshot);
    return _isVisiblePublicCouncil(council) ? council : null;
  }

  Future<void> ensureDemoOpportunity() async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'ensureDemoOpportunity',
    );
    await callable.call<Object?>();
  }

  Stream<List<CommentModel>> watchComments(String councilId) {
    return _firestore.comments
        .where('councilId', isEqualTo: councilId)
        .where('status', isEqualTo: 'visible')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(CommentModel.fromFirestore)
              .toList(growable: false),
        );
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
        .orderBy('createdAt', descending: true)
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

  Future<CreatedCouncilResult> createCouncil({
    required String title,
    required String description,
    required String category,
    required String city,
    required String ownerId,
    required String ownerName,
    String? ownerPhotoUrl,
    String? ownerAvatarEmoji,
    String? categoryId,
    List<CouncilImageUploadInput> images = const [],
    bool isPrivate = false,
    bool allowComments = true,
  }) async {
    final doc = _firestore.councils.doc();
    final shareCode = isPrivate ? _shareCode(doc.id) : null;
    final pendingImages = images.take(10).toList(growable: false);
    for (final image in pendingImages) {
      if (image.bytes.isEmpty) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'invalid-image',
          message: 'تعذر قراءة إحدى الصور المختارة.',
        );
      }
      if (image.bytes.length > _maxCouncilImageBytes) {
        throw FirebaseException(
          plugin: 'majlisna',
          code: 'image-too-large',
          message: 'حجم إحدى الصور أكبر من الحد المسموح.',
        );
      }
    }

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
      'coverThumbnailUrl': null,
      'coverMediumUrl': null,
      'imageUrls': const <String>[],
      'thumbnailUrls': const <String>[],
      'mediumImageUrls': const <String>[],
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

    final pendingImageUpload = pendingImages.isEmpty
        ? null
        : Future<CouncilImageUploadResult>.delayed(
            Duration.zero,
            () => _uploadAndAttachCouncilImagesWithRetry(
              document: doc,
              councilId: doc.id,
              ownerId: ownerId,
              images: pendingImages,
            ),
          );

    return CreatedCouncilResult(
      id: doc.id,
      pendingImageUpload: pendingImageUpload,
    );
  }

  Future<CouncilImageUploadResult> _uploadAndAttachCouncilImagesWithRetry({
    required DocumentReference<Map<String, dynamic>> document,
    required String councilId,
    required String ownerId,
    required List<CouncilImageUploadInput> images,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < _imageUploadAttempts; attempt++) {
      try {
        return await _uploadAndAttachCouncilImages(
          document: document,
          councilId: councilId,
          ownerId: ownerId,
          images: images,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt + 1 < _imageUploadAttempts) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<CouncilImageUploadResult> _uploadAndAttachCouncilImages({
    required DocumentReference<Map<String, dynamic>> document,
    required String councilId,
    required String ownerId,
    required List<CouncilImageUploadInput> images,
  }) async {
    final cleanupRefs = <Reference>[];
    try {
      final uploadResult = await _uploadCouncilImages(
        councilId: councilId,
        ownerId: ownerId,
        images: images,
        cleanupRefs: cleanupRefs,
      );
      if (uploadResult.imageUrls.isNotEmpty) {
        await document.update({
          'coverImageUrl': uploadResult.imageUrls.first,
          'coverThumbnailUrl': uploadResult.thumbnailUrls.first,
          'coverMediumUrl': uploadResult.mediumImageUrls.first,
          'imageUrls': uploadResult.imageUrls,
          'thumbnailUrls': uploadResult.thumbnailUrls,
          'mediumImageUrls': uploadResult.mediumImageUrls,
          'imagesCount': uploadResult.imageUrls.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return uploadResult;
    } catch (_) {
      // The opportunity is already valid and published. Keep it as a text-only
      // opportunity and remove any unattached files left by a partial upload.
      await Future.wait(
        cleanupRefs.map(_deleteStorageObjectSilently),
      );
      rethrow;
    }
  }

  Future<void> _deleteStorageObjectSilently(Reference reference) async {
    try {
      await reference.delete();
    } catch (_) {
      // A missing file or a transient cleanup failure must not hide the
      // original upload error or delete the published opportunity.
    }
  }

  Future<CouncilImageUploadResult> _uploadCouncilImages({
    required String councilId,
    required String ownerId,
    required List<CouncilImageUploadInput> images,
    required List<Reference> cleanupRefs,
  }) async {
    if (images.isEmpty) {
      return const CouncilImageUploadResult(
        imageUrls: <String>[],
        thumbnailUrls: <String>[],
        mediumImageUrls: <String>[],
      );
    }

    final limitedImages = images.take(10).toList(growable: false);
    final uploadedImages = await _mapWithConcurrency<CouncilImageUploadInput,
        _UploadedCouncilImage?>(
      limitedImages,
      concurrency: 2,
      operation: (image, index) => _uploadCouncilImage(
        councilId: councilId,
        ownerId: ownerId,
        image: image,
        index: index,
        cleanupRefs: cleanupRefs,
      ),
    );
    final completed =
        uploadedImages.whereType<_UploadedCouncilImage>().toList();
    return CouncilImageUploadResult(
      imageUrls: completed.map((image) => image.imageUrl).toList(),
      thumbnailUrls: completed.map((image) => image.thumbnailUrl).toList(),
      mediumImageUrls: completed.map((image) => image.imageUrl).toList(),
    );
  }

  Future<_UploadedCouncilImage?> _uploadCouncilImage({
    required String councilId,
    required String ownerId,
    required CouncilImageUploadInput image,
    required int index,
    required List<Reference> cleanupRefs,
  }) async {
    final bytes = image.bytes;
    if (bytes.isEmpty) return null;
    if (bytes.length > _maxCouncilImageBytes) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'image-too-large',
        message: 'حجم الصورة أكبر من الحد المسموح.',
      );
    }

    final extension = _imageExtension(image.name, image.mimeType);
    final uploadId = '${DateTime.now().microsecondsSinceEpoch}_$index';
    final ref = _firestore.councilImageRef(
      councilId,
      ownerId,
      '$uploadId.$extension',
    );
    final thumbnailBytes = await _resizedPngBytes(bytes, maxLongSide: 360);
    final thumbnailRef = thumbnailBytes == null
        ? null
        : _firestore.councilImageRef(
            councilId,
            ownerId,
            'thumb_$uploadId.png',
          );
    cleanupRefs.add(ref);
    if (thumbnailRef != null) cleanupRefs.add(thumbnailRef);

    final originalUpload = _uploadBytes(
      reference: ref,
      bytes: bytes,
      metadata: SettableMetadata(
        contentType: image.mimeType ?? _contentTypeForExtension(extension),
      ),
    );
    final thumbnailUpload = thumbnailBytes != null && thumbnailRef != null
        ? _uploadBytes(
            reference: thumbnailRef,
            bytes: thumbnailBytes,
            metadata: SettableMetadata(contentType: 'image/png'),
          )
        : Future<String?>.value();
    final uploadedUrls = await Future.wait<String?>([
      originalUpload,
      thumbnailUpload,
    ]);
    final imageUrl = uploadedUrls[0]!;
    return _UploadedCouncilImage(
      imageUrl: imageUrl,
      thumbnailUrl: uploadedUrls[1] ?? imageUrl,
    );
  }

  Future<String> _uploadBytes({
    required Reference reference,
    required Uint8List bytes,
    required SettableMetadata metadata,
  }) async {
    final task = reference.putData(bytes, metadata);
    try {
      await task.timeout(_imageUploadTimeout);
    } on TimeoutException {
      try {
        await task.cancel();
      } catch (_) {}
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'image-upload-timeout',
        message: 'استغرق رفع الصور وقتًا أطول من المتوقع.',
      );
    }
    return reference.getDownloadURL().timeout(_downloadUrlTimeout);
  }

  Future<List<R>> _mapWithConcurrency<T, R>(
    List<T> values, {
    required int concurrency,
    required Future<R> Function(T value, int index) operation,
  }) async {
    if (values.isEmpty) return <R>[];

    final results = List<R?>.filled(values.length, null);
    var nextIndex = 0;
    var failed = false;

    Future<void> worker() async {
      while (!failed && nextIndex < values.length) {
        final index = nextIndex++;
        try {
          results[index] = await operation(values[index], index);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }

    final workerCount = math.min(math.max(1, concurrency), values.length);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return results.cast<R>();
  }

  Future<Uint8List?> _resizedPngBytes(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? resized;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceMaxSide = math.max(descriptor.width, descriptor.height);
      if (sourceMaxSide <= maxLongSide) return null;

      final scale = maxLongSide / sourceMaxSide;
      final targetWidth = math.max(1, (descriptor.width * scale).round());
      final targetHeight = math.max(1, (descriptor.height * scale).round());
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await codec.getNextFrame();
      resized = resizedFrame.image;
      final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      resized?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
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
