import 'package:flutter/material.dart';

/// Mixin for screens kept alive inside [IndexedStack] that should reload
/// remote/local lists when the user navigates back to the tab.
mixin ScreenActivationMixin<T extends StatefulWidget> on State<T> {
  bool get screenIsActive;

  bool wasScreenActive(T oldWidget);

  void onScreenActivated();

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (screenIsActive && !wasScreenActive(oldWidget)) {
      onScreenActivated();
    }
  }
}
