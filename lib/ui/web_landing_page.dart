import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WebLandingPage extends StatefulWidget {
  const WebLandingPage({super.key});

  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage> {
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _workflowKey = GlobalKey();

  void _goToApp() {
    Navigator.of(context).pushNamed('/app');
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F1E8),
        body: Stack(
          children: [
            const Positioned.fill(child: _LandingBackground()),
            SafeArea(
              bottom: false,
              child: SelectionArea(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: Column(
                          children: [
                            _TopBar(
                              onFeaturesTap: () => _scrollTo(_featuresKey),
                              onWorkflowTap: () => _scrollTo(_workflowKey),
                              onLoginTap: _goToApp,
                            ),
                            const SizedBox(height: 18),
                            _Reveal(
                              delay: const Duration(milliseconds: 80),
                              child: _HeroSection(
                                onPrimaryTap: _goToApp,
                                onSecondaryTap: () => _scrollTo(_featuresKey),
                              ),
                            ),
                            const SizedBox(height: 34),
                            _Reveal(
                              delay: const Duration(milliseconds: 180),
                              child: _SectionFrame(
                                key: _featuresKey,
                                eyebrow: 'المزايا',
                                title:
                                    'كل ما يحتاجه مدير الأملاك في مساحة واحدة.',
                                description:
                                    'Ejarz Pro يجمع إدارة العقارات والعقود والتحصيل والصيانة والتنبيهات والتقارير في واجهة عربية واضحة ومباشرة.',
                                child: const _FeaturesGrid(),
                              ),
                            ),
                            const SizedBox(height: 26),
                            _Reveal(
                              delay: const Duration(milliseconds: 260),
                              child: _SectionFrame(
                                key: _workflowKey,
                                eyebrow: 'آلية العمل',
                                title:
                                    'مسار عملي سريع من الإدخال حتى المتابعة اليومية.',
                                description:
                                    'الصفحة الرئيسية في النظام مبنية لتختصر الدورة التشغيلية بدل توزيعها بين أدوات متفرقة.',
                                child: const _WorkflowStrip(),
                              ),
                            ),
                            const SizedBox(height: 26),
                            _Reveal(
                              delay: const Duration(milliseconds: 340),
                              child: _ClosingCallout(onTap: _goToApp),
                            ),
                            const SizedBox(height: 18),
                            const _Footer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onFeaturesTap,
    required this.onWorkflowTap,
    required this.onLoginTap,
  });

  final VoidCallback onFeaturesTap;
  final VoidCallback onWorkflowTap;
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE4DBCC)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 32,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F2EE),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Image.asset(
                        'assets/images/home/logo_mark.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ejarz Pro',
                          style: GoogleFonts.cairo(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF12252A),
                          ),
                        ),
                        Text(
                          'منصة إدارة الأملاك والعقود',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5F6E74),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                _TopBarLink(label: 'المزايا', onTap: onFeaturesTap),
                const SizedBox(width: 6),
                _TopBarLink(label: 'آلية العمل', onTap: onWorkflowTap),
                const SizedBox(width: 12),
              ],
              FilledButton(
                onPressed: onLoginTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E766E),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 14 : 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  compact ? 'الدخول' : 'الدخول إلى المنصة',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBarLink extends StatelessWidget {
  const _TopBarLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF1A3340),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        return Container(
          padding: EdgeInsets.all(isWide ? 28 : 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF7F2E9), Color(0xFFFDFBF6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: const Color(0xFFE7DED1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 11,
                      child: _HeroCopy(
                        onPrimaryTap: onPrimaryTap,
                        onSecondaryTap: onSecondaryTap,
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Expanded(flex: 9, child: _ShowcasePanel()),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroCopy(
                      onPrimaryTap: onPrimaryTap,
                      onSecondaryTap: onSecondaryTap,
                    ),
                    const SizedBox(height: 24),
                    const _ShowcasePanel(),
                  ],
                ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE7F2EE),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFCCE5DC)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: Color(0xFF0E766E)),
              const SizedBox(width: 8),
              Text(
                'صفحة هبوط خفيفة تقود مباشرة إلى النظام',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF16433F),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Ejarz Pro يمنح إدارة الأملاك شكلاً أوضح وأهدأ وأكثر احترافية.',
          style: GoogleFonts.cairo(
            fontSize: compact ? 34 : 44,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF12252A),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'واجهة تعريفية سريعة لزوار الموقع، مع مسار واضح للدخول إلى لوحة إدارة العقارات والعقود والتحصيل والصيانة والتقارير.',
          style: GoogleFonts.cairo(
            fontSize: compact ? 17 : 19,
            height: 1.75,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF516067),
          ),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PillTag(label: 'إدارة العقارات والوحدات'),
            _PillTag(label: 'العقود والتحصيل'),
            _PillTag(label: 'الصيانة والخدمات'),
            _PillTag(label: 'التقارير والتنبيهات'),
          ],
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onPrimaryTap,
              icon: const Icon(Icons.login_rounded),
              label: Text(
                'الدخول إلى المنصة',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF12252A),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onSecondaryTap,
              icon: const Icon(Icons.south_west_rounded),
              label: Text(
                'استكشف المزايا',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0E766E),
                side: const BorderSide(color: Color(0xFFBFD8D2)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShowcasePanel extends StatelessWidget {
  const _ShowcasePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 520),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16363C), Color(0xFF0A222B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 36,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -20,
            right: -20,
            bottom: -10,
            child: Opacity(
              opacity: 0.23,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.06, end: 1.0),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Image.asset(
                  'assets/images/home/riyadh_skyline.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Image.asset(
                      'assets/images/home/logo_mark.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ejarz Pro Platform',
                          style: GoogleFonts.cairo(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'تشغيل يومي أنظف لفرق إدارة الأملاك',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEFBF5).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'واجهة واحدة لمتابعة العمليات الأساسية دون تشتيت.',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF12252A),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ShowcaseMetric(
                          title: 'العقارات',
                          subtitle: 'الوحدات، الملاك، الأرشفة',
                          icon: Icons.apartment_rounded,
                          accent: Color(0xFFE9F2FB),
                        ),
                        _ShowcaseMetric(
                          title: 'العقود',
                          subtitle: 'إنشاء، تجديد، إنهاء',
                          icon: Icons.description_rounded,
                          accent: Color(0xFFF8EEDB),
                        ),
                        _ShowcaseMetric(
                          title: 'الصيانة',
                          subtitle: 'طلبات وخدمات دورية',
                          icon: Icons.build_circle_rounded,
                          accent: Color(0xFFE8F5EE),
                        ),
                        _ShowcaseMetric(
                          title: 'التقارير',
                          subtitle: 'ملخص مالي وتشغيلي',
                          icon: Icons.insights_rounded,
                          accent: Color(0xFFF3E9F8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F2E7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Image.asset(
                              'assets/images/ejarz_pro_ai_bot_icon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'مساعد ذكي داخل النظام',
                                  style: GoogleFonts.cairo(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'للوصول السريع إلى الشاشات والبيانات التشغيلية.',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.72),
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShowcaseMetric extends StatelessWidget {
  const _ShowcaseMetric({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEE4D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF17323A)),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF12252A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF627177),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE8DED0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0E766E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 31,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF12252A),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.cairo(
              fontSize: 18,
              height: 1.7,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5B6A70),
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _FeatureCard(
          iconAsset: 'assets/images/home/properties.png',
          title: 'إدارة العقارات والوحدات',
          body:
              'تنظيم المباني والوحدات ووثائق الملكية وحالة الإشغال من نفس المسار.',
          accent: Color(0xFFE8F3F2),
        ),
        _FeatureCard(
          iconAsset: 'assets/images/home/contract_doc.png',
          title: 'العقود والتحصيل',
          body:
              'متابعة إنشاء العقود وتجديدها وإنهائها وربطها بالتدفقات المالية.',
          accent: Color(0xFFF7EEDB),
        ),
        _FeatureCard(
          iconAsset: 'assets/images/home/services.png',
          title: 'الصيانة والخدمات الدورية',
          body:
              'تسجيل البلاغات ومتابعة الطلبات والخدمات المرتبطة بكل عقار أو وحدة.',
          accent: Color(0xFFE8F5EE),
        ),
        _FeatureCard(
          iconAsset: 'assets/images/home/reports.png',
          title: 'تقارير تشغيلية ومالية',
          body:
              'رؤية أوضح للملخصات اليومية والتقارير المالية ومؤشرات النشاط المهمة.',
          accent: Color(0xFFEAF0F8),
        ),
        _FeatureCard(
          iconAsset: 'assets/images/home/bell.png',
          title: 'تنبيهات وإشعارات',
          body:
              'التقاط الاستحقاقات والملاحظات والتنبيهات التشغيلية في مركز واحد.',
          accent: Color(0xFFFCEBD9),
        ),
        _FeatureCard(
          iconAsset: 'assets/images/ejarz_pro_ai_bot_icon.png',
          title: 'مساعد ذكي',
          body:
              'يساعد على الوصول إلى البيانات والشاشات التشغيلية بسرعة أكبر داخل المنصة.',
          accent: Color(0xFFF2EAF7),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.iconAsset,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String iconAsset;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 360 ? constraints.maxWidth : 360.0;
        return Container(
          width: width,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFEFBF6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFECE1D4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Image.asset(iconAsset, fit: BoxFit.contain),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF12252A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  height: 1.75,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5C6A71),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkflowStrip extends StatelessWidget {
  const _WorkflowStrip();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _WorkflowCard(
          step: '01',
          title: 'أضف العقار أو الوحدة',
          body:
              'ابدأ من سجل واضح للعقارات والوحدات والبيانات الأساسية المرتبطة بها.',
          icon: Icons.domain_add_rounded,
        ),
        _WorkflowCard(
          step: '02',
          title: 'اربط العقود والتحصيل',
          body:
              'أنشئ العقود وتابع مواعيدها ومدفوعاتها واستحقاقاتها من نفس البيئة.',
          icon: Icons.receipt_long_rounded,
        ),
        _WorkflowCard(
          step: '03',
          title: 'تابع الصيانة والتقارير',
          body:
              'راقب التنفيذ اليومي والخدمات الدورية والملخصات التشغيلية دون تنقل مرهق.',
          icon: Icons.track_changes_rounded,
        ),
      ],
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.step,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String step;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 360 ? constraints.maxWidth : 360.0;
        return Container(
          width: width,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDFBF6), Color(0xFFF2EEE5)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7DCCA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF12252A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    step,
                    style: GoogleFonts.cairo(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0E766E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF12252A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.75,
                  color: const Color(0xFF5C6A71),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClosingCallout extends StatelessWidget {
  const _ClosingCallout({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14353A), Color(0xFF10242B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 880;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'واجهة عامة للزائر، ودخول واضح للفريق الداخلي.',
                style: GoogleFonts.cairo(
                  fontSize: compact ? 28 : 33,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'يمكن استخدام الصفحة الرئيسية لتعريف الزائر بالمنصة، ثم توجيهه إلى لوحة العمل عندما يكون ذلك مطلوبًا.',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  height: 1.75,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.74),
                ),
              ),
            ],
          );

          final cta = FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.arrow_outward_rounded),
            label: Text(
              'الدخول الآن',
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF7E9CF),
              foregroundColor: const Color(0xFF11242A),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 18),
                cta,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 18),
              cta,
            ],
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 6),
      child: Row(
        children: [
          Text(
            'www.ejarzpro.sa',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF22353C),
            ),
          ),
          const Spacer(),
          Text(
            'Ejarz Pro',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF66757B),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8DED2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF243840),
        ),
      ),
    );
  }
}

class _LandingBackground extends StatelessWidget {
  const _LandingBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8F2E7), Color(0xFFE6F0EC), Color(0xFFF4EFE7)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _GlowCircle(
              size: 320,
              color: Color(0x2217A398),
            ),
          ),
          Positioned(
            left: -90,
            top: 260,
            child: _GlowCircle(
              size: 240,
              color: Color(0x22D4A65A),
            ),
          ),
          Positioned(
            bottom: -110,
            right: 180,
            child: _GlowCircle(
              size: 280,
              color: Color(0x221E6B7C),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 90,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.05),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
