import 'package:barcode/barcode.dart';
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
    pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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

  static pw.Widget _sellerContent(List<String> lines) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          _text(
            lines[i],
            size: i == 0 ? 10 : 7.5,
            weight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
      ],
    );
  }

  static pw.Widget _partiesSection({
    required List<String> sellerLines,
    required List<String> buyerLines,
    required String billNo,
    required String date,
    String referenceNo = '',
    String buyersOrderNo = '',
  }) {
    final partiesTop = pw.Table(
      border: pw.TableBorder(
        top: _borderSide,
        left: _borderSide,
        right: _borderSide,
        bottom: _borderSide,
        horizontalInside: _borderSide,
        verticalInside: _borderSide,
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(11),
        1: const pw.FlexColumnWidth(10),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: _sellerContent(sellerLines),
            ),
            _metadataGrid(
              billNo: billNo,
              date: date,
              referenceNo: referenceNo,
              buyersOrderNo: buyersOrderNo,
              outerBorder: false,
            ),
          ],
        ),
      ],
    );

    final buyerTable = pw.Table(
      border: pw.TableBorder(
        left: _borderSide,
        right: _borderSide,
        bottom: _borderSide,
      ),
      columnWidths: {0: const pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: _buyerContent(buyerLines),
            ),
          ],
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [partiesTop, buyerTable],
    );
  }

  static pw.Widget _invoiceTitleRow(String copyLabel) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
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
        _text('e-Invoice', size: 8, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
      ],
    );
  }

  /// IRN / Ack lines (plain) + QR placeholder — full width below title.
  static pw.Widget _eInvoiceIrRow() {
    const qrSize = 92.0;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text('IRN : Not yet integrated', size: 7),
              _text('Ack No. : $_placeholder', size: 7),
              _text('Ack Date : $_placeholder', size: 7),
            ],
          ),
        ),
        pw.Container(
          width: qrSize,
          height: qrSize,
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: _border),
          ),
          child: pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: 'Not yet integrated',
            width: qrSize - 4,
            height: qrSize - 4,
            drawText: false,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buyerContent(List<String> lines) {
    return pw.Column(
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
    );
  }

  /// Right-side metadata grid (reference invoice).
  static pw.Widget _metadataGrid({
    required String billNo,
    required String date,
    String referenceNo = '',
    String buyersOrderNo = '',
    bool outerBorder = true,
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
      border: outerBorder ? _tableBorder : null,
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

  static pw.Widget _taxHeaderLabelCell(
    String label, {
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Container(
      height: 28,
      color: PdfColors.grey300,
      alignment: align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
      child: _text(
        label,
        size: 6.5,
        weight: pw.FontWeight.bold,
        align: align,
      ),
    );
  }

  /// CGST / SGST two-level header occupying the Rate+Amount column pair.
  static pw.Widget _taxGroupHeaderPair(
    double rateWidth,
    double amountWidth,
    String title,
  ) {
    final pairWidth = rateWidth + amountWidth;
    return pw.Container(
      height: 28,
      color: PdfColors.grey300,
      child: pw.Column(
        children: [
          pw.Container(
            width: pairWidth,
            height: 14,
            alignment: pw.Alignment.center,
            child: _text(title, size: 6.5, weight: pw.FontWeight.bold),
          ),
          pw.Row(
            children: [
              pw.Container(
                width: rateWidth,
                height: 14,
                alignment: pw.Alignment.center,
                child: _text('Rate', size: 6, weight: pw.FontWeight.bold),
              ),
              pw.Container(
                width: amountWidth,
                height: 14,
                alignment: pw.Alignment.center,
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
            _cell('${h.cgstPercent.toStringAsFixed(2)}%', fontSize: 7, align: pw.TextAlign.right),
            _cell(_inr.format(h.cgstAmount), fontSize: 7, align: pw.TextAlign.right),
            _cell('${h.sgstPercent.toStringAsFixed(2)}%', fontSize: 7, align: pw.TextAlign.right),
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

    final headerColWidths = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(w[0]),
      1: pw.FixedColumnWidth(w[1]),
      2: pw.FixedColumnWidth(w[2] + w[3]),
      3: pw.FixedColumnWidth(w[4] + w[5]),
      4: pw.FixedColumnWidth(w[6]),
    };

    final headerTable = pw.Table(
      border: pw.TableBorder(
        top: _borderSide,
        left: _borderSide,
        right: _borderSide,
        bottom: _borderSide,
        horizontalInside: _borderSide,
        verticalInside: _borderSide,
      ),
      columnWidths: headerColWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _taxHeaderLabelCell('HSN/SAC'),
            _taxHeaderLabelCell('Taxable\nValue', align: pw.TextAlign.right),
            _taxGroupHeaderPair(w[2], w[3], 'CGST'),
            _taxGroupHeaderPair(w[4], w[5], 'SGST/UTGST'),
            _taxHeaderLabelCell('Total Tax\nAmount', align: pw.TextAlign.right),
          ],
        ),
      ],
    );

    final bodyTable = pw.Table(
      border: pw.TableBorder(
        left: _borderSide,
        right: _borderSide,
        bottom: _borderSide,
        horizontalInside: _borderSide,
        verticalInside: _borderSide,
      ),
      columnWidths: taxColWidths,
      children: dataRows,
    );

    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [headerTable, bodyTable],
      ),
    );
  }

  static pw.Widget _amountInWordsBlock(double grand) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
          padding: const pw.EdgeInsets.all(4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _text('Declaration', weight: pw.FontWeight.bold, size: 8),
              _text(
                'Certified that the above particulars are true and correct',
                size: 7.5,
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: _text("Customer's Seal and Signature", size: 7.5),
                  ),
                  pw.Expanded(
                    child: _text(
                      'for $signatureName',
                      size: 8,
                      weight: pw.FontWeight.bold,
                      align: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2, right: 4),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _text('Authorised Signatory', size: 7.5, align: pw.TextAlign.right),
          ),
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
      margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _invoiceTitleRow(copyLabel),
          _eInvoiceIrRow(),
          _partiesSection(
            sellerLines: sellerLines,
            buyerLines: buyerLines,
            billNo: billNo,
            date: date,
            referenceNo: referenceNo,
            buyersOrderNo: buyersOrderNo,
          ),
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
          _amountInWordsBlock(grand),
          _taxSummaryTable(hsnRows),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line, width: _border),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: _text(
              'Tax Amount (in words) : ${amountInWordsIndianWithPaise(totalTax)}',
              size: 8,
            ),
          ),
          _declarationBlock(signatureName),
          pw.SizedBox(height: 4),
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
