import 'dart:convert';

import 'package:hive/hive.dart';

import '../../../data/constants/boxes.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/user_scope.dart';
import '../../../models/property.dart';
import '../../../models/tenant.dart';
import '../../../ui/contracts_screen.dart'
    show Contract, PaymentCycle, ContractTerm;
import '../../../ui/invoices_screen.dart' show Invoice;
import '../../../ui/maintenance_screen.dart' show MaintenanceRequest;
import '../../../utils/ksa_time.dart';
import '../ai_chat_executor.dart';
import 'ai_context_provider.dart';
import 'ai_chat_types.dart';

class AiToolExecutor {
  final AiChatExecutor legacyExecutor;

  const AiToolExecutor({
    required this.legacyExecutor,
  });

  Future<Map<String, dynamic>?> preflight({
    required AiToolDefinition definition,
    required String requestedToolName,
    required Map<String, dynamic> arguments,
    required List<String> allowedPermissions,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    if (!definition.supported) {
      return _unsupported('هذه العملية غير مدعومة بعد في الدردشة.');
    }
    switch (definition.name) {
      case 'properties.create': return _preflightPropertyCreate(arguments);
      case 'properties.update': return _preflightPropertyUpdate(arguments);
      case 'tenants.create': return _preflightTenantCreate(arguments);
      case 'tenants.update': return _preflightTenantUpdate(arguments);
      case 'contracts.create': return _preflightCreateContract(arguments);
      case 'contracts.update': return _preflightUpdateContract(arguments);
      case 'contracts.terminate': return _preflightTerminateContract(arguments);
      case 'invoices.create': return _preflightCreateInvoice(arguments);
      case 'payments.create': return _preflightRecordPayment(arguments);
      case 'maintenance.create_ticket': return _preflightCreateMaintenance(arguments);
      case 'maintenance.update_status': return _preflightUpdateMaintenanceStatus(arguments);
      case 'periodic_services.create': return _preflightPeriodicService(arguments, isCreate: true);
      case 'periodic_services.update': return _preflightPeriodicService(arguments, isCreate: false);
      default: return null;
    }
  }

  Future<Map<String, dynamic>> execute({
    required AiToolDefinition definition,
    required String requestedToolName,
    required Map<String, dynamic> arguments,
    required List<String> allowedPermissions,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    switch (definition.name) {
      case 'app.help':
        return _ok(
          message: AiContextProvider.capabilitiesSummary(),
          data: <String, dynamic>{
            'answer': AiContextProvider.capabilitiesSummary(),
          },
        );
      case 'app.module_help':
        return _ok(
          message: AiContextProvider.moduleHelp(
            (arguments['module'] ?? '').toString(),
          ),
          data: <String, dynamic>{
            'answer': AiContextProvider.moduleHelp(
              (arguments['module'] ?? '').toString(),
            ),
          },
        );
      case 'app.capabilities':
        return _ok(
          message: 'القدرات المتاحة لهذا الحساب: ${allowedPermissions.join('، ')}',
          data: <String, dynamic>{
            'permissions': allowedPermissions,
          },
        );
      case 'app.explain_workflow':
        return _ok(
          message: _workflowHelp((arguments['workflow'] ?? '').toString()),
          data: <String, dynamic>{
            'answer': _workflowHelp((arguments['workflow'] ?? '').toString()),
          },
        );
      case 'properties.search':
        return _searchProperties(arguments);
      case 'properties.get':
        return _getProperty(arguments);
      case 'properties.create':
        return _executeLegacy(
          'add_property',
          <String, dynamic>{
            'name': arguments['name'],
            'type': arguments['type'],
            'address': arguments['address'],
            'rentalMode': arguments['rentalMode'],
            'totalUnits': arguments['totalUnits'],
            'description': arguments['notes'],
          },
        );
      case 'properties.update':
        return _executeLegacy(
          'edit_property',
          <String, dynamic>{
            'query': arguments['query'],
            'name': arguments['name'],
            'address': arguments['address'],
            'description': arguments['notes'],
          },
        );
      case 'units.search':
        return _searchUnits(arguments);
      case 'units.available':
        return _availableUnits(arguments);
      case 'tenants.search':
        return _searchTenants(arguments);
      case 'tenants.get':
        return _getTenant(arguments);
      case 'tenants.create':
        return _executeLegacy(
          'add_client_record',
          <String, dynamic>{
            'clientType': arguments['clientType'],
            'fullName': arguments['fullName'],
            'phone': arguments['phone'],
            'nationalId': arguments['nationalId'],
            'email': arguments['email'],
            'notes': arguments['notes'],
            'attachmentPaths': arguments['attachmentPaths'],
          },
        );
      case 'tenants.update':
        return _executeLegacy(
          'edit_tenant',
          <String, dynamic>{
            'query': arguments['query'],
            'phone': arguments['phone'],
            'email': arguments['email'],
            'notes': arguments['notes'],
          },
        );
      case 'contracts.search':
        return _searchContracts(arguments);
      case 'contracts.get':
        return _getContract(arguments);
      case 'contracts.create':
        return _createContract(arguments);
      case 'contracts.update':
        return _updateContract(arguments);
      case 'contracts.terminate':
        return _terminateContract(arguments);
      case 'contracts.expiring':
        return _contractsExpiring(arguments);
      case 'invoices.search':
        return _searchInvoices(arguments);
      case 'invoices.get':
        return _getInvoice(arguments);
      case 'invoices.create':
        return _createInvoice(arguments);
      case 'payments.search':
        return _searchPayments(arguments);
      case 'payments.get':
        return _unsupported('هذه النسخة لا تدعم قراءة سندات السداد كسجل مستقل بعد.');
      case 'payments.create':
        return _recordPayment(arguments);
      case 'maintenance.search':
        return _searchMaintenance(arguments);
      case 'maintenance.get':
        return _getMaintenance(arguments);
      case 'maintenance.create_ticket':
        return _createMaintenance(arguments);
      case 'maintenance.update_status':
        return _executeLegacy(
          'update_maintenance_status',
          <String, dynamic>{
            'query': arguments['query'],
            'status': arguments['status'],
            'notes': arguments['notes'],
          },
        );
      case 'reports.arrears_summary':
        return _reportArrears(arguments);
      case 'reports.owner_statement':
        return _unsupported('كشف المالك عبر الدردشة غير مدعوم بالكامل في هذه النسخة بعد.');
      case 'reports.tenant_statement':
        return _reportTenantStatement(arguments);
      case 'reports.occupancy_rate':
        return _reportOccupancy(arguments);
      case 'reports.rent_collection':
        return _reportRentCollection(arguments);
      case 'reports.income_expense':
        return _reportIncomeExpense(arguments);
      case 'reports.contracts_expiring':
        return _contractsExpiring(arguments);
      case 'reports.vacant_units':
        return _availableUnits(arguments, asReport: true);
      case 'reports.maintenance_summary':
        return _reportMaintenance(arguments);
      case 'periodic_services.search':
        return _periodicServicesSearch(arguments);
      case 'periodic_services.create':
        return _periodicServicesMutate(arguments, isCreate: true);
      case 'periodic_services.update':
        return _periodicServicesMutate(arguments, isCreate: false);
      case 'app.open_screen':
        return _openScreen(requestedToolName, arguments);
      case 'notifications.get':
        return _executeLegacy(
          'get_notifications',
          <String, dynamic>{
            'kind': arguments['kind'],
            'includeDismissed': arguments['includeDismissed'],
          },
        );
      case 'notifications.open_target':
        return _executeLegacy(
          'open_notification_target',
          <String, dynamic>{'notificationRef': arguments['notificationRef']},
        );
      case 'notifications.mark_read':
        return _executeLegacy(
          'mark_notification_read',
          <String, dynamic>{'notificationRef': arguments['notificationRef']},
        );
      default:
        return _unsupported('هذه العملية غير مسجلة ضمن منفذ الأدوات الآمن.');
    }
  }

  Future<Map<String, dynamic>> _executeLegacy(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final raw = await legacyExecutor.executeCached(toolName, arguments);
    return _decodeLegacy(raw);
  }

  Map<String, dynamic> _decodeLegacy(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map.containsKey('error')) {
          return _err(
            (map['error'] ?? 'تعذر تنفيذ العملية.').toString(),
            code: 'legacy_error',
            data: map,
          );
        }
        if (map['success'] == true) {
          return _ok(
            message: (map['message'] ?? 'نجحت العملية.').toString(),
            data: map,
          );
        }
        if (map.containsKey('missingFields')) {
          return <String, dynamic>{
            'status': 'missing_fields',
            'message': (map['error'] ?? map['message'] ?? 'توجد حقول ناقصة.')
                .toString(),
            'missing_fields': map['missingFields'],
            'payload': map,
          };
        }
        return _ok(
          message: (map['message'] ?? '').toString(),
          data: map,
        );
      }
    } catch (_) {}
    return _ok(message: raw, data: <String, dynamic>{'raw': raw});
  }

  Map<String, dynamic> _searchProperties(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final propertyType = _text(arguments, 'property_type');
    final includeArchived = arguments['include_archived'] == true;
    final items = _properties().where((property) {
      if (!includeArchived && property.isArchived) return false;
      if (propertyType.isNotEmpty && property.type.name != propertyType) {
        return false;
      }
      if (query.isEmpty) return true;
      return property.name.toLowerCase().contains(query.toLowerCase()) ||
          property.address.toLowerCase().contains(query.toLowerCase());
    }).map(_propertyPayload).toList(growable: false);

    return _ok(
      message: items.isEmpty
          ? 'لا توجد عقارات مطابقة.'
          : 'تم العثور على ${items.length} عقار/وحدة.',
      data: <String, dynamic>{
        'items': items,
      },
    );
  }

  Map<String, dynamic> _getProperty(Map<String, dynamic> arguments) {
    final propertyId = _text(arguments, 'property_id');
    final query = _text(arguments, 'query');
    final match = propertyId.isNotEmpty
        ? _properties().where((item) => item.id == propertyId).toList()
        : _matchingProperties(query);
    if (match.isEmpty) {
      return _err('لم يتم العثور على العقار المطلوب.');
    }
    if (match.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقار مطابق. اختر العقار الصحيح.',
        match
            .map((item) => AiDisambiguationCandidate(
                  id: item.id,
                  label: item.name,
                  subtitle: item.address,
                  entityType: 'property',
                ).toJson())
            .toList(growable: false),
      );
    }
    final property = match.first;
    return _ok(
      message: 'تم جلب تفاصيل العقار "${property.name}".',
      data: <String, dynamic>{
        'record': _propertyPayload(property),
      },
    );
  }

  Map<String, dynamic> _searchUnits(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final buildingQuery = _text(arguments, 'building_query');
    final items = _properties().where((property) {
      if ((property.parentBuildingId ?? '').trim().isEmpty) return false;
      if (buildingQuery.isNotEmpty) {
        final building = _propertyById(property.parentBuildingId ?? '');
        if (building == null ||
            !building.name.toLowerCase().contains(buildingQuery.toLowerCase())) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      return property.name.toLowerCase().contains(query.toLowerCase());
    }).map((item) {
      final building = _propertyById(item.parentBuildingId ?? '');
      return <String, dynamic>{
        ..._propertyPayload(item),
        'building_name': building?.name,
        'available': !_hasActiveContract(item.id),
      };
    }).toList(growable: false);

    return _ok(
      message: items.isEmpty ? 'لا توجد وحدات مطابقة.' : 'تم جلب الوحدات المطابقة.',
      data: <String, dynamic>{'items': items},
    );
  }

  Map<String, dynamic> _availableUnits(
    Map<String, dynamic> arguments, {
    bool asReport = false,
  }) {
    final buildingQuery = _text(arguments, 'building_query');
    final propertyQuery = _text(arguments, 'property_query');
    final rows = _properties().where((property) {
      if ((property.parentBuildingId ?? '').trim().isEmpty) return false;
      if (_hasActiveContract(property.id)) return false;
      if (buildingQuery.isNotEmpty) {
        final building = _propertyById(property.parentBuildingId ?? '');
        if (building == null ||
            !building.name.toLowerCase().contains(buildingQuery.toLowerCase())) {
          return false;
        }
      }
      if (propertyQuery.isNotEmpty &&
          !property.name.toLowerCase().contains(propertyQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).map((unit) {
      final building = _propertyById(unit.parentBuildingId ?? '');
      return <String, dynamic>{
        'unit_id': unit.id,
        'unit_name': unit.name,
        'building_name': building?.name,
        'type': unit.type.name,
      };
    }).toList(growable: false);

    if (asReport) {
      return _ok(
        message: rows.isEmpty ? 'لا توجد وحدات شاغرة.' : 'تم إعداد تقرير الوحدات الشاغرة.',
        data: <String, dynamic>{
          'report_type': 'vacant_units',
          'period': null,
          'currency': 'SAR',
          'filters': <String, dynamic>{
            'building_query': buildingQuery,
            'property_query': propertyQuery,
          },
          'totals': <String, dynamic>{
            'total_vacant_units': rows.length,
          },
          'rows': rows,
          'generated_at': DateTime.now().toIso8601String(),
        },
      );
    }

    return _ok(
      message: rows.isEmpty ? 'لا توجد وحدات شاغرة.' : 'تم جلب الوحدات الشاغرة.',
      data: <String, dynamic>{'items': rows},
    );
  }

  Map<String, dynamic> _searchTenants(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final clientType = _text(arguments, 'clientType');
    final items = _tenants().where((tenant) {
      if (clientType.isNotEmpty &&
          tenant.clientType.toLowerCase() != clientType.toLowerCase()) {
        return false;
      }
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return tenant.fullName.toLowerCase().contains(q) ||
          (tenant.companyName ?? '').toLowerCase().contains(q) ||
          tenant.nationalId.contains(query) ||
          tenant.phone.contains(query);
    }).map(_tenantPayload).toList(growable: false);
    return _ok(
      message: items.isEmpty ? 'لا توجد نتائج مطابقة.' : 'تم العثور على ${items.length} عميل/مستأجر.',
      data: <String, dynamic>{'items': items},
    );
  }

  Map<String, dynamic> _getTenant(Map<String, dynamic> arguments) {
    final tenantId = _text(arguments, 'tenant_id');
    final query = _text(arguments, 'query');
    final matches = tenantId.isNotEmpty
        ? _tenants().where((tenant) => tenant.id == tenantId).toList()
        : _matchingTenants(query);
    if (matches.isEmpty) {
      return _err('لم يتم العثور على العميل المطلوب.');
    }
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عميل مطابق. اختر العميل الصحيح.',
        matches
            .map((tenant) => AiDisambiguationCandidate(
                  id: tenant.id,
                  label: tenant.fullName,
                  subtitle: tenant.phone,
                  entityType: 'tenant',
                ).toJson())
            .toList(growable: false),
      );
    }
    return _ok(
      message: 'تم جلب تفاصيل العميل "${matches.first.fullName}".',
      data: <String, dynamic>{'record': _tenantPayload(matches.first)},
    );
  }

  Map<String, dynamic> _searchContracts(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final status = _text(arguments, 'status');
    final items = _contracts().where((contract) {
      if (status.isNotEmpty) {
        final contractStatus = _contractStatus(contract);
        if (contractStatus != status) return false;
      }
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return (contract.serialNo ?? '').toLowerCase().contains(q) ||
          _snapshotString(contract.tenantSnapshot, 'fullName')
              .toLowerCase()
              .contains(q) ||
          _snapshotString(contract.propertySnapshot, 'name')
              .toLowerCase()
              .contains(q);
    }).map(_contractPayload).toList(growable: false);
    return _ok(
      message: items.isEmpty ? 'لا توجد عقود مطابقة.' : 'تم العثور على ${items.length} عقد/عقود.',
      data: <String, dynamic>{'items': items},
    );
  }

  Map<String, dynamic> _getContract(Map<String, dynamic> arguments) {
    final contractId = _text(arguments, 'contract_id');
    final query = _text(arguments, 'query');
    final matches = contractId.isNotEmpty
        ? _contracts().where((contract) => contract.id == contractId).toList()
        : _matchingContracts(query);
    if (matches.isEmpty) {
      return _err('لم يتم العثور على العقد المطلوب.');
    }
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقد مطابق. اختر العقد الصحيح.',
        matches
            .map((contract) => AiDisambiguationCandidate(
                  id: contract.id,
                  label: contract.serialNo ?? contract.id,
                  subtitle:
                      '${_snapshotString(contract.tenantSnapshot, 'fullName')} - ${_snapshotString(contract.propertySnapshot, 'name')}',
                  entityType: 'contract',
                ).toJson())
            .toList(growable: false),
      );
    }
    final contract = matches.first;
    final invoices = _invoices()
        .where((invoice) => invoice.contractId == contract.id)
        .toList(growable: false);
    final unpaid = invoices.where((invoice) => !invoice.isPaid).toList(growable: false);
    final overdue = unpaid.where((invoice) => invoice.isOverdue).toList(growable: false);
    final nextUnpaid = unpaid.isEmpty
        ? null
        : (unpaid.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate))).first;
    return _ok(
      message: 'تم جلب تفاصيل العقد ${contract.serialNo ?? ''}.',
      data: <String, dynamic>{
        'record': <String, dynamic>{
          ..._contractPayload(contract),
          'invoices_count': invoices.length,
          'overdue_invoices_count': overdue.length,
          'current_invoice': nextUnpaid == null ? null : _invoicePayload(nextUnpaid),
        },
      },
    );
  }

  Future<Map<String, dynamic>> _createContract(
    Map<String, dynamic> arguments,
  ) async {
    final propertyResolution =
        _resolveSingleProperty(arguments['property_id'], arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;

    final tenantResolution =
        _resolveSingleTenant(arguments['tenant_id'], arguments['tenant_query']);
    if (tenantResolution['status'] == 'disambiguation') return tenantResolution;
    if (tenantResolution['status'] == 'error') return tenantResolution;

    final property = propertyResolution['record'] as Property?;
    final tenant = tenantResolution['record'] as Tenant?;

    final missing = <Map<String, dynamic>>[];
    if (property == null) {
      missing.add(_missingField('property_query', 'العقار أو الوحدة', 'حدد العقار أو الوحدة أولًا.'));
    }
    if (tenant == null) {
      missing.add(_missingField('tenant_query', 'المستأجر', 'حدد المستأجر أولًا.'));
    }
    if (_text(arguments, 'startDate').isEmpty) {
      missing.add(_missingField('startDate', 'تاريخ البداية', 'حدد تاريخ بداية العقد.'));
    }
    if (_text(arguments, 'endDate').isEmpty) {
      missing.add(_missingField('endDate', 'تاريخ النهاية', 'حدد تاريخ نهاية العقد.'));
    }
    if (arguments['rentAmount'] == null) {
      missing.add(_missingField('rentAmount', 'قيمة الإيجار', 'حدد قيمة الإيجار.'));
    }
    if (_text(arguments, 'paymentCycle').isEmpty) {
      missing.add(_missingField('paymentCycle', 'دورة السداد', 'حدد دورة السداد.'));
    }
    if (missing.isNotEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'أحتاج بعض الحقول قبل تجهيز العقد.',
        'missing_fields': missing,
      };
    }

    return _executeLegacy(
      'create_contract',
      <String, dynamic>{
        'propertyName': property!.name,
        'tenantName': tenant!.fullName,
        'startDate': arguments['startDate'],
        'endDate': arguments['endDate'],
        'rentAmount': arguments['rentAmount'],
        'paymentCycle': arguments['paymentCycle'],
        'notes': arguments['notes'],
        'attachmentPaths': arguments['attachmentPaths'],
      },
    );
  }

  Future<Map<String, dynamic>> _updateContract(
    Map<String, dynamic> arguments,
  ) async {
    final query = _text(arguments, 'query');
    if (query.isEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'حدد العقد المراد تعديله أولًا.',
        'missing_fields': <Map<String, dynamic>>[
          _missingField('query', 'العقد', 'حدد رقم العقد أو مرجعه.'),
        ],
      };
    }
    final matches = _matchingContracts(query);
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقد مطابق. اختر العقد الصحيح.',
        matches
            .map((contract) => AiDisambiguationCandidate(
                  id: contract.id,
                  label: contract.serialNo ?? contract.id,
                  subtitle: _snapshotString(contract.tenantSnapshot, 'fullName'),
                  entityType: 'contract',
                ).toJson())
            .toList(growable: false),
      );
    }
    if (matches.isEmpty) {
      return _err('لم يتم العثور على العقد المطلوب.');
    }
    return _executeLegacy(
      'edit_contract',
      <String, dynamic>{
        'contractSerialNo': matches.first.serialNo,
        'endDate': arguments['endDate'],
        'rentAmount': arguments['rentAmount'],
        'notes': arguments['notes'],
      },
    );
  }

  Future<Map<String, dynamic>> _terminateContract(
    Map<String, dynamic> arguments,
  ) async {
    final query = _text(arguments, 'query');
    if (query.isEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'حدد العقد المراد إنهاؤه أولًا.',
        'missing_fields': <Map<String, dynamic>>[
          _missingField('query', 'العقد', 'حدد رقم العقد أو مرجعه.'),
        ],
      };
    }
    final matches = _matchingContracts(query);
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقد مطابق. اختر العقد الصحيح.',
        matches
            .map((contract) => AiDisambiguationCandidate(
                  id: contract.id,
                  label: contract.serialNo ?? contract.id,
                  subtitle: _snapshotString(contract.tenantSnapshot, 'fullName'),
                  entityType: 'contract',
                ).toJson())
            .toList(growable: false),
      );
    }
    if (matches.isEmpty) {
      return _err('لم يتم العثور على العقد المطلوب.');
    }
    return _executeLegacy(
      'terminate_contract',
      <String, dynamic>{
        'contractSerialNo': matches.first.serialNo,
      },
    );
  }

  Map<String, dynamic> _contractsExpiring(Map<String, dynamic> arguments) {
    final days = (arguments['days'] as num?)?.toInt() ?? 30;
    final today = KsaTime.today();
    final rows = _contracts().where((contract) {
      if (contract.isTerminated) return false;
      final end = KsaTime.dateOnly(contract.endDate);
      final delta = end.difference(today).inDays;
      return delta >= 0 && delta <= days;
    }).map((contract) {
      return <String, dynamic>{
        ..._contractPayload(contract),
        'days_until_end':
            KsaTime.dateOnly(contract.endDate).difference(today).inDays,
      };
    }).toList(growable: false)
      ..sort((a, b) => (a['days_until_end'] as int).compareTo(b['days_until_end'] as int));

    return _ok(
      message: rows.isEmpty
          ? 'لا توجد عقود قريبة من الانتهاء.'
          : 'تم إعداد قائمة العقود القريبة من الانتهاء.',
      data: <String, dynamic>{
        'report_type': 'contracts_expiring',
        'period': null,
        'currency': 'SAR',
        'filters': <String, dynamic>{'days': days},
        'totals': <String, dynamic>{'total_contracts': rows.length},
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _searchInvoices(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final status = _text(arguments, 'status');
    final rows = _invoices().where((invoice) {
      if (status == 'paid' && !invoice.isPaid) return false;
      if (status == 'unpaid' && invoice.isPaid) return false;
      if (status == 'overdue' && !invoice.isOverdue) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      final contract = _contractById(invoice.contractId);
      return (invoice.serialNo ?? '').toLowerCase().contains(q) ||
          (contract?.serialNo ?? '').toLowerCase().contains(q) ||
          _snapshotString(contract?.tenantSnapshot, 'fullName')
              .toLowerCase()
              .contains(q);
    }).map(_invoicePayload).toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد فواتير مطابقة.' : 'تم جلب الفواتير المطابقة.',
      data: <String, dynamic>{'items': rows},
    );
  }

  Map<String, dynamic> _getInvoice(Map<String, dynamic> arguments) {
    final invoiceId = _text(arguments, 'invoice_id');
    final serial = _text(arguments, 'invoiceSerialNo');
    final matches = invoiceId.isNotEmpty
        ? _invoices().where((invoice) => invoice.id == invoiceId).toList()
        : _invoices().where((invoice) => (invoice.serialNo ?? '') == serial).toList();
    if (matches.isEmpty) {
      return _err('لم يتم العثور على الفاتورة المطلوبة.');
    }
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من فاتورة مطابقة. اختر الفاتورة الصحيحة.',
        matches
            .map((invoice) => AiDisambiguationCandidate(
                  id: invoice.id,
                  label: invoice.serialNo ?? invoice.id,
                  subtitle: _contractById(invoice.contractId)?.serialNo ?? '',
                  entityType: 'invoice',
                ).toJson())
            .toList(growable: false),
      );
    }
    return _ok(
      message: 'تم جلب تفاصيل الفاتورة ${matches.first.serialNo ?? ''}.',
      data: <String, dynamic>{'record': _invoicePayload(matches.first)},
    );
  }

  Future<Map<String, dynamic>> _createInvoice(
    Map<String, dynamic> arguments,
  ) async {
    final contractResolution = _resolveSingleContract(
      arguments['contract_id'],
      arguments['query'],
    );
    if (contractResolution['status'] == 'disambiguation') {
      return contractResolution;
    }
    if (contractResolution['status'] == 'error') return contractResolution;
    final contract = contractResolution['record'] as Contract?;
    final missing = <Map<String, dynamic>>[];
    if (contract == null) {
      missing.add(_missingField('query', 'العقد', 'حدد العقد أولًا.'));
    }
    if (arguments['amount'] == null) {
      missing.add(_missingField('amount', 'المبلغ', 'حدد مبلغ الفاتورة.'));
    }
    if (_text(arguments, 'dueDate').isEmpty) {
      missing.add(_missingField('dueDate', 'تاريخ الاستحقاق', 'حدد تاريخ الاستحقاق.'));
    }
    if (missing.isNotEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'أحتاج بعض الحقول قبل إنشاء الفاتورة.',
        'missing_fields': missing,
      };
    }
    return _executeLegacy(
      'create_invoice',
      <String, dynamic>{
        'contractSerialNo': contract!.serialNo,
        'amount': arguments['amount'],
        'dueDate': arguments['dueDate'],
        'note': arguments['notes'],
      },
    );
  }

  Map<String, dynamic> _searchPayments(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final rows = _invoices()
        .where((invoice) => invoice.paidAmount > 0)
        .where((invoice) {
          if (query.isEmpty) return true;
          final q = query.toLowerCase();
          final contract = _contractById(invoice.contractId);
          return (invoice.serialNo ?? '').toLowerCase().contains(q) ||
              (contract?.serialNo ?? '').toLowerCase().contains(q) ||
              _snapshotString(contract?.tenantSnapshot, 'fullName')
                  .toLowerCase()
                  .contains(q);
        })
        .map((invoice) => <String, dynamic>{
              'invoice_id': invoice.id,
              'invoice_serial_no': invoice.serialNo,
              'paid_amount': invoice.paidAmount,
              'invoice_amount': invoice.amount,
              'remaining_amount': invoice.remaining,
            })
        .toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد عمليات سداد مطابقة.' : 'تم جلب عمليات السداد المتاحة.',
      data: <String, dynamic>{'items': rows},
    );
  }

  Future<Map<String, dynamic>> _recordPayment(
    Map<String, dynamic> arguments,
  ) async {
    final invoiceResolution =
        _resolveSingleInvoice(arguments['invoice_id'], arguments['invoiceSerialNo'], arguments['query']);
    if (invoiceResolution['status'] == 'disambiguation') return invoiceResolution;
    if (invoiceResolution['status'] == 'error') return invoiceResolution;
    final invoice = invoiceResolution['record'] as Invoice?;
    final missing = <Map<String, dynamic>>[];
    if (invoice == null) {
      missing.add(_missingField('query', 'الفاتورة', 'حدد الفاتورة أو العقد أولًا.'));
    }
    final amount = (arguments['amount'] as num?)?.toDouble();
    if (amount == null) {
      missing.add(_missingField('amount', 'المبلغ', 'حدد مبلغ الدفعة.'));
    }
    if (_text(arguments, 'paymentMethod').isEmpty) {
      missing.add(_missingField('paymentMethod', 'طريقة الدفع', 'حدد طريقة الدفع.'));
    }
    if (missing.isNotEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'أحتاج بعض الحقول قبل تسجيل الدفعة.',
        'missing_fields': missing,
      };
    }
    if (amount! <= 0) return _err('مبلغ الدفعة يجب أن يكون أكبر من صفر.');
    if (invoice!.isCanceled) return _err('لا يمكن تسجيل دفعة على فاتورة ملغاة.');
    if (amount - invoice.remaining > 0.01) {
      return _err('مبلغ الدفعة أكبر من المبلغ المتبقي على الفاتورة.');
    }
    final beforePaidAmount = invoice.paidAmount;
    final result = await _executeLegacy(
      'record_payment',
      <String, dynamic>{
        'invoiceSerialNo': invoice.serialNo,
        'amount': amount,
        'paymentMethod': arguments['paymentMethod'],
      },
    );
    final payload = Map<String, dynamic>.from(
      result['payload'] as Map? ?? const <String, dynamic>{},
    );
    result['payload'] = <String, dynamic>{
      ...payload,
      'invoice_serial_no': invoice.serialNo,
      'invoice_id': invoice.id,
      'before_paid_amount': beforePaidAmount,
      'expected_payment_amount': amount,
      'payment_method': arguments['paymentMethod'],
    };
    return result;
  }

  Map<String, dynamic> _searchMaintenance(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    final status = _text(arguments, 'status');
    final rows = _maintenance().where((request) {
      if (status.isNotEmpty && request.status.name != status) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      final property = _propertyById(request.propertyId);
      return request.title.toLowerCase().contains(q) ||
          (request.serialNo ?? '').toLowerCase().contains(q) ||
          (property?.name ?? '').toLowerCase().contains(q);
    }).map(_maintenancePayload).toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد طلبات صيانة مطابقة.' : 'تم جلب طلبات الصيانة المطابقة.',
      data: <String, dynamic>{'items': rows},
    );
  }

  Map<String, dynamic> _getMaintenance(Map<String, dynamic> arguments) {
    final requestId = _text(arguments, 'request_id');
    final query = _text(arguments, 'query');
    final matches = requestId.isNotEmpty
        ? _maintenance().where((item) => item.id == requestId).toList()
        : _maintenance().where((item) {
            final q = query.toLowerCase();
            return item.title.toLowerCase().contains(q) ||
                (item.serialNo ?? '').toLowerCase().contains(q);
          }).toList();
    if (matches.isEmpty) {
      return _err('لم يتم العثور على طلب الصيانة المطلوب.');
    }
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من طلب صيانة مطابق. اختر الطلب الصحيح.',
        matches
            .map((request) => AiDisambiguationCandidate(
                  id: request.id,
                  label: request.serialNo ?? request.id,
                  subtitle: request.title,
                  entityType: 'maintenance',
                ).toJson())
            .toList(growable: false),
      );
    }
    return _ok(
      message: 'تم جلب تفاصيل طلب الصيانة ${matches.first.serialNo ?? ''}.',
      data: <String, dynamic>{'record': _maintenancePayload(matches.first)},
    );
  }

  Future<Map<String, dynamic>> _createMaintenance(
    Map<String, dynamic> arguments,
  ) async {
    final propertyResolution =
        _resolveSingleProperty(arguments['property_id'], arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final property = propertyResolution['record'] as Property?;
    final missing = <Map<String, dynamic>>[];
    if (property == null) {
      missing.add(_missingField('property_query', 'العقار', 'حدد العقار أو الوحدة أولًا.'));
    }
    if (_text(arguments, 'title').isEmpty) {
      missing.add(_missingField('title', 'العنوان', 'حدد عنوان طلب الصيانة.'));
    }
    if (_text(arguments, 'description').isEmpty) {
      missing.add(_missingField('description', 'الوصف', 'اكتب وصف المشكلة أو الطلب.'));
    }
    if (missing.isNotEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'أحتاج بعض الحقول قبل إنشاء طلب الصيانة.',
        'missing_fields': missing,
      };
    }
    return _executeLegacy(
      'create_maintenance_request',
      <String, dynamic>{
        'propertyName': property!.name,
        'title': arguments['title'],
        'description': arguments['description'],
        'priority': arguments['priority'],
        'provider': arguments['provider'],
        'attachmentPaths': arguments['attachmentPaths'],
      },
    );
  }

  Map<String, dynamic> _reportArrears(Map<String, dynamic> arguments) {
    final period = _resolvePeriod(arguments['from_date'], arguments['to_date']);
    final propertyQuery = _text(arguments, 'property_query');
    final propertyMatches = propertyQuery.isEmpty ? <Property>[] : _matchingProperties(propertyQuery);
    if (propertyQuery.isNotEmpty && propertyMatches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقار مطابق للتقرير. اختر العقار الصحيح.',
        propertyMatches
            .map((item) => AiDisambiguationCandidate(
                  id: item.id,
                  label: item.name,
                  subtitle: item.address,
                  entityType: 'property',
                ).toJson())
            .toList(growable: false),
      );
    }
    final propertyId =
        propertyMatches.length == 1 ? propertyMatches.first.id : '';
    final rows = _invoices().where((invoice) {
      if (!invoice.isOverdue) return false;
      if (propertyId.isNotEmpty && invoice.propertyId != propertyId) return false;
      final dueDate = KsaTime.dateOnly(invoice.dueDate);
      return !dueDate.isBefore(period.$1) && !dueDate.isAfter(period.$2);
    }).map((invoice) {
      final contract = _contractById(invoice.contractId);
      return <String, dynamic>{
        'invoice_serial_no': invoice.serialNo,
        'contract_serial_no': contract?.serialNo,
        'tenant_name': _snapshotString(contract?.tenantSnapshot, 'fullName'),
        'property_name': _snapshotString(contract?.propertySnapshot, 'name'),
        'due_date': _ymd(invoice.dueDate),
        'amount': invoice.amount,
        'paid_amount': invoice.paidAmount,
        'remaining_amount': invoice.remaining,
      };
    }).toList(growable: false);
    final totalDue = rows.fold<double>(
      0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
    );
    final totalPaid = rows.fold<double>(
      0,
      (sum, item) => sum + ((item['paid_amount'] as num?)?.toDouble() ?? 0),
    );
    final totalOverdue = rows.fold<double>(
      0,
      (sum, item) => sum + ((item['remaining_amount'] as num?)?.toDouble() ?? 0),
    );
    return _ok(
      message: rows.isEmpty ? 'لا توجد بيانات متأخرات مطابقة.' : 'تم إعداد تقرير المتأخرات.',
      data: <String, dynamic>{
        'report_type': 'arrears_summary',
        'period': <String, dynamic>{
          'from': _ymd(period.$1),
          'to': _ymd(period.$2),
        },
        'currency': 'SAR',
        'filters': <String, dynamic>{
          'property_query': propertyQuery,
        },
        'totals': <String, dynamic>{
          'total_due': totalDue,
          'total_paid': totalPaid,
          'total_overdue': totalOverdue,
        },
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _reportTenantStatement(Map<String, dynamic> arguments) {
    final tenantQuery = _text(arguments, 'tenant_query');
    final matches = _matchingTenants(tenantQuery);
    if (tenantQuery.isEmpty) {
      return <String, dynamic>{
        'status': 'missing_fields',
        'message': 'حدد المستأجر المطلوب للتقرير.',
        'missing_fields': <Map<String, dynamic>>[
          _missingField('tenant_query', 'المستأجر', 'حدد اسم أو مرجع المستأجر.'),
        ],
      };
    }
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من مستأجر مطابق للتقرير. اختر المستأجر الصحيح.',
        matches
            .map((tenant) => AiDisambiguationCandidate(
                  id: tenant.id,
                  label: tenant.fullName,
                  subtitle: tenant.phone,
                  entityType: 'tenant',
                ).toJson())
            .toList(growable: false),
      );
    }
    if (matches.isEmpty) {
      return _err('لم يتم العثور على المستأجر المطلوب.');
    }
    final period = _resolvePeriod(arguments['from_date'], arguments['to_date']);
    final tenant = matches.first;
    final rows = _invoices().where((invoice) {
      if (invoice.tenantId != tenant.id) return false;
      final issueDate = KsaTime.dateOnly(invoice.issueDate);
      return !issueDate.isBefore(period.$1) && !issueDate.isAfter(period.$2);
    }).map(_invoicePayload).toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد بيانات مطابقة للمستأجر.' : 'تم إعداد كشف المستأجر.',
      data: <String, dynamic>{
        'report_type': 'tenant_statement',
        'period': <String, dynamic>{
          'from': _ymd(period.$1),
          'to': _ymd(period.$2),
        },
        'currency': 'SAR',
        'filters': <String, dynamic>{'tenant_id': tenant.id},
        'totals': <String, dynamic>{
          'total_invoices': rows.length,
          'total_amount': rows.fold<double>(
            0,
            (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
          ),
          'total_paid': rows.fold<double>(
            0,
            (sum, item) => sum + ((item['paid_amount'] as num?)?.toDouble() ?? 0),
          ),
        },
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _reportOccupancy(Map<String, dynamic> arguments) {
    final propertyQuery = _text(arguments, 'property_query');
    final units = _properties().where((property) {
      return (property.parentBuildingId ?? '').trim().isNotEmpty;
    }).toList(growable: false);
    final scopedUnits = propertyQuery.isEmpty
        ? units
        : units.where((unit) {
            final building = _propertyById(unit.parentBuildingId ?? '');
            return unit.name.toLowerCase().contains(propertyQuery.toLowerCase()) ||
                (building?.name ?? '').toLowerCase().contains(propertyQuery.toLowerCase());
          }).toList(growable: false);
    final occupied = scopedUnits.where((unit) => _hasActiveContract(unit.id)).length;
    final vacant = scopedUnits.length - occupied;
    final rate = scopedUnits.isEmpty ? 0.0 : (occupied / scopedUnits.length) * 100;
    return _ok(
      message: 'تم إعداد تقرير الإشغال.',
      data: <String, dynamic>{
        'report_type': 'occupancy_rate',
        'period': null,
        'currency': 'SAR',
        'filters': <String, dynamic>{'property_query': propertyQuery},
        'totals': <String, dynamic>{
          'total_units': scopedUnits.length,
          'occupied_units': occupied,
          'vacant_units': vacant,
          'occupancy_rate': rate,
        },
        'rows': scopedUnits.map((unit) {
          final building = _propertyById(unit.parentBuildingId ?? '');
          return <String, dynamic>{
            'unit_name': unit.name,
            'building_name': building?.name,
            'status': _hasActiveContract(unit.id) ? 'occupied' : 'vacant',
          };
        }).toList(growable: false),
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _reportRentCollection(Map<String, dynamic> arguments) {
    final period = _resolvePeriod(arguments['from_date'], arguments['to_date']);
    final propertyQuery = _text(arguments, 'property_query');
    final propertyMatches = propertyQuery.isEmpty ? <Property>[] : _matchingProperties(propertyQuery);
    if (propertyQuery.isNotEmpty && propertyMatches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقار مطابق للتقرير. اختر العقار الصحيح.',
        propertyMatches
            .map((item) => AiDisambiguationCandidate(
                  id: item.id,
                  label: item.name,
                  subtitle: item.address,
                  entityType: 'property',
                ).toJson())
            .toList(growable: false),
      );
    }
    final propertyId =
        propertyMatches.length == 1 ? propertyMatches.first.id : '';
    final rows = _invoices().where((invoice) {
      if (propertyId.isNotEmpty && invoice.propertyId != propertyId) return false;
      final issueDate = KsaTime.dateOnly(invoice.issueDate);
      return !issueDate.isBefore(period.$1) && !issueDate.isAfter(period.$2);
    }).map((invoice) {
      final contract = _contractById(invoice.contractId);
      return <String, dynamic>{
        'invoice_serial_no': invoice.serialNo,
        'contract_serial_no': contract?.serialNo,
        'tenant_name': _snapshotString(contract?.tenantSnapshot, 'fullName'),
        'property_name': _snapshotString(contract?.propertySnapshot, 'name'),
        'amount': invoice.amount,
        'paid_amount': invoice.paidAmount,
        'remaining_amount': invoice.remaining,
      };
    }).toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد بيانات تحصيل مطابقة.' : 'تم إعداد تقرير التحصيل.',
      data: <String, dynamic>{
        'report_type': 'rent_collection',
        'period': <String, dynamic>{
          'from': _ymd(period.$1),
          'to': _ymd(period.$2),
        },
        'currency': 'SAR',
        'filters': <String, dynamic>{'property_query': propertyQuery},
        'totals': <String, dynamic>{
          'total_billed': rows.fold<double>(
            0,
            (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
          ),
          'total_collected': rows.fold<double>(
            0,
            (sum, item) => sum + ((item['paid_amount'] as num?)?.toDouble() ?? 0),
          ),
          'total_remaining': rows.fold<double>(
            0,
            (sum, item) => sum + ((item['remaining_amount'] as num?)?.toDouble() ?? 0),
          ),
        },
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _reportIncomeExpense(Map<String, dynamic> arguments) {
    final period = _resolvePeriod(arguments['from_date'], arguments['to_date']);
    final rows = _invoices().where((invoice) {
      final issueDate = KsaTime.dateOnly(invoice.issueDate);
      return !issueDate.isBefore(period.$1) && !issueDate.isAfter(period.$2);
    }).map((invoice) => <String, dynamic>{
          'invoice_serial_no': invoice.serialNo,
          'amount': invoice.amount,
          'paid_amount': invoice.paidAmount,
          'kind': invoice.amount >= 0 ? 'income' : 'expense',
        }).toList(growable: false);
    final totalIncome = rows
        .where((row) => row['amount'] is num && (row['amount'] as num) > 0)
        .fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble());
    final totalExpense = rows
        .where((row) => row['amount'] is num && (row['amount'] as num) < 0)
        .fold<double>(0, (sum, row) => sum + (row['amount'] as num).abs().toDouble());
    return _ok(
      message: rows.isEmpty ? 'لا توجد بيانات مالية مطابقة.' : 'تم إعداد تقرير الإيرادات والمصروفات.',
      data: <String, dynamic>{
        'report_type': 'income_expense',
        'period': <String, dynamic>{
          'from': _ymd(period.$1),
          'to': _ymd(period.$2),
        },
        'currency': 'SAR',
        'filters': const <String, dynamic>{},
        'totals': <String, dynamic>{
          'total_income': totalIncome,
          'total_expense': totalExpense,
          'net': totalIncome - totalExpense,
        },
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _reportMaintenance(Map<String, dynamic> arguments) {
    final period = _resolvePeriod(arguments['from_date'], arguments['to_date']);
    final status = _text(arguments, 'status');
    final rows = _maintenance().where((request) {
      final createdDate = KsaTime.dateOnly(request.createdAt);
      if (createdDate.isBefore(period.$1) || createdDate.isAfter(period.$2)) {
        return false;
      }
      if (status.isNotEmpty && request.status.name != status) return false;
      return true;
    }).map(_maintenancePayload).toList(growable: false);
    return _ok(
      message: rows.isEmpty ? 'لا توجد بيانات صيانة مطابقة.' : 'تم إعداد ملخص الصيانة.',
      data: <String, dynamic>{
        'report_type': 'maintenance_summary',
        'period': <String, dynamic>{
          'from': _ymd(period.$1),
          'to': _ymd(period.$2),
        },
        'currency': 'SAR',
        'filters': <String, dynamic>{'status': status},
        'totals': <String, dynamic>{
          'total_requests': rows.length,
          'open_requests': rows.where((row) => row['status'] == 'open').length,
          'completed_requests':
              rows.where((row) => row['status'] == 'completed').length,
        },
        'rows': rows,
        'generated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic>? _preflightPropertyCreate(Map<String, dynamic> arguments) {
    final missing = <Map<String, dynamic>>[];
    if (_text(arguments, 'name').isEmpty) missing.add(_missingField('name', 'اسم العقار', 'حدد اسم العقار.'));
    if (_text(arguments, 'type').isEmpty) missing.add(_missingField('type', 'نوع العقار', 'حدد نوع العقار.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل تجهيز إضافة العقار.', 'missing_fields': missing};
    final existing = _matchingProperties(_text(arguments, 'name'));
    if (existing.isNotEmpty) return _disambiguation('يوجد عقار مشابه بهذا الاسم. اختر العقار إن كنت تقصده، أو غيّر الاسم قبل الإضافة.', existing.map((property) => AiDisambiguationCandidate(id: property.id, label: property.name, subtitle: property.address, entityType: 'property').toJson()).toList(growable: false));
    return null;
  }

  Map<String, dynamic>? _preflightPropertyUpdate(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    if (query.isEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العقار المراد تعديله أولًا.', 'missing_fields': <Map<String, dynamic>>[_missingField('query', 'العقار', 'حدد اسم أو مرجع العقار.')]};
    final hasChange = _text(arguments, 'name').isNotEmpty || _text(arguments, 'address').isNotEmpty || _text(arguments, 'notes').isNotEmpty;
    if (!hasChange) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد الحقل الذي تريد تعديله في العقار.', 'missing_fields': <Map<String, dynamic>>[_missingField('name/address/notes', 'بيانات التعديل', 'اذكر الاسم أو العنوان أو الملاحظات الجديدة.')]};
    final matches = _matchingProperties(query);
    if (matches.length > 1) return _disambiguation('وجدت أكثر من عقار مطابق. اختر العقار الصحيح.', matches.map((property) => AiDisambiguationCandidate(id: property.id, label: property.name, subtitle: property.address, entityType: 'property').toJson()).toList(growable: false));
    if (matches.isEmpty) return _err('لم يتم العثور على العقار المطلوب.');
    return null;
  }

  Map<String, dynamic>? _preflightTenantCreate(Map<String, dynamic> arguments) {
    final missing = <Map<String, dynamic>>[];
    if (_text(arguments, 'fullName').isEmpty) missing.add(_missingField('fullName', 'اسم العميل', 'حدد اسم العميل أو المستأجر.'));
    if (_text(arguments, 'clientType').isEmpty) missing.add(_missingField('clientType', 'نوع العميل', 'حدد هل هو مستأجر أو شركة أو مقدم خدمة.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل تجهيز إضافة العميل.', 'missing_fields': missing};
    final matches = _matchingTenants(_text(arguments, 'fullName'));
    if (matches.isNotEmpty) return _disambiguation('يوجد عميل مشابه بهذا الاسم. اختره إن كان هو المقصود أو غيّر الاسم قبل الإضافة.', matches.map((tenant) => AiDisambiguationCandidate(id: tenant.id, label: tenant.fullName, subtitle: tenant.phone, entityType: 'tenant').toJson()).toList(growable: false));
    return null;
  }

  Map<String, dynamic>? _preflightTenantUpdate(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    if (query.isEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العميل المراد تعديله أولًا.', 'missing_fields': <Map<String, dynamic>>[_missingField('query', 'العميل', 'حدد اسم أو هوية أو جوال العميل.')]};
    final hasChange = _text(arguments, 'phone').isNotEmpty || _text(arguments, 'email').isNotEmpty || _text(arguments, 'notes').isNotEmpty;
    if (!hasChange) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد بيانات العميل التي تريد تعديلها.', 'missing_fields': <Map<String, dynamic>>[_missingField('phone/email/notes', 'بيانات التعديل', 'اذكر الجوال أو البريد أو الملاحظات الجديدة.')]};
    final matches = _matchingTenants(query);
    if (matches.length > 1) return _disambiguation('وجدت أكثر من عميل مطابق. اختر العميل الصحيح.', matches.map((tenant) => AiDisambiguationCandidate(id: tenant.id, label: tenant.fullName, subtitle: tenant.phone, entityType: 'tenant').toJson()).toList(growable: false));
    if (matches.isEmpty) return _err('لم يتم العثور على العميل المطلوب.');
    return null;
  }

  Map<String, dynamic>? _preflightCreateContract(Map<String, dynamic> arguments) {
    final propertyResolution = _resolveSingleProperty(arguments['property_id'], arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final tenantResolution = _resolveSingleTenant(arguments['tenant_id'], arguments['tenant_query']);
    if (tenantResolution['status'] == 'disambiguation') return tenantResolution;
    if (tenantResolution['status'] == 'error') return tenantResolution;
    final property = propertyResolution['record'] as Property?;
    final tenant = tenantResolution['record'] as Tenant?;
    final missing = <Map<String, dynamic>>[];
    if (property == null) missing.add(_missingField('property_query', 'العقار أو الوحدة', 'حدد العقار أو الوحدة.'));
    if (tenant == null) missing.add(_missingField('tenant_query', 'المستأجر', 'حدد المستأجر.'));
    if (_text(arguments, 'startDate').isEmpty) missing.add(_missingField('startDate', 'تاريخ البداية', 'حدد تاريخ بداية العقد.'));
    if (_text(arguments, 'endDate').isEmpty) missing.add(_missingField('endDate', 'تاريخ النهاية', 'حدد تاريخ نهاية العقد.'));
    if (arguments['rentAmount'] == null) missing.add(_missingField('rentAmount', 'قيمة الإيجار', 'حدد قيمة الإيجار.'));
    if (_text(arguments, 'paymentCycle').isEmpty) missing.add(_missingField('paymentCycle', 'دورة السداد', 'حدد دورة السداد.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل تجهيز العقد.', 'missing_fields': missing};
    final start = _parseDate(arguments['startDate']);
    final end = _parseDate(arguments['endDate']);
    if (start == null || end == null || !end.isAfter(start)) return _err('تواريخ العقد غير صحيحة. يجب أن يكون تاريخ النهاية بعد تاريخ البداية.');
    final rentAmount = (arguments['rentAmount'] as num?)?.toDouble() ?? 0;
    if (rentAmount <= 0) return _err('قيمة الإيجار يجب أن تكون أكبر من صفر.');
    if (_hasOverlappingContract(property!.id, start, end)) return _err('لا يمكن إنشاء العقد لأن العقار أو الوحدة لديه عقد نشط أو متداخل في نفس الفترة.');
    return null;
  }

  Map<String, dynamic>? _preflightUpdateContract(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    if (query.isEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العقد المراد تعديله أولًا.', 'missing_fields': <Map<String, dynamic>>[_missingField('query', 'العقد', 'حدد رقم العقد أو مرجعه.')]};
    final hasChange = _text(arguments, 'endDate').isNotEmpty || arguments['rentAmount'] != null || _text(arguments, 'notes').isNotEmpty;
    if (!hasChange) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد بيانات العقد التي تريد تعديلها.', 'missing_fields': <Map<String, dynamic>>[_missingField('endDate/rentAmount/notes', 'بيانات التعديل', 'اذكر تاريخ النهاية أو قيمة الإيجار أو الملاحظات.')]};
    final matches = _matchingContracts(query);
    if (matches.length > 1) return _disambiguation('وجدت أكثر من عقد مطابق. اختر العقد الصحيح.', matches.map((contract) => AiDisambiguationCandidate(id: contract.id, label: contract.serialNo ?? contract.id, subtitle: _snapshotString(contract.tenantSnapshot, 'fullName'), entityType: 'contract').toJson()).toList(growable: false));
    if (matches.isEmpty) return _err('لم يتم العثور على العقد المطلوب.');
    if (matches.first.isTerminated) return _err('لا يمكن تعديل عقد منتهي من هذه الدردشة.');
    return null;
  }

  Map<String, dynamic>? _preflightTerminateContract(Map<String, dynamic> arguments) {
    final query = _text(arguments, 'query');
    if (query.isEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العقد المراد إنهاؤه أولًا.', 'missing_fields': <Map<String, dynamic>>[_missingField('query', 'العقد', 'حدد رقم العقد أو مرجعه.')]};
    final matches = _matchingContracts(query);
    if (matches.length > 1) return _disambiguation('وجدت أكثر من عقد مطابق. اختر العقد الصحيح.', matches.map((contract) => AiDisambiguationCandidate(id: contract.id, label: contract.serialNo ?? contract.id, subtitle: _snapshotString(contract.tenantSnapshot, 'fullName'), entityType: 'contract').toJson()).toList(growable: false));
    if (matches.isEmpty) return _err('لم يتم العثور على العقد المطلوب.');
    if (matches.first.isTerminated) return _err('هذا العقد منتهي مسبقًا.');
    return null;
  }

  Map<String, dynamic>? _preflightCreateInvoice(Map<String, dynamic> arguments) {
    final contractResolution = _resolveSingleContract(arguments['contract_id'], arguments['query']);
    if (contractResolution['status'] == 'disambiguation') return contractResolution;
    if (contractResolution['status'] == 'error') return contractResolution;
    final contract = contractResolution['record'] as Contract?;
    final missing = <Map<String, dynamic>>[];
    if (contract == null) missing.add(_missingField('query', 'العقد', 'حدد العقد.'));
    if (arguments['amount'] == null) missing.add(_missingField('amount', 'المبلغ', 'حدد مبلغ الفاتورة.'));
    if (_text(arguments, 'dueDate').isEmpty) missing.add(_missingField('dueDate', 'تاريخ الاستحقاق', 'حدد تاريخ الاستحقاق.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل إنشاء الفاتورة.', 'missing_fields': missing};
    final amount = (arguments['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return _err('مبلغ الفاتورة يجب أن يكون أكبر من صفر.');
    if (_parseDate(arguments['dueDate']) == null) return _err('تاريخ الاستحقاق غير صحيح.');
    return null;
  }

  Map<String, dynamic>? _preflightRecordPayment(Map<String, dynamic> arguments) {
    final invoiceResolution = _resolveSingleInvoice(arguments['invoice_id'], arguments['invoiceSerialNo'], arguments['query']);
    if (invoiceResolution['status'] == 'disambiguation') return invoiceResolution;
    if (invoiceResolution['status'] == 'error') return invoiceResolution;
    final invoice = invoiceResolution['record'] as Invoice?;
    final missing = <Map<String, dynamic>>[];
    if (invoice == null) missing.add(_missingField('query', 'الفاتورة', 'حدد الفاتورة أو العقد.'));
    if (arguments['amount'] == null) missing.add(_missingField('amount', 'المبلغ', 'حدد مبلغ الدفعة.'));
    if (_text(arguments, 'paymentMethod').isEmpty) missing.add(_missingField('paymentMethod', 'طريقة الدفع', 'حدد طريقة الدفع.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل تسجيل الدفعة.', 'missing_fields': missing};
    final amount = (arguments['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return _err('مبلغ الدفعة يجب أن يكون أكبر من صفر.');
    if (invoice!.isCanceled) return _err('لا يمكن تسجيل دفعة على فاتورة ملغاة.');
    if (amount - invoice.remaining > 0.01) return _err('مبلغ الدفعة أكبر من المبلغ المتبقي على الفاتورة.');
    return null;
  }

  Map<String, dynamic>? _preflightCreateMaintenance(Map<String, dynamic> arguments) {
    final propertyResolution = _resolveSingleProperty(arguments['property_id'], arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final property = propertyResolution['record'] as Property?;
    final missing = <Map<String, dynamic>>[];
    if (property == null) missing.add(_missingField('property_query', 'العقار', 'حدد العقار أو الوحدة.'));
    if (_text(arguments, 'title').isEmpty) missing.add(_missingField('title', 'العنوان', 'حدد عنوان طلب الصيانة.'));
    if (_text(arguments, 'description').isEmpty) missing.add(_missingField('description', 'الوصف', 'اكتب وصف المشكلة أو الخدمة.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل إنشاء طلب الصيانة.', 'missing_fields': missing};
    return null;
  }

  Map<String, dynamic>? _preflightUpdateMaintenanceStatus(Map<String, dynamic> arguments) {
    final missing = <Map<String, dynamic>>[];
    if (_text(arguments, 'query').isEmpty) missing.add(_missingField('query', 'طلب الصيانة', 'حدد رقم أو عنوان الطلب.'));
    if (_text(arguments, 'status').isEmpty) missing.add(_missingField('status', 'الحالة الجديدة', 'حدد الحالة الجديدة.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج تحديد الطلب والحالة قبل التحديث.', 'missing_fields': missing};
    return null;
  }

  Map<String, dynamic>? _preflightPeriodicService(Map<String, dynamic> arguments, {required bool isCreate}) {
    final propertyResolution = _resolveSingleProperty(null, arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final property = propertyResolution['record'] as Property?;
    final type = _text(arguments, 'serviceType');
    final missing = <Map<String, dynamic>>[];
    if (property == null) missing.add(_missingField('property_query', 'العقار', 'حدد العقار أو الوحدة.'));
    if (type.isEmpty) missing.add(_missingField('serviceType', 'نوع الخدمة', 'حدد نوع الخدمة: cleaning/elevator/internet/water/electricity.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض الحقول قبل تجهيز الخدمة الدورية.', 'missing_fields': missing};
    final allowedTypes = const <String>{'cleaning', 'elevator', 'internet', 'water', 'electricity'};
    if (!allowedTypes.contains(type)) return _err('نوع الخدمة الدورية غير مدعوم.');
    final billingMode = _text(arguments, 'billingMode');
    final nextDueDate = _text(arguments, 'nextDueDate');
    if ((type == 'cleaning' || type == 'elevator' || (type == 'internet' && (billingMode.isEmpty || billingMode == 'owner'))) && _text(arguments, 'provider').isEmpty) missing.add(_missingField('provider', 'مقدم الخدمة', 'حدد مقدم الخدمة.'));
    if ((type == 'cleaning' || type == 'elevator' || (type == 'internet' && (billingMode.isEmpty || billingMode == 'owner'))) && nextDueDate.isEmpty) missing.add(_missingField('nextDueDate', 'تاريخ الاستحقاق القادم', 'حدد تاريخ الدورة القادمة.'));
    if ((type == 'water' || type == 'electricity') && billingMode.isEmpty) missing.add(_missingField('billingMode', 'طريقة الخدمة', 'حدد هل الخدمة منفصلة أو مشتركة.'));
    if ((type == 'water' || type == 'electricity') && billingMode == 'separate' && _text(arguments, 'meterNumber').isEmpty) missing.add(_missingField('meterNumber', 'رقم العداد', 'حدد رقم العداد أو افتح الشاشة.'));
    if ((type == 'water' || type == 'electricity') && billingMode == 'shared' && _text(arguments, 'sharedMethod').isEmpty) missing.add(_missingField('sharedMethod', 'طريقة التوزيع', 'حدد fixed أو percent.'));
    if (missing.isNotEmpty) return <String, dynamic>{'status': 'missing_fields', 'message': 'أحتاج بعض تفاصيل الخدمة الدورية قبل التأكيد.', 'missing_fields': missing};
    return null;
  }

  Future<Map<String, dynamic>> _periodicServicesSearch(Map<String, dynamic> arguments) async {
    final propertyResolution = _resolveSingleProperty(null, arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final property = propertyResolution['record'] as Property?;
    if (property == null) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العقار المطلوب لعرض خدماته الدورية.', 'missing_fields': <Map<String, dynamic>>[_missingField('property_query', 'العقار', 'حدد اسم العقار أو الوحدة.')]};
    final type = _text(arguments, 'serviceType');
    final includeHistory = arguments['includeHistory'] == true;
    if (type.isEmpty) return _executeLegacy('get_property_services', <String, dynamic>{'propertyName': property.name});
    return _executeLegacy(includeHistory ? 'get_periodic_service_history' : 'get_property_service_details', <String, dynamic>{'propertyName': property.name, 'serviceType': type});
  }

  Future<Map<String, dynamic>> _periodicServicesMutate(Map<String, dynamic> arguments, {required bool isCreate}) async {
    final propertyResolution = _resolveSingleProperty(null, arguments['property_query']);
    if (propertyResolution['status'] == 'disambiguation') return propertyResolution;
    if (propertyResolution['status'] == 'error') return propertyResolution;
    final property = propertyResolution['record'] as Property?;
    if (property == null) return <String, dynamic>{'status': 'missing_fields', 'message': 'حدد العقار المطلوب للخدمة الدورية.', 'missing_fields': <Map<String, dynamic>>[_missingField('property_query', 'العقار', 'حدد اسم العقار أو الوحدة.')]};
    return _executeLegacy(isCreate ? 'create_periodic_service' : 'update_periodic_service', <String, dynamic>{'propertyName': property.name, 'serviceType': arguments['serviceType'], 'provider': arguments['provider'], 'cost': arguments['cost'], 'billingMode': arguments['billingMode'], 'sharedMethod': arguments['sharedMethod'], 'meterNumber': arguments['meterNumber'], 'sharePercent': arguments['sharePercent'], 'totalAmount': arguments['totalAmount'], 'nextDueDate': arguments['nextDueDate'], 'recurrenceMonths': arguments['recurrenceMonths'], 'remindBeforeDays': arguments['remindBeforeDays']});
  }

  Future<Map<String, dynamic>> _openScreen(
    String requestedToolName,
    Map<String, dynamic> arguments,
  ) async {
    if (requestedToolName != 'app.open_screen' &&
        requestedToolName != 'navigate_to_screen' &&
        requestedToolName != 'open_tenant_entry' &&
        requestedToolName != 'open_property_entry' &&
        requestedToolName != 'open_contract_entry' &&
        requestedToolName != 'open_maintenance_entry' &&
        requestedToolName != 'open_contract_invoice_history') {
      return _unsupported('تعذر تحديد الشاشة المطلوبة.');
    }
    if (requestedToolName == 'app.open_screen') {
      return _executeLegacy(
        'navigate_to_screen',
        <String, dynamic>{'screen': arguments['screen']},
      );
    }
    return _executeLegacy(requestedToolName, arguments);
  }

  Map<String, dynamic> _resolveSingleProperty(dynamic propertyId, dynamic query) {
    final id = (propertyId ?? '').toString().trim();
    if (id.isNotEmpty) {
      final match = _propertyById(id);
      if (match == null) return _err('لم يتم العثور على العقار المطلوب.');
      return <String, dynamic>{'status': 'ok', 'record': match};
    }
    final text = (query ?? '').toString().trim();
    if (text.isEmpty) return <String, dynamic>{'status': 'ok', 'record': null};
    final matches = _matchingProperties(text);
    if (matches.isEmpty) return _err('لم يتم العثور على عقار مطابق.');
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقار مطابق. اختر العقار الصحيح.',
        matches
            .map((item) => AiDisambiguationCandidate(
                  id: item.id,
                  label: item.name,
                  subtitle: item.address,
                  entityType: 'property',
                ).toJson())
            .toList(growable: false),
      );
    }
    return <String, dynamic>{'status': 'ok', 'record': matches.first};
  }

  Map<String, dynamic> _resolveSingleTenant(dynamic tenantId, dynamic query) {
    final id = (tenantId ?? '').toString().trim();
    if (id.isNotEmpty) {
      final match = _tenants().where((tenant) => tenant.id == id).toList();
      if (match.isEmpty) return _err('لم يتم العثور على المستأجر المطلوب.');
      return <String, dynamic>{'status': 'ok', 'record': match.first};
    }
    final text = (query ?? '').toString().trim();
    if (text.isEmpty) return <String, dynamic>{'status': 'ok', 'record': null};
    final matches = _matchingTenants(text);
    if (matches.isEmpty) return _err('لم يتم العثور على مستأجر مطابق.');
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من مستأجر مطابق. اختر المستأجر الصحيح.',
        matches
            .map((tenant) => AiDisambiguationCandidate(
                  id: tenant.id,
                  label: tenant.fullName,
                  subtitle: tenant.phone,
                  entityType: 'tenant',
                ).toJson())
            .toList(growable: false),
      );
    }
    return <String, dynamic>{'status': 'ok', 'record': matches.first};
  }

  Map<String, dynamic> _resolveSingleContract(dynamic contractId, dynamic query) {
    final id = (contractId ?? '').toString().trim();
    if (id.isNotEmpty) {
      final match = _contractById(id);
      if (match == null) return _err('لم يتم العثور على العقد المطلوب.');
      return <String, dynamic>{'status': 'ok', 'record': match};
    }
    final text = (query ?? '').toString().trim();
    if (text.isEmpty) return <String, dynamic>{'status': 'ok', 'record': null};
    final matches = _matchingContracts(text);
    if (matches.isEmpty) return _err('لم يتم العثور على عقد مطابق.');
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من عقد مطابق. اختر العقد الصحيح.',
        matches
            .map((contract) => AiDisambiguationCandidate(
                  id: contract.id,
                  label: contract.serialNo ?? contract.id,
                  subtitle: _snapshotString(contract.tenantSnapshot, 'fullName'),
                  entityType: 'contract',
                ).toJson())
            .toList(growable: false),
      );
    }
    return <String, dynamic>{'status': 'ok', 'record': matches.first};
  }

  Map<String, dynamic> _resolveSingleInvoice(
    dynamic invoiceId,
    dynamic invoiceSerialNo,
    dynamic query,
  ) {
    final id = (invoiceId ?? '').toString().trim();
    if (id.isNotEmpty) {
      final match = _invoices().where((invoice) => invoice.id == id).toList();
      if (match.isEmpty) return _err('لم يتم العثور على الفاتورة المطلوبة.');
      return <String, dynamic>{'status': 'ok', 'record': match.first};
    }

    final serial = (invoiceSerialNo ?? '').toString().trim();
    if (serial.isNotEmpty) {
      final match =
          _invoices().where((invoice) => (invoice.serialNo ?? '') == serial).toList();
      if (match.isEmpty) return _err('لم يتم العثور على الفاتورة المطلوبة.');
      if (match.length > 1) {
        return _disambiguation(
          'وجدت أكثر من فاتورة مطابقة. اختر الفاتورة الصحيحة.',
          match
              .map((invoice) => AiDisambiguationCandidate(
                    id: invoice.id,
                    label: invoice.serialNo ?? invoice.id,
                    subtitle: _contractById(invoice.contractId)?.serialNo ?? '',
                    entityType: 'invoice',
                  ).toJson())
              .toList(growable: false),
        );
      }
      return <String, dynamic>{'status': 'ok', 'record': match.first};
    }

    final text = (query ?? '').toString().trim();
    if (text.isEmpty) return <String, dynamic>{'status': 'ok', 'record': null};
    final matches = _invoices().where((invoice) {
      final q = text.toLowerCase();
      final contract = _contractById(invoice.contractId);
      return (invoice.serialNo ?? '').toLowerCase().contains(q) ||
          (contract?.serialNo ?? '').toLowerCase().contains(q) ||
          _snapshotString(contract?.tenantSnapshot, 'fullName')
              .toLowerCase()
              .contains(q);
    }).toList(growable: false);
    if (matches.isEmpty) return _err('لم يتم العثور على فاتورة مطابقة.');
    if (matches.length > 1) {
      return _disambiguation(
        'وجدت أكثر من فاتورة مطابقة. اختر الفاتورة الصحيحة.',
        matches
            .map((invoice) => AiDisambiguationCandidate(
                  id: invoice.id,
                  label: invoice.serialNo ?? invoice.id,
                  subtitle: _contractById(invoice.contractId)?.serialNo ?? '',
                  entityType: 'invoice',
                ).toJson())
            .toList(growable: false),
      );
    }
    return <String, dynamic>{'status': 'ok', 'record': matches.first};
  }

  List<Property> _properties() {
    final name = boxName(kPropertiesBox);
    if (!Hive.isBoxOpen(name)) return const <Property>[];
    return Hive.box<Property>(name).values.toList(growable: false);
  }

  List<Tenant> _tenants() {
    final name = boxName(kTenantsBox);
    if (!Hive.isBoxOpen(name)) return const <Tenant>[];
    return Hive.box<Tenant>(name).values.toList(growable: false);
  }

  List<Contract> _contracts() {
    final name = boxName(kContractsBox);
    if (!Hive.isBoxOpen(name)) return const <Contract>[];
    return Hive.box<Contract>(name).values.toList(growable: false);
  }

  List<Invoice> _invoices() {
    final name = boxName(kInvoicesBox);
    if (!Hive.isBoxOpen(name)) return const <Invoice>[];
    return Hive.box<Invoice>(name).values.toList(growable: false);
  }

  List<MaintenanceRequest> _maintenance() {
    final name = boxName(kMaintenanceBox);
    if (!Hive.isBoxOpen(name)) return const <MaintenanceRequest>[];
    return Hive.box<MaintenanceRequest>(name).values.toList(growable: false);
  }

  Property? _propertyById(String id) {
    for (final property in _properties()) {
      if (property.id == id) return property;
    }
    return null;
  }

  Contract? _contractById(String id) {
    for (final contract in _contracts()) {
      if (contract.id == id) return contract;
    }
    return null;
  }

  List<Property> _matchingProperties(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Property>[];
    return _properties().where((property) {
      return property.name.toLowerCase().contains(q) ||
          property.address.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<Tenant> _matchingTenants(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Tenant>[];
    return _tenants().where((tenant) {
      return tenant.fullName.toLowerCase().contains(q) ||
          (tenant.companyName ?? '').toLowerCase().contains(q) ||
          tenant.phone.contains(query) ||
          tenant.nationalId.contains(query);
    }).toList(growable: false);
  }

  List<Contract> _matchingContracts(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Contract>[];
    return _contracts().where((contract) {
      return (contract.serialNo ?? '').toLowerCase().contains(q) ||
          _snapshotString(contract.tenantSnapshot, 'fullName')
              .toLowerCase()
              .contains(q) ||
          _snapshotString(contract.propertySnapshot, 'name')
              .toLowerCase()
              .contains(q);
    }).toList(growable: false);
  }

  bool _hasOverlappingContract(String propertyId, DateTime start, DateTime end) {
    final requestedStart = KsaTime.dateOnly(start);
    final requestedEnd = KsaTime.dateOnly(end);
    for (final contract in _contracts()) {
      if (contract.propertyId != propertyId) continue;
      if (contract.isTerminated) continue;
      final existingStart = KsaTime.dateOnly(contract.startDate);
      final existingEnd = KsaTime.dateOnly(contract.endDate);
      final overlaps = !requestedEnd.isBefore(existingStart) &&
          !requestedStart.isAfter(existingEnd);
      if (overlaps) return true;
    }
    return false;
  }

  bool _hasActiveContract(String propertyId) {
    for (final contract in _contracts()) {
      if (contract.propertyId == propertyId && contract.isActiveNow) return true;
    }
    return false;
  }

  String _contractStatus(Contract contract) {
    if (contract.isTerminated) return 'terminated';
    if (contract.isExpiredByTime) return 'expired';
    if (contract.isActiveNow) return 'active';
    return 'pending';
  }

  Map<String, dynamic> _propertyPayload(Property property) {
    return <String, dynamic>{
      'id': property.id,
      'name': property.name,
      'type': property.type.name,
      'type_label': property.type.label,
      'address': property.address,
      'is_archived': property.isArchived,
      'parent_building_id': property.parentBuildingId,
    };
  }

  Map<String, dynamic> _tenantPayload(Tenant tenant) {
    return <String, dynamic>{
      'id': tenant.id,
      'full_name': tenant.fullName,
      'phone': tenant.phone,
      'national_id': tenant.nationalId,
      'client_type': tenant.clientType,
      'is_archived': tenant.isArchived,
      'is_blacklisted': tenant.isBlacklisted,
    };
  }

  Map<String, dynamic> _contractPayload(Contract contract) {
    return <String, dynamic>{
      'id': contract.id,
      'serial_no': contract.serialNo,
      'tenant_name': _snapshotString(contract.tenantSnapshot, 'fullName'),
      'property_name': _snapshotString(contract.propertySnapshot, 'name'),
      'start_date': _ymd(contract.startDate),
      'end_date': _ymd(contract.endDate),
      'rent_amount': contract.rentAmount,
      'payment_cycle': _paymentCycleName(contract.paymentCycle),
      'status': _contractStatus(contract),
    };
  }

  Map<String, dynamic> _invoicePayload(Invoice invoice) {
    return <String, dynamic>{
      'id': invoice.id,
      'serial_no': invoice.serialNo,
      'issue_date': _ymd(invoice.issueDate),
      'due_date': _ymd(invoice.dueDate),
      'amount': invoice.amount,
      'paid_amount': invoice.paidAmount,
      'remaining_amount': invoice.remaining,
      'status': invoice.isCanceled
          ? 'cancelled'
          : invoice.isPaid
              ? 'paid'
              : invoice.isOverdue
                  ? 'overdue'
                  : 'unpaid',
    };
  }

  Map<String, dynamic> _maintenancePayload(MaintenanceRequest request) {
    final property = _propertyById(request.propertyId);
    return <String, dynamic>{
      'id': request.id,
      'serial_no': request.serialNo,
      'title': request.title,
      'property_name': property?.name,
      'status': request.status.name,
      'priority': request.priority.name,
      'created_at': _ymd(request.createdAt),
    };
  }

  String _snapshotString(Map<String, dynamic>? snapshot, String key) {
    return (snapshot?[key] ?? '').toString().trim();
  }

  String _workflowHelp(String workflow) {
    final normalized = workflow.trim().toLowerCase();
    if (normalized.contains('عقد')) {
      return 'سير إضافة العقد يكون عادة: تحديد المستأجر، ثم العقار أو الوحدة، ثم التواريخ، ثم الإيجار ودورة السداد، ثم عرض معاينة التأكيد قبل التنفيذ.';
    }
    if (normalized.contains('دفعة') || normalized.contains('سداد')) {
      return 'سير تسجيل الدفعة يكون: تحديد الفاتورة أو العقد الصحيح، ثم تحديد المبلغ، ثم عرض معاينة التأكيد، وبعد التنفيذ يتم التحقق من الفاتورة المحدثة.';
    }
    if (normalized.contains('صيانة')) {
      return 'سير طلب الصيانة يكون: تحديد العقار أو الوحدة، ثم كتابة العنوان والوصف، ثم الأولوية ومقدم الخدمة إن وجد، ثم عرض معاينة التأكيد قبل الإنشاء.';
    }
    return 'يمكنني شرح سير إضافة العقود والدفعات والصيانة وفتح شاشات الإدخال المناسبة عند الحاجة.';
  }

  String _text(Map<String, dynamic> arguments, String key) {
    return (arguments[key] ?? '').toString().trim();
  }

  String _ymd(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  (DateTime, DateTime) _resolvePeriod(dynamic fromDate, dynamic toDate) {
    final today = KsaTime.today();
    final from = _parseDate(fromDate) ?? DateTime(today.year, today.month, 1);
    final to = _parseDate(toDate) ??
        DateTime(today.year, today.month + 1, 0);
    return (KsaTime.dateOnly(from), KsaTime.dateOnly(to));
  }

  DateTime? _parseDate(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _paymentCycleName(PaymentCycle cycle) {
    switch (cycle) {
      case PaymentCycle.monthly:
        return 'monthly';
      case PaymentCycle.quarterly:
        return 'quarterly';
      case PaymentCycle.semiAnnual:
        return 'semiAnnual';
      case PaymentCycle.annual:
        return 'annual';
    }
  }

  Map<String, dynamic> _missingField(
    String field,
    String label,
    String message,
  ) {
    return <String, dynamic>{
      'field': field,
      'label': label,
      'message': message,
    };
  }

  Map<String, dynamic> _ok({
    required String message,
    required Map<String, dynamic> data,
  }) {
    return <String, dynamic>{
      'status': 'success',
      'message': message,
      'payload': data,
    };
  }

  Map<String, dynamic> _err(
    String message, {
    String code = 'error',
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'status': 'error',
      'message': message,
      'code': code,
      'payload': data,
    };
  }

  Map<String, dynamic> _unsupported(String message) {
    return <String, dynamic>{
      'status': 'unsupported',
      'message': message,
      'payload': const <String, dynamic>{},
    };
  }

  Map<String, dynamic> _disambiguation(
    String message,
    List<Map<String, dynamic>> candidates,
  ) {
    return <String, dynamic>{
      'status': 'disambiguation',
      'message': message,
      'candidates': candidates,
    };
  }
}
