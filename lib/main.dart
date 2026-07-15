import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/constants/app_strings.dart';
import 'core/notifications/notification_service.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();

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
  late Future<void> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<void> _initialize() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).timeout(const Duration(seconds: 2), onTimeout: () {});

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 20));

    await _runNonCriticalStartupTask(NotificationService.instance.initialize());
    await _runNonCriticalStartupTask(AuthController.instance.initialize());
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
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const MajalisnaApp();
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
      semanticLabel: AppStrings.appName,
    );
  }
}
