import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin/admin_dashboard.dart';
import 'core/app_controller.dart';
import 'core/demo_config.dart';
import 'core/firebase_bootstrap.dart';
import 'core/notification_service.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/auth.dart';
import 'screens/contracts.dart';
import 'screens/create_contract.dart';
import 'screens/home.dart';
import 'screens/wallet_profile.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isAdminRoute = kIsWeb && Uri.base.path.startsWith('/admin');
  if (kEjarzLocalDemoMode && !isAdminRoute) {
    debugPrint(
        'Aqood Pro local demo mode is enabled; Firebase startup is skipped.');
  } else if (kIsWeb) {
    unawaited(
      FirebaseBootstrap.scheduleInitialization(
        options: DefaultFirebaseOptions.currentPlatform,
        delay: const Duration(milliseconds: 600),
        timeout: const Duration(seconds: 12),
      ).catchError((Object error) {
        debugPrint('Firebase initialization did not complete: $error');
      }),
    );
  } else {
    try {
      await FirebaseBootstrap.ensureInitialized(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await AppNotificationService.initialize();
    } catch (error) {
      debugPrint('Firebase initialization did not complete: $error');
    }
  }
  if (isAdminRoute) {
    runApp(const AdminDashboardApp());
    return;
  }
  runApp(const AqoodProApp());
}

class AqoodProApp extends StatefulWidget {
  const AqoodProApp({super.key});

  @override
  State<AqoodProApp> createState() => _AqoodProAppState();
}

class _NoOverscrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollBehavior();

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
    final platform = getPlatform(context);
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }
}

class _AqoodProAppState extends State<AqoodProApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    AppNotificationService.onNotificationTap = _handleNotificationTap;
  }

  @override
  void dispose() {
    AppNotificationService.onNotificationTap = null;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    final context = AppNotificationService.navigatorKey.currentContext;
    final navigator = AppNotificationService.navigatorKey.currentState;
    if (context == null || navigator == null) return;
    final actionType = data['actionType']?.toString();
    final contractId = data['contractId']?.toString() ??
        (data['actionPayload'] is Map
            ? (data['actionPayload'] as Map)['contractId']?.toString()
            : null);
    if (actionType == 'supportTicket') {
      final ticketId = data['ticketId']?.toString() ??
          (data['actionPayload'] is Map
              ? (data['actionPayload'] as Map)['ticketId']?.toString()
              : null);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => SupportScreen(initialTicketId: ticketId),
        ),
      );
      return;
    }
    if (actionType != 'contractDetails' && contractId == null) return;
    if (contractId == null || contractId.isEmpty) return;
    final contract = await _controller.contractById(contractId);
    if (contract == null || !context.mounted) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ContractDetailsScreen(contract: contract),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: AppNotificationService.navigatorKey,
            title: 'عقود برو',
            locale: const Locale('ar'),
            supportedLocales: const <Locale>[
              Locale('ar'),
              Locale('en'),
            ],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            scrollBehavior: const _NoOverscrollBehavior(),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _controller.darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              final app = Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              );
              return app;
            },
            home: const _AppGate(),
          );
        },
      ),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (!controller.splashCompleted) {
      return const SplashScreen();
    }
    if (controller.maintenanceBlocksApp) {
      return const _MaintenanceScreen();
    }
    if (!controller.onboardingCompleted) {
      return const OnboardingScreen();
    }
    if (controller.accountBlocked) {
      return const _BlockedAccountScreen();
    }
    if (!controller.loggedIn) {
      return const LoginScreen();
    }
    return const _MainShell();
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 440,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 78,
                height: 78,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.engineering_outlined,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'التطبيق تحت الصيانة',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'نعمل الآن على تحديث الخدمة وتحسين التجربة. سيعود التطبيق للعمل تلقائيًا عند انتهاء الصيانة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  height: 1.55,
                ),
              ),
              if (controller.loggedIn) ...<Widget>[
                const SizedBox(height: 18),
                SecondaryButton(
                  label: 'تسجيل الخروج',
                  icon: Icons.logout_rounded,
                  onPressed: () => AppScope.of(context, listen: false).logout(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedAccountScreen extends StatelessWidget {
  const _BlockedAccountScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 440,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primary,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'الحساب موقوف مؤقتًا',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'لا يمكن استخدام التطبيق بهذا الحساب حاليًا. تواصل مع الدعم إذا كنت تعتقد أن ذلك حدث بالخطأ.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.ejarzTheme.muted,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 18),
              SecondaryButton(
                label: 'تسجيل الخروج',
                icon: Icons.logout_rounded,
                onPressed: () => AppScope.of(context, listen: false).logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell();

  void _openCreateContract(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateContractScreen(),
      ),
    );
  }

  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return PopScope(
      canPop: controller.mainNavigationIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && controller.mainNavigationIndex != 0) {
          controller.setNavigationIndex(0);
        }
      },
      child: Scaffold(
        body: Builder(
          builder: (shellContext) {
            final pages = <Widget>[
              HomeScreen(
                onMenu: () {},
                onNotifications: () => _openNotifications(shellContext),
                onCreate: () => _openCreateContract(shellContext),
                onContracts: () => controller.setNavigationIndex(1),
                onProperties: () => controller.setNavigationIndex(2),
              ),
              ContractsScreen(
                onMenu: () {},
                onNotifications: () => _openNotifications(shellContext),
                onCreate: () => _openCreateContract(shellContext),
              ),
              PropertiesScreen(
                onMenu: () {},
                onNotifications: () => _openNotifications(shellContext),
              ),
              ProfileScreen(
                onMenu: () {},
                onNotifications: () => _openNotifications(shellContext),
              ),
            ];

            return IndexedStack(
              index: controller.mainNavigationIndex,
              children: pages,
            );
          },
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (controller.offlineMode ||
                controller.hasPendingSync ||
                controller.syncingPendingChanges)
              _OfflineSyncBanner(controller: controller),
            _EjarzBottomNavigation(
              currentIndex: controller.mainNavigationIndex,
              onSelect: controller.setNavigationIndex,
              onCreate: () => _openCreateContract(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineSyncBanner extends StatelessWidget {
  final AppController controller;

  const _OfflineSyncBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pending = controller.pendingSyncCount;
    final offline = controller.offlineMode;
    final color = offline ? AppColors.orange : AppColors.primary;
    final text = offline
        ? pending > 0
            ? 'غير متصل - $pending عنصر بانتظار المزامنة'
            : 'غير متصل - البيانات من آخر تحديث'
        : controller.syncingPendingChanges
            ? 'جاري مزامنة التغييرات...'
            : '$pending عنصر جاهز للمزامنة';
    return Material(
      color: color.withValues(alpha: 0.10),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: Row(
            children: <Widget>[
              Icon(
                offline ? Icons.cloud_off_rounded : Icons.cloud_sync_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ejarzTheme.text,
                    fontSize: context.sp(11.5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!offline && pending > 0)
                TextButton(
                  onPressed: controller.syncingPendingChanges
                      ? null
                      : controller.syncPendingChangesNow,
                  child: const Text('مزامنة'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EjarzBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  const _EjarzBottomNavigation({
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.ejarzTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: SizedBox(
          height: 50,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: <Widget>[
                _BottomNavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'الرئيسية',
                  selected: currentIndex == 0,
                  onTap: () => onSelect(0),
                ),
                _BottomNavItem(
                  icon: Icons.description_outlined,
                  selectedIcon: Icons.description_rounded,
                  label: 'عقودي',
                  selected: currentIndex == 1,
                  onTap: () => onSelect(1),
                ),
                _BottomCreateItem(onTap: onCreate),
                _BottomNavItem(
                  icon: Icons.apartment_outlined,
                  selectedIcon: Icons.apartment_rounded,
                  label: 'عقاراتي',
                  selected: currentIndex == 2,
                  onTap: () => onSelect(2),
                ),
                _BottomNavItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'حسابي',
                  selected: currentIndex == 3,
                  onTap: () => onSelect(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.ejarzTheme.muted;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(selected ? selectedIcon : icon, size: 24, color: color),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: context.sp(11.6),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                    fontFamily: AppTheme.fontFamily,
                    fontFamilyFallback: AppTheme.fontFallback,
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

class _BottomCreateItem extends StatelessWidget {
  final VoidCallback onTap;

  const _BottomCreateItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  top: -18,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.09),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: <Color>[
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.ejarzTheme.surface,
                              width: 3,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.32),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
}
