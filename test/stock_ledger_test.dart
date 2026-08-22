import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/utils/stock_ledger.dart';

void main() {
  test('current stock is opening plus purchase minus sales', () {
    final rows = buildStockSummary(
      openingByType: {'GWT': 10, 'FWT': 0, 'KWT': 0, 'SWT': 0},
      transactions: [
        {
          'transactionType': 'PURCHASE',
          'items': [
            {'type': 'GWT', 'pureWt': 2.5},
          ],
        },
        {
          'transactionType': 'SALES',
          'items': [
            {'type': 'GWT', 'pureWt': 1.0},
          ],
        },
      ],
      itemsOf: (row) => row['items'] as List<dynamic>,
    );
    final gwt = rows.firstWhere((r) => r.type == 'GWT');
    expect(gwt.opening, 10);
    expect(gwt.purchased, 2.5);
    expect(gwt.sold, 1.0);
    expect(gwt.current, 11.5);
  });

  test('stock ledger running balance starts at opening', () {
    final ledger = buildStockLedger(
      metalType: 'GWT',
      openingByType: {'GWT': 5, 'FWT': 0, 'KWT': 0, 'SWT': 0},
      openingDate: '01-01-2026',
      openingTime: '10:00 AM',
      transactionsOldestFirst: [
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'partyName': 'Ram',
          'date': '02-01-2026',
          'time': '11:00 AM',
          'items': [
            {'type': 'GWT', 'pureWt': 1.5},
          ],
        },
      ],
      itemsOf: (row) => row['items'] as List<dynamic>,
    );
    expect(ledger, hasLength(2));
    expect(ledger.first.refType, 'OPENING');
    expect(ledger.first.balance, 5);
    expect(ledger.last.refType, 'SALES');
    expect(ledger.last.qtyOut, 1.5);
    expect(ledger.last.balance, 3.5);
  });
}
