// lib/ui/invoices_screen.dart
// شاشة السندات: موديل + Adapter + شاشات (قائمة/تفاصيل/سجل عقد)
// ملاحظة: أضِف مسارات هذا الملف إلى MaterialApp.routes عبر InvoicesRoutes.routes()
// وسجّل الـAdapter: Hive.registerAdapter(InvoiceAdapter());
// ignore_for_file: unused_import,unused_element,unused_local_variable,unnecessary_null_comparison,unnecessary_non_null_assertion,unnecessary_import,prefer_const_declarations,deprecated_member_use,use_build_context_synchronously,no_leading_underscores_for_local_identifiers,prefer_const_constructors,curly_braces_in_flow_control_structures
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../data/services/hive_service.dart';
import '../data/services/office_client_guard.dart'; // ✅ جديد
import '../data/services/comprehensive_reports_service.dart';
import '../data/services/pdf_export_service.dart';
// ✅ مهم: نفس أسلوب المستأجرين
import '../data/services/user_scope.dart' as scope;
import '../data/constants/boxes.dart' as bx;

import 'home_screen.dart';
import 'properties_screen.dart';
import 'tenants_screen.dart';
import 'contracts_screen.dart'
    show Contract, AdvanceMode, ContractTerm, PaymentCycle;
import 'contracts_screen.dart' as contracts_ui
    show
        ContractsScreen,
        openServicesConfigBox,
        isWaterSharedFixedConfig,
        waterInstallmentsFromConfig;
import 'maintenance_screen.dart'
    show
        MaintenanceRequest,
        MaintenancePriority,
        MaintenanceDetailsScreen,
        markPeriodicServiceRequestSuppressedForCurrentCycle;

import 'widgets/app_bottom_nav.dart';
import 'widgets/app_menu_button.dart';
import 'widgets/app_side_drawer.dart';
import 'widgets/entity_audit_info_button.dart';

import '../models/tenant.dart';
import '../models/property.dart';
import '../widgets/darvoo_app_bar.dart';
import '../widgets/custom_confirm_dialog.dart';

// ✅ أسماء الصناديق per-uid عبر user_scope بنفس نمط الشاشات الأخرى
String invoicesBoxName() => scope.boxName(bx.kInvoicesBox);
String tenantsBoxName() => scope.boxName(bx.kTenantsBox);
String propsBoxName() => scope.boxName(bx.kPropertiesBox);
String contractsBoxName() => scope.boxName(bx.kContractsBox);
String contractsEjarMapBoxName() => scope.boxName('contractsEjarNoMap');

String _readEjarNoLocalIfOpen(String contractId) {
  final id = contractId.trim();
  if (id.isEmpty) return '';
  final boxId = contractsEjarMapBoxName();
  if (!Hive.isBoxOpen(boxId)) return '';
  final v = Hive.box<String>(boxId).get(id);
  return (v ?? '').trim();
}

Future<String> _readEjarNoLocalAsync(String contractId) async {
  final id = contractId.trim();
  if (id.isEmpty) return '';
  final boxId = contractsEjarMapBoxName();
  if (!Hive.isBoxOpen(boxId)) {
    await Hive.openBox<String>(boxId);
  }
  final v = Hive.box<String>(boxId).get(id);
  return (v ?? '').trim();
}

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

Map<String, dynamic>? _invoiceSnapshotMapOrNull(dynamic raw) {
  if (raw is! Map) return null;
  try {
    final map = Map<String, dynamic>.from(raw);
    return map.isEmpty ? null : map;
  } catch (_) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key == null) return;
      map[key.toString()] = value;
    });
    return map.isEmpty ? null : map;
  }
}

String? _invoiceSnapshotString(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _invoiceSnapshotDateValue(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

String? _invoiceSnapshotNumberText(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  if (value is num) return _fmtMoneyTrunc(value);
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _invoiceSnapshotIntValue(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

Map<String, String> _invoiceSnapshotPropertySpecMap(String? desc) {
  final text = (desc ?? '').trim();
  if (text.isEmpty) return const <String, String>{};
  final start = text.indexOf('[[SPEC]]');
  final end = text.indexOf('[[/SPEC]]');
  if (start == -1 || end == -1 || end <= start) {
    return const <String, String>{};
  }
  final body = text.substring(start + 8, end).trim();
  if (body.isEmpty) return const <String, String>{};
  final map = <String, String>{};
  for (final line in body.split('\n')) {
    final parts = line.split(':');
    if (parts.length < 2) continue;
    final key = parts.first.trim();
    final value = parts.sublist(1).join(':').trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      map[key] = value;
    }
  }
  return map;
}

String? _invoiceSnapshotPropertyFreeDescription(Map<String, dynamic>? snapshot) {
  final text = _invoiceSnapshotString(snapshot, 'description');
  if (text == null) return null;
  final start = text.indexOf('[[SPEC]]');
  final end = text.indexOf('[[/SPEC]]');
  if (start != -1 && end != -1 && end > start) {
    final free = text.substring(end + 9).trim();
    return free.isEmpty ? null : free;
  }
  return text.trim().isEmpty ? null : text.trim();
}

String? _invoiceSnapshotPropertyFurnishingText(
    Map<String, dynamic>? snapshot) {
  final raw = _invoiceSnapshotPropertySpecMap(
      _invoiceSnapshotString(snapshot, 'description'))['المفروشات'];
  if (raw == null) return null;
  final normalized = raw.trim();
  if (normalized.isEmpty) return null;
  if (normalized.contains('غير')) return 'غير مفروش';
  if (normalized.contains('مفروش')) return 'مفروش';
  return normalized;
}

String _invoiceSnapshotPropertyTypeDisplayLabel(
  Map<String, dynamic> propertySnapshot, {
  Map<String, dynamic>? buildingSnapshot,
}) {
  final rawType =
      _invoiceSnapshotString(propertySnapshot, 'type')?.toLowerCase().trim();
  final hasBuilding =
      (_invoiceSnapshotString(propertySnapshot, 'parentBuildingId') ?? '')
              .trim()
              .isNotEmpty ||
          (buildingSnapshot != null && buildingSnapshot.isNotEmpty);
  if (rawType == 'apartment' && hasBuilding) {
    return 'وحدة';
  }
  return _invoiceSnapshotString(propertySnapshot, 'typeLabel') ??
      (rawType == 'apartment' ? 'شقة' : null) ??
      '—';
}

String _invoiceSnapshotBuildingTypeDisplayLabel(
    Map<String, dynamic>? buildingSnapshot) {
  final rawType =
      _invoiceSnapshotString(buildingSnapshot, 'type')?.toLowerCase().trim();
  final rentalMode = _invoiceSnapshotString(buildingSnapshot, 'rentalMode')
      ?.toLowerCase()
      .trim();
  if (rawType == 'building' && rentalMode == 'perunit') {
    return 'عمارة ذات وحدات';
  }
  return _invoiceSnapshotString(buildingSnapshot, 'typeLabel') ??
      (rawType == 'building' ? 'عمارة' : null) ??
      '—';
}

String _composeInvoicePropertyReference({
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

String _invoicePropertyReference({
  Property? property,
  Property? building,
  Map<String, dynamic>? propertySnapshot,
  Map<String, dynamic>? buildingSnapshot,
  String? fallbackName,
}) {
  final unitName = (property?.name ??
          _invoiceSnapshotString(propertySnapshot, 'name') ??
          fallbackName ??
          '')
      .trim();
  final hasBuilding =
      (property?.parentBuildingId?.trim().isNotEmpty ?? false) ||
          (_invoiceSnapshotString(propertySnapshot, 'parentBuildingId') ?? '')
              .trim()
              .isNotEmpty ||
          building != null ||
          (buildingSnapshot != null && buildingSnapshot.isNotEmpty);
  final buildingName = hasBuilding
      ? (building?.name ?? _invoiceSnapshotString(buildingSnapshot, 'name') ?? '')
          .trim()
      : '';
  return _composeInvoicePropertyReference(
    unitName: unitName,
    buildingName: buildingName,
  );
}

List<String> _invoiceSnapshotStringList(
    Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is List) {
    return value
        .whereType<dynamic>()
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const <String>[] : <String>[text];
}

bool? _invoiceSnapshotBoolValue(Map<String, dynamic>? snapshot, String key) {
  final value = snapshot?[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

String? _invoiceSnapshotBoolText(
  Map<String, dynamic>? snapshot,
  String key, {
  String yes = 'نعم',
  String no = 'لا',
}) {
  final value = _invoiceSnapshotBoolValue(snapshot, key);
  if (value == null) return null;
  return value ? yes : no;
}

void _invoicePutSnapshotValue(
    Map<String, dynamic> target, String key, dynamic value) {
  if (value == null) return;
  if (value is String && value.trim().isEmpty) return;
  target[key] = value;
}

void _invoicePutSnapshotDate(
    Map<String, dynamic> target, String key, DateTime? value) {
  if (value == null) return;
  target[key] = value.millisecondsSinceEpoch;
}

void _invoicePutSnapshotList(
    Map<String, dynamic> target, String key, List<String>? values) {
  if (values == null) return;
  final cleaned = values
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (cleaned.isEmpty) return;
  target[key] = cleaned;
}

bool _invoiceSnapshotHasValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

dynamic _cloneInvoiceSnapshotValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List) return List<dynamic>.from(value);
  return value;
}

String _invoiceSnapshotClientTypeLabel(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value == 'company' || value == 'مستأجر (شركة)' || value == 'شركة') {
    return 'مستأجر (شركة)';
  }
  if (value == 'serviceprovider' ||
      value == 'service_provider' ||
      value == 'service provider' ||
      value == 'مقدم خدمة') {
    return 'مقدم خدمة';
  }
  return 'مستأجر';
}

Map<String, dynamic> _buildInvoiceTenantSnapshot(Tenant tenant) {
  final map = <String, dynamic>{};
  _invoicePutSnapshotValue(map, 'id', tenant.id);
  _invoicePutSnapshotValue(map, 'fullName', tenant.fullName);
  _invoicePutSnapshotValue(map, 'nationalId', tenant.nationalId);
  _invoicePutSnapshotValue(map, 'phone', tenant.phone);
  _invoicePutSnapshotValue(map, 'email', tenant.email);
  _invoicePutSnapshotDate(map, 'dateOfBirth', tenant.dateOfBirth);
  _invoicePutSnapshotValue(map, 'nationality', tenant.nationality);
  _invoicePutSnapshotDate(map, 'idExpiry', tenant.idExpiry);
  _invoicePutSnapshotValue(map, 'addressLine', tenant.addressLine);
  _invoicePutSnapshotValue(map, 'city', tenant.city);
  _invoicePutSnapshotValue(map, 'region', tenant.region);
  _invoicePutSnapshotValue(map, 'postalCode', tenant.postalCode);
  _invoicePutSnapshotValue(map, 'emergencyName', tenant.emergencyName);
  _invoicePutSnapshotValue(map, 'emergencyPhone', tenant.emergencyPhone);
  _invoicePutSnapshotValue(map, 'notes', tenant.notes);
  _invoicePutSnapshotValue(map, 'clientType', tenant.clientType);
  _invoicePutSnapshotValue(map, 'clientTypeLabel',
      _invoiceSnapshotClientTypeLabel(tenant.clientType));
  _invoicePutSnapshotValue(map, 'tenantBankName', tenant.tenantBankName);
  _invoicePutSnapshotValue(
      map, 'tenantBankAccountNumber', tenant.tenantBankAccountNumber);
  _invoicePutSnapshotValue(map, 'tenantTaxNumber', tenant.tenantTaxNumber);
  _invoicePutSnapshotValue(map, 'companyName', tenant.companyName);
  _invoicePutSnapshotValue(
      map, 'companyCommercialRegister', tenant.companyCommercialRegister);
  _invoicePutSnapshotValue(map, 'companyTaxNumber', tenant.companyTaxNumber);
  _invoicePutSnapshotValue(
      map, 'companyRepresentativeName', tenant.companyRepresentativeName);
  _invoicePutSnapshotValue(
      map, 'companyRepresentativePhone', tenant.companyRepresentativePhone);
  _invoicePutSnapshotValue(
      map, 'companyBankAccountNumber', tenant.companyBankAccountNumber);
  _invoicePutSnapshotValue(map, 'companyBankName', tenant.companyBankName);
  _invoicePutSnapshotValue(
      map, 'serviceSpecialization', tenant.serviceSpecialization);
  _invoicePutSnapshotList(map, 'tags', tenant.tags);
  _invoicePutSnapshotList(map, 'attachmentPaths', tenant.attachmentPaths);
  _invoicePutSnapshotValue(map, 'isArchived', tenant.isArchived);
  _invoicePutSnapshotValue(map, 'isBlacklisted', tenant.isBlacklisted);
  _invoicePutSnapshotValue(map, 'blacklistReason', tenant.blacklistReason);
  _invoicePutSnapshotValue(map, 'activeContractsCount', tenant.activeContractsCount);
  _invoicePutSnapshotDate(map, 'createdAt', tenant.createdAt);
  _invoicePutSnapshotDate(map, 'updatedAt', tenant.updatedAt);
  return map;
}

Map<String, dynamic> _buildInvoicePropertySnapshot(Property property) {
  final map = <String, dynamic>{};
  final documentPaths = <String>{
    ...?property.documentAttachmentPaths,
    if ((property.documentAttachmentPath ?? '').trim().isNotEmpty)
      property.documentAttachmentPath!.trim(),
  }.toList();
  _invoicePutSnapshotValue(map, 'id', property.id);
  _invoicePutSnapshotValue(map, 'name', property.name);
  _invoicePutSnapshotValue(map, 'type', property.type.name);
  _invoicePutSnapshotValue(map, 'typeLabel', property.type.label);
  _invoicePutSnapshotValue(map, 'address', property.address);
  _invoicePutSnapshotValue(map, 'price', property.price);
  _invoicePutSnapshotValue(map, 'currency', property.currency);
  _invoicePutSnapshotValue(map, 'rooms', property.rooms);
  _invoicePutSnapshotValue(map, 'area', property.area);
  _invoicePutSnapshotValue(map, 'floors', property.floors);
  _invoicePutSnapshotValue(map, 'totalUnits', property.totalUnits);
  _invoicePutSnapshotValue(map, 'occupiedUnits', property.occupiedUnits);
  _invoicePutSnapshotValue(map, 'rentalMode', property.rentalMode?.name);
  _invoicePutSnapshotValue(map, 'rentalModeLabel', property.rentalMode?.label);
  _invoicePutSnapshotValue(map, 'parentBuildingId', property.parentBuildingId);
  _invoicePutSnapshotValue(map, 'description', property.description);
  _invoicePutSnapshotValue(map, 'documentType', property.documentType);
  _invoicePutSnapshotValue(map, 'documentNumber', property.documentNumber);
  _invoicePutSnapshotDate(map, 'documentDate', property.documentDate);
  _invoicePutSnapshotValue(map, 'electricityNumber', property.electricityNumber);
  _invoicePutSnapshotValue(map, 'electricityMode', property.electricityMode);
  _invoicePutSnapshotValue(map, 'electricityShare', property.electricityShare);
  _invoicePutSnapshotValue(map, 'waterNumber', property.waterNumber);
  _invoicePutSnapshotValue(map, 'waterMode', property.waterMode);
  _invoicePutSnapshotValue(map, 'waterShare', property.waterShare);
  _invoicePutSnapshotValue(map, 'waterAmount', property.waterAmount);
  _invoicePutSnapshotValue(map, 'isArchived', property.isArchived);
  _invoicePutSnapshotDate(map, 'createdAt', property.createdAt);
  _invoicePutSnapshotDate(map, 'updatedAt', property.updatedAt);
  _invoicePutSnapshotList(map, 'documentAttachmentPaths', documentPaths);
  return map;
}

bool _isInvoiceSnapshotImageAttachment(String path) {
  final lower = path.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

bool _isInvoiceSnapshotRemoteAttachment(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://') || p.startsWith('gs://');
}

Future<String> _resolveInvoiceSnapshotRemoteUrl(String path) async {
  if (path.startsWith('gs://')) {
    return FirebaseStorage.instance.refFromURL(path).getDownloadURL();
  }
  return path;
}

Widget _buildInvoiceSnapshotAttachmentThumb(String path) {
  if (_isInvoiceSnapshotImageAttachment(path)) {
    if (_isInvoiceSnapshotRemoteAttachment(path)) {
      return FutureBuilder<String>(
        future: _resolveInvoiceSnapshotRemoteUrl(path),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) {
            return const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white70,
            );
          }
          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white70,
            ),
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          );
        },
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white70,
      ),
    );
  }
  return const Icon(
    Icons.picture_as_pdf_rounded,
    color: Colors.white70,
  );
}

Future<void> _openInvoiceSnapshotAttachment(
    BuildContext context, String path) async {
  try {
    final raw = path.trim();
    String launchable = raw;
    if (raw.startsWith('gs://')) {
      launchable = await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
    }
    Uri? uri;
    if (_isInvoiceSnapshotRemoteAttachment(launchable)) {
      uri = Uri.tryParse(launchable);
    } else {
      final file = File(launchable);
      if (!file.existsSync()) throw Exception('attachment missing');
      uri = Uri.file(file.path);
    }
    if (uri == null) throw Exception('bad uri');
    var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح المرفق', style: GoogleFonts.cairo())),
    );
  }
}

bool _invoiceContractIsInactive(Contract contract) {
  if (contract.isTerminated) return true;
  return contract.isExpiredByTime;
}

Future<void> _showInvoiceArchiveNoticeDialog(
  BuildContext context, {
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Text(
                  'تنبيه',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF1E293B),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFF475569),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'حسنًا',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

double _extractWaterAmountFromNote(String? note) {
  final n = (note ?? '').trim();
  if (n.isEmpty) return 0.0;
  final m = RegExp(r'مياه\s*\(قسط\)\s*:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(n);
  if (m == null) return 0.0;
  return double.tryParse(m.group(1) ?? '') ?? 0.0;
}

double _invoiceWaterAmount(Invoice inv) {
  // أولاً: الحقل المخصص (الطريقة الجديدة)
  if (inv.waterAmount > 0) return inv.waterAmount;
  // ثانياً: fallback للبيانات القديمة المخزنة في الملاحظة
  final w = _extractWaterAmountFromNote(inv.note);
  if (w <= 0) return 0.0;
  if (w > inv.amount) return 0.0;
  return w;
}

double _invoiceRentOnlyAmount(Invoice inv) {
  final r = inv.amount - _invoiceWaterAmount(inv);
  return r < 0 ? 0.0 : r;
}

/// ===============================================================================
/// موديل السند + Adapter
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
  List<String> attachmentPaths;
  String? maintenanceRequestId;
  Map<String, dynamic>? maintenanceSnapshot;

  bool isArchived;
  bool isCanceled;

  double waterAmount;

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
    List<String>? attachmentPaths,
    this.maintenanceRequestId,
    this.maintenanceSnapshot,
    this.isArchived = false,
    this.isCanceled = false,
    this.waterAmount = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? KsaTime.now().microsecondsSinceEpoch.toString(),
        attachmentPaths = attachmentPaths ?? <String>[],
        createdAt = createdAt ?? KsaTime.now(),
        updatedAt = updatedAt ?? KsaTime.now();

  double get remaining {
    final r = amount.abs() - paidAmount;
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
      serialNo: fields[15] as String?,
      tenantId: fields[1] as String,
      contractId: fields[2] as String,
      propertyId: fields[3] as String,
      issueDate: fields[4] as DateTime,
      dueDate: fields[5] as DateTime,
      amount: (fields[6] as num?)?.toDouble() ?? 0.0,
      paidAmount: (fields[7] as num?)?.toDouble() ?? 0.0,
      currency: fields[8] as String? ?? 'SAR',
      note: fields[9] as String?,
      paymentMethod: fields[10] as String? ?? 'نقدًا',
      attachmentPaths:
          (fields[16] as List?)?.map((e) => e.toString()).toList() ??
              <String>[],
      maintenanceRequestId: fields[17] as String?,
      maintenanceSnapshot: (fields[18] as Map?)?.cast<String, dynamic>(),
      isArchived: fields[11] as bool? ?? false,
      isCanceled: fields[12] as bool? ?? false,
      waterAmount: (fields[19] as num?)?.toDouble() ?? 0.0,
      createdAt: fields[13] as DateTime? ?? KsaTime.now(),
      updatedAt: fields[14] as DateTime? ?? KsaTime.now(),
    );
  }

  @override
  void write(BinaryWriter w, Invoice i) {
    w
      ..writeByte(20)
      ..writeByte(0)
      ..write(i.id)
      ..writeByte(1)
      ..write(i.tenantId)
      ..writeByte(2)
      ..write(i.contractId)
      ..writeByte(3)
      ..write(i.propertyId)
      ..writeByte(4)
      ..write(i.issueDate)
      ..writeByte(5)
      ..write(i.dueDate)
      ..writeByte(6)
      ..write(i.amount)
      ..writeByte(7)
      ..write(i.paidAmount)
      ..writeByte(8)
      ..write(i.currency)
      ..writeByte(9)
      ..write(i.note)
      ..writeByte(10)
      ..write(i.paymentMethod)
      ..writeByte(11)
      ..write(i.isArchived)
      ..writeByte(12)
      ..write(i.isCanceled)
      ..writeByte(13)
      ..write(i.createdAt)
      ..writeByte(14)
      ..write(i.updatedAt)
      ..writeByte(15)
      ..write(i.serialNo)
      ..writeByte(16)
      ..write(i.attachmentPaths)
      ..writeByte(17)
      ..write(i.maintenanceRequestId)
      ..writeByte(18)
      ..write(i.maintenanceSnapshot)
      ..writeByte(19)
      ..write(i.waterAmount);
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

String _formatInvoiceHourAmPm(int hour24) {
  final normalized = hour24.clamp(0, 23);
  final hour12 = normalized == 0
      ? 12
      : (normalized > 12 ? normalized - 12 : normalized);
  final suffix = normalized >= 12 ? 'PM' : 'AM';
  return '$hour12:00 $suffix';
}

int _dailyInvoiceDays(Contract c) {
  final days = c.endDate.difference(c.startDate).inDays;
  return days <= 0 ? 1 : days;
}

String _dailyInvoiceDaysLabel(int days) {
  if (days <= 0) return '0 يوم';
  if (days == 1) return '1 يوم';
  if (days == 2) return '2 يوم';
  return '$days أيام';
}

double? _dailyInvoiceRate(Contract? c) {
  if (c == null || c.term != ContractTerm.daily) return null;
  final days = _dailyInvoiceDays(c);
  return days <= 0 ? null : c.totalAmount / days;
}

String _dailyInvoicePeriodLabel(Contract c) {
  final daysLabel = _dailyInvoiceDaysLabel(_dailyInvoiceDays(c));
  final start = c.dailyStartBoundary;
  final end = c.dailyEndBoundary;
  return '$daysLabel من تاريخ ${_fmtDateDynamic(start)} ${_formatInvoiceHourAmPm(start.hour)} إلى ${_fmtDateDynamic(end)} ${_formatInvoiceHourAmPm(end.hour)}';
}

List<InlineSpan> _invoiceDateTimeInlineSpans(
  DateTime d, {
  required TextStyle baseStyle,
  required TextStyle dateStyle,
}) {
  return <InlineSpan>[
    TextSpan(text: _fmtDateDynamic(d), style: dateStyle),
    TextSpan(text: ' ', style: baseStyle),
    TextSpan(text: _formatInvoiceHourAmPm(d.hour), style: baseStyle),
  ];
}

Widget _invoiceDailyPeriodDetailsWidget(
  Contract c, {
  TextStyle? baseStyle,
  TextStyle? dateStyle,
  bool showDaysLabel = true,
}) {
  final effectiveBase = baseStyle ??
      GoogleFonts.cairo(
        color: Colors.white,
        fontSize: 11.sp,
        fontWeight: FontWeight.w700,
      );
  final effectiveDate =
      dateStyle ?? effectiveBase.copyWith(color: const Color(0xFF93C5FD));
  final daysLabel = _dailyInvoiceDaysLabel(_dailyInvoiceDays(c));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showDaysLabel) ...[
        Text('$daysLabel من تاريخ', style: effectiveBase),
        SizedBox(height: 2.h),
      ],
      RichText(
        text: TextSpan(
          style: effectiveBase,
          children: _invoiceDateTimeInlineSpans(
            c.dailyStartBoundary,
            baseStyle: effectiveBase,
            dateStyle: effectiveDate,
          ),
        ),
      ),
      SizedBox(height: 2.h),
      Text('إلى', style: effectiveBase),
      SizedBox(height: 2.h),
      RichText(
        text: TextSpan(
          style: effectiveBase,
          children: _invoiceDateTimeInlineSpans(
            c.dailyEndBoundary,
            baseStyle: effectiveBase,
            dateStyle: effectiveDate,
          ),
        ),
      ),
    ],
  );
}

String _fmtMoneyTrunc(num v) {
  final t = (v * 100).truncate() / 100.0;
  return t.toStringAsFixed(t.truncateToDouble() == t ? 0 : 2);
}

DateTime _addMonthsSafe(DateTime d, int months) {
  final y0 = d.year;
  final m0 = d.month;
  final totalM = m0 - 1 + months;
  final y = y0 + totalM ~/ 12;
  final m = totalM % 12 + 1;
  final maxDay = DateTime(y, m + 1, 0).day;
  final safeDay = d.day > maxDay ? maxDay : d.day;
  return DateTime(y, m, safeDay);
}

int _monthsPerCycleForInvoiceContract(Contract c) {
  switch (c.paymentCycle) {
    case PaymentCycle.monthly:
      return 1;
    case PaymentCycle.quarterly:
      return 3;
    case PaymentCycle.semiAnnual:
      return 6;
    case PaymentCycle.annual:
      final y = c.paymentCycleYears <= 0 ? 1 : c.paymentCycleYears;
      return 12 * y;
  }
}

String _cycleDurationLabelForInvoiceContract(Contract c) {
  final months = _monthsPerCycleForInvoiceContract(c);
  if (months <= 1) return '1 شهر';
  if (months % 12 == 0) {
    final years = (months ~/ 12).clamp(1, 10);
    return years == 1 ? '1 سنة' : '$years سنة';
  }
  return '$months شهور';
}

String _invoicePeriodLabel(Invoice inv, Contract? c) {
  final due = KsaTime.dateOnly(inv.dueDate);
  if (c == null) {
    return 'التاريخ: ${_fmtDateDynamic(due)}';
  }
  if (c.term == ContractTerm.daily) {
    return _dailyInvoicePeriodLabel(c);
  }
  final months = _monthsPerCycleForInvoiceContract(c);
  final duration = _cycleDurationLabelForInvoiceContract(c);
  final endDate = KsaTime.dateOnly(_addMonthsSafe(due, months));
  return '$duration: من ${_fmtDateDynamic(due)} إلى ${_fmtDateDynamic(endDate)}';
}

Widget _invoicePeriodChip(Invoice inv, Contract? c) {
  final due = KsaTime.dateOnly(inv.dueDate);
  final dateColor = const Color(0xFF93C5FD);
  final baseStyle = GoogleFonts.cairo(
      color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700);
  final dateStyle = baseStyle.copyWith(color: dateColor);

  Widget child;
  if (c == null) {
    child = RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'التاريخ: ', style: baseStyle),
          TextSpan(text: _fmtDateDynamic(due), style: dateStyle),
        ],
      ),
    );
  } else if (c.term == ContractTerm.daily) {
    child = _invoiceDailyPeriodDetailsWidget(
      c,
      baseStyle: baseStyle,
      dateStyle: dateStyle,
      showDaysLabel: true,
    );
  } else {
    final months = _monthsPerCycleForInvoiceContract(c);
    final duration = _cycleDurationLabelForInvoiceContract(c);
    final endDate = KsaTime.dateOnly(_addMonthsSafe(due, months));
    child = RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$duration: من ', style: baseStyle),
          TextSpan(text: _fmtDateDynamic(due), style: dateStyle),
          TextSpan(text: ' إلى ', style: baseStyle),
          TextSpan(text: _fmtDateDynamic(endDate), style: dateStyle),
        ],
      ),
    );
  }

  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
    decoration: BoxDecoration(
      color: const Color(0xFF1F2937),
      borderRadius: BorderRadius.circular(10.r),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
    ),
    child: child,
  );
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

Widget _invoiceSnapshotSectionTitle(String t) => Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        t,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14.sp,
        ),
      ),
    );

Widget _invoiceSnapshotRowInfo(String label, String? value,
    {VoidCallback? onTap}) {
  final has = (value ?? '').trim().isNotEmpty;
  if (!has) return const SizedBox.shrink();
  final valueText = Text(
    value!,
    style: GoogleFonts.cairo(
      color: onTap == null ? Colors.white : const Color(0xFF93C5FD),
      decoration: onTap == null ? null : TextDecoration.underline,
    ),
  );
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      children: [
        SizedBox(
          width: 120.w,
          child: Text(
            label,
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: onTap == null
              ? valueText
              : InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8.r),
                  child: valueText,
                ),
        ),
      ],
    ),
  );
}

Widget _invoiceSnapshotNoteCard(String t) => _DarkCard(
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.white70, size: 18),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              t,
              style: GoogleFonts.cairo(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

class _InvoiceSnapshotScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InvoiceSnapshotScaffold({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text(
            title,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -120,
              right: -80,
              child: _softCircle(220.r, const Color(0x33FFFFFF)),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _softCircle(260.r, const Color(0x22FFFFFF)),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceTenantSnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  final Future<void> Function(String path) onAttachmentTap;
  final Future<void> Function()? onOpenOriginal;

  const _InvoiceTenantSnapshotScreen({
    required this.snapshot,
    required this.onAttachmentTap,
    this.onOpenOriginal,
  });

  Widget _dateRow(String label, String key) {
    final value = _invoiceSnapshotDateValue(snapshot, key);
    return _invoiceSnapshotRowInfo(
        label, value == null ? null : _fmtDateDynamic(value));
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = _invoiceSnapshotString(snapshot, 'addressLine') != null ||
        _invoiceSnapshotString(snapshot, 'city') != null ||
        _invoiceSnapshotString(snapshot, 'region') != null ||
        _invoiceSnapshotString(snapshot, 'postalCode') != null;
    final hasCompany = _invoiceSnapshotString(snapshot, 'companyName') != null ||
        _invoiceSnapshotString(snapshot, 'companyCommercialRegister') != null ||
        _invoiceSnapshotString(snapshot, 'companyRepresentativeName') != null ||
        _invoiceSnapshotString(snapshot, 'companyRepresentativePhone') != null ||
        _invoiceSnapshotString(snapshot, 'companyBankName') != null ||
        _invoiceSnapshotString(snapshot, 'companyBankAccountNumber') != null ||
        _invoiceSnapshotString(snapshot, 'companyTaxNumber') != null;
    final hasService =
        _invoiceSnapshotString(snapshot, 'serviceSpecialization') != null;
    final tags = _invoiceSnapshotStringList(snapshot, 'tags');
    final attachments = _invoiceSnapshotStringList(snapshot, 'attachmentPaths');
    final isBlacklisted =
        _invoiceSnapshotBoolValue(snapshot, 'isBlacklisted') == true;
    final hasAdditional =
        _invoiceSnapshotString(snapshot, 'emergencyName') != null ||
            _invoiceSnapshotString(snapshot, 'emergencyPhone') != null ||
            _invoiceSnapshotString(snapshot, 'tenantBankName') != null ||
            _invoiceSnapshotString(snapshot, 'tenantBankAccountNumber') !=
                null ||
            _invoiceSnapshotString(snapshot, 'tenantTaxNumber') != null ||
            tags.isNotEmpty ||
            isBlacklisted ||
            _invoiceSnapshotString(snapshot, 'blacklistReason') != null ||
            _invoiceSnapshotString(snapshot, 'notes') != null;

    return _InvoiceSnapshotScaffold(
      title: 'نسخة المستأجر',
      children: [
        _invoiceSnapshotNoteCard(
          'هذه نسخة محفوظة من بيانات المستأجر المرتبط بالعقد وقت إصدار السند. إذا أردت فتح بيانات المستأجر الأصلية، اضغط على اسم المستأجر.',
        ),
        SizedBox(height: 10.h),
        _DarkCard(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle('بيانات المستأجر وقت العقد'),
                _invoiceSnapshotRowInfo(
                  'الاسم',
                  _invoiceSnapshotString(snapshot, 'fullName'),
                  onTap: onOpenOriginal == null ? null : () => onOpenOriginal!(),
                ),
                _invoiceSnapshotRowInfo(
                    'نوع العميل', _invoiceSnapshotString(snapshot, 'clientTypeLabel')),
              _invoiceSnapshotRowInfo(
                  'رقم الهوية', _invoiceSnapshotString(snapshot, 'nationalId')),
              _invoiceSnapshotRowInfo(
                  'رقم الجوال', _invoiceSnapshotString(snapshot, 'phone')),
              _invoiceSnapshotRowInfo(
                  'البريد الإلكتروني', _invoiceSnapshotString(snapshot, 'email')),
              _dateRow('تاريخ الميلاد', 'dateOfBirth'),
              _invoiceSnapshotRowInfo(
                  'الجنسية', _invoiceSnapshotString(snapshot, 'nationality')),
              _dateRow('تاريخ انتهاء الهوية', 'idExpiry'),
            ],
          ),
        ),
        if (hasAddress) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle('العنوان وقت العقد'),
                _invoiceSnapshotRowInfo(
                    'العنوان', _invoiceSnapshotString(snapshot, 'addressLine')),
                _invoiceSnapshotRowInfo(
                    'المدينة', _invoiceSnapshotString(snapshot, 'city')),
                _invoiceSnapshotRowInfo(
                    'المنطقة', _invoiceSnapshotString(snapshot, 'region')),
                _invoiceSnapshotRowInfo('الرمز البريدي',
                    _invoiceSnapshotString(snapshot, 'postalCode')),
              ],
            ),
          ),
        ],
        if (hasAdditional) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle('بيانات إضافية'),
                _invoiceSnapshotRowInfo(
                    'اسم الطوارئ', _invoiceSnapshotString(snapshot, 'emergencyName')),
                _invoiceSnapshotRowInfo('جوال الطوارئ',
                    _invoiceSnapshotString(snapshot, 'emergencyPhone')),
                _invoiceSnapshotRowInfo(
                    'اسم البنك', _invoiceSnapshotString(snapshot, 'tenantBankName')),
                _invoiceSnapshotRowInfo('رقم الحساب',
                    _invoiceSnapshotString(snapshot, 'tenantBankAccountNumber')),
                _invoiceSnapshotRowInfo('الرقم الضريبي',
                    _invoiceSnapshotString(snapshot, 'tenantTaxNumber')),
                _invoiceSnapshotRowInfo(
                    'الوسوم', tags.isEmpty ? null : tags.join('، ')),
                _invoiceSnapshotRowInfo(
                    'في القائمة السوداء', isBlacklisted ? 'نعم' : null),
                _invoiceSnapshotRowInfo('سبب القائمة السوداء',
                    _invoiceSnapshotString(snapshot, 'blacklistReason')),
                _invoiceSnapshotRowInfo(
                    'الملاحظات', _invoiceSnapshotString(snapshot, 'notes')),
              ],
            ),
          ),
        ],
        if (hasCompany) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle('بيانات الشركة وقت العقد'),
                _invoiceSnapshotRowInfo(
                    'اسم الشركة', _invoiceSnapshotString(snapshot, 'companyName')),
                _invoiceSnapshotRowInfo('السجل التجاري',
                    _invoiceSnapshotString(snapshot, 'companyCommercialRegister')),
                _invoiceSnapshotRowInfo('الرقم الضريبي',
                    _invoiceSnapshotString(snapshot, 'companyTaxNumber')),
                _invoiceSnapshotRowInfo('اسم الممثل',
                    _invoiceSnapshotString(snapshot, 'companyRepresentativeName')),
                _invoiceSnapshotRowInfo('جوال الممثل',
                    _invoiceSnapshotString(snapshot, 'companyRepresentativePhone')),
                _invoiceSnapshotRowInfo('بنك الشركة',
                    _invoiceSnapshotString(snapshot, 'companyBankName')),
                _invoiceSnapshotRowInfo('حساب الشركة',
                    _invoiceSnapshotString(snapshot, 'companyBankAccountNumber')),
              ],
            ),
          ),
        ],
        if (hasService) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle('بيانات الخدمة وقت العقد'),
                _invoiceSnapshotRowInfo('التخصص',
                    _invoiceSnapshotString(snapshot, 'serviceSpecialization')),
              ],
            ),
          ),
        ],
        if (attachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle(
                    'مرفقات المستأجر وقت العقد (${attachments.length})'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: attachments.map((path) {
                    return InkWell(
                      onTap: () => onAttachmentTap(path),
                      borderRadius: BorderRadius.circular(10.r),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: Container(
                          width: 92.w,
                          height: 92.w,
                          color: Colors.white.withOpacity(0.08),
                          child: _buildInvoiceSnapshotAttachmentThumb(path),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InvoicePropertySnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> propertySnapshot;
  final Map<String, dynamic>? buildingSnapshot;
  final String? tenantName;
  final Future<void> Function(String path) onAttachmentTap;
  final Future<void> Function()? onOpenOriginalTenant;
  final Future<void> Function()? onOpenOriginalProperty;
  final Future<void> Function()? onOpenOriginalBuilding;

  const _InvoicePropertySnapshotScreen({
    required this.propertySnapshot,
    this.buildingSnapshot,
    this.tenantName,
    required this.onAttachmentTap,
    this.onOpenOriginalTenant,
    this.onOpenOriginalProperty,
    this.onOpenOriginalBuilding,
  });

  Widget _dateRow(Map<String, dynamic> source, String label, String key) {
    final value = _invoiceSnapshotDateValue(source, key);
    return _invoiceSnapshotRowInfo(
        label, value == null ? null : _fmtDateDynamic(value));
  }

  String? _moneyText(Map<String, dynamic> source, String amountKey) {
    final amount = _invoiceSnapshotNumberText(source, amountKey);
    if (amount == null) return null;
    final currency = _invoiceSnapshotString(source, 'currency');
    return currency == null ? amount : '$amount $currency';
  }

  String? _areaText(Map<String, dynamic> source) {
    final area = _invoiceSnapshotNumberText(source, 'area');
    return area == null ? null : '$area م2';
  }

  @override
  Widget build(BuildContext context) {
    final hasBuilding = buildingSnapshot != null && buildingSnapshot!.isNotEmpty;
    final propertyAttachments =
        _invoiceSnapshotStringList(propertySnapshot, 'documentAttachmentPaths');
    final buildingAttachments = hasBuilding
        ? _invoiceSnapshotStringList(buildingSnapshot, 'documentAttachmentPaths')
        : const <String>[];
    final propertyDescription =
        _invoiceSnapshotPropertyFreeDescription(propertySnapshot);
    final buildingDescription = hasBuilding
        ? _invoiceSnapshotPropertyFreeDescription(buildingSnapshot)
        : null;
    final furnishingText =
        _invoiceSnapshotPropertyFurnishingText(propertySnapshot);
    final propertyTypeLabel = _invoiceSnapshotPropertyTypeDisplayLabel(
      propertySnapshot,
      buildingSnapshot: buildingSnapshot,
    );
    final propertyDescriptionLabel = hasBuilding ? 'وصف الوحدة' : 'وصف العقار';
    final propertyTotalUnits =
        _invoiceSnapshotIntValue(propertySnapshot, 'totalUnits');
    final propertyOccupiedUnits =
        _invoiceSnapshotIntValue(propertySnapshot, 'occupiedUnits');
    final effectivePropertyTotalUnits =
        propertyTotalUnits != null && propertyTotalUnits > 0
            ? propertyTotalUnits
            : null;
    final propertyOccupiedDisplay = effectivePropertyTotalUnits == null
        ? null
        : ((propertyOccupiedUnits ?? 0) < 0
            ? 0
            : ((propertyOccupiedUnits ?? 0) > effectivePropertyTotalUnits
                ? effectivePropertyTotalUnits
                : (propertyOccupiedUnits ?? 0)));
    final propertyVacantDisplay =
        effectivePropertyTotalUnits == null || propertyOccupiedDisplay == null
            ? null
            : (effectivePropertyTotalUnits - propertyOccupiedDisplay);
    final buildingTotalUnits =
        hasBuilding ? _invoiceSnapshotIntValue(buildingSnapshot, 'totalUnits') : null;
    final effectiveBuildingTotalUnits =
        buildingTotalUnits != null && buildingTotalUnits > 0
            ? buildingTotalUnits
            : null;
    final rawBuildingOccupiedUnits =
        hasBuilding ? _invoiceSnapshotIntValue(buildingSnapshot, 'occupiedUnits') : null;
    final buildingOccupiedDisplay = !hasBuilding || effectiveBuildingTotalUnits == null
        ? null
        : (() {
            var occupied = rawBuildingOccupiedUnits ?? 0;
            if (occupied <= 0) {
              occupied = (propertyOccupiedUnits != null && propertyOccupiedUnits! > 0)
                  ? propertyOccupiedUnits!
                  : 1;
            }
            if (occupied < 0) return 0;
            if (occupied > effectiveBuildingTotalUnits) {
              return effectiveBuildingTotalUnits;
            }
            return occupied;
          })();
    final buildingVacantDisplay =
        effectiveBuildingTotalUnits == null || buildingOccupiedDisplay == null
            ? null
            : (effectiveBuildingTotalUnits - buildingOccupiedDisplay);
    final buildingTypeLabel = hasBuilding
        ? _invoiceSnapshotBuildingTypeDisplayLabel(buildingSnapshot)
        : null;
    return _InvoiceSnapshotScaffold(
      title: 'نسخة العقار',
      children: [
        _invoiceSnapshotNoteCard(
          'هذه نسخة محفوظة من بيانات العقار المرتبط بالعقد وقت إصدار السند. إذا أردت فتح تفاصيل العقار الأصلي، اضغط على اسم العقار.',
        ),
        SizedBox(height: 10.h),
        _DarkCard(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _invoiceSnapshotSectionTitle('بيانات العقار وقت العقد'),
              _invoiceSnapshotRowInfo(
                'اسم العقار',
                _invoiceSnapshotString(propertySnapshot, 'name'),
                onTap: onOpenOriginalProperty == null
                    ? null
                    : () => onOpenOriginalProperty!(),
              ),
              _invoiceSnapshotRowInfo(
                'اسم المستأجر',
                tenantName?.trim(),
                onTap: onOpenOriginalTenant == null
                    ? null
                    : () => onOpenOriginalTenant!(),
              ),
              _invoiceSnapshotRowInfo('نوع العقار', propertyTypeLabel),
              _invoiceSnapshotRowInfo('المفروشات', furnishingText),
              _invoiceSnapshotRowInfo(
                  'العنوان', _invoiceSnapshotString(propertySnapshot, 'address')),
              _invoiceSnapshotRowInfo(
                  'القيمة الإيجارية', _moneyText(propertySnapshot, 'price')),
              _invoiceSnapshotRowInfo('المساحة', _areaText(propertySnapshot)),
              _invoiceSnapshotRowInfo(
                  'عدد الغرف', _invoiceSnapshotNumberText(propertySnapshot, 'rooms')),
              _invoiceSnapshotRowInfo('عدد الطوابق',
                  _invoiceSnapshotNumberText(propertySnapshot, 'floors')),
              if (!hasBuilding)
                _invoiceSnapshotRowInfo(
                    'عدد الوحدات',
                    effectivePropertyTotalUnits == null
                        ? null
                        : '$effectivePropertyTotalUnits'),
              if (!hasBuilding)
                _invoiceSnapshotRowInfo(
                    'عدد الوحدات المشغولة',
                    propertyOccupiedDisplay == null
                        ? null
                        : '$propertyOccupiedDisplay'),
              if (!hasBuilding)
                _invoiceSnapshotRowInfo(
                    'عدد الوحدات الخالية',
                    propertyVacantDisplay == null ? null : '$propertyVacantDisplay'),
              _invoiceSnapshotRowInfo('وضع التأجير',
                  _invoiceSnapshotString(propertySnapshot, 'rentalModeLabel')),
              _invoiceSnapshotRowInfo('نوع الوثيقة',
                  _invoiceSnapshotString(propertySnapshot, 'documentType')),
              _invoiceSnapshotRowInfo('رقم الوثيقة',
                  _invoiceSnapshotString(propertySnapshot, 'documentNumber')),
              _dateRow(propertySnapshot, 'تاريخ الوثيقة', 'documentDate'),
              _invoiceSnapshotRowInfo('رقم الكهرباء',
                  _invoiceSnapshotString(propertySnapshot, 'electricityNumber')),
              _invoiceSnapshotRowInfo('وضع الكهرباء',
                  _invoiceSnapshotString(propertySnapshot, 'electricityMode')),
              _invoiceSnapshotRowInfo('حصة الكهرباء',
                  _invoiceSnapshotString(propertySnapshot, 'electricityShare')),
              _invoiceSnapshotRowInfo('رقم المياه',
                  _invoiceSnapshotString(propertySnapshot, 'waterNumber')),
              _invoiceSnapshotRowInfo('وضع المياه',
                  _invoiceSnapshotString(propertySnapshot, 'waterMode')),
              _invoiceSnapshotRowInfo('حصة المياه',
                  _invoiceSnapshotString(propertySnapshot, 'waterShare')),
              _invoiceSnapshotRowInfo('قيمة المياه',
                  _invoiceSnapshotString(propertySnapshot, 'waterAmount')),
              _invoiceSnapshotRowInfo(
                  propertyDescriptionLabel, propertyDescription),
              if (hasBuilding) ...[
                _invoiceSnapshotRowInfo(
                  'اسم العمارة',
                  _invoiceSnapshotString(buildingSnapshot, 'name'),
                  onTap: onOpenOriginalBuilding == null
                      ? null
                      : () => onOpenOriginalBuilding!(),
                ),
                _invoiceSnapshotRowInfo(
                    'نوع العقار', buildingTypeLabel),
                _invoiceSnapshotRowInfo(
                    'عنوان العمارة', _invoiceSnapshotString(buildingSnapshot, 'address')),
                _invoiceSnapshotRowInfo('عدد طوابق العمارة',
                    _invoiceSnapshotNumberText(buildingSnapshot, 'floors')),
                _invoiceSnapshotRowInfo(
                    'عدد وحدات العمارة',
                    effectiveBuildingTotalUnits == null
                        ? null
                        : '$effectiveBuildingTotalUnits'),
                _invoiceSnapshotRowInfo(
                    'عدد الوحدات المشغولة',
                    buildingOccupiedDisplay == null
                        ? null
                        : '$buildingOccupiedDisplay'),
                _invoiceSnapshotRowInfo(
                    'عدد الوحدات الخالية',
                    buildingVacantDisplay == null ? null : '$buildingVacantDisplay'),
                _invoiceSnapshotRowInfo('نوع وثيقة\nالعمارة',
                    _invoiceSnapshotString(buildingSnapshot, 'documentType')),
                _invoiceSnapshotRowInfo('رقم وثيقة العمارة',
                    _invoiceSnapshotString(buildingSnapshot, 'documentNumber')),
                _dateRow(buildingSnapshot!, 'تاريخ وثيقة العمارة', 'documentDate'),
                _invoiceSnapshotRowInfo('رقم كهرباء العمارة',
                    _invoiceSnapshotString(buildingSnapshot, 'electricityNumber')),
                _invoiceSnapshotRowInfo('رقم مياه العمارة',
                    _invoiceSnapshotString(buildingSnapshot, 'waterNumber')),
                _invoiceSnapshotRowInfo(
                    'وصف العمارة', buildingDescription),
              ],
            ],
          ),
        ),
        if (propertyAttachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle(
                    'مرفقات العقار وقت العقد (${propertyAttachments.length})'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: propertyAttachments.map((path) {
                    return InkWell(
                      onTap: () => onAttachmentTap(path),
                      borderRadius: BorderRadius.circular(10.r),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: Container(
                          width: 92.w,
                          height: 92.w,
                          color: Colors.white.withOpacity(0.08),
                          child: _buildInvoiceSnapshotAttachmentThumb(path),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
        if (buildingAttachments.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _DarkCard(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _invoiceSnapshotSectionTitle(
                    'مرفقات العمارة وقت العقد (${buildingAttachments.length})'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: buildingAttachments.map((path) {
                    return InkWell(
                      onTap: () => onAttachmentTap(path),
                      borderRadius: BorderRadius.circular(10.r),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: Container(
                          width: 92.w,
                          height: 92.w,
                          color: Colors.white.withOpacity(0.08),
                          child: _buildInvoiceSnapshotAttachmentThumb(path),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
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

Color _statusColor(Invoice inv) {
  final note = (inv.note ?? '').toLowerCase();
  if (note.contains('[reversal]') ||
      note.contains('[reversed]') ||
      note.contains('معكوس')) {
    return const Color(0xFF0F766E);
  }
  if (inv.isCanceled) return const Color(0xFF7F1D1D);
  if (inv.isPaid) return const Color(0xFF065F46);
  if (inv.isOverdue) return const Color(0xFFB91C1C);
  return const Color(0xFF0EA5E9);
}

String _statusText(Invoice inv) {
  final note = (inv.note ?? '').toLowerCase();
  if (note.contains('[reversal]') ||
      note.contains('[reversed]') ||
      note.contains('معكوس')) {
    return 'معكوس';
  }
  if (inv.isCanceled) return 'ملغية';
  if (_isManualInvoiceAny(inv) && note.contains('[posted]')) return 'معتمد';
  if (inv.isPaid) return 'معتمدة';
  if (inv.isOverdue) return 'متأخرة';
  return 'مسودة';
}

const String _manualInvoiceMarker = '[MANUAL]';

bool _isManualInvoiceAny(dynamic inv) {
  try {
    final note = inv is Map
        ? ((inv['note'] ?? inv['notes'])?.toString().toLowerCase() ?? '')
        : ((inv as dynamic).note?.toString().toLowerCase() ?? '');
    return note.contains(_manualInvoiceMarker.toLowerCase());
  } catch (_) {
    return false;
  }
}

bool _invoiceNoteContainsMarker(dynamic inv, String marker) {
  try {
    final note = inv is Map
        ? ((inv['note'] ?? inv['notes'])?.toString().toLowerCase() ?? '')
        : ((inv as dynamic).note?.toString().toLowerCase() ?? '');
    return note.contains(marker.toLowerCase());
  } catch (_) {
    return false;
  }
}

bool _isOwnerPayoutInvoiceAny(dynamic inv) =>
    _invoiceNoteContainsMarker(inv, '[owner_payout]');

bool _isOwnerAdjustmentInvoiceAny(dynamic inv) =>
    _invoiceNoteContainsMarker(inv, '[owner_adjustment]');

bool _isOfficeCommissionInvoiceAny(dynamic inv) =>
    _invoiceNoteContainsMarker(inv, '[office_commission]');

bool _invoiceNoteHasServiceOrigin(String note) {
  final lower = note.toLowerCase();
  return lower.contains('[service]') ||
      lower.contains('[shared_service_office:') ||
      lower.contains('type=water') ||
      lower.contains('type=electricity') ||
      lower.contains('type=internet') ||
      lower.contains('type=cleaning') ||
      lower.contains('type=elevator');
}

String? _sharedServiceOfficeTypeTokenFromNote(String? note) {
  final text = (note ?? '').trim();
  if (text.isEmpty) return null;
  final match = RegExp(
    r'\[SHARED_SERVICE_OFFICE:\s*(water|electricity)\s*\]',
    caseSensitive: false,
  ).firstMatch(text);
  final token = match?.group(1)?.trim().toLowerCase();
  return (token == null || token.isEmpty) ? null : token;
}

String? _sharedServiceVoucherLabelFromText(
  String text, {
  required bool isExpense,
}) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return null;
  final hasSharedService =
      lower.contains('مشترك') || lower.contains('مشتركة') || lower.contains('shared');
  if (!hasSharedService) return null;
  final prefix = isExpense ? 'سداد' : 'تحصيل';
  if (lower.contains('water') || lower.contains('مياه') || lower.contains('ماء')) {
    return '$prefix خدمة مياه مشتركة';
  }
  if (lower.contains('electric') || lower.contains('كهرب')) {
    return '$prefix خدمة كهرباء مشتركة';
  }
  return null;
}

String _stripMaintenanceRequestPrefix(String raw) {
  final text = raw.trim();
  if (text.startsWith('طلب ')) {
    final stripped = text.substring(4).trim();
    if (stripped.isNotEmpty) return stripped;
  }
  return text;
}

String? _maintenanceServiceTypeLabelFromText(String raw) {
  final text = _stripMaintenanceRequestPrefix(raw);
  final lower = text.toLowerCase();
  if (lower.isEmpty) return null;

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
    return null;
  }
  return text.isEmpty ? null : text;
}

String? _invoiceSharedServiceVoucherDisplayTypeAny(dynamic inv) {
  double amount = 0;
  try {
    amount = ((inv as dynamic).amount as num?)?.toDouble() ?? 0.0;
  } catch (_) {}
  final isExpense = amount < 0;
  final segments = <String>[];
  final rawNote = _invoiceRawNoteAny(inv).trim();
  if (rawNote.isNotEmpty) {
    final markerType = _sharedServiceOfficeTypeTokenFromNote(rawNote);
    if (markerType == 'water') return _sharedServiceVoucherLabelFromText(
      'shared water',
      isExpense: isExpense,
    );
    if (markerType == 'electricity') return _sharedServiceVoucherLabelFromText(
      'shared electricity',
      isExpense: isExpense,
    );
    segments.add(rawNote);
  }
  try {
    final snapshot = inv is Map
        ? (inv['maintenanceSnapshot'] as Map?)?.cast<String, dynamic>()
        : ((inv as dynamic).maintenanceSnapshot as Map?)?.cast<String, dynamic>();
    if (snapshot != null && snapshot.isNotEmpty) {
      for (final key in const ['requestType', 'title', 'description']) {
        final value = (snapshot[key] ?? '').toString().trim();
        if (value.isNotEmpty) segments.add(value);
      }
    }
  } catch (_) {}
  try {
    final requestId = _invoiceMaintenanceRequestIdAny(inv);
    if (requestId.isNotEmpty) {
      final boxId = HiveService.maintenanceBoxName();
      if (Hive.isBoxOpen(boxId)) {
        final box = Hive.box<MaintenanceRequest>(boxId);
        final request = box.get(requestId);
        if (request != null) {
          segments.add(request.requestType);
          segments.add(request.title);
          segments.add(request.description);
        }
      }
    }
  } catch (_) {}
  final hay = segments.join('\n').trim();
  if (hay.isEmpty) return null;
  return _sharedServiceVoucherLabelFromText(
    hay,
    isExpense: isExpense,
  );
}

String? _maintenanceVoucherDisplayTypeFromAny(dynamic inv) {
  final rawNote = _invoiceRawNoteAny(inv).trim();
  final sharedOfficeType = _sharedServiceOfficeTypeTokenFromNote(rawNote);
  if (sharedOfficeType == 'water') return 'خدمة مياه مشتركة';
  if (sharedOfficeType == 'electricity') return 'خدمة كهرباء مشتركة';

  final candidates = <String>[];
  final cleanNote = _cleanInvoiceDisplayNote(rawNote).trim();
  if (cleanNote.isNotEmpty) candidates.add(cleanNote);

  try {
    final snapshot = inv is Map
        ? (inv['maintenanceSnapshot'] as Map?)?.cast<String, dynamic>()
        : ((inv as dynamic).maintenanceSnapshot as Map?)?.cast<String, dynamic>();
    if (snapshot != null && snapshot.isNotEmpty) {
      for (final key in const ['requestType', 'title', 'description']) {
        final value = (snapshot[key] ?? '').toString().trim();
        if (value.isNotEmpty) candidates.add(value);
      }
    }
  } catch (_) {}

  try {
    final requestId = _invoiceMaintenanceRequestIdAny(inv);
    if (requestId.isNotEmpty) {
      final boxId = HiveService.maintenanceBoxName();
      if (Hive.isBoxOpen(boxId)) {
        final box = Hive.box<MaintenanceRequest>(boxId);
        final request = box.get(requestId);
        if (request != null) {
          candidates.add(request.requestType);
          candidates.add(request.title);
          candidates.add(request.description);
        }
      }
    }
  } catch (_) {}

  for (final candidate in candidates) {
    final label = _maintenanceServiceTypeLabelFromText(candidate);
    if (label != null && label.isNotEmpty) return label;
  }

  final combined = candidates.join('\n').trim();
  if (combined.isEmpty) return null;
  return _maintenanceServiceTypeLabelFromText(combined);
}

MaintenanceReceiptDetails _maintenanceDetailsFromInvoiceFallback(
  Invoice invoice,
) {
  final created = invoice.issueDate;
  final rawNote = (invoice.note ?? '').trim();
  final cleanDesc = _cleanInvoiceDisplayNote(rawNote).trim();
  final manualTitle = (_manualInvoiceTitle(rawNote) ?? '').trim();
  final inferredType =
      _maintenanceVoucherDisplayTypeFromAny(invoice) ?? 'خدمات';
  final linkedRequestId = (invoice.maintenanceRequestId ?? '').trim();
  final baseId = linkedRequestId.isNotEmpty ? linkedRequestId : invoice.id;
  final invoiceRef =
      (invoice.serialNo ?? '').trim().isNotEmpty ? invoice.serialNo! : invoice.id;
  final firstDescLine = cleanDesc
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final resolvedTitle = manualTitle.isNotEmpty
      ? manualTitle
      : (firstDescLine.isNotEmpty
          ? firstDescLine
          : (inferredType == 'خدمات' ? 'طلب خدمات' : inferredType));
  final resolvedDescription =
      cleanDesc.isNotEmpty ? cleanDesc : rawNote;
  final isWaterCompanyOfficeExpense =
      manualTitle == 'فاتورة شركة المياه' &&
      (_manualInvoicePartyName(rawNote) ?? '').trim() == 'المكتب' &&
      rawNote.toLowerCase().contains('type=water');
  return MaintenanceReceiptDetails(
    id: baseId,
    invoiceId: invoiceRef,
    requestType: inferredType,
    title: resolvedTitle,
    description: resolvedDescription,
    priority: MaintenancePriority.medium,
    assignedTo: null,
    providerSnapshot: isWaterCompanyOfficeExpense
        ? <String, dynamic>{
            'specialVoucherKind': 'water_company_office_expense',
          }
        : null,
    createdAt: created,
    scheduledDate: isWaterCompanyOfficeExpense ? invoice.dueDate : created,
    executionDeadline:
        isWaterCompanyOfficeExpense ? null : invoice.dueDate,
    cost: invoice.amount.abs(),
    tenantId: invoice.tenantId.isEmpty ? null : invoice.tenantId,
    propertyId: invoice.propertyId.isEmpty ? null : invoice.propertyId,
  );
}

String _invoiceMaintenanceRequestIdAny(dynamic inv) {
  try {
    final raw = inv is Map
        ? (inv['maintenanceRequestId'] ?? '')
        : ((inv as dynamic).maintenanceRequestId ?? '');
    return raw.toString().trim();
  } catch (_) {
    return '';
  }
}

String _officeCommissionLinkedContractVoucherIdAny(dynamic inv) {
  return (_manualInvoiceMarkerValue(_invoiceRawNoteAny(inv), 'CONTRACT_VOUCHER_ID') ??
          '')
      .trim();
}

String _invoiceRawNoteAny(dynamic inv) {
  try {
    return inv is Map
        ? ((inv['note'] ?? inv['notes'])?.toString() ?? '')
        : ((inv as dynamic).note?.toString() ?? '');
  } catch (_) {
    return '';
  }
}

String _manualInvoiceDisplayType(dynamic inv, {required double amount}) {
  final title = _manualInvoiceTitle(_invoiceRawNoteAny(inv));
  if ((title ?? '').trim().isNotEmpty) {
    return title!.trim();
  }
  final cleanNote = _cleanInvoiceDisplayNote(_invoiceRawNoteAny(inv));
  final firstLine = cleanNote
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final normalized = firstLine.toLowerCase();

  if (normalized.contains('مصروف إداري للمكتب')) return 'مصروف إداري';
  if (normalized.contains('مقبوض للمكتب')) return 'مقبوض للمكتب';
  if (normalized.contains('تحويل من رصيد المكتب') ||
      normalized.contains('سحب من رصيد المكتب')) {
    return 'تحويل من رصيد المكتب';
  }
  if (normalized.contains('إيراد عمولة للمكتب') ||
      normalized.contains('عمولة مكتب')) {
    return 'عمولة مكتب';
  }
  if (firstLine.isNotEmpty) return firstLine;
  return amount < 0 ? 'صرف يدوي' : 'قبض يدوي';
}

String? _manualInvoiceMarkerValue(String? note, String key) {
  final text = (note ?? '').trim();
  if (text.isEmpty) return null;
  final exp = RegExp('\\[$key:(.*?)\\]', caseSensitive: false);
  final match = exp.firstMatch(text);
  final value = match?.group(1)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

String? _manualInvoicePartyName(String? note) =>
    _manualInvoiceMarkerValue(note, 'PARTY');

String? _manualInvoicePropertyName(String? note) =>
    _normalizeManualInvoicePropertyName(
      _manualInvoiceMarkerValue(note, 'PROPERTY'),
    );

String? _manualInvoicePartyId(String? note) =>
    _manualInvoiceMarkerValue(note, 'PARTY_ID');

String? _manualInvoicePropertyId(String? note) =>
    _manualInvoiceMarkerValue(note, 'PROPERTY_ID');

String? _manualInvoiceTitle(String? note) =>
    _manualInvoiceMarkerValue(note, 'TITLE');

bool _isOfficeManualInvoiceNote(String? note) {
  final raw = (note ?? '').trim();
  if (raw.isEmpty) return false;
  final lower = raw.toLowerCase();
  if (!lower.contains(_manualInvoiceMarker.toLowerCase())) return false;

  final party = (_manualInvoicePartyName(note) ?? '').trim();
  if (party == 'المكتب') return true;

  return lower.contains('[office_commission]') ||
      lower.contains('[office_withdrawal]') ||
      lower.contains('مصروف إداري للمكتب') ||
      lower.contains('مقبوض للمكتب') ||
      lower.contains('تحويل من رصيد المكتب') ||
      lower.contains('سحب من رصيد المكتب') ||
      lower.contains('إيراد عمولة للمكتب');
}

bool _shouldShowInvoicePaymentMethod(Invoice invoice) {
  if (!_isManualInvoiceAny(invoice)) return false;
  if (_isOfficeManualInvoiceNote(invoice.note)) return false;
  return invoice.paymentMethod.trim().isNotEmpty;
}

String? _normalizeManualInvoicePropertyName(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty ||
      text == 'جميع العقارات معًا' ||
      text == 'إظهار جميع العقارات معًا') {
    return null;
  }
  return text;
}

String _cleanInvoiceDisplayNote(String? note) {
  final raw = (note ?? '').trim();
  if (raw.isEmpty) return '';
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) {
        if (line.isEmpty) return false;
        final lower = line.toLowerCase();
        return lower != _manualInvoiceMarker.toLowerCase() &&
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

bool _shouldUseGeneratedContractRentStatement(Invoice invoice, String cleanNote) {
  if (_isManualInvoiceAny(invoice)) return false;
  if (_isOfficeCommissionInvoiceAny(invoice)) return false;
  if (invoice.contractId.trim().isEmpty) return false;
  if (invoice.amount <= 0) return false;
  final normalized = cleanNote.trim();
  if (normalized.isEmpty) return true;
  return normalized.startsWith('سداد قيمة إيجار') ||
      normalized.startsWith('سداد عقد رقم');
}

String _appendInvoicePropertyReferenceToStatement(
  String statement,
  String propertyRef,
) {
  final normalizedStatement = statement.trim();
  final normalizedPropertyRef = propertyRef.trim();
  if (normalizedPropertyRef.isEmpty || normalizedPropertyRef == '—') {
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

String _invoiceDisplayStatementText({
  required Invoice invoice,
  required String ejarNo,
  required String propertyRef,
}) {
  final cleanNote = _cleanInvoiceDisplayNote(invoice.note);
  if (_isMaintenanceAny(invoice)) {
    final base = cleanNote.isNotEmpty ? cleanNote : 'خدمات';
    return _appendInvoicePropertyReferenceToStatement(base, propertyRef);
  }

  if (!_shouldUseGeneratedContractRentStatement(invoice, cleanNote)) {
    return cleanNote;
  }

  final normalizedEjarNo = ejarNo.trim();
  final normalizedPropertyRef = propertyRef.trim();
  var firstLine = normalizedEjarNo.isNotEmpty
      ? 'سداد قيمة إيجار عقد رقم $normalizedEjarNo'
      : 'سداد قيمة إيجار';
  if (normalizedPropertyRef.isNotEmpty && normalizedPropertyRef != '—') {
    firstLine = '$firstLine • $normalizedPropertyRef';
  }

  final waterAmount = _invoiceWaterAmount(invoice);
  if (waterAmount <= 0) return firstLine;
  return '$firstLine\nمياه (قسط): ${_fmtMoneyTrunc(waterAmount)}';
}

String _buildManualInvoiceNote({
  required String title,
  required String description,
  String? partyName,
  String? propertyName,
  String? partyId,
  String? propertyId,
}) {
  final lines = <String>[_manualInvoiceMarker];
  final cleanTitle = title.trim();
  final cleanParty = (partyName ?? '').trim();
  final cleanProperty = (propertyName ?? '').trim();
  final cleanPartyId = (partyId ?? '').trim();
  final cleanPropertyId = (propertyId ?? '').trim();
  final cleanDescription = description.trim();
  if (cleanTitle.isNotEmpty) lines.add('[TITLE: $cleanTitle]');
  if (cleanParty.isNotEmpty) lines.add('[PARTY: $cleanParty]');
  if (cleanProperty.isNotEmpty) lines.add('[PROPERTY: $cleanProperty]');
  if (cleanPartyId.isNotEmpty) lines.add('[PARTY_ID: $cleanPartyId]');
  if (cleanPropertyId.isNotEmpty) lines.add('[PROPERTY_ID: $cleanPropertyId]');
  if (cleanDescription.isNotEmpty) lines.add(cleanDescription);
  return lines.join('\n');
}

// يحدد نوع السند للعرض
Widget _invoiceTypeLabel(dynamic inv) {
  final isMaintenance = _isMaintenanceAny(inv);
  final isManual = _isManualInvoiceAny(inv);
  final isOwnerPayout = _isOwnerPayoutInvoiceAny(inv);
  final isOwnerAdjustment = _isOwnerAdjustmentInvoiceAny(inv);
  final isOfficeCommission = _isOfficeCommissionInvoiceAny(inv);
  final maintenanceTypeLabel = _maintenanceVoucherDisplayTypeFromAny(inv);
  double amount = 0;
  try {
    amount = ((inv as dynamic).amount as num?)?.toDouble() ?? 0;
  } catch (_) {}
  final isExpense = isMaintenance || amount < 0;
  final mainLabel = isExpense ? 'سند صرف' : 'سند قبض';
  final subLabel = isMaintenance
      ? (maintenanceTypeLabel ?? 'خدمات')
      : (isOwnerPayout
          ? 'تحويل للمالك'
          : (isOwnerAdjustment
              ? 'خصم/تسوية للمالك'
              : (isOfficeCommission
                  ? 'عمولة مكتب'
                  : (isManual
                      ? _manualInvoiceDisplayType(inv, amount: amount)
                      : 'عقد إيجار'))));
  final accentColor = isExpense
      ? const Color(0xFFE11D48)
      : const Color(0xFF22C55E);
  return Row(
    children: [
      Container(
        width: 3.5.w,
        height: 34.h,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
      ),
      SizedBox(width: 10.w),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mainLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16.sp),
            ),
            SizedBox(height: 2.h),
            Text(
              subLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontSize: 11.sp),
            ),
          ],
        ),
      ),
    ],
  );
}

// يتحقق هل السند خدمات (يدعم Map أو Invoice) مع Fallback على الملاحظات
bool _isMaintenanceAny(dynamic inv) {
  try {
    if (_invoiceSharedServiceVoucherDisplayTypeAny(inv) != null) return true;
    final noteText = _invoiceRawNoteAny(inv);
    final lowerNote = noteText.toLowerCase();
    if (_invoiceMaintenanceRequestIdAny(inv).isNotEmpty) return true;
    if (_invoiceNoteHasServiceOrigin(lowerNote)) return true;

    if (inv is Map) {
      final notes = ((inv['note'] ?? inv['notes'])?.toString().toLowerCase() ?? '');
      if (notes.contains(_manualInvoiceMarker.toLowerCase())) return false;
      final kind =
          (inv['type'] ?? inv['requestType'])?.toString().toLowerCase() ?? '';
      if (kind.contains('خدمات') || kind.contains('maintenance')) return true;

      // fallback: لو ما فيه type، جرّب الملاحظات
      return notes.contains('خدمات') || notes.contains('maintenance');
    } else {
      // كائن Invoice: ما فيه type، فاعتمد على note كـ fallback
      if (lowerNote.contains(_manualInvoiceMarker.toLowerCase())) return false;
      return lowerNote.contains('خدمات') || lowerNote.contains('maintenance');
    }
  } catch (_) {
    return false;
  }
}

/// ===============================================================================
/// توليد رقم تسلسلي للسند (YYYY-####) مع تخزين آخر تسلسل في sessionBox
/// ===============================================================================
/// مولّد رقم السند بناءً على أعلى رقم موجود في نفس السنة داخل صندوق السندات فقط
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

enum _OriginFilter { all, contracts, maintenance, manual }

_OriginFilter? _originFilterFromArg(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  switch (normalized) {
    case 'contracts':
      return _OriginFilter.contracts;
    case 'maintenance':
      return _OriginFilter.maintenance;
    case 'manual':
      return _OriginFilter.manual;
    case 'all':
      return _OriginFilter.all;
    default:
      return null;
  }
}

enum _ContractScope { all, active, ended }

enum _InvoiceStatusFilter { all, canceled }

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
  _OriginFilter _fOrigin = _OriginFilter.all; // افتراضي: الكل
  _ContractScope? _fContractScope; // null حتى يُختار
  _InvoiceStatusFilter _fInvoiceStatus = _InvoiceStatusFilter.all;
  _ArchFilter _fArch = _ArchFilter.unarchived; // افتراضي: غير مؤرشفة

  bool get _hasActiveFilters =>
      _fOrigin != _OriginFilter.all ||
      ((_fContractScope ?? _ContractScope.all) != _ContractScope.all) ||
      _fInvoiceStatus != _InvoiceStatusFilter.all ||
      _fArch == _ArchFilter.archived;

  String _currentFilterLabel() {
    final parts = <String>[];
    parts.add(_fArch == _ArchFilter.archived ? 'المؤرشفة' : 'الكل');

    switch (_fOrigin) {
      case _OriginFilter.contracts:
        parts.add('سندات العقود');
        break;
      case _OriginFilter.maintenance:
        parts.add('سندات الخدمات');
        break;
      case _OriginFilter.manual:
        parts.add('سندات أخرى');
        break;
      case _OriginFilter.all:
        break;
    }

    switch (_fContractScope ?? _ContractScope.all) {
      case _ContractScope.active:
        parts.add('سارية');
        break;
      case _ContractScope.ended:
        parts.add('منتهية');
        break;
      case _ContractScope.all:
        break;
    }

    switch (_fInvoiceStatus) {
      case _InvoiceStatusFilter.canceled:
        parts.add('ملغية');
        break;
      case _InvoiceStatusFilter.all:
        break;
    }

    return parts.join(' • ');
  }

  String? _openInvoiceId; // يأتينا من شاشة الخدمات
  bool _didHandleOpen = false; // حتى لا يتكرر الفتح

  // تمييز سندات الخدمات من الملاحظة
  bool _isMaintenance(Invoice inv) {
    return _isMaintenanceAny(inv);
  }

  StreamSubscription<BoxEvent>? _rawListen;

  final GlobalKey _bottomNavKey = GlobalKey();
  double _bottomBarHeight = kBottomNavigationBarHeight;

  bool _invoicesReady = false; // ✅ لا نستخدم الصندوق داخل build قبل الفتح

  // === افتح صندوق السندات Typed قبل أي استعمال (محلي داخل الكلاس) ===
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

      // تأكيد تسجيل الـAdapter وفتح صندوق السندات typed إن لم يُفتح
      await _ensureInvoicesBoxTyped();

      await _bootstrapRawWatcher();

      if (mounted) {
        setState(() => _invoicesReady = true);
      }

      // افتح السند لو جاي من شاشة الخدمات وتم تمرير openId
      if (mounted && _openInvoiceId != null) {
        final inv = Hive.box<Invoice>(invoicesBoxName()).get(_openInvoiceId!);
        _openInvoiceId = null;
        if (inv != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => InvoiceDetailsScreen(invoice: inv)),
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
    if (args is Map) {
      final initialOrigin = _originFilterFromArg(args['initialOrigin']);
      if (initialOrigin != null) {
        _fOrigin = initialOrigin;
      }
      if (args['openId'] is String && (args['openId'] as String).isNotEmpty) {
        _openInvoiceId = args['openId'] as String;
      }
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
        } else if (v is Invoice &&
            (v.serialNo == null || v.serialNo!.isEmpty)) {
          // عيّن رقمًا تلقائيًا للقديمة بدون رقم
          v.serialNo = _nextInvoiceSerialSync(_invoices);
          v.updatedAt = KsaTime.now();
          await v.save();
        }
      }
    } catch (_) {}
  }

  Future<MaintenanceRequest?> _loadMaintenanceRequestForInvoice(
      Invoice invoice) async {
    final invoiceId = (invoice.id).trim();
    final serialNo = (invoice.serialNo ?? '').trim();
    final requestId = (invoice.maintenanceRequestId ?? '').trim();

    if (invoiceId.isEmpty && serialNo.isEmpty) return null;

    final boxId = HiveService.maintenanceBoxName();
    if (!Hive.isBoxOpen(boxId)) {
      await Hive.openBox<MaintenanceRequest>(boxId);
    }
    final box = Hive.box<MaintenanceRequest>(boxId);
    if (requestId.isNotEmpty) {
      final exact = box.get(requestId);
      if (exact != null) return exact;
    }
    return firstWhereOrNull(box.values, (m) {
      final storedId = (m.invoiceId ?? '').trim();
      if (storedId.isEmpty) return false;
      if (storedId == invoiceId) return true;
      if (serialNo.isNotEmpty && storedId == serialNo) return true;
      return false;
    });
  }

  MaintenanceReceiptDetails? _maintenanceDetailsFromSnapshot(Invoice invoice) {
    final snapshot = invoice.maintenanceSnapshot;
    if (snapshot == null || snapshot.isEmpty) return null;
    try {
      return MaintenanceReceiptDetails.fromMap(snapshot);
    } catch (_) {
      return null;
    }
  }

  bool _contractEndedBy(Invoice inv) {
    final c =
        firstWhereOrNull(_contracts.values, (x) => x.id == inv.contractId);
    if (c == null) return false; // غير مربوط بعقد

    // ✅ منتهي يدويًا أو بالتاريخ
    if (c.isTerminated == true) return true;

    final today = KsaTime.today();
    return !today.isBefore(c.endDate); // اليوم >= نهاية العقد
  }

  Future<void> _showBlockDialog(String msg) async {
    await _showInvoiceArchiveNoticeDialog(context, message: msg);
  }

  Future<void> _exportInvoicePdf(Invoice invoice) async {
    final isManual = _isManualInvoiceAny(invoice);
    final manualPartyId = isManual ? _manualInvoicePartyId(invoice.note) : null;
    final manualPropertyId =
        isManual ? _manualInvoicePropertyId(invoice.note) : null;
    final tenant = firstWhereOrNull(
      _tenants.values,
      (x) => x.id == (invoice.tenantId.trim().isNotEmpty ? invoice.tenantId : manualPartyId),
    );
    final property = firstWhereOrNull(
      _properties.values,
      (x) => x.id == (invoice.propertyId.trim().isNotEmpty ? invoice.propertyId : manualPropertyId),
    );
    final contract =
        firstWhereOrNull(_contracts.values, (x) => x.id == invoice.contractId);
    final ejarNo = (contract?.ejarContractNo ?? '').trim().isNotEmpty
        ? (contract!.ejarContractNo ?? '').trim()
        : await _readEjarNoLocalAsync(invoice.contractId);
    final building = property?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (x) => x.id == property!.parentBuildingId);
    final propertySnapshot = _invoiceSnapshotMapOrNull(contract?.propertySnapshot) ??
        (property == null ? null : _buildInvoicePropertySnapshot(property));
    final buildingSnapshot = _invoiceSnapshotMapOrNull(contract?.buildingSnapshot) ??
        (building == null ? null : _buildInvoicePropertySnapshot(building));
    final propertyRef = _invoicePropertyReference(
      property: property,
      building: building,
      propertySnapshot: propertySnapshot,
      buildingSnapshot: buildingSnapshot,
      fallbackName: property?.name,
    );
    final statementText = _invoiceDisplayStatementText(
      invoice: invoice,
      ejarNo: ejarNo,
      propertyRef: propertyRef,
    );
    final maintenanceRequest = await _loadMaintenanceRequestForInvoice(invoice);
    final hasMaintenanceLink =
        (invoice.maintenanceRequestId ?? '').trim().isNotEmpty;
    MaintenanceReceiptDetails? maintenanceDetails;
    if (maintenanceRequest != null) {
      maintenanceDetails =
          MaintenanceReceiptDetails.fromRequest(maintenanceRequest);
    } else {
      maintenanceDetails = _maintenanceDetailsFromSnapshot(invoice);
      if (maintenanceDetails == null &&
          (hasMaintenanceLink || _isMaintenanceAny(invoice))) {
        maintenanceDetails = _maintenanceDetailsFromInvoiceFallback(invoice);
      }
    }
    if (maintenanceDetails != null) {
      await PdfExportService.shareMaintenanceDetailsPdf(
        context: context,
        details: maintenanceDetails,
        property: property,
        relatedInvoices: [invoice],
      );
      return;
    }
    await PdfExportService.shareInvoiceDetailsPdf(
      context: context,
      invoice: invoice,
      tenant: tenant,
      property: property,
      contract: contract,
      ejarContractNo: ejarNo,
      rentOnlyAmount: _invoiceRentOnlyAmount(invoice),
      waterAmount: _invoiceWaterAmount(invoice),
      statementText: statementText,
    );
  }

  /// يُسمح بالأرشفة إذا كانت السند غير مدفوعة.
  /// إن كانت "مدفوعة": تُسمح فقط إذا كانت مربوطة بعقد منتهي.
  Future<bool> _ensureCanArchive(Invoice inv) async {
    // ✅ السماح دائمًا لسندات الخدمات
    if (_isMaintenanceAny(inv)) return true;

    if (!inv.isPaid) return true;
    if ((inv.contractId).isEmpty) {
      await _showBlockDialog(
          'لا يمكن أرشفة السند المدفوع لأنها غير مرتبطة بعقد.');
      return false;
    }
    if (!_contractEndedBy(inv)) {
      await _showBlockDialog(
          'لا يمكن أرشفة السند المدفوع إلا إذا كان العقد منتهي.');
      return false;
    }
    return true;
  }

  Invoice _mapToInvoice(Map m) {
    final id =
        (m['id'] as String?) ?? KsaTime.now().microsecondsSinceEpoch.toString();
    final tenantId = (m['tenantId'] as String?) ?? '';
    final propertyId = (m['propertyId'] as String?) ?? '';

    final issueDate =
        (m['date'] is DateTime) ? m['date'] as DateTime : KsaTime.now();
    final dueDate =
        (m['dueDate'] is DateTime) ? m['dueDate'] as DateTime : issueDate;

    final note = (m['notes'] as String?);
    final createdAt = (m['createdAt'] is DateTime)
        ? m['createdAt'] as DateTime
        : KsaTime.now();

    String contractId = (m['contractId'] as String?) ?? '';
    if (contractId.isEmpty) {
      try {
        final dt = issueDate;
        final match = firstWhereOrNull(
            _contracts.values,
            (c) =>
                c.tenantId == tenantId &&
                c.propertyId == propertyId &&
                !dt.isBefore(c.startDate) &&
                !dt.isAfter(c.endDate));
        contractId = match?.id ?? '';
      } catch (_) {}
    }

    final Contract? c =
        firstWhereOrNull(_contracts.values, (x) => x.id == contractId);

    double amount = 0.0;
    if (m['amount'] is num) {
      amount = (m['amount'] as num).toDouble();
    } else if (c != null) {
      amount = c.rentAmount;
    }

    final String currency =
        (m['currency'] as String?) ?? (c?.currency ?? 'SAR');
    final double paidAmount = (m['paidAmount'] is num)
        ? (m['paidAmount'] as num).toDouble()
        : amount; // تركناها كالسابق

    // رقم السند
    final serialNo =
        (m['serialNo'] as String?) ?? _nextInvoiceSerialSync(_invoices);
    final maintenanceRequestIdRaw =
        (m['maintenanceRequestId'] as String?) ?? '';
    final maintenanceSnapshotRaw =
        (m['maintenanceSnapshot'] as Map?)?.cast<String, dynamic>();
    final attachmentPaths = ((m['attachmentPaths'] as List?) ??
            (m['attachments'] as List?) ??
            const <dynamic>[])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

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
      attachmentPaths: attachmentPaths,
      maintenanceRequestId: maintenanceRequestIdRaw.trim().isEmpty
          ? null
          : maintenanceRequestIdRaw.trim(),
      maintenanceSnapshot: maintenanceSnapshotRaw,
      createdAt: createdAt,
      updatedAt: KsaTime.now(),
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  Future<void> _openAddManualInvoice() async {
    if (await OfficeClientGuard.blockIfOfficeClient(context)) return;

    final created = await Navigator.of(context).push<Invoice>(
      MaterialPageRoute(builder: (_) => const AddManualInvoiceScreen()),
    );
    if (!mounted || created == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(invoice: created),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        var tOrigin = _fOrigin;
        _ContractScope? tScope = _fContractScope;
        var tInvoiceStatus = _fInvoiceStatus;
        var tArch = _fArch;

        InputDecoration _deco(String label) => InputDecoration(
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

        return StatefulBuilder(
          builder: (context, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  16.h + MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                      child: Text('تصفية',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800))),
                  SizedBox(height: 12.h),

                  // (1) الحالة = المصدر
                  DropdownButtonFormField<_OriginFilter>(
                    value: tOrigin,
                    decoration: _deco('الحالة'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white),
                    items: const [
                      DropdownMenuItem(
                          value: _OriginFilter.all, child: Text('الكل')),
                      DropdownMenuItem(
                          value: _OriginFilter.contracts,
                          child: Text('سندات العقود')),
                      DropdownMenuItem(
                          value: _OriginFilter.maintenance,
                          child: Text('سندات الخدمات')),
                      DropdownMenuItem(
                          value: _OriginFilter.manual,
                          child: Text('سندات أخرى')),
                    ],
                    onChanged: (v) => setM(() {
                      tOrigin = v ?? _OriginFilter.all;
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
                        DropdownMenuItem(
                            value: _ContractScope.all, child: Text('الكل')),
                        DropdownMenuItem(
                            value: _ContractScope.active, child: Text('سارية')),
                        DropdownMenuItem(
                            value: _ContractScope.ended, child: Text('منتهية')),
                      ],
                      onChanged: (v) => setM(() {
                        tScope = v ?? _ContractScope.all;
                      }),
                    ),
                    SizedBox(height: 10.h),
                  ],

                  DropdownButtonFormField<_InvoiceStatusFilter>(
                    value: tInvoiceStatus,
                    decoration: _deco('حالة السند'),
                    dropdownColor: const Color(0xFF0B1220),
                    iconEnabledColor: Colors.white70,
                    style: GoogleFonts.cairo(color: Colors.white),
                    items: const [
                      DropdownMenuItem(
                          value: _InvoiceStatusFilter.all,
                          child: Text('الكل')),
                      DropdownMenuItem(
                          value: _InvoiceStatusFilter.canceled,
                          child: Text('ملغية')),
                    ],
                    onChanged: (v) => setM(() {
                      tInvoiceStatus = v ?? _InvoiceStatusFilter.all;
                      tArch = tInvoiceStatus == _InvoiceStatusFilter.canceled
                          ? _ArchFilter.archived
                          : _ArchFilter.unarchived;
                    }),
                  ),
                  SizedBox(height: 10.h),

                  // (3) الأرشفة — تظهر دائمًا الآن
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('الأرشفة',
                        style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text('غير مؤرشفة', style: GoogleFonts.cairo()),
                          selected: tArch == _ArchFilter.unarchived,
                          onSelected: (_) =>
                              setM(() => tArch = _ArchFilter.unarchived),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('مؤرشفة', style: GoogleFonts.cairo()),
                          selected: tArch == _ArchFilter.archived,
                          onSelected: (_) =>
                              setM(() => tArch = _ArchFilter.archived),
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
                              _fOrigin = tOrigin;
                              _fContractScope = tScope;
                              _fInvoiceStatus = tInvoiceStatus;
                              _fArch =
                                  tInvoiceStatus == _InvoiceStatusFilter.canceled
                                      ? _ArchFilter.archived
                                      : tArch;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          child: Text('تصفية',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _fOrigin = _OriginFilter.all;
                              _fContractScope = null;
                              _fInvoiceStatus = _InvoiceStatusFilter.all;
                              _fArch = _ArchFilter.unarchived;
                            });
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24)),
                          child: Text('إلغاء',
                              style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
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
            title: Text('السندات',
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20.sp)),
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
          title: Text('السندات',
              style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20.sp)),
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
                gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF0F766E),
                      Color(0xFF14B8A6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالطرف/العقار/المبلغ',
                      hintStyle: GoogleFonts.cairo(color: Colors.white70),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ),
                if (_hasActiveFilters)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded,
                                size: 16, color: Colors.white70),
                            SizedBox(width: 6.w),
                            Text(
                              _currentFilterLabel(),
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _invoices.listenable(),
                    builder: (context, Box<Invoice> box, _) {
                      // 🚀 تحسين الأداء: كاش للأسماء وتفاصيل العقود للوصول الفوري
                      final tenantNames = {
                        for (var t in _tenants.values)
                          t.id: t.fullName.toLowerCase()
                      };
                      final propertyNames = {
                        for (var p in _properties.values)
                          p.id: p.name.toLowerCase()
                      };
                      final contractsMap = {
                        for (var c in _contracts.values) c.id: c
                      };
                      final invoicesMap = {for (var i in box.values) i.id: i};

                      var items = box.values.toList();

                      // فلتر المصدر/الحالة
                      bool isMaint(Invoice inv) => _isMaintenance(inv);
                      bool isManual(Invoice inv) => _isManualInvoiceAny(inv);
                      String contractOriginId(Invoice inv) {
                        final direct = inv.contractId.trim();
                        if (direct.isNotEmpty) return direct;
                        if (!_isOfficeCommissionInvoiceAny(inv)) return '';
                        final linkedVoucherId =
                            _officeCommissionLinkedContractVoucherIdAny(inv);
                        if (linkedVoucherId.isEmpty) return '';
                        final linkedVoucher = invoicesMap[linkedVoucherId];
                        if (linkedVoucher == null) return '';
                        return linkedVoucher.contractId.trim();
                      }

                      bool isContractOrigin(Invoice inv) {
                        return contractOriginId(inv).isNotEmpty;
                      }

                      if (_fOrigin == _OriginFilter.contracts) {
                        items = items.where((i) => isContractOrigin(i)).toList();

                        // نطاق العقود محسّن بدون firstWhereOrNull
                        if (_fContractScope == _ContractScope.active) {
                          items = items.where((i) {
                            final c = contractsMap[contractOriginId(i)];
                            if (c == null) return false;
                            final ended = c.isTerminated == true ||
                                !KsaTime.today().isBefore(c.endDate);
                            return !ended;
                          }).toList();
                        } else if (_fContractScope == _ContractScope.ended) {
                          items = items.where((i) {
                            final c = contractsMap[contractOriginId(i)];
                            if (c == null) return false;
                            final ended = c.isTerminated == true ||
                                !KsaTime.today().isBefore(c.endDate);
                            return ended;
                          }).toList();
                        }
                      } else if (_fOrigin == _OriginFilter.maintenance) {
                        items = items.where((i) => isMaint(i)).toList();
                      } else if (_fOrigin == _OriginFilter.manual) {
                        items = items.where((i) => isManual(i)).toList();
                      }

                      if (_fInvoiceStatus == _InvoiceStatusFilter.canceled) {
                        items = items.where((i) => i.isCanceled).toList();
                      }

                      // فلتر الأرشفة
                      if (_fArch == _ArchFilter.archived) {
                        items = items.where((i) => i.isArchived).toList();
                      } else {
                        items = items.where((i) => !i.isArchived).toList();
                      }

                      // البحث المحسّن
                      if (_q.isNotEmpty) {
                        final q = _q.toLowerCase();
                        items = items.where((inv) {
                          final tn = (tenantNames[inv.tenantId] ??
                                  _manualInvoicePartyName(inv.note) ??
                                  '')
                              .toLowerCase();
                          final pn = (propertyNames[inv.propertyId] ??
                                  _manualInvoicePropertyName(inv.note) ??
                                  '')
                              .toLowerCase();
                          final amt = inv.amount.toString();
                          final sn = (inv.serialNo ?? '').toLowerCase();
                          return tn.contains(q) ||
                              pn.contains(q) ||
                              amt.contains(q) ||
                              sn.contains(q);
                        }).toList();
                      }

                      // ترتيب
                      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            'لا توجد سندات',
                            style: GoogleFonts.cairo(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          final inv = items[i];
                          final remaining = inv.remaining;

                          return InkWell(
                            borderRadius: BorderRadius.circular(16.r),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        InvoiceDetailsScreen(invoice: inv)),
                              );
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
                                          colors: [
                                            Color(0xFF0F766E),
                                            Color(0xFF14B8A6)
                                          ],
                                          begin: Alignment.topRight,
                                          end: Alignment.bottomLeft),
                                    ),
                                    child: const Icon(
                                        Icons.receipt_long_rounded,
                                        color: Colors.white),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                                child: _invoiceTypeLabel(inv)),
                                            _chip(_statusText(inv),
                                                bg: _statusColor(inv)),
                                          ],
                                        ),
                                        SizedBox(height: 6.h),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _chip(
                                                'الإصدار: ${_fmtDateDynamic(inv.issueDate)}',
                                                bg: const Color(0xFF1F2937)),
                                            SizedBox(height: 6.h),
                                            _chip(
                                                'القيمة: ${_fmtMoneyTrunc(inv.amount)} ريال',
                                                bg: const Color(0xFF1F2937)),
                                            if (!inv.isPaid &&
                                                !inv.isCanceled) ...[
                                              SizedBox(height: 6.h),
                                              _chip(
                                                  'المتبقي: ${_fmtMoneyTrunc(remaining)} ريال',
                                                  bg: const Color(0xFF1F2937)),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_left_rounded,
                                      color: Colors.white70),
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
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.receipt_long_rounded),
          label: Text('إضافة سند',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          onPressed: _openAddManualInvoice,
        ),
      ),
    );
  }
}

/// ===============================================================================
/// تفاصيل السند
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
  final List<String> _attachments = [];
  bool _uploadingAttachments = false;
  String _ejarNoFromLocal = '';
  final Map<String, Future<String>> _remoteThumbUrls = {};
  static const MethodChannel _downloadsChannel =
      MethodChannel('darvoo/downloads');

  Future<MaintenanceRequest?> _loadMaintenanceRequestForInvoice(
      Invoice invoice) async {
    final invoiceId = (invoice.id).trim();
    final serialNo = (invoice.serialNo ?? '').trim();
    final requestId = (invoice.maintenanceRequestId ?? '').trim();

    if (invoiceId.isEmpty && serialNo.isEmpty) return null;

    final boxId = HiveService.maintenanceBoxName();
    if (!Hive.isBoxOpen(boxId)) {
      await Hive.openBox<MaintenanceRequest>(boxId);
    }
    final box = Hive.box<MaintenanceRequest>(boxId);
    if (requestId.isNotEmpty) {
      final exact = box.get(requestId);
      if (exact != null) return exact;
    }
    return firstWhereOrNull(box.values, (m) {
      final storedId = (m.invoiceId ?? '').trim();
      if (storedId.isEmpty) return false;
      if (storedId == invoiceId) return true;
      if (serialNo.isNotEmpty && storedId == serialNo) return true;
      return false;
    });
  }

  @override
  void initState() {
    super.initState();
    final latest = _invoices.get(widget.invoice.id);
    final seed = latest ?? widget.invoice;
    _attachments
      ..clear()
      ..addAll(seed.attachmentPaths);
    (() async {
      final v = await _readEjarNoLocalAsync(widget.invoice.contractId);
      if (!mounted) return;
      setState(() => _ejarNoFromLocal = v);
    })();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureLinkedContractSnapshotsBackfilled();
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
            context, MaterialPageRoute(builder: (_) => const TenantsScreen()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const contracts_ui.ContractsScreen()));
        break;
    }
  }

  Box<Invoice> get _invoices => Hive.box<Invoice>(invoicesBoxName());
  Box<Tenant> get _tenants => Hive.box<Tenant>(tenantsBoxName());
  Box<Property> get _properties => Hive.box<Property>(propsBoxName());
  Box<Contract> get _contracts => Hive.box<Contract>(contractsBoxName());

  Map<String, dynamic>? _resolvedContractTenantSnapshot(
      Contract? contract, Tenant? tenant) {
    return _invoiceSnapshotMapOrNull(contract?.tenantSnapshot) ??
        (tenant == null ? null : _buildInvoiceTenantSnapshot(tenant));
  }

  Map<String, dynamic>? _resolvedContractPropertySnapshot(
      Contract? contract, Property? property) {
    return _invoiceSnapshotMapOrNull(contract?.propertySnapshot) ??
        (property == null ? null : _buildInvoicePropertySnapshot(property));
  }

  Map<String, dynamic>? _resolvedContractBuildingSnapshot(
      Contract? contract, Property? property, Property? building) {
    return _invoiceSnapshotMapOrNull(contract?.buildingSnapshot) ??
        (building == null ? null : _buildInvoicePropertySnapshot(building));
  }

  Future<void> _ensureLinkedContractSnapshotsBackfilled() async {
    final invoice = widget.invoice;
    if (invoice.contractId.trim().isEmpty) return;
    final contract =
        firstWhereOrNull(_contracts.values, (x) => x.id == invoice.contractId);
    if (contract == null || !_invoiceContractIsInactive(contract)) return;

    final tenant =
        firstWhereOrNull(_tenants.values, (x) => x.id == contract.tenantId);
    final property =
        firstWhereOrNull(_properties.values, (x) => x.id == contract.propertyId);
    final building = property?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (x) => x.id == property!.parentBuildingId);

    var changed = false;
    if (tenant != null) {
      final current = _invoiceSnapshotMapOrNull(contract.tenantSnapshot);
      final next = _buildInvoiceTenantSnapshot(tenant);
      if (current == null) {
        contract.tenantSnapshot = next;
        changed = true;
      } else {
        final merged = Map<String, dynamic>.from(current);
        var mergedChanged = false;
        next.forEach((key, value) {
          if (!_invoiceSnapshotHasValue(merged[key]) &&
              _invoiceSnapshotHasValue(value)) {
            merged[key] = _cloneInvoiceSnapshotValue(value);
            mergedChanged = true;
          }
        });
        if (mergedChanged) {
          contract.tenantSnapshot = merged;
          changed = true;
        }
      }
    }
    if (property != null) {
      final current = _invoiceSnapshotMapOrNull(contract.propertySnapshot);
      final next = _buildInvoicePropertySnapshot(property);
      if (current == null) {
        contract.propertySnapshot = next;
        changed = true;
      } else {
        final merged = Map<String, dynamic>.from(current);
        var mergedChanged = false;
        next.forEach((key, value) {
          if (!_invoiceSnapshotHasValue(merged[key]) &&
              _invoiceSnapshotHasValue(value)) {
            merged[key] = _cloneInvoiceSnapshotValue(value);
            mergedChanged = true;
          }
        });
        if (mergedChanged) {
          contract.propertySnapshot = merged;
          changed = true;
        }
      }
    }
    if (building != null) {
      final current = _invoiceSnapshotMapOrNull(contract.buildingSnapshot);
      final next = _buildInvoicePropertySnapshot(building);
      if (current == null) {
        contract.buildingSnapshot = next;
        changed = true;
      } else {
        final merged = Map<String, dynamic>.from(current);
        var mergedChanged = false;
        next.forEach((key, value) {
          if (!_invoiceSnapshotHasValue(merged[key]) &&
              _invoiceSnapshotHasValue(value)) {
            merged[key] = _cloneInvoiceSnapshotValue(value);
            mergedChanged = true;
          }
        });
        if (mergedChanged) {
          contract.buildingSnapshot = merged;
          changed = true;
        }
      }
    }

    if (!changed || !contract.isInBox) return;
    contract.updatedAt = KsaTime.now();
    await contract.save();
    if (mounted) setState(() {});
  }

  Future<void> _openInvoiceTenant(
    BuildContext context,
    Invoice invoice,
    Contract? contract,
    Tenant? tenant,
    Map<String, dynamic>? snapshot,
  ) async {
    if (contract != null && _invoiceContractIsInactive(contract)) {
      final resolved = snapshot ?? _resolvedContractTenantSnapshot(contract, tenant);
      if (resolved == null || resolved.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لا تتوفر نسخة محفوظة من بيانات المستأجر لهذا السند.',
                    style: GoogleFonts.cairo())),
          );
        }
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _InvoiceTenantSnapshotScreen(
            snapshot: resolved,
            onAttachmentTap: _showAttachmentActions,
            onOpenOriginal: () => _openOriginalTenantFromSnapshot(context, resolved),
          ),
        ),
      );
      return;
    }

    final liveTenant = tenant ??
        firstWhereOrNull(_tenants.values, (x) => x.id == invoice.tenantId);
    if (liveTenant != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TenantDetailsScreen(tenant: liveTenant),
        ),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا تتوفر بيانات المستأجر لهذا السند.',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
    }
  }

  Future<void> _openOriginalTenantFromSnapshot(
    BuildContext context,
    Map<String, dynamic> snapshot,
  ) async {
    final tenantId = (_invoiceSnapshotString(snapshot, 'id') ?? '').trim();
    final tenant = tenantId.isEmpty
        ? null
        : firstWhereOrNull(_tenants.values, (x) => x.id == tenantId);
    if (tenant == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح المستأجر الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TenantDetailsScreen(tenant: tenant),
      ),
    );
  }

  Future<void> _openOriginalPropertyFromSnapshot(
    BuildContext context,
    Map<String, dynamic>? snapshot, {
    required bool isBuilding,
  }) async {
    final propertyId = (_invoiceSnapshotString(snapshot, 'id') ?? '').trim();
    final property = propertyId.isEmpty
        ? null
        : firstWhereOrNull(_properties.values, (x) => x.id == propertyId);
    if (property == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isBuilding
                  ? 'تعذر فتح العمارة الأصلية لأنها لم تعد موجودة في البيانات الحالية.'
                  : 'تعذر فتح العقار الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
              style: GoogleFonts.cairo(),
            ),
          ),
        );
      }
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(item: property),
      ),
    );
  }

  Future<void> _openInvoiceProperty(
    BuildContext context,
    Invoice invoice,
    Contract? contract,
    Property? property,
    Map<String, dynamic>? propertySnapshot,
    Map<String, dynamic>? buildingSnapshot,
    String? tenantName,
  ) async {
    if (contract != null && _invoiceContractIsInactive(contract)) {
      final resolvedProperty =
          propertySnapshot ?? _resolvedContractPropertySnapshot(contract, property);
      if (resolvedProperty == null || resolvedProperty.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لا تتوفر نسخة محفوظة من بيانات العقار لهذا السند.',
                    style: GoogleFonts.cairo())),
          );
        }
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _InvoicePropertySnapshotScreen(
            propertySnapshot: resolvedProperty,
            buildingSnapshot: buildingSnapshot,
            tenantName: tenantName,
            onAttachmentTap: _showAttachmentActions,
            onOpenOriginalTenant: () {
              final tenant = firstWhereOrNull(
                _tenants.values,
                (x) => x.id == invoice.tenantId,
              );
              final resolvedTenant =
                  _resolvedContractTenantSnapshot(contract, tenant);
              if (resolvedTenant == null || resolvedTenant.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تعذر فتح المستأجر الأصلي لأنه لم يعد موجودًا في البيانات الحالية.',
                        style: GoogleFonts.cairo(),
                      ),
                    ),
                  );
                }
                return Future.value();
              }
              return _openOriginalTenantFromSnapshot(context, resolvedTenant);
            },
            onOpenOriginalProperty: () => _openOriginalPropertyFromSnapshot(
              context,
              resolvedProperty,
              isBuilding: false,
            ),
            onOpenOriginalBuilding: buildingSnapshot == null ||
                    buildingSnapshot.isEmpty
                ? null
                : () => _openOriginalPropertyFromSnapshot(
                      context,
                      buildingSnapshot,
                      isBuilding: true,
                    ),
          ),
        ),
      );
      return;
    }

    final liveProperty = property ??
        firstWhereOrNull(_properties.values, (x) => x.id == invoice.propertyId);
    if (liveProperty != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PropertyDetailsScreen(item: liveProperty),
        ),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا تتوفر بيانات العقار لهذا السند.',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
    }
  }

  Future<void> _exportInvoicePdf(Invoice invoice) async {
    final tenant =
        firstWhereOrNull(_tenants.values, (x) => x.id == invoice.tenantId);
    final property =
        firstWhereOrNull(_properties.values, (x) => x.id == invoice.propertyId);
    final contract =
        firstWhereOrNull(_contracts.values, (x) => x.id == invoice.contractId);
    final ejarNo = (contract?.ejarContractNo ?? '').trim().isNotEmpty
        ? (contract!.ejarContractNo ?? '').trim()
        : await _readEjarNoLocalAsync(invoice.contractId);
    final building = property?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (x) => x.id == property!.parentBuildingId);
    final propertySnapshot = _resolvedContractPropertySnapshot(contract, property);
    final buildingSnapshot =
        _resolvedContractBuildingSnapshot(contract, property, building);
    final propertyRef = _invoicePropertyReference(
      property: property,
      building: building,
      propertySnapshot: propertySnapshot,
      buildingSnapshot: buildingSnapshot,
      fallbackName: property?.name,
    );
    final statementText = _invoiceDisplayStatementText(
      invoice: invoice,
      ejarNo: ejarNo,
      propertyRef: propertyRef,
    );
    MaintenanceRequest? maintenanceRequest;
    final invoiceId = (invoice.id).trim();
    final serialNo = (invoice.serialNo ?? '').trim();
    final requestId = (invoice.maintenanceRequestId ?? '').trim();
    if (invoiceId.isNotEmpty || serialNo.isNotEmpty) {
      final boxId = HiveService.maintenanceBoxName();
      if (!Hive.isBoxOpen(boxId)) {
        await Hive.openBox<MaintenanceRequest>(boxId);
      }
      final box = Hive.box<MaintenanceRequest>(boxId);
      if (requestId.isNotEmpty) {
        maintenanceRequest = box.get(requestId);
      }
      maintenanceRequest ??= firstWhereOrNull(box.values, (m) {
        final storedId = (m.invoiceId ?? '').trim();
        if (storedId.isEmpty) return false;
        if (storedId == invoiceId) return true;
        if (serialNo.isNotEmpty && storedId == serialNo) return true;
        return false;
      });
    }
    final hasMaintenanceLink =
        (invoice.maintenanceRequestId ?? '').trim().isNotEmpty;
    MaintenanceReceiptDetails? maintenanceDetails;
    if (maintenanceRequest != null) {
      maintenanceDetails =
          MaintenanceReceiptDetails.fromRequest(maintenanceRequest);
    } else {
      final snapshot = invoice.maintenanceSnapshot;
      if (snapshot != null && snapshot.isNotEmpty) {
        try {
          maintenanceDetails = MaintenanceReceiptDetails.fromMap(snapshot);
        } catch (_) {
          maintenanceDetails = null;
        }
      }
      if (maintenanceDetails == null &&
          (hasMaintenanceLink || _isMaintenanceAny(invoice))) {
        maintenanceDetails = _maintenanceDetailsFromInvoiceFallback(invoice);
      }
    }
    if (maintenanceDetails != null) {
      await PdfExportService.shareMaintenanceDetailsPdf(
        context: context,
        details: maintenanceDetails,
        property: property,
        relatedInvoices: [invoice],
      );
      return;
    }
    await PdfExportService.shareInvoiceDetailsPdf(
      context: context,
      invoice: invoice,
      tenant: tenant,
      property: property,
      contract: contract,
      ejarContractNo: ejarNo,
      rentOnlyAmount: _invoiceRentOnlyAmount(invoice),
      waterAmount: _invoiceWaterAmount(invoice),
      statementText: statementText,
    );
  }

  bool _contractEndedBy(Invoice inv) {
    final c =
        firstWhereOrNull(_contracts.values, (x) => x.id == inv.contractId);
    if (c == null) return false; // غير مربوط بعقد

    // ✅ منتهي يدويًا أو بالتاريخ
    if (c.isTerminated == true) return true;

    final today = KsaTime.today();
    return !today.isBefore(c.endDate); // اليوم >= نهاية العقد
  }

  Future<void> _showBlockDialog(String msg) async {
    await _showInvoiceArchiveNoticeDialog(context, message: msg);
  }

  /// يُسمح بالأرشفة إذا كانت السند غير مدفوعة.
  /// إن كانت "مدفوعة": تُسمح فقط إذا كانت مربوطة بعقد منتهي.
  Future<bool> _ensureCanArchive(Invoice inv) async {
    // ✅ السماح دائمًا لسندات الخدمات
    if (_isMaintenanceAny(inv)) return true;

    if (!inv.isPaid) return true;
    if ((inv.contractId).isEmpty) {
      await _showBlockDialog(
          'لا يمكن أرشفة السند المدفوع لأنها غير مرتبطة بعقد.');
      return false;
    }
    if (!_contractEndedBy(inv)) {
      await _showBlockDialog(
          'لا يمكن أرشفة السند المدفوع إلا إذا كان العقد منتهي.');
      return false;
    }
    return true;
  }

  Widget _maintenanceLinkWrapper(Invoice inv, Widget child) {
    if (!_isMaintenanceAny(inv) ||
        inv.maintenanceRequestId == null ||
        inv.maintenanceRequestId!.isEmpty) {
      return child;
    }
    return InkWell(
      onTap: () async {
        final boxId = HiveService.maintenanceBoxName();
        if (!Hive.isBoxOpen(boxId))
          await Hive.openBox<MaintenanceRequest>(boxId);
        final box = Hive.box<MaintenanceRequest>(boxId);
        final req = box.get(inv.maintenanceRequestId);
        if (req != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MaintenanceDetailsScreen(item: req),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تعذر العثور على طلب الخدمات المرتبط.')));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          Padding(
            padding: EdgeInsets.only(right: 120.w, bottom: 8.h),
            child: Text(
              '(انقر لفتح طلب الخدمات)',
              style: GoogleFonts.cairo(
                color: const Color(0xFF0EA5E9),
                fontSize: 10.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowInfoWidget(String label, Widget child) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  String _invoicePeriodLabel(Invoice inv, Contract? c) {
    final due = KsaTime.dateOnly(inv.dueDate);
    if (c == null) {
      return _fmtDateDynamic(due);
    }
    if (c.term == ContractTerm.daily) {
      return _dailyInvoicePeriodLabel(c);
    }
    final months = _monthsPerCycleForInvoiceContract(c);
    final duration = _cycleDurationLabelForInvoiceContract(c);
    final endDate = KsaTime.dateOnly(_addMonthsSafe(due, months));
    return '$duration: من ${_fmtDateDynamic(due)} إلى ${_fmtDateDynamic(endDate)}';
  }

  Widget _infoPill(String text, {Color bg = const Color(0xFF334155)}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
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
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(t,
            style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14.sp)),
      );

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
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              has ? value! : '—',
              style:
                  GoogleFonts.cairo(color: has ? Colors.white : Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoices.get(widget.invoice.id) ?? widget.invoice;
    final isManual = _isManualInvoiceAny(invoice);
    final manualPartyId = isManual ? _manualInvoicePartyId(invoice.note) : null;
    final manualPropertyId =
        isManual ? _manualInvoicePropertyId(invoice.note) : null;

    final t = firstWhereOrNull(
      _tenants.values,
      (x) => x.id == (invoice.tenantId.trim().isNotEmpty ? invoice.tenantId : manualPartyId),
    );
    final p = firstWhereOrNull(
      _properties.values,
      (x) => x.id == (invoice.propertyId.trim().isNotEmpty ? invoice.propertyId : manualPropertyId),
    );
    final linkedContract =
        firstWhereOrNull(_contracts.values, (x) => x.id == invoice.contractId);
    final building = p?.parentBuildingId == null
        ? null
        : firstWhereOrNull(
            _properties.values, (x) => x.id == p!.parentBuildingId);
    final tenantSnapshot = _resolvedContractTenantSnapshot(linkedContract, t);
    final propertySnapshot =
        _resolvedContractPropertySnapshot(linkedContract, p);
    final buildingSnapshot =
        _resolvedContractBuildingSnapshot(linkedContract, p, building);
    final contractInactive =
        linkedContract != null && _invoiceContractIsInactive(linkedContract);
    final ejarNoForView = (() {
      final direct = (linkedContract?.ejarContractNo ?? '').trim();
      if (direct.isNotEmpty) return direct;
      if (_ejarNoFromLocal.trim().isNotEmpty) return _ejarNoFromLocal.trim();
      return _readEjarNoLocalIfOpen(invoice.contractId);
    })();
    final sharedServiceVoucherLabel =
        _invoiceSharedServiceVoucherDisplayTypeAny(invoice);
    final isSharedServiceOfficeVoucher = sharedServiceVoucherLabel != null &&
        invoice.amount < 0 &&
        invoice.tenantId.trim().isEmpty;

    final bool _noTenantMaint =
        _isMaintenanceAny(invoice) && ((invoice.tenantId).isEmpty || t == null);
    final manualPartyName = _manualInvoicePartyName(invoice.note);
    final manualPropertyName = _manualInvoicePropertyName(invoice.note);
    final tenantDisplayName = _noTenantMaint
        ? (isSharedServiceOfficeVoucher ? 'المكتب' : 'بدون مستأجر')
        : (isManual
            ? ((t?.fullName ??
                        manualPartyName ??
                        _invoiceSnapshotString(tenantSnapshot, 'fullName'))
                    ?.trim()
                    .isNotEmpty ==
                true
                ? (t?.fullName ??
                    manualPartyName ??
                    _invoiceSnapshotString(tenantSnapshot, 'fullName'))!
                : 'بدون طرف محدد')
            : (contractInactive
                ? (_invoiceSnapshotString(tenantSnapshot, 'fullName') ??
                    t?.fullName ??
                    '—')
                : (t?.fullName ??
                    _invoiceSnapshotString(tenantSnapshot, 'fullName') ??
                    '—')));
    final propertyDisplayName = isManual
        ? (() {
            final ref = _invoicePropertyReference(
              property: p,
              building: building,
              fallbackName: manualPropertyName,
            );
            return ref.isNotEmpty ? ref : 'بدون عقار محدد';
          })()
        : (() {
            final ref = _invoicePropertyReference(
              property: contractInactive ? null : p,
              building: contractInactive ? null : building,
              propertySnapshot: propertySnapshot,
              buildingSnapshot: buildingSnapshot,
              fallbackName: p?.name,
            );
            return ref.isNotEmpty ? ref : '—';
          })();
    final canOpenTenant = !_noTenantMaint && t != null;
    final canOpenProperty =
        p != null || (contractInactive && propertySnapshot != null);
    final showManualPropertyHeader =
        !isManual || (manualPropertyName ?? '').trim().isNotEmpty || p != null;
    final waterAmount = _invoiceWaterAmount(invoice);
    final rentOnlyAmount = _invoiceRentOnlyAmount(invoice);
    final statementText = _invoiceDisplayStatementText(
      invoice: invoice,
      ejarNo: ejarNoForView,
      propertyRef: propertyDisplayName,
    );
    final isDailyContractReceipt =
        !isManual && linkedContract?.term == ContractTerm.daily;
    final dailyRate = _dailyInvoiceRate(linkedContract);
    final manualPaidDisplay =
        invoice.paidAmount > 0 ? invoice.paidAmount : invoice.amount.abs();
    final manualAmountLabel = invoice.amount < 0 ? 'المبلغ المدفوع' : 'المبلغ المستلم';
    final paidAmountLabel = isManual
        ? manualAmountLabel
        : (isDailyContractReceipt ? 'إجمالي المدفوع' : 'المبلغ المدفوع');

    return WillPopScope(
      onWillPop: () async => !_uploadingAttachments,
      child: AbsorbPointer(
        absorbing: _uploadingAttachments,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              leading: darvooLeading(context, iconColor: Colors.white),
              title: Text('تفاصيل السند',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              actions: [
                IconButton(
                  tooltip: 'Export PDF',
                  onPressed: () => _exportInvoicePdf(invoice),
                  icon: const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.white),
                ),
                IconButton(
                  tooltip:
                      invoice.isArchived ? 'السند مؤرشفة' : 'السند غير مؤرشفة',
                  onPressed: () async {
                    await _showInvoiceArchiveNoticeDialog(
                      context,
                      message: invoice.isArchived
                          ? 'لا يمكن إلغاء أرشفة السند، تتم أرشفته تلقائيًا بعد إلغاء السند.'
                          : 'لا يمكن أرشفة السند يدويًا، تتم أرشفته تلقائيًا بعد إلغاء السند.',
                    );
                  },
                  icon: Icon(
                    invoice.isArchived
                        ? Icons.inventory_2_rounded
                        : Icons.archive_rounded,
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
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF0F766E),
                          Color(0xFF14B8A6)
                        ]),
                  ),
                ),
                Positioned(
                    top: -120,
                    right: -80,
                    child: _softCircle(220.r, const Color(0x33FFFFFF))),
                Positioned(
                    bottom: -140,
                    left: -100,
                    child: _softCircle(260.r, const Color(0x22FFFFFF))),
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _invoiceTypeLabel(invoice),
                      ),
                      SizedBox(height: 10.h),

                      // ===== البطاقة العلوية (الرأس الاحترافي) =====
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // أيقونة السند بتدرج لوني
                                    Container(
                                      width: 56.w,
                                      height: 56.w,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(12.r),
                                        gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF0F766E),
                                              Color(0xFF14B8A6)
                                            ],
                                            begin: Alignment.topRight,
                                            end: Alignment.bottomLeft),
                                      ),
                                      child: const Icon(
                                          Icons.receipt_long_rounded,
                                          color: Colors.white),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap: () async {
                                              if (!canOpenTenant) return;
                                              await _openInvoiceTenant(
                                                context,
                                                invoice,
                                                linkedContract,
                                                t,
                                                tenantSnapshot,
                                              );
                                            },
                                            child: Text(
                                              tenantDisplayName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.cairo(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16.sp,
                                                decoration: canOpenTenant
                                                    ? TextDecoration.underline
                                                    : null,
                                              ),
                                            ),
                                          ),
                                          if (showManualPropertyHeader) ...[
                                            SizedBox(height: 4.h),
                                            InkWell(
                                              onTap: () async {
                                                if (!canOpenProperty) return;
                                                await _openInvoiceProperty(
                                                  context,
                                                  invoice,
                                                  linkedContract,
                                                  p,
                                                  propertySnapshot,
                                                  buildingSnapshot,
                                                  tenantDisplayName,
                                                );
                                              },
                                              child: Text(
                                                propertyDisplayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.cairo(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13.5.sp,
                                                    decoration: canOpenProperty
                                                        ? TextDecoration.underline
                                                        : null),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // حالة السند فقط (أعلى اليسار)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: _infoPill(_statusText(invoice),
                                  bg: _statusColor(invoice)),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 10.h),

                      // ===== البطاقة السفلية (تفاصيل السند) =====
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('تفاصيل السند'),
                            _rowInfo('رقم السند', invoice.serialNo ?? '—'),
                            if (_isMaintenanceAny(invoice))
                              _rowInfo(
                                'تاريخ السند',
                                _fmtDateDynamic(invoice.issueDate),
                              ),
                            if (ejarNoForView.isNotEmpty)
                              _rowInfo('رقم عقد الإيجار', ejarNoForView),
                            if (!_isMaintenanceAny(invoice))
                              if (isDailyContractReceipt && linkedContract != null)
                                _rowInfoWidget(
                                  'تاريخ الاستحقاق',
                                  Padding(
                                    padding: EdgeInsets.only(top: 2.h),
                                    child: _invoiceDailyPeriodDetailsWidget(
                                      linkedContract,
                                      baseStyle: GoogleFonts.cairo(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                _rowInfo(
                                  isManual ? 'تاريخ السند' : 'تاريخ الاستحقاق',
                                  _invoicePeriodLabel(invoice, linkedContract),
                                ),
                            if (isDailyContractReceipt && dailyRate != null)
                              _rowInfo('قيمة اليوم',
                                  '${_fmtMoneyTrunc(dailyRate)} ريال'),
                            _rowInfo(
                              paidAmountLabel,
                              '${_fmtMoneyTrunc(isManual ? manualPaidDisplay : invoice.paidAmount)} ريال',
                            ),
                            if (_shouldShowInvoicePaymentMethod(invoice))
                              _rowInfo('طريقة الدفع', invoice.paymentMethod),
                            if (!isManual && !invoice.isPaid && !invoice.isCanceled)
                              _rowInfo('المبلغ المتبقي',
                                  '${_fmtMoneyTrunc(invoice.remaining)} ريال'),
                            if (waterAmount > 0)
                              _rowInfo('قسط المياه',
                                  '${_fmtMoneyTrunc(waterAmount)} ريال'),
                            if (statementText.isNotEmpty)
                              _maintenanceLinkWrapper(
                                invoice,
                                _rowInfo('البيان', statementText),
                              ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: EntityAuditInfoButton(
                          collectionName: 'invoices',
                          entityId: invoice.id,
                        ),
                      ),

                      SizedBox(height: 10.h),
                      _DarkCard(
                        padding: EdgeInsets.all(14.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'المرفقات (${_attachments.length}/3)',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0EA5E9),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _uploadingAttachments
                                      ? null
                                      : _pickAttachments,
                                  icon: const Icon(Icons.attach_file_rounded),
                                  label: Text(
                                    'إرفاق',
                                    style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            if (_attachments.isNotEmpty) ...[
                              SizedBox(height: 10.h),
                              Wrap(
                                spacing: 8.w,
                                runSpacing: 8.h,
                                children: _attachments.map((path) {
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      InkWell(
                                        onTap: () =>
                                            _showAttachmentActions(path),
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                          child: Container(
                                            width: 88.w,
                                            height: 88.w,
                                            color:
                                                Colors.white.withOpacity(0.08),
                                            child: _buildAttachmentThumb(path),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _removeAttachment(path),
                                          child: Container(
                                            width: 28.w,
                                            height: 28.w,
                                            alignment: Alignment.center,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFB91C1C),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16.sp,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
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
                            if (_isDraftVoucher(invoice))
                              _miniAction(
                                icon: Icons.payments_rounded,
                                label: invoice.amount < 0
                                    ? 'تسجيل دفع'
                                    : 'تسجيل سداد',
                                bg: const Color(0xFF0EA5E9),
                                onTap: () async {
                                  if (await OfficeClientGuard
                                      .blockIfOfficeClient(context)) return;
                                  _addPayment(context, invoice);
                                },
                              ),
                            if (_isDraftVoucher(invoice))
                              _miniAction(
                                icon: Icons.task_alt_rounded,
                                label: 'اعتماد',
                                bg: const Color(0xFF166534),
                                onTap: () => _postDraftVoucher(invoice),
                              ),
                            if (_isDraftVoucher(invoice))
                              _miniAction(
                                icon: Icons.delete_outline_rounded,
                                label: 'حذف مسودة',
                                bg: const Color(0xFF7F1D1D),
                                onTap: () => _deleteDraftVoucher(invoice),
                              ),
                            if (_isPostedVoucher(invoice))
                              _miniAction(
                                icon: Icons.cancel_rounded,
                                label: 'إلغاء',
                                bg: const Color(0xFF9A3412),
                                onTap: () => _cancelPostedVoucher(invoice),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_uploadingAttachments)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.30),
                      alignment: Alignment.center,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 18.w, vertical: 14.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.90),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2.4),
                            ),
                            SizedBox(width: 10.w),
                            Text(
                              'جاري المعالجة...',
                              style: GoogleFonts.cairo(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w800,
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
              currentIndex: 0,
              onTap: _handleBottomTap,
            ),
          ),
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

  bool _isReversedVoucher(Invoice invoice) {
    final note = (invoice.note ?? '').toLowerCase();
    return note.contains('[reversal]') ||
        note.contains('[reversed]') ||
        note.contains('معكوس');
  }

  bool _isDraftVoucher(Invoice invoice) {
    if (invoice.isCanceled || _isReversedVoucher(invoice)) return false;
    final due = invoice.amount.abs();
    return invoice.paidAmount + 0.000001 < due;
  }

  bool _isPostedVoucher(Invoice invoice) {
    if (invoice.isCanceled || _isReversedVoucher(invoice)) return false;
    final due = invoice.amount.abs();
    return invoice.paidAmount + 0.000001 >= due;
  }

  String _appendNoteMarker(String? note, String marker) {
    final base = (note ?? '').trim();
    if (base.toLowerCase().contains(marker.toLowerCase())) return base;
    if (base.isEmpty) return marker;
    return '$base\n$marker';
  }

  Future<bool> _confirmVoucherAction({
    required String title,
    required String message,
    String confirmLabel = 'حفظ',
  }) async {
    return await CustomConfirmDialog.show(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
  }

  bool _shouldSyncOfficeCommissionForInvoice(Invoice invoice) {
    if (invoice.contractId.trim().isEmpty) return false;
    if (_isOfficeCommissionInvoiceAny(invoice) ||
        _isOwnerPayoutInvoiceAny(invoice) ||
        _isOwnerAdjustmentInvoiceAny(invoice)) {
      return false;
    }
    final note = _invoiceRawNoteAny(invoice);
    final lower = note.toLowerCase();
    if (_invoiceNoteHasServiceOrigin(note)) return false;
    if (_invoiceMaintenanceRequestIdAny(invoice).isNotEmpty) return false;
    return !lower.contains('[manual]') && !lower.contains('[office_withdrawal]');
  }

  Future<void> _syncOfficeCommissionForInvoice(Invoice invoice) async {
    if (!_shouldSyncOfficeCommissionForInvoice(invoice)) return;
    try {
      await ComprehensiveReportsService.syncOfficeCommissionVouchers(
        contractVoucherId: invoice.id,
      );
    } catch (e, st) {
      debugPrint('Failed to sync office commission voucher for ${invoice.id}: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _postDraftVoucher(Invoice invoice) async {
    if (!_isDraftVoucher(invoice)) {
      _showTopNotice('لا يمكن اعتماد هذا السند', isError: true);
      return;
    }
    final ok = await _confirmVoucherAction(
      title: 'اعتماد السند',
      message: 'سيتم ترحيل السند واعتماده ماليًا ولا يُسمح بحذفه بعد ذلك.',
      confirmLabel: 'اعتماد',
    );
    if (!ok) return;

    invoice.paidAmount = invoice.amount.abs();
    if (invoice.paymentMethod.trim().isEmpty) {
      invoice.paymentMethod = 'تحويل بنكي';
    }
    invoice.note = _appendNoteMarker(invoice.note, '[POSTED] تم اعتماد السند');
    invoice.updatedAt = KsaTime.now();
    await invoice.save();
    await _syncOfficeCommissionForInvoice(invoice);
    _showTopNotice('تم اعتماد السند');
  }

  Future<void> _cancelPostedVoucher(Invoice invoice) async {
    if (!_isPostedVoucher(invoice)) {
      _showTopNotice('الإلغاء متاح فقط للسند المعتمد', isError: true);
      return;
    }
    final ok = await _confirmVoucherAction(
      title: 'إلغاء السند',
      message: 'بعد الإلغاء سيتم استبعاد السند من الأثر المالي.',
      confirmLabel: 'إلغاء السند',
    );
    if (!ok) return;

    invoice.isCanceled = true;
    invoice.isArchived = true;
    invoice.note =
        _appendNoteMarker(invoice.note, '[CANCELLED] تم إلغاء السند');
    invoice.updatedAt = KsaTime.now();
    await invoice.save();
    await _syncOfficeCommissionForInvoice(invoice);
    final linkedRequest = await _loadMaintenanceRequestForInvoice(invoice);
    if (linkedRequest != null) {
      await markPeriodicServiceRequestSuppressedForCurrentCycle(linkedRequest);
    }
    if (mounted) setState(() {});
    _showTopNotice('تم إلغاء السند');
  }

  Future<void> _reversePostedVoucher(Invoice invoice) async {
    if (!_isPostedVoucher(invoice)) {
      _showTopNotice('العكس متاح فقط للسند المعتمد', isError: true);
      return;
    }
    final ok = await _confirmVoucherAction(
      title: 'عكس السند',
      message:
          'سيتم إنشاء سند عكسي تلقائيًا بنفس القيمة بعكس الإشارة للحفاظ على التتبع المالي.',
      confirmLabel: 'عكس',
    );
    if (!ok) return;

    final reversalId = KsaTime.now().microsecondsSinceEpoch.toString();
    final reversalSerial = _nextInvoiceSerialSync(_invoices);
    final now = KsaTime.now();
    final reversal = Invoice(
      id: reversalId,
      serialNo: reversalSerial,
      tenantId: invoice.tenantId,
      contractId: invoice.contractId,
      propertyId: invoice.propertyId,
      issueDate: now,
      dueDate: now,
      amount: -invoice.amount,
      paidAmount: invoice.amount.abs(),
      currency: invoice.currency,
      note:
          '[REVERSAL] original=${invoice.id} serial=${invoice.serialNo ?? invoice.id}',
      paymentMethod: invoice.paymentMethod,
      attachmentPaths: const <String>[],
      maintenanceRequestId: invoice.maintenanceRequestId,
      maintenanceSnapshot: invoice.maintenanceSnapshot,
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );
    await _invoices.put(reversal.id, reversal);

    invoice.note = _appendNoteMarker(
      invoice.note,
      '[REVERSAL] معكوس بواسطة ${reversal.serialNo ?? reversal.id}',
    );
    invoice.updatedAt = KsaTime.now();
    await invoice.save();
    await _syncOfficeCommissionForInvoice(invoice);
    _showTopNotice('تم إنشاء سند عكسي وربطه بالسند الأصلي');
  }

  Future<void> _deleteDraftVoucher(Invoice invoice) async {
    if (!_isDraftVoucher(invoice)) {
      _showTopNotice('الحذف مسموح فقط للمسودة', isError: true);
      return;
    }
    final ok = await _confirmVoucherAction(
      title: 'حذف مسودة',
      message: 'سيتم حذف السند نهائيًا لأنه مسودة وغير مرحّل.',
      confirmLabel: 'حذف',
    );
    if (!ok) return;

    await _invoices.delete(invoice.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    _showTopNotice('تم حذف المسودة');
  }

  Future<void> _addPayment(BuildContext context, Invoice invoice) async {
    final controller = TextEditingController();
    final methodCtl = TextEditingController(text: invoice.paymentMethod);
    final actionLabel = invoice.amount < 0 ? 'تسجيل دفع' : 'تسجيل سداد';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16.w,
            right: 16.w,
            top: 16.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel,
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              SizedBox(height: 10.h),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))
                ],
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  labelStyle: GoogleFonts.cairo(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: methodCtl,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'طريقة الدفع',
                  labelStyle: GoogleFonts.cairo(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.15))),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text('حفظ',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.white)),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('أدخل مبلغًا صحيحًا', style: GoogleFonts.cairo())));
        }
        return;
      }
      invoice.paidAmount += v;
      final m = methodCtl.text.trim();
      if (m.isNotEmpty) invoice.paymentMethod = m;
      invoice.updatedAt = KsaTime.now();
      await invoice.save();
      await _syncOfficeCommissionForInvoice(invoice);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                invoice.amount < 0 ? 'تم تسجيل الدفع' : 'تم تسجيل السداد',
                style: GoogleFonts.cairo())));
      }
    }
  }

  bool _isImageAttachment(String path) {
    final p = path.toLowerCase().split('?').first;
    return p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.png') ||
        p.endsWith('.webp');
  }

  bool _isRemoteAttachment(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<String> _resolveRemoteUrl(String path) async {
    if (path.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }
    return path;
  }

  Future<String> _resolveRemoteImageUrl(String path) {
    return _remoteThumbUrls.putIfAbsent(path, () => _resolveRemoteUrl(path));
  }

  Widget _buildAttachmentThumb(String path) {
    if (_isImageAttachment(path)) {
      if (_isRemoteAttachment(path)) {
        return FutureBuilder<String>(
          future: _resolveRemoteImageUrl(path),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              );
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white70,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
        ),
      );
    }
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Colors.white70,
    );
  }

  Future<void> _showAttachmentActions(String path) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.download_rounded, color: Colors.white),
                title: Text('تحميل',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadAttachment(path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: Text('مشاركة',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareAttachment(path);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<File?> _resolveAttachmentToLocalFile(String path) async {
    if (!_isRemoteAttachment(path)) {
      final f = File(path);
      if (f.existsSync()) return f;
      return null;
    }
    final url = await _resolveRemoteUrl(path);
    final tmpDir = await getTemporaryDirectory();
    final uri = Uri.tryParse(url);
    final name = (uri?.pathSegments.isNotEmpty == true)
        ? uri!.pathSegments.last
        : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
    final outFile = File('${tmpDir.path}${Platform.pathSeparator}$name');
    await _downloadToFile(url, outFile);
    return outFile;
  }

  Future<void> _downloadToFile(String url, File outFile) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(res);
      await outFile.writeAsBytes(bytes, flush: true);
    } finally {
      client.close();
    }
  }

  String _mimeFromPath(String path) {
    final p = path.toLowerCase().split('?').first;
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('http ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close();
    }
  }

  Future<Directory?> _targetDownloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (dir.existsSync()) return dir;
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  Future<bool> _ensureDownloadPermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      if (_isImageAttachment(path)) {
        final photos = await Permission.photos.request();
        if (photos.isGranted) return true;
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;
    } catch (_) {}
    return true; // نتابع مع MediaStore حتى لو رُفضت الصلاحية
  }

  Future<bool> _saveBytesToDownloads(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    try {
      final res = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      return res != null && res.isNotEmpty;
    } catch (e, s) {
      debugPrint('[attachments] download channel failed: $e');
      debugPrint('[attachments] download channel stack: $s');
      return false;
    }
  }

  Future<void> _downloadAttachment(String path) async {
    try {
      debugPrint('[attachments] download start: $path');
      final ok = await _ensureDownloadPermission(path);
      if (!ok) {
        debugPrint('[attachments] download permission denied');
        _showTopNotice('يلزم إذن التخزين لتحميل الملف', isError: true);
        return;
      }
      final String name;
      Uint8List bytes;
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final uri = Uri.tryParse(url);
        name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        bytes = await _downloadBytes(url);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] download local missing');
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        name = f.path.split(Platform.pathSeparator).last;
        bytes = await f.readAsBytes();
      }

      if (Platform.isAndroid) {
        final saved =
            await _saveBytesToDownloads(bytes, name, _mimeFromPath(name));
        if (!saved) {
          _showTopNotice('تعذر تحميل المرفق', isError: true);
          return;
        }
        _showTopNotice('تم التحميل');
        return;
      }

      final dir = await _targetDownloadsDir();
      if (dir == null) {
        debugPrint('[attachments] download target dir is null');
        _showTopNotice('تعذر تحديد مجلد التنزيل', isError: true);
        return;
      }
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await dest.writeAsBytes(bytes, flush: true);
      debugPrint('[attachments] download saved: ${dest.path}');
      _showTopNotice('تم التحميل');
    } catch (e, s) {
      debugPrint('[attachments] download failed: $e');
      debugPrint('[attachments] download stack: $s');
      _showTopNotice('تعذر تحميل المرفق', isError: true);
    }
  }

  Future<void> _shareAttachment(String path) async {
    try {
      debugPrint('[attachments] share start: $path');
      if (_isRemoteAttachment(path)) {
        final url = await _resolveRemoteUrl(path);
        final bytes = await _downloadBytes(url);
        final uri = Uri.tryParse(url);
        final name = (uri?.pathSegments.isNotEmpty == true)
            ? uri!.pathSegments.last
            : 'attachment_${KsaTime.now().microsecondsSinceEpoch}';
        await Share.shareXFiles([
          XFile.fromData(bytes, name: name, mimeType: _mimeFromPath(name)),
        ]);
      } else {
        final f = File(path);
        if (!f.existsSync()) {
          debugPrint('[attachments] share local missing');
          _showTopNotice('تعذر مشاركة المرفق', isError: true);
          return;
        }
        debugPrint('[attachments] share local path: ${f.path}');
        await Share.shareXFiles(
            [XFile(f.path, mimeType: _mimeFromPath(f.path))]);
      }
    } catch (e, s) {
      debugPrint('[attachments] share failed: $e');
      debugPrint('[attachments] share stack: $s');
      _showTopNotice('تعذر مشاركة المرفق', isError: true);
    }
  }

  void _showTopNotice(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 12;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFF7F1D1D) : const Color(0xFF0EA5E9),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  Future<void> _openAttachment(String path) async {
    try {
      final raw = path.trim();
      String launchable = raw;
      if (raw.startsWith('gs://')) {
        launchable =
            await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      Uri? uri;
      if (_isRemoteAttachment(launchable)) {
        uri = Uri.tryParse(launchable);
      } else {
        final f = File(launchable);
        if (!f.existsSync()) throw Exception('attachment missing');
        uri = Uri.file(f.path);
      }
      if (uri == null) throw Exception('bad uri');

      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر تحميل المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<void> _persistAttachments() async {
    final live = _invoices.get(widget.invoice.id);
    final target = live ?? widget.invoice;
    target.attachmentPaths = List<String>.from(_attachments);
    target.updatedAt = KsaTime.now();
    if (target.key == null) {
      await _invoices.put(target.id, target);
    } else {
      await target.save();
    }
    widget.invoice.attachmentPaths = List<String>.from(_attachments);
    widget.invoice.updatedAt = target.updatedAt;
  }

  Future<void> _deleteLocalAttachmentFile(String path) async {
    final raw = path.trim().toLowerCase();
    final isRemote = raw.startsWith('https://') ||
        raw.startsWith('http://') ||
        raw.startsWith('gs://');
    if (isRemote) return;
    try {
      final f = File(path);
      if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<void> _removeAttachment(String path) async {
    final ok = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف المرفق؟ لن يتم استرجاعه مجددًا.',
      confirmLabel: 'حذف',
      cancelLabel: 'إلغاء',
    );
    if (ok != true) return;
    final previousAttachments = List<String>.from(_attachments);
    setState(() => _attachments.remove(path));
    try {
      await _persistAttachments();
      await _deleteLocalAttachmentFile(path);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _attachments
          ..clear()
          ..addAll(previousAttachments);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف المرفق', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<String?> _uploadAttachmentToStorage(
    File localFile,
    String fileName,
  ) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('invoice_attachments')
          .child(fileName);
      await ref.putFile(localFile);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}invoice_attachments');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName =
          '${KsaTime.now().microsecondsSinceEpoch}_${safeName.isEmpty ? 'doc' : safeName}';
      final outFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (file.bytes != null) {
        await outFile.writeAsBytes(file.bytes!, flush: true);
        return outFile.path;
      }
      final src = file.path;
      if (src != null && src.isNotEmpty) {
        await File(src).copy(outFile.path);
        return outFile.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('لا يمكن رفع أكثر من 3', style: GoogleFonts.cairo())),
        );
      }
      return;
    }

    final remaining = 3 - _attachments.length;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final selectedFiles = picked.files.take(remaining).toList();
    if (picked.files.length > remaining && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('لا يمكن رفع أكثر من 3', style: GoogleFonts.cairo())),
      );
    }

    setState(() => _uploadingAttachments = true);
    try {
      int failed = 0;
      for (final file in selectedFiles) {
        final localPath = await _saveAttachmentLocally(file);
        if (localPath == null) {
          failed += 1;
          continue;
        }
        if (!_attachments.contains(localPath)) {
          _attachments.add(localPath);
          await _persistAttachments();
        }
      }
      if (failed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تعذر حفظ $failed مرفق', style: GoogleFonts.cairo())),
        );
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _uploadingAttachments = false);
    }
  }
}

/// ===============================================================================
/// سجل سندات عقد محدد
/// ===============================================================================
class InvoicesHistoryScreen extends StatefulWidget {
  final String contractId;
  const InvoicesHistoryScreen({super.key, required this.contractId});

  @override
  State<InvoicesHistoryScreen> createState() => _InvoicesHistoryScreenState();
}

class _InvoicesHistoryScreenState extends State<InvoicesHistoryScreen> {
  @override
  void initState() {
    super.initState();
    (() async {
      await contracts_ui.openServicesConfigBox();
      if (mounted) setState(() {});
    })();
  }

  @override
  Widget build(BuildContext context) {
    final contractId = widget.contractId;
    // حماية بسيطة لو فُتح مباشرة بدون تهيئة سابقة
    if (!Hive.isBoxOpen(invoicesBoxName())) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          drawer: Builder(
            builder: (ctx) {
              final media = MediaQuery.of(ctx);
              final double topInset = kToolbarHeight + media.padding.top;
              final double bottomInset =
                  media.padding.bottom; // لا يوجد BottomNav هنا
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
            title: Text('سجل سندات العقد',
                style: GoogleFonts.cairo(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final _invoices = Hive.box<Invoice>(invoicesBoxName());
    final _tenants = Hive.box<Tenant>(tenantsBoxName());
    final _properties = Hive.box<Property>(propsBoxName());
    final _contracts = Hive.box<Contract>(contractsBoxName());

    final c = firstWhereOrNull(_contracts.values, (e) => e.id == contractId);
    final t =
        firstWhereOrNull(_tenants.values, (e) => e.id == (c?.tenantId ?? ''));
    final p = firstWhereOrNull(
        _properties.values, (e) => e.id == (c?.propertyId ?? ''));
    List<Invoice> historyItems([Iterable<Invoice>? source]) =>
        (source ?? _invoices.values)
            .where(
              (i) =>
                  i.contractId == contractId &&
                  !_isOfficeCommissionInvoiceAny(i),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Builder(
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final double topInset = kToolbarHeight + media.padding.top;
            final double bottomInset =
                media.padding.bottom; // لا يوجد BottomNav هنا
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
          title: Text('سجل سندات العقد',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Export PDF',
              onPressed: () async {
                await PdfExportService.shareContractInvoicesPdf(
                  context: context,
                  contractId: contractId,
                  invoices: historyItems(),
                  contract: c,
                  tenant: t,
                  property: p,
                );
              },
              icon:
                  const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
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
                      Color(0xFF0F172A),
                      Color(0xFF0F766E),
                      Color(0xFF14B8A6)
                    ]),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            ValueListenableBuilder(
              valueListenable: _invoices.listenable(),
              builder: (context, Box<Invoice> box, _) {
                final items = historyItems(box.values);

                if (items.isEmpty) {
                  return Center(
                    child: Text('لا توجد سندات لهذا العقد',
                        style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700)),
                  );
                }

// المجاميع والعدادات (مرتبطة بالعقد إذا وُجد: نعرض الإجمالي بعد خصم المقدم إذا كان advanceMode = deductFromTotal)
                final double grossContract = ((c?.totalAmount ?? 0)).toDouble();
                final double advancePaid = ((c?.advancePaid ?? 0)).toDouble();
                final bool deductFromTotal = (c != null) &&
                    (c!.advanceMode == AdvanceMode.deductFromTotal);

                final double contractNet = deductFromTotal
                    ? (grossContract - advancePaid)
                    : grossContract;

// نحسب المدفوع/المتبقي من السندات غير الملغاة مع تشذيب لخانتين (لتطابق العرض)
                double _trunc2(num v) => (v * 100).truncate() / 100.0;
                final filteredItems =
                    items.where((i) => !i.isCanceled).toList();

// ✅ مُعرّف لسند المقدم (النص يأتي من العقود: "سداد مقدم عقد …")
                bool _isAdvanceInvoice(Invoice i) {
                  final n = (i.note ?? '').toString();
                  return n.contains('سداد مقدم عقد');
                }

// الإجمالي = قيمة العقد + إجمالي أقساط المياه المرتبطة
                double contractWaterTotal = 0.0;
                if (c != null) {
                  final cfgBoxName = scope.boxName('servicesConfig');
                  if (Hive.isBoxOpen(cfgBoxName)) {
                    final cfgBox = Hive.box<Map>(cfgBoxName);
                    final raw = cfgBox.get('${c.propertyId}::water');
                    if (raw is Map) {
                      final cfg = Map<String, dynamic>.from(raw);
                      if (contracts_ui.isWaterSharedFixedConfig(cfg) &&
                          (cfg['waterLinkedContractId'] ?? '').toString() ==
                              c.id) {
                        final rows = contracts_ui.waterInstallmentsFromConfig(cfg);
                        for (final row in rows) {
                          contractWaterTotal +=
                              ((row['amount'] as num?)?.toDouble() ?? 0.0);
                        }
                      }
                    }
                  }
                }
                final double totalAmount = contractNet + contractWaterTotal;

// ⚠️ استبعد سند المقدم من "المدفوع" وعدّادات الأقساط عند خصم المقدم من الإجمالي
                final filteredForPaid = deductFromTotal
                    ? filteredItems.where((i) => !_isAdvanceInvoice(i)).toList()
                    : filteredItems;

// المدفوع من السندات (لا نُدخل المقدم هنا)
                final double totalPaid =
                    filteredForPaid.fold<double>(0.0, (s, i) {
                  final paid = _trunc2(i.paidAmount);
                  final cap = _trunc2(i.amount);
                  return s + (paid > cap ? cap : paid);
                });

// المتبقي = الإجمالي - المدفوع (مع حماية من تجاوز المدفوع للإجمالي بسبب الكسور)
                final double totalRemain = (totalAmount -
                        (totalPaid > totalAmount ? totalAmount : totalPaid))
                    .clamp(0, double.infinity);

// قيمة المقدم للعرض كسطر مستقل تحت الجدول (فقط عند الخصم من الإجمالي)
                final double advanceShown =
                    deductFromTotal ? _trunc2(advancePaid) : 0.0;

// الأقساط (Contract-based): إجمالي الأقساط من العقد، والمدفوع/المتبقي من السندات غير الملغاة
                final int _monthsInTermLocal = (c == null)
                    ? 0
                    : (() {
                        switch (c!.term) {
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
                      })();

                final int _monthsPerCycleLocal = (c == null)
                    ? 1
                    : (() {
                        switch (c!.paymentCycle) {
                          case PaymentCycle.monthly:
                            return 1;
                          case PaymentCycle.quarterly:
                            return 3;
                          case PaymentCycle.semiAnnual:
                            return 6;
                          case PaymentCycle.annual:
                            return 12;
                        }
                      })();

                final int expectedInst = (c == null)
                    // لو ما وجدنا العقد (حالة نادرة)، تجاهل أيضًا سند المقدم من العدّادات
                    ? (deductFromTotal
                        ? filteredForPaid.length
                        : filteredItems.length)
                    : (c!.term == ContractTerm.daily
                        ? 1
                        : (((_monthsInTermLocal / _monthsPerCycleLocal).ceil())
                            .clamp(1, 1000)));

                final int paidInst =
                    filteredForPaid.where((i) => i.isPaid).length;
                final int remainInst =
                    (expectedInst - paidInst).clamp(0, 1000000);
                final int totalInst = expectedInst;

                final String cur = items.first.currency;
                final bool fullySettled = (paidInst >= totalInst) &&
                    filteredForPaid.every((i) => i.isPaid);
                final double totalPaidDisplay =
                    fullySettled ? totalAmount : totalPaid;
                final double totalRemainDisplay =
                    (totalAmount - totalPaidDisplay).clamp(0, double.infinity);

                Widget _cell(String text, {bool header = false}) => Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight:
                              header ? FontWeight.w800 : FontWeight.w700,
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
                            border: TableBorder.all(
                                color: Colors.white24, width: 1),
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
                                _cell(
                                    '${_fmtMoneyTrunc(totalAmount)} ريال\nالأقساط: $totalInst'),
                                _cell(
                                    '${_fmtMoneyTrunc(totalPaidDisplay)} ريال\nالأقساط: $paidInst'),
                                _cell(
                                    '${_fmtMoneyTrunc(totalRemainDisplay)} ريال\nالأقساط: $remainInst'),
                              ]),
                            ],
                          ),
                          if (advanceShown > 0) ...[
                            SizedBox(height: 8.h),
                            Row(
                              children: [
                                Text('إجمالي المقدم المدفوع',
                                    style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Text('${_fmtMoneyTrunc(advanceShown)} ريال',
                                    style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ],
                        ],
                      );
                    }

                    // ===== باقي العناصر: بطاقات السندات =====
                    final inv = items[idx - 1];
                    final statusColor = _statusColor(inv);
                    final statusText = _statusText(inv);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  InvoiceDetailsScreen(invoice: inv)),
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
                                  // رقم السند فقط (LTR)
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
                                    spacing: 6.w,
                                    runSpacing: 6.h,
                                    children: [
                                      _chip(
                                          'الإصدار: ${_fmtDateDynamic(inv.issueDate)}',
                                          bg: const Color(0xFF1F2937)),
                                      _invoicePeriodChip(inv, c),
                                      _chip(
                                          'القيمة: ${_fmtMoneyTrunc(inv.amount)} ريال',
                                          bg: const Color(0xFF1F2937)),
                                      _chip('الحالة: $statusText',
                                          bg: statusColor),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_left_rounded,
                                color: Colors.white70),
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

enum _ManualVoucherKind { receipt, expense }

class AddManualInvoiceScreen extends StatefulWidget {
  const AddManualInvoiceScreen({super.key});

  @override
  State<AddManualInvoiceScreen> createState() => _AddManualInvoiceScreenState();
}

class _AddManualInvoiceScreenState extends State<AddManualInvoiceScreen> {
  static const double _manualInvoiceMaxAmount = 500000000;
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _partyName = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final List<String> _attachments = <String>[];

  DateTime _issueDate = KsaTime.today();
  _ManualVoucherKind _kind = _ManualVoucherKind.receipt;
  String _paymentMethod = 'نقدًا';
  bool _processingAttachments = false;
  bool _showAmountLimitWarning = false;

  Box<Invoice> get _invoices => Hive.box<Invoice>(invoicesBoxName());

  void _setAmountLimitWarning(bool value) {
    if (!mounted || _showAmountLimitWarning == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showAmountLimitWarning == value) return;
      setState(() => _showAmountLimitWarning = value);
    });
  }

  Future<void> _pickIssueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _issueDate = KsaTime.dateOnly(picked));
  }

  Future<String?> _saveAttachmentLocally(PlatformFile file) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}invoice_attachments');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName =
          '${KsaTime.now().microsecondsSinceEpoch}_${safeName.isEmpty ? 'doc' : safeName}';
      final outFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (file.bytes != null) {
        await outFile.writeAsBytes(file.bytes!, flush: true);
        return outFile.path;
      }
      final src = file.path;
      if (src != null && src.isNotEmpty) {
        await File(src).copy(outFile.path);
        return outFile.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3', style: GoogleFonts.cairo()),
        ),
      );
      return;
    }

    final remaining = 3 - _attachments.length;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final selectedFiles = picked.files.take(remaining).toList();
    if (picked.files.length > remaining && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن رفع أكثر من 3', style: GoogleFonts.cairo()),
        ),
      );
    }

    setState(() => _processingAttachments = true);
    try {
      for (final file in selectedFiles) {
        final localPath = await _saveAttachmentLocally(file);
        if (localPath == null || _attachments.contains(localPath)) continue;
        _attachments.add(localPath);
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _processingAttachments = false);
    }
  }

  Future<void> _removeAttachment(String path) async {
    setState(() => _attachments.remove(path));
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final enteredAmount = double.tryParse(_amount.text.trim()) ?? 0.0;
    if (enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('أدخل مبلغًا صحيحًا', style: GoogleFonts.cairo()),
        ),
      );
      return;
    }

    final title = _title.text.trim();
    final partySnapshotName = _partyName.text.trim();
    final description = _note.text.trim();
    final now = KsaTime.now();
    final signedAmount =
        _kind == _ManualVoucherKind.expense ? -enteredAmount : enteredAmount;
    final manualNote = _buildManualInvoiceNote(
      title: title,
      description: description,
      partyName: partySnapshotName,
    );

    final invoice = Invoice(
      serialNo: _nextInvoiceSerialSync(_invoices),
      tenantId: '',
      contractId: '',
      propertyId: '',
      issueDate: KsaTime.dateOnly(_issueDate),
      dueDate: KsaTime.dateOnly(_issueDate),
      amount: signedAmount,
      paidAmount: enteredAmount,
      currency: 'SAR',
      note: '$manualNote\n[POSTED] تم اعتماد السند',
      paymentMethod: _paymentMethod,
      attachmentPaths: List<String>.from(_attachments),
      isArchived: false,
      isCanceled: false,
      createdAt: now,
      updatedAt: now,
    );

    await _invoices.put(invoice.id, invoice);
    if (!mounted) return;
    Navigator.of(context).pop(invoice);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
    String? warningMessage,
    bool Function(String text)? shouldShowWarning,
    bool forceShowWarning = false,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final showWarning = warningMessage != null &&
            (forceShowWarning ||
                (shouldShowWarning != null && shouldShowWarning(text)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller,
              validator: validator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLines: maxLines,
              maxLength: maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: (
                BuildContext context, {
                required int currentLength,
                required bool isFocused,
                required int? maxLength,
              }) {
                return const SizedBox.shrink();
              },
              style: GoogleFonts.cairo(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: GoogleFonts.cairo(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide:
                      BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                errorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFDC2626)),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                focusedErrorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFDC2626)),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
            if (showWarning)
              Padding(
                padding: EdgeInsets.only(top: 6.h, right: 6.w),
                child: Text(
                  warningMessage!,
                  style: GoogleFonts.cairo(
                    color: const Color(0xFFEF4444),
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _selectorTile({
    required String title,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _rowInfoWidget(String label, Widget child) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _partyName.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: darvooLeading(context, iconColor: Colors.white),
          title: Text(
            'إضافة سند',
            style: GoogleFonts.cairo(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0F766E),
                    Color(0xFF14B8A6),
                  ],
                ),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220.r, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260.r, const Color(0x22FFFFFF))),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
              child: _DarkCard(
                padding: EdgeInsets.all(16.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<_ManualVoucherKind>(
                        value: _kind,
                        decoration: InputDecoration(
                          labelText: 'نوع السند',
                          labelStyle: GoogleFonts.cairo(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.15)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        dropdownColor: const Color(0xFF0B1220),
                        iconEnabledColor: Colors.white70,
                        style: GoogleFonts.cairo(color: Colors.white),
                        items: const [
                          DropdownMenuItem(
                              value: _ManualVoucherKind.receipt,
                              child: Text('سند قبض')),
                          DropdownMenuItem(
                              value: _ManualVoucherKind.expense,
                              child: Text('سند صرف')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _kind = value);
                        },
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _partyName,
                        label: 'اسم الطرف',
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(40),
                        ],
                        maxLength: 40,
                        warningMessage:
                            'لا يمكن أن يزيد اسم الطرف على 40 حرفًا.',
                        shouldShowWarning: (text) => text.length >= 40,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'هذا الحقل مطلوب';
                          }
                          if (text.length > 40) {
                            return 'لا يمكن أن يزيد اسم الطرف على 40 حرفًا.';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),
                      _selectorTile(
                        title: 'تاريخ السند',
                        value: _fmtDateDynamic(_issueDate),
                        onTap: _pickIssueDate,
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _amount,
                        label: 'المبلغ',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}$')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text.trim();
                            if (text.isEmpty) {
                              _setAmountLimitWarning(false);
                              return newValue;
                            }
                            final amount = double.tryParse(text);
                            if (amount == null) {
                              _setAmountLimitWarning(false);
                              return newValue;
                            }
                            if (amount > _manualInvoiceMaxAmount) {
                              _setAmountLimitWarning(true);
                              return oldValue;
                            }
                            _setAmountLimitWarning(
                                amount >= _manualInvoiceMaxAmount);
                            return newValue;
                          }),
                        ],
                        warningMessage:
                            'لا يمكن أن يزيد المبلغ على 500 مليون.',
                        forceShowWarning: _showAmountLimitWarning,
                        shouldShowWarning: (text) {
                          final amount = double.tryParse(text.trim());
                          return amount != null &&
                              amount >= _manualInvoiceMaxAmount;
                        },
                        validator: (value) {
                          final amount = double.tryParse((value ?? '').trim()) ?? 0;
                          if (amount <= 0) return 'أدخل مبلغًا صحيحًا';
                          if (amount > 500000000) {
                            return 'لا يمكن أن يزيد المبلغ على 500 مليون.';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),
                      DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: 'طريقة الدفع',
                          labelStyle: GoogleFonts.cairo(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.15)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        dropdownColor: const Color(0xFF0B1220),
                        iconEnabledColor: Colors.white70,
                        style: GoogleFonts.cairo(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 'نقدًا', child: Text('نقدًا')),
                          DropdownMenuItem(
                              value: 'تحويل بنكي', child: Text('تحويل بنكي')),
                          DropdownMenuItem(value: 'شيك', child: Text('شيك')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _paymentMethod = value);
                        },
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _title,
                        label: 'عنوان السند',
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(15),
                        ],
                        maxLength: 15,
                        warningMessage:
                            'لا يمكن أن يزيد عنوان السند على 15 حرفًا.',
                        shouldShowWarning: (text) => text.length >= 15,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return 'هذا الحقل مطلوب';
                          if (text.length > 15) {
                            return 'لا يمكن أن يزيد عنوان السند على 15 حرفًا.';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12.h),
                      _field(
                        controller: _note,
                        label: 'البيان',
                        maxLines: 3,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(300),
                        ],
                        maxLength: 300,
                        warningMessage:
                            'لا يمكن أن يزيد البيان على 300 حرف.',
                        shouldShowWarning: (text) => text.length >= 300,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return 'هذا الحقل مطلوب';
                          if (text.length > 300) {
                            return 'لا يمكن أن يزيد البيان على 300 حرف.';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'المرفقات (${_attachments.length}/3)',
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0EA5E9),
                              foregroundColor: Colors.white,
                            ),
                            onPressed:
                                _processingAttachments ? null : _pickAttachments,
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text('إرفاق',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      if (_attachments.isNotEmpty) ...[
                        SizedBox(height: 10.h),
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: _attachments.map((path) {
                            final ext = path.split('.').last.toLowerCase();
                            final isPdf = ext == 'pdf';
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 88.w,
                                  height: 88.w,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10.r),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.15)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPdf
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.image_rounded,
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 6.h),
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6.w),
                                        child: Text(
                                          path.split(Platform.pathSeparator).last,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                              color: Colors.white70,
                                              fontSize: 10.sp),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _removeAttachment(path),
                                    child: Container(
                                      width: 26.w,
                                      height: 26.w,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFB91C1C),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 15.sp,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ],
                      SizedBox(height: 18.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            'حفظ السند',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualInvoicePartyPickerSheet extends StatefulWidget {
  const _ManualInvoicePartyPickerSheet();

  @override
  State<_ManualInvoicePartyPickerSheet> createState() =>
      _ManualInvoicePartyPickerSheetState();
}

class _ManualInvoicePartyPickerSheetState
    extends State<_ManualInvoicePartyPickerSheet> {
  Box<Tenant> get _tenants => Hive.box<Tenant>(tenantsBoxName());
  String _q = '';
  bool _expandTenants = false;
  bool _expandProviders = false;

  String _clientTypeKey(Tenant tenant) {
    final raw = tenant.clientType.trim().toLowerCase();
    if (raw == 'serviceprovider' ||
        raw == 'service_provider' ||
        raw == 'service provider' ||
        raw == 'مقدم خدمة') {
      return 'provider';
    }
    final hasProviderHints =
        (tenant.serviceSpecialization ?? '').trim().isNotEmpty &&
            (tenant.companyName ?? '').trim().isEmpty &&
            (tenant.companyCommercialRegister ?? '').trim().isEmpty &&
            (tenant.tenantBankName ?? '').trim().isEmpty;
    if (hasProviderHints) return 'provider';
    return 'tenant';
  }

  bool _matches(Tenant tenant) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    return tenant.fullName.toLowerCase().contains(q) ||
        tenant.nationalId.toLowerCase().contains(q) ||
        tenant.phone.toLowerCase().contains(q) ||
        (tenant.companyName ?? '').toLowerCase().contains(q) ||
        (tenant.serviceSpecialization ?? '').toLowerCase().contains(q);
  }

  Widget _sectionTile({
    required String title,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<Tenant> items,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: Text(
          title,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        childrenPadding: EdgeInsets.only(right: 8.w, left: 8.w, bottom: 6.h),
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10.w, vertical: 0),
              onTap: () => Navigator.of(context).pop(item),
              leading: Icon(
                _clientTypeKey(item) == 'provider'
                    ? Icons.handyman_rounded
                    : Icons.person_rounded,
                color: Colors.white70,
              ),
              title: Text(
                item.fullName,
                style: GoogleFonts.cairo(color: Colors.white),
              ),
              subtitle: Text(
                _clientTypeKey(item) == 'provider'
                    ? ((item.serviceSpecialization ?? '').trim().isEmpty
                        ? 'مقدم خدمة'
                        : 'مقدم خدمة • ${(item.serviceSpecialization ?? '').trim()}')
                    : _invoiceSnapshotClientTypeLabel(item.clientType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(color: Colors.white70),
              ),
              trailing: item.isBlacklisted
                  ? _chip('محظور', bg: const Color(0xFF7F1D1D))
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم/الهوية/الجوال',
                  hintStyle: GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _tenants.listenable(),
                  builder: (context, Box<Tenant> b, _) {
                    final all = b.values.where((t) => !t.isArchived).toList()
                      ..sort((a, c) => a.fullName.compareTo(c.fullName));
                    final visible = all.where(_matches).toList(growable: false);
                    final tenants = visible
                        .where((t) => _clientTypeKey(t) != 'provider')
                        .toList(growable: false);
                    final providers = visible
                        .where((t) => _clientTypeKey(t) == 'provider')
                        .toList(growable: false);

                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          'لا توجد نتائج مطابقة',
                          style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }

                    final searchOpen = _q.trim().isNotEmpty;
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          title: Text(
                            'بدون تحديد',
                            style: GoogleFonts.cairo(color: Colors.white),
                          ),
                          onTap: () => Navigator.of(context).pop(null),
                        ),
                        if (tenants.isNotEmpty)
                          _sectionTile(
                            title: 'المستأجرون',
                            expanded: searchOpen || _expandTenants,
                            onExpansionChanged: (isOpen) =>
                                setState(() => _expandTenants = isOpen),
                            items: tenants,
                          ),
                        if (providers.isNotEmpty)
                          _sectionTile(
                            title: 'مقدمو الخدمات',
                            expanded: searchOpen || _expandProviders,
                            onExpansionChanged: (isOpen) =>
                                setState(() => _expandProviders = isOpen),
                            items: providers,
                          ),
                      ],
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

class _ManualInvoicePropertyPickerSheet extends StatefulWidget {
  const _ManualInvoicePropertyPickerSheet();

  @override
  State<_ManualInvoicePropertyPickerSheet> createState() =>
      _ManualInvoicePropertyPickerSheetState();
}

class _ManualInvoicePropertyPickerSheetState
    extends State<_ManualInvoicePropertyPickerSheet> {
  Box<Property> get _properties => Hive.box<Property>(propsBoxName());
  String _q = '';
  final Set<String> _expandedBuildingIds = <String>{};

  bool _matches(Property property) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    return property.name.toLowerCase().contains(q) ||
        property.address.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم العقار/العنوان',
                  hintStyle: GoogleFonts.cairo(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Flexible(
                child: ValueListenableBuilder(
                  valueListenable: _properties.listenable(),
                  builder: (context, Box<Property> b, _) {
                    final all = b.values.where((p) => !p.isArchived).toList();
                    final topLevel =
                        all.where((p) => p.parentBuildingId == null).toList();
                    final unitsByBuilding = <String, List<Property>>{};
                    for (final p in all) {
                      final parentId = p.parentBuildingId;
                      if (parentId == null) continue;
                      unitsByBuilding
                          .putIfAbsent(parentId, () => <Property>[])
                          .add(p);
                    }
                    for (final units in unitsByBuilding.values) {
                      units.sort((a, c) => a.name.compareTo(c.name));
                    }

                    topLevel.sort((a, c) {
                      final aHasUnits = a.type == PropertyType.building &&
                          (unitsByBuilding[a.id]?.isNotEmpty ?? false);
                      final cHasUnits = c.type == PropertyType.building &&
                          (unitsByBuilding[c.id]?.isNotEmpty ?? false);
                      if (aHasUnits != cHasUnits) return aHasUnits ? -1 : 1;
                      return a.name.compareTo(c.name);
                    });

                    final widgets = <Widget>[
                      ListTile(
                        title: Text(
                          'بدون تحديد',
                          style: GoogleFonts.cairo(color: Colors.white),
                        ),
                        onTap: () => Navigator.of(context).pop(null),
                      ),
                    ];

                    for (final property in topLevel) {
                      final units =
                          unitsByBuilding[property.id] ?? const <Property>[];
                      final isBuildingWithUnits =
                          property.type == PropertyType.building &&
                              units.isNotEmpty;

                      if (isBuildingWithUnits) {
                        final showBuilding = _matches(property);
                        final visibleUnits = showBuilding
                            ? units
                            : units.where(_matches).toList(growable: false);
                        if (!showBuilding && visibleUnits.isEmpty) continue;
                        final expanded = _expandedBuildingIds.contains(property.id) ||
                            _q.trim().isNotEmpty;
                        widgets.add(
                          Container(
                            margin: EdgeInsets.only(bottom: 6.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.10)),
                            ),
                            child: ExpansionTile(
                              key: ValueKey('manual_invoice_building_${property.id}'),
                              initiallyExpanded: expanded,
                              onExpansionChanged: (isOpen) {
                                setState(() {
                                  if (isOpen) {
                                    _expandedBuildingIds.add(property.id);
                                  } else {
                                    _expandedBuildingIds.remove(property.id);
                                  }
                                });
                              },
                              iconColor: Colors.white70,
                              collapsedIconColor: Colors.white70,
                              title: Text(
                                property.name,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                property.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(color: Colors.white70),
                              ),
                              childrenPadding:
                                  EdgeInsets.only(right: 8.w, left: 8.w),
                              children: [
                                Padding(
                                  padding:
                                      EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'اختر وحدة من هذه العمارة',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                for (final unit in visibleUnits)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 0),
                                    onTap: () =>
                                        Navigator.of(context).pop(unit),
                                    leading: const Icon(
                                      Icons.meeting_room_rounded,
                                      color: Colors.white70,
                                    ),
                                    title: Text(
                                      unit.name,
                                      style: GoogleFonts.cairo(
                                          color: Colors.white),
                                    ),
                                    subtitle: (unit.address).trim().isEmpty
                                        ? null
                                        : Text(
                                            unit.address,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.cairo(
                                                color: Colors.white70),
                                          ),
                                    trailing: _chip('وحدة',
                                        bg: const Color(0xFF334155)),
                                  ),
                              ],
                            ),
                          ),
                        );
                        continue;
                      }

                      if (!_matches(property)) continue;
                      widgets.add(
                        Padding(
                          padding: EdgeInsets.only(bottom: 6.h),
                          child: ListTile(
                            onTap: () => Navigator.of(context).pop(property),
                            leading: const Icon(Icons.home_work_rounded,
                                color: Colors.white),
                            title: Text(
                              property.name,
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                            subtitle: Text(
                              property.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(color: Colors.white70),
                            ),
                            trailing: _chip(
                              property.type == PropertyType.building
                                  ? 'عمارة'
                                  : 'مستقل',
                              bg: const Color(0xFF334155),
                            ),
                          ),
                        ),
                      );
                    }

                    if (widgets.length == 1) {
                      return Center(
                        child: Text(
                          'لا توجد نتائج مطابقة',
                          style: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }

                    return ListView(
                      shrinkWrap: true,
                      children: widgets,
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
/// مسارات
/// ===============================================================================
class InvoicesRoutes {
  static Map<String, WidgetBuilder> routes() => {
        '/invoices': (context) => const InvoicesScreen(),
        '/invoices/history': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final id = (args is Map && args['contractId'] is String)
              ? args['contractId'] as String
              : '';
          return InvoicesHistoryScreen(contractId: id);
        },
      };
}
