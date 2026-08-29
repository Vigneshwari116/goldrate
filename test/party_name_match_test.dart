import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/party_name_match.dart';

void main() {
  test('party name partial and exact matching', () {
    const names = ['UPENDRA', 'Meena', 'Ravi Kumar'];
    expect(PartyNameMatch.hasMatches(names, 'up'), isTrue);
    expect(PartyNameMatch.isExactMatch(names, 'up'), isFalse);
    expect(PartyNameMatch.isExactMatch(names, 'upendra'), isTrue);
    expect(PartyNameMatch.hasMatches(names, 'xyz'), isFalse);
  });
}
