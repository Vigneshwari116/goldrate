/// Cash-to-gold conversion and running party balances.
///
/// Jewellery books keep customer/supplier dues in **grams**. Cash or UPI
/// paid against a gold bill is converted at today's rate:
/// `grams = cash / ratePerGram`.
class GoldLedger {
  GoldLedger._();

  static double cashToGold(double cash, double ratePerGram) {
    if (cash == 0 || ratePerGram <= 0) return 0;
    return cash / ratePerGram;
  }

  static double goldToCash(double grams, double ratePerGram) {
    if (grams == 0 || ratePerGram <= 0) return 0;
    return grams * ratePerGram;
  }

  static double rateForType(String itemType, Map<String, double> rates) {
    switch (itemType) {
      case 'FWT':
        return rates['F.T RATE'] ?? rates['G.P RATE'] ?? 0;
      case 'KWT':
        return rates['KACHA RATE'] ?? rates['G.P RATE'] ?? 0;
      case 'SWT':
        return rates['S RATE'] ?? 0;
      case 'GWT':
      default:
        return rates['G.P RATE'] ?? 0;
    }
  }

  /// Prefer G.P RATE for gold books; fall back to the first available rate.
  static double goldRate(Map<String, double> rates) {
    return rates['G.P RATE'] ??
        rates['F.T RATE'] ??
        rates['KACHA RATE'] ??
        rates['S RATE'] ??
        0;
  }
}

class SettlementResult {
  final double oldGrams;
  final double oldRupees;
  final double billGrams;
  final double billRupees;
  final String paymentMode;
  final double paymentAmount;
  final double ratePerGram;
  final double cashToGoldGrams;
  final double gramsPaid;
  final double rupeesPaid;
  final double newGrams;
  final double newRupees;

  const SettlementResult({
    required this.oldGrams,
    required this.oldRupees,
    required this.billGrams,
    required this.billRupees,
    required this.paymentMode,
    required this.paymentAmount,
    required this.ratePerGram,
    required this.cashToGoldGrams,
    required this.gramsPaid,
    required this.rupeesPaid,
    required this.newGrams,
    required this.newRupees,
  });

  bool get isGoldPayment => paymentMode.toUpperCase() == 'GOLD';

  String get paymentLabel {
    if (isGoldPayment) {
      return '${paymentAmount.toStringAsFixed(3)} g gold';
    }
    return '₹${paymentAmount.toStringAsFixed(2)}'
        '${cashToGoldGrams > 0 ? ' → ${cashToGoldGrams.toStringAsFixed(3)} g' : ''}';
  }
}

/// Settle a bill or receipt against a party's old gold + rupee balance.
///
/// [billSign] is +1 for a sale (party takes metal, owes more) and -1 for
/// a purchase (shop takes metal, shop owes more). Receipt vouchers use
/// billGrams/billRupees = 0 and only apply the payment.
SettlementResult settleLedger({
  required double oldGrams,
  required double oldRupees,
  required double billGrams,
  required double billRupees,
  required String paymentMode,
  required double paymentAmount,
  required double ratePerGram,
  int billSign = 1,
}) {
  final mode = paymentMode.toUpperCase();
  final isGold = mode == 'GOLD';
  final cashToGold =
      isGold ? 0.0 : GoldLedger.cashToGold(paymentAmount, ratePerGram);
  final gramsPaid = isGold ? paymentAmount : cashToGold;
  final rupeesPaid = isGold
      ? GoldLedger.goldToCash(paymentAmount, ratePerGram)
      : paymentAmount;

  final signedGrams = billSign * billGrams;
  final signedRupees = billSign * billRupees;

  return SettlementResult(
    oldGrams: oldGrams,
    oldRupees: oldRupees,
    billGrams: billGrams,
    billRupees: billRupees,
    paymentMode: mode,
    paymentAmount: paymentAmount,
    ratePerGram: ratePerGram,
    cashToGoldGrams: cashToGold,
    gramsPaid: gramsPaid,
    rupeesPaid: rupeesPaid,
    newGrams: oldGrams + signedGrams - (billSign * gramsPaid),
    newRupees: oldRupees + signedRupees - (billSign * rupeesPaid),
  );
}

class DailyTotals {
  final int salesBills;
  final int purchaseBills;
  final int receiptVouchers;
  final double salesGrams;
  final double salesAmount;
  final double salesCreditGrams;
  final double salesCreditAmount;
  final double purchaseGrams;
  final double purchaseAmount;
  final double purchaseCreditGrams;
  final double purchaseCreditAmount;
  final double receiptsCash;
  final double receiptsGold;

  const DailyTotals({
    this.salesBills = 0,
    this.purchaseBills = 0,
    this.receiptVouchers = 0,
    this.salesGrams = 0,
    this.salesAmount = 0,
    this.salesCreditGrams = 0,
    this.salesCreditAmount = 0,
    this.purchaseGrams = 0,
    this.purchaseAmount = 0,
    this.purchaseCreditGrams = 0,
    this.purchaseCreditAmount = 0,
    this.receiptsCash = 0,
    this.receiptsGold = 0,
  });

  DailyTotals addSale({
    required double grams,
    required double amount,
    required double unpaidGrams,
    required double unpaidAmount,
  }) {
    return DailyTotals(
      salesBills: salesBills + 1,
      purchaseBills: purchaseBills,
      receiptVouchers: receiptVouchers,
      salesGrams: salesGrams + grams,
      salesAmount: salesAmount + amount,
      salesCreditGrams: salesCreditGrams + unpaidGrams,
      salesCreditAmount: salesCreditAmount + unpaidAmount,
      purchaseGrams: purchaseGrams,
      purchaseAmount: purchaseAmount,
      purchaseCreditGrams: purchaseCreditGrams,
      purchaseCreditAmount: purchaseCreditAmount,
      receiptsCash: receiptsCash,
      receiptsGold: receiptsGold,
    );
  }

  DailyTotals addPurchase({
    required double grams,
    required double amount,
    required double unpaidGrams,
    required double unpaidAmount,
  }) {
    return DailyTotals(
      salesBills: salesBills,
      purchaseBills: purchaseBills + 1,
      receiptVouchers: receiptVouchers,
      salesGrams: salesGrams,
      salesAmount: salesAmount,
      salesCreditGrams: salesCreditGrams,
      salesCreditAmount: salesCreditAmount,
      purchaseGrams: purchaseGrams + grams,
      purchaseAmount: purchaseAmount + amount,
      purchaseCreditGrams: purchaseCreditGrams + unpaidGrams,
      purchaseCreditAmount: purchaseCreditAmount + unpaidAmount,
      receiptsCash: receiptsCash,
      receiptsGold: receiptsGold,
    );
  }

  DailyTotals addReceipt({required double cash, required double gold}) {
    return DailyTotals(
      salesBills: salesBills,
      purchaseBills: purchaseBills,
      receiptVouchers: receiptVouchers + 1,
      salesGrams: salesGrams,
      salesAmount: salesAmount,
      salesCreditGrams: salesCreditGrams,
      salesCreditAmount: salesCreditAmount,
      purchaseGrams: purchaseGrams,
      purchaseAmount: purchaseAmount,
      purchaseCreditGrams: purchaseCreditGrams,
      purchaseCreditAmount: purchaseCreditAmount,
      receiptsCash: receiptsCash + cash,
      receiptsGold: receiptsGold + gold,
    );
  }
}
