import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/constants/app_strings.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../navigation/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  final repo = CouncilRepository.instance;
  late final TextEditingController nameController;
  late final FocusNode _nameFocusNode;
  late String _lastSyncedName;
  bool notifications = true;
  bool _loadingNotifications = true;
  bool _updatingNotifications = false;
  bool _savingName = false;
  bool _deletingAccount = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: repo.user.name);
    _nameFocusNode = FocusNode();
    _lastSyncedName = repo.user.name.trim();
    repo.addListener(_syncNameFromRepository);
    unawaited(_loadNotificationPreference());
  }

  @override
  void dispose() {
    repo.removeListener(_syncNameFromRepository);
    _nameFocusNode.dispose();
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final isNicknameLocked = repo.user.nicknameLocked;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumBackground(
        showPattern: false,
        child: Column(
          children: [
            CustomGreenHeader(
              title: 'الإعدادات',
              showBack: true,
              onBack: widget.onBack,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  sizes.horizontalPadding,
                  12,
                  sizes.horizontalPadding,
                  90,
                ),
                children: [
                  _SettingsCard(
                    children: [
                      Text(
                        'تغيير الاسم المستعار',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isNicknameLocked
                            ? 'تم تثبيت الاسم ولا يمكن تغييره مرة أخرى.'
                            : 'يمكنك تغيير الاسم مرة واحدة فقط. بعد الحفظ سيتم تثبيته نهائيًا.',
                        style: AppTextStyles.caption.copyWith(fontSize: 10.8),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: nameController,
                          focusNode: _nameFocusNode,
                          enabled: !_savingName && !isNicknameLocked,
                          textAlign: TextAlign.right,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          style: AppTextStyles.body.copyWith(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'الاسم المستعار',
                            hintStyle:
                                AppTextStyles.caption.copyWith(fontSize: 11),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.borderBeige,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.borderBeige,
                              ),
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
                      ),
                      if (_nameError != null) ...[
                        const SizedBox(height: 8),
                        _InlineError(message: _nameError!),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _savingName || isNicknameLocked
                              ? null
                              : _saveNickname,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDarkGreen,
                            foregroundColor: AppColors.cardWhite,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle:
                                AppTextStyles.button.copyWith(fontSize: 13),
                          ),
                          child: _savingName
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.cardWhite,
                                  ),
                                )
                              : Text(
                                  isNicknameLocked
                                      ? 'الاسم مثبت'
                                      : 'حفظ التغيير',
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    children: [
                      _SwitchRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'الإشعارات',
                        subtitle: 'تنبيهات الفرص والردود',
                        value: notifications,
                        onChanged: _loadingNotifications || _updatingNotifications
                            ? null
                            : _setNotifications,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    children: [
                      _SimpleRow(
                        icon: Icons.delete_outline_rounded,
                        label: 'حذف الحساب',
                        danger: true,
                        onTap: _deletingAccount ? null : _confirmDeleteAccount,
                      ),
                      const _ThinDivider(),
                      _SimpleRow(
                        icon: Icons.info_outline_rounded,
                        label: 'حول التطبيق',
                        onTap: _showAboutApp,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadNotificationPreference() async {
    final uid = AuthController.instance.user?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingNotifications = false);
      return;
    }
    try {
      final enabled = await FirebaseUserRepository.instance
          .notificationPreferenceEnabled(uid);
      if (mounted) setState(() => notifications = enabled);
    } catch (_) {
      // Keep the safe default when the preference cannot be loaded.
    } finally {
      if (mounted) setState(() => _loadingNotifications = false);
    }
  }

  Future<void> _setNotifications(bool value) async {
    final uid = AuthController.instance.user?.uid;
    if (uid == null || _updatingNotifications) return;
    final previous = notifications;
    setState(() {
      notifications = value;
      _updatingNotifications = true;
    });
    try {
      await FirebaseUserRepository.instance.setNotificationPreference(
        uid: uid,
        enabled: value,
      );
      if (value) {
        await NotificationService.instance.enableForSignedInUser(uid);
      } else {
        await NotificationService.instance.disableForSignedOutUser(uid);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => notifications = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث إعداد الإشعارات.')),
      );
    } finally {
      if (mounted) setState(() => _updatingNotifications = false);
    }
  }
  Future<void> _saveNickname() async {
    if (repo.user.nicknameLocked) {
      setState(() {
        _nameError = 'تم تثبيت الاسم ولا يمكن تغييره مرة أخرى.';
      });
      return;
    }

    final validation =
        FirebaseUserRepository.validateNickname(nameController.text);
    if (validation != null) {
      setState(() => _nameError = validation);
      return;
    }

    setState(() {
      _savingName = true;
      _nameError = null;
    });

    try {
      final changed =
          await repo.updateNickname(nameController.text, repo.user.avatarEmoji);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed ? 'تم حفظ الاسم وتثبيته نهائيًا' : 'لم يتم تغيير الاسم',
          ),
        ),
      );
    } on NicknameTakenException catch (error) {
      if (!mounted) return;
      setState(() => _nameError = error.message);
    } on NicknameLockedException catch (error) {
      if (!mounted) return;
      setState(() => _nameError = error.message);
    } on NicknameValidationException catch (error) {
      if (!mounted) return;
      setState(() => _nameError = error.message);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() => _nameError = _nicknameFirebaseMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nameError = 'تعذر حفظ الاسم. تحقق من الاتصال وحاول مرة أخرى.';
      });
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  void _syncNameFromRepository() {
    final nextName = repo.user.name.trim();
    if (nextName.isEmpty || nextName == _lastSyncedName) return;

    final currentName = nameController.text.trim();
    final canReplaceControllerValue = !_nameFocusNode.hasFocus ||
        currentName.isEmpty ||
        currentName == _lastSyncedName;

    _lastSyncedName = nextName;
    if (!canReplaceControllerValue || nameController.text == nextName) return;

    nameController.value = TextEditingValue(
      text: nextName,
      selection: TextSelection.collapsed(offset: nextName.length),
    );
  }

  String _nicknameFirebaseMessage(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'تعذر حفظ الاسم بسبب صلاحيات قاعدة البيانات. حاول مرة أخرى لاحقًا.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
    }
    return 'تعذر حفظ الاسم. حاول مرة أخرى.';
  }
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .34),
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await AuthController.instance.prepareAccountDeletion();
      await AccountRepository.instance.deleteMyAccount();
      await AuthController.instance.finishAccountDeletion();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الحساب')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.main,
        (_) => false,
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_deleteAccountMessage(error))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الحساب. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  String _deleteAccountMessage(FirebaseException error) {
    if (error.code == 'unauthenticated') {
      return 'سجّل دخولك مرة أخرى لحذف الحساب.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
    }
    if (error.code == 'apple-token-revocation-failed' ||
        error.code == 'canceled' ||
        error.code == 'authorization-error') {
      return 'يلزم تأكيد حساب Apple لإكمال حذف الحساب.';
    }
    return 'تعذر حذف الحساب. حاول مرة أخرى.';
  }

  void _showAboutApp() {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.textDark.withValues(alpha: .34),
      builder: (_) => const _AboutAppDialog(),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderBeige),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F4A35),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryDarkGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: .84,
            child: Switch.adaptive(
              value: value,
              activeThumbColor: AppColors.primaryDarkGreen,
              activeTrackColor: AppColors.primaryGreen.withValues(alpha: .30),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.primaryDarkGreen;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: danger ? AppColors.red : AppColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: danger ? AppColors.red : AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.borderBeige,
    );
  }
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: .16),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: .18),
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'حذف الحساب؟',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'سيتم حذف ملفك واسمك المحجوز وتسجيل خروجك من التطبيق. هذا الإجراء لا يمكن التراجع عنه.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DialogActionButton(
                        label: 'حذف الحساب',
                        icon: Icons.delete_outline_rounded,
                        destructive: true,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _DialogActionButton(
                        label: 'إلغاء',
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutAppDialog extends StatelessWidget {
  const _AboutAppDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderBeige),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: .14),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppColors.headerGradient,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: AppColors.cardWhite,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.appName,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppStrings.tagline,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _AboutLine(
                  icon: Icons.how_to_vote_outlined,
                  title: 'نقاشات يومية',
                  text: 'فرص قصيرة برأي سريع وقراءة آراء واضحة.',
                ),
                const _AboutLine(
                  icon: Icons.badge_outlined,
                  title: 'هوية مستعارة',
                  text: 'تشارك باسم داخل الفرص مع الحفاظ على بساطة التجربة.',
                ),
                const _AboutLine(
                  icon: Icons.campaign_outlined,
                  title: 'رعاية واضحة',
                  text: 'أي إعلان راعٍ يظهر بشكل معلن وغير مخادع.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: _DialogActionButton(
                    label: 'تم',
                    icon: Icons.check_rounded,
                    onTap: () => Navigator.of(context).pop(),
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

class _AboutLine extends StatelessWidget {
  const _AboutLine({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDarkGreen, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: AppTextStyles.caption.copyWith(fontSize: 10.8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? AppColors.cardWhite : AppColors.textDark;
    final background = destructive ? AppColors.red : AppColors.background;
    final borderColor = destructive
        ? AppColors.red.withValues(alpha: .72)
        : AppColors.borderBeige;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 17),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(
                    color: foreground,
                    fontSize: 12.4,
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.red.withValues(alpha: .18)),
      ),
      child: Text(
        message,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.red,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
