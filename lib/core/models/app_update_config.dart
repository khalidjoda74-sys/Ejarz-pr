import 'package:flutter/widgets.dart';

enum AppUpdateAvailability { none, optional, force }

class AppUpdateConfig {
  const AppUpdateConfig({
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.forceUpdate,
    required this.appStoreUrl,
    required this.messageAr,
    required this.messageEn,
    required this.enabled,
  });

  final String latestVersion;
  final String minimumSupportedVersion;
  final bool forceUpdate;
  final String appStoreUrl;
  final String messageAr;
  final String messageEn;
  final bool enabled;

  static const AppUpdateConfig disabled = AppUpdateConfig(
    latestVersion: '',
    minimumSupportedVersion: '',
    forceUpdate: false,
    appStoreUrl: '',
    messageAr: '',
    messageEn: '',
    enabled: false,
  );

  bool get hasLatestVersion => latestVersion.trim().isNotEmpty;
  bool get hasMinimumSupportedVersion =>
      minimumSupportedVersion.trim().isNotEmpty;
  bool get hasAppStoreUrl => appStoreUrl.trim().isNotEmpty;

  factory AppUpdateConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return disabled;
    String readString(String key) => (map[key] ?? '').toString().trim();
    bool readBool(String key) {
      final value = map[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    return AppUpdateConfig(
      latestVersion: readString('ios_latest_version'),
      minimumSupportedVersion: readString('ios_min_version'),
      forceUpdate: readBool('ios_force_update'),
      appStoreUrl: readString('ios_app_store_url'),
      messageAr: readString('message_ar'),
      messageEn: readString('message_en'),
      enabled: readBool('ios_enabled'),
    );
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.availability,
    required this.currentVersion,
    required this.config,
  });

  final AppUpdateAvailability availability;
  final String currentVersion;
  final AppUpdateConfig config;

  bool get shouldShow => availability != AppUpdateAvailability.none;
  bool get isForce => availability == AppUpdateAvailability.force;
  bool get isOptional => availability == AppUpdateAvailability.optional;

  String localizedMessage(Locale locale) {
    final preferArabic = locale.languageCode.toLowerCase() == 'ar';
    final preferred = preferArabic ? config.messageAr : config.messageEn;
    final fallback = preferArabic ? config.messageEn : config.messageAr;
    if (preferred.trim().isNotEmpty) return preferred.trim();
    if (fallback.trim().isNotEmpty) return fallback.trim();
    if (isForce) {
      return preferArabic
          ? 'يتوفر إصدار أحدث مطلوب لمتابعة استخدام التطبيق. يرجى التحديث من متجر App Store.'
          : 'A newer version is required to continue using the app. Please update from the App Store.';
    }
    return preferArabic
        ? 'يوجد إصدار أحدث من التطبيق. يُفضّل التحديث للحصول على آخر التحسينات.'
        : 'A newer version of the app is available. Updating is recommended to get the latest improvements.';
  }

  String localizedTitle(Locale locale) {
    final preferArabic = locale.languageCode.toLowerCase() == 'ar';
    if (isForce) {
      return preferArabic ? 'تحديث مطلوب' : 'Update Required';
    }
    return preferArabic ? 'يتوفر تحديث جديد' : 'Update Available';
  }

  String localizedUpdateLabel(Locale locale) {
    return locale.languageCode.toLowerCase() == 'ar'
        ? 'تحديث الآن'
        : 'Update Now';
  }

  String localizedLaterLabel(Locale locale) {
    return locale.languageCode.toLowerCase() == 'ar' ? 'لاحقًا' : 'Later';
  }

  String localizedInvalidUrlMessage(Locale locale) {
    return locale.languageCode.toLowerCase() == 'ar'
        ? 'رابط التحديث غير متاح حاليًا.'
        : 'The update link is not available right now.';
  }

  String localizedVersionDetails(Locale locale) {
    final preferArabic = locale.languageCode.toLowerCase() == 'ar';
    final current = currentVersion.trim().isEmpty ? '-' : currentVersion.trim();
    final latest =
        config.latestVersion.trim().isEmpty ? '-' : config.latestVersion.trim();
    return preferArabic
        ? 'الإصدار الحالي: $current\nآخر إصدار متاح: $latest'
        : 'Current version: $current\nLatest available version: $latest';
  }
}
