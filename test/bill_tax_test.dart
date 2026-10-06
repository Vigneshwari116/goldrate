import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/logic/bill_tax.dart';

void main() {
  test('line tax defaults 1.5% CGST/SGST', () {
    final tax = BillLineTax.compute(pureWt: 100, rate: 1000);
    expect(tax.taxableValue, 100000);
    expect(tax.cgstAmount, 1500);
    expect(tax.sgstAmount, 1500);
    expect(tax.inclusiveAmount, 103000);
  });

  test('grand total with TDS and round off', () {
    final lines = [
      BillLineTax.compute(pureWt: 350, rate: 15631.07),
    ];
    final totals = BillTaxTotals.compute(
      lines: lines,
      tdsAmount: 5471,
    );
    expect(totals.totalTaxable, closeTo(5470874.5, 1));
    expect(totals.grandTotal, totals.totalInclusive - 5471 + totals.roundOff);
  });

  test('amount in words', () {
    expect(
      amountInWordsIndian(5629529),
      contains('Lakh'),
    );
  });

  test('default item descriptions for invoice lines', () {
    expect(defaultItemDescriptionForType('GWT'), 'Gold Jewellery');
    expect(defaultItemDescriptionForType('FWT'), 'Gold Jewellery (Fine)');
    expect(defaultItemDescriptionForType('KWT'), 'Gold Jewellery (Kacha)');
    expect(defaultItemDescriptionForType('SWT'), 'Silver Jewellery');
    expect(
      defaultItemDescriptionForType('GWT'),
      isNot(contains('Bullion')),
    );
  });

  test('group tax by HSN', () {
    final rows = groupTaxByHsn([
      (hsn: '7113', tax: BillLineTax.compute(pureWt: 10, rate: 100)),
      (hsn: '7113', tax: BillLineTax.compute(pureWt: 5, rate: 100)),
      (hsn: '7114', tax: BillLineTax.compute(pureWt: 2, rate: 50)),
    ]);
    expect(rows.length, 2);
    expect(rows.firstWhere((r) => r.hsn == '7113').taxable, 1500);
  });
}
