import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiClient {
  ApiClient._();

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
  }

  static Future<Map<String, dynamic>> _decode(http.Response res) async {
    final body = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? (body['error'] ?? res.body) : res.body);
    }
    return body is Map<String, dynamic> ? body : {'data': body};
  }

  static Future<List<Map<String, dynamic>>> _decodeList(http.Response res) async {
    final body = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? (body['error'] ?? res.body) : res.body);
    }
    return List<Map<String, dynamic>>.from(
      (body as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  // ---------- Auth ----------
  static Future<bool> checkLogin(String username, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = await _decode(res);
    return data['success'] == true;
  }

  // ---------- Customers ----------
  static Future<List<Map<String, dynamic>>> getCustomers() async {
    final res = await http.get(_uri('/customers'));
    return _decodeList(res);
  }

  static Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final res = await http.post(
      _uri('/customers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(customer),
    );
    final data = await _decode(res);
    return data['id'] as int;
  }

  static Future<int> deleteCustomer(int id) async {
    final res = await http.delete(_uri('/customers/$id'));
    final data = await _decode(res);
    return data['rowsAffected'] as int;
  }
}
