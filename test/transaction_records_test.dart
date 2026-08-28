import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/transaction_records.dart';
import 'package:grate_app/util/api_row_keys.dart';

void main() {
  test('normalizeApiRow converts snake_case keys', () {
    final row = normalizeApiRow({
      'transaction_type': 'SALES',
      'bill_no': 1,
      'party_name': 'Raja',
    });
    expect(row['transactionType'], 'SALES');
    expect(row['billNo'], 1);
    expect(row['partyName'], 'Raja');
  });

  test('mergeTransactionsWithLedgerBills builds sales from customer ledger', () {
    final merged = mergeTransactionsWithLedgerBills(
      transactions: const [],
      customerRows: [
        {
          'name': 'Raja',
          'bill_ref': 'SAL-1',
          'dr': '17.500',
          'dr_gross': '177.74',
          'dr_net': '5000.00',
          'date': '28-08-2026',
          'time': '10:30 AM',
          'balance_unit': 'GRAMS',
          'narration': 'Bill #1 (Sale)',
        },
      ],
      supplierRows: const [],
    );

    expect(merged, hasLength(1));
    expect(merged.first['transactionType'], 'SALES');
    expect(merged.first['billNo'], 1);
    expect(merged.first['partyName'], 'Raja');
    expect(merged.first['fromLedger'], isTrue);
  });

  test('transactions table row wins over duplicate ledger row', () {
    final merged = mergeTransactionsWithLedgerBills(
      transactions: [
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'partyName': 'Raja',
          'totalPureWt': '20.000',
        },
      ],
      customerRows: [
        {
          'name': 'Raja',
          'billRef': 'SAL-1',
          'dr': '17.500',
        },
      ],
      supplierRows: const [],
    );

    expect(merged, hasLength(1));
    expect(merged.first['totalPureWt'], '20.000');
    expect(merged.first['fromLedger'], isNull);
  });
}
