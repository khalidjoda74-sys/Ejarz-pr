import 'package:flutter/foundation.dart';

/// Demo mode is intentionally explicit for release builds.
///
/// Debug/profile builds use demo mode by default to make buyer walkthroughs fast.
/// Release builds stay production-safe unless built with:
/// --dart-define=EJARZ_DEMO_MODE=true
const bool kEjarzDemoMode = bool.fromEnvironment(
  'EJARZ_DEMO_MODE',
  defaultValue: kDebugMode || kProfileMode,
);

/// Keeps the old fully local walkthrough available only when explicitly needed.
///
/// The normal demo mode stays connected to Firebase so every buyer/customer gets
/// a separate UID and their sample contracts appear in the admin dashboard.
const bool kEjarzLocalDemoMode = bool.fromEnvironment(
  'EJARZ_LOCAL_DEMO_MODE',
  defaultValue: false,
);

const bool kEjarzFirebaseDemoMode = kEjarzDemoMode && !kEjarzLocalDemoMode;

const String kDemoVerificationId = 'ejarz-pro-demo-verification';
const String kDemoUserName = 'عميل النسخة التجريبية';
const String kDemoUserEmail = 'demo@ejarz-pro.sa';
