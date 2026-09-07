import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/touch_input.dart';

void main() {
  test('TouchPercentInputFormatter rejects values above 99.9', () {
    final formatter = TouchPercentInputFormatter();
    expect(
      formatter.formatEditUpdate(
        const TextEditingValue(text: '99.9'),
        const TextEditingValue(text: '100'),
      ).text,
      '99.9',
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

  test('isValidTouchPercent accepts 30 through 99.9', () {
    expect(isValidTouchPercent('30'), isTrue);
    expect(isValidTouchPercent('99.9'), isTrue);
    expect(isValidTouchPercent('91.6'), isTrue);
  });

  test('isValidTouchPercent rejects blank, zero, and out of range', () {
    expect(isValidTouchPercent(''), isFalse);
    expect(isValidTouchPercent('0'), isFalse);
    expect(isValidTouchPercent('29.9'), isFalse);
    expect(isValidTouchPercent('100'), isFalse);
  });

  test('touchPercentValidationMessage returns helper text when invalid', () {
    expect(touchPercentValidationMessage(''), kTouchPercentError);
    expect(touchPercentValidationMessage('91'), isNull);
  });
}
