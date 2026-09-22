import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/bill_tax.dart';
import '../models/bill_line_item.dart';
import '../models/party_billing_profile.dart';

/// GST sales invoice layout (reference: tax invoice with HSN summary).
class SalesTaxInvoicePdf {
  SalesTaxInvoicePdf._();

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _wt = NumberFormat('#,##0.000', 'en_IN');
  static final _rate = NumberFormat('#,##0.00', 'en_IN');

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    double fontSize = 8,
    pw.TextAlign align = pw.TextAlign.left,
    int flex = 1,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.4),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: align,
        ),
      ),
    );
  }

  static pw.Widget _row(List<pw.Widget> cells) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: cells,
    );
  }

  static pw.Page buildPage({
    required ShopSettings shop,
    required Map<String, dynamic> row,
    required PartyBillingProfile buyer,
    required List<BillLineItem> items,
    required BillTaxTotals totals,
    required double tdsAmount,
    required double tcsAmount,
    required bool tdsApplicable,
    required bool tcsApplicable,
  }) {
    final billNo = row['billNo']?.toString() ?? '';
    final date = (row['date'] ?? '').toString();
    final eway = (row['ewayBill'] ?? '').toString();

    final taxLines = items
        .map((i) => (hsn: i.hsn, tax: i.tax))
        .toList();
    final hsnRows = groupTaxByHsn(taxLines);

    final totalWt = items.fold<double>(0, (s, i) => s + i.weight);
    final grand = totals.grandTotal;

    // Aggregate CGST/SGST for display under item table (all lines same % typical).
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

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'INVOICE (ORIGINAL FOR RECIPIENT)',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            shop.shopName.isNotEmpty ? shop.shopName : 'Shop Name',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (shop.address.isNotEmpty)
            pw.Text(shop.address, style: const pw.TextStyle(fontSize: 9)),
          if (shop.phone.isNotEmpty)
            pw.Text('Phone - ${shop.phone}', style: const pw.TextStyle(fontSize: 9)),
          if (shop.gstin.isNotEmpty)
            pw.Text('GSTIN/UIN: ${shop.gstin}',
                style: const pw.TextStyle(fontSize: 9)),
          if (shop.state.isNotEmpty)
            pw.Text(
              'State Name : ${shop.state}${shop.stateCode.isNotEmpty ? ', Code : ${shop.stateCode}' : ''}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Buyer (Bill to)',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text(buyer.name,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      if (buyer.address.isNotEmpty)
                        pw.Text(buyer.address,
                            style: const pw.TextStyle(fontSize: 8.5)),
                      if (buyer.city.isNotEmpty || buyer.pincode.isNotEmpty)
                        pw.Text(
                          '${buyer.city}${buyer.pincode.isNotEmpty ? ' - ${buyer.pincode}' : ''}',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                      if (buyer.gstin.isNotEmpty)
                        pw.Text('GSTIN/UIN : ${buyer.gstin}',
                            style: const pw.TextStyle(fontSize: 8.5)),
                      if (buyer.state.isNotEmpty)
                        pw.Text('State Name : ${buyer.state}',
                            style: const pw.TextStyle(fontSize: 8.5)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                width: 160,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Invoice No. $billNo',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text('Dated $date',
                        style: const pw.TextStyle(fontSize: 8.5)),
                    if (eway.isNotEmpty)
                      pw.Text('E-Way Bill No. $eway',
                          style: const pw.TextStyle(fontSize: 8.5)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _row([
            _cell('Sl\nNo.', bold: true, fontSize: 7.5, align: pw.TextAlign.center, flex: 1),
            _cell('Description of Goods', bold: true, fontSize: 7.5, flex: 4),
            _cell('HSN/SAC', bold: true, fontSize: 7.5, align: pw.TextAlign.center, flex: 2),
            _cell('Quantity', bold: true, fontSize: 7.5, align: pw.TextAlign.center, flex: 2),
            _cell('Rate', bold: true, fontSize: 7.5, align: pw.TextAlign.center, flex: 2),
            _cell('per', bold: true, fontSize: 7.5, align: pw.TextAlign.center, flex: 1),
            _cell('Amount', bold: true, fontSize: 7.5, align: pw.TextAlign.right, flex: 3),
          ]),
          for (var i = 0; i < items.length; i++)
            _row([
              _cell('${i + 1}', align: pw.TextAlign.center, flex: 1),
              _cell(itemTypeDescription(items[i].type), flex: 4),
              _cell(items[i].hsn, align: pw.TextAlign.center, flex: 2),
              _cell('${_wt.format(items[i].weight)} GM',
                  align: pw.TextAlign.center, flex: 2),
              _cell(_rate.format(items[i].rate), align: pw.TextAlign.center, flex: 2),
              _cell('GM', align: pw.TextAlign.center, flex: 1),
              _cell(_inr.format(items[i].tax.taxableValue),
                  align: pw.TextAlign.right, flex: 3),
            ]),
          if (cgstSum > 0) ...[
            _row([
              _cell('', flex: 1),
              _cell('CGST ${cgstPct.toStringAsFixed(1)}%', flex: 4),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('${cgstPct.toStringAsFixed(2)}', align: pw.TextAlign.center, flex: 2),
              _cell('%', align: pw.TextAlign.center, flex: 1),
              _cell(_inr.format(cgstSum), align: pw.TextAlign.right, flex: 3),
            ]),
            _row([
              _cell('', flex: 1),
              _cell('SGST ${sgstPct.toStringAsFixed(1)}%', flex: 4),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('${sgstPct.toStringAsFixed(2)}', align: pw.TextAlign.center, flex: 2),
              _cell('%', align: pw.TextAlign.center, flex: 1),
              _cell(_inr.format(sgstSum), align: pw.TextAlign.right, flex: 3),
            ]),
          ],
          if (tdsApplicable && tdsAmount > 0)
            _row([
              _cell('', flex: 1),
              _cell('Less : TDS', flex: 4),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 1),
              _cell('(-)${_inr.format(tdsAmount)}',
                  align: pw.TextAlign.right, flex: 3),
            ]),
          if (tcsApplicable && tcsAmount > 0)
            _row([
              _cell('', flex: 1),
              _cell('Add : TCS', flex: 4),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 1),
              _cell(_inr.format(tcsAmount), align: pw.TextAlign.right, flex: 3),
            ]),
          if (totals.roundOff.abs() > 0.001)
            _row([
              _cell('', flex: 1),
              _cell('Less : Round Off', flex: 4),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 2),
              _cell('', flex: 1),
              _cell('(${totals.roundOff >= 0 ? '+' : ''}${_inr.format(totals.roundOff)})',
                  align: pw.TextAlign.right, flex: 3),
            ]),
          _row([
            _cell('', flex: 1),
            _cell('Total', bold: true, flex: 4),
            _cell('', flex: 2),
            _cell('${_wt.format(totalWt)} GM',
                bold: true, align: pw.TextAlign.center, flex: 2),
            _cell('', flex: 2),
            _cell('', flex: 1),
            _cell('₹${_inr.format(grand)}',
                bold: true, align: pw.TextAlign.right, flex: 3),
          ]),
          pw.SizedBox(height: 6),
          pw.Text(
            'Amount Chargeable (in words) E. & O.E',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            amountInWordsIndian(grand),
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Tax Summary',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _row([
            _cell('HSN/SAC', bold: true, flex: 2),
            _cell('Taxable Value', bold: true, align: pw.TextAlign.right, flex: 2),
            _cell('CGST Rate', bold: true, align: pw.TextAlign.center, flex: 2),
            _cell('CGST Amount', bold: true, align: pw.TextAlign.right, flex: 2),
            _cell('SGST Rate', bold: true, align: pw.TextAlign.center, flex: 2),
            _cell('SGST Amount', bold: true, align: pw.TextAlign.right, flex: 2),
            _cell('Total Tax', bold: true, align: pw.TextAlign.right, flex: 2),
          ]),
          for (final h in hsnRows)
            _row([
              _cell(h.hsn, flex: 2),
              _cell(_inr.format(h.taxable), align: pw.TextAlign.right, flex: 2),
              _cell('${h.cgstPercent}%', align: pw.TextAlign.center, flex: 2),
              _cell(_inr.format(h.cgstAmount), align: pw.TextAlign.right, flex: 2),
              _cell('${h.sgstPercent}%', align: pw.TextAlign.center, flex: 2),
              _cell(_inr.format(h.sgstAmount), align: pw.TextAlign.right, flex: 2),
              _cell(_inr.format(h.totalTax), align: pw.TextAlign.right, flex: 2),
            ]),
          pw.Spacer(),
          pw.Text(
            'We declare that this invoice shows the actual price of the goods '
            'described and that all particulars are true and correct.',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 24),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'for ${shop.shopName.isNotEmpty ? shop.shopName : '________________'}',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 28),
                pw.Text('Authorised Signatory',
                    style: const pw.TextStyle(fontSize: 8.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
