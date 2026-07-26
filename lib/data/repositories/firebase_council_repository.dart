import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.mediumImageUrls,
  });

  final String id;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final List<String> mediumImageUrls;
}

class _CouncilImageUploadResult {
  const _CouncilImageUploadResult({
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.mediumImageUrls,
  });

  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final List<String> mediumImageUrls;
}

class FirebaseCouncilRepository {
  FirebaseCouncilRepository._();

  static final FirebaseCouncilRepository instance =
      FirebaseCouncilRepository._();
  static const publicDemoCouncilId = 'demo_laundry_public';

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

  Stream<List<CouncilModel>> watchClosedCouncils({int limit = 50}) {
    return watchCouncils(status: CouncilStatus.closed, limit: limit);
  }

  Stream<List<CouncilModel>> watchUserCouncils({
    required String uid,
    bool privateOnly = false,
    int limit = 80,
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

    if (pendingImageFiles.isNotEmpty) {
      try {
        final uploadResult = await _uploadCouncilImages(
          councilId: doc.id,
          ownerId: ownerId,
          imageFiles: pendingImageFiles,
        );
        if (uploadResult.imageUrls.isNotEmpty) {
          await doc.update({
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
        return CreatedCouncilResult(
          id: doc.id,
          imageUrls: uploadResult.imageUrls,
          thumbnailUrls: uploadResult.thumbnailUrls,
          mediumImageUrls: uploadResult.mediumImageUrls,
        );
      } catch (_) {
        await doc.delete();
        rethrow;
      }
    }

    return CreatedCouncilResult(
      id: doc.id,
      imageUrls: const <String>[],
      thumbnailUrls: const <String>[],
      mediumImageUrls: const <String>[],
    );
  }

  Future<_CouncilImageUploadResult> _uploadCouncilImages({
    required String councilId,
    required String ownerId,
    required List<XFile> imageFiles,
  }) async {
    if (imageFiles.isEmpty) {
      return const _CouncilImageUploadResult(
        imageUrls: <String>[],
        thumbnailUrls: <String>[],
        mediumImageUrls: <String>[],
      );
    }

    final urls = <String>[];
    final thumbnailUrls = <String>[];
    final mediumUrls = <String>[];
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
      final fileName =
          '${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
      final ref = _firestore.councilImageRef(councilId, ownerId, fileName);
      final thumbnailBytes = await _resizedPngBytes(bytes, maxLongSide: 360);
      final thumbnailRef = thumbnailBytes == null
          ? null
          : _firestore.councilImageRef(
              councilId,
              ownerId,
              'thumb_${DateTime.now().microsecondsSinceEpoch}_$index.png',
            );
      final originalUpload = ref
          .putData(
            bytes,
            SettableMetadata(
              contentType:
                  image.mimeType ?? _contentTypeForExtension(extension),
            ),
          )
          .then((_) => ref.getDownloadURL());
      final thumbnailUpload = thumbnailBytes != null && thumbnailRef != null
          ? thumbnailRef
              .putData(
                thumbnailBytes,
                SettableMetadata(contentType: 'image/png'),
              )
              .then((_) => thumbnailRef.getDownloadURL())
          : Future<String?>.value();
      final uploadedUrls = await Future.wait<String?>([
        originalUpload,
        thumbnailUpload,
      ]);
      final imageUrl = uploadedUrls[0]!;
      urls.add(imageUrl);
      mediumUrls.add(imageUrl);
      thumbnailUrls.add(uploadedUrls[1] ?? imageUrl);
    }

    return _CouncilImageUploadResult(
      imageUrls: urls,
      thumbnailUrls: thumbnailUrls,
      mediumImageUrls: mediumUrls,
    );
  }

  Future<Uint8List?> _resizedPngBytes(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    ui.Image? original;
    ui.Image? resized;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      original = frame.image;
      final sourceMaxSide = math.max(original.width, original.height);
      if (sourceMaxSide <= maxLongSide) return null;

      final scale = maxLongSide / sourceMaxSide;
      final targetWidth = math.max(1, (original.width * scale).round());
      final targetHeight = math.max(1, (original.height * scale).round());
      final resizedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await resizedCodec.getNextFrame();
      resized = resizedFrame.image;
      final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      original?.dispose();
      resized?.dispose();
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
