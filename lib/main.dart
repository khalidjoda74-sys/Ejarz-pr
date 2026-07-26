import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/constants/app_strings.dart';
import 'core/notifications/notification_service.dart';
import 'core/performance/navigation_performance_probe.dart';
import 'data/repositories/firebase_user_repository.dart';
import 'firebase_options.dart';
import 'navigation/app_routes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  NavigationPerformanceProbe.startIfEnabled();

  runApp(const _StartupGate());
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    return true;
  };

  ErrorWidget.builder = (details) {
    return _StartupErrorView(
      message: details.exceptionAsString(),
      onRetry: null,
    );
  };
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<String> _startup;

  static const _minimumStartupSplashTime = Duration(seconds: 3);
  static const _routeDecisionTimeout = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<String> _initialize() async {
    final routeFuture = _initializeServicesAndResolveRoute();
    await Future.wait<void>([
      routeFuture.then<void>((_) {}),
      Future<void>.delayed(_minimumStartupSplashTime),
    ]);
    return routeFuture;
  }

  Future<String> _initializeServicesAndResolveRoute() async {
    await _initializeServices();
    return _resolveInitialRoute().timeout(
      _routeDecisionTimeout,
      onTimeout: () => AppRoutes.main,
    );
  }

  Future<void> _initializeServices() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).timeout(const Duration(seconds: 2), onTimeout: () {});

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 20));

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    await _runNonCriticalStartupTask(NotificationService.instance.initialize());
    await _runNonCriticalStartupTask(AuthController.instance.initialize());
  }

  Future<String> _resolveInitialRoute() async {
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

  Future<void> _runNonCriticalStartupTask(Future<void> task) async {
    try {
      await task.timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('Startup task skipped: $error');
    }
  }

  void _retry() {
    setState(() {
      _startup = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return MajalisnaApp(initialRoute: snapshot.data ?? AppRoutes.main);
        }

        if (snapshot.hasError) {
          return _StartupShell(
            child: _StartupErrorView(
              message: 'Unable to start the app. Please try again.',
              onRetry: _retry,
            ),
          );
        }

        return const _StartupShell(child: _StartupLoadingView());
      },
    );
  }
}

class _StartupShell extends StatelessWidget {
  const _StartupShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appName,
      home: child,
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: _StartupLogo(),
        ),
      ),
    );
  }
}

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StartupLogo(),
                  const SizedBox(height: 24),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF4D5652),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupLogo extends StatelessWidget {
  const _StartupLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/forsa_pro_logo_header.png',
      width: 190,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      cacheWidth: (190 * MediaQuery.devicePixelRatioOf(context)).ceil(),
      semanticLabel: AppStrings.appName,
    );
  }
}
