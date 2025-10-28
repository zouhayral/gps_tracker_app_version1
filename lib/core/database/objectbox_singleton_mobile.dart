import 'package:flutter/foundation.dart';
import 'package:my_app_gps/objectbox.g.dart';

/// Mobile-only ObjectBox store singleton
class ObjectBoxSingleton {
  static Store? _store;
  static bool _isInitializing = false;

  ObjectBoxSingleton._();

  static Future<Store> getStore() async {
    if (_store != null) return _store!;
    if (_isInitializing) {
      if (kDebugMode) {
        debugPrint('[ObjectBox] ⏳ Store initialization in progress, waiting...');
      }
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_store != null) return _store!;
    }

    _isInitializing = true;
    try {
      if (kDebugMode) debugPrint('[ObjectBox] 🔄 Initializing Store...');
      _store = await openStore();
      if (kDebugMode) debugPrint('[ObjectBox] ✅ Store initialized successfully');
      return _store!;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ObjectBox] ❌ Failed to initialize Store: $e');
        debugPrint(st.toString());
      }
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  static bool get isInitialized => _store != null;

  static Future<void> closeStore() async {
    if (_store == null) return;
    try {
      _store!.close();
      _store = null;
      if (kDebugMode) debugPrint('[ObjectBox] ✅ Store closed successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[ObjectBox] ⚠️ Error closing Store: $e');
      _store = null;
    }
  }

  @visibleForTesting
  static void reset() {
    _store = null;
    _isInitializing = false;
    if (kDebugMode) debugPrint('[ObjectBox] 🔄 Singleton reset (test mode)');
  }
}
