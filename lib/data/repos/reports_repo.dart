// lib/data/repos/reports_repo.dart
//
// مستودع شاشة التقارير: يجمع الأرقام من Firestore لمسارات المستخدم:
// users/{uid}/tenants | properties | contracts | invoices | maintenance
//
// يوفر:
// - ReportsRepo.loadOnce(filters)            ← إحضار لقطة واحدة
// - ReportsRepo.startReportsListener(... )   ← استماع لحظي وإعادة حساب تلقائي
// - ReportsRepo.stop()                       ← إيقاف الاستماع
//
// ملاحظات:
// - يعتمد على UserCollections (كما في بقية الريبوّات).
// - مرن في قراءة الحقول (يدعم أسماء مختلفة/قديمة).
// - استخدم ReportsFilters لتحديد الفترة + خيار includeArchived.
// - إن كانت لديك حقول/أسماء مختلفة جذريًا، عدّل دوال _read/_try* ومواضع القراءة المشار لها بـ TODO.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_user_collections.dart';

/// فلاتر/إعدادات التقارير
class ReportsFilters {
  final DateTime? from;            // بداية الفترة (اختياري)
  final DateTime? to;              // نهاية الفترة (اختياري)
  final bool includeArchived;      // هل تُظهر المؤرشف؟

  const ReportsFilters({
    this.from,
    this.to,
    this.includeArchived = false,
  });

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

/// ناتج التجميع لشاشة التقارير
class ReportsData {
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

  final int invoicesTotal;
  final int invoicesFromContracts;
  final int invoicesFromMaintenance;

  final int maintenanceNew;
  final int maintenanceInProgress;
  final int maintenanceDone;

  int get maintenanceTotal => maintenanceNew + maintenanceInProgress + maintenanceDone;

  final double financeRevenue;
  final double financeReceivables;
  final double financeExpenses;
  final double financeNet;

  const ReportsData({
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
    required this.invoicesTotal,
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

  ReportsData copyWith({
    int? propertiesCount,
    int? tenantsCount,
    int? contractsTotal,
    int? propertyUnitsOccupied,
    int? propertyUnitsVacant,
    int? tenantsBound,
    int? tenantsUnbound,
    int? activeContracts,
    int? nearExpiryContracts,
    int? endedContracts,
    int? invoicesTotal,
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
    return ReportsData(
      propertiesCount: propertiesCount ?? this.propertiesCount,
      tenantsCount: tenantsCount ?? this.tenantsCount,
      contractsTotal: contractsTotal ?? this.contractsTotal,
      propertyUnitsOccupied: propertyUnitsOccupied ?? this.propertyUnitsOccupied,
      propertyUnitsVacant: propertyUnitsVacant ?? this.propertyUnitsVacant,
      tenantsBound: tenantsBound ?? this.tenantsBound,
      tenantsUnbound: tenantsUnbound ?? this.tenantsUnbound,
      activeContracts: activeContracts ?? this.activeContracts,
      nearExpiryContracts: nearExpiryContracts ?? this.nearExpiryContracts,
      endedContracts: endedContracts ?? this.endedContracts,
      invoicesTotal: invoicesTotal ?? this.invoicesTotal,
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

  static ReportsData empty() => const ReportsData(
    propertiesCount: 0,
    tenantsCount: 0,
    contractsTotal: 0,
    propertyUnitsOccupied: 0,
    propertyUnitsVacant: 0,
    tenantsBound: 0,
    tenantsUnbound: 0,
    activeContracts: 0,
    nearExpiryContracts: 0,
    endedContracts: 0,
    invoicesTotal: 0,
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

/// Repo التجميع
class ReportsRepo {
  final UserCollections uc;

  StreamSubscription? _tenantsSub;
  StreamSubscription? _propertiesSub;
  StreamSubscription? _contractsSub;
  StreamSubscription? _invoicesSub;
  StreamSubscription? _maintenanceSub;

  // آخر بيانات خام لكل مجموعة (لنُعيد الحساب عند أي تغيّر)
  List<Map<String, dynamic>> _tenants = const [];
  List<Map<String, dynamic>> _properties = const [];
  List<Map<String, dynamic>> _contracts = const [];
  List<Map<String, dynamic>> _invoices = const [];
  List<Map<String, dynamic>> _maintenance = const [];

  ReportsRepo(this.uc);

  /// لقطة واحدة: يجلب كل المجموعات ويحسب النتائج
  Future<ReportsData> loadOnce(ReportsFilters f) async {
    final futures = await Future.wait([
      uc.tenants.get(),
      uc.properties.get(),
      uc.contracts.get(),
      uc.invoices.get(),
      uc.maintenance.get(),
    ]);

    _tenants     = futures[0].docs.map((d) => _withId(d)).toList();
    _properties  = futures[1].docs.map((d) => _withId(d)).toList();
    _contracts   = futures[2].docs.map((d) => _withId(d)).toList();
    _invoices    = futures[3].docs.map((d) => _withId(d)).toList();
    _maintenance = futures[4].docs.map((d) => _withId(d)).toList();

    return _compute(f);
  }

  /// استماع لحظي: يعيد حساب التقارير عند أي تغيّر، وينادي onData
  void startReportsListener({
    required ReportsFilters filters,
    required void Function(ReportsData data) onData,
  }) {
    stop(); // تأمين

    _tenantsSub = uc.tenants.snapshots().listen((snap) {
      _tenants = snap.docs.map((d) => _withId(d)).toList();
      onData(_compute(filters));
    });

    _propertiesSub = uc.properties.snapshots().listen((snap) {
      _properties = snap.docs.map((d) => _withId(d)).toList();
      onData(_compute(filters));
    });

    _contractsSub = uc.contracts.snapshots().listen((snap) {
      _contracts = snap.docs.map((d) => _withId(d)).toList();
      onData(_compute(filters));
    });

    _invoicesSub = uc.invoices.snapshots().listen((snap) {
      _invoices = snap.docs.map((d) => _withId(d)).toList();
      onData(_compute(filters));
    });

    _maintenanceSub = uc.maintenance.snapshots().listen((snap) {
      _maintenance = snap.docs.map((d) => _withId(d)).toList();
      onData(_compute(filters));
    });
  }

  void stop() {
    _tenantsSub?.cancel();     _tenantsSub = null;
    _propertiesSub?.cancel();  _propertiesSub = null;
    _contractsSub?.cancel();   _contractsSub = null;
    _invoicesSub?.cancel();    _invoicesSub = null;
    _maintenanceSub?.cancel(); _maintenanceSub = null;
  }

  // ----------------- الحساب الفعلي -----------------

  ReportsData _compute(ReportsFilters f) {
    // فلترة المؤرشف
    final tenants     = f.includeArchived ? _tenants : _tenants.where((m) => !(_tryBool(m['isArchived']) ?? false)).toList();
    final properties  = f.includeArchived ? _properties : _properties.where((m) => !(_tryBool(m['isArchived']) ?? false)).toList();
    final contracts   = f.includeArchived ? _contracts : _contracts.where((m) => !(_tryBool(m['isArchived']) ?? false)).toList();
    final invoices    = f.includeArchived ? _invoices : _invoices.where((m) => !(_tryBool(m['isArchived']) ?? false)).toList();
    final maintenance = f.includeArchived ? _maintenance : _maintenance.where((m) => !(_tryBool(m['isArchived']) ?? false)).toList();

    // ===== العقارات: حساب إشغال/شاغر مرن =====
    int occupiedUnits = 0, totalUnits = 0;

    for (final p in properties) {
      // إن كان لديك حقول معيّنة لنمط العقار/الوحدات عدّل هنا (TODO)
      final isBuilding = _containsAny((_tryString(p['type']) ?? '').toLowerCase(), const ['building', 'عمارة']);
      final rentalMode = (_tryString(p['rentalMode']) ?? '').toLowerCase();
      final perUnit    = isBuilding && (rentalMode.contains('unit') || rentalMode.contains('perunit') || rentalMode.contains('وحد'));

      final parentBuildingId = _tryString(p['parentBuildingId']);
      if (parentBuildingId != null && parentBuildingId.isNotEmpty) {
        // وحدة تابعة لعمارة — غالبًا تتعدّ ضمن إجمالي العمارة نفسها
        continue;
      }

      if (perUnit) {
        final units = _tryInt(p['totalUnits']) ?? 0;
        final occ   = (_tryInt(p['occupiedUnits']) ?? 0).clamp(0, units);
        totalUnits  += units;
        occupiedUnits += occ;
      } else {
        totalUnits += 1;
        final occ = (_tryInt(p['occupiedUnits']) ?? 0) > 0 ? 1 : 0;
        occupiedUnits += occ;
      }
    }
    final vacantUnits = (totalUnits - occupiedUnits).clamp(0, totalUnits);

    // ===== العقود: نشط/قارِب/منتهي =====
    final today = _today();
    final nearThreshold = today.add(const Duration(days: 30));
    int activeCtr = 0, nearCtr = 0, endedCtr = 0;

    // تجميع tenantIds النشطة لحساب bound/unbound
    final activeTenantIds = <String>{};

    for (final c in contracts) {
      final terminated = _tryBool(c['isTerminated']) ?? false;

      final start = _tryDate(c['startDate']) ?? _tryDate(c['startsOn']) ?? _tryDate(c['startAt']);
      final end   = _tryDate(c['endDate'])   ?? _tryDate(c['endsOn'])   ?? _tryDate(c['endAt']);

      final isActive = _contractIsActive(start, end, terminated, today);

      if (isActive) {
        activeCtr++;
        if (end != null) {
          final dEnd = DateTime(end.year, end.month, end.day);
          final dNow = DateTime(today.year, today.month, today.day);
          if (!dEnd.isBefore(dNow) && !dEnd.isAfter(nearThreshold)) nearCtr++;
        }
      } else {
        endedCtr++;
      }

      // tenantId من العقد (يدعم أشكال متعددة)
      final tId = _extractTenantId(c);
      if (tId != null && tId.isNotEmpty && isActive) {
        activeTenantIds.add(tId);
      }
    }

    // ===== المستأجرون: مربوط/غير مربوط =====
    int bound = 0;
    for (final t in tenants) {
      final id = _tryString(t['id']) ?? _tryString(t['tenantId']) ?? '';
      if (id.isNotEmpty && activeTenantIds.contains(id)) bound++;
    }
    int unbound = (tenants.length - bound);
    if (unbound < 0) unbound = 0;

    // ===== الفواتير: إجمالي + من عقود/صيانة + ملخص مالي =====
    int totalInv = 0, fromContracts = 0, fromMaintenance = 0;
    double rev = 0.0, recv = 0.0, exp = 0.0;

    final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);

    for (final inv in invoices) {
      totalInv++;

      final bool isMaint = _isMaintInvoiceAny(inv);
      final bool isContract = _isContractInvoiceAny(inv);
      if (isMaint) {
        fromMaintenance++;
      } else if (isContract) {
        fromContracts++;
      }

      final amount = (_tryNum(inv['amount']) ?? _tryNum(inv['total']) ?? _tryNum(inv['net']) ?? _tryNum(inv['grandTotal']) ?? 0).toDouble();

      final paidAt = _tryDate(inv['paidAt']) ?? _tryDate(inv['paid_on']) ?? _tryDate(inv['paymentDate']);
      final dueOn  = _tryDate(inv['dueOn'])  ?? _tryDate(inv['dueDate']);
      final isPaid = paidAt != null;

      final typeStr = (_tryString(inv['type']) ?? _tryString(inv['category']) ?? '').toLowerCase();
      final isExpense = (amount < 0) ||
                        typeStr.contains('expense') || typeStr.contains('مصروف') ||
                        typeStr.contains('cost')    || typeStr.contains('out');

      if (isPaid && !isExpense) { if (!f.hasDate || f.inRange(paidAt)) rev += amount.abs(); }
      if (isPaid &&  isExpense) { if (!f.hasDate || f.inRange(paidAt)) exp += amount.abs(); }

      if (!isPaid) {
        if (!f.hasDate) {
          recv += amount.abs();
        } else {
          final anchor = dueOn ?? todayEnd;
          if (f.inRange(anchor)) recv += amount.abs();
        }
      }
    }
    final net = rev - exp;

    // ===== الصيانة: جديدة/قيد/منتهية =====
    int mNew = 0, mProg = 0, mDone = 0;

    for (final m in maintenance) {
      final k = _normMaintStatus(m['status']);
      if (k == 'open' || k == 'new') {
        mNew++;
      } else if (k == 'inprogress') {
        mProg++;
      } else if (k == 'completed' || k == 'done' || k == 'complete' || k == 'closed') {
        mDone++;
      }
    }

    return ReportsData(
      propertiesCount: properties.length,
      tenantsCount: tenants.length,
      contractsTotal: contracts.length,
      propertyUnitsOccupied: occupiedUnits,
      propertyUnitsVacant: vacantUnits,
      tenantsBound: bound,
      tenantsUnbound: unbound,
      activeContracts: activeCtr,
      nearExpiryContracts: nearCtr,
      endedContracts: endedCtr,
      invoicesTotal: totalInv,
      invoicesFromContracts: fromContracts,
      invoicesFromMaintenance: fromMaintenance,
      maintenanceNew: mNew,
      maintenanceInProgress: mProg,
      maintenanceDone: mDone,
      financeRevenue: rev,
      financeReceivables: recv,
      financeExpenses: exp,
      financeNet: net,
    );
  }

  // ----------------- Helpers مرنة -----------------

  static Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    if (!m.containsKey('id')) m['id'] = d.id;
    return m;
  }

  static bool _containsAny(String s, List<String> keys) {
    for (final k in keys) { if (s.contains(k)) return true; }
    return false;
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _contractIsActive(DateTime? start, DateTime? end, bool terminated, DateTime today) {
    if (terminated) return false;
    final s = start ?? DateTime(2000);
    final e = end ?? DateTime(2200);
    final dNow = DateTime(today.year, today.month, today.day);
    final dS = DateTime(s.year, s.month, s.day);
    final dE = DateTime(e.year, e.month, e.day);
    return (dNow.isAtSameMomentAs(dS) || dNow.isAfter(dS)) &&
           (dNow.isAtSameMomentAs(dE) || dNow.isBefore(dE));
  }

  static String? _extractTenantId(Map<String, dynamic> c) {
    // أسماء شائعة:
    final direct = c['tenantId'] ?? c['tenantID'] ?? c['tenant_id'] ?? c['tid'] ?? c['tenant'];
    if (direct is String && direct.isNotEmpty) return direct;
    if (direct is int) return direct.toString();
    if (direct is Map) {
      final id = direct['id'] ?? direct['tenantId'] ?? direct['tid'];
      if (id is String && id.isNotEmpty) return id;
      if (id is int) return id.toString();
    }
    return null;
  }

  static bool _isMaintInvoiceAny(Map<String, dynamic> inv) {
    final note = (_tryString(inv['note']) ?? _tryString(inv['notes']) ?? _tryString(inv['description']) ?? '').toLowerCase();
    final type = (_tryString(inv['type']) ?? _tryString(inv['category']) ?? _tryString(inv['sourceType']) ?? '').toLowerCase();
    return note.contains('maintenance') || note.contains('صيانة') ||
           type.contains('maintenance') || type.contains('صيانة');
  }

  static bool _isContractInvoiceAny(Map<String, dynamic> inv) {
    final cid = inv['contractId'] ?? inv['contract_id'] ?? inv['cid'] ?? inv['contract'];
    if (cid is String && cid.trim().isNotEmpty) return true;
    if (cid is int && cid != 0) return true;
    if (cid is Map) {
      final inner = cid['id'] ?? cid['contractId'] ?? cid['ref'] ?? cid['refId'];
      if (inner is String && inner.trim().isNotEmpty) return true;
      if (inner is int && inner != 0) return true;
    }
    return false;
  }

  static String _normMaintStatus(dynamic raw) {
    // Enum.name
    try {
      final nm = (raw as dynamic).name;
      if (nm is String && nm.isNotEmpty) return nm.toLowerCase();
    } catch (_) {}
    // String
    if (raw is String) return raw.trim().toLowerCase();
    // int index (افتراضي: open=0,inProgress=1,completed=2,canceled=3)
    if (raw is int) {
      switch (raw) {
        case 0: return 'open';
        case 1: return 'inprogress';
        case 2: return 'completed';
        case 3: return 'canceled';
      }
    }
    return 'unknown';
  }

  static bool? _tryBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return ['1','true','yes','y','on'].contains(v.toLowerCase());
    return null;
  }

  static int? _tryInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static num? _tryNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static String? _tryString(dynamic v) => (v == null) ? null : v.toString();

  static DateTime? _tryDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is String)  { final iso = DateTime.tryParse(v); if (iso != null) return iso; }
    if (v is int) {
      try {
        if (v > 10000000000) return DateTime.fromMillisecondsSinceEpoch((v / 1000).round());
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {}
    }
    return null;
  }
}
