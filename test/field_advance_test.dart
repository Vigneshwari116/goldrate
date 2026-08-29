import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/field_advance.dart';

void main() {
  test('weight does not complete on a single whole digit', () {
    expect(FieldComplete.weight('1'), isFalse);
    expect(FieldComplete.weight('9'), isFalse);
    expect(FieldComplete.weightWholeIdle('1'), isFalse);
    expect(FieldComplete.weightWholeIdle('12'), isTrue);
  });

  test('weight completes on decimal entry only', () {
    expect(FieldComplete.weight('12'), isFalse);
    expect(FieldComplete.weight('12.5'), isTrue);
    expect(FieldComplete.weight('12.50'), isTrue);
    expect(FieldComplete.weight('12.500'), isFalse);
    expect(FieldComplete.weightWholeIdle('123'), isTrue);
  });

  test('touch does not complete on a single whole digit', () {
    expect(FieldComplete.touch('4'), isFalse);
    expect(FieldComplete.touch('9'), isFalse);
    expect(FieldComplete.touchWholeIdle('4'), isFalse);
    expect(FieldComplete.touchWholeIdle('45'), isTrue);
  });

  test('touch completes on one decimal or idle whole number', () {
    expect(FieldComplete.touch('45'), isFalse);
    expect(FieldComplete.touch('45.6'), isTrue);
    expect(FieldComplete.touchWholeIdle('100'), isTrue);
    expect(FieldComplete.touchWholeIdle('238'), isFalse);
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
    expect(FieldComplete.masterWeight('12.500'), isTrue);
  });

  test('voucherAmount follows mode', () {
    expect(FieldComplete.voucherAmount('12.500', 'GOLD'), isTrue);
    expect(FieldComplete.voucherAmount('12.50', 'GOLD'), isFalse);
    expect(FieldComplete.voucherAmount('5000.00', 'CASH'), isTrue);
    expect(FieldComplete.voucherAmount('5000', 'UPI'), isFalse);
  });
}
