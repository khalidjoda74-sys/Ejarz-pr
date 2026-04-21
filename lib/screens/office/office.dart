// lib/screens/office/office.dart
// ï¿½.ï¿½"ف �.�^ح�'د �Sض�. شاشات ا�"ï¿½.ï¿½fØªØ¨: OfficeHomePage + OfficeClientsPage
// + AddOfficeClientDialog + EditOfficeClientDialog + ClientAccessDialog + DeleteClientDialog
//
// Ø§ï¿½"تعد�S�" Ø§ï¿½"جذر�S ا�"ï¿½.Ø·ï¿½"�^ب:
// - �f�" Ø§ï¿½"ع�.�"ï¿½SØ§Øª (Ø¥Ø¶Ø§ÙØ©/ØªØ¹Ø¯ï¿½Sï¿½"/دخ�^�"/Ø­Ø°Ù) ØªØ¹ï¿½.ï¿½" �.ح�"ï¿½Sï¿½<Ø§ Ùï¿½^Ø±ï¿½<Ø§ Ø¯ï¿½^ï¿½? Ø£ï¿½S Ø­Ø¬Ø¨ Ø£ï¿½^ Ø¯ï¿½^Ø§Ø¦Ø± Ø§ï¿½?ØªØ¸Ø§Ø±.
// - Ø¹ï¿½?Ø¯ Ø§ï¿½"إضافة �Sظ�?ر ا�"Ø¹ï¿½.ï¿½Sï¿½" ف�^ر�<ا أع�"ï¿½? Ø§ï¿½"�,ائ�.ة �^�Sب�,�? ثابت�<ا ف�S �.�fا�?�? حت�? �.ع ا�"ï¿½.Ø²Ø§ï¿½.ï¿½?Ø©.
// - Ø«Ø¨Ø§Øª Ø§ï¿½"عرض بعد ا�"Ø±Ø¬ï¿½^Ø¹ ï¿½.ï¿½? ØªØ·Ø¨ï¿½Sï¿½, Ø§ï¿½"ع�.�S�": ØªØ«Ø¨ï¿½SØª ï¿½?Ø·Ø§ï¿½, Hive Ø¥ï¿½"�? UID ا�"ï¿½.ï¿½fØªØ¨ ï¿½fï¿½"�.ا ظ�?رت شاشة ا�"ï¿½.ï¿½fØªØ¨.
// - Ø§ï¿½"أزرار (ا�"Ø¬Ø±Ø³/Øµï¿½"اح�Sات ا�"Ø¯Ø®ï¿½^ï¿½") تظ�?ر دائ�.�<ا�> �^تفتح حت�? بد�^�? إ�?تر�?ت.
// - ا�"ï¿½.Ø²Ø§ï¿½.ï¿½?Ø© ØªØªï¿½. Øªï¿½"�,ائ�S�<ا ع�?د رج�^ع ا�"Ø´Ø¨ï¿½fØ©.
// - ï¿½o. ØªØ£ï¿½fï¿½SØ¯ Ø§ï¿½"حذف دائ�.�<ا س�^اء ا�"Ø¹ï¿½.ï¿½Sï¿½" �.ح�"ï¿½S (pending) Ø£ï¿½^ Ø³Ø­Ø§Ø¨ï¿½S.
// - ï¿½o. Ø´Ø§Ø´Ø© Ø§ï¿½"تعد�S�" ØªÙØ¶ï¿½'�" تعد�S�"ات�f ا�"�.ح�"�Sة ا�"�.ع�"�'ï¿½,Ø© ï¿½^ï¿½"ا تع�Sد ا�"ï¿½,ï¿½Sï¿½. Ø§ï¿½"�,د�S�.ة.
//
// ignore_for_file: use_build_context_synchronously
import 'package:darvoo/utils/ksa_time.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:darvoo/data/services/offline_sync_service.dart';
import 'package:darvoo/data/services/user_scope.dart' as scope;
import 'package:darvoo/widgets/custom_confirm_dialog.dart';

import 'widgets/office_side_drawer.dart';
import 'package:darvoo/data/services/subscription_alerts.dart';
import 'package:darvoo/data/services/hive_service.dart';
import 'package:darvoo/data/services/subscription_expiry.dart';
import 'package:darvoo/data/services/office_client_guard.dart';
import 'package:darvoo/data/services/package_limit_service.dart';
import 'package:darvoo/data/sync/sync_bridge.dart';
import 'package:darvoo/data/services/firestore_user_collections.dart';
import 'package:darvoo/data/repos/tenants_repo.dart';
import 'package:darvoo/ui/widgets/entity_audit_info_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:darvoo/ui/ai_chat/ai_chat_icon.dart';

/// ======================== OfficeSession ========================
class OfficeSession {
  static const _boxName = '_officeSessionBox';
  static const _kToken = 'returnToken';
  static const _kUid = 'expectedOfficeUid';
  static const _kSavedAt = 'savedAtIso';
  static const _sessionBoxName = 'sessionBox';
  static const _kImpersonation = 'officeImpersonation';

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  static Future<void> storeReturnContext({
    required String expectedOfficeUid,
    String? officeReturnToken,
  }) async {
    final b = await _box();
    await b.put(_kUid, expectedOfficeUid);
    await b.put(
        _kToken, officeReturnToken ?? 'office-return'); // أ�S �?ص غ�Sر فارغ
    await b.put(_kSavedAt, KsaTime.now().toIso8601String());
    final session = Hive.isBoxOpen(_sessionBoxName)
        ? Hive.box(_sessionBoxName)
        : await Hive.openBox(_sessionBoxName);
    await session.put(_kImpersonation, true);
  }

  static Future<String?> get expectedOfficeUid async {
    final b = await _box();
    return b.get(_kUid) as String?;
  }

  static Future<String?> get officeToken async {
    final b = await _box();
    return b.get(_kToken) as String?;
  }

  static Future<void> clear() async {
    final b = await _box();
    await b.delete(_kToken);
    await b.delete(_kUid);
    await b.delete(_kSavedAt);
    final session = Hive.isBoxOpen(_sessionBoxName)
        ? Hive.box(_sessionBoxName)
        : await Hive.openBox(_sessionBoxName);
    await session.put(_kImpersonation, false);
  }

  static Future<void> backToOffice(BuildContext context) async {
    final expectedUid = await expectedOfficeUid;
    final user = FirebaseAuth.instance.currentUser;
    final authUid = user?.uid ?? '';
    String targetUid = (expectedUid ?? '').trim();

    if (targetUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد جلسة مكتب محفوظة للرجوع.')),
      );
      return;
    }

    if (authUid.isNotEmpty && targetUid != authUid) {
      var claimOfficeId = '';
      var role = '';
      try {
        final token = await user?.getIdTokenResult();
        final claims = token?.claims ?? const <String, dynamic>{};
        claimOfficeId =
            (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
        role = (claims['role'] ?? '').toString().toLowerCase().trim();
      } catch (_) {}
      final isOfficeStaff =
          role == 'office_staff' || role == 'office-user' || role == 'staff';
      final allowScoped = isOfficeStaff && claimOfficeId == targetUid;
      if (!allowScoped) {
        targetUid = authUid;
      }
    }

    // �o. رج�'ع ا�"Ø¬ï¿½"سة �"ï¿½^Ø¶Ø¹ "�.�fتب" Ø¹Ø§Ø¯ï¿½S (ï¿½"�Sس ع�.�S�" ï¿½.ï¿½fØªØ¨)
    if (Hive.isBoxOpen('sessionBox')) {
      final session = Hive.box('sessionBox');
      await session.put('isOfficeClient', false);
      await session.put(_kImpersonation, false);
    }
    await OfficeClientGuard.refreshFromLocal();

    // ï¿½o. Ø«Ø¨ï¿½'ت �?طا�, Hive ع�"�? UID ا�"�.�fتب
    scope.setFixedUid(targetUid);

    // �o. أعد ت�?�Sئة جس�^ر ا�"�.زا�.�?ة �^خد�.ة ا�"أ�^ف�"ا�S�? �"�"�.�fتب
    try {
      await SyncManager.instance.stopAll();
    } catch (_) {}

    try {
      OfflineSyncService.instance.dispose();
    } catch (_) {}

    final uc = UserCollections(targetUid);
    final tenantsRepo = TenantsRepo(uc);
    await OfflineSyncService.instance.init(uc: uc, repo: tenantsRepo);

    await HiveService.ensureReportsBoxesOpen();

    try {
      await SyncManager.instance.startAll();
    } catch (_) {}

    await clear();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/office', (r) => false);
    }
  }
}

/// ======================== Runtime ========================
class OfficeRuntime {
  static final selectedClientUid = ValueNotifier<String?>(null);
  static final selectedClientName = ValueNotifier<String?>(null);

  static void selectClient({required String uid, required String name}) {
    selectedClientUid.value = uid;
    selectedClientName.value = name;
  }

  static void clear() {
    selectedClientUid.value = null;
    selectedClientName.value = null;
  }
}

/// ======================== Helpers ========================
void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

String _compactStackTrace(StackTrace stackTrace, [int maxLines = 3]) {
  return stackTrace
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(maxLines)
      .join(' | ');
}

void _traceOfficeRuntime(String message) {
  debugPrint(
      '[OfficeRuntimeTrace][${DateTime.now().toIso8601String()}] $message');
}

// Coalesce identical `get()` calls for the same document path to avoid
// tight-loop spam and UI jank when multiple widgets request the same doc.
final Map<String, Future<Map<String, dynamic>>> _docGetInFlight = {};

Future<Map<String, dynamic>> _safeReadDocData(
  DocumentReference<Map<String, dynamic>> ref, {
  Duration timeout = const Duration(seconds: 8),
  String traceLabel = '',
}) async {
  final inflightKey = ref.path;
  final existing = _docGetInFlight[inflightKey];
  if (existing != null) {
    _traceOfficeRuntime('doc-get join-inflight path=${ref.path}');
    return await existing;
  }

  final sw = Stopwatch()..start();
  final label = traceLabel.trim().isEmpty ? ref.path : traceLabel.trim();
  final fut = () async {
    _traceOfficeRuntime(
      'doc-get start label=$label path=${ref.path} timeoutMs=${timeout.inMilliseconds}',
    );
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      _traceOfficeRuntime(
        'doc-get hit source=server label=$label exists=${snap.exists} fromCache=${snap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
      );
      return snap.data() ?? const <String, dynamic>{};
    } on TimeoutException catch (e, st) {
      _traceOfficeRuntime(
        'doc-get timeout label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        _traceOfficeRuntime(
          'doc-get hit source=cache-after-timeout label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
        );
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (cacheError, cacheStack) {
        _traceOfficeRuntime(
          'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${_compactStackTrace(cacheStack)}',
        );
        return const <String, dynamic>{};
      }
    } catch (e, st) {
      _traceOfficeRuntime(
        'doc-get error label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
      try {
        final cacheSnap = await ref.get(const GetOptions(source: Source.cache));
        _traceOfficeRuntime(
          'doc-get hit source=cache-after-error label=$label exists=${cacheSnap.exists} fromCache=${cacheSnap.metadata.isFromCache} +${sw.elapsedMilliseconds}ms',
        );
        return cacheSnap.data() ?? const <String, dynamic>{};
      } catch (cacheError, cacheStack) {
        _traceOfficeRuntime(
          'doc-get cache-failed label=$label path=${ref.path} +${sw.elapsedMilliseconds}ms err=$cacheError stack=${_compactStackTrace(cacheStack)}',
        );
        return const <String, dynamic>{};
      }
    }
  }();

  _docGetInFlight[inflightKey] = fut;
  try {
    return await fut;
  } finally {
    _docGetInFlight.remove(inflightKey);
  }
}

Future<bool> _hasInternetConnection() async {
  bool online = false;
  try {
    final results = await Connectivity().checkConnectivity();
    online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    }
  } catch (_) {
    online = false;
  }
  return online;
}

Future<void> _showInternetRequiredDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: _DarkCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDC2626).withOpacity(0.2),
                  border: Border.all(color: const Color(0x66EF4444)),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFFCA5A5),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'حسنًا',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
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

String _fmtDateKsa(DateTime? utc) {
  if (utc == null) return '-';
  final ksa = utc.toUtc().add(const Duration(hours: 3));
  final y = ksa.year.toString().padLeft(4, '0');
  final m = ksa.month.toString().padLeft(2, '0');
  final d = ksa.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}

DateTime _ksaDateOnly(DateTime dt) {
  final ksa = dt.toUtc().add(const Duration(hours: 3));
  return DateTime(ksa.year, ksa.month, ksa.day);
}

String _fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? _parseYmdFlexible(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty) return null;
  final normalized = raw.replaceAll('/', '-');
  final p = normalized.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12) return null;
  if (d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

DateTime _addOneMonthClamped(DateTime start) {
  final y = start.year + (start.month == 12 ? 1 : 0);
  final m = start.month == 12 ? 1 : start.month + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  final d = math.min(start.day, lastDay);
  return DateTime(
    y,
    m,
    d,
    start.hour,
    start.minute,
    start.second,
    start.millisecond,
    start.microsecond,
  );
}

DateTime _subscriptionEndFromStart(DateTime start) {
  return _addOneMonthClamped(start);
}

DateTime? _parseClientDateOnly(Map<String, dynamic> m, List<String> keys) {
  for (final key in keys) {
    final v = m[key];
    if (v is String) {
      final d = _parseYmdFlexible(v);
      if (d != null) return d;
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return _ksaDateOnly(parsed);
    } else if (v is Timestamp) {
      return _ksaDateOnly(v.toDate());
    } else if (v is DateTime) {
      return _ksaDateOnly(v);
    }
  }
  return null;
}

DateTime? _parseClientDateTime(Map<String, dynamic> m, List<String> keys) {
  for (final key in keys) {
    final v = m[key];
    if (v is Timestamp) {
      final dt = v.toDate();
      return dt.toUtc().add(const Duration(hours: 3));
    } else if (v is DateTime) {
      return v.toUtc().add(const Duration(hours: 3));
    } else if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) {
        return parsed.toUtc().add(const Duration(hours: 3));
      }
      final d = _parseYmdFlexible(v);
      if (d != null) return d;
    }
  }
  return null;
}

double? _parsePrice(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int _parseReminderDays(dynamic v) {
  int n = 1;
  if (v is int) {
    n = v;
  } else if (v is num) {
    n = v.toInt();
  } else if (v is String) {
    n = int.tryParse(v.trim()) ?? 1;
  }
  return n.clamp(1, 3);
}

class _ClientSubscriptionDialogResult {
  final bool enabled;
  final DateTime startDate;
  final DateTime endDate;
  final double price;
  final int reminderDays;

  const _ClientSubscriptionDialogResult({
    required this.enabled,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.reminderDays,
  });
}

class _OfficeClientSubscriptionAlert {
  final String clientName;
  final DateTime endDate;
  final int reminderDays;
  final bool isExpiredToday;

  const _OfficeClientSubscriptionAlert({
    required this.clientName,
    required this.endDate,
    required this.reminderDays,
    required this.isExpiredToday,
  });

  String get title =>
      isExpiredToday ? 'انتهى اشتراك العميل' : 'اقتراب انتهاء اشتراك العميل';

  String get body {
    if (isExpiredToday) {
      return 'تم انتهاء اشتراك "$clientName".';
    }
    if (reminderDays == 1) {
      return 'اشتراك "$clientName" ينتهي بعد يوم واحد.';
    }
    return 'اشتراك "$clientName" ينتهي بعد $reminderDays أيام.';
  }
}

/// �Sجع�" ر�,�. ا�"ج�^ا�" اخت�Sار�S�<ا�O �^�"�f�? إ�? أُدخ�" �Sجب أ�? �S�f�^�? 10 أر�,ا�. با�"ضبط.
String? normalizeLocalPhoneForUi(String? phone) {
  final raw = (phone ?? '').trim();
  if (raw.isEmpty) return '';
  final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length != 10) return null;
  return digitsOnly;
}

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
  final double? minHeight;
  const _DarkCard({required this.child, this.padding, this.minHeight});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }
}

TextStyle get _titleStyle => GoogleFonts.cairo(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 18,
    );

TextStyle get _subStyle => GoogleFonts.cairo(
      color: Colors.white70,
      fontWeight: FontWeight.w700,
      fontSize: 12,
    );

/// �o. ف�^ر�.اتر �S�.�?ع تجا�^ز حد ا�"ط�^�" �.ع ت�?ب�S�? ف�^ر�S
class _LengthLimitFormatter extends TextInputFormatter {
  final int max;
  final VoidCallback? onExceed;
  _LengthLimitFormatter(this.max, {this.onExceed});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    onExceed?.call();
    HapticFeedback.selectionClick();
    return oldValue;
  }
}

/// زر دائر�S أ�S�,�^�?ة ف�,ط �?" �.صغ�'Ø± ï¿½^ï¿½.Øªï¿½?Ø§Ø³ï¿½,
class _IconCircleBtn extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  final String? tooltip;

  final double size; // ï¿½,Ø·Ø± Ø§ï¿½"زر
  final double iconSize; // حج�. ا�"Ø£ï¿½Sï¿½,ï¿½^ï¿½?Ø©
  final bool disabled;

  const _IconCircleBtn({
    required this.icon,
    required this.onTap,
    this.bg = const Color(0xFF1E293B),
    this.tooltip,
    this.size = 42.0,
    this.iconSize = 20.0,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: Colors.white),
    );

    return Tooltip(
      message: tooltip ?? '',
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? 0.55 : 1.0,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ø¯Ø§Ø¦Ø±Ø© Ø§ï¿½?ØªØ¸Ø§Ø± Ø´ÙØ§ÙØ© Ø£Ø«ï¿½?Ø§Ø¡ Ø§ï¿½"ا�?تحا�" Ùï¿½,Ø· (ï¿½"�. �?�"Øºï¿½?Ø§ ï¿½"أ�?�?ا �"Ø§ ØªØªØ¹ï¿½"�, با�"Ø¥Ø¶Ø§ÙØ©/Ø§ï¿½"تعد�S�")
class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: const CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================== (A) OfficeNotificationsBell ========================
class OfficeNotificationsBell extends StatefulWidget {
  const OfficeNotificationsBell({super.key});

  @override
  State<OfficeNotificationsBell> createState() =>
      _OfficeNotificationsBellState();
}

class _OfficeNotificationsBellState extends State<OfficeNotificationsBell> {
  int _badge = 0;
  SubscriptionAlert? _officeSubscriptionAlert;
  List<_OfficeClientSubscriptionAlert> _clientAlerts = const [];
  Timer? _midnightTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clientsSub;
  Future<void>? _refreshInFlight;
  DateTime? _cachedOfficeEndAt;
  DateTime? _cachedOfficeEndAtFetchedAtUtc;

  @override
  void initState() {
    super.initState();
    _refresh();
    _bindClientAlertsWatcher();
    _scheduleNextCheck();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _clientsSub?.cancel();
    super.dispose();
  }

  void _bindClientAlertsWatcher() {
    _clientsSub?.cancel();
    final officeUid = _resolveOfficeUid();
    if (officeUid.isEmpty) return;

    _clientsSub = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeUid)
        .collection('clients')
        .snapshots()
        .listen(
      (qs) {
        final alerts = _computeClientAlertsFromDocs(qs.docs);
        if (!mounted) return;
        setState(() {
          _clientAlerts = alerts;
          _badge = (_officeSubscriptionAlert == null ? 0 : 1) + alerts.length;
        });
      },
      onError: (_) {},
    );
  }

  void _scheduleNextCheck() {
    _midnightTimer?.cancel();
    // Compute the next KSA day boundary from the current KSA wall-clock value.
    final nowUtc = KsaTime.nowUtc();
    final nowKsa = KsaTime.toKsa(nowUtc);
    final nextKsa =
        DateTime(nowKsa.year, nowKsa.month, nowKsa.day).add(const Duration(
      days: 1,
      minutes: 1,
    ));
    final nextUtc = KsaTime.fromKsaToUtc(nextKsa);
    var delay = nextUtc.difference(nowUtc);
    if (delay < const Duration(seconds: 1)) {
      _traceOfficeRuntime(
        'office-notifications schedule-next-check clamped delayMs=${delay.inMilliseconds} nowUtc=$nowUtc nextUtc=$nextUtc',
      );
      delay = const Duration(seconds: 1);
    }
    _midnightTimer = Timer(delay, () {
      _refresh(); // guarded (coalesced) to avoid parallel Firestore reads
      _scheduleNextCheck();
    });
  }

  Future<DateTime?> _subscriptionEndProvider() async {
    try {
      final scopedUid = scope.effectiveUid();
      final userUid = scopedUid == 'guest'
          ? FirebaseAuth.instance.currentUser?.uid
          : scopedUid;
      if (userUid == null || userUid.isEmpty) return null;

      final cacheAtUtc = _cachedOfficeEndAtFetchedAtUtc;
      if (cacheAtUtc != null &&
          DateTime.now().toUtc().difference(cacheAtUtc) <
              const Duration(seconds: 30)) {
        return _cachedOfficeEndAt;
      }

      final data = await _safeReadDocData(
        FirebaseFirestore.instance.collection('users').doc(userUid),
        traceLabel: 'office-subscription users/$userUid',
      );
      if (data.isEmpty) return null;

      // 1) ï¿½?Ø³ØªØ®Ø¯ï¿½. end_date_ksa Ø¥ï¿½? ï¿½^ÙØ¬Ø¯ (ï¿½?ÙØ³ ï¿½?Ø§ÙØ°Ø© "اشترا�f�S" ï¿½"�"ï¿½.ï¿½fØªØ¨)
      final endKsaText = (data['end_date_ksa'] as String?)?.trim();
      if (endKsaText != null && endKsaText.isNotEmpty) {
        final normalized = endKsaText.replaceAll('/', '-');
        final parts = normalized.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            final endAt = DateTime(y, m, d);
            _cachedOfficeEndAt = endAt;
            _cachedOfficeEndAtFetchedAtUtc = DateTime.now().toUtc();
            return endAt;
          }
        }
      }

      // 2) fallback ï¿½"�"Ø­Ø³Ø§Ø¨Ø§Øª Ø§ï¿½"�,د�S�.ة: �?حسب �.�? subscription_end بت�^�,�Sت ا�"Ø³Ø¹ï¿½^Ø¯ï¿½SØ©
      final raw = data['subscription_end'];
      DateTime? dt;
      if (raw is Timestamp) {
        dt = raw.toDate();
      } else if (raw is DateTime) {
        dt = raw;
      } else if (raw is String) {
        dt = DateTime.tryParse(raw);
      }
      if (dt == null) return null;

      final utc = dt.toUtc();
      final ksa = utc.add(const Duration(hours: 3));
      final endAt = DateTime(ksa.year, ksa.month, ksa.day);
      _cachedOfficeEndAt = endAt;
      _cachedOfficeEndAtFetchedAtUtc = DateTime.now().toUtc();
      return endAt;
    } catch (e, st) {
      _traceOfficeRuntime(
        'office-subscription end-provider error err=$e stack=${_compactStackTrace(st)}',
      );
      return null;
    }
  }

  Future<void> _refresh() async {
    _refreshInFlight ??= () async {
      final endAt = await _subscriptionEndProvider();
      final officeAlert = SubscriptionAlerts.compute(endAt: endAt);
      if (!mounted) return;
      setState(() {
        _officeSubscriptionAlert = officeAlert;
        _badge = (officeAlert == null ? 0 : 1) + _clientAlerts.length;
      });
    }();
    try {
      await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
    }
  }

  String _resolveOfficeUid() {
    final scoped = scope.effectiveUid().trim();
    if (scoped.isEmpty || scoped == 'guest') {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    }
    return scoped;
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<_OfficeClientSubscriptionAlert> _computeClientAlertsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    try {
      final now = KsaTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final alerts = <_OfficeClientSubscriptionAlert>[];

      for (final d in docs) {
        final m = d.data();
        if (m['subscriptionEnabled'] != true) continue;

        DateTime? endDate = _parseClientDateOnly(m, const [
          'subscriptionEndKsa',
          'subscriptionEndDate',
          'subscriptionEndAt',
        ]);
        final startDate = _parseClientDateOnly(m, const [
          'subscriptionStartKsa',
          'subscriptionStartDate',
          'subscriptionStartAt',
        ]);
        if (endDate == null && startDate != null) {
          endDate = _subscriptionEndFromStart(startDate);
        }
        if (endDate == null) continue;

        final reminderDays = _parseReminderDays(m['subscriptionReminderDays']);
        final reminderDate = endDate.subtract(Duration(days: reminderDays));
        final expiredAt = endDate.add(const Duration(days: 1));

        final isReminderToday = _sameDate(today, reminderDate);
        final isExpiredToday = _sameDate(today, expiredAt);
        if (!isReminderToday && !isExpiredToday) continue;

        final clientName = (m['name'] ?? '').toString().trim().isNotEmpty
            ? (m['name'] ?? '').toString().trim()
            : (m['email'] ?? d.id).toString();

        alerts.add(
          _OfficeClientSubscriptionAlert(
            clientName: clientName,
            endDate: endDate,
            reminderDays: reminderDays,
            isExpiredToday: isExpiredToday,
          ),
        );
      }

      alerts.sort((a, b) {
        final byPriority =
            (a.isExpiredToday ? 0 : 1).compareTo(b.isExpiredToday ? 0 : 1);
        if (byPriority != 0) return byPriority;
        return a.endDate.compareTo(b.endDate);
      });
      return alerts;
    } catch (e, st) {
      _traceOfficeRuntime(
        'office-notifications compute-client-alerts error err=$e stack=${_compactStackTrace(st)}',
      );
      return const [];
    }
  }

  Future<void> _openSheet() async {
    final officeAlert = _officeSubscriptionAlert;
    final clientAlerts = _clientAlerts;
    if (officeAlert == null && clientAlerts.isEmpty) return;
    final df = DateFormat('d MMMM yyyy', 'ar');
    final firstClientAlert =
        clientAlerts.isNotEmpty ? clientAlerts.first : null;
    final cardTitle = officeAlert?.title ?? firstClientAlert!.title;
    final cardBody = officeAlert?.body ?? firstClientAlert!.body;
    final cardDate = officeAlert?.endAt ?? firstClientAlert!.endDate;
    final cardIcon = officeAlert != null
        ? Icons.warning_amber_rounded
        : (firstClientAlert!.isExpiredToday
            ? Icons.error_outline_rounded
            : Icons.notifications_active_outlined);
    final cardIconColor = officeAlert != null
        ? const Color(0xFFF59E0B)
        : (firstClientAlert!.isExpiredToday
            ? const Color(0xFFDC2626)
            : const Color(0xFF0D9488));
    final cardBgColor = officeAlert != null
        ? const Color(0xFFFFFBEB)
        : (firstClientAlert!.isExpiredToday
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFEFF6FF));
    final cardBorderColor = officeAlert != null
        ? const Color(0xFFF59E0B).withOpacity(0.45)
        : (firstClientAlert!.isExpiredToday
            ? const Color(0xFFFECACA)
            : const Color(0xFFBFDBFE));
    final cardDateLabel = officeAlert != null
        ? 'تاريخ انتهاء اشتراك المكتب: ${df.format(cardDate)}'
        : 'تاريخ نهاية الاشتراك: ${df.format(cardDate)}';
    final totalAlerts = (officeAlert == null ? 0 : 1) + clientAlerts.length;
    final extraAlertsCount = totalAlerts > 1 ? totalAlerts - 1 : 0;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.notifications_active,
                    color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Text('التنبيهات',
                    style: GoogleFonts.cairo(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(cardIcon, color: cardIconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cardTitle,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(cardBody,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF111827))),
                              const SizedBox(height: 8),
                              Text(cardDateLabel,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6B7280))),
                            ]),
                      ),
                    ]),
              ),
              if (extraAlertsCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'يوجد $extraAlertsCount تنبيه إضافي. سيتم عرضها تباعًا عند تحديث الحالة.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: Text('إغلاق',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48, // ï¿½.Ø³Ø§Ø­Ø© Ø¶ØºØ· ï¿½.Ø±ï¿½SØ­Ø© Ø¯Ø§Ø®ï¿½" ا�"ï¿½? AppBar
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior
            .opaque, // Ø£ï¿½S Ø¶ØºØ·Ø© Ø¯Ø§Ø®ï¿½" ا�"ï¿½? 48x48 Øªï¿½?Ø­Ø³Ø¨
        onTap: _openSheet,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
            ),
            if (_badge > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.0),
                  ),
                  child: Text(
                    '$_badge',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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

/// ======================== 1) OfficeHomePage ========================
class OfficeHomePage extends StatefulWidget {
  const OfficeHomePage({super.key});

  @override
  State<OfficeHomePage> createState() => _OfficeHomePageState();
}

class _OfficeHomePageState extends State<OfficeHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // ï¿½Y'^ �?ذا ا�"جد�Sد

  bool _online = true; // �?�" �S�^جد اتصا�" با�"إ�?تر�?ت�Y
  bool _maybeWeak = false; // �?�" ا�"اتصا�" ضع�Sف/غ�Sر �.ست�,ر�Y
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    _startConnectivityWatch();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  void _startConnectivityWatch() {
    // فحص أ�^�"�S
    _checkNow();

    // �.را�,بة أ�S تغ�S�Sر ف�S حا�"ة ا�"شب�fة (�^ا�S فا�S / ب�Sا�?ات / بد�^�? شب�fة)
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _updateFromResult(results);
    });
  }

  Future<void> _checkNow() async {
    final results = await Connectivity().checkConnectivity();
    await _updateFromResult(results);
  }

  Future<void> _updateFromResult(List<ConnectivityResult> results) async {
    // �?�" �S�^جد أ�S �?�^ع اتصا�" غ�Sر none �Y
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    bool online = hasNetwork;
    bool weak = false;

    if (hasNetwork) {
      // �?حا�^�" �?ع�.�" ط�"ب بس�Sط �"�"تأ�fد �.�? أ�? ا�"إ�?تر�?ت فع�"ا�< شغ�'Ø§ï¿½"
      try {
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
        weak = false;
      } catch (_) {
        // �S�^جد شب�fة (�^ا�S فا�S / ب�Sا�?ات) �"ï¿½fï¿½? ï¿½SØ¨Ø¯ï¿½^ Ø§ï¿½"اتصا�" Ø¶Ø¹ï¿½SÙ Ø£ï¿½^ Øºï¿½SØ± ï¿½.Ø³Øªï¿½,Ø±
        online = true; // ï¿½?Ø¹ØªØ¨Ø±ï¿½? ï¿½.ØªØµï¿½" �"ï¿½fï¿½? Ø¶Ø¹ï¿½SÙ
        weak = true;
      }
    } else {
      // ï¿½"ا �S�^جد �^ا�S فا�S �^�"Ø§ Ø¨ï¿½SØ§ï¿½?Ø§Øª
      online = false;
      weak = false;
    }

    if (!mounted) return;
    setState(() {
      _online = online;
      _maybeWeak = weak;
    });
  }

  Future<bool> _onWillPop() async {
    // ï¿½"�^ ا�"ï¿½,Ø§Ø¦ï¿½.Ø© Ø§ï¿½"جا�?ب�Sة �.فت�^حة�O �?�,ف�"ï¿½?Ø§ Ùï¿½,Ø· ï¿½^ï¿½"ا �?عرض �?افذة ا�"Ø®Ø±ï¿½^Ø¬
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop(); // Ø¥Øºï¿½"ا�, ا�"Ø¯Ø±Ø¬
      return false; // ï¿½"ا �?خرج �.�? ا�"Ø´Ø§Ø´Ø©
    }
    final bool shouldExit = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الخروج',
      message: 'هل أنت متأكد من رغبتك في الخروج من التطبيق؟',
      confirmLabel: 'تأكيد الخروج',
      cancelLabel: 'إلغاء',
    );

    if (shouldExit) {
      // ï¿½o. Ø¥Øºï¿½"ا�, ا�"ØªØ·Ø¨ï¿½Sï¿½, ï¿½.Ø¨Ø§Ø´Ø±Ø© (ï¿½.Ø«ï¿½" "ØªØ£ï¿½fï¿½SØ¯ Ø§ï¿½"خر�^ج" Ø§ï¿½"ح�,�S�,�S)
      SystemNavigator.pop();
      // �?رج�'ع false حت�? �"Ø§ ï¿½SØ­Ø§ï¿½^ï¿½" Navigator �Sع�.�" pop ï¿½"ر�^ت آخر
      return false;
    }

    // ا�"ï¿½.Ø³ØªØ®Ø¯ï¿½. ï¿½"غ�? أ�^ رجع �"ï¿½"خ�"Ù ï¿½.ï¿½? Ø§ï¿½"د�Sا�"ï¿½^Ø¬
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop, // ï¿½Y'^ �?�?ا ربط�?ا زر ا�"رج�^ع
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Stack(
          children: [
            // ا�"�^اج�?ة ا�"عاد�Sة �f�.ا �fا�?ت
            Scaffold(
              key: _scaffoldKey, // �Y'^ Ø£Ø¶Ù ï¿½?Ø°Ø§ Ø§ï¿½"سطر
              backgroundColor: Colors.transparent,
              drawer: const OfficeSideDrawer(),
              appBar: AppBar(
                elevation: 0,
                centerTitle: true,
                leading: Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'القائمة',
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                title: Text(
                  'لوحة المكتب',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: 6),
                    child: OfficeNotificationsBell(),
                  ),
                ],
              ),
              body: const OfficeClientsPage(),
            ),

            // �YY� ف�S حا�"Ø© Ø§ï¿½"اتصا�" Ø§ï¿½"ضع�Sف �?' شر�Sط تحذ�Sر ف�,ط بد�^�? حجب �fا�.�"
            if (_maybeWeak && _online) _buildWeakBanner(context),

            const AiChatFloatingIcon(isOfficeMode: true),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBlocker(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false, // ï¿½?ï¿½.ï¿½?Ø¹ Ø£ï¿½S ï¿½"�.س تحت ا�"Ø·Ø¨ï¿½,Ø©
        child: Container(
          color: Colors.black.withOpacity(0.70),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'لا يوجد اتصال بالإنترنت',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'لا يمكن استخدام لوحة المكتب بدون إنترنت.\n'
                'تحقق من الشبكة ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeakBanner(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.network_check_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الاتصال بالإنترنت ضعيف، قد تفشل بعض العمليات.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ï¿½?ï¿½.ï¿½^Ø°Ø¬ Ø¹Ø±Ø¶ Ø¯Ø§Ø®ï¿½"�S �.�^ح�'د
class _ClientItem {
  final String name;
  final String email;
  final String phone;
  final String notes;
  final String
      clientUid; // �,د �S�f�^�? localUid �"ï¿½"ع�.�"Ø§Ø¡ Ø§ï¿½"�.ح�"ï¿½Sï¿½Sï¿½?
  final DateTime? createdAt;
  final bool isLocal;
  final bool subscriptionEnabled;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final double? subscriptionPrice;
  final int subscriptionReminderDays;
  final bool accessBlocked;
  final String? tempId; // ï¿½"�.ح�^ ا�"Ø¹ï¿½.ï¿½Sï¿½" ا�"ï¿½.Ø­ï¿½"�S إ�? رغبت
  _ClientItem({
    required this.name,
    required this.email,
    required this.phone,
    required this.notes,
    required this.clientUid,
    required this.createdAt,
    required this.isLocal,
    this.tempId,
    required this.subscriptionEnabled,
    required this.subscriptionStartDate,
    required this.subscriptionEndDate,
    required this.subscriptionPrice,
    required this.subscriptionReminderDays,
    required this.accessBlocked,
  });
}

class _CreatedOfficeClientResult {
  final String clientUid;
  final String clientName;

  const _CreatedOfficeClientResult({
    required this.clientUid,
    required this.clientName,
  });
}

/// ======================== 2) OfficeClientsPage ========================
class OfficeClientsPage extends StatefulWidget {
  const OfficeClientsPage({super.key});

  @override
  State<OfficeClientsPage> createState() => _OfficeClientsPageState();
}

class _OfficeClientsPageState extends State<OfficeClientsPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _officeSub;

  // �Y'? �fاش �"ï¿½.ï¿½?Ø¹ Ùï¿½"اش ا�"Ø´Ø§Ø´Ø© Ø¹ï¿½?Ø¯ Ø§ï¿½"ا�?تحا�"
  String? _officeUidAtStart;
  String? _requestedScopeUid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _clientsStreamCache;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  User? get _me => FirebaseAuth.instance.currentUser;
  bool _impersonating =
      false; // Ø§ï¿½"�"ï¿½^Ø¯Ø± ï¿½SØ¸ï¿½?Ø± Ùï¿½,Ø· Ø¹ï¿½?Ø¯ Ø§ï¿½"ا�?تحا�"

  // ï¿½o. Ø³Ø¬ï¿½" ترت�Sب ثابت �.ح�"ï¿½Sï¿½<Ø§ (ï¿½SØ¹Øªï¿½.Ø¯ Ø¹ï¿½"�? ا�"Ø¨Ø±ï¿½SØ¯) ï¿½?" �Sحفظ ا�"ï¿½.ï¿½^Ø§Ø¶Ø¹
  static const _orderBoxLogical = '_officeClientsOrder';
  Map<String, int> _orderMap = {};
  int _orderLast = 0;
  bool _orderLoaded = false;

  // ï¿½o. Ø®Ø±ï¿½SØ·Ø© ï¿½"ح�"ï¿½' UID ا�"سحاب�S �"ع�.�"اء �.ح�"�S�S�? عبر ا�"بر�Sد (�.حج�^زة �"�"ت�^س�'Ø¹ ï¿½"اح�,�<ا)
  final Map<String, String> _resolvedUidByEmail = {};

  // �?خز�? آخر �.ج�.�^عة Pending �"ï¿½.Ø¹Ø±ÙØ© Ø§ï¿½"جد�Sد �.�?�?ا (�.حج�^زة �"ï¿½"ت�^س�'ع �"Ø§Ø­ï¿½,ï¿½<Ø§)
  final Set<String> _lastPendingEmails = {};

  // ==== ï¿½.Ø±Ø§ï¿½,Ø¨Ø© Ø§ï¿½"اتصا�" (Ø§Ø®Øªï¿½SØ§Ø±ï¿½S ï¿½"�"Ø¨Ùï¿½?ï¿½? Ø§ï¿½"داخ�"ï¿½SØ©) ====
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // ï¿½o. Ø­Ø°Ù ï¿½.Ø­ï¿½"�S �.ُجد�^�": Ø¥Ø®ÙØ§Ø¤ï¿½?ï¿½. Ùï¿½^Ø±ï¿½<Ø§ ï¿½.ï¿½? Ø§ï¿½"�^اج�?ة
  final Set<String> _locallyDeleted = {};
  int _enterTraceSeq = 0;
  bool _forcedBlockedHandled = false;

  void _traceEnter(String message) {
    debugPrint('[EnterTrace][OfficeClients] $message');
  }

  Future<void> _forceBlockedAndExit({
    required String msg,
    String reason = '',
  }) async {
    final intentionalLogout =
        await OfficeClientGuard.isIntentionalLogoutInProgress();
    if (intentionalLogout) {
      _traceEnter('force-blocked skipped intentional-logout reason=$reason');
      return;
    }

    if (_forcedBlockedHandled) {
      _traceEnter('force-blocked skip duplicate reason=$reason');
      return;
    }
    _forcedBlockedHandled = true;
    _traceEnter('force-blocked start reason=$reason msg=$msg');

    await _officeSub?.cancel();
    _officeSub = null;
    await _connSub?.cancel();
    _connSub = null;

    try {
      final isOfficeClient = await OfficeClientGuard.isOfficeClient();
      await OfficeClientGuard.markOfficeBlocked(
        true,
        email: FirebaseAuth.instance.currentUser?.email,
        uid: FirebaseAuth.instance.currentUser?.uid,
      );
      _traceEnter(
        'force-blocked classification reason=$reason isOfficeClient=$isOfficeClient savedLocalBlocked=true',
      );
    } catch (e) {
      _traceEnter('force-blocked classification error reason=$reason err=$e');
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('last_login_email');
      await sp.remove('last_login_uid');
      await sp.remove('last_login_role');
      await sp.remove('last_login_offline');
    } catch (_) {}

    if (Hive.isBoxOpen('sessionBox')) {
      final session = Hive.box('sessionBox');
      await session.put('loggedIn', false);
    }

    scope.clearFixedUid();
    await OfficeClientGuard.refreshFromLocal();

    if (!mounted) return;

    await CustomConfirmDialog.show(
      context: context,
      title: 'تم إيقاف الحساب',
      message: msg,
      forceBlockedDialog: true,
      confirmLabel: 'خروج',
    );

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  void initState() {
    super.initState();

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final scopedUid = scope.effectiveUid().trim();
    final normalizedScoped = scopedUid == 'guest' ? '' : scopedUid;
    if (authUid.isNotEmpty &&
        normalizedScoped.isNotEmpty &&
        normalizedScoped != authUid) {
      // Start safely with auth uid to avoid unauthorized listeners on stale scope.
      _requestedScopeUid = normalizedScoped;
      _officeUidAtStart = authUid;
    } else {
      _officeUidAtStart =
          normalizedScoped.isNotEmpty ? normalizedScoped : authUid;
    }

    _clientsStreamCache = _buildStreamFor(_officeUidAtStart);
    _traceEnter(
      'init authUid=$authUid scopedUid=$scopedUid officeUidAtStart=${_officeUidAtStart ?? ''} requestedScope=${_requestedScopeUid ?? ''}',
    );
    unawaited(_normalizeOfficeScope());
    unawaited(OfflineSyncService.instance.tryFlushAllIfOnline());
    if (_requestedScopeUid == null || _requestedScopeUid!.isEmpty) {
      _watchOfficeSubscription(); // �Y'^ �.ا�"ï¿½f Ø§ï¿½"�.�fتب: ابدأ ا�"ï¿½.Ø±Ø§ï¿½,Ø¨Ø© ï¿½.Ø¨Ø§Ø´Ø±Ø©
    } else {
      _traceEnter(
        'watch-office-subscription deferred until scope-normalized requestedScope=${_requestedScopeUid ?? ''} authUid=$authUid',
      );
    }
    _loadOrderBox(); // ØªØ­ï¿½.ï¿½Sï¿½" سج�" Ø§ï¿½"ترت�Sب
    _startConnectivityWatch(); // �.را�,بة ا�"Ø§ØªØµØ§ï¿½" (�"Ø§ ØªØ­Ø¬Ø¨ Ø§ï¿½"�^اج�?ة �.ط�"ï¿½,ï¿½<Ø§)
  }

  Future<void> _normalizeOfficeScope() async {
    final user = FirebaseAuth.instance.currentUser;
    final authUid = user?.uid ?? '';
    final candidateUid = (_requestedScopeUid ?? _officeUidAtStart ?? '').trim();
    _traceEnter(
      'normalize-scope start authUid=$authUid candidateUid=$candidateUid requestedScope=${_requestedScopeUid ?? ''}',
    );
    if (authUid.isEmpty) return;

    var claimOfficeId = '';
    var docOfficeId = '';
    var role = '';
    try {
      final token = await user?.getIdTokenResult();
      final claims = token?.claims ?? const <String, dynamic>{};
      claimOfficeId =
          (claims['officeId'] ?? claims['office_id'] ?? '').toString().trim();
      role = (claims['role'] ?? '').toString().toLowerCase().trim();
    } catch (_) {}
    try {
      final um = await _safeReadDocData(
        FirebaseFirestore.instance.collection('users').doc(authUid),
        traceLabel: 'normalize-scope users/$authUid',
      );
      docOfficeId = (um['officeId'] ?? um['office_id'] ?? '').toString().trim();
    } catch (_) {}

    final isOfficeStaff =
        role == 'office_staff' || role == 'office-user' || role == 'staff';
    final allowScoped = candidateUid.isNotEmpty &&
        candidateUid != authUid &&
        isOfficeStaff &&
        ((claimOfficeId.isNotEmpty && claimOfficeId == candidateUid) ||
            (docOfficeId.isNotEmpty && docOfficeId == candidateUid));

    if (allowScoped) {
      _officeUidAtStart = candidateUid;
      scope.setFixedUid(candidateUid);
      _clientsStreamCache = _buildStreamFor(candidateUid);
      await _officeSub?.cancel();
      _watchOfficeSubscription();
      unawaited(OfflineSyncService.instance.tryFlushAllIfOnline());
      _requestedScopeUid = null;
      _traceEnter('normalize-scope use-candidate scopedUid=$candidateUid');
      if (mounted) setState(() {});
      return;
    }

    // Fallback to authenticated owner workspace to avoid stale office UID.
    _officeUidAtStart = authUid;
    scope.setFixedUid(authUid);
    _clientsStreamCache = _buildStreamFor(authUid);
    await _officeSub?.cancel();
    _watchOfficeSubscription();
    unawaited(OfflineSyncService.instance.tryFlushAllIfOnline());
    _requestedScopeUid = null;
    _traceEnter('normalize-scope fallback-auth authUid=$authUid');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _officeSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  // ===== Øµï¿½?Ø§Ø¯ï¿½Sï¿½,/Ø³ØªØ±ï¿½Sï¿½. =====
  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildStreamFor(String? uid) {
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('offices')
        .doc(uid)
        .collection('clients')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);
  }

  void _watchOfficeSubscription() {
    final watchUid =
        _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid;
    if (watchUid == null || watchUid.isEmpty) return;
    _traceEnter('watch-office-subscription start watchUid=$watchUid');

    _officeSub = FirebaseFirestore.instance
        .collection('users')
        .doc(watchUid)
        .snapshots()
        .listen((doc) async {
      // ï¿½?Ø³ØªØ®Ø¯ï¿½. Ùï¿½,Ø· Ø¢Ø®Ø± ï¿½.Ø²Ø§ï¿½.ï¿½?Ø© Ø­ï¿½,ï¿½Sï¿½,ï¿½SØ© ï¿½.ï¿½? Ø§ï¿½"س�Sرفر
      if (doc.metadata.isFromCache) {
        _traceEnter(
          'watch-office-subscription cache-snapshot ignored watchUid=$watchUid',
        );
        return;
      }
      if (!doc.exists) {
        _traceEnter('watch-office-subscription missing-doc watchUid=$watchUid');
        return;
      }

      _traceEnter(
        'watch-office-subscription server-snapshot watchUid=$watchUid pendingWrites=${doc.metadata.hasPendingWrites}',
      );

      final m = doc.data() ?? {};

      // 1️�f� حا�"Ø© Ø§ï¿½"حظر (�?ذ�? دائ�.�<ا تُخرج ا�"ï¿½.ï¿½fØªØ¨ Ùï¿½^Ø±ï¿½<Ø§)
      final blocked = (m['blocked'] ?? false) == true;
      final preciseExpired = SubscriptionExpiry.isExpired(m);

      // 2ï¸ï¿½fï¿½ ï¿½?ï¿½,Ø±Ø£ end_date_ksa ï¿½fï¿½?Øµ ï¿½.Ø«ï¿½" "2025-01-29"
      DateTime? inclusiveEndKsa;
      final endKsaText = (m['end_date_ksa'] as String?)?.trim();
      if (endKsaText != null && endKsaText.isNotEmpty) {
        final parts = endKsaText.split('-'); // ص�Sغة yyyy-MM-dd
        if (parts.length >= 3) {
          final y = int.tryParse(parts[0]);
          final mo = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && mo != null && d != null) {
            // �?ذا �S�.ث�" "ا�"ï¿½Sï¿½^ï¿½. Ø§ï¿½"أخ�Sر" Ùï¿½S Ø§ï¿½"سع�^د�Sة
            inclusiveEndKsa = DateTime(y, mo, d);
          }
        }
      }

      // 3️�f� �?حسب "ØªØ§Ø±ï¿½SØ® Ø§ï¿½"�S�^�." Ø¨Øªï¿½^ï¿½,ï¿½SØª Ø§ï¿½"سع�^د�Sة
      final nowKsa = KsaTime.now();
      final todayKsa = DateTime(nowKsa.year, nowKsa.month, nowKsa.day);

      // 4️�f� �.�?ت�?�S ف�,ط إذا �fا�? ا�"ï¿½Sï¿½^ï¿½. Ùï¿½S Ø§ï¿½"سع�^د�Sة بعد ا�"ï¿½Sï¿½^ï¿½. Ø§ï¿½"أخ�Sر
      // 4️�f� �.�?ت�?�S ف�,ط إذا �fا�? ا�"ï¿½Sï¿½^ï¿½. Ùï¿½S Ø§ï¿½"سع�^د�Sة بعد ا�"ï¿½Sï¿½^ï¿½. Ø§ï¿½"أخ�Sر
      bool expired = false;
      if (inclusiveEndKsa != null) {
        // end_date_ksa = 29 �?' شغا�" Ø·ï¿½^ï¿½" �S�^�. 29�O �^�S�?ت�?�S �.�? بدا�Sة �S�^�. 30
        expired = todayKsa.isAfter(inclusiveEndKsa);
      } else {
        // �Y"ï¿½ ï¿½.Ø³Ø§Ø± Ø§Ø­Øªï¿½SØ§Ø·ï¿½S ï¿½,Ø¯ï¿½Sï¿½. ï¿½"�^ end_date_ksa غ�Sر �.�^ج�^د (حسابات �,د�S�.ة)
        DateTime? end;
        final v = m['subscription_end'];
        if (v is Timestamp) {
          end = v.toDate();
        } else if (v is DateTime) {
          end = v;
        } else if (v is String) {
          end = DateTime.tryParse(v);
        }

        if (end != null) {
          // �o. �?ح�^�" subscription_end Ø¥ï¿½"�? "ØªØ§Ø±ï¿½SØ® Ùï¿½,Ø·" بت�^�,�Sت ا�"Ø³Ø¹ï¿½^Ø¯ï¿½SØ©
          final endUtc = end.toUtc();
          final endKsa = endUtc.add(const Duration(hours: 3));
          final endDateKsa = DateTime(endKsa.year, endKsa.month, endKsa.day);

          // ï¿½Y'? �?فس �.�?ط�, end_date_ksa:
          // endDateKsa = 29 �?' Ø´ØºØ§ï¿½" ط�^�" ï¿½Sï¿½^ï¿½. 29ï¿½O ï¿½^ï¿½Sï¿½?Øªï¿½?ï¿½S ï¿½.ï¿½? Ø¨Ø¯Ø§ï¿½SØ© ï¿½Sï¿½^ï¿½. 30
          expired = todayKsa.isAfter(endDateKsa);
        }
      }

      // ï¿½sï¿½ï¸ ï¿½?ï¿½?Ø§ Ø§ï¿½"تعط�S�" Ùï¿½S Ø´Ø§Ø´Ø© Ø§ï¿½"�.�fتب �?عت�.د�? ف�,ط ع�"ï¿½?:
      //  - blocked (ï¿½.ï¿½^ï¿½,ï¿½^Ù ï¿½.ï¿½? Ø§ï¿½"إدارة)
      //  - expired (تجا�^ز ا�"ï¿½Sï¿½^ï¿½. Ø§ï¿½"أخ�Sر ف�S ا�"Ø³Ø¹ï¿½^Ø¯ï¿½SØ©)
      if (blocked || preciseExpired) {
        _traceEnter(
          'watch-office-subscription enforcement blocked=$blocked expired=$preciseExpired legacyExpired=$expired watchUid=$watchUid end_date_ksa=${m['end_date_ksa'] ?? ''}',
        );
        await _officeSub?.cancel();
        _officeSub = null;

        if (!mounted) return;
        if (blocked) {
          await _forceBlockedAndExit(
            msg: 'تم إيقاف الحساب من الإدارة. لا يمكن متابعة استخدام التطبيق.',
            reason: 'office-sub-blocked',
          );
          return;
        }

        final msg = 'انتهى اشتراك المكتب (وفق آخر مزامنة مباشرة).';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));

        // ï¿½Y"� تسج�S�" Ø®Ø±ï¿½^Ø¬ ï¿½fØ§ï¿½.ï¿½" �.�? حساب ا�"ï¿½.ï¿½fØªØ¨
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}

        // ï¿½Yï¿½ï¿½ ï¿½.Ø³Ø­ Ø¨ï¿½SØ§ï¿½?Ø§Øª Ø¢Ø®Ø± ï¿½.Ø³ØªØ®Ø¯ï¿½. ï¿½.Ø­Ùï¿½^Ø¸ ï¿½"�"ï¿½? auto-login
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.remove('last_login_email');
          await sp.remove('last_login_uid');
          await sp.remove('last_login_role');
          await sp.remove('last_login_offline');
        } catch (_) {}

        // ï¿½Yï¿½ï¿½ ØªØ­Ø¯ï¿½SØ« sessionBox
        if (Hive.isBoxOpen('sessionBox')) {
          final session = Hive.box('sessionBox');
          await session.put('loggedIn', false);
          await session.put('isOfficeClient',
              false); // Ø®Ø±ï¿½^Ø¬ ï¿½.ï¿½? ï¿½^Ø¶Ø¹ "ع�.�S�" ï¿½.ï¿½fØªØ¨"
        }

        // �Y'? ا�.سح UID ا�"Ø§ï¿½?ØªØ­Ø§ï¿½" �.�? user_scope
        scope.clearFixedUid();

        // �Y'? حد�'ث حارس ع�.�S�" Ø§ï¿½"�.�fتب
        await OfficeClientGuard.refreshFromLocal();

        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 150));
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }, onError: (Object error, StackTrace st) async {
      final code = error is FirebaseException ? error.code : '';
      _traceEnter(
          'office-sub onError code=$code err=$error watchUid=$watchUid');
      if (code == 'permission-denied') {
        final intentionalLogout =
            await OfficeClientGuard.isIntentionalLogoutInProgress();
        if (intentionalLogout || FirebaseAuth.instance.currentUser == null) {
          _traceEnter(
            'office-sub permission-denied ignored intentional-logout/signout watchUid=$watchUid',
          );
          return;
        }
        await _forceBlockedAndExit(
          msg:
              'تم إيقاف الحساب أو سحب الصلاحية من هذا الجهاز. لا يمكن متابعة استخدام التطبيق.',
          reason: 'office-sub-permission-denied',
        );
        _traceEnter(
          'office-sub enforced blocked بسبب permission-denied watchUid=$watchUid',
        );
      }
    });
  }

  // �o. ترج�'ع دائ�.�<ا �?فس ا�"Ø³ØªØ±ï¿½Sï¿½. Ø§ï¿½"�.خز�'�? أث�?اء ا�"Ø§ï¿½?ØªØ­Ø§ï¿½" �"ï¿½.ï¿½?Ø¹ Ø§ï¿½"ف�"Ø§Ø´
  Stream<QuerySnapshot<Map<String, dynamic>>>? _clientsStream() {
    // ï¿½"�^ �?ح�? ف�S �^ضع "Ø§ï¿½?ØªØ­Ø§ï¿½"" Ø¹ï¿½.ï¿½Sï¿½" �.�? داخ�" Ø§ï¿½"�.�fتب�O �"Ø§ ØªØºï¿½Sï¿½'ر ا�"�? stream
    if (_impersonating) return _clientsStreamCache;

    // �Y'^ Ø§Ø³ØªØ®Ø¯ï¿½. Ø§ï¿½"�? uid ا�"ÙØ¹ï¿½'ا�" (�.�? user_scope)
    final uid = scope.effectiveUid();

    // �"�^ �.ا ع�?د�?ا �.ستخد�. فع�'Ø§ï¿½" (guest) �?حافظ ع�"ï¿½? Ø§ï¿½"�? stream ا�"ï¿½,Ø¯ï¿½Sï¿½. Ø¥ï¿½? ï¿½^Ø¬Ø¯
    if (uid == 'guest') {
      return _clientsStreamCache;
    }

    // ï¿½"�^ تغ�S�'ر ا�"ï¿½? uid (Ø¯Ø®ï¿½^ï¿½" �.�fتب جد�Sد أ�^ ع�.�S�" Ø¬Ø¯ï¿½SØ¯) Ø§Ø¨ï¿½?Ù stream Ø¬Ø¯ï¿½SØ¯
    if (uid != _officeUidAtStart) {
      _officeUidAtStart = uid;
      _clientsStreamCache = _buildStreamFor(uid);
    }

    return _clientsStreamCache;
  }

  // ===== ØªØ±Øªï¿½SØ¨ ï¿½.Ø­ï¿½"�S =====
  Future<void> _loadOrderBox() async {
    final name = scope.boxName(_orderBoxLogical);
    final box =
        Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
    final raw = (box.get('map') as Map?) ?? {};
    final map = <String, int>{};
    for (final e in raw.entries) {
      final k = e.key.toString();
      final v =
          (e.value is int) ? e.value as int : int.tryParse('${e.value}') ?? 0;
      map[k] = v;
    }
    final last = (box.get('last') as int?) ??
        (map.values.isEmpty ? 0 : map.values.reduce((a, b) => math.max(a, b)));
    setState(() {
      _orderMap = map;
      _orderLast = last;
      _orderLoaded = true;
    });
  }

  void _saveOrderBoxDebounced() {
    Future.microtask(() async {
      final name = scope.boxName(_orderBoxLogical);
      final box =
          Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
      await box.put('map', _orderMap);
      await box.put('last', _orderLast);
    });
  }

  int _ensureIndexForEmail(String email) {
    final key = email.trim().toLowerCase();
    if (key.isEmpty) {
      _orderLast += 1;
      _saveOrderBoxDebounced();
      return _orderLast;
    }
    final ex = _orderMap[key];
    if (ex != null) return ex;
    _orderLast += 1;
    _orderMap[key] = _orderLast;
    _saveOrderBoxDebounced();
    return _orderLast;
  }

  void _startConnectivityWatch() {
    _connSub?.cancel();
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) return;
      unawaited(OfflineSyncService.instance.tryFlushAllIfOnline());
    });
  }

  // ===== أحداث �^اج�?ة =====
  Future<void> _onAdd() async {
    final online = await _hasInternetConnection();
    if (!online) {
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب لإضافة عميل',
        message:
            'لا بد من فتح الإنترنت لإضافة عميل جديد، لأن الإضافة مرتبطة بالسيرفر مباشرة.',
      );
      return;
    }

    final limitDecision = await PackageLimitService.canAddOfficeClient();
    if (!limitDecision.allowed) {
      if (!mounted) return;
      _showSnack(
        context,
        limitDecision.message ??
            'لا يمكن إضافة عميل جديد، لقد وصلت إلى الحد الأقصى المسموح.',
      );
      return;
    }

    final created = await showDialog<_CreatedOfficeClientResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => const AddOfficeClientDialog(),
    );
    if (!mounted) return;
    if (created == null) return;

    final officeUid =
        _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (officeUid.isNotEmpty) {
      _clientsStreamCache = _buildStreamFor(officeUid);
    }
    setState(() {});
    await _enterManageClient(created.clientUid, created.clientName);
  }

  // �o. تأ�f�Sد ا�"Ø­Ø°Ù Ø¯Ø§Ø¦ï¿½.ï¿½<Ø§ (Ø³ï¿½^Ø§Ø¡ ï¿½.Ø­ï¿½"�S أ�^ سحاب�S)
  Future<void> _confirmDelete({
    required bool isLocal,
    required String? tempIdForLocal,
    required String clientUidOrLocal,
    required String displayName,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dctx) => DeleteClientDialog(
        clientName: displayName,
        onConfirm: () => Navigator.pop(dctx, true),
        onCancel: () => Navigator.pop(dctx, false),
      ),
    );
    if (ok != true) return;

    if (isLocal && (tempIdForLocal ?? '').isNotEmpty) {
      try {
        await OfflineSyncService.instance
            .removePendingOfficeCreateByTempId(tempIdForLocal!);
        if (!mounted) return;
        setState(() {});
        _showSnack(context, 'تم الحذف بنجاح.');
      } catch (e) {
        _showSnack(context, 'تعذر حذف العميل المحلي: $e');
      }
      return;
    }

    // سحاب�S: صف�' ا�"Ø­Ø°Ù Ø£ï¿½^Ùï¿½"ا�S�? �^أخفِ �.�? ا�"ï¿½^Ø§Ø¬ï¿½?Ø© Ùï¿½^Ø±ï¿½<Ø§
    try {
      await OfflineSyncService.instance
          .enqueueDeleteOfficeClient(clientUidOrLocal);
      _locallyDeleted.add(clientUidOrLocal);
      if (!mounted) return;
      setState(() {});
      _showSnack(context, 'تم الحذف بنجاح.');
    } catch (e) {
      _showSnack(context, 'تعذر جدولة الحذف: $e');
    }
  }

  Future<void> _onDelete(String clientUid, String clientName) async {
    // Ø§Ø­ØªÙÙØ¸ Ø¨ï¿½?Ø§ ï¿½"�"Ø§Ø³ØªØ®Ø¯Ø§ï¿½. Ø§ï¿½"داخ�"ï¿½S Ø¥ï¿½? Ø§Ø­ØªØ¬Øª (ï¿½?Ø³ØªØ¹ï¿½.ï¿½" _confirmDelete ا�"Ø¢ï¿½?)
    await _confirmDelete(
      isLocal: false,
      tempIdForLocal: null,
      clientUidOrLocal: clientUid,
      displayName: clientName,
    );
  }

  Future<void> _openEdit(
    String clientUid, {
    required String name,
    required String email,
    String? phone,
    String? notes,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => EditOfficeClientDialog(
        clientUid: clientUid,
        initialName: name,
        initialEmail: email,
        initialPhone: phone ?? '',
        initialNotes: notes ?? '',
      ),
    );
    if (!mounted) return;

    // ØªØ­Ø¯ï¿½SØ« Ùï¿½^Ø±ï¿½S ï¿½"تطب�S�, ا�"ØªØ¹Ø¯ï¿½Sï¿½"ات ا�"ï¿½.Ø­ï¿½"�Sة ع�"ï¿½? Ø§ï¿½"بطا�,ات
    setState(() {});
  }

  void _openAccess(String clientUid, String email, bool initialBlocked) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => ClientAccessDialog(
        clientEmail: email,
        clientUid: clientUid,
        initialBlocked: initialBlocked,
      ),
    );
  }

  // �o. زر ا�"Øµï¿½"اح�Sات �Sفتح دائ�.�<ا حت�? بد�^�? �?ت (�"Ø§ Ø´Ø±ï¿½^Ø·)
  void _handleAccessPressed({
    required bool isLocalItem,
    required String email,
    required String clientUidOrLocal,
    required bool initialBlocked,
  }) {
    _openAccess(clientUidOrLocal, email, initialBlocked);
  }

  // Ø§ï¿½"جرس ا�"Ø­ï¿½,ï¿½Sï¿½,ï¿½S ï¿½"�"Ø¹ï¿½.ï¿½"اء ا�"Ø³Ø­Ø§Ø¨ï¿½Sï¿½Sï¿½?
  // Ø§ï¿½"جرس ا�"Ø­ï¿½,ï¿½Sï¿½,ï¿½S ï¿½"�"Ø¹ï¿½.ï¿½"اء ا�"Ø³Ø­Ø§Ø¨ï¿½Sï¿½Sï¿½? ï¿½?" �.رب�^ط بعدد ا�"Øªï¿½?Ø¨ï¿½Sï¿½?Ø§Øª Ùï¿½S ØªØ·Ø¨ï¿½Sï¿½, Ø§ï¿½"ع�.�S�"
  Widget _NotifBell(String clientUid) {
    final officeUid =
        _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid;
    if (officeUid == null || officeUid.isEmpty) return _NotifBellPlaceholder();

    final docStream = FirebaseFirestore.instance
        .collection('offices')
        .doc(officeUid)
        .collection('clients')
        .doc(clientUid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (ctx, snap) {
        int count = 0;

        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          final raw = data['notificationsCount'] ?? data['notifications_count'];
          if (raw is int) {
            count = raw;
          } else if (raw is num) {
            count = raw.toInt();
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                // Ø­Ø§ï¿½"�S�<ا �.جرد ت�"ï¿½.ï¿½SØ­ï¿½O ï¿½"اح�,�<ا �S�.�f�?�?ا فتح تطب�S�, ا�"Ø¹ï¿½.ï¿½Sï¿½" �.باشرة ع�"ï¿½? Ø´Ø§Ø´Ø© Ø§ï¿½"ت�?ب�S�?ات
                _showSnack(
                    ctx, 'اضغط دخول ثم اضغط على "التنبيهات" لمشاهدة التفاصيل.');
              },
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            // �o. ا�"Ø¨Ø§Ø¯Ø¬ ï¿½SØ¸ï¿½?Ø± Ø¯Ø§Ø¦ï¿½.ï¿½<Ø§ Ø­Øªï¿½? ï¿½"�^ count = 0
            Positioned(
              top: 3.8,
              right: -6,
              child: IgnorePointer(
                // �o. �Sخ�"ï¿½S Ø§ï¿½"بادج �"Ø§ ï¿½SØ³Øªï¿½,Ø¨ï¿½" ا�"ï¿½"�.س
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Placeholder �"ï¿½"ع�.�S�" Ø§ï¿½"�.ح�"ï¿½S (ï¿½SØ¸ï¿½?Ø± Ø£ï¿½Sï¿½,ï¿½^ï¿½?Ø© Ùï¿½,Ø·)
  Widget _NotifBellPlaceholder() {
    return const Padding(
      padding: EdgeInsets.all(6.0),
      child: Opacity(
        opacity: 0.85,
        child: Icon(Icons.notifications_none_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildClientCard({
    required String name,
    required String email,
    required String phone,
    required String notes,
    required String clientUid,
    DateTime? createdAt,
    required bool isPendingLocal,
    String? tempIdForLocal,
    required bool subscriptionEnabled,
    required DateTime? subscriptionStartDate,
    required DateTime? subscriptionEndDate,
    required double? subscriptionPrice,
    required int subscriptionReminderDays,
    required bool accessBlocked,
  }) {
    final createdStr = _fmtDateKsa(createdAt);

    final displayName =
        name.isEmpty ? (email.isEmpty ? clientUid : email) : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DarkCard(
          minHeight: 140,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Stack(
            children: [
              Positioned(
                top: -4,
                left: -4,
                child: isPendingLocal
                    ? _NotifBellPlaceholder()
                    : _NotifBell(clientUid),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                        ),
                        child: const Icon(Icons.business_center_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: _titleStyle),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 3,
                        ),
                        onPressed: () => _enterManageClient(
                          clientUid,
                          displayName,
                        ),
                        child: Text('دخول',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          EntityAuditInfoButton(
                            collectionName: 'clients',
                            entityId: clientUid,
                            preferLocalFirst: true,
                          ),
                          const SizedBox(height: 2),
                          Text('الإضافة: $createdStr', style: _subStyle),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _IconCircleBtn(
              icon: Icons.vpn_key_rounded,
              tooltip: 'صلاحيات الدخول',
              onTap: () => _handleAccessPressed(
                isLocalItem: isPendingLocal,
                email: email,
                clientUidOrLocal: clientUid,
                initialBlocked: accessBlocked,
              ),
              bg: const Color(0xFF334155),
              size: 36,
              iconSize: 17,
              disabled: false,
            ),
            const SizedBox(width: 8),
            _IconCircleBtn(
              icon: Icons.edit_rounded,
              tooltip: 'تعديل',
              onTap: () => _openEdit(
                clientUid,
                name: name,
                email: email,
                phone: phone,
                notes: notes,
              ),
              bg: const Color(0xFF1E293B),
              size: 36,
              iconSize: 17,
            ),
            const SizedBox(width: 8),
            _IconCircleBtn(
              icon: Icons.event_repeat_rounded,
              tooltip: 'تفعيل اشتراك',
              onTap: () => _openSubscriptionDialog(
                clientUid: clientUid,
                clientName: displayName,
                isPendingLocal: isPendingLocal,
                createdAt: createdAt,
                initialEnabled: subscriptionEnabled,
                initialStartDate: subscriptionStartDate,
                initialEndDate: subscriptionEndDate,
                initialPrice: subscriptionPrice,
                initialReminderDays: subscriptionReminderDays,
              ),
              bg: const Color(0xFF0F766E),
              size: 36,
              iconSize: 17,
              disabled: isPendingLocal,
            ),
            const SizedBox(width: 8),
            _IconCircleBtn(
              icon: Icons.delete_outline_rounded,
              tooltip: 'حذف',
              onTap: () => _confirmDelete(
                isLocal: isPendingLocal,
                tempIdForLocal: tempIdForLocal,
                clientUidOrLocal: clientUid,
                displayName: displayName,
              ),
              bg: const Color(0xFF7F1D1D),
              size: 36,
              iconSize: 17,
            ),
          ],
        ),
      ],
    );
  }

  /// Ø¯Ø®ï¿½^ï¿½" ا�"ï¿½.ï¿½fØªØ¨ ï¿½"إدارة تطب�S�, ا�"Ø¹ï¿½.ï¿½Sï¿½"
  /// دخ�^�" Ø§ï¿½"�.�fتب �"Ø¥Ø¯Ø§Ø±Ø© ØªØ·Ø¨ï¿½Sï¿½, Ø§ï¿½"ع�.�S�"
  Future<DateTime?> _pickKsaDate(DateTime initialDate) async {
    final now = KsaTime.now();
    final firstDate = DateTime(now.year - 5, 1, 1);
    final lastDate = DateTime(now.year + 10, 12, 31);
    return showDatePicker(
      context: context,
      locale: const Locale('ar'),
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _openSubscriptionDialog({
    required String clientUid,
    required String clientName,
    required bool isPendingLocal,
    required DateTime? createdAt,
    required bool initialEnabled,
    required DateTime? initialStartDate,
    required DateTime? initialEndDate,
    required double? initialPrice,
    required int initialReminderDays,
  }) async {
    final successTimeDf = DateFormat('hh:mm:ss a', 'en_US');
    if (isPendingLocal || clientUid.startsWith('local_')) {
      _showSnack(
        context,
        'لا يمكن تفعيل اشتراك لعميل محلي قبل اكتمال المزامنة.',
      );
      return;
    }

    final officeUid =
        _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (officeUid.isEmpty) {
      _showSnack(context, 'تعذر تحديد حساب المكتب الحالي.');
      return;
    }

    final today = _ksaDateOnly(KsaTime.now());
    final fallbackStart = _ksaDateOnly(createdAt ?? KsaTime.now());
    final resolvedStart = initialStartDate ?? fallbackStart;
    final resolvedEnd =
        initialEndDate ?? _subscriptionEndFromStart(resolvedStart);
    final hasActiveSubscription = initialEnabled && !today.isAfter(resolvedEnd);

    DateTime suggestedStartDate;
    if (initialEnabled) {
      if (hasActiveSubscription) {
        if (initialStartDate != null) {
          suggestedStartDate = _addOneMonthClamped(initialStartDate);
        } else {
          suggestedStartDate = resolvedEnd.add(const Duration(days: 1));
        }
      } else {
        suggestedStartDate = today;
      }
    } else {
      suggestedStartDate = resolvedStart;
    }
    final suggestedEndDate = _subscriptionEndFromStart(suggestedStartDate);

    final result = await showDialog<_ClientSubscriptionDialogResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => _ClientSubscriptionDialog(
        clientName: clientName,
        renewMode: initialEnabled,
        hasActiveSubscription: hasActiveSubscription,
        initialEnabled: initialEnabled,
        initialStartDate: suggestedStartDate,
        initialEndDate: suggestedEndDate,
        initialPrice: initialPrice,
        initialReminderDays: initialReminderDays,
        onPickDate: _pickKsaDate,
      ),
    );

    if (result == null) return;

    final serverNowKsa = KsaTime.now();
    final effectiveStartDate = DateTime(
      result.startDate.year,
      result.startDate.month,
      result.startDate.day,
      serverNowKsa.hour,
      serverNowKsa.minute,
      serverNowKsa.second,
      serverNowKsa.millisecond,
      serverNowKsa.microsecond,
    );
    final effectiveEndDate = _subscriptionEndFromStart(effectiveStartDate);
    final effectiveStartUtc = KsaTime.fromKsaToUtc(effectiveStartDate);
    final effectiveEndUtc = KsaTime.fromKsaToUtc(effectiveEndDate);
    _traceOfficeRuntime(
      'subscription-save renewMode=$initialEnabled active=$hasActiveSubscription '
      'startKsa=${effectiveStartDate.toIso8601String()} startUtc=${effectiveStartUtc.toIso8601String()} '
      'endKsa=${effectiveEndDate.toIso8601String()} endUtc=${effectiveEndUtc.toIso8601String()} '
      'startDate=${_fmtYmd(effectiveStartDate)} endDate=${_fmtYmd(effectiveEndDate)}',
    );

    final data = <String, dynamic>{
      'subscriptionEnabled': result.enabled,
      'subscriptionType': 'monthly',
      'subscriptionReminderDays': result.reminderDays,
      'subscriptionPrice': result.price,
      'subscriptionStartDate': _fmtYmd(effectiveStartDate),
      'subscriptionEndDate': _fmtYmd(effectiveEndDate),
      'subscriptionStartAt': Timestamp.fromDate(effectiveStartUtc),
      'subscriptionEndAt': Timestamp.fromDate(effectiveEndUtc),
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    };

    final online = await _hasInternetConnection();
    if (!online) {
      if (!mounted) return;
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب لتفعيل الاشتراك',
        message:
            'لا يمكن تفعيل اشتراك العميل بدون إنترنت، لأن العملية مرتبطة بالسيرفر مباشرة.',
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('offices')
          .doc(officeUid)
          .collection('clients')
          .doc(clientUid)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      final fixedEndTime = successTimeDf.format(effectiveEndDate).toUpperCase();
      _showSnack(
        context,
        'تم ${initialEnabled ? 'تجديد' : 'تفعيل'} الاشتراك بنجاح. وقت انتهاء الاشتراك: $fixedEndTime',
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      if (e.code == 'unavailable') {
        await _showInternetRequiredDialog(
          context,
          title: 'الإنترنت مطلوب لتفعيل الاشتراك',
          message:
              'لا يمكن تفعيل اشتراك العميل بدون إنترنت، لأن العملية مرتبطة بالسيرفر مباشرة.',
        );
        return;
      }
      _showSnack(context, 'تعذر حفظ إعدادات الاشتراك: $e');
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'تعذر حفظ إعدادات الاشتراك: $e');
    }
  }

  void _traceWorkspaceBoxes({
    required void Function(String message) trace,
    required String workspaceUid,
    required String clientUid,
  }) {
    try {
      final propertyBoxName = scope.boxName('propertiesBox');
      final tenantBoxName = scope.boxName('tenantsBox');
      final invoiceBoxName = scope.boxName('invoicesBox');
      final contractBoxName = HiveService.contractsBoxName();
      final maintenanceBoxName = HiveService.maintenanceBoxName();

      final propertyBox = Hive.isBoxOpen(propertyBoxName)
          ? Hive.box(propertyBoxName)
          : null;
      final tenantBox =
          Hive.isBoxOpen(tenantBoxName) ? Hive.box(tenantBoxName) : null;
      final invoiceBox =
          Hive.isBoxOpen(invoiceBoxName) ? Hive.box(invoiceBoxName) : null;
      final contractBox = Hive.isBoxOpen(contractBoxName)
          ? Hive.box(contractBoxName)
          : null;
      final maintenanceBox = Hive.isBoxOpen(maintenanceBoxName)
          ? Hive.box(maintenanceBoxName)
          : null;

      final propertyPreview = propertyBox == null
          ? const <String>[]
          : propertyBox.values
              .take(3)
              .map((e) => (e is Map ? e['name'] : null) ?? (e as dynamic).name)
              .whereType<Object?>()
              .map((e) => e.toString())
              .toList(growable: false);
      final tenantPreview = tenantBox == null
          ? const <String>[]
          : tenantBox.values
              .take(3)
              .map(
                (e) => (e is Map ? e['fullName'] : null) ?? (e as dynamic).fullName,
              )
              .whereType<Object?>()
              .map((e) => e.toString())
              .toList(growable: false);

      trace(
        'workspace-boxes clientUid=$clientUid workspaceUid=$workspaceUid scope=${scope.effectiveUid()} '
        'propertiesBox=$propertyBoxName count=${propertyBox?.length ?? -1} preview=$propertyPreview '
        'tenantsBox=$tenantBoxName count=${tenantBox?.length ?? -1} preview=$tenantPreview '
        'contractsBox=$contractBoxName count=${contractBox?.length ?? -1} '
        'invoicesBox=$invoiceBoxName count=${invoiceBox?.length ?? -1} '
        'maintenanceBox=$maintenanceBoxName count=${maintenanceBox?.length ?? -1}',
      );
    } catch (e) {
      trace(
        'workspace-boxes failed clientUid=$clientUid workspaceUid=$workspaceUid err=$e',
      );
    }
  }

  Future<String> _resolveImpersonationWorkspaceUid({
    required String officeUid,
    required String clientUid,
    required void Function(String message) trace,
  }) async {
    trace(
      'workspace resolve officeUid=$officeUid clientUid=$clientUid -> use client workspace',
    );
    return clientUid;
  }

  Future<void> _enterManageClient(String clientUid, String clientName) async {
    final traceId = ++_enterTraceSeq;
    final sw = Stopwatch()..start();
    void trace(String message) {
      debugPrint('[EnterTrace#$traceId] +${sw.elapsedMilliseconds}ms $message');
    }

    trace(
      'start clientUid=$clientUid clientName=$clientName authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} scope=${scope.effectiveUid()}',
    );

    // ï¿½Y"' ف�S أ�^�" ï¿½.Ø±Ø© Ø¨Ø¹Ø¯ Ø¥Ø¶Ø§ÙØ© Ø§ï¿½"ع�.�S�": Ø¥Ø°Ø§ ï¿½fØ§ï¿½? UID ï¿½.Ø­ï¿½"�S�<ا �"Ø§ ï¿½?Ø¯Ø®ï¿½" بتات�<ا
    // ب�" ï¿½?Ø­Ø§ï¿½^ï¿½" تفر�Sغ طاب�^ر ا�"ï¿½.Ø²Ø§ï¿½.ï¿½?Ø© Ø«ï¿½. ï¿½?ï¿½?Ø¹Ø´ Ø§ï¿½"�,ائ�.ة �"ï¿½SØ¸ï¿½?Ø± Ø§ï¿½"حساب ا�"Ø­ï¿½,ï¿½Sï¿½,ï¿½S.
    if (clientUid.startsWith('local_')) {
      trace('local-uid branch start');

      var hasNetwork = true;
      try {
        final results = await Connectivity().checkConnectivity();
        hasNetwork = results.any((r) => r != ConnectivityResult.none);
      } catch (_) {
        hasNetwork = true;
      }
      if (!hasNetwork) {
        _showSnack(
          context,
          'تعذر الاتصال. حاول عند توفر الإنترنت.',
        );
        trace('local-uid branch end (offline)');
        return;
      }

      try {
        // ï¿½?Ø­Ø§ï¿½^ï¿½" تفر�Sغ ط�^اب�Sر ا�"Ø£ï¿½^Ùï¿½"ا�S�? (�^�.�?�?ا officeCreateClient) ب�?د�^ء
        await OfflineSyncService.instance.tryFlushAllIfOnline();
        trace('local-uid flushAllIfOnline done');
      } catch (_) {
        // ف�S أس�^أ ا�"Ø£Ø­ï¿½^Ø§ï¿½" �"ï¿½? ØªØªï¿½. Ø§ï¿½"�.زا�.�?ة ا�"Ø¢ï¿½?ï¿½O ï¿½^ï¿½"ا �?دخ�" Ø¹ï¿½"�? UID �.ح�"ï¿½S
        trace('local-uid flushAllIfOnline failed');
      }

      // ï¿½Y"" Ø¥Ø¹Ø§Ø¯Ø© Ø¨ï¿½?Ø§Ø¡ Ø³ØªØ±ï¿½Sï¿½. Ø§ï¿½"ع�.�"Ø§Ø¡ ï¿½"�"ï¿½.ï¿½fØªØ¨ Ø§ï¿½"حا�"ï¿½S (Ø±ï¿½SÙØ±Ø´ Ø¨Ø³ï¿½SØ· ï¿½"�?فس ا�"Ø´Ø§Ø´Ø©)
      final uid =
          _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        setState(() {
          _clientsStreamCache = _buildStreamFor(uid);
        });
      }

      _showSnack(
        context,
        'جارٍ تجهيز هذا العميل في السحابة، انتظر ثوانٍ قليلة ثم اضغط "دخول" مرة أخرى.',
      );
      trace('local-uid branch end return');
      return;
    }

    final officeUid =
        _officeUidAtStart ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (officeUid.isEmpty) {
      _showSnack(context, 'يرجى تسجيل الدخول كمكتب أولًا.');
      trace('abort officeUid-empty');
      return;
    }

    setState(() => _impersonating = true);
    trace('loader on');
    await Future.delayed(const Duration(
        milliseconds: 16)); // Ø¥Ø·Ø§Ø± ï¿½^Ø§Ø­Ø¯ ï¿½"إظ�?ار ا�"ï¿½"�^در

    try {
      await OfficeSession.storeReturnContext(expectedOfficeUid: officeUid);
      trace('OfficeSession.storeReturnContext done officeUid=$officeUid');

      // �o. �?ذ�? ا�"Ø¬ï¿½"سة �,اد�.ة �.�? شاشة ا�"ï¿½.ï¿½fØªØ¨ ï¿½?ÙØ³ï¿½?Ø§ ï¿½?' ص�"اح�Sات �fا�.�"ة (NOT ع�.�S�" �.�,�S�'Ø¯)
// ï¿½o. ï¿½?Ø°ï¿½? Ø§ï¿½"ج�"Ø³Ø© ï¿½,Ø§Ø¯ï¿½.Ø© ï¿½.ï¿½? Ø´Ø§Ø´Ø© Ø§ï¿½"�.�fتب �?فس�?ا �?' ص�"Ø§Ø­ï¿½SØ§Øª ï¿½fØ§ï¿½.ï¿½"ة (NOT ع�.�S�" ï¿½.ï¿½,ï¿½Sï¿½'د)
      const boxName = 'sessionBox';
      final session = Hive.isBoxOpen(boxName)
          ? Hive.box(boxName)
          : await Hive.openBox(boxName);
      trace('sessionBox ready');

// �Y'? Ø§ï¿½?ØªØ­Ø§ï¿½" �.�? �.�fتب: �"ï¿½SØ³ "ع�.�S�" ï¿½.ï¿½fØªØ¨" �.�,�S�'د�O �"ï¿½fï¿½? ï¿½"از�. إ�?تر�?ت
      await session.put(
          'isOfficeClient', false); // ص�"Ø§Ø­ï¿½SØ§Øª ï¿½fØ§ï¿½.ï¿½"ة
      await session.put(
          'clientNeedsInternet', false); // �Sس�.ح با�"Ø¹ï¿½.ï¿½" د�^�? إ�?تر�?ت
      await session.put('workspaceOwnerUid', clientUid);
      await session.put(
        'workspaceOwnerName',
        clientName.trim().isEmpty ? clientUid : clientName.trim(),
      );
      trace('session flags written');

      await OfficeClientGuard.refreshFromLocal();
      trace('OfficeClientGuard.refreshFromLocal done');

      // �o. ثب�'ت �?طا�, Hive ع�"ï¿½? UID Ø§ï¿½"ع�.�S�"
      final workspaceUid = await _resolveImpersonationWorkspaceUid(
        officeUid: officeUid,
        clientUid: clientUid,
        trace: trace,
      );
      scope.setFixedUid(workspaceUid);
      trace(
        'scope.setFixedUid done scope=${scope.effectiveUid()} workspaceUid=$workspaceUid',
      );

      // ï¿½o. Ø£Ø¹Ø¯ Øªï¿½?ï¿½SØ¦Ø© Ø§ï¿½"جس�^ر �^ا�"ï¿½.Ø²Ø§ï¿½.ï¿½?Ø© ï¿½"�?ذا ا�"Ø¹ï¿½.ï¿½Sï¿½" (بد�^�? تغ�S�Sر �.ستخد�. Firebase)
      try {
        // إ�S�,اف جس�^ر ا�"ï¿½.Ø²Ø§ï¿½.ï¿½?Ø© Ø§ï¿½"�,د�S�.ة (�fا�?ت ع�"ï¿½? UID Ø§ï¿½"�.�fتب)
        await SyncManager.instance.stopAll();
        trace('SyncManager.stopAll done');
      } catch (_) {}

      try {
        // إ�S�,اف خد�.ة ا�"Ø£ï¿½^Ùï¿½"ا�S�? ا�"ï¿½,Ø¯ï¿½Sï¿½.Ø© (ï¿½fØ§ï¿½?Øª Ø¹ï¿½"�? UID ا�"ï¿½.ï¿½fØªØ¨)
        OfflineSyncService.instance.dispose();
        trace('OfflineSyncService.dispose done');
      } catch (_) {}

      // Ø®Ø¯ï¿½.Ø© Ø§ï¿½"أ�^ف�"Ø§ï¿½Sï¿½? ï¿½"�?ذا ا�"Ø¹ï¿½.ï¿½Sï¿½"
      final uc = UserCollections(workspaceUid);
      final tenantsRepo = TenantsRepo(uc);
      try {
        await OfflineSyncService.instance
            .init(uc: uc, repo: tenantsRepo)
            .timeout(const Duration(seconds: 8));
        trace(
          'OfflineSyncService.init done for clientUid=$clientUid workspaceUid=$workspaceUid',
        );
      } catch (e) {
        trace('OfflineSyncService.init timeout/error (continue): $e');
      }

      // �o. افتح ص�?اد�S�, Hive ا�"Ø®Ø§ØµØ© Ø¨ï¿½?Ø°Ø§ Ø§ï¿½"ع�.�S�" ï¿½,Ø¨ï¿½" ا�"Ø¯Ø®ï¿½^ï¿½" �"ØªØ·Ø¨ï¿½Sï¿½,ï¿½?
      try {
        await HiveService.ensureReportsBoxesOpen()
            .timeout(const Duration(seconds: 8));
        trace('HiveService.ensureReportsBoxesOpen done');
        _traceWorkspaceBoxes(
          trace: trace,
          workspaceUid: workspaceUid,
          clientUid: clientUid,
        );
      } catch (e) {
        trace(
            'HiveService.ensureReportsBoxesOpen timeout/error (continue): $e');
      }

      // Ø¬Ø³ï¿½^Ø± Firestore <-> Hive:
      // Ø¹ï¿½?Ø¯ "ا�?تحا�" Ø¹ï¿½.ï¿½Sï¿½" �.�? �"ï¿½^Ø­Ø© Ø§ï¿½"�.�fتب" ï¿½Sï¿½fï¿½^ï¿½? authUid != clientUid ØºØ§ï¿½"با�<�O
      // �^تشغ�S�" Ø§ï¿½"جس�^ر �?�?ا �Sسبب permission-denied �.ت�fرر�<ا �^تأخ�Sر�<ا �.�"Ø­ï¿½^Ø¸ï¿½<Ø§.
      // ï¿½"ذ�"ï¿½f ï¿½?Ø´Øºï¿½'�" ا�"جس�^ر ف�,ط إذا �fا�? �?فس حساب Firebase �?�^ ا�"ع�.�S�" �?فس�?.
      try {
        await SyncManager.instance
            .startAll()
            .timeout(const Duration(seconds: 10));
        trace(
          'SyncManager.startAll done authUid=$authUid clientUid=$clientUid workspaceUid=$workspaceUid',
        );
      } catch (e) {
        trace(
          'SyncManager.startAll skipped because timeout/error authUid=$authUid clientUid=$clientUid workspaceUid=$workspaceUid err=$e',
        );
      }

      // حفظ اس�. ا�"ع�.�S�" ف�S ا�"�? runtime (�f�.ا �?�^)
      OfficeRuntime.selectClient(uid: clientUid, name: clientName);
      trace('OfficeRuntime.selectClient done');

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
      trace('navigated /home');
    } catch (e, st) {
      trace('ERROR $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        _showSnack(context, 'فشل الدخول: $e');
      }
    } finally {
      if (mounted) setState(() => _impersonating = false);
      trace('loader off end');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _clientsStream();
    return WillPopScope(
      onWillPop: () async => !_impersonating,
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Stack(
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
                  ],
                ),
              ),
            ),
            Positioned(
                top: -120,
                right: -80,
                child: _softCircle(220, const Color(0x33FFFFFF))),
            Positioned(
                bottom: -140,
                left: -100,
                child: _softCircle(260, const Color(0x22FFFFFF))),
            Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endFloat,
              floatingActionButton: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                onPressed: _onAdd,
                icon: const Icon(Icons.add),
                label: Text('إضافة عميل',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
              body: stream == null
                  ? Center(
                      child: Text(
                        'يرجى تسجيل الدخول',
                        style: GoogleFonts.cairo(
                            color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (context, snap) {
                        // �o. أ�^�" �.رة تفتح ا�"شاشة �^ا�"�? stream �"س�? �Sح�.�" �?' Ø§Ø¹Ø±Ø¶ ï¿½"�^در بد�" "�"ï¿½SØ³ ï¿½"د�S�f ع�.�"Ø§Ø¡ Ø¨Ø¹Ø¯"
                        if (!snap.hasData &&
                            snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        }

                        final docs = snap.data?.docs ?? [];

                        // 1) ا�"Ø¥Ø¶Ø§ÙØ§Øª Ø§ï¿½"�.ح�"ï¿½SØ© Ùï¿½^Ø±ï¿½<Ø§
                        final pendingCreates = OfflineSyncService.instance
                            .listPendingOfficeCreates();
                        final pendingEdits =
                            OfflineSyncService.instance.mapPendingOfficeEdits();
                        final pendingDeleteIds = OfflineSyncService.instance
                            .setPendingOfficeDeletesIds();

                        final pendingEmails = <String>{
                          for (final p in pendingCreates)
                            ((p['email'] ?? '') as String).trim().toLowerCase()
                        };

                        // 2) Ø¹ï¿½?Ø§ØµØ± ï¿½.Ø­ï¿½"�Sة أ�^�"ï¿½<Ø§
                        final items = <_ClientItem>[];
                        for (final p in pendingCreates) {
                          final tempId = (p['tempId'] ?? '') as String;
                          final localUid = (p['localUid'] ?? tempId) as String;
                          final email = (p['email'] ?? '') as String;

                          items.add(_ClientItem(
                            name: (p['name'] ?? '') as String,
                            email: email,
                            phone: (p['phone'] ?? '') as String,
                            notes: (p['notes'] ?? '') as String,
                            clientUid: localUid,
                            createdAt: DateTime.tryParse(
                                (p['createdAtIso'] ?? '') as String),
                            isLocal: true,
                            tempId: tempId,
                            subscriptionEnabled: false,
                            subscriptionStartDate: null,
                            subscriptionEndDate: null,
                            subscriptionPrice: null,
                            subscriptionReminderDays: 1,
                            accessBlocked: false,
                          ));
                        }

                        // 3) Ø¹ï¿½?Ø§ØµØ± Ø§ï¿½"سحاب�S + تطب�S�, تعد�S�" Ø£ï¿½^Ùï¿½"ا�S�? �^تج�?�'ب ا�"Ø§Ø²Ø¯ï¿½^Ø§Ø¬ï¿½SØ© + Ø¥Ø®ÙØ§Ø¡ Ø§ï¿½"�.حذ�^ف �.ح�"ï¿½Sï¿½<Ø§
                        for (final d in docs) {
                          final m = d.data();
                          // ï¿½"ا �?عرض �.ستخد�.�S ا�"ï¿½.ï¿½fØªØ¨ Ø¯Ø§Ø®ï¿½" �,ائ�.ة ا�"Ø¹ï¿½.ï¿½"اء.
                          final entityType = (m['entityType'] ?? '').toString();
                          final accountType =
                              (m['accountType'] ?? '').toString();
                          final officePermission =
                              (m['officePermission'] ?? '').toString();
                          final isOfficeUser = entityType == 'office_user' ||
                              accountType == 'office_staff' ||
                              officePermission == 'full' ||
                              officePermission == 'view';
                          if (isOfficeUser) {
                            continue;
                          }
                          var name = (m['name'] ?? '').toString();
                          final email = (m['email'] ?? '').toString();
                          var phone = (m['phone'] ?? '').toString();
                          var notes = (m['notes'] ?? '').toString();
                          final clientUid =
                              (m['clientUid'] ?? m['uid'] ?? d.id).toString();

                          if (_locallyDeleted.contains(clientUid)) continue;
                          if (pendingDeleteIds.contains(clientUid)) continue;
                          if (pendingEmails
                              .contains(email.trim().toLowerCase())) {
                            continue;
                          }

                          final pe = pendingEdits[clientUid];
                          if (pe != null) {
                            if (pe.containsKey('name')) {
                              name = (pe['name'] ?? '') as String;
                            }
                            if (pe.containsKey('phone')) {
                              final ph = pe['phone'];
                              phone = (ph == null) ? '' : (ph as String);
                            }
                            if (pe.containsKey('notes')) {
                              final nt = pe['notes'];
                              notes = (nt == null) ? '' : (nt as String);
                            }
                          }

                          final createdAt =
                              (m['createdAt'] as Timestamp?)?.toDate();
                          final subscriptionEnabled =
                              m['subscriptionEnabled'] == true;
                          final subscriptionStartDate =
                              _parseClientDateTime(m, const [
                            'subscriptionStartAt',
                            'subscriptionStartKsa',
                            'subscriptionStartDate',
                          ]);
                          DateTime? subscriptionEndDate =
                              _parseClientDateTime(m, const [
                            'subscriptionEndAt',
                            'subscriptionEndKsa',
                            'subscriptionEndDate',
                          ]);
                          if (subscriptionEndDate == null &&
                              subscriptionStartDate != null) {
                            subscriptionEndDate = _subscriptionEndFromStart(
                                subscriptionStartDate);
                          }
                          final subscriptionPrice =
                              _parsePrice(m['subscriptionPrice']);
                          final subscriptionReminderDays =
                              _parseReminderDays(m['subscriptionReminderDays']);
                          final accessBlocked =
                              OfficeClientGuard.isBlockedClientData(m);

                          items.add(_ClientItem(
                            name: name,
                            email: email,
                            phone: phone,
                            notes: notes,
                            clientUid: clientUid,
                            createdAt: createdAt,
                            isLocal: false,
                            subscriptionEnabled: subscriptionEnabled,
                            subscriptionStartDate: subscriptionStartDate,
                            subscriptionEndDate: subscriptionEndDate,
                            subscriptionPrice: subscriptionPrice,
                            subscriptionReminderDays: subscriptionReminderDays,
                            accessBlocked: accessBlocked,
                          ));
                        }

                        // 4) ترت�Sب ثابت �.ح�"ï¿½Sï¿½<Ø§
                        final withOrder = <({int order, _ClientItem it})>[];
                        for (final it in items) {
                          final order = _ensureIndexForEmail(it.email);
                          withOrder.add((order: order, it: it));
                        }
                        withOrder.sort((a, b) => b.order.compareTo(a.order));

                        // 5) Ø¨ï¿½?Ø§Ø¡ Ø§ï¿½"�^اج�?ة
                        if (withOrder.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt_outlined,
                                    size: 64, color: Colors.white54),
                                const SizedBox(height: 12),
                                Text('ليس لديك عملاء بعد',
                                    style: GoogleFonts.cairo(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _onAdd,
                                  icon: const Icon(Icons.add),
                                  label: Text('إضافة عميل',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 100),
                                itemCount: withOrder.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, i) {
                                  final it = withOrder[i].it;
                                  return _buildClientCard(
                                    name: it.name,
                                    email: it.email,
                                    phone: it.phone,
                                    notes: it.notes,
                                    clientUid: it.clientUid,
                                    createdAt: it.createdAt,
                                    isPendingLocal: it.isLocal,
                                    tempIdForLocal: it.tempId,
                                    subscriptionEnabled: it.subscriptionEnabled,
                                    subscriptionStartDate:
                                        it.subscriptionStartDate,
                                    subscriptionEndDate: it.subscriptionEndDate,
                                    subscriptionPrice: it.subscriptionPrice,
                                    subscriptionReminderDays:
                                        it.subscriptionReminderDays,
                                    accessBlocked: it.accessBlocked,
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_impersonating) const _FullScreenLoader(),
          ],
        ),
      ),
    );
  }
} // �?� �?�?ا�Sة _OfficeClientsPageState

class _ClientSubscriptionDialog extends StatefulWidget {
  final String clientName;
  final bool renewMode;
  final bool hasActiveSubscription;
  final bool initialEnabled;
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final double? initialPrice;
  final int initialReminderDays;
  final Future<DateTime?> Function(DateTime initialDate) onPickDate;

  const _ClientSubscriptionDialog({
    required this.clientName,
    required this.renewMode,
    required this.hasActiveSubscription,
    required this.initialEnabled,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.initialPrice,
    required this.initialReminderDays,
    required this.onPickDate,
  });

  @override
  State<_ClientSubscriptionDialog> createState() =>
      _ClientSubscriptionDialogState();
}

class _ClientSubscriptionDialogState extends State<_ClientSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _startDate;
  late DateTime _endDate;
  late int _reminderDays;
  late TextEditingController _priceCtrl;
  final _df = DateFormat('yyyy/MM/dd', 'ar');
  final _timeWithSecondsDf = DateFormat('hh:mm:ss a', 'en_US');

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
    _reminderDays = widget.initialReminderDays.clamp(1, 3);
    final initialPriceText = widget.initialPrice == null
        ? ''
        : widget.initialPrice!.toStringAsFixed(
            widget.initialPrice!.truncateToDouble() == widget.initialPrice
                ? 0
                : 2,
          );
    _priceCtrl = TextEditingController(text: initialPriceText);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  void _recomputeEndDate() {
    _endDate = _subscriptionEndFromStart(_startDate);
  }

  Future<void> _pickStartDate() async {
    final picked = await widget.onPickDate(_startDate);
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startDate.hour,
        _startDate.minute,
        _startDate.second,
      );
      _recomputeEndDate();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final online = await _hasInternetConnection();
    if (!online) {
      if (!mounted) return;
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب لتفعيل الاشتراك',
        message:
            'لا يمكن تفعيل اشتراك العميل بدون إنترنت، لأن العملية مرتبطة بالسيرفر مباشرة.',
      );
      return;
    }
    final bool confirmed = await CustomConfirmDialog.show(
      context: context,
      title: 'تأكيد الاشتراك',
      message:
          'هل أنت متأكد من ${widget.renewMode ? 'تجديد' : 'تفعيل'} الاشتراك؟ عند التأكيد لا يمكنك التراجع إلا بعد انتهاء المدة.',
      confirmLabel: 'تأكيد',
      cancelLabel: 'إلغاء',
    );
    if (!confirmed || !mounted) return;

    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    Navigator.of(context).pop(
      _ClientSubscriptionDialogResult(
        enabled: true,
        startDate: _startDate,
        endDate: _endDate,
        price: price,
        reminderDays: _reminderDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionLabel = widget.renewMode ? 'تجديد' : 'تفعيل';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: _DarkCard(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: ui.TextDirection.ltr,
                    children: [
                      const Icon(Icons.event_repeat_rounded,
                          color: Color(0xFF14B8A6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تفعيل اشتراك',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.clientName,
                    style: GoogleFonts.cairo(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تاريخ البداية',
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: widget.renewMode ? null : _pickStartDate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x3FFFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _df.format(_startDate),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'تاريخ الانتهاء',
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x1FFFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x3FFFFFFF)),
                        ),
                        child: Text(
                          '${_df.format(_endDate)} (شهري)',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ينتهي الاشتراك بنفس وقت الاشتراك.',
                        style: GoogleFonts.cairo(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      if (widget.initialEnabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          'وقت انتهاء الاشتراك: ${_timeWithSecondsDf.format(_endDate).toUpperCase()}',
                          style: GoogleFonts.cairo(
                            color: Colors.white60,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          labelText: 'السعر',
                          labelStyle: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                          errorMaxLines: 2,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0x3FFFFFFF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFF14B8A6)),
                          ),
                        ),
                        validator: (v) {
                          final price = double.tryParse((v ?? '').trim());
                          if (price == null || price <= 0) {
                            return 'أدخل سعرًا صحيحًا أكبر من صفر';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _reminderDays,
                        dropdownColor: const Color(0xFF0F172A),
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          labelText: 'موعد التنبيه',
                          labelStyle: GoogleFonts.cairo(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0x3FFFFFFF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFF14B8A6)),
                          ),
                        ),
                        items: const [1, 2, 3]
                            .map(
                              (d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text('قبل $d يومًا'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _reminderDays = v);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'هذا التنبيه لك أنت لتذكيرك بموعد انتهاء اشتراك العميل.',
                        style: GoogleFonts.cairo(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _submit(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14B8A6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            actionLabel,
                            style:
                                GoogleFonts.cairo(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x3FFFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'إلغاء',
                            style:
                                GoogleFonts.cairo(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================== 3) AddOfficeClientDialog ========================
class AddOfficeClientDialog extends StatefulWidget {
  const AddOfficeClientDialog({super.key});

  @override
  State<AddOfficeClientDialog> createState() => _AddOfficeClientDialogState();
}

class _AddOfficeClientDialogState extends State<AddOfficeClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  // أ�"Øºï¿½Sï¿½?Ø§ Ø£ï¿½S Ø¯ï¿½^Ø§Ø¦Ø± ØªØ­ï¿½.ï¿½Sï¿½" �?" Ø­ÙØ¸ ï¿½.Ø­ï¿½"�S ف�^ر�S
  static const _kNameMax = 50;
  static const _kEmailMax = 40;
  static const _kNotesMax = 1000;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    if (name.length > _kNameMax) {
      _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.');
      return;
    }
    if (email.length > _kEmailMax) {
      _showSnack(context, 'البريد الإلكتروني لا يزيد عن $_kEmailMax حرفًا.');
      return;
    }
    if (notes.length > _kNotesMax) {
      _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.');
      return;
    }

    String? phoneSend;
    final norm = normalizeLocalPhoneForUi(_phoneCtrl.text);
    if (norm == null) {
      _showSnack(context,
          'أدخل رقم الجوال بشكل صحيح (10 أرقام بالضبط) أو اتركه فارغًا.');
      return;
    } else {
      phoneSend = norm;
    }

    final limitDecision = await PackageLimitService.canAddOfficeClient();
    if (!limitDecision.allowed) {
      if (!mounted) return;
      _showSnack(
        context,
        limitDecision.message ??
            'لا يمكن إضافة عميل جديد، لقد وصلت إلى الحد الأقصى المسموح.',
      );
      return;
    }

    final online = await _hasInternetConnection();
    if (!online) {
      if (!mounted) return;
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب لإضافة عميل',
        message:
            'لا يمكن إضافة عميل جديد بدون إنترنت، لأن إنشاء العميل يتم مباشرة في السحابة.',
      );
      return;
    }

    if (mounted) {
      setState(() => _submitting = true);
    }

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('officeCreateClient');
      final result = await callable.call({
        'name': name,
        'email': email.toLowerCase(),
        'phone': phoneSend,
        'notes': notes,
      }).timeout(const Duration(seconds: 15));

      final createdUid = result.data is Map
          ? ((result.data as Map)['uid'] ?? '').toString().trim()
          : '';
      if (createdUid.isEmpty) {
        throw StateError('لم يتم استلام معرف العميل من السحابة.');
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        _CreatedOfficeClientResult(
          clientUid: createdUid,
          clientName: name,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'unavailable') {
        await _showInternetRequiredDialog(
          context,
          title: 'الإنترنت مطلوب لإضافة عميل',
          message:
              'لا يمكن إضافة عميل جديد بدون إنترنت، لأن إنشاء العميل يتم مباشرة في السحابة.',
        );
      } else if (e.code == 'already-exists') {
        _showSnack(context, 'يوجد عميل مسجل بهذا البريد الإلكتروني بالفعل.');
      } else if (e.code == 'deadline-exceeded') {
        _showSnack(
          context,
          'انتهت مهلة الاتصال أثناء إنشاء العميل. حاول مرة أخرى عند تحسن الشبكة.',
        );
      } else {
        _showSnack(context, e.message ?? 'تعذر إضافة العميل.');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showSnack(
        context,
        'استغرقت عملية إنشاء العميل وقتًا أطول من المتوقع. حاول مرة أخرى عند تحسن الشبكة.',
      );
    } on SocketException {
      if (!mounted) return;
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب لإضافة عميل',
        message:
            'لا يمكن إضافة عميل جديد بدون إنترنت، لأن إنشاء العميل يتم مباشرة في السحابة.',
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(context, 'تعذر إضافة العميل الآن. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mq = MediaQuery.of(context);
            final availableHeight =
                constraints.maxHeight - mq.viewInsets.bottom;
            final maxHeight =
                availableHeight.clamp(260.0, constraints.maxHeight);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _DarkCard(
                    minHeight: 0,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('إضافة عميل',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18)),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: _dd('اسم العميل'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'مطلوب'
                                : null,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.singleLineFormatter,
                              _LengthLimitFormatter(
                                _kNameMax,
                                onExceed: () => _showSnack(context,
                                    'اسم العميل لا يزيد عن $_kNameMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dd('البريد الإلكتروني'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'مطلوب';
                              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(s);
                              return ok ? null : 'صيغة بريد غير صحيحة';
                            },
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.singleLineFormatter,
                              _LengthLimitFormatter(
                                _kEmailMax,
                                onExceed: () => _showSnack(context,
                                    'البريد الإلكتروني لا يزيد عن $_kEmailMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _dd('رقم الجوال (اختياري)'),
                            style: GoogleFonts.cairo(color: Colors.white),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _LengthLimitFormatter(
                                10,
                                onExceed: () => _showSnack(
                                    context, 'رقم الجوال لا يزيد عن 10 أرقام.'),
                              ),
                            ],
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return null; // Ø§Ø®Øªï¿½SØ§Ø±ï¿½S
                              return s.length == 10
                                  ? null
                                  : 'يجب أن يكون 10 أرقام بالضبط';
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _notesCtrl,
                            decoration: _dd('ملاحظات (اختياري)'),
                            minLines: 2,
                            maxLines: 6,
                            style: GoogleFonts.cairo(color: Colors.white),
                            textInputAction: TextInputAction.newline,
                            inputFormatters: [
                              _LengthLimitFormatter(
                                _kNotesMax,
                                onExceed: () => _showSnack(context,
                                    'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _submitting ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: _submitting
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'جاري الإنشاء...',
                                              style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        )
                                      : Text('إضافة',
                                          style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _submitting
                                      ? null
                                      : () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Colors.white24)),
                                  child: Text('إلغاء',
                                      style: GoogleFonts.cairo(
                                          color: Colors.white70)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ======================== 4) EditOfficeClientDialog ========================
class EditOfficeClientDialog extends StatefulWidget {
  final String clientUid;
  final String? initialName;
  final String? initialEmail;
  final String? initialPhone;
  final String? initialNotes;

  const EditOfficeClientDialog({
    super.key,
    required this.clientUid,
    this.initialName,
    this.initialEmail,
    this.initialPhone,
    this.initialNotes,
  });

  @override
  State<EditOfficeClientDialog> createState() => _EditOfficeClientDialogState();
}

class _EditOfficeClientDialogState extends State<EditOfficeClientDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const _kNameMax = 50;
  static const _kNotesMax = 1000;

  @override
  void initState() {
    super.initState();
    // Ø§Ø¨Ø¯Ø£ Ø¨Ø§ï¿½"�,�S�. ا�"ï¿½,Ø§Ø¯ï¿½.Ø© ï¿½.ï¿½? Ø§ï¿½"بطا�,ة (�^�?�S �?فس�?ا �.طب�'�, ع�"ï¿½Sï¿½?Ø§ pending edits)
    _nameCtrl.text = widget.initialName ?? '';
    _emailCtrl.text = widget.initialEmail ?? '';
    _phoneCtrl.text = widget.initialPhone ?? '';
    _notesCtrl.text = widget.initialNotes ?? '';
    _loadQuietly(); // ØªØ­ï¿½.ï¿½Sï¿½" �?ادئ �Sفض�'�" Ø§ï¿½"تعد�S�"Ø§Øª Ø§ï¿½"�.ح�"ï¿½SØ© Ø¥ï¿½? ï¿½^ÙØ¬Ø¯Øª
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// ï¿½o. ØªØ­ï¿½.ï¿½Sï¿½" �?ادئ �"Ø§ ï¿½SØ³Ø¨ï¿½'ب ارتداد�<ا: �Sفض�'ï¿½" أ�S تعد�S�"Ø§Øª ï¿½.Ø­ï¿½"�S�'ة �.ع�"ï¿½'�,ة ث�. �S�f�.�'ï¿½" �.�? Firestore
  Future<void> _loadQuietly() async {
    final sw = Stopwatch()..start();
    _traceOfficeRuntime(
        'edit-client load-quietly start clientUid=${widget.clientUid}');
    try {
      // 1) إ�? �^ُجدت تعد�S�"Ø§Øª ï¿½.Ø­ï¿½"�S�'ة �.ع�"ï¿½'�,ة �"�?ذا ا�"ع�.�S�"�O �?طب�'ï¿½,ï¿½?Ø§ ï¿½^ï¿½?ï¿½?Øªï¿½?ï¿½S (ï¿½"ا حاجة �"ï¿½"شب�fة)
      final pendingEdits = OfflineSyncService.instance.mapPendingOfficeEdits();
      final pe = pendingEdits[widget.clientUid];
      if (pe != null) {
        _traceOfficeRuntime(
          'edit-client load-quietly using-pending-edits clientUid=${widget.clientUid} keys=${pe.keys.join(',')} +${sw.elapsedMilliseconds}ms',
        );
        final newName = (pe.containsKey('name'))
            ? (pe['name'] ?? '') as String
            : _nameCtrl.text;
        final newPhone = (pe.containsKey('phone'))
            ? (pe['phone'] == null ? '' : pe['phone'] as String)
            : _phoneCtrl.text;
        final newNotes = (pe.containsKey('notes'))
            ? (pe['notes'] == null ? '' : pe['notes'] as String)
            : _notesCtrl.text;
        if (mounted) {
          setState(() {
            _nameCtrl.text = newName;
            _phoneCtrl.text = newPhone;
            _notesCtrl.text = newNotes;
          });
        }
        // �"Ø§ ï¿½?Ø±Ø¬ï¿½'ع �"�"�,�S�. ا�"�,د�S�.ة حت�? �"�^ ا�"شب�fة أعادت ب�Sا�?ات أ�,د�.
        _traceOfficeRuntime(
          'edit-client load-quietly complete-from-pending clientUid=${widget.clientUid} +${sw.elapsedMilliseconds}ms',
        );
        return;
      }

      // 2) �"�^ �"ا ت�^جد تعد�S�"ات �.ح�"�Sة�O �?�,رأ ب�?د�^ء �.�? Firestore �"�.�"ء أ�S �?�,ص ف�,ط
      final scopedUid = scope.effectiveUid();
      final officeUid = scopedUid == 'guest'
          ? FirebaseAuth.instance.currentUser?.uid
          : scopedUid;
      if (officeUid == null) return;

      final um = await _safeReadDocData(
        FirebaseFirestore.instance.collection('users').doc(widget.clientUid),
        traceLabel: 'edit-client users/${widget.clientUid}',
      );

      final cm = await _safeReadDocData(
        FirebaseFirestore.instance
            .collection('offices')
            .doc(officeUid)
            .collection('clients')
            .doc(widget.clientUid),
        traceLabel:
            'edit-client offices/$officeUid/clients/${widget.clientUid}',
      );

      if (!mounted) return;
      setState(() {
        // �"ا �?طغ�? ع�"�? �.ا �fتب�? ا�"�.ستخد�. ف�S ا�"ح�,�^�"�O �?�f�.�'ï¿½" ف�,ط �.ا �?�^ فارغ
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text =
              (um['name'] ?? cm['name'] ?? _nameCtrl.text).toString();
        }
        if (_emailCtrl.text.trim().isEmpty) {
          _emailCtrl.text =
              (um['email'] ?? cm['email'] ?? _emailCtrl.text).toString();
        }
        if (_phoneCtrl.text.trim().isEmpty) {
          _phoneCtrl.text =
              (um['phone'] ?? cm['phone'] ?? _phoneCtrl.text ?? '').toString();
        }
        if (_notesCtrl.text.trim().isEmpty) {
          _notesCtrl.text = (cm['notes'] ?? _notesCtrl.text ?? '').toString();
        }
      });
      _traceOfficeRuntime(
        'edit-client load-quietly complete-from-firestore clientUid=${widget.clientUid} +${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _traceOfficeRuntime(
        'edit-client load-quietly error clientUid=${widget.clientUid} +${sw.elapsedMilliseconds}ms err=$e stack=${_compactStackTrace(st)}',
      );
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    if (name.isEmpty) {
      _showSnack(context, 'اسم العميل مطلوب.');
      return;
    }
    if (name.length > _kNameMax) {
      _showSnack(context, 'اسم العميل لا يزيد عن $_kNameMax حرفًا.');
      return;
    }
    if (notes.length > _kNotesMax) {
      _showSnack(context, 'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.');
      return;
    }

    final norm = normalizeLocalPhoneForUi(_phoneCtrl.text);
    if (norm == null) {
      _showSnack(context,
          'أدخل رقم الجوال بشكل صحيح (10 أرقام بالضبط) أو اتركه فارغًا.');
      return;
    }

    try {
      // �o. حفظ �.ح�"ï¿½S Ùï¿½^Ø±ï¿½S + Ø¥Øºï¿½"ا�, ا�"Ø¯ï¿½SØ§ï¿½"�^ج
      await OfflineSyncService.instance.enqueueEditOfficeClient(
        clientUid: widget.clientUid,
        name: name,
        phone: norm.isEmpty ? null : norm, // null = حذف
        notes: notes,
      );
      if (!mounted) return;
      _showSnack(context, 'تم التعديل بنجاح.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'تعذر الحفظ: $e');
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mq = MediaQuery.of(context);
            final availableHeight =
                constraints.maxHeight - mq.viewInsets.bottom;
            final maxHeight =
                availableHeight.clamp(260.0, constraints.maxHeight);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _DarkCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('تعديل العميل',
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameCtrl,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('اسم العميل'),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.singleLineFormatter,
                            _LengthLimitFormatter(
                              _kNameMax,
                              onExceed: () => _showSnack(context,
                                  'اسم العميل لا يزيد عن $_kNameMax حرفًا.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailCtrl,
                          enabled: false,
                          style: GoogleFonts.cairo(color: Colors.white60),
                          decoration:
                              _dd('البريد الإلكتروني (غير قابل للتعديل)'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('رقم الجوال (اختياري)'),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _LengthLimitFormatter(
                              10,
                              onExceed: () => _showSnack(
                                  context, 'رقم الجوال لا يزيد عن 10 أرقام.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesCtrl,
                          minLines: 3,
                          maxLines: 6,
                          style: GoogleFonts.cairo(color: Colors.white),
                          decoration: _dd('ملاحظات (اختياري)'),
                          textInputAction: TextInputAction.newline,
                          inputFormatters: [
                            _LengthLimitFormatter(
                              _kNotesMax,
                              onExceed: () => _showSnack(context,
                                  'حقل الملاحظات لا يزيد عن $_kNotesMax حرفًا.'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('حفظ',
                                    style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Colors.white24)),
                                child: Text('إلغاء',
                                    style: GoogleFonts.cairo(
                                        color: Colors.white70)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ======================== 5) ClientAccessDialog ========================
class ClientAccessDialog extends StatefulWidget {
  final String clientEmail;
  final String clientUid;
  final bool initialBlocked;
  const ClientAccessDialog({
    super.key,
    required this.clientEmail,
    required this.clientUid,
    required this.initialBlocked,
  });

  @override
  State<ClientAccessDialog> createState() => _ClientAccessDialogState();
}

class _ClientAccessDialogState extends State<ClientAccessDialog> {
  static final Map<String, bool> _blockedUiCache = <String, bool>{};

  String? _link;
  bool _loadingLink = false;
  bool _toggling = false;
  bool? _blocked;
  bool _loadingBlocked = true;

  String _currentOfficeUid() {
    final scoped = scope.effectiveUid().trim();
    if (scoped.isNotEmpty && scoped != 'guest') return scoped;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  Future<void> _loadBlocked() async {
    final sw = Stopwatch()..start();
    _traceOfficeRuntime(
        'client-access load-blocked start clientUid=${widget.clientUid}');
    try {
      final officeUid = _currentOfficeUid();
      final emailDocId = widget.clientEmail.trim().toLowerCase();

      final reads = <Future<Map<String, dynamic>>>[
        _safeReadDocData(
          FirebaseFirestore.instance.collection('users').doc(widget.clientUid),
          timeout: const Duration(seconds: 3),
          traceLabel: 'client-access users/${widget.clientUid}',
        ),
      ];

      if (officeUid.isNotEmpty) {
        reads.add(
          _safeReadDocData(
            FirebaseFirestore.instance
                .collection('offices')
                .doc(officeUid)
                .collection('clients')
                .doc(widget.clientUid),
            timeout: const Duration(seconds: 3),
            traceLabel:
                'client-access offices/$officeUid/clients/${widget.clientUid}',
          ),
        );
        if (emailDocId.isNotEmpty && emailDocId != widget.clientUid) {
          reads.add(
            _safeReadDocData(
              FirebaseFirestore.instance
                  .collection('offices')
                  .doc(officeUid)
                  .collection('clients')
                  .doc(emailDocId),
              timeout: const Duration(seconds: 3),
              traceLabel:
                  'client-access offices/$officeUid/clients/$emailDocId',
            ),
          );
        }
      }

      final results = await Future.wait(reads);
      final userData = results.first;
      final blockedFromUsers = OfficeClientGuard.isBlockedClientData(userData);
      final blockedFromOfficeClient = results
          .skip(1)
          .any((data) => OfficeClientGuard.isBlockedClientData(data));

      _blocked = blockedFromUsers || blockedFromOfficeClient;
      _blockedUiCache[widget.clientUid] = _blocked == true;
      _loadingBlocked = false;
      if (mounted) setState(() {});
      _traceOfficeRuntime(
        'client-access load-blocked success clientUid=${widget.clientUid} blocked=${_blocked == true} usersBlocked=$blockedFromUsers officeBlocked=$blockedFromOfficeClient +${sw.elapsedMilliseconds}ms',
      );
    } catch (_) {
      _loadingBlocked = false;
      if (mounted) setState(() {});
      // أ�^ف�"Ø§ï¿½Sï¿½?: ï¿½?ÙØ¨ï¿½,ï¿½S Ø¢Ø®Ø± Ø­Ø§ï¿½"ة �.عر�^فة إ�? �^ُجدت.
    }
  }

  @override
  void initState() {
    super.initState();
    _blocked = widget.initialBlocked;
    _loadingBlocked = false;
    _loadBlocked();
  }

  Future<void> _genLink() async {
    // تح�,�'�, �.سب�,: إ�? �"ï¿½. ï¿½Sï¿½^Ø¬Ø¯ Ø¥ï¿½?ØªØ±ï¿½?Øª ï¿½?Ø¸ï¿½?Ø± Øªï¿½?Ø¨ï¿½Sï¿½? ï¿½^Ø§Ø¶Ø­
    final online = await _hasInternetConnection();
    if (!online) {
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب',
        message:
            'لا يمكن توليد رابط تعيين كلمة المرور بدون إنترنت. يرجى فتح الإنترنت ثم المحاولة مرة أخرى.',
      );
      return;
    }

    setState(() {
      _loadingLink = true;
      _link = null;
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('generatePasswordResetLink');
      final res = await callable.call({'email': widget.clientEmail});
      _link = (res.data as Map?)?['resetLink']?.toString();
      if (_link == null || _link!.isEmpty) {
        _showSnack(context, 'تعذر توليد الرابط.');
      }
      if (mounted) setState(() {});
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        await _showInternetRequiredDialog(
          context,
          title: 'الإنترنت مطلوب',
          message:
              'لا يمكن توليد رابط تعيين كلمة المرور بدون إنترنت. يرجى فتح الإنترنت ثم المحاولة مرة أخرى.',
        );
      } else {
        _showSnack(context, e.message ?? 'تعذر توليد الرابط.');
      }
    } on SocketException {
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب',
        message:
            'لا يمكن توليد رابط تعيين كلمة المرور بدون إنترنت. يرجى فتح الإنترنت ثم المحاولة مرة أخرى.',
      );
    } catch (_) {
      _showSnack(context, 'تعذر الاتصال. حاول عند توفر الإنترنت.');
    } finally {
      if (mounted) setState(() => _loadingLink = false);
    }
  }

  Future<void> _toggleBlocked(bool value) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: _DarkCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value ? 'إيقاف دخول العميل' : 'إلغاء الإيقاف',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 12),
              Text(
                value
                    ? 'سيتم منع العميل من دخول التطبيق حتى إعادة التفعيل.\nهل ترغب بالمتابعة؟'
                    : 'سيُسمح للعميل بالدخول من جديد.\nهل ترغب بالمتابعة؟',
                style: GoogleFonts.cairo(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('تأكيد'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dctx, false),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    final previousBlocked = _blocked ?? false;
    setState(() {
      _toggling = true;
      _blocked = value;
    });
    _blockedUiCache[widget.clientUid] = value;
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('updateUserStatus');
      await callable.call({'uid': widget.clientUid, 'blocked': value});
      _blocked = value;
      if (mounted) setState(() {});
      _showSnack(
          context, value ? 'تم إيقاف دخول العميل.' : 'تم السماح بدخول العميل.');
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        _blocked = previousBlocked;
        _blockedUiCache[widget.clientUid] = previousBlocked;
        if (mounted) setState(() {});
        await _showInternetRequiredDialog(
          context,
          title: 'الإنترنت مطلوب',
          message:
              'لا يمكن تنفيذ "السماح بدخول العميل" بدون إنترنت، لأن العملية مرتبطة بالسيرفر مباشرة.',
        );
      } else {
        _blocked = previousBlocked;
        _blockedUiCache[widget.clientUid] = previousBlocked;
        if (mounted) setState(() {});
        _showSnack(context, e.message ?? 'تعذر تعديل الحالة.');
      }
    } on SocketException {
      _blocked = previousBlocked;
      _blockedUiCache[widget.clientUid] = previousBlocked;
      if (mounted) setState(() {});
      await _showInternetRequiredDialog(
        context,
        title: 'الإنترنت مطلوب',
        message:
            'لا يمكن تنفيذ "السماح بدخول العميل" بدون إنترنت، لأن العملية مرتبطة بالسيرفر مباشرة.',
      );
    } catch (_) {
      _blocked = previousBlocked;
      _blockedUiCache[widget.clientUid] = previousBlocked;
      if (mounted) setState(() {});
      _showSnack(context, 'تعذر الاتصال. حاول عند توفر الإنترنت.');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  InputDecoration _dd(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _DarkCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صلاحيات الدخول / كلمة المرور',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 12),
              SelectableText('البريد: ${widget.clientEmail}',
                  style: GoogleFonts.cairo(color: Colors.white70)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loadingLink ? null : _genLink,
                icon: const Icon(Icons.link),
                label: _loadingLink
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('توليد رابط تعيين كلمة مرور'),
              ),
              const SizedBox(height: 8),
              if (_link != null && _link!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _link!,
                          maxLines: 3,
                          style: GoogleFonts.cairo(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _link!));
                          if (mounted) _showSnack(context, 'تم النسخ.');
                        },
                        icon: const Icon(Icons.copy_all_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text((_blocked ?? false) ? 'الدخول: موقوف' : 'الدخول: مسموح',
                      style: GoogleFonts.cairo(color: Colors.white)),
                  const Spacer(),
                  Switch(
                    value: !(_blocked ?? false),
                    onChanged: (_toggling || _blocked == null)
                        ? null
                        : (v) => _toggleBlocked(!v),
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF22C55E),
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                      child: Text('إغلاق',
                          style: GoogleFonts.cairo(color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ======================== 6) DeleteClientDialog ========================
class DeleteClientDialog extends StatefulWidget {
  final String clientName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const DeleteClientDialog({
    super.key,
    required this.clientName,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<DeleteClientDialog> createState() => _DeleteClientDialogState();
}

class _DeleteClientDialogState extends State<DeleteClientDialog> {
  bool _understand = false;

  Future<void> _requireConsentWarning() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: _DarkCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تأكيد مطلوب',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'قبل الحذف النهائي، يجب الإقرار بالموافقة على الحذف عبر تفعيل مربع التأكيد.',
                style: GoogleFonts.cairo(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(dctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _DarkCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x26FF4D4D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x40FF4D4D)),
                    ),
                    child: const Icon(Icons.delete_forever_rounded,
                        color: Color(0xFFFF6B6B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('حذف العميل',
                        style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'سيتم حذف العميل "${widget.clientName}" نهائيًا مع كافة بياناته (العقارات، العقود، السندات، المرفقات، الإشعارات، وغيرها). لا يمكن التراجع.',
                  style: GoogleFonts.cairo(color: Colors.white70, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x14FF4D4D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x26FF4D4D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFFA726)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'هذا الإجراء دائم وسيؤدي إلى فقدان كل السجلات المرتبطة بهذا العميل.',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _understand,
                onChanged: (v) => setState(() => _understand = v ?? false),
                activeColor: const Color(0xFFFF6B6B),
                checkboxShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                    'نعم، أفهم العواقب وأرغب في حذف هذا العميل نهائيًا.',
                    style: GoogleFonts.cairo(color: Colors.white70)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (!_understand) {
                          _requireConsentWarning();
                          return;
                        }
                        widget.onConfirm();
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('حذف نهائي'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7F1D1D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('رجوع',
                          style: GoogleFonts.cairo(color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
