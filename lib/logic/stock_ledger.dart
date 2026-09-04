import 'dart:convert';

import 'package:intl/intl.dart';

/// Weight type codes used on purchase/sales entry screens.
const kStockWeightTypes = ['GWT', 'FWT', 'KWT', 'SWT'];

/// One transaction row in the merged stock summary table.
class StockLedgerRow {
  final String label;
  final Map<String, double> issueWeights;
  final String name;
  final String billNo;
  final String date;
  final Map<String, double> receiptWeights;

  const StockLedgerRow({
    required this.label,
    required this.issueWeights,
    required this.name,
    required this.billNo,
    required this.date,
    required this.receiptWeights,
  });
}

/// Live stock summary for a date range on the Daily Sales Report.
class StockLedgerSummary {
  final Map<String, double> opening;
  final List<StockLedgerRow> rows;
  final Map<String, double> closing;

  const StockLedgerSummary({
    required this.opening,
    required this.rows,
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

String _normalizeItemType(String raw) {
  final type = raw.trim().toUpperCase();
  if (type.startsWith('O.')) return type.substring(2);
  return type;
}

Map<String, double> _weightsFromItems(dynamic raw) {
  final totals = _emptyWeights();
  for (final item in _decodeItems(raw)) {
    if (item is! Map) continue;
    final type = _normalizeItemType((item['type'] ?? '').toString());
    if (!totals.containsKey(type)) continue;
    final weight = (item['weight'] as num?)?.toDouble() ??
        _parseDouble(item['weight']);
    totals[type] = totals[type]! + weight;
  }
  return totals;
}

void _applyNetChange(
  Map<String, double> totals,
  Map<String, double> issue,
  Map<String, double> receipt,
) {
  for (final type in kStockWeightTypes) {
    totals[type] = totals[type]! + receipt[type]! - issue[type]!;
  }
}

/// Issue/receipt sides for a bill: sales issue [items] and receipt
/// [paymentItems]; purchases receipt [items] and issue [paymentItems].
({Map<String, double> issue, Map<String, double> receipt}) _billSides(
  Map<String, dynamic> bill,
) {
  final isPurchase =
      (bill['transactionType'] ?? '').toString() == 'PURCHASE';
  final items = _weightsFromItems(bill['items']);
  final payment = _weightsFromItems(bill['paymentItems']);
  if (isPurchase) {
    return (issue: payment, receipt: items);
  }
  return (issue: items, receipt: payment);
}

/// Builds the live stock ledger for the Daily Sales Report.
///
/// Opening for [from] = opening_weight baseline + net movements before [from].
/// Closing = opening + receipts in range − issues in range. Uses raw
/// [weight] from each line item, never pureWt.
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
  final rows = <StockLedgerRow>[];

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
    final prefix = isPurchase ? 'PUR' : 'SAL';
    final billNo = (bill['billNo'] ?? '').toString();
    final sides = _billSides(bill);

    final beforeRange = !allHistory && billDay.isBefore(rangeFrom);
    final inRange = allHistory ||
        (!billDay.isBefore(rangeFrom) && !billDay.isAfter(rangeTo));

    if (beforeRange) {
      _applyNetChange(opening, sides.issue, sides.receipt);
    }
    if (inRange) {
      rows.add(StockLedgerRow(
        label: '$prefix$billNo',
        issueWeights: sides.issue,
        name: (bill['partyName'] ?? '').toString(),
        billNo: billNo,
        date: (bill['date'] ?? '').toString(),
        receiptWeights: sides.receipt,
      ));
    }
  }

  final closing = Map<String, double>.from(opening);
  for (final row in rows) {
    _applyNetChange(closing, row.issueWeights, row.receiptWeights);
  }

  return StockLedgerSummary(
    opening: opening,
    rows: rows,
    closing: closing,
  );
}

/// Formats a gross weight for the stock table.
///
/// [blankWhenZero] is `true` for Opening/Closing rows (blank cell). Use
/// `false` for transaction rows (shows `0.000` per mockup).
String formatStockWeight(double value, {bool blankWhenZero = true}) {
  if (value == 0) return blankWhenZero ? '' : '0.000';
  final fixed = value.toStringAsFixed(3);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
