import 'dart:convert';

import 'package:intl/intl.dart';

/// Bill-level marker: customer old gold received on a sale receipt.
const kReceiptPurposeOldGold = 'old_gold';

/// One row in the Old Gold Report.
class OldGoldReportRow {
  final String saleNo;
  final String date;
  final String name;
  final double goldWt;
  final double kachaWt;
  final double pureWt;
  final double silverWt;
  final double cash;
  final double total;

  const OldGoldReportRow({
    required this.saleNo,
    required this.date,
    required this.name,
    required this.goldWt,
    required this.kachaWt,
    required this.pureWt,
    required this.silverWt,
    required this.cash,
    required this.total,
  });

  List<String> toTableRow() => [
        saleNo,
        date,
        _fmtWt(goldWt),
        _fmtWt(kachaWt),
        _fmtWt(pureWt),
        _fmtWt(silverWt),
        cash > 0 ? cash.toStringAsFixed(2) : '',
        name,
        total > 0 ? total.toStringAsFixed(2) : '',
      ];
}

class OldGoldTotals {
  final double goldWt;
  final double kachaWt;
  final double pureWt;
  final double silverWt;
  final double cash;
  final double total;

  const OldGoldTotals({
    this.goldWt = 0,
    this.kachaWt = 0,
    this.pureWt = 0,
    this.silverWt = 0,
    this.cash = 0,
    this.total = 0,
  });

  OldGoldTotals operator +(OldGoldTotals other) => OldGoldTotals(
        goldWt: goldWt + other.goldWt,
        kachaWt: kachaWt + other.kachaWt,
        pureWt: pureWt + other.pureWt,
        silverWt: silverWt + other.silverWt,
        cash: cash + other.cash,
        total: total + other.total,
      );

  List<String> bookendRow(String label) => [
        '',
        '',
        _fmtWt(goldWt),
        _fmtWt(kachaWt),
        _fmtWt(pureWt),
        _fmtWt(silverWt),
        cash > 0 ? cash.toStringAsFixed(2) : '',
        label,
        total > 0 ? total.toStringAsFixed(2) : '',
      ];
}

class OldGoldReport {
  final OldGoldTotals opening;
  final List<OldGoldReportRow> rows;
  final OldGoldTotals closing;

  const OldGoldReport({
    required this.opening,
    required this.rows,
    required this.closing,
  });
}

String _fmtWt(double value) {
  if (value == 0) return '';
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

List<dynamic> _decodeItems(dynamic raw) {
  if (raw is List) return raw;
  try {
    return jsonDecode((raw ?? '[]').toString()) as List<dynamic>;
  } catch (_) {
    return const [];
  }
}

double _parseDouble(dynamic raw) =>
    double.tryParse((raw ?? '').toString()) ?? 0;

DateTime? _parseDate(String? raw, DateFormat fmt) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return fmt.parse(raw);
  } catch (_) {
    return null;
  }
}

bool _isOldGoldSale(Map<String, dynamic> bill) {
  if ((bill['transactionType'] ?? '').toString() != 'SALES') return false;
  return (bill['receiptPurpose'] ?? '').toString() == kReceiptPurposeOldGold;
}

OldGoldTotals _totalsFromPaymentItems(
  List<dynamic> items, {
  required double goldRate,
}) {
  var goldWt = 0.0;
  var kachaWt = 0.0;
  var pureWt = 0.0;
  var silverWt = 0.0;
  var cash = 0.0;
  var total = 0.0;

  for (final raw in items) {
    if (raw is! Map) continue;
    final type = (raw['type'] ?? '').toString();
    if (type == 'CASH') {
      final amt = _parseDouble(raw['cashAmount']);
      cash += amt;
      total += amt;
      continue;
    }
    final weight = _parseDouble(raw['weight']);
    final linePure = _parseDouble(raw['pureWt']);
    final rate = _parseDouble(raw['rate']);
    final value = linePure * (rate > 0 ? rate : goldRate);
    total += value;

    switch (type) {
      case 'GWT':
        goldWt += weight;
      case 'FWT':
        pureWt += weight;
      case 'KWT':
        kachaWt += weight;
      case 'SWT':
        silverWt += weight;
    }
  }

  return OldGoldTotals(
    goldWt: goldWt,
    kachaWt: kachaWt,
    pureWt: pureWt,
    silverWt: silverWt,
    cash: cash,
    total: total,
  );
}

OldGoldReportRow _rowFromBill(
  Map<String, dynamic> bill, {
  required double goldRate,
}) {
  final items = _decodeItems(bill['paymentItems']);
  final totals = _totalsFromPaymentItems(items, goldRate: goldRate);
  return OldGoldReportRow(
    saleNo: 'SAL-${bill['billNo']}',
    date: (bill['date'] ?? '').toString(),
    name: (bill['partyName'] ?? '').toString(),
    goldWt: totals.goldWt,
    kachaWt: totals.kachaWt,
    pureWt: totals.pureWt,
    silverWt: totals.silverWt,
    cash: totals.cash,
    total: totals.total,
  );
}

/// Builds the Old Gold Report for sales marked with [kReceiptPurposeOldGold].
OldGoldReport buildOldGoldReport({
  required List<Map<String, dynamic>> transactions,
  required DateTime from,
  required DateTime to,
  bool allHistory = false,
  double goldRate = 0,
  DateFormat? dateFormat,
}) {
  final fmt = dateFormat ?? DateFormat('dd-MM-yyyy');
  final rangeFrom = DateTime(from.year, from.month, from.day);
  final rangeTo = DateTime(to.year, to.month, to.day);

  final oldGoldSales = transactions.where(_isOldGoldSale).toList()
    ..sort((a, b) {
      final ad = _parseDate(a['date']?.toString(), fmt);
      final bd = _parseDate(b['date']?.toString(), fmt);
      if (ad == null && bd == null) {
        return (a['billNo'] as int? ?? 0).compareTo(b['billNo'] as int? ?? 0);
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      final cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
      return (a['billNo'] as int? ?? 0).compareTo(b['billNo'] as int? ?? 0);
    });

  var opening = const OldGoldTotals();
  final rows = <OldGoldReportRow>[];
  var inRangeSum = const OldGoldTotals();

  for (final bill in oldGoldSales) {
    final day = _parseDate(bill['date']?.toString(), fmt);
    if (day == null) continue;
    final billDay = DateTime(day.year, day.month, day.day);
    final row = _rowFromBill(bill, goldRate: goldRate);
    final rowTotals = OldGoldTotals(
      goldWt: row.goldWt,
      kachaWt: row.kachaWt,
      pureWt: row.pureWt,
      silverWt: row.silverWt,
      cash: row.cash,
      total: row.total,
    );

    final beforeRange = !allHistory && billDay.isBefore(rangeFrom);
    final inRange = allHistory ||
        (!billDay.isBefore(rangeFrom) && !billDay.isAfter(rangeTo));

    if (beforeRange) opening = opening + rowTotals;
    if (inRange) {
      rows.add(row);
      inRangeSum = inRangeSum + rowTotals;
    }
  }

  return OldGoldReport(
    opening: opening,
    rows: rows,
    closing: opening + inRangeSum,
  );
}
