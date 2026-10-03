import 'package:flutter/material.dart';

import '../core/demo_config.dart';
import '../core/theme.dart';
import 'illustrations.dart';

class WorkspaceRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) _routes[index] = newRoute;
  }

  /// Respect a form's PopScope, including save-in-progress/unsaved changes.
  Future<bool> returnToRoot() async {
    while (_routes.length > 1) {
      final before = _routes.last;
      await navigator?.maybePop();
      if (_routes.isNotEmpty && identical(_routes.last, before)) return false;
    }
    return true;
  }
}

/// Inherited rather than a screen-width check: nested detail routes only hide
/// their mobile navigation when the desktop navigation is actually present.
class WorkspaceNavigationScope extends InheritedWidget {
  const WorkspaceNavigationScope({super.key, required super.child});

  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceNavigationScope>() !=
      null;

  @override
  bool updateShouldNotify(WorkspaceNavigationScope oldWidget) => false;
}

class AppWorkspace extends StatelessWidget {
  static const breakpoint = 1100.0;
  final Widget child;
  final bool enabled;
  final int selectedIndex;
  final String userName;
  final int unreadNotifications;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onPricing;
  final VoidCallback onSupport;
  final VoidCallback onLegal;
  final VoidCallback onNotifications;
  final VoidCallback onSettings;

  const AppWorkspace({
    super.key,
    required this.child,
    required this.enabled,
    required this.selectedIndex,
    required this.userName,
    required this.unreadNotifications,
    required this.onSelect,
    required this.onCreate,
    required this.onPricing,
    required this.onSupport,
    required this.onLegal,
    required this.onNotifications,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (!enabled || constraints.maxWidth < breakpoint) return child;
          return WorkspaceNavigationScope(
            child: Row(
              // Paint navigation after the Navigator so its BlockSemantics
              // cannot hide the persistent sidebar from screen readers.
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: child),
                SizedBox(
                  key: const ValueKey('desktop-navigation'),
                  width: 248,
                  child: Material(
                    color: context.ejarzTheme.surface,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          end: BorderSide(color: context.ejarzTheme.border),
                        ),
                      ),
                      child: SafeArea(
                        child: ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            const Center(child: BrandIdentity(height: 48)),
                            const SizedBox(height: 10),
                            Text('مساحة إدارة العقود والعقارات',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.ejarzTheme.muted)),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              key: const ValueKey('desktop-create-contract'),
                              onPressed: onCreate,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('إنشاء عقد جديد'),
                            ),
                            const SizedBox(height: 20),
                            _item(context, 'الرئيسية', Icons.dashboard_outlined,
                                () => onSelect(0),
                                selected: selectedIndex == 0),
                            _item(context, 'عقودي', Icons.description_outlined,
                                () => onSelect(1),
                                selected: selectedIndex == 1),
                            _item(context, 'عقاراتي', Icons.apartment_outlined,
                                () => onSelect(2),
                                selected: selectedIndex == 2),
                            _item(context, 'حسابي',
                                Icons.person_outline_rounded, () => onSelect(3),
                                selected: selectedIndex == 3),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(),
                            ),
                            _item(context, 'أسعار العقود',
                                Icons.receipt_long_outlined, onPricing),
                            _item(
                                context,
                                'الإشعارات',
                                Icons.notifications_none_rounded,
                                onNotifications,
                                badge: unreadNotifications),
                            _item(context, 'الدعم الفني',
                                Icons.support_agent_outlined, onSupport),
                            _item(context, 'الشروط والسياسات',
                                Icons.policy_outlined, onLegal),
                            _item(context, 'الإعدادات', Icons.settings_outlined,
                                onSettings),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.ejarzTheme.background,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 5),
                                  Text(
                                      kEjarzDemoMode
                                          ? 'نسخة تجريبية • دون دفع حقيقي'
                                          : 'أهلاً بك في عقدك',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.ejarzTheme.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _item(
      BuildContext context, String title, IconData icon, VoidCallback action,
      {bool selected = false, int badge = 0}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, size: 22),
        title: Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        trailing: badge > 0
            ? Badge(label: Text(badge > 99 ? '99+' : '$badge'))
            : null,
        onTap: action,
      ),
    );
  }
}

/// Natural-height cards; no fixed aspect ratio that can clip Arabic/large text.
class AdaptiveCardGrid extends StatelessWidget {
  final List<Widget> children;
  final double minCardWidth;
  const AdaptiveCardGrid(
      {super.key, required this.children, this.minCardWidth = 390});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= minCardWidth * 2 + 14 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final child in children) SizedBox(width: width, child: child)
            ],
          );
        },
      );
}
