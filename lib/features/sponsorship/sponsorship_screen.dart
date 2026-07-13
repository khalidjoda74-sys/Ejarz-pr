import 'package:flutter/material.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/models/sponsorship_campaign.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';

class SponsorshipScreen extends StatefulWidget {
  const SponsorshipScreen({
    super.key,
    this.initialCategory,
    this.initialScope = SponsorshipPlacementScope.categoryMajlis,
    this.onBack,
  });

  final String? initialCategory;
  final SponsorshipPlacementScope initialScope;
  final VoidCallback? onBack;

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sponsorNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _targetUrlController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _councilIdController = TextEditingController();
  final _notesController = TextEditingController();

  late SponsorshipPlacementScope _scope;
  late String _durationLabel;
  AdPlacement? _selectedPlacement;
  AdPackageOption? _selectedPackage;
  String? _selectedCategory;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _durationLabel = '3 أيام';
    _selectedCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _sponsorNameController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _targetUrlController.dispose();
    _logoUrlController.dispose();
    _councilIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final categories = _availableCategories();

    _selectedCategory ??= categories.isNotEmpty ? categories.first : null;
    final selectedPlacement = _selectedPlacement;
    final bottomPadding = widget.onBack == null ? 24.0 : sizes.bottomNavHeight + 18;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            CustomGreenHeader(
              title: 'إعلانات ورعايات',
              showBack: true,
              onBack: widget.onBack,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  sizes.horizontalPadding,
                  14,
                  sizes.horizontalPadding,
                  bottomPadding,
                ),
                children: selectedPlacement == null
                    ? _buildProducts()
                    : _buildDetails(
                        product: _productFor(selectedPlacement),
                        categories: categories,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProducts() {
    return [
      const _AdsLandingHero(),
      const SizedBox(height: 12),
      for (final product in _adProducts) ...[
        _AdProductCard(
          product: product,
          onTap: () {
            _openProduct(product);
          },
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _buildDetails({
    required _AdProductInfo product,
    required List<String> categories,
  }) {
    return [
      _DetailBackButton(onTap: _closeProduct),
      const SizedBox(height: 8),
      _AdDetailHero(product: product),
      const SizedBox(height: 12),
      _AdPlacementPreview(product: product),
      const SizedBox(height: 12),
      Text(
        'اختر الباقة',
        style: AppTextStyles.cardTitle.copyWith(
          color: AppColors.primaryDarkGreen,
          fontSize: 15,
        ),
      ),
      const SizedBox(height: 8),
      StreamBuilder<List<AdPackageOption>>(
        stream: SponsorshipRepository.instance.watchPackagesFor(product.placement),
        initialData:
            SponsorshipRepository.instance.defaultPackagesFor(product.placement),
        builder: (context, snapshot) {
          final packages = snapshot.data ??
              SponsorshipRepository.instance.defaultPackagesFor(product.placement);
          return Column(
            children: [
              for (final package in packages) ...[
                _AdPackageChoiceCard(
                  package: package,
                  selected: _selectedPackage?.id == package.id,
                  onSelect: () => _selectPackage(package),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 6),
      if (_selectedPackage != null)
        _AdRequestFormCard(
          formKey: _formKey,
          product: product,
          package: _selectedPackage!,
          sponsorNameController: _sponsorNameController,
          contactNameController: _contactNameController,
          contactPhoneController: _contactPhoneController,
          targetUrlController: _targetUrlController,
          logoUrlController: _logoUrlController,
          councilIdController: _councilIdController,
          notesController: _notesController,
          categories: categories,
          selectedCategory: _selectedCategory,
          selectedScope: _scope,
          submitting: _submitting,
          onScopeChanged: (scope) => setState(() => _scope = scope),
          onCategoryChanged: (value) => setState(() => _selectedCategory = value),
          onSubmit: _submitInterest,
        )
      else
        const _SelectPackageHint(),
    ];
  }

  Future<void> _openProduct(_AdProductInfo product) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          icon: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              product.icon,
              color: AppColors.primaryDarkGreen,
              size: 25,
            ),
          ),
          title: Text(
            product.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.primaryDarkGreen,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            _comingSoonCopy(product),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textGray,
              fontSize: 12.7,
              height: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDarkGreen,
                  foregroundColor: AppColors.cardWhite,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 12.8),
                ),
                child: const Text('تم'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _comingSoonCopy(_AdProductInfo product) {
    switch (product.placement) {
      case AdPlacement.councilSponsorship:
        return 'هذا النوع من الإعلان غير متوفر حاليًا وسيتم توفيره قريبًا بإذن الله. رعاية الفرص ستجعل إعلانك يظهر داخل الفرص المناسبة بوضوح واحتراف، مع شارة رعاية تحفظ ثقة المستخدم وتوصل علامتك للجمهور المهتم.';
      case AdPlacement.homeFeaturedCouncil:
        return 'هذا النوع من الإعلان غير متوفر حاليًا وهو قيد التجهيز. قريبًا ستتمكن من إبراز فرصة مختارة في الرئيسية بشكل واضح وجذاب، مع ظهور محترف لا يربك المستخدم ولا يخفي محتوى التطبيق.';
      case AdPlacement.homeBanner:
        return 'بنر الرئيسية غير متوفر حاليًا وسيتم توفيره قريبًا. نعمل على إطلاقه بتصميم قوي يناسب الحملات والعروض المهمة، مع ظهور واضح كإعلان رسمي وبمساحة بارزة في الرئيسية.';
    }
  }

  void _closeProduct() {
    setState(() {
      _selectedPlacement = null;
      _selectedPackage = null;
    });
  }

  void _selectPackage(AdPackageOption package) {
    setState(() {
      _selectedPackage = package;
      _durationLabel = package.durationLabel;
    });
  }

  List<String> _availableCategories() {
    final values = CouncilRepository.instance.categories
        .where((category) => category.trim().isNotEmpty && category != 'الكل')
        .toList();
    final initial = widget.initialCategory?.trim();
    if (initial != null && initial.isNotEmpty && !values.contains(initial)) {
      values.insert(0, initial);
    }
    return values;
  }

  Future<void> _submitInterest() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await AuthGuard.requireAuth(
      context,
      () async {
        setState(() => _submitting = true);
        try {
          final placement = _selectedPlacement ?? AdPlacement.councilSponsorship;
          final product = _productFor(placement);
          final package = _selectedPackage;
          final scope = _scope;
          final categoryName =
              placement != AdPlacement.councilSponsorship ||
                      scope == SponsorshipPlacementScope.allMajalis
                  ? 'كل الفرص'
              : (_selectedCategory ?? 'كل الفرص');
          final rawNotes = _notesController.text.trim();
          final notes = [
            'نوع الإعلان: ${product.title}',
            if (package != null)
              'الباقة: ${package.label} - ${package.durationLabel} - ${package.priceLabel}',
            if (rawNotes.isNotEmpty) rawNotes,
          ].join('\n');

          await SponsorshipRepository.instance.submitInterest(
            SponsorshipInterestInput(
              sponsorName: _sponsorNameController.text,
              contactName: _contactNameController.text,
              contactPhone: _contactPhoneController.text,
              targetUrl: _targetUrlController.text,
              logoUrl: _logoUrlController.text,
              councilId: _councilIdController.text,
              notes: notes,
              placementScope: scope,
              categoryName: categoryName,
              durationLabel: package?.durationLabel ?? _durationLabel,
              adPlacement: placement,
              packageId: package?.id,
              packageLabel: package?.label,
              priceLabel: package?.priceLabel,
              durationHours: package?.durationHours,
            ),
          );

          if (!mounted) return;
          _formKey.currentState?.reset();
          _sponsorNameController.clear();
          _contactNameController.clear();
          _contactPhoneController.clear();
          _targetUrlController.clear();
          _logoUrlController.clear();
          _councilIdController.clear();
          _notesController.clear();
          setState(() => _selectedPackage = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال طلب الإعلان. سنراجعه ونتواصل معك.'),
            ),
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('تعذر إرسال الطلب. تحقق من البيانات وحاول مرة أخرى.'),
            ),
          );
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
      },
      allowAnonymous: false,
    );
  }

  _AdProductInfo _productFor(AdPlacement placement) {
    return _adProducts.firstWhere((product) => product.placement == placement);
  }
}

class _AdProductInfo {
  const _AdProductInfo({
    required this.placement,
    required this.title,
    required this.shortDescription,
    required this.longDescription,
    required this.badge,
    required this.icon,
    required this.previewTitle,
    required this.previewSubtitle,
  });

  final AdPlacement placement;
  final String title;
  final String shortDescription;
  final String longDescription;
  final String badge;
  final IconData icon;
  final String previewTitle;
  final String previewSubtitle;
}

const _adProducts = [
  _AdProductInfo(
    placement: AdPlacement.councilSponsorship,
    title: 'رعاية فرصة',
    shortDescription: 'ظهور اسم الراعي داخل فرصة محددة أو قسم كامل.',
    longDescription:
        'مناسب للعلامات التي تريد الظهور بجانب نقاشات مرتبطة بمجالها، مع شارة رعاية واضحة داخل الفرصة بدون إرباك للمستخدم.',
    badge: 'داخل الفرص',
    icon: Icons.workspace_premium_rounded,
    previewTitle: 'راعي هذه الفرصة',
    previewSubtitle: 'اسم الراعي وشعاره يظهران داخل بطاقة الفرصة أو تفاصيلها.',
  ),
  _AdProductInfo(
    placement: AdPlacement.homeFeaturedCouncil,
    title: 'فرصة مميزة',
    shortDescription: 'تثبيت فرصة في مساحة الرئيسية بشارة مميزة.',
    longDescription:
        'مناسب لمن يريد دفع نقاش معيّن للواجهة الرئيسية لمدة محددة، مع شارة مميز أو برعاية حتى يبقى الإعلان واضحًا وشفافًا.',
    badge: 'مساحة الرئيسية',
    icon: Icons.push_pin_rounded,
    previewTitle: 'فرصة مميزة',
    previewSubtitle: 'كرت فرصة كامل يظهر قرب الفرصة المميزة مع شارة واضحة.',
  ),
  _AdProductInfo(
    placement: AdPlacement.homeBanner,
    title: 'بنر الرئيسية',
    shortDescription: 'بنر إعلاني كبير بنفس مساحة كرت الفرصة المميزة.',
    longDescription:
        'مناسب للعروض والحملات المباشرة. يظهر كبنر واضح في الرئيسية بنفس المساحة الكبيرة، لكن بتصميم يوضح أنه إعلان وليس فرصة.',
    badge: 'بنر رئيسي',
    icon: Icons.view_carousel_rounded,
    previewTitle: 'بنر إعلان رئيسي',
    previewSubtitle: 'صورة أو رسالة مختصرة مع زر معرفة المزيد.',
  ),
];

class _AdsLandingHero extends StatelessWidget {
  const _AdsLandingHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDarkGreen.withValues(alpha: .14),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_rounded, color: AppColors.gold, size: 30),
          const SizedBox(height: 10),
          Text(
            'اختر مساحة الإعلان المناسبة',
            style: AppTextStyles.headline.copyWith(
              color: AppColors.cardWhite,
              fontSize: 21,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ثلاثة أنواع واضحة، وباقات مدة وسعر قابلة للتعديل من لوحة التحكم.',
            style: AppTextStyles.body.copyWith(
              color: AppColors.cardWhite.withValues(alpha: .86),
              fontSize: 12.4,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdProductCard extends StatelessWidget {
  const _AdProductCard({
    required this.product,
    required this.onTap,
  });

  final _AdProductInfo product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderBeige),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F4A35),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: .22),
                ),
              ),
              child: Icon(product.icon,
                  color: AppColors.primaryDarkGreen, size: 24),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppTextStyles.cardTitle.copyWith(fontSize: 15),
                        ),
                      ),
                      _MiniBadge(label: product.badge),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    product.shortDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.3,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBackButton extends StatelessWidget {
  const _DetailBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('أنواع الإعلانات'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDarkGreen,
          textStyle: AppTextStyles.button.copyWith(fontSize: 12),
        ),
      ),
    );
  }
}

class _AdDetailHero extends StatelessWidget {
  const _AdDetailHero({required this.product});

  final _AdProductInfo product;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderBeige),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(product.icon,
                  color: AppColors.primaryDarkGreen, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                ),
              ),
              _MiniBadge(label: product.badge),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            product.longDescription,
            style: AppTextStyles.body.copyWith(fontSize: 12.5, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _AdPlacementPreview extends StatelessWidget {
  const _AdPlacementPreview({required this.product});

  final _AdProductInfo product;

  @override
  Widget build(BuildContext context) {
    final isBanner = product.placement == AdPlacement.homeBanner;
    return Container(
      height: 138,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isBanner
            ? const LinearGradient(
                colors: [Color(0xFF173F34), Color(0xFF2F735F)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : null,
        color: isBanner ? null : AppColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isBanner
              ? AppColors.gold.withValues(alpha: .42)
              : AppColors.borderBeige,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isBanner
                  ? AppColors.cardWhite.withValues(alpha: .12)
                  : AppColors.primaryGreen.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              product.icon,
              color: isBanner ? AppColors.gold : AppColors.primaryDarkGreen,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniBadge(
                  label: product.placement == AdPlacement.homeFeaturedCouncil
                      ? 'مميز'
                      : product.placement == AdPlacement.homeBanner
                          ? 'إعلان'
                          : 'برعاية',
                  dark: isBanner,
                ),
                const SizedBox(height: 7),
                Text(
                  product.previewTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardTitle.copyWith(
                    color:
                        isBanner ? AppColors.cardWhite : AppColors.textDark,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.previewSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: isBanner
                        ? AppColors.cardWhite.withValues(alpha: .84)
                        : AppColors.textGray,
                    fontSize: 11.2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdPackageChoiceCard extends StatelessWidget {
  const _AdPackageChoiceCard({
    required this.package,
    required this.selected,
    required this.onSelect,
  });

  final AdPackageOption package;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.primaryGreen : AppColors.borderBeige,
          width: selected ? 1.3 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.primaryGreen : AppColors.textGray,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${package.durationLabel} · ${package.priceLabel}',
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
                if (package.highlight.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    package.highlight,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: onSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: selected
                    ? AppColors.primaryDarkGreen
                    : AppColors.background,
                foregroundColor: selected
                    ? AppColors.cardWhite
                    : AppColors.primaryDarkGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: AppTextStyles.button.copyWith(fontSize: 11.5),
              ),
              child: Text(selected ? 'مختارة' : 'اختيار'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectPackageHint extends StatelessWidget {
  const _SelectPackageHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded,
              color: AppColors.primaryDarkGreen, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'اختر باقة أولًا لفتح نموذج الطلب.',
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdRequestFormCard extends StatelessWidget {
  const _AdRequestFormCard({
    required this.formKey,
    required this.product,
    required this.package,
    required this.sponsorNameController,
    required this.contactNameController,
    required this.contactPhoneController,
    required this.targetUrlController,
    required this.logoUrlController,
    required this.councilIdController,
    required this.notesController,
    required this.categories,
    required this.selectedCategory,
    required this.selectedScope,
    required this.submitting,
    required this.onScopeChanged,
    required this.onCategoryChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final _AdProductInfo product;
  final AdPackageOption package;
  final TextEditingController sponsorNameController;
  final TextEditingController contactNameController;
  final TextEditingController contactPhoneController;
  final TextEditingController targetUrlController;
  final TextEditingController logoUrlController;
  final TextEditingController councilIdController;
  final TextEditingController notesController;
  final List<String> categories;
  final String? selectedCategory;
  final SponsorshipPlacementScope selectedScope;
  final bool submitting;
  final ValueChanged<SponsorshipPlacementScope> onScopeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final isCouncilSponsor = product.placement == AdPlacement.councilSponsorship;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'طلب ${product.title}',
              style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '${package.label} · ${package.durationLabel} · ${package.priceLabel}',
              style: AppTextStyles.caption.copyWith(fontSize: 11),
            ),
            if (isCouncilSponsor) ...[
              const SizedBox(height: 10),
              _ScopeSelector(
                value: selectedScope,
                onChanged: onScopeChanged,
              ),
              if (selectedScope == SponsorshipPlacementScope.categoryMajlis) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  isExpanded: true,
                  decoration: _inputDecoration('نوع الفرصة'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: onCategoryChanged,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'اختر نوع الفرصة' : null,
                ),
              ],
            ],
            const SizedBox(height: 10),
            _TextInput(
              controller: sponsorNameController,
              label: 'اسم الجهة أو الراعي',
              validator: (value) => _required(value, min: 2),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: contactNameController,
              label: 'اسم المسؤول',
              validator: (value) => _required(value, min: 2),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: contactPhoneController,
              label: 'رقم التواصل',
              keyboardType: TextInputType.phone,
              validator: (value) => _required(value, min: 5),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: targetUrlController,
              label: 'رابط الإعلان أو الجهة',
              keyboardType: TextInputType.url,
              validator: _validUri,
            ),
            if (product.placement != AdPlacement.homeBanner) ...[
              const SizedBox(height: 10),
              _TextInput(
                controller: councilIdController,
                label: product.placement == AdPlacement.homeFeaturedCouncil
                    ? 'معرف الفرصة المطلوب اختياري'
                    : 'معرف الفرصة المحدد اختياري',
              ),
            ],
            const SizedBox(height: 10),
            _TextInput(
              controller: logoUrlController,
              label: product.placement == AdPlacement.homeBanner
                  ? 'رابط صورة البنر اختياري'
                  : 'رابط الشعار اختياري',
              keyboardType: TextInputType.url,
              validator: _validOptionalUri,
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: notesController,
              label: 'تفاصيل إضافية اختيارية',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : onSubmit,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(submitting ? 'جارٍ الإرسال' : 'إرسال الطلب'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDarkGreen,
                  foregroundColor: AppColors.cardWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.cardWhite.withValues(alpha: .13)
            : AppColors.primaryGreen.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? AppColors.gold.withValues(alpha: .38)
              : AppColors.primaryGreen.withValues(alpha: .18),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: dark ? AppColors.cardWhite : AppColors.primaryDarkGreen,
          fontSize: 10.2,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SponsorshipHero extends StatelessWidget {
  const _SponsorshipHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primaryDarkGreen,
            AppColors.primaryGreen,
            Color(0xFF2E6B5D),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDarkGreen.withValues(alpha: .16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.cardWhite.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.gold.withValues(alpha: .44),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign_rounded,
                    color: AppColors.gold, size: 18),
                const SizedBox(width: 7),
                Text(
                  'إعلان راعي',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.cardWhite,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'اجعل علامتك حاضرة داخل الفرص بدون إزعاج',
            style: AppTextStyles.headline.copyWith(
              color: AppColors.cardWhite,
              fontSize: 23,
              height: 1.22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ظهور أنيق داخل بطاقة الفرصة المميزة، مع شعار الراعي وزر اعرف أكثر. الطلب هنا اهتمام فقط، والمراجعة والتفاصيل تتم قبل التفعيل.',
            style: AppTextStyles.body.copyWith(
              color: AppColors.cardWhite.withValues(alpha: .86),
              fontSize: 12.6,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PackageShowcase extends StatelessWidget {
  const _PackageShowcase({
    required this.selectedScope,
    required this.selectedDuration,
    required this.onSelect,
  });

  final SponsorshipPlacementScope selectedScope;
  final String selectedDuration;
  final void Function(SponsorshipPlacementScope scope, String durationLabel)
      onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'باقات إعلان الراعي',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.primaryDarkGreen,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _PackageCard(
          title: 'راعي فرصة محددة',
          subtitle: 'ظهور مناسب لنوع الفرصة المختار مثل فرص التقبيل أو الشراكات.',
          icon: Icons.forum_rounded,
          scope: SponsorshipPlacementScope.categoryMajlis,
          selectedScope: selectedScope,
          selectedDuration: selectedDuration,
          onSelect: onSelect,
        ),
        const SizedBox(height: 10),
        _PackageCard(
          title: 'راعي كل الفرص',
          subtitle: 'حضور أوسع يظهر كرعاية عامة عندما لا توجد رعاية مخصصة.',
          icon: Icons.public_rounded,
          scope: SponsorshipPlacementScope.allMajalis,
          selectedScope: selectedScope,
          selectedDuration: selectedDuration,
          onSelect: onSelect,
          highlighted: true,
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.scope,
    required this.selectedScope,
    required this.selectedDuration,
    required this.onSelect,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final SponsorshipPlacementScope scope;
  final SponsorshipPlacementScope selectedScope;
  final String selectedDuration;
  final void Function(SponsorshipPlacementScope scope, String durationLabel)
      onSelect;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final selected = selectedScope == scope;
    final accent = highlighted ? AppColors.warningGold : AppColors.primaryGreen;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              selected ? accent.withValues(alpha: .56) : AppColors.borderBeige,
          width: selected ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: selected ? .13 : .06),
            blurRadius: selected ? 14 : 9,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: .24)),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DurationButton(
                  label: '3 أيام',
                  selected: selected && selectedDuration == '3 أيام',
                  color: accent,
                  onTap: () => onSelect(scope, '3 أيام'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DurationButton(
                  label: 'شهر',
                  selected: selected && selectedDuration == 'شهر',
                  color: accent,
                  onTap: () => onSelect(scope, 'شهر'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 15, color: accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'السعر والتفعيل يحددان بعد مراجعة الطلب من لوحة التحكم.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5,
                    color: AppColors.textGray,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  const _DurationButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? color : AppColors.cardWhite,
          foregroundColor: selected ? AppColors.cardWhite : color,
          side: BorderSide(color: selected ? color : AppColors.borderBeige),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppTextStyles.button.copyWith(fontSize: 12),
        ),
        child: Text(label),
      ),
    );
  }
}

// ignore: unused_element
class _InterestFormCard extends StatelessWidget {
  const _InterestFormCard({
    required this.formKey,
    required this.sponsorNameController,
    required this.contactNameController,
    required this.contactPhoneController,
    required this.targetUrlController,
    required this.logoUrlController,
    required this.notesController,
    required this.categories,
    required this.selectedCategory,
    required this.selectedScope,
    required this.selectedDuration,
    required this.submitting,
    required this.onScopeChanged,
    required this.onCategoryChanged,
    required this.onDurationChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController sponsorNameController;
  final TextEditingController contactNameController;
  final TextEditingController contactPhoneController;
  final TextEditingController targetUrlController;
  final TextEditingController logoUrlController;
  final TextEditingController notesController;
  final List<String> categories;
  final String? selectedCategory;
  final SponsorshipPlacementScope selectedScope;
  final String selectedDuration;
  final bool submitting;
  final ValueChanged<SponsorshipPlacementScope> onScopeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onDurationChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'طلب إعلان راعي',
              style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'أرسل بياناتك وسنراجع الملاءمة والتوقيت قبل التفعيل.',
              style: AppTextStyles.caption.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 12),
            _ScopeSelector(
              value: selectedScope,
              onChanged: onScopeChanged,
            ),
            if (selectedScope == SponsorshipPlacementScope.categoryMajlis) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                isExpanded: true,
                decoration: _inputDecoration('نوع الفرصة'),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: onCategoryChanged,
                validator: (value) =>
                    value == null || value.isEmpty ? 'اختر نوع الفرصة' : null,
              ),
            ],
            const SizedBox(height: 10),
            _DurationSelector(
              value: selectedDuration,
              onChanged: onDurationChanged,
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: sponsorNameController,
              label: 'اسم الراعي',
              validator: (value) => _required(value, min: 2),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: contactNameController,
              label: 'اسم المسؤول',
              validator: (value) => _required(value, min: 2),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: contactPhoneController,
              label: 'رقم التواصل',
              keyboardType: TextInputType.phone,
              validator: (value) => _required(value, min: 5),
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: targetUrlController,
              label: 'رابط اعرف أكثر',
              keyboardType: TextInputType.url,
              validator: _validUri,
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: logoUrlController,
              label: 'رابط الشعار اختياري',
              keyboardType: TextInputType.url,
              validator: _validOptionalUri,
            ),
            const SizedBox(height: 10),
            _TextInput(
              controller: notesController,
              label: 'ملاحظات اختيارية',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : onSubmit,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(submitting ? 'جارٍ الإرسال' : 'إرسال الطلب'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDarkGreen,
                  foregroundColor: AppColors.cardWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.value,
    required this.onChanged,
  });

  final SponsorshipPlacementScope value;
  final ValueChanged<SponsorshipPlacementScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentOption(
            label: 'فرصة محددة',
            icon: Icons.forum_outlined,
            selected: value == SponsorshipPlacementScope.categoryMajlis,
            onTap: () => onChanged(SponsorshipPlacementScope.categoryMajlis),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SegmentOption(
            label: 'كل الفرص',
            icon: Icons.public_rounded,
            selected: value == SponsorshipPlacementScope.allMajalis,
            onTap: () => onChanged(SponsorshipPlacementScope.allMajalis),
          ),
        ),
      ],
    );
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentOption(
            label: '3 أيام',
            icon: Icons.calendar_view_day_rounded,
            selected: value == '3 أيام',
            onTap: () => onChanged('3 أيام'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SegmentOption(
            label: 'شهر',
            icon: Icons.calendar_month_rounded,
            selected: value == 'شهر',
            onTap: () => onChanged('شهر'),
          ),
        ),
      ],
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryDarkGreen
                : AppColors.background.withValues(alpha: .62),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.borderBeige,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? AppColors.gold : AppColors.primaryDarkGreen,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: selected ? AppColors.cardWhite : AppColors.textDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textAlign: TextAlign.right,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: AppTextStyles.body.copyWith(fontSize: 13),
      decoration: _inputDecoration(label),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: AppTextStyles.caption.copyWith(fontSize: 11.5),
    isDense: true,
    filled: true,
    fillColor: AppColors.background.withValues(alpha: .52),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.borderBeige),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.borderBeige),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
    ),
  );
}

String? _required(String? value, {int min = 1}) {
  final text = value?.trim() ?? '';
  return text.length < min ? 'هذا الحقل مطلوب' : null;
}

String? _validUri(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'الرابط مطلوب';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return 'أدخل رابطًا واضحًا';
  return null;
}

String? _validOptionalUri(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return 'أدخل رابطًا واضحًا';
  return null;
}
