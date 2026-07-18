import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/constants/app_strings.dart';
import 'core/notifications/notification_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/nickname_screen.dart';
import 'features/councils/council_details_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/results/result_details_screen.dart';
import 'navigation/app_routes.dart';
import 'navigation/main_shell.dart';

class MajalisnaApp extends StatelessWidget {
  const MajalisnaApp({
    super.key,
    this.initialRoute = AppRoutes.main,
  });

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: NotificationRouter.navigatorKey,
        title: AppStrings.appName,
        theme: AppTheme.light(),
        scrollBehavior: const _MajalisnaScrollBehavior(),
        builder: (context, child) {
          return ColoredBox(
            color: AppColors.background,
            child: _MajalisnaRefreshLayer(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [Locale('ar', 'SA'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _initialHome(),
        routes: {
          AppRoutes.onboarding: (_) => const OnboardingScreen(),
          AppRoutes.nickname: (_) => const NicknameScreen(),
          AppRoutes.main: (_) => const MainShell(),
        },
        onGenerateRoute: (settings) {
          final name = settings.name ?? '';
          final parts = name.split('/').where((part) => part.isNotEmpty).toList();
          if (parts.length == 2 && parts.first == 'council') {
            return MaterialPageRoute(
              builder: (_) => CouncilDetailsScreen(councilId: parts.last),
              settings: settings,
            );
          }

          if (parts.length == 2 && parts.first == 'result') {
            return MaterialPageRoute(
              builder: (_) => ResultDetailsScreen(councilId: parts.last),
              settings: settings,
            );
          }

          return null;
        },
      ),
    );
  }

  Widget _initialHome() {
    return switch (initialRoute) {
      AppRoutes.nickname => const NicknameScreen(),
      AppRoutes.onboarding => const OnboardingScreen(),
      _ => const MainShell(),
    };
  }
}

class _MajalisnaRefreshLayer extends StatelessWidget {
  const _MajalisnaRefreshLayer({required this.child});

  final Widget child;

  Future<void> _refresh() {
    return Future<void>.delayed(const Duration(milliseconds: 650));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primaryDarkGreen,
      backgroundColor: AppColors.cardWhite,
      strokeWidth: 2.2,
      displacement: 34,
      edgeOffset: 8,
      semanticsLabel: 'تحديث',
      notificationPredicate: (notification) {
        return notification.metrics.axis == Axis.vertical;
      },
      onRefresh: _refresh,
      child: child,
    );
  }
}

class _MajalisnaScrollBehavior extends MaterialScrollBehavior {
  const _MajalisnaScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}
