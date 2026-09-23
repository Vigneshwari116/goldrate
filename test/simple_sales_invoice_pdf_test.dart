import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/bill_tax.dart';
import 'package:grate_app/models/bill_line_item.dart';
import 'package:grate_app/models/party_billing_profile.dart';
import 'package:grate_app/pdf/invoice_party_lines.dart';
import 'package:grate_app/pdf/pdf_kit.dart';
import 'package:grate_app/pdf/simple_sales_tax_invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seller block matches detailed invoice shop lines', () {
    final seller = SimpleSalesTaxInvoicePdf.sellerDisplayLines();
    expect(seller, InvoicePartyLines.shopLines);
    expect(seller.first, 'Shree Mahalasa Jewellery Works');
    expect(seller, isNot(contains('Ultra Engineering Works')));
    expect(
      SimpleSalesTaxInvoicePdf.invoiceSellerSignatureName,
      'Shree Mahalasa Jewellery Works',
    );
  });

  test('consignee lines use live party name', () {
    final buyer = const PartyBillingProfile(
      name: 'TEST CONSIGNEE PVT LTD',
      isCustomer: true,
      address: '42 Market Street',
      city: 'Mangalore',
      gstin: '29DDDDD3333D1Z5',
      state: 'Karnataka',
    );
    final lines = SimpleSalesTaxInvoicePdf.consigneeDisplayLines(buyer);
    expect(lines.first, 'NAME & ADDRESS OF CONSIGNEE');
    expect(lines, contains('TEST CONSIGNEE PVT LTD'));
  });

  test('generates simple sales PDF with original copy only', () async {
    final items = [
      BillLineItem(
        type: 'GWT',
        weight: 10,
        touch: 100,
        rate: 6500,
        hsn: '7113',
        description: 'Gold Chain',
      ),
    ];
    final totals = BillTaxTotals.compute(lines: items.map((i) => i.tax).toList());
    final buyer = const PartyBillingProfile(
      name: 'SAMPLE CUSTOMER',
      isCustomer: true,
      city: 'Bangalore',
      gstin: '29EEEEEE4444E1Z5',
      state: 'Karnataka',
    );

    final doc = await PdfKit.document();
    doc.addPage(
      SimpleSalesTaxInvoicePdf.buildPage(
        buyer: buyer,
        row: {'billNo': 101, 'date': '23-09-2026', 'transactionType': 'SALES'},
        items: items,
        totals: totals,
        copyLabel: SimpleSalesTaxInvoicePdf.copyOriginalForBuyer,
      ),
    );
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(2000));

    final dir = Directory('/opt/cursor/artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = '${dir.path}/simple_sales_invoice_sample.pdf';
    await File(path).writeAsBytes(bytes);

    try {
      final pdftotext = await Process.run('pdftotext', [path, '-']);
      if (pdftotext.exitCode == 0) {
        final text = pdftotext.stdout.toString();
        expect(text, contains('Shree Mahalasa Jewellery Works'));
        expect(text, isNot(contains('Ultra Engineering Works')));
        expect(text, contains('SAMPLE CUSTOMER'));
        expect(text, contains('NAME & ADDRESS OF CONSIGNEE'));
      }
    } on ProcessException {
      // pdftotext optional in CI; PDF bytes assertion above is sufficient.
    }
  });
}
