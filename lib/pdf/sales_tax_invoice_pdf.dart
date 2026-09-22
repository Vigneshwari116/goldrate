import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';

/// Tally-style GST sales invoice — static seller/buyer from reference NAMITHA #97.
class SalesTaxInvoicePdf {
  SalesTaxInvoicePdf._();

  static const double _border = 0.5;
  static const PdfColor _line = PdfColors.black;

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _wt = NumberFormat('#,##0.000', 'en_IN');
  static final _rateFmt = NumberFormat('#,##0.00', 'en_IN');

  // ---------- Hardcoded reference blocks (not from shop_settings / party_profiles) ----------
  static const _sellerLines = [
    'Shree Mahalasa Jewellery Works',
    'No.180, 1st Cross, 9th Main Road,',
    'Srinivasanagar, BSK 1st Stage,',
    'Bangalore',
    'Phone - 9448008065',
    'GSTIN/UIN: 29ABDPV0313K1ZK',
    'State Name : Karnataka, Code : 29',
  ];

  static const _buyerHeader = 'Buyer (Bill to)';
  static const _buyerLines = [
    'NAMITHA BULLION TRADERS',
    'D.No. 10-1-58N17 "Jewel Plaza" Maruthi',
    'Veethika, Road, Udupi -576101',
    'GSTIN/UIN : 29OZPPS0920H1ZM',
    'PAN/IT No : OZPPS0920H',
    'State Name : Karnataka, Code : 29',
    'Place of Supply : Karnataka',
  ];

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

  static pw.Widget _sellerBlock() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _sellerLines.length; i++)
          _text(
            _sellerLines[i],
            size: i == 0 ? 10 : 8,
            weight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
      ],
    );
  }

  static pw.Widget _buyerBlock() {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text(_buyerHeader, size: 8, weight: pw.FontWeight.bold),
          pw.SizedBox(height: 2),
          for (var i = 0; i < _buyerLines.length; i++)
            _text(
              _buyerLines[i],
              size: 8,
              weight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
        ],
      ),
    );
  }

  /// Right-side metadata grid (reference invoice); only invoice no + date filled.
  static pw.Widget _metadataGrid(String billNo, String date) {
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
      columnWidths: {
        0: const pw.FlexColumnWidth(2.2),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FlexColumnWidth(2.2),
        3: const pw.FlexColumnWidth(1.3),
      },
      children: [
        row('Invoice No.', billNo, 'Delivery Note', ''),
        row('Reference No. & Date.', '', "Buyer's Order No.", ''),
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
          _cell('Amount', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('per', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('Rate', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('Quantity', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('HSN/SAC', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
        ],
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add(
        pw.TableRow(
          children: [
            _cell('${i + 1}', align: pw.TextAlign.center),
            _cell(invoicePdfLineDescription(item.type)),
            _cell(_inr.format(item.tax.taxableValue), align: pw.TextAlign.right),
            _cell('GM', align: pw.TextAlign.center),
            _cell(_rateFmt.format(item.rate), align: pw.TextAlign.right),
            _cell('${_wt.format(item.weight)} GM', align: pw.TextAlign.right),
            _cell(item.hsn, align: pw.TextAlign.center),
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
            _cell(_inr.format(cgstSum), align: pw.TextAlign.right),
            _cell('%', align: pw.TextAlign.center),
            _cell(cgstPct.toStringAsFixed(2), align: pw.TextAlign.right),
            _cell(''),
            _cell(''),
          ],
        ),
      );
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('SGST ${sgstPct.toStringAsFixed(1)}%'),
            _cell(_inr.format(sgstSum), align: pw.TextAlign.right),
            _cell('%', align: pw.TextAlign.center),
            _cell(sgstPct.toStringAsFixed(2), align: pw.TextAlign.right),
            _cell(''),
            _cell(''),
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
          _cell('₹${_inr.format(grand)}', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(''),
          _cell('${_wt.format(totalWt)} GM', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
        ],
      ),
    );

    return pw.Table(
      border: _tableBorder,
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(2.8),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(0.4),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.0),
        6: const pw.FlexColumnWidth(0.9),
      },
      children: rows,
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

    pw.TableRow hdr(String a, String b, String c, String d, String e, String f, String g) {
      return pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell(a, weight: pw.FontWeight.bold, fontSize: 6.5),
          _cell(b, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.right),
          _cell(c, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.center),
          _cell(d, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.right),
          _cell(e, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.center),
          _cell(f, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.right),
          _cell(g, weight: pw.FontWeight.bold, fontSize: 6.5, align: pw.TextAlign.right),
        ],
      );
    }

    final dataRows = <pw.TableRow>[
      hdr('HSN/SAC', 'Taxable\nValue', 'CGST\nRate', 'CGST\nAmount', 'SGST/UTGST\nRate', 'SGST/UTGST\nAmount', 'Total Tax\nAmount'),
    ];

    for (final h in hsnRows) {
      dataRows.add(
        pw.TableRow(
          children: [
            _cell(h.hsn),
            _cell(_inr.format(h.taxable), align: pw.TextAlign.right),
            _cell('${h.cgstPercent.toStringAsFixed(2)}%', align: pw.TextAlign.center),
            _cell(_inr.format(h.cgstAmount), align: pw.TextAlign.right),
            _cell('${h.sgstPercent.toStringAsFixed(2)}%', align: pw.TextAlign.center),
            _cell(_inr.format(h.sgstAmount), align: pw.TextAlign.right),
            _cell(_inr.format(h.totalTax), align: pw.TextAlign.right),
          ],
        ),
      );
    }

    dataRows.add(
      pw.TableRow(
        children: [
          _cell('Total', weight: pw.FontWeight.bold),
          _cell(_inr.format(totalTaxable), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(_inr.format(totalCgst), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(''),
          _cell(_inr.format(totalSgst), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell(_inr.format(totalTax), weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    return pw.Table(
      border: _tableBorder,
      columnWidths: {
        for (var i = 0; i < 7; i++) i: const pw.FlexColumnWidth(1),
      },
      children: dataRows,
    );
  }

  static pw.Page buildPage({
    required Map<String, dynamic> row,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double tdsAmount,
    required double tcsAmount,
    required bool tdsApplicable,
    required bool tcsApplicable,
  }) {
    final billNo = row['billNo']?.toString() ?? '';
    final date = (row['date'] ?? '').toString();
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
                    text: '(ORIGINAL FOR RECIPIENT)',
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
              pw.Expanded(flex: 5, child: _sellerBlock()),
              pw.SizedBox(width: 6),
              pw.Expanded(flex: 5, child: _metadataGrid(billNo, date)),
            ],
          ),
          pw.SizedBox(height: 6),
          _buyerBlock(),
          pw.SizedBox(height: 6),
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
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _text(
                  'Amount Chargeable (in words) E. & O.E',
                  weight: pw.FontWeight.bold,
                  size: 7.5,
                ),
              ),
            ],
          ),
          _text(
            amountInWordsIndian(grand),
            size: 8.5,
            weight: pw.FontWeight.bold,
          ),
          pw.SizedBox(height: 6),
          _taxSummaryTable(hsnRows),
          pw.SizedBox(height: 4),
          _text(
            'Tax Amount (in words) : ${amountInWordsIndianWithPaise(totalTax)}',
            size: 8,
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
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
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(height: 28),
                    _text(
                      'for Shree Mahalasa Jewellery Works',
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
