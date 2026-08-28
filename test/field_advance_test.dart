import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/field_advance.dart';

void main() {
  test('weight completes with two or three decimal places', () {
    expect(FieldComplete.weight('12.5'), isFalse);
    expect(FieldComplete.weight('12.50'), isTrue);
    expect(FieldComplete.weight('12.500'), isTrue);
    expect(FieldComplete.weight('0.00'), isFalse);
    expect(FieldComplete.weight('0.000'), isFalse);
  });

  test('touch completes with two decimals including 23.80', () {
    expect(FieldComplete.touch('23.8'), isFalse);
    expect(FieldComplete.touch('23.80'), isTrue);
    expect(FieldComplete.touch('91.6'), isFalse);
    expect(FieldComplete.touch('91.60'), isTrue);
    expect(FieldComplete.touch('99.89'), isTrue);
    expect(FieldComplete.touch('238.00'), isFalse);
    expect(FieldComplete.touch('91'), isFalse);
    expect(FieldComplete.touch('99'), isFalse);
  });

  test('touch whole number 100 idle-advances only when exact', () {
    expect(FieldComplete.touchWholeIdle('100'), isTrue);
    expect(FieldComplete.touchWholeIdle('99'), isFalse);
    expect(FieldComplete.touchWholeIdle('92'), isFalse);
    expect(FieldComplete.touchWholeIdle('238'), isFalse);
    expect(FieldComplete.touchWholeIdle('23.8'), isFalse);
    expect(FieldComplete.touchWholeIdle('9'), isFalse);
  });

  test('mobile completes at ten digits', () {
    expect(FieldComplete.mobile('987654321'), isFalse);
    expect(FieldComplete.mobile('9876543210'), isTrue);
  });

  test('cash completes with paise', () {
    expect(FieldComplete.cash('5000'), isFalse);
    expect(FieldComplete.cash('5000.00'), isTrue);
  });

  test('masterWeight matches flexible decimal weight', () {
    expect(FieldComplete.masterWeight('12.5'), isFalse);
    expect(FieldComplete.masterWeight('12.50'), isTrue);
    expect(FieldComplete.masterWeight('12.500'), isTrue);
  });

  test('voucherAmount follows mode', () {
    expect(FieldComplete.voucherAmount('12.50', 'GOLD'), isTrue);
    expect(FieldComplete.voucherAmount('12.500', 'GOLD'), isTrue);
    expect(FieldComplete.voucherAmount('5000.00', 'CASH'), isTrue);
    expect(FieldComplete.voucherAmount('5000', 'UPI'), isFalse);
  });
}
