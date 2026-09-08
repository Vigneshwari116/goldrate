/// Canonical daily-rate row helpers shared by local DB and API clients.
class RateRows {
  RateRows._();

  static const defaultRateNames = [
    'G.P RATE',
    'F.T RATE',
    'KACHA RATE',
    'S RATE',
  ];

  /// One row per default rate name, in display order.
  static List<Map<String, dynamic>> canonical(
    List<Map<String, dynamic>> rows,
  ) {
    final byName = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final name = (row['rateName'] ?? '').toString().trim();
      if (!defaultRateNames.contains(name)) continue;
      final existing = byName[name];
      if (existing == null) {
        byName[name] = row;
        continue;
      }
      final keeper = _pickBest([existing, row]);
      if (keeper != null) byName[name] = keeper;
    }
    return [
      for (final name in defaultRateNames)
        byName[name] ?? {'id': 0, 'rateName': name, 'rateValue': ''},
    ];
  }

  static Map<String, dynamic>? pickBest(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final sorted = [...rows];
    sorted.sort((a, b) {
      final aHas = (a['rateValue'] ?? '').toString().trim().isNotEmpty;
      final bHas = (b['rateValue'] ?? '').toString().trim().isNotEmpty;
      if (aHas != bHas) return aHas ? -1 : 1;
      final aId = (a['id'] as num?)?.toInt() ?? 0;
      final bId = (b['id'] as num?)?.toInt() ?? 0;
      return bId.compareTo(aId);
    });
    return sorted.first;
  }

  static Map<String, dynamic>? _pickBest(List<Map<String, dynamic>> rows) =>
      pickBest(rows);
}
