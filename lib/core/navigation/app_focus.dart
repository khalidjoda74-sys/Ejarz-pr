import 'package:flutter/widgets.dart';

/// Clears the active input focus and its route/tab restoration history.
///
/// Hiding the system keyboard alone is not enough because Flutter can restore
/// the same focused field when a kept-alive page becomes visible again.
void dismissAppKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus(
    disposition: UnfocusDisposition.scope,
  );
}
