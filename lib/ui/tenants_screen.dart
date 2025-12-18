// lib/ui/tenants_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart'; // ✅ للهجري

import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/user_scope.dart' as scope;
import '../data/constants/boxes.dart' as bx;

import '../data/services/offline_sync_service.dart';


import '../models/tenant.dart';
// ✅ وقت/تاريخ الرياض
import '../utils/ksa_time.dart';

// للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'properties_screen.dart';
import 'contracts_screen.dart' as contracts_ui; // يتيح استخدام Contract و ContractDetailsScreen
import '../models/property.dart';               // نحتاجه لتحديث إشغال العقار

// عناصر الواجهة المشتركة
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';
import '../widgets/darvoo_app_bar.dart';


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

String _limitChars(String t, int max) => t.length <= max ? t : '${t.substring(0, max)}…';

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

Widget _sectionTitle(String t) => Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(
        t,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14.sp,
        ),
      ),
    );

/// ===== فلاتر القائمة =====
enum _LinkedFilter { all, linked, unlinked }
enum _IdExpiryFilter { all, expired, valid }
enum _ArchiveFilter { all, notArchived, archived }

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
  _LinkedFilter _fLinked = _LinkedFilter.all;
  _IdExpiryFilter _fIdExpiry = _IdExpiryFilter.all;
  _ArchiveFilter _fArchive = _ArchiveFilter.notArchived; // الافتراضي: غير مؤرشف

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  bool _handledOpen = false;

  void _openTenantDetailsById(String id) {
    final box = _box;
    Tenant? t;
    try {
      t = box.values.firstWhere((e) => e.id == id);
    } catch (_) {}

    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('المستأجر غير موجود', style: GoogleFonts.cairo())),
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

Future<void> _initTenants() async {
  // نضمن الصناديق مفتوحة (لا تفتح/تغلق مزامنة هنا)
  HiveService.ensureReportsBoxesOpen();

  // حساب ارتفاع البوتوم ناف + فتح مستأجر معيّن لو جاي من شاشة ثانية
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final h = _bottomNavKey.currentContext?.size?.height;
    if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
      setState(() => _bottomBarHeight = h);
    }

    if (_handledOpen) return;
    _handledOpen = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    final String? id = (args is Map) ? args['openTenantId'] as String? : null;
    if (id != null) _openTenantDetailsById(id);
  });
}



  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        // أنت هنا
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()),
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
      (_fLinked != _LinkedFilter.all) ||
      (_fIdExpiry != _IdExpiryFilter.all);

  String _currentFilterLabel() {
    final parts = <String>[];
    parts.add(_fArchive == _ArchiveFilter.archived ? 'المؤرشفة' : 'الكل');
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
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        _LinkedFilter tempLinked = _fLinked;
        _IdExpiryFilter tempId = _fIdExpiry;
        // ✅ مثل العقارات: خياران جنب بعض — «الكل» و«الأرشفة»
        bool arch = _fArchive == _ArchiveFilter.archived;

        return StatefulBuilder(
          builder: (context, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16.w,
                16.h,
                16.w,
                16.h + MediaQuery.of(context).padding.bottom,
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
                  DropdownButtonFormField<_LinkedFilter>(
                    value: tempLinked,
                    decoration: _dropdownDeco('الارتباط بالعقود'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(value: _LinkedFilter.all, child: Text('الكل')),
                      DropdownMenuItem(value: _LinkedFilter.linked, child: Text('مربوطون بعقد')),
                      DropdownMenuItem(value: _LinkedFilter.unlinked, child: Text('غير مربوطين بعقد')),
                    ],
                    onChanged: (v) => setM(() => tempLinked = v ?? _LinkedFilter.all),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),
                  SizedBox(height: 10.h),
                  DropdownButtonFormField<_IdExpiryFilter>(
                    value: tempId,
                    decoration: _dropdownDeco('حالة الهوية'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    items: const [
                      DropdownMenuItem(value: _IdExpiryFilter.all, child: Text('الكل')),
                      DropdownMenuItem(value: _IdExpiryFilter.expired, child: Text('هوية منتهية')),
                      DropdownMenuItem(value: _IdExpiryFilter.valid, child: Text('هوية سارية')),
                    ],
                    onChanged: (v) => setM(() => tempId = v ?? _IdExpiryFilter.all),
                    style: GoogleFonts.cairo(color: Colors.white),
                  ),

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
                              _fLinked = tempLinked;
                              _fIdExpiry = tempId;
                              _fArchive = arch
                                  ? _ArchiveFilter.archived
                                  : _ArchiveFilter.notArchived;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E40AF)),
                          child: Text('تطبيق',
                              style: GoogleFonts.cairo(
                                  color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
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
                                  color: Colors.white70, fontWeight: FontWeight.w700)),
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

  Future<void> _tryArchive(Tenant t) async {
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

    // إذا لم يكن مؤرشفًا → حاول الأرشفة (مع نفس شرط العقود)
    if (t.activeContractsCount > 0) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actionsAlignment: MainAxisAlignment.center,
          title: Text('لا يمكن الأرشفة',
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Text(
            'لا يمكن أرشفة المستأجر لوجود عقود نشطة. أنهِ العقود أولًا من شاشة العقود.',
            style: GoogleFonts.cairo(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('حسنًا',
                  style: GoogleFonts.cairo(
                      color: Colors.white70, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
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

          title: Text('المستأجرون',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20.sp)),
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
                  colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
                ),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

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
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
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

                // ✅ وسم الفلاتر — نفس العقارات
                if (_hasActiveFilters)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded, size: 16, color: Colors.white70),
                            SizedBox(width: 6.w),
                            Text(
                              _currentFilterLabel(),
                              style: GoogleFonts.cairo(
                                  color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w700),
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
                      // الارتباط بالعقود
                      if (_fLinked == _LinkedFilter.linked) {
                        items = items.where((t) => (t.activeContractsCount) > 0).toList();
                      } else if (_fLinked == _LinkedFilter.unlinked) {
                        items = items.where((t) => (t.activeContractsCount) == 0).toList();
                      }
                      // حالة الهوية
                      if (_fIdExpiry == _IdExpiryFilter.expired) {
                        items = items
                            .where((t) =>
                                t.idExpiry != null &&
                                KsaTime.dateOnly(t.idExpiry!).isBefore(todayKsa))
                            .toList();
                      } else if (_fIdExpiry == _IdExpiryFilter.valid) {
                        items = items
                            .where((t) =>
                                t.idExpiry != null &&
                                !KsaTime.dateOnly(t.idExpiry!).isBefore(todayKsa))
                            .toList();
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
  final au = a.updatedAt?.millisecondsSinceEpoch ?? 0;
  final bu = b.updatedAt?.millisecondsSinceEpoch ?? 0;
  final cmpU = bu.compareTo(au);
  if (cmpU != 0) return cmpU;

  final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
  final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
  final cmpC = bc.compareTo(ac);
  if (cmpC != 0) return cmpC;

  return b.id.compareTo(a.id);
});



                      if (items.isEmpty) {
                        return Center(
                          child: Text('لا يوجد مستأجرون',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70, fontWeight: FontWeight.w700)),
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
                                  builder: (_) => TenantDetailsScreen(tenant: t),
                                ),
                              );
                            },
                            onLongPress: () async {
                              // 🚫 منع عميل المكتب من الأرشفة بالضغط المطوّل
                              if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                              _tryArchive(t); // ✅ ضغط مطوّل للأرشفة
                            },
                            child: _DarkCard(

                              padding: EdgeInsets.all(12.w),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 52.w,
                                    height: 52.w,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.r),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                                        begin: Alignment.topRight,
                                        end: Alignment.bottomLeft,
                                      ),
                                    ),
                                    child: const Icon(Icons.person_rounded, color: Colors.white),
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
                                                _limitChars(t.fullName, 48),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.cairo(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16.sp,
                                                ),
                                              ),
                                            ),
                                            if (t.isBlacklisted)
                                              _chip('محظور', bg: const Color(0xFF7F1D1D)),

                                              
                                          ],
                                        ),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            Icon(Icons.badge_outlined,
                                                size: 16.sp, color: Colors.white70),
                                            SizedBox(width: 4.w),
                                            Text(t.nationalId,
                                                style: GoogleFonts.cairo(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w700)),
                                            SizedBox(width: 10.w),
                                            Icon(Icons.call_outlined,
                                                size: 16.sp, color: Colors.white70),
                                            SizedBox(width: 4.w),
                                            Text(t.phone,
                                                style: GoogleFonts.cairo(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                        SizedBox(height: 8.h),
                                        Wrap(
                                          spacing: 6.w,
                                          runSpacing: 6.h,
                                          children: [
                                            _chip('عقود نشطة: ${t.activeContractsCount}',
                                                bg: const Color(0xFF0B3D2E)),
                                            if ((t.nationality ?? '').isNotEmpty)
                                              _chip(t.nationality!,
                                                  bg: const Color(0xFF1F2937)),
                                            if (t.idExpiry != null)
                                              _chip(
                                                'انتهاء الهوية: ${_fmtDateDynamic(t.idExpiry!)}',
                                                bg: const Color(0xFF1F2937),
                                              ), // ✅ هجري/ميلادي
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_left_rounded, color: Colors.white70),
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
          backgroundColor: const Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text('إضافة مستأجر', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            // 🚫 منع عميل المكتب من إضافة مستأجر
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final created = await Navigator.of(context).push<Tenant?>(
              MaterialPageRoute(builder: (_) => AddOrEditTenantScreen()),
            );
            if (created != null) {
              // ✅ حفظ محلي سريع + طابور المزامنة (الـ Snackbar ظهر في شاشة الإضافة)
              await _box.put(created.id, created);
              _sync.enqueueUpsertTenant(created); // بدون await
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
    // 1) إشغال العقار
    final Box<Property> props = Hive.box<Property>(scope.boxName(bx.kPropertiesBox));
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
    final Box<Property> props = Hive.box<Property>(scope.boxName(bx.kPropertiesBox));
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
    HiveService.ensureReportsBoxesOpen();

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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()),
        );
        break;
    }
  }

  Future<void> _toggleArchive(Tenant t) async {
    if (!t.isArchived) {
      // محاولة أرشفة
      if (t.activeContractsCount > 0) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            actionsAlignment: MainAxisAlignment.center,
            title: Text('لا يمكن الأرشفة',
                style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Text('لا يمكن أرشفة المستأجر لوجود عقود نشطة. أنهِ العقود أولًا.',
                style: GoogleFonts.cairo(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('حسنًا',
                    style: GoogleFonts.cairo(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        return;
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
    final tenant = widget.tenant;

    // ✅ اعتبر اليوم الحالي على توقيت الرياض، وقارن كتاريخ فقط
    final todayKsa = KsaTime.dateOnly(KsaTime.now());
    final idExpired =
        tenant.idExpiry != null && KsaTime.dateOnly(tenant.idExpiry!).isBefore(todayKsa);

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

          title: Text('تفاصيل المستأجر',
              style:
                  GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
         actions: [
  IconButton(
    tooltip: tenant.isArchived ? 'فك الأرشفة' : 'أرشفة',
    onPressed: () async {
      // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة من تفاصيل المستأجر
      if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

      // ✅ لو ليس عميل مكتب → نفّذ منطق الأرشفة العادي
      _toggleArchive(tenant);
    },
    icon: Icon(
      tenant.isArchived ? Icons.inventory_2_rounded : Icons.archive_rounded,
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
                  colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
                ),
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
                              width: 56.w,
                              height: 56.w,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                              ),
                              child: const Icon(Icons.person_rounded, color: Colors.white),
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
                                      Text(tenant.nationalId,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w700)),
                                      SizedBox(width: 12.w),
                                      Icon(Icons.call_outlined,
                                          size: 16.sp, color: Colors.white70),
                                      SizedBox(width: 4.w),
                                      Text(tenant.phone,
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
                            InkWell(
                              borderRadius: BorderRadius.circular(10.r),
                              onTap: () => _openTenantContracts(context, tenant),
                              child: _pill('عقود نشطة: ${tenant.activeContractsCount}',
                                  bg: const Color(0xFF0B3D2E)),
                            ),
                            if ((tenant.nationality ?? '').isNotEmpty) _pill(tenant.nationality!),
                            if (tenant.idExpiry != null)
                              _pill(
                                'انتهاء الهوية: ${_fmtDateDynamic(tenant.idExpiry!)}'
                                '${idExpired ? " (منتهية)" : ""}',
                                bg: idExpired
                                    ? const Color(0xFF7F1D1D)
                                    : const Color(0xFF1E293B),
                              ),
    // 👇 جديد: تاريخ إنشاء المستأجر مثل شاشة الصيانة
if (tenant.createdAt != null)
  _pill(
    'تاريخ الإنشاء: ${_fmtDateDynamic(tenant.createdAt!)}',
    bg: const Color(0xFF1D4ED8), // 🔵 لون مميز لتاريخ الإنشاء
  ),

                            if (tenant.isBlacklisted) _pill('محظور', bg: const Color(0xFF7F1D1D)),
                            
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 10.h),

                  // معلومات التواصل
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('التواصل'),
                        _rowInfo('البريد الإلكتروني', tenant.email),
                        SizedBox(height: 10.h),
                        _sectionTitle('شخص للطوارئ'),
                        _rowInfo('الاسم', tenant.emergencyName),
                        _rowInfo('الجوال', tenant.emergencyPhone),
                      ],
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
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            final updated = await Navigator.of(context).push<Tenant?>(
                              MaterialPageRoute(
                                builder: (_) => AddOrEditTenantScreen(existing: tenant),
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
                              setState(() {}); // تحديث العرض
                            }
                          },
                        ),
                        _miniAction(
                          icon: Icons.description_outlined,
                          label: 'الملاحظات',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من تعديل الملاحظات
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            _showNotesSheet(context, tenant);
                          },
                          bg: const Color(0xFF334155),
                        ),
                        _miniAction(
                          icon: Icons.note_add_outlined,
                          label: 'إضافة عقد',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من إضافة عقد
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            _goToAddContract(context, tenant);
                          },
                          bg: const Color(0xFF0EA5E9),
                        ),
                        _miniAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'حذف',
                          onTap: () async {
                            // 🚫 منع عميل المكتب من الحذف
                            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                            _confirmDelete(context, tenant);
                          },
                          bg: const Color(0xFF7F1D1D),
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
              style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              has ? value! : '—',
              style: GoogleFonts.cairo(color: has ? Colors.white : Colors.white54),
            ),
          ),
        ],
      ),
    );
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
                              content:
                                  Text('تم حفظ الملاحظات', style: GoogleFonts.cairo()),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          setState(() {}); // حدّث العرض بعد الحفظ
                        }
                      },
                      child: Text('حفظ',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
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
            builder: (_) => contracts_ui.ContractDetailsScreen(contract: created),
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

    Future<void> _confirmDelete(BuildContext context, Tenant t) async {
    // 1) منع الحذف في حال وجود عقود نشطة (المنطق القديم)
    if (t.activeContractsCount > 0) {
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
            'لا يمكن حذف المستأجر لوجود عقود نشطة. احذف/أنهِ العقود أولًا من شاشة العقود.',
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
      return;
    }

    // 2) منع الحذف في حال وجود أي عقد (حتى لو منتهي) لم يُحذف بعد
    try {
      final cname = HiveService.contractsBoxName();
      final Box<contracts_ui.Contract> contractsBox =
          Hive.box<contracts_ui.Contract>(cname);

      final hasAnyContract = contractsBox.values.any(
        (c) => c.tenantId == t.id,
      );

      if (hasAnyContract) {
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
              'لا يمكن حذف هذا المستأجر لوجود عقود مرتبطة به حتى لو كانت منتهية.\n'
              'لحذف المستأجر يجب أولًا حذف جميع العقود المرتبطة باسمه من شاشة العقود.',
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
        return;
      }
    } catch (_) {
      // لو صار خطأ في قراءة صندوق العقود ما نكسر الشاشة
    }

    // 3) لا توجد عقود نشطة ولا عقود محفوظة → مسموح بالحذف مع تأكيد
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            actionsAlignment: MainAxisAlignment.center,
            title: Text(
              'تأكيد الحذف',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              'هل تريد حذف "${t.fullName}"؟',
              style: GoogleFonts.cairo(
                color: Colors.white70,
              ),
            ),
            actions: [
              // 🔔 حسب تفضيلك: في الواجهات العربية عادة زر "حذف" على اليمين و"إلغاء" على اليسار
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F1D1D),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'حذف',
                  style: GoogleFonts.cairo(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.cairo(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

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

  DateTime? _idExpiry;
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
        final now = DateTime.now();
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
      _fullName.text = t.fullName;
      _nationalId.text = t.nationalId;
      _phone.text = t.phone;
      _email.text = t.email ?? '';
      _nationality.text = t.nationality ?? '';
      _idExpiry = t.idExpiry;
      _emgName.text = t.emergencyName ?? '';
      _emgPhone.text = t.emergencyPhone ?? '';
      _notes.text = t.notes ?? '';
    }
  }

  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PropertiesScreen()));
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

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

          title: Text(isEdit ? 'تعديل مستأجر' : 'إضافة مستأجر',
              style:
                  GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF0F3A8C), Color(0xFF1E40AF), Color(0xFF2148C6)],
                ),
              ),
            ),
            Positioned(top: -120, right: -80, child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(bottom: -140, left: -100, child: _softCircle(260.r, const Color(0x22FFFFFF))),

            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
              child: _DarkCard(
                padding: EdgeInsets.all(16.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
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
                          if ((v ?? '').trim().isEmpty) return 'هذا الحقل مطلوب';
                          final s = v!.trim();
                          final ok =
                              RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$").hasMatch(s);
                          if (!ok) return 'الاسم يجب أن يكون حروفًا ومسافات فقط';
                          if (s.length > 50) return 'الحد الأقصى 50 حرفًا';
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
                              label: 'رقم الهوية',
                              keyboardType: TextInputType.number,
                              maxLength: 10,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              validator: (v) {
                                if ((v ?? '').isEmpty) return 'هذا الحقل مطلوب';
                                if (!RegExp(r'^\d{1,10}$').hasMatch(v!)) {
                                  return 'الهوية أرقام فقط وبحد أقصى 10 رقمًا';
                                }
                              final currentId = widget.existing?.id;
final dup = _box.values.any((t) =>
  t.nationalId == v && (currentId == null || t.id != currentId),
);
if (dup) return 'الهوية مسجلة مسبقآ';

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
                                if ((v ?? '').isEmpty) return 'هذا الحقل مطلوب';
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
                              RegExp(r"^[a-zA-Z\u0600-\u06FF ]+$").hasMatch(s);
                          if (!ok) return 'الجنسية حروف ومسافات فقط';
                          if (s.length > 20) return 'الحد الأقصى 20 حرفًا';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

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

                      // تاريخ انتهاء الهوية
                      InkWell(
                        borderRadius: BorderRadius.circular(12.r),
                        onTap: _pickIdExpiry,
                        child: InputDecorator(
                          decoration: _dd('تاريخ انتهاء الهوية (اختياري)'),
                          child: Row(
                            children: [
                              const Icon(Icons.event_outlined, color: Colors.white70),
                              SizedBox(width: 8.w),
                              Text(
                                _idExpiry == null ? '—' : _fmtDateDynamic(_idExpiry!),
                                style: GoogleFonts.cairo(
                                    color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),

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
                                if (s.length > 50) return 'الحد الأقصى 50 حرفًا';
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

                      _field(
                        controller: _notes,
                        label: 'ملاحظات (اختياري — حد أقصى 300)',
                        maxLines: 3,
                        maxLength: 300,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.length > 300) return 'الحد الأقصى 300 حرف';
                          return null;
                        },
                      ),
                      SizedBox(height: 16.h),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E40AF),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r)),
                          ),
                          onPressed: _save,
                          icon: const Icon(Icons.check),
                          label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
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
            dialogBackgroundColor: const Color(0xFF0B1220),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _idExpiry = KsaTime.dateOnly(picked));
  }

  void _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final isEdit = widget.existing != null;

    if (isEdit) {
      final t = widget.existing!;
      t.fullName = _fullName.text.trim();
      t.nationalId = _nationalId.text.trim();
      t.phone = _phone.text.trim();
      t.email = _email.text.trim().isEmpty ? null : _email.text.trim();
      t.nationality =
          _nationality.text.trim().isEmpty ? null : _nationality.text.trim();
      t.idExpiry = _idExpiry == null ? null : KsaTime.dateOnly(_idExpiry!);
      t.emergencyName =
          _emgName.text.trim().isEmpty ? null : _emgName.text.trim();
      t.emergencyPhone =
          _emgPhone.text.trim().isEmpty ? null : _emgPhone.text.trim();
      t.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      // ❌ لا نعرض/نعدل الأرشفة والحظر هنا
      t.updatedAt = KsaTime.now();

      // احفظ محليًا + صف المزامنة
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التحديث', style: GoogleFonts.cairo())),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pop<Tenant>(t);
    } else {
      // إنشاء المستأجر الجديد
      final t = Tenant(
        id: KsaTime.now().microsecondsSinceEpoch.toString(),
        fullName: _fullName.text.trim(),
        nationalId: _nationalId.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        nationality:
            _nationality.text.trim().isEmpty ? null : _nationality.text.trim(),
        idExpiry: _idExpiry == null ? null : KsaTime.dateOnly(_idExpiry!),
        emergencyName:
            _emgName.text.trim().isEmpty ? null : _emgName.text.trim(),
        emergencyPhone:
            _emgPhone.text.trim().isEmpty ? null : _emgPhone.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isArchived: false,
        isBlacklisted: false,
        blacklistReason: null,
        createdAt: KsaTime.now(),
        updatedAt: KsaTime.now(),
      );

      // احفظ محليًا + صف المزامنة
      final box = Hive.box<Tenant>(scope.boxName(bx.kTenantsBox));
      await box.put(t.id, t);
      _sync.enqueueUpsertTenant(t); // بدون await

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إضافة المستأجر', style: GoogleFonts.cairo())),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pop<Tenant>(t);
    }
  }
}
