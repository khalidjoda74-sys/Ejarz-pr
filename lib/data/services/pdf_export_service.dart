// ignore_for_file: prefer_const_constructors,avoid_types_as_parameter_names,use_build_context_synchronously,unnecessary_string_interpolations,curly_braces_in_flow_control_structures
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/boxes.dart';
import '../services/user_scope.dart';
import '../../ui/contracts_screen.dart' show Contract;
import '../../ui/invoices_screen.dart' show Invoice;
import '../../ui/maintenance_screen.dart'
    show MaintenanceRequest, MaintenancePriority;
import '../../models/property.dart';
import '../../models/tenant.dart';

bool _pdfInvoiceIsManual(Invoice invoice) =>
    (invoice.note ?? '').toLowerCase().contains('[manual]');

bool _pdfInvoiceIsOfficeManual(Invoice invoice) {
  if (!_pdfInvoiceIsManual(invoice)) return false;
  final party = (_pdfInvoicePartyName(invoice.note) ?? '').trim();
  if (party == 'المكتب') return true;

  final note = (invoice.note ?? '').toLowerCase();
  return note.contains('[office_commission]') ||
      note.contains('[office_withdrawal]') ||
      note.contains('مصروف إداري للمكتب') ||
      note.contains('مقبوض للمكتب') ||
      note.contains('تحويل من رصيد المكتب') ||
      note.contains('سحب من رصيد المكتب') ||
      note.contains('إيراد عمولة للمكتب');
}

bool _pdfInvoiceShouldShowPaymentMethod(Invoice invoice) {
  if (!_pdfInvoiceIsManual(invoice)) return false;
  if (_pdfInvoiceIsOfficeManual(invoice)) return false;
  return invoice.paymentMethod.trim().isNotEmpty;
}

bool _pdfInvoiceHasServiceCycleReference(String? note) {
  final lower = (note ?? '').trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower.contains('دورة بتاريخ') ||
      lower.contains('تاريخ الدورة') ||
      lower.contains('دورة الفاتورة');
}

bool _pdfInvoiceHasServiceOrigin(String? note) {
  final lower = (note ?? '').trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower.contains('[service]') ||
      lower.contains('[shared_service_office:') ||
      lower.contains('type=water') ||
      lower.contains('type=electricity') ||
      lower.contains('type=internet') ||
      lower.contains('type=cleaning') ||
      lower.contains('type=elevator') ||
      lower.contains('تحصيل خدمة') ||
      _pdfInvoiceHasServiceCycleReference(lower);
}

String _pdfInvoiceTableDateHeader(Invoice invoice) {
  if (_pdfInvoiceHasServiceCycleReference(invoice.note)) {
    return 'تاريخ الدورة';
  }
  if (_pdfInvoiceHasServiceOrigin(invoice.note)) {
    return 'تاريخ الخدمة';
  }
  return 'التاريخ';
}

bool _pdfInvoiceIsOwnerPayout(Invoice invoice) =>
    (invoice.note ?? '').toLowerCase().contains('[owner_payout]');

bool _pdfInvoiceIsOwnerAdjustment(Invoice invoice) =>
    (invoice.note ?? '').toLowerCase().contains('[owner_adjustment]');

String? _pdfInvoiceMarkerValue(String? note, String key) {
  final text = (note ?? '').trim();
  if (text.isEmpty) return null;
  final exp = RegExp('\\[$key:(.*?)\\]', caseSensitive: false);
  final match = exp.firstMatch(text);
  final value = match?.group(1)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

String? _pdfInvoicePartyName(String? note) =>
    _pdfInvoiceMarkerValue(note, 'PARTY');

String? _pdfInvoicePropertyName(String? note) =>
    _normalizePdfInvoicePropertyName(_pdfInvoiceMarkerValue(note, 'PROPERTY'));

String? _normalizePdfInvoicePropertyName(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty ||
      text == 'جميع العقارات معًا' ||
      text == 'إظهار جميع العقارات معًا') {
    return null;
  }
  return text;
}

String? _pdfMapString(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _composePdfPropertyReference({
  String unitName = '',
  String buildingName = '',
}) {
  final normalizedUnit = unitName.trim();
  final normalizedBuilding = buildingName.trim();
  if (normalizedBuilding.isEmpty) return normalizedUnit;
  if (normalizedUnit.isEmpty || normalizedUnit == normalizedBuilding) {
    return normalizedBuilding;
  }
  return '$normalizedBuilding ($normalizedUnit)';
}

bool _pdfTenantIsProvider(Tenant? tenant) {
  if (tenant == null) return false;
  final raw = tenant.clientType.trim().toLowerCase();
  if (raw == 'serviceprovider' ||
      raw == 'service_provider' ||
      raw == 'service provider' ||
      raw == 'مقدم خدمة') {
    return true;
  }
  return (tenant.serviceSpecialization ?? '').trim().isNotEmpty &&
      raw != 'company' &&
      raw != 'مستأجر (شركة)' &&
      raw != 'شركة';
}

String _pdfInvoiceCleanNote(String? note) {
  final raw = (note ?? '').trim();
  if (raw.isEmpty) return '';
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) {
        if (line.isEmpty) return false;
        final lower = line.toLowerCase();
        return lower != '[manual]' &&
            !lower.startsWith('[service]') &&
            !lower.startsWith('[shared_service_office:') &&
            !lower.startsWith('[party:') &&
            !lower.startsWith('[party_id:') &&
            !lower.startsWith('[property:') &&
            !lower.startsWith('[property_id:') &&
            !lower.startsWith('[title:') &&
            !lower.startsWith('[owner_payout]') &&
            !lower.startsWith('[owner_adjustment]') &&
            !lower.startsWith('[office_commission]') &&
            !lower.startsWith('[office_withdrawal]') &&
            !lower.startsWith('[owner_payout_id:') &&
            !lower.startsWith('[owner_adjustment_id:') &&
            !lower.startsWith('[owner_adjustment_category:') &&
            !lower.startsWith('[contract_voucher_id:') &&
            !lower.startsWith('[posted]') &&
            !lower.startsWith('[cancelled]') &&
            !lower.startsWith('[reversal]') &&
            !lower.startsWith('[reversed]');
      })
      .toList();
  return lines.join('\n').trim();
}

String _pdfInvoiceDisplayNote(String? note) {
  final title = (_pdfInvoiceMarkerValue(note, 'TITLE') ?? '').trim();
  final cleanNote = _pdfInvoiceCleanNote(note);
  if (title.isEmpty) return cleanNote;
  if (cleanNote.isEmpty) return title;

  final normalizedTitle = title.toLowerCase();
  final extraLines = cleanNote
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line.toLowerCase() != normalizedTitle)
      .toList();

  if (extraLines.isEmpty) return title;
  return <String>[title, ...extraLines].join('\n').trim();
}

String _pdfPlainText(dynamic value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

String _pdfAppendPropertyReferenceToStatement(
  String statement,
  String propertyRef,
) {
  final normalizedStatement = statement.trim();
  final normalizedPropertyRef = _pdfPlainText(propertyRef).trim();
  if (normalizedPropertyRef.isEmpty || normalizedPropertyRef == '-') {
    return normalizedStatement;
  }
  if (normalizedStatement.isEmpty) return normalizedPropertyRef;

  final lines = normalizedStatement
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return normalizedPropertyRef;

  final joinedLower = lines.join('\n').toLowerCase();
  if (joinedLower.contains(normalizedPropertyRef.toLowerCase())) {
    return lines.join('\n').trim();
  }

  lines[0] = '${lines[0]} • $normalizedPropertyRef';
  return lines.join('\n').trim();
}

String _pdfMaintenanceStatementText(
  String? note, {
  required String propertyRef,
  String fallback = '',
}) {
  final base = _pdfPlainText(_pdfInvoiceDisplayNote(note), fallback: fallback).trim();
  if (base.isEmpty) return _pdfPlainText(propertyRef, fallback: '-');
  return _pdfAppendPropertyReferenceToStatement(base, propertyRef);
}

class MaintenanceReceiptDetails {
  final String id;
  final String? invoiceId;
  final String requestType;
  final String title;
  final String description;
  final MaintenancePriority priority;
  final String? assignedTo;
  final Map<String, dynamic>? providerSnapshot;
  final DateTime createdAt;
  final DateTime? scheduledDate;
  final DateTime? executionDeadline;
  final DateTime? completedDate;
  final double cost;
  final String? tenantId;
  final String? propertyId;

  const MaintenanceReceiptDetails({
    required this.id,
    this.invoiceId,
    required this.requestType,
    required this.title,
    required this.description,
    required this.priority,
    this.assignedTo,
    this.providerSnapshot,
    required this.createdAt,
    this.scheduledDate,
    this.executionDeadline,
    this.completedDate,
    required this.cost,
    this.tenantId,
    this.propertyId,
  });

  factory MaintenanceReceiptDetails.fromRequest(MaintenanceRequest item) {
    return MaintenanceReceiptDetails(
      id: item.id,
      invoiceId: item.invoiceId,
      requestType: item.requestType,
      title: item.title,
      description: item.description,
      priority: item.priority,
      assignedTo: item.assignedTo,
      providerSnapshot: item.providerSnapshot,
      createdAt: item.createdAt,
      scheduledDate: item.scheduledDate,
      executionDeadline: item.executionDeadline,
      completedDate: item.completedDate,
      cost: item.cost,
      tenantId: item.tenantId,
      propertyId: item.propertyId,
    );
  }

  factory MaintenanceReceiptDetails.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final millis = int.tryParse(value.toString());
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
      return null;
    }

    final priorityName = (map['priority'] ?? '').toString();
    final priority = MaintenancePriority.values.firstWhere(
      (p) => p.name == priorityName,
      orElse: () => MaintenancePriority.medium,
    );

    return MaintenanceReceiptDetails(
      id: (map['id'] ?? '').toString(),
      invoiceId: (map['invoiceId'] ?? '').toString().isEmpty
          ? null
          : (map['invoiceId'] ?? '').toString(),
      requestType: (map['requestType'] ?? 'خدمات').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      priority: priority,
      assignedTo: (map['assignedTo'] ?? '').toString().isEmpty
          ? null
          : (map['assignedTo'] ?? '').toString(),
      providerSnapshot: (map['providerSnapshot'] as Map?)?.cast<String, dynamic>(),
      createdAt: parseDate(map['createdAt']) ?? KsaTime.now(),
      scheduledDate: parseDate(map['scheduledDate']),
      executionDeadline: parseDate(map['executionDeadline']),
      completedDate: parseDate(map['completedDate']),
      cost: (map['cost'] is num)
          ? (map['cost'] as num).toDouble()
          : double.tryParse(map['cost']?.toString() ?? '') ?? 0.0,
      tenantId: (map['tenantId'] ?? '').toString().isEmpty
          ? null
          : (map['tenantId'] ?? '').toString(),
      propertyId: (map['propertyId'] ?? '').toString().isEmpty
          ? null
          : (map['propertyId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoiceId': invoiceId,
        'requestType': requestType,
        'title': title,
        'description': description,
        'priority': priority.name,
        'assignedTo': assignedTo,
        'providerSnapshot': providerSnapshot,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'scheduledDate': scheduledDate?.millisecondsSinceEpoch,
        'executionDeadline': executionDeadline?.millisecondsSinceEpoch,
        'completedDate': completedDate?.millisecondsSinceEpoch,
        'cost': cost,
        'tenantId': tenantId,
        'propertyId': propertyId,
      };
}

String _pdfSharedServiceVoucherLabelFromText(
  String text, {
  bool isExpense = true,
}) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return '';
  final hasSharedService =
      lower.contains('مشترك') || lower.contains('مشتركة') || lower.contains('shared');
  if (!hasSharedService) return '';
  final prefix = isExpense ? 'سداد' : 'تحصيل';
  if (lower.contains('water') || lower.contains('مياه') || lower.contains('ماء')) {
    return '$prefix خدمة مياه مشتركة';
  }
  if (lower.contains('electric') || lower.contains('كهرب')) {
    return '$prefix خدمة كهرباء مشتركة';
  }
  return '';
}

String _pdfMaintenanceSharedServiceVoucherLabel(MaintenanceReceiptDetails details) {
  final hay = '${details.requestType}\n${details.title}\n${details.description}'.trim();
  return _pdfSharedServiceVoucherLabelFromText(hay, isExpense: true);
}

String _pdfStripMaintenanceRequestPrefix(String raw) {
  final text = raw.trim();
  if (text.startsWith('طلب ')) {
    final stripped = text.substring(4).trim();
    if (stripped.isNotEmpty) return stripped;
  }
  return text;
}

String _pdfMaintenanceVoucherTypeLabelFromText(String raw) {
  final text = _pdfStripMaintenanceRequestPrefix(raw);
  final lower = text.toLowerCase();
  if (lower.isEmpty) return '';

  final hasSharedService =
      lower.contains('مشترك') || lower.contains('مشتركة') || lower.contains('shared');
  if (hasSharedService &&
      (lower.contains('water') || lower.contains('مياه') || lower.contains('ماء'))) {
    return 'خدمة مياه مشتركة';
  }
  if (hasSharedService &&
      (lower.contains('electric') || lower.contains('كهرب'))) {
    return 'خدمة كهرباء مشتركة';
  }
  if (lower.contains('مصعد') ||
      lower.contains('اسانسير') ||
      lower.contains('elevator')) {
    return 'صيانة مصعد';
  }
  if (lower.contains('نظاف') || lower.contains('clean')) {
    return 'نظافة عمارة';
  }
  if (lower.contains('internet') ||
      lower.contains('انترنت') ||
      lower.contains('إنترنت')) {
    return 'خدمة إنترنت';
  }
  if (lower.contains('water') || lower.contains('مياه') || lower.contains('ماء')) {
    return 'خدمة مياه';
  }
  if (lower.contains('electric') || lower.contains('كهرب')) {
    return 'خدمة كهرباء';
  }
  if (text == 'خدمات' || text == 'خدمة دورية' || text == 'طلب خدمات') {
    return '';
  }
  return text;
}

String _pdfMaintenanceVoucherDisplayType(MaintenanceReceiptDetails details) {
  final sharedLabel = _pdfMaintenanceSharedServiceVoucherLabel(details);
  if (sharedLabel.isNotEmpty) {
    return sharedLabel.replaceFirst(RegExp(r'^(سداد|تحصيل)\s+'), '').trim();
  }

  for (final value in [details.requestType, details.title, details.description]) {
    final label = _pdfMaintenanceVoucherTypeLabelFromText(value);
    if (label.isNotEmpty) return label;
  }

  final joined =
      '${details.requestType}\n${details.title}\n${details.description}'.trim();
  final inferred = _pdfMaintenanceVoucherTypeLabelFromText(joined);
  return inferred.isNotEmpty ? inferred : 'خدمات';
}

String _pdfMaintenanceSpecialVoucherKind(MaintenanceReceiptDetails details) {
  return (details.providerSnapshot?['specialVoucherKind'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
}

bool _pdfIsWaterCompanyOfficeExpenseVoucher(
  MaintenanceReceiptDetails details,
  List<Invoice> relatedInvoices,
) {
  if (_pdfMaintenanceSpecialVoucherKind(details) ==
      'water_company_office_expense') {
    return true;
  }
  final lowerTitle = details.title.trim().toLowerCase();
  if (lowerTitle == 'فاتورة شركة المياه' &&
      _pdfMaintenanceVoucherDisplayType(details).contains('مياه')) {
    return true;
  }
  for (final invoice in relatedInvoices) {
    final note = (invoice.note ?? '').toLowerCase();
    if (note.contains('[title: فاتورة شركة المياه]') &&
        note.contains('type=water')) {
      return true;
    }
  }
  return false;
}

String _pdfMaintenanceCompactStatementText(
  String? note, {
  required String propertyRef,
  String fallback = '',
  required bool includeTitle,
}) {
  final base = _pdfPlainText(
    includeTitle ? _pdfInvoiceDisplayNote(note) : _pdfInvoiceCleanNote(note),
    fallback: fallback,
  ).trim();
  if (base.isEmpty) return _pdfPlainText(propertyRef, fallback: '-');
  return _pdfAppendPropertyReferenceToStatement(base, propertyRef);
}

bool _pdfMaintenanceIsSharedServiceVoucher(MaintenanceReceiptDetails details) =>
    _pdfMaintenanceSharedServiceVoucherLabel(details).isNotEmpty;

DateTime _pdfMaintenanceEffectiveCycleDate(MaintenanceReceiptDetails details) =>
    details.executionDeadline ??
    details.scheduledDate ??
    details.completedDate ??
    details.createdAt;

class PdfExportService {
  static const String _officeProfilePath = 'office_profile';
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  static Future<Map<String, String>> _loadOfficeProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return const {};
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final office = (data[_officeProfilePath] is Map)
          ? Map<String, dynamic>.from(data[_officeProfilePath] as Map)
          : const <String, dynamic>{};
      String pick(List<String> keys) {
        for (final k in keys) {
          final v = office[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
        for (final k in keys) {
          final v = data[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
        return '';
      }

      final profile = {
        'name': pick(['office_name', 'officeName']),
        'address': pick(['address', 'office_address', 'officeAddress']),
        'commercial': pick(['commercial_no', 'commercialNo']),
        'mobile': pick(['mobile']),
        'phone': pick(['phone']),
        'tax_no': pick(['tax_no', 'taxNo', 'vat_no', 'vatNo']),
        'logo_base64': pick(['logo_base64', 'logoBase64']),
      };
      debugPrint(
        '[PDF_TRACE] officeProfile '
        'uid=$uid '
        'name="${profile['name']}" '
        'mobile="${profile['mobile']}" '
        'phone="${profile['phone']}" '
        'commercial="${profile['commercial']}" '
        'hasLogo=${(profile['logo_base64'] ?? '').isNotEmpty}',
      );
      return profile;
    } catch (_) {
      return const {};
    }
  }

  static Future<Map<String, String>> _loadCurrentUserDebugContext() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return const {};
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final result = <String, String>{
        'uid': uid.trim(),
        'name': (data['name'] ?? '').toString().trim(),
        'role': (data['role'] ?? '').toString().trim(),
        'isDemo': (data['isDemo'] == true).toString(),
        'officeId': (data['officeId'] ?? data['office_id'] ?? '')
            .toString()
            .trim(),
        'demoOfficeId': (data['demoOfficeId'] ?? '').toString().trim(),
      };
      debugPrint(
        '[PDF_TRACE] actor '
        'uid=${result['uid']} '
        'name="${result['name']}" '
        'role=${result['role']} '
        'isDemo=${result['isDemo']} '
        'officeId=${result['officeId']} '
        'demoOfficeId=${result['demoOfficeId']}',
      );
      return result;
    } catch (e) {
      debugPrint('[PDF_TRACE] loadCurrentUserDebugContext failed: $e');
      return const {};
    }
  }

  static Future<Uint8List?> _decodeOfficeLogoBytes(
    Map<String, String> office,
  ) async {
    final officeLogoRaw = _txt(office['logo_base64'], fallback: '').trim();
    if (officeLogoRaw.isEmpty) return null;
    try {
      final bytes = base64Decode(officeLogoRaw);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      debugPrint(
        '[PDF_TRACE] officeLogo valid bytes=${bytes.length}',
      );
      return bytes;
    } catch (e) {
      debugPrint('[PDF_TRACE] officeLogo invalid ignored: $e');
      return null;
    }
  }

  static String _fixMojibake(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    if (!s.contains('Ø') &&
        !s.contains('Ù') &&
        !s.contains('Ã') &&
        !s.contains('Â')) {
      return s;
    }
    try {
      return utf8.decode(latin1.encode(s));
    } catch (_) {
      return s;
    }
  }

  static String _txt(dynamic v, {String fallback = '-'}) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return fallback;
    return _stripPdfUnsafeControls(_fixMojibake(s));
  }

  // Force RTL rendering for short Arabic values inside mixed-direction lines.
  static String _rtlIsolate(dynamic v, {String fallback = '-'}) {
    final s = _txt(v, fallback: fallback).trim();
    if (s.isEmpty) return fallback;
    return s;
  }

  // Remove bidi/control chars unsupported by some PDF fonts.
  static String _stripPdfUnsafeControls(String input) {
    if (input.isEmpty) return input;
    return input.replaceAll(
      RegExp(r'[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]'),
      '',
    );
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _maintenancePriorityLabel(MaintenancePriority p) {
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

  static String _fmtHijriDate(DateTime? d) {
    if (d == null) return '-';
    final h = HijriCalendar.fromDate(d);
    final m = h.hMonth.toString().padLeft(2, '0');
    final day = h.hDay.toString().padLeft(2, '0');
    return '${h.hYear}-$m-$day';
  }

  static String _fmtMoney(num? v) {
    final n = (v ?? 0).toDouble();
    return n.toStringAsFixed(2);
  }

  static Future<(String propertyRef, String propertyAddress)>
      _resolveMaintenancePropertyInfo({
    Property? property,
    String? propertyId,
  }) async {
    Property? current = property;
    final id = (propertyId ?? '').trim();
    Property? building;

    try {
      final pBoxName = boxName(kPropertiesBox);
      final pBox = Hive.isBoxOpen(pBoxName)
          ? Hive.box<Property>(pBoxName)
          : await Hive.openBox<Property>(pBoxName);

      if (current == null && id.isNotEmpty) {
        current = pBox.get(id);
      }

      final parentId = (current?.parentBuildingId ?? '').trim();
      if (parentId.isNotEmpty) {
        building = pBox.get(parentId);
      }
    } catch (_) {}

    final propertyRef = _composePdfPropertyReference(
      unitName: _txt(current?.name ?? id, fallback: '').trim(),
      buildingName: _txt(building?.name, fallback: '').trim(),
    );
    final addressSource =
        _txt(building?.address ?? current?.address, fallback: '').trim();
    return (
      _txt(propertyRef.isEmpty ? (current?.name ?? id) : propertyRef,
          fallback: '-'),
      _txt(addressSource, fallback: '-'),
    );
  }

  static String _toArabicWordsUnder1000(int n) {
    const ones = <String>[
      'صفر',
      'واحد',
      'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
    ];
    const teens = <String>[
      'عشرة',
      'أحد عشر',
      'اثنا عشر',
      'ثلاثة عشر',
      'أربعة عشر',
      'خمسة عشر',
      'ستة عشر',
      'سبعة عشر',
      'ثمانية عشر',
      'تسعة عشر',
    ];
    const tens = <String>[
      '',
      '',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون',
    ];
    const hundreds = <String>[
      '',
      'مائة',
      'مائتان',
      'ثلاثمائة',
      'أربعمائة',
      'خمسمائة',
      'ستمائة',
      'سبعمائة',
      'ثمانمائة',
      'تسعمائة',
    ];

    if (n == 0) return '';
    final parts = <String>[];
    final h = n ~/ 100;
    final r = n % 100;
    if (h > 0) parts.add(hundreds[h]);
    if (r > 0) {
      if (r < 10) {
        parts.add(ones[r]);
      } else if (r < 20) {
        parts.add(teens[r - 10]);
      } else {
        final t = r ~/ 10;
        final o = r % 10;
        if (o == 0) {
          parts.add(tens[t]);
        } else {
          parts.add('${ones[o]} و${tens[t]}');
        }
      }
    }
    return parts.join(' و');
  }

  static String _intToArabicWords(int n) {
    if (n <= 0) return 'صفر';
    String scaleWord(
        int value, String one, String two, String many, String moreThanTen) {
      if (value == 1) return one;
      if (value == 2) return two;
      if (value >= 3 && value <= 10)
        return '${_toArabicWordsUnder1000(value)} $many';
      return '${_toArabicWordsUnder1000(value)} $moreThanTen';
    }

    final parts = <String>[];
    var value = n;
    final millions = value ~/ 1000000;
    value %= 1000000;
    final thousands = value ~/ 1000;
    value %= 1000;
    final rest = value;

    if (millions > 0) {
      parts.add(scaleWord(millions, 'مليون', 'مليونان', 'ملايين', 'مليون'));
    }
    if (thousands > 0) {
      parts.add(scaleWord(thousands, 'ألف', 'ألفان', 'آلاف', 'ألف'));
    }
    if (rest > 0) {
      parts.add(_toArabicWordsUnder1000(rest));
    }
    return parts.join(' و');
  }

  static String _amountInWordsAr(num amount) {
    final n = amount.abs().round();
    return _intToArabicWords(n);
  }

  static String _safeFileName(String input) {
    return input.replaceAll(RegExp(r'[^\w\-\.\u0600-\u06FF]'), '_');
  }

  static const String _pdfRegularFontAsset = 'assets/fonts/tahoma.ttf';
  static const String _pdfBoldFontAsset = 'assets/fonts/tahomabd.ttf';

  static Future<pw.Font> _loadBundledPdfFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }

  static Future<(pw.Font, pw.Font)> _loadFonts() async {
    try {
      final pw.Font regular =
          await _loadBundledPdfFont(_pdfRegularFontAsset);
      final pw.Font bold = await _loadBundledPdfFont(_pdfBoldFontAsset);
      return (regular, bold);
    } catch (_) {
      return (pw.Font.helvetica(), pw.Font.helveticaBold());
    }
  }

  static Uri? _savedLocationToUri(String? rawLocation) {
    final value = (rawLocation ?? '').trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
      return Uri.file(value);
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.scheme.isNotEmpty) {
      return parsed;
    }
    return Uri.file(value);
  }

  static Future<Uri?> _savePdfToDownloads(
    Uint8List bytes,
    String filename,
  ) async {
    final safeName = _safeFileName(filename);
    debugPrint(
      '[PDF_TRACE] saveToDownloads start name=$safeName bytes=${bytes.length}',
    );
    try {
      final savedPath = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': safeName,
          'mimeType': 'application/pdf',
        },
      );
      final savedUri = _savedLocationToUri(savedPath);
      if (savedUri != null) {
        debugPrint(
          '[PDF_TRACE] saveToDownloads channel success raw="$savedPath" uri="$savedUri"',
        );
        return savedUri;
      }
      debugPrint('[PDF_TRACE] saveToDownloads channel returned empty location');
    } catch (e) {
      debugPrint('[PDF_TRACE] saveToDownloads channel failed: $e');
    }

    try {
      final Directory dir;
      if (Platform.isAndroid) {
        final androidDownloads = Directory('/storage/emulated/0/Download');
        if (androidDownloads.existsSync()) {
          dir = androidDownloads;
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}${Platform.pathSeparator}$safeName');
      await file.writeAsBytes(bytes, flush: true);
      debugPrint(
        '[PDF_TRACE] saveToDownloads file fallback success path=${file.path}',
      );
      return Uri.file(file.path);
    } catch (e) {
      debugPrint('[PDF_TRACE] saveToDownloads file fallback failed: $e');
      return null;
    }
  }

  static Future<bool> _shareDoc({
    required BuildContext context,
    required pw.Document doc,
    required String filename,
  }) async {
    try {
      final safeName = _safeFileName(filename);
      await _loadCurrentUserDebugContext();
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$safeName');
      debugPrint(
        '[PDF_TRACE] shareDoc start name=$safeName bytes=${bytes.length} tempPath=${file.path}',
      );
      await file.writeAsBytes(bytes, flush: true);
      final xFile = XFile(file.path, mimeType: 'application/pdf');

      try {
        debugPrint('[PDF_TRACE] shareDoc try Printing.sharePdf');
        await Printing.sharePdf(bytes: bytes, filename: safeName);
        debugPrint('[PDF_TRACE] shareDoc Printing.sharePdf success');
        return true;
      } catch (e) {
        debugPrint('[PDF_TRACE] Printing.sharePdf failed: $e');
      }

      try {
        debugPrint('[PDF_TRACE] shareDoc try Share.shareXFiles temp');
        await Share.shareXFiles([xFile]);
        debugPrint('[PDF_TRACE] shareDoc Share.shareXFiles temp success');
        return true;
      } catch (e) {
        debugPrint('[PDF_TRACE] Share.shareXFiles failed: $e');
      }

      try {
        debugPrint('[PDF_TRACE] shareDoc try Share.shareXFiles memory');
        await Share.shareXFiles([
          XFile.fromData(bytes, mimeType: 'application/pdf', name: safeName),
        ]);
        debugPrint('[PDF_TRACE] shareDoc Share.shareXFiles memory success');
        return true;
      } catch (e) {
        debugPrint('[PDF_TRACE] Share.shareXFiles memory failed: $e');
      }

      final downloadsUri = await _savePdfToDownloads(bytes, safeName);
      if (downloadsUri != null) {
        debugPrint('[PDF_TRACE] shareDoc downloads uri=$downloadsUri');
        try {
          final openedFromDownloads =
              await launchUrl(
                downloadsUri,
                mode: LaunchMode.externalApplication,
              ) ||
              await launchUrl(
                downloadsUri,
                mode: LaunchMode.platformDefault,
              );
          debugPrint('[PDF_TRACE] shareDoc open downloads result=$openedFromDownloads');
          if (openedFromDownloads) return true;
        } catch (e) {
          debugPrint('[PDF_TRACE] open downloads uri failed: $e');
        }
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ ملف PDF في التنزيلات')),
        );
        return true;
      }

      final uri = Uri.file(file.path);
      debugPrint('[PDF_TRACE] shareDoc try open temp uri=$uri');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication) ||
          await launchUrl(uri, mode: LaunchMode.platformDefault);
      debugPrint('[PDF_TRACE] shareDoc open temp result=$opened');
      if (!opened) {
        throw Exception('pdf_open_failed');
      }
      return true;
    } catch (e, s) {
      debugPrint('[PDF_TRACE] shareDoc failed: $e');
      debugPrint('$s');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر مشاركة الملف')),
      );
      return false;
    }
  }

  static pw.Widget _sectionTitle(String title, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(_txt(title),
          textDirection: pw.TextDirection.rtl, style: style),
    );
  }

  static pw.Widget _kv(String k, String v, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_txt('$k:'),
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.right,
              style: style),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Text(_txt(v),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.left,
                style: style),
          ),
        ],
      ),
    );
  }

  static bool _hasPdfValue(dynamic value) {
    final normalized = _txt(value, fallback: '').trim();
    return normalized.isNotEmpty && normalized != '-' && normalized != '—';
  }

  static pw.Widget _periodTextWithDateHighlight(
    String text, {
    required pw.TextStyle baseStyle,
    required PdfColor dateColor,
  }) {
    final normalized = _txt(text, fallback: '').trim();
    if (normalized.isEmpty) {
      return pw.Text(
        '-',
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.left,
        style: baseStyle,
      );
    }

    final matches =
        RegExp(r'([0-9]{4}-[0-9]{2}-[0-9]{2})').allMatches(normalized).toList();
    if (matches.isEmpty) {
      return pw.Text(
        normalized,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.left,
        style: baseStyle,
      );
    }

    final spans = <pw.InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(pw.TextSpan(text: normalized.substring(cursor, m.start)));
      }
      spans.add(
        pw.TextSpan(
          text: normalized.substring(m.start, m.end),
          style: baseStyle.copyWith(color: dateColor),
        ),
      );
      cursor = m.end;
    }
    if (cursor < normalized.length) {
      spans.add(pw.TextSpan(text: normalized.substring(cursor)));
    }

    return pw.RichText(
      textDirection: pw.TextDirection.rtl,
      text: pw.TextSpan(style: baseStyle, children: spans),
    );
  }

  static DateTime _addMonthsSafe(DateTime d, int months) {
    final y0 = d.year;
    final m0 = d.month;
    final totalM = m0 - 1 + months;
    final y = y0 + totalM ~/ 12;
    final m = totalM % 12 + 1;
    final maxDay = DateTime(y, m + 1, 0).day;
    final safeDay = d.day > maxDay ? maxDay : d.day;
    return DateTime(y, m, safeDay);
  }

  static int _monthsPerCycleFromContract(Contract? c) {
    if (c == null) return 1;
    final cycle = c.paymentCycle.toString();
    if (cycle.endsWith('monthly')) return 1;
    if (cycle.endsWith('quarterly')) return 3;
    if (cycle.endsWith('semiAnnual')) return 6;
    if (cycle.endsWith('annual')) {
      final y = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
      return 12 * y;
    }
    return 1;
  }

  static String _cycleDurationLabelForContract(Contract? c) {
    final months = _monthsPerCycleFromContract(c);
    if (months <= 1) return '1 شهر';
    if (months % 12 == 0) {
      final years = (months ~/ 12).clamp(1, 10);
      return years == 1 ? '1 سنة' : '$years سنة';
    }
    return '$months شهور';
  }

  static bool _isDailyContract(Contract? c) =>
      c != null && c.term.toString().split('.').last == 'daily';

  static int _dailyContractDays(Contract c) {
    final days = c.endDate.difference(c.startDate).inDays;
    return days <= 0 ? 1 : days;
  }

  static String _dailyRentalDaysLabel(int days) {
    if (days <= 0) return '0 يوم';
    if (days == 1) return '1 يوم';
    if (days == 2) return '2 يوم';
    return '$days أيام';
  }

  static String _formatHourAmPm(int hour24) {
    final normalized = hour24.clamp(0, 23);
    final hour12 = normalized == 0
        ? 12
        : (normalized > 12 ? normalized - 12 : normalized);
    final suffix = normalized >= 12 ? 'PM' : 'AM';
    return '$hour12:00 $suffix';
  }

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${_formatHourAmPm(d.hour)}';

  static String _dailyInvoicePeriodLabel(Contract c) {
    final daysLabel = _dailyRentalDaysLabel(_dailyContractDays(c));
    return '$daysLabel من تاريخ ${_fmtDateTime(c.dailyStartBoundary)} إلى ${_fmtDateTime(c.dailyEndBoundary)}';
  }

  static double? _dailyInvoiceRate(Contract? c) {
    if (!_isDailyContract(c)) return null;
    final contract = c!;
    final days = _dailyContractDays(contract);
    return days <= 0 ? null : contract.totalAmount / days;
  }

  static String _invoicePeriodLabel(Invoice invoice, Contract? contract) {
    final due = DateTime(
        invoice.dueDate.year, invoice.dueDate.month, invoice.dueDate.day);
    if (_isDailyContract(contract)) {
      return _dailyInvoicePeriodLabel(contract!);
    }
    if (contract == null) {
      return 'التاريخ: ${_fmtDate(due)}';
    }
    final months = _monthsPerCycleFromContract(contract);
    final duration = _cycleDurationLabelForContract(contract);
    final endDate = _addMonthsSafe(due, months);
    return '$duration: من ${_fmtDate(due)} إلى ${_fmtDate(endDate)}';
  }

  static String _contractTermLabel(Contract c) {
    final term = c.term.toString().split('.').last;
    if (term == 'annual' && c.termYears > 1) return '${c.termYears} سنة';
    switch (term) {
      case 'daily':
        return 'يومي';
      case 'monthly':
        return 'شهريًا';
      case 'quarterly':
        return 'ربع سنوي';
      case 'semiAnnual':
        return 'نصف سنوي';
      case 'annual':
        return 'سنويًا';
      default:
        return _txt(term, fallback: 'سنويًا');
    }
  }

  static String _contractPaymentLabel(Contract c) {
    final cycle = c.paymentCycle.toString().split('.').last;
    if (cycle == 'annual' && c.paymentCycleYears > 1) {
      return '${c.paymentCycleYears} سنة';
    }
    switch (cycle) {
      case 'monthly':
        return 'شهريًا';
      case 'quarterly':
        return 'ربع سنوي';
      case 'semiAnnual':
        return 'نصف سنوي';
      case 'annual':
        return 'سنويًا';
      default:
        return _txt(cycle, fallback: 'شهريًا');
    }
  }

  static int _contractTermMonths(Contract c) {
    final term = c.term.toString().split('.').last;
    switch (term) {
      case 'daily':
        return 0;
      case 'monthly':
        return 1;
      case 'quarterly':
        return 3;
      case 'semiAnnual':
        return 6;
      case 'annual':
        final y = c.termYears <= 0 ? 1 : c.termYears;
        return 12 * y;
      default:
        return 12;
    }
  }

  static int _contractInstallmentsCount(Contract c) {
    final term = c.term.toString().split('.').last;
    if (term == 'daily') return 1;
    final months = _contractTermMonths(c).clamp(1, 1200);
    final perCycle = _monthsPerCycleFromContract(c).clamp(1, 120);
    return (months / perCycle).ceil().clamp(1, 1000);
  }

  static List<DateTime> _contractInstallmentDates(Contract c) {
    final start =
        DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
    final end = DateTime(c.endDate.year, c.endDate.month, c.endDate.day);
    final term = c.term.toString().split('.').last;
    if (term == 'daily') return <DateTime>[start];

    final stepMonths = _monthsPerCycleFromContract(c).clamp(1, 120);
    final dates = <DateTime>[];
    var cursor = start;
    var guard = 0;
    while (cursor.isBefore(end) && guard < 1000) {
      dates.add(cursor);
      cursor = _addMonthsSafe(cursor, stepMonths);
      guard++;
    }
    if (dates.isEmpty) {
      dates.add(start);
    }
    return dates;
  }

  static ({double total, double per})? _waterTotalsFromSummary(
      String? summary) {
    final s = _txt(summary, fallback: '').trim();
    if (s.isEmpty || s.contains('لا يوجد')) return null;
    final totalMatch = RegExp(r'إجمالي\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(s);
    final perMatch = RegExp(r'القسط\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(s);
    if (totalMatch == null || perMatch == null) return null;

    final total = double.tryParse(totalMatch.group(1) ?? '');
    final per = double.tryParse(perMatch.group(1) ?? '');
    if (total == null || per == null || total <= 0 || per <= 0) return null;
    return (total: total, per: per);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static double _scheduledWaterInstallmentAmountForDue(
      Contract c, DateTime due) {
    try {
      final boxId = boxName('servicesConfig');
      if (!Hive.isBoxOpen(boxId)) return 0.0;
      final box = Hive.box<Map>(boxId);
      final raw = box.get('${c.propertyId}::water');
      if (raw is! Map) return 0.0;

      final cfg = Map<String, dynamic>.from(raw);
      final mode = (cfg['waterBillingMode'] ?? cfg['mode'] ?? '').toString();
      final method =
          (cfg['waterSharedMethod'] ?? cfg['splitMethod'] ?? '').toString();
      if (mode != 'shared' || method != 'fixed') return 0.0;

      final linked = (cfg['waterLinkedContractId'] ?? '').toString();
      if (linked.isNotEmpty && linked != c.id) return 0.0;

      final rows = cfg['waterInstallments'];
      if (rows is! List) return 0.0;

      final dueIso = _dateOnly(due).toIso8601String();
      for (final row in rows) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        if ((m['dueDate'] ?? '').toString() != dueIso) continue;
        return ((m['amount'] as num?)?.toDouble() ?? 0.0);
      }
    } catch (_) {}
    return 0.0;
  }

  static Future<void> shareContractDetailsPdf({
    required BuildContext context,
    required Contract contract,
    Tenant? tenant,
    Property? property,
    String? waterSummary,
    String? ejarContractNo,
  }) async {
    try {
      debugPrint(
        '[PDF_TRACE] shareContractDetailsPdf start '
        'contractId=${contract.id} '
        'term=${contract.term} '
        'paymentCycle=${contract.paymentCycle} '
        'start=${_fmtDate(contract.startDate)} '
        'end=${_fmtDate(contract.endDate)}',
      );
      final (regular, bold) = await _loadFonts();
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 15, height: 1.65);
      final summaryStyle = pw.TextStyle(
        font: regular,
        fontSize: 16,
        height: 1.85,
        color: PdfColor.fromInt(0xFF0F172A),
      );
      final sectionTitleStyle = pw.TextStyle(
        font: bold,
        fontSize: 21,
        color: PdfColor.fromInt(0xFF0F172A),
      );
      final answerStyle = pw.TextStyle(
        font: bold,
        fontSize: 16,
        height: 1.85,
        color: PdfColor.fromInt(0xFF0B5FB3),
      );
      final footerLabelStyle = pw.TextStyle(
        font: bold,
        fontSize: 14,
        color: PdfColor.fromInt(0xFF0F172A),
      );
      final footerValueStyle = pw.TextStyle(
        font: bold,
        fontSize: 14,
        color: PdfColor.fromInt(0xFF0B5FB3),
      );
      final doc = pw.Document();

      final office = await _loadOfficeProfile();
      final officeName = _txt(office['name'], fallback: '-');
      final officeAddress = _txt(office['address'], fallback: '-');
      final officeMobile = _txt(office['mobile'], fallback: '-');
      final officePhone = _txt(office['phone'], fallback: '-');
      final officeCommercial = _txt(office['commercial'], fallback: '-');
      final officeTax = _txt(
        office['tax'] ?? office['vat'] ?? office['tax_no'] ?? office['vat_no'],
        fallback: '-',
      );
      final officeLogoBytes = await _decodeOfficeLogoBytes(office);

      final issueDate = contract.createdAt;
      final issueDateG = _fmtDate(issueDate);
      final issueDateH = _fmtHijriDate(issueDate);
      final tenantName =
          _txt(tenant?.fullName ?? '-', fallback: 'المستأجر الكريم');
      final (propertyRef, propertyAddress) =
          await _resolveMaintenancePropertyInfo(
        property: property,
        propertyId: contract.propertyId,
      );
      final termLabel = _contractTermLabel(contract);
      final paymentLabel = _contractPaymentLabel(contract);
      final installmentsCount = _contractInstallmentsCount(contract);
      final installmentValue = installmentsCount > 0
          ? (contract.totalAmount / installmentsCount)
          : contract.totalAmount;
      final ejarNoRaw =
          _txt(ejarContractNo ?? contract.ejarContractNo, fallback: '').trim();
      final ejarNo = _txt(ejarNoRaw, fallback: '-');
      final termLabelNormalized = _txt(termLabel, fallback: '');
      final paymentLabelNormalized = _txt(paymentLabel, fallback: '');
      final termLabelDisplay = _rtlIsolate(termLabelNormalized, fallback: '');
      final paymentLabelDisplay =
          _rtlIsolate(paymentLabelNormalized, fallback: '');
      final rawEjarNo = (contract.ejarContractNo ?? '').trim();
      final termRunes =
          termLabel.runes.map((r) => r.toRadixString(16)).join(',');
      final paymentRunes =
          paymentLabel.runes.map((r) => r.toRadixString(16)).join(',');
      debugPrint(
        '[PDF_TRACE] labels '
        'termRaw=${contract.term} termLabel="$termLabel" termLabelNormalized="$termLabelNormalized" '
        'termRunes=$termRunes '
        'paymentRaw=${contract.paymentCycle} paymentLabel="$paymentLabel" '
        'paymentLabelNormalized="$paymentLabelNormalized" paymentRunes=$paymentRunes',
      );
      debugPrint(
        '[PDF_TRACE] ejar '
        'param="$ejarContractNo" '
        'contract.ejarContractNo="$rawEjarNo" '
        'resolvedForPdf="$ejarNo"',
      );
      final waterTotals = _waterTotalsFromSummary(waterSummary);
      final totalRentValue = contract.totalAmount.abs();
      final totalWaterValue = waterTotals?.total ?? 0.0;
      final grandTotalValue = totalRentValue + totalWaterValue;
      final installmentWithWaterValue =
          installmentValue + (waterTotals?.per ?? 0.0);
      final dueDates = _contractInstallmentDates(contract).toList();
      final invoices = <Invoice>[];
      try {
        final invBoxName = boxName(kInvoicesBox);
        final invBox = Hive.isBoxOpen(invBoxName)
            ? Hive.box<Invoice>(invBoxName)
            : await Hive.openBox<Invoice>(invBoxName);
        invoices.addAll(
          invBox.values.where((i) => i.contractId == contract.id).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
        );
      } catch (_) {}

      // Ensure PDF includes all actual invoice dues (including canceled ones)
      // even if contract endDate was shortened after termination.
      final dueSet = <String>{
        for (final d in dueDates) _fmtDate(DateTime(d.year, d.month, d.day)),
      };
      for (final inv in invoices) {
        final d = DateTime(inv.dueDate.year, inv.dueDate.month, inv.dueDate.day);
        final k = _fmtDate(d);
        if (!dueSet.contains(k)) {
          dueDates.add(d);
          dueSet.add(k);
        }
      }
      dueDates.sort((a, b) => a.compareTo(b));
      debugPrint(
        '[PDF_TRACE] shareContractDetailsPdf data '
        'dueDates=${dueDates.length} '
        'invoices=${invoices.length}',
      );
      final totalPaid = invoices.where((i) => !i.isCanceled).fold<double>(
        0.0,
        (sum, i) {
          final amountAbs = i.amount.abs();
          final paidAbs = i.paidAmount.abs();
          return sum + (paidAbs > amountAbs ? amountAbs : paidAbs);
        },
      );
      final totalRemaining =
          (grandTotalValue - totalPaid).clamp(0.0, double.infinity);

      final byDue = <String, List<Invoice>>{};
      for (final inv in invoices) {
        final key = _fmtDate(inv.dueDate);
        byDue.putIfAbsent(key, () => <Invoice>[]).add(inv);
      }
      final now = KsaTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);

      final rows = <List<String>>[];
      for (int i = 0; i < dueDates.length; i++) {
        final due = dueDates[i];
        final dueKey = _fmtDate(due);
        Invoice? matched;
        final exact = byDue[dueKey];
        if (exact != null && exact.isNotEmpty) {
          matched = exact.removeAt(0);
        } else if (i < invoices.length) {
          matched = invoices[i];
        }
        final isPaid = matched != null &&
            !matched.isCanceled &&
            (matched.paidAmount >= (matched.amount - 0.000001));
        String status;
        if (matched?.isCanceled == true) {
          status = 'ملغاة';
        } else if (isPaid) {
          status = 'مدفوع';
        } else {
          final dueOnly = DateTime(due.year, due.month, due.day);
          if (dueOnly.isBefore(todayOnly)) {
            status = 'متأخرة';
          } else if (dueOnly.isAtSameMomentAs(todayOnly)) {
            status = 'مستحقة';
          } else {
            status = 'قادمة';
          }
        }
        final waterAmountForDue =
            _scheduledWaterInstallmentAmountForDue(contract, due);
        final rowValue = installmentValue.abs() + waterAmountForDue;
        final periodEnd =
            _addMonthsSafe(due, _monthsPerCycleFromContract(contract));
        final duePeriod = 'من ${_fmtDate(due)} إلى ${_fmtDate(periodEnd)}';
        rows.add(<String>[
          status,
          duePeriod,
          '${_fmtMoney(rowValue)} ريال',
          'الدفعة ${i + 1}',
        ]);
      }
      debugPrint(
        '[PDF_TRACE] shareContractDetailsPdf rows=${rows.length} '
        'firstRow=${rows.isNotEmpty ? rows.first.join(' | ') : 'EMPTY'}',
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'ت م: $issueDateG',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 14,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'ت هـ: $issueDateH',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 14,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'عقد إيجار',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 32,
                  color: PdfColor.fromInt(0xFF0B3B8C),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('بيانات المكتب',
                        style: pw.TextStyle(font: bold, fontSize: 17)),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(officeName,
                                style: pw.TextStyle(font: bold, fontSize: 16)),
                            pw.Text('العنوان: $officeAddress',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 15)),
                            pw.Text(
                              'الجوال: $officeMobile   |   الهاتف: $officePhone',
                              style: pw.TextStyle(font: regular, fontSize: 15),
                            ),
                            pw.Text('رقم السجل: $officeCommercial',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 15)),
                            if (officeTax != '-')
                              pw.Text('الرقم الضريبي: $officeTax',
                                  style: pw.TextStyle(
                                      font: regular, fontSize: 15)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Container(
                        width: 52,
                        height: 52,
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFCBD5E1)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 8,
                          verticalRadius: 8,
                          child: officeLogoBytes == null
                              ? pw.Center(
                                  child: pw.Text(
                                    'شعار',
                                    style: pw.TextStyle(
                                        font: regular, fontSize: 11),
                                  ),
                                )
                              : pw.Image(
                                  pw.MemoryImage(officeLogoBytes),
                                  fit: pw.BoxFit.cover,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 78),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFFCFDFF),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('تفاصيل العقد', style: sectionTitleStyle),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEAF2FF),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.RichText(
                      textDirection: pw.TextDirection.rtl,
                      text: pw.TextSpan(
                        style: summaryStyle,
                        children: [
                          pw.TextSpan(text: 'عقد السيد المستأجر '),
                          pw.TextSpan(text: tenantName, style: answerStyle),
                          pw.TextSpan(text: ' | مرجع العقار: '),
                          pw.TextSpan(text: propertyRef, style: answerStyle),
                          pw.TextSpan(text: ' | مدة العقد: '),
                          pw.TextSpan(
                            text:
                                '$termLabelDisplay من ${_fmtDate(contract.startDate)} إلى ${_fmtDate(contract.endDate)}',
                            style: answerStyle,
                          ),
                          pw.TextSpan(text: ' | الدفع: '),
                          pw.TextSpan(
                              text: paymentLabelDisplay, style: answerStyle),
                          pw.TextSpan(text: ' | إجمالي قيمة الإيجار: '),
                          pw.TextSpan(
                            text: '${_fmtMoney(contract.totalAmount)} ريال',
                            style: answerStyle,
                          ),
                          if (waterTotals != null) ...[
                            pw.TextSpan(text: ' | إجمالي قيمة المياه: '),
                            pw.TextSpan(
                              text: '${_fmtMoney(waterTotals.total)} ريال',
                              style: answerStyle,
                            ),
                          ],
                          pw.TextSpan(text: ' | إجمالي الدفعات: '),
                          pw.TextSpan(
                            text: '$installmentsCount',
                            style: answerStyle,
                          ),
                          pw.TextSpan(text: ' | قيمة الدفعة: '),
                          pw.TextSpan(
                            text:
                                '${_fmtMoney(installmentWithWaterValue)} ريال',
                            style: answerStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.RichText(
                      textDirection: pw.TextDirection.rtl,
                      text: pw.TextSpan(
                        style: bodyStyle,
                        children: [
                          const pw.TextSpan(text: 'رقم العقد: '),
                          pw.TextSpan(text: ejarNo, style: answerStyle),
                        ],
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.RichText(
                      textDirection: pw.TextDirection.rtl,
                      text: pw.TextSpan(
                        style: bodyStyle,
                        children: [
                          const pw.TextSpan(text: 'عنوان العقار: '),
                          pw.TextSpan(
                              text: propertyAddress, style: answerStyle),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.NewPage(),
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text('جدول الدفعات المجدولة', style: sectionTitleStyle),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['الحالة', 'تاريخ الاستحقاق', 'القيمة', 'الدفعة'],
              data: rows,
              cellAlignment: pw.Alignment.centerRight,
              headerStyle: pw.TextStyle(font: bold, fontSize: 15),
              cellStyle: pw.TextStyle(
                font: regular,
                fontSize: 14,
                color: PdfColor.fromInt(0xFF0F172A),
              ),
              cellBuilder: (index, data, _) {
                if (index != 1) return null;
                final periodText = _txt(data, fallback: '').trim();
                final match = RegExp(
                  r'^من\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\s+إلى\s+([0-9]{4}-[0-9]{2}-[0-9]{2})$',
                ).firstMatch(periodText);
                if (match == null) return null;
                final start = match.group(1) ?? '';
                final end = match.group(2) ?? '';
                return pw.RichText(
                  textDirection: pw.TextDirection.rtl,
                  text: pw.TextSpan(
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 14,
                      color: PdfColor.fromInt(0xFF0F172A),
                    ),
                    children: [
                      pw.TextSpan(text: 'من '),
                      pw.TextSpan(
                        text: start,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 14,
                          color: PdfColor.fromInt(0xFF0B5FB3),
                        ),
                      ),
                      pw.TextSpan(text: ' إلى '),
                      pw.TextSpan(
                        text: end,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 14,
                          color: PdfColor.fromInt(0xFF0B5FB3),
                        ),
                      ),
                    ],
                  ),
                );
              },
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB)),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(6),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.RichText(
                        textDirection: pw.TextDirection.rtl,
                        text: pw.TextSpan(
                          style: footerLabelStyle,
                          children: [
                            const pw.TextSpan(text: 'الإجمالي: '),
                            pw.TextSpan(
                              text: '${_fmtMoney(grandTotalValue)} ريال',
                              style: footerValueStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.RichText(
                        textDirection: pw.TextDirection.rtl,
                        text: pw.TextSpan(
                          style: footerLabelStyle,
                          children: [
                            const pw.TextSpan(text: 'المدفوع: '),
                            pw.TextSpan(
                              text: '${_fmtMoney(totalPaid)} ريال',
                              style: footerValueStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.RichText(
                        textDirection: pw.TextDirection.rtl,
                        text: pw.TextSpan(
                          style: footerLabelStyle,
                          children: [
                            const pw.TextSpan(text: 'المتبقي: '),
                            pw.TextSpan(
                              text: '${_fmtMoney(totalRemaining)} ريال',
                              style: footerValueStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      final shared = await _shareDoc(
        context: context,
        doc: doc,
        filename:
            'contract_${contract.id}_details_${KsaTime.now().millisecondsSinceEpoch}.pdf',
      );
      debugPrint(
        '[PDF_TRACE] shareContractDetailsPdf completed shared=$shared',
      );
    } catch (_) {
      debugPrint('[PDF_TRACE] shareContractDetailsPdf failed');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareContractInvoicesPdf({
    required BuildContext context,
    required String contractId,
    required List<Invoice> invoices,
    Contract? contract,
    Tenant? tenant,
    Property? property,
  }) async {
    try {
      debugPrint(
        '[PDF_TRACE] shareContractInvoicesPdf start '
        'contractId=$contractId invoices=${invoices.length}',
      );
      final (regular, bold) = await _loadFonts();
      final titleStyle = pw.TextStyle(font: bold, fontSize: 18);
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 11);
      final footerStyle = pw.TextStyle(font: bold, fontSize: 12);
      final doc = pw.Document();
      final activeInvoices = invoices.where((i) => !i.isCanceled).toList();
      final totalAmount = activeInvoices.fold<double>(
        0.0,
        (sum, i) => sum + i.amount.abs(),
      );
      final totalPaid = activeInvoices.fold<double>(
        0.0,
        (sum, i) {
          final amountAbs = i.amount.abs();
          final paidAbs = i.paidAmount.abs();
          return sum + (paidAbs > amountAbs ? amountAbs : paidAbs);
        },
      );
      final totalRemaining =
          (totalAmount - totalPaid).clamp(0.0, double.infinity);
      final (propertyRef, _) = await _resolveMaintenancePropertyInfo(
        property: property,
        propertyId: contract?.propertyId ?? '',
      );
      final rows = invoices
          .map((i) => <String>[
                _invoicePeriodLabel(i, contract),
                _fmtMoney(i.amount),
                _fmtMoney(i.paidAmount),
                _fmtMoney(i.remaining),
                i.isCanceled ? 'ملغاة' : (i.isPaid ? 'مدفوعة' : 'غير مدفوعة'),
              ])
          .toList();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            _sectionTitle('سجل سندات العقد', titleStyle),
            _kv('رقم العقد', _txt(contract?.serialNo ?? contractId), bodyStyle),
            _kv('المستأجر', _txt(tenant?.fullName ?? '-'), bodyStyle),
            _kv('العقار', propertyRef, bodyStyle),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                'فترة السداد',
                'الإجمالي',
                'المدفوع',
                'المتبقي',
                'الحالة'
              ],
              data: rows,
              cellAlignment: pw.Alignment.centerRight,
              headerStyle: pw.TextStyle(font: bold, fontSize: 10),
              cellStyle: pw.TextStyle(font: regular, fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB)),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(6),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'الإجمالي: ${_fmtMoney(totalAmount)} ريال',
                        style: footerStyle,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'المدفوع: ${_fmtMoney(totalPaid)} ريال',
                        style: footerStyle,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'المتبقي: ${_fmtMoney(totalRemaining)} ريال',
                        style: footerStyle,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
      );
      await _shareDoc(
        context: context,
        doc: doc,
        filename: 'contract_${contractId}_invoices.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareInvoiceDetailsPdf({
    required BuildContext context,
    required Invoice invoice,
    Tenant? tenant,
    Property? property,
    Contract? contract,
    String? ejarContractNo,
    double? rentOnlyAmount,
    double? waterAmount,
    String? statementText,
  }) async {
    try {
      final (regular, bold) = await _loadFonts();
      final titleStyle = pw.TextStyle(font: bold, fontSize: 18);
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 12);
      final periodDateColor = PdfColor.fromInt(0xFF0B5FB3);
      final doc = pw.Document();
      final office = await _loadOfficeProfile();
      final isManualReceipt = _pdfInvoiceIsManual(invoice);
      final isOwnerPayout = _pdfInvoiceIsOwnerPayout(invoice);
      final isOwnerAdjustment = _pdfInvoiceIsOwnerAdjustment(invoice);
      final isOwnerVoucher = isOwnerPayout || isOwnerAdjustment;
      final isContractReceipt =
          !isManualReceipt && (contract != null || invoice.contractId.isNotEmpty);
      final useReceiptLayout = isContractReceipt || isManualReceipt;

      final officeName = _txt(office['name'], fallback: '-');
      final officeAddress = _txt(office['address'], fallback: '-');
      final officeMobile = _txt(office['mobile'], fallback: '-');
      final officePhone = _txt(office['phone'], fallback: '-');
      final officeCommercial = _txt(office['commercial'], fallback: '-');
      final officeLogoBytes = await _decodeOfficeLogoBytes(office);
      final officeTax = _txt(
        office['tax'] ?? office['vat'] ?? office['tax_no'] ?? office['vat_no'],
        fallback: '-',
      );

      final ejarNo =
          _txt((ejarContractNo ?? contract?.ejarContractNo) ?? '', fallback: '')
              .trim();
      final rentPeriod = _invoicePeriodLabel(invoice, contract);
      final typeLabel = invoice.amount < 0 ? 'صرف' : 'قبض';
      final headerTitle = invoice.amount < 0 ? 'سند صرف' : 'سند قبض';
      final issueDate = invoice.issueDate;
      final issueDateG = _fmtDate(issueDate);
      final issueDateH = _fmtHijriDate(issueDate);
      final manualParty = _pdfInvoicePartyName(invoice.note);
      final manualProperty = _pdfInvoicePropertyName(invoice.note);
      final propertySnapshot = contract?.propertySnapshot;
      final buildingSnapshot = contract?.buildingSnapshot;
      final unitName = (property?.name ??
              _pdfMapString(propertySnapshot, 'name') ??
              manualProperty ??
              '')
          .trim();
      var buildingName = _pdfMapString(buildingSnapshot, 'name') ?? '';
      final hasBuilding =
          (property?.parentBuildingId?.trim().isNotEmpty ?? false) ||
              (_pdfMapString(propertySnapshot, 'parentBuildingId') ?? '')
                  .trim()
                  .isNotEmpty ||
              buildingName.trim().isNotEmpty;
      if (hasBuilding && buildingName.trim().isEmpty) {
        final parentId = (property?.parentBuildingId ?? '').trim();
        if (parentId.isNotEmpty) {
          try {
            final boxNameValue = boxName(kPropertiesBox);
            final pBox = Hive.isBoxOpen(boxNameValue)
                ? Hive.box<Property>(boxNameValue)
                : await Hive.openBox<Property>(boxNameValue);
            buildingName = (pBox.get(parentId)?.name ?? '').trim();
          } catch (_) {}
        }
      }
      final propertyRef = _composePdfPropertyReference(
        unitName: unitName,
        buildingName: hasBuilding ? buildingName : '',
      );
      final noteText = _pdfInvoiceDisplayNote(invoice.note);
      final displayStatementText =
          _txt(statementText, fallback: noteText).trim();
      final receiptStatementText = _txt(displayStatementText, fallback: '').trim();
      final partyValue = isManualReceipt
          ? _txt(manualParty ?? tenant?.fullName, fallback: '-')
          : _txt(tenant?.fullName, fallback: '-');
      final propertyValue = _txt(propertyRef, fallback: '-');
      final manualPartyLabel = isManualReceipt
          ? (isOwnerVoucher
              ? 'المالك'
              : (tenant == null
                  ? 'الطرف'
                  : (_pdfTenantIsProvider(tenant)
                      ? 'مقدم الخدمة'
                      : 'المستأجر')))
          : 'الطرف';
      final manualDescriptionFallback = isOwnerPayout
          ? 'تحويل مستحق المالك'
          : isOwnerAdjustment
              ? 'خصم/تسوية للمالك'
              : (invoice.amount < 0 ? 'سند صرف يدوي' : 'سند قبض يدوي');
      final showManualPropertyRef = isManualReceipt &&
          _txt(propertyValue, fallback: '').trim().isNotEmpty &&
          _txt(propertyValue, fallback: '').trim() != '-';
      final useReceiptStatementLineItem = !isManualReceipt &&
          isContractReceipt &&
          receiptStatementText.isNotEmpty;
      final manualTableDateValue = _pdfInvoiceHasServiceOrigin(invoice.note)
          ? _fmtDate(invoice.dueDate)
          : issueDateG;
      final tableHeaders = isManualReceipt
          ? ['المبلغ', _pdfInvoiceTableDateHeader(invoice), 'البيان']
          : const ['المبلغ', 'الفترة/التاريخ', 'البيان'];
      final dateColumnIndex = 1;
      final manualTableColumnWidths = isManualReceipt
          ? const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(3.4),
              2: pw.FlexColumnWidth(5.4),
            }
          : null;

      final rentValue = (rentOnlyAmount ?? invoice.amount).toDouble().abs();
      final waterValue = (waterAmount ?? 0).toDouble().abs();
      final totalValue = invoice.amount.toDouble().abs();
      final isDailyContract = !isManualReceipt && _isDailyContract(contract);
      final dailyRate = _dailyInvoiceRate(contract);
      final paymentMethodText = _txt(invoice.paymentMethod, fallback: '-');
      final showPaymentMethod = _pdfInvoiceShouldShowPaymentMethod(invoice);
      final lineItems = isManualReceipt
          ? <List<String>>[
              [
                '${_fmtMoney(totalValue)} ريال',
                manualTableDateValue,
                _txt(
                  displayStatementText,
                  fallback: manualDescriptionFallback,
                ),
              ],
            ]
          : useReceiptStatementLineItem
              ? <List<String>>[
                  [
                    '${_fmtMoney(totalValue)} ريال',
                    rentPeriod,
                    receiptStatementText,
                  ],
                ]
              : <List<String>>[
              if (rentValue > 0)
                ['${_fmtMoney(rentValue)} ريال', rentPeriod, 'إيجار'],
              if (waterValue > 0)
                ['${_fmtMoney(waterValue)} ريال', rentPeriod, 'مياه'],
            ];
      if (lineItems.isEmpty) {
        lineItems.add([
          '${_fmtMoney(totalValue)} ريال',
          isManualReceipt ? manualTableDateValue : rentPeriod,
          isManualReceipt ? manualDescriptionFallback : 'سند',
        ]);
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
          textDirection: pw.TextDirection.rtl,
          build: (_) => useReceiptLayout
              ? [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColor.fromInt(0xFFF8FAFC),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              '\u062a \u0645: $issueDateG',
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 13,
                                color: PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Text(
                              '\u062a \u0647\u0640: $issueDateH',
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 13,
                                color: PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Text(
                      headerTitle,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 24,
                        color: PdfColor.fromInt(0xFF0B3B8C),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColor.fromInt(0xFFF8FAFC),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Align(
                          alignment: pw.Alignment.center,
                          child: pw.Text('بيانات المكتب',
                              style: pw.TextStyle(font: bold, fontSize: 16)),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(officeName,
                                      style: pw.TextStyle(
                                          font: bold, fontSize: 14)),
                                  pw.Text('العنوان: $officeAddress',
                                      style: pw.TextStyle(
                                          font: regular, fontSize: 13)),
                                  pw.Text(
                                      'الجوال: $officeMobile   |   الهاتف: $officePhone',
                                      style: pw.TextStyle(
                                          font: regular, fontSize: 13)),
                                  pw.Text('رقم السجل: $officeCommercial',
                                      style: pw.TextStyle(
                                          font: regular, fontSize: 13)),
                                  if (officeTax != '-')
                                    pw.Text('الرقم الضريبي: $officeTax',
                                        style: pw.TextStyle(
                                            font: regular, fontSize: 13)),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 10),
                            pw.Container(
                              width: 52,
                              height: 52,
                              decoration: pw.BoxDecoration(
                                borderRadius: pw.BorderRadius.circular(8),
                                border: pw.Border.all(
                                  color: PdfColor.fromInt(0xFFCBD5E1),
                                ),
                              ),
                              child: pw.ClipRRect(
                                horizontalRadius: 8,
                                verticalRadius: 8,
                                child: officeLogoBytes == null
                                    ? pw.Center(
                                        child: pw.Text(
                                          'شعار',
                                          style: pw.TextStyle(
                                              font: regular, fontSize: 10),
                                        ),
                                      )
                                    : pw.Image(
                                        pw.MemoryImage(officeLogoBytes),
                                        fit: pw.BoxFit.cover,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Align(
                          alignment: pw.Alignment.center,
                          child: pw.Text('بيانات السند',
                              style: pw.TextStyle(font: bold, fontSize: 16)),
                        ),
                        pw.SizedBox(height: 6),
                        _kv('رقم السند', _txt(invoice.serialNo ?? invoice.id),
                            pw.TextStyle(font: regular, fontSize: 13)),
                        _kv('نوع السند', typeLabel,
                            pw.TextStyle(font: regular, fontSize: 13)),
                        if (isManualReceipt)
                          _kv(
                            manualPartyLabel,
                            partyValue,
                            pw.TextStyle(font: regular, fontSize: 13),
                          )
                        else
                          _kv(
                            'استلمنا من',
                            'السيد/ ${_txt(tenant?.fullName ?? '-')} (المستأجر)',
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (showPaymentMethod)
                          _kv(
                            'طريقة الدفع',
                            paymentMethodText,
                            pw.TextStyle(font: regular, fontSize: 13),
                          )
                        else if (!isManualReceipt &&
                            !useReceiptStatementLineItem)
                          _kv(
                            'عن',
                            'إيجار مبلغ ${_fmtMoney(totalValue)} ريال',
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (!isManualReceipt || showManualPropertyRef)
                          _kv(
                            'مرجع العقار',
                            propertyValue,
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (!isManualReceipt)
                          _kv(
                            'رقم عقد الإيجار',
                            _txt(
                              ejarNo.isNotEmpty
                                  ? ejarNo
                                  : (contract?.serialNo ?? invoice.contractId),
                            ),
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (!isManualReceipt)
                          _kv(
                            'تاريخ الاستحقاق',
                            rentPeriod,
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (isDailyContract && dailyRate != null)
                          _kv(
                            'قيمة اليوم',
                            '${_fmtMoney(dailyRate)} ${invoice.currency}',
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                        if (isDailyContract)
                          _kv(
                            'إجمالي المدفوع',
                            '${_fmtMoney(invoice.paidAmount)} ${invoice.currency}',
                            pw.TextStyle(font: regular, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.TableHelper.fromTextArray(
                    headers: tableHeaders,
                    data: lineItems,
                    columnWidths: manualTableColumnWidths,
                    cellAlignment: pw.Alignment.centerRight,
                    headerStyle: pw.TextStyle(font: bold, fontSize: 13),
                    cellStyle: pw.TextStyle(font: regular, fontSize: 12.5),
                    cellBuilder: (index, data, _) {
                      if (index != dateColumnIndex) return null;
                      return _periodTextWithDateHighlight(
                        _txt(data, fallback: '').trim(),
                        baseStyle: pw.TextStyle(font: regular, fontSize: 12.5),
                        dateColor: periodDateColor,
                      );
                    },
                    headerDecoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFE5E7EB)),
                    cellPadding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                  ),
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 6),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                      color: PdfColor.fromInt(0xFFF8FAFC),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            'الإجمالي: ${_fmtMoney(totalValue)} ريال',
                            style: pw.TextStyle(font: bold, fontSize: 14),
                            textDirection: pw.TextDirection.rtl,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                      borderRadius: pw.BorderRadius.circular(6),
                      color: PdfColor.fromInt(0xFFF8FAFC),
                    ),
                    child: pw.Text(
                      'المبلغ كتابة: ${_amountInWordsAr(totalValue)} ريال لا غير.',
                      style: pw.TextStyle(font: regular, fontSize: 13),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ]
              : [
                  _sectionTitle('تفاصيل السند', titleStyle),
                  _kv('رقم السند', _txt(invoice.serialNo ?? invoice.id),
                      bodyStyle),
                  _kv(
                    isManualReceipt
                        ? (isOwnerVoucher ? 'المالك' : 'الطرف')
                        : 'المستأجر',
                    partyValue,
                    bodyStyle,
                  ),
                  _kv('العقار', propertyValue, bodyStyle),
                  if (!isManualReceipt)
                    _kv('رقم عقد الإيجار',
                        _txt(contract?.serialNo ?? invoice.contractId),
                        bodyStyle),
                  _kv('تاريخ الإصدار', _fmtDate(invoice.issueDate), bodyStyle),
                  _kv(
                    'تاريخ الاستحقاق',
                    isDailyContract ? rentPeriod : _fmtDate(invoice.dueDate),
                    bodyStyle,
                  ),
                  if (isDailyContract && dailyRate != null)
                    _kv('قيمة اليوم', '${_fmtMoney(dailyRate)} ${invoice.currency}',
                        bodyStyle),
                  _kv(
                      'قيمة الدفعة (الإيجار)',
                      '${_fmtMoney(rentOnlyAmount ?? invoice.amount)} ${invoice.currency}',
                      bodyStyle),
                  _kv(
                      'قسط المياه',
                      '${_fmtMoney(waterAmount ?? 0)} ${invoice.currency}',
                      bodyStyle),
                  _kv(
                      'الإجمالي',
                      '${_fmtMoney(invoice.amount)} ${invoice.currency}',
                      bodyStyle),
                  _kv(
                      isDailyContract ? 'إجمالي المدفوع' : 'المدفوع',
                      '${_fmtMoney(invoice.paidAmount)} ${invoice.currency}',
                      bodyStyle),
                  _kv(
                      'المتبقي',
                      '${_fmtMoney(invoice.remaining)} ${invoice.currency}',
                      bodyStyle),
                  if (showPaymentMethod)
                    _kv('طريقة الدفع', paymentMethodText, bodyStyle),
                  _kv(isManualReceipt ? 'البيان' : 'ملاحظات',
                      _txt(displayStatementText, fallback: '-'), bodyStyle),
                  pw.SizedBox(height: 12),
                ],
        ),
      );
      await _shareDoc(
        context: context,
        doc: doc,
        filename: 'invoice_${invoice.id}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareMaintenanceDetailsPdf({
    required BuildContext context,
    required MaintenanceReceiptDetails details,
    Property? property,
    List<Invoice> relatedInvoices = const [],
  }) async {
    try {
      final (regular, bold) = await _loadFonts();
      final doc = pw.Document();
      final office = await _loadOfficeProfile();

      final officeName = _txt(office['name'], fallback: '-');
      final officeAddress = _txt(office['address'], fallback: '-');
      final officeMobile = _txt(office['mobile'], fallback: '-');
      final officePhone = _txt(office['phone'], fallback: '-');
      final officeCommercial = _txt(office['commercial'], fallback: '-');
      final officeLogoBytes = await _decodeOfficeLogoBytes(office);
      final officeTax = _txt(
        office['tax'] ?? office['vat'] ?? office['tax_no'] ?? office['vat_no'],
        fallback: '-',
      );

      final issueDate = details.createdAt;
      final issueDateG = _fmtDate(issueDate);
      final issueDateH = _fmtHijriDate(issueDate);
      final receiptInfoStyle = pw.TextStyle(font: regular, fontSize: 13);
      final sharedServiceVoucherLabel =
          _pdfMaintenanceSharedServiceVoucherLabel(details);
      final maintenanceVoucherTypeLabel =
          _pdfMaintenanceVoucherDisplayType(details);
      final isWaterCompanyOfficeExpenseVoucher =
          _pdfIsWaterCompanyOfficeExpenseVoucher(details, relatedInvoices);
      final isSharedServiceVoucher = sharedServiceVoucherLabel.isNotEmpty;
      final cycleDateValue = _fmtDate(_pdfMaintenanceEffectiveCycleDate(details));
      final tableDateHeader =
          (isSharedServiceVoucher || isWaterCompanyOfficeExpenseVoucher)
              ? 'تاريخ الدورة'
              : 'التاريخ';
      String tenantName = '-';
      final tenantId = (details.tenantId ?? '').trim();
      if (tenantId.isNotEmpty) {
        try {
          final tBoxName = boxName(kTenantsBox);
          final tBox = Hive.isBoxOpen(tBoxName)
              ? Hive.box<Tenant>(tBoxName)
              : await Hive.openBox<Tenant>(tBoxName);
          final t = tBox.get(tenantId);
          if (t != null) tenantName = _txt(t.fullName);
        } catch (_) {}
      }
      final (propertyRef, _) = await _resolveMaintenancePropertyInfo(
        property: property,
        propertyId: details.propertyId,
      );
      final receiptNo = _txt(
        relatedInvoices.isNotEmpty
            ? (relatedInvoices.first.serialNo ?? relatedInvoices.first.id)
            : (details.invoiceId ?? details.id),
      );
      final costValue = '${_fmtMoney(details.cost)} ريال';
      final endDateValue =
          _fmtDate(details.completedDate ?? details.executionDeadline);
      final tableRows = relatedInvoices.isNotEmpty
          ? relatedInvoices
              .map((i) => <String>[
                    '${_fmtMoney(i.amount.abs())} ريال',
                    (isSharedServiceVoucher || isWaterCompanyOfficeExpenseVoucher)
                        ? cycleDateValue
                        : _fmtDate(i.dueDate),
                    _pdfMaintenanceCompactStatementText(
                      (i.note ?? '').trim().isEmpty ? details.description : i.note,
                      propertyRef: propertyRef,
                      fallback: details.description,
                      includeTitle: !isWaterCompanyOfficeExpenseVoucher,
                    ),
                  ])
              .toList()
          : <List<String>>[
              <String>[
                costValue,
                (isSharedServiceVoucher || isWaterCompanyOfficeExpenseVoucher)
                    ? cycleDateValue
                    : endDateValue,
                _pdfMaintenanceCompactStatementText(
                  details.description,
                  propertyRef: propertyRef,
                  includeTitle: !isWaterCompanyOfficeExpenseVoucher,
                ),
              ],
            ];
      final amountWordsValue = relatedInvoices.isNotEmpty
          ? relatedInvoices.fold<double>(0.0, (sum, i) => sum + i.amount.abs())
          : details.cost.abs();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'ت م: $issueDateG',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 13,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'ت هـ: $issueDateH',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 13,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'سند صرف',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 24,
                  color: PdfColor.fromInt(0xFF0B3B8C),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('بيانات المكتب',
                        style: pw.TextStyle(font: bold, fontSize: 16)),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(officeName,
                                style: pw.TextStyle(font: bold, fontSize: 14)),
                            pw.Text('العنوان: $officeAddress',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            pw.Text(
                                'الجوال: $officeMobile   |   الهاتف: $officePhone',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            pw.Text('رقم السجل: $officeCommercial',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            if (officeTax != '-')
                              pw.Text('الرقم الضريبي: $officeTax',
                                  style: pw.TextStyle(
                                      font: regular, fontSize: 13)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Container(
                        width: 52,
                        height: 52,
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFCBD5E1)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 8,
                          verticalRadius: 8,
                          child: officeLogoBytes == null
                              ? pw.Center(
                                  child: pw.Text(
                                    'شعار',
                                    style: pw.TextStyle(
                                        font: regular, fontSize: 10),
                                  ),
                                )
                              : pw.Image(
                                  pw.MemoryImage(officeLogoBytes),
                                  fit: pw.BoxFit.cover,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('بيانات السند',
                        style: pw.TextStyle(font: bold, fontSize: 16)),
                  ),
                  pw.SizedBox(height: 6),
                  _kv('رقم السند', receiptNo, receiptInfoStyle),
                  _kv(
                    'نوع السند',
                    maintenanceVoucherTypeLabel,
                    receiptInfoStyle,
                  ),
                  _kv('عنوان الطلب', _txt(details.title), receiptInfoStyle),
                  if (!isWaterCompanyOfficeExpenseVoucher)
                    _kv('الأولوية', _maintenancePriorityLabel(details.priority),
                        receiptInfoStyle),
                  if (!isWaterCompanyOfficeExpenseVoucher &&
                      _hasPdfValue(details.assignedTo))
                    _kv('مقدم الخدمة', _txt(details.assignedTo),
                        receiptInfoStyle),
                  if (isSharedServiceVoucher ||
                      isWaterCompanyOfficeExpenseVoucher)
                    _kv('تاريخ الدورة', cycleDateValue, receiptInfoStyle)
                  else ...[
                    if (_hasPdfValue(details.scheduledDate == null
                        ? ''
                        : _fmtDate(details.scheduledDate)))
                      _kv('تاريخ البدء', _fmtDate(details.scheduledDate),
                          receiptInfoStyle),
                    if (_hasPdfValue(details.executionDeadline == null
                        ? ''
                        : _fmtDate(details.executionDeadline)))
                      _kv('آخر موعد تنفيذ', _fmtDate(details.executionDeadline),
                          receiptInfoStyle),
                  ],
                  if (_hasPdfValue(tenantName))
                    _kv('اسم المستأجر', tenantName, receiptInfoStyle),
                  _kv('مرجع العقار', propertyRef, receiptInfoStyle),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            if (isSharedServiceVoucher || isWaterCompanyOfficeExpenseVoucher)
              pw.NewPage(),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCBD5E1)),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(3.4),
                2: pw.FlexColumnWidth(5.4),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFE5E7EB),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'المبلغ',
                          style: pw.TextStyle(font: bold, fontSize: 13),
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          tableDateHeader,
                          style: pw.TextStyle(font: bold, fontSize: 13),
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'البيان',
                          style: pw.TextStyle(font: bold, fontSize: 13),
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ),
                    ),
                  ],
                ),
                ...tableRows.map(
                  (row) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            _txt(row[0]),
                            style: pw.TextStyle(font: regular, fontSize: 12.5),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            _txt(row[1]),
                            style: pw.TextStyle(font: regular, fontSize: 12.5),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            _txt(row[2]),
                            style: pw.TextStyle(font: regular, fontSize: 12.5),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(6),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Text(
                'المبلغ كتابة: ${_amountInWordsAr(amountWordsValue)} ريال لا غير.',
                style: pw.TextStyle(font: regular, fontSize: 13),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
      );
      await _shareDoc(
        context: context,
        doc: doc,
        filename: 'service_${details.requestType}_${details.id}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareMaintenanceRequestDetailsPdf({
    required BuildContext context,
    required MaintenanceReceiptDetails details,
    Property? property,
  }) async {
    try {
      final (regular, bold) = await _loadFonts();
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 12);
      final doc = pw.Document();
      final office = await _loadOfficeProfile();

      final officeName = _txt(office['name'], fallback: '-');
      final officeAddress = _txt(office['address'], fallback: '-');
      final officeMobile = _txt(office['mobile'], fallback: '-');
      final officePhone = _txt(office['phone'], fallback: '-');
      final officeCommercial = _txt(office['commercial'], fallback: '-');
      final officeLogoBytes = await _decodeOfficeLogoBytes(office);
      final officeTax = _txt(
        office['tax'] ?? office['vat'] ?? office['tax_no'] ?? office['vat_no'],
        fallback: '-',
      );

      final issueDate = details.createdAt;
      final issueDateG = _fmtDate(issueDate);
      final issueDateH = _fmtHijriDate(issueDate);
      final serviceProvider = _txt(details.assignedTo);
      final (propertyRef, propertyAddress) =
          await _resolveMaintenancePropertyInfo(
        property: property,
        propertyId: details.propertyId,
      );
      final startDate = _fmtDate(details.scheduledDate);
      final endDate =
          _fmtDate(details.completedDate ?? details.executionDeadline);

      final subjectStyle = pw.TextStyle(
        font: bold,
        fontSize: 15,
        color: PdfColor.fromInt(0xFF0B3B8C),
      );
      final paragraphStyle = pw.TextStyle(
        font: regular,
        fontSize: 12,
        height: 1.55,
        color: PdfColor.fromInt(0xFF0F172A),
      );
      final closingStyle = pw.TextStyle(
        font: bold,
        fontSize: 12,
        color: PdfColor.fromInt(0xFF0F172A),
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'ت م: $issueDateG',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 13,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'ت هـ: $issueDateH',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 13,
                          color: PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'طلب خدمات',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 24,
                  color: PdfColor.fromInt(0xFF0B3B8C),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFF8FAFC),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('بيانات المكتب',
                        style: pw.TextStyle(font: bold, fontSize: 16)),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(officeName,
                                style: pw.TextStyle(font: bold, fontSize: 14)),
                            pw.Text('العنوان: $officeAddress',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            pw.Text(
                                'الجوال: $officeMobile   |   الهاتف: $officePhone',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            pw.Text('رقم السجل: $officeCommercial',
                                style:
                                    pw.TextStyle(font: regular, fontSize: 13)),
                            if (officeTax != '-')
                              pw.Text('الرقم الضريبي: $officeTax',
                                  style: pw.TextStyle(
                                      font: regular, fontSize: 13)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Container(
                        width: 52,
                        height: 52,
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFCBD5E1)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 8,
                          verticalRadius: 8,
                          child: officeLogoBytes == null
                              ? pw.Center(
                                  child: pw.Text(
                                    'شعار',
                                    style: pw.TextStyle(
                                        font: regular, fontSize: 10),
                                  ),
                                )
                              : pw.Image(
                                  pw.MemoryImage(officeLogoBytes),
                                  fit: pw.BoxFit.cover,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                borderRadius: pw.BorderRadius.circular(8),
                color: PdfColor.fromInt(0xFFFCFDFF),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('تفاصيل الطلب',
                        style: pw.TextStyle(
                            font: bold,
                            fontSize: 16,
                            color: PdfColor.fromInt(0xFF0F172A))),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEAF2FF),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'الموضوع: إشعار تنفيذ طلب خدمات',
                      style: subjectStyle,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'السادة/ $serviceProvider المحترمين،',
                    style: paragraphStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'السلام عليكم ورحمة الله وبركاته،',
                    style: paragraphStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'نفيدكم بأنه تم اعتماد طلب خدمات خاص بـ $propertyRef، ونأمل منكم التكرم بتنفيذ الأعمال المطلوبة حسب التفاصيل أدناه، وذلك خلال الفترة المحددة.',
                    style: paragraphStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(6),
                      border:
                          pw.Border.all(color: PdfColor.fromInt(0xFFD9E2EC)),
                      color: PdfColor.fromInt(0xFFFFFFFF),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _kv('عنوان الطلب', _txt(details.title), bodyStyle),
                        _kv('مرجع العقار', propertyRef, bodyStyle),
                        _kv('عنوان العقار', propertyAddress, bodyStyle),
                        _kv('تاريخ بدء التنفيذ', startDate, bodyStyle),
                        _kv('تاريخ انتهاء التنفيذ', endDate, bodyStyle),
                        _kv('وصف الطلب', _txt(details.description), bodyStyle),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'يرجى الالتزام بالموعد المحدد، وإشعارنا فور الانتهاء، مع تزويدنا بما يلزم من تقرير/صور (إن أمكن).',
                    style: paragraphStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'شاكرين تعاونكم وتقديركم.',
                    style: paragraphStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'وتفضلوا بقبول فائق الاحترام،',
                    style: closingStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
      );
      await _shareDoc(
        context: context,
        doc: doc,
        filename:
            'maintenance_request_${details.id}_${KsaTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareServiceSettingsPdf({
    required BuildContext context,
    required String serviceType,
    required String title,
    required String propertyId,
    required Map<String, dynamic> config,
    List<Map<String, dynamic>> logRows = const [],
  }) async {
    try {
      final (regular, bold) = await _loadFonts();
      final titleStyle = pw.TextStyle(font: bold, fontSize: 18);
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 12);
      final doc = pw.Document();
      final normalizedServiceType = serviceType.trim().toLowerCase();
      const preferredOrder = <String>[
        'providerName',
        'startDate',
        'nextServiceDate',
        'nextDueDate',
        'recurrenceMonths',
        'defaultAmount',
        'remindBeforeDays',
        'lastGeneratedRequestDate',
      ];
      final entries = config.entries.where((e) {
        final key = e.key.toString();
        final value = e.value;
        if (value == null) return false;
        if ('$value'.trim().isEmpty) return false;
        return key != 'providerId' &&
            key != 'serviceType' &&
            key != 'targetId' &&
            key != 'lastGeneratedRequestId' &&
            key != 'dueDay';
      }).toList()
        ..sort((a, b) {
          final ai = preferredOrder.indexOf(a.key.toString());
          final bi = preferredOrder.indexOf(b.key.toString());
          if (ai == -1 && bi == -1) {
            return a.key.toString().compareTo(b.key.toString());
          }
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });

      String serviceTypeLabel(String type) {
        switch (type) {
          case 'cleaning':
            return '\u0627\u0644\u0646\u0638\u0627\u0641\u0629';
          case 'elevator':
            return '\u0635\u064a\u0627\u0646\u0629 \u0627\u0644\u0645\u0635\u0639\u062f';
          case 'water':
            return '\u0627\u0644\u0645\u064a\u0627\u0647';
          case 'electricity':
            return '\u0627\u0644\u0643\u0647\u0631\u0628\u0627\u0621';
          case 'internet':
            return '\u0627\u0644\u0625\u0646\u062a\u0631\u0646\u062a';
          default:
            return _txt(type);
        }
      }

      String serviceSettingLabel(String type, String key) {
        switch (key) {
          case 'providerName':
            return '\u0645\u0642\u062f\u0645 \u0627\u0644\u062e\u062f\u0645\u0629';
          case 'startDate':
            return '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0628\u062f\u0621';
          case 'nextServiceDate':
            return '\u0645\u0648\u0639\u062f \u0627\u0644\u0635\u064a\u0627\u0646\u0629 \u0627\u0644\u0642\u0627\u062f\u0645';
          case 'nextDueDate':
            return type == 'cleaning'
                ? '\u0645\u0648\u0639\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630 \u0627\u0644\u0642\u0627\u062f\u0645'
                : '\u0627\u0644\u0645\u0648\u0639\u062f \u0627\u0644\u0642\u0627\u062f\u0645';
          case 'recurrenceMonths':
            return '\u0627\u0644\u062f\u0648\u0631\u064a\u0629';
          case 'defaultAmount':
            return '\u0627\u0644\u062a\u0643\u0644\u0641\u0629 \u0627\u0644\u0627\u0641\u062a\u0631\u0627\u0636\u064a\u0629';
          case 'remindBeforeDays':
            return '\u0627\u0644\u062a\u0646\u0628\u064a\u0647 \u0642\u0628\u0644 \u0627\u0644\u0645\u0648\u0639\u062f';
          case 'lastGeneratedRequestDate':
            return '\u0622\u062e\u0631 \u062a\u0627\u0631\u064a\u062e \u0625\u0646\u0634\u0627\u0621 \u0637\u0644\u0628';
          default:
            return _txt(key);
        }
      }

      String serviceSettingValue(String key, dynamic value) {
        if (value == null) return '-';
        if (value is DateTime) return _fmtDate(value);
        final raw = value.toString().trim();
        if (raw.isEmpty) return '-';
        DateTime? parseDate() {
          try {
            return DateTime.parse(raw);
          } catch (_) {
            return null;
          }
        }

        switch (key) {
          case 'startDate':
          case 'nextServiceDate':
          case 'nextDueDate':
          case 'lastGeneratedRequestDate':
            return _fmtDate(parseDate());
          case 'recurrenceMonths':
            final months = value is num ? value.toInt() : int.tryParse(raw);
            if (months == null || months <= 0) return '-';
            if (months == 1) {
              return '\u0634\u0647\u0631\u064a\u064b\u0627';
            }
            if (months == 2) {
              return '\u0643\u0644 \u0634\u0647\u0631\u064a\u0646';
            }
            return '\u0643\u0644 $months \u0623\u0634\u0647\u0631';
          case 'defaultAmount':
            final amount =
                value is num ? value.toDouble() : double.tryParse(raw);
            if (amount == null) return _txt(raw);
            return '${_fmtMoney(amount)} \u0631\u064a\u0627\u0644';
          case 'remindBeforeDays':
            final days = value is num ? value.toInt() : int.tryParse(raw);
            if (days == null || days <= 0) {
              return '\u0628\u062f\u0648\u0646 \u062a\u0646\u0628\u064a\u0647';
            }
            if (days == 1) {
              return '\u0642\u0628\u0644 \u064a\u0648\u0645';
            }
            if (days == 2) {
              return '\u0642\u0628\u0644 \u064a\u0648\u0645\u064a\u0646';
            }
            return '\u0642\u0628\u0644 $days \u0623\u064a\u0627\u0645';
          default:
            if (raw == 'true') return '\u0646\u0639\u0645';
            if (raw == 'false') return '\u0644\u0627';
            return _txt(raw);
        }
      }

      String serviceLogHeaderLabel(String key) {
        switch (key) {
          case 'type':
            return '\u0627\u0644\u0637\u0644\u0628';
          case 'date':
            return '\u0627\u0644\u062a\u0627\u0631\u064a\u062e';
          case 'amount':
            return '\u0627\u0644\u062a\u0643\u0644\u0641\u0629';
          case 'status':
            return '\u0627\u0644\u062d\u0627\u0644\u0629';
          default:
            return _txt(key);
        }
      }

      String serviceLogStatusLabel(String value) {
        switch (value.trim().toLowerCase()) {
          case 'open':
            return '\u062c\u062f\u064a\u062f';
          case 'inprogress':
            return '\u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630';
          case 'completed':
            return '\u0645\u0643\u062a\u0645\u0644';
          case 'canceled':
            return '\u0645\u0644\u063a\u064a';
          case 'archived':
            return '\u0645\u0624\u0631\u0634\u0641';
          default:
            return _txt(value);
        }
      }

      String serviceLogValue(String key, dynamic value) {
        if (value == null) return '-';
        final raw = value.toString().trim();
        if (raw.isEmpty) return '-';
        switch (key) {
          case 'date':
            try {
              return _fmtDate(DateTime.parse(raw));
            } catch (_) {
              return _txt(raw);
            }
          case 'amount':
            final amount =
                value is num ? value.toDouble() : double.tryParse(raw);
            if (amount == null) return _txt(raw);
            return '${_fmtMoney(amount)} \u0631\u064a\u0627\u0644';
          case 'status':
            return serviceLogStatusLabel(raw);
          default:
            return _txt(raw);
        }
      }

      final printableLogRows = logRows.map((row) {
        final printable = <String, String>{};
        for (final entry in row.entries) {
          final key = entry.key.toString();
          printable[serviceLogHeaderLabel(key)] =
              serviceLogValue(key, entry.value);
        }
        return printable;
      }).toList();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            _sectionTitle('تفاصيل الخدمات/الخدمة', titleStyle),
            _kv('الخدمة', _txt(title), bodyStyle),
            _kv('النوع', serviceTypeLabel(normalizedServiceType), bodyStyle),
            _kv('العقار', _txt(propertyId), bodyStyle),
            pw.SizedBox(height: 8),
            _sectionTitle('الإعدادات', pw.TextStyle(font: bold, fontSize: 14)),
            ...entries.map(
              (e) => _kv(
                serviceSettingLabel(normalizedServiceType, e.key.toString()),
                serviceSettingValue(e.key.toString(), e.value),
                bodyStyle,
              ),
            ),
            if (printableLogRows.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _sectionTitle(
                  'سجل الطلبات', pw.TextStyle(font: bold, fontSize: 14)),
              pw.TableHelper.fromTextArray(
                headers: printableLogRows.first.keys.toList(),
                data: printableLogRows
                    .map((r) => r.values.map((v) => '$v').toList())
                    .toList(),
                cellAlignment: pw.Alignment.centerRight,
                headerStyle: pw.TextStyle(font: bold, fontSize: 10),
                cellStyle: pw.TextStyle(font: regular, fontSize: 9),
              ),
            ],
            pw.SizedBox(height: 12),
          ],
        ),
      );
      await _shareDoc(
        context: context,
        doc: doc,
        filename:
            'service_${_safeFileName(serviceType)}_${KsaTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }

  static Future<void> shareOwnerPayoutSettlementPdf({
    required BuildContext context,
    required String ownerName,
    required double amount,
    required DateTime transferDate,
    DateTime? periodFrom,
    DateTime? periodTo,
    required double collectedRent,
    required double commission,
    required double expenses,
    double additionalDeductions = 0,
    required double previousPayouts,
    required double readyBefore,
    String? voucherNo,
    String note = '',
  }) async {
    try {
      final (regular, bold) = await _loadFonts();
      final bodyStyle = pw.TextStyle(font: regular, fontSize: 12);
      final titleStyle = pw.TextStyle(font: bold, fontSize: 18);
      final doc = pw.Document();

      final netAfter = readyBefore - amount;
      final periodText = (periodFrom == null && periodTo == null)
          ? 'الفترة المفتوحة'
          : '${_fmtDate(periodFrom)} إلى ${_fmtDate(periodTo)}';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            _sectionTitle('إشعار تسوية وتحويل مالك', titleStyle),
            pw.SizedBox(height: 10),
            _kv('اسم المالك', _txt(ownerName), bodyStyle),
            _kv('رقم المرجع', _txt(voucherNo ?? '-'), bodyStyle),
            _kv('تاريخ التحويل', _fmtDate(transferDate), bodyStyle),
            _kv('الفترة', _txt(periodText), bodyStyle),
            pw.SizedBox(height: 8),
            _sectionTitle(
                'تفاصيل التسوية', pw.TextStyle(font: bold, fontSize: 14)),
            _kv('الإيجارات المحصلة', '${_fmtMoney(collectedRent)} ريال',
                bodyStyle),
            _kv('عمولة المكتب المخصومة', '${_fmtMoney(commission)} ريال',
                bodyStyle),
            _kv('المصروفات المخصومة', '${_fmtMoney(expenses)} ريال', bodyStyle),
            _kv('الخصومات/التسويات', '${_fmtMoney(additionalDeductions)} ريال',
                bodyStyle),
            _kv('التحويلات السابقة', '${_fmtMoney(previousPayouts)} ريال',
                bodyStyle),
            _kv('الرصيد قبل التحويل', '${_fmtMoney(readyBefore)} ريال',
                bodyStyle),
            _kv('مبلغ التحويل الحالي', '${_fmtMoney(amount)} ريال', bodyStyle),
            _kv('الرصيد بعد التحويل', '${_fmtMoney(netAfter)} ريال', bodyStyle),
            if (note.trim().isNotEmpty) _kv('ملاحظات', _txt(note), bodyStyle),
            pw.SizedBox(height: 10),
          ],
        ),
      );

      await _shareDoc(
        context: context,
        doc: doc,
        filename: 'owner_payout_${KsaTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء ملف PDF')),
      );
    }
  }
}



