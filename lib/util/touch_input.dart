import 'package:flutter/services.dart';

/// Valid Touch % range for new metal lines (Issue / Receipt entry).
const double kTouchPercentMin = 30;
const double kTouchPercentMax = 99.9;
const String kTouchPercentError = 'Enter a valid Touch % (30-99.9)';

bool isValidTouchPercent(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final value = double.tryParse(trimmed);
  if (value == null) return false;
  return value >= kTouchPercentMin && value <= kTouchPercentMax;
}

String? touchPercentValidationMessage(String text) {
  return isValidTouchPercent(text) ? null : kTouchPercentError;
}

/// Blur validation: empty is allowed until the user tries to add a row.
String? touchPercentBlurValidationMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return isValidTouchPercent(trimmed) ? null : kTouchPercentError;
}

/// Touch % entry: up to 2 digits before decimal, 2 after; max [kTouchPercentMax].
class TouchPercentInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d{0,2}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!_pattern.hasMatch(text)) return oldValue;
    final value = double.tryParse(text);
    if (value != null && value > kTouchPercentMax) return oldValue;
    return newValue;
  }
}
