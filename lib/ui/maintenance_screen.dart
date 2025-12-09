// lib/ui/maintenance_screen.dart
// شاشة الصيانة: موديل + Adapters + (قائمة/تفاصيل/إضافة-تعديل) + مسارات
//
// تأكد من التسجيل/الفتح في main.dart قبل استخدام الشاشة:
// Hive.registerAdapter(MaintenancePriorityAdapter());
// Hive.registerAdapter(MaintenanceStatusAdapter());
// Hive.registerAdapter(MaintenanceRequestAdapter());
// await Hive.openBox<MaintenanceRequest>(boxName('maintenanceBox'));
//
// await Hive.openBox<Property>(boxName('propertiesBox'));
// await Hive.openBox<Invoice>(boxName('invoicesBox'));              // ← افتح الفواتير بنفس الاسم والنوع
//
// منطق العقود (مبسّط):
// - لا مقارنة تواريخ.
// - أول عقد مرتبط بالعقار ⇒ نأخذ tenantId.
// - إن تعذر قراءة الصندوق أو لا يوجد عقد ⇒ بدون مستأجر.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart'; // ✅ لعرض التاريخ الهجري
import 'invoices_screen.dart' show Invoice, InvoiceAdapter, InvoiceDetailsScreen;
import '../data/services/user_scope.dart';
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/constants/boxes.dart';   // أو المسار الصحيح حسب مكان الملف



// موديلات موجودة لديك
import '../models/tenant.dart';
import '../models/property.dart';

// ===== استيرادات التنقل أسفل الشاشة =====
import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart' as tenants_ui show TenantsScreen;
import 'contracts_screen.dart';

// ===== عناصر الواجهة المشتركة (Drawer + زر القائمة + BottomNav) =====
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// ✅ مصدر الوقت السعودي
import '../utils/ksa_time.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// =================== Firestore sync helpers (local to maintenance screen) ===================
Future<void> _maintenanceUpsertFS(MaintenanceRequest m) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final data = _maintenanceToMap(m)..['updatedAt'] = FieldValue.serverTimestamp();
  await FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('maintenance').doc(m.id)
      .set(data, SetOptions(merge: true));
}

Future<void> _maintenanceDeleteFS(String id) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('maintenance').doc(id)
      .delete();
}

// Map dart model to firestore fields (adjust if your model uses different names)
Map<String, dynamic> _maintenanceToMap(MaintenanceRequest m) {
  final map = <String, dynamic>{};

  void put(String k, dynamic v) {
    if (v == null) return; // لا نكتب null حتى لا نمسح القيم عند الدمج
    map[k] = v;
  }

  put('id', m.id);
  put('propertyId', m.propertyId);
  put('tenantId', m.tenantId);
  put('title', m.title);
  put('note', m.description);
  put('requestType', m.requestType);
  put('priority', (m.priority is Enum) ? (m.priority as Enum).name : m.priority.toString());
  put('status', (m.status is Enum) ? (m.status as Enum).name : m.status.toString());
  put('isArchived', m.isArchived);
  put('cost', m.cost);

  // ✅ جهة التنفيذ
  put('assignedTo', m.assignedTo);

  // ✅ التواريخ الاختيارية
  put('createdAt', m.createdAt.millisecondsSinceEpoch);
  put('scheduledDate', m.scheduledDate?.millisecondsSinceEpoch);
  put('completedDate', m.completedDate?.millisecondsSinceEpoch);

  // ختم تحديث محلي (لا يؤثر على الحقول الاختيارية)
  put('updatedAtLocal', KsaTime.now().millisecondsSinceEpoch);

  put('invoiceId', m.invoiceId);

  return map;
}



const String kContractsBox = 'contractsBox';

/// ------------------------------------------------------------------------------
/// ربط مبسّط: أول عقد يطابق العقار ⇒ يُرجع tenantId (بدون تواريخ).
/// يدعم حالتين: عنصر العقد Map أو كائن مtyped.
/// ------------------------------------------------------------------------------
String? tenantIdForProperty(String? propertyId) {
  if (propertyId == null) return null;
  if (!Hive.isBoxOpen(kContractsBox)) return null;

  dynamic box;
  try {
    box = Hive.box(kContractsBox);
  } catch (_) {
    return null;
  }

  try {
    for (final e in (box as Box).values) {
      try {
        final pid = e is Map
            ? e['propertyId'] as String?
            : (e as dynamic).propertyId as String?;
        if (pid != propertyId) continue;

        final tid = e is Map
            ? e['tenantId'] as String?
            : (e as dynamic).tenantId as String?;
        if (tid != null && tid.isNotEmpty) return tid;
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}

/// ===============================================================================
/// الموديل + الـAdapters
/// ===============================================================================
enum MaintenancePriority { low, medium, high, urgent }
enum MaintenanceStatus { open, inProgress, completed, canceled }

class MaintenancePriorityAdapter extends TypeAdapter<MaintenancePriority> {
  @override
  final int typeId = 60;
  @override
  MaintenancePriority read(BinaryReader r) {
    final v = r.readByte();
    switch (v) {
      case 0:
        return MaintenancePriority.low;
      case 1:
        return MaintenancePriority.medium;
      case 2:
        return MaintenancePriority.high;
      case 3:
        return MaintenancePriority.urgent;
      default:
        return MaintenancePriority.low;
    }
  }

  @override
  void write(BinaryWriter w, MaintenancePriority obj) {
    switch (obj) {
      case MaintenancePriority.low:
        w.writeByte(0);
        break;
      case MaintenancePriority.medium:
        w.writeByte(1);
        break;
      case MaintenancePriority.high:
        w.writeByte(2);
        break;
      case MaintenancePriority.urgent:
        w.writeByte(3);
        break;
    }
  }
}

class MaintenanceStatusAdapter extends TypeAdapter<MaintenanceStatus> {
  @override
  final int typeId = 61;
  @override
  MaintenanceStatus read(BinaryReader r) {
    final v = r.readByte();
    switch (v) {
      case 0:
        return MaintenanceStatus.open;
      case 1:
        return MaintenanceStatus.inProgress;
      case 2:
        return MaintenanceStatus.completed;
      case 3:
        return MaintenanceStatus.canceled;
      default:
        return MaintenanceStatus.open;
    }
  }

  @override
  void write(BinaryWriter w, MaintenanceStatus obj) {
    switch (obj) {
      case MaintenanceStatus.open:
        w.writeByte(0);
        break;
      case MaintenanceStatus.inProgress:
        w.writeByte(1);
        break;
      case MaintenanceStatus.completed:
        w.writeByte(2);
        break;
      case MaintenanceStatus.canceled:
        w.writeByte(3);
        break;
    }
  }
}

class MaintenanceRequest extends HiveObject {
  String id;

  String propertyId; // مطلوب
  String? tenantId; // من العقد تلقائيًا إن وجد

  String title; // عنوان الطلب
  String description; // وصف
  String requestType; // نوع الطلب (يُستخدم كنوع الفاتورة)

  MaintenancePriority priority;
  MaintenanceStatus status;

  DateTime createdAt;
  DateTime? scheduledDate;
  DateTime? completedDate;

  double cost; // تكلفة (افتراضي 0)
  String? assignedTo; // جهة التنفيذ (فني/شركة)
  bool isArchived;

  String? invoiceId; // معرف الفاتورة التي تُنشأ تلقائيًا عند الإكمال

  MaintenanceRequest({
    String? id,
    required this.propertyId,
    this.tenantId,
    required this.title,
    this.description = '',
    this.requestType = 'صيانة',
    this.priority = MaintenancePriority.medium,
    this.status = MaintenanceStatus.open,
    DateTime? createdAt,
    this.scheduledDate,
    this.completedDate,
    this.cost = 0.0,
    this.assignedTo,
    this.isArchived = false,
    this.invoiceId,
  })  : id = id ?? KsaTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? KsaTime.now();
}

class MaintenanceRequestAdapter extends TypeAdapter<MaintenanceRequest> {
  @override
  final int typeId = 62;

  @override
  MaintenanceRequest read(BinaryReader r) {
    final numOfFields = r.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) r.readByte(): r.read(),
    };
    return MaintenanceRequest(
      id: fields[0] as String? ?? KsaTime.now().microsecondsSinceEpoch.toString(),
      propertyId: fields[1] as String,
      tenantId: fields[2] as String?,
      title: fields[3] as String,
      description: fields[4] as String? ?? '',
      priority: fields[5] as MaintenancePriority? ?? MaintenancePriority.medium,
      status: fields[6] as MaintenanceStatus? ?? MaintenanceStatus.open,
      createdAt: fields[7] as DateTime? ?? KsaTime.now(),
      scheduledDate: fields[8] as DateTime?,
      completedDate: fields[9] as DateTime?,
      cost: (fields[10] as double?) ?? 0.0,
      assignedTo: fields[11] as String?,
      isArchived: fields[12] as bool? ?? false,
      invoiceId: fields[13] as String?,
      requestType: fields[14] as String? ?? 'صيانة',
    );
  }

  @override
  void write(BinaryWriter w, MaintenanceRequest m) {
    w
      ..writeByte(15)
      ..writeByte(0)..write(m.id)
      ..writeByte(1)..write(m.propertyId)
      ..writeByte(2)..write(m.tenantId)
      ..writeByte(3)..write(m.title)
      ..writeByte(4)..write(m.description)
      ..writeByte(5)..write(m.priority)
      ..writeByte(6)..write(m.status)
      ..writeByte(7)..write(m.createdAt)
      ..writeByte(8)..write(m.scheduledDate)
      ..writeByte(9)..write(m.completedDate)
      ..writeByte(10)..write(m.cost)
      ..writeByte(11)..write(m.assignedTo)
      ..writeByte(12)..write(m.isArchived)
      ..writeByte(13)..write(m.invoiceId)
      ..writeByte(14)..write(m.requestType);
  }
}

/// ===============================================================================
/// إنشاء/تحديث فاتورة الصيانة مرة واحدة بنوع Invoice
/// ===============================================================================

// نفس منطق أرقام الفواتير في invoices_screen.dart لكن مخصص للصيانة
// مولّد رقم فاتورة للصيانة بناءً على أعلى رقم موجود في نفس السنة
String _nextInvoiceSerialForMaintenance(Box<Invoice> invoices) {
  final year = KsaTime.now().year;

  int maxSeq = 0;
  for (final inv in invoices.values) {
    final s = inv.serialNo;
    if (s != null && s.startsWith('$year-')) {
      final tail = s.split('-').last;
      final n = int.tryParse(tail) ?? 0;
      if (n > maxSeq) maxSeq = n;
    }
  }

  final next = maxSeq + 1;
  return '$year-${next.toString().padLeft(4, '0')}';
}

Future<String> createOrUpdateInvoiceForMaintenance(MaintenanceRequest m) async {
  try {
    final box = Hive.box<Invoice>(boxName('invoicesBox')); // لا تفتح ولا تغلق

    final now = KsaTime.now();
    final String id = (m.invoiceId?.isNotEmpty == true)
        ? m.invoiceId!
        : now.microsecondsSinceEpoch.toString();

    // 🔹 حافظ على رقم الفاتورة القديم إن وجد، وإلا أنشئ رقم جديد
    String? serialNo;
    try {
      final existing = box.get(id);
      if (existing != null &&
          existing.serialNo != null &&
          existing.serialNo!.isNotEmpty) {
        // فاتورة قديمة للصيانة لها رقم → نستخدمه كما هو
        serialNo = existing.serialNo;
      } else {
        // فاتورة جديدة أو قديمة بدون رقم → نولّد رقم جديد
        serialNo = _nextInvoiceSerialForMaintenance(box);
      }
    } catch (_) {
      // في حالة أي خطأ غير متوقع، لا نكسر الكود
      serialNo = null;
    }

    final inv = Invoice(
  id: id,
  serialNo: serialNo,
  tenantId: m.tenantId ?? '',
  contractId: '',
  propertyId: m.propertyId,
  issueDate: m.completedDate ?? now,
  dueDate: m.completedDate ?? now,
  amount: -m.cost,             // ← سالب: مصروف
  paidAmount: m.cost,          // دفع كامل
  currency: 'SAR',
  note: 'صيانة - ${m.title}',
  paymentMethod: 'نقدًا',
  isArchived: m.isArchived,
  isCanceled: false,
  createdAt: now,
  updatedAt: now,
);


    await box.put(id, inv);
    return id;
  } catch (e) {
    debugPrint('Invoice create/update failed: $e');
    return '';
  }
}

/// ===============================================================================
String _fmtDate(DateTime d) {
  final x = KsaTime.dateOnly(d);
  return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

String _fmtDateOrDash(DateTime? d) => d == null ? '—' : _fmtDate(d);

// ✅ تفعيل/تعطيل العرض الهجري من sessionBox
bool get _useHijri {
  if (!Hive.isBoxOpen('sessionBox')) return false;
  try {
    return Hive.box('sessionBox').get('useHijri', defaultValue: false) == true;
  } catch (_) {
    return false;
  }
}

// ✅ ديناميكي هجري/ميلادي
String _fmtDateDynamic(DateTime d) {
  final dd = KsaTime.dateOnly(d);
  if (!_useHijri) return _fmtDate(dd);
  final h = HijriCalendar.fromDate(dd);
  final yy = h.hYear.toString();
  final mm = h.hMonth.toString().padLeft(2, '0');
  final ddh = h.hDay.toString().padLeft(2, '0');
  return '$yy-$mm-$ddh هـ';
}

String _fmtDateOrDashDynamic(DateTime? d) => d == null ? '—' : _fmtDateDynamic(d);

// قصّ إلى خانتين
String _fmtMoneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
}

Widget _softCircle(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

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
              offset: const Offset(0, 10))
        ],
      ),
      child: child,
    );
  }
}

Widget _chip(String text, {Color bg = const Color(0xFF334155)}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text,
          style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700)),
    );

String _limitChars(String t, int max) =>
    t.length <= max ? t : '${t.substring(0, max)}…';

Color _statusColor(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return const Color(0xFF0EA5E9);
    case MaintenanceStatus.inProgress:
      return const Color(0xFFF59E0B);
    case MaintenanceStatus.completed:
      return const Color(0xFF065F46);
    case MaintenanceStatus.canceled:
      return const Color(0xFF7F1D1D);
  }
}

String _statusText(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return 'جديد';
    case MaintenanceStatus.inProgress:
      return 'قيد التنفيذ';
    case MaintenanceStatus.completed:
      return 'مكتمل';
    case MaintenanceStatus.canceled:
      return 'ملغاة';
  }
}

String _priorityText(MaintenancePriority p) {
  switch (p) {
    case MaintenancePriority.low:
      return 'منخفضة';
    case MaintenancePriority.medium:
      return 'متوسطة';
    case MaintenancePriority.high:
      return 'عالية';
    case MaintenancePriority.urgent:
      return 'عاجلة';
  }
}

Color _priorityColor(MaintenancePriority p) {
  switch (p) {
    case MaintenancePriority.low:
      return const Color(0xFF475569);
    case MaintenancePriority.medium:
      return const Color(0xFF2563EB);
    case MaintenancePriority.high:
      return const Color(0xFFB45309);
    case MaintenancePriority.urgent:
      return const Color(0xFFB91C1C);
  }
}

// ✅ تنبيه منع الأرشفة قبل «مكتملة»
Future<void> _showArchiveBlockedDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('تنبيه',
          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text(
        'لا يمكن أرشفة الطلب إلا بعد أن تكون حالته «مكتمل».',
        style: GoogleFonts.cairo(color: Colors.white70),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('حسناً', style: GoogleFonts.cairo(color: Colors.white)),
        ),
      ],
    ),
  );
}

Future<void> showEditBlockedDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        'لا يمكن التعديل',
        style: GoogleFonts.cairo(
            color: Colors.white, fontWeight: FontWeight.w800),
      ),
      content: Text(
        'لا يمكن تعديل طلب الصيانة بعد اعتماده "مكتمل".\n',
        style: GoogleFonts.cairo(color: Colors.white70),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('حسناً',
              style: GoogleFonts.cairo(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// ===============================================================================
/// شاشة القائمة
/// ===============================================================================
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Box<MaintenanceRequest> get _box =>
      Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());


  Box<Property> get _properties => Hive.box<Property>(boxName('propertiesBox'));

  String _q = '';
  bool _showArchived = false;
  MaintenanceStatus? _statusFilter;
  MaintenancePriority? _priorityFilter;
  bool? _archivedFilter; // ✅ يظهر فقط عندما تكون الحالة «مكتملة»

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;
// لفتح طلب عند الوصول عبر التنبيهات مرة واحدة فقط
bool _didReadArgs = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_didReadArgs) return;
  _didReadArgs = true;

  final args = ModalRoute.of(context)?.settings.arguments as Map?;
  final id = args?['openMaintenanceId']?.toString();
  if (id != null && id.isNotEmpty) {
    Future.microtask(() => _openMaintenanceById(id));
  }
}

void _openMaintenanceById(String id) {
  MaintenanceRequest? item;
  for (final m in _box.values) {
    if (m.id == id) { item = m; break; }
  }
  if (item == null) return;

  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MaintenanceDetailsScreen(item: item!)),
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
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        

        // الدروَر يبدأ أسفل الـAppBar وينتهي فوق الـBottomNav
        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset =
                kToolbarHeight + media.padding.top;
            final double bottomInset =
                _bottomBarHeight + media.padding.bottom;
            return Padding(
              padding:
                  EdgeInsets.only(top: topInset, bottom: bottomInset),
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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text('الصيانة',
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20.sp)),
          actions: [
            IconButton(
              tooltip: 'تصفية',
              icon: const Icon(Icons.filter_list_rounded,
                  color: Colors.white),
              onPressed: _openFilters,
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
                      Color(0xFF0F3A8C),
                      Color(0xFF1E40AF),
                      Color(0xFF2148C6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child:
                    _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child:
                    _softCircle(260.r, const Color(0x22FFFFFF))),
            Column(
              children: [
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) =>
                        setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالعنوان/العقار/التكلفة',
                      hintStyle:
                          GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color:
                                  Colors.white.withOpacity(0.15))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color:
                                  Colors.white.withOpacity(0.15))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                          borderRadius:
                              BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w),
                  child: Row(
                    children: [
                      if (_statusFilter != null)
                        Padding(
                          padding:
                              EdgeInsets.only(right: 4.w),
                          child: _chip(
                              'الحالة: ${_statusText(_statusFilter!)}',
                              bg: _statusColor(_statusFilter!)),
                        ),
                      if (_priorityFilter != null)
                        Padding(
                          padding:
                              EdgeInsets.only(right: 4.w),
                          child: _chip(
                              'الأولوية: ${_priorityText(_priorityFilter!)}',
                              bg: _priorityColor(
                                  _priorityFilter!)),
                        ),
                      if (_archivedFilter != null &&
                          _statusFilter == MaintenanceStatus.completed)
                        Padding(
                          padding: EdgeInsets.only(right: 4.w),
                          child: _chip(
                            _archivedFilter == true ? 'مؤرشف' : 'غير مؤرشف',
                            bg: const Color(0xFF334155),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _box.listenable(),
                    builder: (context,
                        Box<MaintenanceRequest> box, _) {
                      // ✅ عند اختيار فلتر الأرشفة مع «مكتملة» نستبدل مفتاح عرض الأرشيف المؤقت
                      final bool showArchivedEffective =
                          _archivedFilter ?? _showArchived;

                      var items = box.values
                          .where((e) => e.isArchived == showArchivedEffective)
                          .toList();

                      if (_statusFilter != null) {
                        items = items
                            .where((e) =>
                                e.status == _statusFilter)
                            .toList();
                      }
                      if (_priorityFilter != null) {
                        items = items
                            .where((e) =>
                                e.priority ==
                                _priorityFilter)
                            .toList();
                      }

                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        // جرّب نحول الإدخال إلى رقم (نقبل 123 أو 123.45 وحتى مع فواصل)
                        final qNum = double.tryParse(_q.replaceAll(RegExp(r'[^0-9.]'), ''));

                        items = items.where((m) {
                          // اسم العقار
                          final pMatch = _properties.values.where((x) => x.id == m.propertyId);
                          final pn = pMatch.isNotEmpty ? pMatch.first.name.toLowerCase() : '';

                          final titleHit = m.title.toLowerCase().contains(q);
                          final descHit  = m.description.toLowerCase().contains(q);
                          final propHit  = pn.contains(q);

                          // مطابقة التكلفة:
                          // - إذا المستخدم كتب رقمًا: نطابق مساواة تقريبية ±0.01
                          // - وإلا نعمل contains على سلسلة التكلفة
                          bool costHit = false;
                          if (qNum != null) {
                            costHit = (m.cost - qNum).abs() < 0.01;
                          } else {
                            final costStr = _fmtMoneyTrunc(m.cost).toLowerCase();
                            costHit = costStr.contains(q);
                          }

                          return titleHit || descHit || propHit || costHit;
                        }).toList();
                      }

                      items.sort((a, b) => b.createdAt
                          .compareTo(a.createdAt));

                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                              showArchivedEffective
                                  ? 'لا توجد طلبات مؤرشفة'
                                  : 'لا توجد طلبات صيانة',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight:
                                      FontWeight.w700)),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            16.w, 8.h, 16.w, 24.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final m = items[i];

                          final pMatch = _properties.values
                              .where(
                                  (x) => x.id == m.propertyId);
                          final p = pMatch.isNotEmpty
                              ? pMatch.first
                              : null;

                          return InkWell(
                            borderRadius:
                                BorderRadius.circular(16.r),
                            onLongPress: () async {
                              await _openRowMenu(
                                  context, m);
                            },
                            onTap: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                builder: (_) =>
                                    MaintenanceDetailsScreen(
                                        item: m),
                              ));
                            },
                            child: _DarkCard(
                              padding:
                                  EdgeInsets.all(12.w),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Container(
                                    width: 52.w,
                                    height: 52.w,
                                    decoration:
                                        BoxDecoration(
                                      borderRadius:
                                          BorderRadius
                                              .circular(12.r),
                                      gradient:
                                          const LinearGradient(
                                              colors: [
                                            Color(
                                                0xFF1E40AF),
                                            Color(
                                                0xFF2148C6)
                                          ],
                                              begin: Alignment
                                                  .topRight,
                                              end: Alignment
                                                  .bottomLeft),
                                    ),
                                    child: const Icon(
                                        Icons
                                            .build_rounded,
                                        color:
                                            Colors.white),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _limitChars(
                                                    m.title,
                                                    60),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                                style: GoogleFonts
                                                    .cairo(
                                                        color: Colors
                                                            .white,
                                                        fontWeight:
                                                            FontWeight
                                                                .w800,
                                                        fontSize:
                                                            15.sp),
                                              ),
                                            ),
                                            _chip(
                                                _statusText(
                                                    m.status),
                                                bg:
                                                    _statusColor(
                                                        m.status)),
                                          ],
                                        ),
                                        SizedBox(
                                            height: 6.h),
                                        Text(
                                          p?.name ?? '—',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(
                                            height: 6.h),
                                        Wrap(
                                          spacing: 6.w,
                                          runSpacing: 6.h,
                                          children: [
                                            _chip(
                                                'الأولوية: ${_priorityText(m.priority)}',
                                                bg: _priorityColor(
                                                    m.priority)),

                                            _chip(
                                                'البدء: ${_fmtDateOrDashDynamic(m.scheduledDate)}',
                                                bg: const Color(
                                                    0xFF1F2937)),
                                            if (m.requestType
                                                .isNotEmpty)
                                              _chip(
                                                  'النوع: ${m.requestType}',
                                                  bg: const Color(
                                                      0xFF1F2937)),
                                            if (m.cost > 0)
  _chip(
      'التكلفة: ${_fmtMoneyTrunc(m.cost)} ريال',
      bg: const Color(0xFF1F2937)),


                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                      Icons
                                          .chevron_left_rounded,
                                      color:
                                          Colors.white70),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0, // لا توجد تبويبة "صيانة" ضمن الـBottomNav؛ اخترنا 0
          onTap: _handleBottomTap,
        ),

floatingActionButton: FloatingActionButton.extended(
  backgroundColor: const Color(0xFF1E40AF),
  foregroundColor: Colors.white,
  elevation: 6,
  icon: const Icon(Icons.add_rounded),
  label: Text('طلب جديد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
  onPressed: () async {
    // 🚫 منع عميل المكتب من إضافة طلب صيانة
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    final result = await Navigator.of(context).push<MaintenanceRequest?>(
      MaterialPageRoute(builder: (_) => const AddOrEditMaintenanceScreen()),
    );
    if (result != null && context.mounted) {
      // رجعنا من إنشاء جديد بنجاح
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('تم إضافة طلب الصيانة', style: GoogleFonts.cairo()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  },
),

      ),
    );
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        MaintenanceStatus? st = _statusFilter;
        MaintenancePriority? pr = _priorityFilter;
        bool? arch = _archivedFilter;

        // ✅ حذف "ملغاة" من الفلتر
        final statusesNoCanceled = MaintenanceStatus.values
            .where((s) => s != MaintenanceStatus.canceled)
            .toList();

        return StatefulBuilder(
          builder: (ctx, setM) {
            final showArchiveChoice =
                st == MaintenanceStatus.completed;
            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  16.h + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('التصفية',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<MaintenanceStatus?>(
                    value: st,
                    decoration: _dd('الحالة'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                    items: <MaintenanceStatus?>[null, ...statusesNoCanceled]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v == null ? 'الكل' : _statusText(v))))
                        .toList(),
                    onChanged: (v) => setM(() {
                      st = v;
                      if (st != MaintenanceStatus.completed) arch = null;
                    }),
                  ),
                  SizedBox(height: 10.h),

                  // 2) الأولوية
                  DropdownButtonFormField<MaintenancePriority?>(
                    value: pr,
                    decoration: _dd('الأولوية'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                    items: <MaintenancePriority?>[null, ...MaintenancePriority.values]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v == null ? 'الكل' : _priorityText(v))))
                        .toList(),
                    onChanged: (v) => setM(() => pr = v),
                  ),
                  SizedBox(height: 10.h),

                  // 3) الأرشفة — تظهر فقط إذا الحالة = مكتملة
                  if (st == MaintenanceStatus.completed) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('الأرشفة', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('غير مؤرشفة', style: GoogleFonts.cairo()),
                            selected: arch == null,
                            onSelected: (_) => setM(() => arch = null),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('مؤرشفة', style: GoogleFonts.cairo()),
                            selected: arch == true,
                            onSelected: (_) => setM(() => arch = true),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF0EA5E9)),
                          onPressed: () {
                            setState(() {
                              _statusFilter = st;
                              _priorityFilter = pr;
                              // ✅ تطبيق فلتر الأرشفة فقط مع «مكتملة»، وإلا نلغيه
                              _archivedFilter =
                                  st == MaintenanceStatus.completed ? arch : null;
                            });
                            Navigator.pop(context);
                          },
                          child: Text('تطبيق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _statusFilter = null;
                              _priorityFilter = null;
                              _archivedFilter = null;
                            });
                            Navigator.pop(context);
                          },
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

    Future<void> _openRowMenu(
    BuildContext context,
    MaintenanceRequest m,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إجراءات سريعة',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12.h),

                // تعديل
                ListTile(
                  onTap: () async {
                    if (await OfficeClientGuard.blockIfOfficeClient(sheetCtx)) {
                      return;
                    }

                    if (m.status == MaintenanceStatus.completed) {
                      Navigator.pop(sheetCtx);
                      await showEditBlockedDialog(sheetCtx);
                      return;
                    }

                    Navigator.pop(sheetCtx);
                    await Navigator.of(sheetCtx).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddOrEditMaintenanceScreen(existing: m),
                      ),
                    );
                  },
                  leading: const Icon(Icons.edit_rounded, color: Colors.white),
                  title: Text(
                    'تعديل',
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                ),

                // تغيير الحالة (فقط إذا ليست مكتملة/ملغاة)
                if (m.status != MaintenanceStatus.completed &&
                    m.status != MaintenanceStatus.canceled)
                  ListTile(
                    onTap: () async {
                      if (await OfficeClientGuard.blockIfOfficeClient(sheetCtx)) {
                        return;
                      }

                      Navigator.pop(sheetCtx);
                      await _changeStatus(sheetCtx, m);
                    },
                    leading: const Icon(Icons.flag_rounded, color: Colors.white),
                    title: Text(
                      'تغيير الحالة',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                  ),

                // أرشفة / فك الأرشفة
                ListTile(
                  onTap: () async {
                    if (await OfficeClientGuard.blockIfOfficeClient(sheetCtx)) {
                      return;
                    }

                    // لا نسمح بأرشفة طلب غير مكتمل (إلا إذا كان يفك الأرشفة)
                    if (m.status != MaintenanceStatus.completed && !m.isArchived) {
                      Navigator.pop(sheetCtx);
                      await _showArchiveBlockedDialog(sheetCtx);
                      return;
                    }

                    Navigator.pop(sheetCtx);

                    final box = Hive.box<MaintenanceRequest>(
                      HiveService.maintenanceBoxName(),
                    );

                    final newArchived = !m.isArchived;
                    m.isArchived = newArchived;
                    await box.put(m.id, m);

                    // مزامنة مع السيرفر
                    unawaited(_maintenanceUpsertFS(m));

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            newArchived
                                ? 'تم الأرشفة'
                                : 'تم إلغاء الأرشفة',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      );
                    }
                  },
                  leading: Icon(
                    m.isArchived
                        ? Icons.unarchive_rounded
                        : Icons.archive_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    m.isArchived ? 'فك الأرشفة' : 'أرشفة',
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                ),

                // حذف
                ListTile(
                  onTap: () async {
                    if (await OfficeClientGuard.blockIfOfficeClient(sheetCtx)) {
                      return;
                    }

                    // 🚫 منع حذف طلب بعد صدور فاتورة له
                    if (m.status == MaintenanceStatus.completed &&
                        m.invoiceId != null &&
                        m.invoiceId!.toString().isNotEmpty) {
                      Navigator.pop(sheetCtx);

                      await showDialog(
                        context: sheetCtx,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF0B1220),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          actionsAlignment: MainAxisAlignment.center,
                          title: Text(
                            'لا يمكن الحذف',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          content: Text(
                            'لا يمكن حذف طلب الصيانة بعد صدور الفاتورة له.\n'
                            'يمكنك فقط أرشفة طلب الصيانة إذا لم تعد بحاجة لظهوره.',
                            style: GoogleFonts.cairo(
                              color: Colors.white70,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(sheetCtx).pop(),
                              child: Text(
                                'حسناً',
                                style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    Navigator.pop(sheetCtx);

                    final ok = await _confirm(
                      sheetCtx,
                      'حذف الطلب',
                      'هل انت متأكد من حذف هذا الطلب سيتم حذف الفاتورة المرتبطة بهذا الطلب',
                    );
                    if (!ok) return;

                    try {
                      await _deleteMaintenanceAndInvoice(m);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم الحذف',
                              style: GoogleFonts.cairo(),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تعذّر الحذف: $e',
                              style: GoogleFonts.cairo(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  leading: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    'حذف',
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Future<bool> _confirm(
      BuildContext context, String title, String msg) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text(title,
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
            content: Text(msg,
                style:
                    GoogleFonts.cairo(color: Colors.white70)),
            actionsAlignment: MainAxisAlignment.center, // ✅ الأزرار بالمنتصف
            actions: [
              // ✅ زر التأكيد أولاً ليظهر يمينًا في RTL
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFB91C1C)),
                  onPressed: () =>
                      Navigator.pop(context, true),
                  child: Text('تأكيد',
                      style: GoogleFonts.cairo(
                          color: Colors.white))),
              TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: Text('إلغاء',
                      style: GoogleFonts.cairo(
                          color: Colors.white70))),
            ],
          ),
        ) ??
        false;
    return ok;
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide:
                BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius:
                BorderRadius.all(Radius.circular(12))),
      );

  // ==== نافذة تغيير الحالة (مع إنشاء الفاتورة لمرة واحدة) ====
  Future<void> _changeStatus(
      BuildContext context, MaintenanceRequest m) async {
    // ✅ إن كانت الحالة الحالية "ملغاة" لعنصر قديم، عيّن الابتدائية "جديدة"
    MaintenanceStatus st = m.status == MaintenanceStatus.canceled
        ? MaintenanceStatus.open
        : m.status;

    final costCtl = TextEditingController(
        text: m.cost > 0 ? m.cost.toStringAsFixed(2) : '');
    DateTime? doneDate = m.completedDate;
    bool saving = false; // خارج StatefulBuilder

    // ✅ حذف "ملغاة" من خيارات تغيير الحالة
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16.w,
              16.h,
              16.w,
              16.h + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تغيير حالة الطلب',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<MaintenanceStatus>(
                    value: st,
                    decoration: _dd('اختر الحالة'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                    items: statusesNoCanceled
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_statusText(s))))
                        .toList(),
                    onChanged: (v) => setM(() {
                      st = v ?? st;
                      if (st == MaintenanceStatus.completed &&
                          doneDate == null) {
                        doneDate = KsaTime.today();
                      }
                    }),
                  ),
                  SizedBox(height: 10.h),

                  if (st == MaintenanceStatus.completed) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: const Color(0x334256F1),
                        borderRadius:
                            BorderRadius.circular(10.r),
                        border: Border.all(
                            color: const Color(0x554256F1)),
                      ),
                      child: Text(
                          'تنبيه مهم: التكلفة ضرورية جدًا لعمل الفاتورة وحفظها في التقارير.',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: costCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'))
                      ],
                      style: GoogleFonts.cairo(
                          color: Colors.white),
                      decoration:
                          _dd('التكلفة الإجمالية'),
                    ),
                    SizedBox(height: 10.h),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(12.r),
                      onTap: () async {
                        final now = KsaTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: doneDate ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                          helpText: 'تاريخ الإنهاء',
                          confirmText: 'اختيار',
                          cancelText: 'إلغاء',
                          builder: (context, child) =>
                              Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  const ColorScheme.dark(
                                primary: Colors.white,
                                onPrimary: Colors.black,
                                surface: Color(0xFF0B1220),
                                onSurface: Colors.white,
                              ),
                              dialogBackgroundColor:
                                  const Color(0xFF0B1220),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setM(() => doneDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration:
                            _dd('تاريخ الإنهاء'),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available,
                                color: Colors.white70),
                            SizedBox(width: 8.w),
                            Text(
                                _fmtDateOrDashDynamic(
                                    doneDate ??
                                        KsaTime.now()),
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF0EA5E9)),
                          onPressed: saving
                              ? null
                              : () async {
                                  setM(() => saving = true);
                                  try {
                                    m.status = st;
                                    if (st ==
                                        MaintenanceStatus
                                            .completed) {
                                      final c =
                                          double.tryParse(
                                              costCtl.text
                                                  .trim());
                                      if (c != null &&
                                          c >= 0) {
                                        m.cost = c;
                                      }
                                      m.completedDate =
                                          doneDate ??
                                              KsaTime.now();

                                      final invId =
                                          await createOrUpdateInvoiceForMaintenance(
                                              m);
                                      if (invId
                                          .isNotEmpty) {
                                        m.invoiceId =
                                            invId;
                                      }
                                    }
                                    final box = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

if (m.isInBox) {
  await m.save();
} else {
  await box.put(m.id, m);
}

                    unawaited(_maintenanceUpsertFS(m));

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                              context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'تم تحديث الحالة',
                                              style: GoogleFonts
                                                  .cairo()),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                              context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'حدث خطأ أثناء الحفظ',
                                              style: GoogleFonts
                                                  .cairo()),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setM(() => saving =
                                          false);
                                    }
                                  }
                                },
                          child: Text('حفظ',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(ctx),
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// ===============================================================================
/// تفاصيل الطلب
/// ===============================================================================
class MaintenanceDetailsScreen extends StatefulWidget {
  final MaintenanceRequest item;
  const MaintenanceDetailsScreen({super.key, required this.item});

  @override
  State<MaintenanceDetailsScreen> createState() =>
      _MaintenanceDetailsScreenState();
}

class _MaintenanceDetailsScreenState
    extends State<MaintenanceDetailsScreen> {

  Box<Property> get _properties =>
      Hive.box<Property>(boxName('propertiesBox'));

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  Future<bool> _confirm(
      BuildContext context, String title, String msg) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text(title,
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
            content: Text(msg,
                style:
                    GoogleFonts.cairo(color: Colors.white70)),
            actionsAlignment: MainAxisAlignment.center, // ✅ الأزرار بالمنتصف
            actions: [
              // ✅ زر التأكيد أولاً ليظهر يمينًا في RTL
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFB91C1C)),
                  onPressed: () =>
                      Navigator.pop(context, true),
                  child: Text('تأكيد',
                      style: GoogleFonts.cairo(
                          color: Colors.white))),
              TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: Text('إلغاء',
                      style: GoogleFonts.cairo(
                          color: Colors.white70))),
            ],
          ),
        ) ??
        false;
    return ok;
  }

  // Fallback محلي لتغيير الحالة (يستخدم الدالة العلوية المشتركة)
  Future<void> _openChangeStatusSheetLocal(
      MaintenanceRequest m) async {
    // ✅ إن كانت الحالة الحالية "ملغاة" لعنصر قديم، عيّن الابتدائية "جديدة"
    MaintenanceStatus st = m.status == MaintenanceStatus.canceled
        ? MaintenanceStatus.open
        : m.status;

    final costCtl = TextEditingController(
        text: m.cost > 0 ? m.cost.toStringAsFixed(2) : '');
    DateTime? doneDate = m.completedDate;
    bool saving = false;

    // ✅ حذف "ملغاة" من خيارات تغيير الحالة
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16.w,
              16.h,
              16.w,
              16.h + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تغيير حالة الطلب',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<MaintenanceStatus>(
                    value: st,
                    decoration: InputDecoration(
                      labelText: 'اختر الحالة',
                      labelStyle: GoogleFonts.cairo(
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                              color:
                                  Colors.white.withOpacity(0.15))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                          borderRadius:
                              BorderRadius.all(Radius.circular(12))),
                    ),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w700),
                    items: statusesNoCanceled
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_statusText(s))))
                        .toList(),
                    onChanged: (v) => setM(() {
                      st = v ?? st;
                      if (st == MaintenanceStatus.completed &&
                          doneDate == null) {
                        doneDate = KsaTime.today();
                      }
                    }),
                  ),
                  SizedBox(height: 10.h),

                  if (st == MaintenanceStatus.completed) ...[
                    TextField(
                      controller: costCtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}$'))
                      ],
                      style: GoogleFonts.cairo(
                          color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'التكلفة الإجمالية',
                        labelStyle: GoogleFonts.cairo(
                            color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                                color: Colors.white
                                    .withOpacity(0.15))),
                        focusedBorder: const OutlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.all(
                                Radius.circular(12))),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(12.r),
                      onTap: () async {
                        final now = KsaTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: doneDate ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                          builder: (context, child) =>
                              Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  const ColorScheme.dark(
                                primary: Colors.white,
                                onPrimary: Colors.black,
                                surface: Color(0xFF0B1220),
                                onSurface: Colors.white,
                              ),
                              dialogBackgroundColor:
                                  const Color(0xFF0B1220),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setM(() => doneDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'تاريخ الإنهاء',
                          labelStyle: GoogleFonts.cairo(
                              color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                  color: Colors.white
                                      .withOpacity(0.15))),
                          focusedBorder: const OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: Colors.white),
                              borderRadius: BorderRadius.all(
                                  Radius.circular(12))),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available,
                                color: Colors.white70),
                            SizedBox(width: 8.w),
                            Text(
                                _fmtDateOrDashDynamic(
                                    doneDate ??
                                        KsaTime.now()),
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF0EA5E9)),
                          onPressed: saving
                              ? null
                              : () async {
                                  setM(() => saving = true);
                                  try {
                                    m.status = st;
                                    if (st ==
                                        MaintenanceStatus
                                            .completed) {
                                      final c =
                                          double.tryParse(
                                              costCtl.text
                                                  .trim());
                                      if (c != null &&
                                          c >= 0) {
                                        m.cost = c;
                                      }
                                      m.completedDate =
                                          doneDate ??
                                              KsaTime.now();

                                      final invId =
                                          await createOrUpdateInvoiceForMaintenance(
                                              m);
                                      if (invId
                                          .isNotEmpty) {
                                        m.invoiceId =
                                            invId;
                                      }
                                    }
                                    final box = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

if (m.isInBox) {
  await m.save();
} else {
  await box.put(m.id, m);
}

                    unawaited(_maintenanceUpsertFS(m));

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                              context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'تم تحديث الحالة',
                                              style: GoogleFonts
                                                  .cairo()),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                              context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'حدث خطأ أثناء الحفظ',
                                              style: GoogleFonts
                                                  .cairo()),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setM(() => saving =
                                          false);
                                    }
                                  }
                                },
                          child: Text('حفظ',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(ctx),
                          child: Text('إغلاق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showDescriptionSheet(BuildContext context, MaintenanceRequest m) {
    final controller = TextEditingController(text: (m.description).trim());

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
                    'الوصف',
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
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب وصف الطلب هنا…',
                  hintStyle: GoogleFonts.cairo(color: Colors.white54),
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
                        m.description = controller.text.trim();
                       final box = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

if (m.isInBox) {
  await m.save();
} else {
  await box.put(m.id, m);
}

                    unawaited(_maintenanceUpsertFS(m));
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم حفظ الوصف', style: GoogleFonts.cairo()),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          setState(() {}); // تحديث العرض
                        }
                      },
                      child: Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('إغلاق', style: GoogleFonts.cairo(color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final pMatch = _properties.values.where((x) => x.id == item.propertyId);
    final p = pMatch.isNotEmpty ? pMatch.first : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
       

        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset =
                kToolbarHeight + media.padding.top;
            final double bottomInset =
                _bottomBarHeight + media.padding.bottom;
            return Padding(
              padding:
                  EdgeInsets.only(top: topInset, bottom: bottomInset),
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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text('تفاصيل الصيانة',
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800)),
          actions: [
            // ✅ أيقونة الأرشفة بالأعلى (بدل زر الفاتورة) + منع الأرشفة قبل «مكتملة»
           // ✅ أيقونة الأرشفة بالأعلى (بدل زر الفاتورة) + منع الأرشفة قبل «مكتملة»
IconButton(
  tooltip: item.isArchived ? 'فك الأرشفة' : 'أرشفة',
  onPressed: () async {
    // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    // ✅ منع الأرشفة قبل «مكتملة»
    if (!item.isArchived && item.status != MaintenanceStatus.completed) {
      await _showArchiveBlockedDialog(context);
      return;
    }

    // الحالة الجديدة للأرشفة
    final bool newArchived = !item.isArchived;
    item.isArchived = newArchived;

    final box = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

    if (item.isInBox) {
      await item.save();
    } else {
      await box.put(item.id, item);
    }

    // ✅ مزامنة حالة الأرشفة مع الفاتورة المرتبطة (إن وجدت)
    try {
      if (item.invoiceId != null && item.invoiceId!.isNotEmpty) {
        final invBox = Hive.box<Invoice>(boxName('invoicesBox'));
        final inv = invBox.get(item.invoiceId);
        if (inv != null) {
          inv.isArchived = newArchived;
          await inv.save();
        }
      }
    } catch (_) {
      // تجاهل أي خطأ هنا حتى لا يمنع الأرشفة عن طلب الصيانة
    }

    unawaited(_maintenanceUpsertFS(item));

    if (context.mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newArchived ? 'تمت الأرشفة' : 'تم فك الأرشفة',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
    }
  },
  icon: Icon(
    item.isArchived ? Icons.inventory_2_rounded : Icons.archive_rounded,
    color: Colors.white,
  ),
),

            // ✅ حذف مع الرسالة الجديدة
                     IconButton(
              tooltip: 'حذف',
              onPressed: () async {
              if (await OfficeClientGuard.blockIfOfficeClient(context)) return;
                // 🚫 منع حذف طلب الصيانة بعد صدور الفاتورة له
                if (item.status == MaintenanceStatus.completed &&
                    item.invoiceId?.isNotEmpty == true) {
                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF0B1220),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      actionsAlignment: MainAxisAlignment.center,
                      title: Text(
                        'لا يمكن الحذف',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      content: Text(
                        'لا يمكن حذف طلب الصيانة بعد صدور الفاتورة له.\n'
                        'يمكنك فقط أرشفة طلب الصيانة إذا لم تعد بحاجة لظهوره.',
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'حسنًا',
                            style: GoogleFonts.cairo(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  return; // ❗ منع الحذف نهائيًا
                }

                final ok = await _confirm(
                  context,
                  'حذف الطلب',
                  'هل انت متأكد من حذف هذا الطلب سيتم حذف الفاتورة المرتبة بهذا الطلب',
                );
                if (!ok) return;

                try {
                  await _deleteMaintenanceAndInvoice(item);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم الحذف',
                          style: GoogleFonts.cairo(),
                        ),
                      ),
                    );
                    Navigator.of(context).pop(); // ارجع للقائمة
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تعذّر الحذف: $e',
                          style: GoogleFonts.cairo(),
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
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
                      Color(0xFF0F3A8C),
                      Color(0xFF1E40AF),
                      Color(0xFF2148C6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child:
                    _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child:
                    _softCircle(260.r, const Color(0x22FFFFFF))),
            SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56.w,
                              height: 56.w,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(12.r),
                                gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1E40AF),
                                      Color(0xFF2148C6)
                                    ],
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft),
                              ),
                              child: const Icon(Icons.build_rounded,
                                  color: Colors.white),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(item.title,
                                      maxLines: 2,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(
                                          color: Colors.white,
                                          fontWeight:
                                              FontWeight.w800,
                                          fontSize: 16.sp)),
                                  SizedBox(height: 4.h),
                                  // اسم العقار (قابل للنقر دائمًا)
                                  InkWell(
                                    onTap: () async {
                                      await Navigator.pushNamed(
                                        context,
                                        '/property/details',
                                        arguments:
                                            item.propertyId,
                                      );
                                    },
                                    child: Text(
                                      p?.name ?? '—',
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        fontWeight:
                                            FontWeight.w700,
                                        fontSize: 13.5.sp,
                                        decoration: TextDecoration
                                            .underline,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Wrap(
                                    spacing: 8.w,
                                    runSpacing: 8.h,
                                    children: [
                                      InkWell(
                                        onTap: () async {
                                          final host = context
                                              .findAncestorStateOfType<
                                                  _MaintenanceScreenState>();
                                          if (host != null) {
                                            await host
                                                ._changeStatus(
                                                    context,
                                                    item);
                                          } else {
                                            await _openChangeStatusSheetLocal(
                                                item);
                                          }
                                          if (mounted) {
                                            setState(() {});
                                          }
                                        },
                                        child: _chip(
                                            _statusText(
                                                item.status),
                                            bg: _statusColor(
                                                item.status)),
                                      ),
                                      _chip('النوع: ${item.requestType}',
                                          bg: const Color(
                                              0xFF1F2937)),
                                      _chip(
                                          'الأولوية: ${_priorityText(item.priority)}',
                                          bg: _priorityColor(
                                              item.priority)),

                                      _chip(
                                          'البدء: ${_fmtDateOrDashDynamic(item.scheduledDate)}',
                                          bg: const Color(
                                              0xFF1F2937)),
                                      if (item.completedDate !=
                                          null)
                                        _chip(
                                            'اكتملت: ${_fmtDateDynamic(item.completedDate!)}',
                                            bg: const Color(
                                                0xFF1F2937)),
                                      if (item.assignedTo
                                              ?.isNotEmpty ==
                                          true)
                                        _chip(
                                            'جهة التنفيذ: ${item.assignedTo}',
                                            bg: const Color(
                                                0xFF1F2937)),
if (item.cost > 0)
  _chip(
      'التكلفة: ${_fmtMoneyTrunc(item.cost)} ريال',
      bg: const Color(0xFF1F2937)),

   // 👇 جديد: "إنشاء" في أسفل البطاقة وباللون المميز
    if (item.createdAt != null)
      _chip(
        'تاريخ الإنشاء: ${_fmtDateDynamic(item.createdAt!)}',
        bg: const Color(0xFF1D4ED8),
      ),


                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8.w,
                      children: [
                                              _miniAction(
                          icon: Icons.edit_rounded,
                          label: 'تعديل',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من تعديل طلب الصيانة
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            if (item.status == MaintenanceStatus.completed) {
                              await showEditBlockedDialog(context);
                              return;
                            }

                            final updated = await Navigator.of(context)
                                .push<MaintenanceRequest?>(
                              MaterialPageRoute(
                                builder: (_) => AddOrEditMaintenanceScreen(existing: item),
                              ),
                            );
                            if (updated != null && context.mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تم التحديث',
                                    style: GoogleFonts.cairo(),
                                  ),
                                ),
                              );
                            }
                          },
                        ),

                        _miniAction(
                          icon: Icons.description_outlined,
                          label: 'الوصف',
                          bg: const Color(0xFF334155),
                          onTap: () async {
                            // 🚫 منع عميل المكتب من تعديل الوصف
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            _showDescriptionSheet(context, item);
                          },
                        ),

                                              if (item.status == MaintenanceStatus.open ||
                            item.status == MaintenanceStatus.inProgress)
                          _miniAction(
                            icon: Icons.autorenew_rounded,
                            label: 'تغيير الحالة',
                            bg: const Color(0xFFF59E0B),
                            onTap: () async {
                              // 🚫 منع عميل المكتب من تغيير حالة الطلب
                              if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                              final host = context
                                  .findAncestorStateOfType<_MaintenanceScreenState>();
                              if (host != null) {
                                await host._changeStatus(context, item);
                              } else {
                                await _openChangeStatusSheetLocal(item);
                              }
                              if (mounted) setState(() {});
                            },
                          ),

                        if (item.invoiceId?.isNotEmpty == true)
  _miniAction(
    icon: Icons.receipt_long_rounded,
    label: 'عرض الفاتورة',
    bg: const Color(0xFF0EA5E9),
    onTap: () async {
      // فتح تفاصيل الفاتورة مباشرة بدون المرور بشاشة قائمة الفواتير
      if (item.invoiceId == null || item.invoiceId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا توجد فاتورة مرتبطة بهذا الطلب.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
        return;
      }

      try {
        final invBox = Hive.box<Invoice>(boxName('invoicesBox'));
        final invoice = invBox.get(item.invoiceId);
        if (invoice == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تعذّر العثور على الفاتورة المرتبطة بهذا الطلب.',
                style: GoogleFonts.cairo(),
              ),
            ),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailsScreen(invoice: invoice),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء فتح الفاتورة.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
    },
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
          currentIndex: 0,
          onTap: _handleBottomTap,
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
        padding: EdgeInsets.symmetric(
            horizontal: 10.w, vertical: 6.h),
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
            Text(label,
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp)),
          ],
        ),
      ),
    );
  }
}

Future<void> _deleteMaintenanceAndInvoice(MaintenanceRequest m) async {
  try {
    // 1) احذف الفاتورة المرتبطة (لو فيه)
    if (m.invoiceId?.isNotEmpty == true) {
      final invBox = Hive.box<Invoice>(boxName('invoicesBox'));
      if (invBox.containsKey(m.invoiceId)) {
        await invBox.delete(m.invoiceId);
      } else {
        for (final k in invBox.keys) {
          final v = invBox.get(k);
          if (v?.id == m.invoiceId) {
            await invBox.delete(k);
            break;
          }
        }
      }
    }

    // 2) احذف طلب الصيانة نفسه
if (m.isInBox) {
  final box = Hive.box<MaintenanceRequest>(boxName('maintenanceBox'));
  dynamic keyToDelete;

  // ابحث عن المفتاح الذي يقابل الـ id
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is MaintenanceRequest && v.id == m.id) {
      keyToDelete = k;
      break;
    }
  }

  if (keyToDelete != null) {
    await box.delete(keyToDelete); // ← هذا هو الصحيح
    unawaited(_maintenanceDeleteFS(m.id));
  }
  return;
}


    if (m.box != null) {
      await m.box!.delete(m.id);
      unawaited(_maintenanceDeleteFS(m.id));
      return;
    }

    // بديل أخير: ابحث عن المفتاح بمطابقة حقل id
    final maintBox = Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

    dynamic keyToDelete;
    for (final k in maintBox.keys) {
      final v = maintBox.get(k);
      if (v?.id == m.id) {
        keyToDelete = k;
        break;
      }
    }
    if (keyToDelete != null) {
      await maintBox.delete(keyToDelete); // ← كان هنا الخطأ
      unawaited(_maintenanceDeleteFS(m.id));
    }
  } catch (e) {
    debugPrint('Delete maintenance/invoice failed: $e');
    rethrow;
  }
}

/// ===============================================================================
/// إنشاء/تعديل
/// ===============================================================================
class AddOrEditMaintenanceScreen extends StatefulWidget {
  final MaintenanceRequest? existing;
  const AddOrEditMaintenanceScreen({super.key, this.existing});

  @override
  State<AddOrEditMaintenanceScreen> createState() =>
      _AddOrEditMaintenanceScreenState();
}

class _AddOrEditMaintenanceScreenState
    extends State<AddOrEditMaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();

  Property? _property;

  final _title = TextEditingController();
  final _desc = TextEditingController();

  MaintenancePriority _priority = MaintenancePriority.medium;
  MaintenanceStatus _status = MaintenanceStatus.open;

  DateTime? _schedule;
  final _assigned = TextEditingController(); // «جهة التنفيذ»
  final _cost = TextEditingController(text: '0');

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
        final now = DateTime.now();
        if (_lastExceedShownAt == null ||
            now.difference(_lastExceedShownAt!).inMilliseconds > 800) {
          _lastExceedShownAt = now;
          _showTempSnack(exceedMsg);
        }
        return oldValue; // منع الزيادة
      }
      return newValue;
    });
  }

  Box<MaintenanceRequest> get _box =>
      Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

  Box<Property> get _properties =>
      Hive.box<Property>(boxName('propertiesBox'));

  bool get isEdit => widget.existing != null;

  // BottomNav + Drawer
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
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
            context,
            MaterialPageRoute(
                builder: (_) => const tenants_ui.TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen()));
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isEdit) {
      final m = widget.existing!;
      if (_title.text.isEmpty &&
          _desc.text.isEmpty &&
          _assigned.text.isEmpty) {
        // تحميل بيانات الطلب
        final pMatch =
            _properties.values.where((p) => p.id == m.propertyId);
        if (pMatch.isNotEmpty) _property = pMatch.first;

        _title.text = m.title;
        _desc.text = m.description;
        _priority = m.priority;
        _status = m.status;
        _schedule = m.scheduledDate;
        _assigned.text = m.assignedTo ?? '';
        if (m.cost > 0) _cost.text = m.cost.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _assigned.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ حذف "ملغاة" من شاشة الإضافة/التعديل
    final statusesNoCanceled = MaintenanceStatus.values
        .where((s) => s != MaintenanceStatus.canceled)
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        

        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset =
                kToolbarHeight + media.padding.top;
            final double bottomInset =
                _bottomBarHeight + media.padding.bottom;
            return Padding(
              padding: EdgeInsets.only(
                  top: topInset, bottom: bottomInset),
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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text(isEdit ? 'تعديل طلب' : 'طلب صيانة جديد',
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800)),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF0F3A8C),
                      Color(0xFF1E40AF),
                      Color(0xFF2148C6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child:
                    _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child:
                    _softCircle(260.r, const Color(0x22FFFFFF))),
            SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
              child: _DarkCard(
                padding: EdgeInsets.all(16.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // 1) العقار/الوحدة (مطلوب)
                      _selectorTile(
                        title: 'العقار/الوحدة (مطلوب)',
                        valueText: _property?.name ??
                            'اختر عقارًا/وحدة',
                        onTap: _pickProperty,
                        leading: const Icon(
                            Icons.home_work_rounded,
                            color: Colors.white),
                        errorText:
                            _property == null ? 'مطلوب' : null,
                      ),
                      SizedBox(height: 12.h),

                      _field(
                        controller: _title,
                        label: 'عنوان الطلب',
                        inputFormatters: [
                          _limitWithFeedbackFormatter(max: 35, exceedMsg: 'تجاوزت الحد الأقصى (35)'),
                        ],
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'مطلوب';
                          if (s.length > 35) return 'تجاوزت الحد الأقصى (35) حرفاً';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

_field(
  controller: _desc,
  label: 'الوصف',
  maxLines: 4,
  inputFormatters: [
    _limitWithFeedbackFormatter(
      max: 2000,
      exceedMsg: 'تجاوزت الحد الأقصى (2000)',
    ),
  ],
  validator: (v) {
    final s = (v ?? '').trim();
    if (s.length > 2000) {
      return 'تجاوزت الحد الأقصى (2000) حرفاً';
    }
    return null;
  },
),
SizedBox(height: 12.h),


                      Row(
                        children: [
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    MaintenancePriority>(
                              value: _priority,
                              decoration: _dd('الأولوية'),
                              dropdownColor:
                                  const Color(0xFF0F172A),
                              iconEnabledColor:
                                  Colors.white70,
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w700),
                              items: MaintenancePriority
                                  .values
                                  .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(
                                          _priorityText(p))))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _priority =
                                      v ?? _priority),
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    MaintenanceStatus>(
                              value: _status,
                              decoration: _dd('الحالة'),
                              dropdownColor:
                                  const Color(0xFF0F172A),
                              iconEnabledColor:
                                  Colors.white70,
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w700),
                              items: statusesNoCanceled
                                  .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                          _statusText(s))))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _status =
                                      v ?? _status),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      InkWell(
                        borderRadius:
                            BorderRadius.circular(12.r),
                        onTap: () async {
                          final now = KsaTime.now();
                          final picked =
                              await showDatePicker(
                            context: context,
                            initialDate: _schedule ?? now,
                            firstDate:
                                DateTime(now.year - 1),
                            lastDate: DateTime(
                                now.year + 2),
                            helpText:
                                'موعد التنفيذ (اختياري)',
                            confirmText: 'اختيار',
                            cancelText: 'إلغاء',
                            builder: (context, child) =>
                                Theme(
                              data:
                                  Theme.of(context).copyWith(
                                colorScheme:
                                    const ColorScheme.dark(
                                  primary: Colors.white,
                                  onPrimary: Colors.black,
                                  surface:
                                      Color(0xFF0B1220),
                                  onSurface:
                                      Colors.white,
                                ),
                                dialogBackgroundColor:
                                    const Color(0xFF0B1220),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() => _schedule = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: _dd(
                              'موعد التنفيذ (اختياري)'),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded,
                                  color: Colors.white70),
                              SizedBox(width: 8.w),
                              Text(
                                  _fmtDateOrDashDynamic(
                                      _schedule),
                                  style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight:
                                          FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),

                     Row(
  children: [
    Expanded(
      child: _field(
        controller: _assigned,
        label: 'جهة التنفيذ',
        inputFormatters: [
          _limitWithFeedbackFormatter(
            max: 50,
            exceedMsg: 'تجاوزت الحد الأقصى (50)',
          ),
        ],
        validator: (v) {
          final s = (v ?? '').trim();
          if (s.isEmpty) return null; // لو تبغاه اختياري
          if (s.length > 50) {
            return 'تجاوزت الحد الأقصى (50) حرفاً';
          }
          return null;
        },
      ),
    ),
    SizedBox(width: 10.w),
    Expanded(
      child: _field(
        controller: _cost,
        label: 'التكلفة (اختياري)',
        keyboardType:
            const TextInputType.numberWithOptions(
                decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(r'^\d*\.?\d{0,2}$'),
          ),
          // 👇 تقييد 100 مليون مع نفس التنبيه
          TextInputFormatter.withFunction(
            (oldValue, newValue) {
              final text = newValue.text;
              if (text.isEmpty) return newValue;

              final n = double.tryParse(text);
              if (n == null) return oldValue;

              if (n > 100000000) {
                final now = DateTime.now();
                if (_lastExceedShownAt == null ||
                    now
                            .difference(
                                _lastExceedShownAt!)
                            .inMilliseconds >
                        800) {
                  _lastExceedShownAt = now;
                  _showTempSnack(
                      'تجاوزت الحد الأقصى (100,000,000)');
                }
                return oldValue; // منع الزيادة
              }

              return newValue;
            },
          ),
        ],
      ),
    ),
  ],
),

                      SizedBox(height: 16.h),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF0EA5E9),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: 12.h),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12.r)),
                          ),
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                              isEdit
                                  ? 'حفظ التعديلات'
                                  : 'حفظ الطلب',
                              style: GoogleFonts.cairo(
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // ——— Bottom Nav
        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  // عناصر الإدخال المشتركة
  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide:
                BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius:
                BorderRadius.all(Radius.circular(12))),
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
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      style: GoogleFonts.cairo(color: Colors.white),
      decoration: _dd(label),
    );
  }

  Widget _selectorTile({
    required String title,
    required String valueText,
    required VoidCallback? onTap,
    required Widget leading,
    String? errorText,
  }) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: onTap,
          child: InputDecorator(
            decoration:
                _dd(title).copyWith(errorText: errorText),
            child: Row(
              children: [
                leading,
                SizedBox(width: 8.w),
                Expanded(
                    child: Text(valueText,
                        style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700))),
                const Icon(Icons.arrow_drop_down,
                    color: Colors.white70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickProperty() async {
    final result = await showModalBottomSheet<Property>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _PropertyPickerSheet(),
    );
    if (result != null) {
      setState(() {
        _property = result;
      });
    }
  }

    Future<void> _save() async {
    // التحقق من صحة الحقول
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // يجب اختيار عقار/وحدة
    if (_property == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اختر العقار/الوحدة',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }

    // قراءة التكلفة (إن وجدت)
    final cost = double.tryParse(_cost.text.trim());
    final m = widget.existing;

    // ==========================
    // حالة "تعديل" طلب موجود
    // ==========================
    if (isEdit && m != null) {
      m.propertyId = _property!.id;
      m.tenantId = tenantIdForProperty(_property!.id); // ← ربط مبسّط
      m.title = _title.text.trim();
      m.description = _desc.text.trim();
      // requestType يظل "صيانة" افتراضيًا
      m.priority = _priority;
      m.status = _status;
      m.scheduledDate = _schedule;
      m.assignedTo =
          _assigned.text.trim().isEmpty ? null : _assigned.text.trim();
      m.cost = cost == null || cost < 0 ? m.cost : cost;

      // ✅ لو الحالة الآن "مكتمل" ولا يوجد فاتورة بعد → نصدر/نحدّث الفاتورة
      if (_status == MaintenanceStatus.completed &&
          (m.invoiceId == null || m.invoiceId!.isEmpty)) {
        // لو ما في completedDate نحط الآن
        m.completedDate ??= KsaTime.now();

        final invId = await createOrUpdateInvoiceForMaintenance(m);
        if (invId.isNotEmpty) {
          m.invoiceId = invId;
        }
      }

      final box =
          Hive.box<MaintenanceRequest>(HiveService.maintenanceBoxName());

      if (m.isInBox) {
        await m.save();
      } else {
        await box.put(m.id, m);
      }

      unawaited(_maintenanceUpsertFS(m));

      if (!mounted) return;
      Navigator.of(context).pop(m);
    }

    // ==========================
    // حالة "إضافة" طلب جديد
    // ==========================
    else {
      final n = MaintenanceRequest(
        propertyId: _property!.id,
        tenantId: tenantIdForProperty(_property!.id), // ← ربط مبسّط
        title: _title.text.trim(),
        description: _desc.text.trim(),
        // requestType يظل "صيانة" افتراضيًا (القيمة الافتراضية في الموديل)
        priority: _priority,
        status: _status,
        scheduledDate: _schedule,
        // لو أضفنا الطلب مباشرة كمكتمل نضع completedDate الآن
        completedDate:
            _status == MaintenanceStatus.completed ? KsaTime.now() : null,
        assignedTo:
            _assigned.text.trim().isEmpty ? null : _assigned.text.trim(),
        cost: cost == null || cost < 0 ? 0.0 : cost,
      );

      // ✅ لو الطلب جديد وتم حفظه مباشرة بحالة "مكتمل" → نصدر الفاتورة فورًا
      if (_status == MaintenanceStatus.completed) {
        final invId = await createOrUpdateInvoiceForMaintenance(n);
        if (invId.isNotEmpty) {
          n.invoiceId = invId;
        }
      }

      await _box.put(n.id, n);
      unawaited(_maintenanceUpsertFS(n));

      if (!mounted) return;
      Navigator.of(context).pop(n);
    }
  }

}

/// ===============================================================================
/// Picker للعقار فقط
/// ===============================================================================
class _PropertyPickerSheet extends StatefulWidget {
  const _PropertyPickerSheet();

  @override
  State<_PropertyPickerSheet> createState() =>
      _PropertyPickerSheetState();
}

class _PropertyPickerSheetState
    extends State<_PropertyPickerSheet> {
  Box<Property> get _properties =>
      Hive.box<Property>(boxName('propertiesBox'));
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم العقار/العنوان',
                  hintStyle:
                      GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(
                        color:
                            Colors.white.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(
                        color:
                            Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        const BorderSide(color: Colors.white),
                    borderRadius:
                        BorderRadius.circular(12.r),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _properties.listenable(),
                  builder: (context, Box<Property> b, _) {
                    var items = b.values.toList();

                    if (_q.isNotEmpty) {
                      final q = _q.toLowerCase();
                      items = items
                          .where((p) =>
                              p.name
                                  .toLowerCase()
                                  .contains(q) ||
                              p.address
                                  .toLowerCase()
                                  .contains(q))
                          .toList();
                    }
                    items.sort((a, c) =>
                        a.name.compareTo(c.name));

                    if (items.isEmpty) {
                      return Center(
                          child: Text('لا توجد عناصر',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight:
                                      FontWeight.w700)));
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: 6.h),
                      itemBuilder: (_, i) {
                        final p = items[i];
                        return ListTile(
                          onTap: () =>
                              Navigator.of(context).pop(p),
                          leading: const Icon(
                              Icons.home_work_rounded,
                              color: Colors.white),
                          title: Text(p.name,
                              style: GoogleFonts.cairo(
                                  color: Colors.white)),
                          subtitle: Text(p.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                  color: Colors.white70)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================================
/// مسارات NamedRoutes
/// ===============================================================================
class MaintenanceRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/maintenance': (context) => const MaintenanceScreen(),
        '/maintenance/new': (context) => const AddOrEditMaintenanceScreen(),
      };
}
