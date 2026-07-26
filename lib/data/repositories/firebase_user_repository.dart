import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';

class NicknameClaim {
  const NicknameClaim({
    required this.nickname,
    required this.nicknameKey,
    required this.avatarEmoji,
    required this.changed,
    required this.nicknameLocked,
  });

  final String nickname;
  final String nicknameKey;
  final String avatarEmoji;
  final bool changed;
  final bool nicknameLocked;

  String get username => '@$nicknameKey';
}

class NicknameValidationException implements Exception {
  const NicknameValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NicknameTakenException implements Exception {
  const NicknameTakenException(this.nickname);

  final String nickname;

  String get message => 'الاسم المستعار مستخدم، جرّب اسمًا آخر.';

  @override
  String toString() => message;
}

class NicknameLockedException implements Exception {
  const NicknameLockedException();

  String get message =>
      'لا يمكن تغيير الاسم مرة أخرى. الاسم يتغير مرة واحدة فقط.';

  @override
  String toString() => message;
}

class NicknameCooldownException implements Exception {
  const NicknameCooldownException(this.availableAt);

  final DateTime availableAt;

  String get message {
    final difference = availableAt.difference(DateTime.now());
    final days = difference.isNegative ? 0 : (difference.inHours + 23) ~/ 24;
    return 'يمكنك تغيير الاسم بعد $days يوم.';
  }

  @override
  String toString() => message;
}

class FirebaseUserRepository {
  FirebaseUserRepository._();

  static final FirebaseUserRepository instance = FirebaseUserRepository._();
  static const Duration _identityReadTimeout = Duration(seconds: 4);

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Stream<UserModel?> watchUser(String uid) {
    return _firestore.user(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return UserModel.fromFirestore(snapshot);
    });
  }

  Future<UserModel?> fetchUser(String uid) async {
    final snapshot = await _firestore.user(uid).get();
    if (!snapshot.exists) return null;
    return UserModel.fromFirestore(snapshot);
  }

  Future<void> ensureUserDocument(
    User user, {
    bool knownReturningUser = false,
  }) async {
    final ref = _firestore.user(user.uid);
    final snapshot = await ref.get();
    final providerIds = user.providerData
        .map((provider) => provider.providerId)
        .where((providerId) => providerId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final providerDisplayName = user.displayName?.trim();

    if (!snapshot.exists) {
      await ref.set(
        {
          'uid': user.uid,
          'id': user.uid,
          if (user.email?.trim().isNotEmpty == true)
            'email': user.email!.trim(),
          if (user.photoURL?.trim().isNotEmpty == true)
            'photoUrl': user.photoURL!.trim(),
          if (knownReturningUser && providerDisplayName?.isNotEmpty == true)
            'displayName': providerDisplayName,
          if (knownReturningUser && providerDisplayName?.isNotEmpty == true)
            'name': providerDisplayName,
          'providerIds': providerIds,
          if (knownReturningUser) 'identityCompleted': true,
          'role': 'user',
          'status': 'active',
          'badge': 'عضو نشط',
          'subscriptionType': 'free',
          'points': 0,
          'councilsCount': 0,
          'commentsCount': 0,
          'reportsCount': 0,
          'badges': <String>[],
          'fcmTokens': <String>[],
          'stats': {
            'points': 0,
            'commentsCount': 0,
            'councilsCount': 0,
            'votesCount': 0,
          },
          'notificationPrefs': {
            'pushEnabled': false,
            'inAppEnabled': true,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'lastSignInAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }

    final data = snapshot.data() ?? const {};
    final hadCompletedIdentity = hasCompletedIdentityData(data);
    final identityCompleted = knownReturningUser || hadCompletedIdentity;
    await ref.set({
      if (!hadCompletedIdentity && providerDisplayName?.isNotEmpty == true)
        'displayName': providerDisplayName,
      if (!hadCompletedIdentity && providerDisplayName?.isNotEmpty == true)
        'name': providerDisplayName,
      if (user.email?.trim().isNotEmpty == true) 'email': user.email!.trim(),
      if (user.photoURL?.trim().isNotEmpty == true)
        'photoUrl': user.photoURL!.trim(),
      'providerIds': providerIds,
      if (identityCompleted) 'identityCompleted': true,
      'lastSignInAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasCompletedIdentity(String uid) async {
    final snapshot =
        await _firestore.user(uid).get().timeout(_identityReadTimeout);
    return hasCompletedIdentityData(snapshot.data());
  }

  Future<bool> needsIdentitySetup(String uid) async {
    return !await hasCompletedIdentity(uid);
  }

  static bool hasCompletedIdentityData(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['identityCompleted'] == true) return true;

    final nicknameKey = _stringValue(data['nicknameKey']);
    if (nicknameKey != null && nicknameKey.isNotEmpty) return true;

    // Modern documents explicitly marked incomplete must not be upgraded from
    // placeholder nickname/display fields.
    if (data.containsKey('identityCompleted')) return false;

    // Older app versions stored the chosen identity without nicknameKey or
    // identityCompleted. A real nickname is sufficient legacy evidence.
    final nickname = _stringValue(data['nickname']);
    if (nickname != null && nickname.isNotEmpty) return true;

    // A provider display name can be copied for a genuinely new account, so it
    // is only legacy evidence when the old schema's username also exists.
    final username = _stringValue(data['username']);
    final legacyName =
        _stringValue(data['displayName']) ?? _stringValue(data['name']);
    return username != null &&
        username.isNotEmpty &&
        legacyName != null &&
        legacyName.isNotEmpty;
  }

  Future<NicknameClaim> claimNickname({
    required String uid,
    required String nickname,
    required String avatarEmoji,
  }) async {
    final cleanNickname = cleanNicknameOrThrow(nickname);
    final nicknameKey = nicknameKeyFor(cleanNickname);
    final safeAvatar = avatarEmoji.trim().isEmpty
        ? 'business:person_growth'
        : avatarEmoji.trim();
    final userRef = _firestore.user(uid);
    final nicknameRef = _firestore.nickname(nicknameKey);

    final claim =
        await _firestore.runTransaction<NicknameClaim>((transaction) async {
      final userSnap = await transaction.get(userRef);
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final oldNicknameKey = _stringValue(userData['nicknameKey']);
      final oldAvatarEmoji = _stringValue(userData['avatarEmoji']) ??
          _stringValue(userData['avatar']);
      final nicknameKeyChanged = oldNicknameKey != nicknameKey;
      final avatarChanged = oldAvatarEmoji != safeAvatar;
      final lockedBefore = userData['nicknameLocked'] == true;
      final lockAfterChange = oldNicknameKey != null &&
          oldNicknameKey.isNotEmpty &&
          nicknameKeyChanged;

      if (!nicknameKeyChanged && !avatarChanged) {
        return NicknameClaim(
          nickname: cleanNickname,
          nicknameKey: nicknameKey,
          avatarEmoji: safeAvatar,
          changed: false,
          nicknameLocked: lockedBefore,
        );
      }

      if (nicknameKeyChanged && lockedBefore) {
        throw const NicknameLockedException();
      }

      final nicknameSnap = await transaction.get(nicknameRef);

      DocumentSnapshot<Map<String, dynamic>>? oldNicknameSnap;
      final oldNicknameRef =
          oldNicknameKey != null && oldNicknameKey != nicknameKey
              ? _firestore.nickname(oldNicknameKey)
              : null;
      if (oldNicknameRef != null) {
        oldNicknameSnap = await transaction.get(oldNicknameRef);
      }

      if (nicknameSnap.exists) {
        final ownerUid = _stringValue(nicknameSnap.data()?['uid']);
        if (ownerUid != uid) {
          throw NicknameTakenException(cleanNickname);
        }
      }

      transaction.set(
        nicknameRef,
        {
          'uid': uid,
          'nickname': cleanNickname,
          'key': nicknameKey,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!nicknameSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (oldNicknameRef != null &&
          oldNicknameSnap?.exists == true &&
          _stringValue(oldNicknameSnap?.data()?['uid']) == uid) {
        transaction.delete(oldNicknameRef);
      }

      transaction.set(
        userRef,
        {
          'uid': uid,
          'id': uid,
          'displayName': cleanNickname,
          'nickname': cleanNickname,
          'name': cleanNickname,
          'username': '@$nicknameKey',
          'nicknameKey': nicknameKey,
          'avatarEmoji': safeAvatar,
          'avatar': safeAvatar,
          'identityCompleted': true,
          if (lockAfterChange) 'nicknameLocked': true,
          if (!userSnap.exists) 'nicknameLocked': false,
          'lastActiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (nicknameKeyChanged)
            'nicknameChangedAt': FieldValue.serverTimestamp(),
          if (lockAfterChange) 'nicknameLockedAt': FieldValue.serverTimestamp(),
          if (!userSnap.exists) 'role': 'user',
          if (!userSnap.exists) 'status': 'active',
          if (!userSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return NicknameClaim(
        nickname: cleanNickname,
        nicknameKey: nicknameKey,
        avatarEmoji: safeAvatar,
        changed: true,
        nicknameLocked: lockedBefore || lockAfterChange,
      );
    });

    return claim;
  }

  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? username,
    String? avatarEmoji,
    String? photoUrl,
  }) {
    return _firestore.user(uid).set({
      if (displayName != null) 'displayName': displayName.trim(),
      if (displayName != null) 'name': displayName.trim(),
      if (username != null) 'username': username.trim(),
      if (avatarEmoji != null) 'avatarEmoji': avatarEmoji,
      if (avatarEmoji != null) 'avatar': avatarEmoji,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String cleanNicknameOrThrow(String value) {
    final normalizedSpaces = value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^@+'), '');

    if (normalizedSpaces.length < 2) {
      throw const NicknameValidationException(
        'اكتب اسمًا مستعارًا من حرفين على الأقل.',
      );
    }
    if (normalizedSpaces.length > 24) {
      throw const NicknameValidationException(
        'الاسم المستعار يجب ألا يتجاوز 24 حرفًا.',
      );
    }
    if (!RegExp(r'^[\u0600-\u06FFA-Za-z0-9_ ]+$').hasMatch(normalizedSpaces)) {
      throw const NicknameValidationException(
        'استخدم حروفًا عربية أو إنجليزية وأرقامًا فقط.',
      );
    }
    if (nicknameKeyFor(normalizedSpaces).length < 2) {
      throw const NicknameValidationException(
        'اكتب اسمًا مستعارًا واضحًا من حرفين على الأقل.',
      );
    }

    return normalizedSpaces;
  }

  static String nicknameKeyFor(String value) {
    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), '_');

    return cleaned.replaceAll(RegExp(r'[^a-z0-9_\u0600-\u06FF]'), '');
  }

  static String? validateNickname(String value) {
    try {
      cleanNicknameOrThrow(value);
      return null;
    } on NicknameValidationException catch (error) {
      return error.message;
    }
  }

  Future<void> saveCurrentFcmToken(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      await saveFcmToken(uid: uid, token: token);
    } on FirebaseException {
      return;
    }
  }

  Future<bool> notificationPreferenceEnabled(String uid) async {
    final snapshot = await _firestore.user(uid).get();
    final preferences = snapshot.data()?['notificationPrefs'];
    if (preferences is Map && preferences['enabled'] is bool) {
      return preferences['enabled'] as bool;
    }
    return true;
  }

  Future<void> setNotificationPreference({
    required String uid,
    required bool enabled,
  }) {
    return _firestore.user(uid).set({
      'notificationPrefs': {'enabled': enabled},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveFcmToken({
    required String uid,
    required String token,
    String? deviceId,
    String? appVersion,
    String locale = 'ar',
    bool enabled = true,
  }) {
    final tokenId = _tokenId(token);

    final tokenData = {
      'token': token,
      'platform': _platformLabel(),
      'deviceId': deviceId,
      'appVersion': appVersion,
      'locale': locale,
      'enabled': enabled,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch()
      ..set(
        _firestore.userFcmTokens(uid).doc(tokenId),
        tokenData,
        SetOptions(merge: true),
      )
      ..set(
        _firestore.user(uid),
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

    return batch.commit();
  }

  Future<void> removeFcmToken({
    required String uid,
    required String token,
  }) {
    final batch = _firestore.batch()
      ..delete(_firestore.userFcmTokens(uid).doc(_tokenId(token)))
      ..set(
        _firestore.user(uid),
        {
          'fcmTokens': FieldValue.arrayRemove([token]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

    return batch.commit();
  }

  Future<void> disableFcmToken({
    required String uid,
    required String token,
  }) {
    return _firestore.userFcmTokens(uid).doc(_tokenId(token)).set({
      'enabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _tokenId(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  // ignore: unused_element
  DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
