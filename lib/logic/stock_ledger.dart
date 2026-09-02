import 'dart:convert';

import 'package:intl/intl.dart';

/// Weight type codes used on purchase/sales entry screens.
const kStockWeightTypes = ['GWT', 'FWT', 'KWT', 'SWT'];

/// One purchase or issue line in the stock summary table.
class StockLedgerLine {
  final String name;
  final String billNo;
  final String date;
  final String type;
  final double weight;

  const StockLedgerLine({
    required this.name,
    required this.billNo,
    required this.date,
    required this.type,
    required this.weight,
  });
}

/// Live stock summary for a date range on the Daily Sales Report.
class StockLedgerSummary {
  final Map<String, double> opening;
  final List<StockLedgerLine> purchases;
  final List<StockLedgerLine> issues;
  final Map<String, double> closing;

  const StockLedgerSummary({
    required this.opening,
    required this.purchases,
    required this.issues,
    required this.closing,
  });
}

Map<String, double> _emptyWeights() => {
      for (final t in kStockWeightTypes) t: 0.0,
    };

/// Maps the one-time [opening_weight] baseline onto GWT/FWT/KWT/SWT.
///
/// Client-confirmed: values in `gPureWt`, `fineWt`, `kachaWt`, and `silverWt`
/// are **gross/raw weight** despite the "Pure" in `gPureWt`'s column name — no
/// touch conversion is applied here or on the Opening Weight entry screen.
///
/// TODO(pre-existing): [DatabaseHelper.getCurrentStock] and `/api/stock/current`
/// apply `item.pureWt` against these same opening columns (gross baseline vs
/// pure movements). Fix separately — out of scope for the stock summary PR.
Map<String, double> openingBaselineFromRow(Map<String, dynamic>? opening) {
  if (opening == null) return _emptyWeights();
  return {
    'GWT': _parseDouble(opening['gPureWt']),
    'FWT': _parseDouble(opening['fineWt']),
    'KWT': _parseDouble(opening['kachaWt']),
    'SWT': _parseDouble(opening['silverWt']),
  };
}

double _parseDouble(dynamic raw) =>
    double.tryParse((raw ?? '').toString()) ?? 0;

DateTime? _parseBillDate(String? raw, DateFormat fmt) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return fmt.parse(raw);
  } catch (_) {
    return null;
  }
}

List<dynamic> _decodeItems(dynamic raw) {
  if (raw is List) return raw;
  try {
    return jsonDecode((raw ?? '[]').toString()) as List<dynamic>;
  } catch (_) {
    return const [];
  }
}

/// Expands a bill into one [StockLedgerLine] per weight row (raw weight only).
List<StockLedgerLine> _linesFromBill(Map<String, dynamic> bill) {
  final isPurchase = (bill['transactionType'] ?? '').toString() == 'PURCHASE';
  final prefix = isPurchase ? 'PUR' : 'SAL';
  final billNo = '$prefix-${bill['billNo']}';
  final name = (bill['partyName'] ?? '').toString();
  final date = (bill['date'] ?? '').toString();
  final lines = <StockLedgerLine>[];

  for (final item in _decodeItems(bill['items'])) {
    if (item is! Map) continue;
    final type = (item['type'] ?? '').toString();
    if (!kStockWeightTypes.contains(type)) continue;
    final weight = (item['weight'] as num?)?.toDouble() ??
        _parseDouble(item['weight']);
    if (weight == 0) continue;
    lines.add(StockLedgerLine(
      name: name,
      billNo: billNo,
      date: date,
      type: type,
      weight: weight,
    ));
  }
  return lines;
}

void _applyBillWeights(
  Map<String, dynamic> bill,
  Map<String, double> totals, {
  required int sign,
}) {
  for (final item in _decodeItems(bill['items'])) {
    if (item is! Map) continue;
    final type = (item['type'] ?? '').toString();
    if (!totals.containsKey(type)) continue;
    final weight = (item['weight'] as num?)?.toDouble() ??
        _parseDouble(item['weight']);
    totals[type] = totals[type]! + (sign * weight);
  }
}

Map<String, double> _sumLines(Iterable<StockLedgerLine> lines) {
  final totals = _emptyWeights();
  for (final line in lines) {
    totals[line.type] = totals[line.type]! + line.weight;
  }
  return totals;
}

/// Builds the live stock ledger for the Daily Sales Report.
///
/// Opening for [from] = opening_weight baseline + purchases before [from]
/// − issues before [from]. Closing = opening + purchases in range − issues
/// in range. Uses raw [weight] from each line item, never pureWt.
StockLedgerSummary buildStockLedgerSummary({
  required List<Map<String, dynamic>> transactions,
  required Map<String, dynamic>? openingWeight,
  required DateTime from,
  required DateTime to,
  bool allHistory = false,
  DateFormat? dateFormat,
}) {
  final fmt = dateFormat ?? DateFormat('dd-MM-yyyy');
  final rangeFrom = DateTime(from.year, from.month, from.day);
  final rangeTo = DateTime(to.year, to.month, to.day);

  final opening = openingBaselineFromRow(openingWeight);
  final purchases = <StockLedgerLine>[];
  final issues = <StockLedgerLine>[];

  final sorted = [...transactions]..sort((a, b) {
      final ad = _parseBillDate(a['date']?.toString(), fmt);
      final bd = _parseBillDate(b['date']?.toString(), fmt);
      if (ad == null && bd == null) {
        return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      final cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
      return (a['billNo'] as int? ?? 0).compareTo(b['billNo'] as int? ?? 0);
    });

  for (final bill in sorted) {
    final day = _parseBillDate(bill['date']?.toString(), fmt);
    if (day == null) continue;
    final billDay = DateTime(day.year, day.month, day.day);
    final isPurchase =
        (bill['transactionType'] ?? '').toString() == 'PURCHASE';
    final sign = isPurchase ? 1 : -1;

    final beforeRange = !allHistory && billDay.isBefore(rangeFrom);
    final inRange = allHistory ||
        (!billDay.isBefore(rangeFrom) && !billDay.isAfter(rangeTo));

    if (beforeRange) {
      _applyBillWeights(bill, opening, sign: sign);
    }
    if (inRange) {
      final lines = _linesFromBill(bill);
      if (isPurchase) {
        purchases.addAll(lines);
      } else {
        issues.addAll(lines);
      }
    }
  }

  final closing = Map<String, double>.from(opening);
  final purchaseTotals = _sumLines(purchases);
  final issueTotals = _sumLines(issues);
  for (final type in kStockWeightTypes) {
    closing[type] =
        closing[type]! + purchaseTotals[type]! - issueTotals[type]!;
  }

  return StockLedgerSummary(
    opening: opening,
    purchases: purchases,
    issues: issues,
    closing: closing,
  );
}

/// Formats a gross weight for the stock table.
///
/// [blankWhenZero] is `true` for Opening/Closing rows (blank cell). Use
/// `false` for Purchase/Issue transaction rows (shows `0.000` per mockup).
String formatStockWeight(double value, {bool blankWhenZero = true}) {
  if (value == 0) return blankWhenZero ? '' : '0.000';
  final fixed = value.toStringAsFixed(3);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
