import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../navigation/app_focus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

Future<bool> showLoginRequiredSheet(BuildContext context) async {
  dismissAppKeyboard();
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.textDark.withValues(alpha: .28),
    builder: (_) => const LoginRequiredSheet(),
  );

  return result ?? false;
}

class LoginRequiredSheet extends StatefulWidget {
  const LoginRequiredSheet({super.key});

  @override
  State<LoginRequiredSheet> createState() => _LoginRequiredSheetState();
}

class _LoginRequiredSheetState extends State<LoginRequiredSheet> {
  final AuthController controller = AuthController.instance;
  String? loadingProvider;

  @override
  void initState() {
    super.initState();
    controller.clearError();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderBeige),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDarkGreen.withValues(alpha: .12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
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
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: AppColors.headerGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.lock_open_rounded,
                            color: AppColors.cardWhite,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'سجّل دخولك',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'سجّل دخولك لإضافة رأيك السريع والمشاركة في النقاشات.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textGray,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      _ErrorBox(message: controller.errorMessage!),
                    ],
                    const SizedBox(height: 14),
                    _ProviderButton(
                      label: 'المتابعة عبر Google',
                      icon: Icons.g_mobiledata_rounded,
                      loading: loadingProvider == 'google',
                      onTap: () => _signIn('google'),
                    ),
                    FutureBuilder<bool>(
                      future: controller.canUseAppleSignIn(),
                      builder: (context, snapshot) {
                        final showApple = snapshot.data ?? false;
                        if (!showApple) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _ProviderButton(
                            label: 'المتابعة عبر Apple',
                            icon: Icons.apple_rounded,
                            loading: loadingProvider == 'apple',
                            onTap: () => _signIn('apple'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textGray,
                        minimumSize: const Size.fromHeight(36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: AppTextStyles.button.copyWith(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                      child: const Text('لاحقًا'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(String provider) async {
    if (controller.isBusy) return;

    setState(() => loadingProvider = provider);
    final ok = provider == 'google'
        ? await controller.signInWithGoogle()
        : await controller.signInWithApple();

    if (!mounted) return;

    setState(() => loadingProvider = null);
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderBeige),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: loading
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryDarkGreen,
                      )
                    : Icon(
                        icon,
                        size: 22,
                        color: AppColors.primaryDarkGreen,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.textDark,
                    fontSize: 13,
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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: .18)),
      ),
      child: Text(
        message,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.red,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
