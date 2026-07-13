import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/firebase_user_repository.dart';
import '../../navigation/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: .92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _navTimer = Timer(const Duration(milliseconds: 2000), _openNextScreen);
  }

  Future<void> _openNextScreen() async {
    final route = await _nextRoute();
    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<String> _nextRoute() async {
    final auth = AuthController.instance;
    final uid = auth.user?.uid;

    if (auth.isSignedIn && uid != null) {
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
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = (screenWidth * .46).clamp(165.0, 220.0).toDouble();

    return Scaffold(
      backgroundColor: AppColors.cardWhite,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Image.asset(
                'assets/images/forsa_pro_logo_header.png',
                width: logoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: AppStrings.appName,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
