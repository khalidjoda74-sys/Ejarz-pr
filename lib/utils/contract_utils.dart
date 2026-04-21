import 'package:darvoo/utils/ksa_time.dart';
import '../ui/contracts_screen.dart' show Contract, ContractTerm, PaymentCycle;
import '../ui/invoices_screen.dart' show Invoice;
import '../data/constants/boxes.dart';
import 'package:hive/hive.dart';
import '../data/services/user_scope.dart'; // يوفر الدالة boxName
// يوفر الثابت kInvoicesBox
import '../data/services/hive_service.dart' as hs;

DateTime _dateOnly(DateTime d) => KsaTime.dateOnly(d);

/// هل هناك فاتورة مدفوعة بالكامل لهذا الاستحقاق؟
bool _paidForDue(Contract c, DateTime due) {
  try {
    if (!Hive.isBoxOpen(boxName(kInvoicesBox))) return false;
    final box = Hive.box<Invoice>(boxName(kInvoicesBox));
    final dOnly = _dateOnly(due);

    for (final inv in box.values) {
      if (inv.contractId == c.id &&
          !(inv.isCanceled == true) &&
          (inv.paidAmount >= (inv.amount - 0.000001)) &&
          _dateOnly(inv.dueDate) == dOnly) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}

int countOverduePayments(Contract c) {
  if (c.term == ContractTerm.daily) return 0;

  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  int count = 0;

  // المعدَّل: الحلقة تقف قبل نهاية العقد (لا تعد endDate نفسه)
  while (cursor.isBefore(end)) {
    if (!_paidForDue(c, cursor) && cursor.isBefore(today)) {
      count++;
    }
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }

  return count;
}

int countDueTodayPayments(Contract c) {
  if (c.term == ContractTerm.daily) return 0;
  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  int count = 0;

  while (!cursor.isAfter(end)) {
    if (!_paidForDue(c, cursor) && cursor.isAtSameMomentAs(today)) {
      count++;
    }
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }
  return count;
}

int countNearDuePayments(Contract c) {
  if (c.term == ContractTerm.daily) return 0;

  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  // نقرأ عدد الأيام من إعدادات الفواتير (نفس اللي تستعمله شاشة العقود)
  int days = 5; // قيمة افتراضية منطقية
  try {
    final sBox = hs.HiveService.boxIfOpen(boxName(kSessionBox));
    if (sBox != null) {
      // نحاول أكثر من مفتاح (نفس أسلوب التقارير في باقي الأماكن)
      final keys = [
        'invoicesNearDays',
        'nearDaysInvoices',
        'nearInvoicesDays',
        'nearDueInvoicesDays',
        'nearDueDaysInvoices',
      ];
      for (final k in keys) {
        final v = sBox.get(k);
        if (v is int && v >= 0) {
          days = v;
          break;
        }
        if (v is num && v >= 0) {
          days = v.toInt();
          break;
        }
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null && parsed >= 0) {
            days = parsed;
            break;
          }
        }
      }
    }
  } catch (_) {}

  final near = today.add(Duration(days: days));
  int count = 0;

  while (!cursor.isAfter(end)) {
    if (!_paidForDue(c, cursor) &&
        cursor.isAfter(today) &&
        (cursor.isBefore(near) || cursor.isAtSameMomentAs(near))) {
      count++;
    }
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }

  return count;
}

/// أوّل استحقاق غير مدفوع فعليًا
DateTime? _earliestUnpaidDueDate(Contract c) {
  if (c.term == ContractTerm.daily) return null;
  final end = _dateOnly(c.endDate);
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  while (!cursor.isAfter(end)) {
    if (!_paidForDue(c, cursor)) return cursor;
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }
  return null;
}

/// يحسب أقرب استحقاق ≥ اليوم ضمن مدة العقد
DateTime? _nextDueDate(Contract c) {
  if (c.term == ContractTerm.daily) return null;
  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final step = _monthsPerCycleForContract(c);
  var due = _dateOnly(c.startDate);

  while (due.isBefore(end)) {
    if (!_paidForDue(c, due) && !due.isBefore(today)) return due;
    due = _dateOnly(_addMonths(due, step));
  }
  return null;
}

/// تُرجِع نفس التاريخ إذا كان صالحًا كـ"دفعة قادمة"
DateTime? _sanitizeUpcoming(Contract c, DateTime? candidate) {
  if (candidate == null) return null;
  final d = _dateOnly(candidate);
  if (!d.isBefore(_dateOnly(c.endDate))) return null;
  if (_paidForDue(c, d)) return null;
  return d;
}

/// هل العقد عليه أي دفعة متأخرة؟
bool isOverdue(Contract c) {
  if (c.term == ContractTerm.daily) return false;
  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  while (!cursor.isAfter(end)) {
    // أي استحقاق غير مدفوع قبل اليوم = متأخر
    if (!_paidForDue(c, cursor) && cursor.isBefore(today)) {
      return true;
    }
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }
  return false;
}

/// هل العقد عليه دفعة مستحقة اليوم؟
bool isDueToday(Contract c) {
  final d = _earliestUnpaidDueDate(c);
  if (d == null) return false;
  return _dateOnly(d) == _dateOnly(KsaTime.now());
}

/// هل العقد عليه دفعة قاربت؟
bool isNearDue(Contract c) {
  if (c.term == ContractTerm.daily) return false;
  final end = _dateOnly(c.endDate);
  final today = _dateOnly(KsaTime.now());
  final stepM = _monthsPerCycleForContract(c);
  var cursor = _dateOnly(c.startDate);

  // نقرأ المدة من إعدادات العقود (مثلاً من sessionBox أو settingsBox)
  int days = 0;
  try {
    final sBox = hs.HiveService.boxIfOpen(boxName(kSessionBox));
    days = sBox?.get('nearDueDays', defaultValue: 0) ?? 0;
  } catch (_) {}

  while (!cursor.isAfter(end)) {
    if (!_paidForDue(c, cursor) && cursor.isAfter(today)) {
      final near = today.add(Duration(days: days));
      return cursor.isBefore(near) || cursor.isAtSameMomentAs(near);
    }
    cursor = _dateOnly(_addMonths(cursor, stepM));
  }
  return false;
}

/// أدوات مساعدة لدورات السداد
int _monthsPerCycle(PaymentCycle c) {
  switch (c) {
    case PaymentCycle.monthly:
      return 1;
    case PaymentCycle.quarterly:
      return 3;
    case PaymentCycle.semiAnnual:
      return 6;
    case PaymentCycle.annual:
      return 12;
  }
}

DateTime _addMonths(DateTime d, int months) {
  final y0 = d.year;
  final m0 = d.month;
  final totalM = m0 - 1 + months;
  final y = y0 + totalM ~/ 12;
  final m = totalM % 12 + 1;
  final day = d.day;
  final maxDay = DateTime(y, m + 1, 0).day;
  final safeDay = day > maxDay ? maxDay : day;
  return DateTime(y, m, safeDay);
}

/// ======= Helpers to compute amounts for receivables =======

int _monthsInTerm(ContractTerm t) {
  switch (t) {
    case ContractTerm.daily:
      return 0;
    case ContractTerm.monthly:
      return 1;
    case ContractTerm.quarterly:
      return 3;
    case ContractTerm.semiAnnual:
      return 6;
    case ContractTerm.annual:
      return 12;
  }
}

int _monthsInContract(Contract c) {
  if (c.term == ContractTerm.annual) {
    final years = c.termYears <= 0 ? 1 : c.termYears;
    return 12 * years;
  }
  return _monthsInTerm(c.term);
}

int _monthsPerCycleForContract(Contract c) {
  if (c.paymentCycle == PaymentCycle.annual) {
    final years = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
    return 12 * years;
  }
  return _monthsPerCycle(c.paymentCycle);
}

/// Compute the per-cycle amount for a contract using the same logic as ContractsScreen.
double perCycleAmountForContract(Contract c) {
  if (c.term == ContractTerm.daily) return c.totalAmount;
  final int months = _monthsInContract(c);
  final int cycles =
      (months / _monthsPerCycleForContract(c)).ceil().clamp(1, 1000);
  // If "deduct from total", reduce the total by advancePaid before dividing
  final double totalForCycles =
      (c.advanceMode.toString().contains('deductFromTotal'))
          ? (c.totalAmount - (c.advancePaid ?? 0))
          : c.totalAmount;
  return (totalForCycles <= 0) ? 0.0 : (totalForCycles / cycles);
}

/// Sum of receivables (unpaid dues) from Contracts schedule only.
/// - If no date filter is provided, counts dues whose due date is <= today.
/// - If from/to are provided, includes dues whose due date is within [from, to] inclusive.
/// - Respects the includeArchived flag.
double sumReceivablesFromContracts(
    {DateTime? from, DateTime? to, bool includeArchived = false}) {
  double total = 0.0;
  try {
    final String cBoxName = hs.HiveService.contractsBoxName();
    if (!Hive.isBoxOpen(cBoxName)) return 0.0;
    final box = Hive.box<Contract>(cBoxName);

    final DateTime today = _dateOnly(KsaTime.now());

    for (final c in box.values) {
      // ignore archived if requested
      try {
        final bool isArchived = (c as dynamic).isArchived == true;
        if (!includeArchived && isArchived) continue;
      } catch (_) {}

      // Effective end date: if terminated early, stop at terminatedAt date (dateOnly)
      DateTime end = _dateOnly(c.endDate);
      try {
        final DateTime? termAt = (c as dynamic).terminatedAt as DateTime?;
        if (termAt != null) {
          final d = _dateOnly(termAt);
          if (d.isBefore(end)) end = d;
        }
      } catch (_) {}

      if (c.term == ContractTerm.daily) {
        final DateTime due = _dateOnly(c.startDate);
        // unpaid and due (<= today) or in date filter
        final bool unpaid = !_paidForDue(c, due);
        if (!unpaid) {
          // nothing to add
        } else {
          bool include;
          if (from == null && to == null) {
            include = !due.isAfter(today);
          } else {
            include = true;
            if (from != null && due.isBefore(_dateOnly(from))) include = false;
            if (to != null && due.isAfter(_dateOnly(to))) include = false;
          }
          if (include) {
            total += c.totalAmount.abs();
          }
        }
        continue;
      }

      // Non-daily: iterate over due dates by payment cycle
      final int stepM = _monthsPerCycleForContract(c);
      DateTime cursor = _dateOnly(c.startDate);

      // Safety guard in case of misconfigured dates
      int guard = 0;
      while (cursor.isBefore(end) && guard < 600) {
        guard++;

        final bool unpaid = !_paidForDue(c, cursor);
        if (unpaid) {
          bool include;
          if (from == null && to == null) {
            include = !cursor.isAfter(today); // due today or overdue
          } else {
            include = true;
            if (from != null && cursor.isBefore(_dateOnly(from))) {
              include = false;
            }
            if (to != null && cursor.isAfter(_dateOnly(to))) include = false;
          }
          if (include) {
            total += perCycleAmountForContract(c).abs();
          }
        }

        cursor = _dateOnly(_addMonths(cursor, stepM));
      }
    }
  } catch (_) {}
  return total;
}

/// Accurate receivables sum in integer cents (no upward rounding), end-exclusive schedule.
/// Mirrors Contracts screen logic: counts only unpaid dues up to today (or within [from..to]).
double sumReceivablesFromContractsExact(
    {DateTime? from, DateTime? to, bool includeArchived = false}) {
  int totalCents = 0;
  try {
    final String cBoxName = hs.HiveService.contractsBoxName();
    if (!Hive.isBoxOpen(cBoxName)) return 0.0;
    final box = Hive.box<Contract>(cBoxName);

    DateTime dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    int toCentsTrunc(num? v) {
      if (v == null) return 0;
      final double d = v.toDouble();
      if (d.isNaN || d.isInfinite) return 0;
      return (d * 100).floor();
    }

    double fromCents(int c) => c / 100.0;

    for (final c in box.values) {
      try {
        // Skip archived if not included
        bool isArchived = false;
        try {
          isArchived = (c as dynamic).isArchived == true;
        } catch (_) {}
        if (!includeArchived && isArchived) continue;

        final DateTime start = _dateOnly((c as dynamic).startDate as DateTime);
        final DateTime end = _dateOnly((c as dynamic).endDate as DateTime);

        if (start.isAfter(end)) continue;

        // If terminated, cap by terminatedAt if earlier
        bool isTerminated = false;
        DateTime? terminatedAt;
        try {
          isTerminated = (c as dynamic).isTerminated == true;
          if (isTerminated) {
            final ta = (c as dynamic).terminatedAt;
            if (ta is DateTime) terminatedAt = _dateOnly(ta);
          }
        } catch (_) {}

        final DateTime today = dOnly(KsaTime.now());
        final DateTime rangeTo = (to != null) ? dOnly(to) : today;
        final DateTime rangeFrom =
            (from != null) ? dOnly(from) : DateTime(2000);

        // effective end is min(end, terminatedAt, rangeTo + 1 day), then end-exclusive iterate in loop.
        DateTime effEnd =
            DateTime(rangeTo.year, rangeTo.month, rangeTo.day + 1);
        if (end.isBefore(effEnd)) effEnd = end;
        if (isTerminated &&
            terminatedAt != null &&
            terminatedAt.isBefore(effEnd)) {
          effEnd = terminatedAt;
        }
        if (!start.isBefore(effEnd)) continue; // no room

        // Per-cycle amount in cents (truncate)
        int stepM =
            _monthsPerCycle((c as dynamic).paymentCycle as PaymentCycle);
        int cycles;
        if ((c as dynamic).term == ContractTerm.daily) {
          cycles = 1;
        } else {
          final int termMonths = _monthsInContract(c);
          cycles = ((termMonths) / stepM).ceil();
          if (cycles < 1) cycles = 1;
          if (cycles > 1000) cycles = 1000;
        }

        // total adjusted for advance if deductFromTotal
        num totalAmount = (c as dynamic).totalAmount ?? 0;
        num advancePaid = (c as dynamic).advancePaid ?? 0;
        String advMode = ((c as dynamic).advanceMode)?.toString() ?? '';
        if (advMode.contains('deductFromTotal')) {
          totalAmount = (totalAmount - advancePaid);
        }
        int perCycleCents = toCentsTrunc(
            (c as dynamic).term == ContractTerm.daily
                ? totalAmount
                : (cycles > 0 ? (totalAmount / cycles) : 0));

        // Iterate due dates
        if ((c as dynamic).term == ContractTerm.daily) {
          final DateTime due = start;
          final bool within = (from != null || to != null)
              ? !(due.isBefore(rangeFrom) || due.isAfter(rangeTo))
              : !due.isAfter(today);
          if (within && !_paidForDue(c, due)) {
            totalCents += perCycleCents;
          }
        } else {
          DateTime cursor = start;
          // jump to first inside rangeFrom
          if (cursor.isBefore(rangeFrom)) {
            while (cursor.isBefore(rangeFrom)) {
              cursor = _dateOnly(_addMonths(cursor, stepM));
            }
          }
          while (cursor.isBefore(effEnd)) {
            final DateTime due = cursor;
            final bool within = (from != null || to != null)
                ? !(due.isBefore(rangeFrom) || due.isAfter(rangeTo))
                : !due.isAfter(today);
            if (within && !_paidForDue(c, due)) {
              totalCents += perCycleCents;
            }
            cursor = _dateOnly(_addMonths(cursor, stepM));
          }
        }
      } catch (_) {}
    }
    return totalCents / 100.0;
  } catch (_) {
    return totalCents / 100.0;
  }
}



