class StatusMapper {
  static bool contractIsArchived(dynamic c) {
    final v = _read(c, ['isArchived', 'archived']);
    return _asBool(v) ?? false;
  }

  static bool contractIsTerminated(dynamic c) {
    final v = _read(c, ['isTerminated', 'terminated']);
    return _asBool(v) ?? false;
  }

  static DateTime? contractStart(dynamic c) {
    return _asDate(_read(c, ['startDate', 'startsOn', 'startAt']));
  }

  static DateTime? contractEnd(dynamic c) {
    return _asDate(_read(c, ['endDate', 'endsOn', 'endAt']));
  }

  static bool maintenanceIsArchived(dynamic m) {
    final v = _read(m, ['isArchived', 'archived']);
    return _asBool(v) ?? false;
  }

  /// new/open -> جديد ، progress/working -> قيد التنفيذ ، done/complete/closed -> مكتملة
  static String maintenanceStage(dynamic m) {
    final s = (_read(m, ['status'])?.toString().toLowerCase() ?? '');
    if (s.contains('new') || s.contains('open')) return 'new';
    if (s.contains('progress') || s.contains('working')) return 'progress';
    if (s.contains('done') || s.contains('complete') || s.contains('closed')) {
      return 'done';
    }
    return 'unknown';
  }

  static bool invoiceIsArchived(dynamic inv) {
    final v = _read(inv, ['isArchived', 'archived']);
    return _asBool(v) ?? false;
  }

  static double invoiceAmount(dynamic inv) {
    final n = _asNum(_read(inv, ['amount', 'total', 'net'])) ?? 0;
    return n.toDouble();
  }

  static DateTime? invoicePaidAt(dynamic inv) {
    final explicit = _asDate(_read(inv, [
      'paidAt',
      'paid_on',
      'paymentDate',
      'paidDate',
    ]));
    if (explicit != null) return explicit;

    final amount = invoiceAmount(inv).abs();
    final paidAmount = (_asNum(_read(inv, ['paidAmount', 'paid'])) ?? 0)
        .toDouble()
        .abs();
    final canceled = _asBool(_read(inv, ['isCanceled', 'canceled'])) ?? false;
    if (!canceled && amount > 0 && paidAmount >= amount - 0.000001) {
      return _asDate(_read(inv, ['issueDate', 'createdAt', 'updatedAt'])) ??
          invoiceDueOn(inv);
    }
    return null;
  }

  static DateTime? invoiceDueOn(dynamic inv) =>
      _asDate(_read(inv, ['dueOn', 'dueDate']));

  static bool invoiceLinkedToContract(dynamic inv) {
    final v = _read(inv, ['contractId', 'contract_id', 'contract']);
    if (v == null) return false;
    return v is! String || v.trim().isNotEmpty;
  }

  static bool invoiceLinkedToMaintenance(dynamic inv) {
    final v = _read(inv, [
      'maintenanceRequestId',
      'maintenanceId',
      'maintenance_id',
      'maintenance',
      'maintenanceSnapshot',
    ]);
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  static bool invoiceIsExpense(dynamic inv) {
    final amount = invoiceAmount(inv);
    final type =
        (_read(inv, ['type', 'category', 'sourceType'])?.toString().toLowerCase() ?? '');
    final note =
        (_read(inv, ['note', 'notes', 'description'])?.toString().toLowerCase() ?? '');
    return amount < 0 ||
        type.contains('expense') ||
        type.contains('مصروف') ||
        type.contains('out') ||
        type.contains('صرف') ||
        type.contains('cost') ||
        note.contains('مصروف');
  }

  // ---------- helpers ----------
  static dynamic _read(Object? o, List<String> names) {
    if (o == null) return null;
    if (o is Map) {
      for (final n in names) {
        if (o.containsKey(n)) return o[n];
      }
    }
    for (final n in names) {
      try {
        final v = _directRead(o, n);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (o as dynamic).toJson?.call()[n];
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (o as dynamic).map?[n];
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (o as dynamic).get?.call(n);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (o as dynamic).noSuchMethod(Invocation.getter(Symbol(n)));
        if (v != null) return v;
      } catch (_) {}
    }
    return null;
  }

  static dynamic _directRead(Object o, String name) {
    final d = o as dynamic;
    try {
      switch (name) {
        case 'id':
          return d.id;
        case 'tenantId':
          return d.tenantId;
        case 'contractId':
          return d.contractId;
        case 'propertyId':
          return d.propertyId;
        case 'maintenanceRequestId':
          return d.maintenanceRequestId;
        case 'maintenanceSnapshot':
          return d.maintenanceSnapshot;
        case 'issueDate':
          return d.issueDate;
        case 'dueDate':
          return d.dueDate;
        case 'amount':
          return d.amount;
        case 'paidAmount':
          return d.paidAmount;
        case 'currency':
          return d.currency;
        case 'note':
        case 'notes':
          return d.note;
        case 'paymentMethod':
          return d.paymentMethod;
        case 'isArchived':
          return d.isArchived;
        case 'isCanceled':
          return d.isCanceled;
        case 'startDate':
          return d.startDate;
        case 'endDate':
          return d.endDate;
        case 'terminatedAt':
          return d.terminatedAt;
        case 'isTerminated':
          return d.isTerminated;
        case 'status':
          return d.status;
        case 'createdAt':
          return d.createdAt;
        case 'updatedAt':
          return d.updatedAt;
        case 'fullName':
          return d.fullName;
        case 'clientType':
          return d.clientType;
        case 'ownerId':
          return d.ownerId;
        case 'totalUnits':
          return d.totalUnits;
        case 'occupiedUnits':
          return d.occupiedUnits;
        case 'isOccupied':
          return d.isOccupied;
      }
    } catch (_) {}
    return null;
  }

  static bool? _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      // true-ish عربية/إنجليزية شائعة
      const trues = {
        '1',
        'true',
        'yes',
        'y',
        'نعم',
        'صح',
        'صحيح',
        'فعّال',
        'فعال'
      };
      const falses = {
        '0',
        'false',
        'no',
        'n',
        'لا',
        'خطأ',
        'غير مفعل',
        'غير مفعّل',
        'غيرفعال'
      };
      if (trues.contains(s)) return true;
      if (falses.contains(s)) return false;
    }
    return null;
  }

  static num? _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static DateTime? _asDate(dynamic v) {
    // دعم Firestore Timestamp بدون الحاجة للاستيراد هنا:
    // نتعرف عليه بشكل ديناميكي لتجنب الاعتماد المباشر.
    try {
      if (v != null && v.runtimeType.toString() == 'Timestamp') {
        // استدعاء toDate() ديناميكي
        final dt = (v as dynamic).toDate?.call();
        if (dt is DateTime) return dt;
      }
    } catch (_) {}

    if (v is DateTime) return v;

    if (v is String) {
      final x = DateTime.tryParse(v);
      if (x != null) return x;
      // لو أتى كسلسلة رقمية:
      final n = num.tryParse(v);
      if (n != null) return _epochNumToDate(n);
      return null;
    }

    if (v is num) {
      return _epochNumToDate(v);
    }

    return null;
  }

  /// يحوّل رقم زمن Epoch إلى DateTime مع التمييز بين seconds/millis/micros
  static DateTime? _epochNumToDate(num n) {
    // نستخدم الحدود التقريبية التالية:
    // < 1e11   → ثواني (1973..5138)
    // 1e11..1e14 → ميلي ثانية (1973..5138)
    // >= 1e14  → مايكرو ثانية
    final abs = n.abs();
    if (abs < 1e11) {
      // seconds → ms
      return DateTime.fromMillisecondsSinceEpoch((n * 1000).round());
    } else if (abs < 1e14) {
      // milliseconds
      return DateTime.fromMillisecondsSinceEpoch(n.round());
    } else {
      // microseconds → ms
      return DateTime.fromMillisecondsSinceEpoch((n / 1000).round());
    }
  }
}
