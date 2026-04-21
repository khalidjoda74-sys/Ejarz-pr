// lib/data/services/subscription_alerts.dart
import 'package:darvoo/utils/ksa_time.dart';
import 'package:intl/intl.dart';

class SubscriptionAlert {
  final String title;
  final String body;
  final DateTime endAt;

  SubscriptionAlert({
    required this.title,
    required this.body,
    required this.endAt,
  });
}

/// منطق إنشاء تنبيه انتهاء الاشتراك.
/// - إذا كان تاريخ الانتهاء اليوم => يظهر نص "سينتهي اشتراكك اليوم، الموافق {التاريخ}"
/// - إذا كان تاريخ الانتهاء غدًا  => يظهر نص "سينتهي اشتراكك غدًا، الموافق {التاريخ}"
/// - غير ذلك                       => لا يظهر تنبيه
class SubscriptionAlerts {
  static SubscriptionAlert? compute({required DateTime? endAt}) {
    if (endAt == null) return null;

    final now = KsaTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(endAt.year, endAt.month, endAt.day);

    final diffDays = end.difference(today).inDays;

    if (diffDays == 0 || diffDays == 1) {
      final df = DateFormat('d MMMM yyyy', 'ar');
      final formatted = df.format(end);

      const String title = 'تنبيه الاشتراك';
      final String body = (diffDays == 0)
          ? 'سينتهي اشتراكك اليوم، الموافق $formatted.'
          : 'سينتهي اشتراكك غدًا، الموافق $formatted.';

      return SubscriptionAlert(title: title, body: body, endAt: end);
    }

    // diffDays < 0 (انتهى بالفعل) أو diffDays > 1 (ما يزال بعيداً): لا تنبيه
    return null;
  }
}



