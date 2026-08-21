import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dataDir;
  late Directory backupDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('jw_data_');
    backupDir = await Directory.systemTemp.createTemp('jw_backup_');
    await databaseFactory.setDatabasesPath(dataDir.path);
    await DatabaseHelper.instance.closeDatabase();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    if (backupDir.existsSync()) backupDir.deleteSync(recursive: true);
  });

  test('second backup to the same folder file includes later edits', () async {
    final dest = p.join(backupDir.path, 'jewellery.db');

    await DatabaseHelper.instance.insertCustomer({
      'name': 'First Party',
      'mobile': '',
      'city': '',
    });
    await DatabaseHelper.instance.copyDatabaseTo(dest);

    await DatabaseHelper.instance.insertCustomer({
      'name': 'Updated Party',
      'mobile': '999',
      'city': 'Chennai',
    });
    await DatabaseHelper.instance.copyDatabaseTo(dest);

    final backupDb = await openDatabase(dest, readOnly: true);
    final names = (await backupDb.query('customers'))
        .map((r) => r['name'].toString())
        .toList();
    await backupDb.close();

    expect(names, containsAll(['First Party', 'Updated Party']));
  });
}
