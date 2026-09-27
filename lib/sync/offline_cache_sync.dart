import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../api/api_reachability.dart';
import '../database/database_helper.dart';
import '../logic/rate_rows.dart';
import '../util/api_row_keys.dart';
import 'pending_sync_service.dart';

/// Downloads server data into the local SQLite cache while online so offline
/// mode has useful data.
class OfflineCacheSync {
  OfflineCacheSync._();

  static final OfflineCacheSync instance = OfflineCacheSync._();

  bool _running = false;

  Future<void> pullFromServerIfOnline() async {
    if (_running) return;
    if (!ApiReachability.instance.isOnline.value) return;
    _running = true;
    try {
      final healthy = await ApiReachability.instance.probeHealth();
      if (!healthy) return;
      await _pull();
      await PendingSyncService.instance.flushPending();
    } catch (_) {
      // Best-effort cache; offline fallback still works with partial data.
    } finally {
      _running = false;
    }
  }

  Future<void> _pull() async {
    final db = await DatabaseHelper.instance.database;

    final rates = RateRows.canonical(await ApiClient.getRates());
    await db.delete('rates');
    for (final row in rates) {
      await db.insert('rates', {
        'id': row['id'],
        'rateName': row['rateName'],
        'rateValue': row['rateValue'],
      });
    }

    final history = await ApiClient.getRateHistory();
    await db.delete('rate_history');
    for (final row in history) {
      await db.insert('rate_history', Map<String, Object?>.from(row));
    }

    try {
      final stats = await ApiClient.getUpdateStats();
      await db.insert(
        'rate_meta',
        {
          'id': 1,
          'lastDate': stats['lastDate'] ?? '',
          'lastTime': stats['lastTime'] ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}

    await _replaceTable(db, 'customers', await ApiClient.getCustomers());
    await _replaceTable(db, 'suppliers', await ApiClient.getSuppliers());

    final opening = await ApiClient.getOpeningWeight();
    await db.delete('opening_weight');
    if (opening != null) {
      await db.insert('opening_weight', Map<String, Object?>.from(opening));
    }

    final txns = await ApiClient.getAllTransactions();
    await db.delete('transactions');
    for (final row in txns) {
      await db.insert('transactions', Map<String, Object?>.from(row));
    }

    final vouchers = await ApiClient.getVouchers();
    await db.delete('vouchers');
    for (final row in vouchers) {
      await db.insert('vouchers', Map<String, Object?>.from(row));
    }

    final hsn = await ApiClient.getItemTypeHsnMap();
    for (final entry in hsn.entries) {
      await db.insert(
        'item_type_hsn',
        {'itemType': entry.key, 'hsnCode': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _replaceTable(
    Database db,
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    await db.delete(table);
    for (final row in normalizeApiList(rows)) {
      await db.insert(table, Map<String, Object?>.from(row));
    }
  }
}
