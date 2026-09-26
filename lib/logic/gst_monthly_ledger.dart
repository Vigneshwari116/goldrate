import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_date.dart';
import 'gst_sales_ledger.dart';
import 'transaction_records.dart';

/// Monthly GST position (output sales tax vs input purchase tax).
class GstMonthlyLedgerRow {
  GstMonthlyLedgerRow({
    required this.year,
    required this.month,
    required this.openingBalance,
    required this.totalPurchaseAmount,
    required this.purchaseGst,
    required this.totalSalesAmount,
    required this.salesGst,
    required this.closingBalance,
  });

  final int year;
  final int month;
  final double openingBalance;
  final double totalPurchaseAmount;
  final double purchaseGst;
  final double totalSalesAmount;
  final double salesGst;
  final double closingBalance;

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _monthFmt = DateFormat('MMMM yyyy');

  String get monthLabel => _monthFmt.format(DateTime(year, month));

  double get netGst => salesGst - purchaseGst;

  String get closingLabel {
    if (closingBalance > 0.005) {
      return 'GST Payable: ₹${_inr.format(closingBalance)}';
    }
    if (closingBalance < -0.005) {
      return 'Input Credit Carried Forward: ₹${_inr.format(-closingBalance)}';
    }
    return 'No GST payable / no credit';
  }

  List<String> toCells() => [
        monthLabel,
        _inr.format(openingBalance),
        _inr.format(totalPurchaseAmount),
        _inr.format(purchaseGst),
        _inr.format(totalSalesAmount),
        _inr.format(salesGst),
        _inr.format(closingBalance),
      ];
}

class GstMonthlyLedgerReport {
  GstMonthlyLedgerReport._();

  static const headers = [
    'Month',
    'Opening Balance',
    'Total Purchase Amount',
    'Purchase GST',
    'Total Sales Amount',
    'Sales GST',
    'Closing Balance',
  ];

  static const _seedKey = 'gst_monthly_ledger_seed_opening';

  static Future<double> loadSeedOpening() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_seedKey) ?? 0;
  }

  static Future<void> saveSeedOpening(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_seedKey, value);
  }

  static GstMonthlyLedgerRow forMonth({
    required List<Map<String, dynamic>> transactions,
    required int year,
    required int month,
    required double seedOpening,
  }) {
    final opening = _openingBeforeMonth(
      transactions: transactions,
      year: year,
      month: month,
      seedOpening: seedOpening,
    );
    final purchase = _aggregateMonth(transactions, year, month, 'PURCHASE');
    final sales = _aggregateMonth(transactions, year, month, 'SALES');
    final closing = opening + sales.gst - purchase.gst;
    return GstMonthlyLedgerRow(
      year: year,
      month: month,
      openingBalance: opening,
      totalPurchaseAmount: purchase.taxable,
      purchaseGst: purchase.gst,
      totalSalesAmount: sales.taxable,
      salesGst: sales.gst,
      closingBalance: closing,
    );
  }

  static double _openingBeforeMonth({
    required List<Map<String, dynamic>> transactions,
    required int year,
    required int month,
    required double seedOpening,
  }) {
    final months = _monthsWithGstActivity(transactions);
    if (months.isEmpty) return seedOpening;

    final target = DateTime(year, month);
    double opening = seedOpening;
    for (final m in months) {
      if (!m.isBefore(target)) break;
      final purchase = _aggregateMonth(transactions, m.year, m.month, 'PURCHASE');
      final sales = _aggregateMonth(transactions, m.year, m.month, 'SALES');
      opening = opening + sales.gst - purchase.gst;
    }
    return opening;
  }

  static List<DateTime> _monthsWithGstActivity(
    List<Map<String, dynamic>> transactions,
  ) {
    final set = <String>{};
    for (final row in transactions) {
      final type = normalizeTransactionType(
        (row['transactionType'] ?? '').toString(),
      );
      if (type != 'SALES' && type != 'PURCHASE') continue;
      final d = parseAppDate(row['date']?.toString());
      if (d == null) continue;
      set.add('${d.year}-${d.month}');
    }
    final list = set.map((key) {
      final parts = key.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]));
    }).toList();
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  static ({double taxable, double gst}) _aggregateMonth(
    List<Map<String, dynamic>> transactions,
    int year,
    int month,
    String transactionType,
  ) {
    double taxable = 0;
    double gst = 0;
    for (final row in transactions) {
      final type = normalizeTransactionType(
        (row['transactionType'] ?? '').toString(),
      );
      if (type != transactionType) continue;
      final d = parseAppDate(row['date']?.toString());
      if (d == null || d.year != year || d.month != month) continue;
      final breakdown = GstSalesLedgerReport.taxBreakdownForBill(row);
      taxable += breakdown.taxable;
      gst += breakdown.cgst + breakdown.sgst + breakdown.igst;
    }
    return (taxable: taxable, gst: gst);
  }

  static bool needsSeedEntry(List<Map<String, dynamic>> transactions) {
    final months = _monthsWithGstActivity(transactions);
    return months.isEmpty;
  }
}
