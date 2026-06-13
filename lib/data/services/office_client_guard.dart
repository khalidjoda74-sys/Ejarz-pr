import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum OfficeLocalBlockState {
  confirmedBlocked,
  notBlocked,
  unknown,
}

class OfficeClientMatch {
  final String officeId;
  final String docId;
  final String matchedBy;
  final Map<String, dynamic> data;

  const OfficeClientMatch({
    required this.officeId,
    required this.docId,
    required this.matchedBy,
    required this.data,
  });

  bool get isBlocked => OfficeClientGuard.isBlockedClientData(data);
}

class OfficeClientGuard {
  static const String _sessionBoxName = 'sessionBox';
  static const String _flagKey = 'isOfficeClient';
  static const String _impersonationKey = 'officeImpersonation';
  static const String _officeStaffPermissionKey = 'officeStaffPermission';
  static const String _officeStaffOfficeUidKey = 'officeStaffOfficeUid';
  static const String _clientNeedsInternetKey = 'clientNeedsInternet';
  static const String _loggedInKey = 'loggedIn';
  static const String _officeBlockedKey = 'office_client_blocked';
  static const String _officeBlockedEmailKey = 'office_client_blocked_email';
  static const String _officeBlockedUidKey = 'office_client_blocked_uid';
  static const String _officeBlockedConfirmedKey =
      'office_client_blocked_confirmed';
  static const String _officeBlockedAtKey = 'office_client_blocked_at_ms';
  static const String _intentionalLogoutKey =
      'office_intentional_logout_in_progress';

  static const String blockedOfficeClientMessage =
      'تم إيقاف دخولك من المكتب، لا يمكن استخدام الحساب حتى يقوم المكتب بإعادة تفعيله.';

  static const String officeClientWriteMessage =
      'ليس لديك صلاحية لتنفيذ هذا الإجراء. هذا الحساب يدار بالكامل عن طريق مكتب العقار.';

  static const String readOnlyOfficeStaffMessage =
      'ليس لديك صلاحية لتنفيذ هذا الإجراء. هذا المستخدم للمشاهدة فقط.';

  static const String officeProfileStaffMessage =
      'بيانات المكتب لا يمكن تعديلها من مستخدم المكتب. يرجى الدخول من حساب المكتب الرئيسي.';

  static bool? _cachedIsOfficeClient;

  static Future<Box> _sessionBox() async {
    if (Hive.isBoxOpen(_sessionBoxName)) {
      return Hive.box(_sessionBoxName);
    }
    return Hive.openBox(_sessionBoxName);
  }

  static bool isBlockedClientData(Map<String, dynamic> m) {
    return (m['blocked'] == true) ||
        (m['disabled'] == true) ||
        (m['active'] == false) ||
        (m['isActive'] == false);
  }

  static Future<bool> isOfficeClient() async {
    try {
      final box = await _sessionBox();
      final isImpersonation =
          box.get(_impersonationKey, defaultValue: false) == true;
      if (isImpersonation) {
        _cachedIsOfficeClient = false;
        debugPrint(
          '[OfficeClientGuard] isOfficeClient=false reason=office-impersonation',
        );
        return false;
      }

      if (_cachedIsOfficeClient != null) return _cachedIsOfficeClient!;

      final raw = box.get(_flagKey, defaultValue: false);
      final value = raw == true;
      _cachedIsOfficeClient = value;
      return value;
    } catch (_) {
      _cachedIsOfficeClient = false;
      return false;
    }
  }

  static Future<void> refreshFromLocal() async {
    _cachedIsOfficeClient = null;
    await isOfficeClient();
  }

  static Future<void> clearSessionState() async {
    try {
      final box = await _sessionBox();
      await box.put(_loggedInKey, false);
      await box.put(_flagKey, false);
      await box.put(_clientNeedsInternetKey, false);
      await box.put(_impersonationKey, false);
      await box.delete(_officeStaffPermissionKey);
      await box.delete(_officeStaffOfficeUidKey);
    } catch (_) {}
  }

  static String normalizeOfficePermission(Object? value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'full' || raw == 'control' || raw == 'write' || raw == 'admin') {
      return 'full';
    }
    if (raw == 'view' || raw == 'read' || raw == 'readonly') {
      return 'view';
    }
    return '';
  }

  static Future<String> currentOfficeStaffPermission() async {
    try {
      final box = await _sessionBox();
      return normalizeOfficePermission(box.get(_officeStaffPermissionKey));
    } catch (_) {
      return '';
    }
  }

  static Future<String> currentOfficeStaffOfficeUid() async {
    try {
      final box = await _sessionBox();
      return (box.get(_officeStaffOfficeUidKey, defaultValue: '') ?? '')
          .toString()
          .trim();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> isOfficeStaffSession() async {
    final permission = await currentOfficeStaffPermission();
    final officeUid = await currentOfficeStaffOfficeUid();
    return permission.isNotEmpty || officeUid.isNotEmpty;
  }

  static Future<bool> canWriteCurrentWorkspace() async {
    if (await isOfficeClient()) return false;
    final permission = await currentOfficeStaffPermission();
    if (permission.isEmpty) return true;
    return permission == 'full';
  }

  static Future<bool> isReadOnlyOfficeStaff() async {
    final permission = await currentOfficeStaffPermission();
    return permission == 'view';
  }

  static void _showGuardSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> setIntentionalLogoutInProgress(bool value) async {
    try {
      final box = await _sessionBox();
      await box.put(_intentionalLogoutKey, value);
    } catch (_) {}
  }

  static Future<bool> isIntentionalLogoutInProgress() async {
    try {
      final box = await _sessionBox();
      return box.get(_intentionalLogoutKey, defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> blockIfOfficeClient(BuildContext context) async {
    final isClient = await isOfficeClient();
    if (!isClient) {
      final readOnlyStaff = await isReadOnlyOfficeStaff();
      if (!readOnlyStaff) {
        debugPrint(
          '[OfficeClientGuard] blockIfOfficeClient allow reason=write-allowed',
        );
        return false;
      }
      debugPrint(
        '[OfficeClientGuard] blockIfOfficeClient blocked reason=office-staff-view',
      );
      _showGuardSnack(context, readOnlyOfficeStaffMessage);
      return true;
    }

    debugPrint(
      '[OfficeClientGuard] blockIfOfficeClient blocked reason=office-client',
    );
    _showGuardSnack(context, officeClientWriteMessage);
    return true;
  }

  static Future<bool> blockIfOfficeStaff(BuildContext context) async {
    if (!await isOfficeStaffSession()) return false;
    debugPrint(
      '[OfficeClientGuard] blockIfOfficeStaff blocked reason=office-staff',
    );
    _showGuardSnack(context, officeProfileStaffMessage);
    return true;
  }

  static String normalizeEmail(String? email) {
    return (email ?? '').trim().toLowerCase();
  }

  static String normalizeUid(String? uid) {
    return (uid ?? '').trim();
  }

  static Future<void> markOfficeBlocked(
    bool blocked, {
    String? email,
    String? uid,
  }) async {
    try {
      final box = await _sessionBox();
      await box.put(_officeBlockedKey, blocked);
      final normalizedEmail = normalizeEmail(email);
      final normalizedUid = normalizeUid(uid);
      if (blocked) {
        await box.put(_officeBlockedEmailKey, normalizedEmail);
        await box.put(_officeBlockedUidKey, normalizedUid);
        await box.put(_officeBlockedConfirmedKey, true);
        await box.put(
            _officeBlockedAtKey, DateTime.now().millisecondsSinceEpoch);
      } else {
        await box.delete(_officeBlockedEmailKey);
        await box.delete(_officeBlockedUidKey);
        await box.put(_officeBlockedConfirmedKey, false);
        await box.delete(_officeBlockedAtKey);
      }
    } catch (_) {}
  }

  static Future<OfficeLocalBlockState> localBlockStateForInput({
    String? email,
    String? uid,
  }) async {
    try {
      final box = await _sessionBox();
      final blocked = box.get(_officeBlockedKey, defaultValue: false) == true;
      final storedEmail =
          (box.get(_officeBlockedEmailKey, defaultValue: '') as String)
              .trim()
              .toLowerCase();
      final storedUid =
          (box.get(_officeBlockedUidKey, defaultValue: '') as String).trim();
      final rawConfirmed = box.get(_officeBlockedConfirmedKey);
      final confirmed = rawConfirmed is bool
          ? rawConfirmed
          : (blocked && (storedEmail.isNotEmpty || storedUid.isNotEmpty));
      if (!blocked || !confirmed) return OfficeLocalBlockState.notBlocked;
      if (rawConfirmed is! bool) {
        await box.put(_officeBlockedConfirmedKey, true);
      }

      final normalizedEmail = normalizeEmail(email);
      final normalizedUid = normalizeUid(uid);

      if (storedUid.isNotEmpty && normalizedUid.isNotEmpty) {
        return storedUid == normalizedUid
            ? OfficeLocalBlockState.confirmedBlocked
            : OfficeLocalBlockState.notBlocked;
      }
      if (storedEmail.isNotEmpty && normalizedEmail.isNotEmpty) {
        return storedEmail == normalizedEmail
            ? OfficeLocalBlockState.confirmedBlocked
            : OfficeLocalBlockState.notBlocked;
      }

      // Legacy/invalid local block entry without account identity.
      return OfficeLocalBlockState.unknown;
    } catch (_) {
      return OfficeLocalBlockState.unknown;
    }
  }

  static Future<bool> isOfficeBlockedLocally({
    String? email,
    String? uid,
  }) async {
    final state = await localBlockStateForInput(email: email, uid: uid);
    return state == OfficeLocalBlockState.confirmedBlocked;
  }

  static Future<bool> isBlockedForEmail(String? email) {
    return isOfficeBlockedLocally(email: normalizeEmail(email));
  }

  static Future<OfficeClientMatch?> findOfficeClientMatchForUser(
    User user, {
    Source source = Source.server,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final uid = user.uid.trim();
    final email = (user.email ?? '').trim().toLowerCase();

    Future<OfficeClientMatch?> firstMatchByField({
      required String field,
      required Object value,
      required String matchedBy,
    }) async {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('clients')
          .where(field, isEqualTo: value)
          .limit(5)
          .get(GetOptions(source: source))
          .timeout(timeout);

      for (final doc in snap.docs) {
        final officeId = doc.reference.parent.parent?.id ?? '';
        if (officeId.isEmpty) continue;
        return OfficeClientMatch(
          officeId: officeId,
          docId: doc.id,
          matchedBy: matchedBy,
          data: doc.data(),
        );
      }
      return null;
    }

    if (uid.isNotEmpty) {
      final byUid = await firstMatchByField(
        field: 'uid',
        value: uid,
        matchedBy: 'uid',
      );
      if (byUid != null) return byUid;
    }

    if (email.isNotEmpty) {
      final byEmail = await firstMatchByField(
        field: 'email',
        value: email,
        matchedBy: 'email',
      );
      if (byEmail != null) return byEmail;
    }

    return null;
  }
}
