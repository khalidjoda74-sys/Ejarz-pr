import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:darvoo/utils/ksa_time.dart';

class SubscriptionExpiry {
  SubscriptionExpiry._();

  static bool isExpired(Map<String, dynamic> data) {
    final endUtc = parseEndUtc(data['subscription_end']);
    if (_isPreciseDemoExpiry(data) && endUtc != null) {
      return !KsaTime.nowUtc().isBefore(endUtc.toUtc());
    }

    final inclusiveEndKsaDate = parseInclusiveEndKsaDate(
      data,
      fallbackEndUtc: endUtc,
    );
    if (inclusiveEndKsaDate == null) return false;

    final todayKsa = KsaTime.dateOnly(KsaTime.nowKsa());
    return todayKsa.isAfter(inclusiveEndKsaDate);
  }

  static DateTime? parseEndUtc(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  static DateTime? parseInclusiveEndKsaDate(
    Map<String, dynamic> data, {
    DateTime? fallbackEndUtc,
  }) {
    final endKsaText = (data['end_date_ksa'] as String?)?.trim();
    if (endKsaText != null && endKsaText.isNotEmpty) {
      final normalized = endKsaText.replaceAll('/', '-');
      final parts = normalized.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          return DateTime(y, m, d);
        }
      }
    }

    final endUtc = fallbackEndUtc ?? parseEndUtc(data['subscription_end']);
    if (endUtc == null) return null;

    final endKsa = KsaTime.toKsa(endUtc);
    return DateTime(endKsa.year, endKsa.month, endKsa.day);
  }

  static bool _isPreciseDemoExpiry(Map<String, dynamic> data) {
    final isDemo = (data['isDemo'] ?? false) == true;
    final duration = (data['duration'] ?? '').toString().trim().toLowerCase();
    return isDemo || duration == 'demo3d';
  }
}
