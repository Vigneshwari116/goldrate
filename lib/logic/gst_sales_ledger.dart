import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/bill_line_item.dart';
import 'transaction_records.dart';

/// One sales bill row for the GST Sales Ledger report.
class GstSalesLedgerRow {
  GstSalesLedgerRow({
    required this.billNo,
    required this.billDate,
    required this.customerName,
    required this.gstin,
    required this.grossWeight,
    required this.netWeight,
    required this.totalWeight,
    required this.rate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
  });

  final int billNo;
  final String billDate;
  final String customerName;
  final String gstin;
  final double grossWeight;
  final double netWeight;
  final double totalWeight;
  final double rate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;

  static final _inr = NumberFormat('#,##0.00', 'en_IN');
  static final _wt3 = NumberFormat('#,##0.000', 'en_IN');
  static final _wt2 = NumberFormat('#,##0.00', 'en_IN');
  static final _rateFmt = NumberFormat('#,##0.00', 'en_IN');

  List<String> toCells() => [
        '$billNo',
        billDate,
        customerName,
        gstin.isEmpty ? '—' : gstin,
        '${_wt2.format(grossWeight)} GM',
        '${_wt3.format(netWeight)} GM',
        '${_wt2.format(totalWeight)} GM',
        _rateFmt.format(rate),
        _inr.format(taxableValue),
        _inr.format(cgst),
        _inr.format(sgst),
        _inr.format(igst),
        _inr.format(grandTotal),
      ];
}

class GstSalesLedgerTotals {
  const GstSalesLedgerTotals({
    required this.totalWeight,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
    required this.totalTaxable,
    required this.weightedRateNumerator,
    required this.netWeightSum,
  });

  final double totalWeight;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;
  final double totalTaxable;
  final double weightedRateNumerator;
  final double netWeightSum;

  double get averageRate =>
      netWeightSum > 0 ? weightedRateNumerator / netWeightSum : 0;

  static const zero = GstSalesLedgerTotals(
    totalWeight: 0,
    cgst: 0,
    sgst: 0,
    igst: 0,
    grandTotal: 0,
    totalTaxable: 0,
    weightedRateNumerator: 0,
    netWeightSum: 0,
  );

  GstSalesLedgerTotals add(GstSalesLedgerRow row) {
    return GstSalesLedgerTotals(
      totalWeight: totalWeight + row.totalWeight,
      cgst: cgst + row.cgst,
      sgst: sgst + row.sgst,
      igst: igst + row.igst,
      grandTotal: grandTotal + row.grandTotal,
      totalTaxable: totalTaxable + row.taxableValue,
      weightedRateNumerator: weightedRateNumerator + (row.rate * row.netWeight),
      netWeightSum: netWeightSum + row.netWeight,
    );
  }

  List<String> toFooterCells() {
    final inr = GstSalesLedgerRow._inr;
    final wt2 = GstSalesLedgerRow._wt2;
    final rateFmt = GstSalesLedgerRow._rateFmt;
    return [
      'TOTAL',
      '',
      '',
      '',
      '',
      '',
      '${wt2.format(totalWeight)} GM',
      rateFmt.format(averageRate),
      inr.format(totalTaxable),
      inr.format(cgst),
      inr.format(sgst),
      inr.format(igst),
      inr.format(grandTotal),
    ];
  }
}

class GstSalesLedgerReport {
  GstSalesLedgerReport._();

  static const headers = [
    'Bill No',
    'Date',
    'Customer',
    'GSTIN',
    'Gross Wt',
    'Net Wt',
    'Total Wt',
    'Rate',
    'Taxable',
    'CGST',
    'SGST',
    'IGST',
    'Grand Total',
  ];

  static const int grandTotalColumnIndex = 12;

  static List<GstSalesLedgerRow> rowsForTransactions(
    List<Map<String, dynamic>> transactions, {
    required bool Function(String? date) inDateRange,
    String transactionType = 'SALES',
  }) {
    final sales = transactions.where((r) {
      final type = normalizeTransactionType(
        (r['transactionType'] ?? '').toString(),
      );
      return type == transactionType && inDateRange(r['date']?.toString());
    }).toList();

    sales.sort((a, b) {
      final an = a['billNo'] as int? ?? 0;
      final bn = b['billNo'] as int? ?? 0;
      return an.compareTo(bn);
    });

    return sales.map(_rowFromBill).toList();
  }

  static GstSalesLedgerTotals totalsFor(List<GstSalesLedgerRow> rows) {
    var totals = GstSalesLedgerTotals.zero;
    for (final row in rows) {
      totals = totals.add(row);
    }
    return totals;
  }

  static GstSalesLedgerRow _rowFromBill(Map<String, dynamic> bill) {
    final items = _parseItems(bill);
    double cgst = 0;
    double sgst = 0;
    double igst = 0;
    double taxableFromItems = 0;
    double pureForRate = 0;
    double rateNumerator = 0;

    for (final item in items) {
      cgst += item.tax.cgstAmount;
      sgst += item.tax.sgstAmount;
      taxableFromItems += item.tax.taxableValue;
      final pure = item.pureWt;
      if (pure > 0) {
        pureForRate += pure;
        rateNumerator += pure * item.rate;
      }
      final igstRaw = (item.toJson()['igstAmount'] as num?)?.toDouble();
      if (igstRaw != null) igst += igstRaw;
    }

    final savedTaxable = _dbl(bill['totalTaxable']);
    final taxable =
        savedTaxable > 0 ? savedTaxable : taxableFromItems;

    final grand = _dbl(bill['grandTotal'], fallback: _dbl(bill['totalValue']));

    final gross = _dbl(bill['totalWt']);
    final net = _dbl(bill['totalPureWt']);
    final totalWt = gross > 0 ? gross : items.fold<double>(0, (s, i) => s + i.weight);

    final rate = pureForRate > 0 ? rateNumerator / pureForRate : 0.0;

    return GstSalesLedgerRow(
      billNo: bill['billNo'] as int? ?? 0,
      billDate: (bill['date'] ?? '').toString(),
      customerName: (bill['partyName'] ?? '').toString().trim(),
      gstin: (bill['partyGstin'] ?? '').toString().trim(),
      grossWeight: gross > 0 ? gross : totalWt,
      netWeight: net > 0 ? net : items.fold<double>(0, (s, i) => s + i.pureWt),
      totalWeight: totalWt,
      rate: rate,
      taxableValue: taxable,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      grandTotal: grand,
    );
  }

  static List<BillLineItem> _parseItems(Map<String, dynamic> bill) {
    try {
      final raw = bill['items'];
      if (raw == null) return [];
      final list = raw is String ? jsonDecode(raw) as List : raw as List;
      return list
          .map((e) => BillLineItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static double _dbl(Object? raw, {double fallback = 0}) {
    final v = double.tryParse((raw ?? '').toString());
    return v ?? fallback;
  }

  /// Tax components for one bill (sales or purchase).
  static ({
    double taxable,
    double cgst,
    double sgst,
    double igst,
    double grandTotal,
  }) taxBreakdownForBill(Map<String, dynamic> bill) {
    final row = _rowFromBill(bill);
    return (
      taxable: row.taxableValue,
      cgst: row.cgst,
      sgst: row.sgst,
      igst: row.igst,
      grandTotal: row.grandTotal,
    );
  }
}

/// GST Purchase Ledger — same columns as sales, supplier as party.
class GstPurchaseLedgerReport {
  GstPurchaseLedgerReport._();

  static const headers = [
    'Bill No',
    'Date',
    'Supplier',
    'GSTIN',
    'Gross Wt',
    'Net Wt',
    'Total Wt',
    'Rate',
    'Taxable',
    'CGST',
    'SGST',
    'IGST',
    'Grand Total',
  ];

  static const int grandTotalColumnIndex = 12;

  static List<GstSalesLedgerRow> rowsForTransactions(
    List<Map<String, dynamic>> transactions, {
    required bool Function(String? date) inDateRange,
  }) =>
      GstSalesLedgerReport.rowsForTransactions(
        transactions,
        inDateRange: inDateRange,
        transactionType: 'PURCHASE',
      );

  static GstSalesLedgerTotals totalsFor(List<GstSalesLedgerRow> rows) =>
      GstSalesLedgerReport.totalsFor(rows);
}
