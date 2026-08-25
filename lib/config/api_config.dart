/// Point this at your Hostinger VPS API.
class ApiConfig {
  ApiConfig._();

  /// Your VPS IP + API port.
  /// Change to https://yourdomain.com/api when you add SSL.
  static const String baseUrl = 'http://187.127.180.135:3002/api';

  /// Set true to use VPS PostgreSQL via API instead of local SQLite.
  static const bool useRemoteApi = true;
}

