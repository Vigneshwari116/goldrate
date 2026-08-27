import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../config/api_config.dart';

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
    final path = await _resolveDatabasePath();

    return await openDatabase(
      path,
      version: 11,
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
        time TEXT,
        oldGrams TEXT,
        oldRupees TEXT,
        newGrams TEXT,
        newRupees TEXT,
        cashToGold TEXT,
        goldRateUsed TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE vouchers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucherType TEXT NOT NULL,
        voucherNo INTEGER NOT NULL,
        partyName TEXT,
        isCustomer INTEGER NOT NULL,
        paymentMode TEXT,
        amount TEXT,
        amountUnit TEXT,
        cashToGold TEXT,
        goldRateUsed TEXT,
        oldGrams TEXT,
        oldRupees TEXT,
        newGrams TEXT,
        newRupees TEXT,
        narration TEXT,
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
    if (oldVersion < 11) {
      await db.execute('ALTER TABLE transactions ADD COLUMN oldGrams TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN oldRupees TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN newGrams TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN newRupees TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN cashToGold TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN goldRateUsed TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS vouchers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucherType TEXT NOT NULL,
          voucherNo INTEGER NOT NULL,
          partyName TEXT,
          isCustomer INTEGER NOT NULL,
          paymentMode TEXT,
          amount TEXT,
          amountUnit TEXT,
          cashToGold TEXT,
          goldRateUsed TEXT,
          oldGrams TEXT,
          oldRupees TEXT,
          newGrams TEXT,
          newRupees TEXT,
          narration TEXT,
          date TEXT,
          time TEXT
        )
      ''');
    }
  }

  Future<bool> checkLogin(String username, String password) async {
    if (ApiConfig.useRemoteApi) {
      return ApiClient.checkLogin(username, password);
    }
    final db = await database;

    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );

    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getRates() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getRates();
    final db = await database;
    return await db.query('rates');
  }

  /// Rates keyed by rateName (e.g. 'G.P RATE' -> 15100), parsed to double.
  /// A rate that hasn't been set yet (blank) is simply left out of the map.
  Future<Map<String, double>> getRatesMap() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getRatesMap();
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
    if (ApiConfig.useRemoteApi) {
      return ApiClient.updateRate(id, rateName, value, date, time);
    }
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
    if (ApiConfig.useRemoteApi) return ApiClient.getUpdateStats();
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
    if (ApiConfig.useRemoteApi) return ApiClient.getRateHistory();
    final db = await database;
    return await db.query('rate_history', orderBy: 'id DESC');
  }


  /// On desktop, sqflite's default path sits under the app install folder
  /// (e.g. C:\Program Files\...), which is read-only on Windows. Store the
  /// database in the per-user application support directory instead.
  Future<String> _resolveDatabasePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final supportDir = await getApplicationSupportDirectory();
      final dbDir = Directory(join(supportDir.path, 'databases'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final newPath = join(dbDir.path, 'jewellery.db');
      final legacyPath = join(await getDatabasesPath(), 'jewellery.db');
      final legacyFile = File(legacyPath);
      final newFile = File(newPath);
      if (await legacyFile.exists() && !await newFile.exists()) {
        await legacyFile.copy(newPath);
      }
      return newPath;
    }

    return join(await getDatabasesPath(), 'jewellery.db');
  }

  Future<String> getDatabasePath() async {
    if (ApiConfig.useRemoteApi) {
      return 'remote:${ApiConfig.baseUrl}';
    }
    return _resolveDatabasePath();
  }

  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    if (ApiConfig.useRemoteApi) return ApiClient.insertCustomer(customer);
    final db = await database;
    return await db.insert('customers', customer);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getCustomers();
    final db = await database;
    return await db.query('customers', orderBy: 'id DESC');
  }


  Future<int> deleteCustomer(int id) async {
    if (ApiConfig.useRemoteApi) return ApiClient.deleteCustomer(id);
    final db = await database;
    return await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    if (ApiConfig.useRemoteApi) return ApiClient.insertSupplier(supplier);
    final db = await database;
    return await db.insert('suppliers', supplier);
  }

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getSuppliers();
    final db = await database;
    return await db.query('suppliers', orderBy: 'id DESC');
  }

  Future<int> deleteSupplier(int id) async {
    if (ApiConfig.useRemoteApi) return ApiClient.deleteSupplier(id);
    final db = await database;
    return await db.delete(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getOpeningWeight() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getOpeningWeight();
    final db = await database;
    final result = await db.query('opening_weight', limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> insertOpeningWeight(Map<String, dynamic> weight) async {
    if (ApiConfig.useRemoteApi) return ApiClient.insertOpeningWeight(weight);
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
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getNextBillNo(transactionType);
    }
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(billNo) as maxBill FROM transactions WHERE transactionType = ?',
      [transactionType],
    );
    final maxBill = result.isNotEmpty ? result.first['maxBill'] as int? : null;
    return (maxBill ?? 0) + 1;
  }

  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    if (ApiConfig.useRemoteApi) return ApiClient.getAllTransactions();
    final db = await database;
    return await db.query('transactions', orderBy: 'id DESC');
  }

  Future<int> insertTransaction(Map<String, dynamic> transaction) async {
    if (ApiConfig.useRemoteApi) return ApiClient.insertTransaction(transaction);
    final db = await database;
    return await db.insert('transactions', transaction);
  }

  Future<List<Map<String, dynamic>>> getTransactions(
      String transactionType) async {
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getTransactions(transactionType);
    }
    final db = await database;
    return await db.query(
      'transactions',
      where: 'transactionType = ?',
      whereArgs: [transactionType],
      orderBy: 'id DESC',
    );
  }

  Future<int> deleteTransaction(int id) async {
    if (ApiConfig.useRemoteApi) return ApiClient.deleteTransaction(id);
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
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getDistinctPartyNames(isCustomer: isCustomer);
    }
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

  Future<String> getPartyPhone(
    String name, {
    required bool isCustomer,
  }) async {
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getPartyPhone(name, isCustomer: isCustomer);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final db = await database;
    final table = isCustomer ? 'customers' : 'suppliers';
    final rows = await db.query(
      table,
      columns: ['mobile'],
      where: 'name = ?',
      whereArgs: [trimmed],
      orderBy: 'id DESC',
    );
    for (final row in rows) {
      final mobile = (row['mobile'] ?? '').toString().trim();
      if (mobile.isNotEmpty) return mobile;
    }
    return '';
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
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getPartyOutstanding(name, isCustomer: isCustomer);
    }
    final db = await database;
    final table = isCustomer ? 'customers' : 'suppliers';
    final rows = await db.query(table, where: 'name = ?', whereArgs: [name]);

    double rupees = 0;
    double grams = 0;
    double crRupees = 0;
    double drRupees = 0;
    double crGrams = 0;
    double drGrams = 0;

    for (final row in rows) {
      final cr = double.tryParse((row['cr'] ?? '').toString()) ?? 0;
      final dr = double.tryParse((row['dr'] ?? '').toString()) ?? 0;
      final unit = (row['balanceUnit'] ?? 'RUPEES').toString();
      final net = dr - cr;
      if (unit == 'GRAMS') {
        grams += net;
        crGrams += cr;
        drGrams += dr;
      } else {
        rupees += net;
        crRupees += cr;
        drRupees += dr;
      }
    }

    return {
      'rupees': rupees,
      'grams': grams,
      'crRupees': crRupees,
      'drRupees': drRupees,
      'crGrams': crGrams,
      'drGrams': drGrams,
    };
  }

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
    if (ApiConfig.useRemoteApi) return ApiClient.getTransactionsByDate(date);
    final db = await database;
    return await db.query(
      'transactions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
    );
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
    if (ApiConfig.useRemoteApi) return ApiClient.getCurrentStock();
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

  // ---------- Receipt / payment vouchers ----------

  Future<int> getNextVoucherNo(String voucherType) async {
    if (ApiConfig.useRemoteApi) return ApiClient.getNextVoucherNo(voucherType);
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(voucherNo) as maxNo FROM vouchers WHERE voucherType = ?',
      [voucherType],
    );
    final maxNo = result.isNotEmpty ? result.first['maxNo'] as int? : null;
    return (maxNo ?? 0) + 1;
  }

  Future<int> insertVoucher(Map<String, dynamic> voucher) async {
    if (ApiConfig.useRemoteApi) return ApiClient.insertVoucher(voucher);
    final db = await database;
    return await db.insert('vouchers', voucher);
  }

  Future<List<Map<String, dynamic>>> getVouchers({String? voucherType}) async {
    if (ApiConfig.useRemoteApi) {
      return ApiClient.getVouchers(voucherType: voucherType);
    }
    final db = await database;
    if (voucherType == null) {
      return await db.query('vouchers', orderBy: 'id DESC');
    }
    return await db.query(
      'vouchers',
      where: 'voucherType = ?',
      whereArgs: [voucherType],
      orderBy: 'id DESC',
    );
  }

  Future<int> deleteVoucher(int id) async {
    if (ApiConfig.useRemoteApi) return ApiClient.deleteVoucher(id);
    final db = await database;
    return await db.delete('vouchers', where: 'id = ?', whereArgs: [id]);
  }

  /// Creates a name-only master row so a bill can still show a running
  /// balance the next time that name is typed.
  Future<void> ensureParty(
    String name, {
    required bool isCustomer,
  }) async {
    if (ApiConfig.useRemoteApi) {
      return ApiClient.ensureParty(name, isCustomer: isCustomer);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await database;
    final table = isCustomer ? 'customers' : 'suppliers';
    final rows = await db.query(table, where: 'name = ?', whereArgs: [trimmed]);
    if (rows.isNotEmpty) return;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time =
        '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';
    if (isCustomer) {
      await insertCustomer({
        'name': trimmed,
        'mobile': '',
        'city': '',
        'cr': '0',
        'dr': '0',
        'drGross': '',
        'drNet': '',
        'narration': 'Opened from bill (name only)',
        'balanceUnit': 'GRAMS',
        'billRef': '',
        'date': date,
        'time': time,
      });
    } else {
      await insertSupplier({
        'name': trimmed,
        'mobile': '',
        'city': '',
        'cr': '0',
        'dr': '0',
        'gross': '',
        'net': '',
        'narration': 'Opened from bill (name only)',
        'balanceUnit': 'GRAMS',
        'billRef': '',
        'date': date,
        'time': time,
      });
    }
  }

  /// Deletes all sales bills, purchase bills, and receipt/payment records.
  /// Keeps customers, suppliers, rates, and opening weight.
  Future<void> clearSalesPurchaseAndRecords() async {
    if (ApiConfig.useRemoteApi) {
      await ApiClient.clearSalesPurchaseAndRecords();
      return;
    }
    final db = await database;
    await db.delete('transactions');
    await db.delete('vouchers');
  }

  /// Wipes all business data (masters, bills, rates, opening weight) but
  /// keeps the login user so the app is not locked out.
  Future<void> resetAllBusinessData() async {
    if (ApiConfig.useRemoteApi) {
      await ApiClient.resetAllBusinessData();
      return;
    }
    final db = await database;
    await db.delete('transactions');
    await db.delete('vouchers');
    await db.delete('opening_weight');
    await db.delete('rate_history');
    await db.delete('rates');
    await db.delete('suppliers');
    await db.delete('customers');
    await db.insert('rates', {'rateName': 'G.P RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'F.T RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'KACHA RATE', 'rateValue': ''});
    await db.insert('rates', {'rateName': 'S RATE', 'rateValue': ''});
    await db.delete(
      'sqlite_sequence',
      where: 'name IN (?, ?, ?, ?, ?, ?, ?)',
      whereArgs: [
        'transactions',
        'vouchers',
        'opening_weight',
        'rate_history',
        'rates',
        'suppliers',
        'customers',
      ],
    );
  }
}
