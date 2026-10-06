import 'gold_ledger.dart';

/// One summarized row per customer for the Customer Abstract report.
class CustomerAbstractRow {
  const CustomerAbstractRow({
    required this.customerName,
    required this.totalGross,
    required this.netPure,
    required this.cashRupees,
    required this.closingGrams,
  });

  final String customerName;
  final double totalGross;
  final double netPure;
  final double cashRupees;
  final double closingGrams;

  List<String> toCells() => [
        customerName,
        totalGross.toStringAsFixed(3),
        netPure.toStringAsFixed(3),
        _formatCash(cashRupees),
        signedLedgerBalance(closingGrams),
      ];
}

class CustomerAbstractTotals {
  const CustomerAbstractTotals({
    required this.totalGross,
    required this.netPure,
    required this.cashRupees,
    required this.closingGrams,
  });

  final double totalGross;
  final double netPure;
  final double cashRupees;
  final double closingGrams;

  List<String> toFooterCells() => [
        'TOTAL',
        totalGross.toStringAsFixed(3),
        netPure.toStringAsFixed(3),
        _formatCash(cashRupees),
        signedLedgerBalance(closingGrams),
      ];
}

String _formatCash(double value) {
  if (value.abs() < 0.005) return '0';
  return '₹${value.toStringAsFixed(2)}';
}

class CustomerAbstractReport {
  CustomerAbstractReport._();

  static const headers = [
    'Customer Name',
    'Total Wt (Gross)',
    'Net Wt (Pure)',
    'Cash (₹)',
    'Closing Balance',
  ];

  static List<CustomerAbstractRow> build({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> vouchers,
    required List<Map<String, dynamic>> masterRows,
    required DateTime? from,
    required DateTime? to,
    required bool allHistory,
    required String nameQuery,
    required double goldRate,
  }) {
    final sections = buildPartyLedgerSections(
      customer: true,
      transactions: transactions,
      vouchers: vouchers,
      masterRows: masterRows,
      from: from,
      to: to,
      allHistory: allHistory,
      nameQuery: nameQuery,
      goldRate: goldRate,
    );

    return [
      for (final section in sections)
        CustomerAbstractRow(
          customerName: section.partyName,
          totalGross: section.totalIssue,
          netPure: section.rows.fold<double>(
            0,
            (sum, row) => sum + row.pureGold,
          ),
          cashRupees: section.totalCash,
          closingGrams: section.closingBalance,
        ),
    ];
  }

  static CustomerAbstractTotals totalsFor(List<CustomerAbstractRow> rows) {
    var gross = 0.0;
    var pure = 0.0;
    var cash = 0.0;
    var closing = 0.0;
    for (final row in rows) {
      gross += row.totalGross;
      pure += row.netPure;
      cash += row.cashRupees;
      closing += row.closingGrams;
    }
    return CustomerAbstractTotals(
      totalGross: gross,
      netPure: pure,
      cashRupees: cash,
      closingGrams: closing,
    );
  }
}
