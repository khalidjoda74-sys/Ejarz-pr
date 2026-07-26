import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/avatar_badge.dart';
import '../../core/widgets/premium_background.dart';
import '../../data/repositories/council_repository.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../navigation/app_routes.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key, this.returnToPrevious = false});

  final bool returnToPrevious;

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _controller = TextEditingController();
  final repo = CouncilRepository.instance;
  static const avatars = businessAvatarOptions;

  String? selectedAvatar;
  String? _errorMessage;
  String? _avatarErrorMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAccess());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _guardAccess() async {
    if (!mounted) return;

    final auth = AuthController.instance;
    final uid = auth.user?.uid;
    if (!auth.isSignedIn || uid == null) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.main,
        (_) => false,
      );
      return;
    }

    if (auth.isIdentityReady(uid)) {
      _finish(completed: true);
      return;
    }

    try {
      final needsIdentity =
          await FirebaseUserRepository.instance.needsIdentitySetup(uid);
      if (!needsIdentity && mounted) {
        auth.markIdentityReady(uid);
        _finish(completed: true);
      }
    } catch (_) {
      // Keep the user on the screen; saving will show a clear retry message.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AppSizes.of(context);
    final logoWidth =
        (MediaQuery.sizeOf(context).width * .28).clamp(96.0, 125.0).toDouble();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: PremiumBackground(
          showPattern: false,
          child: SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                sizes.horizontalPadding,
                18,
                sizes.horizontalPadding,
                22,
              ),
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/forsa_pro_logo_header.png',
                    width: logoWidth,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'فرصة برو',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'اختر هويتك في فرصة برو',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headline.copyWith(
                    color: AppColors.primaryDarkGreen,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'سيظهر هذا الاسم مع مشاركاتك داخل الفرص.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textGray,
                    fontSize: 12.8,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderBeige),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x160F4A35),
                          blurRadius: 14,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: selectedAvatar == null
                        ? Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.textGray.withValues(alpha: .48),
                            size: 24,
                          )
                        : AvatarBadge(label: selectedAvatar!, size: 44),
                  ),
                ),
                const SizedBox(height: 12),
                _IdentityCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _controller,
                        enabled: !_saving,
                        textAlign: TextAlign.right,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(24),
                        ],
                        onChanged: (_) {
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                        onSubmitted: (_) => _submit(),
                        style: AppTextStyles.body.copyWith(fontSize: 13.5),
                        decoration: _inputDecoration(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 9),
                        _ErrorText(message: _errorMessage!),
                      ],
                      const SizedBox(height: 13),
                      Text(
                        'اختر صورة رمزية',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: avatars.map((avatar) {
                          final selected = avatar == selectedAvatar;
                          return GestureDetector(
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      selectedAvatar = avatar;
                                      _avatarErrorMessage = null;
                                    }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 170),
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primaryDarkGreen
                                    : AppColors.background.withValues(
                                        alpha: .58,
                                      ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.gold
                                      : AppColors.borderBeige,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: AvatarBadge(label: avatar, size: 34),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_avatarErrorMessage != null) ...[
                        const SizedBox(height: 9),
                        _ErrorText(message: _avatarErrorMessage!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: .18),
                    ),
                  ),
                  child: Text(
                    'اختر الرمز الأقرب لطبيعة حضورك: مستثمر، شريك، صاحب منشأة، تشغيل، نمو.',
                    style: AppTextStyles.caption.copyWith(
                      height: 1.6,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.cardWhite,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_saving ? 'جارٍ الحفظ' : 'حفظ الهوية'),
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
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      labelText: 'الاسم المستعار',
      hintText: 'مثال: صاحب رأي',
      labelStyle: AppTextStyles.caption.copyWith(fontSize: 12),
      hintStyle: AppTextStyles.caption.copyWith(fontSize: 11),
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

  Future<void> _submit() async {
    if (_saving) return;

    final validation =
        FirebaseUserRepository.validateNickname(_controller.text);
    if (validation != null) {
      setState(() {
        _errorMessage = validation;
        _avatarErrorMessage = null;
      });
      return;
    }

    final avatar = selectedAvatar;
    if (avatar == null) {
      setState(() {
        _errorMessage = null;
        _avatarErrorMessage = 'اختر صورة رمزية قبل حفظ الهوية.';
      });
      return;
    }

    final auth = AuthController.instance;
    if (!auth.isSignedIn || auth.user == null) {
      _finish(completed: false);
      return;
    }

    var completed = false;
    setState(() {
      _saving = true;
      _errorMessage = null;
      _avatarErrorMessage = null;
    });

    try {
      await repo.updateNickname(_controller.text, avatar);
      if (!mounted) return;

      completed = true;
      auth.markIdentityReady(auth.user?.uid);
      _finish(completed: true);
    } on NicknameTakenException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on NicknameLockedException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on NicknameValidationException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _identityFirebaseMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر حفظ الهوية. تحقق من الاتصال وحاول مرة أخرى.';
      });
    } finally {
      if (!completed && mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _identityFirebaseMessage(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'تعذر حفظ الهوية بسبب صلاحيات قاعدة البيانات. حاول مرة أخرى بعد تحديث التطبيق.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
    }
    return 'تعذر حفظ الهوية. حاول مرة أخرى.';
  }

  void _finish({required bool completed}) {
    if (widget.returnToPrevious) {
      Navigator.of(context).pop(completed);
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.main, (_) => false);
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

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
