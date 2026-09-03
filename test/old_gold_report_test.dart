import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/old_gold_report.dart';
import 'package:intl/intl.dart';

void main() {
  final fmt = DateFormat('dd-MM-yyyy');

  Map<String, dynamic> oldGoldSale({
    required int billNo,
    required String date,
    required String party,
    required List<Map<String, dynamic>> paymentItems,
  }) =>
      {
        'transactionType': 'SALES',
        'billNo': billNo,
        'date': date,
        'partyName': party,
        'receiptPurpose': kReceiptPurposeOldGold,
        'paymentItems': paymentItems,
      };

  test('includes only sales marked as old gold', () {
    final report = buildOldGoldReport(
      transactions: [
        oldGoldSale(
          billNo: 1,
          date: '10-01-2026',
          party: 'Ravi',
          paymentItems: [
            {
              'type': 'GWT',
              'weight': 12,
              'touch': 50,
              'pureWt': 6,
              'rate': 100,
            },
          ],
        ),
        {
          'transactionType': 'SALES',
          'billNo': 2,
          'date': '10-01-2026',
          'partyName': 'Other',
          'receiptPurpose': null,
          'paymentItems': [
            {
              'type': 'GWT',
              'weight': 99,
              'touch': 50,
              'pureWt': 49.5,
            },
          ],
        },
      ],
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    expect(report.rows.length, 1);
    expect(report.rows.single.saleNo, 'SAL-1');
    expect(report.rows.single.goldWt, closeTo(12, 0.001));
    expect(report.closing.goldWt, closeTo(12, 0.001));
  });

  test('opening carries forward old gold before range start', () {
    final report = buildOldGoldReport(
      transactions: [
        oldGoldSale(
          billNo: 1,
          date: '05-01-2026',
          party: 'A',
          paymentItems: [
            {'type': 'KWT', 'weight': 20, 'touch': 80, 'pureWt': 16, 'rate': 50},
          ],
        ),
        oldGoldSale(
          billNo: 2,
          date: '10-01-2026',
          party: 'B',
          paymentItems: [
            {'type': 'KWT', 'weight': 5, 'touch': 80, 'pureWt': 4, 'rate': 50},
          ],
        ),
      ],
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    expect(report.opening.kachaWt, closeTo(20, 0.001));
    expect(report.rows.length, 1);
    expect(report.closing.kachaWt, closeTo(25, 0.001));
  });

  test('maps payment item types to report columns and cash', () {
    final report = buildOldGoldReport(
      transactions: [
        oldGoldSale(
          billNo: 3,
          date: '10-01-2026',
          party: 'Mix',
          paymentItems: [
            {'type': 'GWT', 'weight': 1, 'touch': 100, 'pureWt': 1, 'rate': 10},
            {'type': 'FWT', 'weight': 2, 'touch': 100, 'pureWt': 2, 'rate': 10},
            {'type': 'KWT', 'weight': 3, 'touch': 100, 'pureWt': 3, 'rate': 10},
            {'type': 'SWT', 'weight': 4, 'touch': 100, 'pureWt': 4, 'rate': 10},
            {
              'type': 'CASH',
              'weight': 0,
              'touch': 0,
              'pureWt': 0,
              'cashAmount': 500,
            },
          ],
        ),
      ],
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: fmt,
    );

    final row = report.rows.single;
    expect(row.goldWt, closeTo(1, 0.001));
    expect(row.pureWt, closeTo(2, 0.001));
    expect(row.kachaWt, closeTo(3, 0.001));
    expect(row.silverWt, closeTo(4, 0.001));
    expect(row.cash, closeTo(500, 0.001));
    expect(row.total, closeTo(600, 0.001));
  });
}
