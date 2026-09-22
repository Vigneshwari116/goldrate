import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/bill_tax.dart';
import 'package:grate_app/models/bill_line_item.dart';
import 'package:grate_app/models/party_billing_profile.dart';
import 'package:grate_app/pdf/pdf_kit.dart';
import 'package:grate_app/pdf/sales_tax_invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seller and buyer display lines use live data', () {
    final shop = const ShopSettings(
      shopName: 'Alpha Jewellers',
      address: 'Line 1\nLine 2',
      phone: '9999999999',
      gstin: '29AAAAA0000A1Z5',
      state: 'Karnataka',
      stateCode: '29',
    );
    final seller = SalesTaxInvoicePdf.sellerDisplayLines(shop);
    expect(seller.first, 'Alpha Jewellers');
    expect(seller, contains('Phone - 9999999999'));
    expect(seller.last, contains('Karnataka'));

    final buyerA = const PartyBillingProfile(
      name: 'CUSTOMER ALPHA LTD',
      isCustomer: true,
      address: '12 Main Road',
      city: 'Mysuru',
      pincode: '570001',
      gstin: '29BBBBB1111B1Z5',
      state: 'Karnataka',
    );
    final buyerB = const PartyBillingProfile(
      name: 'CUSTOMER BETA TRADERS',
      isCustomer: true,
      city: 'Udupi',
      gstin: '29CCCCC2222C1Z5',
      state: 'Karnataka',
    );
    expect(
      SalesTaxInvoicePdf.buyerDisplayLines(buyerA),
      contains('CUSTOMER ALPHA LTD'),
    );
    expect(
      SalesTaxInvoicePdf.buyerDisplayLines(buyerB),
      contains('CUSTOMER BETA TRADERS'),
    );
    expect(
      SalesTaxInvoicePdf.buyerDisplayLines(buyerA),
      isNot(contains('CUSTOMER BETA TRADERS')),
    );
  });

  test('empty shop settings use placeholders without throwing', () {
    final lines = SalesTaxInvoicePdf.sellerDisplayLines(const ShopSettings());
    expect(lines.first, '—');
    expect(lines, contains('GSTIN/UIN: —'));
  });

  test('PDF bytes differ for two different buyers', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 10,
        touch: 100,
        rate: 1000,
        hsn: '7113',
      ),
    ];
    final totals = BillTaxTotals.compute(lines: items.map((i) => i.tax).toList());

    Future<Uint8List> render(PartyBillingProfile buyer) async {
      final doc = await PdfKit.document();
      doc.addPage(
        SalesTaxInvoicePdf.buildPage(
          shop: const ShopSettings(shopName: 'Test Shop'),
          buyer: buyer,
          row: {'billNo': 1, 'date': '01-01-2026'},
          items: items,
          totals: totals,
          tdsApplicable: false,
          tcsApplicable: false,
          tdsAmount: 0,
          tcsAmount: 0,
        ),
      );
      return doc.save();
    }

    final pdfA = await render(const PartyBillingProfile(
      name: 'UNIQUE BUYER ONE',
      isCustomer: true,
    ));
    final pdfB = await render(const PartyBillingProfile(
      name: 'UNIQUE BUYER TWO',
      isCustomer: true,
    ));

    final textA = String.fromCharCodes(pdfA);
    final textB = String.fromCharCodes(pdfB);
    expect(textA, contains('UNIQUE BUYER ONE'));
    expect(textB, contains('UNIQUE BUYER TWO'));
    expect(textA, isNot(contains('UNIQUE BUYER TWO')));
    expect(textB, isNot(contains('UNIQUE BUYER ONE')));

    final dir = Directory('/opt/cursor/artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File('${dir.path}/invoice_buyer_a.pdf').writeAsBytes(pdfA);
    await File('${dir.path}/invoice_buyer_b.pdf').writeAsBytes(pdfB);
  });
}
