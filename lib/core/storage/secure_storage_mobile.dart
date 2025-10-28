import 'package:my_app_gps/core/storage/secure_storage_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mobile secure storage using SharedPreferences
/// For production mobile apps, consider using flutter_secure_storage or encrypted_shared_preferences
class SecureStorageMobile implements SecureStorageInterface {
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

SecureStorageInterface getSecureStorage() => SecureStorageMobile();
