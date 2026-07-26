import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/moderation/content_moderation.dart';
import '../../core/utils/reference_counted_watch_registry.dart';

import '../mock/mock_data.dart';
import '../models/comment_model.dart';
import '../models/council_model.dart';
import '../models/council_result_model.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import 'firebase_council_repository.dart';
import 'firebase_user_repository.dart';

@immutable
class CouncilFeedState {
  const CouncilFeedState({
    required this.councils,
    required this.categories,
    required this.hasConnectionIssue,
    required this.lastRemoteSyncAt,
  });

  final List<CouncilModel> councils;
  final List<String> categories;
  final bool hasConnectionIssue;
  final DateTime? lastRemoteSyncAt;
}

@immutable
class CouncilUserState {
  const CouncilUserState(this.user);

  final UserModel user;
}

class CouncilRepository extends ChangeNotifier {
  CouncilRepository._();

  static final CouncilRepository instance = CouncilRepository._()
    .._user = MockData.currentUser
    .._mockCouncils = MockData.councils()
    .._councils = MockData.councils()
    .._notifications = MockData.notifications
    .._initializeStateNotifiers()
    .._startFirestoreSync()
    .._startUserSync();

  late UserModel _user;
  late List<CouncilModel> _mockCouncils;
  late List<CouncilModel> _councils;
  List<CouncilResultModel> _results = [];
  late List<NotificationModel> _notifications;
  StreamSubscription<CouncilListSnapshot>? _councilsSubscription;
  StreamSubscription<List<CouncilResultModel>>? _resultsSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _userSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _blockedUsersSubscription;
  final Set<String> _blockedUserIds = <String>{};
  final Map<String, StreamSubscription<List<CommentModel>>>
      _commentSubscriptions = {};
  final ReferenceCountedWatchRegistry<String> _commentWatchRegistry =
      ReferenceCountedWatchRegistry<String>();
  final Set<String> _convincingVotes = {};
  bool _demoOpportunityRequested = false;
  final Map<String, List<CommentModel>> _remoteCommentsByCouncilId = {};
  final List<String> _recentCommentCacheCouncilIds = <String>[];
  final Map<String, List<CommentModel>> _localCommentOverlays = {};
  final Map<String, List<CommentModel>> _privateDemoComments = {};
  final Map<String, CouncilModel> _standaloneCouncilsById = {};
  final Map<String, Future<void>> _standaloneCouncilLoads = {};
  Object? _firestoreError;
  Timer? _councilSyncWatchdog;
  bool _receivedServerCouncilSnapshot = false;
  bool _remoteSyncDelayed = false;
  DateTime? _lastRemoteSyncAt;
  bool _usingFirestore = false;
  final Map<String, VoteOption> _selectedVotes = {};
  late final ValueNotifier<CouncilFeedState> _feedStateNotifier;
  late final ValueNotifier<CouncilUserState> _userStateNotifier;
  late final ValueNotifier<List<CouncilResultModel>> _resultsStateNotifier;

  ValueListenable<CouncilFeedState> get feedState => _feedStateNotifier;
  ValueListenable<CouncilUserState> get userState => _userStateNotifier;
  ValueListenable<List<CouncilResultModel>> get resultsState =>
      _resultsStateNotifier;

  int get debugActiveCommentSubscriptionCount => _commentSubscriptions.length;
  int get debugActiveCommentWatchCount =>
      _commentWatchRegistry.activeReferenceCount;
  int get debugCachedCommentCouncilCount => _remoteCommentsByCouncilId.length;

  void _initializeStateNotifiers() {
    _feedStateNotifier = ValueNotifier<CouncilFeedState>(_createFeedState());
    _userStateNotifier =
        ValueNotifier<CouncilUserState>(CouncilUserState(_user));
    _resultsStateNotifier =
        ValueNotifier<List<CouncilResultModel>>(const <CouncilResultModel>[]);
  }

  CouncilFeedState _createFeedState() {
    return CouncilFeedState(
      councils: councils,
      categories: categories,
      hasConnectionIssue: hasConnectionIssue,
      lastRemoteSyncAt: lastRemoteSyncAt,
    );
  }

  void _emitFeedChange() {
    _feedStateNotifier.value = _createFeedState();
    notifyListeners();
  }

  void _emitUserChange() {
    _userStateNotifier.value = CouncilUserState(_user);
    notifyListeners();
  }

  void _emitFeedAndUserChange() {
    _feedStateNotifier.value = _createFeedState();
    _userStateNotifier.value = CouncilUserState(_user);
    notifyListeners();
  }

  UserModel get user => _user;
  List<CouncilModel> get councils => List.unmodifiable(
        _councils.where((council) => !_isBlockedCouncil(council)),
      );
  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications);
  CouncilModel get todayCouncil {
    final active = activeCouncils;
    for (final council in active) {
      if (council.isCouncilOfDay) return council;
    }
    return active.isNotEmpty
        ? active.first
        : (councils.isNotEmpty ? councils.first : _mockCouncils.first);
  }

  bool get usingFirestore => _usingFirestore;
  Object? get firestoreError => _firestoreError;
  bool get hasConnectionIssue => _firestoreError != null || _remoteSyncDelayed;
  DateTime? get lastRemoteSyncAt => _lastRemoteSyncAt;

  bool hasConvincingVote(String councilId, String commentId) {
    return _convincingVotes.contains('$councilId/$commentId');
  }

  List<String> get categories {
    final values = <String>{};
    for (final category in MockData.categories) {
      final mapped = _canonicalCategory(category);
      if (mapped.trim().isNotEmpty) values.add(mapped);
    }
    for (final council in _councils) {
      final mapped = _canonicalCategory(council.category);
      if (mapped.trim().isNotEmpty) values.add(mapped);
    }

    values.remove('الكل');
    const order = [
      'فرص للتقبيل',
      'فرص مطلوبة',
      'فرص شراكة',
      'تجارب السوق',
    ];
    return [
      'الكل',
      for (final category in order)
        if (values.contains(category)) category,
    ];
  }

  List<CouncilModel> councilsByCategory(String category) {
    if (category == 'الكل') return councils;
    return councils
        .where((c) => _canonicalCategory(c.category) == category)
        .toList();
  }

  List<CouncilModel> get activeCouncils {
    final active =
        councils.where((c) => c.status != CouncilStatus.closed).toList();
    active.sort((a, b) {
      if (a.isCouncilOfDay != b.isCouncilOfDay) {
        return a.isCouncilOfDay ? -1 : 1;
      }
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return 0;
    });
    return active;
  }

  List<CouncilModel> get closedCouncils {
    if (_results.isNotEmpty) {
      return _results.map((result) => result.toCouncilModel()).toList();
    }

    return _councils.where((c) => c.status == CouncilStatus.closed).toList();
  }

  CouncilResultModel? resultById(String councilId) {
    for (final result in _results) {
      if (result.councilId == councilId) return result;
    }

    return null;
  }

  CouncilModel? findCouncilById(String id) {
    final council = _findCouncilById(id);
    return council == null || _isBlockedCouncil(council) ? null : council;
  }

  CouncilModel councilById(String id) {
    final council = _findCouncilById(id);
    if (council == null) {
      throw StateError('Opportunity not found: $id');
    }
    return council;
  }

  CouncilDetailsSession openDetailsSession(String councilId) {
    return CouncilDetailsSession._(this, councilId);
  }

  Future<void> _loadCouncilIfMissing(String councilId) {
    if (_findCouncilById(councilId) != null || councilId.startsWith('demo_')) {
      return Future<void>.value();
    }
    return _standaloneCouncilLoads.putIfAbsent(
      councilId,
      () => _fetchStandaloneCouncil(councilId),
    );
  }

  Future<void> _fetchStandaloneCouncil(String councilId) async {
    try {
      final council =
          await FirebaseCouncilRepository.instance.fetchCouncil(councilId);
      if (council == null) return;
      _applyCachedComments(council);
      _standaloneCouncilsById[councilId] = council;
      while (_standaloneCouncilsById.length > 4) {
        _standaloneCouncilsById.remove(_standaloneCouncilsById.keys.first);
      }
      _emitFeedChange();
    } catch (_) {
      // The details screen keeps its local fallback if this one-shot fetch
      // cannot reach Firestore.
    } finally {
      _standaloneCouncilLoads.remove(councilId);
    }
  }

  Future<void> vote(String councilId, VoteOption option) async {
    final existingCouncil = _findCouncilById(councilId);
    if (existingCouncil != null && isCouncilOwner(existingCouncil)) {
      throw StateError('Opportunity owners cannot vote on their own posts.');
    }

    final council = councilById(councilId);
    if (_isDemoCouncil(council)) {
      throw StateError('Demo opportunities are read-only.');
    }

    final previousParticipants = council.participants;
    final previousHasVoted = council.hasVoted;
    final previousSelectedOption = council.selectedOption;
    final previousVotesCount = council.votesCount;
    final previousSupportPercent = council.supportPercent;
    final previousAgainstPercent = council.againstPercent;
    final previousNeutralPercent = council.neutralPercent;
    final previousSessionVote = _selectedVotes[councilId];

    _applyLocalVote(council, option);
    if (council.selectedOption == null) {
      _selectedVotes.remove(councilId);
    } else {
      _selectedVotes[councilId] = council.selectedOption!;
    }
    _upsertLocalCouncil(council);
    _emitFeedChange();

    try {
      if (_usingFirestore && !_isDemoCouncil(council)) {
        await FirebaseCouncilRepository.instance.castVote(
          councilId: councilId,
          option: option,
        );
      }
    } catch (_) {
      council.participants = previousParticipants;
      council.hasVoted = previousHasVoted;
      council.selectedOption = previousSelectedOption;
      council.votesCount = previousVotesCount;
      council.supportPercent = previousSupportPercent;
      council.againstPercent = previousAgainstPercent;
      council.neutralPercent = previousNeutralPercent;
      if (previousSessionVote == null) {
        _selectedVotes.remove(councilId);
      } else {
        _selectedVotes[councilId] = previousSessionVote;
      }
      _upsertLocalCouncil(council);
      _emitFeedChange();
      rethrow;
    }
  }

  void _acquireCouncilComments(String councilId) {
    if (councilId.trim().isEmpty) return;
    final firstWatcher = _commentWatchRegistry.acquire(councilId);
    if (!firstWatcher) return;
    if (_usingFirestore) _startCommentsSubscription(councilId);
  }

  void _releaseCouncilComments(String councilId) {
    final finalWatcher = _commentWatchRegistry.release(councilId);
    if (!finalWatcher) return;
    final subscription = _commentSubscriptions.remove(councilId);
    if (subscription != null) unawaited(subscription.cancel());
    _convincingVotes.removeWhere((key) => key.startsWith('$councilId/'));
    _touchCommentCache(councilId);
    _pruneCommentCache();
  }

  void syncConvincingVote(
    String councilId,
    String commentId,
    bool selected,
  ) {
    final key = '$councilId/$commentId';
    if (selected) {
      _convincingVotes.add(key);
    } else {
      _convincingVotes.remove(key);
    }
  }

  Future<void> addComment(
    String councilId,
    String text, {
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final council = councilById(councilId);
    if (_isDemoCouncil(council)) {
      throw StateError('Demo opportunities are read-only.');
    }

    ContentModeration.ensureAllowed(<String>[trimmed]);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.isAnonymous) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'سجل دخولك لإضافة التعليق.',
      );
    }

    if (!council.allowComments) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'failed-precondition',
        message: 'التعليقات غير متاحة لهذه الفرصة حالياً.',
      );
    }

    final localCommentId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    CommentModel? parentComment;
    if (parentId != null) {
      for (final comment in council.comments) {
        if (comment.id == parentId) {
          parentComment = comment;
          break;
        }
      }
    }

    final optimisticComment = CommentModel(
      id: localCommentId,
      authorId: firebaseUser.uid,
      authorName: _user.name,
      avatarEmoji: _user.avatarEmoji,
      text: trimmed,
      minutesAgo: 1,
      createdAt: DateTime.now().toUtc(),
      convincingCount: 0,
      repliesCount: 0,
      parentId: parentId,
    );

    final isDemoCouncil = _isDemoCouncil(council);
    if (parentComment != null) parentComment.repliesCount += 1;
    council.comments.insert(0, optimisticComment);
    if (isDemoCouncil) {
      _privateDemoComments
          .putIfAbsent(councilId, () => <CommentModel>[])
          .insert(0, optimisticComment);
    } else {
      _localCommentOverlays
          .putIfAbsent(councilId, () => <CommentModel>[])
          .insert(0, optimisticComment);
    }
    council.commentsCount += 1;
    _user.comments += 1;
    _emitFeedAndUserChange();

    try {
      if (_usingFirestore && !isDemoCouncil) {
        final serverCommentId =
            await FirebaseCouncilRepository.instance.addComment(
          councilId: councilId,
          text: trimmed,
          parentId: parentId,
        );
        if (serverCommentId != null && serverCommentId.isNotEmpty) {
          _replaceLocalCommentId(
            councilId: councilId,
            localCommentId: localCommentId,
            serverCommentId: serverCommentId,
          );
        }
      }
    } catch (_) {
      final beforeLength = council.comments.length;
      council.comments.removeWhere((comment) => comment.id == localCommentId);
      _removeVisibleComment(councilId, localCommentId);
      if (isDemoCouncil) {
        _privateDemoComments[councilId]
            ?.removeWhere((comment) => comment.id == localCommentId);
      } else {
        _localCommentOverlays[councilId]
            ?.removeWhere((comment) => comment.id == localCommentId);
        if (_localCommentOverlays[councilId]?.isEmpty == true) {
          _localCommentOverlays.remove(councilId);
        }
      }
      final removed = beforeLength - council.comments.length;
      if (removed > 0) {
        council.commentsCount = council.commentsCount > removed
            ? council.commentsCount - removed
            : 0;
        _user.comments =
            _user.comments > removed ? _user.comments - removed : 0;
      }
      if (parentComment != null && parentComment.repliesCount > 0) {
        parentComment.repliesCount -= 1;
      }
      _emitFeedAndUserChange();
      rethrow;
    }
  }

  Future<void> addConvincingVote(String councilId, String commentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final council = councilById(councilId);
    if (_isDemoCouncil(council)) {
      throw StateError('Demo opportunities are read-only.');
    }

    CommentModel? targetComment;
    for (final comment in council.comments) {
      if (comment.id == commentId) {
        targetComment = comment;
        break;
      }
    }

    if (targetComment != null && targetComment.authorId == uid) {
      throw StateError('Users cannot mark their own comments as convincing.');
    }
    if (targetComment == null) return;

    final voteKey = '$councilId/$commentId';
    final hadVote = _convincingVotes.contains(voteKey);
    final previousCount = targetComment.convincingCount;

    if (hadVote) {
      targetComment.convincingCount = targetComment.convincingCount > 0
          ? targetComment.convincingCount - 1
          : 0;
      _convincingVotes.remove(voteKey);
    } else {
      targetComment.convincingCount += 1;
      _convincingVotes.add(voteKey);
    }
    final isDemoCouncil = _isDemoCouncil(council);
    _emitFeedChange();

    try {
      if (_usingFirestore && !isDemoCouncil) {
        await FirebaseCouncilRepository.instance.toggleConvincingVote(
          councilId: councilId,
          commentId: commentId,
        );
      }
    } catch (_) {
      targetComment.convincingCount = previousCount;
      if (hadVote) {
        _convincingVotes.add(voteKey);
      } else {
        _convincingVotes.remove(voteKey);
      }
      _emitFeedChange();
      rethrow;
    }
  }

  Future<void> createReport({
    required String targetType,
    required String targetPath,
    required String reason,
    String? councilId,
    String? commentId,
    String? details,
  }) {
    return FirebaseCouncilRepository.instance.createReport(
      targetType: targetType,
      targetPath: targetPath,
      reason: reason,
      councilId: councilId,
      commentId: commentId,
      details: details,
    );
  }

  bool canManageCouncil(CouncilModel council) {
    return isCouncilOwner(council);
  }

  bool isCouncilOwner(CouncilModel council) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ownerId = council.createdBy?.trim();
    return uid != null &&
        uid.isNotEmpty &&
        ownerId != null &&
        ownerId.isNotEmpty &&
        ownerId == uid;
  }

  Future<void> refreshCouncilVisibility(String councilId) async {
    if (_usingFirestore) {
      await FirebaseCouncilRepository.instance.refreshCouncilVisibility(
        councilId: councilId,
      );
    }

    final index = _councils.indexWhere((item) => item.id == councilId);
    if (index == -1) return;

    final council = _councils.removeAt(index);
    _councils.insert(0, council);
    _emitFeedChange();
  }

  Future<void> deleteCouncil(String councilId) async {
    if (_usingFirestore) {
      await FirebaseCouncilRepository.instance.deleteCouncil(
        councilId: councilId,
      );
    }

    _councils.removeWhere((item) => item.id == councilId);
    _mockCouncils.removeWhere((item) => item.id == councilId);
    _emitFeedChange();
  }

  Future<CouncilModel> createCouncil({
    required String title,
    required String description,
    required String category,
    required String city,
    required bool isPrivate,
    required bool allowComments,
    List<XFile> imageFiles = const [],
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.isAnonymous) {
      throw StateError('يجب تسجيل الدخول لإنشاء فرصة.');
    }

    final titleText =
        title.trim().isEmpty ? 'فرصة جديدة بدون عنوان' : title.trim();
    final descriptionText = description.trim().isEmpty
        ? 'شاركنا رأيك في هذه الفرصة.'
        : description.trim();
    ContentModeration.ensureAllowed(<String>[titleText, descriptionText]);
    final ownerName = firebaseUser.displayName?.trim().isNotEmpty == true
        ? firebaseUser.displayName!.trim()
        : _user.name;
    final ownerPhotoUrl = firebaseUser.photoURL;
    final createdCouncil =
        await FirebaseCouncilRepository.instance.createCouncil(
      title: titleText,
      description: descriptionText,
      category: category,
      city: city,
      ownerId: firebaseUser.uid,
      ownerName: ownerName,
      ownerPhotoUrl: ownerPhotoUrl,
      ownerAvatarEmoji: _user.avatarEmoji,
      categoryId: _categoryId(category),
      imageFiles: imageFiles,
      isPrivate: isPrivate,
      allowComments: allowComments,
    );

    final council = CouncilModel(
      id: createdCouncil.id,
      title: titleText,
      description: descriptionText,
      categoryId: _categoryId(category),
      category: category,
      city: city.trim(),
      status: CouncilStatus.active,
      participants: 0,
      commentsCount: 0,
      votesCount: 0,
      supportPercent: 0,
      againstPercent: 0,
      neutralPercent: 0,
      endsIn: '',
      comments: [],
      isPrivate: isPrivate,
      allowComments: allowComments,
      createdBy: firebaseUser.uid,
      createdByName: ownerName,
      createdAt: DateTime.now().toUtc(),
      coverImageUrl: createdCouncil.imageUrls.isNotEmpty
          ? createdCouncil.imageUrls.first
          : null,
      coverThumbnailUrl: createdCouncil.thumbnailUrls.isNotEmpty
          ? createdCouncil.thumbnailUrls.first
          : null,
      coverMediumUrl: createdCouncil.mediumImageUrls.isNotEmpty
          ? createdCouncil.mediumImageUrls.first
          : null,
      imageUrls: createdCouncil.imageUrls,
      thumbnailUrls: createdCouncil.thumbnailUrls,
      mediumImageUrls: createdCouncil.mediumImageUrls,
    );
    _upsertLocalCouncil(council);
    _user.councils += 1;
    _emitFeedAndUserChange();
    return council;
  }

  Future<bool> updateNickname(String name, String avatarEmoji) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null && !firebaseUser.isAnonymous) {
      final claim = await FirebaseUserRepository.instance.claimNickname(
        uid: firebaseUser.uid,
        nickname: name,
        avatarEmoji: avatarEmoji,
      );
      if (!claim.changed) return false;

      _user.name = claim.nickname;
      _user.username = claim.username;
      _user.avatarEmoji = claim.avatarEmoji;
      _user.nicknameLocked = claim.nicknameLocked;
    } else {
      final trimmed = name.trim();
      final changed = trimmed.isNotEmpty &&
          (trimmed != _user.name || avatarEmoji != _user.avatarEmoji);
      if (!changed) return false;

      if (trimmed.isNotEmpty) {
        _user.name = trimmed;
        _user.username = '@${trimmed.replaceAll(' ', '_')}';
      }
      _user.avatarEmoji = avatarEmoji;
      _user.nicknameLocked = true;
    }
    _emitUserChange();
    return true;
  }

  Future<bool> updateAvatarEmoji(String avatarEmoji) async {
    final safeAvatar = avatarEmoji.trim();
    if (safeAvatar.isEmpty || safeAvatar == _user.avatarEmoji) return false;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null && !firebaseUser.isAnonymous) {
      await FirebaseUserRepository.instance.updateUserProfile(
        uid: firebaseUser.uid,
        avatarEmoji: safeAvatar,
      );
    }

    _user.avatarEmoji = safeAvatar;
    _emitUserChange();
    return true;
  }

  void syncUser(UserModel user) {
    if (_sameUser(_user, user)) return;

    _user = user;
    _emitUserChange();
  }

  void retryFirestoreSync() {
    _startFirestoreSync();
  }

  void _startFirestoreSync() {
    _councilsSubscription?.cancel();
    _firestoreError = null;
    _receivedServerCouncilSnapshot = false;
    _remoteSyncDelayed = false;
    _startCouncilSyncWatchdog();
    _emitFeedChange();

    _ensureDemoOpportunity();
    _startResultsSync();
    _councilsSubscription = FirebaseCouncilRepository.instance
        .watchCouncilSnapshots(limit: 80)
        .listen(
      (snapshot) {
        final firestoreCouncils = snapshot.councils;
        final connectionStateChanged = snapshot.isFromCache
            ? false
            : !_receivedServerCouncilSnapshot ||
                _remoteSyncDelayed ||
                _firestoreError != null;
        if (!snapshot.isFromCache) {
          _receivedServerCouncilSnapshot = true;
          _remoteSyncDelayed = false;
          _firestoreError = null;
          _lastRemoteSyncAt = DateTime.now();
          _councilSyncWatchdog?.cancel();
          _councilSyncWatchdog = null;
        }

        if (!snapshot.dataChanged) {
          if (connectionStateChanged) _emitFeedChange();
          return;
        }

        if (firestoreCouncils.isEmpty) {
          _usingFirestore = false;
          _councils = List<CouncilModel>.from(_mockCouncils);
        } else {
          _usingFirestore = true;
          _councils = _withPublicDemoFallback(firestoreCouncils)
              .map(_withSessionVote)
              .map(_withCachedComments)
              .toList();
          _refreshCommentSubscriptions();
        }
        _emitFeedChange();
      },
      onError: (Object error) {
        _firestoreError = error;
        _remoteSyncDelayed = true;
        _councilSyncWatchdog?.cancel();
        _councilSyncWatchdog = null;
        _usingFirestore = false;
        _councils = List<CouncilModel>.from(_mockCouncils);
        _emitFeedChange();
      },
    );
  }

  void _startUserSync() {
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
          _watchFirebaseUser,
          onError: (_) => _watchFirebaseUser(null),
        );
    _watchFirebaseUser(FirebaseAuth.instance.currentUser);
  }

  void _watchFirebaseUser(User? firebaseUser) {
    _userSubscription?.cancel();
    _userSubscription = null;
    _blockedUsersSubscription?.cancel();
    _blockedUsersSubscription = null;
    _convincingVotes.clear();
    _blockedUserIds.clear();

    if (firebaseUser == null || firebaseUser.isAnonymous) {
      if (!_sameUser(_user, MockData.currentUser)) {
        _user = MockData.currentUser;
        _emitUserChange();
      }
      return;
    }

    _blockedUsersSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .collection('blockedUsers')
        .snapshots()
        .listen((snapshot) {
      _blockedUserIds
        ..clear()
        ..addAll(snapshot.docs.map((doc) => doc.id));
      for (final subscription in _commentSubscriptions.values) {
        unawaited(subscription.cancel());
      }
      _commentSubscriptions.clear();
      for (final council in _councils) {
        _applyCachedComments(council);
      }
      _refreshCommentSubscriptions();
      _emitFeedChange();
    }, onError: (_) {});

    _userSubscription =
        FirebaseUserRepository.instance.watchUser(firebaseUser.uid).listen(
      (user) {
        if (user != null) syncUser(user);
      },
      onError: (_) {},
    );
    _ensureDemoOpportunity();
  }

  void _startCouncilSyncWatchdog() {
    _councilSyncWatchdog?.cancel();
    _councilSyncWatchdog = Timer(const Duration(seconds: 7), () {
      if (_receivedServerCouncilSnapshot) return;
      _remoteSyncDelayed = true;
      _emitFeedChange();
    });
  }

  void _ensureDemoOpportunity({bool force = false}) {
    if (!force && _demoOpportunityRequested) return;
    _demoOpportunityRequested = true;
    FirebaseCouncilRepository.instance.ensureDemoOpportunity().catchError((_) {
      _demoOpportunityRequested = false;
    });
  }

  List<CouncilModel> _withPublicDemoFallback(List<CouncilModel> councils) {
    final hasPublicDemo = councils.any(
      (council) => council.id == FirebaseCouncilRepository.publicDemoCouncilId,
    );
    if (hasPublicDemo) return councils;

    for (final council in _mockCouncils) {
      if (council.id == FirebaseCouncilRepository.publicDemoCouncilId) {
        return [council, ...councils];
      }
    }

    return councils;
  }

  bool _sameUser(UserModel a, UserModel b) {
    return a.name == b.name &&
        a.username == b.username &&
        a.avatarEmoji == b.avatarEmoji &&
        a.points == b.points &&
        a.comments == b.comments &&
        a.councils == b.councils &&
        a.badge == b.badge &&
        a.nicknameLocked == b.nicknameLocked;
  }

  void _startResultsSync() {
    _resultsSubscription?.cancel();
    _resultsSubscription = FirebaseCouncilRepository.instance
        .watchCouncilResults(limit: 80)
        .listen(
      (results) {
        _results = results;
        _resultsStateNotifier.value =
            List<CouncilResultModel>.unmodifiable(results);
        notifyListeners();
      },
      onError: (_) {
        _results = [];
        _resultsStateNotifier.value = const <CouncilResultModel>[];
        notifyListeners();
      },
    );
  }

  void _refreshCommentSubscriptions() {
    for (final councilId in _commentWatchRegistry.activeKeys) {
      _startCommentsSubscription(councilId);
    }
  }

  void _startCommentsSubscription(String councilId) {
    if (_commentSubscriptions.containsKey(councilId)) return;

    _commentSubscriptions[councilId] = FirebaseCouncilRepository.instance
        .watchComments(councilId)
        .listen((comments) {
      _remoteCommentsByCouncilId[councilId] = comments;
      _touchCommentCache(councilId);
      _pruneCommentCache();
      _pruneLocalCommentOverlay(councilId, comments);
      if (_applyCachedCommentsToCouncil(councilId)) _emitFeedChange();
    }, onError: (_) {});
  }

  void _touchCommentCache(String councilId) {
    if (!_remoteCommentsByCouncilId.containsKey(councilId)) return;
    _recentCommentCacheCouncilIds
      ..remove(councilId)
      ..add(councilId);
  }

  void _pruneCommentCache() {
    const maximumCachedCouncils = 4;
    while (_remoteCommentsByCouncilId.length > maximumCachedCouncils) {
      String? councilId;
      for (final candidate in _recentCommentCacheCouncilIds) {
        if (_commentWatchRegistry.referenceCountFor(candidate) == 0) {
          councilId = candidate;
          break;
        }
      }
      if (councilId == null) return;

      _recentCommentCacheCouncilIds.remove(councilId);
      _remoteCommentsByCouncilId.remove(councilId);
      final council = _findCouncilById(councilId);
      if (council == null) continue;
      final retainedLocalComments = _visibleCommentsForCouncil(
        councilId,
        const <CommentModel>[],
      );
      council.comments = retainedLocalComments;
    }
  }

  CouncilModel _withCachedComments(CouncilModel council) {
    _applyCachedComments(council);
    return council;
  }

  bool _applyCachedCommentsToCouncil(String councilId) {
    final index = _councils.indexWhere((item) => item.id == councilId);
    if (index != -1) {
      _applyCachedComments(_councils[index]);
      return true;
    }

    final standaloneCouncil = _standaloneCouncilsById[councilId];
    if (standaloneCouncil == null) return false;
    _applyCachedComments(standaloneCouncil);
    return true;
  }

  void _applyCachedComments(CouncilModel council) {
    final remoteComments = _remoteCommentsByCouncilId[council.id];
    final hasLocalComments =
        _localCommentOverlays[council.id]?.isNotEmpty == true ||
            _privateDemoComments[council.id]?.isNotEmpty == true;
    if (remoteComments == null && !hasLocalComments) return;
    final sourceComments = remoteComments == null ||
            (remoteComments.isEmpty &&
                council.id == FirebaseCouncilRepository.publicDemoCouncilId)
        ? council.comments
        : remoteComments;

    final visibleComments = _visibleCommentsForCouncil(
      council.id,
      sourceComments,
    );
    council.comments = visibleComments;
    council.commentsCount = visibleComments.length;
  }

  List<CommentModel> _visibleCommentsForCouncil(
    String councilId,
    List<CommentModel> remoteComments,
  ) {
    final remoteIds = remoteComments.map((comment) => comment.id).toSet();
    final localComments = _localCommentOverlays[councilId] ?? const [];
    final mergedComments = <CommentModel>[
      for (final comment in localComments)
        if (!remoteIds.contains(comment.id)) comment,
      ...remoteComments,
    ];
    final baseComments = mergedComments
        .where((comment) => !_blockedUserIds.contains(comment.authorId))
        .toList(growable: false);
    final visibleComments = _withPrivateDemoComments(councilId, baseComments);
    visibleComments.sort(_compareCommentsNewestFirst);
    return visibleComments;
  }

  void _replaceLocalCommentId({
    required String councilId,
    required String localCommentId,
    required String serverCommentId,
  }) {
    final comments = _localCommentOverlays[councilId];
    if (comments == null || comments.isEmpty) return;

    final index =
        comments.indexWhere((comment) => comment.id == localCommentId);
    if (index == -1) return;

    comments[index] = comments[index].copyWith(id: serverCommentId);
    _pruneLocalCommentOverlay(
      councilId,
      _remoteCommentsByCouncilId[councilId] ?? const <CommentModel>[],
    );
    if (_applyCachedCommentsToCouncil(councilId)) _emitFeedChange();
  }

  void _removeVisibleComment(String councilId, String commentId) {
    final index = _councils.indexWhere((item) => item.id == councilId);
    if (index == -1) return;

    final council = _councils[index];
    final beforeLength = council.comments.length;
    council.comments.removeWhere((comment) => comment.id == commentId);
    final removed = beforeLength - council.comments.length;
    if (removed > 0) {
      council.commentsCount =
          council.commentsCount > removed ? council.commentsCount - removed : 0;
    }
  }

  void _pruneLocalCommentOverlay(
    String councilId,
    List<CommentModel> remoteComments,
  ) {
    final comments = _localCommentOverlays[councilId];
    if (comments == null || comments.isEmpty) return;

    final remoteIds = remoteComments.map((comment) => comment.id).toSet();
    comments.removeWhere((comment) => remoteIds.contains(comment.id));
    if (comments.isEmpty) _localCommentOverlays.remove(councilId);
  }

  int _compareCommentsNewestFirst(CommentModel a, CommentModel b) {
    final aCreatedAt = a.createdAt;
    final bCreatedAt = b.createdAt;
    if (aCreatedAt != null && bCreatedAt != null) {
      return bCreatedAt.compareTo(aCreatedAt);
    }
    if (aCreatedAt != null) return -1;
    if (bCreatedAt != null) return 1;
    return a.minutesAgo.compareTo(b.minutesAgo);
  }

  List<CommentModel> _withPrivateDemoComments(
    String councilId,
    List<CommentModel> comments,
  ) {
    final localComments = _privateDemoComments[councilId];
    if (localComments == null || localComments.isEmpty) return comments;

    final ids = comments.map((comment) => comment.id).toSet();
    return <CommentModel>[
      for (final comment in localComments)
        if (!ids.contains(comment.id)) comment,
      ...comments,
    ];
  }

  bool _isDemoCouncil(CouncilModel council) {
    return council.isSeedContent || council.id.startsWith('demo_');
  }

  bool _isBlockedCouncil(CouncilModel council) {
    final ownerId = council.createdBy?.trim();
    return ownerId != null && _blockedUserIds.contains(ownerId);
  }

  CouncilModel? _findCouncilById(String id) {
    for (final council in _councils) {
      if (council.id == id) return council;
    }
    final standaloneCouncil = _standaloneCouncilsById[id];
    if (standaloneCouncil != null) return standaloneCouncil;
    for (final council in _mockCouncils) {
      if (council.id == id) return council;
    }
    return null;
  }

  void _upsertLocalCouncil(CouncilModel council) {
    final index = _councils.indexWhere((item) => item.id == council.id);
    if (index == -1) {
      final insertIndex = _councils.isEmpty ? 0 : 1;
      _councils.insert(insertIndex, council);
      return;
    }

    _councils[index] = council;
  }

  void _applyLocalVote(CouncilModel council, VoteOption option) {
    final previous = council.selectedOption;
    if (previous == option) {
      final counts = _estimatedVoteCounts(council);
      counts[option] = (counts[option] ?? 0) - 1;
      if ((counts[option] ?? 0) < 0) counts[option] = 0;
      council.participants =
          council.participants > 0 ? council.participants - 1 : 0;
      council.hasVoted = false;
      council.selectedOption = null;
      council.votesCount =
          counts.values.fold<int>(0, (total, value) => total + value);
      council.supportPercent =
          _percent(counts[VoteOption.support] ?? 0, council.votesCount);
      council.againstPercent =
          _percent(counts[VoteOption.against] ?? 0, council.votesCount);
      council.neutralPercent =
          _percent(counts[VoteOption.neutral] ?? 0, council.votesCount);
      return;
    }

    final counts = _estimatedVoteCounts(council);
    if (previous == null) {
      council.participants += 1;
    } else {
      counts[previous] = (counts[previous] ?? 0) - 1;
      if ((counts[previous] ?? 0) < 0) counts[previous] = 0;
    }

    counts[option] = (counts[option] ?? 0) + 1;
    council.hasVoted = true;
    council.selectedOption = option;
    council.votesCount =
        counts.values.fold<int>(0, (total, value) => total + value);
    council.supportPercent =
        _percent(counts[VoteOption.support] ?? 0, council.votesCount);
    council.againstPercent =
        _percent(counts[VoteOption.against] ?? 0, council.votesCount);
    council.neutralPercent =
        _percent(counts[VoteOption.neutral] ?? 0, council.votesCount);
  }

  CouncilModel _withSessionVote(CouncilModel council) {
    council.category = _canonicalCategory(council.category);
    council.categoryId = _categoryId(council.category);

    final selected = _selectedVotes[council.id];
    if (selected == null) return council;

    council.hasVoted = true;
    council.selectedOption = selected;
    return council;
  }

  Map<VoteOption, int> _estimatedVoteCounts(CouncilModel council) {
    final total = council.votesCount;
    return {
      VoteOption.support: _countFromPercent(council.supportPercent, total),
      VoteOption.against: _countFromPercent(council.againstPercent, total),
      VoteOption.neutral: _countFromPercent(council.neutralPercent, total),
    };
  }

  int _countFromPercent(int percent, int total) {
    if (percent <= 0 || total <= 0) return 0;
    return ((percent / 100) * total).round();
  }

  int _percent(int count, int total) {
    if (count <= 0 || total <= 0) return 0;
    return ((count / total) * 100).round();
  }

  String _canonicalCategory(String category) {
    final value = category.trim();
    if (value == 'الكل') return value;
    if (value.contains('تقبيل') ||
        value.contains('للبيع') ||
        value.contains('بيع') ||
        value.contains('تنازل') ||
        value.contains('محل') ||
        value.contains('كوفي') ||
        value.contains('مغسلة') ||
        value.contains('صالون') ||
        value.contains('ورشة')) {
      return 'فرص للتقبيل';
    }
    if (value.contains('مطلوبة') ||
        value.contains('مطلوب') ||
        value.contains('أبحث') ||
        value.contains('ابحث') ||
        value.contains('أبي') ||
        value.contains('احتاج') ||
        value.contains('ميزانية')) {
      return 'فرص مطلوبة';
    }
    if (value.contains('شراكة') ||
        value.contains('شريك') ||
        value.contains('شركاء') ||
        value.contains('ممول') ||
        value.contains('تشغيل') ||
        value.contains('تسويق')) {
      return 'فرص شراكة';
    }
    return 'تجارب السوق';
  }

  String _categoryId(String category) {
    return category
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\u0600-\u06FF\w_]'), '')
        .toLowerCase();
  }

  @override
  void dispose() {
    _councilsSubscription?.cancel();
    _resultsSubscription?.cancel();
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    _blockedUsersSubscription?.cancel();
    _councilSyncWatchdog?.cancel();
    for (final subscription in _commentSubscriptions.values) {
      subscription.cancel();
    }
    _feedStateNotifier.dispose();
    _userStateNotifier.dispose();
    _resultsStateNotifier.dispose();
    super.dispose();
  }
}

class CouncilDetailsSession extends ChangeNotifier {
  CouncilDetailsSession._(this._repository, this.councilId) {
    _repository._acquireCouncilComments(councilId);
    unawaited(_repository._loadCouncilIfMissing(councilId));
    _lastRevision = _calculateRevision();
    _repository.feedState.addListener(_handleRepositoryChange);
  }

  final CouncilRepository _repository;
  final String councilId;
  late int _lastRevision;
  bool _observingFeed = true;
  bool _disposed = false;

  CouncilRepository get repository => _repository;
  CouncilModel? get council => _repository.findCouncilById(councilId);

  void setPresentationActive(bool value) {
    if (_disposed || _observingFeed == value) return;
    _observingFeed = value;
    if (value) {
      _repository.feedState.addListener(_handleRepositoryChange);
      _handleRepositoryChange();
    } else {
      _repository.feedState.removeListener(_handleRepositoryChange);
    }
  }

  void _handleRepositoryChange() {
    if (_disposed) return;
    final revision = _calculateRevision();
    if (_lastRevision == revision) return;
    _lastRevision = revision;
    notifyListeners();
  }

  int _calculateRevision() {
    final value = council;
    if (value == null) return 0;
    return Object.hashAll(
      <Object?>[
        value.id,
        value.title,
        value.description,
        value.categoryId,
        value.category,
        value.city,
        value.status,
        value.participants,
        value.commentsCount,
        value.votesCount,
        value.supportPercent,
        value.againstPercent,
        value.neutralPercent,
        value.endsIn,
        value.isPrivate,
        value.allowComments,
        value.isCouncilOfDay,
        value.isPinned,
        value.hasVoted,
        value.selectedOption,
        Object.hashAll(value.imageUrls),
        Object.hashAll(value.thumbnailUrls),
        Object.hashAll(value.mediumImageUrls),
        Object.hashAll(
          value.comments.map(
            (comment) => Object.hash(
              comment.id,
              comment.parentId,
              comment.text,
              comment.convincingCount,
              comment.repliesCount,
              comment.isBest,
              _repository.hasConvincingVote(councilId, comment.id),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_observingFeed) {
      _repository.feedState.removeListener(_handleRepositoryChange);
    }
    _repository._releaseCouncilComments(councilId);
    super.dispose();
  }
}
