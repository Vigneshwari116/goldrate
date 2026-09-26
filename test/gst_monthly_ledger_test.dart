import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gst_monthly_ledger.dart';

void main() {
  final txns = [
    {
      'transactionType': 'SALES',
      'date': '10-09-2026',
      'totalTaxable': '100000.00',
      'grandTotal': '103000.00',
      'items': '''[
        {"type":"GWT","weight":10,"touch":100,"rate":10000,"hsn":"7113",
         "cgstPercent":1.5,"sgstPercent":1.5}
      ]''',
    },
    {
      'transactionType': 'PURCHASE',
      'date': '12-09-2026',
      'totalTaxable': '50000.00',
      'grandTotal': '51500.00',
      'items': '''[
        {"type":"GWT","weight":5,"touch":100,"rate":10000,"hsn":"7113",
         "cgstPercent":1.5,"sgstPercent":1.5}
      ]''',
    },
  ];

  test('closing = opening + sales gst - purchase gst', () {
    const seed = 1000.0;
    final row = GstMonthlyLedgerReport.forMonth(
      transactions: txns,
      year: 2026,
      month: 9,
      seedOpening: seed,
    );
    expect(row.openingBalance, seed);
    expect(row.salesGst, closeTo(3000, 0.01));
    expect(row.purchaseGst, closeTo(1500, 0.01));
    expect(row.closingBalance, closeTo(seed + 3000 - 1500, 0.01));
  });
}
