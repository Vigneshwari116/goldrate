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
    final type = apiStr(tx, 'transactionType');
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
  final grams = dr > 0 ? dr : cr;

  final gross = customer
      ? apiStr(row, 'drGross')
      : apiStr(row, 'gross');
  final net = customer ? apiStr(row, 'drNet') : apiStr(row, 'net');

  return {
    'id': transactionType == 'SALES' ? -billNo : -(100000 + billNo),
    'transactionType': transactionType,
    'billNo': billNo,
    'partyName': apiStr(row, 'name'),
    'items': '[]',
    'totalWt': gross.isNotEmpty ? gross : grams.toStringAsFixed(2),
    'totalPureWt': grams.toStringAsFixed(3),
    'totalValue': net.isNotEmpty ? net : '0',
    'paymentMode': 'GOLD',
    'paymentAmount': '0',
    'balance': grams.toStringAsFixed(3),
    'balanceUnit': apiStr(row, 'balanceUnit', 'GRAMS'),
    'date': apiStr(row, 'date'),
    'time': apiStr(row, 'time'),
    'oldGrams': '0',
    'oldRupees': '0',
    'newGrams': grams.toStringAsFixed(3),
    'newRupees': '0',
    'cashToGold': '0',
    'goldRateUsed': '0',
    'narration': apiStr(row, 'narration'),
    'billRef': ref,
    'fromLedger': true,
  };
}

int? _billNoFromRef(String ref) {
  final match =
      RegExp(r'^(SAL|PUR)-(\d+)$', caseSensitive: false).firstMatch(ref.trim());
  if (match == null) return null;
  return int.tryParse(match.group(2)!);
}
