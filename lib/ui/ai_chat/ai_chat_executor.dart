import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../data/constants/boxes.dart';
import '../../data/models/activity_log.dart';
import '../../data/services/app_architecture_registry.dart';
import '../../data/services/ai_chat_domain_rules_service.dart';
import '../../data/services/ai_chat_reports_bridge.dart';
import '../../data/services/offline_sync_service.dart';
import '../../data/services/office_client_guard.dart';
import '../../data/services/package_limit_service.dart';
import '../../data/services/subscription_alerts.dart';
import '../../data/services/tenant_record_service.dart';
import '../../data/services/user_scope.dart';
import '../../models/property.dart';
import '../../models/tenant.dart';
import 'ai_chat_app_blueprint.dart';
import 'ai_chat_permissions.dart';
import 'ai_chat_service.dart';
import 'ai_chat_tools.dart';
import '../../ui/contracts_screen.dart'
    show
        AdvanceMode,
        Contract,
        ContractTerm,
        PaymentCycle,
        isContractOverdueForHome,
        missingRequiredPeriodicServicesForProperty;
import '../../ui/invoices_screen.dart' show Invoice;
import '../../ui/maintenance_screen.dart'
    show
        MaintenanceRequest,
        MaintenancePriority,
        MaintenanceStatus,
        buildMaintenanceProviderSnapshot,
        createOrUpdateInvoiceForMaintenance,
        maintenanceLinkedPartyIdForProperty,
        markPeriodicServiceRequestSuppressedForCurrentCycle;
import '../../utils/contract_utils.dart';
import '../../utils/ksa_time.dart';

typedef NavCallback = Future<bool> Function(String route);

class _AiChatExecutorCacheEntry {
  final String result;
  final DateTime createdAt;

  const _AiChatExecutorCacheEntry({
    required this.result,
    required this.createdAt,
  });
}

class AiChatExecutor {
  final NavCallback? onNavigate;
  final ChatUserRole userRole;
  final AiChatScope chatScope;
  static const Duration _readCacheTtl = Duration(seconds: 20);
  static const int _maxReadCacheEntries = 120;
  static final Map<String, _AiChatExecutorCacheEntry> _readCache =
      <String, _AiChatExecutorCacheEntry>{};

  AiChatExecutor({
    this.onNavigate,
    this.userRole = ChatUserRole.viewOnly,
    this.chatScope = const AiChatScope.ownerSelf(),
  });

  Future<String> execute(
      String functionName, Map<String, dynamic> args) async {
    try {
      if (AiChatTools.isOfficeWideReadTool(functionName) && !_canReadAll) {
        return _err('ليس لديك صلاحية للاطلاع على بيانات المكتب العامة من هذا الحساب.');
      }
      if (AiChatTools.isWriteTool(functionName) && !_canWrite) {
        return _err(AiChatPermissions.denyMessage(userRole));
      }

      switch (functionName) {
        // ===== قراءة =====
        case 'get_home_dashboard':
          return _getHomeDashboard();
        case 'get_properties_summary':
          return _getPropertiesSummaryV2();
        case 'get_properties_list':
          return _getPropertiesListV3();
        case 'get_property_details':
          return _getPropertyDetailsV4(args['query'] ?? '');
        case 'get_tenants_list':
          return _getTenantsList();
        case 'get_tenant_details':
          return _getTenantDetails(args['query'] ?? '');
        case 'get_contracts_list':
          return _getContractsList();
        case 'get_active_contracts':
          return _getActiveContracts();
        case 'get_contract_details':
          return _getContractDetails(args['query'] ?? '');
        case 'get_contract_invoice_history':
          return _getContractInvoiceHistory(args['query'] ?? '');
        case 'get_invoices_list':
          return _getInvoicesList();
        case 'get_unpaid_invoices':
          return _getUnpaidInvoices();
        case 'get_maintenance_list':
          return _getMaintenanceList();
        case 'get_maintenance_details':
          return _getMaintenanceDetails(args['query'] ?? '');
        case 'get_total_receivables':
          return _getTotalReceivables();
        case 'get_overdue_count':
          return _getOverdueCount();
        case 'get_financial_summary':
          return _getFinancialSummary(args);
        case 'get_settings':
          return _getSettings(args);
        case 'update_settings':
          return _updateSettings(args);
        case 'open_notification_target':
          return _openNotificationTarget(args);
        case 'get_building_units':
          return _getBuildingUnitsV2(args['buildingName'] ?? '');
        case 'get_invoices_by_type':
          return _getInvoicesByType(args['origin'] ?? 'all');
        case 'get_invoice_payment_history':
          return _getInvoicePaymentHistory(args['invoiceSerialNo'] ?? '');
        case 'get_notifications':
          return _getNotifications(args);
        case 'get_properties_report':
          return _getPropertiesReport(args);
        case 'get_clients_report':
          return _getClientsReport(args);
        case 'get_contracts_report':
          return _getContractsReport(args);
        case 'get_services_report':
          return _getServicesReport(args);
        case 'get_invoices_report':
          return _getInvoicesReport(args);
        case 'get_office_report':
          return _getReportsOffice(args);
        case 'get_owners_report':
          return _getReportsOwners(args);
        case 'get_owner_report_details':
          return _getReportsOwnerDetails(args);
        case 'preview_owner_settlement':
          return _previewReportsOwnerSettlement(args);
        case 'preview_office_settlement':
          return _previewReportsOfficeSettlement(args);
        case 'get_owner_bank_accounts':
          return _getReportsOwnerBankAccounts(args);
        case 'get_app_blueprint':
          return _getAppBlueprint();

        // ===== كتابة - مستأجرين =====
        case 'add_tenant':
        case 'add_client_record':
          return _addTenant(args);
        case 'edit_tenant':
          return _editTenant(args);
        case 'archive_tenant':
          return _archiveTenant(args['query'] ?? '', true);
        case 'unarchive_tenant':
          return _archiveTenant(args['query'] ?? '', false);
        case 'blacklist_tenant':
          return _blacklistTenant(
              args['query'] ?? '', true, args['reason'] ?? '');
        case 'unblacklist_tenant':
          return _blacklistTenant(args['query'] ?? '', false, '');

        // ===== كتابة - عقارات =====
        case 'add_property':
          return _addProperty(args);
        case 'edit_property':
          return _editProperty(args);
        case 'archive_property':
          return _archiveProperty(args['query'] ?? '', true);
        case 'unarchive_property':
          return _archiveProperty(args['query'] ?? '', false);

        // ===== كتابة - عقود =====
        case 'create_contract':
          return _createContract(args);
        case 'edit_contract':
          return _editContract(args);
        case 'renew_contract':
          return _renewContract(args);
        case 'terminate_contract':
          return _terminateContract(args);

        // ===== كتابة - فواتير =====
        case 'create_invoice':
          return _createInvoice(args);
        case 'create_manual_voucher':
          return _createManualVoucher(args);
        case 'add_building_unit':
          return _addBuildingUnit(args);
        case 'record_payment':
          return _recordPayment(args);
        case 'cancel_invoice':
          return _cancelInvoice(args);

        // ===== كتابة - صيانة =====
        case 'create_maintenance_request':
          return _createMaintenanceRequest(args);
        case 'update_maintenance_status':
          return _updateMaintenanceStatus(args);

        // ===== خدمات دورية =====
        case 'create_periodic_service':
          return _createPeriodicService(args);
        case 'get_property_services':
          return _getPropertyServices(args['propertyName'] ?? '');
        case 'get_property_service_details':
          return _getPropertyServiceDetails(
            args['propertyName'] ?? '',
            args['serviceType'] ?? '',
          );
        case 'get_periodic_service_history':
          return _getPeriodicServiceHistory(
              args['propertyName'] ?? '', args['serviceType'] ?? '');
        case 'update_periodic_service':
          return _updatePeriodicService(args);
        case 'mark_notification_read':
          return _markNotificationRead(args);
        case 'assign_property_owner_from_reports':
          return _assignReportsPropertyOwner(args);
        case 'record_office_report_voucher':
          return _recordReportsOfficeVoucher(args);
        case 'record_office_withdrawal':
          return _recordReportsOfficeWithdrawal(args);
        case 'set_report_commission_rule':
          return _setReportsCommissionRule(args);
        case 'record_owner_payout':
          return _recordReportsOwnerPayout(args);
        case 'record_owner_adjustment':
          return _recordReportsOwnerAdjustment(args);
        case 'add_owner_bank_account':
          return _addReportsOwnerBankAccount(args);
        case 'edit_owner_bank_account':
          return _editReportsOwnerBankAccount(args);
        case 'delete_owner_bank_account':
          return _deleteReportsOwnerBankAccount(args);

        // ===== تنقل =====
        case 'navigate_to_screen':
          return await _navigateToScreen(args['screen'] ?? '');
        case 'open_tenant_entry':
          return _openTenantEntry(args);
        case 'open_property_entry':
          return _openPropertyEntry(args);
        case 'open_contract_entry':
          return _openContractEntry(args);
        case 'open_maintenance_entry':
          return _openMaintenanceEntry(args);
        case 'open_contract_invoice_history':
          return _openContractInvoiceHistory(args);

        // ===== مكتب =====
        case 'get_office_dashboard':
          return await _getOfficeDashboard();
        case 'get_office_clients_list':
          return await _getOfficeClientsList();
        case 'get_office_client_details':
          return await _getOfficeClientDetails(args['clientName'] ?? '');
        case 'get_office_summary':
          return await _getOfficeSummary();
        case 'get_office_users_list':
          return await _getOfficeUsersList();
        case 'get_office_user_details':
          return await _getOfficeUserDetails(args);
        case 'get_activity_log':
          return await _getActivityLog(args);
        case 'get_office_client_access':
          return await _getOfficeClientAccess(args);
        case 'get_office_client_subscription':
          return await _getOfficeClientSubscription(args);
        case 'add_office_client':
          return await _addOfficeClient(args);
        case 'edit_office_client':
          return await _editOfficeClient(args);
        case 'delete_office_client':
          return await _deleteOfficeClient(args);
        case 'set_office_client_access':
          return await _setOfficeClientAccess(args);
        case 'set_office_client_subscription':
          return await _setOfficeClientSubscription(args);
        case 'generate_office_client_reset_link':
          return await _generateOfficeClientResetLink(args);
        case 'add_office_user':
          return await _addOfficeUser(args);
        case 'edit_office_user':
          return await _editOfficeUser(args);
        case 'set_office_user_permission':
          return await _setOfficeUserPermission(args);
        case 'set_office_user_access':
          return await _setOfficeUserAccess(args);
        case 'delete_office_user':
          return await _deleteOfficeUser(args);
        case 'generate_office_user_reset_link':
          return await _generateOfficeUserResetLink(args);

        default:
          return _err('أداة غير معروفة: $functionName');
      }
    } catch (e) {
      return _err('حدث خطأ: $e');
    }
  }

  Future<String> executeCached(
    String functionName,
    Map<String, dynamic> args,
  ) async {
    final cachedResult = _tryGetCachedReadResult(functionName, args);
    if (cachedResult != null) {
      return cachedResult;
    }

    final result = await execute(functionName, args);
    if (AiChatTools.isWriteTool(functionName)) {
      _invalidateReadCache();
      return result;
    }

    _cacheReadResult(functionName, args, result);
    return result;
  }

  // ================================================================
  //  مساعدات
  // ================================================================

  String _err(String msg) => jsonEncode({'error': msg});
  String _ok(String msg) => jsonEncode({'success': true, 'message': msg});

  bool _isCacheableReadTool(String functionName) {
    if (AiChatTools.isWriteTool(functionName)) {
      return false;
    }
    return functionName.startsWith('get_') ||
        functionName.startsWith('preview_');
  }

  String _readCacheKey(String functionName, Map<String, dynamic> args) {
    return [
      chatScope.storageTypeKey,
      chatScope.normalizedScopeId,
      userRole.name,
      functionName,
      jsonEncode(args),
    ].join('|');
  }

  String? _tryGetCachedReadResult(
    String functionName,
    Map<String, dynamic> args,
  ) {
    if (!_isCacheableReadTool(functionName)) {
      return null;
    }

    final key = _readCacheKey(functionName, args);
    final entry = _readCache[key];
    if (entry == null) {
      return null;
    }

    final isExpired = DateTime.now().difference(entry.createdAt) > _readCacheTtl;
    if (isExpired) {
      _readCache.remove(key);
      return null;
    }

    return entry.result;
  }

  void _cacheReadResult(
    String functionName,
    Map<String, dynamic> args,
    String result,
  ) {
    if (!_isCacheableReadTool(functionName)) {
      return;
    }

    final decoded = _decodeJsonMap(result);
    if (decoded.containsKey('error')) {
      return;
    }

    _pruneExpiredReadCache();
    _readCache[_readCacheKey(functionName, args)] = _AiChatExecutorCacheEntry(
      result: result,
      createdAt: DateTime.now(),
    );

    if (_readCache.length <= _maxReadCacheEntries) {
      return;
    }

    final overflow = _readCache.length - _maxReadCacheEntries;
    final oldestEntries = _readCache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
    for (final entry in oldestEntries.take(overflow)) {
      _readCache.remove(entry.key);
    }
  }

  void _invalidateReadCache() {
    final prefix =
        '${chatScope.storageTypeKey}|${chatScope.normalizedScopeId}|';
    _readCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  void _pruneExpiredReadCache() {
    final now = DateTime.now();
    _readCache.removeWhere(
      (_, entry) => now.difference(entry.createdAt) > _readCacheTtl,
    );
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  Map<String, dynamic> _navigationAction(
    String route, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'route': route,
      if (arguments.isNotEmpty) 'arguments': arguments,
    };
  }

  String _navigationPayload({
    required String message,
    required String screen,
    required String route,
    Map<String, dynamic> arguments = const <String, dynamic>{},
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    return jsonEncode(<String, dynamic>{
      'success': true,
      'message': message,
      'screen': screen,
      'navigationAction': _navigationAction(route, arguments: arguments),
      ...extra,
    });
  }

  String _syncGuard() {
    if (!KsaTime.isSynced) {
      return _err('يتعذر تنفيذ العملية حالياً، جارٍ مزامنة البيانات...');
    }
    return '';
  }

  String _getAppBlueprint() {
    return jsonEncode(
      AiChatAppBlueprint.buildPayload(
        isOfficeMode: _isOfficeMode,
        canWrite: _canWrite,
        canReadAll: _canReadAll,
      ),
    );
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _coerceJsonObject(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isNotEmpty) return _decodeJsonMap(text);
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  bool _sameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<String> _getHomeDashboard() async {
    if (_isOfficeMode) {
      if (_canReadAll) {
        return _getOfficeDashboard();
      }
      return _err('هذا الحساب لا يملك صلاحية قراءة لوحة المكتب العامة من الدردشة.');
    }

    double receivables = 0;
    try {
      receivables = sumReceivablesFromContractsExact(includeArchived: false);
    } catch (_) {
      receivables = 0;
    }

    var overdueContracts = 0;
    final contractsBox = _contractsBox();
    if (contractsBox != null) {
      for (final contract in contractsBox.values) {
        if (contract.isArchived == true) continue;
        try {
          if (isContractOverdueForHome(contract)) {
            overdueContracts++;
          }
        } catch (_) {}
      }
    }

    final notificationsPayload =
        _decodeJsonMap(_getNotifications(const <String, dynamic>{'limit': 100}));
    final notificationItems = _asMapList(notificationsPayload['notifications']);
    final notificationsCount = _toIntValue(
      notificationsPayload['total'],
      notificationItems.length,
    );

    const dueKinds = <String>{
      'contract_due_soon',
      'contract_due_today',
      'contract_due_overdue',
    };
    final rentDuePreview = notificationItems
        .where((item) => dueKinds.contains((item['kind'] ?? '').toString()))
        .map((item) => <String, dynamic>{
              'kind': item['kind'],
              'title': item['title'],
              'tenantName': item['tenantName'],
              'serialNo': item['serialNo'],
              'anchorDate': item['anchorDate'],
              'notificationRef': item['notificationRef'],
              if (item.containsKey('daysLeft')) 'daysLeft': item['daysLeft'],
              if (item.containsKey('daysOverdue'))
                'daysOverdue': item['daysOverdue'],
            })
        .toList(growable: false)
      ..sort((a, b) {
        int priority(Map<String, dynamic> item) {
          switch ((item['kind'] ?? '').toString()) {
            case 'contract_due_overdue':
              return 0;
            case 'contract_due_today':
              return 1;
            default:
              return 2;
          }
        }

        final byPriority = priority(a).compareTo(priority(b));
        if (byPriority != 0) return byPriority;
        final aDate = _parseDate((a['anchorDate'] ?? '').toString()) ??
            _notificationDateOnly(KsaTime.now());
        final bDate = _parseDate((b['anchorDate'] ?? '').toString()) ??
            _notificationDateOnly(KsaTime.now());
        return aDate.compareTo(bDate);
      });

    return jsonEncode(<String, dynamic>{
      'screen': 'home',
      'title': 'الرئيسية',
      'cards': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'receivables',
          'title': 'إجمالي المستحقات',
          'amount': receivables,
          'formattedValue': '${receivables.toStringAsFixed(2)} ريال',
        },
        <String, dynamic>{
          'key': 'overdue_contracts',
          'title': 'المدفوعات المتأخرة',
          'count': overdueContracts,
          'targetScreen': 'contracts',
          'targetFilter': 'overdue',
        },
        <String, dynamic>{
          'key': 'notifications',
          'title': 'التنبيهات',
          'count': notificationsCount,
          'targetScreen': 'notifications',
        },
      ],
      'quickActions': const <Map<String, dynamic>>[
        <String, dynamic>{'label': 'العقارات', 'screen': 'properties'},
        <String, dynamic>{'label': 'العملاء', 'screen': 'tenants'},
        <String, dynamic>{'label': 'العقود', 'screen': 'contracts'},
        <String, dynamic>{'label': 'الخدمات', 'screen': 'maintenance'},
        <String, dynamic>{'label': 'السندات', 'screen': 'invoices'},
        <String, dynamic>{'label': 'التقارير', 'screen': 'reports'},
      ],
      'rentDueEntry': <String, dynamic>{
        'title': 'أقرب استحقاقات الإيجار',
        'targetScreen': 'contracts',
        'targetFilter': 'nearExpiry',
        'preview': rentDuePreview.take(5).toList(growable: false),
      },
    });
  }

  Future<List<Map<String, dynamic>>> _buildOfficeDashboardClientAlerts() async {
    final ref = _officeClientsRef();
    if (ref == null) return const <Map<String, dynamic>>[];

    final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
    final today = _officeKsaDateOnly(KsaTime.now());
    final alerts = <Map<String, dynamic>>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      if (_isOfficeStaff(data)) continue;
      if (data['subscriptionEnabled'] != true) continue;

      final clientSnapshot = <String, dynamic>{
        'name': data['name'],
        'email': data['email'],
        'clientUid': (data['clientUid'] ?? data['uid'] ?? doc.id).toString(),
        'createdAt': data['createdAt'],
        'subscriptionEnabled': data['subscriptionEnabled'],
        'subscriptionPrice': data['subscriptionPrice'],
        'subscriptionReminderDays': data['subscriptionReminderDays'],
      };
      final state = _buildOfficeClientSubscriptionState(clientSnapshot, data);
      final endDate = state['resolvedEndDate'] as DateTime?;
      if (endDate == null) continue;

      final reminderDays = (state['reminderDays'] as int?) ?? 1;
      final reminderDate = endDate.subtract(Duration(days: reminderDays));
      final expiredAt = endDate.add(const Duration(days: 1));
      final isReminderToday = _sameCalendarDay(today, reminderDate);
      final isExpiredToday = _sameCalendarDay(today, expiredAt);
      if (!isReminderToday && !isExpiredToday) continue;

      final clientName = (data['name'] ?? '').toString().trim().isNotEmpty
          ? (data['name'] ?? '').toString().trim()
          : (data['email'] ?? doc.id).toString();

      alerts.add(<String, dynamic>{
        'kind': isExpiredToday
            ? 'client_subscription_expired_today'
            : 'client_subscription_reminder',
        'clientName': clientName,
        'clientUid': (data['clientUid'] ?? data['uid'] ?? doc.id).toString(),
        'email': (data['email'] ?? '').toString(),
        'endDate': _fmtDate(endDate),
        'endDateIso': endDate.toIso8601String(),
        'title':
            isExpiredToday ? 'انتهى اشتراك عميل اليوم' : 'تنبيه اشتراك عميل',
        'message': isExpiredToday
            ? 'انتهى اشتراك العميل "$clientName" اليوم. تاريخ نهاية الاشتراك ${_fmtDate(endDate)}.'
            : 'سينتهي اشتراك العميل "$clientName" بعد $reminderDays يوم. تاريخ نهاية الاشتراك ${_fmtDate(endDate)}.',
        if (!isExpiredToday) 'reminderDays': reminderDays,
      });
    }

    alerts.sort((a, b) {
      int priority(Map<String, dynamic> item) {
        return (item['kind'] ?? '') == 'client_subscription_expired_today'
            ? 0
            : 1;
      }

      final byPriority = priority(a).compareTo(priority(b));
      if (byPriority != 0) return byPriority;
      final aDate = _parseDate((a['endDateIso'] ?? '').toString()) ?? today;
      final bDate = _parseDate((b['endDateIso'] ?? '').toString()) ?? today;
      return aDate.compareTo(bDate);
    });

    return alerts;
  }

  Future<Map<String, dynamic>?> _loadOfficeClientWorkspaceSummary(
    String clientUid,
  ) async {
    final normalizedUid = clientUid.trim();
    if (normalizedUid.isEmpty || normalizedUid == 'guest') return null;

    final properties = await _loadScopedActiveProperties(normalizedUid);
    final contracts = await _loadScopedActiveContracts(normalizedUid);
    final invoices = await _loadScopedInvoices(normalizedUid);
    if (properties.isEmpty && contracts.isEmpty && invoices.isEmpty) {
      return null;
    }

    final topLevelProperties = _topLevelProperties(properties);
    final buildings = topLevelProperties
        .where((property) => property.type == PropertyType.building)
        .toList(growable: false);
    final occupiedTopLevel = topLevelProperties
        .where((property) => _isTopLevelPropertyOccupied(property, properties))
        .length;
    final registeredBuildingUnits =
        properties.where((property) => _isBuildingUnitProperty(property)).length;
    final configuredBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _configuredUnitsForBuilding(building, properties),
    );
    final occupiedBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _occupiedUnitsForBuilding(building, properties),
    );
    final vacantBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _vacantUnitsForBuilding(building, properties),
    );

    var activeContracts = 0;
    var endedContracts = 0;
    var terminatedContracts = 0;
    var expiringContracts = 0;
    var totalContractAmount = 0.0;
    var paidContractAmount = 0.0;
    var remainingContractAmount = 0.0;
    var totalInstallments = 0;
    var overdueInstallments = 0;

    final contractsPreview = contracts
        .map((contract) {
          final status = _contractStatusLabel(contract);
          if (status == 'نشط') {
            activeContracts++;
          } else if (status == 'منهي') {
            terminatedContracts++;
          } else {
            endedContracts++;
          }
          if (_contractExpiringSoon(contract)) {
            expiringContracts++;
          }

          final linkedInvoices = _linkedContractInvoices(contract.id, invoices);
          final metrics = _contractInvoiceMetrics(linkedInvoices);
          totalContractAmount += contract.totalAmount;
          paidContractAmount +=
              ((metrics['paidAmount'] as num?) ?? 0).toDouble();
          remainingContractAmount +=
              ((metrics['remainingTotal'] as num?) ?? 0).toDouble();
          totalInstallments += ((metrics['totalInstallments'] as num?) ?? 0).toInt();
          overdueInstallments +=
              ((metrics['overdueInstallments'] as num?) ?? 0).toInt();
          return _contractPortfolioItem(contract, invoices);
        })
        .toList(growable: false);

    contractsPreview.sort((a, b) {
      final aRemaining = ((a['remainingAmount'] as num?) ?? 0).toDouble();
      final bRemaining = ((b['remainingAmount'] as num?) ?? 0).toDouble();
      return bRemaining.compareTo(aRemaining);
    });

    return <String, dynamic>{
      'workspaceDataAvailable': true,
      'topLevelProperties': topLevelProperties.length,
      'occupiedTopLevelProperties': occupiedTopLevel,
      'vacantTopLevelProperties': topLevelProperties.length - occupiedTopLevel,
      'buildings': buildings.length,
      'standaloneProperties': topLevelProperties.length - buildings.length,
      'registeredBuildingUnits': registeredBuildingUnits,
      'configuredBuildingUnits': configuredBuildingUnits,
      'occupiedBuildingUnits': occupiedBuildingUnits,
      'vacantBuildingUnits': vacantBuildingUnits,
      'totalContracts': contracts.length,
      'activeContracts': activeContracts,
      'endedContracts': endedContracts,
      'terminatedContracts': terminatedContracts,
      'expiringContracts': expiringContracts,
      'totalContractAmount': double.parse(totalContractAmount.toStringAsFixed(2)),
      'paidContractAmount': double.parse(paidContractAmount.toStringAsFixed(2)),
      'remainingContractAmount':
          double.parse(remainingContractAmount.toStringAsFixed(2)),
      'totalInstallments': totalInstallments,
      'overdueInstallments': overdueInstallments,
      'propertiesPreview': topLevelProperties
          .take(5)
          .map((property) => _topLevelPropertyListItemV2(property, properties))
          .toList(growable: false),
      'contractsPreview': contractsPreview.take(5).toList(growable: false),
      'semanticSummary':
          'له ${topLevelProperties.length} عقار رئيسي و${contracts.length} عقد، والمتبقي في العقود ${remainingContractAmount.toStringAsFixed(2)} ريال.',
    };
  }

  Future<String> _getOfficeDashboard() async {
    if (_officeClientsRef() == null) return _err('Ù„Ø§ ÙŠÙ…ÙƒÙ† Ø§Ù„ÙˆØµÙˆÙ„ Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…ÙƒØªØ¨');

    try {
      final clients = await _loadMergedOfficeClients();
      final users = await _loadOfficeUsers();
      final clientPortfolioSummaries = <Map<String, dynamic>>[];
      for (final client in clients) {
        final clientUid = (client['clientUid'] ?? '').toString().trim();
        if (clientUid.isEmpty) continue;
        final workspaceSummary =
            await _loadOfficeClientWorkspaceSummary(clientUid);
        if (workspaceSummary == null) continue;
        clientPortfolioSummaries.add(<String, dynamic>{
          'clientName': client['name'] ?? '',
          'clientUid': clientUid,
          ...workspaceSummary,
        });
      }

      var totalClients = 0;
      var blockedClients = 0;
      var activeClients = 0;
      var withSubscription = 0;
      var pendingSyncClients = 0;

      for (final client in clients) {
        totalClients++;
        if (client['blocked'] == true) {
          blockedClients++;
        } else {
          activeClients++;
        }
        if (client['subscriptionEnabled'] == true) {
          withSubscription++;
        }
        if (client['pendingSync'] == true) {
          pendingSyncClients++;
        }
      }

      var blockedUsers = 0;
      var fullPermissionUsers = 0;
      var viewPermissionUsers = 0;
      for (final user in users) {
        if (user['blocked'] == true) blockedUsers++;
        if ((user['permission'] ?? 'view') == 'full') {
          fullPermissionUsers++;
        } else {
          viewPermissionUsers++;
        }
      }

      final workspaceUid = effectiveUid().trim();
      final officeDoc = workspaceUid.isEmpty || workspaceUid == 'guest'
          ? const <String, dynamic>{}
          : await _readDocMap(
              FirebaseFirestore.instance.collection('users').doc(workspaceUid),
            );
      final officeEndDate = _officeClientDateOnlyValue(
        officeDoc,
        const <String>['end_date_ksa', 'subscription_end'],
      );
      final officeAlert = SubscriptionAlerts.compute(endAt: officeEndDate);
      final clientAlerts = await _buildOfficeDashboardClientAlerts();

      final clientsWithWorkspaceData = clientPortfolioSummaries.length;
      final clientsWithoutWorkspaceData =
          totalClients - clientsWithWorkspaceData;
      var totalOfficeProperties = 0;
      var totalOfficeBuildings = 0;
      var totalOfficeStandaloneProperties = 0;
      var totalRegisteredBuildingUnits = 0;
      var totalConfiguredBuildingUnits = 0;
      var totalOccupiedBuildingUnits = 0;
      var totalVacantBuildingUnits = 0;
      var totalOfficeContracts = 0;
      var totalActiveContracts = 0;
      var totalEndedContracts = 0;
      var totalTerminatedContracts = 0;
      var totalExpiringContracts = 0;
      var totalRemainingContractAmount = 0.0;

      for (final item in clientPortfolioSummaries) {
        totalOfficeProperties +=
            ((item['topLevelProperties'] as num?) ?? 0).toInt();
        totalOfficeBuildings += ((item['buildings'] as num?) ?? 0).toInt();
        totalOfficeStandaloneProperties +=
            ((item['standaloneProperties'] as num?) ?? 0).toInt();
        totalRegisteredBuildingUnits +=
            ((item['registeredBuildingUnits'] as num?) ?? 0).toInt();
        totalConfiguredBuildingUnits +=
            ((item['configuredBuildingUnits'] as num?) ?? 0).toInt();
        totalOccupiedBuildingUnits +=
            ((item['occupiedBuildingUnits'] as num?) ?? 0).toInt();
        totalVacantBuildingUnits +=
            ((item['vacantBuildingUnits'] as num?) ?? 0).toInt();
        totalOfficeContracts += ((item['totalContracts'] as num?) ?? 0).toInt();
        totalActiveContracts += ((item['activeContracts'] as num?) ?? 0).toInt();
        totalEndedContracts += ((item['endedContracts'] as num?) ?? 0).toInt();
        totalTerminatedContracts +=
            ((item['terminatedContracts'] as num?) ?? 0).toInt();
        totalExpiringContracts +=
            ((item['expiringContracts'] as num?) ?? 0).toInt();
        totalRemainingContractAmount +=
            ((item['remainingContractAmount'] as num?) ?? 0).toDouble();
      }

      clientPortfolioSummaries.sort((a, b) {
        final aRemaining =
            ((a['remainingContractAmount'] as num?) ?? 0).toDouble();
        final bRemaining =
            ((b['remainingContractAmount'] as num?) ?? 0).toDouble();
        return bRemaining.compareTo(aRemaining);
      });

      final alerts = <Map<String, dynamic>>[
        if (officeAlert != null)
          <String, dynamic>{
            'kind': 'office_subscription',
            'title': officeAlert.title,
            'message': officeAlert.body,
            'endDate': _fmtDate(officeAlert.endAt),
            'endDateIso': officeAlert.endAt.toIso8601String(),
          },
        ...clientAlerts,
      ];

      return jsonEncode(<String, dynamic>{
        'screen': 'office',
        'title': 'لوحة المكتب',
        'shell': const <String, dynamic>{
          'hasDrawer': true,
          'hasNotificationsBell': true,
          'embeddedBodyScreen': 'office_clients',
        },
        'clientSummary': <String, dynamic>{
          'totalClients': totalClients,
          'activeClients': activeClients,
          'blockedClients': blockedClients,
          'withSubscription': withSubscription,
          'pendingSyncClients': pendingSyncClients,
        },
        'userSummary': <String, dynamic>{
          'totalUsers': users.length,
          'activeUsers': users.length - blockedUsers,
          'blockedUsers': blockedUsers,
          'fullPermissionUsers': fullPermissionUsers,
          'viewPermissionUsers': viewPermissionUsers,
        },
        'notifications': <String, dynamic>{
          'badgeCount': alerts.length,
          'officeSubscriptionAlerts': officeAlert == null ? 0 : 1,
          'clientSubscriptionAlerts': clientAlerts.length,
          'alerts': alerts.take(5).toList(growable: false),
        },
        'portfolioSummary': <String, dynamic>{
          'clientsWithWorkspaceData': clientsWithWorkspaceData,
          'clientsWithoutWorkspaceData': clientsWithoutWorkspaceData,
          'topLevelProperties': totalOfficeProperties,
          'buildings': totalOfficeBuildings,
          'standaloneProperties': totalOfficeStandaloneProperties,
          'registeredBuildingUnits': totalRegisteredBuildingUnits,
          'configuredBuildingUnits': totalConfiguredBuildingUnits,
          'occupiedBuildingUnits': totalOccupiedBuildingUnits,
          'vacantBuildingUnits': totalVacantBuildingUnits,
          'totalContracts': totalOfficeContracts,
          'activeContracts': totalActiveContracts,
          'endedContracts': totalEndedContracts,
          'terminatedContracts': totalTerminatedContracts,
          'expiringContracts': totalExpiringContracts,
          'remainingContractAmount':
              double.parse(totalRemainingContractAmount.toStringAsFixed(2)),
          'semanticSummary': clientsWithWorkspaceData == 0
              ? 'لا توجد حاليًا مساحات عمل عملاء متاحة محليًا لحساب إجمالي العقارات والعقود.'
              : 'تم احتساب إجمالي العقارات والعقود من ${clientsWithWorkspaceData.toString()} عميل/عملاء داخل المكتب.',
        },
        'quickActions': const <Map<String, dynamic>>[
          <String, dynamic>{'label': 'عملاء المكتب', 'screen': 'office_clients'},
          <String, dynamic>{'label': 'مستخدمي المكتب', 'screen': 'office_users'},
          <String, dynamic>{'label': 'سجل النشاط', 'screen': 'activity_log'},
          <String, dynamic>{'label': 'التنبيهات', 'screen': 'notifications'},
        ],
        'latestClientsPreview': clients
            .take(5)
            .map((client) => <String, dynamic>{
                  'name': client['name'] ?? '',
                  'email': client['email'] ?? '',
                  'clientUid': client['clientUid'] ?? '',
                  'blocked': client['blocked'] == true,
                  'subscriptionEnabled': client['subscriptionEnabled'] == true,
                  'pendingSync': client['pendingSync'] == true,
                  'isLocal': client['isLocal'] == true,
                })
            .toList(growable: false),
        'latestUsersPreview': users
            .take(5)
            .map((user) => <String, dynamic>{
                  'name': user['name'] ?? '',
                  'email': user['email'] ?? '',
                  'uid': user['uid'] ?? '',
                  'permission': user['permission'] ?? 'view',
                  'blocked': user['blocked'] == true,
                })
            .toList(growable: false),
        'clientPortfolioPreview': clientPortfolioSummaries
            .take(5)
            .map((item) => <String, dynamic>{
                  'clientName': item['clientName'] ?? '',
                  'clientUid': item['clientUid'] ?? '',
                  'topLevelProperties': item['topLevelProperties'] ?? 0,
                  'buildings': item['buildings'] ?? 0,
                  'configuredBuildingUnits':
                      item['configuredBuildingUnits'] ?? 0,
                  'occupiedBuildingUnits':
                      item['occupiedBuildingUnits'] ?? 0,
                  'vacantBuildingUnits': item['vacantBuildingUnits'] ?? 0,
                  'totalContracts': item['totalContracts'] ?? 0,
                  'activeContracts': item['activeContracts'] ?? 0,
                  'remainingContractAmount':
                      item['remainingContractAmount'] ?? 0,
                  'semanticSummary': item['semanticSummary'] ?? '',
                })
            .toList(growable: false),
      });
    } catch (e) {
      return _err('تعذر جلب لوحة المكتب: $e');
    }
  }

  bool get _isOfficeMode => chatScope.usesOfficeModeForArchitecture;

  bool get _canWrite => AiChatPermissions.canExecuteWriteOperations(userRole);

  bool get _canReadAll =>
      AiChatPermissions.canReadAllClients(userRole) &&
      chatScope.allowsOfficeWideData;

  Box<Property>? _propertiesBox() {
    final name = boxName(kPropertiesBox);
    return Hive.isBoxOpen(name) ? Hive.box<Property>(name) : null;
  }

  Box<Tenant>? _tenantsBox() {
    final name = boxName(kTenantsBox);
    return Hive.isBoxOpen(name) ? Hive.box<Tenant>(name) : null;
  }

  Box<Contract>? _contractsBox() {
    final name = boxName(kContractsBox);
    return Hive.isBoxOpen(name) ? Hive.box<Contract>(name) : null;
  }

  Box<Invoice>? _invoicesBox() {
    final name = boxName(kInvoicesBox);
    return Hive.isBoxOpen(name) ? Hive.box<Invoice>(name) : null;
  }

  Box<MaintenanceRequest>? _maintenanceBox() {
    final name = boxName(kMaintenanceBox);
    return Hive.isBoxOpen(name) ? Hive.box<MaintenanceRequest>(name) : null;
  }

  String _scopedBoxName(String base, String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return base;
    return '${base}_$normalized';
  }

  Future<Box<T>?> _openScopedBox<T>(String base, String uid) async {
    final normalized = uid.trim();
    if (normalized.isEmpty || normalized == 'guest') return null;
    final name = _scopedBoxName(base, normalized);
    try {
      if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
      if (!await Hive.boxExists(name)) return null;
      return await Hive.openBox<T>(name);
    } catch (_) {
      return null;
    }
  }

  Future<List<Property>> _loadScopedActiveProperties(String uid) async {
    final box = await _openScopedBox<Property>(kPropertiesBox, uid);
    if (box == null) return const <Property>[];
    return box.values
        .where((property) => property.isArchived != true)
        .toList(growable: false);
  }

  Future<List<Contract>> _loadScopedActiveContracts(String uid) async {
    final box = await _openScopedBox<Contract>(kContractsBox, uid);
    if (box == null) return const <Contract>[];
    return box.values
        .where((contract) => contract.isArchived != true)
        .toList(growable: false);
  }

  Future<List<Invoice>> _loadScopedInvoices(String uid) async {
    final box = await _openScopedBox<Invoice>(kInvoicesBox, uid);
    if (box == null) return const <Invoice>[];
    return box.values
        .where((invoice) => invoice.isArchived != true)
        .toList(growable: false);
  }

  Tenant? _findTenant(String query) {
    final box = _tenantsBox();
    if (box == null) return null;
    final q = query.trim().toLowerCase();
    return box.values.cast<Tenant>().where((t) {
      return t.fullName.toLowerCase().contains(q) ||
          t.nationalId.contains(q) ||
          t.phone.contains(q);
    }).firstOrNull;
  }

  Property? _findProperty(String query) {
    final box = _propertiesBox();
    if (box == null) return null;
    final q = query.trim().toLowerCase();
    return box.values
        .cast<Property>()
        .where((p) => p.name.toLowerCase().contains(q))
        .firstOrNull;
  }

  MaintenanceRequest? _findMaintenance(String query) {
    final box = _maintenanceBox();
    if (box == null) return null;
    final q = query.trim().toLowerCase();
    return box.values.where((m) {
      final d = m as dynamic;
      final title = (d.title ?? '').toString().toLowerCase();
      final serial = (d.serialNo ?? '').toString().toLowerCase();
      return title.contains(q) || serial.contains(q);
    }).firstOrNull;
  }

  Contract? _findContract(String query) {
    final box = _contractsBox();
    if (box == null) return null;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    return box.values.where((contract) {
      final serial = (contract.serialNo ?? '').trim().toLowerCase();
      final tenant = (contract.tenantSnapshot?['fullName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final property = (contract.propertySnapshot?['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return serial.contains(q) || tenant.contains(q) || property.contains(q);
    }).firstOrNull;
  }

  bool _invoiceNoteContainsMarker(dynamic invoice, String marker) {
    try {
      final note = invoice is Map
          ? ((invoice['note'] ?? invoice['notes'])?.toString().toLowerCase() ?? '')
          : ((invoice as dynamic).note?.toString().toLowerCase() ?? '');
      return note.contains(marker.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  bool _isOfficeCommissionInvoice(dynamic invoice) {
    return _invoiceNoteContainsMarker(invoice, '[office_commission]');
  }

  String _contractStatusLabel(Contract contract) {
    if (contract.isTerminated) return 'منهي';
    if (contract.endDate.isBefore(KsaTime.now())) return 'منتهي';
    return 'نشط';
  }

  String _contractTermLabel(ContractTerm term) {
    switch (term) {
      case ContractTerm.daily:
        return 'يومي';
      case ContractTerm.monthly:
        return 'شهري';
      case ContractTerm.quarterly:
        return 'ربع سنوي';
      case ContractTerm.semiAnnual:
        return 'نصف سنوي';
      case ContractTerm.annual:
        return 'سنوي';
    }
  }

  String _paymentCycleLabel(PaymentCycle cycle) {
    switch (cycle) {
      case PaymentCycle.monthly:
        return 'شهري';
      case PaymentCycle.quarterly:
        return 'ربع سنوي';
      case PaymentCycle.semiAnnual:
        return 'نصف سنوي';
      case PaymentCycle.annual:
        return 'سنوي';
    }
  }

  Future<int?> _resolveSavedDailyContractCheckoutHour() async {
    dynamic localValue(String boxName) {
      try {
        if (!Hive.isBoxOpen(boxName)) return null;
        return Hive.box(boxName).get('daily_contract_end_hour');
      } catch (_) {
        return null;
      }
    }

    final local = _normalizeHour24(
      localValue('sessionBox') ?? localValue('settingsBox'),
    );
    if (local != null) return local;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    Future<int?> readPrefs(String uid) async {
      final normalizedUid = uid.trim();
      if (normalizedUid.isEmpty || normalizedUid == 'guest') return null;
      final prefs = await _readDocMap(
        FirebaseFirestore.instance.collection('user_prefs').doc(normalizedUid),
      );
      return _normalizeHour24(prefs['daily_contract_end_hour']);
    }

    final workspaceUid = effectiveUid().trim();
    final workspaceHour = await readPrefs(workspaceUid);
    if (workspaceHour != null) return workspaceHour;

    return readPrefs(user.uid);
  }

  String _tenantUpsertError(
    TenantUpsertResult result, {
    String? clientType,
    String operation = 'add_client_record',
  }) {
    final payload = <String, dynamic>{};
    final normalizedType = TenantRecordService.normalizeClientType(clientType);
    final onlyAttachments = result.missingFields.isNotEmpty &&
        result.missingFields.every((issue) => issue.field == 'attachmentPaths');
    final entryOptions = _entryOptionsForOperation(operation);

    if (onlyAttachments) {
      payload['error'] =
          'المرفقات مطلوبة لهذه العملية. يمكنك رفعها هنا في الدردشة حتى 3 ملفات، أو اختيار فتح شاشة الإضافة لإكمالها من الشاشة.';
      payload['requiresScreenCompletion'] = true;
      payload['suggestedScreen'] = 'tenants_new';
    } else {
      payload['error'] =
          result.firstIssueMessage ?? 'تعذر إكمال العملية بسبب بيانات غير صالحة.';
    }

    payload['clientType'] = normalizedType;
    payload['clientTypeLabel'] = TenantRecordService.clientTypeLabel(
      normalizedType,
    );
    payload['requiredFieldsByType'] =
        TenantRecordService.requiredFieldDescriptors(normalizedType);
    payload['nextStep'] = onlyAttachments
        ? 'upload_attachments_or_open_entry_screen'
        : 'collect_missing_or_invalid_fields_then_retry';
    payload['operation'] = operation;

    if (entryOptions.isNotEmpty) {
      payload['entryOptions'] = entryOptions;
      payload['preferredEntryMode'] = 'screen';
      payload['chatCollectionMode'] = _chatCollectionModePayload();
    }
    if (onlyAttachments) {
      payload['chatAttachmentSupport'] = _chatAttachmentSupportPayload();
    }

    if (result.missingFields.isNotEmpty) {
      payload['missingFields'] = result.missingFields
          .map((issue) => issue.toJson())
          .toList(growable: false);
    }

    if ((result.errorMessage ?? '').trim().isNotEmpty) {
      payload['validationError'] = result.errorMessage!.trim();
    }

    return jsonEncode(payload);
  }

  String _domainValidationError(
    AiChatValidationResult<dynamic> result, {
    List<Map<String, dynamic>>? requiredFields,
    String? nextStep,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    final operation = (extra['operation'] ?? '').toString().trim();
    final entryOptions = _entryOptionsForOperation(operation);
    final supportsChatAttachments = _hasAttachmentRequirement(
      operation: operation,
      missingFields: result.missingFields,
      requiredFields: requiredFields,
    );
    final payload = <String, dynamic>{
      'error':
          result.firstIssueMessage ?? 'تعذر إكمال العملية بسبب بيانات غير صالحة.',
      ...extra,
    };

    if (result.requiresScreenCompletion) {
      payload['requiresScreenCompletion'] = true;
    }
    if ((result.suggestedScreen ?? '').trim().isNotEmpty) {
      payload['suggestedScreen'] = result.suggestedScreen;
    }
    if (result.missingFields.isNotEmpty) {
      payload['missingFields'] = result.missingFields
          .map((issue) => issue.toJson())
          .toList(growable: false);
    }
    if ((result.errorMessage ?? '').trim().isNotEmpty) {
      payload['validationError'] = result.errorMessage!.trim();
    }
    if (requiredFields != null && requiredFields.isNotEmpty) {
      payload['requiredFields'] = requiredFields;
    }
    if ((nextStep ?? '').trim().isNotEmpty) {
      payload['nextStep'] = nextStep;
    }
    if (entryOptions.isNotEmpty) {
      payload['entryOptions'] = entryOptions;
      payload['preferredEntryMode'] = 'screen';
      payload['chatCollectionMode'] = _chatCollectionModePayload();
    }
    if (supportsChatAttachments) {
      payload['chatAttachmentSupport'] = _chatAttachmentSupportPayload();
    }

    return jsonEncode(payload);
  }

  Map<String, dynamic> _chatCollectionModePayload() {
    return const <String, dynamic>{
      'style': 'single_question',
      'requiredLabel': 'إلزامي',
      'optionalLabel': 'اختياري',
      'optionalSkipHint': 'يمكنك قول: لا أريده',
    };
  }

  Map<String, dynamic> _chatAttachmentSupportPayload() {
    return const <String, dynamic>{
      'enabled': true,
      'maxFiles': 3,
      'instruction': 'يمكنك رفع المرفقات هنا في الدردشة حتى 3 ملفات.',
    };
  }

  List<Map<String, dynamic>> _entryOptionsForOperation(String operation) {
    switch (operation) {
      case 'add_tenant':
      case 'add_client_record':
        return _buildEntryOptions(
          screenTool: 'open_tenant_entry',
          screenLabel: 'فتح شاشة إضافة عميل',
        );
      case 'add_property':
        return _buildEntryOptions(
          screenTool: 'open_property_entry',
          screenLabel: 'فتح شاشة إضافة عقار',
        );
      case 'create_contract':
        return _buildEntryOptions(
          screenTool: 'open_contract_entry',
          screenLabel: 'فتح شاشة إضافة عقد',
        );
      case 'create_maintenance_request':
        return _buildEntryOptions(
          screenTool: 'open_maintenance_entry',
          screenLabel: 'فتح شاشة إضافة صيانة',
        );
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _buildEntryOptions({
    required String screenTool,
    required String screenLabel,
  }) {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'mode': 'screen',
        'label': screenLabel,
        'description': 'هذا أسرع ومناسب للحالات التي تحتوي على عدة حقول أو مرفقات.',
        'tool': screenTool,
        'preferred': true,
      },
      <String, dynamic>{
        'mode': 'chat',
        'label': 'الإضافة من الدردشة',
        'description': 'سأسألك سؤالًا واحدًا في كل مرة حتى نكمل البيانات.',
        'preferred': false,
      },
    ];
  }

  bool _hasAttachmentRequirement({
    required String operation,
    required Iterable<dynamic> missingFields,
    List<Map<String, dynamic>>? requiredFields,
  }) {
    if (missingFields.any((issue) => _issueContainsAttachmentField(issue))) {
      return true;
    }
    if (requiredFields != null &&
        requiredFields.any((issue) => _issueContainsAttachmentField(issue))) {
      return true;
    }
    switch (operation) {
      case 'add_tenant':
      case 'add_client_record':
      case 'add_property':
      case 'edit_property':
      case 'create_contract':
      case 'create_manual_voucher':
      case 'create_maintenance_request':
        return true;
      default:
        return false;
    }
  }

  bool _issueContainsAttachmentField(dynamic issue) {
    if (issue is TenantValidationIssue) {
      return _isAttachmentFieldName(issue.field);
    }
    if (issue is AiChatValidationIssue) {
      return _isAttachmentFieldName(issue.field);
    }
    if (issue is Map<String, dynamic>) {
      return _isAttachmentFieldName((issue['field'] ?? '').toString());
    }
    if (issue is Map) {
      return _isAttachmentFieldName((issue['field'] ?? '').toString());
    }
    return false;
  }

  bool _isAttachmentFieldName(String field) {
    final normalized = field.trim();
    return normalized == 'attachmentPaths' ||
        normalized == 'documentAttachmentPaths';
  }

  Property? _findPropertyById(String id) {
    final box = _propertiesBox();
    if (box == null) return null;
    return box.values.cast<Property>().where((p) => p.id == id).firstOrNull;
  }

  Tenant? _findTenantById(String id) {
    final box = _tenantsBox();
    if (box == null) return null;
    return box.values.cast<Tenant>().where((t) => t.id == id).firstOrNull;
  }

  Property? _parentBuildingFor(Property property) {
    final parentId = (property.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return null;
    return _findPropertyById(parentId);
  }

  bool _isPropertyOrParentArchived(Property property) {
    if (property.isArchived == true) return true;
    final parent = _parentBuildingFor(property);
    return parent?.isArchived == true;
  }

  String _archivedPropertyActionError(
    Property property, {
    required bool forService,
  }) {
    final parent = _parentBuildingFor(property);
    final selfArchived = property.isArchived == true;
    final parentArchived = parent?.isArchived == true;
    final entityLabel =
        property.parentBuildingId != null ? 'هذه الوحدة' : 'هذا العقار';
    final usageContext = forService ? 'الخدمات' : 'التأجير';
    final error = parentArchived && !selfArchived && property.parentBuildingId != null
        ? 'هذه الوحدة تابعة لعمارة مؤرشفة، لذلك لا يمكن استخدامها في $usageContext قبل فك أرشفة العمارة أولًا.'
        : '$entityLabel مؤرشف حاليًا، لذلك لا يمكن استخدامه في $usageContext قبل فك الأرشفة.';
    return jsonEncode(<String, dynamic>{
      'error': error,
      'code': 'archived_property_blocked',
      'requiresScreenCompletion': true,
      'suggestedScreen': 'properties',
      'nextStep': 'unarchive_property_then_retry',
      'propertyName': property.name,
      'parentBuildingName': parent?.name,
    });
  }

  int _existingUnitsCountForBuilding(String buildingId) {
    final box = _propertiesBox();
    if (box == null) return 0;
    return box.values
        .cast<Property>()
        .where((item) => item.parentBuildingId == buildingId)
        .length;
  }

  bool _hasActiveContractForPropertyId(String propertyId) {
    final box = _contractsBox();
    if (box == null) return false;
    for (final contract in box.values) {
      if (contract.propertyId != propertyId) continue;
      if (contract.isArchived) continue;
      if (contract.isActiveNow) return true;
    }
    return false;
  }

  bool _hasActiveContract(Property property) {
    if (_hasActiveContractForPropertyId(property.id)) return true;
    if (property.type != PropertyType.building && property.occupiedUnits > 0) {
      return true;
    }

    if (property.type == PropertyType.building) {
      if (property.rentalMode != RentalMode.perUnit && property.occupiedUnits > 0) {
        return true;
      }
      final box = _propertiesBox();
      if (box == null) return false;
      for (final unit
          in box.values.where((item) => item.parentBuildingId == property.id)) {
        if (_hasActiveContractForPropertyId(unit.id) || unit.occupiedUnits > 0) {
          return true;
        }
      }
    }
    return false;
  }

  String _archiveBlockedMessageForProperty(Property property) {
    if (property.type == PropertyType.building &&
        property.rentalMode == RentalMode.perUnit) {
      return 'هذه العمارة تحتوي على وحدة أو أكثر مرتبطة بعقد نشط أو إشغال قائم، لذلك لا يمكن أرشفتها الآن.';
    }
    return 'العقار مرتبط بعقد نشط أو إشغال قائم، لذلك لا يمكن أرشفته الآن.';
  }

  bool _isPropertyAvailableForContract(Property property) {
    if (property.parentBuildingId != null) return property.occupiedUnits == 0;
    if (property.type == PropertyType.building) {
      if (property.rentalMode == RentalMode.perUnit) return false;
      return property.occupiedUnits == 0;
    }
    return property.occupiedUnits == 0;
  }

  Future<void> _occupyProperty(Property property) async {
    if (property.parentBuildingId != null) {
      property.occupiedUnits = 1;
      await property.save();
      await _recalcBuildingOccupiedUnits(property.parentBuildingId!);
      return;
    }
    property.occupiedUnits = 1;
    await property.save();
  }

  Future<void> _releaseProperty(Property property) async {
    if (property.parentBuildingId != null) {
      property.occupiedUnits = 0;
      await property.save();
      await _recalcBuildingOccupiedUnits(property.parentBuildingId!);
      return;
    }
    property.occupiedUnits = 0;
    await property.save();
  }

  Future<void> _recalcBuildingOccupiedUnits(String buildingId) async {
    final box = _propertiesBox();
    if (box == null) return;
    final count = box.values
        .cast<Property>()
        .where((item) => item.parentBuildingId == buildingId)
        .where((item) => item.occupiedUnits > 0)
        .length;
    final building = box.values
        .cast<Property>()
        .where((item) => item.id == buildingId)
        .firstOrNull;
    if (building == null) return;
    building.occupiedUnits = count;
    await building.save();
  }

  Future<void> _incrementTenantActiveContracts(String tenantId) async {
    final tenant = _findTenantById(tenantId);
    if (tenant == null) return;
    tenant.activeContractsCount += 1;
    tenant.updatedAt = KsaTime.now();
    await tenant.save();
  }

  Future<void> _decrementTenantActiveContracts(String tenantId) async {
    final tenant = _findTenantById(tenantId);
    if (tenant == null || tenant.activeContractsCount <= 0) return;
    tenant.activeContractsCount -= 1;
    tenant.updatedAt = KsaTime.now();
    await tenant.save();
  }

  Tenant? _findServiceProvider(String query) {
    final box = _tenantsBox();
    if (box == null) return null;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    return box.values.cast<Tenant>().where((tenant) {
      if (tenant.isArchived == true) return false;
      if (tenant.clientType != TenantRecordService.clientTypeServiceProvider) {
        return false;
      }
      return tenant.fullName.toLowerCase().contains(q) ||
          tenant.phone.contains(q) ||
          (tenant.serviceSpecialization ?? '').toLowerCase().contains(q);
    }).firstOrNull;
  }

  String _periodicConfigKey(String propertyId, String type) => '$propertyId::$type';

  Map<String, String> _parsePropertySpec(String? description) {
    final text = (description ?? '').trim();
    if (text.isEmpty) return const <String, String>{};
    final start = text.indexOf('[[SPEC]]');
    final end = text.indexOf('[[/SPEC]]');
    if (start == -1 || end == -1 || end <= start) {
      return const <String, String>{};
    }
    final body = text.substring(start + 8, end).trim();
    final result = <String, String>{};
    for (final line in body.split('\n')) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  String _extractFreePropertyDescription(String? description) {
    final text = (description ?? '').trim();
    if (text.isEmpty) return '';
    final start = text.indexOf('[[SPEC]]');
    final end = text.indexOf('[[/SPEC]]');
    if (start == -1 || end == -1 || end <= start) return text;
    return text.substring(end + 9).trim();
  }

  int? _propertySpecInt(Map<String, String> spec, String key) {
    return int.tryParse((spec[key] ?? '').trim());
  }

  bool? _propertySpecFurnished(Map<String, String> spec) {
    final value = (spec['المفروشات'] ?? '').trim();
    if (value.isEmpty) return null;
    if (value.contains('غير')) return false;
    if (value.contains('مفروش')) return true;
    return null;
  }

  Map<String, dynamic> _buildTenantSnapshot(Tenant tenant) {
    return <String, dynamic>{
      'id': tenant.id,
      'fullName': tenant.fullName,
      'phone': tenant.phone,
      'nationalId': tenant.nationalId,
      'email': tenant.email,
      'clientType': tenant.clientType,
      'companyName': tenant.companyName,
      'serviceSpecialization': tenant.serviceSpecialization,
      'isArchived': tenant.isArchived,
      'isBlacklisted': tenant.isBlacklisted,
    };
  }

  Map<String, dynamic> _buildPropertySnapshot(Property property) {
    final documentPaths = <String>{
      ...?property.documentAttachmentPaths,
      if ((property.documentAttachmentPath ?? '').trim().isNotEmpty)
        property.documentAttachmentPath!.trim(),
    }.toList(growable: false);

    return <String, dynamic>{
      'id': property.id,
      'name': property.name,
      'type': property.type.name,
      'typeLabel': property.type.label,
      'address': property.address,
      'price': property.price,
      'currency': property.currency,
      'rooms': property.rooms,
      'area': property.area,
      'floors': property.floors,
      'totalUnits': property.totalUnits,
      'occupiedUnits': property.occupiedUnits,
      'rentalMode': property.rentalMode?.name,
      'rentalModeLabel': property.rentalMode?.label,
      'parentBuildingId': property.parentBuildingId,
      'description': property.description,
      'documentType': property.documentType,
      'documentNumber': property.documentNumber,
      'documentDate':
          property.documentDate == null ? null : _fmtDate(property.documentDate!),
      'documentAttachmentPaths': documentPaths,
      'isArchived': property.isArchived,
    };
  }

  List<Property> _activePropertiesList() {
    final box = _propertiesBox();
    if (box == null) return const <Property>[];
    return box.values.where((item) => item.isArchived != true).toList(
          growable: false,
        );
  }

  bool _isBuildingUnitProperty(Property property) {
    return (property.parentBuildingId ?? '').trim().isNotEmpty;
  }

  List<Property> _topLevelProperties(List<Property> properties) {
    return properties
        .where((property) => !_isBuildingUnitProperty(property))
        .toList(growable: false);
  }

  List<Property> _buildingUnitsFor(
    Property building,
    List<Property> properties,
  ) {
    final buildingId = building.id.trim();
    if (buildingId.isEmpty) return const <Property>[];
    return properties
        .where(
          (property) =>
              (property.parentBuildingId ?? '').trim() == buildingId,
        )
        .toList(growable: false);
  }

  bool _isPerUnitBuilding(Property property) {
    return property.type == PropertyType.building &&
        property.rentalMode == RentalMode.perUnit;
  }

  int _registeredUnitsForBuilding(
    Property building,
    List<Property> properties,
  ) {
    return _buildingUnitsFor(building, properties).length;
  }

  int _configuredUnitsForBuilding(
    Property building,
    List<Property> properties,
  ) {
    final registeredUnits = _registeredUnitsForBuilding(building, properties);
    if (building.totalUnits > registeredUnits) return building.totalUnits;
    return registeredUnits;
  }

  int _occupiedUnitsForBuilding(
    Property building,
    List<Property> properties,
  ) {
    if (_isPerUnitBuilding(building)) {
      return _buildingUnitsFor(building, properties)
          .where((unit) => unit.occupiedUnits > 0)
          .length;
    }
    return building.occupiedUnits > 0 ? 1 : 0;
  }

  int _vacantUnitsForBuilding(
    Property building,
    List<Property> properties,
  ) {
    final total = _isPerUnitBuilding(building)
        ? _configuredUnitsForBuilding(building, properties)
        : 1;
    final occupied = _occupiedUnitsForBuilding(building, properties);
    final vacant = total - occupied;
    return vacant < 0 ? 0 : vacant;
  }

  bool _isTopLevelPropertyOccupied(
    Property property,
    List<Property> properties,
  ) {
    if (_isPerUnitBuilding(property)) {
      return _occupiedUnitsForBuilding(property, properties) > 0;
    }
    return property.occupiedUnits > 0;
  }

  Property? _parentBuildingForUnit(
    Property unit,
    List<Property> properties,
  ) {
    final parentId = (unit.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return null;
    return properties
        .where((property) => property.id == parentId)
        .firstOrNull;
  }

  String _propertySemanticSummary(
    Property property,
    List<Property> properties,
  ) {
    if (_isBuildingUnitProperty(property)) {
      final building = _parentBuildingForUnit(property, properties);
      final buildingName = building?.name.trim() ?? '';
      final unitName = property.name.trim().isEmpty ? property.id : property.name;
      final occupied = property.occupiedUnits > 0 ? 'مشغولة' : 'خالية';
      if (buildingName.isNotEmpty) {
        return 'هذه وحدة ضمن عمارة $buildingName باسم $unitName، وعدد الغرف ${property.rooms ?? 0}، وحالتها الآن $occupied.';
      }
      return 'هذا السجل يمثل وحدة باسم $unitName، وعدد الغرف ${property.rooms ?? 0}، وحالتها الآن $occupied.';
    }

    if (property.type == PropertyType.building) {
      final configuredUnits = _configuredUnitsForBuilding(property, properties);
      final registeredUnits = _registeredUnitsForBuilding(property, properties);
      final occupiedUnits = _occupiedUnitsForBuilding(property, properties);
      final vacantUnits = _vacantUnitsForBuilding(property, properties);
      if (_isPerUnitBuilding(property)) {
        return 'هذا العقار عمارة ذات وحدات، بعدد وحدات مُعدّ ${configuredUnits.toString()}، والمسجل فعليًا ${registeredUnits.toString()}، والمشغول ${occupiedUnits.toString()}، والخالي ${vacantUnits.toString()}.';
      }
      final occupied = property.occupiedUnits > 0 ? 'مؤجرة' : 'خالية';
      return 'هذا العقار عمارة تؤجر كعقار واحد، وحالتها الآن $occupied.';
    }

    final occupied = property.occupiedUnits > 0 ? 'مشغول' : 'خالي';
    return 'هذا العقار ${property.type.label} مستقل، وعدد الغرف ${property.rooms ?? 0}، وحالته الآن $occupied.';
  }

  Map<String, dynamic> _propertySemanticPayload(
    Property property,
    List<Property> properties,
  ) {
    final payload = <String, dynamic>{
      'name': property.name,
      'type': property.type.name,
      'typeLabel': property.type.label,
      'address': property.address,
      'rooms': property.rooms,
      'roomsLabel': 'غرف',
      'area': property.area,
      'price': property.price,
      'floors': property.floors,
      'description': property.description,
      'documentType': property.documentType,
      'documentNumber': property.documentNumber,
      'electricityNumber': property.electricityNumber,
      'waterNumber': property.waterNumber,
      'isArchived': property.isArchived,
      'semanticSummary': _propertySemanticSummary(property, properties),
    };

    if (_isBuildingUnitProperty(property)) {
      final building = _parentBuildingForUnit(property, properties);
      payload.addAll(<String, dynamic>{
        'structureKind': 'unit',
        'structureLabel': 'وحدة',
        'buildingName': building?.name,
        'isOccupied': property.occupiedUnits > 0,
        'occupiedUnits': property.occupiedUnits,
        'countsLabel': 'غرف',
        'semanticGuidance':
            'هذه وحدة داخل عمارة وليست عقارًا رئيسيًا مستقلًا في عداد العقارات العامة.',
      });
      return payload;
    }

    if (property.type == PropertyType.building) {
      final configuredUnits = _configuredUnitsForBuilding(property, properties);
      final registeredUnits = _registeredUnitsForBuilding(property, properties);
      final occupiedUnits = _occupiedUnitsForBuilding(property, properties);
      final vacantUnits = _vacantUnitsForBuilding(property, properties);
      payload.addAll(<String, dynamic>{
        'structureKind': 'building',
        'structureLabel': 'عمارة',
        'managementMode': _isPerUnitBuilding(property) ? 'units' : 'whole_building',
        'managementModeLabel':
            _isPerUnitBuilding(property) ? 'إدارة بالوحدات' : 'تأجير كامل العمارة',
        'totalUnits': configuredUnits,
        'configuredUnits': configuredUnits,
        'registeredUnits': registeredUnits,
        'occupiedUnits': occupiedUnits,
        'vacantUnits': vacantUnits,
        'isOccupied': occupiedUnits > 0,
        'countsLabel': 'وحدات',
        'semanticGuidance':
            'العمارة تُحسب عقارًا رئيسيًا واحدًا، بينما الإشغال والخلو هنا يُحسبان على مستوى الوحدات لا الغرف.',
      });
      return payload;
    }

    payload.addAll(<String, dynamic>{
      'structureKind': 'property',
      'structureLabel': property.type.label,
      'isOccupied': property.occupiedUnits > 0,
      'occupiedUnits': property.occupiedUnits,
      'countsLabel': 'غرف',
      'semanticGuidance':
          'هذا عقار رئيسي مستقل، وعدد الغرف يخص هذا العقار نفسه وليس وحدات داخل عمارة.',
    });
    return payload;
  }

  Map<String, dynamic> _topLevelPropertyListItem(
    Property property,
    List<Property> properties,
  ) {
    final payload = _propertySemanticPayload(property, properties);
    payload['propertyId'] = property.id;
    if (property.type == PropertyType.building) {
      payload['childUnitsCount'] = _registeredUnitsForBuilding(property, properties);
    }
    return payload;
  }

  Map<String, dynamic> _propertySemanticPayloadStrict(
    Property property,
    List<Property> properties,
  ) {
    final payload = <String, dynamic>{
      'name': property.name,
      'type': property.type.name,
      'typeLabel': property.type.label,
      'address': property.address,
      'area': property.area,
      'price': property.price,
      'floors': property.floors,
      'description': property.description,
      'documentType': property.documentType,
      'documentNumber': property.documentNumber,
      'electricityNumber': property.electricityNumber,
      'waterNumber': property.waterNumber,
      'isArchived': property.isArchived,
      'semanticSummary': _propertySemanticSummary(property, properties),
    };

    if (_isBuildingUnitProperty(property)) {
      final building = _parentBuildingForUnit(property, properties);
      payload.addAll(<String, dynamic>{
        'structureKind': 'unit',
        'structureLabel': 'وحدة',
        'buildingName': building?.name,
        'rooms': property.rooms,
        'roomsLabel': 'غرف',
        'isOccupied': property.occupiedUnits > 0,
        'occupiedUnits': property.occupiedUnits,
        'countsLabel': 'غرف',
        'semanticGuidance':
            'هذه وحدة داخل عمارة وليست عقارًا رئيسيًا مستقلًا في عداد العقارات العامة.',
      });
      return payload;
    }

    if (property.type == PropertyType.building) {
      final configuredUnits = _configuredUnitsForBuilding(property, properties);
      final registeredUnits = _registeredUnitsForBuilding(property, properties);
      final occupiedUnits = _occupiedUnitsForBuilding(property, properties);
      final vacantUnits = _vacantUnitsForBuilding(property, properties);
      payload.addAll(<String, dynamic>{
        'structureKind': 'building',
        'structureLabel': 'عمارة',
        'managementMode':
            _isPerUnitBuilding(property) ? 'units' : 'whole_building',
        'managementModeLabel': _isPerUnitBuilding(property)
            ? 'إدارة بالوحدات'
            : 'تأجير كامل العمارة',
        'totalUnits': configuredUnits,
        'configuredUnits': configuredUnits,
        'registeredUnits': registeredUnits,
        'occupiedUnits': occupiedUnits,
        'vacantUnits': vacantUnits,
        'isOccupied': occupiedUnits > 0,
        'countsLabel': 'وحدات',
        'semanticGuidance':
            'العمارة تُحسب عقارًا رئيسيًا واحدًا، بينما الإشغال والخلو هنا يُحسبان على مستوى الوحدات لا الغرف.',
        'answerContract':
            'اذكر أن هذا العقار عمارة ذات وحدات، واعرض عدد الوحدات والمشغول والخالي. لا تستخدم كلمة غرف لوصف العمارة.',
      });
      return payload;
    }

    payload.addAll(<String, dynamic>{
      'structureKind': 'property',
      'structureLabel': property.type.label,
      'rooms': property.rooms,
      'roomsLabel': 'غرف',
      'isOccupied': property.occupiedUnits > 0,
      'occupiedUnits': property.occupiedUnits,
      'countsLabel': 'غرف',
      'semanticGuidance':
          'هذا عقار رئيسي مستقل، وعدد الغرف يخص هذا العقار نفسه وليس وحدات داخل عمارة.',
    });
    return payload;
  }

  Map<String, dynamic> _topLevelPropertyListItemV2(
    Property property,
    List<Property> properties,
  ) {
    final payload = _propertySemanticPayloadStrict(property, properties);
    payload['propertyId'] = property.id;
    if (property.type == PropertyType.building) {
      payload['childUnitsCount'] = _registeredUnitsForBuilding(property, properties);
    }
    return payload;
  }

  String _normalizeProviderName(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  int _countProviderCurrentMaintenanceRequests(String providerName) {
    final box = _maintenanceBox();
    if (box == null) return 0;

    final target = _normalizeProviderName(providerName);
    if (target.isEmpty) return 0;

    var count = 0;
    for (final item in box.values) {
      final assigned = _normalizeProviderName(item.assignedTo);
      final status = item.status.name.toLowerCase();
      final isCurrent = status == 'open' || status == 'inprogress';
      if (item.isArchived != true && assigned == target && isCurrent) {
        count += 1;
      }
    }
    return count;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readDocMap(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
      return snap.data() ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  int _toIntValue(dynamic raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  int? _normalizeHour24(dynamic raw) {
    if (raw == null) return null;
    final parsed = raw is int
        ? raw
        : raw is num
            ? raw.toInt()
            : raw is String
                ? int.tryParse(raw.trim())
                : null;
    if (parsed == null || parsed < 0 || parsed > 23) return null;
    return parsed;
  }

  String? _hour24Label(int? hour24) {
    if (hour24 == null) return null;
    final h12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final period = hour24 < 12 ? 'صباحًا' : 'مساءً';
    return '$h12 $period';
  }

  Future<void> _putValuesIfBoxOpen(
    String name,
    Map<String, dynamic> values,
  ) async {
    if (!Hive.isBoxOpen(name) || values.isEmpty) return;
    final box = Hive.box(name);
    for (final entry in values.entries) {
      await box.put(entry.key, entry.value);
    }
  }

  String? _normalizeSettingsDateSystem(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'gregorian' || value == 'miladi' || value == 'ميلادي') {
      return 'gregorian';
    }
    if (value == 'hijri' || value == 'hejri' || value == 'هجري') {
      return 'hijri';
    }
    return null;
  }

  String? _normalizeSettingsLanguage(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'ar' ||
        value == 'arabic' ||
        value == 'العربية' ||
        value == 'عربي') {
      return 'ar';
    }
    if (value == 'en' ||
        value == 'english' ||
        value == 'الانجليزية' ||
        value == 'الإنجليزية') {
      return 'en';
    }
    return null;
  }

  Box<String>? _notificationsDismissedBox() {
    final name = boxName('notificationsDismissed');
    return Hive.isBoxOpen(name) ? Hive.box<String>(name) : null;
  }

  Box<String>? _notificationsKnownContractsBox() {
    final name = boxName('notificationsKnownContracts');
    return Hive.isBoxOpen(name) ? Hive.box<String>(name) : null;
  }

  DateTime _notificationDateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  int _notificationDaysBetween(DateTime from, DateTime to) =>
      _notificationDateOnly(to).difference(_notificationDateOnly(from)).inDays;

  int _notificationMonthsPerCycle(PaymentCycle cycle) {
    switch (cycle) {
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

  int _notificationMonthsInTerm(ContractTerm term) {
    switch (term) {
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

  DateTime _notificationAddMonths(DateTime date, int months) {
    if (months == 0) return _notificationDateOnly(date);
    final totalMonths = (date.month - 1) + months;
    final year = date.year + (totalMonths ~/ 12);
    final month = (totalMonths % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = date.day > lastDay ? lastDay : date.day;
    return _notificationDateOnly(DateTime(year, month, safeDay));
  }

  int _notificationCoveredMonthsByAdvance(Contract contract) {
    if (contract.advanceMode != AdvanceMode.coverMonths) return 0;
    final months = _notificationMonthsInTerm(contract.term);
    if (months <= 0 || contract.totalAmount <= 0) return 0;
    final monthlyValue = contract.totalAmount / months;
    final covered = ((contract.advancePaid ?? 0) / monthlyValue).floor();
    return covered.clamp(0, months);
  }

  List<DateTime> _notificationAllInstallmentDueDates(Contract contract) {
    final out = <DateTime>[];
    if (contract.term == ContractTerm.daily) return out;

    final start = _notificationDateOnly(contract.startDate);
    final end = _notificationDateOnly(contract.endDate);
    final termMonths = _notificationMonthsInTerm(contract.term);
    final stepMonths = _notificationMonthsPerCycle(contract.paymentCycle);
    if (termMonths <= 0 || stepMonths <= 0) return out;

    var startCycle = 0;
    if (contract.advanceMode == AdvanceMode.coverMonths) {
      final coveredMonths = _notificationCoveredMonthsByAdvance(contract);
      if (coveredMonths >= termMonths) return out;
      startCycle = (coveredMonths / stepMonths).ceil();
    }

    final totalCycles = (termMonths / stepMonths).ceil();
    for (var i = startCycle; i < totalCycles; i++) {
      final due = _notificationAddMonths(start, i * stepMonths);
      if (due.isBefore(start) || due.isAfter(end)) continue;
      out.add(due);
    }
    return out;
  }

  String _notificationStableKey({
    required String kind,
    required DateTime anchor,
    String? contractId,
    String? invoiceId,
    String? maintenanceId,
  }) {
    final id = contractId ?? invoiceId ?? maintenanceId ?? 'na';
    return '$kind:$id:${_notificationDateOnly(anchor).toIso8601String()}';
  }

  String _notificationLegacyKey({
    required String kind,
    required DateTime anchor,
    String? contractId,
    String? invoiceId,
    String? maintenanceId,
  }) {
    final id = contractId ?? invoiceId ?? maintenanceId ?? 'na';
    return '$kind:$id:${anchor.toIso8601String()}';
  }

  Map<String, dynamic> _notificationRefPayload({
    required String kind,
    required DateTime anchor,
    String? contractId,
    String? invoiceId,
    String? maintenanceId,
    String? propertyId,
    String? serviceType,
    String? serviceTargetId,
  }) {
    return <String, dynamic>{
      'kind': kind,
      'anchorDate': _notificationDateOnly(anchor).toIso8601String(),
      if ((contractId ?? '').trim().isNotEmpty) 'contractId': contractId,
      if ((invoiceId ?? '').trim().isNotEmpty) 'invoiceId': invoiceId,
      if ((maintenanceId ?? '').trim().isNotEmpty) 'maintenanceId': maintenanceId,
      if ((propertyId ?? '').trim().isNotEmpty) 'propertyId': propertyId,
      if ((serviceType ?? '').trim().isNotEmpty) 'serviceType': serviceType,
      if ((serviceTargetId ?? '').trim().isNotEmpty)
        'serviceTargetId': serviceTargetId,
    };
  }

  String _encodeNotificationRef(Map<String, dynamic> data) {
    return base64Url.encode(utf8.encode(jsonEncode(data)));
  }

  Map<String, dynamic>? _decodeNotificationRef(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(text)));
      final map = jsonDecode(decoded);
      if (map is Map<String, dynamic>) return map;
      if (map is Map) return map.cast<String, dynamic>();
    } catch (_) {}
    try {
      final map = jsonDecode(text);
      if (map is Map<String, dynamic>) return map;
      if (map is Map) return map.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _notificationRefFromArgs(Map<String, dynamic> args) {
    final decoded = _decodeNotificationRef(args['notificationRef']);
    if (decoded != null) return decoded;

    final kind = _normalizeNotificationKind(args['kind']);
    final anchor = _parseDate((args['anchorDate'] ?? '').toString().trim());
    if (kind == 'all' || anchor == null) return null;

    return _notificationRefPayload(
      kind: kind,
      anchor: anchor,
      contractId: (args['contractId'] ?? '').toString().trim(),
      invoiceId: (args['invoiceId'] ?? '').toString().trim(),
      maintenanceId: (args['maintenanceId'] ?? '').toString().trim(),
      propertyId: (args['propertyId'] ?? '').toString().trim(),
      serviceType: (args['serviceType'] ?? '').toString().trim(),
      serviceTargetId: (args['serviceTargetId'] ?? '').toString().trim(),
    );
  }

  bool _notificationIsDismissed(Map<String, dynamic> refData) {
    final box = _notificationsDismissedBox();
    if (box == null) return false;
    final kind = (refData['kind'] ?? '').toString().trim();
    final anchor = _parseDate((refData['anchorDate'] ?? '').toString().trim());
    if (kind.isEmpty || anchor == null) return false;
    final contractId = (refData['contractId'] ?? '').toString().trim();
    final invoiceId = (refData['invoiceId'] ?? '').toString().trim();
    final maintenanceId = (refData['maintenanceId'] ?? '').toString().trim();
    final stable = _notificationStableKey(
      kind: kind,
      anchor: anchor,
      contractId: contractId,
      invoiceId: invoiceId,
      maintenanceId: maintenanceId,
    );
    final legacy = _notificationLegacyKey(
      kind: kind,
      anchor: anchor,
      contractId: contractId,
      invoiceId: invoiceId,
      maintenanceId: maintenanceId,
    );
    return box.containsKey(stable) || box.containsKey(legacy);
  }

  String _notificationKindLabel(String kind) {
    switch (kind) {
      case 'contract_started_today':
        return 'بداية عقد اليوم';
      case 'contract_expiring':
        return 'عقد على وشك الانتهاء';
      case 'contract_ended':
        return 'عقد منتهٍ';
      case 'contract_due_soon':
        return 'موعد سداد قادم';
      case 'contract_due_today':
        return 'سداد مستحق اليوم';
      case 'contract_due_overdue':
        return 'سداد متأخر';
      case 'invoice_overdue':
        return 'فاتورة مستحقة أو متأخرة';
      case 'maintenance_today':
        return 'صيانة اليوم';
      case 'service_start':
        return 'بداية خدمة';
      case 'service_due':
        return 'خدمة مستحقة';
      default:
        return kind;
    }
  }

  String _notificationInternetBillingMode(Map<String, dynamic> cfg) {
    final payer = (cfg['payer'] ?? '').toString().trim().toLowerCase();
    final raw = (cfg['internetBillingMode'] ??
            (payer == 'tenant' ? 'separate' : 'owner'))
        .toString()
        .trim()
        .toLowerCase();
    return raw == 'separate' ? 'separate' : 'owner';
  }

  bool _notificationServiceHasProvider(String type, Map<String, dynamic> cfg) {
    if (type == 'internet') {
      if (_notificationInternetBillingMode(cfg) != 'owner') return true;
      return (cfg['providerName'] ?? cfg['provider'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
    }
    if (type == 'cleaning' || type == 'elevator') {
      return (cfg['providerName'] ?? cfg['provider'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
    }
    return true;
  }

  bool _notificationIsSharedUtilityService(
    String type,
    Map<String, dynamic> cfg,
  ) {
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

  int _notificationServiceRemindDays(Map<String, dynamic> cfg) {
    final value = (cfg['remindBeforeDays'] as num?)?.toInt() ?? 0;
    if (value < 0) return 0;
    if (value > 3) return 3;
    return value;
  }

  String _notificationAfterLabel(int days) {
    if (days == 1) return 'غدًا';
    if (days == 2) return 'بعد غد';
    return 'بعد $days أيام';
  }

  String _notificationServiceTitle(
    String type,
    Map<String, dynamic> cfg, {
    required int delta,
  }) {
    final sharedUtility = _notificationIsSharedUtilityService(type, cfg);
    if (delta < 0) {
      final after = _notificationAfterLabel(-delta);
      if (sharedUtility) {
        return type == 'water'
            ? 'لديك فاتورة مياه مشتركة $after'
            : 'لديك فاتورة كهرباء مشتركة $after';
      }
      if (type == 'water') return 'لديك قسط مياه $after';
      if (type == 'electricity') return 'لديك سداد كهرباء $after';
      if (type == 'internet') return 'لديك طلب تجديد خدمة إنترنت $after';
      if (type == 'cleaning') return 'لديك طلب نظافة $after';
      if (type == 'elevator') return 'لديك طلب صيانة مصعد $after';
      return 'لديك خدمة دورية $after';
    }
    if (delta == 0) {
      if (sharedUtility) {
        return type == 'water'
            ? 'اليوم موعد فاتورة المياه المشتركة'
            : 'اليوم موعد فاتورة الكهرباء المشتركة';
      }
      if (type == 'water') return 'اليوم لديك قسط مياه';
      if (type == 'electricity') return 'اليوم لديك سداد كهرباء';
      if (type == 'internet') return 'اليوم لديك طلب تجديد خدمة إنترنت';
      if (type == 'cleaning') return 'اليوم لديك طلب نظافة';
      if (type == 'elevator') return 'اليوم لديك طلب صيانة مصعد';
      return 'اليوم لديك خدمة دورية';
    }
    if (sharedUtility) {
      return type == 'water'
          ? 'فاتورة المياه المشتركة متأخرة'
          : 'فاتورة الكهرباء المشتركة متأخرة';
    }
    if (type == 'water') return 'قسط المياه متأخر';
    if (type == 'electricity') return 'سداد الكهرباء متأخر';
    if (type == 'internet') return 'تجديد خدمة الإنترنت متأخر';
    if (type == 'cleaning') return 'طلب النظافة متأخر';
    if (type == 'elevator') return 'طلب صيانة المصعد متأخر';
    return 'خدمة دورية متأخرة';
  }

  String _notificationServiceSubtitle(
    String type,
    Map<String, dynamic> cfg,
    DateTime due,
  ) {
    final sharedUtility = _notificationIsSharedUtilityService(type, cfg);
    final label = sharedUtility
        ? 'موعد الفاتورة'
        : (type == 'water' || type == 'electricity'
            ? 'موعد السداد'
            : 'موعد التنفيذ');
    return '$label: ${_fmtDate(due)}';
  }

  Map<String, dynamic>? _notificationServiceConfigFor(
    String propertyId,
    String serviceType,
  ) {
    final box = _servicesBox();
    if (box == null) return null;
    final raw = box.get('$propertyId::$serviceType');
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  DateTime? _notificationParseConfigDate(dynamic raw) {
    if (raw is DateTime) return _notificationDateOnly(raw);
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    try {
      return _notificationDateOnly(DateTime.parse(text));
    } catch (_) {
      return null;
    }
  }

  DateTime? _notificationServiceStartDate(Map<String, dynamic> cfg) =>
      _notificationParseConfigDate(cfg['startDate']);

  DateTime? _notificationServiceLastGeneratedDate(Map<String, dynamic> cfg) =>
      _notificationParseConfigDate(cfg['lastGeneratedRequestDate']);

  DateTime? _notificationServiceSuppressedDate(Map<String, dynamic> cfg) =>
      _notificationParseConfigDate(cfg['suppressedRequestDate']);

  DateTime? _notificationServiceCurrentCycleDate(Map<String, dynamic> cfg) {
    final type = (cfg['serviceType'] ?? '').toString().trim();
    final isPeriodicMaintenanceService =
        type == 'cleaning' ||
        type == 'elevator' ||
        (type == 'internet' && _notificationInternetBillingMode(cfg) == 'owner');
    final lastGenerated = _notificationServiceLastGeneratedDate(cfg);
    final startDate = _notificationServiceStartDate(cfg);
    if (isPeriodicMaintenanceService &&
        lastGenerated == null &&
        startDate != null) {
      return startDate;
    }
    return _notificationParseConfigDate(
      cfg['nextDueDate'] ?? cfg['nextServiceDate'],
    );
  }

  bool _notificationMaintenanceHasCanceledInvoice(
    MaintenanceRequest request,
    Box<Invoice>? invoices,
  ) {
    if (invoices == null) return false;
    final invoiceId = (request.invoiceId ?? '').trim();
    if (invoiceId.isEmpty) return false;
    final invoice = invoices.get(invoiceId);
    if (invoice == null) return false;
    return invoice.isCanceled == true;
  }

  DateTime _notificationMaintenanceAnchor(MaintenanceRequest request) =>
      _notificationDateOnly(
        request.periodicCycleDate ??
            request.executionDeadline ??
            request.scheduledDate ??
            request.createdAt,
      );

  String? _notificationNormalizePeriodicServiceTypeToken(dynamic raw) {
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
    return null;
  }

  bool _notificationMatchesLegacyPeriodicMaintenanceRequest(
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

  bool _notificationMatchesPeriodicMaintenanceRequest(
    MaintenanceRequest request, {
    required String propertyId,
    required String type,
  }) {
    if (request.propertyId != propertyId) return false;
    final tagged = _notificationNormalizePeriodicServiceTypeToken(
      request.periodicServiceType,
    );
    if (tagged != null) return tagged == type;
    return _notificationMatchesLegacyPeriodicMaintenanceRequest(request, type);
  }

  MaintenanceRequest? _notificationActivePeriodicMaintenanceRequest({
    required Box<MaintenanceRequest>? maintenance,
    required Box<Invoice>? invoices,
    required String propertyId,
    required String type,
    required DateTime anchor,
  }) {
    if (maintenance == null) return null;
    final normalizedAnchor = _notificationDateOnly(anchor);
    MaintenanceRequest? latest;
    for (final request in maintenance.values) {
      if (request.isArchived) continue;
      if (request.status == MaintenanceStatus.canceled) continue;
      if (request.status == MaintenanceStatus.completed) continue;
      if (_notificationMaintenanceHasCanceledInvoice(request, invoices)) {
        continue;
      }
      if (!_notificationMatchesPeriodicMaintenanceRequest(
        request,
        propertyId: propertyId,
        type: type,
      )) {
        continue;
      }
      if (_notificationMaintenanceAnchor(request) != normalizedAnchor) {
        continue;
      }
      if (latest == null || request.createdAt.isAfter(latest.createdAt)) {
        latest = request;
      }
    }
    return latest;
  }

  bool _notificationHasCompletedPeriodicMaintenanceRequest({
    required Box<MaintenanceRequest>? maintenance,
    required String propertyId,
    required String type,
    required DateTime anchor,
  }) {
    if (maintenance == null) return false;
    final normalizedAnchor = _notificationDateOnly(anchor);
    for (final request in maintenance.values) {
      if (request.isArchived) continue;
      if (request.status != MaintenanceStatus.completed) continue;
      if (!_notificationMatchesPeriodicMaintenanceRequest(
        request,
        propertyId: propertyId,
        type: type,
      )) {
        continue;
      }
      if (_notificationMaintenanceAnchor(request) != normalizedAnchor) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool _notificationCanTrackPeriodicMaintenanceRequest(
    MaintenanceRequest request,
    Box<Invoice>? invoices,
  ) {
    if (request.isArchived) return false;
    if (request.status == MaintenanceStatus.canceled) return false;
    if (request.status == MaintenanceStatus.completed) return false;
    if (_notificationMaintenanceHasCanceledInvoice(request, invoices)) {
      return false;
    }
    return true;
  }

  MaintenanceRequest? _notificationTrackedPeriodicMaintenanceRequestFromConfig({
    required Box<MaintenanceRequest>? maintenance,
    required Box<Invoice>? invoices,
    required String propertyId,
    required String type,
    required Map<String, dynamic> cfg,
  }) {
    if (maintenance == null) return null;

    bool valid(MaintenanceRequest request) {
      return _notificationCanTrackPeriodicMaintenanceRequest(request, invoices) &&
          _notificationMatchesPeriodicMaintenanceRequest(
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
      if (request != null && valid(request)) return request;
    }

    final lastGenerated = _notificationServiceLastGeneratedDate(cfg);
    if (lastGenerated != null) {
      final request = _notificationActivePeriodicMaintenanceRequest(
        maintenance: maintenance,
        invoices: invoices,
        propertyId: propertyId,
        type: type,
        anchor: lastGenerated,
      );
      if (request != null && valid(request)) return request;
    }

    final trackedCycleDate = _notificationServiceCurrentCycleDate(cfg);
    if (trackedCycleDate != null) {
      final request = _notificationActivePeriodicMaintenanceRequest(
        maintenance: maintenance,
        invoices: invoices,
        propertyId: propertyId,
        type: type,
        anchor: trackedCycleDate,
      );
      if (request != null && valid(request)) return request;
    }

    final candidates = maintenance.values.where(valid).toList(growable: false);
    if (candidates.length == 1) return candidates.first;
    return null;
  }

  String? _notificationServiceTargetId(
    String type,
    Map<String, dynamic> cfg, {
    MaintenanceRequest? activePeriodicRequest,
  }) {
    if (_notificationIsSharedUtilityService(type, cfg)) return null;
    final activeId = activePeriodicRequest?.id.toString().trim() ?? '';
    if (activeId.isNotEmpty) return activeId;
    final trackedId = (cfg['targetId'] ?? '').toString().trim();
    if (trackedId.isEmpty) return null;
    return trackedId;
  }

  PropertyType _parsePropertyType(String s) {
    switch (s.toLowerCase()) {
      case 'villa':
        return PropertyType.villa;
      case 'building':
        return PropertyType.building;
      case 'land':
        return PropertyType.land;
      case 'office':
        return PropertyType.office;
      case 'shop':
        return PropertyType.shop;
      case 'warehouse':
        return PropertyType.warehouse;
      default:
        return PropertyType.apartment;
    }
  }

  ContractTerm _parseTerm(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'daily':
        return ContractTerm.daily;
      case 'quarterly':
        return ContractTerm.quarterly;
      case 'semiannual':
        return ContractTerm.semiAnnual;
      case 'annual':
        return ContractTerm.annual;
      default:
        return ContractTerm.monthly;
    }
  }

  PaymentCycle _parsePaymentCycle(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'quarterly':
        return PaymentCycle.quarterly;
      case 'semiannual':
        return PaymentCycle.semiAnnual;
      case 'annual':
        return PaymentCycle.annual;
      default:
        return PaymentCycle.monthly;
    }
  }

  MaintenancePriority _parsePriority(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'low':
        return MaintenancePriority.low;
      case 'high':
        return MaintenancePriority.high;
      case 'urgent':
        return MaintenancePriority.urgent;
      default:
        return MaintenancePriority.medium;
    }
  }

  MaintenanceStatus _parseStatus(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'inprogress':
        return MaintenanceStatus.inProgress;
      case 'completed':
        return MaintenanceStatus.completed;
      case 'canceled':
        return MaintenanceStatus.canceled;
      default:
        return MaintenanceStatus.open;
    }
  }

  String _nextSerial(String prefix, Iterable<String?> existing) {
    final year = KsaTime.now().year;
    int max = 0;
    final p = '$year-';
    for (final s in existing) {
      if (s != null && s.startsWith(p)) {
        final n = int.tryParse(s.substring(p.length)) ?? 0;
        if (n > max) max = n;
      }
    }
    return '$p${(max + 1).toString().padLeft(4, '0')}';
  }

  // ================================================================
  //  قراءة - عقارات
  // ================================================================

  String _getPropertiesSummary() {
    final box = _propertiesBox();
    if (box == null) return _err('لا توجد بيانات');
    final all = box.values.where((p) => p.isArchived != true).toList();
    final total = all.length;
    final occupied = all.where((p) => p.occupiedUnits > 0).length;
    return jsonEncode({
      'total': total,
      'occupied': occupied,
      'vacant': total - occupied,
      'vacancy_rate': total > 0
          ? '${((total - occupied) / total * 100).toStringAsFixed(0)}%'
          : '0%',
    });
  }

  String _getPropertiesList() {
    final box = _propertiesBox();
    if (box == null) return jsonEncode([]);
    final list = box.values
        .where((p) => p.isArchived != true)
        .map((p) => {
              'name': p.name,
              'type': p.type.toString().split('.').last,
              'address': p.address,
              'rooms': p.rooms,
              'area': p.area,
              'price': p.price,
            })
        .toList();
    return jsonEncode(list);
  }

  String _getPropertyDetails(String query) {
    final p = _findProperty(query);
    if (p == null) return _err('لم يتم العثور على عقار بهذا الاسم');
    return jsonEncode({
      'name': p.name,
      'type': p.type.toString().split('.').last,
      'address': p.address,
      'rooms': p.rooms,
      'area': p.area,
      'price': p.price,
      'floors': p.floors,
      'totalUnits': p.totalUnits,
      'occupiedUnits': p.occupiedUnits,
      'description': p.description,
      'documentType': p.documentType,
      'documentNumber': p.documentNumber,
      'electricityNumber': p.electricityNumber,
      'waterNumber': p.waterNumber,
      'isArchived': p.isArchived,
    });
  }

  // ================================================================
  //  قراءة - مستأجرين
  // ================================================================

  String _getPropertiesSummaryV2() {
    final all = _activePropertiesList();
    if (all.isEmpty) return _err('لا توجد بيانات');
    final topLevel = _topLevelProperties(all);
    final buildings = topLevel
        .where((property) => property.type == PropertyType.building)
        .toList(growable: false);
    final standaloneProperties = topLevel
        .where((property) => property.type != PropertyType.building)
        .toList(growable: false);
    final occupied = topLevel
        .where((property) => _isTopLevelPropertyOccupied(property, all))
        .length;
    final vacant = topLevel.length - occupied;
    final registeredBuildingUnits =
        all.where((property) => _isBuildingUnitProperty(property)).length;
    final configuredBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _configuredUnitsForBuilding(building, all),
    );
    final occupiedBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _occupiedUnitsForBuilding(building, all),
    );
    final vacantBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _vacantUnitsForBuilding(building, all),
    );
    final items = topLevel
        .map((property) => _topLevelPropertyListItemV2(property, all))
        .toList(growable: false);
    return jsonEncode({
      'total': topLevel.length,
      'occupied': occupied,
      'vacant': vacant,
      'vacancy_rate': topLevel.isNotEmpty
          ? '${((vacant) / topLevel.length * 100).toStringAsFixed(0)}%'
          : '0%',
      'topLevelProperties': topLevel.length,
      'buildings': buildings.length,
      'standaloneProperties': standaloneProperties.length,
      'registeredBuildingUnits': registeredBuildingUnits,
      'configuredBuildingUnits': configuredBuildingUnits,
      'occupiedBuildingUnits': occupiedBuildingUnits,
      'vacantBuildingUnits': vacantBuildingUnits,
      'propertyTypeBreakdown': {
        for (final type in PropertyType.values)
          type.name: topLevel.where((property) => property.type == type).length,
      },
      'buildingsPreview': buildings
          .take(5)
          .map((building) => {
                'name': building.name,
                'managementMode':
                    _isPerUnitBuilding(building) ? 'units' : 'whole_building',
                'managementModeLabel': _isPerUnitBuilding(building)
                    ? 'إدارة بالوحدات'
                    : 'تأجير كامل العمارة',
                'configuredUnits': _configuredUnitsForBuilding(building, all),
                'registeredUnits': _registeredUnitsForBuilding(building, all),
                'occupiedUnits': _occupiedUnitsForBuilding(building, all),
                'vacantUnits': _vacantUnitsForBuilding(building, all),
              })
          .toList(growable: false),
      'semanticGuidance':
          'عدد العقارات هنا يعني العقارات الرئيسية فقط. الوحدات داخل العمائر لا تُحسب عقارات مستقلة، بل تُذكر ضمن ملخص الوحدات المشغولة والخالية.',
      'semanticSummary':
          'لديك ${topLevel.length} عقار رئيسي، منها ${buildings.length} عمارة، وبإجمالي وحدات مسجلة ${registeredBuildingUnits.toString()}، والمشغول منها ${occupiedBuildingUnits.toString()}، والخالي ${vacantBuildingUnits.toString()}.',
      'items': items,
    });
  }

  String _getPropertiesListV2() {
    final all = _activePropertiesList();
    if (all.isEmpty) return jsonEncode([]);
    final list = _topLevelProperties(all)
        .map((property) => _topLevelPropertyListItem(property, all))
        .toList(growable: false);
    return jsonEncode(list);
  }

  String _getPropertyDetailsV2(String query) {
    final property = _findProperty(query);
    if (property == null) return _err('لم يتم العثور على عقار بهذا الاسم');
    return jsonEncode(_propertySemanticPayload(property, _activePropertiesList()));
  }

  String _getPropertiesListV3() {
    final all = _activePropertiesList();
    if (all.isEmpty) return jsonEncode([]);
    final list = _topLevelProperties(all)
        .map((property) => _topLevelPropertyListItemV2(property, all))
        .toList(growable: false);
    return jsonEncode(list);
  }

  String _getPropertyDetailsV3(String query) {
    final property = _findProperty(query);
    if (property == null) return _err('Ù„Ù… ÙŠØªÙ… Ø§Ù„Ø¹Ø«ÙˆØ± Ø¹Ù„Ù‰ Ø¹Ù‚Ø§Ø± Ø¨Ù‡Ø°Ø§ Ø§Ù„Ø§Ø³Ù…');
    return jsonEncode(
      _propertySemanticPayloadStrict(property, _activePropertiesList()),
    );
  }

  String _getPropertyDetailsV4(String query) {
    final property = _findProperty(query);
    if (property == null) return _getPropertyDetailsV2(query);
    return jsonEncode(
      _propertySemanticPayloadStrict(property, _activePropertiesList()),
    );
  }

  String _getTenantsList() {
    final box = _tenantsBox();
    if (box == null) return jsonEncode([]);
    final list = box.values
        .where((t) => t.isArchived != true)
        .map((t) => {
              'name': t.fullName,
              'phone': t.phone,
              'nationalId': t.nationalId,
              'clientType': t.clientType,
              'isBlacklisted': t.isBlacklisted == true,
            })
        .toList();
    return jsonEncode(list);
  }

  String _getTenantDetails(String query) {
    final t = _findTenant(query);
    if (t == null) {
      return _err('لم يتم العثور على مستأجر بهذا الاسم أو الرقم');
    }
    return jsonEncode({
      'name': t.fullName,
      'nationalId': t.nationalId,
      'phone': t.phone,
      'email': t.email,
      'nationality': t.nationality,
      'clientType': t.clientType,
      'city': t.city,
      'region': t.region,
      'isBlacklisted': t.isBlacklisted == true,
      'blacklistReason': t.blacklistReason,
      'activeContractsCount': t.activeContractsCount,
      'isArchived': t.isArchived,
    });
  }

  // ================================================================
  //  قراءة - عقود
  // ================================================================

  String _getContractsList() {
    final box = _contractsBox();
    if (box == null) return jsonEncode([]);
    final now = KsaTime.now();
    final list = box.values
        .where((c) => (c as dynamic).isArchived != true)
        .map((c) {
      final d = c as dynamic;
      final end = d.endDate as DateTime;
      final terminated = d.isTerminated == true;
      final expired = end.isBefore(now);
      String status = 'نشط';
      if (terminated) {
        status = 'منهي';
      } else if (expired) {
        status = 'منتهي';
      }
      return {
        'serialNo': d.serialNo,
        'tenant': d.tenantSnapshot?['fullName'] ?? '',
        'property': d.propertySnapshot?['name'] ?? '',
        'status': status,
        'totalAmount': d.totalAmount,
        'startDate': _fmtDate(d.startDate as DateTime),
        'endDate': _fmtDate(end),
      };
    }).toList();
    return jsonEncode(list);
  }

  String _getActiveContracts() {
    final box = _contractsBox();
    if (box == null) return jsonEncode([]);
    final now = KsaTime.now();
    final list = box.values.where((c) {
      final d = c as dynamic;
      if (d.isArchived == true || d.isTerminated == true) return false;
      return !(d.endDate as DateTime).isBefore(now);
    }).map((c) {
      final d = c as dynamic;
      return {
        'serialNo': d.serialNo,
        'tenant': d.tenantSnapshot?['fullName'] ?? '',
        'property': d.propertySnapshot?['name'] ?? '',
        'totalAmount': d.totalAmount,
        'rentAmount': d.rentAmount,
        'paymentCycle': d.paymentCycle.toString().split('.').last,
        'endDate': _fmtDate(d.endDate as DateTime),
      };
    }).toList();
    return jsonEncode(list);
  }

  String _getContractDetails(String query) {
    final match = _findContract(query);
    if (match == null) return _err('لم يتم العثور على عقد');
    final invoiceBox = _invoicesBox();
    final invoices = invoiceBox == null
        ? const <Invoice>[]
        : _linkedContractInvoices(match.id, invoiceBox.values);
    final metrics = _contractInvoiceMetrics(invoices);
    final overdueInstallments = countOverduePayments(match);
    final upcomingInstallments =
        countNearDuePayments(match) + countDueTodayPayments(match);

    return jsonEncode({
      'serialNo': match.serialNo,
      'tenant': match.tenantSnapshot?['fullName'] ?? '',
      'property': match.propertySnapshot?['name'] ?? '',
      'totalAmount': match.totalAmount,
      'rentAmount': match.rentAmount,
      'currency': match.currency,
      'term': _contractTermLabel(match.term),
      'paymentCycle': _paymentCycleLabel(match.paymentCycle),
      'startDate': _fmtDate(match.startDate),
      'endDate': _fmtDate(match.endDate),
      'status': _contractStatusLabel(match),
      'isTerminated': match.isTerminated == true,
      'expiringSoon': _contractExpiringSoon(match),
      'terminatedAt': match.terminatedAt != null
          ? _fmtDate(match.terminatedAt as DateTime)
          : null,
      'notes': match.notes,
      'installmentsSummary': <String, dynamic>{
        'totalInstallments': metrics['totalInstallments'],
        'paidInstallments': metrics['paidInstallments'],
        'unpaidInstallments': metrics['unpaidInstallments'],
        'canceledInstallments': metrics['canceledInstallments'],
        'overdueInstallments': overdueInstallments,
        'upcomingInstallments': upcomingInstallments,
        'remainingTotal': metrics['remainingTotal'],
        if (metrics.containsKey('currentInvoice'))
          'currentInvoice': metrics['currentInvoice'],
        if (metrics.containsKey('nextUnpaidInvoice'))
          'nextUnpaidInvoice': metrics['nextUnpaidInvoice'],
        if (metrics.containsKey('lastPaidInvoice'))
          'lastPaidInvoice': metrics['lastPaidInvoice'],
      },
      'invoiceHistorySummary': <String, dynamic>{
        ...metrics,
        'overdueInstallments': overdueInstallments,
        'upcomingInstallments': upcomingInstallments,
      },
      'invoiceHistoryPreview': _contractInvoicePreview(invoices),
      'availableActions': <String, dynamic>{
        'openInvoiceHistory': <String, dynamic>{
          'tool': 'open_contract_invoice_history',
          'query': match.serialNo,
          'label': 'فتح سجل سندات العقد',
        },
      },
    });
  }

  // ================================================================
  //  قراءة - فواتير
  // ================================================================

  double _invoiceRemaining(Invoice invoice) {
    return double.parse((invoice.amount - invoice.paidAmount).toStringAsFixed(2));
  }

  bool _invoiceIsPaid(Invoice invoice) {
    return invoice.isCanceled != true && _invoiceRemaining(invoice) < 0.01;
  }

  bool _invoiceIsOverdue(Invoice invoice) {
    if (invoice.isCanceled == true || _invoiceIsPaid(invoice)) return false;
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      invoice.dueDate.year,
      invoice.dueDate.month,
      invoice.dueDate.day,
    );
    return dueDate.isBefore(today);
  }

  String _invoiceStatusLabel(Invoice invoice) {
    if (invoice.isCanceled == true) return 'ملغية';
    if (_invoiceIsPaid(invoice)) return 'مسددة';
    if (_invoiceIsOverdue(invoice)) return 'متأخرة';
    return 'غير مسددة';
  }

  Map<String, dynamic> _invoicePublicSummary(Invoice invoice) {
    return <String, dynamic>{
      'serialNo': invoice.serialNo,
      'amount': invoice.amount,
      'paidAmount': invoice.paidAmount,
      'remaining': _invoiceRemaining(invoice),
      'status': _invoiceStatusLabel(invoice),
      'issueDate': _fmtDate(invoice.issueDate),
      'dueDate': _fmtDate(invoice.dueDate),
      if ((invoice.paymentMethod ?? '').trim().isNotEmpty)
        'paymentMethod': invoice.paymentMethod,
      if ((invoice.note ?? '').trim().isNotEmpty) 'note': invoice.note,
    };
  }

  Invoice? _currentContractInvoice(List<Invoice> invoices) {
    final unpaid = invoices
        .where((invoice) => invoice.isCanceled != true && !_invoiceIsPaid(invoice))
        .toList(growable: false)
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (unpaid.isEmpty) return null;
    return _firstWhereOrNull(unpaid, _invoiceIsOverdue) ?? unpaid.first;
  }

  Invoice? _nextUnpaidContractInvoice(List<Invoice> invoices) {
    final unpaid = invoices
        .where((invoice) => invoice.isCanceled != true && !_invoiceIsPaid(invoice))
        .toList(growable: false)
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return unpaid.firstOrNull;
  }

  Invoice? _lastPaidContractInvoice(List<Invoice> invoices) {
    final paid = invoices
        .where((invoice) => invoice.isCanceled != true && _invoiceIsPaid(invoice))
        .toList(growable: false)
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return paid.isEmpty ? null : paid.last;
  }

  List<Invoice> _linkedContractInvoices(
    String contractId,
    Iterable<Invoice> invoices,
  ) {
    return invoices
        .where((invoice) =>
            invoice.contractId == contractId &&
            invoice.isArchived != true &&
            !_isOfficeCommissionInvoice(invoice))
        .toList(growable: false);
  }

  Map<String, dynamic> _contractInvoiceMetrics(List<Invoice> invoices) {
    final active = invoices
        .where((invoice) => invoice.isCanceled != true)
        .toList(growable: false);
    final paidInvoices = active.where(_invoiceIsPaid).length;
    final unpaidInvoices = active.where((invoice) => !_invoiceIsPaid(invoice)).length;
    final canceledInvoices = invoices.where((invoice) => invoice.isCanceled == true).length;
    final paidAmount = active.fold<double>(
      0,
      (sum, invoice) => sum + invoice.paidAmount,
    );
    final remainingTotal = active.fold<double>(
      0,
      (sum, invoice) => sum + _invoiceRemaining(invoice),
    );
    final currentInvoice = _currentContractInvoice(invoices);
    final nextUnpaidInvoice = _nextUnpaidContractInvoice(invoices);
    final lastPaidInvoice = _lastPaidContractInvoice(invoices);
    final overdueInvoicesCount = active.where(_invoiceIsOverdue).length;

    return <String, dynamic>{
      'totalInvoices': invoices.length,
      'totalInstallments': invoices.length,
      'paidInvoices': paidInvoices,
      'paidInstallments': paidInvoices,
      'unpaidInvoices': unpaidInvoices,
      'unpaidInstallments': unpaidInvoices,
      'canceledInvoices': canceledInvoices,
      'canceledInstallments': canceledInvoices,
      'paidAmount': double.parse(paidAmount.toStringAsFixed(2)),
      'remainingTotal': double.parse(remainingTotal.toStringAsFixed(2)),
      'overdueInvoicesCount': overdueInvoicesCount,
      'overdueInstallments': overdueInvoicesCount,
      if (currentInvoice != null)
        'currentInvoice': _invoicePublicSummary(currentInvoice),
      if (nextUnpaidInvoice != null) ...<String, dynamic>{
        'nextUnpaidInvoice': _invoicePublicSummary(nextUnpaidInvoice),
        'nextDueDate': _fmtDate(nextUnpaidInvoice.dueDate),
      },
      if (lastPaidInvoice != null)
        'lastPaidInvoice': _invoicePublicSummary(lastPaidInvoice),
    };
  }

  List<Map<String, dynamic>> _contractInvoicePreview(
    List<Invoice> invoices, {
    int limit = 5,
  }) {
    final sorted = invoices.toList(growable: false)
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return sorted
        .take(limit)
        .map(_invoicePublicSummary)
        .toList(growable: false);
  }

  bool _contractExpiringSoon(Contract contract) {
    if (contract.isTerminated == true) return false;
    final now = KsaTime.now();
    if (contract.endDate.isBefore(now)) return false;
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(
      contract.endDate.year,
      contract.endDate.month,
      contract.endDate.day,
    );
    final daysLeft = end.difference(today).inDays;
    return daysLeft >= 0 && daysLeft <= 30;
  }

  Map<String, dynamic> _contractPortfolioItem(
    Contract contract,
    List<Invoice> allInvoices,
  ) {
    final invoices = _linkedContractInvoices(contract.id, allInvoices);
    final metrics = _contractInvoiceMetrics(invoices);
    return <String, dynamic>{
      'serialNo': contract.serialNo,
      'tenantName': (contract.tenantSnapshot?['fullName'] ?? '').toString(),
      'propertyName': (contract.propertySnapshot?['name'] ?? '').toString(),
      'status': _contractStatusLabel(contract),
      'totalAmount': contract.totalAmount,
      'paidAmount': metrics['paidAmount'],
      'remainingAmount': metrics['remainingTotal'],
      'totalInstallments': metrics['totalInstallments'],
      'paidInstallments': metrics['paidInstallments'],
      'unpaidInstallments': metrics['unpaidInstallments'],
      'canceledInstallments': metrics['canceledInstallments'],
      'overdueInstallments': metrics['overdueInstallments'],
      'nextDueDate': metrics['nextDueDate'],
      'expiringSoon': _contractExpiringSoon(contract),
      'term': _contractTermLabel(contract.term),
      'paymentCycle': _paymentCycleLabel(contract.paymentCycle),
    };
  }

  String _getInvoicesList() {
    final box = _invoicesBox();
    if (box == null) return jsonEncode([]);
    final list = box.values
        .where((i) => i.isArchived != true)
        .take(30)
        .map((i) => {
              'serialNo': i.serialNo,
              'amount': i.amount,
              'paidAmount': i.paidAmount,
              'remaining': (i.amount - i.paidAmount),
              'isPaid': (i.amount - i.paidAmount) < 0.01,
              'isCanceled': i.isCanceled == true,
              'dueDate': _fmtDate(i.dueDate),
            })
        .toList();
    return jsonEncode(list);
  }

  String _getUnpaidInvoices() {
    final box = _invoicesBox();
    if (box == null) return jsonEncode([]);
    final now = KsaTime.now();
    final list = box.values.where((i) {
      if (i.isArchived == true || i.isCanceled == true) return false;
      return (i.amount - i.paidAmount) > 0.01;
    }).map((i) {
      final isOverdue = i.dueDate.isBefore(now);
      return {
        'serialNo': i.serialNo,
        'amount': i.amount,
        'paidAmount': i.paidAmount,
        'remaining': i.amount - i.paidAmount,
        'dueDate': _fmtDate(i.dueDate),
        'isOverdue': isOverdue,
      };
    }).toList();
    return jsonEncode(list);
  }

  // ================================================================
  //  قراءة - صيانة
  // ================================================================

  String _getMaintenanceList() {
    final box = _maintenanceBox();
    if (box == null) return jsonEncode([]);
    final list = box.values
        .where((m) => (m as dynamic).isArchived != true)
        .take(30)
        .map((m) {
      final d = m as dynamic;
      return {
        'serialNo': d.serialNo,
        'title': d.title,
        'status': d.status.toString().split('.').last,
        'priority': d.priority.toString().split('.').last,
        'cost': d.cost,
        'requestType': d.requestType,
      };
    }).toList();
    return jsonEncode(list);
  }

  String _getMaintenanceDetails(String query) {
    final m = _findMaintenance(query);
    if (m == null) return _err('لم يتم العثور على طلب صيانة');
    final d = m as dynamic;
    return jsonEncode({
      'serialNo': d.serialNo,
      'title': d.title,
      'description': d.description,
      'status': d.status.toString().split('.').last,
      'priority': d.priority.toString().split('.').last,
      'cost': d.cost,
      'requestType': d.requestType,
      'assignedTo': d.assignedTo,
      'createdAt': d.createdAt != null ? _fmtDate(d.createdAt as DateTime) : null,
      'scheduledDate':
          d.scheduledDate != null ? _fmtDate(d.scheduledDate as DateTime) : null,
      'completedDate':
          d.completedDate != null ? _fmtDate(d.completedDate as DateTime) : null,
    });
  }

  // ================================================================
  //  قراءة - مالي
  // ================================================================

  String _getTotalReceivables() {
    try {
      final total = sumReceivablesFromContractsExact(includeArchived: false);
      return jsonEncode({'totalReceivables': total});
    } catch (_) {
      return jsonEncode({'totalReceivables': 0});
    }
  }

  String _getOverdueCount() {
    final box = _contractsBox();
    if (box == null) return jsonEncode({'count': 0});
    int count = 0;
    for (final c in box.values) {
      try {
        count += countOverduePayments(c);
      } catch (_) {}
    }
    return jsonEncode({'overduePayments': count});
  }

  Future<String> _getFinancialSummary(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getDashboard(args));
  }

  Future<String> _getSettings(Map<String, dynamic> args) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _err('لا يوجد مستخدم مسجل حاليًا.');

    const defaultMsg =
        'عزيزي المستأجر، عقد الإيجار ربع السنوي ينتهي بتاريخ [التاريخ]. نرجو تأكيد رغبتك في التجديد أو إنهاء العقد.';
    const defaultMsgEnded =
        'عزيزي المستأجر، عقد الإيجار ربع السنوي انتهى بتاريخ [التاريخ].';

    final includeTemplates = args['includeTemplates'] == true;
    final userPrefs = await _readDocMap(
      FirebaseFirestore.instance.collection('user_prefs').doc(user.uid),
    );

    final workspaceUid = effectiveUid().trim();
    final canReadWorkspacePrefs = userRole == ChatUserRole.officeOwner ||
        userRole == ChatUserRole.officeStaff;
    final workspacePrefs = canReadWorkspacePrefs &&
            workspaceUid.isNotEmpty &&
            workspaceUid != 'guest' &&
            workspaceUid != user.uid
        ? await _readDocMap(
            FirebaseFirestore.instance.collection('user_prefs').doc(workspaceUid),
          )
        : const <String, dynamic>{};

    String readString(String key, String fallback) =>
        (userPrefs[key] ?? fallback).toString();
    int yearDays(String key, int fallback) =>
        _toIntValue(userPrefs[key], fallback).clamp(1, 45);

    final annualYears = <int, int>{
      for (var y = 1; y <= 10; y++)
        y: yearDays(
          'notif_annual_${y}y_days',
          _toIntValue(userPrefs['notif_annual_days'], 45),
        ),
    };
    final contractAnnualYears = <int, int>{
      for (var y = 1; y <= 10; y++)
        y: yearDays(
          'notif_contract_annual_${y}y_days',
          _toIntValue(
            userPrefs['notif_contract_annual_days'],
            annualYears[y] ?? 45,
          ),
        ),
    };

    final dailyContractEndHour = _normalizeHour24(
      workspacePrefs['daily_contract_end_hour'] ??
          userPrefs['daily_contract_end_hour'],
    );
    final language = readString('settings_language', 'ar');
    final dateSystem = readString('settings_date_system', 'gregorian');

    final payload = <String, dynamic>{
      'screen': 'settings',
      'title': 'الإعدادات',
      'supportsChatWrite': AiChatPermissions.canExecuteWriteOperations(userRole),
      'editableSections': <String>[
        'language',
        'calendar',
        'payment_notifications',
        'contract_notifications',
        'message_templates',
        'daily_contract_end_hour',
      ],
      'language': language,
      'languageLabel': language == 'en' ? 'الإنجليزية' : 'العربية',
      'dateSystem': dateSystem,
      'dateSystemLabel': dateSystem == 'hijri' ? 'هجري' : 'ميلادي',
      'paymentNotifications': <String, dynamic>{
        'monthlyDays': _toIntValue(userPrefs['notif_monthly_days'], 7),
        'quarterlyDays': _toIntValue(userPrefs['notif_quarterly_days'], 15),
        'semiAnnualDays': _toIntValue(userPrefs['notif_semiannual_days'], 30),
        'annualDays': annualYears[1] ?? 45,
        'annualYearsDays': annualYears.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      },
      'contractNotifications': <String, dynamic>{
        'monthlyDays': _toIntValue(
          userPrefs['notif_contract_monthly_days'],
          _toIntValue(userPrefs['notif_monthly_days'], 7),
        ),
        'quarterlyDays': _toIntValue(
          userPrefs['notif_contract_quarterly_days'],
          _toIntValue(userPrefs['notif_quarterly_days'], 15),
        ),
        'semiAnnualDays': _toIntValue(
          userPrefs['notif_contract_semiannual_days'],
          _toIntValue(userPrefs['notif_semiannual_days'], 30),
        ),
        'annualDays': contractAnnualYears[1] ?? (annualYears[1] ?? 45),
        'annualYearsDays': contractAnnualYears.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        'dailyContractEndHour': dailyContractEndHour,
        'dailyContractEndTimeLabel': _hour24Label(dailyContractEndHour),
      },
      'source': <String, dynamic>{
        'userPrefsUid': user.uid,
        'workspacePrefsUid': workspacePrefs.isEmpty ? null : workspaceUid,
        'usesWorkspaceOverrideForDailyContractHour': workspacePrefs.isNotEmpty,
      },
    };

    if (includeTemplates) {
      payload['messageTemplates'] = <String, dynamic>{
        'paymentsBefore': <String, dynamic>{
          'monthly': readString(
            'notif_monthly_msg_before',
            readString('notif_monthly_msg', defaultMsg),
          ),
          'quarterly': readString(
            'notif_quarterly_msg_before',
            readString('notif_quarterly_msg', defaultMsg),
          ),
          'semiAnnual': readString(
            'notif_semiannual_msg_before',
            readString('notif_semiannual_msg', defaultMsg),
          ),
          'annual': readString(
            'notif_annual_msg_before',
            readString('notif_annual_msg', defaultMsg),
          ),
        },
        'paymentsOn': <String, dynamic>{
          'monthly': readString('notif_monthly_msg_on', defaultMsgEnded),
          'quarterly': readString('notif_quarterly_msg_on', defaultMsgEnded),
          'semiAnnual': readString('notif_semiannual_msg_on', defaultMsgEnded),
          'annual': readString('notif_annual_msg_on', defaultMsgEnded),
        },
        'contractsBefore': <String, dynamic>{
          'monthly': readString(
            'notif_contract_monthly_msg_before',
            readString('notif_monthly_msg_before', defaultMsg),
          ),
          'quarterly': readString(
            'notif_contract_quarterly_msg_before',
            readString('notif_quarterly_msg_before', defaultMsg),
          ),
          'semiAnnual': readString(
            'notif_contract_semiannual_msg_before',
            readString('notif_semiannual_msg_before', defaultMsg),
          ),
          'annual': readString(
            'notif_contract_annual_msg_before',
            readString('notif_annual_msg_before', defaultMsg),
          ),
        },
      };
    }

    return jsonEncode(payload);
  }

  Future<String> _updateSettings(Map<String, dynamic> args) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _err('لا يوجد مستخدم مسجل حاليًا.');

    final payload = <String, dynamic>{};
    final issues = <Map<String, String>>[];

    int? parseIntArg(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
      return null;
    }

    String? parseTemplateText(Object? raw) {
      if (raw == null) return null;
      return raw.toString();
    }

    void addIssue(String field, String label, String message) {
      issues.add(<String, String>{
        'field': field,
        'label': label,
        'message': message,
      });
    }

    final language = _normalizeSettingsLanguage(args['language']);
    if (args.containsKey('language')) {
      if (language == null) {
        addIssue('language', 'اللغة', 'قيمة اللغة يجب أن تكون ar أو en.');
      } else {
        payload['settings_language'] = language;
      }
    }

    final dateSystem = _normalizeSettingsDateSystem(args['dateSystem']);
    if (args.containsKey('dateSystem')) {
      if (dateSystem == null) {
        addIssue(
          'dateSystem',
          'نظام التاريخ',
          'قيمة نظام التاريخ يجب أن تكون gregorian أو hijri.',
        );
      } else {
        payload['settings_date_system'] = dateSystem;
      }
    }

    void collectBoundedInt({
      required String argKey,
      required String storeKey,
      required String label,
      required int min,
      required int max,
    }) {
      if (!args.containsKey(argKey)) return;
      final value = parseIntArg(args[argKey]);
      if (value == null || value < min || value > max) {
        addIssue(
          argKey,
          label,
          'قيمة $label يجب أن تكون بين $min و $max.',
        );
        return;
      }
      payload[storeKey] = value;
    }

    void collectYearDaysMap({
      required String argKey,
      required String baseStoreKey,
      required String storePrefix,
      required String label,
    }) {
      if (!args.containsKey(argKey)) return;
      final rawMap = _coerceJsonObject(args[argKey]);
      if (rawMap.isEmpty) {
        addIssue(
          argKey,
          label,
          'يجب إرسال $label على شكل خريطة تحتوي مفاتيح السنوات من 1 إلى 10.',
        );
        return;
      }
      var hasAny = false;
      for (var year = 1; year <= 10; year++) {
        final key = year.toString();
        if (!rawMap.containsKey(key)) continue;
        hasAny = true;
        final value = parseIntArg(rawMap[key]);
        if (value == null || value < 1 || value > 45) {
          addIssue(
            '$argKey.$key',
            '$label السنة $year',
            'قيمة $label للسنة $year يجب أن تكون بين 1 و45.',
          );
          continue;
        }
        payload['${storePrefix}${year}y_days'] = value;
        if (year == 1) payload[baseStoreKey] = value;
      }
      if (!hasAny) {
        addIssue(
          argKey,
          label,
          'لم يتم تمرير أي سنة صالحة داخل $label.',
        );
      }
    }

    void collectTemplateGroup({
      required String argKey,
      required String label,
      required Map<String, String> storeKeys,
    }) {
      if (!args.containsKey(argKey)) return;
      final rawMap = _coerceJsonObject(args[argKey]);
      if (rawMap.isEmpty) {
        addIssue(
          argKey,
          label,
          'يجب إرسال $label على شكل خريطة تحتوي monthly و quarterly و semiAnnual و annual.',
        );
        return;
      }
      var hasAny = false;
      for (final entry in storeKeys.entries) {
        if (!rawMap.containsKey(entry.key)) continue;
        final text = parseTemplateText(rawMap[entry.key]);
        if (text == null) {
          addIssue(
            '$argKey.${entry.key}',
            '$label ${entry.key}',
            'النص المطلوب في ${entry.key} غير صالح.',
          );
          continue;
        }
        payload[entry.value] = text;
        hasAny = true;
      }
      if (!hasAny) {
        addIssue(
          argKey,
          label,
          'لم يتم تمرير أي قالب صالح داخل $label.',
        );
      }
    }

    collectBoundedInt(
      argKey: 'monthlyDays',
      storeKey: 'notif_monthly_days',
      label: 'أيام التنبيه الشهري',
      min: 1,
      max: 7,
    );
    collectBoundedInt(
      argKey: 'quarterlyDays',
      storeKey: 'notif_quarterly_days',
      label: 'أيام التنبيه الربع سنوي',
      min: 1,
      max: 15,
    );
    collectBoundedInt(
      argKey: 'semiAnnualDays',
      storeKey: 'notif_semiannual_days',
      label: 'أيام التنبيه النصف سنوي',
      min: 1,
      max: 30,
    );
    collectBoundedInt(
      argKey: 'annualDays',
      storeKey: 'notif_annual_days',
      label: 'أيام التنبيه السنوي',
      min: 1,
      max: 45,
    );
    collectBoundedInt(
      argKey: 'contractMonthlyDays',
      storeKey: 'notif_contract_monthly_days',
      label: 'أيام تنبيه العقود الشهرية',
      min: 1,
      max: 7,
    );
    collectBoundedInt(
      argKey: 'contractQuarterlyDays',
      storeKey: 'notif_contract_quarterly_days',
      label: 'أيام تنبيه العقود الربع سنوية',
      min: 1,
      max: 15,
    );
    collectBoundedInt(
      argKey: 'contractSemiAnnualDays',
      storeKey: 'notif_contract_semiannual_days',
      label: 'أيام تنبيه العقود النصف سنوية',
      min: 1,
      max: 30,
    );
    collectBoundedInt(
      argKey: 'contractAnnualDays',
      storeKey: 'notif_contract_annual_days',
      label: 'أيام تنبيه العقود السنوية',
      min: 1,
      max: 45,
    );
    collectBoundedInt(
      argKey: 'dailyContractEndHour',
      storeKey: 'daily_contract_end_hour',
      label: 'ساعة الإرسال اليومية',
      min: 0,
      max: 23,
    );
    collectYearDaysMap(
      argKey: 'annualYearsDays',
      baseStoreKey: 'notif_annual_days',
      storePrefix: 'notif_annual_',
      label: 'أيام التنبيه السنوي حسب السنوات',
    );
    collectYearDaysMap(
      argKey: 'contractAnnualYearsDays',
      baseStoreKey: 'notif_contract_annual_days',
      storePrefix: 'notif_contract_annual_',
      label: 'أيام تنبيه العقود السنوي حسب السنوات',
    );
    collectTemplateGroup(
      argKey: 'paymentTemplatesBefore',
      label: 'قوالب دفعات قبل الاستحقاق',
      storeKeys: const <String, String>{
        'monthly': 'notif_monthly_msg_before',
        'quarterly': 'notif_quarterly_msg_before',
        'semiAnnual': 'notif_semiannual_msg_before',
        'annual': 'notif_annual_msg_before',
      },
    );
    collectTemplateGroup(
      argKey: 'paymentTemplatesOn',
      label: 'قوالب دفعات يوم الاستحقاق',
      storeKeys: const <String, String>{
        'monthly': 'notif_monthly_msg_on',
        'quarterly': 'notif_quarterly_msg_on',
        'semiAnnual': 'notif_semiannual_msg_on',
        'annual': 'notif_annual_msg_on',
      },
    );
    collectTemplateGroup(
      argKey: 'contractTemplatesBefore',
      label: 'قوالب العقود قبل الانتهاء',
      storeKeys: const <String, String>{
        'monthly': 'notif_contract_monthly_msg_before',
        'quarterly': 'notif_contract_quarterly_msg_before',
        'semiAnnual': 'notif_contract_semiannual_msg_before',
        'annual': 'notif_contract_annual_msg_before',
      },
    );

    if (issues.isNotEmpty) {
      return jsonEncode(<String, dynamic>{
        'error': issues.first['message'] ?? 'تعذر تعديل الإعدادات بسبب بيانات غير صالحة.',
        'suggestedScreen': 'settings',
        'missingFields': issues,
      });
    }

    if (payload.isEmpty) {
      return _err('لم يتم تقديم أي حقول صالحة لتعديل الإعدادات.');
    }

    final currentPrefs = await _readDocMap(
      FirebaseFirestore.instance.collection('user_prefs').doc(user.uid),
    );
    final finalMonthlyDays =
        payload['notif_monthly_days'] ?? _toIntValue(currentPrefs['notif_monthly_days'], 7);
    final finalQuarterlyDays = payload['notif_quarterly_days'] ??
        _toIntValue(currentPrefs['notif_quarterly_days'], 15);
    final finalSemiAnnualDays = payload['notif_semiannual_days'] ??
        _toIntValue(currentPrefs['notif_semiannual_days'], 30);
    final finalAnnualDays =
        payload['notif_annual_days'] ?? _toIntValue(currentPrefs['notif_annual_days'], 45);

    try {
      await FirebaseFirestore.instance
          .collection('user_prefs')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      if (payload.containsKey('daily_contract_end_hour')) {
        final workspaceUid = effectiveUid().trim();
        if (workspaceUid.isNotEmpty && workspaceUid != 'guest') {
          await FirebaseFirestore.instance
              .collection('user_prefs')
              .doc(workspaceUid)
              .set(
            <String, dynamic>{
              'uid': workspaceUid,
              'daily_contract_end_hour': payload['daily_contract_end_hour'],
            },
            SetOptions(merge: true),
          );
        }
      }

      if (payload.containsKey('settings_date_system')) {
        final dateValue = payload['settings_date_system'].toString();
        final isHijri = dateValue == 'hijri';
        await _putValuesIfBoxOpen('settingsBox', <String, dynamic>{
          if (payload.containsKey('settings_language'))
            'settings_language': payload['settings_language'],
          'settings_date_system': dateValue,
          'isHijri': isHijri,
          'useHijri': isHijri,
          'calendar': isHijri ? 'hijri' : 'gregorian',
          'dateMode': isHijri ? 'hijri' : 'gregorian',
          'calendarMode': isHijri ? 'hijri' : 'gregorian',
          'dateCalendar': isHijri ? 'hijri' : 'gregorian',
        });
        await _putValuesIfBoxOpen('sessionBox', <String, dynamic>{
          if (payload.containsKey('settings_language'))
            'settings_language': payload['settings_language'],
          'isHijri': isHijri,
          'useHijri': isHijri,
          'calendar': isHijri ? 'hijri' : 'gregorian',
          'dateMode': isHijri ? 'hijri' : 'gregorian',
          'calendarMode': isHijri ? 'hijri' : 'gregorian',
          'dateCalendar': isHijri ? 'hijri' : 'gregorian',
        });
      } else if (payload.containsKey('settings_language')) {
        await _putValuesIfBoxOpen('settingsBox', <String, dynamic>{
          'settings_language': payload['settings_language'],
        });
        await _putValuesIfBoxOpen('sessionBox', <String, dynamic>{
          'settings_language': payload['settings_language'],
        });
      }

      if (payload.containsKey('daily_contract_end_hour')) {
        await _putValuesIfBoxOpen('sessionBox', <String, dynamic>{
          'daily_contract_end_hour': payload['daily_contract_end_hour'],
        });
      }

      if (payload.keys.any((key) => key.startsWith('notif_'))) {
        await _putValuesIfBoxOpen('sessionBox', <String, dynamic>{
          'dueSoonMonthly': finalMonthlyDays,
          'dueSoonQuarterly': finalQuarterlyDays,
          'dueSoonSemiannual': finalSemiAnnualDays,
          'dueSoonAnnual': finalAnnualDays,
        });
      }

      Map<String, int>? buildAppliedYears(String prefix) {
        final result = <String, int>{};
        for (var year = 1; year <= 10; year++) {
          final key = '${prefix}${year}y_days';
          if (!payload.containsKey(key)) continue;
          result[year.toString()] = _toIntValue(payload[key], 0);
        }
        return result.isEmpty ? null : result;
      }

      Map<String, String>? buildAppliedTemplates(
        Map<String, String> storeKeys,
      ) {
        final result = <String, String>{};
        for (final entry in storeKeys.entries) {
          if (!payload.containsKey(entry.value)) continue;
          result[entry.key] = payload[entry.value].toString();
        }
        return result.isEmpty ? null : result;
      }

      final appliedAnnualYears = buildAppliedYears('notif_annual_');
      final appliedContractAnnualYears =
          buildAppliedYears('notif_contract_annual_');
      final appliedPaymentBefore = buildAppliedTemplates(
        const <String, String>{
          'monthly': 'notif_monthly_msg_before',
          'quarterly': 'notif_quarterly_msg_before',
          'semiAnnual': 'notif_semiannual_msg_before',
          'annual': 'notif_annual_msg_before',
        },
      );
      final appliedPaymentOn = buildAppliedTemplates(
        const <String, String>{
          'monthly': 'notif_monthly_msg_on',
          'quarterly': 'notif_quarterly_msg_on',
          'semiAnnual': 'notif_semiannual_msg_on',
          'annual': 'notif_annual_msg_on',
        },
      );
      final appliedContractsBefore = buildAppliedTemplates(
        const <String, String>{
          'monthly': 'notif_contract_monthly_msg_before',
          'quarterly': 'notif_contract_quarterly_msg_before',
          'semiAnnual': 'notif_contract_semiannual_msg_before',
          'annual': 'notif_contract_annual_msg_before',
        },
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم تحديث الإعدادات بنجاح.',
        'applied': <String, dynamic>{
          if (payload.containsKey('settings_language'))
            'language': payload['settings_language'],
          if (payload.containsKey('settings_date_system'))
            'dateSystem': payload['settings_date_system'],
          if (payload.containsKey('notif_monthly_days'))
            'monthlyDays': payload['notif_monthly_days'],
          if (payload.containsKey('notif_quarterly_days'))
            'quarterlyDays': payload['notif_quarterly_days'],
          if (payload.containsKey('notif_semiannual_days'))
            'semiAnnualDays': payload['notif_semiannual_days'],
          if (payload.containsKey('notif_annual_days'))
            'annualDays': payload['notif_annual_days'],
          if (payload.containsKey('notif_contract_monthly_days'))
            'contractMonthlyDays': payload['notif_contract_monthly_days'],
          if (payload.containsKey('notif_contract_quarterly_days'))
            'contractQuarterlyDays': payload['notif_contract_quarterly_days'],
          if (payload.containsKey('notif_contract_semiannual_days'))
            'contractSemiAnnualDays': payload['notif_contract_semiannual_days'],
          if (payload.containsKey('notif_contract_annual_days'))
            'contractAnnualDays': payload['notif_contract_annual_days'],
          if (payload.containsKey('daily_contract_end_hour'))
            'dailyContractEndHour': payload['daily_contract_end_hour'],
          if (appliedAnnualYears != null) 'annualYearsDays': appliedAnnualYears,
          if (appliedContractAnnualYears != null)
            'contractAnnualYearsDays': appliedContractAnnualYears,
          if (appliedPaymentBefore != null)
            'paymentTemplatesBefore': appliedPaymentBefore,
          if (appliedPaymentOn != null) 'paymentTemplatesOn': appliedPaymentOn,
          if (appliedContractsBefore != null)
            'contractTemplatesBefore': appliedContractsBefore,
        },
      });
    } catch (e) {
      return _err('تعذر تحديث الإعدادات: $e');
    }
  }

  // ================================================================
  //  وحدات المبنى
  // ================================================================

  String _getBuildingUnits(String buildingName) {
    final box = _propertiesBox();
    if (box == null) return _err('لا توجد بيانات');
    final q = buildingName.trim().toLowerCase();
    final building = box.values.cast<Property>().where((p) {
      return p.name.toLowerCase().contains(q) &&
          p.type == PropertyType.building &&
          p.isArchived != true;
    }).firstOrNull;
    if (building == null) return _err('لم يتم العثور على مبنى بهذا الاسم');

    final units = box.values
        .cast<Property>()
        .where((p) => p.parentBuildingId == building.id && p.isArchived != true)
        .map((u) => {
              'name': u.name,
              'type': u.type.toString().split('.').last,
              'rooms': u.rooms,
              'area': u.area,
              'price': u.price,
            })
        .toList();

    return jsonEncode({
      'building': building.name,
      'totalUnits': building.totalUnits,
      'occupiedUnits': building.occupiedUnits,
      'units': units,
    });
  }

  // ================================================================
  //  فواتير/سندات - فلترة ومحفوظات
  // ================================================================

  String _getBuildingUnitsV2(String buildingName) {
    final all = _activePropertiesList();
    if (all.isEmpty) return _err('لا توجد بيانات');
    final q = buildingName.trim().toLowerCase();
    final building = all.where((property) {
      return property.name.toLowerCase().contains(q) &&
          property.type == PropertyType.building &&
          property.isArchived != true;
    }).firstOrNull;
    if (building == null) return _err('لم يتم العثور على مبنى بهذا الاسم');

    final units = _buildingUnitsFor(building, all)
        .map((unit) => {
              'name': unit.name,
              'type': unit.type.name,
              'typeLabel': unit.type.label,
              'rooms': unit.rooms,
              'roomsLabel': 'غرف',
              'area': unit.area,
              'price': unit.price,
              'isOccupied': unit.occupiedUnits > 0,
              'occupancyLabel': unit.occupiedUnits > 0 ? 'مشغولة' : 'خالية',
            })
        .toList(growable: false);

    return jsonEncode({
      'building': building.name,
      'buildingTypeLabel': building.type.label,
      'managementMode': _isPerUnitBuilding(building) ? 'units' : 'whole_building',
      'managementModeLabel':
          _isPerUnitBuilding(building) ? 'إدارة بالوحدات' : 'تأجير كامل العمارة',
      'totalUnits': _configuredUnitsForBuilding(building, all),
      'registeredUnits': _registeredUnitsForBuilding(building, all),
      'occupiedUnits': _occupiedUnitsForBuilding(building, all),
      'vacantUnits': _vacantUnitsForBuilding(building, all),
      'countsLabel': 'وحدات',
      'semanticSummary':
          'هذه عمارة ذات وحدات، وعدد الوحدات المسجلة ${_registeredUnitsForBuilding(building, all).toString()}، والمشغول ${_occupiedUnitsForBuilding(building, all).toString()}، والخالي ${_vacantUnitsForBuilding(building, all).toString()}.',
      'units': units,
    });
  }

  String _getInvoicesByType(String origin) {
    final box = _invoicesBox();
    if (box == null) return jsonEncode([]);

    final all = box.values.where((i) => i.isArchived != true);
    Iterable<Invoice> filtered;

    switch (origin.toLowerCase()) {
      case 'contract':
        filtered = all.where((i) =>
            i.contractId.isNotEmpty &&
            (i.maintenanceRequestId == null || i.maintenanceRequestId!.isEmpty));
        break;
      case 'maintenance':
        filtered = all.where((i) =>
            i.maintenanceRequestId != null && i.maintenanceRequestId!.isNotEmpty);
        break;
      case 'manual':
        filtered = all.where((i) => i.contractId.isEmpty);
        break;
      default:
        filtered = all;
    }

    final list = filtered.take(30).map((i) => {
          'serialNo': i.serialNo,
          'amount': i.amount,
          'paidAmount': i.paidAmount,
          'remaining': i.amount - i.paidAmount,
          'isPaid': (i.amount - i.paidAmount) < 0.01,
          'isCanceled': i.isCanceled == true,
          'dueDate': _fmtDate(i.dueDate),
          'origin': i.maintenanceRequestId != null &&
                  i.maintenanceRequestId!.isNotEmpty
              ? 'خدمات'
              : i.contractId.isNotEmpty
                  ? 'عقد'
                  : 'يدوي',
        }).toList();
    return jsonEncode(list);
  }

  String _getInvoicePaymentHistory(String serialNo) {
    final box = _invoicesBox();
    if (box == null) return _err('لا توجد بيانات');
    final serial = serialNo.trim();
    final inv = box.values.where((i) => i.serialNo == serial).firstOrNull;
    if (inv == null) return _err('لم يتم العثور على فاتورة بالرقم $serial');

    return jsonEncode({
      'serialNo': inv.serialNo,
      'amount': inv.amount,
      'paidAmount': inv.paidAmount,
      'remaining': _invoiceRemaining(inv),
      'status': _invoiceStatusLabel(inv),
      'isPaid': _invoiceIsPaid(inv),
      'isCanceled': inv.isCanceled == true,
      if ((inv.paymentMethod ?? '').trim().isNotEmpty)
        'paymentMethod': inv.paymentMethod,
      if ((inv.note ?? '').trim().isNotEmpty) 'note': inv.note,
      'issueDate': _fmtDate(inv.issueDate),
      'dueDate': _fmtDate(inv.dueDate),
    });
  }

  String _getContractInvoiceHistory(String query) {
    final contract = _findContract(query);
    if (contract == null) return _err('لم يتم العثور على عقد بهذا المرجع');

    final box = _invoicesBox();
    if (box == null) return _err('لا توجد بيانات فواتير متاحة');

    final items = box.values
        .where((invoice) =>
            invoice.contractId == contract.id &&
            invoice.isArchived != true &&
            !_isOfficeCommissionInvoice(invoice))
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final metrics = _contractInvoiceMetrics(items);

    return jsonEncode(<String, dynamic>{
      'screen': 'invoices_history',
      'title': 'سجل سندات العقد',
      'contract': <String, dynamic>{
        'serialNo': contract.serialNo,
        'tenantName': (contract.tenantSnapshot?['fullName'] ?? '').toString(),
        'propertyName': (contract.propertySnapshot?['name'] ?? '').toString(),
        'status': _contractStatusLabel(contract),
        'startDate': _fmtDate(contract.startDate),
        'endDate': _fmtDate(contract.endDate),
      },
      'summary': <String, dynamic>{
        ...metrics,
      },
      'installmentsSummary': <String, dynamic>{
        'totalInstallments': metrics['totalInstallments'],
        'paidInstallments': metrics['paidInstallments'],
        'unpaidInstallments': metrics['unpaidInstallments'],
        'canceledInstallments': metrics['canceledInstallments'],
        'overdueInstallments': metrics['overdueInstallments'],
        'remainingTotal': metrics['remainingTotal'],
      },
      'history': items
          .map((invoice) => <String, dynamic>{
                'serialNo': invoice.serialNo,
                'amount': invoice.amount,
                'paidAmount': invoice.paidAmount,
                'remaining': _invoiceRemaining(invoice),
                'status': _invoiceStatusLabel(invoice),
                'issueDate': _fmtDate(invoice.issueDate),
                'dueDate': _fmtDate(invoice.dueDate),
                'isCanceled': invoice.isCanceled == true,
                'isPaid': _invoiceIsPaid(invoice),
                if ((invoice.paymentMethod ?? '').trim().isNotEmpty)
                  'paymentMethod': invoice.paymentMethod,
                if ((invoice.note ?? '').trim().isNotEmpty) 'note': invoice.note,
              })
          .toList(growable: false),
      if (metrics.containsKey('currentInvoice'))
        'paymentActionHint':
            'إذا طلب المستخدم سداد الدفعة الحالية فالمقصود السند رقم ${((metrics['currentInvoice'] as Map?)?['serialNo'] ?? '').toString()}.',
    });
  }

  // ================================================================
  //  الإشعارات
  // ================================================================

  String _normalizeNotificationKind(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'contract_started_today':
      case 'contract_expiring':
      case 'contract_ended':
      case 'contract_due_soon':
      case 'contract_due_today':
      case 'contract_due_overdue':
      case 'invoice_overdue':
      case 'maintenance_today':
      case 'service_start':
      case 'service_due':
        return value;
      case 'invoice_due_soon':
        return 'invoice_overdue';
      case 'maintenance_open':
        return 'maintenance_today';
      default:
        return 'all';
    }
  }

  String _getNotificationsLegacy(Map<String, dynamic> args) {
    final requestedKind = _normalizeNotificationKind(args['kind']);
    final limit = _toIntValue(args['limit'], 30).clamp(1, 100);
    final now = KsaTime.now();
    final alerts = <Map<String, dynamic>>[];

    // عقود قريبة الانتهاء (30 يوم)
    final cBox = _contractsBox();
    if (cBox != null) {
      for (final c in cBox.values) {
        final d = c as dynamic;
        if (d.isArchived == true || d.isTerminated == true) continue;
        final end = d.endDate as DateTime;
        final diff = end.difference(now).inDays;
        if (diff >= 0 && diff <= 30) {
          alerts.add({
            'type': 'contract_expiring',
            'serialNo': d.serialNo,
            'tenantName': d.tenantSnapshot?['fullName'] ?? '',
            'endDate': _fmtDate(end),
            'message':
                'عقد ${d.serialNo} (${d.tenantSnapshot?['fullName'] ?? ''}) ينتهي بعد $diff يوم',
            'daysLeft': diff,
          });
        }
      }
    }

    // فواتير متأخرة
    final iBox = _invoicesBox();
    if (iBox != null) {
      for (final i in iBox.values) {
        if (i.isArchived == true || i.isCanceled == true) continue;
        if ((i.amount - i.paidAmount) < 0.01) continue;
        final diff = now.difference(i.dueDate).inDays;
        if (diff > 0) {
          alerts.add({
            'type': 'invoice_overdue',
            'serialNo': i.serialNo,
            'dueDate': _fmtDate(i.dueDate),
            'remaining': (i.amount - i.paidAmount).toStringAsFixed(2),
            'message':
                'فاتورة ${i.serialNo} متأخرة منذ $diff يوم (المتبقي: ${(i.amount - i.paidAmount).toStringAsFixed(2)} ريال)',
            'daysOverdue': diff,
          });
        } else if (diff >= -7) {
          alerts.add({
            'type': 'invoice_due_soon',
            'serialNo': i.serialNo,
            'dueDate': _fmtDate(i.dueDate),
            'remaining': (i.amount - i.paidAmount).toStringAsFixed(2),
            'message':
                'فاتورة ${i.serialNo} مستحقة بعد ${-diff} يوم (المبلغ: ${(i.amount - i.paidAmount).toStringAsFixed(2)} ريال)',
            'daysLeft': -diff,
          });
        }
      }
    }

    // صيانة مفتوحة
    final mBox = _maintenanceBox();
    if (mBox != null) {
      for (final m in mBox.values) {
        final d = m as dynamic;
        if (d.isArchived == true) continue;
        if (d.status == MaintenanceStatus.open) {
          alerts.add({
            'type': 'maintenance_open',
            'serialNo': d.serialNo,
            'title': d.title,
            'message': 'طلب صيانة مفتوح: ${d.title} (${d.serialNo})',
          });
        }
      }
    }

    final svcBox = _servicesBox();
    if (svcBox != null) {
      final today = DateTime(now.year, now.month, now.day);
      for (final rawKey in svcBox.keys) {
        final raw = svcBox.get(rawKey);
        if (raw is! Map) continue;
        final cfg = Map<String, dynamic>.from(raw);
        final key = rawKey.toString();
        final parts = key.split('::');
        if (parts.length < 2) continue;

        final propertyId = parts.first.trim();
        final serviceType = _normalizeServiceType(
          cfg['serviceType'] ?? parts.last,
        );
        if (!_serviceTypes.contains(serviceType)) continue;

        final due = _parseDate(
          (cfg['nextDueDate'] ?? cfg['nextServiceDate'] ?? '').toString(),
        );
        if (due == null) continue;

        final dueDate = DateTime(due.year, due.month, due.day);
        final diff = dueDate.difference(today).inDays;
        final remindBeforeDays =
            _toIntValue(cfg['remindBeforeDays'], 0).clamp(0, 3);

        if (diff > 0 && (remindBeforeDays == 0 || diff > remindBeforeDays)) {
          continue;
        }

        final propertyName = _findPropertyById(propertyId)?.name ?? propertyId;
        final providerName =
            (cfg['providerName'] ?? cfg['provider'] ?? '').toString().trim();

        final alert = <String, dynamic>{
          'type': 'service_due',
          'propertyName': propertyName,
          'serviceType': serviceType,
          'serviceLabel': _serviceLabel(serviceType),
          'providerName': providerName,
          'dueDate': _fmtDate(dueDate),
        };
        if (diff < 0) {
          alert['daysOverdue'] = -diff;
          alert['message'] =
              '${_serviceLabel(serviceType)} في العقار "$propertyName" متأخرة منذ ${-diff} يوم.';
        } else if (diff == 0) {
          alert['daysLeft'] = 0;
          alert['message'] =
              'اليوم موعد ${_serviceLabel(serviceType)} في العقار "$propertyName".';
        } else {
          alert['daysLeft'] = diff;
          alert['message'] =
              '${_serviceLabel(serviceType)} في العقار "$propertyName" بعد $diff يوم.';
        }
        alerts.add(alert);
      }
    }

    if (alerts.isEmpty) {
      return jsonEncode({'info': 'لا توجد إشعارات حالياً. كل شيء على ما يرام.'});
    }

    final filtered = requestedKind == 'all'
        ? alerts
        : alerts
            .where((item) => (item['type'] ?? '').toString() == requestedKind)
            .toList(growable: false);

    if (filtered.isEmpty) {
      return jsonEncode(<String, dynamic>{
        'info': 'لا توجد إشعارات مطابقة لهذا النوع حاليًا.',
        'kind': requestedKind,
      });
    }

    final counts = <String, int>{};
    for (final item in filtered) {
      final type = (item['type'] ?? '').toString();
      counts[type] = (counts[type] ?? 0) + 1;
    }

    return jsonEncode(<String, dynamic>{
      'kind': requestedKind,
      'total': filtered.length,
      'counts': counts,
      'notifications': filtered.take(limit).toList(growable: false),
    });
  }

  // ================================================================
  //  التقارير التفصيلية
  // ================================================================

  String _getNotifications(Map<String, dynamic> args) {
    final requestedKind = _normalizeNotificationKind(args['kind']);
    final limit = _toIntValue(args['limit'], 30).clamp(1, 100).toInt();
    final rawIncludeDismissed = args['includeDismissed'];
    final includeDismissed = rawIncludeDismissed == true ||
        <String>{'1', 'true', 'yes', 'y', 'on'}
            .contains((rawIncludeDismissed ?? '').toString().trim().toLowerCase());
    final today = _notificationDateOnly(KsaTime.now());
    final notifications = <Map<String, dynamic>>[];

    void addNotification({
      required String kind,
      required DateTime anchor,
      required String title,
      required String subtitle,
      required String message,
      DateTime? sortAt,
      String? contractId,
      String? invoiceId,
      String? maintenanceId,
      String? propertyId,
      String? serviceType,
      String? serviceTargetId,
      Map<String, dynamic>? extra,
    }) {
      final refData = _notificationRefPayload(
        kind: kind,
        anchor: anchor,
        contractId: contractId,
        invoiceId: invoiceId,
        maintenanceId: maintenanceId,
        propertyId: propertyId,
        serviceType: serviceType,
        serviceTargetId: serviceTargetId,
      );
      final dismissed = _notificationIsDismissed(refData);
      if (!includeDismissed && dismissed) return;

      notifications.add(<String, dynamic>{
        'kind': kind,
        'kindLabel': _notificationKindLabel(kind),
        'title': title,
        'subtitle': subtitle,
        'message': message,
        'anchorDate': _fmtDate(_notificationDateOnly(anchor)),
        'anchorDateIso': _notificationDateOnly(anchor).toIso8601String(),
        'sortAt': _notificationDateOnly(sortAt ?? anchor).toIso8601String(),
        'dismissed': dismissed,
        'notificationRef': _encodeNotificationRef(refData),
        if ((contractId ?? '').trim().isNotEmpty) 'contractId': contractId,
        if ((invoiceId ?? '').trim().isNotEmpty) 'invoiceId': invoiceId,
        if ((maintenanceId ?? '').trim().isNotEmpty)
          'maintenanceId': maintenanceId,
        if ((propertyId ?? '').trim().isNotEmpty) 'propertyId': propertyId,
        if ((serviceType ?? '').trim().isNotEmpty) 'serviceType': serviceType,
        if ((serviceTargetId ?? '').trim().isNotEmpty)
          'serviceTargetId': serviceTargetId,
        if (extra != null) ...extra,
      });
    }

    String contractDisplayName(Contract contract) {
      final tenant = (contract.tenantSnapshot?['fullName'] ?? '')
          .toString()
          .trim();
      if (tenant.isNotEmpty) return tenant;
      return 'العميل';
    }

    bool contractExistedBeforeToday(Contract contract) {
      final cid = contract.id.trim();
      if (cid.isEmpty) {
        return _notificationDateOnly(contract.createdAt).isBefore(today);
      }
      final knownAt = _notificationParseConfigDate(
        _notificationsKnownContractsBox()?.get(cid),
      );
      if (knownAt != null) return knownAt.isBefore(today);
      return _notificationDateOnly(contract.createdAt).isBefore(today);
    }

    final cBox = _contractsBox();
    if (cBox != null) {
      for (final c in cBox.values) {
        if (c.isArchived == true || c.isTerminated == true) continue;
        final cid = c.id.trim();
        final serial = (c.serialNo ?? '').trim();
        final tenantName = contractDisplayName(c);

        final start = _notificationDateOnly(c.startDate);
        if (start == today && contractExistedBeforeToday(c)) {
          addNotification(
            kind: 'contract_started_today',
            anchor: start,
            sortAt: today,
            contractId: cid,
            title: 'اليوم يبدأ عقد جديد',
            subtitle: 'تاريخ البداية: ${_fmtDate(start)}',
            message: serial.isEmpty
                ? 'اليوم يبدأ عقد جديد للعميل $tenantName.'
                : 'اليوم يبدأ العقد $serial للعميل $tenantName.',
            extra: <String, dynamic>{
              if (serial.isNotEmpty) 'serialNo': serial,
              'tenantName': tenantName,
            },
          );
        }

        final end = _notificationDateOnly(c.endDate);
        final daysToEnd = _notificationDaysBetween(today, end);
        if (end.isBefore(today)) {
          addNotification(
            kind: 'contract_ended',
            anchor: end,
            contractId: cid,
            title: 'انتهى العقد',
            subtitle: 'تاريخ الانتهاء: ${_fmtDate(end)}',
            message: serial.isEmpty
                ? 'انتهى عقد العميل $tenantName بتاريخ ${_fmtDate(end)}.'
                : 'انتهى العقد $serial للعميل $tenantName بتاريخ ${_fmtDate(end)}.',
            extra: <String, dynamic>{
              if (serial.isNotEmpty) 'serialNo': serial,
              'tenantName': tenantName,
            },
          );
        } else if (daysToEnd >= 0 && daysToEnd <= 7) {
          addNotification(
            kind: 'contract_expiring',
            anchor: end,
            sortAt: today,
            contractId: cid,
            title: 'العقد على وشك الانتهاء',
            subtitle: 'تاريخ الانتهاء: ${_fmtDate(end)}',
            message: serial.isEmpty
                ? 'عقد العميل $tenantName ينتهي بعد $daysToEnd يوم.'
                : 'العقد $serial للعميل $tenantName ينتهي بعد $daysToEnd يوم.',
            extra: <String, dynamic>{
              if (serial.isNotEmpty) 'serialNo': serial,
              'tenantName': tenantName,
              'daysLeft': daysToEnd,
            },
          );
        }

        if (c.term != ContractTerm.daily) {
          for (final due in _notificationAllInstallmentDueDates(c)) {
            final anchor = _notificationDateOnly(due);
            final delta = _notificationDaysBetween(anchor, today);
            final daysAhead = -delta;
            if (delta < 0 && daysAhead > 7) continue;

            late final String kind;
            late final String title;
            late final String message;
            if (delta < 0) {
              kind = 'contract_due_soon';
              title = 'موعد سداد قادم';
              message = serial.isEmpty
                  ? 'يوجد موعد سداد قادم للعميل $tenantName بعد $daysAhead يوم.'
                  : 'يوجد موعد سداد قادم في العقد $serial بعد $daysAhead يوم.';
            } else if (delta == 0) {
              kind = 'contract_due_today';
              title = 'سداد مستحق اليوم';
              message = serial.isEmpty
                  ? 'يوجد سداد مستحق اليوم للعميل $tenantName.'
                  : 'يوجد سداد مستحق اليوم في العقد $serial.';
            } else {
              kind = 'contract_due_overdue';
              title = 'سداد متأخر';
              message = serial.isEmpty
                  ? 'يوجد سداد متأخر للعميل $tenantName منذ $delta يوم.'
                  : 'يوجد سداد متأخر في العقد $serial منذ $delta يوم.';
            }

            addNotification(
              kind: kind,
              anchor: anchor,
              contractId: cid,
              title: title,
              subtitle: 'تاريخ الاستحقاق: ${_fmtDate(anchor)}',
              message: message,
              extra: <String, dynamic>{
                if (serial.isNotEmpty) 'serialNo': serial,
                'tenantName': tenantName,
                if (delta < 0) 'daysLeft': daysAhead,
                if (delta > 0) 'daysOverdue': delta,
              },
            );
          }
        }
      }
    }

    final iBox = _invoicesBox();
    if (iBox != null) {
      for (final i in iBox.values) {
        if (i.isArchived == true || i.isCanceled == true) continue;
        final remaining = i.amount - i.paidAmount;
        if (remaining < 0.01) continue;
        final anchor = _notificationDateOnly(i.dueDate);
        final delta = _notificationDaysBetween(anchor, today);
        if (delta < 0) continue;

        final serial = (i.serialNo ?? '').trim();
        addNotification(
          kind: 'invoice_overdue',
          anchor: anchor,
          invoiceId: i.id,
          contractId: i.contractId.isEmpty ? null : i.contractId,
          title: delta == 0 ? 'فاتورة مستحقة اليوم' : 'فاتورة متأخرة',
          subtitle: 'تاريخ الاستحقاق: ${_fmtDate(anchor)}',
          message: serial.isEmpty
              ? 'توجد فاتورة ${delta == 0 ? 'مستحقة اليوم' : 'متأخرة'} بمبلغ متبقٍ ${remaining.toStringAsFixed(2)}.'
              : 'الفاتورة $serial ${delta == 0 ? 'مستحقة اليوم' : 'متأخرة'} وبقي عليها ${remaining.toStringAsFixed(2)}.',
          extra: <String, dynamic>{
            if (serial.isNotEmpty) 'serialNo': serial,
            'remaining': remaining.toStringAsFixed(2),
            if (delta > 0) 'daysOverdue': delta,
          },
        );
      }
    }

    final mBox = _maintenanceBox();
    if (mBox != null) {
      for (final request in mBox.values) {
        if (request.isArchived) continue;
        if (request.status == MaintenanceStatus.canceled) continue;
        if (request.status == MaintenanceStatus.completed) continue;
        if (_notificationMaintenanceHasCanceledInvoice(request, iBox)) {
          continue;
        }
        final scheduled = request.scheduledDate;
        if (scheduled == null) continue;
        final anchor = _notificationDateOnly(scheduled);
        if (anchor != today) continue;

        final titleText = request.title.trim();
        addNotification(
          kind: 'maintenance_today',
          anchor: today,
          maintenanceId: request.id,
          title: titleText.isEmpty
              ? 'لديك طلب صيانة اليوم'
              : 'صيانة اليوم: $titleText',
          subtitle: 'موعد التنفيذ: ${_fmtDate(anchor)}',
          message: titleText.isEmpty
              ? 'يوجد طلب صيانة مجدول اليوم.'
              : 'يوجد طلب صيانة مجدول اليوم بعنوان "$titleText".',
          extra: <String, dynamic>{
            if ((request.serialNo ?? '').trim().isNotEmpty)
              'serialNo': request.serialNo!.trim(),
            if (titleText.isNotEmpty) 'maintenanceTitle': titleText,
          },
        );
      }
    }

    final svcBox = _servicesBox();
    if (svcBox != null) {
      for (final rawKey in svcBox.keys) {
        final raw = svcBox.get(rawKey);
        if (raw is! Map) continue;
        final cfg = Map<String, dynamic>.from(raw);
        final key = rawKey.toString();
        final parts = key.split('::');
        if (parts.length < 2) continue;

        final propertyId = parts.first.trim();
        final serviceType = _normalizeServiceType(
          cfg['serviceType'] ?? parts.last,
        );
        if (!_serviceTypes.contains(serviceType)) continue;
        if (!_notificationServiceHasProvider(serviceType, cfg)) continue;

        final isWaterSharedFixed =
            serviceType == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString().trim().toLowerCase() ==
                'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString().trim().toLowerCase() ==
                'fixed';
        final isWaterSharedPercent =
            serviceType == 'water' &&
            (cfg['waterBillingMode'] ?? '').toString().trim().toLowerCase() ==
                'shared' &&
            (cfg['waterSharedMethod'] ?? '').toString().trim().toLowerCase() ==
                'percent';
        final isElectricitySharedPercent =
            serviceType == 'electricity' &&
            (cfg['electricityBillingMode'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase() ==
                'shared' &&
            (cfg['electricitySharedMethod'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase() ==
                'percent';
        final isPercentBased =
            isWaterSharedPercent || isElectricitySharedPercent;
        final isPeriodicMaintenanceService =
            serviceType == 'cleaning' ||
            serviceType == 'elevator' ||
            (serviceType == 'internet' &&
                _notificationInternetBillingMode(cfg) == 'owner');

        if (!isWaterSharedFixed &&
            !isPercentBased &&
            (cfg['payer'] ?? 'owner').toString().trim().toLowerCase() !=
                'owner') {
          continue;
        }

        final propertyName = _findPropertyById(propertyId)?.name ?? propertyId;
        final startDate = _notificationServiceStartDate(cfg);
        if (!isPeriodicMaintenanceService &&
            startDate != null &&
            _notificationDaysBetween(today, startDate) == 0) {
          final alertId = '$key#serviceStart';
          addNotification(
            kind: 'service_start',
            anchor: startDate,
            maintenanceId: alertId,
            propertyId: propertyId,
            serviceType: serviceType,
            serviceTargetId: (cfg['targetId'] ?? '').toString().trim(),
            title: 'بداية ${_serviceLabel(serviceType)}',
            subtitle: 'تاريخ البداية: ${_fmtDate(startDate)}',
            message:
                'اليوم تبدأ ${_serviceLabel(serviceType)} في العقار "$propertyName".',
          );
        }

        final trackedPeriodicRequest = isPeriodicMaintenanceService
            ? _notificationTrackedPeriodicMaintenanceRequestFromConfig(
                maintenance: mBox,
                invoices: iBox,
                propertyId: propertyId,
                type: serviceType,
                cfg: cfg,
              )
            : null;
        if (trackedPeriodicRequest != null) {
          final trackedDue = _notificationMaintenanceAnchor(
            trackedPeriodicRequest,
          );
          final trackedDelta = _notificationDaysBetween(today, trackedDue);
          final remind = _notificationServiceRemindDays(cfg);
          if (trackedDelta == 0 ||
              (trackedDelta > 0 &&
                  remind > 0 &&
                  trackedDelta == remind) ||
              trackedDelta < 0) {
            final requestTitle = trackedPeriodicRequest.title.trim();
            final title = trackedDelta < 0
                ? '${_serviceLabel(serviceType)} متأخرة'
                : trackedDelta == 0
                    ? 'اليوم لديك طلب ${_serviceLabel(serviceType)}'
                    : 'لديك طلب ${_serviceLabel(serviceType)} بعد $trackedDelta يوم';
            addNotification(
              kind: 'maintenance_today',
              anchor: today,
              sortAt: today,
              maintenanceId: trackedPeriodicRequest.id,
              title: title,
              subtitle: 'موعد التنفيذ: ${_fmtDate(trackedDue)}',
              message: requestTitle.isEmpty
                  ? 'يوجد طلب ${_serviceLabel(serviceType)} مرتبط بالعقار "$propertyName".'
                  : 'يوجد طلب "$requestTitle" مرتبط بالعقار "$propertyName".',
              extra: <String, dynamic>{
                'propertyId': propertyId,
                'propertyName': propertyName,
                'serviceType': serviceType,
                if (requestTitle.isNotEmpty) 'maintenanceTitle': requestTitle,
                if ((trackedPeriodicRequest.serialNo ?? '').trim().isNotEmpty)
                  'serialNo': trackedPeriodicRequest.serialNo!.trim(),
              },
            );
            continue;
          }
        }

        final generatedToday = _notificationServiceLastGeneratedDate(cfg);
        if (generatedToday != null &&
            _notificationDaysBetween(today, generatedToday) == 0) {
          final activeGeneratedRequest = isPeriodicMaintenanceService
              ? _notificationActivePeriodicMaintenanceRequest(
                  maintenance: mBox,
                  invoices: iBox,
                  propertyId: propertyId,
                  type: serviceType,
                  anchor: generatedToday,
                )
              : null;
          final hasCompletedRequest = isPeriodicMaintenanceService &&
              _notificationHasCompletedPeriodicMaintenanceRequest(
                maintenance: mBox,
                propertyId: propertyId,
                type: serviceType,
                anchor: generatedToday,
              );
          final hasActiveRequest =
              !isPeriodicMaintenanceService || activeGeneratedRequest != null;
          final suppressed = _notificationServiceSuppressedDate(cfg);
          if (hasCompletedRequest) continue;
          if (isPeriodicMaintenanceService &&
              suppressed != null &&
              suppressed == _notificationDateOnly(generatedToday) &&
              !hasActiveRequest) {
            continue;
          }
          if (activeGeneratedRequest != null) {
            final requestTitle = activeGeneratedRequest.title.trim();
            addNotification(
              kind: 'maintenance_today',
              anchor: today,
              sortAt: today,
              maintenanceId: activeGeneratedRequest.id,
              title: 'اليوم لديك طلب ${_serviceLabel(serviceType)}',
              subtitle: 'موعد التنفيذ: ${_fmtDate(generatedToday)}',
              message: requestTitle.isEmpty
                  ? 'يوجد طلب ${_serviceLabel(serviceType)} مفتوح في العقار "$propertyName".'
                  : 'يوجد طلب "$requestTitle" مفتوح في العقار "$propertyName".',
              extra: <String, dynamic>{
                'propertyId': propertyId,
                'propertyName': propertyName,
                'serviceType': serviceType,
              },
            );
            continue;
          }

          final alertId = '$key#today';
          addNotification(
            kind: 'service_due',
            anchor: generatedToday,
            maintenanceId: alertId,
            propertyId: propertyId,
            serviceType: serviceType,
            serviceTargetId: (cfg['targetId'] ?? '').toString().trim(),
            title: _notificationServiceTitle(
              serviceType,
              cfg,
              delta: 0,
            ),
            subtitle: _notificationServiceSubtitle(
              serviceType,
              cfg,
              generatedToday,
            ),
            message:
                'اليوم موعد ${_serviceLabel(serviceType)} في العقار "$propertyName".',
            extra: <String, dynamic>{
              'propertyName': propertyName,
            },
          );
          continue;
        }

        final lastGenerated = _notificationServiceLastGeneratedDate(cfg);
        if (isPeriodicMaintenanceService &&
            lastGenerated != null &&
            _notificationDaysBetween(today, lastGenerated) < 0) {
          final activeGeneratedRequest = _notificationActivePeriodicMaintenanceRequest(
            maintenance: mBox,
            invoices: iBox,
            propertyId: propertyId,
            type: serviceType,
            anchor: lastGenerated,
          );
          if (activeGeneratedRequest != null &&
              _notificationDateOnly(activeGeneratedRequest.createdAt) == today) {
            final requestTitle = activeGeneratedRequest.title.trim();
            addNotification(
              kind: 'maintenance_today',
              anchor: today,
              sortAt: today,
              maintenanceId: activeGeneratedRequest.id,
              title: '${_serviceLabel(serviceType)} متأخرة',
              subtitle: 'موعد التنفيذ: ${_fmtDate(lastGenerated)}',
              message: requestTitle.isEmpty
                  ? 'تم إنشاء طلب متأخر اليوم لخدمة ${_serviceLabel(serviceType)} في العقار "$propertyName".'
                  : 'تم إنشاء الطلب "$requestTitle" اليوم لخدمة متأخرة في العقار "$propertyName".',
              extra: <String, dynamic>{
                'propertyId': propertyId,
                'propertyName': propertyName,
                'serviceType': serviceType,
              },
            );
            continue;
          }
        }

        final due = _notificationServiceCurrentCycleDate(cfg);
        if (due == null) continue;
        final activePeriodicRequest = isPeriodicMaintenanceService
            ? _notificationActivePeriodicMaintenanceRequest(
                maintenance: mBox,
                invoices: iBox,
                propertyId: propertyId,
                type: serviceType,
                anchor: due,
              )
            : null;
        final hasActiveRequest =
            !isPeriodicMaintenanceService || activePeriodicRequest != null;
        final suppressed = _notificationServiceSuppressedDate(cfg);
        if (isPeriodicMaintenanceService &&
            suppressed != null &&
            suppressed == _notificationDateOnly(due) &&
            !hasActiveRequest) {
          continue;
        }

        final daysUntilDue = _notificationDaysBetween(today, due);
        if (daysUntilDue < 0) continue;
        final remind = _notificationServiceRemindDays(cfg);
        if (daysUntilDue != 0 &&
            !(remind > 0 && daysUntilDue == remind)) {
          continue;
        }

        if (daysUntilDue == 0 && activePeriodicRequest != null) {
          final requestTitle = activePeriodicRequest.title.trim();
          addNotification(
            kind: 'maintenance_today',
            anchor: today,
            sortAt: today,
            maintenanceId: activePeriodicRequest.id,
            title: 'اليوم لديك طلب ${_serviceLabel(serviceType)}',
            subtitle: 'موعد التنفيذ: ${_fmtDate(due)}',
            message: requestTitle.isEmpty
                ? 'يوجد طلب ${_serviceLabel(serviceType)} مجدول اليوم في العقار "$propertyName".'
                : 'يوجد طلب "$requestTitle" مجدول اليوم في العقار "$propertyName".',
            extra: <String, dynamic>{
              'propertyId': propertyId,
              'propertyName': propertyName,
              'serviceType': serviceType,
            },
          );
          continue;
        }

        final alertType = daysUntilDue == 0 ? 'today' : 'remind-$daysUntilDue';
        final percent = isWaterSharedPercent
            ? ((cfg['sharePercent'] as num?)?.toDouble() ?? 0.0)
            : (isElectricitySharedPercent
                ? ((cfg['electricitySharePercent'] as num?)?.toDouble() ?? 0.0)
                : 0.0);
        final percentText = percent > 0 ? percent.toStringAsFixed(2) : '0.00';
        final alertId = isPercentBased
            ? '$key#percent#$alertType#$percentText'
            : '$key#$alertType';
        addNotification(
          kind: 'service_due',
          anchor: due,
          maintenanceId: alertId,
          propertyId: propertyId,
          serviceType: serviceType,
          serviceTargetId: _notificationServiceTargetId(
            serviceType,
            cfg,
            activePeriodicRequest: activePeriodicRequest,
          ),
          title: _notificationServiceTitle(
            serviceType,
            cfg,
            delta: daysUntilDue == 0 ? 0 : -daysUntilDue,
          ),
          subtitle: _notificationServiceSubtitle(serviceType, cfg, due),
          message: daysUntilDue == 0
              ? 'اليوم موعد ${_serviceLabel(serviceType)} في العقار "$propertyName".'
              : 'يوجد تنبيه ${_serviceLabel(serviceType)} في العقار "$propertyName" بعد $daysUntilDue يوم.',
          extra: <String, dynamic>{
            'propertyName': propertyName,
            if (daysUntilDue > 0) 'daysLeft': daysUntilDue,
          },
        );
      }
    }

    if (notifications.isEmpty) {
      return jsonEncode(<String, dynamic>{
        'info': 'لا توجد إشعارات حالياً.',
        'kind': requestedKind,
      });
    }

    notifications.sort((a, b) {
      final aDate = _parseDate((a['sortAt'] ?? '').toString()) ?? today;
      final bDate = _parseDate((b['sortAt'] ?? '').toString()) ?? today;
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      final aTitle = (a['title'] ?? '').toString();
      final bTitle = (b['title'] ?? '').toString();
      return aTitle.compareTo(bTitle);
    });

    final filtered = requestedKind == 'all'
        ? notifications
        : notifications
            .where((item) => (item['kind'] ?? '').toString() == requestedKind)
            .toList(growable: false);

    if (filtered.isEmpty) {
      return jsonEncode(<String, dynamic>{
        'info': 'لا توجد إشعارات مطابقة لهذا النوع حالياً.',
        'kind': requestedKind,
        'includeDismissed': includeDismissed,
      });
    }

    final counts = <String, int>{};
    for (final item in filtered) {
      final kind = (item['kind'] ?? '').toString();
      counts[kind] = (counts[kind] ?? 0) + 1;
    }

    return jsonEncode(<String, dynamic>{
      'kind': requestedKind,
      'includeDismissed': includeDismissed,
      'total': filtered.length,
      'counts': counts,
      'notifications': filtered.take(limit).toList(growable: false),
    });
  }

  String _openNotificationTarget(Map<String, dynamic> args) {
    final refData = _notificationRefFromArgs(args);
    if (refData == null) {
      return _err('مرجع الإشعار غير صالح أو ناقص.');
    }

    final kind = (refData['kind'] ?? '').toString().trim();
    if (kind.isEmpty || kind == 'all') {
      return _err('نوع الإشعار غير صالح.');
    }

    Map<String, dynamic> buildResult({
      required String route,
      required String message,
      Map<String, dynamic>? arguments,
    }) {
      return <String, dynamic>{
        'success': true,
        'message': message,
        'navigationAction': <String, dynamic>{
          'route': route,
          if (arguments != null) 'arguments': arguments,
        },
      };
    }

    switch (kind) {
      case 'contract_started_today':
      case 'contract_expiring':
      case 'contract_ended':
      case 'contract_due_soon':
      case 'contract_due_today':
      case 'contract_due_overdue':
        final contractId = (refData['contractId'] ?? '').toString().trim();
        if (contractId.isEmpty) {
          return _err('لا يوجد عقد مرتبط بهذا الإشعار.');
        }
        return jsonEncode(buildResult(
          route: '/contracts',
          arguments: <String, dynamic>{'openContractId': contractId},
          message: 'تم فتح العقد المرتبط بالإشعار.',
        ));
      case 'invoice_overdue':
        final invoiceId = (refData['invoiceId'] ?? '').toString().trim();
        if (invoiceId.isEmpty) {
          return _err('لا توجد فاتورة مرتبطة بهذا الإشعار.');
        }
        return jsonEncode(buildResult(
          route: '/invoices',
          arguments: <String, dynamic>{'openInvoiceId': invoiceId},
          message: 'تم فتح الفاتورة المرتبطة بالإشعار.',
        ));
      case 'maintenance_today':
        final maintenanceId =
            (refData['maintenanceId'] ?? '').toString().trim();
        if (maintenanceId.isEmpty) {
          return _err('لا يوجد طلب صيانة مرتبط بهذا الإشعار.');
        }
        return jsonEncode(buildResult(
          route: '/maintenance',
          arguments: <String, dynamic>{'openMaintenanceId': maintenanceId},
          message: 'تم فتح طلب الصيانة المرتبط بالإشعار.',
        ));
      case 'service_due':
        final propertyId = (refData['propertyId'] ?? '').toString().trim();
        final serviceType = (refData['serviceType'] ?? '').toString().trim();
        if (propertyId.isEmpty || serviceType.isEmpty) {
          return _err('بيانات الخدمة المرتبطة بالإشعار غير مكتملة.');
        }
        final cfg = _notificationServiceConfigFor(propertyId, serviceType);
        final opensSharedUtilityDirectly =
            cfg != null && _notificationIsSharedUtilityService(serviceType, cfg);
        final targetId = opensSharedUtilityDirectly
            ? ''
            : (refData['serviceTargetId'] ?? '').toString().trim();
        return jsonEncode(buildResult(
          route: '/property/services',
          arguments: <String, dynamic>{
            'propertyId': propertyId,
            'openService': serviceType,
            'openPay': !opensSharedUtilityDirectly,
            'targetId': targetId,
            'openServiceDirectly': opensSharedUtilityDirectly,
          },
          message: 'تم فتح الخدمة المرتبطة بالإشعار.',
        ));
      case 'service_start':
        final propertyId = (refData['propertyId'] ?? '').toString().trim();
        final serviceType = (refData['serviceType'] ?? '').toString().trim();
        if (propertyId.isEmpty || serviceType.isEmpty) {
          return _err('بيانات الخدمة المرتبطة بالإشعار غير مكتملة.');
        }
        return jsonEncode(buildResult(
          route: '/property/services',
          arguments: <String, dynamic>{
            'propertyId': propertyId,
            'openService': serviceType,
            'openPay': false,
            'targetId': (refData['serviceTargetId'] ?? '').toString().trim(),
          },
          message: 'تم فتح الخدمة المرتبطة بالإشعار.',
        ));
      default:
        return _err('هذا النوع من الإشعارات لا يملك هدف فتح مباشر.');
    }
  }

  Future<String> _markNotificationRead(Map<String, dynamic> args) async {
    final refData = _notificationRefFromArgs(args);
    if (refData == null) {
      return _err('مرجع الإشعار غير صالح أو ناقص.');
    }

    final kind = (refData['kind'] ?? '').toString().trim();
    final anchor = _parseDate((refData['anchorDate'] ?? '').toString().trim());
    if (kind.isEmpty || anchor == null || kind == 'all') {
      return _err('بيانات الإشعار غير مكتملة.');
    }

    final contractId = (refData['contractId'] ?? '').toString().trim();
    final invoiceId = (refData['invoiceId'] ?? '').toString().trim();
    final maintenanceId = (refData['maintenanceId'] ?? '').toString().trim();
    final stableKey = _notificationStableKey(
      kind: kind,
      anchor: anchor,
      contractId: contractId.isEmpty ? null : contractId,
      invoiceId: invoiceId.isEmpty ? null : invoiceId,
      maintenanceId: maintenanceId.isEmpty ? null : maintenanceId,
    );

    try {
      final name = boxName('notificationsDismissed');
      final box = Hive.isBoxOpen(name)
          ? Hive.box<String>(name)
          : await Hive.openBox<String>(name);
      await box.put(stableKey, '1');
      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم تعليم الإشعار كمقروء.',
        'notificationRef': _encodeNotificationRef(refData),
      });
    } catch (e) {
      return _err('تعذر تحديث حالة الإشعار: $e');
    }
  }
  // ================================================================
  //  التقارير التفصيلية
  // ================================================================

  Future<String> _getPropertiesReport(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getPropertiesReport(args));
  }

  Future<String> _getClientsReport(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getClientsReport(args));
  }

  Future<String> _getContractsReport(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getContractsReport(args));
  }

  Future<String> _getServicesReport(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getServicesReport(args));
  }

  Future<String> _getInvoicesReport(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getVouchersReport(args));
  }

  Future<String> _getReportsOffice(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getOfficeReport(args));
  }

  Future<String> _getReportsOwners(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getOwnersReport(args));
  }

  Future<String> _getReportsOwnerDetails(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getOwnerReportDetails(args));
  }

  Future<String> _previewReportsOwnerSettlement(Map<String, dynamic> args) {
    return _runReportBridge(
      () => AiChatReportsBridge.previewOwnerSettlement(args),
    );
  }

  Future<String> _previewReportsOfficeSettlement(Map<String, dynamic> args) {
    return _runReportBridge(
      () => AiChatReportsBridge.previewOfficeSettlement(args),
    );
  }

  Future<String> _getReportsOwnerBankAccounts(Map<String, dynamic> args) {
    return _runReportBridge(() => AiChatReportsBridge.getOwnerBankAccounts(args));
  }

  Future<String> _assignReportsPropertyOwner(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsAssignPropertyOwner(
      propertyQuery: args['propertyQuery'],
      ownerQuery: args['ownerQuery'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsAssignPropertyOwnerRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'assign_property_owner_from_reports',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.assignPropertyOwner(
        draft.propertyQuery,
        draft.ownerQuery,
      ),
    );
  }

  Future<String> _recordReportsOfficeVoucher(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsOfficeVoucher(
      isExpense: args['isExpense'],
      amount: args['amount'],
      transactionDate: args['transactionDate'],
      note: args['note'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.reportsOfficeVoucherRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'record_office_report_voucher',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.recordOfficeVoucher(
        isExpense: draft.isExpense,
        amount: draft.amount,
        transactionDate: draft.transactionDate,
        note: draft.note,
      ),
    );
  }

  Future<String> _recordReportsOfficeWithdrawal(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsOfficeWithdrawal(
      amount: args['amount'],
      transferDate: args['transferDate'],
      note: args['note'],
      fromDate: args['fromDate'],
      toDate: args['toDate'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsOfficeWithdrawalRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'record_office_withdrawal',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.recordOfficeWithdrawal(
        amount: draft.amount,
        transferDate: draft.transferDate,
        note: draft.note,
        fromDate: draft.fromDate,
        toDate: draft.toDate,
      ),
    );
  }

  Future<String> _setReportsCommissionRule(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsCommissionRule(
      mode: args['mode'],
      value: args['value'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsCommissionRuleRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'set_report_commission_rule',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.setCommissionRule(
        mode: draft.mode,
        value: draft.value,
      ),
    );
  }

  Future<String> _recordReportsOwnerPayout(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsOwnerPayout(
      ownerQuery: args['ownerQuery'],
      propertyQuery: args['propertyQuery'],
      amount: args['amount'],
      transferDate: args['transferDate'],
      note: args['note'],
      fromDate: args['fromDate'],
      toDate: args['toDate'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.reportsOwnerPayoutRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'record_owner_payout',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.recordOwnerPayout(
        ownerQuery: draft.ownerQuery,
        propertyQuery: draft.propertyQuery,
        amount: draft.amount,
        transferDate: draft.transferDate,
        note: draft.note,
        fromDate: draft.fromDate,
        toDate: draft.toDate,
      ),
    );
  }

  Future<String> _recordReportsOwnerAdjustment(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsOwnerAdjustment(
      ownerQuery: args['ownerQuery'],
      propertyQuery: args['propertyQuery'],
      category: args['category'],
      amount: args['amount'],
      adjustmentDate: args['adjustmentDate'],
      note: args['note'],
      fromDate: args['fromDate'],
      toDate: args['toDate'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsOwnerAdjustmentRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'record_owner_adjustment',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.recordOwnerAdjustment(
        ownerQuery: draft.ownerQuery,
        propertyQuery: draft.propertyQuery,
        category: draft.category,
        amount: draft.amount,
        adjustmentDate: draft.adjustmentDate,
        note: draft.note,
        fromDate: draft.fromDate,
        toDate: draft.toDate,
      ),
    );
  }

  Future<String> _addReportsOwnerBankAccount(Map<String, dynamic> args) async {
    final validation = AiChatDomainRulesService.validateReportsOwnerBankAccount(
      ownerQuery: args['ownerQuery'],
      bankName: args['bankName'],
      accountNumber: args['accountNumber'],
      iban: args['iban'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsOwnerBankAccountRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'add_owner_bank_account',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.addOwnerBankAccount(
        ownerQuery: draft.ownerQuery,
        bankName: draft.bankName,
        accountNumber: draft.accountNumber,
        iban: draft.iban,
      ),
    );
  }

  Future<String> _editReportsOwnerBankAccount(Map<String, dynamic> args) async {
    final validation =
        AiChatDomainRulesService.validateReportsOwnerBankAccountEdit(
      ownerQuery: args['ownerQuery'],
      accountQuery: args['accountQuery'],
      bankName: args['bankName'],
      accountNumber: args['accountNumber'],
      iban: args['iban'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsOwnerBankAccountEditRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'edit_owner_bank_account',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.editOwnerBankAccount(
        ownerQuery: draft.ownerQuery,
        accountQuery: draft.accountQuery,
        bankName: draft.bankName,
        accountNumber: draft.accountNumber,
        iban: draft.iban,
      ),
    );
  }

  Future<String> _deleteReportsOwnerBankAccount(Map<String, dynamic> args) async {
    final validation =
        AiChatDomainRulesService.validateReportsOwnerBankAccountDelete(
      ownerQuery: args['ownerQuery'],
      accountQuery: args['accountQuery'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.reportsOwnerBankAccountDeleteRequiredFields(),
        nextStep: 'collect_missing_or_invalid_reports_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'reports',
          'operation': 'delete_owner_bank_account',
        },
      );
    }

    final draft = validation.draft!;
    return _runReportBridge(
      () => AiChatReportsBridge.deleteOwnerBankAccount(
        ownerQuery: draft.ownerQuery,
        accountQuery: draft.accountQuery,
      ),
    );
  }

  Future<String> _runReportBridge(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return jsonEncode(await action());
    } on StateError catch (e) {
      return _err(_cleanReportError(e));
    }
  }

  String _cleanReportError(Object error) {
    final text = '$error'.trim();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
    return text;
  }

  // ================================================================
  //  كتابة - مستأجرين
  // ================================================================

  String _addTenant(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _tenantsBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final prepared = TenantRecordService.prepareForUpsert(
      clientType: (args['clientType'] ?? '').toString(),
      fullName: args['fullName']?.toString(),
      nationalId: args['nationalId']?.toString(),
      phone: args['phone']?.toString(),
      email: args['email']?.toString(),
      nationality: args['nationality']?.toString(),
      companyName: args['companyName']?.toString(),
      companyCommercialRegister: args['companyCommercialRegister']?.toString(),
      companyTaxNumber: args['companyTaxNumber']?.toString(),
      companyRepresentativeName:
          args['companyRepresentativeName']?.toString(),
      companyRepresentativePhone:
          args['companyRepresentativePhone']?.toString(),
      serviceSpecialization: args['serviceSpecialization']?.toString(),
      attachmentPaths: args['attachmentPaths'],
      existingTenants: box.values.cast<Tenant>(),
    );
    if (!prepared.isValid) {
      return _tenantUpsertError(
        prepared,
        clientType: args['clientType']?.toString(),
        operation: 'add_client_record',
      );
    }

    final id = const Uuid().v4();
    final now = KsaTime.now();
    final tenant = prepared.draft!.createNew(id: id, now: now);
    box.put(id, tenant);
    OfflineSyncService.instance.enqueueUpsertTenant(tenant);
    return _ok(
      '${TenantRecordService.addedClientSuccessMessage(tenant.clientType)}: "${tenant.fullName}"',
    );
  }

  String _editTenant(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final t = _findTenant(args['query'] ?? '');
    if (t == null) return _err('لم يتم العثور على العميل');

    final prepared = TenantRecordService.prepareForUpsert(
      clientType: args.containsKey('clientType')
          ? (args['clientType']?.toString() ?? t.clientType)
          : t.clientType,
      fullName: args.containsKey('fullName')
          ? args['fullName']?.toString()
          : t.fullName,
      nationalId: args.containsKey('nationalId')
          ? args['nationalId']?.toString()
          : t.nationalId,
      phone: args.containsKey('phone') ? args['phone']?.toString() : t.phone,
      email: args.containsKey('email') ? args['email']?.toString() : t.email,
      nationality: args.containsKey('nationality')
          ? args['nationality']?.toString()
          : t.nationality,
      dateOfBirth: t.dateOfBirth,
      idExpiry: t.idExpiry,
      emergencyName: t.emergencyName,
      emergencyPhone: t.emergencyPhone,
      notes: t.notes,
      companyName: args.containsKey('companyName')
          ? args['companyName']?.toString()
          : t.companyName,
      companyCommercialRegister: args.containsKey('companyCommercialRegister')
          ? args['companyCommercialRegister']?.toString()
          : t.companyCommercialRegister,
      companyTaxNumber: args.containsKey('companyTaxNumber')
          ? args['companyTaxNumber']?.toString()
          : t.companyTaxNumber,
      companyRepresentativeName:
          args.containsKey('companyRepresentativeName')
              ? args['companyRepresentativeName']?.toString()
              : t.companyRepresentativeName,
      companyRepresentativePhone:
          args.containsKey('companyRepresentativePhone')
              ? args['companyRepresentativePhone']?.toString()
              : t.companyRepresentativePhone,
      serviceSpecialization: args.containsKey('serviceSpecialization')
          ? args['serviceSpecialization']?.toString()
          : t.serviceSpecialization,
      attachmentPaths: t.attachmentPaths,
      existingTenants: _tenantsBox()?.values.cast<Tenant>() ?? const <Tenant>[],
      editingTenantId: t.id,
    );
    if (!prepared.isValid) {
      return _tenantUpsertError(
        prepared,
        clientType: args.containsKey('clientType')
            ? args['clientType']?.toString()
            : t.clientType,
        operation: 'edit_tenant',
      );
    }

    prepared.draft!.applyTo(t);
    t.updatedAt = KsaTime.now();
    t.save();
    OfflineSyncService.instance.enqueueUpsertTenant(t);
    return _ok('تم تعديل بيانات العميل "${t.fullName}" بنجاح.');
  }

  String _archiveTenant(String query, bool archive) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final t = _findTenant(query);
    if (t == null) return _err('لم يتم العثور على العميل');
    if (archive) {
      final currentProviderRequests =
          TenantRecordService.effectiveClientType(t) ==
                  TenantRecordService.clientTypeServiceProvider
              ? _countProviderCurrentMaintenanceRequests(t.fullName)
              : 0;
      final blockedMessage = TenantRecordService.archiveBlockedMessage(
        t,
        currentProviderRequests: currentProviderRequests,
      );
      if (blockedMessage != null) {
        return jsonEncode(<String, dynamic>{
          'error': blockedMessage,
          'code': 'archive_blocked',
          'clientType': TenantRecordService.effectiveClientType(t),
          'activeContractsCount': t.activeContractsCount,
          'currentProviderRequests': currentProviderRequests,
        });
      }
    }
    t.isArchived = archive;
    t.updatedAt = KsaTime.now();
    t.save();
    OfflineSyncService.instance.enqueueUpsertTenant(t);
    return _ok(archive
        ? 'تمت أرشفة العميل "${t.fullName}".'
        : 'تم إلغاء أرشفة العميل "${t.fullName}".');
  }

  String _blacklistTenant(String query, bool blacklist, String reason) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final t = _findTenant(query);
    if (t == null) return _err('لم يتم العثور على العميل');
    t.isBlacklisted = blacklist;
    t.blacklistReason = blacklist ? reason : null;
    t.updatedAt = KsaTime.now();
    t.save();
    OfflineSyncService.instance.enqueueUpsertTenant(t);
    return _ok(blacklist
        ? 'تمت إضافة العميل "${t.fullName}" إلى القائمة السوداء.'
        : 'تمت إزالة العميل "${t.fullName}" من القائمة السوداء.');
  }

  // ================================================================
  //  كتابة - عقارات
  // ================================================================

  Future<String> _addProperty(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _propertiesBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final limitDecision = await PackageLimitService.canAddProperty();
    if (!limitDecision.allowed) {
      return jsonEncode(<String, dynamic>{
        'error': limitDecision.message ??
            'لا يمكن إضافة عقار جديد، لقد وصلت إلى الحد الأقصى المسموح.',
        'code': 'package_limit_reached',
        'limit': limitDecision.limit,
        'used': limitDecision.used,
      });
    }

    final validation = AiChatDomainRulesService.validatePropertyUpsert(
      name: args['name'],
      type: args['type'],
      address: args['address'],
      rentalMode: args['rentalMode'],
      totalUnits: args['totalUnits'],
      floors: args['floors'],
      rooms: args['rooms'],
      area: args['area'],
      price: args['price'],
      currency: args['currency'],
      baths: args['baths'],
      halls: args['halls'],
      apartmentFloor: args['apartmentFloor'],
      furnished: args['furnished'],
      description: args['description'],
      documentType: args['documentType'],
      documentNumber: args['documentNumber'],
      documentDate: args['documentDate'],
      documentAttachmentPaths:
          args['documentAttachmentPaths'] ?? args['attachmentPaths'],
      existing: null,
      isLinkedForEdit: false,
      existingUnitsCount: 0,
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: <Map<String, dynamic>>[
          ...AiChatDomainRulesService.propertyBaseRequiredFields(),
          ...AiChatDomainRulesService.propertyDocumentRequiredFields(),
        ],
        nextStep: validation.requiresScreenCompletion
            ? 'open_properties_screen_to_complete_documents'
            : 'collect_missing_or_invalid_property_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'properties',
          'operation': 'add_property',
        },
      );
    }

    final draft = validation.draft!;
    final id = const Uuid().v4();
    final now = KsaTime.now();
    final prop = Property(
      id: id,
      name: draft.name,
      type: draft.type,
      address: draft.address,
      rentalMode: draft.rentalMode,
      totalUnits: draft.totalUnits,
      rooms: draft.rooms,
      area: draft.area,
      floors: draft.floors,
      price: draft.price,
      currency: draft.currency,
      description: draft.description,
      documentType: draft.documentType,
      documentNumber: draft.documentNumber,
      documentDate: draft.documentDate,
      documentAttachmentPath: draft.documentAttachmentPaths.isEmpty
          ? null
          : draft.documentAttachmentPaths.first,
      documentAttachmentPaths: List<String>.from(draft.documentAttachmentPaths),
      createdAt: now,
      updatedAt: now,
    );
    box.put(id, prop);
    OfflineSyncService.instance.enqueueUpsertProperty(prop);
    return jsonEncode(<String, dynamic>{
      'success': true,
      'message': 'تمت إضافة العقار "${prop.name}" بنجاح.',
      'property': <String, dynamic>{
        'id': prop.id,
        'name': prop.name,
        'type': prop.type.name,
      },
    });
  }

  String _editProperty(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final p = _findProperty(args['query'] ?? '');
    if (p == null) return _err('لم يتم العثور على العقار');
    final spec = _parsePropertySpec(p.description);

    final validation = AiChatDomainRulesService.validatePropertyUpsert(
      name: args['name'] ?? p.name,
      type: args['type'] ?? p.type.name,
      address: args['address'] ?? p.address,
      rentalMode: args['rentalMode'] ?? p.rentalMode?.name,
      totalUnits: args['totalUnits'] ?? p.totalUnits,
      floors: args['floors'] ?? p.floors,
      rooms: args['rooms'] ?? p.rooms,
      area: args['area'] ?? p.area,
      price: args['price'] ?? p.price,
      currency: args['currency'] ?? p.currency,
      baths: args['baths'] ?? _propertySpecInt(spec, 'حمامات'),
      halls: args['halls'] ?? _propertySpecInt(spec, 'صالات'),
      apartmentFloor: args['apartmentFloor'] ?? _propertySpecInt(spec, 'الدور'),
      furnished: args['furnished'] ?? _propertySpecFurnished(spec),
      description: args['description'] ?? _extractFreePropertyDescription(p.description),
      documentType: args['documentType'] ?? p.documentType,
      documentNumber: args['documentNumber'] ?? p.documentNumber,
      documentDate:
          args['documentDate'] ?? (p.documentDate == null ? null : _fmtDate(p.documentDate!)),
      documentAttachmentPaths: args['documentAttachmentPaths'] ??
          args['attachmentPaths'] ??
          p.documentAttachmentPaths ??
          ((p.documentAttachmentPath ?? '').trim().isEmpty
              ? const <String>[]
              : <String>[p.documentAttachmentPath!.trim()]),
      existing: p,
      isLinkedForEdit: _hasActiveContract(p) || _existingUnitsCountForBuilding(p.id) > 0,
      existingUnitsCount: _existingUnitsCountForBuilding(p.id),
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: <Map<String, dynamic>>[
          ...AiChatDomainRulesService.propertyBaseRequiredFields(),
          ...AiChatDomainRulesService.propertyDocumentRequiredFields(),
        ],
        nextStep: validation.requiresScreenCompletion
            ? 'open_properties_screen_to_complete_documents'
            : 'collect_missing_or_invalid_property_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'properties',
          'operation': 'edit_property',
          'propertyName': p.name,
        },
      );
    }

    final draft = validation.draft!;
    p.name = draft.name;
    p.type = draft.type;
    p.address = draft.address;
    p.rentalMode = draft.rentalMode;
    p.totalUnits = draft.totalUnits;
    p.rooms = draft.rooms;
    p.area = draft.area;
    p.floors = draft.floors;
    p.price = draft.price;
    p.currency = draft.currency;
    p.description = draft.description;
    p.documentType = draft.documentType;
    p.documentNumber = draft.documentNumber;
    p.documentDate = draft.documentDate;
    p.documentAttachmentPaths = List<String>.from(draft.documentAttachmentPaths);
    p.documentAttachmentPath =
        draft.documentAttachmentPaths.isEmpty ? null : draft.documentAttachmentPaths.first;
    p.updatedAt = KsaTime.now();
    p.save();
    OfflineSyncService.instance.enqueueUpsertProperty(p);
    return _ok('تم تعديل بيانات العقار "${p.name}" بنجاح.');
  }

  String _archiveProperty(String query, bool archive) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final p = _findProperty(query);
    if (p == null) return _err('لم يتم العثور على العقار');
    if (archive && _hasActiveContract(p)) {
      return jsonEncode(<String, dynamic>{
        'error': _archiveBlockedMessageForProperty(p),
        'code': 'archive_blocked',
        'suggestedScreen': 'properties',
        'nextStep': 'terminate_or_clear_active_usage_then_retry',
        'propertyName': p.name,
      });
    }
    p.isArchived = archive;
    p.updatedAt = KsaTime.now();
    p.save();
    OfflineSyncService.instance.enqueueUpsertProperty(p);
    return _ok(archive
        ? 'تمت أرشفة العقار "${p.name}".'
        : 'تم إلغاء أرشفة العقار "${p.name}".');
  }

  // ================================================================
  //  كتابة - عقود
  // ================================================================

  Future<String> _createContract(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final tenantBox = _tenantsBox();
    final propBox = _propertiesBox();
    final contractBox = _contractsBox();
    if (tenantBox == null || propBox == null || contractBox == null) {
      return _err('لا يمكن الوصول للبيانات');
    }

    final tenantName = (args['tenantName'] ?? '').toString().trim().toLowerCase();
    final tenant = tenantBox.values.cast<Tenant>().where((t) {
      return t.fullName.toLowerCase().contains(tenantName) &&
          t.isArchived != true;
    }).firstOrNull;
    if (tenant == null) return _err('لم يتم العثور على مستأجر باسم "${args['tenantName']}"');

    final propName = (args['propertyName'] ?? '').toString().trim().toLowerCase();
    final prop = propBox.values.cast<Property>().where((p) {
      return p.name.toLowerCase().contains(propName) && p.isArchived != true;
    }).firstOrNull;
    if (prop == null) return _err('لم يتم العثور على عقار باسم "${args['propertyName']}"');

    if (_isPropertyOrParentArchived(prop)) {
      return _archivedPropertyActionError(prop, forService: false);
    }

    if (tenant.isBlacklisted == true) {
      return jsonEncode(<String, dynamic>{
        'error': 'العميل محظور ولا يمكن إنشاء عقد جديد له.',
        'code': 'blacklisted_tenant',
        'tenantName': tenant.fullName,
      });
    }

    final requestedTerm =
        AiChatDomainRulesService.normalizeContractTerm(args['term']);
    final rawDailyCheckoutHour = args['dailyCheckoutHour'];
    final hasExplicitDailyCheckoutHour =
        args.containsKey('dailyCheckoutHour') &&
            rawDailyCheckoutHour != null &&
            rawDailyCheckoutHour.toString().trim().isNotEmpty;
    final savedDailyCheckoutHour =
        requestedTerm == ContractTerm.daily && !hasExplicitDailyCheckoutHour
            ? await _resolveSavedDailyContractCheckoutHour()
            : null;
    final effectiveDailyCheckoutHour =
        hasExplicitDailyCheckoutHour
            ? rawDailyCheckoutHour
            : savedDailyCheckoutHour;

    final validation = AiChatDomainRulesService.validateContractCreate(
      startDate: args['startDate'],
      endDate: args['endDate'],
      rentAmount: args['rentAmount'],
      totalAmount: args['totalAmount'],
      term: args['term'],
      termYears: args['termYears'],
      paymentCycle: args['paymentCycle'],
      paymentCycleYears: args['paymentCycleYears'],
      advanceMode: args['advanceMode'],
      advancePaid: args['advancePaid'],
      dailyCheckoutHour: effectiveDailyCheckoutHour,
      notes: args['notes'],
      ejarContractNo: args['ejarContractNo'],
      attachmentPaths: args['attachmentPaths'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.contractCreateRequiredFields(),
        nextStep: 'collect_missing_or_invalid_contract_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'contracts',
          'operation': 'create_contract',
          'tenantName': tenant.fullName,
          'propertyName': prop.name,
          if (savedDailyCheckoutHour != null)
            'resolvedDailyCheckoutHourFromSettings': savedDailyCheckoutHour,
        },
      );
    }

    if (!_isPropertyAvailableForContract(prop)) {
      return jsonEncode(<String, dynamic>{
        'error': 'العقار أو الوحدة غير متاحة حاليًا لإنشاء عقد جديد.',
        'code': 'property_unavailable',
        'propertyName': prop.name,
      });
    }

    final missingServices = await missingRequiredPeriodicServicesForProperty(
      prop.id,
      property: prop,
    );
    if (missingServices.isNotEmpty) {
      return jsonEncode(<String, dynamic>{
        'error':
            'الخدمات الدورية المطلوبة غير مضبوطة لهذا العقار: ${missingServices.join('، ')}.',
        'code': 'periodic_services_incomplete',
        'requiresScreenCompletion': true,
        'suggestedScreen': 'property_services',
        'nextStep': 'open_property_services_and_complete_then_retry',
        'propertyName': prop.name,
        'missingServices': missingServices,
        'navigationAction': _navigationAction(
          '/property/services',
          arguments: <String, dynamic>{'propertyId': prop.id},
        ),
      });
    }

    final draft = validation.draft!;
    final parentBuilding = _parentBuildingFor(prop);
    final id = const Uuid().v4();
    final now = KsaTime.now();
    final serial = _nextSerial(
        'C', contractBox.values.map((c) => (c as dynamic).serialNo as String?));

    final contract = Contract(
      id: id,
      serialNo: serial,
      tenantId: tenant.id,
      propertyId: prop.id,
      tenantSnapshot: _buildTenantSnapshot(tenant),
      propertySnapshot: _buildPropertySnapshot(prop),
      buildingSnapshot:
          parentBuilding == null ? null : _buildPropertySnapshot(parentBuilding),
      startDate: draft.startDate,
      endDate: draft.endDate,
      rentAmount: draft.rentAmount,
      totalAmount: draft.totalAmount,
      term: draft.term,
      termYears: draft.termYears,
      paymentCycle: draft.paymentCycle,
      paymentCycleYears: draft.paymentCycleYears,
      advanceMode: draft.advanceMode,
      advancePaid: draft.advancePaid,
      dailyCheckoutHour: draft.dailyCheckoutHour,
      ejarContractNo: draft.ejarContractNo,
      notes: draft.notes,
      attachmentPaths: List<String>.from(draft.attachmentPaths),
      createdAt: now,
      updatedAt: now,
    );
    contractBox.put(id, contract);
    await _occupyProperty(prop);
    if (contract.isActiveNow) {
      await _incrementTenantActiveContracts(tenant.id);
    }
    return jsonEncode(<String, dynamic>{
      'success': true,
      'message':
          'تم إنشاء العقد رقم $serial بنجاح.\nالعميل: ${tenant.fullName}\nالعقار: ${prop.name}\nالإجمالي: ${draft.totalAmount.toStringAsFixed(2)} ريال',
      'contractSerialNo': serial,
      'contractId': id,
      if (requestedTerm == ContractTerm.daily)
        'appliedDailyCheckoutHour': draft.dailyCheckoutHour,
      if (requestedTerm == ContractTerm.daily && savedDailyCheckoutHour != null)
        'dailyCheckoutHourSource': 'settings',
    });
  }

  Future<String> _terminateContract(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _contractsBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final serial = (args['contractSerialNo'] ?? '').toString().trim();
    final match = box.values.where((c) {
      return (c as dynamic).serialNo == serial;
    }).firstOrNull;
    if (match == null) return _err('لم يتم العثور على عقد بالرقم $serial');

    final c = match as dynamic;
    if (c.isTerminated == true) return _err('هذا العقد منهي بالفعل.');

    final prop = _findPropertyById((c.propertyId ?? '').toString());
    final tenantId = (c.tenantId ?? '').toString();
    final wasActive = match.isActiveNow;
    c.isTerminated = true;
    c.terminatedAt = KsaTime.now();
    c.updatedAt = KsaTime.now();
    await (c as Contract).save();
    if (prop != null) {
      await _releaseProperty(prop);
    }
    if (wasActive && tenantId.isNotEmpty) {
      await _decrementTenantActiveContracts(tenantId);
    }
    return _ok('تم إنهاء العقد $serial بنجاح.');
  }

  // ================================================================
  //  كتابة - فواتير
  // ================================================================

  String _createInvoice(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final contractBox = _contractsBox();
    final invoiceBox = _invoicesBox();
    if (contractBox == null || invoiceBox == null) {
      return _err('لا يمكن الوصول للبيانات');
    }

    final serial = (args['contractSerialNo'] ?? '').toString().trim();
    final contract = contractBox.values.where((c) {
      return (c as dynamic).serialNo == serial;
    }).firstOrNull;
    if (contract == null) return _err('لم يتم العثور على عقد بالرقم $serial');

    final draftValidation = AiChatDomainRulesService.validateInvoiceCreate(
      amount: args['amount'],
      dueDate: args['dueDate'],
      note: args['note'],
    );
    if (!draftValidation.isValid) {
      return _domainValidationError(
        draftValidation,
        requiredFields: AiChatDomainRulesService.invoiceRequiredFields(),
        nextStep: 'collect_missing_or_invalid_invoice_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'invoices',
          'operation': 'create_invoice',
          'contractSerialNo': serial,
        },
      );
    }

    final cd = contract as dynamic;
    final draft = draftValidation.draft!;
    final id = const Uuid().v4();
    final now = KsaTime.now();
    final invSerial = _nextSerial(
        'I', invoiceBox.values.map((i) => i.serialNo));

    final invoice = Invoice(
      id: id,
      serialNo: invSerial,
      tenantId: cd.tenantId as String,
      contractId: cd.id as String,
      propertyId: cd.propertyId as String,
      issueDate: now,
      dueDate: draft.dueDate,
      amount: draft.amount,
      note: draft.note,
      createdAt: now,
      updatedAt: now,
    );
    invoiceBox.put(id, invoice);
    return _ok(
        'تم إصدار الفاتورة رقم $invSerial بمبلغ ${draft.amount.toStringAsFixed(2)} ريال.');
  }

  String _recordPayment(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _invoicesBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final serial = (args['invoiceSerialNo'] ?? '').toString().trim();
    final amount = (args['amount'] as num?)?.toDouble() ?? 0;

    final inv = box.values.where((i) => i.serialNo == serial).firstOrNull;
    if (inv == null) return _err('لم يتم العثور على فاتورة بالرقم $serial');
    if (inv.isCanceled == true) return _err('هذه الفاتورة ملغاة.');
    if (amount <= 0) return _err('مبلغ الدفعة يجب أن يكون أكبر من صفر.');

    final remaining = inv.amount - inv.paidAmount;
    if (remaining < 0.01) return _err('هذه الفاتورة مدفوعة بالكامل.');
    if (amount > remaining + 0.01) {
      return _err(
          'المبلغ ($amount) أكبر من المتبقي (${remaining.toStringAsFixed(2)})');
    }

    inv.paidAmount += amount;
    inv.updatedAt = KsaTime.now();
    inv.save();
    final newRemaining = inv.amount - inv.paidAmount;
    return _ok(
        'تم تسجيل دفعة ${amount.toStringAsFixed(2)} ريال على الفاتورة $serial.\nالمتبقي: ${newRemaining.toStringAsFixed(2)} ريال');
  }

  String _cancelInvoice(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _invoicesBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final serial = (args['invoiceSerialNo'] ?? '').toString().trim();
    final inv = box.values.where((i) => i.serialNo == serial).firstOrNull;
    if (inv == null) return _err('لم يتم العثور على فاتورة بالرقم $serial');
    if (inv.isCanceled == true) return _err('هذه الفاتورة ملغاة بالفعل.');

    inv.isCanceled = true;
    inv.updatedAt = KsaTime.now();
    inv.save();
    return _ok('تم إلغاء الفاتورة $serial بنجاح.');
  }

  String _createManualVoucher(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final invoiceBox = _invoicesBox();
    if (invoiceBox == null) return _err('لا يمكن الوصول للبيانات');

    final validation = AiChatDomainRulesService.validateManualVoucher(
      kind: args['kind'],
      amount: args['amount'],
      issueDate: args['issueDate'] ?? args['dueDate'],
      partyName: args['partyName'],
      paymentMethod: args['paymentMethod'],
      title: args['title'],
      description: args['description'] ?? args['note'],
      tenantName: args['tenantName'],
      propertyName: args['propertyName'],
      attachmentPaths: args['attachmentPaths'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.manualVoucherRequiredFields(),
        nextStep: 'collect_missing_or_invalid_voucher_fields_then_retry',
        extra: const <String, dynamic>{
          'module': 'invoices',
          'operation': 'create_manual_voucher',
        },
      );
    }

    final draft = validation.draft!;
    String tenantId = '';
    String propertyId = '';
    final tenantName = (draft.tenantName ?? '').trim();
    if (tenantName.isNotEmpty) {
      final t = _findTenant(tenantName);
      if (t != null) tenantId = t.id;
    }
    final propName = (draft.propertyName ?? '').trim();
    if (propName.isNotEmpty) {
      final p = _findProperty(propName);
      if (p != null) propertyId = p.id;
    }

    final id = const Uuid().v4();
    final now = KsaTime.now();
    final serial =
        _nextSerial('V', invoiceBox.values.map((i) => i.serialNo));

    final invoice = Invoice(
      id: id,
      serialNo: serial,
      tenantId: tenantId,
      contractId: '', // فارغ = سند يدوي
      propertyId: propertyId,
      issueDate: draft.issueDate,
      dueDate: draft.issueDate,
      amount: draft.signedAmount,
      paidAmount: draft.amount,
      note: draft.buildInvoiceNote(),
      paymentMethod: draft.paymentMethod,
      attachmentPaths: List<String>.from(draft.attachmentPaths),
      createdAt: now,
      updatedAt: now,
    );
    invoiceBox.put(id, invoice);
    return _ok(
      'تم إنشاء سند يدوي رقم $serial بمبلغ ${draft.amount.toStringAsFixed(2)} ريال.',
    );
  }

  // ================================================================
  //  كتابة - تعديل عقد
  // ================================================================

  String _editContract(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _contractsBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final serial = (args['contractSerialNo'] ?? '').toString().trim();
    final match = box.values
        .where((c) => (c as dynamic).serialNo == serial)
        .firstOrNull;
    if (match == null) return _err('لم يتم العثور على عقد بالرقم $serial');

    if (match.isTerminated) return _err('لا يمكن تعديل عقد منهي.');
    final c = match;
    final validation = AiChatDomainRulesService.validateContractEdit(
      contract: c,
      rentAmount: args['rentAmount'],
      totalAmount: args['totalAmount'],
      notes: args['notes'],
      ejarContractNo: args['ejarContractNo'],
      endDate: args['endDate'],
      paymentCycle: args['paymentCycle'],
      paymentCycleYears: args['paymentCycleYears'],
      advanceMode: args['advanceMode'],
      advancePaid: args['advancePaid'],
      dailyCheckoutHour: args['dailyCheckoutHour'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        nextStep: 'correct_contract_values_then_retry',
        extra: <String, dynamic>{
          'module': 'contracts',
          'operation': 'edit_contract',
          'contractSerialNo': serial,
        },
      );
    }

    final draft = validation.draft!;

    if (draft.rentAmount != null) c.rentAmount = draft.rentAmount!;
    if (draft.totalAmount != null) c.totalAmount = draft.totalAmount!;
    if (draft.notes != null) c.notes = draft.notes!;
    if (draft.ejarContractNo != null) c.ejarContractNo = draft.ejarContractNo!;
    if (draft.endDate != null) c.endDate = draft.endDate!;
    if (draft.paymentCycle != null) c.paymentCycle = draft.paymentCycle!;
    if (draft.paymentCycleYears != null) {
      c.paymentCycleYears = draft.paymentCycleYears!;
    }
    if (draft.advanceMode != null) {
      c.advanceMode = draft.advanceMode!;
      if (draft.advanceMode == AdvanceMode.none) {
        c.advancePaid = null;
      }
    }
    if (draft.advancePaid != null) c.advancePaid = draft.advancePaid!;
    if (draft.dailyCheckoutHour != null) {
      c.dailyCheckoutHour = draft.dailyCheckoutHour!;
    }
    c.updatedAt = KsaTime.now();
    c.save();
    return _ok('تم تعديل العقد $serial بنجاح.');
  }

  // ================================================================
  //  كتابة - تجديد عقد
  // ================================================================

  Future<String> _renewContract(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final contractBox = _contractsBox();
    if (contractBox == null) return _err('لا يمكن الوصول للبيانات');

    final serial = (args['contractSerialNo'] ?? '').toString().trim();
    final old = contractBox.values
        .where((c) => (c as dynamic).serialNo == serial)
        .firstOrNull;
    if (old == null) return _err('لم يتم العثور على عقد بالرقم $serial');

    final od = old;
    final property = _findPropertyById(od.propertyId);
    if (property != null && _isPropertyOrParentArchived(property)) {
      return _archivedPropertyActionError(property, forService: false);
    }
    final validation = AiChatDomainRulesService.validateContractRenew(
      newStartDate: args['newStartDate'],
      newEndDate: args['newEndDate'],
      newRentAmount: args['newRentAmount'] ?? args['rentAmount'],
      newTotalAmount: args['newTotalAmount'] ?? args['totalAmount'],
      notes: args['notes'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        nextStep: 'correct_renewal_values_then_retry',
        extra: <String, dynamic>{
          'module': 'contracts',
          'operation': 'renew_contract',
          'contractSerialNo': serial,
        },
      );
    }

    final draft = validation.draft!;

    final rentAmount = draft.newRentAmount ?? od.rentAmount;
    final totalAmount = draft.newTotalAmount ?? od.totalAmount;

    final id = const Uuid().v4();
    final now = KsaTime.now();
    final newSerial = _nextSerial(
        'C', contractBox.values.map((c) => (c as dynamic).serialNo as String?));

    final renewed = Contract(
      id: id,
      serialNo: newSerial,
      tenantId: od.tenantId,
      propertyId: od.propertyId,
      tenantSnapshot: od.tenantSnapshot,
      propertySnapshot: od.propertySnapshot,
      buildingSnapshot: od.buildingSnapshot,
      startDate: draft.newStartDate,
      endDate: draft.newEndDate,
      rentAmount: rentAmount,
      totalAmount: totalAmount,
      term: od.term,
      termYears: od.termYears,
      paymentCycle: od.paymentCycle,
      paymentCycleYears: od.paymentCycleYears,
      advanceMode: od.advanceMode,
      advancePaid: od.advancePaid,
      dailyCheckoutHour: od.dailyCheckoutHour,
      ejarContractNo: od.ejarContractNo,
      notes: draft.notes ?? od.notes,
      attachmentPaths: List<String>.from(od.attachmentPaths),
      createdAt: now,
      updatedAt: now,
    );
    contractBox.put(id, renewed);
    if (property != null) {
      await _occupyProperty(property);
    }
    if (renewed.isActiveNow) {
      await _incrementTenantActiveContracts(od.tenantId);
    }
    return _ok(
        'تم تجديد العقد بنجاح.\nالعقد القديم: $serial\nالعقد الجديد: $newSerial\nالمبلغ: ${totalAmount.toStringAsFixed(2)} ريال');
  }

  // ================================================================
  //  كتابة - وحدة مبنى
  // ================================================================

  String _addBuildingUnit(Map<String, dynamic> args) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final box = _propertiesBox();
    if (box == null) return _err('لا يمكن الوصول للبيانات');

    final buildingName =
        (args['buildingName'] ?? '').toString().trim().toLowerCase();
    final building = box.values
        .where((p) =>
            p.name.toLowerCase().contains(buildingName) &&
            p.type == PropertyType.building &&
            p.isArchived != true)
        .firstOrNull;
    if (building == null) return _err('لم يتم العثور على عمارة بهذا الاسم');
    final existingUnits = _existingUnitsCountForBuilding(building.id);
    final validation = AiChatDomainRulesService.validateBuildingUnit(
      unitName: args['unitName'],
      unitType: args['unitType'] ?? args['type'],
      rooms: args['rooms'],
      area: args['area'],
      price: args['price'],
      currency: args['currency'],
      baths: args['baths'],
      halls: args['halls'],
      apartmentFloor: args['apartmentFloor'],
      furnished: args['furnished'],
      description: args['description'],
      isPerUnitBuilding: building.rentalMode == RentalMode.perUnit,
      remainingCapacity:
          building.totalUnits > 0 ? building.totalUnits - existingUnits : 999999,
      hasLimitedCapacity: building.totalUnits > 0,
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.buildingUnitRequiredFields(),
        nextStep: 'correct_unit_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'properties',
          'operation': 'add_building_unit',
          'buildingName': building.name,
        },
      );
    }

    final draft = validation.draft!;
    final id = const Uuid().v4();
    final now = KsaTime.now();
    final unit = Property(
      id: id,
      name: draft.unitName,
      type: draft.unitType,
      address: building.address,
      parentBuildingId: building.id,
      rooms: draft.rooms,
      area: draft.area,
      price: draft.price,
      currency: draft.currency,
      description: draft.description,
      createdAt: now,
      updatedAt: now,
    );
    box.put(id, unit);

    return _ok(
        'تمت إضافة الوحدة "${unit.name}" للعمارة "${building.name}" بنجاح.\nعدد الوحدات الحالية: ${existingUnits + 1}');
  }

  // ================================================================
  //  كتابة - صيانة
  // ================================================================

  Future<String> _createMaintenanceRequest(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final propBox = _propertiesBox();
    final maintBox = _maintenanceBox();
    if (propBox == null || maintBox == null) {
      return _err('لا يمكن الوصول للبيانات');
    }

    final propName =
        (args['propertyName'] ?? '').toString().trim().toLowerCase();
    final prop = propBox.values
        .where((p) => p.name.toLowerCase().contains(propName))
        .firstOrNull;
    if (prop == null) return _err('لم يتم العثور على عقار بهذا الاسم');
    if (_isPropertyOrParentArchived(prop)) {
      return _archivedPropertyActionError(prop, forService: true);
    }

    final validation = AiChatDomainRulesService.validateMaintenanceRequest(
      title: args['title'],
      description: args['description'],
      requestType: args['requestType'],
      priority: args['priority'],
      scheduledDate: args['scheduledDate'],
      executionDeadline: args['executionDeadline'],
      cost: args['cost'],
      provider: args['provider'],
      attachmentPaths: args['attachmentPaths'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.maintenanceRequiredFields(),
        nextStep: 'collect_missing_or_invalid_maintenance_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'maintenance',
          'operation': 'create_maintenance_request',
          'propertyName': prop.name,
        },
      );
    }

    final draft = validation.draft!;
    final requestedStatus = AiChatDomainRulesService.normalizeStatus(args['status']);
    if (requestedStatus == MaintenanceStatus.canceled) {
      return jsonEncode(<String, dynamic>{
        'error': 'لا يمكن إنشاء طلب جديد بحالة ملغي من الدردشة لأن الشاشة نفسها لا تسمح بذلك عند الإنشاء.',
        'code': 'maintenance_create_canceled_not_allowed',
      });
    }
    final provider = (draft.providerName ?? '').trim().isEmpty
        ? null
        : _findServiceProvider(draft.providerName!);
    if ((draft.providerName ?? '').trim().isNotEmpty && provider == null) {
      return jsonEncode(<String, dynamic>{
        'error': 'لم يتم العثور على مقدم خدمة بهذا الاسم.',
        'code': 'provider_not_found',
        'providerName': draft.providerName,
      });
    }
    final id = const Uuid().v4();
    final now = KsaTime.now();
    final serial = _nextSerial(
        'M', maintBox.values.map((m) => (m as dynamic).serialNo as String?));

    final req = MaintenanceRequest(
      id: id,
      serialNo: serial,
      propertyId: prop.id,
      tenantId: maintenanceLinkedPartyIdForProperty(
        prop.id,
        serviceType: draft.requestType,
      ),
      title: draft.title,
      description: draft.description,
      requestType: draft.requestType,
      priority: draft.priority,
      status: requestedStatus,
      scheduledDate: draft.scheduledDate,
      executionDeadline: draft.executionDeadline,
      assignedTo: provider?.fullName.trim(),
      providerSnapshot:
          provider == null ? null : buildMaintenanceProviderSnapshot(provider),
      cost: draft.cost,
      attachmentPaths: List<String>.from(draft.attachmentPaths),
      completedDate: requestedStatus == MaintenanceStatus.completed ? now : null,
      createdAt: now,
    );

    String? createdInvoiceId;
    String? createdInvoiceSerial;
    if (requestedStatus == MaintenanceStatus.completed) {
      final invoiceId = await createOrUpdateInvoiceForMaintenance(req);
      if (invoiceId.trim().isNotEmpty) {
        req.invoiceId = invoiceId.trim();
        createdInvoiceId = invoiceId.trim();
        createdInvoiceSerial = _invoicesBox()?.get(invoiceId.trim())?.serialNo;
      }
    }

    maintBox.put(id, req);
    return jsonEncode(<String, dynamic>{
      'success': true,
      'message':
          'تم إنشاء طلب الصيانة "$serial - ${req.title}" بنجاح.',
      'requestSerialNo': serial,
      'requestId': id,
      'status': AiChatDomainRulesService.statusLabel(requestedStatus),
      if (createdInvoiceId != null) 'invoiceId': createdInvoiceId,
      if ((createdInvoiceSerial ?? '').trim().isNotEmpty)
        'invoiceSerialNo': createdInvoiceSerial,
    });
  }

  Future<String> _updateMaintenanceStatus(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final m = _findMaintenance(args['query'] ?? '');
    if (m == null) return _err('لم يتم العثور على طلب الصيانة');

    final validation = AiChatDomainRulesService.validateMaintenanceStatus(
      status: args['status'],
      cost: args['cost'],
      provider: args['provider'],
      scheduledDate: args['scheduledDate'],
      executionDeadline: args['executionDeadline'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        nextStep: 'correct_maintenance_status_fields_then_retry',
        extra: <String, dynamic>{
          'module': 'maintenance',
          'operation': 'update_maintenance_status',
          'requestSerialNo': m.serialNo,
        },
      );
    }

    final draft = validation.draft!;
    final provider = (draft.providerName ?? '').trim().isEmpty
        ? null
        : _findServiceProvider(draft.providerName!);
    if ((draft.providerName ?? '').trim().isNotEmpty && provider == null) {
      return jsonEncode(<String, dynamic>{
        'error': 'لم يتم العثور على مقدم خدمة بهذا الاسم.',
        'code': 'provider_not_found',
        'providerName': draft.providerName,
      });
    }

    m.status = draft.status;
    m.cost = draft.cost ?? m.cost;
    if (draft.providerName != null) {
      m.assignedTo = provider?.fullName.trim();
      m.providerSnapshot =
          provider == null ? null : buildMaintenanceProviderSnapshot(provider);
    }
    if (draft.scheduledDate != null) m.scheduledDate = draft.scheduledDate;
    if (draft.executionDeadline != null) {
      m.executionDeadline = draft.executionDeadline;
    }
    if (draft.status == MaintenanceStatus.completed) {
      m.completedDate ??= KsaTime.now();
      if ((m.invoiceId ?? '').trim().isEmpty) {
        final invoiceId = await createOrUpdateInvoiceForMaintenance(m);
        if (invoiceId.trim().isNotEmpty) {
          m.invoiceId = invoiceId.trim();
        }
      }
    }
    if (draft.status == MaintenanceStatus.canceled ||
        draft.status == MaintenanceStatus.completed) {
      if ((m.periodicServiceType ?? '').trim().isNotEmpty) {
        await markPeriodicServiceRequestSuppressedForCurrentCycle(m);
      }
    }
    m.save();
    return _ok(
        'تم تحديث حالة طلب الصيانة "${m.title}" إلى "${AiChatDomainRulesService.statusLabel(draft.status)}".');
  }

  // ================================================================
  //  خدمات دورية
  // ================================================================

  static const _serviceTypes = ['cleaning', 'elevator', 'internet', 'water', 'electricity'];

  static String _serviceLabel(String type) {
    switch (type) {
      case 'cleaning': return 'نظافة عمارة';
      case 'elevator': return 'صيانة مصعد';
      case 'internet': return 'خدمة إنترنت';
      case 'water': return 'خدمة مياه مشتركة';
      case 'electricity': return 'خدمة كهرباء مشتركة';
      default: return 'خدمات';
    }
  }

  static String _serviceTitle(String type) {
    switch (type) {
      case 'cleaning': return 'طلب نظافة عمارة';
      case 'elevator': return 'طلب صيانة مصعد';
      case 'internet': return 'طلب تجديد خدمة إنترنت';
      case 'water': return 'طلب فاتورة مياه مشتركة';
      case 'electricity': return 'طلب فاتورة كهرباء مشتركة';
      default: return 'طلب خدمة';
    }
  }

  Box<Map>? _servicesBox() {
    final name = boxName('servicesConfig');
    return Hive.isBoxOpen(name) ? Hive.box<Map>(name) : null;
  }

  String _normalizeServiceType(String? s) {
    if (s == null) return '';
    final lower = s.toLowerCase().trim();
    if (lower.contains('نظافة') || lower == 'cleaning') return 'cleaning';
    if (lower.contains('مصعد') || lower == 'elevator') return 'elevator';
    if (lower.contains('إنترنت') || lower.contains('انترنت') || lower == 'internet') return 'internet';
    if (lower.contains('مياه') || lower.contains('ماء') || lower == 'water') return 'water';
    if (lower.contains('كهرباء') || lower == 'electricity') return 'electricity';
    return lower;
  }

  Map<String, dynamic> _periodicServiceConfigForPropertyId(
    String propertyId,
    String type,
  ) {
    final box = _servicesBox();
    if (box == null) return const <String, dynamic>{};
    final raw = box.get(_periodicConfigKey(propertyId, type));
    if (raw is! Map) return const <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  Property? _periodicServiceParentProperty(Property property) {
    final parentId = (property.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return null;
    final box = _propertiesBox();
    if (box == null) return null;
    return _firstWhereOrNull(
      box.values.cast<Property>(),
      (item) => item.id == parentId,
    );
  }

  bool _periodicServiceIsBuildingWithUnits(Property property) =>
      property.type == PropertyType.building &&
      property.rentalMode == RentalMode.perUnit;

  bool _periodicServiceIsUnitUnderPerUnitBuilding(Property property) {
    final parent = _periodicServiceParentProperty(property);
    if (parent == null) return false;
    return parent.type == PropertyType.building &&
        parent.rentalMode == RentalMode.perUnit;
  }

  DateTime? _periodicServiceDate(Object? raw) {
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    try {
      final parsed = DateTime.parse(text);
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  double? _periodicServiceNumber(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  int? _periodicServiceInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  String? _normalizeSharedBillingMode(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'shared' || value == 'مشترك') return 'shared';
    if (value == 'separate' ||
        value == 'tenant' ||
        value == 'منفصل' ||
        value == 'على المستأجر') {
      return 'separate';
    }
    return null;
  }

  String? _normalizeInternetBillingMode(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'owner' || value == 'مالك' || value == 'على المالك') {
      return 'owner';
    }
    if (value == 'separate' ||
        value == 'tenant' ||
        value == 'منفصل' ||
        value == 'على المستأجر') {
      return 'separate';
    }
    return null;
  }

  String? _normalizeWaterSharedMethod(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'fixed' || value == 'مبلغ' || value == 'مقطوع') {
      return 'fixed';
    }
    if (value == 'percent' || value == 'percentage' || value == 'نسبة') {
      return 'percent';
    }
    return null;
  }

  String _periodicServiceInternetBillingMode(Map<String, dynamic> cfg) {
    final payer = (cfg['payer'] ?? '').toString().trim().toLowerCase();
    final raw = (cfg['internetBillingMode'] ??
            (payer == 'tenant' ? 'separate' : 'owner'))
        .toString()
        .trim()
        .toLowerCase();
    return raw == 'separate' ? 'separate' : 'owner';
  }

  String _periodicServiceWaterBillingMode(Map<String, dynamic> cfg) {
    final raw = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'shared') return 'shared';
    if (raw == 'separate') return 'separate';
    return (cfg['waterMeterNo'] ?? '').toString().trim().isNotEmpty
        ? 'separate'
        : '';
  }

  String _periodicServiceWaterSharedMethod(Map<String, dynamic> cfg) {
    final raw = (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'fixed') return 'fixed';
    if (raw == 'percent') return 'percent';
    return '';
  }

  String _periodicServiceElectricityBillingMode(Map<String, dynamic> cfg) {
    final raw = (cfg['electricityBillingMode'] ?? cfg['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'shared') return 'shared';
    if (raw == 'separate') return 'separate';
    return (cfg['electricityMeterNo'] ?? '').toString().trim().isNotEmpty
        ? 'separate'
        : '';
  }

  DateTime _periodicServiceRequestAnchor(MaintenanceRequest request) =>
      _notificationDateOnly(
        request.periodicCycleDate ??
            request.executionDeadline ??
            request.scheduledDate ??
            request.createdAt,
      );

  List<MaintenanceRequest> _periodicServiceRequestsFor(
    String propertyId,
    String type,
  ) {
    final box = _maintenanceBox();
    if (box == null) return const <MaintenanceRequest>[];
    final requests = box.values
        .where((request) {
          if (request.isArchived) return false;
          if (request.propertyId != propertyId) return false;
          return _normalizeServiceType(request.periodicServiceType?.toString()) ==
              type;
        })
        .cast<MaintenanceRequest>()
        .toList(growable: false);
    requests.sort(
      (a, b) => _periodicServiceRequestAnchor(b)
          .compareTo(_periodicServiceRequestAnchor(a)),
    );
    return requests;
  }

  Map<String, dynamic>? _serializePeriodicServiceRequest(
    MaintenanceRequest? request,
  ) {
    if (request == null) return null;
    return <String, dynamic>{
      'id': request.id,
      'serialNo': request.serialNo,
      'title': request.title,
      'status': request.status.name,
      'assignedTo': request.assignedTo,
      'cost': request.cost,
      'scheduledDate':
          request.scheduledDate == null ? null : _fmtDate(request.scheduledDate!),
      'executionDeadline': request.executionDeadline == null
          ? null
          : _fmtDate(request.executionDeadline!),
      'periodicCycleDate': request.periodicCycleDate == null
          ? null
          : _fmtDate(request.periodicCycleDate!),
      'completedDate':
          request.completedDate == null ? null : _fmtDate(request.completedDate!),
      'createdAt': _fmtDate(request.createdAt),
      'invoiceId': (request.invoiceId ?? '').trim().isEmpty ? null : request.invoiceId,
    };
  }

  DateTime? _periodicServiceVisibleDueDate(
    Property property,
    String type,
    Map<String, dynamic> cfg,
    List<MaintenanceRequest> requests,
  ) {
    final openRequest = _firstWhereOrNull(
      requests,
      (item) =>
          item.status == MaintenanceStatus.open ||
          item.status == MaintenanceStatus.inProgress,
    );
    final ownerManaged = type == 'cleaning' ||
        type == 'elevator' ||
        (type == 'internet' &&
            _periodicServiceInternetBillingMode(cfg) == 'owner');
    if (ownerManaged && openRequest != null) {
      return _periodicServiceRequestAnchor(openRequest);
    }
    return _periodicServiceDate(cfg['nextDueDate'] ?? cfg['nextServiceDate']);
  }

  bool _periodicServiceConfigured(
    Property property,
    String type,
    Map<String, dynamic> cfg,
  ) {
    if (_periodicServiceIsBuildingWithUnits(property) &&
        (type == 'water' || type == 'electricity')) {
      final mode = (cfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
      if (mode == 'units') return true;
      if (mode == 'shared_percent') {
        return _periodicServiceDate(cfg['nextDueDate']) != null &&
            _asMapList(cfg['sharedPercentUnitShares']).isNotEmpty;
      }
      return false;
    }

    if (_periodicServiceIsUnitUnderPerUnitBuilding(property) &&
        (type == 'water' || type == 'electricity')) {
      final parent = _periodicServiceParentProperty(property);
      if (parent == null) return false;
      final parentCfg = _periodicServiceConfigForPropertyId(parent.id, type);
      final mode =
          (parentCfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
      if (mode == 'shared_percent') {
        return _periodicServiceDate(parentCfg['nextDueDate']) != null;
      }
      if (mode != 'units') return false;
    }

    if (cfg.isEmpty) return false;

    switch (type) {
      case 'cleaning':
      case 'elevator':
        return (_periodicServiceDate(cfg['startDate']) ??
                    _periodicServiceDate(cfg['nextDueDate'])) !=
                null &&
            (cfg['providerName'] ?? cfg['provider'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
      case 'internet':
        if (_periodicServiceInternetBillingMode(cfg) == 'separate') return true;
        return (_periodicServiceDate(cfg['startDate']) ??
                    _periodicServiceDate(cfg['nextDueDate'])) !=
                null &&
            (cfg['providerName'] ?? cfg['provider'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
      case 'water':
        final billingMode = _periodicServiceWaterBillingMode(cfg);
        if (billingMode == 'separate') return true;
        if (billingMode != 'shared') return false;
        final method = _periodicServiceWaterSharedMethod(cfg);
        if (method == 'percent') {
          return (_periodicServiceNumber(cfg['sharePercent']) ?? 0) > 0;
        }
        if (method == 'fixed') {
          return (_periodicServiceNumber(cfg['totalWaterAmount']) ?? 0) > 0 ||
              _asMapList(cfg['waterInstallments']).isNotEmpty;
        }
        return false;
      case 'electricity':
        final billingMode = _periodicServiceElectricityBillingMode(cfg);
        if (billingMode == 'separate') return true;
        if (billingMode != 'shared') return false;
        return (_periodicServiceNumber(cfg['electricitySharePercent']) ?? 0) > 0;
      default:
        return cfg.isNotEmpty;
    }
  }

  String? _periodicServiceWriteBoundaryReason({
    required Property property,
    required String type,
    required Map<String, dynamic> existingConfig,
    Map<String, dynamic> args = const <String, dynamic>{},
  }) {
    final requestedSharedUnitsMode =
        (args['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
    final requestedUnitShares = _coerceJsonObject(args['unitShares']);
    final requestedPercentShares = _coerceJsonObject(
      args['sharedPercentUnitShares'],
    );
    if ((type == 'water' || type == 'electricity') &&
        (_periodicServiceIsBuildingWithUnits(property) ||
            _periodicServiceIsUnitUnderPerUnitBuilding(property) ||
            requestedSharedUnitsMode.isNotEmpty ||
            requestedUnitShares.isNotEmpty ||
            requestedPercentShares.isNotEmpty)) {
      return 'إدارة توزيع ${_serviceLabel(type)} على الوحدات أو نسب الشقق تتم من شاشة خدمات العقار نفسها.';
    }

    if (args['executeNow'] == true || args['runNow'] == true) {
      return 'تنفيذ العملية الفورية لهذا النوع ما زال مرتبطًا بعناصر الشاشة التفاعلية داخل خدمات العقار.';
    }

    if (type == 'water') {
      final billingMode =
          _normalizeSharedBillingMode(args['billingMode'] ?? args['waterBillingMode']) ??
              _periodicServiceWaterBillingMode(existingConfig);
      final sharedMethod = _normalizeWaterSharedMethod(
            args['sharedMethod'] ?? args['waterSharedMethod'],
          ) ??
          _periodicServiceWaterSharedMethod(existingConfig);
      if (billingMode == 'shared' &&
          sharedMethod == 'fixed' &&
          _hasActiveContractForPropertyId(property.id)) {
        return 'توزيع المياه الثابتة على دفعات العقد النشط يحتاج شاشة خدمات العقار.';
      }
    }

    return null;
  }

  String _periodicServiceScreenOnlyPayload({
    required Property property,
    required String type,
    required String reason,
    String? flow,
  }) {
    return jsonEncode(<String, dynamic>{
      'error': reason,
      'requiresScreenCompletion': true,
      'suggestedScreen': 'property_services',
      'propertyName': property.name,
      'propertyId': property.id,
      'serviceType': type,
      'serviceLabel': _serviceLabel(type),
      'nextStep': 'open_property_services_and_complete_then_retry',
      if (flow != null) 'screenOnlyFlow': flow,
      'navigationAction': <String, dynamic>{
        'route': '/property/services',
        'arguments': <String, dynamic>{
          'propertyId': property.id,
          'openService': type,
        },
      },
    });
  }

  String _periodicServiceStatusLabel(
    Property property,
    String type,
    Map<String, dynamic> cfg,
    List<MaintenanceRequest> requests,
  ) {
    final configured = _periodicServiceConfigured(property, type, cfg);
    if (!configured) return 'غير مضبوط';

    if (_periodicServiceIsBuildingWithUnits(property) &&
        (type == 'water' || type == 'electricity')) {
      final mode = (cfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
      if (type == 'water' && mode == 'units_fixed') {
        return 'الإدارة من الوحدات (مبلغ مقطوع)';
      }
      if (type == 'water' && mode == 'units_separate') {
        return 'الإدارة من الوحدات (منفصل)';
      }
      if (mode == 'units') {
        return type == 'electricity'
            ? 'الإدارة من الوحدات (منفصل)'
            : 'الإدارة من الوحدات (مبلغ مقطوع)';
      }
      if (mode == 'shared_percent') {
        return 'التوزيع على الشقق المؤجرة بالتساوي';
      }
    }

    if (_periodicServiceIsUnitUnderPerUnitBuilding(property) &&
        (type == 'water' || type == 'electricity')) {
      final parent = _periodicServiceParentProperty(property);
      if (parent != null) {
        final parentCfg = _periodicServiceConfigForPropertyId(parent.id, type);
        final mode =
            (parentCfg['sharedUnitsMode'] ?? '').toString().trim().toLowerCase();
        if (mode == 'shared_percent') {
          return 'يُدار من العمارة بالتساوي على الشقق المؤجرة';
        }
      }
    }

    if (type == 'internet' &&
        _periodicServiceInternetBillingMode(cfg) == 'separate') {
      return 'مفعل بنمط منفصل';
    }
    if (type == 'water') {
      final billingMode = _periodicServiceWaterBillingMode(cfg);
      final method = _periodicServiceWaterSharedMethod(cfg);
      if (billingMode == 'separate') return 'على المستأجر مباشرة';
      if (billingMode == 'shared' && method == 'percent') {
        final percent = _periodicServiceNumber(cfg['sharePercent']) ?? 0;
        return 'مشترك بالنسبة ${percent.toStringAsFixed(2)}%';
      }
      if (billingMode == 'shared' && method == 'fixed') {
        if (!_hasActiveContractForPropertyId(property.id)) {
          return 'مبلغ محفوظ بانتظار عقد نشط';
        }
      }
    }
    if (type == 'electricity') {
      final billingMode = _periodicServiceElectricityBillingMode(cfg);
      if (billingMode == 'separate') return 'على المستأجر مباشرة';
      if (billingMode == 'shared') {
        final percent = _periodicServiceNumber(cfg['electricitySharePercent']) ?? 0;
        return 'مشترك بالنسبة ${percent.toStringAsFixed(2)}%';
      }
    }

    final nextDue = _periodicServiceVisibleDueDate(property, type, cfg, requests);
    if (nextDue != null) return 'الموعد القادم ${_fmtDate(nextDue)}';
    return 'مفعل';
  }

  List<Map<String, dynamic>> _periodicServicePreviewRows(
    Object? raw, {
    int limit = 10,
  }) {
    final rows = _asMapList(raw).map((item) {
      final row = Map<String, dynamic>.from(item);
      final anchor = _periodicServiceDate(row['dueDate'] ?? row['date']);
      if (anchor != null) {
        if (row.containsKey('dueDate')) row['dueDate'] = _fmtDate(anchor);
        if (row.containsKey('date')) row['date'] = _fmtDate(anchor);
      }
      return row;
    }).toList(growable: false);
    rows.sort((a, b) {
      final aDate = _periodicServiceDate(a['dueDate'] ?? a['date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _periodicServiceDate(b['dueDate'] ?? b['date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    if (rows.length <= limit) return rows;
    return rows.take(limit).toList(growable: false);
  }

  String? _upsertOwnerManagedPeriodicRequest({
    required Property property,
    required String type,
    required Tenant provider,
    required double amount,
    required DateTime dueDate,
  }) {
    final maintBox = _maintenanceBox();
    if (maintBox == null) return null;

    final openRequest = _firstWhereOrNull(maintBox.values, (request) {
      if (request.isArchived) return false;
      if (request.propertyId != property.id) return false;
      if (_normalizeServiceType(request.periodicServiceType?.toString()) != type) {
        return false;
      }
      return request.status == MaintenanceStatus.open ||
          request.status == MaintenanceStatus.inProgress;
    });

    if (openRequest != null) {
      openRequest.title = _serviceTitle(type);
      openRequest.requestType = _serviceLabel(type);
      openRequest.assignedTo = provider.fullName.trim();
      openRequest.providerSnapshot = buildMaintenanceProviderSnapshot(provider);
      openRequest.cost = amount;
      openRequest.scheduledDate = dueDate;
      openRequest.executionDeadline = dueDate;
      openRequest.periodicCycleDate = dueDate;
      openRequest.save();
      return openRequest.serialNo;
    }

    final id = const Uuid().v4();
    final serial = _nextSerial(
      'M',
      maintBox.values.map((item) => (item as dynamic).serialNo as String?),
    );

    maintBox.put(
      id,
      MaintenanceRequest(
        id: id,
        serialNo: serial,
        propertyId: property.id,
        tenantId: maintenanceLinkedPartyIdForProperty(
          property.id,
          serviceType: type,
        ),
        title: _serviceTitle(type),
        description: '',
        requestType: _serviceLabel(type),
        priority: MaintenancePriority.medium,
        status: MaintenanceStatus.open,
        scheduledDate: dueDate,
        executionDeadline: dueDate,
        assignedTo: provider.fullName.trim(),
        providerSnapshot: buildMaintenanceProviderSnapshot(provider),
        cost: amount,
        periodicServiceType: type,
        periodicCycleDate: dueDate,
        createdAt: KsaTime.now(),
      ),
    );
    return serial;
  }

  String _mutatePeriodicService(
    Map<String, dynamic> args, {
    required bool isCreate,
  }) {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final svcBox = _servicesBox();
    if (svcBox == null) return _err('لا يمكن الوصول لإعدادات الخدمات');

    final prop = _findProperty((args['propertyName'] ?? '').toString());
    if (prop == null) return _err('لم يتم العثور على عقار بهذا الاسم');
    if (_isPropertyOrParentArchived(prop)) {
      return _archivedPropertyActionError(prop, forService: true);
    }

    final type = _normalizeServiceType((args['serviceType'] ?? '').toString());
    if (!_serviceTypes.contains(type)) {
      return _err('نوع الخدمة غير معروف.');
    }

    final cfgKey = _periodicConfigKey(prop.id, type);
    final existingCfg = svcBox.get(cfgKey)?.cast<String, dynamic>() ?? {};
    if (isCreate && existingCfg.isNotEmpty) {
      return jsonEncode(<String, dynamic>{
        'error': 'هذه الخدمة الدورية مضبوطة مسبقًا لهذا العقار. استخدم التحديث بدل الإنشاء.',
        'code': 'periodic_service_already_exists',
        'propertyName': prop.name,
        'serviceType': type,
      });
    }
    if (!isCreate && existingCfg.isEmpty) {
      return jsonEncode(<String, dynamic>{
        'error': 'هذه الخدمة الدورية غير مضبوطة بعد لهذا العقار. ابدأ بالإنشاء أولًا.',
        'code': 'periodic_service_not_found',
        'propertyName': prop.name,
        'serviceType': type,
      });
    }

    final screenOnlyReason = _periodicServiceWriteBoundaryReason(
      property: prop,
      type: type,
      existingConfig: existingCfg,
      args: args,
    );
    if (screenOnlyReason != null) {
      return _periodicServiceScreenOnlyPayload(
        property: prop,
        type: type,
        reason: screenOnlyReason,
        flow: type == 'water' || type == 'electricity'
            ? 'shared_units_or_installments'
            : 'screen_only_flow',
      );
    }

    Map<String, String> issue(String field, String label, String message) =>
        <String, String>{
          'field': field,
          'label': label,
          'message': message,
        };

    String validationError(
      String message, {
      List<Map<String, String>> missingFields = const <Map<String, String>>[],
    }) {
      return jsonEncode(<String, dynamic>{
        'error': message,
        'suggestedScreen': 'property_services',
        'propertyName': prop.name,
        'propertyId': prop.id,
        'serviceType': type,
        'serviceLabel': _serviceLabel(type),
        if (missingFields.isNotEmpty) 'missingFields': missingFields,
      });
    }

    String saveOwnerManaged({
      Map<String, dynamic> extraConfig = const <String, dynamic>{},
    }) {
      const allowedRecurrence = <int>{0, 1, 2, 3, 6, 12};
      final providerQuery = (args['provider'] ?? args['providerName'] ?? '')
          .toString()
          .trim();
      final existingProviderName =
          (existingCfg['providerName'] ?? existingCfg['provider'] ?? '')
              .toString()
              .trim();
      final effectiveProviderQuery =
          providerQuery.isNotEmpty ? providerQuery : existingProviderName;
      if (effectiveProviderQuery.isEmpty) {
        return validationError(
          'مقدم الخدمة مطلوب لهذه الخدمة.',
          missingFields: <Map<String, String>>[
            issue('provider', 'مقدم الخدمة', 'مقدم الخدمة مطلوب'),
          ],
        );
      }

      final provider = _findServiceProvider(effectiveProviderQuery);
      if (provider == null) {
        return jsonEncode(<String, dynamic>{
          'error': 'لم يتم العثور على مقدم خدمة بهذا الاسم.',
          'code': 'provider_not_found',
          'providerName': effectiveProviderQuery,
        });
      }

      final amount = _periodicServiceNumber(
            args['cost'] ?? args['defaultAmount'],
          ) ??
          _periodicServiceNumber(
            existingCfg['defaultAmount'] ?? existingCfg['cost'],
          ) ??
          0.0;
      if (amount < 0) {
        return validationError('تكلفة الخدمة لا يمكن أن تكون سالبة.');
      }

      final dueDate = _periodicServiceDate(
            args['nextDueDate'] ?? args['scheduledDate'],
          ) ??
          _periodicServiceDate(existingCfg['nextDueDate']) ??
          _periodicServiceDate(existingCfg['startDate']);
      if (dueDate == null) {
        return validationError(
          'تاريخ الدورة القادمة مطلوب لهذه الخدمة.',
          missingFields: <Map<String, String>>[
            issue('nextDueDate', 'تاريخ الدورة القادمة', 'تاريخ الدورة القادمة مطلوب'),
          ],
        );
      }

      final recurrenceMonths = args.containsKey('recurrenceMonths')
          ? _periodicServiceInt(args['recurrenceMonths'])
          : _periodicServiceInt(existingCfg['recurrenceMonths']);
      if (args.containsKey('recurrenceMonths') &&
          (recurrenceMonths == null ||
              !allowedRecurrence.contains(recurrenceMonths))) {
        return validationError(
          'قيمة التكرار يجب أن تكون واحدة من: 0 أو 1 أو 2 أو 3 أو 6 أو 12.',
          missingFields: <Map<String, String>>[
            issue(
              'recurrenceMonths',
              'التكرار',
              'القيم المسموحة: 0 أو 1 أو 2 أو 3 أو 6 أو 12',
            ),
          ],
        );
      }

      final remindBeforeDays = args.containsKey('remindBeforeDays')
          ? _periodicServiceInt(args['remindBeforeDays'])
          : _periodicServiceInt(existingCfg['remindBeforeDays']);
      if (args.containsKey('remindBeforeDays') &&
          (remindBeforeDays == null ||
              remindBeforeDays < 0 ||
              remindBeforeDays > 3)) {
        return validationError(
          'قيمة التذكير قبل الموعد يجب أن تكون بين 0 و3 أيام.',
          missingFields: <Map<String, String>>[
            issue(
              'remindBeforeDays',
              'التذكير قبل الموعد',
              'القيم المسموحة من 0 إلى 3 أيام',
            ),
          ],
        );
      }

      final nextCfg = <String, dynamic>{
        ...existingCfg,
        ...extraConfig,
        'serviceType': type,
        'payer': 'owner',
        'provider': provider.fullName.trim(),
        'providerId': provider.id,
        'providerName': provider.fullName.trim(),
        'defaultAmount': amount,
        'cost': amount,
        'startDate': dueDate.toIso8601String(),
        'nextDueDate': dueDate.toIso8601String(),
        'dueDay': dueDate.day,
        'recurrenceMonths': recurrenceMonths ?? 0,
        'remindBeforeDays': remindBeforeDays ?? 0,
      };
      svcBox.put(cfgKey, nextCfg);

      final requestSerial = _upsertOwnerManagedPeriodicRequest(
        property: prop,
        type: type,
        provider: provider,
        amount: amount,
        dueDate: dueDate,
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message':
            'تم حفظ إعدادات ${_serviceLabel(type)} للعقار "${prop.name}" بنجاح.',
        'operation': isCreate ? 'create' : 'update',
        'propertyName': prop.name,
        'propertyId': prop.id,
        'serviceType': type,
        'serviceLabel': _serviceLabel(type),
        if (requestSerial != null) 'requestSerialNo': requestSerial,
        'applied': <String, dynamic>{
          'providerName': provider.fullName.trim(),
          'cost': amount,
          'nextDueDate': _fmtDate(dueDate),
          'recurrenceMonths': recurrenceMonths ?? 0,
          'remindBeforeDays': remindBeforeDays ?? 0,
          ...extraConfig,
        },
      });
    }

    switch (type) {
      case 'cleaning':
      case 'elevator':
        return saveOwnerManaged();
      case 'internet':
        final requestedMode = _normalizeInternetBillingMode(
          args['billingMode'] ?? args['internetBillingMode'] ?? args['payer'],
        );
        final mode =
            requestedMode ?? _periodicServiceInternetBillingMode(existingCfg);
        if (mode == 'separate') {
          final nextCfg = <String, dynamic>{
            ...existingCfg,
            'serviceType': type,
            'internetBillingMode': 'separate',
            'payer': 'tenant',
            'provider': '',
            'providerId': '',
            'providerName': '',
            'defaultAmount': 0.0,
            'cost': 0.0,
            'startDate': '',
            'nextDueDate': '',
            'dueDay': '',
            'recurrenceMonths': 0,
            'remindBeforeDays': 0,
            'lastGeneratedRequestDate': '',
            'lastGeneratedRequestId': '',
            'targetId': '',
            'suppressedRequestDate': '',
          };
          svcBox.put(cfgKey, nextCfg);
          return jsonEncode(<String, dynamic>{
            'success': true,
            'message':
                'تم ضبط خدمة الإنترنت على المستأجر مباشرة للعقار "${prop.name}".',
            'operation': isCreate ? 'create' : 'update',
            'propertyName': prop.name,
            'propertyId': prop.id,
            'serviceType': type,
            'serviceLabel': _serviceLabel(type),
            'applied': const <String, dynamic>{
              'internetBillingMode': 'separate',
              'payer': 'tenant',
            },
          });
        }
        return saveOwnerManaged(
          extraConfig: const <String, dynamic>{'internetBillingMode': 'owner'},
        );
      case 'water':
        final billingMode =
            _normalizeSharedBillingMode(args['billingMode'] ?? args['waterBillingMode']) ??
                _periodicServiceWaterBillingMode(existingCfg);
        if (billingMode.isEmpty) {
          return validationError(
            'يجب تحديد نمط فوترة المياه: shared أو separate.',
            missingFields: <Map<String, String>>[
              issue('billingMode', 'نمط الفوترة', 'نمط الفوترة مطلوب'),
            ],
          );
        }
        if (billingMode == 'separate') {
          final meterNo = (args['meterNumber'] ??
                  args['waterMeterNo'] ??
                  existingCfg['waterMeterNo'] ??
                  '')
              .toString()
              .trim();
          if (meterNo.isNotEmpty && !RegExp(r'^\d{4,20}$').hasMatch(meterNo)) {
            return validationError('رقم عداد المياه يجب أن يكون بين 4 و20 رقمًا.');
          }
          final nextCfg = <String, dynamic>{
            ...existingCfg,
            'serviceType': type,
            'waterBillingMode': 'separate',
            'payer': 'tenant',
            'waterMeterNo': meterNo,
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
            'dueDay': '',
            'recurrenceMonths': 0,
            'remindBeforeDays': 0,
          };
          svcBox.put(cfgKey, nextCfg);
          return jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'تم ضبط المياه بنمط منفصل للعقار "${prop.name}".',
            'operation': isCreate ? 'create' : 'update',
            'propertyName': prop.name,
            'propertyId': prop.id,
            'serviceType': type,
            'serviceLabel': _serviceLabel(type),
            'applied': <String, dynamic>{
              'waterBillingMode': 'separate',
              'payer': 'tenant',
              'meterNumber': meterNo,
            },
          });
        }

        final sharedMethod = _normalizeWaterSharedMethod(
              args['sharedMethod'] ?? args['waterSharedMethod'],
            ) ??
            _periodicServiceWaterSharedMethod(existingCfg);
        if (sharedMethod.isEmpty) {
          return validationError(
            'يجب تحديد طريقة توزيع المياه المشتركة: fixed أو percent.',
            missingFields: <Map<String, String>>[
              issue('sharedMethod', 'طريقة التوزيع', 'طريقة التوزيع مطلوبة'),
            ],
          );
        }

        final remindBeforeDays = args.containsKey('remindBeforeDays')
            ? _periodicServiceInt(args['remindBeforeDays'])
            : _periodicServiceInt(existingCfg['remindBeforeDays']);
        if (args.containsKey('remindBeforeDays') &&
            (remindBeforeDays == null ||
                remindBeforeDays < 0 ||
                remindBeforeDays > 3)) {
          return validationError(
            'قيمة التذكير قبل الموعد يجب أن تكون بين 0 و3 أيام.',
          );
        }

        if (sharedMethod == 'percent') {
          final sharePercent = _periodicServiceNumber(args['sharePercent']) ??
              _periodicServiceNumber(existingCfg['sharePercent']);
          if (sharePercent == null || sharePercent <= 0) {
            return validationError(
              'النسبة المطلوبة للمياه المشتركة يجب أن تكون أكبر من صفر.',
              missingFields: <Map<String, String>>[
                issue('sharePercent', 'النسبة', 'النسبة مطلوبة ويجب أن تكون أكبر من صفر'),
              ],
            );
          }
          final dueDate = _periodicServiceDate(
                args['nextDueDate'] ?? args['scheduledDate'],
              ) ??
              _periodicServiceDate(existingCfg['nextDueDate']);
          if (dueDate == null) {
            return validationError(
              'تاريخ الاستحقاق القادم مطلوب للمياه المشتركة بالنسبة.',
              missingFields: <Map<String, String>>[
                issue('nextDueDate', 'تاريخ الاستحقاق', 'تاريخ الاستحقاق مطلوب'),
              ],
            );
          }
          final nextCfg = <String, dynamic>{
            ...existingCfg,
            'serviceType': type,
            'waterBillingMode': 'shared',
            'waterSharedMethod': 'percent',
            'payer': 'owner',
            'sharePercent': sharePercent,
            'nextDueDate': dueDate.toIso8601String(),
            'dueDay': dueDate.day,
            'recurrenceMonths': 1,
            'remindBeforeDays': remindBeforeDays ?? 0,
            'waterMeterNo': '',
            'totalWaterAmount': null,
            'waterPerInstallment': null,
            'waterLinkedContractId': '',
            'waterLinkedTenantId': '',
            'remainingInstallmentsCount': 0,
          };
          svcBox.put(cfgKey, nextCfg);
          return jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'تم حفظ إعدادات المياه المشتركة للعقار "${prop.name}".',
            'operation': isCreate ? 'create' : 'update',
            'propertyName': prop.name,
            'propertyId': prop.id,
            'serviceType': type,
            'serviceLabel': _serviceLabel(type),
            'applied': <String, dynamic>{
              'waterBillingMode': 'shared',
              'waterSharedMethod': 'percent',
              'sharePercent': sharePercent,
              'nextDueDate': _fmtDate(dueDate),
              'remindBeforeDays': remindBeforeDays ?? 0,
            },
          });
        }

        final totalAmount = _periodicServiceNumber(
              args['totalAmount'] ?? args['cost'],
            ) ??
            _periodicServiceNumber(existingCfg['totalWaterAmount']);
        if (totalAmount == null || totalAmount <= 0) {
          return validationError(
            'المبلغ الكلي للمياه المشتركة يجب أن يكون أكبر من صفر.',
            missingFields: <Map<String, String>>[
              issue('totalAmount', 'المبلغ الكلي', 'المبلغ الكلي مطلوب ويجب أن يكون أكبر من صفر'),
            ],
          );
        }
        final dueDate = _periodicServiceDate(
              args['nextDueDate'] ?? args['scheduledDate'],
            ) ??
            _periodicServiceDate(existingCfg['nextDueDate']);
        final nextCfg = <String, dynamic>{
          ...existingCfg,
          'serviceType': type,
          'waterBillingMode': 'shared',
          'waterSharedMethod': 'fixed',
          'payer': 'owner',
          'totalWaterAmount': totalAmount,
          'nextDueDate': dueDate?.toIso8601String() ?? '',
          'dueDay': dueDate?.day ?? '',
          'recurrenceMonths': 0,
          'remindBeforeDays': remindBeforeDays ?? 0,
          'sharePercent': null,
          'waterPercentRequests': <Map<String, dynamic>>[],
          'waterMeterNo': '',
          'waterLinkedContractId': '',
          'waterLinkedTenantId': '',
        };
        svcBox.put(cfgKey, nextCfg);
        return jsonEncode(<String, dynamic>{
          'success': true,
          'message': 'تم حفظ إعدادات المياه المشتركة للعقار "${prop.name}".',
          'operation': isCreate ? 'create' : 'update',
          'propertyName': prop.name,
          'propertyId': prop.id,
          'serviceType': type,
          'serviceLabel': _serviceLabel(type),
          'applied': <String, dynamic>{
            'waterBillingMode': 'shared',
            'waterSharedMethod': 'fixed',
            'totalAmount': totalAmount,
            'nextDueDate': dueDate == null ? null : _fmtDate(dueDate),
            'remindBeforeDays': remindBeforeDays ?? 0,
          },
        });
      case 'electricity':
        final billingMode = _normalizeSharedBillingMode(
              args['billingMode'] ?? args['electricityBillingMode'],
            ) ??
            _periodicServiceElectricityBillingMode(existingCfg);
        if (billingMode.isEmpty) {
          return validationError(
            'يجب تحديد نمط فوترة الكهرباء: shared أو separate.',
            missingFields: <Map<String, String>>[
              issue('billingMode', 'نمط الفوترة', 'نمط الفوترة مطلوب'),
            ],
          );
        }
        if (billingMode == 'separate') {
          final meterNo = (args['meterNumber'] ??
                  args['electricityMeterNo'] ??
                  existingCfg['electricityMeterNo'] ??
                  '')
              .toString()
              .trim();
          if (meterNo.isNotEmpty && !RegExp(r'^\d{4,20}$').hasMatch(meterNo)) {
            return validationError('رقم عداد الكهرباء يجب أن يكون بين 4 و20 رقمًا.');
          }
          final nextCfg = <String, dynamic>{
            ...existingCfg,
            'serviceType': type,
            'electricityBillingMode': 'separate',
            'electricitySharedMethod': '',
            'payer': 'tenant',
            'electricityMeterNo': meterNo,
            'electricitySharePercent': null,
            'electricityPercentRequests': <Map<String, dynamic>>[],
            'nextDueDate': '',
            'dueDay': '',
            'recurrenceMonths': 0,
            'remindBeforeDays': 0,
          };
          svcBox.put(cfgKey, nextCfg);
          return jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'تم ضبط الكهرباء بنمط منفصل للعقار "${prop.name}".',
            'operation': isCreate ? 'create' : 'update',
            'propertyName': prop.name,
            'propertyId': prop.id,
            'serviceType': type,
            'serviceLabel': _serviceLabel(type),
            'applied': <String, dynamic>{
              'electricityBillingMode': 'separate',
              'payer': 'tenant',
              'meterNumber': meterNo,
            },
          });
        }

        final sharePercent =
            _periodicServiceNumber(args['sharePercent']) ??
                _periodicServiceNumber(existingCfg['electricitySharePercent']);
        if (sharePercent == null || sharePercent <= 0) {
          return validationError(
            'نسبة الكهرباء المشتركة يجب أن تكون أكبر من صفر.',
            missingFields: <Map<String, String>>[
              issue('sharePercent', 'النسبة', 'النسبة مطلوبة ويجب أن تكون أكبر من صفر'),
            ],
          );
        }
        final dueDate = _periodicServiceDate(
              args['nextDueDate'] ?? args['scheduledDate'],
            ) ??
            _periodicServiceDate(existingCfg['nextDueDate']);
        if (dueDate == null) {
          return validationError(
            'تاريخ الاستحقاق القادم مطلوب للكهرباء المشتركة.',
            missingFields: <Map<String, String>>[
              issue('nextDueDate', 'تاريخ الاستحقاق', 'تاريخ الاستحقاق مطلوب'),
            ],
          );
        }
        final remindBeforeDays = args.containsKey('remindBeforeDays')
            ? _periodicServiceInt(args['remindBeforeDays'])
            : _periodicServiceInt(existingCfg['remindBeforeDays']);
        if (args.containsKey('remindBeforeDays') &&
            (remindBeforeDays == null ||
                remindBeforeDays < 0 ||
                remindBeforeDays > 3)) {
          return validationError(
            'قيمة التذكير قبل الموعد يجب أن تكون بين 0 و3 أيام.',
          );
        }
        final nextCfg = <String, dynamic>{
          ...existingCfg,
          'serviceType': type,
          'electricityBillingMode': 'shared',
          'electricitySharedMethod': 'percent',
          'payer': 'owner',
          'electricitySharePercent': sharePercent,
          'nextDueDate': dueDate.toIso8601String(),
          'dueDay': dueDate.day,
          'recurrenceMonths': 1,
          'remindBeforeDays': remindBeforeDays ?? 0,
          'electricityMeterNo': '',
        };
        svcBox.put(cfgKey, nextCfg);
        return jsonEncode(<String, dynamic>{
          'success': true,
          'message': 'تم حفظ إعدادات الكهرباء المشتركة للعقار "${prop.name}".',
          'operation': isCreate ? 'create' : 'update',
          'propertyName': prop.name,
          'propertyId': prop.id,
          'serviceType': type,
          'serviceLabel': _serviceLabel(type),
          'applied': <String, dynamic>{
            'electricityBillingMode': 'shared',
            'sharePercent': sharePercent,
            'nextDueDate': _fmtDate(dueDate),
            'remindBeforeDays': remindBeforeDays ?? 0,
          },
        });
    }

    return validationError('نوع الخدمة غير مدعوم حاليًا.');
  }

  String _createPeriodicService(Map<String, dynamic> args) {
    return _mutatePeriodicService(args, isCreate: true);
  }

  Map<String, dynamic> _buildPropertyServicePayload(
    Property property,
    String type,
  ) {
    final cfg = _periodicServiceConfigForPropertyId(property.id, type);
    final requests = _periodicServiceRequestsFor(property.id, type);
    final configured = _periodicServiceConfigured(property, type, cfg);
    final openRequest = _firstWhereOrNull(
      requests,
      (item) =>
          item.status == MaintenanceStatus.open ||
          item.status == MaintenanceStatus.inProgress,
    );
    final lastCompletedRequest = _firstWhereOrNull(
      requests,
      (item) => item.status == MaintenanceStatus.completed,
    );
    final nextDue = _periodicServiceVisibleDueDate(property, type, cfg, requests);
    final parent = _periodicServiceParentProperty(property);
    final writeBoundary = _periodicServiceWriteBoundaryReason(
      property: property,
      type: type,
      existingConfig: cfg,
    );

    final previewRows = type == 'water'
        ? (_periodicServiceWaterSharedMethod(cfg) == 'percent'
            ? _periodicServicePreviewRows(cfg['waterPercentRequests'])
            : _periodicServicePreviewRows(cfg['waterInstallments']))
        : type == 'electricity'
            ? _periodicServicePreviewRows(cfg['electricityPercentRequests'])
            : const <Map<String, dynamic>>[];

    return <String, dynamic>{
      'serviceType': type,
      'label': _serviceLabel(type),
      'serviceLabel': _serviceLabel(type),
      'configured': configured,
      'statusLabel': _periodicServiceStatusLabel(property, type, cfg, requests),
      'providerName': (cfg['providerName'] ?? cfg['provider'] ?? '')
          .toString()
          .trim(),
      'management': <String, dynamic>{
        'payer': (cfg['payer'] ?? '').toString(),
        'sharedUnitsMode': (cfg['sharedUnitsMode'] ?? '').toString(),
        'internetBillingMode':
            type == 'internet' ? _periodicServiceInternetBillingMode(cfg) : null,
        'waterBillingMode':
            type == 'water' ? _periodicServiceWaterBillingMode(cfg) : null,
        'waterSharedMethod':
            type == 'water' ? _periodicServiceWaterSharedMethod(cfg) : null,
        'electricityBillingMode': type == 'electricity'
            ? _periodicServiceElectricityBillingMode(cfg)
            : null,
      },
      'schedule': <String, dynamic>{
        'startDate': _periodicServiceDate(cfg['startDate']) == null
            ? null
            : _fmtDate(_periodicServiceDate(cfg['startDate'])!),
        'nextDueDate': nextDue == null ? null : _fmtDate(nextDue),
        'recurrenceMonths': _periodicServiceInt(cfg['recurrenceMonths']) ?? 0,
        'remindBeforeDays':
            (_periodicServiceInt(cfg['remindBeforeDays']) ?? 0).clamp(0, 3),
      },
      'financial': <String, dynamic>{
        'defaultAmount': _periodicServiceNumber(
          cfg['defaultAmount'] ?? cfg['cost'],
        ),
        'totalWaterAmount': _periodicServiceNumber(cfg['totalWaterAmount']),
        'sharePercent': _periodicServiceNumber(cfg['sharePercent']),
        'electricitySharePercent':
            _periodicServiceNumber(cfg['electricitySharePercent']),
        'waterPerInstallment': _periodicServiceNumber(cfg['waterPerInstallment']),
      },
      'summary': <String, dynamic>{
        'totalRequests': requests.length,
        'openRequests': requests
            .where((item) =>
                item.status == MaintenanceStatus.open ||
                item.status == MaintenanceStatus.inProgress)
            .length,
        'completedRequests': requests
            .where((item) => item.status == MaintenanceStatus.completed)
            .length,
        'configHistoryRows': previewRows.length,
      },
      'currentOpenRequest': _serializePeriodicServiceRequest(openRequest),
      'lastCompletedRequest': _serializePeriodicServiceRequest(lastCompletedRequest),
      'writeBoundary': <String, dynamic>{
        'requiresScreen': writeBoundary != null,
        'reason': writeBoundary,
      },
      'configExtras': <String, dynamic>{
        'providerId': (cfg['providerId'] ?? '').toString(),
        'waterMeterNo': (cfg['waterMeterNo'] ?? '').toString(),
        'electricityMeterNo': (cfg['electricityMeterNo'] ?? '').toString(),
        'sharedPercentUnitShares':
            _periodicServicePreviewRows(cfg['sharedPercentUnitShares']),
        'waterInstallmentsPreview':
            _periodicServicePreviewRows(cfg['waterInstallments']),
        'waterPercentRequestsPreview':
            _periodicServicePreviewRows(cfg['waterPercentRequests']),
        'electricityPercentRequestsPreview':
            _periodicServicePreviewRows(cfg['electricityPercentRequests']),
        'parentBuilding': parent == null
            ? null
            : <String, dynamic>{
                'id': parent.id,
                'name': parent.name,
              },
        'parentManagedMode': parent == null
            ? null
            : (type == 'water' || type == 'electricity')
                ? (_periodicServiceConfigForPropertyId(parent.id, type)['sharedUnitsMode'] ??
                        '')
                    .toString()
                : null,
      },
    };
  }

  String _getPropertyServices(String propertyName) {
    final prop = _findProperty(propertyName);
    if (prop == null) return _err('لم يتم العثور على عقار بهذا الاسم');

    final services = _serviceTypes
        .map((type) => _buildPropertyServicePayload(prop, type))
        .toList(growable: false);

    return jsonEncode(<String, dynamic>{
      'screen': 'property_services',
      'title': 'خدمات العقار',
      'property': <String, dynamic>{
        'id': prop.id,
        'name': prop.name,
        'type': prop.type.toString().split('.').last,
        'rentalMode': prop.rentalMode.toString().split('.').last,
        'isArchived': prop.isArchived,
        'parentBuildingId': prop.parentBuildingId,
        'hasActiveContract': _hasActiveContractForPropertyId(prop.id),
        'isBuildingWithUnits': _periodicServiceIsBuildingWithUnits(prop),
        'isUnitUnderPerUnitBuilding':
            _periodicServiceIsUnitUnderPerUnitBuilding(prop),
      },
      'navigation': <String, dynamic>{
        'route': '/property/services',
        'canOpenDirectlyFromChat': false,
        'requiredArgs': const <String>['propertyId'],
      },
      'services': services,
    });
  }

  String _getPropertyServiceDetails(String propertyName, String serviceType) {
    final prop = _findProperty(propertyName);
    if (prop == null) return _err('لم يتم العثور على عقار بهذا الاسم');

    final type = _normalizeServiceType(serviceType);
    if (!_serviceTypes.contains(type)) {
      return _err('نوع خدمة غير معروف');
    }

    final payload = _buildPropertyServicePayload(prop, type);
    return jsonEncode(<String, dynamic>{
      'screen': 'property_services',
      'title': 'خدمات العقار',
      'property': <String, dynamic>{
        'id': prop.id,
        'name': prop.name,
      },
      ...payload,
    });
  }

  String _getPeriodicServiceHistory(String propertyName, String serviceType) {
    final prop = _findProperty(propertyName);
    if (prop == null) return _err('لم يتم العثور على عقار بهذا الاسم');

    final type = _normalizeServiceType(serviceType);
    if (!_serviceTypes.contains(type)) {
      return _err('نوع خدمة غير معروف');
    }

    final cfg = _periodicServiceConfigForPropertyId(prop.id, type);
    final requests = _periodicServiceRequestsFor(prop.id, type);
    final summary = _buildPropertyServicePayload(prop, type);

    List<Map<String, dynamic>> history;
    String historyKind;
    String? info;

    if (type == 'cleaning' ||
        type == 'elevator' ||
        (type == 'internet' &&
            _periodicServiceInternetBillingMode(cfg) == 'owner')) {
      historyKind = 'maintenance_requests';
      history = requests
          .map((request) => _serializePeriodicServiceRequest(request)!)
          .toList(growable: false);
    } else if (type == 'internet') {
      historyKind = 'none';
      history = const <Map<String, dynamic>>[];
      info = 'هذه الخدمة مضبوطة على المستأجر مباشرة ولا يوجد سجل طلبات دورية على المالك.';
    } else if (type == 'water') {
      final billingMode = _periodicServiceWaterBillingMode(cfg);
      final method = _periodicServiceWaterSharedMethod(cfg);
      if (billingMode == 'separate') {
        historyKind = 'none';
        history = const <Map<String, dynamic>>[];
        info = 'خدمة المياه هنا منفصلة على المستأجر ولا تملك سجلًا دوريًا مشتركًا.';
      } else if (method == 'percent') {
        historyKind = 'water_percent_requests';
        history = _periodicServicePreviewRows(
          cfg['waterPercentRequests'],
          limit: 50,
        );
      } else {
        historyKind = 'water_installments';
        history = _periodicServicePreviewRows(cfg['waterInstallments'], limit: 50);
        final hasArchive =
            (cfg['waterLastContractId'] ?? '').toString().trim().isNotEmpty;
        if (hasArchive) {
          info = 'يوجد أيضًا أرشيف سابق مرتبط بعقد منتهي أو غير نشط داخل إعدادات المياه.';
        }
      }
    } else {
      final billingMode = _periodicServiceElectricityBillingMode(cfg);
      if (billingMode == 'separate') {
        historyKind = 'none';
        history = const <Map<String, dynamic>>[];
        info =
            'خدمة الكهرباء هنا منفصلة على المستأجر ولا تملك سجلًا دوريًا مشتركًا.';
      } else {
        historyKind = 'electricity_percent_requests';
        history = _periodicServicePreviewRows(
          cfg['electricityPercentRequests'],
          limit: 50,
        );
      }
    }

    return jsonEncode(<String, dynamic>{
      'screen': 'property_services',
      'property': <String, dynamic>{'id': prop.id, 'name': prop.name},
      'serviceType': type,
      'serviceLabel': _serviceLabel(type),
      'historyKind': historyKind,
      'history': history,
      if (info != null) 'info': info,
      'summary': summary['summary'],
    });
  }

  String _updatePeriodicService(Map<String, dynamic> args) {
    return _mutatePeriodicService(args, isCreate: false);
  }

  // ================================================================
  //  مداخل الشاشات المرئية
  // ================================================================

  String _openTenantEntry(Map<String, dynamic> args) {
    if (!_canWrite) return _err(AiChatPermissions.denyMessage(userRole));

    return _navigationPayload(
      message: 'تم فتح شاشة إضافة عميل.',
      screen: 'tenants_new',
      route: '/tenants/new',
      extra: <String, dynamic>{
        if ((args['clientType'] ?? '').toString().trim().isNotEmpty)
          'clientType': (args['clientType'] ?? '').toString().trim(),
      },
    );
  }

  String _openPropertyEntry(Map<String, dynamic> args) {
    if (!_canWrite) return _err(AiChatPermissions.denyMessage(userRole));

    return _navigationPayload(
      message: 'تم فتح شاشة إضافة عقار.',
      screen: 'properties_new',
      route: '/properties/new',
      extra: <String, dynamic>{
        if ((args['type'] ?? '').toString().trim().isNotEmpty)
          'propertyType': (args['type'] ?? '').toString().trim(),
      },
    );
  }

  String _openContractEntry(Map<String, dynamic> args) {
    if (!_canWrite) return _err(AiChatPermissions.denyMessage(userRole));

    final propertyQuery = (args['propertyName'] ?? '').toString().trim();
    final tenantQuery = (args['tenantName'] ?? '').toString().trim();

    Property? property;
    Tenant? tenant;
    final unresolvedFields = <String>[];

    if (propertyQuery.isNotEmpty) {
      property = _findProperty(propertyQuery);
      if (property == null) {
        unresolvedFields.add('العقار');
      }
    }
    if (tenantQuery.isNotEmpty) {
      tenant = _findTenant(tenantQuery);
      if (tenant == null) {
        unresolvedFields.add('العميل');
      }
    }

    final navArgs = <String, dynamic>{
      if (property != null) 'prefillPropertyId': property.id,
      if (tenant != null) 'prefillTenantId': tenant.id,
    };
    final message = unresolvedFields.isEmpty
        ? 'تم فتح شاشة إضافة عقد.'
        : 'تم فتح شاشة إضافة عقد. أكمل اختيار ${unresolvedFields.join(' و')} من الشاشة لأن الاسم المكتوب لم يطابق سجلًا موجودًا.';

    return _navigationPayload(
      message: message,
      screen: 'contracts_new',
      route: '/contracts/new',
      arguments: navArgs,
      extra: <String, dynamic>{
        if (property != null) 'propertyName': property.name,
        if (tenant != null) 'tenantName': tenant.fullName,
      },
    );
  }

  String _openMaintenanceEntry(Map<String, dynamic> args) {
    if (!_canWrite) return _err(AiChatPermissions.denyMessage(userRole));

    final propertyQuery = (args['propertyName'] ?? '').toString().trim();
    Property? property;
    final unresolvedFields = <String>[];
    if (propertyQuery.isNotEmpty) {
      property = _findProperty(propertyQuery);
      if (property == null) {
        unresolvedFields.add('العقار');
      }
    }

    final providerQuery = (args['provider'] ?? '').toString().trim();
    final provider = providerQuery.isEmpty ? null : _findServiceProvider(providerQuery);
    if (providerQuery.isNotEmpty && provider == null) {
      unresolvedFields.add('مقدم الخدمة');
    }

    final navArgs = <String, dynamic>{
      if (property != null) 'prefillPropertyId': property.id,
      if ((args['title'] ?? '').toString().trim().isNotEmpty)
        'prefillTitle': (args['title'] ?? '').toString().trim(),
      if ((args['description'] ?? '').toString().trim().isNotEmpty)
        'prefillDescription': (args['description'] ?? '').toString().trim(),
      if ((args['scheduledDate'] ?? '').toString().trim().isNotEmpty)
        'prefillScheduleDate': (args['scheduledDate'] ?? '').toString().trim(),
      if ((args['executionDeadline'] ?? '').toString().trim().isNotEmpty)
        'prefillExecutionDeadline':
            (args['executionDeadline'] ?? '').toString().trim(),
      if (args['cost'] != null) 'prefillCost': args['cost'],
      if ((provider?.id ?? '').trim().isNotEmpty)
        'prefillProviderId': provider!.id,
      if (providerQuery.isNotEmpty) 'prefillProviderName': providerQuery,
    };
    final message = unresolvedFields.isEmpty
        ? 'تم فتح شاشة إضافة صيانة.'
        : 'تم فتح شاشة إضافة صيانة. أكمل اختيار ${unresolvedFields.join(' و')} من الشاشة لأن الاسم المكتوب لم يطابق سجلًا موجودًا.';

    return _navigationPayload(
      message: message,
      screen: 'maintenance_new',
      route: '/maintenance/new',
      arguments: navArgs,
      extra: <String, dynamic>{
        if (property != null) 'propertyName': property.name,
        if (provider != null) 'providerName': provider.fullName,
      },
    );
  }

  String _openContractInvoiceHistory(Map<String, dynamic> args) {
    final contract = _findContract((args['query'] ?? '').toString());
    if (contract == null) return _err('لم يتم العثور على عقد بهذا المرجع');

    return _navigationPayload(
      message: 'تم فتح سجل سندات العقد.',
      screen: 'invoices_history',
      route: '/invoices/history',
      arguments: <String, dynamic>{'contractId': contract.id},
      extra: <String, dynamic>{
        'contractId': contract.id,
        'contractSerialNo': contract.serialNo,
      },
    );
  }

  // ================================================================
  //  التنقل
  // ================================================================

  Future<String> _navigateToScreen(String screen) async {
    final rawTarget = AppArchitectureRegistry.findScreen(
      screen,
      isOfficeMode: _isOfficeMode,
    );
    if (rawTarget == null) return _err('شاشة غير معروفة: $screen');

    final target = AppArchitectureRegistry.findScreen(
      screen,
      isOfficeMode: _isOfficeMode,
      canWrite: _canWrite,
      canReadAll: _canReadAll,
    );
    if (target == null) {
      final title = (rawTarget['title'] ?? screen).toString();
      if (rawTarget['requiresOfficeWideRead'] == true && !_canReadAll) {
        return _err('هذه الشاشة موجودة لكن هذا الحساب لا يملك صلاحية الاطلاع عليها: $title');
      }
      if (rawTarget['chatWriteSupported'] == true &&
          rawTarget['chatReadSupported'] != true &&
          !_canWrite) {
        return _err('هذه الشاشة مخصصة للإدخال أو التعديل ولا يحق لهذا الحساب فتحها: $title');
      }
      return _err('هذه الشاشة موجودة في التطبيق لكنها غير متاحة لهذا الحساب: $title');
    }

    if (target['chatNavigationEnabled'] != true) {
      final requiredArgs =
          ((target['requiredNavigationArgs'] as List?) ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false);
      final reason = requiredArgs.isNotEmpty
          ? 'هذه الشاشة موجودة في التطبيق لكنها تحتاج بيانات فتح إضافية: ${requiredArgs.join(', ')}.'
          : 'هذه الشاشة موجودة في المرجع المعماري لكنها لا تُفتح مباشرة من الدردشة.';
      return jsonEncode(<String, dynamic>{
        'error': reason,
        'screen': target['key'],
        'title': target['title'],
        'entryKind': target['entryKind'],
        if ((target['route'] ?? '').toString().trim().isNotEmpty)
          'route': target['route'],
        if (requiredArgs.isNotEmpty) 'requiredNavigationArgs': requiredArgs,
      });
    }

    final route = (target['route'] ?? '').toString().trim();
    if (route.isEmpty) {
      return _err('لا يوجد مسار مباشر لهذه الشاشة داخل الدردشة.');
    }
    final didNavigate =
        onNavigate == null ? false : await onNavigate!.call(route);
    if (!didNavigate) {
      return _err('تعذر فتح شاشة ${target['title']} فعليًا من واجهة الدردشة الحالية.');
    }
    return jsonEncode(<String, dynamic>{
      'success': true,
      'message': 'تم فتح شاشة ${target['title']}',
      'screen': target['key'],
      'route': route,
    });
  }

  // ================================================================
  //  المكتب — Firestore
  // ================================================================

  CollectionReference<Map<String, dynamic>>? _officeClientsRef() {
    final uid = effectiveUid();
    if (uid.isEmpty || uid == 'guest') return null;
    return FirebaseFirestore.instance
        .collection('offices')
        .doc(uid)
        .collection('clients');
  }

  bool _isOfficeStaff(Map<String, dynamic> m) {
    final role = (m['role'] ?? '').toString();
    final entityType = (m['entityType'] ?? '').toString();
    final accountType = (m['accountType'] ?? '').toString();
    final targetRole = (m['targetRole'] ?? '').toString();
    final officePermission = (m['officePermission'] ?? '').toString();
    final permission = (m['permission'] ?? '').toString();
    return role == 'office_staff' ||
        entityType == 'office_user' ||
        accountType == 'office_staff' ||
        targetRole == 'office' ||
        officePermission == 'full' ||
        officePermission == 'view' ||
        permission == 'full' ||
        permission == 'view';
  }

  DateTime? _officeClientCreatedAt(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _normalizeOfficeClientSearch(Object? raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  Future<List<Map<String, dynamic>>> _loadMergedOfficeClients() async {
    final ref = _officeClientsRef();
    if (ref == null) return const <Map<String, dynamic>>[];

    final pendingCreates = OfflineSyncService.instance.listPendingOfficeCreates();
    final pendingEdits = OfflineSyncService.instance.mapPendingOfficeEdits();
    final pendingDeleteIds = OfflineSyncService.instance.setPendingOfficeDeletesIds();
    final pendingEmails = <String>{
      for (final item in pendingCreates)
        _normalizeOfficeClientSearch(item['email']),
    };

    final clients = <Map<String, dynamic>>[];
    for (final item in pendingCreates) {
      final tempId = (item['tempId'] ?? '').toString().trim();
      final localUid = (item['localUid'] ?? tempId).toString().trim();
      clients.add(<String, dynamic>{
        'name': (item['name'] ?? '').toString(),
        'email': (item['email'] ?? '').toString(),
        'phone': (item['phone'] ?? '').toString(),
        'notes': (item['notes'] ?? '').toString(),
        'clientUid': localUid,
        'docId': tempId,
        'tempId': tempId,
        'isLocal': true,
        'pendingSync': true,
        'blocked': false,
        'subscriptionEnabled': false,
        'subscriptionPrice': null,
        'createdAtIso': (item['createdAtIso'] ?? '').toString(),
      });
    }

    final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
    for (final doc in snap.docs) {
      final m = doc.data();
      if (_isOfficeStaff(m)) continue;

      final email = (m['email'] ?? '').toString();
      final clientUid = (m['clientUid'] ?? m['uid'] ?? doc.id).toString();
      if (pendingDeleteIds.contains(clientUid)) continue;
      if (pendingEmails.contains(_normalizeOfficeClientSearch(email))) continue;

      var name = (m['name'] ?? '').toString();
      var phone = (m['phone'] ?? '').toString();
      var notes = (m['notes'] ?? '').toString();
      final editPatch = pendingEdits[clientUid];
      if (editPatch != null) {
        if (editPatch.containsKey('name')) {
          name = (editPatch['name'] ?? '').toString();
        }
        if (editPatch.containsKey('phone')) {
          final patchedPhone = editPatch['phone'];
          phone = patchedPhone == null ? '' : patchedPhone.toString();
        }
        if (editPatch.containsKey('notes')) {
          final patchedNotes = editPatch['notes'];
          notes = patchedNotes == null ? '' : patchedNotes.toString();
        }
      }

      final blocked =
          (m['blocked'] == true) || (m['disabled'] == true) || (m['active'] == false);

      clients.add(<String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'notes': notes,
        'clientUid': clientUid,
        'docId': doc.id,
        'tempId': null,
        'isLocal': false,
        'pendingSync': editPatch != null,
        'blocked': blocked,
        'subscriptionEnabled': m['subscriptionEnabled'] == true,
        'subscriptionPrice': m['subscriptionPrice'],
        'createdAt': m['createdAt'],
      });
    }

    clients.sort((a, b) {
      final aa = _officeClientCreatedAt(a['createdAtIso'] ?? a['createdAt']) ??
          DateTime(2000);
      final bb = _officeClientCreatedAt(b['createdAtIso'] ?? b['createdAt']) ??
          DateTime(2000);
      return bb.compareTo(aa);
    });
    return clients;
  }

  Map<String, dynamic>? _findOfficeClientRecordInList(
    List<Map<String, dynamic>> clients,
    String query,
  ) {
    final normalized = _normalizeOfficeClientSearch(query);
    if (normalized.isEmpty) return null;

    final exact = clients.where((client) {
      final name = _normalizeOfficeClientSearch(client['name']);
      final email = _normalizeOfficeClientSearch(client['email']);
      final uid = _normalizeOfficeClientSearch(client['clientUid']);
      return name == normalized || email == normalized || uid == normalized;
    }).firstOrNull;
    if (exact != null) return exact;

    return clients.where((client) {
      final name = _normalizeOfficeClientSearch(client['name']);
      final email = _normalizeOfficeClientSearch(client['email']);
      final uid = _normalizeOfficeClientSearch(client['clientUid']);
      return name.contains(normalized) ||
          email.contains(normalized) ||
          uid.contains(normalized);
    }).firstOrNull;
  }

  Future<Map<String, dynamic>> _readOfficeDocMap(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
      return snap.data() ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> _loadOfficeClientAccessState(
    Map<String, dynamic> match,
  ) async {
    final clientUid = (match['clientUid'] ?? '').toString().trim();
    final email = (match['email'] ?? '').toString().trim().toLowerCase();
    final officeUid = effectiveUid().trim();

    final userData = clientUid.isEmpty
        ? const <String, dynamic>{}
        : await _readOfficeDocMap(
            FirebaseFirestore.instance.collection('users').doc(clientUid),
          );

    final officeMatches = <Map<String, dynamic>>[];
    if (officeUid.isNotEmpty && officeUid != 'guest' && clientUid.isNotEmpty) {
      officeMatches.add(
        await _readOfficeDocMap(
          FirebaseFirestore.instance
              .collection('offices')
              .doc(officeUid)
              .collection('clients')
              .doc(clientUid),
        ),
      );
    }
    if (officeUid.isNotEmpty &&
        officeUid != 'guest' &&
        email.isNotEmpty &&
        email != clientUid) {
      officeMatches.add(
        await _readOfficeDocMap(
          FirebaseFirestore.instance
              .collection('offices')
              .doc(officeUid)
              .collection('clients')
              .doc(email),
        ),
      );
    }

    final blockedFromUsers = OfficeClientGuard.isBlockedClientData(userData);
    final blockedFromOffice = officeMatches.any(OfficeClientGuard.isBlockedClientData);
    final blocked = blockedFromUsers || blockedFromOffice || match['blocked'] == true;

    return <String, dynamic>{
      'blocked': blocked,
      'allowAccess': !blocked,
      'userRecordFound': userData.isNotEmpty,
      'officeRecordFound': officeMatches.any((item) => item.isNotEmpty),
      'email': email,
      'clientUid': clientUid,
    };
  }

  Future<Map<String, dynamic>> _loadOfficeClientOfficeRecord(
    Map<String, dynamic> match,
  ) async {
    final clientUid = (match['clientUid'] ?? '').toString().trim();
    final email = (match['email'] ?? '').toString().trim().toLowerCase();
    final officeUid = effectiveUid().trim();
    if (officeUid.isEmpty || officeUid == 'guest') {
      return const <String, dynamic>{};
    }

    if (clientUid.isNotEmpty) {
      final byUid = await _readOfficeDocMap(
        FirebaseFirestore.instance
            .collection('offices')
            .doc(officeUid)
            .collection('clients')
            .doc(clientUid),
      );
      if (byUid.isNotEmpty) return byUid;
    }

    if (email.isNotEmpty && email != clientUid) {
      final byEmail = await _readOfficeDocMap(
        FirebaseFirestore.instance
            .collection('offices')
            .doc(officeUid)
            .collection('clients')
            .doc(email),
      );
      if (byEmail.isNotEmpty) return byEmail;
    }

    return const <String, dynamic>{};
  }

  DateTime? _officeParseYmdFlexible(String? text) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll('/', '-');
    final parts = normalized.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  DateTime _officeKsaDateOnly(DateTime dt) {
    final ksa = dt.toUtc().add(const Duration(hours: 3));
    return DateTime(ksa.year, ksa.month, ksa.day);
  }

  DateTime _officeAddOneMonthClamped(DateTime start) {
    final year = start.year + (start.month == 12 ? 1 : 0);
    final month = start.month == 12 ? 1 : start.month + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = start.day <= lastDay ? start.day : lastDay;
    return DateTime(
      year,
      month,
      day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  DateTime _officeSubscriptionEndFromStart(DateTime start) {
    return _officeAddOneMonthClamped(start);
  }

  DateTime? _officeClientDateOnlyValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return _officeKsaDateOnly(value.toDate());
      }
      if (value is DateTime) {
        return _officeKsaDateOnly(value);
      }
      if (value is String) {
        final parsedYmd = _officeParseYmdFlexible(value);
        if (parsedYmd != null) return parsedYmd;
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return _officeKsaDateOnly(parsed);
        }
      }
    }
    return null;
  }

  DateTime? _officeClientDateTimeValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return value.toDate().toUtc().add(const Duration(hours: 3));
      }
      if (value is DateTime) {
        return value.toUtc().add(const Duration(hours: 3));
      }
      if (value is String) {
        final parsedYmd = _officeParseYmdFlexible(value);
        if (parsedYmd != null) return parsedYmd;
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed.toUtc().add(const Duration(hours: 3));
        }
      }
    }
    return null;
  }

  double? _officeClientPriceValue(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  int _officeClientReminderDaysValue(dynamic value) {
    int reminder = 1;
    if (value is int) {
      reminder = value;
    } else if (value is num) {
      reminder = value.toInt();
    } else if (value is String) {
      reminder = int.tryParse(value.trim()) ?? 1;
    }
    return reminder.clamp(1, 3);
  }

  Map<String, dynamic> _buildOfficeClientSubscriptionState(
    Map<String, dynamic> match,
    Map<String, dynamic> officeRecord,
  ) {
    final createdAt =
        _officeClientCreatedAt(match['createdAtIso'] ?? match['createdAt']);
    final today = _officeKsaDateOnly(KsaTime.now());
    final fallbackStart = _officeKsaDateOnly(createdAt ?? KsaTime.now());
    final initialEnabled =
        officeRecord['subscriptionEnabled'] == true ||
        match['subscriptionEnabled'] == true;
    final initialStartDate = _officeClientDateOnlyValue(
      officeRecord,
      const <String>['subscriptionStartDate', 'subscriptionStartAt'],
    );
    final initialEndDate = _officeClientDateOnlyValue(
      officeRecord,
      const <String>['subscriptionEndDate', 'subscriptionEndAt'],
    );
    final initialPrice = _officeClientPriceValue(
      officeRecord.containsKey('subscriptionPrice')
          ? officeRecord['subscriptionPrice']
          : match['subscriptionPrice'],
    );
    final initialReminderDays = _officeClientReminderDaysValue(
      officeRecord.containsKey('subscriptionReminderDays')
          ? officeRecord['subscriptionReminderDays']
          : match['subscriptionReminderDays'],
    );
    final resolvedStart = initialStartDate ?? fallbackStart;
    final resolvedEnd =
        initialEndDate ?? _officeSubscriptionEndFromStart(resolvedStart);
    final hasActiveSubscription =
        initialEnabled && !today.isAfter(resolvedEnd);

    late final DateTime suggestedStartDate;
    if (initialEnabled) {
      if (hasActiveSubscription) {
        if (initialStartDate != null) {
          suggestedStartDate = _officeAddOneMonthClamped(initialStartDate);
        } else {
          suggestedStartDate = resolvedEnd.add(const Duration(days: 1));
        }
      } else {
        suggestedStartDate = today;
      }
    } else {
      suggestedStartDate = resolvedStart;
    }

    return <String, dynamic>{
      'enabled': initialEnabled,
      'subscriptionType':
          ((officeRecord['subscriptionType'] ?? '').toString().trim().isEmpty)
          ? 'monthly'
          : officeRecord['subscriptionType'],
      'price': initialPrice,
      'reminderDays': initialReminderDays,
      'startDate': initialStartDate,
      'endDate': initialEndDate,
      'resolvedStartDate': resolvedStart,
      'resolvedEndDate': resolvedEnd,
      'hasActiveSubscription': hasActiveSubscription,
      'renewMode': initialEnabled,
      'suggestedStartDate': suggestedStartDate,
      'suggestedEndDate': _officeSubscriptionEndFromStart(suggestedStartDate),
      'updatedAt': _officeClientDateTimeValue(
        officeRecord,
        const <String>['subscriptionUpdatedAt'],
      ),
    };
  }

  CollectionReference<Map<String, dynamic>>? _officeUsersRef() {
    return _officeClientsRef();
  }

  String _normalizeOfficeUserSearch(Object? raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  String _normalizeOfficeUserPermission(
    Object? raw, {
    String fallback = 'view',
  }) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'full' || value == 'view') return value;
    return fallback;
  }

  FirebaseFunctions _officeFunctions() {
    return FirebaseFunctions.instanceFor(region: 'us-central1');
  }

  Future<List<Map<String, dynamic>>> _loadOfficeUsers() async {
    final ref = _officeUsersRef();
    if (ref == null) return const <Map<String, dynamic>>[];

    final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
    final users = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final m = doc.data();
      if (!_isOfficeStaff(m)) continue;

      final uid = (m['uid'] ?? '').toString().trim();
      users.add(<String, dynamic>{
        'docId': doc.id,
        'uid': uid,
        'name': (m['name'] ?? '').toString(),
        'email': (m['email'] ?? '').toString().trim().toLowerCase(),
        'permission': _normalizeOfficeUserPermission(
          m['officePermission'] ?? m['permission'],
        ),
        'blocked':
            (m['blocked'] == true) || (m['disabled'] == true) || (m['active'] == false),
        'createdAt': m['createdAt'],
        'updatedAt': m['updatedAt'],
        'role': (m['role'] ?? '').toString(),
        'accountType': (m['accountType'] ?? '').toString(),
      });
    }

    users.sort((a, b) {
      final aa = _officeClientCreatedAt(a['createdAt'] ?? a['updatedAt']) ??
          DateTime(2000);
      final bb = _officeClientCreatedAt(b['createdAt'] ?? b['updatedAt']) ??
          DateTime(2000);
      return bb.compareTo(aa);
    });
    return users;
  }

  Map<String, dynamic>? _findOfficeUserRecordInList(
    List<Map<String, dynamic>> users,
    String query,
  ) {
    final normalized = _normalizeOfficeUserSearch(query);
    if (normalized.isEmpty) return null;

    final exact = users.where((user) {
      final name = _normalizeOfficeUserSearch(user['name']);
      final email = _normalizeOfficeUserSearch(user['email']);
      final uid = _normalizeOfficeUserSearch(user['uid']);
      final docId = _normalizeOfficeUserSearch(user['docId']);
      return name == normalized ||
          email == normalized ||
          uid == normalized ||
          docId == normalized;
    }).firstOrNull;
    if (exact != null) return exact;

    return users.where((user) {
      final name = _normalizeOfficeUserSearch(user['name']);
      final email = _normalizeOfficeUserSearch(user['email']);
      final uid = _normalizeOfficeUserSearch(user['uid']);
      final docId = _normalizeOfficeUserSearch(user['docId']);
      return name.contains(normalized) ||
          email.contains(normalized) ||
          uid.contains(normalized) ||
          docId.contains(normalized);
    }).firstOrNull;
  }

  String? _validateOfficeUserName(String name) {
    final value = name.trim();
    if (value.isEmpty) return 'الاسم مطلوب.';
    if (value.length > 30) {
      return 'الحد الأقصى للاسم 30 حرفًا.';
    }
    return null;
  }

  String? _validateOfficeUserEmail(String email) {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) return 'البريد الإلكتروني مطلوب.';
    if (!value.contains('@')) return 'يرجى إدخال بريد إلكتروني صحيح.';
    if (value.length > 30) {
      return 'الحد الأقصى للبريد الإلكتروني 30 حرفًا.';
    }
    return null;
  }

  String _officeUserValidationError(
    String message, {
    List<Map<String, String>> issues = const <Map<String, String>>[],
  }) {
    return jsonEncode(<String, dynamic>{
      'error': message,
      'suggestedScreen': 'office_users',
      if (issues.isNotEmpty) 'missingFields': issues,
    });
  }

  CollectionReference<Map<String, dynamic>>? _activityLogsRef() {
    final uid = effectiveUid().trim();
    if (uid.isEmpty || uid == 'guest') return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activity_logs');
  }

  Future<Map<String, dynamic>> _currentUserClaims() async {
    try {
      return (await FirebaseAuth.instance.currentUser?.getIdTokenResult(true))
              ?.claims ??
          const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<bool> _canViewAllActivityLog() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final workspaceUid = effectiveUid().trim();
    if (currentUid.isEmpty) return false;
    if (workspaceUid.isEmpty || workspaceUid == 'guest' || workspaceUid == currentUid) {
      return true;
    }

    final claims = await _currentUserClaims();
    final role = (claims['role'] ?? '').toString().trim().toLowerCase();
    final officePermission =
        (claims['officePermission'] ?? claims['permission'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (role == 'admin' ||
        role == 'owner' ||
        role == 'office' ||
        role == 'office_owner' ||
        officePermission == 'full') {
      return true;
    }

    final userDoc = await _readDocMap(
      FirebaseFirestore.instance.collection('users').doc(currentUid),
    );
    final docRole = (userDoc['role'] ?? '').toString().trim().toLowerCase();
    final docPermission =
        (userDoc['officePermission'] ?? userDoc['permission'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    return docRole == 'admin' ||
        docRole == 'owner' ||
        docRole == 'office' ||
        docRole == 'office_owner' ||
        docPermission == 'full';
  }

  bool _activityMatchesDate(
    ActivityLogEntry entry, {
    required String quickDate,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) {
    final dt = entry.occurredAt.toLocal();
    final now = DateTime.now();

    if (quickDate == 'today') {
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }
    if (quickDate == 'week') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      final startOnly = DateTime(start.year, start.month, start.day);
      final endOnly = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return !dt.isBefore(startOnly) && !dt.isAfter(endOnly);
    }
    if (quickDate == 'month') {
      return dt.year == now.year && dt.month == now.month;
    }

    if (fromDate != null) {
      final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
      if (dt.isBefore(from)) return false;
    }
    if (toDate != null) {
      final to = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
      if (dt.isAfter(to)) return false;
    }
    return true;
  }

  String _activityActionLabel(String raw) {
    switch (raw) {
      case 'create':
        return 'إضافة';
      case 'update':
        return 'تعديل';
      case 'delete':
        return 'حذف';
      case 'archive':
        return 'أرشفة';
      case 'unarchive':
        return 'فك الأرشفة';
      case 'terminate':
        return 'إنهاء';
      case 'status_change':
        return 'تغيير حالة';
      case 'login':
        return 'تسجيل دخول';
      case 'logout':
        return 'تسجيل خروج';
      case 'payment_add':
        return 'إضافة دفعة';
      case 'payment_update':
        return 'تعديل دفعة';
      case 'payment_delete':
        return 'حذف دفعة';
      case 'password_reset_link':
        return 'توليد رابط كلمة المرور';
      default:
        return raw;
    }
  }

  String _activityEntityLabel(String raw) {
    switch (raw) {
      case 'property':
        return 'عقار';
      case 'tenant':
        return 'عميل';
      case 'contract':
        return 'عقد';
      case 'invoice':
        return 'فاتورة';
      case 'maintenance':
        return 'صيانة';
      case 'office_user':
        return 'مستخدم مكتب';
      case 'office_client':
        return 'عميل مكتب';
      default:
        return raw;
    }
  }

  Future<String> _getActivityLog(Map<String, dynamic> args) async {
    final ref = _activityLogsRef();
    if (ref == null) return _err('لا يمكن الوصول إلى سجل النشاط من هذا الحساب.');

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return _err('لا يوجد مستخدم مسجل حاليًا.');

    final canViewAll = await _canViewAllActivityLog();
    final onlyMine = !canViewAll || args['onlyMine'] == true;
    final query = (args['query'] ?? '').toString().trim().toLowerCase();
    final actorQuery = (args['actorQuery'] ?? '').toString().trim().toLowerCase();
    final actionType = (args['actionType'] ?? '').toString().trim().toLowerCase();
    final entityType = (args['entityType'] ?? '').toString().trim().toLowerCase();
    final quickDate = (args['quickDate'] ?? 'all').toString().trim().toLowerCase();
    final fromDate = _parseDate((args['fromDate'] ?? '').toString().trim());
    final toDate = _parseDate((args['toDate'] ?? '').toString().trim());
    final limit = _toIntValue(args['limit'], 25).clamp(1, 200);

    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref
            .orderBy('occurredAt', descending: true)
            .limit(500)
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        snap = await ref
            .limit(500)
            .get(const GetOptions(source: Source.serverAndCache));
      }

      final entries = snap.docs
          .map((doc) => ActivityLogEntry.fromFirestore(doc.id, doc.data()))
          .toList(growable: false)
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      final filtered = entries.where((entry) {
        if (onlyMine && entry.actorUid != currentUid) return false;
        if (actionType.isNotEmpty && actionType != 'all') {
          if (entry.actionType.toLowerCase() != actionType) return false;
        }
        if (entityType.isNotEmpty && entityType != 'all') {
          if (entry.entityType.toLowerCase() != entityType) return false;
        }
        if (!_activityMatchesDate(
          entry,
          quickDate: quickDate,
          fromDate: fromDate,
          toDate: toDate,
        )) {
          return false;
        }
        if (actorQuery.isNotEmpty) {
          final hay = <String>[
            entry.actorUid,
            entry.actorName,
            entry.actorEmail,
          ].join(' ').toLowerCase();
          if (!hay.contains(actorQuery)) return false;
        }
        if (query.isEmpty) return true;
        final hay = <String>[
          entry.actorName,
          entry.actorEmail,
          _activityActionLabel(entry.actionType),
          _activityEntityLabel(entry.entityType),
          entry.entityName,
          entry.entityId,
          entry.description,
        ].join(' ').toLowerCase();
        return hay.contains(query);
      }).take(limit).map((entry) {
        return <String, dynamic>{
          'id': entry.id,
          'occurredAt': entry.occurredAt.toIso8601String(),
          'actorUid': entry.actorUid,
          'actorName': entry.actorName,
          'actorEmail': entry.actorEmail,
          'actorRole': entry.actorRole,
          'actionType': entry.actionType,
          'actionLabel': _activityActionLabel(entry.actionType),
          'entityType': entry.entityType,
          'entityLabel': _activityEntityLabel(entry.entityType),
          'entityId': entry.entityId,
          'entityName': entry.entityName,
          'description': entry.description,
          'changedFields': entry.changedFields,
          'metadata': entry.metadata,
        };
      }).toList(growable: false);

      if (filtered.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'info': 'لا يوجد نشاط مطابق للفلاتر الحالية.',
          'onlyMine': onlyMine,
          'canViewAll': canViewAll,
        });
      }

      return jsonEncode(<String, dynamic>{
        'entries': filtered,
        'total': filtered.length,
        'workspaceUid': effectiveUid().trim(),
        'canViewAll': canViewAll,
        'onlyMine': onlyMine,
      });
    } catch (e) {
      return _err('تعذر جلب سجل النشاط: $e');
    }
  }

  Future<String> _getOfficeUsersList() async {
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    try {
      final users = await _loadOfficeUsers();
      return jsonEncode(<String, dynamic>{
        'users': users
            .map((user) => <String, dynamic>{
                  'name': user['name'] ?? '',
                  'email': user['email'] ?? '',
                  'uid': user['uid'] ?? '',
                  'permission': user['permission'] ?? 'view',
                  'blocked': user['blocked'] == true,
                  'createdAt': _officeClientCreatedAt(user['createdAt'])
                      ?.toIso8601String(),
                  'updatedAt': _officeClientCreatedAt(user['updatedAt'])
                      ?.toIso8601String(),
                })
            .toList(growable: false),
        'total': users.length,
      });
    } catch (e) {
      return _err('تعذر جلب قائمة مستخدمي المكتب: $e');
    }
  }

  Future<String> _getOfficeUserDetails(Map<String, dynamic> args) async {
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب');

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      final email = (match['email'] ?? '').toString().trim();
      return jsonEncode(<String, dynamic>{
        'name': match['name'] ?? '',
        'email': email,
        'uid': uid,
        'docId': match['docId'] ?? '',
        'permission': match['permission'] ?? 'view',
        'blocked': match['blocked'] == true,
        'canManageAccess': uid.isNotEmpty,
        'canGenerateResetLink': uid.isNotEmpty && email.isNotEmpty,
        'createdAt': _officeClientCreatedAt(match['createdAt'])?.toIso8601String(),
        'updatedAt': _officeClientCreatedAt(match['updatedAt'])?.toIso8601String(),
      });
    } catch (e) {
      return _err('تعذر جلب تفاصيل مستخدم المكتب: $e');
    }
  }

  Future<String> _addOfficeUser(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    final ref = _officeUsersRef();
    if (ref == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final name = (args['name'] ?? '').toString().trim();
    final email = (args['email'] ?? '').toString().trim().toLowerCase();
    final permission = _normalizeOfficeUserPermission(args['permission']);

    final issues = <Map<String, String>>[];
    final nameError = _validateOfficeUserName(name);
    if (nameError != null) {
      issues.add(<String, String>{
        'field': 'name',
        'label': 'الاسم',
        'message': nameError,
      });
    }
    final emailError = _validateOfficeUserEmail(email);
    if (emailError != null) {
      issues.add(<String, String>{
        'field': 'email',
        'label': 'البريد الإلكتروني',
        'message': emailError,
      });
    }
    if (issues.isNotEmpty) {
      return _officeUserValidationError(
        issues.first['message'] ?? 'بيانات غير صالحة.',
        issues: issues,
      );
    }

    try {
      final limitDecision = await PackageLimitService.canAddOfficeUser();
      if (!limitDecision.allowed) {
        return _err(
          limitDecision.message ??
              'لا يمكن إضافة مستخدم مكتب جديد، لقد وصلت إلى الحد الأقصى المسموح.',
        );
      }

      final duplicate = await ref.where('email', isEqualTo: email).limit(1).get();
      if (duplicate.docs.isNotEmpty) {
        return _err('يوجد مستخدم مسجل بنفس البريد الإلكتروني: $email');
      }

      final officeUid = effectiveUid().trim();
      if (officeUid.isEmpty || officeUid == 'guest') {
        return _err('تعذر تحديد مساحة المكتب الحالية.');
      }

      final result = await _officeFunctions().httpsCallable('officeCreateClient').call(
        <String, dynamic>{
          'name': name,
          'email': email,
          'phone': '',
          'notes': '',
          'officeId': officeUid,
          'office_id': officeUid,
          'accountType': 'office_staff',
          'targetRole': 'office',
          'officePermission': permission,
        },
      );

      String? createdUid;
      final data = result.data;
      if (data is Map) {
        final uid = data['uid']?.toString().trim();
        if (uid != null && uid.isNotEmpty) createdUid = uid;
      }

      if (createdUid == null || createdUid.isEmpty) {
        await ref.doc(email).set(<String, dynamic>{
          'uid': '',
          'name': name,
          'email': email,
          'role': 'office_staff',
          'entityType': 'office_user',
          'targetRole': 'office',
          'permission': permission,
          'officePermission': permission,
          'officeId': officeUid,
          'office_id': officeUid,
          'accountType': 'office_staff',
          'blocked': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تمت إضافة مستخدم المكتب "$name" بنجاح.',
        'name': name,
        'email': email,
        'uid': createdUid ?? '',
        'permission': permission,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن إضافة مستخدم المكتب الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر إضافة مستخدم المكتب.');
    } catch (e) {
      return _err('تعذر إضافة مستخدم المكتب: $e');
    }
  }

  Future<String> _editOfficeUser(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب المراد تعديله');

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      if (uid.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا المستخدم لا يملك uid جاهزًا بعد، لذلك لا يمكن تعديل بياناته من الدردشة الآن.',
          'code': 'office_user_login_not_ready',
          'userName': match['name'],
        });
      }

      final currentName = (match['name'] ?? '').toString().trim();
      final nextName = args.containsKey('name')
          ? (args['name'] ?? '').toString().trim()
          : currentName;
      final nameError = _validateOfficeUserName(nextName);
      if (nameError != null) {
        return _officeUserValidationError(
          nameError,
          issues: <Map<String, String>>[
            <String, String>{
              'field': 'name',
              'label': 'الاسم',
              'message': nameError,
            },
          ],
        );
      }

      final currentPermission =
          _normalizeOfficeUserPermission(match['permission'], fallback: 'view');
      final nextPermission = args.containsKey('permission')
          ? _normalizeOfficeUserPermission(
              args['permission'],
              fallback: currentPermission,
            )
          : currentPermission;

      if (nextName == currentName && nextPermission == currentPermission) {
        return _err('لم يتم تقديم أي تعديل جديد على مستخدم المكتب.');
      }

      if (nextName != currentName) {
        await _officeFunctions().httpsCallable('updateUserProfile').call(
          <String, dynamic>{
            'uid': uid,
            'name': nextName,
          },
        );
      }

      if (nextPermission != currentPermission) {
        await _officeFunctions().httpsCallable('officeUpdateUserPermission').call(
          <String, dynamic>{
            'uid': uid,
            'permission': nextPermission,
          },
        );
      }

      await _officeUsersRef()!.doc((match['docId'] ?? '').toString()).set(
        <String, dynamic>{
          'name': nextName,
          'permission': nextPermission,
          'officePermission': nextPermission,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم تعديل مستخدم المكتب "${match['name'] ?? ''}" بنجاح.',
        'uid': uid,
        'name': nextName,
        'permission': nextPermission,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن تعديل مستخدم المكتب الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر تعديل مستخدم المكتب.');
    } catch (e) {
      return _err('تعذر تعديل مستخدم المكتب: $e');
    }
  }

  Future<String> _setOfficeUserPermission(Map<String, dynamic> args) async {
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب');
    final permission = _normalizeOfficeUserPermission(args['permission'], fallback: '');
    if (permission.isEmpty) {
      return _officeUserValidationError(
        'يجب تحديد الصلاحية بالقيمة full أو view.',
        issues: const <Map<String, String>>[
          <String, String>{
            'field': 'permission',
            'label': 'الصلاحية',
            'message': 'يجب تحديد الصلاحية بالقيمة full أو view.',
          },
        ],
      );
    }

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      if (uid.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا المستخدم لا يملك uid جاهزًا بعد، لذلك لا يمكن تعديل صلاحيته من الدردشة الآن.',
          'code': 'office_user_login_not_ready',
          'userName': match['name'],
        });
      }

      await _officeFunctions().httpsCallable('officeUpdateUserPermission').call(
        <String, dynamic>{
          'uid': uid,
          'permission': permission,
        },
      );
      await _officeUsersRef()!.doc((match['docId'] ?? '').toString()).set(
        <String, dynamic>{
          'permission': permission,
          'officePermission': permission,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم تحديث صلاحية مستخدم المكتب "${match['name'] ?? ''}".',
        'uid': uid,
        'permission': permission,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن تعديل الصلاحية الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر تعديل صلاحية مستخدم المكتب.');
    } catch (e) {
      return _err('تعذر تعديل صلاحية مستخدم المكتب: $e');
    }
  }

  Future<String> _setOfficeUserAccess(Map<String, dynamic> args) async {
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب');
    if (args['allowAccess'] is! bool) {
      return _officeUserValidationError(
        'يجب تحديد allowAccess بالقيمة true أو false.',
        issues: const <Map<String, String>>[
          <String, String>{
            'field': 'allowAccess',
            'label': 'حالة الدخول',
            'message': 'يجب تحديد allowAccess بالقيمة true أو false.',
          },
        ],
      );
    }

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      if (uid.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا المستخدم لا يملك uid جاهزًا بعد، لذلك لا يمكن إدارة دخوله من الدردشة الآن.',
          'code': 'office_user_login_not_ready',
          'userName': match['name'],
        });
      }

      final blocked = !(args['allowAccess'] == true);
      await _officeFunctions().httpsCallable('updateUserStatus').call(
        <String, dynamic>{
          'uid': uid,
          'blocked': blocked,
        },
      );
      await _officeUsersRef()!.doc((match['docId'] ?? '').toString()).set(
        <String, dynamic>{
          'blocked': blocked,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': blocked
            ? 'تم إيقاف دخول مستخدم المكتب "${match['name'] ?? ''}".'
            : 'تم السماح بدخول مستخدم المكتب "${match['name'] ?? ''}".',
        'uid': uid,
        'blocked': blocked,
        'allowAccess': !blocked,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن تعديل حالة الدخول الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر تعديل حالة دخول مستخدم المكتب.');
    } catch (e) {
      return _err('تعذر تعديل حالة دخول مستخدم المكتب: $e');
    }
  }

  Future<String> _deleteOfficeUser(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب المراد حذفه');

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      if (uid.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا المستخدم لا يملك uid جاهزًا بعد، لذلك لا يمكن حذفه من الدردشة الآن.',
          'code': 'office_user_login_not_ready',
          'userName': match['name'],
        });
      }

      await _officeFunctions().httpsCallable('officeDeleteClient').call(
        <String, dynamic>{'clientUid': uid},
      );
      await _officeUsersRef()!.doc((match['docId'] ?? '').toString()).delete();

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم حذف مستخدم المكتب "${match['name'] ?? ''}".',
        'uid': uid,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن حذف مستخدم المكتب الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر حذف مستخدم المكتب.');
    } catch (e) {
      return _err('تعذر حذف مستخدم المكتب: $e');
    }
  }

  Future<String> _generateOfficeUserResetLink(Map<String, dynamic> args) async {
    if (_officeUsersRef() == null) return _err('لا يمكن الوصول لبيانات مستخدمي المكتب');

    final query = (args['query'] ?? args['userName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد مستخدم المكتب');

    try {
      final users = await _loadOfficeUsers();
      final match = _findOfficeUserRecordInList(users, query);
      if (match == null) {
        return _err('لم يتم العثور على مستخدم مكتب باسم "$query"');
      }

      final uid = (match['uid'] ?? '').toString().trim();
      final email = (match['email'] ?? '').toString().trim();
      if (uid.isEmpty || email.isEmpty) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا المستخدم لا يملك بيانات دخول مكتملة لتوليد رابط إعادة التعيين.',
          'code': 'office_user_login_not_ready',
          'userName': match['name'],
        });
      }

      final res = await _officeFunctions()
          .httpsCallable('generatePasswordResetLink')
          .call(<String, dynamic>{'email': email});
      final link =
          (res.data is Map ? (res.data as Map)['resetLink'] : null)?.toString().trim() ?? '';
      if (link.isEmpty) {
        return _err('تعذر توليد رابط إعادة تعيين كلمة المرور.');
      }

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message':
            'تم توليد رابط إعادة تعيين كلمة المرور لمستخدم المكتب "${match['name'] ?? ''}".',
        'uid': uid,
        'email': email,
        'resetLink': link,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن توليد رابط إعادة التعيين الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر توليد رابط إعادة التعيين.');
    } catch (e) {
      return _err('تعذر توليد رابط إعادة التعيين: $e');
    }
  }

  Future<String> _getOfficeClientsList() async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    try {
      final clients = await _loadMergedOfficeClients();
      return jsonEncode({
        'clients': clients
            .map((client) => <String, dynamic>{
                  'name': client['name'] ?? '',
                  'email': client['email'] ?? '',
                  'phone': client['phone'] ?? '',
                  'clientUid': client['clientUid'] ?? '',
                  'blocked': client['blocked'] == true,
                  'subscriptionEnabled': client['subscriptionEnabled'] == true,
                  'isLocal': client['isLocal'] == true,
                  'pendingSync': client['pendingSync'] == true,
                })
            .toList(growable: false),
        'total': clients.length,
      });
    } catch (e) {
      return _err('تعذر جلب قائمة العملاء: $e');
    }
  }

  Future<String> _getOfficeClientDetails(String clientName) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = clientName.trim().toLowerCase();
    if (query.isEmpty) return _err('يرجى تحديد اسم العميل');

    try {
      final clients = await _loadMergedOfficeClients();
      final found = _findOfficeClientRecordInList(clients, clientName);
      if (found == null) return _err('لم يتم العثور على عميل باسم "$clientName"');

      final createdAt =
          _officeClientCreatedAt(found['createdAtIso'] ?? found['createdAt']);
      final clientUid = (found['clientUid'] ?? '').toString().trim();
      final workspaceSummary =
          clientUid.isEmpty ? null : await _loadOfficeClientWorkspaceSummary(clientUid);

      return jsonEncode({
        'name': found['name'] ?? '',
        'email': found['email'] ?? '',
        'phone': found['phone'] ?? '',
        'notes': found['notes'] ?? '',
        'clientUid': clientUid,
        'blocked': found['blocked'] == true,
        'subscriptionEnabled': found['subscriptionEnabled'] == true,
        'subscriptionPrice': found['subscriptionPrice'],
        'createdAt': createdAt != null ? _fmtDate(createdAt) : null,
        'isLocal': found['isLocal'] == true,
        'pendingSync': found['pendingSync'] == true,
        'workspaceDataAvailable': workspaceSummary != null,
        'workspaceDataMessage': workspaceSummary == null
            ? 'لا توجد حاليًا بيانات تشغيلية متاحة لهذا العميل داخل مساحة العمل المحلية.'
            : 'تم العثور على بيانات تشغيلية لهذا العميل ويمكن عرض عقاراته وعقوده وملخصه التشغيلي.',
        if (workspaceSummary != null) 'workspaceSummary': workspaceSummary,
        if (workspaceSummary != null)
          'propertiesPreview': workspaceSummary['propertiesPreview'],
        if (workspaceSummary != null)
          'contractsPreview': workspaceSummary['contractsPreview'],
      });
    } catch (e) {
      return _err('تعذر جلب تفاصيل العميل: $e');
    }
  }

  Future<String> _getOfficeClientAccess(Map<String, dynamic> args) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل');

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }

      if (match['isLocal'] == true) {
        return jsonEncode(<String, dynamic>{
          'clientName': match['name'] ?? '',
          'clientUid': match['clientUid'] ?? '',
          'email': match['email'] ?? '',
          'pendingSync': true,
          'isLocal': true,
          'hasLoginAccount': false,
          'canManageAccess': false,
          'canGenerateResetLink': false,
          'message':
              'هذا العميل لا يزال محليًا بانتظار المزامنة، لذلك لا توجد له إدارة دخول أو رابط إعادة تعيين بعد.',
        });
      }

      final access = await _loadOfficeClientAccessState(match);
      final hasLoginAccount = access['userRecordFound'] == true;
      return jsonEncode(<String, dynamic>{
        'clientName': match['name'] ?? '',
        'clientUid': match['clientUid'] ?? '',
        'email': match['email'] ?? '',
        'blocked': access['blocked'] == true,
        'allowAccess': access['allowAccess'] == true,
        'hasLoginAccount': hasLoginAccount,
        'officeRecordFound': access['officeRecordFound'] == true,
        'canManageAccess': hasLoginAccount,
        'canGenerateResetLink':
            hasLoginAccount && (match['email'] ?? '').toString().trim().isNotEmpty,
        'pendingSync': false,
        'isLocal': false,
      });
    } catch (e) {
      return _err('تعذر جلب حالة وصول العميل: $e');
    }
  }

  Future<String> _getOfficeClientSubscription(Map<String, dynamic> args) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل');

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }

      if (match['isLocal'] == true) {
        return jsonEncode(<String, dynamic>{
          'clientName': match['name'] ?? '',
          'clientUid': match['clientUid'] ?? '',
          'email': match['email'] ?? '',
          'pendingSync': true,
          'isLocal': true,
          'subscriptionEnabled': false,
          'canManageSubscription': false,
          'message':
              'هذا العميل لا يزال محليًا بانتظار المزامنة، لذلك لا يمكن قراءة أو تفعيل الاشتراك له من الدردشة بعد.',
        });
      }

      final officeRecord = await _loadOfficeClientOfficeRecord(match);
      final state = _buildOfficeClientSubscriptionState(match, officeRecord);
      final startDate = state['startDate'] as DateTime?;
      final endDate = state['endDate'] as DateTime?;
      final suggestedStartDate = state['suggestedStartDate'] as DateTime;
      final suggestedEndDate = state['suggestedEndDate'] as DateTime;
      final updatedAt = state['updatedAt'] as DateTime?;
      final renewMode = state['renewMode'] == true;

      return jsonEncode(<String, dynamic>{
        'clientName': match['name'] ?? '',
        'clientUid': match['clientUid'] ?? '',
        'email': match['email'] ?? '',
        'subscriptionEnabled': state['enabled'] == true,
        'subscriptionType': state['subscriptionType'],
        'price': state['price'],
        'reminderDays': state['reminderDays'],
        'startDate': startDate == null ? null : _fmtDate(startDate),
        'endDate': endDate == null ? null : _fmtDate(endDate),
        'resolvedStartDate': _fmtDate(state['resolvedStartDate'] as DateTime),
        'resolvedEndDate': _fmtDate(state['resolvedEndDate'] as DateTime),
        'suggestedStartDate': _fmtDate(suggestedStartDate),
        'suggestedEndDate': _fmtDate(suggestedEndDate),
        'hasActiveSubscription': state['hasActiveSubscription'] == true,
        'renewMode': renewMode,
        'startDateLockedBySystem': renewMode,
        'canManageSubscription': true,
        'pendingSync': false,
        'isLocal': false,
        'updatedAt': updatedAt == null ? null : updatedAt.toIso8601String(),
        if (renewMode)
          'message':
              'يوجد اشتراك سابق لهذا العميل، لذلك يتم تحديد بداية التجديد تلقائيًا حسب منطق شاشة المكتب.',
      });
    } catch (e) {
      return _err('تعذر جلب حالة اشتراك العميل: $e');
    }
  }

  Future<String> _getOfficeSummary() async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    try {
      int totalClients = 0;
      int blocked = 0;
      int active = 0;
      int withSubscription = 0;

      final clients = await _loadMergedOfficeClients();
      for (final m in clients) {
        totalClients++;
        final isBlocked = m['blocked'] == true;
        if (isBlocked) {
          blocked++;
        } else {
          active++;
        }
        if (m['subscriptionEnabled'] == true) withSubscription++;
      }

      return jsonEncode({
        'totalClients': totalClients,
        'active': active,
        'blocked': blocked,
        'withSubscription': withSubscription,
      });
    } catch (e) {
      return _err('تعذر جلب ملخص المكتب: $e');
    }
  }

  Future<String> _addOfficeClient(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    final ref = _officeClientsRef();
    if (ref == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final validation = AiChatDomainRulesService.validateOfficeClient(
      name: args['name'],
      email: args['email'],
      phone: args['phone'],
      notes: args['notes'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.officeClientRequiredFields(),
        nextStep: 'ask_for_missing_office_client_fields',
        extra: const <String, dynamic>{
          'code': 'office_client_validation_failed',
          'suggestedScreen': 'office_clients',
        },
      );
    }

    final draft = validation.draft!;

    try {
      final limitDecision = await PackageLimitService.canAddOfficeClient();
      if (!limitDecision.allowed) {
        return _err(
          limitDecision.message ??
              'لا يمكن إضافة عميل جديد، لقد وصلت إلى الحد الأقصى المسموح.',
        );
      }

      final pendingCreates = OfflineSyncService.instance.listPendingOfficeCreates();
      final duplicatePending = pendingCreates.any(
        (item) => _normalizeOfficeClientSearch(item['email']) == draft.email,
      );
      if (duplicatePending) {
        return _err('يوجد عميل معلّق بنفس البريد الإلكتروني: ${draft.email}');
      }

      final existing = await ref
          .where('email', isEqualTo: draft.email)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return _err(
          'يوجد عميل مسجل بنفس البريد الإلكتروني: ${draft.email}',
        );
      }

      await OfflineSyncService.instance.enqueueCreateOfficeClient(
        name: draft.name,
        email: draft.email,
        phone: draft.phone,
        notes: draft.notes,
      );

      return _ok('تمت إضافة العميل "${draft.name}" (${draft.email}) بنجاح.');
    } catch (e) {
      return _err('تعذر إضافة العميل: $e');
    }
  }

  Future<String> _editOfficeClient(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل المراد تعديله');

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }

      final currentEmail = (match['email'] ?? '').toString().trim().toLowerCase();
      final requestedEmail = (args['email'] ?? '').toString().trim().toLowerCase();
      if (requestedEmail.isNotEmpty && requestedEmail != currentEmail) {
        return _err(
          'تعديل البريد الإلكتروني لعميل المكتب غير مدعوم من الدردشة حالياً. غيّر الاسم أو الجوال أو الملاحظات فقط.',
        );
      }

      final validation = AiChatDomainRulesService.validateOfficeClient(
        name: args['name'] ?? match['name'],
        email: currentEmail,
        phone: args.containsKey('phone') ? args['phone'] : match['phone'],
        notes: args.containsKey('notes') ? args['notes'] : match['notes'],
      );
      if (!validation.isValid) {
        return _domainValidationError(
          validation,
          requiredFields: AiChatDomainRulesService.officeClientRequiredFields(),
          nextStep: 'correct_office_client_fields_then_retry',
          extra: <String, dynamic>{
            'code': 'office_client_edit_validation_failed',
            'suggestedScreen': 'office_clients',
            'clientUid': match['clientUid'],
            'clientName': match['name'],
          },
        );
      }

      final draft = validation.draft!;
      final currentName = (match['name'] ?? '').toString().trim();
      final currentPhone = (match['phone'] ?? '').toString().trim();
      final currentNotes = (match['notes'] ?? '').toString().trim();
      if (draft.name == currentName &&
          draft.phone == currentPhone &&
          draft.notes == currentNotes) {
        return _err('لم يتم تقديم أي تعديل جديد على العميل.');
      }

      await OfflineSyncService.instance.enqueueEditOfficeClient(
        clientUid: (match['clientUid'] ?? '').toString(),
        name: draft.name,
        phone: args.containsKey('phone')
            ? (draft.phone.isEmpty ? null : draft.phone)
            : null,
        notes: draft.notes,
      );

      return _ok('تم تعديل العميل "${draft.name}" بنجاح.');
    } catch (e) {
      return _err('تعذر تعديل العميل: $e');
    }
  }

  Future<String> _deleteOfficeClient(Map<String, dynamic> args) async {
    final g = _syncGuard();
    if (g.isNotEmpty) return g;

    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل المراد حذفه');

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }

      if (match['isLocal'] == true) {
        final tempId = (match['tempId'] ?? '').toString().trim();
        if (tempId.isEmpty) {
          return _err('تعذر تحديد سجل العميل المحلي لحذفه.');
        }
        await OfflineSyncService.instance.removePendingOfficeCreateByTempId(
          tempId,
        );
      } else {
        await OfflineSyncService.instance.enqueueDeleteOfficeClient(
          (match['clientUid'] ?? '').toString(),
        );
      }

      return _ok('تم حذف العميل "${match['name'] ?? ''}" بنجاح.');
    } catch (e) {
      return _err('تعذر حذف العميل: $e');
    }
  }

  Future<String> _setOfficeClientAccess(Map<String, dynamic> args) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل');

    final validation = AiChatDomainRulesService.validateOfficeClientAccess(
      allowAccess: args['allowAccess'],
      blocked: args['blocked'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields: AiChatDomainRulesService.officeClientAccessRequiredFields(),
        nextStep: 'specify_office_client_access_state_then_retry',
        extra: const <String, dynamic>{
          'code': 'office_client_access_validation_failed',
          'suggestedScreen': 'office_clients',
        },
      );
    }

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }
      if (match['isLocal'] == true) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا العميل لا يزال محليًا بانتظار المزامنة، لذلك لا يمكن إدارة دخوله قبل حفظه فعليًا.',
          'code': 'office_client_pending_sync',
          'clientName': match['name'],
          'pendingSync': true,
        });
      }

      final draft = validation.draft!;
      final access = await _loadOfficeClientAccessState(match);
      if (access['userRecordFound'] != true) {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يوجد حساب دخول فعلي مرتبط بهذا العميل بعد، لذلك لا يمكن تعديل حالة الدخول من الدردشة الآن.',
          'code': 'office_client_login_not_ready',
          'clientName': match['name'],
        });
      }
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('updateUserStatus');
      await callable.call(<String, dynamic>{
        'uid': (match['clientUid'] ?? '').toString(),
        'blocked': draft.blocked,
      });

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': draft.blocked
            ? 'تم إيقاف دخول العميل "${match['name'] ?? ''}".'
            : 'تم السماح بدخول العميل "${match['name'] ?? ''}".',
        'clientName': match['name'] ?? '',
        'clientUid': match['clientUid'] ?? '',
        'blocked': draft.blocked,
        'allowAccess': draft.allowAccess,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن تنفيذ تعديل الدخول الآن لأن العملية مرتبطة بالسيرفر مباشرة وتحتاج اتصال إنترنت فعلي.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر تعديل حالة دخول العميل.');
    } catch (e) {
      return _err('تعذر تعديل حالة دخول العميل: $e');
    }
  }

  Future<String> _setOfficeClientSubscription(Map<String, dynamic> args) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل');

    final validation = AiChatDomainRulesService.validateOfficeClientSubscription(
      price: args['price'],
      reminderDays: args['reminderDays'],
      startDate: args['startDate'],
    );
    if (!validation.isValid) {
      return _domainValidationError(
        validation,
        requiredFields:
            AiChatDomainRulesService.officeClientSubscriptionRequiredFields(),
        nextStep: 'specify_office_client_subscription_fields_then_retry',
        extra: const <String, dynamic>{
          'code': 'office_client_subscription_validation_failed',
          'suggestedScreen': 'office_clients',
        },
      );
    }

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }
      if (match['isLocal'] == true) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا العميل لا يزال محليًا بانتظار المزامنة، لذلك لا يمكن تفعيل الاشتراك له قبل حفظه فعليًا.',
          'code': 'office_client_pending_sync',
          'clientName': match['name'],
          'pendingSync': true,
        });
      }

      final officeRecord = await _loadOfficeClientOfficeRecord(match);
      final state = _buildOfficeClientSubscriptionState(match, officeRecord);
      final draft = validation.draft!;
      final renewMode = state['renewMode'] == true;
      final suggestedStartDate = state['suggestedStartDate'] as DateTime;
      final suggestedEndDate = state['suggestedEndDate'] as DateTime;

      if (renewMode && draft.startDate != null) {
        return jsonEncode(<String, dynamic>{
          'error':
              'يوجد اشتراك سابق لهذا العميل، لذلك تاريخ بداية التجديد يحدده النظام تلقائيًا حسب منطق الشاشة ولا يقبل التعديل اليدوي من الدردشة.',
          'code': 'office_client_subscription_start_locked',
          'clientName': match['name'],
          'suggestedStartDate': _fmtDate(suggestedStartDate),
          'suggestedEndDate': _fmtDate(suggestedEndDate),
        });
      }

      final effectiveReminderDays =
          draft.reminderDays ?? (state['reminderDays'] as int? ?? 1);
      final chosenStartDate = renewMode
          ? suggestedStartDate
          : _officeKsaDateOnly(draft.startDate ?? suggestedStartDate);
      final nowKsa = KsaTime.now();
      final effectiveStartDate = DateTime(
        chosenStartDate.year,
        chosenStartDate.month,
        chosenStartDate.day,
        nowKsa.hour,
        nowKsa.minute,
        nowKsa.second,
        nowKsa.millisecond,
        nowKsa.microsecond,
      );
      final effectiveEndDate = _officeSubscriptionEndFromStart(effectiveStartDate);
      final effectiveStartUtc = KsaTime.fromKsaToUtc(effectiveStartDate);
      final effectiveEndUtc = KsaTime.fromKsaToUtc(effectiveEndDate);

      final docId = (match['clientUid'] ?? '').toString().trim().isNotEmpty
          ? (match['clientUid'] ?? '').toString().trim()
          : (match['docId'] ?? '').toString().trim();
      if (docId.isEmpty) {
        return _err('تعذر تحديد سجل عميل المكتب لحفظ الاشتراك.');
      }

      await FirebaseFirestore.instance
          .collection('offices')
          .doc(effectiveUid())
          .collection('clients')
          .doc(docId)
          .set(<String, dynamic>{
        'subscriptionEnabled': true,
        'subscriptionType': 'monthly',
        'subscriptionReminderDays': effectiveReminderDays,
        'subscriptionPrice': draft.price,
        'subscriptionStartDate': _fmtDate(_officeKsaDateOnly(effectiveStartDate)),
        'subscriptionEndDate': _fmtDate(_officeKsaDateOnly(effectiveEndDate)),
        'subscriptionStartAt': Timestamp.fromDate(effectiveStartUtc),
        'subscriptionEndAt': Timestamp.fromDate(effectiveEndUtc),
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': renewMode
            ? 'تم تجديد اشتراك العميل "${match['name'] ?? ''}" بنجاح.'
            : 'تم تفعيل اشتراك العميل "${match['name'] ?? ''}" بنجاح.',
        'clientName': match['name'] ?? '',
        'clientUid': match['clientUid'] ?? docId,
        'subscriptionEnabled': true,
        'subscriptionType': 'monthly',
        'price': draft.price,
        'reminderDays': effectiveReminderDays,
        'startDate': _fmtDate(_officeKsaDateOnly(effectiveStartDate)),
        'endDate': _fmtDate(_officeKsaDateOnly(effectiveEndDate)),
        'renewMode': renewMode,
        'hasActiveSubscription': true,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن تفعيل أو تجديد اشتراك العميل الآن لأن العملية مرتبطة بالسيرفر مباشرة وتحتاج اتصال إنترنت فعلي.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر حفظ اشتراك العميل.');
    } catch (e) {
      return _err('تعذر حفظ اشتراك العميل: $e');
    }
  }

  Future<String> _generateOfficeClientResetLink(Map<String, dynamic> args) async {
    if (_officeClientsRef() == null) return _err('لا يمكن الوصول لبيانات المكتب');

    final query = (args['query'] ?? args['clientName'] ?? '').toString().trim();
    if (query.isEmpty) return _err('يرجى تحديد العميل');

    try {
      final clients = await _loadMergedOfficeClients();
      final match = _findOfficeClientRecordInList(clients, query);
      if (match == null) {
        return _err('لم يتم العثور على عميل باسم "$query"');
      }
      if (match['isLocal'] == true) {
        return jsonEncode(<String, dynamic>{
          'error':
              'هذا العميل لا يزال محليًا بانتظار المزامنة، لذلك لا يوجد حساب دخول فعلي لتوليد رابط إعادة تعيين له.',
          'code': 'office_client_pending_sync',
          'clientName': match['name'],
          'pendingSync': true,
        });
      }

      final email = (match['email'] ?? '').toString().trim();
      if (email.isEmpty) {
        return _err('لا يوجد بريد إلكتروني صالح لهذا العميل.');
      }
      final access = await _loadOfficeClientAccessState(match);
      if (access['userRecordFound'] != true) {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يوجد حساب دخول فعلي مرتبط بهذا العميل بعد، لذلك لا يمكن توليد رابط إعادة تعيين له الآن.',
          'code': 'office_client_login_not_ready',
          'clientName': match['name'],
        });
      }

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('generatePasswordResetLink');
      final res = await callable.call(<String, dynamic>{'email': email});
      final link =
          (res.data is Map ? (res.data as Map)['resetLink'] : null)?.toString().trim() ?? '';
      if (link.isEmpty) {
        return _err('تعذر توليد رابط إعادة التعيين.');
      }

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'تم توليد رابط إعادة تعيين كلمة المرور للعميل "${match['name'] ?? ''}".',
        'clientName': match['name'] ?? '',
        'clientUid': match['clientUid'] ?? '',
        'email': email,
        'resetLink': link,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        return jsonEncode(<String, dynamic>{
          'error':
              'لا يمكن توليد رابط إعادة التعيين الآن لأن العملية تحتاج اتصال إنترنت فعلي بالخدمة.',
          'code': 'requires_online',
          'nextStep': 'connect_to_internet_then_retry',
        });
      }
      return _err(e.message ?? 'تعذر توليد رابط إعادة التعيين.');
    } catch (e) {
      return _err('تعذر توليد رابط إعادة التعيين: $e');
    }
  }
}
