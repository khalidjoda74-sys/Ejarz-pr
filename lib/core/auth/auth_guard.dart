import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/firebase_user_repository.dart';
import '../../features/auth/nickname_screen.dart';
import '../widgets/login_required_sheet.dart';
import 'auth_controller.dart';

typedef AuthenticatedAction = FutureOr<void> Function();

class AuthGuard {
  const AuthGuard._();

  static Future<bool> requireAuth(
    BuildContext context,
    AuthenticatedAction action, {
    bool allowAnonymous = false,
  }) async {
    final controller = AuthController.instance;
    final hasAllowedSession =
        allowAnonymous ? controller.hasFirebaseSession : controller.isSignedIn;

    if (hasAllowedSession) {
      if (!await _ensureIdentityIfNeeded(context, controller)) return false;
      await action();
      return true;
    }

    if (allowAnonymous) {
      final anonymousReady = await controller.signInAnonymously();
      if (anonymousReady) {
        await action();
        return true;
      }
    }

    if (!context.mounted) return false;

    controller.clearError();
    final signedIn = await showLoginRequiredSheet(context);
    if (!signedIn || !context.mounted) return false;

    if (!await _ensureIdentityIfNeeded(context, controller)) return false;

    await action();
    return true;
  }

  static Future<bool> _ensureIdentityIfNeeded(
    BuildContext context,
    AuthController controller,
  ) async {
    final uid = controller.user?.uid;
    if (!controller.isSignedIn || uid == null) return true;
    if (controller.isIdentityReady(uid)) return true;

    if (controller.isIdentityRequired(uid)) {
      return _openIdentitySetup(context, controller, uid);
    }

    final needsIdentity = await _needsIdentitySetup(context, uid);
    if (!needsIdentity) {
      controller.markIdentityReady(uid);
      return true;
    }

    if (!context.mounted) return false;
    return _openIdentitySetup(context, controller, uid);
  }

  static Future<bool> _needsIdentitySetup(
    BuildContext context,
    String uid,
  ) async {
    Timer? progressTimer;
    var progressVisible = false;

    progressTimer = Timer(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;

      progressVisible = true;
      unawaited(
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (_) => const _IdentityCheckDialog(),
        ),
      );
    });

    try {
      return await FirebaseUserRepository.instance.needsIdentitySetup(uid);
    } catch (_) {
      return true;
    } finally {
      progressTimer.cancel();
      if (progressVisible && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  static Future<bool> _openIdentitySetup(
    BuildContext context,
    AuthController controller,
    String uid,
  ) async {
    if (!context.mounted) return false;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NicknameScreen(returnToPrevious: true),
      ),
    );

    if (completed == true) controller.markIdentityReady(uid);
    return completed == true;
  }
}

class _IdentityCheckDialog extends StatelessWidget {
  const _IdentityCheckDialog();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(width: 12),
              Text(
                'جاري تجهيز حسابك...',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Color(0xFF123A2C),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
