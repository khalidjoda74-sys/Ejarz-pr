// lib/ui/invoices_screen.dart
// شاشة الفواتير: موديل + Adapter + شاشات (قائمة/تفاصيل/سجل عقد)
// ملاحظة: أضِف مسارات هذا الملف إلى MaterialApp.routes عبر InvoicesRoutes.routes()
// وسجّل الـAdapter: Hive.registerAdapter(InvoiceAdapter());

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart'; // ✅ جديد
// ✅ مهم: نفس أسلوب المستأجرين
import '../data/services/user_scope.dart' as scope;
import '../data/constants/boxes.dart' as bx;

import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart';
import 'contracts_screen.dart' show Contract, AdvanceMode, ContractTerm, PaymentCycle;
import 'contracts_screen.dart' as contracts_ui show ContractsScreen;

import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

import '../models/tenant.dart';
import '../models/property.dart';
import '../utils/ksa_time.dart';
import '../widgets/darvoo_app_bar.dart';


// ✅ أسماء الصناديق per-uid عبر user_scope بنفس نمط الشاشات الأخرى
String invoicesBoxName()  => scope.boxName(bx.kInvoicesBox);
String tenantsBoxName()   => scope.boxName(bx.kTenantsBox);
String propsBoxName()     => scope.boxName(bx.kPropertiesBox);
String contractsBoxName() => scope.boxName(bx.kContractsBox);

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

/// ===============================================================================
/// موديل الفاتورة + Adapter
/// ===============================================================================
class Invoice extends HiveObject {
  String id;
  String? serialNo; // ← جديد: 2025-0003

  String tenantId;
  String contractId;
  String propertyId;

  DateTime issueDate;
  DateTime dueDate;

  double amount;
  double paidAmount;
  String currency;

  String? note;
  String paymentMethod;

  bool isArchived;
  bool isCanceled;

  DateTime createdAt;
  DateTime updatedAt;

  Invoice({
    String? id,
    this.serialNo,
    required this.tenantId,
    required this.contractId,
    required this.propertyId,
    required this.issueDate,
    required this.dueDate,
    required this.amount,
    this.paidAmount = 0.0,
    this.currency = 'SAR',
    this.note,
    this.paymentMethod = 'نقدًا',
    this.isArchived = false,
    this.isCanceled = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? KsaTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? KsaTime.now(),
        updatedAt = updatedAt ?? KsaTime.now();

  double get remaining {
    final r = amount - paidAmount;
    return r < 0 ? 0 : r;
  }

  bool get isPaid => !isCanceled && remaining <= 0.000001;

  bool get isOverdue {
    if (isPaid || isCanceled) return false;
    final d = KsaTime.dateOnly(dueDate);
    final t = KsaTime.today();
    return d.isBefore(t);
  }
}

class InvoiceAdapter extends TypeAdapter<Invoice> {
  @override
  final int typeId = 50;

  @override
  Invoice read(BinaryReader r) {
    final numOfFields = r.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) r.readByte(): r.read(),
    };
    return Invoice(
      id: fields[0] as String?,
      serialNo: fields[15] as String?, // ← جديد (قد يكون null في بيانات قديمة)
      tenantId: fields[1] as String,
      contractId: fields[2] as String,
      propertyId: fields[3] as String,
      issueDate: fields[4] as DateTime,
      dueDate: fields[5] as DateTime,
      amount:     (fields[6] as num?)?.toDouble() ?? 0.0,
      paidAmount: (fields[7] as num?)?.toDouble() ?? 0.0,
      currency: fields[8] as String? ?? 'SAR',
      note: fields[9] as String?,
      paymentMethod: fields[10] as String? ?? 'نقدًا',
      isArchived: fields[11] as bool? ?? false,
      isCanceled: fields[12] as bool? ?? false,
      createdAt: fields[13] as DateTime? ?? KsaTime.now(),
      updatedAt: fields[14] as DateTime? ?? KsaTime.now(),
    );
  }

  @override
  void write(BinaryWriter w, Invoice i) {
    w
      ..writeByte(16)                 // ← ازداد إلى 16 حقلًا
      ..writeByte(0)..write(i.id)
      ..writeByte(1)..write(i.tenantId)
      ..writeByte(2)..write(i.contractId)
      ..writeByte(3)..write(i.propertyId)
      ..writeByte(4)..write(i.issueDate)
      ..writeByte(5)..write(i.dueDate)
      ..writeByte(6)..write(i.amount)
      ..writeByte(7)..write(i.paidAmount)
      ..writeByte(8)..write(i.currency)
      ..writeByte(9)..write(i.note)
      ..writeByte(10)..write(i.paymentMethod)
      ..writeByte(11)..write(i.isArchived)
      ..writeByte(12)..write(i.isCanceled)
      ..writeByte(13)..write(i.createdAt)
      ..writeByte(14)..write(i.updatedAt)
      ..writeByte(15)..write(i.serialNo); // ← جديد
  }
}

/// ===============================================================================
/// تنسيق
/// ===============================================================================
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool get _useHijri {
  if (!Hive.isBoxOpen('sessionBox')) return false;
  try {
    return Hive.box('sessionBox').get('useHijri', defaultValue: false) == true;
  } catch (_) {
    return false;
  }
}

String _fmtDateDynamic(DateTime d) {
  final dd = KsaTime.dateOnly(d); // ✅ اعتمد يوم الرياض فقط
  if (!_useHijri) return _fmtDate(dd);
  final h = HijriCalendar.fromDate(dd);
  final yy = h.hYear.toString();
  final mm = h.hMonth.toString().padLeft(2, '0');
  final ddh = h.hDay.toString().padLeft(2, '0');
  return '$yy-$mm-$ddh هـ';
}

String _fmtMoneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
}

Widget _softCircle(double size, Color color) => Container(
  width: size, height: size,
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
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0x26FFFFFF)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0,10))],
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
  child: Text(text, style: GoogleFonts.cairo(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700)),
);

String _limitChars(String t, int max) => t.length <= max ? t : '${t.substring(0, max)}…';

Color _statusColor(Invoice inv) {
  if (inv.isCanceled) return const Color(0xFF7F1D1D);
  if (inv.isPaid) return const Color(0xFF065F46);
  if (inv.isOverdue) return const Color(0xFFB91C1C);
  return const Color(0xFF0EA5E9);
}

String _statusText(Invoice inv) {
  if (inv.isCanceled) return 'ملغاة';
  if (inv.isPaid) return 'مدفوعة';
  if (inv.isOverdue) return 'متأخرة';
  return 'غير مدفوعة';
}

// يحدد نوع الفاتورة للعرض
String _invoiceKind(dynamic inv) => _isMaintenanceAny(inv) ? 'فاتورة صيانة' : 'فاتورة عقد';

// يتحقق هل الفاتورة صيانة (يدعم Map أو Invoice) مع Fallback على الملاحظات
bool _isMaintenanceAny(dynamic inv) {
  try {
    if (inv is Map) {
      final kind = (inv['type'] ?? inv['requestType'])?.toString().toLowerCase() ?? '';
      if (kind.contains('صيانة') || kind.contains('maintenance')) return true;

      // fallback: لو ما فيه type، جرّب الملاحظات
      final notes = (inv['notes'] ?? '').toString().toLowerCase();
      return notes.contains('صيانة') || notes.contains('maintenance');
    } else {
      // كائن Invoice: ما فيه type، فاعتمد على note كـ fallback
      final note = (inv as dynamic).note?.toString().toLowerCase() ?? '';
      return note.contains('صيانة') || note.contains('maintenance');
    }
  } catch (_) {
    return false;
  }
}

/// ===============================================================================
/// توليد رقم تسلسلي للفاتورة (YYYY-####) مع تخزين آخر تسلسل في sessionBox
/// ===============================================================================
/// مولّد رقم الفاتورة بناءً على أعلى رقم موجود في نفس السنة داخل صندوق الفواتير فقط
String _nextInvoiceSerialSync(Box<Invoice> invoices) {
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

/// ===============================================================================
/// شاشـة القـائمة
/// ===============================================================================

enum _OriginFilter { all, contracts, maintenance }
enum _ContractScope { all, active, ended }
enum _ArchFilter { archived, unarchived } // ← يطبّق دائمًا على القائمة

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  Box<Invoice> get _invoices => Hive.box<Invoice>(invoicesBoxName());
  Box<Tenant> get _tenants => Hive.box<Tenant>(tenantsBoxName());
  Box<Property> get _properties => Hive.box<Property>(propsBoxName());
  Box<Contract> get _contracts => Hive.box<Contract>(contractsBoxName());

  String _q = '';

  // فلاتر
  _OriginFilter   _fOrigin = _OriginFilter.all;        // افتراضي: الكل
  _ContractScope? _fContractScope;                     // null حتى يُختار
  _ArchFilter     _fArch   = _ArchFilter.unarchived;   // افتراضي: غير مؤرشفة

  String? _openInvoiceId;      // يأتينا من شاشة الصيانة
  bool _didHandleOpen = false; // حتى لا يتكرر الفتح

  // تمييز فواتير الصيانة من الملاحظة
  bool _isMaintenance(Invoice inv) {
    final n = (inv.note ?? '').toLowerCase();
    return n.contains('صيانة') || n.contains('maintenance');
  }

  StreamSubscription<BoxEvent>? _rawListen;

  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  bool _invoicesReady = false; // ✅ لا نستخدم الصندوق داخل build قبل الفتح

  // === افتح صندوق الفواتير Typed قبل أي استعمال (محلي داخل الكلاس) ===
  Future<Box<Invoice>> _ensureInvoicesBoxTyped() async {
    final adapter = InvoiceAdapter();
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }

    if (Hive.isBoxOpen(invoicesBoxName())) {
      return Hive.box<Invoice>(invoicesBoxName());
    }
    return await Hive.openBox<Invoice>(invoicesBoxName());
  }

  @override
  void initState() {
    super.initState();
    // افتح الصناديق (per-uid) وسجّل المراقب ثم افتح التفاصيل لو مطلوبة
    Future.microtask(() async {
      // يضمن فتح صناديق المستخدم وفضّ الـ aliases مبكرًا
      await HiveService.ensureReportsBoxesOpen();

      // تأكيد تسجيل الـAdapter وفتح صندوق الفواتير typed إن لم يُفتح
      await _ensureInvoicesBoxTyped();

      await _bootstrapRawWatcher();

      if (mounted) {
        setState(() => _invoicesReady = true);
      }

      // افتح الفاتورة لو جاي من شاشة الصيانة وتم تمرير openId
      if (mounted && _openInvoiceId != null) {
        final inv = Hive.box<Invoice>(invoicesBoxName()).get(_openInvoiceId!);
        _openInvoiceId = null;
        if (inv != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoice: inv)),
          );
        }
      }
    });

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
    if (_didHandleOpen) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['openId'] is String && (args['openId'] as String).isNotEmpty) {
      _openInvoiceId = args['openId'] as String;
    }
    _didHandleOpen = true;
  }

  @override
  void dispose() {
    _rawListen?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapRawWatcher() async {
    try {
      final Box raw = Hive.box(invoicesBoxName());
      await _migrateAnyRawEntries(raw);
      _rawListen = raw.watch().listen((e) {
        final v = e.value;
        if (v is Map) {
          final inv = _mapToInvoice(v);
          raw.put(e.key, inv);
        }
      });
    } catch (_) {}
  }

  Future<void> _migrateAnyRawEntries(Box raw) async {
    try {
      for (final k in raw.keys) {
        final v = raw.get(k);
        if (v is Map) {
          final inv = _mapToInvoice(v);
          await raw.put(k, inv);
        } else if (v is Invoice && (v.serialNo == null || v.serialNo!.isEmpty)) {
          // عيّن رقمًا تلقائيًا للقديمة بدون رقم
          v.serialNo = _nextInvoiceSerialSync(_invoices);
          v.updatedAt = KsaTime.now();
          await v.save();
        }
      }
    } catch (_) {}
  }

  bool _contractEndedBy(Invoice inv) {
    final c = firstWhereOrNull(_contracts.values, (x) => x.id == inv.contractId);
    if (c == null) return false; // غير مربوط بعقد

    // ✅ منتهي يدويًا أو بالتاريخ
    if (c.isTerminated == true) return true;

    final today = KsaTime.today();
    return !today.isBefore(c.endDate); // اليوم >= نهاية العقد
  }

  Future<void> _showBlockDialog(String msg) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('لا يمكن الأرشفة',
            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(msg, style: GoogleFonts.cairo(color: Colors.white70)),
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

  /// يُسمح بالأرشفة إذا كانت الفاتورة غير مدفوعة.
  /// إن كانت "مدفوعة": تُسمح فقط إذا كانت مربوطة بعقد منتهي.
  Future<bool> _ensureCanArchive(Invoice inv) async {
    // ✅ السماح دائمًا لفواتير الصيانة
    if (_isMaintenanceAny(inv)) return true;

    if (!inv.isPaid) return true;
    if ((inv.contractId).isEmpty) {
      await _showBlockDialog('لا يمكن أرشفة الفاتورة المدفوعة لأنها غير مرتبطة بعقد.');
      return false;
    }
    if (!_contractEndedBy(inv)) {
      await _showBlockDialog('لا يمكن أرشفة الفاتورة المدفوعة إلا إذا كان العقد منتهي.');
      return false;
    }
    return true;
  }

  Invoice _mapToInvoice(Map m) {
    final id         = (m['id'] as String?) ?? KsaTime.now().microsecondsSinceEpoch.toString();
    final tenantId   = (m['tenantId'] as String?) ?? '';
    final propertyId = (m['propertyId'] as String?) ?? '';

    final issueDate  = (m['date']    is DateTime) ? m['date']    as DateTime : KsaTime.now();
    final dueDate    = (m['dueDate'] is DateTime) ? m['dueDate'] as DateTime : issueDate;

    final note      = (m['notes'] as String?);
    final createdAt = (m['createdAt'] is DateTime) ? m['createdAt'] as DateTime : KsaTime.now();

    String contractId = (m['contractId'] as String?) ?? '';
    if (contractId.isEmpty) {
      try {
        final dt = issueDate;
        final match = firstWhereOrNull(_contracts.values, (c) =>
          c.tenantId == tenantId &&
          c.propertyId == propertyId &&
          !dt.isBefore(c.startDate) &&
          !dt.isAfter(c.endDate)
        );
        contractId = match?.id ?? '';
      } catch (_) {}
    }

    final Contract? c = firstWhereOrNull(_contracts.values, (x) => x.id == contractId);

    double amount = 0.0;
    if (m['amount'] is num) {
      amount = (m['amount'] as num).toDouble();
    } else if (c != null) {
      amount = c.rentAmount;
    }

    final String currency = (m['currency'] as String?) ?? (c?.currency ?? 'SAR');
    final double paidAmount = (m['paidAmount'] is num) ? (m['paidAmount'] as num).toDouble() : amount; // تركناها كالسابق

    // رقم الفاتورة
    final serialNo = (m['serialNo'] as String?) ?? _nextInvoiceSerialSync(_invoices);

    return Invoice(
      id: id,
      serialNo: serialNo,
      tenantId: tenantId,
      contractId: contractId,
      propertyId: propertyId,
      issueDate: issueDate,
      dueDate: dueDate,
      amount: amount,
      paidAmount: paidAmount,
      currency: currency,
      note: note,
      paymentMethod: 'نقدًا',
      createdAt: createdAt,
      updatedAt: KsaTime.now(),
    );
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); break;
      case 1: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen())); break;
      case 2: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TenantsScreen())); break;
      case 3: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen())); break;
    }
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        var tOrigin = _fOrigin;
        _ContractScope? tScope = _fContractScope;
        var tArch   = _fArch;

        InputDecoration _deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(color: Colors.white70),
          filled: true, fillColor: Colors.white.withOpacity(0.06),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        );

        return StatefulBuilder(
          builder: (context, setM) {
            bool showArch() =>
                (tOrigin == _OriginFilter.maintenance) ||
                (tOrigin == _OriginFilter.contracts && tScope == _ContractScope.ended);

            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h + MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: Text('تصفية', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800))),
                  SizedBox(height: 12.h),

                  // (1) الحالة = المصدر
                  DropdownButtonFormField<_OriginFilter>(
                    value: tOrigin,
                    decoration: _deco('الحالة'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: _OriginFilter.all,         child: Text('الكل')),
                      DropdownMenuItem(value: _OriginFilter.contracts,   child: Text('العقود')),
                      DropdownMenuItem(value: _OriginFilter.maintenance, child: Text('الصيانة')),
                    ],
                    onChanged: (v) => setM(() {
                      tOrigin = v ?? _OriginFilter.all;
                      if (tOrigin == _OriginFilter.contracts) {
                        tScope = tScope ?? _ContractScope.all;
                      } else {
                        tScope = null;
                      }
                      if (!showArch()) tArch = _ArchFilter.unarchived;
                    }),
                  ),
                  SizedBox(height: 10.h),

                  // (2) نطاق العقود — يظهر فقط عندما الحالة = العقود
                  if (tOrigin == _OriginFilter.contracts) ...[
                    DropdownButtonFormField<_ContractScope>(
                      value: tScope ?? _ContractScope.all, // الافتراضي: الكل
                      decoration: _deco('العقود'),
                      dropdownColor: const Color(0xFF0B1220),
                      iconEnabledColor: Colors.white70,
                      style: GoogleFonts.cairo(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: _ContractScope.all,    child: Text('الكل')),
                        DropdownMenuItem(value: _ContractScope.active, child: Text('سارية')),
                        DropdownMenuItem(value: _ContractScope.ended,  child: Text('منتهية')),
                      ],
                      onChanged: (v) => setM(() {
                        tScope = v ?? _ContractScope.all;
                        if (!showArch()) tArch = _ArchFilter.unarchived;
                      }),
                    ),
                    SizedBox(height: 10.h),
                  ],

                  // (3) الأرشفة — تظهر عندما: الصيانة أو العقود المنتهية
                  if (showArch()) ...[
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
                            selected: tArch == _ArchFilter.unarchived,
                            onSelected: (_) => setM(() => tArch = _ArchFilter.unarchived),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('مؤرشفة', style: GoogleFonts.cairo()),
                            selected: tArch == _ArchFilter.archived,
                            onSelected: (_) => setM(() => tArch = _ArchFilter.archived),
                          ),
                        ),
                      ],
                    ),
                  ],

                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _fOrigin        = tOrigin;
                              _fContractScope = tScope;
                              _fArch          = tArch;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
                          child: Text('تصفية', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _fOrigin        = _OriginFilter.all;
                              _fContractScope = null;
                              _fArch          = _ArchFilter.unarchived;
                            });
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
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

  @override
  Widget build(BuildContext context) {
    // لا نستخدم الصندوق قبل ما يجهز
    if (!_invoicesReady) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          
          appBar: AppBar(
            
            elevation: 0,
            centerTitle: true,
automaticallyImplyLeading: false,
leading: darvooLeading(context, iconColor: Colors.white),

            title: Text('الفواتير', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20.sp)),
          ),
          body: const Center(child: CircularProgressIndicator()),
          bottomNavigationBar: AppBottomNav(
            key: _bottomNavKey,
            currentIndex: 0,
            onTap: _handleBottomTap,
          ),
        ),
      );
    }

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
                context: ctx, removeTop: true, removeBottom: true,
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

          title: Text('الفواتير', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20.sp)),
          actions: [
            IconButton(
              tooltip: 'تصفية',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
              onPressed: _openFilterSheet,
            ),
          ],
        ),

        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
                    colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)]),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالمستأجر/العقار/المبلغ',
                      hintStyle: GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      filled: true, fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
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
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _invoices.listenable(),
                    builder: (context, Box<Invoice> box, _) {
                      var items = box.values.toList();

                      // فلتر المصدر/الحالة
                      bool isMaint(Invoice inv) => _isMaintenance(inv);
                      if (_fOrigin == _OriginFilter.contracts) {
                        items = items.where((i) => !isMaint(i)).toList();

                        // نطاق العقود
                        if (_fContractScope == _ContractScope.active) {
                          items = items.where((i) => !_contractEndedBy(i)).toList();
                        } else if (_fContractScope == _ContractScope.ended) {
                          items = items.where((i) => _contractEndedBy(i)).toList();
                        }
                      } else if (_fOrigin == _OriginFilter.maintenance) {
                        items = items.where((i) => isMaint(i)).toList();
                      }

                      // فلتر الأرشفة — يطبّق دائمًا على القائمة
                      if (_fArch == _ArchFilter.archived) {
                        items = items.where((i) => i.isArchived).toList();
                      } else {
                        items = items.where((i) => !i.isArchived).toList();
                      }

                      // البحث
                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        items = items.where((inv) {
                          final t = firstWhereOrNull(_tenants.values, (x) => x.id == inv.tenantId);
                          final p = firstWhereOrNull(_properties.values, (x) => x.id == inv.propertyId);
                          final tn = (t?.fullName ?? '').toLowerCase();
                          final pn = (p?.name ?? '').toLowerCase();
                          final amt = inv.amount.toString().toLowerCase();
                          final cur = inv.currency.toLowerCase();
                          final sn  = (inv.serialNo ?? '').toLowerCase();
                          return tn.contains(q) || pn.contains(q) || amt.contains(q) || cur.contains(q) || sn.contains(q);
                        }).toList();
                      }

                  

// ترتيب: الأحدث تحديثًا في الأعلى (سواء فاتورة عقد أو صيانة)
items.sort((a, b) {
  // 1) أولاً: تاريخ آخر تحديث (updatedAt) — آخر حركة فوق
  final cmpUpdated = b.updatedAt.compareTo(a.updatedAt);
  if (cmpUpdated != 0) return cmpUpdated;

  // 2) لو تعادلوا في updatedAt نرجع لتاريخ الإنشاء
  final cmpCreated = b.createdAt.compareTo(a.createdAt);
  if (cmpCreated != 0) return cmpCreated;

  // 3) احتياطياً: تاريخ الإصدار
  final cmpIssue = b.issueDate.compareTo(a.issueDate);
  if (cmpIssue != 0) return cmpIssue;

  // 4) وأخيراً: الـ id لتثبيت الترتيب
  return b.id.compareTo(a.id);
});




                      if (items.isEmpty) {
                        return Center(
                          child: Text('لا توجد فواتير',
                            style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final inv = items[i];
                          final t = firstWhereOrNull(_tenants.values, (x) => x.id == inv.tenantId);
                          final p = firstWhereOrNull(_properties.values, (x) => x.id == inv.propertyId);
                          final remaining = inv.remaining;

                          return InkWell(
                            borderRadius: BorderRadius.circular(16.r),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoice: inv)),
                              );
                            },
                           onLongPress: () {
  // تم إيقاف الأرشفة اليدوية من شاشة الفواتير
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'لا يمكن تغيير حالة الأرشفة من شاشة الفواتير.\n'
        'قم بالأرشفة أو فك الأرشفة من شاشة العقد أو الصيانة المرتبطة.',
        style: GoogleFonts.cairo(),
      ),
    ),
  );
},

                            child: _DarkCard(
                              padding: EdgeInsets.all(12.w),
                              child: Stack(
                                children: [
                                  // أعلى اليمين: رقم الفاتورة (LTR)
                                  if ((inv.serialNo ?? '').isNotEmpty)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: _chip(inv.serialNo!, bg: const Color(0xFF334155)),
                                      ),
                                    ),
                                  // محتوى البطاقة
Padding(
  padding: EdgeInsets.only(top: 34.h), // زوّدنا الفسحة للأسفل عشان يبتعد المربّع عن الرقم
  child: Row(

                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 52.w, height: 52.w,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12.r),
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                                              begin: Alignment.topRight, end: Alignment.bottomLeft),
                                          ),
                                          child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                                        ),
                                        SizedBox(width: 12.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _invoiceKind(inv),
                                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.sp),
                                                    ),
                                                  ),
                                                  _chip(_statusText(inv), bg: _statusColor(inv)),
                                                ],
                                              ),
                                              SizedBox(height: 6.h),
                                              Wrap(
                                                spacing: 6.w, runSpacing: 6.h,
                                                children: [
                                                  _chip('الإصدار: ${_fmtDateDynamic(inv.issueDate)}', bg: const Color(0xFF1F2937)),
                                                  _chip('الاستحقاق: ${_fmtDateDynamic(inv.dueDate)}', bg: const Color(0xFF1F2937)),
                                                  _chip('القيمة: ${_fmtMoneyTrunc(inv.amount)} ريال', bg: const Color(0xFF1F2937)),

                                                  if (!inv.isPaid && !inv.isCanceled)
                                                    _chip('المتبقي: ${_fmtMoneyTrunc(remaining)} ريال', bg: const Color(0xFF1F2937)),

                                                  
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                                      ],
                                    ),
                                  ),
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

        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 0,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }
}

/// ===============================================================================
/// تفاصيل الفاتورة
/// ===============================================================================
class InvoiceDetailsScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceDetailsScreen({super.key, required this.invoice});

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
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
      case 0: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); break;
      case 1: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen())); break;
      case 2: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TenantsScreen())); break;
      case 3: Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen())); break;
    }
  }

  Box<Invoice> get _invoices => Hive.box<Invoice>(invoicesBoxName());
  Box<Tenant> get _tenants => Hive.box<Tenant>(tenantsBoxName());
  Box<Property> get _properties => Hive.box<Property>(propsBoxName());
  Box<Contract> get _contracts => Hive.box<Contract>(contractsBoxName());

  bool _contractEndedBy(Invoice inv) {
    final c = firstWhereOrNull(_contracts.values, (x) => x.id == inv.contractId);
    if (c == null) return false; // غير مربوط بعقد

    // ✅ منتهي يدويًا أو بالتاريخ
    if (c.isTerminated == true) return true;

    final today = KsaTime.today();
    return !today.isBefore(c.endDate); // اليوم >= نهاية العقد
  }

  Future<void> _showBlockDialog(String msg) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('لا يمكن الأرشفة',
            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(msg, style: GoogleFonts.cairo(color: Colors.white70)),
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

  /// يُسمح بالأرشفة إذا كانت الفاتورة غير مدفوعة.
  /// إن كانت "مدفوعة": تُسمح فقط إذا كانت مربوطة بعقد منتهي.
  Future<bool> _ensureCanArchive(Invoice inv) async {
    // ✅ السماح دائمًا لفواتير الصيانة
    if (_isMaintenanceAny(inv)) return true;

    if (!inv.isPaid) return true;
    if ((inv.contractId).isEmpty) {
      await _showBlockDialog('لا يمكن أرشفة الفاتورة المدفوعة لأنها غير مرتبطة بعقد.');
      return false;
    }
    if (!_contractEndedBy(inv)) {
      await _showBlockDialog('لا يمكن أرشفة الفاتورة المدفوعة إلا إذا كان العقد منتهي.');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    // توليد رقم إن كان غير موجود (حماية)



    final t = firstWhereOrNull(_tenants.values, (x) => x.id == invoice.tenantId);
    final p = firstWhereOrNull(_properties.values, (x) => x.id == invoice.propertyId);
    final linkedContract = firstWhereOrNull(_contracts.values, (x) => x.id == invoice.contractId);
    final bool contractTerminated = linkedContract?.isTerminated == true;
    final bool _noTenantMaint =
        _isMaintenanceAny(invoice) && ((invoice.tenantId).isEmpty || t == null);

    final statusColor = _statusColor(invoice);
    final statusText = _statusText(invoice);

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
                context: ctx, removeTop: true, removeBottom: true,
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

          title: Text('تفاصيل الفاتورة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
          IconButton(
  tooltip: invoice.isArchived
      ? 'الفاتورة مؤرشفة - التعديل مسموح فقط من شاشة الطلب'
      : 'الفاتورة غير مؤرشفة - الأرشفة تتم فقط من شاشة الطلب',
  onPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لا يمكن تغيير حالة الأرشفة من شاشة الفاتورة.\n'
          'الأرشفة وفكّها تتم فقط من شاشة العقد أو الصيانة المرتبطة.',
          style: GoogleFonts.cairo(),
        ),
      ),
    );
  },
  icon: Icon(
    invoice.isArchived
        ? Icons.inventory_2_rounded   // أيقونة مؤرشفة
        : Icons.archive_rounded,      // أيقونة غير مؤرشفة
    color: Colors.white,
  ),
),

          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)]),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

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
                              width: 56.w, height: 56.w,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF2148C6)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                            ),
                            SizedBox(height: 56.w, width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _noTenantMaint ? 'بدون مستأجر' : (t?.fullName ?? '—'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5.sp,
                                          ),
                                        ),
                                      ),
                                      if (invoice.serialNo != null && invoice.serialNo!.isNotEmpty)
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: _chip(invoice.serialNo!, bg: const Color(0xFF334155)),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 4.h),
                                  InkWell(
                                    onTap: () async {
                                      try {
                                        await Navigator.of(context).pushNamed('/property/details', arguments: invoice.propertyId);
                                      } catch (_) {}
                                    },
                                    child: Text(p?.name ?? '—',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13.5.sp, decoration: TextDecoration.underline),
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Wrap(
                                    spacing: 8.w, runSpacing: 8.h,
                                    children: [
                                      _chip(_statusText(invoice), bg: _statusColor(invoice)),
                                      _chip('الإصدار: ${_fmtDateDynamic(invoice.issueDate)}', bg: const Color(0xFF1F2937)),
                                      _chip('الاستحقاق: ${_fmtDateDynamic(invoice.dueDate)}', bg: const Color(0xFF1F2937)),
                                      _chip('القيمة: ${_fmtMoneyTrunc(invoice.amount)} ريال', bg: const Color(0xFF1F2937)),
                                      _chip('المدفوع: ${_fmtMoneyTrunc(invoice.paidAmount)} ريال', bg: const Color(0xFF1F2937)),
                                      if (!invoice.isPaid && !invoice.isCanceled)
                                        _chip('المتبقي: ${_fmtMoneyTrunc(invoice.remaining)} ريال', bg: const Color(0xFF1F2937)),
                                      
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        if ((invoice.note ?? '').isNotEmpty) ...[
                          Text('${invoice.note}', style: GoogleFonts.cairo(color: Colors.white70)),
                          if (contractTerminated) ...[
                            SizedBox(height: 6),
                            Text('العقد منتهي',
                              style: GoogleFonts.cairo(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),

                Align(
  alignment: Alignment.centerRight,
  child: Wrap(
    spacing: 8.w,
    children: [
      if (!invoice.isCanceled && !invoice.isPaid)
        _miniAction(
          icon: Icons.payments_rounded,
          label: 'تسجيل سداد',
          bg: const Color(0xFF0EA5E9),
          onTap: () async {
            // 🚫 منع عميل المكتب من تسجيل السداد
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            _addPayment(context, invoice);
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
            Text(label, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.sp)),
          ],
        ),
      ),
    );
  }

  Future<void> _addPayment(BuildContext context, Invoice invoice) async {
    final controller = TextEditingController();
    final methodCtl = TextEditingController(text: invoice.paymentMethod);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16.w, right: 16.w, top: 16.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تسجيل سداد', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
              SizedBox(height: 10.h),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))],
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  labelStyle: GoogleFonts.cairo(color: Colors.white70),
                  filled: true, fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: methodCtl,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'طريقة الدفع',
                  labelStyle: GoogleFonts.cairo(color: Colors.white70),
                  filled: true, fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text('حفظ', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
            ],
          ),
        );
      },
    );

    if (ok == true) {
      final v = double.tryParse(controller.text.trim()) ?? 0.0;
      if (v <= 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أدخل مبلغًا صحيحًا', style: GoogleFonts.cairo())));
        }
        return;
      }
      invoice.paidAmount += v;
      final m = methodCtl.text.trim();
      if (m.isNotEmpty) invoice.paymentMethod = m;
      invoice.updatedAt = KsaTime.now();
      await invoice.save();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسجيل السداد', style: GoogleFonts.cairo())));
      }
    }
  }
}

/// ===============================================================================
/// سجل فواتير عقد محدد
/// ===============================================================================
class InvoicesHistoryScreen extends StatelessWidget {
  final String contractId;
  const InvoicesHistoryScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context) {
    // حماية بسيطة لو فُتح مباشرة بدون تهيئة سابقة
    if (!Hive.isBoxOpen(invoicesBoxName())) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
drawer: Builder(
  builder: (ctx) {
    final media = MediaQuery.of(ctx);
    final double topInset = kToolbarHeight + media.padding.top;
    final double bottomInset = media.padding.bottom; // لا يوجد BottomNav هنا
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
             elevation: 0, centerTitle: true,
automaticallyImplyLeading: false,
leading: darvooLeading(context, iconColor: Colors.white),

            title: Text('سجل فواتير العقد', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final _invoices   = Hive.box<Invoice>(invoicesBoxName());
    final _tenants    = Hive.box<Tenant>(tenantsBoxName());
    final _properties = Hive.box<Property>(propsBoxName());
    final _contracts  = Hive.box<Contract>(contractsBoxName());

    final c = firstWhereOrNull(_contracts.values, (e) => e.id == contractId);
    final t = firstWhereOrNull(_tenants.values,   (e) => e.id == (c?.tenantId ?? ''));
    final p = firstWhereOrNull(_properties.values,(e) => e.id == (c?.propertyId ?? ''));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
drawer: Builder(
  builder: (ctx) {
    final media = MediaQuery.of(ctx);
    final double topInset = kToolbarHeight + media.padding.top;
    final double bottomInset = media.padding.bottom; // لا يوجد BottomNav هنا
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
           elevation: 0, centerTitle: true,
automaticallyImplyLeading: false,
leading: darvooLeading(context, iconColor: Colors.white),

          title: Text('سجل فواتير العقد', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)]),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

            ValueListenableBuilder(
              valueListenable: _invoices.listenable(),
             builder: (context, Box<Invoice> box, _) {
final items = box.values
    .where((i) => i.contractId == contractId)
    .toList()
  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));



                if (items.isEmpty) {
                  return Center(
                    child: Text('لا توجد فواتير لهذا العقد',
                        style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
                  );
                }


// المجاميع والعدادات (مرتبطة بالعقد إذا وُجد: نعرض الإجمالي بعد خصم المقدم إذا كان advanceMode = deductFromTotal)
final double grossContract   = ((c?.totalAmount ?? 0)).toDouble();
final double advancePaid     = ((c?.advancePaid ?? 0)).toDouble();
final bool   deductFromTotal = (c != null) && (c!.advanceMode == AdvanceMode.deductFromTotal);

final double contractNet     = deductFromTotal ? (grossContract - advancePaid) : grossContract;

// نحسب المدفوع/المتبقي من الفواتير غير الملغاة مع تشذيب لخانتين (لتطابق العرض)
double _trunc2(num v) => (v * 100).truncate() / 100.0;
final filteredItems = items.where((i) => !i.isCanceled).toList();

// ✅ مُعرّف لفاتورة المقدم (النص يأتي من العقود: "سداد مقدم عقد …")
bool _isAdvanceInvoice(Invoice i) {
  final n = (i.note ?? '').toString();
  return n.contains('سداد مقدم عقد');
}

// الإجمالي يعكس قيمة العقد (بعد خصم المقدم إن وُجد)
final double totalAmount = contractNet;

// ⚠️ استبعد فاتورة المقدم من "المدفوع" وعدّادات الأقساط عند خصم المقدم من الإجمالي
final filteredForPaid = deductFromTotal
    ? filteredItems.where((i) => !_isAdvanceInvoice(i)).toList()
    : filteredItems;

// المدفوع من الفواتير (لا نُدخل المقدم هنا)
final double totalPaid = filteredForPaid.fold<double>(0.0, (s, i) {
  final paid = _trunc2(i.paidAmount);
  final cap  = _trunc2(i.amount);
  return s + (paid > cap ? cap : paid);
});

// المتبقي = الإجمالي - المدفوع (مع حماية من تجاوز المدفوع للإجمالي بسبب الكسور)
final double totalRemain = (totalAmount - (totalPaid > totalAmount ? totalAmount : totalPaid))
    .clamp(0, double.infinity);

// قيمة المقدم للعرض كسطر مستقل تحت الجدول (فقط عند الخصم من الإجمالي)
final double advanceShown = deductFromTotal ? _trunc2(advancePaid) : 0.0;

// الأقساط (Contract-based): إجمالي الأقساط من العقد، والمدفوع/المتبقي من الفواتير غير الملغاة
final int _monthsInTermLocal = (c == null) ? 0 : (() {
  switch (c!.term) {
    case ContractTerm.daily:      return 0;
    case ContractTerm.monthly:    return 1;
    case ContractTerm.quarterly:  return 3;
    case ContractTerm.semiAnnual: return 6;
    case ContractTerm.annual:     return 12;
  }
})();

final int _monthsPerCycleLocal = (c == null) ? 1 : (() {
  switch (c!.paymentCycle) {
    case PaymentCycle.monthly:    return 1;
    case PaymentCycle.quarterly:  return 3;
    case PaymentCycle.semiAnnual: return 6;
    case PaymentCycle.annual:     return 12;
  }
})();

final int expectedInst = (c == null)
    // لو ما وجدنا العقد (حالة نادرة)، تجاهل أيضًا فاتورة المقدم من العدّادات
    ? (deductFromTotal ? filteredForPaid.length : filteredItems.length)
    : (c!.term == ContractTerm.daily
        ? 1
        : (((_monthsInTermLocal / _monthsPerCycleLocal).ceil()).clamp(1, 1000)));

final int paidInst   = filteredForPaid.where((i) => i.isPaid).length;
final int remainInst = (expectedInst - paidInst).clamp(0, 1000000);
final int totalInst  = expectedInst;

final String cur     = items.first.currency;
final bool fullySettled = (paidInst >= totalInst) && filteredForPaid.every((i) => i.isPaid);
final double totalPaidDisplay = fullySettled ? totalAmount : totalPaid;
final double totalRemainDisplay = (totalAmount - totalPaidDisplay).clamp(0, double.infinity);


                Widget _cell(String text, {bool header = false}) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: header ? FontWeight.w800 : FontWeight.w700,
                      fontSize: header ? 13.sp : 12.5.sp,
                      height: 1.4,
                    ),
                  ),
                );

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemCount: items.length + 1, // أول عنصر = رأس/ملخص
                  itemBuilder: (_, idx) {
                    if (idx == 0) {
                      // ===== رأس منظم بدون بطاقة =====
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // اسم المستأجر ثم العقار (كل واحد سطر)

                          SizedBox(height: 12.h),
                          // جدول بحدود خفيفة — بدون خلفية
                          Table(
                            border: TableBorder.all(color: Colors.white24, width: 1),
                            columnWidths: const {
                              0: FlexColumnWidth(1),
                              1: FlexColumnWidth(1),
                              2: FlexColumnWidth(1),
                            },
                            children: [
                              TableRow(children: [
                                _cell('الإجمالي', header: true),
                                _cell('المدفوع', header: true),
                                _cell('المتبقي', header: true),
                              ]),
                              TableRow(children: [
                                _cell('${_fmtMoneyTrunc(totalAmount)} ريال\nالأقساط: $totalInst'),
                                _cell('${_fmtMoneyTrunc(totalPaidDisplay)} ريال\nالأقساط: $paidInst'),
                                _cell('${_fmtMoneyTrunc(totalRemainDisplay)} ريال\nالأقساط: $remainInst'),
                              ]),
                            ],

                          ),
if (advanceShown > 0) ...[
  SizedBox(height: 8.h),
  Row(
    children: [
      Text('إجمالي المقدم المدفوع',
          style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
      const Spacer(),
      Text('${_fmtMoneyTrunc(advanceShown)} ريال',
          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
    ],
  ),
],

                        ],
                      );
                    }


                    // ===== باقي العناصر: بطاقات الفواتير =====
                    final inv = items[idx - 1];
                    final statusColor = _statusColor(inv);
                    final statusText  = _statusText(inv);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoice: inv)),
                        );
                      },
                      child: _DarkCard(
                        padding: EdgeInsets.all(12.w),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // رقم الفاتورة فقط (LTR)
                                  Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Text(
                                      inv.serialNo ?? '—',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 6.h),
                                  Wrap(
                                    spacing: 6.w, runSpacing: 6.h,
                                    children: [
                                      _chip('الإصدار: ${_fmtDateDynamic(inv.issueDate)}', bg: const Color(0xFF1F2937)),
                                      _chip('الاستحقاق: ${_fmtDateDynamic(inv.dueDate)}', bg: const Color(0xFF1F2937)),
                                      _chip('القيمة: ${_fmtMoneyTrunc(inv.amount)} ريال', bg: const Color(0xFF1F2937)),
                                      _chip('الحالة: $statusText', bg: statusColor),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================================
/// مسارات
/// ===============================================================================
class InvoicesRoutes {
  static Map<String, WidgetBuilder> routes() => {
    '/invoices': (context) => const InvoicesScreen(),
    '/invoices/history': (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final id = (args is Map && args['contractId'] is String) ? args['contractId'] as String : '';
      return InvoicesHistoryScreen(contractId: id);
    },
  };
}
