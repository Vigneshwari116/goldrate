/// Metal type codes used on bills, matching opening-weight columns.
const kMetalTypes = ['GWT', 'FWT', 'KWT', 'SWT'];

const kMetalLabels = {
  'GWT': 'G.Pure',
  'FWT': 'Fine',
  'KWT': 'Kacha',
  'SWT': 'Silver',
};

const kOpeningFieldByType = {
  'GWT': 'gPureWt',
  'FWT': 'fineWt',
  'KWT': 'kachaWt',
  'SWT': 'silverWt',
};

class StockSummaryRow {
  final String type;
  final String label;
  final double opening;
  final double purchased;
  final double sold;
  final double current;

  const StockSummaryRow({
    required this.type,
    required this.label,
    required this.opening,
    required this.purchased,
    required this.sold,
    required this.current,
  });
}

class StockLedgerRow {
  final String metalType;
  final String date;
  final String time;
  final String refType;
  final String particulars;
  final double qtyIn;
  final double qtyOut;
  final double balance;

  const StockLedgerRow({
    required this.metalType,
    required this.date,
    required this.time,
    required this.refType,
    required this.particulars,
    required this.qtyIn,
    required this.qtyOut,
    required this.balance,
  });
}

Map<String, double> openingStockFromRow(Map<String, dynamic>? opening) {
  return {
    for (final type in kMetalTypes)
      type: double.tryParse(
              (opening?[kOpeningFieldByType[type]] ?? '').toString()) ??
          0,
  };
}

/// Running ledger for one metal: opening, then each bill line in order.
List<StockLedgerRow> buildStockLedger({
  required String metalType,
  required Map<String, double> openingByType,
  required String openingDate,
  required String openingTime,
  required List<Map<String, dynamic>> transactionsOldestFirst,
  required List<dynamic> Function(Map<String, dynamic> row) itemsOf,
}) {
  final rows = <StockLedgerRow>[];
  var balance = openingByType[metalType] ?? 0;

  rows.add(StockLedgerRow(
    metalType: metalType,
    date: openingDate,
    time: openingTime,
    refType: 'OPENING',
    particulars: 'Opening stock',
    qtyIn: balance,
    qtyOut: 0,
    balance: balance,
  ));

  for (final tx in transactionsOldestFirst) {
    final kind = (tx['transactionType'] ?? '').toString();
    final isIn = kind == 'PURCHASE';
    final billNo = tx['billNo']?.toString() ?? '';
    final party = (tx['partyName'] ?? '').toString();
    final date = (tx['date'] ?? '').toString();
    final time = (tx['time'] ?? '').toString();

    for (final raw in itemsOf(tx)) {
      if (raw is! Map) continue;
      final type = (raw['type'] ?? '').toString();
      if (type != metalType) continue;
      final wt = (raw['pureWt'] as num?)?.toDouble() ??
          double.tryParse((raw['pureWt'] ?? '').toString()) ??
          0;
      if (isIn) {
        balance += wt;
        rows.add(StockLedgerRow(
          metalType: metalType,
          date: date,
          time: time,
          refType: 'PURCHASE',
          particulars: 'Bill #$billNo  $party',
          qtyIn: wt,
          qtyOut: 0,
          balance: balance,
        ));
      } else {
        balance -= wt;
        rows.add(StockLedgerRow(
          metalType: metalType,
          date: date,
          time: time,
          refType: 'SALES',
          particulars: 'Bill #$billNo  $party',
          qtyIn: 0,
          qtyOut: wt,
          balance: balance,
        ));
      }
    }
  }

  return rows;
}

List<StockSummaryRow> buildStockSummary({
  required Map<String, double> openingByType,
  required List<Map<String, dynamic>> transactions,
  required List<dynamic> Function(Map<String, dynamic> row) itemsOf,
}) {
  final purchased = {for (final t in kMetalTypes) t: 0.0};
  final sold = {for (final t in kMetalTypes) t: 0.0};

  for (final tx in transactions) {
    final kind = (tx['transactionType'] ?? '').toString();
    final intoShop = kind == 'PURCHASE';
    for (final raw in itemsOf(tx)) {
      if (raw is! Map) continue;
      final type = (raw['type'] ?? '').toString();
      if (!purchased.containsKey(type)) continue;
      final wt = (raw['pureWt'] as num?)?.toDouble() ??
          double.tryParse((raw['pureWt'] ?? '').toString()) ??
          0;
      if (intoShop) {
        purchased[type] = purchased[type]! + wt;
      } else {
        sold[type] = sold[type]! + wt;
      }
    }
  }

  return [
    for (final type in kMetalTypes)
      StockSummaryRow(
        type: type,
        label: kMetalLabels[type]!,
        opening: openingByType[type] ?? 0,
        purchased: purchased[type]!,
        sold: sold[type]!,
        current: (openingByType[type] ?? 0) + purchased[type]! - sold[type]!,
      ),
  ];
}
