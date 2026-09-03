import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/theme/app_theme.dart';
import 'package:grate_app/widgets/stock_summary_card.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('Stock summary card renders merged opening, rows, and closing',
      (tester) async {
    final summary = buildStockLedgerSummary(
      transactions: [
        {
          'transactionType': 'PURCHASE',
          'billNo': 1,
          'date': '10-01-2026',
          'partyName': 'ab',
          'items': [
            {'type': 'GWT', 'weight': 12, 'touch': 50, 'pureWt': 6},
          ],
        },
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'date': '10-01-2026',
          'partyName': 'cd',
          'items': [
            {'type': 'GWT', 'weight': 20, 'touch': 50, 'pureWt': 10},
          ],
          'paymentItems': [
            {'type': 'GWT', 'weight': 30, 'touch': 50, 'pureWt': 15},
          ],
        },
        {
          'transactionType': 'PURCHASE',
          'billNo': 2,
          'date': '10-01-2026',
          'partyName': 'ra',
          'items': [
            {'type': 'GWT', 'weight': 20, 'touch': 50, 'pureWt': 10},
          ],
          'paymentItems': [
            {'type': 'FWT', 'weight': 40, 'touch': 98, 'pureWt': 39.2},
          ],
        },
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '300',
        'kachaWt': '400',
        'silverWt': '500',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: DateFormat('dd-MM-yyyy'),
    );

    await tester.binding.setSurfaceSize(const Size(1200, 480));
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SizedBox(
            height: 480,
            child: StockSummaryCard(summary: summary),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STOCK SUMMARY'), findsOneWidget);
    expect(find.text('Opening'), findsOneWidget);
    expect(find.text('Closing Stock'), findsOneWidget);
    expect(find.text('SAL1'), findsOneWidget);
    expect(find.text('PUR1'), findsOneWidget);
    expect(find.text('PUR2'), findsOneWidget);
    expect(find.text('ab'), findsOneWidget);
    expect(find.text('cd'), findsOneWidget);
    expect(find.text('ra'), findsOneWidget);
    expect(find.text('0.000'), findsWidgets);
    expect(find.text('20'), findsWidgets);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);

    await expectLater(
      find.byType(StockSummaryCard),
      matchesGoldenFile('goldens/stock_summary_card.png'),
    );
  });
}
