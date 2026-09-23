import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';
import 'invoice_party_lines.dart';

/// Compact sales tax invoice (Ultra Engineering Works–style layout).
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

  static pw.BorderSide get _side => pw.BorderSide(color: _line, width: _border);

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
      width: 52,
      height: 52,
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

  static pw.Widget _cell(
    String text, {
    double fontSize = 7.5,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: _text(text, size: fontSize, weight: weight, align: align),
    );
  }

  static pw.Widget _sellerAndMeta({
    required String billNo,
    required String billDate,
    String? ewayBill,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: _border),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
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
                            size: i == 0 ? 10 : 7.5,
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
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text('Invoice No.', size: 7, weight: pw.FontWeight.bold),
                  _text(billNo, size: 8, weight: pw.FontWeight.bold),
                  pw.SizedBox(height: 4),
                  _text('Dated', size: 7, weight: pw.FontWeight.bold),
                  _text(billDate, size: 8),
                  if ((ewayBill ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    _text('EWB NO:', size: 7, weight: pw.FontWeight.bold),
                    _text(ewayBill!.trim(), size: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _consigneeBox(List<String> lines) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            _text(
              line,
              size: line.startsWith('NAME &') ? 7.5 : 8,
              weight: line.startsWith('NAME &') ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
        ],
      ),
    );
  }

  static pw.Widget _itemsTable({
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double cgstSum,
    required double sgstSum,
    required double cgstPct,
    required double sgstPct,
  }) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('SL.NO', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('DESCRIPTION', fontSize: 7, weight: pw.FontWeight.bold),
          _cell('HSN/SAC', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.center),
          _cell('QTY', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('PRICE/UNIT', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
          _cell('AMOUNT', fontSize: 7, weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    ];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add(
        pw.TableRow(
          children: [
            _cell('${i + 1}', align: pw.TextAlign.center),
            _cell(item.description),
            _cell(item.hsn, align: pw.TextAlign.center),
            _cell('${_wt.format(item.weight)} GM', align: pw.TextAlign.right),
            _cell(_inr.format(item.rate), align: pw.TextAlign.right),
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
            _cell('CGST ${cgstPct.toStringAsFixed(2)}%'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(_inr.format(cgstSum), align: pw.TextAlign.right),
          ],
        ),
      );
      rows.add(
        pw.TableRow(
          children: [
            _cell(''),
            _cell('SGST ${sgstPct.toStringAsFixed(2)}%'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(_inr.format(sgstSum), align: pw.TextAlign.right),
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
            _cell('Less : Round Off $sign'),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(_inr.format(totals.roundOff.abs()), align: pw.TextAlign.right),
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
          _cell(''),
          _cell(''),
          _cell('₹${_inr.format(totals.grandTotal)}', weight: pw.FontWeight.bold, align: pw.TextAlign.right),
        ],
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: _border),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FixedColumnWidth(44),
        3: const pw.FixedColumnWidth(48),
        4: const pw.FixedColumnWidth(52),
        5: const pw.FixedColumnWidth(58),
      },
      children: rows,
    );
  }

  static pw.Widget _taxTotalsColumn({
    required double taxable,
    required double cgst,
    required double sgst,
    required double igst,
    required double roundOff,
    required double grandTotal,
  }) {
    pw.Widget row(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _text(label, size: 7.5, weight: pw.FontWeight.bold),
            _text(value, size: 7.5, align: pw.TextAlign.right),
          ],
        ),
      );
    }

    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          row('SGST', _inr.format(sgst)),
          row('CGST', _inr.format(cgst)),
          row('IGST', _inr.format(igst)),
          row('P & F', '0.00'),
          row('Round Off', _inr.format(roundOff)),
          row('G.Total', _inr.format(taxable + cgst + sgst + igst)),
          pw.Divider(color: _line, height: 0.5),
          row('Total', '₹${_inr.format(grandTotal)}'),
        ],
      ),
    );
  }

  static pw.Widget _footerBlock() {
    const terms = [
      '1.Good once sold will not be taken back or exchange',
      '2.Interest @24% will be charged if not paid with inthe due period.',
      '3.All Disputes Subject to Bangalore Judrisdiction Only.',
      '4.All Payment Should Be Made By A\\c Payee Cheque/D.D Only',
      '5.Our Risk/Reponsebility Ceases Once Goods Leave Our Premises',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: _border),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
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
                  _text('TERMS & CONDITIONS:', weight: pw.FontWeight.bold, size: 7.5),
                  for (final t in terms) _text(t, size: 6.5),
                  pw.SizedBox(height: 8),
                  _text("Receiver signature & Seal", size: 7.5),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text('BANK NAME :', size: 7),
                  _text('ACCOUNT NO', size: 7),
                  _text('IFS CODE :', size: 7),
                  _text('BRANCH :', size: 7),
                  pw.SizedBox(height: 24),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _text(
                          'for $_signatureName',
                          size: 8,
                          weight: pw.FontWeight.bold,
                          align: pw.TextAlign.right,
                        ),
                        pw.SizedBox(height: 20),
                        _text('Authorised Signatory', size: 7.5, align: pw.TextAlign.right),
                      ],
                    ),
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
    final grand = totals.grandTotal;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _text('TAX INVOICE', size: 12, weight: pw.FontWeight.bold),
              _text(copyLabel, size: 9, weight: pw.FontWeight.bold),
            ],
          ),
          pw.SizedBox(height: 4),
          _sellerAndMeta(billNo: billNo, billDate: billDate, ewayBill: eway),
          _consigneeBox(consignee),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _itemsTable(
                  items: items,
                  totals: totals,
                  cgstSum: cgstSum,
                  sgstSum: sgstSum,
                  cgstPct: cgstPct,
                  sgstPct: sgstPct,
                ),
              ),
              pw.SizedBox(width: 6),
              _taxTotalsColumn(
                taxable: totals.totalTaxable,
                cgst: cgstSum,
                sgst: sgstSum,
                igst: 0,
                roundOff: totals.roundOff,
                grandTotal: grand,
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: _border)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text('RUPEES IN WORDS:', size: 7.5, weight: pw.FontWeight.bold),
                _text(amountInWordsIndian(grand).toUpperCase(), size: 8, weight: pw.FontWeight.bold),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          _footerBlock(),
        ],
      ),
    );
  }
}
