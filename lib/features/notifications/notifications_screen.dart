import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/notifications/notification_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/models/notification_model.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/firebase_notification_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final repo = CouncilRepository.instance;
  final Set<String> _locallyReadNotificationIds = <String>{};
  bool _openingNotification = false;

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final auth = AuthController.instance;

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final uid = auth.user?.uid;
        if (auth.isSignedIn && uid != null) {
          return StreamBuilder<List<NotificationModel>>(
            stream: FirebaseNotificationRepository.instance.watchNotifications(
              uid: uid,
            ),
            builder: (context, snapshot) {
              final firestoreNotifications = snapshot.data;
              final hasFirestoreNotifications = firestoreNotifications != null;
              final baseNotifications =
                  firestoreNotifications ?? const <NotificationModel>[];
              final notifications = _withLocalReadState(baseNotifications);
              return _NotificationsScaffold(
                sizes: sizes,
                onBack: widget.onBack,
                notifications: notifications,
                loading: snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData,
                errorMessage: snapshot.hasError && !snapshot.hasData
                    ? 'تعذر تحميل الإشعارات. تحقق من الاتصال ثم حاول مرة أخرى.'
                    : null,
                onRetry: () => setState(() {}),
                onMarkAllAsRead: notifications.any((item) => !item.read)
                    ? () => _markAllAsRead(
                          uid: uid,
                          notifications: notifications,
                          persistToFirestore: hasFirestoreNotifications,
                        )
                    : null,
                onNotificationTap: (notification) => _openNotification(
                  context,
                  notification,
                  uid,
                  persistToFirestore: hasFirestoreNotifications,
                ),
              );
            },
          );
        }

        final notifications = _withLocalReadState(repo.notifications);
        return _NotificationsScaffold(
          sizes: sizes,
          onBack: widget.onBack,
          notifications: notifications,
          onMarkAllAsRead: notifications.any((item) => !item.read)
              ? () => _markAllAsRead(
                    notifications: notifications,
                    persistToFirestore: false,
                  )
              : null,
          onNotificationTap: (notification) => _openLocalNotification(
            context,
            notification,
          ),
        );
      },
    );
  }

  List<NotificationModel> _withLocalReadState(
    List<NotificationModel> notifications,
  ) {
    return notifications
        .where((notification) =>
            notification.type != 'best_comment' &&
            !notification.title.contains('أفضل مساهمة'))
        .map((notification) => _locallyReadNotificationIds.contains(notification.id)
            ? _notificationWithRead(notification)
            : notification)
        .toList(growable: false);
  }

  NotificationModel _notificationWithRead(NotificationModel notification) {
    if (notification.read) return notification;
    return NotificationModel(
      id: notification.id,
      title: notification.title,
      message: notification.message,
      time: notification.time,
      icon: notification.icon,
      type: notification.type,
      read: true,
      targetRoute: notification.targetRoute,
      councilId: notification.councilId,
      commentId: notification.commentId,
      conversationId: notification.conversationId,
      messageId: notification.messageId,
      iconKey: notification.iconKey,
      createdAt: notification.createdAt,
    );
  }

  Future<void> _markAllAsRead({
    String? uid,
    required List<NotificationModel> notifications,
    required bool persistToFirestore,
  }) async {
    setState(() {
      _locallyReadNotificationIds.addAll(
        notifications.map((notification) => notification.id),
      );
    });

    if (persistToFirestore && uid != null) {
      await FirebaseNotificationRepository.instance.markAllAsRead(uid);
    }
  }

  Future<void> _openLocalNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    if (_openingNotification) return;
    _openingNotification = true;
    setState(() {
      _locallyReadNotificationIds.add(notification.id);
    });
    try {
      await NotificationRouter.openNotification(notification, context: context);
    } finally {
      _openingNotification = false;
    }
  }

  Future<void> _openNotification(
    BuildContext context,
    NotificationModel notification,
    String uid, {
    required bool persistToFirestore,
  }) async {
    if (_openingNotification) return;
    _openingNotification = true;
    setState(() {
      _locallyReadNotificationIds.add(notification.id);
    });

    try {
      if (persistToFirestore && !notification.read) {
        await FirebaseNotificationRepository.instance.markAsRead(
          uid: uid,
          notificationId: notification.id,
        );
      }
      if (!context.mounted) return;

      await NotificationRouter.openNotification(notification, context: context);
    } finally {
      _openingNotification = false;
    }
  }
}

String _notificationDisplayTitle(NotificationModel notification) {
  final title = notification.title.trim();
  final normalizedTitle = _opportunityNotificationCopy(title);
  const featuredTitles = {
    'بدأ مجلس اليوم',
    'بدا مجلس اليوم',
    'مجلس اليوم متاح الآن',
    'مجلس مميز',
    'بدأ فرصة اليوم',
    'بدا فرصة اليوم',
    'فرصة اليوم متاح الآن',
    'فرصة اليوم متاحة الآن',
    'فرصة مميزة',
  };
  if (featuredTitles.contains(title) || featuredTitles.contains(normalizedTitle)) {
    return 'فرصة مميزة بانتظار رأيك';
  }
  return normalizedTitle.replaceAll('فرصة اليوم', 'فرصة مميزة');
}

String _notificationDisplayMessage(NotificationModel notification) {
  final message = _opportunityNotificationCopy(notification.message.trim());
  final normalized = message
      .replaceAll('فرصة اليوم بدأت، شارك برأيك الآن.',
          'فرصة مميزة بانتظار رأيك. شارك رأيك الآن.')
      .replaceAll('فرصة اليوم بدأ، شارك برأيك الآن.',
          'فرصة مميزة بانتظار رأيك. شارك رأيك الآن.')
      .replaceAll('فرصة اليوم بدأت، شارك برأيك الآن',
          'فرصة مميزة بانتظار رأيك. شارك رأيك الآن')
      .replaceAll('فرصة اليوم بدأ، شارك برأيك الآن',
          'فرصة مميزة بانتظار رأيك. شارك رأيك الآن')
      .replaceAll('فرصة اليوم', 'الفرصة المميزة')
      .replaceAll('شارك برأيك الآن', 'شارك رأيك الآن');
  return normalized;
}

String _opportunityNotificationCopy(String value) {
  return value
      .replaceAll('مجالسنا', 'Forsa Pro')
      .replaceAll('فرصتي', 'Forsa Pro')
      .replaceAll('مجالسي', 'فرصي')
      .replaceAll('المجالس', 'الفرص')
      .replaceAll('مجالس', 'فرص')
      .replaceAll('مجلسك', 'فرصتك')
      .replaceAll('المجلس', 'الفرصة')
      .replaceAll('مجلس', 'فرصة')
      .replaceAll('هذا الفرصة', 'هذه الفرصة')
      .replaceAll('لهذا الفرصة', 'لهذه الفرصة')
      .replaceAll('فرصة شاركت فيه', 'فرصة شاركت فيها')
      .replaceAll('فرصة اليوم متاح الآن', 'فرصة اليوم متاحة الآن')
      .replaceAll('الفرصة المميز', 'الفرصة المميزة')
      .replaceAll('فرصة مميز', 'فرصة مميزة');
}
class _NotificationsScaffold extends StatelessWidget {
  const _NotificationsScaffold({
    required this.sizes,
    required this.onBack,
    required this.notifications,
    required this.onNotificationTap,
    required this.onMarkAllAsRead,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
  });

  final AppSizes sizes;
  final VoidCallback? onBack;
  final List<NotificationModel> notifications;
  final ValueChanged<NotificationModel> onNotificationTap;
  final VoidCallback? onMarkAllAsRead;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = 18.0 + MediaQuery.viewPaddingOf(context).bottom;
    final unreadCount = notifications.where((item) => !item.read).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            CustomGreenHeader(
              title: 'الإشعارات',
              showBack: true,
              onBack: onBack,
            ),
            Expanded(
              child: loading
                  ? _NotificationsLoadingList(
                      horizontalPadding: sizes.horizontalPadding,
                      bottomPadding: bottomPadding,
                    )
                  : errorMessage != null
                      ? _NotificationsStatus(
                          icon: Icons.wifi_off_rounded,
                          title: 'تعذر تحميل الإشعارات',
                          message: errorMessage!,
                          onRetry: onRetry,
                        )
                      : notifications.isEmpty
                          ? const _NotificationsStatus(
                              icon: Icons.notifications_none_rounded,
                              title: 'لا توجد إشعارات',
                              message: 'ستظهر هنا التنبيهات والتحديثات الجديدة.',
                            )
                          : ListView(
                              padding: EdgeInsets.fromLTRB(
                                sizes.horizontalPadding,
                                12,
                                sizes.horizontalPadding,
                                bottomPadding,
                              ),
                              children: [
                                if (onMarkAllAsRead != null && unreadCount > 0)
                                  _NotificationsActionBar(
                                    unreadCount: unreadCount,
                                    onMarkAllAsRead: onMarkAllAsRead!,
                                  ),
                                ...notifications.map(
                                  (notification) => _NotificationCard(
                                    notification: notification,
                                    onTap: () =>
                                        onNotificationTap(notification),
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

class _NotificationsLoadingList extends StatelessWidget {
  const _NotificationsLoadingList({
    required this.horizontalPadding,
    required this.bottomPadding,
  });

  final double horizontalPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12,
        horizontalPadding,
        bottomPadding,
      ),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, __) => Container(
        height: 86,
        decoration: BoxDecoration(
          color: AppColors.cardWhite.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderBeige),
        ),
      ),
    );
  }
}

class _NotificationsStatus extends StatelessWidget {
  const _NotificationsStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primaryDarkGreen),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.cardTitle),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textGray),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class _NotificationsActionBar extends StatelessWidget {
  const _NotificationsActionBar({
    required this.unreadCount,
    required this.onMarkAllAsRead,
  });

  final int unreadCount;
  final VoidCallback onMarkAllAsRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: .14),
              ),
            ),
            child: Text(
              '$unreadCount غير مقروءة',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primaryGreen,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onMarkAllAsRead,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: AppTextStyles.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('تعيين الكل كمقروء'),
          ),
        ],
      ),
    );
  }
}
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  Color get color {
    if (notification.type == 'message') {
      return AppColors.primaryDarkGreen;
    }
    if (notification.type == 'الردود' || notification.type == 'reply') {
      return AppColors.red;
    }
    if (notification.type == 'النتائج' ||
        notification.type == 'result_ready' ||
        notification.type == 'council_closed') {
      return AppColors.primaryGreen;
    }
    if (notification.type == 'النقاشات' ||
        notification.type == 'owner_activity' ||
        notification.type == 'discussion') {
      return AppColors.warningGold;
    }
    return AppColors.gold;
  }

  String get typeLabel {
    switch (notification.type) {
      case 'message':
        return 'رسالة';
      case 'reply':
      case 'الردود':
        return 'رد';
      case 'result_ready':
      case 'council_closed':
      case 'النتائج':
        return 'نتيجة';
      case 'owner_activity':
      case 'discussion':
      case 'النقاشات':
        return 'نقاش';
      case 'report':
        return 'بلاغ';
      default:
        return 'تنبيه';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.read;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.primaryGreen.withValues(alpha: .055)
              : AppColors.cardWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUnread
                ? AppColors.primaryGreen.withValues(alpha: .18)
                : AppColors.borderBeige,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F4A35),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUnread) ...[
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 16, left: 8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(notification.icon, color: color, size: 19),
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
                          _notificationDisplayTitle(notification),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 13.5,
                            fontWeight:
                                isUnread ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _NotificationTypeBadge(label: typeLabel, color: color),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _notificationDisplayMessage(notification),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: isUnread
                          ? AppColors.textDark
                          : AppColors.textDark.withValues(alpha: .74),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.time,
                    style: AppTextStyles.caption.copyWith(
                      color: isUnread
                          ? AppColors.primaryGreen
                          : AppColors.textDark.withValues(alpha: .52),
                      fontSize: 10.5,
                      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
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

class _NotificationTypeBadge extends StatelessWidget {
  const _NotificationTypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}
