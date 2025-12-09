// lib/data/services/hive_service.dart
import 'package:flutter/foundation.dart' show Listenable, ValueNotifier;
import 'package:hive_flutter/hive_flutter.dart';

// نماذج Typed ضرورية لفتح الصناديق بنوع صحيح
import '../../models/tenant.dart';
import '../../models/property.dart';
import '../../ui/invoices_screen.dart' show Invoice; // إبقاء النوع فقط

// ثوابت أسماء الصناديق (مجمّعة في ملف واحد)
import '../constants/boxes.dart';

// في مشروعك، تعريفات نماذج العقود/الصيانة والـ Adapters داخل شاشاتهم
import '../../ui/contracts_screen.dart' show Contract, ContractAdapter;
import '../../ui/maintenance_screen.dart'
    show MaintenanceRequest,
         MaintenanceRequestAdapter,
         MaintenancePriorityAdapter,
         MaintenanceStatusAdapter;

// ⚠️ مهم: أدوات نطاق المستخدم (uid → boxName)
import 'user_scope.dart';

/// بدائل شائعة للأسماء (لتغطية اختلافات قديمة/ملفات أخرى) — قواعد (base names)
const List<String> kContractsAliases   = [kContractsBox, 'contracts', 'contracts_box'];
const List<String> kMaintenanceAliases = [kMaintenanceBox, 'maintenance', 'maintenance_box'];

/// حوِّل قائمة أسماء قاعدية إلى أسماء خاصّة بالمستخدم الحالي عبر boxName(...)
List<String> _aliasedNamesForUser(List<String> bases) =>
    bases.map((n) => boxName(n)).toList();

class HiveService {
  /// تسجيل الـAdapters اللازمة مرة واحدة (محمي من التكرار)
  static void _registerAdaptersIfNeeded() {
    // عقود
    final contractAdapter = ContractAdapter();
    if (!Hive.isAdapterRegistered(contractAdapter.typeId)) {
      Hive.registerAdapter(contractAdapter);
    }

    // صيانة: الأولوية + الحالة + الطلب نفسه
    final priorityAdapter = MaintenancePriorityAdapter();
    if (!Hive.isAdapterRegistered(priorityAdapter.typeId)) {
      Hive.registerAdapter(priorityAdapter);
    }
    final statusAdapter = MaintenanceStatusAdapter();
    if (!Hive.isAdapterRegistered(statusAdapter.typeId)) {
      Hive.registerAdapter(statusAdapter);
    }
    final maintenanceAdapter = MaintenanceRequestAdapter();
    if (!Hive.isAdapterRegistered(maintenanceAdapter.typeId)) {
      Hive.registerAdapter(maintenanceAdapter);
    }
  }

  /// ✅ إجبار فتح الصندوق بنوع Typed؛
  /// لو كان مفتوحًا كـ dynamic يتم إغلاقه ثم فتحه Typed.
  static Future<void> _ensureBoxTyped<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      try {
        // لو هذا يرمي استثناء فالصندوق مفتوح كـ dynamic
        Hive.box<T>(name);
      } catch (_) {
        await Hive.box(name).close();
      }
    }
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<T>(name);
    } else {
      // تأكيد Typed (سيرمي لو لا يزال غير Typed لسبب ما)
      Hive.box<T>(name);
    }
  }

  /// ✅ افتح أول اسم من قائمة الأسماء (مع aliases) كـ Typed فقط.
  /// إن وُجد مفتوحًا لكن ليس Typed نغلقه ونفتحه Typed.
  static Future<String?> _ensureOneOfOpenTypedFirst<T>(List<String> names) async {
    // 1) إن كان هناك صندوق مفتوح وقابل للقراءة Typed → استخدمه
    for (final name in names) {
      if (Hive.isBoxOpen(name)) {
        try {
          Hive.box<T>(name);
          return name; // مفتوح Typed
        } catch (_) {
          // مفتوح dynamic: سنعالجه لاحقًا بإعادة الفتح Typed
        }
      }
    }

    // 2) جرّب فتح/إعادة فتح Typed للأسماء حسب الترتيب
    for (final name in names) {
      try {
        await _ensureBoxTyped<T>(name);
        // إن نجح أعلاه دون استثناء، فهو Typed
        return name;
      } catch (_) {
        // جرّب الاسم التالي
      }
    }

    // لم نتمكن من فتح أي منها Typed
    return null;
  }

  /// اسم الصندوق الفعلي المستخدم للعقود (قد يكون alias) — بعد تطبيق boxName
  static String? _contractsBoxNameInUse;

  /// اسم الصندوق الفعلي المستخدم للصيانة (قد يكون alias) — بعد تطبيق boxName
  static String? _maintenanceBoxNameInUse;

  /// (جديد) ترحيل محتوى صندوق العقود من اسم بديل إلى الاسم القياسي لهذا المستخدم
  static Future<void> _migrateContractsIfNeeded({
    required String fromName,
    required String toName,
  }) async {
    if (fromName == toName) return;

    try {
      // تأكد أن المصدر والهدف Typed
      await _ensureBoxTyped<Contract>(fromName);
      await _ensureBoxTyped<Contract>(toName);

      final Box src = Hive.box(fromName);                   // قد يحتوي عناصر غير متوافقة
      final Box<Contract> dst = Hive.box<Contract>(toName); // الهدف Typed

      // دمج بدون الكتابة فوق مفاتيح موجودة
      for (final key in src.keys) {
        try {
          if (dst.containsKey(key)) continue;
          final v = src.get(key);
          if (v is Contract) {
            await dst.put(key, v);
          }
        } catch (_) {
          // تجاهل عنصر فاسد/غير متوافق
        }
      }

      _contractsBoxNameInUse = toName;
    } catch (_) {
      // الترحيل اختياري لتحسين التوافق
    }
  }

  /// (جديد) ترحيل محتوى صندوق الصيانة من اسم بديل إلى الاسم القياسي لهذا المستخدم
  static Future<void> _migrateMaintenanceIfNeeded({
    required String fromName,
    required String toName,
  }) async {
    if (fromName == toName) return;

    try {
      await _ensureBoxTyped<MaintenanceRequest>(fromName);
      await _ensureBoxTyped<MaintenanceRequest>(toName);

      final Box src = Hive.box(fromName);                                   // قد يحتوي عناصر غير متوافقة
      final Box<MaintenanceRequest> dst = Hive.box<MaintenanceRequest>(toName); // الهدف Typed

      for (final key in src.keys) {
        try {
          if (dst.containsKey(key)) continue;
          final v = src.get(key);
          if (v is MaintenanceRequest) {
            await dst.put(key, v);
          }
        } catch (_) {
          // تجاهل عنصر فاسد/غير متوافق
        }
      }

      _maintenanceBoxNameInUse = toName;
    } catch (_) {
      // الترحيل اختياري
    }
  }

  /// افتح صناديق تُستخدم بالتقارير فقط (Typed حصراً وبذكاء مع الأسماء البديلة) — *لكل مستخدم*
  static Future<void> ensureReportsBoxesOpen() async {
    _registerAdaptersIfNeeded();

    // افتح صناديق هذا المستخدم (per-uid) Typed دائمًا
    await _ensureBoxTyped<Tenant>(boxName(kTenantsBox));
    await _ensureBoxTyped<Property>(boxName(kPropertiesBox));
    await _ensureBoxTyped<Invoice>(boxName(kInvoicesBox));

    // العقود: ابحث عن الصندوق الفعلي بين الأسماء البديلة ولكن *لمستخدمك* (Typed فقط)
    _contractsBoxNameInUse ??=
        await _ensureOneOfOpenTypedFirst<Contract>(_aliasedNamesForUser(kContractsAliases));

    // ✅ ترحيل العقود إلى الاسم القياسي لهذا المستخدم إن لزم
    final canonicalContracts = boxName(kContractsBox);
    if (_contractsBoxNameInUse != null) {
      await _migrateContractsIfNeeded(
        fromName: _contractsBoxNameInUse!,
        toName: canonicalContracts,
      );
      _contractsBoxNameInUse = canonicalContracts;
    } else {
      // لو لم نجد أي صندوق بديل أصلاً، افتح القياسي Typed مباشرة
      await _ensureBoxTyped<Contract>(canonicalContracts);
      _contractsBoxNameInUse = canonicalContracts;
    }

    // الصيانة: نفس المبدأ + (✅ ترحيل)
    _maintenanceBoxNameInUse ??=
        await _ensureOneOfOpenTypedFirst<MaintenanceRequest>(_aliasedNamesForUser(kMaintenanceAliases));

    final canonicalMaintenance = boxName(kMaintenanceBox);
    if (_maintenanceBoxNameInUse != null) {
      await _migrateMaintenanceIfNeeded(
        fromName: _maintenanceBoxNameInUse!,
        toName: canonicalMaintenance,
      );
      _maintenanceBoxNameInUse = canonicalMaintenance;
    } else {
      await _ensureBoxTyped<MaintenanceRequest>(canonicalMaintenance);
      _maintenanceBoxNameInUse = canonicalMaintenance;
    }

    // sessionBox dynamic (إعدادات/جلسة) لهذا المستخدم — إبقِه dynamic
    if (!Hive.isBoxOpen(boxName(kSessionBox))) {
      try { await Hive.openBox(boxName(kSessionBox)); } catch (_) {}
    }
  }

  /// حاول إرجاع صندوق Typed؛ وإن لم يكن Typed أو لم يُفتح، أعد null
  static Box<T>? typedBoxIfOpen<T>(String name) {
    if (!Hive.isBoxOpen(name)) return null;
    try { return Hive.box<T>(name); } catch (_) { return null; }
  }

  /// صندوق dynamic إن كان مفتوحًا
  static Box? boxIfOpen(String name) {
    if (!Hive.isBoxOpen(name)) return null;
    try { return Hive.box(name); } catch (_) { return null; }
  }

  /// احصل على Listenables لعقود (يشمل جميع الأسماء البديلة المفتوحة — لأسماء المستخدم)
  static List<Listenable> _contractsListenables() {
    final List<Listenable> list = [];
    for (final name in _aliasedNamesForUser(kContractsAliases)) {
      // فضّل Typed إن وُجد
      final typed = typedBoxIfOpen<Contract>(name)?.listenable();
      if (typed != null) { list.add(typed); continue; }
      final dyn = boxIfOpen(name)?.listenable();
      if (dyn != null) list.add(dyn);
    }
    return list.isEmpty ? [ValueNotifier<bool>(false)] : list;
  }

  /// احصل على Listenables لصيانة (يشمل جميع الأسماء البديلة المفتوحة — لأسماء المستخدم)
  static List<Listenable> _maintenanceListenables() {
    final List<Listenable> list = [];
    for (final name in _aliasedNamesForUser(kMaintenanceAliases)) {
      final typed = typedBoxIfOpen<MaintenanceRequest>(name)?.listenable();
      if (typed != null) { list.add(typed); continue; }
      final dyn = boxIfOpen(name)?.listenable();
      if (dyn != null) list.add(dyn);
    }
    return list.isEmpty ? [ValueNotifier<bool>(false)] : list;
  }

  /// Listenable مدموج لتحديث شاشة التقارير عند أي تغيّر في الصناديق المعنية — *خاصة بالمستخدم*
  static Listenable mergedReportsListenable() {
    final Listenable t = (typedBoxIfOpen<Tenant>(boxName(kTenantsBox))?.listenable()      as Listenable?) ?? ValueNotifier<bool>(false);
    final Listenable p = (typedBoxIfOpen<Property>(boxName(kPropertiesBox))?.listenable() as Listenable?) ?? ValueNotifier<bool>(false);
    final Listenable i = (typedBoxIfOpen<Invoice>(boxName(kInvoicesBox))?.listenable()    as Listenable?) ?? ValueNotifier<bool>(false);
    final Listenable s = (boxIfOpen(boxName(kSessionBox))?.listenable()                   as Listenable?) ?? ValueNotifier<bool>(false);

    // عقود + صيانة (يشمل البدائل)
    final contractsListens   = _contractsListenables();
    final maintenanceListens = _maintenanceListenables();

    return Listenable.merge(<Listenable>[
      t, p, i, s,
      ...contractsListens,
      ...maintenanceListens,
    ]);
  }

  /// API مساعد: اسم صندوق العقود الفعلي الذي تم فتحه (خاص بالمستخدم)
  static String contractsBoxName() => _contractsBoxNameInUse ?? boxName(kContractsBox);

  /// API مساعد: اسم صندوق الصيانة الفعلي الذي تم فتحه (خاص بالمستخدم)
  static String maintenanceBoxName() => _maintenanceBoxNameInUse ?? boxName(kMaintenanceBox);
}
