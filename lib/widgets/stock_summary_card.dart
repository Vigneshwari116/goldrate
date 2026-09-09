import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/stock_ledger.dart';
import '../theme/app_theme.dart';

/// Daily Sales Report — opening stock, separate Purchase and Sales boxes.
class StockSummaryTable extends StatelessWidget {
  const StockSummaryTable({
    super.key,
    required this.summary,
  });

  final StockLedgerSummary summary;

  static const boxHeaders = [
    'Bill No',
    'Name',
    'Date',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
  ];

  static const _infoColCount = 3;
  static const scrollColumnWidth = 72.0;
  static const _cellPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 7);
  static const _boxGap = 16.0;

  static String closingSummaryText(Map<String, double> closing) {
    final parts = <String>[];
    for (final type in kStockWeightTypes) {
      parts.add(
        '$type: ${formatStockWeight(closing[type] ?? 0, blankWhenZero: false)}',
      );
    }
    return 'CLOSING: ${parts.join('  |  ')}';
  }

  /// Flat rows for PDF export.
  static List<List<String>> pdfRowsFor(StockLedgerSummary summary) {
    final openingRow = _openingRowValues(summary.opening);
    final closingRow = _closingRowValues(summary.closing);
    final rows = <List<String>>[];
    rows.add(['PURCHASE', '', '', '', '', '', '']);
    rows.add(boxHeaders);
    rows.add(openingRow);
    for (final bill in summary.purchases) {
      rows.add(_pdfBillRow(bill));
    }
    rows.add(_pdfTotalRow('Total', summary.purchaseTotals));
    rows.add(closingRow);
    rows.add(['', '', '', '', '', '', '']);
    rows.add(['SALES', '', '', '', '', '', '']);
    rows.add(boxHeaders);
    rows.add(openingRow);
    for (final bill in summary.sales) {
      rows.add(_pdfBillRow(bill));
    }
    rows.add(_pdfTotalRow('Total', summary.salesTotals));
    rows.add(closingRow);
    return rows;
  }

  static List<String> _openingRowValues(Map<String, double> opening) => [
        'Opening Stock',
        '',
        '',
        ...kStockWeightTypes.map(
          (t) => formatStockWeight(opening[t] ?? 0, blankWhenZero: false),
        ),
      ];

  static List<String> _pdfBillRow(DailySalesBillRow bill) => [
        bill.billLabel,
        bill.name,
        bill.date,
        ...kStockWeightTypes.map(
          (t) => formatStockWeight(bill.weights[t] ?? 0, blankWhenZero: false),
        ),
      ];

  static List<String> _pdfTotalRow(String label, Map<String, double> totals) => [
        label,
        '',
        '',
        ...kStockWeightTypes.map(
          (t) => formatStockWeight(totals[t] ?? 0, blankWhenZero: false),
        ),
      ];

  static List<String> _closingRowValues(Map<String, double> closing) => [
        'Closing Stock',
        '',
        '',
        ...kStockWeightTypes.map(
          (t) => formatStockWeight(closing[t] ?? 0, blankWhenZero: false),
        ),
      ];

  static bool _sideBySideLayout(double availableWidth) {
    final minBoxWidth = scrollColumnWidth * boxHeaders.length;
    return availableWidth >= minBoxWidth * 2 + _boxGap;
  }

  static double _columnWidthFor(double availableWidth) {
    return math.max(scrollColumnWidth, availableWidth / boxHeaders.length);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : scrollColumnWidth * boxHeaders.length * 2 + _boxGap;
        final sideBySide = _sideBySideLayout(available);

        Widget box(String title, List<DailySalesBillRow> rows, Map<String, double> totals) {
          return _billBox(
            title: title,
            rows: rows,
            totals: totals,
            opening: summary.opening,
            closing: summary.closing,
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: sideBySide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: box('Purchase', summary.purchases, summary.purchaseTotals)),
                    const SizedBox(width: _boxGap),
                    Expanded(child: box('Sales', summary.sales, summary.salesTotals)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    box('Purchase', summary.purchases, summary.purchaseTotals),
                    const SizedBox(height: _boxGap),
                    box('Sales', summary.sales, summary.salesTotals),
                  ],
                ),
        );
      },
    );
  }

  Widget _billBox({
    required String title,
    required List<DailySalesBillRow> rows,
    required Map<String, double> totals,
    required Map<String, double> opening,
    required Map<String, double> closing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : scrollColumnWidth * boxHeaders.length;
        final columnWidth = _columnWidthFor(availableWidth);
        final tableWidth = columnWidth * boxHeaders.length;
        return _billBoxTable(
          title: title,
          rows: rows,
          totals: totals,
          opening: opening,
          closing: closing,
          columnWidth: columnWidth,
          tableWidth: tableWidth,
        );
      },
    );
  }

  Widget _billBoxTable({
    required String title,
    required List<DailySalesBillRow> rows,
    required Map<String, double> totals,
    required Map<String, double> opening,
    required Map<String, double> closing,
    required double columnWidth,
    required double tableWidth,
  }) {

    Widget cell({
      required String text,
      required bool header,
      required bool bold,
      required bool openingRow,
      required bool summaryRow,
      TextAlign align = TextAlign.left,
    }) {
      return SizedBox(
        width: columnWidth,
        child: Padding(
          padding: _cellPadding,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              fontSize: summaryRow
                  ? 12.5
                  : header
                      ? 10
                      : 11,
              fontWeight: header || bold || summaryRow
                  ? FontWeight.w700
                  : FontWeight.normal,
              color: header
                  ? AppColors.mutedBlue
                  : openingRow
                      ? AppColors.navy
                      : Colors.black87,
            ),
          ),
        ),
      );
    }

    Widget rowWidget(
      List<String> values, {
      bool header = false,
      bool bold = false,
      bool openingRow = false,
      bool summaryRow = false,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: openingRow || bold || summaryRow
              ? AppColors.headerBand
              : Colors.white,
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < boxHeaders.length; i++)
              cell(
                text: i < values.length ? values[i] : '',
                header: header,
                bold: bold,
                openingRow: openingRow,
                summaryRow: summaryRow,
                align: i >= _infoColCount ? TextAlign.right : TextAlign.left,
              ),
          ],
        ),
      );
    }

    List<String> billValues(DailySalesBillRow bill) => [
          bill.billLabel,
          bill.name,
          bill.date,
          ...kStockWeightTypes.map(
            (t) => formatStockWeight(bill.weights[t] ?? 0, blankWhenZero: false),
          ),
        ];

    List<String> totalValues() => [
          'Total',
          '',
          '',
          ...kStockWeightTypes.map(
            (t) => formatStockWeight(totals[t] ?? 0, blankWhenZero: false),
          ),
        ];

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.navy,
              letterSpacing: 0.3,
            ),
          ),
        ),
        rowWidget(boxHeaders, header: true),
        rowWidget(_openingRowValues(opening), openingRow: true, bold: true),
        if (rows.isEmpty)
          rowWidget(['—', 'No bills', '', '', '', '', ''])
        else
          for (final bill in rows) rowWidget(billValues(bill)),
        rowWidget(totalValues(), summaryRow: true),
        rowWidget(_closingRowValues(closing), summaryRow: true),
      ],
    );

    return SizedBox(
      width: tableWidth,
      child: table,
    );
  }
}
