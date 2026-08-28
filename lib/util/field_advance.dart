import 'dart:async';

import 'package:flutter/material.dart';

import 'focus_chain.dart';

/// Detects when a field value is fully entered (no Enter key needed).
class FieldComplete {
  FieldComplete._();

  static final _weightDec = RegExp(r'^\d+\.\d{2,3}$');
  static final _touch2 = RegExp(r'^\d+\.\d{2}$');
  static final _mobile10 = RegExp(r'^\d{10}$');
  static final _cash2 = RegExp(r'^\d+\.\d{2}$');

  static bool weight(String value) {
    final t = value.trim();
    if (!_weightDec.hasMatch(t)) return false;
    return (double.tryParse(t) ?? 0) > 0;
  }

  /// Touch % — advance once two decimal places are entered (e.g. 23.80).
  static bool touch(String value) {
    final t = value.trim();
    if (!_touch2.hasMatch(t)) return false;
    final n = double.tryParse(t);
    return n != null && n > 0 && n <= 100;
  }

  /// Whole-number 100 without a decimal — advance only after idle pause.
  static bool touchWholeIdle(String value) => value.trim() == '100';

  static bool mobile(String value) => _mobile10.hasMatch(value.trim());

  static bool cash(String value) {
    final t = value.trim();
    if (!_cash2.hasMatch(t)) return false;
    return (double.tryParse(t) ?? 0) > 0;
  }

  /// Master optional weight — advance once three decimal places are entered.
  static bool masterWeight(String value) => weight(value);

  static bool voucherAmount(String value, String mode) {
    if (mode == 'GOLD') return weight(value);
    return cash(value);
  }
}

/// Auto-advance focus when a field is complete or after typing pauses.
mixin FocusAdvanceMixin<T extends StatefulWidget> on State<T> {
  Timer? _focusAdvanceIdle;

  @override
  void dispose() {
    _focusAdvanceIdle?.cancel();
    super.dispose();
  }

  void advanceWhenComplete({
    required String value,
    required FocusNode from,
    required bool Function(String) isComplete,
    FocusNode? to,
    TextEditingController? toController,
    VoidCallback? action,
  }) {
    if (!from.hasFocus) return;
    if (!isComplete(value)) return;
    _focusAdvanceIdle?.cancel();
    final completedValue = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isComplete(completedValue)) return;
      if (action != null) {
        action();
      } else if (to != null) {
        FocusChain.focus(to, controller: toController);
      }
    });
  }

  void advanceWhenIdle({
    required String value,
    required FocusNode from,
    FocusNode? to,
    TextEditingController? toController,
    VoidCallback? action,
    Duration delay = const Duration(milliseconds: 700),
    bool Function(String value)? when,
  }) {
    _focusAdvanceIdle?.cancel();
    final ready = when ?? (v) => v.trim().length >= 2;
    if (!ready(value)) return;
    _focusAdvanceIdle = Timer(delay, () {
      if (!mounted || !from.hasFocus) return;
      if (action != null) {
        action();
      } else if (to != null) {
        FocusChain.focusNextFrame(to, controller: toController);
      }
    });
  }
}
