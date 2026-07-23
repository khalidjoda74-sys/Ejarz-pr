import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/demo_config.dart';
import '../core/firebase_bootstrap.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppScope.of(context, listen: false).completeSplash();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.white);
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  final List<_OnboardingData> _pages = const <_OnboardingData>[
    _OnboardingData(
      title: 'أنشئ عقدك بسهولة',
      subtitle:
          'أدخل بيانات العقد بخطوات واضحة، وارفع المستندات المطلوبة من جوالك.',
      icon: Icons.description_outlined,
    ),
    _OnboardingData(
      title: 'مراجعة احترافية',
      subtitle:
          'يراجع فريق عقود برو بياناتك قبل إدخالها في منصة إيجار لتقليل الأخطاء والنواقص.',
      icon: Icons.fact_check_outlined,
    ),
    _OnboardingData(
      title: 'تابع العقد حتى التوثيق',
      subtitle:
          'راقب حالة طلبك لحظة بلحظة، واستلم نسخة العقد الموثق داخل التطبيق.',
      icon: Icons.verified_user_outlined,
    ),
  ];

  void _next() {
    if (_index == _pages.length - 1) {
      AppScope.of(context, listen: false).completeOnboarding();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
              child: Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => AppScope.of(context, listen: false)
                        .completeOnboarding(),
                    child: const Text('تخطي'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final data = _pages[index];
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Container(
                                  width:
                                      mathMin(context.screenWidth * 0.46, 188),
                                  height:
                                      mathMin(context.screenWidth * 0.46, 188),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.13),
                                      width: 2,
                                    ),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: <Widget>[
                                      Icon(
                                        data.icon,
                                        color: AppColors.primary,
                                        size: mathMin(
                                          context.screenWidth * 0.26,
                                          105,
                                        ),
                                      ),
                                      if (index == 0)
                                        Positioned(
                                          bottom: 28,
                                          right: 30,
                                          child: Container(
                                            width: 34,
                                            height: 34,
                                            decoration: const BoxDecoration(
                                              color: AppColors.secondary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  data.title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  data.subtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.ejarzTheme.muted,
                                    fontSize: context.sp(12.8),
                                    height: 1.45,
                                  ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        width: index == _index ? 30 : 9,
                        height: 9,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: index == _index
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(
                        _index == _pages.length - 1 ? 'ابدأ الآن' : 'التالي',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double mathMin(double a, double b) => a < b ? a : b;

Future<void> openLegalLink(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    showAppSnackBar(context, 'تعذر فتح الرابط الآن');
  }
}

class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 0,
      children: <Widget>[
        TextButton(
          onPressed: () => openLegalLink(context, controller.legalTermsUrl),
          child: const Text('الشروط والأحكام'),
        ),
        TextButton(
          onPressed: () => openLegalLink(context, controller.legalPrivacyUrl),
          child: const Text('سياسة الخصوصية'),
        ),
      ],
    );
  }
}

class _OnboardingData {
  final String title;
  final String subtitle;
  final IconData icon;

  const _OnboardingData({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class SaudiPhoneNumber {
  final String nationalNumber;

  const SaudiPhoneNumber(this.nationalNumber);

  String get e164 => '+966$nationalNumber';

  String get localDisplay => '0$nationalNumber';

  String get formattedDisplay {
    if (nationalNumber.length != 9) return e164;
    return '+966 ${nationalNumber.substring(0, 2)} '
        '${nationalNumber.substring(2, 5)} '
        '${nationalNumber.substring(5)}';
  }
}

SaudiPhoneNumber? normalizeSaudiMobile(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00966')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('966')) {
    digits = digits.substring(3);
  }
  if (digits.startsWith('05')) {
    digits = digits.substring(1);
  }
  if (!RegExp(r'^5\d{8}$').hasMatch(digits)) {
    return null;
  }
  return SaudiPhoneNumber(digits);
}

String? validateSaudiMobile(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return 'أدخل رقم الجوال';

  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00966')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('966')) {
    digits = digits.substring(3);
  }

  if (digits.startsWith('0')) {
    if (!digits.startsWith('05')) {
      return 'رقم الجوال يجب أن يبدأ بـ 05 أو 5';
    }
    digits = digits.substring(1);
  }

  if (!digits.startsWith('5')) {
    return 'رقم الجوال يجب أن يبدأ بـ 05 أو 5';
  }
  if (digits.length < 9) {
    return 'رقم الجوال يجب أن يكون 9 أرقام إذا بدأ بـ 5 أو 10 أرقام إذا بدأ بـ 05';
  }
  if (digits.length > 9) {
    return 'رقم الجوال أطول من المطلوب';
  }
  if (!RegExp(r'^5\d{8}$').hasMatch(digits)) {
    return 'رقم الجوال غير صحيح';
  }
  return null;
}

String firebasePhoneAuthMessage(FirebaseAuthException error) {
  return switch (error.code) {
    'operation-not-allowed' =>
      'تعذر إرسال رمز التحقق لهذا الرقم حاليًا. حاول لاحقًا أو تواصل مع الدعم',
    'invalid-phone-number' => 'رقم الجوال غير صحيح',
    'too-many-requests' =>
      'طلبات الرمز متكررة خلال وقت قصير. انتظر قليلًا ثم حاول مرة أخرى',
    'quota-exceeded' =>
      'تعذر إرسال رمز جديد الآن. حاول لاحقًا أو تواصل مع الدعم',
    'internal-error' => 'تعذر Firebase معالجة طلب التحقق الآن. حاول لاحقًا',
    'network-request-failed' => 'تحقق من اتصال الإنترنت وحاول مرة أخرى',
    'missing-client-identifier' =>
      'ملف Firebase للتطبيق غير محدث. ثبّت النسخة الجديدة من التطبيق',
    'invalid-verification-code' => 'رمز التحقق غير صحيح',
    'session-expired' => 'انتهت صلاحية الرمز. أعد الإرسال',
    'play-services-not-available' =>
      'خدمات Google Play غير متاحة أو تحتاج إلى تحديث على الجهاز',
    'captcha-check-failed' ||
    'app-not-authorized' ||
    'invalid-app-credential' =>
      'تعذر التحقق من التطبيق. تأكد من إعدادات Firebase وSHA',
    _ => 'تعذر إتمام التحقق الآن. رمز الخطأ: ${error.code}',
  };
}

typedef OtpCodeSent = void Function(String verificationId, int? resendToken);

const int _otpRetryCooldownSeconds = 45;

String _otpCooldownLabel(int seconds) => 'إعادة المحاولة بعد $secondsث';

String _otpCooldownMessage(int seconds) =>
    'انتظر $seconds ثانية قبل طلب رمز جديد';

enum AuthFlow { login, register }

class PhoneRegistrationState {
  final bool registered;
  final bool blocked;
  final String status;

  const PhoneRegistrationState({
    required this.registered,
    required this.blocked,
    required this.status,
  });

  factory PhoneRegistrationState.fromMap(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? 'active';
    return PhoneRegistrationState(
      registered: data['registered'] == true,
      blocked: data['blocked'] == true ||
          status == 'blocked' ||
          status == 'suspended',
      status: status,
    );
  }
}

class AuthProfileResult {
  final String name;
  final String phone;
  final String email;

  const AuthProfileResult({
    required this.name,
    required this.phone,
    required this.email,
  });

  factory AuthProfileResult.fromMap(
    Map<String, dynamic> data, {
    required String fallbackName,
    required String fallbackPhone,
    required String fallbackEmail,
  }) {
    String value(String key, String fallback) {
      final raw = data[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      return fallback;
    }

    return AuthProfileResult(
      name: value('name', fallbackName),
      phone: value('phone', fallbackPhone),
      email: value('email', fallbackEmail),
    );
  }
}

Future<Map<String, dynamic>> _callAuthFunction(
  String name,
  Map<String, Object?> data,
) async {
  await FirebaseBootstrap.ready;
  if (!FirebaseBootstrap.initialized) {
    throw StateError('Firebase is not initialized');
  }
  final result =
      await FirebaseFunctions.instance.httpsCallable(name).call(data);
  final raw = result.data;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

Future<PhoneRegistrationState> checkPhoneRegistration(
  SaudiPhoneNumber phone,
) async {
  final data = await _callAuthFunction(
    'checkPhoneRegistration',
    <String, Object?>{'phoneE164': phone.e164},
  );
  return PhoneRegistrationState.fromMap(data);
}

Future<AuthProfileResult> finalizePhoneAuthFlow({
  required AuthFlow flow,
  required String phone,
  String name = '',
  String email = '',
}) async {
  if (kEjarzDemoMode) {
    return AuthProfileResult(
      name: name.trim().isNotEmpty ? name.trim() : kDemoUserName,
      phone: phone,
      email: email.trim().isNotEmpty ? email.trim() : kDemoUserEmail,
    );
  }

  final data = await _callAuthFunction(
    flow == AuthFlow.register
        ? 'finalizePhoneRegistration'
        : 'finalizePhoneLogin',
    <String, Object?>{
      'phoneE164': phone,
      if (flow == AuthFlow.register) 'name': name.trim(),
      if (flow == AuthFlow.register) 'email': email.trim(),
    },
  );
  return AuthProfileResult.fromMap(
    data,
    fallbackName: name.trim(),
    fallbackPhone: phone,
    fallbackEmail: email.trim(),
  );
}

String phoneAuthFlowMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message?.trim();
    return switch (error.code) {
      'already-exists' => 'الرقم موجود من قبل، استخدم تسجيل الدخول',
      'not-found' => 'الرقم غير مسجل، أنشئ حسابًا جديدًا أولًا',
      'permission-denied' => message?.isNotEmpty == true
          ? message!
          : 'لا يمكن إكمال العملية لهذا الرقم',
      'failed-precondition' => message?.isNotEmpty == true
          ? message!
          : 'لا يمكن إكمال العملية لهذا الرقم',
      'invalid-argument' =>
        message?.isNotEmpty == true ? message! : 'تحقق من البيانات المدخلة',
      'unavailable' => 'تعذر الاتصال بخدمة التحقق الآن. حاول مرة أخرى',
      _ => message?.isNotEmpty == true
          ? message!
          : 'تعذر إكمال التحقق الآن. حاول مرة أخرى',
    };
  }
  return 'تعذر الاتصال بخدمة التحقق الآن. حاول مرة أخرى';
}

Future<void> requestSaudiOtp({
  required BuildContext context,
  required SaudiPhoneNumber phone,
  required VoidCallback onStarted,
  required VoidCallback onFinished,
  required OtpCodeSent onCodeSent,
  required Future<void> Function(PhoneAuthCredential credential) onAutoVerified,
  int? forceResendingToken,
}) async {
  if (kEjarzDemoMode) {
    onStarted();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    onFinished();
    if (!context.mounted) return;
    onCodeSent(kDemoVerificationId, null);
    return;
  }

  if (kIsWeb) {
    showAppSnackBar(
      context,
      'التحقق بدون متصفح متاح في تطبيق Android و iOS. إصدار الويب يحتاج reCAPTCHA.',
    );
    return;
  }

  var finished = false;
  var completedAutomatically = false;

  void finishLoading() {
    if (finished) return;
    finished = true;
    onFinished();
  }

  onStarted();
  try {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.e164,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        completedAutomatically = true;
        try {
          await onAutoVerified(credential);
        } on FirebaseAuthException catch (error) {
          debugPrint(
            'Firebase phone auto verification failed: '
            '${error.code} - ${error.message}',
          );
          if (context.mounted) {
            showAppSnackBar(context, firebasePhoneAuthMessage(error));
          }
        } catch (error) {
          debugPrint('Firebase phone auto verification failed: $error');
          if (context.mounted) {
            showAppSnackBar(context, 'تعذر إكمال التحقق التلقائي');
          }
        } finally {
          finishLoading();
        }
      },
      verificationFailed: (error) {
        debugPrint(
          'Firebase phone verification failed: '
          '${error.code} - ${error.message}',
        );
        finishLoading();
        if (context.mounted) {
          showAppSnackBar(context, firebasePhoneAuthMessage(error));
        }
      },
      codeSent: (verificationId, resendToken) {
        if (completedAutomatically) return;
        finishLoading();
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  } on FirebaseAuthException catch (error) {
    debugPrint(
      'Firebase phone request failed: ${error.code} - ${error.message}',
    );
    finishLoading();
    if (context.mounted) {
      showAppSnackBar(context, firebasePhoneAuthMessage(error));
    }
  } catch (error) {
    debugPrint('Firebase phone request failed: $error');
    finishLoading();
    if (context.mounted) {
      showAppSnackBar(context, 'تعذر إرسال رمز التحقق الآن');
    }
  }
}

class SaudiPhoneField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final TextInputAction textInputAction;

  const SaudiPhoneField({
    super.key,
    required this.onChanged,
    this.textInputAction = TextInputAction.done,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            style: TextStyle(
              color: context.ejarzTheme.text,
              fontSize: context.sp(12.3),
              fontWeight: FontWeight.w700,
            ),
            children: const <InlineSpan>[
              TextSpan(text: 'رقم الجوال'),
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 74,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.ejarzTheme.border),
                ),
                child: const Text(
                  '+966',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  onChanged: onChanged,
                  validator: validateSaudiMobile,
                  keyboardType: TextInputType.phone,
                  textInputAction: textInputAction,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  autofillHints: const <String>[AutofillHints.telephoneNumber],
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    hintText: '5xxxxxxxx',
                    suffixIcon: Icon(Icons.phone_android_rounded, size: 19),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _phoneInput = '';
  bool _loading = false;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _otpRetryCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _login() async {
    if (_cooldownSeconds > 0) {
      showAppSnackBar(context, _otpCooldownMessage(_cooldownSeconds));
      return;
    }
    final phone = normalizeSaudiMobile(_phoneInput);
    if (!_formKey.currentState!.validate() || phone == null) return;

    if (!kEjarzDemoMode) {
      setState(() => _loading = true);
      try {
        final registration = await checkPhoneRegistration(phone);
        if (!mounted) return;
        if (!registration.registered) {
          showAppSnackBar(context, 'الرقم غير مسجل، أنشئ حسابًا جديدًا أولًا');
          return;
        }
        if (registration.blocked) {
          showAppSnackBar(context, 'هذا الحساب موقوف، تواصل مع الدعم');
          return;
        }
      } catch (error) {
        if (mounted) showAppSnackBar(context, phoneAuthFlowMessage(error));
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    _startCooldown();
    await requestSaudiOtp(
      context: context,
      phone: phone,
      onStarted: () {
        if (mounted) setState(() => _loading = true);
      },
      onFinished: () {
        if (mounted) setState(() => _loading = false);
      },
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OtpScreen(
              phone: phone.localDisplay,
              e164Phone: phone.e164,
              verificationId: verificationId,
              resendToken: resendToken,
              flow: AuthFlow.login,
            ),
          ),
        );
      },
      onAutoVerified: (credential) => _completeVerifiedLogin(
        credential: credential,
        phone: phone,
      ),
    );
  }

  Future<void> _completeVerifiedLogin({
    required PhoneAuthCredential credential,
    required SaudiPhoneNumber phone,
  }) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      final profile = await finalizePhoneAuthFlow(
        flow: AuthFlow.login,
        phone: phone.e164,
      );
      if (!mounted) return;
      AppScope.of(context, listen: false).login(
        name: profile.name,
        phone: profile.phone,
        email: profile.email,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseFunctionsException catch (error) {
      await FirebaseAuth.instance.signOut();
      if (mounted) showAppSnackBar(context, phoneAuthFlowMessage(error));
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadingOverlay(
          visible: _loading,
          child: ResponsiveContent(
            maxWidth: 520,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(
                    child: Image(
                      image: AssetImage('assets/images/ejarz_splash_logo.png'),
                      height: 44,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'مرحبًا بك',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kEjarzDemoMode
                        ? 'أدخل رقم جوال لتجربة مسار التحقق كما سيظهر للمستخدم. لن يتم إرسال SMS حقيقي في النسخة التجريبية.'
                        : 'أدخل رقم جوالك وسنرسل رمز تحقق للدخول إلى حسابك.',
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(14),
                    ),
                  ),
                  if (kEjarzDemoMode) ...<Widget>[
                    const SizedBox(height: 12),
                    const InfoBanner(
                      text:
                          'نسخة تجريبية: سيظهر مسار رمز التحقق كاملًا، ويمكنك إدخال أي رمز مكون من 6 أرقام.',
                      icon: Icons.visibility_outlined,
                      color: AppColors.orange,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SaudiPhoneField(
                    onChanged: (value) => _phoneInput = value,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: _cooldownSeconds > 0
                        ? _otpCooldownLabel(_cooldownSeconds)
                        : 'إرسال رمز التحقق',
                    icon: Icons.sms_outlined,
                    loading: _loading,
                    onPressed: _cooldownSeconds > 0 || _loading ? null : _login,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'مستخدم جديد؟',
                          style: TextStyle(color: context.ejarzTheme.muted),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RegisterScreen(),
                      ),
                    ),
                    child: const Text('إنشاء حساب جديد'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'باستخدام التطبيق أنت توافق على الشروط والأحكام وسياسة الخصوصية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.ejarzTheme.muted,
                      fontSize: context.sp(11.5),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const LegalLinksRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _phoneInput = '';
  String _email = '';
  bool _accept = false;
  bool _loading = false;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _otpRetryCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _submit() async {
    if (_cooldownSeconds > 0) {
      showAppSnackBar(context, _otpCooldownMessage(_cooldownSeconds));
      return;
    }
    final phone = normalizeSaudiMobile(_phoneInput);
    if (!_formKey.currentState!.validate() || phone == null) return;
    if (!_accept) {
      showAppSnackBar(context, 'يجب الموافقة على الشروط والأحكام');
      return;
    }
    if (kEjarzDemoMode) {
      showAppSnackBar(
        context,
        'هذه نسخة تجريبية فقط. استخدم تسجيل الدخول لتجربة التطبيق.',
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final registration = await checkPhoneRegistration(phone);
      if (!mounted) return;
      if (registration.registered) {
        showAppSnackBar(context, 'الرقم موجود من قبل، استخدم تسجيل الدخول');
        return;
      }
    } catch (error) {
      if (mounted) showAppSnackBar(context, phoneAuthFlowMessage(error));
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    _startCooldown();
    await requestSaudiOtp(
      context: context,
      phone: phone,
      onStarted: () {
        if (mounted) setState(() => _loading = true);
      },
      onFinished: () {
        if (mounted) setState(() => _loading = false);
      },
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OtpScreen(
              phone: phone.localDisplay,
              e164Phone: phone.e164,
              verificationId: verificationId,
              resendToken: resendToken,
              flow: AuthFlow.register,
              name: _name.trim(),
              email: _email.trim(),
            ),
          ),
        );
      },
      onAutoVerified: (credential) => _completeVerifiedRegistration(
        credential: credential,
        phone: phone,
      ),
    );
  }

  Future<void> _completeVerifiedRegistration({
    required PhoneAuthCredential credential,
    required SaudiPhoneNumber phone,
  }) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      final profile = await finalizePhoneAuthFlow(
        flow: AuthFlow.register,
        phone: phone.e164,
        name: _name.trim(),
        email: _email.trim(),
      );
      if (!mounted) return;
      AppScope.of(context, listen: false).login(
        name: profile.name,
        phone: profile.phone,
        email: profile.email,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseFunctionsException catch (error) {
      await FirebaseAuth.instance.signOut();
      if (mounted) showAppSnackBar(context, phoneAuthFlowMessage(error));
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: LoadingOverlay(
          visible: _loading,
          child: ResponsiveContent(
            maxWidth: 560,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const AppPageHeader(
                    title: 'أنشئ حسابك في عقود برو',
                    subtitle:
                        'أدخل بياناتك الأساسية للبدء في إنشاء العقود ومتابعتها.',
                    icon: Icons.person_add_alt_1_rounded,
                  ),
                  if (kEjarzDemoMode) ...<Widget>[
                    const SizedBox(height: 12),
                    const InfoBanner(
                      text:
                          'إنشاء الحساب غير مفعّل في النسخة التجريبية. استخدم تسجيل الدخول للدخول إلى تجربة جاهزة.',
                      icon: Icons.info_outline_rounded,
                      color: AppColors.orange,
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'الاسم الكامل',
                    hint: 'أدخل اسمك الكامل',
                    icon: Icons.person_outline_rounded,
                    required: true,
                    onChanged: (value) => _name = value,
                    validator: (value) =>
                        value == null || value.trim().length < 3
                            ? 'أدخل الاسم الكامل'
                            : null,
                  ),
                  const SizedBox(height: 15),
                  SaudiPhoneField(
                    onChanged: (value) => _phoneInput = value,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 15),
                  AppTextField(
                    label: 'البريد الإلكتروني',
                    hint: 'name@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    required: true,
                    onChanged: (value) => _email = value,
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return 'أدخل بريدًا إلكترونيًا صحيحًا';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),
                  CheckboxListTile(
                    value: _accept,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setState(() => _accept = value ?? false),
                    title: const Text(
                      'أوافق على الشروط والأحكام وسياسة الخصوصية',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: kEjarzDemoMode
                        ? 'العودة إلى تسجيل الدخول'
                        : _cooldownSeconds > 0
                            ? _otpCooldownLabel(_cooldownSeconds)
                            : 'إنشاء الحساب',
                    icon: kEjarzDemoMode
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    loading: _loading,
                    onPressed: _loading
                        ? null
                        : kEjarzDemoMode
                            ? () => Navigator.of(context).pop()
                            : _cooldownSeconds > 0
                                ? null
                                : _submit,
                  ),
                  const SizedBox(height: 10),
                  const LegalLinksRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  final String phone;
  final String e164Phone;
  final String verificationId;
  final int? resendToken;
  final AuthFlow flow;
  final String name;
  final String email;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.e164Phone,
    required this.verificationId,
    this.resendToken,
    required this.flow,
    this.name = '',
    this.email = '',
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  late String _verificationId;
  int? _resendToken;
  int _seconds = kEjarzDemoMode ? 0 : 60;
  Timer? _timer;
  bool _verifying = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    if (!kEjarzDemoMode) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_seconds <= 1) {
        timer.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds -= 1);
      }
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    if (kEjarzDemoMode) {
      setState(() => _seconds = 0);
      return;
    }
    setState(() => _seconds = 60);
    _startTimer();
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      showAppSnackBar(context, 'أدخل رمز التحقق المكون من 6 أرقام');
      return;
    }
    setState(() => _verifying = true);
    if (kEjarzDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (kEjarzFirebaseDemoMode) {
        try {
          await FirebaseBootstrap.ready;
          if (!FirebaseBootstrap.initialized) {
            throw StateError('Firebase is not initialized');
          }
          if (FirebaseAuth.instance.currentUser == null) {
            await FirebaseAuth.instance.signInAnonymously();
          }
        } catch (error) {
          debugPrint(
              'Firebase demo session unavailable; using local demo: $error');
        }
      }
      if (!mounted) return;
      setState(() => _verifying = false);
      await _finishLogin();
      return;
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      setState(() => _verifying = false);
      await _finishLogin();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        showAppSnackBar(context, firebasePhoneAuthMessage(error));
      }
    } on FirebaseFunctionsException catch (error) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        showAppSnackBar(context, phoneAuthFlowMessage(error));
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'تعذر تأكيد رمز التحقق الآن');
      }
    } finally {
      if (mounted && _verifying) {
        setState(() => _verifying = false);
      }
    }
  }

  Future<void> _resendCode() async {
    if (_seconds != 0 || _resending) return;
    final phone = normalizeSaudiMobile(widget.e164Phone);
    if (phone == null) {
      showAppSnackBar(context, 'رقم الجوال غير صحيح');
      return;
    }

    await requestSaudiOtp(
      context: context,
      phone: phone,
      forceResendingToken: _resendToken,
      onStarted: () {
        if (mounted) setState(() => _resending = true);
      },
      onFinished: () {
        if (mounted) setState(() => _resending = false);
      },
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        _otpController.clear();
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
        });
        _resetTimer();
        showAppSnackBar(
          context,
          kEjarzDemoMode
              ? 'يمكنك إدخال أي رمز تجريبي مكون من 6 أرقام'
              : 'تم إرسال رمز تحقق جديد',
        );
      },
      onAutoVerified: _completeAutoVerification,
    );
  }

  Future<void> _completeAutoVerification(
    PhoneAuthCredential credential,
  ) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      await _finishLogin();
    } on FirebaseFunctionsException catch (error) {
      await FirebaseAuth.instance.signOut();
      if (mounted) showAppSnackBar(context, phoneAuthFlowMessage(error));
    }
  }

  Future<void> _finishLogin() async {
    final profile = await finalizePhoneAuthFlow(
      flow: widget.flow,
      phone: widget.e164Phone,
      name: widget.name,
      email: widget.email,
    );
    if (!mounted) return;
    AppScope.of(context, listen: false).login(
      name: profile.name,
      phone: profile.phone,
      email: profile.email,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق من الجوال')),
      body: SafeArea(
        child: LoadingOverlay(
          visible: _verifying || _resending,
          child: ResponsiveContent(
            maxWidth: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 18),
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sms_outlined,
                    color: AppColors.primary,
                    size: 45,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'أدخل رمز التحقق',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  kEjarzDemoMode
                      ? 'هذه شاشة تحقق تجريبية للرقم ${widget.phone}.'
                      : 'أرسلنا رمزًا مكونًا من 6 أرقام إلى ${widget.phone}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.ejarzTheme.muted,
                    height: 1.6,
                  ),
                ),
                if (kEjarzDemoMode) ...<Widget>[
                  const SizedBox(height: 12),
                  const InfoBanner(
                    text:
                        'أدخل أي 6 أرقام، مثال: 123456. لن يتم الاتصال بخدمة Firebase OTP في هذه النسخة.',
                    icon: Icons.password_rounded,
                    color: AppColors.orange,
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    fontSize: context.sp(22),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 9,
                  ),
                  decoration: const InputDecoration(
                    hintText: '••••••',
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'تأكيد الرمز',
                  icon: Icons.verified_outlined,
                  loading: _verifying,
                  onPressed: _verifying ? null : _verify,
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _seconds == 0 && !_resending ? _resendCode : null,
                  child: Text(
                    kEjarzDemoMode
                        ? 'إعادة عرض الرمز التجريبي'
                        : _seconds == 0
                            ? 'إعادة إرسال الرمز'
                            : 'إعادة الإرسال بعد $_seconds ثانية',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
