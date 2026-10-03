import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

// Public site key, restricted to this project's Hosting domains. It is not a secret.
const appCheckWebSiteKey = String.fromEnvironment(
  'FIREBASE_APPCHECK_WEB_SITE_KEY',
  defaultValue: '6LeVntgtAAAAAL-w7K-RWIafVfbB8OEhIFxkyAZZ',
);

/// Installs the provider once, before other Firebase clients are used.
/// Rollout is observational: errors do not disable login while enforcement is off.
/// The SDK owns token caching and refresh; no timers or force-refresh loops here.
class AppCheckBootstrap {
  static Future<void>? _initialization;
  static String status = 'not_started';
  static String? failureCode;

  static Future<void> initialize() {
    if (kDebugMode) {
      // Development does not silently register trusted debug tokens in production.
      status = 'development_skipped';
      return Future<void>.value();
    }
    return _initialization ??= _activate();
  }

  static Future<void> _activate() async {
    try {
      if (kIsWeb &&
          !{
            'ejarz-pro-20260624.web.app',
            'ejarz-pro-20260624.firebaseapp.com',
            'aqdak.sa',
            'app.aqdak.sa',
          }.contains(Uri.base.host)) {
        status = 'unregistered_host';
        return;
      }
      if (!kIsWeb &&
          defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS) {
        status = 'unsupported_platform';
        return;
      }
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaEnterpriseProvider(appCheckWebSiteKey),
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      // Provider initialized does not mean a device attestation was verified.
      status = 'provider_initialized';
    } catch (_) {
      status = 'initialization_failed';
      failureCode = 'provider_initialization_failed';
      // Never log tokens or provider responses containing credentials.
    }
  }
}
