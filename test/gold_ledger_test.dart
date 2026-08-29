import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gold_ledger.dart';

void main() {
  test('cash converts to gold at the given rate', () {
    expect(GoldLedger.cashToGold(30200, 15100), closeTo(2, 0.0001));
    expect(GoldLedger.goldToCash(2, 15100), closeTo(30200, 0.01));
  });

  test('unpaid sale adds the billed weight to the customer gold balance', () {
    final result = settleLedger(
      oldGrams: 0,
      oldRupees: 0,
      billGrams: 12.5,
      billRupees: 188750,
      paymentMode: 'CASH',
      paymentAmount: 0,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.newGrams, closeTo(12.5, 0.0001));
    expect(result.cashToGoldGrams, 0);
  });

  test('cash receipt converts rupees into gold and reduces the gold balance', () {
    final result = settleLedger(
      oldGrams: 12.5,
      oldRupees: 188750,
      billGrams: 0,
      billRupees: 0,
      paymentMode: 'CASH',
      paymentAmount: 188750,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.cashToGoldGrams, closeTo(12.5, 0.0001));
    expect(result.newGrams, closeTo(0, 0.0001));
  });

  test('gold receipt voucher reduces the gold balance by grams paid', () {
    final result = settleLedger(
      oldGrams: 12.5,
      oldRupees: 0,
      billGrams: 0,
      billRupees: 0,
      paymentMode: 'GOLD',
      paymentAmount: 12.5,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.newGrams, closeTo(0, 0.0001));
  });

  test('unpaid purchase credits the supplier (shop owes gold)', () {
    final result = settleLedger(
      oldGrams: 0,
      oldRupees: 0,
      billGrams: 8.25,
      billRupees: 124575,
      paymentMode: 'CASH',
      paymentAmount: 0,
      ratePerGram: 15100,
      billSign: -1,
    );
    expect(result.newGrams, closeTo(-8.25, 0.0001));
  });

  test('party ledger records list bills and vouchers with name filter', () {
    final rows = buildPartyLedgerRecords(
      customer: true,
      transactions: [
        {
          'transactionType': 'SALES',
          'partyName': 'Ravi Kumar',
          'billNo': 1,
          'totalWt': '12.000',
          'totalPureWt': '10.000',
          'totalValue': '151000',
          'paymentMode': 'GOLD',
          'paymentAmount': '2.000',
          'date': '01-08-2026',
        },
        {
          'transactionType': 'SALES',
          'partyName': 'Meena',
          'billNo': 2,
          'totalWt': '6.000',
          'totalPureWt': '5.000',
          'totalValue': '75500',
          'paymentMode': 'CASH',
          'paymentAmount': '0',
          'cashToGold': '0',
          'date': '02-08-2026',
        },
      ],
      vouchers: [
        {
          'partyName': 'Ravi Kumar',
          'isCustomer': 1,
          'voucherType': 'RECEIPT',
          'voucherNo': 1,
          'paymentMode': 'CASH',
          'amount': '30200',
          'cashToGold': '2.000',
          'date': '03-08-2026',
        },
      ],
      allHistory: true,
      nameQuery: 'ravi',
      goldRate: 15100,
    );
    expect(rows.length, 2);
    expect(rows.first.partyName, 'Ravi Kumar');
    expect(rows.first.typeLabel, 'SALES(G)');
    expect(rows.first.issueWeight, closeTo(12, 0.0001));
    expect(rows.first.receiptWeight, closeTo(2, 0.0001));
    expect(rows.first.pureGold, closeTo(10, 0.0001));
    expect(rows.last.typeLabel, 'RECEIPT(C)');
    expect(rows.last.receiptWeight, closeTo(2, 0.0001));
  });

  test('party ledger sections include opening and closing balances', () {
    final sections = buildPartyLedgerSections(
      customer: true,
      transactions: [
        {
          'transactionType': 'SALES',
          'partyName': 'Ravi',
          'billNo': 1,
          'totalWt': '12.000',
          'totalPureWt': '10.000',
          'totalValue': '151000',
          'paymentMode': 'CASH',
          'paymentAmount': '0',
          'cashToGold': '0',
          'date': '10-08-2026',
        },
      ],
      vouchers: const [],
      from: DateTime(2026, 8, 10),
      to: DateTime(2026, 8, 10),
      goldRate: 15100,
    );
    expect(sections.length, 1);
    expect(sections.first.openingBalance, 0);
    expect(sections.first.closingBalance, closeTo(10, 0.0001));
    final table = sections.first.toTableRows();
    expect(table.first.last, '+10.000 g');
    expect(table.last.last, '+10.000 g');
  });

  test('customer name-wise uses sales as debit and payments as credit', () {
    final rows = buildPartyNameWise(
      customer: true,
      knownNames: ['Ravi'],
      transactions: [
        {
          'transactionType': 'SALES',
          'partyName': 'Ravi',
          'totalPureWt': '12.500',
          'paymentMode': 'CASH',
          'paymentAmount': '0',
          'cashToGold': '0',
          'date': '01-08-2026',
        },
        {
          'transactionType': 'SALES',
          'partyName': 'Ravi',
          'totalPureWt': '2.000',
          'paymentMode': 'CASH',
          'cashToGold': '1.000',
          'date': '10-08-2026',
        },
      ],
      vouchers: [
        {
          'partyName': 'Ravi',
          'isCustomer': 1,
          'voucherType': 'RECEIPT',
          'paymentMode': 'GOLD',
          'amount': '3.000',
          'date': '10-08-2026',
        },
      ],
      from: DateTime(2026, 8, 10),
      to: DateTime(2026, 8, 10),
    );
    expect(rows.first.types, 'SALES, RECEIPT');
    expect(rows.first.opening, closeTo(12.5, 0.0001));
    expect(rows.first.debit, closeTo(2.0, 0.0001));
    expect(rows.first.credit, closeTo(4.0, 0.0001));
    expect(rows.first.closing, closeTo(10.5, 0.0001));
  });

  test('supplier name-wise uses payments as debit and purchases as credit', () {
    final rows = buildPartyNameWise(
      customer: false,
      knownNames: ['Meena'],
      transactions: [
        {
          'transactionType': 'PURCHASE',
          'partyName': 'Meena',
          'totalPureWt': '8.250',
          'paymentMode': 'CASH',
          'cashToGold': '0',
          'date': '05-08-2026',
        },
      ],
      vouchers: const [],
      allHistory: true,
    );
    expect(rows.first.opening, 0);
    expect(rows.first.types, 'PURCHASE');
    expect(rows.first.debit, 0);
    expect(rows.first.credit, closeTo(8.25, 0.0001));
    expect(rows.first.closing, closeTo(-8.25, 0.0001));
  });

  test('ledger entry type and payment mode labels', () {
    expect(ledgerEntryType('SAL-12'), 'SALES');
    expect(ledgerEntryType('PUR-4'), 'PURCHASE');
    expect(ledgerEntryType('RECEIPT-3'), 'RECEIPT');
    expect(ledgerEntryType('PAYMENT-2'), 'PAYMENT');
    expect(paymentModeLabel('upi'), 'UPI');
    expect(paymentModeLabel(''), 'PAYMENT');
    expect(paymentModeLabel('GOLD'), 'GOLD');
  });

  test('daily totals accumulate sales and purchase credit automatically', () {
    final totals = const DailyTotals()
        .addSale(
          grams: 12.5,
          amount: 1000,
          unpaidGrams: 12.5,
          unpaidAmount: 1000,
        )
        .addPurchase(
          grams: 8.25,
          amount: 400,
          unpaidGrams: 8.25,
          unpaidAmount: 400,
        );
    expect(totals.salesBills, 1);
    expect(totals.purchaseBills, 1);
    expect(totals.salesCreditGrams, 12.5);
    expect(totals.purchaseCreditGrams, 8.25);
    expect(totals.salesAmount, 1000);
  });

  test('party ledger ALL names mode includes all history by default', () {
    final rows = buildPartyLedgerRecords(
      customer: true,
      transactions: [
        {
          'transactionType': 'SALES',
          'partyName': 'Ravi',
          'billNo': 1,
          'totalPureWt': '10.000',
          'totalValue': '151000',
          'date': '01-08-2026',
        },
      ],
      vouchers: const [],
      from: DateTime(2026, 8, 28),
      to: DateTime(2026, 8, 28),
      allHistory: true,
      goldRate: 15100,
    );
    expect(rows.length, 1);
    expect(rows.first.partyName, 'Ravi');
  });
}
