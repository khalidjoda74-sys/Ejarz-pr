// lib/data/services/user_scope.dart
// Helpers to scope local Hive boxes by the "effective" user:
// - If a fixed (offline) UID is set, we use it.
// - Otherwise we use FirebaseAuth.currentUser?.uid
// - Fallback: "guest"
//
// This lets you switch accounts locally (offline) by calling setFixedUid(clientUid),
// and revert back to the real signed-in user by calling clearFixedUid().

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Holds a manually "fixed" uid for offline impersonation.
/// When non-null, this UID overrides FirebaseAuth.currentUser?.uid.
final ValueNotifier<String?> _fixedUid = ValueNotifier<String?>(null);

/// Returns the effective UID for scoping (fixed -> auth uid -> "guest").
String effectiveUid() {
  return _fixedUid.value ?? FirebaseAuth.instance.currentUser?.uid ?? 'guest';
}

/// Current effective uid (or "guest").
String currentUidSafe() => effectiveUid();

/// Per-user box name (keeps legacy pattern so existing cached boxes keep working):
/// e.g. "contractsBox_<uid>" or "contractsBox_guest".
String boxName(String base) => '${base}_${effectiveUid()}';

/// Set/clear fixed uid to switch scope offline.
void setFixedUid(String? uid) {
  final normalized = (uid != null && uid.isNotEmpty) ? uid : null;
  if (_fixedUid.value != normalized) {
    _fixedUid.value = normalized; // notifies listeners
  }
}

void clearFixedUid() {
  if (_fixedUid.value != null) {
    _fixedUid.value = null; // notifies listeners
  }
}

/// Listen to scope changes (optional).
ValueListenable<String?> get uidListenable => _fixedUid;

/// Throws if effective uid is "guest".
String uidOrThrow() {
  final uid = effectiveUid();
  if (uid == 'guest') {
    throw StateError('No effective user available (uid == "guest").');
  }
  return uid;
}

/// True if no Firebase user AND no fixed uid (pure guest).
bool isGuest() =>
    FirebaseAuth.instance.currentUser == null && _fixedUid.value == null;
