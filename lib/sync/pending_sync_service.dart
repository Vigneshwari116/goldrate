import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../api/api_reachability.dart';
import '../database/database_helper.dart';

class PendingSyncEntry {
  PendingSyncEntry({
    required this.method,
    required this.path,
    this.bodyJson,
  });

  final String method;
  final String path;
  final String? bodyJson;

  Map<String, dynamic> toRow() => {
        'method': method,
        'path': path,
        'bodyJson': bodyJson,
        'createdAt': DateTime.now().toIso8601String(),
      };

  static PendingSyncEntry post(String path, Map<String, dynamic> body) =>
      PendingSyncEntry(
        method: 'POST',
        path: path,
        bodyJson: jsonEncode(body),
      );

  static PendingSyncEntry put(String path, Map<String, dynamic> body) =>
      PendingSyncEntry(
        method: 'PUT',
        path: path,
        bodyJson: jsonEncode(body),
      );

  static PendingSyncEntry delete(String path) =>
      PendingSyncEntry(method: 'DELETE', path: path);
}

/// Queues offline writes and replays them when the API is reachable again.
class PendingSyncService {
  PendingSyncService._();

  static final PendingSyncService instance = PendingSyncService._();

  bool _flushing = false;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<void> ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        bodyJson TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> enqueue(PendingSyncEntry entry) async {
    final db = await _db;
    await ensureTable(db);
    await db.insert('pending_sync', entry.toRow());
  }

  Future<int> pendingCount() async {
    final db = await _db;
    await ensureTable(db);
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) as c FROM pending_sync'),
    );
    return count ?? 0;
  }

  Future<void> flushPending() async {
    if (_flushing) return;
    if (!ApiReachability.instance.isOnline.value) return;
    _flushing = true;
    try {
      final db = await _db;
      await ensureTable(db);
      final rows = await db.query('pending_sync', orderBy: 'id ASC');
      for (final row in rows) {
        final id = row['id'] as int;
        final method = (row['method'] ?? '').toString();
        final path = (row['path'] ?? '').toString();
        final bodyJson = row['bodyJson'] as String?;
        try {
          await ApiClient.replayPending(
            method: method,
            path: path,
            bodyJson: bodyJson,
          );
          await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
        } catch (e) {
          if (ApiReachability.isNetworkFailure(e)) {
            ApiReachability.instance.markOffline();
            break;
          }
          // Drop malformed entries so one bad row does not block the queue.
          await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
