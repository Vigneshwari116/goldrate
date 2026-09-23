import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';
import 'invoice_party_lines.dart';

/// Compact sales tax invoice (reference: single grid + right tax rail).
class SimpleSalesTaxInvoicePdf {
  SimpleSalesTaxInvoicePdf._();

  static const String copyOriginalForBuyer = 'ORIGINAL FOR BUYER';
  static const String copyDuplicateForTransporter = 'DUPLICATE FOR TRANSPORTER';

  static const List<String> invoiceSellerLines = InvoicePartyLines.shopLines;
  static const String invoiceSellerSignatureName =
      InvoicePartyLines.shopSignatureName;

  static List<String> sellerDisplayLines() =>
      List<String>.unmodifiable(invoiceSellerLines);

  static List<String> consigneeDisplayLines(PartyBillingProfile buyer) {
    return _consigneeLines(buyer);
  }

  static const List<String> _sellerLines = invoiceSellerLines;
  static const String _signatureName = invoiceSellerSignatureName;

  static const double _border = 0.5;
  static const PdfColor _line = PdfColors.black;

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _wt = NumberFormat('#,##0.000', 'en_IN');

  static pw.TableBorder get _tableBorder => pw.TableBorder.all(
        color: _line,
        width: _border,
      );

  static pw.TextStyle _style({
    double size = 8,
    pw.FontWeight weight = pw.FontWeight.normal,
  }) =>
      pw.TextStyle(fontSize: size, fontWeight: weight);

  static pw.Widget _text(
    String value, {
    double size = 8,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Text(value, style: _style(size: size, weight: weight), textAlign: align);

  static pw.Widget _logoPlaceholder() {
    return pw.Container(
      width: 48,
      height: 48,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
        color: PdfColors.grey200,
      ),
      alignment: pw.Alignment.center,
      child: _text('LOGO', size: 7, weight: pw.FontWeight.bold),
    );
  }

  static List<String> _consigneeLines(PartyBillingProfile buyer) {
    final party = InvoicePartyLines.partyAsBuyerLines(buyer);
    return ['NAME & ADDRESS OF CONSIGNEE', ...party.skip(1)];
  }

  static List<String> _shippingLines(PartyBillingProfile buyer) {
    final party = InvoicePartyLines.partyAsBuyerLines(buyer);
    return ['SHIPPING NAME & ADDRESS OF CONSIGNEE', ...party.skip(1)];
  }

  static String _shopGstin() {
    for (final line in _sellerLines) {
      if (line.contains('GSTIN')) {
        return line.replaceFirst('GSTIN/UIN:', '').trim();
      }
    }
    return '';
  }

  static pw.Widget _cell(
    String text, {
    double fontSize = 7.5,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
      child: _text(text, size: fontSize, weight: weight, align: align),
    );
  }

  static pw.Widget _metaField(String label, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _cell(label, fontSize: 7);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label ', style: _style(size: 7)),
            pw.TextSpan(
              text: trimmed,
              style: _style(size: 7, weight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _metadataGrid({
    required String billNo,
    required String date,
    String ewayBill = '',
  }) {
    pw.TableRow pair(String l1, String v1, String l2, String v2) {
      return pw.TableRow(
        children: [
          _metaField(l1, v1),
          _metaField(l2, v2),
        ],
      );
    }

    final eway = ewayBill.trim();
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pair('Invoice No.', billNo, 'Dated', date),
        pair('Delivery Note', '', 'Mode/Terms of Payment', ''),
        pair('Reference No. & Date.', '', 'Other References', ''),
        pair("Buyer's Order No.", '', 'Dated', ''),
        pair('Dispatch Doc No.', '', 'Delivery Note Date', ''),
        pair('Dispatched through', '', 'Destination', ''),
        pair('Vessel/Flight No.', '', 'Place of receipt by shipper:', ''),
        pair('City/Port of Loading', '', 'City/Port of Discharge', ''),
        if (eway.isNotEmpty)
          pair('EWB NO:', eway, '', '')
        else
          pw.TableRow(
            children: [
              _cell('Terms of Delivery', fontSize: 7),
              _cell('', fontSize: 7),
            ],
          ),
        if (eway.isNotEmpty)
          pw.TableRow(
            children: [
              _cell('Terms of Delivery', fontSize: 7),
              _cell('', fontSize: 7),
            ],
          ),
      ],
    );
  }

  static pw.Widget _sellerAndMeta({
    required String billNo,
    required String billDate,
    String? ewayBill,
  }) {
    return pw.Table(
      border: _tableBorder,
      columnWidths: const {
        0: pw.FlexColumnWidth(11),
        1: pw.FlexColumnWidth(10),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _logoPlaceholder(),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _sellerLines.length; i++)
                          _text(
                            _sellerLines[i],
                            size: i == 0 ? 9.5 : 7,
                            weight: i == 0
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _metadataGrid(
              billNo: billNo,
              date: billDate,
              ewayBill: ewayBill ?? '',
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _addressCell(List<String> lines) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            _text(
              line,
              size: line.startsWith('NAME &') || line.startsWith('SHIPPING')
                  ? 7
                  : 7.5,
              weight: line.startsWith('NAME &') || line.startsWith('SHIPPING')
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
        ],
      ),
    );
  }

  /// Consignee | shipping — side by side like reference invoice.
  static pw.Widget _consigneeShippingRow(
    List<String> consignee,
    List<String> shipping,
  ) {
    return pw.Table(
      border: _tableBorder,
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          children: [
            _addressCell(consignee),
            _addressCell(shipping),
          ],
        ),
      ],
    );
  }

  static const _itemColW = [24.0, 40.0, 42.0, 48.0, 62.0]; // sl, hsn, qty, amount — desc flex

  static pw.Widget _mainItemsAndTaxTable({
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double cgstSum,
    required double sgstSum,
    required double cgstPct,
    required double sgstPct,
  }) {
    final taxable = totals.totalTaxable;
    final grand = totals.grandTotal;
    final igst = 0.0;
    final roundOff = totals.roundOff;

    final rows = <pw.TableRow>[];

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('SL.NO', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('DESCRIPTION', fontSize: 7, weight: pw.FontWeight.bold),
          _cell('HSN/SAC', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('QTY', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('AMOUNT', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
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
            _cell(_inr.format(item.tax.taxableValue), align: pw.TextAlign.right),
          ],
        ),
      );
    }

    const minItemRows = 8;
    for (var i = items.length; i < minItemRows; i++) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(''),
          ],
        ),
      );
    }

    void taxRow(
      String label,
      String pct,
      String amount, {
      bool bold = false,
    }) {
      final w = bold ? pw.FontWeight.bold : pw.FontWeight.normal;
      final mid = pct.isEmpty ? '$label :' : '$label : $pct';
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(mid, fontSize: 7, weight: w, align: pw.TextAlign.right),
            _cell(amount, fontSize: 7, weight: w, align: pw.TextAlign.right),
          ],
        ),
      );
    }

    taxRow('Total', '', _inr.format(taxable));
    if (cgstSum > 0 || sgstSum > 0) {
      taxRow('SGST', '${sgstPct.toStringAsFixed(2)} %', _inr.format(sgstSum));
      taxRow('CGST', '${cgstPct.toStringAsFixed(2)} %', _inr.format(cgstSum));
    }
    taxRow('IGST', '${igst.toStringAsFixed(2)} %', _inr.format(igst));
    if (roundOff.abs() > 0.0001) {
      final sign = roundOff < 0 ? '(-)' : '(+)';
      taxRow('Round Off', sign, _inr.format(roundOff.abs()));
    }
    taxRow('G.Total', '', _inr.format(grand), bold: true);

    return pw.Table(
      border: _tableBorder,
      columnWidths: {
        0: pw.FixedColumnWidth(_itemColW[0]),
        1: const pw.FlexColumnWidth(1),
        2: pw.FixedColumnWidth(_itemColW[1]),
        3: pw.FixedColumnWidth(_itemColW[2]),
        4: pw.FixedColumnWidth(_itemColW[3]),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  static pw.Widget _footerBlock({required double grandTotal}) {
    const terms = [
      '1.Good once sold will not be taken back or exchange',
      '2.Interest @24% will be charged if not paid with inthe due period.',
      '3.All Disputes Subject to Bangalore Judrisdiction Only.',
      '4.All Payment Should Be Made By A\\c Payee Cheque/D.D Only',
      '5.Our Risk/Reponsebility Ceases Once Goods Leave Our Premises',
    ];

    final gstin = _shopGstin();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(
          border: _tableBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (gstin.isNotEmpty)
                        _text('GSTIN:$gstin', size: 7, weight: pw.FontWeight.bold),
                      pw.SizedBox(height: 4),
                      _text('RUPEES IN WORDS:', size: 7, weight: pw.FontWeight.bold),
                      _text(
                        amountInWordsIndian(grandTotal).toUpperCase(),
                        size: 7.5,
                        weight: pw.FontWeight.bold,
                      ),
                      pw.SizedBox(height: 6),
                      _text('BANK NAME :', size: 7),
                      _text('ACCOUNT NO', size: 7),
                      _text('IFS CODE :', size: 7),
                      _text('BRANCH :', size: 7),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _text(
                        'for $_signatureName',
                        size: 8,
                        weight: pw.FontWeight.bold,
                        align: pw.TextAlign.right,
                      ),
                      pw.SizedBox(height: 36),
                      _text('Authorised Signatory', size: 7, align: pw.TextAlign.right),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.Container(
          width: double.infinity,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
          padding: const pw.EdgeInsets.all(5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text('TERMS & CONDITIONS:', weight: pw.FontWeight.bold, size: 7),
              for (final t in terms) _text(t, size: 6.5),
              pw.SizedBox(height: 4),
              _text('Receiver signature & Seal', size: 7),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Page buildPage({
    required PartyBillingProfile buyer,
    required Map<String, dynamic> row,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    String copyLabel = copyOriginalForBuyer,
  }) {
    final billNo = row['billNo']?.toString() ?? '';
    final billDate = (row['date'] ?? '').toString();
    final eway = (row['ewayBill'] ?? '').toString();

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

    final consignee = _consigneeLines(buyer);
    final shipping = _shippingLines(buyer);
    final grand = totals.grandTotal;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _text('TAX INVOICE', size: 11, weight: pw.FontWeight.bold),
              _text(copyLabel, size: 9, weight: pw.FontWeight.bold),
            ],
          ),
          pw.SizedBox(height: 3),
          _sellerAndMeta(billNo: billNo, billDate: billDate, ewayBill: eway),
          _consigneeShippingRow(consignee, shipping),
          _mainItemsAndTaxTable(
            items: items,
            totals: totals,
            cgstSum: cgstSum,
            sgstSum: sgstSum,
            cgstPct: cgstPct,
            sgstPct: sgstPct,
          ),
          _footerBlock(grandTotal: grand),
        ],
      ),
    );
  }
}
