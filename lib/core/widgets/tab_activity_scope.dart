import 'package:flutter/widgets.dart';

/// Exposes whether a tab is currently visible.
///
/// Stateful descendants use this signal to pause timers and detach live
/// listeners while their tab is kept alive by the main shell.
class TabActivityScope extends InheritedWidget {
  const TabActivityScope({
    super.key,
    required this.isActive,
    required this.isSelected,
    required super.child,
  });

  /// Whether this tab is visible and its enclosing page route is current.
  ///
  /// Use this for timers, animations, and frame-producing work.
  final bool isActive;

  /// Whether this is the selected main-shell tab.
  ///
  /// This intentionally stays true while a child page covers the shell so
  /// stable streams are not torn down and cold-started again on every back.
  final bool isSelected;

  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<TabActivityScope>()
            ?.isActive ??
        true;
  }

  static bool isSelectedOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<TabActivityScope>()
            ?.isSelected ??
        true;
  }

  @override
  bool updateShouldNotify(TabActivityScope oldWidget) {
    return isActive != oldWidget.isActive || isSelected != oldWidget.isSelected;
  }
}
