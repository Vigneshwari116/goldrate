import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/app_page.dart';

/// Persists login session and last-viewed navigation page across restarts.
class SessionPrefs {
  SessionPrefs._();

  static const _loggedInKey = 'session_logged_in';
  static const _lastPageKey = 'session_last_page';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
    if (!value) {
      await prefs.remove(_lastPageKey);
    }
  }

  static Future<AppPage> getLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_lastPageKey);
    if (name == null) return AppPage.home;
    return AppPage.values.firstWhere(
      (p) => p.name == name,
      orElse: () => AppPage.home,
    );
  }

  static Future<void> setLastPage(AppPage page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPageKey, page.name);
  }
}
