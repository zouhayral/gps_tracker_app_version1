import 'package:flutter/foundation.dart';

/// Web stub for ObjectBox singleton. Not usable on web.
class ObjectBoxSingleton {
  ObjectBoxSingleton._();

  static Future<dynamic> getStore() async {
    throw UnsupportedError('ObjectBox is not available on the web');
  }

  static bool get isInitialized => false;

  static Future<void> closeStore() async {
    if (kDebugMode) {
      debugPrint('[ObjectBox] closeStore() called on web stub');
    }
  }

  static void reset() {}
}
