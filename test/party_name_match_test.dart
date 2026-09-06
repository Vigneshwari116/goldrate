import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/util/party_name_key.dart';

void main() {
  test('findDuplicatePartyName is case-insensitive', () {
    const names = ['Upendra', 'Meena', 'Ravi Kumar'];
    expect(findDuplicatePartyName('upendra', names), 'Upendra');
    expect(findDuplicatePartyName('MEENA', names), 'Meena');
    expect(findDuplicatePartyName('New Person', names), isNull);
    expect(isDuplicatePartyName('ravi kumar', names), isTrue);
  });

  test('party name partial matching still works', () {
    const names = ['UPENDRA', 'Meena', 'Ravi Kumar'];
    expect(partyNameMatches('UPENDRA', 'up'), isTrue);
    expect(partyNameMatches('UPENDRA', 'upendra'), isTrue);
    expect(partyNameMatches('UPENDRA', 'xyz'), isFalse);
  });
}
