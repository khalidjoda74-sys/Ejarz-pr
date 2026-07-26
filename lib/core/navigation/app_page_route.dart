import 'package:flutter/material.dart';

import 'app_focus.dart';

/// An opaque, immediate page switch matching the main bottom-tab behavior.
///
/// Page-to-page slide transitions paint both routes during the animation,
/// which can look like screens are overlapping and adds latency to open/back.
/// Forsa switches pages atomically instead: dialogs and bottom sheets keep
/// their own animations, while full screens never cross-fade or slide.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting = false,
  });

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  TickerFuture didPush() {
    dismissAppKeyboard();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    dismissAppKeyboard();
    return super.didPop(result);
  }

  @override
  void didReplace(Route<dynamic>? oldRoute) {
    dismissAppKeyboard();
    super.didReplace(oldRoute);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
