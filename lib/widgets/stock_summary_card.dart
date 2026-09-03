import 'package:flutter/material.dart';

import '../logic/stock_ledger.dart';
import '../theme/app_theme.dart';

/// Merged Opening / transaction / Closing stock table for the Daily Sales Report.
class StockSummaryTable extends StatelessWidget {
  const StockSummaryTable({
    super.key,
    required this.summary,
  });

  final StockLedgerSummary summary;

  static const headers = [
    'Issue',
    'Type',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
    'Name',
    'Bill no',
    'date',
    'Receipt',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
  ];

  /// Minimum pixel width per column so headers never squash together.
  static const minWidths = [
    56.0,
    52.0,
    44.0,
    44.0,
    44.0,
    44.0,
    96.0,
    56.0,
    76.0,
    56.0,
    44.0,
    44.0,
    44.0,
    44.0,
  ];

  static double get contentWidth =>
      minWidths.fold<double>(0, (sum, w) => sum + w) + 12;

  static double widthFor(int i) => i < minWidths.length ? minWidths[i] : 48.0;

  static List<String> _emptyRow() => List.filled(headers.length, '');

  static List<String> bookendRow(String label, Map<String, double> weights) {
    final row = _emptyRow();
    row[0] = label;
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      final value = formatStockWeight(weights[kStockWeightTypes[i]] ?? 0);
      row[2 + i] = value;
      row[10 + i] = value;
    }
    return row;
  }

  static List<String> transactionRow(StockLedgerRow txn) {
    final row = _emptyRow();
    row[1] = txn.label;
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      final type = kStockWeightTypes[i];
      row[2 + i] =
          formatStockWeight(txn.issueWeights[type] ?? 0, blankWhenZero: false);
      row[10 + i] = formatStockWeight(txn.receiptWeights[type] ?? 0,
          blankWhenZero: false);
    }
    row[6] = txn.name;
    row[7] = txn.billNo;
    row[8] = txn.date;
    return row;
  }

  /// Data rows for PDF export (opening, transactions, closing).
  static List<List<String>> pdfRowsFor(StockLedgerSummary summary) => [
        bookendRow('Opening', summary.opening),
        for (final txn in summary.rows) transactionRow(txn),
        bookendRow('Closing Stock', summary.closing),
      ];

  static String closingSummaryText(Map<String, double> closing) {
    final parts = <String>[];
    for (final type in kStockWeightTypes) {
      final value = closing[type] ?? 0;
      if (value != 0) {
        parts.add('$type: ${formatStockWeight(value, blankWhenZero: false)}');
      }
    }
    if (parts.isEmpty) return 'CLOSING: 0.000 g';
    return 'CLOSING: ${parts.join('  |  ')}';
  }

  @override
  Widget build(BuildContext context) {
    Widget rowWidget(List<String> row,
        {bool header = false, bool band = false, bool bold = false}) {
      return SizedBox(
        width: contentWidth,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: band ? AppColors.headerBand : Colors.white,
            border: const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < headers.length; i++)
                SizedBox(
                  width: widthFor(i),
                  child: Text(
                    i < row.length ? row[i] : '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: i >= 2 && i <= 5 || i >= 10
                        ? TextAlign.right
                        : TextAlign.left,
                    style: TextStyle(
                      fontSize: header ? 10 : 11,
                      fontWeight:
                          header || bold ? FontWeight.w700 : FontWeight.normal,
                      color: header
                          ? AppColors.mutedBlue
                          : (band ? AppColors.navy : Colors.black87),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final rows = [
      rowWidget(headers, header: true),
      rowWidget(bookendRow('Opening', summary.opening), band: true, bold: true),
      for (final txn in summary.rows) rowWidget(transactionRow(txn)),
      rowWidget(bookendRow('Closing Stock', summary.closing),
          band: true, bold: true),
    ];

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
    );
  }
}
