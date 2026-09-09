import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/database_helper.dart';
import 'package:grate_app/logic/rate_rows.dart';
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
    expect(rows.map((r) => r['rateName']).toList(), RateRows.defaultRateNames);
    expect(rows[0]['rateValue'], '15100');
    expect(rows[2]['rateValue'], '100');
  });

  test('rate repair keeps one row per default rate name', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE rates(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              rateName TEXT,
              rateValue TEXT
            )
          ''');
        },
      ),
    );

    for (var copy = 0; copy < 2; copy++) {
      for (final name in RateRows.defaultRateNames) {
        await db.insert('rates', {'rateName': name, 'rateValue': ''});
      }
    }

    expect((await db.query('rates')).length, 8);

    final rows = await db.query('rates', orderBy: 'id DESC');
    for (final name in RateRows.defaultRateNames) {
      final matching = rows
          .where((r) => (r['rateName'] ?? '').toString() == name)
          .toList();
      final keeper = RateRows.pickBest(matching);
      expect(keeper, isNotNull);
      final keepId = (keeper!['id'] as num?)?.toInt() ?? 0;
      for (final row in matching) {
        final id = (row['id'] as num?)?.toInt() ?? 0;
        if (id > 0 && id != keepId) {
          await db.delete('rates', where: 'id = ?', whereArgs: [id]);
        }
      }
    }

    final repaired = RateRows.canonical(await db.query('rates'));
    expect(repaired.length, 4);
    expect(repaired.map((r) => r['rateName']).toSet().length, 4);
    await db.close();
  });
}
