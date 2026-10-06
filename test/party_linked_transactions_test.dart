import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('partyHasLinkedTransactions detects bills and vouchers', () async {
    final db = DatabaseHelper.instance;
    final name = 'linked_txn_test_${DateTime.now().microsecondsSinceEpoch}';

    await db.insertCustomer({
      'name': name,
      'mobile': '',
      'city': '',
      'cr': '0',
      'dr': '0',
      'drGross': '0',
      'drNet': '0',
      'narration': '',
      'balanceUnit': 'GRAMS',
      'billRef': '',
      'date': '07-09-2026',
      'time': '10:00 AM',
    });

    expect(
      await db.partyHasLinkedTransactions(name, isCustomer: true),
      isFalse,
    );

    await db.insertCustomer({
      'name': name,
      'mobile': '',
      'city': '',
      'cr': '0',
      'dr': '1',
      'drGross': '0',
      'drNet': '0',
      'narration': '',
      'balanceUnit': 'GRAMS',
      'billRef': 'SAL-1',
      'date': '07-09-2026',
      'time': '10:30 AM',
    });

    expect(
      await db.partyHasLinkedTransactions(name, isCustomer: true),
      isTrue,
    );
  });
}
