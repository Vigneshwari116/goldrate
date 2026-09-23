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
    double size = 8.5,
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

  static const List<double> _itemColW = [26, 132, 46, 52, 50, 24, 60];

  static Map<int, pw.TableColumnWidth> get _itemColumnWidths => {
        for (var i = 0; i < _itemColW.length; i++)
          i: pw.FixedColumnWidth(_itemColW[i]),
      };

  static pw.Widget _itemCell(
    int column,
    String text, {
    double fontSize = 8,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final width = _itemColW[column];
    return pw.SizedBox(
      width: width,
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: pw.Text(
          text,
          style: _style(size: fontSize, weight: weight),
          textAlign: align,
          maxLines: column == 1 ? 4 : 2,
          overflow: pw.TextOverflow.clip,
        ),
      ),
    );
  }

  static Map<int, pw.TableColumnWidth> get _metaColumnWidths => {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
      };

  /// Tax summary: HSN, taxable, CGST group, SGST group, total tax.
  static const List<double> _taxColumnWidths = [
    44,
    62,
    88,
    88,
    58,
  ];

  static const double _taxCgstRateW = 36;

  static pw.Widget _cell(
    String text, {
    double fontSize = 8,
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

  static pw.Widget _metaField(String label, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _cell(label, fontSize: 7.5);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label ', style: _style(size: 7.5)),
            pw.TextSpan(
              text: trimmed,
              style: _style(size: 7.5, weight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// Right-side metadata grid (reference invoice order, two columns).
  static pw.Widget _metadataGrid({
    required String billNo,
    required String date,
    String referenceNo = '',
    String buyersOrderNo = '',
    bool outerBorder = true,
  }) {
    pw.TableRow pair(String l1, String v1, String l2, String v2) {
      return pw.TableRow(
        children: [
          _metaField(l1, v1),
          _metaField(l2, v2),
        ],
      );
    }

    return pw.Table(
      border: outerBorder ? _tableBorder : null,
      columnWidths: _metaColumnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pair('Invoice No.', billNo, 'Dated', date),
        pair('Delivery Note', '', 'Mode/Terms of Payment', ''),
        pair('Reference No. & Date.', referenceNo, 'Other References', ''),
        pair("Buyer's Order No.", buyersOrderNo, 'Dated', ''),
        pair('Dispatch Doc No.', '', 'Delivery Note Date', ''),
        pair('Dispatched through', '', 'Destination', ''),
        pair('Vessel/Flight No.', '', 'Place of receipt by shipper:', ''),
        pair('City/Port of Loading', '', 'City/Port of Discharge', ''),
        pw.TableRow(
          children: [
            _cell('Terms of Delivery', fontSize: 7.5),
            _cell('', fontSize: 7.5),
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

    List<pw.Widget> itemCells(
      List<String> cells, {
      pw.FontWeight weight = pw.FontWeight.normal,
      Map<int, pw.TextAlign>? align,
    }) {
      return List<pw.Widget>.generate(_itemColW.length, (i) {
        return _itemCell(
          i,
          cells[i],
          fontSize: 7.5,
          weight: weight,
          align: align?[i] ?? _itemDefaultAlign(i),
        );
      });
    }

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: itemCells(
          const [
            'Sl\nNo.',
            'Description of Goods',
            'HSN/SAC',
            'Quantity',
            'Rate',
            'per',
            'Amount',
          ],
          weight: pw.FontWeight.bold,
          align: {
            0: pw.TextAlign.center,
            2: pw.TextAlign.center,
            3: pw.TextAlign.right,
            4: pw.TextAlign.right,
            5: pw.TextAlign.center,
            6: pw.TextAlign.right,
          },
        ),
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '${i + 1}',
            item.description,
            item.hsn,
            '${_wt.format(item.weight)} GM',
            _rateFmt.format(item.rate),
            'GM',
            _inr.format(item.tax.taxableValue),
          ],
          align: {
            0: pw.TextAlign.center,
            2: pw.TextAlign.center,
            3: pw.TextAlign.right,
            4: pw.TextAlign.right,
            5: pw.TextAlign.center,
            6: pw.TextAlign.right,
          },
        ),
        ),
      );
    }

    if (cgstSum > 0) {
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '',
            'CGST ${cgstPct.toStringAsFixed(1)}%',
            '',
            '',
            '',
            '',
            _inr.format(cgstSum),
          ],
          align: {6: pw.TextAlign.right},
        ),
        ),
      );
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '',
            'SGST ${sgstPct.toStringAsFixed(1)}%',
            '',
            '',
            '',
            '',
            _inr.format(sgstSum),
          ],
          align: {6: pw.TextAlign.right},
        ),
        ),
      );
    }

    if (tdsApplicable && tdsAmount > 0) {
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '',
            'Less : TDS for F.Y-2026-27 (-)',
            '',
            '',
            '',
            '',
            _inr.format(tdsAmount),
          ],
          align: {6: pw.TextAlign.right},
        ),
        ),
      );
    }

    if (tcsApplicable && tcsAmount > 0) {
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '',
            'Add : TCS',
            '',
            '',
            '',
            '',
            _inr.format(tcsAmount),
          ],
          align: {6: pw.TextAlign.right},
        ),
        ),
      );
    }

    if (totals.roundOff.abs() > 0.0001) {
      final sign = totals.roundOff < 0 ? '(-)' : '(+)';
      rows.add(
        pw.TableRow(
          children: itemCells(
          [
            '',
            'Less : Round Off $sign',
            '',
            '',
            '',
            '',
            _inr.format(totals.roundOff.abs()),
          ],
          align: {6: pw.TextAlign.right},
        ),
        ),
      );
    }

    double totalPure = 0;
    double rateWeighted = 0;
    for (final item in items) {
      totalPure += item.pureWt;
      rateWeighted += item.pureWt * item.rate;
    }
    final totalRate =
        totalPure > 0 ? rateWeighted / totalPure : 0.0;

    rows.add(
      pw.TableRow(
        children: itemCells(
        [
          '',
          'Total',
          '',
          '${_wt.format(totalWt)} GM',
          _rateFmt.format(totalRate),
          'GM',
          '₹${_inr.format(grand)}',
        ],
        weight: pw.FontWeight.bold,
        align: {
          3: pw.TextAlign.right,
          4: pw.TextAlign.right,
          5: pw.TextAlign.center,
          6: pw.TextAlign.right,
        },
      ),
      ),
    );

    return pw.Table(
      border: _tableBorder,
      columnWidths: _itemColumnWidths,
      children: rows,
    );
  }

  static pw.TextAlign _itemDefaultAlign(int column) {
    switch (column) {
      case 0:
      case 2:
      case 5:
        return pw.TextAlign.center;
      case 3:
      case 4:
      case 6:
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.left;
    }
  }

  static pw.Widget _taxHeaderPlainCell(
    double width,
    String label, {
    double height = 30,
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Container(
      width: width,
      height: height,
      color: PdfColors.grey300,
      alignment: align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
      child: _text(
        label,
        size: 7,
        weight: pw.FontWeight.bold,
        align: align,
      ),
    );
  }

  static pw.Widget _taxGroupHeaderCell(double groupWidth, String title) {
    return pw.Container(
      width: groupWidth,
      height: 30,
      color: PdfColors.grey300,
      child: pw.Column(
        children: [
          pw.Container(
            height: 15,
            width: groupWidth,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: _border),
              ),
            ),
            child: _text(title, size: 7, weight: pw.FontWeight.bold),
          ),
          pw.Row(
            children: [
              pw.Container(
                width: _taxCgstRateW,
                height: 15,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(color: _line, width: _border),
                  ),
                ),
                child: _text('Rate', size: 6.5, weight: pw.FontWeight.bold),
              ),
              pw.Container(
                width: groupWidth - _taxCgstRateW,
                height: 15,
                alignment: pw.Alignment.center,
                child: _text('Amount', size: 6.5, weight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _taxRateAmountCell(
    double groupWidth,
    String rate,
    String amount,
  ) {
    return pw.SizedBox(
      width: groupWidth,
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: _taxCgstRateW,
            child: _cell(rate, fontSize: 7.5, align: pw.TextAlign.right),
          ),
          pw.SizedBox(
            width: groupWidth - _taxCgstRateW,
            child: _cell(amount, fontSize: 7.5, align: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  static pw.Widget _taxDataCell(
    int column,
    String text, {
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final width = _taxColumnWidths[column];
    return pw.SizedBox(
      width: width,
      child: _cell(text, fontSize: 7.5, weight: weight, align: align),
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
            _taxDataCell(0, h.hsn),
            _taxDataCell(1, _inr.format(h.taxable), align: pw.TextAlign.right),
            _taxRateAmountCell(
              w[2],
              '${h.cgstPercent.toStringAsFixed(2)}%',
              _inr.format(h.cgstAmount),
            ),
            _taxRateAmountCell(
              w[3],
              '${h.sgstPercent.toStringAsFixed(2)}%',
              _inr.format(h.sgstAmount),
            ),
            _taxDataCell(4, _inr.format(h.totalTax), align: pw.TextAlign.right),
          ],
        ),
      );
    }

    dataRows.add(
      pw.TableRow(
        children: [
          _taxDataCell(0, 'Total', weight: pw.FontWeight.bold),
          _taxDataCell(1, _inr.format(totalTaxable), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _taxRateAmountCell(w[2], '', _inr.format(totalCgst),),
          _taxRateAmountCell(w[3], '', _inr.format(totalSgst),),
          _taxDataCell(4, _inr.format(totalTax), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    final taxColWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < w.length; i++) i: pw.FixedColumnWidth(w[i]),
    };

    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _taxHeaderPlainCell(w[0], 'HSN/SAC'),
        _taxHeaderPlainCell(w[1], 'Taxable\nValue', align: pw.TextAlign.right),
        _taxGroupHeaderCell(w[2], 'CGST'),
        _taxGroupHeaderCell(w[3], 'SGST/UTGST'),
        _taxHeaderPlainCell(w[4], 'Total Tax\nAmount', align: pw.TextAlign.right),
      ],
    );

    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Table(
        border: _tableBorder,
        columnWidths: taxColWidths,
        children: [headerRow, ...dataRows],
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
            size: 8,
          ),
          _text(
            amountInWordsIndian(grand),
            size: 9,
            weight: pw.FontWeight.bold,
          ),
        ],
      ),
    );
  }

  static pw.Widget _declarationBlock(String signatureName) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _text('Declaration', weight: pw.FontWeight.bold, size: 8.5),
          _text(
            'Certified that the above particulars are true and correct',
            size: 8,
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: _borderSide),
            ),
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 2,
                  child: _text("Customer's Seal and Signature", size: 8),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _text(
                        'for $signatureName',
                        size: 8.5,
                        weight: pw.FontWeight.bold,
                        align: pw.TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 32),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _text('Authorised Signatory', size: 8, align: pw.TextAlign.right),
          ),
        ],
      ),
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
              size: 8.5,
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
