import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/customer_abstract.dart';

void main() {
  test('builds one row per customer with ledger closing balance', () {
    final rows = CustomerAbstractReport.build(
      transactions: [
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'partyName': 'Alpha Jewellers',
          'date': '23-09-2026',
          'items': '[]',
          'totalWt': '10.00',
          'totalPureWt': '9.500',
          'paymentMode': 'CASH',
          'paymentAmount': '1000',
          'paymentItems': '[]',
        },
      ],
      vouchers: const [],
      masterRows: [
        {
          'name': 'Alpha Jewellers',
          'dr': '0',
          'cr': '0',
          'balanceUnit': 'GRAMS',
        },
      ],
      from: DateTime(2026, 9, 23),
      to: DateTime(2026, 9, 23),
      allHistory: false,
      nameQuery: '',
      goldRate: 6500,
    );

    expect(rows.length, 1);
    expect(rows.first.customerName, 'Alpha Jewellers');
    expect(rows.first.totalGross, greaterThan(0));
    expect(rows.first.netPure, 9.5);
    expect(rows.first.cashRupees, 1000);
    expect(rows.first.closingGrams, closeTo(9.5, 0.001));
  });
}
