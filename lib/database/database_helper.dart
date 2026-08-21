import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'jewellery.db');

    return await openDatabase(
      path,
      version: 10,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        password TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE rates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rateName TEXT NOT NULL,
        rateValue TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE rate_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rateName TEXT NOT NULL,
        rateValue TEXT NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT,
        city TEXT,
        cr TEXT,
        dr TEXT,
        drGross TEXT,
        drNet TEXT,
        narration TEXT,
        balanceUnit TEXT,
        billRef TEXT,
        date TEXT,
        time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT,
        city TEXT,
        cr TEXT,
        dr TEXT,
        gross TEXT,
        net TEXT,
        narration TEXT,
        balanceUnit TEXT,
        billRef TEXT,
        date TEXT,
        time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE opening_weight(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gPureWt TEXT,
        fineWt TEXT,
        kachaWt TEXT,
        silverWt TEXT,
        cash TEXT,
        date TEXT,
        time TEXT
      )
    ''');

    // Purchase (Stock Plus) and Sales (Stock Minus) transactions.
    // `items` stores the line items (type/weight/touch/pureWt) as a JSON
    // string, since each transaction can carry multiple weight rows
    // (e.g. a G.Pure row and a Kacha row) exactly like the paper bill.
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transactionType TEXT NOT NULL,
        billNo INTEGER NOT NULL,
        partyName TEXT,
        items TEXT NOT NULL,
        totalWt TEXT,
        totalPureWt TEXT,
        totalValue TEXT,
        paymentMode TEXT,
        paymentAmount TEXT,
        balance TEXT,
        balanceUnit TEXT,
        staffName TEXT,
        date TEXT,
        time TEXT
      )
    ''');

    await db.insert('users', {
      'username': 'ADMIN',
      'password': 'SVENSKA',
    });

    await db.insert('rates', {'rateName': 'G.P RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'F.T RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'KACHA RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'S RATE', 'rateValue': ''});
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE customers ADD COLUMN dr TEXT');
    }
    if (oldVersion < 3) {
      // Adds the suppliers table for the new Supplier Master screen.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS suppliers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          mobile TEXT,
          city TEXT,
          cr TEXT,
          dr TEXT,
          gross TEXT,
          net TEXT,
          narration TEXT,
          date TEXT,
          time TEXT
        )
      ''');
    }
    if (oldVersion == 3) {
      await db.execute('ALTER TABLE suppliers ADD COLUMN gross TEXT');
      await db.execute('ALTER TABLE suppliers ADD COLUMN net TEXT');
    }
    if (oldVersion < 5) {
      // Adds the one-time opening weight baseline table.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS opening_weight(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          gPureWt TEXT,
          fineWt TEXT,
          kachaWt TEXT,
          silverWt TEXT,
          date TEXT,
          time TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      // Adds opening cash-in-hand, plus the purchase/sales transaction log.
      await db.execute('ALTER TABLE opening_weight ADD COLUMN cash TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transactionType TEXT NOT NULL,
          billNo INTEGER NOT NULL,
          partyName TEXT,
          items TEXT NOT NULL,
          totalWt TEXT,
          totalPureWt TEXT,
          paymentMode TEXT,
          paymentAmount TEXT,
          balance TEXT,
          date TEXT,
          time TEXT
        )
      ''');
    }
    if (oldVersion < 7) {
      // Adds the rupee value of a bill and clarifies what unit the
      // balance is in (RUPEES for cash/UPI settlement, GRAMS for a
      // gold exchange settlement) — a bill's payment isn't always in
      // the same unit as the metal itself.
      await db.execute('ALTER TABLE transactions ADD COLUMN totalValue TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN balanceUnit TEXT');
    }
    if (oldVersion < 8) {
      // Lets a customer/supplier ledger row carry the unit its cr/dr is
      // in (RUPEES vs GRAMS), and which bill it came from, so postings
      // from Purchase/Sales bills can be summed correctly and traced
      // back to the bill that created them.
      await db.execute('ALTER TABLE customers ADD COLUMN balanceUnit TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN billRef TEXT');
      await db.execute('ALTER TABLE suppliers ADD COLUMN balanceUnit TEXT');
      await db.execute('ALTER TABLE suppliers ADD COLUMN billRef TEXT');
    }
    if (oldVersion < 9) {
      // Records which staff member saved a bill — useful the moment more
      // than one person uses the same phone, without building full
      // per-user auth.
      await db.execute('ALTER TABLE transactions ADD COLUMN staffName TEXT');
    }
    if (oldVersion < 10) {
      // Full data reset: clears every bit of business data entered so
      // far (customers, suppliers, rates, rate history, opening weight,
      // transactions) so the app comes up as a clean slate, the same
      // way RestoPOS's Masters were cleared.
      //
      // The ADMIN/SVENSKA login is intentionally NOT touched — this
      // file has no sign-up/registration screen, so deleting the only
      // user row would permanently lock every install out of the app.
      // If `users` is somehow empty (shouldn't happen, but just in
      // case), we re-seed the default login so nobody gets locked out.
      await db.delete('transactions');
      await db.delete('opening_weight');
      await db.delete('rate_history');
      await db.delete('rates');
      await db.delete('suppliers');
      await db.delete('customers');

      // Re-insert the blank default rate rows so Rate Master still has
      // its four rows to fill in, exactly like a fresh install.
      await db.insert('rates', {'rateName': 'G.P RATE', 'rateValue': ''});
      await db.insert('rates', {'rateName': 'F.T RATE', 'rateValue': ''});
      await db.insert('rates', {'rateName': 'KACHA RATE', 'rateValue': ''});
      await db.insert('rates', {'rateName': 'S RATE', 'rateValue': ''});

      // Safety net: only runs if the users table is unexpectedly empty.
      final userCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) as count FROM users'),
      ) ??
          0;
      if (userCount == 0) {
        await db.insert('users', {
          'username': 'ADMIN',
          'password': 'SVENSKA',
        });
      }

      // Reset autoincrement counters so new rows start from 1 again.
      await db.delete(
        'sqlite_sequence',
        where: 'name IN (?, ?, ?, ?, ?, ?)',
        whereArgs: [
          'transactions',
          'opening_weight',
          'rate_history',
          'rates',
          'suppliers',
          'customers',
        ],
      );
    }
  }

  Future<bool> checkLogin(String username, String password) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );

    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getRates() async {
    final db = await database;
    return await db.query('rates');
  }

  /// Rates keyed by rateName (e.g. 'G.P RATE' -> 15100), parsed to double.
  /// A rate that hasn't been set yet (blank) is simply left out of the map.
  Future<Map<String, double>> getRatesMap() async {
    final rows = await getRates();
    final map = <String, double>{};
    for (final row in rows) {
      final value = double.tryParse((row['rateValue'] ?? '').toString());
      if (value != null) {
        map[row['rateName'] as String] = value;
      }
    }
    return map;
  }

  Future<int> updateRate(
      int id,
      String rateName,
      String value,
      String date,
      String time,
      ) async {
    final db = await database;

    final rowsAffected = await db.update(
      'rates',
      {'rateValue': value},
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rowsAffected > 0) {
      await db.insert('rate_history', {
        'rateName': rateName,
        'rateValue': value,
        'date': date,
        'time': time,
      });
    }

    return rowsAffected;
  }

  Future<Map<String, dynamic>> getUpdateStats() async {
    final db = await database;

    final countResult =
    await db.rawQuery('SELECT COUNT(*) as count FROM rate_history');
    final count = Sqflite.firstIntValue(countResult) ?? 0;

    final latest = await db.query(
      'rate_history',
      orderBy: 'id DESC',
      limit: 1,
    );

    return {
      'count': count,
      'lastDate': latest.isNotEmpty ? latest.first['date'] as String : '',
      'lastTime': latest.isNotEmpty ? latest.first['time'] as String : '',
    };
  }

  Future<List<Map<String, dynamic>>> getRateHistory() async {
    final db = await database;
    return await db.query('rate_history', orderBy: 'id DESC');
  }


  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    return await db.insert('customers', customer);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    return await db.query('customers', orderBy: 'id DESC');
  }


  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final db = await database;
    return await db.insert('suppliers', supplier);
  }

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final db = await database;
    return await db.query('suppliers', orderBy: 'id DESC');
  }

  Future<int> deleteSupplier(int id) async {
    final db = await database;
    return await db.delete(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getOpeningWeight() async {
    final db = await database;
    final result = await db.query('opening_weight', limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> insertOpeningWeight(Map<String, dynamic> weight) async {
    final existing = await getOpeningWeight();
    if (existing != null) {
      throw StateError('Opening weight has already been saved and is locked.');
    }
    final db = await database;
    return await db.insert('opening_weight', weight);
  }

  // ---------- Transactions (Purchase / Sales) ----------

  /// transactionType is either 'PURCHASE' (Stock Plus) or 'SALES' (Stock Minus).
  /// Bill numbers restart from 1 and increment independently per type,
  /// matching the "BILL NO" column on the paper form.
  Future<int> getNextBillNo(String transactionType) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(billNo) as maxBill FROM transactions WHERE transactionType = ?',
      [transactionType],
    );
    final maxBill = result.isNotEmpty ? result.first['maxBill'] as int? : null;
    return (maxBill ?? 0) + 1;
  }

  Future<int> insertTransaction(Map<String, dynamic> transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction);
  }

  Future<List<Map<String, dynamic>>> getTransactions(
      String transactionType) async {
    final db = await database;
    return await db.query(
      'transactions',
      where: 'transactionType = ?',
      whereArgs: [transactionType],
      orderBy: 'id DESC',
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- Party ledger (Customer/Supplier balances) ----------

  /// Distinct names already on record, used for the party typeahead on
  /// the Purchase/Sales screen — Purchase looks up Suppliers (the shop
  /// is buying stock in), Sales looks up Customers (the shop is selling
  /// stock out).
  Future<List<String>> getDistinctPartyNames({required bool isCustomer}) async {
    final db = await database;
    final table = isCustomer ? 'customers' : 'suppliers';
    final rows = await db.query(table, columns: ['name'], distinct: true);
    final names = rows
        .map((r) => (r['name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  /// Sums every ledger row on record for this name into a running
  /// outstanding total — kept as two separate totals (rupees owed vs
  /// grams owed) rather than one number, since a cash bill's balance
  /// and a gold-exchange bill's balance are never interchangeable.
  /// Positive = the party owes the shop; negative = the shop owes them.
  Future<Map<String, double>> getPartyOutstanding(
      String name, {
        required bool isCustomer,
      }) async {
    final db = await database;
    final table = isCustomer ? 'customers' : 'suppliers';
    final rows = await db.query(table, where: 'name = ?', whereArgs: [name]);

    double rupees = 0;
    double grams = 0;

    for (final row in rows) {
      final cr = double.tryParse((row['cr'] ?? '').toString()) ?? 0;
      final dr = double.tryParse((row['dr'] ?? '').toString()) ?? 0;
      final unit = (row['balanceUnit'] ?? 'RUPEES').toString();
      final net = dr - cr;
      if (unit == 'GRAMS') {
        grams += net;
      } else {
        rupees += net;
      }
    }

    return {'rupees': rupees, 'grams': grams};
  }

  /// Staff names already used on a saved bill, for the login screen's
  /// "who is this" picker — no full auth, just enough to know who
  /// saved which bill.
  Future<List<String>> getDistinctStaffNames() async {
    final db = await database;
    final rows = await db.query('transactions',
        columns: ['staffName'], distinct: true);
    final names = rows
        .map((r) => (r['staffName'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  /// Every Purchase/Sales bill saved on a given date (format
  /// dd-MM-yyyy, matching how dates are stored everywhere else in this
  /// app) — used by the Today Summary screen.
  Future<List<Map<String, dynamic>>> getTransactionsByDate(
      String date) async {
    final db = await database;
    return await db.query(
      'transactions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
    );
  }

  /// Absolute path of the live `jewellery.db` file.
  Future<String> getDatabaseFilePath() async {
    return join(await getDatabasesPath(), 'jewellery.db');
  }

  /// Flushes WAL so a file copy of `jewellery.db` is complete, then
  /// copies that file to [destinationPath].
  Future<void> copyDatabaseTo(String destinationPath) async {
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final source = File(await getDatabaseFilePath());
    if (!await source.exists()) {
      throw StateError('Database file was not found.');
    }
    final dest = File(destinationPath);
    await dest.parent.create(recursive: true);
    await source.copy(destinationPath);
  }

  /// Replaces the live database with [backupPath], then re-opens it.
  /// Any WAL/SHM sidecar files are removed so SQLite starts clean.
  Future<void> restoreDatabaseFrom(String backupPath) async {
    final backup = File(backupPath);
    if (!await backup.exists()) {
      throw StateError('Backup file was not found.');
    }

    await _database?.close();
    _database = null;

    final livePath = await getDatabaseFilePath();
    final wal = File('$livePath-wal');
    final shm = File('$livePath-shm');
    if (await wal.exists()) await wal.delete();
    if (await shm.exists()) await shm.delete();
    await backup.copy(livePath);

    await database;
  }

  // ---------- Live current stock ----------

  /// Current stock, per metal type, calculated live as:
  ///   opening weight (the locked one-time baseline)
  ///   + everything bought in on Purchase bills
  ///   - everything sold out on Sales bills
  /// Nothing is re-entered daily — this always reflects "right now"
  /// because it's computed fresh from the opening baseline plus every
  /// transaction ever saved, not stored as its own row anywhere.
  /// Keys match the item type codes used on the bill: GWT, FWT, KWT, SWT.
  Future<Map<String, double>> getCurrentStock() async {
    final opening = await getOpeningWeight();

    final stock = <String, double>{
      'GWT': double.tryParse((opening?['gPureWt'] ?? '').toString()) ?? 0,
      'FWT': double.tryParse((opening?['fineWt'] ?? '').toString()) ?? 0,
      'KWT': double.tryParse((opening?['kachaWt'] ?? '').toString()) ?? 0,
      'SWT': double.tryParse((opening?['silverWt'] ?? '').toString()) ?? 0,
    };

    final db = await database;
    final rows = await db.query('transactions');

    for (final row in rows) {
      final sign = row['transactionType'] == 'PURCHASE' ? 1.0 : -1.0;
      final itemsRaw = (row['items'] ?? '[]').toString();

      List<dynamic> items;
      try {
        items = jsonDecode(itemsRaw) as List<dynamic>;
      } catch (_) {
        continue; // skip a malformed row instead of crashing the totals
      }

      for (final item in items) {
        if (item is! Map) continue;
        final type = (item['type'] ?? '').toString();
        final pureWt = (item['pureWt'] as num?)?.toDouble() ?? 0;
        if (stock.containsKey(type)) {
          stock[type] = stock[type]! + (sign * pureWt);
        }
      }
    }

    return stock;
  }
}
