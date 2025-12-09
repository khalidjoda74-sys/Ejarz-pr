// lib/core/time_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ksa_time.dart';

/// غلاف بسيط ليتوافق مع الكود القديم الذي يستورد TimeService
class TimeService {
  TimeService._();
  static final instance = TimeService._();

  // ===== مزامنة وقت الخادم =====
  Future<void> ensureSynced({bool force = false}) => KsaTime.ensureSynced(force: force);
  bool get isSynced => KsaTime.isSynced;

  // ===== الآن/التحويلات =====
  DateTime nowUtc() => KsaTime.nowUtc();
  DateTime nowKsa() => KsaTime.nowKsa();
  DateTime toKsa(DateTime any) => KsaTime.toKsa(any);
  DateTime fromKsaToUtc(DateTime ksa) => KsaTime.fromKsaToUtc(ksa);

  // ===== بداية/نهاية اليوم KSA كممثلة بـ UTC =====
  DateTime ksaStartOfDayUtc([DateTime? baseUtc]) => KsaTime.ksaStartOfDayUtc(baseUtc);
  DateTime ksaEndOfDayUtc([DateTime? baseUtc]) => KsaTime.ksaEndOfDayUtc(baseUtc);

  // ===== اشتراكات شهرية (تاريخ-فقط KSA) =====
  /// إضافة أشهر على تاريخ-فقط KSA (ممثّل كـ UTC) وإرجاع "اليوم الأخير المشمول" (كـ UTC).
  DateTime addMonthsKsaDateOnly(DateTime startKsaDateOnlyUtc, int months) =>
      KsaTime.addMonthsKsaDateOnlyUtc(startKsaDateOnlyUtc, months);

  /// من اليوم الأخير المشمول إلى نهاية حصرية (endExclusive = +1 يوم).
  DateTime endExclusiveFromInclusive(DateTime endInclusiveDateOnlyUtc) =>
      KsaTime.endExclusiveUtcFromInclusiveDateOnlyUtc(endInclusiveDateOnlyUtc);

  /// اختصار شائع: من بداية اليوم + عدد الأشهر ← نهاية حصرية.
  DateTime endExclusiveFromStartAndMonthsKsa(DateTime startKsaDateOnlyUtc, int months) {
    final endInc = addMonthsKsaDateOnly(startKsaDateOnlyUtc, months);
    return endExclusiveFromInclusive(endInc);
  }

  // ===== تنسيقات =====
  String formatKsa(DateTime any, {String pattern = 'yyyy/MM/dd'}) =>
      KsaTime.formatKsa(any, pattern: pattern);

  // ===== أدوات =====
  DateTime? parseToUtc(dynamic v) => KsaTime.parseToUtc(v);
}
