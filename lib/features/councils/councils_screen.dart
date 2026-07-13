import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/discussion_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/models/council_model.dart';
import '../../data/repositories/council_repository.dart';

enum _OpportunitySort { latest, interaction, comments, opinions }

class CouncilsScreen extends StatefulWidget {
  const CouncilsScreen({
    super.key,
    required this.onOpenCouncil,
    this.initialCategory = 'الكل',
    this.initialCategoryVersion = 0,
  });

  final ValueChanged<String> onOpenCouncil;
  final String initialCategory;
  final int initialCategoryVersion;

  @override
  State<CouncilsScreen> createState() => _CouncilsScreenState();
}

class _CouncilsScreenState extends State<CouncilsScreen> {
  final repo = CouncilRepository.instance;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late String selectedCategory = widget.initialCategory;
  _OpportunitySort selectedSort = _OpportunitySort.latest;
  String query = '';
  bool _searchVisible = false;

  @override
  void didUpdateWidget(covariant CouncilsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory ||
        widget.initialCategoryVersion != oldWidget.initialCategoryVersion) {
      selectedCategory = widget.initialCategory;
      query = '';
      _searchVisible = false;
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        final filtered = _filteredCouncils();
        final categoryHint = _categoryHint(selectedCategory);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackground(
            showPattern: false,
            child: Column(
              children: [
                CustomGreenHeader(
                  title: 'الفرص',
                  trailing: HeaderRoundButton(
                    icon: _searchVisible
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    onTap: _toggleSearch,
                    badge: !_searchVisible && query.trim().isNotEmpty,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      sizes.horizontalPadding,
                      12,
                      sizes.horizontalPadding,
                      sizes.bottomNavHeight + 18 +
                          MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    children: [
                      if (_searchVisible) ...[
                        _SearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          query: query,
                          onChanged: (value) {
                            if (value == query) return;
                            setState(() => query = value);
                          },
                          onClear: () {
                            _searchController.clear();
                            setState(() => query = '');
                            _searchFocusNode.requestFocus();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        height: 34,
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: repo.categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final category = repo.categories[index];
                              final selected = selectedCategory == category;
                              return _CategoryChip(
                                label: category,
                                selected: selected,
                                onTap: () => setState(() {
                                  selectedCategory = category;
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                      if (categoryHint != null) ...[
                        const SizedBox(height: 8),
                        _CategoryHint(text: categoryHint),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'كل الفرص',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          _SortButton(
                            selected: selectedSort,
                            onSelected: (sort) {
                              setState(() => selectedSort = sort);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (filtered.isEmpty)
                        EmptyState(
                          icon: Icons.manage_search_rounded,
                          title: query.trim().isEmpty
                              ? 'لا توجد فرص بعد'
                              : 'لا توجد نتائج مطابقة',
                          message: query.trim().isEmpty
                              ? 'ستظهر الفرص هنا عند توفر منشورات مناسبة.'
                              : 'جرّب كلمة أبسط أو اختر قسمًا آخر.',
                        )
                      else
                        ...filtered.map(
                          (c) => DiscussionCard(
                            council: c,
                            compact: true,
                            onTap: () => widget.onOpenCouncil(c.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<CouncilModel> _filteredCouncils() {
    final base = repo.councilsByCategory(selectedCategory);
    final q = _searchToken(query);
    final filtered = q.isEmpty
        ? List<CouncilModel>.from(base)
        : base.where((council) => _matchesSearch(council, q)).toList();
    _sortCouncils(filtered);
    return filtered;
  }

  bool _matchesSearch(CouncilModel council, String q) {
    final searchable = _searchToken(
      '${council.title} ${council.description} ${council.category} ${council.createdByName ?? ''}',
    );
    return searchable.contains(q);
  }

  String _searchToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('ـ', '')
        .replaceAll(RegExp('[إأآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
  }

  void _sortCouncils(List<CouncilModel> councils) {
    councils.sort((a, b) {
      switch (selectedSort) {
        case _OpportunitySort.latest:
          return _compareLatest(a, b);
        case _OpportunitySort.interaction:
          final scoreCompare =
              _interactionScore(b).compareTo(_interactionScore(a));
          return scoreCompare != 0 ? scoreCompare : _compareLatest(a, b);
        case _OpportunitySort.comments:
          final commentsCompare = b.commentsCount.compareTo(a.commentsCount);
          return commentsCompare != 0 ? commentsCompare : _compareLatest(a, b);
        case _OpportunitySort.opinions:
          final opinionsCompare = b.votesCount.compareTo(a.votesCount);
          return opinionsCompare != 0 ? opinionsCompare : _compareLatest(a, b);
      }
    });
  }

  int _interactionScore(CouncilModel council) {
    return (council.commentsCount * 3) + council.votesCount;
  }

  int _compareLatest(CouncilModel a, CouncilModel b) {
    final bCreatedAt = b.createdAt;
    final aCreatedAt = a.createdAt;
    if (bCreatedAt != null && aCreatedAt != null) {
      return bCreatedAt.compareTo(aCreatedAt);
    }
    if (bCreatedAt != null) return 1;
    if (aCreatedAt != null) return -1;
    return b.id.compareTo(a.id);
  }

  void _toggleSearch() {
    if (_searchVisible) {
      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() {
        query = '';
        _searchVisible = false;
      });
      return;
    }

    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  String? _categoryHint(String category) {
    switch (category) {
      case 'فرص للتقبيل':
        return 'فرص قائمة للبيع أو التقبيل مثل محل، مطعم، كوفي أو مشروع قائم.';
      case 'فرص مطلوبة':
        return 'طلبات أشخاص يبحثون عن فرصة مناسبة للاستثمار أو التشغيل.';
      case 'فرص شراكة':
        return 'طلبات شراكة من أشخاص يبحثون عن ممول، مشغّل، أو صاحب خبرة.';
      case 'تجارب السوق':
        return 'تجارب واقعية من السوق، نتائج، أخطاء، ونصائح عملية.';
      default:
        return null;
    }
  }
}

class _CategoryHint extends StatelessWidget {
  const _CategoryHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: AppColors.primaryDarkGreen,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textGray,
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: AppTextStyles.body.copyWith(fontSize: 12.5),
        decoration: InputDecoration(
          hintText: 'ابحث باسم فرصة، نشاط، مدينة...',
          hintStyle: AppTextStyles.caption.copyWith(fontSize: 11),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textGray,
            size: 18,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          suffixIcon: query.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح البحث',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textGray,
                    size: 18,
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          filled: true,
          fillColor: AppColors.cardWhite,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderBeige),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderBeige),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryGreen,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.selected,
    required this.onSelected,
  });

  final _OpportunitySort selected;
  final ValueChanged<_OpportunitySort> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_OpportunitySort>(
      initialValue: selected,
      tooltip: 'فرز الفرص',
      position: PopupMenuPosition.under,
      color: AppColors.cardWhite,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderBeige),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => _OpportunitySort.values
          .map(
            (sort) => PopupMenuItem<_OpportunitySort>(
              value: sort,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: [
                    Icon(
                      _sortIcon(sort),
                      size: 18,
                      color: sort == selected
                          ? AppColors.primaryDarkGreen
                          : AppColors.textGray,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _sortLabel(sort),
                      style: AppTextStyles.caption.copyWith(
                        color: sort == selected
                            ? AppColors.primaryDarkGreen
                            : AppColors.textDark,
                        fontSize: 12,
                        fontWeight: sort == selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tune_rounded,
                color: AppColors.primaryDarkGreen,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                _sortLabel(selected),
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primaryDarkGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _sortLabel(_OpportunitySort sort) {
  switch (sort) {
    case _OpportunitySort.latest:
      return 'الأحدث';
    case _OpportunitySort.interaction:
      return 'الأكثر تفاعلًا';
    case _OpportunitySort.comments:
      return 'الأكثر تعليقات';
    case _OpportunitySort.opinions:
      return 'الأكثر آراء';
  }
}

IconData _sortIcon(_OpportunitySort sort) {
  switch (sort) {
    case _OpportunitySort.latest:
      return Icons.schedule_rounded;
    case _OpportunitySort.interaction:
      return Icons.local_fire_department_rounded;
    case _OpportunitySort.comments:
      return Icons.chat_bubble_outline_rounded;
    case _OpportunitySort.opinions:
      return Icons.how_to_vote_outlined;
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? AppColors.cardWhite : AppColors.primaryDarkGreen;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDarkGreen : AppColors.cardWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                selected ? AppColors.primaryDarkGreen : AppColors.borderBeige,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: foreground,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
