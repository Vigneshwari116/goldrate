import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/bill_tax.dart';
import 'package:grate_app/models/bill_line_item.dart';
import 'package:grate_app/models/party_billing_profile.dart';
import 'package:grate_app/pdf/invoice_party_lines.dart';
import 'package:grate_app/pdf/pdf_kit.dart';
import 'package:grate_app/pdf/purchase_tax_invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('purchase GST roles: supplier seller, shop buyer', () {
    final supplier = const PartyBillingProfile(
      name: 'TEST SUPPLIER',
      isCustomer: false,
      gstin: '29AAAAA0000A1Z5',
    );
    final seller = InvoicePartyLines.partyAsSellerLines(supplier);
    final buyer = InvoicePartyLines.shopAsBuyerLines();
    expect(seller.first, 'TEST SUPPLIER');
    expect(buyer.first, 'Buyer (Bill to)');
    expect(buyer, contains('Shree Mahalasa Jewellery Works'));
  });

  test('generates two-page purchase GST PDF', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 5,
        touch: 100,
        rate: 1000,
        hsn: '7113',
      ),
    ];
    final totals = BillTaxTotals.compute(lines: items.map((i) => i.tax).toList());
    final doc = await PdfKit.document();
    doc.addPage(
      PurchaseTaxInvoicePdf.buildPage(
        row: {
          'billNo': 2,
          'date': '23-09-2026',
          'partyName': 'TEST SUPPLIER',
          'poNo': 'PO-99',
          'poDate': '20-09-2026',
        },
        items: items,
        totals: totals,
        tdsApplicable: false,
        tcsApplicable: false,
        tdsAmount: 0,
        tcsAmount: 0,
      ),
    );
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(2000));
  });
}
