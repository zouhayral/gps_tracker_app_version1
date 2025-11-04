import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';

/// Unified lifecycle manager for streams and subscriptions
/// 
/// **Purpose**: Track and manage all active streams, subscriptions, and timers
/// to prevent memory leaks and ensure proper cleanup on disposal.
/// 
/// **Usage**:
/// ```dart
/// final lifecycle = StreamLifecycleManager(name: 'MyRepository');
/// 
/// // Track subscriptions
/// lifecycle.track(myStream.listen(...));
/// 
/// // Track controllers
/// lifecycle.trackController(myStreamController);
/// 
/// // Track timers
/// lifecycle.trackTimer(myTimer);
/// 
/// // Cleanup all at once
/// lifecycle.disposeAll();
/// ```
class StreamLifecycleManager {
  static final _log = 'StreamLifecycle'.logger;
  
  final String name;
  final Set<StreamSubscription<dynamic>> _subscriptions = {};
  final Set<StreamController<dynamic>> _controllers = {};
  final Set<Timer> _timers = {};
  bool _disposed = false;

  StreamLifecycleManager({required this.name});

  /// Track a stream subscription for automatic cleanup
  StreamSubscription<T> track<T>(StreamSubscription<T> subscription) {
    if (_disposed) {
      _log.warning('[$name] ⚠️ Attempting to track subscription after disposal');
      return subscription;
    }
    _subscriptions.add(subscription);
    _log.debug('[$name] 📌 Tracked subscription (total: ${_subscriptions.length})');
    return subscription;
  }

  /// Track a stream controller for automatic cleanup
  StreamController<T> trackController<T>(StreamController<T> controller) {
    if (_disposed) {
      _log.warning('[$name] ⚠️ Attempting to track controller after disposal');
      return controller;
    }
    _controllers.add(controller);
    _log.debug('[$name] 📌 Tracked controller (total: ${_controllers.length})');
    return controller;
  }

  /// Track a timer for automatic cleanup
  Timer trackTimer(Timer timer) {
    if (_disposed) {
      _log.warning('[$name] ⚠️ Attempting to track timer after disposal');
      return timer;
    }
    _timers.add(timer);
    _log.debug('[$name] 📌 Tracked timer (total: ${_timers.length})');
    return timer;
  }

  /// Remove and cancel a specific subscription
  Future<void> untrack(StreamSubscription<dynamic> subscription) async {
    if (_subscriptions.remove(subscription)) {
      await subscription.cancel();
      _log.debug('[$name] ✅ Untracked and canceled subscription');
    }
  }

  /// Remove and close a specific controller
  Future<void> untrackController(StreamController<dynamic> controller) async {
    if (_controllers.remove(controller)) {
      await controller.close();
      _log.debug('[$name] ✅ Untracked and closed controller');
    }
  }

  /// Remove and cancel a specific timer
  void untrackTimer(Timer timer) {
    if (_timers.remove(timer)) {
      timer.cancel();
      _log.debug('[$name] ✅ Untracked and canceled timer');
    }
  }

  /// Get current tracking statistics
  Map<String, int> get stats => {
    'subscriptions': _subscriptions.length,
    'controllers': _controllers.length,
    'timers': _timers.length,
  };

  /// Check if all resources are cleaned up
  bool get isClean => 
      _subscriptions.isEmpty && 
      _controllers.isEmpty && 
      _timers.isEmpty;

  /// Dispose all tracked resources
  void disposeAll() {
    if (_disposed) {
      _log.debug('[$name] ⚠️ Double dispose prevented');
      return;
    }
    _disposed = true;

    final totalResources = _subscriptions.length + 
                          _controllers.length + 
                          _timers.length;

    if (totalResources == 0) {
      _log.debug('[$name] 🧹 No active streams to clean up (active: 0)');
      return;
    }

    _log.debug(
      '[$name] 🧹 Disposing $totalResources stream(s): '
      '${_subscriptions.length} subs, ${_controllers.length} controllers, '
      '${_timers.length} timers',
    );

    final sw = Stopwatch()..start();

    // Cancel all subscriptions (unawaited - dispose must be synchronous)
    for (final sub in _subscriptions) {
      try {
        unawaited(sub.cancel());
      } catch (e) {
        if (kDebugMode) {
          _log.warning('[$name] Error canceling subscription', error: e);
        }
      }
    }

    // Close all controllers (unawaited - dispose must be synchronous)
    for (final controller in _controllers) {
      try {
        // Don't await - controllers can have long-running listeners
        // and dispose() must complete synchronously
        unawaited(controller.close());
      } catch (e) {
        if (kDebugMode) {
          _log.warning('[$name] Error closing controller', error: e);
        }
      }
    }

    // Cancel all timers
    for (final timer in _timers) {
      try {
        timer.cancel();
      } catch (e) {
        if (kDebugMode) {
          _log.warning('[$name] Error canceling timer', error: e);
        }
      }
    }

    _subscriptions.clear();
    _controllers.clear();
    _timers.clear();

    sw.stop();
    
    // Verify complete cleanup with assertion
    assert(
      _subscriptions.isEmpty && _controllers.isEmpty && _timers.isEmpty,
      '[$name] Failed to clean up all resources',
    );
    
    _log.debug(
      '[$name] ✅ Lifecycle cleanup complete: 0 active subscriptions, 0 controllers, 0 timers '
      '(disposed in ${sw.elapsedMilliseconds}ms)',
    );
  }

  /// Log current status
  void logStatus() {
    if (_subscriptions.isEmpty && _controllers.isEmpty && _timers.isEmpty) {
      _log.debug('[$name] 🧹 No idle streams to clean up (active: 0)');
    } else {
      _log.debug(
        '[$name] 📊 Active resources: ${_subscriptions.length} subs, '
        '${_controllers.length} controllers, ${_timers.length} timers',
      );
    }
  }
}

/// Extension to make tracking more convenient
extension StreamSubscriptionTracking<T> on StreamSubscription<T> {
  StreamSubscription<T> trackIn(StreamLifecycleManager manager) {
    return manager.track(this);
  }
}

extension StreamControllerTracking<T> on StreamController<T> {
  StreamController<T> trackIn(StreamLifecycleManager manager) {
    return manager.trackController(this);
  }
}

extension TimerTracking on Timer {
  Timer trackIn(StreamLifecycleManager manager) {
    return manager.trackTimer(this);
  }
}
