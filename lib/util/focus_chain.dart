import 'package:flutter/material.dart';

/// Moves keyboard focus to the next field in data-entry forms.
class FocusChain {
  FocusChain._();

  static void focus(
    FocusNode node, {
    TextEditingController? controller,
    bool selectAll = true,
  }) {
    node.requestFocus();
    if (controller != null && selectAll) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
  }

  static void focusNextFrame(
    FocusNode node, {
    TextEditingController? controller,
    bool selectAll = true,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus(node, controller: controller, selectAll: selectAll);
    });
  }
}
