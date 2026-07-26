import 'package:flutter/material.dart';

import '../core/auth/auth_guard.dart';
import '../core/navigation/app_focus.dart';
import '../core/navigation/app_page_route.dart';
import '../core/navigation/app_route_observer.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/glass_bottom_nav.dart';
import '../core/widgets/tab_activity_scope.dart';
import '../features/create_council/create_council_screen.dart';
import '../features/councils/council_details_screen.dart';
import '../features/councils/councils_screen.dart';
import '../features/home/home_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/results/results_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    @visibleForTesting this.debugTabBuilders,
  }) : assert(debugTabBuilders == null || debugTabBuilders.length == 5);

  final List<WidgetBuilder>? debugTabBuilders;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with PageRouteActivityMixin<MainShell> {
  int _index = 0;
  bool _navigationPending = false;
  final PageController _pageController = PageController();
  final List<bool> _visitedTabs = <bool>[true, false, false, false, false];
  final List<Widget?> _tabChildren = List<Widget?>.filled(5, null);
  String _councilsCategory = 'الكل';
  int _councilsCategoryVersion = 0;
  late final ValueNotifier<CouncilCategorySelection>
      _councilsCategorySelection = ValueNotifier<CouncilCategorySelection>(
    CouncilCategorySelection(
      category: _councilsCategory,
      version: _councilsCategoryVersion,
    ),
  );

  @override
  void dispose() {
    _pageController.dispose();
    _councilsCategorySelection.dispose();
    super.dispose();
  }

  @override
  void onPageRouteActivityChanged(bool isActive) {
    if (mounted) setState(() {});
  }

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
      AppPageRoute(builder: builder),
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
            _activateTab(index);
          },
        );
      });
      return;
    }

    _activateTab(index);
  }

  void _activateTab(int index) {
    if (!mounted || index < 0 || index >= _visitedTabs.length) return;
    dismissAppKeyboard();
    setState(() {
      _visitedTabs[index] = true;
      _index = index;
    });
    _jumpToTab(index);
  }

  void _openCouncilsCategory(String category) {
    dismissAppKeyboard();
    setState(() {
      _councilsCategory = category;
      _councilsCategoryVersion++;
      _councilsCategorySelection.value = CouncilCategorySelection(
        category: _councilsCategory,
        version: _councilsCategoryVersion,
      );
      _visitedTabs[1] = true;
      _index = 1;
    });
    _jumpToTab(1);
  }

  void _jumpToTab(int index) {
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
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
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: _index != 2,
      body: PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || _index == 0) return;
          _activateTab(0);
        },
        child: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          allowImplicitScrolling: false,
          itemCount: _visitedTabs.length,
          itemBuilder: (context, index) => _buildTab(
            index,
            routeIsCurrent: isPageRouteActive,
          ),
        ),
      ),
      bottomNavigationBar: _index == 2
          ? null
          : GlassBottomNav(
              currentIndex: _index,
              onTap: _selectTab,
            ),
    );
  }

  Widget _buildTab(int index, {required bool routeIsCurrent}) {
    if (!_visitedTabs[index]) {
      return const SizedBox.shrink();
    }

    final child = _tabChildren[index] ??= _createTab(index);

    final isSelected = _index == index;
    final isActive = routeIsCurrent && isSelected;
    return TabActivityScope(
      isActive: isActive,
      isSelected: isSelected,
      child: ExcludeFocus(
        excluding: !isActive,
        child: _KeepAliveTab(
          child: TickerMode(
            enabled: isActive,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _createTab(int index) {
    final debugBuilders = widget.debugTabBuilders;
    if (debugBuilders != null) return debugBuilders[index](context);

    return switch (index) {
      0 => HomeScreen(
          key: const PageStorageKey('home_tab'),
          onOpenCouncil: _openCouncil,
          onOpenCategory: _openCouncilsCategory,
          onOpenMessages: _openMessages,
          onOpenNotifications: _openNotifications,
        ),
      1 => CouncilsScreen(
          key: const PageStorageKey('councils_tab'),
          categorySelection: _councilsCategorySelection,
          onOpenCouncil: _openCouncil,
        ),
      2 => CreateCouncilScreen(
          key: const PageStorageKey('create_tab'),
          onBack: () => _activateTab(0),
          onCreated: _openCouncil,
        ),
      3 => ResultsScreen(
          key: const PageStorageKey('results_tab'),
          onOpenCouncil: _openCouncil,
        ),
      _ => ProfileScreen(
          key: const PageStorageKey('profile_tab'),
          onSignedOut: () => _activateTab(0),
        ),
    };
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
