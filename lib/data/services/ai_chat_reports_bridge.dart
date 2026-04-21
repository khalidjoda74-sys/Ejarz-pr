import 'package:hive/hive.dart';

import '../../models/property.dart';
import '../../models/tenant.dart';
import '../../ui/contracts_screen.dart' show Contract, ContractTerm;
import '../../ui/invoices_screen.dart' show Invoice;
import '../../ui/maintenance_screen.dart'
    show MaintenancePriority, MaintenanceRequest;
import '../../utils/ksa_time.dart';
import '../constants/boxes.dart';
import 'comprehensive_reports_service.dart';
import 'hive_service.dart';
import 'tenant_record_service.dart';
import 'user_scope.dart';

class AiChatReportsBridge {
  AiChatReportsBridge._();

  static Future<Map<String, dynamic>> getDashboard(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final summary = context.snapshot.dashboard;
    final office = context.snapshot.office;
    final receivables = context.snapshot.contracts.fold<double>(
      0,
      (sum, item) => sum + item.remainingAmount,
    );
    final propertyById = <String, Property>{
      for (final property in context.allProperties) property.id: property,
    };
    final aggregatedProperties = _sortProperties(
      _aggregatePropertyRows(
        context.snapshot.properties,
        propertyById: propertyById,
      ),
      sortBy: 'net',
      sortDirection: 'desc',
    );
    final topProperties = aggregatedProperties
        .take(5)
        .map((item) => _propertyRowPayload(item, propertyById: propertyById))
        .toList(growable: false);
    final lowestProperties = aggregatedProperties.toList(growable: false)
      ..sort((a, b) => a.net.compareTo(b.net));
    final topOwners = context.snapshot.owners.toList(growable: false)
      ..sort((a, b) => b.readyForPayout.compareTo(a.readyForPayout));

    return <String, dynamic>{
      'screen': 'reports_dashboard',
      'appliedFilters': _filtersPayload(context),
      'summary': <String, dynamic>{
        'totalReceipts': summary.totalReceipts,
        'totalExpenses': summary.totalExpenses,
        'netCashFlow': summary.netCashFlow,
        'rentCollected': summary.rentCollected,
        'officeCommissions': summary.officeCommissions,
        'ownerTransferred': summary.ownerTransferred,
        'unpaidServiceBills': summary.unpaidServiceBills,
        'approvedVouchers': summary.approvedVouchers,
        'approvedReceiptVouchers': summary.approvedReceiptVouchers,
        'approvedPaymentVouchers': summary.approvedPaymentVouchers,
        'remainingContractReceivables': receivables,
      },
      'office': _officeSummaryPayload(office),
      'topPropertiesByNet': topProperties,
      'lowestPropertiesByNet': lowestProperties
          .take(5)
          .map((item) => _propertyRowPayload(item, propertyById: propertyById))
          .toList(growable: false),
      'ownersReadyForPayout': topOwners
          .take(5)
          .map(_ownerRowPayload)
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getPropertiesReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final propertyById = <String, Property>{
      for (final property in context.allProperties) property.id: property,
    };
    var items = _applyPropertyScope(
      context.snapshot.properties,
      context.propertyScopeIds,
      propertyOf: (item) => item.propertyId,
    );
    items = _aggregatePropertyRows(
      items,
      propertyById: propertyById,
    );

    final propertyType = _normalizePropertyType(args['propertyType']);
    if (propertyType != null) {
      items = items
          .where((item) => item.type == propertyType)
          .toList(growable: false);
    }

    final availability = _normalizeAvailability(args['availability']);
    if (availability == 'occupied') {
      items = items.where((item) => item.isOccupied).toList(growable: false);
    } else if (availability == 'vacant') {
      items = items.where((item) => !item.isOccupied).toList(growable: false);
    }

    final archivedCount = context.allProperties.where((property) {
      if (!property.isArchived) return false;
      if ((property.parentBuildingId ?? '').trim().isNotEmpty) return false;
      if (propertyType != null && property.type != propertyType) return false;
      if (context.propertyScopeIds.isNotEmpty &&
          !_scopeContainsPropertyOrUnit(
            property.id,
            context.propertyScopeIds,
            propertyById,
          )) {
        return false;
      }
      return true;
    }).length;

    final sorted = _sortProperties(
      items,
      sortBy: _stringArg(args, const <String>['sortBy']) ?? 'net',
      sortDirection:
          _stringArg(args, const <String>['sortDirection']) ?? 'desc',
    );
    final limit = _limitArg(args, defaultValue: 20);
    final visible = sorted
        .take(limit)
        .map((item) => _propertyRowPayload(item, propertyById: propertyById))
        .toList();
    final lowest = sorted.toList(growable: false)
      ..sort((a, b) => a.net.compareTo(b.net));
    final topLevelProperties = context.allProperties
        .where((property) => !property.isArchived)
        .where((property) => (property.parentBuildingId ?? '').trim().isEmpty)
        .where((property) {
          if (context.propertyScopeIds.isEmpty) return true;
          return _scopeContainsPropertyOrUnit(
            property.id,
            context.propertyScopeIds,
            propertyById,
          );
        })
        .toList(growable: false);
    final buildings = topLevelProperties
        .where((property) => property.type == PropertyType.building)
        .toList(growable: false);
    final registeredBuildingUnits = context.allProperties
        .where((property) => !property.isArchived)
        .where((property) => (property.parentBuildingId ?? '').trim().isNotEmpty)
        .where((property) {
          if (context.propertyScopeIds.isEmpty) return true;
          return context.propertyScopeIds.contains(property.id);
        })
        .length;
    final configuredBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _configuredUnitsForBuilding(building, propertyById),
    );
    final occupiedBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _occupiedUnitsForBuilding(building, propertyById),
    );
    final vacantBuildingUnits = buildings.fold<int>(
      0,
      (sum, building) => sum + _vacantUnitsForBuilding(building, propertyById),
    );

    return <String, dynamic>{
      'screen': 'reports_properties',
      'appliedFilters': <String, dynamic>{
        ..._filtersPayload(context),
        'propertyType': propertyType?.name,
        'propertyTypeLabel': propertyType?.label,
        'availability': availability ?? 'all',
      },
      'summary': <String, dynamic>{
        'total': items.length,
        'occupied': items.where((item) => item.isOccupied).length,
        'vacant': items.where((item) => !item.isOccupied).length,
        'archived': archivedCount,
        'topLevelProperties': topLevelProperties.length,
        'buildings': buildings.length,
        'standaloneProperties':
            topLevelProperties.length - buildings.length,
        'registeredBuildingUnits': registeredBuildingUnits,
        'configuredBuildingUnits': configuredBuildingUnits,
        'occupiedBuildingUnits': occupiedBuildingUnits,
        'vacantBuildingUnits': vacantBuildingUnits,
        'revenues': items.fold<double>(0, (sum, item) => sum + item.revenues),
        'expenses': items.fold<double>(0, (sum, item) => sum + item.expenses),
        'net': items.fold<double>(0, (sum, item) => sum + item.net),
        'semanticGuidance':
            'إجمالي العقارات هنا يُحسب على مستوى العقارات الرئيسية فقط، بينما الوحدات داخل العمائر تُعرض ضمن ملخص الوحدات ولا تُعامل كعقارات مستقلة.',
      },
      'topProperty': sorted.isEmpty
          ? null
          : _propertyRowPayload(sorted.first, propertyById: propertyById),
      'lowestProperty':
          lowest.isEmpty
              ? null
              : _propertyRowPayload(lowest.first, propertyById: propertyById),
      'items': visible,
    };
  }

  static Future<Map<String, dynamic>> getClientsReport(
    Map<String, dynamic> args,
  ) async {
    await HiveService.ensureReportsBoxesOpen();
    final tenants = _loadTenants(includeArchived: true);
    final includeArchived = _boolArg(args['includeArchived']) ?? false;
    final allClients = tenants
        .where((tenant) => includeArchived || !tenant.isArchived)
        .where((tenant) {
          final type = _dashboardClientType(tenant);
          return type == TenantRecordService.clientTypeTenant ||
              type == TenantRecordService.clientTypeCompany ||
              type == TenantRecordService.clientTypeServiceProvider;
        })
        .toList(growable: false);

    final clientTypeFilter =
        _normalizeClientTypeFilter(_stringArg(args, const <String>['clientType']));
    var filtered = allClients.toList(growable: false);
    if (clientTypeFilter != 'all') {
      filtered = filtered
          .where((tenant) => _dashboardClientType(tenant) == clientTypeFilter)
          .toList(growable: false);
    }

    final linkedState =
        _normalizeLinkedState(_stringArg(args, const <String>['linkedState']));
    if (linkedState == 'linked') {
      filtered = filtered
          .where((tenant) => tenant.activeContractsCount > 0)
          .toList(growable: false);
    } else if (linkedState == 'unlinked') {
      filtered = filtered
          .where((tenant) => tenant.activeContractsCount == 0)
          .toList(growable: false);
    }

    final idExpiryState =
        _normalizeIdExpiryState(_stringArg(args, const <String>['idExpiryState']));
    final today = KsaTime.dateOnly(KsaTime.now());
    if (idExpiryState == 'expired') {
      filtered = filtered.where((tenant) {
        final type = _dashboardClientType(tenant);
        return type == TenantRecordService.clientTypeTenant &&
            tenant.idExpiry != null &&
            KsaTime.dateOnly(tenant.idExpiry!).isBefore(today);
      }).toList(growable: false);
    } else if (idExpiryState == 'valid') {
      filtered = filtered.where((tenant) {
        final type = _dashboardClientType(tenant);
        if (type != TenantRecordService.clientTypeTenant) return true;
        if (tenant.idExpiry == null) return true;
        return !KsaTime.dateOnly(tenant.idExpiry!).isBefore(today);
      }).toList(growable: false);
    }

    filtered.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      if (updated != 0) return updated;
      final created = b.createdAt.compareTo(a.createdAt);
      if (created != 0) return created;
      return b.id.compareTo(a.id);
    });

    final limit = _limitArg(args, defaultValue: 20);
    return <String, dynamic>{
      'screen': 'reports_clients',
      'appliedFilters': <String, dynamic>{
        'clientType': clientTypeFilter,
        'linkedState': linkedState ?? 'all',
        'idExpiryState': idExpiryState ?? 'all',
        'includeArchived': includeArchived,
      },
      'summary': <String, dynamic>{
        'total': allClients.length,
        'tenants': allClients
            .where((tenant) =>
                _dashboardClientType(tenant) ==
                TenantRecordService.clientTypeTenant)
            .length,
        'companies': allClients
            .where((tenant) =>
                _dashboardClientType(tenant) ==
                TenantRecordService.clientTypeCompany)
            .length,
        'serviceProviders': allClients
            .where((tenant) =>
                _dashboardClientType(tenant) ==
                TenantRecordService.clientTypeServiceProvider)
            .length,
        'archived': tenants.where((tenant) => tenant.isArchived).length,
        'linkedContracts': allClients
            .where((tenant) => tenant.activeContractsCount > 0)
            .length,
        'unlinkedContracts': allClients
            .where((tenant) => tenant.activeContractsCount == 0)
            .length,
        'expiredIds': allClients.where((tenant) {
          return _dashboardClientType(tenant) ==
                  TenantRecordService.clientTypeTenant &&
              tenant.idExpiry != null &&
              KsaTime.dateOnly(tenant.idExpiry!).isBefore(today);
        }).length,
        'blacklisted': allClients.where((tenant) => tenant.isBlacklisted).length,
      },
      'items': filtered
          .take(limit)
          .map(_clientPayload)
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getContractsReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final contractsById = <String, Contract>{
      for (final contract in context.allContracts) contract.id: contract,
    };
    var items = _applyPropertyScope(
      context.snapshot.contracts,
      context.propertyScopeIds,
      propertyOf: (item) => item.propertyId,
    );

    final term = _normalizeContractTerm(args['term']);
    if (term != null) {
      items = items.where((item) {
        final contract = contractsById[item.contractId];
        return contract?.term == term;
      }).toList(growable: false);
    }

    final statusFilter =
        _normalizeContractStatus(_stringArg(args, const <String>['contractStatus']));
    if (statusFilter != null) {
      items = items
          .where(
            (item) => _normalizeToken(item.status) == _normalizeToken(statusFilter),
          )
          .toList(growable: false);
    }

    if (_boolArg(args['expiringOnly']) == true) {
      items = items.where((item) {
        final contract = contractsById[item.contractId];
        return contract != null && _isContractNearEnd(contract);
      }).toList(growable: false);
    }

    if (_boolArg(args['endsTodayOnly']) == true) {
      items = items.where((item) {
        final contract = contractsById[item.contractId];
        return contract != null && _contractEndsToday(contract);
      }).toList(growable: false);
    }

    final limit = _limitArg(args, defaultValue: 20);
    final sorted = items.toList(growable: false)
      ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));

    return <String, dynamic>{
      'screen': 'reports_contracts',
      'appliedFilters': <String, dynamic>{
        ..._filtersPayload(context),
        'term': term?.name,
        'termLabel': term == null ? null : _contractTermLabel(term),
        'contractStatus': statusFilter,
        'expiringOnly': _boolArg(args['expiringOnly']) == true,
        'endsTodayOnly': _boolArg(args['endsTodayOnly']) == true,
      },
      'summary': <String, dynamic>{
        'total': items.length,
        'active': items.where((item) => item.status == 'نشط').length,
        'inactive': items.where((item) => item.status == 'غير نشط').length,
        'ended': items.where((item) => item.status == 'منتهي').length,
        'terminated': items.where((item) => item.status == 'منهى').length,
        'expiringSoon30Days': items.where((item) {
          final contract = contractsById[item.contractId];
          return contract != null && _isContractNearEnd(contract);
        }).length,
        'endsToday': items.where((item) {
          final contract = contractsById[item.contractId];
          return contract != null && _contractEndsToday(contract);
        }).length,
        'totalAmount': items.fold<double>(0, (sum, item) => sum + item.totalAmount),
        'paidAmount': items.fold<double>(0, (sum, item) => sum + item.paidAmount),
        'remainingAmount':
            items.fold<double>(0, (sum, item) => sum + item.remainingAmount),
      },
      'items': sorted.take(limit).map(_contractRowPayload).toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getServicesReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final priorityByRequestId = <String, MaintenancePriority>{
      for (final request in context.allMaintenance) request.id: request.priority,
    };
    var items = _applyPropertyScope(
      context.snapshot.services,
      context.propertyScopeIds,
      propertyOf: (item) => item.propertyId,
    );

    final serviceType =
        _normalizeServiceType(_stringArg(args, const <String>['serviceType']));
    if (serviceType != null) {
      items = items
          .where((item) => _normalizeServiceType(item.serviceType) == serviceType)
          .toList(growable: false);
    }

    final priority = _normalizePriority(args['priority']);
    if (priority != null) {
      items = items.where((item) {
        return priorityByRequestId[item.id] == priority;
      }).toList(growable: false);
    }

    final paymentState =
        _normalizePaymentState(_stringArg(args, const <String>['paymentState']));
    if (paymentState == 'paid') {
      items = items.where((item) => item.isPaid).toList(growable: false);
    } else if (paymentState == 'unpaid') {
      items = items.where((item) => !item.isPaid).toList(growable: false);
    }

    final limit = _limitArg(args, defaultValue: 20);
    final sorted = items.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));

    return <String, dynamic>{
      'screen': 'reports_services',
      'appliedFilters': <String, dynamic>{
        ..._filtersPayload(context),
        'serviceType': serviceType,
        'serviceTypeLabel':
            serviceType == null ? null : _serviceTypeLabel(serviceType),
        'priority': priority?.name,
        'priorityLabel': priority == null ? null : _priorityLabel(priority),
        'paymentState': paymentState ?? 'all',
      },
      'summary': <String, dynamic>{
        'total': items.length,
        'paid': items.where((item) => item.isPaid).length,
        'unpaid': items.where((item) => !item.isPaid).length,
        'posted': items.where((item) => item.state == VoucherState.posted).length,
        'cancelled': items
            .where((item) => item.state == VoucherState.cancelled)
            .length,
        'amount': items.fold<double>(0, (sum, item) => sum + item.amount),
      },
      'items': sorted.take(limit).map((item) {
        final rowPriority = priorityByRequestId[item.id];
        return _serviceRowPayload(item, priority: rowPriority);
      }).toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getVouchersReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    var items = _applyPropertyScope(
      context.snapshot.vouchers,
      context.propertyScopeIds,
      propertyOf: (item) => item.propertyId,
    );

    final direction =
        _normalizeVoucherDirection(_stringArg(args, const <String>['direction']));
    if (direction != null) {
      items = items
          .where((item) => item.direction == direction)
          .toList(growable: false);
    }

    final operation =
        _normalizeVoucherOperation(_stringArg(args, const <String>['operation']));
    if (operation != null) {
      items = items
          .where((item) => _voucherOperationKey(item) == operation)
          .toList(growable: false);
    }

    final limit = _limitArg(args, defaultValue: 25);
    final sorted = items.toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));

    return <String, dynamic>{
      'screen': 'reports_vouchers',
      'appliedFilters': <String, dynamic>{
        ..._filtersPayload(context),
        'direction': direction?.name,
        'directionLabel': direction?.arLabel,
        'operation': operation,
      },
      'summary': <String, dynamic>{
        'total': items.length,
        'receipts': items
            .where((item) => item.direction == VoucherDirection.receipt)
            .length,
        'payments': items
            .where((item) => item.direction == VoucherDirection.payment)
            .length,
        'posted': items.where((item) => item.state == VoucherState.posted).length,
        'cancelled': items
            .where((item) =>
                item.state == VoucherState.cancelled ||
                item.state == VoucherState.reversed)
            .length,
        'receiptAmount': items
            .where((item) => item.direction == VoucherDirection.receipt)
            .fold<double>(0, (sum, item) => sum + item.amount),
        'paymentAmount': items
            .where((item) => item.direction == VoucherDirection.payment)
            .fold<double>(0, (sum, item) => sum + item.amount),
      },
      'items': sorted
          .take(limit)
          .map((item) => _voucherRowPayload(item, context.snapshot))
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getOfficeReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final commissionRule = await ComprehensiveReportsService.getCommissionRule(
      scope: CommissionScope.global,
    );
    final ledgerLimit = _limitArg(
      args,
      keys: const <String>['ledgerLimit', 'limit'],
      defaultValue: 15,
    );

    return <String, dynamic>{
      'screen': 'reports_office',
      'appliedFilters': _filtersPayload(context),
      'summary': _officeSummaryPayload(context.snapshot.office),
      'commissionRule': <String, dynamic>{
        'mode': commissionRule.mode.name,
        'modeLabel': commissionRule.mode.arLabel,
        'value': commissionRule.value,
      },
      'ledger': context.snapshot.office.ledger
          .take(ledgerLimit)
          .map((item) => _officeLedgerPayload(item, context.snapshot))
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getOwnersReport(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args, usePropertyFilter: true);
    final owners = context.snapshot.owners.toList(growable: false)
      ..sort((a, b) => b.readyForPayout.compareTo(a.readyForPayout));
    final limit = _limitArg(args, defaultValue: 20);

    return <String, dynamic>{
      'screen': 'reports_owners',
      'appliedFilters': _filtersPayload(context),
      'summary': <String, dynamic>{
        'total': owners.length,
        'rentCollected':
            owners.fold<double>(0, (sum, item) => sum + item.rentCollected),
        'officeCommissions':
            owners.fold<double>(0, (sum, item) => sum + item.officeCommissions),
        'ownerExpenses':
            owners.fold<double>(0, (sum, item) => sum + item.ownerExpenses),
        'ownerAdjustments':
            owners.fold<double>(0, (sum, item) => sum + item.ownerAdjustments),
        'previousTransfers':
            owners.fold<double>(0, (sum, item) => sum + item.previousTransfers),
        'currentBalance':
            owners.fold<double>(0, (sum, item) => sum + item.currentBalance),
        'readyForPayout':
            owners.fold<double>(0, (sum, item) => sum + item.readyForPayout),
      },
      'topOwnerByPayout':
          owners.isEmpty ? null : _ownerRowPayload(owners.first),
      'items':
          owners.take(limit).map(_ownerRowPayload).toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> getOwnerReportDetails(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(
      args,
      requireOwner: true,
      usePropertyFilter: true,
    );
    final owner = context.snapshot.owners.firstWhere(
      (item) => item.ownerId == context.owner!.id,
      orElse: () => OwnerReportItem(
        ownerId: context.owner!.id,
        ownerName: context.owner!.name,
        previousBalance: 0,
        rentCollected: 0,
        officeCommissions: 0,
        ownerExpenses: 0,
        ownerAdjustments: 0,
        previousTransfers: 0,
        currentBalance: 0,
        readyForPayout: 0,
        ledger: const <OwnerLedgerEntry>[],
        linkedProperties: 0,
        propertyBreakdowns: const <OwnerPropertyReportItem>[],
      ),
    );
    final ledgerLimit = _limitArg(
      args,
      keys: const <String>['ledgerLimit', 'limit'],
      defaultValue: 20,
    );
    final bankAccounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
      owner.ownerId,
    );

    return <String, dynamic>{
      'screen': 'reports_owner_details',
      'appliedFilters': _filtersPayload(context),
      'owner': _ownerRowPayload(owner),
      'propertyBreakdowns': owner.propertyBreakdowns
          .map(_ownerPropertyPayload)
          .toList(growable: false),
      'ledger': owner.ledger
          .take(ledgerLimit)
          .map((item) => _ownerLedgerPayload(item, context.snapshot))
          .toList(growable: false),
      'bankAccounts': bankAccounts
          .map(_ownerBankAccountPayload)
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> previewOwnerSettlement(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(
      args,
      requireOwner: true,
      usePropertyFilter: true,
    );
    final preview = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: context.owner!.id,
      filters: context.filters,
    );
    return <String, dynamic>{
      'screen': 'reports_owner_settlement_preview',
      'appliedFilters': _filtersPayload(context),
      'preview': _ownerSettlementPreviewPayload(preview),
    };
  }

  static Future<Map<String, dynamic>> previewOfficeSettlement(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args);
    final preview = await ComprehensiveReportsService.previewOfficeSettlement(
      filters: context.filters,
    );
    return <String, dynamic>{
      'screen': 'reports_office_settlement_preview',
      'appliedFilters': _filtersPayload(context),
      'preview': _officeSettlementPreviewPayload(preview),
    };
  }

  static Future<Map<String, dynamic>> getOwnerBankAccounts(
    Map<String, dynamic> args,
  ) async {
    final context = await _loadContext(args, requireOwner: true);
    final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
      context.owner!.id,
    );
    return <String, dynamic>{
      'screen': 'reports_owner_bank_accounts',
      'owner': <String, dynamic>{
        'ownerId': context.owner!.id,
        'ownerName': context.owner!.name,
      },
      'accounts': accounts
          .map(_ownerBankAccountPayload)
          .toList(growable: false),
    };
  }

  static Future<Map<String, dynamic>> assignPropertyOwner(
    String propertyQuery,
    String ownerQuery,
  ) async {
    await HiveService.ensureReportsBoxesOpen();
    await ComprehensiveReportsService.ensureFinanceBoxesOpen();

    final property = _resolveProperty(propertyQuery, _loadProperties(includeArchived: true));
    if (property == null) {
      throw StateError('تعذر العثور على العقار المطلوب.');
    }

    final owner = _resolveAnyTenant(ownerQuery, _loadTenants());
    if (owner == null) {
      throw StateError('تعذر العثور على المالك المطلوب.');
    }

    await ComprehensiveReportsService.assignPropertyOwner(
      propertyId: property.id,
      ownerId: owner.id,
      ownerName: owner.name,
    );

    return <String, dynamic>{
      'success': true,
      'message': 'تم تحديث مالك العقار بنجاح.',
      'propertyId': property.id,
      'propertyName': property.name,
      'ownerId': owner.id,
      'ownerName': owner.name,
    };
  }

  static Future<Map<String, dynamic>> recordOfficeVoucher({
    required bool isExpense,
    required double amount,
    required DateTime transactionDate,
    required String note,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ComprehensiveReportsService.ensureFinanceBoxesOpen();

    if (!isExpense) {
      final rule = await ComprehensiveReportsService.getCommissionRule(
        scope: CommissionScope.global,
      );
      if (rule.mode != CommissionMode.fixed) {
        throw StateError(
          'إيراد عمولة المكتب اليدوي متاح فقط عندما يكون نظام العمولة مبلغًا ثابتًا.',
        );
      }
    }

    final invoice = await ComprehensiveReportsService.executeOfficeManualVoucher(
      isExpense: isExpense,
      amount: amount,
      transactionDate: transactionDate,
      note: note,
    );

    return <String, dynamic>{
      'success': true,
      'message': isExpense
          ? 'تم تسجيل مصروف المكتب بنجاح.'
          : 'تم تسجيل إيراد عمولة المكتب بنجاح.',
      'voucherId': invoice.id,
      'voucherSerialNo': invoice.serialNo ?? invoice.id,
      'amount': amount.abs(),
      'transactionDate': _fmtDate(transactionDate),
      'operation': isExpense ? 'office_expense' : 'office_commission',
    };
  }

  static Future<Map<String, dynamic>> recordOfficeWithdrawal({
    required double amount,
    required DateTime transferDate,
    required String note,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final filters = _buildFilters(fromDate: fromDate, toDate: toDate);
    final previewBefore =
        await ComprehensiveReportsService.previewOfficeSettlement(filters: filters);
    final invoice = await ComprehensiveReportsService.executeOfficeWithdrawal(
      amount: amount,
      transferDate: transferDate,
      note: note,
      filters: filters,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم تنفيذ تحويل المكتب بنجاح.',
      'voucherId': invoice.id,
      'voucherSerialNo': invoice.serialNo ?? invoice.id,
      'amount': amount.abs(),
      'transferDate': _fmtDate(transferDate),
      'readyBefore': previewBefore.readyForWithdrawal,
      'readyAfter':
          (previewBefore.readyForWithdrawal - amount.abs()).clamp(0, double.infinity),
    };
  }

  static Future<Map<String, dynamic>> setCommissionRule({
    required CommissionMode mode,
    required double value,
  }) async {
    await ComprehensiveReportsService.setCommissionRule(
      scope: CommissionScope.global,
      rule: CommissionRule(mode: mode, value: value),
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم حفظ إعداد عمولة المكتب بنجاح.',
      'mode': mode.name,
      'modeLabel': mode.arLabel,
      'value': value,
    };
  }

  static Future<Map<String, dynamic>> recordOwnerPayout({
    required String ownerQuery,
    String? propertyQuery,
    required double amount,
    required DateTime transferDate,
    required String note,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final context = await _loadContext(
      <String, dynamic>{
        'ownerQuery': ownerQuery,
        if ((propertyQuery ?? '').trim().isNotEmpty) 'propertyQuery': propertyQuery,
        if (fromDate != null) 'fromDate': _fmtDate(fromDate),
        if (toDate != null) 'toDate': _fmtDate(toDate),
      },
      requireOwner: true,
      usePropertyFilter: true,
    );
    final previewBefore = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: context.owner!.id,
      filters: context.filters,
    );
    final record = await ComprehensiveReportsService.executeOwnerPayout(
      ownerId: context.owner!.id,
      ownerName: context.owner!.name,
      amount: amount,
      transferDate: transferDate,
      periodFrom: fromDate,
      periodTo: toDate,
      note: note,
      propertyId: context.property?.id ?? '',
      propertyName: context.property?.name ?? '',
      filters: context.filters,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم تنفيذ تحويل المالك بنجاح.',
      'ownerId': context.owner!.id,
      'ownerName': context.owner!.name,
      'propertyId': context.property?.id,
      'propertyName': context.property?.name,
      'amount': amount.abs(),
      'transferDate': _fmtDate(transferDate),
      'voucherId': record.voucherId,
      'voucherSerialNo': record.voucherSerialNo,
      'readyBefore': previewBefore.readyForPayout,
      'readyAfter':
          (previewBefore.readyForPayout - amount.abs()).clamp(0, double.infinity),
    };
  }

  static Future<Map<String, dynamic>> recordOwnerAdjustment({
    required String ownerQuery,
    String? propertyQuery,
    required OwnerAdjustmentCategory category,
    required double amount,
    required DateTime adjustmentDate,
    required String note,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final context = await _loadContext(
      <String, dynamic>{
        'ownerQuery': ownerQuery,
        if ((propertyQuery ?? '').trim().isNotEmpty) 'propertyQuery': propertyQuery,
        if (fromDate != null) 'fromDate': _fmtDate(fromDate),
        if (toDate != null) 'toDate': _fmtDate(toDate),
      },
      requireOwner: true,
      usePropertyFilter: true,
    );
    final previewBefore = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: context.owner!.id,
      filters: context.filters,
    );
    final record = await ComprehensiveReportsService.executeOwnerAdjustment(
      ownerId: context.owner!.id,
      ownerName: context.owner!.name,
      amount: amount,
      category: category,
      adjustmentDate: adjustmentDate,
      periodFrom: fromDate,
      periodTo: toDate,
      note: note,
      propertyId: context.property?.id ?? '',
      propertyName: context.property?.name ?? '',
      filters: context.filters,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم تسجيل خصم/تسوية المالك بنجاح.',
      'ownerId': context.owner!.id,
      'ownerName': context.owner!.name,
      'propertyId': context.property?.id,
      'propertyName': context.property?.name,
      'category': category.name,
      'categoryLabel': category.arLabel,
      'amount': amount.abs(),
      'adjustmentDate': _fmtDate(adjustmentDate),
      'voucherId': record.voucherId,
      'readyBefore': previewBefore.readyForPayout,
      'readyAfter':
          (previewBefore.readyForPayout - amount.abs()).clamp(0, double.infinity),
    };
  }

  static Future<Map<String, dynamic>> addOwnerBankAccount({
    required String ownerQuery,
    required String bankName,
    required String accountNumber,
    required String iban,
  }) async {
    final context = await _loadContext(
      <String, dynamic>{'ownerQuery': ownerQuery},
      requireOwner: true,
    );
    final record = await ComprehensiveReportsService.addOwnerBankAccount(
      ownerId: context.owner!.id,
      ownerName: context.owner!.name,
      bankName: bankName,
      accountNumber: accountNumber,
      iban: iban,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم حفظ الحساب البنكي للمالك.',
      'ownerId': context.owner!.id,
      'ownerName': context.owner!.name,
      'account': _ownerBankAccountPayload(record),
    };
  }

  static Future<Map<String, dynamic>> editOwnerBankAccount({
    required String ownerQuery,
    required String accountQuery,
    required String bankName,
    required String accountNumber,
    required String iban,
  }) async {
    final context = await _loadContext(
      <String, dynamic>{'ownerQuery': ownerQuery},
      requireOwner: true,
    );
    final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
      context.owner!.id,
    );
    final account = _resolveOwnerBankAccount(accountQuery, accounts);
    if (account == null) {
      throw StateError('تعذر العثور على الحساب البنكي المطلوب.');
    }
    final updated = await ComprehensiveReportsService.updateOwnerBankAccount(
      accountId: account.id,
      ownerId: context.owner!.id,
      ownerName: context.owner!.name,
      bankName: bankName,
      accountNumber: accountNumber,
      iban: iban,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم تحديث الحساب البنكي للمالك.',
      'ownerId': context.owner!.id,
      'ownerName': context.owner!.name,
      'account': _ownerBankAccountPayload(updated),
    };
  }

  static Future<Map<String, dynamic>> deleteOwnerBankAccount({
    required String ownerQuery,
    required String accountQuery,
  }) async {
    final context = await _loadContext(
      <String, dynamic>{'ownerQuery': ownerQuery},
      requireOwner: true,
    );
    final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
      context.owner!.id,
    );
    final account = _resolveOwnerBankAccount(accountQuery, accounts);
    if (account == null) {
      throw StateError('تعذر العثور على الحساب البنكي المطلوب.');
    }
    await ComprehensiveReportsService.deleteOwnerBankAccount(
      accountId: account.id,
      ownerId: context.owner!.id,
    );
    return <String, dynamic>{
      'success': true,
      'message': 'تم حذف الحساب البنكي للمالك.',
      'ownerId': context.owner!.id,
      'ownerName': context.owner!.name,
      'accountId': account.id,
      'bankName': account.bankName,
      'accountNumber': account.accountNumber,
    };
  }

  static Future<_ReportsContext> _loadContext(
    Map<String, dynamic> args, {
    bool requireOwner = false,
    bool usePropertyFilter = false,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ComprehensiveReportsService.ensureFinanceBoxesOpen();

    final fromDate = _dateArg(args, const <String>['fromDate', 'from']);
    final toDate = _dateArg(args, const <String>['toDate', 'to']);
    if (fromDate != null && toDate != null && fromDate.isAfter(toDate)) {
      throw StateError('تاريخ البداية يجب أن يكون قبل أو يساوي تاريخ النهاية.');
    }

    final properties = _loadProperties();
    final tenants = _loadTenants(includeArchived: true);
    final contracts = _loadContracts();
    final maintenance = _loadMaintenance();

    final propertyQuery = _stringArg(args, const <String>['propertyQuery']);
    final ownerQuery = _stringArg(args, const <String>['ownerQuery']);
    final contractQuery = _stringArg(
      args,
      const <String>['contractQuery', 'contractNo', 'contractSerialNo'],
    );

    final property = propertyQuery == null
        ? null
        : _resolveProperty(propertyQuery, properties);
    if (propertyQuery != null && property == null) {
      throw StateError('تعذر العثور على العقار المطلوب.');
    }

    final owner = ownerQuery == null
        ? null
        : _resolveOwnerReference(ownerQuery, tenants, null);

    final contract = contractQuery == null
        ? null
        : _resolveContract(contractQuery, contracts);
    if (contractQuery != null && contract == null) {
      throw StateError('تعذر العثور على العقد المطلوب.');
    }

    final serviceType =
        _normalizeServiceType(_stringArg(args, const <String>['serviceType']));
    final contractStatus =
        _normalizeContractStatus(_stringArg(args, const <String>['contractStatus']));
    final voucherState =
        _normalizeVoucherState(_stringArg(args, const <String>['voucherState']));
    final voucherSource =
        _normalizeVoucherSource(_stringArg(args, const <String>['voucherSource']));
    final includeDraft = _boolArg(args['includeDraft']);
    final includeCancelled = _boolArg(args['includeCancelled']);

    final propertyScopeIds = property == null
        ? const <String>{}
        : _propertyScopeIds(property, properties);

    final filters = ComprehensiveReportFilters(
      from: fromDate,
      to: toDate,
      propertyId: usePropertyFilter ? property?.id : null,
      ownerId: owner?.id,
      contractId: contract?.id,
      serviceType: serviceType,
      contractStatus: contractStatus,
      voucherState: voucherState,
      voucherSource: voucherSource,
      includeDraft: includeDraft ?? true,
      includeCancelled: includeCancelled ?? false,
    );

    final snapshot = await ComprehensiveReportsService.load(filters);
    final resolvedOwner = owner ??
        _resolveOwnerReference(
          ownerQuery ?? '',
          tenants,
          snapshot,
        );
    if (requireOwner && resolvedOwner == null) {
      throw StateError('تعذر العثور على المالك المطلوب.');
    }

    return _ReportsContext(
      snapshot: snapshot,
      filters: filters,
      allProperties: properties,
      allTenants: tenants,
      allContracts: contracts,
      allMaintenance: maintenance,
      property: property,
      owner: resolvedOwner,
      contract: contract,
      propertyScopeIds: propertyScopeIds,
    );
  }

  static ComprehensiveReportFilters _buildFilters({
    DateTime? fromDate,
    DateTime? toDate,
    String? propertyId,
    String? ownerId,
  }) {
    if (fromDate != null && toDate != null && fromDate.isAfter(toDate)) {
      throw StateError('تاريخ البداية يجب أن يكون قبل أو يساوي تاريخ النهاية.');
    }
    return ComprehensiveReportFilters(
      from: fromDate,
      to: toDate,
      propertyId: (propertyId ?? '').trim().isEmpty ? null : propertyId,
      ownerId: (ownerId ?? '').trim().isEmpty ? null : ownerId,
    );
  }

  static List<Property> _loadProperties({bool includeArchived = false}) {
    final name = boxName(kPropertiesBox);
    if (!Hive.isBoxOpen(name)) return const <Property>[];
    return Hive.box<Property>(name)
        .values
        .where((property) => includeArchived || !property.isArchived)
        .toList(growable: false);
  }

  static List<Tenant> _loadTenants({bool includeArchived = false}) {
    final name = boxName(kTenantsBox);
    if (!Hive.isBoxOpen(name)) return const <Tenant>[];
    return Hive.box<Tenant>(name)
        .values
        .where((tenant) => includeArchived || !tenant.isArchived)
        .toList(growable: false);
  }

  static List<Contract> _loadContracts() {
    final name = HiveService.contractsBoxName();
    if (!Hive.isBoxOpen(name)) return const <Contract>[];
    return Hive.box<Contract>(name).values.toList(growable: false);
  }

  static List<MaintenanceRequest> _loadMaintenance() {
    final name = HiveService.maintenanceBoxName();
    if (!Hive.isBoxOpen(name)) return const <MaintenanceRequest>[];
    return Hive.box<MaintenanceRequest>(name).values.toList(growable: false);
  }

  static List<T> _applyPropertyScope<T>(
    List<T> items,
    Set<String> scopeIds, {
    String Function(T item)? propertyOf,
  }) {
    if (scopeIds.isEmpty) return items;
    final resolver = propertyOf;
    if (resolver == null) return items;
    return items
        .where((item) => scopeIds.contains(resolver(item).trim()))
        .toList(growable: false);
  }

  static Set<String> _propertyScopeIds(Property property, List<Property> all) {
    final ids = <String>{property.id};
    for (final candidate in all) {
      if ((candidate.parentBuildingId ?? '').trim() == property.id) {
        ids.add(candidate.id);
      }
    }
    return ids;
  }

  static Property? _resolveProperty(String query, List<Property> properties) {
    final normalized = _normalizeToken(query);
    if (normalized.isEmpty) return null;
    for (final property in properties) {
      if (property.id == query.trim() ||
          _normalizeToken(property.name).contains(normalized)) {
        return property;
      }
    }
    return null;
  }

  static _ResolvedOwnerRef? _resolveOwnerReference(
    String query,
    List<Tenant> tenants,
    ComprehensiveReportSnapshot? snapshot,
  ) {
    final normalized = _normalizeToken(query);
    if (normalized.isEmpty) return null;

    for (final tenant in tenants) {
      final clientType = _dashboardClientType(tenant);
      final isOwner =
          _normalizeToken(tenant.clientType) == 'owner' ||
          _normalizeToken(tenant.clientType) == 'مالك' ||
          clientType == 'owner';
      if (!isOwner && snapshot == null) {
        continue;
      }
      final fields = <String>[
        tenant.id,
        tenant.fullName,
        tenant.nationalId,
        tenant.phone,
        tenant.email ?? '',
      ];
      if (fields.any((field) => _normalizeToken(field).contains(normalized))) {
        return _ResolvedOwnerRef(
          id: tenant.id,
          name: tenant.fullName,
        );
      }
    }

    if (snapshot != null) {
      for (final entry in snapshot.ownerNames.entries) {
        if (_normalizeToken(entry.key).contains(normalized) ||
            _normalizeToken(entry.value).contains(normalized)) {
          return _ResolvedOwnerRef(id: entry.key, name: entry.value);
        }
      }
    }

    return null;
  }

  static _ResolvedOwnerRef? _resolveAnyTenant(
    String query,
    List<Tenant> tenants,
  ) {
    final normalized = _normalizeToken(query);
    if (normalized.isEmpty) return null;
    for (final tenant in tenants) {
      final fields = <String>[
        tenant.id,
        tenant.fullName,
        tenant.nationalId,
        tenant.phone,
        tenant.email ?? '',
      ];
      if (fields.any((field) => _normalizeToken(field).contains(normalized))) {
        return _ResolvedOwnerRef(id: tenant.id, name: tenant.fullName);
      }
    }
    return null;
  }

  static Contract? _resolveContract(String query, List<Contract> contracts) {
    final normalized = _normalizeToken(query);
    if (normalized.isEmpty) return null;
    for (final contract in contracts) {
      final serial = (contract.serialNo ?? '').trim();
      final tenantName =
          (contract.tenantSnapshot?['fullName'] ?? '').toString().trim();
      final propertyName =
          (contract.propertySnapshot?['name'] ?? '').toString().trim();
      if (_normalizeToken(contract.id).contains(normalized) ||
          _normalizeToken(serial).contains(normalized) ||
          _normalizeToken(tenantName).contains(normalized) ||
          _normalizeToken(propertyName).contains(normalized)) {
        return contract;
      }
    }
    return null;
  }

  static OwnerBankAccountRecord? _resolveOwnerBankAccount(
    String query,
    List<OwnerBankAccountRecord> accounts,
  ) {
    final normalized = _normalizeToken(query);
    if (normalized.isEmpty) return null;
    for (final account in accounts) {
      final fields = <String>[
        account.id,
        account.bankName,
        account.accountNumber,
        account.iban,
      ];
      if (fields.any((field) => _normalizeToken(field).contains(normalized))) {
        return account;
      }
    }
    return null;
  }

  static List<PropertyReportItem> _sortProperties(
    List<PropertyReportItem> items, {
    required String sortBy,
    required String sortDirection,
  }) {
    final sorted = items.toList(growable: false);
    final descending = _normalizeToken(sortDirection) != 'asc';
    int compare(PropertyReportItem a, PropertyReportItem b) {
      switch (_normalizeToken(sortBy)) {
        case 'revenues':
        case 'revenue':
          return a.revenues.compareTo(b.revenues);
        case 'expenses':
        case 'expense':
          return a.expenses.compareTo(b.expenses);
        case 'overdue':
        case 'overdueamount':
          return a.overdueAmount.compareTo(b.overdueAmount);
        case 'name':
          return a.propertyName.compareTo(b.propertyName);
        case 'net':
        default:
          return a.net.compareTo(b.net);
      }
    }

    sorted.sort((a, b) => descending ? compare(b, a) : compare(a, b));
    return sorted;
  }

  static Map<String, dynamic> _filtersPayload(_ReportsContext context) {
    return <String, dynamic>{
      'fromDate': _fmtDate(context.filters.from),
      'toDate': _fmtDate(context.filters.to),
      'propertyId': context.property?.id,
      'propertyName': context.property?.name,
      'ownerId': context.owner?.id,
      'ownerName': context.owner?.name,
      'contractId': context.contract?.id,
      'contractNo': context.contract?.serialNo,
      'includeDraft': context.filters.includeDraft,
      'includeCancelled': context.filters.includeCancelled,
      'serviceType': context.filters.serviceType,
      'contractStatus': context.filters.contractStatus,
      'voucherState': context.filters.voucherState?.name,
      'voucherSource': context.filters.voucherSource?.name,
    };
  }

  static List<PropertyReportItem> _aggregatePropertyRows(
    List<PropertyReportItem> items, {
    required Map<String, Property> propertyById,
  }) {
    final grouped = <String, _PropertyAggregation>{};
    for (final item in items) {
      final topLevelProperty = _topLevelPropertyFor(item.propertyId, propertyById);
      final groupId = (topLevelProperty?.id ?? item.propertyId).trim();
      final aggregation = grouped.putIfAbsent(
        groupId,
        () => _PropertyAggregation(
          propertyId: groupId.isEmpty ? item.propertyId : groupId,
          propertyName:
              (topLevelProperty?.name ?? item.propertyName).trim().isEmpty
                  ? item.propertyName
                  : (topLevelProperty?.name ?? item.propertyName).trim(),
          ownerId: item.ownerId,
          ownerName: item.ownerName,
          type: topLevelProperty?.type ?? item.type,
          isOccupied: _isAssetOccupied(topLevelProperty, propertyById) ||
              item.isOccupied,
        ),
      );
      aggregation.add(item);
    }
    return grouped.values
        .map((aggregation) => aggregation.toItem())
        .toList(growable: false);
  }

  static Property? _topLevelPropertyFor(
    String propertyId,
    Map<String, Property> propertyById,
  ) {
    final normalizedId = propertyId.trim();
    if (normalizedId.isEmpty) return null;
    var property = propertyById[normalizedId];
    if (property == null) return null;
    final visited = <String>{};
    while ((property!.parentBuildingId ?? '').trim().isNotEmpty) {
      final parentId = (property.parentBuildingId ?? '').trim();
      if (!visited.add(parentId)) break;
      final parent = propertyById[parentId];
      if (parent == null) break;
      property = parent;
    }
    return property;
  }

  static bool _scopeContainsPropertyOrUnit(
    String propertyId,
    Set<String> scopeIds,
    Map<String, Property> propertyById,
  ) {
    if (scopeIds.contains(propertyId.trim())) return true;
    return propertyById.values.any(
      (property) =>
          (property.parentBuildingId ?? '').trim() == propertyId.trim() &&
          scopeIds.contains(property.id),
    );
  }

  static bool _isPerUnitBuilding(Property property) {
    return property.type == PropertyType.building &&
        property.rentalMode == RentalMode.perUnit;
  }

  static int _registeredUnitsForBuilding(
    Property building,
    Map<String, Property> propertyById,
  ) {
    return propertyById.values
        .where(
          (property) => (property.parentBuildingId ?? '').trim() == building.id,
        )
        .where((property) => !property.isArchived)
        .length;
  }

  static int _configuredUnitsForBuilding(
    Property building,
    Map<String, Property> propertyById,
  ) {
    final registered = _registeredUnitsForBuilding(building, propertyById);
    if (building.totalUnits > registered) return building.totalUnits;
    return registered;
  }

  static int _occupiedUnitsForBuilding(
    Property building,
    Map<String, Property> propertyById,
  ) {
    if (_isPerUnitBuilding(building)) {
      return propertyById.values
          .where(
            (property) =>
                (property.parentBuildingId ?? '').trim() == building.id,
          )
          .where((property) => !property.isArchived)
          .where((property) => property.occupiedUnits > 0)
          .length;
    }
    return building.occupiedUnits > 0 ? 1 : 0;
  }

  static int _vacantUnitsForBuilding(
    Property building,
    Map<String, Property> propertyById,
  ) {
    final total = _isPerUnitBuilding(building)
        ? _configuredUnitsForBuilding(building, propertyById)
        : 1;
    final occupied = _occupiedUnitsForBuilding(building, propertyById);
    final vacant = total - occupied;
    return vacant < 0 ? 0 : vacant;
  }

  static bool _isAssetOccupied(
    Property? property,
    Map<String, Property> propertyById,
  ) {
    if (property == null) return false;
    if (_isPerUnitBuilding(property)) {
      return _occupiedUnitsForBuilding(property, propertyById) > 0;
    }
    return property.occupiedUnits > 0;
  }

  static Map<String, dynamic> _propertyRowPayload(
    PropertyReportItem item, {
    Map<String, Property>? propertyById,
  }) {
    final payload = <String, dynamic>{
      'propertyId': item.propertyId,
      'propertyName': item.propertyName,
      'ownerId': item.ownerId,
      'ownerName': item.ownerName,
      'type': item.type.name,
      'typeLabel': item.type.label,
      'isOccupied': item.isOccupied,
      'activeContracts': item.activeContracts,
      'endedContracts': item.endedContracts,
      'receivedPayments': item.receivedPayments,
      'latePayments': item.latePayments,
      'upcomingPayments': item.upcomingPayments,
      'linkedVouchers': item.linkedVouchers,
      'revenues': item.revenues,
      'expenses': item.expenses,
      'serviceExpenses': item.serviceExpenses,
      'overdueAmount': item.overdueAmount,
      'net': item.net,
    };
    if (propertyById == null) return payload;
    final property = _topLevelPropertyFor(item.propertyId, propertyById);
    if (property == null) return payload;
    if (property.type == PropertyType.building) {
      payload.addAll(<String, dynamic>{
        'structureKind': 'building',
        'managementMode':
            _isPerUnitBuilding(property) ? 'units' : 'whole_building',
        'configuredUnits': _configuredUnitsForBuilding(property, propertyById),
        'registeredUnits': _registeredUnitsForBuilding(property, propertyById),
        'occupiedUnits': _occupiedUnitsForBuilding(property, propertyById),
        'vacantUnits': _vacantUnitsForBuilding(property, propertyById),
        'countsLabel': 'وحدات',
      });
      return payload;
    }
    payload.addAll(<String, dynamic>{
      'structureKind': 'property',
      'countsLabel': 'غرف',
    });
    return payload;
  }

  static Map<String, dynamic> _clientPayload(Tenant tenant) {
    final type = _dashboardClientType(tenant);
    return <String, dynamic>{
      'clientId': tenant.id,
      'fullName': tenant.fullName,
      'phone': tenant.phone,
      'nationalId': tenant.nationalId,
      'email': tenant.email,
      'clientType': type,
      'clientTypeLabel': _clientTypeLabel(type),
      'activeContractsCount': tenant.activeContractsCount,
      'isBlacklisted': tenant.isBlacklisted,
      'isArchived': tenant.isArchived,
      'idExpiry': _fmtDate(tenant.idExpiry),
      'updatedAt': _fmtDateTime(tenant.updatedAt),
    };
  }

  static Map<String, dynamic> _contractRowPayload(ContractReportItem item) {
    return <String, dynamic>{
      'contractId': item.contractId,
      'contractNo': item.contractNo,
      'propertyId': item.propertyId,
      'propertyName': item.propertyName,
      'tenantId': item.tenantId,
      'tenantName': item.tenantName,
      'ownerId': item.ownerId,
      'ownerName': item.ownerName,
      'status': item.status,
      'totalAmount': item.totalAmount,
      'paidAmount': item.paidAmount,
      'remainingAmount': item.remainingAmount,
      'overdueInstallments': item.overdueInstallments,
      'upcomingInstallments': item.upcomingInstallments,
      'nextDueDate': _fmtDate(item.nextDueDate),
      'linkedVouchers': item.linkedVouchers,
      'overdueAmount': item.overdueAmount,
    };
  }

  static Map<String, dynamic> _serviceRowPayload(
    ServiceReportItem item, {
    MaintenancePriority? priority,
  }) {
    final normalizedType = _normalizeServiceType(item.serviceType) ?? item.serviceType;
    return <String, dynamic>{
      'serviceId': item.id,
      'serviceType': normalizedType,
      'serviceTypeLabel': _serviceTypeLabel(normalizedType),
      'propertyId': item.propertyId,
      'propertyName': item.propertyName,
      'ownerId': item.ownerId,
      'ownerName': item.ownerName,
      'date': _fmtDate(item.date),
      'amount': item.amount,
      'isPaid': item.isPaid,
      'voucherState': item.state.name,
      'voucherStateLabel': item.state.arLabel,
      'statusLabel': item.statusLabel,
      'priority': priority?.name,
      'priorityLabel': priority == null ? null : _priorityLabel(priority),
      'linkedVoucherId': item.linkedVoucherId,
      'details': item.details,
    };
  }

  static Map<String, dynamic> _voucherRowPayload(
    VoucherReportItem item,
    ComprehensiveReportSnapshot snapshot,
  ) {
    return <String, dynamic>{
      'voucherId': item.id,
      'voucherSerialNo': item.serialNo,
      'date': _fmtDate(item.date),
      'contractId': item.contractId,
      'contractNo': snapshot.contractNumbers[item.contractId] ?? '',
      'propertyId': item.propertyId,
      'propertyName': snapshot.propertyNames[item.propertyId] ?? '',
      'tenantId': item.tenantId,
      'tenantName': snapshot.tenantNames[item.tenantId] ?? '',
      'amount': item.amount,
      'paidAmount': item.paidAmount,
      'paymentMethod': item.paymentMethod,
      'direction': item.direction.name,
      'directionLabel': item.direction.arLabel,
      'state': item.state.name,
      'stateLabel': item.state.arLabel,
      'source': item.source.name,
      'sourceLabel': item.source.arLabel,
      'operation': _voucherOperationKey(item),
      'operationLabel': _voucherOperationLabel(item),
      'note': item.note,
      'isServiceInvoice': item.isServiceInvoice,
    };
  }

  static Map<String, dynamic> _officeSummaryPayload(OfficeReportSummary office) {
    return <String, dynamic>{
      'commissionRevenue': office.commissionRevenue,
      'officeExpenses': office.officeExpenses,
      'officeWithdrawals': office.officeWithdrawals,
      'netProfit': office.netProfit,
      'currentBalance': office.currentBalance,
      'receiptVouchers': office.receiptVouchers,
      'paymentVouchers': office.paymentVouchers,
    };
  }

  static Map<String, dynamic> _ownerRowPayload(OwnerReportItem owner) {
    return <String, dynamic>{
      'ownerId': owner.ownerId,
      'ownerName': owner.ownerName,
      'previousBalance': owner.previousBalance,
      'rentCollected': owner.rentCollected,
      'officeCommissions': owner.officeCommissions,
      'ownerExpenses': owner.ownerExpenses,
      'ownerAdjustments': owner.ownerAdjustments,
      'previousTransfers': owner.previousTransfers,
      'currentBalance': owner.currentBalance,
      'readyForPayout': owner.readyForPayout,
      'linkedProperties': owner.linkedProperties,
    };
  }

  static Map<String, dynamic> _ownerPropertyPayload(
    OwnerPropertyReportItem item,
  ) {
    return <String, dynamic>{
      'propertyId': item.propertyId,
      'propertyName': item.propertyName,
      'rentCollected': item.rentCollected,
      'officeCommissions': item.officeCommissions,
      'ownerExpenses': item.ownerExpenses,
      'ownerAdjustments': item.ownerAdjustments,
      'previousTransfers': item.previousTransfers,
      'currentBalance': item.currentBalance,
      'readyForPayout': item.readyForPayout,
    };
  }

  static VoucherReportItem? _findVoucherByReferenceId(
    ComprehensiveReportSnapshot snapshot,
    String referenceId,
  ) {
    final normalized = referenceId.trim();
    if (normalized.isEmpty) return null;
    for (final voucher in snapshot.vouchers) {
      if (voucher.id == normalized || voucher.serialNo == normalized) {
        return voucher;
      }
    }
    return null;
  }

  static Map<String, dynamic> _linkedVoucherPayload(
    ComprehensiveReportSnapshot snapshot,
    String referenceId,
  ) {
    final voucher = _findVoucherByReferenceId(snapshot, referenceId);
    if (voucher == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'voucherId': voucher.id,
      'voucherSerialNo': voucher.serialNo,
      'voucherDate': _fmtDate(voucher.date),
      'contractNo': snapshot.contractNumbers[voucher.contractId] ?? '',
      'propertyName': snapshot.propertyNames[voucher.propertyId] ?? '',
      'tenantName': snapshot.tenantNames[voucher.tenantId] ?? '',
      'paymentMethod': voucher.paymentMethod,
      'direction': voucher.direction.name,
      'directionLabel': voucher.direction.arLabel,
      'source': voucher.source.name,
      'sourceLabel': voucher.source.arLabel,
      'operation': _voucherOperationKey(voucher),
      'operationLabel': _voucherOperationLabel(voucher),
      'note': voucher.note,
      'isServiceInvoice': voucher.isServiceInvoice,
    };
  }

  static Map<String, dynamic> _officeLedgerPayload(
    OfficeLedgerEntry item,
    ComprehensiveReportSnapshot snapshot,
  ) {
    final linkedVoucher = _linkedVoucherPayload(snapshot, item.referenceId);
    return <String, dynamic>{
      'id': item.id,
      'date': _fmtDate(item.date),
      'description': item.description,
      'type': item.type,
      'debit': item.debit,
      'credit': item.credit,
      'referenceId': item.referenceId,
      'balanceAfter': item.balanceAfter,
      'voucherState': item.voucherState?.name,
      'voucherStateLabel': item.voucherState?.arLabel,
      ...linkedVoucher,
    };
  }

  static Map<String, dynamic> _ownerLedgerPayload(
    OwnerLedgerEntry item,
    ComprehensiveReportSnapshot snapshot,
  ) {
    final linkedVoucher = _linkedVoucherPayload(snapshot, item.referenceId);
    return <String, dynamic>{
      'id': item.id,
      'date': _fmtDate(item.date),
      'description': item.description,
      'type': item.type,
      'debit': item.debit,
      'credit': item.credit,
      'referenceId': item.referenceId,
      'balanceAfter': item.balanceAfter,
      'voucherState': item.voucherState?.name,
      'voucherStateLabel': item.voucherState?.arLabel,
      ...linkedVoucher,
    };
  }

  static Map<String, dynamic> _ownerSettlementPreviewPayload(
    OwnerSettlementPreview preview,
  ) {
    return <String, dynamic>{
      'ownerId': preview.ownerId,
      'ownerName': preview.ownerName,
      'previousBalance': preview.previousBalance,
      'collectedRent': preview.collectedRent,
      'deductedCommission': preview.deductedCommission,
      'deductedExpenses': preview.deductedExpenses,
      'deductedAdjustments': preview.deductedAdjustments,
      'previousPayouts': preview.previousPayouts,
      'readyForPayout': preview.readyForPayout,
      'periodFrom': _fmtDate(preview.periodFrom),
      'periodTo': _fmtDate(preview.periodTo),
    };
  }

  static Map<String, dynamic> _officeSettlementPreviewPayload(
    OfficeSettlementPreview preview,
  ) {
    return <String, dynamic>{
      'netProfit': preview.netProfit,
      'previousWithdrawals': preview.previousWithdrawals,
      'currentBalance': preview.currentBalance,
      'readyForWithdrawal': preview.readyForWithdrawal,
      'periodFrom': _fmtDate(preview.periodFrom),
      'periodTo': _fmtDate(preview.periodTo),
    };
  }

  static Map<String, dynamic> _ownerBankAccountPayload(
    OwnerBankAccountRecord account,
  ) {
    return <String, dynamic>{
      'accountId': account.id,
      'ownerId': account.ownerId,
      'ownerName': account.ownerName,
      'bankName': account.bankName,
      'accountNumber': account.accountNumber,
      'iban': account.iban,
      'createdAt': _fmtDateTime(account.createdAt),
      'updatedAt': _fmtDateTime(account.updatedAt),
    };
  }

  static String _dashboardClientType(Tenant tenant) {
    final raw = _normalizeToken(tenant.clientType);
    if (raw == 'company' || raw == 'مستاجر(شركة)' || raw == 'شركة') {
      return TenantRecordService.clientTypeCompany;
    }
    if (raw == 'serviceprovider' ||
        raw == 'service_provider' ||
        raw == 'serviceprovider' ||
        raw == 'مقدمدخدمة') {
      return TenantRecordService.clientTypeServiceProvider;
    }
    if (raw == 'owner' || raw == 'مالك') {
      return 'owner';
    }
    return TenantRecordService.effectiveClientType(tenant);
  }

  static String _clientTypeLabel(String type) {
    switch (type) {
      case 'owner':
        return 'مالك';
      case TenantRecordService.clientTypeCompany:
        return 'مستأجر شركة';
      case TenantRecordService.clientTypeServiceProvider:
        return 'مقدم خدمة';
      case TenantRecordService.clientTypeTenant:
      default:
        return 'مستأجر فرد';
    }
  }

  static String? _normalizeClientTypeFilter(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty || value == 'all' || value == 'الكل') return 'all';
    if (value == 'tenant' || value == 'tenants' || value == 'مستاجر') {
      return TenantRecordService.clientTypeTenant;
    }
    if (value == 'company' || value == 'companies' || value == 'شركة') {
      return TenantRecordService.clientTypeCompany;
    }
    if (value == 'serviceprovider' ||
        value == 'service' ||
        value == 'مقدمدخدمة') {
      return TenantRecordService.clientTypeServiceProvider;
    }
    return 'all';
  }

  static String? _normalizeLinkedState(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty || value == 'all' || value == 'الكل') return null;
    if (value == 'linked' || value == 'مرتبط') return 'linked';
    if (value == 'unlinked' || value == 'غيرمرتبط') return 'unlinked';
    return null;
  }

  static String? _normalizeIdExpiryState(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty || value == 'all' || value == 'الكل') return null;
    if (value == 'expired' || value == 'منتهي') return 'expired';
    if (value == 'valid' || value == 'ساري') return 'valid';
    return null;
  }

  static String? _normalizeAvailability(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty || value == 'all' || value == 'الكل') return null;
    if (value == 'occupied' || value == 'مشغول') return 'occupied';
    if (value == 'vacant' || value == 'available' || value == 'متاح') {
      return 'vacant';
    }
    return null;
  }

  static ContractTerm? _normalizeContractTerm(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'daily':
      case 'يومي':
        return ContractTerm.daily;
      case 'monthly':
      case 'شهري':
        return ContractTerm.monthly;
      case 'quarterly':
      case 'ربعسنوي':
        return ContractTerm.quarterly;
      case 'semiannual':
      case 'نصفسنوي':
        return ContractTerm.semiAnnual;
      case 'annual':
      case 'سنوي':
        return ContractTerm.annual;
      default:
        return null;
    }
  }

  static String _contractTermLabel(ContractTerm term) {
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

  static String? _normalizeContractStatus(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty) return null;
    if (value == 'active' || value == 'نشط') return 'نشط';
    if (value == 'inactive' || value == 'غيرنشط') return 'غير نشط';
    if (value == 'ended' || value == 'منتهي') return 'منتهي';
    if (value == 'terminated' || value == 'منهى') return 'منهى';
    return null;
  }

  static String? _normalizeServiceType(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty) return null;
    if (value.contains('clean') || value.contains('نظاف')) return 'cleaning';
    if (value.contains('elevator') || value.contains('مصعد')) return 'elevator';
    if (value.contains('internet') || value.contains('انترنت')) return 'internet';
    if (value.contains('water') || value.contains('مياه') || value.contains('ماء')) {
      return 'water';
    }
    if (value.contains('electric') || value.contains('كهرب')) {
      return 'electricity';
    }
    return raw?.trim().isEmpty == true ? null : raw?.trim();
  }

  static String _serviceTypeLabel(String type) {
    switch (_normalizeServiceType(type) ?? type) {
      case 'cleaning':
        return 'نظافة';
      case 'elevator':
        return 'مصعد';
      case 'internet':
        return 'إنترنت';
      case 'water':
        return 'مياه';
      case 'electricity':
        return 'كهرباء';
      default:
        return type;
    }
  }

  static MaintenancePriority? _normalizePriority(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'low':
      case 'منخفض':
        return MaintenancePriority.low;
      case 'medium':
      case 'متوسط':
        return MaintenancePriority.medium;
      case 'high':
      case 'مرتفع':
        return MaintenancePriority.high;
      case 'urgent':
      case 'عاجل':
        return MaintenancePriority.urgent;
      default:
        return null;
    }
  }

  static String _priorityLabel(MaintenancePriority priority) {
    switch (priority) {
      case MaintenancePriority.low:
        return 'منخفض';
      case MaintenancePriority.medium:
        return 'متوسط';
      case MaintenancePriority.high:
        return 'مرتفع';
      case MaintenancePriority.urgent:
        return 'عاجل';
    }
  }

  static String? _normalizePaymentState(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty || value == 'all' || value == 'الكل') return null;
    if (value == 'paid' || value == 'مدفوع') return 'paid';
    if (value == 'unpaid' || value == 'غيرمدفوع') return 'unpaid';
    return null;
  }

  static VoucherState? _normalizeVoucherState(String? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'posted':
      case 'معتمد':
        return VoucherState.posted;
      case 'draft':
      case 'مسودة':
        return VoucherState.draft;
      case 'cancelled':
      case 'ملغي':
        return VoucherState.cancelled;
      case 'reversed':
      case 'معكوس':
        return VoucherState.reversed;
      default:
        return null;
    }
  }

  static VoucherSource? _normalizeVoucherSource(String? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'contracts':
      case 'contract':
      case 'عقود':
        return VoucherSource.contracts;
      case 'services':
      case 'service':
      case 'خدمات':
        return VoucherSource.services;
      case 'maintenance':
      case 'صيانة':
        return VoucherSource.maintenance;
      case 'ownerpayout':
      case 'تحويلللمالك':
        return VoucherSource.ownerPayout;
      case 'owneradjustment':
      case 'خصمللمالك':
      case 'تسويةللمالك':
        return VoucherSource.ownerAdjustment;
      case 'officecommission':
      case 'عمولةالمكتب':
        return VoucherSource.officeCommission;
      case 'officewithdrawal':
      case 'تحويلالمكتب':
        return VoucherSource.officeWithdrawal;
      case 'manual':
      case 'يدوي':
        return VoucherSource.manual;
      case 'other':
      case 'اخرى':
        return VoucherSource.other;
      default:
        return null;
    }
  }

  static VoucherDirection? _normalizeVoucherDirection(String? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'receipt':
      case 'receipts':
      case 'قبض':
        return VoucherDirection.receipt;
      case 'payment':
      case 'payments':
      case 'صرف':
        return VoucherDirection.payment;
      default:
        return null;
    }
  }

  static String? _normalizeVoucherOperation(String? raw) {
    final value = _normalizeToken(raw);
    if (value.isEmpty) return null;
    if (value.contains('rent') || value.contains('ايجار')) return 'rent_receipt';
    if (value.contains('officecommission') || value.contains('عمولة')) {
      return 'office_commission';
    }
    if (value.contains('officeexpense') || value.contains('مصروفمكتب')) {
      return 'office_expense';
    }
    if (value.contains('officewithdrawal') || value.contains('تحويلالمكتب')) {
      return 'office_withdrawal';
    }
    if (value.contains('ownerpayout') || value.contains('تحويلللمالك')) {
      return 'owner_payout';
    }
    if (value.contains('owneradjustment') ||
        value.contains('خصمللمالك') ||
        value.contains('تسويةللمالك')) {
      return 'owner_adjustment';
    }
    if (value.contains('elevator') || value.contains('مصعد')) {
      return 'elevator_maintenance';
    }
    if (value.contains('clean') || value.contains('نظاف')) {
      return 'building_cleaning';
    }
    if (value.contains('water') || value.contains('مياه')) {
      return 'water_services';
    }
    if (value.contains('internet') || value.contains('انترنت')) {
      return 'internet_services';
    }
    if (value.contains('electric') || value.contains('كهرب')) {
      return 'electricity_services';
    }
    if (value.contains('other') || value.contains('اخرى')) {
      return 'other';
    }
    return null;
  }

  static String _voucherOperationKey(VoucherReportItem item) {
    switch (item.source) {
      case VoucherSource.contracts:
        return 'rent_receipt';
      case VoucherSource.officeCommission:
        return 'office_commission';
      case VoucherSource.officeWithdrawal:
        return 'office_withdrawal';
      case VoucherSource.ownerPayout:
        return 'owner_payout';
      case VoucherSource.ownerAdjustment:
        return 'owner_adjustment';
      case VoucherSource.services:
      case VoucherSource.maintenance:
        return _serviceOperationKeyFromText(item.note);
      case VoucherSource.manual:
      case VoucherSource.other:
        final note = _normalizeToken(item.note);
        if (note.contains('مصروفمكتب') || note.contains('مصروفاداريللمكتب')) {
          return 'office_expense';
        }
        if (note.contains('تحويلمنرصيدالمكتب') || note.contains('سحبمنرصيدالمكتب')) {
          return 'office_withdrawal';
        }
        final serviceOperation = _serviceOperationKeyFromText(item.note);
        return serviceOperation;
    }
  }

  static String _voucherOperationLabel(VoucherReportItem item) {
    switch (_voucherOperationKey(item)) {
      case 'rent_receipt':
        return 'دفعة إيجار';
      case 'office_commission':
        return 'عمولة مكتب';
      case 'office_expense':
        return 'مصروف مكتب';
      case 'office_withdrawal':
        return 'تحويل من رصيد المكتب';
      case 'owner_payout':
        return 'تحويل للمالك';
      case 'owner_adjustment':
        return 'خصم/تسوية للمالك';
      case 'elevator_maintenance':
        return 'صيانة مصعد';
      case 'building_cleaning':
        return 'نظافة عمارة';
      case 'water_services':
        return 'خدمات مياه';
      case 'internet_services':
        return 'خدمات إنترنت';
      case 'electricity_services':
        return 'خدمات كهرباء';
      default:
        return 'عملية أخرى';
    }
  }

  static String _serviceOperationKeyFromText(String raw) {
    final note = _normalizeToken(raw);
    if (note.contains('elevator') || note.contains('مصعد')) {
      return 'elevator_maintenance';
    }
    if (note.contains('clean') || note.contains('نظاف')) {
      return 'building_cleaning';
    }
    if (note.contains('internet') || note.contains('انترنت')) {
      return 'internet_services';
    }
    if (note.contains('water') || note.contains('مياه') || note.contains('ماء')) {
      return 'water_services';
    }
    if (note.contains('electric') || note.contains('كهرب')) {
      return 'electricity_services';
    }
    return 'other';
  }

  static bool _isContractNearEnd(Contract contract) {
    if (contract.isTerminated) return false;
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(
      contract.endDate.year,
      contract.endDate.month,
      contract.endDate.day,
    );
    if (end.isBefore(today)) return false;
    return end.difference(today).inDays <= 30;
  }

  static bool _contractEndsToday(Contract contract) {
    if (contract.isTerminated) return false;
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(
      contract.endDate.year,
      contract.endDate.month,
      contract.endDate.day,
    );
    if (contract.term == ContractTerm.daily) {
      return today == end && contract.isActiveNow;
    }
    return today == end;
  }

  static PropertyType? _normalizePropertyType(Object? raw) {
    final value = _normalizeToken(raw);
    switch (value) {
      case 'apartment':
      case 'شقة':
        return PropertyType.apartment;
      case 'villa':
      case 'فيلا':
        return PropertyType.villa;
      case 'building':
      case 'عمارة':
      case 'مبنى':
        return PropertyType.building;
      case 'land':
      case 'ارض':
        return PropertyType.land;
      case 'office':
      case 'مكتب':
        return PropertyType.office;
      case 'shop':
      case 'محل':
        return PropertyType.shop;
      case 'warehouse':
      case 'مستودع':
        return PropertyType.warehouse;
      default:
        return null;
    }
  }

  static String? _stringArg(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = (args[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static bool? _boolArg(Object? raw) {
    if (raw is bool) return raw;
    final value = _normalizeToken(raw);
    if (value.isEmpty) return null;
    if (value == 'true' || value == '1' || value == 'yes' || value == 'نعم') {
      return true;
    }
    if (value == 'false' || value == '0' || value == 'no' || value == 'لا') {
      return false;
    }
    return null;
  }

  static DateTime? _dateArg(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    final raw = _stringArg(args, keys);
    if (raw == null) return null;
    try {
      return KsaTime.dateOnly(DateTime.parse(raw));
    } catch (_) {
      throw StateError('صيغة التاريخ يجب أن تكون YYYY-MM-DD.');
    }
  }

  static int _limitArg(
    Map<String, dynamic> args, {
    List<String> keys = const <String>['limit'],
    required int defaultValue,
  }) {
    for (final key in keys) {
      final raw = args[key];
      if (raw == null) continue;
      final parsed = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (parsed == null) continue;
      if (parsed < 1) return 1;
      if (parsed > 50) return 50;
      return parsed;
    }
    return defaultValue;
  }

  static String _normalizeToken(Object? raw) {
    return (raw ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[\s_\-]+'), '');
  }

  static String? _fmtDate(DateTime? value) {
    if (value == null) return null;
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _fmtDateTime(DateTime value) {
    return '${_fmtDate(value)} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class _PropertyAggregation {
  final String propertyId;
  final String propertyName;
  String ownerId;
  String ownerName;
  final PropertyType type;
  bool isOccupied;
  int activeContracts = 0;
  int endedContracts = 0;
  int receivedPayments = 0;
  int latePayments = 0;
  int upcomingPayments = 0;
  int linkedVouchers = 0;
  double revenues = 0;
  double expenses = 0;
  double serviceExpenses = 0;
  double overdueAmount = 0;
  double net = 0;

  _PropertyAggregation({
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
    required this.ownerName,
    required this.type,
    required this.isOccupied,
  });

  void add(PropertyReportItem item) {
    if (ownerId.trim().isEmpty && item.ownerId.trim().isNotEmpty) {
      ownerId = item.ownerId;
    }
    if (ownerName.trim().isEmpty && item.ownerName.trim().isNotEmpty) {
      ownerName = item.ownerName;
    }
    isOccupied = isOccupied || item.isOccupied;
    activeContracts += item.activeContracts;
    endedContracts += item.endedContracts;
    receivedPayments += item.receivedPayments;
    latePayments += item.latePayments;
    upcomingPayments += item.upcomingPayments;
    linkedVouchers += item.linkedVouchers;
    revenues += item.revenues;
    expenses += item.expenses;
    serviceExpenses += item.serviceExpenses;
    overdueAmount += item.overdueAmount;
    net += item.net;
  }

  PropertyReportItem toItem() {
    return PropertyReportItem(
      propertyId: propertyId,
      propertyName: propertyName,
      ownerId: ownerId,
      ownerName: ownerName,
      type: type,
      isOccupied: isOccupied,
      activeContracts: activeContracts,
      endedContracts: endedContracts,
      receivedPayments: receivedPayments,
      latePayments: latePayments,
      upcomingPayments: upcomingPayments,
      linkedVouchers: linkedVouchers,
      revenues: revenues,
      expenses: expenses,
      serviceExpenses: serviceExpenses,
      overdueAmount: overdueAmount,
      net: net,
    );
  }
}

class _ReportsContext {
  final ComprehensiveReportSnapshot snapshot;
  final ComprehensiveReportFilters filters;
  final List<Property> allProperties;
  final List<Tenant> allTenants;
  final List<Contract> allContracts;
  final List<MaintenanceRequest> allMaintenance;
  final Property? property;
  final _ResolvedOwnerRef? owner;
  final Contract? contract;
  final Set<String> propertyScopeIds;

  const _ReportsContext({
    required this.snapshot,
    required this.filters,
    required this.allProperties,
    required this.allTenants,
    required this.allContracts,
    required this.allMaintenance,
    required this.property,
    required this.owner,
    required this.contract,
    required this.propertyScopeIds,
  });
}

class _ResolvedOwnerRef {
  final String id;
  final String name;

  const _ResolvedOwnerRef({
    required this.id,
    required this.name,
  });
}
