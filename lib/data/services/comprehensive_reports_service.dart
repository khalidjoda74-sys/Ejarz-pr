import 'package:darvoo/utils/ksa_time.dart';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Listenable, ValueNotifier;
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/tenant.dart';
import '../../ui/contracts_screen.dart'
    show Contract, ContractTerm, PaymentCycle;
import '../../ui/invoices_screen.dart' show Invoice;
import '../../ui/maintenance_screen.dart' show MaintenanceRequest;
import '../../utils/contract_utils.dart'
    show
        countDueTodayPayments,
        countNearDuePayments,
        countOverduePayments,
        perCycleAmountForContract;
import '../constants/boxes.dart';
import 'entity_audit_service.dart';
import 'hive_service.dart';
import 'user_scope.dart';

enum CommissionMode { unspecified, percent, fixed }

enum CommissionScope { global, owner, property, contract }

enum VoucherDirection { receipt, payment }

enum VoucherState { draft, posted, cancelled, reversed }

enum VoucherSource {
  contracts,
  services,
  maintenance,
  ownerPayout,
  ownerAdjustment,
  officeCommission,
  officeWithdrawal,
  manual,
  other,
}

enum OwnerPayoutStatus { draft, posted, cancelled, reversed }

enum OwnerAdjustmentCategory {
  ownerDiscount,
  adminDiscount,
  paymentSettlement,
  other,
}

extension CommissionModeLabel on CommissionMode {
  String get arLabel {
    switch (this) {
      case CommissionMode.unspecified:
        return 'غير محدد';
      case CommissionMode.percent:
        return 'نسبة';
      case CommissionMode.fixed:
        return 'مبلغ ثابت';
    }
  }
}

extension CommissionScopeLabel on CommissionScope {
  String get arLabel {
    switch (this) {
      case CommissionScope.global:
        return 'عام';
      case CommissionScope.owner:
        return 'مالك';
      case CommissionScope.property:
        return 'عقار';
      case CommissionScope.contract:
        return 'عقد';
    }
  }
}

extension VoucherDirectionLabel on VoucherDirection {
  String get arLabel {
    switch (this) {
      case VoucherDirection.receipt:
        return 'قبض';
      case VoucherDirection.payment:
        return 'صرف';
    }
  }
}

extension VoucherStateLabel on VoucherState {
  String get arLabel {
    switch (this) {
      case VoucherState.draft:
        return 'مسودة';
      case VoucherState.posted:
        return 'معتمد';
      case VoucherState.cancelled:
        return 'ملغي';
      case VoucherState.reversed:
        return 'معكوس';
    }
  }
}

extension VoucherSourceLabel on VoucherSource {
  String get arLabel {
    switch (this) {
      case VoucherSource.contracts:
        return 'عقود';
      case VoucherSource.services:
        return 'خدمات';
      case VoucherSource.maintenance:
        return 'خدمات';
      case VoucherSource.ownerPayout:
        return 'تحويل للمالك';
      case VoucherSource.ownerAdjustment:
        return 'خصم/تسوية مالك';
      case VoucherSource.officeCommission:
        return 'عمولة مكتب';
      case VoucherSource.officeWithdrawal:
        return 'تحويل من رصيد المكتب';
      case VoucherSource.manual:
        return 'يدوي';
      case VoucherSource.other:
        return 'أخرى';
    }
  }
}

extension OwnerAdjustmentCategoryLabel on OwnerAdjustmentCategory {
  String get arLabel {
    switch (this) {
      case OwnerAdjustmentCategory.ownerDiscount:
        return 'خصم مستحق المالك';
      case OwnerAdjustmentCategory.adminDiscount:
        return 'خصم إداري';
      case OwnerAdjustmentCategory.paymentSettlement:
        return 'تسوية دفعة';
      case OwnerAdjustmentCategory.other:
        return 'أخرى';
    }
  }
}

extension OwnerPayoutStatusLabel on OwnerPayoutStatus {
  String get arLabel {
    switch (this) {
      case OwnerPayoutStatus.draft:
        return 'مسودة';
      case OwnerPayoutStatus.posted:
        return 'مرحّل';
      case OwnerPayoutStatus.cancelled:
        return 'ملغي';
      case OwnerPayoutStatus.reversed:
        return 'معكوس';
    }
  }
}

class CommissionRule {
  final CommissionMode mode;
  final double value;

  const CommissionRule({
    required this.mode,
    required this.value,
  });

  static const CommissionRule zero =
      CommissionRule(mode: CommissionMode.unspecified, value: 0);

  bool get isEnabled {
    switch (mode) {
      case CommissionMode.unspecified:
        return false;
      case CommissionMode.percent:
        return value > 0;
      case CommissionMode.fixed:
        return true;
    }
  }

  double apply(num baseAmount) {
    final base = baseAmount.toDouble().abs();
    if (base <= 0 || value <= 0) return 0;
    switch (mode) {
      case CommissionMode.unspecified:
        return 0;
      case CommissionMode.percent:
        return (base * value / 100).clamp(0, base).toDouble();
      case CommissionMode.fixed:
        return value.clamp(0, base).toDouble();
    }
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        'value': value,
      };

  factory CommissionRule.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return CommissionRule.zero;
    final modeRaw = (map['mode'] ?? '').toString();
    final CommissionMode mode;
    if (modeRaw == CommissionMode.fixed.name) {
      mode = CommissionMode.fixed;
    } else if (modeRaw == CommissionMode.percent.name) {
      mode = CommissionMode.percent;
    } else {
      mode = CommissionMode.unspecified;
    }
    final value = _toDouble(map['value']);
    return CommissionRule(mode: mode, value: value);
  }
}

class ComprehensiveReportFilters {
  final DateTime? from;
  final DateTime? to;
  final String? propertyId;
  final String? ownerId;
  final String? contractId;
  final String? serviceType;
  final String? contractStatus;
  final VoucherState? voucherState;
  final VoucherSource? voucherSource;
  final bool includeDraft;
  final bool includeCancelled;

  const ComprehensiveReportFilters({
    this.from,
    this.to,
    this.propertyId,
    this.ownerId,
    this.contractId,
    this.serviceType,
    this.contractStatus,
    this.voucherState,
    this.voucherSource,
    this.includeDraft = true,
    this.includeCancelled = false,
  });

  ComprehensiveReportFilters copyWith({
    DateTime? from,
    DateTime? to,
    String? propertyId,
    String? ownerId,
    String? contractId,
    String? serviceType,
    String? contractStatus,
    VoucherState? voucherState,
    VoucherSource? voucherSource,
    bool? includeDraft,
    bool? includeCancelled,
    bool clearProperty = false,
    bool clearOwner = false,
    bool clearContract = false,
    bool clearService = false,
    bool clearContractStatus = false,
    bool clearVoucherState = false,
    bool clearVoucherSource = false,
  }) {
    return ComprehensiveReportFilters(
      from: from ?? this.from,
      to: to ?? this.to,
      propertyId: clearProperty ? null : (propertyId ?? this.propertyId),
      ownerId: clearOwner ? null : (ownerId ?? this.ownerId),
      contractId: clearContract ? null : (contractId ?? this.contractId),
      serviceType: clearService ? null : (serviceType ?? this.serviceType),
      contractStatus:
          clearContractStatus ? null : (contractStatus ?? this.contractStatus),
      voucherState:
          clearVoucherState ? null : (voucherState ?? this.voucherState),
      voucherSource:
          clearVoucherSource ? null : (voucherSource ?? this.voucherSource),
      includeDraft: includeDraft ?? this.includeDraft,
      includeCancelled: includeCancelled ?? this.includeCancelled,
    );
  }

  bool inRange(DateTime? date) {
    if (date == null) return true;
    final d = _dateOnly(date);
    if (from != null && d.isBefore(_dateOnly(from!))) return false;
    if (to != null && d.isAfter(_dateOnly(to!))) return false;
    return true;
  }
}

class DashboardSummary {
  final double totalReceipts;
  final double totalExpenses;
  final double netCashFlow;
  final double rentCollected;
  final double officeCommissions;
  final double ownerTransferred;
  final double unpaidServiceBills;
  final int approvedVouchers;
  final int approvedReceiptVouchers;
  final int approvedPaymentVouchers;

  const DashboardSummary({
    required this.totalReceipts,
    required this.totalExpenses,
    required this.netCashFlow,
    required this.rentCollected,
    required this.officeCommissions,
    required this.ownerTransferred,
    required this.unpaidServiceBills,
    required this.approvedVouchers,
    required this.approvedReceiptVouchers,
    required this.approvedPaymentVouchers,
  });
}

class PropertyReportItem {
  final String propertyId;
  final String propertyName;
  final String ownerId;
  final String ownerName;
  final PropertyType type; // جديد
  final bool isOccupied; // جديد
  final int activeContracts;
  final int endedContracts;
  final int receivedPayments;
  final int latePayments;
  final int upcomingPayments;
  final int linkedVouchers;
  final double revenues;
  final double expenses;
  final double serviceExpenses;
  final double overdueAmount;
  final double net;

  const PropertyReportItem({
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
    required this.ownerName,
    required this.type,
    required this.isOccupied,
    required this.activeContracts,
    required this.endedContracts,
    required this.receivedPayments,
    required this.latePayments,
    required this.upcomingPayments,
    required this.linkedVouchers,
    required this.revenues,
    required this.expenses,
    required this.serviceExpenses,
    required this.overdueAmount,
    required this.net,
  });
}

class ContractReportItem {
  final String contractId;
  final String contractNo;
  final String propertyId;
  final String propertyName;
  final String tenantId;
  final String tenantName;
  final String ownerId;
  final String ownerName;
  final String status;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final int overdueInstallments;
  final int upcomingInstallments;
  final DateTime? nextDueDate;
  final int linkedVouchers;
  final double overdueAmount;

  const ContractReportItem({
    required this.contractId,
    required this.contractNo,
    required this.propertyId,
    required this.propertyName,
    required this.tenantId,
    required this.tenantName,
    required this.ownerId,
    required this.ownerName,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.overdueInstallments,
    required this.upcomingInstallments,
    required this.nextDueDate,
    required this.linkedVouchers,
    required this.overdueAmount,
  });
}

class ServiceReportItem {
  final String id;
  final String serviceType;
  final String propertyId;
  final String propertyName;
  final String ownerId;
  final String ownerName;
  final DateTime date;
  final double amount;
  final bool isPaid;
  final VoucherState state;
  final String statusLabel;
  final String linkedVoucherId;
  final String details;

  const ServiceReportItem({
    required this.id,
    required this.serviceType,
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
    required this.ownerName,
    required this.date,
    required this.amount,
    required this.isPaid,
    required this.state,
    required this.statusLabel,
    required this.linkedVoucherId,
    required this.details,
  });
}

class OwnerLedgerEntry {
  final String id;
  final DateTime date;
  final DateTime sortDate;
  final String description;
  final String type;
  final double debit;
  final double credit;
  final String referenceId;
  final double balanceAfter;
  final VoucherState? voucherState;

  const OwnerLedgerEntry({
    required this.id,
    required this.date,
    required this.sortDate,
    required this.description,
    required this.type,
    required this.debit,
    required this.credit,
    required this.referenceId,
    required this.balanceAfter,
    this.voucherState,
  });
}

class OwnerPropertyReportItem {
  final String propertyId;
  final String propertyName;
  final double rentCollected;
  final double officeCommissions;
  final double ownerExpenses;
  final double ownerAdjustments;
  final double previousTransfers;
  final double currentBalance;
  final double readyForPayout;

  const OwnerPropertyReportItem({
    required this.propertyId,
    required this.propertyName,
    required this.rentCollected,
    required this.officeCommissions,
    required this.ownerExpenses,
    required this.ownerAdjustments,
    required this.previousTransfers,
    required this.currentBalance,
    required this.readyForPayout,
  });
}

class OwnerReportItem {
  final String ownerId;
  final String ownerName;
  final double previousBalance;
  final double rentCollected;
  final double officeCommissions;
  final double ownerExpenses;
  final double ownerAdjustments;
  final double previousTransfers;
  final double currentBalance;
  final double readyForPayout;
  final List<OwnerLedgerEntry> ledger;
  final int linkedProperties;
  final List<OwnerPropertyReportItem> propertyBreakdowns;

  const OwnerReportItem({
    required this.ownerId,
    required this.ownerName,
    required this.previousBalance,
    required this.rentCollected,
    required this.officeCommissions,
    required this.ownerExpenses,
    required this.ownerAdjustments,
    required this.previousTransfers,
    required this.currentBalance,
    required this.readyForPayout,
    required this.ledger,
    required this.linkedProperties,
    required this.propertyBreakdowns,
  });
}

class OwnerSettlementPreview {
  final String ownerId;
  final String ownerName;
  final double previousBalance;
  final double collectedRent;
  final double deductedCommission;
  final double deductedExpenses;
  final double deductedAdjustments;
  final double previousPayouts;
  final double readyForPayout;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  const OwnerSettlementPreview({
    required this.ownerId,
    required this.ownerName,
    required this.previousBalance,
    required this.collectedRent,
    required this.deductedCommission,
    required this.deductedExpenses,
    required this.deductedAdjustments,
    required this.previousPayouts,
    required this.readyForPayout,
    required this.periodFrom,
    required this.periodTo,
  });
}

class OfficeSettlementPreview {
  final double netProfit;
  final double previousWithdrawals;
  final double currentBalance;
  final double readyForWithdrawal;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  const OfficeSettlementPreview({
    required this.netProfit,
    required this.previousWithdrawals,
    required this.currentBalance,
    required this.readyForWithdrawal,
    required this.periodFrom,
    required this.periodTo,
  });
}

class OfficeLedgerEntry {
  final String id;
  final DateTime date;
  final DateTime sortDate;
  final String description;
  final String type;
  final double debit;
  final double credit;
  final String referenceId;
  final double balanceAfter;
  final VoucherState? voucherState;

  const OfficeLedgerEntry({
    required this.id,
    required this.date,
    required this.sortDate,
    required this.description,
    required this.type,
    required this.debit,
    required this.credit,
    required this.referenceId,
    required this.balanceAfter,
    this.voucherState,
  });
}

class OfficeReportSummary {
  final double commissionRevenue;
  final double officeExpenses;
  final double officeWithdrawals;
  final double netProfit;
  final double currentBalance;
  final int receiptVouchers;
  final int paymentVouchers;
  final List<OfficeLedgerEntry> ledger;

  const OfficeReportSummary({
    required this.commissionRevenue,
    required this.officeExpenses,
    required this.officeWithdrawals,
    required this.netProfit,
    required this.currentBalance,
    required this.receiptVouchers,
    required this.paymentVouchers,
    required this.ledger,
  });
}

class VoucherReportItem {
  final String id;
  final String serialNo;
  final DateTime date;
  final DateTime createdAt;
  final String contractId;
  final String propertyId;
  final String tenantId;
  final double amount;
  final double paidAmount;
  final String paymentMethod;
  final String note;
  final VoucherDirection direction;
  final VoucherState state;
  final VoucherSource source;
  final bool isServiceInvoice;

  const VoucherReportItem({
    required this.id,
    required this.serialNo,
    required this.date,
    required this.createdAt,
    required this.contractId,
    required this.propertyId,
    required this.tenantId,
    required this.amount,
    required this.paidAmount,
    required this.paymentMethod,
    required this.note,
    required this.direction,
    required this.state,
    required this.source,
    required this.isServiceInvoice,
  });
}

class OwnerPayoutRecord {
  final String id;
  final String ownerId;
  final String ownerName;
  final String propertyId;
  final double amount;
  final OwnerPayoutStatus status;
  final DateTime createdAt;
  final DateTime? postedAt;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final String note;
  final String voucherId;
  final String voucherSerialNo;

  const OwnerPayoutRecord({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.propertyId,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.postedAt,
    required this.periodFrom,
    required this.periodTo,
    required this.note,
    required this.voucherId,
    required this.voucherSerialNo,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'propertyId': propertyId,
        'amount': amount,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'postedAt': postedAt?.millisecondsSinceEpoch,
        'periodFrom': periodFrom?.millisecondsSinceEpoch,
        'periodTo': periodTo?.millisecondsSinceEpoch,
        'note': note,
        'voucherId': voucherId,
        'voucherSerialNo': voucherSerialNo,
      };

  factory OwnerPayoutRecord.fromMap(Map<dynamic, dynamic> map) {
    final statusRaw = (map['status'] ?? '').toString();
    final status = OwnerPayoutStatus.values.firstWhere(
      (e) => e.name == statusRaw,
      orElse: () => OwnerPayoutStatus.draft,
    );
    return OwnerPayoutRecord(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      propertyId: (map['propertyId'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      status: status,
      createdAt: _dateFromAny(map['createdAt']) ?? KsaTime.now(),
      postedAt: _dateFromAny(map['postedAt']),
      periodFrom: _dateFromAny(map['periodFrom']),
      periodTo: _dateFromAny(map['periodTo']),
      note: (map['note'] ?? '').toString(),
      voucherId: (map['voucherId'] ?? '').toString(),
      voucherSerialNo: (map['voucherSerialNo'] ?? '').toString(),
    );
  }

  OwnerPayoutRecord copyWith({
    OwnerPayoutStatus? status,
  }) {
    return OwnerPayoutRecord(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      amount: amount,
      status: status ?? this.status,
      createdAt: createdAt,
      postedAt: postedAt,
      periodFrom: periodFrom,
      periodTo: periodTo,
      note: note,
      voucherId: voucherId,
      voucherSerialNo: voucherSerialNo,
    );
  }
}

class OwnerAdjustmentRecord {
  final String id;
  final String ownerId;
  final String ownerName;
  final String propertyId;
  final double amount;
  final OwnerAdjustmentCategory category;
  final OwnerPayoutStatus status;
  final DateTime createdAt;
  final DateTime? postedAt;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final String note;
  final String voucherId;

  const OwnerAdjustmentRecord({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.propertyId,
    required this.amount,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.postedAt,
    required this.periodFrom,
    required this.periodTo,
    required this.note,
    required this.voucherId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'propertyId': propertyId,
        'amount': amount,
        'category': category.name,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'postedAt': postedAt?.millisecondsSinceEpoch,
        'periodFrom': periodFrom?.millisecondsSinceEpoch,
        'periodTo': periodTo?.millisecondsSinceEpoch,
        'note': note,
        'voucherId': voucherId,
      };

  factory OwnerAdjustmentRecord.fromMap(Map<dynamic, dynamic> map) {
    final statusRaw = (map['status'] ?? '').toString();
    final status = OwnerPayoutStatus.values.firstWhere(
      (e) => e.name == statusRaw,
      orElse: () => OwnerPayoutStatus.draft,
    );
    final categoryRaw = (map['category'] ?? '').toString();
    final category = OwnerAdjustmentCategory.values.firstWhere(
      (e) => e.name == categoryRaw,
      orElse: () => OwnerAdjustmentCategory.ownerDiscount,
    );
    return OwnerAdjustmentRecord(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      propertyId: (map['propertyId'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      category: category,
      status: status,
      createdAt: _dateFromAny(map['createdAt']) ?? KsaTime.now(),
      postedAt: _dateFromAny(map['postedAt']),
      periodFrom: _dateFromAny(map['periodFrom']),
      periodTo: _dateFromAny(map['periodTo']),
      note: (map['note'] ?? '').toString(),
      voucherId: (map['voucherId'] ?? '').toString(),
    );
  }

  OwnerAdjustmentRecord copyWith({
    OwnerPayoutStatus? status,
  }) {
    return OwnerAdjustmentRecord(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      amount: amount,
      category: category,
      status: status ?? this.status,
      createdAt: createdAt,
      postedAt: postedAt,
      periodFrom: periodFrom,
      periodTo: periodTo,
      note: note,
      voucherId: voucherId,
    );
  }
}

class OwnerBankAccountRecord {
  final String id;
  final String ownerId;
  final String ownerName;
  final String bankName;
  final String accountNumber;
  final String iban;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OwnerBankAccountRecord({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.bankName,
    required this.accountNumber,
    required this.iban,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'bankName': bankName,
        'accountNumber': accountNumber,
        'iban': iban,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory OwnerBankAccountRecord.fromMap(Map<dynamic, dynamic> map) {
    final now = KsaTime.now();
    return OwnerBankAccountRecord(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      bankName: (map['bankName'] ?? '').toString(),
      accountNumber: (map['accountNumber'] ?? '').toString(),
      iban: (map['iban'] ?? '').toString(),
      createdAt: _dateFromAny(map['createdAt']) ?? now,
      updatedAt: _dateFromAny(map['updatedAt']) ?? now,
    );
  }
}

class ComprehensiveReportSnapshot {
  final DashboardSummary dashboard;
  final List<PropertyReportItem> properties;
  final List<ContractReportItem> contracts;
  final List<ServiceReportItem> services;
  final List<OwnerReportItem> owners;
  final OfficeReportSummary office;
  final List<VoucherReportItem> vouchers;
  final List<OwnerPayoutRecord> ownerPayouts;
  final List<OwnerAdjustmentRecord> ownerAdjustments;
  final Map<String, String> propertyNames;
  final Map<String, String> ownerNames;
  final Map<String, String> tenantNames;
  final Map<String, String> contractNumbers;

  const ComprehensiveReportSnapshot({
    required this.dashboard,
    required this.properties,
    required this.contracts,
    required this.services,
    required this.owners,
    required this.office,
    required this.vouchers,
    required this.ownerPayouts,
    required this.ownerAdjustments,
    required this.propertyNames,
    required this.ownerNames,
    required this.tenantNames,
    required this.contractNumbers,
  });
}

class ComprehensiveReportsService {
  static const String _financeConfigBoxBase = 'financeConfigBox';
  static const String _propertyOwnersBoxBase = 'propertyOwnersBox';
  static const String _ownerPayoutsBoxBase = 'ownerPayoutsBox';
  static const String _ownerAdjustmentsBoxBase = 'ownerAdjustmentsBox';
  static const String _ownerBankAccountsBoxBase = 'ownerBankAccountsBox';
  static const String _financeConfigAuditCollectionName = 'financeConfig';
  static const String _ownerBankAccountsAuditCollectionName =
      'ownerBankAccounts';

  static String get _financeConfigBoxName => boxName(_financeConfigBoxBase);
  static String get _propertyOwnersBoxName => boxName(_propertyOwnersBoxBase);
  static String get _ownerPayoutsBoxName => boxName(_ownerPayoutsBoxBase);
  static String get _ownerAdjustmentsBoxName =>
      boxName(_ownerAdjustmentsBoxBase);
  static String get _ownerBankAccountsBoxName =>
      boxName(_ownerBankAccountsBoxBase);

  static Future<void> ensureFinanceBoxesOpen() async {
    await _ensureMapBox(_financeConfigBoxName);
    await _ensureMapBox(_propertyOwnersBoxName);
    await _ensureMapBox(_ownerPayoutsBoxName);
    await _ensureMapBox(_ownerAdjustmentsBoxName);
    await _ensureMapBox(_ownerBankAccountsBoxName);
  }

  static Listenable financeListenable() {
    final a = _mapBoxIfOpen(_financeConfigBoxName)?.listenable() ??
        ValueNotifier<bool>(false);
    final b = _mapBoxIfOpen(_propertyOwnersBoxName)?.listenable() ??
        ValueNotifier<bool>(false);
    final c = _mapBoxIfOpen(_ownerPayoutsBoxName)?.listenable() ??
        ValueNotifier<bool>(false);
    final d = _mapBoxIfOpen(_ownerAdjustmentsBoxName)?.listenable() ??
        ValueNotifier<bool>(false);
    final e = _mapBoxIfOpen(_ownerBankAccountsBoxName)?.listenable() ??
        ValueNotifier<bool>(false);
    return Listenable.merge(<Listenable>[a, b, c, d, e]);
  }

  static Future<void> _recordLocalAudit({
    required String collectionName,
    required String entityId,
    required bool isCreate,
  }) async {
    final workspaceUid = effectiveUid().trim();
    if (workspaceUid.isEmpty || workspaceUid == 'guest') return;
    await EntityAuditService.instance.recordLocalAudit(
      workspaceUid: workspaceUid,
      collectionName: collectionName,
      entityId: entityId,
      isCreate: isCreate,
    );
  }

  static Future<void> assignPropertyOwner({
    required String propertyId,
    required String ownerId,
    String? ownerName,
  }) async {
    if (propertyId.trim().isEmpty || ownerId.trim().isEmpty) return;
    await ensureFinanceBoxesOpen();
    final box = Hive.box(_propertyOwnersBoxName);
    await box.put(propertyId.trim(), {
      'ownerId': ownerId.trim(),
      'ownerName': (ownerName ?? '').trim(),
      'updatedAt': KsaTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> clearPropertyOwner(String propertyId) async {
    if (propertyId.trim().isEmpty) return;
    await ensureFinanceBoxesOpen();
    final box = Hive.box(_propertyOwnersBoxName);
    await box.delete(propertyId.trim());
  }

  static Future<void> setCommissionRule({
    required CommissionScope scope,
    String? scopeId,
    required CommissionRule rule,
  }) async {
    await ensureFinanceBoxesOpen();
    final key = _commissionKey(scope, scopeId);
    final box = Hive.box(_financeConfigBoxName);
    final previousRaw = box.get(key);
    final isCreate = previousRaw == null;
    final previous = CommissionRule.fromMap(previousRaw);
    final changed = isCreate ||
        previous.mode != rule.mode ||
        (previous.value - rule.value).abs() > 0.000001;
    if (!changed) return;
    if (scope == CommissionScope.global) {
      if (previous.mode == CommissionMode.percent) {
        await syncOfficeCommissionVouchers();
      }
    }
    await box.put(key, rule.toMap());
    await _recordLocalAudit(
      collectionName: _financeConfigAuditCollectionName,
      entityId: key,
      isCreate: isCreate,
    );
  }

  static Future<CommissionRule> getCommissionRule({
    required CommissionScope scope,
    String? scopeId,
  }) async {
    await ensureFinanceBoxesOpen();
    final key = _commissionKey(scope, scopeId);
    final box = Hive.box(_financeConfigBoxName);
    final raw = box.get(key);
    return CommissionRule.fromMap(raw);
  }

  static Future<OwnerSettlementPreview> previewOwnerSettlement({
    required String ownerId,
    ComprehensiveReportFilters filters = const ComprehensiveReportFilters(),
  }) async {
    final snapshot = await load(filters);
    final owner = snapshot.owners.firstWhere(
      (e) => e.ownerId == ownerId,
      orElse: () => OwnerReportItem(
        ownerId: ownerId,
        ownerName: snapshot.ownerNames[ownerId] ?? ownerId,
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
    return OwnerSettlementPreview(
      ownerId: owner.ownerId,
      ownerName: owner.ownerName,
      previousBalance: owner.previousBalance,
      collectedRent: owner.rentCollected,
      deductedCommission: owner.officeCommissions,
      deductedExpenses: owner.ownerExpenses,
      deductedAdjustments: owner.ownerAdjustments,
      previousPayouts: owner.previousTransfers,
      readyForPayout: owner.readyForPayout,
      periodFrom: filters.from,
      periodTo: filters.to,
    );
  }

  static Future<OfficeSettlementPreview> previewOfficeSettlement({
    ComprehensiveReportFilters filters = const ComprehensiveReportFilters(),
  }) async {
    final snapshot = await load(filters);
    final office = snapshot.office;
    return OfficeSettlementPreview(
      netProfit: office.netProfit,
      previousWithdrawals: office.officeWithdrawals,
      currentBalance: office.currentBalance,
      readyForWithdrawal: math.max(0, office.currentBalance).toDouble(),
      periodFrom: filters.from,
      periodTo: filters.to,
    );
  }

  static String _buildOwnerVoucherNote({
    required String sourceMarker,
    required String description,
    required String ownerId,
    required String ownerName,
    String propertyId = '',
    String propertyName = '',
    String note = '',
    String? recordIdMarker,
    String? recordIdValue,
    String? categoryMarker,
    String? categoryValue,
  }) {
    final lines = <String>[
      '[MANUAL]',
      '[PARTY: ${ownerName.trim()}]',
      '[PARTY_ID: ${ownerId.trim()}]',
      sourceMarker.trim(),
    ];
    final cleanPropertyName = _normalizeOwnerVoucherPropertyName(propertyName);
    final cleanPropertyId = propertyId.trim();
    final cleanRecordIdMarker = (recordIdMarker ?? '').trim();
    final cleanRecordIdValue = (recordIdValue ?? '').trim();
    final cleanCategoryMarker = (categoryMarker ?? '').trim();
    final cleanCategoryValue = (categoryValue ?? '').trim();
    final cleanDescription = description.trim();
    final cleanNote = note.trim();

    if (cleanPropertyName.isNotEmpty) {
      lines.add('[PROPERTY: $cleanPropertyName]');
    }
    if (cleanPropertyId.isNotEmpty) {
      lines.add('[PROPERTY_ID: $cleanPropertyId]');
    }
    if (cleanRecordIdMarker.isNotEmpty && cleanRecordIdValue.isNotEmpty) {
      lines.add('[$cleanRecordIdMarker: $cleanRecordIdValue]');
    }
    if (cleanCategoryMarker.isNotEmpty && cleanCategoryValue.isNotEmpty) {
      lines.add('[$cleanCategoryMarker: $cleanCategoryValue]');
    }
    if (cleanDescription.isNotEmpty) {
      lines.add(cleanDescription);
    }
    if (cleanNote.isNotEmpty) {
      lines.add(cleanNote);
    }
    return lines.join('\n').trim();
  }

  static String _normalizeOwnerVoucherPropertyName(String value) {
    final text = value.trim();
    if (text == 'جميع العقارات معًا' || text == 'إظهار جميع العقارات معًا') {
      return '';
    }
    return text;
  }

  static String _buildOfficeCommissionVoucherNote({
    required String contractVoucherId,
    required String description,
  }) {
    final lines = <String>[
      '[OFFICE_COMMISSION]',
      '[CONTRACT_VOUCHER_ID: ${contractVoucherId.trim()}]',
    ];
    final cleanDescription = description.trim();
    if (cleanDescription.isNotEmpty) {
      lines.add(cleanDescription);
    }
    return lines.join('\n').trim();
  }

  static String _officeCommissionLinkedContractVoucherId(String? note) {
    return (_manualVoucherMarkerValue(note, 'CONTRACT_VOUCHER_ID') ?? '').trim();
  }

  static bool _isOfficeCommissionInvoice(Invoice invoice) {
    return (invoice.note ?? '').toLowerCase().contains('[office_commission]');
  }

  static String _appendVoucherNoteLine(String? current, String line) {
    final cleanLine = line.trim();
    if (cleanLine.isEmpty) return (current ?? '').trim();
    final base = (current ?? '').trim();
    if (base.toLowerCase().contains(cleanLine.toLowerCase())) {
      return base;
    }
    if (base.isEmpty) return cleanLine;
    return '$base\n$cleanLine';
  }

  static String _officeCommissionDescription({
    required String contractNo,
    required String propertyName,
  }) {
    final normalizedContractNo = contractNo.trim();
    final normalizedPropertyName = propertyName.trim();
    final base = normalizedContractNo.isNotEmpty
        ? 'عمولة مكتب من سداد عقد رقم $normalizedContractNo'
        : 'عمولة مكتب من سداد عقد';
    if (normalizedPropertyName.isEmpty) return base;
    return '$base • $normalizedPropertyName';
  }

  static String _officeCommissionContractReference(
    Contract? contract, {
    Box<String>? ejarMapBox,
  }) {
    final directEjarNo = (contract?.ejarContractNo ?? '').trim();
    if (directEjarNo.isNotEmpty) return directEjarNo;

    final contractId = (contract?.id ?? '').trim();
    if (contractId.isNotEmpty && ejarMapBox != null) {
      final localEjarNo = (ejarMapBox.get(contractId) ?? '').trim();
      if (localEjarNo.isNotEmpty) return localEjarNo;
    }

    return (contract?.serialNo ?? '').trim();
  }

  static String _officeCommissionPropertyReference(
    String propertyId,
    Map<String, Property> propertyById,
  ) {
    final normalizedPropertyId = propertyId.trim();
    if (normalizedPropertyId.isEmpty) return '';

    final property = propertyById[normalizedPropertyId];
    if (property == null) return normalizedPropertyId;

    final unitName = property.name.trim();
    final parentId = (property.parentBuildingId ?? '').trim();
    if (parentId.isEmpty) return unitName.isNotEmpty ? unitName : normalizedPropertyId;

    final buildingName = (propertyById[parentId]?.name ?? '').trim();
    if (buildingName.isEmpty) {
      return unitName.isNotEmpty ? unitName : normalizedPropertyId;
    }
    if (unitName.isEmpty || unitName == buildingName) {
      return buildingName;
    }
    return '$buildingName ($unitName)';
  }

  static String _cleanVoucherDisplayNote(String? note) {
    final raw = (note ?? '').trim();
    if (raw.isEmpty) return '';
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) {
          if (line.isEmpty) return false;
          final lower = line.toLowerCase();
          return lower != '[manual]' &&
              !lower.startsWith('[service]') &&
              !lower.startsWith('[shared_service_office:') &&
              !lower.startsWith('[party:') &&
              !lower.startsWith('[party_id:') &&
              !lower.startsWith('[property:') &&
              !lower.startsWith('[property_id:') &&
              !lower.startsWith('[owner_payout]') &&
              !lower.startsWith('[owner_adjustment]') &&
              !lower.startsWith('[owner_payout_id:') &&
              !lower.startsWith('[owner_adjustment_id:') &&
              !lower.startsWith('[owner_adjustment_category:') &&
              !lower.startsWith('[office_commission]') &&
              !lower.startsWith('[office_withdrawal]') &&
              !lower.startsWith('[contract_voucher_id:') &&
              !lower.startsWith('[posted]') &&
              !lower.startsWith('[cancelled]') &&
              !lower.startsWith('[reversal]') &&
              !lower.startsWith('[reversed]');
        })
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  static String _buildOfficeManualVoucherNote({
    required bool isExpense,
    String note = '',
  }) {
    final lines = <String>[
      '[MANUAL]',
      '[PARTY: المكتب]',
      if (!isExpense) '[OFFICE_COMMISSION]',
      if (isExpense)
        'مصروف مكتب'
      else
        'إيراد العمولات',
    ];
    final cleanNote = note.trim();
    if (cleanNote.isNotEmpty) {
      lines.add(cleanNote);
    }
    return lines.join('\n').trim();
  }

  static String _buildOfficeWithdrawalVoucherNote({
    String note = '',
  }) {
    final lines = <String>[
      '[MANUAL]',
      '[PARTY: المكتب]',
      '[OFFICE_WITHDRAWAL]',
      'تحويل من رصيد المكتب',
    ];
    final cleanNote = note.trim();
    if (cleanNote.isNotEmpty) {
      lines.add(cleanNote);
    }
    return lines.join('\n').trim();
  }

  static OwnerPayoutStatus _ownerStatusFromVoucher(
    Invoice? voucher,
    OwnerPayoutStatus fallbackStatus,
  ) {
    if (voucher == null) return fallbackStatus;
    switch (_detectVoucherState(voucher)) {
      case VoucherState.cancelled:
        return OwnerPayoutStatus.cancelled;
      case VoucherState.reversed:
        return OwnerPayoutStatus.reversed;
      case VoucherState.draft:
        return OwnerPayoutStatus.draft;
      case VoucherState.posted:
        return OwnerPayoutStatus.posted;
    }
  }

  static VoucherState _voucherStateFromOwnerStatus(OwnerPayoutStatus status) {
    switch (status) {
      case OwnerPayoutStatus.draft:
        return VoucherState.draft;
      case OwnerPayoutStatus.posted:
        return VoucherState.posted;
      case OwnerPayoutStatus.cancelled:
        return VoucherState.cancelled;
      case OwnerPayoutStatus.reversed:
        return VoucherState.reversed;
    }
  }

  static Future<OwnerPayoutRecord> executeOwnerPayout({
    required String ownerId,
    required String ownerName,
    required double amount,
    DateTime? transferDate,
    DateTime? periodFrom,
    DateTime? periodTo,
    String note = '',
    String propertyId = '',
    String propertyName = '',
    ComprehensiveReportFilters filters = const ComprehensiveReportFilters(),
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final normalizedAmount = amount.abs();
    if (normalizedAmount <= 0) {
      throw StateError('المبلغ يجب أن يكون أكبر من صفر');
    }

    final preview =
        await previewOwnerSettlement(ownerId: ownerId, filters: filters);
    if (normalizedAmount > preview.readyForPayout + 0.000001) {
      throw StateError(
        'المبلغ يتجاوز الرصيد القابل للتحويل (${preview.readyForPayout.toStringAsFixed(2)})',
      );
    }

    final when = _dateOnly(transferDate ?? KsaTime.now());
    final payoutId = _newId();
    final voucherId = _newId();

    final invoicesName = boxName(kInvoicesBox);
    final invoices = Hive.box<Invoice>(invoicesName);
    final serialNo = _nextInvoiceSerial(invoices);
    final payoutNote = _buildOwnerVoucherNote(
      sourceMarker: '[OWNER_PAYOUT]',
      description: 'تحويل مستحق المالك',
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      propertyName: propertyName,
      note: note,
      recordIdMarker: 'OWNER_PAYOUT_ID',
      recordIdValue: payoutId,
    );
    final voucher = Invoice(
      id: voucherId,
      serialNo: serialNo,
      tenantId: ownerId,
      contractId: '',
      propertyId: propertyId,
      issueDate: when,
      dueDate: when,
      amount: -normalizedAmount,
      paidAmount: normalizedAmount,
      currency: 'SAR',
      note: payoutNote.trim(),
      paymentMethod: '',
      isArchived: false,
      isCanceled: false,
      createdAt: KsaTime.now(),
      updatedAt: KsaTime.now(),
    );
    await invoices.put(voucher.id, voucher);

    final rec = OwnerPayoutRecord(
      id: payoutId,
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      amount: normalizedAmount,
      status: OwnerPayoutStatus.posted,
      createdAt: KsaTime.now(),
      postedAt: when,
      periodFrom: periodFrom,
      periodTo: periodTo,
      note: note.trim(),
      voucherId: voucher.id,
      voucherSerialNo: voucher.serialNo ?? '',
    );

    final payouts = Hive.box(_ownerPayoutsBoxName);
    await payouts.put(rec.id, rec.toMap());
    return rec;
  }

  static Future<List<OwnerPayoutRecord>> loadOwnerPayouts() async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();
    final box = Hive.box(_ownerPayoutsBoxName);
    final invoiceById = <String, Invoice>{
      for (final invoice in _safeValues<Invoice>(boxName(kInvoicesBox))) invoice.id: invoice,
    };
    return box.values
        .whereType<Map>()
        .map((e) => OwnerPayoutRecord.fromMap(e))
        .map((record) {
          final voucher = invoiceById[record.voucherId];
          return record.copyWith(
            status: _ownerStatusFromVoucher(voucher, record.status),
          );
        })
        .toList()
      ..sort((a, b) => (b.postedAt ?? b.createdAt).compareTo(
            a.postedAt ?? a.createdAt,
          ));
  }

  static Future<OwnerAdjustmentRecord> executeOwnerAdjustment({
    required String ownerId,
    required String ownerName,
    required double amount,
    required OwnerAdjustmentCategory category,
    DateTime? adjustmentDate,
    DateTime? periodFrom,
    DateTime? periodTo,
    String note = '',
    String propertyId = '',
    String propertyName = '',
    ComprehensiveReportFilters filters = const ComprehensiveReportFilters(),
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final normalizedAmount = amount.abs();
    if (normalizedAmount <= 0) {
      throw StateError('المبلغ يجب أن يكون أكبر من صفر');
    }

    final preview =
        await previewOwnerSettlement(ownerId: ownerId, filters: filters);
    if (normalizedAmount > preview.readyForPayout + 0.000001) {
      throw StateError(
        'المبلغ يتجاوز الرصيد القابل للتطبيق (${preview.readyForPayout.toStringAsFixed(2)})',
      );
    }

    final when = _dateOnly(adjustmentDate ?? KsaTime.now());
    final adjustmentId = _newId();
    final voucherId = _newId();

    final invoicesName = boxName(kInvoicesBox);
    final invoices = Hive.box<Invoice>(invoicesName);
    final serialNo = _nextInvoiceSerial(invoices);
    final adjustmentNote = _buildOwnerVoucherNote(
      sourceMarker: '[OWNER_ADJUSTMENT]',
      description: 'خصم/تسوية للمالك: ${category.arLabel}',
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      propertyName: propertyName,
      note: note,
      recordIdMarker: 'OWNER_ADJUSTMENT_ID',
      recordIdValue: adjustmentId,
      categoryMarker: 'OWNER_ADJUSTMENT_CATEGORY',
      categoryValue: category.name,
    );
    final voucher = Invoice(
      id: voucherId,
      serialNo: serialNo,
      tenantId: ownerId,
      contractId: '',
      propertyId: propertyId,
      issueDate: when,
      dueDate: when,
      amount: normalizedAmount,
      paidAmount: normalizedAmount,
      currency: 'SAR',
      note: adjustmentNote.trim(),
      paymentMethod: '',
      isArchived: false,
      isCanceled: false,
      createdAt: KsaTime.now(),
      updatedAt: KsaTime.now(),
    );
    await invoices.put(voucher.id, voucher);

    final rec = OwnerAdjustmentRecord(
      id: adjustmentId,
      ownerId: ownerId,
      ownerName: ownerName,
      propertyId: propertyId,
      amount: normalizedAmount,
      category: category,
      status: OwnerPayoutStatus.posted,
      createdAt: KsaTime.now(),
      postedAt: when,
      periodFrom: periodFrom,
      periodTo: periodTo,
      note: note.trim(),
      voucherId: voucher.id,
    );

    final adjustments = Hive.box(_ownerAdjustmentsBoxName);
    await adjustments.put(rec.id, rec.toMap());
    return rec;
  }

  static Future<List<OwnerAdjustmentRecord>> loadOwnerAdjustments() async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();
    final box = Hive.box(_ownerAdjustmentsBoxName);
    final invoiceById = <String, Invoice>{
      for (final invoice in _safeValues<Invoice>(boxName(kInvoicesBox))) invoice.id: invoice,
    };
    return box.values
        .whereType<Map>()
        .map((e) => OwnerAdjustmentRecord.fromMap(e))
        .map((record) {
          final voucher = invoiceById[record.voucherId];
          return record.copyWith(
            status: _ownerStatusFromVoucher(voucher, record.status),
          );
        })
        .toList()
      ..sort((a, b) => (b.postedAt ?? b.createdAt).compareTo(
            a.postedAt ?? a.createdAt,
          ));
  }

  static Future<OwnerBankAccountRecord> addOwnerBankAccount({
    required String ownerId,
    required String ownerName,
    required String bankName,
    required String accountNumber,
    String iban = '',
  }) async {
    await ensureFinanceBoxesOpen();

    final normalizedOwnerId = ownerId.trim();
    final normalizedBankName = bankName.trim();
    final normalizedAccountNumber = accountNumber.trim();
    final normalizedIban = iban.trim();

    if (normalizedOwnerId.isEmpty) {
      throw StateError('تعذر تحديد المالك');
    }
    if (normalizedBankName.isEmpty) {
      throw StateError('اسم البنك مطلوب');
    }
    if (normalizedAccountNumber.isEmpty) {
      throw StateError('رقم الحساب مطلوب');
    }

    final now = KsaTime.now();
    final record = OwnerBankAccountRecord(
      id: _newId(),
      ownerId: normalizedOwnerId,
      ownerName: ownerName.trim(),
      bankName: normalizedBankName,
      accountNumber: normalizedAccountNumber,
      iban: normalizedIban,
      createdAt: now,
      updatedAt: now,
    );

    final box = Hive.box(_ownerBankAccountsBoxName);
    await box.put(record.id, record.toMap());
    await _recordLocalAudit(
      collectionName: _ownerBankAccountsAuditCollectionName,
      entityId: record.id,
      isCreate: true,
    );
    return record;
  }

  static Future<OwnerBankAccountRecord> updateOwnerBankAccount({
    required String accountId,
    required String ownerId,
    required String ownerName,
    required String bankName,
    required String accountNumber,
    String iban = '',
  }) async {
    await ensureFinanceBoxesOpen();

    final normalizedAccountId = accountId.trim();
    final normalizedOwnerId = ownerId.trim();
    final normalizedOwnerName = ownerName.trim();
    final normalizedBankName = bankName.trim();
    final normalizedAccountNumber = accountNumber.trim();
    final normalizedIban = iban.trim();

    if (normalizedAccountId.isEmpty) {
      throw StateError('تعذر تحديد الحساب البنكي');
    }
    if (normalizedOwnerId.isEmpty) {
      throw StateError('تعذر تحديد المالك');
    }
    if (normalizedBankName.isEmpty) {
      throw StateError('اسم البنك مطلوب');
    }
    if (normalizedAccountNumber.isEmpty) {
      throw StateError('رقم الحساب مطلوب');
    }

    final box = Hive.box(_ownerBankAccountsBoxName);
    final raw = box.get(normalizedAccountId);
    if (raw is! Map) {
      throw StateError('الحساب البنكي غير موجود');
    }

    final current = OwnerBankAccountRecord.fromMap(raw);
    if (current.ownerId.trim() != normalizedOwnerId) {
      throw StateError('هذا الحساب البنكي لا يتبع لهذا المالك');
    }

    final nextOwnerName =
        normalizedOwnerName.isEmpty ? current.ownerName : normalizedOwnerName;
    final changed = current.ownerName != nextOwnerName ||
        current.bankName != normalizedBankName ||
        current.accountNumber != normalizedAccountNumber ||
        current.iban != normalizedIban;
    if (!changed) return current;

    final updated = OwnerBankAccountRecord(
      id: current.id,
      ownerId: current.ownerId,
      ownerName: nextOwnerName,
      bankName: normalizedBankName,
      accountNumber: normalizedAccountNumber,
      iban: normalizedIban,
      createdAt: current.createdAt,
      updatedAt: KsaTime.now(),
    );

    await box.put(updated.id, updated.toMap());
    await _recordLocalAudit(
      collectionName: _ownerBankAccountsAuditCollectionName,
      entityId: updated.id,
      isCreate: false,
    );
    return updated;
  }

  static Future<void> deleteOwnerBankAccount({
    required String accountId,
    required String ownerId,
  }) async {
    await ensureFinanceBoxesOpen();

    final normalizedAccountId = accountId.trim();
    final normalizedOwnerId = ownerId.trim();
    if (normalizedAccountId.isEmpty) {
      throw StateError('تعذر تحديد الحساب البنكي');
    }
    if (normalizedOwnerId.isEmpty) {
      throw StateError('تعذر تحديد المالك');
    }

    final box = Hive.box(_ownerBankAccountsBoxName);
    final raw = box.get(normalizedAccountId);
    if (raw is! Map) {
      throw StateError('الحساب البنكي غير موجود');
    }

    final current = OwnerBankAccountRecord.fromMap(raw);
    if (current.ownerId.trim() != normalizedOwnerId) {
      throw StateError('هذا الحساب البنكي لا يتبع لهذا المالك');
    }

    await box.delete(normalizedAccountId);
  }

  static Future<void> syncOfficeCommissionVouchers({
    String? contractVoucherId,
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final invoices = Hive.box<Invoice>(boxName(kInvoicesBox));
    final ownerMapBox = Hive.box(_propertyOwnersBoxName);
    final configBox = Hive.box(_financeConfigBoxName);
    final globalCommissionRule = CommissionRule.fromMap(
      configBox.get(_commissionKey(CommissionScope.global, null)),
    );
    final properties = _safeValues<Property>(boxName(kPropertiesBox))
        .where((p) => !p.isArchived)
        .toList(growable: false);
    final contracts = _safeValues<Contract>(HiveService.contractsBoxName())
        .where((c) => !c.isArchived)
        .toList(growable: false);
    final contractsEjarBoxName = boxName('contractsEjarNoMap');
    final contractsEjarBox = Hive.isBoxOpen(contractsEjarBoxName)
        ? Hive.box<String>(contractsEjarBoxName)
        : await Hive.openBox<String>(contractsEjarBoxName);
    final propertyById = <String, Property>{
      for (final property in properties) property.id: property,
    };
    final contractById = <String, Contract>{
      for (final contract in contracts) contract.id: contract,
    };
    final sessionBox = Hive.isBoxOpen(kSessionBox)
        ? Hive.box(kSessionBox)
        : await Hive.openBox(kSessionBox);

    String pickFirstText(Iterable<Object?> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final scopedUid = effectiveUid().trim();
    final workspaceOwnerId = pickFirstText([
      sessionBox.get('workspaceOwnerUid'),
      scopedUid == 'guest' ? '' : scopedUid,
    ]);

    String ownerIdForProperty(String propertyId) {
      final normalizedPropertyId = propertyId.trim();
      if (normalizedPropertyId.isEmpty) return '';

      // الأهم: مالك العقار المربوط صراحة له الأولوية دائمًا.
      // الرجوع إلى مالك مساحة العمل لا يتم إلا عند عدم وجود ربط مباشر/موروث.
      final direct = ownerMapBox.get(normalizedPropertyId);
      if (direct is Map) {
        final ownerId = (direct['ownerId'] ?? '').toString().trim();
        if (ownerId.isNotEmpty) return ownerId;
      } else if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim();
      }

      final property = propertyById[normalizedPropertyId];
      final parentId = property?.parentBuildingId?.trim() ?? '';
      if (parentId.isNotEmpty) {
        final parent = ownerMapBox.get(parentId);
        if (parent is Map) {
          final ownerId = (parent['ownerId'] ?? '').toString().trim();
          if (ownerId.isNotEmpty) return ownerId;
        } else if (parent is String && parent.trim().isNotEmpty) {
          return parent.trim();
        }
      }

      return workspaceOwnerId;
    }

    CommissionRule ruleFor() {
      return globalCommissionRule;
    }

    final officeByContractVoucherId = <String, List<Invoice>>{};
    for (final voucher in invoices.values) {
      final linkedId = _officeCommissionLinkedContractVoucherId(voucher.note);
      if (linkedId.isEmpty) continue;
      officeByContractVoucherId.putIfAbsent(linkedId, () => <Invoice>[]).add(voucher);
    }

    final targetContractVoucherId = (contractVoucherId ?? '').trim();
    final contractVouchers = invoices.values
        .where((invoice) {
          if (targetContractVoucherId.isNotEmpty &&
              invoice.id != targetContractVoucherId) {
            return false;
          }
          if (_detectVoucherSource(invoice) != VoucherSource.contracts) {
            return false;
          }
          return invoice.amount >= 0;
        })
        .toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    bool hasOfficeReversalFor(Invoice voucher) {
      return invoices.values.any((candidate) {
        if (!_isOfficeCommissionInvoice(candidate)) return false;
        final note = (candidate.note ?? '').toLowerCase();
        return note.contains('[reversal]') &&
            note.contains('original=${voucher.id}'.toLowerCase());
      });
    }

    Future<void> cancelOfficeVoucher(Invoice voucher) async {
      if (_detectVoucherState(voucher) == VoucherState.cancelled) return;
      voucher.isCanceled = true;
      voucher.isArchived = true;
      voucher.note = _appendVoucherNoteLine(
        voucher.note,
        '[CANCELLED] تم إلغاء سند عمولة المكتب لارتباطه بإلغاء سند العقد',
      );
      voucher.updatedAt = KsaTime.now();
      await invoices.put(voucher.id, voucher);
    }

    Future<void> reverseOfficeVoucher(
      Invoice voucher,
      String linkedContractVoucherId,
    ) async {
      final state = _detectVoucherState(voucher);
      if (state == VoucherState.cancelled || state == VoucherState.reversed) {
        return;
      }
      if (hasOfficeReversalFor(voucher)) {
        voucher.note = _appendVoucherNoteLine(
          voucher.note,
          '[REVERSAL] معكوس بواسطة سند عمولة مرتبط',
        );
        voucher.updatedAt = KsaTime.now();
        await invoices.put(voucher.id, voucher);
        return;
      }
      final now = KsaTime.now();
      final reversal = Invoice(
        id: _newId(),
        serialNo: _nextInvoiceSerial(invoices),
        tenantId: voucher.tenantId,
        contractId: voucher.contractId,
        propertyId: voucher.propertyId,
        issueDate: now,
        dueDate: now,
        amount: -voucher.amount.abs(),
        paidAmount: voucher.amount.abs(),
        currency: voucher.currency,
        note: _buildOfficeCommissionVoucherNote(
          contractVoucherId: linkedContractVoucherId,
          description:
              '[REVERSAL] original=${voucher.id} serial=${voucher.serialNo ?? voucher.id}\nعكس عمولة المكتب لارتباطها بعكس سند العقد',
        ),
        paymentMethod: voucher.paymentMethod,
        isArchived: false,
        isCanceled: false,
        createdAt: now,
        updatedAt: now,
      );
      await invoices.put(reversal.id, reversal);
      voucher.note = _appendVoucherNoteLine(
        voucher.note,
        '[REVERSAL] معكوس بواسطة ${reversal.serialNo ?? reversal.id}',
      );
      voucher.updatedAt = KsaTime.now();
      await invoices.put(voucher.id, voucher);
    }

    for (final contractVoucher in contractVouchers) {
      final linkedOfficeVouchers = (officeByContractVoucherId[contractVoucher.id] ??
              const <Invoice>[])
          .toList(growable: false);
      final contract = contractById[contractVoucher.contractId];
      final contractState = _detectVoucherState(contractVoucher);

      if (contract?.term == ContractTerm.daily) {
        for (final officeVoucher in linkedOfficeVouchers) {
          if (_detectVoucherState(officeVoucher) == VoucherState.posted) {
            await cancelOfficeVoucher(officeVoucher);
          }
        }
        continue;
      }

      if (contractState == VoucherState.cancelled) {
        for (final officeVoucher in linkedOfficeVouchers) {
          await cancelOfficeVoucher(officeVoucher);
        }
        continue;
      }

      if (contractState == VoucherState.reversed) {
        for (final officeVoucher in linkedOfficeVouchers) {
          await reverseOfficeVoucher(officeVoucher, contractVoucher.id);
        }
        continue;
      }

      if (contractState != VoucherState.posted) {
        continue;
      }

      final historicalCommission =
          _historicalCommissionSnapshotFromContractVoucher(contractVoucher);
      final double commission;
      if (historicalCommission != null) {
        if (historicalCommission.mode != CommissionMode.percent) {
          continue;
        }
        commission = historicalCommission.amount > 0
            ? historicalCommission.amount
            : CommissionRule(
                mode: CommissionMode.percent,
                value: historicalCommission.value,
              ).apply(_rentOnlyAmountFromInvoice(contractVoucher));
      } else {
        final rule = ruleFor();
        if (rule.mode != CommissionMode.percent) {
          continue;
        }
        commission = rule.apply(_rentOnlyAmountFromInvoice(contractVoucher));
      }
      if (commission <= 0) continue;

      final propertyName = _officeCommissionPropertyReference(
        contractVoucher.propertyId,
        propertyById,
      );
      final contractReference = _officeCommissionContractReference(
        contract,
        ejarMapBox: contractsEjarBox,
      );
      final description = _officeCommissionDescription(
        contractNo: contractReference,
        propertyName: propertyName,
      );
      final postedLinkedOfficeVoucher = linkedOfficeVouchers.firstWhere(
        (voucher) => _detectVoucherState(voucher) == VoucherState.posted,
        orElse: () => Invoice(
          id: '',
          tenantId: '',
          contractId: '',
          propertyId: '',
          issueDate: contractVoucher.issueDate,
          dueDate: contractVoucher.dueDate,
          amount: 0,
        ),
      );
      if (postedLinkedOfficeVoucher.id.trim().isNotEmpty) {
        final currentDescription =
            _cleanVoucherDisplayNote(postedLinkedOfficeVoucher.note);
        if (currentDescription != description) {
          postedLinkedOfficeVoucher.note = _buildOfficeCommissionVoucherNote(
            contractVoucherId: contractVoucher.id,
            description: description,
          );
          postedLinkedOfficeVoucher.updatedAt = KsaTime.now();
          await invoices.put(
            postedLinkedOfficeVoucher.id,
            postedLinkedOfficeVoucher,
          );
        }
        continue;
      }

      final now = KsaTime.now();
      final officeVoucher = Invoice(
        id: _newId(),
        serialNo: _nextInvoiceSerial(invoices),
        tenantId: contractVoucher.tenantId,
        contractId: contractVoucher.contractId,
        propertyId: contractVoucher.propertyId,
        issueDate: contractVoucher.issueDate,
        dueDate: contractVoucher.dueDate,
        amount: commission,
        paidAmount: commission,
        currency: contractVoucher.currency,
        note: _buildOfficeCommissionVoucherNote(
          contractVoucherId: contractVoucher.id,
          description: description,
        ),
        paymentMethod: contractVoucher.paymentMethod,
        isArchived: false,
        isCanceled: false,
        createdAt: now,
        updatedAt: now,
      );
      await invoices.put(officeVoucher.id, officeVoucher);
      officeByContractVoucherId
          .putIfAbsent(contractVoucher.id, () => <Invoice>[])
          .add(officeVoucher);
    }
  }

  static Future<List<OwnerBankAccountRecord>> loadOwnerBankAccounts(
    String ownerId,
  ) async {
    await ensureFinanceBoxesOpen();
    final normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.isEmpty) return const <OwnerBankAccountRecord>[];
    final box = Hive.box(_ownerBankAccountsBoxName);
    return box.values
        .whereType<Map>()
        .map((e) => OwnerBankAccountRecord.fromMap(e))
        .where((e) => e.ownerId == normalizedOwnerId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<Invoice> executeOfficeManualVoucher({
    required bool isExpense,
    required double amount,
    DateTime? transactionDate,
    String note = '',
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final normalizedAmount = amount.abs();
    if (normalizedAmount <= 0) {
      throw StateError('المبلغ يجب أن يكون أكبر من صفر');
    }

    final when = _dateOnly(transactionDate ?? KsaTime.now());
    final now = KsaTime.now();
    final signedAmount = isExpense ? -normalizedAmount : normalizedAmount;
    final invoices = Hive.box<Invoice>(boxName(kInvoicesBox));
    var manualCommissionOwnerId = '';
    if (!isExpense) {
      final sessionBox = Hive.isBoxOpen(kSessionBox)
          ? Hive.box(kSessionBox)
          : await Hive.openBox(kSessionBox);
      manualCommissionOwnerId =
          (sessionBox.get('workspaceOwnerUid') ?? '').toString().trim();
      if (manualCommissionOwnerId.isEmpty) {
        final properties = _safeValues<Property>(boxName(kPropertiesBox))
            .where((p) => !p.isArchived)
            .toList(growable: false);
        final ownerMapBox = Hive.box(_propertyOwnersBoxName);
        final propertyById = <String, Property>{
          for (final property in properties) property.id: property,
        };

        String ownerIdForProperty(String propertyId) {
          final normalizedPropertyId = propertyId.trim();
          if (normalizedPropertyId.isEmpty) return '';
          final direct = ownerMapBox.get(normalizedPropertyId);
          if (direct is Map) {
            final ownerId = (direct['ownerId'] ?? '').toString().trim();
            if (ownerId.isNotEmpty) return ownerId;
          } else if (direct is String && direct.trim().isNotEmpty) {
            return direct.trim();
          }
          final property = propertyById[normalizedPropertyId];
          final parentId = property?.parentBuildingId?.trim() ?? '';
          if (parentId.isEmpty) return '';
          final parent = ownerMapBox.get(parentId);
          if (parent is Map) {
            return (parent['ownerId'] ?? '').toString().trim();
          }
          if (parent is String) return parent.trim();
          return '';
        }

        final ownerIds = <String>{};
        for (final property in properties) {
          final ownerId = ownerIdForProperty(property.id);
          if (ownerId.isNotEmpty) ownerIds.add(ownerId);
        }
        if (ownerIds.length == 1) {
          manualCommissionOwnerId = ownerIds.first;
        }
      }
    }
    final manualNote = _buildOfficeManualVoucherNote(
      isExpense: isExpense,
      note: note,
    );

    final invoice = Invoice(
      serialNo: _nextInvoiceSerial(invoices),
      tenantId: manualCommissionOwnerId,
      contractId: '',
      propertyId: '',
      issueDate: when,
      dueDate: when,
      amount: signedAmount,
      paidAmount: normalizedAmount,
      currency: 'SAR',
      note: '$manualNote\n[POSTED] تم اعتماد السند',
      paymentMethod: '',
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );

    await invoices.put(invoice.id, invoice);
    return invoice;
  }

  static Future<Invoice> executeOfficeWithdrawal({
    required double amount,
    DateTime? transferDate,
    String note = '',
    ComprehensiveReportFilters filters = const ComprehensiveReportFilters(),
  }) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final normalizedAmount = amount.abs();
    if (normalizedAmount <= 0) {
      throw StateError('المبلغ يجب أن يكون أكبر من صفر');
    }

    final preview = await previewOfficeSettlement(filters: filters);
    if (normalizedAmount > preview.readyForWithdrawal + 0.000001) {
      throw StateError(
        'المبلغ يتجاوز الرصيد القابل للتحويل (${preview.readyForWithdrawal.toStringAsFixed(2)})',
      );
    }

    final when = _dateOnly(transferDate ?? KsaTime.now());
    final now = KsaTime.now();
    final invoices = Hive.box<Invoice>(boxName(kInvoicesBox));
    final withdrawalNote = _buildOfficeWithdrawalVoucherNote(note: note);

    final invoice = Invoice(
      serialNo: _nextInvoiceSerial(invoices),
      tenantId: '',
      contractId: '',
      propertyId: '',
      issueDate: when,
      dueDate: when,
      amount: -normalizedAmount,
      paidAmount: normalizedAmount,
      currency: 'SAR',
      note: '$withdrawalNote\n[POSTED] تم اعتماد السند',
      paymentMethod: '',
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );

    await invoices.put(invoice.id, invoice);
    return invoice;
  }

  static Future<ComprehensiveReportSnapshot> load(
    ComprehensiveReportFilters filters,
  ) async {
    await HiveService.ensureReportsBoxesOpen();
    await ensureFinanceBoxesOpen();

    final properties = _safeValues<Property>(boxName(kPropertiesBox))
        .where((p) => !p.isArchived)
        .toList(growable: false);
    final tenants = _safeValues<Tenant>(boxName(kTenantsBox))
        .where((t) => !t.isArchived)
        .toList(growable: false);
    final contracts = _safeValues<Contract>(HiveService.contractsBoxName())
        .where((c) => !c.isArchived)
        .toList(growable: false);
    final contractsEjarBoxName = boxName('contractsEjarNoMap');
    final contractsEjarBox = Hive.isBoxOpen(contractsEjarBoxName)
        ? Hive.box<String>(contractsEjarBoxName)
        : await Hive.openBox<String>(contractsEjarBoxName);
    final allInvoices = _safeValues<Invoice>(boxName(kInvoicesBox));
    final invoices = allInvoices
        .where((i) => !i.isArchived)
        .toList(growable: false);
    final maintenance =
        _safeValues<MaintenanceRequest>(HiveService.maintenanceBoxName())
            .where((m) => !m.isArchived)
            .toList(growable: false);
    final allInvoiceEntries = Hive.box<Invoice>(boxName(kInvoicesBox)).values
        .toList(growable: false);
    final invoiceById = <String, Invoice>{
      for (final invoice in allInvoiceEntries) invoice.id: invoice,
    };
    final contractById = <String, Contract>{
      for (final contract in contracts) contract.id: contract,
    };
    final officeCommissionByContractVoucherId = <String, List<Invoice>>{};
    for (final invoice in invoices) {
      final linkedId = _officeCommissionLinkedContractVoucherId(invoice.note);
      if (linkedId.isEmpty) continue;
      officeCommissionByContractVoucherId
          .putIfAbsent(linkedId, () => <Invoice>[])
          .add(invoice);
    }

    final ownerMapBox = Hive.box(_propertyOwnersBoxName);
    final configBox = Hive.box(_financeConfigBoxName);
    final globalCommissionRule = CommissionRule.fromMap(
      configBox.get(_commissionKey(CommissionScope.global, null)),
    );
    final payoutBox = Hive.box(_ownerPayoutsBoxName);
    final adjustmentsBox = Hive.box(_ownerAdjustmentsBoxName);

    final propertyById = <String, Property>{
      for (final p in properties) p.id: p,
    };
    final tenantById = <String, Tenant>{
      for (final t in tenants) t.id: t,
    };
    final sessionBox = Hive.isBoxOpen(kSessionBox)
        ? Hive.box(kSessionBox)
        : await Hive.openBox(kSessionBox);
    String pickFirstText(Iterable<Object?> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final scopedUid = effectiveUid().trim();
    final currentWorkspaceOwnerId = pickFirstText([
      sessionBox.get('workspaceOwnerUid'),
      scopedUid == 'guest' ? '' : scopedUid,
    ]);
    User? authUser;
    try {
      authUser = FirebaseAuth.instance.currentUser;
    } catch (_) {
      authUser = null;
    }
    final currentWorkspaceOwnerName = pickFirstText([
      sessionBox.get('workspaceOwnerName'),
      currentWorkspaceOwnerId.isEmpty
          ? ''
          : tenantById[currentWorkspaceOwnerId]?.fullName,
      authUser?.displayName,
      authUser?.email,
      currentWorkspaceOwnerId,
    ]);

    String ownerIdForProperty(String propertyId) {
      final normalizedPropertyId = propertyId.trim();
      if (normalizedPropertyId.isEmpty) return '';

      // الربط الصريح للعقار أو عمارته الأم هو مصدر الحقيقة.
      // مالك مساحة العمل يستخدم كافتراض فقط إذا لم يوجد ربط عقار.
      final raw = ownerMapBox.get(normalizedPropertyId);
      if (raw is Map) {
        final direct = (raw['ownerId'] ?? '').toString().trim();
        if (direct.isNotEmpty) return direct;
      } else if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
      final prop = propertyById[normalizedPropertyId];
      final parent = prop?.parentBuildingId?.trim() ?? '';
      if (parent.isNotEmpty) {
        final parentRaw = ownerMapBox.get(parent);
        if (parentRaw is Map) {
          final parentOwner = (parentRaw['ownerId'] ?? '').toString().trim();
          if (parentOwner.isNotEmpty) return parentOwner;
        } else if (parentRaw is String && parentRaw.trim().isNotEmpty) {
          return parentRaw.trim();
        }
      }
      return currentWorkspaceOwnerId;
    }

    String ownerNameForId(String ownerId) {
      final normalizedOwnerId = ownerId.trim();
      if (normalizedOwnerId.isEmpty) {
        return currentWorkspaceOwnerName.isNotEmpty
            ? currentWorkspaceOwnerName
            : 'غير محدد';
      }
      if (normalizedOwnerId == currentWorkspaceOwnerId &&
          currentWorkspaceOwnerName.isNotEmpty) {
        return currentWorkspaceOwnerName;
      }
      final t = tenantById[normalizedOwnerId];
      if (t != null) return t.fullName;
      for (final v in ownerMapBox.values) {
        if (v is! Map) continue;
        if ((v['ownerId'] ?? '').toString().trim() == normalizedOwnerId) {
          final n = (v['ownerName'] ?? '').toString().trim();
          if (n.isNotEmpty) return n;
        }
      }
      return normalizedOwnerId;
    }

    Set<String> propertyScopeIds(Property property) {
      final ids = <String>{property.id};
      final isGroupedProperty = property.type == PropertyType.building ||
          property.rentalMode == RentalMode.perUnit;
      if (isGroupedProperty) {
        for (final child in properties) {
          if ((child.parentBuildingId ?? '').trim() == property.id) {
            ids.add(child.id);
          }
        }
      }
      return ids;
    }

    Set<String> ownerScopePropertyIds(Iterable<Property> propertyList) {
      final ids = <String>{};
      for (final property in propertyList) {
        ids.addAll(propertyScopeIds(property));
      }
      return ids;
    }

    bool matchesScopedPropertyId(String candidate, Set<String> scopeIds) {
      final normalized = candidate.trim();
      return normalized.isNotEmpty && scopeIds.contains(normalized);
    }

    bool matchesSelectedPropertyFilter(String candidatePropertyId) {
      final selectedPropertyId = (filters.propertyId ?? '').trim();
      if (selectedPropertyId.isEmpty) return true;
      final candidate = candidatePropertyId.trim();
      if (candidate == selectedPropertyId) return true;
      final selectedProperty = propertyById[selectedPropertyId];
      if (selectedProperty == null) return false;
      return propertyScopeIds(selectedProperty).contains(candidate);
    }

    final payoutRecords = payoutBox.values
        .whereType<Map>()
        .map((e) => OwnerPayoutRecord.fromMap(e))
        .map((record) {
          final voucher = invoiceById[record.voucherId];
          return record.copyWith(
            status: _ownerStatusFromVoucher(voucher, record.status),
          );
        })
        .toList(growable: false);
    final adjustmentRecords = adjustmentsBox.values
        .whereType<Map>()
        .map((e) => OwnerAdjustmentRecord.fromMap(e))
        .map((record) {
          final voucher = invoiceById[record.voucherId];
          return record.copyWith(
            status: _ownerStatusFromVoucher(voucher, record.status),
          );
        })
        .toList(growable: false);

    CommissionRule ruleFor() {
      return globalCommissionRule;
    }

    final vouchers = <VoucherReportItem>[];
    final voucherTabItems = <VoucherReportItem>[];
    final rentRows = <_RentCollectionRow>[];

    bool matchesVoucherTabScope(Invoice inv, VoucherSource source) {
      final date = _dateOnly(inv.issueDate);
      if (!filters.inRange(date)) return false;
      final resolvedPropertyId = _resolvedVoucherPropertyId(inv, source);

      if (!matchesSelectedPropertyFilter(resolvedPropertyId)) {
        return false;
      }
      if (filters.contractId != null &&
          filters.contractId!.trim().isNotEmpty &&
          inv.contractId != filters.contractId!.trim()) {
        return false;
      }
      final ownerId = ownerIdForProperty(resolvedPropertyId);
      if (filters.ownerId != null &&
          filters.ownerId!.trim().isNotEmpty &&
          ownerId != filters.ownerId!.trim()) {
        return false;
      }
      return true;
    }

    for (final inv in allInvoices) {
      final source = _detectVoucherSource(inv);
      if (!matchesVoucherTabScope(inv, source)) continue;
      final state = _detectVoucherState(inv);
      if (state == VoucherState.draft) continue;
      final date = _dateOnly(inv.issueDate);
      final direction =
          inv.amount < 0 ? VoucherDirection.payment : VoucherDirection.receipt;
      final resolvedPropertyId = _resolvedVoucherPropertyId(inv, source);
      final resolvedTenantId = _resolvedVoucherTenantId(inv, source);
      final serviceLikeInvoice = _looksLikeGeneratedServiceVoucherNote(
        inv.note ?? '',
      );

      final voucherItem = VoucherReportItem(
        id: inv.id,
        serialNo: inv.serialNo ?? inv.id,
        date: date,
        createdAt: inv.createdAt,
        contractId: inv.contractId,
        propertyId: resolvedPropertyId,
        tenantId: resolvedTenantId,
        amount: inv.amount.abs(),
        paidAmount: inv.paidAmount.abs(),
        paymentMethod: inv.paymentMethod,
        note: inv.note ?? '',
        direction: direction,
        state: state,
        source: source,
        isServiceInvoice:
            serviceLikeInvoice ||
            source == VoucherSource.services ||
            source == VoucherSource.maintenance,
      );
      voucherTabItems.add(voucherItem);
    }

    for (final inv in invoices) {
      final date = _dateOnly(inv.issueDate);
      if (!filters.inRange(date)) continue;

      final source = _detectVoucherSource(inv);
      final state = _detectVoucherState(inv);
      final direction =
          inv.amount < 0 ? VoucherDirection.payment : VoucherDirection.receipt;
      final resolvedPropertyId = _resolvedVoucherPropertyId(inv, source);
      final resolvedTenantId = _resolvedVoucherTenantId(inv, source);
      final serviceLikeInvoice = _looksLikeGeneratedServiceVoucherNote(
        inv.note ?? '',
      );

      if (!matchesSelectedPropertyFilter(resolvedPropertyId)) {
        continue;
      }
      if (filters.contractId != null &&
          filters.contractId!.trim().isNotEmpty &&
          inv.contractId != filters.contractId!.trim()) {
        continue;
      }
      final ownerId = ownerIdForProperty(resolvedPropertyId);
      if (filters.ownerId != null &&
          filters.ownerId!.trim().isNotEmpty &&
          ownerId != filters.ownerId!.trim()) {
        continue;
      }

      final voucherItem = VoucherReportItem(
        id: inv.id,
        serialNo: inv.serialNo ?? inv.id,
        date: date,
        createdAt: inv.createdAt,
        contractId: inv.contractId,
        propertyId: resolvedPropertyId,
        tenantId: resolvedTenantId,
        amount: inv.amount.abs(),
        paidAmount: inv.paidAmount.abs(),
        paymentMethod: inv.paymentMethod,
        note: inv.note ?? '',
        direction: direction,
        state: state,
        source: source,
        isServiceInvoice:
            serviceLikeInvoice ||
            source == VoucherSource.services ||
            source == VoucherSource.maintenance,
      );

      if (!filters.includeCancelled && state == VoucherState.cancelled) {
        continue;
      }
      if (!filters.includeDraft && state == VoucherState.draft) {
        continue;
      }
      if (filters.voucherState != null && state != filters.voucherState) {
        continue;
      }
      if (filters.voucherSource != null && source != filters.voucherSource) {
        continue;
      }

      vouchers.add(
        voucherItem,
      );

      final bool isPostedReceipt = state == VoucherState.posted &&
          direction == VoucherDirection.receipt &&
          source == VoucherSource.contracts;
      if (isPostedReceipt) {
        final base = _rentOnlyAmountFromInvoice(inv);
        final linkedOfficeVouchers =
            officeCommissionByContractVoucherId[inv.id] ?? const <Invoice>[];
        final postedOfficeVoucher = linkedOfficeVouchers.firstWhere(
          (voucher) => _detectVoucherState(voucher) == VoucherState.posted,
          orElse: () => Invoice(
            id: '',
            tenantId: '',
            contractId: '',
            propertyId: '',
            issueDate: date,
            dueDate: date,
            amount: 0,
          ),
        );
        final linkedOfficeVoucherId = postedOfficeVoucher.id.trim();
        final double commission = linkedOfficeVoucherId.isNotEmpty
            ? postedOfficeVoucher.amount.abs()
            : 0.0;
        rentRows.add(
          _RentCollectionRow(
            voucherId: inv.id,
            date: date,
            propertyId: inv.propertyId,
            contractId: inv.contractId,
            ownerId: ownerId,
            baseAmount: base,
            commissionAmount: commission,
            officeVoucherId: linkedOfficeVoucherId,
          ),
        );
      }
    }

    int compareVoucherTabOrder(VoucherReportItem a, VoucherReportItem b) {
      final dateCmp = b.date.compareTo(a.date);
      if (dateCmp != 0) return dateCmp;
      final createdCmp = b.createdAt.compareTo(a.createdAt);
      if (createdCmp != 0) return createdCmp;
      return b.id.compareTo(a.id);
    }

    vouchers.sort(compareVoucherTabOrder);
    voucherTabItems.sort(compareVoucherTabOrder);

    final approved = vouchers.where((v) => v.state == VoucherState.posted);
    final officeCommissionRevenue = approved
        .where((v) =>
            v.source == VoucherSource.officeCommission &&
            v.direction == VoucherDirection.receipt)
        .fold<double>(0, (p, v) => p + v.amount);
    final totalReceipts = approved
            .where(_countsTowardOperationalReceipt)
            .fold<double>(0, (p, v) => p + v.amount) +
        officeCommissionRevenue;
    final totalExpenses = approved
        .where(_countsTowardOperationalExpense)
        .fold<double>(0, (p, v) => p + v.amount);
    final rentCollected = approved
        .where((v) =>
            v.source == VoucherSource.contracts &&
            v.direction == VoucherDirection.receipt)
        .fold<double>(0, (p, v) => p + v.amount);
    final ownerTransferred = approved
        .where((v) => v.source == VoucherSource.ownerPayout)
        .fold<double>(0, (p, v) => p + v.amount);
    final unpaidServiceBills = vouchers
        .where((v) =>
            _isServiceVoucherItem(v) &&
            v.state == VoucherState.draft)
        .fold<double>(0, (p, v) => p + v.amount);

    final dashboard = DashboardSummary(
      totalReceipts: totalReceipts,
      totalExpenses: totalExpenses,
      netCashFlow: totalReceipts - totalExpenses,
      rentCollected: rentCollected,
      officeCommissions: officeCommissionRevenue,
      ownerTransferred: ownerTransferred,
      unpaidServiceBills: unpaidServiceBills,
      approvedVouchers: approved.length,
      approvedReceiptVouchers:
          approved.where((v) => v.direction == VoucherDirection.receipt).length,
      approvedPaymentVouchers:
          approved.where((v) => v.direction == VoucherDirection.payment).length,
    );

    final propertiesRows = <PropertyReportItem>[];
    for (final p in properties) {
      if (filters.propertyId != null &&
          filters.propertyId!.trim().isNotEmpty &&
          p.id != filters.propertyId!.trim()) {
        continue;
      }
      final ownerId = ownerIdForProperty(p.id);
      if (filters.ownerId != null &&
          filters.ownerId!.trim().isNotEmpty &&
          ownerId != filters.ownerId!.trim()) {
        continue;
      }
      final propertyScope = propertyScopeIds(p);
      final propertyContracts = contracts
          .where((c) => matchesScopedPropertyId(c.propertyId, propertyScope))
          .toList(growable: false);
      final propertyVouchers = vouchers
          .where((v) => matchesScopedPropertyId(v.propertyId, propertyScope))
          .toList(growable: false);

      final activeContracts =
          propertyContracts.where((c) => _contractStatus(c) == 'نشط').length;
      final endedContracts =
          propertyContracts.where((c) => _contractStatus(c) == 'منتهي').length;
      final revenues = propertyVouchers
          .where(_countsTowardOperationalReceipt)
          .fold<double>(0, (sum, v) => sum + v.amount);
      final expenses = propertyVouchers
          .where((v) =>
              v.state == VoucherState.posted &&
              v.direction == VoucherDirection.payment)
          .fold<double>(0, (sum, v) => sum + v.amount);
      final serviceExpenses = propertyVouchers
          .where((v) =>
              v.state == VoucherState.posted &&
              v.direction == VoucherDirection.payment &&
              _isServiceVoucherItem(v))
          .fold<double>(0, (sum, v) => sum + v.amount);

      var latePayments = 0;
      var upcomingPayments = 0;
      var overdueAmount = 0.0;
      for (final c in propertyContracts) {
        latePayments += countOverduePayments(c);
        upcomingPayments += countNearDuePayments(c) + countDueTodayPayments(c);
        overdueAmount +=
            perCycleAmountForContract(c) * countOverduePayments(c).toDouble();
      }

      propertiesRows.add(
        PropertyReportItem(
          propertyId: p.id,
          propertyName: p.name,
          ownerId: ownerId,
          ownerName: ownerNameForId(ownerId),
          type: p.type,
          isOccupied: activeContracts > 0 || p.occupiedUnits > 0,
          activeContracts: activeContracts,
          endedContracts: endedContracts,
          receivedPayments:
              propertyVouchers.where(_countsTowardOperationalReceipt).length,
          latePayments: latePayments,
          upcomingPayments: upcomingPayments,
          linkedVouchers: propertyVouchers.length,
          revenues: revenues,
          expenses: expenses,
          serviceExpenses: serviceExpenses,
          overdueAmount: overdueAmount,
          net: revenues - expenses,
        ),
      );
    }
    propertiesRows.sort((a, b) => b.net.compareTo(a.net));

    final contractsRows = <ContractReportItem>[];
    for (final c in contracts) {
      if (filters.contractId != null &&
          filters.contractId!.trim().isNotEmpty &&
          c.id != filters.contractId!.trim()) {
        continue;
      }
      if (!matchesSelectedPropertyFilter(c.propertyId)) {
        continue;
      }

      final status = _contractStatus(c);
      if (filters.contractStatus != null &&
          filters.contractStatus!.trim().isNotEmpty &&
          status != filters.contractStatus!.trim()) {
        continue;
      }

      final ownerId = ownerIdForProperty(c.propertyId);
      if (filters.ownerId != null &&
          filters.ownerId!.trim().isNotEmpty &&
          ownerId != filters.ownerId!.trim()) {
        continue;
      }

      final linked = vouchers
          .where(
              (v) => v.contractId == c.id && v.state != VoucherState.cancelled)
          .toList(growable: false);
      final contractLinked = linked
          .where((v) => v.source != VoucherSource.officeCommission)
          .toList(growable: false);
      final paidAmount = contractLinked
          .where(_countsTowardContractReceipt)
          .fold<double>(0, (sum, v) => sum + v.amount);
      final remaining = math.max(0, c.totalAmount - paidAmount).toDouble();
      final overdueInstallments = countOverduePayments(c);
      final upcomingInstallments =
          countNearDuePayments(c) + countDueTodayPayments(c);
      final nextDueDate = _nextUnpaidDueDate(c, contractLinked);
      final overdueAmount =
          perCycleAmountForContract(c) * overdueInstallments.toDouble();

      contractsRows.add(
        ContractReportItem(
          contractId: c.id,
          contractNo: (c.serialNo ?? '').trim().isEmpty ? c.id : c.serialNo!,
          propertyId: c.propertyId,
          propertyName: propertyById[c.propertyId]?.name ?? c.propertyId,
          tenantId: c.tenantId,
          tenantName: tenantById[c.tenantId]?.fullName ?? c.tenantId,
          ownerId: ownerId,
          ownerName: ownerNameForId(ownerId),
          status: status,
          totalAmount: c.totalAmount,
          paidAmount: paidAmount,
          remainingAmount: remaining,
          overdueInstallments: overdueInstallments,
          upcomingInstallments: upcomingInstallments,
          nextDueDate: nextDueDate,
          linkedVouchers: contractLinked.length,
          overdueAmount: overdueAmount,
        ),
      );
    }
    contractsRows.sort((a, b) => b.contractNo.compareTo(a.contractNo));

    final servicesRows = <ServiceReportItem>[];
    for (final v in vouchers) {
      if (!_isServiceVoucherItem(v)) {
        continue;
      }
      final serviceType = _detectServiceType(v.note);
      if (filters.serviceType != null &&
          filters.serviceType!.trim().isNotEmpty &&
          serviceType != filters.serviceType!.trim()) {
        continue;
      }
      final ownerId = ownerIdForProperty(v.propertyId);
      servicesRows.add(
        ServiceReportItem(
          id: v.id,
          serviceType: serviceType,
          propertyId: v.propertyId,
          propertyName: propertyById[v.propertyId]?.name ?? v.propertyId,
          ownerId: ownerId,
          ownerName: ownerNameForId(ownerId),
          date: v.date,
          amount: v.amount,
          isPaid: v.state == VoucherState.posted,
          state: v.state,
          statusLabel: v.state.arLabel,
          linkedVoucherId: v.id,
          details: v.note,
        ),
      );
    }

    for (final m in maintenance) {
      final d =
          _dateOnly(m.executionDeadline ?? m.completedDate ?? m.createdAt);
      if (!filters.inRange(d)) continue;
      final linkedId = (m.invoiceId ?? '').trim();
      final exists = linkedId.isNotEmpty &&
          servicesRows.any((e) => e.linkedVoucherId == linkedId);
      if (exists) continue;
      final serviceType = _detectServiceType('${m.requestType} ${m.title}');
      if (filters.serviceType != null &&
          filters.serviceType!.trim().isNotEmpty &&
          serviceType != filters.serviceType!.trim()) {
        continue;
      }
      if (!matchesSelectedPropertyFilter(m.propertyId)) {
        continue;
      }
      final ownerId = ownerIdForProperty(m.propertyId);
      if (filters.ownerId != null &&
          filters.ownerId!.trim().isNotEmpty &&
          ownerId != filters.ownerId!.trim()) {
        continue;
      }
      servicesRows.add(
        ServiceReportItem(
          id: m.id,
          serviceType: serviceType,
          propertyId: m.propertyId,
          propertyName: propertyById[m.propertyId]?.name ?? m.propertyId,
          ownerId: ownerId,
          ownerName: ownerNameForId(ownerId),
          date: d,
          amount: m.cost.abs(),
          isPaid: false,
          state: VoucherState.draft,
          statusLabel: 'غير مسدد',
          linkedVoucherId: linkedId,
          details: m.title,
        ),
      );
    }
    servicesRows.sort((a, b) => b.date.compareTo(a.date));

    final ownerIds = <String>{};
    ownerIds.addAll(
      tenants
          .where((t) {
            final type = t.clientType.toLowerCase();
            return type.contains('owner') || type.contains('مالك');
          })
          .map((t) => t.id),
    );
    for (final rawOwnerMap in ownerMapBox.values) {
      if (rawOwnerMap is Map) {
        final id = (rawOwnerMap['ownerId'] ?? '').toString().trim();
        if (id.isNotEmpty) ownerIds.add(id);
      } else if (rawOwnerMap is String && rawOwnerMap.trim().isNotEmpty) {
        ownerIds.add(rawOwnerMap.trim());
      }
    }
    for (final p in properties) {
      final id = ownerIdForProperty(p.id);
      if (id.isNotEmpty) ownerIds.add(id);
    }
    if (ownerIds.isEmpty && currentWorkspaceOwnerId.isNotEmpty) {
      ownerIds.add(currentWorkspaceOwnerId);
    }
    if (filters.ownerId != null && filters.ownerId!.trim().isNotEmpty) {
      ownerIds
        ..clear()
        ..add(filters.ownerId!.trim());
    }

    bool matchesOwnerPropertyRecord({
      required String recordPropertyId,
      required String targetPropertyId,
      required bool allowUnassignedFallback,
    }) {
      final normalizedRecord = recordPropertyId.trim();
      final normalizedTarget = targetPropertyId.trim();
      if (normalizedRecord.isEmpty) return allowUnassignedFallback;
      if (normalizedRecord == normalizedTarget) return true;
      final targetProperty = propertyById[normalizedTarget];
      if (targetProperty == null) return false;
      return propertyScopeIds(targetProperty).contains(normalizedRecord);
    }

    final ownersRows = <OwnerReportItem>[];
    for (final ownerId in ownerIds) {
      final ownerName = ownerNameForId(ownerId);
      final ownerAllProperties = properties
          .where((p) => ownerIdForProperty(p.id) == ownerId)
          .toList(growable: false);
      final ownerTopLevelProperties = ownerAllProperties.where((property) {
        final parentId = (property.parentBuildingId ?? '').trim();
        if (parentId.isEmpty) return true;
        return !ownerAllProperties.any((candidate) => candidate.id == parentId);
      }).toList(growable: false);
      final filteredPropertyId = (filters.propertyId ?? '').trim();
      final ownerPropertyList = filteredPropertyId.isEmpty
          ? ownerTopLevelProperties.toList(growable: false)
          : ownerAllProperties
              .where((p) => p.id == filteredPropertyId)
              .toList(growable: false);
      final ownerPropertyIds = ownerPropertyList.map((p) => p.id).toSet();
      final ownerPropertyScopeIds = ownerScopePropertyIds(ownerPropertyList);
      final canFallbackUnassignedToSingleProperty =
          ownerAllProperties.length == 1;

      final ownerRentRows =
          rentRows.where((r) => r.ownerId == ownerId).toList(growable: false);
      bool matchesManualOfficeCommissionOwner(Invoice invoice) {
        final invoicePropertyId = invoice.propertyId.trim();
        if (invoicePropertyId.isNotEmpty) {
          return ownerIdForProperty(invoicePropertyId) == ownerId;
        }
        final invoiceOwnerId = invoice.tenantId.trim();
        if (invoiceOwnerId.isNotEmpty) {
          return invoiceOwnerId == ownerId;
        }
        if (currentWorkspaceOwnerId.isNotEmpty) {
          return ownerId == currentWorkspaceOwnerId;
        }
        return ownerIds.length == 1;
      }

      final ownerManualCommissionInvoices = invoices
          .where((invoice) {
            if (_detectVoucherSource(invoice) != VoucherSource.officeCommission) {
              return false;
            }
            if (_officeCommissionLinkedContractVoucherId(invoice.note).isNotEmpty) {
              return false;
            }
            if (!matchesManualOfficeCommissionOwner(invoice)) return false;
            final state = _detectVoucherState(invoice);
            if (state == VoucherState.draft) return false;
            if (!filters.inRange(_dateOnly(invoice.issueDate))) return false;
            if (filteredPropertyId.isEmpty) return true;
            return matchesOwnerPropertyRecord(
              recordPropertyId: invoice.propertyId,
              targetPropertyId: filteredPropertyId,
              allowUnassignedFallback: canFallbackUnassignedToSingleProperty,
            );
          })
          .toList(growable: false);
      final collectedRent =
          ownerRentRows.fold<double>(0, (sum, e) => sum + e.baseAmount);
      final automaticCommissions =
          ownerRentRows.fold<double>(0, (sum, e) => sum + e.commissionAmount);
      final manualCommissions = ownerManualCommissionInvoices
          .where((invoice) => _detectVoucherState(invoice) == VoucherState.posted)
          .fold<double>(0, (sum, invoice) => sum + invoice.amount.abs());
      final comm = automaticCommissions + manualCommissions;

      final ownerExpenses = vouchers
          .where((v) =>
              v.state == VoucherState.posted &&
              v.direction == VoucherDirection.payment &&
              matchesScopedPropertyId(v.propertyId, ownerPropertyScopeIds) &&
              _isServiceVoucherItem(v))
          .fold<double>(0, (sum, v) => sum + v.amount);

      final ownerPayout = payoutRecords
          .where((p) =>
              p.ownerId == ownerId &&
              p.status == OwnerPayoutStatus.posted &&
              filters.inRange(p.postedAt ?? p.createdAt) &&
              (filteredPropertyId.isEmpty ||
                  matchesOwnerPropertyRecord(
                    recordPropertyId: p.propertyId,
                    targetPropertyId: filteredPropertyId,
                    allowUnassignedFallback:
                        canFallbackUnassignedToSingleProperty,
                  )))
          .fold<double>(0, (sum, p) => sum + p.amount.abs());

      final ownerAdjustments = adjustmentRecords
          .where((a) =>
              a.ownerId == ownerId &&
              a.status == OwnerPayoutStatus.posted &&
              filters.inRange(a.postedAt ?? a.createdAt) &&
              (filteredPropertyId.isEmpty ||
                  matchesOwnerPropertyRecord(
                    recordPropertyId: a.propertyId,
                    targetPropertyId: filteredPropertyId,
                    allowUnassignedFallback:
                        canFallbackUnassignedToSingleProperty,
                  )))
          .fold<double>(0, (sum, a) => sum + a.amount.abs());

      final voucherPayout = vouchers
          .where((v) =>
              v.source == VoucherSource.ownerPayout &&
              v.state == VoucherState.posted &&
              _extractOwnerIdFromNote(v.note) == ownerId &&
              (filteredPropertyId.isEmpty ||
                  matchesOwnerPropertyRecord(
                    recordPropertyId: v.propertyId,
                    targetPropertyId: filteredPropertyId,
                    allowUnassignedFallback:
                        canFallbackUnassignedToSingleProperty,
                  )))
          .fold<double>(0, (sum, v) => sum + v.amount.abs());

      final previousTransfers =
          ownerPayout > voucherPayout ? ownerPayout : voucherPayout;

      final currentBalance = collectedRent -
          comm -
          ownerExpenses -
          ownerAdjustments -
          previousTransfers;
      final ready = math.max(0, currentBalance).toDouble();

      final propertyBreakdowns = ownerPropertyList
          .map((property) {
            final propertyScope = propertyScopeIds(property);
            final propertyRentRows = ownerRentRows
                .where((row) => matchesScopedPropertyId(row.propertyId, propertyScope))
                .toList(growable: false);
            final propertyCollectedRent = propertyRentRows.fold<double>(
              0,
              (sum, row) => sum + row.baseAmount,
            );
            final propertyAutomaticCommissions = propertyRentRows.fold<double>(
              0,
              (sum, row) => sum + row.commissionAmount,
            );
            final propertyManualCommissions = ownerManualCommissionInvoices
                .where((invoice) =>
                    matchesOwnerPropertyRecord(
                      recordPropertyId: invoice.propertyId,
                      targetPropertyId: property.id,
                      allowUnassignedFallback:
                          canFallbackUnassignedToSingleProperty,
                    ) &&
                    _detectVoucherState(invoice) == VoucherState.posted)
                .fold<double>(0, (sum, invoice) => sum + invoice.amount.abs());
            final propertyCommissions =
                propertyAutomaticCommissions + propertyManualCommissions;
            final propertyExpenses = vouchers
                .where((v) =>
                    v.state == VoucherState.posted &&
                    v.direction == VoucherDirection.payment &&
                    matchesScopedPropertyId(v.propertyId, propertyScope) &&
                    _isServiceVoucherItem(v))
                .fold<double>(0, (sum, v) => sum + v.amount);
            final propertyAdjustments = adjustmentRecords
                .where((a) =>
                    a.ownerId == ownerId &&
                    a.status == OwnerPayoutStatus.posted &&
                    filters.inRange(a.postedAt ?? a.createdAt) &&
                    matchesOwnerPropertyRecord(
                      recordPropertyId: a.propertyId,
                      targetPropertyId: property.id,
                      allowUnassignedFallback:
                          canFallbackUnassignedToSingleProperty,
                    ))
                .fold<double>(0, (sum, a) => sum + a.amount.abs());
            final propertyOwnerPayout = payoutRecords
                .where((p) =>
                    p.ownerId == ownerId &&
                    p.status == OwnerPayoutStatus.posted &&
                    filters.inRange(p.postedAt ?? p.createdAt) &&
                    matchesOwnerPropertyRecord(
                      recordPropertyId: p.propertyId,
                      targetPropertyId: property.id,
                      allowUnassignedFallback:
                          canFallbackUnassignedToSingleProperty,
                    ))
                .fold<double>(0, (sum, p) => sum + p.amount.abs());
            final propertyVoucherPayout = vouchers
                .where((v) =>
                    v.source == VoucherSource.ownerPayout &&
                    v.state == VoucherState.posted &&
                    _extractOwnerIdFromNote(v.note) == ownerId &&
                    matchesOwnerPropertyRecord(
                      recordPropertyId: v.propertyId,
                      targetPropertyId: property.id,
                      allowUnassignedFallback:
                          canFallbackUnassignedToSingleProperty,
                    ))
                .fold<double>(0, (sum, v) => sum + v.amount.abs());
            final propertyPreviousTransfers =
                propertyOwnerPayout > propertyVoucherPayout
                    ? propertyOwnerPayout
                    : propertyVoucherPayout;
            final propertyCurrentBalance = propertyCollectedRent -
                propertyCommissions -
                propertyExpenses -
                propertyAdjustments -
                propertyPreviousTransfers;

            return OwnerPropertyReportItem(
              propertyId: property.id,
              propertyName: property.name,
              rentCollected: propertyCollectedRent,
              officeCommissions: propertyCommissions,
              ownerExpenses: propertyExpenses,
              ownerAdjustments: propertyAdjustments,
              previousTransfers: propertyPreviousTransfers,
              currentBalance: propertyCurrentBalance,
              readyForPayout: math.max(0, propertyCurrentBalance).toDouble(),
            );
          })
          .toList(growable: true)
        ..sort((a, b) => a.propertyName.compareTo(b.propertyName));

      final ledger = <OwnerLedgerEntry>[];
      var running = 0.0;
      final tmp = <OwnerLedgerEntry>[];

      for (final rr in ownerRentRows) {
        tmp.add(
          OwnerLedgerEntry(
            id: 'rent_${rr.voucherId}',
            date: rr.date,
            sortDate: rr.date,
            description: 'تحصيل إيجار',
            type: 'rent',
            debit: 0,
            credit: rr.baseAmount,
            referenceId: rr.voucherId,
            balanceAfter: 0,
            voucherState: VoucherState.posted,
          ),
        );
        if (rr.commissionAmount > 0) {
          tmp.add(
            OwnerLedgerEntry(
              id: 'com_${rr.voucherId}',
              date: rr.date,
              sortDate: rr.date,
              description: 'خصم عمولة المكتب',
              type: 'commission',
              debit: rr.commissionAmount,
              credit: 0,
              referenceId: rr.voucherId,
              balanceAfter: 0,
              voucherState: VoucherState.posted,
            ),
          );
        }
      }

      for (final invoice in ownerManualCommissionInvoices) {
        tmp.add(
          OwnerLedgerEntry(
            id: 'manual_com_${invoice.id}',
            date: _dateOnly(invoice.issueDate),
            sortDate: invoice.createdAt,
            description: 'خصم عمولة المكتب',
            type: 'commission',
            debit: invoice.amount.abs(),
            credit: 0,
            referenceId: invoice.id,
            balanceAfter: 0,
            voucherState: _detectVoucherState(invoice),
          ),
        );
      }

      for (final v in vouchers.where((v) =>
          v.state == VoucherState.posted &&
          v.direction == VoucherDirection.payment &&
          matchesScopedPropertyId(v.propertyId, ownerPropertyScopeIds) &&
          _isServiceVoucherItem(v))) {
        tmp.add(
          OwnerLedgerEntry(
            id: 'exp_${v.id}',
            date: v.date,
            sortDate: v.date,
            description: 'مصروف محمّل على المالك',
            type: 'expense',
            debit: v.amount,
            credit: 0,
            referenceId: v.id,
            balanceAfter: 0,
            voucherState: v.state,
          ),
        );
      }

      for (final p in payoutRecords.where((p) =>
          p.ownerId == ownerId &&
          p.status != OwnerPayoutStatus.draft &&
          filters.inRange(p.postedAt ?? p.createdAt) &&
          (filteredPropertyId.isEmpty ||
              matchesOwnerPropertyRecord(
                recordPropertyId: p.propertyId,
                targetPropertyId: filteredPropertyId,
                allowUnassignedFallback:
                    canFallbackUnassignedToSingleProperty,
              )))) {
        tmp.add(
          OwnerLedgerEntry(
            id: 'payout_${p.id}',
            date: p.postedAt ?? p.createdAt,
            sortDate: p.createdAt,
            description: 'تحويل للمالك',
            type: 'payout',
            debit: p.amount.abs(),
            credit: 0,
            referenceId: p.voucherId.isEmpty ? p.id : p.voucherId,
            balanceAfter: 0,
            voucherState: _voucherStateFromOwnerStatus(p.status),
          ),
        );
      }

      for (final a in adjustmentRecords.where((a) =>
          a.ownerId == ownerId &&
          a.status != OwnerPayoutStatus.draft &&
          filters.inRange(a.postedAt ?? a.createdAt) &&
          (filteredPropertyId.isEmpty ||
              matchesOwnerPropertyRecord(
                recordPropertyId: a.propertyId,
                targetPropertyId: filteredPropertyId,
                allowUnassignedFallback:
                    canFallbackUnassignedToSingleProperty,
              )))) {
        tmp.add(
          OwnerLedgerEntry(
            id: 'adj_${a.id}',
            date: a.postedAt ?? a.createdAt,
            sortDate: a.createdAt,
            description: 'خصم/تسوية: ${a.category.arLabel}',
            type: 'adjustment',
            debit: a.amount.abs(),
            credit: 0,
            referenceId: a.voucherId.isEmpty ? a.id : a.voucherId,
            balanceAfter: 0,
            voucherState: _voucherStateFromOwnerStatus(a.status),
          ),
        );
      }

      tmp.sort((a, b) => a.sortDate.compareTo(b.sortDate));
      for (final e in tmp) {
        if (e.voucherState == null || e.voucherState == VoucherState.posted) {
          running += (e.credit - e.debit);
        }
        ledger.add(
          OwnerLedgerEntry(
            id: e.id,
            date: e.date,
            sortDate: e.sortDate,
            description: e.description,
            type: e.type,
            debit: e.debit,
            credit: e.credit,
            referenceId: e.referenceId,
            balanceAfter: running,
            voucherState: e.voucherState,
          ),
        );
      }
      ledger.sort((a, b) => b.sortDate.compareTo(a.sortDate));

      ownersRows.add(
        OwnerReportItem(
          ownerId: ownerId,
          ownerName: ownerName,
          previousBalance: 0,
          rentCollected: collectedRent,
          officeCommissions: comm,
          ownerExpenses: ownerExpenses,
          ownerAdjustments: ownerAdjustments,
          previousTransfers: previousTransfers,
          currentBalance: currentBalance,
          readyForPayout: ready,
          ledger: ledger,
          linkedProperties: ownerPropertyIds.length,
          propertyBreakdowns: propertyBreakdowns,
        ),
      );
    }
    ownersRows.sort((a, b) => b.readyForPayout.compareTo(a.readyForPayout));

    final officeExpenses = approved
        .where((v) =>
            v.direction == VoucherDirection.payment &&
            (v.source == VoucherSource.manual || v.source == VoucherSource.other))
        .fold<double>(0, (sum, v) => sum + v.amount);
    final officeWithdrawals = approved
        .where((v) =>
            v.direction == VoucherDirection.payment &&
            v.source == VoucherSource.officeWithdrawal)
        .fold<double>(0, (sum, v) => sum + v.amount);

    final officeLedgerTemp = <OfficeLedgerEntry>[];
    final officeCommissionInvoices = invoices
        .where(
          (invoice) =>
              _detectVoucherSource(invoice) == VoucherSource.officeCommission &&
              _detectVoucherState(invoice) != VoucherState.draft,
        )
        .toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final invoice in officeCommissionInvoices) {
      final state = _detectVoucherState(invoice);
      final propertyName = _officeCommissionPropertyReference(
        invoice.propertyId,
        propertyById,
      );
      final contractNo = _officeCommissionContractReference(
        contractById[invoice.contractId],
        ejarMapBox: contractsEjarBox,
      );
      final cleanNote = _cleanVoucherDisplayNote(invoice.note);
      officeLedgerTemp.add(
        OfficeLedgerEntry(
          id: 'office_commission_${invoice.id}',
          date: _dateOnly(invoice.issueDate),
          sortDate: invoice.createdAt,
          description: cleanNote.isEmpty
              ? _officeCommissionDescription(
                  contractNo: contractNo,
                  propertyName: propertyName,
                )
              : cleanNote,
          type: 'commission',
          debit: state == VoucherState.reversed ? invoice.amount.abs() : 0,
          credit: state == VoucherState.reversed ? 0 : invoice.amount.abs(),
          referenceId: invoice.id,
          balanceAfter: 0,
          voucherState: state,
        ),
      );
    }
    for (final voucher in approved.where((v) =>
        v.direction == VoucherDirection.payment &&
        (v.source == VoucherSource.manual || v.source == VoucherSource.other))) {
      final cleanNote = _cleanVoucherDisplayNote(voucher.note);
      officeLedgerTemp.add(
        OfficeLedgerEntry(
          id: 'office_expense_${voucher.id}',
          date: voucher.date,
          sortDate: invoiceById[voucher.id]?.createdAt ?? voucher.date,
          description: cleanNote.isEmpty ? 'مصروف مكتب' : cleanNote,
          type: 'expense',
          debit: voucher.amount,
          credit: 0,
          referenceId: voucher.id,
          balanceAfter: 0,
          voucherState: voucher.state,
        ),
      );
    }
    for (final voucher in approved.where((v) =>
        v.direction == VoucherDirection.payment &&
        v.source == VoucherSource.officeWithdrawal)) {
      final cleanNote = _cleanVoucherDisplayNote(voucher.note);
      officeLedgerTemp.add(
        OfficeLedgerEntry(
          id: 'office_withdrawal_${voucher.id}',
          date: voucher.date,
          sortDate: invoiceById[voucher.id]?.createdAt ?? voucher.date,
          description:
              cleanNote.isEmpty ? 'تحويل من رصيد المكتب' : cleanNote,
          type: 'withdrawal',
          debit: voucher.amount,
          credit: 0,
          referenceId: voucher.id,
          balanceAfter: 0,
          voucherState: voucher.state,
        ),
      );
    }
    officeLedgerTemp.sort((a, b) => a.sortDate.compareTo(b.sortDate));
    var officeRunningBalance = 0.0;
    final officeLedger = <OfficeLedgerEntry>[];
    for (final entry in officeLedgerTemp) {
        if (entry.voucherState == null || entry.voucherState == VoucherState.posted) {
          officeRunningBalance += entry.credit - entry.debit;
        }
      officeLedger.add(
        OfficeLedgerEntry(
          id: entry.id,
          date: entry.date,
          sortDate: entry.sortDate,
          description: entry.description,
          type: entry.type,
          debit: entry.debit,
          credit: entry.credit,
          referenceId: entry.referenceId,
          balanceAfter: officeRunningBalance,
          voucherState: entry.voucherState,
        ),
      );
    }
    officeLedger.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    final officeNetProfit = officeCommissionRevenue - officeExpenses;
    final officeRemainingProfit = officeNetProfit - officeWithdrawals;

    final office = OfficeReportSummary(
      commissionRevenue: officeCommissionRevenue,
      officeExpenses: officeExpenses,
      officeWithdrawals: officeWithdrawals,
      netProfit: officeNetProfit,
      currentBalance: officeRemainingProfit,
      receiptVouchers:
          approved.where((v) => v.direction == VoucherDirection.receipt).length,
      paymentVouchers:
          approved.where((v) => v.direction == VoucherDirection.payment).length,
      ledger: officeLedger,
    );

    final propertyNames = <String, String>{
      for (final p in properties) p.id: p.name,
    };
    final ownerNames = <String, String>{
      for (final id in ownerIds) id: ownerNameForId(id),
    };
    final tenantNames = <String, String>{
      for (final t in tenants) t.id: t.fullName,
    };
    final contractNumbers = <String, String>{
      for (final c in contracts) c.id: (c.serialNo ?? c.id),
    };

    return ComprehensiveReportSnapshot(
      dashboard: dashboard,
      properties: propertiesRows,
      contracts: contractsRows,
      services: servicesRows,
      owners: ownersRows,
      office: office,
      vouchers: voucherTabItems,
      ownerPayouts: payoutRecords,
      ownerAdjustments: adjustmentRecords,
      propertyNames: propertyNames,
      ownerNames: ownerNames,
      tenantNames: tenantNames,
      contractNumbers: contractNumbers,
    );
  }

  static Future<void> _ensureMapBox(String name) async {
    if (Hive.isBoxOpen(name)) return;
    await Hive.openBox(name);
  }

  static Box<dynamic>? _mapBoxIfOpen(String name) {
    if (!Hive.isBoxOpen(name)) return null;
    try {
      return Hive.box(name);
    } catch (_) {
      return null;
    }
  }

  static List<T> _safeValues<T>(String boxNameValue) {
    if (!Hive.isBoxOpen(boxNameValue)) return <T>[];
    try {
      return Hive.box<T>(boxNameValue).values.toList(growable: false);
    } catch (_) {
      return <T>[];
    }
  }

  static String _commissionKey(CommissionScope scope, String? scopeId) {
    switch (scope) {
      case CommissionScope.global:
        return 'commission::global';
      case CommissionScope.owner:
        return 'commission::owner::${(scopeId ?? '').trim()}';
      case CommissionScope.property:
        return 'commission::property::${(scopeId ?? '').trim()}';
      case CommissionScope.contract:
        return 'commission::contract::${(scopeId ?? '').trim()}';
    }
  }

  static String _newId() => KsaTime.now().microsecondsSinceEpoch.toString();

  static String _nextInvoiceSerial(Box<Invoice> invoices) {
    final year = KsaTime.now().year;
    var maxSeq = 0;
    for (final inv in invoices.values) {
      final s = inv.serialNo;
      if (s == null || !s.startsWith('$year-')) continue;
      final n = int.tryParse(s.split('-').last) ?? 0;
      if (n > maxSeq) maxSeq = n;
    }
    final next = maxSeq + 1;
    return '$year-${next.toString().padLeft(4, '0')}';
  }
}

class _RentCollectionRow {
  final String voucherId;
  final DateTime date;
  final String propertyId;
  final String contractId;
  final String ownerId;
  final double baseAmount;
  final double commissionAmount;
  final String officeVoucherId;

  const _RentCollectionRow({
    required this.voucherId,
    required this.date,
    required this.propertyId,
    required this.contractId,
    required this.ownerId,
    required this.baseAmount,
    required this.commissionAmount,
    this.officeVoucherId = '',
  });
}

bool _countsTowardOperationalReceipt(VoucherReportItem voucher) {
  return voucher.state == VoucherState.posted &&
      voucher.direction == VoucherDirection.receipt &&
      voucher.source != VoucherSource.officeCommission &&
      voucher.source != VoucherSource.ownerAdjustment;
}

bool _countsTowardOperationalExpense(VoucherReportItem voucher) {
  return voucher.state == VoucherState.posted &&
      voucher.direction == VoucherDirection.payment &&
      voucher.source != VoucherSource.officeWithdrawal &&
      voucher.source != VoucherSource.ownerPayout;
}

bool _countsTowardContractReceipt(VoucherReportItem voucher) {
  return voucher.state == VoucherState.posted &&
      voucher.direction == VoucherDirection.receipt &&
      voucher.source == VoucherSource.contracts;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _dateFromAny(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {
      return null;
    }
  }
  if (v is String) return DateTime.tryParse(v);
  return null;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

class _HistoricalCommissionSnapshot {
  final CommissionMode mode;
  final double value;
  final double amount;

  const _HistoricalCommissionSnapshot({
    required this.mode,
    required this.value,
    required this.amount,
  });
}

_HistoricalCommissionSnapshot? _historicalCommissionSnapshotFromContractVoucher(
  Invoice invoice,
) {
  final rawMode =
      (_manualVoucherMarkerValue(invoice.note, 'COMMISSION_MODE') ?? '')
          .trim()
          .toLowerCase();
  if (rawMode.isEmpty) return null;
  final mode = rawMode == CommissionMode.percent.name
      ? CommissionMode.percent
      : rawMode == CommissionMode.fixed.name
          ? CommissionMode.fixed
          : CommissionMode.unspecified;
  return _HistoricalCommissionSnapshot(
    mode: mode,
    value: _toDouble(_manualVoucherMarkerValue(invoice.note, 'COMMISSION_VALUE')),
    amount:
        _toDouble(_manualVoucherMarkerValue(invoice.note, 'COMMISSION_AMOUNT')),
  );
}

VoucherState _detectVoucherState(Invoice inv) {
  if (inv.isCanceled) return VoucherState.cancelled;
  final note = (inv.note ?? '').toLowerCase();
  if (note.contains('[reversal]') || note.contains('معكوس')) {
    return VoucherState.reversed;
  }
  final due = inv.amount.abs();
  if (inv.paidAmount + 0.000001 < due) {
    return VoucherState.draft;
  }
  return VoucherState.posted;
}

String? _manualVoucherMarkerValue(String? note, String key) {
  final text = (note ?? '').trim();
  if (text.isEmpty) return null;
  final exp = RegExp('\\[$key:(.*?)\\]', caseSensitive: false);
  final match = exp.firstMatch(text);
  final value = match?.group(1)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

String _resolvedVoucherPropertyId(Invoice inv, VoucherSource source) {
  final direct = inv.propertyId.trim();
  if (direct.isNotEmpty) return direct;
  final maintenanceProperty =
      (inv.maintenanceSnapshot?['propertyId'] ?? '').toString().trim();
  if (maintenanceProperty.isNotEmpty) return maintenanceProperty;
  final isServiceLike = source == VoucherSource.services ||
      source == VoucherSource.maintenance ||
      _looksLikeGeneratedServiceVoucherNote(inv.note ?? '');
  if (source != VoucherSource.manual && !isServiceLike) {
    return '';
  }
  return (_manualVoucherMarkerValue(inv.note, 'PROPERTY_ID') ?? '').trim();
}

String _resolvedVoucherTenantId(Invoice inv, VoucherSource source) {
  final direct = inv.tenantId.trim();
  if (direct.isNotEmpty) return direct;
  final maintenanceTenant =
      (inv.maintenanceSnapshot?['tenantId'] ?? '').toString().trim();
  if (maintenanceTenant.isNotEmpty) return maintenanceTenant;
  final isServiceLike = source == VoucherSource.services ||
      source == VoucherSource.maintenance ||
      _looksLikeGeneratedServiceVoucherNote(inv.note ?? '');
  if (source != VoucherSource.manual && !isServiceLike) {
    return '';
  }
  return (_manualVoucherMarkerValue(inv.note, 'PARTY_ID') ?? '').trim();
}

String _normalizeServiceHintText(String raw) {
  return raw
      .replaceAll('\u200e', '')
      .replaceAll('\u200f', '')
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .trim();
}

bool _isGeneratedSharedServiceReceiptNote(String raw) {
  final note = _normalizeServiceHintText(raw);
  return note.contains('تحصيل خدمه مياه مشترك') ||
      note.contains('تحصيل خدمه كهرباء مشترك');
}

bool _looksLikeGeneratedServiceVoucherNote(String raw) {
  final note = _normalizeServiceHintText(raw);
  if (note.isEmpty) return false;
  if (note.contains('[service]') || note.contains('[shared_service_office:')) {
    return true;
  }
  final type = _detectServiceType(raw);
  final hasRecognizedServiceType = type == 'water' ||
      type == 'electricity' ||
      type == 'internet' ||
      type == 'cleaning' ||
      type == 'elevator';
  if (!hasRecognizedServiceType) return false;
  final hasMetadataMarker = note.contains('[title:') ||
      note.contains('[property:') ||
      note.contains('[property_id:') ||
      note.contains('[party:') ||
      note.contains('[party_id:');
  if (hasMetadataMarker) return true;
  return note.contains('دوره بتاريخ') ||
      note.contains('تاريخ الدوره') ||
      note.contains('دوره الفاتوره') ||
      note.contains('الوحده:') ||
      note.contains('المستاجر:') ||
      note.contains('العقار:') ||
      note.contains('تحصيل خدمه') ||
      note.contains('سداد خدمه');
}

VoucherSource _detectVoucherSource(Invoice inv) {
  final note = (inv.note ?? '').toLowerCase();
  final hasManualMarker = note.contains('[manual]');
  final hasServiceMarker = note.contains('[service]');
  final hasMaintenanceRequestId =
      (inv.maintenanceRequestId ?? '').trim().isNotEmpty;

  if (note.contains('[owner_payout]')) {
    return VoucherSource.ownerPayout;
  }
  if (note.contains('[owner_adjustment]') || note.contains('[owner_discount]')) {
    return VoucherSource.ownerAdjustment;
  }
  if (note.contains('[office_commission]')) {
    return VoucherSource.officeCommission;
  }
  if (note.contains('[office_withdrawal]')) {
    return VoucherSource.officeWithdrawal;
  }
  if (hasMaintenanceRequestId) {
    return VoucherSource.maintenance;
  }
  if (hasServiceMarker) {
    return VoucherSource.services;
  }
  if (hasManualMarker &&
      (_isGeneratedSharedServiceReceiptNote(note) ||
          _looksLikeGeneratedServiceVoucherNote(note))) {
    return VoucherSource.services;
  }
  if (_looksLikeGeneratedServiceVoucherNote(note)) {
    return VoucherSource.services;
  }
  if (hasManualMarker) {
    return VoucherSource.manual;
  }
  if (inv.contractId.trim().isNotEmpty) {
    return VoucherSource.contracts;
  }

  if (note.contains('تحويل مالك') || note.contains('تحويل للمالك')) {
    return VoucherSource.ownerPayout;
  }
  if (note.contains('خصم مستحق') || note.contains('خصم/تسوية للمالك')) {
    return VoucherSource.ownerAdjustment;
  }
  if (note.contains('عمولة المكتب')) {
    return VoucherSource.officeCommission;
  }
  if (note.contains('تحويل من رصيد المكتب') ||
      note.contains('سحب من رصيد المكتب')) {
    return VoucherSource.officeWithdrawal;
  }
  if (note.contains('type=water') ||
      note.contains('type=electricity') ||
      note.contains('type=internet') ||
      note.contains('type=cleaning') ||
      note.contains('type=elevator')) {
    return VoucherSource.services;
  }
  if (note.contains('صيانة') || note.contains('خدمات')) {
    return VoucherSource.maintenance;
  }
  if (note.contains('يدوي') || note.contains('manual')) {
    return VoucherSource.manual;
  }
  return VoucherSource.other;
}

String _detectServiceType(String raw) {
  final t = _normalizeServiceHintText(raw);
  if (t.contains('[shared_service_office: water]') ||
      t.contains('type=water') ||
      t.contains('خدمه مياه مشترك') ||
      t.contains('فاتوره مياه مشترك') ||
      t.contains('تحصيل خدمه مياه مشترك') ||
      t.contains('سداد خدمه مياه مشترك') ||
      t.contains('خدمات مياه') ||
      t.contains('مياه مشترك') ||
      t.contains('water') ||
      t.contains('مياه') ||
      t.contains('ماء')) {
    return 'water';
  }
  if (t.contains('[shared_service_office: electricity]') ||
      t.contains('type=electricity') ||
      t.contains('خدمه كهرباء مشترك') ||
      t.contains('فاتوره كهرباء مشترك') ||
      t.contains('تحصيل خدمه كهرباء مشترك') ||
      t.contains('سداد خدمه كهرباء مشترك') ||
      t.contains('خدمات كهرباء') ||
      t.contains('كهرباء مشترك') ||
      t.contains('electricity') ||
      t.contains('electric') ||
      t.contains('كهرب')) {
    return 'electricity';
  }
  if (t.contains('type=internet') ||
      t.contains('خدمه انترنت') ||
      t.contains('طلب تجديد خدمه انترنت') ||
      t.contains('خدمات انترنت') ||
      t.contains('الانترنت') ||
      t.contains('انترنت') ||
      t.contains('internet')) {
    return 'internet';
  }
  if (t.contains('type=cleaning') ||
      t.contains('نظافه') ||
      t.contains('cleaning')) {
    return 'cleaning';
  }
  if (t.contains('type=elevator') ||
      t.contains('صيانه مصعد') ||
      t.contains('مصعد') ||
      t.contains('اسانسير') ||
      t.contains('elevator')) {
    return 'elevator';
  }
  if (t.contains('maint') || t.contains('صيانة') || t.contains('خدمات')) {
    return 'maintenance';
  }
  return 'other';
}

bool _isServiceVoucherItem(VoucherReportItem voucher) {
  return voucher.source == VoucherSource.services ||
      voucher.source == VoucherSource.maintenance ||
      voucher.isServiceInvoice;
}

double _rentOnlyAmountFromInvoice(Invoice inv) {
  final note = inv.note ?? '';
  final m =
      RegExp(r'مياه\s*\(قسط\)\s*:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(note);
  final water = m == null ? 0.0 : (double.tryParse(m.group(1) ?? '') ?? 0.0);
  final total = inv.amount.abs();
  if (water <= 0) return total;
  if (water >= total) return total;
  return total - water;
}

String _extractOwnerIdFromNote(String note) {
  final m = RegExp(r'owner=([^\s]+)').firstMatch(note);
  if (m == null) return '';
  return (m.group(1) ?? '').trim();
}

String _contractStatus(Contract c) {
  if (c.isTerminated) return 'منهي';
  if (c.term == ContractTerm.daily) {
    final now = KsaTime.now();
    if (now.isBefore(c.dailyStartBoundary)) return 'غير نشط';
    if (!now.isBefore(c.dailyEndBoundary)) return 'منتهي';
    return 'نشط';
  }
  final now = _dateOnly(KsaTime.now());
  final s = _dateOnly(c.startDate);
  final e = _dateOnly(c.endDate);
  if (now.isBefore(s)) return 'غير نشط';
  if (now.isAfter(e)) return 'منتهي';
  return 'نشط';
}

DateTime? _nextUnpaidDueDate(Contract c, List<VoucherReportItem> linked) {
  if (c.term == ContractTerm.daily) {
    final due = _dateOnly(c.startDate);
    final paid = linked.any((v) =>
        _dateOnly(v.date) == due &&
        v.state == VoucherState.posted &&
        v.direction == VoucherDirection.receipt);
    if (!paid) return due;
    return null;
  }
  final dues = _allContractDues(c);
  for (final d in dues) {
    final paid = linked.any((v) =>
        _dateOnly(v.date) == _dateOnly(d) &&
        v.state == VoucherState.posted &&
        v.direction == VoucherDirection.receipt);
    if (!paid) return _dateOnly(d);
  }
  return null;
}

List<DateTime> _allContractDues(Contract c) {
  final out = <DateTime>[];
  final start = _dateOnly(c.startDate);
  final end = _dateOnly(c.endDate);
  if (start.isAfter(end)) return out;
  if (c.term == ContractTerm.daily) return <DateTime>[start];

  final step = _monthsPerCycle(c);
  var cursor = start;
  var guard = 0;
  while (!cursor.isAfter(end) && guard < 600) {
    out.add(cursor);
    cursor = _addMonths(cursor, step);
    guard++;
  }
  return out;
}

int _monthsPerCycle(Contract c) {
  switch (c.paymentCycle) {
    case PaymentCycle.monthly:
      return 1;
    case PaymentCycle.quarterly:
      return 3;
    case PaymentCycle.semiAnnual:
      return 6;
    case PaymentCycle.annual:
      final y = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
      return 12 * y;
  }
}

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final y = d.year + total ~/ 12;
  final m = total % 12 + 1;
  final maxDay = DateTime(y, m + 1, 0).day;
  final safeDay = d.day > maxDay ? maxDay : d.day;
  return DateTime(y, m, safeDay);
}



