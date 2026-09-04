import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/widgets/stock_summary_card.dart';
import 'package:intl/intl.dart';

void main() {
  final fmt = DateFormat('dd-MM-yyyy');

  Map<String, dynamic> bill({
    required String type,
    required int billNo,
    required String date,
    required String party,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>>? paymentItems,
  }) =>
      {
        'transactionType': type,
        'billNo': billNo,
        'date': date,
        'partyName': party,
        'items': items,
        if (paymentItems != null) 'paymentItems': paymentItems,
      };

  Map<String, dynamic> item(String type, double weight, {double touch = 50}) => {
        'type': type,
        'weight': weight,
        'touch': touch,
        'pureWt': weight * touch / 100,
      };

  test('opening uses baseline plus net movements before range start', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        bill(
          type: 'PURCHASE',
          billNo: 1,
          date: '01-01-2026',
          party: 'ab',
          items: [item('GWT', 12)],
        ),
        bill(
          type: 'SALES',
          billNo: 1,
          date: '05-01-2026',
          party: 'cd',
          items: [item('GWT', 5)],
        ),
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '201',
        'kachaWt': '202',
        'silverWt': '203',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    expect(summary.opening['GWT'], closeTo(207, 0.001)); // 200 + 12 - 5
    expect(summary.opening['FWT'], closeTo(201, 0.001));
    expect(summary.rows, isEmpty);
    expect(summary.closing['GWT'], closeTo(207, 0.001));
  });

  test('closing equals opening plus in-range receipts minus in-range issues', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        bill(
          type: 'PURCHASE',
          billNo: 1,
          date: '10-01-2026',
          party: 'ab',
          items: [item('GWT', 12)],
        ),
        bill(
          type: 'PURCHASE',
          billNo: 2,
          date: '10-01-2026',
          party: 'xy',
          items: [item('FWT', 20)],
        ),
        bill(
          type: 'SALES',
          billNo: 1,
          date: '10-01-2026',
          party: 'cd',
          items: [item('GWT', 12)],
          paymentItems: [item('FWT', 4)],
        ),
        bill(
          type: 'SALES',
          billNo: 2,
          date: '10-01-2026',
          party: 'ef',
          items: [item('FWT', 24)],
        ),
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '201',
        'kachaWt': '202',
        'silverWt': '203',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    expect(summary.opening['GWT'], closeTo(200, 0.001));
    expect(summary.opening['FWT'], closeTo(201, 0.001));
    expect(summary.closing['GWT'], closeTo(200, 0.001)); // 200 + 12 - 12
    expect(summary.closing['FWT'], closeTo(201, 0.001)); // 201 + 20 + 4 - 24
    expect(summary.rows.length, 4);
    expect(summary.rows.map((r) => r.label).toSet(),
        {'PUR1', 'PUR2', 'SAL1', 'SAL2'});
    final sal1 = summary.rows.firstWhere((r) => r.label == 'SAL1');
    expect(sal1.issueWeights['GWT'], closeTo(12, 0.001));
    expect(sal1.receiptWeights['FWT'], closeTo(4, 0.001));
  });

  test('purchase issue side comes from paymentItems', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        bill(
          type: 'PURCHASE',
          billNo: 1,
          date: '10-01-2026',
          party: 'ra',
          items: [item('GWT', 20)],
          paymentItems: [item('FWT', 40)],
        ),
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '201',
        'kachaWt': '202',
        'silverWt': '203',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    final row = summary.rows.single;
    expect(row.label, 'PUR1');
    expect(row.receiptWeights['GWT'], closeTo(20, 0.001));
    expect(row.issueWeights['FWT'], closeTo(40, 0.001));
    expect(summary.closing['GWT'], closeTo(220, 0.001));
    expect(summary.closing['FWT'], closeTo(161, 0.001)); // 201 - 40
  });

  test('closing for date X matches opening for date X+1', () {
    final txns = [
      bill(
        type: 'PURCHASE',
        billNo: 1,
        date: '10-01-2026',
        party: 'ab',
        items: [item('GWT', 12), item('SWT', 42.5)],
      ),
      bill(
        type: 'SALES',
        billNo: 1,
        date: '10-01-2026',
        party: 'cd',
        items: [item('GWT', 12), item('SWT', 64)],
      ),
    ];
    final opening = {
      'gPureWt': '200',
      'fineWt': '201',
      'kachaWt': '202',
      'silverWt': '203',
    };

    final day1 = buildStockLedgerSummary(
      transactions: txns,
      openingWeight: opening,
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );
    final day2 = buildStockLedgerSummary(
      transactions: txns,
      openingWeight: opening,
      from: DateTime(2026, 1, 11),
      to: DateTime(2026, 1, 11),
      dateFormat: fmt,
    );

    for (final type in kStockWeightTypes) {
      expect(day2.opening[type], closeTo(day1.closing[type]!, 0.001));
    }
  });

  test('uses raw weight not pureWt for ledger totals', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        bill(
          type: 'PURCHASE',
          billNo: 1,
          date: '10-01-2026',
          party: 'ab',
          items: [
            {
              'type': 'GWT',
              'weight': 100,
              'touch': 50,
              'pureWt': 1, // should be ignored
            },
          ],
        ),
      ],
      openingWeight: {'gPureWt': '0', 'fineWt': '0', 'kachaWt': '0', 'silverWt': '0'},
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    expect(summary.closing['GWT'], closeTo(100, 0.001));
    expect(summary.rows.single.receiptWeights['GWT'], closeTo(100, 0.001));
  });

  test('formatStockWeight trims trailing zeros', () {
    expect(formatStockWeight(0), '');
    expect(formatStockWeight(0, blankWhenZero: false), '0.000');
    expect(formatStockWeight(12), '12');
    expect(formatStockWeight(42.5), '42.5');
    expect(formatStockWeight(12.340), '12.34');
  });

  test('opening baseline accepts snake_case API keys', () {
    final weights = openingBaselineFromRow({
      'g_pure_wt': '5',
      'fine_wt': '2',
      'kacha_wt': '3',
      'silver_wt': '1',
    });
    expect(weights['GWT'], closeTo(5, 0.001));
    expect(weights['FWT'], closeTo(2, 0.001));
    expect(weights['KWT'], closeTo(3, 0.001));
    expect(weights['SWT'], closeTo(1, 0.001));
  });

  test('daily sales opening and closing show all four weight columns', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'date': '03-09-2026',
          'partyName': 'ab',
          'items': [
            {'type': 'GWT', 'weight': 10, 'touch': 100},
          ],
        },
      ],
      openingWeight: {
        'gPureWt': '5',
        'fineWt': '2',
        'kachaWt': '3',
        'silverWt': '1',
      },
      from: DateTime(2026, 9, 3),
      to: DateTime(2026, 9, 3),
      dateFormat: fmt,
    );

    expect(summary.opening['GWT'], closeTo(5, 0.001));
    expect(summary.opening['FWT'], closeTo(2, 0.001));
    expect(summary.closing['GWT'], closeTo(-5, 0.001));
    expect(summary.closing['FWT'], closeTo(2, 0.001));
    expect(summary.closing['KWT'], closeTo(3, 0.001));
    expect(summary.closing['SWT'], closeTo(1, 0.001));

    final opening = StockSummaryTable.openingRow(summary.opening);
    expect(opening[11], '5');
    expect(opening[12], '2');
    expect(opening[13], '3');
    expect(opening[14], '1');
    expect(opening[6], '');

    final closing = StockSummaryTable.closingRow(summary.closing);
    expect(closing[11], '-5');
    expect(closing[12], '2');
    expect(closing[13], '3');
    expect(closing[14], '1');
    expect(closing[6], '-5');
    expect(closing[7], '2');
    expect(closing[8], '3');
    expect(closing[9], '1');
  });

  test('includes bills when date uses yyyy-MM-dd from API', () {
    final summary = buildStockLedgerSummary(
      transactions: [
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'date': '2026-09-03',
          'partyName': 'ab',
          'items': [
            {'type': 'GWT', 'weight': 10, 'touch': 100},
          ],
        },
      ],
      openingWeight: null,
      from: DateTime(2026, 9, 3),
      to: DateTime(2026, 9, 3),
      dateFormat: fmt,
    );
    expect(summary.rows.length, 1);
    expect(summary.rows.first.issueWeights['GWT'], closeTo(10, 0.001));
  });
}
