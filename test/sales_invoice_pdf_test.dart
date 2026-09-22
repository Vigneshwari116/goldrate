import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/bill_tax.dart';
import 'package:grate_app/models/bill_line_item.dart';
import 'package:grate_app/models/party_billing_profile.dart';
import 'package:grate_app/pdf/sales_tax_invoice_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('generates sample sales tax invoice PDF bytes', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 350,
        touch: 100,
        rate: 15631.07,
        hsn: '71081300',
      ),
    ];
    final totals = BillTaxTotals.compute(
      lines: items.map((i) => i.tax).toList(),
      tdsAmount: 5471,
    );
    final page = SalesTaxInvoicePdf.buildPage(
      shop: const ShopSettings(
        shopName: 'Shree Mahalasa Jewellery Works',
        address: 'No.180, 1st Cross, 9th Main Road, Bangalore',
        phone: '9448008065',
        gstin: '29ABDPV0313K1ZK',
        state: 'Karnataka',
        stateCode: '29',
      ),
      row: {
        'billNo': 97,
        'date': '20-Aug-26',
        'ewayBill': '',
      },
      buyer: const PartyBillingProfile(
        name: 'NAMITHA BULLION TRADERS',
        isCustomer: true,
        address: 'D.No. 10-1-58N17 Jewel Plaza, Udupi',
        city: 'Udupi',
        pincode: '576101',
        gstin: '29OZPPS0920H1ZM',
        state: 'Karnataka',
      ),
      items: items,
      totals: totals,
      tdsApplicable: true,
      tcsApplicable: false,
      tdsAmount: 5471,
      tcsAmount: 0,
    );
    final document = pw.Document();
    document.addPage(page);
    final doc = await document.save();
    final dir = Directory('/opt/cursor/artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/sample_sales_tax_invoice.pdf');
    await file.writeAsBytes(doc);
    expect(doc.length, greaterThan(1000));
  });
}
