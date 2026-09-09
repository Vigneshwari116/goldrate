import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../logic/rate_rows.dart';
import '../util/api_row_keys.dart';

class ApiClient {
  ApiClient._();

  static const Duration requestTimeout = Duration(seconds: 15);

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.baseUrl}$path')
        .replace(queryParameters: query);
  }

  static Future<http.Response> _request(Future<http.Response> call) async {
    try {
      return await call.timeout(requestTimeout);
    } on TimeoutException {
      throw Exception(
        'Cannot reach server at ${ApiConfig.baseUrl}. '
        'Check Wi‑Fi/mobile data and try again.',
      );
    }
  }

  static Future<http.Response> _get(String path, [Map<String, String>? query]) =>
      _request(http.get(_uri(path, query)));

  static Future<http.Response> _post(String path, {Object? body}) =>
      _request(http.post(_uri(path), headers: _jsonHeaders, body: body));

  static Future<http.Response> _put(String path, {Object? body}) =>
      _request(http.put(_uri(path), headers: _jsonHeaders, body: body));

  static Future<http.Response> _delete(String path) =>
      _request(http.delete(_uri(path)));

  /// Quick connectivity probe used during app bootstrap.
  static Future<bool> checkHealth() async {
    try {
      final res = await _get('/health');
      if (res.statusCode != 200) return false;
      final body = _parseBody(res);
      return body is Map && body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  static dynamic _parseBody(http.Response res) {
    if (res.body.isEmpty) return null;
    final trimmed = res.body.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html') ||
        trimmed.startsWith('<HTML')) {
      throw Exception(
        'Server returned an HTML error page (${res.statusCode}) instead of JSON. '
        'The API route may be missing on the server — redeploy the latest '
        'server/index.js (including /api/admin/clear-transactions).',
      );
    }
    try {
      return jsonDecode(res.body);
    } on FormatException catch (e) {
      throw Exception(
        'Invalid server response (${res.statusCode}): ${e.message}',
      );
    }
  }

  static Future<Map<String, dynamic>> _decodeObject(http.Response res) async {
    final body = _parseBody(res);
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? (body['error'] ?? res.body) : res.body);
    }
    if (body == null) return {};
    return Map<String, dynamic>.from(body as Map);
  }

  static Future<List<Map<String, dynamic>>> _decodeList(http.Response res) async {
    final body = _parseBody(res);
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? (body['error'] ?? res.body) : res.body);
    }
    if (body == null) return [];
    return normalizeApiList(
      List<Map<String, dynamic>>.from(
        (body as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
    );
  }

  static Future<List<String>> _decodeStringList(http.Response res) async {
    final body = _parseBody(res);
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? (body['error'] ?? res.body) : res.body);
    }
    return List<String>.from(body as List);
  }

  // ---------- Auth ----------
  static Future<bool> checkLogin(String username, String password) async {
    final res = await _post(
      '/auth/login',
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = await _decodeObject(res);
    return data['success'] == true;
  }

  // ---------- Rates ----------
  static Future<List<Map<String, dynamic>>> getRates() async {
    final res = await _get('/rates');
    return RateRows.canonical(await _decodeList(res));
  }

  static Future<void> ensureDefaultRates() async {
    // Read first — never block the UI on a missing seed POST route (404).
    var rows = await getRates();
    if (rows.length >= RateRows.defaultRateNames.length) return;

    for (final path in ['/rates/ensure-defaults', '/admin/seed-rates']) {
      try {
        final res = await _post(path);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          rows = await getRates();
          if (rows.length >= RateRows.defaultRateNames.length) return;
        }
      } catch (_) {
        // Older API builds may not have the seed route yet.
      }
    }

    // Final read — updated GET /rates auto-seeds and dedupes when empty.
    try {
      await getRates();
    } catch (_) {
      // Caller shows blank template rows when the server is unreachable.
    }
  }

  static Future<Map<String, double>> getRatesMap() async {
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

  static Future<int> updateRate(
    int id,
    String rateName,
    String value,
    String date,
    String time,
  ) async {
    final res = await _put(
      '/rates/$id',
      body: jsonEncode({
        'rateName': rateName,
        'rateValue': value,
        'date': date,
        'time': time,
      }),
    );
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<Map<String, dynamic>> getUpdateStats() async {
    final res = await _get('/rates/stats');
    return _decodeObject(res);
  }

  static Future<List<Map<String, dynamic>>> getRateHistory() async {
    final res = await _get('/rates/history');
    return _decodeList(res);
  }

  // ---------- Customers ----------
  static Future<List<Map<String, dynamic>>> getCustomers() async {
    final res = await _get('/customers');
    return _decodeList(res);
  }

  static Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final res = await _post('/customers', body: jsonEncode(customer));
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteCustomer(int id) async {
    final res = await _delete('/customers/$id');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<int> deleteCustomersByName(String name) async {
    final encoded = Uri.encodeComponent(name.trim());
    final res = await _delete('/customers/by-name/$encoded');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Suppliers ----------
  static Future<List<Map<String, dynamic>>> getSuppliers() async {
    final res = await _get('/suppliers');
    return _decodeList(res);
  }

  static Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final res = await _post('/suppliers', body: jsonEncode(supplier));
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteSupplier(int id) async {
    final res = await _delete('/suppliers/$id');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<int> deleteSuppliersByName(String name) async {
    final encoded = Uri.encodeComponent(name.trim());
    final res = await _delete('/suppliers/by-name/$encoded');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<bool> partyHasLinkedTransactions(
    String name, {
    required bool isCustomer,
  }) async {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final txns = await getAllTransactions();
    for (final row in txns) {
      final party = (row['partyName'] ?? '').toString().trim().toLowerCase();
      if (party == lower) return true;
    }

    final vouchers = await getVouchers();
    for (final row in vouchers) {
      final party = (row['partyName'] ?? '').toString().trim().toLowerCase();
      if (party == lower) return true;
    }

    final ledger = isCustomer ? await getCustomers() : await getSuppliers();
    for (final row in ledger) {
      final rowName = (row['name'] ?? '').toString().trim().toLowerCase();
      final billRef = (row['billRef'] ?? '').toString().trim();
      if (rowName == lower && billRef.isNotEmpty) return true;
    }

    return false;
  }

  static Future<int> deleteLedgerByBillRef(
    String billRef, {
    required bool isCustomer,
  }) async {
    final table = isCustomer ? 'customers' : 'suppliers';
    final encoded = Uri.encodeComponent(billRef.trim());
    final res = await _delete('/$table/by-bill-ref/$encoded');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Opening weight ----------
  static Future<Map<String, dynamic>?> getOpeningWeight() async {
    final res = await _get('/opening-weight');
    if (res.body == 'null' || res.body.isEmpty) return null;
    final body = jsonDecode(res.body);
    if (body == null) return null;
    return normalizeApiRow(Map<String, dynamic>.from(body as Map));
  }

  static Future<int> insertOpeningWeight(Map<String, dynamic> weight) async {
    final res = await _post('/opening-weight', body: jsonEncode(weight));
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  // ---------- Transactions ----------
  static Future<int> getNextBillNo(String transactionType) async {
    final res = await _get('/transactions/next-bill-no', {'type': transactionType});
    final data = await _decodeObject(res);
    return data['billNo'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final res = await _get('/transactions');
    return _decodeList(res);
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
    String transactionType,
  ) async {
    final res = await _get('/transactions', {'type': transactionType});
    return _decodeList(res);
  }

  static Future<List<Map<String, dynamic>>> getTransactionsByDate(
    String date,
  ) async {
    final res = await _get('/transactions', {'date': date});
    return _decodeList(res);
  }

  static Future<int> insertTransaction(Map<String, dynamic> transaction) async {
    final res = await _post('/transactions', body: jsonEncode(transaction));
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteTransaction(int id) async {
    final res = await _delete('/transactions/$id');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Party ledger ----------
  static Future<List<String>> getDistinctPartyNames({
    required bool isCustomer,
  }) async {
    final path = isCustomer ? '/customers/names' : '/suppliers/names';
    final res = await _get(path);
    return _decodeStringList(res);
  }

  static Future<String> getPartyPhone(
    String name, {
    required bool isCustomer,
  }) async {
    final res = await _get('/party/phone', {
      'name': name.trim(),
      'isCustomer': isCustomer.toString(),
    });
    final data = await _decodeObject(res);
    return (data['phone'] ?? '').toString();
  }

  static Future<Map<String, double>> getPartyOutstanding(
    String name, {
    required bool isCustomer,
  }) async {
    final encoded = Uri.encodeComponent(name);
    final path = isCustomer
        ? '/customers/$encoded/outstanding'
        : '/suppliers/$encoded/outstanding';
    final res = await _get(path);
    final data = await _decodeObject(res);
    return {
      'rupees': (data['rupees'] as num?)?.toDouble() ?? 0,
      'grams': (data['grams'] as num?)?.toDouble() ?? 0,
      'crRupees': (data['crRupees'] as num?)?.toDouble() ?? 0,
      'drRupees': (data['drRupees'] as num?)?.toDouble() ?? 0,
      'crGrams': (data['crGrams'] as num?)?.toDouble() ?? 0,
      'drGrams': (data['drGrams'] as num?)?.toDouble() ?? 0,
    };
  }

  static Future<void> ensureParty(
    String name, {
    required bool isCustomer,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final names = await getDistinctPartyNames(isCustomer: isCustomer);
    if (names.contains(trimmed)) return;

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

  // ---------- Stock ----------
  static Future<Map<String, double>> getCurrentStock() async {
    final res = await _get('/stock/current');
    final data = await _decodeObject(res);
    return {
      'GWT': (data['GWT'] as num?)?.toDouble() ?? 0,
      'FWT': (data['FWT'] as num?)?.toDouble() ?? 0,
      'KWT': (data['KWT'] as num?)?.toDouble() ?? 0,
      'SWT': (data['SWT'] as num?)?.toDouble() ?? 0,
    };
  }

  // ---------- Vouchers ----------
  static Future<int> getNextVoucherNo(String voucherType) async {
    final res = await _get('/vouchers/next-no', {'type': voucherType});
    final data = await _decodeObject(res);
    return data['voucherNo'] as int;
  }

  static Future<List<Map<String, dynamic>>> getVouchers({
    String? voucherType,
  }) async {
    final res = voucherType == null
        ? await _get('/vouchers')
        : await _get('/vouchers', {'type': voucherType});
    return _decodeList(res);
  }

  static Future<int> insertVoucher(Map<String, dynamic> voucher) async {
    final res = await _post('/vouchers', body: jsonEncode(voucher));
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteVoucher(int id) async {
    final res = await _delete('/vouchers/$id');
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<void> resetAllBusinessData() async {
    final res = await _post('/admin/reset');
    await _decodeObject(res);
  }

  static Future<void> clearSalesPurchaseAndRecords() async {
    final res = await _post('/admin/clear-transactions');
    await _decodeObject(res);
    await _clearTransactionLedgerRows();
  }

  /// Removes SAL/PUR/RECEIPT/PAYMENT ledger rows so merged reads stay empty
  /// after reset (covers servers not yet redeployed with ledger deletes).
  static Future<void> _clearTransactionLedgerRows() async {
    final customers = await getCustomers();
    for (final row in customers) {
      final ref = (row['billRef'] ?? '').toString().toUpperCase();
      if (ref.startsWith('SAL-') || ref.startsWith('RECEIPT-')) {
        final id = row['id'];
        if (id != null) await deleteCustomer(int.parse(id.toString()));
      }
    }
    final suppliers = await getSuppliers();
    for (final row in suppliers) {
      final ref = (row['billRef'] ?? '').toString().toUpperCase();
      if (ref.startsWith('PUR-') || ref.startsWith('PAYMENT-')) {
        final id = row['id'];
        if (id != null) await deleteSupplier(int.parse(id.toString()));
      }
    }
  }
}
