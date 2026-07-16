import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/moderation/content_moderation.dart';
import '../../core/notifications/notification_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/optimized_network_image.dart';
import '../../core/widgets/premium_background.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/messaging_repository.dart';
import '../councils/council_details_screen.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    this.initialConversation,
  });

  final String conversationId;
  final ConversationModel? initialConversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final MessagingRepository _repo = MessagingRepository.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  late final String _currentUid;
  bool _sending = false;
  bool _pickingImage = false;
  bool _actionBusy = false;
  bool _readMarkScheduled = false;
  bool _openingCouncil = false;

  @override
  void initState() {
    super.initState();
    _currentUid = _repo.viewerUid;
    NotificationRouter.activeConversationId = widget.conversationId;
    unawaited(_repo.markConversationRead(widget.conversationId));
  }

  @override
  void dispose() {
    if (NotificationRouter.activeConversationId == widget.conversationId) {
      NotificationRouter.activeConversationId = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConversationModel?>(
      stream: _repo.watchConversation(widget.conversationId),
      initialData: widget.initialConversation,
      builder: (context, conversationSnapshot) {
        final conversation = conversationSnapshot.data ?? widget.initialConversation;
        final otherName = conversation?.otherParticipant(_currentUid)?.displayName;
        final blocked = conversation?.isBlocked == true;
        if (conversation != null &&
            conversation.unreadFor(_currentUid) > 0 &&
            !_readMarkScheduled) {
          _readMarkScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await _repo.markConversationRead(widget.conversationId);
            } finally {
              _readMarkScheduled = false;
            }
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackground(
            showPattern: false,
            child: Column(
              children: [
                CustomGreenHeader(
                  title: otherName == null || otherName.isEmpty
                      ? 'المحادثة'
                      : otherName,
                  subtitle: 'رسائل مباشرة',
                  showBack: true,
                  trailing: conversation == null
                      ? null
                      : HeaderRoundButton(
                          icon: Icons.more_horiz_rounded,
                          onTap: () => _showConversationActions(conversation),
                        ),
                ),
                Expanded(
                  child: StreamBuilder<List<MessageModel>>(
                    stream: _repo.watchMessages(widget.conversationId),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const <MessageModel>[];
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          messages.isEmpty) {
                        return const _ConversationMessagesSkeleton();
                      }

                      if (snapshot.hasError) {
                        return const _EmptyConversationState(
                          title: 'تعذر تحميل الرسائل',
                          message: 'راجع الاتصال أو صلاحيات الحساب ثم حاول مرة أخرى.',
                        );
                      }

                      if (messages.isEmpty && conversation == null) {
                        return const _EmptyConversationState();
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                        }
                      });

                      return ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          AppSizes.of(context).horizontalPadding,
                          12,
                          AppSizes.of(context).horizontalPadding,
                          12,
                        ),
                        itemCount: messages.length + (conversation == null ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (conversation != null && index == 0) {
                            return _ConversationOpportunityCard(
                              conversation: conversation,
                              onTap: () => _openCouncil(conversation.councilId),
                            );
                          }
                          final message = messages[index - (conversation == null ? 0 : 1)];
                          return _MessageBubble(
                            message: message,
                            mine: message.senderId == _currentUid,
                            sender: conversation?.participantSnapshots[message.senderId],
                          );
                        },
                      );
                    },
                  ),
                ),
                if (blocked)
                  const _BlockedConversationNotice()
                else
                  _MessageComposer(
                    controller: _messageController,
                    sending: _sending,
                    pickingImage: _pickingImage,
                    onSend: _sendMessage,
                    onPickImage: _sendImage,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConversationActions(ConversationModel conversation) async {
    if (_actionBusy) return;
    final blockedByMe = conversation.blockedBy.contains(_currentUid);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardWhite,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConversationActionTile(
                icon: Icons.flag_outlined,
                label: 'بلاغ عن المحادثة',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _reportConversation(conversation);
                },
              ),
              _ConversationActionTile(
                icon: blockedByMe
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                label: blockedByMe
                    ? 'فك حظر المستخدم'
                    : conversation.isBlocked
                        ? 'المحادثة محظورة من الطرف الآخر'
                        : 'حظر المستخدم',
                destructive: !blockedByMe,
                enabled: !conversation.isBlocked || blockedByMe,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  blockedByMe
                      ? _unblockConversation(conversation)
                      : _confirmBlockConversation(conversation);
                },
              ),
              _ConversationActionTile(
                icon: conversation.isArchivedFor(_currentUid)
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: conversation.isArchivedFor(_currentUid)
                    ? 'فك الأرشفة'
                    : 'أرشفة المحادثة',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  conversation.isArchivedFor(_currentUid)
                      ? _unarchiveConversation(conversation)
                      : _archiveConversation(conversation);
                },
              ),
              _ConversationActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'حذف المحادثة من عندي',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteConversation(conversation);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCouncil(String councilId) async {
    if (_openingCouncil || !mounted) return;
    _openingCouncil = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CouncilDetailsScreen(councilId: councilId),
        ),
      );
    } finally {
      _openingCouncil = false;
    }
  }

  Future<void> _reportConversation(ConversationModel conversation) async {
    final input = await showDialog<_ConversationReportInput>(
      context: context,
      builder: (_) => const _ConversationReportDialog(),
    );
    if (input == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _repo.reportConversation(
        conversation.id,
        reason: input.reason,
        details: input.details,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال البلاغ للمراجعة.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال البلاغ. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _confirmBlockConversation(ConversationModel conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _BlockConversationDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _repo.blockConversation(conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حظر المستخدم. لن يتم إرسال رسائل جديدة.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حظر المحادثة. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _unblockConversation(ConversationModel conversation) async {
    setState(() => _actionBusy = true);
    try {
      await _repo.unblockConversation(conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم فك حظر المستخدم.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فك الحظر. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }
  Future<void> _archiveConversation(ConversationModel conversation) async {
    setState(() => _actionBusy = true);
    try {
      await _repo.archiveConversation(conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت أرشفة المحادثة.')),
      );
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر أرشفة المحادثة. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _unarchiveConversation(ConversationModel conversation) async {
    setState(() => _actionBusy = true);
    try {
      await _repo.unarchiveConversation(conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم فك أرشفة المحادثة.')),
      );
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فك الأرشفة. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _confirmDeleteConversation(ConversationModel conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteConversationDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _repo.deleteConversationForMe(conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المحادثة من قائمتك فقط.')),
      );
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف المحادثة. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending || _pickingImage) return;
    if (text.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرسالة طويلة جدًا. الحد 1000 حرف.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.sendMessage(widget.conversationId, text);
      if (!mounted) return;
      _messageController.clear();
      unawaited(_repo.markConversationRead(widget.conversationId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sendErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending || _pickingImage) return;
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;

    setState(() => _pickingImage = true);
    try {
      final uploaded = await _repo.uploadConversationImage(
        widget.conversationId,
        image,
      );
      await _repo.sendImageMessage(
        widget.conversationId,
        imageUrl: uploaded.url,
        imagePath: uploaded.path,
      );
      if (!mounted) return;
      unawaited(_repo.markConversationRead(widget.conversationId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_imageErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  String _sendErrorMessage(Object error) {
    if (error is ContentModerationException) return error.message;
    final value = error.toString();
    if (value.contains('blocked-conversation')) {
      return 'لا يمكن إرسال رسائل جديدة بعد حظر المحادثة.';
    }
    if (value.contains('message-too-long')) {
      return 'الرسالة طويلة جدًا. الحد 1000 حرف.';
    }
    if (value.contains('permission-denied')) {
      return 'لا تملك صلاحية الإرسال في هذه المحادثة.';
    }
    return 'تعذر إرسال الرسالة. حاول مرة أخرى.';
  }

  String _imageErrorMessage(Object error) {
    final value = error.toString();
    if (value.contains('invalid-image')) {
      return 'تعذر إرسال الصورة. الحد الأقصى 5 ميجا.';
    }
    if (value.contains('blocked-conversation')) {
      return 'لا يمكن إرسال صور بعد حظر المحادثة.';
    }
    if (value.contains('permission-denied')) {
      return 'لا تملك صلاحية إرسال صورة في هذه المحادثة.';
    }
    return 'تعذر إرسال الصورة. حاول مرة أخرى.';
  }
}

class _EmptyConversationState extends StatelessWidget {
  const _EmptyConversationState({
    this.title = 'ابدأ المحادثة',
    this.message = 'اكتب رسالتك الأولى بوضوح، واجعل التواصل مرتبطًا بتفاصيل الفرصة.',
  });

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
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primaryDarkGreen,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.cardTitle.copyWith(fontSize: 15)),
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

class _ConversationMessagesSkeleton extends StatelessWidget {
  const _ConversationMessagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSizes.of(context).horizontalPadding,
        12,
        AppSizes.of(context).horizontalPadding,
        12,
      ),
      itemCount: 5,
      itemBuilder: (context, index) {
        final mine = index.isOdd;
        return Align(
          alignment: mine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: MediaQuery.sizeOf(context).width * (mine ? .58 : .70),
            height: index == 0 ? 42 : 54,
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: AppColors.cardWhite.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderBeige),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationOpportunityCard extends StatelessWidget {
  const _ConversationOpportunityCard({
    required this.conversation,
    required this.onTap,
  });

  final ConversationModel conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: .20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.primaryDarkGreen,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الإعلان المرتبط بالمحادثة',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primaryDarkGreen,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        conversation.councilTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardTitle.copyWith(
                          color: AppColors.textDark,
                          fontSize: 13.2,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.primaryDarkGreen,
                  size: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedConversationNotice extends StatelessWidget {
  const _BlockedConversationNotice();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppSizes.of(context).horizontalPadding,
          10,
          AppSizes.of(context).horizontalPadding,
          12,
        ),
        color: AppColors.cardWhite,
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: AppColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم إيقاف إرسال الرسائل في هذه المحادثة. يمكنك قراءة الرسائل السابقة فقط.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textDark,
                  fontSize: 11.5,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    this.sender,
  });

  final MessageModel message;
  final bool mine;
  final ParticipantSnapshot? sender;

  @override
  Widget build(BuildContext context) {
    final image = message.isImage;
    final showText = message.text.isNotEmpty && (!image || message.text != 'صورة');
    final maxWidth = MediaQuery.sizeOf(context).width * .76;

    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          AvatarBadge(
            label: sender?.avatarEmoji ?? 'business:person_growth',
            size: 30,
            border: true,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(image ? 5 : 0),
        decoration: BoxDecoration(
          color: mine ? AppColors.primaryDarkGreen : AppColors.cardWhite,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 5),
            bottomEnd: Radius.circular(mine ? 5 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.borderBeige),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F4A35),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: image ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image)
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(
                    width: maxWidth - 10,
                    height: 190,
                    child: OptimizedNetworkImage(
                      url: message.imageUrl!,
                      width: maxWidth - 10,
                      height: 190,
                      fit: BoxFit.cover,
                      quality: OptimizedImageQuality.medium,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppColors.background,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.background,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ),
                ),
              if (showText) ...[
                if (image) const SizedBox(height: 7),
                Text(
                  message.text,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body.copyWith(
                    color: mine ? AppColors.cardWhite : AppColors.textDark,
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
              ],
              SizedBox(height: image ? 4 : 5),
              Padding(
                padding: image ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
                child: Text(
                  _formatTime(message.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    color: mine
                        ? AppColors.cardWhite.withValues(alpha: .68)
                        : AppColors.textGray,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
        ),
      ],
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return 'الآن';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return 'الآن';
    if (difference.inMinutes < 60) return 'قبل ${difference.inMinutes} د';
    if (difference.inHours < 24) return 'قبل ${difference.inHours} س';
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.sending,
    required this.pickingImage,
    required this.onSend,
    required this.onPickImage,
  });

  final TextEditingController controller;
  final bool sending;
  final bool pickingImage;
  final VoidCallback onSend;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final busy = sending || pickingImage;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSizes.of(context).horizontalPadding,
          8,
          AppSizes.of(context).horizontalPadding,
          10,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardWhite,
          boxShadow: [
            BoxShadow(
              color: Color(0x120F4A35),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: busy ? null : onPickImage,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryDarkGreen.withValues(alpha: .08),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.borderBeige),
                ),
                child: pickingImage
                    ? const Center(
                        child: SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(
                        Icons.image_outlined,
                        color: AppColors.primaryDarkGreen,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textInputAction: TextInputAction.newline,
                textAlign: TextAlign.right,
                style: AppTextStyles.body.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'اكتب رسالة...',
                  hintStyle: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: AppColors.borderBeige),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: AppColors.borderBeige),
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
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: sending ? null : AppColors.headerGradient,
                  color: sending ? AppColors.textGray.withValues(alpha: .28) : null,
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Center(
                        child: SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.cardWhite,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: AppColors.cardWhite,
                        size: 19,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationActionTile extends StatelessWidget {
  const _ConversationActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.primaryDarkGreen;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? color : AppColors.textGray, size: 21),
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(
          color: enabled
              ? (destructive ? AppColors.red : AppColors.textDark)
              : AppColors.textGray,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ConversationReportInput {
  const _ConversationReportInput({required this.reason, required this.details});

  final String reason;
  final String details;
}

class _ConversationReportDialog extends StatefulWidget {
  const _ConversationReportDialog();

  @override
  State<_ConversationReportDialog> createState() => _ConversationReportDialogState();
}

class _ConversationReportDialogState extends State<_ConversationReportDialog> {
  final detailsController = TextEditingController();
  String reason = 'إساءة أو مضايقة';

  static const reasons = [
    'إساءة أو مضايقة',
    'احتيال أو طلب مشبوه',
    'محتوى غير مناسب',
    'سبام',
    'غير ذلك',
  ];

  @override
  void dispose() {
    detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('بلاغ عن المحادثة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: reason,
              items: reasons
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => reason = value);
              },
              decoration: const InputDecoration(labelText: 'سبب البلاغ'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: detailsController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'تفاصيل إضافية',
                hintText: 'اكتب ما يساعد فريق المراجعة بدون مشاركة بيانات حساسة',
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(
                    _ConversationReportInput(
                      reason: reason,
                      details: detailsController.text.trim(),
                    ),
                  ),
                  child: const Text('إرسال البلاغ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockConversationDialog extends StatelessWidget {
  const _BlockConversationDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حظر المستخدم؟'),
        content: const Text(
          'بعد الحظر لن يتمكن أي طرف من إرسال رسائل جديدة داخل هذه المحادثة، وستبقى الرسائل السابقة قابلة للقراءة.',
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('حظر'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteConversationDialog extends StatelessWidget {
  const _DeleteConversationDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حذف المحادثة؟'),
        content: const Text(
          'سيتم إخفاء المحادثة من قائمتك فقط، ولن تُحذف من حساب الطرف الآخر. إذا وصلت رسالة جديدة قد تظهر المحادثة مرة أخرى.',
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('حذف'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
