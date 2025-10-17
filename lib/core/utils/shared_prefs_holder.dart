import 'package:shared_preferences/shared_preferences.dart';

/// Simple holder to synchronously expose a SharedPreferences instance
/// for places where async initialization isn't convenient (e.g. providers).
///
/// Production code should override the provider in main.dart; tests can
/// call SharedPrefsHolder.set(...) during setup to avoid UnimplementedError.
class SharedPrefsHolder {
  static SharedPreferences? _instance;

  static void set(SharedPreferences prefs) {
    _instance = prefs;
  }

  static SharedPreferences? get instance => _instance;
}
