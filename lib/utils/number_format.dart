String formatWeight(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '') ?? 0;
  return n.toStringAsFixed(3);
}

String formatAmount(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '') ?? 0;
  return n.toStringAsFixed(2);
}

String orZero(String? value) {
  final v = (value ?? '').trim();
  return v.isEmpty ? '0' : v;
}
