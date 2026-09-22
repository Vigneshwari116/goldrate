import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// PdfKit loads font assets from the Flutter bundle.
import 'package:grate_app/logic/bill_tax.dart';
import 'package:grate_app/models/bill_line_item.dart';
import 'package:grate_app/pdf/pdf_kit.dart';
import 'package:grate_app/pdf/sales_tax_invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates reference-style sales tax invoice PDF', () async {
    // Mirrors reference NAMITHA #97: 350 GM @ 15631.07, HSN 71081300, TDS 5471
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
    final doc = await PdfKit.document();
    doc.addPage(
      SalesTaxInvoicePdf.buildPage(
        row: {
          'billNo': 97,
          'date': '20-Aug-26',
        },
        items: items,
        totals: totals,
        tdsApplicable: true,
        tcsApplicable: false,
        tdsAmount: 5471,
        tcsAmount: 0,
      ),
    );
    final bytes = await doc.save();
    final dir = Directory('/opt/cursor/artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/namitha_bullion_97_accounts_bill.pdf');
    await file.writeAsBytes(bytes);

    expect(bytes.length, greaterThan(2000));
    expect(totals.grandTotal, closeTo(5629529, 2));
    expect(items.first.tax.taxableValue, closeTo(5470874.5, 1));
  });
}
