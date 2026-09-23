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

  test('seller lines use fixed reference invoice address', () {
    final seller = SalesTaxInvoicePdf.sellerDisplayLines();
    expect(seller.first, 'Shree Mahalasa Jewellery Works');
    expect(seller, contains('GSTIN/UIN: 29ABDPV0313K1ZK'));
    expect(seller, contains('Phone - 9448008065'));
  });

  test('buyer display lines use live party data', () {
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

  test('generates PDF for two buyers without error', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 10,
        touch: 100,
        rate: 1000,
        hsn: '7113',
        description: 'Gold Ring',
      ),
    ];
    expect(items.first.description, 'Gold Ring');
    final totals = BillTaxTotals.compute(lines: items.map((i) => i.tax).toList());

    Future<Uint8List> render(PartyBillingProfile buyer) async {
      final doc = await PdfKit.document();
      doc.addPage(
        SalesTaxInvoicePdf.buildPage(
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

    final pdfA = await render(
      const PartyBillingProfile(
        name: 'UNIQUE BUYER ONE',
        isCustomer: true,
      ),
    );
    final pdfB = await render(
      const PartyBillingProfile(
        name: 'UNIQUE BUYER TWO',
        isCustomer: true,
        gstin: '29AAAAA0000A1Z5',
      ),
    );

    expect(pdfA.length, greaterThan(1000));
    expect(pdfB.length, greaterThan(1000));
    expect(pdfA, isNot(equals(pdfB)));

    final dir = Directory('/opt/cursor/artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File('${dir.path}/invoice_buyer_a.pdf').writeAsBytes(pdfA);
    await File('${dir.path}/invoice_buyer_b.pdf').writeAsBytes(pdfB);
  });

  test('sales GST document has original and transporter copy pages', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 1,
        touch: 100,
        rate: 1000,
        hsn: '7113',
      ),
    ];
    final totals = BillTaxTotals.compute(lines: items.map((i) => i.tax).toList());
    final doc = await PdfKit.document();
    for (final copyLabel in [
      SalesTaxInvoicePdf.copyOriginalForRecipient,
      SalesTaxInvoicePdf.copyDuplicateForTransporter,
    ]) {
      doc.addPage(
        SalesTaxInvoicePdf.buildPage(
          buyer: const PartyBillingProfile(name: 'Buyer', isCustomer: true),
          row: {'billNo': 99, 'date': '01-01-2026'},
          items: items,
          totals: totals,
          tdsApplicable: false,
          tcsApplicable: false,
          tdsAmount: 0,
          tcsAmount: 0,
          copyLabel: copyLabel,
        ),
      );
    }
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(2000));
    expect(SalesTaxInvoicePdf.copyOriginalForRecipient, contains('RECIPIENT'));
    expect(SalesTaxInvoicePdf.copyDuplicateForTransporter, contains('TRANSPORTER'));
  });
}
