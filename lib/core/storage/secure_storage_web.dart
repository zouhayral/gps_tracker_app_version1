import 'package:my_app_gps/core/storage/secure_storage_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WASM-safe secure storage for web using SharedPreferences
/// Note: This stores data in browser localStorage (not encrypted)
/// For production, consider using IndexedDB with encryption or server-side sessions
class SecureStorageWeb implements SecureStorageInterface {
  static const _prefix = 'secure_';

  @override
  Future<String?> read({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<void> delete({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  @override
  Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

SecureStorageInterface getSecureStorage() => SecureStorageWeb();
