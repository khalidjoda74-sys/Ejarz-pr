import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/demo_config.dart';
import '../core/phone_session.dart';
import '../core/phone_code_verifier.dart';
import '../core/theme.dart';
import '../core/web_phone_auth.dart';
import '../widgets/common.dart';
import '../widgets/auth_reference.dart';
import 'auth.dart'
    show
        SaudiPhoneField,
        SaudiPhoneNumber,
        normalizeSaudiMobile,
        requestSaudiOtp,
        firebasePhoneAuthMessage;

Future<void> openAuthSupport(BuildContext context) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final dark = Theme.of(dialogContext).brightness == Brightness.dark;
        final green = dark ? const Color(0xFF80D4B6) : authGreen;
        final ink = dark ? const Color(0xFFF0F6F3) : authInk;
        final muted = dark ? const Color(0xFFB1C1B9) : authMuted;
        return Dialog(
          backgroundColor: dark ? const Color(0xFF172B24) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: SingleChildScrollView(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: DefaultTextStyle(
                    style: TextStyle(fontFamily: 'Dubai', color: ink),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: green.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.mail_outline_rounded,
                                size: 22, color: green)),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('يسعدنا مساعدتك',
                                style: TextStyle(
                                    fontSize: 18,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            tooltip: 'إغلاق',
                            color: muted,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 40),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 19)),
                      ]),
                      const SizedBox(height: 10),
                      Text('تواصل معنا عبر البريد الإلكتروني الرسمي',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, height: 1.5, color: muted)),
                      const SizedBox(height: 12),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: green.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: green.withValues(alpha: .16))),
                          child: Row(children: [
                            Expanded(
                                child: SelectableText('Info@aqdak.sa',
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontFamily: 'Dubai',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: green))),
                            IconButton(
                                tooltip: 'نسخ البريد الإلكتروني',
                                color: green,
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                onPressed: () async {
                                  await Clipboard.setData(const ClipboardData(
                                      text: 'Info@aqdak.sa'));
                                  if (dialogContext.mounted) {
                                    showAppSnackBar(dialogContext,
                                        'تم نسخ البريد الإلكتروني');
                                  }
                                }),
                          ])),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: authGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(42),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 9),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              onPressed: () async {
                                try {
                                  if (await launchUrl(Uri(
                                      scheme: 'mailto',
                                      path: 'Info@aqdak.sa'))) {
                                    return;
                                  }
                                } catch (_) {}
                                if (dialogContext.mounted) {
                                  showAppSnackBar(dialogContext,
                                      'تعذر فتح تطبيق البريد. يمكنك نسخ البريد والتواصل معنا');
                                }
                              },
                              child: const Text('إرسال بريد إلكتروني',
                                  style: TextStyle(
                                      fontFamily: 'Dubai',
                                      fontSize: 14,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600)))),
                    ])),
              ))),
        );
      });
}

class AuthPanel extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool back;
  final bool centerHeader;
  const AuthPanel(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.children,
      this.back = false,
      this.centerHeader = false});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: back ? AppBar(title: const Text('التحقق من الجوال')) : null,
        body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: .08),
                  Theme.of(context).scaffoldBackgroundColor,
                  AppColors.secondary.withValues(alpha: .04)
                ])),
            child: SafeArea(
                child: ResponsiveContent(
                    maxWidth: 520,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 28),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: BrandLogo(markSize: 46)),
                          const SizedBox(height: 30),
                          AppCard(
                              padding: const EdgeInsets.all(24),
                              child: Material(
                                  type: MaterialType.transparency,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Align(
                                            alignment: centerHeader
                                                ? Alignment.center
                                                : AlignmentDirectional
                                                    .centerStart,
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.all(15),
                                                decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: .10),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20)),
                                                child: Icon(icon,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    size: 30))),
                                        const SizedBox(height: 22),
                                        Text(title,
                                            textAlign: centerHeader
                                                ? TextAlign.center
                                                : TextAlign.start,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium),
                                        const SizedBox(height: 10),
                                        Text(subtitle,
                                            textAlign: centerHeader
                                                ? TextAlign.center
                                                : TextAlign.start,
                                            style: TextStyle(
                                                color: context.ejarzTheme.muted,
                                                height: 1.7)),
                                        const SizedBox(height: 26),
                                        ...children,
                                      ]))),
                          const SizedBox(height: 20),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined,
                                    size: 16, color: context.ejarzTheme.muted),
                                const SizedBox(width: 6),
                                Text('عقدك يبدأ بخطوة',
                                    style: TextStyle(
                                        color: context.ejarzTheme.muted)),
                              ]),
                        ])))),
      );
}

class AuthError extends StatelessWidget {
  final String message;
  const AuthError(this.message, {super.key});
  @override
  Widget build(BuildContext context) => message.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
              liveRegion: true,
              child: InfoBanner(
                  text: message,
                  icon: Icons.info_outline,
                  color: AppColors.red)));
}

class LoginScreen extends StatefulWidget {
  final bool reauthenticate;
  const LoginScreen({super.key, this.reauthenticate = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _busy = false;
  String _error = '';
  String? _expectedUid;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    if (widget.reauthenticate) {
      final user = FirebaseAuth.instance.currentUser;
      _expectedUid = user?.uid;
      _phone.text = user?.phoneNumber ?? '';
    }
  }

  Future<void> _acceptCredential(PhoneAuthCredential credential) async {
    if (widget.reauthenticate) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != _expectedUid) {
        throw StateError('تغير الحساب');
      }
      await user.reauthenticateWithCredential(credential);
      await user.getIdToken(true);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      await AppScope.of(context, listen: false).confirmPhoneSignIn(() async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _send() async {
    if (_busy || (!_form.currentState!.validate())) return;
    if (widget.reauthenticate && _expectedUid == null) {
      setState(() => _error = 'أعد تسجيل الدخول قبل حذف الحساب');
      return;
    }
    final phone = normalizeSaudiMobile(_phone.text);
    if (phone == null) return;
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _error = '';
    });
    await requestSaudiOtp(
        context: context,
        phone: phone,
        isActive: () => mounted && attempt == _attempt,
        onStarted: () {},
        onFinished: () {
          if (mounted && attempt == _attempt) setState(() => _busy = false);
        },
        onError: (message) {
          if (mounted) setState(() => _error = message);
        },
        onAutoVerified: _acceptCredential,
        onCodeSent: (verificationId, resendToken) async {
          if (!mounted || attempt != _attempt) return;
          _attempt++;
          setState(() => _busy = false);
          final verified = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                  builder: (_) => OtpScreen(
                      phone: phone,
                      verificationId: verificationId,
                      resendToken: resendToken,
                      expectedUid:
                          widget.reauthenticate ? _expectedUid : null)));
          if (!mounted) return;
          _attempt++;
          if (widget.reauthenticate && verified == true) {
            Navigator.of(context).pop(true);
          }
        });
  }

  @override
  void dispose() {
    _attempt++;
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthReferencePanel(
        verification: widget.reauthenticate,
        busy: _busy,
        onSupport: () => openAuthSupport(context),
        title:
            widget.reauthenticate ? 'أكد ملكيتك للحساب' : 'مرحبًا بك في عقدك',
        subtitle: widget.reauthenticate
            ? 'قبل حذف حسابك، سنرسل رمزًا إلى رقم جوالك المسجل للتحقق من هويتك.'
            : 'أدخل رقم جوالك لتسجيل الدخول أو إنشاء حساب جديد.\nسيتم إرسال رمز التحقق إلى جوالك دون الحاجة إلى كلمة مرور.',
        children: [
          Form(
              key: _form,
              child: AutofillGroup(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    if (widget.reauthenticate)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(_phone.text,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge))
                    else
                      AbsorbPointer(
                          absorbing: _busy,
                          child: SaudiPhoneField(
                              referenceStyle: true,
                              controller: _phone,
                              onChanged: (_) {
                                if (_error.isNotEmpty) {
                                  setState(() => _error = '');
                                }
                              })),
                    const SizedBox(height: 20),
                    AuthError(_error),
                    AuthReferenceButton(
                        label: widget.reauthenticate
                            ? 'إرسال رمز التحقق'
                            : 'متابعة',
                        loading: _busy,
                        onPressed: _busy ? null : _send),
                    const SizedBox(height: 14),
                    AuthSupportLink(onPressed: () => openAuthSupport(context)),
                  ])))
        ],
      );
}

class OtpScreen extends StatefulWidget {
  final PhoneCodeVerifier verifier;
  final SaudiPhoneNumber phone;
  final String verificationId;
  final int? resendToken;
  final String? expectedUid;
  const OtpScreen(
      {super.key,
      required this.phone,
      required this.verificationId,
      this.resendToken,
      this.expectedUid,
      this.verifier = const PhoneCodeVerifier()});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  late String _verificationId;
  int? _resendToken;
  Timer? _timer;
  DateTime _resendAt = DateTime.now();
  int _seconds = 60, _attempt = 0;
  bool _busy = false;
  bool _phoneVerified = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _cooldown();
  }

  void _cooldown() {
    _timer?.cancel();
    _resendAt = DateTime.now().add(const Duration(seconds: 60));
    _seconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds =
          (_resendAt.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil()
              .clamp(0, 60));
      if (_seconds == 0) timer.cancel();
    });
  }

  void _verified() {
    if (!mounted) return;
    if (widget.expectedUid != null) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _accept(PhoneAuthCredential credential) async {
    Future<void> accept() async {
      await widget.verifier.accept(credential,
          expectedUid: widget.expectedUid, phone: widget.phone.e164);
      _phoneVerified = true;
    }

    if (widget.expectedUid == null) {
      await AppScope.of(context, listen: false).confirmPhoneSignIn(accept);
    } else {
      await accept();
    }
    _verified();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = westernDigits(_code.text).trim();
    if (!_phoneVerified && !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'أدخل رمز التحقق المكوّن من 6 أرقام');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      if (kEjarzLocalDemoMode) {
        AppScope.of(context, listen: false).login();
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Future<void> verify() async {
          if (_phoneVerified && widget.expectedUid == null) return;
          await widget.verifier.verify(_verificationId, code,
              expectedUid: widget.expectedUid, phone: widget.phone.e164);
          _phoneVerified = true;
        }

        if (widget.expectedUid == null) {
          await AppScope.of(context, listen: false).confirmPhoneSignIn(verify);
        } else {
          await verify();
        }
        _verified();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FirebaseAuthException
            ? firebasePhoneAuthMessage(error)
            : authFlowError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0 || _busy) return;
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _error = '';
    });
    await requestSaudiOtp(
        context: context,
        phone: widget.phone,
        forceResendingToken: _resendToken,
        isActive: () => mounted && attempt == _attempt,
        onStarted: () {},
        onFinished: () {
          if (mounted && attempt == _attempt) setState(() => _busy = false);
        },
        onError: (message) {
          if (mounted) setState(() => _error = message);
        },
        onAutoVerified: _accept,
        onCodeSent: (id, token) {
          if (!mounted || attempt != _attempt) return;
          setState(() {
            _verificationId = id;
            _resendToken = token;
            _code.clear();
            _cooldown();
          });
        });
  }

  @override
  void dispose() {
    _attempt++;
    _timer?.cancel();
    WebPhoneAuth.clear(_verificationId);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AuthReferencePanel(
          verification: true,
          busy: _busy,
          onSupport: () => openAuthSupport(context),
          title: 'أدخل رمز التحقق',
          subtitle: 'أرسلنا رمزًا مكوّنًا من 6 أرقام إلى رقم جوالك.',
          children: [
            Text(widget.phone.formattedDisplay,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Dubai',
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
            if (widget.expectedUid == null)
              TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (_phoneVerified) {
                            AppScope.of(context, listen: false).logout();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  child: const Text('تعديل رقم الجوال')),
            const SizedBox(height: 10),
            const Center(
                child: SizedBox(
                    width: 50,
                    child: Divider(height: 1, color: Color(0xFFE2EAE5)))),
            const SizedBox(height: 7),
            const Text('رمز التحقق',
                style: TextStyle(
                    fontFamily: 'Dubai',
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(alignment: Alignment.center, children: [
                ExcludeSemantics(
                    child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _code,
                  builder: (context, value, _) => Row(
                      children: List.generate(
                          6,
                          (index) => Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(
                                      right: index == 5 ? 0 : 6),
                                  height: 50,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: index == value.text.length
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : (Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? const Color(0xFF405149)
                                                : const Color(0xFFE0E4E2)),
                                        width: 1.4),
                                  ),
                                  child: Text(
                                      index < value.text.length
                                          ? value.text[index]
                                          : '—',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                              fontFamily: 'Dubai',
                                              fontSize: 23,
                                              color: index < value.text.length
                                                  ? context.ejarzTheme.text
                                                  : context.ejarzTheme.muted)),
                                ),
                              ))),
                )),
                Semantics(
                    label: 'رمز التحقق المكوّن من ستة أرقام',
                    child: TextField(
                      controller: _code,
                      enabled: !_busy && !_phoneVerified,
                      showCursor: false,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => _verify(),
                      inputFormatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) =>
                            newValue.copyWith(
                                text: westernDigits(newValue.text))),
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(
                          color: Colors.transparent, fontSize: 27),
                      decoration: const InputDecoration(
                          filled: false,
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none),
                    )),
              ]),
            ),
            const SizedBox(height: 16),
            AuthError(_error),
            AuthReferenceButton(
                label: _phoneVerified ? 'إعادة المحاولة' : 'تأكيد الرمز',
                loading: _busy,
                onPressed: _busy ? null : _verify),
            const SizedBox(height: 10),
            if (!_phoneVerified)
              TextButton(
                  onPressed: _seconds == 0 && !_busy ? _resend : null,
                  child: Text(_seconds > 0
                      ? 'إعادة الإرسال بعد $_seconds ثانية'
                      : 'إعادة إرسال الرمز')),
          ]));
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  bool _accepted = false, _busy = false;
  String _error = '';
  Future<void> _complete() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'وافق على الشروط وسياسة الخصوصية للمتابعة');
      return;
    }
    final controller = AppScope.of(context, listen: false);
    final generation = controller.accountGeneration;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await callPhoneSession('completePhoneProfile', {
        'expectedUid': FirebaseAuth.instance.currentUser?.uid,
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'acceptTerms': true
      });
      if (!mounted || !controller.isCurrentAccount(generation)) return;
      await controller.retryAccountSession();
    } catch (error) {
      if (mounted) setState(() => _error = authFlowError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    try {
      if (await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _error = 'تعذر فتح الرابط الآن. حاول مجددًا.');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return AuthPanel(
      title: 'أكمل حسابك',
      centerHeader: true,
      subtitle: 'تم التحقق من رقمك. بقيت بيانات بسيطة لنبدأ معًا.',
      icon: Icons.person_outline_rounded,
      children: [
        Form(
            key: _form,
            child: AutofillGroup(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Row(children: [
                    const Icon(Icons.verified_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(controller.userPhone,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right))
                  ]),
                  const SizedBox(height: 22),
                  TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      maxLength: 100,
                      decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                          prefixIcon: Icon(Icons.person_outline),
                          counterText: ''),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'أدخل اسمًا من 3 أحرف على الأقل'
                          : null),
                  const SizedBox(height: 18),
                  TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      validator: optionalEmailError,
                      maxLength: 254,
                      decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني (اختياري)',
                          prefixIcon: Icon(Icons.mail_outline),
                          counterText: '')),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                      value: _accepted,
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _accepted = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                          'أوافق على الشروط والأحكام وسياسة الخصوصية')),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: () => _open(controller.legalTermsUrl),
                        child: const Text('الشروط والأحكام')),
                    TextButton(
                        onPressed: () => _open(controller.legalPrivacyUrl),
                        child: const Text('سياسة الخصوصية'))
                  ]),
                  const SizedBox(height: 12),
                  AuthError(_error),
                  PrimaryButton(
                      label: 'إنشاء حسابي',
                      loading: _busy,
                      onPressed: _busy ? null : _complete),
                  TextButton(
                      onPressed: _busy ? null : controller.logout,
                      child: const Text('استخدام رقم آخر')),
                ])))
      ],
    );
  }
}

class SessionStatusScreen extends StatelessWidget {
  const SessionStatusScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final loading = controller.accountPhase == AccountPhase.loading ||
        !controller.preferencesLoaded;
    return AuthPanel(
        title: loading ? 'نجهّز حسابك' : 'تعذر فتح الحساب',
        subtitle: loading ? 'لحظات ونتحقق من جلستك.' : controller.sessionError,
        icon: loading ? Icons.hourglass_empty_rounded : Icons.info_outline,
        children: loading
            ? [const Center(child: CircularProgressIndicator())]
            : [
                PrimaryButton(
                    label: 'إعادة المحاولة',
                    icon: Icons.refresh,
                    onPressed: controller.retryAccountSession),
                TextButton(
                    onPressed: controller.logout,
                    child: const Text('استخدام رقم آخر')),
                TextButton(
                    onPressed: () => openAuthSupport(context),
                    child: const Text('التواصل مع الدعم')),
              ]);
  }
}
