/// Production authentication is the default for every build mode.
/// A separate demonstration build must explicitly opt in with:
/// --dart-define=EJARZ_DEMO_MODE=true
const bool kEjarzDemoMode = bool.fromEnvironment(
  'EJARZ_DEMO_MODE',
  defaultValue: false,
);

/// Keeps the old fully local walkthrough available only when explicitly needed.
///
/// The normal demo mode stays connected to Firebase so every buyer/customer gets
/// a separate UID and their sample contracts appear in the admin dashboard.
const bool kEjarzLocalDemoMode = kEjarzDemoMode &&
    bool.fromEnvironment(
      'EJARZ_LOCAL_DEMO_MODE',
      defaultValue: false,
    );

const bool kEjarzFirebaseDemoMode = kEjarzDemoMode && !kEjarzLocalDemoMode;

const String kDemoVerificationId = 'ejarz-pro-demo-verification';
const String kDemoUserName = 'عميل النسخة التجريبية';
const String kDemoUserEmail = 'demo@ejarz-pro.sa';
