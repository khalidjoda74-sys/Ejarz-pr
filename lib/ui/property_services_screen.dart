import 'dart:async';

import 'package:darvoo/utils/ksa_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/constants/boxes.dart' as bx;
import '../data/services/pdf_export_service.dart';
import '../data/services/user_scope.dart' show boxName;
import '../models/property.dart';
import '../models/tenant.dart';
import '../widgets/custom_confirm_dialog.dart';
import '../widgets/darvoo_app_bar.dart';
import 'contracts_screen.dart' as contracts_ui
    show
        ContractsScreen,
        normalizePeriodicServiceConfigForNoActiveContract,
        normalizeWaterConfigForNoActiveContract,
        rebuildWaterFixedConfigForContract;
import 'contracts_screen.dart'
    show Contract, ContractDetailsScreen, ContractTerm, PaymentCycle;
import 'home_screen.dart';
import 'invoices_screen.dart' show Invoice, InvoiceDetailsScreen;
import 'maintenance_screen.dart'
    show
        MaintenanceDetailsScreen,
        MaintenancePriority,
        MaintenanceRequest,
        MaintenanceStatus,
        buildMaintenanceProviderSnapshot,
        createOrUpdateInvoiceForMaintenance,
        deleteMaintenanceRequestOnlyLocalAndSync,
        maintenanceLinkedPartyIdForProperty,
        nextMaintenanceRequestSerialForBox,
        saveMaintenanceRequestLocalAndSync,
        tenantIdForProperty;
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;
import 'widgets/app_bottom_nav.dart';

class PropertyServicesRoutes {
  static const String propertyServices = '/property/services';
  static Map<String, WidgetBuilder> routes() => {
        propertyServices: (context) {
          final m =
              (ModalRoute.of(context)?.settings.arguments as Map?) ?? const {};
          return PropertyServicesScreen(
            propertyId: (m['propertyId'] ?? '').toString(),
            openService: m['openService']?.toString(),
            openPay: m['openPay'] == true,
            targetId: m['targetId']?.toString(),
            openServiceDirectly: m['openServiceDirectly'] == true,
          );
        },
      };
}

DateTime _periodicServiceDateOnly(DateTime d) => KsaTime.dateOnly(d);

String _internetBillingModeFromConfig(Map<String, dynamic> cfg) {
  final payer = (cfg['payer'] ?? '').toString().trim().toLowerCase();
  final raw =
      (cfg['internetBillingMode'] ?? (payer == 'tenant' ? 'separate' : 'owner'))
          .toString()
          .trim()
          .toLowerCase();
  return raw == 'separate' ? 'separate' : 'owner';
}

bool _isInternetOwnerPeriodicConfig(Map<String, dynamic> cfg) =>
    _internetBillingModeFromConfig(cfg) == 'owner';

bool _isPeriodicMaintenanceServiceType(String type, Map<String, dynamic> cfg) =>
    type == 'cleaning' ||
    type == 'elevator' ||
    (type == 'internet' && _isInternetOwnerPeriodicConfig(cfg));

DateTime? _periodicServiceParseDate(dynamic raw) {
  if (raw is DateTime) return _periodicServiceDateOnly(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      return _periodicServiceDateOnly(DateTime.parse(raw));
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _periodicServiceRequestTitle(String type) {
  switch (type) {
    case 'cleaning':
      return 'طلب نظافة عمارة';
    case 'elevator':
      return 'طلب صيانة مصعد';
    case 'internet':
      return 'طلب تجديد خدمة إنترنت';
    case 'water':
      return 'طلب فاتورة مياه مشتركة';
    case 'electricity':
      return 'طلب فاتورة كهرباء مشتركة';
    default:
      return 'طلب خدمة';
  }
}

String _periodicServiceRequestTypeLabel(String type) {
  switch (type) {
    case 'cleaning':
      return 'نظافة عمارة';
    case 'elevator':
      return 'صيانة مصعد';
    case 'internet':
      return 'خدمة إنترنت';
    case 'water':
      return 'خدمة مياه مشتركة';
    case 'electricity':
      return 'خدمة كهرباء مشتركة';
    default:
      return 'خدمات';
  }
}

String _periodicServiceInactiveLabel() => String.fromCharCodes(const [
      0x063A,
      0x064A,
      0x0631,
      0x0020,
      0x0645,
      0x0641,
      0x0639,
      0x0644,
      0x0629,
    ]);

String _periodicServiceNoUpcomingDateLabel() => String.fromCharCodes(const [
      0x0627,
      0x0636,
      0x063A,
      0x0637,
      0x0020,
      0x0647,
      0x0646,
      0x0627,
      0x0020,
      0x0644,
      0x062A,
      0x062D,
      0x062F,
      0x064A,
      0x062F,
      0x0020,
      0x0645,
      0x0648,
      0x0639,
      0x062F,
      0x0020,
      0x0627,
      0x0644,
      0x062E,
      0x062F,
      0x0645,
      0x0629,
    ]);

class _PeriodicServiceScheduleState {
  final DateTime? dueForGeneration;
  final DateTime? storedDueDate;

  const _PeriodicServiceScheduleState({
    this.dueForGeneration,
    this.storedDueDate,
  });
}

int _periodicServiceRecurrenceMonths(Map<String, dynamic> cfg) =>
    ((cfg['recurrenceMonths'] as num?)?.toInt() ?? 0).clamp(0, 12);

int _periodicServiceRemindBeforeDays(Map<String, dynamic> cfg) {
  final value = (cfg['remindBeforeDays'] as num?)?.toInt() ?? 0;
  if (value < 0) return 0;
  if (value > 3) return 3;
  return value;
}

DateTime _periodicServiceCurrentCycleFromAnchor(
  DateTime anchor,
  int recurrenceMonths,
  DateTime today,
) {
  final normalizedAnchor = _periodicServiceDateOnly(anchor);
  final normalizedToday = _periodicServiceDateOnly(today);
  if (normalizedAnchor.isAfter(normalizedToday)) return normalizedAnchor;
  var monthsBetween = (normalizedToday.year - normalizedAnchor.year) * 12 +
      (normalizedToday.month - normalizedAnchor.month);
  // تصحيح: إذا لم يصل اليوم بعد في الشهر الحالي، نرجع شهر
  if (normalizedToday.day < normalizedAnchor.day) {
    monthsBetween = monthsBetween > 0 ? monthsBetween - 1 : 0;
  }
  final step = recurrenceMonths < 1 ? 1 : recurrenceMonths;
  final offset = (monthsBetween ~/ step) * step;
  return _periodicServiceAddMonthsClamped(normalizedAnchor, offset);
}

bool _samePeriodicServiceDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return _periodicServiceDateOnly(a) == _periodicServiceDateOnly(b);
}

bool _shouldResetPeriodicServiceGeneration({
  required String type,
  required Map<String, dynamic> previousCfg,
  required DateTime newStartDate,
  required DateTime? newNextDate,
  required int newRecurrenceMonths,
}) {
  final oldStartDate = _periodicServiceStartDateFromConfig(previousCfg);
  final oldNextDate = _periodicServiceDueDateFromConfig(type, previousCfg);
  final oldRecurrenceMonths =
      (previousCfg['recurrenceMonths'] as num?)?.toInt() ?? 0;
  return !_samePeriodicServiceDate(oldStartDate, newStartDate) ||
      !_samePeriodicServiceDate(oldNextDate, newNextDate) ||
      oldRecurrenceMonths != newRecurrenceMonths;
}

_PeriodicServiceScheduleState _periodicServiceScheduleState({
  required String type,
  required Map<String, dynamic> cfg,
  DateTime? today,
}) {
  final normalizedToday = _periodicServiceDateOnly(today ?? KsaTime.today());
  final lastGenerated = _periodicServiceLastGeneratedDateFromConfig(cfg);
  final recurrenceMonths = _periodicServiceRecurrenceMonths(cfg);
  final remindBeforeDays = _periodicServiceRemindBeforeDays(cfg);
  final startDate = _periodicServiceStartDateFromConfig(cfg);
  final configuredDue = _periodicServiceDueDateFromConfig(type, cfg);
  final scheduleAnchor = lastGenerated == null
      ? (startDate ?? configuredDue)
      : (configuredDue ?? startDate);
  if (scheduleAnchor == null) return const _PeriodicServiceScheduleState();

  if (recurrenceMonths <= 0) {
    final due = configuredDue ?? scheduleAnchor;
    final alreadyGenerated = lastGenerated != null &&
        _periodicServiceDateOnly(lastGenerated) ==
            _periodicServiceDateOnly(due);
    final daysUntilDue =
        _periodicServiceDateOnly(due).difference(normalizedToday).inDays;
    if (alreadyGenerated) {
      return const _PeriodicServiceScheduleState();
    }
    return _PeriodicServiceScheduleState(
      dueForGeneration: daysUntilDue <= 0 ||
              (remindBeforeDays > 0 && daysUntilDue == remindBeforeDays)
          ? due
          : null,
      storedDueDate: due,
    );
  }

  final currentCycle = _periodicServiceCurrentCycleFromAnchor(
    scheduleAnchor,
    recurrenceMonths,
    normalizedToday,
  );
  if (currentCycle.isAfter(normalizedToday)) {
    final daysUntilCurrentCycle =
        currentCycle.difference(normalizedToday).inDays;
    return _PeriodicServiceScheduleState(
      dueForGeneration:
          remindBeforeDays > 0 && daysUntilCurrentCycle == remindBeforeDays
              ? currentCycle
              : null,
      storedDueDate: currentCycle,
    );
  }

  final currentGenerated = lastGenerated != null &&
      !currentCycle.isAfter(_periodicServiceDateOnly(lastGenerated));
  if (currentGenerated) {
    return _PeriodicServiceScheduleState(
      storedDueDate:
          _periodicServiceAddMonthsClamped(currentCycle, recurrenceMonths),
    );
  }

  return _PeriodicServiceScheduleState(
    dueForGeneration: currentCycle,
    storedDueDate: currentCycle,
  );
}

_PeriodicServiceScheduleState _periodicServiceDraftScheduleState({
  required String type,
  required Map<String, dynamic> previousCfg,
  required DateTime startDate,
  required int recurrenceMonths,
  required bool hasNextDate,
}) {
  if (!hasNextDate) {
    return const _PeriodicServiceScheduleState();
  }
  final normalizedStartDate = _periodicServiceDateOnly(startDate);
  final rawNextDate = hasNextDate ? normalizedStartDate : null;
  final shouldResetGeneration = _shouldResetPeriodicServiceGeneration(
    type: type,
    previousCfg: previousCfg,
    newStartDate: normalizedStartDate,
    newNextDate: rawNextDate,
    newRecurrenceMonths: recurrenceMonths,
  );
  final draft = <String, dynamic>{
    ...previousCfg,
    'serviceType': type,
    'startDate': normalizedStartDate.toIso8601String(),
    'recurrenceMonths': recurrenceMonths,
    'nextDueDate': rawNextDate?.toIso8601String() ?? '',
  };
  draft.remove('nextServiceDate');
  if (shouldResetGeneration) {
    draft['lastGeneratedRequestDate'] = '';
    draft['lastGeneratedRequestId'] = '';
    draft['targetId'] = '';
  }
  return _periodicServiceScheduleState(type: type, cfg: draft);
}

DateTime? _periodicServiceDueDateFromConfig(
    String type, Map<String, dynamic> cfg) {
  dynamic raw;
  if (type == 'cleaning' || type == 'elevator' || type == 'internet') {
    raw = cfg['nextDueDate'];
  } else {
    return null;
  }
  return _periodicServiceParseDate(raw);
}

DateTime? _periodicServiceStartDateFromConfig(Map<String, dynamic> cfg) =>
    _periodicServiceParseDate(cfg['startDate']);

DateTime? _periodicServiceLastGeneratedDateFromConfig(
        Map<String, dynamic> cfg) =>
    _periodicServiceParseDate(cfg['lastGeneratedRequestDate']);

DateTime? _periodicServiceSuppressedDateFromConfig(Map<String, dynamic> cfg) =>
    _periodicServiceParseDate(cfg['suppressedRequestDate']);

String _periodicServiceSuppressedDateForSave({
  required Map<String, dynamic> previousCfg,
  required bool shouldResetGeneration,
  DateTime? newDueDate,
}) {
  if (shouldResetGeneration) return '';
  final oldSuppressed = (previousCfg['suppressedRequestDate'] ?? '').toString();
  if (oldSuppressed.isEmpty) return '';
  // إذا التاريخ الملغي يطابق التاريخ الجديد، نمسحه لكي لا يمنع التوليد
  if (newDueDate != null) {
    final suppDate = _periodicServiceParseDate(oldSuppressed);
    if (suppDate != null &&
        _periodicServiceDateOnly(suppDate) ==
            _periodicServiceDateOnly(newDueDate)) {
      return '';
    }
  }
  return oldSuppressed;
}

Map<String, dynamic> _periodicServiceConfigWithTrackedRequest({
  required Map<String, dynamic> cfg,
  required MaintenanceRequest request,
}) {
  final requestId = request.id.toString().trim();
  if (requestId.isEmpty) return Map<String, dynamic>.from(cfg);
  return {
    ...cfg,
    'lastGeneratedRequestDate':
        _periodicServiceRequestAnchor(request).toIso8601String(),
    'lastGeneratedRequestId': requestId,
    'targetId': requestId,
  };
}

DateTime? _periodicServiceCurrentCycleDateFromConfig(
  String type,
  Map<String, dynamic> cfg,
) {
  final lastGenerated = _periodicServiceLastGeneratedDateFromConfig(cfg);
  final startDate = _periodicServiceStartDateFromConfig(cfg);
  if (lastGenerated == null && startDate != null) {
    return startDate;
  }
  return _periodicServiceDueDateFromConfig(type, cfg);
}

DateTime? _periodicServiceExecutionDateForToday(
  String type,
  Map<String, dynamic> cfg,
  DateTime today,
) {
  return _periodicServiceScheduleState(
    type: type,
    cfg: cfg,
    today: today,
  ).dueForGeneration;
}

DateTime _periodicServiceAddMonthsClamped(DateTime startDate, int months) {
  final base = _periodicServiceDateOnly(startDate);
  final safeMonths = months < 1 ? 1 : months;
  final totalMonths = (base.month - 1) + safeMonths;
  final year = base.year + (totalMonths ~/ 12);
  final month = (totalMonths % 12) + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = base.day <= lastDay ? base.day : lastDay;
  return DateTime(year, month, day);
}

bool _periodicServiceRequestCanBeUpdated(MaintenanceRequest request) {
  if (request.isArchived) return false;
  return request.status == MaintenanceStatus.open ||
      request.status == MaintenanceStatus.inProgress;
}

bool _isLegacyAutoCompletedPeriodicRequestWithoutInvoice(
  MaintenanceRequest request, {
  Box<Invoice>? invoicesBox,
}) {
  if (request.isArchived) return false;
  if (request.status != MaintenanceStatus.completed) return false;
  if (request.completedDate != null) return false;

  final type = _normalizePeriodicServiceTypeToken(request.periodicServiceType);
  if (type != 'cleaning' && type != 'elevator' && type != 'internet') {
    return false;
  }

  final invoiceId = (request.invoiceId ?? '').trim();
  if (invoiceId.isEmpty) return true;

  final box = invoicesBox ??
      (Hive.isBoxOpen(boxName(bx.kInvoicesBox))
          ? Hive.box<Invoice>(boxName(bx.kInvoicesBox))
          : null);
  if (box == null) return true;

  final invoice = box.get(invoiceId);
  if (invoice == null) return true;
  return invoice.isCanceled;
}

Future<bool> _normalizeLegacyAutoCompletedPeriodicRequest({
  required MaintenanceRequest request,
  Box<Invoice>? invoicesBox,
}) async {
  if (!_isLegacyAutoCompletedPeriodicRequestWithoutInvoice(
    request,
    invoicesBox: invoicesBox,
  )) {
    return false;
  }

  var changed = false;
  if (request.status != MaintenanceStatus.open) {
    request.status = MaintenanceStatus.open;
    changed = true;
  }
  if (request.completedDate != null) {
    request.completedDate = null;
    changed = true;
  }
  if ((request.invoiceId ?? '').trim().isNotEmpty) {
    request.invoiceId = '';
    changed = true;
  }

  if (!changed) return false;
  await saveMaintenanceRequestLocalAndSync(request);
  return true;
}

bool _sameSnapshotList(List<dynamic>? a, List<dynamic>? b) {
  final left = a ?? const <dynamic>[];
  final right = b ?? const <dynamic>[];
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _sameProviderSnapshotMap(
  Map<String, dynamic>? a,
  Map<String, dynamic>? b,
) {
  final left = (a == null || a.isEmpty) ? null : a;
  final right = (b == null || b.isEmpty) ? null : b;
  if (left == null || right == null) return left == right;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key)) return false;
    final rv = right[entry.key];
    final lv = entry.value;
    if (lv is List || rv is List) {
      if (!_sameSnapshotList(
        lv is List ? lv : null,
        rv is List ? rv : null,
      )) {
        return false;
      }
      continue;
    }
    if (lv != rv) return false;
  }
  return true;
}

bool _periodicServiceRequestHasCanceledInvoice(
  MaintenanceRequest request, {
  Box<Invoice>? invoicesBox,
}) {
  final invoiceId = (request.invoiceId ?? '').trim();
  if (invoiceId.isEmpty) return false;
  final box = invoicesBox ??
      (Hive.isBoxOpen(boxName(bx.kInvoicesBox))
          ? Hive.box<Invoice>(boxName(bx.kInvoicesBox))
          : null);
  if (box == null) return false;
  final invoice = box.get(invoiceId);
  if (invoice == null) return false;
  return invoice.isCanceled;
}

Future<bool> _updateExistingPeriodicServiceRequestFromConfig({
  required MaintenanceRequest request,
  required String type,
  required DateTime dueDate,
  required String providerName,
  required double cost,
  required String? tenantId,
  Map<String, dynamic>? providerSnapshot,
}) async {
  if (!_periodicServiceRequestCanBeUpdated(request)) return false;

  var changed = false;
  final normalizedDueDate = _periodicServiceDateOnly(dueDate);
  final expectedTitle = _periodicServiceRequestTitle(type);
  final expectedRequestType = _periodicServiceRequestTypeLabel(type);

  if (request.title != expectedTitle) {
    request.title = expectedTitle;
    changed = true;
  }
  if (request.requestType != expectedRequestType) {
    request.requestType = expectedRequestType;
    changed = true;
  }
  if (request.priority != MaintenancePriority.medium) {
    request.priority = MaintenancePriority.medium;
    changed = true;
  }
  if (_periodicServiceDateOnly(
        request.scheduledDate ?? normalizedDueDate,
      ) !=
      normalizedDueDate) {
    request.scheduledDate = normalizedDueDate;
    changed = true;
  }
  if (_periodicServiceDateOnly(
        request.executionDeadline ?? normalizedDueDate,
      ) !=
      normalizedDueDate) {
    request.executionDeadline = normalizedDueDate;
    changed = true;
  }
  if ((request.assignedTo ?? '').trim() != providerName) {
    request.assignedTo = providerName;
    changed = true;
  }
  if (_normalizePeriodicServiceTypeToken(request.periodicServiceType) != type) {
    request.periodicServiceType = type;
    changed = true;
  }
  if (_periodicServiceDateOnly(
        request.periodicCycleDate ?? normalizedDueDate,
      ) !=
      normalizedDueDate) {
    request.periodicCycleDate = normalizedDueDate;
    changed = true;
  }
  if ((request.tenantId ?? '').trim() != (tenantId ?? '').trim()) {
    request.tenantId = tenantId;
    changed = true;
  }
  if (!_sameProviderSnapshotMap(
    (request.providerSnapshot ?? const <String, dynamic>{})
        .cast<String, dynamic>(),
    providerSnapshot,
  )) {
    request.providerSnapshot = providerSnapshot;
    changed = true;
  }
  if ((request.cost - cost).abs() > 0.0001) {
    request.cost = cost;
    changed = true;
  }

  if (!changed) return false;
  await saveMaintenanceRequestLocalAndSync(request);
  return true;
}

MaintenanceRequest? _findTrackedPeriodicServiceRequestFromConfig({
  required Box<MaintenanceRequest> maintenanceBox,
  Box<Invoice>? invoicesBox,
  required String propertyId,
  required String type,
  required Map<String, dynamic> lookupCfg,
}) {
  final trackedIds = <String>{
    (lookupCfg['targetId'] ?? '').toString().trim(),
    (lookupCfg['lastGeneratedRequestId'] ?? '').toString().trim(),
  }..removeWhere((id) => id.isEmpty);

  bool validTrackedRequest(MaintenanceRequest request) {
    if (!_matchesPeriodicServiceRequest(
      request,
      propertyId: propertyId,
      type: type,
    )) {
      return false;
    }
    if (_periodicServiceRequestHasCanceledInvoice(
      request,
      invoicesBox: invoicesBox,
    )) {
      return false;
    }
    return _periodicServiceRequestCanBeUpdated(request);
  }

  for (final trackedId in trackedIds) {
    final tracked = maintenanceBox.get(trackedId);
    if (tracked == null) continue;
    if (validTrackedRequest(tracked)) return tracked;
  }

  final trackedCycleDate = _periodicServiceCurrentCycleDateFromConfig(
    type,
    lookupCfg,
  );
  if (trackedCycleDate != null) {
    final normalizedTrackedCycleDate =
        _periodicServiceDateOnly(trackedCycleDate);
    final byCycleDate = maintenanceBox.values.firstWhereOrNull((request) {
      if (!validTrackedRequest(request)) return false;
      return _periodicServiceRequestAnchor(request) ==
          normalizedTrackedCycleDate;
    });
    if (byCycleDate != null) return byCycleDate;
  }

  final candidates =
      maintenanceBox.values.where(validTrackedRequest).toList(growable: false);
  if (candidates.length == 1) return candidates.first;

  return null;
}

Future<MaintenanceRequest?> _syncTrackedPeriodicServiceRequestFromConfig({
  required Box<MaintenanceRequest> maintenanceBox,
  Box<Invoice>? invoicesBox,
  required String propertyId,
  required String type,
  required Map<String, dynamic> cfg,
  Map<String, dynamic>? lookupCfg,
}) async {
  final tracked = _findTrackedPeriodicServiceRequestFromConfig(
    maintenanceBox: maintenanceBox,
    invoicesBox: invoicesBox,
    propertyId: propertyId,
    type: type,
    lookupCfg: lookupCfg ?? cfg,
  );
  if (tracked == null) return null;

  final trackedAnchor = _periodicServiceRequestAnchor(tracked);
  final previousLastGenerated = lookupCfg == null
      ? null
      : _periodicServiceLastGeneratedDateFromConfig(lookupCfg);
  final currentLastGenerated = _periodicServiceLastGeneratedDateFromConfig(cfg);
  DateTime? dueDate = _periodicServiceCurrentCycleDateFromConfig(type, cfg) ??
      _periodicServiceDueDateFromConfig(type, cfg);
  if (previousLastGenerated != null &&
      _periodicServiceDateOnly(previousLastGenerated) == trackedAnchor &&
      currentLastGenerated != null &&
      _periodicServiceDateOnly(currentLastGenerated) == trackedAnchor) {
    dueDate = trackedAnchor;
  }
  if (dueDate == null) return null;

  final providerName = (cfg['providerName'] ?? '').toString().trim();
  if (providerName.isEmpty) return null;

  var cost = _periodicServiceDefaultAmount(cfg);
  if (cost.isNaN || cost.isInfinite || cost < 0) cost = 0.0;

  Map<String, dynamic>? providerSnapshot;
  final providerId = (cfg['providerId'] ?? '').toString().trim();
  final tenantsBoxId = boxName(bx.kTenantsBox);
  if (Hive.isBoxOpen(tenantsBoxId)) {
    final tenantsBox = Hive.box<Tenant>(tenantsBoxId);
    final provider = providerId.isNotEmpty
        ? tenantsBox.values.firstWhereOrNull(
            (t) => t.clientType == 'serviceProvider' && t.id == providerId,
          )
        : null;
    final resolvedProvider = provider ??
        tenantsBox.values.firstWhereOrNull(
          (t) =>
              t.clientType == 'serviceProvider' &&
              t.fullName.trim() == providerName,
        );
    if (resolvedProvider != null) {
      providerSnapshot = buildMaintenanceProviderSnapshot(resolvedProvider);
    }
  }

  final requestTenantId = maintenanceLinkedPartyIdForProperty(
    propertyId,
    serviceType: type,
  );
  await _updateExistingPeriodicServiceRequestFromConfig(
    request: tracked,
    type: type,
    dueDate: dueDate,
    providerName: providerName,
    cost: cost,
    tenantId: requestTenantId,
    providerSnapshot: providerSnapshot,
  );
  return tracked;
}

double _periodicServiceDefaultAmount(Map<String, dynamic> cfg) {
  final raw = cfg['defaultAmount'];
  if (raw is num) return raw.toDouble();
  final parsed = double.tryParse((raw ?? '').toString()) ?? 0.0;
  // تصحيح: إذا كانت القيمة نص، نحفظها كرقم لتجنب المشاكل مستقبلاً
  if (raw is String && raw.isNotEmpty) {
    cfg['defaultAmount'] = parsed;
  }
  return parsed;
}

String _periodicServiceDefaultAmountText(Map<String, dynamic> cfg) {
  final amount = _periodicServiceDefaultAmount(cfg);
  if (amount == 0) return '0';
  if (amount == amount.truncateToDouble()) {
    return amount.toInt().toString();
  }
  return amount.toString();
}

String _periodicServiceEditableAmountText(
  Map<String, dynamic> cfg, {
  double fallbackAmount = 0.0,
}) {
  final hasStoredAmount = cfg.containsKey('defaultAmount');
  final amount =
      hasStoredAmount ? _periodicServiceDefaultAmount(cfg) : fallbackAmount;
  if (amount.isNaN || amount.isInfinite || amount <= 0) return '';
  if (amount == amount.truncateToDouble()) {
    return amount.toInt().toString();
  }
  return amount.toStringAsFixed(2);
}

DateTime _periodicServiceRequestAnchor(MaintenanceRequest request) =>
    _periodicServiceDateOnly(request.periodicCycleDate ??
        request.executionDeadline ??
        request.scheduledDate ??
        request.createdAt);

String? _normalizePeriodicServiceTypeToken(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'cleaning' ||
      value.contains('clean') ||
      value.contains('نظاف')) {
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
  if (value == 'water' ||
      value.contains('water') ||
      value.contains('مياه') ||
      value.contains('ماء')) {
    return 'water';
  }
  if (value == 'electricity' ||
      value.contains('electric') ||
      value.contains('electricity') ||
      value.contains('كهرب')) {
    return 'electricity';
  }
  return null;
}

bool _matchesLegacyPeriodicServiceRequestSignature(
  MaintenanceRequest request,
  String type,
) {
  final expectedTitle = _periodicServiceRequestTitle(type).trim();
  final expectedRequestType = _periodicServiceRequestTypeLabel(type).trim();
  return request.title.trim() == expectedTitle ||
      request.requestType.trim() == expectedRequestType;
}

bool _matchesPeriodicServiceRequest(
  MaintenanceRequest request, {
  required String propertyId,
  required String type,
}) {
  if (request.propertyId != propertyId) return false;
  final tagged =
      _normalizePeriodicServiceTypeToken(request.periodicServiceType);
  if (tagged != null) return tagged == type;
  return _matchesLegacyPeriodicServiceRequestSignature(request, type);
}

bool _matchesPeriodicServiceRequestForDue(
  MaintenanceRequest request, {
  required String propertyId,
  required String type,
  required DateTime dueDate,
}) {
  if (!_matchesPeriodicServiceRequest(
    request,
    propertyId: propertyId,
    type: type,
  )) {
    return false;
  }
  return _periodicServiceRequestAnchor(request) ==
      _periodicServiceDateOnly(dueDate);
}

Map<String, dynamic> _advancePeriodicServiceConfig({
  required String type,
  required Map<String, dynamic> current,
  required DateTime dueDate,
  required String requestId,
}) {
  final recurrenceMonths =
      ((current['recurrenceMonths'] as num?)?.toInt() ?? 0).clamp(0, 12);
  final nextDate = recurrenceMonths > 0
      ? _periodicServiceAddMonthsClamped(dueDate, recurrenceMonths)
      : (() {
          final configuredDue =
              _periodicServiceDueDateFromConfig(type, current);
          if (configuredDue != null &&
              configuredDue.isAfter(_periodicServiceDateOnly(dueDate))) {
            return configuredDue;
          }
          return null;
        })();
  final nextIso = nextDate?.toIso8601String() ?? '';
  final updated = <String, dynamic>{
    ...current,
    'lastGeneratedRequestDate':
        _periodicServiceDateOnly(dueDate).toIso8601String(),
    'lastGeneratedRequestId': requestId,
    'targetId': requestId,
    'suppressedRequestDate': '',
  };
  updated.remove('nextServiceDate');
  if (type == 'elevator') {
    updated['nextDueDate'] = nextIso;
  } else {
    updated['nextDueDate'] = nextIso;
    updated['dueDay'] = nextDate?.day;
  }
  return updated;
}

Future<bool> ensurePeriodicServiceRequestsGenerated({
  Box<Map>? servicesBox,
  Box<MaintenanceRequest>? maintenanceBox,
  Box<Invoice>? invoicesBox,
  Set<String>? serviceKeys,
}) async {
  final services = servicesBox ?? Hive.box<Map>(boxName('servicesConfig'));
  final maintenance = maintenanceBox ??
      Hive.box<MaintenanceRequest>(boxName(bx.kMaintenanceBox));
  final invoices = invoicesBox ??
      (Hive.isBoxOpen(boxName(bx.kInvoicesBox))
          ? Hive.box<Invoice>(boxName(bx.kInvoicesBox))
          : null);
  final today = KsaTime.today();
  var changed = false;

  for (final entry in services.toMap().entries) {
    if (serviceKeys != null && !serviceKeys.contains(entry.key.toString())) {
      continue;
    }
    final raw = entry.value;
    if (raw is! Map) continue;
    final cfg = Map<String, dynamic>.from(raw);
    final type = (cfg['serviceType'] ?? '').toString().trim();
    if (!_isPeriodicMaintenanceServiceType(type, cfg)) continue;

    final providerName = (cfg['providerName'] ?? '').toString().trim();
    if (providerName.isEmpty) continue;

    final dueDate = _periodicServiceExecutionDateForToday(type, cfg, today);
    if (dueDate == null) continue;

    final propertyId = entry.key.toString().split('::').first;
    final existing = maintenance.values.firstWhereOrNull((request) {
      if (request.isArchived) return false;
      if (request.status == MaintenanceStatus.canceled) return false;
      if (_periodicServiceRequestHasCanceledInvoice(
        request,
        invoicesBox: invoices,
      )) {
        return false;
      }
      return _matchesPeriodicServiceRequestForDue(
        request,
        propertyId: propertyId,
        type: type,
        dueDate: dueDate,
      );
    });
    if (existing != null) {
      final normalizedExisting =
          await _normalizeLegacyAutoCompletedPeriodicRequest(
        request: existing,
        invoicesBox: invoices,
      );
      if (normalizedExisting) changed = true;
    }
    final suppressedDate = _periodicServiceSuppressedDateFromConfig(cfg);
    if (existing == null &&
        suppressedDate != null &&
        _periodicServiceDateOnly(suppressedDate) == dueDate) {
      continue;
    }

    var requestId = existing?.id ?? '';
    var cost = _periodicServiceDefaultAmount(cfg);
    if (cost.isNaN || cost.isInfinite || cost < 0) cost = 0.0;
    final providerId = (cfg['providerId'] ?? '').toString().trim();
    Map<String, dynamic>? providerSnapshot;
    final tenantsBoxId = boxName(bx.kTenantsBox);
    if (Hive.isBoxOpen(tenantsBoxId)) {
      final tenantsBox = Hive.box<Tenant>(tenantsBoxId);
      final provider = providerId.isNotEmpty
          ? tenantsBox.values.firstWhereOrNull(
              (t) => t.clientType == 'serviceProvider' && t.id == providerId,
            )
          : null;
      final resolvedProvider = provider ??
          tenantsBox.values.firstWhereOrNull(
            (t) =>
                t.clientType == 'serviceProvider' &&
                t.fullName.trim() == providerName,
          );
      if (resolvedProvider != null) {
        providerSnapshot = buildMaintenanceProviderSnapshot(resolvedProvider);
      }
    }

    final requestTenantId = maintenanceLinkedPartyIdForProperty(
      propertyId,
      serviceType: type,
    );

    if (existing == null) {
      final request = MaintenanceRequest(
        serialNo: nextMaintenanceRequestSerialForBox(maintenance),
        propertyId: propertyId,
        tenantId: requestTenantId,
        title: _periodicServiceRequestTitle(type),
        description: '',
        requestType: _periodicServiceRequestTypeLabel(type),
        priority: MaintenancePriority.medium,
        status: MaintenanceStatus.open,
        scheduledDate: dueDate,
        executionDeadline: dueDate,
        assignedTo: providerName,
        providerSnapshot: providerSnapshot,
        cost: cost,
        periodicServiceType: type,
        periodicCycleDate: dueDate,
      );
      await saveMaintenanceRequestLocalAndSync(request);
      requestId = request.id;
      changed = true;
    } else {
      final updatedExisting =
          await _updateExistingPeriodicServiceRequestFromConfig(
        request: existing,
        type: type,
        dueDate: dueDate,
        providerName: providerName,
        cost: cost,
        tenantId: requestTenantId,
        providerSnapshot: providerSnapshot,
      );
      if (updatedExisting) changed = true;
      requestId = existing.id;
    }

    await services.put(
      entry.key,
      _advancePeriodicServiceConfig(
        type: type,
        current: cfg,
        dueDate: dueDate,
        requestId: requestId,
      ),
    );
    changed = true;
  }

  return changed;
}

class PropertyServicesScreen extends StatefulWidget {
  final String propertyId;
  final String? openService;
  final bool openPay;
  final String? targetId;
  final bool openServiceDirectly;
  final bool refreshPeriodicStateOnOpen;
  const PropertyServicesScreen({
    super.key,
    required this.propertyId,
    this.openService,
    this.openPay = false,
    this.targetId,
    this.openServiceDirectly = false,
    this.refreshPeriodicStateOnOpen = true,
  });
  @override
  State<PropertyServicesScreen> createState() => _PropertyServicesScreenState();
}

class _PropertyServicesScreenState extends State<PropertyServicesScreen> {
  static const _servicesBoxBase = 'servicesConfig';
  late Box<Property> _props;
  late Box<Invoice> _invoices;
  late Box<Contract> _contracts;
  late Box<Tenant> _tenants;
  late Box<MaintenanceRequest> _maintenance;
  Box<Map>? _services;

  Property? _property;
  List<Property> _units = const [];
  bool _didOpenFromArgs = false;
  String? _inlineServicePageTitle;
  Widget? _inlineServicePageChild;
  final GlobalKey _bottomNavKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Set<String> _currentServiceKeys() {
    final services = _services;
    if (services == null) return const <String>{};
    final prefix = '${widget.propertyId}::';
    return services.keys
        .map((key) => key.toString())
        .where((key) => key.startsWith(prefix))
        .toSet();
  }

  Future<void> _refreshCurrentPropertyServices({
    required bool openFromArgsIfNeeded,
  }) async {
    final services = _services;
    if (services == null) return;

    final serviceKeys = _currentServiceKeys();
    if (serviceKeys.isNotEmpty) {
      await ensurePeriodicServiceRequestsGenerated(
        servicesBox: services,
        maintenanceBox: _maintenance,
        invoicesBox: _invoices,
        serviceKeys: serviceKeys,
      );
    }

    if (!mounted) return;
    await _resetServicesIfNoActiveContract();
    if (openFromArgsIfNeeded &&
        widget.openService != null &&
        !_didOpenFromArgs) {
      await _openFromArgs();
    }
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    _props = Hive.box<Property>(boxName(bx.kPropertiesBox));
    _invoices = Hive.box<Invoice>(boxName(bx.kInvoicesBox));
    _contracts = Hive.box<Contract>(boxName(bx.kContractsBox));
    _tenants = Hive.box<Tenant>(boxName(bx.kTenantsBox));
    _maintenance = Hive.box<MaintenanceRequest>(boxName(bx.kMaintenanceBox));
    if (!Hive.isBoxOpen(boxName(_servicesBoxBase))) {
      await Hive.openBox<Map>(boxName(_servicesBoxBase));
    }
    _services = Hive.box<Map>(boxName(_servicesBoxBase));
    _property =
        _props.values.firstWhereOrNull((e) => e.id == widget.propertyId);
    _units = _props.values
        .where((e) => e.parentBuildingId == widget.propertyId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    if (!widget.refreshPeriodicStateOnOpen) {
      setState(() {});
      return;
    }
    if (widget.openService != null) {
      await _refreshCurrentPropertyServices(openFromArgsIfNeeded: true);
      return;
    }
    setState(() {});
    unawaited(
      _refreshCurrentPropertyServices(openFromArgsIfNeeded: false),
    );
  }

  Future<void> _resetServicesIfNoActiveContract() async {
    final active = _activeContractForProperty();
    if (active != null) return;
    const serviceTypes = <String>[
      'water',
      'electricity',
      'internet',
      'cleaning',
      'elevator',
    ];
    for (final t in serviceTypes) {
      final k = _serviceKey(t);
      final rawCfg = _services?.get(k);
      final cfg = rawCfg is Map
          ? Map<String, dynamic>.from(rawCfg)
          : <String, dynamic>{};
      final normalized = contracts_ui
          .normalizePeriodicServiceConfigForNoActiveContract(t, cfg);
      if (normalized.isNotEmpty) {
        await _services?.put(k, normalized);
        continue;
      }
      if (_services?.containsKey(k) == true) {
        await _services?.delete(k);
      }
    }
  }

  bool get _buildingWithUnits =>
      _property?.type == PropertyType.building &&
      _property?.rentalMode == RentalMode.perUnit;
  bool get _isRootBuilding =>
      _property?.type == PropertyType.building &&
      _property?.parentBuildingId == null;
  String _serviceKey(String type) => '${widget.propertyId}::$type';
  Map<String, dynamic> _cfg(String type) {
    final r = _services?.get(_serviceKey(type));
    if (r is Map) return Map<String, dynamic>.from(r);
    return <String, dynamic>{};
  }

  Future<void> _saveCfg(String type, Map<String, dynamic> cfg) async {
    await _services?.put(_serviceKey(type), cfg);
    if (mounted) setState(() {});
  }

  Future<void> _saveCfgForProperty(
    String propertyId,
    String type,
    Map<String, dynamic> cfg,
  ) async {
    final normalizedPropertyId = propertyId.trim();
    if (normalizedPropertyId.isEmpty) return;
    await _services?.put('$normalizedPropertyId::$type', cfg);
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _cfgForProperty(String propertyId, String type) {
    final raw = _services?.get('${propertyId.trim()}::$type');
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Property? get _parentBuilding {
    final parentId = (_property?.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return null;
    return _props.values.firstWhereOrNull((e) => e.id == parentId);
  }

  bool get _unitUnderPerUnitBuilding =>
      _parentBuilding?.type == PropertyType.building &&
      _parentBuilding?.rentalMode == RentalMode.perUnit;

  String _sharedUnitsModeFromCfg(Map<String, dynamic> cfg) {
    return (cfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
  }

  String _normalizedSharedUnitsModeValue(String type, String mode) {
    final normalizedType = type.trim().toLowerCase();
    final normalizedMode = mode.trim().toLowerCase();
    if (normalizedType == 'water') {
      if (normalizedMode == 'units') return 'units_fixed';
      if (normalizedMode == 'units_fixed' ||
          normalizedMode == 'units_separate' ||
          normalizedMode == 'shared_percent') {
        return normalizedMode;
      }
      return normalizedMode;
    }
    if (normalizedMode == 'units_fixed' || normalizedMode == 'units_separate') {
      return 'units';
    }
    return normalizedMode;
  }

  String _sharedUnitsModeForType(String type, Map<String, dynamic> cfg) {
    return _normalizedSharedUnitsModeValue(type, _sharedUnitsModeFromCfg(cfg));
  }

  bool _isUnitsManagedMode(String type, String mode) {
    final normalizedType = type.trim().toLowerCase();
    final normalizedMode = _normalizedSharedUnitsModeValue(type, mode);
    if (normalizedType == 'water') {
      return normalizedMode == 'units_fixed' ||
          normalizedMode == 'units_separate';
    }
    return normalizedMode == 'units';
  }

  bool _isWaterUnitsFixedMode(String mode) =>
      _normalizedSharedUnitsModeValue('water', mode) == 'units_fixed';

  bool _isWaterUnitsSeparateMode(String mode) =>
      _normalizedSharedUnitsModeValue('water', mode) == 'units_separate';

  Map<String, dynamic> _buildWaterSeparateUnitCfg(Map<String, dynamic> cfg) {
    final meterNo = (cfg['waterMeterNo'] ?? '').toString().trim();
    return contracts_ui.normalizeWaterConfigForNoActiveContract({
      ...cfg,
      'serviceType': 'water',
      'sharedUnitsMode': 'units_separate',
      'payer': 'tenant',
      'waterBillingMode': 'separate',
      'waterSharedMethod': '',
      'sharePercent': null,
      'waterPercentRequests': <Map<String, dynamic>>[],
      'totalWaterAmount': null,
      'waterPerInstallment': null,
      'waterLinkedContractId': '',
      'waterLinkedTenantId': '',
      'waterInstallments': <Map<String, dynamic>>[],
      'remainingInstallmentsCount': 0,
      'nextDueDate': '',
      'dueDay': 0,
      'recurrenceMonths': 0,
      'remindBeforeDays': 0,
      'waterMeterNo': meterNo,
    });
  }

  List<Map<String, dynamic>> _sharedPercentUnitSharesFromCfg(
      Map<String, dynamic> cfg) {
    final raw = cfg['sharedPercentUnitShares'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Map<String, dynamic> _parentSharedServiceCfg(String type) {
    final building = _parentBuilding;
    if (building == null) return <String, dynamic>{};
    return _cfgForProperty(building.id, type);
  }

  double _sharedPercentForUnit(Map<String, dynamic> cfg, String unitId) {
    final normalizedUnitId = unitId.trim();
    if (normalizedUnitId.isEmpty) return 0.0;
    final row = _sharedPercentUnitSharesFromCfg(cfg).firstWhereOrNull((item) {
      return (item['unitId'] ?? '').toString().trim() == normalizedUnitId;
    });
    if (row == null) return 0.0;
    return _numParse((row['percent'] ?? '').toString());
  }

  double _sharedUnitsPercentTotal(Iterable<Map<String, dynamic>> rows) {
    return rows.fold<double>(0.0, (sum, item) {
      return sum + _numParse((item['percent'] ?? '').toString());
    });
  }

  bool _sharedUnitsPercentTotalIsValid(Iterable<Map<String, dynamic>> rows) {
    final list = rows.toList();
    if (list.any((item) => _numParse((item['percent'] ?? '').toString()) < 0)) {
      return false;
    }
    final total = _sharedUnitsPercentTotal(list);
    return total > 0 && (total - 100).abs() <= 0.01;
  }

  bool _sharedUnitsPercentConfigReady(Map<String, dynamic> cfg) {
    if (_sharedUnitsModeFromCfg(cfg) != 'shared_percent') return false;
    final due = _periodicServiceParseDate(cfg['nextDueDate']);
    return due != null;
  }

  String _effectiveSharedUnitsMode(String type) {
    if (!_unitUnderPerUnitBuilding) return '';
    return _sharedUnitsModeForType(type, _parentSharedServiceCfg(type));
  }

  bool _unitSharedServiceReadyFromBuilding(String type) {
    if (!_unitUnderPerUnitBuilding) return false;
    final parentCfg = _parentSharedServiceCfg(type);
    return _sharedUnitsPercentConfigReady(parentCfg);
  }

  List<Map<String, dynamic>> _buildingSharedUnitRows(Map<String, dynamic> cfg) {
    final saved = _sharedPercentUnitSharesFromCfg(cfg);
    final byId = <String, Map<String, dynamic>>{
      for (final row in saved) (row['unitId'] ?? '').toString().trim(): row,
    };
    final defaultPercent =
        saved.isEmpty && _units.isNotEmpty ? (100 / _units.length) : 0.0;
    return _units.map((unit) {
      final row = byId[unit.id];
      final percent = row == null
          ? defaultPercent
          : _numParse((row['percent'] ?? '').toString());
      return <String, dynamic>{
        'unitId': unit.id,
        'unitName': unit.name,
        'percent': percent,
      };
    }).toList();
  }

  String _sharedUnitsManagedModeLabel(String type, [String mode = 'units']) {
    final normalizedType = type.trim().toLowerCase();
    final normalizedMode = _normalizedSharedUnitsModeValue(type, mode);
    switch (normalizedType) {
      case 'water':
        if (normalizedMode == 'units_separate') {
          return 'الإدارة من الوحدات (منفصل)';
        }
        return 'الإدارة من الوحدات (مبلغ مقطوع)';
      case 'electricity':
        return 'الإدارة من الوحدات (منفصل)';
      default:
        return 'الإدارة من الوحدات';
    }
  }

  String _sharedServiceManagementModeLabel(String type, String mode) {
    switch (_normalizedSharedUnitsModeValue(type, mode)) {
      case 'units':
      case 'units_fixed':
      case 'units_separate':
        return _sharedUnitsManagedModeLabel(type, mode);
      case 'shared_percent':
        return 'التوزيع على الشقق المؤجرة بالتساوي';
      default:
        return 'طريقة الإدارة';
    }
  }

  String _sharedServiceUnitsPreview(Iterable<Property> units) {
    final names = units
        .map((unit) {
          final name = unit.name.trim();
          if (name.isNotEmpty) return name;
          return unit.id.trim();
        })
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return '';
    final shown = names.take(5).map((name) => '- $name').join('\n');
    if (names.length <= 5) return shown;
    return '$shown\n- و${names.length - 5} وحدة أخرى';
  }

  bool _unitHasActiveLocalWaterConfig(String unitId, Map<String, dynamic> cfg) {
    final contract = _activeContractForPropertyId(unitId);
    if (contract == null) return false;
    final mode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (mode != 'shared') return false;

    final method = (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (method == 'fixed') {
      final linkedContractId =
          (cfg['waterLinkedContractId'] ?? '').toString().trim();
      final totalAmount =
          ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0.0).toDouble();
      final perInstallment =
          ((cfg['waterPerInstallment'] as num?)?.toDouble() ?? 0.0).toDouble();
      final remainingInstallments =
          ((cfg['remainingInstallmentsCount'] as num?)?.toInt() ?? 0);
      return linkedContractId == contract.id ||
          totalAmount > 0 ||
          perInstallment > 0 ||
          remainingInstallments > 0 ||
          _waterInstallmentsFromCfg(cfg).isNotEmpty;
    }
    if (method == 'percent') {
      final percent =
          ((cfg['sharePercent'] as num?)?.toDouble() ?? 0.0).toDouble();
      return percent > 0 || _waterPercentRequestsFromCfg(cfg).isNotEmpty;
    }
    return false;
  }

  bool _unitHasActiveLocalElectricityConfig(
    String unitId,
    Map<String, dynamic> cfg,
  ) {
    final contract = _activeContractForPropertyId(unitId);
    if (contract == null) return false;
    final mode = (cfg['electricityBillingMode'] ?? cfg['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (mode != 'shared') return false;
    final percent =
        ((cfg['electricitySharePercent'] as num?)?.toDouble() ?? 0.0)
            .toDouble();
    return percent > 0 || _electricityPercentRequestsFromCfg(cfg).isNotEmpty;
  }

  List<Property> _buildingUnitsWithBlockingLocalServiceConfigs(String type) {
    if (!_buildingWithUnits) return const <Property>[];
    if (type != 'water' && type != 'electricity') return const <Property>[];
    final blocked = <Property>[];
    for (final unit in _units) {
      final localCfg = _cfgForProperty(unit.id, type);
      final hasConflict = type == 'water'
          ? _unitHasActiveLocalWaterConfig(unit.id, localCfg)
          : _unitHasActiveLocalElectricityConfig(unit.id, localCfg);
      if (hasConflict) blocked.add(unit);
    }
    blocked.sort((a, b) => a.name.compareTo(b.name));
    return blocked;
  }

  List<MaintenanceRequest> _sharedServiceCycleRequests(String type) {
    return _serviceRequests(type).where((request) {
      if (request.isArchived) return false;
      if (request.status == MaintenanceStatus.canceled) return false;
      if (_requestHasCanceledInvoice(request)) return false;
      return _isSharedServiceCycleRequest(request);
    }).toList(growable: false);
  }

  List<MaintenanceRequest> _pendingSharedServiceCycleRequests(String type) {
    return _sharedServiceCycleRequests(type).where((request) {
      final counters = _sharedServiceCycleCounters(request);
      return (counters['pending'] ?? 0) > 0;
    }).toList(growable: false);
  }

  Future<bool> _confirmSharedServiceManagementModeChange({
    required BuildContext context,
    required String type,
    required String fromMode,
    required String toMode,
  }) async {
    final normalizedFrom = _normalizedSharedUnitsModeValue(type, fromMode);
    final normalizedTo = _normalizedSharedUnitsModeValue(type, toMode);
    if (normalizedFrom == normalizedTo) return true;

    final targetLabel = _sharedServiceManagementModeLabel(type, normalizedTo);
    if (normalizedTo == 'shared_percent') {
      final blockedUnits = _buildingUnitsWithBlockingLocalServiceConfigs(type);
      if (blockedUnits.isNotEmpty) {
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن تغيير طريقة الإدارة',
          message:
              'لا يمكن التحويل الآن إلى "$targetLabel".\n\nتوجد وحدات لديها عقود نشطة وإعدادات ${_title(type)} محلية فعالة من داخل الوحدة:\n${_sharedServiceUnitsPreview(blockedUnits)}\n\nيجب إيقاف إدارة هذه الخدمة من تلك الوحدات أولًا حتى لا تتكرر المطالبة على المستأجر.',
          confirmLabel: 'حسنًا',
          showCancel: false,
          confirmColor: const Color(0xFFD97706),
        );
        return false;
      }
      return await CustomConfirmDialog.show(
        context: context,
        title: 'تأكيد تغيير طريقة الإدارة',
        message:
            'سيتم اعتماد "$targetLabel" من الدورات القادمة فقط.\n\nأي سجلات أو سندات سابقة داخل الوحدات ستبقى محفوظة كما هي ولن تُحذف.',
        confirmLabel: 'متابعة',
        cancelLabel: 'إلغاء',
        confirmColor: const Color(0xFF0F766E),
      );
    }

    if (normalizedFrom == 'shared_percent' &&
        _isUnitsManagedMode(type, normalizedTo)) {
      final pendingCycles = _pendingSharedServiceCycleRequests(type);
      if (pendingCycles.isNotEmpty) {
        final pendingUnits = pendingCycles.fold<int>(0, (sum, request) {
          final counters = _sharedServiceCycleCounters(request);
          return sum + (counters['pending'] ?? 0);
        });
        await CustomConfirmDialog.show(
          context: context,
          title: 'لا يمكن تغيير طريقة الإدارة',
          message:
              'لا يمكن التحويل الآن إلى "$targetLabel".\n\nتوجد دورات مشتركة سابقة ما زالت بانتظار السداد، وعدد الحصص غير المحصلة حاليًا هو $pendingUnits.\n\nيجب تحصيل هذه الحصص أو إغلاق الدورات المفتوحة أولًا، ثم يمكن تغيير طريقة الإدارة.',
          confirmLabel: 'حسنًا',
          showCancel: false,
          confirmColor: const Color(0xFFD97706),
        );
        return false;
      }

      final hasHistory = _sharedServiceCycleRequests(type).isNotEmpty;
      return await CustomConfirmDialog.show(
        context: context,
        title: 'تأكيد تغيير طريقة الإدارة',
        message: hasHistory
            ? 'سيتم اعتماد "$targetLabel" من الدورات القادمة فقط.\n\nسجل الدورات المشتركة السابقة سيبقى محفوظًا كما هو ولن يُحذف.'
            : 'سيتم اعتماد "$targetLabel" بدءًا من الدورات القادمة فقط.',
        confirmLabel: 'متابعة',
        cancelLabel: 'إلغاء',
        confirmColor: const Color(0xFF0F766E),
      );
    }

    return true;
  }

  Future<String> _resolveSharedServiceManagementModeSelection({
    required BuildContext context,
    required String type,
    required String persistedMode,
    required String currentDraftMode,
    required String? attemptedMode,
  }) async {
    final normalizedPersisted =
        _normalizedSharedUnitsModeValue(type, persistedMode);
    final normalizedDraft = _normalizedSharedUnitsModeValue(type, currentDraftMode);
    final normalizedAttempt =
        _normalizedSharedUnitsModeValue(type, attemptedMode ?? '');
    if (normalizedAttempt.isEmpty) return normalizedDraft;
    if (normalizedAttempt == normalizedDraft) return normalizedDraft;
    if (normalizedAttempt == normalizedPersisted) return normalizedPersisted;
    final canChange = await _confirmSharedServiceManagementModeChange(
      context: context,
      type: type,
      fromMode: normalizedPersisted,
      toMode: normalizedAttempt,
    );
    return canChange ? normalizedAttempt : normalizedDraft;
  }

  Future<void> _promptOpenBuildingSharedService(String type) async {
    final building = _parentBuilding;
    if (building == null) return;
    final mode = _effectiveSharedUnitsMode(type);
    final message = mode == 'shared_percent'
        ? 'هذه الخدمة تُدار من شاشة الخدمات المشتركة في العمارة، ويُقسَّم مبلغ الفاتورة هناك بالتساوي على الشقق المؤجرة فقط.'
        : 'يجب ضبط هذه الخدمة من شاشة الخدمات المشتركة في العمارة أولًا قبل تعديلها من داخل الوحدة.';
    final openNow = await CustomConfirmDialog.show(
      context: context,
      title: 'ضبط الخدمة من العمارة',
      message: message,
      confirmLabel: 'فتح إعدادات العمارة',
      cancelLabel: 'إلغاء',
      confirmColor: const Color(0xFF0F766E),
    );
    if (openNow != true || !mounted) return;
    await Navigator.of(context).pushNamed(
      PropertyServicesRoutes.propertyServices,
      arguments: {
        'propertyId': building.id,
        'openService': type,
      },
    );
    if (mounted) setState(() {});
  }

  List<Tenant> _providers() => _tenants.values
      .where((t) =>
          !t.isArchived &&
          t.clientType.trim().toLowerCase() == 'serviceprovider')
      .toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));

  List<MaintenanceRequest> _serviceRequests(String type) {
    final items = _maintenance.values.where((m) {
      return _matchesPeriodicServiceRequest(
        m,
        propertyId: widget.propertyId,
        type: type,
      );
    }).toList();
    items.sort((a, b) => _periodicServiceRequestAnchor(b)
        .compareTo(_periodicServiceRequestAnchor(a)));
    return items;
  }

  List<MaintenanceRequest> _cleaningRequests() => _serviceRequests('cleaning');

  List<MaintenanceRequest> _elevatorRequests() => _serviceRequests('elevator');

  List<MaintenanceRequest> _internetOwnerRequests() =>
      _serviceRequests('internet');

  MaintenanceRequest? _trackedPeriodicServiceRequest(
    String type,
    Map<String, dynamic> cfg,
  ) {
    if (!_isPeriodicMaintenanceServiceType(type, cfg)) return null;
    return _findTrackedPeriodicServiceRequestFromConfig(
      maintenanceBox: _maintenance,
      invoicesBox: _invoices,
      propertyId: widget.propertyId,
      type: type,
      lookupCfg: cfg,
    );
  }

  Invoice? _activeInvoiceForRequest(MaintenanceRequest request) {
    final invoiceId = (request.invoiceId ?? '').trim();
    if (invoiceId.isEmpty) return null;
    final invoice = _invoices.get(invoiceId);
    if (invoice == null || invoice.isCanceled) return null;
    return invoice;
  }

  bool _requestHasActiveInvoice(MaintenanceRequest request) {
    return _activeInvoiceForRequest(request) != null;
  }

  bool _requestHasCanceledInvoice(MaintenanceRequest request) {
    final invoiceId = (request.invoiceId ?? '').trim();
    if (invoiceId.isEmpty) return false;
    final invoice = _invoices.get(invoiceId);
    if (invoice == null) return false;
    return invoice.isCanceled;
  }

  String _periodicServiceLogStatusLabel(MaintenanceRequest request) {
    if (_requestHasCanceledInvoice(request)) return 'ملغي';
    if (request.isArchived) return 'مؤرشف';
    switch (request.status) {
      case MaintenanceStatus.open:
        return 'جديد';
      case MaintenanceStatus.inProgress:
        return 'قيد التنفيذ';
      case MaintenanceStatus.completed:
        return 'مكتمل';
      case MaintenanceStatus.canceled:
        return 'ملغي';
    }
  }

  Color _periodicServiceLogStatusColor(MaintenanceRequest request) {
    if (_requestHasCanceledInvoice(request)) {
      return const Color(0xFFB91C1C);
    }
    if (request.isArchived) {
      return const Color(0xFF6B7280);
    }
    switch (request.status) {
      case MaintenanceStatus.open:
        return const Color(0xFF0284C7);
      case MaintenanceStatus.inProgress:
        return const Color(0xFFD97706);
      case MaintenanceStatus.completed:
        return const Color(0xFF15803D);
      case MaintenanceStatus.canceled:
        return const Color(0xFFB91C1C);
    }
  }

  static const String _manualInvoiceMarker = '[MANUAL]';

  Map<String, dynamic>? _sharedServiceCycleSnapshot(
    MaintenanceRequest request,
  ) {
    final raw = request.providerSnapshot;
    if (raw == null || raw.isEmpty) return null;
    final snapshot = Map<String, dynamic>.from(raw);
    if ((snapshot['kind'] ?? '').toString() != 'shared_service_cycle') {
      return null;
    }
    final type = _normalizePeriodicServiceTypeToken(
      snapshot['serviceType'] ?? request.periodicServiceType,
    );
    if (type != 'water' && type != 'electricity') return null;
    snapshot['serviceType'] = type;
    return snapshot;
  }

  bool _isSharedServiceCycleRequest(MaintenanceRequest request) =>
      _sharedServiceCycleSnapshot(request) != null;

  List<Map<String, dynamic>> _sharedServiceCycleRows(
    MaintenanceRequest request,
  ) {
    final snapshot = _sharedServiceCycleSnapshot(request);
    if (snapshot == null) return const <Map<String, dynamic>>[];
    final rawRows = snapshot['unitRows'];
    if (rawRows is! List) return const <Map<String, dynamic>>[];
    return rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  DateTime _sharedServiceCycleDate(MaintenanceRequest request) =>
      _periodicServiceRequestAnchor(request);

  double _sharedServiceCycleRowAmount(Map<String, dynamic> row) {
    return ((row['amount'] as num?)?.toDouble() ??
            _numParse((row['amount'] ?? '').toString()))
        .toDouble();
  }

  bool _sharedServiceCycleRowOwnerAdvanced(Map<String, dynamic> row) =>
      row['ownerAdvanced'] == true;

  Invoice? _sharedServiceCycleRowInvoice(Map<String, dynamic> row) {
    final invoiceId = (row['receiptInvoiceId'] ?? '').toString().trim();
    if (invoiceId.isEmpty) return null;
    final invoice = _invoices.get(invoiceId);
    if (invoice == null || invoice.isCanceled) return null;
    return invoice;
  }

  String _sharedServiceCycleRowStatusLabel(
    MaintenanceRequest request,
    Map<String, dynamic> row,
  ) {
    final invoice = _sharedServiceCycleRowInvoice(row);
    if (invoice != null && invoice.isPaid) return 'مدفوع';
    return 'بانتظار السداد';
  }

  Color _sharedServiceCycleRowStatusColor(
    MaintenanceRequest request,
    Map<String, dynamic> row,
  ) {
    final label = _sharedServiceCycleRowStatusLabel(request, row);
    switch (label) {
      case 'مدفوع':
        return const Color(0xFF15803D);
      default:
        return const Color(0xFFD97706);
    }
  }

  Map<String, int> _sharedServiceCycleCounters(MaintenanceRequest request) {
    var paid = 0;
    var pending = 0;
    for (final row in _sharedServiceCycleRows(request)) {
      switch (_sharedServiceCycleRowStatusLabel(request, row)) {
        case 'مدفوع':
          paid++;
          break;
        default:
          pending++;
          break;
      }
    }
    return {
      'paid': paid,
      'pending': pending,
    };
  }

  double _sharedServiceCycleCollectedAmount(MaintenanceRequest request) {
    var total = 0.0;
    for (final row in _sharedServiceCycleRows(request)) {
      final invoice = _sharedServiceCycleRowInvoice(row);
      if (invoice != null && invoice.isPaid) {
        total += invoice.amount.abs();
      }
    }
    return total;
  }

  bool _sharedServiceCycleHasActiveReceipts(MaintenanceRequest request) {
    for (final row in _sharedServiceCycleRows(request)) {
      if (_sharedServiceCycleRowInvoice(row) != null) return true;
    }
    return false;
  }

  String _buildSharedServiceCycleDescription({
    required String type,
    required DateTime cycleDate,
    required double totalAmount,
    required List<Map<String, dynamic>> rows,
  }) {
    var paidCount = 0;
    var pendingCount = 0;
    var collectedAmount = 0.0;
    for (final row in rows) {
      final invoice = _sharedServiceCycleRowInvoice(row);
      if (invoice != null && invoice.isPaid) {
        paidCount++;
        collectedAmount += invoice.amount.abs();
        continue;
      }
      pendingCount++;
    }

    final buffer = StringBuffer()
      ..writeln(_periodicServiceRequestTitle(type))
      ..writeln('تاريخ الدورة: ${_fmt(cycleDate)}')
      ..writeln('المبلغ الكلي: ${totalAmount.toStringAsFixed(2)} ريال')
      ..writeln('آلية التوزيع: بالتساوي على الشقق المؤجرة بعقد فعّال')
      ..writeln('عدد الشقق المشمولة: ${rows.length}')
      ..writeln('المدفوع: $paidCount')
      ..writeln('بانتظار السداد: $pendingCount')
      ..writeln('المحصّل حتى الآن: ${collectedAmount.toStringAsFixed(2)} ريال');

    if (rows.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('تفاصيل الوحدات:');
      for (final row in rows) {
        final unitName = (row['unitName'] ?? '').toString().trim();
        final tenantName = (row['tenantName'] ?? '').toString().trim();
        final amount = _sharedServiceCycleRowAmount(row);
        final status = _sharedServiceCycleRowInvoice(row) != null
            ? 'مدفوع'
            : 'بانتظار السداد';
        buffer.write('- $unitName: ${amount.toStringAsFixed(2)} ريال');
        if (tenantName.isNotEmpty) {
          buffer.write(' | المستأجر: $tenantName');
        }
        buffer.write(' | الحالة: $status');
        if (_sharedServiceCycleRowOwnerAdvanced(row)) {
          buffer.write(' | تحملتها الإدارة وقت التنفيذ');
        }
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  String _sharedServiceReceiptPropertyName(String unitId) {
    final unit = _props.values.firstWhereOrNull((e) => e.id == unitId);
    if (unit == null) return (_property?.name ?? '').trim();
    final building = (unit.parentBuildingId ?? '').trim().isEmpty
        ? null
        : _props.values.firstWhereOrNull((e) => e.id == unit.parentBuildingId);
    final unitName = unit.name.trim();
    final buildingName = (building?.name ?? '').trim();
    if (buildingName.isEmpty || unitName == buildingName) return unitName;
    return '$buildingName - $unitName';
  }

  String _buildSharedServiceReceiptNote({
    required String type,
    required DateTime cycleDate,
    required Map<String, dynamic> row,
  }) {
    final serviceLabel = _periodicServiceRequestTypeLabel(type);
    final title = 'تحصيل $serviceLabel';
    final tenantName = (row['tenantName'] ?? '').toString().trim();
    final propertyName =
        _sharedServiceReceiptPropertyName((row['unitId'] ?? '').toString());
    final amount = _sharedServiceCycleRowAmount(row);
    final lines = <String>[_manualInvoiceMarker];
    lines.add('[SERVICE] type=$type');
    if (title.isNotEmpty) lines.add('[TITLE: $title]');
    if (tenantName.isNotEmpty) lines.add('[PARTY: $tenantName]');
    if (propertyName.isNotEmpty) lines.add('[PROPERTY: $propertyName]');
    final tenantId = (row['tenantId'] ?? '').toString().trim();
    final unitId = (row['unitId'] ?? '').toString().trim();
    if (tenantId.isNotEmpty) lines.add('[PARTY_ID: $tenantId]');
    if (unitId.isNotEmpty) lines.add('[PROPERTY_ID: $unitId]');
    lines.add('تحصيل $serviceLabel لدورة بتاريخ ${_fmt(cycleDate)}');
    if (propertyName.isNotEmpty) lines.add('الوحدة: $propertyName');
    if (tenantName.isNotEmpty) lines.add('المستأجر: $tenantName');
    lines.add('المبلغ: ${amount.toStringAsFixed(2)} ريال');
    if (_sharedServiceCycleRowOwnerAdvanced(row)) {
      lines.add(
        'تم سداد هذه الحصة من الإدارة عند تنفيذ الفاتورة، وهذا السند يثبت تحصيلها لاحقًا من المستأجر.',
      );
    }
    return lines.join('\n').trim();
  }

  Invoice? _waterInstallmentOfficeExpenseInvoice(Map<String, dynamic> row) {
    final invoiceId = (row['officeExpenseInvoiceId'] ?? '').toString().trim();
    if (invoiceId.isEmpty) return null;
    return _invoices.get(invoiceId);
  }

  String _waterCompanyExpensePropertyName() {
    final propertyName = (_property?.name ?? '').trim();
    if (propertyName.isNotEmpty) return propertyName;
    return widget.propertyId.trim();
  }

  String _buildWaterCompanyExpenseNote({
    required DateTime cycleDate,
    required double amount,
  }) {
    final propertyName = _waterCompanyExpensePropertyName();
    final contract = _activeContractForProperty();
    final tenant = contract == null
        ? null
        : _tenants.values.firstWhereOrNull((t) => t.id == contract.tenantId);
    final lines = <String>[_manualInvoiceMarker];
    lines.add('[SERVICE] type=water');
    lines.add('[TITLE: فاتورة شركة المياه]');
    lines.add('[PARTY: المكتب]');
    if (propertyName.isNotEmpty) lines.add('[PROPERTY: $propertyName]');
    if (widget.propertyId.trim().isNotEmpty) {
      lines.add('[PROPERTY_ID: ${widget.propertyId.trim()}]');
    }
    lines.add('تسجيل قيمة الفاتورة الأصلية من شركة المياه لهذه الدورة.');
    lines.add('تاريخ دورة القسط: ${_fmt(cycleDate)}');
    if (propertyName.isNotEmpty) lines.add('العقار: $propertyName');
    if (contract != null) {
      final contractNo = (contract.ejarContractNo ?? '').trim();
      if (contractNo.isNotEmpty) {
        lines.add('رقم العقد: $contractNo');
      }
    }
    if (tenant != null && tenant.fullName.trim().isNotEmpty) {
      lines.add('المستأجر: ${tenant.fullName.trim()}');
    }
    lines.add('المبلغ: ${amount.toStringAsFixed(2)} ريال');
    lines.add(
      'عند إصدار هذا السند سيتم احتساب القيمة كمصروف صحيح في شاشة التقارير.',
    );
    return lines.join('\n').trim();
  }

  Future<void> _linkWaterInstallmentOfficeExpenseInvoice({
    required DateTime dueDate,
    required String invoiceId,
  }) async {
    final cfg = _cfg('water');
    if (cfg.isEmpty) return;
    final dueIso = _d0(dueDate).toIso8601String();
    final rows = _waterInstallmentsFromCfg(cfg).map((row) {
      if ((row['dueDate'] ?? '').toString() != dueIso) return row;
      return {
        ...row,
        'officeExpenseInvoiceId': invoiceId,
      };
    }).toList(growable: false);
    await _saveCfg('water', {
      ...cfg,
      'waterInstallments': rows,
    });
  }

  Future<double?> _showWaterCompanyExpenseAmountDialog(
    BuildContext context,
    DateTime cycleDate,
  ) async {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _WaterCompanyExpenseAmountDialog(
        cycleDateLabel: _fmt(cycleDate),
      ),
    );
  }

  Future<Invoice?> _createSharedServiceReceipt({
    required MaintenanceRequest request,
    required Map<String, dynamic> row,
  }) async {
    final snapshot = _sharedServiceCycleSnapshot(request);
    if (snapshot == null) return null;
    final type = _normalizePeriodicServiceTypeToken(snapshot['serviceType']) ??
        _normalizePeriodicServiceTypeToken(request.periodicServiceType);
    if (type == null) return null;
    final tenantId = (row['tenantId'] ?? '').toString().trim();
    final unitId = (row['unitId'] ?? '').toString().trim();
    final amount = _sharedServiceCycleRowAmount(row);
    if (tenantId.isEmpty || unitId.isEmpty || amount <= 0) return null;

    final existing = _sharedServiceCycleRowInvoice(row);
    if (existing != null && existing.isPaid) return existing;

    final now = KsaTime.now();
    final cycleDate = _sharedServiceCycleDate(request);
    final invoice = Invoice(
      id: now.microsecondsSinceEpoch.toString(),
      serialNo: _nextInvoiceSerial(),
      tenantId: tenantId,
      contractId: '',
      propertyId: unitId,
      issueDate: KsaTime.dateOnly(now),
      dueDate: KsaTime.dateOnly(cycleDate),
      amount: amount,
      paidAmount: amount,
      currency: 'SAR',
      note: _buildSharedServiceReceiptNote(
        type: type,
        cycleDate: cycleDate,
        row: row,
      ),
      paymentMethod: '',
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );
    await _invoices.put(invoice.id, invoice);
    return invoice;
  }

  Future<void> _markSharedServiceCycleRowPaid({
    required MaintenanceRequest request,
    required String unitId,
    required Invoice invoice,
  }) async {
    final snapshot = _sharedServiceCycleSnapshot(request);
    if (snapshot == null) return;
    final nextRows = _sharedServiceCycleRows(request).map((row) {
      final currentUnitId = (row['unitId'] ?? '').toString().trim();
      if (currentUnitId != unitId) return row;
      return {
        ...row,
        'receiptInvoiceId': invoice.id,
        'receiptSerialNo': invoice.serialNo ?? '',
        'paidAt': invoice.issueDate.toIso8601String(),
      };
    }).toList(growable: false);
    final type = _normalizePeriodicServiceTypeToken(snapshot['serviceType']) ??
        _normalizePeriodicServiceTypeToken(request.periodicServiceType) ??
        'water';
    request.providerSnapshot = {
      ...snapshot,
      'unitRows': nextRows,
      'collectedAmount': _sharedServiceCollectedAmountFromRows(nextRows),
    };
    request.description = _buildSharedServiceCycleDescription(
      type: type,
      cycleDate: _sharedServiceCycleDate(request),
      totalAmount: request.cost,
      rows: nextRows,
    );
    await saveMaintenanceRequestLocalAndSync(request);
  }

  double _sharedServiceCollectedAmountFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    var total = 0.0;
    for (final row in rows) {
      final invoice = _sharedServiceCycleRowInvoice(row);
      if (invoice != null && invoice.isPaid) {
        total += invoice.amount.abs();
      }
    }
    return total;
  }

  Future<void> _openSharedServiceCycleRequestSheet(
    BuildContext context,
    MaintenanceRequest request, {
    StateSetter? setModalState,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final snapshot = _sharedServiceCycleSnapshot(request);
          final type = _normalizePeriodicServiceTypeToken(
                snapshot?['serviceType'] ?? request.periodicServiceType,
              ) ??
              _serviceTypeFromTitle(request.title) ??
              'water';
          final cycleDate = _sharedServiceCycleDate(request);
          final rows = _sharedServiceCycleRows(request);
          final counters = _sharedServiceCycleCounters(request);
          final collectedAmount = _sharedServiceCycleCollectedAmount(request);

          Widget summaryChip(String label, String value, Color bg) {
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                '$label: $value',
                style: GoogleFonts.cairo(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.title,
                    style: GoogleFonts.cairo(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 16.sp,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'دورة الفاتورة: ${_fmt(cycleDate)}',
                    style: GoogleFonts.cairo(color: Colors.black54),
                  ),
                  Text(
                    'المبلغ الكلي: ${request.cost.toStringAsFixed(2)} ريال',
                    style: GoogleFonts.cairo(color: Colors.black54),
                  ),
                  SizedBox(height: 10.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      summaryChip(
                        'مدفوع',
                        '${counters['paid'] ?? 0}',
                        const Color(0xFFDCFCE7),
                      ),
                      summaryChip(
                        'بانتظار السداد',
                        '${counters['pending'] ?? 0}',
                        const Color(0xFFFEF3C7),
                      ),
                      summaryChip(
                        'المحصّل',
                        '${collectedAmount.toStringAsFixed(2)} ريال',
                        const Color(0xFFDDEAFE),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  if (rows.isEmpty)
                    Text(
                      'لا توجد تفاصيل وحدات محفوظة لهذه الدورة.',
                      style: GoogleFonts.cairo(color: Colors.black54),
                    )
                  else
                    SizedBox(
                      height: MediaQuery.of(sheetCtx).size.height * 0.55,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8.h),
                        itemBuilder: (_, index) {
                          final row = rows[index];
                          final tenantName =
                              (row['tenantName'] ?? '').toString().trim();
                          final unitName =
                              (row['unitName'] ?? '').toString().trim();
                          final amount = _sharedServiceCycleRowAmount(row);
                          final status =
                              _sharedServiceCycleRowStatusLabel(request, row);
                          final statusColor =
                              _sharedServiceCycleRowStatusColor(request, row);
                          final invoice = _sharedServiceCycleRowInvoice(row);
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            unitName,
                                            style: GoogleFonts.cairo(
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (tenantName.isNotEmpty) ...[
                                            SizedBox(height: 2.h),
                                            Text(
                                              tenantName,
                                              style: GoogleFonts.cairo(
                                                color: Colors.black54,
                                                fontSize: 12.sp,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10.w,
                                        vertical: 6.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        status,
                                        style: GoogleFonts.cairo(
                                          color: statusColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.sp,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  'المبلغ: ${amount.toStringAsFixed(2)} ريال',
                                  style: GoogleFonts.cairo(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_sharedServiceCycleRowOwnerAdvanced(row))
                                  Padding(
                                    padding: EdgeInsets.only(top: 4.h),
                                    child: Text(
                                      'تحملت الإدارة هذه الحصة وقت تنفيذ الفاتورة.',
                                      style: GoogleFonts.cairo(
                                        color: const Color(0xFFB45309),
                                        fontSize: 12.sp,
                                      ),
                                    ),
                                  ),
                                SizedBox(height: 8.h),
                                Row(
                                  children: [
                                    if (invoice != null && invoice.isPaid)
                                      TextButton.icon(
                                        onPressed: () async {
                                          await Navigator.of(sheetCtx).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  InvoiceDetailsScreen(
                                                invoice: invoice,
                                              ),
                                            ),
                                          );
                                          if (!mounted) return;
                                          setState(() {});
                                          if (setModalState != null) {
                                            setModalState(() {});
                                          }
                                          setSheetState(() {});
                                        },
                                        icon: const Icon(
                                          Icons.receipt_long_rounded,
                                        ),
                                        label: const Text('عرض السند'),
                                      )
                                    else
                                      TextButton.icon(
                                        onPressed: () async {
                                          final ok =
                                              await CustomConfirmDialog.show(
                                            context: sheetCtx,
                                            title: 'تأكيد السداد',
                                            message:
                                                'سيتم إصدار سند قبض لهذا المستأجر وتحديث حالته إلى مدفوع.',
                                            confirmLabel: 'سداد',
                                            cancelLabel: 'إلغاء',
                                          );
                                          if (!ok) return;
                                          final invoice =
                                              await _createSharedServiceReceipt(
                                            request: request,
                                            row: row,
                                          );
                                          if (invoice == null) {
                                            _showErr(
                                              'تعذر إصدار سند القبض لهذه الوحدة.',
                                            );
                                            return;
                                          }
                                          await _markSharedServiceCycleRowPaid(
                                            request: request,
                                            unitId: (row['unitId'] ?? '')
                                                .toString(),
                                            invoice: invoice,
                                          );
                                          if (!mounted) return;
                                          setState(() {});
                                          if (setModalState != null) {
                                            setModalState(() {});
                                          }
                                          setSheetState(() {});
                                          _showOk('تم إصدار سند القبض بنجاح.');
                                          await Navigator.of(sheetCtx).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  InvoiceDetailsScreen(
                                                invoice: invoice,
                                              ),
                                            ),
                                          );
                                          if (!mounted) return;
                                          setState(() {});
                                          if (setModalState != null) {
                                            setModalState(() {});
                                          }
                                          setSheetState(() {});
                                        },
                                        icon:
                                            const Icon(Icons.payments_rounded),
                                        label: const Text('سداد'),
                                      ),
                                    const Spacer(),
                                    if ((invoice?.serialNo ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      Text(
                                        'رقم السند: ${invoice!.serialNo}',
                                        style: GoogleFonts.cairo(
                                          color: Colors.black54,
                                          fontSize: 12.sp,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _periodicServiceLogSubtitle(
    MaintenanceRequest request,
    DateTime when,
  ) {
    final baseStyle = GoogleFonts.cairo(color: Colors.black54, fontSize: 12.sp);
    final statusStyle = GoogleFonts.cairo(
      color: _periodicServiceLogStatusColor(request),
      fontSize: 12.sp,
      fontWeight: FontWeight.w700,
    );
    final invoiceStyle = GoogleFonts.cairo(
      color: const Color(0xFF0D9488),
      fontSize: 12.sp,
      fontWeight: FontWeight.w700,
    );
    final sharedCounters = _isSharedServiceCycleRequest(request)
        ? _sharedServiceCycleCounters(request)
        : null;
    final sharedCollected = _isSharedServiceCycleRequest(request)
        ? _sharedServiceCycleCollectedAmount(request)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تاريخ التنفيذ: ${_fmt(when)}', style: baseStyle),
        Text(
          'الجهة المسؤولة: ${(request.assignedTo ?? '').trim().isEmpty ? 'غير محدد' : request.assignedTo!.trim()}',
          style: baseStyle,
        ),
        Text(
          'المبلغ: ${request.cost.toStringAsFixed(2)} ريال',
          style: baseStyle,
        ),
        Text(
          'الحالة: ${_periodicServiceLogStatusLabel(request)}',
          style: statusStyle,
        ),
        if (sharedCounters != null)
          Text(
            'الوحدات: مدفوع ${sharedCounters['paid'] ?? 0} | بانتظار السداد ${sharedCounters['pending'] ?? 0}',
            style: baseStyle,
          ),
        if (sharedCollected != null)
          Text(
            'المحصّل: ${sharedCollected.toStringAsFixed(2)} ريال',
            style: baseStyle,
          ),
        if (_requestHasActiveInvoice(request))
          Text('السند: مرتبط', style: invoiceStyle),
      ],
    );
  }

  Widget _periodicServiceLogActions(
    BuildContext context,
    MaintenanceRequest request, {
    StateSetter? setModalState,
  }) {
    final officeInvoice = _activeInvoiceForRequest(request);
    final officeInvoiceButtonLabel =
        _isSharedServiceCycleRequest(request) ? 'سند المكتب' : 'السند';
    Widget actionButton({
      required String label,
      required Color textColor,
      required Color backgroundColor,
      required VoidCallback onPressed,
    }) {
      return SizedBox(
        width: 104.w,
        height: 38.h,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.sp,
            ),
          ),
        ),
      );
    }

    Future<void> openRequest() async {
      if (_isSharedServiceCycleRequest(request)) {
        await _openSharedServiceCycleRequestSheet(
          context,
          request,
          setModalState: setModalState,
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MaintenanceDetailsScreen(item: request),
          ),
        );
      }
      if (!mounted) return;
      if (setModalState != null) {
        setModalState(() {});
      }
      setState(() {});
    }

    Future<void> openOfficeInvoice() async {
      if (officeInvoice == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailsScreen(invoice: officeInvoice),
        ),
      );
      if (!mounted) return;
      if (setModalState != null) {
        setModalState(() {});
      }
      setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        actionButton(
          label: 'عرض',
          textColor: const Color(0xFF0369A1),
          backgroundColor: const Color(0xFFE0F2FE),
          onPressed: openRequest,
        ),
        SizedBox(height: 6.h),
        actionButton(
          label: 'حذف',
          textColor: const Color(0xFFB91C1C),
          backgroundColor: const Color(0xFFFEE2E2),
          onPressed: () => _deletePeriodicServiceLogItem(
            context,
            request,
            setModalState: setModalState,
          ),
        ),
        if (officeInvoice != null) ...[
          SizedBox(height: 6.h),
          actionButton(
            label: officeInvoiceButtonLabel,
            textColor: const Color(0xFF0D9488),
            backgroundColor: const Color(0xFFDBEAFE),
            onPressed: openOfficeInvoice,
          ),
        ],
      ],
    );
  }

  Widget _periodicServiceLogRow(
    BuildContext context,
    MaintenanceRequest request,
    DateTime when, {
    StateSetter? setModalState,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  request.title,
                  style: GoogleFonts.cairo(color: Colors.black87),
                ),
                SizedBox(height: 4.h),
                _periodicServiceLogSubtitle(request, when),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Transform.translate(
              offset: Offset(0, -4.h),
              child: _periodicServiceLogActions(
                context,
                request,
                setModalState: setModalState,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePeriodicServiceLogItem(
    BuildContext context,
    MaintenanceRequest request, {
    StateSetter? setModalState,
  }) async {
    final hasActiveUnitReceipts = _sharedServiceCycleHasActiveReceipts(request);
    final hasActiveOfficeInvoice = _requestHasActiveInvoice(request);
    if (hasActiveUnitReceipts || hasActiveOfficeInvoice) {
      if (hasActiveUnitReceipts && hasActiveOfficeInvoice) {
        _showErr(
            'لا يمكن حذف هذه الفاتورة لأنها مرتبطة بسندات قبض للمستأجرين وبسند المكتب. يجب إلغاء جميع السندات المرتبطة بهذه الفاتورة، بما فيها سند المكتب، أولًا حتى يمكن حذفها.');
      } else if (hasActiveUnitReceipts) {
        _showErr(
            'لا يمكن حذف هذه الفاتورة لأنها مرتبطة بسندات قبض للمستأجرين. يجب إلغاء جميع سندات المستأجرين المرتبطة بهذه الفاتورة أولًا حتى يمكن حذفها.');
      } else {
        _showErr(
            'لا يمكن حذف هذه الفاتورة لأنها مرتبطة بسند المكتب. يجب إلغاء سند المكتب المرتبط بهذه الفاتورة أولًا حتى يمكن حذفها.');
      }
      return;
    }

    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل تريد حذف هذا الطلب من السجل؟',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (!ok) return;

    final serviceType =
        _normalizePeriodicServiceTypeToken(request.periodicServiceType) ??
            _serviceTypeFromTitle(request.title);
    if (serviceType != null) {
      final cfg = _cfg(serviceType);
      await _saveCfg(serviceType, {
        ...cfg,
        'suppressedRequestDate':
            _periodicServiceRequestAnchor(request).toIso8601String(),
        'lastGeneratedRequestId': '',
        'targetId': '',
      });
      await _clearPeriodicServiceNotificationDismissals(
        type: serviceType,
        startDate: _periodicServiceRequestAnchor(request),
        nextDate: _periodicServiceRequestAnchor(request),
      );
    }
    await deleteMaintenanceRequestOnlyLocalAndSync(request);

    if (!mounted) return;
    if (setModalState != null) setModalState(() {});
    setState(() {});
    _showOk('تم حذف الطلب');
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showErr(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  bool _ensurePeriodicServiceDateSelected(DateTime? previewDate) {
    if (previewDate != null) return true;
    _showErr('يرجى تحديد موعد الخدمة أولًا قبل الحفظ.');
    return false;
  }

  void _showNoServiceProvidersErr() => _showErr(
        'لا يوجد مقدمو خدمة مضافون حاليًا. أضف مقدم خدمة أولًا من شاشة العملاء ثم عد لاختياره هنا.',
      );
  void _showInfo(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: const Color(0xFF475569),
        behavior: SnackBarBehavior.floating,
      ));
  void _showOk(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: GoogleFonts.cairo(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
      ));

  bool _deepValueEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_deepValueEquals(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepValueEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  Future<void> _showArchiveNoticeDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          backgroundColor: Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                    ),
                  ),
                  child: Text(
                    'تنبيه',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF1E293B),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF475569),
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'حسنًا',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureSharedServiceExecutionDateReached({
    required String type,
    required DateTime cycleDate,
  }) async {
    final normalizedCycleDate = KsaTime.dateOnly(cycleDate);
    final today = KsaTime.today();
    if (!normalizedCycleDate.isAfter(today)) return true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          backgroundColor: Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                    ),
                  ),
                  child: Text(
                    'تنبيه',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF1E293B),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text(
                    'لم يحن موعد ${_periodicServiceRequestTypeLabel(type)} بعد.\n\nتاريخ الدورة المحدد هو ${_fmt(normalizedCycleDate)}، ويمكن تنفيذها ابتداءً من هذا التاريخ.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF475569),
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Center(
                    child: SizedBox(
                      width: 160,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'حسنًا',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return false;
  }

  Future<void> _exportServicePdf({
    required String serviceType,
    required String title,
    required Map<String, dynamic> config,
    List<Map<String, dynamic>> logs = const [],
  }) async {
    await PdfExportService.shareServiceSettingsPdf(
      context: context,
      serviceType: serviceType,
      title: title,
      propertyId: widget.propertyId,
      config: config,
      logRows: logs,
    );
  }

  double _numParse(String input, {double fallback = 0.0}) {
    if (input.trim().isEmpty) return fallback;
    const arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var s = input.trim();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(arDigits[i], '$i');
    }
    s = s.replaceAll('٫', '.').replaceAll('،', '').replaceAll(',', '');
    return double.tryParse(s) ?? fallback;
  }

  Future<void> _openFromArgs() async {
    if (_didOpenFromArgs) return;
    _didOpenFromArgs = true;
    final targetId = (widget.targetId ?? '').trim();
    if (widget.openPay && targetId.isNotEmpty) {
      MaintenanceRequest? item;
      for (final request in _maintenance.values) {
        if (request.id == targetId) {
          item = request;
          break;
        }
      }
      if (item != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MaintenanceDetailsScreen(item: item!),
          ),
        );
        return;
      }
    }
    if (widget.openService == null) return;
    if (widget.openServiceDirectly) {
      await _openService(widget.openService!.trim(), replaceCurrent: false);
      return;
    }
    await _openService(widget.openService!, replaceCurrent: false);
  }

  String? _serviceTypeFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('إنترنت')) return 'internet';
    if (t.contains('water') || t.contains('مياه') || t.contains('ماء')) {
      return 'water';
    }
    if (t.contains('electric') || t.contains('كهرب')) return 'electricity';
    if (t.contains('internet') || t.contains('انترنت')) return 'internet';
    if (t.contains('clean') || t.contains('نظاف')) return 'cleaning';
    if (t.contains('elevator') || t.contains('مصعد') || t.contains('اسانسير')) {
      return 'elevator';
    }
    return null;
  }

  List<Map<String, dynamic>> _serviceLogRows(String type) {
    List<Map<String, dynamic>> maintenanceRows(String serviceType) {
      return _serviceRequests(serviceType)
          .map((e) => {
                'type': e.title,
                'date':
                    _fmt(e.executionDeadline ?? e.scheduledDate ?? e.createdAt),
                'amount': e.cost.toStringAsFixed(2),
                'status': _periodicServiceLogStatusLabel(e),
              })
          .toList();
    }

    Map<String, dynamic> requestRow(Map<String, dynamic> e) {
      final amount = ((e['amount'] as num?)?.toDouble() ??
              _numParse((e['amount'] ?? '').toString()))
          .toDouble();
      final percent = ((e['percent'] as num?)?.toDouble() ??
              _numParse((e['percent'] ?? '').toString()))
          .toDouble();
      return {
        'type': 'خدمة دورية',
        'date': (e['date'] ?? '').toString(),
        if (amount > 0)
          'amount': amount.toStringAsFixed(2)
        else
          'percent': percent.toStringAsFixed(2),
        'status': (e['status'] ?? '').toString(),
      };
    }

    if (type == 'water') {
      final official = maintenanceRows(type);
      if (official.isNotEmpty) return official;
      final cfg = _cfg(type);
      final fixed = _waterInstallmentsFromCfg(cfg)
          .map((e) => {
                'type': 'خدمة دورية',
                'date': (e['dueDate'] ?? '').toString(),
                'amount':
                    ((e['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                'status': (e['status'] ?? '').toString(),
              })
          .toList();
      final pct = _waterPercentRequestsFromCfg(cfg).map(requestRow).toList();
      return [...fixed, ...pct];
    }
    if (type == 'electricity') {
      final official = maintenanceRows(type);
      if (official.isNotEmpty) return official;
      final cfg = _cfg(type);
      return _electricityPercentRequestsFromCfg(cfg).map(requestRow).toList();
    }
    if (type == 'internet') {
      return _internetOwnerRequests()
          .map((e) => {
                'type': e.title,
                'date':
                    _fmt(e.executionDeadline ?? e.scheduledDate ?? e.createdAt),
                'amount': e.cost.toStringAsFixed(2),
                'status': _periodicServiceLogStatusLabel(e),
              })
          .toList();
    }
    if (type == 'cleaning') {
      return _cleaningRequests()
          .map((e) => {
                'type': e.title,
                'date':
                    _fmt(e.executionDeadline ?? e.scheduledDate ?? e.createdAt),
                'amount': e.cost.toStringAsFixed(2),
                'status': _periodicServiceLogStatusLabel(e),
              })
          .toList();
    }
    if (type == 'elevator') {
      return _elevatorRequests()
          .map((e) => {
                'type': e.title,
                'date':
                    _fmt(e.executionDeadline ?? e.scheduledDate ?? e.createdAt),
                'amount': e.cost.toStringAsFixed(2),
                'status': _periodicServiceLogStatusLabel(e),
              })
          .toList();
    }
    return const [];
  }

  Widget _servicePageShell(String title, Widget child) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.black87),
          title: Text(title,
              style: GoogleFonts.cairo(
                  color: Colors.black87, fontWeight: FontWeight.w800)),
        ),
        body: Container(color: Colors.white, child: SafeArea(child: child)),
        bottomNavigationBar: Builder(
          builder: (navCtx) => AppBottomNav(
            currentIndex: 1,
            onTap: (i) => _handleBottomTapFrom(navCtx, i),
          ),
        ),
      ),
    );
  }

  Future<void> _openServicePage(
    String title,
    Widget child, {
    bool replaceCurrent = false,
  }) async {
    if (widget.openServiceDirectly) {
      if (mounted) {
        setState(() {
          _inlineServicePageTitle = title;
          _inlineServicePageChild = child;
        });
      } else {
        _inlineServicePageTitle = title;
        _inlineServicePageChild = child;
      }
      return;
    }
    final page = _servicePageShell(title, child);
    if (replaceCurrent) {
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }

  Widget _softCircle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _scrollList(List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      children: List.generate(children.length, (i) {
        final parts = <Widget>[children[i]];
        if (i != children.length - 1) {
          parts.add(Divider(
              color: Colors.black.withValues(alpha: 0.12), height: 10.h));
        }
        return Column(children: parts);
      }),
    );
  }

  bool _samePeriodicDate(DateTime? a, DateTime? b) {
    return _samePeriodicServiceDate(a, b);
  }

  DateTime? _trackedPeriodicServiceDueDate(
    String type,
    Map<String, dynamic> cfg,
  ) {
    final tracked = _trackedPeriodicServiceRequest(type, cfg);
    if (tracked == null) return null;
    return _periodicServiceRequestAnchor(tracked);
  }

  bool _didPeriodicScheduleInputsChange({
    required bool didPickDate,
    required bool hasNextDate,
    required bool hadNextDate,
    required int recurrenceMonths,
    required int previousRecurrenceMonths,
  }) {
    return didPickDate ||
        hasNextDate != hadNextDate ||
        recurrenceMonths != previousRecurrenceMonths;
  }

  bool _shouldResetPeriodicGeneration({
    required String type,
    required Map<String, dynamic> previousCfg,
    required DateTime newStartDate,
    required DateTime? newNextDate,
    required int newRecurrenceMonths,
  }) {
    return _shouldResetPeriodicServiceGeneration(
      type: type,
      previousCfg: previousCfg,
      newStartDate: newStartDate,
      newNextDate: newNextDate,
      newRecurrenceMonths: newRecurrenceMonths,
    );
  }

  Future<void> _clearPeriodicServiceNotificationDismissals({
    required String type,
    required DateTime startDate,
    required DateTime? nextDate,
  }) async {
    final boxId = boxName('notificationsDismissed');
    if (!Hive.isBoxOpen(boxId)) {
      try {
        await Hive.openBox<String>(boxId);
      } catch (_) {
        return;
      }
    }
    final dismissed = Hive.box<String>(boxId);
    final serviceId = _serviceKey(type);
    final anchors = <DateTime>{
      _periodicServiceDateOnly(startDate),
      if (nextDate != null) _periodicServiceDateOnly(nextDate),
    };
    final mids = <String>[
      '$serviceId#today',
      '$serviceId#remind-1',
      '$serviceId#remind-2',
      '$serviceId#remind-3',
    ];

    for (final anchor in anchors) {
      final iso = _periodicServiceDateOnly(anchor).toIso8601String();
      for (final mid in mids) {
        await dismissed.delete('serviceDue:$mid:$iso');
      }
    }
  }

  Future<void> _clearMaintenanceNotificationDismissal({
    required String requestId,
    required DateTime anchor,
  }) async {
    final boxId = boxName('notificationsDismissed');
    if (!Hive.isBoxOpen(boxId)) {
      try {
        await Hive.openBox<String>(boxId);
      } catch (_) {
        return;
      }
    }
    final dismissed = Hive.box<String>(boxId);
    final iso = _periodicServiceDateOnly(anchor).toIso8601String();
    await dismissed.delete('maintenanceToday:$requestId:$iso');
  }

  int _normalizePeriodicRecurrenceMonths(int months) {
    const allowed = <int>{0, 1, 2, 3, 6, 12};
    return allowed.contains(months) ? months : 0;
  }

  DateTime _autoPeriodicNextDate(DateTime startDate, int months) {
    final safeMonths = _normalizePeriodicRecurrenceMonths(months);
    if (safeMonths == 0) return _periodicServiceDateOnly(startDate);
    return _periodicServiceAddMonthsClamped(startDate, safeMonths);
  }

  String _periodicRecurrenceHint(int months) {
    switch (_normalizePeriodicRecurrenceMonths(months)) {
      case 0:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة مرة واحدة فقط حسب التاريخ المحدد أعلاه، ولن تتكرر تلقائيًا.';
      case 1:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة تلقائيًا كل شهر في نفس تاريخ الموعد المحدد أعلاه.';
      case 2:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة تلقائيًا كل شهرين في نفس تاريخ الموعد المحدد أعلاه.';
      case 3:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة تلقائيًا كل 3 شهور في نفس تاريخ الموعد المحدد أعلاه.';
      case 6:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة تلقائيًا كل 6 شهور في نفس تاريخ الموعد المحدد أعلاه.';
      case 12:
        return 'هذا يعني أنه سيتم تنفيذ الخدمة تلقائيًا كل سنة في نفس تاريخ الموعد المحدد أعلاه.';
      default:
        return '';
    }
  }

  DateTime _pickerInitialDate(DateTime value, DateTime firstDate) =>
      value.isBefore(firstDate) ? firstDate : value;

  Future<bool> _confirmPeriodicServiceSave(BuildContext context) async {
    return await CustomConfirmDialog.show(
      context: context,
      title: 'تنبيه',
      message:
          'هل أنت متأكد من حفظ الإعدادات الحالية؟\nسيتم اعتماد البيانات المدخلة وتحديث مواعيد الخدمة والتنبيهات تلقائيًا وفقًا لها.',
      confirmLabel: 'حسنًا',
      cancelLabel: 'تراجع',
      confirmColor: const Color(0xFF0F766E),
    );
  }

  Future<void> _openCleaning({bool replaceCurrent = false}) async {
    const type = 'cleaning';
    final cfg = _cfg(type);
    final trackedDueDate = _trackedPeriodicServiceDueDate(type, cfg);
    final configuredDueDate = _periodicServiceScheduleState(
      type: type,
      cfg: cfg,
    ).storedDueDate;
    final originalStartDate = _periodicServiceStartDateFromConfig(cfg);
    final hasConfiguredSchedule = _isConfigured(type, cfg);
    final initialHasNextDate =
        trackedDueDate != null || configuredDueDate != null;
    final initialRecurrenceMonths = _normalizePeriodicRecurrenceMonths(
      ((cfg['recurrenceMonths'] as num?)?.toInt() ?? 0),
    );
    var date = trackedDueDate ??
        configuredDueDate ??
        originalStartDate ??
        KsaTime.today();
    final initialDisplayDate = date;
    var hasNextDate = initialHasNextDate;
    var didPickDate = false;
    var months = initialRecurrenceMonths;
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final amountCtl =
        TextEditingController(text: _periodicServiceDefaultAmountText(cfg));
    final providers = _providers();
    Tenant? provider = providers
        .firstWhereOrNull((p) => p.id == (cfg['providerId']?.toString() ?? ''));

    await _openServicePage(
      'إعدادات نظافة العمارة',
      StatefulBuilder(
        builder: (ctx, setS) {
          final schedulePreview = _periodicServiceDraftScheduleState(
            type: type,
            previousCfg: cfg,
            startDate: date,
            recurrenceMonths: months,
            hasNextDate: hasNextDate,
          );
          final previewDate = schedulePreview.storedDueDate;
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InputDecorator(
                  decoration: _dd('الجهة المسؤولة'),
                  child: Text('المالك',
                      style: GoogleFonts.cairo(color: Colors.black87))),
              SizedBox(height: 8.h),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('موعد التنفيذ القادم',
                    style: GoogleFonts.cairo(color: Colors.black87)),
                subtitle: Text(
                    previewDate != null
                        ? _fmt(previewDate)
                        : _periodicServiceNoUpcomingDateLabel(),
                    style: GoogleFonts.cairo(
                        color: Colors.black54, fontSize: 12.sp)),
                trailing: const Icon(Icons.event_available_rounded,
                    color: Colors.black54),
                onTap: () async {
                  final p = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (p != null) {
                    setS(() {
                      date = KsaTime.dateOnly(p);
                      hasNextDate = true;
                      didPickDate = !_samePeriodicDate(
                        date,
                        initialDisplayDate,
                      );
                    });
                  }
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: months,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('الموعد الدوري'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بدون تكرار')),
                  DropdownMenuItem(value: 1, child: Text('كل شهر')),
                  DropdownMenuItem(value: 2, child: Text('كل شهرين')),
                  DropdownMenuItem(value: 3, child: Text('كل 3 شهور')),
                  DropdownMenuItem(value: 6, child: Text('كل 6 شهور')),
                  DropdownMenuItem(value: 12, child: Text('سنوي')),
                ],
                onChanged: (v) => setS(
                    () => months = _normalizePeriodicRecurrenceMonths(v ?? 0)),
              ),
              SizedBox(height: 8.h),
              Text(
                _periodicRecurrenceHint(months),
                style: GoogleFonts.cairo(
                  color: const Color(0xFFB91C1C),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 8.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: providers.isEmpty ? _showNoServiceProvidersErr : null,
                child: AbsorbPointer(
                  absorbing: providers.isEmpty,
                  child: DropdownButtonFormField<String>(
                    initialValue: provider?.id,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('مقدم الخدمة'),
                    items: providers
                        .map((p) => DropdownMenuItem(
                            value: p.id, child: Text(p.fullName)))
                        .toList(),
                    onChanged: (v) => setS(() => provider =
                        providers.firstWhereOrNull((p) => p.id == v)),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              TextField(
                  controller: amountCtl,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dd('تكلفة الخدمة')),
              SizedBox(height: 8.h),
              DropdownButtonFormField<int>(
                initialValue: remindBeforeDays,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('موعد التنبيه قبل'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                  DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                  DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                  DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                ],
                onChanged: (v) =>
                    setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
              ),
              SizedBox(height: 8.h),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                    onPressed: () async {
                      if (provider == null) {
                        _showErr('يرجى اختيار مقدم الخدمة');
                        return;
                      }
                      if (!_ensurePeriodicServiceDateSelected(previewDate)) {
                        return;
                      }
                      final ok = await _confirmPeriodicServiceSave(ctx);
                      if (!ok) return;
                      final scheduleChanged = _didPeriodicScheduleInputsChange(
                        didPickDate: didPickDate,
                        hasNextDate: hasNextDate,
                        hadNextDate: initialHasNextDate,
                        recurrenceMonths: months,
                        previousRecurrenceMonths: initialRecurrenceMonths,
                      );
                      final scheduleBaseDate = didPickDate
                          ? date
                          : (trackedDueDate ?? configuredDueDate ?? date);
                      final shouldResetGeneration = scheduleChanged
                          ? _shouldResetPeriodicGeneration(
                              type: type,
                              previousCfg: cfg,
                              newStartDate: scheduleBaseDate,
                              newNextDate:
                                  hasNextDate ? scheduleBaseDate : null,
                              newRecurrenceMonths: months,
                            )
                          : false;
                      final scheduleState = _periodicServiceDraftScheduleState(
                        type: type,
                        previousCfg: cfg,
                        startDate: scheduleBaseDate,
                        recurrenceMonths: months,
                        hasNextDate: hasNextDate,
                      );
                      final effectiveDueDate = scheduleChanged
                          ? scheduleState.storedDueDate
                          : configuredDueDate;
                      final effectiveStartDate = hasNextDate
                          ? (scheduleChanged
                              ? scheduleBaseDate
                              : originalStartDate)
                          : null;
                      final suppressedRequestDate =
                          _periodicServiceSuppressedDateForSave(
                        previousCfg: cfg,
                        shouldResetGeneration: shouldResetGeneration,
                        newDueDate: effectiveDueDate,
                      );
                      final updatedCfg = {
                        ...cfg,
                        'serviceType': type,
                        'payer': 'owner',
                        'startDate':
                            effectiveStartDate?.toIso8601String() ?? '',
                        'dueDay': effectiveDueDate?.day ?? '',
                        'nextDueDate':
                            effectiveDueDate?.toIso8601String() ?? '',
                        'defaultAmount': _numParse(amountCtl.text.trim()),
                        'recurrenceMonths': months,
                        'remindBeforeDays': remindBeforeDays,
                        'providerId': provider?.id ?? '',
                        'providerName': provider?.fullName ?? '',
                        'suppressedRequestDate': suppressedRequestDate,
                      };
                      if (shouldResetGeneration) {
                        updatedCfg['lastGeneratedRequestDate'] = '';
                        updatedCfg['lastGeneratedRequestId'] = '';
                        updatedCfg['targetId'] = '';
                      }
                      await _saveCfg(type, updatedCfg);
                      final trackedRequest =
                          await _syncTrackedPeriodicServiceRequestFromConfig(
                        maintenanceBox: _maintenance,
                        invoicesBox: _invoices,
                        propertyId: widget.propertyId,
                        type: type,
                        cfg: updatedCfg,
                        lookupCfg: cfg,
                      );
                      if (trackedRequest != null) {
                        await _saveCfg(
                          type,
                          _periodicServiceConfigWithTrackedRequest(
                            cfg: updatedCfg,
                            request: trackedRequest,
                          ),
                        );
                      }
                      await _clearPeriodicServiceNotificationDismissals(
                        type: type,
                        startDate: scheduleBaseDate,
                        nextDate: effectiveDueDate,
                      );
                      if (_services != null) {
                        await ensurePeriodicServiceRequestsGenerated(
                          servicesBox: _services,
                          maintenanceBox: _maintenance,
                          invoicesBox: _invoices,
                          serviceKeys: {_serviceKey(type)},
                        );
                      }
                      final refreshedCfg = _cfg(type);
                      final generatedDate =
                          _periodicServiceLastGeneratedDateFromConfig(
                              refreshedCfg);
                      final generatedRequestId =
                          (refreshedCfg['targetId'] ?? '').toString().trim();
                      if (generatedDate != null) {
                        await _clearPeriodicServiceNotificationDismissals(
                          type: type,
                          startDate: generatedDate,
                          nextDate: generatedDate,
                        );
                      }
                      if (generatedDate != null &&
                          generatedRequestId.isNotEmpty) {
                        await _clearMaintenanceNotificationDismissal(
                          requestId: generatedRequestId,
                          anchor: generatedDate,
                        );
                      }
                      if (mounted) setState(() {});
                      _showOk('تم حفظ إعدادات الخدمة');
                      if (mounted) setS(() {});
                    },
                    child: Text('حفظ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                    child: ElevatedButton(
                        style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('إلغاء',
                            style: GoogleFonts.cairo(color: Colors.black87)))),
              ]),
              SizedBox(height: 10.h),
              Center(
                child: Text('سجل الطلبات',
                    style: GoogleFonts.cairo(
                        color: Colors.black87, fontWeight: FontWeight.w800)),
              ),
              SizedBox(height: 6.h),
              if (_cleaningRequests().isEmpty)
                Text('لا توجد طلبات بعد',
                    style: GoogleFonts.cairo(color: Colors.black54))
              else
                _scrollList(_cleaningRequests().map((r) {
                  final when = _periodicServiceRequestAnchor(r);
                  return _periodicServiceLogRow(
                    ctx,
                    r,
                    when,
                    setModalState: setS,
                  );
                }).toList()),
            ]),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _openService(String type, {bool replaceCurrent = false}) async {
    if ((type == 'water' || type == 'electricity') &&
        _unitUnderPerUnitBuilding) {
      final mode = _effectiveSharedUnitsMode(type);
      final allowsLocalManagement = type == 'water'
          ? _isUnitsManagedMode(type, mode)
          : mode == 'units';
      if (!allowsLocalManagement) {
        await _promptOpenBuildingSharedService(type);
        return;
      }
    }
    if (type == 'cleaning') {
      return _openCleaning(replaceCurrent: replaceCurrent);
    }
    if (type == 'water') {
      if (_buildingWithUnits) {
        return _openBuildingSharedOccupiedUnitsServiceSettings(
          type,
          replaceCurrent: replaceCurrent,
        );
      }
      return _openWaterSettings(replaceCurrent: replaceCurrent);
    }
    if (type == 'electricity') {
      if (_buildingWithUnits) {
        return _openBuildingSharedOccupiedUnitsServiceSettings(
          type,
          replaceCurrent: replaceCurrent,
        );
      }
      return _openElectricitySettings(replaceCurrent: replaceCurrent);
    }
    if (type == 'internet') {
      return _openInternetSettings(replaceCurrent: replaceCurrent);
    }
    if (type == 'elevator') {
      return _openElevatorSimple(replaceCurrent: replaceCurrent);
    }
  }

  Future<void> _openBuildingSharedOccupiedUnitsServiceSettings(
    String type, {
    bool replaceCurrent = false,
  }) async {
    var cfg = _cfg(type);
    var managementMode = _sharedUnitsModeForType(type, cfg);
    var reviewedManagementMode = managementMode;
    var managementModeFieldVersion = 0;
    var dueDate = (cfg['nextDueDate'] is String)
        ? (DateTime.tryParse(cfg['nextDueDate']) ?? KsaTime.today())
        : KsaTime.today();
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final legacyRequests = type == 'water'
        ? _waterPercentRequestsFromCfg(cfg)
        : _electricityPercentRequestsFromCfg(cfg);
    var lastAmount = 0.0;
    for (final request in _serviceRequests(type)) {
      if (request.cost > 0) {
        lastAmount = request.cost;
        break;
      }
    }
    if (lastAmount <= 0) {
      for (final row in legacyRequests.reversed) {
        final amount = ((row['amount'] as num?)?.toDouble() ??
                _numParse((row['amount'] ?? '').toString()))
            .toDouble();
        if (amount > 0) {
          lastAmount = amount;
          break;
        }
      }
    }
    final amountCtl = TextEditingController(
      text: _periodicServiceEditableAmountText(
        cfg,
        fallbackAmount: lastAmount,
      ),
    );

    Map<String, Contract> occupiedContractsByUnitId() {
      final now = KsaTime.now();
      final candidates = _contracts.values.where((c) {
        return !c.isTerminated &&
            !c.isArchived &&
            c.startDate.isBefore(now.add(const Duration(days: 1))) &&
            c.endDate.isAfter(now.subtract(const Duration(days: 1)));
      }).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      final mapped = <String, Contract>{};
      for (final contract in candidates) {
        final propertyId = contract.propertyId.trim();
        if (propertyId.isEmpty || mapped.containsKey(propertyId)) continue;
        mapped[propertyId] = contract;
      }
      return mapped;
    }

    Map<String, Tenant> tenantsById() {
      return {
        for (final tenant in _tenants.values)
          if (tenant.id.trim().isNotEmpty) tenant.id.trim(): tenant,
      };
    }

    List<Property> activeOccupiedUnits() {
      final now = KsaTime.now();
      final occupiedIds = _contracts.values
          .where((c) =>
              !c.isTerminated &&
              !c.isArchived &&
              c.startDate.isBefore(now.add(const Duration(days: 1))) &&
              c.endDate.isAfter(now.subtract(const Duration(days: 1))))
          .map((c) => c.propertyId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      return _units.where((unit) => occupiedIds.contains(unit.id)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    List<Map<String, dynamic>> activeEqualShareRows() {
      final units = activeOccupiedUnits();
      if (units.isEmpty) return <Map<String, dynamic>>[];
      final rows = <Map<String, dynamic>>[];
      final perRaw = 100 / units.length;
      final perRounded = ((perRaw * 100).roundToDouble()) / 100.0;
      var distributed = 0.0;
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        final isLast = i == units.length - 1;
        final percent = isLast ? 100 - distributed : perRounded;
        if (!isLast) distributed += perRounded;
        rows.add({
          'unitId': unit.id,
          'unitName': unit.name,
          'percent': percent,
        });
      }
      return rows;
    }

    List<Map<String, dynamic>> activePreviewRows() {
      final totalAmount = _numParse(amountCtl.text.trim());
      final units = activeOccupiedUnits();
      if (totalAmount <= 0 || units.isEmpty) return <Map<String, dynamic>>[];
      final rows = <Map<String, dynamic>>[];
      final perRaw = totalAmount / units.length;
      final perRounded = ((perRaw * 100).roundToDouble()) / 100.0;
      var distributed = 0.0;
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        final isLast = i == units.length - 1;
        final amount = isLast
            ? (totalAmount - distributed).clamp(0.0, totalAmount).toDouble()
            : perRounded;
        if (!isLast) distributed += perRounded;
        rows.add({
          'unitId': unit.id,
          'unitName': unit.name,
          'amount': amount,
        });
      }
      return rows;
    }

    List<Map<String, dynamic>> distributionRows({
      Set<String> ownerAdvancedUnitIds = const <String>{},
    }) {
      final preview = activePreviewRows();
      if (preview.isEmpty) return <Map<String, dynamic>>[];
      final amountsByUnitId = <String, double>{
        for (final row in preview)
          (row['unitId'] ?? '').toString().trim():
              ((row['amount'] as num?)?.toDouble() ?? 0.0),
      };
      final contractsByUnitId = occupiedContractsByUnitId();
      final tenantMap = tenantsById();
      return activeOccupiedUnits().map((unit) {
        final contract = contractsByUnitId[unit.id];
        final tenantId = (contract?.tenantId ?? '').trim();
        final tenant = tenantId.isEmpty ? null : tenantMap[tenantId];
        return <String, dynamic>{
          'unitId': unit.id,
          'unitName': unit.name,
          'amount': amountsByUnitId[unit.id] ?? 0.0,
          'contractId': contract?.id ?? '',
          'tenantId': tenantId,
          'tenantName': tenant?.fullName ?? '',
          'ownerAdvanced': ownerAdvancedUnitIds.contains(unit.id),
          'receiptInvoiceId': '',
          'receiptSerialNo': '',
          'paidAt': '',
        };
      }).toList();
    }

    String buildSharedRequestDescription(
      DateTime cycleDate,
      double totalAmount,
      List<Map<String, dynamic>> rows,
    ) {
      final buffer = StringBuffer()
        ..writeln('${_periodicServiceRequestTitle(type)}')
        ..writeln('تاريخ الدورة: ${_fmt(cycleDate)}')
        ..writeln('المبلغ الكلي: ${totalAmount.toStringAsFixed(2)} ريال')
        ..writeln('طريقة التوزيع: بالتساوي على الشقق المؤجرة فقط')
        ..writeln('عدد الشقق المؤجرة: ${rows.length}');
      if (rows.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('تفاصيل التوزيع:');
        for (final row in rows) {
          final unitName = (row['unitName'] ?? '').toString().trim();
          final tenantName = (row['tenantName'] ?? '').toString().trim();
          final contractId = (row['contractId'] ?? '').toString().trim();
          final amount =
              ((row['amount'] as num?)?.toDouble() ?? 0.0).toDouble();
          buffer.write('- $unitName: ${amount.toStringAsFixed(2)} ريال');
          if (tenantName.isNotEmpty) {
            buffer.write(' | المستأجر: $tenantName');
          }
          if (contractId.isNotEmpty) {
            buffer.write(' | العقد: $contractId');
          }
          buffer.writeln();
        }
      }
      return buffer.toString().trim();
    }

    MaintenanceRequest? existingRequestForDue(DateTime dueDate) {
      final normalizedDue = KsaTime.dateOnly(dueDate);
      return _maintenance.values.firstWhereOrNull((request) {
        if (request.propertyId != widget.propertyId) return false;
        if (request.isArchived) return false;
        if (request.status == MaintenanceStatus.canceled) return false;
        if (_requestHasCanceledInvoice(request)) return false;
        return _matchesPeriodicServiceRequestForDue(
          request,
          propertyId: widget.propertyId,
          type: type,
          dueDate: normalizedDue,
        );
      });
    }

    Future<MaintenanceRequest?> createOrUpdateCycleRequest({
      required DateTime cycleDate,
      required double totalAmount,
      required List<Map<String, dynamic>> rows,
    }) async {
      final description = _buildSharedServiceCycleDescription(
        type: type,
        cycleDate: cycleDate,
        totalAmount: totalAmount,
        rows: rows,
      );
      final providerSnapshot = <String, dynamic>{
        'kind': 'shared_service_cycle',
        'serviceType': type,
        'cycleDate': cycleDate.toIso8601String(),
        'totalAmount': totalAmount,
        'unitRows': rows,
        'collectedAmount': 0.0,
      };
      final completedAt = KsaTime.now();
      final existing = existingRequestForDue(cycleDate);
      if (existing != null) {
        if (_requestHasActiveInvoice(existing) ||
            existing.status == MaintenanceStatus.completed) {
          _showErr('يوجد طلب لهذه الدورة بالفعل ولا يمكن تكراره.');
          return null;
        }
        existing.title = _periodicServiceRequestTitle(type);
        existing.description = description;
        existing.requestType = _periodicServiceRequestTypeLabel(type);
        existing.priority = MaintenancePriority.medium;
        existing.status = MaintenanceStatus.completed;
        existing.scheduledDate = cycleDate;
        existing.executionDeadline = cycleDate;
        existing.completedDate = completedAt;
        existing.cost = totalAmount;
        existing.assignedTo = 'إدارة العمارة';
        existing.providerSnapshot = providerSnapshot;
        existing.tenantId = '';
        existing.periodicServiceType = type;
        existing.periodicCycleDate = cycleDate;
        await saveMaintenanceRequestLocalAndSync(existing);
        final invoiceId = await createOrUpdateInvoiceForMaintenance(existing);
        if (invoiceId.trim().isNotEmpty) {
          existing.invoiceId = invoiceId;
          await saveMaintenanceRequestLocalAndSync(existing);
        }
        return existing;
      }
      final request = MaintenanceRequest(
        serialNo: nextMaintenanceRequestSerialForBox(_maintenance),
        propertyId: widget.propertyId,
        tenantId: '',
        title: _periodicServiceRequestTitle(type),
        description: description,
        requestType: _periodicServiceRequestTypeLabel(type),
        priority: MaintenancePriority.medium,
        status: MaintenanceStatus.completed,
        scheduledDate: cycleDate,
        executionDeadline: cycleDate,
        completedDate: completedAt,
        cost: totalAmount,
        assignedTo: 'إدارة العمارة',
        periodicServiceType: type,
        providerSnapshot: providerSnapshot,
        periodicCycleDate: cycleDate,
      );
      await saveMaintenanceRequestLocalAndSync(request);
      final invoiceId = await createOrUpdateInvoiceForMaintenance(request);
      if (invoiceId.trim().isNotEmpty) {
        request.invoiceId = invoiceId;
        await saveMaintenanceRequestLocalAndSync(request);
      }
      return request;
    }

    List<Property> occupiedUnits() {
      final now = KsaTime.now();
      final occupiedIds = _contracts.values
          .where((c) =>
              !c.isTerminated &&
              !c.isArchived &&
              c.startDate.isBefore(now.add(const Duration(days: 1))) &&
              c.endDate.isAfter(now.subtract(const Duration(days: 1))))
          .map((c) => c.propertyId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      return _units.where((unit) => occupiedIds.contains(unit.id)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    List<Map<String, dynamic>> equalShareRows() {
      final units = occupiedUnits();
      if (units.isEmpty) return <Map<String, dynamic>>[];
      final rows = <Map<String, dynamic>>[];
      final perRaw = 100 / units.length;
      final perRounded = ((perRaw * 100).roundToDouble()) / 100.0;
      var distributed = 0.0;
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        final isLast = i == units.length - 1;
        final percent = isLast ? 100 - distributed : perRounded;
        if (!isLast) distributed += perRounded;
        rows.add({
          'unitId': unit.id,
          'unitName': unit.name,
          'percent': percent,
        });
      }
      return rows;
    }

    List<Map<String, dynamic>> previewRows() {
      final totalAmount = _numParse(amountCtl.text.trim());
      final units = occupiedUnits();
      if (totalAmount <= 0 || units.isEmpty) return <Map<String, dynamic>>[];
      final rows = <Map<String, dynamic>>[];
      final perRaw = totalAmount / units.length;
      final perRounded = ((perRaw * 100).roundToDouble()) / 100.0;
      var distributed = 0.0;
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        final isLast = i == units.length - 1;
        final amount = isLast
            ? (totalAmount - distributed).clamp(0.0, totalAmount).toDouble()
            : perRounded;
        if (!isLast) distributed += perRounded;
        rows.add({
          'unitId': unit.id,
          'unitName': unit.name,
          'amount': amount,
        });
      }
      return rows;
    }

    Future<Set<String>?> pickPaidUnits(BuildContext context) async {
      final rows = distributionRows();
      if (rows.isEmpty) return null;
      final selectedByUnitId = <String, bool>{
        for (final row in rows) (row['unitId'] ?? '').toString().trim(): true,
      };
      return showDialog<Set<String>>(
        context: context,
        builder: (dialogCtx) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (dialogCtx, setDialogState) => AlertDialog(
              insetPadding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              title: Text(
                'تحديد الوحدات المسددة لهذه الدورة',
                style: GoogleFonts.cairo(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                ),
              ),
              contentPadding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
              content: SizedBox(
                width: MediaQuery.of(dialogCtx).size.width * 0.9,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogCtx).size.height * 0.74,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          'ضع علامة صح فقط على الوحدات التي تم تحصيل حصتها فعليًا الآن. عند التأكيد سيتم إصدار سند قبض لكل وحدة محددة وتسجيلها كمدفوعة. إذا كان هناك مستأجر لم يسدد بعد وستتحمل الإدارة حصته الآن، قم بإزالة علامة الصح عنه، وستبقى حصته بانتظار السداد حتى يتم تحصيلها لاحقًا.',
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF475569),
                            fontSize: 12.sp,
                            height: 1.7,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: rows.map((row) {
                              final unitId =
                                  (row['unitId'] ?? '').toString().trim();
                              final unitName =
                                  (row['unitName'] ?? '').toString().trim();
                              final tenantName =
                                  (row['tenantName'] ?? '').toString().trim();
                              final amount = _sharedServiceCycleRowAmount(row);
                              final selected = selectedByUnitId[unitId] == true;
                              final helperText = selected
                                  ? 'سيتم إصدار سند قبض لهذه الوحدة عند التأكيد.'
                                  : 'ستتحمل الإدارة هذه الحصة الآن وتبقى بانتظار السداد.';
                              return Container(
                                margin: EdgeInsets.only(bottom: 8.h),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFFF0FDF4)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFFBBF7D0)
                                        : Colors.black.withOpacity(0.08),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: selected,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10.w,
                                    vertical: 4.h,
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  dense: true,
                                  activeColor: const Color(0xFF15803D),
                                  title: Text(
                                    unitName,
                                    style: GoogleFonts.cairo(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${tenantName.isEmpty ? 'بدون اسم مستأجر' : tenantName}\nالحصة: ${amount.toStringAsFixed(2)} ريال\n$helperText',
                                    style: GoogleFonts.cairo(
                                      color: Colors.black54,
                                      fontSize: 12.sp,
                                      height: 1.55,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedByUnitId[unitId] = value == true;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: _actionButtonStyle(const Color(0xFFDCFCE7)),
                          onPressed: () {
                            final paidUnitIds = selectedByUnitId.entries
                                .where((entry) => entry.value == true)
                                .map((entry) => entry.key)
                                .toSet();
                            Navigator.of(dialogCtx).pop(paidUnitIds);
                          },
                          child: Text(
                            'تأكيد',
                            style:
                                GoogleFonts.cairo(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.cairo(
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<int> issuePaidReceiptsForCycle({
      required MaintenanceRequest request,
      required Set<String> paidUnitIds,
    }) async {
      var issuedCount = 0;
      for (final unitId in paidUnitIds) {
        final row = _sharedServiceCycleRows(request).firstWhereOrNull(
          (item) => (item['unitId'] ?? '').toString().trim() == unitId,
        );
        if (row == null) continue;
        final invoice = await _createSharedServiceReceipt(
          request: request,
          row: row,
        );
        if (invoice == null) continue;
        await _markSharedServiceCycleRowPaid(
          request: request,
          unitId: unitId,
          invoice: invoice,
        );
        issuedCount++;
      }
      return issuedCount;
    }

    Map<String, dynamic> buildUnitsFixedCfg() {
      if (type == 'water') {
        return {
          ...cfg,
          'serviceType': type,
          'sharedUnitsMode': 'units_fixed',
          'sharedPercentUnitShares': <Map<String, dynamic>>[],
          'payer': '',
          'waterBillingMode': '',
          'waterSharedMethod': '',
          'sharePercent': null,
          'waterPercentRequests': _waterPercentRequestsFromCfg(cfg),
          'totalWaterAmount': null,
          'waterPerInstallment': null,
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
          'waterInstallments': <Map<String, dynamic>>[],
          'remainingInstallmentsCount': 0,
          'nextDueDate': '',
          'dueDay': 0,
          'recurrenceMonths': 0,
          'remindBeforeDays': 0,
          'waterMeterNo': '',
        };
      }
      return {
        ...cfg,
        'serviceType': type,
        'sharedUnitsMode': 'units',
        'sharedPercentUnitShares': <Map<String, dynamic>>[],
        'payer': '',
        'electricityBillingMode': '',
        'electricitySharedMethod': '',
        'electricitySharePercent': null,
        'electricityPercentRequests': _electricityPercentRequestsFromCfg(cfg),
        'electricityMeterNo': '',
        'nextDueDate': '',
        'dueDay': 0,
        'recurrenceMonths': 0,
        'remindBeforeDays': 0,
      };
    }

    Map<String, dynamic> buildUnitsSeparateCfg() {
      return {
        ...cfg,
        'serviceType': type,
        'sharedUnitsMode': 'units_separate',
        'sharedPercentUnitShares': <Map<String, dynamic>>[],
        'payer': '',
        'waterBillingMode': '',
        'waterSharedMethod': '',
        'sharePercent': null,
        'waterPercentRequests': _waterPercentRequestsFromCfg(cfg),
        'totalWaterAmount': null,
        'waterPerInstallment': null,
        'waterLinkedContractId': '',
        'waterLinkedTenantId': '',
        'waterInstallments': <Map<String, dynamic>>[],
        'remainingInstallmentsCount': 0,
        'nextDueDate': '',
        'dueDay': 0,
        'recurrenceMonths': 0,
        'remindBeforeDays': 0,
        'waterMeterNo': '',
      };
    }

    Map<String, dynamic> buildSharedConfig() {
      final equalShares = activeEqualShareRows();
      if (type == 'water') {
        return {
          ...cfg,
          'serviceType': type,
          'sharedUnitsMode': 'shared_percent',
          'sharedPercentUnitShares': equalShares,
          'payer': 'owner',
          'waterBillingMode': '',
          'waterSharedMethod': '',
          'sharePercent': null,
          'totalWaterAmount': null,
          'waterPerInstallment': null,
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
          'waterInstallments': <Map<String, dynamic>>[],
          'remainingInstallmentsCount': 0,
          'waterMeterNo': '',
          'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
          'dueDay': dueDate.day,
          'defaultAmount': _numParse(amountCtl.text.trim()),
          'recurrenceMonths': 1,
          'remindBeforeDays': remindBeforeDays,
          'waterPercentRequests': _waterPercentRequestsFromCfg(cfg),
        };
      }
      return {
        ...cfg,
        'serviceType': type,
        'sharedUnitsMode': 'shared_percent',
        'sharedPercentUnitShares': equalShares,
        'payer': 'owner',
        'electricityBillingMode': '',
        'electricitySharedMethod': '',
        'electricitySharePercent': null,
        'electricityMeterNo': '',
        'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
        'dueDay': dueDate.day,
        'defaultAmount': _numParse(amountCtl.text.trim()),
        'recurrenceMonths': 1,
        'remindBeforeDays': remindBeforeDays,
        'electricityPercentRequests': _electricityPercentRequestsFromCfg(cfg),
      };
    }

    Future<void> applyWaterSeparateModeToUnits() async {
      for (final unit in _units) {
        final unitCfg = _cfgForProperty(unit.id, 'water');
        final nextUnitCfg = _buildWaterSeparateUnitCfg(unitCfg);
        await _saveCfgForProperty(unit.id, 'water', nextUnitCfg);
      }
    }

    bool waterSeparateModeNeedsUnitSync() {
      for (final unit in _units) {
        final unitCfg = _cfgForProperty(unit.id, 'water');
        final nextUnitCfg = _buildWaterSeparateUnitCfg(unitCfg);
        if (!_deepValueEquals(unitCfg, nextUnitCfg)) {
          return true;
        }
      }
      return false;
    }

    Future<void> save(BuildContext ctx) async {
      final validMode = managementMode == 'shared_percent' ||
          (type == 'water'
              ? managementMode == 'units_fixed' ||
                  managementMode == 'units_separate'
              : managementMode == 'units');
      if (!validMode) {
        _showErr('يرجى اختيار طريقة الإدارة أولًا.');
        return;
      }
      if (managementMode == 'shared_percent' && _units.isEmpty) {
        _showErr('لا توجد وحدات مرتبطة بهذه العمارة.');
        return;
      }
      final currentMode = _sharedUnitsModeForType(type, cfg);
      if (managementMode != currentMode &&
          reviewedManagementMode != managementMode) {
        final canChangeMode = await _confirmSharedServiceManagementModeChange(
          context: ctx,
          type: type,
          fromMode: currentMode,
          toMode: managementMode,
        );
        if (!canChangeMode) return;
        reviewedManagementMode = managementMode;
      }
      final next = managementMode == 'shared_percent'
          ? buildSharedConfig()
          : (type == 'water'
              ? (managementMode == 'units_separate'
                  ? buildUnitsSeparateCfg()
                  : buildUnitsFixedCfg())
              : buildUnitsFixedCfg());
      final shouldSyncWaterUnits = type == 'water' &&
          managementMode == 'units_separate' &&
          waterSeparateModeNeedsUnitSync();
      if (_deepValueEquals(cfg, next) && !shouldSyncWaterUnits) {
        _showInfo('لا توجد تغييرات للحفظ');
        return;
      }
      await _saveCfg(type, next);
      if (type == 'water' && managementMode == 'units_separate') {
        await applyWaterSeparateModeToUnits();
      }
      cfg = next;
      reviewedManagementMode = managementMode;
      _showOk('تم حفظ الإعدادات');
      if (mounted) setState(() {});
    }

    Widget requestsLog(BuildContext ctx, void Function(void Function()) setS) {
      final requests = _serviceRequests(type);
      if (requests.isEmpty) {
        return Text(
          'لا توجد طلبات بعد',
          style: GoogleFonts.cairo(color: Colors.black54),
        );
      }
      return _scrollList(requests.map((request) {
        final when = _periodicServiceRequestAnchor(request);
        return _periodicServiceLogRow(
          ctx,
          request,
          when,
          setModalState: setS,
        );
      }).toList());
    }

    Widget settingsActionsRow(BuildContext ctx) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: _actionButtonStyle(const Color(0xFFDDEAFE)),
              onPressed: () => save(ctx),
              child: Text(
                'حفظ',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: ElevatedButton(
              style: _actionButtonStyle(const Color(0xFFF1F5F9)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(color: Colors.black87),
              ),
            ),
          ),
        ],
      );
    }

    await _openServicePage(
      'الخدمات المشتركة - ${_title(type)}',
      StatefulBuilder(
        builder: (ctx, setS) {
          final liveOccupiedUnits = activeOccupiedUnits();
          final livePreviewRows = activePreviewRows();
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${type}_shared_management_$managementModeFieldVersion',
                  ),
                  initialValue: managementMode.isEmpty ? null : managementMode,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('طريقة الإدارة'),
                  items: [
                    DropdownMenuItem(
                      value: type == 'water' ? 'units_fixed' : 'units',
                      child: Text(
                        _sharedUnitsManagedModeLabel(
                          type,
                          type == 'water' ? 'units_fixed' : 'units',
                        ),
                      ),
                    ),
                    if (type == 'water')
                      const DropdownMenuItem(
                        value: 'units_separate',
                        child: Text('الإدارة من الوحدات (منفصل)'),
                      ),
                    const DropdownMenuItem(
                      value: 'shared_percent',
                      child: Text('التوزيع على الشقق المؤجرة بالتساوي'),
                    ),
                  ],
                  onChanged: (v) async {
                    final nextMode =
                        await _resolveSharedServiceManagementModeSelection(
                      context: ctx,
                      type: type,
                      persistedMode: _sharedUnitsModeFromCfg(cfg),
                      currentDraftMode: managementMode,
                      attemptedMode: v,
                    );
                    if (!ctx.mounted) return;
                    setS(() {
                      managementMode = nextMode;
                      reviewedManagementMode = nextMode;
                      managementModeFieldVersion++;
                    });
                  },
                ),
                SizedBox(height: 8.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Text(
                    managementMode == 'shared_percent'
                        ? 'عند التنفيذ يُقسَّم مبلغ الفاتورة بالتساوي على الشقق المؤجرة فقط، وأي حصة غير مسددة تبقى بانتظار السداد على المستأجر ولا تُعاد على غيره.'
                        : (type == 'water' &&
                                managementMode == 'units_separate')
                            ? 'عند اختيار هذا الوضع تُضبط المياه كوضع منفصل على جميع الوحدات الحالية، وتبقى الوحدات الجديدة على نفس السياسة من العمارة.'
                            : (type == 'water' &&
                                    managementMode == 'units_fixed')
                                ? 'عند اختيار هذا الوضع يجب ضبط مبلغ المياه المقطوع لكل وحدة من داخل الوحدة قبل إنشاء عقدها.'
                                : 'عند اختيار هذا الوضع تبقى إدارة ${_title(type)} من داخل كل وحدة على حدة، ولا يتم توزيع الخدمة من العمارة.',
                    style: GoogleFonts.cairo(color: Colors.black87),
                  ),
                ),
                if (managementMode == 'shared_percent') ...[
                  SizedBox(height: 10.h),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'تاريخ الفاتورة القادم',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                    subtitle: Text(
                      _fmt(dueDate),
                      style: GoogleFonts.cairo(
                        color: Colors.black54,
                        fontSize: 12.sp,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.black54,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: KsaTime.dateOnly(dueDate),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setS(() => dueDate = KsaTime.dateOnly(picked));
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: 1,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('الدورية'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('شهري')),
                    ],
                    onChanged: null,
                  ),
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<int>(
                    initialValue: remindBeforeDays,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('موعد التنبيه قبل'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                      DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                      DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                      DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                    ],
                    onChanged: (v) =>
                        setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'مبلغ الفاتورة الحالية',
                    style: GoogleFonts.cairo(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: amountCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.cairo(color: Colors.black87),
                    decoration: _plainFieldDecoration(hintText: '0.00'),
                    onChanged: (_) => setS(() {}),
                  ),
                  SizedBox(height: 10.h),
                  settingsActionsRow(ctx),
                  SizedBox(height: 10.h),
                  Text(
                    'الشقق المؤجرة فقط',
                    style: GoogleFonts.cairo(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'يتم التوزيع بالتساوي على الشقق ذات العقود النشطة وقت التنفيذ.',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF475569),
                      fontSize: 12.sp,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  if (liveOccupiedUnits.isEmpty)
                    Text(
                      'لا توجد شقق مؤجرة حاليًا.',
                      style: GoogleFonts.cairo(color: Colors.black54),
                    )
                  else
                    ...liveOccupiedUnits.map((unit) {
                      final preview = livePreviewRows.firstWhereOrNull(
                        (item) => (item['unitId'] ?? '').toString() == unit.id,
                      );
                      final amount =
                          ((preview?['amount'] as num?)?.toDouble() ?? 0.0)
                              .toDouble();
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                                color: Colors.black.withOpacity(0.08)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unit.name,
                                style: GoogleFonts.cairo(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                amount > 0
                                    ? 'المبلغ: ${amount.toStringAsFixed(2)} ريال'
                                    : 'بانتظار إدخال مبلغ الفاتورة الحالية.',
                                style: GoogleFonts.cairo(
                                  color: const Color(0xFF475569),
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  if (liveOccupiedUnits.isNotEmpty) ...[
                    SizedBox(height: 4.h),
                    Text(
                      'عدد الشقق المؤجرة الحالية: ${liveOccupiedUnits.length}',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF475569),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                  SizedBox(height: 10.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: _actionButtonStyle(const Color(0xFFDCFCE7)),
                      onPressed: () async {
                        if (liveOccupiedUnits.isEmpty) {
                          _showErr(
                              'لا توجد شقق مؤجرة حاليًا لتوزيع المبلغ عليها.');
                          return;
                        }
                        final amount = _numParse(amountCtl.text.trim());
                        if (amount <= 0) {
                          _showErr('مبلغ الفاتورة غير صالح');
                          return;
                        }
                        final unitAmounts = activePreviewRows();
                        if (unitAmounts.isEmpty) {
                          _showErr('تعذر توزيع المبلغ على الشقق المؤجرة');
                          return;
                        }
                        final nowDue = KsaTime.dateOnly(dueDate);
                        final canExecuteNow =
                            await _ensureSharedServiceExecutionDateReached(
                          type: type,
                          cycleDate: nowDue,
                        );
                        if (!canExecuteNow) return;
                        final paidUnitIds = await pickPaidUnits(ctx);
                        if (paidUnitIds == null) return;
                        final allUnitIds = unitAmounts
                            .map((row) =>
                                (row['unitId'] ?? '').toString().trim())
                            .where((id) => id.isNotEmpty)
                            .toSet();
                        final ownerAdvancedUnitIds =
                            allUnitIds.difference(paidUnitIds);
                        final nextDue = _addMonthsSafe(nowDue, 1);
                        final request = await createOrUpdateCycleRequest(
                          cycleDate: nowDue,
                          totalAmount: amount,
                          rows: distributionRows(
                            ownerAdvancedUnitIds: ownerAdvancedUnitIds,
                          ),
                        );
                        if (request == null) return;
                        final issuedReceipts = await issuePaidReceiptsForCycle(
                          request: request,
                          paidUnitIds: paidUnitIds,
                        );
                        final baseCfg = buildSharedConfig();
                        cfg = _periodicServiceConfigWithTrackedRequest(
                          cfg: {
                            ...baseCfg,
                            'defaultAmount': 0.0,
                            'nextDueDate': nextDue.toIso8601String(),
                            'dueDay': nextDue.day,
                            'suppressedRequestDate': '',
                          },
                          request: request,
                        );
                        dueDate = nextDue;
                        amountCtl.clear();
                        await _saveCfg(type, cfg);
                        if (mounted) {
                          setState(() {});
                          setS(() {});
                        }
                        _showOk(
                          issuedReceipts > 0
                              ? 'تم تنفيذ الدورة، وإصدار $issuedReceipts سند تحصيل، وتحديث الموعد التالي.'
                              : 'تم تنفيذ الدورة وتحديث الموعد التالي.',
                        );
                      },
                      icon: const Icon(Icons.playlist_add_check_circle_rounded),
                      label: Text(
                        'تنفيذ الفاتورة الحالية',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    'سجل الطلبات',
                    style: GoogleFonts.cairo(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  requestsLog(ctx, setS),
                ],
                if (managementMode != 'shared_percent') ...[
                  SizedBox(height: 12.h),
                  settingsActionsRow(ctx),
                ],
              ],
            ),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _openBuildingSharedUnitsServiceSettings(
    String type, {
    bool replaceCurrent = false,
  }) async {
    var cfg = _cfg(type);
    var managementMode = _sharedUnitsModeFromCfg(cfg);
    var reviewedManagementMode = managementMode;
    var managementModeFieldVersion = 0;
    var dueDate = (cfg['nextDueDate'] is String)
        ? (DateTime.tryParse(cfg['nextDueDate']) ?? KsaTime.today())
        : KsaTime.today();
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final shareCtrls = <String, TextEditingController>{};
    for (final row in _buildingSharedUnitRows(cfg)) {
      final unitId = (row['unitId'] ?? '').toString();
      final percent = ((row['percent'] as num?)?.toDouble() ?? 0.0).toString();
      shareCtrls[unitId] = TextEditingController(text: percent);
    }
    final existingRequests = type == 'water'
        ? _waterPercentRequestsFromCfg(cfg)
        : _electricityPercentRequestsFromCfg(cfg);
    var lastAmount = 0.0;
    for (final row in existingRequests.reversed) {
      final amount = ((row['amount'] as num?)?.toDouble() ??
              _numParse((row['amount'] ?? '').toString()))
          .toDouble();
      if (amount > 0) {
        lastAmount = amount;
        break;
      }
    }
    final amountCtl = TextEditingController(
      text: _periodicServiceEditableAmountText(
        cfg,
        fallbackAmount: lastAmount,
      ),
    );

    List<Map<String, dynamic>> collectShares() {
      return _units.map((unit) {
        final ctl = shareCtrls[unit.id];
        return <String, dynamic>{
          'unitId': unit.id,
          'unitName': unit.name,
          'percent': _numParse(ctl?.text.trim() ?? ''),
        };
      }).toList();
    }

    double sharesTotal() {
      return _sharedUnitsPercentTotal(collectShares());
    }

    bool hasNegativeShares(List<Map<String, dynamic>> shares) {
      return shares.any((item) {
        return _numParse((item['percent'] ?? '').toString()) < 0;
      });
    }

    List<Map<String, dynamic>> currentRequestRows() {
      return type == 'water'
          ? _waterPercentRequestsFromCfg(cfg)
          : _electricityPercentRequestsFromCfg(cfg);
    }

    List<Map<String, dynamic>> previewRows() {
      final totalAmount = _numParse(amountCtl.text.trim());
      final shares = collectShares()
          .where((item) => _numParse((item['percent'] ?? '').toString()) > 0)
          .toList();
      final totalPercent = _sharedUnitsPercentTotal(shares);
      if (totalAmount <= 0 || shares.isEmpty || totalPercent <= 0) {
        return <Map<String, dynamic>>[];
      }
      final rows = <Map<String, dynamic>>[];
      var distributed = 0.0;
      for (var i = 0; i < shares.length; i++) {
        final share = shares[i];
        final isLast = i == shares.length - 1;
        final percent = _numParse((share['percent'] ?? '').toString());
        final amount = isLast
            ? (totalAmount - distributed).clamp(0.0, totalAmount).toDouble()
            : ((totalAmount * percent / totalPercent) * 100).roundToDouble() /
                100.0;
        if (!isLast) distributed += amount;
        rows.add({
          'unitId': (share['unitId'] ?? '').toString(),
          'unitName': (share['unitName'] ?? '').toString(),
          'percent': percent,
          'amount': amount,
        });
      }
      return rows;
    }

    Future<void> showDistributionDetails(
      BuildContext ctx,
      Map<String, dynamic> row,
    ) async {
      final raw = row['unitAmounts'];
      final unitAmounts = raw is List
          ? raw
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
              .whereType<Map<String, dynamic>>()
              .toList()
          : const <Map<String, dynamic>>[];
      if (unitAmounts.isEmpty) return;
      await showDialog<void>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: Text(
            'توزيع مبلغ الفاتورة',
            style: GoogleFonts.cairo(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: unitAmounts.map((item) {
                  final unitName = (item['unitName'] ?? '').toString().trim();
                  final percent = _numParse((item['percent'] ?? '').toString());
                  final amount =
                      ((item['amount'] as num?)?.toDouble() ?? 0.0).toDouble();
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: Text(
                      '$unitName: ${amount.toStringAsFixed(2)} ريال (${percent.toStringAsFixed(2)}%)',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'إغلاق',
                style: GoogleFonts.cairo(color: const Color(0xFF0F766E)),
              ),
            ),
          ],
        ),
      );
    }

    Widget requestsLog(BuildContext ctx, void Function(void Function()) setS) {
      final rows = currentRequestRows();
      if (rows.isEmpty) {
        return Text(
          'لا توجد عمليات تنفيذ بعد',
          style: GoogleFonts.cairo(color: Colors.black54),
        );
      }
      return _scrollList(rows.reversed.map((row) {
        final id = (row['id'] ?? '').toString();
        final due = DateTime.tryParse((row['date'] ?? '').toString()) ??
            KsaTime.today();
        final amount = ((row['amount'] as num?)?.toDouble() ??
                _numParse((row['amount'] ?? '').toString()))
            .toDouble();
        final unitCount = row['unitAmounts'] is List
            ? (row['unitAmounts'] as List).whereType<Map>().length
            : 0;
        return Dismissible(
          key: ValueKey('${type}_shared_$id'),
          direction: Directionality.of(ctx) == TextDirection.rtl
              ? DismissDirection.endToStart
              : DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          onDismissed: (_) async {
            final nextRows = currentRequestRows().where((item) {
              return (item['id'] ?? '').toString() != id;
            }).toList();
            cfg = {
              ...cfg,
              if (type == 'water')
                'waterPercentRequests': nextRows
              else
                'electricityPercentRequests': nextRows,
            };
            await _saveCfg(type, cfg);
            if (mounted) setS(() {});
          },
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'فاتورة ${_title(type)}',
              style: GoogleFonts.cairo(color: Colors.black87),
            ),
            subtitle: Text(
              'موعد التنفيذ: ${_fmt(due)}\nالمبلغ: ${amount.toStringAsFixed(2)} ريال\nالوحدات الموزعة: $unitCount',
              style: GoogleFonts.cairo(
                color: Colors.black54,
                fontSize: 12.sp,
              ),
            ),
            trailing: TextButton(
              onPressed: () => showDistributionDetails(ctx, row),
              child: Text(
                'عرض التوزيع',
                style: GoogleFonts.cairo(
                  color: const Color(0xFF0F766E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }).toList());
    }

    Map<String, dynamic> buildUnitsManagedCfg() {
      if (type == 'water') {
        return {
          ...cfg,
          'serviceType': type,
          'sharedUnitsMode': 'units',
          'sharedPercentUnitShares': <Map<String, dynamic>>[],
          'payer': '',
          'waterBillingMode': '',
          'waterSharedMethod': '',
          'sharePercent': null,
          'waterPercentRequests': _waterPercentRequestsFromCfg(cfg),
          'totalWaterAmount': null,
          'waterPerInstallment': null,
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
          'waterInstallments': <Map<String, dynamic>>[],
          'remainingInstallmentsCount': 0,
          'nextDueDate': '',
          'dueDay': 0,
          'recurrenceMonths': 0,
          'remindBeforeDays': 0,
          'waterMeterNo': '',
        };
      }
      return {
        ...cfg,
        'serviceType': type,
        'sharedUnitsMode': 'units',
        'sharedPercentUnitShares': <Map<String, dynamic>>[],
        'payer': '',
        'electricityBillingMode': '',
        'electricitySharedMethod': '',
        'electricitySharePercent': null,
        'electricityPercentRequests': _electricityPercentRequestsFromCfg(cfg),
        'electricityMeterNo': '',
        'nextDueDate': '',
        'dueDay': 0,
        'recurrenceMonths': 0,
        'remindBeforeDays': 0,
      };
    }

    Map<String, dynamic> buildSharedPercentCfg() {
      final shares = collectShares();
      if (type == 'water') {
        return {
          ...cfg,
          'serviceType': type,
          'sharedUnitsMode': 'shared_percent',
          'sharedPercentUnitShares': shares,
          'payer': 'owner',
          'waterBillingMode': '',
          'waterSharedMethod': '',
          'sharePercent': null,
          'totalWaterAmount': null,
          'waterPerInstallment': null,
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
          'waterInstallments': <Map<String, dynamic>>[],
          'remainingInstallmentsCount': 0,
          'waterMeterNo': '',
          'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
          'dueDay': dueDate.day,
          'defaultAmount': _numParse(amountCtl.text.trim()),
          'recurrenceMonths': 1,
          'remindBeforeDays': remindBeforeDays,
          'waterPercentRequests': _waterPercentRequestsFromCfg(cfg),
        };
      }
      return {
        ...cfg,
        'serviceType': type,
        'sharedUnitsMode': 'shared_percent',
        'sharedPercentUnitShares': shares,
        'payer': 'owner',
        'electricityBillingMode': '',
        'electricitySharedMethod': '',
        'electricitySharePercent': null,
        'electricityMeterNo': '',
        'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
        'dueDay': dueDate.day,
        'defaultAmount': _numParse(amountCtl.text.trim()),
        'recurrenceMonths': 1,
        'remindBeforeDays': remindBeforeDays,
        'electricityPercentRequests': _electricityPercentRequestsFromCfg(cfg),
      };
    }

    Future<void> save(BuildContext ctx) async {
      if (managementMode != 'units' && managementMode != 'shared_percent') {
        _showErr('يرجى اختيار طريقة الإدارة أولًا.');
        return;
      }
      if (managementMode == 'shared_percent') {
        if (_units.isEmpty) {
          _showErr('لا توجد وحدات مرتبطة بهذه العمارة.');
          return;
        }
        final shares = collectShares();
        final hasPositive = shares.any((item) {
          return _numParse((item['percent'] ?? '').toString()) > 0;
        });
        if (!hasPositive) {
          _showErr('يرجى إدخال نسبة صحيحة لوحدة واحدة على الأقل.');
          return;
        }
      }
      if (managementMode == 'shared_percent') {
        final shares = collectShares();
        if (hasNegativeShares(shares)) {
          _showErr('لا يمكن إدخال نسبة سالبة لأي وحدة.');
          return;
        }
        if (!_sharedUnitsPercentTotalIsValid(shares)) {
          _showErr('يجب أن يكون مجموع نسب الوحدات 100%.');
          return;
        }
      }
      final currentMode = _sharedUnitsModeFromCfg(cfg);
      if (managementMode != currentMode &&
          reviewedManagementMode != managementMode) {
        final canChangeMode = await _confirmSharedServiceManagementModeChange(
          context: ctx,
          type: type,
          fromMode: currentMode,
          toMode: managementMode,
        );
        if (!canChangeMode) return;
        reviewedManagementMode = managementMode;
      }
      final next = managementMode == 'shared_percent'
          ? buildSharedPercentCfg()
          : buildUnitsManagedCfg();
      if (_deepValueEquals(cfg, next)) {
        _showInfo('لا توجد تغييرات للحفظ');
        return;
      }
      await _saveCfg(type, next);
      cfg = next;
      reviewedManagementMode = managementMode;
      _showOk('تم حفظ الإعدادات');
      if (mounted) setState(() {});
    }

    await _openServicePage(
      'الخدمات المشتركة - ${_title(type)}',
      StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(
                  '${type}_shared_management_$managementModeFieldVersion',
                ),
                initialValue: managementMode.isEmpty ? null : managementMode,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('طريقة الإدارة'),
                items: [
                  DropdownMenuItem(
                    value: 'units',
                    child: Text(_sharedUnitsManagedModeLabel(type)),
                  ),
                  const DropdownMenuItem(
                    value: 'shared_percent',
                    child: Text('توزيع نسبي مشترك'),
                  ),
                ],
                onChanged: (v) async {
                  final nextMode =
                      await _resolveSharedServiceManagementModeSelection(
                    context: ctx,
                    type: type,
                    persistedMode: _sharedUnitsModeFromCfg(cfg),
                    currentDraftMode: managementMode,
                    attemptedMode: v,
                  );
                  if (!ctx.mounted) return;
                  setS(() {
                    managementMode = nextMode;
                    reviewedManagementMode = nextMode;
                    managementModeFieldVersion++;
                  });
                },
              ),
              SizedBox(height: 8.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                ),
                child: Text(
                  managementMode == 'shared_percent'
                      ? 'تُحفظ نسب الوحدات هنا، ويُعتمد عليها عند تنفيذ فاتورة الخدمة المشتركة من العمارة.'
                      : 'عند اختيار هذا الوضع تبقى إدارة ${_title(type)} من داخل كل وحدة على حدة، ولا يتم توزيع الخدمة من العمارة.',
                  style: GoogleFonts.cairo(color: Colors.black87),
                ),
              ),
              if (managementMode == 'shared_percent') ...[
                SizedBox(height: 10.h),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'تاريخ الفاتورة القادم',
                    style: GoogleFonts.cairo(color: Colors.black87),
                  ),
                  subtitle: Text(
                    _fmt(dueDate),
                    style: GoogleFonts.cairo(
                      color: Colors.black54,
                      fontSize: 12.sp,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.black54,
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: KsaTime.dateOnly(dueDate),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setS(() => dueDate = KsaTime.dateOnly(picked));
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  initialValue: 1,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('الدورية'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('شهري')),
                  ],
                  onChanged: null,
                ),
                SizedBox(height: 8.h),
                DropdownButtonFormField<int>(
                  initialValue: remindBeforeDays,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('موعد التنبيه قبل'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                    DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                    DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                    DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                  ],
                  onChanged: (v) =>
                      setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
                ),
                SizedBox(height: 8.h),
                Text(
                  'أدخل مبلغ الفاتورة الحالية هنا، ثم نفّذ التوزيع على الوحدات حسب النسب. يجب أن يكون مجموع النسب 100%.',
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF475569),
                    fontSize: 12.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'مبلغ الفاتورة الحالية',
                  style: GoogleFonts.cairo(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6.h),
                TextField(
                  controller: amountCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.cairo(color: Colors.black87),
                  decoration: _plainFieldDecoration(hintText: '0.00'),
                  onChanged: (_) => setS(() {}),
                ),
                SizedBox(height: 10.h),
                Text(
                  'نسب الوحدات',
                  style: GoogleFonts.cairo(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6.h),
                ..._units.map((unit) {
                  final ctl = shareCtrls.putIfAbsent(
                    unit.id,
                    () => TextEditingController(text: '0'),
                  );
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unit.name,
                                style: GoogleFonts.cairo(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_numParse(amountCtl.text.trim()) > 0)
                                Builder(
                                  builder: (_) {
                                    final preview =
                                        previewRows().firstWhereOrNull((item) {
                                      return (item['unitId'] ?? '')
                                              .toString()
                                              .trim() ==
                                          unit.id;
                                    });
                                    final amount = ((preview?['amount'] as num?)
                                                ?.toDouble() ??
                                            0.0)
                                        .toDouble();
                                    if (amount <= 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: EdgeInsets.only(top: 2.h),
                                      child: Text(
                                        'حصة التنفيذ الحالية: ${amount.toStringAsFixed(2)} ريال',
                                        style: GoogleFonts.cairo(
                                          color: const Color(0xFF475569),
                                          fontSize: 12.sp,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10.w),
                        SizedBox(
                          width: 120.w,
                          child: TextField(
                            controller: ctl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: GoogleFonts.cairo(color: Colors.black87),
                            decoration: _dd('النسبة').copyWith(suffixText: '%'),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: 4.h),
                Text(
                  'إجمالي الأوزان الحالية: ${sharesTotal().toStringAsFixed(2)}%',
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF475569),
                    fontSize: 12.sp,
                  ),
                ),
              ],
              if (managementMode == 'shared_percent') ...[
                SizedBox(height: 4.h),
                Text(
                  'إجمالي النسب المعتمد للتوزيع: ${sharesTotal().toStringAsFixed(2)}%',
                  style: GoogleFonts.cairo(
                    color: (sharesTotal() - 100).abs() <= 0.01
                        ? const Color(0xFF166534)
                        : const Color(0xFFB91C1C),
                    fontSize: 12.sp,
                  ),
                ),
                if ((sharesTotal() - 100).abs() > 0.01)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      'يجب أن يكون مجموع النسب 100% قبل الحفظ أو التنفيذ.',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFFB91C1C),
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                SizedBox(height: 10.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: _actionButtonStyle(const Color(0xFFDCFCE7)),
                    onPressed: () async {
                      final shares = collectShares();
                      if (hasNegativeShares(shares)) {
                        _showErr('لا يمكن إدخال نسبة سالبة لأي وحدة.');
                        return;
                      }
                      if (!_sharedUnitsPercentTotalIsValid(shares)) {
                        _showErr('يجب أن يكون مجموع نسب الوحدات 100%.');
                        return;
                      }
                      final amount = _numParse(amountCtl.text.trim());
                      if (amount <= 0) {
                        _showErr('مبلغ الفاتورة غير صالح');
                        return;
                      }
                      final unitAmounts = previewRows();
                      if (unitAmounts.isEmpty) {
                        _showErr('تعذر توزيع المبلغ على الوحدات');
                        return;
                      }
                      final nowDue = KsaTime.dateOnly(dueDate);
                      final canExecuteNow =
                          await _ensureSharedServiceExecutionDateReached(
                        type: type,
                        cycleDate: nowDue,
                      );
                      if (!canExecuteNow) return;
                      final nextDue = _addMonthsSafe(nowDue, 1);
                      final request = <String, dynamic>{
                        'id': KsaTime.now().microsecondsSinceEpoch.toString(),
                        'date': nowDue.toIso8601String(),
                        'amount': amount,
                        'status': 'paid',
                        'unitAmounts': unitAmounts,
                      };
                      final baseCfg = buildSharedPercentCfg();
                      cfg = {
                        ...baseCfg,
                        'defaultAmount': 0.0,
                        if (type == 'water')
                          'waterPercentRequests': [
                            ..._waterPercentRequestsFromCfg(cfg),
                            request,
                          ]
                        else
                          'electricityPercentRequests': [
                            ..._electricityPercentRequestsFromCfg(cfg),
                            request,
                          ],
                        'nextDueDate': nextDue.toIso8601String(),
                        'dueDay': nextDue.day,
                      };
                      dueDate = nextDue;
                      amountCtl.clear();
                      await _saveCfg(type, cfg);
                      _showOk('تم تنفيذ الفاتورة وتوزيع المبلغ على الوحدات');
                      if (mounted) setS(() {});
                    },
                    icon: const Icon(Icons.playlist_add_check_circle_rounded),
                    label: Text(
                      'تنفيذ الفاتورة الحالية',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  'سجل التنفيذ',
                  style: GoogleFonts.cairo(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6.h),
                requestsLog(ctx, setS),
              ],
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                      onPressed: () => save(ctx),
                      child: Text(
                        'حفظ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        'إلغاء',
                        style: GoogleFonts.cairo(color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _openWaterSettings({bool replaceCurrent = false}) async {
    const type = 'water';
    var cfg = _cfg(type);
    final allowLocalPercent = !_unitUnderPerUnitBuilding;
    final inheritedBuildingMode =
        _unitUnderPerUnitBuilding ? _effectiveSharedUnitsMode(type) : '';
    final forceSeparateFromBuilding =
        _unitUnderPerUnitBuilding && inheritedBuildingMode == 'units_separate';
    final forceFixedFromBuilding =
        _unitUnderPerUnitBuilding && inheritedBuildingMode == 'units_fixed';
    // Backward-compatible repair for previously generated zero-amount rows.
    if (_waterNeedsRecalc(cfg)) {
      final total = ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0.0);
      final repaired =
          _rebuildWaterFixedConfig(currentCfg: cfg, totalWaterAmount: total);
      await _saveCfg(type, repaired);
      cfg = repaired;
    }
    var billingMode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? 'separate')
        .toString()
        .trim()
        .toLowerCase();
    if (billingMode != 'shared') billingMode = 'separate';
    var sharedMethod =
        (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? 'fixed')
            .toString()
            .trim()
            .toLowerCase();
    if (sharedMethod != 'percent') sharedMethod = 'fixed';
    if (!allowLocalPercent && sharedMethod == 'percent') {
      sharedMethod = 'fixed';
    }
    if (forceSeparateFromBuilding) {
      billingMode = 'separate';
      sharedMethod = 'fixed';
    } else if (forceFixedFromBuilding) {
      billingMode = 'shared';
      sharedMethod = 'fixed';
    }
    var dueDate = (cfg['nextDueDate'] is String)
        ? (DateTime.tryParse(cfg['nextDueDate']) ?? KsaTime.today())
        : KsaTime.today();
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final percentCtl = TextEditingController(
        text: ((cfg['sharePercent'] as num?)?.toDouble() ?? 0).toString());
    final fixedCtl = TextEditingController(
        text: ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0).toString());
    final meterCtl =
        TextEditingController(text: (cfg['waterMeterNo'] ?? '').toString());
    var waterLocked = _waterSettingsLocked(cfg);
    var waterLogTab = 'current';

    Future<void> save(BuildContext ctx) async {
      // منع الحفظ إذا مرتبط بعقد نشط
      if (waterLocked) {
        _showErr(
            'الإعدادات مرتبطة بعقد نشط حاليًا، يجب إلغاء العقد أولًا للتعديل.');
        return;
      }
      if (billingMode == 'shared' && sharedMethod == 'fixed') {
        final total = _numParse(fixedCtl.text.trim());
        if (fixedCtl.text.trim().isEmpty || total <= 0) {
          _showErr('يرجى إدخال مبلغ صحيح أكبر من صفر');
          return;
        }
      }
      // نافذة تأكيد عند حفظ مبلغ مقطوع بدون عقد
      if (billingMode == 'shared' &&
          sharedMethod == 'fixed' &&
          _activeContractForProperty() == null) {
        final confirmed = await CustomConfirmDialog.show(
          context: ctx,
          title: 'تأكيد حفظ إعدادات المياه',
          message:
              'سيتم حفظ إجمالي تكلفة المياه.\n\nعند إضافة عقد لهذا العقار، سيُوزَّع المبلغ تلقائيًا على أقساط حسب دفعات العقد.',
          confirmLabel: 'تأكيد',
          cancelLabel: 'إلغاء',
          confirmColor: const Color(0xFF0F766E),
        );
        if (!confirmed) return;
      }
      final preservePercentRequests =
          (cfg['waterBillingMode'] ?? cfg['mode'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase() ==
                      'shared' &&
                  (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase() ==
                      'percent'
              ? _waterPercentRequestsFromCfg(cfg)
              : <Map<String, dynamic>>[];
      var next = <String, dynamic>{
        ...cfg,
        'serviceType': type,
        'waterBillingMode': billingMode,
        'recurrenceMonths': (billingMode == 'shared' && sharedMethod == 'fixed')
            ? _monthsPerCycle(_activeContractForProperty()?.paymentCycle ??
                PaymentCycle.monthly)
            : 1,
        'dueDay': dueDate.day,
        'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
        'remindBeforeDays': remindBeforeDays,
        'waterMeterNo': billingMode == 'separate' ? meterCtl.text.trim() : '',
      };
      if (billingMode == 'separate') {
        final meter = meterCtl.text.trim();
        final onlyDigits = RegExp(r'^\d{4,20}$');
        if (meter.isNotEmpty && !onlyDigits.hasMatch(meter)) {
          _showErr('رقم العداد يجب أن يكون بين 4 و20 رقمًا');
          return;
        }
        next.addAll({
          'payer': 'tenant',
          'waterSharedMethod': '',
          'sharePercent': null,
          'waterPercentRequests': <Map<String, dynamic>>[],
          'totalWaterAmount': null,
          'waterPerInstallment': null,
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
          'waterInstallments': <Map<String, dynamic>>[],
          'remainingInstallmentsCount': 0,
          'nextDueDate': '',
        });
      } else {
        next['payer'] = 'owner';
        next['waterSharedMethod'] = sharedMethod;
        if (sharedMethod == 'percent') {
          final percent = _numParse(percentCtl.text.trim());
          if (percent <= 0) {
            _showErr('النسبة يجب أن تكون أكبر من صفر');
            return;
          }
          next['sharePercent'] = _numParse(percentCtl.text.trim());
          next['waterPercentRequests'] = preservePercentRequests;
          next['totalWaterAmount'] = null;
          next['waterPerInstallment'] = null;
          next['waterLinkedContractId'] = '';
          next['waterLinkedTenantId'] = '';
          next['waterInstallments'] = <Map<String, dynamic>>[];
          next['remainingInstallmentsCount'] = 0;
          next['waterMeterNo'] = '';
        } else {
          final total = _numParse(fixedCtl.text.trim());
          next['sharePercent'] = null;
          next['waterPercentRequests'] = <Map<String, dynamic>>[];
          next['waterMeterNo'] = '';
          final contract = _activeContractForProperty();
          if (contract != null) {
            // عقد موجود: وزّع على الدفعات
            next = _rebuildWaterFixedConfig(
                currentCfg: next, totalWaterAmount: total);
            final rem =
                (next['remainingInstallmentsCount'] as num?)?.toInt() ?? 0;
            if (total > 0 && rem > 0) {
              final rows = _waterInstallmentsFromCfg(next)
                  .where((r) => (r['status'] ?? '').toString() != 'paid');
              final hasZero = rows
                  .any((r) => ((r['amount'] as num?)?.toDouble() ?? 0) <= 0);
              if (hasZero) {
                _showErr('خطأ في توزيع الأقساط. يرجى المراجعة.');
                return;
              }
            }
          } else {
            // لا يوجد عقد: احفظ المبلغ فقط بدون توزيع
            next['totalWaterAmount'] = total;
            next['waterPerInstallment'] = 0.0;
            next['waterLinkedContractId'] = '';
            next['waterLinkedTenantId'] = '';
            next['waterInstallments'] = <Map<String, dynamic>>[];
            next['remainingInstallmentsCount'] = 0;
            next['nextDueDate'] = '';
          }
        }
      }
      await _saveCfg(type, next);
      cfg = next;
      waterLocked = _waterSettingsLocked(next);
      _showOk('تم حفظ الإعدادات');
      if (mounted) setState(() {});
    }

    await _openServicePage(
      'إعدادات المياه',
      StatefulBuilder(
        builder: (ctx, setS) {
          final rows =
              _waterInstallmentsFromCfg(_rebuildWaterFixedConfig(currentCfg: {
            ...cfg,
            'waterBillingMode': billingMode,
            'waterSharedMethod': sharedMethod,
            'totalWaterAmount': _numParse(fixedCtl.text.trim()),
          }, totalWaterAmount: _numParse(fixedCtl.text.trim())));
          final nextDueFromRows = rows
              .where((r) => (r['status'] ?? '').toString() != 'paid')
              .map((r) => DateTime.tryParse((r['dueDate'] ?? '').toString()))
              .whereType<DateTime>()
              .toList();
          final dueDisplay = (nextDueFromRows.isNotEmpty
                  ? nextDueFromRows.first
                  : DateTime.tryParse((cfg['nextDueDate'] ?? '').toString())) ??
              dueDate;
          final dueDisplayTitle =
              waterLocked ? _waterDueTitle(dueDisplay) : 'تاريخ السداد القادم';
          final contractCycleMonths = _monthsPerCycle(
              _activeContractForProperty()?.paymentCycle ??
                  PaymentCycle.monthly);
          final periodicMonths =
              (billingMode == 'shared' && sharedMethod == 'fixed')
                  ? contractCycleMonths
                  : 1;
          final periodicLabel = periodicMonths == 1
              ? 'شهري'
              : periodicMonths == 3
                  ? 'كل 3 شهور'
                  : periodicMonths == 6
                      ? 'كل 6 شهور'
                      : 'شهري';

          final hasWaterArchive = _hasWaterHistoricalArchive(cfg);

          Widget requestsLog() {
            if (billingMode != 'shared') {
              return Text('لا توجد عناصر في السجل',
                  style: GoogleFonts.cairo(color: Colors.black54));
            }
            if (sharedMethod == 'percent') {
              final rows = _waterPercentRequestsFromCfg(cfg);
              if (rows.isEmpty) {
                return Text('لا توجد عناصر في السجل',
                    style: GoogleFonts.cairo(color: Colors.black54));
              }
              return _scrollList(rows.map((r) {
                final id = (r['id'] ?? '').toString();
                final due = DateTime.tryParse((r['date'] ?? '').toString()) ??
                    KsaTime.today();
                final amount = ((r['amount'] as num?)?.toDouble() ??
                        _numParse((r['amount'] ?? '').toString()))
                    .toDouble();
                final percent = ((r['percent'] as num?)?.toDouble() ??
                        _numParse((r['percent'] ?? '').toString()))
                    .toDouble();
                return Dismissible(
                  key: ValueKey('wpr_$id'),
                  direction: Directionality.of(ctx) == TextDirection.rtl
                      ? DismissDirection.endToStart
                      : DismissDirection.startToEnd,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child:
                        const Icon(Icons.delete_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    final nextRows =
                        _waterPercentRequestsFromCfg(cfg).where((e) {
                      return (e['id'] ?? '').toString() != id;
                    }).toList();
                    cfg = {
                      ...cfg,
                      'waterPercentRequests': nextRows,
                    };
                    await _saveCfg(type, cfg);
                    if (mounted) setS(() {});
                  },
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('فاتورة مياه',
                        style: GoogleFonts.cairo(color: Colors.black87)),
                    subtitle: Text(
                        amount > 0
                            ? 'موعد التنفيذ: ${_fmt(due)}\nالمبلغ: ${amount.toStringAsFixed(2)} ريال'
                            : 'موعد التنفيذ: ${_fmt(due)}\nالنسبة: ${percent.toStringAsFixed(2)}%',
                        style: GoogleFonts.cairo(
                            color: Colors.black54, fontSize: 12.sp)),
                    trailing: TextButton(
                      onPressed: null,
                      child: Text('مدفوع',
                          style: GoogleFonts.cairo(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                );
              }).toList());
            }
            if (sharedMethod != 'fixed') {
              return Text('لا توجد عناصر في السجل',
                  style: GoogleFonts.cairo(color: Colors.black54));
            }
            final linkedCid =
                (cfg['waterLinkedContractId'] ?? '').toString().trim();
            if (linkedCid.isEmpty || rows.isEmpty) {
              return Text('لا توجد عناصر في السجل الحالي',
                  style: GoogleFonts.cairo(color: Colors.black54));
            }
            return _scrollList(rows.map((r) {
              final due = DateTime.tryParse((r['dueDate'] ?? '').toString()) ??
                  KsaTime.today();
              final amount = ((r['amount'] as num?)?.toDouble() ?? 0.0);
              final invoiceId = (r['invoiceId'] ?? '').toString();
              final paid = (r['status'] ?? '').toString() == 'paid' ||
                  invoiceId.isNotEmpty;
              // تحقق هل الفاتورة ملغاة
              final inv = invoiceId.isNotEmpty
                  ? _invoices.values.firstWhereOrNull((e) => e.id == invoiceId)
                  : null;
              final isCanceled = inv != null && inv.isCanceled;
              final officeExpenseInvoice =
                  _waterInstallmentOfficeExpenseInvoice(r);
              final activeOfficeExpenseInvoice = officeExpenseInvoice != null &&
                      !officeExpenseInvoice.isCanceled
                  ? officeExpenseInvoice
                  : null;
              final canRegisterOfficeExpense =
                  paid && !isCanceled && inv != null;
              final dueOnly = KsaTime.dateOnly(due);
              final todayOnly = KsaTime.dateOnly(KsaTime.today());
              final isDueToday = !paid && !isCanceled && dueOnly == todayOnly;

              Widget rowActionButton({
                required String label,
                required VoidCallback onPressed,
                required Color backgroundColor,
                required Color textColor,
              }) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: _actionButtonStyle(backgroundColor),
                    onPressed: onPressed,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                );
              }

              Future<void> openInstallmentInvoice() async {
                if (inv != null) {
                  await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailsScreen(invoice: inv),
                    ),
                  );
                  if (!mounted) return;
                  setS(() {});
                  setState(() {});
                  return;
                }
                final contract = _contracts.values
                    .firstWhereOrNull((c) => c.id == linkedCid);
                if (contract != null) {
                  await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ContractDetailsScreen(contract: contract),
                    ),
                  );
                  if (!mounted) return;
                  setS(() {});
                  setState(() {});
                }
              }

              Future<void> handleOfficeExpense() async {
                if (activeOfficeExpenseInvoice != null) {
                  await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailsScreen(
                        invoice: activeOfficeExpenseInvoice,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  setS(() {});
                  setState(() {});
                  return;
                }
                if (!canRegisterOfficeExpense) {
                  _showErr(
                    'يجب أولًا أن يصبح قسط المستأجر مدفوعًا. عند سداد قيمة قسط الإيجار والمياه يمكنك بعدها تسجيل قيمة فاتورة المياه من الشركة.',
                  );
                  return;
                }
                final companyAmount =
                    await _showWaterCompanyExpenseAmountDialog(ctx, due);
                if (companyAmount == null || companyAmount <= 0) return;
                final invoiceNote = _buildWaterCompanyExpenseNote(
                  cycleDate: due,
                  amount: companyAmount,
                );
                final officeExpenseInvoiceId = await _addOwnerExpense(
                  targetPropertyId: widget.propertyId,
                  amount: companyAmount,
                  note: invoiceNote,
                  date: KsaTime.dateOnly(KsaTime.now()),
                  dueDate: KsaTime.dateOnly(due),
                );
                await _linkWaterInstallmentOfficeExpenseInvoice(
                  dueDate: due,
                  invoiceId: officeExpenseInvoiceId,
                );
                cfg = _cfg(type);
                _showOk('تم إصدار سند الصرف بنجاح');
                if (!mounted) return;
                setS(() {});
                setState(() {});
              }

              return Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: isDueToday
                        ? const Color(0xFFEEF6FF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: isDueToday
                          ? const Color(0xFFBFDBFE)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'قسط مياه',
                              style: GoogleFonts.cairo(color: Colors.black87),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'تاريخ السداد: ${_fmt(due)}\nالمبلغ: ${amount.toStringAsFixed(2)} ريال${isDueToday ? '\nسداد اليوم' : ''}',
                              style: GoogleFonts.cairo(
                                color: isDueToday
                                    ? const Color(0xFF0D9488)
                                    : Colors.black54,
                                fontSize: 12.sp,
                                fontWeight: isDueToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      SizedBox(
                        width: 116.w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            rowActionButton(
                              label: isCanceled
                                  ? 'عرض الملغي'
                                  : (paid ? 'عرض' : 'قادم'),
                              onPressed: openInstallmentInvoice,
                              backgroundColor: paid || isCanceled
                                  ? const Color(0xFFE0F2FE)
                                  : const Color(0xFFF1F5F9),
                              textColor: paid || isCanceled
                                  ? const Color(0xFF0369A1)
                                  : const Color(0xFF64748B),
                            ),
                            SizedBox(height: 6.h),
                            rowActionButton(
                              label: 'سند الصرف',
                              onPressed: handleOfficeExpense,
                              backgroundColor:
                                  activeOfficeExpenseInvoice != null
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFE2E8F0),
                              textColor: activeOfficeExpenseInvoice != null
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFF0F172A),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList());
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: billingMode,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('نظام الفوترة'),
                  items: forceSeparateFromBuilding
                      ? const [
                          DropdownMenuItem(
                            value: 'separate',
                            child: Text('منفصل'),
                          ),
                        ]
                      : forceFixedFromBuilding
                          ? const [
                              DropdownMenuItem(
                                value: 'shared',
                                child: Text('مبلغ مقطوع'),
                              ),
                            ]
                          : const [
                              DropdownMenuItem(
                                value: 'separate',
                                child: Text('منفصل'),
                              ),
                              DropdownMenuItem(
                                value: 'shared',
                                child: Text('مشترك'),
                              ),
                            ],
                  onTap: () {
                    if (waterLocked) {
                      _showErr(
                          'الإعدادات مرتبطة بعقد نشط حاليًا، يجب إلغاء العقد أولًا للتعديل.');
                    }
                  },
                  onChanged: waterLocked ||
                          forceSeparateFromBuilding ||
                          forceFixedFromBuilding
                      ? null
                      : (v) => setS(() => billingMode = (v ?? 'separate')),
                ),
                SizedBox(height: 8.h),
                if (forceSeparateFromBuilding)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      'هذه الوحدة تتبع إعداد العمارة: الإدارة من الوحدات (منفصل). يمكنك هنا حفظ رقم عداد المياه فقط.',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  ),
                if (forceSeparateFromBuilding) SizedBox(height: 8.h),
                if (forceFixedFromBuilding)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      'هذه الوحدة تتبع إعداد العمارة: الإدارة من الوحدات (مبلغ مقطوع). يجب حفظ مبلغ المياه المقطوع لهذه الوحدة قبل إنشاء العقد.',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  ),
                if (forceFixedFromBuilding) SizedBox(height: 8.h),
                if (billingMode == 'separate')
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      'هذا الخيار يعني أن سداد المياه على المستأجر بشكل كامل، ولا يتم إنشاء أقساط مياه ضمن العقد.',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  ),
                if (billingMode == 'separate') ...[
                  SizedBox(height: 8.h),
                  TextField(
                    controller: meterCtl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    decoration: _dd('رقم عداد المياه'),
                  ),
                ],
                if (billingMode == 'shared') ...[
                  DropdownButtonFormField<String>(
                    initialValue: sharedMethod,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('طريقة السداد'),
                    items: forceFixedFromBuilding
                        ? const [
                            DropdownMenuItem(
                              value: 'fixed',
                              child: Text('مبلغ مقطوع'),
                            ),
                          ]
                        : allowLocalPercent
                        ? const [
                            DropdownMenuItem(
                                value: 'fixed', child: Text('مبلغ مقطوع')),
                            DropdownMenuItem(
                                value: 'percent', child: Text('بالنسبة')),
                          ]
                        : const [
                            DropdownMenuItem(
                                value: 'fixed', child: Text('مبلغ مقطوع')),
                          ],
                    onTap: () {
                      if (waterLocked) {
                        _showErr(
                            'الإعدادات مرتبطة بعقد نشط حاليًا، يجب إلغاء العقد أولًا للتعديل.');
                      }
                    },
                    onChanged: waterLocked || forceFixedFromBuilding
                        ? null
                        : (v) => setS(() => sharedMethod = (v ?? 'fixed')),
                  ),
                  SizedBox(height: 8.h),
                  if (!allowLocalPercent)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12.r),
                        border:
                            Border.all(color: Colors.black.withOpacity(0.08)),
                      ),
                      child: Text(
                        forceFixedFromBuilding
                            ? 'في وحدات العمارة ومع وضع المبلغ المقطوع من العمارة، يجب حفظ مبلغ هذه الوحدة هنا قبل إنشاء العقد.'
                            : 'في وحدات العمارة يتاح هنا المبلغ المقطوع فقط، أما التوزيع بالنسبة فيُضبط من شاشة الخدمات المشتركة في العمارة.',
                        style: GoogleFonts.cairo(color: Colors.black87),
                      ),
                    ),
                  if (!allowLocalPercent) SizedBox(height: 8.h),
                  if (sharedMethod == 'percent') ...[
                    TextField(
                      controller: percentCtl,
                      style: GoogleFonts.cairo(color: Colors.black87),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dd('النسبة').copyWith(suffixText: '%'),
                    ),
                    SizedBox(height: 8.h),
                  ] else ...[
                    TextField(
                      controller: fixedCtl,
                      style: GoogleFonts.cairo(color: Colors.black87),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      readOnly: waterLocked,
                      onTap: waterLocked
                          ? () => _showErr(
                              'الإعدادات مرتبطة بعقد نشط حاليًا، يجب إلغاء العقد أولًا للتعديل.')
                          : null,
                      decoration: _dd('المبلغ/التكلفة'),
                    ),
                    SizedBox(height: 8.h),
                  ],
                  // حقول مشتركة بين الطريقتين
                  if (sharedMethod == 'percent') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('تاريخ السداد القادم',
                          style: GoogleFonts.cairo(color: Colors.black87)),
                      subtitle: Text(_fmt(dueDate),
                          style: GoogleFonts.cairo(
                              color: Colors.black54, fontSize: 12.sp)),
                      trailing: const Icon(Icons.calendar_month_rounded,
                          color: Colors.black54),
                      onTap: () async {
                        final p = await showDatePicker(
                            context: ctx,
                            initialDate: KsaTime.dateOnly(dueDate),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (p != null) {
                          setS(() => dueDate = KsaTime.dateOnly(p));
                        }
                      },
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: 1,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(color: Colors.black87),
                      iconEnabledColor: Colors.black54,
                      decoration: _dd('الدوري'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('شهري')),
                      ],
                      onChanged: null,
                    ),
                    SizedBox(height: 8.h),
                    DropdownButtonFormField<int>(
                      initialValue: remindBeforeDays,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(color: Colors.black87),
                      iconEnabledColor: Colors.black54,
                      decoration: _dd('موعد التنبيه قبل'),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                        DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                        DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                        DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                      ],
                      onChanged: (v) =>
                          setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
                    ),
                    SizedBox(height: 8.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: _actionButtonStyle(const Color(0xFFDCFCE7)),
                        onPressed: () async {
                          if (_activeContractForProperty() == null) {
                            _showErr(
                                'لا يمكن تنفيذ الطلب قبل إضافة عقد لهذا العقار.');
                            return;
                          }
                          final p = _numParse(percentCtl.text.trim());
                          if (p <= 0) {
                            _showErr('النسبة يجب أن تكون أكبر من صفر');
                            return;
                          }
                          final nowDue = KsaTime.dateOnly(dueDate);
                          final nextDue = _addMonthsSafe(nowDue, 1);
                          final reqs = _waterPercentRequestsFromCfg(cfg);
                          reqs.add({
                            'id':
                                KsaTime.now().microsecondsSinceEpoch.toString(),
                            'date': nowDue.toIso8601String(),
                            'percent': p,
                            'status': 'paid',
                          });
                          cfg = {
                            ...cfg,
                            'serviceType': type,
                            'waterBillingMode': billingMode,
                            'waterSharedMethod': 'percent',
                            'sharePercent': p,
                            'recurrenceMonths': 1,
                            'dueDay': nextDue.day,
                            'nextDueDate': nextDue.toIso8601String(),
                            'remindBeforeDays': remindBeforeDays,
                            'payer': 'owner',
                            'waterMeterNo': '',
                            'totalWaterAmount': null,
                            'waterPerInstallment': null,
                            'waterLinkedContractId': '',
                            'waterLinkedTenantId': '',
                            'waterInstallments': <Map<String, dynamic>>[],
                            'remainingInstallmentsCount': 0,
                            'waterPercentRequests': reqs,
                          };
                          dueDate = nextDue;
                          await _saveCfg(type, cfg);
                          _showOk('تم تنفيذ العملية بنجاح');
                          if (mounted) setS(() {});
                        },
                        icon:
                            const Icon(Icons.playlist_add_check_circle_rounded),
                        label: Text('تنفيذ الآن',
                            style:
                                GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ] else ...[
                    // مبلغ مقطوع: الحقول تعتمد على العقد
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dueDisplayTitle,
                          style: GoogleFonts.cairo(color: Colors.black87)),
                      subtitle: Text(
                          waterLocked
                              ? _fmt(dueDisplay)
                              : 'يُحدَّد عند ربط العقد',
                          style: GoogleFonts.cairo(
                              color: waterLocked
                                  ? Colors.black54
                                  : const Color(0xFF94A3B8),
                              fontSize: 12.sp)),
                      trailing: Icon(Icons.lock_clock_rounded,
                          color: waterLocked
                              ? Colors.black54
                              : const Color(0xFF94A3B8)),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: periodicMonths,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(
                          color: waterLocked
                              ? Colors.black87
                              : const Color(0xFF94A3B8)),
                      iconEnabledColor: Colors.black54,
                      decoration: _dd('الدوري'),
                      items: [
                        DropdownMenuItem(
                            value: periodicMonths,
                            child: Text(waterLocked
                                ? periodicLabel
                                : 'يُحدَّد عند ربط العقد')),
                      ],
                      onChanged: null,
                    ),
                  ],
                ],
                if (waterLocked) ...[
                  SizedBox(height: 8.h),
                  Text(
                      'الإعدادات مرتبطة بعقد نشط حاليًا، يجب إلغاء العقد أولًا للتعديل.',
                      style: GoogleFonts.cairo(
                          color: const Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700)),
                ],
                SizedBox(height: 10.h),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                      onPressed: () => save(ctx),
                      child: Text('حفظ',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.black87)),
                    ),
                  ),
                ]),
                if (billingMode == 'shared') ...[
                  SizedBox(height: 10.h),
                  Center(
                    child: Text('سجل الطلبات',
                        style: GoogleFonts.cairo(
                            color: Colors.black87,
                            fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(height: 6.h),
                  if (hasWaterArchive) ...[
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setS(() => waterLogTab = 'current'),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 10.h),
                              decoration: BoxDecoration(
                                color: waterLogTab == 'current'
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: waterLogTab == 'current'
                                      ? const Color(0xFF0F766E)
                                      : Colors.black.withOpacity(0.08),
                                ),
                              ),
                              child: Text(
                                'السجل الحالي',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  color: waterLogTab == 'current'
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setS(() => waterLogTab = 'archive'),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 10.h),
                              decoration: BoxDecoration(
                                color: waterLogTab == 'archive'
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: waterLogTab == 'archive'
                                      ? const Color(0xFF0F766E)
                                      : Colors.black.withOpacity(0.08),
                                ),
                              ),
                              child: Text(
                                'الأرشيف',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  color: waterLogTab == 'archive'
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                  ],
                  waterLogTab == 'archive' && hasWaterArchive
                      ? _waterHistoricalSummary(ctx, cfg)
                      : requestsLog(),
                ],
              ],
            ),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  List<Map<String, dynamic>> _electricityPercentRequestsFromCfg(
      Map<String, dynamic> cfg) {
    final raw = cfg['electricityPercentRequests'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _internetRequestsFromCfg(
      Map<String, dynamic> cfg) {
    final raw = cfg['internetRequests'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String _internetBillingModeFromCfg(Map<String, dynamic> cfg) {
    return _internetBillingModeFromConfig(cfg);
  }

  Future<void> _openElectricitySettings({bool replaceCurrent = false}) async {
    const type = 'electricity';
    var cfg = _cfg(type);
    final allowLocalSharedPercent = !_unitUnderPerUnitBuilding;
    var billingMode = (cfg['electricityBillingMode'] ?? 'separate')
        .toString()
        .trim()
        .toLowerCase();
    if (billingMode != 'shared') billingMode = 'separate';
    if (!allowLocalSharedPercent) billingMode = 'separate';
    var sharedMethod = (cfg['electricitySharedMethod'] ?? 'percent')
        .toString()
        .trim()
        .toLowerCase();
    if (sharedMethod != 'percent') sharedMethod = 'percent';
    var dueDate = (cfg['nextDueDate'] is String)
        ? (DateTime.tryParse(cfg['nextDueDate']) ?? KsaTime.today())
        : KsaTime.today();
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final percentCtl = TextEditingController(
        text: ((cfg['electricitySharePercent'] as num?)?.toDouble() ?? 0)
            .toString());
    final meterCtl = TextEditingController(
        text: (cfg['electricityMeterNo'] ?? '').toString());

    Future<void> save(BuildContext ctx) async {
      final next = <String, dynamic>{
        ...cfg,
        'serviceType': type,
        'electricityBillingMode': billingMode,
        'electricitySharedMethod': billingMode == 'shared' ? 'percent' : '',
        'recurrenceMonths': 1,
        'dueDay': dueDate.day,
        'nextDueDate': KsaTime.dateOnly(dueDate).toIso8601String(),
        'remindBeforeDays': remindBeforeDays,
        'electricityMeterNo':
            billingMode == 'separate' ? meterCtl.text.trim() : '',
      };
      if (billingMode == 'separate') {
        final meter = meterCtl.text.trim();
        final onlyDigits = RegExp(r'^\d{4,20}$');
        if (meter.isNotEmpty && !onlyDigits.hasMatch(meter)) {
          _showErr('رقم العداد يجب أن يكون بين 4 و20 رقمًا');
          return;
        }
        next['electricitySharePercent'] = null;
        next['electricityPercentRequests'] = <Map<String, dynamic>>[];
        next['payer'] = 'tenant';
      } else {
        final percent = _numParse(percentCtl.text.trim());
        if (percent <= 0) {
          _showErr('النسبة يجب أن تكون أكبر من صفر');
          return;
        }
        next['electricitySharePercent'] = percent;
        next['payer'] = 'owner';
      }
      cfg = next;
      await _saveCfg(type, next);
      _showOk('تم حفظ إعدادات الكهرباء');
      if (mounted) setState(() {});
    }

    await _openServicePage(
      'إعدادات الكهرباء',
      StatefulBuilder(
        builder: (ctx, setS) {
          Widget requestsLog() {
            if (billingMode != 'shared') {
              return Text('لا توجد عناصر في السجل',
                  style: GoogleFonts.cairo(color: Colors.black54));
            }
            final rows = _electricityPercentRequestsFromCfg(cfg);
            if (rows.isEmpty) {
              return Text('لا توجد عناصر في السجل',
                  style: GoogleFonts.cairo(color: Colors.black54));
            }
            return _scrollList(rows.map((r) {
              final id = (r['id'] ?? '').toString();
              final due = DateTime.tryParse((r['date'] ?? '').toString()) ??
                  KsaTime.today();
              final amount = ((r['amount'] as num?)?.toDouble() ??
                      _numParse((r['amount'] ?? '').toString()))
                  .toDouble();
              final percent = ((r['percent'] as num?)?.toDouble() ??
                      _numParse((r['percent'] ?? '').toString()))
                  .toDouble();
              return Dismissible(
                key: ValueKey('epr_$id'),
                direction: Directionality.of(ctx) == TextDirection.rtl
                    ? DismissDirection.endToStart
                    : DismissDirection.startToEnd,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                ),
                onDismissed: (_) async {
                  final nextRows =
                      _electricityPercentRequestsFromCfg(cfg).where((e) {
                    return (e['id'] ?? '').toString() != id;
                  }).toList();
                  cfg = {
                    ...cfg,
                    'electricityPercentRequests': nextRows,
                  };
                  await _saveCfg(type, cfg);
                  if (mounted) setS(() {});
                },
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('فاتورة كهرباء',
                      style: GoogleFonts.cairo(color: Colors.black87)),
                  subtitle: Text(
                      amount > 0
                          ? 'موعد التنفيذ: ${_fmt(due)}\nالمبلغ: ${amount.toStringAsFixed(2)} ريال'
                          : 'موعد التنفيذ: ${_fmt(due)}\nالنسبة: ${percent.toStringAsFixed(2)}%',
                      style: GoogleFonts.cairo(
                          color: Colors.black54, fontSize: 12.sp)),
                  trailing: TextButton(
                    onPressed: null,
                    child: Text('مدفوع',
                        style: GoogleFonts.cairo(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              );
            }).toList());
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: billingMode,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('نظام الفوترة'),
                  items: allowLocalSharedPercent
                      ? const [
                          DropdownMenuItem(
                              value: 'separate', child: Text('منفصل')),
                          DropdownMenuItem(
                              value: 'shared', child: Text('مشترك')),
                        ]
                      : const [
                          DropdownMenuItem(
                              value: 'separate', child: Text('منفصل')),
                        ],
                  onChanged: (v) => setS(() => billingMode = (v ?? 'separate')),
                ),
                SizedBox(height: 8.h),
                if (!allowLocalSharedPercent)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      'في وحدات العمارة تُدار الكهرباء محليًا كوضع منفصل فقط، أما التوزيع بالنسبة فيُضبط من شاشة الخدمات المشتركة في العمارة.',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  ),
                if (!allowLocalSharedPercent) SizedBox(height: 8.h),
                if (billingMode == 'separate')
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      'هذا الخيار يعني أن سداد الكهرباء على المستأجر بالكامل، ولا يتم إنشاء توزيع مشترك.',
                      style: GoogleFonts.cairo(color: Colors.black87),
                    ),
                  ),
                if (billingMode == 'separate') ...[
                  SizedBox(height: 8.h),
                  TextField(
                    controller: meterCtl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    decoration: _dd('رقم عداد الكهرباء'),
                  ),
                ],
                if (billingMode == 'shared') ...[
                  DropdownButtonFormField<String>(
                    initialValue: sharedMethod,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('طريقة السداد'),
                    items: const [
                      DropdownMenuItem(
                          value: 'percent', child: Text('بالنسبة')),
                    ],
                    onChanged: (v) =>
                        setS(() => sharedMethod = (v ?? 'percent')),
                  ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: percentCtl,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dd('النسبة').copyWith(suffixText: '%'),
                  ),
                  SizedBox(height: 8.h),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('تاريخ السداد القادم',
                        style: GoogleFonts.cairo(color: Colors.black87)),
                    subtitle: Text(_fmt(dueDate),
                        style: GoogleFonts.cairo(
                            color: Colors.black54, fontSize: 12.sp)),
                    trailing: const Icon(Icons.calendar_month_rounded,
                        color: Colors.black54),
                    onTap: () async {
                      final p = await showDatePicker(
                          context: ctx,
                          initialDate: KsaTime.dateOnly(dueDate),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (p != null) {
                        setS(() => dueDate = KsaTime.dateOnly(p));
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: 1,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('الدوري'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('شهري')),
                    ],
                    onChanged: null,
                  ),
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<int>(
                    initialValue: remindBeforeDays,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('موعد التنبيه قبل'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                      DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                      DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                      DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                    ],
                    onChanged: (v) =>
                        setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
                  ),
                  SizedBox(height: 8.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: _actionButtonStyle(const Color(0xFFDCFCE7)),
                      onPressed: () async {
                        if (_activeContractForProperty() == null) {
                          _showErr(
                              'لا يمكن تنفيذ الطلب قبل إضافة عقد لهذا العقار.');
                          return;
                        }
                        final p = _numParse(percentCtl.text.trim());
                        if (p <= 0) {
                          _showErr('النسبة يجب أن تكون أكبر من صفر');
                          return;
                        }
                        final nowDue = KsaTime.dateOnly(dueDate);
                        final nextDue = _addMonthsSafe(nowDue, 1);
                        final reqs = _electricityPercentRequestsFromCfg(cfg);
                        reqs.add({
                          'id': KsaTime.now().microsecondsSinceEpoch.toString(),
                          'date': nowDue.toIso8601String(),
                          'percent': p,
                          'status': 'paid',
                        });
                        cfg = {
                          ...cfg,
                          'serviceType': type,
                          'electricityBillingMode': billingMode,
                          'electricitySharedMethod': 'percent',
                          'electricitySharePercent': p,
                          'recurrenceMonths': 1,
                          'dueDay': nextDue.day,
                          'nextDueDate': nextDue.toIso8601String(),
                          'remindBeforeDays': remindBeforeDays,
                          'payer': 'owner',
                          'electricityPercentRequests': reqs,
                        };
                        dueDate = nextDue;
                        await _saveCfg(type, cfg);
                        _showOk('تم تنفيذ العملية بنجاح');
                        if (mounted) setS(() {});
                      },
                      icon: const Icon(Icons.playlist_add_check_circle_rounded),
                      label: Text('تنفيذ الآن',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Text('سجل الطلبات',
                      style: GoogleFonts.cairo(
                          color: Colors.black87, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6.h),
                  requestsLog(),
                ],
                SizedBox(height: 10.h),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                      onPressed: () => save(ctx),
                      child: Text('حفظ',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: ElevatedButton(
                      style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.black87)),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _openUtilitySimple(String type) async {
    final cfg = _cfg(type);
    final amountCtl =
        TextEditingController(text: (cfg['defaultAmount'] ?? '').toString());
    DateTime invoiceDate = KsaTime.today();
    await _openServicePage(
      'إعدادات ${_title(type)}',
      StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: amountCtl,
              style: GoogleFonts.cairo(color: Colors.black87),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _dd('المبلغ/التكلفة'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('تاريخ التنفيذ',
                  style: GoogleFonts.cairo(color: Colors.black87)),
              subtitle: Text(_fmt(invoiceDate),
                  style: GoogleFonts.cairo(
                      color: Colors.black54, fontSize: 12.sp)),
              trailing: const Icon(Icons.calendar_month_rounded,
                  color: Colors.black54),
              onTap: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: invoiceDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (p != null) setS(() => invoiceDate = KsaTime.dateOnly(p));
              },
            ),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final saved = {
                      ...cfg,
                      'serviceType': type,
                      'defaultAmount':
                          double.tryParse(amountCtl.text.trim()) ?? 0
                    };
                    await _saveCfg(type, saved);
                    _showOk('تم حفظ الإعدادات');
                    if (mounted) setS(() {});
                  },
                  child: Text('حفظ',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.black87)))),
            ]),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final amount = double.tryParse(amountCtl.text.trim()) ?? 0;
                  if (amount <= 0) return _showErr('المبلغ غير صالح');
                  await _addOwnerExpense(
                    targetPropertyId: widget.propertyId,
                    amount: amount,
                    note: '[SERVICE] type=$type pid=${widget.propertyId}',
                    date: invoiceDate,
                  );
                  _showOk('تمت العملية بنجاح');
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text('سداد الآن',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
            ),
            SizedBox(height: 10.h),
            Text('سجل الطلبات',
                style: GoogleFonts.cairo(
                    color: Colors.black87, fontWeight: FontWeight.w800)),
            SizedBox(height: 6.h),
            _scrollList(_invoices.values
                .where((i) =>
                    !i.isArchived &&
                    (i.note ?? '').contains(
                        '[SERVICE] type=$type pid=${widget.propertyId}'))
                .toList()
                .map((inv) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(inv.serialNo ?? inv.id,
                          style: GoogleFonts.cairo(color: Colors.black87)),
                      subtitle: Text(
                          '${_fmt(inv.issueDate)} - ${inv.amount.toStringAsFixed(2)} ريال',
                          style: GoogleFonts.cairo(
                              color: Colors.black54, fontSize: 12.sp)),
                      trailing: TextButton(
                        onPressed: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    InvoiceDetailsScreen(invoice: inv))),
                        child: Text('عرض',
                            style: GoogleFonts.cairo(
                                color: const Color(0xFF38BDF8),
                                fontWeight: FontWeight.w700)),
                      ),
                    ))
                .toList()),
          ]),
        ),
      ),
    );
  }

  Future<void> _openInternetSettings({bool replaceCurrent = false}) async {
    const type = 'internet';
    var cfg = _cfg(type);
    var billingMode = _internetBillingModeFromCfg(cfg);
    final amountCtl =
        TextEditingController(text: _periodicServiceDefaultAmountText(cfg));
    final providers = _providers();
    Tenant? provider = providers
        .firstWhereOrNull((p) => p.id == (cfg['providerId']?.toString() ?? ''));
    final trackedDueDate = billingMode == 'owner'
        ? _trackedPeriodicServiceDueDate(type, cfg)
        : null;
    final configuredDueDate = _periodicServiceScheduleState(
      type: type,
      cfg: cfg,
    ).storedDueDate;
    final originalStartDate = _periodicServiceStartDateFromConfig(cfg);
    final hasConfiguredOwnerSchedule =
        _internetBillingModeFromCfg(cfg) == 'owner' && _isConfigured(type, cfg);
    final initialHasNextDate =
        trackedDueDate != null || configuredDueDate != null;
    final initialRecurrenceMonths = _normalizePeriodicRecurrenceMonths(
      ((cfg['recurrenceMonths'] as num?)?.toInt() ?? 0),
    );
    var nextDate = trackedDueDate ??
        configuredDueDate ??
        originalStartDate ??
        KsaTime.today();
    final initialDisplayDate = nextDate;
    var hasNextDate = initialHasNextDate;
    var didPickNextDate = false;
    var months = initialRecurrenceMonths;
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);

    await _openServicePage(
      'إعدادات ${_title(type)}',
      StatefulBuilder(
        builder: (ctx, setS) {
          final schedulePreview = _periodicServiceDraftScheduleState(
            type: type,
            previousCfg: cfg,
            startDate: nextDate,
            recurrenceMonths: months,
            hasNextDate: hasNextDate,
          );
          final previewDate = schedulePreview.storedDueDate;
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: billingMode,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('نظام الفوترة'),
                items: const [
                  DropdownMenuItem(value: 'separate', child: Text('منفصل')),
                  DropdownMenuItem(value: 'owner', child: Text('على المالك')),
                ],
                onChanged: (v) => setS(() => billingMode = (v ?? 'owner')),
              ),
              SizedBox(height: 8.h),
              if (billingMode == 'separate')
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Text(
                    'هذا الخيار يعني أن سداد الإنترنت على المستأجر بالكامل، ولا يتم إنشاء طلبات دورية للإنترنت على العقار.',
                    style: GoogleFonts.cairo(color: Colors.black87),
                  ),
                ),
              if (billingMode == 'owner') ...[
                InputDecorator(
                    decoration: _dd('الجهة المسؤولة'),
                    child: Text('المالك',
                        style: GoogleFonts.cairo(color: Colors.black87))),
                SizedBox(height: 8.h),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('موعد التنفيذ القادم',
                      style: GoogleFonts.cairo(color: Colors.black87)),
                  subtitle: Text(
                      previewDate != null
                          ? _fmt(previewDate)
                          : _periodicServiceNoUpcomingDateLabel(),
                      style: GoogleFonts.cairo(
                          color: Colors.black54, fontSize: 12.sp)),
                  trailing: const Icon(Icons.event_available_rounded,
                      color: Colors.black54),
                  onTap: () async {
                    final p = await showDatePicker(
                        context: ctx,
                        initialDate: nextDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (p != null) {
                      setS(() {
                        nextDate = KsaTime.dateOnly(p);
                        hasNextDate = true;
                        didPickNextDate = !_samePeriodicDate(
                          nextDate,
                          initialDisplayDate,
                        );
                      });
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  initialValue: months,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('الموعد الدوري'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('بدون تكرار')),
                    DropdownMenuItem(value: 1, child: Text('شهري')),
                    DropdownMenuItem(value: 2, child: Text('كل شهرين')),
                    DropdownMenuItem(value: 3, child: Text('كل 3 شهور')),
                    DropdownMenuItem(value: 6, child: Text('كل 6 شهور')),
                    DropdownMenuItem(value: 12, child: Text('سنوي')),
                  ],
                  onChanged: (v) => setS(() =>
                      months = _normalizePeriodicRecurrenceMonths(v ?? 0)),
                ),
                SizedBox(height: 8.h),
                Text(
                  _periodicRecurrenceHint(months),
                  style: GoogleFonts.cairo(
                    color: const Color(0xFFB91C1C),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 8.h),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: providers.isEmpty ? _showNoServiceProvidersErr : null,
                  child: AbsorbPointer(
                    absorbing: providers.isEmpty,
                    child: DropdownButtonFormField<String>(
                      initialValue: provider?.id,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(color: Colors.black87),
                      iconEnabledColor: Colors.black54,
                      decoration: _dd('مقدم الخدمة'),
                      items: providers
                          .map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.fullName)))
                          .toList(),
                      onChanged: (v) => setS(() => provider =
                          providers.firstWhereOrNull((p) => p.id == v)),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                TextField(
                    controller: amountCtl,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dd('المبلغ')),
                SizedBox(height: 8.h),
                DropdownButtonFormField<int>(
                  initialValue: remindBeforeDays,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  iconEnabledColor: Colors.black54,
                  decoration: _dd('موعد التنبيه قبل'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                    DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                    DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                    DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                  ],
                  onChanged: (v) =>
                      setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
                ),
                SizedBox(height: 8.h),
              ],
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                    onPressed: () async {
                      if (billingMode == 'owner' && provider == null) {
                        _showErr('يرجى اختيار مقدم الخدمة');
                        return;
                      }
                      if (billingMode == 'owner' &&
                          !_ensurePeriodicServiceDateSelected(previewDate)) {
                        return;
                      }
                      final ok = await _confirmPeriodicServiceSave(ctx);
                      if (!ok) return;
                      final previousCfg = cfg;
                      final openPeriodicRequest =
                          _internetBillingModeFromCfg(previousCfg) == 'owner'
                              ? _trackedPeriodicServiceRequest(
                                  type, previousCfg)
                              : null;
                      if (billingMode == 'separate' &&
                          openPeriodicRequest != null) {
                        _showErr(
                          'لا يمكن تحويل خدمة الإنترنت إلى منفصل لوجود طلب دوري مفتوح. يرجى إنهاء الطلب الحالي أو حذفه أولًا.',
                        );
                        return;
                      }
                      final next = <String, dynamic>{
                        ...cfg,
                        'serviceType': type,
                        'internetBillingMode': billingMode,
                        'payer': billingMode == 'separate' ? 'tenant' : 'owner',
                      };
                      DateTime? effectiveDueDate;
                      if (billingMode == 'owner') {
                        final scheduleChanged =
                            _didPeriodicScheduleInputsChange(
                          didPickDate: didPickNextDate,
                          hasNextDate: hasNextDate,
                          hadNextDate: initialHasNextDate,
                          recurrenceMonths: months,
                          previousRecurrenceMonths: initialRecurrenceMonths,
                        );
                        final scheduleBaseDate = didPickNextDate
                            ? nextDate
                            : (trackedDueDate ?? configuredDueDate ?? nextDate);
                        final shouldResetGeneration = scheduleChanged
                            ? _shouldResetPeriodicGeneration(
                                type: type,
                                previousCfg: previousCfg,
                                newStartDate: scheduleBaseDate,
                                newNextDate:
                                    hasNextDate ? scheduleBaseDate : null,
                                newRecurrenceMonths: months,
                              )
                            : false;
                        final scheduleState =
                            _periodicServiceDraftScheduleState(
                          type: type,
                          previousCfg: previousCfg,
                          startDate: scheduleBaseDate,
                          recurrenceMonths: months,
                          hasNextDate: hasNextDate,
                        );
                        effectiveDueDate = scheduleChanged
                            ? scheduleState.storedDueDate
                            : configuredDueDate;
                        final effectiveStartDate = hasNextDate
                            ? (scheduleChanged
                                ? scheduleBaseDate
                                : originalStartDate)
                            : null;
                        final suppressedRequestDate =
                            _periodicServiceSuppressedDateForSave(
                          previousCfg: previousCfg,
                          shouldResetGeneration: shouldResetGeneration,
                          newDueDate: effectiveDueDate,
                        );
                        next.addAll({
                          'startDate':
                              effectiveStartDate?.toIso8601String() ?? '',
                          'dueDay': effectiveDueDate?.day ?? '',
                          'nextDueDate':
                              effectiveDueDate?.toIso8601String() ?? '',
                          'defaultAmount': _numParse(amountCtl.text.trim()),
                          'recurrenceMonths': months,
                          'remindBeforeDays': remindBeforeDays,
                          'providerId': provider?.id ?? '',
                          'providerName': provider?.fullName ?? '',
                          'suppressedRequestDate': suppressedRequestDate,
                        });
                        if (scheduleChanged && shouldResetGeneration) {
                          next['lastGeneratedRequestDate'] = '';
                          next['lastGeneratedRequestId'] = '';
                          next['targetId'] = '';
                        }
                      } else {
                        // separate: المستأجر يدفع - تنظيف جميع حقول الدوري
                        next.addAll({
                          'startDate': '',
                          'dueDay': '',
                          'nextDueDate': '',
                          'defaultAmount': 0.0,
                          'recurrenceMonths': 0,
                          'remindBeforeDays': 0,
                          'providerId': '',
                          'providerName': '',
                          'lastGeneratedRequestDate': '',
                          'lastGeneratedRequestId': '',
                          'targetId': '',
                          'suppressedRequestDate': '',
                        });
                        next.remove('nextServiceDate');
                      }
                      cfg = next;
                      await _saveCfg(type, next);
                      if (billingMode == 'owner') {
                        final trackedRequest =
                            await _syncTrackedPeriodicServiceRequestFromConfig(
                          maintenanceBox: _maintenance,
                          invoicesBox: _invoices,
                          propertyId: widget.propertyId,
                          type: type,
                          cfg: next,
                          lookupCfg: previousCfg,
                        );
                        if (trackedRequest != null) {
                          final trackedCfg =
                              _periodicServiceConfigWithTrackedRequest(
                            cfg: next,
                            request: trackedRequest,
                          );
                          cfg = trackedCfg;
                          await _saveCfg(type, trackedCfg);
                        }
                        await _clearPeriodicServiceNotificationDismissals(
                          type: type,
                          startDate: didPickNextDate
                              ? nextDate
                              : (trackedDueDate ??
                                  configuredDueDate ??
                                  nextDate),
                          nextDate: effectiveDueDate,
                        );
                        if (_services != null) {
                          await ensurePeriodicServiceRequestsGenerated(
                            servicesBox: _services,
                            maintenanceBox: _maintenance,
                            invoicesBox: _invoices,
                            serviceKeys: {_serviceKey(type)},
                          );
                        }
                        final refreshedCfg = _cfg(type);
                        final generatedDate =
                            _periodicServiceLastGeneratedDateFromConfig(
                                refreshedCfg);
                        final generatedRequestId =
                            (refreshedCfg['targetId'] ?? '').toString().trim();
                        if (generatedDate != null) {
                          await _clearPeriodicServiceNotificationDismissals(
                            type: type,
                            startDate: generatedDate,
                            nextDate: generatedDate,
                          );
                        }
                        if (generatedDate != null &&
                            generatedRequestId.isNotEmpty) {
                          await _clearMaintenanceNotificationDismissal(
                            requestId: generatedRequestId,
                            anchor: generatedDate,
                          );
                        }
                      }
                      _showOk('تم حفظ الإعدادات');
                      if (mounted) setS(() {});
                    },
                    child: Text('حفظ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                    child: ElevatedButton(
                        style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('إلغاء',
                            style: GoogleFonts.cairo(color: Colors.black87)))),
              ]),
              if (billingMode == 'owner') ...[
                SizedBox(height: 10.h),
                Center(
                  child: Text('سجل الطلبات',
                      style: GoogleFonts.cairo(
                          color: Colors.black87, fontWeight: FontWeight.w800)),
                ),
                SizedBox(height: 6.h),
                if (_internetOwnerRequests().isEmpty)
                  Text('لا توجد طلبات بعد',
                      style: GoogleFonts.cairo(color: Colors.black54))
                else
                  _scrollList(_internetOwnerRequests().map((r) {
                    final when = _periodicServiceRequestAnchor(r);
                    return _periodicServiceLogRow(
                      ctx,
                      r,
                      when,
                      setModalState: setS,
                    );
                  }).toList()),
              ],
            ]),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _openElevatorSimple({bool replaceCurrent = false}) async {
    final cfg = _cfg('elevator');
    final trackedDueDate = _trackedPeriodicServiceDueDate('elevator', cfg);
    final configuredDueDate = _periodicServiceScheduleState(
      type: 'elevator',
      cfg: cfg,
    ).storedDueDate;
    final originalStartDate = _periodicServiceStartDateFromConfig(cfg);
    final hasConfiguredSchedule = _isConfigured('elevator', cfg);
    final initialHasNextDate =
        trackedDueDate != null || configuredDueDate != null;
    final initialRecurrenceMonths = _normalizePeriodicRecurrenceMonths(
      ((cfg['recurrenceMonths'] as num?)?.toInt() ?? 0),
    );
    DateTime nextDate = trackedDueDate ??
        configuredDueDate ??
        originalStartDate ??
        KsaTime.today();
    final initialDisplayDate = nextDate;
    var hasNextDate = initialHasNextDate;
    var didPickNextDate = false;
    var months = initialRecurrenceMonths;
    var remindBeforeDays =
        ((cfg['remindBeforeDays'] as num?)?.toInt() ?? 0).clamp(0, 3);
    final amountCtl =
        TextEditingController(text: _periodicServiceDefaultAmountText(cfg));
    final providers = _providers();
    Tenant? provider = providers
        .firstWhereOrNull((p) => p.id == (cfg['providerId']?.toString() ?? ''));
    await _openServicePage(
      'إعدادات صيانة المصعد',
      StatefulBuilder(
        builder: (ctx, setS) {
          final schedulePreview = _periodicServiceDraftScheduleState(
            type: 'elevator',
            previousCfg: cfg,
            startDate: nextDate,
            recurrenceMonths: months,
            hasNextDate: hasNextDate,
          );
          final previewDate = schedulePreview.storedDueDate;
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InputDecorator(
                  decoration: _dd('الجهة المسؤولة'),
                  child: Text('المالك',
                      style: GoogleFonts.cairo(color: Colors.black87))),
              SizedBox(height: 8.h),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('موعد التنفيذ القادم',
                    style: GoogleFonts.cairo(color: Colors.black87)),
                subtitle: Text(
                    previewDate != null
                        ? _fmt(previewDate)
                        : _periodicServiceNoUpcomingDateLabel(),
                    style: GoogleFonts.cairo(
                        color: Colors.black54, fontSize: 12.sp)),
                trailing: const Icon(Icons.event_available_rounded,
                    color: Colors.black54),
                onTap: () async {
                  final p = await showDatePicker(
                      context: ctx,
                      initialDate: nextDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (p != null) {
                    setS(() {
                      nextDate = KsaTime.dateOnly(p);
                      hasNextDate = true;
                      didPickNextDate = !_samePeriodicDate(
                        nextDate,
                        initialDisplayDate,
                      );
                    });
                  }
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: months,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('الموعد الدوري'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بدون تكرار')),
                  DropdownMenuItem(value: 1, child: Text('كل شهر')),
                  DropdownMenuItem(value: 2, child: Text('كل شهرين')),
                  DropdownMenuItem(value: 3, child: Text('كل 3 شهور')),
                  DropdownMenuItem(value: 6, child: Text('كل 6 شهور')),
                  DropdownMenuItem(value: 12, child: Text('سنوي')),
                ],
                onChanged: (v) => setS(
                    () => months = _normalizePeriodicRecurrenceMonths(v ?? 0)),
              ),
              SizedBox(height: 8.h),
              Text(
                _periodicRecurrenceHint(months),
                style: GoogleFonts.cairo(
                  color: const Color(0xFFB91C1C),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 8.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: providers.isEmpty ? _showNoServiceProvidersErr : null,
                child: AbsorbPointer(
                  absorbing: providers.isEmpty,
                  child: DropdownButtonFormField<String>(
                    initialValue: provider?.id,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: Colors.black87),
                    iconEnabledColor: Colors.black54,
                    decoration: _dd('مقدم الخدمة'),
                    items: providers
                        .map((p) => DropdownMenuItem(
                            value: p.id, child: Text(p.fullName)))
                        .toList(),
                    onChanged: (v) => setS(() => provider =
                        providers.firstWhereOrNull((p) => p.id == v)),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              TextField(
                  controller: amountCtl,
                  style: GoogleFonts.cairo(color: Colors.black87),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dd('تكلفة الخدمة')),
              SizedBox(height: 8.h),
              DropdownButtonFormField<int>(
                initialValue: remindBeforeDays,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: Colors.black87),
                iconEnabledColor: Colors.black54,
                decoration: _dd('موعد التنبيه قبل'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بدون تنبيه')),
                  DropdownMenuItem(value: 1, child: Text('قبل يوم')),
                  DropdownMenuItem(value: 2, child: Text('قبل يومين')),
                  DropdownMenuItem(value: 3, child: Text('قبل 3 أيام')),
                ],
                onChanged: (v) =>
                    setS(() => remindBeforeDays = (v ?? 0).clamp(0, 3)),
              ),
              SizedBox(height: 8.h),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    style: _actionButtonStyle(const Color(0xFFDDEAFE)),
                    onPressed: () async {
                      if (provider == null) {
                        _showErr('يرجى اختيار مقدم الخدمة');
                        return;
                      }
                      if (!_ensurePeriodicServiceDateSelected(previewDate)) {
                        return;
                      }
                      final ok = await _confirmPeriodicServiceSave(ctx);
                      if (!ok) return;
                      final scheduleChanged = _didPeriodicScheduleInputsChange(
                        didPickDate: didPickNextDate,
                        hasNextDate: hasNextDate,
                        hadNextDate: initialHasNextDate,
                        recurrenceMonths: months,
                        previousRecurrenceMonths: initialRecurrenceMonths,
                      );
                      final scheduleBaseDate = didPickNextDate
                          ? nextDate
                          : (trackedDueDate ?? configuredDueDate ?? nextDate);
                      final shouldResetGeneration = scheduleChanged
                          ? _shouldResetPeriodicGeneration(
                              type: 'elevator',
                              previousCfg: cfg,
                              newStartDate: scheduleBaseDate,
                              newNextDate:
                                  hasNextDate ? scheduleBaseDate : null,
                              newRecurrenceMonths: months,
                            )
                          : false;
                      final scheduleState = _periodicServiceDraftScheduleState(
                        type: 'elevator',
                        previousCfg: cfg,
                        startDate: scheduleBaseDate,
                        recurrenceMonths: months,
                        hasNextDate: hasNextDate,
                      );
                      final effectiveDueDate = scheduleChanged
                          ? scheduleState.storedDueDate
                          : configuredDueDate;
                      final effectiveStartDate = hasNextDate
                          ? (scheduleChanged
                              ? scheduleBaseDate
                              : originalStartDate)
                          : null;
                      final suppressedRequestDate =
                          _periodicServiceSuppressedDateForSave(
                        previousCfg: cfg,
                        shouldResetGeneration: shouldResetGeneration,
                        newDueDate: effectiveDueDate,
                      );
                      final updatedCfg = {
                        ...cfg,
                        'serviceType': 'elevator',
                        'payer': 'owner',
                        'startDate':
                            effectiveStartDate?.toIso8601String() ?? '',
                        'nextDueDate':
                            effectiveDueDate?.toIso8601String() ?? '',
                        'recurrenceMonths': months,
                        'remindBeforeDays': remindBeforeDays,
                        'providerId': provider?.id ?? '',
                        'providerName': provider?.fullName ?? '',
                        'defaultAmount': _numParse(amountCtl.text.trim()),
                        'suppressedRequestDate': suppressedRequestDate,
                      };
                      if (shouldResetGeneration) {
                        updatedCfg['lastGeneratedRequestDate'] = '';
                        updatedCfg['lastGeneratedRequestId'] = '';
                        updatedCfg['targetId'] = '';
                      }
                      await _saveCfg('elevator', updatedCfg);
                      final trackedRequest =
                          await _syncTrackedPeriodicServiceRequestFromConfig(
                        maintenanceBox: _maintenance,
                        invoicesBox: _invoices,
                        propertyId: widget.propertyId,
                        type: 'elevator',
                        cfg: updatedCfg,
                        lookupCfg: cfg,
                      );
                      if (trackedRequest != null) {
                        await _saveCfg(
                          'elevator',
                          _periodicServiceConfigWithTrackedRequest(
                            cfg: updatedCfg,
                            request: trackedRequest,
                          ),
                        );
                      }
                      await _clearPeriodicServiceNotificationDismissals(
                        type: 'elevator',
                        startDate: scheduleBaseDate,
                        nextDate: effectiveDueDate,
                      );
                      if (_services != null) {
                        await ensurePeriodicServiceRequestsGenerated(
                          servicesBox: _services,
                          maintenanceBox: _maintenance,
                          invoicesBox: _invoices,
                          serviceKeys: {_serviceKey('elevator')},
                        );
                      }
                      final refreshedCfg = _cfg('elevator');
                      final generatedDate =
                          _periodicServiceLastGeneratedDateFromConfig(
                              refreshedCfg);
                      final generatedRequestId =
                          (refreshedCfg['targetId'] ?? '').toString().trim();
                      if (generatedDate != null) {
                        await _clearPeriodicServiceNotificationDismissals(
                          type: 'elevator',
                          startDate: generatedDate,
                          nextDate: generatedDate,
                        );
                      }
                      if (generatedDate != null &&
                          generatedRequestId.isNotEmpty) {
                        await _clearMaintenanceNotificationDismissal(
                          requestId: generatedRequestId,
                          anchor: generatedDate,
                        );
                      }
                      if (mounted) setState(() {});
                      _showOk('تم حفظ إعدادات الخدمة');
                      if (mounted) setS(() {});
                    },
                    child: Text('حفظ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                    child: ElevatedButton(
                        style: _actionButtonStyle(const Color(0xFFF1F5F9)),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('إلغاء',
                            style: GoogleFonts.cairo(color: Colors.black87)))),
              ]),
              SizedBox(height: 10.h),
              Center(
                child: Text('سجل الطلبات',
                    style: GoogleFonts.cairo(
                        color: Colors.black87, fontWeight: FontWeight.w800)),
              ),
              SizedBox(height: 6.h),
              if (_elevatorRequests().isEmpty)
                Text('لا توجد طلبات بعد',
                    style: GoogleFonts.cairo(color: Colors.black54))
              else
                _scrollList(_elevatorRequests().map((r) {
                  final when = _periodicServiceRequestAnchor(r);
                  return _periodicServiceLogRow(
                    ctx,
                    r,
                    when,
                    setModalState: setS,
                  );
                }).toList()),
            ]),
          );
        },
      ),
      replaceCurrent: replaceCurrent,
    );
  }

  String _nextInvoiceSerial() {
    final year = KsaTime.now().year;
    var maxSeq = 0;
    for (final inv in _invoices.values) {
      final s = inv.serialNo;
      if (s == null || !s.startsWith('$year-')) continue;
      final tail = s.split('-').last;
      final n = int.tryParse(tail) ?? 0;
      if (n > maxSeq) maxSeq = n;
    }
    final next = maxSeq + 1;
    return '$year-${next.toString().padLeft(4, '0')}';
  }

  Future<String> _addOwnerExpense({
    required String targetPropertyId,
    required double amount,
    required String note,
    required DateTime date,
    DateTime? dueDate,
  }) async {
    final now = KsaTime.now();
    final amt = amount.abs();
    final effectiveDueDate = KsaTime.dateOnly(dueDate ?? date);
    final inv = Invoice(
      id: now.microsecondsSinceEpoch.toString(),
      serialNo: _nextInvoiceSerial(),
      tenantId: '',
      contractId: '',
      propertyId: targetPropertyId,
      issueDate: date,
      dueDate: effectiveDueDate,
      amount: -amt,
      paidAmount: amt,
      currency: 'SAR',
      note: note,
      paymentMethod: 'تحويل بنكي',
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );
    await _invoices.put(inv.id, inv);
    return inv.id;
  }

  DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);

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

  DateTime _addMonthsSafe(DateTime d, int months) {
    final y0 = d.year;
    final m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final safeDay = d.day > lastDay ? lastDay : d.day;
    return DateTime(y, m, safeDay);
  }

  Contract? _activeContractForPropertyId(String propertyId) {
    final now = KsaTime.now();
    final list = _contracts.values
        .where((c) =>
            c.propertyId == propertyId &&
            !c.isTerminated &&
            !c.isArchived &&
            c.startDate.isBefore(now.add(const Duration(days: 1))) &&
            c.endDate.isAfter(now.subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return list.isNotEmpty ? list.first : null;
  }

  Contract? _activeContractForProperty() =>
      _activeContractForPropertyId(widget.propertyId);

  bool _waterSettingsLocked(Map<String, dynamic> cfg) {
    final linkedCid = (cfg['waterLinkedContractId'] ?? '').toString().trim();
    if (linkedCid.isEmpty) return false;
    // مقفل إذا كان مربوط بعقد نشط
    final contract = _activeContractForProperty();
    if (contract != null && contract.id == linkedCid) return true;
    return false;
  }

  int _waterHistoryCount(Map<String, dynamic> cfg, String key) {
    final raw = cfg[key];
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString().trim()) ?? 0;
  }

  double _waterHistoryAmount(Map<String, dynamic> cfg, String key) {
    final raw = cfg[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse((raw ?? '').toString().trim()) ?? 0.0;
  }

  Contract? _waterLastContract(Map<String, dynamic> cfg) {
    final contractId = (cfg['waterLastContractId'] ?? '').toString().trim();
    if (contractId.isEmpty) return null;
    return _contracts.values.firstWhereOrNull((c) => c.id == contractId);
  }

  String _waterLastContractStatus(Map<String, dynamic> cfg) {
    final contract = _waterLastContract(cfg);
    if (contract == null) return 'منتهي';
    if (contract.isTerminated || contract.isArchived) return 'منتهي';
    if (contract.isActiveNow) return 'نشط';
    return 'غير نشط';
  }

  Widget _waterHistoricalSummary(
    BuildContext ctx,
    Map<String, dynamic> cfg,
  ) {
    final contractId = (cfg['waterLastContractId'] ?? '').toString().trim();
    final totalCount = _waterHistoryCount(cfg, 'waterLastInstallmentsCount');
    if (contractId.isEmpty || totalCount <= 0) {
      return Text('لم يتم الربط بعقد بعد',
          style: GoogleFonts.cairo(color: Colors.black54));
    }

    final paidCount = _waterHistoryCount(cfg, 'waterLastPaidInstallmentsCount');
    final canceledCount =
        _waterHistoryCount(cfg, 'waterLastCanceledInstallmentsCount');
    final paidAmount = _waterHistoryAmount(cfg, 'waterLastPaidAmount');
    final canceledAmount = _waterHistoryAmount(cfg, 'waterLastCanceledAmount');
    final contract = _waterLastContract(cfg);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'أرشيف المياه',
            style: GoogleFonts.cairo(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'حالة آخر عقد مرتبط: ${_waterLastContractStatus(cfg)}',
            style: GoogleFonts.cairo(color: Colors.black87),
          ),
          Text(
            'الأقساط المسددة سابقًا: $paidCount',
            style: GoogleFonts.cairo(color: Colors.black87),
          ),
          Text(
            'الأقساط الملغية سابقًا: $canceledCount',
            style: GoogleFonts.cairo(color: Colors.black87),
          ),
          Text(
            'إجمالي المسدد سابقًا: ${paidAmount.toStringAsFixed(2)} ريال',
            style: GoogleFonts.cairo(color: Colors.black87),
          ),
          Text(
            'إجمالي الملغي سابقًا: ${canceledAmount.toStringAsFixed(2)} ريال',
            style: GoogleFonts.cairo(color: Colors.black87),
          ),
          if (contract != null) ...[
            SizedBox(height: 6.h),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) =>
                          ContractDetailsScreen(contract: contract)));
                },
                child: Text(
                  'عرض العقد السابق',
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasWaterHistoricalArchive(Map<String, dynamic> cfg) {
    final contractId = (cfg['waterLastContractId'] ?? '').toString().trim();
    final totalCount = _waterHistoryCount(cfg, 'waterLastInstallmentsCount');
    return contractId.isNotEmpty && totalCount > 0;
  }

  bool _isContractDuePaid(Contract c, DateTime due) {
    final dueOnly = _d0(due);
    for (final inv in _invoices.values) {
      if (inv.contractId != c.id) continue;
      if (inv.isCanceled) continue;
      if (inv.paidAmount < (inv.amount - 0.000001)) continue;
      if (_d0(inv.dueDate) == dueOnly) return true;
    }
    return false;
  }

  List<DateTime> _unpaidContractDues(Contract c) {
    if (c.term == ContractTerm.daily) return const [];
    final end = _d0(c.endDate);
    final start = _d0(c.startDate);
    final step = _monthsPerCycleForContract(c);
    final out = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      if (!_isContractDuePaid(c, cursor)) {
        out.add(cursor);
      }
      cursor = _d0(_addMonthsSafe(cursor, step));
    }
    return out;
  }

  List<DateTime> _allContractDues(Contract c) {
    if (c.term == ContractTerm.daily) return const [];
    final end = _d0(c.endDate);
    final start = _d0(c.startDate);
    final step = _monthsPerCycleForContract(c);
    final out = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      out.add(cursor);
      cursor = _d0(_addMonthsSafe(cursor, step));
    }
    return out;
  }

  List<Map<String, dynamic>> _waterInstallmentsFromCfg(
      Map<String, dynamic> cfg) {
    final raw = cfg['waterInstallments'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _waterPercentRequestsFromCfg(
      Map<String, dynamic> cfg) {
    final raw = cfg['waterPercentRequests'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Map<String, dynamic> _rebuildWaterFixedConfig({
    required Map<String, dynamic> currentCfg,
    required double totalWaterAmount,
  }) {
    final contract = _activeContractForProperty();
    if (contract == null) {
      return contracts_ui.normalizeWaterConfigForNoActiveContract({
        ...currentCfg,
        'serviceType': 'water',
        'payer': 'owner',
        'waterBillingMode': 'shared',
        'waterSharedMethod': 'fixed',
        'sharePercent': null,
        'waterPercentRequests': <Map<String, dynamic>>[],
        'waterMeterNo': '',
        'totalWaterAmount': totalWaterAmount,
      });
    }
    return contracts_ui.rebuildWaterFixedConfigForContract(
      currentCfg: currentCfg,
      contract: contract,
      invoices: _invoices.values,
      totalWaterAmount: totalWaterAmount,
    );
  }

  bool _waterNeedsRecalc(Map<String, dynamic> cfg) {
    if ((cfg['waterBillingMode'] ?? '').toString() != 'shared') return false;
    if ((cfg['waterSharedMethod'] ?? '').toString() != 'fixed') return false;
    final total = ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0.0);
    if (total <= 0) return false;
    final rows = _waterInstallmentsFromCfg(cfg);
    if (rows.isEmpty) return true;
    final pending = rows.where((r) => (r['status'] ?? '').toString() != 'paid');
    if (pending.isEmpty) return false;
    return pending.any((r) => ((r['amount'] as num?)?.toDouble() ?? 0) <= 0);
  }

  String _title(String type) {
    String s(List<int> c) => String.fromCharCodes(c);
    switch (type) {
      case 'water':
        return s([0x0645, 0x064A, 0x0627, 0x0647]);
      case 'electricity':
        return s([0x0643, 0x0647, 0x0631, 0x0628, 0x0627, 0x0621]);
      case 'internet':
        return s([0x0625, 0x0646, 0x062A, 0x0631, 0x0646, 0x062A]);
      case 'cleaning':
        return s([
          0x0646,
          0x0638,
          0x0627,
          0x0641,
          0x0629,
          0x0020,
          0x0639,
          0x0645,
          0x0627,
          0x0631,
          0x0629
        ]);
      case 'elevator':
        return s([
          0x0635,
          0x064A,
          0x0627,
          0x0646,
          0x0629,
          0x0020,
          0x0645,
          0x0635,
          0x0639,
          0x062F
        ]);
      default:
        return s([0x062E, 0x062F, 0x0645, 0x0629]);
    }
  }

  IconData _serviceIcon(String type) {
    switch (type) {
      case 'water':
        return Icons.water_drop_rounded;
      case 'electricity':
        return Icons.bolt_rounded;
      case 'internet':
        return Icons.wifi_rounded;
      case 'cleaning':
        return Icons.cleaning_services_rounded;
      case 'elevator':
        return Icons.elevator_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  List<Color> _serviceTileColors(String type) {
    switch (type) {
      case 'water':
        return const [Color(0xFFE0F2FE), Color(0xFFBAE6FD)];
      case 'electricity':
        return const [Color(0xFFFFF4D6), Color(0xFFFDE68A)];
      case 'internet':
        return const [Color(0xFFDDF7EE), Color(0xFFA7F3D0)];
      case 'cleaning':
        return const [Color(0xFFE8F8EA), Color(0xFFBBF7D0)];
      case 'elevator':
        return const [Color(0xFFEEEAFE), Color(0xFFDDD6FE)];
      default:
        return const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)];
    }
  }

  Color _serviceIconColor(String type) {
    switch (type) {
      case 'water':
        return const Color(0xFF0284C7);
      case 'electricity':
        return const Color(0xFFD97706);
      case 'internet':
        return const Color(0xFF059669);
      case 'cleaning':
        return const Color(0xFF16A34A);
      case 'elevator':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF475569);
    }
  }

  DateTime? _serviceDueDate(String type, Map<String, dynamic> cfg) {
    if (type == 'water' || type == 'electricity') {
      final raw = cfg['nextDueDate'];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      return null;
    }
    if (type == 'internet') {
      if (_internetBillingModeFromCfg(cfg) == 'separate') return null;
      final raw = cfg['nextDueDate'];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      return null;
    }
    if (type == 'cleaning') {
      final raw = cfg['nextDueDate'];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      return null;
    }
    if (type == 'elevator') {
      final raw = cfg['nextDueDate'];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      return null;
    }
    return null;
  }

  DateTime? _serviceDisplayDate(String type, Map<String, dynamic> cfg) {
    final isInternetOwner =
        type == 'internet' && _internetBillingModeFromCfg(cfg) == 'owner';
    if (type == 'cleaning' || type == 'elevator' || isInternetOwner) {
      final tracked = _trackedPeriodicServiceRequest(type, cfg);
      if (tracked != null) {
        return _periodicServiceRequestAnchor(tracked);
      }
      return _periodicServiceScheduleState(
        type: type,
        cfg: cfg,
      ).storedDueDate;
    }
    return _serviceDueDate(type, cfg);
  }

  String _waterDueLabel(DateTime due) {
    final dueOnly = KsaTime.dateOnly(due);
    final todayOnly = KsaTime.dateOnly(KsaTime.today());
    if (dueOnly.isBefore(todayOnly)) return 'تاريخ الاستحقاق المتأخر: ';
    if (dueOnly == todayOnly) return 'تاريخ الاستحقاق الحالي: ';
    return 'تاريخ السداد القادم: ';
  }

  String _waterDueTitle(DateTime due) {
    final dueOnly = KsaTime.dateOnly(due);
    final todayOnly = KsaTime.dateOnly(KsaTime.today());
    if (dueOnly.isBefore(todayOnly)) return 'تاريخ الاستحقاق المتأخر';
    if (dueOnly == todayOnly) return 'تاريخ الاستحقاق الحالي';
    return 'تاريخ السداد القادم';
  }

  bool _isConfigured(String type, Map<String, dynamic> cfg) {
    if (_buildingWithUnits && (type == 'water' || type == 'electricity')) {
      final mode = _sharedUnitsModeForType(type, cfg);
      if (_isUnitsManagedMode(type, mode)) return true;
      if (mode == 'shared_percent') return _sharedUnitsPercentConfigReady(cfg);
      return false;
    }
    if (_unitUnderPerUnitBuilding &&
        (type == 'water' || type == 'electricity')) {
      final mode = _effectiveSharedUnitsMode(type);
      if (mode == 'shared_percent') {
        return _unitSharedServiceReadyFromBuilding(type);
      }
      if (type == 'water' && mode == 'units_separate') return true;
      if (type == 'water' && mode == 'units_fixed') {
        final localMode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (localMode != 'shared') return false;
        final localMethod = (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (localMethod != 'fixed') return false;
        final rows = _waterInstallmentsFromCfg(cfg);
        if (rows.isNotEmpty) return true;
        return ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0) > 0;
      } else if (mode != 'units') {
        return false;
      }
    }
    if (cfg.isEmpty) return false;
    switch (type) {
      case 'cleaning':
        return _periodicServiceStartDateFromConfig(cfg) != null &&
            (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
      case 'elevator':
        return _periodicServiceStartDateFromConfig(cfg) != null &&
            (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
      case 'internet':
        if (_internetBillingModeFromCfg(cfg) == 'separate') return true;
        return _periodicServiceStartDateFromConfig(cfg) != null &&
            (cfg['providerName'] ?? '').toString().trim().isNotEmpty;
      case 'water':
        final mode = (cfg['waterBillingMode'] ?? '').toString();
        if (mode == 'separate') return true;
        if (mode == 'shared') {
          final method = (cfg['waterSharedMethod'] ?? '').toString();
          if (method == 'percent') {
            return (cfg['sharePercent'] as num?) != null;
          }
          if (method == 'fixed') {
            final rows = _waterInstallmentsFromCfg(cfg);
            if (rows.isNotEmpty) return true;
            return ((cfg['totalWaterAmount'] as num?)?.toDouble() ?? 0) > 0;
          }
        }
        return false;
      case 'electricity':
        final mode =
            (cfg['electricityBillingMode'] ?? cfg['mode'] ?? 'separate')
                .toString()
                .trim()
                .toLowerCase();
        if (mode == 'separate') return true;
        if (mode != 'shared') return false;
        return _numParse((cfg['electricitySharePercent'] ?? '').toString()) > 0;
      default:
        return cfg.isNotEmpty;
    }
  }

  bool _isSeparateServiceMode(String type, Map<String, dynamic> cfg) {
    switch (type) {
      case 'water':
        return (cfg['waterBillingMode'] ?? cfg['mode'] ?? '')
                .toString()
                .trim()
                .toLowerCase() ==
            'separate';
      case 'electricity':
        return (cfg['electricityBillingMode'] ?? cfg['mode'] ?? '')
                .toString()
                .trim()
                .toLowerCase() ==
            'separate';
      case 'internet':
        return _internetBillingModeFromCfg(cfg) == 'separate';
      default:
        return false;
    }
  }

  String _serviceSummary(String type, Map<String, dynamic> cfg) {
    String s(List<int> c) => String.fromCharCodes(c);
    final inactiveLabel = _periodicServiceInactiveLabel();
    if (_buildingWithUnits && (type == 'water' || type == 'electricity')) {
      final mode = _sharedUnitsModeForType(type, cfg);
      if (_isUnitsManagedMode(type, mode)) {
        return _sharedUnitsManagedModeLabel(type, mode);
      }
      if (mode == 'shared_percent') {
        if (!_sharedUnitsPercentConfigReady(cfg)) return inactiveLabel;
        final due = _serviceDisplayDate(type, cfg);
        if (due == null) return 'التوزيع على الشقق المؤجرة بالتساوي';
        return 'التوزيع على الشقق المؤجرة بالتساوي • ${_fmt(KsaTime.dateOnly(due))}';
      }
      return inactiveLabel;
    }
    if (_unitUnderPerUnitBuilding &&
        (type == 'water' || type == 'electricity')) {
      final mode = _effectiveSharedUnitsMode(type);
      if (mode == 'shared_percent') {
        final parentCfg = _parentSharedServiceCfg(type);
        if (!_sharedUnitsPercentConfigReady(parentCfg)) {
          return 'يتطلب ضبطًا من العمارة';
        }
        return 'يُدار من العمارة • يُقسَّم بالتساوي على الشقق المؤجرة';
      }
      if (type == 'water' && mode == 'units_separate') {
        return 'يُدار من العمارة • منفصل';
      }
      if (type == 'water' && mode == 'units_fixed') {
        if (!_isConfigured(type, cfg)) return 'يتطلب ضبط المبلغ المقطوع';
      } else if (mode != 'units') {
        return 'يتطلب ضبطًا من العمارة';
      }
    }
    final usesInactiveLabel = type == 'cleaning' ||
        type == 'elevator' ||
        (type == 'internet' && _internetBillingModeFromCfg(cfg) == 'owner');
    if (!_isConfigured(type, cfg)) {
      if (type == 'water' || type == 'electricity' || type == 'internet') {
        return inactiveLabel;
      }
      return usesInactiveLabel
          ? inactiveLabel
          : s([
              0x063A,
              0x064A,
              0x0631,
              0x0020,
              0x0645,
              0x0636,
              0x0628,
              0x0648,
              0x0637
            ]);
    }
    if (_isSeparateServiceMode(type, cfg)) {
      return 'مفعل: منفصل';
    }
    final due = _serviceDisplayDate(type, cfg);
    if (due != null) {
      final label = type == 'water'
          ? _waterDueLabel(due)
          : (type == 'internet' && _internetBillingModeFromCfg(cfg) == 'owner')
              ? 'القادم: '
              : (type == 'cleaning' || type == 'elevator')
                  ? 'الموعد القادم: '
                  : s([
                      0x0627,
                      0x0644,
                      0x0645,
                      0x0648,
                      0x0639,
                      0x062F,
                      0x003A,
                      0x0020
                    ]);
      return '$label${_fmt(KsaTime.dateOnly(due))}';
    }
    if (type == 'water' || type == 'electricity' || type == 'internet') {
      return inactiveLabel;
    }
    return usesInactiveLabel
        ? inactiveLabel
        : s([0x062A, 0x0645, 0x0020, 0x0627, 0x0644, 0x0636, 0x0628, 0x0637]);
  }

  InputDecoration _dd(String label, {String? hintText}) => InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: GoogleFonts.cairo(
            color: Colors.black87, fontWeight: FontWeight.w700),
        hintStyle: GoogleFonts.cairo(
          color: Colors.black38,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.12))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF0F766E)),
            borderRadius: BorderRadius.all(Radius.circular(12))),
      );

  InputDecoration _plainFieldDecoration({String? hintText}) => InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.cairo(
          color: Colors.black38,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF0F766E)),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  ButtonStyle _actionButtonStyle(Color color) => ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black87,
        elevation: 0,
        minimumSize: Size.fromHeight(46.h),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      );

  void _handleBottomTapFrom(BuildContext navContext, int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            navContext, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(navContext,
            MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            navContext,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            navContext,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

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
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inlineServicePageTitle != null && _inlineServicePageChild != null) {
      return _servicePageShell(
        _inlineServicePageTitle!,
        _inlineServicePageChild!,
      );
    }
    if (_property == null || _services == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tiles = _buildingWithUnits
        ? const <String>['water', 'electricity', 'cleaning', 'elevator']
        : (_isRootBuilding
            ? const <String>[
                'water',
                'electricity',
                'internet',
                'cleaning',
                'elevator'
              ]
            : ((_property?.parentBuildingId != null)
                ? const <String>['water', 'electricity', 'internet']
                : const <String>[
                    'water',
                    'electricity',
                    'internet',
                    'cleaning'
                  ]));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text(
              '\u0627\u0644\u062E\u062F\u0645\u0627\u062A \u0627\u0644\u062F\u0648\u0631\u064A\u0629',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6),
                  ],
                ),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isRootBuilding
                        ? '\u0646\u0637\u0627\u0642 \u0627\u0644\u062A\u0637\u0628\u064A\u0642: \u0627\u0644\u0639\u0645\u0627\u0631\u0629 \u0643\u0643\u0644'
                        : '\u0646\u0637\u0627\u0642 \u0627\u0644\u062A\u0637\u0628\u064A\u0642: \u0627\u0644\u0639\u0642\u0627\u0631 \u0643\u0643\u0644',
                    style: GoogleFonts.cairo(color: Colors.white70),
                  ),
                  SizedBox(height: 12.h),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10.h,
                    crossAxisSpacing: 10.w,
                    childAspectRatio: 1.12,
                    children: tiles
                        .map(
                          (t) => InkWell(
                            onTap: () => _openService(t),
                            borderRadius: BorderRadius.circular(14.r),
                            child: Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: _serviceTileColors(t),
                                ),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.10),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42.w,
                                    height: 42.w,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(14.r),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _serviceIcon(t),
                                      color: _serviceIconColor(t),
                                      size: 22,
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Text(
                                    _title(t),
                                    style: GoogleFonts.cairo(
                                      color: const Color(0xFF111827),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.sp,
                                    ),
                                  ),
                                  SizedBox(height: 4.h),
                                  Builder(builder: (_) {
                                    final cfg = _cfg(t);
                                    final ready = _isConfigured(t, cfg);
                                    return Text(
                                      _serviceSummary(t, cfg),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(
                                        color: ready
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFB91C1C),
                                        fontWeight: ready
                                            ? FontWeight.w600
                                            : FontWeight.w700,
                                        fontSize: 12.sp,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
            key: _bottomNavKey, currentIndex: 1, onTap: _handleBottomTap),
      ),
    );
  }
}

class _WaterCompanyExpenseAmountDialog extends StatefulWidget {
  const _WaterCompanyExpenseAmountDialog({
    required this.cycleDateLabel,
  });

  final String cycleDateLabel;

  @override
  State<_WaterCompanyExpenseAmountDialog> createState() =>
      _WaterCompanyExpenseAmountDialogState();
}

class _WaterCompanyExpenseAmountDialogState
    extends State<_WaterCompanyExpenseAmountDialog> {
  late final TextEditingController _amountCtl;
  late final FocusNode _amountFocusNode;
  String? _errorText;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _amountCtl = TextEditingController();
    _amountFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _amountFocusNode.unfocus();
    _amountFocusNode.dispose();
    _amountCtl.dispose();
    super.dispose();
  }

  Future<void> _close([double? value]) async {
    if (_isClosing) return;
    _isClosing = true;
    _amountFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  void _submit() {
    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0.0;
    if (amount <= 0) {
      setState(() {
        _errorText = 'يرجى إدخال مبلغ صحيح أكبر من صفر.';
      });
      return;
    }
    _close(amount);
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: GoogleFonts.cairo(
          color: Colors.black38,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF0F766E)),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  ButtonStyle _buttonStyle(Color color) => ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black87,
        elevation: 0,
        minimumSize: Size.fromHeight(46.h),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.r),
      ),
      titlePadding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 8.h),
      contentPadding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
      title: Text(
        'سند الصرف',
        style: GoogleFonts.cairo(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المبلغ الذي ستدخله هنا هو قيمة الفاتورة الأصلية من شركة المياه لهذه الدورة بتاريخ ${widget.cycleDateLabel}.',
              style: GoogleFonts.cairo(
                color: Colors.black87,
                height: 1.7,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'عند التأكيد سيتم إصدار سند صرف ليظهر بشكل صحيح في شاشة التقارير.',
              style: GoogleFonts.cairo(
                color: const Color(0xFF475569),
                height: 1.7,
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _amountCtl,
              focusNode: _amountFocusNode,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.cairo(color: Colors.black87),
              decoration: _inputDecoration('مبلغ فاتورة الشركة'),
            ),
            if (_errorText != null) ...[
              SizedBox(height: 8.h),
              Text(
                _errorText!,
                style: GoogleFonts.cairo(
                  color: const Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            SizedBox(height: 14.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _buttonStyle(const Color(0xFFDDEAFE)),
                onPressed: _submit,
                child: Text(
                  'تأكيد',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _buttonStyle(const Color(0xFFF1F5F9)),
                onPressed: () => _close(),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.cairo(color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T e) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
