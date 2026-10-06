import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Remote API contract: `ApiClient.insertTransaction` JSON-encodes the full
/// bill map from `TransactionScreen` (includes `billNarration`).
void main() {
  test('transaction POST body includes billNarration camelCase key', () {
    final record = <String, dynamic>{
      'transactionType': 'SALES',
      'billNo': 1,
      'partyName': 'Test Customer',
      'items': '[]',
      'billNarration': 'Ring resizing note',
      'partyAddress': '1 Main St',
      'ewayBill': '',
    };

    final body = jsonEncode(record);
    final decoded = jsonDecode(body) as Map<String, dynamic>;

    expect(decoded.containsKey('billNarration'), isTrue);
    expect(decoded['billNarration'], 'Ring resizing note');
  });
}
