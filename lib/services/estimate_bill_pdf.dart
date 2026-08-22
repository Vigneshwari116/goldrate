import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/number_format.dart';

class EstimateLine {
  final int sno;
  final double weight;
  final double touch;
  final double pureWt;

  EstimateLine({
    required this.sno,
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
  double? goldRate,
}) async {
  final totalWt = lines.fold<double>(0, (s, l) => s + l.weight);
  final totalPure = lines.fold<double>(0, (s, l) => s + l.pureWt);
  final avgTouch = totalWt == 0 ? 0 : totalPure / totalWt * 100;

  final doc = pw.Document();
  final border = pw.Border.all(color: PdfColors.blue700, width: 0.8);
  final headerStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.blue800,
  );
  final cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.blue800);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => pw.Container(
        decoration: pw.BoxDecoration(border: border),
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'ESTIMATE ONLY',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                '|| SHRI ||',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.blue800),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Time : $time', style: cellStyle),
                      pw.Text('Date : $date', style: cellStyle),
                      pw.SizedBox(height: 4),
                      pw.Text('Name : $name', style: cellStyle),
                      pw.Text('Phone : ${phone.isEmpty ? '-' : phone}',
                          style: cellStyle),
                    ],
                  ),
                ),
                pw.Container(
                  width: 52,
                  height: 52,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(border: border),
                  child: pw.Text(
                    'RA',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.blue700, width: 0.6),
              children: [
                pw.TableRow(
                  children: [
                    _h('SNo', headerStyle),
                    _h('Weight', headerStyle),
                    _h('Touch', headerStyle),
                    _h('Pure', headerStyle),
                  ],
                ),
                for (final line in lines)
                  pw.TableRow(
                    children: [
                      _c('${line.sno}', cellStyle),
                      _c(formatWeight(line.weight), cellStyle),
                      _c(formatWeight(line.touch), cellStyle),
                      _c(formatWeight(line.pureWt), cellStyle),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(formatWeight(totalWt),
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900)),
                pw.Text(formatWeight(totalPure),
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900)),
              ],
            ),
            if (goldRate != null && goldRate > 0) ...[
              pw.SizedBox(height: 4),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${formatWeight(totalPure)} x ${formatAmount(goldRate)}  =  ${formatAmount(totalPure * goldRate)}',
                  style: cellStyle,
                ),
              ),
            ],
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Rs', style: cellStyle),
                pw.Text(
                  'CLOSING BALANCE    ${closingBalance.isEmpty ? 'NIL' : closingBalance}',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('TOUCH : ${formatWeight(avgTouch)}', style: cellStyle),
            pw.Spacer(),
            pw.Divider(color: PdfColors.blue700, thickness: 0.6),
            pw.SizedBox(height: 6),
            pw.Text('Bill No. : $billNo', style: cellStyle),
            pw.Text('Date : $date', style: cellStyle),
            pw.Text('Name : $name', style: cellStyle),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Weight : ${formatWeight(totalWt)}', style: cellStyle),
                pw.Text('${lines.length}',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900)),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

pw.Widget _h(String text, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(text, style: style),
  );
}

pw.Widget _c(String text, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(text, style: style),
  );
}
