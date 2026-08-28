import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../util/api_row_keys.dart';

class ApiClient {
  ApiClient._();

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.baseUrl}$path')
        .replace(queryParameters: query);
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
    final res = await http.post(
      _uri('/auth/login'),
      headers: _jsonHeaders,
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = await _decodeObject(res);
    return data['success'] == true;
  }

  // ---------- Rates ----------
  static Future<List<Map<String, dynamic>>> getRates() async {
    final res = await http.get(_uri('/rates'));
    return _decodeList(res);
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
    final res = await http.put(
      _uri('/rates/$id'),
      headers: _jsonHeaders,
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
    final res = await http.get(_uri('/rates/stats'));
    return _decodeObject(res);
  }

  static Future<List<Map<String, dynamic>>> getRateHistory() async {
    final res = await http.get(_uri('/rates/history'));
    return _decodeList(res);
  }

  // ---------- Customers ----------
  static Future<List<Map<String, dynamic>>> getCustomers() async {
    final res = await http.get(_uri('/customers'));
    return _decodeList(res);
  }

  static Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final res = await http.post(
      _uri('/customers'),
      headers: _jsonHeaders,
      body: jsonEncode(customer),
    );
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteCustomer(int id) async {
    final res = await http.delete(_uri('/customers/$id'));
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Suppliers ----------
  static Future<List<Map<String, dynamic>>> getSuppliers() async {
    final res = await http.get(_uri('/suppliers'));
    return _decodeList(res);
  }

  static Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final res = await http.post(
      _uri('/suppliers'),
      headers: _jsonHeaders,
      body: jsonEncode(supplier),
    );
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteSupplier(int id) async {
    final res = await http.delete(_uri('/suppliers/$id'));
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Opening weight ----------
  static Future<Map<String, dynamic>?> getOpeningWeight() async {
    final res = await http.get(_uri('/opening-weight'));
    if (res.body == 'null' || res.body.isEmpty) return null;
    final body = jsonDecode(res.body);
    if (body == null) return null;
    return Map<String, dynamic>.from(body as Map);
  }

  static Future<int> insertOpeningWeight(Map<String, dynamic> weight) async {
    final res = await http.post(
      _uri('/opening-weight'),
      headers: _jsonHeaders,
      body: jsonEncode(weight),
    );
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  // ---------- Transactions ----------
  static Future<int> getNextBillNo(String transactionType) async {
    final res = await http.get(
      _uri('/transactions/next-bill-no', {'type': transactionType}),
    );
    final data = await _decodeObject(res);
    return data['billNo'] as int;
  }

  static Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final res = await http.get(_uri('/transactions'));
    return _decodeList(res);
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
    String transactionType,
  ) async {
    final res = await http.get(
      _uri('/transactions', {'type': transactionType}),
    );
    return _decodeList(res);
  }

  static Future<List<Map<String, dynamic>>> getTransactionsByDate(
    String date,
  ) async {
    final res = await http.get(_uri('/transactions', {'date': date}));
    return _decodeList(res);
  }

  static Future<int> insertTransaction(Map<String, dynamic> transaction) async {
    final res = await http.post(
      _uri('/transactions'),
      headers: _jsonHeaders,
      body: jsonEncode(transaction),
    );
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteTransaction(int id) async {
    final res = await http.delete(_uri('/transactions/$id'));
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  // ---------- Party ledger ----------
  static Future<List<String>> getDistinctPartyNames({
    required bool isCustomer,
  }) async {
    final path = isCustomer ? '/customers/names' : '/suppliers/names';
    final res = await http.get(_uri(path));
    return _decodeStringList(res);
  }

  static Future<String> getPartyPhone(
    String name, {
    required bool isCustomer,
  }) async {
    final res = await http.get(_uri('/party/phone', {
      'name': name.trim(),
      'isCustomer': isCustomer.toString(),
    }));
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
    final res = await http.get(_uri(path));
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
    final res = await http.get(_uri('/stock/current'));
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
    final res = await http.get(
      _uri('/vouchers/next-no', {'type': voucherType}),
    );
    final data = await _decodeObject(res);
    return data['voucherNo'] as int;
  }

  static Future<List<Map<String, dynamic>>> getVouchers({
    String? voucherType,
  }) async {
    final res = voucherType == null
        ? await http.get(_uri('/vouchers'))
        : await http.get(_uri('/vouchers', {'type': voucherType}));
    return _decodeList(res);
  }

  static Future<int> insertVoucher(Map<String, dynamic> voucher) async {
    final res = await http.post(
      _uri('/vouchers'),
      headers: _jsonHeaders,
      body: jsonEncode(voucher),
    );
    final data = await _decodeObject(res);
    return data['id'] as int;
  }

  static Future<int> deleteVoucher(int id) async {
    final res = await http.delete(_uri('/vouchers/$id'));
    final data = await _decodeObject(res);
    return data['rowsAffected'] as int? ?? 0;
  }

  static Future<void> resetAllBusinessData() async {
    final res = await http.post(_uri('/admin/reset'), headers: _jsonHeaders);
    await _decodeObject(res);
  }

  static Future<void> clearSalesPurchaseAndRecords() async {
    final res =
        await http.post(_uri('/admin/clear-transactions'), headers: _jsonHeaders);
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
