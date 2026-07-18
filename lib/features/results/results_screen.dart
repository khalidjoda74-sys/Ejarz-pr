import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/opportunity_vote_copy.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/result_bar.dart';
import '../../core/widgets/relative_time_text.dart';
import '../../data/models/council_model.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/firebase_council_repository.dart';

enum _ActivityFilter {
  created,
  voted,
  commented,
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.onOpenCouncil});

  final ValueChanged<String> onOpenCouncil;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  _ActivityFilter _filter = _ActivityFilter.created;

  @override
  Widget build(BuildContext context) {
    final uid = AuthController.instance.user?.uid;
    final sizes = AppSizes.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            const CustomGreenHeader(title: 'نشاطي'),
            _ActivityFilterBar(
              selected: _filter,
              onChanged: (filter) => setState(() => _filter = filter),
            ),
            Expanded(
              child: uid == null
                  ? const _ActivityEmptyState(
                      icon: Icons.lock_outline_rounded,
                      title: 'سجّل دخولك أولًا',
                      message: 'نشاطك داخل الفرص سيظهر هنا بعد تسجيل الدخول.',
                    )
                  : _ActivityList(
                      uid: uid,
                      filter: _filter,
                      horizontalPadding: sizes.horizontalPadding,
                      onOpenCouncil: widget.onOpenCouncil,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityFilterBar extends StatelessWidget {
  const _ActivityFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _ActivityFilter selected;
  final ValueChanged<_ActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'فرصي',
            icon: Icons.add_circle_outline_rounded,
            selected: selected == _ActivityFilter.created,
            onTap: () => onChanged(_ActivityFilter.created),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'رأيي',
            icon: Icons.how_to_vote_outlined,
            selected: selected == _ActivityFilter.voted,
            onTap: () => onChanged(_ActivityFilter.voted),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'تعليقاتي',
            icon: Icons.chat_bubble_outline_rounded,
            selected: selected == _ActivityFilter.commented,
            onTap: () => onChanged(_ActivityFilter.commented),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    final foreground =
        selected ? AppColors.cardWhite : AppColors.primaryDarkGreen;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDarkGreen : AppColors.cardWhite,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color:
                  selected ? AppColors.primaryDarkGreen : AppColors.borderBeige,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: foreground,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w900,
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

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.uid,
    required this.filter,
    required this.horizontalPadding,
    required this.onOpenCouncil,
  });

  final String uid;
  final _ActivityFilter filter;
  final double horizontalPadding;
  final ValueChanged<String> onOpenCouncil;

  @override
  Widget build(BuildContext context) {
    switch (filter) {
      case _ActivityFilter.created:
        return AnimatedBuilder(
          animation: CouncilRepository.instance,
          builder: (context, _) {
            final localCreatedCouncils = _localCreatedCouncils(uid);
            return _buildActivityStream<CouncilModel>(
              stream: FirebaseCouncilRepository.instance.watchUserCouncils(
                uid: uid,
              ),
              initialData: localCreatedCouncils,
              mergeItems: (remoteCouncils) => _mergeCreatedCouncils(
                localCreatedCouncils,
                remoteCouncils,
              ),
              itemBuilder: (council) => _ActivityCouncilCard(
                council: council,
                onOpen: () => onOpenCouncil(council.id),
              ),
            );
          },
        );
      case _ActivityFilter.voted:
        return _buildActivityStream<VotedCouncilActivity>(
          stream:
              FirebaseCouncilRepository.instance.watchVotedCouncilActivities(
            uid: uid,
          ),
          itemBuilder: (activity) => _ActivityCouncilCard(
            council: activity.council,
            noteIcon: Icons.how_to_vote_outlined,
            noteLabel: 'رأيك',
            noteText: _voteLabel(activity.council, activity.vote),
            onOpen: () => onOpenCouncil(activity.council.id),
          ),
        );
      case _ActivityFilter.commented:
        return _buildActivityStream<CommentedCouncilActivity>(
          stream: FirebaseCouncilRepository.instance
              .watchCommentedCouncilActivities(uid: uid),
          itemBuilder: (activity) => _ActivityCouncilCard(
            council: activity.council,
            noteIcon: Icons.chat_bubble_outline_rounded,
            noteLabel: 'تعليقك',
            noteText: activity.comment.text,
            onOpen: () => onOpenCouncil(activity.council.id),
          ),
        );
    }
  }

  Widget _buildActivityStream<T>({
    required Stream<List<T>> stream,
    required Widget Function(T item) itemBuilder,
    List<T>? initialData,
    List<T> Function(List<T> items)? mergeItems,
  }) {
    return StreamBuilder<List<T>>(
      stream: stream,
      initialData: initialData,
      builder: (context, snapshot) {
        final rawItems = snapshot.data ?? initialData ?? <T>[];
        final items = mergeItems?.call(rawItems) ?? rawItems;

        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return const _ActivityLoadingState();
        }

        if (snapshot.hasError && items.isEmpty) {
          return const _ActivityEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'تعذر تحميل النشاط',
            message: 'راجع الاتصال أو صلاحيات قاعدة البيانات ثم حاول مرة أخرى.',
          );
        }

        if (items.isEmpty) {
          if (kDebugMode) {
            return _ActivityPreviewList(
              filter: filter,
              horizontalPadding: horizontalPadding,
            );
          }

          return _ActivityEmptyState(
            icon: _emptyIcon,
            title: _emptyTitle,
            message: _emptyMessage,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            4,
            horizontalPadding,
            AppSizes.of(context).bottomNavHeight +
                18 +
                MediaQuery.viewPaddingOf(context).bottom,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return itemBuilder(items[index]);
          },
        );
      },
    );
  }

  String _voteLabel(CouncilModel council, VoteOption option) {
    return OpportunityVoteCopy.forCouncil(council).labelFor(option);
  }

  List<CouncilModel> _localCreatedCouncils(String uid) {
    final councils = CouncilRepository.instance.councils
        .where((council) => council.createdBy == uid)
        .toList(growable: false);
    councils.sort(_compareCouncilsLatestFirst);
    return councils;
  }

  List<CouncilModel> _mergeCreatedCouncils(
    List<CouncilModel> localCouncils,
    List<CouncilModel> remoteCouncils,
  ) {
    final byId = <String, CouncilModel>{
      for (final council in remoteCouncils) council.id: council,
    };
    for (final council in localCouncils) {
      byId.putIfAbsent(council.id, () => council);
    }

    final councils = byId.values.toList(growable: false);
    councils.sort(_compareCouncilsLatestFirst);
    return councils;
  }

  int _compareCouncilsLatestFirst(CouncilModel a, CouncilModel b) {
    final aCreatedAt = a.createdAt;
    final bCreatedAt = b.createdAt;
    if (aCreatedAt != null && bCreatedAt != null) {
      return bCreatedAt.compareTo(aCreatedAt);
    }
    if (aCreatedAt != null) return -1;
    if (bCreatedAt != null) return 1;
    return 0;
  }

  IconData get _emptyIcon {
    switch (filter) {
      case _ActivityFilter.created:
        return Icons.add_circle_outline_rounded;
      case _ActivityFilter.voted:
        return Icons.how_to_vote_outlined;
      case _ActivityFilter.commented:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  String get _emptyTitle {
    switch (filter) {
      case _ActivityFilter.created:
        return 'لا توجد فرص لديك';
      case _ActivityFilter.voted:
        return 'لا توجد آراء سريعة بعد';
      case _ActivityFilter.commented:
        return 'لا توجد تعليقات بعد';
    }
  }

  String get _emptyMessage {
    switch (filter) {
      case _ActivityFilter.created:
        return 'أي فرصة تنشئها ستظهر هنا للرجوع إليها بسرعة.';
      case _ActivityFilter.voted:
        return 'الفرص التي تترك فيها رأيك السريع ستظهر هنا.';
      case _ActivityFilter.commented:
        return 'الفرص التي تكتب فيها تعليقات ستظهر هنا.';
    }
  }
}

class _ActivityPreviewList extends StatelessWidget {
  const _ActivityPreviewList({
    required this.filter,
    required this.horizontalPadding,
  });

  final _ActivityFilter filter;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final card = switch (filter) {
      _ActivityFilter.created => _ActivityCouncilCard(
          council: _previewCouncil(
            id: 'preview-created',
            title: 'نموذج فرصة قمت بإنشائه',
            support: 58,
            against: 27,
            neutral: 15,
          ),
          onOpen: () {},
        ),
      _ActivityFilter.voted => _ActivityCouncilCard(
          council: _previewCouncil(
            id: 'preview-voted',
            title: 'نموذج فرصة تركت فيها رأيك',
            support: 44,
            against: 41,
            neutral: 15,
          ),
          noteIcon: Icons.how_to_vote_outlined,
          noteLabel: 'رأيك',
          noteText: OpportunityVoteCopy.forCategory('فرص للتقبيل')
              .labelFor(VoteOption.support),
          onOpen: () {},
        ),
      _ActivityFilter.commented => _ActivityCouncilCard(
          council: _previewCouncil(
            id: 'preview-commented',
            title: 'نموذج فرصة كتبت فيه تعليقًا',
            support: 36,
            against: 49,
            neutral: 15,
          ),
          noteIcon: Icons.chat_bubble_outline_rounded,
          noteLabel: 'تعليقك',
          noteText: 'هذا مثال لشكل مقتطف تعليقك داخل كرت الفرصة.',
          onOpen: () {},
        ),
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        4,
        horizontalPadding,
        AppSizes.of(context).bottomNavHeight +
            18 +
            MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [card],
    );
  }

  CouncilModel _previewCouncil({
    required String id,
    required String title,
    required int support,
    required int against,
    required int neutral,
  }) {
    return CouncilModel(
      id: id,
      title: title,
      description: 'نموذج عرض',
      category: 'فرص للتقبيل',
      status: CouncilStatus.active,
      participants: 64,
      commentsCount: 0,
      votesCount: 64,
      supportPercent: support,
      againstPercent: against,
      neutralPercent: neutral,
      endsIn: 'ينتهي قريبًا',
      comments: const [],
    );
  }
}

class _ActivityCouncilCard extends StatelessWidget {
  const _ActivityCouncilCard({
    required this.council,
    required this.onOpen,
    this.noteIcon,
    this.noteLabel,
    this.noteText,
  });

  final CouncilModel council;
  final VoidCallback onOpen;
  final IconData? noteIcon;
  final String? noteLabel;
  final String? noteText;

  @override
  Widget build(BuildContext context) {
    final note = noteText?.trim();
    final voteCopy = OpportunityVoteCopy.forCouncil(council);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.borderBeige.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  council.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primaryDarkGreen,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                _statusIcon,
                color: _statusColor,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                _statusLabel,
                style: AppTextStyles.caption.copyWith(
                  color: _statusColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            council.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 15,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 7),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.support),
            percent: council.supportPercent,
            color: voteCopy.colorFor(VoteOption.support),
          ),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.against),
            percent: council.againstPercent,
            color: voteCopy.colorFor(VoteOption.against),
          ),
          ResultBar(
            label: voteCopy.resultLabelFor(VoteOption.neutral),
            percent: council.neutralPercent,
            color: voteCopy.colorFor(VoteOption.neutral),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ActivityNote(
              icon: noteIcon ?? Icons.info_outline_rounded,
              label: noteLabel ?? '',
              text: note,
            ),
          ],
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CardMeta(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: '${council.commentsCount} تعليق',
                    ),
                    _CardMeta(
                      icon: Icons.how_to_vote_outlined,
                      text: council.votesCount <= 0
                          ? 'كن أول من يبدي رأيه'
                          : '${council.votesCount} رأي',
                    ),
                    if (council.createdAt != null)
                      RelativeTimeText(
                        dateTime: council.createdAt,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textGray.withValues(alpha: .78),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('فتح النقاش'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDarkGreen,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon {
    switch (council.status) {
      case CouncilStatus.active:
        return Icons.bolt_rounded;
      case CouncilStatus.endingSoon:
        return Icons.timer_outlined;
      case CouncilStatus.closed:
        return Icons.lock_clock_outlined;
    }
  }

  String get _statusLabel {
    switch (council.status) {
      case CouncilStatus.active:
        return 'نشط';
      case CouncilStatus.endingSoon:
        return 'ينتهي قريبًا';
      case CouncilStatus.closed:
        return 'منتهي';
    }
  }

  Color get _statusColor {
    switch (council.status) {
      case CouncilStatus.active:
        return AppColors.primaryDarkGreen;
      case CouncilStatus.endingSoon:
        return AppColors.warningGold;
      case CouncilStatus.closed:
        return AppColors.textGray;
    }
  }
}

class _ActivityNote extends StatelessWidget {
  const _ActivityNote({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderBeige.withValues(alpha: .75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDarkGreen, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primaryDarkGreen,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textDark,
                    fontSize: 11.3,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textGray, size: 13),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.caption.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}

class _ActivityLoadingState extends StatelessWidget {
  const _ActivityLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primaryDarkGreen),
    );
  }
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryDarkGreen, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
