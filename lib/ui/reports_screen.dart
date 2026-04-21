import 'package:darvoo/utils/ksa_time.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/constants/boxes.dart';
import '../data/services/comprehensive_reports_service.dart';
import '../data/services/hive_service.dart';
import '../data/services/pdf_export_service.dart';
import '../data/services/user_scope.dart';
import '../models/tenant.dart';
import '../models/property.dart';
import '../widgets/custom_confirm_dialog.dart';
import '../widgets/darvoo_app_bar.dart';
import 'contracts_screen.dart'
    show Contract, ContractTerm, ContractsScreen, ContractQuickFilter;
import 'maintenance_screen.dart'
    show MaintenancePriority, MaintenanceRequest, MaintenanceStatus;
import 'home_screen.dart';
import 'invoices_screen.dart' show Invoice, InvoiceDetailsScreen;
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/collapsible_filter_handle.dart';
import 'widgets/entity_audit_info_button.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  ComprehensiveReportFilters _filters = const ComprehensiveReportFilters();
  CommissionRule _globalCommissionRule = CommissionRule.zero;

  ComprehensiveReportSnapshot? _snapshot;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  Listenable? _mergedListenable;
  Timer? _refreshDebounce;
  bool _pauseReactiveRefresh = false;
  final ScrollController _flowScrollController = ScrollController();
  bool _flowAutoScrollStoppedByUser = false;
  bool _flowAutoScrollRunning = false;
  bool _flowForward = true;
  final Set<String> _hiddenOwnerLedgerEntryIds = <String>{};
  _ContractPeriodFilter _contractsPeriodFilter = _ContractPeriodFilter.all;
  _ServicePriorityFilter _servicesPriorityFilter = _ServicePriorityFilter.all;
  PropertyType? _propertiesTypeFilter;
  String? _propertiesSelectedPropertyId;
  String? _contractsSelectedPropertyId;
  String? _servicesSelectedPropertyId;
  String? _vouchersSelectedPropertyId;
  String? _ownersSelectedPropertyId;
  _VoucherStatusFilter _voucherStatusFilter = _VoucherStatusFilter.posted;
  _VoucherDirectionFilter _voucherDirectionFilter =
      _VoucherDirectionFilter.all;
  _VoucherOperationFilter _voucherOperationFilter =
      _VoucherOperationFilter.all;
  _ClientTenantSubTypeFilter _clientsTenantSubTypeFilter =
      _ClientTenantSubTypeFilter.all;
  bool _topFiltersCollapsed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > .5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _mergedListenable?.removeListener(_onDataChanged);
    _flowScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await HiveService.ensureReportsBoxesOpen();
      await ComprehensiveReportsService.ensureFinanceBoxesOpen();
      _mergedListenable = Listenable.merge(<Listenable>[
        HiveService.mergedReportsListenable(),
        ComprehensiveReportsService.financeListenable(),
      ]);
      _mergedListenable?.addListener(_onDataChanged);
      await _loadGlobalCommissionRule();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _setStateSafely(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onDataChanged() {
    if (_pauseReactiveRefresh) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      _refresh();
    });
  }

  Future<T> _runWithReactiveRefreshPaused<T>(Future<T> Function() action) async {
    final previous = _pauseReactiveRefresh;
    _pauseReactiveRefresh = true;
    _refreshDebounce?.cancel();
    try {
      return await action();
    } finally {
      _pauseReactiveRefresh = previous;
    }
  }

  void _holdReactiveRefresh() {
    _pauseReactiveRefresh = true;
    _refreshDebounce?.cancel();
  }

  void _runAfterBuildComplete(VoidCallback action) {
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        action();
      });
      return;
    }
    action();
  }

  void _setStateSafely(VoidCallback fn) {
    if (!mounted) return;
    _runAfterBuildComplete(() {
      if (!mounted) return;
      setState(fn);
    });
  }

  void _scheduleRefreshAfterDialogAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _pauseReactiveRefresh = false;
        return;
      }
      try {
        await _refresh();
      } finally {
        _pauseReactiveRefresh = false;
      }
    });
  }

  void _scheduleRefreshAfterOwnerAction() {
    _scheduleRefreshAfterDialogAction();
  }

  void _closeDialogSafely<T>(BuildContext dialogContext, [T? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !dialogContext.mounted) return;
      Navigator.of(dialogContext).pop(result);
    });
  }

  Future<void> _loadGlobalCommissionRule() async {
    _globalCommissionRule = await ComprehensiveReportsService.getCommissionRule(
      scope: CommissionScope.global,
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (mounted && _snapshot == null) {
      _setStateSafely(() {
        _loading = true;
      });
    }
    try {
      await _runWithReactiveRefreshPaused(
        () => ComprehensiveReportsService.syncOfficeCommissionVouchers(),
      );
      final data = await ComprehensiveReportsService.load(_filters);
      await _loadGlobalCommissionRule();
      if (!mounted) return;
      _setStateSafely(() {
        _snapshot = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _setStateSafely(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  void _stopFlowAutoScrollByUser() {
    if (_flowAutoScrollStoppedByUser) return;
    _flowAutoScrollStoppedByUser = true;
    if (_flowScrollController.hasClients) {
      final current = _flowScrollController.offset;
      try {
        _flowScrollController.jumpTo(current);
      } catch (_) {}
    }
  }

  void _scheduleFlowAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startFlowAutoScrollIfNeeded();
    });
  }

  Future<void> _startFlowAutoScrollIfNeeded() async {
    if (!mounted ||
        _flowAutoScrollStoppedByUser ||
        _flowAutoScrollRunning ||
        !_flowScrollController.hasClients) {
      return;
    }
    final maxExtent = _flowScrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;

    _flowAutoScrollRunning = true;
    try {
      while (mounted &&
          !_flowAutoScrollStoppedByUser &&
          _flowScrollController.hasClients) {
        final currentMax = _flowScrollController.position.maxScrollExtent;
        if (currentMax <= 0) break;

        final target = _flowForward ? currentMax : 0.0;
        final current = _flowScrollController.offset;
        final distance = (target - current).abs();

        if (distance < 1.5) {
          _flowForward = !_flowForward;
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        final msPerPx = _flowForward ? 22.0 : 16.0;
        final duration = Duration(
          milliseconds: (distance * msPerPx).clamp(1800.0, 12000.0).round(),
        );
        await _flowScrollController.animateTo(
          target,
          duration: duration,
          curve: Curves.easeInOut,
        );

        _flowForward = !_flowForward;
        await Future.delayed(const Duration(milliseconds: 260));
      }
    } catch (_) {
      // تجاهل إيقاف الحركة الناتج عن تفاعل المستخدم.
    } finally {
      _flowAutoScrollRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final topInset = kToolbarHeight + media.padding.top;
            final bottomInset = _bottomBarHeight + media.padding.bottom;
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
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          centerTitle: true,
          title: Text(
            'التقارير الشاملة',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Stack(
          children: [
            _gradientBg(),
            Positioned(
              top: -120,
              right: -80,
              child: _softCircle(220.r, const Color(0x33FFFFFF)),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _softCircle(260.r, const Color(0x22FFFFFF)),
            ),
            if (_loading && data == null)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white))
            else if (_error != null && data == null)
              Center(
                child: _darkCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white70),
                      SizedBox(height: 8.h),
                      Text(
                        'تعذر تحميل التقارير',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        _error!,
                        style: GoogleFonts.cairo(
                          color: Colors.white54,
                          fontSize: 11.sp,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (data != null)
              DefaultTabController(
                length: 8,
                child: Column(
                  children: [
                    _topFiltersBar(),
                    _flowIndicatorsBand(data),
                    _styledTabs(),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _dashboardTab(data),
                          _propertiesTab(data),
                          _clientsTab(data),
                          _contractsTab(data),
                          _servicesTab(data),
                          _vouchersTab(data),
                          _officeTab(data),
                          _ownersTab(data),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Widget _topFiltersBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 1,
              end: _topFiltersCollapsed ? 0 : 1,
            ),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            child: _darkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 6.h,
                    children: [
                      _quickChip('كل الفترة', () {
                        _applyPeriodFilters(from: null, to: null);
                      }, isSelected: _selectedPeriodChip() == _PeriodChip.all),
                      _quickChip(
                        'اليوم',
                        () => _applyQuickRange(_QuickRange.today),
                        isSelected: _selectedPeriodChip() == _PeriodChip.today,
                      ),
                      _quickChip(
                        'الأسبوع',
                        () => _applyQuickRange(_QuickRange.week),
                        isSelected: _selectedPeriodChip() == _PeriodChip.week,
                      ),
                      _quickChip(
                        'الشهر',
                        () => _applyQuickRange(_QuickRange.month),
                        isSelected: _selectedPeriodChip() == _PeriodChip.month,
                      ),
                      _quickChip(
                        'تحديد فترة',
                        _openGeneralFiltersSheet,
                        isSelected: _selectedPeriodChip() == _PeriodChip.custom,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    _filtersSummaryText(),
                    style: GoogleFonts.cairo(
                      color: Colors.white70,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            builder: (context, value, child) {
              return ClipRect(
                child: Align(
                  heightFactor: value,
                  child: Opacity(opacity: value, child: child),
                ),
              );
            },
          ),
          SizedBox(height: 1.h),
          Transform.translate(
            offset: Offset(0, -8.h),
            child: CollapsibleFilterHandle(
              collapsed: _topFiltersCollapsed,
              onTap: () {
                setState(() {
                  _topFiltersCollapsed = !_topFiltersCollapsed;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardTab(ComprehensiveReportSnapshot data) {
    return Builder(
      builder: (tabContext) {
        final clients = _loadClientsForReports();
        final tenantIndividualsCount = clients
            .where((t) => _normalizeDashboardClientType(t) == 'tenant')
            .length;
        final tenantCompaniesCount = clients
            .where((t) => _normalizeDashboardClientType(t) == 'company')
            .length;
        final providersCount = clients
            .where((t) => _normalizeDashboardClientType(t) == 'serviceProvider')
            .length;
        final clientsCount =
            tenantIndividualsCount + tenantCompaniesCount + providersCount;
        final maintenanceCount =
            data.services.where((e) => e.serviceType == 'maintenance').length;

        void openReportTab(int index) {
          DefaultTabController.of(tabContext).animateTo(index);
        }

        final items = <_DashboardCountItem>[
          _DashboardCountItem(
            title: 'العقارات',
            count: data.properties.length,
            icon: Icons.apartment_rounded,
            startColor: const Color(0xFF0D9488),
            endColor: const Color(0xFF0F766E),
            onTap: () => openReportTab(1),
          ),
          _DashboardCountItem(
            title: 'العملاء',
            count: clientsCount,
            icon: Icons.groups_rounded,
            startColor: const Color(0xFF0F766E),
            endColor: const Color(0xFF115E59),
            onTap: () => openReportTab(2),
          ),
          _DashboardCountItem(
            title: 'العقود',
            count: data.contracts.length,
            icon: Icons.description_rounded,
            startColor: const Color(0xFF7C3AED),
            endColor: const Color(0xFF5B21B6),
            onTap: () => openReportTab(3),
          ),
          _DashboardCountItem(
            title: 'الخدمات',
            count: maintenanceCount,
            icon: Icons.build_circle_rounded,
            startColor: const Color(0xFFF97316),
            endColor: const Color(0xFFEA580C),
            onTap: () => openReportTab(4),
          ),
          _DashboardCountItem(
            title: 'السندات',
            count: data.vouchers.length,
            icon: Icons.receipt_long_rounded,
            startColor: const Color(0xFF16A34A),
            endColor: const Color(0xFF15803D),
            onTap: () => openReportTab(5),
          ),
          _DashboardCountItem(
            title: 'المكتب',
            count: 1,
            icon: Icons.business_center_rounded,
            startColor: const Color(0xFF7C2D12),
            endColor: const Color(0xFF9A3412),
            onTap: () => openReportTab(7),
          ),
        ];
        return _tabScroll(
          child: _dashboardCountsGrid(items),
        );
      },
    );
  }

  Widget _clientsTab(ComprehensiveReportSnapshot _) {
    final allClients = _loadClientsForReports();
    final archivedClients = _loadClientsForReports(includeArchived: true)
        .where((tenant) => tenant.isArchived)
        .toList(growable: false);
    final tenantIndividuals = allClients
        .where((t) => _normalizeDashboardClientType(t) == 'tenant')
        .toList(growable: false);
    final tenantCompanies = allClients
        .where((t) => _normalizeDashboardClientType(t) == 'company')
        .toList(growable: false);
    final serviceProviders = allClients
        .where((t) => _normalizeDashboardClientType(t) == 'serviceProvider')
        .toList(growable: false);
    final filteredTenants = _filterClientsForReports(allClients);
    final todayKsa = KsaTime.dateOnly(KsaTime.now());

    final linkedTenantsCount = filteredTenants
        .where((t) => t.activeContractsCount > 0)
        .length;
    final unlinkedTenantsCount = filteredTenants
        .where((t) => t.activeContractsCount == 0)
        .length;
    final expiredIdsCount = filteredTenants.where((t) {
      return _normalizeDashboardClientType(t) == 'tenant' &&
          t.idExpiry != null &&
          KsaTime.dateOnly(t.idExpiry!).isBefore(todayKsa);
    }).length;

    final items = <_DashboardCountItem>[
      _DashboardCountItem(
        title: 'إجمالي العملاء',
        count: allClients.length,
        icon: Icons.groups_rounded,
        startColor: const Color(0xFF0D9488),
        endColor: const Color(0xFF0F766E),
        onTap: () => _openClientsScreen(),
      ),
      _DashboardCountItem(
        title: 'مستأجرون أفراد',
        count: tenantIndividuals.length,
        icon: Icons.person_rounded,
        startColor: const Color(0xFF0F766E),
        endColor: const Color(0xFF115E59),
        onTap: () => _openClientsScreen(clientType: 'tenant'),
      ),
      _DashboardCountItem(
        title: 'مستأجرون شركات',
        count: tenantCompanies.length,
        icon: Icons.apartment_rounded,
        startColor: const Color(0xFFB45309),
        endColor: const Color(0xFF92400E),
        onTap: () => _openClientsScreen(clientType: 'company'),
      ),
      _DashboardCountItem(
        title: 'مقدمو خدمات',
        count: serviceProviders.length,
        icon: Icons.handyman_rounded,
        startColor: const Color(0xFF9A3412),
        endColor: const Color(0xFF7C2D12),
        onTap: () => _openClientsScreen(clientType: 'serviceProvider'),
      ),
      _DashboardCountItem(
        title: 'المؤرشفون',
        count: archivedClients.length,
        icon: Icons.archive_rounded,
        startColor: const Color(0xFF475569),
        endColor: const Color(0xFF334155),
        onTap: () => _openClientsScreen(archiveState: 'archived'),
      ),
    ];

    void openTenantsIndicator({
      String? linkedState,
      String? idExpiryState,
    }) {
      String tenantSubType = 'all';
      switch (_clientsTenantSubTypeFilter) {
        case _ClientTenantSubTypeFilter.individuals:
          tenantSubType = 'individuals';
          break;
        case _ClientTenantSubTypeFilter.companies:
          tenantSubType = 'companies';
          break;
        case _ClientTenantSubTypeFilter.all:
          tenantSubType = idExpiryState == null ? 'all' : 'individuals';
          break;
      }
      _openClientsScreen(
        tenantType: 'tenants',
        tenantSubType: tenantSubType,
        linkedState: linkedState,
        idExpiryState: idExpiryState,
      );
    }

    String indicatorsTitle;
    final indicatorItems = <_ClientReportIndicatorItem>[];
    switch (_clientsTenantSubTypeFilter) {
      case _ClientTenantSubTypeFilter.individuals:
        indicatorsTitle = 'مؤشرات المستأجرين (أفراد)';
        indicatorItems.addAll([
          _ClientReportIndicatorItem(
            title: 'مرتبطين بعقد',
            value: '$linkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'linked'),
          ),
          _ClientReportIndicatorItem(
            title: 'غير مرتبطين بعقد',
            value: '$unlinkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'unlinked'),
          ),
          _ClientReportIndicatorItem(
            title: 'هويات منتهية للأفراد',
            value: '$expiredIdsCount',
            onTap: () => openTenantsIndicator(idExpiryState: 'expired'),
          ),
        ]);
        break;
      case _ClientTenantSubTypeFilter.companies:
        indicatorsTitle = 'مؤشرات المستأجرين (شركات)';
        indicatorItems.addAll([
          _ClientReportIndicatorItem(
            title: 'مرتبطين بعقد',
            value: '$linkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'linked'),
          ),
          _ClientReportIndicatorItem(
            title: 'غير مرتبطين بعقد',
            value: '$unlinkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'unlinked'),
          ),
        ]);
        break;
      case _ClientTenantSubTypeFilter.all:
        indicatorsTitle = 'مؤشرات كل المستأجرين';
        indicatorItems.addAll([
          _ClientReportIndicatorItem(
            title: 'مرتبطين بعقد',
            value: '$linkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'linked'),
          ),
          _ClientReportIndicatorItem(
            title: 'غير مرتبطين بعقد',
            value: '$unlinkedTenantsCount',
            onTap: () => openTenantsIndicator(linkedState: 'unlinked'),
          ),
          _ClientReportIndicatorItem(
            title: 'هويات منتهية للأفراد',
            value: '$expiredIdsCount',
            onTap: () => openTenantsIndicator(idExpiryState: 'expired'),
          ),
        ]);
        break;
    }

    return _tabScroll(
      child: Column(
        children: [
          _darkCard(
            child: Row(
              children: [
                Text(
                  'نوع المستأجر',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 220.w),
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_ClientTenantSubTypeFilter>(
                          value: _clientsTenantSubTypeFilter,
                          dropdownColor: const Color(0xFF0B1220),
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                          ),
                          isExpanded: true,
                          iconEnabledColor: Colors.white70,
                          items: const [
                            DropdownMenuItem(
                              value: _ClientTenantSubTypeFilter.all,
                              child: Text('الكل'),
                            ),
                            DropdownMenuItem(
                              value: _ClientTenantSubTypeFilter.individuals,
                              child: Text('مستأجرون أفراد'),
                            ),
                            DropdownMenuItem(
                              value: _ClientTenantSubTypeFilter.companies,
                              child: Text('مستأجرون شركات'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _clientsTenantSubTypeFilter = value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _dashboardCountsGrid(items),
          SizedBox(height: 18.h),
          _darkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(indicatorsTitle),
                SizedBox(height: 8.h),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < indicatorItems.length; i++) ...[
                        if (i > 0) SizedBox(width: 8.w),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: indicatorItems[i].onTap,
                            child: _miniKpi(
                              indicatorItems[i].title,
                              indicatorItems[i].value,
                              titleHeight: 30.h,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _propertiesTab(ComprehensiveReportSnapshot data) {
    final allRows = data.properties
        .where((item) =>
            _propertiesTypeFilter == null || item.type == _propertiesTypeFilter)
        .toList(growable: false);
    final allProperties = _loadPropertiesForReports()
        .where((property) =>
            _propertiesTypeFilter == null || property.type == _propertiesTypeFilter)
        .toList(growable: false);
    final archivedProperties = _loadPropertiesForReports(includeArchived: true)
        .where((property) =>
            property.isArchived &&
            (_propertiesTypeFilter == null ||
                property.type == _propertiesTypeFilter))
        .toList(growable: false);
    final propertyOptions = _buildPropertySelectionOptions(allProperties);
    final rawSelectedPropertyId = (_propertiesSelectedPropertyId ?? '').trim();
    final hasSelectedOption = rawSelectedPropertyId.isNotEmpty &&
        propertyOptions.any((item) => item.propertyId == rawSelectedPropertyId);
    final selectedPropertyId = hasSelectedOption ? rawSelectedPropertyId : '';
    final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
      allProperties,
      selectedPropertyId,
    );
    final selectedRows = selectedPropertyScopeIds.isEmpty
        ? allRows
        : allRows
            .where(
              (item) => _matchesPropertySelectionScope(
                item.propertyId,
                selectedPropertyScopeIds,
              ),
            )
            .toList(growable: false);

    final totalCount = allRows.length;
    final availableCount = allRows.where((p) => !p.isOccupied).length;
    final occupiedCount = allRows.where((p) => p.isOccupied).length;
    final selectedPropertyLabel = hasSelectedOption
        ? propertyOptions
            .firstWhere((item) => item.propertyId == rawSelectedPropertyId)
            .label
        : 'الكل';
    final selectedPropertyName = hasSelectedOption
        ? allProperties
            .firstWhere((property) => property.id == rawSelectedPropertyId)
            .name
        : 'الكل';

    Future<void> pickProperty() async {
      final result = await _showPropertySelectionSheet(
        allProperties,
        selectedPropertyId: rawSelectedPropertyId,
      );
      if (result == null || !mounted) return;
      setState(() {
        _propertiesSelectedPropertyId = result.propertyId;
      });
    }

    void navigateToProperties({
      PropertyType? type,
      AvailabilityFilter? availability,
      bool showArchived = false,
    }) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PropertiesScreen(
            initialType: type,
            initialAvailability: availability,
            initialShowArchived: showArchived,
          ),
        ),
      );
    }

    final kpiItems = [
      _DashboardCountItem(
        title: 'إجمالي العقارات',
        count: totalCount,
        icon: Icons.business_rounded,
        startColor: const Color(0xFF22D3EE),
        endColor: const Color(0xFF0D9488),
        onTap: () => navigateToProperties(type: _propertiesTypeFilter),
      ),
      _DashboardCountItem(
        title: 'المتاحة فقط',
        count: availableCount,
        icon: Icons.vpn_key_rounded,
        startColor: const Color(0xFF10B981),
        endColor: const Color(0xFF059669),
        onTap: () => navigateToProperties(
          type: _propertiesTypeFilter,
          availability: AvailabilityFilter.availableOnly,
        ),
      ),
      _DashboardCountItem(
        title: 'المشغولة فقط',
        count: occupiedCount,
        icon: Icons.people_alt_rounded,
        startColor: const Color(0xFFF59E0B),
        endColor: const Color(0xFFD97706),
        onTap: () => navigateToProperties(
          type: _propertiesTypeFilter,
          availability: AvailabilityFilter.occupiedOnly,
        ),
      ),
      _DashboardCountItem(
        title: 'المؤرشفون',
        count: archivedProperties.length,
        icon: Icons.archive_rounded,
        startColor: const Color(0xFF475569),
        endColor: const Color(0xFF334155),
        onTap: () => navigateToProperties(
          type: _propertiesTypeFilter,
          showArchived: true,
        ),
      ),
    ];

    final bool isAllPropertiesSelected = selectedPropertyId.isEmpty;
    final String summaryTitle;
    final double summaryRevenues;
    final double summaryExpenses;
    final double summaryNet;

    if (selectedRows.isEmpty) {
      summaryTitle = isAllPropertiesSelected ? 'كل العقارات' : 'العقار المحدد';
      summaryRevenues = 0;
      summaryExpenses = 0;
      summaryNet = 0;
    } else {
      summaryTitle = isAllPropertiesSelected
          ? 'كل العقارات'
          : selectedPropertyName;
      summaryRevenues =
          selectedRows.fold<double>(0, (sum, item) => sum + item.revenues);
      summaryExpenses =
          selectedRows.fold<double>(0, (sum, item) => sum + item.expenses);
      summaryNet = selectedRows.fold<double>(0, (sum, item) => sum + item.net);
    }

    return _tabScroll(
      child: Column(
        children: [
          _darkCard(
            child: Row(
              children: [
                Text(
                  'نوع العقار',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 220.w),
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<PropertyType?>(
                          value: _propertiesTypeFilter,
                          dropdownColor: const Color(0xFF0B1220),
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                          ),
                          isExpanded: true,
                          iconEnabledColor: Colors.white70,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('الكل'),
                            ),
                            ...PropertyType.values.map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _propertiesTypeFilter = value;
                            _propertiesSelectedPropertyId = null;
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _dashboardCountsGrid(kpiItems),
          SizedBox(height: 12.h),
          _darkCard(
            child: Row(
              children: [
                Text(
                  'اختيار عقار',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: pickProperty,
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 220.w),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedPropertyLabel,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          if (selectedRows.isEmpty)
            _emptyCard(
              isAllPropertiesSelected
                  ? 'لا توجد بيانات تقارير للعقارات حالياً'
                  : 'لا توجد بيانات تقارير للعقار المحدد',
            )
          else ...[
            SizedBox(height: 24.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Row(
                children: [
                  Container(
                    width: 4.w,
                    height: 18.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'التقارير المالية للعقارات',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _darkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summaryTitle,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Column(
                    children: [
                      _reportValueRowItem(
                        'الإيرادات',
                        _money(summaryRevenues),
                        const Color(0xFF22D3EE),
                        Icons.trending_up_rounded,
                      ),
                      _dividerItem(),
                      _reportValueRowItem(
                        'المصروفات',
                        _money(summaryExpenses),
                        const Color(0xFFEF4444),
                        Icons.receipt_long_rounded,
                      ),
                      _dividerItem(),
                      _reportValueRowItem(
                        'صافي العقار',
                        _money(summaryNet),
                        const Color(0xFF10B981),
                        Icons.account_balance_wallet_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contractsTab(ComprehensiveReportSnapshot data) {
    final contracts = _loadContractsForReports();
    final byId = <String, Contract>{for (final c in contracts) c.id: c};
    final allProperties = _loadPropertiesForReports();
    final propertyOptions = _buildPropertySelectionOptions(allProperties);
    final rawSelectedPropertyId = (_contractsSelectedPropertyId ?? '').trim();
    final hasSelectedProperty = rawSelectedPropertyId.isNotEmpty &&
        propertyOptions.any((item) => item.propertyId == rawSelectedPropertyId);
    final selectedPropertyId = hasSelectedProperty ? rawSelectedPropertyId : '';
    final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
      allProperties,
      selectedPropertyId,
    );
    final selectedPropertyLabel = hasSelectedProperty
        ? propertyOptions
            .firstWhere((item) => item.propertyId == rawSelectedPropertyId)
            .label
        : 'الكل';
    final selectedPropertyName = hasSelectedProperty
        ? allProperties
            .firstWhere((property) => property.id == rawSelectedPropertyId)
            .name
        : '';
    final filtered = data.contracts.where((item) {
      if (!_matchesPropertySelectionScope(
        item.propertyId,
        selectedPropertyScopeIds,
      )) {
        return false;
      }
      if (_contractsPeriodFilter == _ContractPeriodFilter.all) return true;
      final c = byId[item.contractId];
      if (c == null) return false;
      return _matchesContractPeriodFilter(c, _contractsPeriodFilter);
    }).toList(growable: false);

    final activeCount = filtered.where((e) => e.status == 'نشط').length;
    final inactiveCount = filtered.where((e) => e.status == 'غير نشط').length;
    final nearContractCount = filtered.where((e) {
      final c = byId[e.contractId];
      return c != null && _isContractNearEnd(c) && e.status == 'نشط';
    }).length;
    final endingTodayCount = filtered.where((e) {
      final c = byId[e.contractId];
      return c != null && _contractEndsToday(c);
    }).length;
    final endedCount = filtered.where((e) {
      final c = byId[e.contractId];
      return c != null && _contractHasEnded(c);
    }).length;
    final cancelledCount = filtered.where((e) {
      final c = byId[e.contractId];
      return c != null && c.isTerminated;
    }).length;
    final nearPaymentsCount = filtered.where((e) {
      final next = e.nextDueDate;
      if (next == null) return false;
      return e.upcomingInstallments > 0 && !_isToday(next);
    }).length;
    final dueTodayCount = filtered.where((e) {
      final next = e.nextDueDate;
      if (next == null) return false;
      return e.upcomingInstallments > 0 && _isToday(next);
    }).length;
    final overdueCount =
        filtered.where((e) => e.overdueInstallments > 0).length;
    final totalContractsCount = filtered.length;

    // --- حساب المبالغ الإجمالية (جديد) ---
    double totalActiveContractsSum = 0; // إجمالي مبالغ العقود السارية
    double totalPaidSum = 0;
    double totalNearDueSum = 0;
    double totalDueTodaySum = 0;
    double totalOverdueSum = 0;

    for (final e in filtered) {
      if (e.status == 'نشط') {
        totalActiveContractsSum += e.totalAmount;
      }
      totalPaidSum += e.paidAmount;
      totalOverdueSum += e.overdueAmount;

      // حساب المبالغ التي قاربت والمستحقة اليوم يدويًا بناءً على حالة العقد في التقرير
      final next = e.nextDueDate;
      if (next != null && e.upcomingInstallments > 0) {
        // إذا كان الاستحقاق اليوم
        if (_isToday(next)) {
          totalDueTodaySum += (e.totalAmount - e.paidAmount) / (e.upcomingInstallments + e.overdueInstallments); 
          // ملاحظة: هذا تقدير تقريبي للمبلغ المستحق بناءً على عدد الأقساط المتبقية
        } else {
          // قارب
          totalNearDueSum += (e.totalAmount - e.paidAmount) / (e.upcomingInstallments + e.overdueInstallments);
        }
      }
    }

    void navigateToContracts(ContractQuickFilter? filter) {
      DateTimeRange? range;
      if (_filters.from != null && _filters.to != null) {
        range = DateTimeRange(start: _filters.from!, end: _filters.to!);
      }
      final args = <String, dynamic>{};
      if (selectedPropertyId.isNotEmpty) {
        args['filterPreviousPropertyId'] = selectedPropertyId;
        args['filterPreviousPropertyName'] = selectedPropertyName;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContractsScreen(
            initialFilter: filter,
            initialDateRange: range,
          ),
          settings: RouteSettings(arguments: args.isEmpty ? null : args),
        ),
      );
    }

    Future<void> pickProperty() async {
      final result = await _showPropertySelectionSheet(
        allProperties,
        selectedPropertyId: rawSelectedPropertyId,
      );
      if (result == null || !mounted) return;
      setState(() {
        _contractsSelectedPropertyId = result.propertyId;
      });
    }

    final items = <_DashboardCountItem>[
      _DashboardCountItem(
        title: 'إجمالي العقود',
        count: totalContractsCount,
        icon: Icons.description_rounded,
        startColor: const Color(0xFF0D9488),
        endColor: const Color(0xFF0F766E),
        onTap: () => navigateToContracts(null),
      ),
      _DashboardCountItem(
        title: 'عقود نشطة',
        count: activeCount,
        icon: Icons.verified_rounded,
        startColor: const Color(0xFF16A34A),
        endColor: const Color(0xFF15803D),
        onTap: () => navigateToContracts(ContractQuickFilter.active),
      ),
      _DashboardCountItem(
        title: 'عقود غير نشطة',
        count: inactiveCount,
        icon: Icons.pause_circle_rounded,
        startColor: const Color(0xFF475569),
        endColor: const Color(0xFF334155),
        onTap: () => navigateToContracts(ContractQuickFilter.inactive),
      ),
      _DashboardCountItem(
        title: 'عقود قاربت',
        count: nearContractCount,
        icon: Icons.hourglass_top_rounded,
        startColor: const Color(0xFFD97706),
        endColor: const Color(0xFFB45309),
        onTap: () => navigateToContracts(ContractQuickFilter.nearContract),
      ),
      _DashboardCountItem(
        title: 'عقود تنتهي اليوم',
        count: endingTodayCount,
        icon: Icons.today_rounded,
        startColor: const Color(0xFF0F766E),
        endColor: const Color(0xFF115E59),
        onTap: () => navigateToContracts(ContractQuickFilter.endsToday),
      ),
      _DashboardCountItem(
        title: 'عقود منتهية',
        count: endedCount,
        icon: Icons.event_busy_rounded,
        startColor: const Color(0xFFB91C1C),
        endColor: const Color(0xFF991B1B),
        onTap: () => navigateToContracts(ContractQuickFilter.ended),
      ),
      _DashboardCountItem(
        title: 'عقود ملغية',
        count: cancelledCount,
        icon: Icons.cancel_rounded,
        startColor: const Color(0xFF7F1D1D),
        endColor: const Color(0xFF5F1414),
        onTap: () => navigateToContracts(ContractQuickFilter.canceled),
      ),
      _DashboardCountItem(
        title: 'دفعات قاربت',
        count: nearPaymentsCount,
        icon: Icons.schedule_rounded,
        startColor: const Color(0xFF0284C7),
        endColor: const Color(0xFF0369A1),
        onTap: () => navigateToContracts(ContractQuickFilter.nearExpiry),
      ),
      _DashboardCountItem(
        title: 'دفعات مستحقة',
        count: dueTodayCount,
        icon: Icons.event_available_rounded,
        startColor: const Color(0xFF7C3AED),
        endColor: const Color(0xFF6D28D9),
        onTap: () => navigateToContracts(ContractQuickFilter.due),
      ),
      _DashboardCountItem(
        title: 'دفعات متأخرة',
        count: overdueCount,
        icon: Icons.warning_amber_rounded,
        startColor: const Color(0xFFEA580C),
        endColor: const Color(0xFFC2410C),
        onTap: () => navigateToContracts(ContractQuickFilter.expired),
      ),
    ];

    return _tabScroll(
      child: Column(
        children: [
          _darkCard(
            child: Row(
              children: [
                Text(
                  'فترة العقد',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 220.w),
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_ContractPeriodFilter>(
                          value: _contractsPeriodFilter,
                          dropdownColor: const Color(0xFF0B1220),
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                          ),
                          isExpanded: true,
                          iconEnabledColor: Colors.white70,
                          items: _ContractPeriodFilter.values.map((period) {
                            return DropdownMenuItem<_ContractPeriodFilter>(
                              value: period,
                              child: Text(period.label),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _contractsPeriodFilter = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _darkCard(
            child: Row(
              children: [
                Text(
                  'اختيار عقار',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: pickProperty,
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 220.w),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedPropertyLabel,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _dashboardCountsGrid(items),
          if (filtered.isEmpty)
            _emptyCard('لا توجد عقود ضمن الفلاتر الحالية')
          else ...[
            // --- قسم تفاصيل مبالغ العقود (جديد) ---
            SizedBox(height: 24.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Row(
                children: [
                  Container(
                    width: 4.w,
                    height: 18.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 8.w),
                                  Text(
                                    'التقارير المالية للعقود',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                  
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _darkCard(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  _amountRowItem(
                    'إجمالي مبالغ العقود',
                    totalActiveContractsSum,
                    const Color(0xFF22D3EE),
                    Icons.account_balance_wallet_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الدفعات المدفوعة',
                    totalPaidSum,
                    const Color(0xFF10B981),
                    Icons.check_circle_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الدفعات التي قاربت',
                    totalNearDueSum,
                    const Color(0xFF0EA5E9),
                    Icons.schedule_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الدفعات المستحقة',
                    totalDueTodaySum,
                    const Color(0xFF8B5CF6),
                    Icons.event_available_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الدفعات المتأخرة',
                    totalOverdueSum,
                    const Color(0xFFEF4444),
                    Icons.error_outline_rounded,
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),
          ],
        ],
      ),
    );
  }

  Widget _dividerItem() => Container(
        margin: EdgeInsets.symmetric(vertical: 12.h),
        height: 1,
        color: Colors.white.withOpacity(0.05),
      );

  Widget _reportValueRowItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, color: color.withOpacity(0.8), size: 18.sp),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.cairo(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: GoogleFonts.cairo(
              color: color,
              fontSize: 14.sp,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _amountRowItem(String label, double value, Color color, IconData icon) {
    return _reportValueRowItem(
      label,
      _money(value),
      color,
      icon,
    );
  }

  Widget _servicesTab(ComprehensiveReportSnapshot data) {
    final allProperties = _loadPropertiesForReports();
    final propertyOptions = _buildPropertySelectionOptions(allProperties);
    final rawSelectedPropertyId = (_servicesSelectedPropertyId ?? '').trim();
    final hasSelectedProperty = rawSelectedPropertyId.isNotEmpty &&
        propertyOptions.any((item) => item.propertyId == rawSelectedPropertyId);
    final selectedPropertyId = hasSelectedProperty ? rawSelectedPropertyId : '';
    final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
      allProperties,
      selectedPropertyId,
    );
    final selectedPropertyLabel = hasSelectedProperty
        ? propertyOptions
            .firstWhere((item) => item.propertyId == rawSelectedPropertyId)
            .label
        : 'الكل';
    final selectedPropertyName = hasSelectedProperty
        ? allProperties
            .firstWhere((property) => property.id == rawSelectedPropertyId)
            .name
        : '';
    final maintenanceRows = _loadMaintenanceForReports();
    final statusByMaintenanceId = <String, MaintenanceStatus>{
      for (final m in maintenanceRows) m.id: m.status,
    };
    final statusByLinkedVoucherId = <String, MaintenanceStatus>{
      for (final m in maintenanceRows)
        if ((m.invoiceId ?? '').trim().isNotEmpty) (m.invoiceId ?? '').trim(): m.status,
    };
    final priorityByMaintenanceId = <String, MaintenancePriority>{
      for (final m in maintenanceRows) m.id: m.priority,
    };
    final priorityByLinkedVoucherId = <String, MaintenancePriority>{
      for (final m in maintenanceRows)
        if ((m.invoiceId ?? '').trim().isNotEmpty) (m.invoiceId ?? '').trim(): m.priority,
    };

    MaintenanceStatus? resolveStatus(ServiceReportItem item) {
      final direct = statusByMaintenanceId[item.id];
      if (direct != null) return direct;
      final linked = item.linkedVoucherId.trim();
      if (linked.isNotEmpty) {
        final byLinked = statusByLinkedVoucherId[linked];
        if (byLinked != null) return byLinked;
      }
      return statusByLinkedVoucherId[item.id];
    }

    MaintenancePriority? resolvePriority(ServiceReportItem item) {
      final direct = priorityByMaintenanceId[item.id];
      if (direct != null) return direct;
      final linked = item.linkedVoucherId.trim();
      if (linked.isNotEmpty) {
        final byLinked = priorityByLinkedVoucherId[linked];
        if (byLinked != null) return byLinked;
      }
      return priorityByLinkedVoucherId[item.id];
    }

    final filtered = data.services.where((item) {
      if (!_matchesPropertySelectionScope(
        item.propertyId,
        selectedPropertyScopeIds,
      )) {
        return false;
      }
      return _matchesServicePriorityFilter(
        item,
        resolvePriority(item),
      );
    }).toList(growable: false);

    final totalCount = filtered.length;
    final openCount = filtered.where((item) {
      final st = resolveStatus(item);
      if (st == null) return !item.isPaid;
      return st == MaintenanceStatus.open;
    }).length;
    final inProgressCount = filtered.where((item) {
      final st = resolveStatus(item);
      return st == MaintenanceStatus.inProgress;
    }).length;
    final completedCount = filtered.where((item) {
      final st = resolveStatus(item);
      if (st == null) return item.isPaid;
      return st == MaintenanceStatus.completed;
    }).length;
    final cancelledCount = filtered
        .where((item) => item.state == VoucherState.cancelled)
        .length;
    final financialRows = filtered
        .where((item) => item.state != VoucherState.cancelled)
        .toList(growable: false);
    final totalServicesAmount = financialRows.fold<double>(
      0,
      (sum, item) => sum + item.amount.abs(),
    );
    final paidServicesAmount = financialRows
        .where((item) => item.isPaid)
        .fold<double>(0, (sum, item) => sum + item.amount.abs());
    final unpaidServicesAmount = financialRows
        .where((item) => !item.isPaid)
        .fold<double>(0, (sum, item) => sum + item.amount.abs());

    void navigateToServices([MaintenanceStatus? status]) {
      final args = <String, dynamic>{};
      if (status != null) {
        args['filterStatus'] = status;
      }
      if (selectedPropertyId.isNotEmpty) {
        args['filterPropertyId'] = selectedPropertyId;
        args['filterPropertyName'] = selectedPropertyName;
      }
      final priority = _maintenancePriorityFromServicesFilter();
      if (priority != null) {
        args['filterPriority'] = priority;
      }
      Navigator.of(context).pushNamed(
        '/maintenance',
        arguments: args.isEmpty ? null : args,
      );
    }

    Future<void> pickProperty() async {
      final result = await _showPropertySelectionSheet(
        allProperties,
        selectedPropertyId: rawSelectedPropertyId,
      );
      if (result == null || !mounted) return;
      setState(() {
        _servicesSelectedPropertyId = result.propertyId;
      });
    }

    final items = <_DashboardCountItem>[
      _DashboardCountItem(
        title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062e\u062f\u0645\u0627\u062a',
        count: totalCount,
        icon: Icons.miscellaneous_services_rounded,
        startColor: const Color(0xFF0D9488),
        endColor: const Color(0xFF0F766E),
        onTap: () => navigateToServices(),
      ),
      _DashboardCountItem(
        title: '\u062e\u062f\u0645\u0627\u062a \u062c\u062f\u064a\u062f\u0629',
        count: openCount,
        icon: Icons.pending_actions_rounded,
        startColor: const Color(0xFFF97316),
        endColor: const Color(0xFFEA580C),
        onTap: () => navigateToServices(MaintenanceStatus.open),
      ),
      _DashboardCountItem(
        title: '\u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630',
        count: inProgressCount,
        icon: Icons.sync_rounded,
        startColor: const Color(0xFF0EA5E9),
        endColor: const Color(0xFF0284C7),
        onTap: () => navigateToServices(MaintenanceStatus.inProgress),
      ),
      _DashboardCountItem(
        title: '\u062e\u062f\u0645\u0627\u062a \u0645\u0643\u062a\u0645\u0644\u0629',
        count: completedCount,
        icon: Icons.task_alt_rounded,
        startColor: const Color(0xFF16A34A),
        endColor: const Color(0xFF15803D),
        onTap: () => navigateToServices(MaintenanceStatus.completed),
      ),
      _DashboardCountItem(
        title: 'خدمات ملغية',
        count: cancelledCount,
        icon: Icons.cancel_rounded,
        startColor: const Color(0xFF991B1B),
        endColor: const Color(0xFF7F1D1D),
        onTap: () => navigateToServices(MaintenanceStatus.canceled),
      ),
    ];

    return _tabScroll(
      child: Column(
        children: [
          _darkCard(
            child: Row(
              children: [
                Text(
                  '\u0627\u0644\u0623\u0648\u0644\u0648\u064a\u0629',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 220.w),
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_ServicePriorityFilter>(
                          value: _servicesPriorityFilter,
                          dropdownColor: const Color(0xFF0B1220),
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                          ),
                          isExpanded: true,
                          iconEnabledColor: Colors.white70,
                          items: _ServicePriorityFilter.values.map((priority) {
                            return DropdownMenuItem<_ServicePriorityFilter>(
                              value: priority,
                              child: Text(priority.label),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _servicesPriorityFilter = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _darkCard(
            child: Row(
              children: [
                Text(
                  'اختيار عقار',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: pickProperty,
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 220.w),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedPropertyLabel,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _dashboardCountsGrid(items),
          if (filtered.isEmpty)
            _emptyCard('\u0644\u0627 \u062a\u0648\u062c\u062f \u062e\u062f\u0645\u0627\u062a \u0636\u0645\u0646 \u0627\u0644\u0641\u0644\u0627\u062a\u0631 \u0627\u0644\u062d\u0627\u0644\u064a\u0629')
          else ...[
            SizedBox(height: 24.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Row(
                children: [
                  Container(
                    width: 4.w,
                    height: 18.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'التقارير المالية للخدمات',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _darkCard(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  _amountRowItem(
                    'إجمالي تكلفة الخدمات',
                    totalServicesAmount,
                    const Color(0xFF22D3EE),
                    Icons.receipt_long_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الخدمات المسددة',
                    paidServicesAmount,
                    const Color(0xFF16A34A),
                    Icons.check_circle_rounded,
                  ),
                  _dividerItem(),
                  _amountRowItem(
                    'الخدمات غير المسددة',
                    unpaidServicesAmount,
                    const Color(0xFFF97316),
                    Icons.pending_actions_rounded,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  Widget _ownersTab(ComprehensiveReportSnapshot data) {
    const showAllPropertiesTogetherValue = '__owners_show_all_properties__';
    final ownerPropertyIds = data.owners
        .expand((owner) => owner.propertyBreakdowns.map((item) => item.propertyId))
        .toSet();
    final allProperties = _loadPropertiesForReports()
        .where((property) => ownerPropertyIds.contains(property.id))
        .toList(growable: false);
    final propertyOptions = _buildPropertySelectionOptions(allProperties);
    final rawSelectedPropertyId = (_ownersSelectedPropertyId ?? '').trim();
    final isShowingAllPropertiesTogether =
        rawSelectedPropertyId == showAllPropertiesTogetherValue;
    final hasSelectedProperty =
        !isShowingAllPropertiesTogether &&
        rawSelectedPropertyId.isNotEmpty &&
        propertyOptions.any((item) => item.propertyId == rawSelectedPropertyId);
    final selectedPropertyId = hasSelectedProperty ? rawSelectedPropertyId : '';
    final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
      allProperties,
      selectedPropertyId,
    );
    final selectedPropertyLabel = isShowingAllPropertiesTogether
        ? 'إظهار جميع العقارات معًا'
        : hasSelectedProperty
            ? propertyOptions
                .firstWhere((item) => item.propertyId == rawSelectedPropertyId)
                .label
            : 'الكل';

    Future<void> pickProperty() async {
      final result = await _showPropertySelectionSheet(
        allProperties,
        allOptionLabel: 'الكل',
        selectedPropertyId: rawSelectedPropertyId,
        secondaryOptionLabel: 'إظهار جميع العقارات معًا',
        secondaryOptionValue: showAllPropertiesTogetherValue,
      );
      if (result == null || !mounted) return;
      setState(() {
        _ownersSelectedPropertyId = result.propertyId;
      });
    }

    final visibleOwners = selectedPropertyId.isEmpty
        ? data.owners
        : data.owners
            .where(
              (owner) => owner.propertyBreakdowns.any(
                (item) => _matchesPropertySelectionScope(
                  item.propertyId,
                  selectedPropertyScopeIds,
                ),
              ),
            )
            .toList(growable: false);

    return _tabScroll(
      child: Column(
        children: [
          if (data.owners.isEmpty)
            _emptyCard(
              'لا يوجد ملاك معروفون حالياً. قم بتعيين المالك من تقارير العقارات.',
            )
          else ...[
            if (propertyOptions.isNotEmpty) ...[
              _darkCard(
                child: Row(
                  children: [
                    Text(
                      'اختيار عقار',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.sp,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: pickProperty,
                          borderRadius: BorderRadius.circular(12.r),
                          child: Container(
                            constraints: BoxConstraints(maxWidth: 220.w),
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 10.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedPropertyLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.sp,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                const Icon(
                                  Icons.apartment_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
            ],
            if (visibleOwners.isEmpty)
              _emptyCard('لا توجد بيانات مالية لهذا العقار')
            else
              ...visibleOwners.map((owner) {
                final displayedProperties = isShowingAllPropertiesTogether
                    ? owner.propertyBreakdowns
                    : selectedPropertyId.isNotEmpty
                        ? owner.propertyBreakdowns
                            .where(
                              (item) => _matchesPropertySelectionScope(
                                item.propertyId,
                                selectedPropertyScopeIds,
                              ),
                            )
                            .toList(growable: false)
                        : const <OwnerPropertyReportItem>[];
                final isPropertyFiltered = selectedPropertyId.isNotEmpty;
                final summaryRent = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.rentCollected,
                      )
                    : owner.rentCollected;
                final summaryCommissions = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.officeCommissions,
                      )
                    : owner.officeCommissions;
                final summaryExpenses = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.ownerExpenses,
                      )
                    : owner.ownerExpenses;
                final summaryAdjustments = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.ownerAdjustments,
                      )
                    : owner.ownerAdjustments;
                final summaryTransfers = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.previousTransfers,
                      )
                    : owner.previousTransfers;
                final summaryBalance = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.currentBalance,
                      )
                    : owner.currentBalance;
                final summaryReady = isPropertyFiltered
                    ? displayedProperties.fold<double>(
                        0,
                        (sum, item) => sum + item.readyForPayout,
                      )
                    : owner.readyForPayout;
                final selectedPropertyName =
                    isPropertyFiltered && displayedProperties.isNotEmpty
                        ? displayedProperties.first.propertyName
                        : '';

                return _darkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'التقارير المالية للمالك',
                                  style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.sp,
                                  ),
                                ),
                                if (!isPropertyFiltered &&
                                    owner.linkedProperties > 0) ...[
                                  SizedBox(height: 4.h),
                                  Text(
                                    'العقارات: ${owner.linkedProperties}',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ],
                                if (selectedPropertyName.isNotEmpty) ...[
                                  SizedBox(height: 4.h),
                                  Text(
                                    'العقار: $selectedPropertyName',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _statusChip(
                            'جاهز للتحويل ${_money(summaryReady)}',
                            const Color(0xFF0E7490),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                        _miniKpiRows3([
                          _MiniKpiCellData(
                          title: 'إجمالي الإيجار المحصل',
                          value: _money(summaryRent),
                        ),
                        _MiniKpiCellData(
                          title: 'عمولة المكتب المخصومة',
                          value: _money(summaryCommissions),
                        ),
                        _MiniKpiCellData(
                          title: 'مصروفات الخدمات',
                          value: _money(summaryExpenses),
                        ),
                        _MiniKpiCellData(
                          title: 'خصومات',
                          value: _money(summaryAdjustments),
                        ),
                        _MiniKpiCellData(
                          title: 'تحويلات سابقة',
                          value: _money(summaryTransfers),
                        ),
                        _MiniKpiCellData(
                          title: 'الرصيد الصافي',
                          value: _money(summaryBalance),
                        ),
                      ], titleHeight: 32.h),
                      SizedBox(height: 8.h),
                      Text(
                        'إجمالي الإيجار المحصل - عمولة المكتب المخصومة - مصروفات الخدمات - خصومات - تحويلات سابقة = الرصيد الصافي',
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.sp,
                        ),
                      ),
                      if (isShowingAllPropertiesTogether &&
                          displayedProperties.isNotEmpty) ...[
                        SizedBox(height: 12.h),
                        _sectionTitle('تفصيل العقارات'),
                        SizedBox(height: 10.h),
                        ...displayedProperties.map((property) {
                          return Container(
                            margin: EdgeInsets.only(bottom: 10.h),
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        property.propertyName,
                                        style: GoogleFonts.cairo(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.sp,
                                        ),
                                      ),
                                    ),
                                    _statusChip(
                                      'جاهز للتحويل ${_money(property.readyForPayout)}',
                                      const Color(0xFF0E7490),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10.h),
                                _miniKpiRows3([
                                  _MiniKpiCellData(
                                    title: 'إجمالي الإيجار المحصل',
                                    value: _money(property.rentCollected),
                                  ),
                                  _MiniKpiCellData(
                                    title: 'عمولة المكتب المخصومة',
                                    value: _money(property.officeCommissions),
                                  ),
                                  _MiniKpiCellData(
                                    title: 'مصروفات الخدمات',
                                    value: _money(property.ownerExpenses),
                                  ),
                                  _MiniKpiCellData(
                                    title: 'خصومات',
                                    value: _money(property.ownerAdjustments),
                                  ),
                                  _MiniKpiCellData(
                                    title: 'تحويلات سابقة',
                                    value: _money(property.previousTransfers),
                                  ),
                                  _MiniKpiCellData(
                                    title: 'الرصيد الصافي',
                                    value: _money(property.currentBalance),
                                  ),
                                ], titleHeight: 32.h),
                              ],
                            ),
                          );
                        }),
                      ],
                      SizedBox(height: 10.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: [
                          SizedBox(
                            width: 140.w,
                            child: ElevatedButton(
                              onPressed: () => _showOwnerPayoutDialog(
                                owner,
                                propertyId:
                                    isPropertyFiltered ? selectedPropertyId : null,
                                propertyName: selectedPropertyName.isNotEmpty
                                    ? selectedPropertyName
                                    : '',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDCFCE7),
                                foregroundColor: Colors.black87,
                              ),
                              child: Text(
                                'تحويل الآن',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 140.w,
                            child: ElevatedButton(
                              onPressed: () => _showOwnerAdjustmentDialog(
                                owner,
                                propertyId:
                                    isPropertyFiltered ? selectedPropertyId : null,
                                propertyName: selectedPropertyName.isNotEmpty
                                    ? selectedPropertyName
                                    : '',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFEDD5),
                                foregroundColor: Colors.black87,
                              ),
                              child: Text(
                                'تسجيل خصم',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 140.w,
                            child: ElevatedButton(
                              onPressed: () => _showOwnerBankAccountsDialog(owner),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE0E7FF),
                                foregroundColor: Colors.black87,
                              ),
                              child: Text(
                                'الحسابات البنكية',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isPropertyFiltered &&
                          _visibleOwnerLedgerEntries(owner.ledger).isNotEmpty) ...[
                        SizedBox(height: 10.h),
                        Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            iconColor: Colors.white70,
                            collapsedIconColor: Colors.white70,
                            title: Text(
                              'كشف الحركات (${_visibleOwnerLedgerEntries(owner.ledger).length})',
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            children: _visibleOwnerLedgerEntries(owner.ledger)
                                .map(_ownerLedgerTile)
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );

    return _tabScroll(
      child: Column(
        children: [
          if (data.owners.isEmpty)
            _emptyCard(
              'لا يوجد ملاك معرفون حالياً. قم بتعيين المالك من تقارير العقارات.',
            )
          else
            ...data.owners.map((owner) {
              return _darkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            owner.ownerName,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.sp,
                            ),
                          ),
                        ),
                        _statusChip(
                          'جاهز للتحويل ${_money(owner.readyForPayout)}',
                          const Color(0xFF0E7490),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        _miniKpi(
                          'إجمالي الإيجار المحصل',
                          _money(owner.rentCollected),
                        ),
                        _miniKpi(
                          'عمولة المكتب المخصومة',
                          _money(owner.officeCommissions),
                        ),
                        _miniKpi(
                          'مصروفات الخدمات',
                          _money(owner.ownerExpenses),
                        ),
                        _miniKpi('خصومات', _money(owner.ownerAdjustments)),
                        _miniKpi(
                            'تحويلات سابقة', _money(owner.previousTransfers)),
                        _miniKpi('الرصيد الصافي', _money(owner.currentBalance)),
                        _miniKpi('العقارات', '${owner.linkedProperties}'),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        SizedBox(
                          width: 140.w,
                          child: ElevatedButton(
                            onPressed: () => _showOwnerPayoutDialog(
                              owner,
                              propertyName: '',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDCFCE7),
                              foregroundColor: Colors.black87,
                            ),
                            child: Text(
                              'تحويل الآن',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140.w,
                          child: ElevatedButton(
                            onPressed: () => _showOwnerAdjustmentDialog(
                              owner,
                              propertyName: '',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFEDD5),
                              foregroundColor: Colors.black87,
                            ),
                            child: Text(
                              'تسجيل خصم',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140.w,
                          child: ElevatedButton(
                            onPressed: () => _showOwnerBankAccountsDialog(owner),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE0E7FF),
                              foregroundColor: Colors.black87,
                            ),
                            child: Text(
                              'الحسابات البنكية',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_visibleOwnerLedgerEntries(owner.ledger).isNotEmpty) ...[
                      SizedBox(height: 10.h),
                      Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          iconColor: Colors.white70,
                          collapsedIconColor: Colors.white70,
                          title: Text(
                            'كشف الحركات (${_visibleOwnerLedgerEntries(owner.ledger).length})',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          children: _visibleOwnerLedgerEntries(owner.ledger)
                              .map(_ownerLedgerTile)
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _officeTab(ComprehensiveReportSnapshot data) {
    final office = data.office;
    final String commissionConfigText;
    final String commissionBehaviorText;
    if (_globalCommissionRule.mode == CommissionMode.unspecified) {
      commissionConfigText = 'غير محدد';
      commissionBehaviorText =
          'يجب تحديد نظام العمولة أولًا حتى يبدأ احتساب عمولة المكتب أو تسجيلها يدويًا';
    } else if (_globalCommissionRule.mode == CommissionMode.fixed) {
      commissionConfigText = 'مبلغ ثابت';
      commissionBehaviorText = 'يُسجل يدويًا من نافذة إيراد العمولات';
    } else {
      commissionConfigText =
          'نسبة ${_globalCommissionRule.value.toStringAsFixed(2)}%';
      commissionBehaviorText = 'تُحتسب تلقائيًا من دفعات العقود';
    }
    return _tabScroll(
      child: Column(
        children: [
          _darkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('التقارير المالية للمكتب'),
                SizedBox(height: 8.h),
                _miniKpiRows3(
                  [
                    _MiniKpiCellData(
                      title: 'إيراد العمولات',
                      value: _money(office.commissionRevenue),
                    ),
                    _MiniKpiCellData(
                      title: 'مصروفات المكتب',
                      value: _money(office.officeExpenses),
                    ),
                    _MiniKpiCellData(
                      title: 'صافي ربح المكتب',
                      value: _money(office.netProfit),
                    ),
                    _MiniKpiCellData(
                      title: 'إجمالي سحوبات المكتب',
                      value: _money(office.officeWithdrawals),
                    ),
                    _MiniKpiCellData(
                      title: 'المتبقي من ربح المكتب',
                      value: _money(office.currentBalance),
                    ),
                  ],
                  titleHeight: 30.h,
                ),
                SizedBox(height: 8.h),
                Text(
                  'إيراد العمولات - مصروفات المكتب = صافي ربح المكتب',
                  style: GoogleFonts.cairo(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.sp,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'صافي ربح المكتب - إجمالي سحوبات المكتب = المتبقي من ربح المكتب',
                  style: GoogleFonts.cairo(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.sp,
                  ),
                ),
                SizedBox(height: 10.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    if (_globalCommissionRule.mode == CommissionMode.fixed)
                      SizedBox(
                        width: 140.w,
                        child: ElevatedButton(
                          onPressed: () => _showOfficeVoucherDialog(
                            office,
                            isExpense: false,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDCFCE7),
                            foregroundColor: Colors.black87,
                          ),
                          child: Text(
                            'إيراد العمولات',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 140.w,
                      child: ElevatedButton(
                        onPressed: () => _showOfficeVoucherDialog(
                          office,
                          isExpense: true,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFEDD5),
                          foregroundColor: Colors.black87,
                        ),
                        child: Text(
                          'مصروف مكتب',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140.w,
                      child: ElevatedButton(
                        onPressed: () => _showOfficeWithdrawalDialog(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDBEAFE),
                          foregroundColor: Colors.black87,
                        ),
                        child: Text(
                          'تحويل الآن',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140.w,
                      child: ElevatedButton(
                        onPressed: () => _showCommissionDialog(data),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E7FF),
                          foregroundColor: Colors.black87,
                        ),
                        child: Text(
                          'ضبط العمولة',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                _officeInfoLine(
                  'نظام العمولة',
                  commissionConfigText,
                ),
                _officeInfoLine(
                  'طريقة التطبيق',
                  commissionBehaviorText,
                ),
              ],
            ),
          ),
          if (office.ledger.isEmpty)
            _emptyCard('لا توجد حركات مالية للمكتب ضمن الفترة الحالية')
          else
            _darkCard(
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white70,
                  title: Text(
                    'كشف حساب المكتب (${office.ledger.length})',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: office.ledger.map(_officeLedgerTile).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vouchersTab(ComprehensiveReportSnapshot data) {
    final allProperties = _loadPropertiesForReports();
    final propertyOptions = _buildPropertySelectionOptions(allProperties);
    final rawSelectedPropertyId = (_vouchersSelectedPropertyId ?? '').trim();
    final hasSelectedProperty = rawSelectedPropertyId.isNotEmpty &&
        propertyOptions.any((item) => item.propertyId == rawSelectedPropertyId);
    final selectedPropertyId = hasSelectedProperty ? rawSelectedPropertyId : '';
    final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
      allProperties,
      selectedPropertyId,
    );
    final selectedPropertyLabel = hasSelectedProperty
        ? propertyOptions
            .firstWhere((item) => item.propertyId == rawSelectedPropertyId)
            .label
        : 'الكل';
    final scopedVouchers = data.vouchers
        .where(
          (v) =>
              v.state != VoucherState.draft &&
              _matchesPropertySelectionScope(
                v.propertyId,
                selectedPropertyScopeIds,
              ),
        )
        .toList(growable: false);
    final scopedVouchersById = <String, VoucherReportItem>{
      for (final voucher in scopedVouchers) voucher.id: voucher,
    };

    String voucherOriginKey(VoucherReportItem voucher) {
      final lowerNote = voucher.note.toLowerCase();
      if (_isServiceVoucher(voucher)) {
        return 'maintenance';
      }
      if (lowerNote.contains('[manual]')) return 'manual';
      if (voucher.contractId.trim().isNotEmpty) return 'contracts';
      if (voucher.source == VoucherSource.officeCommission) {
        final linkedVoucherId = RegExp(
          r'\[contract_voucher_id:\s*([^\]\n]+)\]',
          caseSensitive: false,
        ).firstMatch(voucher.note)?.group(1)?.trim();
        if (linkedVoucherId != null && linkedVoucherId.isNotEmpty) {
          final linkedVoucher = scopedVouchersById[linkedVoucherId];
          if (linkedVoucher != null && linkedVoucher.contractId.trim().isNotEmpty) {
            return 'contracts';
          }
        }
      }
      return '';
    }

    final voucherKpiItems = <_DashboardCountItem>[
      _DashboardCountItem(
        title: 'سندات العقود',
        count: scopedVouchers
            .where((voucher) => voucherOriginKey(voucher) == 'contracts')
            .length,
        icon: Icons.description_rounded,
        startColor: const Color(0xFF0D9488),
        endColor: const Color(0xFF0F766E),
        onTap: () {
          Navigator.of(context).pushNamed(
            '/invoices',
            arguments: {'initialOrigin': 'contracts'},
          );
        },
      ),
      _DashboardCountItem(
        title: 'سندات الخدمات',
        count: scopedVouchers
            .where((voucher) => voucherOriginKey(voucher) == 'maintenance')
            .length,
        icon: Icons.build_circle_rounded,
        startColor: const Color(0xFFF97316),
        endColor: const Color(0xFFEA580C),
        onTap: () {
          Navigator.of(context).pushNamed(
            '/invoices',
            arguments: {'initialOrigin': 'maintenance'},
          );
        },
      ),
      _DashboardCountItem(
        title: 'سندات أخرى',
        count: scopedVouchers
            .where((voucher) => voucherOriginKey(voucher) == 'manual')
            .length,
        icon: Icons.edit_note_rounded,
        startColor: const Color(0xFF0F766E),
        endColor: const Color(0xFF115E59),
        onTap: () {
          Navigator.of(context).pushNamed(
            '/invoices',
            arguments: {'initialOrigin': 'manual'},
          );
        },
      ),
    ];

    Future<void> pickProperty() async {
      final result = await _showPropertySelectionSheet(
        allProperties,
        selectedPropertyId: rawSelectedPropertyId,
      );
      if (result == null || !mounted) return;
      setState(() {
        _vouchersSelectedPropertyId = result.propertyId;
      });
    }

    final visibleVouchers = scopedVouchers.where((v) {
      bool matchesStatus;
      if (_voucherStatusFilter == _VoucherStatusFilter.posted) {
        matchesStatus = v.state == VoucherState.posted;
      } else if (_voucherStatusFilter == _VoucherStatusFilter.cancelled) {
        matchesStatus = v.state == VoucherState.cancelled ||
            v.state == VoucherState.reversed;
      } else {
        matchesStatus = true;
      }
      bool matchesDirection;
      if (_voucherDirectionFilter == _VoucherDirectionFilter.receipts) {
        matchesDirection = v.direction == VoucherDirection.receipt;
      } else if (_voucherDirectionFilter ==
          _VoucherDirectionFilter.payments) {
        matchesDirection = v.direction == VoucherDirection.payment;
      } else {
        matchesDirection = true;
      }
      final matchesOperation =
          _matchesVoucherOperationFilter(v, _voucherOperationFilter);
      return matchesStatus && matchesDirection && matchesOperation;
    }).toList(growable: false);

    return _tabScroll(
      child: Column(
        children: [
          _dashboardCountsGrid(voucherKpiItems),
          SizedBox(height: 12.h),
          _darkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('فلترة السندات'),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Text(
                      'اختيار عقار',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.sp,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: pickProperty,
                          borderRadius: BorderRadius.circular(12.r),
                          child: Container(
                            constraints: BoxConstraints(maxWidth: 220.w),
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 10.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedPropertyLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.sp,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                const Icon(
                                  Icons.apartment_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Expanded(
                      child: _dropdownField<_VoucherStatusFilter>(
                        title: 'الحالة',
                        value: _voucherStatusFilter,
                        items: _VoucherStatusFilter.values
                            .map(
                              (e) => DropdownMenuItem<_VoucherStatusFilter?>(
                              value: e,
                              child: Text(e.label),
                            ),
                          )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _voucherStatusFilter = v);
                        },
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: _dropdownField<_VoucherDirectionFilter>(
                        title: 'الاتجاه',
                        value: _voucherDirectionFilter,
                        items: _VoucherDirectionFilter.values
                            .map(
                              (e) => DropdownMenuItem<_VoucherDirectionFilter?>(
                                value: e,
                                child: Text(e.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _voucherDirectionFilter = v);
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                _voucherOperationSelectorField<_VoucherOperationFilter>(
                  title: 'نوع العملية',
                  value: _voucherOperationFilter,
                  items: _VoucherOperationFilter.values
                      .map(
                        (e) => DropdownMenuItem<_VoucherOperationFilter?>(
                          value: e,
                          child: Text(e.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _voucherOperationFilter = v);
                  },
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'يعرض هذا القسم سجل السندات المرجعي مع فتح السند مباشرة.',
                        style: GoogleFonts.cairo(
                          color: Colors.white60,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (visibleVouchers.isEmpty)
            _emptyCard('لا توجد سندات ضمن الفلاتر الحالية')
          else
            _darkCard(
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white70,
                  title: Text(
                    'كشف السندات (${visibleVouchers.length})',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: visibleVouchers
                      .map((v) => _voucherReportTile(v, data))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openGeneralFiltersSheet() async {
    final result = await showModalBottomSheet<ComprehensiveReportFilters>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
      ),
      builder: (ctx) {
        var f = ComprehensiveReportFilters(
          from: _filters.from,
          to: _filters.to,
        );
        return StatefulBuilder(
          builder: (context, setM) {
            Future<void> pickDate(bool from) async {
              final picked = await showDatePicker(
                context: context,
                initialDate: (from ? f.from : f.to) ?? KsaTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              final pickedDate =
                  DateTime(picked.year, picked.month, picked.day);
              setM(() {
                if (from) {
                  final currentTo = f.to;
                  f = f.copyWith(
                    from: pickedDate,
                    to: currentTo != null && currentTo.isBefore(pickedDate)
                        ? pickedDate
                        : currentTo,
                  );
                } else {
                  final currentFrom = f.from;
                  f = f.copyWith(
                    from: currentFrom != null && currentFrom.isAfter(pickedDate)
                        ? pickedDate
                        : currentFrom,
                    to: pickedDate,
                  );
                }
              });
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16.w,
                12.h,
                16.w,
                16.h + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'تحديد الفترة',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18.sp,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    _darkCard(
                      child: Column(
                        children: [
                          _fieldButton(
                            title: 'من تاريخ',
                            value: _fmtDate(f.from) ?? '—',
                            onTap: () => pickDate(true),
                          ),
                          SizedBox(height: 8.h),
                          _fieldButton(
                            title: 'إلى تاريخ',
                            value: _fmtDate(f.to) ?? '—',
                            onTap: () => pickDate(false),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, f),
                            child: Text(
                              'حفظ',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'إلغاء',
                              style: GoogleFonts.cairo(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    _applyPeriodFilters(from: result.from, to: result.to);
  }

  Future<void> _showAssignOwnerDialog(PropertyReportItem item) async {
    final candidates = _ownerCandidates();
    if (candidates.isEmpty) {
      _showSnack('لا يوجد سجلات ملاك في شاشة العملاء.');
      return;
    }

    String? selected = item.ownerId.isEmpty ? null : item.ownerId;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          title: Text(
            'تعيين مالك للعقار',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: StatefulBuilder(
            builder: (context, setM) {
              return _dropdownField<String>(
                title: 'المالك',
                value: selected,
                items: candidates
                    .map(
                      (t) => DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.fullName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setM(() => selected = v),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'حفظ',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(color: Colors.white70),
              ),
            ),
          ],
        );
      },
    );

    if (res != true || selected == null) return;
    final owner = candidates.firstWhere((e) => e.id == selected);
    await ComprehensiveReportsService.assignPropertyOwner(
      propertyId: item.propertyId,
      ownerId: owner.id,
      ownerName: owner.fullName,
    );
    _showSnack('تم تحديث مالك العقار');
    _refresh();
  }

  Future<void> _showOwnerBankAccountsDialog(OwnerReportItem owner) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OwnerBankAccountsScreen(owner: owner),
      ),
    );
  }

  Future<bool?> _showAddOwnerBankAccountDialog(OwnerReportItem owner) async {
    final bankCtl = TextEditingController();
    final accountCtl = TextEditingController();
    final ibanCtl = TextEditingController();
    String? formError;
    String? bankError;
    String? accountError;
    String? ibanError;
    bool submitting = false;

    String? validateMaxLength(String value, int max, String label) {
      if (value.length >= max) {
        return '$label وصل إلى الحد الأقصى $max';
      }
      return null;
    }

    void updateFieldErrors({bool includeRequired = false}) {
      final bankName = bankCtl.text.trim();
      final accountNumber = accountCtl.text.trim();
      final iban = ibanCtl.text.trim();

      bankError = includeRequired && bankName.isEmpty
          ? 'اسم البنك مطلوب'
          : validateMaxLength(bankName, 30, 'اسم البنك');
      accountError = includeRequired && accountNumber.isEmpty
          ? 'رقم الحساب مطلوب'
          : validateMaxLength(accountNumber, 40, 'رقم الحساب');
      ibanError = validateMaxLength(iban, 40, 'رقم الآيبان');
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setM) {
            void onFieldChanged() {
              setM(() {
                formError = null;
                updateFieldErrors();
              });
            }

            Future<void> saveAccount() async {
              setM(() {
                updateFieldErrors(includeRequired: true);
                final hasErrors = bankError != null ||
                    accountError != null ||
                    ibanError != null;
                formError = hasErrors
                    ? 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.'
                    : null;
              });

              if (formError != null) return;

              setM(() => submitting = true);
              try {
                await ComprehensiveReportsService.addOwnerBankAccount(
                  ownerId: owner.ownerId,
                  ownerName: owner.ownerName,
                  bankName: bankCtl.text.trim(),
                  accountNumber: accountCtl.text.trim(),
                  iban: ibanCtl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(true);
              } catch (e) {
                setM(() {
                  formError = e.toString();
                  submitting = false;
                });
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22.r),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 520.w),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _lightDialogHeader(
                          title: 'إضافة حساب جديد',
                          onCancel: submitting
                              ? null
                              : () => Navigator.of(ctx).pop(false),
                          onSave: submitting ? null : saveAccount,
                          submitting: submitting,
                        ),
                        SizedBox(height: 12.h),
                        _lightInfoCard(
                          child: _lightDialogLine('المالك', owner.ownerName),
                        ),
                        if (formError != null) ...[
                          SizedBox(height: 12.h),
                          _dialogErrorBanner(formError!),
                        ],
                        SizedBox(height: 12.h),
                        TextField(
                          controller: bankCtl,
                          onChanged: (_) => onFieldChanged(),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(30),
                          ],
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF0F172A),
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: _lightDialogInputDeco(
                            'اسم البنك',
                            errorText: bankError,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        TextField(
                          controller: accountCtl,
                          onChanged: (_) => onFieldChanged(),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(40),
                          ],
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF0F172A),
                          ),
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          decoration: _lightDialogInputDeco(
                            'رقم الحساب',
                            errorText: accountError,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        TextField(
                          controller: ibanCtl,
                          onChanged: (_) => onFieldChanged(),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(40),
                          ],
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF0F172A),
                          ),
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.text,
                          decoration: _lightDialogInputDeco(
                            'رقم الآيبان (اختياري)',
                            errorText: ibanError,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    bankCtl.dispose();
    accountCtl.dispose();
    ibanCtl.dispose();
    return result;
  }

  Future<void> _showOwnerPreview(
    OwnerReportItem owner, {
    String? propertyId,
  }) async {
    final effectivePropertyId = (propertyId ?? '').trim();
    final effectiveFilters = effectivePropertyId.isEmpty
        ? _filters
        : _filters.copyWith(propertyId: effectivePropertyId);
    final preview = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: owner.ownerId,
      filters: effectiveFilters,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          title: Text(
            'معاينة تسوية ${owner.ownerName}',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogLine('الرصيد السابق', _money(preview.previousBalance)),
                _dialogLine('الإيجارات المحصلة', _money(preview.collectedRent)),
                _dialogLine(
                  'عمولة المكتب المخصومة',
                  _money(preview.deductedCommission),
                ),
                _dialogLine(
                  'المصروفات المخصومة',
                  _money(preview.deductedExpenses),
                ),
                _dialogLine(
                  'الخصومات/التسويات',
                  _money(preview.deductedAdjustments),
                ),
                _dialogLine(
                    'التحويلات السابقة', _money(preview.previousPayouts)),
                const Divider(color: Colors.white24),
                _dialogLine(
                  'القابل للتحويل الآن',
                  _money(preview.readyForPayout),
                  strong: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'إغلاق',
                style: GoogleFonts.cairo(color: Colors.white70),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showOwnerPayoutDialog(
    OwnerReportItem owner, {
    String? propertyId,
    String propertyName = '',
  }) async {
    final effectivePropertyId = (propertyId ?? '').trim();
    final effectiveFilters = effectivePropertyId.isEmpty
        ? _filters
        : _filters.copyWith(propertyId: effectivePropertyId);
    final preview = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: owner.ownerId,
      filters: effectiveFilters,
    );
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OwnerPayoutScreen(
          owner: owner,
          preview: preview,
          onSubmit: ({
            required double amount,
            required DateTime transferDate,
            required String note,
          }) async {
            _holdReactiveRefresh();
            try {
              final rec = await _runWithReactiveRefreshPaused(() {
                return ComprehensiveReportsService.executeOwnerPayout(
                  ownerId: owner.ownerId,
                  ownerName: owner.ownerName,
                  amount: amount,
                  transferDate: transferDate,
                  periodFrom: _filters.from,
                  periodTo: _filters.to,
                  note: note,
                  propertyId: effectivePropertyId,
                  propertyName: propertyName,
                  filters: effectiveFilters,
                );
              });
              if (!mounted) return;
              final voucherNo = rec.voucherSerialNo.trim().isNotEmpty
                  ? rec.voucherSerialNo.trim()
                  : rec.voucherId;
              await PdfExportService.shareOwnerPayoutSettlementPdf(
                context: context,
                ownerName: owner.ownerName,
                amount: amount,
                transferDate: transferDate,
                periodFrom: _filters.from,
                periodTo: _filters.to,
                collectedRent: preview.collectedRent,
                commission: preview.deductedCommission,
                expenses: preview.deductedExpenses,
                additionalDeductions: preview.deductedAdjustments,
                previousPayouts: preview.previousPayouts,
                readyBefore: preview.readyForPayout,
                voucherNo: voucherNo,
                note: note,
              );
            } catch (e) {
              _pauseReactiveRefresh = false;
              rethrow;
            }
          },
        ),
      ),
    );

    if (done == true) {
      _showSnack('تم تنفيذ تحويل المالك وربطه بالتقارير');
      _scheduleRefreshAfterOwnerAction();
    } else {
      _pauseReactiveRefresh = false;
    }
  }

  Future<void> _showOwnerAdjustmentDialog(
    OwnerReportItem owner, {
    String? propertyId,
    String propertyName = '',
  }) async {
    final effectivePropertyId = (propertyId ?? '').trim();
    final effectiveFilters = effectivePropertyId.isEmpty
        ? _filters
        : _filters.copyWith(propertyId: effectivePropertyId);
    final preview = await ComprehensiveReportsService.previewOwnerSettlement(
      ownerId: owner.ownerId,
      filters: effectiveFilters,
    );
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OwnerAdjustmentScreen(
          owner: owner,
          preview: preview,
          onSubmit: ({
            required OwnerAdjustmentCategory category,
            required double amount,
            required DateTime adjustmentDate,
            required String note,
          }) async {
            _holdReactiveRefresh();
            try {
              await _runWithReactiveRefreshPaused(() {
                return ComprehensiveReportsService.executeOwnerAdjustment(
                  ownerId: owner.ownerId,
                  ownerName: owner.ownerName,
                  amount: amount,
                  category: category,
                  adjustmentDate: adjustmentDate,
                  periodFrom: _filters.from,
                  periodTo: _filters.to,
                  note: note,
                  propertyId: effectivePropertyId,
                  propertyName: propertyName,
                  filters: effectiveFilters,
                );
              });
            } catch (e) {
              _pauseReactiveRefresh = false;
              rethrow;
            }
          },
        ),
      ),
    );

    if (done == true) {
      _showSnack('تم تسجيل الخصم وربطه بالتقارير');
      _scheduleRefreshAfterOwnerAction();
    } else {
      _pauseReactiveRefresh = false;
    }
  }

  Future<void> _showOfficeVoucherDialog(
    OfficeReportSummary office, {
    required bool isExpense,
  }) async {
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OfficeVoucherScreen(
          office: office,
          isExpense: isExpense,
          onSubmit: ({
            required double amount,
            required DateTime transactionDate,
            required String note,
          }) async {
            _holdReactiveRefresh();
            try {
              await _runWithReactiveRefreshPaused(() {
                return ComprehensiveReportsService.executeOfficeManualVoucher(
                  isExpense: isExpense,
                  amount: amount,
                  transactionDate: transactionDate,
                  note: note,
                );
              });
            } catch (e) {
              _pauseReactiveRefresh = false;
              rethrow;
            }
          },
        ),
      ),
    );

    if (saved == true) {
      _showSnack(
        isExpense
            ? 'تم تسجيل مصروف المكتب وربطه بالتقارير'
            : 'تم تسجيل إيراد العمولات وربطه بالتقارير',
      );
      _scheduleRefreshAfterDialogAction();
    } else {
      _pauseReactiveRefresh = false;
    }
  }

  Future<void> _showOfficeWithdrawalDialog() async {
    final preview = await ComprehensiveReportsService.previewOfficeSettlement(
      filters: _filters,
    );
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OfficeWithdrawalScreen(
          preview: preview,
          onSubmit: ({
            required double amount,
            required DateTime transferDate,
            required String note,
          }) async {
            _holdReactiveRefresh();
            try {
              await _runWithReactiveRefreshPaused(() {
                return ComprehensiveReportsService.executeOfficeWithdrawal(
                  amount: amount,
                  transferDate: transferDate,
                  note: note,
                  filters: _filters,
                );
              });
            } catch (e) {
              _pauseReactiveRefresh = false;
              rethrow;
            }
          },
        ),
      ),
    );

    if (done == true) {
      _showSnack('تم تنفيذ تحويل المكتب وربطه بالتقارير');
      _scheduleRefreshAfterDialogAction();
    } else {
      _pauseReactiveRefresh = false;
    }
  }

  Future<void> _showCommissionDialog(ComprehensiveReportSnapshot _) async {
    final result = await showDialog<_CommissionRuleDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _CommissionRuleDialog(
          initialMode: _globalCommissionRule.mode,
          initialValue: _globalCommissionRule.value,
        );
      },
    );

    if (result == null) return;
    await ComprehensiveReportsService.setCommissionRule(
      scope: CommissionScope.global,
      rule: CommissionRule(mode: result.mode, value: result.value),
    );
    _showSnack('تم حفظ إعداد العمولة');
    _refresh();
  }

  List<Tenant> _ownerCandidates() {
    final boxNameValue = boxName(kTenantsBox);
    if (!Hive.isBoxOpen(boxNameValue)) return const [];
    final box = Hive.box<Tenant>(boxNameValue);
    final owners = box.values
        .where(
          (t) => !t.isArchived && t.clientType.toLowerCase().contains('owner'),
        )
        .toList();
    if (owners.isNotEmpty) {
      owners.sort((a, b) => a.fullName.compareTo(b.fullName));
      return owners;
    }
    final fallback = box.values.where((t) => !t.isArchived).toList();
    fallback.sort((a, b) => a.fullName.compareTo(b.fullName));
    return fallback;
  }

  String _filtersSummaryText() {
    if (_filters.from == null && _filters.to == null) {
      return 'الفترة: كل الفترة';
    }
    final from = _fmtDate(_filters.from) ?? 'بداية مفتوحة';
    final to = _fmtDate(_filters.to) ?? 'نهاية مفتوحة';
    return 'الفترة: $from إلى $to';
  }

  _PeriodChip _selectedPeriodChip() {
    final from = _filters.from;
    final to = _filters.to;
    if (from == null && to == null) {
      return _PeriodChip.all;
    }

    final normalizedFrom =
        from == null ? null : DateTime(from.year, from.month, from.day);
    final normalizedTo = to == null ? null : DateTime(to.year, to.month, to.day);
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekday = now.weekday;
    final weekStart = DateTime(now.year, now.month, now.day - (weekday - 1));
    final weekEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    if (normalizedFrom == today && normalizedTo == today) {
      return _PeriodChip.today;
    }
    if (normalizedFrom == weekStart && normalizedTo == weekEnd) {
      return _PeriodChip.week;
    }
    if (normalizedFrom == monthStart && normalizedTo == monthEnd) {
      return _PeriodChip.month;
    }
    return _PeriodChip.custom;
  }

  void _applyPeriodFilters({
    required DateTime? from,
    required DateTime? to,
  }) {
    DateTime? normalizedFrom = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    DateTime? normalizedTo =
        to == null ? null : DateTime(to.year, to.month, to.day);
    if (normalizedFrom != null &&
        normalizedTo != null &&
        normalizedFrom.isAfter(normalizedTo)) {
      final temp = normalizedFrom;
      normalizedFrom = normalizedTo;
      normalizedTo = temp;
    }
    setState(() {
      _filters = ComprehensiveReportFilters(
        from: normalizedFrom,
        to: normalizedTo,
      );
    });
    _refresh();
  }

  void _applyQuickRange(_QuickRange range) {
    final now = KsaTime.now();
    DateTime start;
    DateTime end;
    switch (range) {
      case _QuickRange.today:
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day);
        break;
      case _QuickRange.week:
        final weekday = now.weekday;
        start = DateTime(now.year, now.month, now.day - (weekday - 1));
        end = DateTime(start.year, start.month, start.day + 6);
        break;
      case _QuickRange.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
    }
    _applyPeriodFilters(from: start, to: end);
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PropertiesScreen()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const tenants_ui.TenantsScreen()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ContractsScreen()),
        );
        break;
    }
  }

  Widget _gradientBg() {
    return Container(
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
    );
  }

  Widget _softCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _flowIndicatorsBand(ComprehensiveReportSnapshot data) {
    _scheduleFlowAutoScroll();
    final d = data.dashboard;
    final ownerNetBalance = data.owners.fold<double>(
      0,
      (sum, owner) => sum + owner.currentBalance,
    );
    final items = <_FlowIndicatorItem>[
      _FlowIndicatorItem(
        label: 'إجمالي الإيرادات',
        amount: d.totalReceipts,
        color: const Color(0xFF22C55E),
        icon: Icons.download_rounded,
      ),
      _FlowIndicatorItem(
        label: 'إجمالي المصروفات',
        amount: d.totalExpenses,
        color: const Color(0xFFF97316),
        icon: Icons.upload_rounded,
      ),
      _FlowIndicatorItem(
        label: 'الصافي',
        amount: d.netCashFlow,
        color: const Color(0xFF38BDF8),
        icon: Icons.swap_vert_circle,
      ),
      _FlowIndicatorItem(
        label: 'عمولة المكتب',
        amount: d.officeCommissions,
        color: const Color(0xFFFACC15),
        icon: Icons.percent_rounded,
      ),
      _FlowIndicatorItem(
        label: 'الرصيد الصافي للمالك',
        amount: ownerNetBalance,
        color: const Color(0xFFFB7185),
        icon: Icons.account_balance_wallet_rounded,
      ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: const Color(0xB30B1220),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white24),
        ),
        child: Listener(
          onPointerDown: (_) => _stopFlowAutoScrollByUser(),
          child: SingleChildScrollView(
            controller: _flowScrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: items
                  .map(
                    (item) => Padding(
                      padding: EdgeInsets.only(left: 8.w),
                      child: _flowIndicatorTile(item: item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flowIndicatorTile({
    required _FlowIndicatorItem item,
  }) {
    final indicatorColor =
        item.amount < 0 ? const Color(0xFFF87171) : item.color;
    final hasValue = item.amount.abs() > 0.000001;
    return Container(
      width: 146.w,
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44.w,
                height: 44.w,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: hasValue ? 1.0 : 0.0,
                      strokeWidth: 4.6,
                      color: indicatorColor,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                    Icon(
                      item.icon,
                      color: indicatorColor,
                      size: 16.sp,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            _money(item.amount),
            style: GoogleFonts.cairo(
              color: item.amount < 0 ? const Color(0xFFFCA5A5) : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _styledTabs() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 4.h),
      child: Container(
        padding: EdgeInsets.all(6.w),
        decoration: BoxDecoration(
          color: const Color(0xA60B1220),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white24),
        ),
        child: TabBar(
          isScrollable: true,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: EdgeInsets.symmetric(horizontal: 5.w),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w800,
            fontSize: 12.sp,
          ),
          unselectedLabelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w700,
            fontSize: 12.sp,
          ),
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            gradient: const LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF0D9488)],
            ),
            border: Border.all(color: Colors.white24),
          ),
          tabs: [
            _reportTab('عام', Icons.dashboard_rounded),
            _reportTab('العقارات', Icons.apartment_rounded),
            _reportTab('العملاء', Icons.groups_rounded),
            _reportTab('العقود', Icons.description_rounded),
            _reportTab('الخدمات', Icons.miscellaneous_services_rounded),
            _reportTab('السندات', Icons.receipt_long_rounded),
            _reportTab('المكتب', Icons.business_center_rounded),
            _reportTab('المالك', Icons.person_rounded),
          ],
        ),
      ),
    );
  }

  Tab _reportTab(String title, IconData icon) {
    return Tab(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15.sp),
            SizedBox(width: 6.w),
            Text(title),
          ],
        ),
      ),
    );
  }

  Widget _tabScroll({required Widget child}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 24.h),
      child: child,
    );
  }

  Widget _darkCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      padding: padding ?? EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1220),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Widget _emptyCard(String text) {
    return _darkCard(
      child: Text(
        text,
        style: GoogleFonts.cairo(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _quickChip(
    String label,
    VoidCallback onTap, {
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF22D3EE), Color(0xFF0D9488)],
                )
              : null,
          color: isSelected ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? const Color(0xFF93C5FD) : Colors.white24,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x333B82F6),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12.sp,
          ),
        ),
      ),
    );
  }

  Widget _metricsGrid(List<_MetricItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900
            ? 4
            : width > 680
                ? 3
                : width > 420
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8.w,
            mainAxisSpacing: 8.h,
            childAspectRatio: width > 450 ? 2.5 : 2.1,
          ),
          itemBuilder: (context, i) {
            final item = items[i];
            return _darkCard(
              child: Row(
                children: [
                  Container(
                    width: 42.w,
                    height: 42.w,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(item.icon, color: item.color),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.sp,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          item.value,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Tenant> _loadClientsForReports({bool includeArchived = false}) {
    return _loadTenantsForDashboard(includeArchived: includeArchived)
        .where((tenant) {
      final type = _normalizeDashboardClientType(tenant);
      return type == 'tenant' ||
          type == 'company' ||
          type == 'serviceProvider';
    }).toList();
  }

  List<Property> _loadPropertiesForReports({bool includeArchived = false}) {
    final name = boxName(kPropertiesBox);
    if (!Hive.isBoxOpen(name)) return const <Property>[];
    try {
      return Hive.box<Property>(name)
          .values
          .where((property) => includeArchived || !property.isArchived)
          .toList(growable: false);
    } catch (_) {
      return const <Property>[];
    }
  }

  Set<String> _buildPropertySelectionScopeIds(
    List<Property> properties,
    String selectedPropertyId,
  ) {
    final normalizedSelected = selectedPropertyId.trim();
    if (normalizedSelected.isEmpty) return const <String>{};
    final ids = <String>{normalizedSelected};
    for (final property in properties) {
      if ((property.parentBuildingId ?? '').trim() == normalizedSelected) {
        ids.add(property.id);
      }
    }
    return ids;
  }

  bool _matchesPropertySelectionScope(
    String recordPropertyId,
    Set<String> selectedPropertyIds,
  ) {
    if (selectedPropertyIds.isEmpty) return true;
    return selectedPropertyIds.contains(recordPropertyId.trim());
  }

  Widget? _selectionCheckmark(bool isSelected) {
    if (!isSelected) return null;
    return const Icon(
      Icons.check_rounded,
      color: Color(0xFF60A5FA),
      size: 20,
    );
  }

  List<_PropertySelectionOption> _buildPropertySelectionOptions(
    List<Property> properties,
  ) {
    final topLevel = properties
        .where((property) => (property.parentBuildingId ?? '').trim().isEmpty)
        .toList(growable: false);
    final unitsByBuilding = <String, List<Property>>{};
    for (final property in properties) {
      final parentId = (property.parentBuildingId ?? '').trim();
      if (parentId.isEmpty) continue;
      unitsByBuilding.putIfAbsent(parentId, () => <Property>[]).add(property);
    }
    for (final units in unitsByBuilding.values) {
      units.sort((a, b) => a.name.compareTo(b.name));
    }

    final sortedTopLevel = topLevel.toList(growable: false)
      ..sort((a, b) {
        final aIsBuildingWithUnits =
            a.type == PropertyType.building &&
                (unitsByBuilding[a.id]?.isNotEmpty ?? false);
        final bIsBuildingWithUnits =
            b.type == PropertyType.building &&
                (unitsByBuilding[b.id]?.isNotEmpty ?? false);
        if (aIsBuildingWithUnits != bIsBuildingWithUnits) {
          return aIsBuildingWithUnits ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    final options = <_PropertySelectionOption>[];
    for (final property in sortedTopLevel) {
      final units = unitsByBuilding[property.id] ?? const <Property>[];
      final isBuildingWithUnits =
          property.type == PropertyType.building && units.isNotEmpty;
      if (isBuildingWithUnits) {
        options.add(
          _PropertySelectionOption(
            propertyId: property.id,
            label: '${property.name} (مع جميع الوحدات)',
          ),
        );
        for (final unit in units) {
          options.add(
            _PropertySelectionOption(
              propertyId: unit.id,
              label: '${property.name} / ${unit.name}',
            ),
          );
        }
        continue;
      }
      options.add(
        _PropertySelectionOption(
          propertyId: property.id,
          label: property.name,
        ),
      );
    }
    return options;
  }

  Future<_PropertySelectionSheetResult?> _showPropertySelectionSheet(
    List<Property> properties, {
    String allOptionLabel = 'الكل',
    String? selectedPropertyId,
    String? secondaryOptionLabel,
    String? secondaryOptionValue,
  }) {
    final topLevel = properties
        .where((property) => (property.parentBuildingId ?? '').trim().isEmpty)
        .toList(growable: false);
    final unitsByBuilding = <String, List<Property>>{};
    for (final property in properties) {
      final parentId = (property.parentBuildingId ?? '').trim();
      if (parentId.isEmpty) continue;
      unitsByBuilding.putIfAbsent(parentId, () => <Property>[]).add(property);
    }
    for (final units in unitsByBuilding.values) {
      units.sort((a, b) => a.name.compareTo(b.name));
    }

    final sortedTopLevel = topLevel.toList(growable: false)
      ..sort((a, b) {
        final aIsBuildingWithUnits =
            a.type == PropertyType.building &&
                (unitsByBuilding[a.id]?.isNotEmpty ?? false);
        final bIsBuildingWithUnits =
            b.type == PropertyType.building &&
                (unitsByBuilding[b.id]?.isNotEmpty ?? false);
        if (aIsBuildingWithUnits != bIsBuildingWithUnits) {
          return aIsBuildingWithUnits ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    return showModalBottomSheet<_PropertySelectionSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final normalizedSelectedPropertyId = (selectedPropertyId ?? '').trim();
        final selectedPropertyScopeIds = _buildPropertySelectionScopeIds(
          properties,
          normalizedSelectedPropertyId,
        );
        final isAllSelected = normalizedSelectedPropertyId.isEmpty;
        final isSecondarySelected =
            secondaryOptionValue != null &&
            normalizedSelectedPropertyId == secondaryOptionValue.trim();
        return SafeArea(
          child: SizedBox(
            height: media.size.height * 0.72,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('اختيار عقار'),
                  SizedBox(height: 10.h),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => Navigator.of(sheetContext).pop(
                      const _PropertySelectionSheetResult(propertyId: null),
                    ),
                    leading: const Icon(
                      Icons.layers_clear_rounded,
                      color: Colors.white70,
                    ),
                    title: Text(
                      allOptionLabel,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: _selectionCheckmark(isAllSelected),
                  ),
                  if (secondaryOptionLabel != null &&
                      secondaryOptionValue != null) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => Navigator.of(sheetContext).pop(
                        _PropertySelectionSheetResult(
                          propertyId: secondaryOptionValue,
                        ),
                      ),
                      leading: const Icon(
                        Icons.dashboard_customize_rounded,
                        color: Colors.white70,
                      ),
                      title: Text(
                        secondaryOptionLabel,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: _selectionCheckmark(isSecondarySelected),
                    ),
                  ],
                  SizedBox(height: 6.h),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final property in sortedTopLevel) ...[
                          if (property.type == PropertyType.building &&
                              (unitsByBuilding[property.id]?.isNotEmpty ??
                                  false))
                            Container(
                              margin: EdgeInsets.only(bottom: 8.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.symmetric(
                                  horizontal: 12.w,
                                ),
                                childrenPadding: EdgeInsets.only(
                                  right: 10.w,
                                  left: 10.w,
                                  bottom: 6.h,
                                ),
                                iconColor: Colors.white70,
                                collapsedIconColor: Colors.white70,
                                title: Text(
                                  property.name,
                                  style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: (property.address).trim().isEmpty
                                    ? null
                                    : Text(
                                        property.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.cairo(
                                          color: Colors.white70,
                                        ),
                                      ),
                                children: [
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6.w,
                                    ),
                                    onTap: () => Navigator.of(sheetContext).pop(
                                      _PropertySelectionSheetResult(
                                        propertyId: property.id,
                                      ),
                                    ),
                                    leading: const Icon(
                                      Icons.apartment_rounded,
                                      color: Colors.white70,
                                    ),
                                    title: Text(
                                      'عرض العمارة مع جميع وحداتها',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    trailing: _selectionCheckmark(
                                      selectedPropertyScopeIds
                                              .contains(property.id) &&
                                          normalizedSelectedPropertyId ==
                                              property.id,
                                    ),
                                  ),
                                  for (final unit
                                      in unitsByBuilding[property.id] ??
                                          const <Property>[])
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6.w,
                                      ),
                                      onTap: () => Navigator.of(sheetContext)
                                          .pop(
                                        _PropertySelectionSheetResult(
                                          propertyId: unit.id,
                                        ),
                                      ),
                                      leading: const Icon(
                                        Icons.meeting_room_rounded,
                                        color: Colors.white70,
                                      ),
                                      title: Text(
                                        unit.name,
                                        style: GoogleFonts.cairo(
                                          color: Colors.white,
                                        ),
                                      ),
                                      trailing: _selectionCheckmark(
                                        selectedPropertyScopeIds
                                            .contains(unit.id),
                                      ),
                                      subtitle: (unit.address).trim().isEmpty
                                          ? null
                                          : Text(
                                              unit.address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.cairo(
                                                color: Colors.white70,
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                            )
                          else
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              onTap: () => Navigator.of(sheetContext).pop(
                                _PropertySelectionSheetResult(
                                  propertyId: property.id,
                                ),
                              ),
                              leading: const Icon(
                                Icons.home_work_rounded,
                                color: Colors.white70,
                              ),
                               title: Text(
                                 property.name,
                                 style: GoogleFonts.cairo(
                                   color: Colors.white,
                                   fontWeight: FontWeight.w700,
                                 ),
                               ),
                               trailing: _selectionCheckmark(
                                 normalizedSelectedPropertyId == property.id,
                               ),
                               subtitle: (property.address).trim().isEmpty
                                   ? null
                                   : Text(
                                      property.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                      ),
                                    ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Tenant> _filterClientsForReports(List<Tenant> items) {
    var filtered = items.where((tenant) {
      final type = _normalizeDashboardClientType(tenant);
      return type == 'tenant' || type == 'company';
    }).toList();

    if (_clientsTenantSubTypeFilter ==
        _ClientTenantSubTypeFilter.individuals) {
      filtered = filtered
          .where((tenant) => _normalizeDashboardClientType(tenant) == 'tenant')
          .toList();
    } else if (_clientsTenantSubTypeFilter ==
        _ClientTenantSubTypeFilter.companies) {
      filtered = filtered
          .where((tenant) => _normalizeDashboardClientType(tenant) == 'company')
          .toList();
    }

    filtered.sort((a, b) {
      final updatedCmp = b.updatedAt.compareTo(a.updatedAt);
      if (updatedCmp != 0) return updatedCmp;
      final createdCmp = b.createdAt.compareTo(a.createdAt);
      if (createdCmp != 0) return createdCmp;
      return b.id.compareTo(a.id);
    });

    return filtered;
  }

  String _clientReportTypeLabel(String type) {
    switch (type) {
      case 'company':
        return 'مستأجر شركة';
      case 'serviceProvider':
        return 'مقدم خدمة';
      case 'tenant':
      default:
        return 'مستأجر فرد';
    }
  }

  Color _clientReportTypeColor(String type) {
    switch (type) {
      case 'company':
        return const Color(0xFFB45309);
      case 'serviceProvider':
        return const Color(0xFF9A3412);
      case 'tenant':
      default:
        return const Color(0xFF0D9488);
    }
  }

  String _clientReportMetaText(Tenant client, String type) {
    final parts = <String>[];
    if (type == 'company') {
      final companyName = (client.companyName ?? '').trim();
      final companyRegister = (client.companyCommercialRegister ?? '').trim();
      if (companyName.isNotEmpty && companyName != client.fullName.trim()) {
        parts.add('المنشأة: $companyName');
      }
      if (companyRegister.isNotEmpty) {
        parts.add('السجل: $companyRegister');
      } else if (client.nationalId.trim().isNotEmpty) {
        parts.add('الهوية: ${client.nationalId.trim()}');
      }
    } else if (type == 'serviceProvider') {
      final specialization = (client.serviceSpecialization ?? '').trim();
      if (specialization.isNotEmpty) {
        parts.add('التخصص: $specialization');
      }
      if (client.nationalId.trim().isNotEmpty) {
        parts.add('الهوية: ${client.nationalId.trim()}');
      }
    } else if (client.nationalId.trim().isNotEmpty) {
      parts.add('الهوية: ${client.nationalId.trim()}');
    }

    if (client.phone.trim().isNotEmpty) {
      parts.add('الجوال: ${client.phone.trim()}');
    }

    return parts.isEmpty ? 'لا توجد بيانات إضافية' : parts.join(' • ');
  }

  Future<void> _openClientsScreen({
    String? clientType,
    String? openTenantId,
    String? tenantType,
    String? tenantSubType,
    String? linkedState,
    String? idExpiryState,
    String? archiveState,
  }) async {
    final args = <String, dynamic>{};
    final normalizedType = (clientType ?? '').trim();
    final normalizedOpenId = (openTenantId ?? '').trim();
    final normalizedTenantType = (tenantType ?? '').trim();
    final normalizedTenantSubType = (tenantSubType ?? '').trim();
    final normalizedLinkedState = (linkedState ?? '').trim();
    final normalizedIdExpiryState = (idExpiryState ?? '').trim();
    final normalizedArchiveState = (archiveState ?? '').trim();
    if (normalizedType.isNotEmpty) {
      args['filterClientType'] = normalizedType;
    }
    if (normalizedOpenId.isNotEmpty) {
      args['openTenantId'] = normalizedOpenId;
    }
    if (normalizedTenantType.isNotEmpty) {
      args['filterTenantType'] = normalizedTenantType;
    }
    if (normalizedTenantSubType.isNotEmpty) {
      args['filterTenantSubType'] = normalizedTenantSubType;
    }
    if (normalizedLinkedState.isNotEmpty) {
      args['filterLinked'] = normalizedLinkedState;
    }
    if (normalizedIdExpiryState.isNotEmpty) {
      args['filterIdExpiry'] = normalizedIdExpiryState;
    }
    if (normalizedArchiveState.isNotEmpty) {
      args['filterArchive'] = normalizedArchiveState;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const tenants_ui.TenantsScreen(),
        settings: RouteSettings(arguments: args.isEmpty ? null : args),
      ),
    );
  }

  List<Tenant> _loadTenantsForDashboard({bool includeArchived = false}) {
    final name = boxName(kTenantsBox);
    if (!Hive.isBoxOpen(name)) return const <Tenant>[];
    try {
      return Hive.box<Tenant>(name)
          .values
          .where((t) => includeArchived || !t.isArchived)
          .toList(growable: false);
    } catch (_) {
      return const <Tenant>[];
    }
  }

  List<Contract> _loadContractsForReports() {
    final name = HiveService.contractsBoxName();
    if (!Hive.isBoxOpen(name)) return const <Contract>[];
    try {
      return Hive.box<Contract>(name).values.toList(growable: false);
    } catch (_) {
      return const <Contract>[];
    }
  }

  bool _matchesContractPeriodFilter(
    Contract contract,
    _ContractPeriodFilter filter,
  ) {
    switch (filter) {
      case _ContractPeriodFilter.all:
        return true;
      case _ContractPeriodFilter.daily:
        return contract.term == ContractTerm.daily;
      case _ContractPeriodFilter.monthly:
        return contract.term == ContractTerm.monthly;
      case _ContractPeriodFilter.quarterly:
        return contract.term == ContractTerm.quarterly;
      case _ContractPeriodFilter.semiAnnual:
        return contract.term == ContractTerm.semiAnnual;
      case _ContractPeriodFilter.annual:
        return contract.term == ContractTerm.annual;
    }
  }

  List<MaintenanceRequest> _loadMaintenanceForReports() {
    final name = HiveService.maintenanceBoxName();
    if (!Hive.isBoxOpen(name)) return const <MaintenanceRequest>[];
    try {
      return Hive.box<MaintenanceRequest>(name).values.toList(growable: false);
    } catch (_) {
      return const <MaintenanceRequest>[];
    }
  }

  bool _matchesServicePriorityFilter(
    ServiceReportItem _,
    MaintenancePriority? priority,
  ) {
    switch (_servicesPriorityFilter) {
      case _ServicePriorityFilter.all:
        return true;
      case _ServicePriorityFilter.low:
        return priority == MaintenancePriority.low;
      case _ServicePriorityFilter.medium:
        return priority == MaintenancePriority.medium;
      case _ServicePriorityFilter.high:
        return priority == MaintenancePriority.high;
      case _ServicePriorityFilter.urgent:
        return priority == MaintenancePriority.urgent;
    }
  }

  MaintenancePriority? _maintenancePriorityFromServicesFilter() {
    switch (_servicesPriorityFilter) {
      case _ServicePriorityFilter.all:
        return null;
      case _ServicePriorityFilter.low:
        return MaintenancePriority.low;
      case _ServicePriorityFilter.medium:
        return MaintenancePriority.medium;
      case _ServicePriorityFilter.high:
        return MaintenancePriority.high;
      case _ServicePriorityFilter.urgent:
        return MaintenancePriority.urgent;
    }
  }

  bool _isToday(DateTime date) {
    final now = KsaTime.now();
    return now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
  }

  bool _isContractNearEnd(Contract contract) {
    if (contract.isTerminated) return false;
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(
        contract.endDate.year, contract.endDate.month, contract.endDate.day);
    if (end.isBefore(today)) return false;
    final days = end.difference(today).inDays;
    return days <= 30;
  }

  bool _contractEndsToday(Contract contract) {
    if (contract.isTerminated) return false;
    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      contract.startDate.year,
      contract.startDate.month,
      contract.startDate.day,
    );
    final end = DateTime(
      contract.endDate.year,
      contract.endDate.month,
      contract.endDate.day,
    );

    if (contract.term == ContractTerm.daily) {
      return today == end && contract.isActiveNow;
    }

    return today == end && !today.isBefore(start);
  }

  bool _contractHasEnded(Contract contract) {
    if (contract.isTerminated) return false;
    if (contract.term == ContractTerm.daily) {
      return contract.isExpiredByTime;
    }

    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(
      contract.endDate.year,
      contract.endDate.month,
      contract.endDate.day,
    );
    return today.isAfter(end);
  }

  String _normalizeDashboardClientType(Tenant tenant) {
    final raw = tenant.clientType.trim().toLowerCase();
    if (raw == 'company' || raw == 'مستأجر (شركة)' || raw == 'شركة') {
      return 'company';
    }
    if (raw == 'serviceprovider' ||
        raw == 'service_provider' ||
        raw == 'service provider' ||
        raw == 'مقدم خدمة') {
      return 'serviceProvider';
    }
    if (raw == 'owner' || raw == 'مالك') return 'owner';

    final hasProviderHints =
        (tenant.serviceSpecialization ?? '').trim().isNotEmpty &&
            (tenant.companyName ?? '').trim().isEmpty &&
            (tenant.companyCommercialRegister ?? '').trim().isEmpty &&
            (tenant.tenantBankName ?? '').trim().isEmpty;
    if (hasProviderHints) return 'serviceProvider';
    return 'tenant';
  }

  Widget _dashboardCountsGrid(List<_DashboardCountItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.w,
        mainAxisSpacing: 10.h,
        childAspectRatio: 2.05,
      ),
      itemBuilder: (context, index) => _dashboardCountCard(items[index]),
    );
  }

  Widget _dashboardCountCard(_DashboardCountItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [item.startColor, item.endColor],
          ),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: item.endColor.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(item.icon, color: Colors.white, size: 22.sp),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '${item.count}',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 19.sp,
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

  Widget _miniKpi(String title, String value, {double? titleHeight}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: titleHeight,
            child: Align(
              alignment: Alignment.topRight,
              child: Text(
                title,
                maxLines: titleHeight == null ? null : 2,
                overflow: titleHeight == null ? null : TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.sp,
                ),
              ),
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniKpiRows3(
    List<_MiniKpiCellData> items, {
    double? titleHeight,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 3) {
      final chunk = items.skip(i).take(3).toList(growable: false);
      rows.add(
        Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              Expanded(
                child: index < chunk.length
                    ? _miniKpi(
                        chunk[index].title,
                        chunk[index].value,
                        titleHeight: titleHeight,
                      )
                    : const SizedBox.shrink(),
              ),
              if (index < 2) SizedBox(width: 8.w),
            ],
          ],
        ),
      );
      if (i + 3 < items.length) {
        rows.add(SizedBox(height: 8.h));
      }
    }

    return Column(
      children: rows,
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11.sp,
        ),
      ),
    );
  }

  Widget _line(String title, String value, {bool muted = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.h),
      child: Row(
        children: [
          Text(
            '$title: ',
            style: GoogleFonts.cairo(
              color: muted ? Colors.white54 : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: muted ? Colors.white54 : Colors.white,
                fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _officeInfoLine(String title, String value, {bool muted = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132.w,
            child: Text(
              '$title:',
              style: GoogleFonts.cairo(
                color: muted ? Colors.white54 : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: GoogleFonts.cairo(
                color: muted ? Colors.white54 : Colors.white,
                fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: GoogleFonts.cairo(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 15.sp,
      ),
    );
  }

  Widget _fieldButton({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.r),
          color: const Color(0xFF111827),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Text(
              '$title: ',
              style: GoogleFonts.cairo(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.event_rounded, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _dialogLine(String k, String v, {bool strong = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$k: ',
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lightDialogHeader({
    required String title,
    required VoidCallback? onCancel,
    required VoidCallback? onSave,
    bool submitting = false,
  }) {
    return SizedBox(
      height: 42.h,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onCancel,
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Text(
              title,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 16.sp,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSave,
              child: submitting
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'حفظ',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _lightInfoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _lightDialogLine(String k, String v, {bool strong = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$k: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerBankAccountCard({
    required OwnerBankAccountRecord account,
    required VoidCallback onCopyAccountNumber,
    VoidCallback? onCopyIban,
  }) {
    final hasIban = account.iban.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_rounded,
                color: Color(0xFF475569),
                size: 18,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  account.bankName,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 14.sp,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _bankAccountValueLine('رقم الحساب', account.accountNumber),
          if (hasIban) ...[
            SizedBox(height: 8.h),
            _bankAccountValueLine('رقم الآيبان', account.iban),
          ],
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              OutlinedButton.icon(
                onPressed: onCopyAccountNumber,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(
                  'نسخ رقم الحساب',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasIban && onCopyIban != null)
                OutlinedButton.icon(
                  onPressed: onCopyIban,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 10.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(
                    'نسخ الآيبان',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bankAccountValueLine(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            fontSize: 11.sp,
          ),
        ),
        SizedBox(height: 4.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _lightFieldButton({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    value,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.event_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _lightDialogInputDeco(
    String label, {
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFFFFFFFF),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  List<Widget> _dropdownSelectedItems<T>(
    List<DropdownMenuItem<T?>> items, {
    required Color textColor,
  }) {
    return items.map((item) {
      final child = item.child;
      if (child is Text) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            child.data ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: child.style ??
                GoogleFonts.cairo(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: child,
      );
    }).toList(growable: false);
  }

  Widget _lightDropdownField<T>({
    required String title,
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T?>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 320.h,
      borderRadius: BorderRadius.circular(14.r),
      dropdownColor: Colors.white,
      style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
      iconEnabledColor: const Color(0xFF64748B),
      decoration: _lightDialogInputDeco(title),
      items: items,
      selectedItemBuilder: (_) => _dropdownSelectedItems(
        items,
        textColor: const Color(0xFF0F172A),
      ),
      onChanged: onChanged,
    );
  }

  InputDecoration _dialogInputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(10.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white54),
        borderRadius: BorderRadius.circular(10.r),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String title,
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T?>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 320.h,
      borderRadius: BorderRadius.circular(14.r),
      dropdownColor: const Color(0xFF0B1220),
      style: GoogleFonts.cairo(color: Colors.white),
      iconEnabledColor: Colors.white70,
      decoration: InputDecoration(
        labelText: title,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(10.r),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white54),
          borderRadius: BorderRadius.circular(10.r),
        ),
      ),
      items: items,
      selectedItemBuilder: (_) => _dropdownSelectedItems(
        items,
        textColor: Colors.white,
      ),
      onChanged: onChanged,
    );
  }

  Widget _voucherOperationSelectorField<T>({
    required String title,
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    if (value is! _VoucherOperationFilter) {
      return _dropdownField<T>(
        title: title,
        value: value,
        items: items,
        onChanged: onChanged,
      );
    }
    final current = value;
    final accentColor = _voucherOperationFilterAccentColor(current);
    return InkWell(
      onTap: () async {
        final selected = await _showVoucherOperationFilterSheet(current);
        if (selected == null) return;
        onChanged(selected as T);
      },
      borderRadius: BorderRadius.circular(10.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: accentColor.withOpacity(0.55)),
        ),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                _voucherOperationFilterIcon(current),
                color: Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      color: Colors.white70,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    current.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            const Icon(
              Icons.unfold_more_rounded,
              color: Colors.white70,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<_VoucherOperationFilter?> _showVoucherOperationFilterSheet(
    _VoucherOperationFilter current,
  ) {
    return showModalBottomSheet<_VoucherOperationFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        return SafeArea(
          child: SizedBox(
            height: media.size.height * 0.72,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44.w,
                      height: 5.h,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 14.h),
                  _sectionTitle('اختيار نوع العملية'),
                  SizedBox(height: 6.h),
                  Text(
                    'اختر نوع العملية المناسبة لتصفية السندات. هذه النافذة مهيأة لتبقى مريحة ومنظمة على الشاشات الصغيرة.',
                    style: GoogleFonts.cairo(
                      color: Colors.white60,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _VoucherOperationFilter.values.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
                      itemBuilder: (sheetContext, index) {
                        final option = _VoucherOperationFilter.values[index];
                        final isSelected = option == current;
                        final accentColor =
                            _voucherOperationFilterAccentColor(option);
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(sheetContext).pop(option),
                            borderRadius: BorderRadius.circular(14.r),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 11.h,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentColor.withOpacity(0.14)
                                    : const Color(0xFF111827),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                  color: isSelected
                                      ? accentColor
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40.w,
                                    height: 40.w,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Icon(
                                      _voucherOperationFilterIcon(option),
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.sp,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.chevron_left_rounded,
                                    color: isSelected
                                        ? accentColor
                                        : Colors.white38,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _voucherOperationFilterIcon(_VoucherOperationFilter filter) {
    switch (filter) {
      case _VoucherOperationFilter.all:
        return Icons.tune_rounded;
      case _VoucherOperationFilter.rentReceipt:
        return Icons.receipt_long_rounded;
      case _VoucherOperationFilter.officeCommission:
        return Icons.account_balance_wallet_rounded;
      case _VoucherOperationFilter.officeExpense:
        return Icons.request_quote_rounded;
      case _VoucherOperationFilter.officeWithdrawal:
        return Icons.sync_alt_rounded;
      case _VoucherOperationFilter.ownerPayout:
        return Icons.person_rounded;
      case _VoucherOperationFilter.ownerAdjustment:
        return Icons.rule_folder_rounded;
      case _VoucherOperationFilter.elevatorMaintenance:
        return Icons.apartment_rounded;
      case _VoucherOperationFilter.buildingCleaning:
        return Icons.cleaning_services_rounded;
      case _VoucherOperationFilter.waterServices:
        return Icons.water_drop_rounded;
      case _VoucherOperationFilter.contractWaterInstallment:
        return Icons.opacity_rounded;
      case _VoucherOperationFilter.internetServices:
        return Icons.wifi_rounded;
      case _VoucherOperationFilter.electricityServices:
        return Icons.bolt_rounded;
      case _VoucherOperationFilter.other:
        return Icons.category_rounded;
    }
  }

  Color _voucherOperationFilterAccentColor(_VoucherOperationFilter filter) {
    switch (filter) {
      case _VoucherOperationFilter.all:
        return const Color(0xFF475569);
      case _VoucherOperationFilter.rentReceipt:
        return const Color(0xFF0F766E);
      case _VoucherOperationFilter.officeCommission:
        return const Color(0xFF7C3AED);
      case _VoucherOperationFilter.officeExpense:
        return const Color(0xFF9A3412);
      case _VoucherOperationFilter.officeWithdrawal:
        return const Color(0xFF0D9488);
      case _VoucherOperationFilter.ownerPayout:
        return const Color(0xFF0D9488);
      case _VoucherOperationFilter.ownerAdjustment:
        return const Color(0xFFEA580C);
      case _VoucherOperationFilter.elevatorMaintenance:
        return const Color(0xFFBE185D);
      case _VoucherOperationFilter.buildingCleaning:
        return const Color(0xFF0369A1);
      case _VoucherOperationFilter.waterServices:
        return const Color(0xFF0284C7);
      case _VoucherOperationFilter.contractWaterInstallment:
        return const Color(0xFF0891B2);
      case _VoucherOperationFilter.internetServices:
        return const Color(0xFF059669);
      case _VoucherOperationFilter.electricityServices:
        return const Color(0xFFD97706);
      case _VoucherOperationFilter.other:
        return const Color(0xFF64748B);
    }
  }

  Color _stateColor(VoucherState state) {
    switch (state) {
      case VoucherState.draft:
        return const Color(0xFF9A3412);
      case VoucherState.posted:
        return const Color(0xFF166534);
      case VoucherState.cancelled:
        return const Color(0xFF7F1D1D);
      case VoucherState.reversed:
        return const Color(0xFF0F766E);
    }
  }

  String _serviceTypeAr(String type) {
    switch (type) {
      case 'water':
        return 'المياه';
      case 'electricity':
        return 'الكهرباء';
      case 'internet':
        return 'الإنترنت';
      case 'cleaning':
        return 'النظافة';
      case 'elevator':
        return 'المصعد';
      case 'maintenance':
        return 'الخدمات';
      default:
        return 'أخرى';
    }
  }

  String _money(num v) => v.toStringAsFixed(2);

  String _normalizeVoucherServiceText(String raw) {
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

  bool _looksLikeGeneratedServiceVoucherText(String raw) {
    final note = _normalizeVoucherServiceText(raw);
    if (note.isEmpty) return false;
    if (note.contains('[service]') || note.contains('[shared_service_office:')) {
      return true;
    }
    final hasServiceToken = _voucherServiceTypeTokenFromText(raw) != null;
    if (!hasServiceToken) return false;
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
        note.contains('العقار:');
  }

  bool _isServiceVoucher(VoucherReportItem voucher) {
    return voucher.source == VoucherSource.services ||
        voucher.source == VoucherSource.maintenance ||
        voucher.isServiceInvoice ||
        _looksLikeGeneratedServiceVoucherText(voucher.note);
  }

  String? _voucherServiceTypeTokenFromText(String raw) {
    final note = _normalizeVoucherServiceText(raw);
    if (note.isEmpty) return null;

    if (note.contains('[shared_service_office: water]') ||
        note.contains('type=water')) {
      return 'water';
    }
    if (note.contains('[shared_service_office: electricity]') ||
        note.contains('type=electricity')) {
      return 'electricity';
    }
    if (note.contains('type=internet')) return 'internet';
    if (note.contains('type=cleaning')) return 'cleaning';
    if (note.contains('type=elevator')) return 'elevator';

    if (note.contains('صيانه مصعد') ||
        note.contains('طلب صيانه مصعد') ||
        note.contains('مصعد') ||
        note.contains('اسانسير') ||
        note.contains('elevator')) {
      return 'elevator';
    }
    if (note.contains('نظافه') || note.contains('cleaning')) {
      return 'cleaning';
    }
    if (note.contains('خدمه انترنت') ||
        note.contains('طلب تجديد خدمه انترنت') ||
        note.contains('خدمات انترنت') ||
        note.contains('الانترنت') ||
        note.contains('انترنت') ||
        note.contains('internet')) {
      return 'internet';
    }
    if (note.contains('خدمه كهرباء مشترك') ||
        note.contains('فاتوره كهرباء مشترك') ||
        note.contains('تحصيل خدمه كهرباء مشترك') ||
        note.contains('سداد خدمه كهرباء مشترك') ||
        note.contains('خدمات كهرباء') ||
        note.contains('كهرباء مشترك') ||
        note.contains('electricity') ||
        note.contains('electric') ||
        note.contains('كهرب')) {
      return 'electricity';
    }
    if (note.contains('خدمه مياه مشترك') ||
        note.contains('فاتوره مياه مشترك') ||
        note.contains('تحصيل خدمه مياه مشترك') ||
        note.contains('سداد خدمه مياه مشترك') ||
        note.contains('خدمات مياه') ||
        note.contains('مياه مشترك') ||
        note.contains('water') ||
        note.contains('مياه') ||
        note.contains('ماء')) {
      return 'water';
    }

    return null;
  }

  _VoucherOperationFilter? _voucherServiceOperationFromText(String raw) {
    switch (_voucherServiceTypeTokenFromText(raw)) {
      case 'elevator':
        return _VoucherOperationFilter.elevatorMaintenance;
      case 'cleaning':
        return _VoucherOperationFilter.buildingCleaning;
      case 'internet':
        return _VoucherOperationFilter.internetServices;
      case 'water':
        return _VoucherOperationFilter.waterServices;
      case 'electricity':
        return _VoucherOperationFilter.electricityServices;
      default:
        return null;
    }
  }

  bool _isContractWaterInstallmentVoucher(VoucherReportItem v) {
    if (v.source != VoucherSource.contracts) return false;
    final cleanNote = _cleanVoucherReportNote(v.note);
    return RegExp(
      r'مياه\s*\(قسط\)\s*:',
      caseSensitive: false,
    ).hasMatch(cleanNote);
  }

  bool _matchesVoucherOperationFilter(
    VoucherReportItem v,
    _VoucherOperationFilter filter,
  ) {
    if (filter == _VoucherOperationFilter.all) return true;
    if (filter == _VoucherOperationFilter.contractWaterInstallment) {
      return _isContractWaterInstallmentVoucher(v);
    }
    return _voucherOperationOf(v) == filter;
  }

  _VoucherOperationFilter _voucherOperationOf(VoucherReportItem v) {
    switch (v.source) {
      case VoucherSource.contracts:
        return _VoucherOperationFilter.rentReceipt;
      case VoucherSource.officeCommission:
        return _VoucherOperationFilter.officeCommission;
      case VoucherSource.services:
      case VoucherSource.maintenance:
        return _voucherServiceOperationFromText(v.note) ??
            _VoucherOperationFilter.other;
      case VoucherSource.officeWithdrawal:
        return _VoucherOperationFilter.officeWithdrawal;
      case VoucherSource.ownerPayout:
        return _VoucherOperationFilter.ownerPayout;
      case VoucherSource.ownerAdjustment:
        return _VoucherOperationFilter.ownerAdjustment;
      case VoucherSource.manual:
      case VoucherSource.other:
        final note = v.note.toLowerCase();
        final serviceOperation = _voucherServiceOperationFromText(v.note);
        if (serviceOperation != null && _isServiceVoucher(v)) {
          return serviceOperation;
        }
        if (note.contains('مصروف إداري للمكتب') ||
            note.contains('مصروف مكتب')) {
          return _VoucherOperationFilter.officeExpense;
        }
        if (note.contains('مقبوض للمكتب')) {
          return _VoucherOperationFilter.other;
        }
        if (note.contains('تحويل من رصيد المكتب') ||
            note.contains('سحب من رصيد المكتب')) {
          return _VoucherOperationFilter.officeWithdrawal;
        }
        return _VoucherOperationFilter.other;
    }
  }

  _VoucherOperationFilter _voucherServiceOperationFilter(VoucherReportItem v) {
    return _voucherServiceOperationFromText(v.note) ??
        _VoucherOperationFilter.other;
  }

  String _voucherCustomServiceOperationLabel(VoucherReportItem v) {
    final cleanNote = _cleanVoucherReportNote(v.note);
    if (cleanNote.isEmpty) return 'عملية أخرى';
    final firstLine = cleanNote
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return 'عملية أخرى';
    final beforePropertyRef = firstLine.split('•').first.trim();
    final normalized = beforePropertyRef
        .replaceFirst(RegExp(r'^خدمات\s*-\s*'), '')
        .trim();
    return normalized.isEmpty ? 'عملية أخرى' : normalized;
  }

  String _voucherServiceOperationLabel(VoucherReportItem v) {
    switch (_voucherServiceOperationFilter(v)) {
      case _VoucherOperationFilter.elevatorMaintenance:
        return 'صيانة مصعد';
      case _VoucherOperationFilter.buildingCleaning:
        return 'نظافة عمارة';
      case _VoucherOperationFilter.waterServices:
        return 'خدمات مياه';
      case _VoucherOperationFilter.internetServices:
        return 'خدمات إنترنت';
      case _VoucherOperationFilter.electricityServices:
        return 'خدمات كهرباء';
      default:
        return _voucherCustomServiceOperationLabel(v);
    }
  }

  String _voucherContractOperationLabel(VoucherReportItem v) {
    final note = _cleanVoucherReportNote(v.note).toLowerCase();
    if (note.contains('سداد مقدم عقد')) {
      return 'سداد مقدم عقد';
    }
    if (_isContractWaterInstallmentVoucher(v)) {
      return 'دفعة إيجار تشمل مياه مقطوعة';
    }
    return 'دفعة إيجار';
  }

  String _voucherManualTitle(String note) {
    final match = RegExp(r'\[TITLE:(.*?)\]', caseSensitive: false)
        .firstMatch(note);
    return (match?.group(1) ?? '').trim();
  }

  String? _voucherManualMarkerValue(String note, String key) {
    final match = RegExp('\\[$key:(.*?)\\]', caseSensitive: false)
        .firstMatch(note);
    final value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String _voucherOperationLabel(VoucherReportItem v) {
    switch (_voucherOperationOf(v)) {
      case _VoucherOperationFilter.all:
        return 'كل العمليات';
      case _VoucherOperationFilter.rentReceipt:
        return _voucherContractOperationLabel(v);
      case _VoucherOperationFilter.officeCommission:
        return 'عمولة مكتب';
      case _VoucherOperationFilter.officeExpense:
        return 'مصروف مكتب';
      case _VoucherOperationFilter.officeWithdrawal:
        return 'تحويل من رصيد المكتب';
      case _VoucherOperationFilter.ownerPayout:
        return 'تحويل للمالك';
      case _VoucherOperationFilter.ownerAdjustment:
        return 'خصم/تسوية للمالك';
      case _VoucherOperationFilter.elevatorMaintenance:
      case _VoucherOperationFilter.buildingCleaning:
      case _VoucherOperationFilter.waterServices:
      case _VoucherOperationFilter.internetServices:
      case _VoucherOperationFilter.electricityServices:
        return _voucherServiceOperationLabel(v);
      case _VoucherOperationFilter.contractWaterInstallment:
        return 'مياه مقطوعة من العقد';
      case _VoucherOperationFilter.other:
        if (_isServiceVoucher(v)) {
          return _voucherCustomServiceOperationLabel(v);
        }
        final title = _voucherManualTitle(v.note);
        if (title.isNotEmpty) return title;
        final cleanNote = _cleanVoucherReportNote(v.note);
        final firstLine = cleanNote
            .split('\n')
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        return firstLine.isNotEmpty ? firstLine : 'عملية أخرى';
    }
  }

  Color _voucherOperationColor(VoucherReportItem v) {
    switch (_voucherOperationOf(v)) {
      case _VoucherOperationFilter.rentReceipt:
        return const Color(0xFF0F766E);
      case _VoucherOperationFilter.officeCommission:
        return const Color(0xFF7C3AED);
      case _VoucherOperationFilter.officeExpense:
        return const Color(0xFF9A3412);
      case _VoucherOperationFilter.officeWithdrawal:
        return const Color(0xFF0D9488);
      case _VoucherOperationFilter.ownerPayout:
        return const Color(0xFF0D9488);
      case _VoucherOperationFilter.ownerAdjustment:
        return const Color(0xFFEA580C);
      case _VoucherOperationFilter.elevatorMaintenance:
        return const Color(0xFFBE185D);
      case _VoucherOperationFilter.buildingCleaning:
        return const Color(0xFF0369A1);
      case _VoucherOperationFilter.waterServices:
        return const Color(0xFF0284C7);
      case _VoucherOperationFilter.contractWaterInstallment:
        return const Color(0xFF0891B2);
      case _VoucherOperationFilter.internetServices:
        return const Color(0xFF059669);
      case _VoucherOperationFilter.electricityServices:
        return const Color(0xFFD97706);
      case _VoucherOperationFilter.other:
      case _VoucherOperationFilter.all:
        return const Color(0xFF475569);
    }
  }

  String _voucherPropertyLabel(
    VoucherReportItem v,
    ComprehensiveReportSnapshot data,
  ) {
    final propertyId = v.propertyId.trim();
    if (propertyId.isEmpty) return '-';
    return data.propertyNames[propertyId] ?? propertyId;
  }

  String _voucherContractLabel(
    VoucherReportItem v,
    ComprehensiveReportSnapshot data,
  ) {
    final contractId = v.contractId.trim();
    if (contractId.isEmpty) return '-';
    return data.contractNumbers[contractId] ?? contractId;
  }

  String _voucherPartyLabel(
    VoucherReportItem v,
    ComprehensiveReportSnapshot data,
  ) {
    if (v.source == VoucherSource.manual || v.source == VoucherSource.other) {
      final partyId = v.tenantId.trim();
      if (partyId.isNotEmpty) {
        return data.tenantNames[partyId] ??
            data.ownerNames[partyId] ??
            partyId;
      }
      final partyName = _voucherManualMarkerValue(v.note, 'PARTY');
      if (partyName != null) return partyName;
    }
    switch (v.source) {
      case VoucherSource.contracts:
        final tenantId = v.tenantId.trim();
        if (tenantId.isEmpty) return '-';
        return data.tenantNames[tenantId] ?? tenantId;
      case VoucherSource.ownerPayout:
      case VoucherSource.ownerAdjustment:
        final ownerId = v.tenantId.trim();
        if (ownerId.isEmpty) return 'المالك';
        return data.ownerNames[ownerId] ??
            data.tenantNames[ownerId] ??
            ownerId;
      case VoucherSource.officeWithdrawal:
      case VoucherSource.officeCommission:
      case VoucherSource.manual:
      case VoucherSource.other:
        return 'المكتب';
      case VoucherSource.services:
      case VoucherSource.maintenance:
        final serviceTenantId = v.tenantId.trim();
        if (serviceTenantId.isNotEmpty) {
          return data.tenantNames[serviceTenantId] ?? serviceTenantId;
        }
        final partyName = _voucherManualMarkerValue(v.note, 'PARTY');
        if (partyName != null) return partyName;
        return '-';
    }
  }

  String _cleanVoucherReportNote(String note) {
    final raw = note.trim();
    if (raw.isEmpty) return '';
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) {
          if (line.isEmpty) return false;
          final lower = line.toLowerCase();
          return lower != '[manual]' &&
              !lower.startsWith('[shared_service_office:') &&
              !lower.startsWith('[party:') &&
              !lower.startsWith('[party_id:') &&
              !lower.startsWith('[property:') &&
              !lower.startsWith('[property_id:') &&
              !lower.startsWith('[title:') &&
              !lower.startsWith('[commission_mode:') &&
              !lower.startsWith('[commission_value:') &&
              !lower.startsWith('[commission_amount:') &&
              !lower.startsWith('[owner_payout]') &&
              !lower.startsWith('[owner_adjustment]') &&
              !lower.startsWith('[office_commission]') &&
              !lower.startsWith('[office_withdrawal]') &&
              !lower.startsWith('[service]') &&
              !lower.startsWith('[owner_payout_id:') &&
              !lower.startsWith('[owner_adjustment_id:') &&
              !lower.startsWith('[owner_adjustment_category:') &&
              !lower.startsWith('[contract_voucher_id:') &&
              !lower.startsWith('[posted]') &&
              !lower.startsWith('[cancelled]') &&
              !lower.startsWith('[reversal]') &&
              !lower.startsWith('[reversed]');
        })
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  String _normalizeVoucherText(String value) {
    return value
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  String _trimVoucherReasonPrefix(String title, String line) {
    final rawTitle = title.trim();
    final rawLine = line.trim();
    if (rawTitle.isEmpty || rawLine.isEmpty) return rawLine;

    final prefixes = <String>[
      '$rawTitle - ',
      '$rawTitle – ',
      '$rawTitle: ',
      '$rawTitle • ',
      'خدمات - $rawTitle',
    ];

    for (final prefix in prefixes) {
      if (rawLine.startsWith(prefix)) {
        return rawLine.substring(prefix.length).trim();
      }
    }

    return rawLine;
  }

  String _voucherDisplayReason(VoucherReportItem v) {
    final cleanNote = _cleanVoucherReportNote(v.note);
    if (cleanNote.isEmpty) return '';

    final title = _voucherOperationLabel(v);
    final normalizedTitle = _normalizeVoucherText(title);
    final lines = cleanNote
        .split('\n')
        .map((line) => _trimVoucherReasonPrefix(title, line))
        .where((line) => line.isNotEmpty)
        .where((line) {
          final normalizedLine = _normalizeVoucherText(line);
          if (normalizedLine.isEmpty) return false;
          if (normalizedLine == normalizedTitle) return false;
          final withoutGenericPrefix =
              normalizedLine.replaceFirst(RegExp(r'^خدمات\s*-\s*'), '');
          return withoutGenericPrefix != normalizedTitle;
        })
        .toList(growable: false);

    return lines.join(' • ').trim();
  }

  String _voucherReportStateText(VoucherReportItem v) {
    if (v.state == VoucherState.cancelled) return 'السند ملغي';
    if (v.state == VoucherState.reversed) return 'السند معكوس';
    return 'فتح السند';
  }

  Color _voucherReportActionColor(VoucherReportItem v) {
    if (v.state == VoucherState.cancelled) return const Color(0xFFF87171);
    if (v.state == VoucherState.reversed) return const Color(0xFF93C5FD);
    return Colors.white;
  }

  IconData _voucherReportActionIcon(VoucherReportItem v) {
    if (v.state == VoucherState.cancelled) return Icons.block_rounded;
    if (v.state == VoucherState.reversed) return Icons.undo_rounded;
    return Icons.receipt_long_rounded;
  }

  String _voucherReportSubtitle(
    VoucherReportItem v,
    ComprehensiveReportSnapshot data,
  ) {
    final amountLine =
        '${v.direction == VoucherDirection.receipt ? 'المبلغ المقبوض' : 'المبلغ المصروف'} ${_money(v.amount)}';
    final reason = _voucherDisplayReason(v);
    if (reason.isEmpty) return amountLine;
    return '$reason\n$amountLine';
  }

  Widget _voucherReportTile(
    VoucherReportItem v,
    ComprehensiveReportSnapshot data,
  ) {
    final isCancelledVoucher = v.state == VoucherState.cancelled;
    final isReversedVoucher = v.state == VoucherState.reversed;
    final actionText = _voucherReportStateText(v);
    final actionColor = _voucherReportActionColor(v);
    final actionIcon = _voucherReportActionIcon(v);

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isCancelledVoucher
            ? const Color(0x1AF87171)
            : (isReversedVoucher
                ? const Color(0x1A93C5FD)
                : const Color(0x12000000)),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isCancelledVoucher
              ? const Color(0x55F87171)
              : (isReversedVoucher
                  ? const Color(0x5593C5FD)
                  : Colors.white12),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        trailing: TextButton.icon(
          onPressed: () => _openVoucherFromReports(v.id),
          icon: Icon(
            actionIcon,
            size: 16,
            color: actionColor,
          ),
          label: Text(
            actionText,
            style: GoogleFonts.cairo(
              color: actionColor,
              fontWeight: FontWeight.w700,
              fontSize: 11.sp,
            ),
          ),
        ),
        title: Text(
          '${_fmtDate(v.date) ?? '-'} • ${_voucherOperationLabel(v)}',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Text(
            _voucherReportSubtitle(v, data),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              color: Colors.white60,
              fontSize: 11.sp,
            ),
          ),
        ),
      ),
    );
  }

  String? _fmtDate(DateTime? d) {
    if (d == null) return null;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openVoucherFromReports(String voucherId) async {
    final normalizedVoucherId = voucherId.trim();
    if (normalizedVoucherId.isEmpty) {
      _showSnack('لا يوجد سند مرتبط بهذه الحركة');
      return;
    }
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) {
      await HiveService.ensureReportsBoxesOpen();
    }
    if (!mounted) return;
    final invoicesBox = Hive.box<Invoice>(boxName(kInvoicesBox));
    final invoice = invoicesBox.get(normalizedVoucherId);
    if (invoice == null) {
      _showSnack('تعذر العثور على السند المطلوب.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(invoice: invoice),
      ),
    );
  }

  List<OwnerLedgerEntry> _visibleOwnerLedgerEntries(
    List<OwnerLedgerEntry> entries,
  ) {
    return entries
        .where((entry) => !_hiddenOwnerLedgerEntryIds.contains(entry.id))
        .toList(growable: false);
  }

  void _hideCancelledOwnerLedgerEntry(OwnerLedgerEntry entry) {
    if (_hiddenOwnerLedgerEntryIds.contains(entry.id)) return;
    _setStateSafely(() {
      _hiddenOwnerLedgerEntryIds.add(entry.id);
    });
    _showSnack('تم إخفاء الحركة المرتبطة بالسند الملغي من كشف الحركات.');
  }

  double _ownerLedgerAmountValue(OwnerLedgerEntry entry) {
    return entry.credit > 0 ? entry.credit : entry.debit;
  }

  String _ownerLedgerAmountLabel(OwnerLedgerEntry entry) {
    switch (entry.type) {
      case 'rent':
        return 'المبلغ المحصل';
      case 'commission':
        return 'العمولة المخصومة';
      case 'expense':
        return 'المبلغ المصروف';
      case 'payout':
        return 'المبلغ المحول';
      case 'adjustment':
        return 'المبلغ المخصوم';
      default:
        return 'المبلغ';
    }
  }

  String _ownerLedgerSubtitle(OwnerLedgerEntry entry) {
    return '${_ownerLedgerAmountLabel(entry)} ${_money(_ownerLedgerAmountValue(entry))} | '
        'الرصيد بعد الحركة ${_money(entry.balanceAfter)}';
  }

  double _officeLedgerAmountValue(OfficeLedgerEntry entry) {
    return entry.credit > 0 ? entry.credit : entry.debit;
  }

  String _officeLedgerAmountLabel(OfficeLedgerEntry entry) {
    switch (entry.type) {
      case 'commission':
        return 'العمولة المحصلة';
      case 'receipt':
        return 'المبلغ المقبوض';
      case 'expense':
        return 'المبلغ المصروف';
      case 'withdrawal':
        return 'المبلغ المحول';
      default:
        return 'المبلغ';
    }
  }

  String _officeLedgerSubtitle(OfficeLedgerEntry entry) {
    return '${_officeLedgerAmountLabel(entry)} ${_money(_officeLedgerAmountValue(entry))} | '
        'الرصيد بعد الحركة ${_money(entry.balanceAfter)}';
  }

  Widget _officeLedgerTile(OfficeLedgerEntry entry) {
    final hasVoucher = entry.referenceId.trim().isNotEmpty;
    final voucherState = entry.voucherState;
    final isCancelledVoucher = voucherState == VoucherState.cancelled;
    final isReversedVoucher = voucherState == VoucherState.reversed;
    final actionText = isCancelledVoucher
        ? 'السند ملغي'
        : (isReversedVoucher ? 'السند معكوس' : 'فتح السند');
    final actionColor = isCancelledVoucher
        ? const Color(0xFFF87171)
        : (isReversedVoucher
            ? const Color(0xFF93C5FD)
            : Colors.white);
    final actionIcon = isCancelledVoucher
        ? Icons.block_rounded
        : (isReversedVoucher
            ? Icons.undo_rounded
            : Icons.receipt_long_rounded);
    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isCancelledVoucher
            ? const Color(0x1AF87171)
            : (isReversedVoucher
                ? const Color(0x1A93C5FD)
                : const Color(0x12000000)),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isCancelledVoucher
              ? const Color(0x55F87171)
              : (isReversedVoucher
                  ? const Color(0x5593C5FD)
                  : Colors.white12),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        trailing: hasVoucher
            ? TextButton.icon(
                onPressed: () => _openVoucherFromReports(entry.referenceId),
                icon: Icon(
                  actionIcon,
                  size: 16,
                  color: actionColor,
                ),
                label: Text(
                  actionText,
                  style: GoogleFonts.cairo(
                    color: actionColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.sp,
                  ),
                ),
              )
            : null,
        title: Text(
          '${_fmtDate(entry.date) ?? '-'} • ${entry.description}',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _officeLedgerSubtitle(entry),
          style: GoogleFonts.cairo(
            color: Colors.white60,
            fontSize: 11.sp,
          ),
        ),
      ),
    );
  }

  Widget _ownerLedgerTile(OwnerLedgerEntry entry) {
    final hasVoucher = entry.referenceId.trim().isNotEmpty;
    final voucherState = entry.voucherState;
    final isCancelledVoucher = voucherState == VoucherState.cancelled;
    final isReversedVoucher = voucherState == VoucherState.reversed;
    final actionText = isCancelledVoucher
        ? 'السند ملغي'
        : (isReversedVoucher ? 'السند معكوس' : 'فتح السند');
    final actionColor = isCancelledVoucher
        ? const Color(0xFFF87171)
        : (isReversedVoucher
            ? const Color(0xFF93C5FD)
            : Colors.white);
    final actionIcon = isCancelledVoucher
        ? Icons.block_rounded
        : (isReversedVoucher
            ? Icons.undo_rounded
            : Icons.receipt_long_rounded);

    final tile = Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isCancelledVoucher
            ? const Color(0x1AF87171)
            : const Color(0x12000000),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isCancelledVoucher
              ? const Color(0x55F87171)
              : Colors.white12,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        trailing: hasVoucher
            ? TextButton.icon(
                onPressed: () => _openVoucherFromReports(entry.referenceId),
                icon: Icon(actionIcon, size: 16, color: actionColor),
                label: Text(
                  actionText,
                  style: GoogleFonts.cairo(
                    color: actionColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.sp,
                  ),
                ),
              )
            : null,
        title: Text(
          '${_fmtDate(entry.date) ?? '-'} • ${entry.description}',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _ownerLedgerSubtitle(entry),
          style: GoogleFonts.cairo(
            color: Colors.white60,
            fontSize: 11.sp,
          ),
        ),
      ),
    );

    if (!isCancelledVoucher) {
      return tile;
    }

    return Dismissible(
      key: ValueKey('owner_ledger_${entry.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _hideCancelledOwnerLedgerEntry(entry),
      background: Container(
        margin: EdgeInsets.only(bottom: 6.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0xFF7F1D1D),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_off_rounded, color: Colors.white),
            SizedBox(width: 8.w),
            Text(
              'إخفاء من الكشف',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: tile,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    _runAfterBuildComplete(() {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
      );
    });
  }
}

class _OfficeVoucherScreen extends StatefulWidget {
  final OfficeReportSummary office;
  final bool isExpense;
  final Future<void> Function({
    required double amount,
    required DateTime transactionDate,
    required String note,
  }) onSubmit;

  const _OfficeVoucherScreen({
    required this.office,
    required this.isExpense,
    required this.onSubmit,
  });

  @override
  State<_OfficeVoucherScreen> createState() => _OfficeVoucherScreenState();
}

class _OfficeVoucherScreenState extends State<_OfficeVoucherScreen>
    with WidgetsBindingObserver {
  static const double _maxVoucherAmount = 500000000;
  static const int _maxNoteLength = 150;
  static const String _amountLimitMessage = 'الحد الأقصى 500,000,000';
  static const String _noteLimitMessage = 'الحد الأقصى 150 حرفًا';

  late final TextEditingController _amountCtl;
  late final TextEditingController _noteCtl;
  final FocusNode _noteFocusNode = FocusNode();
  final GlobalKey _noteFieldKey = GlobalKey();
  late DateTime _transactionDate;
  bool _submitting = false;
  bool _pendingNoteVisibilitySync = false;
  String? _formError;
  String? _amountError;
  String? _noteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amountCtl = TextEditingController();
    _noteCtl = TextEditingController();
    _transactionDate = KsaTime.now();
    _noteFocusNode.addListener(_handleNoteFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteFocusNode.removeListener(_handleNoteFocusChanged);
    _noteFocusNode.dispose();
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_noteFocusNode.hasFocus || !_pendingNoteVisibilitySync) return;
    _pendingNoteVisibilitySync = false;
    _ensureNoteFieldVisible();
  }

  String get _title =>
      widget.isExpense ? 'تسجيل مصروف مكتب' : 'تسجيل إيراد العمولات';

  String get _summaryLabel => widget.isExpense
      ? 'إجمالي مصروفات المكتب الحالية'
      : 'إجمالي إيراد العمولات الحالي';

  double get _summaryValue => widget.isExpense
      ? widget.office.officeExpenses
      : widget.office.commissionRevenue;

  String get _amountLabel => widget.isExpense
      ? 'مبلغ المصروف'
      : 'مبلغ العمولة';

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2000),
      lastDate: KsaTime.today(),
    );
    if (picked == null || !mounted) return;
    setState(() => _transactionDate = picked);
  }

  void _dismiss([bool? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _handleNoteFocusChanged() {
    if (!_noteFocusNode.hasFocus) {
      _pendingNoteVisibilitySync = false;
      return;
    }
    _pendingNoteVisibilitySync = true;
    if (!mounted) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      _pendingNoteVisibilitySync = false;
      _ensureNoteFieldVisible();
    }
  }

  void _ensureNoteFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_noteFocusNode.hasFocus) return;
      final fieldContext = _noteFieldKey.currentContext;
      if (fieldContext == null) return;
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.86,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() {
        _amountError = 'أدخل مبلغًا صحيحًا';
        _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
      });
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        amount: amount,
        transactionDate: _transactionDate,
        note: _noteCtl.text.trim(),
      );
      if (!mounted) return;
      _dismiss(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _submitting = false;
      });
    }
  }

  String _money(num value) => value.toStringAsFixed(2);

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showAmountLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _amountError = _amountLimitMessage;
        _formError = null;
      });
    });
  }

  void _showNoteLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _noteError = _noteLimitMessage;
        _formError = null;
      });
    });
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _infoLine(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _chooseDate,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ التسجيل',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _fmtDate(_transactionDate),
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.event_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width >= 900 ? 24.w : 16.w;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final actionBarHeight = 64.h;

    return WillPopScope(
      onWillPop: () async {
        if (_submitting) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _submitting ? null : () => _dismiss(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            _title,
            style: GoogleFonts.cairo(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 17.sp,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              bottomInset + actionBarHeight + 28.h,
            ),
            children: [
              _infoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine('الجهة', 'المكتب'),
                    SizedBox(height: 6.h),
                    Text(
                      _summaryLabel,
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(_summaryValue),
                        textDirection: TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_formError != null) ...[
                SizedBox(height: 12.h),
                _errorBanner(_formError!),
              ],
              SizedBox(height: 12.h),
              TextField(
                controller: _amountCtl,
                scrollPadding: EdgeInsets.only(
                  bottom: actionBarHeight + 12.h,
                ),
                inputFormatters: [
                  _VoucherAmountLimitInputFormatter(
                    maxAmount: _maxVoucherAmount,
                    onExceeded: _showAmountLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
                    _amountError = amount <= 0 ? 'أدخل مبلغًا صحيحًا' : null;
                  });
                },
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                textDirection: TextDirection.ltr,
                decoration: _inputDeco(
                  _amountLabel,
                  errorText: _amountError,
                ),
              ),
              SizedBox(height: 10.h),
              _dateField(),
              SizedBox(height: 10.h),
              TextField(
                key: _noteFieldKey,
                controller: _noteCtl,
                focusNode: _noteFocusNode,
                scrollPadding: EdgeInsets.only(
                  bottom: actionBarHeight + 16.h,
                ),
                inputFormatters: [
                  _TextLengthLimitFormatter(
                    maxLength: _maxNoteLength,
                    onExceeded: _showNoteLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    _noteError = null;
                  });
                },
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                maxLines: 3,
                decoration: _inputDeco(
                  'ملاحظات',
                  errorText: _noteError,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomInset + 16.h,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _dismiss(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      backgroundColor: Colors.white,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w800,
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
}

class _OfficeWithdrawalScreen extends StatefulWidget {
  final OfficeSettlementPreview preview;
  final Future<void> Function({
    required double amount,
    required DateTime transferDate,
    required String note,
  }) onSubmit;

  const _OfficeWithdrawalScreen({
    required this.preview,
    required this.onSubmit,
  });

  @override
  State<_OfficeWithdrawalScreen> createState() => _OfficeWithdrawalScreenState();
}

class _OfficeWithdrawalScreenState extends State<_OfficeWithdrawalScreen>
    with WidgetsBindingObserver {
  static const double _maxVoucherAmount = 500000000;
  static const int _maxNoteLength = 150;
  static const String _amountLimitMessage = 'الحد الأقصى 500,000,000';
  static const String _noteLimitMessage = 'الحد الأقصى 150 حرفًا';

  late final TextEditingController _amountCtl;
  late final TextEditingController _noteCtl;
  final FocusNode _noteFocusNode = FocusNode();
  final GlobalKey _noteFieldKey = GlobalKey();
  late DateTime _transferDate;
  bool _submitting = false;
  bool _pendingNoteVisibilitySync = false;
  String? _formError;
  String? _amountError;
  String? _noteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final readyAmount = widget.preview.readyForWithdrawal <= _maxVoucherAmount
        ? widget.preview.readyForWithdrawal
        : _maxVoucherAmount;
    _amountCtl = TextEditingController(
      text: readyAmount > 0 ? readyAmount.toStringAsFixed(2) : '',
    );
    _noteCtl = TextEditingController();
    _transferDate = KsaTime.now();
    _noteFocusNode.addListener(_handleNoteFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteFocusNode.removeListener(_handleNoteFocusChanged);
    _noteFocusNode.dispose();
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_noteFocusNode.hasFocus || !_pendingNoteVisibilitySync) return;
    _pendingNoteVisibilitySync = false;
    _ensureNoteFieldVisible();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate,
      firstDate: DateTime(2000),
      lastDate: KsaTime.today(),
    );
    if (picked == null || !mounted) return;
    setState(() => _transferDate = picked);
  }

  void _dismiss([bool? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _handleNoteFocusChanged() {
    if (!_noteFocusNode.hasFocus) {
      _pendingNoteVisibilitySync = false;
      return;
    }
    _pendingNoteVisibilitySync = true;
    if (!mounted) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      _pendingNoteVisibilitySync = false;
      _ensureNoteFieldVisible();
    }
  }

  void _ensureNoteFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_noteFocusNode.hasFocus) return;
      final fieldContext = _noteFieldKey.currentContext;
      if (fieldContext == null) return;
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.86,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  String? _validateAmount(double amount) {
    if (amount <= 0) {
      return 'أدخل مبلغًا صحيحًا';
    }
    if (amount > _maxVoucherAmount) {
      return _amountLimitMessage;
    }
    if (amount > widget.preview.readyForWithdrawal + 0.000001) {
      return 'المبلغ يتجاوز الرصيد القابل للتحويل (${_money(widget.preview.readyForWithdrawal)})';
    }
    return null;
  }

  double get _amountInputCap {
    final available = widget.preview.readyForWithdrawal;
    if (available <= 0) return 0;
    return available < _maxVoucherAmount ? available : _maxVoucherAmount;
  }

  String get _amountExceededMessage {
    if (widget.preview.readyForWithdrawal <= _maxVoucherAmount) {
      return 'المبلغ يتجاوز الرصيد القابل للتحويل (${_money(widget.preview.readyForWithdrawal)})';
    }
    return _amountLimitMessage;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
    final amountError = _validateAmount(amount);
    if (amountError != null) {
      setState(() {
        _amountError = amountError;
        _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
      });
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        amount: amount,
        transferDate: _transferDate,
        note: _noteCtl.text.trim(),
      );
      if (!mounted) return;
      _dismiss(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _submitting = false;
      });
    }
  }

  String _money(num value) => value.toStringAsFixed(2);

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showAmountLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _amountError = _amountExceededMessage;
        _formError = null;
      });
    });
  }

  void _showNoteLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _noteError = _noteLimitMessage;
        _formError = null;
      });
    });
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _infoLine(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _chooseDate,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ التحويل',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _fmtDate(_transferDate),
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.event_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.of(context).size.width >= 900 ? 24.w : 16.w;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final actionBarHeight = 64.h;

    return WillPopScope(
      onWillPop: () async {
        if (_submitting) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _submitting ? null : () => _dismiss(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            'تحويل الآن للمكتب',
            style: GoogleFonts.cairo(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 17.sp,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              bottomInset + actionBarHeight + 28.h,
            ),
            children: [
              _infoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine('الجهة', 'المكتب'),
                    _infoLine('صافي ربح المكتب', _money(widget.preview.netProfit)),
                    _infoLine(
                      'إجمالي سحوبات المكتب',
                      _money(widget.preview.previousWithdrawals),
                    ),
                    _infoLine(
                      'المتبقي من ربح المكتب',
                      _money(widget.preview.currentBalance),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'الرصيد القابل للتحويل',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(widget.preview.readyForWithdrawal),
                        textDirection: TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_formError != null) ...[
                SizedBox(height: 12.h),
                _errorBanner(_formError!),
              ],
              SizedBox(height: 12.h),
              TextField(
                controller: _amountCtl,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 12.h),
                inputFormatters: [
                  _VoucherAmountLimitInputFormatter(
                    maxAmount: _amountInputCap,
                    onExceeded: _showAmountLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
                    _amountError = _validateAmount(amount);
                  });
                },
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                textDirection: TextDirection.ltr,
                decoration: _inputDeco(
                  'مبلغ التحويل',
                  errorText: _amountError,
                ),
              ),
              SizedBox(height: 10.h),
              _dateField(),
              SizedBox(height: 10.h),
              TextField(
                key: _noteFieldKey,
                controller: _noteCtl,
                focusNode: _noteFocusNode,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                inputFormatters: [
                  _TextLengthLimitFormatter(
                    maxLength: _maxNoteLength,
                    onExceeded: _showNoteLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    _noteError = null;
                  });
                },
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                maxLines: 3,
                decoration: _inputDeco(
                  'ملاحظات',
                  errorText: _noteError,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomInset + 16.h,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _dismiss(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      backgroundColor: Colors.white,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w800,
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
}

class _OwnerPayoutScreen extends StatefulWidget {
  final OwnerReportItem owner;
  final OwnerSettlementPreview preview;
  final Future<void> Function({
    required double amount,
    required DateTime transferDate,
    required String note,
  }) onSubmit;

  const _OwnerPayoutScreen({
    required this.owner,
    required this.preview,
    required this.onSubmit,
  });

  @override
  State<_OwnerPayoutScreen> createState() => _OwnerPayoutScreenState();
}

class _OwnerPayoutScreenState extends State<_OwnerPayoutScreen>
    with WidgetsBindingObserver {
  static const double _maxVoucherAmount = 500000000;
  static const int _maxNoteLength = 150;
  static const String _amountLimitMessage = 'الحد الأقصى 500,000,000';
  static const String _noteLimitMessage = 'الحد الأقصى 150 حرفًا';

  late final TextEditingController _amountCtl;
  late final TextEditingController _noteCtl;
  final FocusNode _noteFocusNode = FocusNode();
  final GlobalKey _noteFieldKey = GlobalKey();
  late DateTime _transferDate;
  bool _submitting = false;
  bool _pendingNoteVisibilitySync = false;
  String? _formError;
  String? _amountError;
  String? _noteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final readyAmount = widget.preview.readyForPayout <= _maxVoucherAmount
        ? widget.preview.readyForPayout
        : _maxVoucherAmount;
    _amountCtl = TextEditingController(
      text: readyAmount > 0 ? readyAmount.toStringAsFixed(2) : '',
    );
    _noteCtl = TextEditingController();
    _transferDate = KsaTime.now();
    _noteFocusNode.addListener(_handleNoteFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteFocusNode.removeListener(_handleNoteFocusChanged);
    _noteFocusNode.dispose();
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_noteFocusNode.hasFocus || !_pendingNoteVisibilitySync) return;
    _pendingNoteVisibilitySync = false;
    _ensureNoteFieldVisible();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate,
      firstDate: DateTime(2000),
      lastDate: KsaTime.today(),
    );
    if (picked == null || !mounted) return;
    setState(() => _transferDate = picked);
  }

  void _dismiss([bool? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _handleNoteFocusChanged() {
    if (!_noteFocusNode.hasFocus) {
      _pendingNoteVisibilitySync = false;
      return;
    }
    _pendingNoteVisibilitySync = true;
    if (!mounted) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      _pendingNoteVisibilitySync = false;
      _ensureNoteFieldVisible();
    }
  }

  void _ensureNoteFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_noteFocusNode.hasFocus) return;
      final fieldContext = _noteFieldKey.currentContext;
      if (fieldContext == null) return;
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.86,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  String? _validateAmount(double amount) {
    if (amount <= 0) {
      return 'أدخل مبلغًا صحيحًا';
    }
    if (amount > _maxVoucherAmount) {
      return _amountLimitMessage;
    }
    if (amount > widget.preview.readyForPayout + 0.000001) {
      return 'المبلغ يتجاوز الرصيد القابل للتحويل (${_money(widget.preview.readyForPayout)})';
    }
    return null;
  }

  double get _amountInputCap {
    final available = widget.preview.readyForPayout;
    if (available <= 0) return 0;
    return available < _maxVoucherAmount ? available : _maxVoucherAmount;
  }

  String get _amountExceededMessage {
    if (widget.preview.readyForPayout <= _maxVoucherAmount) {
      return 'المبلغ يتجاوز الرصيد القابل للتحويل (${_money(widget.preview.readyForPayout)})';
    }
    return _amountLimitMessage;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
    final amountError = _validateAmount(amount);
    if (amountError != null) {
      setState(() {
        _amountError = amountError;
        _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
      });
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        amount: amount,
        transferDate: _transferDate,
        note: _noteCtl.text.trim(),
      );
      if (!mounted) return;
      _dismiss(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _submitting = false;
      });
    }
  }

  String _money(num value) => value.toStringAsFixed(2);

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showAmountLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _amountError = _amountExceededMessage;
        _formError = null;
      });
    });
  }

  void _showNoteLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _noteError = _noteLimitMessage;
        _formError = null;
      });
    });
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _infoLine(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _chooseDate,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ التحويل',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _fmtDate(_transferDate),
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.event_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.of(context).size.width >= 900 ? 24.w : 16.w;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final actionBarHeight = 64.h;

    return WillPopScope(
      onWillPop: () async {
        if (_submitting) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _submitting ? null : () => _dismiss(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            'تحويل الآن للمالك',
            style: GoogleFonts.cairo(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 17.sp,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              bottomInset + actionBarHeight + 28.h,
            ),
            children: [
              _infoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine('المالك', widget.owner.ownerName),
                    SizedBox(height: 6.h),
                    Text(
                      'الرصيد القابل للتحويل',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(widget.preview.readyForPayout),
                        textDirection: TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_formError != null) ...[
                SizedBox(height: 12.h),
                _errorBanner(_formError!),
              ],
              SizedBox(height: 12.h),
              TextField(
                controller: _amountCtl,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 12.h),
                inputFormatters: [
                  _VoucherAmountLimitInputFormatter(
                    maxAmount: _amountInputCap,
                    onExceeded: _showAmountLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
                    _amountError = _validateAmount(amount);
                  });
                },
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                textDirection: TextDirection.ltr,
                decoration: _inputDeco(
                  'مبلغ التحويل',
                  errorText: _amountError,
                ),
              ),
              SizedBox(height: 10.h),
              _dateField(),
              SizedBox(height: 10.h),
              TextField(
                key: _noteFieldKey,
                controller: _noteCtl,
                focusNode: _noteFocusNode,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                inputFormatters: [
                  _TextLengthLimitFormatter(
                    maxLength: _maxNoteLength,
                    onExceeded: _showNoteLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    _noteError = null;
                  });
                },
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                maxLines: 3,
                decoration: _inputDeco(
                  'ملاحظات',
                  errorText: _noteError,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomInset + 16.h,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _dismiss(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      backgroundColor: Colors.white,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w800,
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
}

class _OwnerAdjustmentScreen extends StatefulWidget {
  final OwnerReportItem owner;
  final OwnerSettlementPreview preview;
  final Future<void> Function({
    required OwnerAdjustmentCategory category,
    required double amount,
    required DateTime adjustmentDate,
    required String note,
  }) onSubmit;

  const _OwnerAdjustmentScreen({
    required this.owner,
    required this.preview,
    required this.onSubmit,
  });

  @override
  State<_OwnerAdjustmentScreen> createState() => _OwnerAdjustmentScreenState();
}

class _OwnerAdjustmentScreenState extends State<_OwnerAdjustmentScreen>
    with WidgetsBindingObserver {
  static const double _maxVoucherAmount = 500000000;
  static const int _maxNoteLength = 150;
  static const String _amountLimitMessage = 'الحد الأقصى 500,000,000';
  static const String _noteLimitMessage = 'الحد الأقصى 150 حرفًا';

  late final TextEditingController _amountCtl;
  late final TextEditingController _noteCtl;
  final FocusNode _noteFocusNode = FocusNode();
  final GlobalKey _noteFieldKey = GlobalKey();
  late DateTime _adjustmentDate;
  OwnerAdjustmentCategory _category = OwnerAdjustmentCategory.ownerDiscount;
  bool _submitting = false;
  bool _pendingNoteVisibilitySync = false;
  String? _formError;
  String? _amountError;
  String? _noteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amountCtl = TextEditingController();
    _noteCtl = TextEditingController();
    _adjustmentDate = KsaTime.now();
    _noteFocusNode.addListener(_handleNoteFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteFocusNode.removeListener(_handleNoteFocusChanged);
    _noteFocusNode.dispose();
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_noteFocusNode.hasFocus || !_pendingNoteVisibilitySync) return;
    _pendingNoteVisibilitySync = false;
    _ensureNoteFieldVisible();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _adjustmentDate,
      firstDate: DateTime(2000),
      lastDate: KsaTime.today(),
    );
    if (picked == null || !mounted) return;
    setState(() => _adjustmentDate = picked);
  }

  void _dismiss([bool? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _handleNoteFocusChanged() {
    if (!_noteFocusNode.hasFocus) {
      _pendingNoteVisibilitySync = false;
      return;
    }
    _pendingNoteVisibilitySync = true;
    if (!mounted) return;
    if (MediaQuery.of(context).viewInsets.bottom > 0) {
      _pendingNoteVisibilitySync = false;
      _ensureNoteFieldVisible();
    }
  }

  void _ensureNoteFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_noteFocusNode.hasFocus) return;
      final fieldContext = _noteFieldKey.currentContext;
      if (fieldContext == null) return;
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.86,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  String? _validateAmount(double amount) {
    if (amount <= 0) {
      return 'أدخل مبلغًا صحيحًا';
    }
    if (amount > _maxVoucherAmount) {
      return _amountLimitMessage;
    }
    if (amount > widget.preview.readyForPayout + 0.000001) {
      return 'المبلغ يتجاوز الرصيد القابل للتطبيق (${_money(widget.preview.readyForPayout)})';
    }
    return null;
  }

  double get _amountInputCap {
    final available = widget.preview.readyForPayout;
    if (available <= 0) return 0;
    return available < _maxVoucherAmount ? available : _maxVoucherAmount;
  }

  String get _amountExceededMessage {
    if (widget.preview.readyForPayout <= _maxVoucherAmount) {
      return 'المبلغ يتجاوز الرصيد القابل للتطبيق (${_money(widget.preview.readyForPayout)})';
    }
    return _amountLimitMessage;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
    final amountError = _validateAmount(amount);
    if (amountError != null) {
      setState(() {
        _amountError = amountError;
        _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
      });
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        category: _category,
        amount: amount,
        adjustmentDate: _adjustmentDate,
        note: _noteCtl.text.trim(),
      );
      if (!mounted) return;
      _dismiss(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _submitting = false;
      });
    }
  }

  String _money(num value) => value.toStringAsFixed(2);

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showAmountLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _amountError = _amountExceededMessage;
        _formError = null;
      });
    });
  }

  void _showNoteLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _noteError = _noteLimitMessage;
        _formError = null;
      });
    });
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _infoLine(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _chooseDate,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ التسجيل',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _fmtDate(_adjustmentDate),
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.event_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.of(context).size.width >= 900 ? 24.w : 16.w;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final actionBarHeight = 64.h;

    return WillPopScope(
      onWillPop: () async {
        if (_submitting) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _submitting ? null : () => _dismiss(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            'تسجيل خصم للمالك',
            style: GoogleFonts.cairo(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 17.sp,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              bottomInset + actionBarHeight + 28.h,
            ),
            children: [
              _infoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine('المالك', widget.owner.ownerName),
                    SizedBox(height: 6.h),
                    Text(
                      'الرصيد المتاح قبل الخصم',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(widget.preview.readyForPayout),
                        textDirection: TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_formError != null) ...[
                SizedBox(height: 12.h),
                _errorBanner(_formError!),
              ],
              SizedBox(height: 12.h),
              DropdownButtonFormField<OwnerAdjustmentCategory>(
                initialValue: _category,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                iconEnabledColor: const Color(0xFF64748B),
                decoration: _inputDeco('نوع الخصم'),
                items: OwnerAdjustmentCategory.values
                    .map(
                      (category) =>
                          DropdownMenuItem<OwnerAdjustmentCategory>(
                        value: category,
                        child: Text(category.arLabel),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _category = value;
                    _formError = null;
                  });
                },
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: _amountCtl,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 12.h),
                inputFormatters: [
                  _VoucherAmountLimitInputFormatter(
                    maxAmount: _amountInputCap,
                    onExceeded: _showAmountLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    final amount = double.tryParse(_amountCtl.text.trim()) ?? 0;
                    _amountError = _validateAmount(amount);
                  });
                },
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                textDirection: TextDirection.ltr,
                decoration: _inputDeco(
                  'مبلغ الخصم',
                  errorText: _amountError,
                ),
              ),
              SizedBox(height: 10.h),
              _dateField(),
              SizedBox(height: 10.h),
              TextField(
                key: _noteFieldKey,
                controller: _noteCtl,
                focusNode: _noteFocusNode,
                scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                inputFormatters: [
                  _TextLengthLimitFormatter(
                    maxLength: _maxNoteLength,
                    onExceeded: _showNoteLimitError,
                  ),
                ],
                onChanged: (_) {
                  setState(() {
                    _formError = null;
                    _noteError = null;
                  });
                },
                style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                maxLines: 3,
                decoration: _inputDeco(
                  'ملاحظات',
                  errorText: _noteError,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomInset + 16.h,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _dismiss(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      backgroundColor: Colors.white,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: Size(0, 48.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w800,
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
}

class _OwnerBankAccountsScreen extends StatefulWidget {
  final OwnerReportItem owner;

  const _OwnerBankAccountsScreen({required this.owner});

  @override
  State<_OwnerBankAccountsScreen> createState() =>
      _OwnerBankAccountsScreenState();
}

class _OwnerBankAccountsScreenState extends State<_OwnerBankAccountsScreen> {
  late final TextEditingController _bankCtl;
  late final TextEditingController _accountCtl;
  late final TextEditingController _ibanCtl;
  List<OwnerBankAccountRecord> _accounts = const [];
  bool _loading = true;
  bool _submitting = false;
  bool _showAddForm = false;
  String? _screenError;
  String? _formError;
  String? _bankError;
  String? _accountError;
  String? _ibanError;
  String? _copyNotice;
  String? _editingAccountId;
  Timer? _copyNoticeTimer;

  bool get _isEditing => _editingAccountId != null;

  @override
  void initState() {
    super.initState();
    _bankCtl = TextEditingController();
    _accountCtl = TextEditingController();
    _ibanCtl = TextEditingController();
    _loadAccounts();
  }

  @override
  void dispose() {
    _copyNoticeTimer?.cancel();
    _bankCtl.dispose();
    _accountCtl.dispose();
    _ibanCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _screenError = null;
      });
    }
    try {
      final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
        widget.owner.ownerId,
      );
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
        _screenError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _screenError = e.toString();
      });
    }
  }

  String? _validateMaxLength(String value, int max, String label) {
    if (value.length >= max) {
      return '$label وصل إلى الحد الأقصى $max';
    }
    return null;
  }

  void _resetAddForm() {
    _bankCtl.clear();
    _accountCtl.clear();
    _ibanCtl.clear();
    _formError = null;
    _bankError = null;
    _accountError = null;
    _ibanError = null;
    _submitting = false;
    _editingAccountId = null;
  }

  void _updateFieldErrors({bool includeRequired = false}) {
    final bankName = _bankCtl.text.trim();
    final accountNumber = _accountCtl.text.trim();
    final iban = _ibanCtl.text.trim();

    _bankError = includeRequired && bankName.isEmpty
        ? 'اسم البنك مطلوب'
        : _validateMaxLength(bankName, 30, 'اسم البنك');
    _accountError = includeRequired && accountNumber.isEmpty
        ? 'رقم الحساب مطلوب'
        : _validateMaxLength(accountNumber, 40, 'رقم الحساب');
    _ibanError = _validateMaxLength(iban, 40, 'رقم الآيبان');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.cairo())),
    );
  }

  Future<void> _copyValue(String value, String successMessage) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) return;
    _copyNoticeTimer?.cancel();
    setState(() {
      _copyNotice = successMessage;
    });
    _copyNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copyNotice = null;
      });
    });
  }

  void _enterAddMode() {
    setState(() {
      _resetAddForm();
      _showAddForm = true;
      _copyNotice = null;
      _screenError = null;
    });
  }

  void _enterEditMode(OwnerBankAccountRecord account) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _resetAddForm();
      _bankCtl.text = account.bankName;
      _accountCtl.text = account.accountNumber;
      _ibanCtl.text = account.iban;
      _editingAccountId = account.id;
      _showAddForm = true;
      _copyNotice = null;
      _screenError = null;
    });
  }

  void _exitAddMode() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _resetAddForm();
      _showAddForm = false;
    });
  }

  Future<void> _saveAccount() async {
    final editingAccountId = _editingAccountId;
    setState(() {
      _updateFieldErrors(includeRequired: true);
      final hasErrors =
          _bankError != null || _accountError != null || _ibanError != null;
      _formError =
          hasErrors ? 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.' : null;
    });

    if (_formError != null) return;

    setState(() => _submitting = true);
    try {
      if (editingAccountId == null) {
        await ComprehensiveReportsService.addOwnerBankAccount(
          ownerId: widget.owner.ownerId,
          ownerName: widget.owner.ownerName,
          bankName: _bankCtl.text.trim(),
          accountNumber: _accountCtl.text.trim(),
          iban: _ibanCtl.text.trim(),
        );
      } else {
        await ComprehensiveReportsService.updateOwnerBankAccount(
          accountId: editingAccountId,
          ownerId: widget.owner.ownerId,
          ownerName: widget.owner.ownerName,
          bankName: _bankCtl.text.trim(),
          accountNumber: _accountCtl.text.trim(),
          iban: _ibanCtl.text.trim(),
        );
      }
      final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
        widget.owner.ownerId,
      );
      if (!mounted) return;
      _showSnack(
        editingAccountId == null
            ? 'تم حفظ الحساب البنكي'
            : 'تم تحديث الحساب البنكي',
      );
      setState(() {
        _accounts = accounts;
        _screenError = null;
        _copyNotice = null;
        _resetAddForm();
        _showAddForm = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.toString();
        _submitting = false;
      });
    }
  }

  Future<void> _deleteAccount(OwnerBankAccountRecord account) async {
    if (_submitting) return;

    final confirmed = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف هذا الحساب البنكي؟',
      confirmLabel: 'تأكيد',
      cancelLabel: 'تراجع',
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ComprehensiveReportsService.deleteOwnerBankAccount(
        accountId: account.id,
        ownerId: widget.owner.ownerId,
      );
      final accounts = await ComprehensiveReportsService.loadOwnerBankAccounts(
        widget.owner.ownerId,
      );
      if (!mounted) return;
      _showSnack('تم حذف الحساب البنكي');
      setState(() {
        _accounts = accounts;
        _screenError = null;
        _copyNotice = null;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _screenError = e.toString();
        _submitting = false;
      });
    }
  }

  Future<bool> _handleBack() async {
    if (_submitting) return false;
    if (_showAddForm) {
      _exitAddMode();
      return false;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    return true;
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _successBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.cairo(
          color: const Color(0xFF166534),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _infoLine(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.cairo(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountActionIcon({
    required IconData icon,
    required String tooltip,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? const Color(0xFFE2E8F0) : backgroundColor,
        borderRadius: BorderRadius.circular(10.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: 34.w,
            height: 34.w,
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }

  Widget _accountCard({
    required OwnerBankAccountRecord account,
    required VoidCallback onCopyAccountNumber,
    VoidCallback? onCopyIban,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final hasIban = account.iban.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_rounded,
                color: Color(0xFF475569),
                size: 18,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  account.bankName,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 14.sp,
                  ),
                ),
              ),
              EntityAuditInfoButton(
                collectionName: 'ownerBankAccounts',
                entityId: account.id,
                preferLocalFirst: true,
                color: const Color(0xFF475569),
              ),
              SizedBox(width: 4.w),
              _accountActionIcon(
                icon: Icons.edit_rounded,
                tooltip: 'تعديل الحساب',
                iconColor: const Color(0xFF0D9488),
                backgroundColor: const Color(0xFFDBEAFE),
                onTap: _submitting ? null : onEdit,
              ),
              SizedBox(width: 4.w),
              _accountActionIcon(
                icon: Icons.delete_rounded,
                tooltip: 'حذف الحساب',
                iconColor: const Color(0xFFB91C1C),
                backgroundColor: const Color(0xFFFEE2E2),
                onTap: _submitting ? null : onDelete,
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _accountValueLine('رقم الحساب', account.accountNumber),
          if (hasIban) ...[
            SizedBox(height: 8.h),
            _accountValueLine('رقم الآيبان', account.iban),
          ],
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              OutlinedButton.icon(
                onPressed: onCopyAccountNumber,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(
                  'نسخ رقم الحساب',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasIban && onCopyIban != null)
                OutlinedButton.icon(
                  onPressed: onCopyIban,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 10.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(
                    'نسخ الآيبان',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountValueLine(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            fontSize: 11.sp,
          ),
        ),
        SizedBox(height: 4.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.of(context).size.width >= 900 ? 24.w : 16.w;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final actionBarHeight = 64.h;

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _submitting
                ? null
                : () async {
                    final shouldPop = await _handleBack();
                    if (!mounted || !shouldPop) return;
                    Navigator.of(context).pop();
                  },
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          title: Text(
            _showAddForm
                ? (_isEditing ? 'تعديل الحساب البنكي' : 'إضافة حساب جديد')
                : 'الحسابات البنكية',
            style: GoogleFonts.cairo(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 17.sp,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              bottomInset + (_showAddForm ? actionBarHeight + 28.h : 24.h),
            ),
            children: [
              _infoCard(
                child: _infoLine('المالك', widget.owner.ownerName),
              ),
              if (_showAddForm) ...[
                if (_formError != null) ...[
                  SizedBox(height: 12.h),
                  _errorBanner(_formError!),
                ],
                SizedBox(height: 12.h),
                TextField(
                  controller: _bankCtl,
                  scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                  onChanged: (_) {
                    setState(() {
                      _formError = null;
                      _updateFieldErrors();
                    });
                  },
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(30),
                  ],
                  style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                  textInputAction: TextInputAction.next,
                  decoration: _inputDeco(
                    'اسم البنك',
                    errorText: _bankError,
                  ),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _accountCtl,
                  scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                  onChanged: (_) {
                    setState(() {
                      _formError = null;
                      _updateFieldErrors();
                    });
                  },
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(40),
                  ],
                  style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDeco(
                    'رقم الحساب',
                    errorText: _accountError,
                  ),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _ibanCtl,
                  scrollPadding: EdgeInsets.only(bottom: actionBarHeight + 16.h),
                  onChanged: (_) {
                    setState(() {
                      _formError = null;
                      _updateFieldErrors();
                    });
                  },
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(40),
                  ],
                  style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.text,
                  decoration: _inputDeco(
                    'رقم الآيبان (اختياري)',
                    errorText: _ibanError,
                  ),
                ),
              ] else ...[
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'الحسابات المحفوظة',
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _enterAddMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE0F2FE),
                        foregroundColor: const Color(0xFF0C4A6E),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 10.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        'إضافة جديد',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                if (_screenError != null) ...[
                  _errorBanner(_screenError!),
                  SizedBox(height: 10.h),
                ],
                if (_loading)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.h),
                      child: const CircularProgressIndicator(),
                    ),
                  )
                else if (_accounts.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'لا توجد حسابات بنكية محفوظة حتى الآن.',
                      style: GoogleFonts.cairo(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ..._accounts.map((account) {
                    return _accountCard(
                      account: account,
                      onCopyAccountNumber: () => _copyValue(
                        account.accountNumber,
                        'تم نسخ رقم الحساب',
                      ),
                      onEdit: () => _enterEditMode(account),
                      onDelete: () => _deleteAccount(account),
                      onCopyIban: account.iban.trim().isEmpty
                          ? null
                          : () => _copyValue(
                                account.iban,
                                'تم نسخ رقم الآيبان',
                              ),
                    );
                  }),
                if (_copyNotice != null) ...[
                  SizedBox(height: 12.h),
                  _successBanner(_copyNotice!),
                ],
              ],
            ],
          ),
        ),
        bottomNavigationBar: _showAddForm
            ? AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  bottomInset + 16.h,
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : _exitAddMode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            backgroundColor: Colors.white,
                            minimumSize: Size(0, 48.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _saveAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: Size(0, 48.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: _submitting
                              ? SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditing ? 'حفظ التعديل' : 'حفظ',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _CommissionRuleDialogResult {
  final CommissionMode mode;
  final double value;

  const _CommissionRuleDialogResult({
    required this.mode,
    required this.value,
  });
}

class _CommissionRuleDialog extends StatefulWidget {
  final CommissionMode initialMode;
  final double initialValue;

  const _CommissionRuleDialog({
    required this.initialMode,
    required this.initialValue,
  });

  @override
  State<_CommissionRuleDialog> createState() => _CommissionRuleDialogState();
}

class _CommissionRuleDialogState extends State<_CommissionRuleDialog> {
  static const double _maxPercent = 100;
  static const String _percentLimitMessage =
      'النسبة لا يمكن أن تتجاوز 100%';

  late CommissionMode _mode;
  late final TextEditingController _valueCtl;
  String? _formError;
  String? _valueError;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    final initialPercent = widget.initialValue < 0
        ? 0.0
        : (widget.initialValue > _maxPercent
            ? _maxPercent
            : widget.initialValue);
    _valueCtl = TextEditingController(
      text: initialPercent.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _valueCtl.dispose();
    super.dispose();
  }

  void _dismiss([_CommissionRuleDialogResult? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  void _showPercentLimitError() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _valueError = _percentLimitMessage;
        _formError = null;
      });
    });
  }

  Future<void> _save() async {
    double value = 0;
    if (_mode == CommissionMode.percent) {
      final raw = _valueCtl.text.trim();
      final parsed = double.tryParse(raw);
      if (raw.isEmpty || parsed == null || parsed < 0) {
        setState(() {
          _valueError = 'أدخل نسبة صحيحة';
          _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
        });
        return;
      }
      if (parsed > _maxPercent) {
        setState(() {
          _valueError = _percentLimitMessage;
          _formError = 'تحقق من الحقول المحددة باللون الأحمر قبل الحفظ.';
        });
        return;
      }
      value = parsed;
    }

    _dismiss(_CommissionRuleDialogResult(mode: _mode, value: value));
  }

  Future<bool> _handleBack() async {
    _dismiss();
    return false;
  }

  InputDecoration _inputDeco(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: const Color(0xFF64748B)),
      errorText: errorText,
      errorStyle: GoogleFonts.cairo(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(
        message,
        style: GoogleFonts.cairo(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actionsAlignment: MainAxisAlignment.center,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ضبط عمولة المكتب',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 6.w),
              EntityAuditInfoButton(
                collectionName: 'financeConfig',
                entityId: 'commission::global',
                preferLocalFirst: true,
                color: const Color(0xFF475569),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: 28.w,
                  height: 28.w,
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 440.w,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<CommissionMode>(
                  initialValue: _mode,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: const Color(0xFF0F172A)),
                  iconEnabledColor: const Color(0xFF64748B),
                  decoration: _inputDeco('نوع العمولة'),
                  items: CommissionMode.values
                      .map(
                        (mode) => DropdownMenuItem<CommissionMode>(
                          value: mode,
                          child: Text(mode.arLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _mode = value;
                      _formError = null;
                      _valueError = null;
                    });
                  },
                ),
                SizedBox(height: 10.h),
                if (_mode == CommissionMode.percent) ...[
                  if (_formError != null) ...[
                    _errorBanner(_formError!),
                    SizedBox(height: 10.h),
                  ],
                  TextField(
                    controller: _valueCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      _PercentageLimitInputFormatter(
                        maxValue: _maxPercent,
                        onExceeded: _showPercentLimitError,
                      ),
                    ],
                    onChanged: (_) {
                      setState(() {
                        _formError = null;
                        final text = _valueCtl.text.trim();
                        if (text.isEmpty) {
                          _valueError = null;
                          return;
                        }
                        final value = double.tryParse(text);
                        if (value == null || value < 0) {
                          _valueError = 'أدخل نسبة صحيحة';
                        } else if (value > _maxPercent) {
                          _valueError = _percentLimitMessage;
                        } else {
                          _valueError = null;
                        }
                      });
                    },
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF0F172A),
                    ),
                    textDirection: TextDirection.ltr,
                    decoration: _inputDeco(
                      'قيمة النسبة %',
                      errorText: _valueError,
                    ),
                  ),
                ] else if (_mode == CommissionMode.unspecified)
                  Text(
                    'في هذه الحالة لن يتم احتساب أي عمولة من دفعات العقود حتى يتم تحديد نظام العمولة.',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFFDC2626),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'في حالة اختيار عمولة مبلغ ثابت، يتم إدخال العمولة لاحقًا يدويًا من نافذة إيراد العمولات.',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFFDC2626),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'حفظ',
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _dismiss,
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoucherAmountLimitInputFormatter extends TextInputFormatter {
  final double maxAmount;
  final VoidCallback onExceeded;

  _VoucherAmountLimitInputFormatter({
    required this.maxAmount,
    required this.onExceeded,
  });

  static final RegExp _pattern = RegExp(r'^\d{0,9}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.trim();
    if (text.isEmpty) return newValue;

    if (!_pattern.hasMatch(text)) {
      final parts = text.split('.');
      final integerPart = parts.isNotEmpty ? parts.first : text;
      if (integerPart.length > 9) {
        onExceeded();
      }
      return oldValue;
    }

    final amount = double.tryParse(text);
    if (amount == null) {
      return oldValue;
    }

    if (amount > maxAmount) {
      onExceeded();
      return oldValue;
    }

    return newValue;
  }
}

class _PercentageLimitInputFormatter extends TextInputFormatter {
  final double maxValue;
  final VoidCallback onExceeded;

  _PercentageLimitInputFormatter({
    required this.maxValue,
    required this.onExceeded,
  });

  static final RegExp _pattern = RegExp(r'^\d{0,3}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.trim();
    if (text.isEmpty) return newValue;

    if (!_pattern.hasMatch(text)) {
      return oldValue;
    }

    final value = double.tryParse(text);
    if (value == null) {
      return oldValue;
    }

    if (value > maxValue) {
      onExceeded();
      return oldValue;
    }

    return newValue;
  }
}

class _TextLengthLimitFormatter extends TextInputFormatter {
  final int maxLength;
  final VoidCallback onExceeded;

  _TextLengthLimitFormatter({
    required this.maxLength,
    required this.onExceeded,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > maxLength) {
      onExceeded();
      return oldValue;
    }
    return newValue;
  }
}

enum _QuickRange { today, week, month }

enum _PeriodChip { all, today, week, month, custom }

enum _ContractPeriodFilter {
  all,
  daily,
  monthly,
  quarterly,
  semiAnnual,
  annual,
}

extension _ContractPeriodFilterLabel on _ContractPeriodFilter {
  String get label {
    switch (this) {
      case _ContractPeriodFilter.all:
        return 'الكل';
      case _ContractPeriodFilter.daily:
        return 'يومي';
      case _ContractPeriodFilter.monthly:
        return 'شهري';
      case _ContractPeriodFilter.quarterly:
        return 'ربع سنوي';
      case _ContractPeriodFilter.semiAnnual:
        return 'نصف سنوي';
      case _ContractPeriodFilter.annual:
        return 'سنوي';
    }
  }
}

enum _ServicePriorityFilter {
  all,
  low,
  medium,
  high,
  urgent,
}

extension _ServicePriorityFilterLabel on _ServicePriorityFilter {
  String get label {
    switch (this) {
      case _ServicePriorityFilter.all:
        return 'الكل';
      case _ServicePriorityFilter.low:
        return 'منخفضة';
      case _ServicePriorityFilter.medium:
        return 'متوسطة';
      case _ServicePriorityFilter.high:
        return 'عالية';
      case _ServicePriorityFilter.urgent:
        return 'عاجلة';
    }
  }
}

enum _VoucherStatusFilter { all, posted, cancelled }

extension _VoucherStatusFilterLabel on _VoucherStatusFilter {
  String get label {
    switch (this) {
      case _VoucherStatusFilter.all:
        return 'كل الحالات';
      case _VoucherStatusFilter.posted:
        return 'معتمد';
      case _VoucherStatusFilter.cancelled:
        return 'ملغي';
    }
  }
}

enum _VoucherDirectionFilter { all, receipts, payments }

extension _VoucherDirectionFilterLabel on _VoucherDirectionFilter {
  String get label {
    switch (this) {
      case _VoucherDirectionFilter.all:
        return 'الكل';
      case _VoucherDirectionFilter.receipts:
        return 'قبض';
      case _VoucherDirectionFilter.payments:
        return 'صرف';
    }
  }
}

enum _VoucherOperationFilter {
  all,
  rentReceipt,
  officeCommission,
  officeExpense,
  officeWithdrawal,
  ownerPayout,
  ownerAdjustment,
  elevatorMaintenance,
  buildingCleaning,
  waterServices,
  contractWaterInstallment,
  internetServices,
  electricityServices,
  other,
}

extension _VoucherOperationFilterLabel on _VoucherOperationFilter {
  String get label {
    switch (this) {
      case _VoucherOperationFilter.all:
        return 'كل العمليات';
      case _VoucherOperationFilter.rentReceipt:
        return 'سداد عقد إيجار';
      case _VoucherOperationFilter.officeCommission:
        return 'عمولة مكتب';
      case _VoucherOperationFilter.officeExpense:
        return 'مصروف مكتب';
      case _VoucherOperationFilter.officeWithdrawal:
        return 'تحويل من رصيد المكتب';
      case _VoucherOperationFilter.ownerPayout:
        return 'تحويل للمالك';
      case _VoucherOperationFilter.ownerAdjustment:
        return 'خصم/تسوية للمالك';
      case _VoucherOperationFilter.elevatorMaintenance:
        return 'صيانة مصعد';
      case _VoucherOperationFilter.buildingCleaning:
        return 'نظافة عمارة';
      case _VoucherOperationFilter.waterServices:
        return 'خدمات مياه';
      case _VoucherOperationFilter.contractWaterInstallment:
        return 'مياه مقطوعة من العقد';
      case _VoucherOperationFilter.internetServices:
        return 'خدمات إنترنت';
      case _VoucherOperationFilter.electricityServices:
        return 'خدمات كهرباء';
      case _VoucherOperationFilter.other:
        return 'عمليات أخرى';
    }
  }
}

enum _ClientTenantSubTypeFilter { all, individuals, companies }

class _MetricItem {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricItem(this.title, this.value, this.icon, this.color);
}

class _ClientReportIndicatorItem {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _ClientReportIndicatorItem({
    required this.title,
    required this.value,
    required this.onTap,
  });
}

class _PropertySelectionOption {
  final String propertyId;
  final String label;

  const _PropertySelectionOption({
    required this.propertyId,
    required this.label,
  });
}

class _PropertySelectionSheetResult {
  final String? propertyId;

  const _PropertySelectionSheetResult({required this.propertyId});
}

class _MiniKpiCellData {
  final String title;
  final String value;

  const _MiniKpiCellData({
    required this.title,
    required this.value,
  });
}

class _DashboardCountItem {
  final String title;
  final int count;
  final IconData icon;
  final Color startColor;
  final Color endColor;
  final VoidCallback? onTap; // جديد

  const _DashboardCountItem({
    required this.title,
    required this.count,
    required this.icon,
    required this.startColor,
    required this.endColor,
    this.onTap,
  });
}

class _FlowIndicatorItem {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _FlowIndicatorItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });
}

class ReportsRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/reports': (context) => const ReportsScreen(),
      };
}



