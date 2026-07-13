import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/moderation/content_moderation.dart';

import '../mock/mock_data.dart';
import '../models/comment_model.dart';
import '../models/council_model.dart';
import '../models/council_result_model.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import 'firebase_council_repository.dart';
import 'firebase_user_repository.dart';

class CouncilRepository extends ChangeNotifier {
  CouncilRepository._();

  static final CouncilRepository instance = CouncilRepository._()
    .._user = MockData.currentUser
    .._mockCouncils = MockData.councils()
    .._councils = MockData.councils()
    .._notifications = MockData.notifications
    .._startFirestoreSync()
    .._startUserSync();

  late UserModel _user;
  late List<CouncilModel> _mockCouncils;
  late List<CouncilModel> _councils;
  List<CouncilResultModel> _results = [];
  late List<NotificationModel> _notifications;
  StreamSubscription<List<CouncilModel>>? _councilsSubscription;
  StreamSubscription<List<CouncilResultModel>>? _resultsSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _userSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _blockedUsersSubscription;
  final Set<String> _blockedUserIds = <String>{};
  final Map<String, StreamSubscription<List<CommentModel>>>
      _commentSubscriptions = {};
  final Map<String, StreamSubscription<bool>>
      _convincingVoteSubscriptions = {};
  final Set<String> _requestedCommentWatches = {};
  final Set<String> _convincingVotes = {};
  final Set<String> _demoOpportunitySeededUsers = {};
  final Map<String, List<CommentModel>> _privateDemoComments = {};
  Object? _firestoreError;
  bool _usingFirestore = false;
  final Map<String, VoteOption> _selectedVotes = {};

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

  Future<void> vote(String councilId, VoteOption option) async {
    final existingCouncil = _findCouncilById(councilId);
    if (existingCouncil != null && isCouncilOwner(existingCouncil)) {
      throw StateError('Opportunity owners cannot vote on their own posts.');
    }

    final council = councilById(councilId);
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
    notifyListeners();

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
      notifyListeners();
      rethrow;
    }
  }

  void watchCouncilComments(String councilId) {
    if (councilId.trim().isEmpty) return;
    _requestedCommentWatches.add(councilId);
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (councilId.startsWith('demo_laundry_') &&
        firebaseUser != null &&
        !firebaseUser.isAnonymous) {
      _ensureDemoOpportunity(firebaseUser, force: true);
    }
    if (_usingFirestore) _startCommentsSubscription(councilId);
  }

  Future<void> addComment(
    String councilId,
    String text, {
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    ContentModeration.ensureAllowed(<String>[trimmed]);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.isAnonymous) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'unauthenticated',
        message: 'سجل دخولك لإضافة التعليق.',
      );
    }

    final council = councilById(councilId);
    if (!council.allowComments) {
      throw FirebaseException(
        plugin: 'majlisna',
        code: 'failed-precondition',
        message: 'التعليقات غير متاحة لهذه الفرصة حالياً.',
      );
    }

    final localCommentId =
        'local_${DateTime.now().microsecondsSinceEpoch}';
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
    }
    council.commentsCount += 1;
    _user.comments += 1;
    notifyListeners();

    try {
      if (_usingFirestore && !isDemoCouncil) {
        await FirebaseCouncilRepository.instance.addComment(
          councilId: councilId,
          text: trimmed,
          parentId: parentId,
        );
      }
    } catch (_) {
      final beforeLength = council.comments.length;
      council.comments.removeWhere((comment) => comment.id == localCommentId);
      if (isDemoCouncil) {
        _privateDemoComments[councilId]
            ?.removeWhere((comment) => comment.id == localCommentId);
      }
      final removed = beforeLength - council.comments.length;
      if (removed > 0) {
        council.commentsCount = council.commentsCount > removed
            ? council.commentsCount - removed
            : 0;
        _user.comments = _user.comments > removed ? _user.comments - removed : 0;
      }
      if (parentComment != null && parentComment.repliesCount > 0) {
        parentComment.repliesCount -= 1;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addConvincingVote(String councilId, String commentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final council = councilById(councilId);
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
    notifyListeners();

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
      notifyListeners();
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
    notifyListeners();
  }

  Future<void> deleteCouncil(String councilId) async {
    if (_usingFirestore) {
      await FirebaseCouncilRepository.instance.deleteCouncil(
        councilId: councilId,
      );
    }

    _councils.removeWhere((item) => item.id == councilId);
    _mockCouncils.removeWhere((item) => item.id == councilId);
    notifyListeners();
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
    final councilId = await FirebaseCouncilRepository.instance.createCouncil(
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
      id: councilId,
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
    );
    _upsertLocalCouncil(council);
    _user.councils += 1;
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    return true;
  }
  void syncUser(UserModel user) {
    if (_sameUser(_user, user)) return;

    _user = user;
    notifyListeners();
  }

  void _startFirestoreSync() {
    _councilsSubscription?.cancel();
    _startResultsSync();
    _councilsSubscription =
        FirebaseCouncilRepository.instance.watchCouncils(limit: 200).listen(
      (firestoreCouncils) {
        _firestoreError = null;
        if (firestoreCouncils.isEmpty) {
          _usingFirestore = false;
          _councils = List<CouncilModel>.from(_mockCouncils);
        } else {
          _usingFirestore = true;
          _councils = firestoreCouncils.map(_withSessionVote).toList();
          _refreshCommentSubscriptions();
        }
        notifyListeners();
      },
      onError: (Object error) {
        _firestoreError = error;
        _usingFirestore = false;
        _councils = List<CouncilModel>.from(_mockCouncils);
        notifyListeners();
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
    _cancelConvincingVoteSubscriptions(clearVotes: true);
    _blockedUserIds.clear();

    if (firebaseUser == null || firebaseUser.isAnonymous) {
      if (!_sameUser(_user, MockData.currentUser)) {
        _user = MockData.currentUser;
        notifyListeners();
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
      _refreshCommentSubscriptions();
      notifyListeners();
    }, onError: (_) {});

    _userSubscription =
        FirebaseUserRepository.instance.watchUser(firebaseUser.uid).listen(
      (user) {
        if (user != null) syncUser(user);
      },
      onError: (_) {},
    );
    _ensureDemoOpportunity(firebaseUser);
  }
  void _ensureDemoOpportunity(User firebaseUser, {bool force = false}) {
    if (!force && !_demoOpportunitySeededUsers.add(firebaseUser.uid)) return;
    _demoOpportunitySeededUsers.add(firebaseUser.uid);
    final displayName = firebaseUser.displayName?.trim();
    FirebaseCouncilRepository.instance
        .ensureDemoOpportunityForUser(
          uid: firebaseUser.uid,
          ownerName: displayName != null && displayName.isNotEmpty
              ? displayName
              : _user.name,
          ownerPhotoUrl: firebaseUser.photoURL,
          ownerAvatarEmoji: _user.avatarEmoji,
        )
        .catchError((_) {
      _demoOpportunitySeededUsers.remove(firebaseUser.uid);
    });
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
        notifyListeners();
      },
      onError: (_) {
        _results = [];
        notifyListeners();
      },
    );
  }

  void _refreshCommentSubscriptions() {
    for (final councilId in _requestedCommentWatches) {
      _startCommentsSubscription(councilId);
    }
  }

  void _startCommentsSubscription(String councilId) {
    if (_commentSubscriptions.containsKey(councilId)) return;

    _commentSubscriptions[councilId] = FirebaseCouncilRepository.instance
        .watchComments(councilId)
        .listen((comments) {
      final index = _councils.indexWhere((item) => item.id == councilId);
      if (index == -1) return;

      final council = _councils[index];
      final baseComments = comments
          .where((comment) => !_blockedUserIds.contains(comment.authorId))
          .toList(growable: false);
      final visibleComments = _withPrivateDemoComments(councilId, baseComments);
      council.comments = visibleComments;
      council.commentsCount = visibleComments.length;
      _refreshConvincingVoteSubscriptions(councilId, visibleComments);
      notifyListeners();
    }, onError: (_) {});
  }

  void _refreshConvincingVoteSubscriptions(
    String councilId,
    List<CommentModel> comments,
  ) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.isAnonymous) return;

    final activeKeys = <String>{};
    for (final comment in comments) {
      if (comment.authorId == firebaseUser.uid) continue;
      final key = '$councilId/${comment.id}';
      activeKeys.add(key);
      _convincingVoteSubscriptions.putIfAbsent(
        key,
        () => FirebaseCouncilRepository.instance
            .watchConvincingVote(commentId: comment.id, uid: firebaseUser.uid)
            .listen(
              (selected) {
                if (selected) {
                  _convincingVotes.add(key);
                } else {
                  _convincingVotes.remove(key);
                }
                notifyListeners();
              },
              onError: (_) {},
            ),
      );
    }

    final staleKeys = _convincingVoteSubscriptions.keys
        .where((key) => key.startsWith('$councilId/') && !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      unawaited(_convincingVoteSubscriptions.remove(key)?.cancel());
      _convincingVotes.remove(key);
    }
  }

  void _cancelConvincingVoteSubscriptions({bool clearVotes = false}) {
    for (final subscription in _convincingVoteSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _convincingVoteSubscriptions.clear();
    if (clearVotes) _convincingVotes.clear();
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
      council.participants = council.participants > 0 ? council.participants - 1 : 0;
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
    for (final subscription in _commentSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}
