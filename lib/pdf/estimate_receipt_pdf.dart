import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Physical shop receipt layout for sales/purchase estimates.
class EstimateReceiptPdf {
  EstimateReceiptPdf._();

  static pw.Widget borderedCell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.center,
    double fontSize = 9,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
      ),
    );
  }

  static pw.TableRow tableRow(List<String> cells, {bool header = false}) {
    return pw.TableRow(
      children: cells
          .map(
            (c) => borderedCell(
              c,
              bold: header,
              fontSize: header ? 9 : 8.5,
            ),
          )
          .toList(),
    );
  }

  static pw.Widget summaryLine(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Page buildPage({
    required String transactionLabel,
    required String billKind,
    required Map<String, dynamic> row,
    required String phone,
    required List<ReceiptLineItem> items,
    required double totalWt,
    required double totalPure,
    required double avgTouch,
    required double ratePerGram,
    required String closingLabel,
    required double cashReceived,
    required String paymentMode,
  }) {
    final rateLine = totalPure > 0 && ratePerGram > 0
        ? '${totalPure.toStringAsFixed(3)} x ${ratePerGram.toStringAsFixed(2)}'
        : '-';

    return pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'ESTIMATE ONLY',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Time: ${row['time'] ?? ''}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Date: ${row['date'] ?? ''}',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Name: ${row['partyName'] ?? '-'}',
              style: const pw.TextStyle(fontSize: 10)),
          if (phone.isNotEmpty)
            pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FlexColumnWidth(1.6),
            },
            children: [
              tableRow(
                ['SNo', 'Token', 'Weight', 'Touch', 'Pure'],
                header: true,
              ),
              for (var i = 0; i < items.length; i++)
                tableRow([
                  '${i + 1}',
                  items[i].token,
                  items[i].weight.toStringAsFixed(3),
                  items[i].touch.toStringAsFixed(2),
                  items[i].pureWt.toStringAsFixed(3),
                ]),
            ],
          ),
          pw.SizedBox(height: 8),
          summaryLine('Total Weight', totalWt.toStringAsFixed(3), bold: true),
          summaryLine('PURE GOLD', totalPure.toStringAsFixed(3), bold: true),
          summaryLine('Rate', rateLine),
          summaryLine('CLOSING BALANCE', closingLabel, bold: true),
          summaryLine('TOUCH:', avgTouch.toStringAsFixed(2)),
          if (cashReceived > 0 && paymentMode == 'CASH')
            summaryLine(
              'CASH RECEIVED',
              '₹${cashReceived.toStringAsFixed(2)}',
              bold: true,
            ),
          pw.Spacer(),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Bill No. $billKind-${row['billNo']}'),
              pw.Text('${row['date'] ?? ''}'),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Name: ${row['partyName'] ?? '-'}'),
              pw.Text('Weight: ${totalWt.toStringAsFixed(3)}'),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              transactionLabel,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.token,
    required this.weight,
    required this.touch,
    required this.pureWt,
  });

  final String token;
  final double weight;
  final double touch;
  final double pureWt;
}
