import 'dart:async';

import 'package:flutter/foundation.dart';

/// Throttled ValueNotifier that only propagates updates after a minimum interval
/// Reduces unnecessary rebuilds when updates arrive faster than the frame rate
class ThrottledValueNotifier<T> extends ValueNotifier<T> {
  ThrottledValueNotifier(
    super.value, {
    this.throttleDuration = const Duration(milliseconds: 50),
    this.enabled = true,
  });

  final Duration throttleDuration;
  bool enabled;

  Timer? _throttleTimer;
  T? _pendingValue;
  bool _hasUpdate = false;

  @override
  set value(T newValue) {
    // If throttling disabled, update immediately
    if (!enabled) {
      super.value = newValue;
      return;
    }

    // If identical value, skip
    if (newValue == value) {
      return;
    }

    // Store pending value
    _pendingValue = newValue;
    _hasUpdate = true;

    // If no timer active, start one
    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _throttleTimer = Timer(throttleDuration, _flushUpdate);
    }
  }

  void _flushUpdate() {
    if (_hasUpdate && _pendingValue != null) {
      super.value = _pendingValue as T;
      _hasUpdate = false;
      _pendingValue = null;
    }
  }

  /// Force immediate update, bypassing throttle
  void forceUpdate(T newValue) {
    _throttleTimer?.cancel();
    _hasUpdate = false;
    _pendingValue = null;
    super.value = newValue;
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }
}

/// Extension to convert regular ValueNotifier to throttled
extension ThrottledValueNotifierExtension<T> on ValueNotifier<T> {
  ThrottledValueNotifier<T> throttled({
    Duration throttleDuration = const Duration(milliseconds: 50),
  }) {
    return ThrottledValueNotifier<T>(
      value,
      throttleDuration: throttleDuration,
    );
  }
}
