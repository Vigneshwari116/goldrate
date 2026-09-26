import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gst_sales_ledger.dart';
import 'package:grate_app/util/app_date.dart';

void main() {
  final sampleBills = [
    {
      'transactionType': 'PURCHASE',
      'billNo': 3,
      'date': '05-09-2026',
      'partyName': 'Supplier A',
      'partyGstin': '29CCCC0000C1Z5',
      'totalWt': '8.00',
      'totalPureWt': '7.600',
      'totalTaxable': '80000.00',
      'grandTotal': '82400.00',
      'items': '''[
        {"type":"GWT","weight":8,"touch":95,"rate":10000,"hsn":"7113",
         "cgstPercent":1.5,"sgstPercent":1.5}
      ]''',
    },
    {
      'transactionType': 'SALES',
      'billNo': 1,
      'date': '05-09-2026',
      'partyName': 'Customer',
      'grandTotal': '1000.00',
      'items': '[]',
    },
  ];

  test('purchase ledger includes only purchase bills', () {
    final rows = GstPurchaseLedgerReport.rowsForTransactions(
      sampleBills,
      inDateRange: (_) => true,
    );
    expect(rows.length, 1);
    expect(rows.first.billNo, 3);
    expect(rows.first.customerName, 'Supplier A');
  });
}
