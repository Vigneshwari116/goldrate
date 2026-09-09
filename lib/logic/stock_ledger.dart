import 'dart:convert';

import 'package:intl/intl.dart';

import 'transaction_records.dart';

/// Weight type codes used on purchase/sales entry screens.
const kStockWeightTypes = ['GWT', 'FWT', 'KWT', 'SWT'];

/// One bill row in the Purchase or Sales box on the Daily Sales Report.
class DailySalesBillRow {
  final String billLabel;
  final String billNo;
  final String name;
  final String date;
  final Map<String, double> weights;

  const DailySalesBillRow({
    required this.billLabel,
    required this.billNo,
    required this.name,
    required this.date,
    required this.weights,
  });
}

/// Live stock summary for a date range on the Daily Sales Report.
class StockLedgerSummary {
  final Map<String, double> opening;
  final List<DailySalesBillRow> purchases;
  final List<DailySalesBillRow> sales;
  final Map<String, double> purchaseTotals;
  final Map<String, double> salesTotals;
  final Map<String, double> closing;

  const StockLedgerSummary({
    required this.opening,
    required this.purchases,
    required this.sales,
    required this.purchaseTotals,
    required this.salesTotals,
    required this.closing,
  });

  /// All in-range rows (legacy helper for record counts).
  int get rowCount => purchases.length + sales.length;
}

Map<String, double> _emptyWeights() => {
      for (final t in kStockWeightTypes) t: 0.0,
    };

Map<String, double> _copyWeights(Map<String, double> source) =>
    Map<String, double>.from(source);

/// Maps the one-time [opening_weight] baseline onto GWT/FWT/KWT/SWT.
Map<String, double> openingBaselineFromRow(Map<String, dynamic>? opening) {
  if (opening == null) return _emptyWeights();
  return {
    'GWT': _openingField(opening, 'gPureWt', 'g_pure_wt'),
    'FWT': _openingField(opening, 'fineWt', 'fine_wt'),
    'KWT': _openingField(opening, 'kachaWt', 'kacha_wt'),
    'SWT': _openingField(opening, 'silverWt', 'silver_wt'),
  };
}

double _openingField(
  Map<String, dynamic> opening,
  String camelKey,
  String snakeKey,
) =>
    _parseDouble(opening[camelKey] ?? opening[snakeKey]);

double _parseDouble(dynamic raw) =>
    double.tryParse((raw ?? '').toString()) ?? 0;

DateTime? _parseBillDate(String? raw, DateFormat fmt) {
  if (raw == null || raw.isEmpty) return null;
  final text = raw.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
    try {
      return DateFormat('yyyy-MM-dd').parse(text);
    } catch (_) {}
  }
  try {
    return fmt.parse(text);
  } catch (_) {
    for (final pattern in ['dd/MM/yyyy', 'dd-MM-yyyy']) {
      try {
        return DateFormat(pattern).parse(text);
      } catch (_) {}
    }
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

/// Bill line weights for Daily Sales boxes — **items only**.
///
/// Payment / old-gold trade-in lines (`paymentItems`, O.GWT etc.) are
/// excluded from Purchase/Sales boxes and from Closing Stock.
Map<String, double> billBoxWeights(Map<String, dynamic> bill) {
  return _sumItemWeightsByType(bill['items']);
}

/// Payment / receipt line weights by type (GWT/FWT/KWT/SWT only).
///
/// Old-gold trade-in types (`O.GWT` etc.) and cash lines are excluded.
Map<String, double> billPaymentBoxWeights(Map<String, dynamic> bill) {
  return _sumItemWeightsByType(bill['paymentItems']);
}

Map<String, double> _sumItemWeightsByType(dynamic raw) {
  final totals = _emptyWeights();
  for (final item in _decodeItems(raw)) {
    if (item is! Map) continue;
    final type = (item['type'] ?? '').toString().trim().toUpperCase();
    if (!totals.containsKey(type)) continue;
    final weight = (item['weight'] as num?)?.toDouble() ??
        _parseDouble(item['weight']);
    totals[type] = totals[type]! + weight;
  }
  return totals;
}

Map<String, double> emptyStockWeights() => _emptyWeights();

Map<String, double> copyStockWeights(Map<String, double> source) =>
    _copyWeights(source);

void addStockWeights(Map<String, double> totals, Map<String, double> delta) {
  _addWeights(totals, delta);
}

double sumStockWeights(Map<String, double> weights) {
  var total = 0.0;
  for (final type in kStockWeightTypes) {
    total += weights[type] ?? 0;
  }
  return total;
}

Map<String, double> sumStockWeightMaps(
  Iterable<Map<String, double>> maps,
) {
  final totals = _emptyWeights();
  for (final map in maps) {
    _addWeights(totals, map);
  }
  return totals;
}

/// Four table cells for GWT/FWT/KWT/SWT columns.
List<String> formatWeightRowCells(
  Map<String, double> weights, {
  bool blankWhenZero = true,
}) {
  return kStockWeightTypes
      .map(
        (type) => formatStockWeight(
          weights[type] ?? 0,
          blankWhenZero: blankWhenZero,
        ),
      )
      .toList();
}

/// Eight table cells: receipt weights then issue weights.
List<String> formatReceiptIssueWeightCells(
  Map<String, double> receipt,
  Map<String, double> issue, {
  bool blankWhenZero = true,
}) {
  return [
    ...formatWeightRowCells(receipt, blankWhenZero: blankWhenZero),
    ...formatWeightRowCells(issue, blankWhenZero: blankWhenZero),
  ];
}

void _addWeights(Map<String, double> totals, Map<String, double> delta) {
  for (final type in kStockWeightTypes) {
    totals[type] = totals[type]! + (delta[type] ?? 0);
  }
}

void _subtractWeights(Map<String, double> totals, Map<String, double> delta) {
  for (final type in kStockWeightTypes) {
    totals[type] = totals[type]! - (delta[type] ?? 0);
  }
}

Map<String, double> sumBillWeights(Iterable<DailySalesBillRow> rows) {
  final totals = _emptyWeights();
  for (final row in rows) {
    _addWeights(totals, row.weights);
  }
  return totals;
}

/// Builds the live stock ledger for the Daily Sales Report.
///
/// Opening = baseline + purchase items before range − sales items before range.
/// Closing = opening + purchase box totals − sales box totals (items only).
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
  final purchases = <DailySalesBillRow>[];
  final sales = <DailySalesBillRow>[];

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
    final type =
        normalizeTransactionType((bill['transactionType'] ?? '').toString());
    final isPurchase = type == 'PURCHASE';
    final isSales = type == 'SALES';
    if (!isPurchase && !isSales) continue;

    final prefix = isPurchase ? 'PUR' : 'SAL';
    final billNo = (bill['billNo'] ?? '').toString();
    final weights = billBoxWeights(bill);

    final beforeRange = !allHistory && billDay.isBefore(rangeFrom);
    final inRange = allHistory ||
        (!billDay.isBefore(rangeFrom) && !billDay.isAfter(rangeTo));

    if (beforeRange) {
      if (isPurchase) {
        _addWeights(opening, weights);
      } else {
        _subtractWeights(opening, weights);
      }
    }

    if (inRange) {
      final row = DailySalesBillRow(
        billLabel: '$prefix$billNo',
        billNo: billNo,
        name: (bill['partyName'] ?? '').toString(),
        date: (bill['date'] ?? '').toString(),
        weights: weights,
      );
      if (isPurchase) {
        purchases.add(row);
      } else {
        sales.add(row);
      }
    }
  }

  final purchaseTotals = sumBillWeights(purchases);
  final salesTotals = sumBillWeights(sales);
  final closing = _copyWeights(opening);
  _addWeights(closing, purchaseTotals);
  _subtractWeights(closing, salesTotals);

  return StockLedgerSummary(
    opening: opening,
    purchases: purchases,
    sales: sales,
    purchaseTotals: purchaseTotals,
    salesTotals: salesTotals,
    closing: closing,
  );
}

/// Formats a gross weight for the stock table.
String formatStockWeight(double value, {bool blankWhenZero = true}) {
  if (value == 0) return blankWhenZero ? '' : '0.000';
  final fixed = value.toStringAsFixed(3);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
