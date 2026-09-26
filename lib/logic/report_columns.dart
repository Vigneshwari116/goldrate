import 'stock_ledger.dart';

/// Shared column layout for Sales/Purchase/Ledger bill-list reports.
class ReportColumns {
  ReportColumns._();

  static const billInfoHeaders = [
    'BILL NO',
    'DATE',
    'NAME',
    'MODE',
    'CASH (₹)',
  ];

  static const ledgerInfoHeaders = [
    'BILL NO',
    'DATE',
    'NAME',
    'TYPE',
    'CASH (₹)',
  ];

  static const billColumnFlex = [2, 2, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1];

  static const ledgerColumnFlex = [2, 2, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 3];

  static List<String> billListHeaders({bool ledger = false}) => [
        ...(ledger ? ledgerInfoHeaders : billInfoHeaders),
        ...kStockWeightTypes,
        ...kStockWeightTypes,
        if (ledger) 'NARRATION',
      ];

  /// Top header row — parent labels spanning weight groups.
  static List<String> billListGroupHeaders({bool ledger = false}) => [
        ...(ledger ? ledgerInfoHeaders : billInfoHeaders),
        'R.WEIGHT',
        '',
        '',
        '',
        'ISSUE WT',
        '',
        '',
        '',
        if (ledger) '',
      ];

  /// Bottom header row — leaf column labels.
  static List<String> billListLeafHeaders({bool ledger = false}) => [
        ...(ledger ? ledgerInfoHeaders : billInfoHeaders),
        ...kStockWeightTypes,
        ...kStockWeightTypes,
        if (ledger) 'NARRATION',
      ];

  static List<List<String>> billListPdfHeaderRows({bool ledger = false}) => [
        billListGroupHeaders(ledger: ledger),
        billListLeafHeaders(ledger: ledger),
      ];

  static List<String> billRowCells({
    required List<String> infoCells,
    required Map<String, double> receiptWeights,
    required Map<String, double> issueWeights,
    String? narration,
    bool blankWhenZero = true,
  }) {
    return [
      ...infoCells,
      ...formatReceiptIssueWeightCells(
        receiptWeights,
        issueWeights,
        blankWhenZero: blankWhenZero,
      ),
      if (narration != null) narration,
    ];
  }

  static List<String> billFooterCells({
    required String label,
    required int labelColumnIndex,
    required int columnCount,
    required double totalCash,
    required Map<String, double> totalReceiptWeights,
    required Map<String, double> totalIssueWeights,
    String? trailing,
  }) {
    final row = List<String>.filled(columnCount, '');
    row[labelColumnIndex] = label;
    row[4] = formatReportCash(totalCash, blankWhenZero: false);
    final weights = formatReceiptIssueWeightCells(
      totalReceiptWeights,
      totalIssueWeights,
      blankWhenZero: false,
    );
    for (var i = 0; i < weights.length; i++) {
      row[5 + i] = weights[i];
    }
    if (trailing != null && columnCount > 12) {
      row[columnCount - 1] = trailing;
    }
    return row;
  }
}

String formatReportCash(double rupees, {bool blankWhenZero = true}) {
  if (rupees.abs() < 0.005) {
    return blankWhenZero ? '' : '0';
  }
  final rounded = rupees.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '₹$text';
}
