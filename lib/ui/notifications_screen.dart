// lib/ui/notifications_screen.dart
// ???? ??"?????S????: ???^?"?'? ??S????.?S?f?S?<? ?.?? ??"??,?^? ?^??"??^???S? ?^??"??S????
// - ??"?????S???? ?"? ?????'?Z???> ???????? ?"???S?<? ?.?? ??"??????S?,.
// - ?S?.?f?? ?"?"?.?????. ??? ??"?????S?? ???"??? ?S?.?S???<??> ??????'?" ??"?.???^??? ??S Box<String> ????. notificationsDismissed.
// - ??"????:
//   ??? ??,?^?: "?,???? ??"?? ??"????????" (endDate ??"??" 7 ??S??.)?O "?.??????" (endDate < ??"?S?^?.)
//   ??? ?????,??,?? ??"??,?: "?.????, ??"?S?^?." ?^"?.????" ???? ???^?? ?^??^? ??^???S?
//   ??? ??S????: "?.?^?? ????S? ??"?S?^?." (scheduledDate == ??"?S?^?. ?^?"?. ???f?.?'?Z?")
import 'package:darvoo/utils/ksa_time.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:darvoo/data/services/user_scope.dart' as scope;

import '../data/services/user_scope.dart' show boxName;
import '../data/services/office_client_guard.dart'; // ?o. ???S?

import 'contracts_screen.dart'
    show
        Contract,
        ContractTerm,
        PaymentCycle,
        AdvanceMode,
        ContractsScreen,
        ContractDetailsScreen;

import 'invoices_screen.dart' show Invoice;

import 'maintenance_screen.dart'
    show MaintenanceRequest, MaintenanceStatus, MaintenanceDetailsScreen;
import 'property_services_screen.dart'
    show PropertyServicesRoutes, ensurePeriodicServiceRequestsGenerated;

import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;

import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import '../widgets/darvoo_app_bar.dart';

// ==============================
// ??"?.?????
// ==============================
class NotificationsRoutes {
  static const String notifications = '/notifications';
  static Map<String, WidgetBuilder> routes() => {
        notifications: (_) => const NotificationsScreen(),
      };
}

// ==============================
// ????^?? ??"?????S??
// ==============================
enum NotificationKind {
  contractStartedToday,
  contractExpiring,
  contractEnded,
  contractDueSoon,
  contractDueToday,
  contractDueOverdue,
  invoiceOverdue,
  maintenanceToday,
  serviceStart,
  serviceDue,
}

// ==============================
// Helpers ?.????f? (Top-level) ?"?.????S? ??"?????
// ==============================

DateTime _dateOnlyGlobal(DateTime d) => DateTime(d.year, d.month, d.day);

String stableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  // ??"??f?" ??"?.???.?: anchor ?.???'? day-only
  return '${k.name}:$id:${_dateOnlyGlobal(anchor).toIso8601String()}';
}

// ???. ????S ?"?"?.????S? ??"?,??S?.? (?f???? ??????. anchor ??f??.?" ??"?^?,?)
String legacyStableKey(
  NotificationKind k, {
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return '${k.name}:$id:${anchor.toIso8601String()}';
}

// ?.???? ???.?" (ALL) ?"???? ??"?f?S???/??"?S?^?. ??? ??"???? ??? ???^? ??"?????S??
String anyStableKey({
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final id = cid ?? iid ?? mid ?? 'na';
  return 'ALL:$id:${_dateOnlyGlobal(anchor).toIso8601String()}';
}

String _fmtYmdGlobal(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _serviceDueDateGlobal(Map<String, dynamic> cfg) {
  final type = (cfg['serviceType'] ?? '').toString();
  dynamic raw;
  if (type == 'elevator') {
    raw = cfg['nextServiceDate'] ?? cfg['nextDueDate'];
  } else {
    raw = cfg['nextDueDate'];
  }
  if (raw is DateTime) return _dateOnlyGlobal(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return _dateOnlyGlobal(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

DateTime? _serviceStartDateGlobal(Map<String, dynamic> cfg) {
  final raw = cfg['startDate'];
  if (raw is DateTime) return _dateOnlyGlobal(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return _dateOnlyGlobal(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _internetBillingModeGlobal(Map<String, dynamic> cfg) {
  final payer = (cfg['payer'] ?? '').toString().trim().toLowerCase();
  final raw = (cfg['internetBillingMode'] ??
          (payer == 'tenant' ? 'separate' : 'owner'))
      .toString()
      .trim()
      .toLowerCase();
  return raw == 'separate' ? 'separate' : 'owner';
}

DateTime? _serviceCurrentCycleDateGlobal(Map<String, dynamic> cfg) {
  final type = (cfg['serviceType'] ?? '').toString();
  final isPeriodicMaintenanceService =
      type == 'cleaning' ||
      type == 'elevator' ||
      (type == 'internet' && _internetBillingModeGlobal(cfg) == 'owner');
  final lastGenerated = _serviceLastGeneratedDateGlobal(cfg);
  final startDate = _serviceStartDateGlobal(cfg);
  if (isPeriodicMaintenanceService &&
      lastGenerated == null &&
      startDate != null) {
    return startDate;
  }
  return _serviceDueDateGlobal(cfg);
}

DateTime? _serviceSuppressedDateGlobal(Map<String, dynamic> cfg) {
  final raw = cfg['suppressedRequestDate'];
  if (raw is DateTime) return _dateOnlyGlobal(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return _dateOnlyGlobal(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

bool _maintenanceHasCanceledInvoiceGlobal(
  dynamic request,
  Box<Invoice>? invoices,
) {
  if (invoices == null) return false;
  final invoiceId = (request as dynamic).invoiceId?.toString().trim() ?? '';
  if (invoiceId.isEmpty) return false;
  final invoice = invoices.get(invoiceId);
  if (invoice == null) return false;
  return invoice.isCanceled;
}

DateTime _maintenanceAnchorGlobal(MaintenanceRequest request) =>
    _dateOnlyGlobal(
      request.periodicCycleDate ??
          request.executionDeadline ??
          request.scheduledDate ??
          request.createdAt,
    );

String? _normalizePeriodicServiceTypeTokenGlobal(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'cleaning' || value.contains('clean') || value.contains('نظاف')) {
    return 'cleaning';
  }
  if (value == 'elevator' ||
      value.contains('elevator') ||
      value.contains('مصعد') ||
      value.contains('اسانسير')) {
    return 'elevator';
  }
  if (value == 'internet' ||
      value.contains('internet') ||
      value.contains('انترنت') ||
      value.contains('إنترنت')) {
    return 'internet';
  }
  return null;
}

bool _matchesLegacyPeriodicMaintenanceRequestGlobal(
  MaintenanceRequest request,
  String type,
) {
  String expectedTitle = '';
  String expectedRequestType = '';
  switch (type) {
    case 'cleaning':
      expectedTitle = 'طلب نظافة عمارة';
      expectedRequestType = 'نظافة عمارة';
      break;
    case 'elevator':
      expectedTitle = 'طلب صيانة مصعد';
      expectedRequestType = 'صيانة مصعد';
      break;
    case 'internet':
      expectedTitle = 'طلب تجديد خدمة إنترنت';
      expectedRequestType = 'خدمة إنترنت';
      break;
  }
  if (expectedTitle.isEmpty || expectedRequestType.isEmpty) return false;
  return request.title.trim() == expectedTitle ||
      request.requestType.trim() == expectedRequestType;
}

bool _matchesPeriodicMaintenanceRequestGlobal(
  MaintenanceRequest request, {
  required String propertyId,
  required String type,
}) {
  if (request.propertyId != propertyId) return false;
  final tagged =
      _normalizePeriodicServiceTypeTokenGlobal(request.periodicServiceType);
  if (tagged != null) return tagged == type;
  return _matchesLegacyPeriodicMaintenanceRequestGlobal(request, type);
}

MaintenanceRequest? _activePeriodicMaintenanceRequestGlobal({
  required Box<MaintenanceRequest>? maintenance,
  required Box<Invoice>? invoices,
  required String propertyId,
  required String type,
  required DateTime anchor,
}) {
  if (maintenance == null) return null;
  final normalizedAnchor = _dateOnlyGlobal(anchor);
  MaintenanceRequest? latest;
  for (final request in maintenance.values) {
    if (request.isArchived) continue;
    if (request.status == MaintenanceStatus.canceled) continue;
    if (request.status == MaintenanceStatus.completed) continue;
    if (_maintenanceHasCanceledInvoiceGlobal(request, invoices)) continue;
    if (!_matchesPeriodicMaintenanceRequestGlobal(
      request,
      propertyId: propertyId,
      type: type,
    )) {
      continue;
    }
    if (_maintenanceAnchorGlobal(request) != normalizedAnchor) {
      continue;
    }
    if (latest == null || request.createdAt.isAfter(latest.createdAt)) {
      latest = request;
    }
  }
  return latest;
}

bool _hasActivePeriodicMaintenanceRequestGlobal({
  required Box<MaintenanceRequest>? maintenance,
  required Box<Invoice>? invoices,
  required String propertyId,
  required String type,
  required DateTime anchor,
}) {
  return _activePeriodicMaintenanceRequestGlobal(
        maintenance: maintenance,
        invoices: invoices,
        propertyId: propertyId,
        type: type,
        anchor: anchor,
      ) !=
      null;
}

bool _hasCompletedPeriodicMaintenanceRequestGlobal({
  required Box<MaintenanceRequest>? maintenance,
  required String propertyId,
  required String type,
  required DateTime anchor,
}) {
  if (maintenance == null) return false;
  final normalizedAnchor = _dateOnlyGlobal(anchor);
  for (final request in maintenance.values) {
    if (request.isArchived) continue;
    if (request.status != MaintenanceStatus.completed) continue;
    if (!_matchesPeriodicMaintenanceRequestGlobal(
      request,
      propertyId: propertyId,
      type: type,
    )) {
      continue;
    }
    if (_maintenanceAnchorGlobal(request) != normalizedAnchor) {
      continue;
    }
    return true;
  }
  return false;
}

bool _canTrackPeriodicMaintenanceRequestGlobal(
  MaintenanceRequest request,
  Box<Invoice>? invoices,
) {
  if (request.isArchived) return false;
  if (request.status == MaintenanceStatus.canceled) return false;
  if (request.status == MaintenanceStatus.completed) return false;
  if (_maintenanceHasCanceledInvoiceGlobal(request, invoices)) return false;
  return true;
}

MaintenanceRequest? _trackedPeriodicMaintenanceRequestFromConfigGlobal({
  required Box<MaintenanceRequest>? maintenance,
  required Box<Invoice>? invoices,
  required String propertyId,
  required String type,
  required Map<String, dynamic> cfg,
}) {
  if (maintenance == null) return null;
  bool valid(MaintenanceRequest request) {
    return _canTrackPeriodicMaintenanceRequestGlobal(request, invoices) &&
        _matchesPeriodicMaintenanceRequestGlobal(
          request,
          propertyId: propertyId,
          type: type,
        );
  }

  final trackedIds = <String>{
    (cfg['targetId'] ?? '').toString().trim(),
    (cfg['lastGeneratedRequestId'] ?? '').toString().trim(),
  }..removeWhere((id) => id.isEmpty);

  for (final trackedId in trackedIds) {
    final request = maintenance.get(trackedId);
    if (request != null && valid(request)) {
      return request;
    }
  }

  final lastGenerated = _serviceLastGeneratedDateGlobal(cfg);
  if (lastGenerated != null) {
    final request = _activePeriodicMaintenanceRequestGlobal(
      maintenance: maintenance,
      invoices: invoices,
      propertyId: propertyId,
      type: type,
      anchor: lastGenerated,
    );
    if (request != null && valid(request)) {
      return request;
    }
  }

  final trackedCycleDate = _serviceCurrentCycleDateGlobal(cfg);
  if (trackedCycleDate != null) {
    final request = _activePeriodicMaintenanceRequestGlobal(
      maintenance: maintenance,
      invoices: invoices,
      propertyId: propertyId,
      type: type,
      anchor: trackedCycleDate,
    );
    if (request != null && valid(request)) {
      return request;
    }
  }

  final candidates = maintenance.values.where(valid).toList(growable: false);
  if (candidates.length == 1) {
    return candidates.first;
  }

  return null;
}

DateTime? _serviceLastGeneratedDateGlobal(Map<String, dynamic> cfg) {
  final raw = cfg['lastGeneratedRequestDate'];
  if (raw is DateTime) return _dateOnlyGlobal(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return _dateOnlyGlobal(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

bool _serviceNeedsProviderGlobal(String type) =>
    type == 'cleaning' || type == 'elevator';

bool _serviceHasProviderGlobal(String type, Map<String, dynamic> cfg) {
  if (type == 'internet') {
    if (_internetBillingModeGlobal(cfg) != 'owner') return true;
    return (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
  }
  if (!_serviceNeedsProviderGlobal(type)) return true;
  return (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
}

String _serviceAfterLabelGlobal(int days) {
  if (days == 1) return 'غدًا';
  if (days == 2) return 'بعد غد';
  return 'بعد $days أيام';
}

int _serviceRemindDaysGlobal(Map<String, dynamic> cfg) {
  final v = (cfg['remindBeforeDays'] as num?)?.toInt() ?? 0;
  if (v < 0) return 0;
  if (v > 3) return 3;
  return v;
}

String _serviceTodayTitleGlobal(String type) {
  if (type == 'water') {
    return '\u0627\u0644\u064a\u0648\u0645 \u0644\u062f\u064a\u0643 \u0642\u0633\u0637 \u0645\u064a\u0627\u0647';
  }
  if (type == 'electricity') {
    return '\u0627\u0644\u064a\u0648\u0645 \u0644\u062f\u064a\u0643 \u0633\u062f\u0627\u062f \u0643\u0647\u0631\u0628\u0627\u0621';
  }
  if (type == 'internet') {
    return 'اليوم لديك طلب تجديد خدمة إنترنت';
  }
  if (type == 'cleaning') {
    return 'اليوم لديك طلب نظافة';
  }
  if (type == 'elevator') {
    return 'اليوم لديك طلب صيانة مصعد';
  }
  return '\u0627\u0644\u064a\u0648\u0645 \u0644\u062f\u064a\u0643 \u062e\u062f\u0645\u0629 \u062f\u0648\u0631\u064a\u0629';
}

String _serviceRemindTitleGlobal(String type, int days) {
  final after = _serviceAfterLabelGlobal(days);
  if (type == 'water') {
    return '\u0644\u062f\u064a\u0643 \u0642\u0633\u0637 \u0645\u064a\u0627\u0647 $after';
  }
  if (type == 'electricity') {
    return '\u0644\u062f\u064a\u0643 \u0633\u062f\u0627\u062f \u0643\u0647\u0631\u0628\u0627\u0621 $after';
  }
  if (type == 'internet') {
    return 'لديك طلب تجديد خدمة إنترنت $after';
  }
  if (type == 'cleaning') {
    return 'لديك طلب نظافة $after';
  }
  if (type == 'elevator') {
    return 'لديك طلب صيانة مصعد $after';
  }
  return '\u0644\u062f\u064a\u0643 \u062e\u062f\u0645\u0629 \u062f\u0648\u0631\u064a\u0629 $after';
}

String _serviceOverdueTitleGlobal(String type) {
  if (type == 'water') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0642\u0633\u0637 \u0627\u0644\u0645\u064a\u0627\u0647';
  }
  if (type == 'electricity') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0633\u062f\u0627\u062f \u0627\u0644\u0643\u0647\u0631\u0628\u0627\u0621';
  }
  if (type == 'internet') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0637\u0644\u0628 \u062a\u062c\u062f\u064a\u062f \u062e\u062f\u0645\u0629 \u0627\u0644\u0625\u0646\u062a\u0631\u0646\u062a';
  }
  if (type == 'cleaning') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0637\u0644\u0628 \u0627\u0644\u0646\u0638\u0627\u0641\u0629';
  }
  if (type == 'elevator') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0637\u0644\u0628 \u0635\u064a\u0627\u0646\u0629 \u0627\u0644\u0645\u0635\u0639\u062f';
  }
  return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u062e\u062f\u0645\u0629 \u062f\u0648\u0631\u064a\u0629';
}

bool _isSharedUtilityServiceGlobal(String type, Map<String, dynamic> cfg) {
  if (type != 'water' && type != 'electricity') return false;
  final sharedUnitsMode =
      (cfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
  if (sharedUnitsMode == 'shared_percent') return true;
  if (type == 'water') {
    final billingMode =
        (cfg['waterBillingMode'] ?? '').toString().trim().toLowerCase();
    final sharedMethod =
        (cfg['waterSharedMethod'] ?? '').toString().trim().toLowerCase();
    return billingMode == 'shared' ||
        sharedMethod == 'fixed' ||
        sharedMethod == 'percent';
  }
  final billingMode =
      (cfg['electricityBillingMode'] ?? '').toString().trim().toLowerCase();
  final sharedMethod =
      (cfg['electricitySharedMethod'] ?? '').toString().trim().toLowerCase();
  return billingMode == 'shared' || sharedMethod == 'percent';
}

String _sharedUtilityTodayTitleGlobal(String type) {
  if (type == 'water') {
    return 'اليوم موعد فاتورة المياه المشتركة';
  }
  return 'اليوم موعد فاتورة الكهرباء المشتركة';
}

String _sharedUtilityRemindTitleGlobal(String type, int days) {
  final after = _serviceAfterLabelGlobal(days);
  if (type == 'water') {
    return 'لديك فاتورة مياه مشتركة $after';
  }
  return 'لديك فاتورة كهرباء مشتركة $after';
}

String _sharedUtilityOverdueTitleGlobal(String type) {
  if (type == 'water') {
    return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0641\u0627\u062a\u0648\u0631\u0629 \u0627\u0644\u0645\u064a\u0627\u0647 \u0627\u0644\u0645\u0634\u062a\u0631\u0643\u0629';
  }
  return '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0641\u0627\u062a\u0648\u0631\u0629 \u0627\u0644\u0643\u0647\u0631\u0628\u0627\u0621 \u0627\u0644\u0645\u0634\u062a\u0631\u0643\u0629';
}

String? _serviceNotificationAlertTypeGlobal(int delta, int remind) {
  if (delta == 0) return 'today';
  if (delta < 0) return 'overdue';
  if (remind > 0 && delta == remind) return 'remind-$remind';
  return null;
}

String _serviceNotificationTitleGlobal(
  String type,
  Map<String, dynamic> cfg, {
  required int delta,
  required bool isPercentBased,
  required double percent,
}) {
  if (isPercentBased) {
    final pctTxt = percent > 0 ? percent.toStringAsFixed(2) : '0.00';
    if (delta == 0) {
      return type == 'water'
          ? 'اليوم سداد مياه (بنسبة $pctTxt%)'
          : 'اليوم سداد كهرباء (بنسبة $pctTxt%)';
    }
    final after = delta == 1
        ? 'بعد يوم'
        : (delta == 2 ? 'بعد يومين' : 'بعد $delta أيام');
    return type == 'water'
        ? 'سداد مياه $after ($pctTxt%)'
        : 'سداد كهرباء $after ($pctTxt%)';
  }
  if (_isSharedUtilityServiceGlobal(type, cfg)) {
    return delta == 0
        ? _sharedUtilityTodayTitleGlobal(type)
        : _sharedUtilityRemindTitleGlobal(type, delta);
  }
  return delta == 0
      ? _serviceTodayTitleGlobal(type)
      : _serviceRemindTitleGlobal(type, delta);
}

String _serviceNotificationSubtitleGlobal(
  String type,
  Map<String, dynamic> cfg,
  DateTime due, {
  required bool isPercentBased,
}) {
  final label = _isSharedUtilityServiceGlobal(type, cfg)
      ? 'موعد الفاتورة'
      : (isPercentBased ? 'موعد السداد' : 'موعد التنفيذ');
  return '$label: ${_fmtYmdGlobal(due)}';
}

String _serviceNotificationResolvedTitleGlobal(
  String type,
  Map<String, dynamic> cfg, {
  required int delta,
  required bool isPercentBased,
  required double percent,
}) {
  if (delta >= 0) {
    return _serviceNotificationTitleGlobal(
      type,
      cfg,
      delta: delta,
      isPercentBased: isPercentBased,
      percent: percent,
    );
  }
  if (isPercentBased) {
    final pctTxt = percent > 0 ? percent.toStringAsFixed(2) : '0.00';
    return type == 'water'
        ? '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0633\u062f\u0627\u062f \u0645\u064a\u0627\u0647 (\u0628\u0646\u0633\u0628\u0629 $pctTxt%)'
        : '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0633\u062f\u0627\u062f \u0643\u0647\u0631\u0628\u0627\u0621 (\u0628\u0646\u0633\u0628\u0629 $pctTxt%)';
  }
  if (_isSharedUtilityServiceGlobal(type, cfg)) {
    return _sharedUtilityOverdueTitleGlobal(type);
  }
  return _serviceOverdueTitleGlobal(type);
}

String _serviceNotificationResolvedSubtitleGlobal(
  String type,
  Map<String, dynamic> cfg,
  DateTime due, {
  required bool isPercentBased,
  required int delta,
}) {
  if (delta >= 0) {
    return _serviceNotificationSubtitleGlobal(
      type,
      cfg,
      due,
      isPercentBased: isPercentBased,
    );
  }
  final label = _isSharedUtilityServiceGlobal(type, cfg)
      ? '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0627\u0644\u0641\u0627\u062a\u0648\u0631\u0629'
      : (isPercentBased
          ? '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0627\u0644\u0633\u062f\u0627\u062f'
          : '\u0645\u0636\u0649 \u0645\u0648\u0639\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630');
  return '$label: ${_fmtYmdGlobal(due)}';
}

String? _serviceNotificationTargetIdGlobal(
  String type,
  Map<String, dynamic> cfg, {
  MaintenanceRequest? activePeriodicRequest,
}) {
  if (_isSharedUtilityServiceGlobal(type, cfg)) return null;
  final activeId = activePeriodicRequest?.id?.toString().trim() ?? '';
  if (activeId.isNotEmpty) return activeId;
  final trackedId = (cfg['targetId'] ?? '').toString().trim();
  if (trackedId.isEmpty) return null;
  return trackedId;
}

String _periodicMaintenanceTodayTitleByTypeGlobal(String type) {
  if (type == 'internet') {
    return 'لديك طلب تجديد خدمة إنترنت اليوم';
  }
  if (type == 'cleaning') {
    return 'لديك طلب نظافة اليوم';
  }
  if (type == 'elevator') {
    return 'لديك طلب صيانة مصعد اليوم';
  }
  return 'لديك طلب خدمات اليوم';
}

String _periodicMaintenanceOpenTitleByTypeGlobal(String type) {
  if (type == 'internet') {
    return 'لديك طلب تجديد خدمة إنترنت مفتوح';
  }
  if (type == 'cleaning') {
    return 'لديك طلب نظافة مفتوح';
  }
  if (type == 'elevator') {
    return 'لديك طلب صيانة مصعد مفتوح';
  }
  return 'لديك طلب خدمات مفتوح';
}

String _periodicMaintenanceOverdueTitleByTypeGlobal(String type) {
  if (type == 'internet') {
    return 'لديك طلب تجديد خدمة إنترنت متأخر التنفيذ';
  }
  if (type == 'cleaning') {
    return 'لديك طلب نظافة متأخر التنفيذ';
  }
  if (type == 'elevator') {
    return 'لديك طلب صيانة مصعد متأخر التنفيذ';
  }
  return 'لديك طلب خدمات متأخر التنفيذ';
}

String _periodicMaintenanceActiveTitleGlobal(
  MaintenanceRequest request,
  DateTime today,
  DateTime dueAnchor,
) {
  final type = _normalizePeriodicServiceTypeTokenGlobal(
        request.periodicServiceType,
      ) ??
      _normalizePeriodicServiceTypeTokenGlobal(request.title);
  if (type == null) {
    return _maintenanceTodayTitleGlobal(request.title);
  }
  final delta =
      _dateOnlyGlobal(dueAnchor).difference(_dateOnlyGlobal(today)).inDays;
  if (delta < 0) {
    return _periodicMaintenanceOverdueTitleByTypeGlobal(type);
  }
  if (delta == 0) {
    return _periodicMaintenanceTodayTitleByTypeGlobal(type);
  }
  return _serviceRemindTitleGlobal(type, delta);
}

bool _isPeriodicMaintenanceRequestTitleGlobal(String title) {
  final normalized = title.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('\u0646\u0638\u0627\u0641') ||
      normalized.contains('clean') ||
      normalized.contains('\u0645\u0635\u0639\u062f') ||
      normalized.contains('\u0627\u0633\u0627\u0646\u0633\u064a\u0631') ||
      normalized.contains('elevator') ||
      normalized.contains('internet') ||
      normalized.contains('انترنت') ||
      normalized.contains('إنترنت');
}

String _maintenanceTodayTitleGlobal(String maintenanceTitle) {
  final title = maintenanceTitle.trim();
  if (title.isEmpty) {
    return '\u0627\u0644\u064a\u0648\u0645 \u0644\u062f\u064a\u0643 \u0637\u0644\u0628 \u062e\u062f\u0645\u0627\u062a';
  }
  final normalized = title.toLowerCase();
  if (normalized.contains('\u0645\u0635\u0639\u062f') ||
      normalized.contains('\u0627\u0633\u0627\u0646\u0633\u064a\u0631') ||
      normalized.contains('elevator')) {
    return 'تم إنشاء طلب صيانة المصعد';
  }
  if (normalized.contains('\u0646\u0638\u0627\u0641') ||
      normalized.contains('clean')) {
    return 'تم إنشاء طلب نظافة';
  }
  if (normalized.contains('internet') ||
      normalized.contains('انترنت') ||
      normalized.contains('إنترنت')) {
    return 'تم إنشاء طلب تجديد خدمة إنترنت';
  }
  if (_isPeriodicMaintenanceRequestTitleGlobal(title)) {
    return 'تم إنشاء طلب خدمات';
  }
  return '\u0637\u0644\u0628 \u062e\u062f\u0645\u0627\u062a \u0644\u0644\u064a\u0648\u0645';
}

String _maintenanceTodaySubtitleGlobal(
  String maintenanceTitle,
  DateTime anchor,
) {
  final dateText = _fmtYmdGlobal(anchor);
  final title = maintenanceTitle.trim();
  if (title.isEmpty || _isPeriodicMaintenanceRequestTitleGlobal(title)) {
    return '\u0645\u0648\u0639\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630: $dateText';
  }
  return '\u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0637\u0644\u0628: $title\n'
      '\u0645\u0648\u0639\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630: $dateText';
}

String _periodicMaintenanceCreatedTodayTitleGlobal(String maintenanceTitle) {
  final normalized = maintenanceTitle.trim().toLowerCase();
  if (normalized.contains('\u0645\u0635\u0639\u062f') ||
      normalized.contains('\u0627\u0633\u0627\u0646\u0633\u064a\u0631') ||
      normalized.contains('elevator')) {
    return 'تم إنشاء طلب صيانة المصعد لليوم';
  }
  if (normalized.contains('\u0646\u0638\u0627\u0641') ||
      normalized.contains('clean')) {
    return 'تم إنشاء طلب نظافة لليوم';
  }
  if (normalized.contains('internet') ||
      normalized.contains('Ø§Ù†ØªØ±Ù†Øª') ||
      normalized.contains('Ø¥Ù†ØªØ±Ù†Øª')) {
    return 'تم إنشاء طلب تجديد خدمة إنترنت لليوم';
  }
  return 'تم إنشاء طلب خدمات لليوم';
}

String _periodicMaintenanceCreatedNotificationTitleGlobal(
  MaintenanceRequest request,
  DateTime today,
  DateTime dueAnchor,
) {
  final type = _normalizePeriodicServiceTypeTokenGlobal(
        request.periodicServiceType,
      ) ??
      _normalizePeriodicServiceTypeTokenGlobal(request.title);
  final delta =
      _dateOnlyGlobal(dueAnchor).difference(_dateOnlyGlobal(today)).inDays;
  if (type == null) {
    if (delta < 0) return 'لديك طلب خدمات مفتوح';
    if (delta == 0) return 'لديك طلب خدمات اليوم';
    return 'لديك طلب خدمات قادم';
  }
  if (delta < 0) {
    return _periodicMaintenanceOverdueTitleByTypeGlobal(type);
  }
  if (delta == 0) {
    return _periodicMaintenanceTodayTitleByTypeGlobal(type);
  }
  return _serviceRemindTitleGlobal(type, delta);
}

DateTime _periodicMaintenanceSortAnchorGlobal(DateTime today, DateTime anchor) {
  final normalizedToday = _dateOnlyGlobal(today);
  final normalizedAnchor = _dateOnlyGlobal(anchor);
  return normalizedAnchor.isBefore(normalizedToday)
      ? normalizedToday
      : normalizedAnchor;
}

DateTime _periodicServiceTodaySortKeyGlobal(DateTime anchor) {
  final day = _dateOnlyGlobal(anchor);
  return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}

int _periodicServiceTodayOrderBaseGlobal(MaintenanceRequest request) =>
    request.createdAt.millisecondsSinceEpoch * 10;

// ???? ?.?^??'? ?S??????. ??S ??"???? ?^??"????
bool isDismissed({
  required Box<String> dismissedBox,
  required NotificationKind kind,
  String? cid,
  String? iid,
  String? mid,
  required DateTime anchor,
}) {
  final kNew = stableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);
  final kOld =
      legacyStableKey(kind, cid: cid, iid: iid, mid: mid, anchor: anchor);

  // ?"? ???????. ??"?.???? ??"???. (ANY) ???? ?"? ???.??? ????^? ??"?????S???? ????"? ?.???"??
  // ?"???? ??"??,? ??^ ??"???? (?.??"??< ?.?? "?,???" ??"?? "?.??????S").
  return dismissedBox.containsKey(kNew) || dismissedBox.containsKey(kOld);
}

// ==============================
// ???.?^?? ??"?????S??
// ==============================
class AppNotification {
  final NotificationKind kind;
  final String title;
  final String subtitle;
  final String? contractId;
  final String? invoiceId;
  final String? maintenanceId;
  final String? propertyId;
  final String? serviceType;
  final String? serviceTargetId;

  /// ?"?"??? (??"???? ??.???S?<? ??^?"?<?)
  final DateTime sortKey;

  /// ?.???? ????? ?"??f?^?S?? ??"???^?S?/??"?????
  final DateTime anchor;

  /// ????S? ??"????^? ??"??^?" (??f?? = ???? ????^??<?)
  final int appearOrder;

  AppNotification({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sortKey,
    required this.anchor,
    required this.appearOrder,
    this.contractId,
    this.invoiceId,
    this.maintenanceId,
    this.propertyId,
    this.serviceType,
    this.serviceTargetId,
  });
}

// ==============================
// ?.???^?? ????S? ?S???? ???? ???^?? ?????^?, Hive
// ==============================
class _OrderStore {
  final Box<int>? _box;
  final Map<String, int> _mem = {};
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  _OrderStore._(this._box);

  static _OrderStore createSync(String logicalName) {
    final name = boxName(logicalName);
    try {
      final b = Hive.box<int>(name);
      return _OrderStore._(b);
    } catch (_) {
      // ?????^?" ????? ???"??"??S??O ?^?"?^ ???" ?S??,?? ??"???f?? ??"?.??,?? ????"? ???^?? ?f???
      try {
        Hive.openBox<int>(name);
      } catch (_) {}
      return _OrderStore._(null);
    }
  }

  Listenable listenable() => _box?.listenable() ?? _tick;

  int? get(String key) => _box?.get(key) ?? _mem[key];

  void put(String key, int value) {
    if (_box != null) {
      _box.put(key, value);
    } else {
      _mem[key] = value;
      _tick.value++; // ?S?^?,? ??"?? AnimatedBuilder
    }
  }

  int getCounter() {
    const ck = '__counter__';
    if (_box != null) return _box.get(ck, defaultValue: 0) ?? 0;
    return _mem[ck] ?? 0;
  }

  int bumpCounter() {
    final next = getCounter() + 1;
    put('__counter__', next);
    return next;
  }
}

// ==============================
// Merged Listenable
// ==============================
class _MergedListenable extends ChangeNotifier {
  final List<Listenable> _sources;
  final List<VoidCallback> _removers = [];
  _MergedListenable(this._sources) {
    for (final s in _sources) {
      s.addListener(_onChange);
      _removers.add(() => s.removeListener(_onChange));
    }
  }
  void _onChange() => notifyListeners();
  @override
  void dispose() {
    for (final r in _removers) {
      try {
        r();
      } catch (_) {}
    }
    _removers.clear();
    super.dispose();
  }
}

// ==============================
// ???? ??"?????S????
// ==============================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  Box<Contract>? _contracts;
  Box<Invoice>? _invoices;
  Box<MaintenanceRequest>? _maintenance;
  Box<Map>? _servicesConfig;
  Box<String>? _dismissed; // notificationsDismissed
  Box<String>? _stickyMaint; // notificationsStickyMaintenance

  Box<String>? _knownContracts; // notificationsKnownContracts
  Box<String>? _pinnedKinds; // notificationsPinnedKind
  late final _OrderStore _order; // notificationsOrder (??^ ???f??)
  _MergedListenable? _merged;
  List<AppNotification> _items = const [];
  bool _openingNotificationTarget = false;

  Future<void>? _ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });

    _order = _OrderStore.createSync('notificationsOrder');
    _ready = _ensureOpenAndWire();
  }

  Future<void> _ensureOpenAndWire() async {
    Future<void> openIfNeeded<T>(String logical) async {
      final real = boxName(logical);
      if (!Hive.isBoxOpen(real)) {
        await Hive.openBox<T>(real);
      }
    }

    await Future.wait([
      openIfNeeded<Contract>('contractsBox'),
      openIfNeeded<Invoice>('invoicesBox'),
      openIfNeeded<MaintenanceRequest>('maintenanceBox'),
      openIfNeeded<Map>('servicesConfig'),
      openIfNeeded<String>('notificationsDismissed'),
      openIfNeeded<String>('notificationsStickyMaintenance'),

      openIfNeeded<String>('notificationsKnownContracts'),
      openIfNeeded<String>('notificationsPinnedKind'),
      // ????S???S: ????S? ??"????^?
      openIfNeeded<int>('notificationsOrder'),
    ]);

    _contracts = Hive.box<Contract>(boxName('contractsBox'));
    _invoices = Hive.box<Invoice>(boxName('invoicesBox'));
    _maintenance = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
    _servicesConfig = Hive.box<Map>(boxName('servicesConfig'));
    await ensurePeriodicServiceRequestsGenerated(
      servicesBox: _servicesConfig,
      maintenanceBox: _maintenance,
      invoicesBox: _invoices,
    );
    _dismissed = Hive.box<String>(boxName('notificationsDismissed'));
    _stickyMaint = Hive.box<String>(boxName('notificationsStickyMaintenance'));

    _knownContracts = Hive.box<String>(boxName('notificationsKnownContracts'));
    _pinnedKinds = Hive.box<String>(boxName('notificationsPinnedKind'));
    _pinnedKinds = Hive.box<String>(boxName('notificationsPinnedKind'));

    _merged = _MergedListenable([
      _contracts!.listenable(),
      _invoices!.listenable(),
      _maintenance!.listenable(),
      _servicesConfig!.listenable(),
      _dismissed!.listenable(),
      if (_stickyMaint != null) _stickyMaint!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      if (_pinnedKinds != null) _pinnedKinds!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      _order.listenable(),
    ]);

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _merged?.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _serviceConfigForNotification(AppNotification n) {
    final propertyId = (n.propertyId ?? '').trim();
    final serviceType = (n.serviceType ?? '').trim();
    if (propertyId.isEmpty || serviceType.isEmpty || _servicesConfig == null) {
      return null;
    }
    final raw = _servicesConfig!.get('$propertyId::$serviceType');
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  // ==============================
  // Helpers ??^???S?/?????
  // ==============================
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _todayDateOnly() => _dateOnly(KsaTime.now());
  int _daysBetween(DateTime a, DateTime b) =>
      _dateOnly(b).difference(_dateOnly(a)).inDays;

  int _monthsPerCycle(PaymentCycle c) {
    switch (c) {
      case PaymentCycle.monthly:
        return 1;
      case PaymentCycle.quarterly:
        return 3;
      case PaymentCycle.semiAnnual:
        return 6;
      case PaymentCycle.annual:
        return 12;
    }
  }

  int _monthsPerCycleForContract(Contract c) {
    if (c.paymentCycle == PaymentCycle.annual) {
      final years = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
      return 12 * years;
    }
    return _monthsPerCycle(c.paymentCycle);
  }

  int _monthsInTerm(ContractTerm t) {
    switch (t) {
      case ContractTerm.daily:
        return 0;
      case ContractTerm.monthly:
        return 1;
      case ContractTerm.quarterly:
        return 3;
      case ContractTerm.semiAnnual:
        return 6;
      case ContractTerm.annual:
        return 12;
    }
  }

  DateTime _addMonths(DateTime d, int months) {
    if (months == 0) return _dateOnly(d);
    final y0 = d.year, m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final lastDay =
        (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
    final safeDay = d.day > lastDay ? lastDay : d.day;
    return _dateOnly(DateTime(y, m, safeDay));
  }

  int _coveredMonthsByAdvance(Contract c) {
    if (c.advanceMode != AdvanceMode.coverMonths) return 0;
    if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
    final months = _monthsInTerm(c.term);
    if (months <= 0) return 0;
    final monthlyValue = c.totalAmount / months;
    final covered = ((c.advancePaid ?? 0) / monthlyValue).floor();
    return covered.clamp(0, months);
  }

  DateTime? _firstDueAfterAdvance(Contract c) {
    if (c.term == ContractTerm.daily) return null;
    final start = _dateOnly(c.startDate), end = _dateOnly(c.endDate);
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      final termMonths = _monthsInTerm(c.term);
      if (covered >= termMonths) return null;
      final mpc = _monthsPerCycleForContract(c);
      final cyclesCovered = (covered / mpc).ceil();
      final first = _addMonths(start, cyclesCovered * mpc);
      if (!first.isBefore(start) && !first.isAfter(end)) return first;
      return null;
    }
    return start;
  }

  /// ??.?S? ??^???S? ?????,??, ??"????? (??,??? ??"??,?) ??? ???. ??"????? ??"?.???? ???"?.?,??.
  /// ???????.??? ?"????? ?????S???? "???? ?.????,? / ???? ?.?????" ???S? ????? ?f?" ???? ??????S?? ?.???,?".
  List<DateTime> _allInstallmentDueDates(Contract c) {
    final List<DateTime> out = [];
    if (c.term == ContractTerm.daily) return out;

    DateTime start;
    DateTime end;
    try {
      start = _dateOnly(c.startDate);
      end = _dateOnly(c.endDate);
    } catch (_) {
      return out;
    }

    final termMonths = _monthsInTerm(c.term);
    if (termMonths <= 0) return out;
    final mpc = _monthsPerCycleForContract(c);
    if (mpc <= 0) return out;

    final totalCycles = (termMonths / mpc).ceil();

    int startCycle = 0;
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      if (covered >= termMonths) return out;
      final cyclesCovered = (covered / mpc).ceil();
      startCycle = cyclesCovered;
    }

    for (int i = startCycle; i < totalCycles; i++) {
      final due = _addMonths(start, i * mpc);
      final d0 = _dateOnly(due);
      if (d0.isBefore(start) || d0.isAfter(end)) continue;
      out.add(d0);
    }

    return out;
  }

  bool _isContractDueToday(Contract c) {
    if (c.term == ContractTerm.daily) return false;
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first) == _todayDateOnly();
  }

  bool _isContractOverdue(Contract c) {
    final today = _todayDateOnly();
    if (c.term == ContractTerm.daily) {
      return c.isExpiredByTime;
    }
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first).isBefore(today);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  // ?,??" ??"???^?: ?S??? ???^? ??"?????S?? ?"??^?" ????^? ?"?.???? (id + anchor) ???? ?"? ?S???S? ?"???,?<?
  NotificationKind _lockKind(NotificationKind proposed,
      {String? cid, required DateTime anchor}) {
    // ?"?. ???? ?????'? ??^?" ???^? ?S?????> ????.? ?"?"?????S?? ???? ?S???S?'?
    // ?.?? "?,??? ??"?? ??"????????" ??"?? "?.??????" ??^ ?.?? "?.????, ??"?S?^?." ??"?? "?.????"
    // ???? ???"? ??"??,? ??^ ?????,??,???? ??S ?f?" ????? ??^?"?S?.
    return proposed;
  }

// ???,? ??^?" ?.?????? ?"?"??,? ?"????S?, ??"??,?^? ??"?.???? ???S??<?
  void _markContractSeen(String? cid) {
    if (cid == null || _knownContracts == null) return;
    if (!_knownContracts!.containsKey(cid)) {
      try {
        _knownContracts!.put(cid, _dateOnly(KsaTime.now()).toIso8601String());
      } catch (_) {}
    }
  }

  DateTime? _firstSeen(String? cid) {
    if (cid == null || _knownContracts == null) return null;
    final s = _knownContracts!.get(cid);
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  bool _existedBeforeDate(String? cid, DateTime date) {
    final fs = _firstSeen(cid);
    if (fs == null) return false;
    return _dateOnly(fs).isBefore(_dateOnly(date));
  }

  // =====================================
  // ???,??. ??"??,?^?: ????S? + ??? ?.?^??^?,
  // =====================================

  // ???"?S? LTR ?"????S? ?????? ??,?. ?.??" 2025-0003 ????" RTL
  String _ltr(Object? v) {
    final s = (v == null) ? '' : v.toString();
    if (s.isEmpty) return s;
    return '\u200E$s\u200E';
  }

  // ????S?: ?"?^ ??"??,?. ?.???'?Z?? ?f?? "0003-2025" ???,?"??? ??"?? "2025-0003"
  String _normalizeSerial(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return v;
    final parts = v.split('-');
    if (parts.length == 2) {
      final a = parts[0].trim();
      final b = parts[1].trim();
      bool isYear(String x) {
        final n = int.tryParse(x);
        return n != null && x.length == 4 && n >= 1900 && n <= 2100;
      }

      if (!isYear(a) && isYear(b)) {
        // seq-year => year-seq
        final seq = a.padLeft(4, '0');
        return '$b-$seq';
      }
    }
    return v;
  }

  // ?S??S? "??,?. ??"??,?" ?f?.? ??S ????,? ??"??,?^? (serialNo ??^?"?<??O ??. ??,?^?" ???S?"?)?O ???^?? ??"??,?^? ??"?? id
  String _contractLabel(Contract c) {
    try {
      final d = c as dynamic;
      final cand = [
        d.serialNo,
        d.number,
        d.contractNumber,
        d.code,
        d.ref,
        d.displayNo,
        d.displayId,
        d.serial,
      ].firstWhere(
        (v) => v != null && v.toString().trim().isNotEmpty,
        orElse: () => null,
      );
      if (cand != null) {
        final t = _normalizeSerial(cand.toString().trim());
        return _ltr(t);
      }
    } catch (_) {}
    return '';
  }

  // ??????? ??? ??,?. ??"??,? ?.?? ??"Box ???"?.??? (?"? ????? ??"id ??"??^?S?" ???"??,?<?)
  String contractTextById(String? cid) {
    if (cid == null || _contracts == null) return '';
    try {
      final c = _contracts!.get(cid);
      if (c != null) {
        final s = _contractLabel(c);
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return '';
  }

  // ==============================
  // ?.????S? ?^????S? ????^?
  // ==============================
  String _stableKey(NotificationKind k,
      {String? cid, String? iid, String? mid, required DateTime anchor}) {
    final id = cid ?? iid ?? mid ?? 'na';
    return '${k.name}:$id:${_dateOnly(anchor).toIso8601String()}';
  }

  int _ensureAppearOrder(String stableKeyStr) {
    final existing = _order.get(stableKeyStr);
    if (existing != null) return existing;
    final next = _order.bumpCounter();
    _order.put(stableKeyStr, next);
    return next;
  }

  // ==============================
  // ??^?"?S? ??"?????S????
  // ==============================
  List<AppNotification> _generate() {
    final today = _todayDateOnly();
    final out = <AppNotification>[];
    final handledPeriodicMaintenanceIds = <String>{};

    void addPeriodicTodayPair({
      required MaintenanceRequest request,
      required DateTime anchor,
    }) {
      final sortKey = _periodicServiceTodaySortKeyGlobal(
        _periodicMaintenanceSortAnchorGlobal(today, anchor),
      );
      final baseOrder = _periodicServiceTodayOrderBaseGlobal(request);
      final notificationAnchor = _dateOnlyGlobal(today);
      out.add(AppNotification(
        kind: NotificationKind.maintenanceToday,
        title: _periodicMaintenanceActiveTitleGlobal(request, today, anchor),
        subtitle: _maintenanceTodaySubtitleGlobal(request.title, anchor),
        sortKey: sortKey,
        anchor: notificationAnchor,
        appearOrder: baseOrder + 1,
        maintenanceId: request.id?.toString(),
      ));
      final requestId = request.id?.toString();
      if (requestId != null && requestId.isNotEmpty) {
        handledPeriodicMaintenanceIds.add(requestId);
      }
    }

    void addPeriodicCreatedTodayNotification({
      required MaintenanceRequest request,
      required DateTime dueAnchor,
    }) {
      final requestId = request.id?.toString();
      if (requestId == null || requestId.isEmpty) return;
      if (handledPeriodicMaintenanceIds.contains(requestId)) return;
      final todayAnchor = _dateOnlyGlobal(today);
      final skey = _stableKey(
        NotificationKind.maintenanceToday,
        mid: requestId,
        anchor: todayAnchor,
      );
      final order = _ensureAppearOrder(skey);
      out.add(AppNotification(
        kind: NotificationKind.maintenanceToday,
        title: _periodicMaintenanceCreatedNotificationTitleGlobal(
          request,
          today,
          dueAnchor,
        ),
        subtitle: _maintenanceTodaySubtitleGlobal(request.title, dueAnchor),
        sortKey: _periodicServiceTodaySortKeyGlobal(todayAnchor),
        anchor: todayAnchor,
        appearOrder: order,
        maintenanceId: requestId,
      ));
      handledPeriodicMaintenanceIds.add(requestId);
    }

    // --- ??,?^? ---
    for (final c in _contracts!.values) {
      try {
        if ((c as dynamic).isArchived == true) continue;
        if ((c as dynamic).isTerminated == true) {
          continue; // ?Y'^ ??????? ??"??,?^? ??"?.??????S? ?.??f??<?
        }
      } catch (_) {}
      final String? cid = (() {
        try {
          return (c as dynamic).id?.toString();
        } catch (_) {
          return null;
        }
      })();

      // ??,? ??? ??"?S?^?. (??,? ??? ?f??? ??"??,? ?.?^??^??<? ?,??" ??"?S?^?. ?^?"?. ?S?f?? ?.????<? ???S??<?)
      DateTime? start0;
      try {
        start0 = (c as dynamic).startDate as DateTime?;
      } catch (_) {}
      if (start0 != null) {
        final d0 = _dateOnly(start0);
        if (d0 == today && _existedBeforeDate(cid, d0)) {
          final anchor = d0;
          final skey = _stableKey(NotificationKind.contractStartedToday,
              cid: cid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: NotificationKind.contractStartedToday,
            title: 'اليوم يبدأ عقد جديد',
            subtitle: 'تاريخ البداية: ${_fmt(start0)}',
            sortKey: today,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }
      // ???" "??^?" ?.??????" ?"???? ??"??,?
      _markContractSeen(cid);

      // ???"? ??,?. ??"??,? ?"?"??? (???^?? ??"??,?^? ??"?? id)
      final label = _contractLabel(c);
      final contractText = label.isNotEmpty ? label : 'عقد';

      DateTime? end;
      try {
        end = (c as dynamic).endDate as DateTime?;
      } catch (_) {}
      if (end != null) {
        final ended = _dateOnly(end).isBefore(today);
        final daysToEnd = _daysBetween(today, end);

        if (ended) {
          final anchor = _dateOnly(end);
          const proposed = NotificationKind.contractEnded;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: finalKind,
            title: 'انتهى العقد',
            subtitle: 'تاريخ الانتهاء: ${_fmt(end)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        } else if (daysToEnd >= 0 && daysToEnd <= 7) {
          final anchor = _dateOnly(end);
          const proposed = NotificationKind.contractExpiring;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: finalKind,
            title: 'العقد على وشك الانتهاء',
            subtitle: 'تاريخ الانتهاء: ${_fmt(end)}',
            sortKey: today,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }

      // ?????,??,?? ??,?: ??????S ?????S?? ?.???,?" ?"?f?" ???? (?,??) ?.????,? ??^ ?.?????
      try {
        final Contract cObj = c;
        if (cObj.term != ContractTerm.daily) {
          final dues = _allInstallmentDueDates(cObj);
          for (final due in dues) {
            final delta =
                _daysBetween(due, today); // ??"?S?^?. - ????S? ??"?????,??,
            final daysAhead =
                -delta; // ?f?. ?S?^?. ???,?S ??"?? ??"?????,??, (?.?^?? = ??S ??"?.???,??")

            // ??????" ??"????? ??"???S?? ????< (??f?? ?.?? 7 ??S??. ?,??" ??"?????,??,)
            if (delta < 0 && daysAhead > 7) continue;

            final anchor = _dateOnly(due);
            NotificationKind kind;
            String title;
            String subtitle;

            if (delta < 0) {
              // ???? ?,??S?? (?"?. ?S??? ?.?^????? ??? ?"?f?? ??"??" 7 ??S??.)
              kind = NotificationKind.contractDueSoon;
              title = 'موعد سداد قادم';
              subtitle = 'تاريخ الاستحقاق: ${_fmt(due)}';
            } else if (delta == 0) {
              // ???? ?.????,? ??"?S?^?.
              kind = NotificationKind.contractDueToday;
              title = 'سداد مستحق اليوم';
              subtitle = 'تاريخ الاستحقاق: ${_fmt(due)}';
            } else {
              // ???? ?.?????
              kind = NotificationKind.contractDueOverdue;
              title = 'سداد متأخر';
              subtitle = 'تاريخ الاستحقاق: ${_fmt(due)}';
            }

            final skey = _stableKey(kind, cid: cid, anchor: anchor);
            final order = _ensureAppearOrder(skey);
            out.add(AppNotification(
              kind: kind,
              title: title,
              subtitle: subtitle,
              sortKey: anchor,
              anchor: anchor,
              appearOrder: order,
              contractId: cid,
            ));
          }
        }
      } catch (_) {}
      _markContractSeen(cid);
    }

// --- ??^???S? ---
    for (final inv in _invoices!.values) {
      try {
        if ((inv as dynamic).isArchived == true) continue;
        final isPaid = (inv as dynamic).isPaid == true;
        if (isPaid) continue;
        final due = (inv as dynamic).dueDate as DateTime?;
        final iid = (inv as dynamic).id?.toString();
        final cid = (inv as dynamic).contractId?.toString();
        if (due == null) continue;

        final delta = _daysBetween(due, today);
        final anchor = _dateOnly(due);
        final skey = _stableKey(NotificationKind.invoiceOverdue,
            iid: iid, anchor: anchor);
        final order = _ensureAppearOrder(skey);

        // ????? ??"????^??? ??"????S ???^?? ?????" ??"???" ?"??????? ????? ??"???.?S?
        String buildInvoiceSubtitle(String statusText) {
          final cText = contractTextById(cid);
          String s = 'فاتورة ${_ltr(iid)}';
          if (cText.isNotEmpty) {
            s += ' لعقد $cText';
          }
          s += ' $statusText (${_fmt(due)})';
          return s;
        }

        if (delta == 0) {
          out.add(AppNotification(
            kind: NotificationKind.invoiceOverdue,
            title: delta == 0 ? 'فاتورة مستحقة اليوم' : 'فاتورة متأخرة',
            subtitle: 'تاريخ الاستحقاق: ${_fmt(due)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            invoiceId: iid,
            contractId: cid,
          ));
        } else if (delta > 0) {
          out.add(AppNotification(
            kind: NotificationKind.invoiceOverdue,
            title: 'فاتورة متأخرة',
            subtitle: 'تاريخ الاستحقاق: ${_fmt(due)}',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            invoiceId: iid,
            contractId: cid,
          ));
        }
      } catch (_) {}
    }

    // ??? ???????S: (1) sortKey ??????"?S ??. (2) appearOrder ??????"??
    for (final entry in _servicesConfig!.toMap().entries) {
      try {
        final key = entry.key.toString();
        final raw = entry.value;
        final cfg = Map<String, dynamic>.from(raw);
        final type = (cfg['serviceType'] ?? '').toString();
        if (type != 'cleaning' &&
            type != 'elevator' &&
            type != 'water' &&
            type != 'internet' &&
            type != 'electricity') {
          continue;
        }
        final isWaterSharedFixed = type == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString() == 'fixed';
        final isWaterSharedPercent = type == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString() == 'percent';
        final isElectricitySharedPercent = type == 'electricity' &&
            (cfg['electricityBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['electricitySharedMethod'] ?? '').toString() == 'percent';
        final isPercentBased =
            isWaterSharedPercent || isElectricitySharedPercent;
        final isPeriodicMaintenanceService =
            type == 'cleaning' ||
            type == 'elevator' ||
            (type == 'internet' && _internetBillingModeGlobal(cfg) == 'owner');
        final pid = key.split('::').first;
        final suppressedDate = _serviceSuppressedDateGlobal(cfg);
        final trackedPeriodicRequest = isPeriodicMaintenanceService
            ? _trackedPeriodicMaintenanceRequestFromConfigGlobal(
                maintenance: _maintenance,
                invoices: _invoices,
                propertyId: pid,
                type: type,
                cfg: cfg,
              )
            : null;
        if (!_serviceHasProviderGlobal(type, cfg)) {
          continue;
        }
        if (!isWaterSharedFixed &&
            !isPercentBased &&
            (cfg['payer'] ?? 'owner').toString() != 'owner') {
          continue;
        }
        final start = _serviceStartDateGlobal(cfg);
        if (!isPeriodicMaintenanceService &&
            start != null &&
            _daysBetween(today, start) == 0) {
          final pid = key.split('::').first;
          final alertMid = '$key#serviceStart';
          final skey = _stableKey(NotificationKind.serviceStart,
              mid: alertMid, anchor: start);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: NotificationKind.serviceStart,
            title: type == 'cleaning'
                ? '\u0627\u0644\u064a\u0648\u0645 \u064a\u062c\u0628 \u0628\u062f\u0621 \u0623\u0639\u0645\u0627\u0644 \u0627\u0644\u0646\u0638\u0627\u0641\u0629'
                : '\u0627\u0644\u064a\u0648\u0645 \u064a\u062c\u0628 \u0628\u062f\u0621 \u0635\u064a\u0627\u0646\u0629 \u0627\u0644\u0645\u0635\u0639\u062f',
            subtitle:
                '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0628\u062f\u0621: ${_fmtYmdGlobal(start)}',
            sortKey: start,
            anchor: start,
            appearOrder: order,
            maintenanceId: alertMid,
            propertyId: pid,
            serviceType: type,
            serviceTargetId: cfg['targetId']?.toString(),
          ));
        }
        if (trackedPeriodicRequest != null) {
          final trackedDue = _maintenanceAnchorGlobal(trackedPeriodicRequest);
          final trackedDelta = _daysBetween(today, trackedDue);
          final remind = _serviceRemindDaysGlobal(cfg);
          if (trackedDelta == 0 ||
              (trackedDelta > 0 &&
                  remind > 0 &&
                  trackedDelta == remind)) {
            addPeriodicTodayPair(
              request: trackedPeriodicRequest,
              anchor: trackedDue,
            );
            continue;
          }
          if (trackedDelta < 0) {
            if (_dateOnlyGlobal(trackedPeriodicRequest.createdAt) == today) {
              addPeriodicCreatedTodayNotification(
                request: trackedPeriodicRequest,
                dueAnchor: trackedDue,
              );
            } else {
              addPeriodicTodayPair(
                request: trackedPeriodicRequest,
                anchor: trackedDue,
              );
            }
          }
          continue;
        }
        final generatedToday = _serviceLastGeneratedDateGlobal(cfg);
        if (generatedToday != null && _daysBetween(today, generatedToday) == 0) {
          final activePeriodicRequest = isPeriodicMaintenanceService
              ? _activePeriodicMaintenanceRequestGlobal(
                  maintenance: _maintenance,
                  invoices: _invoices,
                  propertyId: pid,
                  type: type,
                  anchor: generatedToday,
                )
              : null;
          final hasCompletedRequest = isPeriodicMaintenanceService &&
              _hasCompletedPeriodicMaintenanceRequestGlobal(
                maintenance: _maintenance,
                propertyId: pid,
                type: type,
                anchor: generatedToday,
              );
          final hasActiveRequest =
              !isPeriodicMaintenanceService || activePeriodicRequest != null;
          if (hasCompletedRequest) {
            continue;
          }
          if (isPeriodicMaintenanceService &&
              suppressedDate != null &&
              _dateOnlyGlobal(suppressedDate) == _dateOnlyGlobal(generatedToday) &&
              !hasActiveRequest) {
            continue;
          }
          if (activePeriodicRequest != null) {
            addPeriodicTodayPair(
              request: activePeriodicRequest,
              anchor: generatedToday,
            );
            continue;
          }
          final alertMid = '$key#today';
          final skey = _stableKey(NotificationKind.serviceDue,
              mid: alertMid, anchor: generatedToday);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: NotificationKind.serviceDue,
            title: _serviceTodayTitleGlobal(type),
            subtitle: isPercentBased
                ? 'موعد السداد: ${_fmtYmdGlobal(generatedToday)}'
                : 'موعد التنفيذ: ${_fmtYmdGlobal(generatedToday)}',
            sortKey: generatedToday,
            anchor: generatedToday,
            appearOrder: order,
            maintenanceId: alertMid,
            propertyId: pid,
            serviceType: type,
            serviceTargetId: cfg['targetId']?.toString(),
          ));
          continue;
        }
        final lastGenerated = _serviceLastGeneratedDateGlobal(cfg);
        if (isPeriodicMaintenanceService &&
            lastGenerated != null &&
            _daysBetween(today, lastGenerated) < 0) {
          final activeGeneratedRequest = _activePeriodicMaintenanceRequestGlobal(
            maintenance: _maintenance,
            invoices: _invoices,
            propertyId: pid,
            type: type,
            anchor: lastGenerated,
          );
          if (activeGeneratedRequest != null &&
              _dateOnlyGlobal(activeGeneratedRequest.createdAt) == today) {
            addPeriodicCreatedTodayNotification(
              request: activeGeneratedRequest,
              dueAnchor: lastGenerated,
            );
            continue;
          }
        }
        final due = _serviceCurrentCycleDateGlobal(cfg);
        if (due == null) continue;
        final activePeriodicRequest = isPeriodicMaintenanceService
            ? _activePeriodicMaintenanceRequestGlobal(
                maintenance: _maintenance,
                invoices: _invoices,
                propertyId: pid,
                type: type,
                anchor: due,
              )
            : null;
        final hasActiveRequest =
            !isPeriodicMaintenanceService || activePeriodicRequest != null;
        if (isPeriodicMaintenanceService &&
            suppressedDate != null &&
            _dateOnlyGlobal(suppressedDate) == _dateOnlyGlobal(due) &&
            !hasActiveRequest) {
          continue;
        }
        final delta = _daysBetween(today, due);
        final remind = _serviceRemindDaysGlobal(cfg);
        late String alertType;
        late String title;
        final pct = isWaterSharedPercent
            ? ((cfg['sharePercent'] as num?)?.toDouble() ?? 0.0)
            : (isElectricitySharedPercent
                ? ((cfg['electricitySharePercent'] as num?)?.toDouble() ?? 0.0)
                : 0.0);
        final pctTxt = pct > 0 ? pct.toStringAsFixed(2) : '0.00';
        if (delta <= 0) {
          alertType = delta < 0 ? 'overdue' : 'today';
          if (isPercentBased) {
            title = type == 'water'
                ? 'اليوم سداد مياه (بنسبة $pctTxt%)'
                : 'اليوم سداد كهرباء (بنسبة $pctTxt%)';
          } else {
            title = _serviceTodayTitleGlobal(type);
          }
        } else if (remind > 0 && delta == remind) {
          alertType = 'remind-$remind';
          if (isPercentBased) {
            final after = remind == 1
                ? 'بعد يوم'
                : (remind == 2 ? 'بعد يومين' : 'بعد $remind أيام');
            title = type == 'water'
                ? 'سداد مياه $after ($pctTxt%)'
                : 'سداد كهرباء $after ($pctTxt%)';
          } else {
            title = _serviceRemindTitleGlobal(type, remind);
          }
        } else {
          continue;
        }
        title = _serviceNotificationResolvedTitleGlobal(
          type,
          cfg,
          delta: delta,
          isPercentBased: isPercentBased,
          percent: pct,
        );
        if (delta <= 0 && activePeriodicRequest != null) {
          addPeriodicTodayPair(
            request: activePeriodicRequest,
            anchor: due,
          );
          continue;
        }
        final alertMid = isPercentBased
            ? '$key#percent#$alertType#$pctTxt'
            : '$key#$alertType';
        final skey =
            _stableKey(NotificationKind.serviceDue, mid: alertMid, anchor: due);
        final order = _ensureAppearOrder(skey);
        out.add(AppNotification(
          kind: NotificationKind.serviceDue,
          title: title,
          subtitle: _serviceNotificationResolvedSubtitleGlobal(
            type,
            cfg,
            due,
            isPercentBased: isPercentBased,
            delta: delta,
          ),
          sortKey: due,
          anchor: due,
          appearOrder: order,
          maintenanceId: alertMid,
          propertyId: pid,
          serviceType: type,
          serviceTargetId: _serviceNotificationTargetIdGlobal(
            type,
            cfg,
            activePeriodicRequest: activePeriodicRequest,
          ),
        ));
      } catch (_) {}
    }

    // --- ??S???? ---
    // --- ??S???? ---
    for (final m in _maintenance!.values) {
      try {
        if ((m as dynamic).isArchived == true) continue;
        if ((m as dynamic).status == MaintenanceStatus.canceled) continue;
        if ((m as dynamic).status == MaintenanceStatus.completed) continue;
        if (_maintenanceHasCanceledInvoiceGlobal(m, _invoices)) continue;
        final s = (m as dynamic).scheduledDate as DateTime?;
        final mid = (m as dynamic).id?.toString();
        final maintenanceTitle = (m as dynamic).title?.toString().trim() ?? '';
        if (s == null) continue;
        if (mid != null && handledPeriodicMaintenanceIds.contains(mid)) {
          continue;
        }

        final isToday = _dateOnly(s) == today;

        // ?.???? ?.???? ?"?f?" ??"? ??S????
        final midKey = mid ?? 'na';
        final pinnedIso = _stickyMaint?.get(midKey);
        final DateTime? pinnedAnchor =
            pinnedIso != null ? DateTime.tryParse(pinnedIso) : null;

        // ??^?" ?S?^?. ?S???? ??S?? (??"?S?^?.): ?????'? ??"?.????
        if (isToday && pinnedAnchor == null) {
          try {
            _stickyMaint?.put(midKey, _dateOnly(s).toIso8601String());
          } catch (_) {}
        }

        // ????? ??"?????S?? ??? ?f??? ??"?S?^?. ?.?^???? ??^ ??. ????S??? ????,?<?
        final DateTime anchor = pinnedAnchor ?? _dateOnly(s);
        final bool shouldShow = isToday || pinnedAnchor != null;

        if (shouldShow) {
          final skey = _stableKey(NotificationKind.maintenanceToday,
              mid: mid, anchor: anchor);
          final order = _ensureAppearOrder(skey);
          out.add(AppNotification(
            kind: NotificationKind.maintenanceToday,
            title: _maintenanceTodayTitleGlobal(maintenanceTitle),
            subtitle:
                _maintenanceTodaySubtitleGlobal(maintenanceTitle, anchor),
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            maintenanceId: mid,
          ));
        }
      } catch (_) {}
    }

    out.sort((a, b) {
      final c1 = b.sortKey.compareTo(a.sortKey);
      if (c1 != 0) return c1;
      return b.appearOrder.compareTo(a.appearOrder);
    });

    return out;
  }

  (IconData, Color) _iconOf(NotificationKind k, BuildContext context) {
    switch (k) {
      case NotificationKind.contractExpiring:
        return (Icons.hourglass_top_rounded, Colors.amber.shade700);
      case NotificationKind.contractEnded:
        return (Icons.event_busy_rounded, Colors.blueGrey);
      case NotificationKind.contractStartedToday:
        return (Icons.play_circle_fill_rounded, Colors.green.shade600);
      case NotificationKind.contractDueSoon:
        return (Icons.event_available_rounded, Colors.teal.shade600);
      case NotificationKind.contractDueToday:
        return (Icons.event_available_rounded, Colors.teal.shade600);
      case NotificationKind.contractDueOverdue:
        return (Icons.schedule_rounded, Colors.orange.shade700);
      case NotificationKind.invoiceOverdue:
        return (Icons.warning_rounded, Colors.red.shade600);
      case NotificationKind.maintenanceToday:
        return (
          Icons.build_circle_rounded,
          Theme.of(context).colorScheme.primary
        );
      case NotificationKind.serviceStart:
        return (Icons.play_circle_fill_rounded, Colors.indigo.shade600);
      case NotificationKind.serviceDue:
        return (Icons.miscellaneous_services_rounded, Colors.teal.shade600);
    }
  }

  String _dismissKey(AppNotification n) => _stableKey(n.kind,
      cid: n.contractId,
      iid: n.invoiceId,
      mid: n.maintenanceId,
      anchor: n.anchor);

  String _baseDismissKey(AppNotification n) => anyStableKey(
      cid: n.contractId,
      iid: n.invoiceId,
      mid: n.maintenanceId,
      anchor: n.anchor);

  Future<void> _dismissAll(AppNotification n) async {
    final dis = _dismissed;
    if (dis == null) return;
    try {
      await dis.put(_dismissKey(n), '1');
    } catch (_) {}
    // ?"? ?????'?" ??? ??"??? ??"?.???? ??"???. (ALL) ???? ????.? ?????^? ?????S?? ???S?
    // ???? ???S?'? ???"? ???? ??"??,? ??^ ??"???? (?.??"??< ?.?? "?,???" ??"?? "?.??????S").
  }

  Future<void> _open(AppNotification n) async {
    if (_openingNotificationTarget) return;
    _openingNotificationTarget = true;
    try {
      switch (n.kind) {
        // ?Y"? ?????S???? ??"??,?^? ??' ???? ???? ?????S?" ??"??,? ?.?????
        case NotificationKind.contractExpiring:
        case NotificationKind.contractEnded:
        case NotificationKind.contractDueSoon:
        case NotificationKind.contractDueToday:
        case NotificationKind.contractDueOverdue:
        case NotificationKind.contractStartedToday:
          {
            final cid = n.contractId;
            if (cid != null && cid.isNotEmpty && _contracts != null) {
              Contract? target;
              for (final c in _contracts!.values) {
                if (c.id == cid) {
                  target = c;
                  break;
                }
              }
              if (target != null) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContractDetailsScreen(contract: target!),
                  ),
                );
                break; // ?o. ?"? ???f?.?" ??"?? ??"?? fallback
              }
            }

            // ????S??: ?"?^ ?.? ?"?,?S??? ??"??,? ?"??S ????O ????? ?"?"??"?^?f ??"?,??S?.
            await Navigator.of(context).pushNamed(
              '/contracts',
              arguments: {'openContractId': n.contractId},
            );
            break;
          }

        // ?Y"? ?????S???? ??"??^???S?: ?????f??? ?f?.? ???S (?.? ??????? ??"??? ???? ?????S?" ?.???^?"?)
        case NotificationKind.invoiceOverdue:
          await Navigator.of(context).pushNamed(
            '/invoices',
            arguments: {'openInvoiceId': n.invoiceId},
          );
          break;

        // ?Y"? ?????S?? ??S???? ??"?S?^?. ??' ???? ?????S?" ??"? ??"??S???? ?.?????
        case NotificationKind.maintenanceToday:
          {
            final mid = n.maintenanceId;
            if (mid != null && mid.isNotEmpty && _maintenance != null) {
              MaintenanceRequest? item;
              for (final m in _maintenance!.values) {
                if (m.id == mid) {
                  item = m;
                  break;
                }
              }
              if (item != null) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MaintenanceDetailsScreen(item: item!),
                  ),
                );
                break; // ?o. ?"? ???f?.?" ??"?? ??"?? fallback
              }
            }

            // ????S??: ?"?^ ?.? ?"?,?S??? ??"??"? ?"??S ????O ????? ?"?"??"?^?f ??"?,??S?.
            await Navigator.of(context).pushNamed(
              '/maintenance',
              arguments: {'openMaintenanceId': n.maintenanceId},
            );
            break;
          }
        case NotificationKind.serviceDue:
          {
            final cfg = _serviceConfigForNotification(n);
            final serviceType = (n.serviceType ?? '').trim();
            final opensSharedUtilityDirectly = cfg != null &&
                _isSharedUtilityServiceGlobal(serviceType, cfg);
            final targetId =
                opensSharedUtilityDirectly ? '' : (n.serviceTargetId ?? '').trim();
            if (!opensSharedUtilityDirectly &&
                targetId.isNotEmpty &&
                _maintenance != null) {
              MaintenanceRequest? item;
              for (final m in _maintenance!.values) {
                if (m.id == targetId) {
                  item = m;
                  break;
                }
              }
              if (item != null) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MaintenanceDetailsScreen(item: item!),
                  ),
                );
                break;
              }
            }
            await Navigator.of(context).pushNamed(
              PropertyServicesRoutes.propertyServices,
              arguments: {
                'propertyId': n.propertyId,
                'openService': n.serviceType,
                'openPay': !opensSharedUtilityDirectly,
                'targetId': opensSharedUtilityDirectly ? '' : n.serviceTargetId,
                'openServiceDirectly': opensSharedUtilityDirectly,
              },
            );
            break;
          }
        case NotificationKind.serviceStart:
          {
            await Navigator.of(context).pushNamed(
              PropertyServicesRoutes.propertyServices,
              arguments: {
                'propertyId': n.propertyId,
                'openService': n.serviceType,
                'openPay': false,
                'targetId': n.serviceTargetId,
              },
            );
            break;
          }
      }
    } finally {
      _openingNotificationTarget = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ?"?^ ?"??? ?.? ????S?? ??"??????S?,?O ???? Loader ??S??.? ?????
    if (_merged == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              color: const Color(0xFFE5E7EB),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(
                      0xFF0B1220), // ??^ const Color(0xFF0B1220) ?"?^ ???S?? ???^? ????
                  elevation: 0,
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  leading: darvooLeading(context, iconColor: Colors.white),

                  title: Text(
                    'التنبيهات',
                    style: GoogleFonts.cairo(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),

                // ?o. drawer ?.??.?^?? ??S?? AppBar ?^ BottomNav
                drawer: Builder(
                  builder: (ctx) {
                    final media = MediaQuery.of(ctx);
                    final double topInset = kToolbarHeight + media.padding.top;
                    final double bottomInset =
                        _bottomBarHeight + media.padding.bottom;
                    return Padding(
                      padding:
                          EdgeInsets.only(top: topInset, bottom: bottomInset),
                      child: MediaQuery.removePadding(
                        context: ctx,
                        removeTop: true,
                        removeBottom: true,
                        child: const AppSideDrawer(),
                      ),
                    );
                  },
                ),

                body: const Center(child: CircularProgressIndicator()),

                // ?o. BottomNav ?.????
                bottomNavigationBar: Container(
                  color: const Color(0xFF0B1220),
                  child: AppBottomNav(
                    key: _bottomNavKey,
                    currentIndex: 2,
                    onTap: _handleBottomTap,
                  ),
                ),
              ),
            ),
          ));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: const Color(0xFFE5E7EB),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: const Color(
                  0xFF0B1220), // ??^ const Color(0xFF0B1220) ?"?^ ???S?? ???^? ????
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              leading: darvooLeading(context, iconColor: Colors.white),

              title: Text(
                'التنبيهات',
                style: GoogleFonts.cairo(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),

            // ?o. drawer ?.??.?^?? ??S?? AppBar ?^ BottomNav
            drawer: Builder(
              builder: (ctx) {
                final media = MediaQuery.of(ctx);
                final double topInset = kToolbarHeight + media.padding.top;
                final double bottomInset =
                    _bottomBarHeight + media.padding.bottom;
                return Padding(
                  padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                  child: MediaQuery.removePadding(
                    context: ctx,
                    removeTop: true,
                    removeBottom: true,
                    child: const AppSideDrawer(),
                  ),
                );
              },
            ),

            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: AnimatedBuilder(
                animation: _merged!,
                builder: (context, _) {
                  _items = _generate();

                  // ???????? ??"?.???^? (???. ???S? + ????S)
                  final visible = _items
                      .where((n) => !isDismissed(
                            dismissedBox: _dismissed!,
                            kind: n.kind,
                            cid: n.contractId,
                            iid: n.invoiceId,
                            mid: n.maintenanceId,
                            anchor: n.anchor,
                          ))
                      .toList();

                  if (visible.isEmpty) return _EmptyState();

                  return ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, i) {
                      final n = visible[i];
                      final (icon, color) = _iconOf(n.kind, context);
                      final k = _dismissKey(n); // ???f?? ???"?.???? ??"???S?

                      return Dismissible(
                        key: ValueKey(k),
                        direction: DismissDirection.startToEnd,
                        onDismissed: (_) async {
                          if (await OfficeClientGuard.blockIfOfficeClient(
                              context)) {
                            return;
                          }
                          await _dismissAll(n);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Text('تمت قراءة التنبيه',
                                  style: GoogleFonts.cairo(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        child: _NotifCard(
                          icon: icon,
                          color: color,
                          title: n.title,
                          subtitle: n.subtitle,
                          onTap: () => _open(n),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ?o. BottomNav ?.????
            bottomNavigationBar: Container(
              color: const Color(0xFF0B1220),
              child: AppBottomNav(
                key: _bottomNavKey,
                currentIndex: 2,
                onTap: _handleBottomTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ?o. ???"? ??"????,?" ??"???"?S ????" ??"?f?"??
  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }
}

// ==============================
// Widgets ?.?????
// ==============================
class _NotifCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NotifCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.r),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: color, size: 26.w),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_off_rounded,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'لا توجد تنبيهات حالياً',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================
// ???? ??S ?"??? ??"?????S???? (?"???????.?? ??S ??"???S??S?)
// ==============================
class NotificationsCounter extends StatefulWidget {
  final Widget Function(int count) builder;
  const NotificationsCounter({super.key, required this.builder});

  @override
  State<NotificationsCounter> createState() => _NotificationsCounterState();
}

class _NotificationsCounterState extends State<NotificationsCounter> {
  Box<Contract>? _contracts;
  Box<Invoice>? _invoices;
  Box<MaintenanceRequest>? _maintenance;
  Box<Map>? _servicesConfig;
  Box<String>? _dismissed;
  Box<String>? _knownContracts; // notificationsKnownContracts
  Box<String>? _pinnedKinds; // notificationsPinnedKind
  late final _OrderStore _order;
  _MergedListenable? _merged;
  // ??? ??? ??. ????? ?"?"?? Cloud ???? ?"? ???f?? ??"?f???? ??"? ?????
  int _lastPushedCount = -1;

  Future<void> _pushCountToCloud(int count) async {
    // ?"?^ ?"?. ?S???S?'? ??"??? ?"? ???f?? ?????S?
    if (count == _lastPushedCount) return;
    _lastPushedCount = count;

    try {
      // ?Y'^ ???????. ??"?? effectiveUid ?.?? user_scope ???? ??S ?^?? "??.?S?" ?.?f??"
      final uid = scope.effectiveUid();
      if (uid == 'guest') return; // ?"?^ ?.? ??S ?.?????. ???'??" ????????"

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'notificationsCount': count,
          'notificationsUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // ??^??"??S?? / ??? ??"???S?? ?zo ????????" ??.??.?<? ???? ?"? ?S???? ??"?? UI
    }
  }

  Future<void>? _ready;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _today() => _dateOnly(KsaTime.now());
  int _daysBetween(DateTime a, DateTime b) =>
      _dateOnly(b).difference(_dateOnly(a)).inDays;

  @override
  void initState() {
    super.initState();
    _order = _OrderStore.createSync('notificationsOrder');
    _ready = _ensureOpenAndWire();
  }

  Future<void> _ensureOpenAndWire() async {
    Future<void> openIfNeeded<T>(String logical) async {
      final real = boxName(logical);
      if (!Hive.isBoxOpen(real)) {
        await Hive.openBox<T>(real);
      }
    }

    await Future.wait([
      openIfNeeded<Contract>('contractsBox'),
      openIfNeeded<Invoice>('invoicesBox'),
      openIfNeeded<MaintenanceRequest>('maintenanceBox'),
      openIfNeeded<Map>('servicesConfig'),
      openIfNeeded<String>('notificationsDismissed'),
      openIfNeeded<String>('notificationsStickyMaintenance'),
      openIfNeeded<String>('notificationsPinnedKind'),
      openIfNeeded<String>('notificationsKnownContracts'),
      openIfNeeded<int>('notificationsOrder'),
    ]);

    _contracts = Hive.box<Contract>(boxName('contractsBox'));
    _invoices = Hive.box<Invoice>(boxName('invoicesBox'));
    _maintenance = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
    _servicesConfig = Hive.box<Map>(boxName('servicesConfig'));
    await ensurePeriodicServiceRequestsGenerated(
      servicesBox: _servicesConfig,
      maintenanceBox: _maintenance,
      invoicesBox: _invoices,
    );
    _dismissed = Hive.box<String>(boxName('notificationsDismissed'));
    _knownContracts = Hive.box<String>(boxName('notificationsKnownContracts'));
    _pinnedKinds = Hive.box<String>(boxName('notificationsPinnedKind'));

    _merged = _MergedListenable([
      _contracts!.listenable(),
      _invoices!.listenable(),
      _maintenance!.listenable(),
      _servicesConfig!.listenable(),
      _dismissed!.listenable(),
      if (_pinnedKinds != null) _pinnedKinds!.listenable(),
      if (_knownContracts != null) _knownContracts!.listenable(),
      _order.listenable(),
    ]);

    if (mounted) setState(() {});
  }

  int _monthsPerCycle(PaymentCycle c) {
    switch (c) {
      case PaymentCycle.monthly:
        return 1;
      case PaymentCycle.quarterly:
        return 3;
      case PaymentCycle.semiAnnual:
        return 6;
      case PaymentCycle.annual:
        return 12;
    }
  }

  int _monthsPerCycleForContract(Contract c) {
    if (c.paymentCycle == PaymentCycle.annual) {
      final years = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
      return 12 * years;
    }
    return _monthsPerCycle(c.paymentCycle);
  }

  int _monthsInTerm(ContractTerm t) {
    switch (t) {
      case ContractTerm.daily:
        return 0;
      case ContractTerm.monthly:
        return 1;
      case ContractTerm.quarterly:
        return 3;
      case ContractTerm.semiAnnual:
        return 6;
      case ContractTerm.annual:
        return 12;
    }
  }

  DateTime _addMonths(DateTime d, int months) {
    if (months == 0) return _dateOnly(d);
    final y0 = d.year, m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final lastDay =
        (m == 12) ? DateTime(y + 1, 1, 0).day : DateTime(y, m + 1, 0).day;
    final safeDay = d.day > lastDay ? lastDay : d.day;
    return _dateOnly(DateTime(y, m, safeDay));
  }

  int _coveredMonthsByAdvance(Contract c) {
    if (c.advanceMode != AdvanceMode.coverMonths) return 0;
    if ((c.advancePaid ?? 0) <= 0 || c.totalAmount <= 0) return 0;
    final months = _monthsInTerm(c.term);
    if (months <= 0) return 0;
    final monthlyValue = c.totalAmount / months;
    final covered = ((c.advancePaid ?? 0) / monthlyValue).floor();
    return covered.clamp(0, months);
  }

  DateTime? _firstDueAfterAdvance(Contract c) {
    if (c.term == ContractTerm.daily) return null;
    final start = _dateOnly(c.startDate), end = _dateOnly(c.endDate);
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      final termMonths = _monthsInTerm(c.term);
      if (covered >= termMonths) return null;
      final mpc = _monthsPerCycleForContract(c);
      final cyclesCovered = (covered / mpc).ceil();
      final first = _addMonths(start, cyclesCovered * mpc);
      if (!first.isBefore(start) && !first.isAfter(end)) return first;
      return null;
    }
    return start;
  }

  /// ??.?S? ??^???S? ?????,??, ??"????? (??,??? ??"??,?) ??? ???. ??"????? ??"?.???? ???"?.?,??.
  /// ???????.??? ?"????? ?????S???? "???? ?.????,? / ???? ?.?????" ???S? ????? ?f?" ???? ??????S?? ?.???,?".
  List<DateTime> _allInstallmentDueDates(Contract c) {
    final List<DateTime> out = [];
    if (c.term == ContractTerm.daily) return out;

    DateTime start;
    DateTime end;
    try {
      start = _dateOnly(c.startDate);
      end = _dateOnly(c.endDate);
    } catch (_) {
      return out;
    }

    final termMonths = _monthsInTerm(c.term);
    if (termMonths <= 0) return out;
    final mpc = _monthsPerCycleForContract(c);
    if (mpc <= 0) return out;

    final totalCycles = (termMonths / mpc).ceil();

    int startCycle = 0;
    if (c.advanceMode == AdvanceMode.coverMonths) {
      final covered = _coveredMonthsByAdvance(c);
      if (covered >= termMonths) return out;
      final cyclesCovered = (covered / mpc).ceil();
      startCycle = cyclesCovered;
    }

    for (int i = startCycle; i < totalCycles; i++) {
      final due = _addMonths(start, i * mpc);
      final d0 = _dateOnly(due);
      if (d0.isBefore(start) || d0.isAfter(end)) continue;
      out.add(d0);
    }

    return out;
  }

  bool _isDueToday(Contract c) {
    if (c.term == ContractTerm.daily) return false;
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first) == _today();
  }

  bool _isOverdue(Contract c) {
    if (c.term == ContractTerm.daily) {
      return c.isExpiredByTime;
    }
    final first = _firstDueAfterAdvance(c);
    if (first == null) return false;
    return _dateOnly(first).isBefore(_today());
  }

  // ?,??" ??"???^? ??S ??"????
  NotificationKind _lockKind(NotificationKind proposed,
      {String? cid, required DateTime anchor}) {
    // ???? ?.????, ??"???? ??"???S??S?: ?"? ?????'? ??"???^? ??S ??"???? ??S??<?
    // ???? ?S??f? ??"???'?? ??"???"? ??"???"?S? (?,??? / ?.?????? / ?.????, / ?.????).
    return proposed;
  }

  void _markContractSeen(String? cid) {
    if (cid == null || _knownContracts == null) return;
    if (!_knownContracts!.containsKey(cid)) {
      try {
        _knownContracts!.put(cid, _dateOnly(KsaTime.now()).toIso8601String());
      } catch (_) {}
    }
  }

  DateTime? _firstSeen(String? cid) {
    if (cid == null || _knownContracts == null) return null;
    final s = _knownContracts!.get(cid);
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  bool _existedBeforeDate(String? cid, DateTime date) {
    final fs = _firstSeen(cid);
    if (fs == null) return false;
    return _dateOnly(fs).isBefore(_dateOnly(date));
  }

  String _stableKey(NotificationKind k,
      {String? cid, String? iid, String? mid, required DateTime anchor}) {
    final id = cid ?? iid ?? mid ?? 'na';
    return '${k.name}:$id:${_dateOnly(anchor).toIso8601String()}';
  }

  List<AppNotification> _gen() {
    final today = _today();
    final out = <AppNotification>[];
    final handledPeriodicMaintenanceIds = <String>{};

    void addPeriodicTrackedNotification({
      required MaintenanceRequest request,
      required DateTime dueAnchor,
    }) {
      final requestId = request.id?.toString();
      if (requestId == null || requestId.isEmpty) return;
      if (handledPeriodicMaintenanceIds.contains(requestId)) return;
      final notificationAnchor = _dateOnly(today);
      final skey = _stableKey(
        NotificationKind.maintenanceToday,
        mid: requestId,
        anchor: notificationAnchor,
      );
      final order = _order.get(skey) ?? 0;
      out.add(AppNotification(
        kind: NotificationKind.maintenanceToday,
        title: '',
        subtitle: '',
        sortKey: _periodicServiceTodaySortKeyGlobal(
          _periodicMaintenanceSortAnchorGlobal(today, dueAnchor),
        ),
        anchor: notificationAnchor,
        appearOrder: order,
        maintenanceId: requestId,
      ));
      handledPeriodicMaintenanceIds.add(requestId);
    }

    void addPeriodicCreatedTodayNotification({
      required MaintenanceRequest request,
      required DateTime dueAnchor,
    }) {
      final requestId = request.id?.toString();
      if (requestId == null || requestId.isEmpty) return;
      if (handledPeriodicMaintenanceIds.contains(requestId)) return;
      final todayAnchor = _dateOnly(today);
      final skey = _stableKey(
        NotificationKind.maintenanceToday,
        mid: requestId,
        anchor: todayAnchor,
      );
      final order = _order.get(skey) ?? 0;
      out.add(AppNotification(
        kind: NotificationKind.maintenanceToday,
        title: '',
        subtitle: '',
        sortKey: _periodicServiceTodaySortKeyGlobal(todayAnchor),
        anchor: todayAnchor,
        appearOrder: order,
        maintenanceId: requestId,
      ));
      handledPeriodicMaintenanceIds.add(requestId);
    }

    for (final c in _contracts!.values) {
      try {
        if ((c as dynamic).isArchived == true) continue;
        if ((c as dynamic).isTerminated == true) {
          continue; // ?Y'^ ???? ??"??? ?????
        }
      } catch (_) {}
      final String? cid = (() {
        try {
          return (c as dynamic).id?.toString();
        } catch (_) {
          return null;
        }
      })();

      // ??,? ??? ??"?S?^?. (??S? ?.??? ???S??<?)
      DateTime? start0;
      try {
        start0 = (c as dynamic).startDate as DateTime?;
      } catch (_) {}
      if (start0 != null) {
        final d0 = _dateOnly(start0);
        if (d0 == _today() && _existedBeforeDate(cid, d0)) {
          final anchor = d0;
          const proposed = NotificationKind.contractStartedToday;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: _today(),
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }
      _markContractSeen(cid);

      DateTime? end;
      try {
        end = (c as dynamic).endDate as DateTime?;
      } catch (_) {}
      if (end != null) {
        final ended = _dateOnly(end).isBefore(today);
        final daysToEnd = _daysBetween(today, end);
        if (ended) {
          final anchor = _dateOnly(end);
          const proposed = NotificationKind.contractEnded;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: anchor,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        } else if (daysToEnd >= 0 && daysToEnd <= 7) {
          final anchor = _dateOnly(end);
          const proposed = NotificationKind.contractExpiring;
          final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
          final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: finalKind,
            title: '',
            subtitle: '',
            sortKey: today,
            anchor: anchor,
            appearOrder: order,
            contractId: cid,
          ));
        }
      }

      try {
        final Contract cObj = c;
        if (cObj.term != ContractTerm.daily) {
          final dues = _allInstallmentDueDates(cObj);
          for (final due in dues) {
            // ???? ?.????, ??"???? ??"?f??.?"? ??,??S??<?
            final delta =
                _daysBetween(due, today); // ??"?S?^?. - ????S? ??"?????,??,
            final daysAhead =
                -delta; // ?f?. ?S?^?. ???,?S ??"?? ??"?????,??, (?"?^ ?.?^?? = ??S ??"?.???,??")

            // ??????" ??"????? ??"???S?? ???<? (??f?? ?.?? 7 ??S??. ?,??" ??"?????,??,)
            if (delta < 0 && daysAhead > 7) continue;

            final anchor = _dateOnly(due);
            NotificationKind kind;

            if (delta < 0) {
              // ???? "?,????" (?,??S?? ?.?? ??"?????,??,)
              kind = NotificationKind.contractDueSoon;
            } else if (delta == 0) {
              // ???? ?.????,? ??"?S?^?.
              kind = NotificationKind.contractDueToday;
            } else {
              // ???? ?.?????
              kind = NotificationKind.contractDueOverdue;
            }

            final proposed = kind;
            final finalKind = _lockKind(proposed, cid: cid, anchor: anchor);
            final skey = _stableKey(finalKind, cid: cid, anchor: anchor);
            final order = _order.get(skey) ?? 0;

            out.add(AppNotification(
              kind: finalKind,
              title: '',
              subtitle: '',
              sortKey: anchor,
              anchor: anchor,
              appearOrder: order,
              contractId: cid,
            ));
          }
        }
      } catch (_) {}

      _markContractSeen(cid);
    }

    for (final inv in _invoices!.values) {
      try {
        if ((inv as dynamic).isArchived == true) continue;
        if ((inv as dynamic).isPaid == true) continue;
        final due = (inv as dynamic).dueDate as DateTime?;
        if (due == null) continue;
        final delta = _daysBetween(due, today);
        if (delta < 0) continue;
        final iid = (inv as dynamic).id?.toString();
        final anchor = _dateOnly(due);
        final skey = _stableKey(NotificationKind.invoiceOverdue,
            iid: iid, anchor: anchor);
        final order = _order.get(skey) ?? 0;
        out.add(AppNotification(
          kind: NotificationKind.invoiceOverdue,
          title: '',
          subtitle: '',
          sortKey: anchor,
          anchor: anchor,
          appearOrder: order,
          invoiceId: iid,
        ));
      } catch (_) {}
    }

    for (final m in _maintenance!.values) {
      try {
        if ((m as dynamic).isArchived == true) continue;
        final s = (m as dynamic).scheduledDate as DateTime?;
        final st = (m as dynamic).status as MaintenanceStatus?;
        if (s == null) continue;
        if (st == MaintenanceStatus.canceled) continue;
        if (st == MaintenanceStatus.completed) continue;
        if (_maintenanceHasCanceledInvoiceGlobal(m, _invoices)) continue;
        if (_dateOnly(s) != today) continue;
        final mid = (m as dynamic).id?.toString();
        if (mid != null && handledPeriodicMaintenanceIds.contains(mid)) {
          continue;
        }
        final anchor = _dateOnly(s);
        final skey = _stableKey(NotificationKind.maintenanceToday,
            mid: mid, anchor: anchor);
        final order = _order.get(skey) ?? 0;
        out.add(AppNotification(
          kind: NotificationKind.maintenanceToday,
          title: '',
          subtitle: '',
          sortKey: anchor,
          anchor: anchor,
          appearOrder: order,
          maintenanceId: mid,
        ));
      } catch (_) {}
    }

    for (final entry in _servicesConfig!.toMap().entries) {
      try {
        final key = entry.key.toString();
        final raw = entry.value;
        final cfg = Map<String, dynamic>.from(raw);
        final type = (cfg['serviceType'] ?? '').toString();
        if (type != 'cleaning' &&
            type != 'elevator' &&
            type != 'water' &&
            type != 'internet' &&
            type != 'electricity') {
          continue;
        }
        final isWaterSharedFixed = type == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString() == 'fixed';
        final isWaterSharedPercent = type == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString() == 'percent';
        final isElectricitySharedPercent = type == 'electricity' &&
            (cfg['electricityBillingMode'] ?? '').toString() == 'shared' &&
            (cfg['electricitySharedMethod'] ?? '').toString() == 'percent';
        final isPercentBased =
            isWaterSharedPercent || isElectricitySharedPercent;
        final isPeriodicMaintenanceService =
            type == 'cleaning' ||
            type == 'elevator' ||
            (type == 'internet' && _internetBillingModeGlobal(cfg) == 'owner');
        final pid = key.split('::').first;
        final suppressedDate = _serviceSuppressedDateGlobal(cfg);
        final trackedPeriodicRequest = isPeriodicMaintenanceService
            ? _trackedPeriodicMaintenanceRequestFromConfigGlobal(
                maintenance: _maintenance,
                invoices: _invoices,
                propertyId: pid,
                type: type,
                cfg: cfg,
              )
            : null;
        if (!_serviceHasProviderGlobal(type, cfg)) {
          continue;
        }
        if (!isWaterSharedFixed &&
            !isPercentBased &&
            (cfg['payer'] ?? 'owner').toString() != 'owner') {
          continue;
        }
        final start = _serviceStartDateGlobal(cfg);
        if (!isPeriodicMaintenanceService &&
            start != null &&
            _daysBetween(today, start) == 0) {
          final pid = key.split('::').first;
          final alertMid = '$key#serviceStart';
          final skey = _stableKey(NotificationKind.serviceStart,
              mid: alertMid, anchor: start);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: NotificationKind.serviceStart,
            title: '',
            subtitle: '',
            sortKey: start,
            anchor: start,
            appearOrder: order,
            maintenanceId: alertMid,
            propertyId: pid,
            serviceType: type,
            serviceTargetId: cfg['targetId']?.toString(),
          ));
        }
        if (trackedPeriodicRequest != null) {
          final trackedDue = _maintenanceAnchorGlobal(trackedPeriodicRequest);
          final trackedDelta = _daysBetween(today, trackedDue);
          final remind = _serviceRemindDaysGlobal(cfg);
          if (trackedDelta == 0 ||
              (trackedDelta > 0 &&
                  remind > 0 &&
                  trackedDelta == remind)) {
            addPeriodicTrackedNotification(
              request: trackedPeriodicRequest,
              dueAnchor: trackedDue,
            );
            continue;
          }
          if (trackedDelta < 0) {
            if (_dateOnly(trackedPeriodicRequest.createdAt) == today) {
              addPeriodicCreatedTodayNotification(
                request: trackedPeriodicRequest,
                dueAnchor: trackedDue,
              );
            } else {
              addPeriodicTrackedNotification(
                request: trackedPeriodicRequest,
                dueAnchor: trackedDue,
              );
            }
          }
          continue;
        }
        final generatedToday = _serviceLastGeneratedDateGlobal(cfg);
        if (generatedToday != null && _daysBetween(today, generatedToday) == 0) {
          final hasCompletedRequest = isPeriodicMaintenanceService &&
              _hasCompletedPeriodicMaintenanceRequestGlobal(
                maintenance: _maintenance,
                propertyId: pid,
                type: type,
                anchor: generatedToday,
              );
          final hasActiveRequest = !isPeriodicMaintenanceService ||
              _hasActivePeriodicMaintenanceRequestGlobal(
                maintenance: _maintenance,
                invoices: _invoices,
                propertyId: pid,
                type: type,
                anchor: generatedToday,
              );
          if (hasCompletedRequest) {
            continue;
          }
          if (isPeriodicMaintenanceService && hasActiveRequest) {
            continue;
          }
          if (isPeriodicMaintenanceService &&
              suppressedDate != null &&
              _dateOnlyGlobal(suppressedDate) == _dateOnlyGlobal(generatedToday) &&
              !hasActiveRequest) {
            continue;
          }
          final alertMid = '$key#today';
          final skey = _stableKey(NotificationKind.serviceDue,
              mid: alertMid, anchor: generatedToday);
          final order = _order.get(skey) ?? 0;
          out.add(AppNotification(
            kind: NotificationKind.serviceDue,
            title: '',
            subtitle: '',
            sortKey: generatedToday,
            anchor: generatedToday,
            appearOrder: order,
            maintenanceId: alertMid,
            propertyId: pid,
            serviceType: type,
            serviceTargetId: cfg['targetId']?.toString(),
          ));
          continue;
        }
        final lastGenerated = _serviceLastGeneratedDateGlobal(cfg);
        if (isPeriodicMaintenanceService &&
            lastGenerated != null &&
            _daysBetween(today, lastGenerated) < 0) {
          final activeGeneratedRequest = _activePeriodicMaintenanceRequestGlobal(
            maintenance: _maintenance,
            invoices: _invoices,
            propertyId: pid,
            type: type,
            anchor: lastGenerated,
          );
          if (activeGeneratedRequest != null &&
              _dateOnly(activeGeneratedRequest.createdAt) == today) {
            addPeriodicCreatedTodayNotification(
              request: activeGeneratedRequest,
              dueAnchor: lastGenerated,
            );
            continue;
          }
        }
        final due = _serviceCurrentCycleDateGlobal(cfg);
        if (due == null) continue;
        final hasActiveRequest = !isPeriodicMaintenanceService ||
            _hasActivePeriodicMaintenanceRequestGlobal(
              maintenance: _maintenance,
              invoices: _invoices,
              propertyId: pid,
              type: type,
              anchor: due,
            );
        if (isPeriodicMaintenanceService && hasActiveRequest) {
          continue;
        }
        if (isPeriodicMaintenanceService &&
            suppressedDate != null &&
            _dateOnlyGlobal(suppressedDate) == _dateOnlyGlobal(due) &&
            !hasActiveRequest) {
          continue;
        }
        final delta = _daysBetween(today, due);
        final remind = _serviceRemindDaysGlobal(cfg);
        late String alertType;
        if (delta <= 0) {
          alertType = delta < 0 ? 'overdue' : 'today';
        } else if (remind > 0 && delta == remind) {
          alertType = 'remind-$remind';
        } else {
          continue;
        }
        final pct = isWaterSharedPercent
            ? ((cfg['sharePercent'] as num?)?.toDouble() ?? 0.0)
            : (isElectricitySharedPercent
                ? ((cfg['electricitySharePercent'] as num?)?.toDouble() ?? 0.0)
                : 0.0);
        final pctTxt = pct > 0 ? pct.toStringAsFixed(2) : '0.00';
        final alertMid = isPercentBased
            ? '$key#percent#$alertType#$pctTxt'
            : '$key#$alertType';
        final skey =
            _stableKey(NotificationKind.serviceDue, mid: alertMid, anchor: due);
        final order = _order.get(skey) ?? 0;
        out.add(AppNotification(
          kind: NotificationKind.serviceDue,
          title: '',
          subtitle: '',
          sortKey: due,
          anchor: due,
          appearOrder: order,
          maintenanceId: alertMid,
          propertyId: pid,
          serviceType: type,
          serviceTargetId: cfg['targetId']?.toString(),
        ));
      } catch (_) {}
    }

    out.sort((a, b) {
      final c1 = b.sortKey.compareTo(a.sortKey);
      if (c1 != 0) return c1;
      return b.appearOrder.compareTo(a.appearOrder);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // ?"?^ ?"??? ?.? ????S?? ??"??????S?,?O ???? 0 ???" ??.?S? ???
    if (_merged == null) {
      return widget.builder(0);
    }
    return AnimatedBuilder(
      animation: _merged!,
      builder: (context, _) {
        final all = _gen();
        final visibleCount = all
            .where((n) => !isDismissed(
                  dismissedBox: _dismissed!,
                  kind: n.kind,
                  cid: n.contractId,
                  iid: n.invoiceId,
                  mid: n.maintenanceId,
                  anchor: n.anchor,
                ))
            .length;

        // ?Y"? ?.???.??? ??"??? ?.? Cloud Firestore (?S??????. ??S ???? ??"?.?f??)
        _pushCountToCloud(visibleCount);

        return widget.builder(visibleCount);
      },
    );
  }
}



