import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/models/bill_line_item.dart';

void main() {
  test('description defaults by type and serializes in JSON', () {
    final line = BillLineItem(
      type: 'GWT',
      weight: 1,
      touch: 100,
      rate: 100,
      hsn: '7113',
    );
    expect(line.description, 'Gold Jewellery');

    final custom = BillLineItem(
      type: 'GWT',
      weight: 1,
      touch: 100,
      rate: 100,
      hsn: '7113',
      description: 'Gold Chain',
    );
    expect(custom.description, 'Gold Chain');
    expect(custom.toJson()['description'], 'Gold Chain');

    final restored = BillLineItem.fromJson(custom.toJson());
    expect(restored.description, 'Gold Chain');
  });

  test('legacy JSON without description gets type default', () {
    final json = {
      'type': 'FWT',
      'weight': 2,
      'touch': 99.5,
      'rate': 5000,
      'hsn': '7113',
    };
    expect(BillLineItem.fromJson(json).description, 'Gold Jewellery (Fine)');
  });
}
