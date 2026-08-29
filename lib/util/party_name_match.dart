/// Helpers for matching typed party names against saved master lists.
class PartyNameMatch {
  PartyNameMatch._();

  static bool hasMatches(Iterable<String> names, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return names.any((name) => name.toLowerCase().contains(q));
  }

  static bool isExactMatch(Iterable<String> names, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return names.any((name) => name.toLowerCase() == q);
  }
}
