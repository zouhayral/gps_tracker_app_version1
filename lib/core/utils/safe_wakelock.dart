import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Safe wakelock wrapper with lifecycle-aware enable/disable
///
/// **Purpose**: Prevent NoActivityException from wakelock_plus by checking
/// app lifecycle state before enabling/disabling wakelock.
///
/// **Usage**:
/// ```dart
/// await SafeWakelock.enable();  // Enable when app is in foreground
/// await SafeWakelock.disable(); // Disable safely
/// ```
///
/// **Requirements**:
/// - Add `wakelock_plus: ^1.0.0` to pubspec.yaml dependencies
/// - Uncomment wakelock_plus import below
/// - Uncomment actual implementation in enable/disable methods
///
/// **Current Status**: Stub implementation (no-op until wakelock_plus added)
class SafeWakelock {
  static bool _enabled = false;

  /// Enable wakelock if app is in foreground
  ///
  /// Checks lifecycle state before enabling to prevent NoActivityException.
  /// Safe to call from any context - fails gracefully if not ready.
  static Future<void> enable() async {
    try {
      final lifecycle = WidgetsBinding.instance.lifecycleState;

      if (lifecycle == AppLifecycleState.resumed) {
        // TODO: Uncomment when wakelock_plus is added to dependencies
        // await WakelockPlus.enable();
        _enabled = true;

        if (kDebugMode) {
          debugPrint('[SafeWakelock] ✅ Enabled (foreground)');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[SafeWakelock] ⚠️ Skipped – App not in foreground (state: $lifecycle)',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeWakelock] ❌ Error enabling wakelock: $e');
      }
    }
  }

  /// Disable wakelock safely
  ///
  /// Only disables if wakelock was previously enabled.
  /// Safe to call multiple times.
  static Future<void> disable() async {
    try {
      if (_enabled) {
        // TODO: Uncomment when wakelock_plus is added to dependencies
        // await WakelockPlus.disable();
        _enabled = false;

        if (kDebugMode) {
          debugPrint('[SafeWakelock] 🔒 Disabled');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeWakelock] ❌ Error disabling wakelock: $e');
      }
    }
  }

  /// Check if wakelock is currently enabled
  static bool get isEnabled => _enabled;

  /// Toggle wakelock based on parameter
  static Future<void> toggle({required bool enable}) async {
    if (enable) {
      await SafeWakelock.enable();
    } else {
      await SafeWakelock.disable();
    }
  }
}

/// Instructions to activate full wakelock support:
///
/// 1. Add to pubspec.yaml dependencies:
///    ```yaml
///    wakelock_plus: ^1.0.0
///    ```
///
/// 2. Run: flutter pub get
///
/// 3. Uncomment this import at top of file:
///    ```dart
///    // import 'package:wakelock_plus/wakelock_plus.dart';
///    ```
///
/// 4. Uncomment WakelockPlus.enable() and disable() calls in methods above
///
/// 5. Use in your code:
///    ```dart
///    // Keep screen on during prefetch
///    await SafeWakelock.enable();
///    await prefetchOrchestrator.start();
///    await SafeWakelock.disable();
///    ```
