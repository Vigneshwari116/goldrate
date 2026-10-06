import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/theme/responsive.dart';
import 'package:grate_app/widgets/stock_summary_card.dart';

StockLedgerSummary _emptySummary() {
  final weights = {for (final t in kStockWeightTypes) t: 0.0};
  return StockLedgerSummary(
    opening: weights,
    purchases: const [],
    sales: const [],
    purchaseTotals: weights,
    salesTotals: weights,
    closing: weights,
  );
}

void main() {

  test('compact breakpoint is 430px', () {
    expect(Responsive.compactBreakpoint, 430);
  });

  testWidgets('StockSummaryTable uses horizontal scroll when narrow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: StockSummaryTable(summary: _emptySummary()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

}
