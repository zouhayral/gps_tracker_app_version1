import 'package:shared_preferences/shared_preferences.dart';

/// Simple holder to synchronously expose a SharedPreferences instance
/// for places where async initialization isn't convenient (e.g. providers).
///
/// Production code should override the provider in main.dart; tests can
/// call SharedPrefsHolder.set(...) during setup to avoid UnimplementedError.
class SharedPrefsHolder {
  static late SharedPreferences _instance;
  static bool _initialized = false;

  static set instance(SharedPreferences prefs) {
    _instance = prefs;
    _initialized = true;
  }
  static SharedPreferences get instance => _instance;
  static bool get isInitialized => _initialized;
}
