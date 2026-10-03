import 'package:flutter/material.dart';

const authGreen = Color(0xFF007C60);
const authInk = Color(0xFF17282C);
const authMuted = Color(0xFF738087);

/// The editable phone and OTP screens share the supplied botanical artwork.
class AuthReferencePanel extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final bool verification, busy;
  final VoidCallback? onSupport;
  const AuthReferencePanel(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.children,
      this.verification = false,
      this.busy = false,
      this.onSupport});

  @override
  Widget build(BuildContext context) {
    final original = Theme.of(context);
    final dark = original.brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF0F6F3) : authInk;
    final muted = dark ? const Color(0xFFB1C1B9) : authMuted;
    final green = dark ? const Color(0xFF80D4B6) : authGreen;
    final theme = original.copyWith(
      textTheme: original.textTheme
          .apply(fontFamily: 'Dubai', bodyColor: ink, displayColor: ink),
      colorScheme: original.colorScheme.copyWith(
          primary: green,
          onSurface: ink,
          surface: dark ? const Color(0xFF172B24) : Colors.white),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: green,
              minimumSize: const Size(40, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              textStyle: const TextStyle(
                  fontFamily: 'Dubai',
                  fontSize: 14,
                  fontWeight: FontWeight.w600))),
      inputDecorationTheme: original.inputDecorationTheme.copyWith(
        fillColor: dark ? const Color(0xFF172B24) : Colors.white,
        hintStyle: TextStyle(fontFamily: 'Dubai', color: muted, fontSize: 16),
        labelStyle: TextStyle(fontFamily: 'Dubai', color: ink, fontSize: 15),
        suffixIconColor: muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color:
                    dark ? const Color(0xFF405149) : const Color(0xFFE0E4E2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color:
                    dark ? const Color(0xFF405149) : const Color(0xFFE0E4E2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: green, width: 1.2)),
      ),
    );
    return Theme(
        data: theme,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor:
              dark ? const Color(0xFF10251D) : const Color(0xFFFAF8EF),
          body: Stack(fit: StackFit.expand, children: [
            Positioned.fill(
                child: ExcludeSemantics(
                    child: Image.asset(
                        'assets/images/auth_botanical_background.png',
                        fit: BoxFit.fill,
                        color: dark ? const Color(0xFF304B3E) : null,
                        colorBlendMode: dark ? BlendMode.multiply : null))),
            SafeArea(child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(0.0, 520.0);
              final padding = width < 380 ? 18.0 : 22.0;
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                        width: width,
                        child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                padding, verification ? 6 : 30, padding, 18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (verification) ...[
                                    SizedBox(
                                        height: 46,
                                        child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Text('التحقق من الجوال',
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: ink)),
                                              Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: IconButton(
                                                      color: ink,
                                                      tooltip: 'رجوع',
                                                      onPressed: busy
                                                          ? null
                                                          : () => Navigator.of(
                                                                  context)
                                                              .maybePop(),
                                                      icon: const Directionality(
                                                          textDirection:
                                                              TextDirection.ltr,
                                                          child: Icon(
                                                              Icons
                                                                  .arrow_forward,
                                                              size: 25)))),
                                            ])),
                                    const SizedBox(height: 28),
                                  ],
                                  Visibility(
                                      visible: !verification,
                                      maintainState: true,
                                      maintainAnimation: true,
                                      maintainSize: true,
                                      child: Center(
                                          child: SizedBox(
                                              width: 120,
                                              child: Column(children: [
                                                Image.asset(
                                                    'assets/images/aqdak_horizontal.png',
                                                    width: 120,
                                                    height: 35,
                                                    fit: BoxFit.contain,
                                                    semanticLabel: 'عقدك',
                                                    color: dark ? green : null),
                                                Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: SizedBox(
                                                        width: 84,
                                                        child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            child: Text(
                                                                'أسهل طريق لعقودك',
                                                                style: TextStyle(
                                                                    fontFamily:
                                                                        'Dubai',
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w400,
                                                                    color: dark
                                                                        ? muted
                                                                        : const Color(
                                                                            0xFF5C8180),
                                                                    fontSize:
                                                                        11.5,
                                                                    height:
                                                                        1.3))))),
                                              ])))),
                                  SizedBox(height: verification ? 20 : 28),
                                  Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: verification ? 18 : 26),
                                      decoration: BoxDecoration(
                                          color: dark
                                              ? const Color(0xF5172B24)
                                              : const Color(0xFAFFFFFF),
                                          borderRadius:
                                              BorderRadius.circular(26),
                                          border: Border.all(
                                              color: Colors.white.withValues(
                                                  alpha: dark ? .08 : .85)),
                                          boxShadow: [
                                            BoxShadow(
                                                color: const Color(0xFF44794B)
                                                    .withValues(
                                                        alpha:
                                                            dark ? .08 : .14),
                                                blurRadius: 28,
                                                offset: const Offset(0, 16))
                                          ]),
                                      child: Material(
                                          type: MaterialType.transparency,
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                if (verification) ...[
                                                  Center(
                                                      child: Container(
                                                          width: 60,
                                                          height: 60,
                                                          decoration: BoxDecoration(
                                                              color: green
                                                                  .withValues(
                                                                      alpha:
                                                                          .09),
                                                              shape: BoxShape
                                                                  .circle),
                                                          child: Icon(
                                                              Icons
                                                                  .sms_outlined,
                                                              size: 33,
                                                              color: green))),
                                                  const SizedBox(height: 5),
                                                ],
                                                Text(title,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        fontSize: verification
                                                            ? 22
                                                            : 25,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        height: 1.2,
                                                        color: verification
                                                            ? ink
                                                            : (dark
                                                                ? green
                                                                : const Color(
                                                                    0xFF004C3B)))),
                                                const SizedBox(height: 8),
                                                Text(subtitle,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        color: muted,
                                                        fontSize: 13.5,
                                                        height: verification
                                                            ? 1.5
                                                            : 1.7)),
                                                SizedBox(
                                                    height:
                                                        verification ? 12 : 22),
                                                ...children,
                                              ]))),
                                  if (verification) ...[
                                    const SizedBox(height: 14),
                                    AuthSupportLink(onPressed: onSupport),
                                  ],
                                  const SizedBox(height: 16),
                                  _AuthTrustRow(green: green, muted: muted),
                                  const SizedBox(height: 16),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                            width: 40,
                                            child: Divider(
                                                color: green.withValues(
                                                    alpha: .3))),
                                        const SizedBox(width: 14),
                                        Text('عقدك يبدأ بخطوة',
                                            style: TextStyle(
                                                color: green, fontSize: 14)),
                                        const SizedBox(width: 14),
                                        SizedBox(
                                            width: 40,
                                            child: Divider(
                                                color: green.withValues(
                                                    alpha: .3))),
                                      ]),
                                ])))),
              );
            })),
          ]),
        ));
  }
}

class AuthSupportLink extends StatelessWidget {
  final VoidCallback? onPressed;
  const AuthSupportLink({super.key, this.onPressed});
  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: onPressed,
      child: SizedBox(
          width: double.infinity,
          child: Stack(alignment: Alignment.center, children: [
            const Text('تحتاج مساعدة؟',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Dubai',
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Transform.translate(
                offset: Offset(MediaQuery.textScalerOf(context).scale(65), 0),
                child: const Icon(Icons.headset_mic_outlined, size: 21)),
          ])));
}

class AuthReferenceButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading, arrow;
  const AuthReferenceButton(
      {super.key,
      required this.label,
      this.onPressed,
      this.loading = false,
      this.arrow = false});
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
              colors: [Color(0xFF007D60), Color(0xFF259C7C)]),
          boxShadow: [
            BoxShadow(
                color: authGreen.withValues(alpha: .12),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ]),
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Text(label,
                        style: const TextStyle(
                            fontFamily: 'Dubai',
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    if (arrow) ...[
                      const SizedBox(width: 10),
                      const Directionality(
                          textDirection: TextDirection.ltr,
                          child: Icon(Icons.arrow_back, size: 23))
                    ],
                  ]),
      ));
}

class _AuthTrustRow extends StatelessWidget {
  final Color green, muted;
  const _AuthTrustRow({required this.green, required this.muted});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
          child: Row(children: [
        _item(Icons.description_outlined, 'مصمم لك', 'لإدارة عقودك بكل سهولة'),
        VerticalDivider(
            width: 12,
            indent: 18,
            endIndent: 4,
            color: green.withValues(alpha: .13)),
        _item(Icons.bolt_outlined, 'سريع وسهل', 'دخول في ثوانٍ'),
        VerticalDivider(
            width: 12,
            indent: 18,
            endIndent: 4,
            color: green.withValues(alpha: .13)),
        _item(Icons.shield_outlined, 'آمن وموثوق', 'بياناتك في أمان'),
      ]));
  Widget _item(IconData icon, String title, String detail) => Expanded(
          child: Column(children: [
        Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: green.withValues(alpha: .09), shape: BoxShape.circle),
            child: Icon(icon, color: green, size: 21)),
        const SizedBox(height: 4),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: muted,
                fontFamily: 'Dubai',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.4)),
        const SizedBox(height: 2),
        Text(detail,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: muted, fontFamily: 'Dubai', fontSize: 11, height: 1.4)),
      ]));
}
