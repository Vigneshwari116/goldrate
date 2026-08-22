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
}
