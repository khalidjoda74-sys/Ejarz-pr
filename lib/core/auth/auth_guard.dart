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

    bool needsIdentity;
    try {
      needsIdentity =
          await FirebaseUserRepository.instance.needsIdentitySetup(uid);
    } catch (_) {
      needsIdentity = true;
    }

    if (!needsIdentity) {
      controller.markIdentityReady(uid);
      return true;
    }
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
