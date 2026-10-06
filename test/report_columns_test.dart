import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/report_columns.dart';
import 'package:grate_app/logic/stock_ledger.dart';

void main() {
  test('bill list headers include cash and eight weight columns', () {
    final headers = ReportColumns.billListLeafHeaders();
    expect(headers.length, 13);
    expect(headers[4], 'CASH (₹)');
    expect(headers.sublist(5, 9), kStockWeightTypes);
    expect(headers.sublist(9, 13), kStockWeightTypes);
  });

  test('ledger headers append narration column', () {
    final headers = ReportColumns.billListLeafHeaders(ledger: true);
    expect(headers.length, 14);
    expect(headers.last, 'NARRATION');
  });

  test('formatReportCash formats rupees with symbol', () {
    expect(formatReportCash(15000), '₹15,000');
    expect(formatReportCash(0), '');
    expect(formatReportCash(0, blankWhenZero: false), '0');
  });
}
