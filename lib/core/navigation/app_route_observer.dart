import 'package:flutter/material.dart';

import 'app_focus.dart';

/// Observes page-to-page navigation without treating dialogs and bottom sheets
/// as page changes.
final RouteObserver<PageRoute<dynamic>> appPageRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Exposes whether the owning page is the visible page in its navigator.
///
/// A [PopupRoute] does not deactivate the page, so opening a dialog cannot
/// tear down live data and force a cold reload when the dialog closes.
mixin PageRouteActivityMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  PageRoute<dynamic>? _observedPageRoute;
  bool _pageRouteActive = true;

  @protected
  bool get isPageRouteActive => _pageRouteActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _observedPageRoute)) return;

    appPageRouteObserver.unsubscribe(this);
    _observedPageRoute = route is PageRoute<dynamic> ? route : null;
    final pageRoute = _observedPageRoute;
    if (pageRoute != null) {
      appPageRouteObserver.subscribe(this, pageRoute);
    }
  }

  @override
  void didPush() => _setPageRouteActive(true);

  @override
  void didPopNext() => _setPageRouteActive(true);

  @override
  void didPushNext() => _setPageRouteActive(false);

  @override
  void didPop() => _setPageRouteActive(false);

  void _setPageRouteActive(bool value) {
    if (_pageRouteActive == value) return;
    dismissAppKeyboard();
    _pageRouteActive = value;
    onPageRouteActivityChanged(value);
  }

  @protected
  void onPageRouteActivityChanged(bool isActive) {}

  @override
  void dispose() {
    appPageRouteObserver.unsubscribe(this);
    _observedPageRoute = null;
    super.dispose();
  }
}
