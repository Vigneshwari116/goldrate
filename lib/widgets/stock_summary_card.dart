import 'package:flutter/material.dart';

import '../logic/stock_ledger.dart';
import '../theme/app_theme.dart';

/// Merged Opening / transaction / Closing stock table for the Daily Sales Report.
class StockSummaryCard extends StatelessWidget {
  const StockSummaryCard({super.key, required this.summary});

  final StockLedgerSummary summary;

  static const _headers = [
    'Issue',
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

  static const _flex = [2, 2, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2];

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

  List<String> _bookendRow(String label, Map<String, double> weights) {
    final row = _emptyRow();
    row[0] = label;
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      final value = formatStockWeight(weights[kStockWeightTypes[i]] ?? 0);
      row[1 + i] = value;
      row[9 + i] = value;
    }
    return row;
  }

  List<String> _transactionRow(StockLedgerRow txn) {
    final row = _emptyRow();
    row[0] = txn.label;
    for (var i = 0; i < kStockWeightTypes.length; i++) {
      final type = kStockWeightTypes[i];
      row[1 + i] =
          formatStockWeight(txn.issueWeights[type] ?? 0, blankWhenZero: false);
      row[9 + i] = formatStockWeight(txn.receiptWeights[type] ?? 0,
          blankWhenZero: false);
    }
    row[5] = txn.name;
    row[6] = txn.billNo;
    row[7] = txn.date;
    return row;
  }

  @override
  Widget build(BuildContext context) {
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
                  textAlign: i >= 1 && i <= 4 || i >= 9
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
        rowWidget(_bookendRow('Opening', summary.opening),
            band: true, bold: true),
        for (final txn in summary.rows) rowWidget(_transactionRow(txn)),
        rowWidget(_bookendRow('Closing Stock', summary.closing),
            band: true, bold: true),
      ],
    );
  }
}
