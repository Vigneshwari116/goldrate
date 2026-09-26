/// Parses dates stored as dd-MM-yyyy, dd/MM/yyyy, or yyyy-MM-dd (API).
DateTime? parseAppDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final text = raw.trim();

  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
    try {
      final parts = text.split(RegExp(r'[-T ]'));
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {}
  }

  try {
    final parts = text.split(RegExp(r'[-/]'));
    if (parts.length < 3) return null;
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  } catch (_) {
    return null;
  }
}
