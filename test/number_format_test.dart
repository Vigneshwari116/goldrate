import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/utils/number_format.dart';

void main() {
  test('weights always print with three decimals', () {
    expect(formatWeight(null), '0.000');
    expect(formatWeight(''), '0.000');
    expect(formatWeight(12), '12.000');
    expect(formatWeight('5.2'), '5.200');
  });

  test('empty ledger amounts become 0', () {
    expect(orZero(null), '0');
    expect(orZero(''), '0');
    expect(orZero('  '), '0');
    expect(orZero('12.5'), '12.5');
  });
}
