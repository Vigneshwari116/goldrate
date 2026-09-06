import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/widgets/stock_summary_card.dart';
import 'package:intl/intl.dart';

void main() {
  test('closing summary lists all four weight types', () {
    final text = StockSummaryTable.closingSummaryText({
      'GWT': 200,
      'FWT': 201,
      'KWT': 202,
      'SWT': 500,
    });
    expect(text, contains('GWT: 200'));
    expect(text, contains('FWT: 201'));
    expect(text, contains('KWT: 202'));
    expect(text, contains('SWT: 500'));
  });

  test('buildStockLedgerSummary splits purchase and sales rows', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        {
          'transactionType': 'PURCHASE',
          'billNo': 1,
          'date': '10-01-2026',
          'partyName': 'ab',
          'items': [
            {'type': 'GWT', 'weight': 12, 'touch': 50, 'pureWt': 6},
          ],
        },
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'date': '10-01-2026',
          'partyName': 'cd',
          'items': [
            {'type': 'GWT', 'weight': 20, 'touch': 50, 'pureWt': 10},
          ],
          'paymentItems': [
            {'type': 'O.GWT', 'weight': 30, 'touch': 50, 'pureWt': 15},
          ],
        },
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '300',
        'kachaWt': '400',
        'silverWt': '500',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: DateFormat('dd-MM-yyyy'),
    );

    expect(summary.purchases.length, 1);
    expect(summary.sales.length, 1);
    expect(summary.purchases.single.weights['GWT'], closeTo(12, 0.001));
    expect(summary.sales.single.weights['GWT'], closeTo(20, 0.001));
    expect(summary.purchaseTotals['GWT'], closeTo(12, 0.001));
    expect(summary.salesTotals['GWT'], closeTo(20, 0.001));
    expect(summary.closing['GWT'], closeTo(192, 0.001));
  });

  test('pdf opening row places weights under GWT FWT KWT SWT columns in both boxes', () {
    final summary = buildStockLedgerSummary(
      transactions: const [],
      openingWeight: {
        'gPureWt': '110.2',
        'fineWt': '201',
        'kachaWt': '202',
        'silverWt': '5000',
      },
      from: DateTime(2026, 9, 6),
      to: DateTime(2026, 9, 6),
      dateFormat: DateFormat('dd-MM-yyyy'),
    );

    final rows = StockSummaryTable.pdfRowsFor(summary);
    expect(rows[0][0], 'PURCHASE');
    expect(rows[1], StockSummaryTable.boxHeaders);
    expect(rows[2][0], 'Opening Stock', reason: rows.map((r) => r[0]).join(', '));

    final purchaseOpening = rows[2];
    final salesHeaderIndex =
        rows.indexWhere((row) => row.isNotEmpty && row.first == 'SALES');
    expect(salesHeaderIndex, greaterThan(0));
    final salesOpening = rows[salesHeaderIndex + 2];

    for (final openingRow in [purchaseOpening, salesOpening]) {
      expect(openingRow[0], 'Opening Stock');
      expect(openingRow[1], '');
      expect(openingRow[2], '');
      expect(openingRow[3], '110.2');
      expect(openingRow[4], '201');
      expect(openingRow[5], '202');
      expect(openingRow[6], '5000');
    }
  });
}
