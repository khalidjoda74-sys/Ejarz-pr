// lib/ui/reports_screen.dart
// شاشة التقارير: الرئيسية + تبويبات + مخطط مالي دائري مع عرض أصفار دائماً

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show Listenable, VoidCallback;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import '../utils/contract_utils.dart';




// شاشات التنقل
import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;
import 'contracts_screen.dart' show ContractsScreen;

// عناصر الواجهة المشتركة
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// ثوابت الصناديق + تخصيص الاسم بحسب المستخدم
import '../data/constants/boxes.dart';
import '../data/services/user_scope.dart';
import 'contracts_screen.dart' show Contract;
import 'maintenance_screen.dart' show MaintenanceRequest, MaintenanceStatus;


// الوقت/التاريخ (KSA)
import '../utils/ksa_time.dart';


// موديلات وصناديق
import '../models/tenant.dart';
import '../models/property.dart';
import 'invoices_screen.dart' show Invoice; // النوع فقط، الثابت يأتي من boxes.dart

// خدمة Hive (نستخدمها هنا فقط، آمنة بدون دوران استيراد)
import '../data/services/hive_service.dart' as hs;

// أسماء صناديق افتراضية محلية (fallback فقط)
const String _kTenantsBox = 'tenantsBox';
const String _kPropertiesBox = 'propertiesBox';
const String _kContractsBox = 'contractsBox';
const String _kMaintenanceBox = 'maintenanceBox';
const String _kSessionBox = 'sessionBox';

/// Listenable خفيف كـ fallback
class _DummyListenable implements Listenable {
  const _DummyListenable();
  @override void addListener(VoidCallback listener) {}
  @override void removeListener(VoidCallback listener) {}
}

/// ====== الفلاتر / الأقسام ======
enum _ReportSection { overview, properties, tenants, contracts, invoices, maintenance }

class _ReportFilters {
  DateTime? from;
  DateTime? to;
  bool includeArchived = false;
  _ReportSection section = _ReportSection.overview;

  bool get hasDate => from != null || to != null;

  bool inRange(DateTime? d) {
    if (d == null) return true;
    if (from != null && d.isBefore(_atStartOfDay(from!))) return false;
    if (to != null && d.isAfter(_atEndOfDay(to!))) return false;
    return true;
  }

  static DateTime _atStartOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _atEndOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

/// ====== شاشة التقارير ======
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  final _filters = _ReportFilters();
  late final Future<void> _boxesReady;

  @override
  void initState() {
    super.initState();
    _boxesReady = _ensureBoxes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > .5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

Future<void> _ensureBoxes() async {
  try {
    await hs.HiveService.ensureReportsBoxesOpen();
  } catch (_) {
    // استخدم نفس أسماء HiveService هنا
    final ctrName = hs.HiveService.contractsBoxName();
    final mName   = hs.HiveService.maintenanceBoxName();

    if (!Hive.isBoxOpen(boxName(kTenantsBox)))     { await Hive.openBox<Tenant>(boxName(kTenantsBox)); }
    if (!Hive.isBoxOpen(boxName(kPropertiesBox)))  { await Hive.openBox<Property>(boxName(kPropertiesBox)); }
    if (!Hive.isBoxOpen(boxName(kInvoicesBox)))    { await Hive.openBox<Invoice>(boxName(kInvoicesBox)); }
    if (!Hive.isBoxOpen(ctrName))                  { await Hive.openBox<Contract>(ctrName); }            // ✅
    if (!Hive.isBoxOpen(mName))                    { await Hive.openBox<MaintenanceRequest>(mName); }    // ✅
    if (!Hive.isBoxOpen(boxName(kSessionBox)))     { await Hive.openBox(boxName(kSessionBox)); }
  }
}


  Box<T>? _typedBoxIfOpen<T>(String name) {
    if (!Hive.isBoxOpen(name)) return null;
    try { return Hive.box<T>(name); } catch (_) { return null; }
  }

  Box? _boxIfOpen(String name) {
    if (!Hive.isBoxOpen(name)) return null;
    try { return Hive.box(name); } catch (_) { return null; }
  }

  Box? _firstOpenBox(List<String> names) {
    for (final n in names) {
      if (Hive.isBoxOpen(n)) {
        try { return Hive.box(n); } catch (_) {}
      }
    }
    return null;
  }

  Listenable _listenOrDummy(Box? b) => b?.listenable() ?? const _DummyListenable();

  void _handleBottomTap(int i) {
    switch (i) {
      case 0: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); break;
      case 1: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen())); break;
      case 2: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const tenants_ui.TenantsScreen())); break;
      case 3: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ContractsScreen())); break;
    }
  }

  String _fmtDateGregorian(DateTime d) {
    final x = KsaTime.dateOnly(d);
    return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  bool get _useHijri {
    try {
      final box = () {
        try { return hs.HiveService.boxIfOpen(boxName(kSessionBox)); } catch (_) {}
        return _boxIfOpen(boxName(kSessionBox));
      }();
      if (box == null) return false;
      return box.get('useHijri', defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  String _fmtDateDynamic(DateTime d) {
    final dd = KsaTime.dateOnly(d);
    if (!_useHijri) return _fmtDateGregorian(dd);
    final h = HijriCalendar.fromDate(dd);
    return '${h.hYear}-${h.hMonth.toString().padLeft(2, '0')}-${h.hDay.toString().padLeft(2, '0')} هـ';
  }

  @override
  Widget build(BuildContext context) {
    final today = KsaTime.today();

    return WillPopScope(
      onWillPop: () async {
        if (_filters.section != _ReportSection.overview) {
          setState(() {
            _filters.section = _ReportSection.overview;
          });
          return false;
        }
        return true;
      },
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          
          drawer: Builder(
            builder: (ctx) {
              final media = MediaQuery.of(ctx);
              final double topInset = kToolbarHeight + media.padding.top;
              final double bottomInset = _bottomBarHeight + media.padding.bottom;
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
  // ...
  centerTitle: true,
  title: Text(
    'التقارير',
    style: GoogleFonts.cairo(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    ),
  ),
  actions: const [],
),

body: Stack(

            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight, end: Alignment.bottomLeft,
                    colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
                  ),
                ),
              ),
              Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
              Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: FutureBuilder<void>(
                    future: _boxesReady,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final merged = () {
                        try { return hs.HiveService.mergedReportsListenable(); } catch (_) {}
                        final t = _listenOrDummy(_boxIfOpen(boxName(kTenantsBox)));
                        final p = _listenOrDummy(_boxIfOpen(boxName(kPropertiesBox)));
                        final i = _listenOrDummy(_boxIfOpen(boxName(kInvoicesBox)));
final c = _listenOrDummy(() {
  try { return hs.HiveService.boxIfOpen(hs.HiveService.contractsBoxName()); } catch (_) {}
  return _firstOpenBox([hs.HiveService.contractsBoxName(), boxName(kContractsBox)]);
}());
final m = _listenOrDummy(() {
  try { return hs.HiveService.boxIfOpen(hs.HiveService.maintenanceBoxName()); } catch (_) {}
  return _firstOpenBox([hs.HiveService.maintenanceBoxName(), boxName(kMaintenanceBox)]);
}());
                        final s = _listenOrDummy(_boxIfOpen(boxName(kSessionBox)));
                        return Listenable.merge([t, p, i, c, m, s]);
                      }();

                      return AnimatedBuilder(
                        animation: merged,
                        builder: (context, _) {
                          final tenantsBox = () {
                            try { return hs.HiveService.typedBoxIfOpen<Tenant>(boxName(kTenantsBox)); } catch (_) {}
                            return _typedBoxIfOpen<Tenant>(boxName(kTenantsBox));
                          }();

                          final propsBox = () {
                            try { return hs.HiveService.typedBoxIfOpen<Property>(boxName(kPropertiesBox)); } catch (_) {}
                            return _typedBoxIfOpen<Property>(boxName(kPropertiesBox));
                          }();

                          final invBox = () {
                            try { return hs.HiveService.typedBoxIfOpen<Invoice>(boxName(kInvoicesBox)); } catch (_) {}
                            return _typedBoxIfOpen<Invoice>(boxName(kInvoicesBox));
                          }();

final ctrBox = hs.HiveService.typedBoxIfOpen<Contract>(
  hs.HiveService.contractsBoxName(),
);

final mBox = hs.HiveService.typedBoxIfOpen<MaintenanceRequest>(
  hs.HiveService.maintenanceBoxName(),
) 
?? _typedBoxIfOpen<MaintenanceRequest>(boxName(_kMaintenanceBox))
?? _boxIfOpen(hs.HiveService.maintenanceBoxName())
?? _boxIfOpen(boxName(_kMaintenanceBox));

final maintenanceItems = mBox?.values.toList() ?? [];

int total = 0;
int newCount = 0;
int inProgress = 0;
int completed = 0;
int canceled = 0; // لو حابب تحسب الملغاة

for (final m in maintenanceItems) {
  final req = m as MaintenanceRequest; // تأكيد النوع
  if (!req.isArchived) {
    total++;
    final st = req.status;

    if (st == MaintenanceStatus.open) {
      newCount++;
    } else if (st == MaintenanceStatus.inProgress) {
      inProgress++;
    } else if (st == MaintenanceStatus.completed) {
      completed++;
    } else if (st == MaintenanceStatus.canceled) {
      canceled++;
    }
  }
}



// الآن تقدر تستخدم هذه القيم في شاشة التقارير
final maintenanceTotal = total;
final maintenanceNew = newCount;
final maintenanceInProgress = inProgress;
final maintenanceDone = completed;








                          final sBox = () {
                            try { return hs.HiveService.boxIfOpen(boxName(kSessionBox)); } catch (_) {}
                            return _boxIfOpen(boxName(kSessionBox));
                          }();

                          final data = _GatheredData.collect(
                            tenantsBox, propsBox, ctrBox, invBox, mBox, sBox, _filters,
                          );

                          final header = _DarkCard(
                            padding: EdgeInsets.all(12.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  runSpacing: 8.h,
                                  spacing: 8.w,
                                  children: [
                                    
                                    _chipButton(label: 'اليوم', onTap: () => _applyQuickRange(_QuickRange.today)),
                                    _chipButton(label: 'هذا الأسبوع', onTap: () => _applyQuickRange(_QuickRange.week)),
                                    _chipButton(label: 'هذا الشهر', onTap: () => _applyQuickRange(_QuickRange.month)),
                                    _chipButton(label: 'هذا العام', onTap: () => _applyQuickRange(_QuickRange.year)),
                                  ],
                                ),
                                SizedBox(height: 10.h),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _fieldLike(
                                        context,
                                        icon: Icons.date_range,
                                        title: 'من',
                                        value: _filters.from == null ? '—' : _fmtDateDynamic(_filters.from!),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _filters.from ?? KsaTime.today(),
                                            firstDate: DateTime(2000), lastDate: DateTime(2100),
                                            builder: (_, child) => _darkDateTheme(child),
                                          );
                                          if (picked != null) {
                                            setState(() => _filters.from = DateTime(picked.year, picked.month, picked.day));
                                          }
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: _fieldLike(
                                        context,
                                        icon: Icons.event,
                                        title: 'إلى',
                                        value: _filters.to == null ? '—' : _fmtDateDynamic(_filters.to!),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _filters.to ?? KsaTime.today(),
                                            firstDate: DateTime(2000), lastDate: DateTime(2100),
                                            builder: (_, child) => _darkDateTheme(child),
                                          );
                                          if (picked != null) {
                                            setState(() => _filters.to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999));
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6.h),
                                Text('اليوم: ${_fmtDateDynamic(today)}',
                                    style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.sp)),
                              ],
                            ),
                          );

                          final financeCard = _FinanceBreakdownCard(
                            revenue: data.financeRevenue,
                            receivables: data.financeReceivables,
                            expenses: data.financeExpenses,
                            net: data.financeNet,
                          );

                          Widget body;
                          switch (_filters.section) {
                            case _ReportSection.overview:
                              body = _OverviewTab(data: data, onOpen: (sec) => setState(() => _filters.section = sec));
                              break;
                            case _ReportSection.properties:
                              body = _PropertiesTab(data: data);
                              break;
                            case _ReportSection.tenants:
                              body = _TenantsTab(data: data);
                              break;
                            case _ReportSection.contracts:
                              body = _ContractsTab(data: data);
                              break;
                            case _ReportSection.invoices:
                              body = _InvoicesTab(data: data);
                              break;
                            case _ReportSection.maintenance:
                              body = _MaintenanceTab(data: data);
                              break;
                          }

                          return ListView(
                            padding: EdgeInsets.only(bottom: 24.h),
                            children: [
                              header,
                              SizedBox(height: 12.h),
                              financeCard,
                              SizedBox(height: 12.h),
                              body,
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: AppBottomNav(key: _bottomNavKey, currentIndex: 0, onTap: _handleBottomTap),
        ),
      ),
    ),
  );
  }

  void _applyQuickRange(_QuickRange r) {
    final now = KsaTime.now();
    DateTime start;
    DateTime end;

    switch (r) {
      case _QuickRange.today:
        start = KsaTime.dateOnly(now);
        end   = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case _QuickRange.week:
        final weekday = now.weekday;
        final s = now.subtract(Duration(days: weekday - 1));
        start = KsaTime.dateOnly(s);
        end   = DateTime(start.year, start.month, start.day + 6, 23, 59, 59, 999);
        break;
      case _QuickRange.month:
        start = DateTime(now.year, now.month, 1);
        end   = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        break;
      case _QuickRange.year:
        start = DateTime(now.year, 1, 1);
        end   = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        break;
    }

    setState(() {
      _filters.from = start;
      _filters.to = end;
    });
  }

  Future<void> _openFiltersSheet() async {
    final result = await showModalBottomSheet<_ReportFilters>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18.r))),
      isScrollControlled: true,
      builder: (_) => ReportsFiltersSheet(initial: _filters, fmtDate: _fmtDateDynamic),
    );
    if (result != null) {
      setState(() {
        _filters.from = result.from;
        _filters.to = result.to;
        _filters.includeArchived = result.includeArchived;
        _filters.section = result.section;
      });
    }
  }

  Widget _softCircle(double size, Color color) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

/// ====== تبويب نظرة عامة ======
class _OverviewTab extends StatelessWidget {
  final _GatheredData data;
  final void Function(_ReportSection) onOpen;
  const _OverviewTab({required this.data, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: _gridCards([
        _navKpi('العقارات', '${data.propertiesCount}', () => onOpen(_ReportSection.properties)),
        _navKpi('المستأجرون', '${data.tenantsCount}', () => onOpen(_ReportSection.tenants)),
        _navKpi('العقود', '${data.contractsTotal}', () => onOpen(_ReportSection.contracts)),
        _navKpi('الفواتير', '${data.invoicesTotal}', () => onOpen(_ReportSection.invoices)),
        _navKpi('الصيانة', '${data.maintenanceTotal}', () => onOpen(_ReportSection.maintenance)),
      ]),
    );
  }
}

Widget _navKpi(String title, String value, VoidCallback onTap) {
IconData _homeIconForTitle(String t) {
  if (t.contains('العقارات') || t.contains('عقارات')) return Icons.apartment;
  if (t.contains('المستأجرين') || t.contains('مستأجر')) return Icons.people;
  if (t.contains('العقود') || t.contains('عقد')) return Icons.assignment;
  if (t.contains('الفواتير') || t.contains('فاتورة')) return Icons.receipt_long;
  if (t.contains('الصيانة') || t.contains('صيانة')) return Icons.build;
  return Icons.arrow_outward_rounded;
}

  final display = (value.trim().isEmpty) ? '0' : value;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16.r),
    child: _DarkCard(
      padding: EdgeInsets.all(14.w),
      child: Row(
        children: [
          Container(
  width: 36.w,
  height: 36.w,
  decoration: BoxDecoration(
    color: Colors.black.withOpacity(0.7),
    borderRadius: BorderRadius.circular(8.r),
  ),
  alignment: Alignment.center,
  child: Icon(_homeIconForTitle(title), color: Colors.white, size: 24.sp), // ← هذا هو السطر الجديد
),

          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.sp)),
                SizedBox(height: 2.h),
                Text(display, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.sp)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// ====== تبويب العقارات ======
class _PropertiesTab extends StatelessWidget {
  final _GatheredData data;
  const _PropertiesTab({required this.data});
  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: _gridCards([
        _kpi('إجمالي العقارات', '${data.propertiesCount}', asset: 'assets/reports/properties.png', icon: Icons.home_work),
        _kpi('الوحدات المشغولة', '${data.propertyUnitsOccupied}', asset: 'assets/reports/occupied.png', icon: Icons.apartment),
        _kpi('الوحدات الخالية', '${data.propertyUnitsVacant}', asset: 'assets/reports/vacant.png', icon: Icons.meeting_room_outlined),
      ]),
    );
  }
}

/// ====== تبويب المستأجرون ======
class _TenantsTab extends StatelessWidget {
  final _GatheredData data;
  const _TenantsTab({required this.data});
  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: _gridCards([
        _kpi('إجمالي المستأجرين', '${data.tenantsCount}', asset: 'assets/reports/tenants.png', icon: Icons.people_alt),
        _kpi('مربوطون بعقد', '${data.tenantsBound}', asset: 'assets/reports/tenants_bound.png', icon: Icons.link),
        _kpi('غير مربوطين بعقد', '${data.tenantsUnbound}', asset: 'assets/reports/tenants_unbound.png', icon: Icons.link_off),
      ]),
    );
  }
}

/// ====== تبويب العقود ======

class _ContractsTab extends StatelessWidget {
  final _GatheredData data;
  const _ContractsTab({required this.data});
  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: _gridCards([
        _kpi('إجمالي العقود', '${data.contractsTotal}', asset: 'assets/reports/contracts.png', icon: Icons.description),
        _kpi('العقود النشطة', '${data.activeContracts}', asset: 'assets/reports/contracts_active.png', icon: Icons.play_circle_fill),
        _kpi('العقود غير النشطة', '${data.inactiveContracts}', asset: 'assets/reports/contracts_inactive.png', icon: Icons.pause_circle_filled),
        _kpi('العقود القاربت', '${data.nearExpiryContracts}', asset: 'assets/reports/contracts_near.png', icon: Icons.hourglass_top),
        _kpi('العقود المنتهية', '${data.endedContracts}', asset: 'assets/reports/contracts_ended.png', icon: Icons.stop_circle),
        _kpi('دفعات قاربت', '${data.contractInvoicesNearDue}', asset: 'assets/reports/invoices_near.png', icon: Icons.schedule),
        _kpi('دفعات مستحقة', '${data.contractInvoicesDueToday}', asset: 'assets/reports/invoices_due.png', icon: Icons.event_available),
        _kpi('دفعات متأخرة', '${data.contractInvoicesOverdue}', asset: 'assets/reports/invoices_overdue.png', icon: Icons.warning_amber),
      ]),
    );
  }
}
/// ====== تبويب الفواتير ======
class _InvoicesTab extends StatelessWidget {
  final _GatheredData data;
  const _InvoicesTab({required this.data});
  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      child: _gridCards([
        _kpi('إجمالي الفواتير', '${data.invoicesTotal}', asset: 'assets/reports/invoices_total.png', icon: Icons.receipt_long),
        _kpi('فواتير العقود', '${data.invoicesFromContracts}', asset: 'assets/reports/invoices_contracts.png', icon: Icons.description_outlined),
        _kpi('فواتير الصيانة', '${data.invoicesFromMaintenance}', asset: 'assets/reports/invoices_maintenance.png', icon: Icons.build_circle),
      ]),
    );
  }
}

/// ====== تبويب الصيانة ======
class _MaintenanceTab extends StatelessWidget {
  final _GatheredData data;
  const _MaintenanceTab({required this.data});

  @override
  Widget build(BuildContext context) {
    // لاحقًا لو احتجنا قائمة مفصلة نستخدم هذه البيانات
    // لكن الآن نعرض فقط الإحصائيات العليا
    // final List<dynamic> items = data.maintenanceItems ?? <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DarkCard(
          child: _gridCards([
            _kpi(
              'إجمالي الطلبات',
              '${data.maintenanceTotal}',
              asset: 'assets/reports/maintenance_total.png',
              icon: Icons.build_rounded,
            ),
            _kpi(
              'طلبات جديدة',
              '${data.maintenanceNew}',
              asset: 'assets/reports/maintenance_new.png',
              icon: Icons.fiber_new,
            ),
            _kpi(
              'قيد التنفيذ',
              '${data.maintenanceInProgress}',
              asset: 'assets/reports/maintenance_inprogress.png',
              icon: Icons.construction,
            ),
            _kpi(
              'مكتملة',
              '${data.maintenanceDone}',
              asset: 'assets/reports/maintenance_done.png',
              icon: Icons.verified,
            ),
          ]),
        ),
      ],
    );
  }
}

/// ====== ورقة الفلاتر ======
class ReportsFiltersSheet extends StatefulWidget {
  final _ReportFilters initial;
  final String Function(DateTime) fmtDate;
  const ReportsFiltersSheet({super.key, required this.initial, required this.fmtDate});
  @override
  State<ReportsFiltersSheet> createState() => _ReportsFiltersSheetState();
}

class _ReportsFiltersSheetState extends State<ReportsFiltersSheet> {
  late _ReportFilters f;
  @override
  void initState() {
    super.initState();
    f = _ReportFilters()
      ..from = widget.initial.from
      ..to = widget.initial.to
      ..includeArchived = widget.initial.includeArchived
      ..section = widget.initial.section;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        right: 16.w, left: 16.w, top: 12.h,
        bottom: 16.h + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40.w, height: 4.h, margin: EdgeInsets.only(bottom: 12.h), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)))),
          Text('فلاتر التقارير', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18.sp)),
          SizedBox(height: 12.h),
          _DarkCard(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('الفترة'),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Expanded(
                      child: _fieldLike(
                        context,
                        icon: Icons.date_range,
                        title: 'من',
                        value: f.from == null ? '—' : widget.fmtDate(f.from!),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: f.from ?? KsaTime.today(),
                            firstDate: DateTime(2000), lastDate: DateTime(2100),
                            builder: (_, child) => _darkDateTheme(child),
                          );
                          if (picked != null) {
                            setState(() => f.from = DateTime(picked.year, picked.month, picked.day));
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: _fieldLike(
                        context,
                        icon: Icons.event,
                        title: 'إلى',
                        value: f.to == null ? '—' : widget.fmtDate(f.to!),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: f.to ?? KsaTime.today(),
                            firstDate: DateTime(2000), lastDate: DateTime(2100),
                            builder: (_, child) => _darkDateTheme(child),
                          );
                          if (picked != null) {
                            setState(() => f.to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Checkbox(
                      value: f.includeArchived,
                      onChanged: (v) => setState(() => f.includeArchived = v ?? false),
                      activeColor: Colors.white, checkColor: Colors.black,
                    ),
                    Text('إظهار المؤرشفة', style: GoogleFonts.cairo(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _DarkCard(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('نوع التقارير'),
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 8.w, runSpacing: 8.h,
                  children: [
                    _segChip('الرئيسية', f.section == _ReportSection.overview, () => setState(() => f.section = _ReportSection.overview)),
                    _segChip('العقارات', f.section == _ReportSection.properties, () => setState(() => f.section = _ReportSection.properties)),
                    _segChip('المستأجرون', f.section == _ReportSection.tenants, () => setState(() => f.section = _ReportSection.tenants)),
                    _segChip('العقود', f.section == _ReportSection.contracts, () => setState(() => f.section = _ReportSection.contracts)),
                    _segChip('الفواتير', f.section == _ReportSection.invoices, () => setState(() => f.section = _ReportSection.invoices)),
                    _segChip('الصيانة', f.section == _ReportSection.maintenance, () => setState(() => f.section = _ReportSection.maintenance)),
                  ],
                )
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w600))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r))),
                onPressed: () => Navigator.pop(context, f),
                child: Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ====== جمع البيانات ======
class _GatheredData {
  final int propertiesCount;
  final int tenantsCount;
  final int contractsTotal;
  final int propertyUnitsOccupied;
  final int propertyUnitsVacant;
  final int tenantsBound;
  final int tenantsUnbound;
  final int activeContracts;
  final int nearExpiryContracts;
  final int endedContracts;
  final int inactiveContracts;
  final int invoicesTotal;
  final int invoicesFromContracts;
  final int invoicesFromMaintenance;
  final int contractInvoicesNearDue;
  final int contractInvoicesDueToday;
  final int contractInvoicesOverdue;
  final int maintenanceNew;
  final int maintenanceInProgress;
  final int maintenanceDone;
  int get maintenanceTotal => maintenanceNew + maintenanceInProgress + maintenanceDone;
  // list of maintenance items to display (filtered & sorted)
  final List<dynamic> maintenanceItems;
  final double financeRevenue;
  final double financeReceivables;
  final double financeExpenses;
  final double financeNet;

  _GatheredData({
    required this.propertiesCount,
    required this.tenantsCount,
    required this.contractsTotal,
    required this.propertyUnitsOccupied,
    required this.propertyUnitsVacant,
    required this.tenantsBound,
    required this.tenantsUnbound,
    required this.activeContracts,
    required this.nearExpiryContracts,
    required this.endedContracts,
    required this.inactiveContracts,
    required this.invoicesTotal,
    required this.invoicesFromContracts,
    required this.invoicesFromMaintenance,
    required this.contractInvoicesNearDue,
    required this.contractInvoicesDueToday,
    required this.contractInvoicesOverdue,
    required this.maintenanceNew,
    required this.maintenanceInProgress,
    required this.maintenanceDone,
    required this.maintenanceItems,
    required this.financeRevenue,
    required this.financeReceivables,
    required this.financeExpenses,
    required this.financeNet,
  });

  static _GatheredData collect(
    Box<Tenant>? tenantsBox,
    Box<Property>? propsBox,
    Box? ctrBox,
    Box<Invoice>? invBox,
    Box? mBox,
    Box? sessionBox,
    _ReportFilters f,
  ) {
// استبعاد المؤرشفة دائمًا داخل التقارير
f.includeArchived = false;

    // لوائح أساسية
    final props = propsBox?.values.toList(growable: false) ?? const <Property>[];
    final tenants = tenantsBox?.values.toList(growable: false) ?? const <Tenant>[];
    final contracts = ctrBox?.values.toList(growable: false) ?? const <dynamic>[];
// تطبيق فلترة الأرشفة على المستأجرين
List<Tenant> tenantsList = tenants;
if (!f.includeArchived) {
  tenantsList = tenantsList.where((t) {
    bool arch = false;
    try { final v = (t as dynamic).isArchived; if (v is bool) arch = v; } catch (_){}
    if (!arch) { try { final v = (t as dynamic)['isArchived']; if (v is bool) arch = v; } catch (_){ } }
    return !arch;
  }).toList(growable: false);
}

    
    // قراءة عتبات "قارب" للعقود والفواتير من sessionBox إن وُجدت (لتطابق شاشة العقود الرئيسية)
    int _prefInt(Box? box, List<String> keys, int def) {
      if (box == null) return def;
      for (final k in keys) {
        try {
          final v = box.get(k);
          final int? n = _tryInt(v) ?? _tryNum(v)?.toInt();
          if (n != null && n >= 0) return n;
        } catch (_) {}
      }
      return def;
    }
    final int contractsNearDays = _prefInt(sessionBox, [
      'contractsNearDays','nearDaysContracts','nearContractsDays','nearEndContractsDays','nearEndDaysContracts','nearEndDays'
    ], 14);
    final int invoicesNearDays  = _prefInt(sessionBox, [
      'invoicesNearDays','nearDaysInvoices','nearInvoicesDays','nearDueInvoicesDays','nearDueDaysInvoices'
    ], 5);
// نحتاج اليوم في أكثر من مكان (عقود + فواتير)
    final now = KsaTime.today();

    // ----- العقارات: عدّ صحيح بدون _read() ودون مضاعفة الوحدات -----
    int occupiedUnits = 0, totalUnits = 0;

    // فلترة الأرشفة (اختياري) — إن كنت تستخدم archivedPropsBox
    List<Property> propsList = propsBox?.values.toList(growable: false) ?? const <Property>[];
    if (!f.includeArchived) {
      try {
        if (Hive.isBoxOpen('archivedPropsBox')) {
          final ab = Hive.box<bool>('archivedPropsBox');
          propsList = propsList.where((p) => !(ab.get(p.id, defaultValue: false) ?? false)).toList();
        }
      } catch (_) {}
    }

// Fallback: فلترة حسب isArchived داخل الموديل نفسه
if (!f.includeArchived) {
  propsList = propsList.where((p) {
    bool arch = false;
    try { final v = (p as dynamic).isArchived; if (v is bool) arch = v; } catch (_){}
    if (!arch) { try { final v = (p as dynamic)['isArchived']; if (v is bool) arch = v; } catch (_){ } }
    return !arch;
  }).toList(growable: false);
}

    // حساب عدد العقارات:
    // - نستثني "عمارة وحدات" (type = building && rentalMode = perUnit)
    // - لأننا نريد عدّ الوحدات داخلها فقط، وليس سجل العمارة نفسه
    final int propertiesCount = propsList.where((p) {
      try {
        final bool isBuilding = p.type == PropertyType.building;
        final bool isPerUnit  = isBuilding && p.rentalMode == RentalMode.perUnit;
        // لو كانت عمارة بنمط "وحدات" لا نحسبها ضمن إجمالي العقارات
        return !isPerUnit;
      } catch (_) {
        // لو تعذّر قراءة النوع/وضع التأجير نحتسبه كعنصر عادي
        return true;
      }
    }).length;

       // عدّ الوحدات (العقارات المستقلة + الوحدات الفعلية داخل العمائر)
    for (final p in propsList) {
      final bool hasParent = p.parentBuildingId != null;

      if (hasParent) {
        // وحدة تابعة لعمارة (شقة/وحدة): تُحتسب كوحدة واحدة
        totalUnits += 1;
        occupiedUnits += (p.occupiedUnits > 0) ? 1 : 0;
        continue;
      }

      final isBuilding = p.type == PropertyType.building;
      final isPerUnit  = isBuilding && p.rentalMode == RentalMode.perUnit;

      if (isPerUnit) {
        // عمارة بنمط "وحدات": لا تُحتسب كوحدة بحد ذاتها
        // سيتم احتساب الوحدات التابعة لها (parentBuildingId != null) أعلاه
        continue;
      }

      // عقار مستقل أو عمارة “تأجير كامل”: عنصر واحد فقط
      totalUnits += 1;
      occupiedUnits += (p.occupiedUnits > 0) ? 1 : 0;
    }


    final int vacantUnits = (totalUnits - occupiedUnits).clamp(0, totalUnits);

    // ===== العقود =====
    int activeCtr = 0, nearCtr = 0, endedCtr = 0, inactiveCtr = 0;
    final nearThreshold = now.add(Duration(days: contractsNearDays));

    
for (final c in contracts) {
      final bool archived   = (c is Contract) ? c.isArchived   : false;
      if (!f.includeArchived && archived) continue;

final DateTime? start = (c is Contract) ? c.startDate : null;
final DateTime? end   = (c is Contract) ? c.endDate   : null;
final bool terminated = (c is Contract) ? c.isTerminated : false;

      final DateTime dNow   = KsaTime.dateOnly(now);
      final DateTime dStart = start != null ? KsaTime.dateOnly(start) : DateTime(2000,1,1);
      final DateTime dEnd   = end   != null ? KsaTime.dateOnly(end)   : DateTime(2200,1,1);

      if (terminated || dNow.isAfter(dEnd)) {
        // منتهية
        endedCtr++;
        continue;
      }

      if (dNow.isBefore(dStart)) {
        // غير نشطة (لم تبدأ بعد)
        inactiveCtr++;
        continue;
      }

      // نشطة
      activeCtr++;
      if (end != null) {
        if (!dEnd.isBefore(dNow) && !dEnd.isAfter(nearThreshold)) {
          nearCtr++;
        }
      }
    }

// ===== عدّ دفعات العقود كما في شاشة العقود =====
// ===== عدّ دفعات العقود (قاربت / مستحقة / متأخرة) =====
int ctrInvNear = 0, ctrInvDueToday = 0, ctrInvOverdue = 0;

for (final c in contracts) {
  if (c is! Contract) continue;

  // تجاهل العقود المؤرشفة إذا الفلتر لا يشملها
  if (!f.includeArchived && c.isArchived) continue;

  final bool terminated = c.isTerminated;
  final DateTime? start = c.startDate;
  final DateTime? end   = c.endDate;

  final DateTime dNow   = KsaTime.dateOnly(now);
  final DateTime dStart = start != null ? KsaTime.dateOnly(start) : DateTime(2000, 1, 1);
  final DateTime dEnd   = end   != null ? KsaTime.dateOnly(end)   : DateTime(2200, 1, 1);

  // نفس منطق حالة العقود فوق: نشط إذا اليوم بين البداية والنهاية والعقد غير منتهي
  final bool isActive =
      !terminated &&
      !dNow.isBefore(dStart) &&
      !dNow.isAfter(dEnd);

  // العقد يعتبر "قارب" لو تاريخ نهايته بين اليوم و nearThreshold
  // (نفس منطق nearCtr في قسم العقود)
  final bool isNearExpiry =
      !terminated &&
      end != null &&
      !dEnd.isBefore(dNow) &&
      !dEnd.isAfter(nearThreshold);

  // آخر يوم في العقد بالضبط
  final bool isLastDayOfContract =
      end != null && dEnd.isAtSameMomentAs(dNow);

  // 1) الدفعات المتأخرة: تُحسب دائمًا حتى لو العقد منتهي
  final int ov = countOverduePayments(c);
  ctrInvOverdue += ov;

  // 2) الدفعات المستحقة اليوم + الدفعات القريبة: فقط للعقود النشطة
  if (isActive) {
    // ✅ المطلوب: لا نربط آخر يوم في العقد بـ "دفعات مستحقة" في شاشة التقارير
    if (!isLastDayOfContract) {
      ctrInvDueToday += countDueTodayPayments(c);
    }

    // ✅ المطلوب السابق: في حالة العقد "قارب" لا نظهر له "دفعات قاربت" نهائياً
    if (!isNearExpiry) {
      ctrInvNear += countNearDuePayments(c);
    }
  } else if (terminated) {
    // ✅ عقد مُنهى وبقيت دفعة مستحقة اليوم: نظهرها هنا أيضاً
    ctrInvDueToday += countDueTodayPayments(c);
  }
}




final int contractsTotal = contracts.where((c) {
  final bool archived = (c is Contract) ? c.isArchived : (_tryBool(_read(c, ['isArchived'])) ?? false);
  return f.includeArchived || !archived;
}).length;


    // ===== المستأجرون (نحسب الارتباط من العقود الفعلية - نسخة أكثر تحمّلاً) =====

    // نحاول استخراج tenantId من أي شكل محتمل
    String? _extractTenantId(dynamic c) {
      // 1) لو كان عند العقد getter مباشر
      try {
        final v = (c as dynamic).tenantId;
        if (v is String && v.isNotEmpty) return v;
        if (v is int) return v.toString();
      } catch (_) {}

      // 2) لو العقد يحتوي كائن tenant نفسه أو قيمة tenant كسلسلة
      try {
        final t = (c as dynamic).tenant;
        if (t is String && t.isNotEmpty) return t;          // tenant = "id"
        if (t is Tenant) return t.id;                       // tenant = Tenant object
        if (t is Map) {
          final id = t['id'] ?? t['tenantId'] ?? t['tid'];
          if (id is String && id.isNotEmpty) return id;
          if (id is int) return id.toString();
        }
      } catch (_) {}

      // 3) محاولات بأسماء شائعة ضمن الخريطة/الـobject
      final direct = _read(c, ['tenantId','tenantID','tenant_id','tid','tenant']);
      if (direct is String && direct.isNotEmpty) return direct;
      if (direct is int) return direct.toString();
      if (direct is Tenant) return direct.id;
      if (direct is Map) {
        final id = direct['id'] ?? direct['tenantId'] ?? direct['tid'];
        if (id is String && id.isNotEmpty) return id;
        if (id is int) return id.toString();
      }

      return null;
    }

    // قراءة آمنة لتواريخ العقد حتى لو كان Typed
    DateTime? _contractStart(dynamic c) {
      try { final v = (c as dynamic).startDate; if (v is DateTime) return v; } catch (_) {}
      return _tryDate(_read(c, ['startDate','startsOn','startAt']));
    }
    DateTime? _contractEnd(dynamic c) {
      try { final v = (c as dynamic).endDate; if (v is DateTime) return v; } catch (_) {}
      return _tryDate(_read(c, ['endDate','endsOn','endAt']));
    }
    bool _contractTerminated(dynamic c) {
      try { final v = (c as dynamic).isTerminated; if (v is bool) return v; } catch (_) {}
      return _tryBool(_read(c, ['isTerminated'])) ?? false;
    }
    bool _contractArchived(dynamic c) {
      try { final v = (c as dynamic).isArchived; if (v is bool) return v; } catch (_) {}
      return _tryBool(_read(c, ['isArchived'])) ?? false;
    }

    final activeTenantIds = <String>{};

    for (final c in contracts) {
      if (!f.includeArchived && _contractArchived(c)) continue;

      final String? tenantId = _extractTenantId(c);
      if (tenantId == null || tenantId.isEmpty) continue;

      final DateTime? start = _contractStart(c);
      final DateTime? end   = _contractEnd(c);
      final bool terminated = _contractTerminated(c);

      if (_GatheredData._contractIsActive(start, end, terminated)) {
        activeTenantIds.add(tenantId);
      }
    }

    // bound = لديهم عقد نشط فعليًا، unbound = الباقي
int bound = 0;
for (final t in tenantsList) {
  if (activeTenantIds.contains(t.id)) bound++;
}
int unbound = tenantsList.length - bound;


    // ===== Helpers تخص Invoice typed =====
    bool _isMaintInvoiceAny(dynamic inv) {
      // Typed
      if (inv is Invoice) {
        final note = (inv.note ?? '').toLowerCase();
        return note.contains('maintenance') || note.contains('صيانة');
      }
      // Fallback لو كانت Map (بيانات قديمة)
      final type  = (_tryString(_read(inv, ['type','category','sourceType'])) ?? '').toLowerCase();
      final notes = (_tryString(_read(inv, ['note','notes','description','memo'])) ?? '').toLowerCase();
      return type.contains('maintenance') || type.contains('صيانة')
          || notes.contains('maintenance') || notes.contains('صيانة');
    }

    bool _isContractInvoiceAny(dynamic inv) {
      // Typed
      if (inv is Invoice) {
        return (inv.contractId).isNotEmpty;
      }
      // Fallback لو كانت Map (بيانات قديمة)
      final cid = _read(inv, ['contractId','contract_id','cid','contract']);
      if (cid is String && cid.trim().isNotEmpty) return true;
      if (cid is int && cid != 0) return true;
      // كائن متداخل
      final cObj = _read(inv, ['contract','contractRef']);
      if (cObj is Map) {
        final inner = _read(cObj, ['id','contractId','ref','refId']);
        if (inner is String && inner.trim().isNotEmpty) return true;
        if (inner is int && inner != 0) return true;
      }
      return false;
    }

    // ===== الفواتير + الملخص المالي =====
    final invoices = invBox?.values.toList(growable: false) ?? const <Invoice>[];
    int totalInv = 0, fromContracts = 0, fromMaintenance = 0;
    double rev = 0.0, recv = 0.0, exp = 0.0;
// تجميع معرفات العقود المؤرشفة لاستبعاد فواتيرها
    // جهّز قائمة بمعرّفات العقود المؤرشفة (لاستخدامها مع الفواتير)
    final Set<String> _archCtrIds = <String>{};
    if (!f.includeArchived) {
      for (final c in contracts) {
        if (_contractArchived(c)) {
          // استخراج id العقد بأي شكل متاح
          String id = '';
          try {
            final v = (c as dynamic).id;
            if (v != null) id = v.toString();
          } catch (_) {}
          if (id.isEmpty) {
            final v = _read(c, ['id', 'contractId', 'ref', 'refId']);
            if (v != null) id = v.toString();
          }
          if (id.isNotEmpty) _archCtrIds.add(id);
        }
      }
    }

    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    for (final inv in invoices) {
      // 1) حالة الأرشفة على مستوى الفاتورة نفسها
      bool archived = false;
      try {
        if (inv is Invoice) {
          // قراءة مباشرة من موديل Invoice الـ Typed
          archived = inv.isArchived == true;
        } else {
          final v = _read(inv, ['isArchived']);
          if (v is bool) archived = v;
        }
      } catch (_) {
        final v = _tryBool(_read(inv, ['isArchived']));
        if (v != null) archived = v;
      }

      // 2) هل الفاتورة مرتبطة بعقد مؤرشف؟
      String cid = '';
      // 2.1 contractId مباشر
      try {
        cid = (inv as dynamic).contractId?.toString() ?? '';
      } catch (_) {}
      // 2.2 من كائن العقد داخل الفاتورة (لو موجود)
      if (cid.isEmpty) {
        final cObj = _read(inv, ['contract', 'contractRef']);
        final inner = _read(cObj, ['id', 'contractId', 'ref', 'refId']);
        if (inner != null) cid = inner.toString();
      }
      final bool hasArchivedContract =
          cid.isNotEmpty && _archCtrIds.contains(cid);

      // 3) الاستبعاد النهائي:
      //    - الفاتورة مؤرشفة بنفسها
      //    - أو مرتبطة بعقد مؤرشف
      if (archived || hasArchivedContract) {
        continue;
      }

      // من هنا وما بعده فقط فواتير فعّالة تُستخدم في:
      // - عدّ الفواتير في التقارير
      // - الملخص المالي (Revenue / Receivables / Expenses / Net)
      totalInv++;

      // تصنيف المصدر (أولوية الصيانة ثم العقود)
      final bool isMaint    = _isMaintInvoiceAny(inv);
      final bool isContract = _isContractInvoiceAny(inv);

      if (isMaint) {
        fromMaintenance++;
      } else if (isContract) {
        fromContracts++;
      }

      // — الحساب المالي كالمعتاد
double amount;
DateTime? dueOn;
DateTime? paidAt;   // ✅ لازم نعرّفه هنا
bool isPaid;
bool isCanceled;

if (inv is Invoice) {
  amount     = inv.amount;
  dueOn      = inv.dueDate;
  isPaid     = (inv.paidAmount >= inv.amount - 0.000001);
  isCanceled = inv.isCanceled == true;

  // ✅ لا تشتق paidAt من dueDate
  // استخدم حقل دفع فعلي إن كان موجود في الموديل، وإلا اتركه null
  paidAt     = null; // أو inv.paidAt إذا كان معرف في الـ Invoice
} else {
  amount     = (_tryNum(_read(inv, ['amount','total','net','grandTotal'])) ?? 0).toDouble();
  dueOn      = _tryDate(_read(inv, ['dueOn','dueDate']));
  paidAt     = _tryDate(_read(inv, ['paidAt','paid_on','paymentDate']));
  isPaid     = paidAt != null;
  isCanceled = _tryBool(_read(inv, ['isCanceled','canceled'])) == true;
}





final String type = (_tryString(_read(inv, ['type','category'])) ?? '').toLowerCase();
      final bool isExpense = (amount < 0) ||
          type.contains('expense') || type.contains('مصروف') ||
          type.contains('out') || type.contains('cost');

// بعد تحديد isPaid / isExpense
if (isPaid && !isExpense) {
  if (!f.hasDate || f.inRange(paidAt)) rev += amount.abs();
}
if (isPaid && isExpense) {
  if (!f.hasDate || f.inRange(paidAt)) exp += amount.abs();
}

// لا تضبط paidAt = dueDate.
// اترك paidAt كما هو (حقيقي إن وجد، وإلا null)



      if (!isPaid) {
        if (!f.hasDate) { /* disabled: receivables from invoices */ } else {
          final DateTime anchor = dueOn ?? todayEnd;
          /* receivables from invoices disabled: rely on sumReceivablesFromContracts */
        }
      }
    }
    
    // === المستحقات (من شاشة العقود الأصلية فقط) ===
    // بدلاً من جمع فواتير غير مدفوعة (الذي قد يختلط مع الصيانة/الملغاة)،
    // نحسب "المستحقات" بنفس منطق شاشة العقود: أي كل قسط غير مدفوع
    // وتاريخ استحقاقه اليوم أو قبله (أو داخل مرشح التاريخ).
    try {
      recv = sumReceivablesFromContracts(
        from: f.from,
        to: f.to,
        includeArchived: f.includeArchived,
      );
    } catch (_) {}

    // تحديث المستحقات من العقود مباشرة لضمان التطابق مع شاشة العقود (هللات + بدون زيادة):
    try {
      if (f.hasDate) {
        recv = sumReceivablesFromContractsExact(from: f.from, to: f.to, includeArchived: f.includeArchived);
      } else {
        recv = sumReceivablesFromContractsExact(includeArchived: f.includeArchived);
      }
    } catch (_) {}
final double net = (rev - exp);

    // ===== الصيانة =====
    final List<dynamic> maintenance = mBox?.values.toList(growable: false) ?? const <dynamic>[];

final List<dynamic> maintenanceFiltered = <dynamic>[];
    try {
      final List<dynamic> rawMaintenance = maintenance; // defined earlier as mBox?.values...
      for (final m in rawMaintenance) {
        final bool archived = (() {
          try { final v = (m as dynamic).isArchived; if (v is bool) return v; } catch (_) {}
          try { final v = (m as dynamic)['isArchived']; if (v is bool) return v; } catch (_) {}
          return false;
        })();
        if (!f.includeArchived && archived) continue;

        DateTime? created;
        try {
          final d = (m as dynamic).createdAt;
          if (d is DateTime) created = d;
          else if (d is String) created = DateTime.tryParse(d);
          else if (d is int) created = DateTime.fromMillisecondsSinceEpoch(d);
        } catch (_) {}

        if (created != null) {
          if (f.from != null && created.isBefore(f.from!)) continue;
          if (f.to != null && created.isAfter(f.to!)) continue;
        }
        maintenanceFiltered.add(m);
      }

      maintenanceFiltered.sort((a, b) {
        DateTime da = DateTime.tryParse((a as dynamic).createdAt?.toString() ?? '') ??
            ((a as dynamic).createdAt is int ? DateTime.fromMillisecondsSinceEpoch((a as dynamic).createdAt) : DateTime(1970));
        DateTime db = DateTime.tryParse((b as dynamic).createdAt?.toString() ?? '') ??
            ((b as dynamic).createdAt is int ? DateTime.fromMillisecondsSinceEpoch((b as dynamic).createdAt) : DateTime(1970));
        return db.compareTo(da);
      });
    } catch (_) {
      // if anything fails, fall back to empty list
    
    }

    int mNew = 0, mProg = 0, mDone = 0;

    // ——— دالة تساعدنا نفهم الحالة سواء كانت Enum أو String أو int ———
    String _normMaintStatus(dynamic raw) {
      // Enum: MaintenanceStatus.open.name => 'open'
      try {
        final nm = (raw as dynamic).name;
        if (nm is String && nm.isNotEmpty) return nm.toLowerCase();
      } catch (_) {}

      // String قديم
      if (raw is String) return raw.trim().toLowerCase();

      // index قديم (عدّل الأرقام لو ترتيب enum عندك مختلف)
      if (raw is int) {
        // open(0), inProgress(1), completed(2), canceled(3)
        switch (raw) {
          case 0: return 'open';
          case 1: return 'inprogress';
          case 2: return 'completed';
          case 3: return 'canceled';
        }
      }
      return 'unknown';
    }

    // ——— الحلقة الجديدة ———
    for (final m in maintenance) {
      final bool archived = _tryBool(_read(m, ['isArchived'])) ?? false;
      if (!f.includeArchived && archived) continue;

      // جرّب كموديل Typed ثم كـ Map قديم
      final dynamic status = (() {
        try { return (m as dynamic).status; } catch (_) {}
        try { return (m as dynamic)['status']; } catch (_) {}
        return null;
      })();

      final k = _normMaintStatus(status);

      if (k == 'open' || k == 'new') {
        mNew++;
      } else if (k == 'inprogress') {
        mProg++;
      } else if (k == 'completed' || k == 'done' || k == 'complete' || k == 'closed') {
        mDone++;
      } else if (k == 'canceled' || k == 'cancelled') {
        // لو عندك بطاقة "ملغاة" احسبها هنا؛ وإلا تجاهلها.
      }
    }

    // ===== الإرجاع =====
    
    // FINAL debug before returning gathered data
    try { print('FINAL collect() => mNew:$mNew, mProg:$mProg, mDone:$mDone, maintenanceFiltered:${maintenanceFiltered.length}, maintenanceRaw:${maintenance.length}'); } catch(_) {}


    // --- compute maintenance counts from maintenanceFiltered (ensure accurate counts) ---
    
    try {
      
for (final m in maintenanceFiltered) {
    final dynamic status = (() {
      try { return (m as dynamic).status; } catch (_) {}
      try { return (m as dynamic)['status']; } catch (_) {}
      return null;
    })();

    String k = 'unknown';
    try {
      if (status == null) {
        k = 'unknown';
      } else if (status is String) {
        final s = status.toLowerCase().trim();
        k = s.contains('.') ? s.split('.').last : s;
      } else {
        // status may be an enum or an object; try .name then toString()
        try {
          final nm = (status as dynamic).name;
          if (nm is String && nm.isNotEmpty) {
            k = nm.toLowerCase().trim();
          } else {
            final s = status.toString();
            k = s.contains('.') ? s.split('.').last.toLowerCase().trim() : s.toLowerCase().trim();
          }
        } catch (_) {
          try {
            final s = status.toString();
            k = s.contains('.') ? s.split('.').last.toLowerCase().trim() : s.toLowerCase().trim();
          } catch (_) {
            k = 'unknown';
          }
        }
      }
    } catch (_) {
      k = 'unknown';
    }

    if (k == 'open' || k == 'new' || k == 'pending') {
      mNew++;
    } else if (k == 'inprogress' || k == 'in_progress' || k == 'in progress' || k == 'assigned') {
      mProg++;
    } else if (k == 'completed' || k == 'done' || k == 'complete' || k == 'closed' || k == 'resolved') {
      mDone++;
    }
  }

    } catch (_) {}
    // debug
    try { print('RECALC counts => mNew:$mNew, mProg:$mProg, mDone:$mDone'); } catch(_) {}
return _GatheredData(
      propertiesCount: propertiesCount,
      tenantsCount: tenantsList.length,
      contractsTotal: contractsTotal,

      propertyUnitsOccupied: occupiedUnits,
      propertyUnitsVacant: vacantUnits,

      tenantsBound: bound,
      tenantsUnbound: unbound,

      activeContracts: activeCtr,
      nearExpiryContracts: nearCtr,
      endedContracts: endedCtr,
      inactiveContracts: inactiveCtr,

      invoicesTotal: totalInv,
      invoicesFromContracts: fromContracts,
      invoicesFromMaintenance: fromMaintenance,
      contractInvoicesNearDue: ctrInvNear,
      contractInvoicesDueToday: ctrInvDueToday,
      contractInvoicesOverdue: ctrInvOverdue,

      maintenanceNew: mNew,
      maintenanceInProgress: mProg,
      maintenanceDone: mDone,
      maintenanceItems: maintenanceFiltered,


    // --- build maintenanceFiltered list (filtered by archive/date and sorted) ---

      financeRevenue: rev,
      financeReceivables: recv,
      financeExpenses: exp,
      financeNet: net,
    );
  }

  static bool _contractIsActive(DateTime? start, DateTime? end, bool terminated) {
    if (terminated) return false;
    final now = KsaTime.today();
    final s = start ?? DateTime(2000);
    final e = end ?? DateTime(2200);
    final dNow = DateTime(now.year, now.month, now.day);
    final dS = DateTime(s.year, s.month, s.day);
    final dE = DateTime(e.year, e.month, e.day);
    return (dNow.isAtSameMomentAs(dS) || dNow.isAfter(dS)) &&
           (dNow.isAtSameMomentAs(dE) || dNow.isBefore(dE));
  }
}

/// ====== Widgets مساعدة ======
enum _QuickRange { today, week, month, year }

class _DarkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _DarkCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(16.w),
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172C),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: child,
    );
  }
}

Widget _chipButton({IconData? icon, required String label, VoidCallback? onTap}) {
  return InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.white70),
            SizedBox(width: 6.w),
          ],
          Text(label, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

Widget _fieldLike(BuildContext context, {required IconData icon, required String title, required String value, required VoidCallback onTap}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12.r),
    child: Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172C),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          SizedBox(width: 8.w),
          Text('$title: ', style: GoogleFonts.cairo(color: Colors.white70)),
          Expanded(child: Text(value, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    ),
  );
}

Widget _gridCards(List<Widget> children) {
  return LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      final cross = w > 900 ? 3 : w > 600 ? 2 : 1;
      return GridView.count(
        crossAxisCount: cross,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10.w,
        mainAxisSpacing: 10.h,
        childAspectRatio: w > 600 ? 3.5 : 3.0,
        children: children,
      );
    },
  );
}


Widget _kpi(
  String title,
  String value, {
  Color color = Colors.white,
  String? asset,                // مسار صورة (اختياري). إن لم توجد الصورة يُستبدل بأيقونة.
  IconData? icon,               // أيقونة fallback عند عدم وجود صورة.
}) {
  final display = (value.trim().isEmpty) ? '0' : value;
  try { if (title.contains('صيانة') || title.contains('طلبات')) print('KPI debug => '+title+' = '+display); } catch(_) {}

  Widget leading;
  if (asset != null) {
    leading = Image.asset(
      asset,
      width: 28,
      height: 28,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) {
        return Icon(icon ?? Icons.insert_chart_outlined, size: 22, color: color);
      },
    );
  } else if (icon != null) {
    leading = Icon(icon, size: 22, color: color);
  } else {
    leading = Text('ⓘ', style: GoogleFonts.cairo(color: color, fontWeight: FontWeight.w800));
  }

  return _DarkCard(
    padding: EdgeInsets.all(14.w),
    child: Row(
      children: [
        Container(
          width: 46.w, height: 46.w,
          decoration: BoxDecoration(
            color: color.withOpacity(.15),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: color.withOpacity(.35)),
          ),
          alignment: Alignment.center,
          child: leading,
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.sp)),
              SizedBox(height: 2.h),
              Text(display, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.sp)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _sectionTitle(String t) => Text(t, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.sp));
Widget _muted(String t)   => Text(t, style: GoogleFonts.cairo(color: Colors.white54));


String _moneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
}
String _money(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

Theme _darkDateTheme(Widget? child) {
  return Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Color(0xFF0E172C), onSurface: Colors.white),
      dialogBackgroundColor: const Color(0xFF0E172C),
    ),
    child: child!,
  );
}

Widget _segChip(String label, bool selected, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected ? Colors.white : const Color(0xFF1F2937),
        border: Border.all(color: selected ? Colors.white : Colors.white24),
      ),
      child: Text(label, style: GoogleFonts.cairo(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w800)),
    ),
  );
}

/// ====== بطاقة المخطط المالي ======
class _FinanceBreakdownCard extends StatelessWidget {
  final double revenue;
  final double receivables;
  final double expenses;
  final double net;

  const _FinanceBreakdownCard({required this.revenue, required this.receivables, required this.expenses, required this.net});

  @override
Widget build(BuildContext context) {
  // احسب قيم القطاعات بدون "الصافي"
  final double revenuePos     = revenue.clamp(0, double.infinity).toDouble();
  final double receivablesPos = receivables.clamp(0, double.infinity).toDouble();
  final double expensesPos    = expenses.clamp(0, double.infinity).toDouble();

  // إجمالي المخطط = مجموع القطاعات فقط
  final total = revenuePos + receivablesPos + expensesPos;

  // القيم المعروضة في المخطط
  final values = <double>[revenuePos, receivablesPos, expensesPos];

  // عناوين وألوان القطاعات (بدون "الصافي" كقطاع)
  final labels = ['الإيرادات', 'المستحقات', 'المصروفات'];
  final colors = const [Color(0xFF34D399), Color(0xFFFFD166), Color(0xFFFF5C5C)];

  return _DarkCard(
    padding: EdgeInsets.all(16.w),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('المُلخص المالي للفترة'),
        SizedBox(height: 10.h),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 520;
            final chart = SizedBox(
              height: 180.h,
              child: CustomPaint(
                painter: _DonutPainter(values: values, colors: colors, strokeWidth: 22),
                child: Center(
                  // اعرض "الصافي" في المنتصف فقط
                  child: Text(
                    _money(net),
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18.sp),
                  ),
                ),
              ),
            );

            final legend = Wrap(
              runSpacing: 8.h,
              spacing: 16.w,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[0], shape: BoxShape.circle)),
                  SizedBox(width: 6.w),
                  Text('الإيرادات: ${_money(revenuePos)}', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[1], shape: BoxShape.circle)),
                  SizedBox(width: 6.w),
                  Text('المستحقات: ${_moneyTrunc(receivablesPos)}', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [

                  Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[2], shape: BoxShape.circle)),
                  SizedBox(width: 6.w),
                  Text('المصروفات: ${_money(expensesPos)}', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
                // سطر منفصل للصافي (بدون نقطة لون لأنه ليس قطاعًا)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 12),
                  SizedBox(width: 6.w),
                  Text('الصافي: ${_money(net)}', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ],
            );

            if (wide) {
              return Row(children: [Expanded(child: chart), SizedBox(width: 16.w), Expanded(child: legend)]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chart, SizedBox(height: 12.h), legend]);
          },
        ),
      ],
    ),
  );
}

}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double strokeWidth;

  _DonutPainter({required this.values, required this.colors, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = math.min(size.width, size.height) / 2 - strokeWidth;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.white12;

    canvas.drawCircle(center, radius, backgroundPaint);

    final total = values.fold<double>(0, (p, c) => p + c);
    if (total <= 0) return;

    double startAngle = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * (2 * math.pi);
      if (sweep <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = colors[i];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) {
    if (old.strokeWidth != strokeWidth) return true;
    if (old.values.length != values.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (old.values[i] != values[i]) return true;
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// ====== Utils ديناميكية ======
dynamic _read(Object? o, List<String> names) {
  if (o == null) return null;
  if (o is Map) {
    for (final n in names) {
      if (o.containsKey(n)) return o[n];
    }
  }
  for (final n in names) {
    try { final v = (o as dynamic).toJson?.call()[n]; if (v != null) return v; } catch (_) {}
    try { final v = (o as dynamic).noSuchMethod(Invocation.getter(Symbol(n))); if (v != null) return v; } catch (_) {}
    try { final v = (o as dynamic).map?[n]; if (v != null) return v; } catch (_) {}
    try { final v = (o as dynamic).get?.call(n); if (v != null) return v; } catch (_) {}
  }
  return null;
}

bool? _tryBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return ['1', 'true', 'yes', 'y'].contains(v.toLowerCase());
  return null;
}

int? _tryInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

num? _tryNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

String? _tryString(dynamic v) => v?.toString();

DateTime? _tryDate(dynamic v) {
  if (v is DateTime) return v;
  if (v is String) {
    final iso = DateTime.tryParse(v);
    if (iso != null) return iso;
  }
  if (v is int) {
    try {
      if (v > 10000000000) return DateTime.fromMillisecondsSinceEpoch((v / 1000).round());
      return DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {}
  }
  return null;
}

/// مسارات اختيارية
class ReportsRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/reports': (context) => const ReportsScreen(),
      };
}