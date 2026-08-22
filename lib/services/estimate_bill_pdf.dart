import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/number_format.dart';

/// Paper estimate uses 99.90 as the standard fine touch.
const double kEstimateFineTouch = 99.90;

class EstimateLine {
  final int sno;
  final String token;
  final double weight;
  final double touch;
  final double pureWt;

  EstimateLine({
    required this.sno,
    this.token = '',
    required this.weight,
    required this.touch,
    required this.pureWt,
  });
}

Future<Uint8List> buildEstimateBillPdf({
  required String billNo,
  required String date,
  required String time,
  required String name,
  required String phone,
  required List<EstimateLine> lines,
  required String closingBalance,
}) async {
  final totalWt = lines.fold<double>(0, (s, l) => s + l.weight);
  final totalPure = lines.fold<double>(0, (s, l) => s + l.pureWt);
  final atFine = kEstimateFineTouch <= 0
      ? 0.0
      : totalPure / (kEstimateFineTouch / 100);
  final restatedPure = atFine * (kEstimateFineTouch / 100);

  final doc = pw.Document();
  final ink = PdfColors.blue800;
  final inkDark = PdfColors.blue900;
  final border = pw.Border.all(color: PdfColors.blue700, width: 0.8);
  final headerStyle = pw.TextStyle(
    fontSize: 8,
    fontWeight: pw.FontWeight.bold,
    color: ink,
  );
  final cellStyle = pw.TextStyle(fontSize: 8, color: ink);
  final bold = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: inkDark,
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(14),
      build: (context) => pw.Container(
        decoration: pw.BoxDecoration(border: border),
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'ESTIMATE ONLY',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: inkDark,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    '|| SHRI ||',
                    style: pw.TextStyle(fontSize: 9, color: ink),
                  ),
                ),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.topRight,
                    child: pw.Container(
                      width: 36,
                      height: 36,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(border: border),
                      child: pw.Text(
                        'RA',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Time : $time', style: cellStyle),
            pw.Text('Date : $date', style: cellStyle),
            pw.SizedBox(height: 4),
            pw.Text('Name : ${name.toUpperCase()}', style: cellStyle),
            pw.Text('Phone : ${phone.isEmpty ? '-' : phone}', style: cellStyle),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.blue700, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.7),
                1: pw.FlexColumnWidth(1.1),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  children: [
                    _h('SNo', headerStyle),
                    _h('Token', headerStyle),
                    _h('Weight', headerStyle, right: true),
                    _h('Touch', headerStyle, right: true),
                    _h('Pure', headerStyle, right: true),
                  ],
                ),
                for (final line in lines)
                  pw.TableRow(
                    children: [
                      _c('${line.sno}', cellStyle),
                      _c(line.token.trim().isEmpty ? '-' : line.token, cellStyle),
                      _c(formatWeight(line.weight), cellStyle, right: true),
                      _c(formatWeight(line.touch), cellStyle, right: true),
                      _c(formatWeight(line.pureWt), cellStyle, right: true),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(formatWeight(totalWt), style: bold),
                pw.Text(
                  'PURE GOLD     ${formatWeight(totalPure)}',
                  style: bold,
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '${formatWeight(atFine)} x ${formatWeight(kEstimateFineTouch)}  =  ${formatWeight(restatedPure)}',
                style: cellStyle,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Rs', style: cellStyle),
                pw.Text(
                  'CLOSING BALANCE    ${closingBalance.isEmpty ? 'NIL' : closingBalance}',
                  style: bold,
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'TOUCH : ${formatWeight(kEstimateFineTouch)}',
              style: cellStyle,
            ),
            pw.Spacer(),
            pw.Container(
              decoration: pw.BoxDecoration(border: border),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Bill No. : $billNo', style: cellStyle),
                  pw.Text('Date : $date', style: cellStyle),
                  pw.Text('Name : ${name.toUpperCase()}', style: cellStyle),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Weight : ${formatWeight(totalWt)}',
                          style: cellStyle),
                      pw.Text('${lines.length}', style: bold),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

pw.Widget _h(String text, pw.TextStyle style, {bool right = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(
      text,
      style: style,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );
}

pw.Widget _c(String text, pw.TextStyle style, {bool right = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(
      text,
      style: style,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );
}
