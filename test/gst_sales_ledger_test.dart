import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gst_sales_ledger.dart';
import 'package:grate_app/util/app_date.dart';

void main() {
  final sampleBills = [
    {
      'transactionType': 'SALES',
      'billNo': 1,
      'date': '01-09-2026',
      'partyName': 'Alpha Traders',
      'partyGstin': '29AAAAA0000A1Z5',
      'totalWt': '10.00',
      'totalPureWt': '9.500',
      'totalTaxable': '100000.00',
      'grandTotal': '103000.00',
      'items': '''[
        {"type":"GWT","weight":10,"touch":95,"rate":10000,"hsn":"7113",
         "cgstPercent":1.5,"sgstPercent":1.5}
      ]''',
    },
    {
      'transactionType': 'SALES',
      'billNo': 2,
      'date': '15-09-2026',
      'partyName': 'Beta Jewellers',
      'partyGstin': '29BBBBB1111B1Z5',
      'totalWt': '5.00',
      'totalPureWt': '5.000',
      'totalTaxable': '50000.00',
      'grandTotal': '51500.00',
      'items': '''[
        {"type":"GWT","weight":5,"touch":100,"rate":10000,"hsn":"7113",
         "cgstPercent":1.5,"sgstPercent":1.5}
      ]''',
    },
    {
      'transactionType': 'PURCHASE',
      'billNo': 1,
      'date': '10-09-2026',
      'partyName': 'Supplier X',
      'grandTotal': '99999.00',
      'items': '[]',
    },
  ];

  bool inRange(String? date) {
    final d = parseAppDate(date);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 9, 10);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  test('filters sales bills by date range', () {
    final rows = GstSalesLedgerReport.rowsForTransactions(
      sampleBills,
      inDateRange: inRange,
    );
    expect(rows.length, 1);
    expect(rows.first.billNo, 1);
    expect(rows.first.customerName, 'Alpha Traders');
  });

  test('uses saved grand total per bill', () {
    final rows = GstSalesLedgerReport.rowsForTransactions(
      sampleBills,
      inDateRange: (_) => true,
    );
    expect(rows.length, 2);
    expect(rows[0].grandTotal, 103000);
    expect(rows[1].grandTotal, 51500);
  });

  test('range totals sum weight and tax columns', () {
    final rows = GstSalesLedgerReport.rowsForTransactions(
      sampleBills,
      inDateRange: (_) => true,
    );
    final totals = GstSalesLedgerReport.totalsFor(rows);
    expect(totals.totalWeight, 15);
    expect(totals.grandTotal, 103000 + 51500);
    final footer = totals.toFooterCells();
    expect(footer.first, 'TOTAL');
    expect(footer.last.replaceAll(',', ''), contains('154500'));
  });

  test('single-day range includes only that day', () {
    bool singleDay(String? date) {
      final d = parseAppDate(date);
      if (d == null) return false;
      return d.day == 15 && d.month == 9 && d.year == 2026;
    }

    final rows = GstSalesLedgerReport.rowsForTransactions(
      sampleBills,
      inDateRange: singleDay,
    );
    expect(rows.length, 1);
    expect(rows.first.billNo, 2);
  });
}
