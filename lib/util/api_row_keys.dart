/// Normalizes API/DB rows so the app always reads camelCase keys.
Map<String, dynamic> normalizeApiRow(Map<String, dynamic> row) {
  final out = <String, dynamic>{};
  for (final entry in row.entries) {
    final key = entry.key;
    final camel = key.contains('_') ? _snakeToCamel(key) : key;
    out.putIfAbsent(camel, () => entry.value);
  }
  return out;
}

List<Map<String, dynamic>> normalizeApiList(List<Map<String, dynamic>> rows) {
  return rows.map(normalizeApiRow).toList();
}

String _snakeToCamel(String key) {
  return key.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

String apiStr(Map<String, dynamic> row, String key, [String fallback = '']) {
  final value = row[key];
  if (value == null) return fallback;
  return value.toString();
}
