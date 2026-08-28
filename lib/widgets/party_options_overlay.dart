import 'package:flutter/material.dart';

/// Positions autocomplete suggestions directly below the name field.
Widget partyAutocompleteOptionsView({
  required BuildContext context,
  required Widget child,
}) {
  return Align(
    alignment: AlignmentDirectional.topStart,
    widthFactor: 1.0,
    heightFactor: 0.0,
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
