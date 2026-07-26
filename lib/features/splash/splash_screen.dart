import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/auth/auth_controller.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../navigation/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _didNavigate = false;

  static const _routeDecisionTimeout = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openNextScreen());
    });
  }

  Future<void> _openNextScreen() async {
    if (_didNavigate) return;

    final route = await _nextRoute().timeout(
      _routeDecisionTimeout,
      onTimeout: () => AppRoutes.main,
    );
    if (!mounted || _didNavigate) return;

    _didNavigate = true;
    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<String> _nextRoute() async {
    final auth = AuthController.instance;
    final uid = auth.user?.uid;

    if (auth.isSignedIn && uid != null) {
      if (auth.isIdentityReady(uid)) return AppRoutes.main;
      try {
        final needsIdentity =
            await FirebaseUserRepository.instance.needsIdentitySetup(uid);
        if (needsIdentity) return AppRoutes.nickname;
        auth.markIdentityReady(uid);
      } catch (_) {
        return AppRoutes.main;
      }
    }

    return AppRoutes.main;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(),
    );
  }
}
