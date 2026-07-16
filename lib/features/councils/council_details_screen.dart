import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/moderation/content_moderation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/opportunity_vote_copy.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/optimized_network_image.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/result_bar.dart';
import '../../core/widgets/relative_time_text.dart';
import '../../core/widgets/vote_button.dart';
import '../../data/models/comment_model.dart';
import '../../data/models/council_model.dart';
import '../../data/models/sponsorship_campaign.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/sponsorship_repository.dart';
import '../messages/conversation_screen.dart';
import '../moderation/report_dialog.dart';
import '../sponsorship/sponsorship_screen.dart';

class CouncilDetailsScreen extends StatefulWidget {
  const CouncilDetailsScreen({super.key, required this.councilId});

  final String councilId;

  @override
  State<CouncilDetailsScreen> createState() => _CouncilDetailsScreenState();
}

class _CouncilDetailsScreenState extends State<CouncilDetailsScreen> {
  final repo = CouncilRepository.instance;
  final commentController = TextEditingController();
  final commentFocusNode = FocusNode();
  static const int _initialVisibleReplies = 2;
  static const int _replyPageSize = 3;
  final Map<String, int> _visibleReplyLimits = {};
  CommentModel? _replyingTo;
  bool _openingConversation = false;
  int _voteRequestId = 0;
  final Set<String> _precachedImageUrls = <String>{};

  @override
  void initState() {
    super.initState();
    repo.watchCouncilComments(widget.councilId);
  }

  @override
  void didUpdateWidget(covariant CouncilDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.councilId != widget.councilId) {
      _replyingTo = null;
      commentController.clear();
      _visibleReplyLimits.clear();
      repo.watchCouncilComments(widget.councilId);
    }
  }

  @override
  void dispose() {
    commentController.dispose();
    commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        final sizes = AppSizes.of(context);
        final council = repo.findCouncilById(widget.councilId);
        if (council == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                CustomGreenHeader(title: 'نقاش الفرصة', showBack: true),
                Expanded(
                  child: Center(
                    child: Text('هذه الفرصة لم تعد متاحة.'),
                  ),
                ),
              ],
            ),
          );
        }
        _precacheCouncilImages(council.imageUrls);
        final voteCopy = OpportunityVoteCopy.forCouncil(council);
        final isOwner = repo.isCouncilOwner(council);
        final commentThreads = _threadComments(council.comments);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackground(
            showPattern: false,
            child: Column(
              children: [
                CustomGreenHeader(
                  title: 'نقاش الفرصة',
                  showBack: true,
                  trailing: isOwner
                      ? null
                      : HeaderRoundButton(
                          icon: Icons.flag_outlined,
                          onTap: () => _reportCouncil(council),
                        ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      sizes.horizontalPadding,
                      10,
                      sizes.horizontalPadding,
                      10,
                    ),
                    children: [
                      _QuestionPanel(council: council),
                      if (council.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _CouncilImagesGrid(council: council),
                      ],
                      if (_canContactOwner(council) || isOwner) ...[
                        const SizedBox(height: 8),
                        _CouncilQuickActions(
                          showContact: _canContactOwner(council),
                          showOwnerActions: isOwner,
                          contactLoading: _openingConversation,
                          onContact: () => _openConversation(council),
                          onRefresh: () => _refreshVisibility(council),
                          onDelete: () => _confirmDeleteCouncil(council),
                        ),
                      ],
                      if (!isOwner) ...[
                        const SizedBox(height: 9),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            voteCopy.prompt,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textGray,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            VoteButton(
                              label: voteCopy.labelFor(VoteOption.support),
                              icon: voteCopy.iconFor(VoteOption.support),
                              option: VoteOption.support,
                              colorOverride:
                                  voteCopy.colorFor(VoteOption.support),
                              selected:
                                  council.selectedOption == VoteOption.support,
                              onTap: () => _vote(council, VoteOption.support),
                            ),
                            const SizedBox(width: 8),
                            VoteButton(
                              label: voteCopy.labelFor(VoteOption.against),
                              icon: voteCopy.iconFor(VoteOption.against),
                              option: VoteOption.against,
                              colorOverride:
                                  voteCopy.colorFor(VoteOption.against),
                              selected:
                                  council.selectedOption == VoteOption.against,
                              onTap: () => _vote(council, VoteOption.against),
                            ),
                            const SizedBox(width: 8),
                            VoteButton(
                              label: voteCopy.labelFor(VoteOption.neutral),
                              icon: voteCopy.iconFor(VoteOption.neutral),
                              option: VoteOption.neutral,
                              colorOverride:
                                  voteCopy.colorFor(VoteOption.neutral),
                              selected:
                                  council.selectedOption == VoteOption.neutral,
                              onTap: () => _vote(council, VoteOption.neutral),
                            ),
                          ],
                        ),
                      ],
                      _CouncilSponsorSlot(council: council),
                      const SizedBox(height: 10),
                      _ResultsPanel(council: council, isOwner: isOwner),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'التعليقات (${council.commentsCount})',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'الأحدث',
                            style: AppTextStyles.caption.copyWith(fontSize: 11),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textGray,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ...commentThreads.map((thread) {
                        final comment = thread.comment;
                        final replyLimit = _replyLimitFor(comment.id);
                        return _CommentTile(
                          comment: comment,
                          replies: thread.replies,
                          visibleReplyLimit: replyLimit,
                          onShowMoreReplies: thread.replies.length > replyLimit
                              ? () => _showMoreReplies(
                                    comment.id,
                                    thread.replies.length,
                                  )
                              : null,
                          allowReplies: council.allowComments,
                          onAuthorTap: comment.isSeedContent
                              ? () => unawaited(
                                    _showEditorialNotice(account: true),
                                  )
                              : null,
                          isOwnComment: _isOwnComment(comment),
                          isConvinced: repo.hasConvincingVote(
                            council.id,
                            comment.id,
                          ),
                          onReport: () => AuthGuard.requireAuth(
                            context,
                            () => showReportDialog(
                              context,
                              onSubmit: (reason) => repo.createReport(
                                targetType: 'comment',
                                targetPath:
                                    'councils/${council.id}/comments/${comment.id}',
                                reason: reason,
                                councilId: council.id,
                                commentId: comment.id,
                              ),
                            ),
                          ),
                          onConvince: () => AuthGuard.requireAuth(
                            context,
                            () => _convince(council, comment),
                          ),
                          onReply: () => AuthGuard.requireAuth(
                            context,
                            () => _startReply(council, comment),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                if (council.allowComments)
                  _CommentInput(
                    controller: commentController,
                    focusNode: commentFocusNode,
                    replyingToName: _replyingTo?.authorName,
                    onCancelReply: _cancelReply,
                    onSend: () => _send(council),
                  )
                else
                  const _CommentsClosedNotice(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditorialNotice({bool account = false}) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryDarkGreen,
            size: 25,
          ),
        ),
        title: Text(
          account ? 'حساب تعريفي' : 'منشور تعريفي',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
        ),
        content: Text(
          account
              ? 'هذا حساب تجريبي مرتبط بمحتوى تعريفي، وليس حساب عضو حقيقي. أُضيف لعرض أمثلة مفيدة، لذلك لا تتوفر له صفحة شخصية أو مراسلة.'
              : 'هذا المنشور أعدّه فريق فرصة برو كمثال توعوي مفيد، وليس عرضًا حقيقيًا أو طلبًا قائمًا. لذلك لا يوجد صاحب فعلي يمكن مراسلته.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(fontSize: 12.5, height: 1.55),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  void _precacheCouncilImages(List<String> urls) {
    for (final url in urls.take(10)) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !_precachedImageUrls.add(url)) continue;
      unawaited(precacheImage(NetworkImage(url), context));
    }
  }

  bool _canContactOwner(CouncilModel council) {
    final ownerId = council.createdBy?.trim() ?? '';
    return ownerId.isNotEmpty &&
        council.status == CouncilStatus.active &&
        !repo.canManageCouncil(council);
  }

  Future<void> _reportCouncil(CouncilModel council) async {
    await AuthGuard.requireAuth(context, () async {
      await showReportDialog(
        context,
        onSubmit: (reason) => repo.createReport(
          targetType: 'council',
          targetPath: 'councils/${council.id}',
          reason: reason,
          councilId: council.id,
        ),
      );
    });
  }
  Future<void> _openConversation(CouncilModel council) async {
    if (council.isSeedContent) {
      await _showEditorialNotice();
      return;
    }
    if (_openingConversation) return;

    await AuthGuard.requireAuth(
      context,
      () async {
        setState(() => _openingConversation = true);
        try {
          final conversation =
              await MessagingRepository.instance.getOrCreateConversation(council);
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConversationScreen(
                conversationId: conversation.id,
                initialConversation: conversation,
              ),
            ),
          );
        } catch (error) {
          if (!mounted) return;
          final message = error.toString().contains('self-message')
              ? 'لا يمكنك مراسلة نفسك.'
              : 'تعذر فتح المحادثة. حاول مرة أخرى.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        } finally {
          if (mounted) setState(() => _openingConversation = false);
        }
      },
      allowAnonymous: false,
    );
  }
  // ignore: unused_element
  Future<void> _showCouncilActions(CouncilModel council) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardWhite,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CouncilActionTile(
                  icon: Icons.trending_up_rounded,
                  title: 'تحديث الظهور',
                  subtitle: 'يرفع الفرصة في القائمة مرة واحدة كل 24 ساعة',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _refreshVisibility(council);
                  },
                ),
                const SizedBox(height: 8),
                _CouncilActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'حذف الفرصة',
                  subtitle: 'إخفاء الفرصة من التطبيق نهائيًا',
                  destructive: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmDeleteCouncil(council);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshVisibility(CouncilModel council) async {
    final createdAt = council.createdAt;
    if (createdAt != null &&
        DateTime.now().difference(createdAt) < const Duration(hours: 24)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تحديث الظهور متاح بعد مرور 24 ساعة من نشر الفرصة أو آخر تحديث لها.'),
        ),
      );
      return;
    }

    try {
      await repo.refreshCouncilVisibility(council.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الظهور. ستظهر الفرصة أعلى القائمة الآن.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('too-soon')
          ? 'تحديث الظهور متاح بعد مرور 24 ساعة من نشر الفرصة أو آخر تحديث لها.'
          : 'تعذر تحديث الظهور. حاول مرة أخرى.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _confirmDeleteCouncil(CouncilModel council) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.cardWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.red,
              size: 25,
            ),
          ),
          title: Text(
            'حذف الفرصة؟',
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textDark,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'سيتم إخفاء الفرصة من التطبيق ولن يستطيع المستخدمون الوصول إليها بعد الحذف.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textGray,
              fontSize: 12.6,
              height: 1.55,
              fontWeight: FontWeight.w700,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: AppColors.cardWhite,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: AppTextStyles.button.copyWith(fontSize: 12.8),
                    ),
                    child: const Text('حذف'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textDark,
                      minimumSize: const Size.fromHeight(42),
                      side: const BorderSide(color: AppColors.borderBeige),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: AppTextStyles.button.copyWith(fontSize: 12.8),
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await repo.deleteCouncil(council.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفرصة')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الفرصة. حاول مرة أخرى.')),
      );
    }
  }
  Future<void> _vote(CouncilModel council, VoteOption option) async {
    if (repo.isCouncilOwner(council)) {
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('لا يمكن لصاحب الفرصة إضافة رأي سريع على فرصته.')),
      );
      return;
    }

    final previousOption = council.selectedOption;
    final removingVote = previousOption == option;
    final changingVote = previousOption != null && previousOption != option;
    final requestId = ++_voteRequestId;
    ScaffoldMessenger.of(context).clearSnackBars();

    await AuthGuard.requireAuth(context, () async {
      try {
        await repo.vote(council.id, option);
        if (!mounted || requestId != _voteRequestId) return;
        final message = removingVote
            ? 'تم إلغاء رأيك السريع'
            : changingVote
                ? 'تم تحديث رأيك السريع'
                : 'تم تسجيل رأيك السريع';
        final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
        messenger.showSnackBar(
          SnackBar(content: Text(message)),
        );
      } catch (_) {
        if (!mounted || requestId != _voteRequestId) return;
        final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الرأي. حاول مرة أخرى.')),
        );
      }
    });
  }

  Future<void> _send(CouncilModel council) async {
    final text = commentController.text.trim();
    if (text.isEmpty) return;
    if (!council.allowComments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التعليقات مغلقة لهذه الفرصة.')),
      );
      return;
    }

    final replyingTo = _replyingTo;
    await AuthGuard.requireAuth(context, () async {
      commentController.clear();
      setState(() => _replyingTo = null);
      FocusScope.of(context).unfocus();

      try {
        await repo.addComment(
          council.id,
          text,
          parentId: replyingTo?.id,
        );
        if (replyingTo != null && mounted) {
          setState(() {
            _visibleReplyLimits[replyingTo.id] =
                _replyLimitFor(replyingTo.id) + 1;
          });
        }
      } on ContentModerationException catch (error) {
        if (!mounted) return;
        _restoreCommentDraft(text, replyingTo);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      } on FirebaseException catch (error) {
        if (!mounted) return;
        _restoreCommentDraft(text, replyingTo);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_commentErrorMessage(error))),
        );
      } catch (_) {
        if (!mounted) return;
        _restoreCommentDraft(text, replyingTo);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              replyingTo == null
                  ? 'تعذر إرسال التعليق. حاول مرة أخرى.'
                  : 'تعذر إرسال الرد. حاول مرة أخرى.',
            ),
          ),
        );
      }
    });
  }

  String _commentErrorMessage(FirebaseException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;

    switch (error.code) {
      case 'unauthenticated':
        return 'سجل دخولك لإضافة التعليق.';
      case 'not-found':
        return 'هذه الفرصة لم تعد متاحة.';
      case 'invalid-argument':
        return 'راجع نص التعليق ثم حاول مرة أخرى.';
      case 'failed-precondition':
        return 'التعليقات غير متاحة لهذه الفرصة حالياً.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'تعذر الاتصال بالخادم. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }

    return 'تعذر إرسال التعليق. حاول مرة أخرى.';
  }

  void _restoreCommentDraft(String text, CommentModel? replyingTo) {
    setState(() => _replyingTo = replyingTo);
    commentController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) commentFocusNode.requestFocus();
    });
  }

  Future<void> _convince(CouncilModel council, CommentModel comment) async {
    if (_isOwnComment(comment)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تقييم تعليقك الشخصي.')),
      );
      return;
    }

    try {
      await repo.addConvincingVote(council.id, comment.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث رأيك')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث الرأي. حاول مرة أخرى.')),
      );
    }
  }

  void _startReply(CouncilModel council, CommentModel comment) {
    if (!council.allowComments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التعليقات مغلقة لهذه الفرصة.')),
      );
      return;
    }

    setState(() => _replyingTo = comment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) commentFocusNode.requestFocus();
    });
  }

  void _cancelReply() {
    if (_replyingTo == null) return;
    setState(() => _replyingTo = null);
    commentFocusNode.requestFocus();
  }

  List<_CommentThread> _threadComments(List<CommentModel> comments) {
    final repliesByParentId = <String, List<CommentModel>>{};
    final topLevel = <CommentModel>[];

    for (final comment in comments) {
      final parentId = comment.parentId;
      if (parentId == null || parentId.isEmpty) {
        topLevel.add(comment);
      } else {
        repliesByParentId
            .putIfAbsent(parentId, () => <CommentModel>[])
            .add(comment);
      }
    }

    return [
      for (final comment in topLevel)
        _CommentThread(
          comment: comment,
          replies: repliesByParentId[comment.id] ?? const <CommentModel>[],
        ),
    ];
  }

  int _replyLimitFor(String commentId) {
    return _visibleReplyLimits[commentId] ?? _initialVisibleReplies;
  }

  void _showMoreReplies(String commentId, int totalReplies) {
    setState(() {
      final next = _replyLimitFor(commentId) + _replyPageSize;
      _visibleReplyLimits[commentId] =
          next > totalReplies ? totalReplies : next;
    });
  }

  bool _isOwnComment(CommentModel comment) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final authorId = comment.authorId?.trim();
    return uid != null &&
        uid.isNotEmpty &&
        authorId != null &&
        authorId.isNotEmpty &&
        authorId == uid;
  }
}

class _CommentThread {
  const _CommentThread({required this.comment, required this.replies});

  final CommentModel comment;
  final List<CommentModel> replies;
}

class _CouncilSponsorSlot extends StatefulWidget {
  const _CouncilSponsorSlot({required this.council});

  final CouncilModel council;

  @override
  State<_CouncilSponsorSlot> createState() => _CouncilSponsorSlotState();
}

class _CouncilSponsorSlotState extends State<_CouncilSponsorSlot> {
  final _sponsorshipRepo = SponsorshipRepository.instance;
  bool _openingSponsorshipRequest = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SponsorshipCampaign?>(
      stream: _sponsorshipRepo.watchActiveForCategory(widget.council.category),
      builder: (context, snapshot) {
        final activeSponsorship = snapshot.data;

        if (activeSponsorship == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 9),
            child: _CouncilAdvertiseHereBanner(
              categoryName: widget.council.category,
              onTap: _openSponsorshipRequest,
            ),
          );
        }

        final sponsorship = activeSponsorship;
        _recordImpression(sponsorship);

        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 9),
          child: _CouncilSponsorBanner(
            sponsorship: sponsorship,
            onTap: () => _openSponsor(sponsorship),
          ),
        );
      },
    );
  }

  Future<void> _openSponsorshipRequest() async {
    if (_openingSponsorshipRequest || !mounted) return;
    _openingSponsorshipRequest = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SponsorshipScreen(initialCategory: widget.council.category),
        ),
      );
    } finally {
      _openingSponsorshipRequest = false;
    }
  }

  void _recordImpression(SponsorshipCampaign sponsorship) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sponsorshipRepo.recordImpression(sponsorship.id));
    });
  }

  Future<void> _openSponsor(SponsorshipCampaign sponsorship) async {
    final uri = Uri.tryParse(sponsorship.targetUrl);
    if (uri == null || !uri.hasScheme) {
      _showSponsorLinkError();
      return;
    }

    try {
      unawaited(_sponsorshipRepo.recordClick(sponsorship.id));
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _showSponsorLinkError();
    } catch (_) {
      _showSponsorLinkError();
    }
  }

  void _showSponsorLinkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح رابط الراعي حاليًا.')),
    );
  }
}

class _CouncilAdvertiseHereBanner extends StatelessWidget {
  const _CouncilAdvertiseHereBanner({
    required this.categoryName,
    required this.onTap,
  });

  final String categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppColors.cardWhite,
                  Color(0xFFFFFBF1),
                ],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.gold.withValues(alpha: .66)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F4A35),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .50),
                    ),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: AppColors.gold,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أعلن هنا',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardTitle.copyWith(
                          color: AppColors.primaryDarkGreen,
                          fontSize: 14.2,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اجعل إعلانك حاضرًا داخل الفرص المناسبة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textGray,
                          fontSize: 10.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDarkGreen,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .46),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'اطلب الإعلان',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.cardWhite,
                        fontSize: 9.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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

class _CouncilSponsorBanner extends StatelessWidget {
  const _CouncilSponsorBanner({
    required this.sponsorship,
    this.onTap,
  });

  final SponsorshipCampaign sponsorship;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.gold.withValues(alpha: .58)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F4A35),
                  blurRadius: 9,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _CouncilSponsorLogo(url: sponsorship.logoUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'برعاية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.warningGold,
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sponsorship.sponsorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardTitle.copyWith(
                          color: AppColors.primaryDarkGreen,
                          fontSize: 13.4,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .44),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'زيارة',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cardWhite,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: AppColors.gold,
                        size: 13,
                      ),
                    ],
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

class _CouncilSponsorLogo extends StatelessWidget {
  const _CouncilSponsorLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final validImageUrl = uri != null && uri.hasScheme;

    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primaryDarkGreen.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.borderBeige),
      ),
      child: validImageUrl
          ? OptimizedNetworkImage(
              url: url,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              quality: OptimizedImageQuality.thumbnail,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_rounded,
                color: AppColors.primaryDarkGreen,
                size: 20,
              ),
            )
          : const Icon(
              Icons.storefront_rounded,
              color: AppColors.primaryDarkGreen,
              size: 20,
            ),
    );
  }
}

class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({required this.council});
  final CouncilModel council;

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
            color: Color(0x0D0F4A35),
            blurRadius: 9,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.borderBeige.withValues(alpha: .62),
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
                  ),
                ),
                const SizedBox(width: 10),
                _CouncilCityTimeInfo(
                  city: council.city,
                  createdAt: council.createdAt,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            council.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.pageTitle.copyWith(
              fontSize: 16.5,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            council.description,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textGray,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.how_to_vote_outlined,
                size: 14,
                color: AppColors.gold,
              ),
              const SizedBox(width: 4),
              Text(
                council.votesCount <= 0 ? 'كن أول من يبدي رأيه' : '${council.votesCount} رأي',
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CouncilCityTimeInfo extends StatelessWidget {
  const _CouncilCityTimeInfo({required this.city, required this.createdAt});

  final String city;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final cityLabel = city.trim().isEmpty ? 'غير محددة' : city.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 118),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 12,
                color: AppColors.primaryDarkGreen,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  cityLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primaryDarkGreen,
                    fontSize: 10.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            RelativeTimeText(
              dateTime: createdAt,
              textAlign: TextAlign.left,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textGray.withValues(alpha: .80),
                fontSize: 10.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CouncilQuickActions extends StatelessWidget {
  const _CouncilQuickActions({
    required this.showContact,
    required this.showOwnerActions,
    required this.contactLoading,
    required this.onContact,
    required this.onRefresh,
    required this.onDelete,
  });

  final bool showContact;
  final bool showOwnerActions;
  final bool contactLoading;
  final VoidCallback onContact;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (showContact)
            _CouncilActionIcon(
              icon: Icons.chat_bubble_outline_rounded,
              tooltip: 'تواصل',
              loading: contactLoading,
              backgroundColor: AppColors.primaryDarkGreen,
              foregroundColor: AppColors.cardWhite,
              onTap: onContact,
            ),
          if (showOwnerActions) ...[
            _CouncilActionIcon(
              icon: Icons.refresh_rounded,
              tooltip: 'تحديث الظهور',
              backgroundColor: AppColors.primaryGreen.withValues(alpha: .10),
              foregroundColor: AppColors.primaryDarkGreen,
              onTap: onRefresh,
            ),
            const SizedBox(width: 8),
            _CouncilActionIcon(
              icon: Icons.delete_outline_rounded,
              tooltip: 'حذف الفرصة',
              backgroundColor: AppColors.red.withValues(alpha: .10),
              foregroundColor: AppColors.red,
              onTap: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _CouncilActionIcon extends StatelessWidget {
  const _CouncilActionIcon({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: loading ? null : onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: foregroundColor.withValues(alpha: .22)),
            ),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foregroundColor,
                      ),
                    )
                  : Icon(icon, size: 16, color: foregroundColor),
            ),
          ),
        ),
      ),
    );
  }
}
class _CouncilImagesGrid extends StatelessWidget {
  const _CouncilImagesGrid({required this.council});

  final CouncilModel council;

  @override
  Widget build(BuildContext context) {
    final originals = council.imageUrls.take(10).toList(growable: false);
    if (originals.isEmpty) return const SizedBox.shrink();
    final thumbnails = council.thumbnailImageUrls.take(10).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemSize = ((constraints.maxWidth - 32) / 5).clamp(54.0, 70.0);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < originals.length; index++)
              _CouncilImageThumb(
                url: index < thumbnails.length ? thumbnails[index] : originals[index],
                size: itemSize,
                onTap: () => _openImageViewer(context, originals, index),
              ),
          ],
        );
      },
    );
  }

  void _openImageViewer(
    BuildContext context,
    List<String> urls,
    int initialIndex,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .84),
      builder: (_) => _CouncilImageViewer(
        imageUrls: urls,
        initialIndex: initialIndex,
      ),
    );
  }
}

class _CouncilImageThumb extends StatelessWidget {
  const _CouncilImageThumb({
    required this.url,
    required this.size,
    required this.onTap,
  });

  final String url;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: OptimizedNetworkImage(
          url: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          quality: OptimizedImageQuality.thumbnail,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textGray,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _CouncilImageViewer extends StatefulWidget {
  const _CouncilImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_CouncilImageViewer> createState() => _CouncilImageViewerState();
}

class _CouncilImageViewerState extends State<_CouncilImageViewer> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: size.height * .72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.textDark,
              borderRadius: BorderRadius.circular(22),
            ),
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) => setState(() {
                _currentIndex = index;
              }),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 3,
                child: Center(
                  child: OptimizedNetworkImage(
                    url: widget.imageUrls[index],
                    fit: BoxFit.contain,
                    quality: OptimizedImageQuality.original,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.cardWhite,
                      size: 42,
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 12,
            start: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.textDark.withValues(alpha: .70),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: AppColors.cardWhite,
                  size: 19,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 12,
            start: 0,
            end: 0,
            child: Center(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.textDark.withValues(alpha: .70),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    '${_currentIndex + 1}/${widget.imageUrls.length}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.cardWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({required this.council, required this.isOwner});
  final CouncilModel council;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final voteCopy = OpportunityVoteCopy.forCouncil(council);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.borderBeige),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOwner && council.votesCount <= 0
                ? 'لم تصل آراء بعد'
                : isOwner || council.hasVoted
                ? 'نتيجة الرأي السريع'
                : 'اختر رأيك السريع لرؤية النتائج',
            style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
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
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.replies,
    required this.visibleReplyLimit,
    required this.allowReplies,
    required this.isOwnComment,
    required this.isConvinced,
    this.onAuthorTap,
    required this.onReport,
    required this.onConvince,
    required this.onReply,
    this.onShowMoreReplies,
  });

  final CommentModel comment;
  final List<CommentModel> replies;
  final int visibleReplyLimit;
  final bool allowReplies;
  final bool isOwnComment;
  final bool isConvinced;
  final VoidCallback? onAuthorTap;
  final VoidCallback onReport;
  final VoidCallback onConvince;
  final VoidCallback onReply;
  final VoidCallback? onShowMoreReplies;

  @override
  Widget build(BuildContext context) {
    final visibleReplies = replies.take(visibleReplyLimit).toList(growable: false);
    final remainingReplies = replies.length - visibleReplies.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: comment.isBest ? AppColors.gold : AppColors.borderBeige,
          width: comment.isBest ? 1.2 : 1,
        ),
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
          if (comment.isBest)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'أفضل رأي في الفرصة',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primaryDarkGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAuthorTap,
                child: AvatarBadge(label: comment.avatarEmoji, size: 34),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      comment.timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.text,
            style: AppTextStyles.body.copyWith(fontSize: 12.5, height: 1.42),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              if (!isOwnComment)
                _CommentAction(
                  onPressed: onConvince,
                  icon: isConvinced
                      ? Icons.thumb_up_alt_rounded
                      : Icons.thumb_up_alt_outlined,
                  label: 'رأي مقنع ${comment.convincingCount}',
                  color: AppColors.primaryDarkGreen,
                  selected: isConvinced,
                ),
              if (allowReplies)
                _CommentAction(
                  onPressed: onReply,
                  icon: Icons.reply_rounded,
                  label: 'رد ${comment.repliesCount}',
                  color: AppColors.textGray,
                ),
              if (!isOwnComment)
                _CommentAction(
                  onPressed: onReport,
                  icon: Icons.flag_outlined,
                  label: 'إبلاغ',
                  color: AppColors.textGray,
                ),
            ],
          ),
          if (visibleReplies.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CommentReplies(
              replies: visibleReplies,
              remainingReplies: remainingReplies,
              onShowMore: onShowMoreReplies,
              onAuthorTap: onAuthorTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentReplies extends StatelessWidget {
  const _CommentReplies({
    required this.replies,
    required this.remainingReplies,
    required this.onShowMore,
    this.onAuthorTap,
  });

  final List<CommentModel> replies;
  final int remainingReplies;
  final VoidCallback? onShowMore;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 34),
      padding: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: AppColors.borderBeige.withValues(alpha: .85)),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < replies.length; index++) ...[
            if (index > 0) const SizedBox(height: 7),
            _ReplyTile(reply: replies[index], onAuthorTap: onAuthorTap),
          ],
          if (remainingReplies > 0 && onShowMore != null) ...[
            const SizedBox(height: 3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onShowMore,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                label: Text('إظهار المزيد من الردود ($remainingReplies)'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDarkGreen,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  textStyle: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply, this.onAuthorTap});

  final CommentModel reply;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: reply.isSeedContent ? onAuthorTap : null,
          child: AvatarBadge(label: reply.avatarEmoji, size: 26),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reply.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    reply.timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 9.8),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                reply.text,
                style: AppTextStyles.body.copyWith(fontSize: 12, height: 1.38),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.selected = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.cardWhite : color,
        backgroundColor: selected ? color : Colors.transparent,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 9 : 2,
          vertical: selected ? 5 : 4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected ? color : Colors.transparent,
          ),
        ),
        textStyle: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _CommentsClosedNotice extends StatelessWidget {
  const _CommentsClosedNotice();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 7, 16, 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderBeige),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryDarkGreen,
                size: 16,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'التعليقات مغلقة لهذه الفرصة',
                textAlign: TextAlign.right,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.replyingToName,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? replyingToName;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isReplying = replyingToName != null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 9),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.borderBeige.withValues(alpha: .7)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isReplying
                  ? Container(
                      key: ValueKey(replyingToName),
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 4, 5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primaryGreen.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.reply_rounded,
                            color: AppColors.primaryDarkGreen,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'الرد على $replyingToName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primaryDarkGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onCancelReply,
                            tooltip: 'إلغاء الرد',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textGray,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      textAlign: TextAlign.right,
                      style: AppTextStyles.body.copyWith(fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: isReplying ? 'اكتب ردك...' : 'اكتب تعليقك...',
                        hintStyle:
                            AppTextStyles.caption.copyWith(fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              const BorderSide(color: AppColors.borderBeige),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              const BorderSide(color: AppColors.borderBeige),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: AppColors.primaryGreen,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSend,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      gradient: AppColors.headerGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.cardWhite,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CouncilActionTile extends StatelessWidget {
  const _CouncilActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.primaryDarkGreen;

    return Material(
      color: destructive
          ? AppColors.red.withValues(alpha: .06)
          : AppColors.primaryDarkGreen.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.cardTitle.copyWith(
                        color: color,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textGray,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
