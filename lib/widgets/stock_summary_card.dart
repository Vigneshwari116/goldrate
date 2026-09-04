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

  static const columnCount = 13;

  static const _labelCol = 0;
  static const _nameCol = 1;
  static const _billCol = 2;
  static const _dateCol = 3;
  static const _typeCol = 4;
  static const _receiptStart = 5;
  static const _issueStart = 9;
  static const _infoColCount = 5;
  static const _weightColCount = 4;

  /// Flat header row for PDF export.
  static const headers = [
    '',
    'Name',
    'Bill no',
    'date',
    'Type',
    'Rcpt GWT',
    'Rcpt FWT',
    'Rcpt KWT',
    'Rcpt SWT',
    'Issue GWT',
    'Issue FWT',
    'Issue KWT',
    'Issue SWT',
  ];

  /// Equal column width when horizontal scroll is required on narrow screens.
  static const scrollColumnWidth = 68.0;

  static const _cellPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 7);

  static double minScrollWidth() => scrollColumnWidth * columnCount;

  static List<String> _emptyRow() => List.filled(columnCount, '');

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

  /// Opening stock — same baseline in Receipt and Issue weight columns.
  static List<String> openingRow(Map<String, double> weights) {
    final row = _emptyRow();
    row[_labelCol] = 'Opening';
    _setWeights(row, _receiptStart, weights);
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
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minScrollWidth();
        final columnWidth = math.max(
          scrollColumnWidth,
          availableWidth / columnCount,
        );
        final tableWidth = columnWidth * columnCount;
        final needsHorizontalScroll = tableWidth > availableWidth + 0.5;

        TextStyle cellStyle({
          required bool header,
          required bool band,
          required bool bold,
        }) {
          return TextStyle(
            fontSize: header ? 10 : 11,
            fontWeight: header || bold ? FontWeight.w700 : FontWeight.normal,
            color: header
                ? AppColors.mutedBlue
                : (band ? AppColors.navy : Colors.black87),
          );
        }

        Widget sizedCell({
          required double width,
          required Widget child,
        }) {
          return SizedBox(width: width, child: child);
        }

        Widget textCell({
          required int index,
          required String text,
          required bool header,
          required bool band,
          required bool bold,
          TextAlign textAlign = TextAlign.left,
        }) {
          return sizedCell(
            width: columnWidth,
            child: Padding(
              padding: _cellPadding,
              child: Text(
                text,
                maxLines: header ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: cellStyle(header: header, band: band, bold: bold),
              ),
            ),
          );
        }

        Widget groupHeaderCell({
          required String text,
          required int span,
        }) {
          return sizedCell(
            width: columnWidth * span,
            child: Padding(
              padding: _cellPadding,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: cellStyle(header: true, band: false, bold: true),
              ),
            ),
          );
        }

        Widget headerWidget() {
          const infoLabels = ['', 'Name', 'Bill no', 'date', 'Type'];
          const weightLabels = ['GWT', 'FWT', 'KWT', 'SWT'];

          Widget headerBand({required List<Widget> children}) {
            return Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            );
          }

          return Column(
            children: [
              headerBand(
                children: [
                  for (final label in infoLabels)
                    textCell(
                      index: infoLabels.indexOf(label),
                      text: label,
                      header: true,
                      band: false,
                      bold: true,
                    ),
                  groupHeaderCell(text: 'Receipt', span: _weightColCount),
                  groupHeaderCell(text: 'Issue', span: _weightColCount),
                ],
              ),
              headerBand(
                children: [
                  for (var i = 0; i < _infoColCount; i++)
                    sizedCell(width: columnWidth, child: const SizedBox.shrink()),
                  for (final label in weightLabels)
                    textCell(
                      index: _receiptStart + weightLabels.indexOf(label),
                      text: label,
                      header: true,
                      band: false,
                      bold: true,
                      textAlign: TextAlign.right,
                    ),
                  for (final label in weightLabels)
                    textCell(
                      index: _issueStart + weightLabels.indexOf(label),
                      text: label,
                      header: true,
                      band: false,
                      bold: true,
                      textAlign: TextAlign.right,
                    ),
                ],
              ),
            ],
          );
        }

        Widget dataRowWidget(
          List<String> row, {
          bool band = false,
          bool bold = false,
        }) {
          return Container(
            decoration: BoxDecoration(
              color: band ? AppColors.headerBand : Colors.white,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columnCount; i++)
                  textCell(
                    index: i,
                    text: i < row.length ? row[i] : '',
                    header: false,
                    band: band,
                    bold: bold,
                    textAlign:
                        _isWeightColumn(i) ? TextAlign.right : TextAlign.left,
                  ),
              ],
            ),
          );
        }

        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerWidget(),
            dataRowWidget(openingRow(summary.opening), band: true, bold: true),
            for (final txn in summary.rows)
              dataRowWidget(transactionRow(txn)),
            dataRowWidget(closingRow(summary.closing), band: true, bold: true),
          ],
        );

        final sizedTable = SizedBox(
          width: tableWidth,
          child: table,
        );

        if (needsHorizontalScroll) {
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: sizedTable,
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: sizedTable,
        );
      },
    );
  }
}
