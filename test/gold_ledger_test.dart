import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gold_ledger.dart';

void main() {
  test('cash converts to gold at the given rate', () {
    expect(GoldLedger.cashToGold(75500, 15100), closeTo(5, 0.0001));
    expect(GoldLedger.goldToCash(50, 15100), closeTo(755000, 0.01));
  });

  test('unpaid 50g sale adds 50g to the customer gold balance', () {
    final result = settleLedger(
      oldGrams: 0,
      oldRupees: 0,
      billGrams: 50,
      billRupees: 755000,
      paymentMode: 'CASH',
      paymentAmount: 0,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.newGrams, closeTo(50, 0.0001));
    expect(result.cashToGoldGrams, 0);
  });

  test('cash receipt against a 50g balance converts rupees into gold', () {
    final result = settleLedger(
      oldGrams: 50,
      oldRupees: 755000,
      billGrams: 0,
      billRupees: 0,
      paymentMode: 'CASH',
      paymentAmount: 755000,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.cashToGoldGrams, closeTo(50, 0.0001));
    expect(result.newGrams, closeTo(0, 0.0001));
  });

  test('gold receipt voucher of 50g clears a 50g sales balance', () {
    final result = settleLedger(
      oldGrams: 50,
      oldRupees: 0,
      billGrams: 0,
      billRupees: 0,
      paymentMode: 'GOLD',
      paymentAmount: 50,
      ratePerGram: 15100,
      billSign: 1,
    );
    expect(result.newGrams, closeTo(0, 0.0001));
  });

  test('unpaid purchase credits the supplier (shop owes gold)', () {
    final result = settleLedger(
      oldGrams: 0,
      oldRupees: 0,
      billGrams: 50,
      billRupees: 755000,
      paymentMode: 'CASH',
      paymentAmount: 0,
      ratePerGram: 15100,
      billSign: -1,
    );
    expect(result.newGrams, closeTo(-50, 0.0001));
  });

  test('daily totals accumulate sales and purchase credit automatically', () {
    final totals = const DailyTotals()
        .addSale(
          grams: 50,
          amount: 1000,
          unpaidGrams: 50,
          unpaidAmount: 1000,
        )
        .addPurchase(
          grams: 20,
          amount: 400,
          unpaidGrams: 20,
          unpaidAmount: 400,
        );
    expect(totals.salesBills, 1);
    expect(totals.purchaseBills, 1);
    expect(totals.salesCreditGrams, 50);
    expect(totals.purchaseCreditGrams, 20);
    expect(totals.salesAmount, 1000);
  });
}
