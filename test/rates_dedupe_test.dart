import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('canonicalRateRows collapses duplicate rate names', () {
    final rows = DatabaseHelper.canonicalRateRows([
      {'id': 1, 'rateName': 'G.P RATE', 'rateValue': ''},
      {'id': 5, 'rateName': 'G.P RATE', 'rateValue': '15100'},
      {'id': 2, 'rateName': 'F.T RATE', 'rateValue': ''},
      {'id': 6, 'rateName': 'F.T RATE', 'rateValue': ''},
      {'id': 3, 'rateName': 'KACHA RATE', 'rateValue': '100'},
      {'id': 7, 'rateName': 'KACHA RATE', 'rateValue': ''},
      {'id': 4, 'rateName': 'S RATE', 'rateValue': ''},
      {'id': 8, 'rateName': 'S RATE', 'rateValue': ''},
    ]);

    expect(rows.length, 4);
    expect(rows.map((r) => r['rateName']).toList(), [
      'G.P RATE',
      'F.T RATE',
      'KACHA RATE',
      'S RATE',
    ]);
    expect(rows[0]['rateValue'], '15100');
    expect(rows[2]['rateValue'], '100');
  });

  test('ensureDefaultRates repairs duplicate rows in database', () async {
    final helper = DatabaseHelper.instance;
    final database = await helper.database;
    await database.delete('rates');
    for (var copy = 0; copy < 2; copy++) {
      for (final name in [
        'G.P RATE',
        'F.T RATE',
        'KACHA RATE',
        'S RATE',
      ]) {
        await database.insert('rates', {'rateName': name, 'rateValue': ''});
      }
    }

    expect((await helper.getRates()).length, 8);

    await helper.ensureDefaultRates();

    expect((await helper.getRates()).length, 4);
    final masterRows = await helper.getRatesForMaster();
    expect(masterRows.length, 4);
    expect(masterRows.map((r) => r['rateName']).toSet().length, 4);
  });
}
