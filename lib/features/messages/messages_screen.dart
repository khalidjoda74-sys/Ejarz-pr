import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/app_page_route.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../data/models/conversation_model.dart';
import '../../data/repositories/messaging_repository.dart';
import 'conversation_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _showArchived = false;
  bool _openingConversation = false;
  late final Stream<List<ConversationModel>> _activeConversationsStream;
  late final Stream<List<ConversationModel>> _archivedConversationsStream;

  @override
  void initState() {
    super.initState();
    final repository = MessagingRepository.instance;
    _activeConversationsStream =
        repository.watchMyConversations(includeArchived: false);
    _archivedConversationsStream =
        repository.watchMyConversations(includeArchived: true);
  }

  Future<void> _openConversation(ConversationModel conversation) async {
    if (_openingConversation || !mounted) return;
    _openingConversation = true;
    try {
      final repository = MessagingRepository.instance;
      if (conversation.unreadFor(repository.viewerUid) > 0) {
        unawaited(repository.markConversationRead(conversation.id));
      }
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ConversationScreen(
            conversationId: conversation.id,
            initialConversation: conversation,
          ),
        ),
      );
    } finally {
      _openingConversation = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = MessagingRepository.instance;
    final currentUid = repo.viewerUid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            CustomGreenHeader(
              title: _showArchived ? 'الأرشيف' : 'الرسائل',
              subtitle: _showArchived
                  ? 'المحادثات المؤرشفة'
                  : 'محادثاتك المباشرة وحول الفرص',
              showBack: true,
              onBack: widget.onBack,
              trailing: HeaderRoundButton(
                icon: _showArchived
                    ? Icons.mark_chat_unread_outlined
                    : Icons.archive_outlined,
                onTap: () => setState(() => _showArchived = !_showArchived),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ConversationModel>>(
                stream: _showArchived
                    ? _archivedConversationsStream
                    : _activeConversationsStream,
                builder: (context, snapshot) {
                  final conversations =
                      snapshot.data ?? const <ConversationModel>[];

                  if (snapshot.hasError) {
                    return const _MessagesState(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذر تحميل الرسائل',
                      message:
                          'راجع الاتصال أو صلاحيات الحساب ثم حاول مرة أخرى.',
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      conversations.isEmpty) {
                    return const _MessagesSkeleton();
                  }

                  if (currentUid.isEmpty) {
                    return const _MessagesState(
                      icon: Icons.lock_outline_rounded,
                      title: 'سجل الدخول للرسائل',
                      message: 'المحادثات تظهر للأعضاء المسجلين فقط.',
                    );
                  }

                  if (conversations.isEmpty) {
                    return _MessagesState(
                      icon: _showArchived
                          ? Icons.archive_outlined
                          : Icons.chat_bubble_outline_rounded,
                      title: _showArchived ? 'الأرشيف فارغ' : 'لا توجد رسائل',
                      message: _showArchived
                          ? 'المحادثات التي تؤرشفها ستظهر هنا، ويمكنك فتحها وفك الأرشفة.'
                          : 'ستظهر هنا المحادثات المباشرة والمحادثات المرتبطة بالفرص.',
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.of(context).horizontalPadding,
                      12,
                      AppSizes.of(context).horizontalPadding,
                      MediaQuery.viewPaddingOf(context).bottom + 18,
                    ),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return _ConversationTile(
                        conversation: conversation,
                        currentUid: currentUid,
                        onTap: () => _openConversation(conversation),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesSkeleton extends StatelessWidget {
  const _MessagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSizes.of(context).horizontalPadding,
        12,
        AppSizes.of(context).horizontalPadding,
        MediaQuery.viewPaddingOf(context).bottom + 18,
      ),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => Container(
        height: 78,
        decoration: BoxDecoration(
          color: AppColors.cardWhite.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppColors.borderBeige),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUid,
    required this.onTap,
  });

  final ConversationModel conversation;
  final String currentUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherParticipant(currentUid);
    final unread = conversation.unreadFor(currentUid);
    final hasUnread = unread > 0;
    final sentByMe = conversation.lastSenderId == currentUid;
    final lastText = conversation.lastMessageText.isEmpty
        ? 'لم تبدأ المحادثة بعد'
        : '${sentByMe ? 'أنت: ' : ''}${conversation.lastMessageText}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasUnread
                ? AppColors.primaryGreen.withValues(alpha: .08)
                : AppColors.cardWhite,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: hasUnread
                  ? AppColors.primaryGreen.withValues(alpha: .32)
                  : AppColors.borderBeige,
              width: hasUnread ? 1.2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F4A35),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              _ConversationAvatar(
                label: other?.avatarEmoji,
                active: hasUnread,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            other?.displayName ?? 'عضو Forsa Pro',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 14,
                              color: AppColors.textDark,
                              fontWeight:
                                  hasUnread ? FontWeight.w900 : FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(conversation.sortAt),
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10.5,
                            color: hasUnread
                                ? AppColors.primaryDarkGreen
                                : AppColors.textGray,
                            fontWeight:
                                hasUnread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ConversationContextBadge(
                      contextType: conversation.contextType,
                      opportunityTitle: conversation.councilTitle,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12.2,
                              color: hasUnread
                                  ? AppColors.textDark
                                  : AppColors.textGray,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: unread),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return 'الآن';
    if (difference.inMinutes < 60) return 'قبل ${difference.inMinutes} د';
    if (difference.inHours < 24) return 'قبل ${difference.inHours} س';
    if (difference.inDays == 1) return 'أمس';
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }
}

class _ConversationContextBadge extends StatelessWidget {
  const _ConversationContextBadge({
    required this.contextType,
    required this.opportunityTitle,
  });

  final ConversationContextType contextType;
  final String? opportunityTitle;

  @override
  Widget build(BuildContext context) {
    final direct = contextType == ConversationContextType.direct;
    final color = direct ? AppColors.primaryGreen : AppColors.primaryDarkGreen;
    final label = direct
        ? 'محادثة مباشرة'
        : (opportunityTitle?.trim().isNotEmpty == true
            ? opportunityTitle!.trim()
            : 'محادثة حول فرصة');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              direct ? Icons.person_outline_rounded : Icons.campaign_outlined,
              size: 12.5,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10.8,
                  color: color,
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

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.label, required this.active});

  final String? label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryDarkGreen.withValues(alpha: .10)
            : AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? AppColors.primaryGreen.withValues(alpha: .34)
              : AppColors.borderBeige,
        ),
      ),
      child: AvatarBadge(
        label: (label == null || label!.isEmpty)
            ? 'business:person_growth'
            : label!,
        size: 40,
        border: active,
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: const BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.cardWhite,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MessagesState extends StatelessWidget {
  const _MessagesState({
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
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.primaryDarkGreen.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppColors.primaryDarkGreen,
                size: 28,
              ),
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
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textGray,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
