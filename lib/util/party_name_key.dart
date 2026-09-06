/// Canonical party name for grouping ledger rows (case-insensitive).
String partyNameKey(String name) => name.trim().toLowerCase();

/// Display name — first seen spelling wins when merging case variants.
String partyDisplayName(String name) => name.trim();

/// Returns true when [name] matches an existing party (case-insensitive).
bool isDuplicatePartyName(String name, Iterable<String> existingNames) {
  final key = partyNameKey(name);
  if (key.isEmpty) return false;
  for (final existing in existingNames) {
    if (partyNameKey(existing) == key) return true;
  }
  return false;
}

/// Finds an existing party whose name matches case-insensitively.
String? findDuplicatePartyName(String name, Iterable<String> existingNames) {
  final key = partyNameKey(name);
  if (key.isEmpty) return null;
  for (final existing in existingNames) {
    if (partyNameKey(existing) == key) return existing.trim();
  }
  return null;
}

bool partyNameMatches(String storedName, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return partyNameKey(storedName).contains(q);
}
