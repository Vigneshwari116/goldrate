import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/touch_input.dart';

void main() {
  test('TouchPercentInputFormatter rejects values above 99.99', () {
    final formatter = TouchPercentInputFormatter();
    expect(
      formatter.formatEditUpdate(
        const TextEditingValue(text: '99.99'),
        const TextEditingValue(text: '100'),
      ).text,
      '99.99',
    );
  });

  test('TouchPercentInputFormatter allows two decimal places', () {
    final formatter = TouchPercentInputFormatter();
    expect(
      formatter.formatEditUpdate(
        const TextEditingValue(text: '9'),
        const TextEditingValue(text: '91.60'),
      ).text,
      '91.60',
    );
  });
}
