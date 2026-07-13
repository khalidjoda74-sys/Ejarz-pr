import 'package:flutter/material.dart';

import '../core/auth/auth_guard.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/glass_bottom_nav.dart';
import '../features/create_council/create_council_screen.dart';
import '../features/councils/council_details_screen.dart';
import '../features/councils/councils_screen.dart';
import '../features/home/home_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/results/results_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _navigationPending = false;
  String _councilsCategory = 'الكل';
  int _councilsCategoryVersion = 0;

  Future<void> _runNavigation(Future<void> Function() action) async {
    if (_navigationPending || !mounted) return;
    _navigationPending = true;
    try {
      await action();
    } finally {
      _navigationPending = false;
    }
  }

  Future<void> _pushShellRoute(WidgetBuilder builder) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: builder),
    );
  }

  Future<void> _openCouncil(String id) {
    return _runNavigation(
      () => _pushShellRoute(
        (_) => CouncilDetailsScreen(councilId: id),
      ),
    );
  }

  Future<void> _selectTab(int index) async {
    if (index < 0 || index > 4 || index == _index) return;

    if (index == 2 || index == 3) {
      await _runNavigation(() async {
        await AuthGuard.requireAuth(
          context,
          () {
            if (!mounted) return;
            setState(() => _index = index);
          },
        );
      });
      return;
    }

    setState(() => _index = index);
  }

  void _openCouncilsCategory(String category) {
    setState(() {
      _councilsCategory = category;
      _councilsCategoryVersion++;
      _index = 1;
    });
  }

  Future<void> _openNotifications() {
    return _runNavigation(() async {
      await AuthGuard.requireAuth(
        context,
        () async {
          if (!mounted) return;
          await _pushShellRoute(
            (routeContext) => NotificationsScreen(
              onBack: () => Navigator.of(routeContext).maybePop(),
            ),
          );
        },
      );
    });
  }

  Future<void> _openMessages() {
    return _runNavigation(() async {
      await AuthGuard.requireAuth(
        context,
        () async {
          if (!mounted) return;
          await _pushShellRoute(
            (routeContext) => MessagesScreen(
              onBack: () => Navigator.of(routeContext).maybePop(),
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        key: const PageStorageKey('home_tab'),
        onOpenCouncil: _openCouncil,
        onOpenCategory: _openCouncilsCategory,
        onOpenMessages: _openMessages,
        onOpenNotifications: _openNotifications,
      ),
      CouncilsScreen(
        key: const PageStorageKey('councils_tab'),
        initialCategory: _councilsCategory,
        initialCategoryVersion: _councilsCategoryVersion,
        onOpenCouncil: _openCouncil,
      ),
      CreateCouncilScreen(
        key: const PageStorageKey('create_tab'),
        onCreated: _openCouncil,
      ),
      ResultsScreen(
        key: const PageStorageKey('results_tab'),
        onOpenCouncil: _openCouncil,
      ),
      ProfileScreen(
        key: const PageStorageKey('profile_tab'),
        onSignedOut: () => setState(() => _index = 0),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || _index == 0) return;
          setState(() => _index = 0);
        },
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: GlassBottomNav(
        currentIndex: _index,
        onTap: _selectTab,
      ),
    );
  }
}
