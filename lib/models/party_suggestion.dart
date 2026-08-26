/// One row in the Sales/Purchase party autocomplete list.
class PartySuggestion {
  const PartySuggestion({
    required this.name,
    this.mobile = '',
    this.city = '',
    this.cr = '0',
    this.dr = '0',
    this.balanceUnit = 'GRAMS',
  });

  final String name;
  final String mobile;
  final String city;
  final String cr;
  final String dr;
  final String balanceUnit;

  String get detailLine {
    final parts = <String>[];
    if (mobile.isNotEmpty) parts.add('Mob $mobile');
    if (city.isNotEmpty) parts.add(city);
    if (balanceUnit == 'GRAMS') {
      parts.add('CR ${cr}g · DR ${dr}g');
    } else {
      parts.add('CR ₹$cr · DR ₹$dr');
    }
    return parts.join('  ·  ');
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        mobile.toLowerCase().contains(q) ||
        city.toLowerCase().contains(q);
  }

  static List<PartySuggestion> fromLedgerRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => []).add(row);
    }

    final out = <PartySuggestion>[];
    grouped.forEach((name, entries) {
      var mobile = '';
      var city = '';
      var cr = 0.0;
      var dr = 0.0;
      var unit = 'GRAMS';

      for (final e in entries) {
        cr += double.tryParse((e['cr'] ?? '0').toString()) ?? 0;
        dr += double.tryParse((e['dr'] ?? '0').toString()) ?? 0;
        unit = (e['balanceUnit'] ?? unit).toString().toUpperCase();
        if (mobile.isEmpty) {
          mobile = (e['mobile'] ?? '').toString().trim();
        }
        if (city.isEmpty) {
          city = (e['city'] ?? '').toString().trim();
        }
      }

      out.add(PartySuggestion(
        name: name,
        mobile: mobile,
        city: city,
        cr: cr.toStringAsFixed(unit == 'GRAMS' ? 3 : 2),
        dr: dr.toStringAsFixed(unit == 'GRAMS' ? 3 : 2),
        balanceUnit: unit,
      ));
    });

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
