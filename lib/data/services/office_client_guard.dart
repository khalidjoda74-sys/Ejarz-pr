// lib/data/services/office_client_guard.dart
// خدمة صغيرة للتحقق هل المستخدم "عميل مكتب" أم لا
// وتعتمد بالكامل على Hive (sessionBox) حتى تعمل بدون إنترنت.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class OfficeClientGuard {
  static const String _sessionBoxName = 'sessionBox';
  static const String _flagKey = 'isOfficeClient';

  static bool? _cachedIsOfficeClient;

  /// يرجع true إذا كان المستخدم الحالي "عميل مكتب" (يُدار من مكتب عقار).
  /// المنطق هنا يعتمد فقط على sessionBox حتى يعمل 100٪ بدون إنترنت.
  static Future<bool> isOfficeClient() async {
    // إن وُجدت قيمة كاش نعيدها مباشرة
    if (_cachedIsOfficeClient != null) return _cachedIsOfficeClient!;

    try {
      if (!Hive.isBoxOpen(_sessionBoxName)) {
        // في تطبيقك يتم فتح sessionBox في البداية، لكن لو لم يكن مفتوحاً نعتبره ليس عميل مكتب
        _cachedIsOfficeClient = false;
        return false;
      }

      final box = Hive.box(_sessionBoxName);
      final raw = box.get(_flagKey, defaultValue: false);

      final value = raw == true;
      _cachedIsOfficeClient = value;
      return value;
    } catch (_) {
      _cachedIsOfficeClient = false;
      return false;
    }
  }

  /// يمكن استدعاؤها من أي مكان لتحديث الكاش (مثلاً بعد تسجيل الدخول أو تسجيل خروج).
  static Future<void> refreshFromLocal() async {
    _cachedIsOfficeClient = null;
    await isOfficeClient();
  }

  /// تُستخدم داخل onPressed:
  /// - إن كان عميل مكتب ➜ تُظهر رسالة وتُرجع true (اخرج من الـ onPressed).
  /// - غير ذلك ➜ تُرجع false (كمّل التنفيذ عادي).
  static Future<bool> blockIfOfficeClient(BuildContext context) async {
    final isClient = await isOfficeClient();
    if (!isClient) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ليس لديك صلاحية لتنفيذ هذا الإجراء. هذا الحساب يُدار بالكامل عن طريق مكتب العقار.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }
}
