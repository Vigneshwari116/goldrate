import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/field_advance.dart';

void main() {
  test('weight completes on whole number, one decimal, or two decimals', () {
    expect(FieldComplete.weight('12'), isTrue);
    expect(FieldComplete.weight('12.5'), isTrue);
    expect(FieldComplete.weight('12.50'), isTrue);
    expect(FieldComplete.weight('12.500'), isFalse);
    expect(FieldComplete.weight('0'), isFalse);
    expect(FieldComplete.weight('0.00'), isFalse);
  });

  test('weight whole idle advances only on multi-digit whole numbers', () {
    expect(FieldComplete.weightWholeIdle('123'), isTrue);
    expect(FieldComplete.weightWholeIdle('12'), isTrue);
    expect(FieldComplete.weightWholeIdle('1'), isFalse);
    expect(FieldComplete.weightWholeIdle('123.4'), isFalse);
  });

  test('touch completes on whole number or one decimal', () {
    expect(FieldComplete.touch('45'), isTrue);
    expect(FieldComplete.touch('45.6'), isTrue);
    expect(FieldComplete.touch('23.80'), isFalse);
    expect(FieldComplete.touch('91.6'), isTrue);
    expect(FieldComplete.touch('238'), isFalse);
    expect(FieldComplete.touch('0'), isFalse);
  });

  test('touch whole number idle-advances only when valid', () {
    expect(FieldComplete.touchWholeIdle('100'), isTrue);
    expect(FieldComplete.touchWholeIdle('45'), isTrue);
    expect(FieldComplete.touchWholeIdle('99'), isTrue);
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

  test('masterWeight requires three decimal places', () {
    expect(FieldComplete.masterWeight('12.5'), isFalse);
    expect(FieldComplete.masterWeight('12.50'), isFalse);
    expect(FieldComplete.masterWeight('12.500'), isTrue);
  });

  test('voucherAmount follows mode', () {
    expect(FieldComplete.voucherAmount('12.500', 'GOLD'), isTrue);
    expect(FieldComplete.voucherAmount('12.50', 'GOLD'), isFalse);
    expect(FieldComplete.voucherAmount('5000.00', 'CASH'), isTrue);
    expect(FieldComplete.voucherAmount('5000', 'UPI'), isFalse);
  });
}
