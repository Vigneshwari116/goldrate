import 'dart:math' as math;

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

  /// Equal column width when horizontal scroll is required on narrow screens.
  static const scrollColumnWidth = 68.0;

  static const _cellPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 7);

  static double minScrollWidth() => scrollColumnWidth * headers.length;

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

  static bool _isWeightColumn(int index) =>
      index >= 2 && index <= 5 || index >= 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useScroll =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < minScrollWidth();

        Widget cell({
          required int index,
          required String text,
          required bool header,
          required bool band,
          required bool bold,
          double? width,
        }) {
          final child = Text(
            text,
            maxLines: header ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: _isWeightColumn(index) ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: header ? 10 : 11,
              fontWeight: header || bold ? FontWeight.w700 : FontWeight.normal,
              color: header
                  ? AppColors.mutedBlue
                  : (band ? AppColors.navy : Colors.black87),
            ),
          );

          final padded = Padding(padding: _cellPadding, child: child);
          if (width != null) {
            return SizedBox(width: width, child: padded);
          }
          return Expanded(child: padded);
        }

        Widget rowWidget(List<String> row,
            {bool header = false, bool band = false, bool bold = false}) {
          return Container(
            decoration: BoxDecoration(
              color: band ? AppColors.headerBand : Colors.white,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < headers.length; i++)
                  cell(
                    index: i,
                    text: i < row.length ? row[i] : '',
                    header: header,
                    band: band,
                    bold: bold,
                    width: useScroll ? scrollColumnWidth : null,
                  ),
              ],
            ),
          );
        }

        final rows = [
          rowWidget(headers, header: true),
          rowWidget(bookendRow('Opening', summary.opening),
              band: true, bold: true),
          for (final txn in summary.rows) rowWidget(transactionRow(txn)),
          rowWidget(bookendRow('Closing Stock', summary.closing),
              band: true, bold: true),
        ];

        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );

        if (useScroll) {
          final tableWidth = math.max(minScrollWidth(), constraints.maxWidth);
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: table,
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: table,
        );
      },
    );
  }
}
