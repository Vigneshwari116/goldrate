import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/models/party_suggestion.dart';

void main() {
  test('groups duplicate names case-insensitively', () {
    final rows = [
      {'name': 'Gajendra', 'mobile': '111', 'city': 'Chennai', 'cr': '1', 'dr': '2'},
      {'name': 'GAJENDRA', 'mobile': '222', 'city': 'Madurai', 'cr': '0', 'dr': '3'},
      {'name': 'Ram', 'mobile': '', 'city': '', 'cr': '0', 'dr': '0'},
    ];

    final suggestions = PartySuggestion.fromLedgerRows(rows, roleLabel: 'Customer');
    expect(suggestions.length, 2);
    expect(suggestions.map((s) => s.name).toList(), ['Gajendra', 'Ram']);
    expect(suggestions.first.roleLabel, 'Customer');
    expect(suggestions.first.detailLine, contains('Customer'));
    expect(suggestions.first.detailLine, isNot(contains('CR')));
  });

  test('matches only when query is non-empty', () {
    const party = PartySuggestion(name: 'Gajendra', mobile: '99999', city: 'City');
    expect(party.matches(''), isFalse);
    expect(party.matches('gaj'), isTrue);
    expect(party.matches('999'), isTrue);
    expect(party.matches('city'), isTrue);
  });

  test('exact name match is detected case-insensitively', () {
    const party = PartySuggestion(name: 'Gajendra');
    expect(party.isExactNameMatch('gajendra'), isTrue);
    expect(party.isExactNameMatch('Gaj'), isFalse);
  });
}
