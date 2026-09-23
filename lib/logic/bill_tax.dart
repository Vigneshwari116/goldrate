import 'dart:math';

/// GST/totals for one bill line (amount = pureWt × rate).
class BillLineTax {
  final double taxableValue;
  final double cgstPercent;
  final double sgstPercent;
  final double cgstAmount;
  final double sgstAmount;
  final double inclusiveAmount;

  const BillLineTax({
    required this.taxableValue,
    required this.cgstPercent,
    required this.sgstPercent,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.inclusiveAmount,
  });

  static BillLineTax compute({
    required double pureWt,
    required double rate,
    double cgstPercent = 1.5,
    double sgstPercent = 1.5,
  }) {
    final taxable = pureWt * rate;
    final cgst = taxable * cgstPercent / 100;
    final sgst = taxable * sgstPercent / 100;
    return BillLineTax(
      taxableValue: taxable,
      cgstPercent: cgstPercent,
      sgstPercent: sgstPercent,
      cgstAmount: cgst,
      sgstAmount: sgst,
      inclusiveAmount: taxable + cgst + sgst,
    );
  }
}

class BillTaxTotals {
  final double totalTaxable;
  final double totalInclusive;
  final double roundOff;
  final double grandTotal;

  const BillTaxTotals({
    required this.totalTaxable,
    required this.totalInclusive,
    required this.roundOff,
    required this.grandTotal,
  });

  static BillTaxTotals compute({
    required List<BillLineTax> lines,
    double tdsAmount = 0,
    double tcsAmount = 0,
  }) {
    final taxable = lines.fold<double>(0, (s, l) => s + l.taxableValue);
    final inclusive = lines.fold<double>(0, (s, l) => s + l.inclusiveAmount);
    final beforeRound = inclusive - tdsAmount + tcsAmount;
    final rounded = beforeRound.roundToDouble();
    final roundOff = rounded - beforeRound;
    return BillTaxTotals(
      totalTaxable: taxable,
      totalInclusive: inclusive,
      roundOff: roundOff,
      grandTotal: rounded,
    );
  }
}

/// HSN defaults per metal type (overridable in Master settings).
const Map<String, String> kDefaultHsnByItemType = {
  'GWT': '7113',
  'FWT': '7113',
  'KWT': '7113',
  'SWT': '7114',
};

String itemTypeDescription(String type) {
  switch (type) {
    case 'GWT':
      return 'Gold (G.Pure)';
    case 'FWT':
      return 'Fine Gold';
    case 'KWT':
      return 'Kacha Gold';
    case 'SWT':
      return 'Silver';
    default:
      return type;
  }
}

/// Indian numbering — e.g. "INR Fifty Six Lakh ... Only".
String amountInWordsIndian(double amount) {
  final rupees = amount.round();
  if (rupees == 0) return 'INR Zero Only';
  final negative = rupees < 0;
  final n = negative ? -rupees : rupees;
  final words = _wordsUnderCrore(n);
  final prefix = negative ? 'INR Minus ' : 'INR ';
  return '$prefix$words Only';
}

/// Rupees + paise for tax summary footers (e.g. "... Twenty Two paise Only").
String amountInWordsIndianWithPaise(double amount) {
  final negative = amount < 0;
  final abs = negative ? -amount : amount;
  final rupees = abs.floor();
  final paise = ((abs - rupees) * 100).round().clamp(0, 99);
  final rupeeWords =
      rupees == 0 ? 'Zero' : _wordsUnderCrore(rupees);
  final prefix = negative ? 'INR Minus ' : 'INR ';
  if (paise == 0) {
    return '$prefix$rupeeWords Only';
  }
  final paiseWords = _twoDigitWords(paise);
  return '$prefix$rupeeWords and $paiseWords ${_paiseLabel(paise)} Only';
}

String _paiseLabel(int paise) {
  return paise == 1 ? 'paisa' : 'paise';
}

/// Description line on the reference tax invoice PDF.
String invoicePdfLineDescription(String type) {
  switch (type) {
    case 'GWT':
      return 'Gold Bullion_999';
    case 'FWT':
      return 'Fine Gold';
    case 'KWT':
      return 'Kacha Gold';
    case 'SWT':
      return 'Silver Bullion';
    default:
      return type;
  }
}

String _wordsUnderCrore(int n) {
  if (n >= 10000000) {
    final crores = n ~/ 10000000;
    final rest = n % 10000000;
    return '${_twoDigitWords(crores)} Crore${rest > 0 ? ' ${_wordsUnderLakh(rest)}' : ''}';
  }
  return _wordsUnderLakh(n);
}

String _wordsUnderLakh(int n) {
  if (n >= 100000) {
    final lakhs = n ~/ 100000;
    final rest = n % 100000;
    return '${_twoDigitWords(lakhs)} Lakh${rest > 0 ? ' ${_wordsUnderThousand(rest)}' : ''}';
  }
  return _wordsUnderThousand(n);
}

String _wordsUnderThousand(int n) {
  if (n >= 1000) {
    final thousands = n ~/ 1000;
    final rest = n % 1000;
    return '${_twoDigitWords(thousands)} Thousand${rest > 0 ? ' ${_wordsUnderHundred(rest)}' : ''}';
  }
  return _wordsUnderHundred(n);
}

String _wordsUnderHundred(int n) {
  if (n >= 100) {
    final hundreds = n ~/ 100;
    final rest = n % 100;
    return '${_unit(hundreds)} Hundred${rest > 0 ? ' ${_twoDigitWords(rest)}' : ''}';
  }
  return _twoDigitWords(n);
}

String _twoDigitWords(int n) {
  if (n < 20) return _unit(n);
  final tens = n ~/ 10;
  final ones = n % 10;
  const tensNames = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];
  if (ones == 0) return tensNames[tens];
  return '${tensNames[tens]} ${_unit(ones)}';
}

String _unit(int n) {
  const names = [
    'Zero',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  return names[min(n, names.length - 1)];
}

/// Groups line items by HSN for the tax summary table on the invoice.
class HsnTaxSummaryRow {
  final String hsn;
  final double taxable;
  final double cgstPercent;
  final double cgstAmount;
  final double sgstPercent;
  final double sgstAmount;

  HsnTaxSummaryRow({
    required this.hsn,
    required this.taxable,
    required this.cgstPercent,
    required this.cgstAmount,
    required this.sgstPercent,
    required this.sgstAmount,
  });

  double get totalTax => cgstAmount + sgstAmount;
}

List<HsnTaxSummaryRow> groupTaxByHsn(
  List<({String hsn, BillLineTax tax})> lines,
) {
  final map = <String, HsnTaxSummaryRow>{};
  for (final line in lines) {
    final key = line.hsn;
    final existing = map[key];
    if (existing == null) {
      map[key] = HsnTaxSummaryRow(
        hsn: key,
        taxable: line.tax.taxableValue,
        cgstPercent: line.tax.cgstPercent,
        cgstAmount: line.tax.cgstAmount,
        sgstPercent: line.tax.sgstPercent,
        sgstAmount: line.tax.sgstAmount,
      );
    } else {
      map[key] = HsnTaxSummaryRow(
        hsn: key,
        taxable: existing.taxable + line.tax.taxableValue,
        cgstPercent: line.tax.cgstPercent,
        cgstAmount: existing.cgstAmount + line.tax.cgstAmount,
        sgstPercent: line.tax.sgstPercent,
        sgstAmount: existing.sgstAmount + line.tax.sgstAmount,
      );
    }
  }
  final rows = map.values.toList();
  rows.sort((a, b) => a.hsn.compareTo(b.hsn));
  return rows;
}
