import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntityAuditInfo {
  final String createdByName;
  final String createdByUid;
  final String createdByEmail;
  final DateTime? createdAt;
  final String updatedByName;
  final String updatedByUid;
  final String updatedByEmail;
  final DateTime? updatedAt;
  final String source;

  const EntityAuditInfo({
    required this.createdByName,
    required this.createdByUid,
    required this.createdByEmail,
    required this.createdAt,
    required this.updatedByName,
    required this.updatedByUid,
    required this.updatedByEmail,
    required this.updatedAt,
    this.source = 'remote',
  });
}

class _AuditActor {
  final String uid;
  final String name;
  final String email;
  const _AuditActor(
      {required this.uid, required this.name, required this.email});
}

class EntityAuditService {
  EntityAuditService._();
  static final EntityAuditService instance = EntityAuditService._();
  static const String _managementLabel =
      '\u0627\u0644\u0625\u062f\u0627\u0631\u0629';
  static const String _unknownLabel =
      '\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641';

  static const String fieldCreatedByUid = 'auditCreatedByUid';
  static const String fieldCreatedByName = 'auditCreatedByName';
  static const String fieldCreatedByEmail = 'auditCreatedByEmail';
  static const String fieldCreatedAt = 'auditCreatedAt';
  static const String fieldUpdatedByUid = 'auditUpdatedByUid';
  static const String fieldUpdatedByName = 'auditUpdatedByName';
  static const String fieldUpdatedByEmail = 'auditUpdatedByEmail';
  static const String fieldUpdatedAt = 'auditUpdatedAt';
  final Map<String, String> _officeUserNameCache = <String, String>{};

  Future<void> recordLocalAudit({
    required String workspaceUid,
    required String collectionName,
    required String entityId,
    required bool isCreate,
  }) async {
    final ws = workspaceUid.trim();
    final col = collectionName.trim();
    final id = entityId.trim();
    if (ws.isEmpty || ws == 'guest' || col.isEmpty || id.isEmpty) return;
    final actor = await _resolveCurrentActor(workspaceUid: ws);
    final nowIso = DateTime.now().toIso8601String();
    final key = _localCacheKey(ws, col, id);
    try {
      final sp = await SharedPreferences.getInstance();
      final current = _decodeMap(sp.getString(key));
      final createdByUid =
          (current[fieldCreatedByUid] ?? '').toString().trim().isNotEmpty
              ? (current[fieldCreatedByUid] ?? '').toString().trim()
              : actor.uid;
      final createdByName =
          (current[fieldCreatedByName] ?? '').toString().trim().isNotEmpty
              ? (current[fieldCreatedByName] ?? '').toString().trim()
              : actor.name;
      final createdByEmail =
          (current[fieldCreatedByEmail] ?? '').toString().trim().isNotEmpty
              ? (current[fieldCreatedByEmail] ?? '').toString().trim()
              : actor.email;
      final createdAt =
          (current[fieldCreatedAt] ?? '').toString().trim().isNotEmpty
              ? (current[fieldCreatedAt] ?? '').toString().trim()
              : nowIso;

      final out = <String, dynamic>{
        fieldCreatedByUid: createdByUid,
        fieldCreatedByName: createdByName,
        fieldCreatedByEmail: createdByEmail,
        fieldCreatedAt: createdAt,
        fieldUpdatedByUid: actor.uid,
        fieldUpdatedByName: actor.name,
        fieldUpdatedByEmail: actor.email,
        fieldUpdatedAt: nowIso,
      };
      if (isCreate) {
        out[fieldCreatedByUid] = actor.uid;
        out[fieldCreatedByName] = actor.name;
        out[fieldCreatedByEmail] = actor.email;
        out[fieldCreatedAt] = nowIso;
      }
      await sp.setString(key, _encodeMap(out));
      debugPrint(
        '[AuditTrace][Local] write key=$key isCreate=$isCreate actorUid=${actor.uid} actorName=${actor.name}',
      );
    } catch (e) {
      debugPrint('[AuditTrace][Local] write-failed key=$key err=$e');
    }
  }

  Future<Map<String, dynamic>> buildWriteAuditFields({
    required bool isCreate,
    required String workspaceUid,
  }) async {
    final actor = await _resolveCurrentActor(workspaceUid: workspaceUid);
    debugPrint(
      '[AuditTrace][Write] workspaceUid=$workspaceUid isCreate=$isCreate actorUid=${actor.uid} actorName=${actor.name} actorEmail=${actor.email}',
    );
    final m = <String, dynamic>{
      fieldUpdatedByUid: actor.uid,
      fieldUpdatedByName: actor.name,
      fieldUpdatedByEmail: actor.email,
      fieldUpdatedAt: FieldValue.serverTimestamp(),
    };
    if (isCreate) {
      m[fieldCreatedByUid] = actor.uid;
      m[fieldCreatedByName] = actor.name;
      m[fieldCreatedByEmail] = actor.email;
      m[fieldCreatedAt] = FieldValue.serverTimestamp();
    }
    return m;
  }

  Future<EntityAuditInfo?> loadEntityAudit({
    required String workspaceUid,
    required String collectionName,
    required String entityId,
  }) async {
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final candidateWorkspaces = <String>[
      if (authUid.isNotEmpty && authUid != workspaceUid.trim()) authUid,
      workspaceUid.trim(),
    ].where((e) => e.isNotEmpty && e != 'guest').toList(growable: false);

    debugPrint(
      '[AuditTrace][Read] start collection=$collectionName entityId=$entityId workspaceUid=$workspaceUid authUid=$authUid candidates=$candidateWorkspaces',
    );

    Map<String, dynamic> m = const <String, dynamic>{};
    String resolvedWorkspace = '';
    for (final w in candidateWorkspaces) {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(w)
            .collection(collectionName)
            .doc(entityId)
            .get();
      } on FirebaseException catch (e) {
        debugPrint(
          '[AuditTrace][Read] denied workspace=$w code=${e.code} msg=${e.message}',
        );
        continue;
      } catch (e) {
        debugPrint('[AuditTrace][Read] failed workspace=$w err=$e');
        continue;
      }
      if (!snap.exists) {
        debugPrint(
          '[AuditTrace][Read] miss workspace=$w collection=$collectionName entityId=$entityId',
        );
        continue;
      }
      m = snap.data() ?? const <String, dynamic>{};
      resolvedWorkspace = w;
      debugPrint(
        '[AuditTrace][Read] hit workspace=$w keys=${m.keys.toList()}',
      );
      break;
    }
    if (resolvedWorkspace.isEmpty) {
      final local = await _readLocalAudit(
        candidateWorkspaces: candidateWorkspaces,
        collectionName: collectionName,
        entityId: entityId,
      );
      if (local != null) {
        debugPrint(
          '[AuditTrace][Read] fallback-local collection=$collectionName entityId=$entityId',
        );
        return local;
      }
      final synthesized = await _buildSynthesizedAudit(
        workspaceUid: workspaceUid,
        authUid: authUid,
        entityId: entityId,
      );
      if (synthesized != null) {
        debugPrint(
          '[AuditTrace][Read] fallback-synth collection=$collectionName entityId=$entityId',
        );
        return synthesized;
      }
      debugPrint(
        '[AuditTrace][Read] not-found collection=$collectionName entityId=$entityId',
      );
      return null;
    }

    final createdByUid = (m[fieldCreatedByUid] ??
            m['ownerId'] ??
            m['userId'] ??
            m['uid'] ??
            resolvedWorkspace)
        .toString()
        .trim();
    final createdByName = (m[fieldCreatedByName] ?? '').toString().trim();
    final createdByEmail = (m[fieldCreatedByEmail] ?? '').toString().trim();
    final updatedByUid =
        (m[fieldUpdatedByUid] ?? createdByUid).toString().trim();
    final updatedByName = (m[fieldUpdatedByName] ?? '').toString().trim();
    final updatedByEmail =
        (m[fieldUpdatedByEmail] ?? createdByEmail).toString().trim();
    final createdAt = _toDate(m[fieldCreatedAt]) ?? _toDate(m['createdAt']);
    final updatedAt = _toDate(m[fieldUpdatedAt]) ?? _toDate(m['updatedAt']);

    final normalizedCreatedName = await _resolveActorDisplayName(
      workspaceUid: resolvedWorkspace,
      uid: createdByUid,
      email: createdByEmail,
      preferredName: createdByName,
    );
    final normalizedUpdatedName = await _resolveActorDisplayName(
      workspaceUid: resolvedWorkspace,
      uid: updatedByUid,
      email: updatedByEmail,
      preferredName: updatedByName,
    );

    debugPrint(
      '[AuditTrace][Read] resolved workspace=$resolvedWorkspace createdByUid=$createdByUid createdByName=$normalizedCreatedName createdAt=$createdAt updatedByUid=$updatedByUid updatedByName=$normalizedUpdatedName updatedAt=$updatedAt',
    );

    return EntityAuditInfo(
      createdByName: normalizedCreatedName,
      createdByUid: createdByUid,
      createdByEmail: createdByEmail,
      createdAt: createdAt,
      updatedByName: normalizedUpdatedName,
      updatedByUid: updatedByUid,
      updatedByEmail: updatedByEmail,
      updatedAt: updatedAt,
      source: 'remote',
    );
  }

  Future<EntityAuditInfo?> loadLocalEntityAudit({
    required String workspaceUid,
    required String collectionName,
    required String entityId,
  }) async {
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final candidateWorkspaces = <String>[
      if (authUid.isNotEmpty && authUid != workspaceUid.trim()) authUid,
      workspaceUid.trim(),
    ].where((e) => e.isNotEmpty && e != 'guest').toList(growable: false);

    return _readLocalAudit(
      candidateWorkspaces: candidateWorkspaces,
      collectionName: collectionName,
      entityId: entityId,
    );
  }

  Future<_AuditActor> _resolveCurrentActor(
      {required String workspaceUid}) async {
    final u = FirebaseAuth.instance.currentUser;
    final uid = (u?.uid ?? '').trim();
    final email = (u?.email ?? '').trim();
    var name = (u?.displayName ?? '').trim();

    if (name.isEmpty) {
      final officeUserName = await _resolveOfficeUserName(
        workspaceUid: workspaceUid,
        actorUid: uid,
        actorEmail: email,
      );
      if (officeUserName.isNotEmpty) {
        name = officeUserName;
      }
    }

    if (name.isEmpty && uid.isNotEmpty) {
      try {
        final usersDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final m = usersDoc.data() ?? const <String, dynamic>{};
        name = _pickName(m).trim();
        debugPrint(
          '[AuditTrace][Actor] users/$uid exists=${usersDoc.exists} pickedName=$name',
        );
      } catch (_) {}
    }

    if (name.isEmpty && uid.isNotEmpty && uid == workspaceUid) {
      name = _managementLabel;
    }
    if (name.isEmpty) {
      name = email.isNotEmpty ? email : (uid.isNotEmpty ? uid : _unknownLabel);
    }

    return _AuditActor(uid: uid, name: name, email: email);
  }

  Future<String> _resolveActorDisplayName({
    required String workspaceUid,
    required String uid,
    required String email,
    required String preferredName,
  }) async {
    final directName = preferredName.trim();
    if (directName.isNotEmpty) return directName;

    final actorUid = uid.trim();
    final actorEmail = email.trim().toLowerCase();
    final ws = workspaceUid.trim();

    if (actorUid.isNotEmpty && ws.isNotEmpty && actorUid == ws) {
      return _managementLabel;
    }

    final officeUserName = await _resolveOfficeUserName(
      workspaceUid: ws,
      actorUid: actorUid,
      actorEmail: actorEmail,
    );
    if (officeUserName.isNotEmpty) return officeUserName;

    if (actorUid.isNotEmpty) {
      try {
        final usersDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(actorUid)
            .get();
        if (usersDoc.exists) {
          final usersName =
              _pickName(usersDoc.data() ?? const <String, dynamic>{});
          if (usersName.isNotEmpty) return usersName;
        }
      } catch (_) {}
    }

    if (actorEmail.isNotEmpty) return actorEmail;
    if (actorUid.isNotEmpty) return actorUid;
    return _unknownLabel;
  }

  Future<String> _resolveOfficeUserName({
    required String workspaceUid,
    required String actorUid,
    required String actorEmail,
  }) async {
    final ws = workspaceUid.trim();
    final uid = actorUid.trim();
    final email = actorEmail.trim().toLowerCase();
    if (ws.isEmpty || ws == 'guest') return '';

    final cacheKey = '$ws|$uid|$email';
    final cached = _officeUserNameCache[cacheKey];
    if (cached != null) return cached;

    final clientsRef = FirebaseFirestore.instance
        .collection('offices')
        .doc(ws)
        .collection('clients');

    String resolved = '';
    try {
      if (uid.isNotEmpty) {
        final direct = await clientsRef.doc(uid).get();
        if (direct.exists) {
          resolved = _pickName(direct.data() ?? const <String, dynamic>{});
        }
      }
    } catch (_) {}

    if (resolved.isEmpty && uid.isNotEmpty) {
      try {
        final byUid =
            await clientsRef.where('uid', isEqualTo: uid).limit(1).get();
        if (byUid.docs.isNotEmpty) {
          resolved = _pickName(byUid.docs.first.data());
        }
      } catch (_) {}
    }

    if (resolved.isEmpty && email.isNotEmpty) {
      try {
        final byEmail =
            await clientsRef.where('email', isEqualTo: email).limit(1).get();
        if (byEmail.docs.isNotEmpty) {
          resolved = _pickName(byEmail.docs.first.data());
        }
      } catch (_) {}
    }

    _officeUserNameCache[cacheKey] = resolved;
    return resolved;
  }

  String _pickName(Map<String, dynamic> m) {
    const keys = <String>[
      'displayName',
      'fullName',
      'name',
      'username',
      'userName',
    ];
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Future<EntityAuditInfo?> _readLocalAudit({
    required List<String> candidateWorkspaces,
    required String collectionName,
    required String entityId,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final ws in candidateWorkspaces) {
        final key = _localCacheKey(ws, collectionName, entityId);
        final raw = sp.getString(key);
        final m = _decodeMap(raw);
        if (m.isEmpty) continue;
        final createdByUid = (m[fieldCreatedByUid] ?? '').toString().trim();
        final createdByName = (m[fieldCreatedByName] ?? '').toString().trim();
        final createdByEmail = (m[fieldCreatedByEmail] ?? '').toString().trim();
        final updatedByUid = (m[fieldUpdatedByUid] ?? '').toString().trim();
        final updatedByName = (m[fieldUpdatedByName] ?? '').toString().trim();
        final updatedByEmail = (m[fieldUpdatedByEmail] ?? '').toString().trim();
        final createdAt = _toDate(m[fieldCreatedAt]);
        final updatedAt = _toDate(m[fieldUpdatedAt]);
        final normalizedCreatedName = await _resolveActorDisplayName(
          workspaceUid: ws,
          uid: createdByUid,
          email: createdByEmail,
          preferredName: createdByName,
        );
        final normalizedUpdatedName = await _resolveActorDisplayName(
          workspaceUid: ws,
          uid: updatedByUid,
          email: updatedByEmail,
          preferredName: updatedByName,
        );
        return EntityAuditInfo(
          createdByName: normalizedCreatedName,
          createdByUid: createdByUid,
          createdByEmail: createdByEmail,
          createdAt: createdAt,
          updatedByName: normalizedUpdatedName,
          updatedByUid: updatedByUid,
          updatedByEmail: updatedByEmail,
          updatedAt: updatedAt,
          source: 'local-cache',
        );
      }
    } catch (_) {}
    return null;
  }

  Future<EntityAuditInfo?> _buildSynthesizedAudit({
    required String workspaceUid,
    required String authUid,
    required String entityId,
  }) async {
    final derivedAt = _deriveDateFromEntityId(entityId);
    if (derivedAt == null) return null;
    final actor = await _resolveCurrentActor(
      workspaceUid: workspaceUid.trim().isNotEmpty ? workspaceUid : authUid,
    );
    final ownerUid =
        workspaceUid.trim().isNotEmpty ? workspaceUid.trim() : authUid;
    final ownerName = await _resolveActorDisplayName(
      workspaceUid: ownerUid,
      uid: ownerUid,
      email: actor.email,
      preferredName: '',
    );
    return EntityAuditInfo(
      createdByName: ownerName,
      createdByUid: ownerUid,
      createdByEmail: actor.email,
      createdAt: derivedAt,
      updatedByName: ownerName,
      updatedByUid: ownerUid,
      updatedByEmail: actor.email,
      updatedAt: derivedAt,
      source: 'synth',
    );
  }

  DateTime? _deriveDateFromEntityId(String entityId) {
    final n = int.tryParse(entityId.trim());
    if (n == null || n <= 0) return null;
    // Common IDs in this app are epoch-based (microseconds or milliseconds).
    if (n >= 1000000000000000) {
      return DateTime.fromMicrosecondsSinceEpoch(n);
    }
    if (n >= 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    if (n >= 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    return null;
  }

  String _localCacheKey(
      String workspaceUid, String collectionName, String entityId) {
    return 'audit_cache::${workspaceUid.trim()}::${collectionName.trim()}::${entityId.trim()}';
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) {
        return v.map((k, value) => MapEntry(k.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _encodeMap(Map<String, dynamic> m) {
    try {
      return jsonEncode(m);
    } catch (_) {
      return '{}';
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
