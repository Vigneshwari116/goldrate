import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/gst_sales_ledger.dart';
import 'package:grate_app/screens/gst_sales_ledger_screen.dart';
import 'package:grate_app/screens/transaction_screen.dart';
import 'package:grate_app/theme/responsive.dart';

Future<List<String>> _overflowsDuring(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final hits = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final line = d.exceptionAsString().split('\n').first;
    if (line.contains('overflowed')) hits.add(line);
    prev?.call(d);
  };
  await action();
  FlutterError.onError = prev;
  return hits;
}

Widget _viewport(double width, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 900)),
    child: child,
  );
}

GstSalesLedgerRow _sampleRow() {
  return GstSalesLedgerRow(
    billNo: 7,
    billDate: '25-09-2026',
    customerName: 'Sample Customer With A Long Name',
    gstin: '29ABCDE1234F1Z5',
    grossWeight: 10.5,
    netWeight: 10.25,
    totalWeight: 10.5,
    rate: 6500,
    taxableValue: 66625,
    cgst: 999.38,
    sgst: 999.38,
    igst: 0,
    grandTotal: 68623.76,
  );
}

void main() {
  group('TransactionBillHeader', () {
    testWidgets('stacks date under bill number when compact', (tester) async {
      final overflows = await _overflowsDuring(tester, () async {
        await tester.pumpWidget(
          _viewport(
            375,
            const MaterialApp(
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TransactionBillHeader(
                    numberLabel: 'BILL NO',
                    billNumber: '42',
                    dateTimeText: '25-09-2026  02:30 PM',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });
      expect(overflows, isEmpty);
      expect(
        find.descendant(
          of: find.byType(TransactionBillHeader),
          matching: find.byType(Column),
        ),
        findsOneWidget,
      );
    });

    testWidgets('uses Row when not compact', (tester) async {
      await tester.pumpWidget(
        _viewport(
          1280,
          const MaterialApp(
            home: Scaffold(
              body: TransactionBillHeader(
                numberLabel: 'BILL NO',
                billNumber: '42',
                dateTimeText: '25-09-2026  02:30 PM',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(TransactionBillHeader),
          matching: find.byType(Row),
        ),
        findsOneWidget,
      );
    });
  });

  group('GstSalesLedgerCompactList', () {
    testWidgets('shows expandable cards instead of wide table', (tester) async {
      final overflows = await _overflowsDuring(tester, () async {
        await tester.pumpWidget(
          _viewport(
            375,
            MaterialApp(
              home: Scaffold(
                body: GstSalesLedgerCompactList(rows: [_sampleRow()]),
              ),
            ),
          ),
        );
        await tester.pump();
      });
      expect(overflows, isEmpty);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('Bill #7'), findsOneWidget);
      expect(find.textContaining('Grand Total'), findsOneWidget);
    });

    testWidgets('does not use horizontal scroll view', (tester) async {
      await tester.pumpWidget(
        _viewport(
          375,
          MaterialApp(
            home: Scaffold(
              body: GstSalesLedgerCompactList(rows: [_sampleRow()]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
    });
  });

  testWidgets('party name field drops 248px cap when compact', (tester) async {
    Widget partyWrapper(BuildContext context) {
      const inner = SizedBox(key: Key('party_inner'), height: 1);
      if (Responsive.isCompact(context)) {
        return const KeyedSubtree(key: Key('party_name_field'), child: inner);
      }
      return const KeyedSubtree(
        key: Key('party_name_field'),
        child: SizedBox(width: 248, child: inner),
      );
    }

    await tester.pumpWidget(
      _viewport(375, MaterialApp(home: Builder(builder: partyWrapper))),
    );
    final compactBox = tester.widget<SizedBox>(find.byKey(const Key('party_inner')));
    expect(compactBox.width, isNull);

    await tester.pumpWidget(
      _viewport(1280, MaterialApp(home: Builder(builder: partyWrapper))),
    );
    final wideBox = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byKey(const Key('party_inner')),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 248,
        ),
      ),
    );
    expect(wideBox.width, 248);
  });
}
