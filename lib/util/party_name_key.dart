/// Canonical party name for grouping ledger rows (case-insensitive).
String partyNameKey(String name) => name.trim().toLowerCase();

/// Display name — first seen spelling wins when merging case variants.
String partyDisplayName(String name) => name.trim();

bool partyNameMatches(String storedName, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return partyNameKey(storedName).contains(q);
}
