import '../logic/bill_tax.dart';

/// One issue/receipt weight row on a purchase or sales bill.
class BillLineItem {
  final String type;
  final double weight;
  final double touch;
  final double rate;
  final String hsn;
  final String description;
  final double cgstPercent;
  final double sgstPercent;

  BillLineItem({
    required this.type,
    required this.weight,
    required this.touch,
    required this.rate,
    required this.hsn,
    String? description,
    this.cgstPercent = 1.5,
    this.sgstPercent = 1.5,
  }) : description = (description?.trim().isNotEmpty == true)
            ? description!.trim()
            : defaultItemDescriptionForType(type);

  double get pureWt => weight * touch / 100;

  double get value => pureWt * rate;

  BillLineTax get tax => BillLineTax.compute(
        pureWt: pureWt,
        rate: rate,
        cgstPercent: cgstPercent,
        sgstPercent: sgstPercent,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'weight': weight,
        'touch': touch,
        'pureWt': double.parse(pureWt.toStringAsFixed(3)),
        'rate': rate,
        'value': value,
        'hsn': hsn,
        'description': description,
        'cgstPercent': cgstPercent,
        'sgstPercent': sgstPercent,
        'taxableValue': double.parse(tax.taxableValue.toStringAsFixed(2)),
        'cgstAmount': double.parse(tax.cgstAmount.toStringAsFixed(2)),
        'sgstAmount': double.parse(tax.sgstAmount.toStringAsFixed(2)),
        'inclusiveAmount': double.parse(tax.inclusiveAmount.toStringAsFixed(2)),
      };

  factory BillLineItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final hsnRaw = (json['hsn'] ?? '').toString();
    final descRaw = (json['description'] ?? '').toString().trim();
    return BillLineItem(
      type: type,
      weight: (json['weight'] as num).toDouble(),
      touch: (json['touch'] as num).toDouble(),
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
      hsn: hsnRaw.isNotEmpty ? hsnRaw : (kDefaultHsnByItemType[type] ?? ''),
      description: descRaw.isNotEmpty ? descRaw : null,
      cgstPercent: (json['cgstPercent'] as num?)?.toDouble() ?? 1.5,
      sgstPercent: (json['sgstPercent'] as num?)?.toDouble() ?? 1.5,
    );
  }

  BillLineItem copyWith({
    double? cgstPercent,
    double? sgstPercent,
    String? hsn,
    String? description,
  }) {
    return BillLineItem(
      type: type,
      weight: weight,
      touch: touch,
      rate: rate,
      hsn: hsn ?? this.hsn,
      description: description ?? this.description,
      cgstPercent: cgstPercent ?? this.cgstPercent,
      sgstPercent: sgstPercent ?? this.sgstPercent,
    );
  }
}
