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

/// One row of a customer/supplier name-wise gold statement (grams).
class PartyNameWiseRow {
  final String name;
  final String types;
  final double opening;
  final double debit;
  final double credit;

  const PartyNameWiseRow({
    required this.name,
    required this.types,
    required this.opening,
    required this.debit,
    required this.credit,
  });

  double get closing => opening + debit - credit;

  List<String> toTableCells() => [
        name,
        types,
        opening.toStringAsFixed(3),
        debit.toStringAsFixed(3),
        credit.toStringAsFixed(3),
        closing.toStringAsFixed(3),
      ];
}

String ledgerEntryType(String billRef) {
  final r = billRef.toUpperCase();
  if (r.startsWith('SAL')) return 'SALES';
  if (r.startsWith('PUR')) return 'PURCHASE';
  if (r.contains('RECEIPT') || r.startsWith('RCPT')) return 'RECEIPT';
  if (r.contains('PAYMENT') || r.startsWith('PAY')) return 'PAYMENT';
  return '-';
}

String paymentModeLabel(String? raw) {
  final m = (raw ?? '').trim().toUpperCase();
  if (m == 'CASH' || m == 'UPI' || m == 'GOLD') return m;
  if (m.contains('UPI')) return 'UPI';
  if (m.contains('CASH')) return 'CASH';
  if (m.contains('GOLD')) return 'GOLD';
  if (m.isEmpty) return 'PAYMENT';
  return m;
}

DateTime? parseAppDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final p = raw.split(RegExp(r'[-/]'));
    if (p.length < 3) return null;
    return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
  } catch (_) {
    return null;
  }
}

/// Gold grams received as payment on a bill or voucher.
double goldPaidOnRow(Map<String, dynamic> row) {
  final mode = (row['paymentMode'] ?? '').toString().toUpperCase();
  if (mode == 'GOLD') {
    return double.tryParse(
            (row['paymentAmount'] ?? row['amount'] ?? '').toString()) ??
        0;
  }
  return double.tryParse((row['cashToGold'] ?? '').toString()) ?? 0;
}

class _NameWiseAcc {
  double opening = 0;
  double debit = 0;
  double credit = 0;
  final types = <String>{};
}

/// Customer: Debit (Sales), Credit (Payment).
/// Supplier: Debit (Payment), Credit (Purchase).
/// Closing = Opening + Debit − Credit, in grams.
List<PartyNameWiseRow> buildPartyNameWise({
  required bool customer,
  required Iterable<String> knownNames,
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> vouchers,
  DateTime? from,
  DateTime? to,
  bool allHistory = false,
}) {
  final acc = <String, _NameWiseAcc>{};
  void ensure(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    acc.putIfAbsent(n, () => _NameWiseAcc());
  }

  for (final n in knownNames) {
    ensure(n);
  }

  final fromDay = from == null
      ? null
      : DateTime(from.year, from.month, from.day);
  final toDay = to == null ? null : DateTime(to.year, to.month, to.day);

  void apply(
    String name,
    DateTime? date,
    double debit,
    double credit,
    String kind,
  ) {
    ensure(name);
    final a = acc[name.trim()];
    if (a == null) return;
    if (allHistory || fromDay == null || toDay == null) {
      a.debit += debit;
      a.credit += credit;
      if (debit > 0 || credit > 0) a.types.add(kind);
      return;
    }
    final day = date == null
        ? fromDay
        : DateTime(date.year, date.month, date.day);
    if (day.isBefore(fromDay)) {
      a.opening += debit - credit;
    } else if (!day.isAfter(toDay)) {
      a.debit += debit;
      a.credit += credit;
      if (debit > 0 || credit > 0) a.types.add(kind);
    }
  }

  for (final bill in transactions) {
    final type = (bill['transactionType'] ?? '').toString();
    final name = (bill['partyName'] ?? '').toString();
    final grams = double.tryParse((bill['totalPureWt'] ?? '').toString()) ?? 0;
    final paid = goldPaidOnRow(bill);
    final date = parseAppDate(bill['date']?.toString());
    if (customer && type == 'SALES') {
      apply(name, date, grams, paid, 'SALES');
    } else if (!customer && type == 'PURCHASE') {
      apply(name, date, paid, grams, 'PURCHASE');
    }
  }

  for (final v in vouchers) {
    final name = (v['partyName'] ?? '').toString();
    final flag = v['isCustomer'];
    final isCust = flag == 1 || flag == true || flag == '1'
        ? true
        : flag == 0 || flag == false || flag == '0'
            ? false
            : (v['voucherType'] ?? '').toString() == 'RECEIPT';
    if (customer != isCust) continue;
    final paid = goldPaidOnRow(v);
    final date = parseAppDate(v['date']?.toString());
    if (customer) {
      apply(name, date, 0, paid, 'RECEIPT');
    } else {
      apply(name, date, paid, 0, 'PAYMENT');
    }
  }

  final names = acc.keys.toList()..sort();
  return [
    for (final n in names)
      PartyNameWiseRow(
        name: n,
        types: acc[n]!.types.isEmpty ? '-' : acc[n]!.types.join(', '),
        opening: acc[n]!.opening,
        debit: acc[n]!.debit,
        credit: acc[n]!.credit,
      ),
  ];
}
