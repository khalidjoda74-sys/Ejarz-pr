import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/demo_config.dart';
import '../core/web_phone_auth.dart';
import '../core/phone_session.dart';
export 'phone_auth_screens.dart';
import '../core/firebase_bootstrap.dart';
import '../core/theme.dart';
import '../core/runtime_config.dart';
import '../widgets/common.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (controller.preferencesLoaded &&
        controller.accountPhase != AccountPhase.loading &&
        !controller.splashCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !controller.preferencesLoaded ||
            controller.accountPhase == AccountPhase.loading) {
          return;
        }
        controller.completeSplash();
      });
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/images/aqdak_splash.png',
            width: 180,
            height: 190,
            fit: BoxFit.contain,
            semanticLabel: 'عقدك'),
      ),
    );
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

  final List<_OnboardingData> _defaultPages = const <_OnboardingData>[
    _OnboardingData(
      title: 'أنشئ عقدك بسهولة',
      subtitle:
          'أدخل بيانات العقد بخطوات واضحة، وارفع المستندات المطلوبة من جوالك.',
      icon: Icons.description_outlined,
    ),
    _OnboardingData(
      title: 'مراجعة احترافية',
      subtitle:
          'يراجع فريق عقدك بياناتك قبل إدخالها في منصة إيجار لتقليل الأخطاء والنواقص.',
      icon: Icons.fact_check_outlined,
    ),
    _OnboardingData(
      title: 'تابع العقد حتى التوثيق',
      subtitle:
          'راقب حالة طلبك لحظة بلحظة، واستلم نسخة العقد الموثق داخل التطبيق.',
      icon: Icons.verified_user_outlined,
    ),
  ];

  List<_OnboardingData> get _pages {
    final slides = AppRuntime.entries('onboardingSlides');
    return slides.isEmpty
        ? _defaultPages
        : slides
            .map((v) => _OnboardingData(
                title: '${v['title']}',
                subtitle: '${v['subtitle']}',
                icon: Icons.description_outlined))
            .toList();
  }

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
  var digits = westernDigits(raw).replaceAll(RegExp(r'\D'), '');
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

  var digits = westernDigits(input).replaceAll(RegExp(r'\D'), '');
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
    'unauthorized-domain' =>
      'رابط الموقع غير معتمد لتسجيل الدخول. استخدم الرابط الرسمي أو تواصل مع الدعم.',
    'web-context-cancelled' ||
    'popup-closed-by-user' =>
      'تم إغلاق التحقق. اضغط إرسال الرمز للمحاولة مرة أخرى.',
    'play-services-not-available' =>
      'خدمات Google Play غير متاحة أو تحتاج إلى تحديث على الجهاز',
    'captcha-check-failed' ||
    'app-not-authorized' ||
    'invalid-app-credential' =>
      kIsWeb
          ? 'تعذر إكمال التحقق الأمني. أعد المحاولة واسمح لنافذة التحقق بالظهور.'
          : 'تعذر التحقق من التطبيق. تأكد من إعدادات Firebase وSHA',
    _ => 'تعذر إتمام التحقق الآن. رمز الخطأ: ${error.code}',
  };
}

typedef OtpCodeSent = void Function(String verificationId, int? resendToken);

Future<void> requestSaudiOtp({
  required BuildContext context,
  required SaudiPhoneNumber phone,
  required VoidCallback onStarted,
  required VoidCallback onFinished,
  required OtpCodeSent onCodeSent,
  required Future<void> Function(PhoneAuthCredential credential) onAutoVerified,
  int? forceResendingToken,
  bool Function()? isActive,
  ValueChanged<String>? onError,
}) async {
  bool active() => context.mounted && (isActive?.call() ?? true);
  void fail(String message) {
    if (!active()) return;
    if (onError != null) {
      onError(message);
    } else {
      showAppSnackBar(context, message);
    }
  }

  final remaining = PhoneOtpCooldown.remaining(phone.e164);
  if (remaining > 0) {
    fail('انتظر $remaining ثانية قبل طلب رمز جديد');
    onFinished();
    return;
  }

  if (kEjarzDemoMode) {
    onStarted();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    onFinished();
    if (!active()) return;
    onCodeSent(kDemoVerificationId, null);
    return;
  }

  if (kIsWeb) {
    onStarted();
    try {
      await FirebaseBootstrap.ready;
      if (!FirebaseBootstrap.initialized) {
        throw StateError('Firebase unavailable');
      }
      await FirebaseAuth.instance.setLanguageCode('ar');
      final verificationId = await WebPhoneAuth.request(phone.e164);
      PhoneOtpCooldown.sent(phone.e164);
      if (active()) {
        onCodeSent(verificationId, null);
      } else {
        WebPhoneAuth.clear(verificationId);
      }
    } on FirebaseAuthException catch (error) {
      if (active()) {
        fail(firebasePhoneAuthMessage(error));
      }
    } catch (_) {
      if (active()) {
        fail('تعذر إرسال الرمز. تحقق من الاتصال وحاول مجددًا.');
      }
    } finally {
      onFinished();
    }
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
    await FirebaseBootstrap.ready;
    if (!FirebaseBootstrap.initialized) {
      throw StateError('Firebase unavailable');
    }
    await FirebaseAuth.instance.setLanguageCode('ar');
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.e164,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        if (!active()) return;
        completedAutomatically = true;
        try {
          await onAutoVerified(credential);
        } on FirebaseAuthException catch (error) {
          debugPrint(
            'Firebase phone auto verification failed: '
            '${error.code} - ${error.message}',
          );
          if (active()) {
            fail(firebasePhoneAuthMessage(error));
          }
        } catch (error) {
          debugPrint('Firebase phone auto verification failed: $error');
          if (active()) {
            fail('تعذر إكمال التحقق التلقائي');
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
        if (active()) {
          fail(firebasePhoneAuthMessage(error));
        }
      },
      codeSent: (verificationId, resendToken) {
        PhoneOtpCooldown.sent(phone.e164);
        if (completedAutomatically || !active()) return;
        finishLoading();
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) => finishLoading(),
    );
  } on FirebaseAuthException catch (error) {
    debugPrint(
      'Firebase phone request failed: ${error.code} - ${error.message}',
    );
    finishLoading();
    if (active()) {
      fail(firebasePhoneAuthMessage(error));
    }
  } catch (error) {
    debugPrint('Firebase phone request failed: $error');
    finishLoading();
    if (active()) {
      fail('تعذر إرسال رمز التحقق الآن');
    }
  }
}

class SaudiPhoneField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final TextInputAction textInputAction;
  final TextEditingController? controller;
  final bool referenceStyle;

  const SaudiPhoneField({
    super.key,
    required this.onChanged,
    this.controller,
    this.referenceStyle = false,
    this.textInputAction = TextInputAction.done,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: context.ejarzTheme.text,
                  fontSize: referenceStyle ? 15 : context.sp(12.3),
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
              if (referenceStyle)
                SizedBox(
                    width: 88,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF213E33)
                                  : const Color(0xFFEDF7F1),
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          side: const BorderSide(color: Color(0xFFDCE4DF)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13))),
                      onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (sheetContext) => SafeArea(
                              child: ListTile(
                                  title: const Text('المملكة العربية السعودية'),
                                  subtitle: const Text('+966',
                                      textDirection: TextDirection.ltr),
                                  trailing: const Icon(Icons.check),
                                  onTap: () => Navigator.pop(sheetContext)))),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.keyboard_arrow_down, size: 20),
                            Expanded(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('+966',
                                        style: TextStyle(
                                            fontFamily: 'Dubai',
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800))))
                          ]),
                    ))
              else
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
                  controller: controller,
                  onChanged: onChanged,
                  validator: validateSaudiMobile,
                  keyboardType: TextInputType.phone,
                  textInputAction: textInputAction,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: referenceStyle
                      ? const TextStyle(fontFamily: 'Dubai', fontSize: 17)
                      : null,
                  autofillHints: const <String>[AutofillHints.telephoneNumber],
                  inputFormatters: <TextInputFormatter>[
                    TextInputFormatter.withFunction((oldValue, newValue) =>
                        newValue.copyWith(text: westernDigits(newValue.text))),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    LengthLimitingTextInputFormatter(14),
                  ],
                  decoration: InputDecoration(
                    hintText: '5xxxxxxxx',
                    contentPadding: referenceStyle
                        ? const EdgeInsets.symmetric(
                            horizontal: 17, vertical: 11)
                        : null,
                    suffixIcon:
                        const Icon(Icons.phone_android_rounded, size: 20),
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
