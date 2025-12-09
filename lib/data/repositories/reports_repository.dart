// lib/data/repositories/reports_repository.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show Listenable;
import 'package:hive_flutter/hive_flutter.dart';

import '../services/hive_service.dart';
import '../mappers/status_mapper.dart';
import '../models/reports_summary.dart';
import '../../ui/invoices_screen.dart' show kInvoicesBox; // ← مهم لإيجاد اسم صندوق الفواتير

class ReportsRepository {
  /// افتح الصناديق الضرورية للتقارير
  static Future<void> ensureReady() => HiveService.ensureReportsBoxesOpen();

  /// Listenable مدموج لإعادة بناء الواجهة عند أي تغيّر
  static Listenable mergedListenable() => HiveService.mergedReportsListenable();

  /// فلتر الفترة (اختياري)
  final DateTime? from;
  final DateTime? to;
  final bool includeArchived;

  ReportsRepository({this.from, this.to, this.includeArchived = false});

  bool get hasDate => from != null || to != null;

  bool inRange(DateTime? d) {
    if (d == null) return true;
    if (from != null && d.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
    if (to != null && d.isAfter(DateTime(to!.year, to!.month, to!.day, 23, 59, 59, 999))) return false;
    return true;
  }

  ReportsSummary getSummary() {
    // استخدم ثوابت الصناديق من HiveService
    final propsBox = HiveService.boxIfOpen(kPropertiesBox);
    final tenBox   = HiveService.boxIfOpen(kTenantsBox);
    final ctrBox   = HiveService.boxIfOpen(kContractsBox);
    final invBox   = HiveService.boxIfOpen(kInvoicesBox); // ← بعد استيرادها بالأعلى
    final mBox     = HiveService.boxIfOpen(kMaintenanceBox);

    final props     = propsBox?.values.toList(growable: false) ?? const [];
    final tenants   = tenBox?.values.toList(growable: false) ?? const [];
    final contracts = ctrBox?.values.toList(growable: false) ?? const [];
    final invoices  = invBox?.values.toList(growable: false) ?? const [];
    final maints    = mBox?.values.toList(growable: false) ?? const [];

    // --- Properties (occupied/vacant) ---
    int occupiedUnits = 0, totalUnits = 0;
    for (final p in props) {
      final isOcc    = _asBool(_read(p, const ['isOccupied'])) ?? false;
      final units    = _asInt(_read(p, const ['totalUnits'])) ?? 1;
      final occUnits = _asInt(_read(p, const ['occupiedUnits'])) ?? (isOcc ? units : 0);
      totalUnits    += math.max(units, 1);
      occupiedUnits += math.max(occUnits, 0);
    }
    final vacantUnits = (totalUnits - occupiedUnits).clamp(0, totalUnits);

    // --- Contracts (active/near/ended) ---
    int active = 0, near = 0, ended = 0;
    final today = DateTime.now();
    final dToday = DateTime(today.year, today.month, today.day);
    final nearThreshold = dToday.add(const Duration(days: 30));

    for (final c in contracts) {
      if (!includeArchived && StatusMapper.contractIsArchived(c)) continue;

      final start = StatusMapper.contractStart(c);
      final end   = StatusMapper.contractEnd(c);
      final term  = StatusMapper.contractIsTerminated(c);

      final isActive = _contractIsActive(start, end, term);
      if (isActive) {
        active++;
        if (end != null) {
          final dEnd = DateTime(end.year, end.month, end.day);
          if (!dEnd.isBefore(dToday) && !dEnd.isAfter(nearThreshold)) near++;
        }
      } else {
        ended++;
      }
    }

    // --- Tenants (bound/unbound) ---
    int bound = 0, unbound = 0;
    for (final t in tenants) {
      final hasActive =
          (_asBool(_read(t, const ['hasActiveContract'])) ?? false) ||
          ((_asInt(_read(t, const ['contractsCount'])) ?? 0) > 0) ||
          (_read(t, const ['contractId', 'activeContractId', 'contract']) != null);
      if (hasActive) bound++; else unbound++;
    }

    // --- Invoices (split + finance) ---
    int invTotal = 0, invFromCtr = 0, invFromMaint = 0;
    double revenue = 0, receivables = 0, expenses = 0;

    for (final inv in invoices) {
      if (!includeArchived && StatusMapper.invoiceIsArchived(inv)) continue;
      invTotal++;

      final hasCtr   = StatusMapper.invoiceLinkedToContract(inv);
      final hasMaint = StatusMapper.invoiceLinkedToMaintenance(inv);
      if (hasCtr && !hasMaint) { invFromCtr++; }
      else if (hasMaint && !hasCtr) { invFromMaint++; }

      final amount    = StatusMapper.invoiceAmount(inv).abs();
      final paidAt    = StatusMapper.invoicePaidAt(inv);
      final dueOn     = StatusMapper.invoiceDueOn(inv);
      final isExpense = StatusMapper.invoiceIsExpense(inv);
      final isPaid    = paidAt != null;

      if (isPaid && !isExpense) {
        if (!hasDate || inRange(paidAt)) revenue += amount;
      }
      if (isPaid && isExpense) {
        if (!hasDate || inRange(paidAt)) expenses += amount;
      }
      if (!isPaid) {
        if (!hasDate) {
          receivables += amount;
        } else {
          final anchor = dueOn ?? DateTime.now();
          if (inRange(anchor)) receivables += amount;
        }
      }
    }
    final net = revenue - expenses;

    // --- Maintenance (status split) ---
    int mNew = 0, mProg = 0, mDone = 0;
    for (final m in maints) {
      if (!includeArchived && StatusMapper.maintenanceIsArchived(m)) continue;
      switch (StatusMapper.maintenanceStage(m)) {
        case 'new': mNew++; break;
        case 'progress': mProg++; break;
        case 'done': mDone++; break;
      }
    }
    final mTotal = mNew + mProg + mDone;

    return ReportsSummary(
      propertiesCount: props.length,
      tenantsCount: tenants.length,
      contractsTotal: contracts.length,
      invoicesTotal: invTotal,
      maintenanceTotal: mTotal,
      propertyUnitsOccupied: occupiedUnits,
      propertyUnitsVacant: vacantUnits,
      tenantsBound: bound,
      tenantsUnbound: unbound,
      activeContracts: active,
      nearExpiryContracts: near,
      endedContracts: ended,
      invoicesFromContracts: invFromCtr,
      invoicesFromMaintenance: invFromMaint,
      maintenanceNew: mNew,
      maintenanceInProgress: mProg,
      maintenanceDone: mDone,
      financeRevenue: revenue,
      financeReceivables: receivables,
      financeExpenses: expenses,
      financeNet: net,
    );
  }

  // ---------- helpers ----------
  static bool _contractIsActive(DateTime? start, DateTime? end, bool terminated) {
    if (terminated) return false;
    final now = DateTime.now();
    final s = start ?? DateTime(2000);
    final e = end ?? DateTime(2200);
    final dNow = DateTime(now.year, now.month, now.day);
    final dS = DateTime(s.year, s.month, s.day);
    final dE = DateTime(e.year, e.month, e.day);
    return (dNow.isAtSameMomentAs(dS) || dNow.isAfter(dS)) &&
           (dNow.isAtSameMomentAs(dE) || dNow.isBefore(dE));
  }

  static dynamic _read(Object? o, List<String> names) {
    if (o == null) return null;
    if (o is Map) { for (final n in names) { if (o.containsKey(n)) return o[n]; } }
    for (final n in names) {
      try { final v = (o as dynamic).toJson?.call()[n]; if (v != null) return v; } catch (_) {}
      try { final v = (o as dynamic).noSuchMethod(Invocation.getter(Symbol(n))); if (v != null) return v; } catch (_) {}
      try { final v = (o as dynamic).map?[n]; if (v != null) return v; } catch (_) {}
      try { final v = (o as dynamic).get?.call(n); if (v != null) return v; } catch (_) {}
    }
    return null;
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static bool? _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return ['1','true','yes','y','نعم'].contains(v.toLowerCase());
    return null;
  }
}
