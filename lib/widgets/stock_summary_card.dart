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

  static const scrollColumnWidth = 72.0;
  static const _cellPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 7);

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
    final rows = <List<String>>[];
    rows.add([
      'Opening Stock',
      '',
      '',
      ...kStockWeightTypes.map(
        (t) => formatStockWeight(summary.opening[t] ?? 0, blankWhenZero: false),
      ),
    ]);
    rows.add(['', '', '', '', '', '', '']);
    rows.add(['PURCHASE', '', '', '', '', '', '']);
    rows.add(boxHeaders);
    for (final bill in summary.purchases) {
      rows.add(_pdfBillRow(bill));
    }
    rows.add(_pdfTotalRow('Purchase Total', summary.purchaseTotals));
    rows.add(['', '', '', '', '', '', '']);
    rows.add(['SALES', '', '', '', '', '', '']);
    rows.add(boxHeaders);
    for (final bill in summary.sales) {
      rows.add(_pdfBillRow(bill));
    }
    rows.add(_pdfTotalRow('Sales Total', summary.salesTotals));
    return rows;
  }

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = boxHeaders.length;
        final minWidth = scrollColumnWidth * columnCount;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minWidth * 2 + 24;
        final columnWidth = math.max(scrollColumnWidth, minWidth / columnCount);
        final boxWidth = columnWidth * columnCount;
        final sideBySide = available >= boxWidth * 2 + 24;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _openingBand(columnWidth),
              const SizedBox(height: 12),
              if (sideBySide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _billBox(
                        title: 'Purchase',
                        rows: summary.purchases,
                        totals: summary.purchaseTotals,
                        columnWidth: columnWidth,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _billBox(
                        title: 'Sales',
                        rows: summary.sales,
                        totals: summary.salesTotals,
                        columnWidth: columnWidth,
                      ),
                    ),
                  ],
                )
              else ...[
                _billBox(
                  title: 'Purchase',
                  rows: summary.purchases,
                  totals: summary.purchaseTotals,
                  columnWidth: columnWidth,
                ),
                const SizedBox(height: 16),
                _billBox(
                  title: 'Sales',
                  rows: summary.sales,
                  totals: summary.salesTotals,
                  columnWidth: columnWidth,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _openingBand(double columnWidth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 110,
            child: Text(
              'Opening Stock',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AppColors.navy,
              ),
            ),
          ),
          for (final type in kStockWeightTypes)
            Expanded(
              child: Text(
                '${type}: ${formatStockWeight(summary.opening[type] ?? 0, blankWhenZero: false)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _billBox({
    required String title,
    required List<DailySalesBillRow> rows,
    required Map<String, double> totals,
    required double columnWidth,
  }) {
    final tableWidth = columnWidth * boxHeaders.length;

    Widget cell({
      required String text,
      required bool header,
      required bool bold,
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
              fontSize: header ? 10 : 11,
              fontWeight: header || bold ? FontWeight.w700 : FontWeight.normal,
              color: header ? AppColors.mutedBlue : Colors.black87,
            ),
          ),
        ),
      );
    }

    Widget rowWidget(List<String> values, {bool header = false, bool bold = false}) {
      return Container(
        decoration: BoxDecoration(
          color: bold ? AppColors.headerBand : Colors.white,
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
                align: i >= 3 ? TextAlign.right : TextAlign.left,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        if (rows.isEmpty)
          rowWidget(['—', 'No bills', '', '', '', '', ''])
        else
          for (final bill in rows) rowWidget(billValues(bill)),
        rowWidget(totalValues(), bold: true),
      ],
    );

    return Scrollbar(
      thumbVisibility: tableWidth > 400,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: math.max(tableWidth, 280), child: table),
      ),
    );
  }
}
