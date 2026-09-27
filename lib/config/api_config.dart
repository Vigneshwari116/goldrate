/// Point this at your Hostinger VPS API.
class ApiConfig {
  ApiConfig._();

  /// Production API (PostgreSQL on VPS).
  static const String baseUrl = 'https://gold.winagrum.tech/api';

  /// When true, each operation tries the remote API first and falls back to
  /// local SQLite / web storage if the server is unreachable.
  static const bool useRemoteApi = true;
}

