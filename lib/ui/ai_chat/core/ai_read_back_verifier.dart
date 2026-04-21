import 'package:hive/hive.dart';

import '../../../data/constants/boxes.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/user_scope.dart';
import '../../../models/property.dart';
import '../../../models/tenant.dart';
import '../../../ui/contracts_screen.dart' show Contract;
import '../../../ui/invoices_screen.dart' show Invoice;
import '../../../ui/maintenance_screen.dart' show MaintenanceRequest;
import 'ai_chat_types.dart';

class AiReadBackVerifier {
  const AiReadBackVerifier();

  Future<Map<String, dynamic>> verify({
    required AiToolDefinition definition,
    required Map<String, dynamic> normalizedArguments,
    required Map<String, dynamic> executionPayload,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    switch (definition.name) {
      case 'properties.create':
      case 'properties.update':
        return _verifyProperty(normalizedArguments, executionPayload);
      case 'tenants.create':
      case 'tenants.update':
        return _verifyTenant(normalizedArguments, executionPayload);
      case 'contracts.create':
      case 'contracts.update':
      case 'contracts.terminate':
        return _verifyContract(definition, normalizedArguments, executionPayload);
      case 'invoices.create':
        return _verifyInvoice(normalizedArguments, executionPayload);
      case 'payments.create':
        return _verifyPayment(normalizedArguments, executionPayload);
      case 'maintenance.create_ticket':
      case 'maintenance.update_status':
        return _verifyMaintenance(normalizedArguments, executionPayload);
      default:
        return <String, dynamic>{
          'verified': true,
          'message': 'لا يحتاج هذا الإجراء إلى تحقق لاحق إضافي.',
          'result_reference': const <String, dynamic>{},
        };
    }
  }

  Map<String, dynamic> _verifyProperty(
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _propertiesBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق العقارات للتحقق.');
    }
    final payload = _payload(executionPayload);
    final propertyData =
        Map<String, dynamic>.from(payload['property'] as Map? ?? const <String, dynamic>{});
    final propertyId = (propertyData['id'] ?? payload['property_id'] ?? '').toString().trim();
    Property? property;
    if (propertyId.isNotEmpty) {
      property = box.get(propertyId);
    }
    property ??= _findPropertyByExactName(
      box.values,
      (normalizedArguments['name'] ?? normalizedArguments['query'] ?? '').toString(),
    );
    if (property == null) {
      return _failed('تعذر العثور على العقار بعد التنفيذ.');
    }

    final requestedName = (normalizedArguments['name'] ?? '').toString().trim();
    if (requestedName.isNotEmpty && property.name.trim() != requestedName) {
      return _failed('تم التنفيذ لكن الاسم المقروء لا يطابق المطلوب.');
    }
    final requestedType = (normalizedArguments['type'] ?? '').toString().trim();
    if (requestedType.isNotEmpty && _enumName(property.type) != requestedType) {
      return _failed('تم التنفيذ لكن نوع العقار المقروء لا يطابق المطلوب.');
    }
    final requestedAddress = (normalizedArguments['address'] ?? '').toString().trim();
    if (requestedAddress.isNotEmpty && property.address.trim() != requestedAddress) {
      return _failed('تم التنفيذ لكن عنوان العقار المقروء لا يطابق المطلوب.');
    }
    final requestedRentalMode =
        (normalizedArguments['rentalMode'] ?? '').toString().trim();
    if (requestedRentalMode.isNotEmpty &&
        _enumName(property.rentalMode) != requestedRentalMode) {
      return _failed('تم التنفيذ لكن نمط التأجير المقروء لا يطابق المطلوب.');
    }
    final requestedTotalUnits = (normalizedArguments['totalUnits'] as num?)?.toInt();
    if (requestedTotalUnits != null && property.totalUnits != requestedTotalUnits) {
      return _failed('تم التنفيذ لكن عدد الوحدات المقروء لا يطابق المطلوب.');
    }
    return _success(
      message: 'تم التحقق من العقار من المصدر بعد التنفيذ.',
      reference: <String, dynamic>{
        'property_id': property.id,
      },
    );
  }

  Map<String, dynamic> _verifyTenant(
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _tenantsBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق العملاء للتحقق.');
    }
    final payload = _payload(executionPayload);
    final tenantData =
        Map<String, dynamic>.from(payload['client'] as Map? ?? const <String, dynamic>{});
    final requestedName =
        (normalizedArguments['fullName'] ?? normalizedArguments['query'] ?? tenantData['full_name'] ?? '')
            .toString()
            .trim();
    final requestedPhone =
        (normalizedArguments['phone'] ?? tenantData['phone'] ?? '').toString().trim();
    final requestedNationalId =
        (normalizedArguments['nationalId'] ?? tenantData['national_id'] ?? '')
            .toString()
            .trim();
    Tenant? tenant = _findTenant(
      box.values,
      name: requestedName,
      phone: requestedPhone,
      nationalId: requestedNationalId,
      query: (normalizedArguments['query'] ?? '').toString(),
    );
    if (tenant == null) {
      return _failed('تعذر العثور على العميل بعد التنفيذ.');
    }
    final requestedEmail =
        (normalizedArguments['email'] ?? tenantData['email'] ?? '').toString().trim();
    if (requestedEmail.isNotEmpty && (tenant.email ?? '').trim() != requestedEmail) {
      return _failed('تم التنفيذ لكن بريد العميل المقروء لا يطابق المطلوب.');
    }
    final requestedClientType =
        (normalizedArguments['clientType'] ?? tenantData['client_type'] ?? '')
            .toString()
            .trim();
    if (requestedClientType.isNotEmpty &&
        tenant.clientType.trim() != requestedClientType) {
      return _failed('تم التنفيذ لكن نوع العميل المقروء لا يطابق المطلوب.');
    }
    return _success(
      message: 'تم التحقق من العميل من المصدر بعد التنفيذ.',
      reference: <String, dynamic>{
        'tenant_id': tenant.id,
      },
    );
  }

  Map<String, dynamic> _verifyContract(
    AiToolDefinition definition,
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _contractsBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق العقود للتحقق.');
    }
    final payload = _payload(executionPayload);
    final contractId = (payload['contractId'] ?? payload['contract_id'] ?? '').toString().trim();
    Contract? contract;
    if (contractId.isNotEmpty) {
      contract = box.get(contractId);
    }
    final serial = (payload['contractSerialNo'] ??
            payload['contract_serial_no'] ??
            normalizedArguments['query'] ??
            normalizedArguments['contractSerialNo'] ??
            '')
        .toString()
        .trim();
    contract ??= _findContract(box.values, serial: serial);
    if (contract == null) {
      return _failed('تعذر العثور على العقد بعد التنفيذ.');
    }
    if (definition.name == 'contracts.terminate' && !contract.isTerminated) {
      return _failed('تم تنفيذ الإنهاء لكن قراءة العقد لم تؤكد الحالة المنتهية.');
    }
    final requestedStartDate =
        (normalizedArguments['startDate'] ?? '').toString().trim();
    if (requestedStartDate.isNotEmpty &&
        !_sameYmd(contract.startDate.toIso8601String(), requestedStartDate)) {
      return _failed('تم التنفيذ لكن تاريخ بداية العقد المقروء لا يطابق المطلوب.');
    }
    final requestedEndDate =
        (normalizedArguments['endDate'] ?? '').toString().trim();
    if (requestedEndDate.isNotEmpty &&
        !_sameYmd(contract.endDate.toIso8601String(), requestedEndDate)) {
      return _failed('تم التنفيذ لكن تاريخ نهاية العقد المقروء لا يطابق المطلوب.');
    }
    final requestedRentAmount =
        (normalizedArguments['rentAmount'] as num?)?.toDouble();
    if (requestedRentAmount != null &&
        (contract.rentAmount - requestedRentAmount).abs() > 0.01) {
      return _failed('تم التنفيذ لكن قيمة الإيجار المقروءة لا تطابق المطلوب.');
    }
    final requestedPaymentCycle =
        (normalizedArguments['paymentCycle'] ?? '').toString().trim();
    if (requestedPaymentCycle.isNotEmpty &&
        _enumName(contract.paymentCycle) != requestedPaymentCycle) {
      return _failed('تم التنفيذ لكن دورة السداد المقروءة لا تطابق المطلوب.');
    }
    return _success(
      message: 'تم التحقق من العقد من المصدر بعد التنفيذ.',
      reference: <String, dynamic>{
        'contract_id': contract.id,
        'contract_serial_no': contract.serialNo,
      },
    );
  }

  Map<String, dynamic> _verifyInvoice(
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _invoicesBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق الفواتير للتحقق.');
    }
    final payload = _payload(executionPayload);
    final invoiceId = (payload['invoice_id'] ?? '').toString().trim();
    Invoice? invoice;
    if (invoiceId.isNotEmpty) {
      invoice = box.get(invoiceId);
    }
    final amount = (normalizedArguments['amount'] as num?)?.toDouble();
    final dueDate = (normalizedArguments['dueDate'] ?? '').toString().trim();
    invoice ??= box.values.cast<Invoice?>().firstWhere(
          (item) {
            if (item == null) return false;
            if (amount != null && (item.amount - amount).abs() > 0.01) return false;
            if (dueDate.isNotEmpty &&
                !_sameYmd(item.dueDate.toIso8601String(), dueDate)) {
              return false;
            }
            return true;
          },
          orElse: () => null,
        );
    if (invoice == null) {
      return _failed('تعذر العثور على الفاتورة بعد التنفيذ.');
    }
    return _success(
      message: 'تم التحقق من الفاتورة من المصدر بعد التنفيذ.',
      reference: <String, dynamic>{
        'invoice_id': invoice.id,
        'invoice_serial_no': invoice.serialNo,
      },
    );
  }

  Map<String, dynamic> _verifyPayment(
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _invoicesBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق الفواتير للتحقق من الدفعة.');
    }
    final payload = _payload(executionPayload);
    final serial =
        (normalizedArguments['invoiceSerialNo'] ?? payload['invoice_serial_no'] ?? '')
            .toString()
            .trim();
    if (serial.isEmpty) {
      return _failed('لا توجد فاتورة واضحة للتحقق من الدفعة.');
    }
    final invoice = box.values.cast<Invoice?>().firstWhere(
          (item) => item != null && (item.serialNo ?? '').trim() == serial,
          orElse: () => null,
        );
    if (invoice == null) {
      return _failed('تعذر العثور على الفاتورة بعد تسجيل الدفعة.');
    }
    final amount = (normalizedArguments['amount'] as num?)?.toDouble() ??
        (payload['expected_payment_amount'] as num?)?.toDouble() ??
        0;
    final beforePaidAmount =
        (payload['before_paid_amount'] as num?)?.toDouble();
    if (beforePaidAmount != null) {
      final expectedPaid = beforePaidAmount + amount;
      if (invoice.paidAmount + 0.001 < expectedPaid) {
        return _failed('لم تؤكد قراءة الفاتورة زيادة السداد بالمبلغ المطلوب.');
      }
    } else if (invoice.paidAmount + 0.001 < amount) {
      return _failed('لم تؤكد قراءة الفاتورة وجود المبلغ المدفوع.');
    }
    return _success(
      message: 'تم التحقق من الفاتورة المحدّثة بعد تسجيل الدفعة.',
      reference: <String, dynamic>{
        'invoice_id': invoice.id,
        'invoice_serial_no': invoice.serialNo,
      },
    );
  }

  Map<String, dynamic> _verifyMaintenance(
    Map<String, dynamic> normalizedArguments,
    Map<String, dynamic> executionPayload,
  ) {
    final box = _maintenanceBox();
    if (box == null) {
      return _failed('تعذر فتح صندوق الصيانة للتحقق.');
    }
    final payload = _payload(executionPayload);
    final requestId =
        (payload['requestId'] ?? payload['request_id'] ?? payload['maintenance_id'] ?? '')
            .toString()
            .trim();
    MaintenanceRequest? request;
    if (requestId.isNotEmpty) {
      request = box.get(requestId);
    }
    final requestedTitle =
        (normalizedArguments['title'] ?? normalizedArguments['query'] ?? '')
            .toString()
            .trim();
    request ??= box.values.cast<MaintenanceRequest?>().firstWhere(
          (item) => item != null && requestedTitle.isNotEmpty && item.title.trim() == requestedTitle,
          orElse: () => null,
        );
    if (request == null) {
      return _failed('تعذر العثور على طلب الصيانة بعد التنفيذ.');
    }
    if (requestedTitle.isNotEmpty && request.title.trim() != requestedTitle) {
      return _failed('تم التنفيذ لكن عنوان طلب الصيانة المقروء لا يطابق المطلوب.');
    }
    final requestedStatus = (normalizedArguments['status'] ?? '').toString().trim();
    if (requestedStatus.isNotEmpty && _enumName(request.status) != requestedStatus) {
      return _failed('تم التنفيذ لكن حالة طلب الصيانة المقروءة لا تطابق المطلوب.');
    }
    final requestedPriority =
        (normalizedArguments['priority'] ?? '').toString().trim();
    if (requestedPriority.isNotEmpty &&
        _enumName(request.priority) != requestedPriority) {
      return _failed('تم التنفيذ لكن أولوية طلب الصيانة المقروءة لا تطابق المطلوب.');
    }
    final requestedPropertyId =
        (normalizedArguments['property_id'] ?? '').toString().trim();
    if (requestedPropertyId.isNotEmpty && request.propertyId != requestedPropertyId) {
      return _failed('تم التنفيذ لكن العقار المرتبط بطلب الصيانة لا يطابق المطلوب.');
    }
    return _success(
      message: 'تم التحقق من طلب الصيانة من المصدر بعد التنفيذ.',
      reference: <String, dynamic>{
        'maintenance_id': request.id,
        'maintenance_serial_no': request.serialNo,
      },
    );
  }

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

  Map<String, dynamic> _payload(Map<String, dynamic> executionPayload) {
    return Map<String, dynamic>.from(
      executionPayload['payload'] as Map? ?? const <String, dynamic>{},
    );
  }

  Property? _findPropertyByExactName(Iterable<Property> values, String query) {
    final text = query.trim();
    if (text.isEmpty) return null;
    for (final item in values) {
      if (item.name.trim() == text) return item;
    }
    for (final item in values) {
      if (item.name.trim().toLowerCase().contains(text.toLowerCase())) {
        return item;
      }
    }
    return null;
  }

  Tenant? _findTenant(
    Iterable<Tenant> values, {
    required String name,
    required String phone,
    required String nationalId,
    required String query,
  }) {
    for (final tenant in values) {
      if (name.isNotEmpty && tenant.fullName.trim() != name) continue;
      if (phone.isNotEmpty && tenant.phone.trim() != phone) continue;
      if (nationalId.isNotEmpty && tenant.nationalId.trim() != nationalId) continue;
      if (name.isNotEmpty || phone.isNotEmpty || nationalId.isNotEmpty) {
        return tenant;
      }
    }
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return null;
    for (final tenant in values) {
      if (tenant.fullName.toLowerCase().contains(text) ||
          tenant.phone.contains(query) ||
          tenant.nationalId.contains(query)) {
        return tenant;
      }
    }
    return null;
  }

  Contract? _findContract(
    Iterable<Contract> values, {
    required String serial,
  }) {
    if (serial.isEmpty) return null;
    for (final contract in values) {
      if ((contract.serialNo ?? '').trim() == serial) {
        return contract;
      }
    }
    for (final contract in values) {
      if ((contract.serialNo ?? '').toLowerCase().contains(serial.toLowerCase())) {
        return contract;
      }
    }
    return null;
  }

  bool _sameYmd(String a, String b) {
    if (a.length < 10 || b.length < 10) return false;
    return a.substring(0, 10) == b.substring(0, 10);
  }

  String _enumName(dynamic value) {
    if (value == null) return '';
    if (value is Enum) return value.name;
    final text = value.toString();
    if (text.contains('.')) {
      return text.split('.').last;
    }
    return text;
  }

  Map<String, dynamic> _success({
    required String message,
    required Map<String, dynamic> reference,
  }) {
    return <String, dynamic>{
      'verified': true,
      'message': message,
      'result_reference': reference,
    };
  }

  Map<String, dynamic> _failed(String message) {
    return <String, dynamic>{
      'verified': false,
      'message': message,
      'result_reference': const <String, dynamic>{},
    };
  }
}
