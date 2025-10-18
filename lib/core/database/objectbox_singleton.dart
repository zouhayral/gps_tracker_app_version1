import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';

import 'package:my_app_gps/objectbox.g.dart';

/// Singleton ObjectBox Store manager
///
/// **Purpose**: Prevent "Cannot create multiple Store instances" runtime error
/// by ensuring only one Store instance exists throughout app lifetime.
///
/// **Problem**: Multiple `await openStore()` calls create duplicate Store instances,
/// causing ObjectBox to throw exceptions.
///
/// **Solution**: Single Store instance managed via singleton pattern.
///
/// **Usage**:
/// ```dart
/// // Instead of: final store = await openStore();
/// final store = await ObjectBoxSingleton.getStore();
/// ```
///
/// **Features**:
/// - Thread-safe singleton initialization
/// - Automatic store creation on first access
/// - Clean shutdown support
/// - Debug logging for lifecycle tracking
class ObjectBoxSingleton {
  static Store? _store;
  static bool _isInitializing = false;

  /// Private constructor to prevent instantiation
  ObjectBoxSingleton._();

  /// Get the singleton ObjectBox Store instance
  ///
  /// Creates store on first call, returns cached instance on subsequent calls.
  /// Thread-safe with initialization lock.
  ///
  /// **Returns**: ObjectBox Store instance
  ///
  /// **Throws**: ObjectBox initialization errors (e.g., filesystem issues)
  static Future<Store> getStore() async {
    // Fast path: Store already initialized
    if (_store != null) {
      return _store!;
    }

    // Prevent concurrent initialization
    if (_isInitializing) {
      if (kDebugMode) {
        debugPrint(
          '[ObjectBox] ⏳ Store initialization in progress, waiting...',
        );
      }

      // Wait for initialization to complete
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Check if store was initialized by another caller
      if (_store != null) {
        return _store!;
      }
    }

    // Initialize store
    _isInitializing = true;

    try {
      if (kDebugMode) {
        debugPrint('[ObjectBox] 🔄 Initializing Store...');
      }

      _store = await openStore();

      if (kDebugMode) {
        debugPrint('[ObjectBox] ✅ Store initialized successfully');
      }

      return _store!;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[ObjectBox] ❌ Failed to initialize Store: $e');
        debugPrint(stack.toString());
      }
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Check if store is currently initialized
  ///
  /// Useful for conditional logic that depends on database availability.
  static bool get isInitialized => _store != null;

  /// Close the ObjectBox Store and release resources
  ///
  /// Should be called during app shutdown or hot restart.
  /// After calling this, next `getStore()` will reinitialize.
  ///
  /// **Warning**: Only call this when you're sure no operations are in progress.
  static Future<void> closeStore() async {
    if (_store == null) {
      if (kDebugMode) {
        debugPrint('[ObjectBox] ℹ️ Store already closed or not initialized');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('[ObjectBox] 🔒 Closing Store...');
      }

      _store!.close();
      _store = null;

      if (kDebugMode) {
        debugPrint('[ObjectBox] ✅ Store closed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ObjectBox] ⚠️ Error closing Store: $e');
      }
      // Still null out the reference even if close failed
      _store = null;
    }
  }

  /// Reset singleton (for testing only)
  ///
  /// **Warning**: Only use in test teardown. Never call in production code.
  @visibleForTesting
  static void reset() {
    _store = null;
    _isInitializing = false;
    if (kDebugMode) {
      debugPrint('[ObjectBox] 🔄 Singleton reset (test mode)');
    }
  }
}
