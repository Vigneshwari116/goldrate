import 'dart:convert';

import '../util/api_row_keys.dart';

/// Builds sales/purchase bill rows from customer/supplier ledger entries
/// (bill_ref SAL-1 / PUR-1) when the transactions table is empty or missing
/// a row that was still posted to the party ledger.
List<Map<String, dynamic>> mergeTransactionsWithLedgerBills({
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> customerRows,
  required List<Map<String, dynamic>> supplierRows,
}) {
  final normalizedTxns = normalizeApiList(transactions);
  final byKey = <String, Map<String, dynamic>>{};

  for (final tx in normalizedTxns) {
    final type = normalizeTransactionType(apiStr(tx, 'transactionType'));
    final billNo = tx['billNo'];
    if (type.isEmpty || billNo == null) continue;
    byKey['$type:$billNo'] = tx;
  }

  void addLedgerRows(
    List<Map<String, dynamic>> rows, {
    required String transactionType,
    required bool customer,
  }) {
    for (final raw in rows) {
      final row = normalizeApiRow(raw);
      final synthetic = _transactionFromLedgerRow(
        row,
        transactionType: transactionType,
        customer: customer,
      );
      if (synthetic == null) continue;
      final key =
          '${synthetic['transactionType']}:${synthetic['billNo']}';
      byKey.putIfAbsent(key, () => synthetic);
    }
  }

  addLedgerRows(customerRows, transactionType: 'SALES', customer: true);
  addLedgerRows(supplierRows, transactionType: 'PURCHASE', customer: false);

  final merged = byKey.values.toList();
  merged.sort((a, b) {
    final aBill = a['billNo'] as int? ?? 0;
    final bBill = b['billNo'] as int? ?? 0;
    if (aBill != bBill) return bBill.compareTo(aBill);
    return apiStr(b, 'date').compareTo(apiStr(a, 'date'));
  });
  return merged;
}

String normalizeTransactionType(String raw) => raw.trim().toUpperCase();

Map<String, dynamic>? _transactionFromLedgerRow(
  Map<String, dynamic> row, {
  required String transactionType,
  required bool customer,
}) {
  final ref = apiStr(row, 'billRef');
  final billNo = _billNoFromRef(ref);
  if (billNo == null) return null;

  final expectedPrefix = transactionType == 'SALES' ? 'SAL' : 'PUR';
  if (!ref.toUpperCase().startsWith(expectedPrefix)) return null;

  final dr = double.tryParse(apiStr(row, 'dr', '0')) ?? 0;
  final cr = double.tryParse(apiStr(row, 'cr', '0')) ?? 0;
  final balanceDelta = dr > 0 ? dr : cr;

  final grossField = customer ? apiStr(row, 'drGross') : apiStr(row, 'gross');
  final netField = customer ? apiStr(row, 'drNet') : apiStr(row, 'net');
  final grossVal = double.tryParse(grossField) ?? 0;
  final narration = apiStr(row, 'narration');

  var billPure = balanceDelta;
  final narrationPure = _pureGramsFromNarration(narration);
  if (billPure < 0.0005 && narrationPure != null) {
    billPure = narrationPure;
  }
  if (billPure < 0.0005 && grossVal > 0) {
    billPure = grossVal;
  }

  final items = _itemsJsonFromLedger(
    narration: narration,
    grossWt: grossVal,
    pureWt: billPure,
  );
  final paymentItems = _paymentItemsJsonFromLedger(
    narration: narration,
    transactionType: transactionType,
    billPure: billPure,
    balanceDelta: balanceDelta,
    grossWt: grossVal,
  );

  final hasGoldPayment = paymentItems != '[]';
  final paymentGrams = _paymentGramsFromItems(paymentItems);

  return {
    'id': transactionType == 'SALES' ? -billNo : -(100000 + billNo),
    'transactionType': transactionType,
    'billNo': billNo,
    'partyName': apiStr(row, 'name'),
    'items': items,
    if (hasGoldPayment) 'paymentItems': paymentItems,
    'totalWt': grossVal > 0
        ? grossVal.toStringAsFixed(2)
        : billPure.toStringAsFixed(2),
    'totalPureWt': billPure.toStringAsFixed(3),
    'totalValue': netField.isNotEmpty ? netField : '0',
    'paymentMode': hasGoldPayment ? 'GOLD' : 'GOLD',
    'paymentAmount':
        hasGoldPayment ? paymentGrams.toStringAsFixed(3) : '0',
    'balance': balanceDelta.toStringAsFixed(3),
    'balanceUnit': apiStr(row, 'balanceUnit', 'GRAMS'),
    'date': apiStr(row, 'date'),
    'time': apiStr(row, 'time'),
    'oldGrams': '0',
    'oldRupees': '0',
    'newGrams': balanceDelta.toStringAsFixed(3),
    'newRupees': '0',
    'cashToGold': '0',
    'goldRateUsed': '0',
    'narration': narration,
    'billRef': ref,
    'fromLedger': true,
  };
}

double? _pureGramsFromNarration(String narration) {
  final match =
      RegExp(r'Pure\s+([\d.]+)', caseSensitive: false).firstMatch(narration);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

double _gwtFromNarration(String narration) {
  final match =
      RegExp(r'GWT\s+([\d.]+)', caseSensitive: false).firstMatch(narration);
  if (match == null) return 0;
  return double.tryParse(match.group(1)!) ?? 0;
}

String _itemsJsonFromLedger({
  required String narration,
  required double grossWt,
  required double pureWt,
}) {
  if (grossWt <= 0 && pureWt <= 0) return '[]';

  final gwt = _gwtFromNarration(narration);
  final weight = gwt > 0 ? gwt : (grossWt > 0 ? grossWt : pureWt);
  final pure = pureWt > 0 ? pureWt : weight;
  if (weight <= 0) return '[]';

  return jsonEncode([
    {
      'type': 'GWT',
      'weight': weight,
      'touch': 100,
      'pureWt': pure,
    },
  ]);
}

String _paymentItemsJsonFromLedger({
  required String narration,
  required String transactionType,
  required double billPure,
  required double balanceDelta,
  required double grossWt,
}) {
  if (billPure <= 0 && grossWt <= 0) return '[]';

  final paid = billPure - balanceDelta;
  if (paid <= 0.0005) return '[]';

  final gwtPaid = _gwtFromNarration(narration);
  final weight = gwtPaid > 0 && (gwtPaid - paid).abs() < 0.05
      ? gwtPaid
      : (grossWt > 0 && (grossWt - paid).abs() < 0.05 ? grossWt : paid);

  return jsonEncode([
    {
      'type': 'GWT',
      'weight': weight,
      'touch': 100,
      'pureWt': paid,
    },
  ]);
}

double _paymentGramsFromItems(String paymentItemsJson) {
  try {
    final items = jsonDecode(paymentItemsJson) as List<dynamic>;
    var sum = 0.0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final pure = double.tryParse((raw['pureWt'] ?? '').toString());
      if (pure != null) {
        sum += pure;
      } else {
        sum += double.tryParse((raw['weight'] ?? '').toString()) ?? 0;
      }
    }
    return sum;
  } catch (_) {
    return 0;
  }
}

int? _billNoFromRef(String ref) {
  final match =
      RegExp(r'^(SAL|PUR)-(\d+)$', caseSensitive: false).firstMatch(ref.trim());
  if (match == null) return null;
  return int.tryParse(match.group(2)!);
}
