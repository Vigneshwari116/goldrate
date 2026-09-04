import 'package:flutter/services.dart';

/// Touch % entry: up to 2 digits before decimal, 2 after; max 99.99.
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
    if (value != null && value > 99.99) return oldValue;
    return newValue;
  }
}
