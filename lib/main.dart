// lib/main.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase (Ã™â€žÃ™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€  Ã™Ë†Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â²Ã˜Â§Ã™â€¦Ã™â€ Ã˜Â© Ã™Ë†Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Data / Repos / Sync
import 'data/constants/boxes.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/hive_service.dart';
import 'data/services/user_scope.dart';
import 'data/sync/sync_bridge.dart';
import 'data/services/offline_sync_service.dart';
import 'data/services/firestore_user_collections.dart';
import 'data/repos/tenants_repo.dart';

// Models
import 'models/property.dart';
import 'models/tenant.dart';

// Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€šÃ™Ë†Ã˜Â¯
import 'ui/contracts_screen.dart'
    show Contract, ContractAdapter, AddOrEditContractScreen;
import 'ui/contracts_screen.dart' as contracts_ui show ContractsScreen;

// Ã˜Â§Ã™â€žÃ™ÂÃ™Ë†Ã˜Â§Ã˜ÂªÃ™Å Ã˜Â±
import 'ui/invoices_screen.dart' show Invoice, InvoiceAdapter, InvoicesRoutes;

// Ã˜Â§Ã™â€žÃ˜ÂµÃ™Å Ã˜Â§Ã™â€ Ã˜Â©
import 'ui/maintenance_screen.dart'
    show
        MaintenanceRequest,
        MaintenanceRequestAdapter,
        MaintenancePriorityAdapter,
        MaintenanceStatusAdapter,
        MaintenanceRoutes;

// Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ˜Â§Ã˜Â±Ã™Å Ã˜Â±
import 'ui/reports_screen.dart' show ReportsRoutes;
import 'ui/property_services_screen.dart' show PropertyServicesRoutes;
import 'ui/notifications_screen.dart' show NotificationsRoutes;

// UI
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'widgets/disabled_account_guard.dart';
import 'ui/ai_chat/ai_chat_service.dart';

//Ã™â€žÃ™Ë†Ã˜Â­Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã™Æ’Ã˜ÂªÃ˜Â¨
import 'screens/office/office.dart';

// Ã˜Â®Ã™â€žÃ™ÂÃ™Å Ã˜Â© Ã˜Â¹Ã˜Â§Ã™â€¦Ã˜Â© Ã™ÂÃ˜Â§Ã˜ÂªÃ˜Â­Ã˜Â© (Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â¬Ã˜Â¹Ã™â€žÃ™â€¡Ã˜Â§ Ã˜Â³Ã™Ë†Ã˜Â¯Ã˜Â§Ã˜Â¡ Ã˜Â­Ã˜ÂªÃ™â€° Ã™â€žÃ˜Â§ Ã˜ÂªÃ˜ÂªÃ˜Â£Ã˜Â«Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â§Ã˜Â´Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â§Ã˜Â®Ã™â€žÃ™Å Ã˜Â© Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â±)
const Color kRouteBg = Color(0xFFF8FAFC);
const Color kBrandPrimary = Color(0xFF0F766E);
const Color kBrandSecondary = Color(0xFF4F46E5);
const Color kBrandDark = Color(0xFF0F172A);
const Color kBrandAccent = Color(0xFF5EEAD4);

// Ã™Å Ã˜Â¬Ã˜Â¹Ã™â€ž Ã˜Â§Ã™â€ Ã˜ÂªÃ™â€šÃ˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â§Ã˜Âª Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã˜Â£Ã™Å  Ã˜Â£Ã™â€ Ã™Å Ã™â€¦Ã™Å Ã˜Â´Ã™â€
class NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â£Ã™Å  Ã˜Â­Ã˜Â±Ã™Æ’Ã˜Â©
  }
}

// ... (rest of imports)

// REMOVED SaTime class as it is replaced by KsaTime in utils/ksa_time.dart

bool __isOfficeStaffMarker(Map<String, dynamic> m) {
  final role = (m['role'] ?? '').toString().toLowerCase();
  final accountType = (m['accountType'] ?? '').toString().toLowerCase();
  final entityType = (m['entityType'] ?? '').toString().toLowerCase();
  final targetRole = (m['targetRole'] ?? '').toString().toLowerCase();
  final officePermission =
      (m['officePermission'] ?? '').toString().toLowerCase();
  final permission = (m['permission'] ?? '').toString().toLowerCase();
  return role == 'office_staff' ||
      accountType == 'office_staff' ||
      entityType == 'office_user' ||
      targetRole == 'office' ||
      officePermission == 'full' ||
      officePermission == 'view' ||
      permission == 'full' ||
      permission == 'view';
}

bool __isExplicitOfficeClientMarker(Map<String, dynamic> m) {
  if (__isOfficeStaffMarker(m)) return false;
  final origin = (m['origin'] ?? '').toString().toLowerCase();
  final accountType = (m['accountType'] ?? '').toString().toLowerCase();
  final entityType = (m['entityType'] ?? '').toString().toLowerCase();
  final targetRole = (m['targetRole'] ?? '').toString().toLowerCase();

  return m['is_office_client'] == true ||
      origin == 'officeclient' ||
      accountType == 'office_client' ||
      entityType == 'office_client' ||
      targetRole == 'client';
}

String __traceNowIso() => DateTime.now().toIso8601String();

String __compactStackTrace(StackTrace stackTrace, [int maxLines = 3]) {
  return stackTrace
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(maxLines)
      .join(' | ');
}

void __traceWorkspace(String message) {
  debugPrint('[WorkspaceTrace][${__traceNowIso()}][Main] $message');
}

String __scopedBoxName(String base, String uid) => '${base}_$uid';

Tenant __cloneTenantForRecovery(Tenant t) {
  return Tenant(
    id: t.id,
    fullName: t.fullName,
    nationalId: t.nationalId,
    phone: t.phone,
    email: t.email,
    dateOfBirth: t.dateOfBirth,
    nationality: t.nationality,
    idExpiry: t.idExpiry,
    addressLine: t.addressLine,
    city: t.city,
    region: t.region,
    postalCode: t.postalCode,
    emergencyName: t.emergencyName,
    emergencyPhone: t.emergencyPhone,
    notes: t.notes,
    tags: List<String>.from(t.tags),
    clientType: t.clientType,
    tenantBankName: t.tenantBankName,
    tenantBankAccountNumber: t.tenantBankAccountNumber,
    tenantTaxNumber: t.tenantTaxNumber,
    companyName: t.companyName,
    companyCommercialRegister: t.companyCommercialRegister,
    companyTaxNumber: t.companyTaxNumber,
    companyRepresentativeName: t.companyRepresentativeName,
    companyRepresentativePhone: t.companyRepresentativePhone,
    companyBankAccountNumber: t.companyBankAccountNumber,
    companyBankName: t.companyBankName,
    serviceSpecialization: t.serviceSpecialization,
    attachmentPaths: List<String>.from(t.attachmentPaths),
    isArchived: t.isArchived,
    isBlacklisted: t.isBlacklisted,
    blacklistReason: t.blacklistReason,
    activeContractsCount: t.activeContractsCount,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
  );
}

Property __clonePropertyForRecovery(Property p) {
  return Property(
    id: p.id,
    name: p.name,
    type: p.type,
    address: p.address,
    price: p.price,
    currency: p.currency,
    rooms: p.rooms,
    area: p.area,
    floors: p.floors,
    totalUnits: p.totalUnits,
    occupiedUnits: p.occupiedUnits,
    rentalMode: p.rentalMode,
    parentBuildingId: p.parentBuildingId,
    description: p.description,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
    isArchived: p.isArchived,
    documentType: p.documentType,
    documentNumber: p.documentNumber,
    documentDate: p.documentDate,
    documentAttachmentPath: p.documentAttachmentPath,
    documentAttachmentPaths: p.documentAttachmentPaths == null
        ? null
        : List<String>.from(p.documentAttachmentPaths!),
    electricityNumber: p.electricityNumber,
    electricityMode: p.electricityMode,
    electricityShare: p.electricityShare,
    waterNumber: p.waterNumber,
    waterMode: p.waterMode,
    waterShare: p.waterShare,
    waterAmount: p.waterAmount,
  );
}

dynamic __deepCopyDynamic(dynamic v) {
  if (v is Map) {
    return v.map((key, value) => MapEntry(key, __deepCopyDynamic(value)));
  }
  if (v is List) {
    return v.map(__deepCopyDynamic).toList();
  }
  if (v is Set) {
    return v.map(__deepCopyDynamic).toSet();
  }
  return v;
}

Future<void> __migrateTenantsLocalBox({
  required String fromUid,
  required String toUid,
}) async {
  final fromName = __scopedBoxName(kTenantsBox, fromUid);
  final toName = __scopedBoxName(kTenantsBox, toUid);
  if (fromName == toName) return;
  try {
    final from = await Hive.openBox<Tenant>(fromName);
    final to = await Hive.openBox<Tenant>(toName);
    var moved = 0;
    for (final key in from.keys) {
      final oldVal = from.get(key);
      if (oldVal == null) continue;
      final incoming = __cloneTenantForRecovery(oldVal);
      final existing = to.get(key);
      if (existing == null || incoming.updatedAt.isAfter(existing.updatedAt)) {
        await to.put(key, incoming);
        moved++;
      }
    }
    __traceWorkspace(
        'recover-local tenants from=$fromUid to=$toUid moved=$moved');
  } catch (e) {
    __traceWorkspace('recover-local tenants failed from=$fromUid err=$e');
  }
}

Future<void> __migratePropertiesLocalBox({
  required String fromUid,
  required String toUid,
}) async {
  final fromName = __scopedBoxName(kPropertiesBox, fromUid);
  final toName = __scopedBoxName(kPropertiesBox, toUid);
  if (fromName == toName) return;
  try {
    final from = await Hive.openBox<Property>(fromName);
    final to = await Hive.openBox<Property>(toName);
    var moved = 0;
    for (final key in from.keys) {
      final oldVal = from.get(key);
      if (oldVal == null) continue;
      final incoming = __clonePropertyForRecovery(oldVal);
      final existing = to.get(key);
      final incomingAt = incoming.updatedAt ??
          incoming.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final existingAt = existing == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : (existing.updatedAt ??
              existing.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0));
      if (existing == null || incomingAt.isAfter(existingAt)) {
        await to.put(key, incoming);
        moved++;
      }
    }
    __traceWorkspace(
      'recover-local properties from=$fromUid to=$toUid moved=$moved',
    );
  } catch (e) {
    __traceWorkspace('recover-local properties failed from=$fromUid err=$e');
  }
}

Future<void> __migrateDynamicLocalBox({
  required String base,
  required String fromUid,
  required String toUid,
}) async {
  final fromName = __scopedBoxName(base, fromUid);
  final toName = __scopedBoxName(base, toUid);
  if (fromName == toName) return;
  try {
    final from = await Hive.openBox(fromName);
    final to = await Hive.openBox(toName);
    var moved = 0;
    for (final key in from.keys) {
      if (to.containsKey(key)) continue;
      final val = from.get(key);
      await to.put(key, __deepCopyDynamic(val));
      moved++;
    }
    if (moved > 0) {
      __traceWorkspace(
          'recover-local box=$base from=$fromUid to=$toUid moved=$moved');
    }
  } catch (e) {
    __traceWorkspace('recover-local box=$base failed from=$fromUid err=$e');
  }
}

Future<Set<String>> __collectLegacyUidCandidates(
  User u,
  String targetUid,
) async {
  final out = <String>{};
  final authUid = u.uid.trim();
  final scopeUid = effectiveUid().trim();
  if (scopeUid.isNotEmpty &&
      scopeUid != 'guest' &&
      scopeUid != authUid &&
      scopeUid != targetUid) {
    out.add(scopeUid);
  }
  try {
    final sp = await SharedPreferences.getInstance();
    final email = (u.email ?? '').trim().toLowerCase();
    final prefsCandidates = <String?>[
      sp.getString('last_login_uid'),
      sp.getString('office_workspace_uid_${u.uid}'),
      if (email.isNotEmpty) sp.getString('office_workspace_email_$email'),
      if (email.isNotEmpty) sp.getString('offline_uid_$email'),
    ];
    for (final raw in prefsCandidates) {
      final c = (raw ?? '').trim();
      if (c.isEmpty || c == 'guest' || c == authUid || c == targetUid) continue;
      out.add(c);
    }
  } catch (_) {}
  return out;
}

Future<void> __recoverLocalDataFromLegacyScopes(
  User u,
  String targetUid,
) async {
  // Safety lock: do not copy local data across scopes/users.
  // Previous legacy migration could move office-local boxes into a different
  // authenticated account and cause mixed tenants/properties visibility.
  __traceWorkspace(
    'recover-local disabled target=$targetUid authUid=${u.uid} (cross-scope migration blocked)',
  );
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('last_login_uid', targetUid);
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      await sp.setString('offline_uid_$email', targetUid);
    }
  } catch (_) {}
}

const Duration __kFirestoreLookupTimeout = Duration(seconds: 6);

Future<DocumentSnapshot<Map<String, dynamic>>?> __safeDocGet(
  DocumentReference<Map<String, dynamic>> ref, {
  Duration timeout = __kFirestoreLookupTimeout,
  String traceLabel = '',
}) async {
  final sw = Stopwatch()..start();
  final label = traceLabel.trim().isEmpty ? ref.path : traceLabel.trim();
  __traceWorkspace(
    'doc-get start label=$label path=${ref.path} timeoutMs=${timeout.inMilliseconds}',
  );
  try {
    final snap =
        await ref.get(const GetOptions(source: Source.server)).timeout(timeout);
    __traceWorkspace(
      'doc-get hit source=server label=$label exists=${snap.exists} fromCache=${snap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
    );
    return snap;
  } on TimeoutException catch (e, st) {
    __traceWorkspace(
      'doc-get timeout label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
    try {
      final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
      __traceWorkspace(
        'doc-get hit source=cache-after-timeout label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return cacheSnap;
    } catch (cacheError, cacheStack) {
      __traceWorkspace(
        'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${__compactStackTrace(cacheStack)}',
      );
      return null;
    }
  } catch (e, st) {
    __traceWorkspace(
      'doc-get error label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
    try {
      final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
      __traceWorkspace(
        'doc-get hit source=cache-after-error label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return cacheSnap;
    } catch (cacheError, cacheStack) {
      __traceWorkspace(
        'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${__compactStackTrace(cacheStack)}',
      );
      return null;
    }
  }
}

Future<QuerySnapshot<Map<String, dynamic>>?> __safeQueryGet(
  Query<Map<String, dynamic>> query, {
  Duration timeout = __kFirestoreLookupTimeout,
  String traceLabel = '',
}) async {
  final sw = Stopwatch()..start();
  final label =
      traceLabel.trim().isEmpty ? query.toString() : traceLabel.trim();
  __traceWorkspace(
    'query-get start label=$label timeoutMs=${timeout.inMilliseconds}',
  );
  try {
    final snap = await query
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    __traceWorkspace(
      'query-get hit source=server label=$label docs=${snap.docs.length} fromCache=${snap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
    );
    return snap;
  } on TimeoutException catch (e, st) {
    __traceWorkspace(
      'query-get timeout label=$label +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
    try {
      final cacheSnap = await query.get(const GetOptions(source: Source.cache));
      __traceWorkspace(
        'query-get hit source=cache-after-timeout label=$label docs=${cacheSnap.docs.length} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return cacheSnap;
    } catch (cacheError, cacheStack) {
      __traceWorkspace(
        'query-get cache-failed label=$label +${sw.elapsedMilliseconds}ms err=$cacheError stack=${__compactStackTrace(cacheStack)}',
      );
      return null;
    }
  } catch (e, st) {
    __traceWorkspace(
      'query-get error label=$label +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
    try {
      final cacheSnap = await query.get(const GetOptions(source: Source.cache));
      __traceWorkspace(
        'query-get hit source=cache-after-error label=$label docs=${cacheSnap.docs.length} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return cacheSnap;
    } catch (cacheError, cacheStack) {
      __traceWorkspace(
        'query-get cache-failed label=$label +${sw.elapsedMilliseconds}ms err=$cacheError stack=${__compactStackTrace(cacheStack)}',
      );
      return null;
    }
  }
}

Future<bool> __hasOfficeStaffRecordUnderOffice(User u, String officeId) async {
  if (officeId.isEmpty) return false;
  final sw = Stopwatch()..start();
  __traceWorkspace(
    'staff-check start authUid=${u.uid} officeId=$officeId email=${u.email ?? ''}',
  );

  // Accept explicit office workspace entitlement from token claims.
  try {
    final token = await u.getIdTokenResult();
    final claims = token.claims ?? const <String, dynamic>{};
    final claimOfficeId =
        (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
    if (claimOfficeId.isNotEmpty && claimOfficeId == officeId) {
      __traceWorkspace(
        'staff-check hit source=claims officeId=$officeId +${sw.elapsedMilliseconds}ms',
      );
      return true;
    }
  } catch (e, st) {
    __traceWorkspace(
      'staff-check claims-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  // Accept explicit office workspace entitlement from users/{uid} profile.
  try {
    final userDoc = await __safeDocGet(
      FirebaseFirestore.instance.collection('users').doc(u.uid),
      traceLabel: 'staff-check users/${u.uid}',
    );
    final map = userDoc?.data() ?? const <String, dynamic>{};
    final docOfficeId =
        (map['officeId'] ?? map['office_id'] ?? '').toString().trim();
    if (docOfficeId.isNotEmpty && docOfficeId == officeId) {
      __traceWorkspace(
        'staff-check hit source=users-doc officeId=$officeId +${sw.elapsedMilliseconds}ms',
      );
      return true;
    }
  } catch (e, st) {
    __traceWorkspace(
      'staff-check users-doc-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  final ref = FirebaseFirestore.instance
      .collection('offices')
      .doc(officeId)
      .collection('clients');

  try {
    final byUidDoc = await __safeDocGet(
      ref.doc(u.uid),
      traceLabel:
          'staff-check office-doc-by-uid offices/$officeId/clients/${u.uid}',
    );
    if ((byUidDoc?.exists ?? false) &&
        __isOfficeStaffMarker(byUidDoc?.data() ?? {})) {
      __traceWorkspace(
        'staff-check hit source=office-doc-uid officeId=$officeId +${sw.elapsedMilliseconds}ms',
      );
      return true;
    }
  } catch (e, st) {
    __traceWorkspace(
      'staff-check office-doc-uid-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  final email = (u.email ?? '').trim().toLowerCase();
  if (email.isNotEmpty) {
    try {
      final byEmailDoc = await __safeDocGet(
        ref.doc(email),
        traceLabel:
            'staff-check office-doc-by-email offices/$officeId/clients/$email',
      );
      if ((byEmailDoc?.exists ?? false) &&
          __isOfficeStaffMarker(byEmailDoc?.data() ?? {})) {
        __traceWorkspace(
          'staff-check hit source=office-doc-email officeId=$officeId +${sw.elapsedMilliseconds}ms',
        );
        return true;
      }
    } catch (e, st) {
      __traceWorkspace(
        'staff-check office-doc-email-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
      );
    }
  }

  try {
    final byUid = await __safeQueryGet(
      ref.where('uid', isEqualTo: u.uid).limit(5),
      traceLabel:
          'staff-check query-by-uid offices/$officeId/clients uid=${u.uid}',
    );
    for (final d in byUid?.docs ?? const []) {
      if (__isOfficeStaffMarker(d.data())) {
        __traceWorkspace(
          'staff-check hit source=query-uid officeId=$officeId docId=${d.id} +${sw.elapsedMilliseconds}ms',
        );
        return true;
      }
    }
  } catch (e, st) {
    __traceWorkspace(
      'staff-check query-uid-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  if (email.isNotEmpty) {
    try {
      final byEmail = await __safeQueryGet(
        ref.where('email', isEqualTo: email).limit(5),
        traceLabel:
            'staff-check query-by-email offices/$officeId/clients email=$email',
      );
      for (final d in byEmail?.docs ?? const []) {
        if (__isOfficeStaffMarker(d.data())) {
          __traceWorkspace(
            'staff-check hit source=query-email officeId=$officeId docId=${d.id} +${sw.elapsedMilliseconds}ms',
          );
          return true;
        }
      }
    } catch (e, st) {
      __traceWorkspace(
        'staff-check query-email-error officeId=$officeId +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
      );
    }
  }

  __traceWorkspace(
    'staff-check miss authUid=${u.uid} officeId=$officeId +${sw.elapsedMilliseconds}ms',
  );
  return false;
}

Future<String?> __sanitizeResolvedOfficeWorkspaceUid(
  User u,
  String? resolvedOfficeUid,
) async {
  final candidate = (resolvedOfficeUid ?? '').trim();
  if (candidate.isEmpty) return null;
  if (candidate == u.uid) return candidate;
  final isStaff = await __hasOfficeStaffRecordUnderOffice(u, candidate);
  if (isStaff) return candidate;
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('office_workspace_uid_${u.uid}');
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      await sp.remove('office_workspace_email_$email');
    }
  } catch (_) {}
  __traceWorkspace(
    'sanitize-reject candidate=$candidate authUid=${u.uid} -> fallback-to-auth',
  );
  return null;
}

Future<void> __cleanupWorkspacePrefsForOwner(
    User u, String workspaceUid) async {
  if (workspaceUid != u.uid) return;
  try {
    final token = await u.getIdTokenResult();
    final claims = token.claims ?? const <String, dynamic>{};
    final role = (claims['role'] ?? '').toString().toLowerCase().trim();
    final isOfficeStaff =
        role == 'office_staff' || role == 'office-user' || role == 'staff';
    if (isOfficeStaff) return;
  } catch (_) {}
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('office_workspace_uid_${u.uid}');
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      await sp.remove('office_workspace_email_$email');
    }
  } catch (_) {}
}

Future<String?> __resolveOfficeWorkspaceUid(User u) async {
  final sw = Stopwatch()..start();
  __traceWorkspace('resolve-start uid=${u.uid} email=${u.email ?? ''}');
  bool claimsSuggestOfficeOwner = false;
  bool docSuggestOfficeOwner = false;
  bool claimsExplicitOfficeClient = false;
  bool docExplicitOfficeClient = false;
  final hintedOfficeIds = <String>{};

  try {
    final t = await u.getIdTokenResult();
    final claims = t.claims ?? {};
    final role = claims['role']?.toString().toLowerCase();
    final normalized = claims.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    claimsExplicitOfficeClient = __isExplicitOfficeClientMarker(normalized);
    final officeId =
        (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
    if (officeId.isNotEmpty) {
      __traceWorkspace(
        'claims officeId=$officeId officeStaffMarker=${__isOfficeStaffMarker(normalized)} explicitClient=$claimsExplicitOfficeClient',
      );
      if (__isOfficeStaffMarker(normalized)) {
        __traceWorkspace('resolve-hit source=claims officeId=$officeId');
        return officeId;
      }
      hintedOfficeIds.add(officeId);
    }
    claimsSuggestOfficeOwner = role == 'office' ||
        role == 'office_owner' ||
        claims['office'] == true ||
        claims['isOffice'] == true;
  } catch (e, st) {
    __traceWorkspace(
      'resolve-claims-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  try {
    final d = await __safeDocGet(
      FirebaseFirestore.instance.collection('users').doc(u.uid),
      traceLabel: 'resolve-office users/${u.uid}',
    );
    final data = d?.data() ?? {};
    final role = data['role']?.toString().toLowerCase();
    docExplicitOfficeClient = __isExplicitOfficeClientMarker(data);
    final officeId =
        (data['officeId'] ?? data['office_id'] ?? '').toString().trim();
    if (officeId.isNotEmpty) {
      __traceWorkspace(
        'users-doc officeId=$officeId officeStaffMarker=${__isOfficeStaffMarker(data)} explicitClient=$docExplicitOfficeClient',
      );
      if (__isOfficeStaffMarker(data)) {
        __traceWorkspace('resolve-hit source=users-doc officeId=$officeId');
        return officeId;
      }
      hintedOfficeIds.add(officeId);
    }
    docSuggestOfficeOwner = role == 'office' ||
        role == 'office_owner' ||
        data['isOffice'] == true ||
        data['office'] == true;
  } catch (e, st) {
    __traceWorkspace(
      'resolve-users-doc-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  try {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString('office_workspace_uid_${u.uid}')?.trim();
    if (saved != null && saved.isNotEmpty) {
      final ok = await __hasOfficeStaffRecordUnderOffice(u, saved);
      __traceWorkspace('prefs uid-key=$saved verified=$ok');
      if (ok) {
        __traceWorkspace('resolve-hit source=prefs-uid officeId=$saved');
        return saved;
      }
    }
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      final savedByEmail =
          sp.getString('office_workspace_email_$email')?.trim();
      if (savedByEmail != null && savedByEmail.isNotEmpty) {
        final ok = await __hasOfficeStaffRecordUnderOffice(u, savedByEmail);
        __traceWorkspace('prefs email-key=$savedByEmail verified=$ok');
        if (ok) {
          __traceWorkspace(
              'resolve-hit source=prefs-email officeId=$savedByEmail');
          return savedByEmail;
        }
      }
    }
  } catch (e, st) {
    __traceWorkspace(
      'resolve-prefs-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  if (claimsExplicitOfficeClient || docExplicitOfficeClient) {
    __traceWorkspace('resolve-result null explicit-office-client');
    return null;
  }

  if (claimsSuggestOfficeOwner || docSuggestOfficeOwner) {
    __traceWorkspace('resolve-hit source=owner-self officeId=${u.uid}');
    return u.uid;
  }

  for (final officeId in hintedOfficeIds) {
    final ok = await __hasOfficeStaffRecordUnderOffice(u, officeId);
    __traceWorkspace('hint officeId=$officeId verified=$ok');
    if (ok) {
      __traceWorkspace('resolve-hit source=hint officeId=$officeId');
      return officeId;
    }
  }

  try {
    final byUid = await __safeQueryGet(
      FirebaseFirestore.instance
          .collectionGroup('clients')
          .where('uid', isEqualTo: u.uid)
          .limit(10),
      traceLabel: 'resolve-office cg-clients-by-uid uid=${u.uid}',
    );
    for (final d in byUid?.docs ?? const []) {
      if (__isOfficeStaffMarker(d.data())) {
        final parent = d.reference.parent.parent;
        if (parent != null) {
          __traceWorkspace('resolve-hit source=cg-uid officeId=${parent.id}');
          return parent.id;
        }
      }
    }
  } catch (e, st) {
    __traceWorkspace(
      'resolve-cg-uid-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  try {
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      final byEmail = await __safeQueryGet(
        FirebaseFirestore.instance
            .collectionGroup('clients')
            .where('email', isEqualTo: email)
            .limit(10),
        traceLabel: 'resolve-office cg-clients-by-email email=$email',
      );
      for (final d in byEmail?.docs ?? const []) {
        if (__isOfficeStaffMarker(d.data())) {
          final parent = d.reference.parent.parent;
          if (parent != null) {
            __traceWorkspace(
              'resolve-hit source=cg-emailField officeId=${parent.id}',
            );
            return parent.id;
          }
        }
      }
    }
  } catch (e, st) {
    __traceWorkspace(
      'resolve-cg-email-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }

  __traceWorkspace(
      'resolve-result null uid=${u.uid} +${sw.elapsedMilliseconds}ms');
  return null;
}

Future<String?> __resolveUserRole(User u) async {
  final sw = Stopwatch()..start();
  __traceWorkspace('role-resolve start uid=${u.uid}');
  final officeWorkspaceUid = await __resolveOfficeWorkspaceUid(u);
  if (officeWorkspaceUid != null && officeWorkspaceUid.isNotEmpty) {
    __traceWorkspace(
      'role-resolve hit source=office-workspace role=office workspaceUid=$officeWorkspaceUid +${sw.elapsedMilliseconds}ms',
    );
    return 'office';
  }
  try {
    final t = await u.getIdTokenResult();
    final claims = (t.claims ?? {}).map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final r = t.claims?['role']?.toString();
    if (r != null && r.isNotEmpty) {
      __traceWorkspace(
        'role-resolve hit source=claims role=$r +${sw.elapsedMilliseconds}ms',
      );
      return r;
    }
    if (__isOfficeStaffMarker(claims)) {
      __traceWorkspace(
        'role-resolve hit source=claims-marker role=office_staff +${sw.elapsedMilliseconds}ms',
      );
      return 'office_staff';
    }
  } catch (e, st) {
    __traceWorkspace(
      'role-resolve claims-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }
  try {
    final d = await __safeDocGet(
      FirebaseFirestore.instance.collection('users').doc(u.uid),
      traceLabel: 'resolve-role users/${u.uid}',
    );
    final data = d?.data() ?? {};
    final role = data['role']?.toString();
    if (role != null && role.isNotEmpty) {
      __traceWorkspace(
        'role-resolve hit source=users-doc role=$role +${sw.elapsedMilliseconds}ms',
      );
      return role;
    }
    if (__isOfficeStaffMarker(data)) {
      __traceWorkspace(
        'role-resolve hit source=users-doc-marker role=office_staff +${sw.elapsedMilliseconds}ms',
      );
      return 'office_staff';
    }
  } catch (e, st) {
    __traceWorkspace(
      'role-resolve users-doc-error uid=${u.uid} +${sw.elapsedMilliseconds}ms err=$e stack=${__compactStackTrace(st)}',
    );
  }
  __traceWorkspace(
      'role-resolve result=null uid=${u.uid} +${sw.elapsedMilliseconds}ms');
  return null;
}

/* ===================== main ===================== */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ã˜Â´Ã˜Â±Ã™Å Ã˜Â· Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ˜Â© Ã™Ë†Ã˜Â´Ã˜Â±Ã™Å Ã˜Â· Ã˜Â§Ã™â€žÃ™â€ Ã˜Â¸Ã˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â³Ã™ÂÃ™â€žÃ™Å  Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â³Ã™Ë†Ã˜Â¯ Ã™Æ’Ã™â€¦Ã˜Â§ Ã˜ÂªÃ˜Â±Ã™Å Ã˜Â¯
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kBrandDark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBrandDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await ConnectivityService.instance.init();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(const MyApp());
}

bool _splashDone = false;
final ValueNotifier<String?> _activeRouteName = ValueNotifier<String?>(null);

class _AppRouteObserver extends NavigatorObserver {
  void _updateRoute(Route<dynamic>? route) {
    final routeName = route?.settings.name;
    if (_activeRouteName.value != routeName) {
      _activeRouteName.value = routeName;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateRoute(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateRoute(previousRoute);
  }
}

final _appRouteObserver = _AppRouteObserver();

class _AppOnlineOnlyGuard extends StatefulWidget {
  const _AppOnlineOnlyGuard({required this.child});

  final Widget child;

  @override
  State<_AppOnlineOnlyGuard> createState() => _AppOnlineOnlyGuardState();
}

class _AppOnlineOnlyGuardState extends State<_AppOnlineOnlyGuard> {
  bool _timeSyncInFlight = false;
  bool _syncFailed = false;
  Timer? _syncRetryTimer;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.statusListenable.addListener(_handleGuardTick);
    KsaTime.syncListenable.addListener(_handleGuardTick);
    _activeRouteName.addListener(_handleGuardTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureServerTimeIfPossible());
    });
  }

  @override
  void dispose() {
    _syncRetryTimer?.cancel();
    ConnectivityService.instance.statusListenable
        .removeListener(_handleGuardTick);
    KsaTime.syncListenable.removeListener(_handleGuardTick);
    _activeRouteName.removeListener(_handleGuardTick);
    super.dispose();
  }

  void _handleGuardTick() {
    if (!mounted) return;
    if (ConnectivityService.instance.currentStatus != true || KsaTime.isSynced) {
      _syncRetryTimer?.cancel();
    }
    setState(() {});
    unawaited(_ensureServerTimeIfPossible());
  }

  void _scheduleServerTimeRetry() {
    _syncRetryTimer?.cancel();
    if (!mounted) return;
    if (ConnectivityService.instance.currentStatus != true) return;
    if (KsaTime.isSynced) return;
    _syncRetryTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_timeSyncInFlight) return;
      if (ConnectivityService.instance.currentStatus != true) return;
      if (KsaTime.isSynced) return;
      unawaited(_ensureServerTimeIfPossible());
    });
  }

  Future<void> _ensureServerTimeIfPossible() async {
    if (_timeSyncInFlight) return;
    if (Firebase.apps.isEmpty) return;
    if (ConnectivityService.instance.currentStatus != true) return;
    if (KsaTime.isSynced) {
      _syncRetryTimer?.cancel();
      if (_syncFailed) {
        _syncFailed = false;
        if (mounted) setState(() {});
      }
      return;
    }

    _timeSyncInFlight = true;
    _syncRetryTimer?.cancel();
    _syncFailed = false;
    if (mounted) setState(() {});
    try {
      for (int i = 0; i < 10; i++) {
        await KsaTime.ensureSynced(force: true);
        if (KsaTime.isSynced) {
          KsaTime.startAutoSync();
          _syncFailed = false;
          _syncRetryTimer?.cancel();
          break;
        }
        if (!mounted) break;
        if (ConnectivityService.instance.currentStatus != true) break;
        await Future.delayed(const Duration(seconds: 3));
      }
      if (!KsaTime.isSynced) {
        _syncFailed = true;
        _scheduleServerTimeRetry();
      }
    } finally {
      _timeSyncInFlight = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ConnectivityService.instance.currentStatus;
    final showOfflineOverlay = isOnline == false;
    final isLoginRoute = _activeRouteName.value == '/login';
    final showSlowBanner = _splashDone &&
        !isLoginRoute &&
        isOnline == true &&
        !KsaTime.isSynced &&
        (_timeSyncInFlight || _syncFailed);

    return Stack(
      children: [
        widget.child,
        if (showSlowBanner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: _syncFailed
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF59E0B),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _syncFailed
                            ? Icons.cloud_off_rounded
                            : Icons.hourglass_top_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncFailed
                              ? 'تعذرت مزامنة وقت الخادم حاليًا، جارٍ إعادة المحاولة...'
                              : 'جاري مزامنة وقت الخادم، يرجى الانتظار قليلًا...',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_splashDone && showOfflineOverlay)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withOpacity(0.42),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.64),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 50,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'يجب الاتصال بالإنترنت',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'التطبيق يعمل الآن عبر الإنترنت فقط. تحقق من الاتصال ثم أعد المحاولة.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.84),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375,
          812), // Ã™â€¦Ã™â€šÃ˜Â§Ã˜Â³ Ã™â€¦Ã˜Â±Ã˜Â¬Ã˜Â¹Ã™Å Ã˜â€º Ã˜ÂºÃ™Å Ã™â€˜Ã˜Â±Ã™â€¡ Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã˜Â¬Ã˜Â©
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp(
          useInheritedMediaQuery:
              true, // Ã™â€¦Ã™â€¡Ã™â€¦ Ã™â€žÃ˜ÂªÃ™â€ Ã˜Â§Ã˜Â³Ã™â€š Ã˜Â§Ã™â€žÃ™â€šÃ™Å Ã˜Â§Ã˜Â³Ã˜Â§Ã˜Âª
          debugShowCheckedModeBanner: false,
          title: 'Darvoo',
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: NoGlowScrollBehavior(),
          navigatorObservers: [_appRouteObserver],

          // Ã¢Å“â€¦ Ã™â€šÃ™ÂÃ™â€ž Ã˜ÂªÃ™Æ’Ã˜Â¨Ã™Å Ã˜Â± Ã˜Â§Ã™â€žÃ™â€ Ã˜Âµ + SafeArea Ã˜Â³Ã™ÂÃ™â€žÃ™Å  Ã˜Â¹Ã˜Â§Ã™â€žÃ™â€¦Ã™Å  Ã™â€žÃ™â€¦Ã™â€ Ã˜Â¹ Ã˜ÂªÃ˜Â¬Ã˜Â§Ã™Ë†Ã˜Â² Ã˜Â´Ã˜Â±Ã™Å Ã˜Â· Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â¬Ã™Ë†Ã˜Â¹/Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€ Ã™â€šÃ™â€ž
          builder: (context, innerChild) {
            final mq = MediaQuery.of(context);
            final body = ColoredBox(
              color: kBrandDark,
              child: innerChild ?? const SizedBox.shrink(),
            );
            final safe = SafeArea(top: false, bottom: true, child: body);
            final guardedChild = MediaQuery(
              data: mq.copyWith(
                // Ã™Å Ã™â€¦Ã™â€ Ã˜Â¹ Ã˜ÂªÃ˜Â¶Ã˜Â®Ã™Å Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€ Ã˜Âµ Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â£Ã™â€ Ã˜Â¯Ã˜Â±Ã™Ë†Ã™Å Ã˜Â¯ 15
                textScaler: const TextScaler.linear(1.0),
                // Ã™â€žÃ™â€žÃ™â€ Ã˜Â³Ã˜Â® Ã˜Â§Ã™â€žÃ˜Â£Ã™â€šÃ˜Â¯Ã™â€¦ Ã™â€¦Ã™â€  Flutter Ã™Å Ã™â€¦Ã™Æ’Ã™â€  Ã˜Â§Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã˜Â§Ã™â€¦:
                // textScaleFactor: 1.0,
              ),
              child: safe,
            );
            return _AppOnlineOnlyGuard(child: guardedChild);
          },

          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,

            // Ã˜Â®Ã™â€žÃ™ÂÃ™Å Ã˜Â§Ã˜Âª Ã˜Â¹Ã˜Â§Ã™â€¦Ã˜Â© Ã˜Â¨Ã™Å Ã˜Â¶Ã˜Â§Ã˜Â¡
            scaffoldBackgroundColor: kRouteBg,
            canvasColor: kRouteBg,

            colorScheme: ColorScheme.fromSeed(
              seedColor: kBrandPrimary,
              brightness: Brightness.light,
            ),
            fontFamily: GoogleFonts.cairo().fontFamily,

            // AppBar Ã˜Â£Ã˜Â³Ã™Ë†Ã˜Â¯
            appBarTheme: const AppBarTheme(
              backgroundColor: kBrandDark,
              elevation: 0,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: kBrandDark,
                statusBarIconBrightness: Brightness.light,
              ),
            ),

            // BottomNavigationBar Ã˜Â£Ã˜Â³Ã™Ë†Ã˜Â¯ (Ã˜Â«Ã˜Â§Ã˜Â¨Ã˜Âª)
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: kBrandDark,
              selectedItemColor: kBrandAccent,
              unselectedItemColor: Color(0xFFCBD5E1),
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),

            // NavigationBar (Material 3) Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã˜Â¬Ã˜Â©
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: kBrandDark,
              indicatorColor: const Color(0x1F5EEAD4),
              elevation: 8,
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(color: Colors.white),
              ),
              iconTheme: WidgetStateProperty.all(
                const IconThemeData(color: Colors.white),
              ),
            ),

            // Ã˜ÂªÃ™Ë†Ã˜Â§Ã™ÂÃ™â€š Ã™â€¦Ã˜Â¹ Ã™â€ Ã˜Â³Ã˜Â®Ã˜ÂªÃ™Æ’: BottomAppBarThemeData
            bottomAppBarTheme: const BottomAppBarThemeData(
              color: kBrandDark,
              elevation: 8,
            ),

            // Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â§Ã™ÂÃ˜ÂªÃ˜Â±Ã˜Â§Ã˜Â¶Ã™Å Ã˜Â© Ã˜Â¨Ã˜Â®Ã™â€žÃ™ÂÃ™Å Ã˜Â© Ã˜Â¨Ã™Å Ã˜Â¶Ã˜Â§Ã˜Â¡
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(kBrandPrimary),
                foregroundColor: WidgetStateProperty.all(Colors.white),
                elevation: WidgetStateProperty.all(2),
              ),
            ),

            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.fuchsia: NoAnimationPageTransitionsBuilder(),
              },
            ),
          ),

          routes: {
            ...InvoicesRoutes.routes(),
            ...MaintenanceRoutes.routes(),
            ...ReportsRoutes.routes(),
            ...PropertyServicesRoutes.routes(),
            ...NotificationsRoutes.routes(),
            '/home': (_) => const DisabledAccountGuard(child: HomeScreen()),
            '/login': (_) => const LoginScreen(),
            '/office': (_) => const DisabledAccountGuard(child: OfficeHomePage()),
            '/contracts': (_) => const contracts_ui.ContractsScreen(),
            '/contracts/new': (_) => const AddOrEditContractScreen(),
          },
          home: const SplashRouter(),
        );
      },
    );
  }
}

/// Ã˜Â´Ã˜Â§Ã˜Â´Ã˜Â© Ã˜Â´Ã˜Â¹Ã˜Â§Ã˜Â±/Ã˜ÂªÃ™Ë†Ã˜Â¬Ã™Å Ã™â€¡ Ã˜ÂªÃ˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â¯ Ã˜Â¹Ã™â€žÃ™â€° Firebase Auth
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  StreamSubscription<User?>? _authSub;

  // Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â²Ã˜Â§Ã™â€¦Ã™â€ Ã˜Â© Ã™â€žÃ™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€  (Ã˜Â³Ã™â€ Ã˜Â¬Ã™â€žÃ˜ÂªÃ™Ë†Ã™â€ )
  final _offlineSync = OfflineSyncService.instance;

  @override
  void initState() {
    super.initState();
    _kickoff();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _offlineSync.dispose();
    super.dispose();
  }

  /// Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© Firebase Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â³Ã˜Â§Ã˜Â³Ã™Å Ã˜Â© Ã™â€¦Ã˜Â±Ã™â€˜Ã˜Â© Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯Ã˜Â© Ã™ÂÃ™â€šÃ˜Â· (Ã˜Â¯Ã™Ë†Ã™â€  Ã˜Â±Ã˜Â¨Ã˜Â·Ã™â€¡Ã˜Â§ Ã˜Â¨Ã˜Â³Ã˜Â±Ã˜Â¹Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¨Ã™Æ’Ã˜Â©)
  Future<void> _ensureFirebaseCore() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> _loadAiChatApiKey() async {
    await AiChatService.refreshApiKeyFromRemote();
  }

  /// Ã™Æ’Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â«Ã™â€šÃ™Å Ã™â€žÃ˜Â© Ã™â€¡Ã™â€ Ã˜Â§ Ã™Ë†Ã˜ÂªÃ˜Â¹Ã™â€¦Ã™â€ž Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¨Ã™â€žÃ˜Â§Ã˜Â´
  Future<void> _bootstrapAll() async {
    // 1) Firebase
    await _ensureFirebaseCore();

    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: false);

    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    try {
      await FirebaseAuth.instance.setLanguageCode('ar');
    } catch (_) {}

    // 2) Hive + Adapters + Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜Â§Ã™â€žÃ˜ÂµÃ™â€ Ã˜Â§Ã˜Â¯Ã™Å Ã™â€š
    await Hive.initFlutter();
    _registerHiveAdapters();

    final currUser = FirebaseAuth.instance.currentUser;
    final bootstrapWorkspaceUid = currUser == null
        ? null
        : ((await __sanitizeResolvedOfficeWorkspaceUid(
                currUser, await __resolveOfficeWorkspaceUid(currUser))) ??
            currUser.uid);
    if (currUser != null &&
        bootstrapWorkspaceUid != null &&
        bootstrapWorkspaceUid.isNotEmpty) {
      await __recoverLocalDataFromLegacyScopes(currUser, bootstrapWorkspaceUid);
      await __cleanupWorkspacePrefsForOwner(currUser, bootstrapWorkspaceUid);
    }
    if (bootstrapWorkspaceUid != null && bootstrapWorkspaceUid.isNotEmpty) {
      setFixedUid(bootstrapWorkspaceUid);
    } else {
      clearFixedUid();
    }

    // Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜ÂµÃ™â€ Ã˜Â§Ã˜Â¯Ã™Å Ã™â€š Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ (Ã˜Â£Ã™Ë† "guest")
    await HiveService.ensureReportsBoxesOpen();

    // Ã˜Â¬Ã˜Â³Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â²Ã˜Â§Ã™â€¦Ã™â€ Ã˜Â©
    await SyncManager.instance.startAll();
    final syncScopeUid = effectiveUid().trim();

    // Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€  Ã™â€žÃ™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  (Ã˜Â¥Ã™â€  Ã™Ë†Ã™ÂÃ˜Â¬Ã˜Â¯)
    if (currUser != null) {
      final uc = UserCollections(
        (syncScopeUid.isNotEmpty && syncScopeUid != 'guest')
            ? syncScopeUid
            : (bootstrapWorkspaceUid ?? currUser.uid),
      );
      final repo = TenantsRepo(uc);
      _offlineSync.dispose();
      await _offlineSync.init(uc: uc, repo: repo);
    }

    // Ã˜ÂªÃ™Ë†Ã™â€šÃ™Å Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¹Ã™Ë†Ã˜Â¯Ã™Å Ã˜Â© (Ã˜Â³Ã™Å Ã˜Â±Ã™ÂÃ˜Â±)
    await KsaTime.ensureSynced();
    if (KsaTime.isSynced) {
      KsaTime.startAutoSync();
    }

    // جلب مفتاح OpenAI للمساعد الذكي
    unawaited(_loadAiChatApiKey());

    //Ã™â€¦Ã˜ÂªÃ˜Â§Ã˜Â¨Ã˜Â¹Ã˜Â© Ã˜ÂªÃ˜ÂºÃ™Å Ã™â€˜Ã˜Â± Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await SyncManager.instance.stopAll();
      _offlineSync.dispose();

      // Ã˜Â£Ã˜ÂºÃ™â€žÃ™â€š Ã˜ÂµÃ™â€ Ã˜Â§Ã˜Â¯Ã™Å Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¨Ã™â€š
      final candidates = <String>{
        boxName('sessionBox'),
        boxName('contractsBox'),
        boxName('propertiesBox'),
        boxName('tenantsBox'),
        boxName(kInvoicesBox),
        boxName('maintenanceBox'),
        boxName('reportsBox'),
      };

      for (final name in candidates) {
        if (Hive.isBoxOpen(name)) {
          try {
            await Hive.box(name).close();
          } catch (_) {}
        }
      }

      final workspaceUid = user == null
          ? null
          : ((await __sanitizeResolvedOfficeWorkspaceUid(
                  user, await __resolveOfficeWorkspaceUid(user))) ??
              user.uid);
      __traceWorkspace(
        'auth-state uid=${user?.uid ?? ''} resolvedWorkspace=${workspaceUid ?? ''}',
      );
      if (workspaceUid != null && workspaceUid.isNotEmpty && user != null) {
        await __recoverLocalDataFromLegacyScopes(user, workspaceUid);
        await __cleanupWorkspacePrefsForOwner(user, workspaceUid);
        setFixedUid(workspaceUid);
      } else {
        clearFixedUid();
      }

      // Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜ÂµÃ™â€ Ã˜Â§Ã˜Â¯Ã™Å Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å
      await HiveService.ensureReportsBoxesOpen();

      // Ã˜Â¬Ã˜Â³Ã™Ë†Ã˜Â± Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦
      await SyncManager.instance.startAll();
      final syncScopeUid = effectiveUid().trim();
      __traceWorkspace(
        'auth-state normalizedScope=${syncScopeUid.isEmpty ? 'guest' : syncScopeUid}',
      );

      // Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€  Ã™â€žÃ™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦
      if (user != null) {
        final ucUid = (syncScopeUid.isNotEmpty && syncScopeUid != 'guest')
            ? syncScopeUid
            : (workspaceUid ?? user.uid);
        final uc = UserCollections(
          ucUid,
        );
        final repo = TenantsRepo(uc);
        await _offlineSync.init(uc: uc, repo: repo);
        unawaited(_loadAiChatApiKey());
      }

      if (mounted) setState(() {});
    });
  }

  Future<void> _kickoff() async {
    // 1) Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© Firebase Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â³Ã˜Â§Ã˜Â³Ã™Å Ã˜Â© Ã˜Â¨Ã˜Â³Ã˜Â±Ã˜Â¹Ã˜Â© (Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â±Ã˜ÂªÃ˜Â¨Ã˜Â·Ã˜Â© Ã˜Â¨Ã˜Â³Ã˜Â±Ã˜Â¹Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â±Ã™â€ Ã˜Âª)
    await _ensureFirebaseCore();

    // 2) Ã˜Â§Ã˜Â¨Ã˜Â¯Ã˜Â£ Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â«Ã™â€šÃ™Å Ã™â€žÃ˜Â© Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â®Ã™â€žÃ™ÂÃ™Å Ã˜Â© Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â´Ã˜Â§Ã˜Â´Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¹Ã˜Â§Ã˜Â±
    _bootstrapAll(); // Ã™â€žÃ˜Â§ Ã™â€ Ã™â€ Ã˜ÂªÃ˜Â¸Ã˜Â± Ã™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ™â‚¬ Future Ã™â€¡Ã™â€ Ã˜Â§

    // 3) Ã™â€ Ã˜Â¶Ã™â€¦Ã™â€  Ã˜Â¨Ã™â€šÃ˜Â§Ã˜Â¡ Ã˜Â´Ã˜Â§Ã˜Â´Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¹Ã˜Â§Ã˜Â± Ã™â€žÃ™ÂÃ˜ÂªÃ˜Â±Ã˜Â© Ã™â€šÃ˜ÂµÃ™Å Ã˜Â±Ã˜Â© Ã™ÂÃ™â€šÃ˜Â·
    await const Duration(seconds: 2).delay();

    if (!mounted) return;

    var user = FirebaseAuth.instance.currentUser;

    // تحقق من صلاحية التوكن (مثلاً حساب ديمو محذوف)
    if (user != null) {
      try {
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        user = null;
      }
    }

    //Ã°Å¸â€˜â€¡ Ã˜Â£Ã™Ë†Ã™â€žÃ˜Â§Ã™â€¹: Ã™â€žÃ™Ë† Ã™â€¦Ã˜Â§ Ã™ÂÃ™Å  Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Firebase Ã™â€ Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€ Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜Â¢Ã˜Â®Ã˜Â± Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã™â€¦Ã˜Â­Ã™ÂÃ™Ë†Ã˜Â¸ (Ã˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€ )
    if (user != null) {
      await _loadAiChatApiKey();
    }

    if (user == null) {
      clearFixedUid();
      _splashDone = true;
      Navigator.of(context).pushReplacementNamed('/login');
      return;

      final sp = await SharedPreferences.getInstance();
      final lastUid = sp.getString('last_login_uid');
      final lastRole = sp.getString('last_login_role');

      if (lastUid == null || lastRole == null) {
        // Ã™â€¦Ã˜Â§ Ã™ÂÃ™Å  Ã˜Â£Ã™Å  Ã˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â³Ã˜Â§Ã˜Â¨Ã™â€š Ã™â€¦Ã˜Â­Ã™ÂÃ™Ë†Ã˜Â¸ Ã¢â€ â€™ Ã™â€ Ã˜Â°Ã™â€¡Ã˜Â¨ Ã™â€žÃ˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // Ã˜Â«Ã˜Â¨Ã™â€˜Ã˜Âª Ã˜Â§Ã™â€žÃ™â‚¬ UID Ã™â€žÃ™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€
      setFixedUid(lastUid);

      // Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜ÂµÃ™â€ Ã˜Â§Ã˜Â¯Ã™Å Ã™â€š Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦
      await HiveService.ensureReportsBoxesOpen();

      // Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â£Ã™Ë†Ã™ÂÃ™â€žÃ˜Â§Ã™Å Ã™â€  Ã™â€žÃ™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ (Ã˜Â­Ã˜ÂªÃ™â€° Ã™â€žÃ™Ë† Ã™â€¦Ã˜Â§Ã™ÂÃ™Å Ã˜Â´ FirebaseAuth user)
      final uc = UserCollections(lastUid);
      final repo = TenantsRepo(uc);
      await _offlineSync.init(uc: uc, repo: repo);

      if (!mounted) return;

      final role = lastRole.toLowerCase();
      if (role == 'office' || role == 'office_owner') {
        Navigator.of(context).pushReplacementNamed('/office');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
      return;
    }

    // Ã™â€¡Ã™â€ Ã˜Â§ Ã™ÂÃ™Å  Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Firebase Ã˜Â¹Ã˜Â§Ã˜Â¯Ã™Å  Ã¢â€ â€™ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜Â·Ã™â€š Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¨Ã™â€š Ã™Æ’Ã™â€¦Ã˜Â§ Ã™â€¡Ã™Ë†
    final officeWorkspaceUid = await __sanitizeResolvedOfficeWorkspaceUid(
      user,
      await __resolveOfficeWorkspaceUid(user),
    );
    if (officeWorkspaceUid != null && officeWorkspaceUid.isNotEmpty) {
      await __recoverLocalDataFromLegacyScopes(user, officeWorkspaceUid);
      await __cleanupWorkspacePrefsForOwner(user, officeWorkspaceUid);
      __traceWorkspace(
        'kickoff-route /office uid=${user.uid} workspaceUid=$officeWorkspaceUid',
      );
      setFixedUid(officeWorkspaceUid);
      _splashDone = true;
      Navigator.of(context).pushReplacementNamed('/office');
      return;
    }

    final role = (await __resolveUserRole(user))?.toLowerCase() ?? 'client';
    _splashDone = true;
    if (role == 'office' || role == 'office_owner') {
      __traceWorkspace('kickoff-role-office uid=${user.uid}');
      setFixedUid(user.uid);
      Navigator.of(context).pushReplacementNamed('/office');
    } else if (role == 'office_staff') {
      __traceWorkspace('kickoff-office-staff-unresolved uid=${user.uid}');
      clearFixedUid();
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      Navigator.of(context).pushReplacementNamed('/login');
    } else {
      __traceWorkspace('kickoff-route /home uid=${user.uid}');
      setFixedUid(user.uid);
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // Ã˜Â®Ã™â€žÃ™ÂÃ™Å Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¨Ã™â€žÃ˜Â§Ã˜Â´ Ã˜Â¨Ã™Å Ã˜Â¶Ã˜Â§Ã˜Â¡ (Ã™â€žÃ˜Â§ Ã˜Â³Ã™Ë†Ã˜Â¯Ã˜Â§Ã˜Â¡)
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 200.w,
                    height: 200.w,
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ====== Ã˜Â§Ã™â€¦Ã˜ÂªÃ˜Â¯Ã˜Â§Ã˜Â¯ Ã˜ÂµÃ˜ÂºÃ™Å Ã˜Â± Ã™â€žÃ˜ÂªÃ˜Â£Ã˜Â®Ã™Å Ã˜Â± Ã˜Â£Ã™â€ Ã™Å Ã™â€š ====== */
extension _Delay on Duration {
  Future<void> delay() => Future.delayed(this);
}

// ===================== Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Adapters Ã˜Â¨Ã˜Â£Ã™â€¦Ã˜Â§Ã™â€  =====================
void _registerHiveAdapters() {
  if (!Hive.isAdapterRegistered(PropertyTypeAdapter().typeId)) {
    Hive.registerAdapter(PropertyTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(RentalModeAdapter().typeId)) {
    Hive.registerAdapter(RentalModeAdapter());
  }
  if (!Hive.isAdapterRegistered(PropertyAdapter().typeId)) {
    Hive.registerAdapter(PropertyAdapter());
  }
  if (!Hive.isAdapterRegistered(TenantAdapter().typeId)) {
    Hive.registerAdapter(TenantAdapter());
  }
  if (!Hive.isAdapterRegistered(ContractAdapter().typeId)) {
    Hive.registerAdapter(ContractAdapter());
  }
  if (!Hive.isAdapterRegistered(InvoiceAdapter().typeId)) {
    Hive.registerAdapter(InvoiceAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenancePriorityAdapter().typeId)) {
    Hive.registerAdapter(MaintenancePriorityAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenanceStatusAdapter().typeId)) {
    Hive.registerAdapter(MaintenanceStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(MaintenanceRequestAdapter().typeId)) {
    Hive.registerAdapter(MaintenanceRequestAdapter());
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
