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

  // Name | Bill no | date | Type | Receipt GWT..SWT | Issue GWT..SWT
  static const headers = [
    '',
    'Name',
    'Bill no',
    'date',
    'Type',
    'Receipt',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
    'Issue',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
  ];

  static const _labelCol = 0;
  static const _nameCol = 1;
  static const _billCol = 2;
  static const _dateCol = 3;
  static const _typeCol = 4;
  static const _receiptStart = 6;
  static const _issueStart = 11;

  /// Equal column width when horizontal scroll is required on narrow screens.
  static const scrollColumnWidth = 68.0;

  static const _cellPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 7);

  static double minScrollWidth() => scrollColumnWidth * headers.length;

  static List<String> _emptyRow() => List.filled(headers.length, '');

  static void _setWeights(
    List<String> row,
    int startCol,
    Map<String, double> weights,
  ) {
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      row[startCol + i] = formatStockWeight(
        weights[kStockWeightTypes[i]] ?? 0,
        blankWhenZero: false,
      );
    }
  }

  /// Opening stock — Issue GWT/FWT/KWT/SWT only.
  static List<String> openingRow(Map<String, double> weights) {
    final row = _emptyRow();
    row[_labelCol] = 'Opening';
    _setWeights(row, _issueStart, weights);
    return row;
  }

  /// Closing stock — same totals in Receipt and Issue weight columns.
  static List<String> closingRow(Map<String, double> weights) {
    final row = _emptyRow();
    row[_labelCol] = 'Closing Stock';
    _setWeights(row, _receiptStart, weights);
    _setWeights(row, _issueStart, weights);
    return row;
  }

  static List<String> transactionRow(StockLedgerRow txn) {
    final row = _emptyRow();
    row[_typeCol] = txn.label;
    row[_nameCol] = txn.name;
    row[_billCol] = txn.billNo;
    row[_dateCol] = txn.date;
    _setWeights(row, _receiptStart, txn.receiptWeights);
    _setWeights(row, _issueStart, txn.issueWeights);
    return row;
  }

  /// Data rows for PDF export (opening, transactions, closing).
  static List<List<String>> pdfRowsFor(StockLedgerSummary summary) => [
        openingRow(summary.opening),
        for (final txn in summary.rows) transactionRow(txn),
        closingRow(summary.closing),
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
      index >= _receiptStart && index <= _receiptStart + 3 ||
      index >= _issueStart && index <= _issueStart + 3;

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
          rowWidget(openingRow(summary.opening), band: true, bold: true),
          for (final txn in summary.rows) rowWidget(transactionRow(txn)),
          rowWidget(closingRow(summary.closing), band: true, bold: true),
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
