import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/tenant.dart';
import '../constants/boxes.dart' as bx;
import 'user_scope.dart' as scope;

class OfficePackageSnapshot {
  final String packageId;
  final String name;
  final int? officeUsersLimit;
  final bool officeUsersUnlimited;
  final int? clientsLimit;
  final bool clientsUnlimited;
  final int? propertiesLimit;
  final bool propertiesUnlimited;
  final num? monthlyPrice;
  final num? yearlyPrice;
  final bool isActive;

  const OfficePackageSnapshot({
    required this.packageId,
    required this.name,
    required this.officeUsersLimit,
    required this.officeUsersUnlimited,
    required this.clientsLimit,
    required this.clientsUnlimited,
    required this.propertiesLimit,
    required this.propertiesUnlimited,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.isActive,
  });

  bool get hasAnyData =>
      packageId.isNotEmpty ||
      name.isNotEmpty ||
      officeUsersLimit != null ||
      clientsLimit != null ||
      propertiesLimit != null ||
      officeUsersUnlimited ||
      clientsUnlimited ||
      propertiesUnlimited;

  String displayLimit({
    required int? value,
    required bool unlimited,
  }) {
    if (unlimited) return 'غير محدود';
    if (value == null) return 'غير محدد';
    return value.toString();
  }

  String get officeUsersDisplay => displayLimit(
        value: officeUsersLimit,
        unlimited: officeUsersUnlimited,
      );

  String get clientsDisplay => displayLimit(
        value: clientsLimit,
        unlimited: clientsUnlimited,
      );

  String get propertiesDisplay => displayLimit(
        value: propertiesLimit,
        unlimited: propertiesUnlimited,
      );

  static const OfficePackageSnapshot _demoUnlimited = OfficePackageSnapshot(
    packageId: 'demo_unlimited',
    name: 'تجريبي',
    officeUsersLimit: null,
    officeUsersUnlimited: true,
    clientsLimit: null,
    clientsUnlimited: true,
    propertiesLimit: null,
    propertiesUnlimited: true,
    monthlyPrice: null,
    yearlyPrice: null,
    isActive: true,
  );

  static OfficePackageSnapshot? fromUserDoc(Map<String, dynamic> data) {
    if (_isDemoOfficeDocument(data)) return _demoUnlimited;

    final snapshot = _asMap(data['packageSnapshot']) ??
        _asMap(data['package_snapshot']) ??
        const <String, dynamic>{};
    final limits = _asMap(snapshot['limits']) ?? const <String, dynamic>{};
    final pricing = _asMap(snapshot['pricing']) ?? const <String, dynamic>{};

    final packageId = _string(
      data['packageId'] ?? data['package_id'] ?? snapshot['packageId'],
    );
    final name = _string(
      snapshot['name'] ?? snapshot['packageName'] ?? data['packageName'],
    );

    final officeUsersUnlimited = _bool(
      limits['officeUsersUnlimited'] ??
          snapshot['officeUsersUnlimited'] ??
          snapshot['usersUnlimited'],
    );
    final clientsUnlimited = _bool(
      limits['clientsUnlimited'] ??
          snapshot['clientsUnlimited'] ??
          snapshot['tenantsUnlimited'],
    );
    final propertiesUnlimited = _bool(
      limits['propertiesUnlimited'] ??
          snapshot['propertiesUnlimited'] ??
          snapshot['unitsUnlimited'],
    );

    final officeUsersLimit = _int(
      limits['officeUsers'] ??
          limits['users'] ??
          snapshot['officeUsersLimit'] ??
          snapshot['usersLimit'],
    );
    final clientsLimit = _int(
      limits['clients'] ??
          limits['tenants'] ??
          snapshot['clientsLimit'] ??
          snapshot['tenantsLimit'],
    );
    final propertiesLimit = _int(
      limits['properties'] ??
          snapshot['propertiesLimit'] ??
          snapshot['unitsLimit'],
    );

    final monthlyPrice = _num(
      pricing['monthly'] ?? snapshot['monthlyPrice'] ?? snapshot['monthly'],
    );
    final yearlyPrice = _num(
      pricing['yearly'] ?? snapshot['yearlyPrice'] ?? snapshot['yearly'],
    );
    final isActive =
        snapshot.containsKey('isActive') ? _bool(snapshot['isActive']) : true;

    final parsed = OfficePackageSnapshot(
      packageId: packageId,
      name: name,
      officeUsersLimit: officeUsersLimit,
      officeUsersUnlimited: officeUsersUnlimited,
      clientsLimit: clientsLimit,
      clientsUnlimited: clientsUnlimited,
      propertiesLimit: propertiesLimit,
      propertiesUnlimited: propertiesUnlimited,
      monthlyPrice: monthlyPrice,
      yearlyPrice: yearlyPrice,
      isActive: isActive,
    );

    return parsed.hasAnyData ? parsed : null;
  }

  static bool _isDemoOfficeDocument(Map<String, dynamic> data) {
    final isDemo = _bool(data['isDemo']);
    final duration = _string(data['duration']).toLowerCase();
    if (!isDemo && duration != 'demo3d') return false;

    final role = _string(data['role']).toLowerCase();
    final entityType = _string(data['entityType']).toLowerCase();
    final accountType = _string(data['accountType']).toLowerCase();
    final targetRole = _string(data['targetRole']).toLowerCase();
    final hasOwnerMarker =
        _string(data['ownerUid']).isNotEmpty || _string(data['ownerId']).isNotEmpty;
    final looksLikeOffice = role == 'office' ||
        entityType == 'office' ||
        accountType == 'office_owner' ||
        targetRole == 'office' ||
        hasOwnerMarker;
    final looksLikeOfficeClient = role == 'client' ||
        entityType == 'office_client' ||
        accountType == 'office_client' ||
        _bool(data['is_office_client']);
    return looksLikeOffice && !looksLikeOfficeClient;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return null;
  }

  static String _string(dynamic value) {
    return (value ?? '').toString().trim();
  }

  static bool _bool(dynamic value) {
    return value == true;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static num? _num(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().trim());
  }
}

class PackageLimitDecision {
  final bool allowed;
  final String? message;
  final int used;
  final int? limit;
  final OfficePackageSnapshot? packageSnapshot;

  const PackageLimitDecision({
    required this.allowed,
    required this.message,
    required this.used,
    required this.limit,
    required this.packageSnapshot,
  });
}

class _ResolvedPackageContext {
  final String officeUid;
  final OfficePackageSnapshot? snapshot;

  const _ResolvedPackageContext({
    required this.officeUid,
    required this.snapshot,
  });
}

class PackageLimitService {
  static const String _sessionBoxName = 'sessionBox';
  static const String _pkgCachePrefix = 'pkg_ctx_';

  static String? currentOfficeWorkspaceUid() {
    final scopedUid = scope.effectiveUid();
    if (scopedUid.isNotEmpty && scopedUid != 'guest') {
      return scopedUid;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static Future<OfficePackageSnapshot?> getCurrentOfficePackage() async {
    final context = await _loadPackageContext();
    return context?.snapshot;
  }

  static Future<PackageLimitDecision> canAddOfficeUser() async {
    try {
      final context = await _loadPackageContext();
      final snapshot = context?.snapshot;
      if (snapshot == null ||
          snapshot.officeUsersUnlimited ||
          snapshot.officeUsersLimit == null) {
        return PackageLimitDecision(
          allowed: true,
          message: null,
          used: 0,
          limit: snapshot?.officeUsersLimit,
          packageSnapshot: snapshot,
        );
      }

      final used = await _countOfficeUsers(context!.officeUid);
      final limit = snapshot.officeUsersLimit!;
      final allowed = used < limit;
      return PackageLimitDecision(
        allowed: allowed,
        message:
            allowed ? null : _limitReachedMessage('Ù…Ø³ØªØ®Ø¯Ù… Ù…ÙƒØªØ¨', snapshot.name),
        used: used,
        limit: limit,
        packageSnapshot: snapshot,
      );
    } catch (_) {
      return const PackageLimitDecision(
        allowed: true,
        message: null,
        used: 0,
        limit: null,
        packageSnapshot: null,
      );
    }
  }

  static Future<PackageLimitDecision> canAddOfficeClient() async {
    try {
      final context = await _loadPackageContext();
      final snapshot = context?.snapshot;
      if (snapshot == null ||
          snapshot.clientsUnlimited ||
          snapshot.clientsLimit == null) {
        return PackageLimitDecision(
          allowed: true,
          message: null,
          used: 0,
          limit: snapshot?.clientsLimit,
          packageSnapshot: snapshot,
        );
      }

      final used = await _countOfficeClients(context!.officeUid);
      final limit = snapshot.clientsLimit!;
      final allowed = used < limit;
      return PackageLimitDecision(
        allowed: allowed,
        message: allowed
            ? null
            : _limitReachedMessage('Ø¹Ù…ÙŠÙ„ Ù„ÙˆØ­Ø© Ø§Ù„Ù…ÙƒØªØ¨', snapshot.name),
        used: used,
        limit: limit,
        packageSnapshot: snapshot,
      );
    } catch (_) {
      return const PackageLimitDecision(
        allowed: true,
        message: null,
        used: 0,
        limit: null,
        packageSnapshot: null,
      );
    }
  }

  static Future<PackageLimitDecision> canAddProperty() async {
    try {
      final context = await _loadPackageContext();
      final snapshot = context?.snapshot;
      if (snapshot == null ||
          snapshot.propertiesUnlimited ||
          snapshot.propertiesLimit == null) {
        return PackageLimitDecision(
          allowed: true,
          message: null,
          used: 0,
          limit: snapshot?.propertiesLimit,
          packageSnapshot: snapshot,
        );
      }

      final used = _countTopLevelProperties();
      final limit = snapshot.propertiesLimit!;
      final allowed = used < limit;
      return PackageLimitDecision(
        allowed: allowed,
        message: allowed ? null : _limitReachedMessage('Ø¹Ù‚Ø§Ø±', snapshot.name),
        used: used,
        limit: limit,
        packageSnapshot: snapshot,
      );
    } catch (_) {
      return const PackageLimitDecision(
        allowed: true,
        message: null,
        used: 0,
        limit: null,
        packageSnapshot: null,
      );
    }
  }

  static Future<PackageLimitDecision> canAddClient() async {
    return const PackageLimitDecision(
      allowed: true,
      message: null,
      used: 0,
      limit: null,
      packageSnapshot: null,
    );
  }

  static String _limitReachedMessage(String entityLabel, String packageName) {
    final planPart =
        packageName.trim().isEmpty ? '' : ' ÙÙŠ Ø§Ù„Ø¨Ø§Ù‚Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ© ($packageName)';
    return 'Ù„Ø§ ÙŠÙ…ÙƒÙ† Ø¥Ø¶Ø§ÙØ© $entityLabel Ø¬Ø¯ÙŠØ¯ØŒ Ù„Ù‚Ø¯ ÙˆØµÙ„Øª Ø¥Ù„Ù‰ Ø§Ù„Ø­Ø¯ Ø§Ù„Ø£Ù‚ØµÙ‰ Ø§Ù„Ù…Ø³Ù…ÙˆØ­$planPart.';
  }

  static Future<_ResolvedPackageContext?> _loadPackageContext() async {
    final workspaceUid = currentOfficeWorkspaceUid();
    if (workspaceUid == null || workspaceUid.isEmpty) return null;

    final cachedContext = await _readCachedPackageContext(workspaceUid);

    final users = FirebaseFirestore.instance.collection('users');
    final offices = FirebaseFirestore.instance.collection('offices');

    final workspaceUserData = await _readDocData(users.doc(workspaceUid));
    final workspaceUserSnapshot = await _resolveSnapshotFromDocData(
      workspaceUserData,
    );
    if (workspaceUserSnapshot != null) {
      final context = _ResolvedPackageContext(
        officeUid: workspaceUid,
        snapshot: workspaceUserSnapshot,
      );
      await _writeCachedPackageContext(workspaceUid, context);
      return context;
    }

    final workspaceOfficeData = await _readDocData(offices.doc(workspaceUid));
    final workspaceOfficeSnapshot = await _resolveSnapshotFromDocData(
      workspaceOfficeData,
    );
    if (workspaceOfficeSnapshot != null) {
      final context = _ResolvedPackageContext(
        officeUid: workspaceUid,
        snapshot: workspaceOfficeSnapshot,
      );
      await _writeCachedPackageContext(workspaceUid, context);
      return context;
    }

    final ownerOfficeUid = _extractOfficeUid(
      workspaceUserData,
      workspaceOfficeData,
    );
    if (ownerOfficeUid == null || ownerOfficeUid.isEmpty) {
      return cachedContext ??
          _ResolvedPackageContext(
        officeUid: workspaceUid,
        snapshot: null,
      );
    }

    final ownerUserData = await _readDocData(users.doc(ownerOfficeUid));
    final ownerUserSnapshot = await _resolveSnapshotFromDocData(ownerUserData);
    if (ownerUserSnapshot != null) {
      final context = _ResolvedPackageContext(
        officeUid: ownerOfficeUid,
        snapshot: ownerUserSnapshot,
      );
      await _writeCachedPackageContext(workspaceUid, context);
      return context;
    }

    final ownerOfficeData = await _readDocData(offices.doc(ownerOfficeUid));
    final ownerOfficeSnapshot = await _resolveSnapshotFromDocData(
      ownerOfficeData,
    );
    final context = _ResolvedPackageContext(
      officeUid: ownerOfficeUid,
      snapshot: ownerOfficeSnapshot,
    );
    await _writeCachedPackageContext(workspaceUid, context);
    return context.snapshot != null ? context : cachedContext ?? context;
  }

  static Future<Map<String, dynamic>> _readDocData(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      return snap.data() ?? const <String, dynamic>{};
    } on TimeoutException {
      try {
        final snap = await ref.get(const GetOptions(source: Source.cache));
        return snap.data() ?? const <String, dynamic>{};
      } catch (_) {
        return const <String, dynamic>{};
      }
    } catch (_) {
      try {
        final snap = await ref.get(const GetOptions(source: Source.cache));
        return snap.data() ?? const <String, dynamic>{};
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
  }

  static String? _extractOfficeUid(
    Map<String, dynamic> primary, [
    Map<String, dynamic> secondary = const <String, dynamic>{},
  ]) {
    for (final source in <Map<String, dynamic>>[primary, secondary]) {
      final raw = (source['officeId'] ??
              source['office_id'] ??
              source['ownerUid'] ??
              source['ownerId'] ??
              source['createdBy'] ??
              '')
          .toString()
          .trim();
      if (raw.isNotEmpty) return raw;
    }
    return null;
  }

  static Future<int> _countOfficeUsers(String officeUid) async {
    final ref = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeUid)
        .collection('clients');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      snap = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snap = await ref.get(const GetOptions(source: Source.cache));
    }

    var count = 0;
    for (final doc in snap.docs) {
      if (_isOfficeUserDoc(doc.data())) {
        count += 1;
      }
    }
    return count;
  }

  static Future<int> _countOfficeClients(String officeUid) async {
    final ref = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeUid)
        .collection('clients');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      snap = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snap = await ref.get(const GetOptions(source: Source.cache));
    }

    var count = 0;
    for (final doc in snap.docs) {
      if (_isOfficeManagedClientDoc(doc.data())) {
        count += 1;
      }
    }
    return count;
  }

  static bool _isOfficeUserDoc(Map<String, dynamic> m) {
    final role = (m['role'] ?? '').toString().trim().toLowerCase();
    final entityType = (m['entityType'] ?? '').toString().trim().toLowerCase();
    final accountType =
        (m['accountType'] ?? '').toString().trim().toLowerCase();
    final targetRole = (m['targetRole'] ?? '').toString().trim().toLowerCase();
    final officePermission =
        (m['officePermission'] ?? '').toString().trim().toLowerCase();
    final permission = (m['permission'] ?? '').toString().trim().toLowerCase();
    return role == 'office_staff' ||
        entityType == 'office_user' ||
        accountType == 'office_staff' ||
        targetRole == 'office' ||
        officePermission == 'full' ||
        officePermission == 'view' ||
        permission == 'full' ||
        permission == 'view';
  }

  static bool _isOfficeManagedClientDoc(Map<String, dynamic> m) {
    if (_isOfficeUserDoc(m)) return false;
    final role = (m['role'] ?? '').toString().trim().toLowerCase();
    final entityType = (m['entityType'] ?? '').toString().trim().toLowerCase();
    final accountType =
        (m['accountType'] ?? '').toString().trim().toLowerCase();
    final targetRole = (m['targetRole'] ?? '').toString().trim().toLowerCase();
    return role == 'client' ||
        entityType == 'office_client' ||
        accountType == 'office_client' ||
        targetRole == 'client' ||
        m['is_office_client'] == true;
  }

  static int _countTopLevelProperties() {
    final name = scope.boxName(bx.kPropertiesBox);
    if (!Hive.isBoxOpen(name)) return 0;
    final box = Hive.box<Property>(name);
    return box.values.where((item) => item.parentBuildingId == null).length;
  }

  static int _countClients() {
    final name = scope.boxName(bx.kTenantsBox);
    if (!Hive.isBoxOpen(name)) return 0;
    final box = Hive.box<Tenant>(name);
    return box.values.length;
  }

  static Future<OfficePackageSnapshot?> _resolveSnapshotFromDocData(
    Map<String, dynamic> docData,
  ) async {
    final direct = OfficePackageSnapshot.fromUserDoc(docData);
    if (_hasResolvedLimits(direct)) return direct;

    final packageId = _normalizePackageId(
      docData['packageId'] ??
          docData['package_id'] ??
          (docData['packageSnapshot'] is Map
              ? (docData['packageSnapshot'] as Map)['packageId']
              : null),
    );
    if (packageId.isEmpty) return direct;

    final packageData = await _readDocData(
      FirebaseFirestore.instance.collection('packages').doc(packageId),
    );
    if (packageData.isEmpty) return direct;

    final merged = <String, dynamic>{
      ...docData,
      'packageId': packageId,
      'packageSnapshot': <String, dynamic>{
        'packageId': packageId,
        ...packageData,
      },
    };
    final resolved = OfficePackageSnapshot.fromUserDoc(merged);
    return resolved ?? direct;
  }

  static bool _hasResolvedLimits(OfficePackageSnapshot? snapshot) {
    if (snapshot == null) return false;
    return snapshot.officeUsersUnlimited ||
        snapshot.clientsUnlimited ||
        snapshot.propertiesUnlimited ||
        snapshot.officeUsersLimit != null ||
        snapshot.clientsLimit != null ||
        snapshot.propertiesLimit != null;
  }

  static String _normalizePackageId(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final lower = raw.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || lower == 'nan') {
      return '';
    }
    return raw;
  }

  static Future<Box> _sessionBox() async {
    if (Hive.isBoxOpen(_sessionBoxName)) return Hive.box(_sessionBoxName);
    return Hive.openBox(_sessionBoxName);
  }

  static String _packageCacheKey(String workspaceUid) =>
      '$_pkgCachePrefix${workspaceUid.trim()}';

  static Future<void> _writeCachedPackageContext(
    String workspaceUid,
    _ResolvedPackageContext context,
  ) async {
    final snapshot = context.snapshot;
    if (snapshot == null) return;
    try {
      final box = await _sessionBox();
      await box.put(_packageCacheKey(workspaceUid), <String, dynamic>{
        'officeUid': context.officeUid,
        'cachedAt': DateTime.now().toIso8601String(),
        'doc': <String, dynamic>{
          'packageId': snapshot.packageId,
          'packageName': snapshot.name,
          'packageSnapshot': <String, dynamic>{
            'packageId': snapshot.packageId,
            'name': snapshot.name,
            'isActive': snapshot.isActive,
            'limits': <String, dynamic>{
              'officeUsersUnlimited': snapshot.officeUsersUnlimited,
              'clientsUnlimited': snapshot.clientsUnlimited,
              'propertiesUnlimited': snapshot.propertiesUnlimited,
              'officeUsers': snapshot.officeUsersLimit,
              'clients': snapshot.clientsLimit,
              'properties': snapshot.propertiesLimit,
            },
            'pricing': <String, dynamic>{
              'monthly': snapshot.monthlyPrice,
              'yearly': snapshot.yearlyPrice,
            },
          },
        },
      });
    } catch (_) {}
  }

  static Future<_ResolvedPackageContext?> _readCachedPackageContext(
    String workspaceUid,
  ) async {
    try {
      final box = await _sessionBox();
      final raw = box.get(_packageCacheKey(workspaceUid));
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final officeUid = (map['officeUid'] ?? '').toString().trim();
      final docRaw = map['doc'];
      if (docRaw is! Map) return null;
      final doc = Map<String, dynamic>.from(docRaw);
      final snapshot = OfficePackageSnapshot.fromUserDoc(doc);
      if (snapshot == null) return null;
      return _ResolvedPackageContext(
        officeUid: officeUid.isEmpty ? workspaceUid : officeUid,
        snapshot: snapshot,
      );
    } catch (_) {
      return null;
    }
  }
}
