import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/logic/transaction_records.dart';
import 'package:grate_app/util/api_row_keys.dart';
import 'package:grate_app/util/app_date.dart';
import 'package:intl/intl.dart';

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

  test('mergeTransactionsWithLedgerBills builds purchase from supplier ledger',
      () {
    final merged = mergeTransactionsWithLedgerBills(
      transactions: const [],
      customerRows: const [],
      supplierRows: [
        {
          'name': 'Vendor',
          'bill_ref': 'PUR-2',
          'cr': '0',
          'dr': '0',
          'gross': '25.000',
          'net': '5000.00',
          'date': '04-09-2026',
          'time': '01:00 PM',
          'balance_unit': 'GRAMS',
          'narration':
              'Bill #2 (Purchase) — GWT 25.00, Pure 12.500, Value ₹5000.00',
        },
      ],
    );

    expect(merged, hasLength(1));
    expect(merged.first['transactionType'], 'PURCHASE');
    expect(merged.first['billNo'], 2);
    expect(merged.first['partyName'], 'Vendor');
    expect(merged.first['totalPureWt'], '12.500');
    expect(merged.first['items'], isNot('[]'));

    final summary = buildStockLedgerSummary(
      transactions: merged,
      openingWeight: {
        'gPureWt': '0',
        'fineWt': '0',
        'kachaWt': '0',
        'silverWt': '0',
      },
      from: DateTime(2026, 9, 4),
      to: DateTime(2026, 9, 4),
      dateFormat: DateFormat('dd-MM-yyyy'),
    );
    expect(summary.rows, hasLength(1));
    expect(summary.rows.first.label, 'PUR2');
    expect(summary.rows.first.receiptWeights['GWT'], closeTo(25, 0.001));
  });

  test('parseAppDate accepts dd-MM-yyyy and yyyy-MM-dd', () {
    expect(
      parseAppDate('04-09-2026'),
      DateTime(2026, 9, 4),
    );
    expect(
      parseAppDate('2026-09-04'),
      DateTime(2026, 9, 4),
    );
  });
}
