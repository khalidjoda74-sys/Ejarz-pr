// lib/ui/tenants_screen.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart'; // ✅ للهجري
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/package_limit_service.dart';
import '../data/services/tenant_record_service.dart';
import '../data/services/user_scope.dart' as scope;
import '../data/constants/boxes.dart' as bx;

import '../data/services/offline_sync_service.dart';

import '../models/tenant.dart';
// ✅ وقت/تاريخ الرياض

// للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'properties_screen.dart';
import 'contracts_screen.dart'
    as contracts_ui; // يتيح استخدام Contract و ContractDetailsScreen
import 'maintenance_screen.dart' as maintenance_ui;
import '../models/property.dart'; // نحتاجه لتحديث إشغال العقار

// عناصر الواجهة المشتركة
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/entity_audit_info_button.dart';
import '../widgets/darvoo_app_bar.dart';
import '../widgets/custom_confirm_dialog.dart';

/// ===== عناصر خلفية/ستايل موحّدة =====
Widget _softCircle(double size, Color color) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _DarkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const _DarkCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0x26FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

String _limitChars(String t, int max) =>
    t.length <= max ? t : '${t.substring(0, max)}…';
const String _clientTypeTenant = 'tenant';
const String _clientTypeCompany = 'company';
const String _clientTypeServiceProvider = 'serviceProvider';

String _normalizeClientType(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty) return _clientTypeTenant;
  if (v == 'tenant' || v == 'مستأجر') return _clientTypeTenant;
  if (v == 'company' || v == 'مستأجر (شركة)' || v == 'شركة') {
    return _clientTypeCompany;
  }
  if (v == 'serviceprovider' ||
      v == 'service_provider' ||
      v == 'service provider' ||
      v == 'مقدم خدمة') {
    return _clientTypeServiceProvider;
  }
  return _clientTypeTenant;
}

String _effectiveClientType(Tenant t) {
  final normalized = _normalizeClientType(t.clientType);
  if (normalized != _clientTypeTenant) return normalized;
  final hasProviderHints = (t.serviceSpecialization ?? '').trim().isNotEmpty &&
      (t.companyName ?? '').trim().isEmpty &&
      (t.companyCommercialRegister ?? '').trim().isEmpty &&
      (t.tenantBankName ?? '').trim().isEmpty;
  if (hasProviderHints) return _clientTypeServiceProvider;
  return normalized;
}

bool _clientTypeRequiresAttachments(String type) =>
    _normalizeClientType(type) != _clientTypeServiceProvider;

bool _isMaintenanceProviderCurrentStatus(dynamic status) {
  if (status == null) return false;
  if (status is Enum) {
    final name = status.name.toLowerCase();
    return name == 'open' || name == 'inprogress';
  }
  final txt = status.toString().toLowerCase();
  return txt.contains('open') || txt.contains('inprogress');
}

String _normProviderName(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _countProviderMaintenanceRequests(String providerName) {
  final target = _normProviderName(providerName);
  if (target.isEmpty) return 0;
  final boxName = HiveService.maintenanceBoxName();
  if (!Hive.isBoxOpen(boxName)) return 0;
  Box<maintenance_ui.MaintenanceRequest> box;
  try {
    box = Hive.box<maintenance_ui.MaintenanceRequest>(boxName);
  } catch (_) {
    return 0;
  }

  var count = 0;
  for (final item in box.values) {
      final assigned = _normProviderName(item.assignedTo);
      if (!item.isArchived &&
          assigned == target &&
          _isMaintenanceProviderCurrentStatus(item.status)) {
        count += 1;
      }
    }
  return count;
}

int _countProviderAllMaintenanceRequests(String providerName) {
  final target = _normProviderName(providerName);
  if (target.isEmpty) return 0;
  final boxName = HiveService.maintenanceBoxName();
  if (!Hive.isBoxOpen(boxName)) return 0;
  Box<maintenance_ui.MaintenanceRequest> box;
  try {
    box = Hive.box<maintenance_ui.MaintenanceRequest>(boxName);
  } catch (_) {
    return 0;
  }

  var count = 0;
  for (final item in box.values) {
    final assigned = _normProviderName(item.assignedTo);
    if (assigned == target) {
      count += 1;
    }
  }
  return count;
}

int _countTenantAllContracts(String tenantId) {
  final id = tenantId.trim();
  if (id.isEmpty) return 0;
  try {
    final cname = HiveService.contractsBoxName();
    if (!Hive.isBoxOpen(cname)) return 0;
    final Box<contracts_ui.Contract> contractsBox =
        Hive.box<contracts_ui.Contract>(cname);
    return contractsBox.values.where((c) => c.tenantId == id).length;
  } catch (_) {
    return 0;
  }
}

Future<void> _showTenantBlockedActionDialog(
  BuildContext context, {
  required String message,
}) async {
  await CustomConfirmDialog.show(
    context: context,
    title: 'تنبيه',
    message: message,
    confirmLabel: 'حسنًا',
    showCancel: false,
  );
}

void _debugLogProviderCountDetails(String providerName) {
  if (!kDebugMode) return;
  final target = _normProviderName(providerName);
  final boxName = HiveService.maintenanceBoxName();
  if (!Hive.isBoxOpen(boxName)) {
    debugPrint(
        '[provider-count] maintenance box not open: $boxName target="$target"');
    return;
  }

  try {
    final box = Hive.box<maintenance_ui.MaintenanceRequest>(boxName);
    var total = 0;
    var sameNameAllStatuses = 0;
    var sameNameVisibleStatuses = 0;
    var sameNameVisibleStatusesNotArchived = 0;

    for (final item in box.values) {
      total += 1;
      final assignedRaw = item.assignedTo ?? '';
      final assignedNorm = _normProviderName(assignedRaw);
      final sameName = assignedNorm == target;
      if (!sameName) continue;
      sameNameAllStatuses += 1;
      final visible = _isMaintenanceProviderCurrentStatus(item.status);
      if (visible) sameNameVisibleStatuses += 1;
      if (visible && !item.isArchived) {
        sameNameVisibleStatusesNotArchived += 1;
      }
      debugPrint(
          '[provider-count:item] id=${item.id} assignedRaw="$assignedRaw" assignedNorm="$assignedNorm" status=${item.status} archived=${item.isArchived}');
    }

    debugPrint(
        '[provider-count:summary] box=$boxName targetRaw="$providerName" targetNorm="$target" total=$total sameNameAllStatuses=$sameNameAllStatuses sameNameVisibleStatuses=$sameNameVisibleStatuses sameNameVisibleStatusesNotArchived=$sameNameVisibleStatusesNotArchived');
  } catch (e) {
    debugPrint('[provider-count:error] $e');
  }
}

String _clientTypeLabel(String type) {
  switch (_normalizeClientType(type)) {
    case _clientTypeCompany:
      return 'مستأجر (شركة)';
    case _clientTypeServiceProvider:
      return 'مقدم خدمة';
    case _clientTypeTenant:
    default:
      return 'مستأجر';
  }
}

Color _clientTypeColor(String type) {
  switch (_normalizeClientType(type)) {
    case _clientTypeTenant:
      return const Color(0xFF0D9488);
    case _clientTypeCompany:
      return const Color(0xFFB45309);
    case _clientTypeServiceProvider:
      return const Color(0xFF9A3412);
    default:
      return const Color(0xFF334155);
  }
}

String _addedClientSuccessMessage(String type) {
  switch (_normalizeClientType(type)) {
    case _clientTypeCompany:
      return 'تم إضافة مستأجر (شركة) بنجاح';
    case _clientTypeServiceProvider:
      return 'تم إضافة مزود خدمة بنجاح';
    case _clientTypeTenant:
    default:
      return 'تم إضافة مستأجر بنجاح';
  }
}

/// ✅ دوال مشتركة Top-Level
String _fmtDate(DateTime d) {
  final dd = KsaTime.dateOnly(d);
  return '${dd.year}-${dd.month.toString().padLeft(2, '0')}-${dd.day.toString().padLeft(2, '0')}';
}

bool get _useHijri {
  if (!Hive.isBoxOpen('sessionBox')) return false;
  try {
    return Hive.box('sessionBox').get('useHijri', defaultValue: false) == true;
  } catch (_) {
    return false;
  }
}

/// ✅ تنسيق هجري/ميلادي للعرض فقط
String _fmtDateDynamic(DateTime d) {
  final dd = KsaTime.dateOnly(d);
  if (!_useHijri) {
    return '${dd.year}-${dd.month.toString().padLeft(2, '0')}-${dd.day.toString().padLeft(2, '0')}';
  }
  final h = HijriCalendar.fromDate(dd);
  final yy = h.hYear.toString();
  final mm = h.hMonth.toString().padLeft(2, '0');
  final ddh = h.hDay.toString().padLeft(2, '0');
  return '$yy-$mm-$ddh هـ';
}

Widget _sectionTitle(String t) => Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(t,
          style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14.sp)),
    );

/// ===== فلاتر القائمة =====
enum _LinkedFilter { all, linked, unlinked }

enum _IdExpiryFilter { all, expired, valid }

enum _ArchiveFilter { all, notArchived, archived }

enum _TenantTypeFilter { all, tenants, serviceProviders }

enum _TenantSubTypeFilter { all, individuals, companies }

/// ===== شاشة قائمة المستأجرين =====
class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key});

  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  Box<Tenant> get _box => Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));

  final _sync = OfflineSyncService.instance;

  String _q = '';

  // فلاتر
  _TenantTypeFilter _fTenantType = _TenantTypeFilter.all;
  _TenantSubTypeFilter _fTenantSubType = _TenantSubTypeFilter.all;
  _LinkedFilter _fLinked = _LinkedFilter.all;
  _IdExpiryFilter _fIdExpiry = _IdExpiryFilter.all;
  _ArchiveFilter _fArchive = _ArchiveFilter.notArchived; // الافتراضي: غير مؤرشف

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  bool _handledOpen = false;
  bool _appliedRouteArgs = false;
  String? _pendingOpenTenantId;

  void _openTenantDetailsById(String id) {
    final box = _box;
    Tenant? t;
    try {
      t = box.values.firstWhere((e) => e.id == id);
    } catch (_) {}

    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('المستأجر غير موجود', style: GoogleFonts.cairo())),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TenantDetailsScreen(tenant: t!)),
    );
  }

  @override
  void initState() {
    super.initState();
    _initTenants();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyRouteArgumentsIfNeeded();
  }

  void _applyRouteArgumentsIfNeeded() {
    if (_appliedRouteArgs) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    _appliedRouteArgs = true;

    final args = route.settings.arguments;
    if (args is! Map) return;

    final requestedClientType = _normalizeClientType(
      args['filterClientType']?.toString(),
    );
    final requestedTenantType =
        (args['filterTenantType'] ?? '').toString().trim().toLowerCase();
    final requestedTenantSubType =
        (args['filterTenantSubType'] ?? '').toString().trim().toLowerCase();
    final requestedLinked =
        (args['filterLinked'] ?? '').toString().trim().toLowerCase();
    final requestedIdExpiry =
        (args['filterIdExpiry'] ?? '').toString().trim().toLowerCase();
    final requestedArchive =
        (args['filterArchive'] ?? '').toString().trim().toLowerCase();

    if (requestedClientType == _clientTypeServiceProvider) {
      _fTenantType = _TenantTypeFilter.serviceProviders;
      _fTenantSubType = _TenantSubTypeFilter.all;
      _fLinked = _LinkedFilter.all;
      _fIdExpiry = _IdExpiryFilter.all;
    } else if (requestedClientType == _clientTypeCompany) {
      _fTenantType = _TenantTypeFilter.tenants;
      _fTenantSubType = _TenantSubTypeFilter.companies;
      _fLinked = _LinkedFilter.all;
      _fIdExpiry = _IdExpiryFilter.all;
    } else if (args['filterClientType'] != null) {
      _fTenantType = _TenantTypeFilter.tenants;
      _fTenantSubType = _TenantSubTypeFilter.individuals;
      _fLinked = _LinkedFilter.all;
      _fIdExpiry = _IdExpiryFilter.all;
    }

    if (requestedTenantType.isNotEmpty) {
      if (requestedTenantType == 'tenants') {
        _fTenantType = _TenantTypeFilter.tenants;
      } else if (requestedTenantType == 'serviceproviders' ||
          requestedTenantType == 'service_providers') {
        _fTenantType = _TenantTypeFilter.serviceProviders;
      } else {
        _fTenantType = _TenantTypeFilter.all;
      }
    }

    if (requestedTenantSubType.isNotEmpty) {
      _fTenantType = _TenantTypeFilter.tenants;
      if (requestedTenantSubType == 'individuals') {
        _fTenantSubType = _TenantSubTypeFilter.individuals;
      } else if (requestedTenantSubType == 'companies') {
        _fTenantSubType = _TenantSubTypeFilter.companies;
      } else {
        _fTenantSubType = _TenantSubTypeFilter.all;
      }
    }

    if (requestedLinked.isNotEmpty) {
      _fTenantType = _TenantTypeFilter.tenants;
      if (requestedLinked == 'linked') {
        _fLinked = _LinkedFilter.linked;
      } else if (requestedLinked == 'unlinked') {
        _fLinked = _LinkedFilter.unlinked;
      } else {
        _fLinked = _LinkedFilter.all;
      }
    }

    if (requestedIdExpiry.isNotEmpty) {
      _fTenantType = _TenantTypeFilter.tenants;
      _fTenantSubType = _TenantSubTypeFilter.individuals;
      if (requestedIdExpiry == 'expired') {
        _fIdExpiry = _IdExpiryFilter.expired;
      } else if (requestedIdExpiry == 'valid') {
        _fIdExpiry = _IdExpiryFilter.valid;
      } else {
        _fIdExpiry = _IdExpiryFilter.all;
      }
    }

    if (requestedArchive.isNotEmpty) {
      if (requestedArchive == 'archived') {
        _fArchive = _ArchiveFilter.archived;
      } else if (requestedArchive == 'notarchived' ||
          requestedArchive == 'not_archived') {
        _fArchive = _ArchiveFilter.notArchived;
      } else {
        _fArchive = _ArchiveFilter.all;
      }
    }

    if (_fTenantType != _TenantTypeFilter.tenants) {
      _fTenantSubType = _TenantSubTypeFilter.all;
      _fLinked = _LinkedFilter.all;
      _fIdExpiry = _IdExpiryFilter.all;
    } else if (_fTenantSubType != _TenantSubTypeFilter.individuals &&
        requestedIdExpiry.isEmpty) {
      _fIdExpiry = _IdExpiryFilter.all;
    }

    final openTenantId = (args['openTenantId'] ?? '').toString().trim();
    if (openTenantId.isNotEmpty) {
      _pendingOpenTenantId = openTenantId;
    }
  }

  Future<void> _initTenants() async {
    // نضمن الصناديق مفتوحة (لا تفتح/تغلق مزامنة هنا)
    await HiveService.ensureReportsBoxesOpen();
    if (mounted) {
      setState(() {});
    }

    // حساب ارتفاع البوتوم ناف + فتح مستأجر معيّن لو جاي من شاشة ثانية
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }

      if (_handledOpen) return;
      _handledOpen = true;
      final id = _pendingOpenTenantId;
      if (id != null) _openTenantDetailsById(id);
    });
  }

  Future<void> _openProviderMaintenanceRequests(Tenant t) async {
    final args = <String, dynamic>{
      'filterAssignedTo': t.fullName,
      'filterClientType': _clientTypeServiceProvider,
      'providerRequestsView': 'current',
    };
    try {
      await Navigator.of(context).pushNamed('/maintenance', arguments: args);
      return;
    } catch (_) {}
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const maintenance_ui.MaintenanceScreen(),
        settings: RouteSettings(arguments: args),
      ),
    );
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
        // أنت هنا
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const contracts_ui.ContractsScreen()),
        );
        break;
    }
  }

  InputDecoration _dropdownDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  // —— حالة الفلاتر وملخّصها (تمامًا كالعقارات)
  bool get _hasActiveFilters =>
      (_fArchive == _ArchiveFilter.archived) ||
      (_fTenantType != _TenantTypeFilter.all) ||
      (_fTenantSubType != _TenantSubTypeFilter.all) ||
      (_fLinked != _LinkedFilter.all) ||
      (_fIdExpiry != _IdExpiryFilter.all);

  String _currentFilterLabel() {
    final parts = <String>[];
    parts.add(_fArchive == _ArchiveFilter.archived ? 'المؤرشفة' : 'الكل');
    switch (_fTenantType) {
      case _TenantTypeFilter.tenants:
        switch (_fTenantSubType) {
          case _TenantSubTypeFilter.individuals:
            parts.add('مستأجرون أفراد');
            break;
          case _TenantSubTypeFilter.companies:
            parts.add('مستأجرون شركات');
            break;
          case _TenantSubTypeFilter.all:
            parts.add('مستأجرون');
            break;
        }
        break;
      case _TenantTypeFilter.serviceProviders:
        parts.add('مقدمو خدمات');
        break;
      case _TenantTypeFilter.all:
        break;
    }
    switch (_fLinked) {
      case _LinkedFilter.linked:
        parts.add('مربوطون بعقد');
        break;
      case _LinkedFilter.unlinked:
        parts.add('غير مربوطين بعقد');
        break;
      case _LinkedFilter.all:
        break;
    }
    switch (_fIdExpiry) {
      case _IdExpiryFilter.expired:
        parts.add('هوية منتهية');
        break;
      case _IdExpiryFilter.valid:
        parts.add('هوية سارية');
        break;
      case _IdExpiryFilter.all:
        break;
    }
    return parts.join(' • ');
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        _TenantTypeFilter tempTenantType = _fTenantType;
        _TenantSubTypeFilter tempTenantSubType = _fTenantSubType;
        _LinkedFilter tempLinked = _fLinked;
        _IdExpiryFilter tempId = _fIdExpiry;
        // ✅ مثل العقارات: خياران جنب بعض — «الكل» و«الأرشفة»
        bool arch = _fArchive == _ArchiveFilter.archived;

        return StatefulBuilder(
          builder: (context, setM) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16.w,
                  16.h,
                  16.w,
                  16.h +
                      MediaQuery.of(context).padding.bottom +
                      MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Center(
                    child: Text(
                      'تصفية',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // ——— قوائم منسدلة مثل شاشة العقارات ———
                  DropdownButtonFormField<_TenantTypeFilter>(
                    initialValue: tempTenantType,
                    decoration: _dropdownDeco('النوع'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(
                          value: _TenantTypeFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _TenantTypeFilter.tenants,
                          child: Text('مستأجرون')),
                      DropdownMenuItem(
                          value: _TenantTypeFilter.serviceProviders,
                          child: Text('مقدمو خدمات')),
                    ],
                    onChanged: (v) => setM(() {
                      tempTenantType = v ?? _TenantTypeFilter.all;
                      if (tempTenantType != _TenantTypeFilter.tenants) {
                        tempTenantSubType = _TenantSubTypeFilter.all;
                        tempLinked = _LinkedFilter.all;
                        tempId = _IdExpiryFilter.all;
                      }
                    }),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                  if (tempTenantType == _TenantTypeFilter.tenants) ...[
                    SizedBox(height: 10.h),
                    DropdownButtonFormField<_TenantSubTypeFilter>(
                      initialValue: tempTenantSubType,
                      decoration: _dropdownDeco('نوع المستأجرين'),
                      dropdownColor: const Color(0xFF0B1220),
                      iconEnabledColor: Colors.white70,
                      items: const [
                        DropdownMenuItem(
                            value: _TenantSubTypeFilter.all,
                            child: Text('الكل')),
                        DropdownMenuItem(
                            value: _TenantSubTypeFilter.individuals,
                            child: Text('أفراد')),
                        DropdownMenuItem(
                            value: _TenantSubTypeFilter.companies,
                            child: Text('شركات')),
                      ],
                      onChanged: (v) => setM(() {
                        tempTenantSubType = v ?? _TenantSubTypeFilter.all;
                        if (tempTenantSubType !=
                            _TenantSubTypeFilter.individuals) {
                          tempId = _IdExpiryFilter.all;
                        }
                      }),
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                    SizedBox(height: 10.h),
                    DropdownButtonFormField<_LinkedFilter>(
                    initialValue: tempLinked,
                    decoration: _dropdownDeco('الارتباط بالعقود'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(
                          value: _LinkedFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _LinkedFilter.linked,
                          child: Text('مربوطون بعقد')),
                      DropdownMenuItem(
                          value: _LinkedFilter.unlinked,
                          child: Text('غير مربوطين بعقد')),
                    ],
                    onChanged: (v) =>
                        setM(() => tempLinked = v ?? _LinkedFilter.all),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                  ],
                  if (tempTenantType == _TenantTypeFilter.tenants &&
                      tempTenantSubType ==
                          _TenantSubTypeFilter.individuals) ...[
                    SizedBox(height: 10.h),
                    DropdownButtonFormField<_IdExpiryFilter>(
                    initialValue: tempId,
                    decoration: _dropdownDeco('حالة الهوية'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(
                          value: _IdExpiryFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _IdExpiryFilter.expired,
                          child: Text('هوية منتهية')),
                      DropdownMenuItem(
                          value: _IdExpiryFilter.valid,
                          child: Text('هوية سارية')),
                    ],
                      onChanged: (v) =>
                          setM(() => tempId = v ?? _IdExpiryFilter.all),
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                  ],

                  // —— الأرشفة مثل شاشة العقارات: خياران جنب بعض
                  SizedBox(height: 14.h),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'الأرشفة',
                      style: GoogleFonts.cairo(
                          color: Colors.white70, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text('غير مؤرشفة', style: GoogleFonts.cairo()),
                          selected: !arch,
                          onSelected: (_) => setM(() => arch = false),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('مؤرشفة', style: GoogleFonts.cairo()),
                          selected: arch,
                          onSelected: (_) => setM(() => arch = true),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _fTenantType = tempTenantType;
                              _fTenantSubType =
                                  tempTenantType == _TenantTypeFilter.tenants
                                      ? tempTenantSubType
                                      : _TenantSubTypeFilter.all;
                              _fLinked =
                                  tempTenantType == _TenantTypeFilter.tenants
                                      ? tempLinked
                                      : _LinkedFilter.all;
                              _fIdExpiry =
                                  tempTenantType == _TenantTypeFilter.tenants &&
                                          tempTenantSubType ==
                                              _TenantSubTypeFilter.individuals
                                      ? tempId
                                      : _IdExpiryFilter.all;
                              _fArchive = arch
                                  ? _ArchiveFilter.archived
                                  : _ArchiveFilter.notArchived;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          child: Text('تطبيق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _fTenantType = _TenantTypeFilter.all;
                              _fTenantSubType = _TenantSubTypeFilter.all;
                              _fLinked = _LinkedFilter.all;
                              _fIdExpiry = _IdExpiryFilter.all;
                              _fArchive = _ArchiveFilter.notArchived;
                            });
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24)),
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
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
  }

  Future<void> _tryArchive(Tenant t) async {
    final type = _effectiveClientType(t);
    final currentProviderRequests =
        type == _clientTypeServiceProvider
            ? _countProviderMaintenanceRequests(t.fullName)
            : 0;

    // إذا كان مؤرشفًا → فك الأرشفة مباشرة
    if (t.isArchived) {
      t.isArchived = false;
      t.updatedAt = KsaTime.now();

      // 1) احفظ محليًا فورًا (offline-first)
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);

      // 2) أضف للمزامنة (Firestore عندما يتوفر النت) — بدون await
      _sync.enqueueUpsertTenant(t);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم فك الأرشفة', style: GoogleFonts.cairo())),
      );
      return;
    }

    // إذا لم يكن مؤرشفًا → حاول الأرشفة
    if (type == _clientTypeServiceProvider) {
      if (currentProviderRequests > 0) {
        await _showTenantBlockedActionDialog(
          context,
          message:
              'لا يمكن أرشفة مقدم الخدمة لوجود طلبات خدمات سارية مرتبطة به. يمكنك أرشفته فقط إذا لم تعد هناك طلبات خدمات سارية.',
        );
        return;
      }
    } else {
      if (t.activeContractsCount > 0) {
        await _showTenantBlockedActionDialog(
          context,
          message:
              'لا يمكن أرشفة هذا العميل لوجود عقود نشطة مرتبطة به. يمكنك أرشفته بعد إنهاء العقود النشطة.',
        );
        return;
      }
    }

    t.isArchived = true;
    t.updatedAt = KsaTime.now();

    // 1) احفظ محليًا فورًا (offline-first)
    final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
    await box.put(t.id, t);

    // 2) أضف للمزامنة — بدون await
    _sync.enqueueUpsertTenant(t);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت الأرشفة', style: GoogleFonts.cairo())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayKsa = KsaTime.dateOnly(KsaTime.now());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // الدروَر يبدأ أسفل الـAppBar وينتهي فوق الـBottomNav
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
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text('العملاء',
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20.sp)),
          actions: [
            IconButton(
              onPressed: _openFilterSheet,
              tooltip: 'التصفيه',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
            ),
          ],
        ),
        body: Stack(
          children: [
            // خلفية متدرجة مع دوائر
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6)
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

            Column(
              children: [
                // شريط بحث بسيط
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم / رقم الهوية / الجوال',
                      hintStyle: GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ),

                // ✅ وسم الفلاتر — نفس العقارات
                if (_hasActiveFilters)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded,
                                size: 16, color: Colors.white70),
                            SizedBox(width: 6.w),
                            Text(
                              _currentFilterLabel(),
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // القائمة
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _box.listenable(),
                    builder: (context, Box<Tenant> b, _) {
                      var items = b.values.toList();

                      // —— تطبيق الفلاتر
                      // الأرشفة (مثل العقارات: إما المؤرشفة أو غير المؤرشفة)
                      if (_fArchive == _ArchiveFilter.notArchived) {
                        items = items.where((t) => !t.isArchived).toList();
                      } else if (_fArchive == _ArchiveFilter.archived) {
                        items = items.where((t) => t.isArchived).toList();
                      }
                      // النوع
                      if (_fTenantType != _TenantTypeFilter.all) {
                        items = items.where((t) {
                          final type = _effectiveClientType(t);
                          if (_fTenantType ==
                              _TenantTypeFilter.serviceProviders) {
                            return type == _clientTypeServiceProvider;
                          }
                          return type == _clientTypeTenant ||
                              type == _clientTypeCompany;
                        }).toList();
                      }
                      // نوع المستأجرين
                      if (_fTenantType == _TenantTypeFilter.tenants) {
                        if (_fTenantSubType ==
                            _TenantSubTypeFilter.individuals) {
                          items = items
                              .where((t) =>
                                  _effectiveClientType(t) == _clientTypeTenant)
                              .toList();
                        } else if (_fTenantSubType ==
                            _TenantSubTypeFilter.companies) {
                          items = items
                              .where((t) =>
                                  _effectiveClientType(t) == _clientTypeCompany)
                              .toList();
                        }
                      }
                      // الارتباط بالعقود
                      if (_fTenantType == _TenantTypeFilter.tenants) {
                        if (_fLinked == _LinkedFilter.linked) {
                          items = items
                              .where((t) => (t.activeContractsCount) > 0)
                              .toList();
                        } else if (_fLinked == _LinkedFilter.unlinked) {
                          items = items
                              .where((t) => (t.activeContractsCount) == 0)
                              .toList();
                        }
                      }
                      // حالة الهوية
                      if (_fTenantType == _TenantTypeFilter.tenants &&
                          _fTenantSubType ==
                              _TenantSubTypeFilter.individuals) {
                        if (_fIdExpiry == _IdExpiryFilter.expired) {
                          items = items
                              .where((t) =>
                                  t.idExpiry != null &&
                                  KsaTime.dateOnly(t.idExpiry!)
                                      .isBefore(todayKsa))
                              .toList();
                        } else if (_fIdExpiry == _IdExpiryFilter.valid) {
                          items = items
                              .where((t) =>
                                  t.idExpiry != null &&
                                  !KsaTime.dateOnly(t.idExpiry!)
                                      .isBefore(todayKsa))
                              .toList();
                        }
                      }

                      // البحث
                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        items = items.where((t) {
                          return t.fullName.toLowerCase().contains(q) ||
                              t.nationalId.toLowerCase().contains(q) ||
                              t.phone.toLowerCase().contains(q);
                        }).toList();
                      }

                      // ترتيب: الأحدث أولاً (مع حماية null)
                      // ترتيب ثابت: الأحدث تعديلًا ثم إنشاءً، ثم كاسر تعادل بالـ id
                      items.sort((a, b) {
                        final au = a.updatedAt.millisecondsSinceEpoch ?? 0;
                        final bu = b.updatedAt.millisecondsSinceEpoch ?? 0;
                        final cmpU = bu.compareTo(au);
                        if (cmpU != 0) return cmpU;

                        final ac = a.createdAt.millisecondsSinceEpoch ?? 0;
                        final bc = b.createdAt.millisecondsSinceEpoch ?? 0;
                        final cmpC = bc.compareTo(ac);
                        if (cmpC != 0) return cmpC;

                        return b.id.compareTo(a.id);
                      });

                      if (items.isEmpty) {
                        return Center(
                          child: Text('لا يوجد مستأجرون',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final t = items[i];
                          return KeyedSubtree(
                              key: ValueKey(t.id),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16.r),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TenantDetailsScreen(tenant: t),
                                    ),
                                  );
                                },
                                onLongPress: () async {
                                  // 🚫 منع عميل المكتب من الأرشفة بالضغط المطوّل
                                  if (await OfficeClientGuard
                                      .blockIfOfficeClient(context)) {
                                    return;
                                  }

                                  _tryArchive(t); // ✅ ضغط مطوّل للأرشفة
                                },
                                child: _DarkCard(
                                  padding: EdgeInsets.all(12.w),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 52.w,
                                        height: 52.w,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12.r),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF0F766E),
                                              Color(0xFF14B8A6)
                                            ],
                                            begin: Alignment.topRight,
                                            end: Alignment.bottomLeft,
                                          ),
                                        ),
                                        child: const Icon(Icons.person_rounded,
                                            color: Colors.white),
                                      ),
                                      SizedBox(width: 12.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _limitChars(t.fullName, 48),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.cairo(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16.sp,
                                                    ),
                                                  ),
                                                ),
                                                if (t.isBlacklisted)
                                                  _chip('محظور',
                                                      bg: const Color(
                                                          0xFF7F1D1D)),
                                              ],
                                            ),
                                            SizedBox(height: 6.h),
                                            Row(
                                              children: [
                                                Icon(Icons.badge_outlined,
                                                    size: 16.sp,
                                                    color: Colors.white70),
                                                SizedBox(width: 4.w),
                                                Text(t.nationalId,
                                                    style: GoogleFonts.cairo(
                                                        color: Colors.white70,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                SizedBox(width: 10.w),
                                                Icon(Icons.call_outlined,
                                                    size: 16.sp,
                                                    color: Colors.white70),
                                                SizedBox(width: 4.w),
                                                Text(t.phone,
                                                    style: GoogleFonts.cairo(
                                                        color: Colors.white70,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                              ],
                                            ),
                                            SizedBox(height: 8.h),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _chip(
                                                  'نوع العميل: ${_clientTypeLabel(_effectiveClientType(t))}',
                                                  bg: _clientTypeColor(
                                                      _effectiveClientType(t)),
                                                ),
                                                SizedBox(height: 6.h),
                                                if (_effectiveClientType(t) ==
                                                    _clientTypeServiceProvider)
                                                  _chip(
                                                    'طلبات خدمات: ${_countProviderMaintenanceRequests(t.fullName)}',
                                                    bg: const Color(0xFF0B3D2E),
                                                  )
                                                else
                                                  _chip(
                                                    'عقود نشطة: ${t.activeContractsCount}',
                                                    bg: const Color(0xFF0B3D2E),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_left_rounded,
                                          color: Colors.white70),
                                    ],
                                  ),
                                ),
                              ));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text('إضافة مستأجر',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            try {
            // 🚫 منع عميل المكتب من إضافة مستأجر
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final limitDecision = await PackageLimitService.canAddClient();
            if (!limitDecision.allowed) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    limitDecision.message ??
                        'لا يمكن إضافة عميل جديد، لقد وصلت إلى الحد الأقصى المسموح.',
                    style: GoogleFonts.cairo(),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }

            final created = await Navigator.of(context).push<Tenant?>(
              MaterialPageRoute(builder: (_) => const AddOrEditTenantScreen()),
            );
            if (created != null) {
              // ✅ حفظ محلي سريع + طابور المزامنة (الـ Snackbar ظهر في شاشة الإضافة)
              await _box.put(created.id, created);
              _sync.enqueueUpsertTenant(created); // بدون await
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TenantDetailsScreen(tenant: created),
                ),
              );
            }
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      'تعذر التحقق من حد العملاء/المستأجرين الآن. أعد المحاولة بعد قليل.',
                      style: GoogleFonts.cairo(),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 2,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Widget _chip(String text, {Color bg = const Color(0xFF334155)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// ===== تفاصيل المستأجر =====
class TenantDetailsScreen extends StatefulWidget {
  final Tenant tenant;
  const TenantDetailsScreen({super.key, required this.tenant});

  @override
  State<TenantDetailsScreen> createState() => _TenantDetailsScreenState();
}

class _TenantDetailsScreenState extends State<TenantDetailsScreen> {
  int _providerMaintenanceCount = 0;
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');
  late Tenant _liveTenant;

  // مساعد بسيط
  T? _firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
    for (final e in it) {
      if (test(e)) return e;
    }
    return null;
  }

  // مثل منطق شاشة العقود: عند إنشاء عقد جديد
  Future<void> _onContractCreatedFromTenantFlow(
      contracts_ui.Contract c, Tenant t) async {
    await contracts_ui.linkWaterConfigToContractIfNeeded(c);

    // 1) إشغال العقار
    final Box<Property> props =
        Hive.box<Property>(scope.boxName(bx.kPropertiesBox));
    final prop = _firstWhereOrNull(props.values, (p) => p.id == c.propertyId);
    if (prop != null) {
      await _occupyProperty(prop);
    }

    // 2) زيادة عداد العقود النشطة للمستأجر (إن كان العقد نشطًا الآن)
    if (c.isActiveNow) {
      t.activeContractsCount += 1;
      t.updatedAt = KsaTime.now();

      // 1) احفظ محليًا فورًا (offline-first)
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);

      // 2) أضف للمزامنة (Firestore عندما يتوفر النت) — بدون await
      OfflineSyncService.instance.enqueueUpsertTenant(t);
    }
  }

  Future<void> _occupyProperty(Property p) async {
    if (p.parentBuildingId != null) {
      p.occupiedUnits = 1;
      await p.save();
      await _recalcBuildingOccupiedUnits(p.parentBuildingId!);
    } else {
      p.occupiedUnits = 1;
      await p.save();
    }
  }

  Future<void> _recalcBuildingOccupiedUnits(String buildingId) async {
    final Box<Property> props =
        Hive.box<Property>(scope.boxName(bx.kPropertiesBox));
    final all = props.values.where((e) => e.parentBuildingId == buildingId);
    final count = all.where((e) => e.occupiedUnits > 0).length;
    final building = _firstWhereOrNull(props.values, (e) => e.id == buildingId);
    if (building != null) {
      building.occupiedUnits = count;
      await building.save();
    }
  }

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  final _sync = OfflineSyncService.instance;

  @override
  void initState() {
    super.initState();
    _liveTenant = widget.tenant;
    _initDetailsScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  Future<void> _initDetailsScreen() async {
    await HiveService.ensureReportsBoxesOpen();
    await _refreshProviderMaintenanceCount();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshProviderMaintenanceCount() async {
    if (_effectiveClientType(widget.tenant) != _clientTypeServiceProvider) {
      _providerMaintenanceCount = 0;
      return;
    }
    await HiveService.ensureReportsBoxesOpen();
    _debugLogProviderCountDetails(widget.tenant.fullName);
    final count = _countProviderMaintenanceRequests(widget.tenant.fullName);
    if (!mounted) return;
    setState(() => _providerMaintenanceCount = count);
  }

  Future<bool> _blockArchivedContractAction(Tenant tenant) async {
    if (!tenant.isArchived ||
        _effectiveClientType(tenant) == _clientTypeServiceProvider) {
      return false;
    }
    await _showTenantBlockedActionDialog(
      context,
      message:
          'هذا العميل مؤرشف حاليًا، لذلك لا يمكن إضافة عقد جديد له قبل فك الأرشفة.\n'
          'إذا كنت تريد إعادة استخدام بياناته في عقد جديد، فقم بفك الأرشفة أولًا ثم أعد المحاولة.',
    );
    return true;
  }

  Future<bool> _blockArchivedProviderAction(Tenant tenant) async {
    if (!tenant.isArchived ||
        _effectiveClientType(tenant) != _clientTypeServiceProvider) {
      return false;
    }
    await _showTenantBlockedActionDialog(
      context,
      message:
          'مقدم الخدمة هذا مؤرشف حاليًا، لذلك لا يمكن تنفيذ أي إجراء عليه قبل فك الأرشفة.\n'
          'إذا كنت تريد استخدامه مرة أخرى في طلبات الخدمات، فقم بفك الأرشفة أولًا ثم أعد المحاولة.',
    );
    return true;
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const contracts_ui.ContractsScreen()),
        );
        break;
    }
  }

  Future<void> _toggleArchive(Tenant t) async {
    final type = _effectiveClientType(t);
    final currentProviderRequests =
        type == _clientTypeServiceProvider
            ? _countProviderMaintenanceRequests(t.fullName)
            : 0;

    if (!t.isArchived) {
      // محاولة أرشفة
      if (type == _clientTypeServiceProvider) {
        if (currentProviderRequests > 0) {
          await _showTenantBlockedActionDialog(
            context,
            message:
                'لا يمكن أرشفة مقدم الخدمة لوجود طلبات خدمات سارية مرتبطة به. يمكنك أرشفته فقط إذا لم تعد هناك طلبات خدمات سارية.',
          );
          return;
        }
      } else {
        if (t.activeContractsCount > 0) {
          await _showTenantBlockedActionDialog(
            context,
            message:
                'لا يمكن أرشفة هذا العميل لوجود عقود نشطة مرتبطة به. يمكنك أرشفته بعد إنهاء العقود النشطة.',
          );
          return;
        }
      }
      t.isArchived = true;
      t.updatedAt = KsaTime.now();

      // 1) احفظ محليًا فورًا (offline-first)
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت الأرشفة', style: GoogleFonts.cairo())),
      );
      setState(() {});
    } else {
      // فك الأرشفة
      t.isArchived = false;
      t.updatedAt = KsaTime.now();

      // 1) احفظ محليًا فورًا (offline-first)
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم فك الأرشفة', style: GoogleFonts.cairo())),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = _liveTenant;
    final isTenant = _effectiveClientType(tenant) == _clientTypeTenant;
    final isCompany = _effectiveClientType(tenant) == _clientTypeCompany;
    final isServiceProvider =
        _effectiveClientType(tenant) == _clientTypeServiceProvider;

    // ✅ اعتبر اليوم الحالي على توقيت الرياض، وقارن كتاريخ فقط
    final todayKsa = KsaTime.dateOnly(KsaTime.now());
    final idExpired = tenant.idExpiry != null &&
        KsaTime.dateOnly(tenant.idExpiry!).isBefore(todayKsa);

    return Directionality(
      textDirection: TextDirection.rtl,
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
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text('تفاصيل العميل',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: tenant.isArchived ? 'فك الأرشفة' : 'أرشفة',
              onPressed: () async {
                // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة من تفاصيل المستأجر
                if (await OfficeClientGuard.blockIfOfficeClient(context)) {
                  return;
                }

                // ✅ لو ليس عميل مكتب → نفّذ منطق الأرشفة العادي
                _toggleArchive(tenant);
              },
              icon: Icon(
                tenant.isArchived
                    ? Icons.inventory_2_rounded
                    : Icons.archive_rounded,
                color: Colors.white,
              ),
            ),
          ],
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
                    Color(0xFF14B8A6)
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
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56.w,
                              height: 56.w,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0F766E),
                                    Color(0xFF14B8A6)
                                  ],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                              ),
                              child: const Icon(Icons.person_rounded,
                                  color: Colors.white),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_limitChars(tenant.fullName, 64),
                                      style: GoogleFonts.cairo(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16.sp)),
                                  SizedBox(height: 6.h),
                                  Row(
                                    children: [
                                      Icon(Icons.badge_outlined,
                                          size: 16.sp, color: Colors.white70),
                                      SizedBox(width: 4.w),
                                      Text(
                                          _effectiveClientType(tenant) ==
                                                  _clientTypeCompany
                                              ? (tenant
                                                      .companyCommercialRegister ??
                                                  tenant.nationalId)
                                              : tenant.nationalId,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w700)),
                                      SizedBox(width: 12.w),
                                      Icon(Icons.call_outlined,
                                          size: 16.sp, color: Colors.white70),
                                      SizedBox(width: 4.w),
                                      Text(
                                          _effectiveClientType(tenant) ==
                                                  _clientTypeCompany
                                              ? (tenant
                                                      .companyRepresentativePhone ??
                                                  tenant.phone)
                                              : tenant.phone,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            _pill(
                                'نوع العميل: ${_clientTypeLabel(_effectiveClientType(tenant))}',
                                bg: _clientTypeColor(
                                    _effectiveClientType(tenant))),
                            InkWell(
                              borderRadius: BorderRadius.circular(10.r),
                              onTap: () => _effectiveClientType(tenant) ==
                                      _clientTypeServiceProvider
                                  ? _openProviderMaintenanceRequests(
                                      context, tenant)
                                  : _openTenantContracts(context, tenant),
                              child: _pill(
                                _effectiveClientType(tenant) ==
                                        _clientTypeServiceProvider
                                    ? 'طلبات خدمات: $_providerMaintenanceCount'
                                    : 'عقود نشطة: ${tenant.activeContractsCount}',
                                bg: const Color(0xFF0B3D2E),
                              ),
                            ),
                            if (_effectiveClientType(tenant) ==
                                    _clientTypeTenant &&
                                (tenant.nationality ?? '').isNotEmpty)
                              _pill(tenant.nationality!),
                            if (_effectiveClientType(tenant) ==
                                    _clientTypeTenant &&
                                tenant.idExpiry != null)
                              _pill(
                                'انتهاء الهوية: ${_fmtDateDynamic(tenant.idExpiry!)}'
                                '${idExpired ? " (منتهية)" : ""}',
                                bg: idExpired
                                    ? const Color(0xFF7F1D1D)
                                    : const Color(0xFF1E293B),
                              ),
                            if (tenant.isBlacklisted)
                              _pill('محظور', bg: const Color(0xFF7F1D1D)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 10.h),

                  // بيانات أساسية
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('بيانات أساسية'),
                        if (_effectiveClientType(tenant) == _clientTypeCompany)
                          _rowInfo(
                            'رقم السجل التجاري',
                            (tenant.companyCommercialRegister ?? '')
                                    .trim()
                                    .isEmpty
                                ? tenant.nationalId
                                : tenant.companyCommercialRegister,
                          )
                        else
                          _rowInfo('رقم الهوية', tenant.nationalId),
                        if (isTenant) ...[
                          _rowInfo('الجنسية', tenant.nationality),
                          _rowInfo(
                            'تاريخ انتهاء الهوية',
                            tenant.idExpiry == null
                                ? null
                                : _fmtDateDynamic(tenant.idExpiry!),
                          ),
                          _rowInfo('ملاحظات', tenant.notes),
                        ],
                        if (isCompany) ...[
                          _rowInfo('اسم الشركة', tenant.companyName),
                          _rowInfo('الرقم الضريبي', tenant.companyTaxNumber),
                          _rowInfo('اسم ممثل الشركة',
                              tenant.companyRepresentativeName),
                          _rowInfo(
                              'رقم الجوال', tenant.companyRepresentativePhone),
                        ],
                        if (isServiceProvider) ...[
                          _rowInfo('الاسم الكامل', tenant.fullName),
                          _rowInfo('رقم الجوال', tenant.phone),
                          _rowInfo('التخصص', tenant.serviceSpecialization),
                          _rowInfo('ملاحظات', tenant.notes),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),

                  // التواصل
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('التواصل'),
                        _rowInfo('البريد الإلكتروني', tenant.email),
                        if (isTenant)
                          _rowInfo(
                            'تاريخ الميلاد',
                            tenant.dateOfBirth == null
                                ? null
                                : _fmtDateDynamic(tenant.dateOfBirth!),
                          ),
                        if (isCompany)
                          _rowInfo('جوال ممثل الشركة',
                              tenant.companyRepresentativePhone),
                        if (isServiceProvider)
                          _rowInfo('رقم الجوال', tenant.phone),
                        if (isTenant)
                          _rowInfo('رقم الجوال', tenant.phone),
                      ],
                    ),
                  ),
                  if (isTenant) ...[
                    SizedBox(height: 10.h),
                    _DarkCard(
                      padding: EdgeInsets.all(14.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('شخص للطوارئ'),
                          _rowInfo('الاسم', tenant.emergencyName),
                          _rowInfo('الجوال', tenant.emergencyPhone),
                        ],
                      ),
                    ),
                  ],
                  if (tenant.attachmentPaths.isNotEmpty) ...[
                    SizedBox(height: 10.h),
                    _DarkCard(
                      padding: EdgeInsets.all(14.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                              'المرفقات (${tenant.attachmentPaths.length}/3)'),
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 8.w,
                            runSpacing: 8.h,
                            children: tenant.attachmentPaths.map((path) {
                              return InkWell(
                                onTap: () => _showAttachmentActions(path),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10.r),
                                  child: Container(
                                    width: 92.w,
                                    height: 92.w,
                                    color: Colors.white.withOpacity(0.08),
                                    child: _buildAttachmentThumb(path),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: EntityAuditInfoButton(
                      collectionName: 'tenants',
                      entityId: tenant.id,
                    ),
                  ),

                  // أزرار الإجراءات
                  SizedBox(height: 8.h),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8.w,
                      children: [
                        _miniAction(
                          icon: Icons.edit_rounded,
                          label: 'تعديل',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من التعديل
                            if (await OfficeClientGuard.blockIfOfficeClient(
                                context)) {
                              return;
                            }
                            if (await _blockArchivedProviderAction(tenant)) {
                              return;
                            }

                            final updated =
                                await Navigator.of(context).push<Tenant?>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AddOrEditTenantScreen(existing: tenant),
                              ),
                            );
                            if (updated != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تم تحديث "${tenant.fullName}"',
                                      style: GoogleFonts.cairo()),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              setState(
                                  () => _liveTenant = updated); // تحديث العرض
                            }
                          },
                        ),
                        _miniAction(
                          icon: Icons.description_outlined,
                          label: 'الملاحظات',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من تعديل الملاحظات
                            if (await OfficeClientGuard.blockIfOfficeClient(
                                context)) {
                              return;
                            }
                            if (await _blockArchivedProviderAction(tenant)) {
                              return;
                            }

                            _showNotesSheet(context, tenant);
                          },
                          bg: const Color(0xFF334155),
                        ),
                        _miniAction(
                          icon: Icons.note_add_outlined,
                          label: _effectiveClientType(tenant) ==
                                  _clientTypeServiceProvider
                              ? 'إضافة طلب'
                              : 'إضافة عقد',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من الإجراء
                            if (await OfficeClientGuard.blockIfOfficeClient(
                                context)) {
                              return;
                            }
                            if (_effectiveClientType(tenant) ==
                                    _clientTypeServiceProvider &&
                                await _blockArchivedProviderAction(tenant)) {
                              return;
                            }
                            if (_effectiveClientType(tenant) !=
                                    _clientTypeServiceProvider &&
                                await _blockArchivedContractAction(tenant)) {
                              return;
                            }

                            if (_effectiveClientType(tenant) ==
                                _clientTypeServiceProvider) {
                              _goToAddMaintenance(context, tenant);
                            } else {
                              _goToAddContract(context, tenant);
                            }
                          },
                          bg: const Color(0xFF0EA5E9),
                        ),
                        if (_effectiveClientType(tenant) !=
                            _clientTypeServiceProvider)
                          Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: _miniAction(
                              icon: Icons.history_rounded,
                              label: 'عقود سابقة',
                              onTap: () async {
                                await Navigator.pushNamed(
                                  context,
                                  '/contracts',
                                  arguments: {
                                    'filterPreviousTenantId': tenant.id,
                                    'filterPreviousTenantName': tenant.fullName,
                                  },
                                );
                              },
                              bg: const Color(0xFF4338CA),
                            ),
                          ),
                        if (_effectiveClientType(tenant) ==
                            _clientTypeServiceProvider)
                          Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: _miniAction(
                              icon: Icons.history_rounded,
                              label: 'خدمات سابقة',
                              onTap: () async {
                                if (await _blockArchivedProviderAction(tenant)) {
                                  return;
                                }
                                await _openProviderMaintenanceHistory(
                                    context, tenant);
                              },
                              bg: const Color(0xFF4338CA),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child: _miniAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'حذف',
                            onTap: () async {
                              // 🚫 منع عميل المكتب من الحذف
                              if (await OfficeClientGuard.blockIfOfficeClient(
                                  context)) {
                                return;
                              }
                              if (await _blockArchivedProviderAction(tenant)) {
                                return;
                              }

                              _confirmDelete(context, tenant);
                            },
                            bg: const Color(0xFF7F1D1D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 2,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  // ======= أدوات تفاصيل =======
  Widget _pill(String text, {Color bg = const Color(0xFF1E293B)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 12.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color bg = const Color(0xFF1E293B),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16.sp, color: Colors.white),
            SizedBox(width: 6.w),
            Text(
              label,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowInfo(String label, String? value) {
    final has = (value ?? '').trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              has ? value! : '—',
              style:
                  GoogleFonts.cairo(color: has ? Colors.white : Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  bool _isImageAttachment(String path) {
    final lower = path.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isRemoteAttachment(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<String> _resolveRemoteUrl(String path) async {
    if (path.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }
    return path;
  }

  Future<String> _resolveRemoteImageUrl(String path) {
    return _remoteThumbUrls.putIfAbsent(path, () => _resolveRemoteUrl(path));
  }

  Widget _buildAttachmentThumb(String path) {
    if (_isImageAttachment(path)) {
      if (_isRemoteAttachment(path)) {
        return FutureBuilder<String>(
          future: _resolveRemoteImageUrl(path),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              );
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Colors.white70,
    );
  }

  Future<void> _showAttachmentActions(String path) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: Colors.white),
                title: Text('تحميل',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: Text('مشاركة',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  String _mimeFromPath(String path) {
    final p = path.toLowerCase().split('?').first;
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close();
    }
  }

  Future<bool> _ensureDownloadPermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      if (_isImageAttachment(path)) {
        final photos = await Permission.photos.request();
        if (photos.isGranted) return true;
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;
    } catch (_) {}
    return true;
  }

  Future<bool> _saveBytesToDownloads(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    try {
      final res = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      return res != null && res.isNotEmpty;
    } catch (e, s) {
      debugPrint('[attachments] download channel failed: $e');
      debugPrint('[attachments] download channel stack: $s');
      return false;
    }
  }

  Future<Directory?> _targetDownloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (dir.existsSync()) return dir;
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _downloadAttachment(String path) async {
    try {
      debugPrint('[attachments] download start: $path');
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
        debugPrint('[attachments] download permission denied');
        _showTopNotice('يلزم إذن التخزين لتحميل الملف', isError: true);
        return;
      }
      final String name;
      Uint8List bytes;
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final uri = Uri.tryParse(url);
        name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        bytes = await _downloadBytes(url);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] download local missing');
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        name = f.path.split(Platform.pathSeparator).last;
        bytes = await f.readAsBytes();
      }

      if (Platform.isAndroid) {
        final saved =
            await _saveBytesToDownloads(bytes, name, _mimeFromPath(name));
        if (!saved) {
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        _showTopNotice('تم التحميل');
        return;
      }

      final dir = await _targetDownloadsDir();
      if (dir == null) {
        debugPrint('[attachments] download target dir is null');
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      debugPrint('[attachments] download saved: ${dest.path}');
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
      debugPrint('[attachments] share start: $path');
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final bytes = await _downloadBytes(url);
        final uri = Uri.tryParse(url);
        final name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        await Share.shareXFiles([
          XFile.fromData(bytes, name: name, mimeType: _mimeFromPath(name)),
        ]);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] share local missing');
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        debugPrint('[attachments] share local path: ${f.path}');
        await Share.shareXFiles(
            [XFile(f.path, mimeType: _mimeFromPath(f.path))]);
      }
    } catch (e, s) {
      debugPrint('[attachments] share failed: $e');
      debugPrint('[attachments] share stack: $s');
      _showTopNotice('تعذر مشاركة المرفق', isError: true);
    }
  }

  void _showTopNotice(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 12;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable =
            await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      Uri? uri;
      if (_isRemoteAttachment(launchable)) {
        uri = Uri.tryParse(launchable);
      } else {
        final f = File(launchable);
        if (!f.existsSync()) throw Exception('attachment missing');
        uri = Uri.file(f.path);
      }
      if (uri == null) throw Exception('bad uri');

      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _openTenantContracts(BuildContext context, Tenant t) async {
    // نحاول أولًا عبر المسار المسمى إن كان مضافًا في MaterialApp.routes
    try {
      await Navigator.of(context)
          .pushNamed('/contracts', arguments: {'filterTenantId': t.id});
      return;
    } catch (_) {
      // لو المسار غير معرّف، نعمل fallback بفتح ContractsScreen وتمرير نفس الـ arguments
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const contracts_ui.ContractsScreen(),
        settings: RouteSettings(arguments: {'filterTenantId': t.id}),
      ),
    );
  }

  Future<void> _openProviderMaintenanceRequests(
      BuildContext context, Tenant t) async {
    final args = <String, dynamic>{
      'filterAssignedTo': t.fullName,
      'filterClientType': _clientTypeServiceProvider,
      'providerRequestsView': 'current',
    };
    try {
      await Navigator.of(context).pushNamed('/maintenance', arguments: args);
      await _refreshProviderMaintenanceCount();
      return;
    } catch (_) {}
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const maintenance_ui.MaintenanceScreen(),
        settings: RouteSettings(arguments: args),
      ),
    );
    await _refreshProviderMaintenanceCount();
  }

  Future<void> _openProviderMaintenanceHistory(
      BuildContext context, Tenant t) async {
    final args = <String, dynamic>{
      'filterAssignedTo': t.fullName,
      'filterClientType': _clientTypeServiceProvider,
      'providerRequestsView': 'history',
    };
    try {
      await Navigator.of(context).pushNamed('/maintenance', arguments: args);
      await _refreshProviderMaintenanceCount();
      return;
    } catch (_) {}
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const maintenance_ui.MaintenanceScreen(),
        settings: RouteSettings(arguments: args),
      ),
    );
    await _refreshProviderMaintenanceCount();
  }

  void _showNotesSheet(BuildContext context, Tenant t) {
    final controller = TextEditingController(text: (t.notes ?? '').trim());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16.w,
            16.h,
            16.w,
            16.h + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white70),
                  SizedBox(width: 8.w),
                  Text(
                    'الملاحظات',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: controller,
                maxLines: 6,
                buildCounter: (context,
                    {required int? currentLength,
                    required bool? isFocused,
                    required int? maxLength}) {
                  if (maxLength == null) return null;
                  final cur = currentLength ?? 0;
                  if (cur >= maxLength) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'هذا أقصى حد ($maxLength)',
                        style: GoogleFonts.cairo(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب ملاحظات المستأجر هنا…',
                  hintStyle: GoogleFonts.cairo(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final txt = controller.text.trim();
                        t.notes = txt.isEmpty ? null : txt;
                        t.updatedAt = KsaTime.now();

                        // 1) احفظ محليًا فورًا (offline-first)
                        final box =
                            Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
                        await box.put(t.id, t);

                        // 2) أضف للمزامنة — بدون await
                        _sync.enqueueUpsertTenant(t);

                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم حفظ الملاحظات',
                                  style: GoogleFonts.cairo()),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          setState(() {}); // حدّث العرض بعد الحفظ
                        }
                      },
                      child: Text('حفظ',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _goToAddContract(BuildContext context, Tenant t) async {
    if (await _blockArchivedContractAction(t)) {
      return;
    }
    try {
      // نمرر المفتاح المتوافق مع شاشة العقود
      final created = await Navigator.of(context).pushNamed(
        '/contracts/new',
        arguments: {
          'prefillTenantId': t.id, // ← المفتاح الصحيح
        },
      ) as contracts_ui.Contract?;

      // لو رجع عقد، خزّنه وكمّل تحديثات الحالة
      if (created != null) {
        final cname = HiveService.contractsBoxName();
        final Box<contracts_ui.Contract> contractsBox =
            Hive.box<contracts_ui.Contract>(cname);
        await contractsBox.add(created);

        await _onContractCreatedFromTenantFlow(created, t);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة العقد', style: GoogleFonts.cairo()),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // (اختياري) افتح تفاصيل العقد مباشرة
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                contracts_ui.ContractDetailsScreen(contract: created),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'مسار إضافة العقد غير مهيأ بعد. اربطه بالمسار /contracts/new.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _goToAddMaintenance(BuildContext context, Tenant t) async {
    if (await _blockArchivedProviderAction(t)) {
      return;
    }
    try {
      await Navigator.of(context).pushNamed(
        '/maintenance/new',
        arguments: {
          'prefillProviderId': t.id,
          'prefillProviderName': t.fullName,
          'prefillProviderLocked': true,
        },
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'مسار إضافة طلب الخدمات غير مهيأ بعد. اربطه بالمسار /maintenance/new.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Tenant t) async {
    final type = _effectiveClientType(t);
    if (type == _clientTypeServiceProvider) {
      final currentRequests = _countProviderMaintenanceRequests(t.fullName);
      final allRequests = _countProviderAllMaintenanceRequests(t.fullName);
      if (allRequests > 0) {
        await _showTenantBlockedActionDialog(
          context,
          message: currentRequests > 0
              ? 'لا يمكن حذف مقدم الخدمة لوجود طلبات خدمات سارية أو خدمات سابقة مرتبطة به. يجب حذفها من النظام تمامًا أولًا. ويمكنك أرشفة مقدم الخدمة إذا لم تعد هناك طلبات خدمات سارية.'
              : 'لا يمكن حذف مقدم الخدمة لوجود خدمات سابقة مرتبطة به. يجب حذفها من النظام تمامًا أولًا. ويمكنك أرشفة مقدم الخدمة إذا لم تعد هناك طلبات خدمات سارية.',
        );
        return;
      }
    } else {
      final allContracts = _countTenantAllContracts(t.id);
      if (allContracts > 0 || t.activeContractsCount > 0) {
        await _showTenantBlockedActionDialog(
          context,
          message: t.activeContractsCount > 0
              ? 'إذا كانت هناك عقود نشطة أو سابقة لهذا العميل فلا يمكن حذفه إلا بعد حذفها من النظام تمامًا. ويمكنك أرشفة العميل إذا لم تعد هناك عقود نشطة مرتبطة به.'
              : 'إذا كانت هناك عقود سابقة لهذا العميل فلا يمكن حذفه إلا بعد حذفها من النظام تمامًا. ويمكنك أرشفة العميل إذا لم تعد هناك عقود نشطة مرتبطة به.',
        );
        return;
      }
    }

    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل تريد حذف "${t.fullName}"؟',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );

    if (!ok) return;

    // 4) الحذف الفعلي من Hive + المزامنة
    final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
    await box.delete(t.id);

    _sync.enqueueDeleteTenantSoft(t.id); // حذف سوفت للمزامنة مع السحابة

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف "${t.fullName}"',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// ===== شاشة إضافة/تعديل مستأجر =====
class AddOrEditTenantScreen extends StatefulWidget {
  final Tenant? existing; // إن وُجد => تعديل
  const AddOrEditTenantScreen({super.key, this.existing});

  @override
  State<AddOrEditTenantScreen> createState() => _AddOrEditTenantScreenState();
}

class _AddOrEditTenantScreenState extends State<AddOrEditTenantScreen> {
  final _formKey = GlobalKey<FormState>();

  final _sync = OfflineSyncService.instance;

  // Bottom nav + drawer ضبط
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  // حقول + قيود
  final _fullName = TextEditingController(); // حد 50، حروف ومسافات فقط
  final _nationalId = TextEditingController(); // أرقام فقط حد 10
  final _phone = TextEditingController(); // أرقام فقط حد 10
  final _email = TextEditingController(); // حد 40، ASCII، بدون مسافات
  final _nationality = TextEditingController(); // حروف ومسافات فقط حد 20
  final _emgName = TextEditingController(); // حروف ومسافات فقط حد 50
  final _emgPhone = TextEditingController(); // أرقام فقط حد 10
  final _notes = TextEditingController(); // حد 300
  final _tenantBankName = TextEditingController();
  final _tenantBankAccountNumber = TextEditingController();
  final _tenantTaxNumber = TextEditingController();
  final _companyName = TextEditingController();
  final _companyCommercialRegister = TextEditingController();
  final _companyTaxNumber = TextEditingController();
  final _companyRepresentativeName = TextEditingController();
  final _companyRepresentativePhone = TextEditingController();
  final _companyBankAccountNumber = TextEditingController();
  final _companyBankName = TextEditingController();
  final _serviceSpecialization = TextEditingController();
  String _clientType = _clientTypeTenant;
  final List<String> _attachments = <String>[];
  final Set<String> _initialLocalAttachments = <String>{};
  bool _uploadingAttachments = false;
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  DateTime? _idExpiry;
  DateTime? _dateOfBirth;
  // منع تجاوز الحد + تنبيه قصير
  DateTime? _lastExceedShownAt;

  void _showTempSnack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  TextInputFormatter _limitWithFeedbackFormatter({
    required int max,
    required String exceedMsg,
  }) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.length > max) {
        final now = KsaTime.now();
        if (_lastExceedShownAt == null ||
            now.difference(_lastExceedShownAt!).inMilliseconds > 800) {
          _lastExceedShownAt = now;
          _showTempSnack(exceedMsg);
        }
        return oldValue; // يمنع الكتابة الزائدة فورًا
      }
      return newValue;
    });
  }

  Box<Tenant> get _box => Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));

  @override
  void initState() {
    super.initState();
    HiveService.ensureReportsBoxesOpen();

    // ارتفاع البوتوم ناف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });

    final t = widget.existing;
    if (t != null) {
      _clientType = _effectiveClientType(t);
      _fullName.text = t.fullName;
      _nationalId.text = t.nationalId;
      _phone.text = t.phone;
      _email.text = t.email ?? '';
      _nationality.text = t.nationality ?? '';
      _idExpiry = t.idExpiry;
      _dateOfBirth = t.dateOfBirth;
      _emgName.text = t.emergencyName ?? '';
      _emgPhone.text = t.emergencyPhone ?? '';
      _notes.text = t.notes ?? '';
      _tenantBankName.text = t.tenantBankName ?? '';
      _tenantBankAccountNumber.text = t.tenantBankAccountNumber ?? '';
      _tenantTaxNumber.text = t.tenantTaxNumber ?? '';
      _companyName.text = t.companyName ?? '';
      _companyCommercialRegister.text = t.companyCommercialRegister ?? '';
      _companyTaxNumber.text = t.companyTaxNumber ?? '';
      _companyRepresentativeName.text = t.companyRepresentativeName ?? '';
      _companyRepresentativePhone.text = t.companyRepresentativePhone ?? '';
      _companyBankAccountNumber.text = t.companyBankAccountNumber ?? '';
      _companyBankName.text = t.companyBankName ?? '';
      _serviceSpecialization.text = t.serviceSpecialization ?? '';
      _attachments
        ..clear()
        ..addAll(t.attachmentPaths);
      _initialLocalAttachments
        ..clear()
        ..addAll(_attachments.where((path) => !_isRemoteAttachment(path)));
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const contracts_ui.ContractsScreen()),
        );
        break;
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _nationalId.dispose();
    _phone.dispose();
    _email.dispose();
    _nationality.dispose();
    _emgName.dispose();
    _emgPhone.dispose();
    _notes.dispose();
    _tenantBankName.dispose();
    _tenantBankAccountNumber.dispose();
    _tenantTaxNumber.dispose();
    _companyName.dispose();
    _companyCommercialRegister.dispose();
    _companyTaxNumber.dispose();
    _companyRepresentativeName.dispose();
    _companyRepresentativePhone.dispose();
    _companyBankAccountNumber.dispose();
    _companyBankName.dispose();
    _serviceSpecialization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return WillPopScope(
      onWillPop: () async => !_uploadingAttachments,
      child: AbsorbPointer(
        absorbing: _uploadingAttachments,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
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
            appBar: AppBar(
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              leading: darvooLeading(context, iconColor: Colors.white),
              title: Text(isEdit ? 'تعديل عميل' : 'إضافة عميل',
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
                        Color(0xFF14B8A6)
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
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                  child: _DarkCard(
                    padding: EdgeInsets.all(16.w),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _clientType,
                            decoration: _dd('نوع العميل'),
                            dropdownColor: const Color(0xFF0F172A),
                            iconEnabledColor: Colors.white70,
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                            items: const [
                              DropdownMenuItem(
                                  value: _clientTypeTenant,
                                  child: Text('مستأجر')),
                              DropdownMenuItem(
                                  value: _clientTypeCompany,
                                  child: Text('مستأجر (شركة)')),
                              DropdownMenuItem(
                                  value: _clientTypeServiceProvider,
                                  child: Text('مقدم خدمة')),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _clientType = _normalizeClientType(v);
                              });
                            },
                            validator: _req,
                          ),
                          SizedBox(height: 12.h),
                          if (_normalizeClientType(_clientType) !=
                              _clientTypeCompany) ...[
                            // الاسم الكامل (50)
                            _field(
                              controller: _fullName,
                              label: 'الاسم الكامل',
                              maxLength: 50,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r"[a-zA-Z\u0600-\u06FF ]"),
                                ),
                              ],
                              validator: (v) {
                                if ((v ?? '').trim().isEmpty) {
                                  return 'هذا الحقل مطلوب';
                                }
                                final s = v!.trim();
                                final ok = RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$")
                                    .hasMatch(s);
                                if (!ok) {
                                  return 'الاسم يجب أن يكون حروفًا ومسافات فقط';
                                }
                                if (s.length > 50) {
                                  return 'الحد الأقصى 50 حرفًا';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 10.h),

                            // الهوية + الجوال
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    controller: _nationalId,
                                    label: _normalizeClientType(_clientType) ==
                                            _clientTypeServiceProvider
                                        ? 'رقم الهوية (اختياري)'
                                        : 'رقم الهوية',
                                    keyboardType: TextInputType.number,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    validator: (v) {
                                      if (_normalizeClientType(_clientType) ==
                                          _clientTypeServiceProvider) {
                                        if ((v ?? '').trim().isEmpty) {
                                          return null;
                                        }
                                      } else if ((v ?? '').isEmpty) {
                                        return 'هذا الحقل مطلوب';
                                      }
                                      if (!RegExp(r'^\d{1,10}$').hasMatch(v!)) {
                                        return 'الهوية أرقام فقط وبحد أقصى 10 رقمًا';
                                      }
                                      final currentId = widget.existing?.id;
                                      final dup = _box.values.any(
                                        (t) =>
                                            t.nationalId == v &&
                                            (currentId == null ||
                                                t.id != currentId),
                                      );
                                      if (dup) return 'الهوية مسجلة مسبقآ';
                                      return null;
                                    },
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: _field(
                                    controller: _phone,
                                    label: 'الجوال',
                                    keyboardType: TextInputType.number,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    validator: (v) {
                                      if ((v ?? '').isEmpty) {
                                        return 'هذا الحقل مطلوب';
                                      }
                                      if (!RegExp(r'^\d{1,10}$').hasMatch(v!)) {
                                        return 'الجوال أرقام فقط وبحد أقصى 10 رقمًا';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12.h),

                            if (_normalizeClientType(_clientType) !=
                                _clientTypeServiceProvider) ...[
                              // الجنسية (20)
                              _field(
                                controller: _nationality,
                                label: 'الجنسية (اختياري)',
                                maxLength: 20,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r"[a-zA-Z\u0600-\u06FF ]"),
                                  ),
                                ],
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return null;
                                  final ok =
                                      RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$")
                                          .hasMatch(s);
                                  if (!ok) return 'الجنسية حروف ومسافات فقط';
                                  if (s.length > 20) {
                                    return 'الحد الأقصى 20 حرفًا';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 12.h),
                            ],

                            // البريد الإلكتروني (40، ASCII بدون مسافات) — إصلاح الحد
                            _field(
                              controller: _email,
                              label: 'البريد الإلكتروني (اختياري)',
                              keyboardType: TextInputType.emailAddress,
                              maxLength: 40,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) return null;
                                if (s.length > 40) return 'الحد الأقصى 40 حرف';
                                final emailRx = RegExp(
                                    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
                                if (!emailRx.hasMatch(s)) {
                                  return 'صيغة بريد غير صحيحة (إنجليزي فقط وبدون مسافات)';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 12.h),

                            if (_normalizeClientType(_clientType) ==
                                _clientTypeTenant) ...[
                              // تاريخ الميلاد (اختياري)
                              InkWell(
                                borderRadius: BorderRadius.circular(12.r),
                                onTap: _pickDateOfBirth,
                                child: InputDecorator(
                                  decoration: _dd('تاريخ الميلاد (اختياري)'),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.cake_outlined,
                                          color: Colors.white70),
                                      SizedBox(width: 8.w),
                                      Text(
                                        _dateOfBirth == null
                                            ? '—'
                                            : _fmtDateDynamic(_dateOfBirth!),
                                        style: GoogleFonts.cairo(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 12.h),
                            ],

                            if (_normalizeClientType(_clientType) !=
                                _clientTypeServiceProvider) ...[
                              // تاريخ انتهاء الهوية
                              InkWell(
                                borderRadius: BorderRadius.circular(12.r),
                                onTap: _pickIdExpiry,
                                child: InputDecorator(
                                  decoration:
                                      _dd('تاريخ انتهاء الهوية (اختياري)'),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.event_outlined,
                                          color: Colors.white70),
                                      SizedBox(width: 8.w),
                                      Text(
                                        _idExpiry == null
                                            ? '—'
                                            : _fmtDateDynamic(_idExpiry!),
                                        style: GoogleFonts.cairo(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 12.h),
                            ],
                          ],
                          if (_normalizeClientType(_clientType) ==
                              _clientTypeTenant) ...[
                            _sectionTitle('جهة اتصال للطوارئ'),
                            Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    controller: _emgName,
                                    label: 'الاسم (اختياري)',
                                    maxLength: 50,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r"[a-zA-Z\u0600-\u06FF ]"),
                                      ),
                                    ],
                                    validator: (v) {
                                      final s = (v ?? '').trim();
                                      if (s.isEmpty) return null;
                                      if (!RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$")
                                          .hasMatch(s)) {
                                        return 'الاسم حروف ومسافات فقط';
                                      }
                                      if (s.length > 50) {
                                        return 'الحد الأقصى 50 حرفًا';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: _field(
                                    controller: _emgPhone,
                                    label: 'الجوال (اختياري)',
                                    keyboardType: TextInputType.number,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    validator: (v) {
                                      final s = (v ?? '').trim();
                                      if (s.isEmpty) return null;
                                      if (!RegExp(r'^\d{1,10}$').hasMatch(s)) {
                                        return 'أرقام فقط وبحد أقصى 10 رقمًا';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12.h),
                          ],
                          if (_normalizeClientType(_clientType) !=
                              _clientTypeCompany) ...[
                            _field(
                              controller: _notes,
                              label: 'ملاحظات (اختياري — حد أقصى 300)',
                              maxLines: 3,
                              maxLength: 300,
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.length > 300) {
                                  return 'الحد الأقصى 300 حرف';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16.h),
                          ],
                          if (_normalizeClientType(_clientType) ==
                              _clientTypeCompany) ...[
                            _field(
                              controller: _companyName,
                              label: 'اسم الشركة',
                              validator: _req,
                            ),
                            SizedBox(height: 12.h),
                            _field(
                              controller: _companyCommercialRegister,
                              label: 'رقم السجل التجاري',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              validator: _req,
                            ),
                            SizedBox(height: 12.h),
                            _field(
                              controller: _companyTaxNumber,
                              label: 'الرقم الضريبي',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              validator: _req,
                            ),
                            SizedBox(height: 12.h),
                            _field(
                              controller: _companyRepresentativeName,
                              label: 'اسم ممثل الشركة',
                              validator: _req,
                            ),
                            SizedBox(height: 12.h),
                            _field(
                              controller: _companyRepresentativePhone,
                              label: 'رقم الجوال',
                              keyboardType: TextInputType.number,
                              maxLength: 10,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              validator: (v) {
                                if ((v ?? '').trim().isEmpty) {
                                  return 'هذا الحقل مطلوب';
                                }
                                if (!RegExp(r'^\d{1,10}$').hasMatch(v!)) {
                                  return 'الجوال أرقام فقط وبحد أقصى 10 رقمًا';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 12.h),
                          ],
                          if (_normalizeClientType(_clientType) ==
                              _clientTypeServiceProvider) ...[
                            _field(
                              controller: _serviceSpecialization,
                              label: 'التخصص/الخدمة',
                              validator: _req,
                            ),
                            SizedBox(height: 12.h),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _clientTypeRequiresAttachments(_clientType)
                                      ? 'المرفقات (${_attachments.length}/3)'
                                      : 'المرفقات (${_attachments.length}/3) - اختياري',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0EA5E9),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _uploadingAttachments
                                    ? null
                                    : _pickAttachments,
                                icon: _uploadingAttachments
                                    ? SizedBox(
                                        width: 16.w,
                                        height: 16.w,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.attach_file_rounded),
                                label: Text('إرفاق',
                                    style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          if (_attachments.isNotEmpty) ...[
                            Wrap(
                              spacing: 8.w,
                              runSpacing: 8.h,
                              children: _attachments.map((path) {
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    InkWell(
                                      onTap: () => _showAttachmentActions(path),
                                      borderRadius: BorderRadius.circular(10.r),
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        child: Container(
                                          width: 88.w,
                                          height: 88.w,
                                          color: Colors.white.withOpacity(0.08),
                                          child: _buildAttachmentThumb(path),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            _confirmRemoveAttachment(path),
                                        child: Container(
                                          width: 28.w,
                                          height: 28.w,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFB91C1C),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 16.sp,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 16.h),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r)),
                              ),
                              onPressed: _save,
                              icon: const Icon(Icons.check),
                              label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_uploadingAttachments)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: false,
                      child: Container(
                        color: Colors.black.withOpacity(0.30),
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 18.w, vertical: 14.h),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.90),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20.w,
                                height: 20.w,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2.4),
                              ),
                              SizedBox(width: 10.w),
                              Text(
                                'جاري المعالجة...',
                                style: GoogleFonts.cairo(
                                  color: const Color(0xFF111827),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: AppBottomNav(
              key: _bottomNavKey,
              currentIndex: 2,
              onTap: _handleBottomTap,
            ),
          ),
        ),
      ),
    );
  }

  // ===== أدوات شاشة الإضافة/التعديل =====
  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
  }) {
    final fmts = <TextInputFormatter>[];
    if (inputFormatters != null) fmts.addAll(inputFormatters);
    if (maxLength != null) {
      fmts.add(_limitWithFeedbackFormatter(
        max: maxLength,
        exceedMsg: 'تجاوزت الحد الأقصى ($maxLength)',
      ));
    }

    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: fmts,
      maxLines: maxLines,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: _dd(label),
    );
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  bool _isImageAttachment(String path) {
    final lower = path.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isRemoteAttachment(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<String> _resolveRemoteUrl(String path) async {
    if (path.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }
    return path;
  }

  Future<String> _resolveRemoteImageUrl(String path) {
    return _remoteThumbUrls.putIfAbsent(path, () => _resolveRemoteUrl(path));
  }

  Widget _buildAttachmentThumb(String path) {
    if (_isImageAttachment(path)) {
      if (_isRemoteAttachment(path)) {
        return FutureBuilder<String>(
          future: _resolveRemoteImageUrl(path),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              );
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Colors.white70,
    );
  }

  Future<void> _showAttachmentActions(String path) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: Colors.white),
                title: Text('تحميل',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: Text('مشاركة',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  String _mimeFromPath(String path) {
    final p = path.toLowerCase().split('?').first;
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close();
    }
  }

  Future<bool> _ensureDownloadPermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      if (_isImageAttachment(path)) {
        final photos = await Permission.photos.request();
        if (photos.isGranted) return true;
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;
    } catch (_) {}
    return true;
  }

  Future<bool> _saveBytesToDownloads(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    try {
      final res = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      return res != null && res.isNotEmpty;
    } catch (e, s) {
      debugPrint('[attachments] download channel failed: $e');
      debugPrint('[attachments] download channel stack: $s');
      return false;
    }
  }

  Future<Directory?> _targetDownloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (dir.existsSync()) return dir;
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _downloadAttachment(String path) async {
    try {
      debugPrint('[attachments] download start: $path');
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
        debugPrint('[attachments] download permission denied');
        _showTopNotice('يلزم إذن التخزين لتحميل الملف', isError: true);
        return;
      }
      final String name;
      Uint8List bytes;
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final uri = Uri.tryParse(url);
        name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        bytes = await _downloadBytes(url);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] download local missing');
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        name = f.path.split(Platform.pathSeparator).last;
        bytes = await f.readAsBytes();
      }

      if (Platform.isAndroid) {
        final saved =
            await _saveBytesToDownloads(bytes, name, _mimeFromPath(name));
        if (!saved) {
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        _showTopNotice('تم التحميل');
        return;
      }

      final dir = await _targetDownloadsDir();
      if (dir == null) {
        debugPrint('[attachments] download target dir is null');
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      debugPrint('[attachments] download saved: ${dest.path}');
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
      debugPrint('[attachments] share start: $path');
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final bytes = await _downloadBytes(url);
        final uri = Uri.tryParse(url);
        final name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        await Share.shareXFiles([
          XFile.fromData(bytes, name: name, mimeType: _mimeFromPath(name)),
        ]);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] share local missing');
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        debugPrint('[attachments] share local path: ${f.path}');
        await Share.shareXFiles(
            [XFile(f.path, mimeType: _mimeFromPath(f.path))]);
      }
    } catch (e, s) {
      debugPrint('[attachments] share failed: $e');
      debugPrint('[attachments] share stack: $s');
      _showTopNotice('تعذر مشاركة المرفق', isError: true);
    }
  }

  void _showTopNotice(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 12;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable =
            await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      Uri? uri;
      if (_isRemoteAttachment(launchable)) {
        uri = Uri.tryParse(launchable);
      } else {
        final f = File(launchable);
        if (!f.existsSync()) throw Exception('attachment missing');
        uri = Uri.file(f.path);
      }
      if (uri == null) throw Exception('bad uri');

      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<String?> _uploadAttachmentToStorage(
    File localFile,
    String fileName,
  ) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('tenant_attachments')
          .child(fileName);
      await ref.putFile(localFile);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}tenant_attachments');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName =
          '${KsaTime.now().microsecondsSinceEpoch}_${safeName.isEmpty ? 'doc' : safeName}';
      final outFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (file.bytes != null) {
        await outFile.writeAsBytes(file.bytes!, flush: true);
        return outFile.path;
      }
      final src = file.path;
      if (src != null && src.isNotEmpty) {
        await File(src).copy(outFile.path);
        return outFile.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3',
              style: GoogleFonts.cairo(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final remaining = 3 - _attachments.length;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final selectedFiles = picked.files.take(remaining).toList();
    if (picked.files.length > remaining && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3',
              style: GoogleFonts.cairo(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }

    setState(() => _uploadingAttachments = true);
    try {
      int failed = 0;
      for (final file in selectedFiles) {
        final localPath = await _saveAttachmentLocally(file);
        if (localPath == null) {
          failed += 1;
          continue;
        }
        if (!_attachments.contains(localPath)) {
          _attachments.add(localPath);
        }
      }
      if (failed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ $failed مرفق',
                style: GoogleFonts.cairo(color: Colors.white)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAttachments = false);
    }
  }

  List<String> _removedInitialLocalAttachments() {
    final currentPaths = _attachments
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return _initialLocalAttachments
        .where((path) => !currentPaths.contains(path))
        .toList(growable: false);
  }

  Future<void> _deleteLocalAttachments(Iterable<String> paths) async {
    final uniquePaths = paths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_isRemoteAttachment(e))
        .toSet();
    for (final path in uniquePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmRemoveAttachment(String path) async {
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف المرفق؟ لن يتم استرجاعه مجددًا.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (ok != true || !mounted) return;
    setState(() => _attachments.remove(path));
  }

  Future<void> _pickIdExpiry() async {
    final nowKsa = KsaTime.now();
    final init = _idExpiry ?? nowKsa;
    final picked = await showDatePicker(
      context: context,
      initialDate: KsaTime.dateOnly(init),
      firstDate: DateTime(1990, 1, 1),
      lastDate: DateTime(nowKsa.year + 30, 12, 31),
      helpText: 'اختر تاريخ انتهاء الهوية',
      confirmText: 'اختيار',
      cancelText: 'إلغاء',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF0B1220),
              onSurface: Colors.white,
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: Color(0xFF0B1220)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _idExpiry = KsaTime.dateOnly(picked));
  }

  Future<void> _pickDateOfBirth() async {
    final nowKsa = KsaTime.now();
    final init = _dateOfBirth ?? DateTime(1990, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: KsaTime.dateOnly(init),
      firstDate: DateTime(1920, 1, 1),
      lastDate: nowKsa,
      helpText: 'اختر تاريخ الميلاد',
      confirmText: 'اختيار',
      cancelText: 'إلغاء',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF0B1220),
              onSurface: Colors.white,
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: Color(0xFF0B1220)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateOfBirth = KsaTime.dateOnly(picked));
    }
  }

  void _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final prepared = TenantRecordService.prepareForUpsert(
      clientType: _clientType,
      fullName: _fullName.text,
      nationalId: _nationalId.text,
      phone: _phone.text,
      email: _email.text,
      nationality: _nationality.text,
      dateOfBirth: _dateOfBirth,
      idExpiry: _idExpiry,
      emergencyName: _emgName.text,
      emergencyPhone: _emgPhone.text,
      notes: _notes.text,
      companyName: _companyName.text,
      companyCommercialRegister: _companyCommercialRegister.text,
      companyTaxNumber: _companyTaxNumber.text,
      companyRepresentativeName: _companyRepresentativeName.text,
      companyRepresentativePhone: _companyRepresentativePhone.text,
      serviceSpecialization: _serviceSpecialization.text,
      attachmentPaths: _attachments,
      existingTenants: _box.values.cast<Tenant>(),
      editingTenantId: widget.existing?.id,
    );

    final issueMessage = prepared.firstIssueMessage;
    if (issueMessage != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(issueMessage, style: GoogleFonts.cairo(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final draft = prepared.draft!;
    final normalizedType = draft.clientType;

    final isEdit = widget.existing != null;

    if (isEdit) {
      final t = widget.existing!;
      draft.applyTo(t);
      // ❌ لا نعرض/نعدل الأرشفة والحظر هنا
      t.updatedAt = KsaTime.now();

      // احفظ محليًا + صف المزامنة
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      final removedLocalAttachments = _removedInitialLocalAttachments();
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await
      await _deleteLocalAttachments(removedLocalAttachments);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التحديث', style: GoogleFonts.cairo())),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pop<Tenant>(t);
    } else {
      // إنشاء المستأجر الجديد
      final now = KsaTime.now();
      final t = draft.createNew(
        id: now.microsecondsSinceEpoch.toString(),
        now: now,
      );

      // احفظ محليًا + صف المزامنة
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_addedClientSuccessMessage(normalizedType),
                style: GoogleFonts.cairo())),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pop<Tenant>(t);
    }
  }
}
