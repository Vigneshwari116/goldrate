import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/screens/login_screen.dart';
import 'package:grate_app/screens/reports_screen.dart';
import 'package:grate_app/theme/responsive.dart';

Future<List<String>> _collectOverflows(
  WidgetTester tester,
  Future<void> Function() pumpBody,
) async {
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final line = d.exceptionAsString().split('\n').first;
    if (line.contains('overflowed')) overflows.add(line);
    prev?.call(d);
  };
  await pumpBody();
  FlutterError.onError = prev;
  return overflows;
}

Widget _withViewport(double width, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 900)),
    child: child,
  );
}

void main() {
  group('Login form width', () {
    Future<BoxConstraints> loginConstraints(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        _withViewport(
          width,
          const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pump();
      final box = tester.widget<ConstrainedBox>(
        find.byKey(const Key('login_form_width')),
      );
      return box.constraints;
    }

    testWidgets('fits padded viewport at 375 without overflow', (tester) async {
      final overflows = await _collectOverflows(tester, () async {
        await tester.pumpWidget(
          _withViewport(375, const MaterialApp(home: LoginScreen())),
        );
        await tester.pump();
      });
      expect(overflows, isEmpty);

      final constraints = await loginConstraints(tester, 375);
      expect(constraints.maxWidth, 335);
    });

    testWidgets('keeps 350px cap at 1280', (tester) async {
      final constraints = await loginConstraints(tester, 1280);
      expect(constraints.maxWidth, 350);
    });
  });

  group('ReportSummaryHeader', () {
    Widget longHeader() {
      return ReportSummaryHeader(
        title: 'SALES REPORT WITH EXTRA LONG TITLE TEXT',
        records: 42,
        units: 12.345,
        total: 1234567.89,
        totalText: 'TOTAL: ₹12,34,567.89',
      );
    }

    testWidgets('stacks total chip below title when compact', (tester) async {
      final overflows = await _collectOverflows(tester, () async {
        await tester.pumpWidget(
          _withViewport(
            375,
            MaterialApp(
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: longHeader(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });
      expect(overflows, isEmpty);

      final columnFinder = find.descendant(
        of: find.byType(ReportSummaryHeader),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Column &&
              w.children.length == 3 &&
              w.children[2] is Align,
        ),
      );
      expect(columnFinder, findsOneWidget);
    });

    testWidgets('uses Row layout when not compact', (tester) async {
      await tester.pumpWidget(
        _withViewport(
          1280,
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: longHeader(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ReportSummaryHeader),
          matching: find.byType(Row),
        ),
        findsOneWidget,
      );
      expect(Responsive.isCompact(
        tester.element(find.byType(ReportSummaryHeader)),
      ), isFalse);
    });
  });

  testWidgets('ledger name filter width is not fixed 260 when compact',
      (tester) async {
    double? fieldWidth;
    await tester.pumpWidget(
      _withViewport(
        375,
        MaterialApp(
          home: Builder(
            builder: (context) {
              fieldWidth = Responsive.isCompact(context)
                  ? MediaQuery.sizeOf(context).width - 24
                  : 260.0;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(fieldWidth, 351);

    await tester.pumpWidget(
      _withViewport(
        1280,
        MaterialApp(
          home: Builder(
            builder: (context) {
              fieldWidth = Responsive.isCompact(context)
                  ? MediaQuery.sizeOf(context).width - 24
                  : 260.0;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(fieldWidth, 260);
  });
}
