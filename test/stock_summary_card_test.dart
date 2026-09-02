import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/stock_ledger.dart';
import 'package:grate_app/theme/app_theme.dart';
import 'package:grate_app/widgets/stock_summary_card.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('Stock summary card renders opening, movements, and closing',
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
          'transactionType': 'PURCHASE',
          'billNo': 2,
          'date': '10-01-2026',
          'partyName': 'xy',
          'items': [
            {'type': 'FWT', 'weight': 20, 'touch': 98, 'pureWt': 19.6},
          ],
        },
        {
          'transactionType': 'SALES',
          'billNo': 1,
          'date': '10-01-2026',
          'partyName': 'cd',
          'items': [
            {'type': 'GWT', 'weight': 12, 'touch': 50, 'pureWt': 6},
          ],
        },
        {
          'transactionType': 'SALES',
          'billNo': 2,
          'date': '10-01-2026',
          'partyName': 'ef',
          'items': [
            {'type': 'FWT', 'weight': 24, 'touch': 98, 'pureWt': 23.52},
          ],
        },
      ],
      openingWeight: {
        'gPureWt': '200',
        'fineWt': '201',
        'kachaWt': '202',
        'silverWt': '203',
      },
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 10),
      dateFormat: DateFormat('dd-MM-yyyy'),
    );

    await tester.binding.setSurfaceSize(const Size(1100, 420));
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: StockSummaryCard(summary: summary),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STOCK SUMMARY'), findsOneWidget);
    expect(find.text('Opening'), findsOneWidget);
    expect(find.text('Closing Stock'), findsOneWidget);
    expect(find.text('PURCHASE'), findsOneWidget);
    expect(find.text('ISSUE'), findsOneWidget);
    expect(find.text('200'), findsNWidgets(2)); // opening + closing GWT
    expect(find.text('201'), findsWidgets);
    expect(find.text('ab'), findsOneWidget);
    expect(find.text('PUR-1'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('24'), findsOneWidget);

    await expectLater(
      find.byType(StockSummaryCard),
      matchesGoldenFile('goldens/stock_summary_card.png'),
    );
  });
}
