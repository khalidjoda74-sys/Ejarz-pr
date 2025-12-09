class ReportsSummary {
  // overview
  final int propertiesCount;
  final int tenantsCount;
  final int contractsTotal;
  final int invoicesTotal;
  final int maintenanceTotal;

  // properties
  final int propertyUnitsOccupied;
  final int propertyUnitsVacant;

  // tenants
  final int tenantsBound;
  final int tenantsUnbound;

  // contracts
  final int activeContracts;
  final int nearExpiryContracts;
  final int endedContracts;

  // invoices split
  final int invoicesFromContracts;
  final int invoicesFromMaintenance;

  // maintenance split
  final int maintenanceNew;
  final int maintenanceInProgress;
  final int maintenanceDone;

  // finance
  final double financeRevenue;
  final double financeReceivables;
  final double financeExpenses;
  final double financeNet;

  ReportsSummary({
    required this.propertiesCount,
    required this.tenantsCount,
    required this.contractsTotal,
    required this.invoicesTotal,
    required this.maintenanceTotal,
    required this.propertyUnitsOccupied,
    required this.propertyUnitsVacant,
    required this.tenantsBound,
    required this.tenantsUnbound,
    required this.activeContracts,
    required this.nearExpiryContracts,
    required this.endedContracts,
    required this.invoicesFromContracts,
    required this.invoicesFromMaintenance,
    required this.maintenanceNew,
    required this.maintenanceInProgress,
    required this.maintenanceDone,
    required this.financeRevenue,
    required this.financeReceivables,
    required this.financeExpenses,
    required this.financeNet,
  });

  ReportsSummary copyWith({
    int? propertiesCount,
    int? tenantsCount,
    int? contractsTotal,
    int? invoicesTotal,
    int? maintenanceTotal,
    int? propertyUnitsOccupied,
    int? propertyUnitsVacant,
    int? tenantsBound,
    int? tenantsUnbound,
    int? activeContracts,
    int? nearExpiryContracts,
    int? endedContracts,
    int? invoicesFromContracts,
    int? invoicesFromMaintenance,
    int? maintenanceNew,
    int? maintenanceInProgress,
    int? maintenanceDone,
    double? financeRevenue,
    double? financeReceivables,
    double? financeExpenses,
    double? financeNet,
  }) {
    return ReportsSummary(
      propertiesCount: propertiesCount ?? this.propertiesCount,
      tenantsCount: tenantsCount ?? this.tenantsCount,
      contractsTotal: contractsTotal ?? this.contractsTotal,
      invoicesTotal: invoicesTotal ?? this.invoicesTotal,
      maintenanceTotal: maintenanceTotal ?? this.maintenanceTotal,
      propertyUnitsOccupied: propertyUnitsOccupied ?? this.propertyUnitsOccupied,
      propertyUnitsVacant: propertyUnitsVacant ?? this.propertyUnitsVacant,
      tenantsBound: tenantsBound ?? this.tenantsBound,
      tenantsUnbound: tenantsUnbound ?? this.tenantsUnbound,
      activeContracts: activeContracts ?? this.activeContracts,
      nearExpiryContracts: nearExpiryContracts ?? this.nearExpiryContracts,
      endedContracts: endedContracts ?? this.endedContracts,
      invoicesFromContracts: invoicesFromContracts ?? this.invoicesFromContracts,
      invoicesFromMaintenance: invoicesFromMaintenance ?? this.invoicesFromMaintenance,
      maintenanceNew: maintenanceNew ?? this.maintenanceNew,
      maintenanceInProgress: maintenanceInProgress ?? this.maintenanceInProgress,
      maintenanceDone: maintenanceDone ?? this.maintenanceDone,
      financeRevenue: financeRevenue ?? this.financeRevenue,
      financeReceivables: financeReceivables ?? this.financeReceivables,
      financeExpenses: financeExpenses ?? this.financeExpenses,
      financeNet: financeNet ?? this.financeNet,
    );
  }

  static ReportsSummary empty() => ReportsSummary(
    propertiesCount: 0,
    tenantsCount: 0,
    contractsTotal: 0,
    invoicesTotal: 0,
    maintenanceTotal: 0,
    propertyUnitsOccupied: 0,
    propertyUnitsVacant: 0,
    tenantsBound: 0,
    tenantsUnbound: 0,
    activeContracts: 0,
    nearExpiryContracts: 0,
    endedContracts: 0,
    invoicesFromContracts: 0,
    invoicesFromMaintenance: 0,
    maintenanceNew: 0,
    maintenanceInProgress: 0,
    maintenanceDone: 0,
    financeRevenue: 0,
    financeReceivables: 0,
    financeExpenses: 0,
    financeNet: 0,
  );
}
