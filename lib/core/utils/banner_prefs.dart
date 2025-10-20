import 'package:shared_preferences/shared_preferences.dart';

/// Session-scoped preferences for the bottom notification banner.
///
/// The banner should remain hidden after dismissal until the app restarts.
/// We implement this by storing a single boolean key that is cleared on app
/// startup via [resetOnAppRestart()].
class BannerPrefs {
  static const String _dismissedKey = 'banner_dismissed';

  /// Returns true if the banner has been dismissed for the current session.
  static Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissedKey) ?? false;
  }

  /// Mark the banner as dismissed for the current session.
  static Future<void> setDismissed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, value);
  }

  /// Clears the dismissed flag. Call once on app startup to make the banner
  /// visible again in the new session.
  static Future<void> resetOnAppRestart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedKey);
  }
}
