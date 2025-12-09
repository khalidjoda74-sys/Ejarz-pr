// lib/ui/properties_screen.dart
import 'dart:ui';
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/ksa_time.dart'; // ✅ لتستخدم KsaTime.now()
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart';
import '../data/services/user_scope.dart';
import '../data/constants/boxes.dart';   // أو المسار الصحيح حسب مكان الملف
import '../data/services/offline_sync_service.dart';
import 'dart:async' show unawaited;







// 👇 هذا السطر الجديد لاستيراد نوع العقد نفسه
import 'contracts_screen.dart' show Contract, ContractDetailsScreen;


import '../models/property.dart';
import '../models/tenant.dart';

// للتنقّل عبر الـ BottomNav
import 'home_screen.dart';
import 'tenants_screen.dart';
import 'contracts_screen.dart' as contracts_ui show ContractsScreen;

// عناصر الواجهة المشتركة
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';

// ===== SnackBar throttle لتفادي تكرار التنبيهات =====
DateTime? _lastExceedSnackAtProps;
bool _exceedSnackQueuedProps = false;

void _showExceedSnackOnce({BuildContext? ctx, required String msg, Duration dur = const Duration(seconds: 2)}) {
  final now = DateTime.now();
  // تهدئة: لا تظهر أكثر من مرة كل 800ms
  if (_lastExceedSnackAtProps != null &&
      now.difference(_lastExceedSnackAtProps!).inMilliseconds < 800) {
    return;
  }
  _lastExceedSnackAtProps = now;

  // لا تحجز أكثر من callback واحد في نفس الوقت
  if (_exceedSnackQueuedProps) return;
  _exceedSnackQueuedProps = true;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final focusCtx = WidgetsBinding.instance.focusManager.primaryFocus?.context;
    final useCtx = ctx ?? focusCtx;
    if (useCtx != null) {
      final sm = ScaffoldMessenger.maybeOf(useCtx);
      if (sm != null && sm.mounted) {
        sm
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(msg, style: GoogleFonts.cairo()),
              behavior: SnackBarBehavior.floating,
              duration: dur,
            ),
          );
      }
    }
    _exceedSnackQueuedProps = false;
  });
}

// قصّ أي إدخال يتجاوز الحد ويُظهر تنبيه لحظي (مع تهدئة)
TextInputFormatter _limitWithFeedbackFormatter({
  required int max,
  required String exceedMsg,
  BuildContext? ctx, // اختياري
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    if (newV.text.characters.length <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV; // امنع التجاوز
  });
}

// حدّ أقصى لعدد صحيح مع تنبيه SnackBar (مع تهدئة)
TextInputFormatter _maxIntWithFeedback({
  required int max,
  required String exceedMsg,
  BuildContext? ctx,
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    final t = newV.text;
    if (t.isEmpty) return newV;
    final n = int.tryParse(t);
    if (n != null && n <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV;
  });
}

// حدّ أقصى لعدد عشري/عددي مع تنبيه SnackBar (مع تهدئة)
TextInputFormatter _maxNumWithFeedback({
  required num max,
  required String exceedMsg,
  BuildContext? ctx,
}) {
  return TextInputFormatter.withFunction((oldV, newV) {
    final t = newV.text;
    if (t.isEmpty) return newV;
    final n = num.tryParse(t);
    if (n != null && n <= max) return newV;
    _showExceedSnackOnce(ctx: ctx, msg: exceedMsg);
    return oldV;
  });
}


const String kArchivedPropsBoxBase = 'archivedPropsBox';
String archivedBoxName() => boxName(kArchivedPropsBoxBase);

/// فتح صندوق الأرشفة (إن لم يكن مفتوحًا)
Future<Box<bool>> _openArchivedBox() async {
if (!Hive.isBoxOpen(archivedBoxName())) {
try {
return await Hive.openBox<bool>(archivedBoxName());
} catch (_) {}
}
return Hive.box<bool>(archivedBoxName());
}

/// قراءة حالة الأرشفة
bool _isArchivedProp(String propertyId) {
  try {
    final b = Hive.box<Property>(boxName(kPropertiesBox));
    for (final e in b.values) {
      if (e.id == propertyId) {
        return e.isArchived == true;
      }
    }
  } catch (_) {}
  return false;
}

/// ضبط حالة الأرشفة
Future<void> _setArchivedProp(String propertyId, bool archived) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));
  for (final e in b.values) {
    if (e.id == propertyId) {
      e.isArchived = archived;
      await b.put(e.id, e);
      break;
    }
  }
}

/// ضبط حالة الأرشفة لمجموعة معًا
Future<void> _setArchivedMany(Iterable<String> ids, bool archived) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));
  for (final e in b.values) {
    if (ids.contains(e.id)) {
      e.isArchived = archived;
      await b.put(e.id, e);
    }
  }
}


/// فكّ الأرشفة للعقار نفسه وللأب (إن كانت وحدة)
Future<void> _unarchiveSelfAndParent(Property p) async {
  final b = Hive.box<Property>(boxName(kPropertiesBox));

  // فك أرشفة العنصر نفسه
  if (p.isArchived == true) {
    p.isArchived = false;
    await b.put(p.id, p);
  }

  // فك أرشفة الأب (إن وُجد)
  final parentId = p.parentBuildingId;
  if (parentId != null) {
    for (final e in b.values) {
      if (e.id == parentId && e.isArchived == true) {
        e.isArchived = false;
        await b.put(e.id, e);
        break;
      }
    }
  }
}


/// دائرة ناعمة للخلفية
Widget _softCircle(double size, Color color) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// منطق المساعدة
bool _isBuilding(Property p) => p.type == PropertyType.building;
bool _isPerUnit(Property p) => _isBuilding(p) && p.rentalMode == RentalMode.perUnit;
bool _isWholeBuilding(Property p) => _isBuilding(p) && p.rentalMode == RentalMode.wholeBuilding;
bool _isUnit(Property p) => p.parentBuildingId != null;

/// يعيد عددًا صحيحًا موجبًا كحد أدنى
int _availableUnits(Property p) {
  final d = p.totalUnits - p.occupiedUnits;
  return d > 0 ? d : 0;
}

bool _isAvailable(Property p) {
  if (_isPerUnit(p)) return _availableUnits(p) > 0;
  return p.occupiedUnits == 0;
}

/// أيقونة النوع
IconData _iconOf(PropertyType type) {
  switch (type) {
    case PropertyType.apartment:
      return Icons.apartment_rounded;
    case PropertyType.villa:
      return Icons.house_rounded;
    case PropertyType.building:
      return Icons.business_rounded;
    case PropertyType.land:
      return Icons.terrain_rounded;
    case PropertyType.office:
      return Icons.domain_rounded;
    case PropertyType.shop:
      return Icons.storefront_rounded;
    case PropertyType.warehouse:
      return Icons.warehouse_rounded;
  }
}
// يستخرج الرقم في آخر الاسم (يدعم "شقة 3" و"شقة3").
// إذا لم يوجد رقم، يُعيد -1 ليأتي بعد المرقّمات.
int _extractTrailingNumber(String name) {
  final noSpaces = name.replaceAll(' ', '');
  final m = RegExp(r'(\d+)$').firstMatch(noSpaces);
  return m == null ? -1 : int.tryParse(m.group(1)!) ?? -1;
}


/// محاولة آمنة لمعرفة هل هناك عقد نشط مرتبط بـ propertyId
bool _hasActiveContractForPropertyId(String propertyId) {
final cname = HiveService.contractsBoxName(); // قد يكون alias+scoped
if (!Hive.isBoxOpen(cname)) return false;
dynamic box;
try {
box = Hive.box(cname);
  } catch (_) {
    return false;
  }
  try {
    final now = DateTime.now();
    for (final e in (box as Box).values) {
      if (e is Map) {
        final pid = e['propertyId'];
        final isActive = e['isActive'];
        final terminated = e['isTerminated'] == true;
        DateTime? start, end;
        try {
          start = e['startDate'] as DateTime?;
        } catch (_) {}
        try {
          end = e['endDate'] as DateTime?;
        } catch (_) {}
        if (pid == propertyId) {
          if (isActive == true && !terminated) return true;
          if (start != null && end != null && !terminated) {
            final sd = DateTime(start.year, start.month, start.day);
            final ed = DateTime(end.year, end.month, end.day);
            final today = DateTime(now.year, now.month, now.day);
            final active = !today.isBefore(sd) && !today.isAfter(ed);
            if (active) return true;
          }
        }
      } else {
        try {
          final c = e as dynamic;
          final pid = c.propertyId as String?;
          final start = c.startDate as DateTime?;
          final end = c.endDate as DateTime?;
          final terminated = (c.isTerminated as bool?) ?? false;
          if (pid == propertyId && start != null && end != null && !terminated) {
            final sd = DateTime(start.year, start.month, start.day);
            final ed = DateTime(end.year, end.month, end.day);
            final today = DateTime(now.year, now.month, now.day);
            final active = !today.isBefore(sd) && !today.isAfter(ed);
            if (active) return true;
          }
        } catch (_) {}
      }
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// هل مرتبط بعقد؟
/// - الوحدة/العقار العادي: فحص مباشر.
/// - العمارة: أي عقد على العمارة نفسها أو على أي وحدة تابعة يعتبر ارتباطًا نشطًا.
bool _hasActiveContract(Property p) {
  if (_hasActiveContractForPropertyId(p.id)) return true;
  if (!_isPerUnit(p) && p.occupiedUnits > 0) return true;

  if (_isBuilding(p)) {
    final box = Hive.box<Property>(boxName(kPropertiesBox));
    for (final u in box.values.where((e) => e.parentBuildingId == p.id)) {
      if (_hasActiveContractForPropertyId(u.id) || u.occupiedUnits > 0) return true;
    }
  }
  return false;
}

/// استخراج مواصفات [[SPEC]] من الوصف (بدون تعديل الموديل)
Map<String, String> _parseSpec(String? desc) {
  if (desc == null || desc.isEmpty) return {};
  final start = desc.indexOf('[[SPEC]]');
  final end = desc.indexOf('[[/SPEC]]');
  if (start == -1 || end == -1 || end <= start) return {};
  final body = desc.substring(start + 8, end).trim();
  final map = <String, String>{};
  for (final line in body.split('\n')) {
    final parts = line.split(':');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      final value = parts.sublist(1).join(':').trim();
      if (key.isNotEmpty && value.isNotEmpty) map[key] = value;
    }
  }
  return map;
}

/// استخراج الوصف الحر (بعد كتلة SPEC)
String _extractFreeDesc(String? desc) {
  final d = (desc ?? '').trim();
  if (d.isEmpty) return '';
  final start = d.indexOf('[[SPEC]]');
  final end = d.indexOf('[[/SPEC]]');
  if (start != -1 && end != -1 && end > start) {
    final after = d.substring(end + 9).trim();
    return after;
  }
  return d;
}

/// دمج مواصفات [[SPEC]] مع وصف حر
String _buildSpec({
  int? baths,
  int? halls,
  int? floorNo,
  bool? furnished,
  String? extraDesc,
}) {
  final b = StringBuffer();
  b.writeln('[[SPEC]]');
  if (baths != null) b.writeln('حمامات: $baths');
  if (halls != null) b.writeln('صالات: $halls');
  if (floorNo != null) b.writeln('الدور: $floorNo');
  if (furnished != null) b.writeln('المفروشات: ${furnished ? "مفروشة" : "غير مفروشة"}');
  b.writeln('[[/SPEC]]');
  if ((extraDesc ?? '').trim().isNotEmpty) {
    b.writeln(extraDesc!.trim());
  }
  return b.toString().trim();
}

/// لعرض حتى 50 حرف في النصوص (الاسم)
String _limitChars(String text, int max) => (text.length <= max) ? text : '${text.substring(0, max)}…';

/// فلاتر خارجيّة (مستوى الملف)
enum AvailabilityFilter { all, availableOnly, occupiedOnly }
enum _RentalModeFilter { all, whole, perUnit, nonBuilding }

/// ============================================================================
/// أدوات مشتركة للأرشفة (تفعيل/تعطيل + تتبّع للوحدات إن كانت عمارة)
/// ============================================================================
Future<void> _toggleArchiveForProperty(BuildContext context, Property p) async {
  // منع الأرشفة في حال وجود عقد نشط (يشمل عقود الوحدات عند كون p عمارة)
  if (_hasActiveContract(p)) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actionsAlignment: MainAxisAlignment.center,
        title: Text('لا يمكن الأرشفة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text('العقار مرتبط بعقد نشط. لا يمكن أرشفته إلا بعد إنهاء العقد.', style: GoogleFonts.cairo(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('حسنًا', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return;
  }

  // 1) احسب القيمة الجديدة وحدّث الكائن
  final newVal = !(p.isArchived == true);
  p.isArchived = newVal;

  // 2) خزّن في Hive بمفتاح = id (مهم جدًّا لتجنّب الارتداد/الدبل)
  final box = Hive.box<Property>(boxName(kPropertiesBox));
  await box.put(p.id, p);  // لا تستخدم add

  // 3) ادفع المزامنة (إن وجدت خدمة/ريبو)
  unawaited(OfflineSyncService.instance.enqueueUpsertProperty(p));
  // أو: unawaited(propertiesRepo.saveProperty(p));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newVal ? 'تم الأرشفة' : 'تم فك الأرشفة', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// إزالة الحالة من صندوق الأرشفة (مع تتبّع للوحدات عند الحاجة)
Future<void> _clearArchiveState(Property p) async {
  try {
    final ab = await _openArchivedBox();
    // احذف حالة الأرشفة للعقار فقط — لا تلمس الوحدات إطلاقًا
    await ab.delete(p.id);
  } catch (_) {}
}
Future<void> deletePropertyById(String id) async {
  final box = Hive.box<Property>(boxName(kPropertiesBox));
  dynamic keyToDelete;
  for (final k in box.keys) {
    final v = box.get(k);
    if (v is Property && v.id == id) { keyToDelete = k; break; }
  }
  if (keyToDelete != null) {
    await box.delete(keyToDelete);
  }
}

/// ============================================================================
/// شاشة قائمة العقارات
/// ============================================================================
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  Box<Property> get _box => Hive.box<Property>(boxName(kPropertiesBox));

  // —— لضبط الدروَر بين الـAppBar والـBottomNav
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

bool _handledOpen = false;


  // بحث + تصفية + أرشيف
  String _q = '';
  bool _showArchived = false;
  AvailabilityFilter _availability = AvailabilityFilter.all;
  PropertyType? _typeFilter;
  _RentalModeFilter _rentalModeFilter = _RentalModeFilter.all;

  @override
void initState() {
  super.initState();
  // افتح صندوق الأرشفة مبكرًا
() async {
await HiveService.ensureReportsBoxesOpen(); // يفتح صناديق هذا المستخدم + يحلّ aliases
await _openArchivedBox();
if (mounted) setState(() {});
}();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final h = _bottomNavKey.currentContext?.size?.height;
    if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
      setState(() => _bottomBarHeight = h);
    }

    // ✅ فتح عقار معيّن عند الوصول من شاشة العقد
    if (_handledOpen) return;
    _handledOpen = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    final String? openId = (args is Map) ? args['openPropertyId'] as String? : null;
    if (openId != null) _openPropertyDetailsById(openId);
  });
}


  void _handleBottomTap(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 1:
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        AvailabilityFilter av = _availability;
        PropertyType? tp = _typeFilter;
        _RentalModeFilter rm = _rentalModeFilter;
        bool arch = _showArchived; // ← خيار الأرشفة داخل الفلتر

        return StatefulBuilder(
          builder: (ctx, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('التصفية', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
                  SizedBox(height: 12.h),

                  DropdownButtonFormField<AvailabilityFilter>(
                    value: av,
                    decoration: _dd('التوفّر'),
                    dropdownColor: const Color(0xFF0F172A),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
                    items: const [
                      DropdownMenuItem(value: AvailabilityFilter.all, child: Text('الكل')),
                      DropdownMenuItem(value: AvailabilityFilter.availableOnly, child: Text('المتاحة فقط')),
                      DropdownMenuItem(value: AvailabilityFilter.occupiedOnly, child: Text('المشغولة فقط')),
                    ],
                    onChanged: (v) => setM(() => av = v ?? av),
                  ),
                  SizedBox(height: 10.h),

                DropdownButtonFormField<PropertyType?>(
  value: tp,
  decoration: _dd('نوع العقار'),
  dropdownColor: const Color(0xFF0F172A),
  iconEnabledColor: Colors.white70,
  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
  items: <PropertyType?>[null, ...PropertyType.values]
      .map((t) => DropdownMenuItem(value: t, child: Text(t == null ? 'الكل' : t.label)))
      .toList(),
  onChanged: (v) => setM(() {
    tp = v;
    if (tp != PropertyType.building) {
      rm = _RentalModeFilter.all; // صفّر نمط التأجير إذا لم تكن "عمارة"
    }
  }),
),

                  if (tp == PropertyType.building) ...[
  SizedBox(height: 10.h),
  DropdownButtonFormField<_RentalModeFilter>(
    value: rm,
    decoration: _dd('نمط التأجير'),
    dropdownColor: const Color(0xFF0F172A),
    iconEnabledColor: Colors.white70,
    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
    items: const [
      DropdownMenuItem(value: _RentalModeFilter.all, child: Text('الكل')),
      DropdownMenuItem(value: _RentalModeFilter.whole, child: Text('تأجير كامل')),
      DropdownMenuItem(value: _RentalModeFilter.perUnit, child: Text('تأجير وحدات')),
      DropdownMenuItem(value: _RentalModeFilter.nonBuilding, child: Text('غير عمارة')),
    ],
    onChanged: (v) => setM(() => rm = v ?? rm),
  ),
],


                  // —— الأرشفة: خياران يمين/يسار (الكل / الأرشفة)
                  SizedBox(height: 14.h),
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
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
                          onPressed: () {
                            setState(() {
                              _availability = av;
                              _typeFilter = tp;
                              _rentalModeFilter = rm;
                              _showArchived = arch; // ← تطبيق الأرشفة
                            });
                            Navigator.pop(context);
                          },
                          child: Text('تطبيق', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _availability = AvailabilityFilter.all;
                              _typeFilter = null;
                              _rentalModeFilter = _RentalModeFilter.all;
                              _showArchived = false; // ← رجوع للوضع الافتراضي (الكل)
                            });
                            Navigator.pop(context);
                          },
                          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

void _openPropertyDetailsById(String id) {
  final box = _box; // Hive.box<Property>('propertiesBox');
  Property? p;
  try {
    p = box.values.firstWhere((e) => e.id == id);
  } catch (_) {}

  if (p == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('العقار غير موجود', style: GoogleFonts.cairo())),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PropertyDetailsScreen(item: p!)),
  );
}


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

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    final ok = await showDialog<bool>(
          context: context,
         builder: (_) => AlertDialog(
  backgroundColor: const Color(0xFF0B1220),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  actionsAlignment: MainAxisAlignment.center, // ✅ يوسّط الأزرار
  title: Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
  content: Text(msg, style: GoogleFonts.cairo(color: Colors.white70)),
  actions: [
    // ✅ ضع "تأكيد" أولاً ليظهر يمينًا في RTL
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
      onPressed: () => Navigator.pop(context, true),
      child: Text('تأكيد', style: GoogleFonts.cairo(color: Colors.white)),
    ),
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70)),
    ),
  ],
),

        ) ??
        false;
    return ok;
  }

  // —— هل هناك فلاتر نشطة؟
  bool get _hasActiveFilters =>
      _showArchived ||
      _availability != AvailabilityFilter.all ||
      _typeFilter != null ||
      _rentalModeFilter != _RentalModeFilter.all;

  // —— نص موجز للفلتر الحالي
  String _currentFilterLabel() {
    final parts = <String>[];
    parts.add(_showArchived ? 'المؤرشفة' : 'الكل');

    switch (_availability) {
      case AvailabilityFilter.availableOnly:
        parts.add('المتاحة فقط');
        break;
      case AvailabilityFilter.occupiedOnly:
        parts.add('المشغولة فقط');
        break;
      case AvailabilityFilter.all:
        break;
    }

    if (_typeFilter != null) {
      parts.add(_typeFilter!.label);
    }

    switch (_rentalModeFilter) {
      case _RentalModeFilter.whole:
        parts.add('تأجير كامل');
        break;
      case _RentalModeFilter.perUnit:
        parts.add('تأجير وحدات');
        break;
      case _RentalModeFilter.nonBuilding:
        parts.add('غير عمارة');
        break;
      case _RentalModeFilter.all:
        break;
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text('العقارات', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20.sp)),
          actions: [
            IconButton(
              tooltip: 'تصفية',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
              onPressed: _openFilters,
            ),
          ],
        ),
        body: Stack(
          children: [
            // خلفية
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
                // شريط البحث
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم/العنوان',
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

                // وسم الفلاتر
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
                            Text(_currentFilterLabel(),
                                style: GoogleFonts.cairo(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // قائمة العقارات
                Expanded(
                  child: AnimatedBuilder(
animation: Hive.isBoxOpen(archivedBoxName())
? Hive.box<bool>(archivedBoxName()).listenable()
: ValueNotifier(0),
                    builder: (_, __) {
                      return ValueListenableBuilder(
                        valueListenable: _box.listenable(),
                        builder: (context, box, _) {
                          final b = box as Box<Property>;

// أظهر الوحدات فقط إذا كان هناك فلاتر مفعّلة، وعند "نوع العقار: الكل" أو "شقة"
var items = b.values.where((p) {
  if (p.parentBuildingId == null) return true; // العقارات/العمائر تظهر دائمًا
  final showUnits = _hasActiveFilters && ((_typeFilter == null) || (_typeFilter == PropertyType.apartment));
  return showUnits;
}).toList();
// إزالة التكرار حسب id قبل الفرز/العرض
final byId = <String, Property>{};
for (final p in items) {
  byId[p.id] = p; // آخر قيمة تفوز
}
items = byId.values.toList();






                          // ✅ أمان إضافي: أي عقار مؤرشف وعليه عقد نشط (هو أو أي وحدة) نفك أرشفته تلقائيًا
                          for (final top in items.where((e) => e.parentBuildingId == null)) {

                            if (_isArchivedProp(top.id) && _hasActiveContract(top)) {
                              _setArchivedProp(top.id, false);
                            }
                          }

                          // أرشيف (باستخدام صندوق منفصل)
                          items = items.where((p) => (p.isArchived == true) == _showArchived).toList();


                          // فلاتر
                          if (_typeFilter != null) {
                            items = items.where((p) => p.type == _typeFilter).toList();
                          }
                          switch (_rentalModeFilter) {
                            case _RentalModeFilter.whole:
                              items = items.where((p) => _isWholeBuilding(p)).toList();
                              break;
                            case _RentalModeFilter.perUnit:
                              items = items.where((p) => _isPerUnit(p)).toList();
                              break;
                            case _RentalModeFilter.nonBuilding:
                              items = items.where((p) => !_isBuilding(p)).toList();
                              break;
                            case _RentalModeFilter.all:
                              break;
                          }
                          switch (_availability) {
                            case AvailabilityFilter.availableOnly:
                              items = items.where((p) => _isAvailable(p)).toList();
                              break;
                            case AvailabilityFilter.occupiedOnly:
                              items = items.where((p) => !_isAvailable(p)).toList();
                              break;
                            case AvailabilityFilter.all:
                              break;
                          }

                          // بحث
                          if (_q.isNotEmpty) {
                            final q = _q.toLowerCase();
                            items = items
                                .where((p) => p.name.toLowerCase().contains(q) || p.address.toLowerCase().contains(q))
                                .toList();
                          }

                          // الأحدث أولاً اعتمادًا على أن id رقم زمني (microsecondsSinceEpoch) محفوظ كسلسلة
items.sort((a, c) {
  final ai = int.tryParse(a.id) ?? 0;
  final ci = int.tryParse(c.id) ?? 0;
  return ci.compareTo(ai);
});


                          if (items.isEmpty) {
                            return Center(
                              child: Text(_showArchived ? 'لا توجد عقارات مؤرشفة' : 'لا توجد عقارات بعد',
                                  style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
                            );
                          }

                          return ListView.separated(
                            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => SizedBox(height: 12.h),
                            itemBuilder: (context, i) {
                              final p = items[i];

                              return InkWell(
                                borderRadius: BorderRadius.circular(16.r),
                                // الضغط المطوّل: أرشفة/فك الأرشفة مباشرة (مع منع الأرشفة إذا هناك عقد نشط)
                                // الضغط المطوّل: أرشفة/فك الأرشفة مباشرة (مع منع الأرشفة إذا هناك عقد نشط)
onLongPress: () async {
  // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
  if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

  if (_hasActiveContract(p)) {
    await showDialog(
      context: context,
      builder: (ctx) => _alert(
        ctx,
        title: 'لا يمكن الأرشفة',
        message: 'العقار مرتبط بعقد نشط. لا يمكن أرشفته إلا بعد إنهاء العقد.',
      ),
    );
    return;
  }
  await _toggleArchiveForProperty(context, p);
  if (mounted) setState(() {});
},

                                // الضغط العادي: فتح التفاصيل
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => PropertyDetailsScreen(item: p)),
                                  );
                                },
                                child: _DarkCard(
                                  padding: EdgeInsets.all(12.w),
                                  child: Stack(
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(minHeight: 118.h),
                                        child: Row(
                                          children: [
                                            // أيقونة حسب النوع
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
                                              child: Icon(_iconOf(p.type), color: Colors.white),
                                            ),
                                            SizedBox(width: 12.w),

                                            Expanded(
                                              child: Padding(
                                                padding: EdgeInsets.only(left: 128.w),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _limitChars(p.name, 50),
                                                            maxLines: 2,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: GoogleFonts.cairo(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.w800,
                                                              fontSize: 16.sp,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 4.h),
                                                    Row(
                                                      children: [
                                                        Icon(Icons.location_on_outlined, size: 16.sp, color: Colors.white70),
                                                        SizedBox(width: 4.w),
                                                        Expanded(
                                                          child: Text(
                                                            p.address,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: GoogleFonts.cairo(
                                                              color: Colors.white70,
                                                              fontSize: 12.sp,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 8.h),

                                                    // معلومات عدد الوحدات:
                                                   // معلومات عدد الوحدات:
if (_isBuilding(p) && p.totalUnits > 0) ...[
  Wrap(
    spacing: 6.w,
    runSpacing: 6.h,
    children: [
      _chip('عدد الوحدات: ${p.totalUnits}', bg: const Color(0xFF1F2937)),

      // نحافظ على ارتفاع موحّد للبطاقة باستخدام Visibility مع maintainSize
      Visibility(
        visible: _isPerUnit(p),
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: _chip('مشغولة: ${p.occupiedUnits}', bg: const Color(0xFF7F1D1D)),
      ),
      Visibility(
        visible: _isPerUnit(p),
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: _chip('المتاحة: ${_availableUnits(p)}', bg: const Color(0xFF064E3B)),
      ),
    ],
  ),
],

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                                          ],
                                        ),
                                      ),
                                      // نوع العقار
                                      Positioned(
                                        left: 8,
                                        top: 8,
                                        child: _chip(_isUnit(p) ? 'وحدة (${p.type.label})' : p.type.label,
                                            bg: const Color(0xFF334155)),
                                      ),
                                      // شارة نمط التأجير (عمارة فقط)
                                      if (_isBuilding(p))
                                        Positioned(
                                          left: 8,
                                          top: 38,
                                          child: _chip(_isPerUnit(p) ? 'تأجير وحدات' : 'تأجير كامل',
                                              bg: const Color(0xFF1E293B)),
                                        ),
                                      // الحالة
                                      Positioned(
                                        left: 8,
                                        bottom: 8,
                                        child: _chip(_isAvailable(p) ? 'متاحة' : 'مشغولة',
                                            bg: _isAvailable(p) ? const Color(0xFF065F46) : const Color(0xFF7F1D1D)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

               floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.add_business_rounded),
          label: Text('إضافة عقار', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: () async {
            // 🚫 منع عميل المكتب من إضافة عقار
            if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

            final created = await Navigator.of(context).push<Property?>(
              MaterialPageRoute(builder: (_) => const AddOrEditPropertyScreen()),
            );
            if (created != null) {
              await _box.put(created.id, created); // ← put باستخدام id
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم إضافة "${created.name}"', style: GoogleFonts.cairo()),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        ),


        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Future<void> _openRowMenu(BuildContext context, Property p) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        final archived = _isArchivedProp(p.id);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('إجراءات سريعة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
                SizedBox(height: 12.h),
                               ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من التعديل
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                    Navigator.pop(context);
                    if (_hasActiveContract(p)) {
                      await showDialog(
                        context: context,
                        builder: (ctx) => _alert(
                          ctx,
                          title: 'لا يمكن التعديل',
                          message: _isPerUnit(p)
                              ? 'لا يمكن تعديل بيانات العمارة لأ...وحداتها مرتبطة بعقود نشطة. يمكن تعديل الوحدات غير المرتبطة فقط.'
                              : 'العقار مرتبط بعقد نشط، لذلك لا يمكن تعديله إلا بعد إنهاء العقد',
                        ),
                      );
                      return;
                    }

                    final updated = await Navigator.of(context).push<Property?>(
                      MaterialPageRoute(builder: (_) => AddOrEditPropertyScreen(existing: p)),
                    );
                    if (updated != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم التحديث', style: GoogleFonts.cairo()),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {}); // للتحديث إن لزم
                    }
                  },
                  leading: const Icon(Icons.edit_rounded, color: Colors.white),
                  title: Text('تعديل', style: GoogleFonts.cairo(color: Colors.white)),
                ),

                                ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من الأرشفة/فك الأرشفة
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                    Navigator.pop(context);
                    await _toggleArchiveForProperty(context, p);
                    if (mounted) setState(() {});
                  },
                  leading: Icon(archived ? Icons.unarchive_rounded : Icons.archive_rounded, color: Colors.white),
                  title: Text(archived ? 'فك الأرشفة' : 'أرشفة', style: GoogleFonts.cairo(color: Colors.white)),
                ),

                                ListTile(
                  onTap: () async {
                    // 🚫 منع عميل المكتب من الحذف
                    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                    Navigator.pop(context);
                    await _confirmDelete(context, p);
                  },
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.white),
                  title: Text('حذف', style: GoogleFonts.cairo(color: Colors.white)),
                ),

              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Property p) async {
    if (_isBuilding(p)) {
      final hasUnits = Hive.box<Property>(boxName(kPropertiesBox)).values.any((e) => e.parentBuildingId == p.id);
      if (hasUnits) {
        await showDialog(
          context: context,
          builder: (ctx) => _alert(
            ctx,
            title: 'لا يمكن الحذف',
            message: 'لا يمكن حذف العمارة قبل حذف جميع الوحدات التابعة لها.',
          ),
        );
        return;
      }
    }

      // 🚫 منع حذف العقار في حال وجود أي عقد (نشط أو منتهي) مرتبط بهذا العقار
  try {
    final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
    final hasAnyContract = contractsBox.values.any(
      (c) => c.propertyId == p.id,
    );

    if (hasAnyContract) {
      await showDialog(
        context: context,
        builder: (ctx) => _alert(
          ctx,
          title: 'لا يمكن الحذف',
          message: 'لا يمكن حذف هذا العقار لوجود عقود مرتبطة به حتى لو كانت منتهية.\n'
              'لحذف العقار يجب أولًا حذف جميع العقود المرتبطة به من شاشة العقود.',
        ),
      );
      return;
    }
  } catch (_) {
    // لو حصل خطأ في قراءة صندوق العقود لا نكسر الشاشة
  }


    final confirmed = await _confirm(context, 'تأكيد الحذف', 'هل تريد حذف "${p.name}"؟');
    if (!confirmed) return;

    final parentId = p.parentBuildingId;
   await deletePropertyById(p.id);

OfflineSyncService.instance.enqueueDeleteProperty(p.id); // بدون await


    // احذف حالة الأرشفة المخزنة له (وتتبّع للوحدات)
    await _clearArchiveState(p);

  

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف "${p.name}"', style: GoogleFonts.cairo()), behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).maybePop();
    }
  }

  AlertDialog _alert(BuildContext ctx, {required String title, required String message}) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
actionsAlignment: MainAxisAlignment.center, // ← يوسّط الأزرار

      title: Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text(message, style: GoogleFonts.cairo(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('حسنًا', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
      ],
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
      child: Text(text, style: GoogleFonts.cairo(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700)),
    );
  }
}

/// ============================================================================
/// تفاصيل العقار
/// ============================================================================
class PropertyDetailsScreen extends StatefulWidget {
  final Property item;
  const PropertyDetailsScreen({super.key, required this.item});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  Box<Property> get _box => Hive.box<Property>(boxName(kPropertiesBox));

  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  @override
  void initState() {
    super.initState();
    // افتح صندوق الأرشفة مبكرًا
() async {
await HiveService.ensureReportsBoxesOpen();
await _openArchivedBox();
if (mounted) setState(() {});
}();
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  /// فتح تفاصيل العقد مباشرة لعقار معيّن بدون المرور على شاشة العقود (لتفادي الوميض)
  Future<void> _openContractDetailsDirect(Property p) async {
    try {
      final cname = HiveService.contractsBoxName();
      final contractsBox = Hive.isBoxOpen(cname)
          ? Hive.box<Contract>(cname)
          : await Hive.openBox<Contract>(cname);

      // كل العقود غير المؤرشفة المرتبطة بهذا العقار
      final byProp = contractsBox.values
          .where((c) => c.propertyId == p.id && !c.isArchived)
          .toList();

      if (byProp.isEmpty) {
        // احتياط: لو ما لقينا عقد (مع إن _hasActiveContract رجّع true) نرجع للسلوك القديم
        await Navigator.pushNamed(
          context,
          '/contracts',
          arguments: {'openPropertyId': p.id},
        );
        return;
      }

      // نفس منطق ContractsScreen: الأحدث، مع تفضيل العقد النشط الآن
      byProp.sort((a, b) => b.startDate.compareTo(a.startDate));
      final Contract target =
          byProp.firstWhere((c) => c.isActiveNow, orElse: () => byProp.first);

      // فتح شاشة تفاصيل العقد مباشرة
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractDetailsScreen(contract: target),
        ),
      );

      // بعد الرجوع: فك الأرشفة وتحديث الواجهة
      await _unarchiveSelfAndParent(p);
      if (mounted) setState(() {});
    } catch (_) {
      // في حالة أي خطأ، نفتح شاشة العقود الكاملة كحل احتياطي
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const contracts_ui.ContractsScreen(),
        ),
      );
    }
  }


  // في _PropertyDetailsScreenState
  // في _PropertyDetailsScreenState
  Future<void> _goToAddOrViewContract(Property p) async {
    final has = _hasActiveContract(p);
    try {
      if (has) {
        // 🔄 افتح تفاصيل العقد مباشرة بدون وميض شاشة العقود
        await _openContractDetailsDirect(p);
        return;
      }

      // شاشة إضافة عقد تُرجع Contract عند الحفظ والرجوع
      final result = await Navigator.pushNamed(
        context,
        '/contracts/new',
        arguments: {'prefillPropertyId': p.id},
      );

      if (result is Contract) {
        // خزّن العقد محليًا
        final cname = HiveService.contractsBoxName();
        final contractsBox = Hive.isBoxOpen(cname)
            ? Hive.box<Contract>(cname)
            : await Hive.openBox<Contract>(cname);
        await contractsBox.add(result);

        // ✅ فورًا: فك الأرشفة عن العقار نفسه وإن كان وحدة فك عن العمارة الأب أيضًا
        await _unarchiveSelfAndParent(p);

        // حدّث عدّاد عقود المستأجر النشطة
        final tenants = Hive.box<Tenant>(boxName(kTenantsBox));
        Tenant? t;
        for (final e in tenants.values) {
          if (e.id == result.tenantId) {
            t = e;
            break;
          }
        }
        if (t != null && (result as dynamic).isActiveNow == true) {
          t!.activeContractsCount += 1;
          t!.updatedAt = DateTime.now();
          await t!.save();
        }

        // حدّث إشغال العقار/الوحدة
        final props = Hive.box<Property>(boxName(kPropertiesBox));
        Property? target;
        for (final e in props.values) {
          if (e.id == p.id) {
            target = e;
            break;
          }
        }

        if (target != null) {
          if (target.parentBuildingId != null) {
            // وحدة داخل عمارة
            target.occupiedUnits = 1;
            await props.put(target.id, target); // ← بدل save()

            // تحديث إشغال العمارة
            Property? building;
            for (final e in props.values) {
              if (e.id == target!.parentBuildingId) {
                building = e;
                break;
              }
            }
            if (building != null) {
              final units = props.values.where((e) => e.parentBuildingId == building!.id);
              final occupiedCount = units.where((u) => u.occupiedUnits > 0).length;
              building.occupiedUnits = occupiedCount;
              await props.put(building.id, building); // ← بدل save()
            }
          } else {
            // عقار مستقل
            target.occupiedUnits = 1;
            await props.put(target.id, target); // ← بدل save()
          }
        }

        // افتح شاشة العقود بعد الحفظ وحدّث الواجهة
        if (mounted) {
          await Navigator.pushNamed(
            context,
            '/contracts',
            arguments: {'openPropertyId': p.id},
          );

          // ✅ تأكيد فكّ الأرشفة مجددًا بعد العودة
          await _unarchiveSelfAndParent(p);
          setState(() {});
        }
      }
    } catch (_) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const contracts_ui.ContractsScreen(),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final available = _availableUnits(item);
    final bool fullyOccupied = _isPerUnit(item) ? (available == 0) : (item.occupiedUnits > 0);
    final String statusText = fullyOccupied ? 'مشغولة' : 'متاحة';
    final Color statusColor = fullyOccupied ? const Color(0xFFB91C1C) : const Color(0xFF059669);
    final spec = _parseSpec(item.description);
    final archived = _isArchivedProp(item.id);

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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text('تفاصيل العقار', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
            if (item.parentBuildingId == null) // إظهار الزر للعقار/العمارة فقط، وليس للوحدة
             IconButton(
  tooltip: archived ? 'فك الأرشفة' : 'أرشفة',
  onPressed: () async {
    // 🚫 منع عميل المكتب من الأرشفة / فك الأرشفة
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    await _toggleArchiveForProperty(context, item);
    if (mounted) setState(() {});
  },
  icon: Icon(
    archived ? Icons.inventory_2_rounded : Icons.archive_rounded,
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
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 140.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== البطاقة الأساسية =====
                  _DarkCard(
                    padding: EdgeInsets.all(14.w),
                    child: Stack(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(minHeight: 128.h),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                child: Icon(_iconOf(item.type), color: Colors.white),
                              ),
                              SizedBox(height: 12.h, width: 12.w),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 128.w),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_limitChars(item.name, 50),
                                          maxLines: 2,
                                          softWrap: true,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.sp)),
                                      SizedBox(height: 6.h),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 16.sp, color: Colors.white70),
                                          SizedBox(width: 4.w),
                                          Expanded(
                                            child: Text(
                                              item.address,
                                              maxLines: null,
                                              softWrap: true,
                                              overflow: TextOverflow.visible,
                                              style: GoogleFonts.cairo(
                                                  color: Colors.white70, fontSize: 13.sp, fontWeight: FontWeight.w600, height: 1.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 12.h),
                                      Wrap(
                                        spacing: 10.w,
                                        runSpacing: 8.h,
                                        children: [
                                          
                                          if (_isBuilding(item) && item.totalUnits > 0) _pill('عدد الوحدات: ${item.totalUnits}'),
                                          if (_isPerUnit(item)) ...[
                                            _pill('مشغولة: ${item.occupiedUnits}', bg: const Color(0xFF7F1D1D)),
                                            _pill('متاحة: $available', bg: const Color(0xFF064E3B)),
                                          ],
                                          if (item.area != null) _pill('المساحة: ${item.area} م²'),
                                          if (item.floors != null && item.type != PropertyType.apartment) _pill('الطوابق: ${item.floors}'),
                                          if (item.rooms != null) _pill('الغرف: ${item.rooms}'),
                                          if (spec['حمامات'] != null) _pill('الحمامات: ${spec['حمامات']}'),
                                          if (spec['صالات'] != null) _pill('الصالات: ${spec['صالات']}'),
                                          if (spec['الدور'] != null) _pill('الدور: ${spec['الدور']}'),
                                                                                    if (spec['المفروشات'] != null)
                                            _pill(
                                              spec['المفروشات']!,
                                              bg: spec['المفروشات'] == 'مفروشة'
                                                  ? const Color(0xFF065F46)
                                                  : const Color(0xFF1E293B),
                                            ),
                                          if (item.price != null)
                                            _pill('السعر: ${item.price!.toStringAsFixed(0)} ريال'),
                                          if (item.createdAt != null)
                                            _pill(
                                              'تاريخ الإنشاء: ${item.createdAt!.toString().split(" ").first}',
                                              bg: const Color(0xFF1D4ED8), // 🎨 لون مميز
                                            ),
                                        ],

                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(left: 8, top: 8, child: _infoPill(item.type.label, bg: const Color(0xFF065F46))),
// إذا كانت هذه التفاصيل تخص "وحدة" تابعة لعمارة، أظهر شارة "عمارة" قابلة للنقر
if (item.parentBuildingId != null)
  Positioned(
    left: 8,
    top: 38, // تحت شارة "شقة" تمامًا، مثل "تأجير وحدات" في شاشة العمارة
    child: InkWell(
      onTap: () {
        // ابحث عن العمارة الأم وافتح تفاصيلها
        final box = Hive.box<Property>(boxName(kPropertiesBox));
        Property? parent;
        for (final e in box.values) {
          if (e.id == item.parentBuildingId) {
            parent = e;
            break;
          }
        }
        if (parent != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PropertyDetailsScreen(item: parent!)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('لم يتم العثور على العمارة', style: GoogleFonts.cairo())),
          );
        }
      },
      child: _infoPill('عمارة', bg: const Color(0xFF1E293B)),
    ),
  ),

if (_isBuilding(item))
  Positioned(
    left: 8,
    top: 38,
    child: _infoPill(
      _isPerUnit(item) ? 'تأجير وحدات' : 'تأجير كامل',
      bg: const Color(0xFF1E293B),
    ),
  ),

                        Positioned(left: 8, bottom: 8, child: _infoPill(statusText, bg: statusColor)),
                      ],
                    ),
                  ),

                  // ===== أزرار الإجراءات تحت البطاقة =====
                  SizedBox(height: 10.h),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          alignment: WrapAlignment.start,
                          textDirection: TextDirection.rtl,
children: [
  _miniAction(
    icon: Icons.delete_forever_rounded, // ✅ أضفنا الأيقونة
    label: 'حذف',
    bg: const Color(0xFF7F1D1D),
    onTap: () async {
      // 🚫 منع عميل المكتب من الحذف
      if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

      await _confirmDeleteHere(context, item);
    },
  ),


                            _miniAction(
                              icon: Icons.edit_rounded,
                              label: 'تعديل',
                              bg: const Color(0xFF334155),
                              onTap: () async {
                                // 🚫 منع عميل المكتب من التعديل
                                if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

                                if (_hasActiveContract(item)) {
                                  await showDialog(
                                    context: context,
                                    builder: (ctx) => _alertHere(
                                      ctx,
                                      title: 'لا يمكن التعديل',
                                      message: _isPerUnit(item)
                                          ? 'لا يمكن تعديل بيانات العمارة لأن بعض وحداتها مرتبطة بعقود نشطة. يمكن تعديل الوحدات غير المرتبطة فقط.'
                                          : 'العقار مرتبط بعقد نشط، لذلك لا يمكن تعديله إلا بعد إنهاء العقد .',
                                    ),
                                  );
                                  return;
                                }

                                final updated = await Navigator.of(context).push<Property?>(
                                  MaterialPageRoute(builder: (_) => AddOrEditPropertyScreen(existing: item)),
                                );
                                if (updated != null && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('تم التحديث', style: GoogleFonts.cairo()),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  setState(() {});
                                }
                              },
                            ),


                           _miniAction(
  icon: Icons.description_outlined,
  label: 'الملاحظات',
  bg: const Color(0xFF334155),
  onTap: () async {
    // 🚫 منع عميل المكتب من فتح / تعديل الملاحظات
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    _showDescriptionSheet(context, item);
  },
),

                          ],
                        ),
                      ),

                      SizedBox(height: 8.h),

                      // زر إضافة/تفاصيل العقد
                      if (!_isPerUnit(item))
                        Align(
                          alignment: Alignment.centerRight,
                          child: _miniAction(
icon: _hasActiveContract(item)
    ? Icons.assignment_turned_in_rounded
    : Icons.note_add_rounded,
label: _hasActiveContract(item) ? 'تفاصيل العقد' : 'إضافة عقد',
bg: const Color(0xFF0EA5E9),
onTap: () async {
  // 🚫 منع عميل المكتب من إضافة / فتح عقد
  if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

  await _goToAddOrViewContract(item);
},
),

                        ),
                    ],
                  ),

                  // زر إضافة وحدات (إن كانت عمارة ووضع تأجير وحدات)
                  if (_isPerUnit(item)) ...[
                    SizedBox(height: 12.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                        onPressed: () async {
                          final existing = _countUnits(item);
                          if (item.totalUnits > 0 && existing >= item.totalUnits) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تم إضافة جميع الوحدات المتعلقة بالعمارة سابقًا', style: GoogleFonts.cairo()),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                            return;
                          }

                          final list = await Navigator.of(context).push<List<Property>?>(
                            MaterialPageRoute(builder: (_) => AddUnitsScreen(building: item, existingUnitsCount: existing)),
                          );

                          if (list != null && list.isNotEmpty) {
                            final box = Hive.box<Property>(boxName(kPropertiesBox));
                            for (final u in list) {
  await box.put(u.id, u); // ← استخدم المفتاح = id
}

                            

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('تمت إضافة ${list.length} وحدة', style: GoogleFonts.cairo()),
                                    behavior: SnackBarBehavior.floating),
                              );
                              setState(() {});
                            }
                          }
                        },
                        icon: const Icon(Icons.add_home_work_rounded),
                        label: Text('إضافة وحدات العمارة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],

                  // ===== قائمة الوحدات للوضع "تأجير وحدات" =====
                  if (_isPerUnit(item)) ...[
                    SizedBox(height: 14.h),
                    Text('الوحدات', style: GoogleFonts.cairo(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8.h),
                    ValueListenableBuilder(
                      valueListenable: _box.listenable(),
                      builder: (context, box, _) {
                        final b = box as Box<Property>;
                        final units = b.values
                            .where((e) => e.parentBuildingId == item.id)
                            .toList()
   ..sort((a, c) {
  // 1) الأحدث أولًا بالاعتماد على id الزمني (microsecondsSinceEpoch)
  final ai = int.tryParse(a.id) ?? 0;
  final ci = int.tryParse(c.id) ?? 0;
  final byIdDesc = ci.compareTo(ai);
  if (byIdDesc != 0) return byIdDesc;

  // 2) تعادل الوقت: فكّ الترتيب بحسب الرقم في نهاية الاسم (الأكبر أولًا)
  final an = _extractTrailingNumber(a.name);
  final cn = _extractTrailingNumber(c.name);
  if (an != cn) return cn.compareTo(an);

  // 3) تعادل تام: ترتيب أبجدي تنازلي كحل أخير
  return c.name.compareTo(a.name);
});



                        if (units.isEmpty) {
                          return Text('لا توجد وحدات بعد',
                              style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700));
                        }

                        return Column(
                          children: [
                            for (final u in units) ...[
                              _unitCard(u),
                              SizedBox(height: 10.h),
                            ]
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  // ===== إجراءات الملاحظات =====
  void _showDescriptionSheet(BuildContext context, Property p) {
    final String oldDesc = p.description ?? '';
    final String existingFree = _extractFreeDesc(oldDesc);
    final controller = TextEditingController(text: existingFree);

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

              // حقل تحرير الملاحظات الحر
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: 500,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب ملاحظات العقار هنا…',
                  hintStyle: GoogleFonts.cairo(color: Colors.white54),
                  counterText: '',
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
          // نفس كود الحفظ بدون أي تغيير
          final newFree = controller.text.trim();
          String newDesc;
          final d = oldDesc;
          final start = d.indexOf('[[SPEC]]');
          final end = d.indexOf('[[/SPEC]]');
          if (start != -1 && end != -1 && end > start) {
            final specBlock = d.substring(0, end + 9).trimRight();
            newDesc = newFree.isEmpty ? specBlock : '$specBlock\n$newFree';
          } else {
            newDesc = newFree;
          }
p.description = newDesc.trim();
final box = Hive.box<Property>(boxName(kPropertiesBox));
await box.put(p.id, p);

          if (mounted) {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الملاحظات', style: GoogleFonts.cairo()), behavior: SnackBarBehavior.floating),
            );
            setState(() {});
          }
        },
        child: Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
      ),
    ),
    SizedBox(width: 8.w),
    Expanded(
      child: OutlinedButton(
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white)),
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

  int _countUnits(Property building) {
    final all = Hive.box<Property>(boxName(kPropertiesBox)).values;
    return all.where((e) => e.parentBuildingId == building.id).length;
  }

  // بطاقة وحدة ضمن شاشة تفاصيل العمارة — بدون زر تعديل، والضغط يفتح التفاصيل
  Widget _unitCard(Property u) {
    final available = _isAvailable(u);

    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PropertyDetailsScreen(item: u)),
        );
        if (mounted) setState(() {});
      },
      child: _DarkCard(
        padding: EdgeInsets.all(12.w),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 108.h),
              child: Row(
                children: [
                  Container(
                    width: 48.w,
                    height: 48.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.r),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E40AF), Color(0xFF2148C6)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                    child: Icon(_iconOf(u.type), color: Colors.white),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 120.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _limitChars(u.name, 50),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.sp,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14.sp, color: Colors.white70),
                              SizedBox(width: 4.w),
                              Expanded(
                                child: Text(
                                  u.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    color: Colors.white70,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6.h),
                          Wrap(
                            spacing: 6.w,
                            runSpacing: 6.h,
                            children: [
                              _infoPill(
                                available ? 'متاحة' : 'مشغولة',
                                bg: available ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                ],
              ),
            ),

            // شارة نوع العنصر (وحدة)
            Positioned(
              left: 8,
              top: 8,
              child: _infoPill('وحدة (${u.type.label})', bg: const Color(0xFF334155)),
            ),

            // ✅ تمت إزالة زر "تعديل" نهائيًا
          ],
        ),
      ),
    );
  }

  // عناصر UI صغيرة
  Widget _miniAction({required IconData icon, required String label, required VoidCallback onTap, Color bg = const Color(0xFF334155)}) {
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

  Widget _pill(String text, {Color bg = const Color(0xFF1E293B)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text, style: GoogleFonts.cairo(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w700)),
    );
  }

  Widget _infoPill(String text, {Color bg = const Color(0xFF1E293B)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text, style: GoogleFonts.cairo(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w800)),
    );
  }

  // حوار تنبيه محلي لهذه الشاشة
  AlertDialog _alertHere(BuildContext ctx, {required String title, required String message}) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
actionsAlignment: MainAxisAlignment.center, // ← يوسّط الأزرار

      title: Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text(message, style: GoogleFonts.cairo(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('حسنًا', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteHere(BuildContext context, Property p) async {
    // منع حذف العمارة التي بها وحدات
    if (_isBuilding(p)) {
      final hasUnits = Hive.box<Property>(boxName(kPropertiesBox)).values.any((e) => e.parentBuildingId == p.id);
      if (hasUnits) {
        await showDialog(
          context: context,
          builder: (ctx) => _alertHere(
            ctx,
            title: 'لا يمكن الحذف',
            message: 'لا يمكن حذف العمارة قبل حذف جميع الوحدات التابعة لها.',
          ),
        );
        return;
      }
    }

      // 🚫 منع الحذف في حال وجود أي عقد (نشط أو منتهي) مرتبط بهذا العقار
  try {
    final contractsBox = Hive.box<Contract>(boxName(kContractsBox));
    final hasAnyContract = contractsBox.values.any(
      (c) => c.propertyId == p.id,
    );

    if (hasAnyContract) {
      await showDialog(
        context: context,
        builder: (ctx) => _alertHere(
          ctx,
          title: 'لا يمكن الحذف',
          message: 'لا يمكن حذف هذا العقار لوجود عقود مرتبطة به حتى لو كانت منتهية.\n'
              'لحذف العقار يجب أولًا حذف جميع العقود المرتبطة به من شاشة العقود.',
        ),
      );
      return;
    }
  } catch (_) {
    // لو حصل خطأ في قراءة صندوق العقود لا نكسر الشاشة
  }


    final ok = await showDialog<bool>(
          context: context,
        builder: (_) => AlertDialog(
  backgroundColor: const Color(0xFF0B1220),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  actionsAlignment: MainAxisAlignment.center, // ✅ يوسّط الأزرار
  title: Text('تأكيد الحذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
  content: Text('هل تريد حذف "${p.name}"؟', style: GoogleFonts.cairo(color: Colors.white70)),
  actions: [
    // ✅ "تأكيد" أولاً ليظهر يمينًا في RTL
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
      onPressed: () => Navigator.pop(context, true),
      child: Text('تأكيد', style: GoogleFonts.cairo(color: Colors.white)),
    ),
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.white70)),
    ),
  ],
),

        ) ??
        false;
    if (!ok) return;

    final parentId = p.parentBuildingId;
    await deletePropertyById(p.id);


    // إزالة حالة الأرشفة (مع تتبّع)
    await _clearArchiveState(p);

    // إن كانت وحدة: حدّث إجمالي وحدات العمارة
  

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف "${p.name}"', style: GoogleFonts.cairo()), behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).maybePop();
    }
  }
}

/// ============================================================================
/// إضافة/تعديل عقار (شاشة واحدة تدعم الوضعين)
/// ============================================================================
class AddOrEditPropertyScreen extends StatefulWidget {
  final Property? existing; // null = إضافة

  const AddOrEditPropertyScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AddOrEditPropertyScreen> createState() => _AddOrEditPropertyScreenState();
}

class _AddOrEditPropertyScreenState extends State<AddOrEditPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Bottom nav + drawer ضبط
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  // Controllers
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _units = TextEditingController();
  final _floors = TextEditingController();
  final _rooms = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();

  // المواصفات
  final _baths = TextEditingController();
  final _halls = TextEditingController();
  final _aptFloorNo = TextEditingController();
  bool? _furnished;

  PropertyType? _selectedType;
  RentalMode? _rentalMode;
  String _currency = 'SAR';

  bool get isBuilding => _selectedType == PropertyType.building;
  bool get isPerUnit => isBuilding && _rentalMode == RentalMode.perUnit;

  // يظهر حقل عدد الوحدات للعمارة
  bool get showUnitsField => isBuilding;

  bool get showFloors => _selectedType == PropertyType.building || _selectedType == PropertyType.villa;
  bool get showRooms => _selectedType == PropertyType.apartment || _selectedType == PropertyType.villa;
  bool get requireArea => _selectedType == PropertyType.land;
  bool get showArea => true;

  bool get showBathsHallsFurnished => _selectedType == PropertyType.apartment || _selectedType == PropertyType.villa;
  bool get showApartmentFloorNo => _selectedType == PropertyType.apartment;

  @override
  void initState() {
    super.initState();

    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _address.text = e.address;
      _selectedType = e.type;
      _rentalMode = e.rentalMode;
      _units.text = e.totalUnits > 0 ? e.totalUnits.toString() : '';
      _floors.text = e.floors?.toString() ?? '';
      _rooms.text = e.rooms?.toString() ?? '';
      _area.text = e.area?.toString() ?? '';
      _price.text = e.price?.toString() ?? '';
      _currency = e.currency;
      final spec = _parseSpec(e.description);
      _baths.text = spec['حمامات'] ?? '';
      _halls.text = spec['صالات'] ?? '';
      _aptFloorNo.text = spec['الدور'] ?? '';
      _furnished = spec['المفروشات'] == null ? null : (spec['المفروشات']!.contains('مفروشة') ? true : false);
      _desc.text = _extractFreeDesc(e.description);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _bottomNavKey.currentContext?.size?.height;
      if (h != null && (h - _bottomBarHeight).abs() > 0.5) {
        setState(() => _bottomBarHeight = h);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _units.dispose();
    _floors.dispose();
    _rooms.dispose();
    _area.dispose();
    _price.dispose();
    _desc.dispose();
    _baths.dispose();
    _halls.dispose();
    _aptFloorNo.dispose();
    super.dispose();
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

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

  // ⬇️ بدّل الدالة الموجودة بنفس الاسم بهذه
Widget _field({
  required TextEditingController controller,
  required String label,
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  int maxLines = 1,
  int? maxLength,
  bool enabled = true,
  List<TextInputFormatter>? inputFormatters,
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
    maxLines: maxLines,
    maxLength: maxLength,
    enabled: enabled,
    inputFormatters: fmts,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    // لا نعرض 0/XX
    buildCounter: (ctx, {required int? currentLength, required bool? isFocused, required int? maxLength}) => null,
    style: GoogleFonts.cairo(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      counterText: '', // احتياط لإخفاء 0/XX
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;

    // في وضع التعديل: منع تغيير النوع/نمط التأجير لتجنب التعقيدات
    final canChangeType = !isEdit;
    final canChangeRentalMode = !isEdit;

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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text(isEdit ? 'تعديل عقار' : 'إضافة عقار',
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
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
      // الاسم: مطلوب، حتى 60 حرف (يُمنع تجاوزها + تظهر رسالة "هذا أقصى حد")
      _field(
        controller: _name,
        label: 'اسم العقار ',

        maxLength: 25,
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.isEmpty) return 'هذا الحقل مطلوب';
          return null;
        },
      ),
      SizedBox(height: 12),

      // العنوان: مطلوب، حتى 50 حرف
      _field(
        controller: _address,
        label: 'العنوان ',
        maxLength: 50,
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.isEmpty) return 'هذا الحقل مطلوب';
          return null;
        },
      ),
      SizedBox(height: 12),

      // نوع العقار
      DropdownButtonFormField<PropertyType>(
        value: _selectedType,
        decoration: _dd('نوع العقار'),
        dropdownColor: const Color(0xFF0F172A),
        iconEnabledColor: Colors.white70,
        style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
        items: PropertyType.values
            .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
            .toList(),
        onChanged: canChangeType
            ? (v) => setState(() {
                  _selectedType = v;
                  if (!isBuilding) _rentalMode = null;
                })
            : null,
        validator: (v) => v == null ? 'اختر نوع العقار' : null,
      ),
      SizedBox(height: 12),

      // نمط التأجير (للعمارة فقط)
      if (_selectedType == PropertyType.building) ...[
        Align(
          alignment: Alignment.centerRight,
          child: Text('نمط التأجير', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
        SizedBox(height: 6),
        _rentalChoice(
          value: RentalMode.wholeBuilding,
          group: _rentalMode,
          onChanged: canChangeRentalMode ? (v) => setState(() => _rentalMode = v) : null,
          title: 'تأجير كامل العمارة',
          subtitle: 'عقد واحد يشمل المبنى كاملًا، بدون وحدات داخلية.',
        ),
        SizedBox(height: 8),
        _rentalChoice(
          value: RentalMode.perUnit,
          group: _rentalMode,
          onChanged: canChangeRentalMode ? (v) => setState(() => _rentalMode = v) : null,
          title: 'تأجير الوحدات',
          subtitle: 'إضافة وحدات (شقق/مكاتب) لكل عقد مستقل.',
        ),
        SizedBox(height: 12),
      ],

      // عدد الوحدات (للعمارة): يمنع > 500
      if (showUnitsField) ...[
  _field(
    controller: _units,
    label: isPerUnit
        ? 'عدد الوحدات (مطلوب 1–500)'
        : 'عدد الوحدات (اختياري 1–500)',
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      _maxIntWithFeedback(max: 500, exceedMsg: 'الحد الأقصى للوحدات هو 500'),
    ],
    enabled: !(widget.isEdit && isPerUnit), // ← اغلق الحقل في تعديل + تأجير وحدات
    validator: (v) {
      if (!(widget.isEdit && isPerUnit)) {
        final t = (v ?? '').trim();
        if (isPerUnit && t.isEmpty) return 'عدد الوحدات مطلوب';
        if (t.isEmpty) return null;
        final n = int.tryParse(t);
        if (n == null || n < 1 || n > 500) return 'أدخل عددًا صحيحًا (1–500)';
      }
      return null;
    },
  ),
  SizedBox(height: 12),
],



      // الطوابق: يمنع > 100
      if (showFloors) ...[
  _field(
    controller: _floors,
    label: 'عدد الطوابق (1–100)',
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      _maxIntWithFeedback(max: 100, exceedMsg: 'الحد الأقصى للطوابق هو 100'),
    ],
    validator: (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return null; // اختياري
      final n = int.tryParse(t);
      if (n == null || n < 1 || n > 100) return 'أدخل رقمًا بين 1 و 100';
      return null;
    },
  ),
  SizedBox(height: 12),
],


      // الغرف: يمنع > 20
      if (showRooms) ...[
  _field(
    controller: _rooms,
    label: 'عدد الغرف (اختياري)',
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      _maxIntWithFeedback(max: 20, exceedMsg: 'الحد الأقصى للغرف هو 20'),
    ],
    validator: (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      if (n == null || n < 0 || n > 20) return 'أدخل رقمًا بين 0 و 20';
      return null;
    },
  ),
  SizedBox(height: 12),
],


      // حمامات/صالات: يمنع > 20 و > 10
      if (showBathsHallsFurnished) ...[
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _baths,
                label: 'عدد الحمامات (اختياري)',
                keyboardType: TextInputType.number,
                inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 20, exceedMsg: 'الحد الأقصى هو 20'),
],

              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _field(
                controller: _halls,
                label: 'عدد الصالات (اختياري)',
                keyboardType: TextInputType.number,
                inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 10, exceedMsg: 'الحد الأقصى هو 10'),
],

              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        FormField<bool?>(
  initialValue: _furnished,
  validator: (_) => _furnished == null ? 'هذا الحقل مطلوب' : null,
  builder: (field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('المفروشات:', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
           ChoiceChip(
  label: const Text('مفروشة'),
  selected: _furnished == true,
  onSelected: (_) {
    setState(() => _furnished = true);
    field.didChange(true);
  },
  showCheckmark: false,
  selectedColor: const Color(0xFF059669),            // أخضر عند التحديد
  backgroundColor: const Color(0xFF1F2937),     // ✅ لون افتراضي داكن بدل الأبيض
  labelStyle: GoogleFonts.cairo(
    color: _furnished == true ? Colors.white : Colors.white70,
    fontWeight: FontWeight.w700,
  ),
),
ChoiceChip(
  label: const Text('غير مفروشة'),
  selected: _furnished == false,
  onSelected: (_) {
    setState(() => _furnished = false);
    field.didChange(false);
  },
  showCheckmark: false,
  selectedColor: const Color(0xFF059669),            // أخضر عند التحديد
  backgroundColor: const Color(0xFF1F2937),     // ✅ لون افتراضي داكن بدل الأبيض
  labelStyle: GoogleFonts.cairo(
    color: _furnished == false ? Colors.white : Colors.white70,
    fontWeight: FontWeight.w700,
  ),
),

          ],
        ),
      ),
      if (field.hasError)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(field.errorText!, style: GoogleFonts.cairo(color: Colors.redAccent, fontWeight: FontWeight.w700)),
        ),
    ],
  ),
),
SizedBox(height: 12),

      ],

      // رقم الدور: يمنع > 100
     if (showApartmentFloorNo) ...[
  _field(
    controller: _aptFloorNo,
    label: 'رقم الدور (اختياري)',
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      _maxIntWithFeedback(max: 100, exceedMsg: 'الحد الأقصى لرقم الدور هو 100'),
    ],
  ),
  SizedBox(height: 12),
],


      // المساحة: تمنع > 100000
      if (showArea) ...[
        _field(
          controller: _area,
          label: requireArea ? 'المساحة (اختياري)' : 'المساحة (اختياري)',
          keyboardType: TextInputType.number,
         inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  _maxNumWithFeedback(max: 100000, exceedMsg: 'الحد الأقصى للمساحة هو 100000'),
],

          validator: (v) {
            final t = (v ?? '').trim();
            if (requireArea && t.isEmpty) return 'المساحة مطلوبة للأراضي';
            if (t.isEmpty) return null;
            final n = double.tryParse(t);
            if (n == null || n < 1) return 'أدخل رقمًا بين 1 و 100000';
            return null;
          },
        ),
        SizedBox(height: 12),
      ],

      // السعر: يمنع > 999,999,999
      Row(
        children: [
          Expanded(
            child: _field(
              controller: _price,
              label: 'السعر (اختياري)',
              keyboardType: TextInputType.number,
             inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  _maxNumWithFeedback(max: 999999999, exceedMsg: 'الحد الأقصى للسعر هو 999,999,999'),
],

              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = double.tryParse(t);
                if (n == null || n < 1) return 'أدخل رقمًا بين 1 و 999,999,999';
                return null;
              },
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
  value: _currency,
  decoration: _dd('العملة'),
  dropdownColor: const Color(0xFF0F172A),
  iconEnabledColor: Colors.white70,
  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
  items: const ['SAR']
      .map(
        (c) => DropdownMenuItem<String>(
          value: c,
          child: Text('ريال'),
        ),
      )
      .toList(),
  onChanged: (v) => setState(() => _currency = v ?? 'ريال'),
),

          ),
        ],
      ),
      SizedBox(height: 12),

      // الوصف: حتى 500 حرف (منع + تنبيه)
      _field(
        controller: _desc,
        label: 'الوصف/ملاحظات (اختياري)',
        maxLines: 4,
        maxLength: 500,
      ),
      SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E40AF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  ),
)


              ),
            ),
          ],
        ),

        bottomNavigationBar: AppBottomNav(
          key: _bottomNavKey,
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedType == null) return;

    if (_selectedType == PropertyType.building && _rentalMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اختر نمط التأجير للعمارة', style: GoogleFonts.cairo())),
      );
      return;
    }

    final baths = int.tryParse(_baths.text.trim());
    final halls = int.tryParse(_halls.text.trim());
    final aptFloor = int.tryParse(_aptFloorNo.text.trim());
    final furnished = _furnished;

    // 👈 وقت موحّد لهذي العملية (إضافة/تعديل)
       final now = KsaTime.now();

    final mergedDesc = _buildSpec(
      baths: (_selectedType == PropertyType.apartment || _selectedType == PropertyType.villa) ? baths : null,
      halls: (_selectedType == PropertyType.apartment || _selectedType == PropertyType.villa) ? halls : null,
      floorNo: (_selectedType == PropertyType.apartment) ? aptFloor : null,
      furnished: (_selectedType == PropertyType.apartment || _selectedType == PropertyType.villa) ? furnished : null,
      extraDesc: _desc.text,
    );

    final parsedUnits = int.tryParse(_units.text.trim()) ?? 0;

    if (widget.isEdit && widget.existing != null) {
      final m = widget.existing!;
      if (_hasActiveContract(m)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يمكن تعديل العقار وهو مرتبط بعقد نشط', style: GoogleFonts.cairo())),
        );
        return;
      }
      m.name = _name.text.trim();
      m.address = _address.text.trim();
      m.type = _selectedType!;
      m.rentalMode = _selectedType == PropertyType.building ? _rentalMode : null;
      if (_selectedType == PropertyType.building) {
  if (_rentalMode == RentalMode.perUnit && widget.isEdit) {
    // لا تغيّر عدد الوحدات عند تعديل عمارة بنمط تأجير وحدات
  } else {
    m.totalUnits = parsedUnits;
  }
} else {
  m.totalUnits = 0;
}

            m.area = _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim());
      m.floors = _floors.text.trim().isEmpty ? null : int.tryParse(_floors.text.trim());
      m.rooms = _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim());
      m.price = _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
      m.currency = _currency;
      m.description = mergedDesc;
      m.updatedAt = now; // 👈 آخر تعديل

      final box = Hive.box<Property>(boxName(kPropertiesBox));
      await box.put(m.id, m);
      unawaited(OfflineSyncService.instance.enqueueUpsertProperty(m));


      if (mounted) Navigator.of(context).pop(m);
       } else {
      // نستخدم نفس now الذي عرفناه فوق
      final nowId = now.microsecondsSinceEpoch.toString();

      final p = Property(
        id: nowId, // ⬅️ معرّف مبني على الوقت
        name: _name.text.trim(),
        address: _address.text.trim(),
        type: _selectedType!,
        rentalMode: _selectedType == PropertyType.building ? _rentalMode : null,
        totalUnits: _selectedType == PropertyType.building ? parsedUnits : 0,
        occupiedUnits: 0,
        area: _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim()),
        floors: _floors.text.trim().isEmpty ? null : int.tryParse(_floors.text.trim()),
        rooms: _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim()),
        price: _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim()),
        currency: _currency,
        description: mergedDesc,

        // 👇 هنا الحل الجذري: تخزين تاريخ الإنشاء والتحديث
        createdAt: now,
        updatedAt: now,
      );

      if (mounted) Navigator.of(context).pop(p);
    }


    }
  }

  Widget _rentalChoice({
    required RentalMode value,
    required RentalMode? group,
    required ValueChanged<RentalMode?>? onChanged,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: RadioListTile<RentalMode>(
        value: value,
        groupValue: group,
        onChanged: onChanged,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: Colors.white,
        selectedTileColor: Colors.white.withOpacity(0.08),
        title: Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12.sp, height: 1.4)),
      ),
    );
  }


/// ============================================================================
/// شاشة إضافة وحدات تابعة لعمارة
/// ============================================================================
/// ============================================================================
/// شاشة إضافة وحدات تابعة لعمارة (مع قيود الحقول)
/// ============================================================================
class AddUnitsScreen extends StatefulWidget {
  final Property building;
  final int existingUnitsCount;

  const AddUnitsScreen({super.key, required this.building, this.existingUnitsCount = 0});

  @override
  State<AddUnitsScreen> createState() => _AddUnitsScreenState();
}

class _AddUnitsScreenState extends State<AddUnitsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Bottom nav + drawer ضبط
  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  // تفاصيل الوحدة
  final _baseName = TextEditingController(text: 'شقة');

  // الحقول بقيود:
  final _rooms = TextEditingController();      // 0..20 (اختياري)
  final _baths = TextEditingController();      // 0..20 (اختياري)
  final _halls = TextEditingController();      // 0..10 (اختياري)
  final _aptFloorNo = TextEditingController(); // 0..100 (اختياري)
  final _area = TextEditingController();       // 1..100000 (اختياري)
  final _price = TextEditingController();      // 1..999,999,999 (اختياري)
  final _desc = TextEditingController();       // حتى 500 حرف

  bool? _furnished;
  String _currency = 'SAR';

  bool _bulk = false;

  final _bulkCount = TextEditingController();

  int _remaining() {
    final total = widget.building.totalUnits;
    final existing = widget.existingUnitsCount;
    if (total <= 0) return 0;
    final r = total - existing;
    return r < 0 ? 0 : r;
  }

@override
void initState() {
  super.initState();
  () async { await _openArchivedBox(); }();
  _bulkCount.text = '1'; // العدد = 1 افتراضيًا عندما الإضافة ليست جماعية
}


  @override
  void dispose() {
    _baseName.dispose();
    _rooms.dispose();
    _baths.dispose();
    _halls.dispose();
    _aptFloorNo.dispose();
    _area.dispose();
    _price.dispose();
    _desc.dispose();
    _bulkCount.dispose();
    super.dispose();
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

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
  TextEditingController? controller,
  required String label,
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  int maxLines = 1,
  int? maxLength,
  List<TextInputFormatter>? inputFormatters,
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
    maxLines: maxLines,
    maxLength: maxLength,
    inputFormatters: fmts,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    buildCounter: (ctx, {required int? currentLength, required bool? isFocused, required int? maxLength}) => null,
    style: GoogleFonts.cairo(color: Colors.white),
    decoration: InputDecoration(
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
      counterText: '',
    ),
  );
}



  @override
  Widget build(BuildContext context) {
    final b = widget.building;
    final remaining = _remaining();

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
          leading: const AppMenuButton(iconColor: Colors.white),
          title: Text('إضافة وحدات', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w800)),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('العمارة: ${b.name}', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(height: 10.h),

                      SwitchListTile(
                        value: _bulk,
                        onChanged: (v) => setState(() {
  _bulk = v;
  if (!v) _bulkCount.text = '1'; // إذا ألغيت الإضافة الجماعية يرجّع 1 ويثبّته
}),

                        title: Text('إضافة كل الوحدات بنفس التفاصيل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          _bulk ? 'سيتم إنشاء عدة شقق متتالية بنفس المواصفات.' : 'ستتم إضافة شقة واحدة فقط بهذه المواصفات.',
                          style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12.sp),
                        ),
                        activeColor: const Color(0xFF22C55E),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SizedBox(height: 8.h),

                  // اسم الوحدة — سطر مستقل
_field(
  controller: _baseName,
  label: 'اسم الوحدة الأساسي ',
  maxLength: 25,
  validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
),
SizedBox(height: 12.h),

// عدد الوحدات — سطر مستقل تحت الاسم
TextFormField(
  controller: _bulkCount,
  enabled: _bulk, // ✅ يتفعّل فقط عند تفعيل الإضافة الجماعية

  keyboardType: TextInputType.number,
  autovalidateMode: AutovalidateMode.onUserInteraction,
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  style: GoogleFonts.cairo(color: Colors.white),
  decoration: InputDecoration(
    labelText: 'عدد الوحدات',
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
  ),
  validator: (v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'هذا الحقل مطلوب';
    final rem = remaining; // دالة remaining موجودة فوق
    if (widget.building.totalUnits > 0 && n > rem) {
      return 'يوجد $rem وحدات فقط';
    }
    return null;
  },
  onChanged: (v) {
    final n = int.tryParse(v);
    final rem = remaining;
    if (widget.building.totalUnits > 0 && n != null && n > rem) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يوجد $rem وحدات فقط', style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  },
),
SizedBox(height: 12.h),


                      // الغرف: 0–20 (اختياري)
                      _field(
                        controller: _rooms,
                        label: 'عدد الغرف (اختياري)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 20, exceedMsg: 'الحد الأقصى هو 20'),
],

                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          if (n == null || n < 0) return 'أدخل رقمًا بين 0 و 20';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // حمامات/صالات: 0–20 و 0–10 (اختياري)
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _baths,
                              label: 'عدد الحمامات (اختياري)',
                              keyboardType: TextInputType.number,
                             inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 20, exceedMsg: 'الحد الأقصى هو 20'),
],

                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 0) return 'أدخل رقمًا بين 0 و 20';
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: _field(
                              controller: _halls,
                              label: 'عدد الصالات (اختياري) ',
                              keyboardType: TextInputType.number,
                             inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 10, exceedMsg: 'الحد الأقصى هو 10'),
],

                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                if (n == null || n < 0) return 'أدخل رقمًا بين 0 و 10';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // رقم الدور: 0–100 (اختياري)
                      _field(
                        controller: _aptFloorNo,
                        label: 'رقم الدور (اختياري)',
                        keyboardType: TextInputType.number,
                       inputFormatters: [
  FilteringTextInputFormatter.digitsOnly,
  _maxIntWithFeedback(max: 100, exceedMsg: 'الحد الأقصى هو 100'),
],

                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          if (n == null || n < 0) return 'أدخل رقمًا بين 0 و 100';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // حالة المفروشات
                     FormField<bool?>(
  initialValue: _furnished,
  validator: (_) => _furnished == null ? 'هذا الحقل مطلوب' : null,
  builder: (field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('المفروشات:', style: GoogleFonts.cairo(color: Colors.white70, fontWeight: FontWeight.w700)),
           ChoiceChip(
  label: const Text('مفروشة'),
  selected: _furnished == true,
  onSelected: (_) {
    setState(() => _furnished = true);
    field.didChange(true);
  },
  showCheckmark: false,
  selectedColor: const Color(0xFF059669),            // أخضر عند التحديد
  backgroundColor: const Color(0xFF1F2937),     // ✅ لون افتراضي داكن بدل الأبيض
  labelStyle: GoogleFonts.cairo(
    color: _furnished == true ? Colors.white : Colors.white70,
    fontWeight: FontWeight.w700,
  ),
),
ChoiceChip(
  label: const Text('غير مفروشة'),
  selected: _furnished == false,
  onSelected: (_) {
    setState(() => _furnished = false);
    field.didChange(false);
  },
  showCheckmark: false,
  selectedColor: const Color(0xFF059669),            // أخضر عند التحديد
  backgroundColor: const Color(0xFF1F2937),     // ✅ لون افتراضي داكن بدل الأبيض
  labelStyle: GoogleFonts.cairo(
    color: _furnished == false ? Colors.white : Colors.white70,
    fontWeight: FontWeight.w700,
  ),
),

          ],
        ),
      ),
      if (field.hasError)
        Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(field.errorText!, style: GoogleFonts.cairo(color: Colors.redAccent, fontWeight: FontWeight.w700)),
        ),
    ],
  ),
),
SizedBox(height: 12.h),

                      // المساحة: 1–100000 (اختياري، عشري)
                      _field(
                        controller: _area,
                        label: 'المساحة (اختياري)',
                        keyboardType: TextInputType.number,
                       inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  _maxNumWithFeedback(max: 100000, exceedMsg: 'الحد الأقصى للمساحة هو 100000'),
],

                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = double.tryParse(t);
                          if (n == null || n < 1) return 'أدخل رقمًا بين 1 و 100000';
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),

                      // السعر + العملة: السعر 1–999,999,999 (اختياري، عشري)
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _price,
                              label: 'السعر (اختياري)',
                              keyboardType: TextInputType.number,
                             inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  _maxNumWithFeedback(max: 999999999, exceedMsg: 'الحد الأقصى للسعر هو 999,999,999'),
],

                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = double.tryParse(t);
                                if (n == null || n < 1) return 'أدخل رقمًا بين 1 و 999,999,999';
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: DropdownButtonFormField<String>(
  value: _currency,
  decoration: _dd('العملة'),
  dropdownColor: const Color(0xFF0F172A),
  iconEnabledColor: Colors.white70,
  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700),
  items: const ['SAR']
      .map(
        (c) => DropdownMenuItem<String>(
          value: c,
          child: Text('ريال'),
        ),
      )
      .toList(),
  onChanged: (v) => setState(() => _currency = v ?? 'ريال'),
),

                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),

                      // الوصف: حتى 500 حرف مع تنبيه أقصى حد
                      _field(
                        controller: _desc,
                        label: 'الوصف/ملاحظات (اختياري)',
                        maxLines: 3,
                        maxLength: 500,
                      ),
                      SizedBox(height: 16.h),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0EA5E9),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                          ),
                          onPressed: _saveUnits,
                          icon: const Icon(Icons.save_rounded),
                          label: Text('حفظ الوحدات', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
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
          currentIndex: 1,
          onTap: _handleBottomTap,
        ),
      ),
    );
  }

void _saveUnits() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tsBase = KsaTime.now().microsecondsSinceEpoch; // بذرة زمنية واحدة لكل الدفعة
    final unitBaseName = _baseName.text.trim().isEmpty ? 'وحدة' : _baseName.text.trim();
    final count = _bulk ? int.parse(_bulkCount.text.trim()) : 1; // كم وحدة هننشئ؟

    final createdAt = KsaTime.now(); // 👈 وقت إنشاء هذه الوحدات



    final rooms = _rooms.text.trim().isEmpty ? null : int.tryParse(_rooms.text.trim());
    final baths = _baths.text.trim().isEmpty ? null : int.tryParse(_baths.text.trim());
    final halls = _halls.text.trim().isEmpty ? null : int.tryParse(_halls.text.trim());
    final aptFloor = _aptFloorNo.text.trim().isEmpty ? null : int.tryParse(_aptFloorNo.text.trim());
    final furnished = _furnished;

    final area = _area.text.trim().isEmpty ? null : double.tryParse(_area.text.trim());
    final price = _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
    final descFree = _desc.text.trim().isEmpty ? null : _desc.text.trim();

    final specDesc = _buildSpec(
      baths: baths,
      halls: halls,
      floorNo: aptFloor,
      furnished: furnished,
      extraDesc: descFree,
    );

    final startIndex = widget.existingUnitsCount + 1;
    final List<Property> created = [];
      

    final remaining = _remaining();
    if (_bulk && widget.building.totalUnits > 0) {
      final requested = int.tryParse(_bulkCount.text.trim()) ?? 0;
      if (requested <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('أدخل عدد وحدات صحيح', style: GoogleFonts.cairo())),
        );
        return;
      }
      if (requested > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يمكن إضافة أكثر من $remaining وحدة', style: GoogleFonts.cairo())),
        );
        return;
      }
    }

        if (_bulk) {
      final count = int.tryParse(_bulkCount.text.trim()) ?? 0;
      for (int i = 0; i < count; i++) {
        created.add(
          Property(
            name: '$unitBaseName ${startIndex + i}',
            type: PropertyType.apartment,
            address: widget.building.address,
            rooms: rooms,
            area: area,
            price: price,
            currency: _currency,
            rentalMode: null,
            totalUnits: 0,
            occupiedUnits: 0,
            parentBuildingId: widget.building.id,
            description: specDesc,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
      }
    } else {
      created.add(
        Property(
          name: unitBaseName,
          type: PropertyType.apartment,
          address: widget.building.address,
          rooms: rooms,
          area: area,
          price: price,
          currency: _currency,
          rentalMode: null,
          totalUnits: 0,
          occupiedUnits: 0,
          parentBuildingId: widget.building.id,
          description: specDesc,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
    }


    Navigator.of(context).pop(created);
  }
}

/// ============================================================================
/// عناصر تصميم غامقة مشتركة
/// ============================================================================
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }
}

// امتداد صغير للـ Iterable لتفادي الأخطاء عند عدم وجود عنصر
extension on Iterable<Property?> {
  Property? get firstOrNull => isEmpty ? null : first;
}
