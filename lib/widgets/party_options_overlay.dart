import 'package:flutter/material.dart';

/// Positions autocomplete suggestions directly below the name field.
Widget partyAutocompleteOptionsView({
  required BuildContext context,
  required Widget child,
}) {
  return Material(
    color: Colors.transparent,
    child: child,
  );
}

Widget partyAutocompleteOptionsShell({
  required Widget child,
  double maxHeight = 280,
  double minWidth = 320,
}) {
  return Material(
    elevation: 6,
    borderRadius: BorderRadius.circular(6),
    color: Colors.white,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, minWidth: minWidth),
      child: child,
    ),
  );
}

/// Selects an autocomplete option on pointer-down so taps register before
/// the overlay closes from focus changes.
Widget partyAutocompleteOptionTile({
  required VoidCallback onSelected,
  required Widget child,
}) {
  return Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => onSelected(),
    child: child,
  );
}
