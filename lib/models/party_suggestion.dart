/// One row in the Sales/Purchase party autocomplete list.
class PartySuggestion {
  const PartySuggestion({
    required this.name,
    this.mobile = '',
    this.city = '',
    this.cr = '0',
    this.dr = '0',
    this.balanceUnit = 'GRAMS',
    this.roleLabel = '',
  });

  final String name;
  final String mobile;
  final String city;
  final String cr;
  final String dr;
  final String balanceUnit;
  final String roleLabel;

  String get detailLine {
    final parts = <String>[];
    if (roleLabel.isNotEmpty) parts.add(roleLabel);
    if (mobile.isNotEmpty) parts.add('Mob $mobile');
    if (city.isNotEmpty) parts.add(city);
    return parts.isEmpty ? 'Saved party' : parts.join('  ·  ');
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return name.toLowerCase().contains(q) ||
        mobile.toLowerCase().contains(q) ||
        city.toLowerCase().contains(q);
  }

  bool isExactNameMatch(String query) =>
      name.trim().toLowerCase() == query.trim().toLowerCase();

  static List<PartySuggestion> fromLedgerRows(
    List<Map<String, dynamic>> rows, {
    String roleLabel = '',
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(row);
    }

    final out = <PartySuggestion>[];
    grouped.forEach((_, entries) {
      final name = (entries.first['name'] ?? '').toString().trim();
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
        roleLabel: roleLabel,
      ));
    });

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
