import 'package:flutter/material.dart';

import '../logic/stock_ledger.dart';
import '../theme/app_theme.dart';

/// Opening / Purchase / Issue / Closing stock table for the Daily Sales Report.
class StockSummaryCard extends StatelessWidget {
  const StockSummaryCard({super.key, required this.summary});

  final StockLedgerSummary summary;

  static const _headers = [
    '',
    'purchase',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
    'Name',
    'Bill no',
    'date',
    'issue',
    'GWT',
    'FWT',
    'KWT',
    'SWT',
  ];

  static const _flex = [2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: AppColors.headerBand,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Text(
              'STOCK SUMMARY',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: AppColors.navy,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StockSummaryTable(
              summary: summary,
              headers: _headers,
              columnFlex: _flex,
            ),
          ),
        ],
      ),
    );
  }
}

class StockSummaryTable extends StatelessWidget {
  const StockSummaryTable({
    super.key,
    required this.summary,
    required this.headers,
    required this.columnFlex,
  });

  final StockLedgerSummary summary;
  final List<String> headers;
  final List<int> columnFlex;

  List<String> _emptyRow() => List.filled(headers.length, '');

  List<String> _weightRow(String label, Map<String, double> weights) {
    final row = _emptyRow();
    row[0] = label;
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      row[2 + i] = formatStockWeight(weights[kStockWeightTypes[i]] ?? 0);
    }
    return row;
  }

  List<String> _combinedRow(
    StockLedgerLine? purchase,
    StockLedgerLine? issue, {
    bool purchaseLabel = false,
    bool issueLabel = false,
  }) {
    final row = _emptyRow();
    if (purchaseLabel) row[1] = 'PURCHASE';
    if (issueLabel) row[9] = 'ISSUE';
    if (purchase != null) {
      for (var i = 0; i < kStockWeightTypes.length; i++) {
        final t = kStockWeightTypes[i];
        if (purchase.type == t) {
          row[2 + i] = formatStockWeight(purchase.weight);
        }
      }
      row[6] = purchase.name;
      row[7] = purchase.billNo;
      row[8] = purchase.date;
    }
    if (issue != null) {
      for (var i = 0; i < kStockWeightTypes.length; i++) {
        final t = kStockWeightTypes[i];
        if (issue.type == t) {
          row[10 + i] = formatStockWeight(issue.weight);
        }
      }
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final dataRows = <List<String>>[];
    final rowCount = summary.purchases.length > summary.issues.length
        ? summary.purchases.length
        : summary.issues.length;
    for (var i = 0; i < rowCount; i++) {
      dataRows.add(_combinedRow(
        i < summary.purchases.length ? summary.purchases[i] : null,
        i < summary.issues.length ? summary.issues[i] : null,
        purchaseLabel: i == 0,
        issueLabel: i == 0,
      ));
    }

    int flexFor(int i) => i < columnFlex.length ? columnFlex[i] : 2;

    Widget rowWidget(List<String> row,
        {bool header = false, bool band = false, bool bold = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: band ? AppColors.headerBand : Colors.white,
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < headers.length; i++)
              Expanded(
                flex: flexFor(i),
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
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        rowWidget(headers, header: true),
        rowWidget(_weightRow('Opening', summary.opening), band: true, bold: true),
        for (final row in dataRows) rowWidget(row),
        rowWidget(_weightRow('Closing Stock', summary.closing),
            band: true, bold: true),
      ],
    );
  }
}
