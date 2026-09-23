import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
/// Shared GST tax invoice layout (sales + purchase).
class GstTaxInvoiceLayout {
  GstTaxInvoiceLayout._();

  static const String copyOriginalForRecipient = '(ORIGINAL FOR RECIPIENT)';
  static const String copyDuplicateForTransporter = '(DUPLICATE FOR TRANSPORTER)';

  static const double _border = 0.5;
  static const PdfColor _line = PdfColors.black;
  static const String _placeholder = '—';

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _wt = NumberFormat('#,##0.000', 'en_IN');
  static final _rateFmt = NumberFormat('#,##0.00', 'en_IN');

  static pw.TextStyle _style({
    double size = 8,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.FontStyle fontStyle = pw.FontStyle.normal,
  }) =>
      pw.TextStyle(
        fontSize: size,
        fontWeight: weight,
        fontStyle: fontStyle,
      );

  static pw.Widget _text(
    String value, {
    double size = 8,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.FontStyle fontStyle = pw.FontStyle.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Text(
        value,
        style: _style(size: size, weight: weight, fontStyle: fontStyle),
        textAlign: align,
      );

  static pw.TableBorder get _tableBorder => pw.TableBorder.all(
        color: _line,
        width: _border,
      );

  static pw.BorderSide get _borderSide =>
      pw.BorderSide(color: _line, width: _border);

  static Map<int, pw.TableColumnWidth> get _itemColumnWidths => {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FixedColumnWidth(128),
        2: const pw.FixedColumnWidth(44),
        3: const pw.FixedColumnWidth(50),
        4: const pw.FixedColumnWidth(48),
        5: const pw.FixedColumnWidth(22),
        6: const pw.FixedColumnWidth(58),
      };

  static Map<int, pw.TableColumnWidth> get _metaColumnWidths => {
        0: const pw.FixedColumnWidth(72),
        1: const pw.FixedColumnWidth(52),
        2: const pw.FixedColumnWidth(72),
        3: const pw.FixedColumnWidth(52),
      };

  static const List<double> _taxColumnWidths = [
    40,
    56,
    32,
    48,
    32,
    48,
    52,
  ];

  static pw.Widget _cell(
    String text, {
    double fontSize = 7.5,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
    pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  }) {
    return pw.Padding(
      padding: padding,
      child: pw.Text(
        text,
        style: _style(size: fontSize, weight: weight),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _sellerBlock(List<String> lines) {
    return pw.Table(
      border: _tableBorder,
      columnWidths: {0: const pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    _text(
                      lines[i],
                      size: i == 0 ? 10 : 7.5,
                      weight:
                          i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Placeholder e-invoice block (no live IRN/QR integration).
  static pw.Widget _eInvoicePlaceholder() {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text('e-Invoice', size: 8, weight: pw.FontWeight.bold),
                _text('IRN : Not yet integrated', size: 7),
                _text('Ack No. : $_placeholder', size: 7),
                _text('Ack Date. : $_placeholder', size: 7),
              ],
            ),
          ),
          pw.Container(
            width: 54,
            height: 54,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey300,
              border: pw.Border.all(color: _line, width: _border),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buyerBlock(List<String> lines) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            _text(
              lines[i],
              size: 8,
              weight: i == 0 || i == 1
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
        ],
      ),
    );
  }

  /// Right-side metadata grid (reference invoice).
  static pw.Widget _metadataGrid({
    required String billNo,
    required String date,
    String referenceNo = '',
    String buyersOrderNo = '',
  }) {
    pw.TableRow row(String l1, String v1, String l2, String v2) {
      return pw.TableRow(
        children: [
          _cell(l1, fontSize: 7),
          _cell(v1, fontSize: 7, weight: pw.FontWeight.bold),
          _cell(l2, fontSize: 7),
          _cell(v2, fontSize: 7),
        ],
      );
    }

    return pw.Table(
      border: _tableBorder,
      columnWidths: _metaColumnWidths,
      children: [
        row('Invoice No.', billNo, 'Delivery Note', ''),
        row('Reference No. & Date.', referenceNo, "Buyer's Order No.", buyersOrderNo),
        row('Dispatch Doc No.', '', 'Dispatched through', ''),
        row('Vessel/Flight No.', '', 'City/Port of Loading', ''),
        row('Dated', date, 'Mode/Terms of Payment', ''),
        row('Other References', '', 'Dated', ''),
        row('Delivery Note Date', '', 'Destination', ''),
        row('Place of receipt by shipper:', '', 'City/Port of Discharge', ''),
        pw.TableRow(
          children: [
            _cell('Terms of Delivery', fontSize: 7),
            _cell('', fontSize: 7),
            _cell('', fontSize: 7),
            _cell('', fontSize: 7),
          ],
        ),
      ],
    );
  }

  static pw.Widget _itemsTable({
    required List<BillLineItem> items,
    required double cgstPct,
    required double sgstPct,
    required double cgstSum,
    required double sgstSum,
    required bool tdsApplicable,
    required double tdsAmount,
    required bool tcsApplicable,
    required double tcsAmount,
    required BillTaxTotals totals,
    required double totalWt,
  }) {
    final grand = totals.grandTotal;
    final rows = <pw.TableRow>[];

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Sl\nNo.', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Description of Goods', fontSize: 7, weight: pw.FontWeight.bold),
          _cell('HSN/SAC', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Quantity', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('Rate', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('per', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Amount', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add(
        pw.TableRow(
          children: [
            _cell('${i + 1}', align: pw.TextAlign.center),
            _cell(item.description),
            _cell(item.hsn, align: pw.TextAlign.center),
            _cell('${_wt.format(item.weight)} GM', align: pw.TextAlign.right),
            _cell(_rateFmt.format(item.rate), align: pw.TextAlign.right),
            _cell('GM', align: pw.TextAlign.center),
            _cell(_inr.format(item.tax.taxableValue), align: pw.TextAlign.right),
          ],
        ),
      );
    }

    if (cgstSum > 0) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('CGST ${cgstPct.toStringAsFixed(1)}%'),
            _cell(''),
            _cell(''),
            _cell(cgstPct.toStringAsFixed(2), align: pw.TextAlign.right),
            _cell('%', align: pw.TextAlign.center),
            _cell(_inr.format(cgstSum), align: pw.TextAlign.right),
          ],
        ),
      );
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('SGST ${sgstPct.toStringAsFixed(1)}%'),
            _cell(''),
            _cell(''),
            _cell(sgstPct.toStringAsFixed(2), align: pw.TextAlign.right),
            _cell('%', align: pw.TextAlign.center),
            _cell(_inr.format(sgstSum), align: pw.TextAlign.right),
          ],
        ),
      );
    }

    if (tdsApplicable && tdsAmount > 0) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('Less : TDS for F.Y-2026-27 (-)${_inr.format(tdsAmount)}'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
          ],
        ),
      );
    }

    if (tcsApplicable && tcsAmount > 0) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('Add : TCS ${_inr.format(tcsAmount)}'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
          ],
        ),
      );
    }

    if (totals.roundOff.abs() > 0.0001) {
      final sign = totals.roundOff < 0 ? '(-)' : '(+)';
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('Less : Round Off $sign${_inr.format(totals.roundOff.abs())}'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
          ],
        ),
      );
    }

    rows.add(
      pw.TableRow(
        children: [
          _cell(''),
          _cell('Total', weight: pw.FontWeight.bold),
          _cell(''),
          _cell('${_wt.format(totalWt)} GM', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(''),
          _cell('₹${_inr.format(grand)}', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Table(
        border: _tableBorder,
        columnWidths: _itemColumnWidths,
        children: rows,
      ),
    );
  }

  static pw.Widget _taxHeaderTallCell(double width, String label) {
    const headerHeight = 28.0;
    return pw.Container(
      width: width,
      height: headerHeight,
      decoration: pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border(
          top: _borderSide,
          left: _borderSide,
          right: _borderSide,
          bottom: _borderSide,
        ),
      ),
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
      child: _text(
        label,
        size: 6.5,
        weight: pw.FontWeight.bold,
        align: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _taxGroupHeader(double rateWidth, double amountWidth, String title) {
    const topHeight = 14.0;
    const subHeight = 14.0;
    return pw.SizedBox(
      width: rateWidth + amountWidth,
      child: pw.Column(
        children: [
          pw.Container(
            height: topHeight,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey300,
              border: pw.Border(
                top: _borderSide,
                left: _borderSide,
                right: _borderSide,
                bottom: _borderSide,
              ),
            ),
            child: _text(title, size: 6.5, weight: pw.FontWeight.bold),
          ),
          pw.Row(
            children: [
              pw.Container(
                width: rateWidth,
                height: subHeight,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey300,
                  border: pw.Border(
                    left: _borderSide,
                    right: _borderSide,
                    bottom: _borderSide,
                  ),
                ),
                child: _text('Rate', size: 6, weight: pw.FontWeight.bold),
              ),
              pw.Container(
                width: amountWidth,
                height: subHeight,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey300,
                  border: pw.Border(
                    right: _borderSide,
                    bottom: _borderSide,
                  ),
                ),
                child: _text('Amount', size: 6, weight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _taxSummaryTable(List<HsnTaxSummaryRow> hsnRows) {
    double totalTaxable = 0;
    double totalCgst = 0;
    double totalSgst = 0;
    double totalTax = 0;
    for (final h in hsnRows) {
      totalTaxable += h.taxable;
      totalCgst += h.cgstAmount;
      totalSgst += h.sgstAmount;
      totalTax += h.totalTax;
    }

    final w = _taxColumnWidths;
    final dataRows = <pw.TableRow>[];

    for (final h in hsnRows) {
      dataRows.add(
        pw.TableRow(
          children: [
            _cell(h.hsn, fontSize: 7),
            _cell(_inr.format(h.taxable), fontSize: 7, align: pw.TextAlign.right),
            _cell('${h.cgstPercent.toStringAsFixed(2)}%', fontSize: 7, align: pw.TextAlign.center),
            _cell(_inr.format(h.cgstAmount), fontSize: 7, align: pw.TextAlign.right),
            _cell('${h.sgstPercent.toStringAsFixed(2)}%', fontSize: 7, align: pw.TextAlign.center),
            _cell(_inr.format(h.sgstAmount), fontSize: 7, align: pw.TextAlign.right),
            _cell(_inr.format(h.totalTax), fontSize: 7, align: pw.TextAlign.right),
          ],
        ),
      );
    }

    dataRows.add(
      pw.TableRow(
        children: [
          _cell('Total', fontSize: 7, weight: pw.FontWeight.bold),
          _cell(_inr.format(totalTaxable), fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(_inr.format(totalCgst), fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(_inr.format(totalSgst), fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(_inr.format(totalTax), fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    final taxColWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < w.length; i++) i: pw.FixedColumnWidth(w[i]),
    };

    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _taxHeaderTallCell(w[0], 'HSN/SAC'),
              _taxHeaderTallCell(w[1], 'Taxable\nValue'),
              _taxGroupHeader(w[2], w[3], 'CGST'),
              _taxGroupHeader(w[4], w[5], 'SGST/UTGST'),
              _taxHeaderTallCell(w[6], 'Total Tax\nAmount'),
            ],
          ),
          pw.Table(
            border: _tableBorder,
            columnWidths: taxColWidths,
            children: dataRows,
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountInWordsBlock(double grand) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text(
            'Amount Chargeable (in words) E. & O.E',
            weight: pw.FontWeight.bold,
            size: 7.5,
          ),
          _text(
            amountInWordsIndian(grand),
            size: 8.5,
            weight: pw.FontWeight.bold,
          ),
        ],
      ),
    );
  }

  static pw.Widget _declarationBlock(String signatureName) {
    return pw.Table(
      border: _tableBorder,
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text('Declaration', weight: pw.FontWeight.bold, size: 8),
                  _text(
                    'Certified that the above particulars are true and correct',
                    size: 7.5,
                  ),
                  pw.SizedBox(height: 20),
                  _text("Customer's Seal and Signature", size: 7.5),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.SizedBox(height: 28),
                  _text(
                    'for $signatureName',
                    size: 8,
                    weight: pw.FontWeight.bold,
                    align: pw.TextAlign.right,
                  ),
                  pw.SizedBox(height: 24),
                  _text(
                    'Authorised Signatory',
                    size: 7.5,
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Page buildPage({
    required List<String> sellerLines,
    required List<String> buyerLines,
    required String signatureName,
    required String billNo,
    required String billDate,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double tdsAmount,
    required double tcsAmount,
    required bool tdsApplicable,
    required bool tcsApplicable,
    String copyLabel = copyOriginalForRecipient,
    String referenceNo = '',
    String buyersOrderNo = '',
  }) {
    final date = billDate;
    final grand = totals.grandTotal;

    final taxLines = items.map((i) => (hsn: i.hsn, tax: i.tax)).toList();
    final hsnRows = groupTaxByHsn(taxLines);
    final totalTax = hsnRows.fold<double>(0, (s, h) => s + h.totalTax);

    double cgstPct = 0;
    double sgstPct = 0;
    double cgstSum = 0;
    double sgstSum = 0;
    for (final item in items) {
      cgstPct = item.cgstPercent;
      sgstPct = item.sgstPercent;
      cgstSum += item.tax.cgstAmount;
      sgstSum += item.tax.sgstAmount;
    }
    final totalWt = items.fold<double>(0, (s, i) => s + i.weight);

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'INVOICE ',
                    style: _style(size: 11, weight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(
                    text: copyLabel,
                    style: _style(size: 9, fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 11,
                child: _sellerBlock(sellerLines),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 10,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _eInvoicePlaceholder(),
                    _metadataGrid(
                      billNo: billNo,
                      date: date,
                      referenceNo: referenceNo,
                      buyersOrderNo: buyersOrderNo,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          _buyerBlock(buyerLines),
          pw.SizedBox(height: 4),
          _itemsTable(
            items: items,
            cgstPct: cgstPct,
            sgstPct: sgstPct,
            cgstSum: cgstSum,
            sgstSum: sgstSum,
            tdsApplicable: tdsApplicable,
            tdsAmount: tdsAmount,
            tcsApplicable: tcsApplicable,
            tcsAmount: tcsAmount,
            totals: totals,
            totalWt: totalWt,
          ),
          pw.SizedBox(height: 4),
          _amountInWordsBlock(grand),
          pw.SizedBox(height: 4),
          _taxSummaryTable(hsnRows),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line, width: _border),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: _text(
              'Tax Amount (in words) : ${amountInWordsIndianWithPaise(totalTax)}',
              size: 8,
            ),
          ),
          pw.SizedBox(height: 4),
          _declarationBlock(signatureName),
          pw.SizedBox(height: 10),
          pw.Center(
            child: _text(
              'This is a Computer Generated Invoice',
              size: 8,
            ),
          ),
        ],
      ),
    );
  }
}
