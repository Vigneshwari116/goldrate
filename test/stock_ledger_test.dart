import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:intl/intl.dart';

void main() {
  final fmt = DateFormat('dd-MM-yyyy');

  Map<String, dynamic> bill({
    required String type,
    required int billNo,
    required String date,
    required String party,
    required List<Map<String, dynamic>> items,
  }) =>
      {
        'transactionType': type,
        'billNo': billNo,
        'date': date,
        'partyName': party,
        'items': items,
      };

  Map<String, dynamic> item(String type, double weight, {double touch = 50}) => {
        'type': type,
        'weight': weight,
        'touch': touch,
        'pureWt': weight * touch / 100,
      };

  test('opening uses baseline plus movements before range start', () {
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
    expect(summary.purchases, isEmpty);
    expect(summary.issues, isEmpty);
    expect(summary.closing['GWT'], closeTo(207, 0.001));
  });

  test('closing equals opening plus in-range purchases minus in-range issues', () {
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
    expect(summary.closing['FWT'], closeTo(197, 0.001)); // 201 + 20 - 24
    expect(summary.purchases.length, 2);
    expect(summary.issues.length, 2);
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
    expect(summary.purchases.single.weight, closeTo(100, 0.001));
  });

  test('formatStockWeight trims trailing zeros', () {
    expect(formatStockWeight(0), '');
    expect(formatStockWeight(12), '12');
    expect(formatStockWeight(42.5), '42.5');
    expect(formatStockWeight(12.340), '12.34');
  });
}
